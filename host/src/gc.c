/* Precise mark-sweep collector with pooled size-class allocator and bulk page free (plan PERF3, MM3, D153). */
#include "gcFloor.h"
#include "value.h"
#include <errno.h>
#include <math.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define PAGE_SIZE 16384
#define PAGE_MASK ((uintptr_t)(PAGE_SIZE - 1))
#define PAGE_HEADER_SIZE 512
#define NUM_SIZE_CLASSES 63
#define MAX_SMALL_SIZE 512
#define LARGE_CLASS_IDX 255

typedef struct Page Page;
struct Page {
  Page *next;
  Page *nextFree;
  uint16_t classIdx;
  uint16_t slotSize;
  uint16_t slotCount;
  uint16_t allocCount;
  uint16_t markedCount;
  uint16_t bumpOffset;
  void *freeList;
  uint64_t inUse[16];
};

typedef struct {
  Page *pages;
  Page *freePages;
  Page *activePage;
} SizeClass;

static SizeClass sizeClasses[NUM_SIZE_CLASSES];
static Page *cachedPages;
static int cachedPageCount;

typedef struct LargeObj LargeObj;
struct LargeObj {
  LargeObj *next;
  size_t bytes;
  size_t span; /* bytes of the allocation from &o on, the range an interior pointer may hit */
  Obj o;
};

static LargeObj *largeObjects;

/* (:m :why "gcFindObj resolves an arbitrary word to a live object for conservative scanning: live pages sit in an open-addressed set keyed by their 16KB-aligned base, large objects in an address-sorted index; heapLo..heapHi only widens, as a cheap pre-filter" :ref RT-MEMORY) */
static Page **pageSet; static size_t pageSetCap, pageSetCount;
static LargeObj **largeIndex; static size_t nLarge, capLarge; static int largeSorted = 1;
static uintptr_t heapLo = UINTPTR_MAX, heapHi;
static int collecting;

/* (:m :why "new bytes between collections = max(gcMinBytes, live * gcGrowth); ASL_GC_GROWTH and ASL_GC_MIN_MIB override; ASL_GC_MAX_MIB caps live plus new bytes, past it a collection that frees too little is ERR_OOM" :ref PERF2) */
static size_t gcMinBytes = (size_t)32 << 20, gcMaxBytes;
static double gcGrowth = 2.0;
static size_t allocated, threshold = (size_t)8 << 20;
static int stress, gcStats, gcVerify;
static uint64_t statsCollections;
static uint64_t statsObjectsAllocated;
static uint64_t statsObjectsFreed;
static uint64_t statsBytesAllocated;
static uint64_t statsBytesLive;
static uint64_t statsTotalGCNs;
static uint64_t statsPagesFreed;
/* (:m :why "counts every newPage() checkout (cache or fresh OS page) regardless of RSS: a page holding stranded, never-reused free capacity forces a size class to check out more pages for the same logical workload than a correct free list would, so this is a machine-load-independent signature of the sweep bug at gc.c:420, unlike peak RSS" :ref PERF3) */
static uint64_t statsPagesAcquired;

static Val *roots[4096]; static int nroots;
static Proto **protos; static int nprotos, capprotos;
Val *gcStackBase, **gcStackTop;
void (*gcExternalRoots)(void (*mark)(Val));
static Obj **markStk; static size_t markSp, markCap;

typedef struct {
  Obj *o;
  int childIdx;
  int numChildren;
} DfsFrame;

static DfsFrame *dfsStk;
static size_t dfsSp, dfsCap;

static void gcPrintStats(void) {
  fprintf(stderr, "(:gcStats :collections %llu :objectsAllocated %llu :objectsFreed %llu :bytesAllocated %llu :bytesLive %llu :totalGCNs %llu :pagesFreed %llu :pagesAcquired %llu)\n",
          (unsigned long long)statsCollections,
          (unsigned long long)statsObjectsAllocated,
          (unsigned long long)statsObjectsFreed,
          (unsigned long long)statsBytesAllocated,
          (unsigned long long)statsBytesLive,
          (unsigned long long)statsTotalGCNs,
          (unsigned long long)statsPagesFreed,
          (unsigned long long)statsPagesAcquired);
  fflush(stderr);
}

void gcInit(void) {
  const char *s = getenv("ASL_GC_STRESS");
  stress = s && s[0] == '1';
  const char *st = getenv("ASL_GC_STATS");
  if (st && st[0] == '1') {
    gcStats = 1;
    atexit(gcPrintStats);
  }
  const char *g = getenv("ASL_GC_GROWTH");
  if (g && g[0]) {
    char *end; errno = 0;
    double d = strtod(g, &end);
    if (errno || *end || !isfinite(d) || d < 0.25 || d > 64.0) { fprintf(stderr, "ERR_ENV: ASL_GC_GROWTH must be a number in [0.25, 64], got '%s'\n", g); exit(2); }
    gcGrowth = d;
  }
  const char *m = getenv("ASL_GC_MIN_MIB");
  if (m && m[0]) {
    char *end; errno = 0;
    unsigned long long mib = strtoull(m, &end, 10);
    if (errno || *end || m[0] == '-' || mib < 1 || mib > 65536) { fprintf(stderr, "ERR_ENV: ASL_GC_MIN_MIB must be an integer in [1, 65536], got '%s'\n", m); exit(2); }
    gcMinBytes = (size_t)mib << 20;
  }
  const char *x = getenv("ASL_GC_MAX_MIB");
  if (x && x[0]) {
    char *end; errno = 0;
    unsigned long long mib = strtoull(x, &end, 10);
    if (errno || *end || x[0] == '-' || mib < 1 || mib > 65536) { fprintf(stderr, "ERR_ENV: ASL_GC_MAX_MIB must be an integer in [1, 65536], got '%s'\n", x); exit(2); }
    gcMaxBytes = (size_t)mib << 20;
  }
  threshold = gcMaxBytes && gcMaxBytes < gcMinBytes ? gcMaxBytes : gcMinBytes;
  const char *v = getenv("ASL_GC_VERIFY");
  gcVerify = v && v[0] == '1';
}

void gcRegisterProto(Proto *p) {
  if (nprotos == capprotos) { capprotos = capprotos ? capprotos * 2 : 64; protos = realloc(protos, sizeof(Proto *) * capprotos); if (!protos) exit(70); }
  protos[nprotos++] = p;
}

void asl_gc_root_push(Val *v) {
  if (nroots == (int)(sizeof roots / sizeof roots[0])) gcFloorFail("ERR_INTERNAL", "gc root stack overflow");
  roots[nroots++] = v;
}
void asl_gc_root_pop(int n) { nroots -= n; }

static int hasObj(Val v) {
  switch (v.tag) {
    case T_STR: case T_LIST: case T_REC: case T_CTOR: case T_FN: case T_BYTES: case T_F64ARR: case T_I64ARR: case T_I8ARR: case T_HANDLE: return v.u.o != NULL;
    default: return 0;
  }
}

static void markObj(Obj *o) {
  if (o->mark || o->perm) return;
  o->mark = 1;
  if (o->classIdx != LARGE_CLASS_IDX) {
    Page *p = (Page *)((uintptr_t)o & ~PAGE_MASK);
    p->markedCount++;
  }
  if (markSp == markCap) { markCap = markCap ? markCap * 2 : 1024; markStk = realloc(markStk, sizeof(Obj *) * markCap); if (!markStk) exit(70); }
  markStk[markSp++] = o;
}

static void markVal(Val v) { if (hasObj(v)) markObj(v.u.o); }

static void drain(void) {
  while (markSp) {
    Obj *o = markStk[--markSp];
    switch (o->type) {
      case O_CONS: markVal(((Cons *)o)->car); markVal(((Cons *)o)->cdr); break;
      case O_REC: { Rec *r = (Rec *)o; for (int i = 0; i < r->n; i++) markVal(r->v[i]); break; }
      case O_CTOR: { Ctor *c = (Ctor *)o; for (int i = 0; i < c->n; i++) markVal(c->f[i]); break; }
      case O_CLOSURE: { Closure *c = (Closure *)o; for (int i = 0; i < c->n; i++) markVal(c->up[i]); break; }
      default: break;
    }
  }
}

static void markRoot(Val v) { markVal(v); drain(); }

static inline int getNumChildren(Obj *o) {
  switch (o->type) {
    case O_CONS: return 2;
    case O_REC: return ((Rec *)o)->n;
    case O_CTOR: return ((Ctor *)o)->n;
    case O_CLOSURE: return ((Closure *)o)->n;
    default: return 0;
  }
}

static inline Val getObjChild(Obj *o, int idx) {
  switch (o->type) {
    case O_CONS:
      return idx == 0 ? ((Cons *)o)->car : ((Cons *)o)->cdr;
    case O_REC:
      return ((Rec *)o)->v[idx];
    case O_CTOR:
      return ((Ctor *)o)->f[idx];
    case O_CLOSURE:
      return ((Closure *)o)->up[idx];
    default:
      return VUNIT;
  }
}

static const char *gcObjTypeName(int type) {
  switch (type) {
    case O_CONS: return ":cons";
    case O_REC: return ":record";
    case O_CTOR: return ":ctor";
    case O_CLOSURE: return ":closure";
    case O_STR: return ":string";
    case O_BYTES: return ":bytes";
    case O_ARR: return ":array";
    case O_HANDLE: return ":handle";
    default: return ":unknown";
  }
}

enum { GC_WHITE = 0, GC_GREY = 1, GC_BLACK = 2 };

static void runVerifyDfs(Obj *start) {
  if (start->mark != GC_WHITE) return;

  dfsSp = 0;
  if (dfsCap < 1024) {
    dfsCap = 1024;
    dfsStk = realloc(dfsStk, sizeof(DfsFrame) * dfsCap);
    if (!dfsStk) { fprintf(stderr, "ERR_OOM\n"); exit(70); }
  }
  start->mark = GC_GREY;
  dfsStk[dfsSp++] = (DfsFrame){start, 0, getNumChildren(start)};

  while (dfsSp > 0) {
    DfsFrame *top = &dfsStk[dfsSp - 1];
    if (top->childIdx < top->numChildren) {
      Val cv = getObjChild(top->o, top->childIdx);
      top->childIdx++;
      if (!hasObj(cv)) continue;
      Obj *child = cv.u.o;
      if (!child || child->perm) continue;

      if (child->mark == GC_GREY) {
        int depth = 1;
        for (int i = (int)dfsSp - 1; i >= 0; i--) {
          if (dfsStk[i].o == child) {
            depth = (int)dfsSp - i;
            break;
          }
        }
        fprintf(stderr, "(:gcCycle :type %s :depth %d)\n", gcObjTypeName(child->type), depth);
        fflush(stderr);
        gcFloorFail("ERR_HEAP_CYCLE", "cycle of depth %d detected in %s", depth, gcObjTypeName(child->type));
      } else if (child->mark == GC_WHITE) {
        if (dfsSp == dfsCap) {
          if (dfsCap >= 1048576) {
            gcFloorFail("ERR_LIMIT", "heap verification stack depth limit exceeded");
          }
          dfsCap *= 2;
          dfsStk = realloc(dfsStk, sizeof(DfsFrame) * dfsCap);
          if (!dfsStk) { fprintf(stderr, "ERR_OOM\n"); exit(70); }
          top = &dfsStk[dfsSp - 1];
        }
        child->mark = GC_GREY;
        dfsStk[dfsSp++] = (DfsFrame){child, 0, getNumChildren(child)};
      }
    } else {
      top->o->mark = GC_BLACK;
      dfsSp--;
    }
  }
}

/* fn on every in-use pooled object, page by page; reset first zeroes each page's markedCount */
static void forEachPooled(void (*fn)(Obj *), int reset) {
  for (int sc = 0; sc < NUM_SIZE_CLASSES; sc++) {
    for (Page *p = sizeClasses[sc].pages; p; p = p->next) {
      if (reset) p->markedCount = 0;
      for (int k = 0; k < (p->slotCount + 63) / 64; k++)
        for (uint64_t w = p->inUse[k]; w; w &= w - 1)
          fn((Obj *)((char *)p + PAGE_HEADER_SIZE + ((k << 6) + __builtin_ctzll(w)) * p->slotSize));
    }
  }
}

static void clearMark(Obj *o) { o->mark = 0; }

/* every mark bit and page markedCount back to zero: after verify, and after a mark phase an error cut short */
static void clearMarks(void) {
  for (LargeObj *lo = largeObjects; lo; lo = lo->next) lo->o.mark = 0;
  forEachPooled(clearMark, 1);
}

static void gcVerifyHeap(void) {
  for (LargeObj *lo = largeObjects; lo; lo = lo->next) runVerifyDfs(&lo->o);
  forEachPooled(runVerifyDfs, 0);
  clearMarks();
}

static inline int sizeClassFor(size_t bytes) {
  if (bytes < 16) bytes = 16;
  int sc = (int)((bytes + 7) >> 3) - 2;
  if (sc >= NUM_SIZE_CLASSES) sc = NUM_SIZE_CLASSES - 1;
  return sc;
}

static inline size_t pageSlot(uintptr_t base) { return (size_t)(((base >> 14) * 0x9E3779B97F4A7C15ULL) >> 20) & (pageSetCap - 1); }

static void pageSetPut(Page *p) {
  size_t i = pageSlot((uintptr_t)p);
  while (pageSet[i]) { if (pageSet[i] == p) return; i = (i + 1) & (pageSetCap - 1); }
  pageSet[i] = p;
  pageSetCount++;
}

/* room for one more page at load <= 1/2, grown before a page is acquired so a failed grow leaks nothing */
static int failNextGrow;
void gcTestFailNextPageSetGrow(void) { failNextGrow = 1; }

static void pageSetReserve(void) {
  if ((pageSetCount + 1) * 2 <= pageSetCap) return;
  size_t oldCap = pageSetCap, cap = oldCap ? oldCap * 2 : 256;
  Page **old = pageSet, **grown = failNextGrow ? NULL : calloc(cap, sizeof(Page *));
  failNextGrow = 0;
  if (!grown) gcFloorFail("ERR_OOM", "out of memory growing the GC page set to %zu entries", cap);
  pageSet = grown; pageSetCap = cap; pageSetCount = 0;
  for (size_t i = 0; i < oldCap; i++) if (old[i]) pageSetPut(old[i]);
  free(old);
}

static Page *pageSetGet(uintptr_t base) {
  if (!pageSetCap) return NULL;
  for (size_t i = pageSlot(base); pageSet[i]; i = (i + 1) & (pageSetCap - 1))
    if ((uintptr_t)pageSet[i] == base) return pageSet[i];
  return NULL;
}

/* linear-probe delete by backward shift, so no tombstones slow later lookups */
static void pageSetDel(Page *p) {
  if (!pageSetCap) gcFloorFail("ERR_INTERNAL", "gc page set is empty on page release");
  size_t i = pageSlot((uintptr_t)p);
  while (pageSet[i] != p) {
    if (!pageSet[i]) gcFloorFail("ERR_INTERNAL", "gc page %p missing from the page set", (void *)p);
    i = (i + 1) & (pageSetCap - 1);
  }
  pageSet[i] = NULL;
  pageSetCount--;
  for (size_t j = (i + 1) & (pageSetCap - 1); pageSet[j]; j = (j + 1) & (pageSetCap - 1)) {
    size_t h = pageSlot((uintptr_t)pageSet[j]);
    if ((j > i && (h <= i || h > j)) || (j < i && h <= i && h > j)) { pageSet[i] = pageSet[j]; pageSet[j] = NULL; i = j; }
  }
}

static Page *newPage(int sc) {
  pageSetReserve();
  statsPagesAcquired++;
  Page *p = NULL;
  if (cachedPageCount > 0) {
    p = cachedPages;
    cachedPages = p->next;
    cachedPageCount--;
  } else {
    int r = posix_memalign((void **)&p, PAGE_SIZE, PAGE_SIZE);
    if (r != 0 || !p) gcFloorFail("ERR_OOM", "out of memory allocating GC page");
  }
  memset(p, 0, PAGE_HEADER_SIZE);
  p->classIdx = (uint16_t)sc;
  p->slotSize = (uint16_t)((sc + 2) * 8);
  p->slotCount = (uint16_t)((PAGE_SIZE - PAGE_HEADER_SIZE) / p->slotSize);
  p->bumpOffset = PAGE_HEADER_SIZE;
  pageSetPut(p);
  if ((uintptr_t)p < heapLo) heapLo = (uintptr_t)p;
  if ((uintptr_t)p + PAGE_SIZE > heapHi) heapHi = (uintptr_t)p + PAGE_SIZE;
  return p;
}

static void freePage(Page *p) {
  pageSetDel(p);
  statsPagesFreed++;
  if (cachedPageCount < 32) {
    p->next = cachedPages;
    cachedPages = p;
    cachedPageCount++;
  } else {
    free(p);
  }
}

static void *allocLarge(int type, size_t bytes) {
  size_t total = sizeof(LargeObj) + (bytes > sizeof(Obj) ? bytes - sizeof(Obj) : 0);
  if (nLarge == capLarge) {
    size_t cap = capLarge ? capLarge * 2 : 256;
    LargeObj **grown = realloc(largeIndex, cap * sizeof(LargeObj *));
    if (!grown) gcFloorFail("ERR_OOM", "out of memory growing the large object index to %zu entries", cap);
    largeIndex = grown; capLarge = cap;
  }
  LargeObj *lo = calloc(1, total);
  if (!lo) gcFloorFail("ERR_OOM", "out of memory allocating %zu bytes", bytes);
  lo->span = total - offsetof(LargeObj, o);
  if (nLarge && largeIndex[nLarge - 1] > lo) largeSorted = 0;
  largeIndex[nLarge++] = lo;
  if ((uintptr_t)lo < heapLo) heapLo = (uintptr_t)lo;
  if ((uintptr_t)lo + total > heapHi) heapHi = (uintptr_t)lo + total;
  lo->bytes = bytes;
  lo->o.type = (uint8_t)type;
  lo->o.classIdx = LARGE_CLASS_IDX;
  lo->o.size = (uint32_t)(bytes > 0xFFFFFFFFU ? 0xFFFFFFFFU : bytes);
  lo->next = largeObjects;
  largeObjects = lo;
  allocated += bytes;
  statsObjectsAllocated++;
  statsBytesAllocated += bytes;
  return &lo->o;
}

void asl_gc_collect(void) {
  struct timespec t0, t1;
  if (gcStats) clock_gettime(CLOCK_MONOTONIC, &t0);
  statsCollections++;
  /* (:m :why "a root hook may raise; collecting and the marks set so far must not outlive the mark phase, or the next collection skips tracing a stale-marked object and frees children stored into it since; so the error is caught here, both cleared and the error passed on" :ref GC-abortMidMark) */
  jmp_buf jb; const GcFloorGuard *guard = gcFloorGuard; void *previous = guard ? guard->handlerGet() : NULL;
  if (guard) { if (setjmp(jb)) { collecting = 0; markSp = 0; clearMarks(); guard->handlerSet(previous); guard->rethrow(); } guard->handlerSet(&jb); }
  collecting = 1;

  gcMutatorRoots(markRoot);
  if (gcExternalRoots) gcExternalRoots(markRoot);
  if (gcStackBase && gcStackTop) for (Val *p = gcStackBase; p < *gcStackTop; p++) { markVal(*p); drain(); }
  for (int i = 0; i < nroots; i++) { markVal(*roots[i]); drain(); }
  for (int i = 0; i < nprotos; i++) for (int k = 0; k < protos[i]->nconsts; k++) { markVal(protos[i]->consts[k]); drain(); }

  collecting = 0;
  if (guard) guard->handlerSet(previous);
  size_t live = 0;
  char finalizerError[GC_FLOOR_MSG_MAX] = {0};

  /* drop the unmarked large objects from the index while their marks are still readable; order is kept */
  size_t kept = 0;
  for (size_t i = 0; i < nLarge; i++) if (largeIndex[i]->o.mark) largeIndex[kept++] = largeIndex[i];
  nLarge = kept;

  LargeObj **lpp = &largeObjects;
  while (*lpp) {
    LargeObj *lo = *lpp;
    Obj *o = &lo->o;
    if (o->mark) {
      o->mark = 0;
      live += lo->bytes;
      lpp = &lo->next;
      continue;
    }
    *lpp = lo->next;
    if (o->type == O_ARR) free(((Arr *)o)->data);
    if (o->type == O_HANDLE && ((Handle *)o)->fin && !guard) ((Handle *)o)->fin(((Handle *)o)->p);
    else if (o->type == O_HANDLE && ((Handle *)o)->fin) {
      jmp_buf finJb; void *finPrevious = guard->handlerGet();
      if (setjmp(finJb) == 0) {
        guard->handlerSet(&finJb);
        ((Handle *)o)->fin(((Handle *)o)->p);
      } else if (!finalizerError[0]) {
        size_t n = guard->msgSize < sizeof finalizerError ? guard->msgSize : sizeof finalizerError;
        if (n) { memcpy(finalizerError, guard->msg, n); finalizerError[n - 1] = 0; }
      }
      guard->handlerSet(finPrevious);
    }
    free(lo);
    statsObjectsFreed++;
  }

  for (int sc = 0; sc < NUM_SIZE_CLASSES; sc++) {
    Page **pp = &sizeClasses[sc].pages;
    sizeClasses[sc].freePages = NULL;
    sizeClasses[sc].activePage = NULL;

    while (*pp) {
      Page *p = *pp;

      if (p->markedCount == 0) {
        *pp = p->next;
        statsObjectsFreed += p->allocCount;
        freePage(p);
        continue;
      }

      /* (:m :why "rebuild the free list from every slot ever carved by bump allocation below bumpOffset, not just the slots currently marked in-use: a slot freed in an earlier sweep and never reallocated has its inUse bit already clear, so scanning only set bits stranded it off the free list forever while any other object on the page stayed live" :ref PERF3) */
      p->freeList = NULL;
      int slotLimit = (int)(((size_t)p->bumpOffset - PAGE_HEADER_SIZE) / p->slotSize);
      for (int slotIdx = 0; slotIdx < slotLimit; slotIdx++) {
        int k = slotIdx >> 6, b = slotIdx & 63;
        Obj *o = (Obj *)((char *)p + PAGE_HEADER_SIZE + slotIdx * p->slotSize);
        if (p->inUse[k] & (1ULL << b)) {
          if (o->mark) {
            o->mark = 0;
            live += o->size;
          } else {
            statsObjectsFreed++;
            p->inUse[k] &= ~(1ULL << b);
            *(void **)o = p->freeList;
            p->freeList = o;
          }
        } else {
          /* already free from a previous cycle and never reallocated */
          *(void **)o = p->freeList;
          p->freeList = o;
        }
      }

      p->allocCount = p->markedCount;
      p->markedCount = 0;

      if (p->freeList != NULL) {
        p->nextFree = sizeClasses[sc].freePages;
        sizeClasses[sc].freePages = p;
      } else if (!sizeClasses[sc].activePage && (size_t)p->bumpOffset + p->slotSize <= PAGE_SIZE) {
        sizeClasses[sc].activePage = p;
      }

      pp = &p->next;
    }
  }

  allocated = 0;
  statsBytesLive = live;
  double next = (double)live * gcGrowth;
  size_t cap = (size_t)1 << 46;
  threshold = next >= (double)cap ? cap : (size_t)next;
  if (threshold < gcMinBytes) threshold = gcMinBytes;
  if (gcMaxBytes) { size_t room = live < gcMaxBytes ? gcMaxBytes - live : 0; if (threshold > room) threshold = room; }

  if (gcVerify) gcVerifyHeap();

  if (gcStats) {
    clock_gettime(CLOCK_MONOTONIC, &t1);
    statsTotalGCNs += (uint64_t)(t1.tv_sec - t0.tv_sec) * 1000000000ULL + (uint64_t)(t1.tv_nsec - t0.tv_nsec);
  }
  /* (:m :why "set only under a guard: the first finalizer error, raised once the sweep is whole") */
  if (finalizerError[0]) {
    size_t n = strlen(finalizerError) + 1;
    if (n > guard->msgSize) n = guard->msgSize;
    memcpy(guard->msg, finalizerError, n);
    guard->msg[n - 1] = 0;
    guard->rethrow();
  }
  if (gcMaxBytes && live > gcMaxBytes) gcFloorFail("ERR_OOM", "live heap exceeds ASL_GC_MAX_MIB=%zu", gcMaxBytes >> 20);
}

uint64_t gcFreedObjects(void) { return statsObjectsFreed; }

void gcAccount(Obj *o, size_t bytes) {
  /* (:m :why "a permanent object also carries classIdx LARGE_CLASS_IDX but is a bare calloc'd Obj (asl_alloc_perm), not embedded in a LargeObj; treating it as one computes a bogus LargeObj* below the allocation and writes out of bounds" :ref PERF3) */
  if (o->classIdx == LARGE_CLASS_IDX && !o->perm) {
    LargeObj *lo = (LargeObj *)((char *)o - offsetof(LargeObj, o));
    lo->bytes += bytes;
  }
  o->size += (uint32_t)bytes;
  allocated += bytes;
  statsBytesAllocated += bytes;
}

void gcWillAllocate(size_t bytes) {
  if (stress || allocated + bytes > threshold) asl_gc_collect();
}

/* one slot of class sc, slotSize bytes each; inlined with a constant class, the slot index divides by a constant */
static inline __attribute__((always_inline)) Obj *poolAlloc(int sc, size_t slotSize) {
  SizeClass *s = &sizeClasses[sc];
  Page *p = s->freePages;
  void *slot;
  if (p) {
    slot = p->freeList; p->freeList = *(void **)slot;
    if (!p->freeList) { s->freePages = p->nextFree; p->nextFree = NULL; }
  } else {
    p = s->activePage;
    if (!p || (size_t)p->bumpOffset + slotSize > PAGE_SIZE) { p = newPage(sc); p->next = s->pages; s->pages = p; s->activePage = p; }
    slot = (char *)p + p->bumpOffset; p->bumpOffset += (uint16_t)slotSize;
  }
  int slotIdx = (int)((size_t)((char *)slot - ((char *)p + PAGE_HEADER_SIZE)) / slotSize);
  p->inUse[slotIdx >> 6] |= (1ULL << (slotIdx & 63));
  p->allocCount++;
  return (Obj *)slot;
}

void *asl_alloc(int type, size_t bytes) {
  if (stress || allocated > threshold) asl_gc_collect();

  if (bytes > MAX_SMALL_SIZE || type == O_ARR || type == O_HANDLE) {
    return allocLarge(type, bytes);
  }

  int sc = sizeClassFor(bytes);
  size_t slotSize = (size_t)(sc + 2) * 8;
  Obj *o = poolAlloc(sc, slotSize);
  memset(o, 0, slotSize);
  o->type = (uint8_t)type;
  o->size = (uint32_t)bytes;
  o->classIdx = (uint8_t)sc;

  allocated += bytes;
  statsObjectsAllocated++;
  statsBytesAllocated += bytes;
  return o;
}

/* asl_alloc(O_CONS, sizeof(Cons)) for a caller that stores car and cdr before any further allocation: the class is a
   constant and the header is written whole, so no slot is cleared first */
Cons *asl_alloc_cons(void) {
  if (stress || allocated > threshold) asl_gc_collect();
  enum { SC = (sizeof(Cons) + 7) / 8 - 2 };
  _Static_assert(sizeof(Cons) <= MAX_SMALL_SIZE && SC >= 0, "a cons cell is a pooled small object");
  Obj *o = poolAlloc(SC, (SC + 2) * 8);
  *o = (Obj){.size = (uint32_t)sizeof(Cons), .type = O_CONS, .classIdx = SC};
  allocated += sizeof(Cons); statsObjectsAllocated++; statsBytesAllocated += sizeof(Cons);
  return (Cons *)o;
}

void *asl_alloc_perm(int type, size_t bytes) {
  Obj *o = calloc(1, bytes);
  if (!o) gcFloorFail("ERR_OOM", "out of memory allocating %zu bytes", bytes);
  o->type = (uint8_t)type;
  o->perm = 1;
  o->classIdx = LARGE_CLASS_IDX;
  o->size = (uint32_t)bytes;
  statsObjectsAllocated++;
  statsBytesAllocated += bytes;
  return o;
}

static int largeCmp(const void *a, const void *b) {
  uintptr_t x = (uintptr_t)*(LargeObj *const *)a, y = (uintptr_t)*(LargeObj *const *)b;
  return x < y ? -1 : x > y;
}

/* (:m :why "perm objects are bare calloc'd Objs outside every page and the large index, so they resolve to NULL: they are never swept and markObj never traces through them, so a conservative scan has nothing to keep alive" :ref RT-MEMORY) */
Obj *gcFindObj(uintptr_t w) {
  if (w < heapLo || w >= heapHi) return NULL;
  Page *p = pageSetGet(w & ~PAGE_MASK);
  if (p) {
    uintptr_t first = (uintptr_t)p + PAGE_HEADER_SIZE;
    if (w < first) return NULL;
    size_t slotIdx = (size_t)(w - first) / p->slotSize;
    if (slotIdx >= p->slotCount) return NULL;
    if (!(p->inUse[slotIdx >> 6] & (1ULL << (slotIdx & 63)))) return NULL;
    return (Obj *)(first + slotIdx * p->slotSize);
  }
  if (!nLarge) return NULL;
  if (!largeSorted) { qsort(largeIndex, nLarge, sizeof(LargeObj *), largeCmp); largeSorted = 1; }
  size_t lo = 0, hi = nLarge;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    if ((uintptr_t)largeIndex[mid] <= w) lo = mid + 1; else hi = mid;
  }
  if (!lo) return NULL;
  LargeObj *l = largeIndex[lo - 1];
  uintptr_t start = (uintptr_t)&l->o;
  return w >= start && w - start < l->span ? &l->o : NULL;
}

/* marks every live object a word in [lo, hi) points at or into; only a root hook inside asl_gc_collect may call it */
__attribute__((no_sanitize("address")))
void gcScanConservative(const void *lo, const void *hi) {
  if (!collecting) gcFloorFail("ERR_INTERNAL", "gcScanConservative outside a collection");
  if ((uintptr_t)hi < (uintptr_t)lo) gcFloorFail("ERR_INTERNAL", "gcScanConservative range %p..%p is inverted", lo, hi);
  uintptr_t a = ((uintptr_t)lo + sizeof(uintptr_t) - 1) & ~(uintptr_t)(sizeof(uintptr_t) - 1);
  for (; a + sizeof(uintptr_t) <= (uintptr_t)hi; a += sizeof(uintptr_t)) {
    Obj *o = gcFindObj(*(const uintptr_t *)a);
    if (o) { markObj(o); drain(); }
  }
}
