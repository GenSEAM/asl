#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>

#if defined(__linux__)
#include <sys/epoll.h>
#include <sys/inotify.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <dirent.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#endif

#define ASL_PLATFORM_ERR_EOF         (-1)
#define ASL_PLATFORM_ERR_TIMEOUT     (-2)
#define ASL_PLATFORM_ERR_DENIED      (-3)
#define ASL_PLATFORM_ERR_BAD_HANDLE  (-4)
#define ASL_PLATFORM_ERR_NOT_FOUND   (-5)
#define ASL_PLATFORM_ERR_BUSY        (-6)

int64_t asl_platform_linux_time_monotonic(void) {
#if defined(__linux__)
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((int64_t)ts.tv_sec * 1000000000LL) + (int64_t)ts.tv_nsec;
#else
    return 0;
#endif
}

int64_t asl_platform_linux_fs_read(int64_t handle, void* buf, int64_t count) {
#if defined(__linux__)
    if (handle < 0 || !buf || count < 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    ssize_t n = read((int)handle, buf, (size_t)count);
    if (n < 0) return ASL_PLATFORM_ERR_DENIED;
    if (n == 0 && count > 0) return ASL_PLATFORM_ERR_EOF;
    return (int64_t)n;
#else
    (void)handle; (void)buf; (void)count;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

int64_t asl_platform_linux_fs_write(int64_t handle, const void* buf, int64_t count) {
#if defined(__linux__)
    if (handle < 0 || !buf || count < 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    ssize_t n = write((int)handle, buf, (size_t)count);
    if (n < 0) return ASL_PLATFORM_ERR_DENIED;
    return (int64_t)n;
#else
    (void)handle; (void)buf; (void)count;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

int64_t asl_platform_linux_fs_stat(const char* path, struct stat* st) {
#if defined(__linux__)
    if (!path || !st) return ASL_PLATFORM_ERR_BAD_HANDLE;
    if (stat(path, st) != 0) return ASL_PLATFORM_ERR_NOT_FOUND;
    return 0;
#else
    (void)path; (void)st;
    return ASL_PLATFORM_ERR_NOT_FOUND;
#endif
}

int64_t asl_platform_linux_fs_watch(const char* path) {
#if defined(__linux__)
    if (!path) return ASL_PLATFORM_ERR_BAD_HANDLE;
    int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (fd < 0) return ASL_PLATFORM_ERR_DENIED;
    int wd = inotify_add_watch(fd, path, IN_MODIFY | IN_CREATE | IN_DELETE);
    if (wd < 0) { close(fd); return ASL_PLATFORM_ERR_NOT_FOUND; }
    return (int64_t)fd;
#else
    (void)path;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

int64_t asl_platform_linux_proc_spawn(const char* path, char* const argv[], char* const envp[]) {
#if defined(__linux__)
    if (!path || !argv) return ASL_PLATFORM_ERR_BAD_HANDLE;
    pid_t pid = fork();
    if (pid < 0) return ASL_PLATFORM_ERR_BUSY;
    if (pid == 0) {
        if (envp) execve(path, argv, envp);
        else execv(path, argv);
        _exit(127);
    }
    return (int64_t)pid;
#else
    (void)path; (void)argv; (void)envp;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

int64_t asl_platform_linux_proc_wait(int64_t pid, int64_t* exit_status) {
#if defined(__linux__)
    if (pid <= 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    int status = 0;
    pid_t res = waitpid((pid_t)pid, &status, 0);
    if (res < 0) return ASL_PLATFORM_ERR_NOT_FOUND;
    if (exit_status) {
        if (WIFEXITED(status)) *exit_status = WEXITSTATUS(status);
        else if (WIFSIGNALED(status)) *exit_status = 128 + WTERMSIG(status);
        else *exit_status = -1;
    }
    return 0;
#else
    (void)pid; (void)exit_status;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

int64_t asl_platform_linux_proc_signal(int64_t pid, int32_t sig) {
#if defined(__linux__)
    if (pid <= 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    if (kill((pid_t)pid, sig) != 0) return ASL_PLATFORM_ERR_DENIED;
    return 0;
#else
    (void)pid; (void)sig;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

int64_t asl_platform_linux_net_socket(const char* host, int32_t port) {
#if defined(__linux__)
    if (!host || port <= 0 || port > 65535) return ASL_PLATFORM_ERR_BAD_HANDLE;
    int s = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (s < 0) return ASL_PLATFORM_ERR_DENIED;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) <= 0) {
        close(s);
        return ASL_PLATFORM_ERR_NOT_FOUND;
    }
    if (connect(s, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        close(s);
        return ASL_PLATFORM_ERR_DENIED;
    }
    return (int64_t)s;
#else
    (void)host; (void)port;
    return ASL_PLATFORM_ERR_DENIED;
#endif
}

void* asl_platform_linux_mem_alloc_page(int64_t page_count) {
#if defined(__linux__)
    if (page_count <= 0) return NULL;
    size_t size = (size_t)page_count * 4096;
    void* p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    if (p == MAP_FAILED) return NULL;
    return p;
#else
    if (page_count <= 0) return NULL;
    return malloc((size_t)page_count * 4096);
#endif
}

int64_t asl_platform_linux_mem_free_page(void* ptr, int64_t page_count) {
#if defined(__linux__)
    if (!ptr || page_count <= 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    size_t size = (size_t)page_count * 4096;
    if (munmap(ptr, size) != 0) return ASL_PLATFORM_ERR_DENIED;
    return 0;
#else
    if (!ptr || page_count <= 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    free(ptr);
    return 0;
#endif
}
