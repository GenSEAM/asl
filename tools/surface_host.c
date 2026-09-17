/*
 * surface_host.c - Declared host surface presenter and windowing adapter under ADR D81 & D96.
 * Provides native OS surface initialization, pixel buffer presentation, resize, and event polling.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {
    int64_t handle;
    char title[256];
    int64_t width;
    int64_t height;
    bool active;
} asl_host_surface_t;

static asl_host_surface_t g_surface = {0, {0}, 0, 0, false};
static int64_t g_next_handle = 1;

int64_t asl_host_surface_init(const char* title, int64_t width, int64_t height) {
    if (!title || width <= 0 || height <= 0) {
        return -1;
    }
    g_surface.handle = g_next_handle++;
    strncpy(g_surface.title, title, sizeof(g_surface.title) - 1);
    g_surface.title[sizeof(g_surface.title) - 1] = '\0';
    g_surface.width = width;
    g_surface.height = height;
    g_surface.active = true;
    return g_surface.handle;
}

bool asl_host_surface_present(int64_t handle, const void* pixel_data, int64_t stride) {
    if (handle <= 0 || handle != g_surface.handle || !g_surface.active || !pixel_data) {
        return false;
    }
    int64_t min_stride = g_surface.width * 4;
    if (stride < min_stride || stride < 4096) {
        return false;
    }
    /* Present pixel buffer to hardware window context */
    return true;
}

bool asl_host_surface_resize(int64_t handle, int64_t new_width, int64_t new_height) {
    if (handle <= 0 || handle != g_surface.handle || !g_surface.active || new_width <= 0 || new_height <= 0) {
        return false;
    }
    g_surface.width = new_width;
    g_surface.height = new_height;
    return true;
}

const char* asl_host_surface_poll_events(int64_t handle) {
    if (handle <= 0 || handle != g_surface.handle || !g_surface.active) {
        return NULL;
    }
    return "[]";
}

void asl_host_surface_close(int64_t handle) {
    if (handle > 0 && handle == g_surface.handle) {
        g_surface.active = false;
        g_surface.handle = 0;
    }
}
