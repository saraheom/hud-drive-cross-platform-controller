/*
 * U2W v8.35 bounded native CarPlay keyframe request helper.
 * Freestanding ARM EABI/Linux binary: no libc and no process control.
 *
 * Sends exactly one binary-verified Carlinkit request header:
 *   magic=0x55AA55AA, payload length=0, type=0x0C RequestKeyFrame,
 *   check=~0x0C.
 * Primary local endpoint is /var/run/adb-driver; /var/run/phonemirror is a
 * single bounded fallback. There is no retry loop, registration spoofing,
 * AppleCarPlay signal/restart, ARMiPhoneIAP2 signal/restart, or TCP reconnect.
 */
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned long usize;

#define SYS_exit   1
#define SYS_close  6
#define SYS_socket 281
#define SYS_sendto 290
#define AF_UNIX 1
#define SOCK_DGRAM 2

struct sockaddr_un_local {
    u16 sun_family;
    char sun_path[108];
};

static inline long sc1(long n, long a0) {
    register long r0 __asm__("r0") = a0;
    register long r7 __asm__("r7") = n;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r7) : "memory");
    return r0;
}
static inline long sc3(long n, long a0, long a1, long a2) {
    register long r0 __asm__("r0") = a0;
    register long r1 __asm__("r1") = a1;
    register long r2 __asm__("r2") = a2;
    register long r7 __asm__("r7") = n;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r7) : "memory");
    return r0;
}
static inline long sc6(long n, long a0, long a1, long a2, long a3, long a4, long a5) {
    register long r0 __asm__("r0") = a0;
    register long r1 __asm__("r1") = a1;
    register long r2 __asm__("r2") = a2;
    register long r3 __asm__("r3") = a3;
    register long r4 __asm__("r4") = a4;
    register long r5 __asm__("r5") = a5;
    register long r7 __asm__("r7") = n;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r7) : "memory");
    return r0;
}

static int copy_path(struct sockaddr_un_local *addr, const char *path) {
    int i = 0;
    addr->sun_family = AF_UNIX;
    while (i < 107 && path[i]) { addr->sun_path[i] = path[i]; i++; }
    addr->sun_path[i] = 0;
    return 2 + i + 1;
}

static long send_one(long fd, const char *path) {
    static const unsigned char request[16] = {
        0xAA,0x55,0xAA,0x55, 0x00,0x00,0x00,0x00,
        0x0C,0x00,0x00,0x00, 0xF3,0xFF,0xFF,0xFF
    };
    struct sockaddr_un_local addr;
    addr.sun_family = 0;
    for (int i = 0; i < 108; i++) addr.sun_path[i] = 0;
    int len = copy_path(&addr, path);
    return sc6(SYS_sendto, fd, (long)request, 16, 0, (long)&addr, len);
}

void _start(void) {
    long fd = sc3(SYS_socket, AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0) sc1(SYS_exit, 20);
    long r = send_one(fd, "/var/run/adb-driver");
    if (r == 16) { sc1(SYS_close, fd); sc1(SYS_exit, 0); }
    r = send_one(fd, "/var/run/phonemirror");
    sc1(SYS_close, fd);
    if (r == 16) sc1(SYS_exit, 10);
    sc1(SYS_exit, 20);
    for (;;) { }
}
