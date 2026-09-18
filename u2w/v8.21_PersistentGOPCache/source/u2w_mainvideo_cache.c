/* U2W v8.21 persistent decoder-safe GOP cache daemon.
 *
 * Reads the existing v8.11 /tmp/u2w_mainvideo_live.h264 mirror continuously,
 * including across pathname rotations. The cache file always begins at the
 * latest validated SPS + PPS + IDR and then follows subsequent H.264 NALs.
 * A new HTTP client can therefore bootstrap even when the current exporter
 * generation contains only P-slices.
 *
 * This process never touches AppleCarPlay, never opens its fds, and never
 * modifies Route Guidance / Now Playing. It only tails the already-exported
 * v8.11 rolling file.
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
#define O_WRONLY 1
#define O_CREAT 64
#define O_TRUNC 512
#define O_APPEND 1024
#define SEEK_SET 0
#define SEEK_END 2
#define TAIL_BYTES 64
#define PARSE_CAP (1024*1024)
#define MAX_CACHE_BYTES (48*1024*1024)
static const char live_path[]="/tmp/u2w_mainvideo_live.h264";
static const char cache_path[]="/tmp/u2w_mainvideo_gop_cache.h264";
static const char ready_path[]="/tmp/u2w_mainvideo_cache_ready";
static unsigned char io_buf[65536];
static unsigned char parse_buf[PARSE_CAP];
static size_t parse_len=0;
static unsigned char delivered_tail[TAIL_BYTES], verify_tail[TAIL_BYTES];
static unsigned char sps[256], pps[128];
static size_t sps_len=0,pps_len=0;
static int cache_fd=-1,cache_ready=0;
static off_t cache_bytes=0;

static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static void nap_ms(long ms){struct timespec t;t.tv_sec=ms/1000;t.tv_nsec=(ms%1000)*1000000;sc2(SYS_nanosleep,(long)&t,0);}
static int writeall(int fd,const void*p,size_t n){const unsigned char*b=p;size_t o=0;while(o<n){long w=sc3(SYS_write,fd,(long)(b+o),n-o);if(w<=0)return -1;o+=(size_t)w;}return 0;}
static int eq(const unsigned char*a,const unsigned char*b,size_t n){for(size_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int plausible_profile(unsigned char p){return p==66||p==77||p==88||p==100||p==110||p==122||p==244;}
static void logmsg(const char*s){size_t n=0;while(s[n])n++;writeall(1,s,n);writeall(1,"\n",1);}
static int mark_ready(void){int f=(int)sc3(SYS_open,(long)ready_path,O_WRONLY|O_CREAT|O_TRUNC,0644);if(f<0)return -1;writeall(f,"1\n",2);sc1(SYS_close,f);return 0;}
static void clear_ready(void){/* opening/truncating marker to empty is enough for status; streamer checks cache size too */int f=(int)sc3(SYS_open,(long)ready_path,O_WRONLY|O_CREAT|O_TRUNC,0644);if(f>=0)sc1(SYS_close,f);}
static int cache_open_reset(void){if(cache_fd>=0)sc1(SYS_close,cache_fd);cache_fd=(int)sc3(SYS_open,(long)cache_path,O_WRONLY|O_CREAT|O_TRUNC,0644);cache_bytes=0;cache_ready=0;clear_ready();return cache_fd<0?-1:0;}
static int cache_open_append(void){if(cache_fd>=0)return 0;cache_fd=(int)sc3(SYS_open,(long)cache_path,O_WRONLY|O_CREAT|O_APPEND,0644);return cache_fd<0?-1:0;}
static int write_nal_to_cache(const unsigned char*n,size_t len){static const unsigned char sc[4]={0,0,0,1};if(!cache_ready||cache_bytes>(off_t)MAX_CACHE_BYTES)return 0;if(cache_open_append()<0)return -1;if(writeall(cache_fd,sc,4)<0||writeall(cache_fd,n,len)<0)return -1;cache_bytes+=(off_t)(4+len);return 0;}
static int begin_cache_with_idr(const unsigned char*idr,size_t idr_len){static const unsigned char sc[4]={0,0,0,1};if(!sps_len||!pps_len)return 0;if(cache_open_reset()<0)return -1;if(writeall(cache_fd,sc,4)<0||writeall(cache_fd,sps,sps_len)<0)return -1;if(writeall(cache_fd,sc,4)<0||writeall(cache_fd,pps,pps_len)<0)return -1;if(writeall(cache_fd,sc,4)<0||writeall(cache_fd,idr,idr_len)<0)return -1;cache_bytes=(off_t)(12+sps_len+pps_len+idr_len);cache_ready=1;mark_ready();logmsg("cache-reset-valid-idr");return 0;}
static void process_nal(const unsigned char*n,size_t len){if(len<1||len>512*1024)return;unsigned char h=n[0];if(h&0x80)return;int type=h&0x1f;if(type==7){if(len>=4&&len<=128&&(h&0x60)&&plausible_profile(n[1])){sps_len=len>sizeof(sps)?0:len;if(sps_len)for(size_t i=0;i<len;i++)sps[i]=n[i];}return;}if(type==8){if(len>=2&&len<=64&&(h&0x60)){pps_len=len>sizeof(pps)?0:len;if(pps_len)for(size_t i=0;i<len;i++)pps[i]=n[i];}return;}if(type==5){if((h&0x60)&&len>=32){begin_cache_with_idr(n,len);}return;}if(type==1||type==6||type==9){write_nal_to_cache(n,len);return;}}
static long find_start(const unsigned char*b,size_t n,size_t from,size_t*sc_len){for(size_t i=from;i+3<n;i++){if(b[i]==0&&b[i+1]==0&&b[i+2]==1){*sc_len=3;return (long)i;}if(i+4<n&&b[i]==0&&b[i+1]==0&&b[i+2]==0&&b[i+3]==1){*sc_len=4;return (long)i;}}return -1;}
static void parse_append(const unsigned char*d,size_t n){if(n==0)return;if(n>PARSE_CAP){d+=n-PARSE_CAP;n=PARSE_CAP;parse_len=0;}if(parse_len+n>PARSE_CAP){size_t drop=(parse_len+n)-PARSE_CAP;if(drop>=parse_len)parse_len=0;else{for(size_t i=0;i<parse_len-drop;i++)parse_buf[i]=parse_buf[i+drop];parse_len-=drop;}}for(size_t i=0;i<n;i++)parse_buf[parse_len+i]=d[i];parse_len+=n;size_t sc1len=0;long s1=find_start(parse_buf,parse_len,0,&sc1len);if(s1<0){if(parse_len>8){for(size_t i=0;i<8;i++)parse_buf[i]=parse_buf[parse_len-8+i];parse_len=8;}return;}size_t cur=(size_t)s1;size_t curlen=sc1len;for(;;){size_t nextlen=0;long s2=find_start(parse_buf,parse_len,cur+curlen,&nextlen);if(s2<0)break;size_t payload=cur+curlen;size_t end=(size_t)s2;while(end>payload&&parse_buf[end-1]==0)end--;if(end>payload)process_nal(parse_buf+payload,end-payload);cur=(size_t)s2;curlen=nextlen;}if(cur>0){size_t remain=parse_len-cur;for(size_t i=0;i<remain;i++)parse_buf[i]=parse_buf[cur+i];parse_len=remain;}}
static int read_exact(int fd,unsigned char*out,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_read,fd,(long)(out+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int capture_tail(int fd,off_t pos,size_t*tail_len){size_t n=(size_t)(pos<(off_t)TAIL_BYTES?pos:(off_t)TAIL_BYTES);*tail_len=n;if(n==0)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return -1;if(read_exact(fd,delivered_tail,n)<0)return -1;return sc3(SYS_lseek,fd,pos,SEEK_SET)<0?-1:0;}
static int same_generation(int fd,off_t pos,size_t tail_len){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end<0||(off_t)end<pos)return 0;if(tail_len==0)return pos==0;if(pos<(off_t)tail_len)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)tail_len,SEEK_SET)<0)return 0;if(read_exact(fd,verify_tail,tail_len)<0)return 0;return eq(delivered_tail,verify_tail,tail_len);}
void _start(void){int fd=-1;off_t pos=0;size_t tail_len=0;clear_ready();logmsg("u2w-mainvideo-cache-v8.21-start");for(;;){if(fd<0){fd=(int)sc3(SYS_open,(long)live_path,O_RDONLY,0);if(fd<0){nap_ms(100);continue;}if(!same_generation(fd,pos,tail_len)){pos=0;tail_len=0;sc3(SYS_lseek,fd,0,SEEK_SET);logmsg("live-generation-change");}else sc3(SYS_lseek,fd,pos,SEEK_SET);}long r=sc3(SYS_read,fd,(long)io_buf,sizeof(io_buf));if(r>0){parse_append(io_buf,(size_t)r);pos+=(off_t)r;continue;}if(capture_tail(fd,pos,&tail_len)<0)tail_len=0;sc1(SYS_close,fd);fd=-1;nap_ms(50);} }
