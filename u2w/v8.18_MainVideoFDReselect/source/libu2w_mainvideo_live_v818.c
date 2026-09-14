/*
 * U2W v8.18 MainVideo fd-reselection exporter.
 *
 * Loaded only into the saved stock AppleCarPlay process by the existing v8.11
 * wrapper.  It passively observes outbound write/send/writev/sendmsg payloads,
 * mirrors only a validated Annex-B H.264 stream, and reselects the stream when
 * the original fd is closed/reused or stops carrying plausible H.264.
 *
 * No CarPlay bytes are modified, consumed, delayed, or injected.
 */
typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long size_t;
typedef long ssize_t;

struct iovec { void *iov_base; size_t iov_len; };
struct msghdr {
    void *msg_name;
    int msg_namelen;
    struct iovec *msg_iov;
    size_t msg_iovlen;
    void *msg_control;
    size_t msg_controllen;
    int msg_flags;
};

#define NULL ((void*)0)
#define RTLD_NEXT ((void*)-1L)
#define O_WRONLY 1
#define O_CREAT  0100
#define O_TRUNC  01000
#define O_APPEND 02000
#define LIVE_CAP_BYTES (12u*1024u*1024u)
#define MAIN_NO_H264_BYTES (2u*1024u*1024u)
#define CANDIDATE_MAX_BYTES (4u*1024u*1024u)
#define CANDIDATE_MAX_CALLS 800u
#define OTHER_FD_SWITCH_STALE_CALLS 128u
#define MAX_IOV 128

extern void *dlsym(void *, const char *);
extern int open(const char *, int, ...);
extern int rename(const char *, const char *);
extern int unlink(const char *);
extern int snprintf(char *, size_t, const char *, ...);

static ssize_t (*real_write_fn)(int,const void*,size_t);
static ssize_t (*real_send_fn)(int,const void*,size_t,int);
static ssize_t (*real_writev_fn)(int,const struct iovec*,int);
static ssize_t (*real_sendmsg_fn)(int,const struct msghdr*,int);
static size_t (*real_fwrite_fn)(const void*,size_t,size_t,void*);
static int (*real_close_fn)(int);

static volatile int g_resolving;
static volatile int g_guard;
static volatile int g_lock;

static int g_live_fd=-1;
static int g_main_fd=-1;
static int g_candidate_fd=-1;
static u32 g_candidate_stage;
static u32 g_candidate_bytes;
static u32 g_candidate_calls;
static u32 g_main_no_h264_bytes;
static u32 g_main_bad_ps;
static u32 g_generation;
static u32 g_file_bytes;
static u32 g_total_bytes;
static u32 g_main_writes;
static u32 g_sps;
static u32 g_pps;
static u32 g_idr;
static u32 g_slice;
static u32 g_valid_nals;
static u32 g_bad_parameter_sets;
static u32 g_fd_promotions;
static u32 g_fd_switches;
static u32 g_fd_invalidations;
static u32 g_fd_close_invalidations;
static u32 g_candidate_abandons;
static u32 g_pending_reselect;
static u32 g_observe_calls;
static u32 g_main_last_h264_call;
static u32 g_last_reason;

static const char LIVE_PATH[]="/tmp/u2w_mainvideo_live.h264";
static const char STATUS_PATH[]="/tmp/u2w_mainvideo_status.txt";
static const char STATUS_TMP[]="/tmp/u2w_mainvideo_status.txt.tmp";

static void lock_state(void){ while(__sync_lock_test_and_set(&g_lock,1)){} __sync_synchronize(); }
static void unlock_state(void){ __sync_synchronize(); __sync_lock_release(&g_lock); }

static void ensure_real(void){
    if(g_resolving) return;
    g_resolving=1;
    if(!real_write_fn) real_write_fn=(ssize_t(*)(int,const void*,size_t))dlsym(RTLD_NEXT,"write");
    if(!real_send_fn) real_send_fn=(ssize_t(*)(int,const void*,size_t,int))dlsym(RTLD_NEXT,"send");
    if(!real_writev_fn) real_writev_fn=(ssize_t(*)(int,const struct iovec*,int))dlsym(RTLD_NEXT,"writev");
    if(!real_sendmsg_fn) real_sendmsg_fn=(ssize_t(*)(int,const struct msghdr*,int))dlsym(RTLD_NEXT,"sendmsg");
    if(!real_fwrite_fn) real_fwrite_fn=(size_t(*)(const void*,size_t,size_t,void*))dlsym(RTLD_NEXT,"fwrite");
    if(!real_close_fn) real_close_fn=(int(*)(int))dlsym(RTLD_NEXT,"close");
    g_resolving=0;
}

static void close_live(void){
    ensure_real();
    if(g_live_fd>=0 && real_close_fn){ real_close_fn(g_live_fd); g_live_fd=-1; }
}

static int open_live(int truncate){
    int fd;
    close_live();
    fd=open(LIVE_PATH,O_WRONLY|O_CREAT|(truncate?O_TRUNC:O_APPEND),0644);
    if(fd<0) return 0;
    g_live_fd=fd;
    if(truncate){ g_file_bytes=0; g_generation++; }
    return 1;
}

static int write_live(const u8 *p,size_t n){
    ssize_t w;
    ensure_real();
    if(!p || n==0 || !real_write_fn) return 0;
    if(g_live_fd<0 && !open_live(0)) return 0;
    g_guard=1;
    w=real_write_fn(g_live_fd,p,n);
    g_guard=0;
    if(w>0){ g_file_bytes+=(u32)w; g_total_bytes+=(u32)w; return (int)w; }
    close_live();
    return 0;
}

static int profile_ok(u8 p){
    return p==66 || p==77 || p==88 || p==100 || p==110 || p==118 || p==122 || p==128 || p==134 || p==135 || p==138 || p==139 || p==244;
}

static int start_code(const u8 *b,size_t n,size_t i,size_t *sc){
    if(i+3<=n && b[i]==0 && b[i+1]==0 && b[i+2]==1){ *sc=3; return 1; }
    if(i+4<=n && b[i]==0 && b[i+1]==0 && b[i+2]==0 && b[i+3]==1){ *sc=4; return 1; }
    return 0;
}

struct scan_result {
    int sps,pps,idr,slice;
    u32 valid_nals;
    u32 bad_ps;
    size_t first_sps;
};

static struct scan_result scan_annexb(const u8 *b,size_t n){
    struct scan_result r; size_t i=0;
    r.sps=r.pps=r.idr=r.slice=0; r.valid_nals=r.bad_ps=0; r.first_sps=n;
    while(i+4<=n){
        size_t sc=0, hdr, j, next=n, sc2=0, nal_len; int complete=0; u8 h,type;
        if(!start_code(b,n,i,&sc)){ i++; continue; }
        hdr=i+sc; if(hdr>=n){ break; }
        h=b[hdr];
        if(h&0x80){ i=hdr+1; continue; }
        type=h&31;
        j=hdr+1;
        while(j+3<=n){ if(start_code(b,n,j,&sc2)){ next=j; complete=1; break; } j++; }
        nal_len=(next>hdr)?(next-hdr):0;
        if(type==7){
            int good=0;
            if(complete && nal_len>=5 && nal_len<=128 && hdr+3<n){
                u8 profile=b[hdr+1], level=b[hdr+3];
                if(profile_ok(profile) && level>=9 && level<=62) good=1;
            }
            if(good){ r.sps=1; r.valid_nals++; if(i<r.first_sps) r.first_sps=i; }
            else if(complete && nal_len>128) r.bad_ps++;
        }else if(type==8){
            if(complete && nal_len>=2 && nal_len<=64){ r.pps=1; r.valid_nals++; }
            else if(complete && nal_len>64) r.bad_ps++;
        }else if(type==5){
            if(nal_len>=16){ r.idr=1; r.valid_nals++; }
        }else if(type==1){
            if(nal_len>=8){ r.slice=1; r.valid_nals++; }
        }else if(type==6 || type==9){
            if(nal_len>=2) r.valid_nals++;
        }
        if(complete) i=next; else break;
    }
    return r;
}

static void write_status(void){
    char b[2300]; int n,fd;
    ensure_real(); if(!real_write_fn) return;
    n=snprintf(b,sizeof(b),
        "exporter_active=YES\n"
        "exporter_version=v8.18-mainvideo-fd-reselect\n"
        "process=AppleCarPlay\n"
        "main_fd=%d\n"
        "candidate_fd=%d\n"
        "candidate_stage=%u\n"
        "generation=%u\n"
        "segment_bytes=%u\n"
        "total_mirrored_bytes=%u\n"
        "main_writes=%u\n"
        "sps=%u\npps=%u\nidr=%u\nslice=%u\n"
        "valid_nals=%u\n"
        "bad_parameter_sets=%u\n"
        "main_bytes_since_valid_h264=%u\n"
        "fd_promotions=%u\nfd_switches=%u\nfd_invalidations=%u\nfd_close_invalidations=%u\n"
        "candidate_abandons=%u\nobserve_calls=%u\nmain_last_h264_call=%u\nlast_reason=%u\n"
        "rotation_cap_bytes=%u\n"
        "selection_policy=validated-sps-pps-idr+close-hook+content-watchdog\n"
        "live_path=%s\n",
        g_main_fd,g_candidate_fd,g_candidate_stage,g_generation,g_file_bytes,g_total_bytes,g_main_writes,
        g_sps,g_pps,g_idr,g_slice,g_valid_nals,g_bad_parameter_sets,g_main_no_h264_bytes,
        g_fd_promotions,g_fd_switches,g_fd_invalidations,g_fd_close_invalidations,
        g_candidate_abandons,g_observe_calls,g_main_last_h264_call,g_last_reason,LIVE_CAP_BYTES,LIVE_PATH);
    if(n<=0) return; if(n>(int)sizeof(b)) n=(int)sizeof(b);
    fd=open(STATUS_TMP,O_WRONLY|O_CREAT|O_TRUNC,0644);
    if(fd<0) return;
    g_guard=1; real_write_fn(fd,b,(size_t)n); g_guard=0;
    if(real_close_fn) real_close_fn(fd);
    rename(STATUS_TMP,STATUS_PATH);
}

static void abandon_candidate(u32 reason){
    if(g_candidate_fd>=0) g_candidate_abandons++;
    g_candidate_fd=-1; g_candidate_stage=0; g_candidate_bytes=0; g_candidate_calls=0; g_last_reason=reason;
}

static void invalidate_main(u32 reason,int from_close){
    if(g_main_fd>=0){
        g_fd_invalidations++; if(from_close) g_fd_close_invalidations++;
        g_pending_reselect=1;
    }
    g_main_fd=-1; g_main_no_h264_bytes=0; g_main_bad_ps=0; g_last_reason=reason;
    abandon_candidate(reason);
    close_live();
}

static void start_candidate(int fd,const u8 *b,size_t n,struct scan_result s){
    size_t off=s.first_sps;
    if(off>=n) return;
    abandon_candidate(0);
    g_candidate_fd=fd; g_candidate_stage=1; g_candidate_bytes=0; g_candidate_calls=0;
    if(!open_live(1)){ abandon_candidate(101); return; }
    write_live(b+off,n-off);
    g_candidate_bytes+=(u32)(n-off); g_candidate_calls++;
    if(s.pps) g_candidate_stage=2;
    if(g_candidate_stage>=2 && s.idr) g_candidate_stage=3;
}

static void promote_candidate(int fd){
    int old=g_main_fd;
    g_main_fd=fd; g_candidate_fd=-1; g_candidate_stage=0; g_candidate_bytes=0; g_candidate_calls=0;
    g_main_no_h264_bytes=0; g_main_bad_ps=0; g_main_last_h264_call=g_observe_calls;
    g_fd_promotions++; if((old>=0 && old!=fd) || g_pending_reselect) g_fd_switches++;
    g_pending_reselect=0;
    g_last_reason=200;
}

static void observe_outbound(int fd,const void *vp,size_t n){
    const u8 *b=(const u8*)vp; struct scan_result s; int has_h264;
    if(g_guard || !b || n<4 || fd<0) return;
    lock_state();
    g_observe_calls++;
    s=scan_annexb(b,n);
    has_h264=(s.valid_nals>0);
    g_bad_parameter_sets+=s.bad_ps;

    if(g_main_fd>=0 && fd==g_main_fd){
        g_main_writes++;
        if(has_h264){
            g_main_no_h264_bytes=0; g_main_last_h264_call=g_observe_calls;
            if(s.sps || s.pps) g_main_bad_ps=0;
        }else{
            if(n>0xffffffffu-g_main_no_h264_bytes) g_main_no_h264_bytes=0xffffffffu; else g_main_no_h264_bytes+=(u32)n;
        }
        if(s.bad_ps){ g_main_bad_ps+=s.bad_ps; }
        if(g_main_bad_ps>=2 || g_main_no_h264_bytes>=MAIN_NO_H264_BYTES){
            invalidate_main(g_main_bad_ps>=2?301:302,0);
            write_status(); unlock_state(); return;
        }
        if(g_file_bytes>=LIVE_CAP_BYTES && s.sps && s.first_sps<n){
            if(open_live(1)) write_live(b+s.first_sps,n-s.first_sps);
        }else{
            write_live(b,n);
        }
        g_sps+=(u32)s.sps; g_pps+=(u32)s.pps; g_idr+=(u32)s.idr; g_slice+=(u32)s.slice; g_valid_nals+=s.valid_nals;
        if(s.sps||s.pps||s.idr || (g_main_writes&255u)==0) write_status();
        unlock_state(); return;
    }

    /* If another fd presents a complete decoder bootstrap while the selected fd
     * has gone quiet, prefer the newly proven video stream even if close() was not
     * observed (dup/shutdown/reallocation edge case). */
    if(g_main_fd>=0 && fd!=g_main_fd){
        if(s.sps && s.pps && s.idr && (g_observe_calls-g_main_last_h264_call)>=OTHER_FD_SWITCH_STALE_CALLS){
            invalidate_main(303,0);
            start_candidate(fd,b,n,s);
            if(g_candidate_stage>=3){ promote_candidate(fd); }
            g_sps+=(u32)s.sps; g_pps+=(u32)s.pps; g_idr+=(u32)s.idr; g_slice+=(u32)s.slice; g_valid_nals+=s.valid_nals;
            write_status();
        }
        unlock_state(); return;
    }

    if(g_candidate_fd<0){
        if(s.sps){
            start_candidate(fd,b,n,s);
            g_sps+=(u32)s.sps; g_pps+=(u32)s.pps; g_idr+=(u32)s.idr; g_slice+=(u32)s.slice; g_valid_nals+=s.valid_nals;
            if(g_candidate_stage>=3) promote_candidate(fd);
            write_status();
        }
        unlock_state(); return;
    }

    if(fd==g_candidate_fd){
        g_candidate_calls++; g_candidate_bytes+=(u32)n;
        if(s.bad_ps>=2){ abandon_candidate(401); close_live(); write_status(); unlock_state(); return; }
        write_live(b,n);
        if(s.sps) g_candidate_stage=1;
        if(g_candidate_stage>=1 && s.pps) g_candidate_stage=2;
        if(g_candidate_stage>=2 && s.idr) g_candidate_stage=3;
        g_sps+=(u32)s.sps; g_pps+=(u32)s.pps; g_idr+=(u32)s.idr; g_slice+=(u32)s.slice; g_valid_nals+=s.valid_nals;
        if(g_candidate_stage>=3){ promote_candidate(fd); write_status(); unlock_state(); return; }
        if(g_candidate_bytes>CANDIDATE_MAX_BYTES || g_candidate_calls>CANDIDATE_MAX_CALLS){
            abandon_candidate(402); close_live(); write_status(); unlock_state(); return;
        }
    }else if(s.sps && s.pps && s.idr){
        /* A stronger one-buffer candidate supersedes a stalled provisional one. */
        abandon_candidate(403); close_live(); start_candidate(fd,b,n,s);
        if(g_candidate_stage>=3) promote_candidate(fd);
        g_sps+=(u32)s.sps; g_pps+=(u32)s.pps; g_idr+=(u32)s.idr; g_slice+=(u32)s.slice; g_valid_nals+=s.valid_nals;
        write_status();
    }
    unlock_state();
}

__attribute__((constructor)) static void init_live(void){
    ensure_real();
    unlink(LIVE_PATH); unlink(STATUS_PATH); unlink(STATUS_TMP);
    write_status();
}

__attribute__((destructor)) static void fini_live(void){
    lock_state(); write_status(); close_live(); unlock_state();
}

ssize_t write(int fd,const void *buf,size_t n){
    ssize_t r; ensure_real(); if(!real_write_fn) return -1;
    r=real_write_fn(fd,buf,n); if(r>0) observe_outbound(fd,buf,(size_t)r); return r;
}

ssize_t send(int fd,const void *buf,size_t n,int flags){
    ssize_t r; ensure_real(); if(!real_send_fn) return -1;
    r=real_send_fn(fd,buf,n,flags); if(r>0) observe_outbound(fd,buf,(size_t)r); return r;
}

ssize_t writev(int fd,const struct iovec *iov,int iovcnt){
    ssize_t r; size_t remain; int i; ensure_real(); if(!real_writev_fn) return -1;
    r=real_writev_fn(fd,iov,iovcnt); if(r<=0 || g_guard || !iov || iovcnt<=0 || iovcnt>MAX_IOV) return r;
    remain=(size_t)r;
    for(i=0;i<iovcnt && remain;i++){
        size_t take=iov[i].iov_len<remain?iov[i].iov_len:remain;
        if(iov[i].iov_base && take) observe_outbound(fd,iov[i].iov_base,take);
        remain-=take;
    }
    return r;
}

ssize_t sendmsg(int fd,const struct msghdr *msg,int flags){
    ssize_t r; size_t remain; size_t i; ensure_real(); if(!real_sendmsg_fn) return -1;
    r=real_sendmsg_fn(fd,msg,flags); if(r<=0 || g_guard || !msg || !msg->msg_iov || msg->msg_iovlen==0 || msg->msg_iovlen>MAX_IOV) return r;
    remain=(size_t)r;
    for(i=0;i<msg->msg_iovlen && remain;i++){
        size_t take=msg->msg_iov[i].iov_len<remain?msg->msg_iov[i].iov_len:remain;
        if(msg->msg_iov[i].iov_base && take) observe_outbound(fd,msg->msg_iov[i].iov_base,take);
        remain-=take;
    }
    return r;
}

size_t fwrite(const void *ptr,size_t size,size_t nmemb,void *stream){
    ensure_real(); if(!real_fwrite_fn) return 0;
    /* stdio ultimately reaches one of the fd-based hooks above on this runtime;
     * do not mirror here as well or the stream would be duplicated. */
    return real_fwrite_fn(ptr,size,nmemb,stream);
}

int close(int fd){
    int r; ensure_real(); if(!real_close_fn) return -1;
    if(!g_guard){
        lock_state();
        if(fd==g_main_fd){ invalidate_main(501,1); write_status(); }
        else if(fd==g_candidate_fd){ abandon_candidate(502); close_live(); write_status(); }
        unlock_state();
    }
    r=real_close_fn(fd); return r;
}
