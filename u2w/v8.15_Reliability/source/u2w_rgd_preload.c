/*
 * U2W CarPlay data shim (v8.8 Route Guidance + passive Now Playing + active lane resolver)
 * ARM/Linux LD_PRELOAD interposer for Carlinkit ARMiPhoneIAP2.
 *
 * Scope:
 *   - Patch outgoing iAP2 IdentificationInformation (0x1D01):
 *       * messagesSentByAccessory += 0x5200, 0x5203
 *       * messagesReceivedFromDevice += 0x5201, 0x5202, 0x5204
 *       * append RouteGuidanceDisplayComponent Identify TLV (0x001E)
 *   - Piggyback StartRouteGuidanceUpdates (0x5200) after the first
 *     outgoing StartNowPlayingUpdates (0x5000), and retry on outgoing
 *     LocationInformation (0xFFFB) until a 0x5201/2/4 response arrives.
 *   - Observe and preserve raw incoming 0x5201/0x5202/0x5204 messages.
 *   - Passively merge incoming 0x5001 NowPlayingUpdate deltas and export
 *     normalized media JSON without changing stock Now Playing negotiation.
 *   - Passively reassemble the JPEG artwork transfer already requested by
 *     the stock runtime.
 *
 * It does NOT modify the protected ARMiPhoneIAP2 binary in memory or on disk.
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef signed short s16;
typedef signed int s32;
typedef unsigned long size_t;
typedef long ssize_t;
typedef int socklen_t;

struct iovec { void *iov_base; size_t iov_len; };
struct msghdr {
    void *msg_name;
    socklen_t msg_namelen;
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
#define PR_SET_NAME 15

extern void *dlsym(void *, const char *);
extern void *malloc(size_t);
extern void free(void *);
extern void *memcpy(void *, const void *, size_t);
extern void *memset(void *, int, size_t);
extern size_t strlen(const char *);
extern int memcmp(const void *, const void *, size_t);
extern int open(const char *, int, ...);
extern int close(int);
extern int rename(const char *, const char *);
extern int unlink(const char *);
extern int snprintf(char *, size_t, const char *, ...);
extern int prctl(int, ...);

static ssize_t (*real_write_fn)(int,const void*,size_t);
static ssize_t (*real_send_fn)(int,const void*,size_t,int);
static ssize_t (*real_sendto_fn)(int,const void*,size_t,int,const void*,socklen_t);
static ssize_t (*real_read_fn)(int,void*,size_t);
static ssize_t (*real_recv_fn)(int,void*,size_t,int);
static ssize_t (*real_recvfrom_fn)(int,void*,size_t,int,void*,socklen_t*);
static ssize_t (*real_writev_fn)(int,const struct iovec*,int);
static ssize_t (*real_sendmsg_fn)(int,const struct msghdr*,int);
static ssize_t (*real_recvmsg_fn)(int,struct msghdr*,int);
static size_t (*real_fwrite_fn)(const void*,size_t,size_t,void*);
static size_t (*real_fwrite_unlocked_fn)(const void*,size_t,size_t,void*);
static size_t (*real_fread_fn)(void*,size_t,size_t,void*);
static size_t (*real_fread_unlocked_fn)(void*,size_t,size_t,void*);

static volatile int g_guard = 0;
/* v8.15: JSON publication can be called from multiple ARMiPhoneIAP2 threads.
 * v8.8 used one shared scratch buffer + one fixed .tmp pathname with no lock,
 * allowing concurrent route/media callbacks to expose malformed snapshots.
 * Keep atomic rename and serialize each writer around build + write + rename. */
static volatile int g_live_json_lock = 0;
static volatile int g_media_json_lock = 0;
static void json_lock(volatile int *lock){ while(__sync_lock_test_and_set(lock,1)){} __sync_synchronize(); }
static void json_unlock(volatile int *lock){ __sync_synchronize(); __sync_lock_release(lock); }

static volatile int g_identify_prepared = 0;
static volatile int g_identify_patched = 0;
static volatile int g_sent_5200 = 0;
static volatile int g_got_520x = 0;
static volatile u32 g_count_5200 = 0;
static volatile u32 g_count_5201 = 0;
static volatile u32 g_count_5202 = 0;
static volatile u32 g_count_5204 = 0;
static volatile u32 g_last_5201_len = 0;
static volatile u32 g_last_5202_len = 0;
static volatile u32 g_last_5204_len = 0;
static volatile u32 g_identify_seen = 0;
static volatile u32 g_wifi_identify_seen = 0;
static volatile u32 g_nonwifi_identify_seen = 0;
static volatile u32 g_identify_patch_count = 0;
static volatile u32 g_seen_tx_control = 0;
static volatile u32 g_seen_rx_control = 0;
static volatile u32 g_identify_accept_seen = 0;
static volatile u32 g_tx_write_calls = 0;
static volatile u32 g_tx_send_calls = 0;
static volatile u32 g_tx_sendto_calls = 0;
static volatile u32 g_tx_writev_calls = 0;
static volatile u32 g_tx_sendmsg_calls = 0;
static volatile u32 g_tx_fwrite_calls = 0;
static volatile u32 g_tx_fwrite_unlocked_calls = 0;
static volatile u32 g_tx_candidate_records = 0;
static volatile u32 g_tx_ident_signature_calls = 0;
static volatile u32 g_rx_unknown_52xx = 0;
static volatile u32 g_rx_read_calls = 0;
static volatile u32 g_rx_recv_calls = 0;
static volatile u32 g_rx_recvfrom_calls = 0;
static volatile u32 g_rx_recvmsg_calls = 0;
static volatile u32 g_rx_fread_calls = 0;
static volatile u32 g_rx_fread_unlocked_calls = 0;
static volatile u32 g_rx_candidate_records = 0;
static volatile u32 g_tx_aa55_frames = 0;
static volatile u32 g_tx_aa55_patched = 0;
static volatile u32 g_rx_aa55_frames = 0;

static char g_current_road[160];
static char g_destination[160];
static char g_distance_string[80];
static char g_dist_to_maneuver_string[80];
static char g_source_name[80];
static char g_maneuver_desc[200];
static char g_after_road[160];
static u32 g_distance_remaining;
static u32 g_dist_to_maneuver;
static u16 g_maneuver_index;
static u8  g_route_state;
static u8  g_maneuver_type;

/* v8.5 normalized live-export state.  Keep the fields fixed-size and simple so
 * the old ARM runtime does not gain any allocator or C++ dependencies. */
#define RGD_MAX_MANEUVERS 32
struct rgd_maneuver_state {
    u8 valid;
    u16 index;
    u8 type;
    u8 driving_side;
    u32 distance_meters;
    u8 display_units;
    char description[200];
    char after_road[160];
    char display_distance[80];
};
static struct rgd_maneuver_state g_maneuvers[RGD_MAX_MANEUVERS];
static u32 g_live_sequence;
static u32 g_estimated_arrival_unix;
static u32 g_time_remaining;
static u8 g_distance_remaining_units;
static u8 g_dist_to_maneuver_units;
static u16 g_current_maneuver_index;
static u16 g_next_maneuver_index;
static u16 g_maneuver_count;
static u8 g_have_current_maneuver;
static u8 g_have_next_maneuver;
static u8 g_lane_guidance_showing;

/* v8.8 lane resolver.
 *
 * Physical Google Maps captures plus iOS 26.1 Route Guidance reverse-
 * engineering show that 0x5204 TLV 0x0001 is a composedGuidanceEventIndex,
 * NOT a route maneuver index. iOS can pre-cache several 0x5204 events in one
 * burst, then RouteGuidanceUpdate (0x5201) InfoType 0x0010 selects which cached
 * guidance event is current. InfoType 0x0012 is the stock showing flag.
 *
 * v8.7 kept only the last 0x5204 packet, losing burst entries and incorrectly
 * naming the event id maneuverIndex. v8.8 keeps a bounded event-id cache and
 * exports the event selected by 0x5201 InfoType 16. */
#define RGD_MAX_LANES 12
#define RGD_MAX_LANE_ANGLES 4
#define RGD_MAX_LANE_EVENTS 32
struct rgd_lane_state {
    u8 valid;
    u16 index;
    u8 status;
    u8 angle_count;
    s16 angles[RGD_MAX_LANE_ANGLES];
};
struct rgd_lane_event_state {
    u8 valid;
    u16 event_index;
    u8 lane_count;
    u32 sequence;
    u32 last_use;
    struct rgd_lane_state lanes[RGD_MAX_LANES];
};
static struct rgd_lane_event_state g_lane_events[RGD_MAX_LANE_EVENTS];
static u16 g_active_lane_guidance_index;
static u8 g_have_active_lane_guidance_index;
static u32 g_lane_sequence;
static u32 g_lane_cache_clock;

static char g_live_json[32768];

/* v8.8 retains the v8.6 passive Now Playing exporter. 0x5001 is delta-based: fields omitted
 * from a later update MUST retain their previous value. */
static volatile u32 g_count_5001;
static volatile u32 g_last_5001_len;
static u32 g_media_sequence;
static u32 g_media_track_id_low;
static u32 g_media_duration_ms;
static u32 g_media_elapsed_ms;
static u32 g_media_queue_index;
static u32 g_media_queue_count;
static u16 g_media_track_number;
static u16 g_media_track_count;
static u8 g_media_playback_status;
static u8 g_media_shuffle_mode;
static u8 g_media_repeat_mode;
static u8 g_media_artwork_transfer_id;
static u32 g_media_artwork_sequence;
static u32 g_media_artwork_bytes;
static u8 g_media_artwork_available;
static char g_media_title[256];
static char g_media_artist[256];
static char g_media_album[256];
static char g_media_app[128];
static char g_media_bundle[192];
static char g_media_json[4096];

#define MEDIA_ART_MAX_BYTES 1572864
static u8 g_art_capturing;
static u8 g_art_prev_ff;
static u32 g_art_capture_bytes;

static u16 be16(const u8 *p) { return (u16)(((u16)p[0]<<8)|p[1]); }
static u32 be32(const u8 *p) { return ((u32)p[0]<<24)|((u32)p[1]<<16)|((u32)p[2]<<8)|p[3]; }
static void put16(u8 *p,u16 v){p[0]=(u8)(v>>8);p[1]=(u8)v;}
static u32 le32(const u8 *p){return (u32)p[0]|((u32)p[1]<<8)|((u32)p[2]<<16)|((u32)p[3]<<24);}
static void putle32(u8 *p,u32 v){p[0]=(u8)v;p[1]=(u8)(v>>8);p[2]=(u8)(v>>16);p[3]=(u8)(v>>24);}

static u8 cksum(const u8 *p,size_t n){
    u32 s=0; size_t i; for(i=0;i<n;i++) s+=p[i]; return (u8)(0-(u8)s);
}

static void ensure_real(void){
    if (!real_write_fn) real_write_fn=(ssize_t(*)(int,const void*,size_t))dlsym(RTLD_NEXT,"write");
    if (!real_send_fn) real_send_fn=(ssize_t(*)(int,const void*,size_t,int))dlsym(RTLD_NEXT,"send");
    if (!real_sendto_fn) real_sendto_fn=(ssize_t(*)(int,const void*,size_t,int,const void*,socklen_t))dlsym(RTLD_NEXT,"sendto");
    if (!real_read_fn) real_read_fn=(ssize_t(*)(int,void*,size_t))dlsym(RTLD_NEXT,"read");
    if (!real_recv_fn) real_recv_fn=(ssize_t(*)(int,void*,size_t,int))dlsym(RTLD_NEXT,"recv");
    if (!real_recvfrom_fn) real_recvfrom_fn=(ssize_t(*)(int,void*,size_t,int,void*,socklen_t*))dlsym(RTLD_NEXT,"recvfrom");
    if (!real_writev_fn) real_writev_fn=(ssize_t(*)(int,const struct iovec*,int))dlsym(RTLD_NEXT,"writev");
    if (!real_sendmsg_fn) real_sendmsg_fn=(ssize_t(*)(int,const struct msghdr*,int))dlsym(RTLD_NEXT,"sendmsg");
    if (!real_recvmsg_fn) real_recvmsg_fn=(ssize_t(*)(int,struct msghdr*,int))dlsym(RTLD_NEXT,"recvmsg");
    if (!real_fwrite_fn) real_fwrite_fn=(size_t(*)(const void*,size_t,size_t,void*))dlsym(RTLD_NEXT,"fwrite");
    if (!real_fwrite_unlocked_fn) real_fwrite_unlocked_fn=(size_t(*)(const void*,size_t,size_t,void*))dlsym(RTLD_NEXT,"fwrite_unlocked");
    if (!real_fread_fn) real_fread_fn=(size_t(*)(void*,size_t,size_t,void*))dlsym(RTLD_NEXT,"fread");
    if (!real_fread_unlocked_fn) real_fread_unlocked_fn=(size_t(*)(void*,size_t,size_t,void*))dlsym(RTLD_NEXT,"fread_unlocked");
}

static void file_append(const char *path,const void *buf,size_t n){
    int fd; ensure_real(); if(!real_write_fn) return;
    fd=open(path,O_WRONLY|O_CREAT|O_APPEND,0644); if(fd<0)return;
    real_write_fn(fd,buf,n); close(fd);
}
static void log_line(const char *s){ if(s) file_append("/tmp/u2w_rgd.log",s,strlen(s)); }

static int marker_exists(const char *path){ int fd=open(path,0); if(fd<0)return 0; close(fd); return 1; }
static void touch_marker(const char *path){ int fd=open(path,O_WRONLY|O_CREAT,0644); if(fd>=0)close(fd); }


static void raw_record_ex(const char *path,u16 msgid,u16 flags,const u8 *msg,size_t n){
    u8 h[12];
    h[0]='U';h[1]='2';h[2]='W';h[3]='R';
    h[4]=(u8)(msgid>>8);h[5]=(u8)msgid;
    h[6]=(u8)(flags>>8);h[7]=(u8)flags;
    h[8]=(u8)(n>>24);h[9]=(u8)(n>>16);h[10]=(u8)(n>>8);h[11]=(u8)n;
    file_append(path,h,sizeof(h)); file_append(path,msg,n);
}
static void raw_record(const char *path,u16 msgid,const u8 *msg,size_t n){ raw_record_ex(path,msgid,0,msg,n); }

/* Keep a bounded sample of early/suspicious TX buffers. This is diagnostic only:
 * it lets us identify the Wi-Fi iAP2 write path if it differs from the BT path. */
static int has_ident_signature(const u8 *b,size_t n){
    size_t i; if(!b)return 0;
    for(i=0;i+5<n;i++){
        if(b[i]==0x40&&b[i+1]==0x40&&b[i+4]==0x1d&&b[i+5]==0x01)return 1;
    }
    return 0;
}
static int has_iap2_signature(const u8 *b,size_t n){
    size_t i; if(!b)return 0;
    for(i=0;i+1<n;i++) if((b[i]==0xff&&b[i+1]==0x5a)||(b[i]==0x40&&b[i+1]==0x40))return 1;
    return 0;
}
static void capture_tx_candidate(u16 api,const u8 *b,size_t n){
    int ident=has_ident_signature(b,n); int sig=has_iap2_signature(b,n); size_t take=n;
    if(ident) g_tx_ident_signature_calls++;
    if(g_tx_candidate_records>=160)return;
    /* Preserve all iAP2-looking buffers, plus the first 48 small writes before the Wi-Fi Identify is found. */
    if(!sig && !(g_tx_candidate_records<48 && n<=4096))return;
    if(take>8192)take=8192;
    raw_record_ex("/tmp/u2w_rgd_tx_candidates.bin",api,(u16)((ident?1:0)|(sig?2:0)),b,take);
    g_tx_candidate_records++;
}

static void capture_rx_candidate(u16 api,const u8 *b,size_t n){
    int sig=has_iap2_signature(b,n); size_t take=n;
    if(g_rx_candidate_records>=160)return;
    if(!sig && !(g_rx_candidate_records<32 && n<=4096))return;
    if(take>8192)take=8192;
    raw_record_ex("/tmp/u2w_rgd_rx_candidates.bin",api,(u16)(sig?2:0),b,take);
    g_rx_candidate_records++;
}

static void copy_text(char *dst,size_t cap,const u8 *src,size_t n){
    size_t i=0; if(!dst||cap==0)return;
    while(i<n && i+1<cap && src[i]) { u8 c=src[i]; dst[i]=(c>=0x20||c>=0x80)?(char)c:' '; i++; }
    dst[i]=0;
}

static u32 be64_low32(const u8 *p,size_t n){
    if(!p||n<8)return 0;
    /* Current Unix ETA seconds and remaining-second values fit in u32. */
    return be32(p+4);
}
static int text_equal(const char *a,const char *b){
    size_t i=0;if(!a||!b)return 0;
    while(a[i]&&b[i]){if(a[i]!=b[i])return 0;i++;}
    return a[i]==b[i];
}
static void clear_maneuvers(void){memset(g_maneuvers,0,sizeof(g_maneuvers));g_maneuver_count=0;g_have_current_maneuver=0;g_have_next_maneuver=0;}

static size_t json_puts(char *dst,size_t cap,size_t o,const char *src){
    size_t i=0;if(!dst||!src)return o;
    while(src[i]&&o+1<cap)dst[o++]=src[i++];
    if(o<cap)dst[o]=0;return o;
}
static size_t json_num(char *dst,size_t cap,size_t o,u32 v){
    char t[32];int n=snprintf(t,sizeof(t),"%u",v);if(n>0)return json_puts(dst,cap,o,t);return o;
}
static size_t json_snum(char *dst,size_t cap,size_t o,s32 v){
    char t[32];int n=snprintf(t,sizeof(t),"%d",v);if(n>0)return json_puts(dst,cap,o,t);return o;
}
static size_t json_q(char *dst,size_t cap,size_t o,const char *src){
    size_t i=0;o=json_puts(dst,cap,o,"\"");
    if(!src)src="";
    while(src[i]&&o+8<cap){u8 c=(u8)src[i++];
        if(c=='\"'||c=='\\'){dst[o++]='\\';dst[o++]=(char)c;}
        else if(c=='\n'){dst[o++]='\\';dst[o++]='n';}
        else if(c=='\r'){dst[o++]='\\';dst[o++]='r';}
        else if(c=='\t'){dst[o++]='\\';dst[o++]='t';}
        else if(c<0x20){dst[o++]=' ';}
        else dst[o++]=(char)c;
    }
    if(o+2<cap){dst[o++]='\"';dst[o]=0;}return o;
}
static void clear_lane_state(void){
    memset(g_lane_events,0,sizeof(g_lane_events));
    g_have_active_lane_guidance_index=0;
    g_active_lane_guidance_index=0;
    g_lane_cache_clock=0;
}
static struct rgd_lane_event_state *find_lane_event(u16 event_index){
    u32 i;
    for(i=0;i<RGD_MAX_LANE_EVENTS;i++){
        if(g_lane_events[i].valid && g_lane_events[i].event_index==event_index){
            return &g_lane_events[i];
        }
    }
    return NULL;
}
static struct rgd_lane_event_state *alloc_lane_event(u16 event_index){
    u32 i,slot=0;u32 oldest=0xffffffffu;
    struct rgd_lane_event_state *existing=find_lane_event(event_index);
    if(existing)return existing;
    for(i=0;i<RGD_MAX_LANE_EVENTS;i++){
        if(!g_lane_events[i].valid){slot=i;oldest=0;break;}
        /* Never evict the currently selected event if another slot exists. */
        if(g_have_active_lane_guidance_index && g_lane_events[i].event_index==g_active_lane_guidance_index)continue;
        if(g_lane_events[i].last_use<oldest){oldest=g_lane_events[i].last_use;slot=i;}
    }
    memset(&g_lane_events[slot],0,sizeof(g_lane_events[slot]));
    g_lane_events[slot].valid=1;
    g_lane_events[slot].event_index=event_index;
    g_lane_events[slot].last_use=++g_lane_cache_clock;
    return &g_lane_events[slot];
}
static struct rgd_lane_event_state *current_lane_event(void){
    if(!g_have_active_lane_guidance_index)return NULL;
    return find_lane_event(g_active_lane_guidance_index);
}

static void write_live_json(void){
    size_t o=0;u32 i;int fd;
    json_lock(&g_live_json_lock);
    o=json_puts(g_live_json,sizeof(g_live_json),o,"{\"version\":2,\"sequence\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_live_sequence);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"source\":");o=json_q(g_live_json,sizeof(g_live_json),o,g_source_name);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"routeState\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_route_state);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"active\":");o=json_puts(g_live_json,sizeof(g_live_json),o,g_route_state?"true":"false");
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"currentRoad\":");o=json_q(g_live_json,sizeof(g_live_json),o,g_current_road);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"destination\":");o=json_q(g_live_json,sizeof(g_live_json),o,g_destination);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"estimatedArrivalUnixSeconds\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_estimated_arrival_unix);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"timeRemainingSeconds\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_time_remaining);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceRemainingMeters\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_distance_remaining);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceRemainingText\":");o=json_q(g_live_json,sizeof(g_live_json),o,g_distance_string);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceRemainingUnits\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_distance_remaining_units);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceToManeuverMeters\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_dist_to_maneuver);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceToManeuverText\":");o=json_q(g_live_json,sizeof(g_live_json),o,g_dist_to_maneuver_string);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceToManeuverUnits\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_dist_to_maneuver_units);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"currentManeuverIndex\":");if(g_have_current_maneuver)o=json_num(g_live_json,sizeof(g_live_json),o,g_current_maneuver_index);else o=json_puts(g_live_json,sizeof(g_live_json),o,"null");
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"nextManeuverIndex\":");if(g_have_next_maneuver)o=json_num(g_live_json,sizeof(g_live_json),o,g_next_maneuver_index);else o=json_puts(g_live_json,sizeof(g_live_json),o,"null");
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"maneuverCount\":");o=json_num(g_live_json,sizeof(g_live_json),o,g_maneuver_count);
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"laneGuidanceShowing\":");o=json_puts(g_live_json,sizeof(g_live_json),o,g_lane_guidance_showing?"true":"false");
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"laneGuidanceIndex\":");if(g_have_active_lane_guidance_index)o=json_num(g_live_json,sizeof(g_live_json),o,g_active_lane_guidance_index);else o=json_puts(g_live_json,sizeof(g_live_json),o,"null");
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"laneGuidance\":");
    {
        struct rgd_lane_event_state *ev=current_lane_event();
        if(ev && ev->lane_count>0){
            u32 li,ai;
            o=json_puts(g_live_json,sizeof(g_live_json),o,"{\"sequence\":");o=json_num(g_live_json,sizeof(g_live_json),o,ev->sequence);
            o=json_puts(g_live_json,sizeof(g_live_json),o,",\"guidanceEventIndex\":");o=json_num(g_live_json,sizeof(g_live_json),o,ev->event_index);
            /* Deprecated compatibility alias: this is an event id, not a maneuver id. */
            o=json_puts(g_live_json,sizeof(g_live_json),o,",\"maneuverIndex\":null");
            o=json_puts(g_live_json,sizeof(g_live_json),o,",\"lanes\":[");
            for(li=0;li<ev->lane_count&&li<RGD_MAX_LANES;li++)if(ev->lanes[li].valid){
                struct rgd_lane_state *ln=&ev->lanes[li];
                if(g_live_json[o-1]!='[')o=json_puts(g_live_json,sizeof(g_live_json),o,",");
                o=json_puts(g_live_json,sizeof(g_live_json),o,"{\"index\":");o=json_num(g_live_json,sizeof(g_live_json),o,ln->index);
                o=json_puts(g_live_json,sizeof(g_live_json),o,",\"status\":");o=json_num(g_live_json,sizeof(g_live_json),o,ln->status);
                o=json_puts(g_live_json,sizeof(g_live_json),o,",\"recommended\":");o=json_puts(g_live_json,sizeof(g_live_json),o,ln->status==2?"true":"false");
                o=json_puts(g_live_json,sizeof(g_live_json),o,",\"angles\":[");
                for(ai=0;ai<ln->angle_count&&ai<RGD_MAX_LANE_ANGLES;ai++){if(ai)o=json_puts(g_live_json,sizeof(g_live_json),o,",");o=json_snum(g_live_json,sizeof(g_live_json),o,(s32)ln->angles[ai]);}
                o=json_puts(g_live_json,sizeof(g_live_json),o,"]}");
            }
            o=json_puts(g_live_json,sizeof(g_live_json),o,"]}");
        }else o=json_puts(g_live_json,sizeof(g_live_json),o,"null");
    }
    o=json_puts(g_live_json,sizeof(g_live_json),o,",\"maneuvers\":[");
    for(i=0;i<RGD_MAX_MANEUVERS;i++)if(g_maneuvers[i].valid){
        struct rgd_maneuver_state *m=&g_maneuvers[i];
        if(g_live_json[o-1]!='[')o=json_puts(g_live_json,sizeof(g_live_json),o,",");
        o=json_puts(g_live_json,sizeof(g_live_json),o,"{\"index\":");o=json_num(g_live_json,sizeof(g_live_json),o,m->index);
        o=json_puts(g_live_json,sizeof(g_live_json),o,",\"description\":");o=json_q(g_live_json,sizeof(g_live_json),o,m->description);
        o=json_puts(g_live_json,sizeof(g_live_json),o,",\"type\":");o=json_num(g_live_json,sizeof(g_live_json),o,m->type);
        o=json_puts(g_live_json,sizeof(g_live_json),o,",\"afterRoad\":");o=json_q(g_live_json,sizeof(g_live_json),o,m->after_road);
        o=json_puts(g_live_json,sizeof(g_live_json),o,",\"distanceMeters\":");o=json_num(g_live_json,sizeof(g_live_json),o,m->distance_meters);
        o=json_puts(g_live_json,sizeof(g_live_json),o,",\"displayDistanceText\":");o=json_q(g_live_json,sizeof(g_live_json),o,m->display_distance);
        o=json_puts(g_live_json,sizeof(g_live_json),o,",\"drivingSide\":");o=json_num(g_live_json,sizeof(g_live_json),o,m->driving_side);
        o=json_puts(g_live_json,sizeof(g_live_json),o,"}");
    }
    o=json_puts(g_live_json,sizeof(g_live_json),o,"]}\n");
    fd=open("/tmp/u2w_rgd_live.json.tmp",O_WRONLY|O_CREAT|O_TRUNC,0644);ensure_real();
    if(fd>=0&&real_write_fn){real_write_fn(fd,g_live_json,o);close(fd);rename("/tmp/u2w_rgd_live.json.tmp","/tmp/u2w_rgd_live.json");}
    json_unlock(&g_live_json_lock);
}

static void write_media_json(void){
    size_t o=0;int fd;
    json_lock(&g_media_json_lock);
    o=json_puts(g_media_json,sizeof(g_media_json),o,"{\"version\":1,\"sequence\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_sequence);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"receivedUpdates\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_count_5001);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"sourceApp\":");o=json_q(g_media_json,sizeof(g_media_json),o,g_media_app);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"sourceBundleID\":");o=json_q(g_media_json,sizeof(g_media_json),o,g_media_bundle);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"playbackStatus\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_playback_status);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"playing\":");o=json_puts(g_media_json,sizeof(g_media_json),o,g_media_playback_status==1?"true":"false");
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"title\":");o=json_q(g_media_json,sizeof(g_media_json),o,g_media_title);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"artist\":");o=json_q(g_media_json,sizeof(g_media_json),o,g_media_artist);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"album\":");o=json_q(g_media_json,sizeof(g_media_json),o,g_media_album);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"durationMs\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_duration_ms);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"elapsedMs\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_elapsed_ms);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"queueIndex\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_queue_index);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"queueCount\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_queue_count);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"trackNumber\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_track_number);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"trackCount\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_track_count);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"shuffleMode\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_shuffle_mode);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"repeatMode\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_repeat_mode);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"artworkTransferID\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_artwork_transfer_id);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"artworkSequence\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_artwork_sequence);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"artworkBytes\":");o=json_num(g_media_json,sizeof(g_media_json),o,g_media_artwork_bytes);
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"artworkAvailable\":");o=json_puts(g_media_json,sizeof(g_media_json),o,g_media_artwork_available?"true":"false");
    o=json_puts(g_media_json,sizeof(g_media_json),o,",\"artworkURL\":\"/cgi-bin/u2wmedia-artwork.cgi\"}\n");
    fd=open("/tmp/u2w_media_live.json.tmp",O_WRONLY|O_CREAT|O_TRUNC,0644);ensure_real();
    if(fd>=0&&real_write_fn){real_write_fn(fd,g_media_json,o);close(fd);rename("/tmp/u2w_media_live.json.tmp","/tmp/u2w_media_live.json");}
    json_unlock(&g_media_json_lock);
}

static void media_art_reset_for_new_id(u8 id){
    if(id==g_media_artwork_transfer_id)return;
    g_media_artwork_transfer_id=id;
    g_art_capturing=0;g_art_prev_ff=0;g_art_capture_bytes=0;
    g_media_artwork_bytes=0;g_media_artwork_available=0;
    unlink("/tmp/u2w_nowplaying_artwork.jpg");
    unlink("/tmp/u2w_nowplaying_artwork.tmp");
}

static void parse_5001_group_media(const u8 *p,size_t n){
    size_t o=0;
    while(o+4<=n){
        u16 L=be16(p+o),id=be16(p+o+2);const u8 *v;size_t vn;
        if(L<4||o+L>n)break;v=p+o+4;vn=L-4;
        if(id==0x0000 && vn>=8)g_media_track_id_low=be32(v+4);
        else if(id==0x0001)copy_text(g_media_title,sizeof(g_media_title),v,vn);
        else if(id==0x0004 && vn>=4)g_media_duration_ms=be32(v);
        else if(id==0x0006)copy_text(g_media_album,sizeof(g_media_album),v,vn);
        else if(id==0x0007 && vn>=2)g_media_track_number=be16(v);
        else if(id==0x0008 && vn>=2)g_media_track_count=be16(v);
        else if(id==0x000C)copy_text(g_media_artist,sizeof(g_media_artist),v,vn);
        else if((id==0x001A||id==0x0014) && vn>=1)media_art_reset_for_new_id(v[0]);
        o+=L;
    }
}
static void parse_5001_group_playback(const u8 *p,size_t n){
    size_t o=0;
    while(o+4<=n){
        u16 L=be16(p+o),id=be16(p+o+2);const u8 *v;size_t vn;
        if(L<4||o+L>n)break;v=p+o+4;vn=L-4;
        if(id==0x0000 && vn>=1)g_media_playback_status=v[0];
        else if(id==0x0001 && vn>=4)g_media_elapsed_ms=be32(v);
        else if(id==0x0002 && vn>=4)g_media_queue_index=be32(v);
        else if(id==0x0003 && vn>=4)g_media_queue_count=be32(v);
        else if(id==0x0005 && vn>=1)g_media_shuffle_mode=v[0];
        else if(id==0x0006 && vn>=1)g_media_repeat_mode=v[0];
        else if(id==0x0007)copy_text(g_media_app,sizeof(g_media_app),v,vn);
        else if(id==0x0010)copy_text(g_media_bundle,sizeof(g_media_bundle),v,vn);
        o+=L;
    }
}
static void parse_5001(const u8 *msg,size_t n){
    size_t o=6;
    while(o+4<=n){
        u16 L=be16(msg+o),id=be16(msg+o+2);const u8 *v;size_t vn;
        if(L<4||o+L>n)break;v=msg+o+4;vn=L-4;
        if(id==0)parse_5001_group_media(v,vn);
        else if(id==1)parse_5001_group_playback(v,vn);
        o+=L;
    }
    g_media_sequence++;
    write_media_json();
}

static void media_art_observe_bytes(const u8 *b,size_t n){
    size_t i,start=(size_t)-1,end=n;int found_end=0;
    if(!b||!n||!g_media_artwork_transfer_id)return;
    if(!g_art_capturing){
        for(i=0;i+5<n;i++){
            if(b[i]==0x15 && b[i+1]==g_media_artwork_transfer_id && b[i+2]==0x80 &&
               b[i+3]==0xff && b[i+4]==0xd8 && b[i+5]==0xff){start=i+3;break;}
        }
        if(start==(size_t)-1)return;
        unlink("/tmp/u2w_nowplaying_artwork.tmp");
        g_art_capturing=1;g_art_prev_ff=0;g_art_capture_bytes=0;
        b+=start;n-=start;
    }
    if(g_art_prev_ff && n && b[0]==0xd9){
        file_append("/tmp/u2w_nowplaying_artwork.tmp",b,1);g_art_capture_bytes++;
        rename("/tmp/u2w_nowplaying_artwork.tmp","/tmp/u2w_nowplaying_artwork.jpg");
        g_media_artwork_bytes=g_art_capture_bytes;g_media_artwork_sequence++;g_media_artwork_available=1;
        g_art_capturing=0;g_art_prev_ff=0;write_media_json();log_line("RX Now Playing artwork JPEG complete\n");
        return;
    }
    for(i=1;i<n;i++)if(b[i-1]==0xff&&b[i]==0xd9){end=i+1;found_end=1;break;}
    if(g_art_capture_bytes+(u32)end<=MEDIA_ART_MAX_BYTES){
        file_append("/tmp/u2w_nowplaying_artwork.tmp",b,end);g_art_capture_bytes+=(u32)end;
    } else {
        g_art_capturing=0;g_art_prev_ff=0;g_art_capture_bytes=0;unlink("/tmp/u2w_nowplaying_artwork.tmp");log_line("RX Now Playing artwork aborted: size limit\n");return;
    }
    if(found_end){
        rename("/tmp/u2w_nowplaying_artwork.tmp","/tmp/u2w_nowplaying_artwork.jpg");
        g_media_artwork_bytes=g_art_capture_bytes;g_media_artwork_sequence++;g_media_artwork_available=1;
        g_art_capturing=0;g_art_prev_ff=0;write_media_json();log_line("RX Now Playing artwork JPEG complete\n");
    }else g_art_prev_ff=(b[n-1]==0xff)?1:0;
}

static void parse_5201(const u8 *msg,size_t n){
    size_t o=6;char new_source[80];int source_seen=0;new_source[0]=0;
    while(o+4<=n){
        u16 L=be16(msg+o), id=be16(msg+o+2); if(L<4||o+L>n)break;
        const u8 *v=msg+o+4; size_t vn=L-4;
        if(id==0x0001 && vn>=1) g_route_state=v[0];
        else if(id==0x0003) copy_text(g_current_road,sizeof(g_current_road),v,vn);
        else if(id==0x0004) copy_text(g_destination,sizeof(g_destination),v,vn);
        else if(id==0x0005 && vn>=8) g_estimated_arrival_unix=be64_low32(v,vn);
        else if(id==0x0006 && vn>=8) g_time_remaining=be64_low32(v,vn);
        else if(id==0x0007 && vn>=4) g_distance_remaining=be32(v);
        else if(id==0x0008) copy_text(g_distance_string,sizeof(g_distance_string),v,vn);
        else if(id==0x0009 && vn>=1) g_distance_remaining_units=v[0];
        else if(id==0x000A && vn>=4) g_dist_to_maneuver=be32(v);
        else if(id==0x000B) copy_text(g_dist_to_maneuver_string,sizeof(g_dist_to_maneuver_string),v,vn);
        else if(id==0x000C && vn>=1) g_dist_to_maneuver_units=v[0];
        else if(id==0x000D){
            if(vn>=4){g_current_maneuver_index=be16(v);g_next_maneuver_index=be16(v+2);g_have_current_maneuver=1;g_have_next_maneuver=1;}
            else if(vn>=2){g_next_maneuver_index=be16(v);g_have_next_maneuver=1;g_have_current_maneuver=0;}
        }
        else if(id==0x000E && vn>=2) g_maneuver_count=be16(v);
        else if(id==0x0010 && vn>=2){g_active_lane_guidance_index=be16(v);g_have_active_lane_guidance_index=1;}
        else if(id==0x0012 && vn>=1) g_lane_guidance_showing=v[0]?1:0;
        else if(id==0x0013){copy_text(new_source,sizeof(new_source),v,vn);source_seen=1;}
        o+=L;
    }
    if(g_route_state==0){g_lane_guidance_showing=0;clear_lane_state();}
    if(source_seen){
        if(g_source_name[0]&&!text_equal(g_source_name,new_source)){clear_maneuvers();clear_lane_state();}
        copy_text(g_source_name,sizeof(g_source_name),(const u8*)new_source,strlen(new_source)+1);
    }
    g_live_sequence++;
    write_live_json();
}
static void parse_5202(const u8 *msg,size_t n){
    size_t o=6;u16 idx=0;int have_idx=0;struct rgd_maneuver_state tmp;memset(&tmp,0,sizeof(tmp));
    while(o+4<=n){
        u16 L=be16(msg+o), id=be16(msg+o+2); if(L<4||o+L>n)break;
        const u8 *v=msg+o+4; size_t vn=L-4;
        if(id==0x0001 && vn>=2){idx=be16(v);have_idx=1;tmp.index=idx;}
        else if(id==0x0002) copy_text(tmp.description,sizeof(tmp.description),v,vn);
        else if(id==0x0003 && vn>=1) tmp.type=v[0];
        else if(id==0x0004) copy_text(tmp.after_road,sizeof(tmp.after_road),v,vn);
        else if(id==0x0005 && vn>=4) tmp.distance_meters=be32(v);
        else if(id==0x0006) copy_text(tmp.display_distance,sizeof(tmp.display_distance),v,vn);
        else if(id==0x0007 && vn>=1) tmp.display_units=v[0];
        else if(id==0x0008 && vn>=1) tmp.driving_side=v[0];
        o+=L;
    }
    if(have_idx&&idx<RGD_MAX_MANEUVERS){tmp.valid=1;g_maneuvers[idx]=tmp;if(g_maneuver_count<idx+1)g_maneuver_count=idx+1;}
    g_maneuver_index=idx;g_maneuver_type=tmp.type;copy_text(g_maneuver_desc,sizeof(g_maneuver_desc),(const u8*)tmp.description,strlen(tmp.description)+1);copy_text(g_after_road,sizeof(g_after_road),(const u8*)tmp.after_road,strlen(tmp.after_road)+1);
    write_live_json();
}

static s16 be16s(const u8 *p){return (s16)be16(p);}

static void parse_5204(const u8 *msg,size_t n){
    size_t o=6;
    struct rgd_lane_state next[RGD_MAX_LANES];
    u8 next_count=0;
    u16 event_index=0;
    u8 have_event_index=0;
    memset(next,0,sizeof(next));
    while(o+4<=n){
        u16 L=be16(msg+o),id=be16(msg+o+2);
        const u8 *v;size_t vn;
        if(L<4||o+L>n)break;
        v=msg+o+4;vn=L-4;
        if(id==0x0001&&vn>=2){
            event_index=be16(v);have_event_index=1;
        }else if(id==0x0002&&next_count<RGD_MAX_LANES){
            struct rgd_lane_state lane;size_t x=0;
            memset(&lane,0,sizeof(lane));
            lane.index=next_count;
            while(x+4<=vn){
                u16 z=be16(v+x),pid=be16(v+x+2);
                const u8 *pv;size_t pvn;
                if(z<4||x+z>vn)break;
                pv=v+x+4;pvn=z-4;
                if(pid==0x0000&&pvn>=2)lane.index=be16(pv);
                else if(pid==0x0001&&pvn>=1)lane.status=pv[0];
                else if(pid>=0x0002&&pvn>=2&&lane.angle_count<RGD_MAX_LANE_ANGLES){
                    lane.angles[lane.angle_count++]=be16s(pv);
                }
                x+=z;
            }
            if(lane.angle_count>0){lane.valid=1;next[next_count++]=lane;}
        }
        o+=L;
    }
    if(next_count>0 && have_event_index){
        struct rgd_lane_event_state *ev=alloc_lane_event(event_index);
        if(ev){
            memset(ev->lanes,0,sizeof(ev->lanes));
            memcpy(ev->lanes,next,sizeof(next));
            ev->lane_count=next_count;
            ev->sequence=++g_lane_sequence;
            ev->last_use=++g_lane_cache_clock;
        }
    }
    write_live_json();
}

static void write_status(void){
    char b[3000]; int n;
    n=snprintf(b,sizeof(b),
      "U2W CarPlay Data Exporter v8.8 Route Guidance + Now Playing + Active Lane Resolution\n"
      "shim_loaded=YES\n"
      "identify_prepared=%s\n"
      "identify_patched=%s\n"
      "identify_seen=%u\n"
      "wifi_identify_seen=%u\n"
      "nonwifi_identify_seen=%u\n"
      "identify_patch_count=%u\n"
      "identify_accept_seen=%u\n"
      "5200_sent=%s\n"
      "5200_send_count=%u\n"
      "5201_received=%u\n"
      "5202_received=%u\n"
      "5204_received=%u\n"
      "unknown_52xx_received=%u\n"
      "last_5201_len=%u\n"
      "last_5202_len=%u\n"
      "last_5204_len=%u\n"
      "5001_received=%u\n"
      "last_5001_len=%u\n"
      "media_sequence=%u\n"
      "media_artwork_transfer_id=%u\n"
      "media_artwork_sequence=%u\n"
      "media_artwork_available=%u\n"
      "tx_control_buffers=%u\n"
      "rx_control_buffers=%u\n"
      "tx_write_calls=%u\n"
      "tx_send_calls=%u\n"
      "tx_sendto_calls=%u\n"
      "tx_writev_calls=%u\n"
      "tx_sendmsg_calls=%u\n"
      "tx_fwrite_calls=%u\n"
      "tx_fwrite_unlocked_calls=%u\n"
      "tx_candidate_records=%u\n"
      "tx_ident_signature_calls=%u\n"
      "tx_aa55_frames=%u\n"
      "tx_aa55_patched=%u\n"
      "rx_aa55_frames=%u\n"
      "rx_read_calls=%u\n"
      "rx_recv_calls=%u\n"
      "rx_recvfrom_calls=%u\n"
      "rx_recvmsg_calls=%u\n"
      "rx_fread_calls=%u\n"
      "rx_fread_unlocked_calls=%u\n"
      "rx_candidate_records=%u\n"
      "route_state=%u\n"
      "live_sequence=%u\n"
      "eta_unix_seconds=%u\n"
      "time_remaining_seconds=%u\n"
      "current_maneuver_index=%u\n"
      "next_maneuver_index=%u\n"
      "maneuver_count=%u\n"
      "lane_guidance_showing=%u\n"
      "lane_guidance_sequence=%u\n"
      "lane_guidance_index=%u\n"
      "lane_guidance_resolved_event=%u\n"
      "lane_guidance_lane_count=%u\n"
      "current_road=%s\n"
      "destination=%s\n"
      "distance_remaining=%u\n"
      "distance_string=%s\n"
      "distance_to_maneuver=%u\n"
      "distance_to_maneuver_string=%s\n"
      "source_name=%s\n"
      "maneuver_index=%u\n"
      "maneuver_type=%u\n"
      "maneuver_description=%s\n"
      "after_maneuver_road=%s\n",
      g_identify_prepared?"YES":"NO",g_identify_patched?"YES":"NO",g_identify_seen,g_wifi_identify_seen,g_nonwifi_identify_seen,g_identify_patch_count,g_identify_accept_seen,
      g_sent_5200?"YES":"NO",g_count_5200,g_count_5201,g_count_5202,g_count_5204,g_rx_unknown_52xx,
      g_last_5201_len,g_last_5202_len,g_last_5204_len,g_count_5001,g_last_5001_len,g_media_sequence,g_media_artwork_transfer_id,g_media_artwork_sequence,g_media_artwork_available,g_seen_tx_control,g_seen_rx_control,
      g_tx_write_calls,g_tx_send_calls,g_tx_sendto_calls,g_tx_writev_calls,g_tx_sendmsg_calls,g_tx_fwrite_calls,g_tx_fwrite_unlocked_calls,
      g_tx_candidate_records,g_tx_ident_signature_calls,g_tx_aa55_frames,g_tx_aa55_patched,g_rx_aa55_frames,
      g_rx_read_calls,g_rx_recv_calls,g_rx_recvfrom_calls,g_rx_recvmsg_calls,g_rx_fread_calls,g_rx_fread_unlocked_calls,g_rx_candidate_records,
      g_route_state,g_live_sequence,g_estimated_arrival_unix,g_time_remaining,g_current_maneuver_index,g_next_maneuver_index,g_maneuver_count,g_lane_guidance_showing,g_lane_sequence,(u32)(g_have_active_lane_guidance_index?g_active_lane_guidance_index:65535),(u32)(current_lane_event()?current_lane_event()->event_index:65535),(u32)(current_lane_event()?current_lane_event()->lane_count:0),g_current_road,g_destination,
      g_distance_remaining,g_distance_string,g_dist_to_maneuver,g_dist_to_maneuver_string,
      g_source_name,g_maneuver_index,g_maneuver_type,g_maneuver_desc,g_after_road);
    if(n>0){ int fd=open("/tmp/u2w_rgd_status.txt",O_WRONLY|O_CREAT|O_TRUNC,0644); ensure_real(); if(fd>=0&&real_write_fn){real_write_fn(fd,b,(size_t)n);close(fd);} }
}

static int contains_id(const u8 *v,size_t n,u16 id){ size_t i; for(i=0;i+1<n;i+=2) if(be16(v+i)==id)return 1; return 0; }

/* The user's Wi-Fi Identify already advertises accessory-sent 0xFFFB
 * LocationInformation.  The preceding Bluetooth Identify does not.
 * Patch only the Wi-Fi identification cycle. */
static int identify_is_wifi(const u8 *in,size_t ml){
    size_t o=6;
    while(o+4<=ml){
        u16 L=be16(in+o), pid=be16(in+o+2);
        if(L<4||o+L>ml)break;
        if(pid==6){
            const u8 *v=in+o+4; size_t vn=L-4;
            if(contains_id(v,vn,0xFFFB) && contains_id(v,vn,0x5000)) return 1;
        }
        o+=L;
    }
    return 0;
}

static size_t build_rgd_component(u8 *o,size_t cap,u16 cid){
    const char name[]="RouteGuidanceDisplayComponent";
    size_t nl=sizeof(name); /* includes NUL */
    size_t total=4 + 6 + (4+nl) + 7*6;
    size_t x=0; int id;
    if(cap<total)return 0;
    put16(o+x,(u16)total);x+=2; put16(o+x,0x001E);x+=2;
    put16(o+x,6);x+=2;put16(o+x,0);x+=2;put16(o+x,cid);x+=2;
    put16(o+x,(u16)(4+nl));x+=2;put16(o+x,1);x+=2;memcpy(o+x,name,nl);x+=nl;
    for(id=2;id<=8;id++){
        u16 val=(id==6||id==8)?6:0x0100;
        put16(o+x,6);x+=2;put16(o+x,(u16)id);x+=2;put16(o+x,val);x+=2;
    }
    return x;
}

/* Rebuild one control message, patching Identify if needed. */
static size_t patch_control_msg(const u8 *in,size_t in_n,u8 *out,size_t cap,int *did_ident){
    u16 ml,id; size_t ri,wo; int have_rg=0;
    if(in_n<6||be16(in)!=0x4040)return 0;
    ml=be16(in+2);id=be16(in+4); if(ml<6||ml>in_n)return 0;
    if(id!=0x1D01){ if(cap<ml)return 0; memcpy(out,in,ml); return ml; }
    g_identify_seen++;
    raw_record_ex("/tmp/u2w_rgd_identify.bin",0x1D01,0x0001,in,ml); /* pre-patch */
    if(!identify_is_wifi(in,ml)){
        g_nonwifi_identify_seen++;
        if(cap<ml)return 0;
        memcpy(out,in,ml);
        return ml;
    }
    g_wifi_identify_seen++;
    /* If already has 0x001E, don't duplicate. */
    ri=6; while(ri+4<=ml){u16 L=be16(in+ri),pid=be16(in+ri+2);if(L<4||ri+L>ml)break;if(pid==0x001E)have_rg=1;ri+=L;}
    wo=6; ri=6;
    if(cap<(size_t)ml+128)return 0;
    memcpy(out,in,6);
    while(ri+4<=ml){
        u16 L=be16(in+ri),pid=be16(in+ri+2); const u8 *v; size_t vn;
        if(L<4||ri+L>ml) return 0;
        v=in+ri+4;vn=L-4;
        if(pid==6){
            size_t add=(contains_id(v,vn,0x5200)?0:2)+(contains_id(v,vn,0x5203)?0:2);
            put16(out+wo,(u16)(L+add));put16(out+wo+2,pid);memcpy(out+wo+4,v,vn);wo+=L;
            if(!contains_id(v,vn,0x5200)){put16(out+wo,0x5200);wo+=2;}
            if(!contains_id(v,vn,0x5203)){put16(out+wo,0x5203);wo+=2;}
        } else if(pid==7){
            size_t add=(contains_id(v,vn,0x5201)?0:2)+(contains_id(v,vn,0x5202)?0:2)+(contains_id(v,vn,0x5204)?0:2);
            put16(out+wo,(u16)(L+add));put16(out+wo+2,pid);memcpy(out+wo+4,v,vn);wo+=L;
            if(!contains_id(v,vn,0x5201)){put16(out+wo,0x5201);wo+=2;}
            if(!contains_id(v,vn,0x5202)){put16(out+wo,0x5202);wo+=2;}
            if(!contains_id(v,vn,0x5204)){put16(out+wo,0x5204);wo+=2;}
        } else { memcpy(out+wo,in+ri,L);wo+=L; }
        ri+=L;
    }
    if(!have_rg){ size_t z=build_rgd_component(out+wo,cap-wo,0x0010); if(!z)return 0; wo+=z; }
    put16(out,0x4040);put16(out+2,(u16)wo);put16(out+4,0x1D01);
    raw_record_ex("/tmp/u2w_rgd_identify.bin",0x1D01,0x0002,out,wo); /* post-patch */
    *did_ident=1; return wo;
}

static size_t build_5200(u8 *o,size_t cap){
    if(cap<24)return 0;
    put16(o,0x4040);put16(o+2,24);put16(o+4,0x5200);
    put16(o+6,6);put16(o+8,0);put16(o+10,0x0010);
    put16(o+12,4);put16(o+14,1);
    put16(o+16,4);put16(o+18,2);
    put16(o+20,4);put16(o+22,3);
    return 24;
}

/* Transform a control-session payload. */
static size_t transform_control(const u8 *in,size_t n,u8 *out,size_t cap,int allow_inject){
    size_t ri=0,wo=0; int did_ident=0; int trigger_5000=0,trigger_loc=0;
    while(ri+6<=n && be16(in+ri)==0x4040){
        u16 L=be16(in+ri+2),mid=be16(in+ri+4);size_t z;
        if(L<6||ri+L>n)return 0;
        if(mid==0x5000)trigger_5000=1;
        if(mid==0xFFFB)trigger_loc=1;
        z=patch_control_msg(in+ri,L,out+wo,cap-wo,&did_ident);if(!z)return 0;wo+=z;ri+=L;
    }
    if(ri!=n)return 0;
    if(did_ident){g_identify_prepared=1;g_identify_patch_count++;log_line("Identify 0x1D01 prepared for RouteGuidance\n");}
    if(allow_inject && (g_identify_patched||g_identify_prepared) && !g_got_520x &&
       (trigger_5000 || trigger_loc || (g_identify_accept_seen && !g_sent_5200 && !did_ident))){
        /* Send as soon as Identify is accepted and an outgoing control write exists.
         * 0x5000 is the normal first trigger; 0xFFFB remains a bounded retry path. */
        if(!g_sent_5200 || (trigger_loc && g_count_5200<8)){ size_t z=build_5200(out+wo,cap-wo); if(z){
            raw_record_ex("/tmp/u2w_rgd_52xx.bin",0x5200,0x0100,out+wo,z);
            wo+=z;log_line("TX 0x5200 StartRouteGuidanceUpdates prepared for piggyback\n");
        } }
    }
    return wo;
}

/* Carlinkit Wi-Fi transport wrapper observed on the user's physical U2W:
 *   +0  AA55AA55
 *   +4  little-endian (inner_iAP2_len + 8)
 *   +8  little-endian 6
 *   +12 little-endian -7 (0xFFFFFFF9)
 *   +16 little-endian inner_iAP2_len
 *   +20 little-endian 16
 *   +24 FF5A... iAP2 packet
 */
static int is_aa55_frame(const u8 *b,size_t n,size_t *inner_n){
    u32 il,ol;
    if(!b||n<33||b[0]!=0xaa||b[1]!=0x55||b[2]!=0xaa||b[3]!=0x55)return 0;
    il=le32(b+16);ol=le32(b+4);
    if(le32(b+20)!=16||il<9||(size_t)il>n-24)return 0;
    if(ol!=il+8)return 0;
    if(b[24]!=0xff||b[25]!=0x5a)return 0;
    if(inner_n)*inner_n=(size_t)il; return 1;
}

static size_t transform_tx(const u8 *in,size_t n,u8 *out,size_t cap);

static size_t transform_aa55(const u8 *in,size_t n,u8 *out,size_t cap){
    size_t ri=0,wo=0;
    while(ri<n){
        size_t il,newil,frame;
        if(!is_aa55_frame(in+ri,n-ri,&il))return 0;
        frame=24+il; g_tx_aa55_frames++;
        if(wo+24>cap)return 0;
        memcpy(out+wo,in+ri,24);
        newil=transform_tx(in+ri+24,il,out+wo+24,cap-wo-24);
        if(!newil)return 0;
        putle32(out+wo+4,(u32)(newil+8));
        putle32(out+wo+16,(u32)newil);
        if(newil!=il)g_tx_aa55_patched++;
        wo+=24+newil;ri+=frame;
    }
    return wo;
}

/* Inspect a successfully-written transformed packet and persist proof. */
static void confirm_control_tx(const u8 *p,size_t n){
    size_t o=0;
    while(o+6<=n&&be16(p+o)==0x4040){
        u16 L=be16(p+o+2),mid=be16(p+o+4);
        if(L<6||o+L>n)break;
        if(mid==0x1D01 && identify_is_wifi(p+o,L)){
            size_t x=6;int hs0=0,hs3=0,hr1=0,hr2=0,hr4=0,hc=0;
            while(x+4<=L){u16 z=be16(p+o+x),pid=be16(p+o+x+2);const u8*v=p+o+x+4;size_t vn; if(z<4||x+z>L)break;vn=z-4;
                if(pid==6){hs0=contains_id(v,vn,0x5200);hs3=contains_id(v,vn,0x5203);}
                else if(pid==7){hr1=contains_id(v,vn,0x5201);hr2=contains_id(v,vn,0x5202);hr4=contains_id(v,vn,0x5204);}
                else if(pid==0x001E)hc=1; x+=z;
            }
            if(hs0&&hs3&&hr1&&hr2&&hr4&&hc){g_identify_patched=1;touch_marker("/tmp/u2w_rgd_identify_patched.marker");log_line("WIRE CONFIRMED: Wi-Fi Identify contains RouteGuidance registration\n");}
        }
        if(mid==0x5200){g_sent_5200=1;g_count_5200++;touch_marker("/tmp/u2w_rgd_5200_sent.marker");raw_record_ex("/tmp/u2w_rgd_52xx.bin",0x5200,0x0110,p+o,L);log_line("WIRE CONFIRMED: TX 0x5200 StartRouteGuidanceUpdates\n");}
        o+=L;
    }
}
static void confirm_tx_delivery(const u8 *b,size_t n){
    size_t o=0;
    if(!b||!n)return;
    if(n>=2&&be16(b)==0x4040){confirm_control_tx(b,n);write_status();return;}
    if(n>=4&&b[0]==0xaa&&b[1]==0x55&&b[2]==0xaa&&b[3]==0x55){
        while(o<n){size_t il;if(!is_aa55_frame(b+o,n-o,&il))break;confirm_tx_delivery(b+o+24,il);o+=24+il;}write_status();return;
    }
    while(o+9<=n&&be16(b+o)==0xFF5A){u16 L=be16(b+o+2);if(L<9||o+L>n)break;if(L>10&&(b[o+4]&0x40)&&b[o+7]!=0){size_t pn=L-10;const u8*p=b+o+9;if(pn>=6&&be16(p)==0x4040)confirm_control_tx(p,pn);}o+=L;}
    write_status();
}

/* Transform full iAP2 link packet(s), preserving checksum/framing. */
static size_t transform_tx(const u8 *in,size_t n,u8 *out,size_t cap){
    if(n>=4&&in[0]==0xaa&&in[1]==0x55&&in[2]==0xaa&&in[3]==0x55) return transform_aa55(in,n,out,cap);
    size_t ri=0,wo=0;
    if(n>=2 && be16(in)==0x4040){ size_t z=transform_control(in,n,out,cap,1); if(z){g_seen_tx_control++;write_status();return z;} return 0; }
    while(ri<n){
        u16 plen;u8 ctrl,sid;size_t payn,newpay;u8 *dst;const u8 *pay;
        if(ri+9>n||be16(in+ri)!=0xFF5A)return 0;
        plen=be16(in+ri+2);if(plen<9||ri+plen>n)return 0;
        ctrl=in[ri+4];sid=in[ri+7];
        if(plen<=9){if(wo+plen>cap)return 0;
        memcpy(out+wo,in+ri,plen);wo+=plen;ri+=plen;continue;}
        payn=plen-10;pay=in+ri+9;
        if((ctrl&0x40)&&sid!=0 && payn>=6 && be16(pay)==0x4040){
            u8 tmp[8192];newpay=transform_control(pay,payn,tmp,sizeof(tmp),1);
            if(newpay){
                size_t np=9+newpay+1;if(wo+np>cap||np>65535)return 0;dst=out+wo;
                memcpy(dst,in+ri,9);put16(dst+2,(u16)np);dst[8]=cksum(dst,8);memcpy(dst+9,tmp,newpay);dst[9+newpay]=cksum(dst+9,newpay);wo+=np;g_seen_tx_control++;ri+=plen;continue;
            }
        }
        if(wo+plen>cap)return 0;
        memcpy(out+wo,in+ri,plen);wo+=plen;ri+=plen;
    }
    write_status();return wo;
}

static void observe_control(const u8 *p,size_t n){
    size_t o=0;while(o+6<=n&&be16(p+o)==0x4040){u16 L=be16(p+o+2),mid=be16(p+o+4);if(L<6||o+L>n)break;
        if(mid==0x1D02){g_identify_accept_seen++;touch_marker("/tmp/u2w_rgd_identify_accept.marker");log_line("RX 0x1D02 IdentificationAccepted\n");}
        if(mid==0x5001){g_count_5001++;g_last_5001_len=L;parse_5001(p+o,L);log_line("RX 0x5001 NowPlayingUpdate\n");}
        if((mid&0xFF00)==0x5200){ raw_record_ex("/tmp/u2w_rgd_52xx.bin",mid,0x0200,p+o,L); }
        if(mid==0x5201){g_count_5201++;g_last_5201_len=L;g_got_520x=1;touch_marker("/tmp/u2w_rgd_5201.marker");parse_5201(p+o,L);log_line("RX 0x5201 RouteGuidanceUpdate\n");}
        else if(mid==0x5202){g_count_5202++;g_last_5202_len=L;g_got_520x=1;touch_marker("/tmp/u2w_rgd_5202.marker");parse_5202(p+o,L);log_line("RX 0x5202 RouteGuidanceManeuverUpdate\n");}
        else if(mid==0x5204){g_count_5204++;g_last_5204_len=L;g_got_520x=1;touch_marker("/tmp/u2w_rgd_5204.marker");parse_5204(p+o,L);log_line("RX 0x5204 LaneGuidanceInformation decoded\n");}
        else if((mid&0xFF00)==0x5200){g_rx_unknown_52xx++;g_got_520x=1;log_line("RX unknown 0x52xx message\n");}
        o+=L;
    }
}
static void observe_rx(const u8 *b,size_t n){
    size_t o=0,i=0;int any=0;
    if(!b||!n)return;
    media_art_observe_bytes(b,n);
    if(n>=4&&b[0]==0xaa&&b[1]==0x55&&b[2]==0xaa&&b[3]==0x55){
        while(o<n){size_t il;if(!is_aa55_frame(b+o,n-o,&il))break;g_rx_aa55_frames++;observe_rx(b+o+24,il);o+=24+il;}
        write_status();return;
    }
    if(n>=2&&be16(b)==0x4040){g_seen_rx_control++;observe_control(b,n);write_status();return;}

    /* v8.5: physical U2W RX buffers carry an 8-byte internal prefix before
     * FF5A (for example <frameLenLE><0x10LE>).  Scan validated FF5A packets at
     * any offset instead of requiring the iAP2 sync at byte zero. */
    while(i+10<=n){
        if(b[i]==0xff&&b[i+1]==0x5a){
            u16 L=be16(b+i+2);
            if(L>=10&&i+L<=n){
                u8 ctrl=b[i+4],sid=b[i+7];size_t pn=L-10;const u8 *p=b+i+9;
                if((ctrl&0x40)&&sid!=0&&pn>=6&&be16(p)==0x4040){
                    u16 cl=be16(p+2);if(cl>=6&&cl<=pn){g_seen_rx_control++;observe_control(p,cl);any=1;}
                }
                i+=L;continue;
            }
        }
        i++;
    }
    if(any)write_status();
}


static ssize_t tx_common(int which,int fd,const void *buf,size_t n,int flags,const void *addr,socklen_t alen){
    u8 *tmp;size_t outn;ssize_t r;size_t cap=n+1024;
    ensure_real();
    if(which==0)g_tx_write_calls++; else if(which==1)g_tx_send_calls++; else g_tx_sendto_calls++;
    if(!g_guard&&buf&&n)capture_tx_candidate((u16)(0x1000+which),(const u8*)buf,n);
    if(g_guard||!buf||n<6) goto passthru;
    tmp=(u8*)malloc(cap); if(!tmp)goto passthru;g_guard=1;outn=transform_tx((const u8*)buf,n,tmp,cap);g_guard=0;
    if(outn&&outn!=n){g_guard=1;if(which==0)r=real_write_fn(fd,tmp,outn);else if(which==1)r=real_send_fn(fd,tmp,outn,flags);else r=real_sendto_fn(fd,tmp,outn,flags,addr,alen);g_guard=0;if(r==(ssize_t)outn)confirm_tx_delivery(tmp,outn);free(tmp);if(r<0)return r;if(r==(ssize_t)outn)return (ssize_t)n;return r;}
    free(tmp);
passthru:
    if(which==0)return real_write_fn?real_write_fn(fd,buf,n):-1;
    if(which==1)return real_send_fn?real_send_fn(fd,buf,n,flags):-1;
    return real_sendto_fn?real_sendto_fn(fd,buf,n,flags,addr,alen):-1;
}

ssize_t write(int fd,const void *buf,size_t n){return tx_common(0,fd,buf,n,0,NULL,0);}
ssize_t send(int fd,const void *buf,size_t n,int flags){return tx_common(1,fd,buf,n,flags,NULL,0);}
ssize_t sendto(int fd,const void *buf,size_t n,int flags,const void *a,socklen_t al){return tx_common(2,fd,buf,n,flags,a,al);}
ssize_t read(int fd,void *buf,size_t n){ssize_t r;ensure_real();r=real_read_fn?real_read_fn(fd,buf,n):-1;if(r>0&&!g_guard){g_rx_read_calls++;capture_rx_candidate(0x2000,(u8*)buf,(size_t)r);g_guard=1;observe_rx((u8*)buf,(size_t)r);g_guard=0;}return r;}
ssize_t recv(int fd,void *buf,size_t n,int flags){ssize_t r;ensure_real();r=real_recv_fn?real_recv_fn(fd,buf,n,flags):-1;if(r>0&&!g_guard){g_rx_recv_calls++;capture_rx_candidate(0x2001,(u8*)buf,(size_t)r);g_guard=1;observe_rx((u8*)buf,(size_t)r);g_guard=0;}return r;}
ssize_t recvfrom(int fd,void *buf,size_t n,int flags,void *a,socklen_t *al){ssize_t r;ensure_real();r=real_recvfrom_fn?real_recvfrom_fn(fd,buf,n,flags,a,al):-1;if(r>0&&!g_guard){g_rx_recvfrom_calls++;capture_rx_candidate(0x2002,(u8*)buf,(size_t)r);g_guard=1;observe_rx((u8*)buf,(size_t)r);g_guard=0;}return r;}

static size_t iov_total(const struct iovec *iov,size_t iovcnt){
    size_t i,total=0; if(!iov)return 0;
    for(i=0;i<iovcnt;i++){ if(iov[i].iov_len>((size_t)-1)-total)return 0; total+=iov[i].iov_len; }
    return total;
}
static size_t iov_flatten(const struct iovec *iov,size_t iovcnt,u8 *dst,size_t want){
    size_t i,o=0;
    for(i=0;i<iovcnt && o<want;i++){
        size_t take=iov[i].iov_len; if(take>want-o)take=want-o;
        if(take){ if(!iov[i].iov_base)return 0; memcpy(dst+o,iov[i].iov_base,take); o+=take; }
    }
    return o;
}

ssize_t writev(int fd,const struct iovec *iov,int iovcnt){
    size_t n,cap,outn;u8 *flat,*tmp;ssize_t r;
    ensure_real(); if(!real_writev_fn)return -1;
    if(g_guard||iovcnt<=0||iovcnt>128)return real_writev_fn(fd,iov,iovcnt);
    n=iov_total(iov,(size_t)iovcnt); if(n<6||n>262144)return real_writev_fn(fd,iov,iovcnt);
    flat=(u8*)malloc(n); if(!flat)return real_writev_fn(fd,iov,iovcnt);
    if(iov_flatten(iov,(size_t)iovcnt,flat,n)!=n){free(flat);return real_writev_fn(fd,iov,iovcnt);}
    g_tx_writev_calls++; capture_tx_candidate(0x1003,flat,n);
    cap=n+1024;tmp=(u8*)malloc(cap);if(!tmp){free(flat);return real_writev_fn(fd,iov,iovcnt);}
    g_guard=1;outn=transform_tx(flat,n,tmp,cap);g_guard=0;
    if(outn&&outn!=n){
        struct iovec one; one.iov_base=tmp; one.iov_len=outn;
        g_guard=1;r=real_writev_fn(fd,&one,1);g_guard=0;
        if(r==(ssize_t)outn)confirm_tx_delivery(tmp,outn);
        free(tmp);free(flat);
        if(r==(ssize_t)outn)return (ssize_t)n;
        return r;
    }
    free(tmp);free(flat);return real_writev_fn(fd,iov,iovcnt);
}

ssize_t sendmsg(int fd,const struct msghdr *msg,int flags){
    size_t n,cap,outn;u8 *flat,*tmp;ssize_t r;struct iovec one;struct msghdr m;
    ensure_real(); if(!real_sendmsg_fn)return -1;
    if(g_guard||!msg||!msg->msg_iov||msg->msg_iovlen==0||msg->msg_iovlen>128)return real_sendmsg_fn(fd,msg,flags);
    n=iov_total(msg->msg_iov,msg->msg_iovlen); if(n<6||n>262144)return real_sendmsg_fn(fd,msg,flags);
    flat=(u8*)malloc(n);if(!flat)return real_sendmsg_fn(fd,msg,flags);
    if(iov_flatten(msg->msg_iov,msg->msg_iovlen,flat,n)!=n){free(flat);return real_sendmsg_fn(fd,msg,flags);}
    g_tx_sendmsg_calls++; capture_tx_candidate(0x1004,flat,n);
    cap=n+1024;tmp=(u8*)malloc(cap);if(!tmp){free(flat);return real_sendmsg_fn(fd,msg,flags);}
    g_guard=1;outn=transform_tx(flat,n,tmp,cap);g_guard=0;
    if(outn&&outn!=n){
        one.iov_base=tmp;one.iov_len=outn;m=*msg;m.msg_iov=&one;m.msg_iovlen=1;
        g_guard=1;r=real_sendmsg_fn(fd,&m,flags);g_guard=0;if(r==(ssize_t)outn)confirm_tx_delivery(tmp,outn);free(tmp);free(flat);
        if(r==(ssize_t)outn)return (ssize_t)n;
        return r;
    }
    free(tmp);free(flat);return real_sendmsg_fn(fd,msg,flags);
}

static size_t fwrite_common(int unlocked,const void *ptr,size_t size,size_t nmemb,void *stream){
    size_t n,cap,outn,w;u8 *tmp;size_t (*fn)(const void*,size_t,size_t,void*);
    ensure_real();fn=unlocked?real_fwrite_unlocked_fn:real_fwrite_fn;
    if(!fn && unlocked)fn=real_fwrite_fn;if(!fn)return 0;
    n=size*nmemb; /* runtime uses ordinary fwrite sizes; avoid pulling libgcc division helpers */
    if(unlocked)g_tx_fwrite_unlocked_calls++;else g_tx_fwrite_calls++;
    if(!g_guard&&ptr&&n)capture_tx_candidate((u16)(unlocked?0x1006:0x1005),(const u8*)ptr,n);
    if(g_guard||!ptr||n<6||n>262144)return fn(ptr,size,nmemb,stream);
    cap=n+1024;tmp=(u8*)malloc(cap);if(!tmp)return fn(ptr,size,nmemb,stream);
    g_guard=1;outn=transform_tx((const u8*)ptr,n,tmp,cap);g_guard=0;
    if(outn&&outn!=n){
        g_guard=1;w=fn(tmp,1,outn,stream);g_guard=0;if(w==outn)confirm_tx_delivery(tmp,outn);free(tmp);
        if(w==outn)return nmemb;
        return 0;
    }
    free(tmp);return fn(ptr,size,nmemb,stream);
}
size_t fwrite(const void *ptr,size_t size,size_t nmemb,void *stream){return fwrite_common(0,ptr,size,nmemb,stream);}
size_t fwrite_unlocked(const void *ptr,size_t size,size_t nmemb,void *stream){return fwrite_common(1,ptr,size,nmemb,stream);}

static size_t fread_common(int unlocked,void *ptr,size_t size,size_t nmemb,void *stream){
    size_t got,n;size_t (*fn)(void*,size_t,size_t,void*);
    ensure_real();fn=unlocked?real_fread_unlocked_fn:real_fread_fn;if(!fn&&unlocked)fn=real_fread_fn;if(!fn)return 0;
    got=fn(ptr,size,nmemb,stream); if(!got||!ptr||g_guard)return got;
    /* Bound diagnostic reads without division so ARM build does not pull libgcc helpers. */
    if(size>4096 || got>65535)return got; n=got*size; if(n>262144)return got;
    if(unlocked)g_rx_fread_unlocked_calls++;else g_rx_fread_calls++;capture_rx_candidate((u16)(unlocked?0x2005:0x2004),(u8*)ptr,n);
    g_guard=1;observe_rx((u8*)ptr,n);g_guard=0;return got;
}
size_t fread(void *ptr,size_t size,size_t nmemb,void *stream){return fread_common(0,ptr,size,nmemb,stream);}
size_t fread_unlocked(void *ptr,size_t size,size_t nmemb,void *stream){return fread_common(1,ptr,size,nmemb,stream);}

ssize_t recvmsg(int fd,struct msghdr *msg,int flags){
    ssize_t r;u8 *flat;size_t got;ensure_real();
    if(!real_recvmsg_fn)return -1;
    r=real_recvmsg_fn(fd,msg,flags);
    if(r>0&&!g_guard&&msg&&msg->msg_iov&&msg->msg_iovlen>0&&msg->msg_iovlen<=128){
        flat=(u8*)malloc((size_t)r);
        if(flat){ got=iov_flatten(msg->msg_iov,msg->msg_iovlen,flat,(size_t)r); if(got==(size_t)r){g_rx_recvmsg_calls++;capture_rx_candidate(0x2003,flat,got);g_guard=1;observe_rx(flat,got);g_guard=0;} free(flat); }
    }
    return r;
}

__attribute__((constructor)) static void init_shim(void){
    ensure_real();prctl(PR_SET_NAME,"ARMiPhoneIAP2",0,0,0);
    if(marker_exists("/tmp/u2w_rgd_identify_patched.marker")){g_identify_patched=1;g_identify_prepared=1;}
    if(marker_exists("/tmp/u2w_rgd_identify_accept.marker"))g_identify_accept_seen=1;
    if(marker_exists("/tmp/u2w_rgd_5200_sent.marker")){g_sent_5200=1;g_count_5200=1;}
    if(marker_exists("/tmp/u2w_rgd_5201.marker")){g_count_5201=1;g_got_520x=1;}
    if(marker_exists("/tmp/u2w_rgd_5202.marker")){g_count_5202=1;g_got_520x=1;}
    if(marker_exists("/tmp/u2w_rgd_5204.marker")){g_count_5204=1;g_got_520x=1;}
    log_line("U2W CarPlay data preload v8.8 (Route Guidance + Now Playing + active lane resolver) loaded\n");write_status();write_live_json();write_media_json();
}
