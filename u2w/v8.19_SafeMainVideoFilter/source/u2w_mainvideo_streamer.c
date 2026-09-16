/* U2W v8.19 safe MainVideo Annex-B H.264 filter/streamer.
 *
 * Safety scope is intentionally narrow: this CGI does NOT preload, hook, patch,
 * signal, restart, or otherwise modify AppleCarPlay.  The validated v8.11
 * exporter remains untouched.  This process only reads the existing rolling
 * /tmp/u2w_mainvideo_live.h264 file and writes a sanitized H.264 byte stream to
 * its own CGI stdout.
 *
 * Field captures showed fd33 contains genuine 800x480 H.264 intermixed with
 * byte sequences that merely resemble Annex-B start codes.  v8.17 could choose
 * those false SPS/PPS/IDR markers as a decoder bootstrap.  v8.19 accepts only:
 *   - syntactically valid SPS describing exactly 800x480,
 *   - PPS referring to the accepted SPS,
 *   - IDR/non-IDR slices referring to the accepted PPS,
 * and emits canonical 4-byte Annex-B start codes.  Everything else is dropped.
 *
 * Generation handling preserves v8.17's delivered-tail fingerprint.  On a
 * rolling-file replacement the filter discards parameter-set state and finds a
 * new validated SPS/PPS/IDR bootstrap.  It never scans or intercepts live
 * AppleCarPlay syscalls.
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
#define TAIL_BYTES 64
#define SCAN_BYTES 32768
#define MAX_NAL_BYTES 131072
#define MAX_PARAM_BYTES 256
#define MAX_RBSP_BYTES 512
#define EXPECT_WIDTH 800
#define EXPECT_HEIGHT 480
#define NO_OFFSET ((off_t)-1)

static unsigned char scanbuf[SCAN_BYTES];
static unsigned char nalbuf[MAX_NAL_BYTES];
static unsigned char rbsp[MAX_RBSP_BYTES];
static unsigned char delivered_tail[TAIL_BYTES];
static unsigned char verify_tail[TAIL_BYTES];
static const unsigned char annexb4[4]={0,0,0,1};
static const char path[]="/tmp/u2w_mainvideo_live.h264";

static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static int writeall(int fd,const void*p,size_t n){const unsigned char*b=(const unsigned char*)p;size_t o=0;while(o<n){long w=sc3(SYS_write,fd,(long)(b+o),n-o);if(w<=0)return -1;o+=(size_t)w;}return 0;}
static void nap_ms(long ms){struct timespec t;t.tv_sec=ms/1000;t.tv_nsec=(ms%1000)*1000000;sc2(SYS_nanosleep,(long)&t,0);}
static int equal_bytes(const unsigned char*a,const unsigned char*b,size_t n){for(size_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int read_exact(int fd,unsigned char*out,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_read,fd,(long)(out+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}

struct br { const unsigned char *p; size_t n; size_t bit; int error; };
static unsigned br_bit(struct br*b){if(b->bit>=b->n*8){b->error=1;return 0;}unsigned v=(b->p[b->bit>>3]>>(7-(b->bit&7)))&1;b->bit++;return v;}
static unsigned br_bits(struct br*b,unsigned n){unsigned v=0;if(n>24){b->error=1;return 0;}for(unsigned i=0;i<n;i++)v=(v<<1)|br_bit(b);return v;}
static unsigned br_ue(struct br*b){unsigned z=0;while(!b->error && br_bit(b)==0){if(++z>24){b->error=1;return 0;}}if(b->error)return 0;return ((1u<<z)-1u)+(z?br_bits(b,z):0u);}
static int br_se(struct br*b){unsigned c=br_ue(b);return (c&1)?(int)((c+1)>>1):-(int)(c>>1);}

/* Copy a bounded EBSP prefix to RBSP, removing emulation-prevention 0x03. */
static size_t make_rbsp(const unsigned char*src,size_t n){size_t o=0;unsigned zeros=0;for(size_t i=0;i<n && o<MAX_RBSP_BYTES;i++){unsigned char x=src[i];if(zeros>=2 && x==3){zeros=0;continue;}rbsp[o++]=x;if(x==0)zeros++;else zeros=0;}return o;}

struct sps_info {
    unsigned id;
    unsigned width;
    unsigned height;
    unsigned log2_max_frame_num_minus4;
    unsigned pic_order_cnt_type;
    unsigned log2_max_pic_order_cnt_lsb_minus4;
    unsigned frame_mbs_only_flag;
    unsigned delta_pic_order_always_zero_flag;
    int valid;
};
struct pps_info {
    unsigned id;
    unsigned sps_id;
    unsigned bottom_field_pic_order_in_frame_present_flag;
    unsigned redundant_pic_cnt_present_flag;
    int valid;
};
struct filter_state { struct sps_info sps; struct pps_info pps; };

static int skip_scaling_list(struct br*b,unsigned size){int last=8,next=8;for(unsigned j=0;j<size && !b->error;j++){if(next!=0){int d=br_se(b);next=(last+d+256)&255;}last=next!=0?next:last;}return b->error?-1:0;}

static int parse_sps(const unsigned char*nal,size_t n,struct sps_info*out){
    if(n<5 || n>MAX_PARAM_BYTES || (nal[0]&0x80) || (nal[0]&0x1f)!=7)return -1;
    size_t rn=make_rbsp(nal+1,n-1); struct br b={rbsp,rn,0,0};
    unsigned profile=br_bits(&b,8); (void)br_bits(&b,8); unsigned level=br_bits(&b,8); unsigned id=br_ue(&b);
    if(b.error || id>31 || level==0 || level>60)return -1;
    unsigned chroma=1,separate=0;
    if(profile==100||profile==110||profile==122||profile==244||profile==44||profile==83||profile==86||profile==118||profile==128||profile==138||profile==139||profile==134||profile==135){
        chroma=br_ue(&b); if(chroma>3)return -1; if(chroma==3)separate=br_bit(&b);
        if(br_ue(&b)>6 || br_ue(&b)>6)return -1; (void)br_bit(&b);
        if(br_bit(&b)){unsigned count=chroma!=3?8:12;for(unsigned i=0;i<count;i++)if(br_bit(&b) && skip_scaling_list(&b,i<6?16:64)<0)return -1;}
    }
    unsigned log2fn=br_ue(&b); if(log2fn>12)return -1;
    unsigned poc=br_ue(&b); if(poc>2)return -1;
    unsigned log2poc=0,delta_zero=0;
    if(poc==0){log2poc=br_ue(&b);if(log2poc>12)return -1;}
    else if(poc==1){delta_zero=br_bit(&b);(void)br_se(&b);(void)br_se(&b);unsigned cnt=br_ue(&b);if(cnt>16)return -1;for(unsigned i=0;i<cnt;i++)(void)br_se(&b);}
    if(br_ue(&b)>16)return -1; (void)br_bit(&b);
    unsigned wmb=br_ue(&b),hmap=br_ue(&b); if(wmb>255||hmap>255)return -1;
    unsigned frame_only=br_bit(&b); if(!frame_only)(void)br_bit(&b); (void)br_bit(&b);
    unsigned crop=br_bit(&b); unsigned l=0,r=0,t=0,bot=0;
    if(crop){l=br_ue(&b);r=br_ue(&b);t=br_ue(&b);bot=br_ue(&b);if(l>255||r>255||t>255||bot>255)return -1;}
    if(b.error)return -1;
    unsigned width=(wmb+1)*16; unsigned height=(2-frame_only)*(hmap+1)*16;
    unsigned cux,cuy;
    if(chroma==0||separate){cux=1;cuy=2-frame_only;}
    else if(chroma==1){cux=2;cuy=2*(2-frame_only);}
    else if(chroma==2){cux=2;cuy=2-frame_only;}
    else {cux=1;cuy=2-frame_only;}
    if((l+r)*cux>=width || (t+bot)*cuy>=height)return -1;
    width-=(l+r)*cux; height-=(t+bot)*cuy;
    if(width!=EXPECT_WIDTH || height!=EXPECT_HEIGHT)return -1;
    out->id=id;out->width=width;out->height=height;out->log2_max_frame_num_minus4=log2fn;out->pic_order_cnt_type=poc;out->log2_max_pic_order_cnt_lsb_minus4=log2poc;out->frame_mbs_only_flag=frame_only;out->delta_pic_order_always_zero_flag=delta_zero;out->valid=1;return 0;
}

static int parse_pps(const unsigned char*nal,size_t n,const struct sps_info*sps,struct pps_info*out){
    if(!sps->valid || n<2 || n>MAX_PARAM_BYTES || (nal[0]&0x80) || (nal[0]&0x1f)!=8)return -1;
    size_t rn=make_rbsp(nal+1,n-1);struct br b={rbsp,rn,0,0};
    unsigned id=br_ue(&b),sid=br_ue(&b);if(b.error||id>255||sid!=sps->id)return -1;
    (void)br_bit(&b); unsigned bottom=br_bit(&b); unsigned slice_groups=br_ue(&b); if(slice_groups!=0)return -1;
    /* We intentionally do not require the rest of PPS syntax for acceptance;
     * the first fields are enough to bind it to the validated 800x480 SPS. */
    out->id=id;out->sps_id=sid;out->bottom_field_pic_order_in_frame_present_flag=bottom;out->redundant_pic_cnt_present_flag=0;out->valid=1;return 0;
}

static int parse_slice(const unsigned char*nal,size_t n,const struct filter_state*s,int is_idr){
    if(!s->sps.valid||!s->pps.valid||n<4||n>MAX_NAL_BYTES||(nal[0]&0x80))return -1;
    unsigned type=nal[0]&0x1f;if(type!=(is_idr?5u:1u))return -1;
    /* The three fields needed to bind this VCL NAL to the validated decoder
     * state are all at the front of slice_header, so a bounded prefix is enough. */
    size_t prefix=n-1;if(prefix>MAX_RBSP_BYTES)prefix=MAX_RBSP_BYTES;size_t rn=make_rbsp(nal+1,prefix);struct br b={rbsp,rn,0,0};
    unsigned first_mb=br_ue(&b),slice_type=br_ue(&b),pps_id=br_ue(&b);
    if(b.error||first_mb!=0||slice_type>9||pps_id!=s->pps.id)return -1;
    unsigned frame_bits=s->sps.log2_max_frame_num_minus4+4;if(frame_bits<4||frame_bits>16)return -1;(void)br_bits(&b,frame_bits);
    unsigned field_pic=0;if(!s->sps.frame_mbs_only_flag){field_pic=br_bit(&b);if(field_pic)(void)br_bit(&b);}
    if(is_idr){unsigned idr=br_ue(&b);if(idr>65535)return -1;}
    if(s->sps.pic_order_cnt_type==0){unsigned bits=s->sps.log2_max_pic_order_cnt_lsb_minus4+4;if(bits<4||bits>16)return -1;(void)br_bits(&b,bits);if(s->pps.bottom_field_pic_order_in_frame_present_flag&&!field_pic)(void)br_se(&b);}
    else if(s->sps.pic_order_cnt_type==1&&!s->sps.delta_pic_order_always_zero_flag){(void)br_se(&b);if(s->pps.bottom_field_pic_order_in_frame_present_flag&&!field_pic)(void)br_se(&b);}
    return b.error?-1:0;
}

static int start_code_len_at(int fd,off_t start){unsigned char h[4];if(sc3(SYS_lseek,fd,start,SEEK_SET)<0)return -1;long r=sc3(SYS_read,fd,(long)h,4);if(r>=3&&h[0]==0&&h[1]==0&&h[2]==1)return 3;if(r>=4&&h[0]==0&&h[1]==0&&h[2]==0&&h[3]==1)return 4;return -1;}

/* Find the next Annex-B start code in [from,end). */
static off_t find_start(int fd,off_t from,off_t end){
    if(from<0||end<=from||sc3(SYS_lseek,fd,from,SEEK_SET)<0)return NO_OFFSET;
    off_t absolute=from;unsigned zeros=0;
    while(absolute<end){size_t want=(size_t)((end-absolute)>(off_t)SCAN_BYTES?SCAN_BYTES:(end-absolute));long r=sc3(SYS_read,fd,(long)scanbuf,want);if(r<=0)return NO_OFFSET;for(long i=0;i<r;i++,absolute++){unsigned char x=scanbuf[i];if(x==0){zeros++;continue;}if(x==1&&zeros>=2){off_t here=absolute-(zeros>=3?3:2);return here;}zeros=0;}}
    return NO_OFFSET;
}

static int load_nal(int fd,off_t start,off_t end,size_t*outn){
    int sc=start_code_len_at(fd,start);if(sc<0||end<=start+sc)return -1;off_t raw=end-start-sc;if(raw<=0||raw>(off_t)MAX_NAL_BYTES)return -2;if(sc3(SYS_lseek,fd,start+sc,SEEK_SET)<0)return -1;size_t n=(size_t)raw;if(read_exact(fd,nalbuf,n)<0)return -1;while(n>0&&nalbuf[n-1]==0)n--;if(n==0)return -1;*outn=n;return 0;
}
static int send_nal(const unsigned char*nal,size_t n){if(writeall(1,annexb4,4)<0)return -1;return writeall(1,nal,n);}

/* Scan current file and locate the newest *validated* SPS/PPS/IDR trio. */
static int newest_valid_gop(int fd,off_t*osps,off_t*opps,off_t*oidr,struct filter_state*outstate){
    long lend=sc3(SYS_lseek,fd,0,SEEK_END);if(lend<=0)return -1;off_t end=(off_t)lend;
    off_t cur=find_start(fd,0,end);if(cur<0)return -1;
    struct filter_state st;st.sps.valid=0;st.pps.valid=0;off_t last_sps=NO_OFFSET,last_pps=NO_OFFSET,best_sps=NO_OFFSET,best_pps=NO_OFFSET,best_idr=NO_OFFSET;struct filter_state best=st;
    while(cur>=0&&cur<end){off_t next=find_start(fd,cur+3,end);if(next<0)break;size_t n=0;int lr=load_nal(fd,cur,next,&n);if(lr==0&&n>0){unsigned type=nalbuf[0]&0x1f;if(!(nalbuf[0]&0x80)&&type==7){struct sps_info s;if(parse_sps(nalbuf,n,&s)==0){st.sps=s;st.pps.valid=0;last_sps=cur;last_pps=NO_OFFSET;}}else if(!(nalbuf[0]&0x80)&&type==8&&st.sps.valid){struct pps_info p;if(parse_pps(nalbuf,n,&st.sps,&p)==0){st.pps=p;last_pps=cur;}}else if(type==5&&last_sps>=0&&last_pps>=0&&parse_slice(nalbuf,n,&st,1)==0){best_sps=last_sps;best_pps=last_pps;best_idr=cur;best=st;}}cur=next;}
    if(best_idr<0)return -1;*osps=best_sps;*opps=best_pps;*oidr=best_idr;*outstate=best;return 0;
}

static int send_nal_at(int fd,off_t start,off_t file_end){off_t next=find_start(fd,start+3,file_end);if(next<0)return -1;size_t n=0;if(load_nal(fd,start,next,&n)!=0)return -1;return send_nal(nalbuf,n);}

static int bootstrap_live_edge(int fd,off_t*pos,struct filter_state*state){
    off_t sps,pps,idr;struct filter_state st;if(newest_valid_gop(fd,&sps,&pps,&idr,&st)<0)return -1;long lend=sc3(SYS_lseek,fd,0,SEEK_END);if(lend<=0)return -1;off_t end=(off_t)lend;
    if(send_nal_at(fd,sps,end)<0||send_nal_at(fd,pps,end)<0)return -1;*state=st;*pos=idr;return 0;
}

static int capture_tail(int fd,off_t pos,size_t*tail_len){size_t n=(size_t)(pos<(off_t)TAIL_BYTES?pos:(off_t)TAIL_BYTES);*tail_len=n;if(n==0)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return -1;if(read_exact(fd,delivered_tail,n)<0)return -1;return 0;}
static int same_generation_at_pos(int fd,off_t pos,size_t tail_len){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end<0||(off_t)end<pos)return 0;if(tail_len==0)return pos==0;if(pos<(off_t)tail_len)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)tail_len,SEEK_SET)<0)return 0;if(read_exact(fd,verify_tail,tail_len)<0)return 0;return equal_bytes(delivered_tail,verify_tail,tail_len);}

/* Validate and emit one complete NAL.  Invalid/fake markers are silently
 * dropped; importantly they never replace the accepted SPS/PPS state. */
static int filter_emit_nal(struct filter_state*st,const unsigned char*nal,size_t n){
    if(n==0||(nal[0]&0x80))return 0;unsigned type=nal[0]&0x1f;
    if(type==7){struct sps_info s;if(parse_sps(nal,n,&s)<0)return 0;st->sps=s;st->pps.valid=0;return send_nal(nal,n);}
    if(type==8){struct pps_info p;if(parse_pps(nal,n,&st->sps,&p)<0)return 0;st->pps=p;return send_nal(nal,n);}
    if(type==5){if(parse_slice(nal,n,st,1)<0)return 0;return send_nal(nal,n);}
    if(type==1){if(parse_slice(nal,n,st,0)<0)return 0;return send_nal(nal,n);}
    return 0;
}

void _start(void){
    static const char hdr[]="Content-Type: video/H264\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nX-U2W-Video-Format: Annex-B-H264\r\nX-U2W-Streamer: v8.19-safe-mainvideo-filter\r\nX-U2W-AppleCarPlay-Hooks: none\r\n\r\n";
    if(writeall(1,hdr,sizeof(hdr)-1)<0)sc1(SYS_exit,0);
    int fd=-1;off_t pos=0;size_t tail_len=0;struct filter_state state;state.sps.valid=0;state.pps.valid=0;
    for(;;){
        if(fd<0){
            fd=(int)sc3(SYS_open,(long)path,O_RDONLY,0);if(fd<0){nap_ms(250);continue;}
            /* A new process or generation must establish a validated decoder-safe
             * bootstrap before any video bytes are emitted.  Retry slowly to keep
             * CPU pressure negligible when the rolling file currently contains no
             * trustworthy GOP. */
            if(bootstrap_live_edge(fd,&pos,&state)<0){sc1(SYS_close,fd);fd=-1;nap_ms(1000);continue;}
            tail_len=0;
        }

        long lend=sc3(SYS_lseek,fd,0,SEEK_END);if(lend<0){sc1(SYS_close,fd);fd=-1;nap_ms(250);continue;}off_t end=(off_t)lend;
        off_t next=find_start(fd,pos+3,end);
        if(next>=0){size_t n=0;int lr=load_nal(fd,pos,next,&n);if(lr==0){int er=filter_emit_nal(&state,nalbuf,n);if(er<0){sc1(SYS_close,fd);sc1(SYS_exit,0);}}pos=next;continue;}

        /* No complete next NAL yet.  Reopen the pathname so rolling-file replace
         * is detected, but fingerprint at the current NAL boundary to avoid
         * replaying historical data. */
        if(capture_tail(fd,pos,&tail_len)<0)tail_len=0;sc1(SYS_close,fd);fd=-1;nap_ms(80);
        fd=(int)sc3(SYS_open,(long)path,O_RDONLY,0);if(fd<0){nap_ms(250);continue;}
        if(!same_generation_at_pos(fd,pos,tail_len)){
            state.sps.valid=0;state.pps.valid=0;
            if(bootstrap_live_edge(fd,&pos,&state)<0){sc1(SYS_close,fd);fd=-1;nap_ms(1000);continue;}
            tail_len=0;
        }
    }
}
