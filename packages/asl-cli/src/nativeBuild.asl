(module asl-cli/nativeBuild
  :x [main]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/prelude/native/sha256 :a sh) (tools/fleet/run :a run)])

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

fn failure what: String d: run/Done -> String
  (if (= d.verdict "exit")
    (str what " exited " (stringFromInt64 d.exit) ": " (lastLines d.out))
    (str what " was killed: " d.verdict))

fn passed? d: run/Done -> Bool
  (and (= d.verdict "exit") (= d.exit 0))

fn ! shaOf path: String -> (Result String String)
  (mt (fileReadBytes path)
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
      (mt (firstLine! start (list (clang!) "-print-target-triple"))
        ((err e) (err e))
        ((ok machine)
          (let [(triple (seedTriple machine))]
            (mt (mt (fileRead (str root "/asl/seed/seed.asn")) ((err e) (none)) ((ok text) (seedRow text triple)))
              ((none) (err (str "no seed for " triple " in asl/seed/seed.asn")))
              ((some row)
                (mt (firstLine! start (list (clang!) "--version"))
                  ((err e) (err e))
                  ((ok version)
                    (mt (shaOf lib)
                      ((err e) (err e))
                        ((ok libSha) (mt (dirCreate start.tmp)
                        ((err e) (err (str "cannot create " start.tmp ": " e)))
                        ((ok _) (ok (pair (with (with start :base (sh/bytesSha256 (stringToBytes (str row "\n" libSha "\n" version)))) :clangVersion version) row)))))))))))))))

fn ! link! b: Build ll: String out: String -> (Result String String)
  (let [(d (child! b (list (clang!) "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" b.lib "-lm" "-o" out)))]
    (if (passed? d) (ok out) (err (failure (str "clang link of " ll) d))))

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
            (else (mt (link! b ll (str b.tmp "/seed.bin"))
                    ((err e) (err e))
                    ((ok bin) (mt (dirCreate dir)
                      ((err e) (err (str "cannot create " dir ": " e)))
                      ((ok _) (mt (pathRename bin (str dir "/bin"))
                        ((err e) (err (str "cannot install the seed: " e)))
                        ((ok _) (ok (str dir "/bin"))))))))))))))

fn rootRelative prefixes: (List String) line: String -> String
  (mt (listHead (filter (fn [(p String)] -> Bool (stringStartsWith? line p)) prefixes))
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
      (mt (fileRead out)
        ((err e) (err (str "cannot read " out ": " e)))
        ((ok text) (ok (distinct (listAppend (cons entry (cons "asl/prelude/prelude.asl" (map (fn [(l String)] -> String (rootRelative prefixes (stringTrim l)))
                                                                                         (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines text)))))
                                             (listAppend natives extra))))))))

fn ! keyOf! b: Build src: String tag: String entry: String deps: (List String) -> (Result String String)
  (mt (listHead deps)
    ((none) (ok (sh/bytesSha256 (stringToBytes (str b.base " " tag " " entry)))))
    ((some p) (mt (shaOf (if (= src b.root) (nc/underRoot src p) (str src "/" p)))
      ((err e) (err e))
      ((ok digest) (mt (keyOf! b src tag entry (optionOr (listTail deps) (list)))
        ((err e) (err e))
        ((ok rest) (ok (sh/bytesSha256 (stringToBytes (str p "\n" digest "\n" rest))))))))))

fn ! copyAll! from: String to: String paths: (List String) -> (Result Unit String)
  (mt (listHead paths)
    ((none) (ok ()))
    ((some p) (let [(target (str to "/" p))]
                (mt (mt (dirCreate (sys/parentOf target)) ((err e) (err e)) ((ok _) (mt (fileReadBytes (nc/underRoot from p)) ((err e) (err e)) ((ok bytes) (fileWrite target bytes)))))
                  ((err e) (err (str "cannot snapshot " p ": " e)))
                  ((ok _) (copyAll! from to (optionOr (listTail paths) (list))))))))

fn ! install! b: Build name: String tag: String entry: String key: String dir: String deps: (List String) bin: String -> (Result String String)
  (let [(staged (str b.tmp "/" name ".dir"))]
    (mt (mt (dirCreate staged) ((err e) (err e)) ((ok _) (mt (fileWrite (str staged "/deps") (str (stringJoin deps "\n") "\n"))
      ((err e) (err e)) ((ok _) (fileWrite (str staged "/clang-version") (str b.clangVersion "\n"))))))
      ((err e) (err (str "cannot stage " staged ": " e)))
      ((ok _) (mt (copyAll! b.root (str staged "/src") deps)
        ((err e) (err e))
        ((ok _) (if (!= (resultOr (keyOf! b (str staged "/src") tag entry deps) "") key)
          (err (str "the sources of " entry " changed during its build; the next call rebuilds"))
          (mt (pathRename bin (str staged "/bin"))
            ((err e) (err (str "cannot stage " bin ": " e)))
            ((ok _) (mt (pathRename staged dir)
              ((ok _) (ok dir))
              ((err e) (if (sys/executable? (str dir "/bin")) (ok dir) (err (str "cannot install " dir ": " e)))))))))))))

fn ! compile! b: Build name: String compiler: String tag: String entry: String dir: String deps: (List String) key: String -> (Result String String)
  (let [(ll (str b.tmp "/" name ".ll"))
        (built (child! b (list compiler "build" entry "-o" ll)))
        (failed (fn [(why String)] -> (Result String String)
                  (do (fileWrite (str dir ".failed") (str why "\n")) (err why))))]
    (cond
      ((= built.verdict "exit") (if (= built.exit 0)
                                  (mt (link! b ll (str b.tmp "/" name ".bin"))
                                    ((err e) (failed e))
                                    ((ok bin) (install! b name tag entry key dir deps bin)))
                                  (failed (failure (str compiler " build " entry) built))))
      (else (err (failure (str compiler " build " entry) built)))))

fn ! stage! b: Build name: String compiler: String tag: String entry: String extra: (List String) -> (Result String String)
  (mt (depsOf! b compiler entry extra)
    ((err e) (err e))
    ((ok deps) (mt (keyOf! b b.root tag entry deps)
      ((err e) (err e))
      ((ok key) (let [(dir (str b.cache "/" name "-" key))]
                  (cond
                    ((sys/executable? (str dir "/bin")) (ok dir))
                    ((sys/isFile? (str dir ".failed")) (err (str "an earlier build of " entry " with key " key " failed: " (stringTrim (resultOr (fileRead (str dir ".failed")) "")))))
                    (else (do (say! (str "asl: native build: " entry " with " (sys/baseName (sys/parentOf compiler))))
                              (compile! b name compiler tag entry dir deps key)))))))))

fn ! writeHead! b: Build dir: String -> (Result String String)
  (let [(head (nc/headPath b.cache b.root))
        (part (str head ".part." (stringFromInt64 (procSelf))))]
    (mt (fileWrite part (str dir "\n"))
      ((err e) (err (str "cannot write " part ": " e)))
      ((ok _) (mt (pathRename part head) ((err e) (err (str "cannot install " head ": " e))) ((ok _) (ok dir))))))

fn ! build! root: String cacheDir: String owner: String -> (Result String String)
  (mt (setup! root cacheDir owner)
    ((err e) (err e))
    ((ok ready)
      (let [(b (pairFirst ready))]
        (mt (seed! b (pairSecond ready))
          ((err e) (err e))
          ((ok seedBin) (mt (stage! b "asl1" seedBin (sys/baseName (sys/parentOf seedBin)) "asl/packages/asl-compiler/src/asl1.asl" (list))
            ((err e) (err e))
            ((ok stage1) (let [(asl1Deps (stringLines (stringTrim (resultOr (fileRead (str stage1 "/deps")) ""))))]
              (mt (stage! b "cli" (str stage1 "/bin") (sys/baseName stage1) "asl/packages/asl-cli/src/native.asl"
                          (listAppend asl1Deps (list "asl/host/out/libaslrt.a" "asl/seed/seed.asn")))
                ((err e) (err e))
                ((ok cli) (if (nc/probe? root cli) (writeHead! b cli) (err "the built native CLI failed its self-probe"))))))))))))

fn flagValue args: (List String) flag: String -> (Option String)
  (mt (listIndexOf args flag)
    ((none) (none))
    ((some i) (listGet args (+ i 1))))

fn ! releaseLock! cacheDir: String owner: String -> Bool
  (let [(lock (str cacheDir "/lock"))
        (held (stringTrim (resultOr (fileRead (str lock "/pid")) "")))]
    (if (and (not (stringEmpty? held)) (or (= held (stringFromInt64 (procSelf))) (= held owner))) (ok? (pathRemove lock)) false))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (optionOr (listHead args) ""))
        (second (optionOr (listGet args 1) "--"))
        (cacheDir (optionOr (flagValue args "--cache") (if (stringStartsWith? second "--") (nc/cacheDir!) second)))
        (owner (optionOr (flagValue args "--lock-owner") ""))
        (pid (stringFromInt64 (procSelf)))]
    (cond
      ((stringEmpty? root) (do (say! "usage: nativeBuild ROOT [CACHE] [--if-cold] [--lock-owner PID]") (ok 2)))
      ((and (listContains? args "--if-cold") (let [(head (stringTrim (resultOr (fileRead (nc/headPath cacheDir root)) "")))] (and (nc/fresh? root head) (nc/probe? root head)))) (ok 0))
      ((and (not (stringEmpty? owner)) (or (<= (optionOr (stringToInt64 owner) 0) 1) (not (nc/alive? (optionOr (stringToInt64 owner) 0))))) (do (releaseLock! cacheDir owner) (ok 1)))
      (else
        (let [(_ (say! (str "asl: native build pid " pid " started for " root)))
              (code (mt (build! root cacheDir owner)
                      ((ok dir) (do (say! (str "asl: native build: " dir)) 0))
                      ((err e) (do (say! (str "asl: native build failed: " e)) 1))))
              (_ (pathRemove (str cacheDir "/tmp." pid)))
              (_ (releaseLock! cacheDir owner))]
          (do (say! (str "asl: native build pid " pid " exit " (stringFromInt64 code)))
              (ok code))))))
