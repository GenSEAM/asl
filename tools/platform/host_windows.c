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
#define ASL_PLATFORM_ERR_OVERFLOW    (-7)

#define ASL_IOCP_RING_CAPACITY 1024

typedef struct {
    uint64_t handle;
    uint32_t bytes;
    uint32_t status;
    uint32_t flags;
} AslIocpEvent;

typedef struct {
    AslIocpEvent events[ASL_IOCP_RING_CAPACITY];
    size_t head;
    size_t tail;
    size_t count;
    uint64_t overflow_count;
} AslIocpRing;

void asl_platform_windows_iocp_ring_init(AslIocpRing* ring) {
    if (!ring) return;
    ring->head = 0;
    ring->tail = 0;
    ring->count = 0;
    ring->overflow_count = 0;
}

int64_t asl_platform_windows_iocp_ring_push(AslIocpRing* ring, uint64_t handle, uint32_t bytes, uint32_t status, uint32_t flags) {
    if (!ring) return ASL_PLATFORM_ERR_BAD_HANDLE;
    if (ring->count >= ASL_IOCP_RING_CAPACITY) {
        ring->overflow_count++;
        return ASL_PLATFORM_ERR_OVERFLOW;
    }
    ring->events[ring->tail].handle = handle;
    ring->events[ring->tail].bytes = bytes;
    ring->events[ring->tail].status = status;
    ring->events[ring->tail].flags = flags;
    ring->tail = (ring->tail + 1) % ASL_IOCP_RING_CAPACITY;
    ring->count++;
    return 0;
}

int64_t asl_platform_windows_iocp_ring_pop(AslIocpRing* ring, AslIocpEvent* out_event) {
    if (!ring) return ASL_PLATFORM_ERR_BAD_HANDLE;
    if (ring->count == 0) return ASL_PLATFORM_ERR_EOF;
    if (out_event) {
        *out_event = ring->events[ring->head];
    }
    ring->head = (ring->head + 1) % ASL_IOCP_RING_CAPACITY;
    ring->count--;
    return 0;
}

int64_t asl_platform_windows_qpc_to_nanoseconds(int64_t qpc, int64_t freq) {
    if (freq <= 0 || qpc <= 0) return 0;
    int64_t quotient = qpc / freq;
    int64_t remainder = qpc % freq;
    return (quotient * 1000000000LL) + ((remainder * 1000000000LL) / freq);
}

int64_t asl_platform_windows_normalize_path(const char* win_path, char* out_buf, size_t out_cap) {
    if (!win_path || !out_buf || out_cap < 2) return ASL_PLATFORM_ERR_BAD_HANDLE;
    size_t in_len = strlen(win_path);
    size_t out_idx = 0;
    size_t in_idx = 0;

    if (in_len >= 2 && win_path[1] == ':') {
        char drive = win_path[0];
        if (drive >= 'A' && drive <= 'Z') drive = (char)(drive + ('a' - 'A'));
        if (out_idx + 3 >= out_cap) return ASL_PLATFORM_ERR_BUSY;
        out_buf[out_idx++] = '/';
        out_buf[out_idx++] = drive;
        in_idx = 2;
        if (in_idx < in_len && (win_path[in_idx] == '\\' || win_path[in_idx] == '/')) {
            in_idx++;
        }
    }

    bool last_was_slash = (out_idx > 0 && out_buf[out_idx - 1] == '/');
    while (in_idx < in_len && out_idx + 1 < out_cap) {
        char c = win_path[in_idx++];
        if (c == '\\' || c == '/') {
            if (!last_was_slash) {
                out_buf[out_idx++] = '/';
                last_was_slash = true;
            }
        } else {
            out_buf[out_idx++] = c;
            last_was_slash = false;
        }
    }

    if (out_idx == 0 && out_idx + 1 < out_cap) {
        out_buf[out_idx++] = '/';
    }
    out_buf[out_idx] = '\0';
    return (int64_t)out_idx;
}

#if defined(_WIN32) || defined(_WIN64)
#include <windows.h>

int64_t asl_platform_windows_time_monotonic(void) {
    LARGE_INTEGER qpc, freq;
    if (!QueryPerformanceFrequency(&freq) || !QueryPerformanceCounter(&qpc)) return 0;
    return asl_platform_windows_qpc_to_nanoseconds(qpc.QuadPart, freq.QuadPart);
}

int64_t asl_platform_windows_cancel_io_and_close(HANDLE h) {
    if (h == NULL || h == INVALID_HANDLE_VALUE) return ASL_PLATFORM_ERR_BAD_HANDLE;
    CancelIoEx(h, NULL);
    CloseHandle(h);
    return 0;
}

void* asl_platform_windows_mem_alloc_page(int64_t page_count) {
    if (page_count <= 0) return NULL;
    return VirtualAlloc(NULL, (size_t)page_count * 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
}

int64_t asl_platform_windows_mem_free_page(void* ptr, int64_t page_count) {
    (void)page_count;
    if (!ptr) return ASL_PLATFORM_ERR_BAD_HANDLE;
    if (!VirtualFree(ptr, 0, MEM_RELEASE)) return ASL_PLATFORM_ERR_DENIED;
    return 0;
}
#else
int64_t asl_platform_windows_time_monotonic(void) {
    return 0;
}
int64_t asl_platform_windows_cancel_io_and_close(void* h) {
    (void)h;
    return 0;
}
void* asl_platform_windows_mem_alloc_page(int64_t page_count) {
    if (page_count <= 0) return NULL;
    return malloc((size_t)page_count * 4096);
}
int64_t asl_platform_windows_mem_free_page(void* ptr, int64_t page_count) {
    (void)page_count;
    if (!ptr) return ASL_PLATFORM_ERR_BAD_HANDLE;
    free(ptr);
    return 0;
}
#endif
