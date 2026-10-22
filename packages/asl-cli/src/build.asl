(module asl-cli/build
  :x [buildCommand!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/asl1Cache :a cache) (asl/packages/asl-cli/src/verify :a verify) (asl/packages/asl-cli/src/nativeBuild :a nb) (asl/packages/asl-cli/src/rcConfig :a rcc)])

fn usage -> String
  "usage: asl build FILE [-o OUT]"

fn ! fail text: String code: Int64 -> Int64
  (do (sys/sayErr! text) code)

fn findClang! name: String -> (Option String)
  (if (stringContains? name "/")
    (if (and (sys/isFile? name) (sys/executable? name)) (some name) (none))
    (sys/onPath! name))

fn parseArgs! args: (List String) target: String out: String -> (Result (Pair String String) Int64)
  (match (listHead args)
    ((none) (ok (pair target out)))
    ((some a)
      (let [(more (optionOr (listTail args) (list)))]
        (cond
          ((= a "-o")
            (if (listEmpty? more)
              (err (fail "(:build :status :failed :error ERR_USAGE :message \"-o requires an output path\")" 2))
              (parseArgs! (optionOr (listTail more) (list)) target (optionOr (listHead more) ""))))
          ((stringStartsWith? a "-") (err (fail (str "(:build :status :failed :error ERR_UNKNOWN_ARG :message \"unknown option " a "\")") 2)))
          ((stringEmpty? target) (parseArgs! more a out))
          (else (err (fail (str "(:build :status :failed :error ERR_USAGE :message \"unexpected argument " a "\")") 2)))))))

fn ! drop! path: String -> Bool
  (if (not (fileExists? path))
    true
    (match (pathRemove path) ((ok _) true) ((err e) (do (sys/sayErr! (str "asl build: cannot remove " path ": " e)) false))))

fn defaultOut target: String -> String
  (if (stringEndsWith? target ".asl") (optionOr (stringSlice target 0 (- (stringLength target) 4)) target) (str target ".out"))

fn ! tempDir! base: String n: Int64 -> (Result String String)
  (let [(path (str base "/aslBuild" (stringFromInt64 (procSelf)) (stringFromInt64 (mod (/ (nowNs) 1000) 1000000)) (stringFromInt64 n)))]
    (if (fileExists? path)
      (if (> n 50) (err "no free name") (tempDir! base (+ n 1)))
      (match (dirCreate path) ((err e) (err e)) ((ok _) (ok path)))))

fn rcArgs mode: String -> (List String)
  (if (= mode "0") (list) (list "--rc" mode))

fn ! interpretAsl1! ctx: sys/Context target: String ll: String mode: String -> Int64
  (sys/run! (listAppend (list "nice" "-n" "15" ctx.hostBin "run" (str ctx.root "/asl/packages/asl-compiler/src/asl1.asl") "build" target "-o" ll) (rcArgs mode)))

fn ! compileLl! ctx: sys/Context clang: String lib: String target: String ll: String mode: String -> Int64
  (if (not (sys/isFile? (str ctx.root "/asl/packages/asl-compiler/src/asl1.asl")))
    (interpretAsl1! ctx target ll mode)
    (match (cache/nativeAsl1! ctx lib clang)
      ((ok native) (sys/run! (listAppend (list "nice" "-n" "15" native "build" target "-o" ll) (rcArgs mode))))
      ((err reason)
        (do
          (sys/sayErr! (str "NATIVE-ASL1-FALLBACK " reason))
          (interpretAsl1! ctx target ll mode)))))

; (:m :ref RC-DEFAULT :do "variant runtimes live in the toolchain cache, shared with rcTest; no env override")
fn variantCacheDir ctx: sys/Context -> String
  (str ctx.root "/.asl/cache/rcRuntime")

fn ! clangVersion! clang: String -> (Result String String)
  (match (sys/capture! (list clang "--version") (none))
    ((err e) (err e))
    ((ok c) (if (= c.exitCode 0) (ok (stringTrim (optionOr (listHead (stringLines c.stdout)) ""))) (err (str clang " --version failed: " c.stderr)))))

; (:m :ref HL-FIX3 :do ":native (:rc :asan) (formerly ASL_NATIVE_SANITIZE=1) wires bin/asl build's link step to nativeBuild's own ASan runtime instead of the plain libaslrt.a: reuses the already-cached native asl1 compiler (cache/nativeAsl1!) to build nativeBuild/asanRuntime!'s rtAbi/rtFloor/gcRoute objects into a distinct libaslrt-asan.a under a dedicated cache dir, keyed by clang version + those 3 sources, never colliding with the plain cache")
; (:m :ref RC-CONFIG :do "one cached variant runtime per mode: asan for :rc :asan, the untraced runtime for :rc :notrace")
fn ! variantLib! ctx: sys/Context clang: String lib: String variant: String -> (Result String String)
  (match (cache/nativeAsl1! ctx lib clang)
    ((err e) (err (str variant " runtime needs a native asl1 compiler: " e)))
    ((ok native)
      (match (clangVersion! clang)
        ((err e) (err e))
        ((ok version)
          (let [(cacheDir (variantCacheDir ctx)) (_ (dirCreate (str ctx.root "/.asl/cache")))]
            (match (dirCreate cacheDir)
              ((err e) (err (str "cannot create " cacheDir ": " e)))
              ((ok _)
                (let [(b (nb/Build :root ctx.root :cache cacheDir :tmp cacheDir :lib lib :base "" :clangVersion version :owner ""
                                    :deadlineNs (+ (monotonicNs) 1800000000000) :maxDesc 32))]
                  (if (= variant "notrace") (nb/notraceRuntime! b native (str ctx.root "/asl/packages")) (nb/asanRuntime! b native (str ctx.root "/asl/packages")))))))))))

fn ! effectiveLibAndFlags! ctx: sys/Context clang: String lib: String mode: String -> (Result (Pair String (List String)) String)
  (cond
    ((= mode "asan")
      (match (variantLib! ctx clang lib "asan")
        ((err e) (err e))
        ((ok asanLib) (ok (pair asanLib (nb/sanitizeFlags))))))
    ((= mode "notrace")
      (match (variantLib! ctx clang lib "notrace")
        ((err e) (err e))
        ((ok ntLib) (ok (pair ntLib (list "-O2"))))))
    (else (ok (pair lib (list "-O2")))))

fn ! linkAttempt! clang: String flags: (List String) libs: (List String) ll: String part: String -> (Result sys/Captured String)
  (sys/capture! (listAppend (list "nice" "-n" "15" clang) (listAppend flags (listAppend (list "-Wno-override-module" "-x" "ir" ll "-x" "none") (listAppend libs (list "-lm" "-o" part))))) (none))

fn ! link! ctx: sys/Context clang: String lib: String target: String out: String tmp: String mode: String -> Int64
  (let [(ll (str tmp "/out.ll"))
        (part (str out ".part" (stringFromInt64 (procSelf))))
        (compiled (compileLl! ctx clang lib target ll mode))]
    (cond
      ((or (!= compiled 0) (not (sys/isFile? ll)))
        (do (drop! ll) (drop! tmp) (if (!= compiled 0) compiled 1)))
      (else
        (let [(outDir (let [(d (sys/parentOf out))] (if (stringEmpty? d) (if (stringStartsWith? out "/") "/" ".") d)))]
          (match (dirCreate outDir)
            ((err _) (do (drop! ll) (drop! tmp) (fail (str "ERR_BUILD: cannot create " outDir) 1)))
            ((ok _)
              (match (effectiveLibAndFlags! ctx clang lib mode)
                ((err e) (do (drop! ll) (drop! tmp) (fail (str "ERR_BUILD: runtime variant: " e) 1)))
                ((ok libFlags)
                  (let [(effLib (pairFirst libFlags))
                        (flags (pairSecond libFlags))
                        (linkRes (linkAttempt! clang flags (list effLib) ll part))
                        (removed (drop! tmp))]
                    (cond
                      ((err? linkRes) (do (drop! part) (fail (match linkRes ((err e) e) ((ok _) "")) 1)))
                      ((or (!= (match linkRes ((ok c) c.exitCode) ((err _) 1)) 0) (not (sys/isFile? part)))
                        (do (drop! part) (fail (str "ERR_BUILD: clang link failed for " target ": " (match linkRes ((ok c) c.stderr) ((err _) ""))) (match linkRes ((ok c) (if (!= c.exitCode 0) c.exitCode 1)) ((err _) 1)))))
                      ((not removed) (do (drop! part) (fail (str "ERR_BUILD: cannot remove " tmp) 1)))
                      (else
                        (match (pathRename part out)
                          ((err _) (do (drop! part) (fail (str "ERR_BUILD: cannot write " out) 1)))
                          ((ok _) (do (sys/say! (str "built " out)) 0))))))))))))))

fn ! buildFile! ctx: sys/Context clang: String lib: String target: String given: String -> Int64
  (let [(out (if (stringEmpty? given) (defaultOut target) given))
        (checked (verify/nativeCheckPaths! (list target)))]
    (if (!= checked 0)
      checked
      (match (tempDir! (let [(t (optionOr (envGet "TMPDIR") ""))] (if (stringEmpty? t) "/tmp" (if (stringEndsWith? t "/") (optionOr (stringSlice t 0 (- (stringLength t) 1)) t) t))) 0)
        ((err _) (fail "ERR_BUILD: cannot create temporary directory" 1))
        ((ok tmp) (match (rcc/rcModeIn! (sys/parentOf (resultOr (realPath target) target)) "notrace")
                    ((err e) (do (drop! tmp) (fail e 1)))
                    ((ok mode) (link! ctx clang lib target out tmp mode)))))))

fn ! buildCommand! ctx: sys/Context args: (List String) -> Int64
  (let [(first (optionOr (listHead args) ""))
        (clangName (let [(c (optionOr (envGet "CLANG") ""))] (if (stringEmpty? c) "clang" c)))
        (lib (let [(configured (optionOr (envGet "ASL_HOST_LIBRARY") ""))] (if (stringEmpty? configured) (str ctx.root "/asl/host/out/libaslrt.a") configured)))]
    (cond
      ((or (= first "-h") (= first "--help")) (do (sys/say! (usage)) 0))
      ((listEmpty? args) (fail (usage) 2))
      (else
        (match (findClang! clangName)
          ((none) (fail (str "ERR_BUILD: clang not found: " clangName "; install clang or set CLANG") 1))
          ((some clang)
            (if (not (sys/isFile? lib))
              (fail (str "ERR_BUILD: libaslrt.a not found at " lib "; build it with sh asl/host/build.sh") 1)
              (match (parseArgs! args "" "")
                ((err code) code)
                ((ok parsed)
                  (let [(target (pairFirst parsed))]
                    (cond
                      ((stringEmpty? target) (fail (usage) 2))
                      ((not (sys/isFile? target)) (fail (str "(:build :status :failed :error ERR_NO_FILE :message \"file not found: " target "\")") 1))
                      (else (buildFile! ctx clang lib target (pairSecond parsed)))))))))))))
