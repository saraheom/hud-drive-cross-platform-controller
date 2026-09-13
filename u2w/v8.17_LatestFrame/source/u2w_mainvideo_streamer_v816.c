/* U2W v8.16 live-edge Annex-B H.264 CGI streamer.
 *
 * v8.15 fixed same-fd O_TRUNC stalls, but a client reconnect still started at
 * byte zero and an exporter generation rollover can replace/reopen the path,
 * leaving the CGI on a stale inode. v8.16 deliberately reopens the live path
 * at EOF and bootstraps each fresh connection/generation with the latest SPS,
 * PPS, and newest IDR, then follows only bytes from that IDR onward.
 */
typedef unsigned long size_t;
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
static int writeall(int fd,const void*p,size_t n){const unsigned char*b=(const unsigned char*)p;size_t o=0;while(o<n){long w=sc3(SYS_write,fd,(long)(b+o),n-o);if(w<=0)return -1;o+=(size_t)w;}return 0;}
static void nap_ms(long ms){struct timespec t;t.tv_sec=ms/1000;t.tv_nsec=(ms%1000)*1000000;sc2(SYS_nanosleep,(long)&t,0);}

/* Scan the current segment. At every IDR remember the most recent SPS/PPS
 * that preceded it. At EOF this therefore describes the newest decoder-safe
 * GOP without forcing playback from the parameter-set location. */
static int newest_gop(int fd,off_t*osps,off_t*opps,off_t*oidr){
    off_t absolute=0,last_sps=-1,last_pps=-1,best_sps=-1,best_pps=-1,best_idr=-1;
    int zeros=0,expect_header=0; off_t pending_start=-1;
    if(sc3(SYS_lseek,fd,0,SEEK_SET)<0)return -1;
    for(;;){
        long r=sc3(SYS_read,fd,(long)buf,sizeof(buf));
        if(r<0)return -1;
        if(r==0)break;
        for(long i=0;i<r;i++,absolute++){
            unsigned char b=buf[i];
            if(expect_header){
                int type=b&0x1f;
                if(type==7)last_sps=pending_start;
                else if(type==8)last_pps=pending_start;
                else if(type==5 && last_sps>=0 && last_pps>=0){
                    best_sps=last_sps;best_pps=last_pps;best_idr=pending_start;
                }
                expect_header=0;
            }
            if(b==0){zeros++;continue;}
            if(b==1 && zeros>=2){int z=zeros>=3?3:2;pending_start=absolute-z;expect_header=1;}
            zeros=0;
        }
    }
    if(best_idr<0)return -1;
    *osps=best_sps;*opps=best_pps;*oidr=best_idr;return 0;
}

/* Return the next Annex-B start-code offset after `start`, or current EOF. */
static off_t next_start(int fd,off_t start){
    off_t pos=start+3,absolute=pos; int zeros=0;
    if(sc3(SYS_lseek,fd,pos,SEEK_SET)<0)return -1;
    for(;;){
        long r=sc3(SYS_read,fd,(long)buf,sizeof(buf));
        if(r<0)return -1;
        if(r==0){long e=sc3(SYS_lseek,fd,0,SEEK_END);return e<0?-1:(off_t)e;}
        for(long i=0;i<r;i++,absolute++){
            unsigned char b=buf[i];
            if(b==0){zeros++;continue;}
            if(b==1 && zeros>=2){int z=zeros>=3?3:2;return absolute-z;}
            zeros=0;
        }
    }
}

static int send_range(int fd,off_t start,off_t end){
    if(end<=start)return -1;
    if(sc3(SYS_lseek,fd,start,SEEK_SET)<0)return -1;
    off_t remain=end-start;
    while(remain>0){
        size_t want=(size_t)(remain>(off_t)sizeof(buf)?sizeof(buf):remain);
        long r=sc3(SYS_read,fd,(long)buf,want);
        if(r<=0)return -1;
        if(writeall(1,buf,(size_t)r)<0)return -1;
        remain-=(off_t)r;
    }
    return 0;
}

/* Send parameter sets only, then position the fd at the newest IDR. */
static int bootstrap_live_edge(int fd,off_t*pos){
    off_t sps,pps,idr;
    if(newest_gop(fd,&sps,&pps,&idr)<0)return -1;
    off_t sps_end=next_start(fd,sps); if(sps_end<0)return -1;
    off_t pps_end=next_start(fd,pps); if(pps_end<0)return -1;
    if(send_range(fd,sps,sps_end)<0)return -1;
    if(send_range(fd,pps,pps_end)<0)return -1;
    if(sc3(SYS_lseek,fd,idr,SEEK_SET)<0)return -1;
    *pos=idr;return 0;
}

void _start(void){
 static const char hdr[]="Content-Type: video/H264\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nX-U2W-Video-Format: Annex-B-H264\r\nX-U2W-Streamer: v8.16-live-edge-gop\r\n\r\n";
 if(writeall(1,hdr,sizeof(hdr)-1)<0)sc1(SYS_exit,0);
 int fd=-1;off_t pos=0;int bootstrap=1;
 for(;;){
   if(fd<0){
     fd=(int)sc3(SYS_open,(long)path,O_RDONLY,0);
     if(fd<0){nap_ms(100);continue;}
     if(bootstrap){
       if(bootstrap_live_edge(fd,&pos)<0){sc1(SYS_close,fd);fd=-1;nap_ms(100);continue;}
       bootstrap=0;
     }else{
       long end=sc3(SYS_lseek,fd,0,SEEK_END);
       if(end<0){sc1(SYS_close,fd);fd=-1;nap_ms(100);continue;}
       if((off_t)end<pos){
         /* New exporter generation/path: seed decoder from that generation's
          * parameter sets and newest IDR instead of replaying byte zero. */
         if(bootstrap_live_edge(fd,&pos)<0){sc1(SYS_close,fd);fd=-1;nap_ms(100);continue;}
       }else sc3(SYS_lseek,fd,pos,SEEK_SET);
     }
   }
   long r=sc3(SYS_read,fd,(long)buf,sizeof(buf));
   if(r>0){if(writeall(1,buf,(size_t)r)<0){sc1(SYS_close,fd);sc1(SYS_exit,0);}pos+=(off_t)r;continue;}
   /* Always reopen the pathname at EOF. If the exporter replaced the file,
    * the next iteration sees the new object instead of a stale inode. */
   sc1(SYS_close,fd);fd=-1;nap_ms(100);
 }
}
