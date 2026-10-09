#include "value.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/un.h>
#include <unistd.h>

static Val netErrno(void) {
  char b[32]; snprintf(b, sizeof b, "io:%d", errno); return mkResult(0, mkStr(b, strlen(b)));
}
static Val netBad(void) { return mkResult(0, mkStr("io:22", 5)); }
static int intArg(Val v, int64_t *out) { if (v.tag != T_INT) return 0; *out = v.u.i; return 1; }
static int stringArg(Val v, Str **out) { if (v.tag != T_STR) return 0; *out = (Str *)v.u.o; return 1; }
static int setCloexec(int fd) { int f = fcntl(fd, F_GETFD); return f >= 0 && fcntl(fd, F_SETFD, f | FD_CLOEXEC) >= 0; }
static int makeSocket(int domain, int type) {
  int fd;
#ifdef SOCK_CLOEXEC
  fd = socket(domain, type | SOCK_CLOEXEC, 0);
  if (fd >= 0 || errno != EINVAL) return fd;
#endif
  fd = socket(domain, type, 0);
  if (fd >= 0 && !setCloexec(fd)) { int e = errno; close(fd); errno = e; return -1; }
  return fd;
}
static int portArg(Val v, uint16_t *port) { int64_t n; if (!intArg(v, &n) || n < 0 || n > 65535) return 0; *port = (uint16_t)n; return 1; }
static Val bTcpListen(Val *a, int n) {
  (void)n; uint16_t port; if (!portArg(a[0], &port)) return netBad();
  int fd = makeSocket(AF_INET, SOCK_STREAM); if (fd < 0) return netErrno();
  struct sockaddr_in sa; memset(&sa, 0, sizeof sa); sa.sin_family = AF_INET; sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK); sa.sin_port = htons(port);
  if (bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0 || listen(fd, SOMAXCONN) < 0) { int e = errno; close(fd); errno = e; return netErrno(); }
  return mkResult(1, vint(fd));
}
static Val bTcpConnect(Val *a, int n) {
  (void)n; uint16_t port; if (!portArg(a[0], &port) || port == 0) return netBad();
  int fd = makeSocket(AF_INET, SOCK_STREAM); if (fd < 0) return netErrno();
  struct sockaddr_in sa; memset(&sa, 0, sizeof sa); sa.sin_family = AF_INET; sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK); sa.sin_port = htons(port);
  if (connect(fd, (struct sockaddr *)&sa, sizeof sa) < 0) { int e = errno; close(fd); errno = e; return netErrno(); }
  return mkResult(1, vint(fd));
}
static Val bSockAccept(Val *a, int n) {
  (void)n; int64_t raw; if (!intArg(a[0], &raw) || raw < 0 || raw > INT_MAX) return netBad();
  int fd = accept((int)raw, NULL, NULL); if (fd < 0) return netErrno();
  if (!setCloexec(fd)) { int e = errno; close(fd); errno = e; return netErrno(); }
  return mkResult(1, vint(fd));
}
static Val bSockLocalPort(Val *a, int n) {
  (void)n; int64_t raw; if (!intArg(a[0], &raw) || raw < 0 || raw > INT_MAX) return netBad();
  struct sockaddr_in sa; socklen_t len = sizeof sa; memset(&sa, 0, sizeof sa);
  if (getsockname((int)raw, (struct sockaddr *)&sa, &len) < 0) return netErrno();
  if (sa.sin_family != AF_INET || len < sizeof sa) return netBad();
  return mkResult(1, vint((int64_t)ntohs(sa.sin_port)));
}
static int unixAddr(Str *s, struct sockaddr_un *sa, socklen_t *len) {
  if (s->len == 0 || s->len >= sizeof sa->sun_path || memchr(s->s, 0, s->len)) return 0;
  memset(sa, 0, sizeof *sa); sa->sun_family = AF_UNIX; memcpy(sa->sun_path, s->s, s->len); sa->sun_path[s->len] = 0;
  *len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + s->len + 1); return 1;
}
static Val bUnixListen(Val *a, int n) {
  (void)n; Str *path; struct sockaddr_un sa; socklen_t len; if (!stringArg(a[0], &path) || !unixAddr(path, &sa, &len)) return netBad();
  int fd = makeSocket(AF_UNIX, SOCK_STREAM); if (fd < 0) return netErrno();
  mode_t old = umask(0177); int br = bind(fd, (struct sockaddr *)&sa, len); int e = errno; umask(old); errno = e;
  if (br < 0) { close(fd); return netErrno(); }
  if (listen(fd, SOMAXCONN) < 0) { e = errno; close(fd); errno = e; return netErrno(); }
  return mkResult(1, vint(fd));
}
static Val bUnixConnect(Val *a, int n) {
  (void)n; Str *path; struct sockaddr_un sa; socklen_t len; if (!stringArg(a[0], &path) || !unixAddr(path, &sa, &len)) return netBad();
  int fd = makeSocket(AF_UNIX, SOCK_STREAM); if (fd < 0) return netErrno();
  if (connect(fd, (struct sockaddr *)&sa, len) < 0) { int e = errno; close(fd); errno = e; return netErrno(); }
  return mkResult(1, vint(fd));
}

const Builtin sysNetBuiltins[] = {
  {"tcpListen", bTcpListen, 1, 1}, {"tcpConnect", bTcpConnect, 1, 1},
  {"sockAccept", bSockAccept, 1, 1}, {"sockLocalPort", bSockLocalPort, 1, 1},
  {"unixListen", bUnixListen, 1, 1}, {"unixConnect", bUnixConnect, 1, 1},
};
const int nSysNetBuiltins = (int)(sizeof sysNetBuiltins / sizeof sysNetBuiltins[0]);

/* a native binary's call of one of these by name (asl-target-llvm builtinTableSym); referencing it links this table */
Val asl_rt_builtin_sysNet(const char *name, int64_t argc, Val *argv) { return builtinCallIn(sysNetBuiltins, nSysNetBuiltins, name, argc, argv); }
