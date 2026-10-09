(module asl-cli/asl1Cache
  :x [nativeAsl1! singleFlight! bootstrap! buildNative! buildNativeTransaction!]
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
  (mt (listHead paths)
    ((none) (ok acc))
    ((some path)
      (mt (shaFile path)
        ((err e) (err e))
        ((ok digest) (appendFileHash (optionOr (listTail paths) (list)) (str acc path "=" digest "\n"))))))

fn ! interpretedDeps! ctx: sys/Context compiler: String -> (Result String String)
  (mt (sys/capture! (list "nice" "-n" "15" ctx.hostBin "run" compiler "deps" compiler) (none))
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

fn ! makeKey closure: String base: String -> (Result String String)
  (let [(deps (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines (sys/stripTrailingNewlines closure))))]
    (mt (appendFileHash deps "")
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

fn ! seedPath! -> String
  (optionOr (envGet "ASL_NATIVE_ASL1_SEED") (str (optionOr (envGet "HOME") ".") "/.asl/run/asl1/seed/asl1-native"))

fn ! validSeed? path: String -> Bool
  (mt (fileReadString (str path ".sha256"))
    ((err _) false)
    ((ok expected) (mt (shaFile path)
      ((err _) false)
      ((ok actual) (= (sys/stripTrailingNewlines expected) actual)))))

fn ! pinSeed! cached: String -> (Result String String)
  (let [(seed (seedPath!))]
    (if (validSeed? seed) (ok seed)
      (mt (dirCreate (sys/parentOf seed))
        ((err e) (err (str "cannot create native asl1 seed directory: " e)))
        ((ok _) (let [(status (sys/runMerged! (list "cp" cached seed)))]
          (if (!= status 0) (err (str "cannot pin native asl1 seed (exit " (stringFromInt64 status) ")"))
            (mt (shaFile seed)
              ((err e) (do (drop seed) (err e)))
              ((ok digest) (mt (fileWrite (str seed ".sha256") (str digest "\n"))
                ((err e) (do (drop seed) (err e)))
                ((ok _) (ok seed)))))))))))

fn ! ensureSeed! -> (Result String String)
  (let [(seed (seedPath!))]
    (if (validSeed? seed) (ok seed)
      (mt (latestCachedBinary!)
        ((none) (err "ERR_NO_NATIVE_SEED"))
        ((some cached) (pinSeed! cached)))))

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

fn buildNative! previousFn: Any seedFn: Any stage: Any install: Any -> (Result String String)
  (let [(previous (previousFn))]
    (mt previous
      ((some _) (mt (seedFn previous)
        ((err e) (err e))
        ((ok _) (bootstrap! previous (err "unused seed: cached native compiler selected") stage install))))
      ((none) (mt (seedFn previous)
        ((err e) (err e))
        ((ok seed) (bootstrap! previous (ok seed) stage install))))))

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

fn ! warmBinary! base: String -> (Option String)
  (mt (fileReadString (headPath! base))
    ((err _) (none))
    ((ok key)
      (mt (fileReadString (depsPath! key))
        ((err _) (none))
        ((ok closure)
          (mt (makeKey closure base)
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

fn ! coldBinary! ctx: sys/Context compiler: String lib: String clang: String base: String -> (Result String String)
  (mt (interpretedDeps! ctx compiler)
    ((err e) (err e))
    ((ok closure) (mt (makeKey closure base)
      ((err e) (err e))
      ((ok key) (mt (dirCreate (entryDir! key))
        ((err e) (err (str "cannot create keyed cache directory: " e)))
        ((ok _) (mt (singleFlight!
          (str (entryDir! key) "/build.lock")
          (binaryPath! key)
          3600000
          (fn [] (usable? key))
          (fn [] (buildNativeTransaction! (cacheDir!) key closure (fn [] (latestCachedBinary!)) (fn [(cached (Option String))] -> (Result String String)
            (mt cached ((some binary) (pinSeed! binary)) ((none) (ensureSeed!))))
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
            ((ok base) (mt (warmBinary! base)
              ((some binary) (ok binary))
              ((none) (coldBinary! ctx compiler lib clang base)))))))))))
