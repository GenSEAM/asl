(module asl-target-llvm/libc
  :x [StructFacts TripleFacts RuntimeAbi libcTriples libcFacts libcVerified darwinArm64Facts linuxX8664Facts linuxAarch64Facts wasm32Facts runtimeAbi hostImport pairFind structFieldOffset structSize libcConst emptyTripleFacts rusageMaxRssUnit exePathSource]
  :i [])

schema StructFacts
  size: Int64
  fields: (List (Pair String Int64))

schema TripleFacts
  triple: String
  verified: Bool
  errnoAccessor: String
  consts: (List (Pair String Int64))
  variadic: (List (Pair String Bool))
  structs: (List (Pair String StructFacts))

schema RuntimeAbi
  triple: String
  memory: String
  output: String
  clock: String
  exit: String
  trap: String

fn libcTriples -> (List String)
  (list "darwin-arm64" "linux-x86_64" "linux-aarch64" "wasm32-unknown-unknown")

fn emptyTripleFacts -> TripleFacts
  (TripleFacts :triple "" :verified false :errnoAccessor "" :consts (list) :variadic (list) :structs (list))

fn pairFind xs: (List (Pair String V)) key: String -> (Option V)
  (fold (fn [(acc (Option V)) (p (Pair String V))] -> (Option V)
          (if (= (pairFirst p) key) (some (pairSecond p)) acc))
        (none) xs)

fn structFieldOffset sf: StructFacts field: String -> (Option Int64)
  (pairFind sf.fields field)

fn structSize facts: TripleFacts structName: String -> (Option Int64)
  (optionMap (fn [(sf StructFacts)] -> Int64 sf.size) (pairFind facts.structs structName))

fn libcConst facts: TripleFacts name: String -> (Option Int64)
  (pairFind facts.consts name)

fn rusageMaxRssUnit triple: String -> Int64
  (if (= triple "linux-x86_64") 1 (if (= triple "linux-aarch64") 1 1024))

fn exePathSource triple: String -> String
  (cond ((= triple "darwin-arm64") "nsGetExecutablePath")
        ((or (= triple "linux-x86_64") (= triple "linux-aarch64")) "procSelfExe")
        (else ""))

fn libcVerified triple: String -> Bool
  (mt (libcFacts triple) ((some f) f.verified) ((none) false))

fn darwinArm64Facts -> TripleFacts
  (TripleFacts
    :triple "darwin-arm64"
    :verified true
    :errnoAccessor "__error"
    :consts (list
      (pair "O_RDONLY" 0) (pair "O_WRONLY" 1) (pair "O_RDWR" 2) (pair "O_CREAT" 512)
      (pair "O_EXCL" 2048) (pair "O_TRUNC" 1024) (pair "O_APPEND" 8) (pair "O_NONBLOCK" 4)
      (pair "O_CLOEXEC" 16777216) (pair "O_DIRECTORY" 1048576) (pair "O_SYNC" 128)
      (pair "F_GETFL" 3) (pair "F_SETFL" 4) (pair "F_GETFD" 1) (pair "F_SETFD" 2)
      (pair "F_DUPFD" 0) (pair "F_DUPFD_CLOEXEC" 67) (pair "F_GETLK" 7) (pair "F_SETLK" 8) (pair "F_SETLKW" 9)
      (pair "LOCK_SH" 1) (pair "LOCK_EX" 2) (pair "LOCK_UN" 8) (pair "LOCK_NB" 4)
      (pair "EPERM" 1) (pair "ENOENT" 2) (pair "ESRCH" 3) (pair "EINTR" 4) (pair "EIO" 5) (pair "ENXIO" 6)
      (pair "EBADF" 9) (pair "EAGAIN" 35) (pair "ENOMEM" 12) (pair "EACCES" 13) (pair "EFAULT" 14)
      (pair "EBUSY" 16) (pair "EEXIST" 17) (pair "ENOTDIR" 20) (pair "EISDIR" 21) (pair "EINVAL" 22) (pair "ENOTEMPTY" 66) (pair "ESPIPE" 29) (pair "SEEK_SET" 0) (pair "SEEK_CUR" 1)
      (pair "ENFILE" 23) (pair "EMFILE" 24) (pair "ENOSPC" 28) (pair "EPIPE" 32) (pair "ERANGE" 34)
      (pair "ENOSYS" 78) (pair "ETIMEDOUT" 60) (pair "ECONNREFUSED" 61) (pair "ECHILD" 10)
      (pair "_SC_NPROCESSORS_ONLN" 58)
      (pair "POLLIN" 1) (pair "POLLOUT" 4) (pair "POLLNVAL" 32)
      (pair "RUSAGE_SELF" 0)
      (pair "S_IFMT" 61440) (pair "S_IFIFO" 4096) (pair "S_IFCHR" 8192) (pair "S_IFDIR" 16384)
      (pair "S_IFBLK" 24576) (pair "S_IFREG" 32768) (pair "S_IFLNK" 40960) (pair "S_IFSOCK" 49152)
      (pair "DT_UNKNOWN" 0) (pair "DT_FIFO" 1) (pair "DT_CHR" 2) (pair "DT_DIR" 4)
      (pair "DT_BLK" 6) (pair "DT_REG" 8) (pair "DT_LNK" 10) (pair "DT_SOCK" 12)
      (pair "AF_UNIX" 1) (pair "AF_INET" 2) (pair "SOCK_STREAM" 1)
      (pair "SOL_SOCKET" 65535) (pair "SO_REUSEADDR" 4) (pair "FD_CLOEXEC" 1) (pair "WNOHANG" 1) (pair "CLOCK_REALTIME" 0) (pair "CLOCK_MONOTONIC" 6) (pair "PATH_MAX" 1024)
      (pair "O_NOFOLLOW" 256) (pair "AT_FDCWD" -2) (pair "AT_SYMLINK_NOFOLLOW" 32) (pair "NAME_MAX" 255)
      (pair "ELOOP" 62) (pair "ENAMETOOLONG" 63) (pair "EWOULDBLOCK" 35)
      (pair "SIGPIPE" 13) (pair "SIG_DFL" 0) (pair "SIG_IGN" 1) (pair "SIG_BLOCK" 1) (pair "SIG_SETMASK" 3)
      (pair "RUSAGE_CHILDREN" -1) (pair "P_PID" 1) (pair "WEXITED" 4) (pair "WNOWAIT" 32)
      (pair "EVFILT_PROC" -5) (pair "EVFILT_SIGNAL" -6) (pair "NOTE_EXIT" 2147483648) (pair "EV_ADD" 1) (pair "EV_ONESHOT" 16) (pair "EV_ERROR" 16384)
      (pair "EROFS" 30) (pair "EOVERFLOW" 84) (pair "POLLPRI" 2) (pair "POLLERR" 8) (pair "POLLHUP" 16)
      (pair "SIGHUP" 1) (pair "SIGINT" 2) (pair "SIGQUIT" 3) (pair "SIGKILL" 9) (pair "SIGUSR1" 30) (pair "SIGUSR2" 31)
      (pair "SIGTERM" 15) (pair "SIGCONT" 19) (pair "SIGSTOP" 17) (pair "SIGWINCH" 28)
      (pair "PROT_READ" 1) (pair "PROT_WRITE" 2) (pair "MAP_PRIVATE" 2) (pair "MAP_ANON" 4096)
      (pair "SCM_RIGHTS" 1) (pair "MSG_CTRUNC" 32) (pair "EBADMSG" 94) (pair "EMSGSIZE" 40)
      (pair "CMSG_LEN_INT" 16) (pair "CMSG_SPACE_INT" 16) (pair "CMSG_DATA_OFFSET" 12))
    :variadic (list
      (pair "open" true) (pair "openat" true) (pair "fcntl" true) (pair "ioctl" true)
      (pair "flock" false) (pair "stat" false) (pair "lstat" false) (pair "fstat" false)
      (pair "uname" false) (pair "getrusage" false) (pair "gettimeofday" false)
      (pair "poll" false) (pair "readdir" false) (pair "mmap" false) (pair "munmap" false))
    :structs (list
      (pair "stat" (StructFacts :size 144 :fields (list
        (pair "st_dev" 0) (pair "st_ino" 8) (pair "st_mode" 4) (pair "st_nlink" 6)
        (pair "st_uid" 16) (pair "st_gid" 20) (pair "st_rdev" 24) (pair "st_size" 96)
        (pair "st_blksize" 112) (pair "st_blocks" 104)
        (pair "st_atimespec" 32) (pair "st_mtimespec" 48) (pair "st_ctimespec" 64))))
      (pair "flock" (StructFacts :size 24 :fields (list
        (pair "l_start" 0) (pair "l_len" 8) (pair "l_pid" 16) (pair "l_type" 20) (pair "l_whence" 22))))
      (pair "sockaddr_in" (StructFacts :size 16 :fields (list
        (pair "sin_family" 1) (pair "sin_port" 2) (pair "sin_addr" 4))))
      (pair "sockaddr_un" (StructFacts :size 106 :fields (list
        (pair "sun_family" 1) (pair "sun_path" 2))))
      (pair "utsname" (StructFacts :size 1280 :fields (list
        (pair "sysname" 0) (pair "nodename" 256) (pair "release" 512) (pair "version" 768) (pair "machine" 1024))))
      (pair "tm" (StructFacts :size 56 :fields (list
        (pair "tm_sec" 0) (pair "tm_min" 4) (pair "tm_hour" 8) (pair "tm_mday" 12) (pair "tm_mon" 16)
        (pair "tm_year" 20) (pair "tm_wday" 24) (pair "tm_yday" 28) (pair "tm_isdst" 32))))
      (pair "rusage" (StructFacts :size 144 :fields (list
        (pair "ru_utime" 0) (pair "ru_stime" 16) (pair "ru_maxrss" 32))))
      (pair "dirent" (StructFacts :size 1048 :fields (list
        (pair "d_ino" 0) (pair "d_reclen" 16) (pair "d_type" 20) (pair "d_name" 21))))
      (pair "pollfd" (StructFacts :size 8 :fields (list
        (pair "fd" 0) (pair "events" 4) (pair "revents" 6))))
      (pair "timespec" (StructFacts :size 16 :fields (list
        (pair "tv_sec" 0) (pair "tv_nsec" 8))))
      (pair "timeval" (StructFacts :size 16 :fields (list
        (pair "tv_sec" 0) (pair "tv_usec" 8))))
      (pair "passwd" (StructFacts :size 72 :fields (list
        (pair "pw_name" 0) (pair "pw_passwd" 8) (pair "pw_uid" 16) (pair "pw_gid" 20)
        (pair "pw_change" 24) (pair "pw_class" 32) (pair "pw_gecos" 40)
        (pair "pw_dir" 48) (pair "pw_shell" 56) (pair "pw_expire" 64))))
      (pair "posix_spawn_file_actions_t" (StructFacts :size 8 :fields (list)))
      (pair "pthread_attr_t" (StructFacts :size 64 :fields (list)))
      (pair "sigset_t" (StructFacts :size 4 :fields (list)))
      (pair "sigaction" (StructFacts :size 16 :fields (list
        (pair "sa_handler" 0) (pair "sa_mask" 8) (pair "sa_flags" 12))))
      (pair "siginfo_t" (StructFacts :size 104 :fields (list
        (pair "si_signo" 0) (pair "si_pid" 12))))
      (pair "kevent" (StructFacts :size 32 :fields (list
        (pair "ident" 0) (pair "filter" 8) (pair "flags" 10) (pair "fflags" 12) (pair "data" 16) (pair "udata" 24))))
      (pair "msghdr" (StructFacts :size 48 :fields (list
        (pair "msg_name" 0) (pair "msg_namelen" 8) (pair "msg_iov" 16) (pair "msg_iovlen" 24)
        (pair "msg_control" 32) (pair "msg_controllen" 40) (pair "msg_flags" 44))))
      (pair "cmsghdr" (StructFacts :size 12 :fields (list
        (pair "cmsg_len" 0) (pair "cmsg_level" 4) (pair "cmsg_type" 8))))
      (pair "iovec" (StructFacts :size 16 :fields (list
        (pair "iov_base" 0) (pair "iov_len" 8))))))

fn concatRows groups: (List (List (Pair String V))) -> (List (Pair String V))
  (fold (fn [(acc (List (Pair String V))) (xs (List (Pair String V)))] -> (List (Pair String V)) (listAppend acc xs)) (list) groups)

fn linuxErrnoBase -> (List (Pair String Int64))
  (list (pair "EPERM" 1) (pair "ENOENT" 2) (pair "ESRCH" 3) (pair "EINTR" 4) (pair "EIO" 5) (pair "ENXIO" 6)
        (pair "EBADF" 9) (pair "ECHILD" 10) (pair "EAGAIN" 11) (pair "ENOMEM" 12) (pair "EACCES" 13) (pair "EFAULT" 14)
        (pair "EBUSY" 16) (pair "EEXIST" 17) (pair "ENOTDIR" 20) (pair "EISDIR" 21) (pair "EINVAL" 22) (pair "ENFILE" 23)
        (pair "EMFILE" 24) (pair "ENOSPC" 28) (pair "ESPIPE" 29) (pair "EROFS" 30) (pair "EPIPE" 32) (pair "ERANGE" 34))

fn linuxErrno -> (List (Pair String Int64))
  (list (pair "ENAMETOOLONG" 36) (pair "ENOSYS" 38) (pair "ENOTEMPTY" 39) (pair "ELOOP" 40) (pair "EWOULDBLOCK" 11)
        (pair "EBADMSG" 74) (pair "EOVERFLOW" 75) (pair "EMSGSIZE" 90) (pair "ETIMEDOUT" 110) (pair "ECONNREFUSED" 111))

fn linuxGenericFcntl -> (List (Pair String Int64))
  (list (pair "O_RDONLY" 0) (pair "O_WRONLY" 1) (pair "O_RDWR" 2) (pair "O_CREAT" 64) (pair "O_EXCL" 128) (pair "O_TRUNC" 512)
        (pair "O_APPEND" 1024) (pair "O_NONBLOCK" 2048) (pair "O_CLOEXEC" 524288) (pair "O_SYNC" 1052672)
        (pair "F_DUPFD" 0) (pair "F_GETFD" 1) (pair "F_SETFD" 2) (pair "F_GETFL" 3) (pair "F_SETFL" 4)
        (pair "F_GETLK" 5) (pair "F_SETLK" 6) (pair "F_SETLKW" 7) (pair "FD_CLOEXEC" 1)
        (pair "LOCK_SH" 1) (pair "LOCK_EX" 2) (pair "LOCK_NB" 4) (pair "LOCK_UN" 8))

fn linuxX8664OpenFlags -> (List (Pair String Int64))
  (list (pair "O_DIRECTORY" 65536) (pair "O_NOFOLLOW" 131072))

fn linuxAarch64OpenFlags -> (List (Pair String Int64))
  (list (pair "O_DIRECTORY" 16384) (pair "O_NOFOLLOW" 32768))

fn linuxFcntl -> (List (Pair String Int64))
  (list (pair "F_DUPFD_CLOEXEC" 1030) (pair "AT_FDCWD" -100) (pair "AT_SYMLINK_NOFOLLOW" 256))

fn linuxSeek -> (List (Pair String Int64))
  (list (pair "SEEK_SET" 0) (pair "SEEK_CUR" 1))

fn linuxConfname -> (List (Pair String Int64))
  (list (pair "_SC_NPROCESSORS_ONLN" 84))

fn linuxPoll -> (List (Pair String Int64))
  (list (pair "POLLIN" 1) (pair "POLLPRI" 2) (pair "POLLOUT" 4) (pair "POLLERR" 8) (pair "POLLHUP" 16) (pair "POLLNVAL" 32))

fn linuxResource -> (List (Pair String Int64))
  (list (pair "RUSAGE_SELF" 0) (pair "RUSAGE_CHILDREN" -1))

fn linuxStatModes -> (List (Pair String Int64))
  (list (pair "S_IFMT" 61440) (pair "S_IFIFO" 4096) (pair "S_IFCHR" 8192) (pair "S_IFDIR" 16384)
        (pair "S_IFBLK" 24576) (pair "S_IFREG" 32768) (pair "S_IFLNK" 40960) (pair "S_IFSOCK" 49152))

fn linuxDirentTypes -> (List (Pair String Int64))
  (list (pair "DT_UNKNOWN" 0) (pair "DT_FIFO" 1) (pair "DT_CHR" 2) (pair "DT_DIR" 4)
        (pair "DT_BLK" 6) (pair "DT_REG" 8) (pair "DT_LNK" 10) (pair "DT_SOCK" 12))

fn linuxSocket -> (List (Pair String Int64))
  (list (pair "AF_UNIX" 1) (pair "AF_INET" 2) (pair "SCM_RIGHTS" 1) (pair "MSG_CTRUNC" 8) (pair "MSG_CMSG_CLOEXEC" 1073741824))

fn linuxCmsg -> (List (Pair String Int64))
  (list (pair "CMSG_LEN_INT" 20) (pair "CMSG_SPACE_INT" 24) (pair "CMSG_DATA_OFFSET" 16))

fn linuxSocketType -> (List (Pair String Int64))
  (list (pair "SOCK_STREAM" 1) (pair "SOCK_CLOEXEC" 524288))

fn linuxSocketLevel -> (List (Pair String Int64))
  (list (pair "SOL_SOCKET" 1) (pair "SO_REUSEADDR" 2))

fn linuxWait -> (List (Pair String Int64))
  (list (pair "WNOHANG" 1) (pair "WEXITED" 4) (pair "WNOWAIT" 16777216) (pair "P_PID" 1))

fn linuxClocks -> (List (Pair String Int64))
  (list (pair "CLOCK_REALTIME" 0) (pair "CLOCK_MONOTONIC" 1))

fn linuxLimits -> (List (Pair String Int64))
  (list (pair "PATH_MAX" 4096) (pair "NAME_MAX" 255))

fn linuxSignals -> (List (Pair String Int64))
  (list (pair "SIGHUP" 1) (pair "SIGINT" 2) (pair "SIGQUIT" 3) (pair "SIGKILL" 9) (pair "SIGUSR1" 10) (pair "SIGUSR2" 12)
        (pair "SIGPIPE" 13) (pair "SIGTERM" 15) (pair "SIGCONT" 18) (pair "SIGSTOP" 19) (pair "SIGWINCH" 28))

fn linuxSignalHandlers -> (List (Pair String Int64))
  (list (pair "SIG_DFL" 0) (pair "SIG_IGN" 1))

fn linuxSigprocmask -> (List (Pair String Int64))
  (list (pair "SIG_BLOCK" 0) (pair "SIG_SETMASK" 2))

fn linuxMmanCommon -> (List (Pair String Int64))
  (list (pair "PROT_READ" 1) (pair "PROT_WRITE" 2) (pair "MAP_ANON" 32))

fn linuxMman -> (List (Pair String Int64))
  (list (pair "MAP_PRIVATE" 2))

fn linuxSyscalls -> (List (Pair String Int64))
  (list (pair "SYS_pidfd_open" 434))

fn linuxSignalfd -> (List (Pair String Int64))
  (list (pair "SFD_CLOEXEC" 524288))

fn linuxCommonConsts -> (List (Pair String Int64))
  (concatRows (list (linuxErrnoBase) (linuxErrno) (linuxGenericFcntl) (linuxFcntl) (linuxSeek) (linuxConfname) (linuxPoll) (linuxResource)
                    (linuxStatModes) (linuxDirentTypes) (linuxSocket) (linuxCmsg) (linuxSocketType) (linuxSocketLevel) (linuxWait) (linuxClocks)
                    (linuxLimits) (linuxSignals) (linuxSignalHandlers) (linuxSigprocmask) (linuxMmanCommon) (linuxMman) (linuxSyscalls) (linuxSignalfd)))

fn linuxPthreadAttr size: Int64 -> (Pair String StructFacts)
  (pair "pthread_attr_t" (StructFacts :size size :fields (list)))

fn linuxX8664Stat -> (Pair String StructFacts)
  (pair "stat" (StructFacts :size 144 :fields (list
    (pair "st_dev" 0) (pair "st_ino" 8) (pair "st_nlink" 16) (pair "st_mode" 24)
    (pair "st_uid" 28) (pair "st_gid" 32) (pair "st_rdev" 40) (pair "st_size" 48)
    (pair "st_blksize" 56) (pair "st_blocks" 64)
    (pair "st_atimespec" 72) (pair "st_mtimespec" 88) (pair "st_ctimespec" 104))))

fn linuxAarch64Stat -> (Pair String StructFacts)
  (pair "stat" (StructFacts :size 128 :fields (list
    (pair "st_dev" 0) (pair "st_ino" 8) (pair "st_mode" 16) (pair "st_nlink" 20)
    (pair "st_uid" 24) (pair "st_gid" 28) (pair "st_rdev" 32) (pair "st_size" 48)
    (pair "st_blksize" 56) (pair "st_blocks" 64)
    (pair "st_atimespec" 72) (pair "st_mtimespec" 88) (pair "st_ctimespec" 104))))

fn linuxFlock -> (Pair String StructFacts)
  (pair "flock" (StructFacts :size 32 :fields (list
    (pair "l_type" 0) (pair "l_whence" 2) (pair "l_start" 8) (pair "l_len" 16) (pair "l_pid" 24))))

fn linuxSockaddrIn -> (Pair String StructFacts)
  (pair "sockaddr_in" (StructFacts :size 16 :fields (list
    (pair "sin_family" 0) (pair "sin_port" 2) (pair "sin_addr" 4))))

fn linuxSockaddrUn -> (Pair String StructFacts)
  (pair "sockaddr_un" (StructFacts :size 110 :fields (list
    (pair "sun_family" 0) (pair "sun_path" 2))))

fn linuxUtsname -> (Pair String StructFacts)
  (pair "utsname" (StructFacts :size 390 :fields (list
    (pair "sysname" 0) (pair "nodename" 65) (pair "release" 130) (pair "version" 195) (pair "machine" 260))))

fn linuxTm -> (Pair String StructFacts)
  (pair "tm" (StructFacts :size 56 :fields (list
    (pair "tm_sec" 0) (pair "tm_min" 4) (pair "tm_hour" 8) (pair "tm_mday" 12) (pair "tm_mon" 16)
    (pair "tm_year" 20) (pair "tm_wday" 24) (pair "tm_yday" 28) (pair "tm_isdst" 32))))

fn linuxRusage -> (Pair String StructFacts)
  (pair "rusage" (StructFacts :size 144 :fields (list
    (pair "ru_utime" 0) (pair "ru_stime" 16) (pair "ru_maxrss" 32))))

fn linuxDirent -> (Pair String StructFacts)
  (pair "dirent" (StructFacts :size 280 :fields (list
    (pair "d_ino" 0) (pair "d_reclen" 16) (pair "d_type" 18) (pair "d_name" 19))))

fn linuxPollfd -> (Pair String StructFacts)
  (pair "pollfd" (StructFacts :size 8 :fields (list
    (pair "fd" 0) (pair "events" 4) (pair "revents" 6))))

fn linuxTimespec -> (Pair String StructFacts)
  (pair "timespec" (StructFacts :size 16 :fields (list
    (pair "tv_sec" 0) (pair "tv_nsec" 8))))

fn linuxTimeval -> (Pair String StructFacts)
  (pair "timeval" (StructFacts :size 16 :fields (list
    (pair "tv_sec" 0) (pair "tv_usec" 8))))

fn linuxSpawnFileActions -> (Pair String StructFacts)
  (pair "posix_spawn_file_actions_t" (StructFacts :size 80 :fields (list)))

fn linuxSigset -> (Pair String StructFacts)
  (pair "sigset_t" (StructFacts :size 128 :fields (list)))

fn linuxSigaction -> (Pair String StructFacts)
  (pair "sigaction" (StructFacts :size 152 :fields (list
    (pair "sa_handler" 0) (pair "sa_mask" 8) (pair "sa_flags" 136))))

fn linuxSiginfo -> (Pair String StructFacts)
  (pair "siginfo_t" (StructFacts :size 128 :fields (list
    (pair "si_signo" 0) (pair "si_pid" 16))))

fn linuxSignalfdSiginfo -> (Pair String StructFacts)
  (pair "signalfd_siginfo" (StructFacts :size 128 :fields (list
    (pair "ssi_signo" 0))))

fn linuxPasswd -> (Pair String StructFacts)
  (pair "passwd" (StructFacts :size 48 :fields (list
    (pair "pw_name" 0) (pair "pw_passwd" 8) (pair "pw_uid" 16) (pair "pw_gid" 20)
    (pair "pw_gecos" 24) (pair "pw_dir" 32) (pair "pw_shell" 40))))

fn linuxMsghdr -> (Pair String StructFacts)
  (pair "msghdr" (StructFacts :size 56 :fields (list
    (pair "msg_name" 0) (pair "msg_namelen" 8) (pair "msg_iov" 16) (pair "msg_iovlen" 24)
    (pair "msg_control" 32) (pair "msg_controllen" 40) (pair "msg_flags" 48))))

fn linuxCmsghdr -> (Pair String StructFacts)
  (pair "cmsghdr" (StructFacts :size 16 :fields (list
    (pair "cmsg_len" 0) (pair "cmsg_level" 8) (pair "cmsg_type" 12))))

fn linuxIovec -> (Pair String StructFacts)
  (pair "iovec" (StructFacts :size 16 :fields (list
    (pair "iov_base" 0) (pair "iov_len" 8))))

fn linuxCommonStructs -> (List (Pair String StructFacts))
  (list (linuxFlock) (linuxSockaddrIn) (linuxSockaddrUn) (linuxUtsname) (linuxTm) (linuxRusage) (linuxDirent) (linuxPollfd)
        (linuxTimespec) (linuxTimeval) (linuxSpawnFileActions) (linuxSigset) (linuxSigaction) (linuxSiginfo) (linuxSignalfdSiginfo)
        (linuxPasswd) (linuxMsghdr) (linuxCmsghdr) (linuxIovec))

fn linuxCommonVariadic -> (List (Pair String Bool))
  (list
    (pair "open" true) (pair "openat" true) (pair "fcntl" true) (pair "ioctl" true)
    (pair "flock" false) (pair "stat" false) (pair "lstat" false) (pair "fstat" false)
    (pair "uname" false) (pair "getrusage" false) (pair "gettimeofday" false)
    (pair "poll" false) (pair "readdir" false) (pair "syscall" true) (pair "mmap" false) (pair "munmap" false))

fn linuxErrnoAccessor -> String
  "__errno_location"

fn linuxX8664Facts -> TripleFacts
  (TripleFacts
    :triple "linux-x86_64"
    :verified true
    :errnoAccessor (linuxErrnoAccessor)
    :consts (listAppend (linuxX8664OpenFlags) (linuxCommonConsts))
    :variadic (linuxCommonVariadic)
    :structs (cons (linuxPthreadAttr 56) (cons (linuxX8664Stat) (linuxCommonStructs))))

fn linuxAarch64Facts -> TripleFacts
  (TripleFacts
    :triple "linux-aarch64"
    :verified true
    :errnoAccessor (linuxErrnoAccessor)
    :consts (listAppend (linuxAarch64OpenFlags) (linuxCommonConsts))
    :variadic (linuxCommonVariadic)
    :structs (cons (linuxPthreadAttr 64) (cons (linuxAarch64Stat) (linuxCommonStructs))))

fn libcFacts triple: String -> (Option TripleFacts)
  (cond
    ((= triple "darwin-arm64") (some (darwinArm64Facts)))
    ((= triple "linux-x86_64") (some (linuxX8664Facts)))
    ((= triple "linux-aarch64") (some (linuxAarch64Facts)))
    ((= triple "wasm32-unknown-unknown") (some (wasm32Facts)))
    (else (none)))

fn wasm32Facts -> TripleFacts
  (TripleFacts :triple "wasm32-unknown-unknown" :verified false :errnoAccessor "" :consts (list) :variadic (list) :structs (list))

fn runtimeAbi triple: String -> (Option RuntimeAbi)
  (if (= triple "wasm32-unknown-unknown")
    (some (RuntimeAbi :triple triple :memory "memory.grow" :output "asl.write" :clock "asl.nowNs" :exit "asl.exit" :trap "asl.trap"))
    (none))

fn hostImport service: String -> (Pair String String)
  (mt (stringIndexOf service ".")
    ((some at) (pair (optionOr (stringSlice service 0 at) "") (optionOr (stringSlice service (+ at 1) (stringLength service)) "")))
    ((none) (pair "" service)))
