/* U2W v8.15 rotation-safe Annex-B H.264 CGI streamer.
 * The v8.11 exporter truncates /tmp/u2w_mainvideo_live.h264 at a fresh SPS
 * after ~12 MiB. BusyBox tail -f can remain parked beyond the new EOF after
 * that truncation. This follower checks the current end offset itself and seeks
 * back to 0 whenever the file generation is truncated, preserving one HTTP
 * response across arbitrarily many exporter generations. */
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
struct timespec { long tv_sec; long tv_nsec; };
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
static unsigned char buf[65536];
static const char path[]="/tmp/u2w_mainvideo_live.h264";
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static int writeall(int fd,const void*p,size_t n){const unsigned char*b=(const unsigned char*)p;size_t o=0;while(o<n){long w=sc3(SYS_write,fd,(long)(b+o),n-o);if(w<=0)return -1;o+=(size_t)w;}return 0;}
static void nap(void){struct timespec t;t.tv_sec=0;t.tv_nsec=100000000;sc2(SYS_nanosleep,(long)&t,0);}
void _start(void){
 static const char hdr[]="Content-Type: video/H264\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nX-U2W-Video-Format: Annex-B-H264\r\nX-U2W-Streamer: v8.15-rotation-safe\r\n\r\n";
 if(writeall(1,hdr,sizeof(hdr)-1)<0)sc1(SYS_exit,0);
 int fd=-1; off_t pos=0;
 for(;;){
   if(fd<0){
     fd=(int)sc3(SYS_open,(long)path,O_RDONLY,0);
     if(fd<0){nap();continue;}
     pos=0;sc3(SYS_lseek,fd,0,SEEK_SET);
   }
   long r=sc3(SYS_read,fd,(long)buf,sizeof(buf));
   if(r>0){
     if(writeall(1,buf,(size_t)r)<0){sc1(SYS_close,fd);sc1(SYS_exit,0);}
     pos+=(off_t)r;continue;
   }
   if(r<0){sc1(SYS_close,fd);fd=-1;nap();continue;}
   /* EOF: detect same-inode O_TRUNC generation rollover. */
   long end=sc3(SYS_lseek,fd,0,SEEK_END);
   if(end>=0 && (off_t)end<pos){pos=0;sc3(SYS_lseek,fd,0,SEEK_SET);continue;}
   if(end>=0)sc3(SYS_lseek,fd,pos,SEEK_SET);
   nap();
 }
}
