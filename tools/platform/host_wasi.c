#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#define ASL_PLATFORM_ERR_EOF         (-1)
#define ASL_PLATFORM_ERR_TIMEOUT     (-2)
#define ASL_PLATFORM_ERR_DENIED      (-3)
#define ASL_PLATFORM_ERR_BAD_HANDLE  (-4)
#define ASL_PLATFORM_ERR_NOT_FOUND   (-5)
#define ASL_PLATFORM_ERR_BUSY        (-6)

#if defined(__wasi__)
#include <wasi/api.h>

int64_t asl_platform_wasi_time_monotonic(void) {
    __wasi_timestamp_t ts = 0;
    __wasi_errno_t err = __wasi_clock_time_get(__WASI_CLOCKID_MONOTONIC, 1, &ts);
    if (err != __WASI_ERRNO_SUCCESS) return 0;
    return (int64_t)ts;
}

int64_t asl_platform_wasi_fs_read(int64_t fd, void* buf, int64_t count) {
    if (fd < 0 || !buf || count < 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    __wasi_iovec_t iov = { .buf = buf, .buf_len = (size_t)count };
    size_t nread = 0;
    __wasi_errno_t err = __wasi_fd_read((__wasi_fd_t)fd, &iov, 1, &nread);
    if (err != __WASI_ERRNO_SUCCESS) return ASL_PLATFORM_ERR_DENIED;
    if (nread == 0 && count > 0) return ASL_PLATFORM_ERR_EOF;
    return (int64_t)nread;
}

int64_t asl_platform_wasi_fs_write(int64_t fd, const void* buf, int64_t count) {
    if (fd < 0 || !buf || count < 0) return ASL_PLATFORM_ERR_BAD_HANDLE;
    __wasi_ciovec_t ciov = { .buf = buf, .buf_len = (size_t)count };
    size_t nwritten = 0;
    __wasi_errno_t err = __wasi_fd_write((__wasi_fd_t)fd, &ciov, 1, &nwritten);
    if (err != __WASI_ERRNO_SUCCESS) return ASL_PLATFORM_ERR_DENIED;
    return (int64_t)nwritten;
}

int64_t asl_platform_wasi_proc_spawn(const char* path, char* const argv[], char* const envp[]) {
    (void)path; (void)argv; (void)envp;
    return ASL_PLATFORM_ERR_DENIED;
}

void* asl_platform_wasi_mem_alloc_page(int64_t page_count) {
    if (page_count <= 0) return NULL;
    return malloc((size_t)page_count * 65536);
}

int64_t asl_platform_wasi_mem_free_page(void* ptr, int64_t page_count) {
    (void)page_count;
    if (!ptr) return ASL_PLATFORM_ERR_BAD_HANDLE;
    free(ptr);
    return 0;
}
#else
int64_t asl_platform_wasi_time_monotonic(void) {
    return 0;
}
int64_t asl_platform_wasi_fs_read(int64_t fd, void* buf, int64_t count) {
    (void)fd; (void)buf; (void)count;
    return ASL_PLATFORM_ERR_DENIED;
}
int64_t asl_platform_wasi_fs_write(int64_t fd, const void* buf, int64_t count) {
    (void)fd; (void)buf; (void)count;
    return ASL_PLATFORM_ERR_DENIED;
}
int64_t asl_platform_wasi_proc_spawn(const char* path, char* const argv[], char* const envp[]) {
    (void)path; (void)argv; (void)envp;
    return ASL_PLATFORM_ERR_DENIED;
}
void* asl_platform_wasi_mem_alloc_page(int64_t page_count) {
    if (page_count <= 0) return NULL;
    return malloc((size_t)page_count * 65536);
}
int64_t asl_platform_wasi_mem_free_page(void* ptr, int64_t page_count) {
    (void)page_count;
    if (!ptr) return ASL_PLATFORM_ERR_BAD_HANDLE;
    free(ptr);
    return 0;
}
#endif
