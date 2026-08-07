from __future__ import annotations

import asyncio
import platform
import queue
import threading
import time
import traceback
import tkinter as tk
from tkinter import ttk, messagebox

from bleak import BleakClient, BleakScanner
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
        threading.Thread(target=self._run, daemon=True, name="HUDWAY-BLE-Asyncio").start()

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
            self.events.put(("log", "All discoverable BLE advertisers will be listed; HUDWAY is not pre-filtered."))

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
                        star = " [NUS/HUDWAY candidate]" if is_hud_nus else ""
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
        if self.client and self.client.is_connected:
            await self.client.disconnect()
        self.client = BleakClient(
            address,
            disconnected_callback=lambda _: self.events.put(("status", "Disconnected")),
        )
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

    def _notify(self, _, data):
        self.events.put(("rx", p.hexstr(bytes(data))))

    async def disconnect(self):
        if self.client:
            await self.client.disconnect()
        self.events.put(("status", "Disconnected"))
        self.events.put(("log", "Disconnected."))

    async def send(self, data: bytes, label="Raw"):
        if not self.client or not self.client.is_connected:
            raise RuntimeError("Not connected")
        self.events.put(("log", f"TX {label}: {p.hexstr(data)}"))
        for i, c in enumerate(p.chunks(data, 19), 1):
            await self.client.write_gatt_char(p.TX_UUID, c, response=False)
            self.events.put(("log", f"  chunk {i}: {p.hexstr(c)}"))
            await asyncio.sleep(0.04)

    async def initialize(self):
        now = int(time.time() * 1000)
        seq = [
            ("System time", p.cmd_system_time(now)),
            ("Keep alive", p.cmd_keep_alive()),
            ("Phone name", p.cmd_phone_name("HUDWAY Windows Tester")),
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


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("HUDWAY BLE Protocol Tester")
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
        nb.add(nav, text="Navigation")
        nb.add(bright, text="Brightness / Init")
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
        ttk.Button(nav, text="Demo: ON + Right 150 ft", command=self.demo).grid(row=5, column=2, columnspan=2, padx=5, sticky="ew")
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
        self.log.insert("end", "HUDWAY BLE Tester started. Click Scan; scan diagnostics will appear here immediately.\n")

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
