(module asl-target-llvm/tests/sysRouteTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/sysRoute :a rt)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn hostLib -> String
  "asl/host/out/libaslhost.a"

fn probeEnv -> String
  "env SYSROUTE_PROBE='sysRoute 42' "

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
    ((none) (do (assert false (str "hostFacts: libc.asl has no row for this host's triple \"" (hostTriple) "\"")) (libc/emptyTripleFacts))))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn fdSource -> String
  (lines (list
    "(module sysFd :x [main] :i [])"
    ""
    "fn label fd: Int64 r: Int64 w: Int64 -> String"
    "  (cond ((= fd r) \"r\") ((= fd w) \"w\") (else \"other\"))"
    ""
    "fn ! shape res: (Result (List (Pair Int64 Int64)) String) r: Int64 w: Int64 -> String"
    "  (mt res"
    "    ((err e) (str \"err \" e))"
    "    ((ok ready) (str \"ok\" (fold (fn [(acc String) (p (Pair Int64 Int64))] -> String (mt p ((pair fd m) (str acc \" \" (label fd r w) \":\" m)))) \"\" ready))))"
    ""
    "fn dup s: String k: Int64 -> String"
    "  (if (= k 0) s (dup (str s s) (- k 1)))"
    ""
    "fn ! readAll r: Int64 want: Int64 acc: String -> String"
    "  (if (>= (stringLength acc) want)"
    "    acc"
    "    (mt (fdRead r (- want (stringLength acc)))"
    "      ((err e) (str acc \"<err \" e \">\"))"
    "      ((ok s) (if (= (stringLength s) 0) acc (readAll r want (str acc s))))))"
    ""
    "fn ! bigTrip w: Int64 r: Int64 -> String"
    "  (mt (fdWrite w (dup \"x\" 16))"
    "    ((err e) (str \"write err \" e))"
    "    ((ok n) (str (> n 0) \" \" (= (stringLength (readAll r n \"\")) n))))"
    ""
    "fn ! pipeChecks w: Int64 r: Int64 pid: Int64 -> (Result Int64 String)"
    "  (do (println \"write empty\" (fdWrite w \"\"))"
    "      (println \"read zero\" (fdRead r 0))"
    "      (println \"poll idle 0\" (shape (fdPoll (list (pair r 1)) 0) r w))"
    "      (println \"poll idle 50\" (shape (fdPoll (list (pair r 1)) 50) r w))"
    "      (println \"poll writable\" (shape (fdPoll (list (pair w 2)) 0) r w))"
    "      (println \"write one\" (fdWrite w \"y\"))"
    "      (println \"poll readable\" (shape (fdPoll (list (pair r 1)) 5000) r w))"
    "      (println \"poll both\" (shape (fdPoll (list (pair r 1) (list w 2 9)) 0) r w))"
    "      (println \"read one\" (fdRead r 1))"
    "      (println \"nonblocking on\" (fdNonBlocking r true))"
    "      (println \"read empty pipe\" (fdRead r 1))"
    "      (println \"nonblocking off\" (fdNonBlocking r false))"
    "      (println \"nonblocking w\" (fdNonBlocking w true))"
    "      (println \"big round trip\" (bigTrip w r))"
    "      (println \"close w\" (fdClose w))"
    "      (println \"read eof\" (fdRead r 4))"
    "      (println \"wait cat\" (procWaitPid pid false))"
    "      (println \"close r\" (fdClose r))"
    "      (println \"read closed\" (fdRead r 1))"
    "      (println \"write closed\" (fdWrite r \"z\"))"
    "      (println \"close closed\" (fdClose r))"
    "      (println \"poll closed\" (shape (fdPoll (list (pair r 1)) 0) r w))"
    "      (println \"nonblocking closed\" (fdNonBlocking r true))"
    "      (println \"fd -1\" (fdRead -1 1) (fdClose -1) (fdWrite -1 \"x\") (fdNonBlocking -1 true))"
    "      (println \"fd 999999\" (fdRead 999999 1) (fdClose 999999) (fdWrite 999999 \"x\") (fdNonBlocking 999999 true))"
    "      (println \"fd 2147483648\" (fdRead 2147483648 1) (fdClose 2147483648) (fdWrite 2147483648 \"x\"))"
    "      (println \"bad max\" (fdRead 0 -1) (fdRead 0 16777217))"
    "      (println \"bad types\" (fdRead 1.5 1) (fdRead 0 \"1\") (fdWrite 1 5) (fdWrite \"1\" \"x\") (fdClose \"3\") (fdNonBlocking 0 1) (fdNonBlocking 0.0 true))"
    "      (println \"poll args\" (fdPoll 5 0) (fdPoll (list) -2) (fdPoll (list) 0) (fdPoll (list) 50) (fdPoll (list 1 2) 0) (fdPoll (list) \"0\"))"
    "      (println \"poll items\" (fdPoll (list (pair -1 1)) 0) (fdPoll (list (pair 2147483648 1)) 0) (fdPoll (list (list 0)) 0) (fdPoll (list (some 1)) 0) (fdPoll (list (pair 0 \"1\")) 0) (fdPoll (list (list 1.5 1)) 0))"
    "      (println \"poll big timeout\" (shape (fdPoll (list (pair 999999 1)) 3000000000) 0 0))"
    "      (println \"poll shapes\" (fdPoll () 0) (fdPoll () -2) (fdPoll (list :a 1) 0) (fdPoll (list (list :a 1)) 0) (fdPoll (list true) 0) (fdPoll :a 0))"
    "      (ok 0))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (mt (procSpawnv (list \"/bin/cat\") (none) (none))"
    "    ((err e) (do (println \"procSpawnv\" e) (ok 1)))"
    "    ((ok child) (pipeChecks child.stdin child.stdout child.pid)))"))

fn infoSource -> String
  (lines (list
    "(module sysInfo :x [main] :i [])"
    ""
    "fn ! readAll fd: Int64 acc: String -> String"
    "  (mt (fdRead fd 4096)"
    "    ((err e) (str acc \"<err \" e \">\"))"
    "    ((ok s) (if (= (stringLength s) 0) acc (readAll fd (str acc s)))))"
    ""
    "fn ! childOut argv: (List String) -> String"
    "  (mt (procSpawnv argv (none) (none))"
    "    ((err e) (str \"spawn err \" e))"
    "    ((ok c) (let [(out (readAll c.stdout \"\"))]"
    "              (do (procWaitPid c.pid false) (fdClose c.stdout) (fdClose c.stdin) (fdClose c.stderr) out))))"
    ""
    "fn ! reapedPid -> Int64"
    "  (mt (procSpawnv (list \"/usr/bin/true\") (none) (none))"
    "    ((err e) -1)"
    "    ((ok c) (do (procWaitPid c.pid false) (fdClose c.stdout) (fdClose c.stdin) (fdClose c.stderr) c.pid)))"
    ""
    "fn joinLines xs: (List String) -> String"
    "  (fold (fn [(acc String) (x String)] -> String (str acc x \"\\n\")) \"\" xs)"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(self (procSelf))"
    "        (gone (reapedPid))"
    "        (env (envList))]"
    "    (do (println \"cpuCount is getconf\" (mt (cpuCount) ((ok c) (= (str c \"\\n\") (childOut (list \"/usr/bin/getconf\" \"_NPROCESSORS_ONLN\")))) ((err e) e)))"
    "        (println \"platformInfo\" (platformInfo))"
    "        (println \"platformInfo is uname\" (mt (platformInfo) ((ok p) (= (str p.os \" \" p.release \" \" p.machine \"\\n\") (childOut (list \"/usr/bin/uname\" \"-s\" \"-r\" \"-m\")))) ((err e) e)))"
    "        (println \"localDate is date\" (mt (localDate) ((ok d) (= (str d \"\\n\") (childOut (list \"/bin/date\" \"+%Y-%m-%d\")))) ((err e) e)))"
    "        (println \"envList has probe\" (listContains? env \"SYSROUTE_PROBE=sysRoute 42\"))"
    "        (println \"envList is env\" (= (joinLines env) (childOut (list \"/usr/bin/env\"))))"
    "        (println \"procSelf is sh's parent\" (= (str self \"\\n\") (childOut (list \"/bin/sh\" \"-c\" \"echo $PPID\"))))"
    "        (println \"procAlive? self\" (procAlive? self))"
    "        (println \"procAlive? reaped\" (procAlive? gone))"
    "        (println \"procAlive? 1\" (procAlive? 1))"
    "        (println \"procAlive? bad\" (procAlive? 0) (procAlive? -3) (procAlive? 2147483648) (procAlive? \"1\"))"
    "        (println \"procKill self\" (procKill self \"SIGCONT\") (procKill self \"SIGWINCH\"))"
    "        (println \"procKill reaped\" (procKill gone \"SIGTERM\"))"
    "        (println \"procKill bad\" (procKill self \"SIGFOO\") (procKill self \"\") (procKill 1 \"SIGTERM\") (procKill -1 \"SIGTERM\") (procKill 0 \"SIGTERM\") (procKill 2147483648 \"SIGTERM\") (procKill -2147483648 \"SIGTERM\") (procKill self 15) (procKill \"1\" \"SIGTERM\"))"
    "        (println \"procExePath ok\" (ok? (procExePath)))"
    "        (eprintln (mt (procExePath) ((ok p) p) ((err e) e)))"
    "        (ok 0)))"))

fn fileSource -> String
  (lines (list
    "(module sysFile :x [main] :i [])"
    ""
    "fn ! shape res: (Result Int64 String) -> String"
    "  (mt res"
    "    ((ok fd) (do (fdClose fd) \"ok\"))"
    "    ((err e) (str \"err \" e)))"
    ""
    "fn ! child self: String rest: String -> String"
    "  (stringReplace (processRun (str self \" '\" self \"' \" rest)).stdout \"\\n\" \"\")"
    ""
    "fn dup s: String k: Int64 -> String"
    "  (if (= k 0) s (dup (str s s) (- k 1)))"
    ""
    "fn ! decoys dir: String pid: Int64 from: Int64 upto: Int64 -> Bool"
    "  (if (> from upto)"
    "    true"
    "    (do (fileWrite (str dir \"/.asl-write-\" pid \"-\" from) \"decoy\")"
    "        (decoys dir pid (+ from 1) upto)))"
    ""
    "fn ! lockChecks self: String d: String -> Bool"
    "  (let [(p (str d \"/lk\"))"
    "        (nul \"a\\u{0}b\")"
    "        (long (str d \"/\" (dup \"x\" 13)))]"
    "    (do (println \"lock ok\" (shape (fileLock p true)) (shape (fileLock p false)))"
    "        (println \"lock held\" (mt (fileLock p true)"
    "                               ((ok fd) (let [(ex (child self (str \"lock \" p \" true\")))"
    "                                              (sh (child self (str \"lock \" p \" false\")))]"
    "                                          (do (fdClose fd) (str ex \" / \" sh))))"
    "                               ((err e) (str \"err \" e))))"
    "        (println \"lock released\" (child self (str \"lock \" p \" true\")))"
    "        (println \"lock shared\" (mt (fileLock p false)"
    "                                 ((ok fd) (let [(sh (child self (str \"lock \" p \" false\")))"
    "                                                (ex (child self (str \"lock \" p \" true\")))]"
    "                                            (do (fdClose fd) (str sh \" / \" ex))))"
    "                                 ((err e) (str \"err \" e))))"
    "        (println \"lock bad\" (fileLock 5 true) (fileLock p 1) (fileLock nul true) (fileLock (str d \"/sub\") true) (fileLock (str d \"/nodir/x\") true) (fileLock long true))"
    "        (println \"wait free\" (shape (fileLockWait p)) (shape (fileLockWait p false)) (shape (fileLockWait p 50)) (shape (fileLockWait p (some 50)))"
    "                 (shape (fileLockWait p (none))) (shape (fileLockWait p true (some 50))) (shape (fileLockWait p false (none)))"
    "                 (shape (fileLockWait p true -1)) (shape (fileLockWait p true 0)) (shape (fileLockWait p true 1125899906842625)))"
    "        (println \"wait held\" (mt (fileLock p true)"
    "                               ((ok fd) (let [(a (child self (str \"wait \" p \" true 0\")))"
    "                                              (b (child self (str \"wait \" p \" true 150\")))"
    "                                              (c (child self (str \"wait \" p \" false 30\")))]"
    "                                          (do (fdClose fd) (str a \" / \" b \" / \" c))))"
    "                               ((err e) (str \"err \" e))))"
    "        (println \"wait shared\" (mt (fileLock p false)"
    "                                 ((ok fd) (let [(a (child self (str \"wait \" p \" false 100\")))"
    "                                                (b (child self (str \"wait \" p \" true 40\")))]"
    "                                            (do (fdClose fd) (str a \" / \" b))))"
    "                                 ((err e) (str \"err \" e))))"
    "        (println \"wait bad\" (fileLockWait) (fileLockWait p true 1 2) (fileLockWait 5) (fileLockWait p \"x\") (fileLockWait p 1 2) (fileLockWait p true \"x\")"
    "                 (fileLockWait p true (some \"x\")) (fileLockWait p (pair 1 2)) (fileLockWait p 1.5) (fileLockWait nul) (fileLockWait (str d \"/sub\")) (fileLockWait long))"
    "        true))"
    ""
    "fn ! appendChecks self: String d: String -> Bool"
    "  (let [(a (str d \"/log\"))]"
    "    (do (println \"append\" (fileAppend a \"A\\n\") (child self (str \"append \" a)) (fileAppend a (stringToBytes \"C\\n\")) (fileAppend a \"\"))"
    "        (println \"append content\" (fileReadString a))"
    "        (println \"append bad\" (fileAppend 5 \"x\") (fileAppend a 5) (fileAppend \"a\\u{0}b\" \"x\") (fileAppend (str d \"/sub\") \"x\")"
    "                 (fileAppend (str d \"/\" (dup \"x\" 13)) 5) (fileAppend (str d \"/nodir/x\") \"x\"))"
    "        true))"
    ""
    "fn ! atChecks self: String d: String -> Bool"
    "  (let [(pid (procSelf))"
    "        (sub (str d \"/sub\"))"
    "        (big (dup \"0123456789\" 10))]"
    "    (do (decoys sub pid 1 1)"
    "        (println \"write over decoy\" (fileWriteAt d \"sub/f.txt\" \"new data\") (fileReadAt d \"sub/f.txt\")"
    "                 (= (fileReadAt d (str \"sub/.asl-write-\" pid \"-1\")) (ok \"decoy\")) (fileReadAt d (str \"sub/.asl-write-\" pid \"-2\")))"
    "        (decoys sub pid 3 130)"
    "        (println \"write exhausted\" (fileWriteAt d \"sub/f.txt\" \"lost\") (fileReadAt d \"sub/f.txt\"))"
    "        (println \"write after\" (fileWriteAt d \"sub/f.txt\" \"kept\") (fileReadAt d \"sub/f.txt\") (fileReadAt d (str \"sub/.asl-write-\" pid \"-131\")))"
    "        (println \"write nul data\" (fileWriteAt d \"sub/f.txt\" \"a\\u{0}b\") (mt (fileReadAt d \"sub/f.txt\") ((ok s) (stringLength s)) ((err e) -1)))"
    "        (println \"write big\" (fileWriteAt d \"sub/big.txt\" big) (= (fileReadAt d \"sub/big.txt\") (ok big)) (stringLength big))"
    "        (println \"read\" (fileReadAt d \"sub/empty.txt\") (fileReadAt d \"real/r.txt\"))"
    "        (println \"linked parent\" (fileReadAt d \"link/r.txt\") (fileWriteAt d \"link/r.txt\" \"y\") (fileLockAt d \"link/r.txt\" true))"
    "        (println \"linked leaf\" (fileWriteAt d \"sub/lnk\" \"y\") (fileReadAt d \"sub/lnk\") (fileLockAt d \"sub/lnk\" true))"
    "        (println \"kind\" (fileWriteAt d \"sub/fifo\" \"y\") (fileWriteAt d \"real\" \"y\") (fileReadAt d \"sub/fifo\") (fileReadAt d \"real\") (fileLockAt d \"real\" true))"
    "        (println \"refused read\" (fileReadAt d \"..\") (fileReadAt d \"sub/../sub/f.txt\") (fileReadAt d \"./sub/f.txt\") (fileReadAt d \"sub/./f.txt\")"
    "                 (fileReadAt d \"sub//f.txt\") (fileReadAt d \"sub/\") (fileReadAt d \"\") (fileReadAt d \"/etc/hosts\") (fileReadAt d \"sub\\\\f.txt\") (fileReadAt \"\" \"sub/f.txt\"))"
    "        (println \"refused write\" (fileWriteAt d \"..\" \"y\") (fileWriteAt d \"sub/.\" \"y\") (fileWriteAt d \"/etc/hosts\" \"y\") (fileWriteAt d \"sub//f.txt\" \"y\"))"
    "        (println \"refused lock\" (fileLockAt d \"sub/..\" true) (fileLockAt d \".\" true) (fileLockAt d \"/tmp/x\" true) (fileLockAt d \"a\\\\b\" true))"
    "        (println \"missing\" (fileWriteAt d \"sub/missing.txt\" \"y\") (fileReadAt d \"sub/missing.txt\") (fileReadAt d \"nodir/x\") (fileWriteAt d \"nodir/x\" \"y\"))"
    "        (println \"roots\" (fileReadAt (str d \"/sub/f.txt\") \"x\") (fileReadAt (str d \"/link\") \"r.txt\") (fileReadAt (str d \"/none\") \"x\"))"
    "        (println \"long\" (fileReadAt d (str \"sub/\" (dup \"a\" 8))) (fileReadAt d (dup \"a/\" 12)) (fileWriteAt d (dup \"a\" 8) \"y\"))"
    "        (println \"bad args\" (fileReadAt 5 \"a\") (fileReadAt d 5) (fileWriteAt d \"sub/f.txt\" 5) (fileWriteAt 5 \"x\" \"y\") (fileLockAt d \"x\" 1) (fileLockAt d 5 true)"
    "                 (fileReadAt d \"a\\u{0}b\") (fileWriteAt \"a\\u{0}b\" \"x\" \"y\") (fileLockAt d \"x\\u{0}\" true))"
    "        (println \"lockAt\" (shape (fileLockAt d \"sub/new.lock\" true)) (shape (fileLockAt d \"sub/new.lock\" false)) (shape (fileLockAt d \"sub/f.txt\" false)))"
    "        (println \"lockAt held\" (mt (fileLockAt d \"sub/new.lock\" true)"
    "                                 ((ok fd) (let [(c (child self (str \"lockAt \" d \" sub/new.lock\")))] (do (fdClose fd) c)))"
    "                                 ((err e) (str \"err \" e))))"
    "        (println \"lockAt released\" (child self (str \"lockAt \" d \" sub/new.lock\")))"
    "        true))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(self (optionOr (listGet args 0) \"\"))"
    "        (mode (optionOr (listGet args 1) \"\"))"
    "        (a (optionOr (listGet args 2) \"\"))"
    "        (b (optionOr (listGet args 3) \"\"))"
    "        (c (optionOr (listGet args 4) \"\"))]"
    "    (cond"
    "      ((= mode \"main\") (do (lockChecks self a) (appendChecks self a) (atChecks self a) (ok 0)))"
    "      ((= mode \"lock\") (do (println (shape (fileLock a (= b \"true\")))) (ok 0)))"
    "      ((= mode \"wait\") (do (println (shape (fileLockWait a (= b \"true\") (optionOr (stringToInt64 c) -2)))) (ok 0)))"
    "      ((= mode \"append\") (do (println (fileAppend a \"B\\n\")) (ok 0)))"
    "      ((= mode \"lockAt\") (do (println (shape (fileLockAt a b true))) (ok 0)))"
    "      (else (do (println \"usage\") (ok 2)))))"))

fn routedNames -> (List String)
  (list "fdRead" "fdWrite" "fdClose" "fdPoll" "fdNonBlocking" "cpuCount" "platformInfo" "localDate" "envList" "procSelf" "procAlive?" "procKill" "procExePath"
        "fileLock" "fileLockWait" "fileAppend" "fileLockAt" "fileReadAt" "fileWriteAt"
        "procSpawnv" "procWaitPid" "procWaitAny" "procPoll" "procRusage" "procExecv")

fn fdNames -> (List String)
  (list "fdRead" "fdWrite" "fdClose" "fdPoll" "fdNonBlocking")

fn infoNames -> (List String)
  (list "fdRead" "fdClose" "cpuCount" "platformInfo" "localDate" "envList" "procSelf" "procAlive?" "procKill" "procExePath")

fn cTableCall name: String -> String
  (str "@asl_rt_builtin_sys(ptr @name." (ssa/llvmName name) ",")

fn wrapperDef name: String -> String
  (str "define internal tailcc %Val @" (ssa/llvmName (str "asl-target-llvm/sysRoute." name)) "(")

fn ! fileText path: String -> String
  (mt (fileReadString path) ((ok t) t) ((err e) (do (assert false (str path ": " e)) "")))

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn ! lowered name: String src: String -> (Option ty/SsaModule)
  (let [(preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do (assert (not (stringEmpty? preludeText)) (str (lk/preludePath) " is readable"))
        (mt (lk/lowerSourceWith src preludeText)
          ((err ds) (do (assert false (str name ": lowerSourceWith: " (diagText ds))) (none)))
          ((ok m) (some m)))))

fn ! build work: String name: String src: String -> String
  (let [(_ (assert (ok? (fileWrite (str work "/" name ".asl") src)) (str name ".asl written")))]
    (mt (lowered name src)
      ((none) "")
      ((some m)
        (mt (llvm/emitLlvmProgramFor (hostFacts) m "main")
          ((err ds) (do (assert false (str name ": emitLlvmProgramFor: " (diagText ds))) ""))
          ((ok text) (do (assert (ok? (fileWrite (str work "/" name ".ll") text)) (str name ".ll written")) text))))))

fn ! linkBin work: String name: String -> Bool
  (let [(out (sh (str (clang) " -x ir " work "/" name ".ll -x none " (lib) " -lm -o " work "/" name)))]
    (do (assert (= out.exitCode 0) (str name ": links; " out.stderr))
        (= out.exitCode 0)))

fn ! checkIr label: String ll: String used: (List String) -> Bool
  (do (map (fn [(n String)] -> Bool (do (assert (not (stringContains? ll (cTableCall n))) (str label ": " n " is not called through asl_rt_builtin_sys")) true)) (routedNames))
      (map (fn [(n String)] -> Bool (do (assert (stringContains? ll (wrapperDef n)) (str label ": IR defines the " n " wrapper internal")) true)) used)
      true)

fn ! checkParity label: String bin: String src: String -> (Pair ProcessOutput ProcessOutput)
  (let [(native (sh (str (probeEnv) bin)))
        (vm (sh (str (probeEnv) (host) " run " src)))]
    (do (assert (= native.stdout vm.stdout) (str label ": native stdout equals asl-host run's; native=" native.stdout " vm=" vm.stdout " vm stderr=" vm.stderr))
        (assert (= native.exitCode vm.exitCode) (str label ": native exit " native.exitCode " equals asl-host run's " vm.exitCode "; native stderr " native.stderr))
        (pair native vm)))

fn fdWant -> String
  (lines (list "write empty (ok 0)" "read zero (ok \"\")" "poll idle 0 ok" "poll idle 50 ok" "poll writable ok w:2" "write one (ok 1)" "poll readable ok r:1" "poll both ok r:1 w:2"
               "read one (ok \"y\")" "nonblocking on (ok ())" "read empty pipe (err \"wouldBlock\")" "nonblocking off (ok ())" "nonblocking w (ok ())" "big round trip true true"
               "close w (ok ())" "read eof (ok \"\")" "wait cat (ok (some 0))" "close r (ok ())" "read closed (err \"badFd\")" "write closed (err \"badFd\")" "close closed (err \"badFd\")"
               "poll closed ok r:4" "nonblocking closed (err \"badFd\")"
               "fd -1 (err \"badFd\") (err \"badFd\") (err \"badFd\") (err \"badFd\")" "fd 999999 (err \"badFd\") (err \"badFd\") (err \"badFd\") (err \"badFd\")"
               "fd 2147483648 (err \"badFd\") (err \"badFd\") (err \"badFd\")" "bad max (err \"io:22\") (err \"io:22\")"
               "bad types (err \"badFd\") (err \"badFd\") (err \"io:22\") (err \"badFd\") (err \"badFd\") (err \"io:22\") (err \"badFd\")"
               "poll args (err \"io:22\") (err \"io:22\") (ok ()) (ok ()) (err \"io:22\") (err \"io:22\")"
               "poll items (err \"badFd\") (err \"badFd\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\")"
               "poll big timeout ok other:4"
               "poll shapes (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\")"))

fn ! testFd work: String -> Bool
  (let [(ll (build work "sysFd" (fdSource)))
        (_ (checkIr "sysFd" ll (fdNames)))
        (_ (linkBin work "sysFd"))
        (outs (checkParity "sysFd" (str work "/sysFd") (str work "/sysFd.asl")))]
    (do (assert (= (pairFirst outs).stdout (fdWant)) (str "sysFd: each step prints sys.c's shape: " (pairFirst outs).stdout))
        true))

fn ! realOf path: String -> String
  (mt (realPath path) ((ok p) p) ((err e) (do (assert false (str "realPath " path ": " e)) "")))

fn ! testInfo work: String -> Bool
  (let [(ll (build work "sysInfo" (infoSource)))
        (_ (checkIr "sysInfo" ll (infoNames)))
        (_ (linkBin work "sysInfo"))
        (bin (str work "/sysInfo"))
        (outs (checkParity "sysInfo" bin (str work "/sysInfo.asl")))
        (out (pairFirst outs).stdout)
        (shown (stringSplit out "\n"))]
    (do (map (fn [(l String)] -> Bool (do (assert (listContains? shown l) (str "sysInfo prints " l ": " out)) true))
             (list "cpuCount is getconf true" "platformInfo is uname true" "localDate is date true" "envList has probe true" "envList is env true"
                   "procSelf is sh's parent true" "procAlive? self (ok true)" "procAlive? reaped (ok false)" "procAlive? 1 (ok true)"
                   "procAlive? bad (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\")" "procKill self (ok ()) (ok ())" "procKill reaped (err \"noProcess\")"
                   "procKill bad (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\")"
                   "procExePath ok true"))
        (assert (stringStartsWith? out "cpuCount is getconf true\nplatformInfo (ok {:os ") (str "sysInfo platformInfo is a PlatformInfo record: " out))
        (assert (= (pairFirst outs).stderr (str (realOf bin) "\n")) (str "native procExePath is the binary's realpath: " (pairFirst outs).stderr))
        (assert (stringStartsWith? (pairSecond outs).stderr (str (realOf (host)) "\n")) (str "asl-host procExePath is asl-host's realpath: " (pairSecond outs).stderr))
        true))

fn ! fileDirSetup dir: String -> Bool
  (let [(out (sh (str "mkdir -p " dir "/sub " dir "/real && printf old > " dir "/sub/f.txt && chmod 640 " dir "/sub/f.txt && : > " dir "/sub/big.txt && : > " dir "/sub/empty.txt"
                      " && printf x > " dir "/real/r.txt && ln -s real " dir "/link && ln -s f.txt " dir "/sub/lnk && mkfifo " dir "/sub/fifo")))]
    (do (assert (= out.exitCode 0) (str dir " prepared: " out.stderr)) true))

fn fileNames -> (List String)
  (list "fileLock" "fileLockWait/1" "fileLockWait/2" "fileLockWait/3" "fileLockWait/bad" "fileAppend" "fileLockAt" "fileReadAt" "fileWriteAt")

fn ! errnoText name: String -> String
  (str "(err \"io:" (optionOr (libc/libcConst (hostFacts) name) -1) "\")")

fn times s: String n: Int64 -> String
  (stringJoin (map (fn [(i Int64)] -> String s) (range 0 n)) " ")

fn ! fileWant -> String
  (let [(inval "(err \"io:22\")") (isdir (errnoText "EISDIR")) (long (errnoText "ENAMETOOLONG"))
        (missing "(err \"notFound\")") (link "(err \"ERR_PATH_SYMLINK\")") (kind "(err \"ERR_PATH_TYPE\")")]
    (lines (list "lock ok ok ok" "lock held err busy / err busy" "lock released ok" "lock shared ok / err busy"
                 (str "lock bad " (times inval 3) " " isdir " " missing " " long)
                 (str "wait free " (times "ok" 10))
                 "wait held err ERR_TIMEOUT / err ERR_TIMEOUT / err ERR_TIMEOUT" "wait shared ok / err ERR_TIMEOUT"
                 (str "wait bad " (times inval 10) " " isdir " " long)
                 (str "append " (times "(ok ())" 4)) "append content (ok \"A\\nB\\nC\\n\")"
                 (str "append bad " (times inval 3) " " isdir " " long " " missing)
                 "write over decoy (ok ()) (ok \"new data\") true (err \"notFound\")" "write exhausted (err \"io:17\") (ok \"new data\")"
                 "write after (ok ()) (ok \"kept\") (err \"notFound\")" "write nul data (ok ()) 3" "write big (ok ()) true 10240" "read (ok \"\") (ok \"x\")"
                 (str "linked parent " (times link 3)) (str "linked leaf " (times link 3)) (str "kind " (times kind 4) " " isdir)
                 (str "refused read " (times inval 10)) (str "refused write " (times inval 4)) (str "refused lock " (times inval 4))
                 (str "missing " (times missing 4)) (str "roots " link " " link " " missing) (str "long " (times long 3)) (str "bad args " (times inval 9))
                 "lockAt ok ok ok" "lockAt held err busy" "lockAt released ok")))

fn ! testFile work: String -> Bool
  (let [(_ (fileDirSetup (str work "/fn")))
        (_ (fileDirSetup (str work "/fv")))
        (ll (build work "sysFile" (fileSource)))
        (_ (checkIr "sysFile" ll (fileNames)))
        (_ (linkBin work "sysFile"))
        (bin (str work "/sysFile"))
        (vmCmd (str (host) " run " work "/sysFile.asl"))
        (native (sh (str bin " '" bin "' main " work "/fn")))
        (vm (sh (str vmCmd " '" vmCmd "' main " work "/fv")))]
    (do (assert (= native.stdout vm.stdout) (str "sysFile: native stdout equals asl-host run's; native=" native.stdout " vm=" vm.stdout " vm stderr=" vm.stderr))
        (assert (= native.exitCode vm.exitCode) (str "sysFile: native exit " native.exitCode " equals asl-host run's " vm.exitCode "; native stderr " native.stderr))
        (assert (= native.stdout (fileWant)) (str "sysFile: each step prints sys.c's shape: " native.stdout))
        (map (fn [(side String)] -> Bool
               (do (assert (= (sh (str "find " work "/" side "/sub/f.txt -perm 640")).stdout (str work "/" side "/sub/f.txt\n")) (str "sysFile: fileWriteAt kept f.txt's mode 640 in " side)) true))
             (list "fn" "fv"))
        true))

fn lowerNames -> (List String)
  (list "procSpawnv" "procWaitPid" "procWaitAny" "procPoll" "procRusage" "procExecv" "fileLock" "fileLockWait" "fileAppend" "fileLockAt" "fileReadAt" "fileWriteAt")

fn twelveSource -> String
  (lines (list
    "(module sysTwelve :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println \"proc\" (fdRead 0 0) (procSpawnv (list) (none) (none)) (procWaitPid 0 true) (procWaitAny (list) 0) (procPoll (list) (list) -2) (ok? (procRusage)) (procExecv (list) (none)))"
    "      (println \"file\" (fileLock \"\" true) (fileLockWait \"\" true 0) (fileAppend \"\" \"\") (fileLockAt \"\" \"x\" true) (fileReadAt \"/\" \"\") (fileWriteAt \"/\" \"..\" \"\"))"
    "      (ok 0))"))

fn twelveWant -> String
  (lines (list "proc (ok \"\") (err \"io:22\") (err \"io:22\") (err \"io:22\") (err \"io:22\") true (err \"io:22\")"
               "file (err \"notFound\") (err \"notFound\") (err \"notFound\") (err \"io:22\") (err \"io:22\") (err \"io:22\")"))

fn ! nmSymbols bin: String -> (List String)
  (let [(out (sh (str "nm -P " bin)))]
    (do (assert (= out.exitCode 0) (str "nm -P " bin ": " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listHead (stringSplit line " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringEmpty? line))) (stringSplit out.stdout "\n")))))

fn ! sysCNames -> (List String)
  (fold (fn [(acc (List String)) (r (List String))] -> (List String)
          (let [(raw (optionOr (listGet r 1) ""))
                (name (if (stringStartsWith? raw "_") (optionOr (stringSlice raw 1 (stringLength raw)) raw) raw))]
            (if (and (stringEndsWith? (optionOr (listHead r) "") "[sys.o]")
                     (and (!= (optionOr (listGet r 2) "") "U")
                          (or (stringStartsWith? name "bFd") (or (stringStartsWith? name "bProc") (stringStartsWith? name "bFile")))))
              (cons name acc)
              acc)))
        (list) (nmLines (hostLib)))

fn ! testTwelve work: String -> Bool
  (let [(ll (build work "sysTwelve" (twelveSource)))
        (_ (checkIr "sysTwelve" ll (cons "fdRead" (filter (fn [(n String)] -> Bool (not (= n "fileLockWait"))) (lowerNames)))))
        (_ (assert (stringContains? ll (wrapperDef "fileLockWait/3")) "sysTwelve: IR defines the fileLockWait/3 wrapper internal"))
        (_ (assert (not (stringContains? ll "@asl_rt_builtin_sys(")) "sysTwelve: no call or declare of asl_rt_builtin_sys is emitted"))
        (_ (assert (listContains? (ssa/runtimeDecls) "declare %Val @asl_rt_builtin_sys(ptr, i64, ptr)") "sysTwelve: runtimeDecls keeps asl_rt_builtin_sys, which usedDecls drops when unused"))
        (linked (linkBin work "sysTwelve"))
        (outs (checkParity "sysTwelve" (str work "/sysTwelve") (str work "/sysTwelve.asl")))
        (syms (nmSymbols (str work "/sysTwelve")))
        (cNames (sysCNames))
        (sysSyms (filter (fn [(s String)] -> Bool (listContains? cNames s)) syms))]
    (do (assert linked "sysTwelve links against libaslrt.a")
        (assert (= (pairFirst outs).stdout (twelveWant)) (str "sysTwelve prints sys.c's answers: " (pairFirst outs).stdout))
        (assert (> (listLength syms) 0) "sysTwelve: nm -P lists symbols")
        (assert (listContains? cNames "bProcSpawnv") (str "libaslhost.a's sys.o lists its bFd, bProc and bFile functions: " cNames))
        (assert (listEmpty? sysSyms) (str "sysTwelve: no sys.c bFd, bProc or bFile symbol is linked: " sysSyms))
        true))

fn probeSource names: (List String) -> String
  (lines (listAppend (list "#include <errno.h>" "#include <poll.h>" "#include <signal.h>" "#include <stdio.h>" "int main(void) {")
           (listAppend (map (fn [(n String)] -> String (str "  printf(\"%s %d\\n\", \"" n "\", " n ");")) names) (list "  return 0;" "}"))))

fn ! testConsts work: String -> Bool
  (let [(names (listAppend (list "EROFS" "EOVERFLOW" "POLLPRI" "POLLERR" "POLLHUP" "EINVAL")
                 (listAppend (map (fn [(k (Pair String String))] -> String (pairFirst k)) (rt/errKinds)) (rt/signalNames))))
        (rows (map (fn [(n String)] -> (Pair String Int64) (pair n (optionOr (rt/routeConst (hostFacts) n) -1))) names))
        (_ (assert (ok? (fileWrite (str work "/constProbe.c") (probeSource names))) "constProbe.c written"))
        (built (sh (str "/usr/bin/clang -o " work "/constProbe " work "/constProbe.c")))
        (_ (assert (= built.exitCode 0) (str "constProbe compiles: " built.stderr)))
        (ran (sh (str work "/constProbe")))
        (want (lines (map (fn [(p (Pair String Int64))] -> String (str (pairFirst p) " " (pairSecond p))) rows)))]
    (do (assert (= ran.stdout want) (str "routeConst equals the C headers: headers=" ran.stdout " table=" want))
        (map (fn [(n String)] -> Bool (do (assert (= (rt/routeConst (hostFacts) n) (libc/libcConst (hostFacts) n)) (str "routeConst reads libc.asl's " n " row")) true)) names)
        true))

fn ! nmLines archive: String -> (List (List String))
  (let [(out (sh (str "nm -P -A " archive)))]
    (do (assert (= out.exitCode 0) (str "nm -P -A " archive ": " out.stderr))
        (map (fn [(line String)] -> (List String)
               (let [(halves (stringSplit line ": "))
                     (member (optionOr (listHead halves) ""))
                     (rest (stringSplit (optionOr (listGet halves 1) "") " "))]
                 (list member (optionOr (listGet rest 0) "") (optionOr (listGet rest 1) ""))))
             (filter (fn [(line String)] -> Bool (stringContains? line ": ")) (stringSplit out.stdout "\n")))))

fn defines? row: (List String) -> Bool
  (listContains? (list "T" "D" "S" "C" "B") (optionOr (listGet row 2) ""))

fn ! testArchive -> Bool
  (let [(hostRows (nmLines (hostLib)))
        (sysDefs (map (fn [(r (List String))] -> String (optionOr (listGet r 1) ""))
                      (filter (fn [(r (List String))] -> Bool (and (or (stringEndsWith? (optionOr (listHead r) "") "[sys.o]") (stringEndsWith? (optionOr (listHead r) "") "[sysNet.o]")) (defines? r))) hostRows)))
        (rtRows (nmLines (lib)))
        (members (filter (fn [(m String)] -> Bool (or (stringEndsWith? m "[sys.o]") (stringEndsWith? m "[sysNet.o]"))) (map (fn [(r (List String))] -> String (optionOr (listHead r) "")) rtRows)))
        (defs (filter (fn [(r (List String))] -> Bool (and (defines? r) (listContains? sysDefs (optionOr (listGet r 1) "")))) rtRows))
        (refs (filter (fn [(r (List String))] -> Bool (and (= (optionOr (listGet r 2) "") "U") (listContains? sysDefs (optionOr (listGet r 1) "")))) rtRows))]
    (do (assert (listContains? sysDefs "_asl_rt_builtin_sys") (str "libaslhost.a's sys.o defines asl_rt_builtin_sys: " sysDefs))
        (assert (listContains? sysDefs "_asl_rt_builtin_sysNet") (str "libaslhost.a's sysNet.o defines asl_rt_builtin_sysNet: " sysDefs))
        (assert (> (listLength rtRows) 0) "nm -P -A lists libaslrt.a's symbols")
        (assert (listEmpty? members) (str "libaslrt.a has no sys.o or sysNet.o member: " (listTake members 3)))
        (assert (listEmpty? defs) (str "no libaslrt.a member defines a sys.c or sysNet.c global: " (listTake defs 3)))
        (assert (listEmpty? refs) (str "no libaslrt.a member refers to a sys.c or sysNet.c global: " (listTake refs 3)))
        true))

fn ! optBin -> (Option String)
  (listHead (filter (fn [(c String)] -> Bool (= (sh (str "test -x " c)).exitCode 0))
                    (list "/opt/homebrew/opt/llvm/bin/opt" "/opt/homebrew/opt/llvm@22/bin/opt" "/usr/local/opt/llvm/bin/opt")))

fn ! testPortable work: String -> Bool
  (mt (lowered "sysInfo" (infoSource))
    ((none) false)
    ((some m)
      (do (mt (llvm/emitLlvmProgram m "main")
            ((err ds) (assert false (str "sysInfo emitLlvmProgram: " (diagText ds))))
            ((ok text)
              (do (map (fn [(n String)] -> Bool (do (assert (stringContains? text (cTableCall n)) (str "pure emitLlvmProgram calls " n " through sys.c's table")) true)) (infoNames))
                  (assert (not (stringContains? text "sysRoute$2E")) "pure emitLlvmProgram adds no sysRoute function"))))
          (mt (llvm/emitLlvmProgramFor (libc/linuxX8664Facts) m "main")
            ((err ds) (assert false (str "sysInfo emitLlvmProgramFor linux-x86_64: " (diagText ds))))
            ((ok text)
              (do (checkIr "sysInfo linux-x86_64" text (infoNames))
                  (assert (stringContains? text "@__errno_location") "linux-x86_64 routing reads errno through __errno_location")
                  (assert (stringContains? text "@environ") "linux-x86_64 envList reads the environ global")
                  (assert (not (stringContains? text "@_NSGetEnviron")) "linux-x86_64 routing has no darwin _NSGetEnviron")
                  (assert (ok? (fileWrite (str work "/sysInfoLinux.ll") text)) "sysInfoLinux.ll written")
                  (mt (optBin)
                    ((none) (do (println "sysInfo linux-x86_64: no opt on this host, -passes=verify skipped") true))
                    ((some o) (do (assert (= (sh (str o " -passes=verify -disable-output " work "/sysInfoLinux.ll")).exitCode 0) "linux-x86_64 routed IR verifies") true))))))
          true)))

fn routedOf res: (Result rt/Routed (List ty/IrDiag)) -> (Option ty/SsaModule)
  (mt res ((ok r) (some r.result)) ((err _) (none)))

fn diagCodes res: (Result rt/Routed (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn withRecord m: ty/SsaModule d: ty/SsaRecordDecl -> ty/SsaModule
  (ty/ssaModule m.name m.strings m.types (listAppend m.records (list d)) m.externs m.globals m.functions)

fn withString m: ty/SsaModule s: String -> ty/SsaModule
  (ty/ssaModule m.name (listAppend m.strings (list s)) m.types m.records m.externs m.globals m.functions)

fn countIn xs: (List String) s: String -> Int64
  (listLength (filter (fn [(x String)] -> Bool (= x s)) xs))

fn referencePoolIndex strings: (List String) s: String -> (Option Int64)
  (listHead (filter (fn [(i Int64)] -> Bool (= (listGet strings i) (some s))) (range 0 (listLength strings))))

fn referencePoolWith strings: (List String) wanted: (List String) -> (Pair (List String) (Map String Int64))
  (fold (fn [(acc (Pair (List String) (Map String Int64))) (s String)] -> (Pair (List String) (Map String Int64))
          (let [(have (pairFirst acc))]
            (mt (referencePoolIndex have s)
              ((some i) (pair have (mapSet (pairSecond acc) s i)))
              ((none) (pair (listAppend have (list s)) (mapSet (pairSecond acc) s (listLength have)))))))
        (pair strings (mapEmpty)) wanted)

fn poolMapsAgree? wanted: (List String) a: (Map String Int64) b: (Map String Int64) -> Bool
  (and (= (mapSize a) (mapSize b))
       (listAll? (fn [(s String)] -> Bool (= (mapGet a s) (mapGet b s))) wanted))

fn ! checkPoolWith label: String strings: (List String) wanted: (List String) -> Bool
  (let [(want (referencePoolWith strings wanted))
        (got (rt/poolWith strings wanted))]
    (do (assert (= (pairFirst want) (pairFirst got)) (str label ": poolWith's pooled strings equal the reference's; reference=" (pairFirst want) " got=" (pairFirst got)))
        (assert (poolMapsAgree? wanted (pairSecond want) (pairSecond got)) (str label ": poolWith's index map agrees with the reference on every wanted key"))
        true))

fn ! testPoolWith -> Bool
  (do (checkPoolWith "empty/empty" (list) (list))
      (checkPoolWith "empty strings" (list) (list "a" "b" "a" "c"))
      (checkPoolWith "no wanted" (list "x" "y" "z") (list))
      (checkPoolWith "all already present" (list "a" "b" "c") (list "c" "a" "b" "a"))
      (checkPoolWith "all new" (list "a" "b") (list "c" "d" "c" "e"))
      (checkPoolWith "duplicates in strings keep the first index" (list "x" "y" "x" "z" "x") (list "x" "y" "z" "x"))
      (checkPoolWith "mixed present and new with repeats" (list "a" "b" "a") (list "b" "c" "a" "c" "d" "b" "d"))
      true)

fn ! testRouteModule -> Bool
  (let [(facts (libc/darwinArm64Facts))]
    (mt (lowered "sysInfo" (infoSource))
      ((none) false)
      ((some m)
        (do (mt (routedOf (rt/routeModule facts m))
              ((none) (assert false "sysInfo routes for darwin-arm64"))
              ((some out) (do (assert (= (countIn out.strings "badFd") 1) "badFd is in the routed pool once")
                              (assert (= (countIn out.strings "SIGWINCH") 1) "SIGWINCH is in the routed pool once")
                              (assert (not (rt/routes? out)) "a routed module has no routed builtin call left"))))
            (mt (routedOf (rt/routeModule facts (withString m "badFd")))
              ((none) (assert false "sysInfo with badFd in its pool routes"))
              ((some out) (assert (= (countIn out.strings "badFd") 1) "badFd already in the pool is reused, not appended")))
            (mt (routedOf (rt/routeModule facts (withRecord m (ty/ssaRecordDecl "PlatformInfo" (list "os" "release" "machine")))))
              ((none) (assert false "sysInfo declaring the same PlatformInfo routes"))
              ((some out) (assert (= (listLength (filter (fn [(d ty/SsaRecordDecl)] -> Bool (= d.name "PlatformInfo")) out.records)) 1) "an own PlatformInfo with the same fields is declared once")))
            (assert (= (diagCodes (rt/routeModule facts (withRecord m (ty/ssaRecordDecl "PlatformInfo" (list "os"))))) (list "ERR_LLVM_SYSROUTE_RECORD")) "an own PlatformInfo with other fields is ERR_LLVM_SYSROUTE_RECORD")
            true))))

fn tagProbe name: String n: Int64 -> ty/SsaFunction
  (ty/ssaFunction name (list) (list) (ty/tyI64)
    (list (ty/ssaBlock "entry" (list)
            (list (ty/ssaInstr "n" (ty/tyI64) (ty/opConst (ty/constInt n)))
                  (ty/ssaInstr "t" (ty/tyI64) (ty/opCall (rt/wrapperName "tagCheck") (list "n"))))
            (ty/termReturn "t"))))

fn ! testTagGuard work: String -> Bool
  (mt (lowered "sysTag" (lines (list "(module sysTag :x [main] :i [])" "" "fn ! main -> (Result Int64 String)" "  (do (fdClose 99) (fdPoll (list) 0) (ok 0))")))
    ((none) false)
    ((some m)
      (mt (routedOf (rt/routeModule (hostFacts) m))
        ((none) (do (assert false "sysTag routes for this host") false))
        ((some r)
          (let [(probed (ty/ssaModule r.name r.strings r.types r.records r.externs r.globals
                          (listAppend r.functions (list (tagProbe "tagGood" 6) (tagProbe "tagBad" 300)))))
                (runs (map (fn [(entry String)] -> ProcessOutput
                             (mt (llvm/emitLlvmProgram probed entry)
                               ((err ds) (do (assert false (str entry ": emitLlvmProgram: " (diagText ds))) (sh "false")))
                               ((ok text) (do (assert (ok? (fileWrite (str work "/" entry ".ll") text)) (str entry ".ll written"))
                                              (linkBin work entry)
                                              (sh (str work "/" entry))))))
                           (list "tagGood" "tagBad")))
                (good (optionOr (listGet runs 0) (sh "false")))
                (bad (optionOr (listGet runs 1) (sh "false")))]
            (do (assert (= good.exitCode 6) (str "tagCheck passes a Tag through: exit " good.exitCode " " good.stderr))
                (assert (!= bad.exitCode 0) (str "tagCheck of 300 does not return: exit " bad.exitCode))
                (assert (stringContains? bad.stderr (rt/tagGuardText)) (str "tagCheck of 300 names the broken ABI assumption on stderr: " bad.stderr))
                true))))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testConsts work)
        (testArchive)
        (testPoolWith)
        (testRouteModule)
        (testFd work)
        (testInfo work)
        (testFile work)
        (testTwelve work)
        (testTagGuard work)
        (testPortable work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
