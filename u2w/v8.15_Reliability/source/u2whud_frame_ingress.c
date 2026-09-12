/* U2W v8.14 iPhone frame ingress: persistent TCP 15331, [u32 BE length][JPEG] */
typedef unsigned int u32; typedef unsigned short u16; typedef unsigned long size_t; typedef long ssize_t;
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; unsigned char zero[8]; };
#define SYS_exit 1
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_unlink 10
#define SYS_rename 38
#define SYS_socket 281
#define SYS_bind 282
#define SYS_listen 284
#define SYS_accept 285
#define AF_INET 2
#define SOCK_STREAM 1
#define O_WRONLY 1
#define O_CREAT 64
#define O_TRUNC 512
static unsigned char framebuf[131072];
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static u16 htons(u16 x){return (u16)((x<<8)|(x>>8));}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static long wr(int fd,const void*p,size_t n){return sc3(SYS_write,fd,(long)p,n);}
static void logmsg(const char*s){wr(1,s,slen(s));}
static int readn(int fd,unsigned char*p,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_read,fd,(long)(p+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int writeall(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=wr(fd,p+o,n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int store_frame(const unsigned char*p,size_t n){
 const char *tmp="/tmp/u2whud_latest.new", *dst="/tmp/u2whud_latest.jpg";
 int f=(int)sc3(SYS_open,(long)tmp,O_WRONLY|O_CREAT|O_TRUNC,0644); if(f<0)return -1;
 if(writeall(f,p,n)<0){sc1(SYS_close,f);sc1(SYS_unlink,(long)tmp);return -1;}
 sc1(SYS_close,f); if(sc2(SYS_rename,(long)tmp,(long)dst)<0){sc1(SYS_unlink,(long)tmp);return -1;} return 0;
}
static void serve(int c){
 unsigned char h[4]; unsigned int frames=0; logmsg("ingress-client-connected\n");
 for(;;){
  if(readn(c,h,4)<0)break;
  u32 n=((u32)h[0]<<24)|((u32)h[1]<<16)|((u32)h[2]<<8)|h[3];
  if(n<128 || n>sizeof(framebuf)){logmsg("invalid-frame-length\n");break;}
  if(readn(c,framebuf,n)<0)break;
  if(framebuf[0]!=0xFF||framebuf[1]!=0xD8||framebuf[n-2]!=0xFF||framebuf[n-1]!=0xD9){logmsg("invalid-jpeg\n");continue;}
  if(store_frame(framebuf,n)==0){frames++; if(frames==1)logmsg("first-live-frame-stored\n");}
 }
 logmsg("ingress-client-closed\n");
}
void _start(void){
 int s=(int)sc3(SYS_socket,AF_INET,SOCK_STREAM,0);if(s<0){logmsg("socket-fail\n");sc1(SYS_exit,20);} struct sockaddr_in a;a.sin_family=AF_INET;a.sin_port=htons(15331);a.sin_addr=0;for(int i=0;i<8;i++)a.zero[i]=0;
 if(sc3(SYS_bind,s,(long)&a,sizeof(a))<0){logmsg("bind-15331-fail\n");sc1(SYS_exit,21);}if(sc2(SYS_listen,s,2)<0){logmsg("listen-fail\n");sc1(SYS_exit,22);}logmsg("frame-ingress-listening-15331\n");
 for(;;){int c=(int)sc3(SYS_accept,s,0,0);if(c<0)continue;serve(c);sc1(SYS_close,c);} }
