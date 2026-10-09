(module asl-target-llvm/tests/sysNetTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/sys :a sys)
      (asl-target-llvm/sysNet :a sysNet)
      (asl-target-llvm/libc :a libc)])

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn host -> String
  "asl/host/out/asl-host"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! writeAndLink work: String name: String text: String -> Bool
  (let [(ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite ll text)) (str name ": .ll written"))
        (assert (= (sh (str (clang) " -x ir " ll " -x none " (lib) " -lm -o " work "/" name)).exitCode 0)
          (str name ": clang links against " (lib)))
        true))

fn ! opt -> String
  (if (= (sh "test -x /opt/homebrew/opt/llvm/bin/opt").exitCode 0) "/opt/homebrew/opt/llvm/bin/opt" "opt")

fn ! verifies? work: String name: String -> Bool
  (let [(out (sh (str (opt) " -passes=verify -disable-output " work "/" name ".ll")))]
    (do (assert (= out.exitCode 0) (str name ": opt -passes=verify; stderr: " out.stderr))
        true))

fn edge target: String -> ty/SsaEdge
  (ty/ssaEdge target (list))

fn okErrSwitch scrutinee: String okLabel: String errLabel: String -> ty/SsaTerm
  (ty/termSwitch scrutinee "Result" (list (ty/ssaCase "ok" (edge okLabel)) (ty/ssaCase "err" (edge errLabel))) (none))

fn okI64Instrs resv: String dest: String -> (List ty/SsaInstr)
  (list (ty/ssaInstr (str dest ".box") (ty/tyVal) (ty/opVariantField resv 0))
        (ty/ssaInstr dest (ty/tyI64) (ty/opUnbox (str dest ".box"))))

fn okValInstrs resv: String dest: String -> (List ty/SsaInstr)
  (list (ty/ssaInstr dest (ty/tyVal) (ty/opVariantField resv 0)))

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
    ((none) (do (assert false (str "hostFacts: no verified libc.asl row for this host's triple (uname says \"" (hostTriple) "\")")) (libc/emptyTripleFacts))))

fn ! mutantSockaddrInFacts base: libc/TripleFacts -> libc/TripleFacts
  (libc/TripleFacts :triple base.triple :verified base.verified :errnoAccessor base.errnoAccessor
    :consts base.consts :variadic base.variadic
    :structs (map (fn [(p (Pair String libc/StructFacts))] -> (Pair String libc/StructFacts)
                     (if (= (pairFirst p) "sockaddr_in")
                       (pair "sockaddr_in" (libc/StructFacts :size (pairSecond p).size
                                             :fields (map (fn [(fp (Pair String Int64))] -> (Pair String Int64)
                                                            (if (= (pairFirst fp) "sin_port") (pair "sin_port" (+ (pairSecond fp) 1)) fp))
                                                          (pairSecond p).fields)))
                       p))
                   base.structs))


fn tcpEchoRunFn facts: libc/TripleFacts -> (Result (List ty/SsaFunction) String)
  (mt (sysNet/tcpListenFn facts)
    ((err e) (err e))
    ((ok tcpListen)
     (mt (sysNet/tcpConnectFn facts)
       ((err e) (err e))
       ((ok tcpConnect)
        (mt (sysNet/sockAcceptFn facts)
          ((err e) (err e))
          ((ok sockAccept)
           (mt (sysNet/sockLocalPortFn facts)
             ((err e) (err e))
             ((ok sockLocalPort)
              (ok (list (sys/sysErrnoValueFn facts) tcpListen tcpConnect sockAccept sockLocalPort (sys/sysWriteFn) (sys/sysReadFn)
                (ty/ssaFunction "run" (list) (list) (ty/tyI64)
                  (list
                   (sys/block "s1.call"
                     (list (sys/int32Const "s1.port" 0) (sys/callInstr "s1.resv" (ty/tyVal) "sysNetTcpListen" (list "s1.port")))
                     (okErrSwitch "s1.resv" "s1.ok" "s1.err"))
                   (sys/block "s1.err" (list (sys/int64Const "s1.sent" 201)) (ty/termReturn "s1.sent"))
                   (sys/block "s1.ok"
                     (listAppend (okI64Instrs "s1.resv" "fd64")
                       (list (sys/primInstr "fdI32" (ty/tyI32) "rawNarrowI32" (list "fd64"))))
                     (ty/termJump (edge "s2.call")))
                   (sys/block "s2.call"
                     (list (sys/callInstr "s2.resv" (ty/tyVal) "sysNetSockLocalPort" (list "fdI32")))
                     (okErrSwitch "s2.resv" "s2.ok" "s2.err"))
                   (sys/block "s2.err" (list (sys/int64Const "s2.sent" 202)) (ty/termReturn "s2.sent"))
                   (sys/block "s2.ok"
                     (listAppend (okI64Instrs "s2.resv" "port64")
                       (list (sys/primInstr "portI32" (ty/tyI32) "rawNarrowI32" (list "port64"))))
                     (ty/termJump (edge "s3.call")))
                   (sys/block "s3.call"
                     (list (sys/callInstr "s3.resv" (ty/tyVal) "sysNetTcpConnect" (list "portI32")))
                     (okErrSwitch "s3.resv" "s3.ok" "s3.err"))
                   (sys/block "s3.err" (list (sys/int64Const "s3.sent" 203)) (ty/termReturn "s3.sent"))
                   (sys/block "s3.ok"
                     (listAppend (okI64Instrs "s3.resv" "cfd64")
                       (list (sys/primInstr "cfdI32" (ty/tyI32) "rawNarrowI32" (list "cfd64"))))
                     (ty/termJump (edge "s4.call")))
                   (sys/block "s4.call"
                     (list (sys/callInstr "s4.resv" (ty/tyVal) "sysNetSockAccept" (list "fdI32")))
                     (okErrSwitch "s4.resv" "s4.ok" "s4.err"))
                   (sys/block "s4.err" (list (sys/int64Const "s4.sent" 204)) (ty/termReturn "s4.sent"))
                   (sys/block "s4.ok"
                     (listAppend (okI64Instrs "s4.resv" "afd64")
                       (list (sys/primInstr "afdI32" (ty/tyI32) "rawNarrowI32" (list "afd64"))))
                     (ty/termJump (edge "s5.call")))
                   (sys/block "s5.call"
                     (list (ty/ssaInstr "dataVal" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                           (sys/callInstr "s5.resv" (ty/tyVal) "sysWrite" (list "cfdI32" "dataVal")))
                     (okErrSwitch "s5.resv" "s5.ok" "s5.err"))
                   (sys/block "s5.err" (list (sys/int64Const "s5.sent" 205)) (ty/termReturn "s5.sent"))
                   (sys/block "s5.ok" (list) (ty/termJump (edge "s6.call")))
                   (sys/block "s6.call"
                     (list (sys/int64Const "s6.max" 1) (sys/callInstr "s6.resv" (ty/tyVal) "sysRead" (list "afdI32" "s6.max")))
                     (okErrSwitch "s6.resv" "s6.ok" "s6.err"))
                   (sys/block "s6.err" (list (sys/int64Const "s6.sent" 206)) (ty/termReturn "s6.sent"))
                   (sys/block "s6.ok"
                     (listAppend (okValInstrs "s6.resv" "echoBytes")
                       (list (sys/int64Const "echoIdx0" 0)
                             (sys/entryInstr "echoByte" (ty/tyI64) "bytesGet" (list "echoBytes" "echoIdx0"))
                             (sys/callInstr "closeC" (ty/tyI32) "close" (list "cfdI32"))
                             (sys/callInstr "closeA" (ty/tyI32) "close" (list "afdI32"))
                             (sys/callInstr "closeL" (ty/tyI32) "close" (list "fdI32"))))
                     (ty/termReturn "echoByte"))))))))))))))


fn unixEchoRunFn facts: libc/TripleFacts path: String -> (Result (List ty/SsaFunction) String)
  (mt (sysNet/unixListenFn facts)
    ((err e) (err e))
    ((ok unixListen)
     (mt (sysNet/unixConnectFn facts)
       ((err e) (err e))
       ((ok unixConnect)
        (mt (sysNet/sockAcceptFn facts)
          ((err e) (err e))
          ((ok sockAccept)
           (ok (list (sys/sysErrnoValueFn facts) unixListen unixConnect sockAccept (sys/sysWriteFn) (sys/sysReadFn)
             (ty/ssaFunction "run" (list) (list) (ty/tyI64)
               (list
                (sys/block "u1.call"
                  (list (ty/ssaInstr "pathVal" (ty/tyVal) (ty/opConst (ty/constStr 1)))
                        (sys/callInstr "u1.resv" (ty/tyVal) "sysNetUnixListen" (list "pathVal")))
                  (okErrSwitch "u1.resv" "u1.ok" "u1.err"))
                (sys/block "u1.err" (list (sys/int64Const "u1.sent" 201)) (ty/termReturn "u1.sent"))
                (sys/block "u1.ok"
                  (listAppend (okI64Instrs "u1.resv" "fd64")
                    (list (sys/primInstr "fdI32" (ty/tyI32) "rawNarrowI32" (list "fd64"))))
                  (ty/termJump (edge "u2.call")))
                (sys/block "u2.call"
                  (list (ty/ssaInstr "pathVal2" (ty/tyVal) (ty/opConst (ty/constStr 1)))
                        (sys/callInstr "u2.resv" (ty/tyVal) "sysNetUnixConnect" (list "pathVal2")))
                  (okErrSwitch "u2.resv" "u2.ok" "u2.err"))
                (sys/block "u2.err" (list (sys/int64Const "u2.sent" 203)) (ty/termReturn "u2.sent"))
                (sys/block "u2.ok"
                  (listAppend (okI64Instrs "u2.resv" "cfd64")
                    (list (sys/primInstr "cfdI32" (ty/tyI32) "rawNarrowI32" (list "cfd64"))))
                  (ty/termJump (edge "u3.call")))
                (sys/block "u3.call"
                  (list (sys/callInstr "u3.resv" (ty/tyVal) "sysNetSockAccept" (list "fdI32")))
                  (okErrSwitch "u3.resv" "u3.ok" "u3.err"))
                (sys/block "u3.err" (list (sys/int64Const "u3.sent" 204)) (ty/termReturn "u3.sent"))
                (sys/block "u3.ok"
                  (listAppend (okI64Instrs "u3.resv" "afd64")
                    (list (sys/primInstr "afdI32" (ty/tyI32) "rawNarrowI32" (list "afd64"))))
                  (ty/termJump (edge "u4.call")))
                (sys/block "u4.call"
                  (list (ty/ssaInstr "dataVal" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                        (sys/callInstr "u4.resv" (ty/tyVal) "sysWrite" (list "cfdI32" "dataVal")))
                  (okErrSwitch "u4.resv" "u4.ok" "u4.err"))
                (sys/block "u4.err" (list (sys/int64Const "u4.sent" 205)) (ty/termReturn "u4.sent"))
                (sys/block "u4.ok" (list) (ty/termJump (edge "u5.call")))
                (sys/block "u5.call"
                  (list (sys/int64Const "u5.max" 1) (sys/callInstr "u5.resv" (ty/tyVal) "sysRead" (list "afdI32" "u5.max")))
                  (okErrSwitch "u5.resv" "u5.ok" "u5.err"))
                (sys/block "u5.err" (list (sys/int64Const "u5.sent" 206)) (ty/termReturn "u5.sent"))
                (sys/block "u5.ok"
                  (listAppend (okValInstrs "u5.resv" "echoBytes")
                    (list (sys/int64Const "echoIdx0" 0)
                          (sys/entryInstr "echoByte" (ty/tyI64) "bytesGet" (list "echoBytes" "echoIdx0"))
                          (sys/callInstr "closeC" (ty/tyI32) "close" (list "cfdI32"))
                          (sys/callInstr "closeA" (ty/tyI32) "close" (list "afdI32"))
                          (sys/callInstr "closeL" (ty/tyI32) "close" (list "fdI32"))))
                  (ty/termReturn "echoByte"))))))))))))

fn dedupExternsByName externs: (List ty/SsaExtern) -> (List ty/SsaExtern)
  (mapValues (fold (fn [(acc (Map String ty/SsaExtern)) (e ty/SsaExtern)] -> (Map String ty/SsaExtern) (mapSet acc e.name e)) (mapEmpty) externs))

fn moduleOf facts: libc/TripleFacts strings: (List String) functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" strings (list (sys/resultTypeDecl) (sys/optionTypeDecl)) (list)
    (dedupExternsByName (listAppend (sys/sysExterns facts) (sysNet/sysNetExterns facts))) (list) functions)

fn textOf res: (Result String (List ty/IrDiag)) -> String
  (mt res ((ok text) text) ((err diags) (str "ERR: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code "@" d.locus ": " d.message)) diags) " || "))))

fn ! unwrapFn label: String res: (Result ty/SsaFunction String) -> ty/SsaFunction
  (mt res ((ok f) f) ((err e) (do (assert false (str label ": " e)) (sys/sysGetpidFn))))

fn ! unwrapFns label: String res: (Result (List ty/SsaFunction) String) -> (List ty/SsaFunction)
  (mt res ((ok fs) fs) ((err e) (do (assert false (str label ": " e)) (list))))

fn ! asciiA -> String
  "A"

fn ! tcpSourceFixture work: String -> String
  (let [(path (str work "/tcpEchoSrc.asl"))
        (src (str
               "(module tests/tcpEchoSrc :x [main] :i [])\n"
               "fn ! main args: (List String) -> (Result Int64 String)\n"
               "  (mt (tcpListen 0)\n"
               "    ((err e) (ok 201))\n"
               "    ((ok fd)\n"
               "     (mt (sockLocalPort fd)\n"
               "       ((err e) (ok 202))\n"
               "       ((ok port)\n"
               "        (mt (tcpConnect port)\n"
               "          ((err e) (ok 203))\n"
               "          ((ok cfd)\n"
               "           (mt (sockAccept fd)\n"
               "             ((err e) (ok 204))\n"
               "             ((ok afd)\n"
               "              (mt (fdWrite cfd \"A\")\n"
               "                ((err e) (ok 205))\n"
               "                ((ok n)\n"
               "                 (mt (fdRead afd 1)\n"
               "                   ((err e) (ok 206))\n"
               "                   ((ok s)\n"
               "                    (do (fdClose cfd) (fdClose afd) (fdClose fd)\n"
               "                        (if (= s \"A\") (ok 65) (ok 0)))))))))))))))\n"))]
    (do (assert (ok? (fileWrite path src)) "tcpEchoSrc.asl written")
        path))

fn ! unixSourceFixture work: String path: String -> String
  (let [(srcPath (str work "/unixEchoSrc.asl"))
        (src (str
               "(module tests/unixEchoSrc :x [main] :i [])\n"
               "fn ! main args: (List String) -> (Result Int64 String)\n"
               "  (mt (unixListen \"" path "\")\n"
               "    ((err e) (ok 201))\n"
               "    ((ok fd)\n"
               "     (mt (unixConnect \"" path "\")\n"
               "       ((err e) (ok 203))\n"
               "       ((ok cfd)\n"
               "        (mt (sockAccept fd)\n"
               "          ((err e) (ok 204))\n"
               "          ((ok afd)\n"
               "           (mt (fdWrite cfd \"A\")\n"
               "             ((err e) (ok 205))\n"
               "             ((ok n)\n"
               "              (mt (fdRead afd 1)\n"
               "                ((err e) (ok 206))\n"
               "                ((ok s)\n"
               "                 (do (fdClose cfd) (fdClose afd) (fdClose fd)\n"
               "                     (if (= s \"A\") (ok 65) (ok 0)))))))))))))\n"))]
    (do (assert (ok? (fileWrite srcPath src)) "unixEchoSrc.asl written")
        srcPath))

fn ! runOneEcho work: String name: String facts: libc/TripleFacts runFn: (Result (List ty/SsaFunction) String) strings: (List String) -> Int64
  (let [(fns (unwrapFns (str name ": step functions") runFn))]
    (if (= (listLength fns) 0)
      -1
      (let [(allFns (listAppend (list (sys/sysGetpidFn)) fns))
            (text (textOf (llvm/emitLlvmProgram (moduleOf facts strings allFns) "run")))]
        (do (assert (not (stringStartsWith? text "ERR")) (str name ": emits: " text))
            (writeAndLink work name text)
            (verifies? work name)
            (sh (str work "/" name)).exitCode))))

fn ! emitAndVerifyOnly work: String name: String facts: libc/TripleFacts runFn: (Result (List ty/SsaFunction) String) strings: (List String) -> Bool
  (let [(fns (unwrapFns (str name ": step functions") runFn))]
    (if (= (listLength fns) 0)
      false
      (let [(allFns (listAppend (list (sys/sysGetpidFn)) fns))
            (text (textOf (llvm/emitLlvmProgram (moduleOf facts strings allFns) "run")))]
        (do (assert (not (stringStartsWith? text "ERR")) (str name ": emits: " text))
            (assert (stringContains? text "@accept4") (str name ": calls accept4, the linux-only cloexec-atomic accept"))
            (assert (ok? (fileWrite (str work "/" name ".ll") text)) (str name ": .ll written"))
            (verifies? work name)))))

fn ! nulPathRunFn facts: libc/TripleFacts -> (Result (List ty/SsaFunction) String)
  (mt (sysNet/unixListenFn facts)
    ((err e) (err e))
    ((ok unixListen)
     (mt (libc/libcConst facts "EINVAL")
       ((none) (err "hostFacts: no EINVAL const"))
       ((some einval)
        (ok (list (sys/sysErrnoValueFn facts) unixListen
          (ty/ssaFunction "run" (list) (list) (ty/tyI64)
            (list
             (sys/block "n.entry"
               (list (sys/int64Const "n.bufSize" 4)
                     (sys/callInstr "n.buf" (ty/tyPtr) "malloc" (list "n.bufSize"))
                     (sys/int64Const "n.o0" 0) (sys/int32Const "n.cA" 97) (sys/primInstr "n.s0" (ty/tyI1) "rawStoreI8" (list "n.buf" "n.o0" "n.cA"))
                     (sys/int64Const "n.o1" 1) (sys/int32Const "n.cB" 98) (sys/primInstr "n.s1" (ty/tyI1) "rawStoreI8" (list "n.buf" "n.o1" "n.cB"))
                     (sys/int64Const "n.o2" 2) (sys/int32Const "n.zero" 0) (sys/primInstr "n.s2" (ty/tyI1) "rawStoreI8" (list "n.buf" "n.o2" "n.zero"))
                     (sys/int64Const "n.o3" 3) (sys/int32Const "n.cC" 99) (sys/primInstr "n.s3" (ty/tyI1) "rawStoreI8" (list "n.buf" "n.o3" "n.cC"))
                     (sys/int64Const "n.len" 4)
                     (sys/callInstr "n.pathVal" (ty/tyVal) "mkStr" (list "n.buf" "n.len"))
                     (sys/callInstr "n.resv" (ty/tyVal) "sysNetUnixListen" (list "n.pathVal")))
               (okErrSwitch "n.resv" "n.okCase" "n.errCase"))
             (sys/block "n.okCase" (list (sys/int64Const "n.wrongOk" 1)) (ty/termReturn "n.wrongOk"))
             (sys/block "n.errCase"
               (list (ty/ssaInstr "n.errBox" (ty/tyVal) (ty/opVariantField "n.resv" 0))
                     (ty/ssaInstr "n.errCode" (ty/tyI64) (ty/opUnbox "n.errBox"))
                     (sys/int64Const "n.einvalC" einval)
                     (sys/primInstr "n.isEinval" (ty/tyI1) "eqInt" (list "n.errCode" "n.einvalC")))
               (ty/termBranch "n.isEinval" (edge "n.good") (edge "n.bad")))
             (sys/block "n.good" (list (sys/int64Const "n.65" 65)) (ty/termReturn "n.65"))
             (sys/block "n.bad" (list (sys/int64Const "n.0" 0)) (ty/termReturn "n.0"))))))))))

fn ! portRangeRunFn facts: libc/TripleFacts -> (Result (List ty/SsaFunction) String)
  (mt (sysNet/tcpListenFn facts)
    ((err e) (err e))
    ((ok tcpListen)
     (mt (sysNet/tcpConnectFn facts)
       ((err e) (err e))
       ((ok tcpConnect)
        (mt (libc/libcConst facts "EINVAL")
          ((none) (err "hostFacts: no EINVAL const"))
          ((some einval)
           (ok (list (sys/sysErrnoValueFn facts) tcpListen tcpConnect
             (ty/ssaFunction "run" (list) (list) (ty/tyI64)
               (list
                (sys/block "p.entry"
                  (list (sys/int32Const "p.big" 65536)
                        (sys/callInstr "p.resv1" (ty/tyVal) "sysNetTcpListen" (list "p.big")))
                  (okErrSwitch "p.resv1" "p.wrongOk1" "p.err1"))
                (sys/block "p.wrongOk1" (list (sys/int64Const "p.w1" 1)) (ty/termReturn "p.w1"))
                (sys/block "p.err1"
                  (list (ty/ssaInstr "p.eb1" (ty/tyVal) (ty/opVariantField "p.resv1" 0))
                        (ty/ssaInstr "p.ec1" (ty/tyI64) (ty/opUnbox "p.eb1"))
                        (sys/int64Const "p.einvalC1" einval)
                        (sys/primInstr "p.isE1" (ty/tyI1) "eqInt" (list "p.ec1" "p.einvalC1")))
                  (ty/termBranch "p.isE1" (edge "p.step2") (edge "p.bad")))
                (sys/block "p.step2"
                  (list (sys/int32Const "p.big2" 70000)
                        (sys/callInstr "p.resv2" (ty/tyVal) "sysNetTcpConnect" (list "p.big2")))
                  (okErrSwitch "p.resv2" "p.wrongOk2" "p.err2"))
                (sys/block "p.wrongOk2" (list (sys/int64Const "p.w2" 2)) (ty/termReturn "p.w2"))
                (sys/block "p.err2"
                  (list (ty/ssaInstr "p.eb2" (ty/tyVal) (ty/opVariantField "p.resv2" 0))
                        (ty/ssaInstr "p.ec2" (ty/tyI64) (ty/opUnbox "p.eb2"))
                        (sys/int64Const "p.einvalC2" einval)
                        (sys/primInstr "p.isE2" (ty/tyI1) "eqInt" (list "p.ec2" "p.einvalC2")))
                  (ty/termBranch "p.isE2" (edge "p.good") (edge "p.bad")))
                (sys/block "p.good" (list (sys/int64Const "p.65" 65)) (ty/termReturn "p.65"))
                (sys/block "p.bad" (list (sys/int64Const "p.0" 0)) (ty/termReturn "p.0"))))))))))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d")) (work (stringReplace made.stdout "\n" "")) (facts (hostFacts))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (let [(tcpNative (runOneEcho work "tcpEcho" facts (tcpEchoRunFn facts) (list (asciiA))))
              (tcpSrc (tcpSourceFixture work))
              (tcpHost (sh (str (host) " run " tcpSrc)))]
          (do (assert (= tcpNative 65) (str "tcp echo native: exit " tcpNative ", want 65 ('A' echoed through a real loopback TCP round trip)"))
              (assert (= tcpHost.exitCode 65) (str "tcp echo asl-host: exit " tcpHost.exitCode ", want 65; stderr " tcpHost.stderr))
              (assert (= tcpNative tcpHost.exitCode) (str "tcp echo: native exit equals asl-host run's exit; native=" tcpNative " host=" tcpHost.exitCode))))
        (let [(sockPath (str work "/echo.sock"))
              (sockPathHost (str work "/echoHost.sock"))
              (unixNative (runOneEcho work "unixEcho" facts (unixEchoRunFn facts sockPath) (list (asciiA) sockPath)))
              (unixSrc (unixSourceFixture work sockPathHost))
              (unixHost (sh (str (host) " run " unixSrc)))]
          (do (assert (= unixNative 65) (str "unix echo native: exit " unixNative ", want 65"))
              (assert (= unixHost.exitCode 65) (str "unix echo asl-host: exit " unixHost.exitCode ", want 65; stderr " unixHost.stderr))
              (assert (= unixNative unixHost.exitCode) (str "unix echo: native exit equals asl-host run's exit; native=" unixNative " host=" unixHost.exitCode))))
        (let [(mutant (mutantSockaddrInFacts facts))
              (mutantResult (runOneEcho work "tcpEchoMutant" mutant (tcpEchoRunFn mutant) (list (asciiA))))]
          (assert (not (= mutantResult 65)) (str "mutant sin_port offset+1: tcp echo must NOT exit 65 (got " mutantResult "), proving the gate is sensitive to a real byte-layout bug")))
        (let [(nulResult (runOneEcho work "nulPath" facts (nulPathRunFn facts) (list)))]
          (assert (= nulResult 65) (str "unixListen(\"ab\\0c\"): exit " nulResult ", want 65 (EINVAL rejected before socket(), as unixAddr's memchr does)")))
        (let [(portResult (runOneEcho work "portRange" facts (portRangeRunFn facts) (list)))]
          (assert (= portResult 65) (str "tcpListen(65536)/tcpConnect(70000): exit " portResult ", want 65 (both EINVAL, as portArg does)")))
        (assert (emitAndVerifyOnly work "tcpEchoLinuxX8664" (libc/linuxX8664Facts) (tcpEchoRunFn (libc/linuxX8664Facts)) (list (asciiA)))
          "linux-x86_64 sysNet IR (accept4 branch) verifies")
        (assert (emitAndVerifyOnly work "tcpEchoLinuxAarch64" (libc/linuxAarch64Facts) (tcpEchoRunFn (libc/linuxAarch64Facts)) (list (asciiA)))
          "linux-aarch64 sysNet IR (accept4 branch) verifies")
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
