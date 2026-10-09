/* C floor error exit (FLOORRT): the collector and the native roots report fatal memory errors here, not through
   value.c's aslError, so libaslrt.a's floor objects do not pull the interpreter's error machinery. */
#ifndef ASL_GC_FLOOR_H
#define ASL_GC_FLOOR_H

#include <stddef.h>

/* asl-host's exit code for an uncaught error (aslErrorRethrow), ERR_OOM included */
enum { GC_FLOOR_EXIT = 1 };

/* bytes of a raise message the collector keeps across a sweep; asl-host's aslErrorMsg fits (vm.c asserts it) */
enum { GC_FLOOR_MSG_MAX = 4096 };

/* NULL in a native binary; asl-host's vmInit points it at aslError so its handlers catch floor errors as before.
   It is called with the code and the formatted text and must not return. */
extern void (*gcFloorRaise)(const char *code, const char *msg);

/* asl-host's raise guard: vmInit points gcFloorGuard at value.c's handler stack, rethrow and message buffer, so a
   raise inside a collection or a finalizer restores the collector's state and then propagates. NULL in a native
   binary, whose raises exit, so the collector runs unguarded and gc.o needs none of value.c. */
typedef struct {
  void *(*handlerGet)(void);
  void (*handlerSet)(void *jmpbuf);
  void (*rethrow)(void) __attribute__((noreturn)); /* re-raise msg to the current handler */
  char *msg;
  size_t msgSize;
} GcFloorGuard;
extern const GcFloorGuard *gcFloorGuard;

/* "CODE: text" to fd 2 and exit(GC_FLOOR_EXIT), or gcFloorRaise when a host set it */
_Noreturn void gcFloorFail(const char *code, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

#endif
