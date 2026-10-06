/* U2W v8.32 safe bounded-checkpoint MainVideo relay.
 *
 * Safety-first data path:
 *   AppleCarPlay -> proven v8.11 /tmp/u2w_mainvideo_live.h264 mirror
 *                -> this standalone TCP/15332 relay -> iPhone
 *
 * v8.32 keeps v8.31's process-safety boundary while restoring only a small,
 * current-generation recovery checkpoint.  It performs one forward scan of the
 * CURRENT v8.11 mirror on on-demand startup, then tails live bytes.  It never
 * scans archived generations, never opens AppleCarPlay fds, and never restarts
 * or signals AppleCarPlay/ARMiPhoneIAP2.
 *
 * A checkpoint is hard-capped at 1.5 MiB and contains exactly one strictly
 * validated SPS/PPS/IDR epoch plus the validated dependent VCL chain observed
 * after that IDR.  A reference-frame discontinuity invalidates the checkpoint
 * and quarantines dependent pictures until the next genuine IDR.  While waiting
 * the relay sends zero-length transport heartbeats.
 *
 * The relay never opens AppleCarPlay fds, never patches/restarts AppleCarPlay,
 * and never routes long-lived H.264 through Boa.  Slow/broken clients are
 * bounded by a 1 second send timeout and are dropped rather than stalling the
 * live tail loop.
 *
 * Wire:
 *   8 bytes ASCII "U2WH2649"
 *   repeated [u32BE length][payload]
 *     length > 0 : one H.264 NAL (without Annex-B start code)
 *     length == 0: relay transport heartbeat (not H.264)
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
#define SEEK_SET 0
#define SEEK_END 2
#define PARSE_CAP (768*1024)
#define CHECKPOINT_CAP 1572864U
#define TAIL_BYTES 64
#define MAX_NAL_BYTES (512*1024)
#define MAX_PARAM_BYTES 256
#define MAX_RBSP_BYTES 512
#define EXPECT_WIDTH 800
#define EXPECT_HEIGHT 480
#define HEARTBEAT_IDLE_TICKS 200U /* 200 * 10ms = 2s while source is idle */

static const char live_path[]="/tmp/u2w_mainvideo_live.h264";
static const char status_tmp[]="/tmp/u2w_h264_relay_status.new";
static const char status_path[]="/tmp/u2w_h264_relay_status.txt";
static unsigned char io_buf[65536];
static unsigned char parse_buf[PARSE_CAP]; static size_t parse_len=0;
static unsigned char checkpoint_buf[CHECKPOINT_CAP]; static size_t checkpoint_len=0; static u32 checkpoint_nals=0;
static unsigned char rbsp[MAX_RBSP_BYTES];
static unsigned char delivered_tail[TAIL_BYTES],verify_tail[TAIL_BYTES];
static unsigned char sps[256],pps[256]; static size_t sps_len=0,pps_len=0;
static int listen_fd=-1,client_fd=-1,client_live=0,live_edge_initialized=0,startup_scan_active=1,startup_scan_complete=0;
static u32 source_bytes=0,generation_changes=0,sps_count=0,pps_count=0,idr_count=0,slice_count=0,rejected_count=0;
static u32 client_sessions=0,client_bootstraps=0,client_send_failures=0,client_replaced_count=0;
static u32 pre_idr_slices_dropped=0,status_tick=0,last_bootstrap_source_bytes=0,last_nal_type=0,heartbeat_count=0,codec_epoch_resets=0;
static u32 waiting_slices_since_heartbeat=0;
static u32 checkpoint_valid=0,checkpoint_building=0,checkpoint_expired=0,checkpoint_replays=0,checkpoint_invalidations=0;
static u32 frame_num_discontinuities=0,false_idr_rejects=0,last_ref_frame_num=0,last_ref_modulus=0;
static int have_last_ref=0,awaiting_reference_idr=1;

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
struct br{const unsigned char*p;size_t n;size_t bit;int error;};
static unsigned br_bit(struct br*b){if(b->bit>=b->n*8){b->error=1;return 0;}unsigned v=(b->p[b->bit>>3]>>(7-(b->bit&7)))&1;b->bit++;return v;}
static unsigned br_bits(struct br*b,unsigned n){unsigned v=0;if(n>24){b->error=1;return 0;}for(unsigned i=0;i<n;i++)v=(v<<1)|br_bit(b);return v;}
static unsigned br_ue(struct br*b){unsigned z=0;while(!b->error&&br_bit(b)==0){if(++z>24){b->error=1;return 0;}}if(b->error)return 0;return ((1u<<z)-1u)+(z?br_bits(b,z):0u);}
static int br_se(struct br*b){unsigned c=br_ue(b);return(c&1)?(int)((c+1)>>1):-(int)(c>>1);}
static size_t make_rbsp(const unsigned char*src,size_t n){size_t o=0;unsigned zeros=0;for(size_t i=0;i<n&&o<MAX_RBSP_BYTES;i++){unsigned char x=src[i];if(zeros>=2&&x==3){zeros=0;continue;}rbsp[o++]=x;if(x==0)zeros++;else zeros=0;}return o;}
struct sps_info{unsigned id,width,height,log2_max_frame_num_minus4,pic_order_cnt_type,log2_max_pic_order_cnt_lsb_minus4,frame_mbs_only_flag,delta_pic_order_always_zero_flag;int valid;};
struct pps_info{unsigned id,sps_id,bottom_field_pic_order_in_frame_present_flag;int valid;};
struct slice_info{unsigned first_mb,slice_type,pps_id,frame_num,nal_type,idr_pic_id;int valid;};
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
static int parse_slice_info(const unsigned char*nal,size_t n,const struct filter_state*s,struct slice_info*out){if(!s->sps.valid||!s->pps.valid||n<4||n>MAX_NAL_BYTES||(nal[0]&0x80))return -1;unsigned type=nal[0]&0x1f;if(type!=1&&type!=5)return -1;size_t prefix=n-1;if(prefix>MAX_RBSP_BYTES)prefix=MAX_RBSP_BYTES;size_t rn=make_rbsp(nal+1,prefix);struct br b={rbsp,rn,0,0};unsigned first=br_ue(&b),slice_type=br_ue(&b),pid=br_ue(&b);if(b.error||slice_type>9||pid!=s->pps.id)return -1;unsigned bits=s->sps.log2_max_frame_num_minus4+4;if(bits<4||bits>16)return -1;unsigned frame_num=br_bits(&b,bits);unsigned field=0;if(!s->sps.frame_mbs_only_flag){field=br_bit(&b);if(field)(void)br_bit(&b);}unsigned idr=0;if(type==5){idr=br_ue(&b);if(idr>65535)return -1;}if(s->sps.pic_order_cnt_type==0){unsigned pb=s->sps.log2_max_pic_order_cnt_lsb_minus4+4;if(pb<4||pb>16)return -1;(void)br_bits(&b,pb);if(s->pps.bottom_field_pic_order_in_frame_present_flag&&!field)(void)br_se(&b);}else if(s->sps.pic_order_cnt_type==1&&!s->sps.delta_pic_order_always_zero_flag){(void)br_se(&b);if(s->pps.bottom_field_pic_order_in_frame_present_flag&&!field)(void)br_se(&b);}if(b.error)return -1;out->first_mb=first;out->slice_type=slice_type;out->pps_id=pid;out->frame_num=frame_num;out->nal_type=type;out->idr_pic_id=idr;out->valid=1;return 0;}
static int accept_slice(struct filter_state*s,const struct slice_info*i){if(i->first_mb==0){s->cont.pps_id=i->pps_id;s->cont.frame_num=i->frame_num;s->cont.nal_type=i->nal_type;s->cont.idr_pic_id=i->idr_pic_id;s->cont.valid=1;return 1;}if(!s->cont.valid)return 0;return s->cont.pps_id==i->pps_id&&s->cont.frame_num==i->frame_num&&s->cont.nal_type==i->nal_type&&s->cont.idr_pic_id==i->idr_pic_id;}


static unsigned frame_modulus(void){unsigned bits=live_filter.sps.log2_max_frame_num_minus4+4;return (bits>=4&&bits<=16)?(1U<<bits):0U;}
static void invalidate_checkpoint(const char*why,int quarantine){checkpoint_len=0;checkpoint_nals=0;checkpoint_valid=0;checkpoint_building=0;checkpoint_expired=0;checkpoint_invalidations++;if(quarantine){awaiting_reference_idr=1;have_last_ref=0;live_filter.cont.valid=0;if(client_live)client_live=0;}logmsg(why);}
static int checkpoint_append_framed(const unsigned char*n,size_t len){if(!checkpoint_building)return 0;if(checkpoint_len+4+len>CHECKPOINT_CAP){checkpoint_len=0;checkpoint_nals=0;checkpoint_valid=0;checkpoint_building=0;checkpoint_expired=1;logmsg("checkpoint-hard-cap-expired-wait-next-idr");return -1;}checkpoint_buf[checkpoint_len++]=(len>>24)&255;checkpoint_buf[checkpoint_len++]=(len>>16)&255;checkpoint_buf[checkpoint_len++]=(len>>8)&255;checkpoint_buf[checkpoint_len++]=len&255;memcpy(checkpoint_buf+checkpoint_len,n,len);checkpoint_len+=len;checkpoint_nals++;checkpoint_valid=1;return 0;}
static int strict_idr(const struct slice_info*i){unsigned st=i->slice_type>=5U?i->slice_type-5U:i->slice_type;return i->nal_type==5&&(st==2U||st==4U)&&i->frame_num==0U;}
static void write_status(void){
 char b[2200];size_t o=0;
 o=addstr(b,o,sizeof(b),"relay_version=v8.32-safe-bounded-checkpoint\nrelay_port=15332\ntransport=length-framed-current-generation-checkpoint\nwire_magic=U2WH2649\nrelay_autostart=NO\nnavigation_dependency=NONE\napplecarplay_modified=NO\nadapter_h264_parser=VALIDATOR_ONLY\nadapter_video_cache=BOUNDED_CURRENT_CHECKPOINT\n");
 o=kvyn(b,o,sizeof(b),"client_connected=",client_fd>=0);o=addstr(b,o,sizeof(b),"client_state=");o=addstr(b,o,sizeof(b),client_fd<0?"NO_CLIENT\n":(client_live?"LIVE\n":"WAITING_SAFE_CHECKPOINT\n"));
 o=kvyn(b,o,sizeof(b),"startup_scan_complete=",startup_scan_complete);o=kvyn(b,o,sizeof(b),"have_sps=",sps_len>0);o=kvyn(b,o,sizeof(b),"have_pps=",pps_len>0);
 o=kvyn(b,o,sizeof(b),"checkpoint_valid=",checkpoint_valid);o=kvyn(b,o,sizeof(b),"checkpoint_building=",checkpoint_building);o=kvyn(b,o,sizeof(b),"checkpoint_expired=",checkpoint_expired);o=kv(b,o,sizeof(b),"checkpoint_bytes=",(u32)checkpoint_len);o=kv(b,o,sizeof(b),"checkpoint_nals=",checkpoint_nals);o=kv(b,o,sizeof(b),"checkpoint_cap_bytes=",CHECKPOINT_CAP);o=kv(b,o,sizeof(b),"checkpoint_replays=",checkpoint_replays);o=kv(b,o,sizeof(b),"checkpoint_invalidations=",checkpoint_invalidations);
 o=kv(b,o,sizeof(b),"frame_num_discontinuities=",frame_num_discontinuities);o=kv(b,o,sizeof(b),"false_idr_rejects=",false_idr_rejects);o=kvyn(b,o,sizeof(b),"waiting_reference_idr=",awaiting_reference_idr);
 o=kv(b,o,sizeof(b),"source_bytes_low32=",source_bytes);o=kv(b,o,sizeof(b),"source_generation_changes=",generation_changes);o=kv(b,o,sizeof(b),"sps=",sps_count);o=kv(b,o,sizeof(b),"pps=",pps_count);o=kv(b,o,sizeof(b),"idr=",idr_count);o=kv(b,o,sizeof(b),"slices=",slice_count);o=kv(b,o,sizeof(b),"rejected_nals=",rejected_count);
 o=kv(b,o,sizeof(b),"client_sessions=",client_sessions);o=kv(b,o,sizeof(b),"client_bootstraps=",client_bootstraps);o=kv(b,o,sizeof(b),"client_send_failures=",client_send_failures);o=kv(b,o,sizeof(b),"client_replaced_count=",client_replaced_count);o=kv(b,o,sizeof(b),"pre_idr_slices_dropped=",pre_idr_slices_dropped);o=kv(b,o,sizeof(b),"transport_heartbeats=",heartbeat_count);o=kv(b,o,sizeof(b),"codec_epoch_resets=",codec_epoch_resets);o=kv(b,o,sizeof(b),"last_bootstrap_source_bytes=",last_bootstrap_source_bytes);o=kv(b,o,sizeof(b),"last_nal_type=",last_nal_type);
 int f=(int)sc3(SYS_open,(long)status_tmp,O_WRONLY|O_CREAT|O_TRUNC,0644);if(f>=0){writeall_fd(f,(unsigned char*)b,o);sc1(SYS_close,f);sc2(SYS_rename,(long)status_tmp,(long)status_path);}
}
static void drop_client(const char*why,int failure){if(client_fd>=0){sc1(SYS_close,client_fd);client_fd=-1;}client_live=0;if(failure)client_send_failures++;logmsg(why);write_status();}
static int send_framed(const unsigned char*n,size_t len){if(client_fd<0)return -1;unsigned char h[4];h[0]=(len>>24)&255;h[1]=(len>>16)&255;h[2]=(len>>8)&255;h[3]=len&255;if(sendall(client_fd,h,4)<0||(len&&sendall(client_fd,n,len)<0)){drop_client("client-send-failed",1);return -1;}return 0;}
static void send_idle_heartbeat(void){if(client_fd<0)return;if(send_framed((const unsigned char*)0,0)==0){heartbeat_count++;if((heartbeat_count&15U)==1U)write_status();}}
static int replay_checkpoint(void){if(client_fd<0||client_live||startup_scan_active||!checkpoint_valid||!sps_len||!pps_len)return 0;if(send_framed(sps,sps_len)<0||send_framed(pps,pps_len)<0)return -1;if(checkpoint_len&&sendall(client_fd,checkpoint_buf,checkpoint_len)<0){drop_client("checkpoint-replay-send-failed",1);return -1;}client_live=1;waiting_slices_since_heartbeat=0;client_bootstraps++;checkpoint_replays++;last_bootstrap_source_bytes=source_bytes;logmsg("client-bootstrap-safe-current-checkpoint");write_status();return 1;}
static int begin_live_at_idr(const unsigned char*n,size_t len){if(client_fd<0||client_live||startup_scan_active||!sps_len||!pps_len)return 0;if(send_framed(sps,sps_len)<0||send_framed(pps,pps_len)<0||send_framed(n,len)<0)return -1;client_live=1;waiting_slices_since_heartbeat=0;client_bootstraps++;last_bootstrap_source_bytes=source_bytes;logmsg("client-bootstrap-next-strict-live-idr");write_status();return 1;}
static void codec_reset(const char*why){live_filter.pps.valid=0;live_filter.cont.valid=0;pps_len=0;awaiting_reference_idr=1;have_last_ref=0;invalidate_checkpoint(why,1);codec_epoch_resets++;write_status();}
static void process_nal(const unsigned char*n,size_t len){
 if(len<1||len>MAX_NAL_BYTES){rejected_count++;return;}unsigned type=n[0]&0x1f;last_nal_type=(u32)type;
 if(type==7){struct sps_info si;if(parse_sps(n,len,&si)<0){rejected_count++;return;}int changed=sps_len>0&&(sps_len!=len||!eq(sps,n,len));if(changed)codec_reset("codec-sps-change-invalidate-checkpoint");if(len<=sizeof(sps)){memcpy(sps,n,len);sps_len=len;live_filter.sps=si;sps_count++;}return;}
 if(type==8){struct pps_info pi;if(parse_pps(n,len,&live_filter.sps,&pi)<0){rejected_count++;return;}int changed=pps_len>0&&(pps_len!=len||!eq(pps,n,len));if(changed){awaiting_reference_idr=1;have_last_ref=0;live_filter.cont.valid=0;invalidate_checkpoint("codec-pps-change-invalidate-checkpoint",1);codec_epoch_resets++;}if(len<=sizeof(pps)){memcpy(pps,n,len);pps_len=len;live_filter.pps=pi;pps_count++;}return;}
 if(type==1||type==5){struct slice_info si;if(parse_slice_info(n,len,&live_filter,&si)<0||!accept_slice(&live_filter,&si)){rejected_count++;return;}unsigned nal_ref_idc=(n[0]>>5)&3U;
  if(type==5){if(!strict_idr(&si)){false_idr_rejects++;rejected_count++;live_filter.cont.valid=0;return;}if(si.first_mb==0){checkpoint_len=0;checkpoint_nals=0;checkpoint_valid=0;checkpoint_building=1;checkpoint_expired=0;awaiting_reference_idr=0;have_last_ref=1;last_ref_frame_num=0;last_ref_modulus=frame_modulus();idr_count++;}checkpoint_append_framed(n,len);if(!startup_scan_active&&client_fd>=0){if(client_live){if(send_framed(n,len)<0)return;}else if(si.first_mb==0&&sps_len&&pps_len){if(begin_live_at_idr(n,len)<0)return;}}}
  else {slice_count++;if(si.first_mb==0){if(awaiting_reference_idr){pre_idr_slices_dropped++;rejected_count++;live_filter.cont.valid=0;return;}if(nal_ref_idc!=0&&have_last_ref&&last_ref_modulus){u32 expected=(last_ref_frame_num+1U)&(last_ref_modulus-1U);if(si.frame_num!=expected){frame_num_discontinuities++;rejected_count++;invalidate_checkpoint("reference-frame-num-break-invalidate-checkpoint",1);return;}}if(nal_ref_idc!=0){last_ref_frame_num=si.frame_num;last_ref_modulus=frame_modulus();have_last_ref=last_ref_modulus!=0;}}checkpoint_append_framed(n,len);if(!startup_scan_active&&client_fd>=0){if(client_live){if(send_framed(n,len)<0)return;}else{pre_idr_slices_dropped++;waiting_slices_since_heartbeat++;if(waiting_slices_since_heartbeat>=30U){waiting_slices_since_heartbeat=0;send_idle_heartbeat();}}}}
  if((idr_count+slice_count)%2048U==0U)write_status();return;}
}
static long find_start(const unsigned char*b,size_t n,size_t from,size_t*sc_len){for(size_t i=from;i+3<n;i++){if(b[i]==0&&b[i+1]==0&&b[i+2]==1){*sc_len=3;return (long)i;}if(i+4<n&&b[i]==0&&b[i+1]==0&&b[i+2]==0&&b[i+3]==1){*sc_len=4;return (long)i;}}return -1;}
static void parse_append(const unsigned char*d,size_t n){if(!n)return;if(n>PARSE_CAP){d+=n-PARSE_CAP;n=PARSE_CAP;parse_len=0;}if(parse_len+n>PARSE_CAP){size_t drop=(parse_len+n)-PARSE_CAP;if(drop>=parse_len)parse_len=0;else{for(size_t i=0;i<parse_len-drop;i++)parse_buf[i]=parse_buf[i+drop];parse_len-=drop;}}for(size_t i=0;i<n;i++)parse_buf[parse_len+i]=d[i];parse_len+=n;size_t l1=0;long s1=find_start(parse_buf,parse_len,0,&l1);if(s1<0){if(parse_len>8){for(size_t i=0;i<8;i++)parse_buf[i]=parse_buf[parse_len-8+i];parse_len=8;}return;}size_t cur=(size_t)s1,cl=l1;for(;;){size_t nl=0;long s2=find_start(parse_buf,parse_len,cur+cl,&nl);if(s2<0)break;size_t p=cur+cl,e=(size_t)s2;while(e>p&&parse_buf[e-1]==0)e--;if(e>p)process_nal(parse_buf+p,e-p);cur=(size_t)s2;cl=nl;}if(cur>0){size_t r=parse_len-cur;for(size_t i=0;i<r;i++)parse_buf[i]=parse_buf[cur+i];parse_len=r;}}
static int capture_tail(int fd,off_t pos,size_t*len){size_t n=(size_t)(pos<(off_t)TAIL_BYTES?pos:(off_t)TAIL_BYTES);*len=n;if(!n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return -1;if(read_exact(fd,delivered_tail,n)<0)return -1;return sc3(SYS_lseek,fd,pos,SEEK_SET)<0?-1:0;}
static int same_generation(int fd,off_t pos,size_t n){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end<0||(off_t)end<pos)return 0;if(n==0)return pos==0;if(pos<(off_t)n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return 0;if(read_exact(fd,verify_tail,n)<0)return 0;return eq(delivered_tail,verify_tail,n);}
static void accept_if_ready(void){struct pollfd p;p.fd=listen_fd;p.events=POLLIN;p.revents=0;long r=sc3(SYS_poll,(long)&p,1,0);if(r<=0||!(p.revents&POLLIN))return;int c=(int)sc3(SYS_accept,listen_fd,0,0);if(c<0)return;if(client_fd>=0){sc1(SYS_close,client_fd);client_replaced_count++;logmsg("client-replaced-by-new-session");}client_fd=c;client_live=0;waiting_slices_since_heartbeat=0;client_sessions++;struct timeval tv;tv.tv_sec=1;tv.tv_usec=0;sc5(SYS_setsockopt,c,SOL_SOCKET,SO_SNDTIMEO,(long)&tv,sizeof(tv));static const unsigned char magic[8]={'U','2','W','H','2','6','4','9'};if(sendall(c,magic,8)<0){drop_client("client-magic-send-failed",1);return;}if(replay_checkpoint()>0)logmsg("client-connected-replayed-safe-checkpoint");else logmsg("client-connected-waiting-safe-checkpoint");write_status();}
void _start(void){listen_fd=(int)sc3(SYS_socket,AF_INET,SOCK_STREAM,0);if(listen_fd<0)sc1(SYS_exit,20);int one=1;sc5(SYS_setsockopt,listen_fd,SOL_SOCKET,SO_REUSEADDR,(long)&one,sizeof(one));struct sockaddr_in a;a.sin_family=AF_INET;a.sin_port=htons(15332);a.sin_addr=0;for(int i=0;i<8;i++)a.zero[i]=0;if(sc3(SYS_bind,listen_fd,(long)&a,sizeof(a))<0)sc1(SYS_exit,21);if(sc2(SYS_listen,listen_fd,2)<0)sc1(SYS_exit,22);reset_filter(&live_filter);logmsg("u2w-mainvideo-relay-v8.32-listening-15332-safe-checkpoint");write_status();int fd=-1;off_t pos=0;size_t tail_len=0;u32 idle_ticks=0,eof_ticks=0;for(;;){accept_if_ready();if(fd<0){fd=(int)sc3(SYS_open,(long)live_path,O_RDONLY,0);if(fd<0){nap_ms(20);idle_ticks+=2;if(client_fd>=0&&idle_ticks>=HEARTBEAT_IDLE_TICKS){idle_ticks=0;send_idle_heartbeat();}continue;}if(!live_edge_initialized){pos=0;tail_len=0;sc3(SYS_lseek,fd,0,SEEK_SET);live_edge_initialized=1;startup_scan_active=1;startup_scan_complete=0;logmsg("startup-forward-scan-current-mirror-only");write_status();}else if(!same_generation(fd,pos,tail_len)){pos=0;tail_len=0;sc3(SYS_lseek,fd,0,SEEK_SET);generation_changes++;logmsg("source-generation-change-preserve-validator-check-continuity");write_status();}else sc3(SYS_lseek,fd,pos,SEEK_SET);eof_ticks=0;}long r=sc3(SYS_read,fd,(long)io_buf,sizeof(io_buf));if(r>0){parse_append(io_buf,(size_t)r);pos+=(off_t)r;source_bytes+=(u32)r;idle_ticks=0;eof_ticks=0;continue;}if(startup_scan_active){startup_scan_active=0;startup_scan_complete=1;logmsg("startup-forward-scan-complete");write_status();if(client_fd>=0&&!client_live)replay_checkpoint();}nap_ms(10);idle_ticks++;eof_ticks++;status_tick++;if(client_fd>=0&&idle_ticks>=HEARTBEAT_IDLE_TICKS){idle_ticks=0;send_idle_heartbeat();}if(status_tick>=500U){status_tick=0;write_status();}if(eof_ticks<20U)continue;if(capture_tail(fd,pos,&tail_len)<0)tail_len=0;sc1(SYS_close,fd);fd=-1;eof_ticks=0;}}
