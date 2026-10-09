#include "value.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void want(Val v, Tag t, const char *who) {
  if (v.tag != t) aslError("ERR_TYPE", "%s expects %s, got %s", who, tagName(t), tagName(v.tag));
}

static Val reverseList(Val xs) {
  Val out = VNIL;
  asl_gc_root_push(&xs); asl_gc_root_push(&out);
  for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) out = mkCons(((Cons *)x)->car, out);
  asl_gc_root_pop(2);
  return out;
}

/* ---- Unit CC5: parMap and parFold via fork + pipe with sequential fallback (D151) ---- */

static int hostCpuCount(void) {
#if defined(_SC_NPROCESSORS_ONLN)
  long c = sysconf(_SC_NPROCESSORS_ONLN);
  if (c >= 1) return (int)c;
#endif
  return 4;
}

enum {
  SER_UNIT = 1,
  SER_BOOL = 2,
  SER_INT = 3,
  SER_FLOAT = 4,
  SER_KW = 5,
  SER_STR = 6,
  SER_BYTES = 7,
  SER_LIST = 8,
  SER_CTOR = 9,
  SER_REC = 10,
  SER_F64ARR = 11,
  SER_I64ARR = 12,
  SER_I8ARR = 13
};

typedef struct {
  uint8_t *data;
  size_t len, cap;
  int err;
} SerBuf;

/* A worker frame is deliberately bounded; child output is untrusted input. */
#define SER_MAX_BYTES ((size_t)64 * 1024 * 1024)

static int checkedAddSize(size_t a, size_t b, size_t *out) {
  if (b > SIZE_MAX - a) return 0;
  *out = a + b;
  return 1;
}

static int checkedMulSize(size_t a, size_t b, size_t *out) {
  if (a && b > SIZE_MAX / a) return 0;
  *out = a * b;
  return 1;
}

/* ASL_PAR_FORCE_FALLBACK=1 is a documented test hook: it makes the normal
 * fork-failure fallback run, without changing callback execution semantics. */
static int parallelFallbackRequested(void) {
  static int cached = -1;
  if (cached < 0) {
    const char *value = getenv("ASL_PAR_FORCE_FALLBACK");
    cached = value && strcmp(value, "1") == 0;
  }
  return cached;
}

static pid_t parallelFork(void) {
  if (parallelFallbackRequested()) { errno = EAGAIN; return (pid_t)-1; }
  return fork();
}

static void serWrite(SerBuf *b, const void *p, size_t n) {
  if (b->err) return;
  size_t needed;
  if (!checkedAddSize(b->len, n, &needed) || needed > SER_MAX_BYTES) { b->err = 3; return; }
  if (needed > b->cap) {
    size_t nc = b->cap ? b->cap : 256;
    while (nc < needed) {
      if (nc > SIZE_MAX / 2) { nc = needed; break; }
      nc *= 2;
    }
    if (nc > SER_MAX_BYTES) nc = SER_MAX_BYTES;
    if (nc < needed) { b->err = 3; return; }
    uint8_t *nd = realloc(b->data, nc);
    if (!nd) { b->err = 1; return; }
    b->data = nd;
    b->cap = nc;
  }
  memcpy(b->data + b->len, p, n);
  b->len += n;
}

static void serU8(SerBuf *b, uint8_t u) { serWrite(b, &u, 1); }
static void serU32(SerBuf *b, uint32_t u) { serWrite(b, &u, 4); }
static void serU64(SerBuf *b, uint64_t u) { serWrite(b, &u, 8); }
static void serI64(SerBuf *b, int64_t i) { serWrite(b, &i, 8); }
static void serF64(SerBuf *b, double d) { serWrite(b, &d, 8); }

static void serVal(SerBuf *b, Val v, int depth) {
  if (b->err) return;
  if (depth > 10000) { b->err = 2; return; }
  switch (v.tag) {
    case T_UNIT:
      serU8(b, SER_UNIT);
      break;
    case T_BOOL:
      serU8(b, SER_BOOL);
      serU8(b, v.u.i ? 1 : 0);
      break;
    case T_INT:
      serU8(b, SER_INT);
      serI64(b, v.u.i);
      break;
    case T_FLOAT:
      serU8(b, SER_FLOAT);
      serF64(b, v.u.f);
      break;
    case T_KW: {
      serU8(b, SER_KW);
      const char *s = symName((int)v.aux);
      if (strlen(s) > UINT32_MAX) { b->err = 3; return; }
      uint32_t len = (uint32_t)strlen(s);
      serU32(b, len);
      serWrite(b, s, len);
      break;
    }
    case T_STR: {
      serU8(b, SER_STR);
      Str *s = (Str *)v.u.o;
      serU64(b, (uint64_t)s->len);
      serWrite(b, s->s, s->len);
      break;
    }
    case T_BYTES: {
      serU8(b, SER_BYTES);
      Arr *a = (Arr *)v.u.o;
      serU64(b, (uint64_t)a->len);
      if (a->len && a->data) serWrite(b, a->data, a->len);
      break;
    }
    case T_LIST: {
      serU8(b, SER_LIST);
      uint64_t count = 0;
      for (Obj *x = v.u.o; x; x = ((Cons *)x)->cdr.u.o) {
        if (count == UINT64_MAX) { b->err = 3; return; }
        count++;
      }
      serU64(b, count);
      for (Obj *x = v.u.o; x; x = ((Cons *)x)->cdr.u.o) {
        serVal(b, ((Cons *)x)->car, depth + 1);
        if (b->err) return;
      }
      break;
    }
    case T_CTOR: {
      serU8(b, SER_CTOR);
      Ctor *c = (Ctor *)v.u.o;
      const char *name = symName(c->ctor);
      if (strlen(name) > UINT32_MAX) { b->err = 3; return; }
      uint32_t len = (uint32_t)strlen(name);
      serU32(b, len);
      serWrite(b, name, len);
      serU32(b, (uint32_t)c->n);
      for (int i = 0; i < c->n; i++) {
        serVal(b, c->f[i], depth + 1);
        if (b->err) return;
      }
      break;
    }
    case T_REC: {
      serU8(b, SER_REC);
      Rec *r = (Rec *)v.u.o;
      if (r->schema < 0) {
        serU32(b, 0);
      } else {
        const char *schema = symName(r->schema);
        if (strlen(schema) > UINT32_MAX) { b->err = 3; return; }
        uint32_t slen = (uint32_t)strlen(schema);
        serU32(b, slen);
        serWrite(b, schema, slen);
      }
      serU32(b, (uint32_t)r->n);
      for (int i = 0; i < r->n; i++) {
        const char *kname = symName(r->keys[i]);
        if (strlen(kname) > UINT32_MAX) { b->err = 3; return; }
        uint32_t klen = (uint32_t)strlen(kname);
        serU32(b, klen);
        serWrite(b, kname, klen);
        serVal(b, r->v[i], depth + 1);
        if (b->err) return;
      }
      break;
    }
    case T_F64ARR:
    case T_I64ARR:
    case T_I8ARR: {
      uint8_t tag = v.tag == T_F64ARR ? SER_F64ARR : v.tag == T_I64ARR ? SER_I64ARR : SER_I8ARR;
      serU8(b, tag);
      Arr *a = (Arr *)v.u.o;
      serU64(b, (uint64_t)a->len);
      size_t byteLen;
      if (!checkedMulSize(a->len, a->elem, &byteLen)) { b->err = 3; return; }
      if (byteLen && a->data) serWrite(b, a->data, byteLen);
      break;
    }
    default:
      b->err = 1;
      return;
  }
}

typedef struct {
  const uint8_t *data;
  size_t pos, len;
  int err;
} DeserCtx;

static int deserRead(DeserCtx *d, void *out, size_t n) {
  if (d->err || d->pos > d->len || n > d->len - d->pos) { d->err = 1; return 0; }
  memcpy(out, d->data + d->pos, n);
  d->pos += n;
  return 1;
}
static int deserHas(DeserCtx *d, uint64_t n) {
  if (d->pos > d->len || n > SIZE_MAX || n > SER_MAX_BYTES || n > d->len - d->pos) {
    d->err = 1;
    return 0;
  }
  return 1;
}
static uint8_t deserU8(DeserCtx *d) { uint8_t u = 0; deserRead(d, &u, 1); return u; }
static uint32_t deserU32(DeserCtx *d) { uint32_t u = 0; deserRead(d, &u, 4); return u; }
static uint64_t deserU64(DeserCtx *d) { uint64_t u = 0; deserRead(d, &u, 8); return u; }
static int64_t deserI64(DeserCtx *d) { int64_t i = 0; deserRead(d, &i, 8); return i; }
static double deserF64(DeserCtx *d) { double f = 0.0; deserRead(d, &f, 8); return f; }

typedef struct KeyEntry {
  int *keys;
  int n;
  struct KeyEntry *next;
} KeyEntry;

static KeyEntry *keyEntryHead = NULL;

static int *internKeys(const int *keys, int n) {
  if (n <= 0) {
    static int empty[1];
    return empty;
  }
  for (KeyEntry *e = keyEntryHead; e; e = e->next) {
    if (e->n == n && memcmp(e->keys, keys, sizeof(int) * (size_t)n) == 0) {
      return e->keys;
    }
  }
  KeyEntry *e = malloc(sizeof(KeyEntry));
  if (!e) return NULL;
  e->keys = malloc(sizeof(int) * (size_t)n);
  if (!e->keys) { free(e); return NULL; }
  memcpy(e->keys, keys, sizeof(int) * (size_t)n);
  e->n = n;
  e->next = keyEntryHead;
  keyEntryHead = e;
  return e->keys;
}

static Val deserVal(DeserCtx *d, int depth) {
  if (d->err) return VUNIT;
  if (depth > 10000) { d->err = 2; return VUNIT; }
  uint8_t tag = deserU8(d);
  if (d->err) return VUNIT;
  switch (tag) {
    case SER_UNIT: return VUNIT;
    case SER_BOOL: {
      uint8_t b = deserU8(d);
      return vbool(b != 0);
    }
    case SER_INT: return vint(deserI64(d));
    case SER_FLOAT: return vfloat(deserF64(d));
    case SER_KW: {
      uint32_t len = deserU32(d);
      if (d->err || !deserHas(d, len)) return VUNIT;
      int id = intern((const char *)(d->data + d->pos), len);
      d->pos += len;
      return vkw(id);
    }
    case SER_STR: {
      uint64_t len = deserU64(d);
      if (d->err || !deserHas(d, len)) return VUNIT;
      Val v = mkStr((const char *)(d->data + d->pos), (size_t)len);
      d->pos += len;
      return v;
    }
    case SER_BYTES: {
      uint64_t len = deserU64(d);
      if (d->err || !deserHas(d, len)) return VUNIT;
      Val v = mkBytes(d->data + d->pos, (size_t)len);
      d->pos += len;
      return v;
    }
    case SER_LIST: {
      uint64_t count = deserU64(d);
      if (d->err) return VUNIT;
      if (count > d->len - d->pos || count > SER_MAX_BYTES) { d->err = 1; return VUNIT; }
      if (count == 0) return VNIL;
      Val rev = VNIL;
      asl_gc_root_push(&rev);
      for (uint64_t i = 0; i < count; i++) {
        Val elem = deserVal(d, depth + 1);
        if (d->err) { asl_gc_root_pop(1); return VUNIT; }
        rev = mkCons(elem, rev);
      }
      Val out = VNIL;
      asl_gc_root_push(&out);
      for (Obj *x = rev.u.o; x; x = ((Cons *)x)->cdr.u.o) {
        out = mkCons(((Cons *)x)->car, out);
      }
      asl_gc_root_pop(2);
      return out;
    }
    case SER_CTOR: {
      uint32_t len = deserU32(d);
      if (d->err || !deserHas(d, len)) return VUNIT;
      int ctorSym = intern((const char *)(d->data + d->pos), len);
      d->pos += len;
      uint32_t n = deserU32(d);
      if (d->err) return VUNIT;
      if (n > INT_MAX || n > SER_MAX_BYTES / sizeof(Val)) { d->err = 1; return VUNIT; }
      if (n > d->len - d->pos || n > SER_MAX_BYTES) { d->err = 1; return VUNIT; }
      Val cv = mkCtor(ctorSym, (int)n);
      asl_gc_root_push(&cv);
      for (uint32_t i = 0; i < n; i++) {
        Val f = deserVal(d, depth + 1);
        if (d->err) { asl_gc_root_pop(1); return VUNIT; }
        Ctor *c = (Ctor *)cv.u.o;
        c->f[i] = f;
      }
      asl_gc_root_pop(1);
      return cv;
    }
    case SER_REC: {
      uint32_t slen = deserU32(d);
      if (d->err) return VUNIT;
      int schemaSym = -1;
      if (slen > 0) {
        if (!deserHas(d, slen)) return VUNIT;
        schemaSym = intern((const char *)(d->data + d->pos), slen);
        d->pos += slen;
      }
      uint32_t n = deserU32(d);
      if (d->err) return VUNIT;
      if (n > SER_MAX_BYTES / sizeof(Val) || n > (d->len - d->pos) / 5 || n > (uint32_t)INT_MAX) { d->err = 1; return VUNIT; }
      size_t valuesBytes, keysBytes, recordBytes;
      if (!checkedMulSize((size_t)n, sizeof(Val), &valuesBytes) ||
          !checkedAddSize(sizeof(Rec), valuesBytes, &recordBytes) ||
          !checkedMulSize((size_t)n, sizeof(int), &keysBytes)) { d->err = 1; return VUNIT; }
      int *kbuf = n ? malloc(keysBytes) : NULL;
      if (n && !kbuf) { d->err = 1; return VUNIT; }
      Rec *r = asl_alloc(O_REC, recordBytes);
      Val rv = vobj(T_REC, r);
      asl_gc_root_push(&rv);
      r->schema = schemaSym;
      r->n = (int)n;
      r->keys = NULL;
      for (uint32_t i = 0; i < n; i++) {
        uint32_t klen = deserU32(d);
        if (d->err || !deserHas(d, klen)) { free(kbuf); asl_gc_root_pop(1); return VUNIT; }
        int ksym = intern((const char *)(d->data + d->pos), klen);
        d->pos += klen;
        kbuf[i] = ksym;
        Val f = deserVal(d, depth + 1);
        if (d->err) { free(kbuf); asl_gc_root_pop(1); return VUNIT; }
        r = (Rec *)rv.u.o;
        r->v[i] = f;
      }
      r = (Rec *)rv.u.o;
      r->keys = internKeys(kbuf, (int)n);
      free(kbuf);
      if (!r->keys) { d->err = 1; asl_gc_root_pop(1); return VUNIT; }
      asl_gc_root_pop(1);
      return rv;
    }
    case SER_F64ARR:
    case SER_I64ARR:
    case SER_I8ARR: {
      uint64_t len = deserU64(d);
      size_t elem = tag == SER_F64ARR ? 8 : tag == SER_I64ARR ? 8 : 1;
      size_t blen;
      if (d->err || len > SIZE_MAX || !checkedMulSize((size_t)len, elem, &blen) || blen > SER_MAX_BYTES) { d->err = 1; return VUNIT; }
      if (!deserHas(d, blen)) return VUNIT;
      Val v = mkArray(tag == SER_F64ARR ? T_F64ARR : tag == SER_I64ARR ? T_I64ARR : T_I8ARR, (size_t)len);
      Arr *a = (Arr *)v.u.o;
      if (blen && a->data) memcpy(a->data, d->data + d->pos, blen);
      d->pos += blen;
      return v;
    }
    default:
      d->err = 1;
      return VUNIT;
  }
}

static int writeAll(int fd, const void *buf, size_t len) {
  const char *p = (const char *)buf;
  while (len > 0) {
    ssize_t w = write(fd, p, len);
    if (w < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    p += w;
    len -= (size_t)w;
  }
  return 0;
}

/* (:m :why "S62407.1: a failed element fails the call naming its index, the same ERR_WORKER_TRAP the worker path raises, so wasm and Windows (always sequential) report what fork does" :ref TASK-624-07) */
static Val parMapSequential(Val fn, Val xs) {
  Val out = VNIL, cur = xs;
  volatile int64_t idx = 0;
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  asl_gc_root_push(&fn); asl_gc_root_push(&out); asl_gc_root_push(&cur);
  if (setjmp(jb)) {
    char cause[sizeof aslErrorMsg];
    snprintf(cause, sizeof cause, "%s", aslErrorMsg);
    aslErrorHandlerSet(previous);
    asl_gc_root_pop(3);
    aslError("ERR_WORKER_TRAP", "parMap element %lld: %s", (long long)idx, cause);
  }
  aslErrorHandlerSet(&jb);
  for (Obj *x = cur.u.o; x; x = ((Cons *)x)->cdr.u.o, idx++) {
    Val v = aslCall(fn, 1, &((Cons *)x)->car);
    out = mkCons(v, out);
  }
  aslErrorHandlerSet(previous);
  Val r = reverseList(out);
  asl_gc_root_pop(3);
  return r;
}

static Val bParMap(Val *a, int n) {
  if (n < 2) aslError("ERR_ARITY", "parMap expects at least 2 arguments, got %d", n);
  Val fn, xs;
  int64_t nSlots = hostCpuCount();
  if (n == 2) {
    fn = a[0]; xs = a[1];
  } else if (n == 3) {
    if (a[0].tag == T_INT) {
      nSlots = a[0].u.i; fn = a[1]; xs = a[2];
    } else if (a[2].tag == T_INT) {
      fn = a[0]; xs = a[1]; nSlots = a[2].u.i;
    } else {
      aslError("ERR_TYPE", "parMap expects (parMap fn list [slots]) or (parMap slots fn list)");
    }
  } else {
    aslError("ERR_ARITY", "parMap expects 2 or 3 arguments, got %d", n);
  }
  if (nSlots <= 0) aslError("ERR_ARG", "parMap slots must be positive, got %lld", (long long)nSlots);
  want(xs, T_LIST, "parMap");

  int64_t M = 0;
  for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) M++;
  if (M == 0) return VNIL;
  int64_t K = nSlots > M ? M : nSlots;
  if (K > 256) K = 256;

#if defined(__wasm__) || defined(_WIN32)
  K = 1;
#endif

  if (K <= 1) return parMapSequential(fn, xs);

  Val *items = malloc(sizeof(Val) * (size_t)M);
  if (!items) aslError("ERR_OOM", "parMap items");
  int64_t idx = 0;
  for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) items[idx++] = ((Cons *)x)->car;

  int (*pipes)[2] = malloc(sizeof(int[2]) * (size_t)K);
  pid_t *pids = malloc(sizeof(pid_t) * (size_t)K);
  if (!pipes || !pids) {
    free(items); free(pipes); free(pids);
    aslError("ERR_OOM", "parMap process tables");
  }

  for (int64_t k = 0; k < K; k++) {
    if (pipe(pipes[k]) != 0) {
      for (int64_t j = 0; j < k; j++) {
        kill(pids[j], SIGKILL);
        close(pipes[j][0]);
        int st; while (waitpid(pids[j], &st, 0) < 0 && errno == EINTR) {}
      }
      free(pipes); free(pids); free(items);
      return parMapSequential(fn, xs);
    }

    int64_t start_k = (k * M) / K;
    int64_t end_k = ((k + 1) * M) / K;
    int64_t count_k = end_k - start_k;

    fflush(NULL);
    pid_t pid = parallelFork();
    if (pid < 0) {
      close(pipes[k][0]); close(pipes[k][1]);
      for (int64_t j = 0; j < k; j++) {
        kill(pids[j], SIGKILL);
        close(pipes[j][0]);
        int st; while (waitpid(pids[j], &st, 0) < 0 && errno == EINTR) {}
      }
      free(pipes); free(pids); free(items);
      return parMapSequential(fn, xs);
    }

    if (pid == 0) {
      close(pipes[k][0]);
      for (int64_t j = 0; j < k; j++) close(pipes[j][0]);
      signal(SIGPIPE, SIG_DFL);
      signal(SIGINT, SIG_DFL);
      signal(SIGTERM, SIG_DFL);

      jmp_buf jb;
      volatile int64_t failIdx = start_k;
      aslErrorHandlerSet(&jb);
      if (setjmp(jb)) {
        char pkt[1024];
        int written = snprintf(pkt + 5, sizeof(pkt) - 5, "parMap element %lld: %s", (long long)failIdx, aslErrorMsg);
        uint32_t msgLen = written < 0 ? 0 : (uint32_t)written;
        if (msgLen > sizeof(pkt) - 6) msgLen = (uint32_t)(sizeof(pkt) - 6);
        pkt[0] = 1;
        memcpy(pkt + 1, &msgLen, 4);
        writeAll(pipes[k][1], pkt, 5 + msgLen);
        close(pipes[k][1]);
        fflush(stdout);
        fflush(stderr);
        _exit(1);
      }

      SerBuf sb = {0};
      Val curItem = VUNIT;
      asl_gc_root_push(&fn);
      asl_gc_root_push(&curItem);
      for (int64_t i = start_k; i < end_k; i++) {
        failIdx = i;
        curItem = items[i];
        Val res = aslCall(fn, 1, &curItem);
        serVal(&sb, res, 0);
        if (sb.err == 3) {
          aslError("ERR_SERIALIZE_SIZE", "parMap worker result exceeds serialization size limit");
        }
        if (sb.err) {
          aslError("ERR_NOT_SERIALIZABLE", "cannot serialize parMap result across worker process");
        }
      }
      asl_gc_root_pop(2);

      uint8_t status = 0;
      writeAll(pipes[k][1], &status, 1);
      uint64_t ck = (uint64_t)count_k;
      writeAll(pipes[k][1], &ck, 8);
      if (sb.len) writeAll(pipes[k][1], sb.data, sb.len);
      free(sb.data);
      close(pipes[k][1]);
      fflush(stdout);
      fflush(stderr);
      _exit(0);
    }

    pids[k] = pid;
    close(pipes[k][1]);
  }

  struct pollfd *pfds = malloc(sizeof(struct pollfd) * (size_t)K);
  SerBuf *inbufs = calloc((size_t)K, sizeof(SerBuf));
  if (!pfds || !inbufs) {
    for (int64_t k = 0; k < K; k++) {
      kill(pids[k], SIGKILL);
      close(pipes[k][0]);
      int st; while (waitpid(pids[k], &st, 0) < 0 && errno == EINTR) {}
    }
    free(items); free(pipes); free(pids); free(pfds); free(inbufs);
    aslError("ERR_OOM", "parMap poll buffers");
  }

  int openPipes = (int)K;
  int failedWorker = -1;
  int oversizedWorker = -1;
  for (int64_t k = 0; k < K; k++) {
    pfds[k].fd = pipes[k][0];
    pfds[k].events = POLLIN;
    pfds[k].revents = 0;
  }

  while (openPipes > 0) {
    int pr = poll(pfds, (nfds_t)K, -1);
    if (pr < 0) {
      if (errno == EINTR) continue;
      break;
    }
    for (int64_t k = 0; k < K; k++) {
      if (pfds[k].fd < 0) continue;
      if (pfds[k].revents & (POLLIN | POLLHUP | POLLERR)) {
        char buf[8192];
        ssize_t r = read(pfds[k].fd, buf, sizeof(buf));
        if (r > 0) {
          serWrite(&inbufs[k], buf, (size_t)r);
          if (inbufs[k].err) {
            if (oversizedWorker < 0) oversizedWorker = (int)k;
            for (int64_t j = 0; j < K; j++) if (j != k) kill(pids[j], SIGTERM);
          }
          if (inbufs[k].len >= 5 && inbufs[k].data[0] == 1) {
            if (failedWorker < 0 || k < failedWorker) failedWorker = (int)k;
            for (int64_t j = failedWorker + 1; j < K; j++) kill(pids[j], SIGTERM);
          }
        } else if (r == 0 || (r < 0 && errno != EINTR && errno != EAGAIN)) {
          close(pfds[k].fd);
          pfds[k].fd = -1;
          openPipes--;
        }
      }
    }
  }

  for (int64_t k = 0; k < K; k++) {
    if (inbufs[k].len >= 5 && inbufs[k].data[0] == 1) {
      if (failedWorker < 0 || k < failedWorker) failedWorker = (int)k;
    }
  }

  int otherTrapped = -1;
  int otherSig = 0, otherExit = 0;
  for (int64_t k = 0; k < K; k++) {
    if (pfds[k].fd >= 0) close(pfds[k].fd);
    int st = 0;
    pid_t w;
    while ((w = waitpid(pids[k], &st, 0)) < 0 && errno == EINTR) {}
    (void)w;
    if (failedWorker < 0) {
      if (WIFSIGNALED(st) && otherTrapped < 0) {
        otherTrapped = (int)k;
        otherSig = WTERMSIG(st);
      } else if (WIFEXITED(st) && WEXITSTATUS(st) != 0 && otherTrapped < 0) {
        otherTrapped = (int)k;
        otherExit = WEXITSTATUS(st);
      }
    }
  }

  int workerTrapped = -1;
  char trapMsg[1024] = {0};
  if (failedWorker >= 0) {
    workerTrapped = failedWorker;
    uint32_t mlen = 0;
    memcpy(&mlen, inbufs[failedWorker].data + 1, 4);
    if (mlen > sizeof(trapMsg) - 1) mlen = sizeof(trapMsg) - 1;
    if (mlen && inbufs[failedWorker].len >= 5 && mlen <= inbufs[failedWorker].len - 5) {
      memcpy(trapMsg, inbufs[failedWorker].data + 5, mlen);
      trapMsg[mlen] = 0;
    } else {
      snprintf(trapMsg, sizeof(trapMsg), "worker %d reported error", failedWorker);
    }
  } else if (otherTrapped >= 0) {
    workerTrapped = otherTrapped;
    if (otherSig) snprintf(trapMsg, sizeof(trapMsg), "worker %d killed by signal %d", otherTrapped, otherSig);
    else snprintf(trapMsg, sizeof(trapMsg), "worker %d exited with code %d", otherTrapped, otherExit);
  }

  if (oversizedWorker >= 0) {
    for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
    free(inbufs); free(pfds); free(pipes); free(pids); free(items);
    aslError("ERR_SERIALIZE_SIZE", "worker %d response exceeds serialization size limit", oversizedWorker);
  }

  if (workerTrapped >= 0) {
    for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
    free(inbufs); free(pfds); free(pipes); free(pids); free(items);
    aslError("ERR_WORKER_TRAP", "%s", trapMsg[0] ? trapMsg : "worker trapped");
  }

  Val *chunkLists = malloc(sizeof(Val) * (size_t)K);
  if (!chunkLists) {
    for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
    free(inbufs); free(pfds); free(pipes); free(pids); free(items);
    aslError("ERR_OOM", "parMap chunk lists");
  }

  for (int64_t k = 0; k < K; k++) {
    chunkLists[k] = VNIL;
    asl_gc_root_push(&chunkLists[k]);
  }

  for (int64_t k = 0; k < K; k++) {
    int64_t start_k = (k * M) / K;
    int64_t end_k = ((k + 1) * M) / K;
    int64_t count_k = end_k - start_k;

    DeserCtx d = {inbufs[k].data, 0, inbufs[k].len, 0};
    uint8_t st = deserU8(&d);
    uint64_t ck = deserU64(&d);
    if (st != 0 || ck != (uint64_t)count_k || d.err) {
      asl_gc_root_pop((int)K);
      for (int64_t j = 0; j < K; j++) free(inbufs[j].data);
      free(inbufs); free(pfds); free(pipes); free(pids); free(items); free(chunkLists);
      aslError("ERR_WORKER_TRAP", "worker %d sent corrupted data", (int)k);
    }
    for (int64_t i = 0; i < count_k; i++) {
      Val item = deserVal(&d, 0);
      if (d.err) {
        asl_gc_root_pop((int)K);
        for (int64_t j = 0; j < K; j++) free(inbufs[j].data);
        free(inbufs); free(pfds); free(pipes); free(pids); free(items); free(chunkLists);
        aslError("ERR_WORKER_TRAP", "deserialization error on worker %d item %lld", (int)k, (long long)i);
      }
      asl_gc_root_push(&item);
      chunkLists[k] = mkCons(item, chunkLists[k]);
      asl_gc_root_pop(1);
    }
    chunkLists[k] = reverseList(chunkLists[k]);
  }

  Val out = VNIL;
  asl_gc_root_push(&out);
  for (int64_t k = K - 1; k >= 0; k--) {
    Val rev = reverseList(chunkLists[k]);
    asl_gc_root_push(&rev);
    for (Obj *x = rev.u.o; x; x = ((Cons *)x)->cdr.u.o) {
      Val elem = ((Cons *)x)->car;
      asl_gc_root_push(&elem);
      out = mkCons(elem, out);
      asl_gc_root_pop(1);
    }
    asl_gc_root_pop(1);
  }
  asl_gc_root_pop(1 + (int)K);

  for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
  free(inbufs); free(pfds); free(pipes); free(pids); free(items); free(chunkLists);
  return out;
}

static Val bParFold(Val *a, int n) {
  if (n < 4 || n > 5) aslError("ERR_ARITY", "parFold expects 4 or 5 arguments, got %d", n);
  Val step = a[0], combine = a[1], init = a[2], xs = a[3];
  int64_t nSlots = hostCpuCount();
  if (n == 5) {
    want(a[4], T_INT, "parFold slots");
    nSlots = a[4].u.i;
  }
  if (nSlots <= 0) aslError("ERR_ARG", "parFold slots must be positive, got %lld", (long long)nSlots);
  want(xs, T_LIST, "parFold");

  int64_t M = 0;
  for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) M++;
  if (M == 0) return init;
  int64_t K = nSlots > M ? M : nSlots;
  if (K > 256) K = 256;

#if defined(__wasm__) || defined(_WIN32)
  K = 1;
#endif

  if (K <= 1) {
    Val acc = init;
    asl_gc_root_push(&step); asl_gc_root_push(&acc);
    for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) {
      Val args[2] = {acc, ((Cons *)x)->car};
      acc = aslCall(step, 2, args);
    }
    asl_gc_root_pop(2);
    return acc;
  }

  Val *items = malloc(sizeof(Val) * (size_t)M);
  if (!items) aslError("ERR_OOM", "parFold items");
  int64_t idx = 0;
  for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) items[idx++] = ((Cons *)x)->car;

  int (*pipes)[2] = malloc(sizeof(int[2]) * (size_t)K);
  pid_t *pids = malloc(sizeof(pid_t) * (size_t)K);
  if (!pipes || !pids) {
    free(items); free(pipes); free(pids);
    aslError("ERR_OOM", "parFold process tables");
  }

  for (int64_t k = 0; k < K; k++) {
    if (pipe(pipes[k]) != 0) {
      for (int64_t j = 0; j < k; j++) {
        kill(pids[j], SIGKILL);
        close(pipes[j][0]);
        int st; while (waitpid(pids[j], &st, 0) < 0 && errno == EINTR) {}
      }
      free(pipes); free(pids);
      Val acc = init;
      asl_gc_root_push(&step); asl_gc_root_push(&acc);
      for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) {
        Val args[2] = {acc, ((Cons *)x)->car};
        acc = aslCall(step, 2, args);
      }
      asl_gc_root_pop(2);
      free(items);
      return acc;
    }

    int64_t start_k = (k * M) / K;
    int64_t end_k = ((k + 1) * M) / K;

    fflush(NULL);
    pid_t pid = parallelFork();
    if (pid < 0) {
      close(pipes[k][0]); close(pipes[k][1]);
      for (int64_t j = 0; j < k; j++) {
        kill(pids[j], SIGKILL);
        close(pipes[j][0]);
        int st; while (waitpid(pids[j], &st, 0) < 0 && errno == EINTR) {}
      }
      free(pipes); free(pids);
      Val acc = init;
      asl_gc_root_push(&step); asl_gc_root_push(&acc);
      for (Obj *x = xs.u.o; x; x = ((Cons *)x)->cdr.u.o) {
        Val args[2] = {acc, ((Cons *)x)->car};
        acc = aslCall(step, 2, args);
      }
      asl_gc_root_pop(2);
      free(items);
      return acc;
    }

    if (pid == 0) {
      close(pipes[k][0]);
      for (int64_t j = 0; j < k; j++) close(pipes[j][0]);
      signal(SIGPIPE, SIG_DFL);
      signal(SIGINT, SIG_DFL);
      signal(SIGTERM, SIG_DFL);

      jmp_buf jb;
      aslErrorHandlerSet(&jb);
      if (setjmp(jb)) {
        uint32_t msgLen = (uint32_t)strlen(aslErrorMsg);
        char pkt[1024];
        if (msgLen > sizeof(pkt) - 5) msgLen = (uint32_t)(sizeof(pkt) - 5);
        pkt[0] = 1;
        memcpy(pkt + 1, &msgLen, 4);
        if (msgLen) memcpy(pkt + 5, aslErrorMsg, msgLen);
        writeAll(pipes[k][1], pkt, 5 + msgLen);
        close(pipes[k][1]);
        fflush(stdout);
        fflush(stderr);
        _exit(1);
      }

      Val acc = init;
      Val curItem = VUNIT;
      asl_gc_root_push(&step);
      asl_gc_root_push(&acc);
      asl_gc_root_push(&curItem);

      for (int64_t i = start_k; i < end_k; i++) {
        curItem = items[i];
        Val callArgs[2] = {acc, curItem};
        acc = aslCall(step, 2, callArgs);
      }
      asl_gc_root_pop(3);

      SerBuf sb = {0};
      serVal(&sb, acc, 0);
      if (sb.err == 3) {
        aslError("ERR_SERIALIZE_SIZE", "parFold worker result exceeds serialization size limit");
      }
      if (sb.err) {
        aslError("ERR_NOT_SERIALIZABLE", "cannot serialize parFold result across worker process");
      }

      uint8_t status = 0;
      writeAll(pipes[k][1], &status, 1);
      if (sb.len) writeAll(pipes[k][1], sb.data, sb.len);
      free(sb.data);
      close(pipes[k][1]);
      fflush(stdout);
      fflush(stderr);
      _exit(0);
    }

    pids[k] = pid;
    close(pipes[k][1]);
  }

  struct pollfd *pfds = malloc(sizeof(struct pollfd) * (size_t)K);
  SerBuf *inbufs = calloc((size_t)K, sizeof(SerBuf));
  if (!pfds || !inbufs) {
    for (int64_t k = 0; k < K; k++) {
      kill(pids[k], SIGKILL);
      close(pipes[k][0]);
      int st; while (waitpid(pids[k], &st, 0) < 0 && errno == EINTR) {}
    }
    free(items); free(pipes); free(pids); free(pfds); free(inbufs);
    aslError("ERR_OOM", "parFold poll buffers");
  }

  int openPipes = (int)K;
  int failedWorker = -1;
  int oversizedWorker = -1;
  for (int64_t k = 0; k < K; k++) {
    pfds[k].fd = pipes[k][0];
    pfds[k].events = POLLIN;
    pfds[k].revents = 0;
  }

  while (openPipes > 0) {
    int pr = poll(pfds, (nfds_t)K, -1);
    if (pr < 0) {
      if (errno == EINTR) continue;
      break;
    }
    for (int64_t k = 0; k < K; k++) {
      if (pfds[k].fd < 0) continue;
      if (pfds[k].revents & (POLLIN | POLLHUP | POLLERR)) {
        char buf[8192];
        ssize_t r = read(pfds[k].fd, buf, sizeof(buf));
        if (r > 0) {
          serWrite(&inbufs[k], buf, (size_t)r);
          if (inbufs[k].err) {
            if (oversizedWorker < 0) oversizedWorker = (int)k;
            for (int64_t j = 0; j < K; j++) if (j != k) kill(pids[j], SIGTERM);
          }
          if (inbufs[k].len >= 5 && inbufs[k].data[0] == 1) {
            if (failedWorker < 0) failedWorker = (int)k;
            for (int64_t j = 0; j < K; j++) if (j != k) kill(pids[j], SIGTERM);
          }
        } else if (r == 0 || (r < 0 && errno != EINTR && errno != EAGAIN)) {
          close(pfds[k].fd);
          pfds[k].fd = -1;
          openPipes--;
        }
      }
    }
  }

  if (failedWorker < 0) {
    for (int64_t k = 0; k < K; k++) {
      if (inbufs[k].len >= 5 && inbufs[k].data[0] == 1) {
        failedWorker = (int)k;
        break;
      }
    }
  }

  int otherTrapped = -1;
  int otherSig = 0, otherExit = 0;
  for (int64_t k = 0; k < K; k++) {
    if (pfds[k].fd >= 0) close(pfds[k].fd);
    int st = 0;
    pid_t w;
    while ((w = waitpid(pids[k], &st, 0)) < 0 && errno == EINTR) {}
    (void)w;
    if (failedWorker < 0) {
      if (WIFSIGNALED(st) && otherTrapped < 0) {
        otherTrapped = (int)k;
        otherSig = WTERMSIG(st);
      } else if (WIFEXITED(st) && WEXITSTATUS(st) != 0 && otherTrapped < 0) {
        otherTrapped = (int)k;
        otherExit = WEXITSTATUS(st);
      }
    }
  }

  int workerTrapped = -1;
  char trapMsg[1024] = {0};
  if (failedWorker >= 0) {
    workerTrapped = failedWorker;
    uint32_t mlen = 0;
    memcpy(&mlen, inbufs[failedWorker].data + 1, 4);
    if (mlen > sizeof(trapMsg) - 1) mlen = sizeof(trapMsg) - 1;
    if (mlen && inbufs[failedWorker].len >= 5 && mlen <= inbufs[failedWorker].len - 5) {
      memcpy(trapMsg, inbufs[failedWorker].data + 5, mlen);
      trapMsg[mlen] = 0;
    } else {
      snprintf(trapMsg, sizeof(trapMsg), "worker %d reported error", failedWorker);
    }
  } else if (otherTrapped >= 0) {
    workerTrapped = otherTrapped;
    if (otherSig) snprintf(trapMsg, sizeof(trapMsg), "worker %d killed by signal %d", otherTrapped, otherSig);
    else snprintf(trapMsg, sizeof(trapMsg), "worker %d exited with code %d", otherTrapped, otherExit);
  }

  if (oversizedWorker >= 0) {
    for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
    free(inbufs); free(pfds); free(pipes); free(pids); free(items);
    aslError("ERR_SERIALIZE_SIZE", "worker %d response exceeds serialization size limit", oversizedWorker);
  }

  if (workerTrapped >= 0) {
    for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
    free(inbufs); free(pfds); free(pipes); free(pids); free(items);
    aslError("ERR_WORKER_TRAP", "%s", trapMsg[0] ? trapMsg : "worker trapped");
  }

  Val *chunkAccs = malloc(sizeof(Val) * (size_t)K);
  if (!chunkAccs) {
    for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
    free(inbufs); free(pfds); free(pipes); free(pids); free(items);
    aslError("ERR_OOM", "parFold chunk accumulators");
  }

  asl_gc_root_push(&combine);
  for (int64_t k = 0; k < K; k++) {
    DeserCtx d = {inbufs[k].data, 0, inbufs[k].len, 0};
    uint8_t st = deserU8(&d);
    if (st != 0 || d.err) {
      asl_gc_root_pop(1 + (int)k);
      for (int64_t j = 0; j < K; j++) free(inbufs[j].data);
      free(inbufs); free(pfds); free(pipes); free(pids); free(items); free(chunkAccs);
      aslError("ERR_WORKER_TRAP", "worker %d sent corrupted fold data", (int)k);
    }
    chunkAccs[k] = deserVal(&d, 0);
    if (d.err) {
      asl_gc_root_pop(1 + (int)k);
      for (int64_t j = 0; j < K; j++) free(inbufs[j].data);
      free(inbufs); free(pfds); free(pipes); free(pids); free(items); free(chunkAccs);
      aslError("ERR_WORKER_TRAP", "deserialization error on worker %d fold accumulator", (int)k);
    }
    asl_gc_root_push(&chunkAccs[k]);
  }

  Val result = chunkAccs[0];
  asl_gc_root_push(&result);
  for (int64_t k = 1; k < K; k++) {
    Val callArgs[2] = {result, chunkAccs[k]};
    result = aslCall(combine, 2, callArgs);
  }
  asl_gc_root_pop(2 + (int)K);

  for (int64_t k = 0; k < K; k++) free(inbufs[k].data);
  free(inbufs); free(pfds); free(pipes); free(pids); free(items); free(chunkAccs);
  return result;
}


const Builtin parallelBuiltins[] = {
  {"parMap", bParMap, -1, 0},
  {"parFold", bParFold, -1, 0},
};
const int nParallelBuiltins = (int)(sizeof parallelBuiltins / sizeof parallelBuiltins[0]);

/* a native binary's call of one of these by name (asl-target-llvm builtinTableSym); referencing it links this table */
Val asl_rt_builtin_parallel(const char *name, int64_t argc, Val *argv) { return builtinCallIn(parallelBuiltins, nParallelBuiltins, name, argc, argv); }
