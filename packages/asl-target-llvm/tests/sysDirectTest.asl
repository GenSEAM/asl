(module asl-target-llvm/tests/sysDirectTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/sys :a sys)
      (asl-target-llvm/libc :a libc)])

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn host -> String
  "asl/host/out/asl-host"

fn ! repoRootAbs -> String
  (stringTrim (sh "pwd").stdout)

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! expectExit label: String cmd: String want: Int64 -> Bool
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode want) (str label ": exit " out.exitCode ", want " want "; stderr: " out.stderr))
        true))

fn ! writeAndLink work: String name: String text: String -> Bool
  (let [(ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite ll text)) (str name ": .ll written"))
        (expectExit (str name ": clang links against " (lib)) (str (clang) " -x ir " ll " -x none " (lib) " -lm -o " work "/" name) 0)))

fn edge target: String -> ty/SsaEdge
  (ty/ssaEdge target (list))

fn okErrSwitch scrutinee: String okLabel: String errLabel: String -> ty/SsaTerm
  (ty/termSwitch scrutinee "Result" (list (ty/ssaCase "ok" (edge okLabel)) (ty/ssaCase "err" (edge errLabel))) (none))

fn someNoneSwitch scrutinee: String someLabel: String noneLabel: String -> ty/SsaTerm
  (ty/termSwitch scrutinee "Option" (list (ty/ssaCase "some" (edge someLabel)) (ty/ssaCase "none" (edge noneLabel))) (none))

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Darwin") (or (= m "x86_64") (= m "x86"))) "darwin-x86_64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (mt (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "hostFacts: no verified libc.asl row for this host's triple (uname says \"" (hostTriple) "\"); add one, probe-verified, not guessed, before running this gate here")) (libc/emptyTripleFacts))))

fn ! dateFromEpoch epoch: Int64 fmt: String -> ProcessOutput
  (if (= (stringReplace (sh "uname -s").stdout "\n" "") "Darwin")
    (sh (str "TZ=UTC date -r " epoch " +\"" fmt "\""))
    (sh (str "TZ=UTC date -d @" epoch " +\"" fmt "\"")))

fn moduleOf facts: libc/TripleFacts strings: (List String) functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" strings (list (sys/resultTypeDecl) (sys/optionTypeDecl)) (list) (sys/sysExterns facts) (list) functions)

fn textOf res: (Result String (List ty/IrDiag)) -> String
  (mt res ((ok text) text) ((err diags) (str "ERR: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code "@" d.locus ": " d.message)) diags) " || "))))

fn constOf facts: libc/TripleFacts name: String -> Int64
  (optionOr (libc/libcConst facts name) -1)

fn errCaseInstrs -> (List ty/SsaInstr)
  (list (ty/ssaInstr "errBox" (ty/tyVal) (ty/opVariantField "resv" 0))
        (ty/ssaInstr "errCode" (ty/tyI64) (ty/opUnbox "errBox")))

fn ! unwrapFn label: String res: (Result ty/SsaFunction String) -> ty/SsaFunction
  (mt res
    ((ok f) f)
    ((err e) (do (assert false (str label ": " e)) (sys/sysGetpidFn))))

fn runFn entryPre: (List ty/SsaInstr) callee: String callArgs: (List String) okInstrs: (List ty/SsaInstr) okReturn: String -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (list (sys/block "entry"
            (listAppend entryPre (list (sys/callInstr "resv" (ty/tyVal) callee callArgs)))
            (okErrSwitch "resv" "okCase" "errCase"))
          (sys/block "okCase" okInstrs (ty/termReturn okReturn))
          (sys/block "errCase" (errCaseInstrs) (ty/termReturn "errCode"))))

fn caseModule facts: libc/TripleFacts strings: (List String) needed: (List ty/SsaFunction) entryPre: (List ty/SsaInstr) callee: String callArgs: (List String) okInstrs: (List ty/SsaInstr) okReturn: String -> ty/SsaModule
  (moduleOf facts strings (listAppend (cons (sys/sysErrnoValueFn facts) needed) (list (runFn entryPre callee callArgs okInstrs okReturn))))

fn errnoCaseModule facts: libc/TripleFacts strings: (List String) needed: (List ty/SsaFunction) entryPre: (List ty/SsaInstr) callee: String callArgs: (List String) -> ty/SsaModule
  (caseModule facts strings needed entryPre callee callArgs (list (sys/int64Const "dummy" 0)) "dummy")

fn getenvModule facts: libc/TripleFacts strings: (List String) someInstrs: (List ty/SsaInstr) someReturn: String noneReturn: Int64 -> ty/SsaModule
  (moduleOf facts strings (list (sys/sysGetenvFn)
    (ty/ssaFunction "run" (list) (list) (ty/tyI64)
      (list (sys/block "entry"
              (list (ty/ssaInstr "nameV" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                    (sys/callInstr "resv" (ty/tyVal) "sysGetenv" (list "nameV")))
              (someNoneSwitch "resv" "someCase" "noneCase"))
            (sys/block "someCase" someInstrs (ty/termReturn someReturn))
            (sys/block "noneCase" (list (sys/int64Const "noneSentinel" noneReturn)) (ty/termReturn "noneSentinel"))))))

fn ! runCase work: String name: String module: ty/SsaModule cmd: String -> ProcessOutput
  (let [(text (textOf (llvm/emitLlvmProgram module "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str name ": emits: " text))
        (writeAndLink work name text)
        (sh cmd)))

fn ! runPlain work: String name: String module: ty/SsaModule -> ProcessOutput
  (runCase work name module (str work "/" name))

fn ! runWithFd3 work: String name: String module: ty/SsaModule path: String -> ProcessOutput
  (runCase work name module (str "exec 3<>'" path "' && exec " work "/" name))

fn ! expectErrno label: String out: ProcessOutput facts: libc/TripleFacts name: String -> Bool
  (let [(want (constOf facts name))]
    (do (assert (not (= want -1)) (str label ": " name " is in libc/libcConst for " facts.triple))
        (assert (= out.exitCode want) (str label ": exit " out.exitCode ", want " name "=" want "; stderr: " out.stderr))
        true))

fn ! declaresReal text: String decl: String -> Bool
  (do (assert (stringContains? text decl) (str "declares: " decl)) true)

fn ! neverBuiltin text: String name: String -> Bool
  (do (assert (not (stringContains? text name)) (str "never calls the " name " builtin")) true)

fn ! testRead work: String facts: libc/TripleFacts -> Bool
  (let [(okMod (caseModule facts (list) (list (sys/sysReadFn))
                 (list (sys/int32Const "fd" 0) (sys/int64Const "max" 256)) "sysRead" (list "fd" "max")
                 (list (ty/ssaInstr "bytes" (ty/tyVal) (ty/opVariantField "resv" 0))
                       (sys/entryInstr "n" (ty/tyI64) "bytesLength" (list "bytes")))
                 "n"))
        (errMod (errnoCaseModule facts (list) (list (sys/sysReadFn))
                  (list (sys/int32Const "fd" -1) (sys/int64Const "max" 10)) "sysRead" (list "fd" "max")))
        (okText (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal okText "declare i64 @read(i32, ptr, i64)")
        (assert (stringContains? okText "icmp eq ptr") "read ok: sysRead's malloc'd scratch buffer is NULL-checked (rawPtrIsNull)")
        (neverBuiltin okText "fdRead")
        (writeAndLink work "sysReadOk" okText)
        (let [(out (sh (str "printf 'abcde' | " work "/sysReadOk")))]
          (do (assert (= out.exitCode 5) (str "read ok: exit " out.exitCode ", want 5 (bytes read)"))
              (assert (ok? (fileWrite (str work "/readFixture.asl")
                              "(module tests/readFixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n  (mt (fdRead 0 256) ((ok s) (ok (stringLength s))) ((err e) (err e)))\n"))
                      "read ok: asl-host comparison fixture written")
              (let [(hostOut (sh (str "printf 'abcde' | " (host) " run " work "/readFixture.asl")))]
                (assert (= out.exitCode hostOut.exitCode) (str "read ok: native byte count equals the asl-host run's: native=" out.exitCode " host=" hostOut.exitCode)))))
        (expectErrno "read err" (runPlain work "sysReadErr" errMod) facts "EBADF")))

fn ! testReadZeroLength work: String facts: libc/TripleFacts -> Bool
  (let [(okMod (caseModule facts (list) (list (sys/sysReadFn))
                 (list (sys/int32Const "fd" 0) (sys/int64Const "max" 0)) "sysRead" (list "fd" "max")
                 (list (ty/ssaInstr "bytes" (ty/tyVal) (ty/opVariantField "resv" 0))
                       (sys/entryInstr "n" (ty/tyI64) "bytesLength" (list "bytes")))
                 "n"))
        (okText (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (assert (stringContains? okText "icmp eq ptr") "read zero-length ok: scratch buffer is still NULL-checked, even though it is malloc'd at max(0,1)=1, not malloc(0)")
        (assert (stringContains? okText "bb.size$2Ez:\n  %size$2Eone = bitcast i64 1 to i64") "read zero-length ok: the zero-size branch allocates 1 byte (atLeastOneBlocks), not 0 -- malloc(0) is implementation-defined NULL and this host's malloc happens not to, so this IR-text check is the one that actually catches a size.z regression")
        (writeAndLink work "sysReadZeroOk" okText)
        (let [(out (sh (str "printf '' | " work "/sysReadZeroOk")))]
          (do (assert (= out.exitCode 0) (str "read zero-length ok: exit " out.exitCode ", want 0 (read(fd, buf, 0) returns 0 bytes, not an error)"))
              true))))

fn ! testFreeDeclaredPtr work: String facts: libc/TripleFacts -> Bool
  (let [(errMod (errnoCaseModule facts (list) (list (sys/sysReadFn)) (list (sys/int32Const "fd" -1) (sys/int64Const "max" 10)) "sysRead" (list "fd" "max")))
        (text (textOf (llvm/emitLlvmProgram errMod "run")))]
    (declaresReal text "declare i64 @free(ptr)"))

fn ! testWrite work: String facts: libc/TripleFacts -> Bool
  (let [(text "hello from native\n")
        (okMod (caseModule facts (list text) (list (sys/sysWriteFn))
                 (list (sys/int32Const "fd" 1) (ty/ssaInstr "data" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysWrite" (list "fd" "data")
                 (list (ty/ssaInstr "cntBox" (ty/tyVal) (ty/opVariantField "resv" 0)) (ty/ssaInstr "cnt" (ty/tyI64) (ty/opUnbox "cntBox")))
                 "cnt"))
        (errMod (errnoCaseModule facts (list "x") (list (sys/sysWriteFn))
                  (list (sys/int32Const "fd" -1) (ty/ssaInstr "data" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysWrite" (list "fd" "data")))
        (okText (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal okText "declare i64 @write(i32, ptr, i64)")
        (neverBuiltin okText "fdWrite")
        (writeAndLink work "sysWriteOk" okText)
        (let [(out (sh (str work "/sysWriteOk")))]
          (do (assert (= out.exitCode (stringLength text)) (str "write ok: exit " out.exitCode ", want " (stringLength text) " (bytes written)"))
              (assert (= out.stdout text) (str "write ok: stdout is the literal, got " out.stdout))
              (assert (ok? (fileWrite (str work "/writeFixture.asl")
                              (str "(module tests/writeFixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n  (mt (fdWrite 1 \"" text "\") ((ok _) (ok 0)) ((err e) (err e)))\n")))
                      "write ok: asl-host comparison fixture written")
              (let [(hostOut (sh (str (host) " run " work "/writeFixture.asl")))]
                (assert (= out.stdout hostOut.stdout) (str "write ok: native stdout equals the asl-host run's: native=" out.stdout " host=" hostOut.stdout)))))
        (expectErrno "write err" (runPlain work "sysWriteErr" errMod) facts "EBADF")))

fn ! testClose work: String facts: libc/TripleFacts -> Bool
  (let [(path (str work "/closeTarget"))
        (okMod (caseModule facts (list) (list (sys/sysCloseFn)) (list (sys/int32Const "fd" 3)) "sysClose" (list "fd")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list) (list (sys/sysCloseFn)) (list (sys/int32Const "fd" -1)) "sysClose" (list "fd")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @close(i32)")
        (assert (stringContains? text "sext i32") "close ok: close's real i32 return is widened (rawWidenI32) before the 0/-1 check")
        (assert (ok? (fileWrite path "close me")) "close ok: target file written")
        (let [(out (runWithFd3 work "sysCloseOk" okMod path))]
          (assert (= out.exitCode 0) (str "close ok: exit " out.exitCode ", want 0; stderr: " out.stderr)))
        (expectErrno "close err" (runPlain work "sysCloseErr" errMod) facts "EBADF")))

fn ! testPread work: String facts: libc/TripleFacts -> Bool
  (let [(content "pread content\n")
        (path (str work "/preadTarget"))
        (okMod (caseModule facts (list) (list (sys/sysPreadFn))
                 (list (sys/int32Const "fd" 3) (sys/int64Const "max" (stringLength content)) (sys/int64Const "offset" 0))
                 "sysPread" (list "fd" "max" "offset")
                 (list (ty/ssaInstr "bytes" (ty/tyVal) (ty/opVariantField "resv" 0))
                       (sys/entryInstr "n" (ty/tyI64) "bytesLength" (list "bytes")))
                 "n"))
        (errMod (errnoCaseModule facts (list) (list (sys/sysPreadFn))
                  (list (sys/int32Const "fd" -1) (sys/int64Const "max" 10) (sys/int64Const "offset" 0)) "sysPread" (list "fd" "max" "offset")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i64 @pread(i32, ptr, i64, i64)")
        (assert (ok? (fileWrite path content)) "pread ok: target file written")
        (let [(out (runWithFd3 work "sysPreadOk" okMod path))]
          (assert (= out.exitCode (stringLength content)) (str "pread ok: exit " out.exitCode ", want " (stringLength content) " (bytes read)")))
        (expectErrno "pread err" (runPlain work "sysPreadErr" errMod) facts "EBADF")))

fn ! testPwrite work: String facts: libc/TripleFacts -> Bool
  (let [(content "pwritten!\n")
        (path (str work "/pwriteTarget"))
        (okMod (caseModule facts (list content) (list (sys/sysPwriteFn))
                 (list (sys/int32Const "fd" 3) (ty/ssaInstr "data" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int64Const "offset" 0))
                 "sysPwrite" (list "fd" "data" "offset")
                 (list (ty/ssaInstr "cntBox" (ty/tyVal) (ty/opVariantField "resv" 0)) (ty/ssaInstr "cnt" (ty/tyI64) (ty/opUnbox "cntBox")))
                 "cnt"))
        (errMod (errnoCaseModule facts (list content) (list (sys/sysPwriteFn))
                  (list (sys/int32Const "fd" -1) (ty/ssaInstr "data" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int64Const "offset" 0)) "sysPwrite" (list "fd" "data" "offset")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i64 @pwrite(i32, ptr, i64, i64)")
        (assert (ok? (fileWrite path "..........")) "pwrite ok: target file pre-sized")
        (let [(out (runWithFd3 work "sysPwriteOk" okMod path))]
          (do (assert (= out.exitCode (stringLength content)) (str "pwrite ok: exit " out.exitCode ", want " (stringLength content) " (bytes written)"))
              (let [(catOut (sh (str "cat " path)))]
                (assert (stringStartsWith? catOut.stdout content) (str "pwrite ok: file now starts with the written data, got " catOut.stdout)))))
        (expectErrno "pwrite err" (runPlain work "sysPwriteErr" errMod) facts "EBADF")))

fn ! testKill work: String facts: libc/TripleFacts -> Bool
  (let [(okMod (caseModule facts (list) (list (sys/sysKillFn) (sys/sysGetpidFn))
                 (list (sys/callInstr "pid" (ty/tyI32) "sysGetpid" (list)) (sys/int32Const "sig" 0)) "sysKill" (list "pid" "sig")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list) (list (sys/sysKillFn) (sys/sysGetpidFn))
                  (list (sys/callInstr "pid" (ty/tyI32) "sysGetpid" (list)) (sys/int32Const "sig" -1)) "sysKill" (list "pid" "sig")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @kill(i32, i32)")
        (assert (= (runPlain work "sysKillOk" okMod).exitCode 0) "kill ok: kill(getpid(), 0) exits 0")
        (expectErrno "kill err" (runPlain work "sysKillErr" errMod) facts "EINVAL")))

fn ! testFsync work: String facts: libc/TripleFacts -> Bool
  (let [(path (str work "/fsyncTarget"))
        (okMod (caseModule facts (list) (list (sys/sysFsyncFn)) (list (sys/int32Const "fd" 3)) "sysFsync" (list "fd")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list) (list (sys/sysFsyncFn)) (list (sys/int32Const "fd" -1)) "sysFsync" (list "fd")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @fsync(i32)")
        (assert (ok? (fileWrite path "fsync me")) "fsync ok: target file written")
        (let [(out (runWithFd3 work "sysFsyncOk" okMod path))]
          (assert (= out.exitCode 0) (str "fsync ok: exit " out.exitCode ", want 0; stderr: " out.stderr)))
        (expectErrno "fsync err" (runPlain work "sysFsyncErr" errMod) facts "EBADF")))

fn ! testFlock work: String facts: libc/TripleFacts -> Bool
  (let [(lockEx (constOf facts "LOCK_EX"))
        (path (str work "/flockTarget"))
        (okMod (caseModule facts (list) (list (sys/sysFlockFn)) (list (sys/int32Const "fd" 3) (sys/int32Const "op" lockEx)) "sysFlock" (list "fd" "op")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list) (list (sys/sysFlockFn)) (list (sys/int32Const "fd" -1) (sys/int32Const "op" lockEx)) "sysFlock" (list "fd" "op")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @flock(i32, i32)")
        (assert (not (= lockEx -1)) "flock: LOCK_EX is in libc/libcConst for this triple")
        (assert (ok? (fileWrite path "flock me")) "flock ok: target file written")
        (let [(out (runWithFd3 work "sysFlockOk" okMod path))]
          (assert (= out.exitCode 0) (str "flock ok: exit " out.exitCode ", want 0; stderr: " out.stderr)))
        (expectErrno "flock err" (runPlain work "sysFlockErr" errMod) facts "EBADF")))

fn ! testRename work: String facts: libc/TripleFacts -> Bool
  (let [(src (str work "/renameSrc"))
        (dst (str work "/renameDst"))
        (missing (str work "/renameMissing"))
        (okMod (caseModule facts (list src dst) (list (sys/sysRenameFn))
                 (list (ty/ssaInstr "old" (ty/tyVal) (ty/opConst (ty/constStr 0))) (ty/ssaInstr "new" (ty/tyVal) (ty/opConst (ty/constStr 1))))
                 "sysRename" (list "old" "new") (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list missing dst) (list (sys/sysRenameFn))
                  (list (ty/ssaInstr "old" (ty/tyVal) (ty/opConst (ty/constStr 0))) (ty/ssaInstr "new" (ty/tyVal) (ty/opConst (ty/constStr 1))))
                  "sysRename" (list "old" "new")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @rename(ptr, ptr)")
        (assert (ok? (fileWrite src "rename me")) "rename ok: source file written")
        (let [(out (runPlain work "sysRenameOk" okMod))]
          (do (assert (= out.exitCode 0) (str "rename ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= (sh (str "test -f " dst " && ! test -f " src)).exitCode 0) "rename ok: dst exists and src is gone")))
        (expectErrno "rename err" (runPlain work "sysRenameErr" errMod) facts "ENOENT")))

fn ! testChmod work: String facts: libc/TripleFacts -> Bool
  (let [(path (str work "/chmodTarget"))
        (missing (str work "/chmodMissing"))
        (okMod (caseModule facts (list path) (list (sys/sysChmodFn))
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int32Const "mode" 420))
                 "sysChmod" (list "p" "mode") (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list missing) (list (sys/sysChmodFn))
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int32Const "mode" 420)) "sysChmod" (list "p" "mode")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @chmod(ptr, i32)")
        (assert (ok? (fileWrite path "chmod me")) "chmod ok: target file written")
        (let [(out (runPlain work "sysChmodOk" okMod))]
          (assert (= out.exitCode 0) (str "chmod ok: exit " out.exitCode ", want 0; stderr: " out.stderr)))
        (expectErrno "chmod err" (runPlain work "sysChmodErr" errMod) facts "ENOENT")))

fn ! testMkdir work: String facts: libc/TripleFacts -> Bool
  (let [(dir (str work "/mkdirTarget"))
        (okMod (caseModule facts (list dir) (list (sys/sysMkdirFn))
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int32Const "mode" 493))
                 "sysMkdir" (list "p" "mode") (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list dir) (list (sys/sysMkdirFn))
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int32Const "mode" 493)) "sysMkdir" (list "p" "mode")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @mkdir(ptr, i32)")
        (let [(out (runPlain work "sysMkdirOk" okMod))]
          (do (assert (= out.exitCode 0) (str "mkdir ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= (sh (str "test -d " dir)).exitCode 0) "mkdir ok: directory now exists")))
        (expectErrno "mkdir err" (runPlain work "sysMkdirErr" errMod) facts "EEXIST")))

fn ! testUnlink work: String facts: libc/TripleFacts -> Bool
  (let [(path (str work "/unlinkTarget"))
        (okMod (caseModule facts (list path) (list (sys/sysUnlinkFn))
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysUnlink" (list "p")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list path) (list (sys/sysUnlinkFn))
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysUnlink" (list "p")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @unlink(ptr)")
        (assert (ok? (fileWrite path "unlink me")) "unlink ok: target file written")
        (let [(out (runPlain work "sysUnlinkOk" okMod))]
          (do (assert (= out.exitCode 0) (str "unlink ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= (sh (str "! test -f " path)).exitCode 0) "unlink ok: file is gone")))
        (expectErrno "unlink err" (runPlain work "sysUnlinkErr" errMod) facts "ENOENT")))

fn ! testRmdir work: String facts: libc/TripleFacts -> Bool
  (let [(dir (str work "/rmdirTarget"))
        (okMod (caseModule facts (list dir) (list (sys/sysRmdirFn))
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysRmdir" (list "p")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list dir) (list (sys/sysRmdirFn))
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysRmdir" (list "p")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @rmdir(ptr)")
        (assert (= (sh (str "mkdir -p " dir)).exitCode 0) "rmdir ok: target directory made")
        (let [(out (runPlain work "sysRmdirOk" okMod))]
          (do (assert (= out.exitCode 0) (str "rmdir ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= (sh (str "! test -d " dir)).exitCode 0) "rmdir ok: directory is gone")))
        (expectErrno "rmdir err" (runPlain work "sysRmdirErr" errMod) facts "ENOENT")))

fn ! testSymlink work: String facts: libc/TripleFacts -> Bool
  (let [(target (str work "/symlinkTarget"))
        (link (str work "/symlinkLink"))
        (okMod (caseModule facts (list target link) (list (sys/sysSymlinkFn))
                 (list (ty/ssaInstr "t" (ty/tyVal) (ty/opConst (ty/constStr 0))) (ty/ssaInstr "l" (ty/tyVal) (ty/opConst (ty/constStr 1))))
                 "sysSymlink" (list "t" "l") (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list target target) (list (sys/sysSymlinkFn))
                  (list (ty/ssaInstr "t" (ty/tyVal) (ty/opConst (ty/constStr 0))) (ty/ssaInstr "l" (ty/tyVal) (ty/opConst (ty/constStr 1))))
                  "sysSymlink" (list "t" "l")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @symlink(ptr, ptr)")
        (assert (ok? (fileWrite target "symlink target")) "symlink ok: target file written")
        (let [(out (runPlain work "sysSymlinkOk" okMod))]
          (do (assert (= out.exitCode 0) (str "symlink ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= (sh (str "test -L " link)).exitCode 0) "symlink ok: link now exists")))
        (expectErrno "symlink err" (runPlain work "sysSymlinkErr" errMod) facts "EEXIST")))

fn ! testReadlink work: String facts: libc/TripleFacts -> Bool
  (let [(target (str work "/readlinkTarget"))
        (link (str work "/readlinkLink"))
        (missing (str work "/readlinkMissing"))
        (okMod (caseModule facts (list link) (list (sys/sysReadlinkFn))
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int64Const "max" 256))
                 "sysReadlink" (list "p" "max")
                 (list (ty/ssaInstr "bytes" (ty/tyVal) (ty/opVariantField "resv" 0))
                       (sys/entryInstr "n" (ty/tyI64) "bytesLength" (list "bytes")))
                 "n"))
        (errMod (errnoCaseModule facts (list missing) (list (sys/sysReadlinkFn))
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int64Const "max" 256)) "sysReadlink" (list "p" "max")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i64 @readlink(ptr, ptr, i64)")
        (assert (ok? (fileWrite target "readlink target")) "readlink ok: target file written")
        (assert (= (sh (str "ln -sf " target " " link)).exitCode 0) "readlink ok: symlink made")
        (let [(out (runPlain work "sysReadlinkOk" okMod))]
          (assert (= out.exitCode (stringLength target)) (str "readlink ok: exit " out.exitCode ", want " (stringLength target) " (resolved length)")))
        (expectErrno "readlink err" (runPlain work "sysReadlinkErr" errMod) facts "ENOENT")))

fn realpathWriteModule facts: libc/TripleFacts strings: (List String) -> ty/SsaModule
  (moduleOf facts strings (list (sys/sysErrnoValueFn facts) (sys/sysRealpathFn) (sys/sysWriteFn)
    (ty/ssaFunction "run" (list) (list) (ty/tyI64)
      (list (sys/block "entry"
              (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                    (sys/callInstr "resv" (ty/tyVal) "sysRealpath" (list "p")))
              (okErrSwitch "resv" "writeCase" "errCase"))
            (sys/block "writeCase"
              (list (ty/ssaInstr "sBox" (ty/tyVal) (ty/opVariantField "resv" 0))
                    (sys/int32Const "fd" 1)
                    (sys/callInstr "wres" (ty/tyVal) "sysWrite" (list "fd" "sBox")))
              (okErrSwitch "wres" "doneCase" "errCase"))
            (sys/block "doneCase"
              (list (ty/ssaInstr "cntBox" (ty/tyVal) (ty/opVariantField "wres" 0))
                    (ty/ssaInstr "cnt" (ty/tyI64) (ty/opUnbox "cntBox")))
              (ty/termReturn "cnt"))
            (sys/block "errCase" (list (sys/int64Const "sentinel" -1)) (ty/termReturn "sentinel"))))))

fn ! testRealpath work: String facts: libc/TripleFacts -> Bool
  (let [(target (str work "/realpathTarget"))
        (link (str work "/realpathLink"))
        (missing (str work "/realpathMissing"))
        (okMod (realpathWriteModule facts (list link)))
        (relMod (realpathWriteModule facts (list "realpathLink")))
        (errMod (errnoCaseModule facts (list missing) (list (sys/sysRealpathFn))
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysRealpath" (list "p")))
        (okText (textOf (llvm/emitLlvmProgram okMod "run")))
        (root (repoRootAbs))]
    (do (declaresReal okText "declare ptr @realpath(ptr, ptr)")
        (assert (ok? (fileWrite target "realpath target")) "realpath ok: target file written")
        (assert (= (sh (str "ln -sf " target " " link)).exitCode 0) "realpath ok: symlink made")
        (let [(out (runPlain work "sysRealpathOk" okMod))
              (hostFixture (str work "/realpathHostFixture.asl"))]
          (do (assert (> out.exitCode 0) (str "realpath ok (symlink): exit " out.exitCode ", want a positive byte count"))
              (assert (ok? (fileWrite hostFixture
                          (str "(module tests/realpathHostFixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n  (mt (realPath \"" link "\") ((ok s) (do (print s) (ok 0))) ((err e) (err e)))\n")))
                    "realpath ok (symlink): asl-host comparison fixture written")
              (let [(hostOut (sh (str root "/" (host) " run " hostFixture)))]
                (assert (= out.stdout hostOut.stdout) (str "realpath ok (symlink): native stdout " out.stdout " vs asl-host run's realPath+print stdout " hostOut.stdout)))))
        (let [(relOut (runCase work "sysRealpathRel" relMod (str "cd '" work "' && exec " work "/sysRealpathRel")))
              (relHostFixture (str work "/realpathRelHostFixture.asl"))]
          (do (assert (> relOut.exitCode 0) (str "realpath rel: exit " relOut.exitCode ", want a positive byte count"))
              (assert (ok? (fileWrite relHostFixture
                          "(module tests/realpathRelHostFixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n  (mt (realPath \"realpathLink\") ((ok s) (do (print s) (ok 0))) ((err e) (err e)))\n"))
                    "realpath rel: asl-host comparison fixture written")
              (let [(relHostOut (sh (str "cd '" work "' && " root "/" (host) " run " relHostFixture)))]
                (assert (= relOut.stdout relHostOut.stdout) (str "realpath rel: native stdout " relOut.stdout " vs asl-host run's realPath+print stdout " relHostOut.stdout)))))
        (expectErrno "realpath err" (runPlain work "sysRealpathErr" errMod) facts "ENOENT")))

fn ! exePathWriteModule facts: libc/TripleFacts -> ty/SsaModule
  (moduleOf facts (list) (list (sys/sysErrnoValueFn facts) (unwrapFn "exe path" (sys/sysExePathFn facts)) (sys/sysWriteFn)
    (ty/ssaFunction "run" (list) (list) (ty/tyI64)
      (list (sys/block "entry"
              (list (sys/callInstr "resv" (ty/tyVal) "sysExePath" (list)))
              (okErrSwitch "resv" "writeCase" "errCase"))
            (sys/block "writeCase"
              (list (ty/ssaInstr "sBox" (ty/tyVal) (ty/opVariantField "resv" 0))
                    (sys/int32Const "fd" 1)
                    (sys/callInstr "wres" (ty/tyVal) "sysWrite" (list "fd" "sBox")))
              (okErrSwitch "wres" "doneCase" "errCase"))
            (sys/block "doneCase"
              (list (ty/ssaInstr "cntBox" (ty/tyVal) (ty/opVariantField "wres" 0))
                    (ty/ssaInstr "cnt" (ty/tyI64) (ty/opUnbox "cntBox")))
              (ty/termReturn "cnt"))
            (sys/block "errCase" (list (sys/int64Const "sentinel" -1)) (ty/termReturn "sentinel"))))))

fn ! testExePath work: String facts: libc/TripleFacts -> Bool
  (let [(mod (exePathWriteModule facts))
        (text (textOf (llvm/emitLlvmProgram mod "run")))
        (bin (str work "/sysExePathOk"))
        (link (str work "/exePathLink"))
        (root (repoRootAbs))
        (darwin? (= (libc/exePathSource facts.triple) "nsGetExecutablePath"))]
    (do (declaresReal text "declare ptr @realpath(ptr, ptr)")
        (if darwin?
          (declaresReal text "declare i32 @_NSGetExecutablePath(ptr, ptr)")
          (neverBuiltin text "_NSGetExecutablePath"))
        (let [(out (runCase work "sysExePathOk" mod (str "ln -sf " bin " " link " && cd / && exec " link)))
              (fixture (str work "/exePathHostFixture.asl"))]
          (do (assert (> out.exitCode 0) (str "exe path: exit " out.exitCode ", want a positive byte count; stderr: " out.stderr))
              (assert (ok? (fileWrite fixture
                          (str "(module tests/exePathHostFixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n"
                               "  (mt (realPath \"" bin "\") ((ok s) (do (println s) (mt (procExePath) ((ok e) (mt (realPath \"" root "/" (host) "\") ((ok h) (do (print (if (= e h) \"same\" (str \"differs \" e \" \" h))) (ok 0))) ((err x) (err x)))) ((err x) (err x))))) ((err e) (err e)))\n")))
                    "exe path: asl-host comparison fixture written")
              (let [(hostLink (str work "/hostExeLink"))
                    (hostOut (sh (str "ln -sf " root "/" (host) " " hostLink " && cd / && exec " hostLink " run " fixture)))
                    (lines (stringSplit hostOut.stdout "\n"))]
                (do (assert (= hostOut.exitCode 0) (str "exe path: asl-host fixture exit " hostOut.exitCode "; stderr: " hostOut.stderr))
                    (assert (= out.stdout (optionOr (listGet lines 0) "")) (str "exe path: native stdout " out.stdout " vs asl-host realPath of the binary " hostOut.stdout))
                    (assert (= (optionOr (listGet lines 1) "") "same") (str "exe path: asl-host procExePath vs its own realPath: " hostOut.stdout))
                    true))))))

fn ! testSysconf work: String facts: libc/TripleFacts -> Bool
  (let [(name (constOf facts "_SC_NPROCESSORS_ONLN"))
        (okMod (caseModule facts (list) (list (sys/sysSysconfFn)) (list (sys/int32Const "name" name)) "sysSysconf" (list "name")
                 (list (ty/ssaInstr "cntBox" (ty/tyVal) (ty/opVariantField "resv" 0)) (ty/ssaInstr "cnt" (ty/tyI64) (ty/opUnbox "cntBox")))
                 "cnt"))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i64 @sysconf(i32)")
        (assert (not (= name -1)) "sysconf: _SC_NPROCESSORS_ONLN is in libc/libcConst for this triple")
        (let [(out (runPlain work "sysSysconfOk" okMod))]
          (do (assert (> out.exitCode 0) (str "sysconf ok: exit " out.exitCode ", want a positive processor count")) true))))

fn ! testClockGettime work: String facts: libc/TripleFacts -> Bool
  (let [(okMod (caseModule facts (list) (list (unwrapFn "clock_gettime" (sys/sysClockGettimeFn facts))) (list (sys/int32Const "clockId" 0)) "sysClockGettime" (list "clockId")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list) (list (unwrapFn "clock_gettime" (sys/sysClockGettimeFn facts))) (list (sys/int32Const "clockId" 999)) "sysClockGettime" (list "clockId")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @clock_gettime(i32, ptr)")
        (let [(out (runPlain work "sysClockGettimeOk" okMod))]
          (assert (= out.exitCode 0) (str "clock_gettime ok: exit " out.exitCode ", want 0 (clock id 0 is CLOCK_REALTIME on both darwin and linux); stderr: " out.stderr)))
        (expectErrno "clock_gettime err" (runPlain work "sysClockGettimeErr" errMod) facts "EINVAL")))

fn ! testUsleep work: String facts: libc/TripleFacts -> Bool
  (let [(okMod (caseModule facts (list) (list (sys/sysUsleepFn)) (list (sys/int32Const "micros" 1000)) "sysUsleep" (list "micros")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @usleep(i32)")
        (let [(out (runPlain work "sysUsleepOk" okMod))]
          (do (assert (= out.exitCode 0) (str "usleep ok: exit " out.exitCode ", want 0; stderr: " out.stderr)) true))))

fn ! testGetenv work: String facts: libc/TripleFacts -> Bool
  (let [(hitMod (getenvModule facts (list "PATH")
                  (list (ty/ssaInstr "envBox" (ty/tyVal) (ty/opVariantField "resv" 0))
                        (sys/entryInstr "envLen" (ty/tyI64) "bytesLength" (list "envBox")))
                  "envLen" -1))
        (missMod (getenvModule facts (list "ASEX_S3B_DEFINITELY_UNSET_XYZ")
                   (list (sys/int64Const "dummy" -1)) "dummy" 7))
        (text (textOf (llvm/emitLlvmProgram hitMod "run")))
        (hitOut (runPlain work "sysGetenvHit" hitMod))
        (missOut (runPlain work "sysGetenvMiss" missMod))]
    (do (declaresReal text "declare ptr @getenv(ptr)")
        (assert (> hitOut.exitCode 0) (str "getenv hit: exit " hitOut.exitCode ", want PATH's length > 0; stderr: " hitOut.stderr))
        (assert (= missOut.exitCode 7) (str "getenv miss: exit " missOut.exitCode ", want the none-branch sentinel 7; stderr: " missOut.stderr))
        true))

fn fcntlSetThenGetModule facts: libc/TripleFacts setCmd: Int64 getCmd: Int64 arg: Int64 nonblock: Int64 -> ty/SsaModule
  (moduleOf facts (list) (list (sys/sysErrnoValueFn facts) (sys/sysFcntlSetFn) (sys/sysFcntlGetFn)
    (ty/ssaFunction "run" (list) (list) (ty/tyI64)
      (list (sys/block "entry"
              (list (sys/int32Const "fd" 3) (sys/int32Const "setCmd" setCmd) (sys/int32Const "arg" arg)
                    (sys/callInstr "setRes" (ty/tyVal) "sysFcntlSet" (list "fd" "setCmd" "arg")))
              (okErrSwitch "setRes" "getCase" "errCase"))
            (sys/block "getCase"
              (list (sys/int32Const "getCmd" getCmd)
                    (sys/callInstr "getRes" (ty/tyVal) "sysFcntlGet" (list "fd" "getCmd")))
              (okErrSwitch "getRes" "maskCase" "errCase"))
            (sys/block "maskCase"
              (list (ty/ssaInstr "flagsBox" (ty/tyVal) (ty/opVariantField "getRes" 0))
                    (ty/ssaInstr "flags" (ty/tyI64) (ty/opUnbox "flagsBox"))
                    (sys/int64Const "nonblockC" nonblock)
                    (sys/primInstr "masked" (ty/tyI64) "rawAndI64" (list "flags" "nonblockC"))
                    (sys/int64Const "zero2" 0)
                    (sys/primInstr "isZero" (ty/tyI1) "eqInt" (list "masked" "zero2")))
              (ty/termBranch "isZero" (edge "notSet") (edge "isSet")))
            (sys/block "isSet" (list (sys/int64Const "one" 1)) (ty/termReturn "one"))
            (sys/block "notSet" (list (sys/int64Const "zeroR" 0)) (ty/termReturn "zeroR"))
            (sys/block "errCase" (list (sys/int64Const "sentinel" 2)) (ty/termReturn "sentinel"))))))

fn ! testFcntl work: String facts: libc/TripleFacts -> Bool
  (let [(path (str work "/fcntlTarget"))
        (getfl (constOf facts "F_GETFL")) (setfl (constOf facts "F_SETFL"))
        (rdwr (constOf facts "O_RDWR")) (nonblock (constOf facts "O_NONBLOCK"))
        (getOkMod (caseModule facts (list) (list (sys/sysFcntlGetFn))
                    (list (sys/int32Const "fd" 3) (sys/int32Const "cmd" getfl)) "sysFcntlGet" (list "fd" "cmd")
                    (list (ty/ssaInstr "flagsBox" (ty/tyVal) (ty/opVariantField "resv" 0)) (ty/ssaInstr "flags" (ty/tyI64) (ty/opUnbox "flagsBox")))
                    "flags"))
        (getErrMod (errnoCaseModule facts (list) (list (sys/sysFcntlGetFn))
                     (list (sys/int32Const "fd" -1) (sys/int32Const "cmd" getfl)) "sysFcntlGet" (list "fd" "cmd")))
        (setThenGetMod (fcntlSetThenGetModule facts setfl getfl nonblock nonblock))
        (setErrMod (errnoCaseModule facts (list) (list (sys/sysFcntlSetFn))
                     (list (sys/int32Const "fd" -1) (sys/int32Const "cmd" setfl) (sys/int32Const "arg" nonblock)) "sysFcntlSet" (list "fd" "cmd" "arg")))
        (text (textOf (llvm/emitLlvmProgram getOkMod "run")))]
    (do (declaresReal text "declare i32 @fcntl(i32, i32, ...)")
        (assert (not (= getfl -1)) "fcntl: F_GETFL is in libc/libcConst for this triple")
        (assert (not (= setfl -1)) "fcntl: F_SETFL is in libc/libcConst for this triple")
        (assert (not (= rdwr -1)) "fcntl: O_RDWR is in libc/libcConst for this triple")
        (assert (not (= nonblock -1)) "fcntl: O_NONBLOCK is in libc/libcConst for this triple")
        (assert (ok? (fileWrite path "fcntl me")) "fcntl: target file written")
        (let [(out (runWithFd3 work "sysFcntlGetOk" getOkMod path))]
          (assert (= out.exitCode rdwr) (str "fcntl get ok: exit " out.exitCode ", want O_RDWR=" rdwr "; stderr: " out.stderr)))
        (expectErrno "fcntl get err" (runPlain work "sysFcntlGetErr" getErrMod) facts "EBADF")
        (let [(out (runWithFd3 work "sysFcntlSetThenGet" setThenGetMod path))]
          (assert (= out.exitCode 1) (str "fcntl set then get: exit " out.exitCode ", want 1 (O_NONBLOCK read back set after F_SETFL); stderr: " out.stderr)))
        (expectErrno "fcntl set err" (runPlain work "sysFcntlSetErr" setErrMod) facts "EBADF")))

fn ! testPoll work: String facts: libc/TripleFacts -> Bool
  (let [(pollin (constOf facts "POLLIN")) (pollnval (constOf facts "POLLNVAL"))
        (fifo (str work "/pollFifo"))
        (readyInstrs (list (ty/ssaInstr "payload" (ty/tyVal) (ty/opVariantField "resv" 0))
                       (sys/int64Const "zeroRaw" 0) (sys/boxInstr "defaultBox" "zeroRaw")
                       (sys/entryInstr "readyBox" (ty/tyVal) "@listHeadOr" (list "payload" "defaultBox"))
                       (ty/ssaInstr "ready" (ty/tyI64) (ty/opUnbox "readyBox"))))
        (reventsInstrs (list (ty/ssaInstr "payload" (ty/tyVal) (ty/opVariantField "resv" 0))
                         (sys/int64Const "zeroRaw" 0) (sys/boxInstr "defaultBox" "zeroRaw")
                         (sys/entryInstr "tailBox" (ty/tyVal) "@listTailOr" (list "payload" "defaultBox"))
                         (sys/entryInstr "revBox" (ty/tyVal) "@listHeadOr" (list "tailBox" "defaultBox"))
                         (ty/ssaInstr "revents" (ty/tyI64) (ty/opUnbox "revBox"))))
        (readyMod (caseModule facts (list) (list (unwrapFn "poll" (sys/sysPollFn facts)))
                    (list (sys/int32Const "fd" 3) (sys/int32Const "events" pollin) (sys/int32Const "timeoutMs" 0)) "sysPoll" (list "fd" "events" "timeoutMs")
                    readyInstrs "ready"))
        (reventsMod (caseModule facts (list) (list (unwrapFn "poll" (sys/sysPollFn facts)))
                      (list (sys/int32Const "fd" 3) (sys/int32Const "events" pollin) (sys/int32Const "timeoutMs" 0)) "sysPoll" (list "fd" "events" "timeoutMs")
                      reventsInstrs "revents"))
        (badFdMod (caseModule facts (list) (list (unwrapFn "poll" (sys/sysPollFn facts)))
                    (list (sys/int32Const "fd" 99) (sys/int32Const "events" pollin) (sys/int32Const "timeoutMs" 0)) "sysPoll" (list "fd" "events" "timeoutMs")
                    reventsInstrs "revents"))
        (text (textOf (llvm/emitLlvmProgram readyMod "run")))]
    (do (declaresReal text "declare i32 @poll(ptr, i64, i32)")
        (assert (not (= pollin -1)) "poll: POLLIN is in libc/libcConst for this triple")
        (assert (not (= pollnval -1)) "poll: POLLNVAL is in libc/libcConst for this triple")
        (assert (= (sh (str "mkfifo " fifo)).exitCode 0) "poll: fifo made")
        (let [(out (runWithFd3 work "sysPollBeforeWrite" readyMod fifo))]
          (assert (= out.exitCode 0) (str "poll before write: exit " out.exitCode ", want 0 ready descriptors; stderr: " out.stderr)))
        (let [(out (runCase work "sysPollAfterWriteReady" readyMod (str "exec 3<>'" fifo "' && printf 'x' >&3 && exec " work "/sysPollAfterWriteReady")))]
          (assert (= out.exitCode 1) (str "poll after write: exit " out.exitCode ", want 1 ready descriptor; stderr: " out.stderr)))
        (let [(out (runCase work "sysPollAfterWriteRevents" reventsMod (str "exec 3<>'" fifo "' && printf 'x' >&3 && exec " work "/sysPollAfterWriteRevents")))]
          (assert (= out.exitCode pollin) (str "poll after write: revents " out.exitCode ", want POLLIN=" pollin "; stderr: " out.stderr)))
        (let [(out (runPlain work "sysPollBadFd" badFdMod))]
          (assert (= out.exitCode pollnval) (str "poll bad fd: revents " out.exitCode ", want POLLNVAL=" pollnval "; stderr: " out.stderr)))
        true))

fn ! testNanosleep work: String facts: libc/TripleFacts -> Bool
  (let [(okMod (caseModule facts (list) (list (unwrapFn "nanosleep" (sys/sysNanosleepFn facts)))
                 (list (sys/int64Const "sec" 0) (sys/int64Const "nanos" 1000000)) "sysNanosleep" (list "sec" "nanos")
                 (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list) (list (unwrapFn "nanosleep" (sys/sysNanosleepFn facts)))
                  (list (sys/int64Const "sec" -1) (sys/int64Const "nanos" 0)) "sysNanosleep" (list "sec" "nanos")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @nanosleep(ptr, ptr)")
        (let [(out (runPlain work "sysNanosleepOk" okMod))]
          (assert (= out.exitCode 0) (str "nanosleep ok: exit " out.exitCode ", want 0; stderr: " out.stderr)))
        (expectErrno "nanosleep err" (runPlain work "sysNanosleepErr" errMod) facts "EINVAL")))

fn ! testGetpid work: String facts: libc/TripleFacts -> Bool
  (let [(mod (moduleOf facts (list)
               (list (sys/sysGetpidFn)
                     (ty/ssaFunction "run" (list) (list) (ty/tyI64)
                       (list (sys/block "entry" (list (sys/callInstr "pid" (ty/tyI32) "sysGetpid" (list)) (sys/int64Const "zero" 0)) (ty/termReturn "zero")))))))
        (text (textOf (llvm/emitLlvmProgram mod "run")))]
    (do (declaresReal text "declare i32 @getpid()")
        (let [(out (runPlain work "sysGetpidOk" mod))]
          (do (assert (= out.exitCode 0) (str "getpid ok: exit " out.exitCode " (sanity: getpid links and runs; no raw i32 primitive here to inspect its value further); stderr: " out.stderr)) true))))

fn listFieldInstrs listVar: String n: Int64 prefix: String -> (Pair (List ty/SsaInstr) (List String))
  (fold
    (fn [(acc (Pair (List ty/SsaInstr) (List String))) (i Int64)] -> (Pair (List ty/SsaInstr) (List String))
      (let [(doneSoFar (pairFirst acc)) (namesSoFar (pairSecond acc))
            (tailName (if (= i 0) listVar (str prefix ".tail" i)))
            (headBoxName (str prefix ".headBox" i)) (headName (str prefix ".h" i))
            (defName (str prefix ".def" i)) (defRawName (str prefix ".defRaw" i))
            (headPre (list (sys/int64Const defRawName 0) (sys/boxInstr defName defRawName)
                            (sys/entryInstr headBoxName (ty/tyVal) "@listHeadOr" (list tailName defName))
                            (ty/ssaInstr headName (ty/tyI64) (ty/opUnbox headBoxName))))
            (tailPre (if (< i (- n 1))
                       (list (sys/entryInstr (str prefix ".tail" (+ i 1)) (ty/tyVal) "@listTailOr" (list tailName defName)))
                       (list)))]
        (pair (listAppend doneSoFar (listAppend headPre tailPre)) (listAppend namesSoFar (list headName)))))
    (pair (list) (list)) (range 0 n))

fn joinIntsInstrsGo names: (List String) spaceName: String prefix: String i: Int64 acc: (List ty/SsaInstr) accName: String -> (Pair (List ty/SsaInstr) String)
  (mt (listHead names)
    ((none) (pair acc accName))
    ((some h)
     (let [(strName (str prefix ".str" i)) (convInstr (sys/entryInstr strName (ty/tyVal) "stringFromInt64" (list h)))]
       (if (= i 0)
         (joinIntsInstrsGo (optionOr (listTail names) (list)) spaceName prefix (+ i 1) (listAppend acc (list convInstr)) strName)
         (let [(cat1Name (str prefix ".cat1_" i)) (cat2Name (str prefix ".cat2_" i))
               (cat1Instr (sys/entryInstr cat1Name (ty/tyVal) "stringConcat" (list accName spaceName)))
               (cat2Instr (sys/entryInstr cat2Name (ty/tyVal) "stringConcat" (list cat1Name strName)))]
           (joinIntsInstrsGo (optionOr (listTail names) (list)) spaceName prefix (+ i 1) (listAppend acc (list convInstr cat1Instr cat2Instr)) cat2Name))))))

fn joinIntsInstrs names: (List String) spaceName: String prefix: String -> (Pair (List ty/SsaInstr) String)
  (joinIntsInstrsGo names spaceName prefix 0 (list) "")

fn ! testStatFamily work: String facts: libc/TripleFacts label: String sysFnName: String externName: String sysFn: (Fn libc/TripleFacts -> (Result ty/SsaFunction String)) path: String wantKind: String followLink: Bool -> Bool
  (let [(fn0 (unwrapFn sysFnName (sysFn facts)))
        (fields (listFieldInstrs "payload" 4 "f"))
        (joined (joinIntsInstrs (pairSecond fields) "sp" "j"))
        (okInstrs
          (listAppend (list (ty/ssaInstr "payload" (ty/tyVal) (ty/opVariantField "resv" 0)))
            (listAppend (pairFirst fields)
              (listAppend (list (ty/ssaInstr "sp" (ty/tyVal) (ty/opConst (ty/constStr 1))) (ty/ssaInstr "nl" (ty/tyVal) (ty/opConst (ty/constStr 2))))
                (listAppend (pairFirst joined)
                  (list (ty/ssaInstr "line" (ty/tyVal) (ty/opEntry "stringConcat" (list (pairSecond joined) "nl")))
                        (sys/callInstr "wr" (ty/tyVal) "sysWrite" (list "one" "line"))
                        (sys/int64Const "zeroExit" 0)))))))
        (okMod (caseModule facts (list path " " "\n") (list fn0 (sys/sysWriteFn))
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int32Const "one" 1))
                 sysFnName (list "p") okInstrs "zeroExit"))
        (missingMod (errnoCaseModule facts (list (str path ".missing")) (list fn0)
                      (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) sysFnName (list "p")))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))
        (oracleFn (if followLink "fileStat" "fileLstat"))]
    (do (declaresReal text (str "declare i32 @" externName))
        (let [(out (runPlain work (str label "Ok") okMod))
              (outFields (stringSplit (stringTrim out.stdout) " "))
              (nativeSize (optionOr (listGet outFields 0) "")) (nativeMode (optionOr (listGet outFields 1) ""))
              (nativeMtime (optionOr (listGet outFields 2) "")) (nativeKind (optionOr (listGet outFields 3) ""))
              (fixturePath (str work "/" label "Fixture.asl"))
              (fixtureSrc (str "(module tests/" label "Fixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n  (mt (" oracleFn " \"" path "\")\n    ((ok st) (mt (fdWrite 1 (str (stringFromInt64 st.size) \" \" (stringFromInt64 st.mode) \" \" (stringFromInt64 st.mtime)))\n                ((ok _) (ok 0)) ((err e) (err e))))\n    ((err e) (err e)))\n"))]
          (do (assert (= out.exitCode 0) (str label " ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (ok? (fileWrite fixturePath fixtureSrc)) (str label " ok: asl-host " oracleFn " fixture written"))
              (let [(oracleOut (sh (str (host) " run " fixturePath)))
                    (hostFields (stringSplit (stringTrim oracleOut.stdout) " "))
                    (hostSize (optionOr (listGet hostFields 0) "")) (hostMode (optionOr (listGet hostFields 1) ""))
                    (hostMtime (optionOr (listGet hostFields 2) ""))]
                (do (assert (= nativeSize hostSize) (str label " ok: size " nativeSize ", oracle says " hostSize))
                    (assert (= nativeMode hostMode) (str label " ok: mode " nativeMode ", oracle says " hostMode))
                    (assert (= nativeMtime hostMtime) (str label " ok: mtime " nativeMtime ", oracle says " hostMtime))
                    (assert (= nativeKind (stringFromInt64 (constOf facts wantKind))) (str label " ok: kind " nativeKind ", want " wantKind "=" (stringFromInt64 (constOf facts wantKind))))))
              (expectErrno (str label " err") (runPlain work (str label "Err") missingMod) facts "ENOENT")))))

fn ! testStat work: String facts: libc/TripleFacts -> Bool
  (let [(target (str work "/statTarget"))]
    (do (assert (ok? (fileWrite target "stat me\n")) "stat: target file written")
        (testStatFamily work facts "sysStat" "sysStat" "stat" sys/sysStatFn target "S_IFREG" true)))

fn ! testLstat work: String facts: libc/TripleFacts -> Bool
  (let [(target (str work "/lstatTarget")) (link (str work "/lstatLink"))]
    (do (assert (ok? (fileWrite target "lstat target\n")) "lstat: target file written")
        (assert (= (sh (str "ln -sf " target " " link)).exitCode 0) "lstat: symlink made")
        (testStatFamily work facts "sysLstat" "sysLstat" "lstat" sys/sysLstatFn link "S_IFLNK" false)))

fn ! mustSizeIn structs: (Option libc/StructFacts) label: String -> Int64
  (mt structs ((some sf) sf.size) ((none) (do (assert false (str label ": no stat row in libc.asl for this triple")) -1)))

fn ! mustOffsetIn structs: (Option libc/StructFacts) field: String label: String -> Int64
  (mt structs
    ((none) (do (assert false (str label ": no stat row in libc.asl for this triple")) -1))
    ((some sf) (mt (libc/structFieldOffset sf field)
                 ((some off) off)
                 ((none) (do (assert false (str label ": no " field " field in libc.asl's stat row for this triple")) -1)))))

fn ! readAtimeMtimeModule facts: libc/TripleFacts path: String -> ty/SsaModule
  (let [(structs (libc/pairFind facts.structs "stat"))
        (statSize (mustSizeIn structs "readAtimeMtimeModule"))
        (atimeOff (mustOffsetIn structs "st_atimespec" "readAtimeMtimeModule"))
        (mtimeOff (mustOffsetIn structs "st_mtimespec" "readAtimeMtimeModule"))
        (timespecStructs (libc/pairFind facts.structs "timespec"))
        (nsecOff (mustOffsetIn timespecStructs "tv_nsec" "readAtimeMtimeModule"))
        (atimeNsecOff (+ atimeOff nsecOff))
        (mtimeNsecOff (+ mtimeOff nsecOff))]
    (moduleOf facts (list path " " "\n") (list (sys/sysErrnoValueFn facts) (sys/sysWriteFn)
      (ty/ssaFunction "run" (list) (list) (ty/tyI64)
        (list
          (sys/block "entry"
            (list (ty/ssaInstr "pathV" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                  (sys/int32Const "repr" 0)
                  (sys/callInstr "p" (ty/tyPtr) "valToCStr" (list "pathV" "repr"))
                  (sys/int64Const "stSize" statSize)
                  (sys/callInstr "st" (ty/tyPtr) "malloc" (list "stSize"))
                  (sys/primInstr "stNull" (ty/tyI1) "rawPtrIsNull" (list "st")))
            (ty/termBranch "stNull" (edge "errAlloc") (edge "call")))
          (sys/block "call"
            (list (sys/callInstr "rc" (ty/tyI32) "stat" (list "p" "st"))
                  (sys/primInstr "rc64" (ty/tyI64) "rawWidenI32" (list "rc"))
                  (sys/int64Const "zero" 0)
                  (sys/primInstr "isErr" (ty/tyI1) "neInt" (list "rc64" "zero")))
            (ty/termBranch "isErr" (edge "errCall") (edge "ok")))
          (sys/block "errAlloc"
            (list (sys/callInstr "fp0" (ty/tyI64) "free" (list "p")) (sys/callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list)))
            (ty/termReturn "errno0"))
          (sys/block "errCall"
            (list (sys/callInstr "fp1" (ty/tyI64) "free" (list "p")) (sys/callInstr "fst1" (ty/tyI64) "free" (list "st"))
                  (sys/callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
            (ty/termReturn "errno1"))
          (sys/block "ok"
            (list
              (sys/int64Const "atimeOffC" atimeOff) (sys/primInstr "atimeSec" (ty/tyI64) "rawLoadI64" (list "st" "atimeOffC"))
              (sys/int64Const "mtimeOffC" mtimeOff) (sys/primInstr "mtimeSec" (ty/tyI64) "rawLoadI64" (list "st" "mtimeOffC"))
              (sys/int64Const "atimeNsecOffC" atimeNsecOff) (sys/primInstr "atimeNsec" (ty/tyI64) "rawLoadI64" (list "st" "atimeNsecOffC"))
              (sys/int64Const "mtimeNsecOffC" mtimeNsecOff) (sys/primInstr "mtimeNsec" (ty/tyI64) "rawLoadI64" (list "st" "mtimeNsecOffC"))
              (sys/callInstr "fp2" (ty/tyI64) "free" (list "p")) (sys/callInstr "fst2" (ty/tyI64) "free" (list "st"))
              (sys/int32Const "one" 1)
              (sys/entryInstr "aStr" (ty/tyVal) "stringFromInt64" (list "atimeSec"))
              (sys/entryInstr "anStr" (ty/tyVal) "stringFromInt64" (list "atimeNsec"))
              (sys/entryInstr "mStr" (ty/tyVal) "stringFromInt64" (list "mtimeSec"))
              (sys/entryInstr "mnStr" (ty/tyVal) "stringFromInt64" (list "mtimeNsec"))
              (ty/ssaInstr "sp" (ty/tyVal) (ty/opConst (ty/constStr 1)))
              (ty/ssaInstr "nl" (ty/tyVal) (ty/opConst (ty/constStr 2)))
              (sys/entryInstr "l1" (ty/tyVal) "stringConcat" (list "aStr" "sp"))
              (sys/entryInstr "l2" (ty/tyVal) "stringConcat" (list "l1" "anStr"))
              (sys/entryInstr "l3" (ty/tyVal) "stringConcat" (list "l2" "sp"))
              (sys/entryInstr "l4" (ty/tyVal) "stringConcat" (list "l3" "mStr"))
              (sys/entryInstr "l5" (ty/tyVal) "stringConcat" (list "l4" "sp"))
              (sys/entryInstr "l6" (ty/tyVal) "stringConcat" (list "l5" "mnStr"))
              (sys/entryInstr "line" (ty/tyVal) "stringConcat" (list "l6" "nl"))
              (sys/callInstr "wr" (ty/tyVal) "sysWrite" (list "one" "line"))
              (sys/int64Const "zeroExit" 0))
            (ty/termReturn "zeroExit")))))))

fn ! testUtimes work: String facts: libc/TripleFacts -> Bool
  (let [(fn0 (unwrapFn "utimes" (sys/sysUtimesFn facts)))
        (target (str work "/utimesTarget"))
        (aSec 1700000100) (aUsec 111000) (mSec 1700000300) (mUsec 222000)
        (okMod (caseModule facts (list target) (list fn0)
                 (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int64Const "aSec" aSec) (sys/int64Const "aUsec" aUsec)
                       (sys/int64Const "mSec" mSec) (sys/int64Const "mUsec" mUsec))
                 "sysUtimes" (list "p" "aSec" "aUsec" "mSec" "mUsec") (list (sys/int64Const "zero" 0)) "zero"))
        (errMod (errnoCaseModule facts (list (str target ".missing")) (list fn0)
                  (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/int64Const "aSec" aSec) (sys/int64Const "aUsec" aUsec)
                        (sys/int64Const "mSec" mSec) (sys/int64Const "mUsec" mUsec))
                  "sysUtimes" (list "p" "aSec" "aUsec" "mSec" "mUsec")))]
    (do (assert (ok? (fileWrite target "utimes me\n")) "utimes ok: target file written")
        (let [(text (textOf (llvm/emitLlvmProgram okMod "run")))]
          (do (declaresReal text "declare i32 @utimes(ptr, ptr)")
              (let [(out (runPlain work "sysUtimesOk" okMod))]
                (assert (= out.exitCode 0) (str "utimes ok: exit " out.exitCode ", want 0; stderr: " out.stderr)))))
        (let [(readMod (readAtimeMtimeModule facts target))
              (out (runPlain work "sysUtimesReadback" readMod))
              (fields (stringSplit (stringTrim out.stdout) " "))
              (gotASec (optionOr (listGet fields 0) "")) (gotANsec (optionOr (listGet fields 1) ""))
              (gotMSec (optionOr (listGet fields 2) "")) (gotMNsec (optionOr (listGet fields 3) ""))
              (wantANsec (* aUsec 1000)) (wantMNsec (* mUsec 1000))]
          (do (assert (= out.exitCode 0) (str "utimes readback: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= gotASec (stringFromInt64 aSec)) (str "utimes: st_atimespec.tv_sec " gotASec ", want " (stringFromInt64 aSec)))
              (assert (= gotMSec (stringFromInt64 mSec)) (str "utimes: st_mtimespec.tv_sec " gotMSec ", want " (stringFromInt64 mSec)))
              (assert (= gotANsec (stringFromInt64 wantANsec)) (str "utimes: st_atimespec.tv_nsec " gotANsec ", want " (stringFromInt64 wantANsec) " (aUsec*1000)"))
              (assert (= gotMNsec (stringFromInt64 wantMNsec)) (str "utimes: st_mtimespec.tv_nsec " gotMNsec ", want " (stringFromInt64 wantMNsec) " (mUsec*1000)"))))
        (expectErrno "utimes err" (runPlain work "sysUtimesErr" errMod) facts "ENOENT")))

fn ! testLocaltime work: String facts: libc/TripleFacts -> Bool
  (let [(fn0 (unwrapFn "localtime" (sys/sysLocaltimeFn facts)))
        (okMod (moduleOf facts (list " " "\n") (list (sys/sysErrnoValueFn facts) fn0 (sys/sysWriteFn)
                 (ty/ssaFunction "run" (list) (list) (ty/tyI64)
                   (list (sys/block "entry"
                           (list (sys/int64Const "epoch" 1700000000) (sys/int32Const "one" 1) (sys/callInstr "resv" (ty/tyVal) "sysLocaltime" (list "epoch")))
                           (okErrSwitch "resv" "okCase" "errCase"))
                         (sys/block "okCase"
                           (let [(payload (list (ty/ssaInstr "payload" (ty/tyVal) (ty/opVariantField "resv" 0))))
                                 (fields (listFieldInstrs "payload" 9 "f"))
                                 (spaceInstr (ty/ssaInstr "sp" (ty/tyVal) (ty/opConst (ty/constStr 0))))
                                 (nlInstr (ty/ssaInstr "nl" (ty/tyVal) (ty/opConst (ty/constStr 1))))
                                 (joined (joinIntsInstrs (pairSecond fields) "sp" "j"))
                                 (lineInstr (ty/ssaInstr "line" (ty/tyVal) (ty/opEntry "stringConcat" (list (pairSecond joined) "nl"))))
                                 (zeroInstr (sys/int64Const "zeroExit" 0))]
                             (listAppend payload (listAppend (pairFirst fields)
                               (listAppend (list spaceInstr nlInstr) (listAppend (pairFirst joined)
                                 (list lineInstr (sys/callInstr "wr" (ty/tyVal) "sysWrite" (list "one" "line")) zeroInstr))))))
                           (ty/termReturn "zeroExit"))
                         (sys/block "errCase" (errCaseInstrs) (ty/termReturn "errCode")))))))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare ptr @localtime_r(ptr, ptr)")
        (let [(ll (str work "/sysLocaltimeOk.ll"))]
          (do (assert (ok? (fileWrite ll text)) "localtime: .ll written")
              (expectExit "localtime: clang links" (str (clang) " -x ir " ll " -x none " (lib) " -lm -o " work "/sysLocaltimeOk") 0)))
        (let [(out (sh (str "TZ=UTC " work "/sysLocaltimeOk")))
              (fields (stringSplit (stringTrim out.stdout) " "))
              (oracle (dateFromEpoch 1700000000 "%S %M %H %d %m %Y %w %j"))
              (oFields (stringSplit (stringTrim oracle.stdout) " "))
              (wantSec (optionOr (listGet oFields 0) "")) (wantMin (optionOr (listGet oFields 1) "")) (wantHour (optionOr (listGet oFields 2) ""))
              (wantMday (optionOr (listGet oFields 3) "")) (wantMon1 (optionOr (stringToInt64 (optionOr (listGet oFields 4) "")) 0))
              (wantYear4 (optionOr (stringToInt64 (optionOr (listGet oFields 5) "")) 0)) (wantWday (optionOr (listGet oFields 6) ""))
              (wantYday1 (optionOr (stringToInt64 (optionOr (listGet oFields 7) "")) 0))]
          (do (assert (= out.exitCode 0) (str "localtime ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= (stringToInt64 (optionOr (listGet fields 0) "")) (stringToInt64 wantSec)) "localtime: tm_sec matches date's")
              (assert (= (stringToInt64 (optionOr (listGet fields 1) "")) (stringToInt64 wantMin)) "localtime: tm_min matches date's")
              (assert (= (stringToInt64 (optionOr (listGet fields 2) "")) (stringToInt64 wantHour)) "localtime: tm_hour matches date's")
              (assert (= (stringToInt64 (optionOr (listGet fields 3) "")) (stringToInt64 wantMday)) "localtime: tm_mday matches date's")
              (assert (= (optionOr (listGet fields 4) "") (stringFromInt64 (- wantMon1 1))) "localtime: tm_mon is date's %m minus 1")
              (assert (= (optionOr (listGet fields 5) "") (stringFromInt64 (- wantYear4 1900))) "localtime: tm_year is date's %Y minus 1900")
              (assert (= (stringToInt64 (optionOr (listGet fields 6) "")) (stringToInt64 wantWday)) "localtime: tm_wday matches date's %w")
              (assert (= (optionOr (listGet fields 7) "") (stringFromInt64 (- wantYday1 1))) "localtime: tm_yday is date's %j minus 1")
              true))))

fn ! testGetrusage work: String facts: libc/TripleFacts -> Bool
  (let [(fn0 (unwrapFn "getrusage" (sys/sysGetrusageFn facts)))
        (okMod (moduleOf facts (list " " "\n") (list (sys/sysErrnoValueFn facts) fn0 (sys/sysWriteFn)
                 (ty/ssaFunction "run" (list) (list) (ty/tyI64)
                   (list (sys/block "entry"
                           (list (sys/int32Const "one" 1) (sys/callInstr "resv" (ty/tyVal) "sysGetrusage" (list)))
                           (okErrSwitch "resv" "okCase" "errCase"))
                         (sys/block "okCase"
                           (let [(payload (list (ty/ssaInstr "payload" (ty/tyVal) (ty/opVariantField "resv" 0))))
                                 (fields (listFieldInstrs "payload" 3 "f"))
                                 (spaceInstr (ty/ssaInstr "sp" (ty/tyVal) (ty/opConst (ty/constStr 0))))
                                 (nlInstr (ty/ssaInstr "nl" (ty/tyVal) (ty/opConst (ty/constStr 1))))
                                 (joined (joinIntsInstrs (pairSecond fields) "sp" "j"))
                                 (lineInstr (ty/ssaInstr "line" (ty/tyVal) (ty/opEntry "stringConcat" (list (pairSecond joined) "nl"))))
                                 (zeroInstr (sys/int64Const "zeroExit" 0))]
                             (listAppend payload (listAppend (pairFirst fields)
                               (listAppend (list spaceInstr nlInstr) (listAppend (pairFirst joined)
                                 (list lineInstr (sys/callInstr "wr" (ty/tyVal) "sysWrite" (list "one" "line")) zeroInstr))))))
                           (ty/termReturn "zeroExit"))
                         (sys/block "errCase" (errCaseInstrs) (ty/termReturn "errCode")))))))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @getrusage(i32, ptr)")
        (let [(out (runPlain work "sysGetrusageOk" okMod))
              (fields (stringSplit (stringTrim out.stdout) " "))
              (maxRss (optionOr (stringToInt64 (optionOr (listGet fields 0) "")) -1))
              (userUs (optionOr (stringToInt64 (optionOr (listGet fields 1) "")) -1))
              (sysUs (optionOr (stringToInt64 (optionOr (listGet fields 2) "")) -1))]
          (do (assert (= out.exitCode 0) (str "getrusage ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (> maxRss 0) (str "getrusage ok: maxRss " maxRss ", want > 0"))
              (assert (>= userUs 0) (str "getrusage ok: userUs " userUs ", want >= 0"))
              (assert (>= sysUs 0) (str "getrusage ok: sysUs " sysUs ", want >= 0"))
              (assert (> (+ userUs sysUs) 0) (str "getrusage ok: userUs+sysUs " (+ userUs sysUs) ", want > 0"))
              true))))

fn ! testUname work: String facts: libc/TripleFacts -> Bool
  (let [(fn0 (unwrapFn "uname" (sys/sysUnameFn facts)))
        (okMod (moduleOf facts (list " " "\n") (list (sys/sysErrnoValueFn facts) fn0 (sys/sysWriteFn)
                 (ty/ssaFunction "run" (list) (list) (ty/tyI64)
                   (list (sys/block "entry"
                           (list (sys/int32Const "one" 1) (sys/callInstr "resv" (ty/tyVal) "sysUname" (list)))
                           (ty/termSwitch "resv" "Result" (list (ty/ssaCase "ok" (edge "okCase")) (ty/ssaCase "err" (edge "errCase"))) (none)))
                         (sys/block "okCase"
                           (list (ty/ssaInstr "payload" (ty/tyVal) (ty/opVariantField "resv" 0))
                                 (ty/ssaInstr "sysnameS" (ty/tyVal) (ty/opEntry "@listHeadOr" (list "payload" "payload")))
                                 (ty/ssaInstr "tailS" (ty/tyVal) (ty/opEntry "@listTailOr" (list "payload" "payload")))
                                 (ty/ssaInstr "machineS" (ty/tyVal) (ty/opEntry "@listHeadOr" (list "tailS" "tailS")))
                                 (ty/ssaInstr "sp" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                                 (ty/ssaInstr "nl" (ty/tyVal) (ty/opConst (ty/constStr 1)))
                                 (ty/ssaInstr "l1" (ty/tyVal) (ty/opEntry "stringConcat" (list "sysnameS" "sp")))
                                 (ty/ssaInstr "l2" (ty/tyVal) (ty/opEntry "stringConcat" (list "l1" "machineS")))
                                 (ty/ssaInstr "line" (ty/tyVal) (ty/opEntry "stringConcat" (list "l2" "nl")))
                                 (sys/int32Const "one2" 1) (sys/callInstr "wr" (ty/tyVal) "sysWrite" (list "one2" "line"))
                                 (sys/int64Const "zeroExit" 0))
                           (ty/termReturn "zeroExit"))
                         (sys/block "errCase" (errCaseInstrs) (ty/termReturn "errCode")))))))
        (text (textOf (llvm/emitLlvmProgram okMod "run")))]
    (do (declaresReal text "declare i32 @uname(ptr)")
        (let [(out (runPlain work "sysUnameOk" okMod))
              (fields (stringSplit (stringTrim out.stdout) " "))
              (nativeSysname (optionOr (listGet fields 0) "")) (nativeMachine (optionOr (listGet fields 1) ""))
              (wantSysname (stringTrim (sh "uname -s").stdout)) (wantMachine (stringTrim (sh "uname -m").stdout))]
          (do (assert (= out.exitCode 0) (str "uname ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
              (assert (= nativeSysname wantSysname) (str "uname ok: sysname " nativeSysname ", want " wantSysname))
              (assert (= nativeMachine wantMachine) (str "uname ok: machine " nativeMachine ", want " wantMachine))
              true))))

fn ! dirListPrintLoopModule facts: libc/TripleFacts path: String -> ty/SsaModule
  (moduleOf facts (list path "\n" "1") (list (sys/sysErrnoValueFn facts) (sys/sysWriteFn) (unwrapFn "dirList" (sys/sysDirListFn facts))
    (ty/ssaFunction "run" (list) (list) (ty/tyI64)
      (list (sys/block "entry"
              (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0))) (sys/callInstr "resv" (ty/tyVal) "sysDirList" (list "p")))
              (okErrSwitch "resv" "okCase" "errCase"))
            (sys/block "okCase"
              (list (ty/ssaInstr "names" (ty/tyVal) (ty/opVariantField "resv" 0)))
              (ty/termJump (ty/ssaEdge "loop" (list "names"))))
            (ty/ssaBlock "loop" (list (ty/ssaParam "cur" (ty/tyVal)))
              (list (ty/ssaInstr "isEmpty" (ty/tyI1) (ty/opEntry "listEmpty?" (list "cur"))))
              (ty/termBranch "isEmpty" (sys/edgeTo "done") (sys/edgeTo "writeOne")))
            (sys/block "writeOne"
              (list (ty/ssaInstr "headV" (ty/tyVal) (ty/opEntry "@listFirst" (list "cur")))
                    (ty/ssaInstr "tailV" (ty/tyVal) (ty/opEntry "@listRest" (list "cur")))
                    (ty/ssaInstr "nlC" (ty/tyVal) (ty/opConst (ty/constStr 1)))
                    (ty/ssaInstr "lineV" (ty/tyVal) (ty/opEntry "stringConcat" (list "headV" "nlC")))
                    (sys/int32Const "oneFd" 1) (sys/callInstr "wr" (ty/tyVal) "sysWrite" (list "oneFd" "lineV")))
              (ty/termJump (ty/ssaEdge "loop" (list "tailV"))))
            (sys/block "done" (list (sys/int64Const "zeroExit" 0)) (ty/termReturn "zeroExit"))
            (sys/block "errCase" (errCaseInstrs) (ty/termReturn "errCode"))))))

fn ! testDirList work: String facts: libc/TripleFacts -> Bool
  (let [(dir (str work "/dirListTarget"))]
    (do (assert (= (sh (str "mkdir -p " dir)).exitCode 0) "dirList: target directory made")
        (assert (ok? (fileWrite (str dir "/bb.txt") "b")) "dirList: bb.txt written")
        (assert (ok? (fileWrite (str dir "/aa.txt") "a")) "dirList: aa.txt written")
        (assert (ok? (fileWrite (str dir "/cc.txt") "c")) "dirList: cc.txt written")
        (let [(okMod (dirListPrintLoopModule facts dir))
              (text (textOf (llvm/emitLlvmProgram okMod "run")))]
          (do (declaresReal text "declare ptr @opendir(ptr)")
              (declaresReal text "declare ptr @readdir(ptr)")
              (declaresReal text "declare i32 @closedir(ptr)")
              (let [(out (runPlain work "sysDirListOk" okMod))
                    (nativeSorted (stringTrim (sh (str "printf %s " (quoteSh out.stdout) " | sort")).stdout))
                    (fixturePath (str work "/dirListFixture.asl"))
                    (fixtureSrc (str "(module tests/dirListFixture :x [main] :i [])\nfn ! main -> (Result Int64 String)\n  (mt (dirList \"" dir "\")\n    ((ok names) (mt (fdWrite 1 (stringJoin (map (fn [n] (str n \"\\n\")) names) \"\"))\n                   ((ok _) (ok 0)) ((err e) (err e))))\n    ((err e) (err e)))\n"))]
                (do (assert (= out.exitCode 0) (str "dirList ok: exit " out.exitCode ", want 0; stderr: " out.stderr))
                    (assert (ok? (fileWrite fixturePath fixtureSrc)) "dirList ok: asl-host comparison fixture written")
                    (let [(hostOut (sh (str (host) " run " fixturePath)))
                          (hostSorted (stringTrim (sh (str "printf %s " (quoteSh hostOut.stdout) " | sort")).stdout))]
                      (assert (= nativeSorted hostSorted) (str "dirList ok: sorted native names [" nativeSorted "] != asl-host dirList's sorted [" hostSorted "]")))))))
        (let [(errMod (errnoCaseModule facts (list (str dir ".missing")) (list (unwrapFn "dirList" (sys/sysDirListFn facts)))
                        (list (ty/ssaInstr "p" (ty/tyVal) (ty/opConst (ty/constStr 0)))) "sysDirList" (list "p")))]
          (expectErrno "dirList err" (runPlain work "sysDirListErr" errMod) facts "ENOENT"))))

fn quoteSh s: String -> String
  (str "'" (stringJoin (map (fn [(c String)] -> String (if (= c "'") "'\\''" c)) (stringChars s)) "") "'")

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))
        (facts (hostFacts))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testRead work facts)
        (testReadZeroLength work facts)
        (testFreeDeclaredPtr work facts)
        (testWrite work facts)
        (testClose work facts)
        (testPread work facts)
        (testPwrite work facts)
        (testKill work facts)
        (testFsync work facts)
        (testFlock work facts)
        (testRename work facts)
        (testChmod work facts)
        (testMkdir work facts)
        (testUnlink work facts)
        (testRmdir work facts)
        (testSymlink work facts)
        (testReadlink work facts)
        (testRealpath work facts)
        (testExePath work facts)
        (testSysconf work facts)
        (testClockGettime work facts)
        (testUsleep work facts)
        (testGetenv work facts)
        (testFcntl work facts)
        (testPoll work facts)
        (testNanosleep work facts)
        (testGetpid work facts)
        (testStat work facts)
        (testLstat work facts)
        (testUtimes work facts)
        (testLocaltime work facts)
        (testGetrusage work facts)
        (testUname work facts)
        (testDirList work facts)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
