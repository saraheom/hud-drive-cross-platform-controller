/* U2W v8.22 hardened KivicCast relay: v8.15.1 behavior + socket stall watchdog. */
typedef unsigned int u32; typedef unsigned short u16; typedef unsigned long size_t; typedef long ssize_t;
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; unsigned char zero[8]; };
struct timespec { long tv_sec; long tv_nsec; };
struct timeval { long tv_sec; long tv_usec; };
#define SYS_exit 1
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_unlink 10
#define SYS_nanosleep 162
#define SYS_socket 281
#define SYS_bind 282
#define SYS_listen 284
#define SYS_accept 285
#define SYS_sendto 290
#define SYS_setsockopt 294
#define AF_INET 2
#define SOCK_STREAM 1
#define SOL_SOCKET 1
#define SO_REUSEADDR 2
#define SO_RCVTIMEO 20
#define SO_SNDTIMEO 21
#define MSG_NOSIGNAL 0x4000
#define O_WRONLY 1
#define O_CREAT 64
#define O_TRUNC 512
static unsigned char framebuf[131072];
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static long sc5(long n,long a,long b,long c,long d,long e){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r7):"memory");return r0;}
static long sc6(long n,long a,long b,long c,long d,long e,long f){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;register long r5 __asm__("r5")=f;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory");return r0;}
static u16 htons(u16 x){return (u16)((x<<8)|(x>>8));}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static int contains(const char*b,size_t n,const char*s){size_t m=slen(s),i,j;if(m>n)return 0;for(i=0;i+m<=n;i++){for(j=0;j<m&&b[i+j]==s[j];j++);if(j==m)return 1;}return 0;}
static long wr(int fd,const void*p,size_t n){return sc3(SYS_write,fd,(long)p,n);}
static void logmsg(const char*s){wr(1,s,slen(s));}
static void touch_marker(const char*path){int f=(int)sc3(SYS_open,(long)path,O_WRONLY|O_CREAT|O_TRUNC,0644);if(f>=0){static const char one[]="1\n";wr(f,one,2);sc1(SYS_close,f);}}
static void clear_marker(const char*path){sc1(SYS_unlink,(long)path);}
static void clear_established(void){clear_marker("/tmp/u2whud_session_established");}
/* sendto(MSG_NOSIGNAL) avoids SIGPIPE killing the entire relay when the HUD closes a probe socket. */
static int sendall(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=sc6(SYS_sendto,fd,(long)(p+o),n-o,MSG_NOSIGNAL,0,0);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static void sleep200(void){struct timespec t;t.tv_sec=0;t.tv_nsec=200000000L;sc2(SYS_nanosleep,(long)&t,0);}
static size_t load_into(const char*path,unsigned char*buf,size_t cap){int f=(int)sc3(SYS_open,(long)path,0,0);if(f<0)return 0;size_t o=0;for(;;){if(o>=cap)break;long r=sc3(SYS_read,f,(long)(buf+o),cap-o);if(r<=0)break;o+=(size_t)r;}sc1(SYS_close,f);return o;}
static size_t dec(char*out,u32 v){static const u32 pow10[6]={100000,10000,1000,100,10,1};size_t n=0;int started=0;for(int i=0;i<6;i++){unsigned char d=0;while(v>=pow10[i]){v-=pow10[i];d++;}if(d||started||i==5){out[n++]=(char)('0'+d);started=1;}}return n;}
static int part_header(int c,size_t n){static const char a[]="--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ";static const char b[]="\r\n\r\n";char num[16];size_t m=dec(num,(u32)n);if(sendall(c,(const unsigned char*)a,sizeof(a)-1)<0)return -1;if(sendall(c,(const unsigned char*)num,m)<0)return -1;return sendall(c,(const unsigned char*)b,sizeof(b)-1);}
/* Return 1 only for baseline SOF0 480x240. Return 2 for progressive 480x240, 0 otherwise. */
static int jpeg_compat(const unsigned char*p,size_t n){if(n<4||p[0]!=0xff||p[1]!=0xd8)return 0;size_t i=2;while(i+8<n){if(p[i]!=0xff){i++;continue;}while(i<n&&p[i]==0xff)i++;if(i>=n)break;unsigned char m=p[i++];if(m==0xd9||m==0xda)break;if(m==0x01||(m>=0xd0&&m<=0xd7))continue;if(i+2>n)break;u16 len=(u16)(((u16)p[i]<<8)|p[i+1]);if(len<2||i+len>n)break;if((m==0xc0||m==0xc2)&&len>=7){u16 h=(u16)(((u16)p[i+3]<<8)|p[i+4]);u16 w=(u16)(((u16)p[i+5]<<8)|p[i+6]);if(w==480&&h==240)return m==0xc0?1:2;return 0;}i+=len;}return 0;}
static int send_part(int c,const unsigned char*p,size_t n){static const char crlf[]="\r\n";if(part_header(c,n)<0)return -1;if(sendall(c,p,n)<0)return -1;if(sendall(c,(const unsigned char*)crlf,2)<0)return -1;return 0;}
static void serve_client(int c){
 struct timeval tv;tv.tv_sec=2;tv.tv_usec=0;sc5(SYS_setsockopt,c,SOL_SOCKET,SO_SNDTIMEO,(long)&tv,sizeof(tv));tv.tv_sec=3;sc5(SYS_setsockopt,c,SOL_SOCKET,SO_RCVTIMEO,(long)&tv,sizeof(tv));
 static const char hdr[]="HTTP/1.1 200 OK\r\nConnection: close\r\nCache-Control: no-cache, no-store\r\nPragma: no-cache\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n";
 char req[1024];long rn=sc3(SYS_read,c,(long)req,sizeof(req));if(rn<=0){logmsg("hud-http-empty-request\n");return;}if(contains(req,(size_t)rn,"HEAD ")){logmsg("hud-http-head\n");sendall(c,(const unsigned char*)hdr,sizeof(hdr)-1);return;}if(contains(req,(size_t)rn,"GET "))logmsg("hud-http-get\n");else logmsg("hud-http-other\n");
 if(sendall(c,(const unsigned char*)hdr,sizeof(hdr)-1)<0){logmsg("hud-http-header-send-failed\n");return;}logmsg("hud-mjpeg-client-connected\n");
 touch_marker("/tmp/u2whud_session_client");touch_marker("/tmp/u2whud_session_established");
 /* v8.15.1 never exposes the old known-image primer. Wait until the iPhone
    has published a valid baseline 480x240 JPEG, then prime the stock decoder
    with three copies of that actual live HUD frame. If live input later pauses
    or is temporarily incompatible, hold the HUD's last frame instead of
    switching to a fallback image. */
 int logged_live=0,logged_wait=0,primed=0;
 for(;;){
  size_t n=load_into("/tmp/u2whud_latest.jpg",framebuf,sizeof(framebuf));
  int compat=jpeg_compat(framebuf,n);
  if(n<128||compat!=1){
   if(!logged_wait){
    if(compat==2)logmsg("waiting-live-jpeg-progressive\n");
    else logmsg("waiting-first-live-frame\n");
    logged_wait=1;
   }
   sleep200();
   continue;
  }
  logged_wait=0;
  if(!primed){
   for(int k=0;k<3;k++){
    if(send_part(c,framebuf,n)<0){logmsg("mjpeg-send-failed\n");logmsg("hud-mjpeg-client-closed\n");clear_established();return;}
    if(k==0){logmsg("live-primer-frame-sent\n");touch_marker("/tmp/u2whud_session_live");}
    sleep200();
   }
   primed=1;
   logged_live=1;
   continue;
  }
  if(send_part(c,framebuf,n)<0){logmsg("mjpeg-send-failed\n");break;}
  if(!logged_live){logmsg("live-frame-sent\n");touch_marker("/tmp/u2whud_session_live");logged_live=1;}
  sleep200();
 }
 logmsg("hud-mjpeg-client-closed\n");clear_established();
}
void _start(void){
 int s=(int)sc3(SYS_socket,AF_INET,SOCK_STREAM,0);if(s<0){logmsg("tcp-socket-fail\n");sc1(SYS_exit,12);}int one=1;if(sc5(SYS_setsockopt,s,SOL_SOCKET,SO_REUSEADDR,(long)&one,sizeof(one))<0)logmsg("reuseaddr-fail\n");struct sockaddr_in ta;ta.sin_family=AF_INET;ta.sin_port=htons(15330);ta.sin_addr=0;for(int i=0;i<8;i++)ta.zero[i]=0;if(sc3(SYS_bind,s,(long)&ta,sizeof(ta))<0){logmsg("tcp-bind-fail\n");sc1(SYS_exit,13);}if(sc2(SYS_listen,s,4)<0){logmsg("listen-fail\n");sc1(SYS_exit,14);}logmsg("mjpeg-listening-15330-v822-watchdog\n");for(;;){int c=(int)sc3(SYS_accept,s,0,0);if(c<0)continue;serve_client(c);sc1(SYS_close,c);} }
