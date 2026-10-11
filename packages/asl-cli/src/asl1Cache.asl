(module asl-cli/asl1Cache
  :x [nativeAsl1! singleFlight! bootstrap! buildNative! buildNativeTransaction! closure!]
  :i [(asl/packages/asl-cli/src/system :a sys)])

fn compilerPath! ctx: sys/Context -> String
  (optionOr (envGet "ASL_NATIVE_ASL1_SOURCE") (str ctx.root "/asl/packages/asl-compiler/src/asl1.asl"))

fn cacheDir! -> String
  (let [(configured (optionOr (envGet "ASL_NATIVE_ASL1_CACHE") ""))]
    (if (not (stringEmpty? configured))
      configured
      (str (optionOr (envGet "HOME") ".") "/.asl/run/asl1")))

fn entryDir! key: String -> String
  (str (cacheDir!) "/" key)

fn binaryPath! key: String -> String
  (str (entryDir! key) "/asl1-native")

fn keyPath! key: String -> String
  (str (entryDir! key) "/key")

fn depsPath! key: String -> String
  (str (entryDir! key) "/deps")

fn shaPath! key: String -> String
  (str (entryDir! key) "/sha256")

fn ! shaFile path: String -> (Result String String)
  (mt (fileReadBytes path)
    ((err e) (err (str "cannot hash " path ": " e)))
    ((ok bytes) (ok (bytesSha256 bytes))))

fn ! validBinary? path: String key: String -> Bool
  (and (mt (fileReadString (keyPath! key))
        ((err _) false)
        ((ok stored) (= stored key)))
    (mt (fileReadString (shaPath! key))
      ((err _) false)
      ((ok expected)
        (mt (shaFile path)
          ((err _) false)
          ((ok actual) (= (sys/stripTrailingNewlines expected) actual))))))

fn ! appendFileHash paths: (List String) acc: String -> (Result String String)
  (appendFileHashIn "" paths acc)

fn ! appendFileHashIn root: String paths: (List String) acc: String -> (Result String String)
  (mt (listHead paths)
    ((none) (ok acc))
    ((some path)
      (mt (shaFile (underRoot root path))
        ((err e) (err e))
        ((ok digest) (appendFileHashIn root (optionOr (listTail paths) (list)) (str acc path "=" digest "\n"))))))

fn underRoot root: String path: String -> String
  (if (or (stringEmpty? root) (stringStartsWith? path "/")) path (str root "/" path))

fn ! interpretedDeps! ctx: sys/Context compiler: String -> (Result String String)
  (mt (sys/capture! (list "nice" "-n" "15" ctx.hostBin "run" compiler "deps" compiler) (some ctx.root))
    ((err e) (err (str "cannot read asl1 dependency closure: " e)))
    ((ok captured)
      (if (!= captured.exitCode 0)
        (err (str "asl1 deps failed (exit " (stringFromInt64 captured.exitCode) ")"))
        (ok captured.stdout))))

fn ! versionLine clang: String -> (Result String String)
  (mt (sys/capture! (list "env" "TMPDIR=/tmp" clang "--version") (none))
    ((err e) (err (str "cannot query clang version: " e)))
    ((ok captured)
      (if (!= captured.exitCode 0)
        (err "clang --version failed")
        (ok (optionOr (listHead (stringLines captured.stdout)) "")))))

fn ! baseHashes compiler: String lib: String clangVersion: String -> (Result String String)
  (mt (appendFileHash (list compiler lib) "")
    ((err e) (err e))
    ((ok hashes) (ok (str hashes "clang=" clangVersion "\n"))))

fn headPath! base: String -> String
  (str (cacheDir!) "/head-" (bytesSha256 (stringToBytes base)))

fn ! makeKey closure: String base: String root: String -> (Result String String)
  (let [(deps (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines (sys/stripTrailingNewlines closure))))]
    (mt (appendFileHashIn root deps "")
      ((err e) (err e))
      ((ok hashes) (ok (bytesSha256 (stringToBytes (str hashes base)))))))

fn ! drop path: String -> Bool
  (if (not (fileExists? path)) true
    (mt (pathRemove path) ((ok _) true) ((err e) (do (sys/sayErr! (str "asl1 cache: cannot remove " path ": " e)) false))))

fn ! installNative! part: String binary: String keyTmp: String shaTmp: String depsTmp: String entry: String key: String closure: String -> (Result String String)
  (mt (shaFile part)
    ((err e) (do (drop part) (err e)))
    ((ok digest)
      (mt (fileWrite shaTmp (str digest "\n"))
        ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (err (str "cannot write native asl1 cache digest: " e))))
        ((ok _) (mt (fileWrite keyTmp key)
          ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot write native asl1 cache key: " e))))
          ((ok _) (mt (fileWrite depsTmp closure)
            ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot write native asl1 dependency manifest: " e))))
            ((ok _) (mt (pathRename part binary)
              ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot install native asl1 cache binary: " e))))
          ((ok _) (mt (pathRename keyTmp (str entry "/key"))
                ((err e) (do (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot install native asl1 cache key: " e))))
            ((ok _) (mt (pathRename depsTmp (str entry "/deps"))
                  ((err e) (do (drop depsTmp) (drop shaTmp) (err (str "cannot install native asl1 dependency manifest: " e))))
              ((ok _) (mt (pathRename shaTmp (str entry "/sha256"))
                    ((err e) (do (drop shaTmp) (err (str "cannot install native asl1 cache digest: " e))))
                    ((ok _) (ok binary)))))))))))))))))

fn bootstrap! previous: (Option String) seed: (Result String String) stage: Any install: Any -> (Result String String)
  (mt (mt previous ((some native) (ok native)) ((none) seed))
    ((err e) (err e))
    ((ok native)
  (mt (stage native)
    ((err e) (err e))
    ((ok stage1) (mt (stage stage1)
      ((err e) (err e))
      ((ok stage2) (install stage2)))))))

fn ! latestCachedBinary! -> (Option String)
  (mt (sys/capture! (list "ls" "-t" (cacheDir!)) (none))
    ((err _) (none))
    ((ok listing)
      (latestHeadBinary! (filter (fn [(name String)] -> Bool (stringStartsWith? name "head-")) (stringLines listing.stdout)))))

fn ! latestHeadBinary! heads: (List String) -> (Option String)
  (mt (listHead heads)
    ((none) (none))
    ((some headName)
      (mt (fileReadString (str (cacheDir!) "/" headName))
        ((err _) (latestHeadBinary! (optionOr (listTail heads) (list))))
        ((ok rawKey)
          (let [(key (sys/stripTrailingNewlines rawKey))]
            (if (usable? key) (some (binaryPath! key))
              (latestHeadBinary! (optionOr (listTail heads) (list)))))))))

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

fn ! bytesMatch? path: String bytes: String sha: String -> Bool
  (mt (fileReadBytes path)
    ((err _) false)
    ((ok b) (and (= (stringFromInt64 (bytesLength b)) bytes) (= (bytesSha256 b) sha))))

fn ! linkSeed! dir: String gz: String llBytes: String llSha: String lib: String clang: String -> (Result String String)
  (let [(tag (str (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (copy (str dir "/asl1." tag ".ll.gz"))
        (ll (str dir "/asl1." tag ".ll"))
        (part (str dir "/asl1-native.part." tag))
        (binary (str dir "/asl1-native"))]
    (mt (mt (fileReadBytes gz) ((err e) (err e)) ((ok b) (fileWrite copy b)))
      ((err e) (do (drop copy) (err (str "ERR_SEED_IO: cannot copy " gz ": " e))))
      ((ok _)
        (if (!= (sys/runMerged! (list "gzip" "-d" "-f" copy)) 0)
          (do (drop copy) (drop ll) (err (str "ERR_SEED_UNPACK: gzip -d " gz " failed")))
          (if (not (bytesMatch? ll llBytes llSha))
            (do (drop ll) (err (str "ERR_SEED_SHA: " gz " unpacks to IR whose size or sha256 differs from llBytes/llSha256")))
            (let [(linked (sys/runMerged! (list "nice" "-n" "15" clang "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" lib "-lm" "-o" part)))]
              (do (drop ll)
                (if (or (!= linked 0) (not (sys/isFile? part)))
                  (do (drop part) (err (str "ERR_SEED_LINK: clang could not link the seed (exit " (stringFromInt64 linked) ")")))
                  (mt (shaFile part)
                    ((err e) (do (drop part) (err e)))
                    ((ok digest) (mt (fileWrite (str part ".sha256") (str digest "\n"))
                      ((err e) (do (drop part) (err (str "ERR_SEED_IO: " e))))
                      ((ok _) (mt (pathRename (str part ".sha256") (str binary ".sha256"))
                        ((err e) (do (drop part) (err (str "ERR_SEED_IO: " e))))
                        ((ok _) (mt (pathRename part binary)
                          ((err e) (do (drop part) (err (str "ERR_SEED_IO: " e))))
                          ((ok _) (ok binary)))))))))))))))))

fn ! checkedInSeed! root: String lib: String clang: String -> (Result String String)
  (mt (sys/capture! (list "env" "TMPDIR=/tmp" clang "-dumpmachine") (none))
    ((err e) (err (str "ERR_SEED_CLANG: " e)))
    ((ok machine)
      (let [(key (seedTriple machine.stdout))]
        (mt (fileReadString (str root "/asl/seed/seed.asn"))
          ((err e) (err (str "ERR_NO_NATIVE_SEED: " root "/asl/seed/seed.asn: " e)))
          ((ok text) (mt (seedRow text key)
            ((none) (err (str "ERR_NO_NATIVE_SEED: no seed for " key " in asl/seed/seed.asn")))
            ((some row)
              (let [(file (optionOr (seedField row "file") ""))
                    (llSha (optionOr (seedField row "llSha256") ""))
                    (gz (str root "/" file))
                    (dir (str (cacheDir!) "/seed/" llSha))
                    (binary (str dir "/asl1-native"))]
                (cond
                  ((or (stringEmpty? file) (!= (stringLength llSha) 64)) (err (str "ERR_SEED_MANIFEST: the " key " row lacks :file or :llSha256")))
                  ((not (bytesMatch? gz (optionOr (seedField row "bytes") "") (optionOr (seedField row "sha256") ""))) (err (str "ERR_SEED_SHA: " file " does not match the size and sha256 in asl/seed/seed.asn")))
                  ((validSeed? binary) (ok binary))
                  (else (mt (dirCreate dir)
                    ((err e) (err (str "ERR_SEED_IO: cannot create " dir ": " e)))
                    ((ok _) (linkSeed! dir gz (optionOr (seedField row "llBytes") "") llSha lib clang)))))))))))))

fn ! validSeed? path: String -> Bool
  (mt (fileReadString (str path ".sha256"))
    ((err _) false)
    ((ok expected) (mt (shaFile path)
      ((err _) false)
      ((ok actual) (= (sys/stripTrailingNewlines expected) actual)))))

fn ! ensureSeed! root: String lib: String clang: String -> (Result String String)
  (mt (envGet "ASL_NATIVE_ASL1_SEED")
    ((some pinned) (if (validSeed? pinned) (ok pinned) (err "ERR_NO_NATIVE_SEED")))
    ((none) (checkedInSeed! root lib clang)))

fn staleSeed reason: String -> String
  (str "ERR_SEED_STALE: the bootstrap seed cannot build the compiler sources (" reason "); regenerate it with asl-host run tools/seed.asl regen")

fn ! nativeStage! compiler: String source: String lib: String clang: String -> (Result String String)
  (let [(ll (str compiler ".boot.ll"))
        (part (str compiler ".boot.native"))
        (compiled (sys/run! (list "nice" "-n" "15" compiler "build" source "-o" ll)))
        (inputCleanup (if (stringContains? compiler ".boot.native") (drop compiler) true))]
    (if (!= compiled 0)
      (do (drop ll) (drop part) (err (str "native asl1 stage failed (exit " (stringFromInt64 compiled) ")")))
      (let [(linked (sys/runMerged! (list "nice" "-n" "15" clang "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" lib "-lm" "-o" part)))]
        (do (drop ll)
          (if (or (!= linked 0) (not (sys/isFile? part)))
            (do (drop part) (err (str "clang could not link native asl1 (exit " (stringFromInt64 linked) ")")))
            (ok part))))))

fn fromSeed! seed: String stage: Any install: Any -> (Result String String)
  (bootstrap! (none) (ok seed) (fn [(c String)] -> (Result String String)
                                  (mt (stage c) ((ok s) (ok s)) ((err e) (err (if (= c seed) (staleSeed e) e)))))
              install)

fn buildNative! previousFn: Any seedFn: Any stage: Any install: Any -> (Result String String)
  (let [(previous (previousFn))]
    (mt previous
      ((some _) (mt (bootstrap! previous (err "unused seed: cached native compiler selected") stage install)
        ((ok binary) (ok binary))
        ((err first) (mt (seedFn previous)
          ((err e) (err (str first "; " e)))
          ((ok seed) (mt (fromSeed! seed stage install)
            ((ok binary) (ok binary))
            ((err e) (err (str first "; retried from the seed: " e)))))))))
      ((none) (mt (seedFn previous)
        ((err e) (err e))
        ((ok seed) (fromSeed! seed stage install))))))

fn buildNativeTransaction! root: String key: String closure: String previousFn: Any seedFn: Any stage: Any -> (Result String String)
  (let [(entry (str root "/" key))
        (binary (str entry "/asl1-native"))
        (part (str binary ".part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (keyTmp (str entry "/key.part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (shaTmp (str entry "/sha256.part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (depsTmp (str entry "/deps.part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))]
    (buildNative! previousFn seedFn stage
          (fn [(stage2 String)] -> (Result String String)
            (mt (pathRename stage2 part)
              ((err e) (err (str "cannot stage bootstrapped native asl1: " e)))
              ((ok _) (installNative! part binary keyTmp shaTmp depsTmp entry key closure))))))

fn ! lockOwnerAlive? lockPath: String -> (Result Bool String)
  (mt (fileReadString lockPath)
    ((err e) (err (str "ERR_ASL1_CACHE_OWNER_READ: " e)))
    ((ok metadata)
      (mt (listHead (stringLines metadata))
        ((none) (err "ERR_ASL1_CACHE_OWNER_METADATA: missing owner PID"))
        ((some pidText)
          (mt (stringToInt64 pidText)
            ((none) (err "ERR_ASL1_CACHE_OWNER_METADATA: malformed owner PID"))
            ((some pid)
              (mt (procAlive? pid)
                ((err e) (err (str "ERR_ASL1_CACHE_OWNER_LIVENESS: " e)))
                ((ok alive) (ok alive)))))))))

fn ! closeGuard! fd: Int64 result: (Result Bool String) -> (Result Bool String)
  (mt (fdClose fd)
    ((err closeErr) (mt result
      ((err e) (err (str e "; takeover guard close failed: " closeErr)))
      ((ok _) (err (str "ERR_ASL1_CACHE_GUARD_CLOSE: " closeErr)))))
    ((ok _) result))

fn ! createOwnedLock! lockPath: String -> (Result Bool String)
  (mt (fileCreateExclusive lockPath (str (stringFromInt64 (procSelf)) "\n" (stringFromInt64 (nowNs)) "\n"))
    ((ok _) (ok true))
    ((err e) (if (stringContains? e "alreadyExists") (ok false) (err (str "ERR_ASL1_CACHE_LOCK: " e)))))

fn ! withTakeoverGuard! lockPath: String timeoutMs: Int64 -> (Result Bool String)
  (let [(guardPath (str lockPath ".takeover"))]
    (mt (fileLockWait guardPath true timeoutMs)
      ((err e) (err (str "ERR_ASL1_CACHE_GUARD: " e)))
      ((ok fd)
        (let [(attempt (createOwnedLock! lockPath))]
          (mt attempt
            ((err e) (closeGuard! fd (err e)))
            ((ok created)
              (if created
                (closeGuard! fd (ok true))
                (mt (lockOwnerAlive? lockPath)
                  ((err e) (closeGuard! fd (err e)))
                  ((ok alive)
                    (if alive
                      (closeGuard! fd (ok false))
                      (mt (pathRemove lockPath)
                        ((err e) (closeGuard! fd (err (str "ERR_ASL1_CACHE_STALE_REMOVE: " e))))
                        ((ok _) (mt (createOwnedLock! lockPath)
                          ((err e) (closeGuard! fd (err e)))
                          ((ok taken) (closeGuard! fd (ok taken))))))))))))))))
fn ! singleFlightLoop! lockPath: String artifactPath: String timeoutMs: Int64 startNs: Int64 readyFn: Any builder: Any -> (Result String String)
  (if (readyFn)
    (ok artifactPath)
    (let [(elapsedMs (/ (- (monotonicNs) startNs) 1000000))
          (remainingMs (if (< timeoutMs 0) -1 (- timeoutMs elapsedMs)))]
      (if (and (>= timeoutMs 0) (>= elapsedMs timeoutMs))
        (err (str "ERR_ASL1_CACHE_LOCK_TIMEOUT: " lockPath))
        (mt (withTakeoverGuard! lockPath remainingMs)
        ((err e) (if (and (>= timeoutMs 0) (>= (/ (- (monotonicNs) startNs) 1000000) timeoutMs))
          (err (str "ERR_ASL1_CACHE_LOCK_TIMEOUT: " lockPath))
          (err e)))
        ((ok acquired)
          (if acquired
            (let [(result (if (readyFn) (ok artifactPath) (builder)))
                  (removed (pathRemove lockPath))]
              (mt removed
                ((err e) (mt result
                  ((err original) (err (str original "; lock cleanup failed: " e)))
                  ((ok _) (err (str "ERR_ASL1_CACHE_LOCK_REMOVE: " e)))))
                ((ok _) result)))
            (do (sleepMs 10) (singleFlightLoop! lockPath artifactPath timeoutMs startNs readyFn builder))))))))

fn singleFlight! lockPath: String artifactPath: String timeoutMs: Int64 readyFn: Any builder: Any -> (Result String String)
  (let [(boundedTimeoutMs (if (< timeoutMs 0) 0 timeoutMs))]
    (singleFlightLoop! lockPath artifactPath boundedTimeoutMs (monotonicNs) readyFn builder))

fn ! usable? key: String -> Bool
  (let [(binary (binaryPath! key))]
    (and (sys/isFile? binary) (and (sys/executable? binary) (validBinary? binary key))))

fn ! warmBinary! base: String root: String -> (Option String)
  (mt (fileReadString (headPath! base))
    ((err _) (none))
    ((ok key)
      (mt (fileReadString (depsPath! key))
        ((err _) (none))
        ((ok closure)
          (mt (makeKey closure base root)
            ((err _) (none))
            ((ok actual) (if (and (= actual key) (usable? key)) (some (binaryPath! key)) (none))))))))

fn ! writeHead! base: String key: String -> Bool
  (let [(head (headPath! base))
        (part (str head ".part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))]
    (mt (fileWrite part key)
      ((err e) (do (drop part) (sys/sayErr! (str "asl1 cache: cannot write head " part ": " e)) false))
      ((ok _) (mt (pathRename part head)
        ((err e) (do (drop part) (sys/sayErr! (str "asl1 cache: cannot install head " head ": " e)) false))
        ((ok _) true)))))

fn rootRelative root: String line: String -> String
  (if (stringStartsWith? line (str root "/")) (optionOr (stringSlice line (+ (stringLength root) 1) (stringLength line)) line) line)

fn ! nativeDeps! root: String native: String compiler: String -> (Result String String)
  (mt (sys/capture! (list "nice" "-n" "15" native "deps" compiler) (none))
    ((err e) (err (str "cannot run " native " deps: " e)))
    ((ok captured)
      (if (!= captured.exitCode 0)
        (err (str "native asl1 deps failed (exit " (stringFromInt64 captured.exitCode) ")"))
        (let [(real (resultOr (realPath root) root))
              (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines captured.stdout)))]
          (ok (stringJoin (map (fn [(l String)] -> String (rootRelative real (rootRelative root l))) lines) "\n"))))))

fn ! traceErr! line: String -> Bool
  (if (= (optionOr (envGet "ASL_NATIVE_TRACE") "") "1") (sys/sayErr! line) true)

fn ! closure! ctx: sys/Context compiler: String lib: String clang: String -> (Result String String)
  (mt (latestCachedBinary!)
    ((none) (interpretedDeps! ctx compiler))
    ((some b) (mt (nativeDeps! ctx.root b compiler)
      ((ok listing) (ok listing))
      ((err why) (do (traceErr! (str "asl1 cache: no native asl1 (" why "); asl-host reads the asl1 closure to bootstrap")) (interpretedDeps! ctx compiler))))))

fn ! coldBinary! ctx: sys/Context compiler: String lib: String clang: String base: String -> (Result String String)
  (mt (closure! ctx compiler lib clang)
    ((err e) (err e))
    ((ok closure) (mt (makeKey closure base ctx.root)
      ((err e) (err e))
      ((ok key) (mt (dirCreate (entryDir! key))
        ((err e) (err (str "cannot create keyed cache directory: " e)))
        ((ok _) (mt (singleFlight!
          (str (entryDir! key) "/build.lock")
          (binaryPath! key)
          3600000
          (fn [] (usable? key))
          (fn [] (buildNativeTransaction! (cacheDir!) key closure (fn [] (latestCachedBinary!)) (fn [(cached (Option String))] -> (Result String String)
            (ensureSeed! ctx.root lib clang))
            (fn [(native String)] -> (Result String String) (nativeStage! native compiler lib clang)))))
          ((err e) (err e))
          ((ok binary) (do (writeHead! base key) (ok binary))))))))))

fn ! nativeAsl1! ctx: sys/Context lib: String clang: String -> (Result String String)
  (let [(compiler (compilerPath! ctx))
        (disabled (= (optionOr (envGet "ASL_NATIVE_ASL1") "") "0"))]
    (if disabled
      (err "native compiler cache disabled by ASL_NATIVE_ASL1=0")
      (mt (dirCreate (cacheDir!))
        ((err e) (err (str "cannot create cache directory " (cacheDir!) ": " e)))
        ((ok _) (mt (versionLine clang)
          ((err e) (err e))
          ((ok version) (mt (baseHashes compiler lib version)
            ((err e) (err e))
            ((ok base) (mt (warmBinary! base ctx.root)
              ((some binary) (ok binary))
              ((none) (coldBinary! ctx compiler lib clang base)))))))))))
