(module asl-cli/asl1Cache
  :x [memoSha! memoShaIn! statFacts! notraceLib! nativeAsl1! singleFlight! bootstrap! buildNative! buildNativeTransaction! closure!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl-parser/ast :a a) (asl-checker/resolve :a r) (asl/packages/asl-cli/src/nativeBuild :a nb)])

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

fn ! hashBytes path: String -> (Result String String)
  (match (fileReadBytes path)
    ((err e) (err (str "cannot hash " path ": " e)))
    ((ok bytes) (ok (bytesSha256 bytes))))

; (:m :ref WARMBUILD-DIGEST-STAMP-20261025 :do "sha256 in ASL costs about 380 instructions a byte, and a warm build hashed the 20 MB cached compiler plus 55 dependency files (8.7e9 of 28.1e9 instructions, 55% of sampled CPU). A digest is remembered beside the cache as 'dev ino ctime mtime size digest' under the sha256 of the real path and reused only while all five facts are unchanged (git-index style): touch -r, cp -p then mv, a retargeted symlink or an archive extraction keep mtime and size but change ino or ctime. The facts come from one batched stat(1) spawn (BSD -f or GNU -c form); FileStat has no ino/dev/ctime, and a field added to the compiler's own record cannot be used by asl-cli until the seed asl1 knows it. A failed spawn means no stamps, every file is hashed. Git's racy rule: a file with mtime or ctime within racyNs of now is never remembered. The stored digest must be 64 lowercase hex. Returns the digest and whether the stamp answered")
fn racyNs -> Int64
  2000000000

fn stampFile stampDir: String path: String -> String
  (str stampDir "/" (bytesSha256 (stringToBytes (resultOr (realPath path) path))))

fn hexChar? c: String -> Bool
  (some? (stringIndexOf "0123456789abcdef" c))

fn hex64? s: String -> Bool
  (and (= (stringLength s) 64) (= (listLength (filter hexChar? (stringChars s))) 64))

fn nsOfSeconds s: String -> Int64
  (optionOr (stringToInt64 (stringReplace s "." "")) 9000000000000000000)

fn racyFacts? facts: String window: Int64 -> Bool
  (let [(parts (stringSplit facts " "))
        (limit (- (nowNs) window))]
    (or (!= (listLength parts) 5)
      (or (>= (nsOfSeconds (optionOr (listGet parts 2) "")) limit)
          (>= (nsOfSeconds (optionOr (listGet parts 3) "")) limit))))

fn ! statLines! flags: (List String) paths: (List String) -> (Option (List String))
  (match (sys/capture! (listAppend (cons "stat" flags) (cons "--" paths)) (none))
    ((err _) (none))
    ((ok c) (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines c.stdout)))]
      (if (and (= c.exitCode 0) (= (listLength lines) (listLength paths))) (some lines) (none)))))

fn ! statFacts! paths: (List String) -> (List String)
  (if (listEmpty? paths) (list)
    (match (statLines! (list "-c" "%d %i %.9Z %.9Y %s") paths)
      ((some lines) lines)
      ((none) (match (statLines! (list "-f" "%d %i %Fc %Fm %z") paths)
        ((some lines) lines)
        ((none) (map (fn [(p String)] -> String "") paths))))))

fn ! sweepParts! stampDir: String -> Bool
  (let [(old (- (nowNs) 86400000000000))]
    (do (map (fn [(n String)] -> Bool
          (if (stringContains? n ".part.")
            (match (fileStat (str stampDir "/" n)) ((ok st) (if (< st.mtimeNs old) (ok? (pathRemove (str stampDir "/" n))) false)) ((err _) false))
            false))
        (resultOr (dirList stampDir) (list)))
        true))

fn ! recordStamp! stampDir: String path: String facts: String digest: String -> Bool
  (let [(file (stampFile stampDir path))
        (part (str file ".part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))]
    (match (dirCreate stampDir)
      ((err _) false)
      ((ok _) (do (sweepParts! stampDir) (match (fileWrite part (str facts " " digest "\n"))
        ((err _) (do (drop part) false))
        ((ok _) (match (pathRename part file)
          ((err _) (do (drop part) false))
          ((ok _) true))))))))

fn ! memoSha! stampDir: String path: String facts: String -> (Result (Pair String Bool) String)
  (memoShaIn! stampDir path facts (racyNs))

fn ! memoShaIn! stampDir: String path: String facts: String window: Int64 -> (Result (Pair String Bool) String)
  (let [(stored (sys/stripTrailingNewlines (resultOr (fileReadString (stampFile stampDir path)) "")))
        (want (str facts " "))
        (storedDigest (optionOr (stringSlice stored (stringLength want) (stringLength stored)) ""))]
    (if (and (not (stringEmpty? facts)) (and (stringStartsWith? stored want) (hex64? storedDigest)))
      (ok (pair storedDigest true))
      (match (hashBytes path)
        ((err e) (err e))
        ((ok digest)
          (do (if (and (not (stringEmpty? facts)) (not (racyFacts? facts window))) (recordStamp! stampDir path facts digest) false)
              (ok (pair digest false)))))))

fn ! stampDir! -> String
  (str (cacheDir!) ".stamps")

fn ! shaFile path: String -> (Result String String)
  (match (memoSha! (stampDir!) path (optionOr (listHead (statFacts! (list path))) ""))
    ((err e) (err e))
    ((ok hit) (ok (pairFirst hit))))

fn ! validBinary? path: String key: String -> Bool
  (and (match (fileReadString (keyPath! key))
        ((err _) false)
        ((ok stored) (= stored key)))
    (match (fileReadString (shaPath! key))
      ((err _) false)
      ((ok expected)
        (match (shaFile path)
          ((err _) false)
          ((ok actual) (= (sys/stripTrailingNewlines expected) actual))))))

fn ! appendFileHash paths: (List String) acc: String -> (Result String String)
  (appendFileHashIn "" paths acc)

fn ! appendFileHashIn root: String paths: (List String) acc: String -> (Result String String)
  (appendHashes root paths (statFacts! (map (fn [(p String)] -> String (underRoot root p)) paths)) acc)

fn ! appendHashes root: String paths: (List String) facts: (List String) acc: String -> (Result String String)
  (match (listHead paths)
    ((none) (ok acc))
    ((some path)
      (match (memoSha! (stampDir!) (underRoot root path) (optionOr (listHead facts) ""))
        ((err e) (err e))
        ((ok hit) (appendHashes root (optionOr (listTail paths) (list)) (optionOr (listTail facts) (list)) (str acc path "=" (pairFirst hit) "\n"))))))

fn underRoot root: String path: String -> String
  (if (or (stringEmpty? root) (stringStartsWith? path "/")) path (str root "/" path))

fn distinctSorted xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (optionOr (listHead acc) "") x) acc (cons x acc))) (list) (listSort xs)))

; (:m :ref SNAPSHOT-HOST-ABSENT-BUILD-HOSTBIN :do "HL-C: asl1.asl's own 'deps' verb (asl-compiler/src/asl1.asl's deps fn) used to be the only way to compute the asl1 dependency closure for cache-keying, and it only ran interpreted through the deleted stage-0 host (ctx.hostBin); this walks the same closure in-process, with the same resolver (asl-checker/resolve's collectSummary/loadModuleDeps!) asl1.asl itself uses, so no process -- host or native -- needs to exist yet for a cold cache to key itself")
fn ! interpretedDeps! ctx: sys/Context compiler: String -> (Result String String)
  (match (fileReadString compiler)
    ((err e) (err (str "cannot read asl1 dependency closure: " e)))
    ((ok src)
      (match (a/parse src)
        ((err pe) (err (str "cannot read asl1 dependency closure: " compiler ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": parse error " pe.msg)))
        ((ok forms)
          (let [(summary (r/collectSummary forms compiler))
                (root (resultOr (realPath ctx.root) ctx.root))]
            (match (r/loadModuleDeps! (cons (r/parentDirOf compiler) (list ctx.root)) (r/mapValuesList summary.imports))
              ((err _) (err "cannot read asl1 dependency closure: its imports do not load"))
              ((ok closure)
                (let [(absPaths (filter (fn [(k String)] -> Bool (stringStartsWith? k "/")) (mapKeys closure)))
                      (relPaths (map (fn [(p String)] -> String (rootRelative root p)) absPaths))]
                  (ok (stringJoin (distinctSorted relPaths) "\n"))))))))))

fn ! versionLine clang: String -> (Result String String)
  (match (sys/capture! (list "env" "TMPDIR=/tmp" clang "--version") (none))
    ((err e) (err (str "cannot query clang version: " e)))
    ((ok captured)
      (if (!= captured.exitCode 0)
        (err "clang --version failed")
        (ok (optionOr (listHead (stringLines captured.stdout)) "")))))

fn ! baseHashes compiler: String lib: String clangVersion: String -> (Result String String)
  (match (appendFileHash (list compiler lib) "")
    ((err e) (err e))
    ((ok hashes) (ok (str hashes "clang=" clangVersion "\nrc=notrace\n"))))

fn headPath! base: String -> String
  (str (cacheDir!) "/head-" (bytesSha256 (stringToBytes base)))

fn ! makeKey closure: String base: String root: String -> (Result String String)
  (let [(deps (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines (sys/stripTrailingNewlines closure))))]
    (match (appendFileHashIn root deps "")
      ((err e) (err e))
      ((ok hashes) (ok (bytesSha256 (stringToBytes (str hashes base)))))))

fn ! drop path: String -> Bool
  (if (not (fileExists? path)) true
    (match (pathRemove path) ((ok _) true) ((err e) (do (sys/sayErr! (str "asl1 cache: cannot remove " path ": " e)) false))))

fn ! installNative! part: String binary: String keyTmp: String shaTmp: String depsTmp: String entry: String key: String closure: String -> (Result String String)
  (match (shaFile part)
    ((err e) (do (drop part) (err e)))
    ((ok digest)
      (match (fileWrite shaTmp (str digest "\n"))
        ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (err (str "cannot write native asl1 cache digest: " e))))
        ((ok _) (match (fileWrite keyTmp key)
          ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot write native asl1 cache key: " e))))
          ((ok _) (match (fileWrite depsTmp closure)
            ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot write native asl1 dependency manifest: " e))))
            ((ok _) (match (pathRename part binary)
              ((err e) (do (drop part) (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot install native asl1 cache binary: " e))))
          ((ok _) (match (pathRename keyTmp (str entry "/key"))
                ((err e) (do (drop keyTmp) (drop shaTmp) (drop depsTmp) (err (str "cannot install native asl1 cache key: " e))))
            ((ok _) (match (pathRename depsTmp (str entry "/deps"))
                  ((err e) (do (drop depsTmp) (drop shaTmp) (err (str "cannot install native asl1 dependency manifest: " e))))
              ((ok _) (match (pathRename shaTmp (str entry "/sha256"))
                    ((err e) (do (drop shaTmp) (err (str "cannot install native asl1 cache digest: " e))))
                    ((ok _) (ok binary)))))))))))))))))

fn bootstrap! previous: (Option String) seed: (Result String String) stage: Any install: Any -> (Result String String)
  (match (match previous ((some native) (ok native)) ((none) seed))
    ((err e) (err e))
    ((ok native)
  (match (stage native)
    ((err e) (err e))
    ((ok stage1) (match (stage stage1)
      ((err e) (err e))
      ((ok stage2) (install stage2)))))))

fn ! latestCachedBinary! -> (Option String)
  (match (sys/capture! (list "ls" "-t" (cacheDir!)) (none))
    ((err _) (none))
    ((ok listing)
      (latestHeadBinary! (filter (fn [(name String)] -> Bool (stringStartsWith? name "head-")) (stringLines listing.stdout)))))

fn ! latestHeadBinary! heads: (List String) -> (Option String)
  (match (listHead heads)
    ((none) (none))
    ((some headName)
      (match (fileReadString (str (cacheDir!) "/" headName))
        ((err _) (latestHeadBinary! (optionOr (listTail heads) (list))))
        ((ok rawKey)
          (let [(key (sys/stripTrailingNewlines rawKey))]
            (cond
              ((usable? key) (some (binaryPath! key)))
              ((usableTracing? key) (some (str (entryDir! key) "-tracing/asl1-native")))
              (else (latestHeadBinary! (optionOr (listTail heads) (list))))))))))

; (:m :ref TOOLNT :do "a tracing fallback entry is a valid prior compiler for the next bootstrap, but never satisfies usable? for the notrace key, so asl build keeps retrying the notrace stage")
fn ! usableTracing? key: String -> Bool
  (let [(dir (str (entryDir! key) "-tracing")) (binary (str dir "/asl1-native"))]
    (and (sys/isFile? binary)
      (and (sys/executable? binary)
        (match (fileReadString (str dir "/sha256"))
          ((err _) false)
          ((ok expected) (match (shaFile binary)
            ((err _) false)
            ((ok actual) (= (sys/stripTrailingNewlines expected) actual))))))))

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
  (match (fileReadBytes path)
    ((err _) false)
    ((ok b) (and (= (stringFromInt64 (bytesLength b)) bytes) (= (bytesSha256 b) sha))))

fn ! linkSeed! dir: String gz: String llBytes: String llSha: String lib: String clang: String -> (Result String String)
  (let [(tag (str (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (copy (str dir "/asl1." tag ".ll.gz"))
        (ll (str dir "/asl1." tag ".ll"))
        (part (str dir "/asl1-native.part." tag))
        (binary (str dir "/asl1-native"))]
    (match (match (fileReadBytes gz) ((err e) (err e)) ((ok b) (fileWrite copy b)))
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
                  (match (shaFile part)
                    ((err e) (do (drop part) (err e)))
                    ((ok digest) (match (fileWrite (str part ".sha256") (str digest "\n"))
                      ((err e) (do (drop part) (err (str "ERR_SEED_IO: " e))))
                      ((ok _) (match (pathRename (str part ".sha256") (str binary ".sha256"))
                        ((err e) (do (drop part) (err (str "ERR_SEED_IO: " e))))
                        ((ok _) (match (pathRename part binary)
                          ((err e) (do (drop part) (err (str "ERR_SEED_IO: " e))))
                          ((ok _) (ok binary)))))))))))))))))

fn ! checkedInSeed! root: String lib: String clang: String -> (Result String String)
  (match (sys/capture! (list "env" "TMPDIR=/tmp" clang "-dumpmachine") (none))
    ((err e) (err (str "ERR_SEED_CLANG: " e)))
    ((ok machine)
      (let [(key (seedTriple machine.stdout))]
        (match (fileReadString (str root "/asl/seed/seed.asn"))
          ((err e) (err (str "ERR_NO_NATIVE_SEED: " root "/asl/seed/seed.asn: " e)))
          ((ok text) (match (seedRow text key)
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
                  (else (match (dirCreate dir)
                    ((err e) (err (str "ERR_SEED_IO: cannot create " dir ": " e)))
                    ((ok _) (linkSeed! dir gz (optionOr (seedField row "llBytes") "") llSha lib clang)))))))))))))

fn ! validSeed? path: String -> Bool
  (match (fileReadString (str path ".sha256"))
    ((err _) false)
    ((ok expected) (match (shaFile path)
      ((err _) false)
      ((ok actual) (= (sys/stripTrailingNewlines expected) actual)))))

fn ! ensureSeed! root: String lib: String clang: String -> (Result String String)
  (match (envGet "ASL_NATIVE_ASL1_SEED")
    ((some pinned) (if (validSeed? pinned) (ok pinned) (err "ERR_NO_NATIVE_SEED")))
    ((none) (checkedInSeed! root lib clang)))

; (:m :ref HL-FIXWAVE :do "this message told the reader to regenerate the seed with asl-host, retired for good by HL-DELETE; bin/asl is the only runner left")
fn staleSeed reason: String -> String
  (str "ERR_SEED_STALE: the bootstrap seed cannot build the compiler sources (" reason "); regenerate it with bin/asl run asl/tools/seed.asl regen")

; (:m :ref TOOLNT :do "the native asl1 stages are compiled with --rc notrace and linked against the untraced runtime, built once per clang and runtime sources by the stage binary itself and cached under the asl1 cache's rt directory; a tracing build needed 18.1 s and 2.18 GB for the same self-compile that notrace does in 12.3 s and 1.15 GB")
fn ! notraceLib! compiler: String root: String lib: String clang: String -> (Result String String)
  (match (versionLine clang)
    ((err e) (err e))
    ((ok version)
      (let [(dir (str (cacheDir!) "/rt")) (_ (dirCreate (cacheDir!)))]
        (match (dirCreate dir)
          ((err e) (err (str "cannot create " dir ": " e)))
          ((ok _) (nb/notraceRuntime! (nb/Build :root root :cache dir :tmp dir :lib lib :base "" :clangVersion version :owner "" :deadlineNs (+ (monotonicNs) 1800000000000) :maxDesc 32)
                                      compiler (str root "/asl/packages")))))))

fn ! nativeStage! compiler: String source: String root: String lib: String clang: String -> (Result String String)
  (match (notraceLib! compiler root lib clang)
    ((ok ntLib) (stageWith! compiler source ntLib clang (list "--rc" "notrace")))
    ((err why) (do (sys/sayErr! (str "(:receipt :rc tracing :reason \"notrace runtime unavailable: " (stringReplace why "\"" "'") "\" :effect \"this asl1 is a tracing build, cached beside the notrace key and rebuilt on the next call\")"))
                   (match (stageWith! compiler source lib clang (list))
                     ((err e) (err e))
                     ((ok part) (match (fileWrite (str part ".tracing") "tracing\n")
                       ((err e) (do (drop part) (err (str "cannot mark the tracing stage: " e))))
                       ((ok _) (ok part))))))))

fn ! stageWith! compiler: String source: String lib: String clang: String rcArgs: (List String) -> (Result String String)
  (let [(ll (str compiler ".boot.ll"))
        (part (str compiler ".boot.native"))
        (compiled (sys/run! (listAppend (list "nice" "-n" "15" compiler "build" source "-o" ll) rcArgs)))
        (inputCleanup (if (stringContains? compiler ".boot.native") (and (drop compiler) (drop (str compiler ".tracing"))) true))]
    (if (!= compiled 0)
      (do (drop ll) (drop part) (err (str "native asl1 stage failed (exit " (stringFromInt64 compiled) ")")))
      (let [(linked (sys/runMerged! (list "nice" "-n" "15" clang "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" lib "-lm" "-o" part)))]
        (do (drop ll)
          (if (or (!= linked 0) (not (sys/isFile? part)))
            (do (drop part) (err (str "clang could not link native asl1 (exit " (stringFromInt64 linked) ")")))
            (ok part))))))

fn fromSeed! seed: String stage: Any install: Any -> (Result String String)
  (bootstrap! (none) (ok seed) (fn [(c String)] -> (Result String String)
                                  (match (stage c) ((ok s) (ok s)) ((err e) (err (if (= c seed) (staleSeed e) e)))))
              install)

fn buildNative! previousFn: Any seedFn: Any stage: Any install: Any -> (Result String String)
  (let [(previous (previousFn))]
    (match previous
      ((some _) (match (bootstrap! previous (err "unused seed: cached native compiler selected") stage install)
        ((ok binary) (ok binary))
        ((err first) (match (seedFn previous)
          ((err e) (err (str first "; " e)))
          ((ok seed) (match (fromSeed! seed stage install)
            ((ok binary) (ok binary))
            ((err e) (err (str first "; retried from the seed: " e)))))))))
      ((none) (match (seedFn previous)
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
            (installStage! stage2 part binary keyTmp shaTmp depsTmp entry key closure))))

; (:m :ref TOOLNT :do "a stage that fell back to the tracing runtime is installed under <key>-tracing with rc=tracing, never under the notrace key, so usable? stays false for the key and the next call rebuilds the notrace stage; a notrace stage writes rc=notrace next to its binary")
fn ! installStage! stage2: String part: String binary: String keyTmp: String shaTmp: String depsTmp: String entry: String key: String closure: String -> (Result String String)
  (let [(tracing (fileExists? (str stage2 ".tracing")))
        (dir (if tracing (str entry "-tracing") entry))
        (rel (fn [(path String)] -> String (str dir (optionOr (stringSlice path (stringLength entry) (stringLength path)) ""))))
        (made (if tracing (do (drop (str stage2 ".tracing")) (dirCreate dir)) (ok ())))]
    (match made
      ((err e) (err (str "cannot create the tracing stage dir: " e)))
      ((ok _) (match (pathRename stage2 (rel part))
        ((err e) (err (str "cannot stage bootstrapped native asl1: " e)))
        ((ok _) (match (installNative! (rel part) (rel binary) (rel keyTmp) (rel shaTmp) (rel depsTmp) dir key closure)
          ((err e) (err e))
          ((ok installed) (match (fileWrite (str dir "/rc") (if tracing "tracing\n" "notrace\n"))
            ((err e) (err (str "cannot write the rc marker: " e)))
            ((ok _) (ok installed))))))))))

fn ! lockOwnerAlive? lockPath: String -> (Result Bool String)
  (match (fileReadString lockPath)
    ((err e) (err (str "ERR_ASL1_CACHE_OWNER_READ: " e)))
    ((ok metadata)
      (match (listHead (stringLines metadata))
        ((none) (err "ERR_ASL1_CACHE_OWNER_METADATA: missing owner PID"))
        ((some pidText)
          (match (stringToInt64 pidText)
            ((none) (err "ERR_ASL1_CACHE_OWNER_METADATA: malformed owner PID"))
            ((some pid)
              (match (procAlive? pid)
                ((err e) (err (str "ERR_ASL1_CACHE_OWNER_LIVENESS: " e)))
                ((ok alive) (ok alive)))))))))

fn ! closeGuard! fd: Int64 result: (Result Bool String) -> (Result Bool String)
  (match (fdClose fd)
    ((err closeErr) (match result
      ((err e) (err (str e "; takeover guard close failed: " closeErr)))
      ((ok _) (err (str "ERR_ASL1_CACHE_GUARD_CLOSE: " closeErr)))))
    ((ok _) result))

fn ! createOwnedLock! lockPath: String -> (Result Bool String)
  (match (fileCreateExclusive lockPath (str (stringFromInt64 (procSelf)) "\n" (stringFromInt64 (nowNs)) "\n"))
    ((ok _) (ok true))
    ((err e) (if (stringContains? e "alreadyExists") (ok false) (err (str "ERR_ASL1_CACHE_LOCK: " e)))))

fn ! withTakeoverGuard! lockPath: String timeoutMs: Int64 -> (Result Bool String)
  (let [(guardPath (str lockPath ".takeover"))]
    (match (fileLockWait guardPath true timeoutMs)
      ((err e) (err (str "ERR_ASL1_CACHE_GUARD: " e)))
      ((ok fd)
        (let [(attempt (createOwnedLock! lockPath))]
          (match attempt
            ((err e) (closeGuard! fd (err e)))
            ((ok created)
              (if created
                (closeGuard! fd (ok true))
                (match (lockOwnerAlive? lockPath)
                  ((err e) (closeGuard! fd (err e)))
                  ((ok alive)
                    (if alive
                      (closeGuard! fd (ok false))
                      (match (pathRemove lockPath)
                        ((err e) (closeGuard! fd (err (str "ERR_ASL1_CACHE_STALE_REMOVE: " e))))
                        ((ok _) (match (createOwnedLock! lockPath)
                          ((err e) (closeGuard! fd (err e)))
                          ((ok taken) (closeGuard! fd (ok taken))))))))))))))))
fn ! singleFlightLoop! lockPath: String artifactPath: String timeoutMs: Int64 startNs: Int64 readyFn: Any builder: Any -> (Result String String)
  (if (readyFn)
    (ok artifactPath)
    (let [(elapsedMs (/ (- (monotonicNs) startNs) 1000000))
          (remainingMs (if (< timeoutMs 0) -1 (- timeoutMs elapsedMs)))]
      (if (and (>= timeoutMs 0) (>= elapsedMs timeoutMs))
        (err (str "ERR_ASL1_CACHE_LOCK_TIMEOUT: " lockPath))
        (match (withTakeoverGuard! lockPath remainingMs)
        ((err e) (if (and (>= timeoutMs 0) (>= (/ (- (monotonicNs) startNs) 1000000) timeoutMs))
          (err (str "ERR_ASL1_CACHE_LOCK_TIMEOUT: " lockPath))
          (err e)))
        ((ok acquired)
          (if acquired
            (let [(result (if (readyFn) (ok artifactPath) (builder)))
                  (removed (pathRemove lockPath))]
              (match removed
                ((err e) (match result
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
  (match (fileReadString (headPath! base))
    ((err _) (none))
    ((ok key)
      (match (fileReadString (depsPath! key))
        ((err _) (none))
        ((ok closure)
          (match (makeKey closure base root)
            ((err _) (none))
            ((ok actual) (if (and (= actual key) (usable? key)) (some (binaryPath! key)) (none))))))))

fn ! writeHead! base: String key: String -> Bool
  (let [(head (headPath! base))
        (part (str head ".part." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))]
    (match (fileWrite part key)
      ((err e) (do (drop part) (sys/sayErr! (str "asl1 cache: cannot write head " part ": " e)) false))
      ((ok _) (match (pathRename part head)
        ((err e) (do (drop part) (sys/sayErr! (str "asl1 cache: cannot install head " head ": " e)) false))
        ((ok _) true)))))

fn rootRelative root: String line: String -> String
  (if (stringStartsWith? line (str root "/")) (optionOr (stringSlice line (+ (stringLength root) 1) (stringLength line)) line) line)

fn ! nativeDeps! root: String native: String compiler: String -> (Result String String)
  (match (sys/capture! (list "nice" "-n" "15" native "deps" compiler) (none))
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
  (match (latestCachedBinary!)
    ((none) (interpretedDeps! ctx compiler))
    ((some b) (match (nativeDeps! ctx.root b compiler)
      ((ok listing) (ok listing))
      ((err why) (do (traceErr! (str "asl1 cache: no native asl1 (" why "); asl-host reads the asl1 closure to bootstrap")) (interpretedDeps! ctx compiler))))))

fn ! coldBinary! ctx: sys/Context compiler: String lib: String clang: String base: String -> (Result String String)
  (match (closure! ctx compiler lib clang)
    ((err e) (err e))
    ((ok closure) (match (makeKey closure base ctx.root)
      ((err e) (err e))
      ((ok key) (match (dirCreate (entryDir! key))
        ((err e) (err (str "cannot create keyed cache directory: " e)))
        ((ok _) (match (singleFlight!
          (str (entryDir! key) "/build.lock")
          (binaryPath! key)
          3600000
          (fn [] (usable? key))
          (fn [] (buildNativeTransaction! (cacheDir!) key closure (fn [] (latestCachedBinary!)) (fn [(cached (Option String))] -> (Result String String)
            (ensureSeed! ctx.root lib clang))
            (fn [(native String)] -> (Result String String) (nativeStage! native compiler ctx.root lib clang)))))
          ((err e) (err e))
          ((ok binary) (do (writeHead! base key) (ok binary))))))))))

fn ! nativeAsl1! ctx: sys/Context lib: String clang: String -> (Result String String)
  (let [(compiler (compilerPath! ctx))
        (disabled (= (optionOr (envGet "ASL_NATIVE_ASL1") "") "0"))]
    (if disabled
      (err "native compiler cache disabled by ASL_NATIVE_ASL1=0")
      (match (dirCreate (cacheDir!))
        ((err e) (err (str "cannot create cache directory " (cacheDir!) ": " e)))
        ((ok _) (match (versionLine clang)
          ((err e) (err e))
          ((ok version) (match (baseHashes compiler lib version)
            ((err e) (err e))
            ((ok base) (match (warmBinary! base ctx.root)
              ((some binary) (ok binary))
              ((none) (coldBinary! ctx compiler lib clang base)))))))))))
