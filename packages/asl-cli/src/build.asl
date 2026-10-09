(module asl-cli/build
  :x [buildCommand! hostArchive?]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/asl1Cache :a cache)])

fn usage -> String
  "usage: asl build FILE [-o OUT]"

fn ! fail text: String code: Int64 -> Int64
  (do (sys/sayErr! text) code)

fn findClang! name: String -> (Option String)
  (if (stringContains? name "/")
    (if (and (sys/isFile? name) (sys/executable? name)) (some name) (none))
    (sys/onPath! name))

fn parseArgs! args: (List String) target: String out: String -> (Result (Pair String String) Int64)
  (mt (listHead args)
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
    (mt (pathRemove path) ((ok _) true) ((err e) (do (sys/sayErr! (str "asl build: cannot remove " path ": " e)) false))))

fn defaultOut target: String -> String
  (if (stringEndsWith? target ".asl") (optionOr (stringSlice target 0 (- (stringLength target) 4)) target) (str target ".out"))

fn ! tempDir! base: String n: Int64 -> (Result String String)
  (let [(path (str base "/aslBuild" (stringFromInt64 (procSelf)) (stringFromInt64 (mod (/ (nowNs) 1000) 1000000)) (stringFromInt64 n)))]
    (if (fileExists? path)
      (if (> n 50) (err "no free name") (tempDir! base (+ n 1)))
      (mt (dirCreate path) ((err e) (err e)) ((ok _) (ok path)))))

fn ! interpretAsl1! ctx: sys/Context target: String ll: String -> Int64
  (sys/run! (list "nice" "-n" "15" ctx.hostBin "run" (str ctx.root "/asl/packages/asl-compiler/src/asl1.asl") "build" target "-o" ll))

fn ! compileLl! ctx: sys/Context clang: String lib: String target: String ll: String -> Int64
  (if (not (sys/isFile? (str ctx.root "/asl/packages/asl-compiler/src/asl1.asl")))
    (interpretAsl1! ctx target ll)
    (mt (cache/nativeAsl1! ctx lib clang)
      ((ok native) (sys/run! (list "nice" "-n" "15" native "build" target "-o" ll)))
      ((err reason)
        (do
          (sys/sayErr! (str "NATIVE-ASL1-FALLBACK " reason))
          (interpretAsl1! ctx target ll)))))

fn hostLibOf lib: String -> String
  (let [(dir (sys/parentOf lib))]
    (str (if (stringEmpty? dir) "" (str dir "/")) (stringReplace (sys/baseName lib) "libaslrt" "libaslhost")))

fn hostArchive? text: String -> Bool
  (or (stringContains? text "call %Val @asl_rt_builtin_sys(")
      (or (stringContains? text "call %Val @asl_rt_builtin_sysNet(")
          (stringContains? text "call %Val @asl_rt_builtin_parallel(")))

fn ! linkLibs! lib: String ll: String -> (Result (List String) String)
  (mt (fileReadString ll)
    ((err e) (err (str "ERR_BUILD: cannot read " ll ": " e)))
    ((ok text)
      (if (not (hostArchive? text))
        (ok (list lib))
        (let [(host (hostLibOf lib))]
          (if (sys/isFile? host) (ok (list lib host)) (err (str "ERR_BUILD: the program calls an unrouted sys, socket, parMap or parFold builtin and " host " is missing; build it with sh asl/host/build.sh")))))))

fn ! link! ctx: sys/Context clang: String lib: String target: String out: String tmp: String -> Int64
  (let [(ll (str tmp "/out.ll"))
        (part (str out ".part" (stringFromInt64 (procSelf))))
        (compiled (compileLl! ctx clang lib target ll))]
    (cond
      ((or (!= compiled 0) (not (sys/isFile? ll)))
        (do (drop! ll) (drop! tmp) (if (!= compiled 0) compiled 1)))
      (else
        (let [(outDir (let [(d (sys/parentOf out))] (if (stringEmpty? d) (if (stringStartsWith? out "/") "/" ".") d)))]
          (mt (dirCreate outDir)
            ((err _) (do (drop! ll) (drop! tmp) (fail (str "ERR_BUILD: cannot create " outDir) 1)))
            ((ok _)
              (let [(libs (linkLibs! lib ll))
                    (linked (mt libs ((err _) 1) ((ok ls) (sys/runMerged! (listAppend (list "nice" "-n" "15" clang "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none") (listAppend ls (list "-lm" "-o" part)))))))
                    (removed (drop! tmp))]
                (cond
                  ((err? libs) (do (drop! part) (fail (mt libs ((err e) e) ((ok _) "")) 1)))
                  ((or (!= linked 0) (not (sys/isFile? part)))
                    (do (drop! part) (fail (str "ERR_BUILD: clang link failed for " target) (if (!= linked 0) linked 1))))
                  ((not removed) (do (drop! part) (fail (str "ERR_BUILD: cannot remove " tmp) 1)))
                  (else
                    (mt (pathRename part out)
                      ((err _) (do (drop! part) (fail (str "ERR_BUILD: cannot write " out) 1)))
                      ((ok _) (do (sys/say! (str "built " out)) 0))))))))))))

fn ! buildFile! ctx: sys/Context clang: String lib: String target: String given: String -> Int64
  (let [(out (if (stringEmpty? given) (defaultOut target) given))
        (checked (sys/run! (list ctx.hostBin "check" target)))]
    (if (!= checked 0)
      checked
      (mt (tempDir! (let [(t (optionOr (envGet "TMPDIR") ""))] (if (stringEmpty? t) "/tmp" (if (stringEndsWith? t "/") (optionOr (stringSlice t 0 (- (stringLength t) 1)) t) t))) 0)
        ((err _) (fail "ERR_BUILD: cannot create temporary directory" 1))
        ((ok tmp) (link! ctx clang lib target out tmp)))))

fn ! buildCommand! ctx: sys/Context args: (List String) -> Int64
  (let [(first (optionOr (listHead args) ""))
        (clangName (let [(c (optionOr (envGet "CLANG") ""))] (if (stringEmpty? c) "clang" c)))
        (lib (let [(configured (optionOr (envGet "ASL_HOST_LIBRARY") ""))] (if (stringEmpty? configured) (str ctx.root "/asl/host/out/libaslrt.a") configured)))]
    (cond
      ((or (= first "-h") (= first "--help")) (do (sys/say! (usage)) 0))
      ((listEmpty? args) (fail (usage) 2))
      ((not (sys/executable? ctx.hostBin))
        (fail "(:build :status :failed :error ERR_HOST_ABSENT :message \"asl build needs stage-0 host at asl/host/out/asl-host; build it with sh asl/host/build.sh or set ASL_HOST\")" 2))
      (else
        (mt (findClang! clangName)
          ((none) (fail (str "ERR_BUILD: clang not found: " clangName "; install clang or set CLANG") 1))
          ((some clang)
            (if (not (sys/isFile? lib))
              (fail (str "ERR_BUILD: libaslrt.a not found at " lib "; build it with sh asl/host/build.sh") 1)
              (mt (parseArgs! args "" "")
                ((err code) code)
                ((ok parsed)
                  (let [(target (pairFirst parsed))]
                    (cond
                      ((stringEmpty? target) (fail (usage) 2))
                      ((not (sys/isFile? target)) (fail (str "(:build :status :failed :error ERR_NO_FILE :message \"file not found: " target "\")") 1))
                      (else (buildFile! ctx clang lib target (pairSecond parsed)))))))))))))
