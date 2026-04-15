/*
 * nimo.c — dyld interposition library for Discord UDP primer injection.
 * On the first 74-byte sendto() per socket, sends two 1-byte primer packets
 * (0x00, 0x01) to the same destination, waits 50ms, then forwards the call.
 */

#include <sys/socket.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdint.h>
#include <mach-o/dyld-interposing.h>

#define HANDSHAKE_SIZE 74
#define PRIMER_DELAY_US 50000
#define MAX_SOCKETS 65536

static bool socket_first_send[MAX_SOCKETS];
static pthread_mutex_t socket_mutex = PTHREAD_MUTEX_INITIALIZER;

static ssize_t (*real_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t) = sendto;
static int (*real_close)(int) = close;

static bool is_first_send_and_mark(int sockfd) {
    if (sockfd < 0 || sockfd >= MAX_SOCKETS) {
        return false;
    }
    bool first;
    pthread_mutex_lock(&socket_mutex);
    first = !socket_first_send[sockfd];
    if (first) {
        socket_first_send[sockfd] = true;
    }
    pthread_mutex_unlock(&socket_mutex);
    return first;
}

ssize_t nimo_sendto(int sockfd, const void *buf, size_t len, int flags,
                    const struct sockaddr *dest_addr, socklen_t addrlen) {
    if (len == HANDSHAKE_SIZE && is_first_send_and_mark(sockfd)) {
        const uint8_t primer0 = 0x00;
        const uint8_t primer1 = 0x01;
        (void)real_sendto(sockfd, &primer0, 1, flags, dest_addr, addrlen);
        (void)real_sendto(sockfd, &primer1, 1, flags, dest_addr, addrlen);
        usleep(PRIMER_DELAY_US);
    }
    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

int nimo_close(int fd) {
    if (fd >= 0 && fd < MAX_SOCKETS) {
        pthread_mutex_lock(&socket_mutex);
        socket_first_send[fd] = false;
        pthread_mutex_unlock(&socket_mutex);
    }
    if (real_close) {
        return real_close(fd);
    }
    return 0;
}

#ifndef NIMO_TEST
DYLD_INTERPOSE(nimo_sendto, sendto);
DYLD_INTERPOSE(nimo_close, close);
#endif
