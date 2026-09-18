/* U2W v8.21 fail-fast CGI streamer for the persistent decoder-safe GOP cache. */
typedef unsigned long size_t; typedef long off_t; struct timespec{long tv_sec;long tv_nsec;};
#define SYS_exit 1
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_lseek 19
#define SYS_nanosleep 162
#define O_RDONLY 0
#define SEEK_SET 0
#define SEEK_END 2
#define TAIL_BYTES 64
static const char cache_path[]="/tmp/u2w_mainvideo_gop_cache.h264";
static unsigned char buf[65536],tail[TAIL_BYTES],verify[TAIL_BYTES];
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static int writeall(int fd,const void*p,size_t n){const unsigned char*b=p;size_t o=0;while(o<n){long w=sc3(SYS_write,fd,(long)(b+o),n-o);if(w<=0)return -1;o+=(size_t)w;}return 0;}
static void nap_ms(long ms){struct timespec t;t.tv_sec=ms/1000;t.tv_nsec=(ms%1000)*1000000;sc2(SYS_nanosleep,(long)&t,0);}
static int eq(const unsigned char*a,const unsigned char*b,size_t n){for(size_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int read_exact(int fd,unsigned char*out,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_read,fd,(long)(out+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int capture_tail(int fd,off_t pos,size_t*len){size_t n=(size_t)(pos<(off_t)TAIL_BYTES?pos:(off_t)TAIL_BYTES);*len=n;if(!n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return -1;if(read_exact(fd,tail,n)<0)return -1;return 0;}
static int same_generation(int fd,off_t pos,size_t n){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end<0||(off_t)end<pos)return 0;if(n==0)return pos==0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return 0;if(read_exact(fd,verify,n)<0)return 0;return eq(tail,verify,n);}
static int open_ready_cache(void){for(int i=0;i<20;i++){int fd=(int)sc3(SYS_open,(long)cache_path,O_RDONLY,0);if(fd>=0){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end>64){sc3(SYS_lseek,fd,0,SEEK_SET);return fd;}sc1(SYS_close,fd);}nap_ms(100);}return -1;}
void _start(void){int fd=open_ready_cache();if(fd<0){static const char no[]="Status: 503 Service Unavailable\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nRetry-After: 2\r\nX-U2W-Streamer: v8.21-gop-cache-relay\r\nX-U2W-Cache: not-ready\r\n\r\nMainVideo GOP cache not ready\n";writeall(1,no,sizeof(no)-1);sc1(SYS_exit,0);}static const char hdr[]="Content-Type: video/H264\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nX-U2W-Video-Format: Annex-B-H264\r\nX-U2W-Streamer: v8.21-gop-cache-relay\r\nX-U2W-Cache: ready\r\n\r\n";if(writeall(1,hdr,sizeof(hdr)-1)<0)sc1(SYS_exit,0);off_t pos=0;size_t tail_len=0;int idle_polls=0;for(;;){if(sc3(SYS_lseek,fd,pos,SEEK_SET)<0){sc1(SYS_close,fd);sc1(SYS_exit,0);}long r=sc3(SYS_read,fd,(long)buf,sizeof(buf));if(r>0){idle_polls=0;if(writeall(1,buf,(size_t)r)<0){sc1(SYS_close,fd);sc1(SYS_exit,0);}pos+=(off_t)r;continue;}if(++idle_polls>100){sc1(SYS_close,fd);sc1(SYS_exit,0);}capture_tail(fd,pos,&tail_len);sc1(SYS_close,fd);fd=-1;nap_ms(50);fd=(int)sc3(SYS_open,(long)cache_path,O_RDONLY,0);if(fd<0){sc1(SYS_exit,0);}if(!same_generation(fd,pos,tail_len)){pos=0;tail_len=0;} }}
