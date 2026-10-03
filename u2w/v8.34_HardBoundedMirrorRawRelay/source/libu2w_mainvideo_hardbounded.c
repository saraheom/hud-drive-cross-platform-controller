/* U2W v8.34 hard-bounded lossless passive main-CarPlay-video mirror.
 * Derived only from the exact field-proven v8.11 source.
 *
 * v8.34 preserves the real AppleCarPlay write path and keeps the mirror passive. It
 * removes the last SPS-dependent resource hazard: the mirror rotates at an ordinary
 * successful AppleCarPlay write boundary whenever the current inode would exceed 8 MiB.
 * No H.264 parser or GOP cache is required. It also passively unlatches the selected
 * source when that exact fd closes so a later genuine SPS-bearing fd can be selected.
 *
 * Original v8.11 provenance:
 * Target: Carlinkit U2W 2021.03.06.1343, AppleCarPlay stock SHA1
 * bc9618df3f957a3e381646dc576e008be27725da.
 *
 * This LD_PRELOAD shim is intentionally passive. It observes outbound H.264
 * written by AppleCarPlay and mirrors the dominant TX H.264 fd into a bounded
 * Annex-B file in /tmp. It never changes, consumes, delays, or injects CarPlay
 * traffic. The rolling mirror is hard-bounded near 8 MiB independent of SPS/IDR cadence. A
 * reader holding the old inode drains it to EOF and then reopens the atomically-swapped
 * new generation. Rotation occurs only between successful AppleCarPlay write calls, so
 * concatenating old+new generations is byte-identical to the mirrored write stream.
 */
typedef unsigned int size_t;
typedef int ssize_t;
typedef unsigned int socklen_t;
struct iovec { void *iov_base; size_t iov_len; };
struct msghdr { void *msg_name; socklen_t msg_namelen; struct iovec *msg_iov; size_t msg_iovlen; void *msg_control; size_t msg_controllen; int msg_flags; };
extern void *dlsym(void *, const char *);
extern int open(const char *, int, ...);
extern int close(int);
extern int rename(const char *, const char *);
extern int unlink(const char *);
extern int snprintf(char *, size_t, const char *, ...);
#define RTLD_NEXT ((void *)-1)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_APPEND 02000
#define ROTATE_AT (8U*1024U*1024U)
#define STATUS_EVERY 256U
#define LIVE_PATH "/tmp/u2w_mainvideo_live.h264"
#define LIVE_NEXT "/tmp/u2w_mainvideo_live.next"
#define STATUS_PATH "/tmp/u2w_mainvideo_status.txt"
#define STATUS_TMP  "/tmp/u2w_mainvideo_status.txt.tmp"

typedef ssize_t (*write_fn_t)(int,const void*,size_t);
typedef ssize_t (*send_fn_t)(int,const void*,size_t,int);
typedef ssize_t (*writev_fn_t)(int,const struct iovec*,int);
typedef ssize_t (*sendmsg_fn_t)(int,const struct msghdr*,int);
typedef size_t (*fwrite_fn_t)(const void*,size_t,size_t,void*);
typedef int (*close_fn_t)(int);
static write_fn_t real_write_fn;
static send_fn_t real_send_fn;
static writev_fn_t real_writev_fn;
static sendmsg_fn_t real_sendmsg_fn;
static fwrite_fn_t real_fwrite_fn;
static close_fn_t real_close_fn;

static int g_guard=0;
static int g_is_apple=0;
static int g_main_fd=-1;
static int g_live_fd=-1;
static unsigned int g_generation=0;
static unsigned int g_file_bytes=0;
static unsigned int g_total_bytes=0;
static unsigned int g_main_writes=0;
static unsigned int g_sps=0,g_pps=0,g_idr=0,g_slice=0;
static unsigned int g_candidate_sps=0;
static unsigned int g_rotation_attempts=0;
static unsigned int g_rotation_success=0;
static unsigned int g_rotation_fallback_append=0;
static unsigned int g_rotation_prefix_preserved=0;
static unsigned int g_mirror_partial_retries=0;
static unsigned int g_mirror_write_failures=0;
static unsigned int g_source_unlatches=0;
static unsigned int g_source_relatches=0;
static unsigned int g_hard_cap_rotations=0;
static unsigned int g_resource_guard_trips=0;

static void ensure_real(void){
 if(!real_write_fn) real_write_fn=(write_fn_t)dlsym(RTLD_NEXT,"write");
 if(!real_send_fn) real_send_fn=(send_fn_t)dlsym(RTLD_NEXT,"send");
 if(!real_writev_fn) real_writev_fn=(writev_fn_t)dlsym(RTLD_NEXT,"writev");
 if(!real_sendmsg_fn) real_sendmsg_fn=(sendmsg_fn_t)dlsym(RTLD_NEXT,"sendmsg");
 if(!real_fwrite_fn) real_fwrite_fn=(fwrite_fn_t)dlsym(RTLD_NEXT,"fwrite");
 if(!real_close_fn) real_close_fn=(close_fn_t)dlsym(RTLD_NEXT,"close");
}
static size_t slen(const char*s){size_t n=0;while(s&&s[n])n++;return n;}
static int contains(const unsigned char*p,size_t n,const char*s){size_t i,j,m=slen(s);if(!m||n<m)return 0;for(i=0;i+m<=n;i++){for(j=0;j<m&&p[i+j]==(unsigned char)s[j];j++){}if(j==m)return 1;}return 0;}
static int start_code_at(const unsigned char*p,size_t n,size_t i,size_t*hdr){
 if(i+3<n&&p[i]==0&&p[i+1]==0&&p[i+2]==0&&p[i+3]==1){*hdr=4;return 1;}
 if(i+2<n&&p[i]==0&&p[i+1]==0&&p[i+2]==1){*hdr=3;return 1;}
 return 0;
}
static size_t first_start(const unsigned char*p,size_t n){size_t i,h;for(i=0;i+4<n;i++)if(start_code_at(p,n,i,&h))return i;return n;}
static unsigned int scan_nals(const unsigned char*p,size_t n,unsigned int*c7,unsigned int*c8,unsigned int*c5,unsigned int*c1){
 size_t i,h;unsigned int hits=0;*c7=*c8=*c5=*c1=0;
 for(i=0;i+4<n;i++)if(start_code_at(p,n,i,&h)){unsigned int t=p[i+h]&31U;if(t==7){(*c7)++;hits++;}else if(t==8){(*c8)++;hits++;}else if(t==5){(*c5)++;hits++;}else if(t==1){(*c1)++;hits++;}i+=h-1;}
 return hits;
}
static void close_live(void){if(g_live_fd>=0){close(g_live_fd);g_live_fd=-1;}}
static int open_live(int truncate){int flags=O_WRONLY|O_CREAT|(truncate?O_TRUNC:O_APPEND);close_live();g_live_fd=open(LIVE_PATH,flags,0644);return g_live_fd>=0;}
static int write_all_real(int fd,const unsigned char*p,size_t n,int track){
 size_t off=0;ensure_real();if(fd<0||!p||!real_write_fn)return 0;
 g_guard=1;
 while(off<n){
   ssize_t r=real_write_fn(fd,p+off,n-off);
   if(r<=0){if(track)g_mirror_write_failures++;g_guard=0;return 0;}
   if((size_t)r<n-off&&track)g_mirror_partial_retries++;
   off+=(size_t)r;
 }
 g_guard=0;return 1;
}
static int append_live_all(const unsigned char*p,size_t n){
 if(!p||!n)return 0;if(g_live_fd<0&&!open_live(0))return 0;
 if(!write_all_real(g_live_fd,p,n,1)){close_live();return 0;}
 g_file_bytes+=(unsigned int)n;g_total_bytes+=(unsigned int)n;return 1;
}
static int rotate_live_atomic(const unsigned char*p,size_t n,size_t prefix){
 int nextfd,oldfd;
 if(!p||!n)return 0;g_rotation_attempts++;
 unlink(LIVE_NEXT);
 nextfd=open(LIVE_NEXT,O_WRONLY|O_CREAT|O_TRUNC,0644);
 if(nextfd<0){g_rotation_fallback_append++;return 0;}
 if(!write_all_real(nextfd,p,n,1)){close(nextfd);unlink(LIVE_NEXT);g_rotation_fallback_append++;return 0;}
 if(rename(LIVE_NEXT,LIVE_PATH)!=0){close(nextfd);unlink(LIVE_NEXT);g_rotation_fallback_append++;return 0;}
 oldfd=g_live_fd;g_live_fd=nextfd;if(oldfd>=0)close(oldfd);
 g_generation++;g_file_bytes=(unsigned int)n;g_total_bytes+=(unsigned int)n;
 g_rotation_success++;if(prefix<n)g_rotation_prefix_preserved+=(unsigned int)prefix;
 return 1;
}
static void write_status(void){
 char b[2048];int fd,pos;if(g_guard)return;g_guard=1;ensure_real();
 pos=snprintf(b,sizeof(b),
  "exporter_active=YES\nexporter_version=v8.34-hard-bounded-lossless-mirror\nprocess=AppleCarPlay\nmain_fd=%d\ngeneration=%u\nsegment_bytes=%u\ntotal_mirrored_bytes=%u\nmain_writes=%u\nsps=%u\npps=%u\nidr=%u\nslice=%u\ncandidate_sps=%u\nrotation_cap_bytes=%u\nrotation_attempts=%u\nrotation_success=%u\nrotation_fallback_append=%u\nhard_cap_rotations=%u\nresource_guard_trips=%u\nmirror_partial_write_retries=%u\nmirror_write_failures=%u\nsource_unlatches=%u\nsource_relatches=%u\nrotation_policy=hard-8MiB-applecarplay-write-boundary-atomic-inode-swap\nmirror_write_policy=write-all\nresource_guard=fail-closed-mainvideo-only\nsource_selection=passive-first-sps-fd-with-close-unlatch\nlive_path=%s\n",
  g_main_fd,g_generation,g_file_bytes,g_total_bytes,g_main_writes,g_sps,g_pps,g_idr,g_slice,g_candidate_sps,(unsigned int)ROTATE_AT,
  g_rotation_attempts,g_rotation_success,g_rotation_fallback_append,g_hard_cap_rotations,g_resource_guard_trips,g_mirror_partial_retries,g_mirror_write_failures,g_source_unlatches,g_source_relatches,LIVE_PATH);
 fd=open(STATUS_TMP,O_WRONLY|O_CREAT|O_TRUNC,0644);if(fd>=0){write_all_real(fd,(const unsigned char*)b,(size_t)pos,0);close(fd);rename(STATUS_TMP,STATUS_PATH);}g_guard=0;
}
static void mirror_main(int fd,const unsigned char*p,size_t n){
 unsigned int c7=0,c8=0,c5=0,c1=0,hits;size_t off=0;int rotate=0;
 if(!g_is_apple||g_guard||fd<0||!p||n<4)return;
 hits=scan_nals(p,n,&c7,&c8,&c5,&c1);
 if(g_main_fd<0){
   if(!c7)return;
   g_candidate_sps++;
   /* On this stock binary the main CarPlay encoder is the sustained outbound
    * H.264 channel. Lock to the first TX fd carrying an SPS. */
   g_main_fd=fd;g_generation=1;g_file_bytes=0;g_source_relatches++;off=first_start(p,n);if(off>=n)return;
   if(!open_live(1))return;
 } else if(fd!=g_main_fd){return;}
 if(n>ROTATE_AT){
   /* A single mirror write larger than the entire hard cap is unexpected. Never
    * let diagnostics consume the adapter's RAM-backed /tmp just to preserve video. */
   g_resource_guard_trips++;g_main_fd=-1;g_source_unlatches++;close_live();unlink(LIVE_PATH);unlink(LIVE_NEXT);write_status();return;
 }
 if(g_file_bytes>0 && (g_file_bytes>=ROTATE_AT || n>ROTATE_AT-g_file_bytes)){
   rotate=1;g_hard_cap_rotations++;
   /* v8.34: rotate at the boundary between two successful AppleCarPlay writes.
    * The complete current write starts the next inode. This requires no SPS and
    * keeps concatenated relay output byte-identical to the mirror input. */
   if(!rotate_live_atomic(p,n,n)){
     /* Resource safety takes priority over MainVideo availability. If /tmp cannot
      * create the bounded next generation, stop this passive mirror session rather
      * than grow the old inode without bound. A later genuine SPS may relatch. */
     g_resource_guard_trips++;g_main_fd=-1;g_source_unlatches++;close_live();unlink(LIVE_PATH);unlink(LIVE_NEXT);write_status();return;
   }
 }else{
   if(g_live_fd<0&&!open_live(0))return;
   if(g_file_bytes==0&&!rotate){size_t s=first_start(p,n);if(s<n)off=s;}
   /* Once locked to the video fd, mirror full subsequent buffers. This preserves
    * slice continuation bytes even if a libc write happens to split a NAL. */
   if(off<n)append_live_all(p+off,n-off);
 }
 g_main_writes++;g_sps+=c7;g_pps+=c8;g_idr+=c5;g_slice+=c1;
 if(c7||c8||c5||(g_main_writes%STATUS_EVERY)==0)write_status();
 (void)hits;
}
static void detect_process(void){char b[128];int fd;ssize_t r;size_t n0=0;ensure_real();fd=open("/proc/self/cmdline",O_RDONLY);if(fd>=0&&real_write_fn){
 /* Avoid depending on the hooked read symbol: /proc cmdline is tiny and the
  * process wrapper exports U2W_MAINVIDEO_LIVE only for AppleCarPlay. */
 close(fd);
 }
 /* The wrapper only preloads this shim into AppleCarPlay, so this flag is safe. */
 g_is_apple=1;
}
__attribute__((constructor)) static void init_live(void){detect_process();unlink(LIVE_PATH);unlink(LIVE_NEXT);unlink(STATUS_PATH);unlink(STATUS_TMP);write_status();}
__attribute__((destructor)) static void fini_live(void){write_status();close_live();}

int close(int fd){int was_main;ensure_real();was_main=(fd==g_main_fd);if(was_main){g_main_fd=-1;g_source_unlatches++;close_live();unlink(LIVE_PATH);unlink(LIVE_NEXT);write_status();}return real_close_fn?real_close_fn(fd):-1;}
ssize_t write(int fd,const void*b,size_t n){ssize_t r;ensure_real();r=real_write_fn?real_write_fn(fd,b,n):-1;if(r>0)mirror_main(fd,(const unsigned char*)b,(size_t)r);return r;}
ssize_t send(int fd,const void*b,size_t n,int f){ssize_t r;ensure_real();r=real_send_fn?real_send_fn(fd,b,n,f):-1;if(r>0)mirror_main(fd,(const unsigned char*)b,(size_t)r);return r;}
ssize_t writev(int fd,const struct iovec*v,int c){ssize_t r;int i;size_t remain;ensure_real();r=real_writev_fn?real_writev_fn(fd,v,c):-1;if(r>0&&v){remain=(size_t)r;for(i=0;i<c&&remain;i++){size_t take=v[i].iov_len<remain?v[i].iov_len:remain;if(v[i].iov_base&&take)mirror_main(fd,(const unsigned char*)v[i].iov_base,take);remain-=take;}}return r;}
ssize_t sendmsg(int fd,const struct msghdr*m,int f){ssize_t r;size_t i,remain;ensure_real();r=real_sendmsg_fn?real_sendmsg_fn(fd,m,f):-1;if(r>0&&m){remain=(size_t)r;for(i=0;i<m->msg_iovlen&&remain;i++){size_t take=m->msg_iov[i].iov_len<remain?m->msg_iov[i].iov_len:remain;if(m->msg_iov[i].iov_base&&take)mirror_main(fd,(const unsigned char*)m->msg_iov[i].iov_base,take);remain-=take;}}return r;}
size_t fwrite(const void*p,size_t s,size_t n,void*st){size_t r;ensure_real();r=real_fwrite_fn?real_fwrite_fn(p,s,n,st):0;/* Main stream was physically observed on fd-backed writes; do not guess a FILE* fd. */return r;}
