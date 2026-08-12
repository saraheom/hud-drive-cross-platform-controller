from __future__ import annotations

import sys

import asyncio
import platform
import queue
import threading
import time
import traceback
import tkinter as tk
from tkinter import ttk, messagebox

from bleak import BleakClient, BleakScanner


# PyInstaller/WinRT safeguard:
# Bleak loads several Windows Runtime projections dynamically when advertisements
# arrive. Explicit imports ensure one-file builds carry the modules.
if sys.platform == "win32":
    try:
        import winrt.windows.devices.bluetooth  # noqa: F401
        import winrt.windows.devices.bluetooth.advertisement  # noqa: F401
        import winrt.windows.devices.bluetooth.genericattributeprofile  # noqa: F401
        import winrt.windows.devices.enumeration  # noqa: F401
        import winrt.windows.foundation  # noqa: F401
        import winrt.windows.foundation.collections  # noqa: F401
        import winrt.windows.storage.streams  # noqa: F401
        WINRT_IMPORT_ERROR = None
    except Exception as _winrt_exc:
        WINRT_IMPORT_ERROR = repr(_winrt_exc)
else:
    WINRT_IMPORT_ERROR = None
import bleak

import protocol as p


class BleWorker:
    def __init__(self, events: queue.Queue):
        self.events = events
        self.loop = asyncio.new_event_loop()
        self.client = None
        self.devices = []
        self._loop_ready = threading.Event()
        self._scan_lock = threading.Lock()
        self._scanning = False
        self._disconnect_requested = False
        self._auto_keepalive_tasks = set()
        # HUD's Android transport serializes every packet/chunk. Never let
        # a keepalive interleave with a multi-chunk maneuver packet.
        self._tx_lock = asyncio.Lock()
        self._tx_sequence = 0
        self._route_sim_task = None
        self._ui_sequence_task = None
        threading.Thread(target=self._run, daemon=True, name="HUD-BLE-Asyncio").start()

    def _run(self):
        try:
            asyncio.set_event_loop(self.loop)
            self.events.put(("log", "BLE worker thread started."))
            self.events.put(("log", f"Python: {platform.python_version()} | Bleak: {getattr(bleak, '__version__', 'unknown')}"))
            self.events.put(("log", f"Windows: {platform.platform()}"))
            self._loop_ready.set()
            self.loop.run_forever()
        except Exception:
            self.events.put(("log", "FATAL BLE worker error:\n" + traceback.format_exc()))

    def submit(self, coro):
        if not self._loop_ready.wait(timeout=3.0):
            raise RuntimeError("BLE worker event loop did not start")
        return asyncio.run_coroutine_threadsafe(coro, self.loop)

    async def scan(self, timeout: float = 10.0):
        if self._scanning:
            self.events.put(("log", "Scan already in progress."))
            return

        self._scanning = True
        found = {}
        try:
            self.events.put(("status", "Scanning..."))
            self.events.put(("log", f"Starting BLE scan for {timeout:.0f} seconds..."))
            self.events.put(("log", "All discoverable BLE advertisers will be listed; HUD is not pre-filtered."))

            def detected(device, adv):
                try:
                    address = device.address
                    name = device.name or getattr(adv, "local_name", None) or "(unnamed)"
                    service_uuids = [u.lower() for u in (getattr(adv, "service_uuids", None) or [])]
                    is_hud_nus = p.SERVICE_UUID.lower() in service_uuids
                    rssi = getattr(adv, "rssi", None)
                    previous = found.get(address)
                    found[address] = (name, address, is_hud_nus, rssi, service_uuids)
                    if previous is None:
                        star = " [NUS/HUD candidate]" if is_hud_nus else ""
                        self.events.put(("log", f"FOUND: {name} | {address} | RSSI={rssi}{star}"))
                        self.events.put(("devices_live", list(found.values())))
                except Exception as e:
                    self.events.put(("log", f"Detection callback error: {type(e).__name__}: {e}"))

            scanner = BleakScanner(detection_callback=detected)
            self.events.put(("log", "Opening Windows BLE scanner..."))
            await scanner.start()
            self.events.put(("log", "Scanner started successfully."))
            await asyncio.sleep(timeout)
            await scanner.stop()
            self.events.put(("log", "Scanner stopped."))

            self.devices = sorted(
                list(found.values()),
                key=lambda x: (not x[2], -(x[3] if isinstance(x[3], int) else -999), x[0].lower()),
            )
            self.events.put(("devices", self.devices))
            self.events.put(("log", f"Scan complete: {len(self.devices)} BLE device(s) discovered."))
            if not self.devices:
                self.events.put(("log", "No BLE advertisers were returned by Windows to Bleak."))
                self.events.put(("log", "If Windows Settings sees devices, use the Diagnostic Console build and send us its output."))
            self.events.put(("status", "Disconnected" if not (self.client and self.client.is_connected) else "Connected"))
        except Exception as e:
            self.events.put(("log", f"SCAN ERROR: {type(e).__name__}: {e}"))
            self.events.put(("log", traceback.format_exc()))
            self.events.put(("status", "Scan failed"))
        finally:
            self._scanning = False

    async def connect(self, address):
        self.events.put(("log", f"Connecting to {address}..."))
        self._disconnect_requested = False
        if self.client and self.client.is_connected:
            await self.client.disconnect()

        def on_disconnected(_client):
            reason = "requested by tester" if self._disconnect_requested else "remote/link loss"
            self.events.put(("log", f"*** GATT DISCONNECTED ({reason}) ***"))
            self.events.put(("status", "Disconnected"))

        self.client = BleakClient(address, disconnected_callback=on_disconnected)
        await self.client.connect(timeout=20)
        self.events.put(("log", "GATT connection established."))

        # Log discovered services/characteristics so we can validate the hardware protocol.
        try:
            services = self.client.services
            for service in services:
                self.events.put(("log", f"SERVICE {service.uuid}"))
                for char in service.characteristics:
                    self.events.put(("log", f"  CHAR {char.uuid} props={','.join(char.properties)}"))
        except Exception as e:
            self.events.put(("log", f"Service enumeration warning: {e}"))

        await self.client.start_notify(p.RX_UUID, self._notify)
        self.events.put(("status", f"Connected: {address}"))
        self.events.put(("log", f"RX notifications enabled on {p.RX_UUID}"))

        # This is the first command sent by the original Android application
        # after GATT connection. The HUD replies with UartConnectionEventPacket.
        await self.send(p.cmd_uart_connection_check(), "UART connection check")
        self.events.put(("log", "HUD connection watchdog handshake started."))

    def _notify(self, _, data):
        packet = bytes(data)
        self.events.put(("rx", p.hexstr(packet)))

        # Original HUD Android behavior:
        # every UartConnectionEventPacket resets its 20 s watchdog and causes
        # an immediate KeepAliveCommandPacket to be sent back to the HUD.
        if p.is_uart_connection_event(packet):
            mode = p.uart_connection_mode(packet)
            self.events.put(("log", f"RX UART connection event (kivicMode={mode}) -> queue automatic KeepAlive"))
            try:
                task = asyncio.create_task(self.send(p.cmd_keep_alive(), "Auto KeepAlive"))
                self._auto_keepalive_tasks.add(task)
                task.add_done_callback(self._auto_keepalive_tasks.discard)
            except Exception as exc:
                self.events.put(("log", f"Auto KeepAlive scheduling error: {type(exc).__name__}: {exc}"))

    async def disconnect(self):
        self._disconnect_requested = True
        if self.client:
            await self.client.disconnect()
        self.events.put(("status", "Disconnected"))
        self.events.put(("log", "Disconnected."))

    async def send(self, data: bytes, label="Raw"):
        # The original Android HudNetworkManager has one global packet queue.
        # It sends a single 19-byte chunk and only advances on the GATT write
        # callback. Without this lock, an RX-triggered Auto KeepAlive can splice
        # itself into the middle of a maneuver frame and corrupt the UART stream.
        async with self._tx_lock:
            if not self.client or not self.client.is_connected:
                raise RuntimeError("Not connected")

            self._tx_sequence += 1
            seq = self._tx_sequence
            chunks = list(p.chunks(data, 19))
            self.events.put(("log", f"TX#{seq} {label}: {p.hexstr(data)}"))

            for i, c in enumerate(chunks, 1):
                if not self.client or not self.client.is_connected:
                    raise RuntimeError(f"Disconnected during TX#{seq} chunk {i}/{len(chunks)}")
                await self.client.write_gatt_char(p.TX_UUID, c, response=False)
                self.events.put(("log", f"  TX#{seq} chunk {i}/{len(chunks)}: {p.hexstr(c)}"))
                # Bleak/WinRT's write coroutine can complete before the peripheral
                # has consumed a no-response write. A conservative gap approximates
                # the Android callback-driven pacing during protocol discovery.
                await asyncio.sleep(0.060)

            # Prevent the next queued command from starting in the same BLE burst.
            await asyncio.sleep(0.040)

    async def initialize(self):
        now = int(time.time() * 1000)
        seq = [
            ("System time", p.cmd_system_time(now)),
            ("Keep alive", p.cmd_keep_alive()),
            ("Phone name", p.cmd_phone_name("HUD Windows Tester")),
            ("Keep alive", p.cmd_keep_alive()),
            ("Full screen", p.cmd_full_screen(True)),
            ("Keep alive", p.cmd_keep_alive()),
            ("Navigation off", p.cmd_nav_state(False)),
            ("Keep alive", p.cmd_keep_alive()),
            ("Brightness defaults", p.cmd_min_brightness(50, False)),
            ("Keep alive", p.cmd_keep_alive()),
        ]
        for label, data in seq:
            await self.send(data, label)
            await asyncio.sleep(0.12)


    async def run_route_simulator(self):
        """Five-leg manual navigation simulation with 1 Hz distance updates."""
        if self._route_sim_task and not self._route_sim_task.done():
            self.events.put(("log", "Route simulator is already running."))
            return

        async def _run():
            legs = [
                ("Straight", 2, 4, "Continue straight\nOak Avenue\n", 120),
                ("Right", 2, 2, "Turn right\nMain St\nOak Avenue", 100),
                ("Keep left", 8, 5, "Keep left\nUS-1 North\nMain St", 140),
                ("Exit right", 7, 2, "Take exit 12B\nMarket Street\nUS-1 North", 120),
                ("Left", 2, 6, "Turn left\nDestination Drive\nMarket Street", 80),
            ]
            try:
                self.events.put(("log", "=== ROUTE SIMULATOR START ==="))
                await self.send(p.cmd_nav_state(True), "Simulator Navigation ON")
                await asyncio.sleep(0.3)

                for leg_no, (name, typ, direction, text, start_m) in enumerate(legs, 1):
                    self.events.put(("log", f"SIM LEG {leg_no}/5: {name} | {text.splitlines()[1]}"))
                    # Six 1-second updates per leg; distance visibly counts down.
                    distances = [start_m, int(start_m*0.80), int(start_m*0.60),
                                 int(start_m*0.40), int(start_m*0.20), 5]
                    for distance in distances:
                        await self.send(
                            p.cmd_maneuver(distance, typ, direction, text),
                            f"SIM {leg_no}/5 {name} {distance}m"
                        )
                        await asyncio.sleep(1.0)

                await self.send(
                    p.cmd_maneuver(0, 17, 4, "You have arrived\nDestination Drive\n"),
                    "SIM Destination"
                )
                await asyncio.sleep(2.0)
                self.events.put(("log", "=== ROUTE SIMULATOR COMPLETE ==="))
            except asyncio.CancelledError:
                self.events.put(("log", "=== ROUTE SIMULATOR STOPPED ==="))
                raise
            finally:
                self._route_sim_task = None

        self._route_sim_task = asyncio.create_task(_run())
        await self._route_sim_task

    async def stop_route_simulator(self):
        task = self._route_sim_task
        if task and not task.done():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._route_sim_task = None

    async def run_ui_sequence(self):
        """Scripted dashboard transitions; this is not the firmware boot animation."""
        if self._ui_sequence_task and not self._ui_sequence_task.done():
            self.events.put(("log", "UI sequence is already running."))
            return

        async def _run():
            sequence = [
                ("Minimal", p.cmd_dashboard("Empty", "Simple", "Empty", False), 1.2),
                ("Classic", p.cmd_dashboard("Speedo", "Simple", "Time", False), 1.2),
                ("Stats", p.cmd_dashboard("AvgSpeedo", "Digits", "MaxSpeedo", False), 1.2),
                ("Navigation layout", p.cmd_dashboard("Speedo", "Navigation", "Time", True), 1.2),
            ]
            try:
                self.events.put(("log", "=== SCRIPTED UI SEQUENCE START ==="))
                await self.send(p.cmd_display_time_weather(False), "Hide time/weather panel")
                for label, packet, delay in sequence:
                    await self.send(packet, f"UI sequence: {label}")
                    await asyncio.sleep(delay)
                await self.send(p.cmd_display_time_weather(True), "Show time/weather panel")
                self.events.put(("log", "=== SCRIPTED UI SEQUENCE COMPLETE ==="))
            except asyncio.CancelledError:
                self.events.put(("log", "=== SCRIPTED UI SEQUENCE STOPPED ==="))
                raise
            finally:
                self._ui_sequence_task = None

        self._ui_sequence_task = asyncio.create_task(_run())
        await self._ui_sequence_task


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("HUD BLE Protocol Tester")
        self.geometry("1000x760")
        self.events = queue.Queue()
        self.worker = BleWorker(self.events)
        self._build()
        self.after(100, self.poll)

    def _build(self):
        top = ttk.Frame(self, padding=8)
        top.pack(fill="x")
        self.scan_btn = ttk.Button(top, text="Scan", command=self.scan_clicked)
        self.scan_btn.pack(side="left")
        self.dev = ttk.Combobox(top, width=68, state="readonly")
        self.dev.pack(side="left", padx=6)
        ttk.Button(top, text="Connect", command=self.connect).pack(side="left")
        ttk.Button(top, text="Disconnect", command=lambda: self.run(self.worker.submit(self.worker.disconnect()))).pack(side="left", padx=5)
        self.status = tk.StringVar(value="Disconnected")
        ttk.Label(top, textvariable=self.status).pack(side="left", padx=10)

        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=8, pady=4)
        nav = ttk.Frame(nb, padding=10)
        bright = ttk.Frame(nb, padding=10)
        raw = ttk.Frame(nb, padding=10)
        ui = ttk.Frame(nb, padding=10)
        nb.add(nav, text="Navigation")
        nb.add(bright, text="Brightness / Init")
        nb.add(ui, text="Dashboard / UI")
        nb.add(raw, text="Raw Packets")

        ttk.Button(nav, text="Initialize HUD", command=lambda: self.run(self.worker.submit(self.worker.initialize()))).grid(row=0, column=0, pady=5, sticky="ew")
        ttk.Button(nav, text="Navigation ON", command=lambda: self.send(p.cmd_nav_state(True), "Navigation ON")).grid(row=0, column=1, padx=5)
        ttk.Button(nav, text="Navigation OFF", command=lambda: self.send(p.cmd_nav_state(False), "Navigation OFF")).grid(row=0, column=2)
        ttk.Button(nav, text="Keep Alive", command=lambda: self.send(p.cmd_keep_alive(), "Keep Alive")).grid(row=0, column=3, padx=5)
        ttk.Label(nav, text="Maneuver").grid(row=1, column=0, sticky="w")
        self.man = ttk.Combobox(nav, values=list(p.MANEUVERS), state="readonly")
        self.man.set("Right")
        self.man.grid(row=1, column=1, sticky="ew")
        ttk.Label(nav, text="Distance (meters)").grid(row=2, column=0, sticky="w")
        self.dist = tk.StringVar(value="46")
        ttk.Entry(nav, textvariable=self.dist).grid(row=2, column=1, sticky="ew")
        ttk.Label(nav, text="Display text").grid(row=3, column=0, sticky="w")
        self.street = tk.StringVar(value="Turn right\\nMain St\\n")
        ttk.Entry(nav, textvariable=self.street, width=55).grid(row=3, column=1, columnspan=3, sticky="ew")
        ttk.Label(nav, text="Roundabout exit").grid(row=4, column=0, sticky="w")
        self.exit = tk.StringVar(value="0")
        ttk.Entry(nav, textvariable=self.exit).grid(row=4, column=1, sticky="ew")
        ttk.Button(nav, text="Send Maneuver", command=self.send_maneuver).grid(row=5, column=0, columnspan=2, pady=10, sticky="ew")
        ttk.Button(nav, text="Single Demo: Right 150 ft", command=self.demo).grid(row=5, column=2, columnspan=2, padx=5, sticky="ew")
        ttk.Button(nav, text="START 5-Leg Navigation Simulator", command=self.start_route_sim).grid(row=6, column=0, columnspan=3, pady=6, sticky="ew")
        ttk.Button(nav, text="STOP Simulator", command=self.stop_route_sim).grid(row=6, column=3, padx=5, sticky="ew")
        ttk.Label(nav, text="Simulator sends a new maneuver/distance every second across 5 streets.").grid(row=7, column=0, columnspan=4, sticky="w", pady=(0,8))
        for i in range(4):
            nav.columnconfigure(i, weight=1)

        ttk.Button(bright, text="Initialize HUD", command=lambda: self.run(self.worker.submit(self.worker.initialize()))).grid(row=0, column=0, columnspan=2, sticky="ew", pady=5)
        ttk.Button(bright, text="Auto Brightness ON", command=lambda: self.send(p.cmd_auto_brightness(True), "Auto brightness ON")).grid(row=1, column=0, sticky="ew")
        ttk.Button(bright, text="Auto Brightness OFF", command=lambda: self.send(p.cmd_auto_brightness(False), "Auto brightness OFF")).grid(row=1, column=1, sticky="ew", padx=5)
        ttk.Label(bright, text="Manual brightness").grid(row=2, column=0, sticky="w")
        self.bval = tk.IntVar(value=128)
        ttk.Scale(bright, from_=0, to=255, variable=self.bval, orient="horizontal").grid(row=2, column=1, sticky="ew")
        ttk.Button(bright, text="Send Manual Brightness", command=lambda: self.send(p.cmd_manual_brightness(int(self.bval.get())), "Manual brightness")).grid(row=3, column=0, columnspan=2, sticky="ew", pady=5)
        ttk.Button(bright, text="Full Screen ON", command=lambda: self.send(p.cmd_full_screen(True), "Full screen ON")).grid(row=4, column=0, sticky="ew")
        ttk.Button(bright, text="Full Screen OFF", command=lambda: self.send(p.cmd_full_screen(False), "Full screen OFF")).grid(row=4, column=1, sticky="ew", padx=5)
        bright.columnconfigure(0, weight=1)
        bright.columnconfigure(1, weight=1)

        ttk.Label(ui, text="Time / Weather bottom panel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0,5))
        ttk.Button(ui, text="Time + Weather ON", command=lambda: self.send(p.cmd_display_time_weather(True), "Time/weather panel ON")).grid(row=1, column=0, sticky="ew")
        ttk.Button(ui, text="Time + Weather OFF", command=lambda: self.send(p.cmd_display_time_weather(False), "Time/weather panel OFF")).grid(row=1, column=1, sticky="ew", padx=5)

        ttk.Separator(ui, orient="horizontal").grid(row=2, column=0, columnspan=2, sticky="ew", pady=12)
        ttk.Label(ui, text="Dashboard preset").grid(row=3, column=0, sticky="w")
        self.dashboard_preset = ttk.Combobox(ui, values=list(p.DASHBOARD_PRESETS), state="readonly")
        self.dashboard_preset.set("Classic home")
        self.dashboard_preset.grid(row=3, column=1, sticky="ew")
        ttk.Button(ui, text="Send Dashboard Preset", command=self.send_dashboard_preset).grid(row=4, column=0, columnspan=2, sticky="ew", pady=6)

        ttk.Separator(ui, orient="horizontal").grid(row=5, column=0, columnspan=2, sticky="ew", pady=12)
        ttk.Label(ui, text="Scripted UI transition (test sequence; not firmware boot animation)").grid(row=6, column=0, columnspan=2, sticky="w")
        ttk.Button(ui, text="Run Custom UI Sequence", command=self.start_ui_sequence).grid(row=7, column=0, columnspan=2, sticky="ew", pady=6)

        ui.columnconfigure(0, weight=1)
        ui.columnconfigure(1, weight=1)

        ttk.Label(raw, text="Hex bytes (already framed, or any raw BLE value)").pack(anchor="w")
        self.raw = tk.Text(raw, height=7)
        self.raw.pack(fill="x")
        self.raw.insert("1.0", p.hexstr(p.cmd_keep_alive()))
        ttk.Button(raw, text="Send Raw Hex", command=self.send_raw).pack(anchor="w", pady=5)
        ttk.Label(raw, text="Generated packet preview").pack(anchor="w")
        self.preview = tk.Text(raw, height=7)
        self.preview.pack(fill="x")

        logf = ttk.LabelFrame(self, text="TX / RX / Diagnostic log", padding=5)
        logf.pack(fill="both", expand=True, padx=8, pady=6)
        self.log = tk.Text(logf, height=16)
        self.log.pack(fill="both", expand=True)
        self.log.insert("end", "HUD BLE Tester started. Click Scan; scan diagnostics will appear here immediately.\n")

    def ui_log(self, text: str):
        self.log.insert("end", text + "\n")
        self.log.see("end")

    def scan_clicked(self):
        # This line proves the Tk button callback itself fired even if Bleak/WinRT fails later.
        self.ui_log("SCAN BUTTON: clicked")
        self.status.set("Starting scan...")
        self.dev["values"] = []
        self.dev.set("")
        try:
            fut = self.worker.submit(self.worker.scan())
            self.run(fut)
        except Exception as e:
            self.ui_log(f"SCAN SCHEDULING ERROR: {type(e).__name__}: {e}")
            self.status.set("Scan failed")

    def run(self, fut):
        def done(f):
            try:
                f.result()
            except Exception as e:
                self.events.put(("log", f"ASYNC ERROR: {type(e).__name__}: {e}"))
                self.events.put(("log", traceback.format_exc()))
        fut.add_done_callback(done)

    def send(self, data, label):
        self.preview.delete("1.0", "end")
        self.preview.insert("1.0", p.hexstr(data))
        try:
            self.run(self.worker.submit(self.worker.send(data, label)))
        except Exception as e:
            self.ui_log(f"SEND SCHEDULING ERROR: {type(e).__name__}: {e}")

    def connect(self):
        idx = self.dev.current()
        if idx < 0:
            return messagebox.showinfo("Select device", "Scan and select a device first.")
        try:
            self.run(self.worker.submit(self.worker.connect(self.worker.devices[idx][1])))
        except Exception as e:
            self.ui_log(f"CONNECT SCHEDULING ERROR: {type(e).__name__}: {e}")

    def send_maneuver(self):
        t, d = p.MANEUVERS[self.man.get()]
        data = p.cmd_maneuver(
            int(self.dist.get()),
            t,
            d,
            self.street.get().replace("\\n", "\n"),
            exit_index=int(self.exit.get()),
        )
        self.send(data, "Maneuver")

    def demo(self):
        async def x():
            await self.worker.send(p.cmd_nav_state(True), "Navigation ON")
            await asyncio.sleep(0.2)
            await self.worker.send(p.cmd_keep_alive(), "Keep Alive")
            await asyncio.sleep(0.2)
            await self.worker.send(p.cmd_maneuver(46, 2, 2, "Turn right\nMain St\n"), "Right 150 ft")
        try:
            self.run(self.worker.submit(x()))
        except Exception as e:
            self.ui_log(f"DEMO SCHEDULING ERROR: {type(e).__name__}: {e}")

    def start_route_sim(self):
        try:
            self.run(self.worker.submit(self.worker.run_route_simulator()))
        except Exception as e:
            self.ui_log(f"SIMULATOR SCHEDULING ERROR: {type(e).__name__}: {e}")

    def stop_route_sim(self):
        try:
            self.run(self.worker.submit(self.worker.stop_route_simulator()))
        except Exception as e:
            self.ui_log(f"SIMULATOR STOP ERROR: {type(e).__name__}: {e}")

    def send_dashboard_preset(self):
        name = self.dashboard_preset.get()
        left, center, right, navi = p.DASHBOARD_PRESETS[name]
        self.send(p.cmd_dashboard(left, center, right, navi), f"Dashboard preset: {name}")

    def start_ui_sequence(self):
        try:
            self.run(self.worker.submit(self.worker.run_ui_sequence()))
        except Exception as e:
            self.ui_log(f"UI SEQUENCE ERROR: {type(e).__name__}: {e}")

    def send_raw(self):
        try:
            self.send(p.parse_hex(self.raw.get("1.0", "end")), "Raw")
        except Exception as e:
            messagebox.showerror("Invalid hex", str(e))

    def update_device_list(self, val):
        self.worker.devices = val
        values = []
        for n, a, is_hud, rssi, _uuids in val:
            star = "★ " if is_hud else ""
            rssi_text = f" | RSSI {rssi}" if rssi is not None else ""
            values.append(f"{star}{n} | {a}{rssi_text}")
        self.dev["values"] = values
        if val and self.dev.current() < 0:
            self.dev.current(0)

    def poll(self):
        try:
            while True:
                kind, val = self.events.get_nowait()
                if kind in ("devices", "devices_live"):
                    self.update_device_list(val)
                elif kind == "status":
                    self.status.set(val)
                elif kind == "rx":
                    self.ui_log(f"RX: {val}")
                else:
                    self.ui_log(val)
        except queue.Empty:
            pass
        self.after(100, self.poll)


if __name__ == "__main__":
    App().mainloop()
