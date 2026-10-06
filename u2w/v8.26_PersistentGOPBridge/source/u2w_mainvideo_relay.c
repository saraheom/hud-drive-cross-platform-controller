/* U2W v8.26 persistent validated-GOP bridge MainVideo H.264 relay.
 *
 * Data path remains intentionally narrow and safe:
 *   AppleCarPlay -> proven v8.11 /tmp/u2w_mainvideo_live.h264 mirror
 *                -> this standalone TCP/15332 relay -> iPhone
 *
 * This process never opens AppleCarPlay fds, never patches/restarts AppleCarPlay,
 * and never carries long-lived video through Boa.  The 2026-09-22 field test
 * proved v8.25's main weakness was treating each v8.11 rolling-file rotation as
 * a decoder epoch: the live client was forced back to WAITING_VALIDATED_GOP and
 * 125/126 rescans missed even though v8.11 continued to report many IDRs.
 *
 * v8.26 therefore treats a rolling-file generation as a storage boundary, not a
 * codec boundary.  It preserves the validated H.264 state and a single
 * disk-backed, length-framed current GOP across rotations.  A reconnect can replay
 * that coordinated cache without Boa and without reading a file while another
 * process truncates it.  The cache is reset only at a genuinely validated IDR or
 * a real SPS/PPS configuration change.  If the cache is unavailable/overflowed,
 * the client remains connected and waits for the next validated live IDR.
 *
 * Wire protocol (unchanged framing, already accepted by v90.35.3.24.2+):
 *   8 bytes ASCII "U2WH2644"
 *   repeated: [u32 big-endian NAL length][NAL bytes without Annex-B prefix]
 */
typedef unsigned int u32; typedef unsigned short u16; typedef unsigned long size_t; typedef long off_t;
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; unsigned char zero[8]; };
struct timespec { long tv_sec; long tv_nsec; };
struct timeval { long tv_sec; long tv_usec; };
struct pollfd { int fd; short events; short revents; };
#define SYS_exit 1
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_lseek 19
#define SYS_rename 38
#define SYS_nanosleep 162
#define SYS_poll 168
#define SYS_socket 281
#define SYS_bind 282
#define SYS_listen 284
#define SYS_accept 285
#define SYS_sendto 290
#define SYS_setsockopt 294
#define AF_INET 2
#define SOCK_STREAM 1
#define SOL_SOCKET 1
#define SO_REUSEADDR 2
#define SO_SNDTIMEO 21
#define MSG_NOSIGNAL 0x4000
#define POLLIN 1
#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT 64
#define O_TRUNC 512
#define O_APPEND 1024
#define SEEK_SET 0
#define SEEK_END 2
#define PARSE_CAP (1024*1024)
#define SCAN_BYTES 32768
#define TAIL_BYTES 64
#define MAX_NAL_BYTES (512*1024)
#define MAX_PARAM_BYTES 256
#define MAX_RBSP_BYTES 512
#define EXPECT_WIDTH 800
#define EXPECT_HEIGHT 480
#define CATCHUP_CAP (48*1024*1024)
#define CATCHUP_FRAME_PACE_MS 4
#define CACHE_REPLAY_PACE_EVERY_SLICES 4
#define CACHE_REPLAY_PACE_MS 1
#define NO_OFFSET ((off_t)-1)

static const char live_path[]="/tmp/u2w_mainvideo_live.h264";
static const char status_tmp[]="/tmp/u2w_h264_relay_status.new";
static const char status_path[]="/tmp/u2w_h264_relay_status.txt";
static const char cache_path[]="/tmp/u2w_mainvideo_validated_gop.cache";
static unsigned char io_buf[65536];
static unsigned char parse_buf[PARSE_CAP]; static size_t parse_len=0;
static unsigned char scanbuf[SCAN_BYTES];
static unsigned char nalbuf[MAX_NAL_BYTES];
static unsigned char rbsp[MAX_RBSP_BYTES];
static unsigned char delivered_tail[TAIL_BYTES],verify_tail[TAIL_BYTES];
static unsigned char sps[256],pps[256]; static size_t sps_len=0,pps_len=0;
static int listen_fd=-1,client_fd=-1,client_live=0,startup_scan_complete=0,client_scan_pending=0;
static int cache_fd=-1,cache_ready=0,cache_building=0,cache_overflow=0;
static u32 source_bytes=0,generation_changes=0,sps_count=0,pps_count=0,idr_count=0,slice_count=0,rejected_count=0;
static u32 client_sessions=0,client_bootstraps=0,live_idr_bootstraps=0,file_gop_bootstraps=0,generation_reseeds=0;
static u32 file_gop_scan_attempts=0,file_gop_scan_misses=0,file_gop_cap_rejects=0,client_send_failures=0,client_replaced_count=0;
static u32 pre_idr_slices_dropped=0,status_tick=0,last_bootstrap_source_bytes=0,last_bootstrap_bytes=0,last_nal_type=0;
static u32 catchup_active=0,catchup_bytes=0,catchup_frames=0,catchup_target_bytes=0;
static u32 cache_bytes=0,cache_frames=0,cache_resets=0,cache_replays=0,cache_invalidations=0,codec_epoch_resets=0;
static int last_bootstrap_mode=0; /* 0 NONE, 1 FILE_GOP, 2 LIVE_IDR, 3 GENERATION_GOP, 4 GOP_CACHE */

static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static long sc5(long n,long a,long b,long c,long d,long e){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r7):"memory");return r0;}
static long sc6(long n,long a,long b,long c,long d,long e,long f){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;register long r5 __asm__("r5")=f;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory");return r0;}
static u16 htons(u16 x){return (u16)((x<<8)|(x>>8));}
__attribute__((used,noinline)) void *memcpy(void*d,const void*s,size_t n){unsigned char*o=(unsigned char*)d;const unsigned char*i=(const unsigned char*)s;for(size_t k=0;k<n;k++)o[k]=i[k];return d;}
__attribute__((used,noinline)) void *memset(void*d,int v,size_t n){unsigned char*o=(unsigned char*)d;for(size_t k=0;k<n;k++)o[k]=(unsigned char)v;return d;}
static void nap_ms(long ms){struct timespec t;t.tv_sec=ms/1000;t.tv_nsec=(ms%1000)*1000000L;sc2(SYS_nanosleep,(long)&t,0);}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static int writeall_fd(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_write,fd,(long)(p+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int sendall(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=sc6(SYS_sendto,fd,(long)(p+o),n-o,MSG_NOSIGNAL,0,0);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static void logmsg(const char*s){writeall_fd(1,(const unsigned char*)s,slen(s));writeall_fd(1,(const unsigned char*)"\n",1);}
static int eq(const unsigned char*a,const unsigned char*b,size_t n){for(size_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int read_exact(int fd,unsigned char*out,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_read,fd,(long)(out+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static size_t addstr(char*b,size_t o,size_t cap,const char*s){while(*s&&o<cap)b[o++]=*s++;return o;}
static size_t addu32(char*b,size_t o,size_t cap,u32 v){static const u32 pw[10]={1000000000U,100000000U,10000000U,1000000U,100000U,10000U,1000U,100U,10U,1U};int st=0;for(int i=0;i<10;i++){unsigned char d=0;while(v>=pw[i]){v-=pw[i];d++;}if(d||st||i==9){if(o<cap)b[o++]=(char)('0'+d);st=1;}}return o;}
static size_t kv(char*b,size_t o,size_t cap,const char*k,u32 v){o=addstr(b,o,cap,k);o=addu32(b,o,cap,v);if(o<cap)b[o++]='\n';return o;}
static size_t kvyn(char*b,size_t o,size_t cap,const char*k,int yes){o=addstr(b,o,cap,k);o=addstr(b,o,cap,yes?"YES\n":"NO\n");return o;}
static const char* mode_name(void){return last_bootstrap_mode==1?"FILE_GOP":last_bootstrap_mode==2?"LIVE_IDR":last_bootstrap_mode==3?"GENERATION_GOP":last_bootstrap_mode==4?"GOP_CACHE":"NONE";}

struct br{const unsigned char*p;size_t n;size_t bit;int error;};
static unsigned br_bit(struct br*b){if(b->bit>=b->n*8){b->error=1;return 0;}unsigned v=(b->p[b->bit>>3]>>(7-(b->bit&7)))&1;b->bit++;return v;}
static unsigned br_bits(struct br*b,unsigned n){unsigned v=0;if(n>24){b->error=1;return 0;}for(unsigned i=0;i<n;i++)v=(v<<1)|br_bit(b);return v;}
static unsigned br_ue(struct br*b){unsigned z=0;while(!b->error&&br_bit(b)==0){if(++z>24){b->error=1;return 0;}}if(b->error)return 0;return ((1u<<z)-1u)+(z?br_bits(b,z):0u);}
static int br_se(struct br*b){unsigned c=br_ue(b);return(c&1)?(int)((c+1)>>1):-(int)(c>>1);}
static size_t make_rbsp(const unsigned char*src,size_t n){size_t o=0;unsigned zeros=0;for(size_t i=0;i<n&&o<MAX_RBSP_BYTES;i++){unsigned char x=src[i];if(zeros>=2&&x==3){zeros=0;continue;}rbsp[o++]=x;if(x==0)zeros++;else zeros=0;}return o;}
struct sps_info{unsigned id,width,height,log2_max_frame_num_minus4,pic_order_cnt_type,log2_max_pic_order_cnt_lsb_minus4,frame_mbs_only_flag,delta_pic_order_always_zero_flag;int valid;};
struct pps_info{unsigned id,sps_id,bottom_field_pic_order_in_frame_present_flag;int valid;};
struct slice_info{unsigned first_mb,pps_id,frame_num,nal_type,idr_pic_id;int valid;};
struct frame_key{unsigned pps_id,frame_num,nal_type,idr_pic_id;int valid;};
struct filter_state{struct sps_info sps;struct pps_info pps;struct frame_key cont;};
static struct filter_state live_filter;
static void reset_filter(struct filter_state*s){s->sps.valid=0;s->pps.valid=0;s->cont.valid=0;}
static int skip_scaling_list(struct br*b,unsigned size){int last=8,next=8;for(unsigned j=0;j<size&&!b->error;j++){if(next!=0){int d=br_se(b);next=(last+d+256)&255;}last=next!=0?next:last;}return b->error?-1:0;}
static int parse_sps(const unsigned char*nal,size_t n,struct sps_info*out){
 if(n<5||n>MAX_PARAM_BYTES||(nal[0]&0x80)||(nal[0]&0x1f)!=7)return -1;size_t rn=make_rbsp(nal+1,n-1);struct br b={rbsp,rn,0,0};
 unsigned profile=br_bits(&b,8);(void)br_bits(&b,8);unsigned level=br_bits(&b,8);unsigned id=br_ue(&b);if(b.error||id>31||level==0||level>60)return -1;
 unsigned chroma=1,separate=0;if(profile==100||profile==110||profile==122||profile==244||profile==44||profile==83||profile==86||profile==118||profile==128||profile==138||profile==139||profile==134||profile==135){chroma=br_ue(&b);if(chroma>3)return -1;if(chroma==3)separate=br_bit(&b);if(br_ue(&b)>6||br_ue(&b)>6)return -1;(void)br_bit(&b);if(br_bit(&b)){unsigned cnt=chroma!=3?8:12;for(unsigned i=0;i<cnt;i++)if(br_bit(&b)&&skip_scaling_list(&b,i<6?16:64)<0)return -1;}}
 unsigned log2fn=br_ue(&b);if(log2fn>12)return -1;unsigned poc=br_ue(&b);if(poc>2)return -1;unsigned log2poc=0,delta0=0;if(poc==0){log2poc=br_ue(&b);if(log2poc>12)return -1;}else if(poc==1){delta0=br_bit(&b);(void)br_se(&b);(void)br_se(&b);unsigned cnt=br_ue(&b);if(cnt>16)return -1;for(unsigned i=0;i<cnt;i++)(void)br_se(&b);}if(br_ue(&b)>16)return -1;(void)br_bit(&b);
 unsigned wmb=br_ue(&b),hmap=br_ue(&b);if(wmb>255||hmap>255)return -1;unsigned frame=br_bit(&b);if(!frame)(void)br_bit(&b);(void)br_bit(&b);unsigned crop=br_bit(&b),l=0,r=0,t=0,bot=0;if(crop){l=br_ue(&b);r=br_ue(&b);t=br_ue(&b);bot=br_ue(&b);if(l>255||r>255||t>255||bot>255)return -1;}if(b.error)return -1;unsigned width=(wmb+1)*16,height=(2-frame)*(hmap+1)*16,cux,cuy;if(chroma==0||separate){cux=1;cuy=2-frame;}else if(chroma==1){cux=2;cuy=2*(2-frame);}else if(chroma==2){cux=2;cuy=2-frame;}else{cux=1;cuy=2-frame;}if((l+r)*cux>=width||(t+bot)*cuy>=height)return -1;width-=(l+r)*cux;height-=(t+bot)*cuy;if(width!=EXPECT_WIDTH||height!=EXPECT_HEIGHT)return -1;
 out->id=id;out->width=width;out->height=height;out->log2_max_frame_num_minus4=log2fn;out->pic_order_cnt_type=poc;out->log2_max_pic_order_cnt_lsb_minus4=log2poc;out->frame_mbs_only_flag=frame;out->delta_pic_order_always_zero_flag=delta0;out->valid=1;return 0;}
static int parse_pps(const unsigned char*nal,size_t n,const struct sps_info*sps,struct pps_info*out){if(!sps->valid||n<2||n>MAX_PARAM_BYTES||(nal[0]&0x80)||(nal[0]&0x1f)!=8)return -1;size_t rn=make_rbsp(nal+1,n-1);struct br b={rbsp,rn,0,0};unsigned id=br_ue(&b),sid=br_ue(&b);if(b.error||id>255||sid!=sps->id)return -1;(void)br_bit(&b);unsigned bottom=br_bit(&b);unsigned groups=br_ue(&b);if(groups!=0)return -1;out->id=id;out->sps_id=sid;out->bottom_field_pic_order_in_frame_present_flag=bottom;out->valid=1;return 0;}
static int parse_slice_info(const unsigned char*nal,size_t n,const struct filter_state*s,struct slice_info*out){if(!s->sps.valid||!s->pps.valid||n<4||n>MAX_NAL_BYTES||(nal[0]&0x80))return -1;unsigned type=nal[0]&0x1f;if(type!=1&&type!=5)return -1;size_t prefix=n-1;if(prefix>MAX_RBSP_BYTES)prefix=MAX_RBSP_BYTES;size_t rn=make_rbsp(nal+1,prefix);struct br b={rbsp,rn,0,0};unsigned first=br_ue(&b),slice_type=br_ue(&b),pid=br_ue(&b);if(b.error||slice_type>9||pid!=s->pps.id)return -1;unsigned bits=s->sps.log2_max_frame_num_minus4+4;if(bits<4||bits>16)return -1;unsigned frame_num=br_bits(&b,bits);unsigned field=0;if(!s->sps.frame_mbs_only_flag){field=br_bit(&b);if(field)(void)br_bit(&b);}unsigned idr=0;if(type==5){idr=br_ue(&b);if(idr>65535)return -1;}if(s->sps.pic_order_cnt_type==0){unsigned pb=s->sps.log2_max_pic_order_cnt_lsb_minus4+4;if(pb<4||pb>16)return -1;(void)br_bits(&b,pb);if(s->pps.bottom_field_pic_order_in_frame_present_flag&&!field)(void)br_se(&b);}else if(s->sps.pic_order_cnt_type==1&&!s->sps.delta_pic_order_always_zero_flag){(void)br_se(&b);if(s->pps.bottom_field_pic_order_in_frame_present_flag&&!field)(void)br_se(&b);}if(b.error)return -1;out->first_mb=first;out->pps_id=pid;out->frame_num=frame_num;out->nal_type=type;out->idr_pic_id=idr;out->valid=1;return 0;}
static int accept_slice(struct filter_state*s,const struct slice_info*i){if(i->first_mb==0){s->cont.pps_id=i->pps_id;s->cont.frame_num=i->frame_num;s->cont.nal_type=i->nal_type;s->cont.idr_pic_id=i->idr_pic_id;s->cont.valid=1;return 1;}if(!s->cont.valid)return 0;return s->cont.pps_id==i->pps_id&&s->cont.frame_num==i->frame_num&&s->cont.nal_type==i->nal_type&&s->cont.idr_pic_id==i->idr_pic_id;}

static int start_code_len_at(int fd,off_t start){unsigned char h[4];if(sc3(SYS_lseek,fd,start,SEEK_SET)<0)return -1;long r=sc3(SYS_read,fd,(long)h,4);if(r>=3&&h[0]==0&&h[1]==0&&h[2]==1)return 3;if(r>=4&&h[0]==0&&h[1]==0&&h[2]==0&&h[3]==1)return 4;return -1;}
static off_t find_start_fd(int fd,off_t from,off_t end){if(from<0||end<=from||sc3(SYS_lseek,fd,from,SEEK_SET)<0)return NO_OFFSET;off_t absolute=from;unsigned zeros=0;while(absolute<end){size_t want=(size_t)((end-absolute)>(off_t)SCAN_BYTES?SCAN_BYTES:(end-absolute));long r=sc3(SYS_read,fd,(long)scanbuf,want);if(r<=0)return NO_OFFSET;for(long i=0;i<r;i++,absolute++){unsigned char x=scanbuf[i];if(x==0){zeros++;continue;}if(x==1&&zeros>=2)return absolute-(zeros>=3?3:2);zeros=0;}}return NO_OFFSET;}
static int load_nal(int fd,off_t start,off_t end,size_t*outn){int sc=start_code_len_at(fd,start);if(sc<0||end<=start+sc)return -1;off_t raw=end-start-sc;if(raw<=0||raw>(off_t)MAX_NAL_BYTES)return -2;if(sc3(SYS_lseek,fd,start+sc,SEEK_SET)<0)return -1;size_t n=(size_t)raw;if(read_exact(fd,nalbuf,n)<0)return -1;while(n>0&&nalbuf[n-1]==0)n--;if(!n)return -1;*outn=n;return 0;}
static int newest_valid_gop(int fd,off_t*osps,off_t*opps,off_t*oidr,struct filter_state*outstate){long le=sc3(SYS_lseek,fd,0,SEEK_END);if(le<=0)return -1;off_t end=(off_t)le,cur=find_start_fd(fd,0,end);if(cur<0)return -1;struct filter_state st;reset_filter(&st);off_t ls=NO_OFFSET,lp=NO_OFFSET,bs=NO_OFFSET,bp=NO_OFFSET,bi=NO_OFFSET;struct filter_state best=st;while(cur>=0&&cur<end){off_t next=find_start_fd(fd,cur+3,end);if(next<0)break;size_t n=0;if(load_nal(fd,cur,next,&n)==0&&n){unsigned type=nalbuf[0]&0x1f;if(type==7){struct sps_info si;if(parse_sps(nalbuf,n,&si)==0){st.sps=si;st.pps.valid=0;st.cont.valid=0;ls=cur;lp=NO_OFFSET;}}else if(type==8&&st.sps.valid){struct pps_info pi;if(parse_pps(nalbuf,n,&st.sps,&pi)==0){st.pps=pi;st.cont.valid=0;lp=cur;}}else if(type==5&&ls>=0&&lp>=0){struct slice_info si;if(parse_slice_info(nalbuf,n,&st,&si)==0&&si.first_mb==0){bs=ls;bp=lp;bi=cur;best=st;}}}cur=next;}if(bi<0)return -1;*osps=bs;*opps=bp;*oidr=bi;*outstate=best;return 0;}

static void write_status(void){char b[3000];size_t o=0;o=addstr(b,o,sizeof(b),"relay_version=v8.26-persistent-gop-bridge\nrelay_port=15332\ntransport=length-framed-nal-persistent-gop\nwire_magic=U2WH2644\n");o=kvyn(b,o,sizeof(b),"client_connected=",client_fd>=0);o=addstr(b,o,sizeof(b),"client_state=");o=addstr(b,o,sizeof(b),client_fd<0?"NO_CLIENT\n":(client_live?"LIVE\n":(catchup_active?"CATCHING_UP_GOP\n":"WAITING_GOP_CACHE_OR_LIVE_IDR\n")));o=kvyn(b,o,sizeof(b),"startup_scan_complete=",startup_scan_complete);o=kvyn(b,o,sizeof(b),"have_sps=",sps_len>0);o=kvyn(b,o,sizeof(b),"have_pps=",pps_len>0);o=kvyn(b,o,sizeof(b),"gop_cache_ready=",cache_ready);o=kvyn(b,o,sizeof(b),"gop_cache_building=",cache_building);o=kvyn(b,o,sizeof(b),"gop_cache_overflow=",cache_overflow);o=kv(b,o,sizeof(b),"gop_cache_bytes=",cache_bytes);o=kv(b,o,sizeof(b),"gop_cache_frames=",cache_frames);o=kv(b,o,sizeof(b),"gop_cache_cap=",CATCHUP_CAP);o=kv(b,o,sizeof(b),"gop_cache_resets=",cache_resets);o=kv(b,o,sizeof(b),"gop_cache_replays=",cache_replays);o=kv(b,o,sizeof(b),"gop_cache_invalidations=",cache_invalidations);o=kv(b,o,sizeof(b),"codec_epoch_resets=",codec_epoch_resets);o=kvyn(b,o,sizeof(b),"catchup_active=",catchup_active);o=kv(b,o,sizeof(b),"catchup_bytes=",catchup_bytes);o=kv(b,o,sizeof(b),"catchup_frames=",catchup_frames);o=kv(b,o,sizeof(b),"catchup_target_bytes=",catchup_target_bytes);o=kv(b,o,sizeof(b),"file_gop_scan_attempts=",file_gop_scan_attempts);o=kv(b,o,sizeof(b),"file_gop_scan_misses=",file_gop_scan_misses);o=kv(b,o,sizeof(b),"file_gop_cap_rejects=",file_gop_cap_rejects);o=kv(b,o,sizeof(b),"file_gop_bootstraps=",file_gop_bootstraps);o=kv(b,o,sizeof(b),"live_idr_bootstraps=",live_idr_bootstraps);o=kv(b,o,sizeof(b),"generation_reseeds=",generation_reseeds);o=kv(b,o,sizeof(b),"client_bootstraps=",client_bootstraps);o=addstr(b,o,sizeof(b),"last_bootstrap_mode=");o=addstr(b,o,sizeof(b),mode_name());if(o<sizeof(b))b[o++]='\n';o=kv(b,o,sizeof(b),"last_bootstrap_bytes=",last_bootstrap_bytes);o=kv(b,o,sizeof(b),"source_bytes_low32=",source_bytes);o=kv(b,o,sizeof(b),"source_generation_changes=",generation_changes);o=kv(b,o,sizeof(b),"sps=",sps_count);o=kv(b,o,sizeof(b),"pps=",pps_count);o=kv(b,o,sizeof(b),"idr=",idr_count);o=kv(b,o,sizeof(b),"slices=",slice_count);o=kv(b,o,sizeof(b),"rejected_nals=",rejected_count);o=kv(b,o,sizeof(b),"client_sessions=",client_sessions);o=kv(b,o,sizeof(b),"client_send_failures=",client_send_failures);o=kv(b,o,sizeof(b),"client_replaced_count=",client_replaced_count);o=kv(b,o,sizeof(b),"pre_idr_slices_dropped=",pre_idr_slices_dropped);o=kv(b,o,sizeof(b),"last_bootstrap_source_bytes=",last_bootstrap_source_bytes);o=kv(b,o,sizeof(b),"last_nal_type=",last_nal_type);int f=(int)sc3(SYS_open,(long)status_tmp,O_WRONLY|O_CREAT|O_TRUNC,0644);if(f>=0){writeall_fd(f,(unsigned char*)b,o);sc1(SYS_close,f);sc2(SYS_rename,(long)status_tmp,(long)status_path);}}
static void drop_client(const char*why,int failure){if(client_fd>=0){sc1(SYS_close,client_fd);client_fd=-1;}client_live=0;client_scan_pending=0;catchup_active=0;if(failure)client_send_failures++;logmsg(why);write_status();}
static int send_framed(const unsigned char*n,size_t len){if(client_fd<0)return -1;unsigned char h[4];h[0]=(len>>24)&255;h[1]=(len>>16)&255;h[2]=(len>>8)&255;h[3]=len&255;if(sendall(client_fd,h,4)<0||sendall(client_fd,n,len)<0){drop_client("client-send-failed",1);return -1;}return 0;}
static int cache_write_record_fd(int fd,const unsigned char*n,size_t len){unsigned char h[4];h[0]=(len>>24)&255;h[1]=(len>>16)&255;h[2]=(len>>8)&255;h[3]=len&255;if(writeall_fd(fd,h,4)<0||writeall_fd(fd,n,len)<0)return -1;return 0;}
static void cache_close(void){if(cache_fd>=0){sc1(SYS_close,cache_fd);cache_fd=-1;}}
static void cache_invalidate(const char*why){cache_close();cache_ready=0;cache_building=0;cache_overflow=0;cache_bytes=0;cache_frames=0;cache_invalidations++;logmsg(why);write_status();}
static int cache_reset_with_idr(const unsigned char*idr,size_t len){if(!sps_len||!pps_len)return 0;cache_close();cache_fd=(int)sc3(SYS_open,(long)cache_path,O_WRONLY|O_CREAT|O_TRUNC,0644);if(cache_fd<0){cache_ready=0;return -1;}if(cache_write_record_fd(cache_fd,sps,sps_len)<0||cache_write_record_fd(cache_fd,pps,pps_len)<0||cache_write_record_fd(cache_fd,idr,len)<0){cache_close();cache_ready=0;return -1;}cache_bytes=(u32)(12+sps_len+pps_len+len);cache_frames=1;cache_ready=0;cache_building=1;cache_overflow=0;cache_resets++;logmsg("gop-cache-building-at-validated-idr");return 0;}
static int cache_append(const unsigned char*n,size_t len,int frame_start){if((!cache_ready&&!cache_building)||cache_overflow)return 0;if(cache_bytes+(u32)(4+len)>CATCHUP_CAP){cache_overflow=1;cache_ready=0;cache_building=0;cache_close();cache_invalidations++;logmsg("gop-cache-overflow-wait-next-idr");write_status();return 0;}if(cache_fd<0){cache_fd=(int)sc3(SYS_open,(long)cache_path,O_WRONLY|O_CREAT|O_APPEND,0644);if(cache_fd<0)return -1;}if(cache_write_record_fd(cache_fd,n,len)<0)return -1;cache_bytes+=(u32)(4+len);if(frame_start){cache_frames++;if(cache_building){cache_building=0;cache_ready=1;logmsg("gop-cache-promoted-after-complete-idr");write_status();}}return 0;}
static int begin_live_from_cache(void){if(client_fd<0||client_live||!cache_ready||cache_overflow||cache_bytes<16)return 0;cache_close();int fd=(int)sc3(SYS_open,(long)cache_path,O_RDONLY,0);if(fd<0)return 0;u32 target=cache_bytes,done=0,frames=0,slices=0;catchup_active=1;catchup_bytes=0;catchup_frames=0;catchup_target_bytes=target;write_status();while(done+4<=target){unsigned char h[4];if(read_exact(fd,h,4)<0)break;done+=4;u32 len=((u32)h[0]<<24)|((u32)h[1]<<16)|((u32)h[2]<<8)|(u32)h[3];if(!len||len>MAX_NAL_BYTES||done+len>target){done=0;break;}if(read_exact(fd,nalbuf,len)<0){done=0;break;}done+=len;if(send_framed(nalbuf,len)<0){sc1(SYS_close,fd);catchup_active=0;return -1;}unsigned type=nalbuf[0]&0x1f;if(type==1||type==5){slices++;if((slices%CACHE_REPLAY_PACE_EVERY_SLICES)==0)nap_ms(CACHE_REPLAY_PACE_MS);frames++;}catchup_bytes=done;catchup_frames=frames;if((frames&255U)==0)write_status();}sc1(SYS_close,fd);catchup_active=0;if(done!=target){cache_invalidate("gop-cache-replay-structure-invalid");return 0;}client_live=1;client_scan_pending=0;client_bootstraps++;cache_replays++;last_bootstrap_mode=4;last_bootstrap_bytes=target;last_bootstrap_source_bytes=source_bytes;logmsg("client-bootstrap-persistent-gop-cache");write_status();return 1;}
static int copy_current_param_sets(const unsigned char*sn,size_t sl,const unsigned char*pn,size_t pl){if(sl>sizeof(sps)||pl>sizeof(pps)||!sl||!pl)return -1;for(size_t i=0;i<sl;i++)sps[i]=sn[i];sps_len=sl;for(size_t i=0;i<pl;i++)pps[i]=pn[i];pps_len=pl;return 0;}
static int load_nal_copy(int fd,off_t start,off_t file_end,unsigned char*out,size_t cap,size_t*outn){off_t next=find_start_fd(fd,start+3,file_end);if(next<0)return -1;size_t n=0;if(load_nal(fd,start,next,&n)!=0||n>cap)return -1;for(size_t i=0;i<n;i++)out[i]=nalbuf[i];*outn=n;return 0;}
static int catchup_accept_and_send(struct filter_state*st,const unsigned char*n,size_t len){
    if(!len||(n[0]&0x80))return 0;
    unsigned type=n[0]&0x1f;
    if(type==7){
        struct sps_info si;
        if(parse_sps(n,len,&si)<0)return 0;
        st->sps=si;st->pps.valid=0;st->cont.valid=0;
        return send_framed(n,len)<0?-1:1;
    }
    if(type==8){
        struct pps_info pi;
        if(parse_pps(n,len,&st->sps,&pi)<0)return 0;
        st->pps=pi;st->cont.valid=0;
        return send_framed(n,len)<0?-1:1;
    }
    if(type==5||type==1){
        struct slice_info si;
        if(parse_slice_info(n,len,st,&si)<0||!accept_slice(st,&si))return 0;
        if(send_framed(n,len)<0)return -1;
        return si.first_mb==0?2:1;
    }
    return 0;
}

static int begin_live_from_file_gop(int fd,off_t*pos,size_t*tail_len,int generation_mode){
    if(client_fd<0||client_live)return 0;
    const off_t resume=*pos;
    file_gop_scan_attempts++;
    off_t os,op,oi;
    struct filter_state st;
    if(newest_valid_gop(fd,&os,&op,&oi,&st)<0){
        file_gop_scan_misses++;
        sc3(SYS_lseek,fd,resume,SEEK_SET);
        logmsg("validated-gop-scan-miss-wait-live-idr");
        write_status();
        return 0;
    }
    long le=sc3(SYS_lseek,fd,0,SEEK_END);
    if(le<=0){sc3(SYS_lseek,fd,resume,SEEK_SET);return 0;}
    off_t end=(off_t)le;
    if(end-oi>(off_t)CATCHUP_CAP){
        file_gop_cap_rejects++;
        sc3(SYS_lseek,fd,resume,SEEK_SET);
        logmsg("validated-gop-catchup-cap-exceeded-wait-live-idr");
        write_status();
        return 0;
    }
    unsigned char sb[256],pb[256];
    size_t sl=0,pl=0;
    if(load_nal_copy(fd,os,end,sb,sizeof(sb),&sl)<0||load_nal_copy(fd,op,end,pb,sizeof(pb),&pl)<0){
        sc3(SYS_lseek,fd,resume,SEEK_SET);
        return 0;
    }
    catchup_active=1;
    catchup_bytes=0;
    catchup_frames=0;
    catchup_target_bytes=(u32)(end-oi);
    write_status();
    if(send_framed(sb,sl)<0||send_framed(pb,pl)<0){catchup_active=0;return -1;}
    struct filter_state local=st;
    local.cont.valid=0;
    off_t cur=oi;
    u32 sent_bytes=(u32)(sl+pl);
    while(cur>=0&&cur<end){
        off_t next=find_start_fd(fd,cur+3,end);
        if(next<0)break;
        size_t n=0;
        if(load_nal(fd,cur,next,&n)==0&&n){
            int sr=catchup_accept_and_send(&local,nalbuf,n);
            if(sr<0){catchup_active=0;return -1;}
            if(sr>0){
                sent_bytes+=(u32)n;
                catchup_bytes+=(u32)n;
                if(sr==2){
                    catchup_frames++;
                    if((catchup_frames&127U)==0)write_status();
                    nap_ms(CATCHUP_FRAME_PACE_MS);
                }
            }
        }
        cur=next;
    }
    /* Keep the validated SPS/PPS that anchor this selected GOP. Any later
       parameter-set transition was already delivered during catch-up; a new
       client will rescan the file, and a generation change clears these. */
    if(copy_current_param_sets(sb,sl,pb,pl)<0){catchup_active=0;sc3(SYS_lseek,fd,resume,SEEK_SET);return 0;}
    live_filter=local;
    parse_len=0;
    *pos=cur;
    *tail_len=0;
    if(sc3(SYS_lseek,fd,*pos,SEEK_SET)<0){catchup_active=0;*pos=resume;sc3(SYS_lseek,fd,resume,SEEK_SET);return 0;}
    catchup_active=0;
    client_live=1;
    client_scan_pending=0;
    client_bootstraps++;
    file_gop_bootstraps++;
    last_bootstrap_mode=generation_mode?3:1;
    last_bootstrap_bytes=sent_bytes;
    last_bootstrap_source_bytes=source_bytes;
    logmsg(generation_mode?"client-generation-bootstrap-validated-file-gop":"client-bootstrap-validated-file-gop");
    write_status();
    return 1;
}
static int begin_live_at_idr(const unsigned char*n,size_t len){if(client_fd<0||client_live||!sps_len||!pps_len)return 0;if(send_framed(sps,sps_len)<0||send_framed(pps,pps_len)<0||send_framed(n,len)<0)return -1;client_live=1;client_scan_pending=0;client_bootstraps++;live_idr_bootstraps++;last_bootstrap_mode=2;last_bootstrap_bytes=(u32)(sps_len+pps_len+len);last_bootstrap_source_bytes=source_bytes;logmsg("client-bootstrap-fresh-validated-live-idr");write_status();return 1;}
static int process_validated_nal(const unsigned char*n,size_t len){
 if(!len||len>MAX_NAL_BYTES||(n[0]&0x80)){rejected_count++;return 0;}
 unsigned type=n[0]&0x1f;last_nal_type=(u32)type;
 if(type==7){
  struct sps_info si;if(parse_sps(n,len,&si)<0){rejected_count++;return 0;}
  int same=(sps_len==len&&sps_len>0&&eq(sps,n,len));
  if(!same&&sps_len>0){codec_epoch_resets++;live_filter.pps.valid=0;live_filter.cont.valid=0;pps_len=0;cache_invalidate("codec-sps-change-invalidated-gop-cache");if(client_live){client_live=0;logmsg("codec-sps-change-client-waits-fresh-idr");}}
  live_filter.sps=si;
  if(len<=sizeof(sps)){for(size_t i=0;i<len;i++)sps[i]=n[i];sps_len=len;}else sps_len=0;
  sps_count++;
  if(same&&cache_ready&&cache_append(n,len,0)<0)return -1;
  if(client_live&&send_framed(n,len)<0)return -1;
  return 1;
 }
 if(type==8){
  struct pps_info pi;if(parse_pps(n,len,&live_filter.sps,&pi)<0){rejected_count++;return 0;}
  int same=(pps_len==len&&pps_len>0&&eq(pps,n,len));
  if(!same&&pps_len>0){codec_epoch_resets++;live_filter.cont.valid=0;cache_invalidate("codec-pps-change-invalidated-gop-cache");if(client_live){client_live=0;logmsg("codec-pps-change-client-waits-fresh-idr");}}
  live_filter.pps=pi;
  if(len<=sizeof(pps)){for(size_t i=0;i<len;i++)pps[i]=n[i];pps_len=len;}else pps_len=0;
  pps_count++;
  if(same&&cache_ready&&cache_append(n,len,0)<0)return -1;
  if(client_live&&send_framed(n,len)<0)return -1;
  return 1;
 }
 if(type==5||type==1){
  struct slice_info si;if(parse_slice_info(n,len,&live_filter,&si)<0||!accept_slice(&live_filter,&si)){rejected_count++;return 0;}
  if(type==5){
   idr_count++;
   if(si.first_mb==0){if(cache_reset_with_idr(n,len)<0)return -1;}else if(cache_append(n,len,0)<0)return -1;
   if(client_live){if(send_framed(n,len)<0)return -1;}else if(sps_len&&pps_len){if(begin_live_at_idr(n,len)<0)return -1;}
   write_status();
  }else{
   slice_count++;
   if(cache_append(n,len,si.first_mb==0)<0)return -1;
   if(client_live){if(send_framed(n,len)<0)return -1;}else pre_idr_slices_dropped++;
  }
  return 1;
 }
 rejected_count++;return 0;
}
static long find_start_mem(const unsigned char*b,size_t n,size_t from,size_t*sc_len){for(size_t i=from;i+3<n;i++){if(b[i]==0&&b[i+1]==0&&b[i+2]==1){*sc_len=3;return(long)i;}if(i+4<n&&b[i]==0&&b[i+1]==0&&b[i+2]==0&&b[i+3]==1){*sc_len=4;return(long)i;}}return -1;}
static void parse_append(const unsigned char*d,size_t n){if(!n)return;if(n>PARSE_CAP){d+=n-PARSE_CAP;n=PARSE_CAP;parse_len=0;}if(parse_len+n>PARSE_CAP){size_t drop=(parse_len+n)-PARSE_CAP;if(drop>=parse_len)parse_len=0;else{for(size_t i=0;i<parse_len-drop;i++)parse_buf[i]=parse_buf[i+drop];parse_len-=drop;}}for(size_t i=0;i<n;i++)parse_buf[parse_len+i]=d[i];parse_len+=n;size_t l1=0;long s1=find_start_mem(parse_buf,parse_len,0,&l1);if(s1<0){if(parse_len>8){for(size_t i=0;i<8;i++)parse_buf[i]=parse_buf[parse_len-8+i];parse_len=8;}return;}size_t cur=(size_t)s1,cl=l1;for(;;){size_t nl=0;long s2=find_start_mem(parse_buf,parse_len,cur+cl,&nl);if(s2<0)break;size_t p=cur+cl,e=(size_t)s2;while(e>p&&parse_buf[e-1]==0)e--;if(e>p)process_validated_nal(parse_buf+p,e-p);cur=(size_t)s2;cl=nl;}if(cur>0){size_t r=parse_len-cur;for(size_t i=0;i<r;i++)parse_buf[i]=parse_buf[cur+i];parse_len=r;}}
static int capture_tail(int fd,off_t pos,size_t*len){size_t n=(size_t)(pos<(off_t)TAIL_BYTES?pos:(off_t)TAIL_BYTES);*len=n;if(!n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return -1;if(read_exact(fd,delivered_tail,n)<0)return -1;return sc3(SYS_lseek,fd,pos,SEEK_SET)<0?-1:0;}
static int same_generation(int fd,off_t pos,size_t n){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end<0||(off_t)end<pos)return 0;if(n==0)return pos==0;if(pos<(off_t)n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return 0;if(read_exact(fd,verify_tail,n)<0)return 0;return eq(delivered_tail,verify_tail,n);}
static void accept_if_ready(void){struct pollfd p;p.fd=listen_fd;p.events=POLLIN;p.revents=0;long r=sc3(SYS_poll,(long)&p,1,0);if(r<=0||!(p.revents&POLLIN))return;int c=(int)sc3(SYS_accept,listen_fd,0,0);if(c<0)return;if(client_fd>=0){sc1(SYS_close,client_fd);client_replaced_count++;logmsg("client-replaced-by-new-session");}client_fd=c;client_live=0;client_scan_pending=1;client_sessions++;struct timeval tv;tv.tv_sec=20;tv.tv_usec=0;sc5(SYS_setsockopt,c,SOL_SOCKET,SO_SNDTIMEO,(long)&tv,sizeof(tv));static const unsigned char magic[8]={'U','2','W','H','2','6','4','4'};if(sendall(c,magic,8)<0){drop_client("client-magic-send-failed",1);return;}logmsg(cache_ready?"client-connected-persistent-gop-cache-ready":"client-connected-waiting-cache-or-live-idr");write_status();}

void _start(void){reset_filter(&live_filter);cache_close();cache_ready=0;cache_building=0;cache_overflow=0;cache_bytes=0;cache_frames=0;listen_fd=(int)sc3(SYS_socket,AF_INET,SOCK_STREAM,0);if(listen_fd<0)sc1(SYS_exit,20);int one=1;sc5(SYS_setsockopt,listen_fd,SOL_SOCKET,SO_REUSEADDR,(long)&one,sizeof(one));struct sockaddr_in a;a.sin_family=AF_INET;a.sin_port=htons(15332);a.sin_addr=0;for(int i=0;i<8;i++)a.zero[i]=0;if(sc3(SYS_bind,listen_fd,(long)&a,sizeof(a))<0)sc1(SYS_exit,21);if(sc2(SYS_listen,listen_fd,2)<0)sc1(SYS_exit,22);logmsg("u2w-mainvideo-relay-v8.26-listening-15332-persistent-gop-bridge");write_status();int fd=-1;off_t pos=0;size_t tail_len=0;for(;;){accept_if_ready();if(fd<0){fd=(int)sc3(SYS_open,(long)live_path,O_RDONLY,0);if(fd<0){nap_ms(20);status_tick++;if(status_tick>=50){status_tick=0;write_status();}continue;}if(!same_generation(fd,pos,tail_len)){pos=0;tail_len=0;parse_len=0;sc3(SYS_lseek,fd,0,SEEK_SET);generation_changes++;logmsg("source-generation-change-preserve-validator-client-and-gop-cache");write_status();}else sc3(SYS_lseek,fd,pos,SEEK_SET);}if(client_fd>=0&&!client_live&&client_scan_pending){int br=begin_live_from_cache();if(br==0)br=begin_live_from_file_gop(fd,&pos,&tail_len,0);client_scan_pending=0;if(br<0){if(fd>=0)sc1(SYS_close,fd);fd=-1;continue;}}long r=sc3(SYS_read,fd,(long)io_buf,sizeof(io_buf));if(r>0){parse_append(io_buf,(size_t)r);pos+=(off_t)r;source_bytes+=(u32)r;continue;}if(!startup_scan_complete){startup_scan_complete=1;logmsg("startup-scan-complete-live-tail");write_status();}if(capture_tail(fd,pos,&tail_len)<0)tail_len=0;sc1(SYS_close,fd);fd=-1;nap_ms(10);status_tick++;if(status_tick>=100){status_tick=0;write_status();}}}
