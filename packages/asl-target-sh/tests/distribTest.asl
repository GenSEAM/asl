(module asl-target-sh/tests/distribTest
  :x [runTests]
  :i [(asl-target-sh/distrib :a dist)])

fn bytesFromInts ints: (List Int64) -> Bytes
  (let [(n (listLength ints))
        (b (bytesAlloc n))]
    (do (fold (fn [idx val] (do (bytesSet b idx val) (+ idx 1))) 0 ints)
        b))

fn checkRunnableBytes! bs: Bytes os: String arch: String -> Bool
  (let [(tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/distTest." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
    (mt (fileWrite tmp bs)
      ((err _) false)
      ((ok _)
        (do (fileChmod tmp 493)
            (let [(res (dist/isRunnable! tmp os arch))]
              (do (pathRemove tmp) res))))))

fn testDistribTargetsAndHeaders -> Bool
  (let [(targets (dist/distribTargetsList))
        (hdrSh (dist/generateInstallShHeader))
        (ps1Code (dist/generateInstallPs1 "0.1.0"))
        (cmdCode (dist/generateAslCmd "0.1.0"))]
    (assert (listContains? targets "posix-shell") "Targets must include posix-shell")
    (assert (listContains? targets "windows-powershell") "Targets must include windows-powershell")
    (assert (listContains? targets "windows-cmd") "Targets must include windows-cmd")
    (assert (stringContains? hdrSh "Single Source of Truth (SSOT)") "POSIX header must declare SSOT")
    (assert (stringContains? ps1Code "Single Source of Truth (SSOT)") "PowerShell code must declare SSOT")
    (assert (stringContains? ps1Code "$Version = \"0.1.0\"") "PowerShell code must embed version")
    (assert (stringContains? cmdCode "asl 0.1.0 (wasm-wasi windows-x64 substrate)") "CMD wrapper must embed version")
    (assert (stringContains? cmdCode "where node >nul 2>&1") "CMD wrapper must check node/wasm runtimes")
    (refute (stringContains? hdrSh "asl.cmd") "POSIX header must not mention asl.cmd")
    true)

fn testBinaryInspectionAndRunnable! -> Bool
  (let [
        (machoArm64 (bytesFromInts (list 207 250 237 254  12 0 0 1  0 0 0 0  2 0 0 0)))
        (machoX64 (bytesFromInts (list 207 250 237 254  7 0 0 1  3 0 0 0  2 0 0 0)))
        (machoFat (bytesFromInts (list
          202 254 186 190  0 0 0 2
          1 0 0 7  0 0 0 3  0 0 16 0  0 0 16 0  0 0 0 14
          1 0 0 12  0 0 0 2  0 0 32 0  0 0 16 0  0 0 0 14)))
        (elfArm64LE (bytesFromInts (list 127 69 76 70  2 1 1 0  0 0 0 0  0 0 0 0  2 0 183 0)))
        (elfArm64BE (bytesFromInts (list 127 69 76 70  2 2 1 0  0 0 0 0  0 0 0 0  0 2 0 183)))
        (elfX64LE (bytesFromInts (list 127 69 76 70  2 1 1 0  0 0 0 0  0 0 0 0  2 0 62 0)))
        (elfX64BE (bytesFromInts (list 127 69 76 70  2 2 1 0  0 0 0 0  0 0 0 0  0 2 0 62)))
        (shebang (bytesFromInts (list 35 33 47 98 105 110 47 115 104 10)))
        (pe (bytesFromInts (list 77 90 144 0  3 0 0 0  4 0 0 0  255 255 0 0)))
        (truncEmpty (bytesFromInts (list)))
        (trunc1 (bytesFromInts (list 127)))
        (trunc3 (bytesFromInts (list 127 69 76)))
        (truncElf4 (bytesFromInts (list 127 69 76 70)))
        (truncMacho4 (bytesFromInts (list 207 250 237 254)))
        (truncFat8 (bytesFromInts (list 202 254 186 190  0 0 0 2)))]

    (assert (dist/isMachO machoArm64) "isMachO accepts Mach-O arm64")
    (assert (dist/isMachO machoX64) "isMachO accepts Mach-O x86_64")
    (assert (dist/isMachO machoFat) "isMachO accepts Mach-O universal fat binary")
    (assert (dist/isMachO truncMacho4) "isMachO accepts 4-byte Mach-O magic")
    (refute (dist/isMachO elfArm64LE) "isMachO rejects ELF aarch64 LE")
    (refute (dist/isMachO elfX64LE) "isMachO rejects ELF x86_64 LE")
    (refute (dist/isMachO shebang) "isMachO rejects shebang")
    (refute (dist/isMachO pe) "isMachO rejects PE")
    (refute (dist/isMachO trunc3) "isMachO rejects 3-byte input")
    (refute (dist/isMachO truncEmpty) "isMachO rejects empty input")

    (assert (dist/isElf elfArm64LE) "isElf accepts ELF aarch64 LE")
    (assert (dist/isElf elfArm64BE) "isElf accepts ELF aarch64 BE")
    (assert (dist/isElf elfX64LE) "isElf accepts ELF x86_64 LE")
    (assert (dist/isElf elfX64BE) "isElf accepts ELF x86_64 BE")
    (assert (dist/isElf truncElf4) "isElf accepts 4-byte ELF magic")
    (refute (dist/isElf machoArm64) "isElf rejects Mach-O arm64")
    (refute (dist/isElf machoX64) "isElf rejects Mach-O x86_64")
    (refute (dist/isElf machoFat) "isElf rejects Mach-O fat")
    (refute (dist/isElf shebang) "isElf rejects shebang")
    (refute (dist/isElf pe) "isElf rejects PE")
    (refute (dist/isElf trunc3) "isElf rejects 3-byte input")
    (refute (dist/isElf truncEmpty) "isElf rejects empty input")

    (assert (dist/isScript shebang) "isScript accepts shebang")
    (refute (dist/isScript machoArm64) "isScript rejects Mach-O arm64")
    (refute (dist/isScript elfX64LE) "isScript rejects ELF x86_64")
    (refute (dist/isScript pe) "isScript rejects PE")
    (refute (dist/isScript trunc1) "isScript rejects 1-byte input")
    (refute (dist/isScript truncEmpty) "isScript rejects empty input")

    (assert (checkRunnableBytes! shebang "darwin" "arm64") "shebang runnable on darwin arm64")
    (assert (checkRunnableBytes! shebang "darwin" "x86_64") "shebang runnable on darwin x86_64")
    (assert (checkRunnableBytes! shebang "linux" "arm64") "shebang runnable on linux arm64")
    (assert (checkRunnableBytes! shebang "linux" "x86_64") "shebang runnable on linux x86_64")

    (assert (checkRunnableBytes! machoArm64 "darwin" "arm64") "Mach-O arm64 runnable on darwin arm64")
    (refute (checkRunnableBytes! machoArm64 "darwin" "x86_64") "Mach-O arm64 not runnable on darwin x86_64")
    (refute (checkRunnableBytes! machoArm64 "linux" "arm64") "Mach-O arm64 not runnable on linux arm64")
    (refute (checkRunnableBytes! machoArm64 "linux" "x86_64") "Mach-O arm64 not runnable on linux x86_64")

    (refute (checkRunnableBytes! machoX64 "darwin" "arm64") "Mach-O x86_64 not runnable on darwin arm64")
    (assert (checkRunnableBytes! machoX64 "darwin" "x86_64") "Mach-O x86_64 runnable on darwin x86_64")
    (refute (checkRunnableBytes! machoX64 "linux" "arm64") "Mach-O x86_64 not runnable on linux arm64")
    (refute (checkRunnableBytes! machoX64 "linux" "x86_64") "Mach-O x86_64 not runnable on linux x86_64")

    (assert (checkRunnableBytes! machoFat "darwin" "arm64") "Mach-O fat runnable on darwin arm64")
    (assert (checkRunnableBytes! machoFat "darwin" "x86_64") "Mach-O fat runnable on darwin x86_64")
    (refute (checkRunnableBytes! machoFat "linux" "arm64") "Mach-O fat not runnable on linux arm64")
    (refute (checkRunnableBytes! machoFat "linux" "x86_64") "Mach-O fat not runnable on linux x86_64")

    (assert (checkRunnableBytes! elfArm64LE "linux" "arm64") "ELF aarch64 LE runnable on linux arm64")
    (refute (checkRunnableBytes! elfArm64LE "linux" "x86_64") "ELF aarch64 LE not runnable on linux x86_64")
    (refute (checkRunnableBytes! elfArm64LE "darwin" "arm64") "ELF aarch64 LE not runnable on darwin arm64")
    (refute (checkRunnableBytes! elfArm64LE "darwin" "x86_64") "ELF aarch64 LE not runnable on darwin x86_64")

    (assert (checkRunnableBytes! elfArm64BE "linux" "arm64") "ELF aarch64 BE runnable on linux arm64")
    (refute (checkRunnableBytes! elfArm64BE "linux" "x86_64") "ELF aarch64 BE not runnable on linux x86_64")
    (refute (checkRunnableBytes! elfArm64BE "darwin" "arm64") "ELF aarch64 BE not runnable on darwin arm64")
    (refute (checkRunnableBytes! elfArm64BE "darwin" "x86_64") "ELF aarch64 BE not runnable on darwin x86_64")

    (refute (checkRunnableBytes! elfX64LE "linux" "arm64") "ELF x86_64 LE not runnable on linux arm64")
    (assert (checkRunnableBytes! elfX64LE "linux" "x86_64") "ELF x86_64 LE runnable on linux x86_64")
    (refute (checkRunnableBytes! elfX64LE "darwin" "arm64") "ELF x86_64 LE not runnable on darwin arm64")
    (refute (checkRunnableBytes! elfX64LE "darwin" "x86_64") "ELF x86_64 LE not runnable on darwin x86_64")

    (refute (checkRunnableBytes! elfX64BE "linux" "arm64") "ELF x86_64 BE not runnable on linux arm64")
    (assert (checkRunnableBytes! elfX64BE "linux" "x86_64") "ELF x86_64 BE runnable on linux x86_64")
    (refute (checkRunnableBytes! elfX64BE "darwin" "arm64") "ELF x86_64 BE not runnable on darwin arm64")
    (refute (checkRunnableBytes! elfX64BE "darwin" "x86_64") "ELF x86_64 BE not runnable on darwin x86_64")

    (refute (checkRunnableBytes! pe "darwin" "arm64") "PE not runnable on darwin arm64")
    (refute (checkRunnableBytes! pe "darwin" "x86_64") "PE not runnable on darwin x86_64")
    (refute (checkRunnableBytes! pe "linux" "arm64") "PE not runnable on linux arm64")
    (refute (checkRunnableBytes! pe "linux" "x86_64") "PE not runnable on linux x86_64")

    (refute (checkRunnableBytes! truncEmpty "darwin" "arm64") "empty not runnable on darwin arm64")
    (refute (checkRunnableBytes! truncEmpty "linux" "x86_64") "empty not runnable on linux x86_64")
    (refute (checkRunnableBytes! trunc1 "darwin" "arm64") "1 byte not runnable on darwin arm64")
    (refute (checkRunnableBytes! trunc3 "linux" "x86_64") "3 bytes not runnable on linux x86_64")
    (refute (checkRunnableBytes! truncElf4 "linux" "x86_64") "truncated ELF (4b) not runnable on linux x86_64")
    (refute (checkRunnableBytes! truncElf4 "linux" "arm64") "truncated ELF (4b) not runnable on linux arm64")
    (refute (checkRunnableBytes! truncMacho4 "darwin" "arm64") "truncated Mach-O (4b) not runnable on darwin arm64")
    (refute (checkRunnableBytes! truncMacho4 "darwin" "x86_64") "truncated Mach-O (4b) not runnable on darwin x86_64")
    (refute (checkRunnableBytes! truncFat8 "darwin" "arm64") "truncated fat (8b) not runnable on darwin arm64")
    (refute (checkRunnableBytes! truncFat8 "darwin" "x86_64") "truncated fat (8b) not runnable on darwin x86_64")

    (assert (= (dist/defaultRepoUrl) "https://github.com/GenSEAM/asl.git") "defaultRepoUrl must be canonical GitHub URL")
    (assert (some? (dist/prebuiltBaseUrl!)) "prebuiltBaseUrl must be some when REPO_URL is default")
    (assert (= (dist/prebuiltBaseUrl!) (some "https://github.com/GenSEAM/asl/releases/download/v0.1.0")) "prebuiltBaseUrl must match v0.1.0 releases URL")
    true)


fn resolveHost! -> String
  (let [(envHost (optionOr (envGet "ASL_HOST") ""))
        (statEnv (if (> (stringLength envHost) 0) (fileStat envHost) (err "none")))]
    (if (ok? statEnv)
      envHost
      (resultOr (pathCanonicalize "asl/host/out/asl-host")
                (resultOr (pathCanonicalize "host/out/asl-host") "asl/host/out/asl-host"))))


fn testPortableEntry! -> Bool
  (let [(sh (dist/generatePortableAsl))
        (tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/portTest." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))
        (pkgDir (str tmp "/repo"))
        (cliDir (str pkgDir "/packages/asl-cli/src"))
        (cliFile (str cliDir "/main.asl"))
        (stDry (dist/Inst :tree pkgDir :from "pipe" :tty "none" :os "linux" :arch "x86_64" :home tmp :installDir (str tmp "/bin")
                          :dry true :autoYes true :filter "" :skip true :purge false :force false :sourceDir "" :entry "" :prebuilt false :links (list) :answeredOps ""))
        (stReal (dist/Inst :tree pkgDir :from "pipe" :tty "none" :os "linux" :arch "x86_64" :home tmp :installDir (str tmp "/bin")
                           :dry false :autoYes true :filter "" :skip true :purge false :force false :sourceDir "" :entry "" :prebuilt false :links (list) :answeredOps ""))
        (cleanUp (fn [] (dist/runArgv! (list "rm" "-rf" tmp) (none) (none) 5000)))
        (cleanAndAssert (fn [cond msg] (if cond (assert cond msg) (do (cleanUp) (assert cond msg)))))
        (cleanAndRefute (fn [cond msg] (if (not cond) (refute cond msg) (do (cleanUp) (refute cond msg)))))]
    (do
      (cleanAndAssert (stringStartsWith? sh "#!/bin/sh") "generatePortableAsl must start with shebang")
      (cleanAndRefute (stringContains? sh "echo \"asl 0.1.0") "generatePortableAsl must run host for version, not hardcode echo")
      (cleanAndAssert (stringContains? sh "packages/asl-cli/src/main.asl") "generatePortableAsl must locate CLI main")
      (cleanAndAssert (stringContains? sh "asl-host") "generatePortableAsl must resolve asl-host")
      (cleanAndRefute (stringContains? sh "ls -ld") "generatePortableAsl must resolve symlinks without parsing ls -ld")
      (cleanAndAssert (stringContains? sh "readlink") "generatePortableAsl must use readlink loop")
      (cleanAndAssert (stringContains? sh "CDPATH=") "generatePortableAsl must guard cd with CDPATH=")
      (dirCreate cliDir)
      (fileWrite cliFile "(module asl-cli/main)\n")
      (cleanAndAssert (dist/isRegular! cliFile) "cliFile created")
      (let [(shDir (str pkgDir "/packages/asl-target-sh/src"))
            (shFile (str shDir "/distrib.asl"))
            (dOk (dirCreate shDir))
            (wOk (fileWrite shFile "(module mock)\n"))]
        (cleanAndAssert (dist/isRegular! shFile) "distribFile created"))
      (cleanAndAssert (some? (dist/pkgOf! pkgDir)) "pkgOf must detect temp repo root layout")
      (cleanAndRefute (some? (dist/pkgOf! (str tmp "/nonexistent_pkg"))) "pkgOf must reject empty / non-package dir")
      (let [(dryRes (dist/emitPortableEntry! pkgDir stDry))
            (expectedTarget (str pkgDir "/host/out/asl"))]
        (do
          (cleanAndAssert (= dryRes (some expectedTarget)) "emitPortableEntry dry run returns target")
          (cleanAndRefute (dist/isRegular! expectedTarget) "emitPortableEntry dry run must not write target")
          (let [(realRes (dist/emitPortableEntry! pkgDir stReal))]
            (do
              (cleanAndAssert (= realRes (some expectedTarget)) "emitPortableEntry real creates target")
              (cleanAndAssert (dist/isRegular! expectedTarget) "target file exists")
              (cleanAndAssert (dist/isRunnable! expectedTarget "linux" "x86_64") "target runnable on linux x86_64")
              (cleanAndAssert (dist/isRunnable! expectedTarget "darwin" "arm64") "target runnable on darwin arm64")
              (cleanAndAssert (= (dist/aslEntry! pkgDir "linux" "x86_64") (some expectedTarget)) "aslEntry finds portable entry on linux")
              (fileChmod expectedTarget 365)
              (cleanAndAssert (= (dist/emitPortableEntry! pkgDir stReal) (none)) "emitPortableEntry rejects failed update of existing runnable target")
              (cleanUp)
              true))))))

fn testAnswersAgainstRealCli! -> Bool
  (let [(bin (resultOr (pathCanonicalize "bin/asl") "bin/asl"))
        (home (optionOr (envGet "HOME") "/tmp"))
        (dir (optionOr (envGet "TMPDIR") "/tmp"))]
    (do
      (assert (dist/answersOp? bin "read" home dir) "probe recognizes an operation listed by the real CLI")
      (assert (not (dist/answersOp? bin "ins2DefinitelyMissing" home dir)) "probe rejects an operation absent from the real CLI registry")
      true))

fn testPortableWrapperExecution! -> Bool
  (let [(hostBin (resolveHost!))
        (tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/portGate." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))
        (pkgDir (str tmp "/repo"))
        (wrapper (str pkgDir "/host/out/asl"))
        (cliDir (str pkgDir "/packages/asl-cli/src"))
        (cliMain (str cliDir "/main.asl"))
        (shDir (str pkgDir "/packages/asl-target-sh/src"))
        (shDistrib (str shDir "/distrib.asl"))
        (testScript (str tmp "/testScript.asl"))
        (badCheck (str tmp "/badCheck.asl"))
        (goodCheck (str tmp "/goodCheck.asl"))
        (symlinkWrapper (str tmp "/symlinkAsl"))
        (cleanUp (fn [] (dist/runArgv! (list "rm" "-rf" tmp) (none) (none) 5000)))
        (env (some (list (str "ASL_HOST=" hostBin) "PATH=/bin:/usr/bin:/usr/local/bin")))
        (st (dist/Inst :tree pkgDir :from "file" :tty "none" :os "linux" :arch "x86_64" :home tmp :installDir (str tmp "/bin")
                       :dry false :autoYes true :filter "" :skip true :purge false :force false :sourceDir "" :entry "" :prebuilt false :links (list) :answeredOps ""))
        (cleanAndAssert (fn [cond msg] (if cond (assert cond msg) (do (cleanUp) (assert cond msg)))))
        (cleanAndRefute (fn [cond msg] (if (not cond) (refute cond msg) (do (cleanUp) (refute cond msg)))))]
    (do
      (dirCreate cliDir)
      (dirCreate shDir)
      (fileWrite shDistrib "(module mock/dist)\n")
      (fileWrite cliMain "(module asl-cli/main :x [main] :i [])\nfn main args: (List String) -> (Result Unit String)\n  (let [(first (optionOr (listHead args) \"\"))]\n    (cond\n      ((stringContains? first \"unsupported\") (err \"ERR_UNIMPLEMENTED\"))\n      ((stringContains? first \"unimplemented_zero\") (do (println \"ERR_UNIMPLEMENTED\") (ok ())))\n      ((stringContains? first \"not_implemented\") (do (println \"ERR_NOT_IMPLEMENTED\") (ok ())))\n      ((stringContains? first \"unknown_cmd\") (do (println \"unknown command\") (ok ())))\n      ((stringContains? first \"missing_arg\") (do (println \"ERR_MISSING_ARG\") (err \"ERR_MISSING_ARG\")))\n      (else (do (println (str \"CLI_ARGS=\" (stringJoin args \"|\"))) (ok ())))))\n")
      (fileWrite testScript "(module test/script :x [main] :i [])\nfn main args: (List String) -> (Result Unit String)\n  (do (println (str \"RUN_ARGS=\" (stringJoin args \"|\"))) (ok ()))\n")
      (fileWrite badCheck "(module bad/check")
      (fileWrite goodCheck "(module good/check)\n")

      (dist/emitPortableEntry! pkgDir st)
      (cleanAndAssert (dist/isRegular! wrapper) "wrapper file must be emitted")

      (let [(resCli (dist/runArgv! (list wrapper "echo" "hello world with spaces" "another space arg") (some tmp) env 10000))
            (outCli (mt resCli ((ok r) (str r.out r.errText)) ((err _) "")))]
        (do
          (cleanAndAssert (ok? resCli) "CLI exec wrapper invocation must succeed")
          (cleanAndAssert (stringContains? outCli "CLI_ARGS=echo|hello world with spaces|another space arg") "wrapper CLI exec must pass through arguments with spaces intact (Mutant 1 killed)")))

      (let [(resRun (dist/runArgv! (list wrapper "run" testScript "run first" "run second with spaces") (some tmp) env 10000))
            (outRun (mt resRun ((ok r) (str r.out r.errText)) ((err _) "")))]
        (do
          (cleanAndAssert (ok? resRun) "wrapper run invocation must succeed")
          (cleanAndAssert (= (mt resRun ((ok r) r.code) ((err _) 1)) 0) "wrapper run exit code must be 0")
          (cleanAndAssert (stringContains? outRun "RUN_ARGS=run first|run second with spaces") "wrapper run must pass through arguments with spaces intact (Mutant 2 killed)")))

      (let [(resBad (dist/runArgv! (list wrapper "check" badCheck) (some tmp) env 10000))
            (resGood (dist/runArgv! (list wrapper "check" goodCheck) (some tmp) env 10000))]
        (do
          (cleanAndAssert (ok? resBad) "wrapper check bad invocation must return result")
          (cleanAndAssert (!= (mt resBad ((ok r) r.code) ((err _) 0)) 0) "failing check must exit non-zero (exit code propagation)")
          (cleanAndAssert (ok? resGood) "wrapper check good invocation must return result")
          (cleanAndAssert (= (mt resGood ((ok r) r.code) ((err _) 1)) 0) "passing check must exit 0")))

      (let [(symRes (dist/runArgv! (list "ln" "-s" wrapper symlinkWrapper) (none) (none) 5000))
            (resSym (dist/runArgv! (list symlinkWrapper "run" testScript "sym pass") (some tmp) env 10000))]
        (do
          (cleanAndAssert (ok? symRes) "symlink creation must succeed")
          (cleanAndAssert (ok? resSym) "symlinked wrapper invocation must succeed")
          (cleanAndAssert (= (mt resSym ((ok r) r.code) ((err _) 1)) 0) "symlinked wrapper must exit 0")
          (cleanAndAssert (stringContains? (mt resSym ((ok r) (str r.out r.errText)) ((err _) "")) "RUN_ARGS=sym pass") "symlinked wrapper must pass arguments through")))

      (let [(resVer (dist/runArgv! (list wrapper "--version") (some tmp) env 10000))
            (outVer (mt resVer ((ok r) (str r.out r.errText)) ((err _) "")))]
        (do
          (cleanAndAssert (ok? resVer) "wrapper --version must succeed")
          (cleanAndAssert (= (mt resVer ((ok r) r.code) ((err _) 1)) 0) "wrapper --version exit code 0")
          (cleanAndAssert (stringContains? outVer "CLI_ARGS=--version") "wrapper --version must run host to invoke CLI main")))

      (let [(cloneDir (str tmp "/.asl/repo"))
            (srcDir (str tmp "/src"))
            (i1 (dist/runArgv! (list "git" "init" srcDir) (none) (none) 5000))
            (c1 (dist/runArgv! (list "git" "-C" srcDir "-c" "user.name=test" "-c" "user.email=test@test.com" "commit" "--allow-empty" "-m" "init") (none) (none) 5000))
            (cl1 (dist/runArgv! (list "git" "clone" srcDir cloneDir) (none) (none) 5000))
            (pkgSh (str cloneDir "/packages/asl-target-sh/src"))
            (pkgCli (str cloneDir "/packages/asl-cli/src"))
            (dSh (dirCreate pkgSh))
            (dCli (dirCreate pkgCli))
            (wSh (fileWrite (str pkgSh "/distrib.asl") "(module mock/sh)\n"))
            (wCli (fileWrite (str pkgCli "/main.asl") "(module mock/cli)\n"))
            (stCloneDry (dist/Inst :tree (str tmp "/empty") :from "pipe" :tty "none" :os "linux" :arch "x86_64" :home tmp :installDir (str tmp "/bin")
                                   :dry true :autoYes true :filter "" :skip true :purge false :force false :sourceDir "" :entry "" :prebuilt false :links (list) :answeredOps ""))
            (resDry (dist/stepClone! stCloneDry))
            (stCloneReal (dist/Inst :tree (str tmp "/empty") :from "pipe" :tty "none" :os "linux" :arch "x86_64" :home tmp :installDir (str tmp "/bin")
                                    :dry false :autoYes true :filter "" :skip true :purge false :force false :sourceDir "" :entry "" :prebuilt false :links (list) :answeredOps ""))
            (resReal (dist/stepClone! stCloneReal))]
        (do
          (cleanAndAssert (mt resDry ((dist/go s) (= s.entry (str cloneDir "/host/out/asl"))) ((dist/stop _) false)) "stepClone dry run must wire portable wrapper entry (Mutant 4 killed)")
          (cleanAndAssert (mt resReal ((dist/go s) (= s.entry (str cloneDir "/host/out/asl"))) ((dist/stop _) false)) "stepClone real must wire portable wrapper entry")
          (cleanAndAssert (dist/isRegular! (str cloneDir "/host/out/asl")) "stepClone real must emit wrapper to disk")

          (let [(envNoHost (some (list "PATH=/bin:/usr/bin:/usr/local/bin")))
                (hostLink (str pkgDir "/host/out/asl-host"))
                (hRes (dist/runArgv! (list "ln" "-s" hostBin hostLink) (none) (none) 5000))
                (binDir (str pkgDir "/bin"))
                (dBin (dirCreate binDir))
                (binWrapper (str binDir "/asl"))
                (cpRes (dist/runArgv! (list "cp" wrapper binWrapper) (none) (none) 5000))]
            (do
              (cleanAndAssert (ok? hRes) "host symlink creation in host/out must succeed")
              (cleanAndAssert (ok? cpRes) "wrapper copy to installed location bin/asl must succeed")

              (let [(resA (dist/runArgv! (list binWrapper "echo" "fallback host lookup" "with spaces") (some tmp) envNoHost 10000))
                    (outA (mt resA ((ok r) (str r.out r.errText)) ((err _) "")))]
                (do
                  (cleanAndAssert (ok? resA) "wrapper at installed location with ../host/out fallback must succeed")
                  (cleanAndAssert (= (mt resA ((ok r) r.code) ((err _) 1)) 0) "wrapper at installed location exit code must be 0")
                  (cleanAndAssert (stringContains? outA "CLI_ARGS=echo|fallback host lookup|with spaces") "wrapper at installed location must locate host via ../host/out fallback and pass arguments (Mutant corrupt ../host/out killed)")))

              (let [(resB (dist/runArgv! (list wrapper "echo" "here host lookup" "with spaces") (some tmp) envNoHost 10000))
                    (outB (mt resB ((ok r) (str r.out r.errText)) ((err _) "")))]
                (do
                  (cleanAndAssert (ok? resB) "wrapper next to asl-host must succeed without ASL_HOST")
                  (cleanAndAssert (= (mt resB ((ok r) r.code) ((err _) 1)) 0) "wrapper next to asl-host exit code must be 0")
                  (cleanAndAssert (stringContains? outB "CLI_ARGS=echo|here host lookup|with spaces") "wrapper must locate host via $HERE/asl-host and pass arguments (Mutant corrupt $HERE/asl-host killed)")))

              (let [(resRunNoHost (dist/runArgv! (list binWrapper "run" testScript "run no host") (some tmp) envNoHost 10000))
                    (outRunNoHost (mt resRunNoHost ((ok r) (str r.out r.errText)) ((err _) "")))
                    (resVerNoHost (dist/runArgv! (list wrapper "--version") (some tmp) envNoHost 10000))
                    (outVerNoHost (mt resVerNoHost ((ok r) (str r.out r.errText)) ((err _) "")))]
                (do
                  (cleanAndAssert (ok? resRunNoHost) "wrapper run without ASL_HOST must succeed")
                  (cleanAndAssert (= (mt resRunNoHost ((ok r) r.code) ((err _) 1)) 0) "wrapper run without ASL_HOST exit code must be 0")
                  (cleanAndAssert (stringContains? outRunNoHost "RUN_ARGS=run no host") "wrapper run must pass arguments without ASL_HOST")
                  (cleanAndAssert (ok? resVerNoHost) "wrapper --version without ASL_HOST must succeed")
                  (cleanAndAssert (= (mt resVerNoHost ((ok r) r.code) ((err _) 1)) 0) "wrapper --version without ASL_HOST exit code must be 0")
                  (cleanAndAssert (stringContains? outVerNoHost "CLI_ARGS=--version") "wrapper --version without ASL_HOST must invoke CLI main")))))
          (cleanUp)
          true))))

fn ! runTests -> Bool
  (and (testDistribTargetsAndHeaders) (and (testBinaryInspectionAndRunnable!) (and (testPortableEntry!) (and (testAnswersAgainstRealCli!) (testPortableWrapperExecution!)))))
