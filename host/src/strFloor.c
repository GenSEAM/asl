/* C floor (FLOORRT, PRELUDEASL-Z): the string primitives stringLength, stringSlice and stringConcat, which allocate their
   results with asl_alloc, and the floor error exit. The primitives fail through gcFloorFail, which asl-host's vmInit
   points at aslError, so asl-host reports prelude.c's ERR_TYPE texts unchanged and strFloor.o needs none of value.c's
   error machinery. mkStr and mkStrPerm live in prelude.c (ABIVAL-5): native code builds Strings in IR
   (asl-target-llvm/rtValue), so no libaslrt.a member defines them; KW_SOME, KW_NONE, mkCtor and tagName come from
   value.c in asl-host and from the program's IR in a native binary. */
#include "gcFloor.h"
#include "value.h"
#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

Val bStringLength(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_STR) gcFloorFail("ERR_TYPE", "%s expects %s, got %s", "stringLength", tagName(T_STR), tagName(a[0].tag));
  return vint((int64_t)((Str *)a[0].u.o)->len);
}

Val bStringConcat(Val *a, int n) {
  (void)n;
  for (int i = 0; i < 2; i++)
    if (a[i].tag != T_STR) gcFloorFail("ERR_TYPE", "%s expects %s, got %s", "stringConcat", tagName(T_STR), tagName(a[i].tag));
  size_t len = ((Str *)a[0].u.o)->len + ((Str *)a[1].u.o)->len;
  asl_gc_root_push(&a[0]); asl_gc_root_push(&a[1]);
  Str *o = asl_alloc(O_STR, sizeof(Str) + len + 1);
  asl_gc_root_pop(2);
  Str *x = (Str *)a[0].u.o, *y = (Str *)a[1].u.o;
  o->len = len; memcpy(o->s, x->s, x->len); memcpy(o->s + x->len, y->s, y->len); o->s[len] = 0;
  return vobj(T_STR, o);
}

Val bStringSlice(Val *a, int n) {
  (void)n;
  for (int i = 0; i < 3; i++) {
    Tag want = i ? T_INT : T_STR;
    if (a[i].tag != want) gcFloorFail("ERR_TYPE", "%s expects %s, got %s", "stringSlice", tagName(want), tagName(a[i].tag));
  }
  int64_t s = a[1].u.i, e = a[2].u.i;
  if (s < 0 || e < s || (size_t)e > ((Str *)a[0].u.o)->len) return mkCtor(KW_NONE, 0);
  size_t slen = (size_t)(e - s);
  asl_gc_root_push(&a[0]);
  Str *o = asl_alloc(O_STR, sizeof(Str) + slen + 1);
  asl_gc_root_pop(1);
  o->len = slen; memcpy(o->s, ((Str *)a[0].u.o)->s + s, slen); o->s[slen] = 0;
  Val v = vobj(T_STR, o);
  asl_gc_root_push(&v);
  Val r = mkCtor(KW_SOME, 1);
  asl_gc_root_pop(1);
  ((Ctor *)r.u.o)->f[0] = v;
  return r;
}

void (*gcFloorRaise)(const char *code, const char *msg);
const GcFloorGuard *gcFloorGuard;

static void floorWriteAll(const char *p, size_t n) {
  while (n > 0) {
    ssize_t w = write(2, p, n);
    if (w < 0 && errno == EINTR) continue;
    if (w <= 0) return; /* stderr is gone: the exit code still reports the failure */
    p += w; n -= (size_t)w;
  }
}

_Noreturn void gcFloorFail(const char *code, const char *fmt, ...) {
  char msg[1024];
  va_list ap; va_start(ap, fmt);
  int k = vsnprintf(msg, sizeof msg, fmt, ap);
  va_end(ap);
  if (k < 0) msg[0] = 0;
  if (gcFloorRaise) gcFloorRaise(code, msg);
  char line[sizeof msg + 128];
  int n = snprintf(line, sizeof line, "%s: %s\n", code, msg);
  if (n < 0) n = 0;
  if ((size_t)n >= sizeof line) { n = (int)sizeof line - 1; line[n - 1] = '\n'; }
  floorWriteAll(line, (size_t)n);
  exit(GC_FLOOR_EXIT);
}
