(module asl-target-llvm/tests/sysProcTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/sys :a sys)
      (asl-target-llvm/sysProc :a proc)
      (asl-target-llvm/libc :a libc)])

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn host -> String
  "asl/host/out/asl-host"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! exitOf cmd: String -> Int64
  (sh cmd).exitCode

fn ! expectExit label: String cmd: String want: Int64 -> Bool
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode want) (str label ": exit " out.exitCode ", want " want "; stderr: " out.stderr))
        true))

fn ! writeAndLink work: String name: String text: String -> Bool
  (let [(ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite ll text)) (str name ": .ll written"))
        (expectExit (str name ": clang links against " (lib)) (str (clang) " -x ir " ll " -x none " (lib) " -lm -o " work "/" name) 0)))

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (exitOf (str "test -x " c)) 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/opt/homebrew/opt/llvm@22/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (mt (listGet known 0)
      ((some o) (some o))
      ((none) (if (= (exitOf "command -v opt >/dev/null 2>&1") 0) (some "opt") (none)))))

fn ! verifyLl label: String work: String file: String -> Bool
  (mt (optBin)
    ((none) (do (println (str label ": opt not found on this host, skipping -passes=verify")) true))
    ((some o) (expectExit (str label ": opt -passes=verify accepts the emitted IR") (str o " -passes=verify -disable-output " work "/" file ".ll") 0)))

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (optionOr (libc/libcFacts (hostTriple)) (libc/darwinArm64Facts))

fn textOf res: (Result String (List ty/IrDiag)) -> String
  (mt res ((ok text) text) ((err diags) (str "ERR: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " @ " d.locus ": " d.message)) diags) " || "))))

fn ! sysFns facts: libc/TripleFacts -> (List ty/SsaFunction)
  (mt (sys/sysFunctions facts)
    ((ok fs) fs)
    ((err e) (do (assert false (str "sysFunctions: " e)) (list))))

fn ! procFns facts: libc/TripleFacts -> (List ty/SsaFunction)
  (mt (proc/sysProcFunctions facts)
    ((ok fs) fs)
    ((err e) (do (assert false (str "sysProcFunctions: " e)) (list))))

fn ! moduleOf facts: libc/TripleFacts strings: (List String) extraFns: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" strings (list (sys/resultTypeDecl) (sys/optionTypeDecl)) (proc/sysProcRecords)
    (listAppend (sys/sysExterns facts) (proc/sysProcExterns facts))
    (list)
    (listAppend (sysFns facts) (listAppend (procFns facts) extraFns)))

fn edge target: String -> ty/SsaEdge
  (ty/ssaEdge target (list))

fn okErrSwitch scrutinee: String okLabel: String errLabel: String -> ty/SsaTerm
  (ty/termSwitch scrutinee "Result" (list (ty/ssaCase "ok" (edge okLabel)) (ty/ssaCase "err" (edge errLabel))) (none))

fn constStrInstr dest: String i: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opConst (ty/constStr i)))

fn boolBranch cond: String passLabel: String failLabel: String -> ty/SsaTerm
  (ty/termBranch cond (edge passLabel) (edge failLabel))

fn passFailBlocks passLabel: String passCode: Int64 failLabel: String failCode: Int64 -> (List ty/SsaBlock)
  (list
    (sys/block passLabel (list (sys/int64Const (str passLabel ".code") passCode)) (ty/termReturn (str passLabel ".code")))
    (sys/block failLabel (list (sys/int64Const (str failLabel ".code") failCode)) (ty/termReturn (str failLabel ".code"))))

fn sentinelBlock label: String code: Int64 -> ty/SsaBlock
  (sys/block label (list (sys/int64Const (str label ".code") code)) (ty/termReturn (str label ".code")))

fn strListConstInstrs destList: String prefix: String indices: (List Int64) -> (List ty/SsaInstr)
  (let [(named (map (fn [(i Int64)] -> (Pair String Int64) (pair (str prefix "." (stringFromInt64 i)) i)) indices))]
    (listAppend
      (map (fn [(np (Pair String Int64))] -> ty/SsaInstr (constStrInstr (pairFirst np) (pairSecond np))) named)
      (list (sys/listInstr destList (map pairFirst named)))))

fn pidRangeRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (list
      (sys/block "entry"
        (list (sys/int64Const "tooWidePid" 2147483648)
              (sys/int64Const "zeroSignal" 0)
              (sys/callInstr "killRes" (ty/tyVal) "procKill" (list "tooWidePid" "zeroSignal")))
        (okErrSwitch "killRes" "killOk" "killErr"))
      (sys/block "killErr"
        (list (ty/ssaInstr "errnoBox" (ty/tyVal) (ty/opVariantField "killRes" 0))
              (ty/ssaInstr "errno" (ty/tyI64) (ty/opUnbox "errnoBox"))
              (sys/int64Const "einval" 22)
              (ty/ssaInstr "isEinval" (ty/tyI1) (ty/opPrim "eqInt" (list "errno" "einval"))))
        (boolBranch "isEinval" "pass" "wrongErrno"))
      (sentinelBlock "killOk" 2)
      (sentinelBlock "wrongErrno" 1)
      (sentinelBlock "pass" 0)))

fn spawnEchoRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvList" "argv" (list 0 1))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "pathV" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv"))))
          (okErrSwitch "spawnRes" "spawnOk" "errSpawn"))
        (sys/block "spawnOk"
          (list
            (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "pidBox" (ty/tyVal) (ty/opField "rec1" "pid"))
            (ty/ssaInstr "pid" (ty/tyI64) (ty/opUnbox "pidBox"))
            (ty/ssaInstr "outFdBox" (ty/tyVal) (ty/opField "rec1" "outFd"))
            (ty/ssaInstr "outFd" (ty/tyI64) (ty/opUnbox "outFdBox"))
            (ty/ssaInstr "outFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd")))
            (ty/ssaInstr "errFdBox" (ty/tyVal) (ty/opField "rec1" "errFd"))
            (ty/ssaInstr "errFd" (ty/tyI64) (ty/opUnbox "errFdBox"))
            (ty/ssaInstr "errFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd")))
            (sys/int64Const "max" 64)
            (sys/callInstr "readRes" (ty/tyVal) "sysRead" (list "outFd32" "max")))
          (okErrSwitch "readRes" "readOk" "errRead"))
        (sys/block "readOk"
          (list
            (ty/ssaInstr "bytes" (ty/tyVal) (ty/opVariantField "readRes" 0))
            (sys/entryInstr "n" (ty/tyI64) "bytesLength" (list "bytes"))
            (sys/int64Const "three" 3)
            (ty/ssaInstr "lenOk" (ty/tyI1) (ty/opPrim "eqInt" (list "n" "three")))
            (sys/int64Const "idx0" 0)
            (sys/entryInstr "b0" (ty/tyI64) "bytesGet" (list "bytes" "idx0"))
            (sys/int64Const "hChar" 104)
            (ty/ssaInstr "c0" (ty/tyI1) (ty/opPrim "eqInt" (list "b0" "hChar")))
            (sys/int64Const "idx1" 1)
            (sys/entryInstr "b1" (ty/tyI64) "bytesGet" (list "bytes" "idx1"))
            (sys/int64Const "iChar" 105)
            (ty/ssaInstr "c1" (ty/tyI1) (ty/opPrim "eqInt" (list "b1" "iChar")))
            (sys/int64Const "idx2" 2)
            (sys/entryInstr "b2" (ty/tyI64) "bytesGet" (list "bytes" "idx2"))
            (sys/int64Const "nlChar" 10)
            (ty/ssaInstr "c2" (ty/tyI1) (ty/opPrim "eqInt" (list "b2" "nlChar")))
            (ty/ssaInstr "bytesOk1" (ty/tyI1) (ty/opPrim "andBool" (list "lenOk" "c0")))
            (ty/ssaInstr "bytesOk2" (ty/tyI1) (ty/opPrim "andBool" (list "bytesOk1" "c1")))
            (ty/ssaInstr "bytesOk" (ty/tyI1) (ty/opPrim "andBool" (list "bytesOk2" "c2")))
            (sys/callInstr "closeOut" (ty/tyVal) "sysClose" (list "outFd32"))
            (sys/callInstr "closeErr" (ty/tyVal) "sysClose" (list "errFd32"))
            (sys/int64Const "forever" -1)
            (sys/callInstr "waitRes" (ty/tyVal) "procWait" (list "pid" "forever")))
          (okErrSwitch "waitRes" "waitOk" "errWait"))
        (sys/block "waitOk"
          (list
            (ty/ssaInstr "rec2" (ty/tyVal) (ty/opVariantField "waitRes" 0))
            (ty/ssaInstr "statusBox" (ty/tyVal) (ty/opField "rec2" "status"))
            (ty/ssaInstr "status" (ty/tyI64) (ty/opUnbox "statusBox"))
            (sys/int64Const "zero" 0)
            (ty/ssaInstr "statusOk" (ty/tyI1) (ty/opPrim "eqInt" (list "status" "zero")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "bytesOk" "statusOk"))))
          (boolBranch "allOk" "pass" "fail9")))
      (listAppend
        (passFailBlocks "pass" 0 "fail9" 9)
        (list (sentinelBlock "errSpawn" 1) (sentinelBlock "errRead" 2) (sentinelBlock "errWait" 7)))))

fn spawnTimeoutKillRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvList" "argv" (list 0 1))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "pathV" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv"))))
          (okErrSwitch "spawnRes" "spawnOk" "errSpawn"))
        (sys/block "spawnOk"
          (list
            (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "pidBox" (ty/tyVal) (ty/opField "rec1" "pid"))
            (ty/ssaInstr "pid" (ty/tyI64) (ty/opUnbox "pidBox"))
            (ty/ssaInstr "outFdBox" (ty/tyVal) (ty/opField "rec1" "outFd"))
            (ty/ssaInstr "outFd" (ty/tyI64) (ty/opUnbox "outFdBox"))
            (ty/ssaInstr "outFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd")))
            (ty/ssaInstr "errFdBox" (ty/tyVal) (ty/opField "rec1" "errFd"))
            (ty/ssaInstr "errFd" (ty/tyI64) (ty/opUnbox "errFdBox"))
            (ty/ssaInstr "errFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd")))
            (sys/callInstr "closeOut" (ty/tyVal) "sysClose" (list "outFd32"))
            (sys/callInstr "closeErr" (ty/tyVal) "sysClose" (list "errFd32"))
            (sys/int64Const "shortTimeout" 50)
            (sys/callInstr "wait1Res" (ty/tyVal) "procWait" (list "pid" "shortTimeout")))
          (okErrSwitch "wait1Res" "wait1Ok" "errWait1"))
        (sys/block "wait1Ok"
          (list
            (ty/ssaInstr "rec2" (ty/tyVal) (ty/opVariantField "wait1Res" 0))
            (ty/ssaInstr "timedOut1Box" (ty/tyVal) (ty/opField "rec2" "timedOut"))
            (ty/ssaInstr "timedOut1" (ty/tyI64) (ty/opUnbox "timedOut1Box"))
            (sys/int64Const "one" 1)
            (ty/ssaInstr "c1" (ty/tyI1) (ty/opPrim "eqInt" (list "timedOut1" "one")))
            (sys/int64Const "sigkill" 9)
            (sys/callInstr "killRes" (ty/tyVal) "procKill" (list "pid" "sigkill")))
          (okErrSwitch "killRes" "killOk" "errKill"))
        (sys/block "killOk"
          (list (sys/int64Const "forever" -1)
                (sys/callInstr "wait2Res" (ty/tyVal) "procWait" (list "pid" "forever")))
          (okErrSwitch "wait2Res" "wait2Ok" "errWait2"))
        (sys/block "wait2Ok"
          (list
            (ty/ssaInstr "rec3" (ty/tyVal) (ty/opVariantField "wait2Res" 0))
            (ty/ssaInstr "status2Box" (ty/tyVal) (ty/opField "rec3" "status"))
            (ty/ssaInstr "status2" (ty/tyI64) (ty/opUnbox "status2Box"))
            (ty/ssaInstr "timedOut2Box" (ty/tyVal) (ty/opField "rec3" "timedOut"))
            (ty/ssaInstr "timedOut2" (ty/tyI64) (ty/opUnbox "timedOut2Box"))
            (sys/int64Const "signalMask" 127)
            (ty/ssaInstr "statusMasked" (ty/tyI64) (ty/opPrim "rawAndI64" (list "status2" "signalMask")))
            (sys/int64Const "nine" 9)
            (ty/ssaInstr "c2" (ty/tyI1) (ty/opPrim "eqInt" (list "statusMasked" "nine")))
            (sys/int64Const "zero2" 0)
            (ty/ssaInstr "c3" (ty/tyI1) (ty/opPrim "eqInt" (list "timedOut2" "zero2")))
            (ty/ssaInstr "c1c2" (ty/tyI1) (ty/opPrim "andBool" (list "c1" "c2")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "c1c2" "c3"))))
          (boolBranch "allOk" "pass" "fail10")))
      (listAppend
        (passFailBlocks "pass" 0 "fail10" 10)
        (list (sentinelBlock "errSpawn" 1) (sentinelBlock "errWait1" 7)
              (sentinelBlock "errKill" 8) (sentinelBlock "errWait2" 9)))))

fn waitAnyRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argv1List" "argv1" (list 0 1))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "path1V" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawn1Res" (ty/tyVal) "procSpawn" (list "path1V" "argv1List" "envpList" "inheritEnv"))))
          (okErrSwitch "spawn1Res" "spawn1Ok" "errSpawn1"))
        (sys/block "spawn1Ok"
          (listAppend
            (list
              (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawn1Res" 0))
              (ty/ssaInstr "pid1Box" (ty/tyVal) (ty/opField "rec1" "pid"))
              (ty/ssaInstr "pid1" (ty/tyI64) (ty/opUnbox "pid1Box"))
              (ty/ssaInstr "outFd1Box" (ty/tyVal) (ty/opField "rec1" "outFd"))
              (ty/ssaInstr "outFd1" (ty/tyI64) (ty/opUnbox "outFd1Box"))
              (ty/ssaInstr "outFd1_32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd1")))
              (ty/ssaInstr "errFd1Box" (ty/tyVal) (ty/opField "rec1" "errFd"))
              (ty/ssaInstr "errFd1" (ty/tyI64) (ty/opUnbox "errFd1Box"))
              (ty/ssaInstr "errFd1_32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd1"))))
            (listAppend
              (strListConstInstrs "argv2List" "argv2" (list 2 3))
              (list
                (constStrInstr "path2V" 2)
                (sys/callInstr "spawn2Res" (ty/tyVal) "procSpawn" (list "path2V" "argv2List" "envpList" "inheritEnv")))))
          (okErrSwitch "spawn2Res" "spawn2Ok" "errSpawn2"))
        (sys/block "spawn2Ok"
          (list
            (ty/ssaInstr "rec2" (ty/tyVal) (ty/opVariantField "spawn2Res" 0))
            (ty/ssaInstr "pid2Box" (ty/tyVal) (ty/opField "rec2" "pid"))
            (ty/ssaInstr "pid2" (ty/tyI64) (ty/opUnbox "pid2Box"))
            (ty/ssaInstr "outFd2Box" (ty/tyVal) (ty/opField "rec2" "outFd"))
            (ty/ssaInstr "outFd2" (ty/tyI64) (ty/opUnbox "outFd2Box"))
            (ty/ssaInstr "outFd2_32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd2")))
            (ty/ssaInstr "errFd2Box" (ty/tyVal) (ty/opField "rec2" "errFd"))
            (ty/ssaInstr "errFd2" (ty/tyI64) (ty/opUnbox "errFd2Box"))
            (ty/ssaInstr "errFd2_32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd2")))
            (sys/int64Const "forever" -1)
            (sys/callInstr "anyRes" (ty/tyVal) "procWaitAny" (list "pid1" "pid2" "forever")))
          (okErrSwitch "anyRes" "anyOk" "errAny"))
        (sys/block "anyOk"
          (list
            (ty/ssaInstr "rec3" (ty/tyVal) (ty/opVariantField "anyRes" 0))
            (ty/ssaInstr "idxBox" (ty/tyVal) (ty/opField "rec3" "index"))
            (ty/ssaInstr "idx" (ty/tyI64) (ty/opUnbox "idxBox"))
            (ty/ssaInstr "waitedPidBox" (ty/tyVal) (ty/opField "rec3" "pid"))
            (ty/ssaInstr "waitedPid" (ty/tyI64) (ty/opUnbox "waitedPidBox"))
            (ty/ssaInstr "status3Box" (ty/tyVal) (ty/opField "rec3" "status"))
            (ty/ssaInstr "status3" (ty/tyI64) (ty/opUnbox "status3Box"))
            (ty/ssaInstr "timedOut3Box" (ty/tyVal) (ty/opField "rec3" "timedOut"))
            (ty/ssaInstr "timedOut3" (ty/tyI64) (ty/opUnbox "timedOut3Box"))
            (sys/int64Const "oneIdx" 1)
            (ty/ssaInstr "c1" (ty/tyI1) (ty/opPrim "eqInt" (list "idx" "oneIdx")))
            (ty/ssaInstr "c2" (ty/tyI1) (ty/opPrim "eqInt" (list "waitedPid" "pid2")))
            (sys/int64Const "zero3" 0)
            (ty/ssaInstr "c3" (ty/tyI1) (ty/opPrim "eqInt" (list "status3" "zero3")))
            (ty/ssaInstr "c4" (ty/tyI1) (ty/opPrim "eqInt" (list "timedOut3" "zero3")))
            (sys/callInstr "close1Out" (ty/tyVal) "sysClose" (list "outFd1_32"))
            (sys/callInstr "close1Err" (ty/tyVal) "sysClose" (list "errFd1_32"))
            (sys/callInstr "close2Out" (ty/tyVal) "sysClose" (list "outFd2_32"))
            (sys/callInstr "close2Err" (ty/tyVal) "sysClose" (list "errFd2_32"))
            (sys/int64Const "sigkill" 9)
            (sys/callInstr "killRes" (ty/tyVal) "procKill" (list "pid1" "sigkill"))
            (sys/int64Const "reapTimeout" 1000)
            (sys/callInstr "reapRes" (ty/tyVal) "procWait" (list "pid1" "reapTimeout"))
            (ty/ssaInstr "c12" (ty/tyI1) (ty/opPrim "andBool" (list "c1" "c2")))
            (ty/ssaInstr "c34" (ty/tyI1) (ty/opPrim "andBool" (list "c3" "c4")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "c12" "c34"))))
          (boolBranch "allOk" "pass" "fail11")))
      (listAppend
        (passFailBlocks "pass" 0 "fail11" 11)
        (list (sentinelBlock "errSpawn1" 1) (sentinelBlock "errSpawn2" 2) (sentinelBlock "errAny" 3)))))

fn procSelfRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (list
              (sys/callInstr "selfPid" (ty/tyI64) "procSelf" (list))
              (sys/entryInstr "selfStr" (ty/tyVal) "stringFromInt64" (list "selfPid"))
              (constStrInstr "nlV" 3)
              (sys/entryInstr "expected" (ty/tyVal) "stringConcat" (list "selfStr" "nlV")))
            (listAppend
              (strListConstInstrs "argvList" "argv" (list 0 1 2))
              (list
                (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
                (constStrInstr "pathV" 0)
                (sys/int32Const "inheritEnv" 1)
                (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv")))))
          (okErrSwitch "spawnRes" "spawnOk" "errSpawn"))
        (sys/block "spawnOk"
          (list
            (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "pidBox" (ty/tyVal) (ty/opField "rec1" "pid"))
            (ty/ssaInstr "pid" (ty/tyI64) (ty/opUnbox "pidBox"))
            (ty/ssaInstr "outFdBox" (ty/tyVal) (ty/opField "rec1" "outFd"))
            (ty/ssaInstr "outFd" (ty/tyI64) (ty/opUnbox "outFdBox"))
            (ty/ssaInstr "outFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd")))
            (ty/ssaInstr "errFdBox" (ty/tyVal) (ty/opField "rec1" "errFd"))
            (ty/ssaInstr "errFd" (ty/tyI64) (ty/opUnbox "errFdBox"))
            (ty/ssaInstr "errFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd")))
            (sys/int64Const "max" 64)
            (sys/callInstr "readRes" (ty/tyVal) "sysRead" (list "outFd32" "max")))
          (okErrSwitch "readRes" "readOk" "errRead"))
        (sys/block "readOk"
          (list
            (ty/ssaInstr "actual" (ty/tyVal) (ty/opVariantField "readRes" 0))
            (sys/entryInstr "expectedBytes" (ty/tyVal) "stringToBytes" (list "expected"))
            (sys/entryInstr "eqRes" (ty/tyI1) "=" (list "expectedBytes" "actual"))
            (sys/callInstr "closeOut" (ty/tyVal) "sysClose" (list "outFd32"))
            (sys/callInstr "closeErr" (ty/tyVal) "sysClose" (list "errFd32"))
            (sys/int64Const "forever" -1)
            (sys/callInstr "waitRes" (ty/tyVal) "procWait" (list "pid" "forever")))
          (okErrSwitch "waitRes" "waitOk" "errWait"))
        (sys/block "waitOk"
          (list
            (ty/ssaInstr "rec2" (ty/tyVal) (ty/opVariantField "waitRes" 0))
            (ty/ssaInstr "statusBox" (ty/tyVal) (ty/opField "rec2" "status"))
            (ty/ssaInstr "status" (ty/tyI64) (ty/opUnbox "statusBox"))
            (sys/int64Const "zero" 0)
            (ty/ssaInstr "statusOk" (ty/tyI1) (ty/opPrim "eqInt" (list "status" "zero")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "eqRes" "statusOk"))))
          (boolBranch "allOk" "pass" "fail9")))
      (listAppend
        (passFailBlocks "pass" 0 "fail9" 9)
        (list (sentinelBlock "errSpawn" 1) (sentinelBlock "errRead" 2) (sentinelBlock "errWait" 7)))))

fn procAliveRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvList" "argv" (list 0 1))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "pathV" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv"))))
          (okErrSwitch "spawnRes" "spawnOk" "errSpawn"))
        (sys/block "spawnOk"
          (list
            (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "pidBox" (ty/tyVal) (ty/opField "rec1" "pid"))
            (ty/ssaInstr "pid" (ty/tyI64) (ty/opUnbox "pidBox"))
            (ty/ssaInstr "outFdBox" (ty/tyVal) (ty/opField "rec1" "outFd"))
            (ty/ssaInstr "outFd" (ty/tyI64) (ty/opUnbox "outFdBox"))
            (ty/ssaInstr "outFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd")))
            (ty/ssaInstr "errFdBox" (ty/tyVal) (ty/opField "rec1" "errFd"))
            (ty/ssaInstr "errFd" (ty/tyI64) (ty/opUnbox "errFdBox"))
            (ty/ssaInstr "errFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd")))
            (sys/callInstr "closeOut" (ty/tyVal) "sysClose" (list "outFd32"))
            (sys/callInstr "closeErr" (ty/tyVal) "sysClose" (list "errFd32"))
            (sys/callInstr "alive1Res" (ty/tyVal) "procAlive" (list "pid")))
          (okErrSwitch "alive1Res" "alive1Ok" "errAlive1"))
        (sys/block "alive1Ok"
          (list
            (ty/ssaInstr "alive1Box" (ty/tyVal) (ty/opVariantField "alive1Res" 0))
            (ty/ssaInstr "c1" (ty/tyI1) (ty/opUnbox "alive1Box"))
            (sys/int64Const "sigkill" 9)
            (sys/callInstr "killRes" (ty/tyVal) "procKill" (list "pid" "sigkill")))
          (okErrSwitch "killRes" "killOk" "errKill"))
        (sys/block "killOk"
          (list (sys/int64Const "reapTimeout" 2000)
                (sys/callInstr "waitRes" (ty/tyVal) "procWait" (list "pid" "reapTimeout")))
          (okErrSwitch "waitRes" "waitOk" "errWait"))
        (sys/block "waitOk"
          (list (sys/callInstr "alive2Res" (ty/tyVal) "procAlive" (list "pid")))
          (okErrSwitch "alive2Res" "alive2Ok" "errAlive2"))
        (sys/block "alive2Ok"
          (list
            (ty/ssaInstr "alive2Box" (ty/tyVal) (ty/opVariantField "alive2Res" 0))
            (ty/ssaInstr "isAlive2" (ty/tyI1) (ty/opUnbox "alive2Box"))
            (ty/ssaInstr "c2" (ty/tyI1) (ty/opPrim "notBool" (list "isAlive2")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "c1" "c2"))))
          (boolBranch "allOk" "pass" "fail13")))
      (listAppend
        (passFailBlocks "pass" 0 "fail13" 13)
        (list (sentinelBlock "errSpawn" 1) (sentinelBlock "errAlive1" 2) (sentinelBlock "errKill" 3)
              (sentinelBlock "errWait" 4) (sentinelBlock "errAlive2" 5)))))

fn spawnEnoentRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvList" "argv" (list 0))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "pathV" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv"))))
          (okErrSwitch "spawnRes" "unexpectedOk" "spawnErr"))
        (sentinelBlock "unexpectedOk" 2)
        (sys/block "spawnErr"
          (list
            (ty/ssaInstr "errBox" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "errnoV" (ty/tyI64) (ty/opUnbox "errBox"))
            (sys/int64Const "enoent" 2)
            (ty/ssaInstr "isEnoent" (ty/tyI1) (ty/opPrim "eqInt" (list "errnoV" "enoent"))))
          (boolBranch "isEnoent" "pass" "fail9")))
      (passFailBlocks "pass" 0 "fail9" 9)))

fn inheritEnvRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvList" "argv" (list 0 1 2))
            (listAppend
              (strListConstInstrs "envpList" "envp" (list 3))
              (list
                (constStrInstr "pathV" 0)
                (sys/int32Const "inheritEnv" 0)
                (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv")))))
          (okErrSwitch "spawnRes" "spawnOk" "errSpawn"))
        (sys/block "spawnOk"
          (list
            (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "pidBox" (ty/tyVal) (ty/opField "rec1" "pid"))
            (ty/ssaInstr "pid" (ty/tyI64) (ty/opUnbox "pidBox"))
            (ty/ssaInstr "outFdBox" (ty/tyVal) (ty/opField "rec1" "outFd"))
            (ty/ssaInstr "outFd" (ty/tyI64) (ty/opUnbox "outFdBox"))
            (ty/ssaInstr "outFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd")))
            (ty/ssaInstr "errFdBox" (ty/tyVal) (ty/opField "rec1" "errFd"))
            (ty/ssaInstr "errFd" (ty/tyI64) (ty/opUnbox "errFdBox"))
            (ty/ssaInstr "errFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd")))
            (sys/int64Const "max" 16)
            (sys/callInstr "readRes" (ty/tyVal) "sysRead" (list "outFd32" "max")))
          (okErrSwitch "readRes" "readOk" "errRead"))
        (sys/block "readOk"
          (list
            (ty/ssaInstr "actual" (ty/tyVal) (ty/opVariantField "readRes" 0))
            (constStrInstr "expected" 4)
            (sys/entryInstr "expectedBytes" (ty/tyVal) "stringToBytes" (list "expected"))
            (sys/entryInstr "eqRes" (ty/tyI1) "=" (list "expectedBytes" "actual"))
            (sys/callInstr "closeOut" (ty/tyVal) "sysClose" (list "outFd32"))
            (sys/callInstr "closeErr" (ty/tyVal) "sysClose" (list "errFd32"))
            (sys/int64Const "forever" -1)
            (sys/callInstr "waitRes" (ty/tyVal) "procWait" (list "pid" "forever")))
          (okErrSwitch "waitRes" "waitOk" "errWait"))
        (sys/block "waitOk"
          (list
            (ty/ssaInstr "rec2" (ty/tyVal) (ty/opVariantField "waitRes" 0))
            (ty/ssaInstr "statusBox" (ty/tyVal) (ty/opField "rec2" "status"))
            (ty/ssaInstr "status" (ty/tyI64) (ty/opUnbox "statusBox"))
            (sys/int64Const "zero" 0)
            (ty/ssaInstr "statusOk" (ty/tyI1) (ty/opPrim "eqInt" (list "status" "zero")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "eqRes" "statusOk"))))
          (boolBranch "allOk" "pass" "fail9")))
      (listAppend
        (passFailBlocks "pass" 0 "fail9" 9)
        (list (sentinelBlock "errSpawn" 1) (sentinelBlock "errRead" 2) (sentinelBlock "errWait" 7)))))

fn inheritEnvRealRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvList" "argv" (list 0 1 2))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "pathV" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawnRes" (ty/tyVal) "procSpawn" (list "pathV" "argvList" "envpList" "inheritEnv"))))
          (okErrSwitch "spawnRes" "spawnOk" "errSpawn"))
        (sys/block "spawnOk"
          (list
            (ty/ssaInstr "rec1" (ty/tyVal) (ty/opVariantField "spawnRes" 0))
            (ty/ssaInstr "pidBox" (ty/tyVal) (ty/opField "rec1" "pid"))
            (ty/ssaInstr "pid" (ty/tyI64) (ty/opUnbox "pidBox"))
            (ty/ssaInstr "outFdBox" (ty/tyVal) (ty/opField "rec1" "outFd"))
            (ty/ssaInstr "outFd" (ty/tyI64) (ty/opUnbox "outFdBox"))
            (ty/ssaInstr "outFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFd")))
            (ty/ssaInstr "errFdBox" (ty/tyVal) (ty/opField "rec1" "errFd"))
            (ty/ssaInstr "errFd" (ty/tyI64) (ty/opUnbox "errFdBox"))
            (ty/ssaInstr "errFd32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFd")))
            (sys/int64Const "max" 16)
            (sys/callInstr "readRes" (ty/tyVal) "sysRead" (list "outFd32" "max")))
          (okErrSwitch "readRes" "readOk" "errRead"))
        (sys/block "readOk"
          (list
            (ty/ssaInstr "actual" (ty/tyVal) (ty/opVariantField "readRes" 0))
            (constStrInstr "expected" 3)
            (sys/entryInstr "expectedBytes" (ty/tyVal) "stringToBytes" (list "expected"))
            (sys/entryInstr "eqRes" (ty/tyI1) "=" (list "expectedBytes" "actual"))
            (sys/callInstr "closeOut" (ty/tyVal) "sysClose" (list "outFd32"))
            (sys/callInstr "closeErr" (ty/tyVal) "sysClose" (list "errFd32"))
            (sys/int64Const "forever" -1)
            (sys/callInstr "waitRes" (ty/tyVal) "procWait" (list "pid" "forever")))
          (okErrSwitch "waitRes" "waitOk" "errWait"))
        (sys/block "waitOk"
          (list
            (ty/ssaInstr "rec2" (ty/tyVal) (ty/opVariantField "waitRes" 0))
            (ty/ssaInstr "statusBox" (ty/tyVal) (ty/opField "rec2" "status"))
            (ty/ssaInstr "status" (ty/tyI64) (ty/opUnbox "statusBox"))
            (sys/int64Const "zero" 0)
            (ty/ssaInstr "statusOk" (ty/tyI1) (ty/opPrim "eqInt" (list "status" "zero")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "eqRes" "statusOk"))))
          (boolBranch "allOk" "pass" "fail9")))
      (listAppend
        (passFailBlocks "pass" 0 "fail9" 9)
        (list (sentinelBlock "errSpawn" 1) (sentinelBlock "errRead" 2) (sentinelBlock "errWait" 7)))))

fn waitAnyNoStealRunFn -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (listAppend
      (list
        (sys/block "entry"
          (listAppend
            (strListConstInstrs "argvAList" "argvA" (list 0 1))
            (list
              (ty/ssaInstr "envpList" (ty/tyVal) (ty/opList (list)))
              (constStrInstr "pathAV" 0)
              (sys/int32Const "inheritEnv" 1)
              (sys/callInstr "spawnARes" (ty/tyVal) "procSpawn" (list "pathAV" "argvAList" "envpList" "inheritEnv"))))
          (okErrSwitch "spawnARes" "spawnAOk" "errSpawnA"))
        (sys/block "spawnAOk"
          (listAppend
            (list
              (ty/ssaInstr "recA" (ty/tyVal) (ty/opVariantField "spawnARes" 0))
              (ty/ssaInstr "pidABox" (ty/tyVal) (ty/opField "recA" "pid"))
              (ty/ssaInstr "pidA" (ty/tyI64) (ty/opUnbox "pidABox"))
              (ty/ssaInstr "outFdABox" (ty/tyVal) (ty/opField "recA" "outFd"))
              (ty/ssaInstr "outFdA" (ty/tyI64) (ty/opUnbox "outFdABox"))
              (ty/ssaInstr "outFdA32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFdA")))
              (ty/ssaInstr "errFdABox" (ty/tyVal) (ty/opField "recA" "errFd"))
              (ty/ssaInstr "errFdA" (ty/tyI64) (ty/opUnbox "errFdABox"))
              (ty/ssaInstr "errFdA32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFdA"))))
            (listAppend
              (strListConstInstrs "argvBList" "argvB" (list 2 3))
              (list
                (constStrInstr "pathBV" 2)
                (sys/callInstr "spawnBRes" (ty/tyVal) "procSpawn" (list "pathBV" "argvBList" "envpList" "inheritEnv")))))
          (okErrSwitch "spawnBRes" "spawnBOk" "errSpawnB"))
        (sys/block "spawnBOk"
          (list
            (ty/ssaInstr "recB" (ty/tyVal) (ty/opVariantField "spawnBRes" 0))
            (ty/ssaInstr "pidBBox" (ty/tyVal) (ty/opField "recB" "pid"))
            (ty/ssaInstr "pidB" (ty/tyI64) (ty/opUnbox "pidBBox"))
            (ty/ssaInstr "outFdBBox" (ty/tyVal) (ty/opField "recB" "outFd"))
            (ty/ssaInstr "outFdB" (ty/tyI64) (ty/opUnbox "outFdBBox"))
            (ty/ssaInstr "outFdB32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFdB")))
            (ty/ssaInstr "errFdBBox" (ty/tyVal) (ty/opField "recB" "errFd"))
            (ty/ssaInstr "errFdB" (ty/tyI64) (ty/opUnbox "errFdBBox"))
            (ty/ssaInstr "errFdB32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFdB")))
            (sys/callInstr "spawnCRes" (ty/tyVal) "procSpawn" (list "pathBV" "argvBList" "envpList" "inheritEnv")))
          (okErrSwitch "spawnCRes" "spawnCOk" "errSpawnC"))
        (sys/block "spawnCOk"
          (list
            (ty/ssaInstr "recC" (ty/tyVal) (ty/opVariantField "spawnCRes" 0))
            (ty/ssaInstr "pidCBox" (ty/tyVal) (ty/opField "recC" "pid"))
            (ty/ssaInstr "pidC" (ty/tyI64) (ty/opUnbox "pidCBox"))
            (ty/ssaInstr "outFdCBox" (ty/tyVal) (ty/opField "recC" "outFd"))
            (ty/ssaInstr "outFdC" (ty/tyI64) (ty/opUnbox "outFdCBox"))
            (ty/ssaInstr "outFdC32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "outFdC")))
            (ty/ssaInstr "errFdCBox" (ty/tyVal) (ty/opField "recC" "errFd"))
            (ty/ssaInstr "errFdC" (ty/tyI64) (ty/opUnbox "errFdCBox"))
            (ty/ssaInstr "errFdC32" (ty/tyI32) (ty/opPrim "rawNarrowI32" (list "errFdC")))
            (sys/int64Const "shortTimeout" 50)
            (sys/callInstr "anyRes" (ty/tyVal) "procWaitAny" (list "pidB" "pidC" "shortTimeout")))
          (okErrSwitch "anyRes" "anyOk" "errAny"))
        (sys/block "anyOk"
          (list
            (ty/ssaInstr "recAny" (ty/tyVal) (ty/opVariantField "anyRes" 0))
            (ty/ssaInstr "timedOutAnyBox" (ty/tyVal) (ty/opField "recAny" "timedOut"))
            (ty/ssaInstr "timedOutAny" (ty/tyI64) (ty/opUnbox "timedOutAnyBox"))
            (sys/int64Const "one" 1)
            (ty/ssaInstr "c1" (ty/tyI1) (ty/opPrim "eqInt" (list "timedOutAny" "one")))
            (sys/int64Const "forever" -1)
            (sys/callInstr "waitARes" (ty/tyVal) "procWait" (list "pidA" "forever")))
          (okErrSwitch "waitARes" "waitAOk" "errWaitA"))
        (sys/block "waitAOk"
          (list
            (ty/ssaInstr "recA2" (ty/tyVal) (ty/opVariantField "waitARes" 0))
            (ty/ssaInstr "statusABox" (ty/tyVal) (ty/opField "recA2" "status"))
            (ty/ssaInstr "statusA" (ty/tyI64) (ty/opUnbox "statusABox"))
            (ty/ssaInstr "timedOutABox" (ty/tyVal) (ty/opField "recA2" "timedOut"))
            (ty/ssaInstr "timedOutA" (ty/tyI64) (ty/opUnbox "timedOutABox"))
            (sys/int64Const "zero" 0)
            (ty/ssaInstr "c2" (ty/tyI1) (ty/opPrim "eqInt" (list "statusA" "zero")))
            (ty/ssaInstr "c3" (ty/tyI1) (ty/opPrim "eqInt" (list "timedOutA" "zero")))
            (sys/callInstr "closeOutA" (ty/tyVal) "sysClose" (list "outFdA32"))
            (sys/callInstr "closeErrA" (ty/tyVal) "sysClose" (list "errFdA32"))
            (sys/callInstr "closeOutB" (ty/tyVal) "sysClose" (list "outFdB32"))
            (sys/callInstr "closeErrB" (ty/tyVal) "sysClose" (list "errFdB32"))
            (sys/callInstr "closeOutC" (ty/tyVal) "sysClose" (list "outFdC32"))
            (sys/callInstr "closeErrC" (ty/tyVal) "sysClose" (list "errFdC32"))
            (sys/int64Const "sigkill" 9)
            (sys/callInstr "killBRes" (ty/tyVal) "procKill" (list "pidB" "sigkill"))
            (sys/int64Const "reapTimeout" 2000)
            (sys/callInstr "reapBRes" (ty/tyVal) "procWait" (list "pidB" "reapTimeout"))
            (sys/callInstr "killCRes" (ty/tyVal) "procKill" (list "pidC" "sigkill"))
            (sys/callInstr "reapCRes" (ty/tyVal) "procWait" (list "pidC" "reapTimeout"))
            (ty/ssaInstr "c12" (ty/tyI1) (ty/opPrim "andBool" (list "c1" "c2")))
            (ty/ssaInstr "allOk" (ty/tyI1) (ty/opPrim "andBool" (list "c12" "c3"))))
          (boolBranch "allOk" "pass" "fail12")))
      (listAppend
        (passFailBlocks "pass" 0 "fail12" 12)
        (list (sentinelBlock "errSpawnA" 1) (sentinelBlock "errSpawnB" 2) (sentinelBlock "errSpawnC" 3)
              (sentinelBlock "errAny" 4) (sentinelBlock "errWaitA" 5)))))

fn ! testSpawnEcho work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/bin/echo" "hi") (list (spawnEchoRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "spawnEcho: emits: " text))
        (writeAndLink work "spawnEcho" text)
        (verifyLl "spawnEcho" work "spawnEcho")
        (expectExit "spawnEcho: native checks pass" (str work "/spawnEcho") 0)))

fn ! testSpawnTimeoutKill work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/bin/sleep" "2") (list (spawnTimeoutKillRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "spawnTimeoutKill: emits: " text))
        (writeAndLink work "spawnTimeoutKill" text)
        (verifyLl "spawnTimeoutKill" work "spawnTimeoutKill")
        (expectExit "spawnTimeoutKill: native checks pass" (str work "/spawnTimeoutKill") 0)))

fn ! testWaitAny work: String facts: libc/TripleFacts -> Bool
  (let [(strings (list "/bin/sleep" "2" "/bin/echo" "hi"))
        (text (textOf (llvm/emitLlvmProgram (moduleOf facts strings (list (waitAnyRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "waitAny: emits: " text))
        (writeAndLink work "waitAny" text)
        (verifyLl "waitAny" work "waitAny")
        (expectExit "waitAny: native checks pass" (str work "/waitAny") 0)))

fn ! testHostComparison work: String -> Bool
  (let [(ref (sh "echo hi")) (hRes (processSpawn "/bin/echo hi"))]
    (mt hRes
      ((err e) (do (assert false (str "testHostComparison: processSpawn failed: " e)) false))
      ((ok h)
       (let [(wRes (processWait h 2000))]
         (mt wRes
           ((err e) (do (assert false (str "testHostComparison: processWait failed: " e)) false))
           ((ok out)
            (do (assert (= out.exitCode ref.exitCode) (str "testHostComparison: exit " out.exitCode ", want " ref.exitCode))
                (assert (= out.stdout ref.stdout) (str "testHostComparison: stdout " out.stdout ", want " ref.stdout))
                true)))))))

fn ! testProcPidRange work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list) (list (pidRangeRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "procPidRange: emits: " text))
        (writeAndLink work "procPidRange" text)
        (expectExit "procPidRange: high pid returns EINVAL without signaling a process group" (str work "/procPidRange") 0)))

fn ! testProcSelf work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/bin/sh" "-c" "echo $PPID" "\n") (list (procSelfRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "procSelf: emits: " text))
        (writeAndLink work "procSelf" text)
        (verifyLl "procSelf" work "procSelf")
        (expectExit "procSelf: native checks pass" (str work "/procSelf") 0)))

fn ! testProcAlive work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/bin/sleep" "2") (list (procAliveRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "procAlive: emits: " text))
        (writeAndLink work "procAlive" text)
        (verifyLl "procAlive" work "procAlive")
        (expectExit "procAlive: native checks pass" (str work "/procAlive") 0)))

fn ! testSpawnEnoent work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/nonexistent/binS6NoSuchFile") (list (spawnEnoentRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "spawnEnoent: emits: " text))
        (writeAndLink work "spawnEnoent" text)
        (verifyLl "spawnEnoent" work "spawnEnoent")
        (expectExit "spawnEnoent: native checks pass" (str work "/spawnEnoent") 0)))

fn ! testInheritEnv work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/bin/sh" "-c" "echo $FOO" "FOO=bar" "bar\n") (list (inheritEnvRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "inheritEnv: emits: " text))
        (writeAndLink work "inheritEnv" text)
        (verifyLl "inheritEnv" work "inheritEnv")
        (expectExit "inheritEnv: native checks pass" (str work "/inheritEnv") 0)))

fn ! testInheritEnvReal work: String facts: libc/TripleFacts -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (moduleOf facts (list "/bin/sh" "-c" "echo $FOO" "bar\n") (list (inheritEnvRealRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "inheritEnvReal: emits: " text))
        (writeAndLink work "inheritEnvReal" text)
        (verifyLl "inheritEnvReal" work "inheritEnvReal")
        (expectExit "inheritEnvReal: native checks pass under the parent's own FOO=bar" (str "env FOO=bar " work "/inheritEnvReal") 0)))

fn ! testWaitAnyNoSteal work: String facts: libc/TripleFacts -> Bool
  (let [(strings (list "/bin/echo" "hi" "/bin/sleep" "2"))
        (text (textOf (llvm/emitLlvmProgram (moduleOf facts strings (list (waitAnyNoStealRunFn))) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "waitAnyNoSteal: emits: " text))
        (writeAndLink work "waitAnyNoSteal" text)
        (verifyLl "waitAnyNoSteal" work "waitAnyNoSteal")
        (expectExit "waitAnyNoSteal: native checks pass" (str work "/waitAnyNoSteal") 0)))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))
        (facts (hostFacts))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testSpawnEcho work facts)
        (testSpawnTimeoutKill work facts)
        (testWaitAny work facts)
        (testWaitAnyNoSteal work facts)
        (testProcSelf work facts)
        (testProcAlive work facts)
        (testProcPidRange work facts)
        (testSpawnEnoent work facts)
        (testInheritEnv work facts)
        (testInheritEnvReal work facts)
        (testHostComparison work)
        (testProc work)
        (testProcFwd work)
        (testProcLinux work (libc/linuxX8664Facts) "x86_64")
        (testProcLinux work (libc/linuxAarch64Facts) "aarch64")
        (assert (= (exitOf (str "rm -rf " work)) 0) "work directory removed")
        true))

fn probeEnv -> String
  "env SYSROUTE_PROBE='sysRoute 42' "

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn routedNames -> (List String)
  (list "procSpawnv" "procWaitPid" "procWaitAny" "procPoll" "procRusage" "procExecv")

fn cTableCall name: String -> String
  (str "@asl_rt_builtin_sys(ptr @name." (ssa/llvmName name) ",")

fn wrapperDef name: String -> String
  (str "define internal tailcc %Val @" (ssa/llvmName (str "asl-target-llvm/sysRoute." name)) "(")

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

fn procSource work: String -> String
  (lines (list
    "(module sysProcProbe :x [main] :i [])"
    ""
    "fn ! readAll fd: Int64 acc: String -> String"
    "  (mt (fdRead fd 4096)"
    "    ((err e) (str acc \"<err \" e \">\"))"
    "    ((ok s) (if (= (stringLength s) 0) acc (readAll fd (str acc s)))))"
    ""
    "fn flat s: String -> String"
    "  (stringReplace s \"\\n\" \"|\")"
    ""
    "fn noDigits s: String -> String"
    "  (fold (fn [(acc String) (d String)] -> String (stringReplace acc d \"\")) s (list \"0\" \"1\" \"2\" \"3\" \"4\" \"5\" \"6\" \"7\" \"8\" \"9\"))"
    ""
    "fn ! closeAll c: SpawnedProc -> Bool"
    "  (do (fdClose c.stdin) (fdClose c.stdout) (fdClose c.stderr) true)"
    ""
    "fn ! run argv: (List String) cwd: (Option String) env: (Option (List String)) -> String"
    "  (mt (procSpawnv argv cwd env)"
    "    ((err e) (str \"err \" e))"
    "    ((ok c) (let [(out (readAll c.stdout \"\"))"
    "                  (w (procWaitPid c.pid false))]"
    "              (do (closeAll c) (str (flat out) \" \" w)))))"
    ""
    "fn ! envVar name: String -> String"
    "  (fold (fn [(acc String) (kv String)] -> String (if (stringStartsWith? kv (str name \"=\")) (stringReplace kv (str name \"=\") \"\") acc)) \"\" (envList))"
    ""
    "fn ! self -> String"
    "  (mt (procExePath)"
    "    ((err e) (str \"exe err \" e))"
    (str "    ((ok p) (if (stringEndsWith? p \"/asl-host\") (str p \" run \" \"" work "/sysProc.asl\") p)))")
    ""
    "fn label pid: Int64 names: (List (Pair Int64 String)) -> String"
    "  (fold (fn [(acc String) (p (Pair Int64 String))] -> String (mt p ((pair q n) (if (= q pid) n acc)))) \"other\" names)"
    ""
    "fn anyShape res: (Result (Option (Pair Int64 Int64)) String) names: (List (Pair Int64 String)) -> String"
    "  (mt res"
    "    ((err e) (str \"err \" e))"
    "    ((ok o) (mt o ((none) \"ok none\") ((some p) (mt p ((pair pid code) (str \"ok \" (label pid names) \" \" code)))))))"
    ""
    "fn pollShape res: (Result (Pair (List (Pair Int64 Int64)) (List (Pair Int64 Int64))) String) names: (List (Pair Int64 String)) -> String"
    "  (mt res"
    "    ((err e) (str \"err \" e))"
    "    ((ok r) (mt r ((pair fds pids)"
    "                   (str \"ok fds\" (fold (fn [(acc String) (p (Pair Int64 Int64))] -> String (mt p ((pair fd m) (str acc \" \" (label fd names) \":\" m)))) \"\" fds)"
    "                        \" pids\" (fold (fn [(acc String) (p (Pair Int64 Int64))] -> String (mt p ((pair pid code) (str acc \" \" (label pid names) \":\" code)))) \"\" pids))))))"
    ""
    "fn ! spawnCases -> Bool"
    "  (do (println \"echo\" (run (list \"/bin/echo\" \"hi\" \"there\") (none) (none)))"
    "      (println \"exit 7\" (run (list \"/bin/sh\" \"-c\" \"exit 7\") (none) (none)))"
    "      (println \"missing\" (run (list \"/nonexistent/procProbe\") (none) (none)))"
    "      (println \"not on path\" (run (list \"procProbeNoSuchCmd\") (none) (none)))"
    "      (println \"env path\" (run (list \"echo\" \"via env\") (none) (some (list \"PATH=/bin\"))))"
    "      (println \"env no path\" (run (list \"echo\" \"x\") (none) (some (list \"PATH=/nonexistent\"))))"
    "      (println \"env var\" (run (list \"/bin/sh\" \"-c\" \"echo $PROBE_V:$HOME\") (none) (some (list \"PROBE_V=v1\"))))"
    "      (println \"env empty\" (run (list \"/usr/bin/env\") (none) (some (list))))"
    "      (println \"cwd\" (run (list \"/bin/pwd\") (some \"/\") (none)))"
    "      (println \"cwd missing\" (run (list \"/bin/pwd\") (some \"/nonexistent/dir\") (none)))"
    "      (println \"record\" (mt (procSpawnv (list \"/bin/sh\" \"-c\" \"read l; echo got $l; echo oops >&2; exit 2\") (none) (none))"
    "                          ((err e) (str \"err \" e))"
    "                          ((ok c) (let [(shape (str (noDigits (str c)) \" \" (> c.pid 0) \" \" (>= c.stdin 3) \" \" (>= c.stdout 3) \" \" (>= c.stderr 3)))"
    "                                        (wrote (fdWrite c.stdin \"line\\n\"))"
    "                                        (out (readAll c.stdout \"\"))"
    "                                        (errOut (readAll c.stderr \"\"))"
    "                                        (w (procWaitPid c.pid false))]"
    "                                    (do (closeAll c) (str shape \" \" wrote \" \" (flat out) \" \" (flat errOut) \" \" w))))))"
    "      (println \"spawn args\" (procSpawnv (list) (none) (none)) (procSpawnv \"x\" (none) (none)) (procSpawnv (list 1) (none) (none)) (procSpawnv (list \"/bin/echo\" 2) (none) (none)))"
    "      (println \"spawn cwd args\" (procSpawnv (list \"/bin/echo\") 5 (none)) (procSpawnv (list \"/bin/echo\") (some 5) (none)) (procSpawnv (list \"/bin/echo\") (some \"\") (none)) (procSpawnv (list) (some 5) (none)))"
    "      (println \"spawn env args\" (procSpawnv (list \"/bin/echo\") (none) 5) (procSpawnv (list \"/bin/echo\") (none) (some 5)) (procSpawnv (list \"/bin/echo\") (none) (some (list \"NOEQ\"))) (procSpawnv (list \"/bin/echo\") (none) (some (list \"=x\"))) (procSpawnv (list \"/bin/echo\") (none) (some (list 3))))"
    "      true)"
    ""
    "fn ! waitCases -> Bool"
    "  (mt (procSpawnv (list \"/bin/sleep\" \"5\") (none) (none))"
    "    ((err e) (do (println \"sleep spawn\" e) false))"
    "    ((ok c) (let [(p c.pid) (names (list (pair p \"sleep\") (pair c.stdout \"out\")))]"
    "              (do (println \"running nohang\" (procWaitPid p true))"
    "                  (println \"waitAny 50\" (anyShape (procWaitAny (list p) 50) names))"
    "                  (println \"poll 50\" (pollShape (procPoll (list) (list p) 50) names))"
    "                  (println \"poll fd 0\" (pollShape (procPoll (list (pair c.stdout 1)) (list p) 0) names))"
    "                  (println \"kill\" (procKill p \"SIGTERM\"))"
    "                  (println \"killed\" (procWaitPid p false))"
    "                  (println \"reaped nohang\" (procWaitPid p true))"
    "                  (println \"reaped wait\" (procWaitPid p false))"
    "                  (println \"poll eof\" (pollShape (procPoll (list (pair c.stdout 1)) (list) 0) names))"
    "                  (closeAll c)))))"
    ""
    "fn ! anyCases -> Bool"
    "  (mt (procSpawnv (list \"/bin/sleep\" \"5\") (none) (none))"
    "    ((err e) (do (println \"a spawn\" e) false))"
    "    ((ok a) (mt (procSpawnv (list \"/bin/sh\" \"-c\" \"exit 3\") (none) (none))"
    "      ((err e) (do (println \"b spawn\" e) false))"
    "      ((ok b) (mt (procSpawnv (list \"/bin/sleep\" \"5\") (none) (none))"
    "        ((err e) (do (println \"c spawn\" e) false))"
    "        ((ok c) (let [(names (list (pair a.pid \"a\") (pair b.pid \"b\") (pair c.pid \"c\")))]"
    "          (do (println \"any of three\" (anyShape (procWaitAny (list a.pid b.pid c.pid) 5000) names))"
    "              (println \"kill a\" (procKill a.pid \"SIGTERM\") (procWaitPid a.pid false))"
    "              (println \"kill c\" (procKill c.pid \"SIGKILL\") (anyShape (procWaitAny (list c.pid) -1) names))"
    "              (println \"any reaped\" (anyShape (procWaitAny (list b.pid) 0) names))"
    "              (closeAll a) (closeAll b) (closeAll c)"
    "              true))))))))"
    ""
    "fn ! pollCases -> Bool"
    "  (mt (procSpawnv (list \"/bin/sh\" \"-c\" \"read l; exit 4\") (none) (none))"
    "    ((err e) (do (println \"z spawn\" e) false))"
    "    ((ok z) (let [(names (list (pair z.pid \"z\") (pair z.stdout \"zout\") (pair z.stdin \"zin\")))]"
    "              (do (println \"poll before\" (pollShape (procPoll (list (pair z.stdout 1)) (list z.pid) 0) names))"
    "                  (println \"poll writable\" (pollShape (procPoll (list (pair z.stdin 2)) (list z.pid) 0) names))"
    "                  (println \"release\" (fdWrite z.stdin \"go\\n\"))"
    "                  (println \"poll exit\" (pollShape (procPoll (list) (list z.pid) 5000) names))"
    "                  (println \"poll after\" (pollShape (procPoll (list) (list z.pid) 0) names))"
    "                  (closeAll z)"
    "                  (mt (procSpawnv (list \"/bin/sh\" \"-c\" \"exit 5\") (none) (none))"
    "                    ((err e) (do (println \"x spawn\" e) false))"
    "                    ((ok x) (mt (procSpawnv (list \"/bin/sh\" \"-c\" \"exit 6\") (none) (none))"
    "                      ((err e) (do (println \"y spawn\" e) false))"
    "                      ((ok y) (let [(both (list (pair x.pid \"x\") (pair y.pid \"y\")))"
    "                                    (_ (run (list \"/bin/sleep\" \"0.3\") (none) (none)))]"
    "                                (do (println \"poll reaps both\" (pollShape (procPoll (list) (list x.pid y.pid) 0) both))"
    "                                    (closeAll x) (closeAll y) true))))))))))"
    ""
    "fn ! argCases -> Bool"
    "  (do (println \"waitPid args\" (procWaitPid \"1\" false) (procWaitPid 1 \"x\") (procWaitPid 0 false) (procWaitPid -5 true) (procWaitPid 2147483648 true) (procWaitPid 1 true) (procWaitPid 1 false))"
    "      (println \"waitAny args\" (procWaitAny (list) 0) (procWaitAny (list 1) -2) (procWaitAny (list 1) \"0\") (procWaitAny \"x\" 0) (procWaitAny (list 0) 0) (procWaitAny (list 2147483648) 0) (procWaitAny \"x\" -2) (procWaitAny (list 1) 0))"
    "      (println \"poll args\" (procPoll 5 (list) 0) (procPoll (list) (list) -2) (procPoll (list) \"x\" 0) (procPoll (list (pair -1 1)) (list) 0) (procPoll (list (pair 0 4)) (list) 0) (procPoll (list (pair 0 0)) (list) 0) (procPoll (list (list 0)) (list) 0) (procPoll (list (pair 0 1)) (list -1) 0))"
    "      (println \"poll empty\" (procPoll (list) (list) 0) (procPoll (list) (list) 30) (procPoll (list) (list 1) 0))"
    "      (println \"execv args\" (procExecv (list) (none)) (procExecv \"x\" (none)) (procExecv (list 1) (none)) (procExecv (list \"/bin/echo\") 5) (procExecv (list \"/bin/echo\") (some (list \"X\"))) (procExecv (list \"/bin/echo\") (some 1)))"
    "      (println \"execv missing\" (procExecv (list \"/nonexistent/procProbe\") (none)) (procExecv (list \"procProbeNoSuchCmd\") (some (list \"PATH=/bin\"))))"
    "      true)"
    ""
    "fn ! rusageCase -> Bool"
    "  (mt (procRusage)"
    "    ((err e) (do (println \"rusage err\" e) false))"
    "    ((ok r) (do (println \"rusage\" (noDigits (str r)) (> r.selfMaxRssKb 0) (>= r.selfUserUs 0) (>= r.selfSysUs 0) (> r.childrenMaxRssKb 0) (>= r.childrenUserUs 0) (>= r.childrenSysUs 0))"
    "                true)))"
    ""
    "fn ! execCases -> Bool"
    "  (do (println \"exec echo\" (run (list \"/bin/sh\" \"-c\" (str \"PROC_MODE=exec \" (self))) (none) (none)))"
    "      (println \"exec env\" (run (list \"/bin/sh\" \"-c\" (str \"PROC_MODE=execenv \" (self))) (none) (none)))"
    "      (println \"exec missing\" (run (list \"/bin/sh\" \"-c\" (str \"PROC_MODE=execmissing \" (self))) (none) (none)))"
    "      true)"
    ""
    "fn ! execMode mode: String -> (Result Int64 String)"
    "  (do (print \"pre \")"
    "      (println \"returned\" (cond ((= mode \"exec\") (procExecv (list \"/bin/echo\" \"exec\" \"ok\") (none)))"
    "                                ((= mode \"execenv\") (procExecv (list \"sh\" \"-c\" \"echo $EV\") (some (list \"EV=fromEnv\" \"PATH=/bin\"))))"
    "                                (else (procExecv (list \"/nonexistent/procProbe\") (none)))))"
    "      (ok 3))"
    ""
    "fn ! fwdMode -> (Result Int64 String)"
    "  (let [(dir (envVar \"PROC_DIR\"))]"
    "    (mt (procSpawnv (list \"/bin/sh\" \"-c\" (str \"trap 'echo term > \" dir \"/term; exit 9' TERM; echo ready > \" dir \"/ready; while :; do sleep 0.05; done\")) (none) (none))"
    "      ((err e) (do (println \"fwd spawn\" e) (ok 1)))"
    "      ((ok c) (do (println \"fwd spawned\")"
    "                  (println \"fwd waited\" (procWaitPid c.pid false))"
    "                  (ok 0)))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(mode (envVar \"PROC_MODE\"))]"
    "    (cond ((stringStartsWith? mode \"exec\") (execMode mode))"
    "          ((= mode \"fwd\") (fwdMode))"
    "          (else (do (spawnCases) (waitCases) (anyCases) (pollCases) (argCases) (rusageCase) (execCases) (ok 0)))))"
    ))

fn procNames -> (List String)
  (list "procSpawnv" "procWaitPid" "procWaitAny" "procPoll" "procRusage" "procExecv")

fn procWant -> String
  (let [(inval "(err \"io:22\")")
        (ten (fn [(k Int64) (s String)] -> String (stringJoin (map (fn [(i Int64)] -> String s) (range 0 k)) " ")))]
    (lines (list "echo hi there| (ok (some 0))" "exit 7  (ok (some 7))" "missing err notFound" "not on path err notFound"
                 "env path via env| (ok (some 0))" "env no path err notFound" "env var v1:| (ok (some 0))" "env empty  (ok (some 0))"
                 "cwd /| (ok (some 0))" "cwd missing err notFound"
                 "record {:pid  :stdin  :stdout  :stderr } true true true true (ok 5) got line| oops| (ok (some 2))"
                 (str "spawn args " (ten 4 inval)) (str "spawn cwd args " (ten 4 inval)) (str "spawn env args " (ten 5 inval))
                 "running nohang (ok (none))" "waitAny 50 ok none" "poll 50 ok fds pids" "poll fd 0 ok fds pids"
                 "kill (ok ())" "killed (ok (some -15))" "reaped nohang (err \"noChild\")" "reaped wait (err \"noChild\")" "poll eof ok fds out:5 pids"
                 "any of three ok b 3" "kill a (ok ()) (ok (some -15))" "kill c (ok ()) ok c -9" "any reaped err noChild"
                 "poll before ok fds pids" "poll writable ok fds zin:2 pids" "release (ok 3)" "poll exit ok fds pids z:4" "poll after err noChild"
                 "poll reaps both ok fds pids x:5 y:6"
                 (str "waitPid args " (ten 5 inval) " (err \"noChild\") (err \"noChild\")")
                 (str "waitAny args " (ten 7 inval) " (err \"noChild\")")
                 (str "poll args " (ten 3 inval) " (err \"badFd\") " (ten 4 inval))
                 "poll empty (ok (pair () ())) (ok (pair () ())) (err \"noChild\")"
                 (str "execv args " (ten 6 inval))
                 "execv missing (err \"notFound\") (err \"notFound\")"
                 "rusage {:selfMaxRssKb  :selfUserUs  :selfSysUs  :childrenMaxRssKb  :childrenUserUs  :childrenSysUs } true true true true true true"
                 "exec echo pre exec ok| (ok (some 0))" "exec env pre fromEnv| (ok (some 0))" "exec missing pre returned (err \"notFound\")| (ok (some 3))")))

fn ! testProc work: String -> Bool
  (let [(ll (build work "sysProc" (procSource work)))
        (_ (checkIr "sysProc" ll (procNames)))
        (_ (linkBin work "sysProc"))
        (outs (checkParity "sysProc" (str work "/sysProc") (str work "/sysProc.asl")))]
    (do (assert (= (pairFirst outs).stdout (procWant)) (str "sysProc: each case prints sys.c's result: " (pairFirst outs).stdout))
        true))

fn ! fwdRun work: String tag: String cmd: String -> String
  (let [(dir (str work "/" tag))
        (script (str "mkdir -p " dir "; PROC_MODE=fwd PROC_DIR=" dir " " cmd " > " dir "/out & P=$!; i=0; "
                     "while [ ! -f " dir "/ready ] && [ $i -lt 400 ]; do sleep 0.05; i=$((i+1)); done; sleep 0.3; "
                     "kill -TERM $P; wait $P; echo status=$?; cat " dir "/out; cat " dir "/term"))]
    (sh script).stdout)

fn ! testProcFwd work: String -> Bool
  (let [(want (lines (list "status=143" "fwd spawned" "term")))
        (native (fwdRun work "fwdNative" (str work "/sysProc")))
        (vm (fwdRun work "fwdVm" (str (host) " run " work "/sysProc.asl")))]
    (do (assert (= vm want) (str "sysProc fwd: asl-host run forwards SIGTERM and dies by it: " vm))
        (assert (= native want) (str "sysProc fwd: the native binary forwards SIGTERM and dies by it, as asl-host run: " native))
        true))

fn ! testProcLinux work: String facts: libc/TripleFacts arch: String -> Bool
  (let [(label (str "sysProc linux-" arch))]
    (mt (lowered label (procSource work))
      ((none) false)
      ((some m)
        (mt (llvm/emitLlvmProgramFor facts m "main")
          ((err ds) (do (assert false (str label ": emitLlvmProgramFor: " (diagText ds))) false))
          ((ok text)
            (do (checkIr label text (procNames))
                (assert (stringContains? text "@signalfd(") (str label " forwards signals through signalfd"))
                (assert (stringContains? text "@syscall(") (str label " opens pidfds through syscall"))
                (assert (stringContains? text "@dlsym(") (str label " finds environ through dlsym"))
                (assert (not (stringContains? text "@kqueue(")) (str label " has no darwin kqueue"))
                (assert (not (stringContains? text "@_NSGetEnviron(")) (str label " has no darwin _NSGetEnviron"))
                (assert (ok? (fileWrite (str work "/sysProcLinux-" arch ".ll") text)) (str label ".ll written"))
                (verifyLl label work (str "sysProcLinux-" arch))))))))
