from __future__ import annotations
import asyncio, threading, queue, time
import tkinter as tk
from tkinter import ttk, messagebox
from bleak import BleakScanner, BleakClient
import protocol as p

class BleWorker:
    def __init__(self, events):
        self.events=events; self.loop=asyncio.new_event_loop(); self.client=None; self.devices=[]
        threading.Thread(target=self._run,daemon=True).start()
    def _run(self): asyncio.set_event_loop(self.loop); self.loop.run_forever()
    def submit(self,coro): return asyncio.run_coroutine_threadsafe(coro,self.loop)
    async def scan(self):
        self.events.put(('log','Scanning 8 seconds...'))
        devs=await BleakScanner.discover(timeout=8.0,return_adv=True)
        self.devices=[]
        for addr,(d,adv) in devs.items():
            name=d.name or adv.local_name or '(unnamed)'
            uuids=[u.lower() for u in (adv.service_uuids or [])]
            self.devices.append((name,d.address,p.SERVICE_UUID in uuids))
        self.events.put(('devices',self.devices))
    async def connect(self,address):
        if self.client and self.client.is_connected: await self.client.disconnect()
        self.client=BleakClient(address,disconnected_callback=lambda _: self.events.put(('status','Disconnected')))
        await self.client.connect(timeout=20)
        await self.client.start_notify(p.RX_UUID,self._notify)
        self.events.put(('status',f'Connected: {address}'))
        self.events.put(('log','RX notifications enabled'))
    def _notify(self,_,data): self.events.put(('rx',p.hexstr(bytes(data))))
    async def disconnect(self):
        if self.client: await self.client.disconnect()
        self.events.put(('status','Disconnected'))
    async def send(self,data: bytes,label='Raw'):
        if not self.client or not self.client.is_connected: raise RuntimeError('Not connected')
        self.events.put(('log',f'TX {label}: {p.hexstr(data)}'))
        for i,c in enumerate(p.chunks(data,19),1):
            await self.client.write_gatt_char(p.TX_UUID,c,response=False)
            self.events.put(('log',f'  chunk {i}: {p.hexstr(c)}'))
            await asyncio.sleep(0.04)
    async def initialize(self):
        now=int(time.time()*1000)
        seq=[('System time',p.cmd_system_time(now)),('Keep alive',p.cmd_keep_alive()),
             ('Phone name',p.cmd_phone_name('HUDWAY Windows Tester')),('Keep alive',p.cmd_keep_alive()),
             ('Full screen',p.cmd_full_screen(True)),('Keep alive',p.cmd_keep_alive()),
             ('Navigation off',p.cmd_nav_state(False)),('Keep alive',p.cmd_keep_alive()),
             ('Brightness defaults',p.cmd_min_brightness(50,False)),('Keep alive',p.cmd_keep_alive())]
        for label,data in seq:
            await self.send(data,label); await asyncio.sleep(.12)

class App(tk.Tk):
    def __init__(self):
        super().__init__(); self.title('HUDWAY BLE Protocol Tester'); self.geometry('980x720')
        self.events=queue.Queue(); self.worker=BleWorker(self.events); self._build(); self.after(100,self.poll)
    def _build(self):
        top=ttk.Frame(self,padding=8); top.pack(fill='x')
        ttk.Button(top,text='Scan',command=lambda:self.run(self.worker.scan())).pack(side='left')
        self.dev=ttk.Combobox(top,width=62,state='readonly'); self.dev.pack(side='left',padx=6)
        ttk.Button(top,text='Connect',command=self.connect).pack(side='left'); ttk.Button(top,text='Disconnect',command=lambda:self.run(self.worker.disconnect())).pack(side='left',padx=5)
        self.status=tk.StringVar(value='Disconnected'); ttk.Label(top,textvariable=self.status).pack(side='left',padx=10)
        nb=ttk.Notebook(self); nb.pack(fill='both',expand=True,padx=8,pady=4)
        nav=ttk.Frame(nb,padding=10); bright=ttk.Frame(nb,padding=10); raw=ttk.Frame(nb,padding=10); nb.add(nav,text='Navigation'); nb.add(bright,text='Brightness / Init'); nb.add(raw,text='Raw Packets')
        ttk.Button(nav,text='Initialize HUD',command=lambda:self.run(self.worker.initialize())).grid(row=0,column=0,pady=5,sticky='ew')
        ttk.Button(nav,text='Navigation ON',command=lambda:self.send(p.cmd_nav_state(True),'Navigation ON')).grid(row=0,column=1,padx=5)
        ttk.Button(nav,text='Navigation OFF',command=lambda:self.send(p.cmd_nav_state(False),'Navigation OFF')).grid(row=0,column=2)
        ttk.Button(nav,text='Keep Alive',command=lambda:self.send(p.cmd_keep_alive(),'Keep Alive')).grid(row=0,column=3,padx=5)
        ttk.Label(nav,text='Maneuver').grid(row=1,column=0,sticky='w'); self.man=ttk.Combobox(nav,values=list(p.MANEUVERS),state='readonly'); self.man.set('Right'); self.man.grid(row=1,column=1,sticky='ew')
        ttk.Label(nav,text='Distance (meters)').grid(row=2,column=0,sticky='w'); self.dist=tk.StringVar(value='46'); ttk.Entry(nav,textvariable=self.dist).grid(row=2,column=1,sticky='ew')
        ttk.Label(nav,text='Display text').grid(row=3,column=0,sticky='w'); self.street=tk.StringVar(value='Turn right\nMain St\n'); ttk.Entry(nav,textvariable=self.street,width=55).grid(row=3,column=1,columnspan=3,sticky='ew')
        ttk.Label(nav,text='Roundabout exit').grid(row=4,column=0,sticky='w'); self.exit=tk.StringVar(value='0'); ttk.Entry(nav,textvariable=self.exit).grid(row=4,column=1,sticky='ew')
        ttk.Button(nav,text='Send Maneuver',command=self.send_maneuver).grid(row=5,column=0,columnspan=2,pady=10,sticky='ew')
        ttk.Button(nav,text='Demo: ON + Right 150 ft',command=self.demo).grid(row=5,column=2,columnspan=2,padx=5,sticky='ew')
        for i in range(4): nav.columnconfigure(i,weight=1)
        ttk.Button(bright,text='Initialize HUD',command=lambda:self.run(self.worker.initialize())).grid(row=0,column=0,columnspan=2,sticky='ew',pady=5)
        ttk.Button(bright,text='Auto Brightness ON',command=lambda:self.send(p.cmd_auto_brightness(True),'Auto brightness ON')).grid(row=1,column=0,sticky='ew')
        ttk.Button(bright,text='Auto Brightness OFF',command=lambda:self.send(p.cmd_auto_brightness(False),'Auto brightness OFF')).grid(row=1,column=1,sticky='ew',padx=5)
        ttk.Label(bright,text='Manual brightness').grid(row=2,column=0,sticky='w'); self.bval=tk.IntVar(value=128); ttk.Scale(bright,from_=0,to=255,variable=self.bval,orient='horizontal').grid(row=2,column=1,sticky='ew')
        ttk.Button(bright,text='Send Manual Brightness',command=lambda:self.send(p.cmd_manual_brightness(int(self.bval.get())),'Manual brightness')).grid(row=3,column=0,columnspan=2,sticky='ew',pady=5)
        ttk.Button(bright,text='Full Screen ON',command=lambda:self.send(p.cmd_full_screen(True),'Full screen ON')).grid(row=4,column=0,sticky='ew'); ttk.Button(bright,text='Full Screen OFF',command=lambda:self.send(p.cmd_full_screen(False),'Full screen OFF')).grid(row=4,column=1,sticky='ew',padx=5)
        bright.columnconfigure(0,weight=1); bright.columnconfigure(1,weight=1)
        ttk.Label(raw,text='Hex bytes (already framed, or any raw BLE value)').pack(anchor='w'); self.raw=tk.Text(raw,height=7); self.raw.pack(fill='x'); self.raw.insert('1.0',p.hexstr(p.cmd_keep_alive()))
        ttk.Button(raw,text='Send Raw Hex',command=self.send_raw).pack(anchor='w',pady=5)
        ttk.Label(raw,text='Generated packet preview').pack(anchor='w'); self.preview=tk.Text(raw,height=7); self.preview.pack(fill='x')
        logf=ttk.LabelFrame(self,text='TX / RX log',padding=5); logf.pack(fill='both',expand=True,padx=8,pady=6); self.log=tk.Text(logf,height=14); self.log.pack(fill='both',expand=True)
    def run(self,fut):
        def done(f):
            try:f.result()
            except Exception as e:self.events.put(('log',f'ERROR: {e}'))
        fut.add_done_callback(done)
    def send(self,data,label): self.preview.delete('1.0','end'); self.preview.insert('1.0',p.hexstr(data)); self.run(self.worker.send(data,label))
    def connect(self):
        idx=self.dev.current()
        if idx<0:return messagebox.showinfo('Select device','Scan and select a device first.')
        self.run(self.worker.connect(self.worker.devices[idx][1]))
    def send_maneuver(self):
        t,d=p.MANEUVERS[self.man.get()]; data=p.cmd_maneuver(int(self.dist.get()),t,d,self.street.get().replace('\\n','\n'),exit_index=int(self.exit.get())); self.send(data,'Maneuver')
    def demo(self):
        async def x():
            await self.worker.send(p.cmd_nav_state(True),'Navigation ON'); await asyncio.sleep(.2); await self.worker.send(p.cmd_keep_alive(),'Keep Alive'); await asyncio.sleep(.2); await self.worker.send(p.cmd_maneuver(46,2,2,'Turn right\nMain St\n'),'Right 150 ft')
        self.run(x())
    def send_raw(self):
        try:self.send(p.parse_hex(self.raw.get('1.0','end')),'Raw')
        except Exception as e:messagebox.showerror('Invalid hex',str(e))
    def poll(self):
        try:
            while True:
                kind,val=self.events.get_nowait()
                if kind=='devices':
                    self.dev['values']=[f"{'★ ' if u else ''}{n} | {a}" for n,a,u in val]
                    if val:self.dev.current(0)
                elif kind=='status':self.status.set(val)
                elif kind=='rx':self.log.insert('end',f'RX: {val}\n'); self.log.see('end')
                else:self.log.insert('end',val+'\n'); self.log.see('end')
        except queue.Empty:pass
        self.after(100,self.poll)
if __name__=='__main__': App().mainloop()
