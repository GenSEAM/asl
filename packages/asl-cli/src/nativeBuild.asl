(module asl-cli/nativeBuild
  :x [Build main link! compile! stage! partsOf sanitizeFlags linkSanitized! asanRuntime! notraceRuntime! transientFailure?]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/prelude/native/sha256 :a sh) (asl/packages/asl-proc/src/jobPool :a run) (asl/packages/asl-cli/src/irSplit :a ir)])

(schema Build
  (:f root String)
  (:f cache String)
  (:f tmp String)
  (:f lib String)
  (:f base String)
  (:f clangVersion String)
  (:f owner String)
  (:f deadlineNs Int64)
  (:f maxDesc Int64))

fn seedField row: String key: String -> (Option String)
  (let [(parts (stringSplit row (str ":" key " ")))]
    (if (< (listLength parts) 2) (none)
      (let [(rest (optionOr (listGet parts 1) ""))]
        (if (stringStartsWith? rest "\"")
          (listHead (stringSplit (optionOr (stringSlice rest 1 (stringLength rest)) "") "\""))
          (listHead (stringSplit (stringReplace rest ")" " ") " "))))))

fn stripVersion s: String -> String
  (let [(n (stringLength s))]
    (if (and (> n 0) (stringContains? "0123456789." (optionOr (stringSlice s (- n 1) n) "x"))) (stripVersion (optionOr (stringSlice s 0 (- n 1)) "")) s))

fn seedTriple triple: String -> String
  (let [(parts (stringSplit (stringTrim triple) "-"))]
    (stringJoin (listAppend (listTake parts (max 0 (- (listLength parts) 1))) (list (stripVersion (optionOr (listLast parts) "")))) "-"))

fn seedRow text: String key: String -> (Option String)
  (listHead (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:seed ") (stringContains? l (str ":triple \"" key "\""))))
                    (map stringTrim (stringLines text))))

fn ! say! line: String -> Bool
  (do (eprintln line) true)

fn ! envInt! name: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (envGet name) "")) fallback)

fn ! clang! -> String
  (optionOr (envGet "CLANG") "clang")

fn ! remainingS b: Build -> Int64
  (max 1 (/ (- b.deadlineNs (monotonicNs)) 1000000000))

fn ! ownerAlive? b: Build -> Bool
  (if (stringEmpty? b.owner) true
    (and (> (optionOr (stringToInt64 b.owner) 0) 1) (nc/alive? (optionOr (stringToInt64 b.owner) 0))))

fn ! child! b: Build argv: (List String) -> run/Done
  (if (or (<= b.deadlineNs (monotonicNs)) (not (ownerAlive? b)))
    (run/Done :idx 0 :exit 1 :out "" :ms 0 :verdict (if (ownerAlive? b) "deadline" "owner-gone"))
    (run/runOneLimited (run/job argv b.root (run/childEnv (list (str "ASL_PRELUDE=" b.root "/asl/prelude/prelude.asl")))) (run/limits (remainingS b) b.maxDesc)))

fn lastLines text: String -> String
  (let [(lines (stringLines (stringTrim text)))]
    (stringJoin (listDrop lines (max 0 (- (listLength lines) 20))) "\n"))

; (:m :ref NATIVECLI-STICKY-FAIL-20261018 :do "owner-gone/deadline (child!, compileParts!'s own ad hoc message) and timeout/runaway/spawnFailed (run/Done.verdict, via failure) are transient infrastructure causes, never a compiler diagnostic; only an 'exited N' message (failure's d.verdict = exit branch) reflects the compiler itself running and rejecting the input, which is the one case safe to cache and replay under the input digest. transientFailure? names every other message shape this module ever produces, by the fixed substrings failure/compileParts! always write for a non-exit verdict, so compile!'s .failed marker is written only for a deterministic failure")
fn transientFailure? why: String -> Bool
  (or (stringContains? why " was killed: ") (stringContains? why " did not run: "))

fn failure what: String d: run/Done -> String
  (if (= d.verdict "exit")
    (str what " exited " (stringFromInt64 d.exit) ": " (lastLines d.out))
    (str what " was killed: " d.verdict))

fn passed? d: run/Done -> Bool
  (and (= d.verdict "exit") (= d.exit 0))

fn ! shaOf path: String -> (Result String String)
  (match (fileReadBytes path)
    ((err e) (err (str "cannot read " path ": " e)))
    ((ok bytes) (ok (sh/bytesSha256 bytes))))

fn ! firstLine! b: Build argv: (List String) -> (Result String String)
  (let [(d (child! b argv))]
    (if (passed? d) (ok (stringTrim (optionOr (listHead (stringLines d.out)) ""))) (err (failure (stringJoin argv " ") d))))

fn ! setup! root: String cacheDir: String owner: String -> (Result (Pair Build String) String)
  (let [(lib (str root "/asl/host/out/libaslrt.a"))
        (start (Build :root root :cache cacheDir :tmp (str cacheDir "/tmp." (stringFromInt64 (procSelf))) :lib lib :base "" :clangVersion "" :owner owner
                      :deadlineNs (+ (monotonicNs) (* (envInt! "ASL_NATIVE_CLI_TIMEOUT" 1800) 1000000000)) :maxDesc (envInt! "ASL_NATIVE_CLI_MAXDESC" 32)))]
    (if (not (sys/isFile? lib))
      (err "asl/host/out/libaslrt.a is absent (sh asl/host/build.sh)")
      (match (firstLine! start (list (clang!) "-print-target-triple"))
        ((err e) (err e))
        ((ok machine)
          (let [(triple (seedTriple machine))]
            (match (match (fileReadString (str root "/asl/seed/seed.asn")) ((err e) (none)) ((ok text) (seedRow text triple)))
              ((none) (err (str "no seed for " triple " in asl/seed/seed.asn")))
              ((some row)
                (match (firstLine! start (list (clang!) "--version"))
                  ((err e) (err e))
                  ((ok version)
                    (match (shaOf lib)
                      ((err e) (err e))
                        ((ok libSha) (match (dirCreate start.tmp)
                        ((err e) (err (str "cannot create " start.tmp ": " e)))
                        ((ok _) (ok (pair (with (with start :base (sh/bytesSha256 (stringToBytes (str row "\n" libSha "\n" version)))) :clangVersion version) row)))))))))))))))

fn ! linkWith! b: Build inputs: (List String) ll: String out: String -> (Result String String)
  (let [(d (child! b (listAppend (cons (clang!) (cons "-O2" inputs)) (list b.lib "-lm" "-o" out))))]
    (if (passed? d) (ok out) (err (failure (str "clang link of " ll) d))))

fn ! writeParts! ll: String parts: (List (Pair Int64 String)) -> (Result (List String) String)
  (match (listHead parts)
    ((none) (ok (list)))
    ((some p) (let [(path (str ll ".part" (stringFromInt64 (pairFirst p)) ".ll"))]
                (match (fileWrite path (pairSecond p))
                  ((err e) (err (str "cannot write " path ": " e)))
                  ((ok _) (match (writeParts! ll (optionOr (listTail parts) (list)))
                    ((err e) (err e))
                    ((ok rest) (ok (cons path rest)))))))))

fn ! partsOf ll: String n: Int64 -> (Result (List String) String)
  (match (fileReadString ll)
    ((err e) (err (str "cannot read " ll ": " e)))
    ((ok text) (match (ir/split text n)
      ((err e) (err (str "cannot split " ll ": " e)))
      ((ok parts) (writeParts! ll (enumerate parts))))))

fn ! compileParts! b: Build ll: String paths: (List String) n: Int64 -> (Result (List String) String)
  (let [(jobs (map (fn [(p String)] -> run/Job (run/job (list (clang!) "-O2" "-Wno-override-module" "-x" "ir" p "-c" "-o" (str p ".o")) b.root (run/childEnv (list))))
                   paths))
        (done (if (or (<= b.deadlineNs (monotonicNs)) (not (ownerAlive? b))) (list) (run/runPoolLimited jobs n (run/limits (remainingS b) b.maxDesc))))
        (bad (filter (fn [(d run/Done)] -> Bool (not (passed? d))) done))]
    (cond
      ((!= (listLength done) (listLength paths)) (err (str "clang -c of the parts of " ll " did not run: " (if (ownerAlive? b) "deadline" "owner-gone"))))
      ((not (listEmpty? bad)) (match (listHead bad)
                                ((some d) (err (failure (str "clang -c of " (optionOr (listGet paths d.idx) ll)) d)))
                                ((none) (err (str "clang -c of the parts of " ll " failed")))))
      (else (ok (map (fn [(p String)] -> String (str p ".o")) paths)))))

fn ! link! b: Build ll: String out: String -> (Result String String)
  (let [(n (envInt! "ASL_NATIVE_LINK_JOBS" 8))
        (start (monotonicNs))
        (whole (fn [(why String)] -> (Result String String)
                 (do (say! (str "asl: native build: link " (sys/baseName ll) " whole" why))
                     (linkWith! b (list "-Wno-override-module" "-x" "ir" ll "-x" "none") ll out))))
        (linked (if (<= n 1) (whole "")
                  (match (partsOf ll n)
                    ((err e) (whole (str " (" e ")")))
                    ((ok paths) (if (< (listLength paths) 2) (whole "")
                                  (match (compileParts! b ll paths n)
                                    ((err e) (err e))
                                    ((ok objs) (do (say! (str "asl: native build: link " (sys/baseName ll) " parts " (stringFromInt64 (listLength objs))))
                                                   (linkWith! b objs ll out)))))))))]
    (do (say! (str "asl: native build: link " (sys/baseName ll) " " (stringFromInt64 (/ (- (monotonicNs) start) 1000000)) " ms"))
        linked))

fn ! sanitizeFlags -> (List String)
  (list "-O0" "-g" "-fno-omit-frame-pointer" "-fsanitize=address,undefined")

fn ! linkWithFlags! b: Build inputs: (List String) lib: String out: String sanitize: Bool label: String -> (Result String String)
  (let [(opt (if sanitize (sanitizeFlags) (list "-O2")))
        (d (child! b (listAppend (cons (clang!) opt) (listAppend inputs (list lib "-lm" "-o" out)))))]
    (if (passed? d) (ok out) (err (failure (str "clang link of " label (if sanitize " under ASan" "")) d))))

fn ! linkSanitized! b: Build ll: String lib: String out: String sanitize: Bool -> (Result String String)
  (linkWithFlags! b (list "-Wno-override-module" "-x" "ir" ll "-x" "none") lib out sanitize (sys/baseName ll))

fn ! emitLl! b: Build asl1: String src: String out: String -> (Result String String)
  (let [(d (child! b (list asl1 "build" src "-o" out)))]
    (if (passed? d) (ok out) (err (failure (str asl1 " build " src) d))))

fn ! compileObj! b: Build ll: String obj: String -> (Result String String)
  (let [(d (child! b (list (clang!) "-O2" "-Wno-override-module" "-c" "-x" "ir" ll "-o" obj)))]
    (if (passed? d) (ok obj) (err (failure (str "clang -c of " ll) d))))

fn ! arPack! b: Build out: String objs: (List String) -> (Result String String)
  (let [(d (child! b (listAppend (list "ar" "rcs" out) objs)))]
    (if (passed? d) (ok out) (err (failure (str "ar " out) d))))

fn ! buildEmitter! b: Build asl1: String src: String tmp: String name: String -> (Result String String)
  (let [(ll (str tmp "/" name "Emitter.ll")) (bin (str tmp "/" name "Emitter"))]
    (match (emitLl! b asl1 src ll)
      ((err e) (err e))
      ((ok _) (linkSanitized! b ll b.lib bin false))))

fn ! runEmitter! b: Build bin: String out: String extra: (List String) -> (Result String String)
  (let [(d (child! b (cons bin (cons out extra))))]
    (if (passed? d) (ok out) (err (failure (str bin " " out) d))))

fn ! emitModuleObj! b: Build asl1: String src: String tmp: String name: String extra: (List String) -> (Result String String)
  (match (buildEmitter! b asl1 src tmp name)
    ((err e) (err e))
    ((ok bin)
      (let [(ll (str tmp "/" name ".ll")) (obj (str tmp "/" name ".o"))]
        (match (runEmitter! b bin ll extra)
          ((err e) (err e))
          ((ok _) (compileObj! b ll obj))))))

fn ! emitObjs! b: Build asl1: String tmp: String specs: (List (Pair (Pair String String) (List String))) -> (Result (List String) String)
  (match (listHead specs)
    ((none) (ok (list)))
    ((some spec)
      (let [(loc (pairFirst spec)) (src (pairFirst loc)) (name (pairSecond loc)) (extra (pairSecond spec))]
        (match (emitModuleObj! b asl1 src tmp name extra)
          ((err e) (err e))
          ((ok obj) (match (emitObjs! b asl1 tmp (optionOr (listTail specs) (list)))
            ((err e) (err e))
            ((ok rest) (ok (cons obj rest)))))))))

fn ! asanRuntimeKey! b: Build packagesDir: String -> (Result String String)
  (variantKey! b packagesDir "asan")

fn ! variantKey! b: Build packagesDir: String variant: String -> (Result String String)
  (match (shaOf (str packagesDir "/asl-target-llvm/src/gcRoute.asl"))
    ((err e) (err e))
    ((ok s1) (match (shaOf (str packagesDir "/asl-target-llvm/src/rtAbi.asl"))
      ((err e) (err e))
      ((ok s2) (match (shaOf (str packagesDir "/asl-target-llvm/src/rtFloor.asl"))
        ((err e) (err e))
        ((ok s3) (ok (sh/bytesSha256 (stringToBytes (str b.clangVersion "\n" variant "\n" s1 "\n" s2 "\n" s3))))))))))

fn ! asanRuntime! b: Build asl1: String packagesDir: String -> (Result String String)
  (variantRuntime! b asl1 packagesDir "asan" (list) (list "asan"))

fn ! notraceRuntime! b: Build asl1: String packagesDir: String -> (Result String String)
  (variantRuntime! b asl1 packagesDir "notrace" (list "notrace") (list))

fn ! clearDir! dir: String -> (Result Unit String)
  (match (dirList dir)
    ((err e) (err (str "cannot list " dir ": " e)))
    ((ok names)
      (let [(left (filter (fn [(n String)] -> Bool (err? (pathRemove (str dir "/" n)))) names))]
        (cond
          ((not (listEmpty? left)) (err (str "cannot remove " dir "/" (optionOr (listHead left) ""))))
          (else (match (pathRemove dir)
            ((err e) (err (str "cannot remove " dir ": " e)))
            ((ok _) (ok ()))))))))

fn ! packVariant! b: Build asl1: String tmp: String specs: (List (Pair (Pair String String) (List String))) variant: String dir: String lib: String -> (Result String String)
  (match (emitObjs! b asl1 tmp specs)
    ((err e) (err e))
    ((ok objs) (match (arPack! b (str tmp "/libaslrt-" variant ".a") objs)
      ((err e) (err e))
      ((ok built) (match (dirCreate dir)
        ((err e) (err (str "cannot create " dir ": " e)))
        ((ok _) (match (pathRename built lib)
          ((err e) (err (str "cannot install " lib ": " e)))
          ((ok _) (ok lib)))))))))

fn ! variantRuntime! b: Build asl1: String packagesDir: String variant: String gcExtra: (List String) abiExtra: (List String) -> (Result String String)
  (match (variantKey! b packagesDir variant)
    ((err e) (err e))
    ((ok key)
      (let [(dir (str b.cache "/rt-" variant "-" key)) (lib (str dir "/libaslrt-" variant ".a"))]
        (if (sys/isFile? lib) (ok lib)
          (let [(tmp (str b.tmp "/rt-" variant "." (stringFromInt64 (procSelf))))
                (specs (list (pair (pair (str packagesDir "/asl-target-llvm/src/gcRoute.asl") "gcAsl") gcExtra)
                             (pair (pair (str packagesDir "/asl-target-llvm/src/rtAbi.asl") "rtAbi") abiExtra)
                             (pair (pair (str packagesDir "/asl-target-llvm/src/rtFloor.asl") "rtFloor") (list))))]
            (match (dirCreate tmp)
              ((err e) (err (str "cannot create " tmp ": " e)))
              ((ok _)
                (let [(built (packVariant! b asl1 tmp specs variant dir lib))]
                  (match (clearDir! tmp)
                    ((err e) (match built ((err first) (err (str first "; " e))) ((ok _) (err e))))
                    ((ok _) built))))))))))

fn ! seed! b: Build row: String -> (Result String String)
  (let [(file (optionOr (seedField row "file") ""))
        (llSha (optionOr (seedField row "llSha256") ""))
        (dir (str b.cache "/seed-" llSha "-" (optionOr (stringSlice b.base 0 16) b.base)))
        (ll (str b.tmp "/seed.ll"))]
    (cond
      ((or (stringEmpty? file) (!= (stringLength llSha) 64)) (err "the seed row lacks :file or :llSha256"))
      ((sys/executable? (str dir "/bin")) (ok (str dir "/bin")))
      (else
        (let [(d (child! b (list "/bin/sh" "-c" "exec gzip -dc \"$0\" > \"$1\"" (str b.root "/" file) ll)))]
          (cond
            ((not (passed? d)) (err (failure (str "gzip -dc " file) d)))
            ((!= (resultOr (shaOf ll) "") llSha) (err (str "seed " file " did not unpack to llSha256 " llSha)))
            (else (match (link! b ll (str b.tmp "/seed.bin"))
                    ((err e) (err e))
                    ((ok bin) (match (dirCreate dir)
                      ((err e) (err (str "cannot create " dir ": " e)))
                      ((ok _) (match (pathRename bin (str dir "/bin"))
                        ((err e) (err (str "cannot install the seed: " e)))
                        ((ok _) (ok (str dir "/bin"))))))))))))))

fn rootRelative prefixes: (List String) line: String -> String
  (match (listHead (filter (fn [(p String)] -> Bool (stringStartsWith? line p)) prefixes))
    ((none) line)
    ((some p) (optionOr (stringSlice line (stringLength p) (stringLength line)) line)))

fn distinct xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (optionOr (listHead acc) "") x) acc (cons x acc))) (list) (listSort xs)))

fn ! depsOf! b: Build compiler: String entry: String extra: (List String) -> (Result (List String) String)
  (let [(out (str b.tmp "/deps.out"))
        (d (child! b (list "/bin/sh" "-c" "exec \"$0\" deps \"$1\" > \"$2\"" compiler entry out)))
        (prefixes (list (str (resultOr (realPath b.root) b.root) "/") (str b.root "/")))
        (natives (map (fn [(n String)] -> String (str "asl/prelude/native/" n))
                      (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) (resultOr (dirList (str b.root "/asl/prelude/native")) (list)))))]
    (if (not (passed? d))
      (err (failure (str compiler " deps " entry) d))
      (match (fileReadString out)
        ((err e) (err (str "cannot read " out ": " e)))
        ((ok text) (ok (distinct (listAppend (cons entry (cons "asl/prelude/prelude.asl" (map (fn [(l String)] -> String (rootRelative prefixes (stringTrim l)))
                                                                                         (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines text)))))
                                             (listAppend natives extra))))))))

fn ! keyOf! b: Build src: String tag: String entry: String deps: (List String) -> (Result String String)
  (match (listHead deps)
    ((none) (ok (sh/bytesSha256 (stringToBytes (str b.base " " tag " " entry)))))
    ((some p) (match (shaOf (if (= src b.root) (nc/underRoot src p) (str src "/" p)))
      ((err e) (err e))
      ((ok digest) (match (keyOf! b src tag entry (optionOr (listTail deps) (list)))
        ((err e) (err e))
        ((ok rest) (ok (sh/bytesSha256 (stringToBytes (str p "\n" digest "\n" rest))))))))))

fn ! copyAll! from: String to: String paths: (List String) -> (Result Unit String)
  (match (listHead paths)
    ((none) (ok ()))
    ((some p) (let [(target (str to "/" p))]
                (match (match (dirCreate (sys/parentOf target)) ((err e) (err e)) ((ok _) (match (fileReadBytes (nc/underRoot from p)) ((err e) (err e)) ((ok bytes) (fileWrite target bytes)))))
                  ((err e) (err (str "cannot snapshot " p ": " e)))
                  ((ok _) (copyAll! from to (optionOr (listTail paths) (list))))))))

fn ! install! b: Build name: String tag: String entry: String key: String dir: String deps: (List String) bin: String -> (Result String String)
  (let [(staged (str b.tmp "/" name ".dir"))]
    (match (match (dirCreate staged) ((err e) (err e)) ((ok _) (match (fileWrite (str staged "/deps") (str (stringJoin deps "\n") "\n"))
      ((err e) (err e)) ((ok _) (match (fileWrite (str staged "/clang-version") (str b.clangVersion "\n")) ((err e) (err e)) ((ok _) (fileWrite (str staged "/rc") "notrace\n")))))))
      ((err e) (err (str "cannot stage " staged ": " e)))
      ((ok _) (match (copyAll! b.root (str staged "/src") deps)
        ((err e) (err e))
        ((ok _) (if (!= (resultOr (keyOf! b (str staged "/src") tag entry deps) "") key)
          (err (str "the sources of " entry " changed during its build; the next call rebuilds"))
          (match (pathRename bin (str staged "/bin"))
            ((err e) (err (str "cannot stage " bin ": " e)))
            ((ok _) (match (pathRename staged dir)
              ((ok _) (ok dir))
              ((err e) (if (sys/executable? (str dir "/bin")) (ok dir) (err (str "cannot install " dir ": " e)))))))))))))

fn ! compile! b: Build name: String compiler: String tag: String entry: String dir: String deps: (List String) key: String -> (Result String String)
  (let [(ll (str b.tmp "/" name ".ll"))
        (start (monotonicNs))
        (built (child! b (list compiler "build" entry "-o" ll "--rc" "notrace")))
        (_ (say! (str "asl: native build: build " entry " " (stringFromInt64 (/ (- (monotonicNs) start) 1000000)) " ms")))
        (failed (fn [(why String)] -> (Result String String)
                  (do (if (transientFailure? why) (ok ()) (fileWrite (str dir ".failed") (str why "\n"))) (err why))))]
    (cond
      ((= built.verdict "exit") (if (= built.exit 0)
                                  (match (link! b ll (str b.tmp "/" name ".bin"))
                                    ((err e) (failed e))
                                    ((ok bin) (install! b name tag entry key dir deps bin)))
                                  (failed (failure (str compiler " build " entry) built))))
      (else (err (failure (str compiler " build " entry) built)))))

; (:m :ref NATIVECLI-STICKY-FAIL-20261018 :do "a .failed marker written before this fix (or by another process) can itself carry a transient-shaped message; a marker whose own stored text is transient is read as absent, not replayed, and is removed so it is not re-parsed on every later call")
fn ! stage! b: Build name: String compiler: String tag: String entry: String extra: (List String) -> (Result String String)
  (match (depsOf! b compiler entry extra)
    ((err e) (err e))
    ((ok deps) (match (keyOf! b b.root (str tag "+notrace") entry deps)
      ((err e) (err e))
      ((ok key) (let [(dir (str b.cache "/" name "-" key))
                       (marker (str dir ".failed"))
                       (markerPresent (sys/isFile? marker))
                       (markerText (if markerPresent (stringTrim (resultOr (fileReadString marker) "")) ""))
                       (stuckTransient (and markerPresent (transientFailure? markerText)))
                       (cleared (if stuckTransient (pathRemove marker) (ok ())))]
                  (cond
                    ((sys/executable? (str dir "/bin")) (ok dir))
                    ((and markerPresent (not stuckTransient)) (err (str "an earlier build of " entry " with key " key " failed: " markerText)))
                    (else (do (say! (str "asl: native build: " entry " with " (sys/baseName (sys/parentOf compiler))))
                              (compile! b name compiler (str tag "+notrace") entry dir deps key)))))))))

fn ! writeHead! b: Build dir: String -> (Result String String)
  (let [(head (nc/headPath b.cache b.root))
        (part (str head ".part." (stringFromInt64 (procSelf))))]
    (match (fileWrite part (str dir "\n"))
      ((err e) (err (str "cannot write " part ": " e)))
      ((ok _) (match (pathRename part head) ((err e) (err (str "cannot install " head ": " e))) ((ok _) (ok dir))))))

fn withLib b: Build lib: String -> Build
  (with b :lib lib)

fn ! build! root: String cacheDir: String owner: String -> (Result String String)
  (match (setup! root cacheDir owner)
    ((err e) (err e))
    ((ok ready)
      (let [(b (pairFirst ready))]
        (match (seed! b (pairSecond ready))
          ((err e) (err e))
          ((ok seedBin) (match (notraceRuntime! b seedBin (str root "/asl/packages"))
            ((err e) (err e))
            ((ok ntLib) (let [(nb (withLib b ntLib))]
              (match (stage! nb "asl1" seedBin (sys/baseName (sys/parentOf seedBin)) "asl/packages/asl-compiler/src/asl1.asl" (list))
                ((err e) (err e))
                ((ok stage1) (let [(asl1Deps (stringLines (stringTrim (resultOr (fileReadString (str stage1 "/deps")) ""))))]
                  (match (stage! nb "cli" (str stage1 "/bin") (sys/baseName stage1) "asl/packages/asl-cli/src/native.asl"
                              (listAppend asl1Deps (list "asl/host/out/libaslrt.a" "asl/seed/seed.asn")))
                    ((err e) (err e))
                    ((ok cli) (if (nc/probe? root cli) (writeHead! b cli) (err "the built native CLI failed its self-probe")))))))))))))))

fn flagValue args: (List String) flag: String -> (Option String)
  (match (listIndexOf args flag)
    ((none) (none))
    ((some i) (listGet args (+ i 1))))

fn ! releaseLock! cacheDir: String owner: String -> Bool
  (let [(lock (str cacheDir "/lock"))
        (held (stringTrim (resultOr (fileReadString (str lock "/pid")) "")))]
    (if (and (not (stringEmpty? held)) (or (= held (stringFromInt64 (procSelf))) (= held owner))) (ok? (pathRemove lock)) false))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (optionOr (listHead args) ""))
        (second (optionOr (listGet args 1) "--"))
        (cacheDir (optionOr (flagValue args "--cache") (if (stringStartsWith? second "--") (nc/cacheDir!) second)))
        (owner (optionOr (flagValue args "--lock-owner") ""))
        (pid (stringFromInt64 (procSelf)))]
    (cond
      ((stringEmpty? root) (do (say! "usage: nativeBuild ROOT [CACHE] [--if-cold] [--lock-owner PID]") (ok 2)))
      ((and (listContains? args "--if-cold") (let [(head (stringTrim (resultOr (fileReadString (nc/headPath cacheDir root)) "")))] (and (nc/fresh? root head) (nc/probe? root head)))) (ok 0))
      ((and (not (stringEmpty? owner)) (or (<= (optionOr (stringToInt64 owner) 0) 1) (not (nc/alive? (optionOr (stringToInt64 owner) 0))))) (do (releaseLock! cacheDir owner) (ok 1)))
      (else
        (let [(_ (say! (str "asl: native build pid " pid " started for " root)))
              (code (match (build! root cacheDir owner)
                      ((ok dir) (do (say! (str "asl: native build: " dir)) 0))
                      ((err e) (do (say! (str "asl: native build failed: " e)) 1))))
              (_ (pathRemove (str cacheDir "/tmp." pid)))
              (_ (releaseLock! cacheDir owner))]
          (do (say! (str "asl: native build pid " pid " exit " (stringFromInt64 code)))
              (ok code))))))
