/* Typed builtins. Every builtin checks its operand tags and fails with ERR_TYPE rather than coercing (I3 I9). */
#include <limits.h>
#include "value.h"
#include <pwd.h>
#include <dirent.h>
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

long assertCount, refuteCount;

/* Strings for asl-host's C (ABIVAL-5: out of strFloor.c, so libaslrt.a defines no mkStr; native code builds its own) */
Val mkStr(const char *s, size_t n) {
  Str *o = asl_alloc(O_STR, sizeof(Str) + n + 1);
  o->len = n; memcpy(o->s, s, n); o->s[n] = 0;
  return vobj(T_STR, o);
}

Val mkStrPerm(const char *s, size_t n) {
  Str *o = asl_alloc_perm(O_STR, sizeof(Str) + n + 1);
  o->len = n; memcpy(o->s, s, n); o->s[n] = 0;
  return vobj(T_STR, o);
}

/* a whole file, NUL-terminated, or NULL when it cannot be opened (reader.c readFile, fileReadBytes, fileReadString) */
char *slurpFile(const char *path, size_t *len) {
  FILE *f = fopen(path, "rb"); if (!f) return NULL;
  size_t cap = 1 << 16, n = 0; char *buf = malloc(cap); if (!buf) exit(70);
  for (;;) {
    if (n == cap) { cap *= 2; buf = realloc(buf, cap); if (!buf) exit(70); }
    size_t r = fread(buf + n, 1, cap - n, f); if (r == 0) break;
    n += r;
  }
  fclose(f); buf = realloc(buf, n + 1); buf[n] = 0; *len = n; return buf;
}

/* appends data to path, opened O_APPEND; 0 or the errno of the failing call (sys.c fileAppend, aslLogSpawn) */
int fileAppendRaw(const char *path, const char *data, size_t len) {
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
  if (fd < 0) return errno;
  const char *buf = data; size_t rem = len;
  while (rem > 0) {
    ssize_t wr = write(fd, buf, rem);
    if (wr < 0) {
      if (errno == EINTR) continue;
      int e = errno; close(fd); return e;
    }
    if (wr == 0) { close(fd); return ENOSPC; }
    buf += wr; rem -= (size_t)wr;
  }
  if (close(fd) < 0) return errno;
  return 0;
}

void aslLogSpawn(const char *argv0) {
  const char *log = getenv("ASL_SPAWN_LOG");
  if (!log || !*log) return;
  char cwd[PATH_MAX];
  if (!getcwd(cwd, sizeof cwd)) cwd[0] = '\0';
  char buf[PATH_MAX * 2 + 64];
  int len = snprintf(buf, sizeof buf, "%s %s\n", argv0 ? argv0 : "", cwd);
  if (len <= 0) return;
  if ((size_t)len >= sizeof buf) len = (int)(sizeof buf - 1);
  fileAppendRaw(log, buf, (size_t)len);
}

static void want(Val v, Tag t, const char *who) {
  if (v.tag != t) aslError("ERR_TYPE", "%s expects %s, got %s", who, tagName(t), tagName(v.tag));
}
static Str *str(Val v, const char *who) { want(v, T_STR, who); return (Str *)v.u.o; }

static Val bList(Val *a, int n) {
  Val acc = VNIL;
  asl_gc_root_push(&acc);
  for (int i = n - 1; i >= 0; i--) acc = mkCons(a[i], acc);
  asl_gc_root_pop(1);
  return acc;
}
/* ctor(v), v rooted across the allocation; listHead, listTail and stringSlice answer (some v) or none, never trap (D148) */
static Val wrap(int ctor, Val v) { asl_gc_root_push(&v); Val r = mkCtor(ctor, 1); asl_gc_root_pop(1); ((Ctor *)r.u.o)->f[0] = v; return r; }
static Val bListTail(Val *a, int n) {
  (void)n; want(a[0], T_LIST, "listTail");
  return a[0].u.o ? wrap(KW_SOME, ((Cons *)a[0].u.o)->cdr) : mkCtor(KW_NONE, 0);
}
static Val bListHead(Val *a, int n) {
  (void)n; want(a[0], T_LIST, "listHead");
  return a[0].u.o ? wrap(KW_SOME, ((Cons *)a[0].u.o)->car) : mkCtor(KW_NONE, 0);
}
static Val bListEmpty(Val *a, int n) { (void)n; want(a[0], T_LIST, "listEmpty?"); return vbool(a[0].u.o == NULL); }
static Val bCons(Val *a, int n) { (void)n; want(a[1], T_LIST, "cons"); return mkCons(a[0], a[1]); }

typedef struct { char *b; size_t n, cap; } SBuf;
static void sput(SBuf *s, const char *p, size_t n) {
  if (s->n + n + 1 > s->cap) { while (s->n + n + 1 > s->cap) s->cap = s->cap ? s->cap * 2 : 64; s->b = realloc(s->b, s->cap); if (!s->b) exit(70); }
  memcpy(s->b + s->n, p, n); s->n += n;
}
static Val bStr(Val *a, int n) {
  SBuf s = {0};
  for (int i = 0; i < n; i++) {
    if (a[i].tag == T_STR) { Str *x = (Str *)a[i].u.o; sput(&s, x->s, x->len); }
    else { size_t k; char *t = valToCStrN(a[i], 1, &k); sput(&s, t, k); free(t); }
  }
  Val r = mkStr(s.b ? s.b : "", s.n);
  free(s.b);
  return r;
}
static Val bStringFromInt(Val *a, int n) { (void)n; want(a[0], T_INT, "stringFromInt64"); char b[32]; snprintf(b, sizeof b, "%lld", (long long)a[0].u.i); return mkStr(b, strlen(b)); }
static Val bStringFromFloat(Val *a, int n) { (void)n; want(a[0], T_FLOAT, "stringFromFloat64"); char b[40]; floatRepr(a[0].u.f, b); return mkStr(b, strlen(b)); }
static Val bStringToFloat(Val *a, int n) {
  (void)n; Str *x = str(a[0], "stringToFloat64"); double d;
  if (!floatParse(x->s, x->len, &d)) return mkCtor(KW_NONE, 0);
  return wrap(KW_SOME, vfloat(d));
}
static Val bIntToFloat(Val *a, int n) { (void)n; want(a[0], T_INT, "int64ToFloat64"); return vfloat((double)a[0].u.i); }
static Val bFloatToInt(Val *a, int n) {
  (void)n; want(a[0], T_FLOAT, "float64ToInt64"); double d = a[0].u.f;
  if (!(d >= -9223372036854775808.0 && d < 9223372036854775808.0)) return mkCtor(KW_NONE, 0);
  return wrap(KW_SOME, vint((int64_t)d));
}
#define MATH1(fn, cfn, name) static Val b##fn(Val *a, int n) { (void)n; want(a[0], T_FLOAT, name); return vfloat(cfn(a[0].u.f)); }
#define MATH2(fn, cfn, name) static Val b##fn(Val *a, int n) { (void)n; want(a[0], T_FLOAT, name); want(a[1], T_FLOAT, name); return vfloat(cfn(a[0].u.f, a[1].u.f)); }
MATH1(Floor, floor, "floor") MATH1(Ceil, ceil, "ceil") MATH1(Round, round, "round")
MATH1(Exp, exp, "exp") MATH1(Log, log, "log") MATH1(Log2, log2, "log2") MATH1(Log10, log10, "log10")
MATH1(Sqrt, sqrt, "sqrt") MATH1(Sin, sin, "sin") MATH1(Cos, cos, "cos") MATH1(Tan, tan, "tan")
MATH2(Pow, pow, "pow") MATH2(Atan2, atan2, "atan2")
static Val bClamp(Val *a, int n) {
  (void)n; want(a[0], T_FLOAT, "clamp"); want(a[1], T_FLOAT, "clamp"); want(a[2], T_FLOAT, "clamp");
  double lo = a[0].u.f, hi = a[1].u.f, x = a[2].u.f;
  if (isnan(lo) || isnan(hi) || !(lo <= hi)) aslError("ERR_RANGE", "clamp: lo <= hi required, got lo=%f hi=%f", lo, hi);
  if (isnan(x)) return vfloat(x);
  return vfloat(x < lo ? lo : (x > hi ? hi : x));
}
static Val bAbs(Val *a, int n) {
  (void)n;
  if (a[0].tag == T_INT) { if (a[0].u.i == INT64_MIN) aslError("ERR_INT_OVERFLOW", "abs of INT64_MIN"); return vint(a[0].u.i < 0 ? -a[0].u.i : a[0].u.i); }
  want(a[0], T_FLOAT, "abs"); return vfloat(fabs(a[0].u.f));
}
static Val minmax(Val *a, int isMax, const char *who) {
  if (a[0].tag != a[1].tag || (a[0].tag != T_INT && a[0].tag != T_FLOAT)) aslError("ERR_TYPE", "%s expects two Int or two Float, got %s and %s", who, tagName(a[0].tag), tagName(a[1].tag));
  int gt = a[0].tag == T_INT ? a[0].u.i > a[1].u.i : a[0].u.f > a[1].u.f;
  return (gt == isMax) ? a[0] : a[1];
}
static Val bMin(Val *a, int n) { (void)n; return minmax(a, 0, "min"); }
static Val bMax(Val *a, int n) { (void)n; return minmax(a, 1, "max"); }
/* count masked to 0..63 (count & 63) so every count, including a negative bit pattern or one past the
   width, is defined, matching the <<, >> lowering asl-target-c/emit.asl and asl-target-llvm/ssa.asl give
   the same shiftMask conformance rule (tests/conformance/xplat/shift_mask_64, shift_mask_overflow);
   left shift wraps in the unsigned domain and back (no overflow trap, as + and * wrap); right shift is
   arithmetic (sign-extending), done on the signed value directly */
static Val bitShiftLeft(Val *a, int n) {
  (void)n; want(a[0], T_INT, "<<"); want(a[1], T_INT, "<<");
  return vint((int64_t)((uint64_t)a[0].u.i << (uint64_t)(a[1].u.i & 63)));
}
static Val bitShiftRight(Val *a, int n) {
  (void)n; want(a[0], T_INT, ">>"); want(a[1], T_INT, ">>");
  return vint(a[0].u.i >> (a[1].u.i & 63));
}
/* the 29 codes aslError itself raises somewhere in the host as a literal first argument (grep -ohE
   'aslError\("ERR_[A-Z0-9_]+"' over every .c file in asl/host/src, quoted, sorted and deduped; test.c's
   "ERR_TEST_FAILED" : "ERR_MAIN_FAILED" ternary is the one call whose code is not a bare literal, both arms
   counted): the trap builtin validates a
   caller-given code against this table so (trap "x" ...) cannot fabricate a code the host would never itself raise.
   Many other ERR_* strings appear in asl/host/src (ERR_BAD_FORM, ERR_READ_UNBALANCED, ERR_TYPE_MISMATCH, ERR_ENV,
   ...); they are not in this table because they are never passed to aslError. Most are diag()/lexErr() codes from
   the host's own bootstrap reader/compiler/resolver/checker (compile.c, reader.c, resolve.c, types.c, loader.c):
   load-time diagnostics collected and printed as "path:line:col: CODE message", a different format than aslError's
   one-line "CODE: message", so trap must not be able to produce them under aslError's format. ERR_ENV (gc.c) and a
   few IoError-returning codes (ERR_PATH_SYMLINK, ERR_PATH_TYPE, ERR_TIMEOUT, sys.c) are returned as plain (err "CODE")
   values or printed directly with their own exit code, likewise never through aslError. Lives here, not value.c
   (plan INT16-valueGcBudget round 1: valueGc group over its 1000-line budget), since its only caller is bTrap
   below and trapBlockedCode's own blocklist sits right next to it for the same reason. */
static const char *const knownErrCodes[] = {
  "ERR_ARG", "ERR_ARITY", "ERR_ASSERT", "ERR_ASSERT_AT_INIT", "ERR_DEPTH", "ERR_DIV_ZERO", "ERR_FIELD",
  "ERR_HEAP_CYCLE", "ERR_INT_OVERFLOW", "ERR_INTERNAL", "ERR_IO", "ERR_LIMIT", "ERR_MAIN_FAILED",
  "ERR_MATCH_NONEXHAUSTIVE", "ERR_NO_ENTRY", "ERR_NOT_SERIALIZABLE", "ERR_OOM", "ERR_PARQUET", "ERR_PROBE",
  "ERR_RANGE", "ERR_REFUTE", "ERR_SERIALIZE_SIZE", "ERR_SHAPE", "ERR_STACK_DEPTH", "ERR_TEST_FAILED", "ERR_TYPE",
  "ERR_UNKNOWN_SYMBOL", "ERR_UNSUPPORTED", "ERR_WORKER_TRAP",
};

int aslKnownErrCode(const char *code) {
  for (size_t i = 0; i < sizeof knownErrCodes / sizeof knownErrCodes[0]; i++) if (!strcmp(code, knownErrCodes[i])) return 1;
  return 0;
}
/* ERR_PROBE, ERR_OOM and ERR_INTERNAL are real aslError codes (aslKnownErrCode accepts them), but gcHooks.c's test
   probes identify their own internal signals by matching aslErrorMsg's prefix against exactly these three strings
   (gcPageSetOomProbe, gcAbortedCollectProbe, gcStaleMarkProbe); letting ASL source raise them through trap would let
   user code impersonate a host-internal invariant failure or a GC test probe's own signal, so trap blocks them like
   an unknown code (round 2 fix a) even though the host itself does raise them elsewhere. */
static int trapBlockedCode(const char *code) {
  static const char *const blocked[] = {"ERR_PROBE", "ERR_OOM", "ERR_INTERNAL"};
  for (size_t i = 0; i < sizeof blocked / sizeof blocked[0]; i++) if (!strcmp(code, blocked[i])) return 1;
  return 0;
}
/* aborts with a chosen error code and message, identical in format and exit status to a host-raised error (LANG-TRAPPRIM):
   the code is checked against aslKnownErrCode so (trap "x" ...) cannot invent a code the host would never itself raise,
   and the message is passed as an argument, not a format string, so a '%' in it is never reinterpreted. A message
   holding a newline is itself rejected (round 2 fix b): the host's own "CODE: message" line is always one line, and
   a bare \n in it would split the error frame across lines on both the VM and a native binary's stderr. */
static Val bTrap(Val *a, int n) {
  (void)n;
  Str *code = str(a[0], "trap"); Str *msg = str(a[1], "trap");
  if (!aslKnownErrCode(code->s) || trapBlockedCode(code->s)) aslError("ERR_TYPE", "trap: unknown error code %s", code->s);
  if (memchr(msg->s, '\n', msg->len)) aslError("ERR_TYPE", "trap: message must not contain a newline");
  aslError(code->s, "%s", msg->s);
  return VUNIT; /* unreachable: aslError is _Noreturn, kept only so bTrap matches BuiltinFn's Val return */
}
static Val bPrint(Val *a, int n) { for (int i = 0; i < n; i++) { if (i) fputc(' ', stdout); valPrint(stdout, a[i], 0); } return VUNIT; }
static Val bPrintln(Val *a, int n) { bPrint(a, n); fputc('\n', stdout); return VUNIT; }


/* ---- bytes, files, hashing ---- */
int zstdDecompress(const uint8_t *src, size_t len, uint8_t **outp, size_t *outn, char *err, size_t errlen);

Val mkBytes(const uint8_t *p, size_t n) {
  Arr *a = asl_alloc(O_ARR, sizeof(Arr));
  a->elem = 1; a->len = n; a->data = malloc(n + 1);
  if (!a->data) aslError("ERR_OOM", "cannot allocate %zu bytes", n);
  if (n) { if (p) memcpy(a->data, p, n); else memset(a->data, 0, n); }
  a->data[n] = 0;
  gcAccount(&a->h, n);
  return vobj(T_BYTES, a);
}
/* takes ownership of a malloc'd buffer */
static Val adoptBytes(uint8_t *p, size_t n) {
  Arr *a = asl_alloc(O_ARR, sizeof(Arr));
  a->elem = 1; a->len = n; a->data = p;
  gcAccount(&a->h, n);
  return vobj(T_BYTES, a);
}
Val mkResult(int ok, Val v) { return wrap(ok ? KW_OK : KW_ERR, v); }
static Val errStr(const char *msg) { return mkResult(0, mkStr(msg, strlen(msg))); }

/* IO failures are (err "KIND: PATH: reason"): KIND is the IoError case of errno, which the prelude's fileRead maps back */
static const char *ioKind(int e) {
  switch (e) {
    case ENOENT: return "notFound";
    case EACCES: case EPERM: case EROFS: return "permissionDenied";
    case EEXIST: case ENOTEMPTY: return "alreadyExists";
    case ENOTDIR: case EISDIR: case ENAMETOOLONG: case ELOOP: case EINVAL: return "invalidPath";
    case EINTR: return "interrupted";
    default: return "other";
  }
}
static Val ioErr(const char *path, int e) { char m[PATH_MAX + 160]; snprintf(m, sizeof m, "%s: %s: %s", ioKind(e), path, strerror(e)); return errStr(m); }
static Val formatErr(const char *kind, const char *path, const char *reason) { char m[PATH_MAX + 160]; snprintf(m, sizeof m, "%s: %s: %s", kind, path ? path : "-", reason); return errStr(m); }

static Val bFileReadBytes(Val *a, int n) {
  (void)n; Str *p = str(a[0], "fileReadBytes"); size_t len;
  char *buf = slurpFile(p->s, &len);
  if (!buf) return ioErr(p->s, errno);
  return mkResult(1, adoptBytes((uint8_t *)buf, len));
}
static Val bFileReadString(Val *a, int n) {
  (void)n; Str *p = str(a[0], "fileReadString"); size_t len;
  char *buf = slurpFile(p->s, &len);
  if (!buf) return ioErr(p->s, errno);
  Val r = mkResult(1, mkStr(buf, len)); free(buf);
  return r;
}
static Val bPathCanonicalize(Val *a, int n) {
  (void)n; Str *p = str(a[0], "realPath"); char real[PATH_MAX];
  if (!realpath(p->s, real)) return ioErr(p->s, errno);
  return mkResult(1, mkStr(real, strlen(real)));
}
static Val bFileWrite(Val *a, int n) {
  (void)n; Str *p = str(a[0], "fileWrite"); const char *data; size_t len;
  if (a[1].tag == T_STR) { data = ((Str *)a[1].u.o)->s; len = ((Str *)a[1].u.o)->len; }
  else if (a[1].tag == T_BYTES) { data = (const char *)((Arr *)a[1].u.o)->data; len = ((Arr *)a[1].u.o)->len; }
  else aslError("ERR_TYPE", "fileWrite expects String or Bytes content, got %s", tagName(a[1].tag));
  FILE *f = fopen(p->s, "wb");
  if (!f) return ioErr(p->s, errno);
  int bad = fwrite(data, 1, len, f) != len, e = errno;
  if (fclose(f) != 0 && !bad) { bad = 1; e = errno; }
  return bad ? ioErr(p->s, e) : mkResult(1, VUNIT);
}
static int cmpName(const void *x, const void *y) { return strcmp(*(char *const *)x, *(char *const *)y); }
/* entries except . and .., sorted bytewise */
static Val bDirList(Val *a, int n) {
  (void)n; Str *p = str(a[0], "dirList");
  DIR *d = opendir(p->s);
  if (!d) return ioErr(p->s, errno);
  char **names = NULL; size_t k = 0, cap = 0; struct dirent *ent;
  while ((ent = readdir(d))) {
    if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, "..")) continue;
    if (k == cap) { cap = cap ? cap * 2 : 32; char **g = realloc(names, cap * sizeof *names); if (!g) break; names = g; }
    if (!(names[k] = strdup(ent->d_name))) break;
    k++;
  }
  int oom = ent != NULL;
  closedir(d);
  if (oom) { while (k) free(names[--k]); free(names); aslError("ERR_OOM", "dirList: out of memory listing %s", p->s); }
  qsort(names, k, sizeof *names, cmpName);
  Val acc = VNIL;
  asl_gc_root_push(&acc);
  while (k) { k--; acc = mkCons(mkStr(names[k], strlen(names[k])), acc); free(names[k]); }
  free(names);
  asl_gc_root_pop(1);
  return mkResult(1, acc);
}
/* a record of n rooted values; keys[n] marks the cached field ids as filled */
static Val mkRec(const char *schema, int *keys, const char *const *fields, int n, const Val *v) {
  if (!keys[n]) { for (int i = 0; i < n; i++) keys[i] = intern(fields[i], strlen(fields[i])); keys[n] = 1; }
  Rec *r = asl_alloc(O_REC, sizeof(Rec) + sizeof(Val) * (size_t)n);
  r->schema = intern(schema, strlen(schema)); r->n = n; r->keys = keys;
  for (int i = 0; i < n; i++) r->v[i] = v[i];
  return vobj(T_REC, r);
}
/* st_mtime in nanoseconds: st_mtimespec on macOS, st_mtim on POSIX 2008 */
static int64_t mtimeNsOf(const struct stat *st) {
#ifdef __APPLE__
  return (int64_t)st->st_mtimespec.tv_sec * 1000000000 + (int64_t)st->st_mtimespec.tv_nsec;
#else
  return (int64_t)st->st_mtim.tv_sec * 1000000000 + (int64_t)st->st_mtim.tv_nsec;
#endif
}
static Val bFileStat(Val *a, int n) {
  (void)n; Str *p = str(a[0], "fileStat"); struct stat st;
  if (stat(p->s, &st) != 0) return ioErr(p->s, errno);
  static int keys[7]; static const char *const f[] = {"isFile", "isDir", "size", "mtime", "mode", "mtimeNs"};
  Val v[6] = {vbool(S_ISREG(st.st_mode)), vbool(S_ISDIR(st.st_mode)), vint((int64_t)st.st_size), vint((int64_t)st.st_mtime), vint((int64_t)st.st_mode), vint(mtimeNsOf(&st))};
  Val r = mkRec("FileStat", keys, f, 6, v);
  return mkResult(1, r);
}
#define FILE_READ_RANGE_MAX (1024LL * 1024LL * 1024LL) /* 1 GiB cap */

static Val bFileReadRange(Val *a, int n) {
  (void)n;
  if (n < 3 || a[0].tag != T_STR || a[1].tag != T_INT || a[2].tag != T_INT) {
    return formatErr("fileReadRange", "-", "invalid argument");
  }
  Str *p = (Str *)a[0].u.o;
  int64_t offset = a[1].u.i;
  int64_t length = a[2].u.i;
  if (offset < 0) return formatErr("fileReadRange", p->s, "negative offset");
  if (length < 0) return formatErr("fileReadRange", p->s, "negative length");
  if (length > FILE_READ_RANGE_MAX) return formatErr("lengthLimitExceeded", p->s, "length exceeds 1 GiB cap");
  int fd = open(p->s, O_RDONLY);
  if (fd < 0) return ioErr(p->s, errno);
  struct stat fst;
  if (fstat(fd, &fst) != 0) {
    int e = errno;
    close(fd);
    return ioErr(p->s, e);
  }
  int is_reg = S_ISREG(fst.st_mode);
  if (is_reg) {
    int64_t avail = (int64_t)fst.st_size > offset ? (int64_t)fst.st_size - offset : 0;
    if (length > avail) length = avail;
  } else {
    int non_seekable = (lseek(fd, 0, SEEK_CUR) == (off_t)-1 && errno == ESPIPE);
    if (non_seekable && offset > 0) {
      close(fd);
      return formatErr("nonSeekable", p->s, "positive offset on non-seekable file");
    }
    if (!non_seekable && offset > 0) {
      if (lseek(fd, (off_t)offset, SEEK_SET) == (off_t)-1) {
        int e = errno;
        close(fd);
        if (e == ESPIPE) return formatErr("nonSeekable", p->s, "positive offset on non-seekable file");
        return ioErr(p->s, e);
      }
    }
  }
  if (length == 0) {
    close(fd);
    return mkResult(1, mkBytes(NULL, 0));
  }
  uint8_t *buf = malloc((size_t)length + 1);
  if (!buf) {
    close(fd);
    return formatErr("fileReadRange", p->s, "out of memory");
  }
  size_t total = 0;
  while (total < (size_t)length) {
    ssize_t r = is_reg
      ? pread(fd, buf + total, (size_t)length - total, (off_t)offset + (off_t)total)
      : read(fd, buf + total, (size_t)length - total);
    if (r == 0) break;
    if (r < 0) {
      if (errno == EINTR) continue;
      int e = errno;
      free(buf);
      close(fd);
      return ioErr(p->s, e);
    }
    total += (size_t)r;
  }
  close(fd);
  if (total < (size_t)length) {
    uint8_t *shrunk = realloc(buf, total + 1);
    if (shrunk) buf = shrunk;
  }
  buf[total] = 0;
  return mkResult(1, adoptBytes(buf, total));
}
/* /bin/sh -c CMD with stdout and stderr captured; retains shell-like 128+signal convention */
static Val bProcessRun(Val *a, int n) {
  (void)n; Str *p = str(a[0], "processRun"); aslLogSpawn("/bin/sh");
  int po[2], pe[2];
  if (pipe(po) != 0) aslError("ERR_IO", "processRun: pipe: %s", strerror(errno));
  if (pipe(pe) != 0) { int e = errno; close(po[0]); close(po[1]); aslError("ERR_IO", "processRun: pipe: %s", strerror(e)); }
  pid_t pid = fork();
  if (pid < 0) { int e = errno; close(po[0]); close(po[1]); close(pe[0]); close(pe[1]); aslError("ERR_IO", "processRun: fork: %s", strerror(e)); }
  if (pid == 0) {
    dup2(po[1], STDOUT_FILENO); dup2(pe[1], STDERR_FILENO);
    close(po[0]); close(po[1]); close(pe[0]); close(pe[1]);
    execl("/bin/sh", "sh", "-c", p->s, (char *)NULL);
    _exit(127);
  }
  close(po[1]); close(pe[1]);
  struct pollfd fds[2] = {{po[0], POLLIN, 0}, {pe[0], POLLIN, 0}};
  SBuf out[2] = {{0}, {0}};
  for (int open = 2; open > 0;) {
    if (poll(fds, 2, -1) < 0) { if (errno == EINTR) continue; break; }
    for (int i = 0; i < 2; i++) {
      if (fds[i].fd < 0 || !(fds[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
      char buf[4096]; ssize_t r = read(fds[i].fd, buf, sizeof buf);
      if (r > 0) sput(&out[i], buf, (size_t)r);
      else if (r == 0 || errno != EINTR) { close(fds[i].fd); fds[i].fd = -1; open--; }
    }
  }
  for (int i = 0; i < 2; i++) if (fds[i].fd >= 0) close(fds[i].fd);
  int st = 0; pid_t w;
  while ((w = waitpid(pid, &st, 0)) < 0 && errno == EINTR) {}
  if (w < 0) { int e = errno; free(out[0].b); free(out[1].b); aslError("ERR_IO", "processRun: waitpid: %s", strerror(e)); }
  int code = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
  Val v[3] = {vint(code), mkStr(out[0].b ? out[0].b : "", out[0].n), VUNIT};
  asl_gc_root_push(&v[1]);
  v[2] = mkStr(out[1].b ? out[1].b : "", out[1].n);
  asl_gc_root_push(&v[2]);
  free(out[0].b); free(out[1].b);
  static int keys[4]; static const char *const f[] = {"exitCode", "stdout", "stderr"};
  Val r = mkRec("ProcessOutput", keys, f, 3, v);
  asl_gc_root_pop(2);
  return r;
}
static Val bClockRealtimeNs(Val *a, int n) {
  (void)a; (void)n;
  struct timespec ts;
  if (clock_gettime(CLOCK_REALTIME, &ts) != 0) aslError("ERR_IO", "nowNs: %s", strerror(errno));
  return vint((int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec);
}
static Val bClockMonotonicNs(Val *a, int n) {
  (void)a; (void)n;
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) aslError("ERR_IO", "monotonicNs: %s", strerror(errno));
  return vint((int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec);
}
static Val bSleepMs(Val *a, int n) {
  (void)n;
  want(a[0], T_INT, "sleepMs");
  int64_t ms = a[0].u.i;
  if (ms < 0) aslError("ERR_RANGE", "sleepMs: %lld is negative", (long long)ms);
  struct timespec req, rem;
  req.tv_sec = (time_t)(ms / 1000);
  req.tv_nsec = (long)((ms % 1000) * 1000000);
  while (nanosleep(&req, &rem) == -1) {
    if (errno == EINTR) req = rem;
    else aslError("ERR_IO", "sleepMs: nanosleep: %s", strerror(errno));
  }
  return VUNIT;
}
static Val bEnvGet(Val *a, int n) {
  if (n < 1 || a[0].tag != T_STR) return mkCtor(KW_NONE, 0);
  Str *s = (Str *)a[0].u.o;
  if (memchr(s->s, '\0', s->len)) return mkCtor(KW_NONE, 0);
  const char *v = getenv(s->s);
  if (!v) return mkCtor(KW_NONE, 0);
  return wrap(KW_SOME, mkStr(v, strlen(v)));
}
static Val bGetHomeDir(Val *a, int n) {
  (void)a; (void)n;
  const char *home = getenv("HOME");
  if (home && home[0] != '\0') {
    return mkResult(1, mkStr(home, strlen(home)));
  }
  struct passwd *pw = getpwuid(getuid());
  if (pw && pw->pw_dir && pw->pw_dir[0] != '\0') {
    return mkResult(1, mkStr(pw->pw_dir, strlen(pw->pw_dir)));
  }
  return formatErr("getHomeDir", "-", "cannot determine home directory");
}
static Val bFileCreateExclusive(Val *a, int n) {
  if (n < 2 || a[0].tag != T_STR) return formatErr("fileCreateExclusive", "-", "invalid argument");
  Str *p = (Str *)a[0].u.o;
  if (memchr(p->s, '\0', p->len)) return ioErr(p->s, EINVAL);
  const char *data;
  size_t len;
  if (a[1].tag == T_STR) {
    data = ((Str *)a[1].u.o)->s;
    len = ((Str *)a[1].u.o)->len;
  } else if (a[1].tag == T_BYTES) {
    data = (const char *)((Arr *)a[1].u.o)->data;
    len = ((Arr *)a[1].u.o)->len;
  } else {
    return formatErr("fileCreateExclusive", p->s, "invalid argument");
  }
  int fd = open(p->s, O_WRONLY | O_CREAT | O_EXCL, 0666);
  if (fd < 0) return ioErr(p->s, errno);
  size_t written = 0;
  int writeErr = 0;
  while (written < len) {
    ssize_t w = write(fd, data + written, len - written);
    if (w < 0) {
      if (errno == EINTR) continue;
      writeErr = errno;
      break;
    }
    written += (size_t)w;
  }
  if (close(fd) != 0 && writeErr == 0) {
    writeErr = errno;
  }
  if (writeErr != 0) {
    unlink(p->s);
    return ioErr(p->s, writeErr);
  }
  return mkResult(1, VUNIT);
}
static Val bDirCreate(Val *a, int n) {
  if (n < 1 || a[0].tag != T_STR) return formatErr("dirCreate", "-", "invalid argument");
  Str *p = (Str *)a[0].u.o;
  if (p->len == 0) return ioErr(p->s, EINVAL);
  if (memchr(p->s, '\0', p->len)) return ioErr(p->s, EINVAL);
  char buf[PATH_MAX];
  if (p->len >= sizeof(buf)) return ioErr(p->s, ENAMETOOLONG);
  memcpy(buf, p->s, p->len + 1);

  for (size_t i = 1; i <= p->len; i++) {
    if (buf[i] == '/' || buf[i] == '\0') {
      char c = buf[i];
      buf[i] = '\0';
      if (buf[0] != '\0' && strcmp(buf, "/") != 0) {
        struct stat st;
        if (stat(buf, &st) == 0) {
          if (!S_ISDIR(st.st_mode)) return ioErr(buf, ENOTDIR);
        } else {
          if (mkdir(buf, 0777) != 0 && errno != EEXIST) return ioErr(buf, errno);
          if (stat(buf, &st) != 0 || !S_ISDIR(st.st_mode)) return ioErr(buf, ENOTDIR);
        }
      }
      buf[i] = c;
    }
  }
  return mkResult(1, VUNIT);
}
static Val bPathRename(Val *a, int n) {
  if (n < 2 || a[0].tag != T_STR || a[1].tag != T_STR) return formatErr("pathRename", "-", "invalid argument");
  Str *from = (Str *)a[0].u.o;
  Str *to = (Str *)a[1].u.o;
  if (memchr(from->s, '\0', from->len)) return ioErr(from->s, EINVAL);
  if (memchr(to->s, '\0', to->len)) return ioErr(to->s, EINVAL);
  if (rename(from->s, to->s) != 0) return ioErr(from->s, errno);
  return mkResult(1, VUNIT);
}
static Str *pathArg(Val v) { return v.tag == T_STR && !memchr(((Str *)v.u.o)->s, '\0', ((Str *)v.u.o)->len) ? (Str *)v.u.o : NULL; }
static Val bFileChmod(Val *a, int n) {
  (void)n; Str *p = pathArg(a[0]);
  if (!p || a[1].tag != T_INT || a[1].u.i < 0 || a[1].u.i > 07777) return formatErr("fileChmod", p ? p->s : "-", "invalid argument");
  if (chmod(p->s, (mode_t)a[1].u.i) != 0) return ioErr(p->s, errno);
  return mkResult(1, VUNIT);
}
static Val bFileFsync(Val *a, int n) {
  (void)n; Str *p = pathArg(a[0]);
  if (!p) return formatErr("fileFsync", "-", "invalid argument");
  int fd = open(p->s, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return ioErr(p->s, errno);
  int r, e = 0;
  while ((r = fsync(fd)) != 0 && errno == EINTR) {}
  if (r != 0) e = errno;
  if (close(fd) != 0 && !e && errno != EINTR) e = errno;
  return e ? ioErr(p->s, e) : mkResult(1, VUNIT);
}
static Val bFileReadlink(Val *a, int n) {
  (void)n; Str *p = pathArg(a[0]);
  if (!p) return formatErr("fileReadlink", "-", "invalid argument");
  for (size_t cap = 256; cap <= ((size_t)1 << 20); cap *= 2) {
    char *buf = malloc(cap);
    if (!buf) return formatErr("fileReadlink", p->s, "out of memory");
    ssize_t len = readlink(p->s, buf, cap);
    if (len < 0) { int e = errno; free(buf); return ioErr(p->s, e); }
    if ((size_t)len < cap) { Val r = mkStr(buf, (size_t)len); free(buf); return mkResult(1, r); }
    free(buf);
  }
  return ioErr(p->s, ENAMETOOLONG);
}
static Val bFileLstat(Val *a, int n) {
  (void)n; Str *p = pathArg(a[0]); struct stat st;
  if (!p) return formatErr("fileLstat", "-", "invalid argument");
  if (lstat(p->s, &st) != 0) return ioErr(p->s, errno);
  static int keys[8]; static const char *const f[] = {"isFile", "isDir", "isSymlink", "size", "mtime", "mode", "mtimeNs"};
  Val v[7] = {vbool(S_ISREG(st.st_mode)), vbool(S_ISDIR(st.st_mode)), vbool(S_ISLNK(st.st_mode)), vint((int64_t)st.st_size), vint((int64_t)st.st_mtime), vint((int64_t)st.st_mode), vint(mtimeNsOf(&st))};
  Val r = mkRec("LinkStat", keys, f, 7, v);
  return mkResult(1, r);
}
/* utimensat: atime and mtime both set to mtimeNs, following a final symlink */
static Val bFileUtime(Val *a, int n) {
  (void)n; Str *p = pathArg(a[0]);
  if (!p || a[1].tag != T_INT) return formatErr("fileUtime", p ? p->s : "-", "invalid argument");
  int64_t ns = a[1].u.i, sec = ns / 1000000000, rem = ns % 1000000000;
  if (rem < 0) { rem += 1000000000; sec -= 1; }
  struct timespec ts[2];
  ts[0].tv_sec = (time_t)sec; ts[0].tv_nsec = (long)rem; ts[1] = ts[0];
  if (utimensat(AT_FDCWD, p->s, ts, 0) != 0) return ioErr(p->s, errno);
  return mkResult(1, VUNIT);
}
static Val bPathSymlink(Val *a, int n) {
  (void)n; Str *target = pathArg(a[0]), *link = pathArg(a[1]);
  if (!target || !link || target->len == 0) return formatErr("pathSymlink", link ? link->s : "-", "invalid argument");
  if (symlink(target->s, link->s) != 0) return ioErr(link->s, errno);
  return mkResult(1, VUNIT);
}
static int removeRec(const char *path, char *errBuf, size_t errBufLen) {
  struct stat st;
  if (lstat(path, &st) != 0) {
    snprintf(errBuf, errBufLen, "%s: %s: %s", ioKind(errno), path, strerror(errno));
    return -1;
  }
  if (S_ISDIR(st.st_mode)) {
    int dfd = open(path, O_RDONLY | O_NOFOLLOW | O_DIRECTORY);
    if (dfd < 0) {
      snprintf(errBuf, errBufLen, "%s: %s: %s", ioKind(errno), path, strerror(errno));
      return -1;
    }
    DIR *d = fdopendir(dfd);
    if (!d) {
      int e = errno;
      close(dfd);
      snprintf(errBuf, errBufLen, "%s: %s: %s", ioKind(e), path, strerror(e));
      return -1;
    }
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
      if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, "..")) continue;
      char sub[PATH_MAX];
      int n = snprintf(sub, sizeof(sub), "%s/%s", path, ent->d_name);
      if (n < 0 || (size_t)n >= sizeof(sub)) {
        closedir(d);
        snprintf(errBuf, errBufLen, "%s: %s: %s", ioKind(ENAMETOOLONG), path, strerror(ENAMETOOLONG));
        return -1;
      }
      if (removeRec(sub, errBuf, errBufLen) != 0) {
        closedir(d);
        return -1;
      }
    }
    closedir(d);
    if (rmdir(path) != 0) {
      snprintf(errBuf, errBufLen, "%s: %s: %s", ioKind(errno), path, strerror(errno));
      return -1;
    }
  } else {
    if (unlink(path) != 0) {
      snprintf(errBuf, errBufLen, "%s: %s: %s", ioKind(errno), path, strerror(errno));
      return -1;
    }
  }
  return 0;
}
static Val bPathRemove(Val *a, int n) {
  if (n < 1 || a[0].tag != T_STR) return formatErr("pathRemove", "-", "invalid argument");
  Str *p = (Str *)a[0].u.o;
  if (memchr(p->s, '\0', p->len)) return ioErr(p->s, EINVAL);
  char errBuf[512] = {0};
  if (removeRec(p->s, errBuf, sizeof(errBuf)) != 0) {
    return errStr(errBuf[0] ? errBuf : "pathRemove failed");
  }
  return mkResult(1, VUNIT);
}
typedef struct ProcessHandleNode {
  int64_t handleId;
  pid_t pid;
  int outFd;
  int errFd;
  struct ProcessHandleNode *next;
} ProcessHandleNode;

static ProcessHandleNode *activeProcesses = NULL;
static int64_t nextProcessHandleId = 1;

static Val bProcessSpawn(Val *a, int n) {
  if (n < 1 || a[0].tag != T_STR) return formatErr("processSpawn", "-", "invalid argument");
  Str *cmd = (Str *)a[0].u.o;
  if (memchr(cmd->s, '\0', cmd->len)) return ioErr("processSpawn", EINVAL); aslLogSpawn("/bin/sh");

  char outTemplate[] = "/tmp/asl_sp_out_XXXXXX";
  char errTemplate[] = "/tmp/asl_sp_err_XXXXXX";
  int outFd = mkstemp(outTemplate);
  if (outFd < 0) return ioErr("/tmp", errno);
  unlink(outTemplate);
  int errFd = mkstemp(errTemplate);
  if (errFd < 0) {
    int e = errno;
    close(outFd);
    return ioErr("/tmp", e);
  }
  unlink(errTemplate);
  if (fcntl(outFd, F_SETFD, FD_CLOEXEC) < 0) {
    int e = errno;
    close(outFd);
    close(errFd);
    return ioErr("fcntl", e);
  }
  if (fcntl(errFd, F_SETFD, FD_CLOEXEC) < 0) {
    int e = errno;
    close(outFd);
    close(errFd);
    return ioErr("fcntl", e);
  }

  pid_t pid = fork();
  if (pid < 0) {
    int e = errno;
    close(outFd);
    close(errFd);
    return ioErr("fork", e);
  }

  if (pid == 0) {
    setpgid(0, 0);
    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      close(devnull);
    }
    dup2(outFd, STDOUT_FILENO);
    dup2(errFd, STDERR_FILENO);
    close(outFd);
    close(errFd);
    execl("/bin/sh", "sh", "-c", cmd->s, (char *)NULL);
    _exit(127);
  }

  setpgid(pid, pid);

  ProcessHandleNode *node = malloc(sizeof(ProcessHandleNode));
  if (!node) {
    kill(-pid, SIGKILL);
    close(outFd);
    close(errFd);
    return formatErr("processSpawn", "-", "out of memory");
  }
  node->handleId = nextProcessHandleId++;
  node->pid = pid;
  node->outFd = outFd;
  node->errFd = errFd;
  node->next = activeProcesses;
  activeProcesses = node;

  return mkResult(1, vint(node->handleId));
}

static char *slurpFd(int fd, size_t *outLen, int *outErr) {
  *outLen = 0;
  *outErr = 0;
  if (lseek(fd, 0, SEEK_SET) < 0) {
    *outErr = errno;
    return NULL;
  }
  struct stat st;
  if (fstat(fd, &st) < 0) {
    *outErr = errno;
    return NULL;
  }
  size_t sz = (size_t)st.st_size;
  char *buf = malloc(sz + 1);
  if (!buf) {
    *outErr = ENOMEM;
    return NULL;
  }
  size_t total = 0;
  while (total < sz) {
    ssize_t n = read(fd, buf + total, sz - total);
    if (n < 0) {
      if (errno == EINTR) continue;
      *outErr = errno;
      free(buf);
      return NULL;
    }
    if (n == 0) break;
    total += (size_t)n;
  }
  buf[total] = '\0';
  *outLen = total;
  return buf;
}

static Val bProcessWait(Val *a, int n) {
  if (n < 2 || a[0].tag != T_INT || a[1].tag != T_INT) return formatErr("processWait", "-", "invalid argument");
  int64_t handleId = a[0].u.i;
  int64_t timeoutMs = a[1].u.i;

  char hbuf[32];
  snprintf(hbuf, sizeof(hbuf), "%lld", (long long)handleId);

  if (timeoutMs < 0) return formatErr("processWait", hbuf, "negative timeoutMs");

  ProcessHandleNode **curr = &activeProcesses;
  ProcessHandleNode *target = NULL;
  while (*curr) {
    if ((*curr)->handleId == handleId) {
      target = *curr;
      *curr = target->next;
      break;
    }
    curr = &(*curr)->next;
  }

  if (!target) return formatErr("processWait", hbuf, "unknown or freed handle");

  pid_t pid = target->pid;
  int st = 0;
  int timed_out = 0;

  if (timeoutMs == 0) {
    pid_t w;
    while ((w = waitpid(pid, &st, 0)) < 0 && errno == EINTR) {}
    if (w < 0) {
      int e = errno;
      close(target->outFd);
      close(target->errFd);
      free(target);
      return ioErr("processWait", e);
    }
  } else {
    struct timespec tsStart;
    clock_gettime(CLOCK_MONOTONIC, &tsStart);
    int reaped = 0;
    while (1) {
      pid_t w = waitpid(pid, &st, WNOHANG);
      if (w == pid) {
        reaped = 1;
        break;
      }
      if (w < 0) {
        if (errno != EINTR) {
          int e = errno;
          close(target->outFd);
          close(target->errFd);
          free(target);
          return ioErr("processWait", e);
        }
      }
      struct timespec tsCur;
      clock_gettime(CLOCK_MONOTONIC, &tsCur);
      int64_t elapsedMs = (int64_t)(tsCur.tv_sec - tsStart.tv_sec) * 1000LL +
                          (int64_t)(tsCur.tv_nsec - tsStart.tv_nsec) / 1000000LL;
      if (elapsedMs >= timeoutMs) {
        timed_out = 1;
        break;
      }
      struct timespec req = {0, 5000000};
      nanosleep(&req, NULL);
    }

    if (timed_out) {
      kill(-pid, SIGTERM);

      struct timespec termStart;
      clock_gettime(CLOCK_MONOTONIC, &termStart);
      while (1) {
        if (!reaped) {
          pid_t w = waitpid(pid, &st, WNOHANG);
          if (w == pid) {
            reaped = 1;
          } else if (w < 0 && errno != EINTR) {
            int e = errno;
            close(target->outFd);
            close(target->errFd);
            free(target);
            return ioErr("processWait", e);
          }
        }
        if (reaped && kill(-pid, 0) < 0 && errno == ESRCH) {
          break;
        }
        struct timespec tsCur;
        clock_gettime(CLOCK_MONOTONIC, &tsCur);
        int64_t termElapsedMs = (int64_t)(tsCur.tv_sec - termStart.tv_sec) * 1000LL +
                                (int64_t)(tsCur.tv_nsec - termStart.tv_nsec) / 1000000LL;
        if (termElapsedMs >= 2000) break;
        struct timespec req = {0, 10000000};
        nanosleep(&req, NULL);
      }

      kill(-pid, SIGKILL);
      if (!reaped) {
        pid_t w;
        while ((w = waitpid(pid, &st, 0)) < 0 && errno == EINTR) {}
        if (w < 0) {
          int e = errno;
          close(target->outFd);
          close(target->errFd);
          free(target);
          return ioErr("processWait", e);
        }
        reaped = 1;
      }
      for (int i = 0; i < 20; i++) {
        if (kill(-pid, 0) < 0 && errno == ESRCH) break;
        struct timespec req = {0, 5000000};
        nanosleep(&req, NULL);
      }
    }
  }

  int exitCode;
  if (timed_out) {
    exitCode = 124;
  } else {
    exitCode = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
  }

  int slurpErr = 0;
  size_t outLen = 0, errLen = 0;
  char *outBuf = slurpFd(target->outFd, &outLen, &slurpErr);
  char *errBuf = NULL;
  if (!slurpErr) {
    errBuf = slurpFd(target->errFd, &errLen, &slurpErr);
  }
  close(target->outFd);
  close(target->errFd);
  free(target);

  if (slurpErr) {
    if (outBuf) free(outBuf);
    if (errBuf) free(errBuf);
    return formatErr("process", hbuf, strerror(slurpErr));
  }

  Val v[3] = {vint(exitCode), mkStr(outBuf ? outBuf : "", outLen), VUNIT};
  asl_gc_root_push(&v[1]);
  v[2] = mkStr(errBuf ? errBuf : "", errLen);
  asl_gc_root_push(&v[2]);
  if (outBuf) free(outBuf);
  if (errBuf) free(errBuf);

  static int keys[4];
  static const char *const f[] = {"exitCode", "stdout", "stderr"};
  Val r = mkRec("ProcessOutput", keys, f, 3, v);
  asl_gc_root_pop(2);

  return mkResult(1, r);
}
static Val bEprintln(Val *a, int n) { for (int i = 0; i < n; i++) { if (i) fputc(' ', stderr); valPrint(stderr, a[i], 0); } fputc('\n', stderr); return VUNIT; }
static Val bZstd(Val *a, int n) {
  (void)n; want(a[0], T_BYTES, "zstdDecompress");
  Arr *b = (Arr *)a[0].u.o; uint8_t *out; size_t on; char err[256];
  if (zstdDecompress(b->data, b->len, &out, &on, err, sizeof err) != 0) return errStr(err);
  return mkResult(1, adoptBytes(out, on));
}
static Val bBytesLength(Val *a, int n) { (void)n; want(a[0], T_BYTES, "bytesLength"); return vint((int64_t)((Arr *)a[0].u.o)->len); }
static Val bBytesAlloc(Val *a, int n) {
  (void)n; want(a[0], T_INT, "bytesAlloc");
  if (a[0].u.i < 0) aslError("ERR_RANGE", "bytesAlloc: negative size %lld", (long long)a[0].u.i);
  return mkBytes(NULL, (size_t)a[0].u.i);
}
/* the slot's byte offset, or ERR_RANGE: slot i of width w lies in [i*w, i*w+w) */
static size_t slot(Val *a, size_t w, const char *who) {
  want(a[0], T_BYTES, who); want(a[1], T_INT, who);
  size_t len = ((Arr *)a[0].u.o)->len; int64_t i = a[1].u.i;
  if (i < 0 || (uint64_t)i >= len / w) aslError("ERR_RANGE", "%s: slot %lld outside %zu bytes", who, (long long)i, len);
  return (size_t)i * w;
}
static Val bBytesGet(Val *a, int n) { (void)n; size_t o = slot(a, 1, "bytesGet"); return vint(((Arr *)a[0].u.o)->data[o]); }
/* (:m :why "writes raw bytes, never a Val: no heap edge" :ref D153) */
static Val bBytesSet(Val *a, int n) {
  (void)n; size_t o = slot(a, 1, "bytesSet"); want(a[2], T_INT, "bytesSet");
  if (a[2].u.i < 0 || a[2].u.i > 255) aslError("ERR_RANGE", "bytesSet: %lld is not a byte", (long long)a[2].u.i);
  ((Arr *)a[0].u.o)->data[o] = (unsigned char)a[2].u.i;
  return VUNIT;
}
static Val bBytesGetF64(Val *a, int n) { (void)n; size_t o = slot(a, 8, "bytesGetFloat64"); double d; memcpy(&d, ((Arr *)a[0].u.o)->data + o, 8); return vfloat(d); }
/* (:m :why "writes raw bytes, never a Val: no heap edge" :ref D153) */
static Val bBytesSetF64(Val *a, int n) {
  (void)n; size_t o = slot(a, 8, "bytesSetFloat64"); want(a[2], T_FLOAT, "bytesSetFloat64");
  memcpy(((Arr *)a[0].u.o)->data + o, &a[2].u.f, 8);
  return VUNIT;
}
/* the one string primitive past the three of the floor: a string's UTF-8 bytes, from which charCode and fnv1a64 derive in ASL */
static Val bStringToBytes(Val *a, int n) { (void)n; Str *s = str(a[0], "stringToBytes"); return mkBytes((const uint8_t *)s->s, s->len); }

static const uint32_t K256[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
  0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
  0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
#define ROR(x, r) (((x) >> (r)) | ((x) << (32 - (r))))
static void shaBlock(uint32_t h[8], const uint8_t *p) {
  uint32_t w[64], v[8];
  for (int i = 0; i < 16; i++) w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 | (uint32_t)p[4 * i + 2] << 8 | p[4 * i + 3];
  for (int i = 16; i < 64; i++) {
    uint32_t s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3), s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  memcpy(v, h, sizeof v);
  for (int i = 0; i < 64; i++) {
    uint32_t t1 = v[7] + (ROR(v[4], 6) ^ ROR(v[4], 11) ^ ROR(v[4], 25)) + ((v[4] & v[5]) ^ (~v[4] & v[6])) + K256[i] + w[i];
    uint32_t t2 = (ROR(v[0], 2) ^ ROR(v[0], 13) ^ ROR(v[0], 22)) + ((v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]));
    memmove(v + 1, v, 7 * sizeof(uint32_t)); v[4] += t1; v[0] = t1 + t2;
  }
  for (int i = 0; i < 8; i++) h[i] += v[i];
}
static Val bSha256(Val *a, int n) {
  (void)n; want(a[0], T_BYTES, "bytesSha256");
  Arr *b = (Arr *)a[0].u.o; const uint8_t *p = b->data; size_t len = b->len, i = 0;
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  for (; i + 64 <= len; i += 64) shaBlock(h, p + i);
  uint8_t tail[128] = {0}; size_t r = len - i;
  memcpy(tail, p + i, r); tail[r] = 0x80;
  size_t tl = r + 9 <= 64 ? 64 : 128; uint64_t bits = (uint64_t)len * 8;
  for (int k = 0; k < 8; k++) tail[tl - 1 - k] = (uint8_t)(bits >> (8 * k));
  shaBlock(h, tail); if (tl == 128) shaBlock(h, tail + 64);
  char hex[65];
  for (int k = 0; k < 8; k++) snprintf(hex + 8 * k, 9, "%08x", h[k]);
  return mkStr(hex, 64);
}

static Val bStartsWith(Val *a, int n) {
  (void)n; Str *x = str(a[0], "stringStartsWith?"), *y = str(a[1], "stringStartsWith?");
  return vbool(y->len <= x->len && !memcmp(x->s, y->s, y->len));
}
static Val bContains(Val *a, int n) {
  (void)n; Str *x = str(a[0], "stringContains?"), *y = str(a[1], "stringContains?");
  if (y->len == 0) return vbool(1);
  for (size_t i = 0; i + y->len <= x->len; i++) if (!memcmp(x->s + i, y->s, y->len)) return vbool(1);
  return vbool(0);
}

static Val bPartial(Val *a, int n) {
  if (n < 1) aslError("ERR_ARITY", "partial expects a function");
  Val r = mkCtor(KW_PARTIAL, n);
  for (int i = 0; i < n; i++) ((Ctor *)r.u.o)->f[i] = a[i];
  return r;
}
const Builtin coreBuiltins[] = {
  {"list", bList, -1, 0}, {"listTail", bListTail, 1, 0}, {"listHead", bListHead, 1, 0},
  {"listEmpty?", bListEmpty, 1, 0}, {"cons", bCons, 2, 0},
  {"str", bStr, -1, 0}, {"stringLength", bStringLength, 1, 0}, {"stringConcat", bStringConcat, 2, 0}, {"stringSlice", bStringSlice, 3, 0},
  {"stringFromInt64", bStringFromInt, 1, 0}, {"stringFromFloat64", bStringFromFloat, 1, 0}, {"stringToFloat64", bStringToFloat, 1, 0},
  {"int64ToFloat64", bIntToFloat, 1, 0}, {"float64ToInt64", bFloatToInt, 1, 0},
  {"floor", bFloor, 1, 0}, {"ceil", bCeil, 1, 0}, {"round", bRound, 1, 0}, {"clamp", bClamp, 3, 0}, {"pow", bPow, 2, 0}, {"exp", bExp, 1, 0}, {"log", bLog, 1, 0},
  {"log2", bLog2, 1, 0}, {"log10", bLog10, 1, 0}, {"sqrt", bSqrt, 1, 0}, {"sin", bSin, 1, 0}, {"cos", bCos, 1, 0}, {"tan", bTan, 1, 0}, {"atan2", bAtan2, 2, 0},
  {"fileReadBytes", bFileReadBytes, 1, 1}, {"fileReadString", bFileReadString, 1, 1}, {"realPath", bPathCanonicalize, 1, 1}, {"zstdDecompress", bZstd, 1, 0}, {"bytesSha256", bSha256, 1, 0}, {"bytesLength", bBytesLength, 1, 0},
  {"stringStartsWith?", bStartsWith, 2, 0}, {"stringContains?", bContains, 2, 0},
  {"partial", bPartial, -1, 0},
  {"abs", bAbs, 1, 0}, {"min", bMin, 2, 0}, {"max", bMax, 2, 0}, {"<<", bitShiftLeft, 2, 0}, {">>", bitShiftRight, 2, 0}, {"trap", bTrap, 2, 0}, {"print", bPrint, -1, 1}, {"println", bPrintln, -1, 1}, {"eprintln", bEprintln, -1, 1},
  {"fileWrite", bFileWrite, 2, 1}, {"dirList", bDirList, 1, 1}, {"fileStat", bFileStat, 1, 1}, {"fileReadRange", bFileReadRange, 3, 1}, {"processRun", bProcessRun, 1, 1},
  {"nowNs", bClockRealtimeNs, 0, 1}, {"monotonicNs", bClockMonotonicNs, 0, 1}, {"sleepMs", bSleepMs, 1, 1},
  {"envGet", bEnvGet, 1, 1}, {"getHomeDir", bGetHomeDir, 0, 1}, {"processSpawn", bProcessSpawn, 1, 1}, {"processWait", bProcessWait, 2, 1},
  {"fileCreateExclusive", bFileCreateExclusive, 2, 1}, {"dirCreate", bDirCreate, 1, 1},
  {"pathRemove", bPathRemove, 1, 1}, {"pathRename", bPathRename, 2, 1},
  {"fileChmod", bFileChmod, 2, 1}, {"fileFsync", bFileFsync, 1, 1}, {"fileReadlink", bFileReadlink, 1, 1}, {"fileLstat", bFileLstat, 1, 1}, {"pathSymlink", bPathSymlink, 2, 1}, {"fileUtime", bFileUtime, 2, 1},
  {"bytesAlloc", bBytesAlloc, 1, 0}, {"bytesGet", bBytesGet, 2, 0}, {"bytesSet", bBytesSet, 3, 1},
  {"bytesGetFloat64", bBytesGetF64, 2, 0}, {"bytesSetFloat64", bBytesSetF64, 3, 1}, {"stringToBytes", bStringToBytes, 1, 0},
};

const int nCoreBuiltins = (int)(sizeof coreBuiltins / sizeof coreBuiltins[0]);

/* lookups walk builtinTables: vm.c's chain in asl-host, abi.c's core-only chain in a native binary */
const Builtin *builtinLookup(const char *name) {
  for (int k = 0; k < nBuiltinTables; k++) for (int i = 0; i < *builtinTables[k].n; i++) if (!strcmp(builtinTables[k].t[i].name, name)) return &builtinTables[k].t[i];
  return NULL;
}
const Builtin *builtinAt(int i) {
  for (int k = 0; k < nBuiltinTables; k++) { if (i < *builtinTables[k].n) return &builtinTables[k].t[i]; i -= *builtinTables[k].n; }
  return NULL;
}
int builtinIndex(const Builtin *b) {
  for (int k = 0, base = 0; k < nBuiltinTables; base += *builtinTables[k].n, k++) if (b >= builtinTables[k].t && b < builtinTables[k].t + *builtinTables[k].n) return base + (int)(b - builtinTables[k].t);
  return -1;
}

/* a native call of a builtin of table t by name (asl_rt_builtin_<table>, emitted by asl-target-llvm for the tables a
   native binary links only when it calls one): the interpreter's arity check, operands copied off the caller's array */
Val builtinCallIn(const Builtin *t, int n, const char *name, int64_t argc, Val *argv) {
  if (argc < 0 || argc > MAX_BUILTIN_ARGS) aslError("ERR_LIMIT", "%s: count %lld outside 0..%d", name, (long long)argc, MAX_BUILTIN_ARGS);
  for (int i = 0; i < n; i++) {
    if (strcmp(t[i].name, name)) continue;
    if (t[i].arity >= 0 && t[i].arity != (int)argc) aslError("ERR_ARITY", "%s expects %d argument(s), got %d", name, t[i].arity, (int)argc);
    Val a[MAX_BUILTIN_ARGS];
    for (int64_t k = 0; k < argc; k++) a[k] = argv[k];
    return t[i].fn(a, (int)argc);
  }
  aslError("ERR_UNKNOWN_SYMBOL", "%s", name);
}
