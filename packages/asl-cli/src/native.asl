(module asl-cli/native
  :x [main pruneStaleStaged!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/cacheFallback :a cf) (asl/packages/asl-cli/src/command :a cmd) (asl-tools/nativeTest :a nt) (asl-parser/indentParser :a ip) (asl-harness/launch :a launch) (asl/packages/asl-cli/src/sweep :a sw) (asl/packages/asl-proc/src/jobPool :a run) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-gates/src/suiteRunner :a runner) (asl-forms/main :a forms) (asl-intel :a intel) (asl/packages/asl-cli/src/verify :a verify) (asl-checker/checkCached :a cc) (asl-checker/types :a ty) (asl-checker/resolve :a ckr) (asl-tools/agentSurfaceAudit :a tsa) (asl-pack/pkgCli :a pkg) (asl-tools/fleet/jobserver :a js)])

fn rest args: (List String) -> (List String)
  (optionOr (listTail args) (list))

fn first args: (List String) -> String
  (optionOr (listHead args) "")

fn ! atRoot? ctx: sys/Context -> Bool
  (= (resultOr (realPath ".") ".") (resultOr (realPath ctx.root) ctx.root))

fn rooted ctx: sys/Context file: String -> String
  (let [(prefix (str ctx.root "/"))]
    (if (stringStartsWith? file prefix) (optionOr (stringSlice file (stringLength prefix) (stringLength file)) file) file))

; (:m :ref NATIVECACHE-REALROOT :do "arguments are resolved with realPath, so they are compared with the resolved root too: a root reached through a symlink (/tmp, /var on macOS) made every in-root suite look outside it, so it was staged into outsidePkg and ran from the mirror, where its cwd-relative reads (the corpus cache roots) were missing")
fn ! realRoot ctx: sys/Context -> String
  (resultOr (realPath ctx.root) ctx.root)

fn ! inRoot? ctx: sys/Context absFile: String -> Bool
  (or (stringStartsWith? absFile (str ctx.root "/")) (stringStartsWith? absFile (str (realRoot ctx) "/")))

fn ! rootedAbs ctx: sys/Context absFile: String -> String
  (let [(real (realRoot ctx))]
    (if (stringStartsWith? absFile (str real "/")) (optionOr (stringSlice absFile (+ (stringLength real) 1) (stringLength absFile)) absFile) (rooted ctx absFile)))

fn ! nativeTest! args: (List String) -> Int64
  (match (nt/main (cons "--self-fp" (cons (nt/fingerprint) args)))
    ((ok code) code)
    ((err e) (do (sys/sayErr! (str "asl: nativeTest: " e)) 1)))

; (:m :ref NATIVETEST-HOSTLESS :do "bin/asl run asl/tools/nativeTest.asl runs the nativeTest this CLI is built from in place (bin/asl rebuilds the CLI when that source moves): no per-process compile of its ~60-module closure, and nothing of it in the suite cache")
fn ! nativeTool! args: (List String) -> Int64
  (match (nt/main args)
    ((ok code) code)
    ((err e) (do (sys/sayErr! (str "asl: nativeTest: " e)) 1)))

fn ! outsideStageDir ctx: sys/Context -> String
  (str ctx.root "/.asl/cache/nativeTest/outside")

fn ! outsidePkgStageDir ctx: sys/Context -> String
  (str ctx.root "/.asl/cache/nativeTest/outsidePkg")

fn ! outsideRelPath digest: String -> String
  (str ".asl/cache/nativeTest/outside/" digest ".asl")

fn ! ensureDir! dir: String -> (Result Unit String)
  (if (sys/isDir? dir) (ok ()) (dirCreate dir))

; (:m :ref OUTSIDEPKG-STAGE-SOURCES-20261024 :do "the cache of staged outside files keeps the newest 4 entries per kind: staging touches the entry it uses (a single file is rewritten, a package directory gets a .used file written) and prunes older ones, never an entry used in the last 30 minutes or the one being staged")
fn ! stageKeep -> Int64
  4

fn ! stageMinAgeNs -> Int64
  1800000000000

fn ! touchUsed! path: String -> Bool
  (if (sys/isDir? path)
    (ok? (fileWrite (str path "/.used") (stringFromInt64 (nowNs))))
    (match (fileReadBytes path)
      ((err _) false)
      ((ok b) (let [(part (str path ".part." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
                (and (ok? (fileWrite part b)) (ok? (pathRename part path)))))))

fn ! pruneStage! dir: String prefix: String current: String -> Int64
  (nc/pruneEntries! dir prefix (stageKeep) (stageMinAgeNs) (list current))

fn ! stageOutsideSingle! ctx: sys/Context absFile: String -> (Result String String)
  (match (fileReadString absFile)
    ((err e) (err (str "cannot read " absFile ": " e)))
    ((ok src)
      (let [(digest (bytesSha256 (stringToBytes src)))
            (rel (outsideRelPath digest))
            (dest (str ctx.root "/" rel))]
        (match (ensureDir! (outsideStageDir ctx))
          ((err e2) (err (str "cannot create " (outsideStageDir ctx) ": " e2)))
          ((ok _)
            (match (if (sys/isFile? dest)
                      (match (fileReadString dest)
                        ((ok d) (if (= d src) (ok ()) (writeAtomic! dest (stringToBytes src))))
                        ((err _) (writeAtomic! dest (stringToBytes src))))
                      (writeAtomic! dest (stringToBytes src)))
              ((err e3) (err (str "cannot write " dest ": " e3)))
              ((ok _) (do (touchUsed! dest) (pruneStage! (outsideStageDir ctx) "" (str digest ".asl")) (ok rel)))))))))

; (:m :ref NATIVETEST-OUTSIDE-CLOSURE-20261020 :do "an externally-rooted file with its own .asl.config.asn (a vendored project, not a loose script) declares a package with sibling-module imports that a single-file content-hash copy can never resolve, since every import inside it names a sibling by the package's own workspace-qualified path; find that package's root the same way asl check does (climb to the nearest .asl.config.asn) and mirror the whole package's .asl files under ctx.root so resolveImport!'s own scanUp!, unmodified, finds a config at the mirror's root instead of climbing past it into ctx.root's")
fn ! findPackageRoot! dir: String depth: Int64 -> (Option String)
  (if (or (> depth 64) (= dir "/"))
    (none)
    (if (sys/isFile? (str dir "/.asl.config.asn"))
      (some dir)
      (let [(parent (ckr/parentDirOf dir))]
        (if (= parent dir) (none) (findPackageRoot! parent (+ depth 1))))))

fn ! dropPrefixLen s: String n: Int64 -> String
  (optionOr (stringSlice s n (stringLength s)) "")

fn ! afterNeedle s: String needle: String -> (Option String)
  (match (stringIndexOf s needle) ((none) (none)) ((some i) (some (dropPrefixLen s (+ i (stringLength needle))))))

; (:m :ref NATIVETEST-OUTSIDE-CLOSURE-20261020 :do "only the :workspace value is needed for resolveWorkspaceQualified!'s fast path; a plain needle-and-quote scan avoids pulling the full ASN reader in just for this one field")
fn ! quotedValueAfter s: String needle: String -> String
  (match (afterNeedle s needle)
    ((none) "")
    ((some rest) (match (stringIndexOf rest "\"")
      ((none) "")
      ((some q1) (let [(afterQ1 (dropPrefixLen rest (+ q1 1)))]
        (match (stringIndexOf afterQ1 "\"")
          ((none) "")
          ((some q2) (optionOr (stringSlice afterQ1 0 q2) ""))))))))

fn ! workspaceNameOf configText: String -> String
  (quotedValueAfter configText ":workspace")

; (:m :ref STAGE-CONCURRENT-RUNS :do "two asl test runs of one package share its staging dir and each restaged every file while the other read it: a source equal to its staged copy is left alone, and a changed one is written to a hidden .part.PID.NAME beside it (never pruned by a concurrent stager) and renamed over dest, so a concurrent reader sees the old file or the new one, never a partial one")
fn ! mirrorFile! src: String dest: String -> (Result Unit String)
  (match (fileReadBytes src)
    ((err e) (err (str "cannot read " src ": " e)))
    ((ok content)
      (match (fileReadBytes dest)
        ((ok staged) (if (= staged content) (ok ()) (writeAtomic! dest content)))
        ((err _) (writeAtomic! dest content)))))

fn ! writeAtomic! dest: String content: Bytes -> (Result Unit String)
  (match (ensureDir! (ckr/parentDirOf dest))
    ((err e2) (err (str "cannot create " (ckr/parentDirOf dest) ": " e2)))
    ((ok _)
      (let [(part (str (ckr/parentDirOf dest) "/.part." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs)) "." (sys/baseName dest)))]
        (match (fileWrite part content)
          ((err e3) (err (str "cannot write " part ": " e3)))
          ((ok _) (match (pathRename part dest)
                    ((err e4) (do (pathRemove part) (err (str "cannot rename " part " to " dest ": " e4))))
                    ((ok _) (ok ()))))))))

; (:m :ref OUTSIDEPKG-STAGE-SOURCES-20261024 :do "a staged package copied every listed file, so one asl test of a package with multi-GB exported data wrote tens of GB per cache key (68G in 13 entries on 2026-10-24); the build reads only .asl and .asn sources (and the manifest, an .asn), which stay real copies, while every other file, and an .asn over 1MB, is a symlink to the original: relative and workspace-qualified data paths still open, nothing is duplicated, and removing the stage drops the links only")
fn ! sourceSized? path: String -> Bool
  (and (or (stringEndsWith? path ".asl") (stringEndsWith? path ".asn"))
       (or (stringEndsWith? path ".asl") (match (fileStat path) ((ok st) (<= st.size 1048576)) ((err _) false))))

; (:m :ref OUTSIDEPKG-STAGE-SOURCES-20261024 :do "a staged suite may write into its package data, so non-source files are copy-on-write clones (macOS cp -c, Linux cp --reflink=auto) that share blocks with the original until written and never touch it; where a clone fails (non-CoW filesystem, other volume) a file up to 8MB is copied and a larger one is linked, and the number linked is reported on stderr; stale links from an earlier stage are removed first so a copy never writes through them")
fn ! cloneLimitBytes -> Int64
  8388608

fn ! runIn! dir: String argv: (List String) -> Int64
  (let [(d (run/runOneLimited (run/job argv dir (run/childEnv (list))) (run/limits 120 8)))] d.exit)

fn ! cloneBatch! destDir: String srcs: (List String) -> Bool
  (let [(tail (listAppend srcs (list (str destDir "/"))))]
    (or (= (runIn! destDir (cons "cp" (cons "-c" (cons "--" tail)))) 0)
        (= (runIn! destDir (cons "cp" (cons "--reflink=auto" (cons "--" tail)))) 0)))

fn ! settleOne! destDir: String src: String -> Int64
  (if (cloneBatch! destDir (list src))
    0
    (if (match (fileStat src) ((ok st) (<= st.size (cloneLimitBytes))) ((err _) true))
      (if (= (runIn! destDir (list "cp" "--" src (str destDir "/"))) 0) 0 (if (= (runIn! destDir (list "ln" "-sf" "--" src (str destDir "/"))) 0) 1 -1))
      (if (= (runIn! destDir (list "ln" "-sf" "--" src (str destDir "/"))) 0) 1 -1)))

fn ! settleEach! destDir: String srcs: (List String) -> Int64
  (fold (fn [(n Int64) (src String)] -> Int64 (let [(r (settleOne! destDir src))] (if (< r 0) -1000000000 (+ n r)))) 0 srcs)

; (:m :ref STAGE-CONCURRENT-RUNS :do "a staged clone is current when dest is a link (it names the source) or a regular file of the source size no older than the source; only stale ones are cloned, into a hidden per-process dir beside them, and each is renamed over its dest, so a concurrent run never finds a data file removed or half cloned (ERR_PARQUET cannot read column chunk, vtbot 2026-10-30)")
fn ! cloneCurrent? src: String dest: String -> Bool
  (match (fileLstat dest)
    ((err _) false)
    ((ok lst) (or lst.isSymlink
                  (match (fileStat src)
                    ((err _) false)
                    ((ok st) (and (= lst.size st.size) (>= lst.mtimeNs st.mtimeNs)))))))

fn ! landClones! tmp: String destDir: String names: (List String) -> Bool
  (let [(moved (map (fn [(n String)] -> Bool (or (not (fileExists? (str tmp "/" n))) (ok? (pathRename (str tmp "/" n) (str destDir "/" n))))) names))
        (_ (runIn! destDir (list "rm" "-rf" "--" tmp)))]
    (listAll? (fn [(b Bool)] -> Bool b) moved))

fn ! cloneChunks! destDir: String srcs: (List String) -> Int64
  (if (listEmpty? srcs)
    0
    (let [(chunk (filter (fn [(src String)] -> Bool (not (cloneCurrent? src (str destDir "/" (sys/baseName src))))) (listTake srcs 200)))
          (rest (listDrop srcs 200))
          (tmp (str destDir "/.stage." (stringFromInt64 (procSelf))))
          (here (cond
                  ((listEmpty? chunk) 0)
                  ((not (ok? (ensureDir! tmp))) -1000000000)
                  (else (let [(n (if (cloneBatch! tmp chunk) 0 (settleEach! tmp chunk)))]
                          (if (landClones! tmp destDir (map sys/baseName chunk)) n -1000000000)))))
          (more (cloneChunks! destDir rest))]
      (+ here more)))

fn ! cloneDirGroups! groups: (List (Pair String (List String))) -> (Result Int64 String)
  (match (listHead groups)
    ((none) (ok 0))
    ((some g)
      (match (ensureDir! (pairFirst g))
        ((err e) (err (str "cannot create " (pairFirst g) ": " e)))
        ((ok _)
          (let [(n (cloneChunks! (pairFirst g) (pairSecond g)))]
            (if (< n 0)
              (err (str "cannot clone, copy or link into " (pairFirst g)))
              (match (cloneDirGroups! (optionOr (listTail groups) (list)))
                ((err e) (err e))
                ((ok m) (ok (+ n m))))))))))

fn ! groupByDir files: (List (Pair String String)) -> (List (Pair String (List String)))
  (fold (fn [(acc (List (Pair String (List String)))) (f (Pair String String))] -> (List (Pair String (List String)))
          (let [(dir (ckr/parentDirOf (pairSecond f)))]
            (if (listAny? (fn [(g (Pair String (List String)))] -> Bool (= (pairFirst g) dir)) acc)
              (map (fn [(g (Pair String (List String)))] -> (Pair String (List String)) (if (= (pairFirst g) dir) (pair dir (cons (pairFirst f) (pairSecond g))) g)) acc)
              (cons (pair dir (list (pairFirst f))) acc))))
        (list) files)

fn ! mirrorFiles! root: String mirrorDir: String files: (List String) -> (Result Unit String)
  (let [(plan (map (fn [(f String)] -> (Pair String String) (pair f (str mirrorDir "/" (dropPrefixLen f (+ (stringLength root) 1))))) files))
        (copies (filter (fn [(p (Pair String String))] -> Bool (sourceSized? (pairFirst p))) plan))
        (links (filter (fn [(p (Pair String String))] -> Bool (not (sourceSized? (pairFirst p)))) plan))]
    (match (mirrorCopies! copies)
      ((err e) (err e))
      ((ok _) (match (cloneDirGroups! (groupByDir links))
                ((err e) (err e))
                ((ok linked) (do (if (> linked 0) (eprintln (str "(:stage :symlinked " (stringFromInt64 linked) " :over " (stringFromInt64 (cloneLimitBytes)) " :why clone-failed :into " mirrorDir ")")) ()) (ok ())))))))

fn ! mirrorCopies! copies: (List (Pair String String)) -> (Result Unit String)
  (match (listHead copies)
    ((none) (ok ()))
    ((some c)
      (match (mirrorFile! (pairFirst c) (pairSecond c))
        ((err e) (err e))
        ((ok _) (mirrorCopies! (optionOr (listTail copies) (list)))))))

fn ! writeMirrorConfig! root: String mirrorDir: String -> (Result Unit String)
  (let [(origText (resultOr (fileReadString (str root "/.asl.config.asn")) ""))
        (ws (workspaceNameOf origText))
        (synth (str "(:asl-config :workspace \"" ws "\" :root true)\n"))]
    (writeAtomic! (str mirrorDir "/.asl.config.asn") (stringToBytes synth)))

; (:m :ref NATIVETEST-OUTSIDE-CLOSURE-20261020 :do "a test opens data files (parquet fixtures, .asn contracts) by paths relative to the package, so the mirror carries every tracked and untracked-but-not-ignored file of the package as bytes, listed by git; a package that is not a git work tree falls back to every file outside dot-directories plus the .asl files under .asl/mem that the index walk skips")
fn ! gitFiles! root: String -> (Option (List String))
  (let [(d (run/runOneLimited (run/job (list "git" "-C" root "ls-files" "-co" "--exclude-standard") root (run/childEnv (list))) (run/limits 60 8)))]
    (if (= d.exit 0)
      (some (filter (fn [(p String)] -> Bool (sys/isFile? p)) (map (fn [(l String)] -> String (str root "/" l)) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines d.out)))))
      (none)))

fn ! fallbackFiles! root: String -> (List String)
  (let [(memDir (str root "/.asl/mem"))]
    (listAppend (tsa/filesUnder! root) (filter (fn [(p String)] -> Bool (stringEndsWith? p ".asl")) (if (sys/isDir? memDir) (tsa/filesUnder! memDir) (list)))))

; (:m :ref NATIVETEST-MIRRORDATA-20261023 :do "git-ignored data (exported parquet, several GB across a workspace) is not mirrored by default; a package opts directories in with :testData (\"datasets/export\") in its .asl.config.asn, and those directories are mirrored as bytes beside the git-listed files")
fn ! quotedStringsIn s: String -> (List String)
  (match (stringIndexOf s "\"")
    ((none) (list))
    ((some q1) (let [(afterQ1 (dropPrefixLen s (+ q1 1)))]
      (match (stringIndexOf afterQ1 "\"")
        ((none) (list))
        ((some q2) (cons (optionOr (stringSlice afterQ1 0 q2) "") (quotedStringsIn (dropPrefixLen afterQ1 (+ q2 1)))))))))

fn ! testDataDirs configText: String -> (List String)
  (match (afterNeedle configText ":testData")
    ((none) (list))
    ((some rest) (match (stringIndexOf rest "\n")
      ((none) (list))
      ((some close) (quotedStringsIn (optionOr (stringSlice rest 0 close) ""))))))

; (:m :ref INBOXFIX-TESTDATAFILE-20261028 :do "a :testData entry is a directory (every file under it) or a regular file (that file at its relative path); an entry that is neither is an error naming it, never dropped")
fn ! testDataEntryFiles! root: String entry: String -> (Result (List String) String)
  (let [(path (str root "/" entry))]
    (cond
      ((sys/isDir? path) (ok (tsa/filesUnder! path)))
      ((sys/isFile? path) (ok (list path)))
      (else (err (str ":testData entry \"" entry "\" is neither a file nor a directory under " root)))))

fn ! testDataFiles! root: String configText: String -> (Result (List String) String)
  (fold (fn [(acc (Result (List String) String)) (d String)] -> (Result (List String) String)
          (match acc
            ((err e) (err e))
            ((ok files) (match (testDataEntryFiles! root d) ((err e) (err e)) ((ok more) (ok (listAppend files more)))))))
        (ok (list)) (testDataDirs configText))

; (:m :ref MAINRED4-SYMLINK-20261025 :do "the index walk never indexes a symlink, so a symlinked .asl in a package is no module of it (the escapePkg confinement fixture); the mirror copies bytes through symlinks, which turned such an entry into a real module inside the staged root, so symlinked .asl files are left out of the mirror")
fn ! indexable? path: String -> Bool
  (or (not (stringEndsWith? path ".asl")) (match (fileLstat path) ((ok st) (not st.isSymlink)) ((err _) true)))

; (:m :ref MAINRED5-CLOSURE-20261026 :do "mirroring every first-party file into each staged root cost 11.8MB per stage (MIRROR-FIRSTPARTY-COST); only the first-party modules reachable from the staged sources through header :i entries, plus the manifests of their packages, are mirrored. The header scan is textual (the region from :i [ to the next ]), a superset of the real imports, never a subset")
fn ! tokensOf s: String -> (List String)
  (filter (fn [(t String)] -> Bool (and (not (stringEmpty? t)) (not (stringStartsWith? t ":"))))
          (stringSplit (stringReplace (stringReplace s "\n" " ") "\t" " ") " "))

fn ! rawTokens s: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringReplace (stringReplace s "\n" " ") "\t" " ") " "))

fn ! importNamesIn src: String -> (List String)
  (match (stringIndexOf src ":i [")
    ((none) (list))
    ((some k)
      (let [(rest (dropPrefixLen src (+ k 4)))
            (region (match (stringIndexOf rest "]") ((some e) (optionOr (stringSlice rest 0 e) "")) ((none) "")))
            (pieces (stringSplit region "("))]
        (listAppend (tokensOf (optionOr (listHead pieces) ""))
          (fold (fn [(acc (List String)) (p String)] -> (List String)
                  (let [(sp (stringSplit p ")"))
                        (first (optionOr (listHead (rawTokens (optionOr (listHead sp) ""))) ""))]
                    (listAppend (if (stringEmpty? first) acc (listAppend acc (list first))) (tokensOf (optionOr (listGet sp 1) "")))))
                (list) (optionOr (listTail pieces) (list)))))))

fn ! moduleNameIn src: String -> String
  (match (stringIndexOf src "(module ")
    ((none) "")
    ((some k) (optionOr (listHead (rawTokens (stringReplace (optionOr (stringSlice src (+ k 8) (+ k 200)) (dropPrefixLen src (+ k 8))) ")" " "))) "")))

fn ! keyOf path: String -> String
  (if (stringEndsWith? path ".asl") (optionOr (stringSlice path 0 (- (stringLength path) 4)) path) path)

fn ! indexFirstParty! root: String files: (List String) -> (Map String String)
  (fold (fn [(m (Map String String)) (p String)] -> (Map String String)
          (if (stringEndsWith? p ".asl")
            (let [(withPath (mapSet m (str "path:" (keyOf p)) p))
                  (n (moduleNameIn (resultOr (fileReadString p) "")))]
              (if (stringEmpty? n) withPath (mapSet withPath (str "mod:" n) p)))
            m))
        (mapEmpty) files)

fn ! resolveFirstParty idx: (Map String String) root: String dir: String name: String -> (Option String)
  (if (stringContains? name "/")
    (match (mapGet idx (str "mod:" name))
      ((some p) (some p))
      ((none) (mapGet idx (str "path:" root "/" name))))
    (let [(parent (ckr/parentDirOf dir))
          (tries (list (str "path:" dir "/" name) (str "path:" dir "/src/" name) (str "path:" parent "/" name) (str "mod:" name)))]
      (firstKeyHit idx tries)))

fn ! firstKeyHit idx: (Map String String) xs: (List String) -> (Option String)
  (match (listHead xs)
    ((none) (none))
    ((some x) (match (mapGet idx x) ((some v) (some v)) ((none) (firstKeyHit idx (optionOr (listTail xs) (list)))))))

fn ! closeFirstParty! idx: (Map String String) root: String pending: (List (Pair String String)) seen: (Map String Bool) -> (Map String Bool)
  (match (listHead pending)
    ((none) seen)
    ((some e)
      (let [(rest (optionOr (listTail pending) (list)))]
        (match (resolveFirstParty idx root (pairFirst e) (pairSecond e))
          ((none) (closeFirstParty! idx root rest seen))
          ((some p)
            (if (some? (mapGet seen p))
              (closeFirstParty! idx root rest seen)
              (let [(names (importNamesIn (resultOr (fileReadString p) "")))
                    (more (map (fn [(n String)] -> (Pair String String) (pair (ckr/parentDirOf p) n)) names))]
                (closeFirstParty! idx root (listAppend rest more) (mapSet seen p true)))))))))

fn ! manifestFor root: String path: String all: (Map String Bool) -> (Option String)
  (let [(dir (ckr/parentDirOf path))
        (m (str dir "/manifest.asn"))]
    (cond
      ((some? (mapGet all m)) (some m))
      ((or (<= (stringLength dir) (stringLength root)) (= dir "/")) (none))
      (else (manifestFor root dir all)))) 

fn ! firstPartyFiles! root: String staged: (List String) -> (List String)
  (let [(all (filter (fn [(p String)] -> Bool
                       (let [(rel (dropPrefixLen p (+ (stringLength root) 1)))]
                         (and (or (stringStartsWith? rel "asl/packages/") (stringStartsWith? rel "asl/tools/"))
                              (and (not (stringContains? rel "/tests/"))
                                   (or (stringEndsWith? rel ".asl") (stringEndsWith? rel "/manifest.asn"))))))
                     (optionOr (gitFiles! root) (fallbackFiles! root))))
        (idx (indexFirstParty! root all))
        (present (fold (fn [(m (Map String Bool)) (p String)] -> (Map String Bool) (mapSet m p true)) (mapEmpty) all))
        (initial (fold (fn [(acc (List (Pair String String))) (f String)] -> (List (Pair String String))
                         (if (stringEndsWith? f ".asl")
                           (listAppend acc (map (fn [(n String)] -> (Pair String String) (pair (ckr/parentDirOf f) n)) (importNamesIn (resultOr (fileReadString f) ""))))
                           acc))
                       (list) staged))
        (seen (closeFirstParty! idx root initial (mapEmpty)))
        (stagedNames (fold (fn [(m (Map String Bool)) (f String)] -> (Map String Bool)
                             (let [(n (if (stringEndsWith? f ".asl") (moduleNameIn (resultOr (fileReadString f) "")) ""))] (if (stringEmpty? n) m (mapSet m n true))))
                           (mapEmpty) staged))
        (mods (filter (fn [(p String)] -> Bool (not (some? (mapGet stagedNames (moduleNameIn (resultOr (fileReadString p) "")))))) (mapKeys seen)))
        (manifests (fold (fn [(acc (List String)) (p String)] -> (List String)
                           (match (manifestFor root p present) ((some m) (if (listAny? (fn [(x String)] -> Bool (= x m)) acc) acc (cons m acc))) ((none) acc)))
                         (list) mods))]
    (listAppend mods manifests))

; (:m :ref NATIVETEST-MIRRORASL-20261023 :do "the package is mirrored twice: flat under the digest directory, the working directory of its suite, so files read relative to the package root open, and again under <digest>/<workspace>/, the indexed root with the synthesized :root true config and the suite, so a file read by a workspace-qualified path (vtbot/asl/x.asl read as text, vtbot/asl/tests/fixtures/x.parquet) opens too; only the second copy sits under the config, so no module is indexed twice")
fn ! stagePackageMirror! ctx: sys/Context root: String -> (Result String String)
  (let [(digest (bytesSha256 (stringToBytes root)))
        (wsName (workspaceNameOf (resultOr (fileReadString (str root "/.asl.config.asn")) "")))
        (mirrorDir (str (outsidePkgStageDir ctx) "/" digest))
        (pkgDir (str mirrorDir "/" (if (stringEmpty? wsName) "pkg" wsName)))
        (cfgText (resultOr (fileReadString (str root "/.asl.config.asn")) ""))
        (dataFiles (testDataFiles! root cfgText))
        (files (filter indexable? (listAppend (optionOr (gitFiles! root) (fallbackFiles! root)) (resultOr dataFiles (list)))))]
    (match dataFiles
      ((err e) (err e))
      ((ok _) (stagePackageFiles! ctx root files digest mirrorDir pkgDir))))

; (:m :ref INBOXFIX-STALESTAGE-20261028 :do "staging mirrors the source exactly: after the copies, every regular file under the package's own staging dir (mirrorDir) that no copy wrote is removed, so a module deleted or checked out away no longer resolves; hidden paths (.used, .asl caches) are never pruned, nothing outside mirrorDir is touched, and the walk compares listings only (no recopy)")
fn ! stagedDests root: String dir: String files: (List String) -> (List String)
  (map (fn [(f String)] -> String (str dir "/" (dropPrefixLen f (+ (stringLength root) 1)))) files)

fn hiddenRel? rel: String -> Bool
  (listAny? (fn [(seg String)] -> Bool (stringStartsWith? seg ".")) (stringSplit rel "/"))

; (:m :ref LEON-LAUNCH-STAGE-RACE :do "a mirror file written in the last 600 s belongs to a concurrent stager with the same digest, so prune leaves it; five launches in one second lost bounded.asl and jobPool.asl to each other's prune")
fn ! freshStaged? path: String -> Bool
  (match (fileStat path)
    ((ok st) (< (- (nowNs) st.mtimeNs) 600000000000))
    ((err _) false))

fn ! pruneStaleStaged! mirrorDir: String expected: (List String) -> Int64
  (let [(keep (fold (fn [(m (Map String Bool)) (d String)] -> (Map String Bool) (mapSet m d true)) (mapEmpty) expected))
        (stale (filter (fn [(f String)] -> Bool (and (not (some? (mapGet keep f))) (and (not (hiddenRel? (dropPrefixLen f (+ (stringLength mirrorDir) 1)))) (not (freshStaged? f))))) (tsa/filesUnder! mirrorDir)))]
    (do (map (fn [(f String)] -> Bool (ok? (pathRemove f))) stale) (listLength stale)))

fn ! stagePackageFiles! ctx: sys/Context root: String files: (List String) digest: String mirrorDir: String pkgDir: String -> (Result String String)
  (match (ensureDir! pkgDir)
      ((err e) (err (str "cannot create " pkgDir ": " e)))
      ((ok _)
        (match (mirrorFiles! root mirrorDir files)
          ((err e) (err e))
          ((ok _)
            (match (mirrorFiles! root pkgDir files)
              ((err e) (err e))
              ((ok _)
                (match (mirrorFiles! ctx.root pkgDir (firstPartyFiles! ctx.root files))
                  ((err e) (err e))
                  ((ok _)
                    (match (writeMirrorConfig! root pkgDir)
                      ((err e) (err (str "cannot write " pkgDir "/.asl.config.asn: " e)))
                      ((ok _) (do (pruneStaleStaged! mirrorDir (listAppend (stagedDests root mirrorDir files) (listAppend (stagedDests root pkgDir files) (listAppend (stagedDests ctx.root pkgDir (firstPartyFiles! ctx.root files)) (list (str pkgDir "/.asl.config.asn")))))) (touchUsed! mirrorDir) (pruneStage! (outsidePkgStageDir ctx) "" digest) (ok pkgDir))))))))))))

fn ! stageOutside! ctx: sys/Context absFile: String -> (Result String String)
  (match (findPackageRoot! (ckr/parentDirOf absFile) 0)
    ((none) (stageOutsideSingle! ctx absFile))
    ((some root)
      (match (stagePackageMirror! ctx root)
        ((err e) (err e))
        ((ok mirrorDir) (ok (rooted ctx (str mirrorDir "/" (dropPrefixLen absFile (+ (stringLength root) 1)))))))))

fn ! runOutside! ctx: sys/Context file: String absFile: String args: (List String) -> Int64
  (if (not (sys/isFile? absFile))
    (do (sys/sayErr! (str "(:run :status :failed :error ERR_NO_FILE :message \"file not found: " file "\")")) 1)
    (match (stageOutside! ctx absFile)
      ((err e) (do (sys/sayErr! (str "(:run :status :failed :error ERR_BUILD :message \"cannot stage " file ": " e "\")")) 1))
      ((ok rel)
        (do (eprintln (str "NATIVE-BYPASS " file " :reason absolute-path-outside-workspace :staged " rel))
            (nativeTest! (listAppend (list "run" "--as" file (str ctx.root "/" rel)) (rest args)))))))

; (:m :ref R1-NATIVE-RECERT :do "nt/main prints its own 'FAIL path: ERR_NATIVE_UNSUPPORTED: path exports neither runTests nor main' when run! delegates straight to it, same generic wrap as the test-side gap but with no Built.reason string this layer could intercept; a cheap static nt/entryOf read of the file's own header, done here before delegating, catches the same no-entry case and reports it with the canonical ERR_NO_ENTRY CONTRACT.asn names, while any file that does declare an entry still goes to nativeTest! exactly as before")
; (:m :ref POSTFIX :do "the early-intercept FAIL line reinvented nt/main's own construction and got it wrong on 3 points: it rooted (relative) both path mentions where nt/main's runFile uses the raw absFile for the FAIL prefix and only the relative logical path for the message body, it dropped the colon after ERR_NO_ENTRY, and it appended a bogus (after 0 asserts) suffix nt/main's run leg never prints (that suffix is test/eval-only, from failLine, not runFile's bare failReason); matched verbatim to nt/main's own text so nativeCliTest's native-equals-asl-host comparison holds")
fn ! runEntryChecked! ctx: sys/Context absFile: String args: (List String) -> Int64
  (match (fileReadString absFile)
    ((err _) (nativeTest! (cons "run" (cons absFile (rest args)))))
    ((ok src)
      (if (listContains? (nt/exportsOf src) "main")
        (nativeTest! (cons "run" (cons absFile (rest args))))
        (do (eprintln (str "FAIL " absFile ": ERR_NO_ENTRY: " (rootedAbs ctx absFile) " exports neither runTests nor main")) 1))))

; (:m :ref OUT-OF-ROOT-USERPATH :do "an in-root file is run as absFile, not (rooted ctx absFile): nativeTest.asl's runFile now reads the path it is given against the caller's actual cwd (OUT-OF-ROOT-USERPATH), so a root-stripped name only resolves when cwd already equals root; absFile is cwd-independent and runFile derives its own logical/import name by stripping toolRoot internally")
fn ! run! ctx: sys/Context args: (List String) -> Int64
  (let [(file (first args))
        (absFile (resultOr (realPath file) file))
        (inRoot (inRoot? ctx absFile))]
    (cond
      ((or (listEmpty? args) (or (= file "--help") (= file "-h"))) (cmd/dispatch! ctx "run" args))
      ((not inRoot) (runOutside! ctx file absFile args))
      ((= (rootedAbs ctx absFile) "asl/tools/nativeTest.asl") (nativeTool! (rest args)))
      (else (runEntryChecked! ctx absFile args))))

fn ! eprintText text: String -> Unit
  (if (stringEmpty? text) () (do (eprintln (if (stringEndsWith? text "\n") (optionOr (stringSlice text 0 (- (stringLength text) 1)) text) text)) ()))

fn ! preludeOverride ctx: sys/Context -> String
  (str "ASL_PRELUDE=" ctx.root "/asl/host/out/prelude.asl")

fn ! hostJob ctx: sys/Context cwd: String path: String errFile: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$NATIVE_HOST_ERR\"" ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/command.asl") "test" path) cwd
           (run/childEnv (list (str "NATIVE_HOST_ERR=" errFile))))

fn oneLine text: String -> String
  (stringReplace (stringTrim text) "\n" " ")

; (:m :ref R1-NATIVE-RECERT :do "the lowering pass rejects an unbuilt file with its own ERR_LOWER_* vocabulary, wrapped generically as ERR_NATIVE_UNSUPPORTED by every caller below; CONTRACT.asn names the canonical code verbatim, so recognize the well-known lowering shapes and surface that code; an unrecognized shape keeps the generic tag")
fn unsupportedCode reason: String -> String
  (cond
    ((stringContains? reason "exports neither runTests nor main") "ERR_NO_ENTRY")
    ((and (stringContains? reason "imports ") (or (stringContains? reason "not declared") (stringContains? reason "has an empty, . or .. segment"))) "ERR_UNRESOLVED_IMPORT")
    ((stringContains? reason "[ERR_LOWER_ARITY]") "ERR_ARITY")
    ((stringContains? reason "is neither a module function nor a builtin") "ERR_UNKNOWN_SYMBOL")
    ((stringContains? reason "unknown symbol '") "ERR_UNKNOWN_SYMBOL")
    ((stringContains? reason "declares no '") "ERR_UNKNOWN_SYMBOL")
    ((stringContains? reason "nested deeper than") "ERR_DEPTH")
    (else ""))

fn unsupportedTag reason: String -> String
  (let [(code (unsupportedCode reason))] (if (stringEmpty? code) "ERR_NATIVE_UNSUPPORTED" code))

fn ! gapNote path: String reason: String -> Unit
  (do (eprintln (str "asl: " path " runs on asl-host: " (unsupportedTag reason) ": " (oneLine reason))) ())

fn ! hostSuite! ctx: sys/Context path: String reason: String -> Int64
  (if (not (sys/executable? ctx.hostBin))
    (do (eprintln (str "FAIL " path ": " (unsupportedTag reason) ": " reason " (after 0 asserts)")) 1)
    (let [(_ (gapNote path reason))
          (errFile (str "/tmp/aslNativeHost" (stringFromInt64 (procSelf)) ".err"))
          (timeoutS (resultOr (sw/timeoutWanted!) 1800))
          (d (run/runOneLimited (hostJob ctx "." path errFile) (run/limits timeoutS 64)))
          (errText (resultOr (fileReadString errFile) ""))
          (_ (pathRemove errFile))]
      (do (print d.out)
          (eprintText errText)
          (if (= d.verdict "exit") d.exit (do (eprintln (str "FAIL " path ": asl-host " d.verdict " after " (stringFromInt64 timeoutS) "s (after 0 asserts)")) 124)))))

fn ! suiteRelPath! ctx: sys/Context path: String -> (Result String String)
  (let [(absPath (resultOr (realPath path) path))]
    (if (inRoot? ctx absPath)
      (ok (rootedAbs ctx absPath))
      (stageOutside! ctx absPath)))

fn ! suite! ctx: sys/Context fp: String path: String -> Int64
  (match (suiteRelPath! ctx path)
    ((err e) (do (eprintln (str "FAIL " path ": ERR_BUILD cannot stage " path ": " e " (after 0 asserts)")) 1))
    ((ok rel) (suiteBuilt! ctx fp path rel)))

; (:m :ref OUT-OF-ROOT-USERPATH :do "rel is always root-relative (rooted for an in-root file, stageOutside!'s rel for a staged one); nt/prepare would read it bare against the actual cwd (OUT-OF-ROOT-USERPATH), wrong whenever test! skipped reexecTestAtRoot! (anyOutOfRoot?) and cwd never became ctx.root, so prepareSourceIn reads the absolute ctx.root-anchored path while keeping rel as the logical/import name")
; (:m :ref NATIVETEST-OUTSIDE-CLOSURE-20261020 :do "a staged package sits at <digest>/<workspace>/ under outsidePkg and its suite runs with <digest> as the working directory, the arrangement of the source tree where the package directory is named by its workspace, so a data path written workspace-qualified (vtbot/asl/tests/fixtures/x.parquet) opens the same file; every other suite keeps the cwd it was started with")
fn ! suiteCwd ctx: sys/Context rel: String -> (Option String)
  (let [(marker ".asl/cache/nativeTest/outsidePkg/")]
    (if (stringStartsWith? rel marker)
      (let [(tail (dropPrefixLen rel (stringLength marker)))
            (digest (optionOr (listHead (stringSplit tail "/")) ""))]
        (some (str ctx.root "/" marker digest)))
      (none)))

fn ! suiteBuilt! ctx: sys/Context fp: String path: String rel: String -> Int64
  (let [(built (nt/prepareTestSource (str ctx.root "/" rel) rel fp))]
    (match built.binary
      ((some binPath)
        (let [(bin (if (stringStartsWith? binPath "/") binPath (str ctx.root "/" binPath)))
              (out (nt/runProcIn (list "nice" "-n" "15" bin) (suiteCwd ctx rel) (some (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (nt/initPhaseOff))))))
              (v (nt/judgeInit! bin path (preludeOverride ctx) (nt/verdictOf path out.exitCode out.stderr)))]
          (do (print out.stdout)
              (eprintText v.stderr)
              (if (= v.exit 0) (println v.line) (eprintln v.line))
              v.exit)))
      ((none) (if (= built.cache "checker-reject")
                (do (eprintln (nt/suiteFailLine ctx.root rel path built.reason)) 1)
                (hostSuite! ctx path built.reason)))))

fn ! suites! ctx: sys/Context paths: (List String) -> Int64
  (if (not (sys/isFile? (str ctx.root "/asl/host/out/libaslrt.a")))
    (do (eprintln (str "asl test: " ctx.root "/asl/host/out/libaslrt.a not found; run sh asl/host/build.sh")) 2)
    (let [(fp (nt/fingerprint))
          (codes (map (fn [(p String)] -> Int64 (if (sys/isFile? p) (suite! ctx fp p) (do (eprintln (str p ":0:0: ERR_IO cannot open file\nFAIL " p ": 1 load error(s) (after 0 asserts)")) 1))) paths))]
      (optionOr (listHead (filter (fn [(c Int64)] -> Bool (!= c 0)) codes)) 0)))

fn ! absolute path: String -> String
  (if (stringStartsWith? path "/") path (str (resultOr (realPath ".") ".") "/" path))

fn ! sweepJob ctx: sys/Context ws: String tmp: String i: Int64 bin: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" 2>\"$NATIVE_SWEEP_ERR\"" bin) ws
           (run/childEnv (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (nt/initPhaseOff) (str "NATIVE_SWEEP_ERR=" tmp "/" (stringFromInt64 i) ".err"))))

fn ! initProbeJob ctx: sys/Context ws: String tmp: String i: Int64 bin: String -> run/Job
  (run/job (list "/bin/sh" "-c" "exec \"$0\" 2>\"$NATIVE_SWEEP_ERR\"" bin) ws
           (run/childEnv (list "ASL_ASSERT_REPORT=1" (preludeOverride ctx) (nt/initPhaseOn) (str "NATIVE_SWEEP_ERR=" tmp "/" (stringFromInt64 i) ".init.err"))))

fn ! initProbed tmp: String timeoutS: Int64 done: sw/Done d: run/Done -> sw/Done
  (if (!= d.verdict "exit")
    (sw/Done :index done.index :path done.path :code 124 :last (str "module-initialization probe timed out after " (stringFromInt64 timeoutS) "s") :out done.out)
    (match (nt/initVerdict done.path d.exit (resultOr (fileReadString (str tmp "/" (stringFromInt64 done.index) ".init.err")) ""))
      ((none) done)
      ((some v) (sw/Done :index done.index :path done.path :code v.exit :last v.line :out ""))))

fn ! sweepInitProbes! ctx: sys/Context ws: String tmp: String timeoutS: Int64 k: Int64 pairs: (List (Pair sw/Done String)) -> (List sw/Done)
  (let [(passed (filter (fn [(p (Pair sw/Done String))] -> Bool (= (pairFirst p).code 0)) pairs))
        (failed (filter (fn [(p (Pair sw/Done String))] -> Bool (!= (pairFirst p).code 0)) pairs))
        (jobs (map (fn [(p (Pair sw/Done String))] -> run/Job (initProbeJob ctx ws tmp (pairFirst p).index (pairSecond p))) passed))
        (ran (run/runPoolLimited jobs k (run/limits timeoutS 64)))]
    (listAppend (map (fn [(p (Pair (Pair sw/Done String) run/Done))] -> sw/Done (initProbed tmp timeoutS (pairFirst (pairFirst p)) (pairSecond p))) (zip passed ran))
                (map (fn [(p (Pair sw/Done String))] -> sw/Done (pairFirst p)) failed)))

fn ! sweepVerdict tmp: String timeoutS: Int64 i: Int64 path: String d: run/Done -> sw/Done
  (if (!= d.verdict "exit")
    (sw/Done :index i :path path :code 124 :last (str "timed out after " (stringFromInt64 timeoutS) "s") :out "")
    (let [(v (nt/verdictOf path d.exit (resultOr (fileReadString (str tmp "/" (stringFromInt64 i) ".err")) "")))
          (out (if (= v.exit 0) (str d.out v.line "\n") d.out))
          (errText (if (= v.exit 0) v.stderr (str v.stderr "\n" v.line)))]
      (sw/Done :index i :path path :code v.exit :last (sw/lastLine (str out "\n" errText)) :out out)))

fn ! sweepDone! ctx: sys/Context ws: String timeoutS: Int64 k: Int64 files: (List String) -> (List sw/Done)
  (let [(fp (nt/fingerprint))
        (rootReal (resultOr (realPath ctx.root) ctx.root))
        (tmp (str "/tmp/aslNativeSweep" (stringFromInt64 (procSelf))))
        (made (dirCreate tmp))
        (rel (map (fn [(ip (Pair Int64 String))] -> String (nt/relativeTo rootReal (str ws "/" (pairSecond ip)))) (enumerate files)))
        (built (zip (enumerate files) (nt/prepareAll rel fp k)))
        (runnable (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (some? (pairSecond b).binary)) built))
        (rejected (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (and (none? (pairSecond b).binary) (= (pairSecond b).cache "checker-reject"))) built))
        (unbuilt (filter (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (and (none? (pairSecond b).binary) (!= (pairSecond b).cache "checker-reject"))) built))
        (jobs (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> run/Job (sweepJob ctx ws tmp (pairFirst (pairFirst b)) (absolute (optionOr (pairSecond b).binary "")))) runnable))
        (ran (if (ok? made) (run/runPoolLimited jobs k (run/limits timeoutS 64)) (list)))
        (judged (map (fn [(p (Pair (Pair (Pair Int64 String) nt/Built) run/Done))] -> (Pair sw/Done String)
                       (pair (sweepVerdict tmp timeoutS (pairFirst (pairFirst (pairFirst p))) (pairSecond (pairFirst (pairFirst p))) (pairSecond p))
                             (absolute (optionOr (pairSecond (pairFirst p)).binary ""))))
                     (zip runnable ran)))
        (fromRuns (sweepInitProbes! ctx ws tmp timeoutS k judged))
        (fromChecker (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
                             (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 1
                                      :last (nt/failLine (pairSecond (pairFirst b)) (pairSecond b).reason) :out ""))
                           rejected))
        (fromBuilds (hostSweep! ctx ws tmp timeoutS k unbuilt))
        (lost (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
                     (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 127 :last (str "cannot create " tmp) :out ""))
                   (if (ok? made) (list) runnable)))
        (removed (pathRemove tmp))]
    (listAppend fromRuns (listAppend fromChecker (listAppend fromBuilds lost))))

fn ! hostSweep! ctx: sys/Context ws: String tmp: String timeoutS: Int64 k: Int64 unbuilt: (List (Pair (Pair Int64 String) nt/Built)) -> (List sw/Done)
  (let [(errOf (fn [(i Int64)] -> String (str tmp "/" (stringFromInt64 i) ".host.err")))
        (hosted (sys/executable? ctx.hostBin))
        (notes (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> Bool (do (if hosted (gapNote (pairSecond (pairFirst b)) (pairSecond b).reason) ()) true)) unbuilt))
        (ran (if hosted (run/runPoolLimited (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> run/Job (hostJob ctx ws (pairSecond (pairFirst b)) (errOf (pairFirst (pairFirst b))))) unbuilt) k (run/limits timeoutS 64)) (list)))]
    (if (not hosted)
      (map (fn [(b (Pair (Pair Int64 String) nt/Built))] -> sw/Done
             (sw/Done :index (pairFirst (pairFirst b)) :path (pairSecond (pairFirst b)) :code 1
                      :last (str "FAIL " (pairSecond (pairFirst b)) ": " (unsupportedTag (pairSecond b).reason) ": " (pairSecond b).reason " (after 0 asserts)") :out ""))
           unbuilt)
      (map (fn [(p (Pair (Pair (Pair Int64 String) nt/Built) run/Done))] -> sw/Done
             (let [(i (pairFirst (pairFirst (pairFirst p))))
                   (path (pairSecond (pairFirst (pairFirst p))))
                   (d (pairSecond p))]
               (if (!= d.verdict "exit")
                 (sw/Done :index i :path path :code 124 :last (str "timed out after " (stringFromInt64 timeoutS) "s") :out "")
                 (sw/Done :index i :path path :code d.exit :last (sw/lastLine (str d.out "\n" (resultOr (fileReadString (errOf i)) ""))) :out d.out))))
           (zip unbuilt ran))))

fn ! sweepFailed! verb: String e: String -> Int64
  (do (eprintln (str "(:" verb " :status :failed :error ERR_NOT_A_WORKSPACE :message \"" e "\")")) 1)

fn ! sweepTest! ctx: sys/Context -> Int64
  (match (sw/workspace!)
    ((err e) (sweepFailed! "sweep" e))
    ((ok ws)
      (match (sw/timeoutWanted!)
        ((err e) (sweepFailed! "sweep" e))
        ((ok timeoutS)
          (match (sw/jobsWanted!)
            ((err e) (sweepFailed! "sweep" e))
            ((ok jobs)
              (match (sw/plan! "test" ws)
                ((err e) (sweepFailed! "sweep" e))
                ((ok plan) (sw/report! "test" "native" (pairFirst plan) (pairSecond plan) (sweepDone! ctx ws timeoutS (max 1 jobs) (pairFirst plan)) (sw/frozenCountFor! "test" ws))))))))))

fn ! changedFailed! e: String -> Int64
  (do (eprintln (str "(:changed :status :failed :error ERR_SELECTION :message \"" e "\")")) 2)

fn ! changedTest! ctx: sys/Context args: (List String) -> Int64
  (let [(restArgs (filter (fn [(a String)] -> Bool (and (!= a "--changed") (!= a "--dry-run"))) (rest args)))
        (dryRun (listContains? args "--dry-run"))]
    (if (> (listLength restArgs) 1)
      (do (sys/say! "(:changed :status :failed :error ERR_USAGE :message \"asl test --changed [BASE] [--dry-run]\")") 2)
      (let [(base (optionOr (listHead restArgs) "main"))]
        (match (sw/changedPlan! base)
          ((err e) (changedFailed! e))
          ((ok plan)
           (let [(changed (pairFirst plan))
                 (selected (pairFirst (pairSecond plan)))
                 (frozen (pairSecond (pairSecond plan)))]
            (if dryRun
              (sw/changedDry! base changed selected frozen)
              (match (sw/workspace!)
                ((err e) (changedFailed! e))
                ((ok ws)
                  (match (sw/timeoutWanted!)
                    ((err e) (changedFailed! (str "ERR_TIMEOUT: " e)))
                    ((ok timeoutS) (sw/changedReport! base changed selected (sweepDone! ctx ws timeoutS 2 selected) frozen))))))))))))

; (:m :ref CHECK-FOREIGN-ASL-PKGS :do "asl check of a .asl file outside the toolchain root checks its staged mirror under the root (stageOutside!, the view asl test checks), where asl-* packages resolve; the caller's path stays in every line; in-root files and other arguments take the old path")
fn ! outsideAsl? ctx: sys/Context a: String -> Bool
  (and (stringEndsWith? a ".asl") (and (sys/isFile? a) (not (inRoot? ctx (resultOr (realPath a) a)))))

; (:m :ref CHECK-FOREIGN-LOWS :do "the staged view of one outside file: a package file checks inside the package mirror (stagePackageMirror!, the view asl test checks) with the flat mirror and the indexed <workspace>/ mirror both mapped back to the package root, absolute and root-relative; a lone file checks its single-file stage mapped back to the path given")
fn ! relForm ctx: sys/Context p: String -> String
  (if (stringStartsWith? p (str ctx.root "/")) (dropPrefixLen p (+ (stringLength ctx.root) 1)) p)

fn ! stagedView! ctx: sys/Context a: String -> (Result verify/Staged String)
  (let [(abs (resultOr (realPath a) a))]
    (match (findPackageRoot! (ckr/parentDirOf abs) 0)
      ((some root)
        (match (stagePackageMirror! ctx root)
          ((err e) (err (str a ": cannot stage: " e)))
          ((ok mirrorDir)
            (let [(wsRaw (workspaceNameOf (resultOr (fileReadString (str root "/.asl.config.asn")) "")))
                  (ws (if (stringEmpty? wsRaw) "pkg" wsRaw))
                  (indexed (str mirrorDir "/" ws "/"))
                  (flat (str mirrorDir "/"))]
              (ok (verify/Staged :actual (str mirrorDir "/" (dropPrefixLen abs (+ (stringLength root) 1))) :shown a
                                 :maps (list (pair indexed (str root "/")) (pair flat (str root "/"))
                                             (pair (relForm ctx indexed) (str root "/")) (pair (relForm ctx flat) (str root "/")))))))))
      ((none)
        (match (stageOutsideSingle! ctx abs)
          ((err e) (err (str a ": cannot stage: " e)))
          ((ok rel) (ok (verify/Staged :actual (str ctx.root "/" rel) :shown a :maps (list (pair rel a)))))))))

fn ! stagedViews! ctx: sys/Context files: (List String) -> (Result (List verify/Staged) String)
  (fold (fn [(acc (Result (List verify/Staged) String)) (a String)] -> (Result (List verify/Staged) String)
          (match acc
            ((err e) (err e))
            ((ok ss) (match (stagedView! ctx a) ((err e) (err e)) ((ok s) (ok (listAppend ss (list s))))))))
        (ok (list)) files)

fn ! bareSweepRefused! verb: String -> Int64
  (do (sys/say! (str "(:" verb " :status :failed :error ERR_BARE_SWEEP :message \"asl " verb " needs paths or --all; a bare asl " verb " would sweep every suite\")")) 2)

fn ! allWithPaths! verb: String -> Int64
  (do (sys/say! (str "(:" verb " :status :failed :error ERR_USAGE :message \"asl " verb " --all takes no paths\")")) 2)

fn ! check! ctx: sys/Context args: (List String) -> Int64
  (cond
    ((listEmpty? args) (bareSweepRefused! "check"))
    ((and (listContains? args "--all") (> (listLength args) 1)) (allWithPaths! "check"))
    ((= args (list "--all")) (match (sw/nativeCheckSweep!) ((ok code) code) ((err e) (do (sys/sayErr! e) 1))))
    (else (checkPaths! ctx args)))

fn ! checkPaths! ctx: sys/Context args: (List String) -> Int64
  (let [(outside (filter (fn [(a String)] -> Bool (outsideAsl? ctx a)) args))
        (others (filter (fn [(a String)] -> Bool (not (outsideAsl? ctx a))) args))]
    (if (listEmpty? outside)
      (cmd/dispatch! ctx "check" args)
      (match (stagedViews! ctx outside)
        ((err e) (do (sys/sayErr! e) 1))
        ((ok views)
          (let [(inRootAsl (filter (fn [(a String)] -> Bool (stringEndsWith? a ".asl")) others))
                (nonAsl (filter (fn [(a String)] -> Bool (not (stringEndsWith? a ".asl"))) others))
                (all (listAppend views (map (fn [(a String)] -> verify/Staged (verify/Staged :actual a :shown a :maps (list))) inRootAsl)))
                (rc (verify/checkStaged! all nonAsl))]
            rc)))))

fn ! rootRelativeArg ctx: sys/Context a: String -> String
  (rootedAbs ctx (resultOr (realPath a) a))

fn ! reexecTestAtRoot! ctx: sys/Context args: (List String) dir: String -> Int64
  (sys/execv! (listAppend (list "/bin/sh" "-c" "cd -- \"$0\" && exec \"$@\"" ctx.root (str ctx.root "/bin/asl") "test")
                          (listAppend (if (stringEmpty? dir) (list) (list "--jobserverDir" dir))
                          (map (fn [(a String)] -> String (rootRelativeArg ctx a)) args)))
              (list))

fn ! outOfRoot? ctx: sys/Context a: String -> Bool
  (not (inRoot? ctx (resultOr (realPath a) a)))

; (:m :ref OUT-OF-ROOT-USERPATH :do "reexecTestAtRoot! exists so a plain-file arg given relative to a toolchain SUBdirectory still resolves (cd to root, then make the arg root-relative); an already-absolute, genuinely out-of-root arg (a /tmp fixture repo, fleetCompareTest's base/head) gains nothing from that cd and loses everything from it, since the fixture's own relative data-file reads (at runtime, inside the compiled suite) stay anchored to whatever cwd the reexec left behind, not the fixture's own root; skip the reexec for those and let the normal else-branch pipeline (suites!, whose suiteRelPath! already stages a genuinely out-of-root path) run with cwd untouched")
fn ! anyOutOfRoot? ctx: sys/Context args: (List String) -> Bool
  (listAny? (fn [(a String)] -> Bool (outOfRoot? ctx a)) (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) args))

fn ! test! ctx: sys/Context args: (List String) dir: String -> Int64
  (let [(tracing (or (listContains? args "--trace") (= (optionOr (envGet "ASL_TRACE") "0") "1")))
        (plainFiles (and (not (listEmpty? args)) (and (not (listContains? args "--changed")) (and (not (listContains? args "--all")) (not (= (first args) "--native"))))))
        (hosted (or (listContains? args "--compare") (or tracing (and (not plainFiles) (not (atRoot? ctx))))))]
    (cond
      (hosted (cmd/dispatch! ctx "test" args))
      ((and plainFiles (not (atRoot? ctx)) (not (anyOutOfRoot? ctx args))) (reexecTestAtRoot! ctx args dir))
      ((listContains? args "--changed") (changedTest! ctx args))
      ((listEmpty? args) (bareSweepRefused! "test"))
      ((listContains? args "--all") (if (= args (list "--all")) (sweepTest! ctx) (allWithPaths! "test")))
      ((= (first args) "--native") (if (listEmpty? (rest args)) (cmd/dispatch! ctx "test" args) (suites! ctx (rest args))))
      (else (match (cmd/testFiles! args (list))
              ((err code) code)
              ((ok paths)
                (let [(dirs (filter (fn [(a String)] -> Bool (sys/isDir? a)) args))
                      (selection (runner/selectDirectorySuites! ctx.root paths dirs))
                      (selected (pairFirst selection))
                      (frozen (pairSecond selection))
                      (note (if (listEmpty? dirs) true (sys/say! (str "(:test :frozen " (stringFromInt64 (listLength frozen)) ")"))))]
                  (suites! ctx selected)))))))

fn readCode msg: String -> String
  (if (or (or (stringStartsWith? msg "unmatched") (stringStartsWith? msg "unclosed")) (or (stringContains? msg "' closes '") (stringContains? msg "unterminated")))
    "ERR_READ_UNBALANCED"
    "ERR_READ")

fn ! parse! ctx: sys/Context args: (List String) -> Int64
  (if (listEmpty? args)
    (cmd/dispatch! ctx "parse" args)
    (let [(path (first args))]
      (match (fileReadString path)
        ((err _) (do (sys/sayErr! (str path ": ERR_IO cannot read file")) 1))
        ((ok src) (match (ip/parseIndentedFormsPos src)
                    ((err e) (do (sys/sayErr! (str path ":" (stringFromInt64 e.line) ":" (stringFromInt64 e.col) ": " (readCode e.msg) " " e.msg)) 1))
                    ((ok forms) (do (sys/say! (str (stringFromInt64 (listLength forms)) " top-level form(s)")) 0)))))))

fn evalSource expr: String -> String
  (str "(module nativeEval :x [main] :i [])\n\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(shown (str (list (do " expr "\n  ))))]\n"
       "    (do (println (optionOr (stringSlice shown 1 (- (stringLength shown) 1)) shown)) (ok 0)))\n")

fn ! printDiag! d: ty/Diagnostic -> Bool
  (sys/sayErr! (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message))

fn ! evalRejected! path: String reason: String -> Int64
  (let [(verdict (pairFirst (cc/checkFileCached! path (verify/checkRoots) (cc/emptyCache))))
        (diags (match verdict ((err _) (list)) ((ok v) v.diags)))]
    (if (listEmpty? diags)
      (do (sys/sayErr! (str "asl eval: " reason)) 1)
      (do (map printDiag! diags) 1)))

; (:m :ref BIN-NO-PERSIST-20261026 :do "asl eval builds into an ephemeral slot and removes it and its source after the run; only the shared library objects stay")
; (:m :ref NATIVECACHE-EVALNAME :do "the source is named by its text, pid and clock, so two evals of the same text at once never share, and remove, one file")
fn ! evalValue! ctx: sys/Context expr: String -> Int64
  (let [(src (evalSource expr))
        (digest (nt/slotKey "eval" src))
        (dir (str ctx.root "/.asl/cache/nativeTest/evals"))
        (path (str dir "/" digest "x" (stringFromInt64 (procSelf)) "x" (stringFromInt64 (monotonicNs)) ".asl"))
        (fp (nt/fingerprint))
        (cDir (let [(configured (optionOr (envGet "ASL_NATIVE_TEST_CACHE") ""))]
                (if (stringEmpty? configured) (str ctx.root "/.asl/cache/nativeTest") configured)))
        (slot (nt/ephemeralSlotIn! cDir))
        (key (nt/slotKey (str "eval:" (nt/importPathOf path) ":" slot) digest))
        (made (match (dirCreate dir) ((err e) (str e)) ((ok _) (match (fileWrite path src) ((err e) (str e)) ((ok _) (match (dirCreate slot) ((err e) (str e)) ((ok _) "")))))))]
    (if (not (stringEmpty? made))
      (do (pathRemove slot) (pathRemove path) (sys/sayErr! (str "asl eval: cannot prepare " path ": " made)) 1)
      (let [(built (nt/compileIn cDir path path src slot key fp "eval"))
            (code (match built.binary
                    ((none) (evalRejected! path built.reason))
                    ((some bin) (let [(out (nt/runProc (list bin) (some (nt/withEnvOverrides! (list (preludeOverride ctx))))))]
                                  (do (print out.stdout)
                                      (eprintText out.stderr)
                                      out.exitCode)))))
            (_ (pathRemove slot))
            (_ (pathRemove path))
            (_ (nt/sweepStore! cDir))]
        code)))

fn ! eval! ctx: sys/Context args: (List String) -> Int64
  (let [(expr (stringJoin args " "))
        (trimmed (sys/trimLeft expr))]
    (cond
      ((= (first args) "--native")
        (if (or (listEmpty? (rest args)) (not (atRoot? ctx))) (cmd/dispatch! ctx "eval" args) (nativeTest! (list "eval" (stringJoin (rest args) " ")))))
      ((stringStartsWith? trimmed "(:") (let [(r (cmd/asnEcho trimmed))] (do (sys/say! (pairFirst r)) (pairSecond r))))
      ((stringEmpty? (stringTrim expr)) (do (sys/say! "()") 0))
      (else (evalValue! ctx expr))))

fn ! launch! ctx: sys/Context args: (List String) -> Int64
  (match (launch/mainIn! ctx.root args) ((ok code) code) ((err e) (do (sys/sayErr! (str "asl launch: " e)) 1)))

; (:m :ref PKG-CLIENT :do "asl pkg runs natively like launch: the package manager client is asl-pack/pkgCli, no subprocess for the verb itself")
fn ! pkg! args: (List String) -> Int64
  (match (pkg/main args) ((ok code) code) ((err e) (do (sys/sayErr! (str "asl pkg: " e)) 1)))

fn ! forms! args: (List String) -> Int64
  (let [(result (forms/mainText! args))]
    (do (sys/say! (sys/stripTrailingNewlines (pairFirst result))) (pairSecond result)))

fn ! intel! ctx: sys/Context args: (List String) -> Int64
  (let [(oc (intel/runIntel! (intel/makeCtxFor! ctx.root) args))]
    (do (print oc.out)
        (if (stringEmpty? oc.err) () (eprintln (optionOr (stringSlice oc.err 0 (- (stringLength oc.err) 1)) "")))
        oc.code))

fn intelAlias verb: String -> String
  (cond
    ((listContains? (list "coupling" "graph" "complexity" "stubs" "trace") verb) verb)
    ((or (= verb "vitality") (= verb "full")) "vitality")
    (else ""))

; (:m :ref MACHINE-JOBSERVER :do "asl test and asl build hold one machine-wide CPU token of class writer for the life of this process (the pid stays the same across execv, and a dead owner's token is reclaimed), unless an ancestor already holds one; --jobserverDir DIR names the token dir (default ~/.asl/run/jobserver; none takes no token), stripped before dispatch; asl check and asl forms stay token-free; a wait past 30 minutes proceeds without a token")
fn jobserverDirOf args: (List String) -> String
  (match (listIndexOf args "--jobserverDir")
    ((some i) (optionOr (listGet args (+ i 1)) ""))
    ((none) ""))

fn withoutJobserverDir args: (List String) -> (List String)
  (match (listIndexOf args "--jobserverDir")
    ((some i) (listAppend (listTake args i) (listDrop args (+ i 2))))
    ((none) args))

fn ! jobserverToken! verb: String dir: String -> Bool
  (if (and (or (= verb "test") (= verb "build")) (!= dir "none"))
    (let [(g (js/acquireProc dir "writer" "cli" 1800000))]
      (if (= g.state "expired") (sys/sayErr! "(:jobserver :note tokenTimeout :proceeding true)") true))
    true)

fn ! dispatch! ctx: sys/Context verb: String args: (List String) -> Int64
  (let [(_ (jobserverToken! verb (jobserverDirOf args)))]
    (dispatchRaw! ctx verb (withoutJobserverDir args) (jobserverDirOf args)))

fn ! dispatchRaw! ctx: sys/Context verb: String args: (List String) dir: String -> Int64
  (cond
    ((or (stringStartsWith? verb "(") (stringStartsWith? verb ":")) (forms! (cons verb args)))
    ((= verb "rpc") (forms! args))
    ((= verb "intel") (intel! ctx args))
    ((not (stringEmpty? (intelAlias verb))) (intel! ctx (cons (intelAlias verb) args)))
    ((= verb "run") (run! ctx args))
    ((= verb "test") (test! ctx args dir))
    ((= verb "parse") (parse! ctx args))
    ((= verb "eval") (eval! ctx args))
    ((= verb "launch") (launch! ctx args))
    ((= verb "pkg") (pkg! args))
    ((= verb "check") (check! ctx args))
    (else (cmd/dispatch! ctx verb args)))

; (:m :ref SHEBANG :do "inline code is staged by content digest like an outside file and run as a script module in the caller's cwd, with the arguments after it")
; (:m :ref SCRIPT-ENTRY :do "asl -e and asl - stage their text under a name unique to this process (pid and a digest prefix), so concurrent runs of the same text never share or delete each other's file, and remove it once the run ends")
fn ! inlineStagePath ctx: sys/Context code: String mark: String -> String
  (if (stringStartsWith? mark "f")
    (str (outsideStageDir ctx) "/inline" mark ".asl")
    (str (outsideStageDir ctx) "/inline" mark (stringFromInt64 (procSelf)) "x" (optionOr (stringSlice (bytesSha256 (stringToBytes code)) 0 16) "") ".asl"))

fn ! runInline! ctx: sys/Context mark: String code: String args: (List String) -> Int64
  (let [(dest (inlineStagePath ctx code mark))]
    (match (ensureDir! (outsideStageDir ctx))
      ((err e) (do (sys/sayErr! (str "(:run :status :failed :error ERR_BUILD :message \"cannot create " (outsideStageDir ctx) ": " e "\")")) 1))
      ((ok _) (match (fileWrite dest code)
                ((err e) (do (sys/sayErr! (str "(:run :status :failed :error ERR_BUILD :message \"cannot write " dest ": " e "\")")) 1))
                ((ok _) (let [(exit (runEntryChecked! ctx dest (cons dest args))) (_ (pathRemove dest))] exit))))))

fn ! inlineUsage! -> Int64
  (do (sys/sayErr! "(:run :status :failed :error ERR_MISSING_ARG :message \"usage: asl -e CODE [ARG ...]\")") 2)

; (:m :ref SHEBANG :do "asl - reads stdin: text whose first form is keyword-headed, like (:tools), is a batch of operation forms as before; any other text is top-level script code and the arguments after - are its args")
fn ! stdinEntry! ctx: sys/Context args: (List String) -> Int64
  (match (cmd/readStdin! (list))
    ((err e) (do (sys/sayErr! (str "asl -: stdin: " e)) 2))
    ((ok text) (if (stringStartsWith? (sys/trimLeft text) "(:")
                 (if (listEmpty? (rest args)) (dispatch! ctx "rpc" (list (sys/stripTrailingNewlines text))) (do (sys/sayErr! "(:batch :status :failed :error ERR_MISSING_ARG :message \"usage: asl - reads forms from stdin and takes no other argument\")") 2))
                 (runInline! ctx "s" text (rest args)))))

; (:m :ref SHEBANG :do "a first argument that is an existing file and names a path (holds a / or ends in .asl) runs as a program: its main or top-level code when it has one, else its runTests; any verb without a / stays a verb, so verbs win over files of the same name; a file without the .asl suffix (an executable with a #! line) is staged by content")
fn ! pathArg? verb: String -> Bool
  (and (sys/isFile? verb) (or (stringContains? verb "/") (stringEndsWith? verb ".asl")))

fn ! runPath! ctx: sys/Context file: String args: (List String) -> Int64
  (match (fileReadString file)
    ((err _) (run! ctx (cons file args)))
    ((ok src) (cond ((not (listContains? (nt/exportsOf src) "main")) (dispatch! ctx "test" (cons file args)))
                    ((stringEndsWith? file ".asl") (run! ctx (cons file args)))
                    (else (runInline! ctx (str "f" (stringFromInt64 (procSelf)) "x-" (optionOr (listLast (stringSplit file "/")) file)) src args)))))

; (:m :ref ASL-STDIN-EDIT-HANG :do "asl -f FILE dispatches the file's forms through the native rpc like asl -; the command.asl main it used before spawned asl run asl-forms/main.asl, a source compile that never finished")
fn ! fileEntry! ctx: sys/Context args: (List String) -> Int64
  (if (or (!= (listLength args) 2) (not (sys/isFile? (first (rest args)))))
    (do (sys/say! "(:batch :status :failed :error ERR_MISSING_ARG :message \"usage: asl -f FILE, one readable file of forms and no other argument\")") 2)
    (match (fileReadString (first (rest args)))
      ((err _) (do (sys/say! "(:batch :status :failed :error ERR_MISSING_ARG :message \"usage: asl -f FILE, one readable file of forms and no other argument\")") 2))
      ((ok text) (dispatch! ctx "rpc" (list (sys/stripTrailingNewlines text))))))

fn ! entry! ctx: sys/Context args: (List String) -> Int64
  (let [(head (first args))]
    (cond
      ((= head "-e") (if (listEmpty? (rest args)) (inlineUsage!) (runInline! ctx "e" (first (rest args)) (rest (rest args)))))
      ((= head "-") (stdinEntry! ctx args))
      ((= head "-f") (fileEntry! ctx args))
      ((pathArg? head) (runPath! ctx head (rest args)))
      (else (let [(r (cmd/route! ctx args))]
              (dispatch! ctx (pairFirst r) (pairSecond r))))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (sys/context!)
    ((err e) (do (sys/sayErr! (str "(:asl :status :failed :error ERR_NO_WORKSPACE :message \"" e "\")")) (ok 2)))
    ((ok ctx) (match (nc/nativeGate! ctx args) ((some code) (ok code)) ((none) (match (cf/reroot! ctx args) ((some code) (ok code)) ((none) (ok (entry! ctx args))))))))
