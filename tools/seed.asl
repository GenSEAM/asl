(module asl-tools/seed
  :x [Entry Stages seedDir manifestPath compilerSource runtimeArchive fibSource tripleKey seedFileFor parseManifest entryFor bytesCheck unpack verifyEntry verify manifestRow replaceRow link linkArgv linkWith compileWith compileRc bootstrap importPaths sourceClosure sourceDigest staleness checkVerdict regen crossTargets crossTarget RuntimeEntry runtimeModules runtimeFileFor parseRuntime runtimeRow replaceRuntimeRows runtimeDigest runtimeStaleness main]
  :i [(asl-tools/fleet/run :a fr) (asl/packages/asl-cli/src/asl1Cache :a ac)])

(schema Entry
  (:f triple String)
  (:f file String)
  (:f bytes Int64)
  (:f sha256 String)
  (:f llBytes Int64)
  (:f llSha256 String)
  (:f fingerprint String)
  (:f sourceDigest String)
  (:f sourceCommit String))

(schema Stages
  (:f stage1 String)
  (:f stage2Ll String)
  (:f stage2 String)
  (:f stage3Ll String)
  (:f stage2Lib String)
  (:f fixpoint Bool))

(schema RuntimeEntry
  (:f triple String)
  (:f module String)
  (:f file String)
  (:f bytes Int64)
  (:f sha256 String)
  (:f llBytes Int64)
  (:f llSha256 String)
  (:f sourceDigest String)
  (:f sourceCommit String))

fn seedDir -> String
  "asl/seed"

fn manifestPath -> String
  "asl/seed/seed.asn"

fn compilerSource -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn runtimeArchive -> String
  "asl/host/out/libaslrt.a"

fn fibSource -> String
  "tests/conformance/bootstrap/fibProgram.asl"

fn stageTimeoutS -> Int64
  1500

fn stageMaxDesc -> Int64
  16

fn ! clang -> String
  (optionOr (envGet "CLANG") "clang")

fn digitOrDot? c: String -> Bool
  (stringContains? "0123456789." c)

fn stripVersion s: String -> String
  (let [(n (stringLength s))]
    (if (and (> n 0) (digitOrDot? (optionOr (stringSlice s (- n 1) n) "x"))) (stripVersion (optionOr (stringSlice s 0 (- n 1)) "")) s))

; (:m :ref RV1 :do "a linux triple is keyed by its arch alone (aarch64-linux-gnu, x86_64-pc-linux-gnu -> ARCH-unknown-linux-gnu), matching build.sh seed_triple and asl-cli seedTriple; others drop their OS version")
fn tripleKey triple: String -> String
  (let [(parts (stringSplit (stringTrim triple) "-"))
        (arch (optionOr (listHead parts) ""))
        (lastPart (optionOr (listLast parts) ""))]
    (if (listContains? parts "linux")
      (str (if (= arch "arm64") "aarch64" arch) "-unknown-linux-gnu")
      (stringJoin (listAppend (listTake parts (max 0 (- (listLength parts) 1))) (list (stripVersion lastPart))) "-")))

fn seedFileFor key: String -> String
  (str (seedDir) "/" key "/asl1.ll.gz")

fn runtimeModules -> (List (Pair String String))
  (list (pair "gcAsl" "gcRoute") (pair "rtAbi" "rtAbi") (pair "rtFloor" "rtFloor"))

fn emitterSource emitter: String -> String
  (str "asl/packages/asl-target-llvm/src/" emitter ".asl")

fn runtimeFileFor key: String module: String -> String
  (str (seedDir) "/" key "/" module ".ll.gz")

fn ! runJob argv: (List String) root: String env: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv root (fr/childEnv env)) (fr/limits (stageTimeoutS) (stageMaxDesc)))

fn ! hostTriple root: String -> (Result String String)
  (let [(d (runJob (list (clang) "-dumpmachine") root (list)))]
    (if (= d.exit 0) (ok (stringTrim d.out)) (err (str "ERR_SEED_CLANG: " (clang) " -dumpmachine exit " d.exit ": " (stringTrim d.out)))))

fn ! fingerprintFor root: String key: String -> (Result String String)
  (let [(v (runJob (list (clang) "--version") root (list)))]
    (if (!= v.exit 0) (err (str "ERR_SEED_CLANG: " (clang) " --version exit " v.exit))
      (ok (bytesSha256 (stringToBytes (stringJoin (list "seed/1" (optionOr (listHead (stringLines v.out)) "") key) "\n"))))))

; (:m :ref RV1 :do "a seed key other than the host's is cut by cross emission: the host fixpoint compiler builds asl1 with --target and the runtime emitters write their modules with --target, the libc.asl triple paired here")
fn crossTargets -> (List (Pair String String))
  (list (pair "aarch64-unknown-linux-gnu" "linux-aarch64") (pair "x86_64-unknown-linux-gnu" "linux-x86_64"))

fn crossTarget key: String -> (Option String)
  (optionMap pairSecond (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) key)) (crossTargets)))

; (:m :ref SEEDX86 :do "a seed cut from sources that differ from HEAD names HEAD+dirty, so :sourceCommit never claims a commit the IR was not cut from; commit first, then regen")
fn ! sourceCommitOf root: String -> String
  (let [(d (runJob (list "git" "rev-parse" "HEAD") root (list)))
        (s (runJob (list "git" "status" "--porcelain" "--untracked-files=no" "--" "asl/packages" "asl/prelude") root (list)))]
    (cond
      ((!= d.exit 0) "unknown")
      ((or (!= s.exit 0) (not (stringEmpty? (stringTrim s.out)))) (str (stringTrim d.out) "+dirty"))
      (else (stringTrim d.out))))

fn fieldOf row: String key: String -> (Option String)
  (let [(parts (stringSplit row (str ":" key " ")))]
    (if (< (listLength parts) 2) (none)
      (let [(rest (optionOr (listGet parts 1) ""))]
        (if (stringStartsWith? rest "\"")
          (listHead (stringSplit (optionOr (stringSlice rest 1 (stringLength rest)) "") "\""))
          (listHead (stringSplit (stringReplace rest ")" " ") " "))))))

fn entryOfRow row: String -> (Option Entry)
  (match (fieldOf row "triple")
    ((none) (none))
    ((some triple)
     (some (Entry :triple triple
                  :file (optionOr (fieldOf row "file") "")
                  :bytes (optionOr (stringToInt64 (optionOr (fieldOf row "bytes") "")) -1)
                  :sha256 (optionOr (fieldOf row "sha256") "")
                  :llBytes (optionOr (stringToInt64 (optionOr (fieldOf row "llBytes") "")) -1)
                  :llSha256 (optionOr (fieldOf row "llSha256") "")
                  :fingerprint (optionOr (fieldOf row "fingerprint") "")
                  :sourceDigest (optionOr (fieldOf row "sourceDigest") "")
                  :sourceCommit (optionOr (fieldOf row "sourceCommit") "")))))

fn parseManifest text: String -> (List Entry)
  (fold (fn [(acc (List Entry)) (l String)] -> (List Entry)
          (if (stringStartsWith? (stringTrim l) "(:seed ")
            (match (entryOfRow (stringTrim l)) ((some e) (listAppend acc (list e))) ((none) acc))
            acc))
        (list) (stringLines text))

fn runtimeOfRow row: String -> (Option RuntimeEntry)
  (match (fieldOf row "triple")
    ((none) (none))
    ((some triple)
     (some (RuntimeEntry :triple triple
                         :module (optionOr (fieldOf row "module") "")
                         :file (optionOr (fieldOf row "file") "")
                         :bytes (optionOr (stringToInt64 (optionOr (fieldOf row "bytes") "")) -1)
                         :sha256 (optionOr (fieldOf row "sha256") "")
                         :llBytes (optionOr (stringToInt64 (optionOr (fieldOf row "llBytes") "")) -1)
                         :llSha256 (optionOr (fieldOf row "llSha256") "")
                         :sourceDigest (optionOr (fieldOf row "sourceDigest") "")
                         :sourceCommit (optionOr (fieldOf row "sourceCommit") "")))))

fn parseRuntime text: String -> (List RuntimeEntry)
  (fold (fn [(acc (List RuntimeEntry)) (l String)] -> (List RuntimeEntry)
          (if (stringStartsWith? (stringTrim l) "(:runtimeSeed ")
            (match (runtimeOfRow (stringTrim l)) ((some e) (listAppend acc (list e))) ((none) acc))
            acc))
        (list) (stringLines text))

fn entryFor entries: (List Entry) key: String -> (Option Entry)
  (listHead (filter (fn [(e Entry)] -> Bool (= e.triple key)) entries))

fn ! bytesCheck path: String label: String bytes: Int64 sha: String -> (Result Unit String)
  (match (fileReadBytes path)
    ((err x) (err (str "ERR_SEED_MISSING: " label ": " x)))
    ((ok b) (let [(got (bytesSha256 b))]
              (cond
                ((!= (bytesLength b) bytes) (err (str "ERR_SEED_SIZE: " label " has " (bytesLength b) " bytes, manifest says " bytes)))
                ((!= got sha) (err (str "ERR_SEED_SHA: " label " hashes to " got ", manifest says " sha)))
                (else (ok ()))))))

fn ! unpack root: String gz: String work: String -> (Result String String)
  (let [(copy (str work "/seed.ll.gz"))
        (out (str work "/seed.ll"))]
    (match (fileReadBytes gz)
      ((err x) (err (str "ERR_SEED_IO: " gz ": " x)))
      ((ok b) (match (fileWrite copy b)
                ((err x) (err (str "ERR_SEED_IO: " copy ": " x)))
                ((ok _) (let [(d (runJob (list "gzip" "-d" "-f" copy) root (list)))]
                          (if (and (= d.exit 0) (fileExists? out)) (ok out) (err (str "ERR_SEED_UNPACK: gzip -d " copy " (" d.verdict " exit " d.exit "): " (stringTrim d.out))))))))))

fn ! verifyEntry root: String e: Entry work: String -> (Result String String)
  (cond
    ((or (!= (stringLength e.sha256) 64) (!= (stringLength e.llSha256) 64)) (err (str "ERR_SEED_MANIFEST: " e.triple " lacks a 64-hex sha256 or llSha256")))
    ((!= e.file (seedFileFor e.triple)) (err (str "ERR_SEED_MANIFEST: " e.triple " file " e.file " is not " (seedFileFor e.triple))))
    (else
     (match (bytesCheck (str root "/" e.file) e.file e.bytes e.sha256)
       ((err x) (err x))
       ((ok _) (match (unpack root (str root "/" e.file) work)
                 ((err x) (err x))
                 ((ok ll) (match (bytesCheck ll (str e.file " unpacked") e.llBytes e.llSha256)
                            ((err x) (err x))
                            ((ok _) (ok ll)))))))))

fn ! verify root: String manifestText: String work: String -> (Result Entry String)
  (match (hostTriple root)
    ((err e) (err e))
    ((ok t) (match (entryFor (parseManifest manifestText) (tripleKey t))
              ((none) (err (str "ERR_SEED_TRIPLE: no seed for " (tripleKey t) " in " (manifestPath))))
              ((some e) (match (verifyEntry root e work) ((ok _) (ok e)) ((err x) (err x)))))))

fn ! notHost? path: String -> Bool
  (and (not (stringEndsWith? path "/asl-host")) (!= path "asl-host"))

; (:m :ref FIXPOINT-O2-NT :do "stages link at -O2 as asl build does; stage2 on is notrace IR linked against the notrace runtime asl1Cache builds with the stage compiler")
fn ! linkArgv ll: String out: String lib: String -> (List String)
  (list (clang) "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" lib "-lm" "-o" out)

fn ! linkWith root: String ll: String out: String lib: String -> (Result String String)
  (let [(d (runJob (linkArgv ll out lib) root (list)))]
    (if (and (= d.exit 0) (fileExists? out)) (ok out) (err (str "ERR_SEED_LINK: clang " ll " (" d.verdict " exit " d.exit "): " (stringTrim d.out)))))

fn ! link root: String ll: String out: String -> (Result String String)
  (linkWith root ll out (str root "/" (runtimeArchive)))

fn ! compileWith root: String compiler: String entry: String out: String -> (Result String String)
  (compileRc root compiler entry out (list))

fn ! compileRc root: String compiler: String entry: String out: String rc: (List String) -> (Result String String)
  (if (not (notHost? compiler)) (err (str "ERR_SEED_STAGE: " compiler " is the host interpreter, not a stage binary"))
    (let [(_ (if (fileExists? out) (pathRemove out) (ok ())))
          (d (runJob (listAppend (list compiler "build" entry "-o" out) rc) root
                     (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" root "/asl/prelude/prelude.asl") "ASL_HOST_CACHE=0")))]
      (if (and (= d.exit 0) (fileExists? out)) (ok out) (err (str "ERR_SEED_BUILD: " compiler " build " entry " (" d.verdict " exit " d.exit "): " (stringTrim d.out))))))

fn ! fileSha path: String -> String
  (match (fileReadBytes path) ((ok b) (bytesSha256 b)) ((err e) (str "unreadable " e)))

fn ! bootstrap root: String e: Entry work: String -> (Result Stages String)
  (match (verifyEntry root e work)
    ((err x) (err x))
    ((ok seedPath)
     (match (link root seedPath (str work "/stage1"))
       ((err x) (err x))
       ((ok s1) (match (compileRc root s1 (compilerSource) (str work "/stage2.ll") (list "--rc" "notrace"))
                  ((err x) (err x))
                  ((ok l2) (match (ac/notraceLib! s1 root (str root "/" (runtimeArchive)) (clang))
                             ((err x) (err (str "ERR_SEED_RT: notrace runtime built by " s1 ": " x)))
                             ((ok lib2) (match (linkWith root l2 (str work "/stage2") lib2)
                             ((err x) (err x))
                             ((ok s2) (match (compileRc root s2 (compilerSource) (str work "/stage3.ll") (list "--rc" "notrace"))
                                        ((err x) (err x))
                                        ((ok l3) (ok (Stages :stage1 s1 :stage2Ll l2 :stage2 s2 :stage3Ll l3 :stage2Lib lib2
                                                             :fixpoint (= (fileSha l2) (fileSha l3))))))))))))))))

fn importPaths header: String -> (List String)
  (fold (fn [(acc (List String)) (piece String)] -> (List String)
          (let [(token (optionOr (listHead (stringSplit (stringTrim piece) " ")) ""))
                (parts (stringSplit token "/"))]
            (if (and (>= (listLength parts) 2) (not (stringContains? token "]")))
              (listAppend acc (list (str "asl/packages/" (optionOr (listHead parts) "") "/src/" (stringJoin (optionOr (listTail parts) (list)) "/") ".asl")))
              acc)))
        (list) (optionOr (listTail (stringSplit header "(")) (list)))

fn ! closureFrom root: String frontier: (List String) seen: (List String) -> (List String)
  (match (listHead frontier)
    ((none) (listSort seen))
    ((some f)
     (let [(rest (optionOr (listTail frontier) (list)))]
       (if (or (listContains? seen f) (not (fileExists? (str root "/" f))))
         (closureFrom root rest seen)
         (let [(header (optionOr (listHead (stringSplit (resultOr (fileReadString (str root "/" f)) "") "\n\n")) ""))]
           (closureFrom root (listAppend rest (importPaths header)) (cons f seen)))))))

fn ! sourceClosure root: String -> (List String)
  (let [(natives (match (dirList (str root "/asl/prelude/native"))
                   ((ok names) (map (fn [(n String)] -> String (str "asl/prelude/native/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) (listSort names))))
                   ((err _) (list))))]
    (listAppend (closureFrom root (list (compilerSource)) (list)) (cons "asl/prelude/prelude.asl" natives)))

fn ! sourceDigest root: String -> String
  (bytesSha256 (stringToBytes (stringJoin (map (fn [(f String)] -> String (str f " " (fileSha (str root "/" f)))) (sourceClosure root)) "\n")))

fn staleness e: Entry current: String -> (Option String)
  (if (= e.sourceDigest current) (none) (some (str "sourceDigest " e.sourceDigest " in the manifest, " current " in the tree (seed cut at " e.sourceCommit ")")))

fn ! runtimeClosure root: String -> (List String)
  (let [(natives (match (dirList (str root "/asl/prelude/native"))
                   ((ok names) (map (fn [(n String)] -> String (str "asl/prelude/native/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) (listSort names))))
                   ((err _) (list))))]
    (listAppend (closureFrom root (map (fn [(m (Pair String String))] -> String (emitterSource (pairSecond m))) (runtimeModules)) (list)) (cons "asl/prelude/prelude.asl" natives)))

fn ! runtimeDigest root: String -> String
  (bytesSha256 (stringToBytes (stringJoin (map (fn [(f String)] -> String (str f " " (fileSha (str root "/" f)))) (runtimeClosure root)) "\n")))

fn runtimeStaleness e: RuntimeEntry current: String -> (Option String)
  (if (= e.sourceDigest current) (none) (some (str "sourceDigest " e.sourceDigest " in the manifest, " current " in the tree (runtime cut at " e.sourceCommit ")")))

fn manifestRow e: Entry -> String
  (str "  (:seed :triple \"" e.triple "\" :file \"" e.file "\" :bytes " e.bytes " :sha256 \"" e.sha256 "\" :llBytes " e.llBytes " :llSha256 \"" e.llSha256 "\" :fingerprint \"" e.fingerprint "\" :sourceDigest \"" e.sourceDigest "\" :sourceCommit \"" e.sourceCommit "\")")

fn manifestHeader -> String
  "(:seeds :v 1 :format \"whole-program LLVM IR of asl/packages/asl-compiler/src/asl1.asl, gzip -9 -n, one per triple; sha256/bytes of the .gz, llSha256/llBytes of the IR\" :regen \"bin/asl run asl/tools/seed.asl regen\" :link \"gzip -dc asl1.ll.gz > asl1.ll; clang -x ir asl1.ll -x none asl/host/out/libaslrt.a -lm\" :runtime \"libaslrt.a holds rtFloor.o, rtAbi.o and gcAsl.o, all emitted from ASL by build.sh (RT-FLOOR)\" :policy \"regenerate only when seedFixpointTest needs it (stage2.ll differs from stage3.ll) or at a release, never per commit; asl/tools/seed.asl check compares sourceDigest (sha256 over the asl1 import closure and the prelude) with the tree and rewrites nothing\""

fn replaceRow text: String e: Entry -> String
  (let [(others (filter (fn [(o Entry)] -> Bool (!= o.triple e.triple)) (parseManifest text)))
        (rows (listSortBy (fn [(o Entry)] -> String o.triple) (listAppend others (list e))))]
    (manifestText rows (parseRuntime text)))

fn runtimeRow e: RuntimeEntry -> String
  (str "  (:runtimeSeed :triple \"" e.triple "\" :module \"" e.module "\" :file \"" e.file "\" :bytes " e.bytes " :sha256 \"" e.sha256 "\" :llBytes " e.llBytes " :llSha256 \"" e.llSha256 "\" :sourceDigest \"" e.sourceDigest "\" :sourceCommit \"" e.sourceCommit "\")")

fn manifestText seeds: (List Entry) runtimes: (List RuntimeEntry) -> String
  (let [(sorted (listSortBy (fn [(r RuntimeEntry)] -> String (str r.triple "/" r.module)) runtimes))]
    (str (manifestHeader) "\n" (stringJoin (listAppend (map manifestRow seeds) (map runtimeRow sorted)) "\n") ")\n"))

fn replaceRuntimeRows text: String fresh: (List RuntimeEntry) -> String
  (let [(same? (fn [(a RuntimeEntry) (b RuntimeEntry)] -> Bool (and (= a.triple b.triple) (= a.module b.module))))
        (others (filter (fn [(o RuntimeEntry)] -> Bool (not (listAny? (fn [(f RuntimeEntry)] -> Bool (same? o f)) fresh))) (parseRuntime text)))]
    (manifestText (listSortBy (fn [(o Entry)] -> String o.triple) (parseManifest text)) (listAppend others fresh)))

fn ! freshWork -> (Result String String)
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/aslSeed." (procSelf) "." (monotonicNs)))]
    (match (dirCreate dir) ((ok _) (ok dir)) ((err e) (err (str "ERR_SEED_IO: cannot create " dir ": " e)))))

fn ! iterate root: String candidate: String work: String round: Int64 -> (Result String String)
  (if (> round 4) (err (str "ERR_SEED_FIXPOINT: no fixpoint after 4 rounds from " candidate))
    (match (link root candidate (str work "/r" round))
      ((err x) (err x))
      ((ok b) (match (compileWith root b (compilerSource) (str work "/r" round ".ll"))
                ((err x) (err x))
                ((ok next) (if (= (fileSha next) (fileSha candidate)) (ok next) (iterate root next work (+ round 1))))))))

fn ! hostCandidate root: String work: String -> (Result String String)
  (let [(out (str work "/host.ll"))
        (d (runJob (list (fr/legacyHost!) "run" (compilerSource) "build" (compilerSource) "-o" out) root
                   (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" root "/asl/prelude/prelude.asl") "ASL_HOST_CACHE=0")))]
    (if (and (= d.exit 0) (fileExists? out)) (ok out) (err (str "ERR_SEED_BUILD: stage0 build (" d.verdict " exit " d.exit "): " (stringTrim d.out)))))

fn argAfter args: (List String) flag: String -> (Option String)
  (match (listHead args)
    ((none) (none))
    ((some a) (if (= a flag) (listGet args 1) (argAfter (optionOr (listTail args) (list)) flag))))

fn ! candidateOf root: String args: (List String) work: String key: String -> (Result String String)
  (cond
    ((listContains? args "--from-host") (hostCandidate root work))
    ((listContains? args "--from")
     (match (argAfter args "--from") ((some p) (if (fileExists? p) (ok p) (err (str "ERR_SEED_MISSING: " p)))) ((none) (err "--from needs a .ll path"))))
    (else (match (fileReadString (str root "/" (manifestPath)))
            ((err e) (err (str "ERR_SEED_MISSING: " (manifestPath) ": " e "; use --from-host or --from FILE.ll")))
            ((ok text) (match (entryFor (parseManifest text) key)
                         ((none) (err (str "ERR_SEED_TRIPLE: no seed for " key "; use --from-host or --from FILE.ll")))
                         ((some e) (verifyEntry root e work)))))))

fn ! pack root: String fixed: String work: String -> (Result String String)
  (let [(copy (str work "/pack.ll"))]
    (match (fileReadBytes fixed)
      ((err x) (err (str "ERR_SEED_IO: " fixed ": " x)))
      ((ok b) (match (fileWrite copy b)
                ((err x) (err (str "ERR_SEED_IO: " copy ": " x)))
                ((ok _) (let [(d (runJob (list "gzip" "-9" "-n" "-f" copy) root (list)))]
                          (if (and (= d.exit 0) (fileExists? (str copy ".gz"))) (ok (str copy ".gz")) (err (str "ERR_SEED_PACK: gzip " copy " (" d.verdict " exit " d.exit "): " (stringTrim d.out))))))))))

fn ! writeSeed root: String key: String fixed: String work: String -> (Result Entry String)
  (match (pack root fixed work)
    ((err e) (err e))
    ((ok gz) (match (fileReadBytes gz)
               ((err e) (err (str "ERR_SEED_IO: " gz ": " e)))
               ((ok b) (let [(ll (resultOr (fileReadBytes fixed) (bytesAlloc 0)))
                             (file (seedFileFor key))
                             (_ (dirCreate (str root "/" (seedDir) "/" key)))
                             (entry (Entry :triple key :file file :bytes (bytesLength b) :sha256 (bytesSha256 b)
                                           :llBytes (bytesLength ll) :llSha256 (bytesSha256 ll)
                                           :fingerprint (resultOr (fingerprintFor root key) "unknown") :sourceDigest (sourceDigest root) :sourceCommit (sourceCommitOf root)))
                             (old (resultOr (fileReadString (str root "/" (manifestPath))) ""))]
                         (match (fileWrite (str root "/" file) b)
                           ((err x) (err (str "ERR_SEED_IO: " file ": " x)))
                           ((ok _) (match (fileWrite (str root "/" (manifestPath)) (replaceRow old entry))
                                     ((err x) (err (str "ERR_SEED_IO: " (manifestPath) ": " x)))
                                     ((ok _) (ok entry))))))))))

fn ! runtimeModule root: String key: String compiler: String work: String emitArgs: (List String) m: (Pair String String) -> (Result RuntimeEntry String)
  (let [(module (pairFirst m))
        (emitter (pairSecond m))
        (ll (str work "/" module ".ll"))]
    (match (compileWith root compiler (emitterSource emitter) (str work "/" emitter ".prog.ll"))
      ((err x) (err x))
      ((ok progLl) (match (link root progLl (str work "/" emitter ".prog"))
        ((err x) (err x))
        ((ok prog) (let [(d (runJob (cons prog (cons ll emitArgs)) root (list)))]
          (if (not (and (= d.exit 0) (fileExists? ll)))
            (err (str "ERR_SEED_RUNTIME: " emitter " (" d.verdict " exit " d.exit "): " (stringTrim d.out)))
            (match (pack root ll work)
              ((err x) (err x))
              ((ok gz) (match (fileReadBytes gz)
                ((err x) (err (str "ERR_SEED_IO: " gz ": " x)))
                ((ok b) (let [(ir (resultOr (fileReadBytes ll) (bytesAlloc 0)))
                              (file (runtimeFileFor key module))]
                  (match (fileWrite (str root "/" file) b)
                    ((err x) (err (str "ERR_SEED_IO: " file ": " x)))
                    ((ok _) (ok (RuntimeEntry :triple key :module module :file file :bytes (bytesLength b) :sha256 (bytesSha256 b)
                                              :llBytes (bytesLength ir) :llSha256 (bytesSha256 ir) :sourceDigest (runtimeDigest root) :sourceCommit (sourceCommitOf root)))))))))))))))))

fn ! runtimeAll root: String key: String compiler: String work: String emitArgs: (List String) mods: (List (Pair String String)) acc: (List RuntimeEntry) -> (Result (List RuntimeEntry) String)
  (match (listHead mods)
    ((none) (ok acc))
    ((some m) (match (runtimeModule root key compiler work emitArgs m)
                ((err x) (err x))
                ((ok e) (runtimeAll root key compiler work emitArgs (optionOr (listTail mods) (list)) (listAppend acc (list e)))))))

fn ! runtimeFrom root: String key: String ll: String work: String emitArgs: (List String) -> (Result (List RuntimeEntry) String)
  (match (link root ll (str work "/runtimeCompiler"))
    ((err e) (err e))
    ((ok compiler) (match (runtimeAll root key compiler work emitArgs (runtimeModules) (list))
      ((err e) (err e))
      ((ok fresh) (match (fileWrite (str root "/" (manifestPath)) (replaceRuntimeRows (resultOr (fileReadString (str root "/" (manifestPath))) "") fresh))
        ((err x) (err (str "ERR_SEED_IO: " (manifestPath) ": " x)))
        ((ok _) (ok fresh)))))))

fn targetArgv target: String -> (List String)
  (if (stringEmpty? target) (list) (list "--target" target))

; (:m :ref RV1 :do "fixed is the host fixpoint IR; for a cross target the compiler it links builds asl1 once more with --target, and that IR is the seed")
fn ! seedIr root: String fixed: String work: String target: String -> (Result String String)
  (if (stringEmpty? target) (ok fixed)
    (match (link root fixed (str work "/crossCompiler"))
      ((err x) (err x))
      ((ok compiler) (compileRc root compiler (compilerSource) (str work "/cross.ll") (targetArgv target)))))

fn ! regenIn root: String args: (List String) work: String hostKey: String key: String target: String -> (Result Entry String)
  (match (candidateOf root args work hostKey)
    ((err e) (err e))
    ((ok c) (if (listContains? args "--runtime")
              (match (runtimeFrom root key c work (targetArgv target))
                ((err e) (err e))
                ((ok _) (match (entryFor (parseManifest (resultOr (fileReadString (str root "/" (manifestPath))) "")) key)
                          ((none) (err (str "ERR_SEED_TRIPLE: no seed for " key)))
                          ((some e) (ok e)))))
              (match (iterate root c work 1)
                ((err e) (err e))
                ((ok fixed) (match (seedIr root fixed work target)
                  ((err e) (err e))
                  ((ok ir) (match (writeSeed root key ir work)
                    ((err e) (err e))
                    ((ok entry) (match (runtimeFrom root key fixed work (targetArgv target)) ((err e) (err e)) ((ok _) (ok entry))))))))))))

; (:m :ref RV1 :do "--triple KEY names the seed to cut: the host's key, or no flag, regenerates the host seed, a crossTargets key a cross seed, anything else is refused")
fn ! regen root: String args: (List String) -> (Result Entry String)
  (match (hostTriple root)
    ((err e) (err e))
    ((ok t) (let [(hostKey (tripleKey t))
                  (key (optionOr (argAfter args "--triple") hostKey))
                  (target (if (= key hostKey) (some "") (crossTarget key)))]
              (match target
                ((none) (err (str "ERR_SEED_TRIPLE: --triple " key " is neither the host " hostKey " nor a cross target (" (stringJoin (map pairFirst (crossTargets)) ", ") ")")))
                ((some tgt) (match (freshWork)
                              ((err e) (err e))
                              ((ok work) (let [(result (regenIn root args work hostKey key tgt))
                                               (_ (pathRemove work))]
                                           result))))))))

fn ! checkVerdict root: String triple: String -> (Pair Int64 String)
  (match (fileReadString (str root "/" (manifestPath)))
    ((err x) (pair 1 (str "ERR_SEED_MISSING: " (manifestPath) " is not readable under the root (ASL_ROOT, else the cwd): " x)))
    ((ok text) (let [(key (tripleKey triple))
                     (asl1 (match (entryFor (parseManifest text) key)
                             ((none) (pair 1 (str "ERR_SEED_TRIPLE: no seed for " key)))
                             ((some e) (match (staleness e (sourceDigest root))
                                         ((none) (pair 0 (str "(:seed :check :triple " e.triple " :current true)")))
                                         ((some why) (pair 1 (str "(:seed :check :triple " e.triple " :current false :why \"" why "\")")))))))
                     (rows (filter (fn [(r RuntimeEntry)] -> Bool (= r.triple key)) (parseRuntime text)))
                     (digest (runtimeDigest root))
                     (runtime (if (listEmpty? rows)
                                (list (pair 1 (str "ERR_SEED_RUNTIME: no runtime seed for " key)))
                                (map (fn [(r RuntimeEntry)] -> (Pair Int64 String)
                                       (match (runtimeStaleness r digest)
                                         ((none) (pair 0 (str "(:seed :check :runtime " r.module " :triple " r.triple " :current true)")))
                                         ((some why) (pair 1 (str "ERR_SEED_STALE: runtime " r.module " for " r.triple ": " why "; regenerate it with bin/asl run asl/tools/seed.asl regen --runtime")))))
                                     rows)))
                     (all (cons asl1 runtime))]
                 (pair (fold (fn [(acc Int64) (v (Pair Int64 String))] -> Int64 (max acc (pairFirst v))) 0 all)
                       (stringJoin (map pairSecond all) "\n")))))

fn ! main args: (List String) -> Int64
  (let [(root (optionOr (envGet "ASL_ROOT") "."))]
    (cond
      ((= (listHead args) (some "regen"))
       (match (regen root args)
         ((ok e) (do (println (if (listContains? args "--runtime") (str "(:seed :regen :runtime :triple " e.triple ")") (str "(:seed :regen :triple " e.triple " :bytes " e.bytes " :sha256 " e.sha256 " :llBytes " e.llBytes " :llSha256 " e.llSha256 ")"))) 0))
         ((err e) (do (eprintln e) 1))))
      ((= (listHead args) (some "verify"))
       (match (fileReadString (str root "/" (manifestPath)))
         ((err e) (do (eprintln (str "ERR_SEED_MISSING: " (manifestPath) ": " e)) 1))
         ((ok text) (match (freshWork)
                      ((err e) (do (eprintln e) 1))
                      ((ok work) (let [(checked (verify root text work))
                                       (_ (pathRemove work))]
                                   (match checked
                                     ((ok e) (do (println (str "(:seed :verified :triple " e.triple " :sha256 " e.sha256 " :llSha256 " e.llSha256 ")")) 0))
                                     ((err e) (do (eprintln e) 1)))))))))
      ((= (listHead args) (some "check"))
       (match (hostTriple root)
         ((err e) (do (eprintln e) 1))
         ((ok t) (let [(v (checkVerdict root (optionOr (argAfter args "--triple") t)))]
                   (do (map (fn [(l String)] -> Bool (do (if (stringStartsWith? l "ERR_") (eprintln l) (println l)) true)) (stringLines (pairSecond v))) (pairFirst v))))))
      (else (do (eprintln "usage: asl/tools/seed.asl regen [--from-host | --from FILE.ll | --runtime] [--triple KEY] | verify | check [--triple KEY]") 2))))
