(module asl-target-llvm/tests/sysNetRouteTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysNet :a sysNet)
      (asl-target-llvm/sysRoute :a rt)])

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
    ((none) (do (assert false (str "hostFacts: libc.asl has no row for this host's triple \"" (hostTriple) "\"")) (libc/emptyTripleFacts))))

fn ! hostConst name: String -> String
  (mt (libc/libcConst (hostFacts) name)
    ((some v) (str "io:" v))
    ((none) (do (assert false (str "libc.asl has no " name " row for " (hostTriple))) "")))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn echoSource -> String
  (lines (list
    "(module netEcho :x [main] :i [])"
    ""
    "fn ! roundTrip label: String lfd: Int64 cfd: Int64 -> Int64"
    "  (mt (sockAccept lfd)"
    "    ((err e) (do (println label \"sockAccept\" e) 1))"
    "    ((ok afd)"
    "      (do (fdWrite cfd \"ping\")"
    "          (let [(got (mt (fdRead afd 4) ((ok s) s) ((err e) (str \"err \" e))))]"
    "            (do (println label \"echo\" got)"
    "                (fdClose afd) (fdClose cfd) (fdClose lfd)"
    "                (if (= got \"ping\") 0 1))))))"
    ""
    "fn ! tcpEcho -> Int64"
    "  (mt (tcpListen 0)"
    "    ((err e) (do (println \"tcp tcpListen\" e) 1))"
    "    ((ok lfd)"
    "      (mt (sockLocalPort lfd)"
    "        ((err e) (do (println \"tcp sockLocalPort\" e) 1))"
    "        ((ok port)"
    "          (do (println \"tcp port in range\" (and (> port 0) (<= port 65535)))"
    "              (mt (tcpConnect port)"
    "                ((err e) (do (println \"tcp tcpConnect\" e) 1))"
    "                ((ok cfd) (roundTrip \"tcp\" lfd cfd))))))))"
    ""
    "fn ! unixEcho dir: String -> Int64"
    "  (let [(path (str dir \"/echo.sock\"))]"
    "    (mt (unixListen path)"
    "      ((err e) (do (println \"unix unixListen\" e) 1))"
    "      ((ok lfd)"
    "        (mt (unixConnect path)"
    "          ((err e) (do (println \"unix unixConnect\" e) 1))"
    "          ((ok cfd) (let [(code (roundTrip \"unix\" lfd cfd))] (do (pathRemove path) code)))))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(dir (optionOr (listHead args) \".\"))"
    "        (t (tcpEcho))"
    "        (u (unixEcho dir))]"
    "    (ok (+ t u)))"))

fn errorsSource -> String
  (lines (list
    "(module netErrors :x [main] :i [])"
    ""
    "fn shape r: (Result Int64 String) -> String"
    "  (mt r ((ok _) \"ok\") ((err e) e))"
    ""
    "fn ! report label: String r: (Result Int64 String) -> Int64"
    "  (do (println label (shape r)) 0)"
    ""
    "fn ! anyPort x: Any"
    "  (tcpListen x)"
    ""
    "fn ! anyPath x: Any"
    "  (unixListen x)"
    ""
    "fn ! boundCases -> Int64"
    "  (mt (tcpListen 0)"
    "    ((err e) (do (println \"tcpListen 0\" e) 1))"
    "    ((ok lfd)"
    "      (mt (sockLocalPort lfd)"
    "        ((err e) (do (println \"sockLocalPort\" e) 1))"
    "        ((ok port)"
    "          (do (report \"tcpListen bound port\" (tcpListen port))"
    "              (fdClose lfd)"
    "              (report \"tcpConnect closed port\" (tcpConnect port)))))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(dir (optionOr (listHead args) \".\"))"
    "        (long (stringJoin (map (fn [(i Int64)] -> String \"a\") (range 0 200)) \"\"))]"
    "    (do (report \"tcpListen -1\" (tcpListen -1))"
    "        (report \"tcpListen 65536\" (tcpListen 65536))"
    "        (boundCases)"
    "        (report \"tcpConnect 0\" (tcpConnect 0))"
    "        (report \"tcpConnect 4294967297\" (tcpConnect 4294967297))"
    "        (report \"sockAccept -1\" (sockAccept -1))"
    "        (report \"sockAccept 2147483648\" (sockAccept 2147483648))"
    "        (report \"sockLocalPort -1\" (sockLocalPort -1))"
    "        (report \"unixListen empty\" (unixListen \"\"))"
    "        (report (str \"unixListen \" (stringLength long) \"-byte path\") (unixListen long))"
    "        (report \"unixConnect missing\" (unixConnect (str dir \"/missing.sock\")))"
    "        (report \"tcpListen string 80\" (anyPort \"80\"))"
    "        (report \"tcpListen float 80.0\" (anyPort 80.0))"
    "        (report \"unixListen int 7\" (anyPath 7))"
    "        (ok 0)))"))

fn sixSource -> String
  (lines (list
    "(module netSix :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (mt (tcpListen -1) ((ok _) \"ok\") ((err e) e)))"
    "      (println (mt (tcpConnect 0) ((ok _) \"ok\") ((err e) e)))"
    "      (println (mt (sockAccept -1) ((ok _) \"ok\") ((err e) e)))"
    "      (println (mt (sockLocalPort -1) ((ok _) \"ok\") ((err e) e)))"
    "      (println (mt (unixListen \"\") ((ok _) \"ok\") ((err e) e)))"
    "      (println (mt (unixConnect \"\") ((ok _) \"ok\") ((err e) e)))"
    "      (ok 0))"))

fn libSource -> String
  (lines (list
    "(module nrfx/netLib :x [listenShape])"
    ""
    "fn ! listenShape port: Int64 -> String"
    "  (mt (tcpListen port) ((ok fd) \"ok\") ((err e) e))"))

fn appSource -> String
  (lines (list
    "(module nrfx/netApp :x [main] :i [(nrfx/netLib :a nl)])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (str \"lib \" (nl/listenShape -1)))"
    "      (println (str \"lib \" (nl/listenShape 0)))"
    "      (println (str \"app \" (mt (tcpListen 70000) ((ok fd) \"ok\") ((err e) e))))"
    "      (ok 0))"))

fn wrapperDef name: String -> String
  (str "define internal tailcc %Val @asl$2Dtarget$2Dllvm$2FsysRoute$2E" name "(")

fn routedNames -> (List String)
  (list "tcpListen" "tcpConnect" "sockAccept" "sockLocalPort" "unixListen" "unixConnect")

fn cTableSymbols -> (List String)
  (list "bTcpListen" "bSockAccept" "bUnixListen" "sysNetBuiltins")

fn ! fileText path: String -> String
  (mt (fileReadString path) ((ok t) t) ((err e) (do (assert false (str path ": " e)) "")))

fn ! build work: String name: String src: String -> String
  (let [(srcPath (str work "/" name ".asl"))
        (ll (str work "/" name ".ll"))
        (preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do (assert (ok? (fileWrite srcPath src)) (str name ".asl written"))
        (assert (not (stringEmpty? preludeText)) (str (lk/preludePath) " is readable"))
        (mt (mt (lk/lowerSourceWith src preludeText) ((err ds) (err ds)) ((ok m) (llvm/emitLlvmProgramFor (hostFacts) m "main")))
          ((err ds) (do (assert false (str name ": lowerSourceWith and emitLlvmProgramFor: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; "))) ""))
          ((ok text) (do (assert (ok? (fileWrite ll text)) (str name ".ll written")) text)))))

fn ! linkBin work: String name: String lls: (List String) -> Bool
  (linkBinWith work name lls (lib))

fn ! linkBinWith work: String name: String lls: (List String) libs: String -> Bool
  (let [(out (sh (str (clang) " -x ir " (stringJoin lls " ") " -x none " libs " -lm -o " work "/" name)))]
    (do (assert (= out.exitCode 0) (str name ": links; " out.stderr))
        (= out.exitCode 0)))

fn ! nmNames bin: String -> (List String)
  (let [(out (sh (str "nm -P " bin)))]
    (do (assert (= out.exitCode 0) (str "nm -P " bin ": " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listHead (stringSplit line " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringEmpty? line))) (stringSplit out.stdout "\n")))))

fn ! checkIr label: String ll: String -> Bool
  (do (assert (not (stringContains? ll "asl_rt_builtin_sysNet")) (str label ": emitted IR has no asl_rt_builtin_sysNet"))
      (map (fn [(n String)] -> Bool (do (assert (stringContains? ll (wrapperDef n)) (str label ": IR defines the " n " wrapper internal")) true)) (routedNames))
      true)

fn ! checkSymbols label: String bin: String -> Bool
  (let [(names (nmNames bin))]
    (do (assert (> (listLength names) 0) (str label ": nm -P lists symbols"))
        (map (fn [(s String)] -> Bool (do (assert (not (listContains? names s)) (str label ": nm -P has no " s)) true)) (cTableSymbols))
        true))

fn ! checkParity label: String bin: String src: String nativeArg: String hostArg: String -> String
  (let [(native (sh (str bin " " nativeArg)))
        (vm (sh (str (host) " run " src " " hostArg)))]
    (do (assert (= native.stdout vm.stdout) (str label ": native stdout equals asl-host run's; native=" native.stdout " vm=" vm.stdout " vm stderr=" vm.stderr))
        (assert (= native.exitCode vm.exitCode) (str label ": native exit " native.exitCode " equals asl-host run's " vm.exitCode "; native stderr " native.stderr))
        native.stdout))

fn ! testEcho work: String -> Bool
  (let [(ll (build work "netEcho" (echoSource)))
        (_ (checkIr "netEcho" ll))
        (bin (str work "/netEcho"))
        (_ (linkBin work "netEcho" (list (str work "/netEcho.ll"))))
        (_ (checkSymbols "netEcho" bin))
        (_ (sh (str "mkdir -p " work "/echoNative " work "/echoHost")))
        (out (checkParity "netEcho" bin (str work "/netEcho.asl") (str work "/echoNative") (str work "/echoHost")))]
    (do (assert (= out (lines (list "tcp port in range true" "tcp echo ping" "unix echo ping"))) (str "netEcho: both echoes arrive: " out))
        true))

fn ! testErrors work: String -> Bool
  (let [(ll (build work "netErrors" (errorsSource)))
        (_ (checkIr "netErrors" ll))
        (bin (str work "/netErrors"))
        (_ (linkBin work "netErrors" (list (str work "/netErrors.ll"))))
        (_ (checkSymbols "netErrors" bin))
        (out (checkParity "netErrors" bin (str work "/netErrors.asl") work work))
        (inval (hostConst "EINVAL"))
        (bound (optionOr (listGet (stringSplit out "\n") 2) ""))
        (_ (assert (and (stringStartsWith? bound "tcpListen bound port io:") (not (= bound (str "tcpListen bound port " inval))))
                   (str "netErrors: listening on a bound port is an errno other than EINVAL: " bound)))
        (want (lines (list (str "tcpListen -1 " inval) (str "tcpListen 65536 " inval) bound (str "tcpConnect closed port " (hostConst "ECONNREFUSED"))
                           (str "tcpConnect 0 " inval) (str "tcpConnect 4294967297 " inval) (str "sockAccept -1 " inval) (str "sockAccept 2147483648 " inval) (str "sockLocalPort -1 " inval)
                           (str "unixListen empty " inval) (str "unixListen 200-byte path " inval) (str "unixConnect missing " (hostConst "ENOENT"))
                           (str "tcpListen string 80 " inval) (str "tcpListen float 80.0 " inval) (str "unixListen int 7 " inval))))]
    (do (assert (= out want) (str "netErrors: each case prints the VM's err shape: " out))
        true))

fn ! countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn ! testTwoModules work: String -> Bool
  (let [(dir (str work "/mm"))
        (_ (sh (str "mkdir -p " dir "/nrfx")))
        (_ (assert (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig)\n")) "two-module root marker written"))
        (_ (assert (ok? (fileWrite (str dir "/nrfx/netLib.asl") (libSource))) "netLib.asl written"))
        (appPath (str dir "/nrfx/netApp.asl"))
        (_ (assert (ok? (fileWrite appPath (appSource))) "netApp.asl written"))
        (want (lines (list "lib io:22" "lib ok" "app io:22")))
        (linkedLl (str work "/netLinked.ll"))
        (built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " appPath " -o " linkedLl)))
        (_ (assert (= built.exitCode 0) (str "two-module asl1 build: " built.stdout built.stderr)))
        (linkedText (fileText linkedLl))
        (routedHere (some? (rt/routeFactsFor (hostTriple))))
        (_ (if routedHere
             (do (assert (= (countOf linkedText "define internal tailcc %Val @sysNetTcpListen(") 1) "linked two-module IR defines sysNetTcpListen once")
                 (checkIr "netLinked" linkedText))
             (do (assert (stringContains? linkedText "asl_rt_builtin_sysNet") (str "asl1 build on unverified " (hostTriple) " keeps the C sysNet table"))
                 (assert (= (countOf linkedText "@sysNetTcpListen(") 0) (str "asl1 build on unverified " (hostTriple) " adds no routed function"))
                 true)))
        (_ (linkBin work "netLinked" (list linkedLl)))
        (_ (if routedHere (checkSymbols "netLinked" (str work "/netLinked")) true))
        (linkedOut (checkParity "netLinked" (str work "/netLinked") appPath "" ""))
        (_ (assert (= linkedOut want) (str "two-module linked program prints " linkedOut)))]
    (mt (lk/loadClosure! appPath)
      ((err ds) (do (assert false (str "loadClosure! " appPath ": " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
      ((ok units)
        (let [(lls (map (fn [(u lk/LinkUnit)] -> String
                          (let [(scope (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude (list) :strings (list) :only (none)))
                                (ll (str work "/sep." (stringReplace u.name "/" "_") ".ll"))]
                            (mt (low/lowerLinked u.forms u.positions scope)
                              ((err ds) (do (assert false (str u.name " lowers: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) ll))
                              ((ok m)
                                (let [(res (if (= u.name "nrfx/netApp") (llvm/emitLlvmProgramFor (hostFacts) m (str m.name ".main")) (llvm/emitLlvmModuleFor (hostFacts) m)))]
                                  (mt res
                                    ((err ds) (do (assert false (str u.name " emits: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) ll))
                                    ((ok text)
                                      (do (assert (= (countOf text "define internal tailcc %Val @sysNetTcpListen(") 1) (str u.name ": its own internal sysNetTcpListen"))
                                          (assert (ok? (fileWrite ll text)) (str ll " written"))
                                          ll))))))))
                        units))]
          (do (assert (= (listLength lls) 2) "the closure has two modules")
              (linkBin work "netSeparate" lls)
              (checkSymbols "netSeparate" (str work "/netSeparate"))
              (assert (= (sh (str work "/netSeparate")).stdout want) "separately compiled two-module program prints as the VM does")
              true)))))

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/opt/homebrew/opt/llvm@22/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (listHead known))

fn ! testLinuxRouting work: String -> Bool
  (mt (low/lowerSource (sixSource))
    ((err ds) (do (assert false (str "netSix lowers: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
    ((ok m)
      (mt (llvm/emitLlvmProgramFor (libc/linuxX8664Facts) m "main")
        ((err ds) (do (assert false (str "netSix emits for linux-x86_64: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
        ((ok text)
          (do (checkIr "netSix linux-x86_64" text)
              (assert (stringContains? text "@__errno_location") "linux-x86_64 routing reads errno through __errno_location")
              (assert (stringContains? text "@accept4") "linux-x86_64 routing accepts through accept4")
              (assert (not (stringContains? text "@__error(")) "linux-x86_64 routing has no darwin __error")
              (assert (ok? (fileWrite (str work "/netSixLinux.ll") text)) "netSixLinux.ll written")
              (mt (optBin)
                ((none) (do (println "netSix linux-x86_64: no opt on this host, -passes=verify skipped") true))
                ((some o) (do (assert (= (sh (str o " -passes=verify -disable-output " work "/netSixLinux.ll")).exitCode 0) "linux-x86_64 routed IR verifies") true))))))))

fn backlogIn res: (Result ty/SsaFunction String) dest: String -> Int64
  (mt res
    ((err _) -1)
    ((ok f) (fold (fn [(acc Int64) (b ty/SsaBlock)] -> Int64
                    (fold (fn [(acc2 Int64) (i ty/SsaInstr)] -> Int64
                            (if (= i.dest dest) (mt i.op ((ty/opConst c) (mt c ((ty/constInt v) v) (_ acc2))) (_ acc2)) acc2))
                          acc b.instrs))
                  -1 f.blocks)))

fn ! testBacklog -> Bool
  (do (assert (= (backlogIn (sysNet/tcpListenFn (libc/darwinArm64Facts)) "tl.backlog") 128) "darwin-arm64 tcpListen backlog is SOMAXCONN 128")
      (assert (= (backlogIn (sysNet/unixListenFn (libc/darwinArm64Facts)) "ul.backlog") 128) "darwin-arm64 unixListen backlog is SOMAXCONN 128")
      (assert (= (backlogIn (sysNet/tcpListenFn (libc/linuxX8664Facts)) "tl.backlog") 4096) "linux-x86_64 tcpListen backlog is SOMAXCONN 4096")
      (assert (= (backlogIn (sysNet/unixListenFn (libc/linuxAarch64Facts)) "ul.backlog") 4096) "linux-aarch64 unixListen backlog is SOMAXCONN 4096")
      true)

fn clashSource -> String
  (lines (list
    "(module netClash :x [main] :i [])"
    ""
    "fn sysNetTcpListen p: Int64 -> Int64"
    "  (+ p 1)"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (str (sysNetTcpListen 1)))"
    "      (println (mt (tcpListen -1) ((ok _) \"ok\") ((err e) e)))"
    "      (ok 0))"))

fn diagCodes res: (Result rt/Routed (List ty/IrDiag)) -> (List String)
  (mt res
    ((ok _) (list))
    ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn namedCount externs: (List ty/SsaExtern) name: String -> Int64
  (listLength (filter (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) externs))

fn withExtern m: ty/SsaModule e: ty/SsaExtern -> ty/SsaModule
  (ty/ssaModule m.name m.strings m.types m.records (listAppend m.externs (list e)) m.globals m.functions)

fn withString m: ty/SsaModule s: String -> ty/SsaModule
  (ty/ssaModule m.name (listAppend m.strings (list s)) m.types m.records m.externs m.globals m.functions)

fn ! testRouteModule -> Bool
  (let [(facts (libc/darwinArm64Facts))
        (close (listHead (filter (fn [(e ty/SsaExtern)] -> Bool (= e.name "close")) (sysNet/sysNetExterns facts))))]
    (mt (low/lowerSource (sixSource))
      ((err ds) (do (assert false (str "netSix lowers: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
      ((ok m)
        (do (assert (some? close) "sysNetExterns declares close")
            (mt (rt/routeModule facts m)
              ((err _) (assert false "netSix routes"))
              ((ok r) (let [(out r.result)]
                        (do (assert (= (listLength out.strings) (+ (listLength m.strings) 1)) "io: is appended to a pool without it")
                            (assert (= (listGet out.strings (listLength m.strings)) (some "io:")) "the appended pool string is io:")
                            (assert (not (rt/routes? out)) "a routed module has no routed builtin call left")
                            (mt (rt/routeModule facts out)
                              ((err _) (assert false "a routed module routes again"))
                              ((ok again) (assert (and (= again.result out) (listEmpty? again.internal)) "a module calling no routed builtin comes back unchanged, adding nothing")))))))
            (mt (rt/routeModule facts (withString m "io:"))
              ((err _) (assert false "netSix with io: in its pool routes"))
              ((ok r) (assert (= (listLength r.result.strings) (+ (listLength m.strings) 1)) "io: already in the pool is reused, not appended")))
            (mt close
              ((none) false)
              ((some c)
                (do (mt (rt/routeModule facts (withExtern m c))
                      ((err _) (assert false "netSix declaring sysNet's close extern routes"))
                      ((ok r) (assert (= (namedCount r.result.externs "close") 1) "an own extern identical to an added one is declared once")))
                    (assert (= (diagCodes (rt/routeModule facts (withExtern m (ty/ssaExtern "close" 1)))) (list "ERR_LLVM_SYSROUTE_EXTERN")) "an own close extern with another signature is ERR_LLVM_SYSROUTE_EXTERN")
                    true)))
            (mt (low/lowerSource (clashSource))
              ((err ds) (assert false (str "netClash lowers: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))))
              ((ok c) (assert (= (diagCodes (rt/routeModule facts c)) (list "ERR_LLVM_SYSROUTE_NAME")) "a module function named sysNetTcpListen is ERR_LLVM_SYSROUTE_NAME")))
            true))))

fn ! testNativeEntries work: String -> Bool
  (mt (low/lowerSource (sixSource))
    ((err ds) (do (assert false (str "netSix lowers: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
    ((ok m)
      (do (mt (llvm/emitLlvmProgram m "main")
            ((err ds) (assert false (str "netSix emitLlvmProgram: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))))
            ((ok text)
              (do (assert (stringContains? text "asl_rt_builtin_sysNet") "pure emitLlvmProgram calls the C sysNet table")
                  (assert (not (stringContains? text "@sysNetTcpListen(")) "pure emitLlvmProgram adds no sysNet function")
                  (map (fn [(n String)] -> Bool (do (assert (not (stringContains? text (str "sysRoute$2E" n "("))) (str "pure emitLlvmProgram adds no " n " wrapper")) true)) (routedNames))
                  (assert (not (stringContains? text "@__error(")) "pure emitLlvmProgram reads no darwin __error")
                  (assert (ok? (fileWrite (str work "/netSixPure.ll") text)) "netSixPure.ll written")
                  (linkBinWith work "netSixPure" (list (str work "/netSixPure.ll")) (str (lib) " asl/host/out/libaslhost.a"))
                  (assert (= (sh (str work "/netSixPure")).stdout (lines (map (fn [(i Int64)] -> String (hostConst "EINVAL")) (range 0 6))))
                          "the unrouted netSix prints the C table's EINVAL for each call"))))
          (assert (= (rt/tripleOf "Linux" "x86_64") "linux-x86_64") "tripleOf Linux x86_64")
          (assert (= (rt/tripleOf "Linux" "aarch64") "linux-aarch64") "tripleOf Linux aarch64")
          (assert (= (rt/tripleOf "Darwin" "arm64") "darwin-arm64") "tripleOf Darwin arm64")
          (assert (= (rt/tripleOf "Darwin" "x86_64") "") "tripleOf Darwin x86_64 is no libc.asl triple")
          (assert (= (optionMap (fn [(f libc/TripleFacts)] -> String f.triple) (rt/routeFactsFor "darwin-arm64")) (some "darwin-arm64")) "routeFactsFor darwin-arm64 is its verified row")
          (assert (= (optionMap (fn [(f libc/TripleFacts)] -> String f.triple) (rt/routeFactsFor "linux-x86_64")) (some "linux-x86_64")) "routeFactsFor linux-x86_64 is its measured row (SYSLINUX)")
          (assert (= (optionMap (fn [(f libc/TripleFacts)] -> String f.triple) (rt/routeFactsFor "linux-aarch64")) (some "linux-aarch64")) "routeFactsFor linux-aarch64 is its measured row (SYSLINUX)")
          (assert (not (some? (rt/routeFactsFor ""))) "routeFactsFor an unknown host is none")
          (mt (platformInfo)
            ((err e) (assert false (str "platformInfo: " e)))
            ((ok p) (assert (= (rt/tripleOf p.os p.machine) (hostTriple)) (str "tripleOf platformInfo equals uname's triple " (hostTriple)))))
          (mt (llvm/emitLlvmProgramNative! m "main")
            ((err ds) (assert false (str "netSix emitLlvmProgramNative!: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))))
            ((ok text)
              (if (some? (rt/routeFactsFor (hostTriple)))
                (checkIr (str "netSix native " (hostTriple)) text)
                (do (assert (and (stringContains? text "asl_rt_builtin_sysNet") (not (stringContains? text "@sysNetTcpListen(")))
                            (str "netSix native on unverified " (hostTriple) " keeps the C sysNet table"))
                    true))))
          true)))


fn ki dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI64) (ty/opConst (ty/constInt n)))

fn ki32 dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI32) (ty/opConst (ty/constInt n)))

fn kbox dest: String n: Int64 -> (List ty/SsaInstr)
  (list (ki (str dest ".raw") n) (ty/ssaInstr dest (ty/tyVal) (ty/opBox (str dest ".raw"))))

fn bi dest: String name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opBuiltin name args))

fn pi dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opPrim name args))

fn ci dest: String t: ty/SsaTy callee: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opCall callee args))

fn fieldOf dest: String v: String i: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opVariantField v i))

fn fdOf prefix: String box: String -> (List ty/SsaInstr)
  (list (ty/ssaInstr (str prefix ".i64") (ty/tyI64) (ty/opUnbox box))
        (pi (str prefix ".i32") (ty/tyI32) "rawNarrowI32" (list (str prefix ".i64"))))

fn blk label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn okOr scrutinee: String okLabel: String errLabel: String -> ty/SsaTerm
  (ty/termSwitch scrutinee "Result" (list (ty/ssaCase "ok" (ty/ssaEdge okLabel (list))) (ty/ssaCase "err" (ty/ssaEdge errLabel (list)))) (none))

fn branchTo cond: String yes: String no: String -> ty/SsaTerm
  (ty/termBranch cond (ty/ssaEdge yes (list)) (ty/ssaEdge no (list)))

fn exitWith label: String code: Int64 -> ty/SsaBlock
  (blk label (list (ki (str label ".code") code)) (ty/termReturn (str label ".code")))

fn handoffExterns -> (List ty/SsaExtern)
  (list (ty/ssaExternTyped "fork" (list) (ty/tyI32))
        (ty/ssaExternTyped "waitpid" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))
        (ty/ssaExternTyped "read" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64))
        (ty/ssaExternTyped "write" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64))
        (ty/ssaExternTyped "close" (list (ty/tyI32)) (ty/tyI32))
        (ty/ssaExternTyped "malloc" (list (ty/tyI64)) (ty/tyPtr)))

fn handoffRun -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (list
      (blk "entry" (list (bi "sp" "unixSocketPair" (list))) (okOr "sp" "spOk" "e210"))
      (blk "spOk"
        (listAppend (list (fieldOf "pairV" "sp" 0) (fieldOf "aBox" "pairV" 0) (fieldOf "bBox" "pairV" 1))
          (listAppend (fdOf "a" "aBox")
            (listAppend (fdOf "b" "bBox")
              (list (ci "pid" (ty/tyI32) "fork" (list)) (ki32 "z32" 0) (pi "forkFailed" (ty/tyI1) "rawLtI32" (list "pid" "z32"))))))
        (branchTo "forkFailed" "e211" "forked"))
      (blk "forked" (list (pi "isChild" (ty/tyI1) "rawEqI32" (list "pid" "z32"))) (branchTo "isChild" "child" "parent"))
      (blk "child" (list (ci "closeA" (ty/tyI32) "close" (list "a.i32")) (bi "got" "sockRecvFd" (list "bBox"))) (okOr "got" "childGot" "e220"))
      (blk "childGot" (list (fieldOf "lfdBox" "got" 0) (bi "acc" "sockAccept" (list "lfdBox"))) (okOr "acc" "childAccepted" "e221"))
      (blk "childAccepted"
        (listAppend (cons (fieldOf "afdBox" "acc" 0) (fdOf "afd" "afdBox"))
          (list (ki "one" 1) (ci "outBuf" (ty/tyPtr) "malloc" (list "one")) (ki "z64" 0) (ki32 "letterA" 65)
                (pi "putA" (ty/tyI1) "rawStoreI8" (list "outBuf" "z64" "letterA"))
                (ci "wrote" (ty/tyI64) "write" (list "afd.i32" "outBuf" "one"))
                (pi "writeShort" (ty/tyI1) "ltInt" (list "wrote" "one"))))
        (branchTo "writeShort" "e222" "childDone"))
      (exitWith "childDone" 0)
      (blk "parent"
        (list (ci "closeB" (ty/tyI32) "close" (list "b.i32")) (ty/ssaInstr "path" (ty/tyVal) (ty/opConst (ty/constStr 0)))
              (bi "listened" "unixListen" (list "path")))
        (okOr "listened" "parentListening" "e230"))
      (blk "parentListening" (list (fieldOf "lBox" "listened" 0) (bi "sent" "sockSendFd" (list "aBox" "lBox"))) (okOr "sent" "parentSent" "e231"))
      (blk "parentSent"
        (listAppend (fdOf "l" "lBox")
          (list (fieldOf "sentBox" "sent" 0) (ty/ssaInstr "sent.i64" (ty/tyI64) (ty/opUnbox "sentBox"))
                (pi "sentSame" (ty/tyI1) "eqInt" (list "sent.i64" "l.i64"))))
        (branchTo "sentSame" "parentClose" "e232"))
      (blk "parentClose"
        (list (ci "closeL" (ty/tyI32) "close" (list "l.i32")) (ci "closeA2" (ty/tyI32) "close" (list "a.i32"))
              (bi "conn" "unixConnect" (list "path")))
        (okOr "conn" "parentConnected" "e233"))
      (blk "parentConnected"
        (listAppend (cons (fieldOf "cfdBox" "conn" 0) (fdOf "cfd" "cfdBox"))
          (list (ki "pOne" 1) (ci "inBuf" (ty/tyPtr) "malloc" (list "pOne"))
                (ci "readN" (ty/tyI64) "read" (list "cfd.i32" "inBuf" "pOne"))
                (pi "readShort" (ty/tyI1) "ltInt" (list "readN" "pOne"))))
        (branchTo "readShort" "e234" "parentRead"))
      (blk "parentRead"
        (list (ki "pZ64" 0) (pi "byte32" (ty/tyI32) "rawLoadI8" (list "inBuf" "pZ64")) (pi "byte" (ty/tyI64) "rawWidenI32" (list "byte32"))
              (ki "four" 4) (ci "status" (ty/tyPtr) "malloc" (list "four"))
              (ci "waited" (ty/tyI32) "waitpid" (list "pid" "status" "z32"))
              (pi "waitFailed" (ty/tyI1) "rawNeI32" (list "waited" "pid")))
        (branchTo "waitFailed" "e235" "parentWaited"))
      (blk "parentWaited"
        (list (pi "st" (ty/tyI32) "rawLoadI32" (list "status" "pZ64")) (pi "childOk" (ty/tyI1) "rawEqI32" (list "st" "z32")))
        (branchTo "childOk" "done" "e236"))
      (blk "done" (list) (ty/termReturn "byte"))
      (exitWith "e210" 210) (exitWith "e211" 211) (exitWith "e220" 220) (exitWith "e221" 221) (exitWith "e222" 222)
      (exitWith "e230" 230) (exitWith "e231" 231) (exitWith "e232" 232) (exitWith "e233" 233) (exitWith "e234" 234)
      (exitWith "e235" 235) (exitWith "e236" 236)))

fn programTypes -> (List ty/SsaTypeDecl)
  (list (ty/ssaTypeDecl "Result" (list (ty/ssaVariant "ok" 1) (ty/ssaVariant "err" 1)))
        (ty/ssaTypeDecl "Pair" (list (ty/ssaVariant "pair" 2))))

fn handoffModule path: String -> ty/SsaModule
  (ty/ssaModule "fdHandoff" (list path) (programTypes) (list) (handoffExterns) (list) (list (handoffRun)))

fn printRes label: String v: String -> ty/SsaInstr
  (bi label "println" (list v))

fn fdErrorsRun -> ty/SsaFunction
  (ty/ssaFunction "run" (list) (list) (ty/tyI64)
    (list
      (blk "entry"
        (listAppend (kbox "minus1" -1)
          (listAppend (kbox "zero" 0)
            (listAppend (kbox "big" 2147483648)
              (list (ty/ssaInstr "x" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                    (bi "r1" "sockRecvFd" (list "minus1")) (printRes "p1" "r1")
                    (bi "r2" "sockRecvFd" (list "big")) (printRes "p2" "r2")
                    (bi "r3" "sockSendFd" (list "minus1" "zero")) (printRes "p3" "r3")
                    (bi "r4" "sockSendFd" (list "zero" "x")) (printRes "p4" "r4")
                    (bi "sp" "unixSocketPair" (list))))))
        (okOr "sp" "paired" "failed"))
      (blk "paired"
        (listAppend (list (fieldOf "pairV" "sp" 0) (fieldOf "aBox" "pairV" 0) (fieldOf "bBox" "pairV" 1))
          (listAppend (fdOf "a" "aBox")
            (listAppend (fdOf "b" "bBox")
              (list (ci "closeA" (ty/tyI32) "close" (list "a.i32"))
                    (bi "r5" "sockRecvFd" (list "bBox")) (printRes "p5" "r5")
                    (ci "closeB" (ty/tyI32) "close" (list "b.i32"))
                    (bi "r6" "sockSendFd" (list "bBox" "zero")) (printRes "p6" "r6")
                    (ki "exit0" 0)))))
        (ty/termReturn "exit0"))
      (exitWith "failed" 1)))

fn fdErrorsModule -> ty/SsaModule
  (ty/ssaModule "fdErrors" (list "x") (programTypes) (list) (list (ty/ssaExternTyped "close" (list (ty/tyI32)) (ty/tyI32))) (list) (list (fdErrorsRun)))

fn withConst facts: libc/TripleFacts name: String delta: Int64 -> libc/TripleFacts
  (libc/TripleFacts :triple facts.triple :verified facts.verified :errnoAccessor facts.errnoAccessor
    :consts (listAppend facts.consts (list (pair name (+ (optionOr (libc/libcConst facts name) 0) delta))))
    :variadic facts.variadic :structs facts.structs)

fn ! emitRun work: String name: String facts: libc/TripleFacts m: ty/SsaModule -> String
  (mt (llvm/emitLlvmProgramFor facts m "run")
    ((err ds) (do (assert false (str name ": emitLlvmProgramFor: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; "))) ""))
    ((ok text) (do (assert (ok? (fileWrite (str work "/" name ".ll") text)) (str name ".ll written")) text)))

fn ! runGuarded bin: String -> ProcessOutput
  (sh (str "(" bin " & p=$!; (sleep 20; kill -9 $p 2>/dev/null) & w=$!; wait $p; rc=$?; kill $w 2>/dev/null; exit $rc)"))

fn ! testFdHandoff work: String -> Bool
  (let [(facts (hostFacts))
        (sockPath (str work "/fd.sock"))
        (ll (emitRun work "fdHandoff" facts (handoffModule sockPath)))
        (_ (do (assert (not (stringContains? ll "asl_rt_builtin_sysNet")) "fdHandoff: emitted IR has no asl_rt_builtin_sysNet")
               (map (fn [(n String)] -> Bool (do (assert (stringContains? ll (wrapperDef n)) (str "fdHandoff: IR defines the " n " wrapper internal")) true)) (list "unixSocketPair" "sockSendFd" "sockRecvFd"))
               (assert (stringContains? ll "@sendmsg(") "fdHandoff: IR calls sendmsg")
               (assert (stringContains? ll "@recvmsg(") "fdHandoff: IR calls recvmsg")))
        (_ (linkBin work "fdHandoff" (list (str work "/fdHandoff.ll"))))
        (ran (runGuarded (str work "/fdHandoff")))
        (_ (assert (= ran.exitCode 65) (str "fdHandoff: the child accepts on the passed listener and the parent reads its A (exit 65), got " ran.exitCode " " ran.stderr)))
        (errLl (emitRun work "fdErrors" facts (fdErrorsModule)))
        (_ (linkBin work "fdErrors" (list (str work "/fdErrors.ll"))))
        (errs (runGuarded (str work "/fdErrors")))
        (inval (str "(err \"" (hostConst "EINVAL") "\")"))
        (want (lines (list inval inval inval inval (str "(err \"" (hostConst "EBADMSG") "\")") (str "(err \"" (hostConst "EBADF") "\")"))))
        (_ (assert (= errs.stdout want) (str "fdErrors prints the wrappers' err shapes: " errs.stdout " stderr " errs.stderr)))
        (_ (assert (= errs.exitCode 0) (str "fdErrors exits 0, got " errs.exitCode)))
        (mutantPath (str work "/fdMutant.sock"))
        (_ (emitRun work "fdMutant" (withConst facts "SCM_RIGHTS" 1) (handoffModule mutantPath)))
        (_ (linkBin work "fdMutant" (list (str work "/fdMutant.ll"))))
        (mutant (runGuarded (str work "/fdMutant")))
        (_ (assert (not (= mutant.exitCode 65)) (str "fdMutant: SCM_RIGHTS + 1 passes no descriptor, so no A arrives; exit " mutant.exitCode)))
        (refused (diagCodes (rt/routeModule (withConst facts "CMSG_DATA_OFFSET" 4) (handoffModule sockPath))))]
    (do (assert (= refused (list "ERR_LLVM_SYSROUTE_FACTS")) (str "a CMSG_DATA_OFFSET past CMSG_LEN_INT is refused at build: " refused))
        true))

fn ! testFdHandoffLinux work: String -> Bool
  (let [(text (emitRun work "fdHandoffLinux" (libc/linuxX8664Facts) (handoffModule "/tmp/fd.sock")))]
    (do (assert (stringContains? text "@recvmsg(") "linux-x86_64 fdHandoff calls recvmsg")
        (assert (stringContains? text "i32 1073741824") "linux-x86_64 recvmsg passes MSG_CMSG_CLOEXEC")
        (assert (stringContains? text "@__errno_location") "linux-x86_64 fdHandoff reads errno through __errno_location")
        (mt (optBin)
          ((none) (do (println "fdHandoff linux-x86_64: no opt on this host, -passes=verify skipped") true))
          ((some o) (do (assert (= (sh (str o " -passes=verify -disable-output " work "/fdHandoffLinux.ll")).exitCode 0) "linux-x86_64 fdHandoff IR verifies") true)))))

fn rowOf facts: libc/TripleFacts structName: String field: String -> Int64
  (mt (libc/pairFind facts.structs structName)
    ((none) -1)
    ((some sf) (optionOr (libc/structFieldOffset sf field) -1)))

fn constOf facts: libc/TripleFacts name: String -> Int64
  (optionOr (libc/libcConst facts name) -1)

fn sendRawInstrs facts: libc/TripleFacts p: String sock: String fds: (List String) cmsgLen: Int64 controlLen: Int64 -> (List ty/SsaInstr)
  (let [(msgSize (optionOr (libc/structSize facts "msghdr") 0))
        (iov msgSize)
        (ctl (+ msgSize 16))
        (dataByte (+ ctl 32))
        (total (+ dataByte 8))
        (dataOff (constOf facts "CMSG_DATA_OFFSET"))
        (st (fn [(name String) (prim String) (off Int64) (v String)] -> (List ty/SsaInstr)
              (list (ki (str p "." name "Off") off) (pi (str p "." name "St") (ty/tyI1) prim (list (str p ".buf") (str p "." name "Off") v)))))]
    (listAppend
      (list (ki (str p ".total") total) (ci (str p ".buf") (ty/tyPtr) "malloc" (list (str p ".total"))) (ki (str p ".z") 0)
            (pi (str p ".base") (ty/tyI64) "rawPtrToInt" (list (str p ".buf")))
            (ki (str p ".dataC") dataByte) (pi (str p ".dataAddr") (ty/tyI64) "addInt" (list (str p ".base") (str p ".dataC")))
            (ki (str p ".iovC") iov) (pi (str p ".iovAddr") (ty/tyI64) "addInt" (list (str p ".base") (str p ".iovC")))
            (ki (str p ".ctlC") ctl) (pi (str p ".ctlAddr") (ty/tyI64) "addInt" (list (str p ".base") (str p ".ctlC")))
            (ki (str p ".one") 1) (ki32 (str p ".one32") 1) (ki32 (str p ".ctlLen") controlLen) (ki32 (str p ".cmsgLen") cmsgLen)
            (ki32 (str p ".level") (constOf facts "SOL_SOCKET")) (ki32 (str p ".type") (constOf facts "SCM_RIGHTS")) (ki32 (str p ".flags") 0))
      (listAppend (fold (fn [(acc (List ty/SsaInstr)) (i Int64)] -> (List ty/SsaInstr) (listAppend acc (st (str "z" i) "rawStoreI64" (* i 8) (str p ".z")))) (list) (range 0 (/ total 8)))
        (listAppend
          (listAppend (st "iovBase" "rawStoreI64" (+ iov (rowOf facts "iovec" "iov_base")) (str p ".dataAddr"))
            (listAppend (st "iovLen" "rawStoreI64" (+ iov (rowOf facts "iovec" "iov_len")) (str p ".one"))
              (listAppend (st "msgIov" "rawStoreI64" (rowOf facts "msghdr" "msg_iov") (str p ".iovAddr"))
                (listAppend (st "msgIovlen" "rawStoreI32" (rowOf facts "msghdr" "msg_iovlen") (str p ".one32"))
                  (listAppend (st "msgControl" "rawStoreI64" (rowOf facts "msghdr" "msg_control") (str p ".ctlAddr"))
                    (listAppend (st "msgControllen" "rawStoreI32" (rowOf facts "msghdr" "msg_controllen") (str p ".ctlLen"))
                      (listAppend (st "cmsgLen" "rawStoreI32" (+ ctl (rowOf facts "cmsghdr" "cmsg_len")) (str p ".cmsgLen"))
                        (listAppend (st "cmsgLevel" "rawStoreI32" (+ ctl (rowOf facts "cmsghdr" "cmsg_level")) (str p ".level"))
                          (st "cmsgType" "rawStoreI32" (+ ctl (rowOf facts "cmsghdr" "cmsg_type")) (str p ".type"))))))))))
          (listAppend (fold (fn [(acc (List ty/SsaInstr)) (i Int64)] -> (List ty/SsaInstr) (listAppend acc (st (str "fd" i) "rawStoreI32" (+ ctl (+ dataOff (* i 4))) (optionOr (listGet fds i) "")))) (list) (range 0 (listLength fds)))
            (list (ci (str p ".n") (ty/tyI64) "sendmsg" (list sock (str p ".buf") (str p ".flags")))
                  (ty/ssaInstr (str p ".nBox") (ty/tyVal) (ty/opBox (str p ".n")))
                  (printRes (str p ".printed") (str p ".nBox"))))))))

fn fdEdgesRun facts: libc/TripleFacts -> ty/SsaFunction
  (let [(dataOff (constOf facts "CMSG_DATA_OFFSET"))
        (twoLen (+ dataOff 8))
        (aligned (- (constOf facts "CMSG_SPACE_INT") (constOf facts "CMSG_LEN_INT")))
        (twoSpace (if (= aligned 0) twoLen (* (/ (+ twoLen 7) 8) 8)))]
    (ty/ssaFunction "run" (list) (list) (ty/tyI64)
      (list
        (blk "entry" (list (bi "ch" "unixSocketPair" (list))) (okOr "ch" "chOk" "failed"))
        (blk "chOk"
          (listAppend (list (fieldOf "chV" "ch" 0) (fieldOf "aBox" "chV" 0) (fieldOf "bBox" "chV" 1) (bi "pass" "unixSocketPair" (list)))
            (listAppend (fdOf "a" "aBox") (fdOf "b" "bBox")))
          (okOr "pass" "passOk" "failed"))
        (blk "passOk"
          (list (fieldOf "passV" "pass" 0) (fieldOf "xBox" "passV" 0) (fieldOf "yBox" "passV" 1)
                (bi "sent" "sockSendFd" (list "aBox" "xBox")) (bi "got" "sockRecvFd" (list "bBox")))
          (okOr "got" "gotOk" "failed"))
        (blk "gotOk"
          (listAppend (cons (fieldOf "rBox" "got" 0) (fdOf "r" "rBox"))
            (listAppend (fdOf "x" "xBox")
              (listAppend (fdOf "y" "yBox")
                (listAppend
                  (list (ki32 "getfd" (constOf facts "F_GETFD")) (ci "fdFlags" (ty/tyI32) "fcntl" (list "r.i32" "getfd"))
                        (ki32 "cloexecBit" (constOf facts "FD_CLOEXEC")) (pi "cloexec" (ty/tyI32) "rawAndI32" (list "fdFlags" "cloexecBit"))
                        (pi "cloexec64" (ty/tyI64) "rawWidenI32" (list "cloexec")) (ty/ssaInstr "cloexecBox" (ty/tyVal) (ty/opBox "cloexec64"))
                        (printRes "p1" "cloexecBox"))
                  (listAppend (sendRawInstrs facts "two" "a.i32" (list "x.i32" "y.i32") twoLen twoSpace)
                    (listAppend (list (bi "cut" "sockRecvFd" (list "bBox")) (printRes "p2" "cut"))
                      (listAppend (sendRawInstrs facts "none" "a.i32" (list) dataOff dataOff)
                        (list (bi "empty" "sockRecvFd" (list "bBox")) (printRes "p3" "empty") (ki "exit0" 0)))))))))
          (ty/termReturn "exit0"))
        (exitWith "failed" 1))))

fn fdEdgesModule facts: libc/TripleFacts -> ty/SsaModule
  (ty/ssaModule "fdEdges" (list) (programTypes) (list)
    (list (ty/ssaExternTyped "malloc" (list (ty/tyI64)) (ty/tyPtr))
          (ty/ssaExternTyped "sendmsg" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI64))
          (ty/ssaExternVariadic "fcntl" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32)))
    (list) (list (fdEdgesRun facts)))

fn ! testFdEdges work: String -> Bool
  (let [(facts (hostFacts))
        (_ (emitRun work "fdEdges" facts (fdEdgesModule facts)))
        (_ (linkBin work "fdEdges" (list (str work "/fdEdges.ll"))))
        (ran (runGuarded (str work "/fdEdges")))
        (want (lines (list "1" "1" (str "(err \"" (hostConst "EMSGSIZE") "\")") "1" (str "(err \"" (hostConst "EBADMSG") "\")"))))]
    (do (assert (= (optionOr (listGet (stringSplit ran.stdout "\n") 0) "") "1") (str "fdEdges: a received descriptor has FD_CLOEXEC set: " ran.stdout))
        (assert (= (optionOr (listGet (stringSplit ran.stdout "\n") 2) "") (str "(err \"" (hostConst "EMSGSIZE") "\")")) (str "fdEdges: two fds into one int of control data is MSG_CTRUNC, io:EMSGSIZE: " ran.stdout))
        (assert (= (optionOr (listGet (stringSplit ran.stdout "\n") 4) "") (str "(err \"" (hostConst "EBADMSG") "\")")) (str "fdEdges: SCM_RIGHTS with no int is io:EBADMSG: " ran.stdout))
        (assert (= ran.stdout want) (str "fdEdges prints " ran.stdout " stderr " ran.stderr))
        (assert (= ran.exitCode 0) (str "fdEdges exits 0, got " ran.exitCode))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testBacklog)
        (testRouteModule)
        (testEcho work)
        (testErrors work)
        (testTwoModules work)
        (testLinuxRouting work)
        (testNativeEntries work)
        (testFdHandoff work)
        (testFdHandoffLinux work)
        (testFdEdges work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
