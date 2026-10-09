(module asl-target-llvm/tests/preludeProcRouteTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/sysProc :a proc)
      (asl-target-llvm/ssa :a ssa)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (mt (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "unsupported host triple: " (hostTriple))) (libc/emptyTripleFacts))))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn coreNames -> (List String)
  (list "processSpawn" "processWait" "processRun")

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn ! lowered src: String -> (Option ty/SsaModule)
  (let [(preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do (assert (not (stringEmpty? preludeText)) "host prelude is readable")
        (mt (lk/lowerSourceWith src preludeText)
          ((err ds) (do (assert false (str "lowerSourceWith: " (diagText ds))) (none)))
          ((ok m)
            (mt (rt/routeModule (hostFacts) m)
              ((err ds) (do (assert false (str "routeModule: " (diagText ds))) (none)))
              ((ok routed) (some routed.result)))))))

fn ! emit work: String name: String src: String -> String
  (do (assert (ok? (fileWrite (str work "/" name ".asl") src)) (str name " source written"))
      (mt (lowered src)
        ((none) "")
        ((some m)
          (mt (llvm/emitLlvmProgramFor (hostFacts) m "main")
            ((err ds) (do (assert false (str "emitLlvmProgramFor: " (diagText ds))) ""))
            ((ok ll) (do (assert (ok? (fileWrite (str work "/" name ".ll") ll)) (str name " IR written")) ll))))))

fn coreCall name: String -> String
  (str "@asl_rt_builtin(ptr @name." (ssa/llvmName name) ",")

fn ! checkIr ll: String -> Bool
  (do (assert (> (stringLength ll) 0) "native IR emitted")
      (map (fn [(n String)] -> Bool
        (do (assert (not (stringContains? ll (coreCall n))) (str n " not routed through asl_rt_builtin")) true)) (coreNames))
      true)

fn stdinCheckScript -> String
  (lines (list
    "import os, sys"
    "a = os.fstat(0)"
    "b = os.stat('/dev/null')"
    "sys.exit(0 if (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino) else 1)"))

fn ! source scriptPath: String -> String
  (lines (list
    "(module procRoute :x [main] :i [])"
    ""
    "fn ! show label: String r: ProcessOutput -> Bool"
    "  (do (println label r.exitCode r.stdout r.stderr) true)"
    ""
    "fn ! showWait label: String r: (Result ProcessOutput String) -> Bool"
    "  (do (mt r ((ok o) (println label \"ok\" o.exitCode o.stdout o.stderr)) ((err e) (println label \"err\" e))) true)"
    ""
    "fn ! showSpawn label: String r: (Result Int64 String) -> Int64"
    "  (mt r ((ok h) (do (println label \"ok\" h) h)) ((err e) (do (println label \"err\" e) -1)))"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (do"
    "    (show \"echo\" (processRun \"echo hello\"))"
    "    (show \"large\" (processRun \"python3 -c \\\"import os; [(os.write(1,b'O'*4096),os.write(2,b'E'*4096)) for _ in range(256)]\\\"\"))"
    "    (show \"exit3\" (processRun \"exit 3\"))"
    "    (show \"missing\" (processRun \"asl-PRELUDEASL-P-command-that-does-not-exist\"))"
    "    (show \"late\" (processRun \"(sleep 0.2; echo late) &\"))"
    "    (show \"signal\" (processRun \"kill -TERM $$\"))"
    "    (let [(h (showSpawn \"spawn\" (processSpawn \"echo spawned\")))]"
    "      (do (showWait \"wait\" (processWait h 0))"
    "          (showWait \"wait-again\" (processWait h 0))))"
    "    (let [(h (showSpawn \"timeout-spawn\" (processSpawn \"sleep 5\")))"
    "          (start (monotonicNs))"
    "          (r (processWait h 10))"
    "          (elapsed (- (monotonicNs) start))]"
    "      (do (showWait \"timeout\" r)"
    "          (println \"timeout-before-grace\" (< elapsed 1500000000))))"
    "    (showWait \"grace\" (processWait (showSpawn \"grace-spawn\" (processSpawn \"trap '' TERM; sleep 1; echo survived\")) 300))"
    "    (showWait \"grace-kill\" (processWait (showSpawn \"grace-kill-spawn\" (processSpawn \"trap '' TERM; sleep 4; echo late\")) 300))"
    "    (showWait \"invented\" (processWait 987654321 0))"
    "    (showSpawn \"bad-spawn\" (processSpawn 5))"
    "    (showWait \"bad-handle\" (processWait \"x\" 0))"
    "    (showWait \"bad-timeout\" (processWait 1 \"y\"))"
    "    (showSpawn \"nul-spawn\" (processSpawn \"echo\\x00hi\"))"
    "    (let [(ha (showSpawn \"multi-a\" (processSpawn \"sleep 0.3; echo a\")))"
    "          (hb (showSpawn \"multi-b\" (processSpawn \"sleep 0.1; echo b\")))"
    "          (hc (showSpawn \"multi-c\" (processSpawn \"sleep 0.2; echo c\")))]"
    "      (do (showWait \"multi-b-wait\" (processWait hb 2000))"
    "          (showWait \"multi-a-wait\" (processWait ha 2000))"
    "          (showWait \"multi-c-wait\" (processWait hc 2000))))"
    (str "    (showWait \"stdin-devnull\" (processWait (showSpawn \"stdin-spawn\" (processSpawn \"python3 " scriptPath " && echo devnull-yes || echo devnull-no\")) 2000))")
    "    (ok 0))"))

fn ! setup work: String -> Bool
  (do (assert (ok? (dirCreate work)) "test work directory created")
      (assert (ok? (fileWrite (str work "/parentStdin.txt") "not /dev/null\n")) "parent stdin fixture written")
      true)

fn ! buildNative work: String name: String -> ProcessOutput
  (sh (str (clang) " -x ir " work "/" name ".ll -x none " (lib) " -lm -o " work "/" name))

fn ! runNative work: String name: String prefix: String -> ProcessOutput
  (sh (str prefix "ASL_SPAWN_LOG=" work "/native.log " work "/" name " < " work "/parentStdin.txt"))

fn ! runHost work: String name: String prefix: String -> ProcessOutput
  (sh (str prefix "ASL_SPAWN_LOG=" work "/host.log " (host) " run " work "/" name ".asl < " work "/parentStdin.txt"))

fn ! fileText path: String -> String
  (resultOr (fileRead path) (str "<read error: " path ">"))

fn ! testParity work: String -> Bool
  (let [(scriptPath (str work "/stdinCheck.py"))
        (scriptWritten (fileWrite scriptPath (stdinCheckScript)))
        (src (source scriptPath))
        (ll (emit work "procRoute" src))]
    (do (assert (ok? scriptWritten) "stdin check script written")
        (assert (checkIr ll) "process IR bypasses core builtins")
        (let [(expected (runHost work "procRoute" ""))]
          (do (assert (= expected.exitCode 0) "host source completed")
              (assert (stringContains? expected.stdout "\nsignal 143  \n") "host reports SIGTERM death as 128+15")
              (assert (stringContains? expected.stdout "\ntimeout-before-grace true\n") "host timed processWait returns before the SIGTERM grace deadline")
              (assert (stringContains? expected.stdout "\ngrace ok 124 survived\n \n") "host lets a SIGTERM-ignoring group finish inside the 2 s grace before SIGKILL")
              (assert (stringContains? expected.stdout "\ngrace-kill ok 124  \n") "host SIGKILLs a SIGTERM-ignoring group once the 2 s grace runs out")
              (assert (stringContains? expected.stdout "\nbad-spawn err processSpawn: -: invalid argument\n") "host formats a non-String processSpawn command as formatErr")
              (assert (stringContains? expected.stdout "\nbad-timeout err processWait: -: invalid argument\n") "host formats a non-Int processWait argument as formatErr")
              (assert (stringContains? expected.stdout "\nnul-spawn err invalidPath: processSpawn: Invalid argument\n") "host rejects a command with an embedded NUL byte before forking")
              (assert (stringContains? expected.stdout "\nmulti-b-wait ok 0 b\n \n") "host waits a middle-of-list handle first among several live handles")
              (assert (stringContains? expected.stdout "\nmulti-a-wait ok 0 a\n \n") "host waits the oldest (tail) handle after removing a middle one")
              (assert (stringContains? expected.stdout "\nmulti-c-wait ok 0 c\n \n") "host waits the newest (head) handle last, after both others are gone")
              (assert (stringContains? expected.stdout "\nstdin-devnull ok 0 devnull-yes\n \n") "host redirects a spawned process's stdin to /dev/null, verified by the child's own fstat identity check, independent of the test process's own stdin")
              (let [(built (buildNative work "procRoute"))]
                (do (assert (= built.exitCode 0) "native IR compiled")
                    (let [(native (runNative work "procRoute" ""))]
                      (do (assert (= native.exitCode expected.exitCode) "native exit matches host")
                          (assert (= native.stdout expected.stdout) "native stdout matches host")
                          (assert (= native.stderr expected.stderr) "native stderr matches host")
                          (let [(nativePath (str work "/native.log"))
                                (hostPath (str work "/host.log"))
                                (nativeLog (fileText nativePath))
                                (hostLog (fileText hostPath))]
                            (do (assert (not (= nativeLog (str "<read error: " nativePath ">"))) "native spawn log was readable")
                                (assert (not (= hostLog (str "<read error: " hostPath ">"))) "host spawn log was readable")
                                (assert (= nativeLog hostLog) "ASL_SPAWN_LOG lines match byte-for-byte")))
                          true))))))))

fn ioShimSource -> String
  (lines (list
    "#define _GNU_SOURCE"
    "#include <errno.h>"
    "#include <fcntl.h>"
    "#include <poll.h>"
    "#include <stdio.h>"
    "#include <stdlib.h>"
    "#include <string.h>"
    "#include <unistd.h>"
    "#ifdef __APPLE__"
    "#define realPoll poll"
    "#define realRead read"
    "#define realFwrite fwrite"
    "#define realFree free"
    "#else"
    "#include <dlfcn.h>"
    "extern void __libc_free(void *);"
    "static int realPoll(struct pollfd *f, nfds_t n, int t) { static int (*p)(struct pollfd *, nfds_t, int); if (!p) p = dlsym(RTLD_NEXT, \"poll\"); return p(f, n, t); }"
    "static ssize_t realRead(int fd, void *b, size_t n) { static ssize_t (*p)(int, void *, size_t); if (!p) p = dlsym(RTLD_NEXT, \"read\"); return p(fd, b, n); }"
    "static size_t realFwrite(const void *b, size_t s, size_t n, FILE *f) { static size_t (*p)(const void *, size_t, size_t, FILE *); if (!p) p = dlsym(RTLD_NEXT, \"fwrite\"); return p(b, s, n, f); }"
    "static void realFree(void *q) { __libc_free(q); }"
    "#endif"
    "static void *eintrBuf;"
    "static int eintrFreed;"
    "static int pollSeen;"
    "static int pollPipes[2];"
    "static void mark(const char *s) { if (write(2, s, strlen(s)) < 0) _exit(71); }"
    "static int mode(const char *m) { const char *v = getenv(\"ASL_IO_SHIM\"); return v != NULL && strcmp(v, m) == 0; }"
    "static int shimPoll(struct pollfd *f, nfds_t n, int t) {"
    "  if (!mode(\"poll\")) return realPoll(f, n, t);"
    "  mark(\"pollShim\\n\");"
    "  if (!pollSeen && n == 2) { pollPipes[0] = f[0].fd; pollPipes[1] = f[1].fd; pollSeen = 1; }"
    "  errno = EINVAL;"
    "  return -1;"
    "}"
    "static ssize_t shimRead(int fd, void *b, size_t n) {"
    "  if (eintrBuf == NULL && fd > 2 && n == 4096 && mode(\"readEintr\")) { eintrBuf = b; mark(\"readShim eintr\\n\"); errno = EINTR; return -1; }"
    "  return realRead(fd, b, n);"
    "}"
    "static size_t shimFwrite(const void *b, size_t s, size_t n, FILE *f) {"
    "  if (f != stdout && f != stderr && mode(\"fwrite\")) { mark(\"fwriteShim\\n\"); return 0; }"
    "  return realFwrite(b, s, n, f);"
    "}"
    "static void shimFree(void *q) { if (q != NULL && q == eintrBuf) eintrFreed = 1; realFree(q); }"
    "static int fdClosed(int fd) { return fcntl(fd, F_GETFD) < 0 && errno == EBADF; }"
    "__attribute__((destructor)) static void report(void) {"
    "  if (eintrBuf != NULL) mark(eintrFreed ? \"readShim freed\\n\" : \"readShim leaked\\n\");"
    "  if (pollSeen) mark(fdClosed(pollPipes[0]) && fdClosed(pollPipes[1]) ? \"pollShim pipes closed\\n\" : \"pollShim pipes open\\n\");"
    "}"
    "#ifdef __APPLE__"
    "struct interpose { const void *replacement; const void *replacee; };"
    "__attribute__((used)) static const struct interpose interposers[] __attribute__((section(\"__DATA,__interpose\"))) = {"
    "  {(const void *)shimPoll, (const void *)poll}, {(const void *)shimRead, (const void *)read},"
    "  {(const void *)shimFwrite, (const void *)fwrite}, {(const void *)shimFree, (const void *)free}};"
    "#else"
    "int poll(struct pollfd *f, nfds_t n, int t) { return shimPoll(f, n, t); }"
    "ssize_t read(int fd, void *b, size_t n) { return shimRead(fd, b, n); }"
    "size_t fwrite(const void *b, size_t s, size_t n, FILE *f) { return shimFwrite(b, s, n, f); }"
    "void free(void *q) { shimFree(q); }"
    "#endif"))

fn runSource name: String cmd: String -> String
  (lines (list
    (str "(module " name " :x [main] :i [])")
    ""
    "fn ! main -> (Result Int64 String)"
    (str "  (let [(r (processRun \"" cmd "\"))]")
    (str "    (do (println \"" name "\" r.exitCode r.stdout r.stderr)")
    "        (ok 0)))"))

fn ! preloadPrefix shim: String mode: String -> String
  (str "ASL_IO_SHIM=" mode " "
    (if (stringStartsWith? (hostTriple) "darwin") (str "DYLD_INSERT_LIBRARIES=" shim " ") (str "LD_PRELOAD=" shim " ")))

fn ! buildShim work: String -> String
  (let [(src (str work "/ioShim.c"))
        (shim (str work "/ioShim.so"))
        (shared (if (stringStartsWith? (hostTriple) "darwin") "-dynamiclib" "-shared -fPIC -ldl"))]
    (do (assert (ok? (fileWrite src (ioShimSource))) "io shim source written")
        (let [(built (sh (str "/usr/bin/clang " shared " " src " -o " shim)))]
          (do (assert (= built.exitCode 0) (str "io shim compiled: " built.stderr)) shim))))

fn ! buildRun work: String name: String cmd: String -> Bool
  (let [(ll (emit work name (runSource name cmd)))]
    (do (assert (> (stringLength ll) 0) (str name " native IR emitted"))
        (let [(built (buildNative work name))]
          (do (assert (= built.exitCode 0) (str name " native IR compiled")) true))))

fn ! testPollFailure work: String shim: String -> Bool
  (let [(prefix (preloadPrefix shim "poll"))]
    (do (buildRun work "pollFail" "exit 7")
        (let [(expected (runHost work "pollFail" prefix))
              (native (runNative work "pollFail" prefix))]
          (do (assert (= expected.exitCode 0) "host completed under failing poll")
              (assert (stringContains? expected.stderr "pollShim\n") "host processRun called the failing poll")
              (assert (stringContains? expected.stderr "pollShim pipes closed\n") "host closed both pipes after poll failed")
              (assert (= expected.stdout "pollFail 7  \n") "host reaped the child after poll failed")
              (assert (= native.exitCode expected.exitCode) "native exit matches host under failing poll")
              (assert (= native.stdout expected.stdout) "native stdout matches host under failing poll")
              (assert (stringContains? native.stderr "pollShim pipes closed\n") "native closed both pipes after poll failed")
              (assert (= native.stderr expected.stderr) "native stderr matches host under failing poll")
              true))))

fn stderrOnly -> String
  "echo hi >&2; sleep 0.2"

fn ! testReadInterrupted work: String shim: String name: String cmd: String line: String -> Bool
  (do (buildRun work name cmd)
      (let [(expected (runHost work name ""))
            (native (runNative work name (preloadPrefix shim "readEintr")))]
        (do (assert (= expected.stdout line) (str name " host captured the child output"))
            (assert (stringContains? native.stderr "readShim eintr\n") (str name " native processRun read was interrupted"))
            (assert (= native.exitCode 0) (str name " native completed after the interrupted read"))
            (assert (= native.stdout expected.stdout) (str name " native output survives the interrupted read"))
            (assert (stringContains? native.stderr "readShim freed\n") (str name " native freed the interrupted read buffer"))
            true)))

fn ! testCaptureWriteFailure work: String shim: String name: String cmd: String -> Bool
  (do (buildRun work name cmd)
      (let [(native (runNative work name (preloadPrefix shim "fwrite")))]
        (do (assert (stringContains? native.stderr "fwriteShim\n") (str name " native processRun wrote into the failing capture stream"))
            (assert (not (= native.exitCode 0)) (str name " native fails when captured output cannot be stored"))
            (assert (stringContains? native.stderr "processRun: out of memory") (str name " native reports the capture failure as out of memory"))
            (assert (not (stringContains? native.stdout name)) (str name " native returns no truncated ProcessOutput"))
            true)))

fn ! testExternsCalled -> Bool
  (let [(facts (hostFacts))
        (pool (fold (fn [(m (Map String Int64)) (s String)] -> (Map String Int64) (mapSet m s (mapSize m))) (mapEmpty) (proc/procRouteStrings)))]
    (mt (proc/procRouteFunctions facts pool)
      ((err e) (do (assert false (str "procRouteFunctions: " e)) false))
      ((ok fs)
        (let [(called (fold functionCalls (list) fs))]
          (do (assert (> (listLength called) 0) "procRouteFunctions make direct calls")
              (map (fn [(x ty/SsaExtern)] -> Bool
                (do (assert (listContains? called x.name) (str "procRouteExterns " x.name " is called")) true)) (proc/procRouteExterns facts))
              true)))))

fn factReads text: String -> (List String)
  (fold (fn [(acc (List String)) (chunk String)] -> (List String)
          (mt (listGet (stringSplit chunk "\"") 0)
            ((some n) (if (or (stringContains? n ".") (listContains? acc n)) acc (cons n acc)))
            ((none) acc)))
        (list) (listDrop (stringSplit text "(kf k \"") 1))

fn ! testFactsDeclared -> Bool
  (let [(path "asl/packages/asl-target-llvm/src/sysProc.asl")
        (text (fileText path))
        (reads (factReads text))
        (declared (fold (fn [(acc (List String)) (triple String)] -> (List String)
                          (mt (libc/libcFacts triple)
                            ((some f) (listAppend acc (proc/procFactNames f)))
                            ((none) (do (assert false (str "libc facts for " triple)) acc))))
                        (list) (list "darwin-arm64" "linux-x86_64" "linux-aarch64")))]
    (do (assert (> (listLength reads) 0) "sysProc.asl reads libc facts through kf")
        (assert (listContains? reads "SIGKILL") "sysProc.asl reads SIGKILL through kf")
        (map (fn [(n String)] -> Bool (do (assert (listContains? declared n) (str "procFactNames declares " n)) true)) reads)
        true))

fn instrCalls acc: (List String) i: ty/SsaInstr -> (List String)
  (mt i.op ((ty/opCall n _) (cons n acc)) (_ acc))

fn functionCalls acc: (List String) f: ty/SsaFunction -> (List String)
  (fold (fn [(a (List String)) (b ty/SsaBlock)] -> (List String) (fold instrCalls a b.instrs)) acc f.blocks)

fn findByName name: String fs: (List ty/SsaFunction) -> (Option ty/SsaFunction)
  (fold (fn [(acc (Option ty/SsaFunction)) (f ty/SsaFunction)] -> (Option ty/SsaFunction) (if (= f.name name) (some f) acc)) (none) fs)

fn findBlock label: String bs: (List ty/SsaBlock) -> (Option ty/SsaBlock)
  (fold (fn [(acc (Option ty/SsaBlock)) (b ty/SsaBlock)] -> (Option ty/SsaBlock) (if (= b.label label) (some b) acc)) (none) bs)

fn instrByDest name: String instrs: (List ty/SsaInstr) -> (Option ty/SsaInstr)
  (fold (fn [(acc (Option ty/SsaInstr)) (i ty/SsaInstr)] -> (Option ty/SsaInstr) (if (= i.dest name) (some i) acc)) (none) instrs)

fn constStrIndex op: ty/SsaOp -> (Option Int64)
  (mt op
    ((ty/opConst c) (mt c ((ty/constStr idx) (some idx)) (_ (none))))
    (_ (none)))

fn globalDestNamed f: ty/SsaFunction namePart: String -> (Option String)
  (fold (fn [(acc (Option String)) (b ty/SsaBlock)] -> (Option String)
          (fold (fn [(acc2 (Option String)) (i ty/SsaInstr)] -> (Option String)
                  (mt i.op ((ty/opGlobal g) (if (stringContains? g namePart) (some i.dest) acc2)) (_ acc2)))
                acc b.instrs))
        (none) f.blocks)

fn unboxDestOf f: ty/SsaFunction v: String -> (Option String)
  (fold (fn [(acc (Option String)) (b ty/SsaBlock)] -> (Option String)
          (fold (fn [(acc2 (Option String)) (i ty/SsaInstr)] -> (Option String)
                  (mt i.op ((ty/opUnbox u) (if (= u v) (some i.dest) acc2)) (_ acc2)))
                acc b.instrs))
        (none) f.blocks)

fn eqIntDestOn f: ty/SsaFunction v: String -> (Option String)
  (fold (fn [(acc (Option String)) (b ty/SsaBlock)] -> (Option String)
          (fold (fn [(acc2 (Option String)) (i ty/SsaInstr)] -> (Option String)
                  (mt i.op ((ty/opPrim n args) (if (and (= n "eqInt") (listContains? args v)) (some i.dest) acc2)) (_ acc2)))
                acc b.instrs))
        (none) f.blocks)

fn branchBlockOn f: ty/SsaFunction cond: String -> (Option ty/SsaBlock)
  (fold (fn [(acc (Option ty/SsaBlock)) (b ty/SsaBlock)] -> (Option ty/SsaBlock)
          (mt b.term ((ty/termBranch c _ _) (if (= c cond) (some b) acc)) (_ acc)))
        (none) f.blocks)

fn argIsOomConst instrs: (List ty/SsaInstr) oomIdx: Int64 a: String -> Bool
  (mt (instrByDest a instrs)
    ((some ai) (= (optionOr (constStrIndex ai.op) -998) oomIdx))
    ((none) false))

fn callIsFormatErrOom instrs: (List ty/SsaInstr) oomIdx: Int64 i: ty/SsaInstr -> Bool
  (mt i.op
    ((ty/opCall callee args)
      (and (stringContains? callee "processFormatErr")
           (fold (fn [(hit Bool) (a String)] -> Bool (if hit true (argIsOomConst instrs oomIdx a))) false args)))
    (_ false))

fn blockHasFormatErrOom pool: (Map String Int64) instrs: (List ty/SsaInstr) -> Bool
  (let [(oomIdx (optionOr (mapGet pool "out of memory") -999))]
    (fold (fn [(found Bool) (i ty/SsaInstr)] -> Bool (if found true (callIsFormatErrOom instrs oomIdx i))) false instrs))

fn reachesFormatErrOom f: ty/SsaFunction pool: (Map String Int64) label: String fuel: Int64 -> Bool
  (if (<= fuel 0) false
    (mt (findBlock label f.blocks)
      ((none) false)
      ((some b)
        (if (blockHasFormatErrOom pool b.instrs) true
          (mt b.term
            ((ty/termJump e) (reachesFormatErrOom f pool e.target (- fuel 1)))
            (_ false))))))

fn ! testWaitStateGuard -> Bool
  (let [(facts (hostFacts))
        (pool (fold (fn [(m (Map String Int64)) (s String)] -> (Map String Int64) (mapSet m s (mapSize m))) (mapEmpty) (proc/procRouteStrings)))]
    (mt (proc/procRouteFunctions facts pool)
      ((err e) (do (assert false (str "procRouteFunctions: " e)) false))
      ((ok fs)
        (mt (findByName "asl-target-llvm/sysRoute.processWait" fs)
          ((none) (do (assert false "processWait is present in procRouteFunctions") false))
          ((some f)
            (mt (globalDestNamed f "processHandleState")
              ((none) (do (assert false "processWait reads the processHandleState global") false))
              ((some g)
                (mt (unboxDestOf f g)
                  ((none) (do (assert false "processWait unboxes the processHandleState global value") false))
                  ((some stateId)
                    (mt (eqIntDestOn f stateId)
                      ((none) (do (assert false "processWait compares the unboxed state value with eqInt") false))
                      ((some cond)
                        (mt (branchBlockOn f cond)
                          ((none) (do (assert false "processWait branches on the state-missing comparison") false))
                          ((some b)
                            (mt b.term
                              ((ty/termBranch _ thenE elseE)
                                (do (assert (or (reachesFormatErrOom f pool thenE.target 4) (reachesFormatErrOom f pool elseE.target 4))
                                            "one arm of the state-missing branch reaches processFormatErr(processWait, -, out of memory) instead of dereferencing the state pointer")
                                    true))
                              (_ (do (assert false "the state-missing comparison's block ends in a two-way branch") false))))))))))))))))

fn ! cleanup work: String -> Bool
  (do (assert (ok? (pathRemove work)) "test work directory removed")
      (assert (err? (dirList work)) "test work directory is gone")
      true)

fn ! runTests -> Bool
  (let [(work (str "/tmp/preludeProcRouteTest-" (nowNs)))]
    (do (testExternsCalled)
        (testFactsDeclared)
        (testWaitStateGuard)
        (setup work)
        (testParity work)
        (let [(shim (buildShim work))]
          (do (testPollFailure work shim)
              (testReadInterrupted work shim "readEintr" "echo hi" "readEintr 0 hi\n \n")
              (testReadInterrupted work shim "readEintrErr" (stderrOnly) "readEintrErr 0  hi\n\n")
              (testCaptureWriteFailure work shim "fwriteFail" "echo hi")
              (testCaptureWriteFailure work shim "fwriteFailErr" (stderrOnly))))
        (cleanup work)))
