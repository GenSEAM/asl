/* Test-only probe for asl/packages/asl-target-llvm/src/libc.asl (plan RT unit S1).
 * Prints one NAME=VALUE line per O_, F_, LOCK_, errno and _SC_NPROCESSORS_ONLN constant
 * and one sizeof_STRUCT=N or STRUCT.FIELD=OFFSET line per struct named in libcFacts, so
 * tests/libcTableTest.asl (darwin-arm64, on this host) and
 * tests/linuxLayoutGateTest.asl (linux-x86_64/linux-aarch64, via docker: RT unit LIBC-linuxLayoutGate)
 * can diff the table against the real libc headers of the triple each runs the probe on,
 * instead of hand-copied numbers. Portable across both: __APPLE__ picks Darwin's errno
 * accessor (__error) and stat timespec field names (st_atimespec/st_mtimespec/st_ctimespec)
 * over glibc's (__errno_location, st_atim/st_mtim/st_ctim) and <sys/dirent.h> over <dirent.h>;
 * the printed field names stay the darwin spelling on every triple, since libc.asl's own
 * struct rows use that spelling as a table key, not a real field name, for all three triples.
 */
#ifndef __APPLE__
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stddef.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <sys/un.h>
#include <sys/utsname.h>
#include <time.h>
#include <sys/resource.h>
#include <sys/time.h>
#ifdef __APPLE__
#include <sys/dirent.h>
#else
#include <dirent.h>
#endif
#include <poll.h>
#include <pwd.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>
#include <spawn.h>
#include <limits.h>
#include <signal.h>
#include <sys/mman.h>
#include <pthread.h>
#ifdef __APPLE__
#include <sys/event.h>
#else
#include <sys/syscall.h>
#include <sys/signalfd.h>
#endif

#define P(name, val) printf("%s=%lld\n", name, (long long)(val))

int main(void) {
  /* errno accessor probe: force a real failure, then confirm the real storage the
   * errno macro expands to (__error on darwin, __errno_location on glibc) is the
   * same storage the errno macro reads, instead of just restating its name as a string. */
  errno = 0;
  int badFd = open("/nonexistent/__libc_probe_errno_check__", O_RDONLY);
  int viaMacro = errno;
#ifdef __APPLE__
  int viaAccessor = *__error();
#else
  int viaAccessor = *__errno_location();
#endif
  P("errnoAccessorMatchesMacro", (badFd < 0 && viaMacro != 0 && viaMacro == viaAccessor) ? 1 : 0);

  P("O_RDONLY", O_RDONLY);
  P("O_WRONLY", O_WRONLY);
  P("O_RDWR", O_RDWR);
  P("O_CREAT", O_CREAT);
  P("O_EXCL", O_EXCL);
  P("O_TRUNC", O_TRUNC);
  P("O_APPEND", O_APPEND);
  P("O_NONBLOCK", O_NONBLOCK);
  P("O_CLOEXEC", O_CLOEXEC);
  P("O_DIRECTORY", O_DIRECTORY);
  P("O_SYNC", O_SYNC);
  P("F_GETFL", F_GETFL);
  P("F_SETFL", F_SETFL);
  P("F_GETFD", F_GETFD);
  P("F_SETFD", F_SETFD);
  P("F_DUPFD", F_DUPFD);
  P("F_DUPFD_CLOEXEC", F_DUPFD_CLOEXEC);
  P("F_GETLK", F_GETLK);
  P("F_SETLK", F_SETLK);
  P("F_SETLKW", F_SETLKW);
  P("LOCK_SH", LOCK_SH);
  P("LOCK_EX", LOCK_EX);
  P("LOCK_UN", LOCK_UN);
  P("LOCK_NB", LOCK_NB);
  P("EPERM", EPERM);
  P("ENOENT", ENOENT);
  P("ESRCH", ESRCH);
  P("EINTR", EINTR);
  P("EIO", EIO);
  P("ENXIO", ENXIO);
  P("EBADF", EBADF);
  P("EAGAIN", EAGAIN);
  P("ENOMEM", ENOMEM);
  P("EACCES", EACCES);
  P("EFAULT", EFAULT);
  P("EBUSY", EBUSY);
  P("EEXIST", EEXIST);
  P("ENOTEMPTY", ENOTEMPTY);
  P("ESPIPE", ESPIPE);
  P("SEEK_SET", SEEK_SET);
  P("SEEK_CUR", SEEK_CUR);
  P("ENOTDIR", ENOTDIR);
  P("EISDIR", EISDIR);
  P("EINVAL", EINVAL);
  P("ENFILE", ENFILE);
  P("EMFILE", EMFILE);
  P("ENOSPC", ENOSPC);
  P("EPIPE", EPIPE);
  P("ERANGE", ERANGE);
  P("ENOSYS", ENOSYS);
  P("ETIMEDOUT", ETIMEDOUT);
  P("ECONNREFUSED", ECONNREFUSED);
  P("ECHILD", ECHILD);
  P("_SC_NPROCESSORS_ONLN", _SC_NPROCESSORS_ONLN);

  P("sizeof_stat", sizeof(struct stat));
  P("stat.st_dev", offsetof(struct stat, st_dev));
  P("stat.st_ino", offsetof(struct stat, st_ino));
  P("stat.st_mode", offsetof(struct stat, st_mode));
  P("stat.st_nlink", offsetof(struct stat, st_nlink));
  P("stat.st_uid", offsetof(struct stat, st_uid));
  P("stat.st_gid", offsetof(struct stat, st_gid));
  P("stat.st_rdev", offsetof(struct stat, st_rdev));
  P("stat.st_size", offsetof(struct stat, st_size));
  P("stat.st_blksize", offsetof(struct stat, st_blksize));
  P("stat.st_blocks", offsetof(struct stat, st_blocks));
#ifdef __APPLE__
  P("stat.st_atimespec", offsetof(struct stat, st_atimespec));
  P("stat.st_mtimespec", offsetof(struct stat, st_mtimespec));
  P("stat.st_ctimespec", offsetof(struct stat, st_ctimespec));
#else
  P("stat.st_atimespec", offsetof(struct stat, st_atim));
  P("stat.st_mtimespec", offsetof(struct stat, st_mtim));
  P("stat.st_ctimespec", offsetof(struct stat, st_ctim));
#endif

  P("sizeof_flock", sizeof(struct flock));
  P("flock.l_start", offsetof(struct flock, l_start));
  P("flock.l_len", offsetof(struct flock, l_len));
  P("flock.l_pid", offsetof(struct flock, l_pid));
  P("flock.l_type", offsetof(struct flock, l_type));
  P("flock.l_whence", offsetof(struct flock, l_whence));

  P("sizeof_sockaddr_in", sizeof(struct sockaddr_in));
  P("sockaddr_in.sin_family", offsetof(struct sockaddr_in, sin_family));
  P("sockaddr_in.sin_port", offsetof(struct sockaddr_in, sin_port));
  P("sockaddr_in.sin_addr", offsetof(struct sockaddr_in, sin_addr));

  P("sizeof_sockaddr_un", sizeof(struct sockaddr_un));
  P("sockaddr_un.sun_family", offsetof(struct sockaddr_un, sun_family));
  P("sockaddr_un.sun_path", offsetof(struct sockaddr_un, sun_path));

  P("AF_UNIX", AF_UNIX);
  P("AF_INET", AF_INET);
  P("SOCK_STREAM", SOCK_STREAM);
  P("SOL_SOCKET", SOL_SOCKET);
  P("SO_REUSEADDR", SO_REUSEADDR);
  P("FD_CLOEXEC", FD_CLOEXEC);
#ifndef __APPLE__
  P("SOCK_CLOEXEC", SOCK_CLOEXEC);
#endif

  P("sizeof_utsname", sizeof(struct utsname));
  P("utsname.sysname", offsetof(struct utsname, sysname));
  P("utsname.nodename", offsetof(struct utsname, nodename));
  P("utsname.release", offsetof(struct utsname, release));
  P("utsname.version", offsetof(struct utsname, version));
  P("utsname.machine", offsetof(struct utsname, machine));

  P("sizeof_tm", sizeof(struct tm));
  P("tm.tm_sec", offsetof(struct tm, tm_sec));
  P("tm.tm_min", offsetof(struct tm, tm_min));
  P("tm.tm_hour", offsetof(struct tm, tm_hour));
  P("tm.tm_mday", offsetof(struct tm, tm_mday));
  P("tm.tm_mon", offsetof(struct tm, tm_mon));
  P("tm.tm_year", offsetof(struct tm, tm_year));
  P("tm.tm_wday", offsetof(struct tm, tm_wday));
  P("tm.tm_yday", offsetof(struct tm, tm_yday));
  P("tm.tm_isdst", offsetof(struct tm, tm_isdst));

  P("sizeof_rusage", sizeof(struct rusage));
  P("rusage.ru_utime", offsetof(struct rusage, ru_utime));
  P("rusage.ru_stime", offsetof(struct rusage, ru_stime));
  P("rusage.ru_maxrss", offsetof(struct rusage, ru_maxrss));

  P("sizeof_dirent", sizeof(struct dirent));
  P("dirent.d_ino", offsetof(struct dirent, d_ino));
  P("dirent.d_reclen", offsetof(struct dirent, d_reclen));
  P("dirent.d_type", offsetof(struct dirent, d_type));
  P("dirent.d_name", offsetof(struct dirent, d_name));

  P("sizeof_pollfd", sizeof(struct pollfd));
  P("pollfd.fd", offsetof(struct pollfd, fd));
  P("pollfd.events", offsetof(struct pollfd, events));
  P("pollfd.revents", offsetof(struct pollfd, revents));
  P("sizeof_passwd", sizeof(struct passwd));
  P("passwd.pw_name", offsetof(struct passwd, pw_name));
  P("passwd.pw_passwd", offsetof(struct passwd, pw_passwd));
  P("passwd.pw_uid", offsetof(struct passwd, pw_uid));
  P("passwd.pw_gid", offsetof(struct passwd, pw_gid));
#ifdef __APPLE__
  P("passwd.pw_change", offsetof(struct passwd, pw_change));
  P("passwd.pw_class", offsetof(struct passwd, pw_class));
#endif
  P("passwd.pw_gecos", offsetof(struct passwd, pw_gecos));
  P("passwd.pw_dir", offsetof(struct passwd, pw_dir));
  P("passwd.pw_shell", offsetof(struct passwd, pw_shell));
#ifdef __APPLE__
  P("passwd.pw_expire", offsetof(struct passwd, pw_expire));
#endif

  P("POLLIN", POLLIN);
  P("POLLOUT", POLLOUT);
  P("POLLNVAL", POLLNVAL);

  P("sizeof_timespec", sizeof(struct timespec));
  P("timespec.tv_sec", offsetof(struct timespec, tv_sec));
  P("timespec.tv_nsec", offsetof(struct timespec, tv_nsec));

  P("sizeof_timeval", sizeof(struct timeval));
  P("timeval.tv_sec", offsetof(struct timeval, tv_sec));
  P("timeval.tv_usec", offsetof(struct timeval, tv_usec));

  P("RUSAGE_SELF", RUSAGE_SELF);
  P("S_IFMT", S_IFMT);
  P("S_IFIFO", S_IFIFO);
  P("S_IFCHR", S_IFCHR);
  P("S_IFDIR", S_IFDIR);
  P("S_IFBLK", S_IFBLK);
  P("S_IFREG", S_IFREG);
  P("S_IFLNK", S_IFLNK);
  P("S_IFSOCK", S_IFSOCK);
  P("DT_UNKNOWN", DT_UNKNOWN);
  P("DT_FIFO", DT_FIFO);
  P("DT_CHR", DT_CHR);
  P("DT_DIR", DT_DIR);
  P("DT_BLK", DT_BLK);
  P("DT_REG", DT_REG);
  P("DT_LNK", DT_LNK);
  P("DT_SOCK", DT_SOCK);
  P("WNOHANG", WNOHANG);
  P("CLOCK_REALTIME", CLOCK_REALTIME);
  P("CLOCK_MONOTONIC", CLOCK_MONOTONIC);
  P("PROT_READ", PROT_READ);
  P("PROT_WRITE", PROT_WRITE);
  P("MAP_PRIVATE", MAP_PRIVATE);
  P("MAP_ANON", MAP_ANON);
  P("sizeof_posix_spawn_file_actions_t", sizeof(posix_spawn_file_actions_t));
  P("PATH_MAX", PATH_MAX);

  /* sysRoute's fileLockAt/fileReadAt/fileWriteAt safe walk and procSpawnv, procWaitPid, procWaitAny, procPoll and procRusage (SYSLOWER-b) */
  P("O_NOFOLLOW", O_NOFOLLOW);
  P("AT_FDCWD", AT_FDCWD);
  P("AT_SYMLINK_NOFOLLOW", AT_SYMLINK_NOFOLLOW);
  P("NAME_MAX", NAME_MAX);
  P("ELOOP", ELOOP);
  P("ENAMETOOLONG", ENAMETOOLONG);
  P("EWOULDBLOCK", EWOULDBLOCK);
  P("EROFS", EROFS);
  P("EOVERFLOW", EOVERFLOW);
  P("POLLPRI", POLLPRI);
  P("POLLERR", POLLERR);
  P("POLLHUP", POLLHUP);
  P("SIGHUP", SIGHUP);
  P("SIGINT", SIGINT);
  P("SIGQUIT", SIGQUIT);
  P("SIGKILL", SIGKILL);
  P("SIGUSR1", SIGUSR1);
  P("SIGUSR2", SIGUSR2);
  P("SIGTERM", SIGTERM);
  P("SIGCONT", SIGCONT);
  P("SIGSTOP", SIGSTOP);
  P("SIGWINCH", SIGWINCH);
  P("SIGPIPE", SIGPIPE);
  P("SIG_DFL", (long)SIG_DFL);
  P("SIG_IGN", (long)SIG_IGN);
  P("SIG_BLOCK", SIG_BLOCK);
  P("SIG_SETMASK", SIG_SETMASK);
  P("RUSAGE_CHILDREN", RUSAGE_CHILDREN);
  P("P_PID", P_PID);
  P("WEXITED", WEXITED);
  P("WNOWAIT", WNOWAIT);
  P("sizeof_sigset_t", sizeof(sigset_t));
  P("sizeof_sigaction", sizeof(struct sigaction));
  P("sigaction.sa_handler", offsetof(struct sigaction, sa_handler));
  P("sigaction.sa_mask", offsetof(struct sigaction, sa_mask));
  P("sigaction.sa_flags", offsetof(struct sigaction, sa_flags));
  P("sizeof_siginfo_t", sizeof(siginfo_t));
  P("sizeof_pthread_attr_t", sizeof(pthread_attr_t));
  P("siginfo_t.si_signo", offsetof(siginfo_t, si_signo));
  P("siginfo_t.si_pid", offsetof(siginfo_t, si_pid));
  /* sysNet's sysNetSendFd and sysNetRecvFd (FDHANDOFF): one int of SCM_RIGHTS over sendmsg/recvmsg */
  P("SCM_RIGHTS", SCM_RIGHTS);
  P("MSG_CTRUNC", MSG_CTRUNC);
  P("EBADMSG", EBADMSG);
  P("EMSGSIZE", EMSGSIZE);
  P("CMSG_LEN_INT", CMSG_LEN(sizeof(int)));
  P("CMSG_SPACE_INT", CMSG_SPACE(sizeof(int)));
  {
    union { struct cmsghdr h; char b[CMSG_SPACE(sizeof(int))]; } cm;
    P("CMSG_DATA_OFFSET", (char *)CMSG_DATA(&cm.h) - (char *)&cm.h);
  }
  P("sizeof_msghdr", sizeof(struct msghdr));
  P("msghdr.msg_name", offsetof(struct msghdr, msg_name));
  P("msghdr.msg_namelen", offsetof(struct msghdr, msg_namelen));
  P("msghdr.msg_iov", offsetof(struct msghdr, msg_iov));
  P("msghdr.msg_iovlen", offsetof(struct msghdr, msg_iovlen));
  P("msghdr.msg_control", offsetof(struct msghdr, msg_control));
  P("msghdr.msg_controllen", offsetof(struct msghdr, msg_controllen));
  P("msghdr.msg_flags", offsetof(struct msghdr, msg_flags));
  P("sizeof_cmsghdr", sizeof(struct cmsghdr));
  P("cmsghdr.cmsg_len", offsetof(struct cmsghdr, cmsg_len));
  P("cmsghdr.cmsg_level", offsetof(struct cmsghdr, cmsg_level));
  P("cmsghdr.cmsg_type", offsetof(struct cmsghdr, cmsg_type));
  P("sizeof_iovec", sizeof(struct iovec));
  P("iovec.iov_base", offsetof(struct iovec, iov_base));
  P("iovec.iov_len", offsetof(struct iovec, iov_len));
#ifdef __APPLE__
  P("EVFILT_PROC", EVFILT_PROC);
  P("EVFILT_SIGNAL", EVFILT_SIGNAL);
  P("NOTE_EXIT", NOTE_EXIT);
  P("EV_ADD", EV_ADD);
  P("EV_ONESHOT", EV_ONESHOT);
  P("EV_ERROR", EV_ERROR);
  P("sizeof_kevent", sizeof(struct kevent));
  P("kevent.ident", offsetof(struct kevent, ident));
  P("kevent.filter", offsetof(struct kevent, filter));
  P("kevent.flags", offsetof(struct kevent, flags));
  P("kevent.fflags", offsetof(struct kevent, fflags));
  P("kevent.data", offsetof(struct kevent, data));
  P("kevent.udata", offsetof(struct kevent, udata));
#else
  P("SYS_pidfd_open", SYS_pidfd_open);
  P("SFD_CLOEXEC", SFD_CLOEXEC);
  P("MSG_CMSG_CLOEXEC", MSG_CMSG_CLOEXEC);
  P("sizeof_signalfd_siginfo", sizeof(struct signalfd_siginfo));
  P("signalfd_siginfo.ssi_signo", offsetof(struct signalfd_siginfo, ssi_signo));
#endif
  return 0;
}
