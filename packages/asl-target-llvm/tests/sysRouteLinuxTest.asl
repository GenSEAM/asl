(module asl-target-llvm/tests/sysRouteLinuxTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/parallel :a par)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/sysRoute :a rt)])

schema IrFact
  function: String
  local: String
  fact: String
  x8664: Int64
  aarch64: Int64
  darwin: Int64
  header: String

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn clang -> String
  "/usr/bin/clang"

fn linuxTriples -> (List String)
  (list "linux-x86_64" "linux-aarch64")

fn unameText triple: String -> String
  (cond ((= triple "linux-x86_64") "Linux x86_64\n")
        ((= triple "linux-aarch64") "Linux aarch64\n")
        ((= triple "darwin-arm64") "Darwin arm64\n")
        (else "Plan9 mips\n"))

fn llvmTriple triple: String -> String
  (cond ((= triple "linux-x86_64") "x86_64-unknown-linux-gnu")
        ((= triple "linux-aarch64") "aarch64-unknown-linux-gnu")
        (else "arm64-apple-darwin"))

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn arityRows text: String -> (List (Pair String Int64))
  (mt (stringIndexOf text "fn builtinArity name: String")
    ((none) (list))
    ((some start)
      (let [(body (optionOr (stringSlice text start (stringLength text)) ""))
            (table (optionOr (stringSlice body 0 (optionOr (stringIndexOf body "\n\nfn ") (stringLength body))) ""))]
        (map (fn [(p String)] -> (Pair String Int64)
               (let [(close (optionOr (stringIndexOf p "\"") -1))
                     (name (optionOr (stringSlice p 0 (max close 0)) ""))
                     (someAt (optionOr (stringIndexOf p "(some ") -1))
                     (rest (optionOr (stringSlice p (+ someAt 6) (stringLength p)) ""))]
                 (pair name
                       (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit rest ")")) ""))) -9))))
             (listDrop (stringSplit table "((= name \"") 1)))))

fn documentedGaps -> (List (Pair String String))
  (list)

fn operands n: Int64 -> String
  (stringJoin (map (fn [(k Int64)] -> String "0") (range 0 (if (< n 0) 1 n))) " ")

fn fixtureSrc rows: (List (Pair String Int64)) -> String
  (let [(numbered (enumerate rows))]
    (str "(module linuxAll :x [main] :i [])\n\n"
         (stringJoin (map (fn [(p (Pair Int64 (Pair String Int64)))] -> String
                            (str "fn ! b" (pairFirst p) " -> Int64\n  (do (" (pairFirst (pairSecond p)) " " (operands (pairSecond (pairSecond p))) ") 0)\n\n"))
                          numbered) "")
         "fn ! main -> Int64\n  (do\n"
         (stringJoin (map (fn [(p (Pair Int64 (Pair String Int64)))] -> String (str "    (b" (pairFirst p) ")\n")) numbered) "")
         "    0)\n"))

fn gapFunctions rows: (List (Pair String Int64)) -> (List String)
  (map (fn [(p (Pair Int64 (Pair String Int64)))] -> String (str "b" (pairFirst p)))
       (filter (fn [(p (Pair Int64 (Pair String Int64)))] -> Bool (some? (libc/pairFind (documentedGaps) (pairFirst (pairSecond p))))) (enumerate rows)))

fn diagFunction d: ty/IrDiag -> String
  (optionOr (listHead (stringSplit d.locus "@")) "")

fn ! nativeOnHost triple: String m: ty/SsaModule -> (Result String (List ty/IrDiag))
  (mt (rt/hostFactsOf (unameText triple))
    ((err e) (err (list (ty/makeIrDiag "ERR_TEST_UNAME" e triple))))
    ((ok found) (mt found
                  ((some facts) (llvm/emitLlvmProgramFor facts m (str m.name ".main")))
                  ((none) (llvm/emitLlvmProgram m (str m.name ".main"))))))

fn routedWrappers -> (List String)
  (listAppend
    (map (fn [(n String)] -> String (str "define internal tailcc %Val @" (ssa/llvmName (if (= n "fileLockWait") (str (rt/wrapperName n) "/1") (rt/wrapperName n))) "("))
         (fold (fn [(acc (List String)) (t rt/RouteTable)] -> (List String) (listAppend acc (rt/tableBuiltins t))) (list) (rt/routeTables)))
    (map (fn [(p (Pair String Int64))] -> String (str "define internal tailcc %Val @" (ssa/llvmName (par/wrapperName (pairFirst p) (pairSecond p))) "("))
         (list (pair "parMap" 3) (pair "parFold" 5))))

fn tripleOfFacts row: (Option libc/TripleFacts) -> (Option String)
  (optionMap (fn [(f libc/TripleFacts)] -> String f.triple) row)

fn hostTripleOf text: String -> (Option String)
  (mt (rt/hostFactsOf text) ((ok f) (tripleOfFacts f)) ((err e) (some e)))

fn ! testRouteFacts -> Bool
  (do (map (fn [(t String)] -> Bool
             (let [(row (rt/routeFactsFor t))]
               (do (assert (= (tripleOfFacts row) (some t)) (str "routeFactsFor " t " is its libc.asl row"))
                   (assert (= row (libc/libcFacts t)) (str "routeFactsFor " t " equals libcFacts " t))
                   (assert (= (optionMap (fn [(f libc/TripleFacts)] -> Bool f.verified) row) (some true)) (str t " row is marked verified"))
                   (assert (= (hostTripleOf (unameText t)) (some t)) (str "hostFactsOf " (unameText t) " routes for " t))
                   true)))
           (linuxTriples))
      (assert (= (rt/routeFactsFor "darwin-arm64") (some (libc/darwinArm64Facts))) "routeFactsFor darwin-arm64 is still its own row")
      (assert (= (hostTripleOf "Linux arm64\n") (some "linux-aarch64")) "uname machine arm64 on Linux routes for linux-aarch64")
      (assert (none? (rt/routeFactsFor "")) "a triple libc.asl lacks has no facts")
      (assert (= (rt/hostFactsOf (unameText "")) (ok (none))) "an unknown host stays unrouted")
      (assert (err? (rt/hostFactsOf "Linux")) "uname text that is not two words is an err")
      true)

fn ! checkLinuxIr triple: String text: String -> Bool
  (do (refute (stringContains? text "@asl_rt_builtin_") (str triple ": no call through a C builtin table, so libaslhost.a is not needed"))
      (map (fn [(w String)] -> Bool (do (assert (stringContains? text w) (str triple ": defines " w)) true)) (routedWrappers))
      (assert (stringContains? text "@__errno_location(") (str triple ": errno through glibc's __errno_location"))
      (refute (stringContains? text "@__error(") (str triple ": no darwin __error"))
      (refute (stringContains? text "@_NSGetEnviron(") (str triple ": no darwin _NSGetEnviron"))
      (refute (stringContains? text "@kevent(") (str triple ": no darwin kevent"))
      true)

fn ! objectFor work: String triple: String -> Bool
  (let [(ll (str work "/" triple ".ll"))
        (obj (str work "/" triple ".o"))
        (out (sh (str (clang) " -target " (llvmTriple triple) " -c -x ir " ll " -o " obj)))
        (kind (sh (str "file -b " obj)))]
    (do (assert (= out.exitCode 0) (str triple ": clang -target " (llvmTriple triple) " compiles the IR: " out.stderr))
        (assert (stringContains? kind.stdout "ELF 64-bit") (str triple ": the object is ELF 64-bit: " kind.stdout))
        true))

fn ! testBuiltins work: String rows: (List (Pair String Int64)) m: ty/SsaModule -> (List String)
  (fold (fn [(acc (List String)) (t String)] -> (List String)
          (mt (nativeOnHost t m)
            ((err ds) (let [(gaps (gapFunctions rows))
                            (stray (filter (fn [(d ty/IrDiag)] -> Bool (not (listContains? gaps (diagFunction d)))) ds))]
                        (do (assert (listEmpty? stray) (str t ": every builtin lowers or is a documented gap; failing: " (diagText stray)))
                            acc)))
            ((ok text) (do (assert (listEmpty? (gapFunctions rows)) (str t ": a documented gap lowers, so it is no longer a gap"))
                           (checkLinuxIr t text)
                           (assert (ok? (fileWrite (str work "/" t ".ll") text)) (str t ".ll written"))
                           (objectFor work t)
                           (listAppend acc (list t))))))
        (list) (linuxTriples))

fn factTable -> (List IrFact)
  (list (IrFact :function "asl-target-llvm/sysRoute.fdNonBlocking" :local "nb" :fact "O_NONBLOCK" :x8664 2048 :aarch64 2048 :darwin 4 :header "include/uapi/asm-generic/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileAppend" :local "flags.c1" :fact "O_CREAT" :x8664 64 :aarch64 64 :darwin 512 :header "include/uapi/asm-generic/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileAppend" :local "flags.c2" :fact "O_APPEND" :x8664 1024 :aarch64 1024 :darwin 8 :header "include/uapi/asm-generic/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileAppend" :local "flags.c3" :fact "O_CLOEXEC" :x8664 524288 :aarch64 524288 :darwin 16777216 :header "include/uapi/asm-generic/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileCreateExclusive" :local "oflags.c2" :fact "O_EXCL" :x8664 128 :aarch64 128 :darwin 2048 :header "include/uapi/asm-generic/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileWrite" :local "oflags.c2" :fact "O_TRUNC" :x8664 512 :aarch64 512 :darwin 1024 :header "include/uapi/asm-generic/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileParentAt" :local "rootFlags.c1" :fact "O_DIRECTORY" :x8664 65536 :aarch64 16384 :darwin 1048576 :header "include/uapi/asm-generic/fcntl.h; aarch64 arch/arm64/include/uapi/asm/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileReadAt" :local "flags.c1" :fact "O_NOFOLLOW" :x8664 131072 :aarch64 32768 :darwin 256 :header "include/uapi/asm-generic/fcntl.h; aarch64 arch/arm64/include/uapi/asm/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.procHighCloexec" :local "dupCmd" :fact "F_DUPFD_CLOEXEC" :x8664 1030 :aarch64 1030 :darwin 67 :header "include/uapi/linux/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileWriteAt" :local "noFollow" :fact "AT_SYMLINK_NOFOLLOW" :x8664 256 :aarch64 256 :darwin 32 :header "include/uapi/linux/fcntl.h")
        (IrFact :function "sysUtimensat" :local "dirfd" :fact "AT_FDCWD" :x8664 -100 :aarch64 -100 :darwin -2 :header "include/uapi/linux/fcntl.h")
        (IrFact :function "asl-target-llvm/sysRoute.errnoErr" :local "c0" :fact "EAGAIN" :x8664 11 :aarch64 11 :darwin 35 :header "include/uapi/asm-generic/errno-base.h")
        (IrFact :function "asl-target-llvm/sysRoute.fileIoKind" :local "exists.c1" :fact "ENOTEMPTY" :x8664 39 :aarch64 39 :darwin 66 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "asl-target-llvm/sysRoute.procIoErr" :local "eloop" :fact "ELOOP" :x8664 40 :aarch64 40 :darwin 62 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "asl-target-llvm/sysRoute.dirCreate" :local "enametoolong" :fact "ENAMETOOLONG" :x8664 36 :aarch64 36 :darwin 63 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "asl-target-llvm/sysRoute.procSpawnv" :local "enosys" :fact "ENOSYS" :x8664 38 :aarch64 38 :darwin 78 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "asl-target-llvm/sysRoute.localDate" :local "eoverflow" :fact "EOVERFLOW" :x8664 75 :aarch64 75 :darwin 84 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "sysNetRecvFd" :local "rf.emsgsize" :fact "EMSGSIZE" :x8664 90 :aarch64 90 :darwin 40 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "sysNetRecvFd" :local "rf.badmsg" :fact "EBADMSG" :x8664 74 :aarch64 74 :darwin 94 :header "include/uapi/asm-generic/errno.h")
        (IrFact :function "asl-target-llvm/sysRoute.dirCreate" :local "pathMax" :fact "PATH_MAX" :x8664 4096 :aarch64 4096 :darwin 1024 :header "include/uapi/linux/limits.h")
        (IrFact :function "asl-target-llvm/sysRoute.cpuCount" :local "name" :fact "_SC_NPROCESSORS_ONLN" :x8664 84 :aarch64 84 :darwin 58 :header "glibc bits/confname.h")
        (IrFact :function "asl-target-llvm/parallel.cpuCount" :local "name" :fact "_SC_NPROCESSORS_ONLN" :x8664 84 :aarch64 84 :darwin 58 :header "glibc bits/confname.h")
        (IrFact :function "asl-target-llvm/sysRoute.monotonicNs" :local "clock" :fact "CLOCK_MONOTONIC" :x8664 1 :aarch64 1 :darwin 6 :header "include/uapi/linux/time.h")
        (IrFact :function "asl-target-llvm/sysRoute.procKill" :local "num4" :fact "SIGUSR1" :x8664 10 :aarch64 10 :darwin 30 :header "arch/x86/include/uapi/asm/signal.h; include/uapi/asm-generic/signal.h")
        (IrFact :function "asl-target-llvm/sysRoute.procKill" :local "num5" :fact "SIGUSR2" :x8664 12 :aarch64 12 :darwin 31 :header "arch/x86/include/uapi/asm/signal.h; include/uapi/asm-generic/signal.h")
        (IrFact :function "asl-target-llvm/sysRoute.procKill" :local "num7" :fact "SIGCONT" :x8664 18 :aarch64 18 :darwin 19 :header "arch/x86/include/uapi/asm/signal.h; include/uapi/asm-generic/signal.h")
        (IrFact :function "asl-target-llvm/sysRoute.procKill" :local "num8" :fact "SIGSTOP" :x8664 19 :aarch64 19 :darwin 17 :header "arch/x86/include/uapi/asm/signal.h; include/uapi/asm-generic/signal.h")
        (IrFact :function "asl-target-llvm/sysRoute.procWaitFwd" :local "block" :fact "SIG_BLOCK" :x8664 0 :aarch64 0 :darwin 1 :header "glibc bits/sigaction.h")
        (IrFact :function "asl-target-llvm/sysRoute.procWaitFwd" :local "setmask" :fact "SIG_SETMASK" :x8664 2 :aarch64 2 :darwin 3 :header "glibc bits/sigaction.h")
        (IrFact :function "asl-target-llvm/sysRoute.procWaitFwd" :local "sfdFlags" :fact "SFD_CLOEXEC" :x8664 524288 :aarch64 524288 :darwin -1 :header "include/uapi/linux/signalfd.h")
        (IrFact :function "asl-target-llvm/sysRoute.procWatchOpen" :local "pidfdNr" :fact "SYS_pidfd_open" :x8664 434 :aarch64 434 :darwin -1 :header "arch/x86/entry/syscalls/syscall_64.tbl; include/uapi/asm-generic/unistd.h")
        (IrFact :function "sysNetRecvFd" :local "rf.solSocket" :fact "SOL_SOCKET" :x8664 1 :aarch64 1 :darwin 65535 :header "include/uapi/asm-generic/socket.h")
        (IrFact :function "sysNetRecvFd" :local "rf.ctrunc" :fact "MSG_CTRUNC" :x8664 8 :aarch64 8 :darwin 32 :header "glibc bits/socket.h")
        (IrFact :function "sysNetRecvFd" :local "rf.flags" :fact "MSG_CMSG_CLOEXEC" :x8664 1073741824 :aarch64 1073741824 :darwin -1 :header "glibc bits/socket.h")
        (IrFact :function "sysNetSendFd" :local "sf.cmsgLen" :fact "CMSG_LEN_INT" :x8664 20 :aarch64 20 :darwin 16 :header "glibc bits/socket.h CMSG_LEN")
        (IrFact :function "sysNetRecvFd" :local "rf.msgFlagsOff" :fact "msghdr.msg_flags" :x8664 48 :aarch64 48 :darwin 44 :header "glibc bits/socket.h")
        (IrFact :function "sysNetTcpListen" :local "tl.famOffC" :fact "sockaddr_in.sin_family" :x8664 0 :aarch64 0 :darwin 1 :header "glibc netinet/in.h, bits/sockaddr.h")
        (IrFact :function "sysNetUnixListen" :local "ul.famOffC" :fact "sockaddr_un.sun_family" :x8664 0 :aarch64 0 :darwin 1 :header "glibc sys/un.h, bits/sockaddr.h")
        (IrFact :function "sysLstat" :local "modeOffC" :fact "stat.st_mode" :x8664 24 :aarch64 16 :darwin 4 :header "glibc x86_64-linux-gnu and aarch64-linux-gnu bits/struct_stat.h")
        (IrFact :function "sysLstat" :local "sizeOffC" :fact "stat.st_size" :x8664 48 :aarch64 48 :darwin 96 :header "glibc bits/struct_stat.h")
        (IrFact :function "sysLstat" :local "mtimeSecOffC" :fact "stat.st_mtimespec" :x8664 88 :aarch64 88 :darwin 48 :header "glibc bits/struct_stat.h")
        (IrFact :function "sysLstat" :local "st.size" :fact "stat.size" :x8664 144 :aarch64 128 :darwin 144 :header "glibc x86_64-linux-gnu and aarch64-linux-gnu bits/struct_stat.h")
        (IrFact :function "asl-target-llvm/sysRoute.platformInfo" :local "size" :fact "utsname.size" :x8664 390 :aarch64 390 :darwin 1280 :header "glibc sys/utsname.h, bits/utsname.h _UTSNAME_LENGTH 65")
        (IrFact :function "asl-target-llvm/sysRoute.platformInfo" :local "cstr.release.fieldOff" :fact "utsname.release" :x8664 130 :aarch64 130 :darwin 512 :header "glibc sys/utsname.h")
        (IrFact :function "asl-target-llvm/sysRoute.platformInfo" :local "cstr.machine.fieldOff" :fact "utsname.machine" :x8664 260 :aarch64 260 :darwin 1024 :header "glibc sys/utsname.h")
        (IrFact :function "sysDirList" :local "dNameOff0" :fact "dirent.d_name" :x8664 19 :aarch64 19 :darwin 21 :header "glibc bits/dirent.h")
        (IrFact :function "asl-target-llvm/sysRoute.getHomeDir" :local "pwDirOff" :fact "passwd.pw_dir" :x8664 32 :aarch64 32 :darwin 48 :header "glibc pwd.h")
        (IrFact :function "asl-target-llvm/sysRoute.procExitScan" :local "siSize" :fact "siginfo_t.size" :x8664 128 :aarch64 128 :darwin 104 :header "glibc bits/types/siginfo_t.h")
        (IrFact :function "asl-target-llvm/sysRoute.procExitScan" :local "pidOff" :fact "siginfo_t.si_pid" :x8664 16 :aarch64 16 :darwin 12 :header "glibc bits/types/siginfo_t.h"))

fn want row: IrFact triple: String -> Int64
  (cond ((= triple "linux-x86_64") row.x8664)
        ((= triple "linux-aarch64") row.aarch64)
        (else row.darwin))

fn factValue facts: libc/TripleFacts name: String -> (Option Int64)
  (let [(parts (stringSplit name "."))]
    (if (= (listLength parts) 2)
      (let [(structName (optionOr (listGet parts 0) "")) (field (optionOr (listGet parts 1) ""))]
        (if (= field "size")
          (libc/structSize facts structName)
          (mt (libc/pairFind facts.structs structName)
            ((none) (none))
            ((some sf) (libc/structFieldOffset sf field)))))
      (libc/libcConst facts name)))

fn constScan -> String
  "/^define /{f=$0; sub(/[(].*/,\"\",f); sub(/.*@/,\"\",f)}\nmatch($0,/%[A-Za-z0-9$._]+ = bitcast i(32|64) -?[0-9]+ to/){s=substr($0,RSTART,RLENGTH); split(s,a,\" \"); n=a[1]; sub(/^%/,\"\",n); print f \"|\" n \" \" a[5]}\n"

fn ! irConsts work: String triple: String -> (Map String (List Int64))
  (let [(prog (str work "/constScan.awk"))
        (_ (assert (ok? (fileWrite prog (constScan))) "constScan.awk written"))
        (out (sh (str "awk -f " prog " " work "/" triple ".ll")))]
    (do (assert (= out.exitCode 0) (str triple ": awk scans the IR: " out.stderr))
        (fold (fn [(acc (Map String (List Int64))) (line String)] -> (Map String (List Int64))
                (let [(parts (stringSplit line " "))]
                  (mt (stringToInt64 (optionOr (listGet parts 1) ""))
                    ((none) acc)
                    ((some v) (let [(k (optionOr (listGet parts 0) ""))]
                                (mapSet acc k (listAppend (optionOr (mapGet acc k) (list)) (list v))))))))
              (mapEmpty) (stringLines out.stdout))))

fn ! testFacts work: String triple: String emitted: Bool -> Bool
  (mt (libc/libcFacts triple)
    ((none) (do (assert false (str "libcFacts " triple)) false))
    ((some facts)
      (let [(consts (if emitted (irConsts work triple) (mapEmpty)))]
        (do (map (fn [(row IrFact)] -> Bool
                   (let [(v (want row triple))
                         (key (str (ssa/llvmName row.function) "|" (ssa/llvmName row.local)))
                         (seen (mapGet consts key))]
                     (do (if (and (= triple "darwin-arm64") (= v -1))
                           (do (assert (none? (factValue facts row.fact)) (str triple " has no " row.fact " row")) true)
                           (do (assert (= (factValue facts row.fact) (some v)) (str triple " " row.fact " is " v " (" row.header "), libc.asl has " (factValue facts row.fact)))
                               (if emitted
                                 (do (assert (= seen (some (list v))) (str triple " IR " key " is " row.fact " " v ", emitted " seen)) true)
                                 true)))
                         true)))
                 (factTable))
            true))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))
        (src (str work "/linuxAll.asl"))
        (rows (mt (fileReadString "asl/packages/asl-ir/src/lower.asl") ((ok t) (arityRows t)) ((err e) (do (assert false (str "reads lower.asl: " e)) (list)))))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (> (listLength rows) 150) (str "builtinArity yields its rows, got " (listLength rows)))
        (assert (listAll? (fn [(r (Pair String Int64))] -> Bool (and (not (stringEmpty? (pairFirst r))) (>= (pairSecond r) -1))) rows) "every builtinArity row parses to a name and an arity")
        (assert (listContains? (map (fn [(r (Pair String Int64))] -> String (pairFirst r)) rows) "envGet") "builtinArity lists envGet")
        (testRouteFacts)
        (assert (ok? (fileWrite src (fixtureSrc rows))) (str "fileWrite " src))
        (mt (lk/linkEntry! src)
          ((err ds) (assert false (str "the builtin fixture links: " (diagText ds))))
          ((ok m)
            (let [(linux (testBuiltins work rows m))]
              (do (map (fn [(t String)] -> Bool (testFacts work t (listContains? linux t))) (linuxTriples))
                  (mt (llvm/emitLlvmProgramFor (libc/darwinArm64Facts) m (str m.name ".main"))
                    ((err ds) (assert false (str "darwin-arm64 emits: " (diagText ds))))
                    ((ok text) (do (assert (ok? (fileWrite (str work "/darwin-arm64.ll") text)) "darwin-arm64.ll written")
                                   (testFacts work "darwin-arm64" true))))
                  true))))
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
