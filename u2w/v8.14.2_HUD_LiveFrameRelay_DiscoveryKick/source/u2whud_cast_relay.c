/* U2W v8.14 KivicCast relay. Serves latest /tmp/u2whud_latest.jpg at 5 fps. */
typedef unsigned int u32; typedef unsigned short u16; typedef unsigned long size_t; typedef long ssize_t;
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; unsigned char zero[8]; };
struct timespec { long tv_sec; long tv_nsec; };
#define SYS_exit 1
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_nanosleep 162
#define SYS_socket 281
#define SYS_bind 282
#define SYS_listen 284
#define SYS_accept 285
#define SYS_sendto 290
#define SYS_recvfrom 292
#define AF_INET 2
#define SOCK_STREAM 1
#define SOCK_DGRAM 2
static unsigned char framebuf[131072];
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static long sc6(long n,long a,long b,long c,long d,long e,long f){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;register long r5 __asm__("r5")=f;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory");return r0;}
static u16 htons(u16 x){return (u16)((x<<8)|(x>>8));}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static int contains(const char*b,size_t n,const char*s){size_t m=slen(s),i,j;if(m>n)return 0;for(i=0;i+m<=n;i++){for(j=0;j<m&&b[i+j]==s[j];j++);if(j==m)return 1;}return 0;}
static long wr(int fd,const void*p,size_t n){return sc3(SYS_write,fd,(long)p,n);}
static void logmsg(const char*s){wr(1,s,slen(s));}
static int sendall(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=wr(fd,p+o,n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static void sleep200(void){struct timespec t;t.tv_sec=0;t.tv_nsec=200000000L;sc2(SYS_nanosleep,(long)&t,0);}
static size_t load(const char*path){int f=(int)sc3(SYS_open,(long)path,0,0);if(f<0)return 0;size_t o=0;for(;;){if(o>=sizeof(framebuf))break;long r=sc3(SYS_read,f,(long)(framebuf+o),sizeof(framebuf)-o);if(r<=0)break;o+=(size_t)r;}sc1(SYS_close,f);return o;}
static size_t dec(char*out,u32 v){char rev[16];size_t n=0;if(v==0){out[0]='0';return 1;}while(v){rev[n++]=(char)('0'+v%10);v/=10;}for(size_t i=0;i<n;i++)out[i]=rev[n-1-i];return n;}
static int part_header(int c,size_t n){static const char a[]="--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ";static const char b[]="\r\n\r\n";char num[16];size_t m=dec(num,(u32)n);if(sendall(c,(const unsigned char*)a,sizeof(a)-1)<0)return -1;if(sendall(c,(const unsigned char*)num,m)<0)return -1;return sendall(c,(const unsigned char*)b,sizeof(b)-1);}
static void serve_client(int c){
 static const char hdr[]="HTTP/1.1 200 OK\r\nConnection: close\r\nCache-Control: no-cache, no-store\r\nPragma: no-cache\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n";static const char crlf[]="\r\n";char req[1024];sc3(SYS_read,c,(long)req,sizeof(req));if(sendall(c,(const unsigned char*)hdr,sizeof(hdr)-1)<0)return;logmsg("hud-mjpeg-client-connected\n");
 for(;;){size_t n=load("/tmp/u2whud_latest.jpg");if(n<128)n=load("/usr/lib/u2whud/u2whud_test.jpg");if(n<128){sleep200();continue;}if(part_header(c,n)<0)break;if(sendall(c,framebuf,n)<0)break;if(sendall(c,(const unsigned char*)crlf,2)<0)break;sleep200();}logmsg("hud-mjpeg-client-closed\n");
}
void _start(void){
 int s=(int)sc3(SYS_socket,AF_INET,SOCK_STREAM,0);if(s<0){logmsg("tcp-socket-fail\n");sc1(SYS_exit,12);}struct sockaddr_in ta;ta.sin_family=AF_INET;ta.sin_port=htons(15330);ta.sin_addr=0;for(int i=0;i<8;i++)ta.zero[i]=0;if(sc3(SYS_bind,s,(long)&ta,sizeof(ta))<0){logmsg("tcp-bind-fail\n");sc1(SYS_exit,13);}if(sc2(SYS_listen,s,2)<0){logmsg("listen-fail\n");sc1(SYS_exit,14);}logmsg("mjpeg-listening-15330\n");for(;;){int c=(int)sc3(SYS_accept,s,0,0);if(c<0)continue;serve_client(c);sc1(SYS_close,c);} }
