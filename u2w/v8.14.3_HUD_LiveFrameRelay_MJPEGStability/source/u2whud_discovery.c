/* U2W v8.14.1 persistent KivicCast discovery responder. */
typedef unsigned int u32; typedef unsigned short u16; typedef unsigned long size_t;
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; unsigned char zero[8]; };
#define SYS_exit 1
#define SYS_write 4
#define SYS_close 6
#define SYS_socket 281
#define SYS_bind 282
#define SYS_sendto 290
#define SYS_recvfrom 292
#define AF_INET 2
#define SOCK_DGRAM 2
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static long sc6(long n,long a,long b,long c,long d,long e,long f){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;register long r5 __asm__("r5")=f;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory");return r0;}
static u16 htons(u16 x){return (u16)((x<<8)|(x>>8));}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static int contains(const char*b,size_t n,const char*s){size_t m=slen(s),i,j;if(m>n)return 0;for(i=0;i+m<=n;i++){for(j=0;j<m&&b[i+j]==s[j];j++);if(j==m)return 1;}return 0;}
static void logmsg(const char*s){sc3(SYS_write,1,(long)s,slen(s));}
void _start(void){
 int u=(int)sc3(SYS_socket,AF_INET,SOCK_DGRAM,0);if(u<0){logmsg("udp-socket-fail\n");sc1(SYS_exit,10);}struct sockaddr_in a;a.sin_family=AF_INET;a.sin_port=htons(15320);a.sin_addr=0;for(int i=0;i<8;i++)a.zero[i]=0;if(sc3(SYS_bind,u,(long)&a,sizeof(a))<0){logmsg("udp-bind-fail\n");sc1(SYS_exit,11);}logmsg("persistent-discovery-listening-15320\n");
 char b[1024];struct sockaddr_in peer;u32 plen=sizeof(peer);long n;static const char desc[]="{\"streamType\":\"http\",\"streamURL\":\"http://192.168.50.2:15330\",\"ip\":\"192.168.50.2\",\"port\":15330,\"fps\":5,\"timeout\":5000}";
 for(;;){
  plen=sizeof(peer);
  n=sc6(SYS_recvfrom,u,(long)b,sizeof(b),0,(long)&peer,(long)&plen);
  if(n<=0)continue;
  logmsg("discovery-packet-received\n");
  sc6(SYS_sendto,u,(long)desc,sizeof(desc)-1,0,(long)&peer,plen);
  if(contains(b,(size_t)n,"KVMJPEG/1.0"))logmsg("discovery-replied\n");
  else logmsg("discovery-replied-fallback\n");
 }
}
