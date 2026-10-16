#!/usr/bin/env python3
from pathlib import Path
import io,tarfile,gzip,subprocess,hashlib,tempfile
BASE=Path(__file__).resolve().parent; SRC=BASE/'source'; KEY=b'CarPlay5KBP6ClJv'; IV=KEY
INSTALL=['install_once.sh','libu2w_rgd_preload_v840.so','u2wvideo-bootstrap-current.cgi','u2wvideo-bootstrap-previous.cgi','u2wvideo-relay-status.cgi','u2wresource-status.cgi']
ROLLBACK=['rollback_once.sh','v839-libu2w_rgd_preload.so','v838-u2wvideo-bootstrap-current.cgi','v838-u2wvideo-bootstrap-previous.cgi','v838-u2wvideo-relay-status.cgi']
def pack(names,once):
 b=io.BytesIO()
 with gzip.GzipFile(filename='',mode='wb',fileobj=b,mtime=0,compresslevel=9) as gz:
  with tarfile.open(fileobj=gz,mode='w',format=tarfile.GNU_FORMAT) as tf:
   for n in names:
    d=(SRC/n).read_bytes(); ti=tarfile.TarInfo('tmp/once.sh' if n==once else 'tmp/'+n);ti.size=len(d);ti.uid=ti.gid=0;ti.uname=ti.gname='root';ti.mtime=0;ti.mode=0o755;tf.addfile(ti,io.BytesIO(d))
 return b.getvalue()
def aes(d,dec=False):
 full=len(d)//16*16
 if not full:return d
 with tempfile.TemporaryDirectory() as td:
  i=Path(td)/'i';o=Path(td)/'o';i.write_bytes(d[:full]);cmd=['openssl','enc']+(['-d'] if dec else [])+['-aes-128-cbc','-nopad','-K',KEY.hex(),'-iv',IV.hex(),'-in',str(i),'-out',str(o)];subprocess.run(cmd,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);return o.read_bytes()+d[full:]
rows=[]
for names,once,name in [(INSTALL,'install_once.sh','U2W_Update_v8.40_ResourceSafeBootstrap_v839.img'),(ROLLBACK,'rollback_once.sh','U2W_Update_v8.40_SAFE_ROLLBACK_v8.39.img')]:
 t=pack(names,once); w=aes(t); assert aes(w,True)==t; (BASE/name).write_bytes(w); rows.append((name,hashlib.sha256(w).hexdigest())); print(name,len(w),rows[-1][1])
(BASE/'U2W_v8.40_SHA256SUMS.txt').write_text(''.join(f'{h}  {n}\n' for n,h in rows))
