(module asl-cli/build
  :x [buildCommand!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/asl1Cache :a cache) (asl/packages/asl-cli/src/verify :a verify) (asl/packages/asl-cli/src/nativeBuild :a nb) (asl/packages/asl-cli/src/rcConfig :a rcc) (asl-parser/reader :a rd) (asl-checker/foreign :a fsig)])

fn usage -> String
  "usage: asl build FILE [-o OUT]"

; (:m :ref BUILDPAR :do "the link shape a build asked for on its command line (--parts N, --dev, --release; the usage line stays the one the argv parity fixtures pin); an empty field means the config decides (nb/linkPartsFor!, nb/linkLevelFor!)")
(schema Opts
  (:f target String)
  (:f out String)
  (:f parts String)
  (:f level String))

fn ! fail text: String code: Int64 -> Int64
  (do (sys/sayErr! text) code)

fn findClang! name: String -> (Option String)
  (if (stringContains? name "/")
    (if (and (sys/isFile? name) (sys/executable? name)) (some name) (none))
    (sys/onPath! name))

fn parseArgs! args: (List String) o: Opts -> (Result Opts Int64)
  (match (listHead args)
    ((none) (ok o))
    ((some a)
      (let [(more (optionOr (listTail args) (list)))
            (value (fn [(flag String)] -> (Result String Int64)
                     (if (listEmpty? more)
                       (err (fail (str "(:build :status :failed :error ERR_USAGE :message \"" flag " requires a value\")") 2))
                       (ok (optionOr (listHead more) "")))))
            (after (optionOr (listTail more) (list)))]
        (cond
          ((= a "-o") (match (value "-o") ((err c) (err c)) ((ok v) (parseArgs! after (with o :out v)))))
          ((= a "--parts") (match (value "--parts") ((err c) (err c)) ((ok v) (parseArgs! after (with o :parts v)))))
          ((= a "--dev") (parseArgs! more (with o :level "dev")))
          ((= a "--release") (parseArgs! more (with o :level "release")))
          ((stringStartsWith? a "-") (err (fail (str "(:build :status :failed :error ERR_UNKNOWN_ARG :message \"unknown option " a "\")") 2)))
          ((stringEmpty? o.target) (parseArgs! more (with o :target a)))
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

fn ! effectiveLibAndFlags! ctx: sys/Context clang: String lib: String mode: String opt: String -> (Result (Pair String (List String)) String)
  (cond
    ((= mode "asan")
      (match (variantLib! ctx clang lib "asan")
        ((err e) (err e))
        ((ok asanLib) (ok (pair asanLib (nb/sanitizeFlags))))))
    ((= mode "notrace")
      (match (variantLib! ctx clang lib "notrace")
        ((err e) (err e))
        ((ok ntLib) (ok (pair ntLib (list opt))))))
    (else (ok (pair lib (list opt)))))

; (:m :ref BUILDPAR :do "the link goes through nativeBuild's parts path: the .ll is split into the configured number of parts (a --parts flag exactly; a configured or default count only while each part keeps nb/minPartBytes, so a small program links whole as before), compiled in parallel by the bounded job pool and linked; one part, or a split that fails, is the old single clang call. The shape is reported on stderr as one ASN line when it is not the classic one part at -O2, which stays silent as the argv parity cases pin")
fn ! linkShape! dir: String o: Opts -> (Result (Pair Int64 String) String)
  (match (if (stringEmpty? o.parts) (nb/linkPartsFor! dir) (nb/partsValue o.parts))
    ((err e) (err e))
    ((ok n) (match (if (stringEmpty? o.level) (nb/linkLevelFor! dir) (nb/levelFlag o.level))
      ((err e) (err e))
      ((ok opt) (ok (pair n opt))))))

; (:m :ref FFI1 :do "the native libraries a program's foreign fns call: :linkLibraries [\"z\"] in the manifest.asn nearest the entry file becomes -lz after libaslrt.a on the link line; c and m need no row")
fn valueOf items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead items)
    ((none) (none))
    ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) key)) (listGet items 1) (valueOf (optionOr (listTail items) (list)) key))))

fn unquoted s: String -> String
  (if (and (>= (stringLength s) 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\""))) (optionOr (stringSlice s 1 (- (stringLength s) 1)) s) s)

fn linkLibraries text: String -> (Result (List String) String)
  (match (valueOf (rd/sexprToList (rd/parseSexpr text)) ":linkLibraries")
    ((none) (ok (list)))
    ((some v)
      (let [(names (map (fn [(e rd/SExpr)] -> String (unquoted (rd/sexprHead e))) (match v ((rd/sexprVect xs) xs) ((rd/sexprList xs) xs) ((rd/sexprAtom _) (list v)))))
            (bad (filter (fn [(n String)] -> Bool (not (fsig/libName? n))) names))]
        (if (listEmpty? bad)
          (ok (map (fn [(n String)] -> String (str "-l" n)) names))
          (err (str ":linkLibraries names " (optionOr (listHead bad) "") ", which is not a library name ([A-Za-z0-9_.+-], not starting with -)"))))))

fn ! nearestManifest! dir: String depth: Int64 -> (Option String)
  (let [(m (str dir "/manifest.asn"))]
    (cond
      ((sys/isFile? m) (some m))
      ((or (<= depth 0) (or (stringEmpty? dir) (= dir "/"))) (none))
      (else (nearestManifest! (sys/parentOf dir) (- depth 1)))))

fn ! linksFor! target: String -> (Result (List String) String)
  (match (nearestManifest! (sys/parentOf (resultOr (realPath target) target)) 32)
    ((none) (ok (list)))
    ((some m) (match (fileReadString m)
                ((err e) (err (str "cannot read " m ": " e)))
                ((ok text) (match (linkLibraries text)
                             ((err e) (err (str m ": " e)))
                             ((ok links) (ok links)))))))

fn ! linkAttempt! ctx: sys/Context clang: String flags: (List String) lib: String links: (List String) ll: String part: String n: Int64 tmp: String -> (Result (Pair Int64 String) String)
  (let [(b (nb/Build :root ctx.root :cache tmp :tmp tmp :lib lib :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 3600000000000) :maxDesc (+ 16 (* 4 n)) :links links))]
    (nb/linkParts! b clang flags ll part n))

fn ! link! ctx: sys/Context clang: String lib: String target: String out: String tmp: String mode: String shape: (Pair Int64 String) exact: Bool -> Int64
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
              (match (effectiveLibAndFlags! ctx clang lib mode (pairSecond shape))
                ((err e) (do (drop! ll) (drop! tmp) (fail (str "ERR_BUILD: runtime variant: " e) 1)))
                ((ok libFlags) (match (linksFor! target)
                ((err e) (do (drop! ll) (drop! tmp) (fail (str "ERR_BUILD: " e) 1)))
                ((ok links)
                  (let [(flags (pairSecond libFlags))
                        (start (monotonicNs))
                        (n (if exact (pairFirst shape) (nb/partsForSize (pairFirst shape) (resultOr (fileSize ll) 0))))
                        (linkRes (linkAttempt! ctx clang flags (pairFirst libFlags) links ll part n tmp))
                        (ms (/ (- (monotonicNs) start) 1000000))
                        (removed (drop! tmp))]
                    (match linkRes
                      ((err e) (do (drop! part) (fail (str "ERR_BUILD: clang link failed for " target ": " e) 1)))
                      ((ok linked)
                        (cond
                          ((not (sys/isFile? part)) (do (drop! part) (fail (str "ERR_BUILD: clang link wrote no " part) 1)))
                          ((not removed) (do (drop! part) (fail (str "ERR_BUILD: cannot remove " tmp) 1)))
                          (else
                            (match (pathRename part out)
                              ((err _) (do (drop! part) (fail (str "ERR_BUILD: cannot write " out) 1)))
                              ((ok _) (do (if (and (= (pairFirst linked) 1) (= (optionOr (listHead flags) "") "-O2")) true (sys/sayErr! (str "(:build :link (:parts " (stringFromInt64 (pairFirst linked)) " :opt \"" (optionOr (listHead flags) "") "\" :ms " (stringFromInt64 ms)
                                                             (if (stringEmpty? (pairSecond linked)) "" (str " :whole \"" (stringReplace (pairSecond linked) "\"" "'") "\"")) "))")))
                                          (sys/say! (str "built " out)) 0))))))))))))))))))

fn ! buildFile! ctx: sys/Context clang: String lib: String target: String o: Opts -> Int64
  (let [(given o.out)
        (out (if (stringEmpty? given) (defaultOut target) given))
        (checked (verify/nativeCheckPaths! (list target)))]
    (if (!= checked 0)
      checked
      (match (tempDir! (let [(t (optionOr (envGet "TMPDIR") ""))] (if (stringEmpty? t) "/tmp" (if (stringEndsWith? t "/") (optionOr (stringSlice t 0 (- (stringLength t) 1)) t) t))) 0)
        ((err _) (fail "ERR_BUILD: cannot create temporary directory" 1))
        ((ok tmp) (let [(dir (sys/parentOf (resultOr (realPath target) target)))]
                    (match (rcc/rcModeIn! dir "notrace")
                      ((err e) (do (drop! tmp) (fail e 1)))
                      ((ok mode) (match (linkShape! dir o)
                        ((err e) (do (drop! tmp) (fail e 1)))
                        ((ok shape) (link! ctx clang lib target out tmp mode shape (not (stringEmpty? o.parts))))))))))))

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
              (match (parseArgs! args (Opts :target "" :out "" :parts "" :level ""))
                ((err code) code)
                ((ok parsed)
                  (let [(target parsed.target)]
                    (cond
                      ((stringEmpty? target) (fail (usage) 2))
                      ((not (sys/isFile? target)) (fail (str "(:build :status :failed :error ERR_NO_FILE :message \"file not found: " target "\")") 1))
                      (else (buildFile! ctx clang lib target parsed))))))))))))
