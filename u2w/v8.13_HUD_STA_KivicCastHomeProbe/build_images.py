#!/usr/bin/env python3
from pathlib import Path
import io, tarfile, gzip, subprocess, hashlib, tempfile
BASE=Path(__file__).resolve().parent; SRC=BASE/'source'
KEY=b'CarPlay5KBP6ClJv'; IV=KEY
INSTALL=['install_once.sh','u2whud_cast_test','u2whud_test.jpg','u2whud_stop.sh','u2whud-start.cgi','u2whud-stop.cgi','u2whud-status.cgi']
def sha(b): return hashlib.sha256(b).hexdigest()
def tar_payload(uninstall=False):
    names=['uninstall_once.sh'] if uninstall else INSTALL
    bio=io.BytesIO()
    with gzip.GzipFile(filename='',mode='wb',fileobj=bio,mtime=0,compresslevel=9) as gz:
      with tarfile.open(fileobj=gz,mode='w',format=tarfile.GNU_FORMAT) as tf:
        for name in names:
          data=(SRC/name).read_bytes(); arc='tmp/once.sh' if name in ('install_once.sh','uninstall_once.sh') else 'tmp/'+name
          ti=tarfile.TarInfo(arc); ti.size=len(data);ti.uid=ti.gid=0;ti.uname=ti.gname='root';ti.mtime=0;ti.mode=0o755
          tf.addfile(ti,io.BytesIO(data))
    return bio.getvalue()
def aes(data,dec=False):
    full=(len(data)//16)*16; head=data[:full]; tail=data[full:]
    if not head:return tail
    with tempfile.TemporaryDirectory() as td:
      ip=Path(td)/'in';op=Path(td)/'out';ip.write_bytes(head)
      cmd=['openssl','enc']+(['-d'] if dec else [])+['-aes-128-cbc','-nopad','-K',KEY.hex(),'-iv',IV.hex(),'-in',str(ip),'-out',str(op)]
      subprocess.run(cmd,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
      return op.read_bytes()+tail
for uninstall,outname in [(False,'U2W_Update_v8.13_HUD_STA_KivicCastHomeProbe.img'),(True,'U2W_Update_v8.13_HUD_STA_KivicCastHomeProbe_UNINSTALL.img')]:
    t=tar_payload(uninstall); w=aes(t); assert aes(w,True)==t
    (BASE/outname).write_bytes(w)
    with tarfile.open(fileobj=io.BytesIO(t),mode='r:gz') as tf: members=[m.name for m in tf.getmembers()]
    print(outname,len(w),sha(w),members)
