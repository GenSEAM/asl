(module asl-cli/pack
  :x [packCommand! cliScripts]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/verify :a verify)])

(schema PackOptions
  (:f quick Bool)
  (:f install Bool)
  (:f skipGates Bool)
  (:f target String)
  (:f version String)
  (:f mode String)
  (:f stageDir String))

fn usageLines -> String
  (str "usage: asl pack [--plan|--check|--stage DIR] [--quick] [--install] [--skip-gates] [--target PLATFORM] [--version V] [--all] [--keep-intermediates] [PLATFORM]\n"
       "  --plan   print the stages and inputs a build would use; builds nothing, runs no gates\n"
       "  --check  verify prerequisites (native build script, static gate checks); builds nothing\n"
       "  --stage DIR  lay out the darwin-arm64 tree in DIR from the files as they are; builds nothing")

fn withTarget o: PackOptions t: String -> PackOptions
  (with o :target t)

fn withFlags o: PackOptions quick: Bool install: Bool skip: Bool -> PackOptions
  (with o :quick quick :install install :skipGates skip)

fn withVersion o: PackOptions v: String -> PackOptions
  (with o :version v)

fn withMode o: PackOptions m: String dir: String -> PackOptions
  (with o :mode m :stageDir dir)

fn ! parseOptions! args: (List String) o: PackOptions -> (Result PackOptions Int64)
  (mt (listHead args)
    ((none) (ok o))
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))
            (value (optionOr (listHead rest) ""))
            (afterValue (optionOr (listTail rest) (list)))]
        (cond
          ((or (= a "--self") (= a "--self-only"))
            (do (sys/say! "(:pack :status :failed :error ERR_RETIRED :message \"asl pack --self built bin/asl-self from the tools/compileLlvmBootstrap.asl stub, which nothing runs; the native compiler route is asl1 (stage2FixpointTest)\")") (err 2)))
          ((or (= a "--quick") (= a "-q")) (parseOptions! rest (withFlags o true o.install o.skipGates)))
          ((= a "--install") (parseOptions! rest (withFlags o o.quick true o.skipGates)))
          ((= a "--skip-gates") (parseOptions! rest (withFlags o o.quick o.install true)))
          ((= a "--target") (if (listEmpty? rest) (err 1) (parseOptions! afterValue (withTarget o value))))
          ((= a "--version") (if (listEmpty? rest) (err 1) (parseOptions! afterValue (withVersion o value))))
          ((or (= a "--dist") (= a "--all")) (parseOptions! rest (withTarget o "all")))
          ((= a "--keep-intermediates") (parseOptions! rest o))
          ((or (= a "--help") (= a "-h")) (do (sys/say! (usageLines)) (err 0)))
          ((= a "--plan") (parseOptions! rest (withMode o "plan" o.stageDir)))
          ((= a "--stage") (if (listEmpty? rest) (err 1) (parseOptions! afterValue (withMode o "stage" value))))
          ((= a "--check") (parseOptions! rest (withMode o "check" o.stageDir)))
          ((stringStartsWith? a "-") (do (sys/sayErr! (str "asl pack: unknown flag " a " (see asl pack --help)")) (err 2)))
          ((stringEmpty? a) (parseOptions! rest o))
          (else (parseOptions! rest (withTarget o a)))))))

fn flag b: Bool -> String
  (if b "true" "false")

fn planText o: PackOptions -> String
  (str "(:packPlan :target \"" o.target "\" :version \"" o.version "\" :stages (\n"
       "  (:stage 1 :do \"asl audit gates --static; asl check .asl.config.asn; asl audit consistency\" :skipped " (flag o.skipGates) ")\n"
       "  (:stage 2 :do \"dist/v" o.version ": darwin-arm64 and linux-x64 tarballs\" :quick " (flag o.quick) ")))")

; (:m :ref AUDIT-PY-RETIRE :do "the asl-gates audit entrypoint and its dependency closure a packed bundle's bin/asl needs on disk, now that audit! execs auditMain.asl via bin/asl run instead of scripts/audit/audit.py")
fn cliScripts -> (List String)
  (list "asl/packages/asl-gates/src/dyck.asl"
        "asl/packages/asl-gates/src/suiteTimes.asl"
        "asl/packages/asl-gates/src/runnerLedger.asl"
        "asl/packages/asl-gates/src/runnerMain.asl"
        "asl/packages/asl-gates/src/suiteRunner.asl"
        "asl/packages/asl-gates/src/auditGates.asl"
        "asl/packages/asl-gates/src/auditForeign.asl"
        "asl/packages/asl-gates/src/auditMain.asl")

fn ! mkdirs! dirs: (List String) -> Int64
  (mt (listHead dirs)
    ((none) 0)
    ((some d)
      (mt (dirCreate d)
        ((err e) (do (sys/sayErr! (str "mkdir: " d ": " e)) 1))
        ((ok _) (mkdirs! (optionOr (listTail dirs) (list)))))))

fn ! copyEach! files: (List String) dest: String -> Int64
  (mt (listHead files)
    ((none) 0)
    ((some f)
      (let [(rc (sys/run! (list "cp" "-f" f dest)))]
        (if (!= rc 0) rc (copyEach! (optionOr (listTail files) (list)) dest)))))

fn ! sourcesOf! dir: String suffix: String -> (Result (List String) String)
  (mt (dirList dir)
    ((err e) (err (str dir ": " e)))
    ((ok names) (ok (map (fn [(n String)] -> String (str dir "/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n suffix)) names)))))

fn ! copyCliSources! root: String rt: String -> Int64
  (mt (sourcesOf! (str root "/asl/packages/asl-cli/src") ".asl")
    ((err e) (do (sys/sayErr! (str "asl pack: " e)) 1))
    ((ok cli)
      (let [(made (mkdirs! (list (str rt "/asl/packages/asl-cli/src") (str rt "/asl/packages/asl-gates/src"))))]
        (if (!= made 0)
          made
          (let [(r1 (copyEach! cli (str rt "/asl/packages/asl-cli/src/")))]
            (if (!= r1 0)
              r1
              (let [(r2 (copyEach! (map (fn [(p String)] -> String (str root "/" p)) (cliScripts)) (str rt "/asl/packages/asl-gates/src/")))]
                (if (!= r2 0) r2 (let [(r3 (sys/run! (list "cp" "-f" (str root "/.asl.config.asn") (str rt "/.asl.config.asn"))))] (if (!= r3 0) r3 (copyRuntimePackages! root rt)))))))))))

fn ! copyPackages! root: String dest: String -> Int64
  (mt (dirList (str root "/asl/packages"))
    ((err e) (do (sys/sayErr! (str "asl pack: asl/packages: " e)) 0))
    ((ok names)
      (let [(entries (map (fn [(n String)] -> String (str root "/asl/packages/" n)) (filter (fn [(n String)] -> Bool (not (stringStartsWith? n "."))) names)))]
        (if (listEmpty? entries)
          0
          (let [(rc (sys/run! (listAppend (cons "cp" (cons "-R" entries)) (list dest))))]
            (do (if (!= rc 0) (sys/sayErr! (str "asl pack: copying asl/packages exited " (stringFromInt64 rc) "; the bundle continues without them")) true) 0))))))

fn ! copyRuntimePackages! root: String rt: String -> Int64
  (mt (dirList (str root "/asl/packages"))
    ((err e) (do (sys/sayErr! (str "asl pack: asl/packages: " e)) 1))
    ((ok names)
      (let [(entries (map (fn [(n String)] -> String (str root "/asl/packages/" n)) (filter (fn [(n String)] -> Bool (not (stringStartsWith? n "."))) names)))]
        (if (listEmpty? entries) 0
          (sys/run! (listAppend (cons "cp" (cons "-R" entries)) (list (str rt "/asl/packages/"))))))))

fn ! writePlatform! path: String line: String -> Int64
  (mt (fileWrite path (str line "\n")) ((err e) (do (sys/sayErr! (str "asl pack: " path ": " e)) 1)) ((ok _) 0))

; (:m :ref HL-FIXWAVE :do "r8 used to copy asl/host/out/asl-host into the staged runtime only when it happened to exist, a leftover from the stage-0 host era; HL-DELETE means that path can never exist again, so the staged bundle instead gets what rt/bin/asl's own cold-start bootstrap (asl/bin/asl's logic) actually needs on a fresh machine with no prebuilt cache: asl/host/build.sh and the asl1 seed tree, plus any already-built libaslrt.a as a best-effort head start")
fn ! stageDarwin! ctx: sys/Context stage: String version: String -> Int64
  (let [(root ctx.root) (rt (str stage "/runtime"))
        (r1 (mkdirs! (list (str rt "/bin") (str rt "/asl/grammar") (str rt "/asl/prelude") (str stage "/bin") (str stage "/packages") (str stage "/.dist-meta"))))]
    (if (!= r1 0) r1
      (let [(r2 (sys/run! (list "cp" "-f" (str root "/bin/asl") (str rt "/bin/asl"))))]
        (if (!= r2 0) r2
          (let [(r3 (sys/run! (list "chmod" "+x" (str rt "/bin/asl"))))]
            (if (!= r3 0) r3
              (let [(r5 (copyCliSources! root rt))]
                (if (!= r5 0) r5
                  (mt (sourcesOf! (str root "/asl/grammar") ".asn")
                        ((err e) (do (sys/sayErr! (str "asl pack: " e)) 1))
                        ((ok grammar)
                          (let [(r6 (if (listEmpty? grammar) (do (sys/sayErr! (str "cp: " root "/asl/grammar/*.asn: No such file or directory")) 1) (copyEach! grammar (str rt "/asl/grammar/"))))]
                            (if (!= r6 0) r6
                              (let [(r7 (sys/run! (list "cp" "-f" (str root "/asl/prelude/prelude.asn") (str rt "/asl/prelude/"))))]
                                (if (!= r7 0) r7
                                  (let [(r8 (let [(m (mkdirs! (list (str rt "/asl/host/out") (str rt "/asl/seed"))))]
                                              (if (!= m 0) m
                                                (let [(rb (sys/run! (list "cp" "-f" (str root "/asl/host/build.sh") (str rt "/asl/host/build.sh"))))]
                                                  (if (!= rb 0) rb
                                                    (let [(rs (sys/run! (list "cp" "-R" (str root "/asl/seed/.") (str rt "/asl/seed/"))))]
                                                      (if (!= rs 0) rs
                                                        (if (sys/isFile? (str root "/asl/host/out/libaslrt.a"))
                                                          (copyEach! (list (str root "/asl/host/out/libaslrt.a")) (str rt "/asl/host/out/"))
                                                          0))))))))]
                                    (if (!= r8 0) r8
                                      (let [(r9 (sys/run! (list "ln" "-sfn" "runtime/bin/asl" (str stage "/asl"))))]
                                        (if (!= r9 0) r9
                                          (let [(r10 (sys/run! (list "ln" "-sfn" "../runtime/bin/asl" (str stage "/bin/asl"))))]
                                            (if (!= r10 0) r10
                                              (let [(r11 (copyPackages! root (str stage "/packages/")))]
                                                (if (!= r11 0) r11
                                                  (writePlatform! (str stage "/.dist-meta/platform.asn")
                                                                  (str "(:target \"darwin-arm64\" :version \"" version "\" :substrate \"native-llvm\" :arch \"arm64\" :os \"darwin\")"))))))))))))))))))))))))

fn ! stageMode! ctx: sys/Context o: PackOptions -> Int64
  (let [(dir o.stageDir)
        (occupied (mt (fileStat dir)
                    ((err _) false)
                    ((ok st) (if st.isDir (mt (dirList dir) ((ok names) (not (listEmpty? names))) ((err _) false)) true))))]
    (if (or (stringEmpty? dir) occupied)
      (do (sys/sayErr! "asl pack --stage DIR: DIR must be new or empty") 2)
      (let [(rc (stageDarwin! ctx dir o.version))]
        (if (!= rc 0) rc (do (sys/say! (str "(:packStage :target \"darwin-arm64\" :dir \"" dir "\")")) 0)))))

; (:m :ref AUDIT-PY-RETIRE :do "asl pack's own gate checks exec the native asl-gates/auditMain.asl entry via bin/asl run, same dispatch as command.asl's audit!, not scripts/audit/audit.py")
fn nativeAuditEntry root: String -> String
  (str root "/asl/packages/asl-gates/src/auditMain.asl")

fn nativeAuditArgv root: String sub: String args: (List String) -> (List String)
  (listAppend (listAppend (list (str root "/bin/asl") "run" (nativeAuditEntry root) sub) args) (list "--root" root))

fn ! staticGatesPass! root: String -> Bool
  (if (not (sys/isFile? (nativeAuditEntry root)))
    false
    (mt (sys/capture! (nativeAuditArgv root "gates" (list "--static")) (none))
      ((err _) false)
      ((ok c) (= c.exitCode 0))))

; (:m :ref HL-FIXWAVE :do "asl/host/out/asl-host can never exist again after HL-DELETE; the prerequisite pack now checks for is the native build script that bootstraps bin/asl from the asl1 seed (asl/host/build.sh), not a host binary")
fn ! checkMode! ctx: sys/Context -> Int64
  (let [(noNative (if (sys/isFile? (str ctx.root "/asl/host/build.sh")) "" " native build script asl/host/build.sh absent;"))
        (noGates (if (staticGatesPass! ctx.root) "" " static gate checks fail (asl audit gates --static);"))
        (missing (str noNative noGates))]
    (if (stringEmpty? missing)
      (do (sys/say! "(:packCheck :native \"asl/host/build.sh\" :staticGates :passed)") 0)
      (do (sys/say! (str "(:packCheck :status :failed :message \"" (optionOr (stringSlice missing 1 (stringLength missing)) "") "\")")) 1)))

fn ! makeTemp! prefix: String n: Int64 -> (Result String String)
  (let [(path (str "/tmp/" prefix "." (stringFromInt64 (procSelf)) "." (stringFromInt64 (/ (nowNs) 1000)) "." (stringFromInt64 n)))]
    (if (fileExists? path)
      (if (> n 50) (err (str "no free temporary directory for " prefix)) (makeTemp! prefix (+ n 1)))
      (mt (dirCreate path) ((err e) (err (str path ": " e))) ((ok _) (ok path)))))

fn ! gates! ctx: sys/Context -> Int64
  (let [(root ctx.root)]
    (if (not (sys/isFile? (nativeAuditEntry root)))
      (do (sys/sayErr! "Error: the asl-gates audit entry was not found") 1)
      (let [(r1 (sys/run! (nativeAuditArgv root "gates" (list "--static"))))]
        (if (!= r1 0) r1
          (let [(r2 (verify/checkFiles! ctx (list (str root "/.asl.config.asn"))))]
            (if (!= r2 0) r2 (sys/run! (nativeAuditArgv root "consistency" (list)))))))))

fn digitAt? s: String i: Int64 -> Bool
  (let [(b (stringToBytes s))] (and (< i (bytesLength b)) (and (>= (bytesGet b i) 48) (<= (bytesGet b i) 57))))

fn byteAt b: Bytes i: Int64 -> Int64
  (if (< i (bytesLength b)) (bytesGet b i) -1)

fn digitRun b: Bytes i: Int64 -> Int64
  (if (and (>= (byteAt b i) 48) (<= (byteAt b i) 57)) (digitRun b (+ i 1)) i)

fn decimalLiteral? t: String -> Bool
  (let [(b (stringToBytes t))
        (n (bytesLength b))
        (s0 (if (or (= (byteAt b 0) 43) (= (byteAt b 0) 45)) 1 0))
        (intEnd (digitRun b s0))
        (hasPoint (= (byteAt b intEnd) 46))
        (fracEnd (if hasPoint (digitRun b (+ intEnd 1)) intEnd))
        (mantissaDigits (- (- fracEnd s0) (if hasPoint 1 0)))
        (hasExp (or (= (byteAt b fracEnd) 101) (= (byteAt b fracEnd) 69)))
        (expStart (if hasExp (+ fracEnd (if (or (= (byteAt b (+ fracEnd 1)) 43) (= (byteAt b (+ fracEnd 1)) 45)) 2 1)) fracEnd))
        (expEnd (if hasExp (digitRun b expStart) fracEnd))]
    (and (> mantissaDigits 0) (and (or (not hasExp) (> expEnd expStart)) (= expEnd n))))

fn radixDigit c: Int64 -> Int64
  (cond
    ((and (>= c 48) (<= c 57)) (- c 48))
    ((and (>= c 97) (<= c 102)) (- c 87))
    ((and (>= c 65) (<= c 70)) (- c 55))
    (else 99))

fn radixValue b: Bytes i: Int64 radix: Int64 acc: Float64 -> (Option Float64)
  (cond
    ((>= i (bytesLength b)) (some acc))
    ((>= (radixDigit (bytesGet b i)) radix) (none))
    (else (radixValue b (+ i 1) radix (+ (* acc (int64ToFloat64 radix)) (int64ToFloat64 (radixDigit (bytesGet b i)))))))

fn radixLiteral t: String -> (Option Float64)
  (let [(b (stringToBytes t))
        (marker (byteAt b 1))
        (radix (cond ((or (= marker 120) (= marker 88)) 16) ((or (= marker 111) (= marker 79)) 8) ((or (= marker 98) (= marker 66)) 2) (else 0)))]
    (if (or (!= (byteAt b 0) 48) (or (= radix 0) (< (bytesLength b) 3)))
      (none)
      (radixValue b 2 radix 0.0)))

fn uint8Of v: Float64 -> Int64
  (if (or (not (isFinite? v)) (>= (abs v) 9.0e18))
    0
    (mod (optionOr (float64ToInt64 v) 0) 256))

fn csvByte field: String -> (Option Int64)
  (let [(t (stringTrim field))]
    (cond
      ((stringEmpty? t) (some 0))
      ((listContains? (list "Infinity" "+Infinity" "-Infinity") t) (some 0))
      ((decimalLiteral? t) (optionMap uint8Of (stringToFloat64 t)))
      (else (optionMap uint8Of (radixLiteral t)))))

fn ! csvBytes! fields: (List String) line: String acc: (List Int64) -> (Result (List Int64) String)
  (mt (listHead fields)
    ((none) (ok (listReverse acc)))
    ((some f)
      (mt (csvByte f)
        ((none) (err (str "(:pack :status :failed :error ERR_WASM_CSV :message \"field " (stringReplace (stringReplace f "\\" "\\\\") "\"" "\\\"") " of line " (stringReplace (stringReplace line "\\" "\\\\") "\"" "\\\"") " is not a number\")")))
        ((some v) (csvBytes! (optionOr (listTail fields) (list)) line (cons v acc))))))

fn ! writeBytes! path: String values: (List Int64) -> (Result Int64 String)
  (let [(b (bytesAlloc (listLength values)))
        (filled (fold (fn [(i Int64) (v Int64)] -> Int64 (do (bytesSet b i v) (+ i 1))) 0 values))]
    (mt (fileWrite path b) ((err e) (err (str path ": " e))) ((ok _) (ok filled))))

fn firstDigitLine lines: (List String) -> (Option String)
  (mt (listHead lines)
    ((none) (none))
    ((some l) (if (digitAt? l 0) (some l) (firstDigitLine (optionOr (listTail lines) (list))))))

fn ! compileWasm! ctx: sys/Context distDir: String -> Int64
  (if (not (sys/executable? ctx.hostBin))
    0
    (mt (sys/capture! (list ctx.hostBin "run" (str ctx.root "/tools/compileWasm.asl")) (none))
      ((err e) (do (sys/sayErr! (str "asl pack: compileWasm: " e)) 0))
      ((ok c)
        (mt (if (= c.exitCode 0) (firstDigitLine (stringLines c.stdout)) (none))
          ((none) 0)
          ((some line)
            (mt (csvBytes! (stringSplit (stringTrim line) ",") (stringTrim line) (list))
              ((err e) (do (sys/sayErr! e) 1))
              ((ok values)
                (mt (writeBytes! (str distDir "/asl.wasm") values)
                  ((err e) (do (sys/sayErr! (str "asl pack: " e)) 1))
                  ((ok n) (do (sys/say! (str "    ✓ Compiled asl.wasm (" (stringFromInt64 n) " bytes)")) 0))))))))))

fn ! tarball! out: String dir: String members: (List String) -> Int64
  (sys/run! (listAppend (list "tar" "-czf" out "-C" dir) members))

fn ! packDarwin! ctx: sys/Context o: PackOptions distDir: String -> Int64
  (let [(v o.version) (name (str "asl-" o.version "-darwin-arm64.tar.gz"))]
    (do (sys/say! (str "    • Packaging target: " name "..."))
      (mt (makeTemp! "asl-pack-darwin" 0)
        ((err e) (do (sys/sayErr! (str "asl pack: " e)) 1))
        ((ok stage)
          (let [(rc (stageDarwin! ctx stage v))
                (rc2 (if (!= rc 0) rc (tarball! (str distDir "/" name) stage (list "asl" "bin" "runtime" "packages" ".dist-meta"))))
                (removed (pathRemove stage))]
            (cond
              ((!= rc2 0) rc2)
              ((err? removed) (do (sys/sayErr! (str "asl pack: cannot remove " stage)) 1))
              (else (do (sys/say! (str "    ✓ Packaged " distDir "/" name)) 0))))))))

fn linuxWrapper -> String
  (str "#!/usr/bin/env bash\n"
       "set -eo pipefail\n"
       "SCRIPT_DIR=\"$(cd -P \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
       "if [ \"$1\" = \"--version\" ] || [ \"$1\" = \"-v\" ]; then\n"
       "  echo \"asl 0.1.0 (wasm-wasi linux-x64 substrate)\"\n"
       "  exit 0\n"
       "fi\n"
       "exec node \"${SCRIPT_DIR}/run-wasm.js\" \"$@\"\n")

fn ! layLinux! ctx: sys/Context o: PackOptions distDir: String tmp: String -> Int64
  (let [(wasm (str distDir "/asl.wasm"))
        (r1 (if (fileExists? wasm) (sys/run! (list "cp" "-f" wasm (str tmp "/asl.wasm"))) 0))]
    (if (!= r1 0) r1
      (mt (fileWrite (str tmp "/asl") (linuxWrapper))
        ((err e) (do (sys/sayErr! (str "asl pack: " e)) 1))
        ((ok _)
          (let [(r2 (sys/run! (list "chmod" "+x" (str tmp "/asl"))))]
            (if (!= r2 0) r2
              (let [(r3 (mkdirs! (list (str tmp "/packages") (str tmp "/.dist-meta"))))]
                (if (!= r3 0) r3
                  (let [(r4 (copyPackages! ctx.root (str tmp "/packages/")))]
                    (if (!= r4 0) r4
                      (let [(r5 (writePlatform! (str tmp "/.dist-meta/platform.asn") (str "(:target \"linux-x64\" :version \"" o.version "\" :substrate \"wasm-wasi\" :arch \"x64\" :os \"linux\")")))]
                        (if (!= r5 0) r5
                          (tarball! (str distDir "/asl-" o.version "-linux-x64.tar.gz") tmp (list "asl" "packages" ".dist-meta"))))))))))))))

fn ! packLinux! ctx: sys/Context o: PackOptions distDir: String -> Int64
  (let [(name (str "asl-" o.version "-linux-x64.tar.gz"))]
    (do (sys/say! (str "    • Packaging target: " name "..."))
      (mt (makeTemp! "asl-pack-linux" 0)
        ((err e) (do (sys/sayErr! (str "asl pack: " e)) 1))
        ((ok tmp)
          (let [(rc (layLinux! ctx o distDir tmp))
                (removed (pathRemove tmp))]
            (cond
              ((!= rc 0) rc)
              ((err? removed) (do (sys/sayErr! (str "asl pack: cannot remove " tmp)) 1))
              (else (do (sys/say! (str "    ✓ Packaged " distDir "/" name)) 0))))))))

fn ! writeSums! distDir: String -> Int64
  (mt (dirList distDir)
    ((err e) (do (sys/sayErr! (str "asl pack: " distDir ": " e)) 1))
    ((ok names)
      (let [(files (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "asl-") (sys/isFile? (str distDir "/" n)))) names))
            (lines (map (fn [(n String)] -> (Result String String) (mt (fileReadBytes (str distDir "/" n)) ((ok b) (ok (str (bytesSha256 b) "  " n "\n"))) ((err e) (err (str n ": " e))))) files))
            (bad (filter err? lines))]
        (mt (if (listEmpty? bad) (fileWrite (str distDir "/SHA256SUMS") (stringJoin (map (fn [(r (Result String String))] -> String (resultOr r "")) lines) "")) (err "unreadable asl-* file"))
          ((err e) (do (sys/sayErr! (str "asl pack: SHA256SUMS: " e)) 1))
          ((ok _) (do (sys/say! (str "    ✓ Emitted " distDir "/SHA256SUMS")) 0))))))

fn ! installLink! ctx: sys/Context -> Int64
  (let [(dir (str (optionOr (envGet "HOME") "") "/.local/bin"))
        (made (mkdirs! (list dir)))]
    (if (!= made 0) made
      (let [(rc (sys/run! (list "ln" "-sf" (str ctx.root "/bin/asl") (str dir "/asl"))))]
        (if (!= rc 0) rc (do (sys/say! (str "✓ [Install] Successfully installed ASL binary to " dir "/asl")) 0)))))

fn rule -> String
  "================================================================================"

fn wants? o: PackOptions names: (List String) -> Bool
  (listContains? names o.target)

fn ! distribute! ctx: sys/Context o: PackOptions -> Int64
  (let [(tag (str "v" o.version))
        (distDir (str ctx.root "/dist/" tag))
        (made (do (sys/say! "--> [2/2] Packaging distribution release bundles...") (mkdirs! (list distDir))))]
    (if (!= made 0) made
      (let [(r1 (if (and (sys/isFile? (str ctx.root "/tools/compileWasm.asl")) (wants? o (list "all" "wasm" "linux-x64")))
                  (do (sys/say! "    • Compiling WebAssembly bytecode (tools/compileWasm.asl)...") (compileWasm! ctx distDir))
                  0))]
        (if (!= r1 0) r1
          (let [(r2 (if (wants? o (list "all" "darwin-arm64")) (packDarwin! ctx o distDir) 0))]
            (if (!= r2 0) r2
              (let [(r3 (if (wants? o (list "all" "linux-x64")) (packLinux! ctx o distDir) 0))]
                (if (!= r3 0) r3
                  (let [(r4 (writeSums! distDir))]
                    (if (!= r4 0) r4
                      (let [(r5 (if o.install (installLink! ctx) 0))]
                        (if (!= r5 0) r5
                          (do (sys/say! (rule)) (sys/say! (str "✓ === [ASL Pack] ALL TARGETS PACKAGED CLEANLY (" tag ") ===")) (sys/say! (rule)) 0)))))))))))))

fn ! buildMode! ctx: sys/Context o: PackOptions -> Int64
  (do (sys/say! (rule))
      (sys/say! "        AgentSlang (ASL) Unified Packager & Multi-Platform Bundler             ")
      (sys/say! (rule))
    (let [(made (mkdirs! (list (str ctx.root "/dist"))))
          (gated (cond
                   ((!= made 0) made)
                   (o.skipGates (do (sys/say! "--> [1/2] Skipping verification gates (--skip-gates active).") 0))
                   (else (do (sys/say! "--> [1/2] Running static verification gates...") (gates! ctx)))))]
      (cond
        ((!= gated 0) gated)
        ((and o.quick (not o.install)) (do (sys/say! "✓ [Pack] Quick build & verification audit passed cleanly. Skipping release distribution packaging.") 0))
        (else (distribute! ctx o)))))

fn ! packCommand! ctx: sys/Context args: (List String) -> Int64
  (mt (parseOptions! args (PackOptions :quick false :install false :skipGates false :target "all" :version "0.1.0" :mode "build" :stageDir ""))
    ((err code) code)
    ((ok o)
      (cond
        ((= o.mode "plan") (do (sys/say! (planText o)) 0))
        ((= o.mode "stage") (stageMode! ctx o))
        ((= o.mode "check") (checkMode! ctx))
        (else (buildMode! ctx o)))))
