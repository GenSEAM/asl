#include "value.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#elif defined(_WIN32)
#include <windows.h>
#endif
#if defined(__APPLE__) || defined(__FreeBSD__)
#include <sys/event.h>
#elif defined(__linux__)
#include <sys/syscall.h>
#endif

static const char *sysErrKind(int e, char *ioBuf, size_t ioBufLen) {
  switch (e) {
    case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
    case EWOULDBLOCK:
#endif
      return "wouldBlock";
    case ENOENT:
      return "notFound";
    case EACCES:
    case EPERM:
    case EROFS:
      return "permission";
    case EBADF:
      return "badFd";
    case EBUSY:
      return "busy";
    case EINTR:
      return "interrupted";
    case ESRCH:
      return "noProcess";
    case ECHILD:
      return "noChild";
    default:
      snprintf(ioBuf, ioBufLen, "io:%d", e);
      return ioBuf;
  }
}

static Val errStr(const char *msg) {
  return mkResult(0, mkStr(msg, strlen(msg)));
}

static Val mapErrno(int e) {
  char buf[32];
  const char *k = sysErrKind(e, buf, sizeof buf);
  return errStr(k);
}

static int64_t monoMs(void);

static Val mkPairVal(Val a, Val b) {
  int symPair = intern("pair", 4);
  asl_gc_root_push(&a);
  asl_gc_root_push(&b);
  Val r = mkCtor(symPair, 2);
  asl_gc_root_pop(2);
  Ctor *c = (Ctor *)r.u.o;
  c->f[0] = a;
  c->f[1] = b;
  return r;
}

static Val bFdRead(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT || a[1].tag != T_INT) return errStr("badFd");
  int64_t fd = a[0].u.i;
  int64_t max = a[1].u.i;
  if (fd < 0 || fd > INT_MAX) return errStr("badFd");
  if (max < 0 || max > (1LL << 24)) return errStr("io:22");
  if (max == 0) return mkResult(1, mkStr("", 0));

  char *buf = malloc((size_t)max);
  if (!buf) return errStr("io:12");

  ssize_t rd = read((int)fd, buf, (size_t)max);
  if (rd < 0) {
    int e = errno;
    free(buf);
    return mapErrno(e);
  }
  Val res = mkStr(buf, (size_t)rd);
  free(buf);
  return mkResult(1, res);
}

static Val bFdWrite(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT) return errStr("badFd");
  if (a[1].tag != T_STR) return errStr("io:22");
  int64_t fd = a[0].u.i;
  if (fd < 0 || fd > INT_MAX) return errStr("badFd");
  Str *s = (Str *)a[1].u.o;
  ssize_t wr = write((int)fd, s->s, s->len);
  if (wr < 0) return mapErrno(errno);
  return mkResult(1, vint((int64_t)wr));
}

static Val bFdClose(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT) return errStr("badFd");
  int64_t fd = a[0].u.i;
  if (fd < 0 || fd > INT_MAX) return errStr("badFd");
  if (close((int)fd) < 0) return mapErrno(errno);
  return mkResult(1, VUNIT);
}

static int fdPairArg(Val item, int64_t *fd, int64_t *mask) {
  Val fVal = VUNIT, sVal = VUNIT;
  int ok = 0;
  if (item.tag == T_CTOR) {
    Ctor *c = (Ctor *)item.u.o;
    if (c->ctor == intern("pair", 4) && c->n == 2) {
      fVal = c->f[0];
      sVal = c->f[1];
      ok = 1;
    }
  } else if (item.tag == T_LIST && item.u.o) {
    fVal = ((Cons *)item.u.o)->car;
    Val cdr = ((Cons *)item.u.o)->cdr;
    if (cdr.tag == T_LIST && cdr.u.o) {
      sVal = ((Cons *)cdr.u.o)->car;
      ok = 1;
    }
  }
  if (!ok || fVal.tag != T_INT || sVal.tag != T_INT) return 1;
  if (fVal.u.i < 0 || fVal.u.i > INT_MAX) return 2;
  *fd = fVal.u.i;
  *mask = sVal.u.i;
  return 0;
}

static Val bFdPoll(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_LIST || a[1].tag != T_INT) return errStr("io:22");

  int count = 0;
  for (Obj *x = a[0].u.o; x; x = ((Cons *)x)->cdr.u.o) count++;

  int64_t tms = a[1].u.i;
  if (tms < -1) return errStr("io:22");
  int timeout = tms > INT_MAX ? INT_MAX : (int)tms;

  if (count == 0) {
    if (poll(NULL, 0, timeout) < 0) return mapErrno(errno);
    return mkResult(1, VNIL);
  }

  struct pollfd *pfd = malloc((size_t)count * sizeof(struct pollfd));
  if (!pfd) return errStr("io:12");
  int64_t *inFds = malloc((size_t)count * sizeof(int64_t));
  if (!inFds) { free(pfd); return errStr("io:12"); }

  int i = 0;
  for (Obj *x = a[0].u.o; x; x = ((Cons *)x)->cdr.u.o, i++) {
    int64_t fd, mask;
    int bad = fdPairArg(((Cons *)x)->car, &fd, &mask);
    if (bad) {
      free(pfd); free(inFds);
      return errStr(bad == 2 ? "badFd" : "io:22");
    }
    inFds[i] = fd;
    pfd[i].fd = (int)fd;
    short ev = 0;
    if (mask & 1) ev |= POLLIN;
    if (mask & 2) ev |= POLLOUT;
    pfd[i].events = ev;
    pfd[i].revents = 0;
  }

  int prc = poll(pfd, (nfds_t)count, timeout);
  if (prc < 0) {
    int e = errno;
    free(pfd); free(inFds);
    return mapErrno(e);
  }

  int *readyMasks = malloc((size_t)count * sizeof(int));
  int64_t *readyFds = malloc((size_t)count * sizeof(int64_t));
  if (!readyMasks || !readyFds) {
    free(pfd); free(inFds);
    if (readyMasks) free(readyMasks);
    if (readyFds) free(readyFds);
    return errStr("io:12");
  }

  int nReady = 0;
  for (int j = 0; j < count; j++) {
    int rm = 0;
    if (pfd[j].revents & (POLLIN | POLLPRI)) rm |= 1;
    if (pfd[j].revents & POLLOUT) rm |= 2;
    if (pfd[j].revents & (POLLHUP | POLLERR | POLLNVAL)) rm |= 4;
    if (rm != 0) {
      readyFds[nReady] = inFds[j];
      readyMasks[nReady] = rm;
      nReady++;
    }
  }
  free(pfd); free(inFds);

  Val acc = VNIL;
  asl_gc_root_push(&acc);
  for (int j = nReady - 1; j >= 0; j--) {
    Val p = mkPairVal(vint(readyFds[j]), vint(readyMasks[j]));
    asl_gc_root_push(&p);
    acc = mkCons(p, acc);
    asl_gc_root_pop(1);
  }
  asl_gc_root_pop(1);

  free(readyMasks);
  free(readyFds);
  return mkResult(1, acc);
}

static Val bFdNonBlocking(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT) return errStr("badFd");
  if (a[1].tag != T_BOOL) return errStr("io:22");
  int64_t fd = a[0].u.i;
  if (fd < 0 || fd > INT_MAX) return errStr("badFd");
  int flags = fcntl((int)fd, F_GETFL, 0);
  if (flags < 0) return mapErrno(errno);
  if (a[1].u.i) flags |= O_NONBLOCK;
  else flags &= ~O_NONBLOCK;
  if (fcntl((int)fd, F_SETFL, flags) < 0) return mapErrno(errno);
  return mkResult(1, VUNIT);
}

static Val bFileLock(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_STR || a[1].tag != T_BOOL) return errStr("io:22");
  Str *p = (Str *)a[0].u.o;
  if (memchr(p->s, '\0', p->len)) return errStr("io:22");
  char path[PATH_MAX];
  if (p->len >= sizeof(path)) return mapErrno(ENAMETOOLONG);
  memcpy(path, p->s, p->len);
  path[p->len] = '\0';

  int fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  if (fd < 0) return mapErrno(errno);

  int op = (a[1].u.i ? LOCK_EX : LOCK_SH) | LOCK_NB;
  if (flock(fd, op) < 0) {
    int e = errno;
    close(fd);
    if (e == EWOULDBLOCK || e == EAGAIN || e == EBUSY) return errStr("busy");
    return mapErrno(e);
  }
  return mkResult(1, vint((int64_t)fd));
}

static Val safePathErr(int e) {
  if (e == ELOOP || e == ENOTDIR) return errStr("ERR_PATH_SYMLINK");
  return mapErrno(e);
}

/* Open every directory component beneath an already opened repo root without following links. */
static int safeParentAt(const char *root, const char *rel, char *leaf, size_t leafCap, int *error) {
  if (!root || !*root || !rel || !*rel || rel[0] == '/' || strchr(rel, '\\')) { *error = EINVAL; return -1; }
  char path[PATH_MAX];
  size_t len = strlen(rel);
  if (len >= sizeof(path)) { *error = ENAMETOOLONG; return -1; }
  memcpy(path, rel, len + 1);
  int dirfd = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (dirfd < 0) { *error = errno; return -1; }
  char *part = path;
  for (;;) {
    char *slash = strchr(part, '/');
    if (slash) *slash = '\0';
    if (!*part || !strcmp(part, ".") || !strcmp(part, "..")) { close(dirfd); *error = EINVAL; return -1; }
    if (!slash) {
      if (strlen(part) >= leafCap) { close(dirfd); *error = ENAMETOOLONG; return -1; }
      strcpy(leaf, part);
      return dirfd;
    }
    if (!slash[1]) { close(dirfd); *error = EINVAL; return -1; }
    int next = openat(dirfd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (next < 0) { *error = errno; close(dirfd); return -1; }
    close(dirfd);
    dirfd = next;
    part = slash + 1;
  }
}

static Val bFileLockAt(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_STR || a[1].tag != T_STR || a[2].tag != T_BOOL) return errStr("io:22");
  Str *root = (Str *)a[0].u.o, *rel = (Str *)a[1].u.o;
  if (memchr(root->s, '\0', root->len) || memchr(rel->s, '\0', rel->len)) return errStr("io:22");
  char leaf[NAME_MAX + 1]; int e = 0;
  int dirfd = safeParentAt(root->s, rel->s, leaf, sizeof(leaf), &e);
  if (dirfd < 0) return safePathErr(e);
  int fd = openat(dirfd, leaf, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0666);
  if (fd < 0 && errno == EEXIST) fd = openat(dirfd, leaf, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
  e = errno;
  close(dirfd);
  if (fd < 0) return safePathErr(e);
  int op = (a[2].u.i ? LOCK_EX : LOCK_SH) | LOCK_NB;
  if (flock(fd, op) < 0) { e = errno; close(fd); if (e == EWOULDBLOCK || e == EAGAIN || e == EBUSY) return errStr("busy"); return safePathErr(e); }
  return mkResult(1, vint((int64_t)fd));
}

static Val bFileReadAt(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_STR || a[1].tag != T_STR) return errStr("io:22");
  Str *root = (Str *)a[0].u.o, *rel = (Str *)a[1].u.o;
  if (memchr(root->s, '\0', root->len) || memchr(rel->s, '\0', rel->len)) return errStr("io:22");
  char leaf[NAME_MAX + 1]; int e = 0;
  int dirfd = safeParentAt(root->s, rel->s, leaf, sizeof(leaf), &e);
  if (dirfd < 0) return safePathErr(e);
  int fd = openat(dirfd, leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  e = errno; close(dirfd);
  if (fd < 0) return safePathErr(e);
  struct stat st;
  if (fstat(fd, &st) != 0) { e = errno; close(fd); return safePathErr(e); }
  if (!S_ISREG(st.st_mode)) { close(fd); return errStr("ERR_PATH_TYPE"); }
  size_t cap = st.st_size > 0 && (uintmax_t)st.st_size < SIZE_MAX ? (size_t)st.st_size : 4096;
  if (cap < 4096) cap = 4096;
  char *buf = malloc(cap);
  if (!buf) { close(fd); return errStr("io:12"); }
  size_t len = 0;
  for (;;) {
    if (len == cap) { if (cap > SIZE_MAX / 2) { free(buf); close(fd); return errStr("io:12"); } size_t next = cap * 2; char *grown = realloc(buf, next); if (!grown) { free(buf); close(fd); return errStr("io:12"); } buf = grown; cap = next; }
    ssize_t got = read(fd, buf + len, cap - len);
    if (got < 0) { if (errno == EINTR) continue; e = errno; free(buf); close(fd); return safePathErr(e); }
    if (got == 0) break;
    len += (size_t)got;
  }
  if (close(fd) != 0) { e = errno; free(buf); return safePathErr(e); }
  Val result = mkResult(1, mkStr(buf, len));
  free(buf);
  return result;
}

static Val bFileWriteAt(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_STR || a[1].tag != T_STR || a[2].tag != T_STR) return errStr("io:22");
  Str *root = (Str *)a[0].u.o, *rel = (Str *)a[1].u.o, *data = (Str *)a[2].u.o;
  if (memchr(root->s, '\0', root->len) || memchr(rel->s, '\0', rel->len)) return errStr("io:22");
  char leaf[NAME_MAX + 1]; int e = 0;
  int dirfd = safeParentAt(root->s, rel->s, leaf, sizeof(leaf), &e);
  if (dirfd < 0) return safePathErr(e);
  struct stat st;
  if (fstatat(dirfd, leaf, &st, AT_SYMLINK_NOFOLLOW) != 0) { e = errno; close(dirfd); return safePathErr(e); }
  if (S_ISLNK(st.st_mode)) { close(dirfd); return errStr("ERR_PATH_SYMLINK"); }
  if (!S_ISREG(st.st_mode)) { close(dirfd); return errStr("ERR_PATH_TYPE"); }
  static unsigned long tempSequence = 0;
  char temp[NAME_MAX + 1];
  int fd = -1;
  for (int attempt = 0; attempt < 128; attempt++) {
    unsigned long seq = ++tempSequence;
    int count = snprintf(temp, sizeof(temp), ".asl-write-%ld-%lu", (long)getpid(), seq);
    if (count < 0 || (size_t)count >= sizeof(temp)) { close(dirfd); return errStr("io:36"); }
    fd = openat(dirfd, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, st.st_mode & 0777);
    if (fd >= 0) break;
    if (errno != EEXIST) { e = errno; close(dirfd); return safePathErr(e); }
  }
  if (fd < 0) { close(dirfd); return errStr("io:17"); }
  if (fchmod(fd, st.st_mode & 07777) != 0) { e = errno; close(fd); unlinkat(dirfd, temp, 0); close(dirfd); return safePathErr(e); }
  size_t done = 0;
  while (done < data->len) {
    ssize_t w = write(fd, data->s + done, data->len - done);
    if (w < 0) { if (errno == EINTR) continue; e = errno; close(fd); unlinkat(dirfd, temp, 0); close(dirfd); return safePathErr(e); }
    done += (size_t)w;
  }
  while (fsync(fd) != 0) { if (errno == EINTR) continue; e = errno; close(fd); unlinkat(dirfd, temp, 0); close(dirfd); return safePathErr(e); }
  if (close(fd) != 0) { e = errno; unlinkat(dirfd, temp, 0); close(dirfd); return safePathErr(e); }
  if (fstatat(dirfd, leaf, &st, AT_SYMLINK_NOFOLLOW) != 0) { e = errno; unlinkat(dirfd, temp, 0); close(dirfd); return safePathErr(e); }
  if (S_ISLNK(st.st_mode)) { unlinkat(dirfd, temp, 0); close(dirfd); return errStr("ERR_PATH_SYMLINK"); }
  if (!S_ISREG(st.st_mode)) { unlinkat(dirfd, temp, 0); close(dirfd); return errStr("ERR_PATH_TYPE"); }
  if (renameat(dirfd, temp, dirfd, leaf) != 0) { e = errno; unlinkat(dirfd, temp, 0); close(dirfd); return safePathErr(e); }
  while (fsync(dirfd) != 0) { if (errno == EINTR) continue; e = errno; close(dirfd); return safePathErr(e); }
  if (close(dirfd) != 0) return safePathErr(errno);
  return mkResult(1, VUNIT);
}

extern char **environ;

static void freeStrv(char **v) {
  if (!v) return;
  for (char **p = v; *p; p++) free(*p);
  free(v);
}

static int strvFromList(Val l, char ***out) {
  *out = NULL;
  if (l.tag != T_LIST) return EINVAL;
  size_t count = 0;
  for (Obj *x = l.u.o; x; x = ((Cons *)x)->cdr.u.o) count++;
  char **v = calloc(count + 1, sizeof(char *));
  if (!v) return ENOMEM;
  size_t i = 0;
  for (Obj *x = l.u.o; x; x = ((Cons *)x)->cdr.u.o, i++) {
    Val item = ((Cons *)x)->car;
    if (item.tag != T_STR) { freeStrv(v); return EINVAL; }
    Str *s = (Str *)item.u.o;
    if (memchr(s->s, '\0', s->len)) { freeStrv(v); return EINVAL; }
    v[i] = malloc(s->len + 1);
    if (!v[i]) { freeStrv(v); return ENOMEM; }
    memcpy(v[i], s->s, s->len);
    v[i][s->len] = '\0';
  }
  *out = v;
  return 0;
}

static int optionArg(Val o, Val *inner) {
  if (o.tag != T_CTOR) return -1;
  Ctor *c = (Ctor *)o.u.o;
  if (c->ctor == KW_NONE && c->n == 0) return 0;
  if (c->ctor == KW_SOME && c->n == 1) { *inner = c->f[0]; return 1; }
  return -1;
}

/* fileLockWait path [exclusive [timeoutMs]]
 * Blocking variant of fileLock (HB3):
 * - path: String file path to lock
 * - exclusive: Bool (true for LOCK_EX, false for LOCK_SH; default true if omitted)
 * - timeoutMs: optional timeout in ms (Int64, (some ms), (none), or omitted/negative for indefinite wait)
 * Returns (ok fd) on success.
 * On timeout expiry, returns (err "ERR_TIMEOUT").
 * On other error, returns (err <reason>).
 */
static Val bFileLockWait(Val *a, int n) {
  if (n < 1 || n > 3) return errStr("io:22");
  if (a[0].tag != T_STR) return errStr("io:22");
  Str *p = (Str *)a[0].u.o;
  if (memchr(p->s, '\0', p->len)) return errStr("io:22");
  char path[PATH_MAX];
  if (p->len >= sizeof(path)) return mapErrno(ENAMETOOLONG);
  memcpy(path, p->s, p->len);
  path[p->len] = '\0';

  int exclusive = 1;
  int64_t timeoutMs = -1;

  if (n == 2) {
    if (a[1].tag == T_BOOL) {
      exclusive = (int)a[1].u.i;
    } else if (a[1].tag == T_INT) {
      timeoutMs = a[1].u.i;
    } else {
      Val inner = VUNIT;
      int ok = optionArg(a[1], &inner);
      if (ok == 0) timeoutMs = -1;
      else if (ok == 1 && inner.tag == T_INT) timeoutMs = inner.u.i;
      else return errStr("io:22");
    }
  } else if (n == 3) {
    if (a[1].tag != T_BOOL) return errStr("io:22");
    exclusive = (int)a[1].u.i;
    if (a[2].tag == T_INT) {
      timeoutMs = a[2].u.i;
    } else {
      Val inner = VUNIT;
      int ok = optionArg(a[2], &inner);
      if (ok == 0) timeoutMs = -1;
      else if (ok == 1 && inner.tag == T_INT) timeoutMs = inner.u.i;
      else return errStr("io:22");
    }
  }

  int fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  if (fd < 0) return mapErrno(errno);

  int op = exclusive ? LOCK_EX : LOCK_SH;

  if (timeoutMs < 0 || timeoutMs > ((int64_t)1 << 50)) {
    while (flock(fd, op) < 0) {
      if (errno == EINTR) continue;
      int e = errno;
      close(fd);
      return mapErrno(e);
    }
    return mkResult(1, vint((int64_t)fd));
  }

  if (flock(fd, op | LOCK_NB) == 0) {
    return mkResult(1, vint((int64_t)fd));
  }
  int e = errno;
  if (e != EWOULDBLOCK && e != EAGAIN && e != EBUSY) {
    close(fd);
    return mapErrno(e);
  }
  if (timeoutMs == 0) {
    close(fd);
    return errStr("ERR_TIMEOUT");
  }

  int64_t deadline = monoMs() + timeoutMs;
  int step = 1;
  while (1) {
    int64_t now = monoMs();
    if (now >= deadline) {
      close(fd);
      return errStr("ERR_TIMEOUT");
    }
    int64_t rem = deadline - now;
    int waitMs = (int)(rem < step ? rem : step);
    if (waitMs <= 0) waitMs = 1;
    poll(NULL, 0, waitMs);

    if (flock(fd, op | LOCK_NB) == 0) {
      return mkResult(1, vint((int64_t)fd));
    }
    e = errno;
    if (e != EWOULDBLOCK && e != EAGAIN && e != EBUSY && e != EINTR) {
      close(fd);
      return mapErrno(e);
    }
    if (step < 20) step *= 2;
  }
}

static Val bFileAppend(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_STR) return errStr("io:22");
  Str *p = (Str *)a[0].u.o;
  if (memchr(p->s, '\0', p->len)) return errStr("io:22");
  char path[PATH_MAX];
  if (p->len >= sizeof(path)) return mapErrno(ENAMETOOLONG);
  memcpy(path, p->s, p->len);
  path[p->len] = '\0';
  const char *data; size_t len;
  if (a[1].tag == T_STR) {
    Str *s = (Str *)a[1].u.o; data = s->s; len = s->len;
  } else if (a[1].tag == T_BYTES) {
    Arr *ar = (Arr *)a[1].u.o; data = (const char *)ar->data; len = ar->len;
  } else {
    return errStr("io:22");
  }
  int e = fileAppendRaw(path, data, len);
  if (e) return mapErrno(e);
  return mkResult(1, VUNIT);
}



static int envArg(Val o, char ***envp) {
  Val inner = VUNIT;
  *envp = NULL;
  int k = optionArg(o, &inner);
  if (k < 0) return EINVAL;
  if (k == 0) return 0;
  char **v;
  int e = strvFromList(inner, &v);
  if (e) return e;
  for (char **p = v; *p; p++) if (!strchr(*p, '=') || **p == '=') { freeStrv(v); return EINVAL; }
  *envp = v;
  return 0;
}

static int highCloexec(int *fd) {
  if (*fd < 3) {
    int moved = fcntl(*fd, F_DUPFD_CLOEXEC, 3);
    if (moved < 0) return errno;
    close(*fd);
    *fd = moved;
    return 0;
  }
  return fcntl(*fd, F_SETFD, FD_CLOEXEC) < 0 ? errno : 0;
}

static int pipeHigh(int p[2]) {
  if (pipe(p) < 0) return errno;
  int e = highCloexec(&p[0]);
  if (!e) e = highCloexec(&p[1]);
  if (e) { close(p[0]); close(p[1]); }
  return e;
}

static void closeAll(int *fds, int n) {
  for (int i = 0; i < n; i++) if (fds[i] >= 0) close(fds[i]);
}

static int exitCodeOf(int st) {
  return WIFEXITED(st) ? WEXITSTATUS(st) : -WTERMSIG(st);
}

static Val mkSpawned(pid_t pid, int inW, int outR, int errR) {
  static int keys[5];
  static const char *const fields[] = {"pid", "stdin", "stdout", "stderr"};
  if (!keys[4]) { for (int i = 0; i < 4; i++) keys[i] = intern(fields[i], strlen(fields[i])); keys[4] = 1; }
  Rec *r = asl_alloc(O_REC, sizeof(Rec) + sizeof(Val) * 4);
  r->schema = intern("SpawnedProc", 11);
  r->n = 4;
  r->keys = keys;
  r->v[0] = vint((int64_t)pid);
  r->v[1] = vint((int64_t)inW);
  r->v[2] = vint((int64_t)outR);
  r->v[3] = vint((int64_t)errR);
  return mkResult(1, vobj(T_REC, r));
}

static Val bProcSpawnv(Val *a, int n) {
  (void)n;
  char **argv = NULL, **envp = NULL;
  char *cwd = NULL;
  int e = strvFromList(a[0], &argv);
  if (e) return mapErrno(e);
  if (!argv[0]) { freeStrv(argv); return errStr("io:22"); }
  Val cwdVal = VUNIT;
  int ck = optionArg(a[1], &cwdVal);
  if (ck < 0 || (ck == 1 && cwdVal.tag != T_STR)) { freeStrv(argv); return errStr("io:22"); }
  if (ck == 1) {
    Str *s = (Str *)cwdVal.u.o;
    if (memchr(s->s, '\0', s->len) || s->len == 0) { freeStrv(argv); return errStr("io:22"); }
    cwd = malloc(s->len + 1);
    if (!cwd) { freeStrv(argv); return errStr("io:12"); }
    memcpy(cwd, s->s, s->len);
    cwd[s->len] = '\0';
  }
  e = envArg(a[2], &envp);
  if (e) { freeStrv(argv); free(cwd); return mapErrno(e); }
  aslLogSpawn(argv[0]);

  int fds[8] = {-1, -1, -1, -1, -1, -1, -1, -1};
  for (int i = 0; i < 4 && !e; i++) e = pipeHigh(&fds[2 * i]);
  if (e) { closeAll(fds, 8); freeStrv(argv); freeStrv(envp); free(cwd); return mapErrno(e); }
  int inR = fds[0], inW = fds[1], outR = fds[2], outW = fds[3], errR = fds[4], errW = fds[5], repR = fds[6], repW = fds[7];

  pid_t pid = fork();
  if (pid < 0) {
    e = errno;
    closeAll(fds, 8); freeStrv(argv); freeStrv(envp); free(cwd);
    return mapErrno(e);
  }
  if (pid == 0) {
    setpgid(0, 0);
    signal(SIGPIPE, SIG_DFL);
    int ce = 0;
    if (dup2(inR, STDIN_FILENO) < 0 || dup2(outW, STDOUT_FILENO) < 0 || dup2(errW, STDERR_FILENO) < 0) ce = errno;
    if (!ce && cwd && chdir(cwd) < 0) ce = errno;
    if (!ce) {
      if (envp) environ = envp;
      execvp(argv[0], argv);
      ce = errno;
    }
    ssize_t wr = write(repW, &ce, sizeof ce);
    (void)wr;
    _exit(127);
  }
  setpgid(pid, pid);
  close(inR); close(outW); close(errW); close(repW);
  freeStrv(argv); freeStrv(envp); free(cwd);

  int childErr = 0;
  ssize_t rd;
  while ((rd = read(repR, &childErr, sizeof childErr)) < 0 && errno == EINTR) {}
  close(repR);
  if (rd == (ssize_t)sizeof childErr) {
    int st;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    close(inW); close(outR); close(errR);
    return mapErrno(childErr);
  }
  return mkSpawned(pid, inW, outR, errR);
}

static volatile sig_atomic_t fwdPending;
static void fwdHandler(int sig) { fwdPending = sig; }
static const int fwdSignals[] = {SIGINT, SIGTERM, SIGHUP};
#define NFWD ((int)(sizeof fwdSignals / sizeof fwdSignals[0]))

/* a blocking wait forwards SIGINT SIGTERM SIGHUP to the child's process group, then re-raises it here */
static pid_t waitForwarding(pid_t pid, int *st, int *err) {
  struct sigaction sa, old[NFWD]; char mine[NFWD] = {0};
  memset(&sa, 0, sizeof sa); sa.sa_handler = fwdHandler;
  sigemptyset(&sa.sa_mask);
  fwdPending = 0;
  for (int i = 0; i < NFWD; i++) if (sigaction(fwdSignals[i], NULL, &old[i]) == 0 && old[i].sa_handler == SIG_DFL) mine[i] = sigaction(fwdSignals[i], &sa, NULL) == 0;
  int got = 0; pid_t w;
  for (;;) {
    if (fwdPending) { got = fwdPending; fwdPending = 0; if (kill(-pid, got) < 0) kill(pid, got); }
    w = waitpid(pid, st, 0);
    if (w >= 0 || errno != EINTR) break;
  }
  *err = w < 0 ? errno : 0;
  for (int i = 0; i < NFWD; i++) if (mine[i]) sigaction(fwdSignals[i], &old[i], NULL);
  if (fwdPending || got) { fflush(NULL); raise(fwdPending ? fwdPending : got); }
  return w;
}

static Val bProcWaitPid(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT || a[1].tag != T_BOOL) return errStr("io:22");
  int64_t pid = a[0].u.i;
  if (pid <= 0 || pid > INT_MAX) return errStr("io:22");
  int st = 0, e = 0;
  pid_t w;
  if (a[1].u.i) {
    while ((w = waitpid((pid_t)pid, &st, WNOHANG)) < 0 && errno == EINTR) {}
    if (w < 0) e = errno;
  } else {
    w = waitForwarding((pid_t)pid, &st, &e);
  }
  if (e) return mapErrno(e);
  if (w == 0) return mkResult(1, mkCtor(KW_NONE, 0));
  Val code = vint((int64_t)exitCodeOf(st));
  Val some = mkCtor(KW_SOME, 1);
  ((Ctor *)some.u.o)->f[0] = code;
  return mkResult(1, some);
}

static const struct { const char *name; int sig; } sysSignals[] = {
  {"SIGHUP", SIGHUP}, {"SIGINT", SIGINT}, {"SIGQUIT", SIGQUIT}, {"SIGKILL", SIGKILL},
  {"SIGUSR1", SIGUSR1}, {"SIGUSR2", SIGUSR2}, {"SIGTERM", SIGTERM}, {"SIGCONT", SIGCONT},
  {"SIGSTOP", SIGSTOP}, {"SIGWINCH", SIGWINCH},
};

static Val bProcKill(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT || a[1].tag != T_STR) return errStr("io:22");
  int64_t pid = a[0].u.i;
  if (pid > INT_MAX || pid < -(int64_t)INT_MAX || (pid >= -1 && pid <= 1)) return errStr("io:22");
  Str *s = (Str *)a[1].u.o;
  int sig = -1;
  for (size_t i = 0; i < sizeof sysSignals / sizeof sysSignals[0]; i++)
    if (strlen(sysSignals[i].name) == s->len && !memcmp(sysSignals[i].name, s->s, s->len)) sig = sysSignals[i].sig;
  if (sig < 0) return errStr("io:22");
  if (kill((pid_t)pid, sig) < 0) return mapErrno(errno);
  return mkResult(1, VUNIT);
}

static Val bProcSelf(Val *a, int n) {
  (void)a; (void)n;
  return vint((int64_t)getpid());
}

/* the running executable's path: here rather than in loader.c so a native binary linking libaslrt.a has it for procExePath */
int hostGetExecutablePath(char *buf, size_t bufsize) {
#if defined(__APPLE__)
  uint32_t sz = (uint32_t)bufsize; return _NSGetExecutablePath(buf, &sz) == 0;
#elif defined(__linux__)
  ssize_t len = readlink("/proc/self/exe", buf, bufsize - 1);
  if (len != -1) { buf[len] = '\0'; return 1; }
  return 0;
#elif defined(_WIN32)
  return GetModuleFileNameA(NULL, buf, (DWORD)bufsize) != 0;
#else
  (void)buf; (void)bufsize; return 0;
#endif
}

/* the running executable's resolved path (hostGetExecutablePath: _NSGetExecutablePath or /proc/self/exe);
   dyld sets no errno on a path longer than the buffer, reported as ERANGE like asl-target-llvm sysExePath */
static Val bProcExePath(Val *a, int n) {
  (void)a; (void)n;
  char exe[PATH_MAX + 64], real[PATH_MAX];
  errno = 0; if (!hostGetExecutablePath(exe, sizeof exe)) return mapErrno(errno ? errno : ERANGE);
  if (!realpath(exe, real)) return mapErrno(errno);
  return mkResult(1, mkStr(real, strlen(real)));
}

static Val bProcExecv(Val *a, int n) {
  (void)n;
  char **argv = NULL, **envp = NULL;
  int e = strvFromList(a[0], &argv);
  if (e) return mapErrno(e);
  if (!argv[0]) { freeStrv(argv); return errStr("io:22"); }
  aslLogSpawn(argv[0]);
  e = envArg(a[1], &envp);
  if (e) { freeStrv(argv); return mapErrno(e); }
  fflush(NULL);
  char **saved = environ;
  if (envp) environ = envp;
  signal(SIGPIPE, SIG_DFL);
  execvp(argv[0], argv);
  e = errno;
  signal(SIGPIPE, SIG_IGN);
  environ = saved;
  freeStrv(argv); freeStrv(envp);
  return mapErrno(e);
}

static Val bEnvList(Val *a, int n) {
  (void)a; (void)n;
  size_t count = 0;
  while (environ[count]) count++;
  Val acc = VNIL;
  asl_gc_root_push(&acc);
  for (size_t i = count; i > 0; i--) {
    Val s = mkStr(environ[i - 1], strlen(environ[i - 1]));
    asl_gc_root_push(&s);
    acc = mkCons(s, acc);
    asl_gc_root_pop(1);
  }
  asl_gc_root_pop(1);
  return acc;
}

typedef struct {
  int n;
  int *fds;
} ChildWatch;

static void watchClose(ChildWatch *w) {
  for (int i = 0; i < w->n; i++) if (w->fds[i] >= 0) close(w->fds[i]);
  free(w->fds);
  w->fds = NULL;
  w->n = 0;
}

static int watchOpen(ChildWatch *w, const pid_t *pids, int np, char *known, int *regErr) {
  *regErr = 0;
  w->n = 0;
  w->fds = NULL;
  if (np == 0) return 0;
#if defined(__APPLE__) || defined(__FreeBSD__)
  w->fds = malloc(sizeof(int));
  if (!w->fds) return ENOMEM;
  int kq = kqueue();
  if (kq < 0) { int e = errno; free(w->fds); w->fds = NULL; return e; }
  w->fds[0] = kq;
  w->n = 1;
  if (fcntl(kq, F_SETFD, FD_CLOEXEC) < 0) { int e = errno; watchClose(w); return e; }
  for (int i = 0; i < np; i++) {
    struct kevent ev;
    EV_SET(&ev, (uintptr_t)pids[i], EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (kevent(kq, &ev, 1, NULL, 0, NULL) < 0) {
      if (errno == ESRCH) known[i] = 1;
      else if (!*regErr) *regErr = errno;
    }
  }
  return 0;
#elif defined(__linux__) && defined(SYS_pidfd_open)
  w->fds = malloc((size_t)np * sizeof(int));
  if (!w->fds) return ENOMEM;
  w->n = np;
  for (int i = 0; i < np; i++) {
    w->fds[i] = (int)syscall(SYS_pidfd_open, pids[i], 0);
    if (w->fds[i] < 0) {
      if (errno == ESRCH) known[i] = 1;
      else if (!*regErr) *regErr = errno;
    }
  }
  return 0;
#else
  (void)pids;
  (void)known;
  return ENOSYS;
#endif
}

static void watchDrain(ChildWatch *w, const struct pollfd *pfd, const pid_t *pids, int np, char *known) {
#if defined(__APPLE__) || defined(__FreeBSD__)
  (void)pfd;
  struct kevent out[16];
  struct timespec zero = {0, 0};
  int got;
  while (w->n == 1 && (got = kevent(w->fds[0], NULL, 0, out, 16, &zero)) > 0) {
    for (int j = 0; j < got; j++) {
      if ((out[j].flags & EV_ERROR) || out[j].filter != EVFILT_PROC || !(out[j].fflags & NOTE_EXIT)) continue;
      for (int i = 0; i < np; i++) if ((uintptr_t)pids[i] == out[j].ident) known[i] = 1;
    }
    if (got < 16) break;
  }
#else
  (void)pids;
  for (int i = 0; i < w->n && i < np; i++) if (w->fds[i] >= 0 && (pfd[i].revents & (POLLIN | POLLHUP))) known[i] = 1;
#endif
}

static int64_t monoMs(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int pidsArg(Val l, pid_t **out, int *np) {
  *out = NULL;
  *np = 0;
  if (l.tag != T_LIST) return EINVAL;
  int count = 0;
  for (Obj *x = l.u.o; x; x = ((Cons *)x)->cdr.u.o) {
    Val v = ((Cons *)x)->car;
    if (v.tag != T_INT || v.u.i <= 0 || v.u.i > INT_MAX) return EINVAL;
    count++;
  }
  if (count == 0) return 0;
  pid_t *p = malloc((size_t)count * sizeof(pid_t));
  if (!p) return ENOMEM;
  int i = 0;
  for (Obj *x = l.u.o; x; x = ((Cons *)x)->cdr.u.o) p[i++] = (pid_t)((Cons *)x)->car.u.i;
  *out = p;
  *np = count;
  return 0;
}

static int exitScan(const pid_t *pids, int np, const char *known, char *exited, int *nExited) {
  *nExited = 0;
  for (int i = 0; i < np; i++) {
    siginfo_t si;
    memset(&si, 0, sizeof si);
    int r;
    while ((r = waitid(P_PID, (id_t)pids[i], &si, WEXITED | WNOWAIT | (known[i] ? 0 : WNOHANG))) < 0 && errno == EINTR) {}
    if (r < 0) return errno;
    exited[i] = si.si_pid != 0;
    *nExited += exited[i];
  }
  return 0;
}

static int reapPid(pid_t pid, int *code) {
  int st = 0;
  pid_t w;
  while ((w = waitpid(pid, &st, WNOHANG)) < 0 && errno == EINTR) {}
  if (w < 0) return errno;
  if (w == 0) return ECHILD;
  *code = exitCodeOf(st);
  return 0;
}

typedef struct {
  int nUser;
  struct pollfd *pfd;
  int64_t *masks;
  int nReady;
  int nExited;
  pid_t *donePid;
  int *doneCode;
} WaitSet;

static int waitSet(WaitSet *s, const pid_t *pids, int np, int64_t timeoutMs, int reapAll) {
  s->nReady = 0;
  s->nExited = 0;
  char *exited = np ? calloc((size_t)np * 2, 1) : NULL;
  if (np && !exited) return ENOMEM;
  char *known = exited ? exited + np : NULL;
  ChildWatch w;
  int regErr = 0;
  int e = watchOpen(&w, pids, np, known, &regErr);
  if (e) { free(exited); return e; }
  for (int i = 0; i < w.n; i++) {
    s->pfd[s->nUser + i].fd = w.fds[i];
    s->pfd[s->nUser + i].events = POLLIN;
  }
  int64_t deadline = timeoutMs < 0 || timeoutMs > ((int64_t)1 << 50) ? -1 : monoMs() + timeoutMs;
  for (;;) {
    int nEx = 0;
    e = exitScan(pids, np, known, exited, &nEx);
    if (e) break;
    if (regErr && nEx == 0) { e = regErr; break; }
    int timeout = -1;
    if (deadline >= 0) {
      int64_t left = deadline - monoMs();
      timeout = left <= 0 ? 0 : left > INT_MAX ? INT_MAX : (int)left;
    }
    if (nEx > 0) timeout = 0;
    for (int i = 0; i < s->nUser + w.n; i++) s->pfd[i].revents = 0;
    int prc = poll(s->pfd, (nfds_t)(s->nUser + w.n), timeout);
    if (prc < 0 && errno == EINTR) continue;
    if (prc < 0) { e = errno; break; }
    for (int i = 0; i < s->nUser; i++) {
      int rm = 0;
      if (s->pfd[i].revents & (POLLIN | POLLPRI)) rm |= 1;
      if (s->pfd[i].revents & POLLOUT) rm |= 2;
      if (s->pfd[i].revents & (POLLHUP | POLLERR | POLLNVAL)) rm |= 4;
      if (rm) s->masks[s->nReady++] = ((int64_t)i << 3) | rm;
    }
    if (nEx == 0 && prc > 0 && w.n > 0) {
      watchDrain(&w, s->pfd + s->nUser, pids, np, known);
      e = exitScan(pids, np, known, exited, &nEx);
      if (e) break;
    }
    for (int i = 0; i < np && (reapAll || s->nExited == 0); i++) {
      if (!exited[i]) continue;
      int dup = 0;
      for (int j = 0; j < s->nExited; j++) dup |= s->donePid[j] == pids[i];
      if (dup) continue;
      e = reapPid(pids[i], &s->doneCode[s->nExited]);
      if (e) break;
      s->donePid[s->nExited++] = pids[i];
    }
    if (e) break;
    if (s->nReady > 0 || s->nExited > 0 || prc == 0) break;
  }
  free(exited);
  watchClose(&w);
  return e;
}

static int waitSetAlloc(WaitSet *s, int nUser, int np) {
  int nw = np > 0 ? np : 1;
  s->nUser = nUser;
  s->pfd = calloc((size_t)(nUser + nw), sizeof(struct pollfd));
  s->masks = calloc((size_t)(nUser > 0 ? nUser : 1), sizeof(int64_t));
  s->donePid = calloc((size_t)nw, sizeof(pid_t));
  s->doneCode = calloc((size_t)nw, sizeof(int));
  if (s->pfd && s->masks && s->donePid && s->doneCode) return 0;
  free(s->pfd); free(s->masks); free(s->donePid); free(s->doneCode);
  return ENOMEM;
}

static void waitSetFree(WaitSet *s) {
  free(s->pfd); free(s->masks); free(s->donePid); free(s->doneCode);
}

static int timeoutArg(Val t, int64_t *out) {
  if (t.tag != T_INT || t.u.i < -1) return EINVAL;
  *out = t.u.i;
  return 0;
}

static Val bProcWaitAny(Val *a, int n) {
  (void)n;
  pid_t *pids;
  int np;
  int64_t tms;
  if (timeoutArg(a[1], &tms)) return errStr("io:22");
  int e = pidsArg(a[0], &pids, &np);
  if (e) return mapErrno(e);
  if (np == 0) return errStr("io:22");
  WaitSet s;
  e = waitSetAlloc(&s, 0, np);
  if (!e) {
    e = waitSet(&s, pids, np, tms, 0);
    if (e) waitSetFree(&s);
  }
  free(pids);
  if (e) return mapErrno(e);
  int got = s.nExited;
  pid_t pid = got ? s.donePid[0] : 0;
  int code = got ? s.doneCode[0] : 0;
  waitSetFree(&s);
  if (!got) return mkResult(1, mkCtor(KW_NONE, 0));
  Val p = mkPairVal(vint((int64_t)pid), vint((int64_t)code));
  asl_gc_root_push(&p);
  Val some = mkCtor(KW_SOME, 1);
  ((Ctor *)some.u.o)->f[0] = p;
  asl_gc_root_pop(1);
  return mkResult(1, some);
}

static Val bProcPoll(Val *a, int n) {
  (void)n;
  int64_t tms;
  if (a[0].tag != T_LIST || timeoutArg(a[2], &tms)) return errStr("io:22");
  int nUser = 0;
  for (Obj *x = a[0].u.o; x; x = ((Cons *)x)->cdr.u.o) nUser++;
  pid_t *pids;
  int np;
  int e = pidsArg(a[1], &pids, &np);
  if (e) return mapErrno(e);
  WaitSet s;
  if (waitSetAlloc(&s, nUser, np)) { free(pids); return errStr("io:12"); }
  int i = 0;
  for (Obj *x = a[0].u.o; x; x = ((Cons *)x)->cdr.u.o, i++) {
    int64_t fd, mask;
    int bad = fdPairArg(((Cons *)x)->car, &fd, &mask);
    if (!bad && (mask < 1 || mask > 3)) bad = 1;
    if (bad) { waitSetFree(&s); free(pids); return errStr(bad == 2 ? "badFd" : "io:22"); }
    s.pfd[i].fd = (int)fd;
    s.pfd[i].events = (short)(((mask & 1) ? POLLIN : 0) | ((mask & 2) ? POLLOUT : 0));
  }
  e = waitSet(&s, pids, np, tms, 1);
  free(pids);
  if (e) { waitSetFree(&s); return mapErrno(e); }
  Val fdsOut = VNIL, pidsOut = VNIL, p = VNIL;
  asl_gc_root_push(&fdsOut);
  asl_gc_root_push(&pidsOut);
  asl_gc_root_push(&p);
  for (int j = s.nReady - 1; j >= 0; j--) {
    int idx = (int)(s.masks[j] >> 3);
    p = mkPairVal(vint((int64_t)s.pfd[idx].fd), vint(s.masks[j] & 7));
    fdsOut = mkCons(p, fdsOut);
  }
  for (int j = s.nExited - 1; j >= 0; j--) {
    p = mkPairVal(vint((int64_t)s.donePid[j]), vint((int64_t)s.doneCode[j]));
    pidsOut = mkCons(p, pidsOut);
  }
  waitSetFree(&s);
  p = mkPairVal(fdsOut, pidsOut);
  asl_gc_root_pop(3);
  return mkResult(1, p);
}

static Val mkRecVals(const char *schema, int *keys, const char *const *fields, int n, Val *v) {
  if (!keys[n]) { for (int i = 0; i < n; i++) keys[i] = intern(fields[i], strlen(fields[i])); keys[n] = 1; }
  for (int i = 0; i < n; i++) asl_gc_root_push(&v[i]);
  Rec *r = asl_alloc(O_REC, sizeof(Rec) + sizeof(Val) * (size_t)n);
  asl_gc_root_pop(n);
  r->schema = intern(schema, strlen(schema)); r->n = n; r->keys = keys;
  for (int i = 0; i < n; i++) r->v[i] = v[i];
  return mkResult(1, vobj(T_REC, r));
}

static Val bCpuCount(Val *a, int n) {
  (void)a; (void)n; errno = 0;
  long c = sysconf(_SC_NPROCESSORS_ONLN);
  if (c < 1) return errno ? mapErrno(errno) : errStr("io:38");
  return mkResult(1, vint((int64_t)c));
}

#if defined(__APPLE__)
#define RSS_UNIT 1024
#else
#define RSS_UNIT 1
#endif
static int64_t maxRssKb(const struct rusage *u) { return (int64_t)u->ru_maxrss / RSS_UNIT; }
static int64_t cpuUs(struct timeval t) { return (int64_t)t.tv_sec * 1000000 + (int64_t)t.tv_usec; }

static Val bProcRusage(Val *a, int n) {
  (void)a; (void)n;
  struct rusage self, kids; static int keys[7];
  if (getrusage(RUSAGE_SELF, &self) < 0 || getrusage(RUSAGE_CHILDREN, &kids) < 0) return mapErrno(errno);
  static const char *const f[] = {"selfMaxRssKb", "selfUserUs", "selfSysUs", "childrenMaxRssKb", "childrenUserUs", "childrenSysUs"};
  Val v[6] = {vint(maxRssKb(&self)), vint(cpuUs(self.ru_utime)), vint(cpuUs(self.ru_stime)), vint(maxRssKb(&kids)), vint(cpuUs(kids.ru_utime)), vint(cpuUs(kids.ru_stime))};
  return mkRecVals("Rusage", keys, f, 6, v);
}

static Val bPlatformInfo(Val *a, int n) {
  (void)a; (void)n;
  struct utsname u; static int keys[4];
  if (uname(&u) < 0) return mapErrno(errno);
  static const char *const f[] = {"os", "release", "machine"};
  Val v[3] = {VUNIT, VUNIT, VUNIT};
  const char *src[3] = {u.sysname, u.release, u.machine};
  for (int i = 0; i < 3; i++) asl_gc_root_push(&v[i]);
  for (int i = 0; i < 3; i++) v[i] = mkStr(src[i], strlen(src[i]));
  asl_gc_root_pop(3);
  return mkRecVals("PlatformInfo", keys, f, 3, v);
}

static Val bLocalDate(Val *a, int n) {
  (void)a; (void)n;
  time_t now = time(NULL); struct tm tm; char buf[32];
  if (now == (time_t)-1) return mapErrno(errno);
  if (!localtime_r(&now, &tm)) return mapErrno(errno ? errno : EOVERFLOW);
  size_t len = strftime(buf, sizeof buf, "%Y-%m-%d", &tm);
  if (!len) return errStr("io:84");
  return mkResult(1, mkStr(buf, len));
}

static Val bProcAlive(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_INT || a[0].u.i <= 0 || a[0].u.i > INT_MAX) return errStr("io:22");
  int r = kill((pid_t)a[0].u.i, 0);
  if (r == 0 || errno == EPERM || errno == ESRCH) return mkResult(1, vbool(r == 0 || errno == EPERM));
  return mapErrno(errno);
}


const Builtin sysBuiltins[] = {
  {"fdRead", bFdRead, 2, 1}, {"fdWrite", bFdWrite, 2, 1},
  {"fdClose", bFdClose, 1, 1},
  {"fdPoll", bFdPoll, 2, 1},
  {"fdNonBlocking", bFdNonBlocking, 2, 1},
  {"fileLock", bFileLock, 2, 1},
  {"fileLockWait", bFileLockWait, -1, 1},
  {"fileAppend", bFileAppend, 2, 1},
  {"fileLockAt", bFileLockAt, 3, 1}, {"fileReadAt", bFileReadAt, 2, 1}, {"fileWriteAt", bFileWriteAt, 3, 1},
  {"procSpawnv", bProcSpawnv, 3, 1},
  {"procWaitPid", bProcWaitPid, 2, 1},
  {"procKill", bProcKill, 2, 1},
  {"procSelf", bProcSelf, 0, 1},
  {"procExePath", bProcExePath, 0, 1},
  {"procExecv", bProcExecv, 2, 1},
  {"envList", bEnvList, 0, 1},
  {"procWaitAny", bProcWaitAny, 2, 1},
  {"procPoll", bProcPoll, 3, 1},
  {"cpuCount", bCpuCount, 0, 1},
  {"procRusage", bProcRusage, 0, 1},
  {"platformInfo", bPlatformInfo, 0, 1},
  {"localDate", bLocalDate, 0, 1},
  {"procAlive?", bProcAlive, 1, 1},
};
const int nSysBuiltins = (int)(sizeof sysBuiltins / sizeof sysBuiltins[0]);

/* a native binary's call of one of these by name (asl-target-llvm builtinTableSym); referencing it links this table */
Val asl_rt_builtin_sys(const char *name, int64_t argc, Val *argv) { return builtinCallIn(sysBuiltins, nSysBuiltins, name, argc, argv); }
