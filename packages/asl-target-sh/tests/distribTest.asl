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
    (match (fileWrite tmp bs)
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
      (cleanAndAssert (stringContains? sh "exec \"$HERE/../../bin/asl\" \"$@\"") "generatePortableAsl must delegate to the package's own bin/asl launcher")
      (cleanAndRefute (stringContains? sh "ASL_HOST") "generatePortableAsl must not search for a host interpreter")
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
  (let [(bin (resultOr (realPath "bin/asl") "bin/asl"))
        (home (optionOr (envGet "HOME") "/tmp"))
        (dir (optionOr (envGet "TMPDIR") "/tmp"))]
    (do
      (assert (dist/answersOp? bin "read" home dir) "probe recognizes an operation listed by the real CLI")
      (assert (not (dist/answersOp? bin "ins2DefinitelyMissing" home dir)) "probe rejects an operation absent from the real CLI registry")
      true))

; (:m :ref BASE-RED-4 :do "the portable entry now only delegates to the package's own bin/asl (HL-DELETE retired asl-host): a stub bin/asl records its arguments and exits 7 on 'fail', and the wrapper must pass arguments with spaces intact, propagate the exit code and work through a symlink")
fn testPortableWrapperExecution! -> Bool
  (let [(tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/portGate." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))
        (pkgDir (str tmp "/repo"))
        (wrapper (str pkgDir "/host/out/asl"))
        (cliDir (str pkgDir "/packages/asl-cli/src"))
        (shDir (str pkgDir "/packages/asl-target-sh/src"))
        (binDir (str pkgDir "/bin"))
        (stub (str binDir "/asl"))
        (symlinkWrapper (str tmp "/symlinkAsl"))
        (cleanUp (fn [] (dist/runArgv! (list "rm" "-rf" tmp) (none) (none) 5000)))
        (env (some (list "PATH=/bin:/usr/bin:/usr/local/bin")))
        (st (dist/Inst :tree pkgDir :from "file" :tty "none" :os "linux" :arch "x86_64" :home tmp :installDir (str tmp "/bin")
                       :dry false :autoYes true :filter "" :skip true :purge false :force false :sourceDir "" :entry "" :prebuilt false :links (list) :answeredOps ""))
        (cleanAndAssert (fn [cond msg] (if cond (assert cond msg) (do (cleanUp) (assert cond msg)))))]
    (do
      (dirCreate cliDir)
      (dirCreate shDir)
      (dirCreate binDir)
      (fileWrite (str shDir "/distrib.asl") "(module mock/dist)\n")
      (fileWrite (str cliDir "/main.asl") "(module asl-cli/main)\n")
      (fileWrite stub "#!/bin/sh\nargs=\"\"\nfor a in \"$@\"; do args=\"$args|$a\"; done\necho \"STUB_ARGS$args\"\nif [ \"${1:-}\" = fail ]; then exit 7; fi\nexit 0\n")
      (dist/runArgv! (list "chmod" "+x" stub) (none) (none) 5000)
      (dist/emitPortableEntry! pkgDir st)
      (cleanAndAssert (dist/isRegular! wrapper) "wrapper file must be emitted")
      (let [(resEcho (dist/runArgv! (list wrapper "echo" "hello world with spaces" "another space arg") (some tmp) env 10000))
            (outEcho (match resEcho ((ok r) (str r.out r.errText)) ((err _) "")))
            (resFail (dist/runArgv! (list wrapper "fail") (some tmp) env 10000))
            (symRes (dist/runArgv! (list "ln" "-s" wrapper symlinkWrapper) (none) (none) 5000))
            (resSym (dist/runArgv! (list symlinkWrapper "sym pass") (some tmp) env 10000))
            (outSym (match resSym ((ok r) (str r.out r.errText)) ((err _) "")))]
        (do
          (cleanAndAssert (ok? resEcho) "wrapper invocation must succeed")
          (cleanAndAssert (stringContains? outEcho "STUB_ARGS|echo|hello world with spaces|another space arg") "wrapper must pass arguments with spaces intact to bin/asl")
          (cleanAndAssert (= (match resFail ((ok r) r.code) ((err _) 0)) 7) "the exit code of bin/asl must propagate")
          (cleanAndAssert (ok? symRes) "symlink creation must succeed")
          (cleanAndAssert (stringContains? outSym "STUB_ARGS|sym pass") "a symlinked wrapper must resolve its own directory and reach bin/asl")
          (cleanUp)
          true))))

fn ! runTests -> Bool
  (and (testDistribTargetsAndHeaders) (and (testBinaryInspectionAndRunnable!) (and (testPortableEntry!) (and (testAnswersAgainstRealCli!) (testPortableWrapperExecution!)))))
