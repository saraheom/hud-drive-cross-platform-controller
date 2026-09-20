/* U2W v8.24 bounded recent-IDR MainVideo H.264 relay.
 *
 * Reads only the stable v8.11 /tmp/u2w_mainvideo_live.h264 mirror. It never
 * opens AppleCarPlay fds, never modifies AppleCarPlay, and never uses Boa for
 * long-lived video traffic. One iPhone client connects directly to TCP/15332.
 *
 * Wire protocol:
 *   8 bytes ASCII "U2WH2643"
 *   repeated: [u32 big-endian NAL length][NAL bytes without Annex-B prefix]
 *
 * v8.24 keeps a small bounded recent decoder anchor to close the race observed in
 * the 2026-09-19 parked test: a valid IDR arrived milliseconds before the iPhone
 * connected, so v8.23 waited indefinitely for another IDR. The relay retains at
 * most 4 MiB from the latest validated IDR. A new client may bootstrap from that
 * recent SPS/PPS+IDR chain; if the chain has grown beyond the cap, it falls back
 * to waiting for the next naturally arriving live IDR. This is deliberately far
 * smaller than the unsafe 17-20 MiB v8.22 historical-GOP bursts.
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
#define PARSE_CAP (1024*1024)
#define TAIL_BYTES 64
#define MAX_NAL_BYTES (512*1024)
#define RECENT_CAP (4*1024*1024)
static const char live_path[]="/tmp/u2w_mainvideo_live.h264";
static const char status_tmp[]="/tmp/u2w_h264_relay_status.new";
static const char status_path[]="/tmp/u2w_h264_relay_status.txt";
static unsigned char io_buf[65536];
static unsigned char parse_buf[PARSE_CAP]; static size_t parse_len=0;
static unsigned char delivered_tail[TAIL_BYTES], verify_tail[TAIL_BYTES];
static unsigned char sps[256],pps[128]; static size_t sps_len=0,pps_len=0;
static unsigned char anchor_sps[256],anchor_pps[128]; static size_t anchor_sps_len=0,anchor_pps_len=0;
static unsigned char recent_buf[RECENT_CAP]; static size_t recent_len=0; static int recent_ready=0;
static int listen_fd=-1, client_fd=-1, client_live=0, startup_scan_complete=0;
static u32 source_bytes=0, generation_changes=0, sps_count=0,pps_count=0,idr_count=0,slice_count=0;
static u32 client_sessions=0,live_bootstrap_count=0,client_send_failures=0,pre_idr_slices_dropped=0,status_tick=0;
static u32 client_replaced_count=0,last_bootstrap_source_bytes=0,last_nal_type=0;
static u32 recent_anchor_resets=0,recent_anchor_overflows=0,recent_bootstrap_count=0,recent_anchor_source_bytes=0;
static long sc1(long n,long a){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;__asm__ volatile("svc 0":"+r"(r0):"r"(r7):"memory");return r0;}
static long sc2(long n,long a,long b){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r7):"memory");return r0;}
static long sc3(long n,long a,long b,long c){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory");return r0;}
static long sc5(long n,long a,long b,long c,long d,long e){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r7):"memory");return r0;}
static long sc6(long n,long a,long b,long c,long d,long e,long f){register long r7 __asm__("r7")=n;register long r0 __asm__("r0")=a;register long r1 __asm__("r1")=b;register long r2 __asm__("r2")=c;register long r3 __asm__("r3")=d;register long r4 __asm__("r4")=e;register long r5 __asm__("r5")=f;__asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory");return r0;}
static u16 htons(u16 x){return (u16)((x<<8)|(x>>8));}
static void nap_ms(long ms){struct timespec t;t.tv_sec=0;t.tv_nsec=ms*1000000L;sc2(SYS_nanosleep,(long)&t,0);}
static size_t slen(const char*s){size_t n=0;while(s[n])n++;return n;}
static int writeall_fd(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_write,fd,(long)(p+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int sendall(int fd,const unsigned char*p,size_t n){size_t o=0;while(o<n){long r=sc6(SYS_sendto,fd,(long)(p+o),n-o,MSG_NOSIGNAL,0,0);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static void logmsg(const char*s){writeall_fd(1,(const unsigned char*)s,slen(s));writeall_fd(1,(const unsigned char*)"\n",1);}
static int eq(const unsigned char*a,const unsigned char*b,size_t n){for(size_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int plausible_profile(unsigned char p){return p==66||p==77||p==88||p==100||p==110||p==122||p==244;}
static size_t addstr(char*b,size_t o,size_t cap,const char*s){while(*s&&o<cap)b[o++]=*s++;return o;}
static size_t addu32(char*b,size_t o,size_t cap,u32 v){static const u32 pw[10]={1000000000U,100000000U,10000000U,1000000U,100000U,10000U,1000U,100U,10U,1U};int started=0;for(int i=0;i<10;i++){unsigned char d=0;while(v>=pw[i]){v-=pw[i];d++;}if(d||started||i==9){if(o<cap)b[o++]=(char)('0'+d);started=1;}}return o;}
static size_t kv(char*b,size_t o,size_t cap,const char*k,u32 v){o=addstr(b,o,cap,k);o=addu32(b,o,cap,v);if(o<cap)b[o++]='\n';return o;}
static size_t kvyn(char*b,size_t o,size_t cap,const char*k,int yes){o=addstr(b,o,cap,k);o=addstr(b,o,cap,yes?"YES\n":"NO\n");return o;}
static void write_status(void){char b[1800];size_t o=0;o=addstr(b,o,sizeof(b),"relay_version=v8.24-recent-idr-tcp\nrelay_port=15332\ntransport=length-framed-nal-recent-idr\nwire_magic=U2WH2643\nrecent_anchor_cap_bytes=4194304\n");o=kvyn(b,o,sizeof(b),"client_connected=",client_fd>=0);o=addstr(b,o,sizeof(b),"client_state=");o=addstr(b,o,sizeof(b),client_fd<0?"NO_CLIENT\n":(client_live?"LIVE\n":"WAITING_BOOTSTRAP\n"));o=kvyn(b,o,sizeof(b),"startup_scan_complete=",startup_scan_complete);o=kvyn(b,o,sizeof(b),"have_sps=",sps_len>0);o=kvyn(b,o,sizeof(b),"have_pps=",pps_len>0);o=kvyn(b,o,sizeof(b),"recent_anchor_ready=",recent_ready&&anchor_sps_len&&anchor_pps_len&&recent_len>0);o=kv(b,o,sizeof(b),"recent_anchor_bytes=",(u32)recent_len);o=kv(b,o,sizeof(b),"recent_anchor_source_bytes=",recent_anchor_source_bytes);o=kv(b,o,sizeof(b),"recent_anchor_resets=",recent_anchor_resets);o=kv(b,o,sizeof(b),"recent_anchor_overflows=",recent_anchor_overflows);o=kv(b,o,sizeof(b),"recent_bootstraps=",recent_bootstrap_count);o=kv(b,o,sizeof(b),"source_bytes_low32=",source_bytes);o=kv(b,o,sizeof(b),"source_generation_changes=",generation_changes);o=kv(b,o,sizeof(b),"sps=",sps_count);o=kv(b,o,sizeof(b),"pps=",pps_count);o=kv(b,o,sizeof(b),"idr=",idr_count);o=kv(b,o,sizeof(b),"slices=",slice_count);o=kv(b,o,sizeof(b),"client_sessions=",client_sessions);o=kv(b,o,sizeof(b),"client_live_bootstraps=",live_bootstrap_count);o=kv(b,o,sizeof(b),"client_send_failures=",client_send_failures);o=kv(b,o,sizeof(b),"client_replaced_count=",client_replaced_count);o=kv(b,o,sizeof(b),"pre_idr_slices_dropped=",pre_idr_slices_dropped);o=kv(b,o,sizeof(b),"last_bootstrap_source_bytes=",last_bootstrap_source_bytes);o=kv(b,o,sizeof(b),"last_nal_type=",last_nal_type);int f=(int)sc3(SYS_open,(long)status_tmp,O_WRONLY|O_CREAT|O_TRUNC,0644);if(f>=0){writeall_fd(f,(unsigned char*)b,o);sc1(SYS_close,f);sc2(SYS_rename,(long)status_tmp,(long)status_path);}}
static void drop_client(const char*why,int count_failure){if(client_fd>=0){sc1(SYS_close,client_fd);client_fd=-1;}client_live=0;if(count_failure)client_send_failures++;logmsg(why);write_status();}
static int send_framed(const unsigned char*n,size_t len){if(client_fd<0)return -1;unsigned char h[4];h[0]=(len>>24)&255;h[1]=(len>>16)&255;h[2]=(len>>8)&255;h[3]=len&255;if(sendall(client_fd,h,4)<0||sendall(client_fd,n,len)<0){drop_client("client-send-failed",1);return -1;}return 0;}
static int recent_append(const unsigned char*n,size_t len){size_t need=4+len;if(!recent_ready)return 0;if(need>RECENT_CAP||recent_len+need>RECENT_CAP){recent_ready=0;recent_len=0;recent_anchor_overflows++;logmsg("recent-anchor-cap-exceeded-wait-next-idr");write_status();return -1;}recent_buf[recent_len]=(len>>24)&255;recent_buf[recent_len+1]=(len>>16)&255;recent_buf[recent_len+2]=(len>>8)&255;recent_buf[recent_len+3]=len&255;for(size_t i=0;i<len;i++)recent_buf[recent_len+4+i]=n[i];recent_len+=need;return 0;}
static void recent_reset_at_idr(const unsigned char*n,size_t len){recent_len=0;recent_ready=0;anchor_sps_len=0;anchor_pps_len=0;if(!sps_len||!pps_len||len<16||len>MAX_NAL_BYTES)return;for(size_t i=0;i<sps_len;i++)anchor_sps[i]=sps[i];anchor_sps_len=sps_len;for(size_t i=0;i<pps_len;i++)anchor_pps[i]=pps[i];anchor_pps_len=pps_len;recent_ready=1;recent_anchor_resets++;recent_anchor_source_bytes=source_bytes;if(recent_append(n,len)<0)return;}
static int begin_live_from_recent_anchor(void){if(client_fd<0||client_live||!startup_scan_complete||!recent_ready||!anchor_sps_len||!anchor_pps_len||!recent_len)return 0;if(send_framed(anchor_sps,anchor_sps_len)<0)return -1;if(send_framed(anchor_pps,anchor_pps_len)<0)return -1;size_t o=0;while(o+4<=recent_len){size_t len=((size_t)recent_buf[o]<<24)|((size_t)recent_buf[o+1]<<16)|((size_t)recent_buf[o+2]<<8)|(size_t)recent_buf[o+3];o+=4;if(!len||len>MAX_NAL_BYTES||o+len>recent_len){drop_client("recent-anchor-corrupt",1);return -1;}if(send_framed(recent_buf+o,len)<0)return -1;o+=len;}client_live=1;live_bootstrap_count++;recent_bootstrap_count++;last_bootstrap_source_bytes=source_bytes;logmsg("client-live-bootstrap-recent-idr-anchor");write_status();return 1;}
static int begin_live_at_idr(const unsigned char*n,size_t len){if(client_fd<0||client_live||!startup_scan_complete||!sps_len||!pps_len)return 0;if(send_framed(sps,sps_len)<0)return -1;if(send_framed(pps,pps_len)<0)return -1;if(send_framed(n,len)<0)return -1;client_live=1;live_bootstrap_count++;last_bootstrap_source_bytes=source_bytes;logmsg("client-live-bootstrap-fresh-sps-pps-idr");write_status();return 1;}
static void process_nal(const unsigned char*n,size_t len){if(len<1||len>MAX_NAL_BYTES)return;unsigned char h=n[0];if(h&0x80)return;int type=h&0x1f;last_nal_type=(u32)type;if(type==7){if(len>=4&&len<=128&&(h&0x60)&&plausible_profile(n[1])){sps_len=len>sizeof(sps)?0:len;if(sps_len){for(size_t i=0;i<len;i++)sps[i]=n[i];sps_count++;if(startup_scan_complete&&client_live)send_framed(n,len);}}return;}if(type==8){if(len>=2&&len<=96&&(h&0x60)){pps_len=len>sizeof(pps)?0:len;if(pps_len){for(size_t i=0;i<len;i++)pps[i]=n[i];pps_count++;if(startup_scan_complete&&client_live)send_framed(n,len);}}return;}if(type==5){if(!(h&0x60)||len<16)return;idr_count++;recent_reset_at_idr(n,len);if(client_fd>=0&&startup_scan_complete){if(client_live)send_framed(n,len);else if(sps_len&&pps_len)begin_live_at_idr(n,len);}write_status();return;}if(type==1){if(!(h&0x60)||len<4)return;slice_count++;if(recent_ready)recent_append(n,len);if(startup_scan_complete&&client_fd>=0){if(client_live)send_framed(n,len);else pre_idr_slices_dropped++;}return;}}
static long find_start(const unsigned char*b,size_t n,size_t from,size_t*sc_len){for(size_t i=from;i+3<n;i++){if(b[i]==0&&b[i+1]==0&&b[i+2]==1){*sc_len=3;return (long)i;}if(i+4<n&&b[i]==0&&b[i+1]==0&&b[i+2]==0&&b[i+3]==1){*sc_len=4;return (long)i;}}return -1;}
static void parse_append(const unsigned char*d,size_t n){if(!n)return;if(n>PARSE_CAP){d+=n-PARSE_CAP;n=PARSE_CAP;parse_len=0;}if(parse_len+n>PARSE_CAP){size_t drop=(parse_len+n)-PARSE_CAP;if(drop>=parse_len)parse_len=0;else{for(size_t i=0;i<parse_len-drop;i++)parse_buf[i]=parse_buf[i+drop];parse_len-=drop;}}for(size_t i=0;i<n;i++)parse_buf[parse_len+i]=d[i];parse_len+=n;size_t l1=0;long s1=find_start(parse_buf,parse_len,0,&l1);if(s1<0){if(parse_len>8){for(size_t i=0;i<8;i++)parse_buf[i]=parse_buf[parse_len-8+i];parse_len=8;}return;}size_t cur=(size_t)s1,cl=l1;for(;;){size_t nl=0;long s2=find_start(parse_buf,parse_len,cur+cl,&nl);if(s2<0)break;size_t p=cur+cl,e=(size_t)s2;while(e>p&&parse_buf[e-1]==0)e--;if(e>p)process_nal(parse_buf+p,e-p);cur=(size_t)s2;cl=nl;}if(cur>0){size_t r=parse_len-cur;for(size_t i=0;i<r;i++)parse_buf[i]=parse_buf[cur+i];parse_len=r;}}
static int read_exact(int fd,unsigned char*out,size_t n){size_t o=0;while(o<n){long r=sc3(SYS_read,fd,(long)(out+o),n-o);if(r<=0)return -1;o+=(size_t)r;}return 0;}
static int capture_tail(int fd,off_t pos,size_t*len){size_t n=(size_t)(pos<(off_t)TAIL_BYTES?pos:(off_t)TAIL_BYTES);*len=n;if(!n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return -1;if(read_exact(fd,delivered_tail,n)<0)return -1;return sc3(SYS_lseek,fd,pos,SEEK_SET)<0?-1:0;}
static int same_generation(int fd,off_t pos,size_t n){long end=sc3(SYS_lseek,fd,0,SEEK_END);if(end<0||(off_t)end<pos)return 0;if(n==0)return pos==0;if(pos<(off_t)n)return 0;if(sc3(SYS_lseek,fd,pos-(off_t)n,SEEK_SET)<0)return 0;if(read_exact(fd,verify_tail,n)<0)return 0;return eq(delivered_tail,verify_tail,n);}
static void accept_if_ready(void){struct pollfd p;p.fd=listen_fd;p.events=POLLIN;p.revents=0;long r=sc3(SYS_poll,(long)&p,1,0);if(r<=0||!(p.revents&POLLIN))return;int c=(int)sc3(SYS_accept,listen_fd,0,0);if(c<0)return;if(client_fd>=0){sc1(SYS_close,client_fd);client_replaced_count++;logmsg("client-replaced-by-new-session");}client_fd=c;client_live=0;client_sessions++;struct timeval tv;tv.tv_sec=8;tv.tv_usec=0;sc5(SYS_setsockopt,c,SOL_SOCKET,SO_SNDTIMEO,(long)&tv,sizeof(tv));static const unsigned char magic[8]={'U','2','W','H','2','6','4','3'};if(sendall(c,magic,8)<0){drop_client("client-magic-send-failed",1);return;}if(startup_scan_complete&&recent_ready&&anchor_sps_len&&anchor_pps_len&&recent_len){logmsg("client-connected-recent-anchor-available");if(begin_live_from_recent_anchor()!=1)return;}else logmsg("client-connected-waiting-bootstrap-idr");write_status();}
void _start(void){listen_fd=(int)sc3(SYS_socket,AF_INET,SOCK_STREAM,0);if(listen_fd<0)sc1(SYS_exit,20);int one=1;sc5(SYS_setsockopt,listen_fd,SOL_SOCKET,SO_REUSEADDR,(long)&one,sizeof(one));struct sockaddr_in a;a.sin_family=AF_INET;a.sin_port=htons(15332);a.sin_addr=0;for(int i=0;i<8;i++)a.zero[i]=0;if(sc3(SYS_bind,listen_fd,(long)&a,sizeof(a))<0)sc1(SYS_exit,21);if(sc2(SYS_listen,listen_fd,2)<0)sc1(SYS_exit,22);logmsg("u2w-mainvideo-relay-v8.24-listening-15332-recent-idr");write_status();int fd=-1;off_t pos=0;size_t tail_len=0;for(;;){accept_if_ready();if(fd<0){fd=(int)sc3(SYS_open,(long)live_path,O_RDONLY,0);if(fd<0){nap_ms(20);status_tick++;if(status_tick>=50){status_tick=0;write_status();}continue;}if(!same_generation(fd,pos,tail_len)){pos=0;tail_len=0;sc3(SYS_lseek,fd,0,SEEK_SET);generation_changes++;/* v8.11 rolls the mirror at write boundaries while the H.264 encoder itself remains continuous. Preserve parse_len across that file-generation handoff so an Annex-B NAL split across the rollover is not discarded. A true CarPlay restart will emit fresh parameter sets/IDR and naturally resynchronize. */logmsg("source-generation-change-parser-continuity-preserved");}else sc3(SYS_lseek,fd,pos,SEEK_SET);}long r=sc3(SYS_read,fd,(long)io_buf,sizeof(io_buf));if(r>0){parse_append(io_buf,(size_t)r);pos+=(off_t)r;source_bytes+=(u32)r;continue;}if(!startup_scan_complete){startup_scan_complete=1;logmsg("startup-scan-complete-live-tail");if(client_fd>=0&&!client_live&&recent_ready&&anchor_sps_len&&anchor_pps_len&&recent_len){logmsg("startup-scan-client-bootstrap-from-recent-anchor");begin_live_from_recent_anchor();}write_status();}if(capture_tail(fd,pos,&tail_len)<0)tail_len=0;sc1(SYS_close,fd);fd=-1;nap_ms(10);status_tick++;if(status_tick>=100){status_tick=0;write_status();}}}
