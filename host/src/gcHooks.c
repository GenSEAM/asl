/* GC test hooks, bound only under ASL_GC_TEST_HOOKS=1 (gcInit): probes for cycle verification, perm accounting and conservative lookup (D153, PERF3, RT-MEMORY). */
#include "value.h"
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

int nGcTestBuiltins;
extern const int gcTestBuiltinCount;

static void gcHooksInit(void) __attribute__((constructor));
static void gcHooksInit(void) {
  const char *enabled = getenv("ASL_GC_TEST_HOOKS");
  nGcTestBuiltins = enabled && enabled[0] == '1' ? gcTestBuiltinCount : 0;
}

static int heapVal(Val v) {
  switch (v.tag) {
    case T_STR: case T_LIST: case T_REC: case T_CTOR: case T_FN: case T_BYTES: case T_F64ARR: case T_I64ARR: case T_I8ARR: case T_HANDLE: return v.u.o != NULL;
    default: return 0;
  }
}

/* (:m :why "cycle on purpose; unbound unless ASL_GC_TEST_HOOKS=1" :ref D153) */
static Val bGcSeedCycle(Val *a, int n) {
  (void)n;
  Val v = a[0];
  if (v.tag == T_LIST && v.u.o) ((Cons *)v.u.o)->cdr = v;
  else if (v.tag == T_REC && v.u.o && ((Rec *)v.u.o)->n > 0) ((Rec *)v.u.o)->v[0] = v;
  else aslError("ERR_TYPE", "gcSeedCycle expects a non-empty List or a Record with a field");
  const char *verify = getenv("ASL_GC_VERIFY");
  if (verify && verify[0] == '1') asl_gc_collect();
  return v;
}

/* (:m :why "reproduces the latent gcAccount OOB write on a permanent object (asl_alloc_perm is a bare calloc'd Obj, not a LargeObj): unbound unless ASL_GC_TEST_HOOKS=1" :ref PERF3) */
static Val bGcAccountPermProbe(Val *a, int n) {
  (void)a; (void)n;
  Arr *perm = (Arr *)asl_alloc_perm(O_ARR, sizeof(Arr));
  perm->elem = 1; perm->len = 0; perm->data = NULL;
  gcAccount(&perm->h, 8);
  return vint((int64_t)perm->h.size);
}

static Val bGcObjAddr(Val *a, int n) {
  (void)n;
  if (!heapVal(a[0])) aslError("ERR_TYPE", "gcObjAddr expects a heap value");
  return vint((int64_t)(uintptr_t)a[0].u.o);
}

static Val bGcFindObjProbe(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT) aslError("ERR_TYPE", "gcFindObjProbe expects an Int address");
  return vint((int64_t)(uintptr_t)gcFindObj((uintptr_t)a[0].u.i));
}

static Val bGcPermAddr(Val *a, int n) {
  (void)a; (void)n;
  return vint((int64_t)(uintptr_t)asl_alloc_perm(O_CONS, sizeof(Cons)));
}

static const uintptr_t *probeLo, *probeHi;
static void (*probePrevRoots)(void (*mark)(Val));
static void probeRoots(void (*mark)(Val)) {
  if (probePrevRoots) probePrevRoots(mark);
  if (!probeLo) aslError("ERR_INTERNAL", "gcConservativeProbe root hook has no range");
  gcScanConservative(probeLo, probeHi);
}

/* (:m :why "keep and keepBig are held only by interior pointers in this C frame, drop and dropBig by nothing: after a collection whose one extra root is gcScanConservative over the frame, (keep keepBig drop dropBig) must read (1 1 0 0)" :ref RT-MEMORY) */
static Val bGcConservativeProbe(Val *a, int n) {
  (void)a; (void)n;
  volatile uintptr_t words[4] = {0, 0, 0, 0};
  probeLo = (const uintptr_t *)words; probeHi = probeLo + 4;
  probePrevRoots = gcExternalRoots; gcExternalRoots = probeRoots;
  Cons *keep = asl_alloc(O_CONS, sizeof(Cons));
  keep->car = vint(42); keep->cdr = VNIL;
  words[1] = (uintptr_t)&keep->cdr;
  Arr *keepBig = asl_alloc(O_ARR, sizeof(Arr));
  keepBig->elem = 8;
  words[3] = (uintptr_t)&keepBig->elem;
  uintptr_t drop = (uintptr_t)asl_alloc(O_CONS, sizeof(Cons));
  uintptr_t dropBig = (uintptr_t)asl_alloc(O_ARR, sizeof(Arr));
  asl_gc_collect();
  int64_t found[4] = {
    gcFindObj((uintptr_t)keep) == &keep->h && keep->car.tag == T_INT && keep->car.u.i == 42,
    gcFindObj((uintptr_t)keepBig) == &keepBig->h && keepBig->elem == 8,
    gcFindObj(drop) != NULL,
    gcFindObj(dropBig) != NULL,
  };
  gcExternalRoots = probePrevRoots; probePrevRoots = NULL;
  probeLo = probeHi = NULL;
  Val out = VNIL;
  asl_gc_root_push(&out);
  for (int i = 3; i >= 0; i--) out = mkCons(vint(found[i]), out);
  asl_gc_root_pop(1);
  return out;
}

/* (:m :why "the next page set grow fails as if calloc did; the rooted cells must still resolve and allocation must go on, which a pageSet nulled before the failure breaks" :ref RT-MEMORY) */
static Val cells; /* static, not a local: it must hold its last value across the longjmp */
static Val bGcPageSetOomProbe(Val *a, int n) {
  (void)a; (void)n;
  cells = VNIL;
  asl_gc_root_push(&cells);
  cells = mkCons(vint(-1), cells);
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  int raised = 0;
  gcTestFailNextPageSetGrow();
  if (setjmp(jb) == 0) {
    aslErrorHandlerSet(&jb);
    for (int i = 0; i < 4000000; i++) cells = mkCons(vint(i), cells);
    aslErrorHandlerSet(previous);
  } else {
    aslErrorHandlerSet(previous);
    raised = strncmp(aslErrorMsg, "ERR_OOM", 7) == 0;
  }
  if (!raised) aslError("ERR_INTERNAL", "gcPageSetOomProbe: no page set grow within 4000000 cells");
  int found = cells.u.o && gcFindObj((uintptr_t)cells.u.o) == cells.u.o;
  for (int i = 0; i < 100000; i++) cells = mkCons(vint(i), cells);
  found = found && gcFindObj((uintptr_t)cells.u.o) == cells.u.o;
  asl_gc_root_pop(1);
  return vbool(found);
}

static void raisingRoots(void (*mark)(Val)) { (void)mark; aslError("ERR_PROBE", "root hook raises"); }

/* (:m :why "after a collection left by an error from a root hook, gcScanConservative must refuse to run: true when it raises ERR_INTERNAL" :ref RT-MEMORY) */
static Val bGcAbortedCollectProbe(Val *a, int n) {
  (void)a; (void)n;
  void (*prev)(void (*)(Val)) = gcExternalRoots;
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  volatile int stage = 0;
  uintptr_t word = 0;
  if (setjmp(jb) == 0) {
    aslErrorHandlerSet(&jb);
    gcExternalRoots = raisingRoots;
    asl_gc_collect();
    aslErrorHandlerSet(previous); gcExternalRoots = prev;
    aslError("ERR_INTERNAL", "gcAbortedCollectProbe: the raising root hook did not raise");
  }
  gcExternalRoots = prev;
  if (strncmp(aslErrorMsg, "ERR_PROBE", 9) != 0) { aslErrorHandlerSet(previous); aslErrorRethrow(); }
  stage = 1;
  if (setjmp(jb) == 0) {
    gcScanConservative(&word, &word + 1);
    aslErrorHandlerSet(previous);
    return vbool(0);
  }
  aslErrorHandlerSet(previous);
  return vbool(stage == 1 && strncmp(aslErrorMsg, "ERR_INTERNAL", 12) == 0);
}

static Val parent; /* static: rooted, and holds its value across the longjmp */
static const uintptr_t *staleLo, *staleHi;
static void markThenRaiseRoots(void (*mark)(Val)) { (void)mark; gcScanConservative(staleLo, staleHi); aslError("ERR_PROBE", "root hook raises after marking"); }

/* a collection whose root hook marks what lo..hi points to, then raises: 1 when it raised ERR_PROBE, 0 when it did not raise, -1 for any other error (left in aslErrorMsg) */
static int collectAbortedAfterMarking(const uintptr_t *lo, const uintptr_t *hi) {
  void (*prev)(void (*)(Val)) = gcExternalRoots;
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  int raised = 0;
  staleLo = lo; staleHi = hi;
  if (setjmp(jb) == 0) {
    aslErrorHandlerSet(&jb);
    gcExternalRoots = markThenRaiseRoots;
    asl_gc_collect();
  } else {
    raised = strncmp(aslErrorMsg, "ERR_PROBE", 9) == 0 ? 1 : -1;
  }
  aslErrorHandlerSet(previous); gcExternalRoots = prev;
  staleLo = staleHi = NULL;
  return raised;
}

/* (:m :why "parent is marked, then the collection aborts; a child stored into parent afterwards must survive the next collection: true when it does" :ref GC-abortMidMark) */
static Val bGcStaleMarkProbe(Val *a, int n) {
  (void)a; (void)n;
  parent = mkCons(vint(1), VNIL);
  asl_gc_root_push(&parent);
  uintptr_t word = (uintptr_t)parent.u.o;
  int aborted = collectAbortedAfterMarking(&word, &word + 1);
  if (aborted != 1) {
    asl_gc_root_pop(1);
    if (aborted < 0) aslErrorRethrow();
    aslError("ERR_INTERNAL", "gcStaleMarkProbe: the root hook did not raise");
  }
  Val child = mkCons(vint(42), VNIL);
  ((Cons *)parent.u.o)->car = child;
  asl_gc_collect();
  Obj *found = gcFindObj((uintptr_t)child.u.o);
  int alive = found == child.u.o && ((Cons *)parent.u.o)->car.u.o == child.u.o && ((Cons *)found)->car.tag == T_INT && ((Cons *)found)->car.u.i == 42;
  asl_gc_root_pop(1);
  return vbool(alive);
}

/* (:m :why "a lone pooled object is marked, then the collection aborts; the next collection frees it and its page, so a third frees nothing; a page markedCount the abort left stale keeps the page and frees the object again in the third: true when it frees nothing" :ref GC-abortMidMark) */
static Val bGcStaleCountProbe(Val *a, int n) {
  (void)a; (void)n;
  Obj *lone = asl_alloc(O_STR, 480);
  /* 16384 is gc.c's PAGE_SIZE and 512 its PAGE_HEADER_SIZE: the first slot of a page no other object shares */
  if (((uintptr_t)lone & 16383) != 512) aslError("ERR_INTERNAL", "gcStaleCountProbe: object %p does not open a fresh page", (void *)lone);
  uintptr_t word = (uintptr_t)lone;
  int aborted = collectAbortedAfterMarking(&word, &word + 1);
  if (aborted < 0) aslErrorRethrow();
  if (!aborted) aslError("ERR_INTERNAL", "gcStaleCountProbe: the root hook did not raise");
  asl_gc_collect();
  uint64_t settled = gcFreedObjects();
  asl_gc_collect();
  return vbool(gcFindObj(word) == NULL && gcFreedObjects() == settled);
}

static int finalizerRaiseCalls, finalizerTailCalls;
static void raisingFinalizer(void *p) {
  (void)p;
  finalizerRaiseCalls++;
  aslError("ERR_PROBE", "gcFinalizerRaiseProbe finalizer raised");
}
static void tailFinalizer(void *p) { (void)p; finalizerTailCalls++; }

/* (:m :why "the raising large finalizer is first in sweep order; collection must finish later frees, clear a live mark, and report the original ERR_PROBE" :ref GC-finalizerRaise) */
static Val bGcFinalizerRaiseProbe(Val *a, int n) {
  (void)a; (void)n;
  finalizerRaiseCalls = finalizerTailCalls = 0;
  Val live = mkCons(vint(1), VNIL);
  asl_gc_root_push(&live);
  Val child = mkCons(vint(42), VNIL);
  asl_gc_root_push(&child);
  uint64_t before = gcFreedObjects();
  Handle *late = asl_alloc(O_HANDLE, sizeof(Handle));
  late->kind = "probe"; late->p = NULL; late->fin = tailFinalizer;
  Handle *raising = asl_alloc(O_HANDLE, sizeof(Handle));
  raising->kind = "probe"; raising->p = NULL; raising->fin = raisingFinalizer;
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  int reported = 0;
  if (setjmp(jb) == 0) {
    aslErrorHandlerSet(&jb);
    asl_gc_collect();
    aslErrorHandlerSet(previous);
  } else {
    reported = strncmp(aslErrorMsg, "ERR_PROBE", 9) == 0 && strstr(aslErrorMsg, "gcFinalizerRaiseProbe") != NULL;
    aslErrorHandlerSet(previous);
  }
  if (!reported) { asl_gc_root_pop(2); aslError("ERR_INTERNAL", "gcFinalizerRaiseProbe: sweep did not re-raise finalizer error"); }
  ((Cons *)live.u.o)->car = child;
  int cleared = ((Obj *)live.u.o)->mark == 0;
  int swept = finalizerRaiseCalls == 1 && finalizerTailCalls == 1 && gcFreedObjects() - before >= 2;
  uint64_t afterSweep = gcFreedObjects();
  Handle *next = asl_alloc(O_HANDLE, sizeof(Handle));
  next->kind = "probe"; next->p = NULL; next->fin = tailFinalizer;
  asl_gc_root_pop(1);
  asl_gc_collect();
  int childAlive = gcFindObj((uintptr_t)child.u.o) == child.u.o && ((Cons *)child.u.o)->car.u.i == 42;
  int nextSwept = finalizerTailCalls == 2 && gcFreedObjects() > afterSweep;
  asl_gc_root_pop(1);
  return vbool(reported && cleared && swept && childAlive && nextSwept);
}

const Builtin gcTestBuiltins[] = {
  {"gcSeedCycle", bGcSeedCycle, 1, 0},
  {"gcAccountPermProbe", bGcAccountPermProbe, 0, 0},
  {"gcObjAddr", bGcObjAddr, 1, 0},
  {"gcFindObjProbe", bGcFindObjProbe, 1, 0},
  {"gcPermAddr", bGcPermAddr, 0, 0},
  {"gcConservativeProbe", bGcConservativeProbe, 0, 0},
  {"gcPageSetOomProbe", bGcPageSetOomProbe, 0, 0},
  {"gcAbortedCollectProbe", bGcAbortedCollectProbe, 0, 0},
  {"gcStaleMarkProbe", bGcStaleMarkProbe, 0, 0},
  {"gcStaleCountProbe", bGcStaleCountProbe, 0, 0},
  {"gcFinalizerRaiseProbe", bGcFinalizerRaiseProbe, 0, 0},
};
const int gcTestBuiltinCount = (int)(sizeof gcTestBuiltins / sizeof gcTestBuiltins[0]);
