#include "../nimo.c"

#include <stdio.h>
#include <string.h>

static int failures = 0;
static int checks = 0;

#define ASSERT(cond, msg) do { \
    checks++; \
    if (!(cond)) { \
        failures++; \
        printf("FAIL: %s (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } else { \
        printf("PASS: %s\n", (msg)); \
    } \
} while (0)

static void reset_state(void) {
    pthread_mutex_lock(&socket_mutex);
    memset(socket_first_send, 0, sizeof(socket_first_send));
    pthread_mutex_unlock(&socket_mutex);
}

static void test_first_send_returns_true_then_false(void) {
    reset_state();
    ASSERT(is_first_send_and_mark(5) == true, "first call for fd 5 returns true");
    ASSERT(is_first_send_and_mark(5) == false, "second call for fd 5 returns false");
}

static void test_out_of_range_fd_returns_false(void) {
    reset_state();
    ASSERT(is_first_send_and_mark(-1) == false, "fd -1 returns false");
    ASSERT(is_first_send_and_mark(70000) == false, "fd 70000 returns false");
    ASSERT(is_first_send_and_mark(MAX_SOCKETS) == false, "fd MAX_SOCKETS returns false");
}

static void test_close_resets_tracking(void) {
    reset_state();
    int fd = 10;
    void *saved_close = (void *)real_close;
    real_close = NULL;

    ASSERT(is_first_send_and_mark(fd) == true, "first-send true before close");
    ASSERT(is_first_send_and_mark(fd) == false, "second-send false before close");
    (void)nimo_close(fd);
    ASSERT(is_first_send_and_mark(fd) == true, "first-send true again after close");

    real_close = (int (*)(int))saved_close;
}

static void test_different_fds_independent(void) {
    reset_state();
    ASSERT(is_first_send_and_mark(5) == true, "fd 5 first-send true");
    ASSERT(is_first_send_and_mark(6) == true, "fd 6 first-send true independently");
    ASSERT(is_first_send_and_mark(5) == false, "fd 5 second-send false");
    ASSERT(is_first_send_and_mark(6) == false, "fd 6 second-send false");
}

int main(void) {
    test_first_send_returns_true_then_false();
    test_out_of_range_fd_returns_false();
    test_close_resets_tracking();
    test_different_fds_independent();

    printf("\n%d/%d checks passed\n", checks - failures, checks);
    return failures == 0 ? 0 : 1;
}
