/* Stage-0 ASL host: shared value model, GC, compiler and VM interfaces (plan R1 H2 H3 H4). */
#ifndef ASL_VALUE_H
#define ASL_VALUE_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

typedef enum {
  T_UNIT, T_BOOL, T_INT, T_FLOAT, T_KW, T_STR, T_LIST, T_REC, T_CTOR, T_FN, T_BUILTIN, T_BYTES,
  T_F64ARR, T_I64ARR, T_I8ARR, T_HANDLE
} Tag;

typedef struct Obj Obj;
typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; double f; Obj *o; } u; } Val;

enum { O_STR, O_CONS, O_REC, O_CTOR, O_CLOSURE, O_BYTES, O_ARR, O_HANDLE };
struct Obj { uint32_t size; uint8_t type; uint8_t mark; uint8_t perm; uint8_t classIdx; };
typedef struct { Obj h; size_t len; char s[]; } Str;
typedef struct { Obj h; Val car, cdr; } Cons;
typedef struct { Obj h; int schema; int n; int *keys; Val v[]; } Rec;
typedef struct { Obj h; int ctor; int n; Val f[]; } Ctor;
typedef struct Proto Proto;
typedef struct { Obj h; Proto *p; int n; Val up[]; } Closure;
typedef struct { Obj h; size_t len; size_t elem; unsigned char *data; } Arr; enum { MAX_ARRAY_ELEMENTS = 16777216 };
/* native resource with a finalizer run when the collector frees it */
typedef struct { Obj h; const char *kind; void *p; void (*fin)(void *); } Handle;

typedef Val (*BuiltinFn)(Val *args, int argc);
typedef struct { const char *name; BuiltinFn fn; int arity; /* -1 variadic */ int effect; /* 1: touches the world, so a caller needs ! (LS1) */ } Builtin;

struct Proto {
  const char *name; const char *file;
  int nparams, maxstack;
  uint32_t *code; int ncode, capcode;
  Val *consts; int nconsts, capconsts;
  void *native; /* entry of LLVM-compiled code, called by abi.c in a native binary; NULL for bytecode */
};

/* constructors */
#define VUNIT ((Val){T_UNIT, 0, {.i = 0}})
#define VNIL ((Val){T_LIST, 0, {.o = NULL}})
static inline Val vbool(int b) { Val v = {T_BOOL, 0, {.i = b ? 1 : 0}}; return v; }
static inline Val vint(int64_t i) { Val v = {T_INT, 0, {.i = i}}; return v; }
static inline Val vfloat(double f) { Val v = {T_FLOAT, 0, {.f = f}}; return v; }
static inline Val vobj(Tag t, void *o) { Val v = {t, 0, {.o = (Obj *)o}}; return v; }
static inline Val vkw(int id) { Val v = {T_KW, (uint32_t)id, {.i = 0}}; return v; }

/* interning */
int intern(const char *s, size_t n);
const char *symName(int id);

/* gc.c */
void *asl_alloc(int type, size_t bytes);
Cons *asl_alloc_cons(void); /* fields uninitialised: the caller sets car and cdr before allocating again */
void *asl_alloc_perm(int type, size_t bytes);
void asl_gc_root_push(Val *v);
void asl_gc_root_pop(int n);
void asl_gc_collect(void);
void gcInit(void);
void gcWillAllocate(size_t bytes);
void gcAccount(Obj *o, size_t bytes); /* external buffer bytes owned by o, for GC pacing */ Val mkArray(Tag t, size_t n); /* shared checked allocator for unboxed arrays */
void gcRegisterProto(Proto *p);
Obj *gcFindObj(uintptr_t w); /* live heap object holding address w (start or interior), else NULL */
uint64_t gcFreedObjects(void); /* objects actually freed by completed sweeps */
void gcTestFailNextPageSetGrow(void); /* gcHooks.c probe: the next page set grow fails as on OOM */
void gcScanConservative(const void *lo, const void *hi); /* from a root hook during asl_gc_collect: mark objects words in [lo, hi) point into */
extern Val *gcStackBase, **gcStackTop;
extern void (*gcExternalRoots)(void (*mark)(Val)); /* abi.c: roots held by compiled code */

/* value.c; mkStr and mkStrPerm are in prelude.c, the string floor primitives behind stringLength, stringConcat and stringSlice in strFloor.c */
Val mkStr(const char *s, size_t n);
Val mkStrPerm(const char *s, size_t n);
Val bStringLength(Val *a, int n); Val bStringConcat(Val *a, int n); Val bStringSlice(Val *a, int n);
Val mkCons(Val car, Val cdr);
Val mkCtor(int ctor, int n);
const char *tagName(Tag t);
int valEq(Val a, Val b);
void valPrint(FILE *f, Val v, int repr);
char *valToCStr(Val v, int repr);
char *valToCStrN(Val v, int repr, size_t *n); /* *n is the byte length: a string may hold NUL */
char *valToCStrShort(Val v, int repr); /* bounded depth, for diagnostics */
extern int KW_SOME, KW_NONE, KW_OK, KW_ERR, KW_PARTIAL;

/* errors: every runtime and load error longjmps to the active handler and exits nonzero */
_Noreturn void aslError(const char *code, const char *fmt, ...); _Noreturn void aslErrorRethrow(void); /* re-raise aslErrorMsg to the current handler */
void aslErrorHandlerSet(void *jmpbuf); void *aslErrorHandlerGet(void);
int aslKnownErrCode(const char *code); /* true for a code aslError itself raises somewhere in the host (the trap builtin's vocabulary) */
extern char aslErrorMsg[4096];
/* file:line:col of the assert or refute that raised the pending error, else empty; printed on its own line before
   the FAIL line, so the FAIL line and the knownRed digests over it stay as they were */
extern char aslErrorSite[1024];
void errorSite(const char *file, unsigned line, unsigned col);
void printErrorSite(void);

/* float.c */
void floatRepr(double d, char *out);
int floatParse(const char *s, size_t n, double *out);

/* prelude.c */
Val mkBytes(const uint8_t *p, size_t n);
Val mkResult(int ok, Val v);
char *slurpFile(const char *path, size_t *len);
const Builtin *builtinLookup(const char *name);
const Builtin *builtinAt(int i);
int builtinIndex(const Builtin *b);
#define MAX_BUILTIN_ARGS 256
Val builtinCallIn(const Builtin *t, int n, const char *name, int64_t argc, Val *argv);
int fileAppendRaw(const char *path, const char *data, size_t len);
void aslLogSpawn(const char *argv0);
extern long assertCount, refuteCount;
extern const char *initModuleName;
extern const Builtin coreBuiltins[]; extern const int nCoreBuiltins;
extern const Builtin arrayBuiltins[]; extern const int nArrayBuiltins; extern const Builtin kernelBuiltins[]; extern const int nKernelBuiltins;
extern const Builtin parquetBuiltins[]; extern const int nParquetBuiltins; extern const Builtin gcTestBuiltins[]; extern int nGcTestBuiltins; /* gcHooks.c */
extern const Builtin sysBuiltins[]; extern const int nSysBuiltins; extern const Builtin sysNetBuiltins[]; extern const int nSysNetBuiltins;
extern const Builtin parallelBuiltins[]; extern const int nParallelBuiltins;
/* the tables builtinLookup searches, in order: hostBuiltins.c defines asl-host's chain, abi.c a native binary's (core only) */
typedef struct { const Builtin *t; const int *n; } BuiltinTable;
extern const BuiltinTable builtinTables[]; extern const int nBuiltinTables;

/* weak in vm.c for asl-host; a native program's IR defines it (asl-target-llvm/rtObject) for the libaslhost.a C it links */
Val aslCall(Val fn, int argc, Val *args); /* call a function value from a builtin */
void gcMutatorRoots(void (*mark)(Val)); /* the mutator's precise roots, marked at every collection */
void abiGcRoots(void (*mark)(Val)); /* abi.c: compiled code's roots */

/* vm.c */
Val vmCall(Val fn, int argc, Val *args); void vmGcRoots(void (*mark)(Val));
Val vmRunProto(Proto *p);
void vmInit(void); void vmStateSave(void **stackPointer, int *framePointer); void vmStateRestore(void *stackPointer, int framePointer);
extern Val *globals; extern int nglobals;
#define MAX_FRAMES 1048576

#endif
