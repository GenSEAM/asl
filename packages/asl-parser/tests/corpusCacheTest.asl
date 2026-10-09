(module asl-parser/tests/corpusCacheTest
  :x [runTests]
  :i [(asl-syntax/tests/asl/layoutCorpusLib :a lay)
      (asl-parser/tests/printReparseLib :a pr)
      (asl-syntax/tests/asl/corpusCache :a cc)])

fn fixedFiles -> (List String)
  (list "asl/packages/asl-syntax/src/core/bytesText.asl"
        "asl/packages/asl-syntax/src/core/print.asl"
        "asl/packages/asl-syntax/src/core/outline.asl")

fn layoutRun! cache: cc/Cache files: (List String) -> lay/CorpusStats
  (fold (fn [(s lay/CorpusStats) (f String)] -> lay/CorpusStats (lay/verifyCorpusFile! f s)) (lay/emptyCorpusStatsWith cache) files)

fn printRun! cache: cc/Cache files: (List String) -> pr/CorpusStats
  (fold (fn [(s pr/CorpusStats) (f String)] -> pr/CorpusStats (pr/verifyCorpusFile! f s)) (pr/emptyCorpusStatsWith cache) files)

fn sh! cmd: String -> ProcessOutput
  (processRun cmd)

fn runnerCounts stdout: String -> (Pair Int64 Int64)
  (mt (listHead (filter (fn [(l String)] -> Bool (stringContains? l " assertion(s) executed (")) (stringSplit stdout "\n")))
    ((none) (pair -1 -1))
    ((some line)
     (let [(tail (optionOr (listLast (stringSplit line ": ")) ""))
           (words (stringSplit tail " "))
           (executed (optionOr (stringToInt64 (optionOr (listGet words 0) "")) -1))
           (passed (optionOr (stringToInt64 (stringReplace (optionOr (listGet words 3) "") "(" "")) -1))]
       (pair executed passed))))

fn probe! cacheDir: String files: String -> ProcessOutput
  (sh! (str "ASL_CORPUS_CACHE='" cacheDir "' CORPUS_CACHE_PROBE_FILES='" files "' asl/host/out/asl-host test asl/packages/asl-parser/tests/corpusCacheProbe.asl 2>&1"))

fn countFiles! dir: String -> Int64
  (mt (dirList dir)
    ((err _) 0)
    ((ok names)
     (fold (fn [(n Int64) (name String)] -> Int64
             (let [(child (str dir "/" name))]
               (mt (fileStat child)
                 ((err _) n)
                 ((ok st) (if st.isDir (+ n (countFiles! child)) (+ n 1))))))
           0 names)))

fn testSecondRunHits! tmp: String fp: String -> Bool
  (let [(files (fixedFiles))
        (n (listLength files))
        (cache (cc/cacheAt (str tmp "/hits") fp))
        (lay1 (layoutRun! cache files))
        (lay2 (layoutRun! cache files))
        (pr1 (printRun! cache files))
        (pr2 (printRun! cache files))
        (joined (stringJoin files " "))
        (cold (probe! (str tmp "/runner") joined))
        (warm (probe! (str tmp "/runner") joined))
        (coldCounts (runnerCounts cold.stdout))
        (warmCounts (runnerCounts warm.stdout))
        (off1 (probe! "0" joined))
        (off2 (probe! "0" joined))]
    (do
      (assert (and (= lay1.cached 0) (= lay2.cached n)) (str "layoutCorpus cold run hits 0 and warm run hits " (stringFromInt64 n) ": " (stringFromInt64 lay1.cached) " then " (stringFromInt64 lay2.cached)))
      (assert (and (= lay1.matched lay2.matched) (and (= lay1.checked lay2.checked) (and (= lay2.bugs 0) (= lay2.checked n)))) "layoutCorpus warm stats equal cold stats")
      (assert (and (= pr1.cached 0) (= pr2.cached n)) (str "printReparse cold run hits 0 and warm run hits " (stringFromInt64 n) ": " (stringFromInt64 pr1.cached) " then " (stringFromInt64 pr2.cached)))
      (assert (and (= pr1.passed pr2.passed) (and (= pr2.bugs 0) (= pr2.passed n))) "printReparse warm stats equal cold stats")
      (assert (and (= cold.exitCode 0) (= warm.exitCode 0)) (str "probe runs exit 0: " cold.stdout warm.stdout))
      (assert (and (= coldCounts warmCounts) (and (= (pairFirst warmCounts) (pairSecond warmCounts)) (= (pairFirst warmCounts) (+ (* 3 n) 2))))
        (str "runner counts cold " (stringFromInt64 (pairFirst coldCounts)) "/" (stringFromInt64 (pairSecond coldCounts)) " warm " (stringFromInt64 (pairFirst warmCounts)) "/" (stringFromInt64 (pairSecond warmCounts)) " equal and " (stringFromInt64 (+ (* 3 n) 2))))
      (assert (and (stringContains? cold.stdout "liftLower: cached=0") (stringContains? warm.stdout (str "liftLower: cached=" (stringFromInt64 n)))) "liftLower cold run hits 0 and warm run hits every file")
      (assert (and (stringContains? warm.stdout (str "layoutCorpus: checked=" (stringFromInt64 n))) (stringContains? warm.stdout (str "bugs=0 cached=" (stringFromInt64 n)))) "runner warm run reports every file cached")
      (assert (and (= off2.exitCode 0) (and (stringContains? off2.stdout "liftLower: cached=0") (stringContains? off2.stdout "bugs=0 cached=0"))) "ASL_CORPUS_CACHE=0 disables the cache: a repeated run hits nothing")
      (and (= lay2.cached n) (and (= pr2.cached n) (= coldCounts warmCounts)))))

fn snapshotProbe! root: String cwd: String home: String files: String -> ProcessOutput
  (sh! (str "cd '" cwd "' && env -u ASL_CORPUS_CACHE HOME='" home "' CORPUS_CACHE_PROBE_FILES='" files "' '" root "/asl/host/out/asl-host' test '" root "/asl/packages/asl-parser/tests/corpusCacheProbe.asl' 2>&1"))

fn snapshotProbeNoHome! root: String cwd: String files: String -> ProcessOutput
  (sh! (str "cd '" cwd "' && env -u ASL_CORPUS_CACHE -u HOME CORPUS_CACHE_PROBE_FILES='" files "' '" root "/asl/host/out/asl-host' test '" root "/asl/packages/asl-parser/tests/corpusCacheProbe.asl' 2>&1"))

fn snapshotProbeEmptyHome! root: String cwd: String files: String -> ProcessOutput
  (sh! (str "cd '" cwd "' && env -u ASL_CORPUS_CACHE HOME='' CORPUS_CACHE_PROBE_FILES='" files "' '" root "/asl/host/out/asl-host' test '" root "/asl/packages/asl-parser/tests/corpusCacheProbe.asl' 2>&1"))

fn snapshotProbeEmptyCacheEnv! root: String cwd: String home: String files: String -> ProcessOutput
  (sh! (str "cd '" cwd "' && ASL_CORPUS_CACHE='' HOME='" home "' CORPUS_CACHE_PROBE_FILES='" files "' '" root "/asl/host/out/asl-host' test '" root "/asl/packages/asl-parser/tests/corpusCacheProbe.asl' 2>&1"))

fn probeFilesOnly! cwd: String -> ProcessOutput
  (sh! (str "mkdir -p '" cwd "/probeFiles' && cp asl/packages/asl-syntax/src/core/bytesText.asl '" cwd "/probeFiles/bytesText.asl' && cp asl/packages/asl-syntax/src/core/print.asl '" cwd "/probeFiles/print.asl' && cp asl/packages/asl-syntax/src/core/outline.asl '" cwd "/probeFiles/outline.asl'"))

fn snapshotFiles! root: String cwd: String -> ProcessOutput
  (sh! (str "mkdir -p '" cwd "/asl' '" cwd "/asl/packages' && ln -s '" root "/asl/prelude' '" cwd "/asl/prelude' && ln -s '" root "/asl/host' '" cwd "/asl/host' && ln -s '" root "/asl/packages/asl-parser' '" cwd "/asl/packages/asl-parser' && ln -s '" root "/asl/packages/asl-syntax' '" cwd "/asl/packages/asl-syntax' && ln -s '" root "/asl/packages/asl-json' '" cwd "/asl/packages/asl-json' && ln -s '" root "/asl/packages/asl-forms' '" cwd "/asl/packages/asl-forms' && mkdir -p '" cwd "/probeFiles' && cp asl/packages/asl-syntax/src/core/bytesText.asl '" cwd "/probeFiles/bytesText.asl' && cp asl/packages/asl-syntax/src/core/print.asl '" cwd "/probeFiles/print.asl' && cp asl/packages/asl-syntax/src/core/outline.asl '" cwd "/probeFiles/outline.asl'"))

fn testDefaultSnapshotCache! tmp: String -> Bool
  (let [(root (stringTrim (sh! "pwd").stdout))
        (files (list "probeFiles/bytesText.asl" "probeFiles/print.asl" "probeFiles/outline.asl"))
        (n (listLength files))
        (joined (stringJoin files " "))
        (home (str tmp "/home"))
        (snapA (str tmp "/snapshotA"))
        (snapB (str tmp "/snapshotB"))
        (snapC (str tmp "/snapshotC"))
        (snapNoHome (str tmp "/snapshotNoHome"))
        (snapEmptyHome (str tmp "/snapshotEmptyHome"))
        (snapEmptyCache (str tmp "/snapshotEmptyCache"))
        (emptyCacheHome (str tmp "/emptyCacheHome"))
        (made (sh! (str "mkdir -p '" home "'")))
        (copiedA (snapshotFiles! root snapA))
        (copiedB (snapshotFiles! root snapB))
        (first (snapshotProbe! root snapA home joined))
        (second (snapshotProbe! root snapB home joined))
        (copiedC (snapshotFiles! root snapC))
        (changedPath (str snapC "/probeFiles/bytesText.asl"))
        (original (resultOr (fileReadString changedPath) ""))
        (edited (fileWrite changedPath (str original "\n")))
        (third (snapshotProbe! root snapC home joined))
        (copiedNoHome (snapshotFiles! root snapNoHome))
        (noHome (snapshotProbeNoHome! root snapNoHome joined))
        (copiedEmptyHome (snapshotFiles! root snapEmptyHome))
        (emptyHome (snapshotProbeEmptyHome! root snapEmptyHome joined))
        (copiedEmptyCache (snapshotFiles! root snapEmptyCache))
        (madeEmptyCacheHome (sh! (str "mkdir -p '" emptyCacheHome "'")))
        (emptyCacheEnv (snapshotProbeEmptyCacheEnv! root snapEmptyCache emptyCacheHome joined))
        (allWarm (and (stringContains? second.stdout (str "layoutCorpus: checked=" (stringFromInt64 n)))
                      (and (stringContains? second.stdout (str "bugs=0 cached=" (stringFromInt64 n)))
                           (and (stringContains? second.stdout (str "liftLower: cached=" (stringFromInt64 n)))
                                (stringContains? second.stdout (str "printReparse: checked=" (stringFromInt64 n) " passed=" (stringFromInt64 n) " bugs=0 cached=" (stringFromInt64 n)))))))
        (oneChanged (and (stringContains? third.stdout (str "layoutCorpus: checked=" (stringFromInt64 n)))
                         (and (stringContains? third.stdout (str "bugs=0 cached=" (stringFromInt64 (- n 1))))
                              (and (stringContains? third.stdout (str "liftLower: cached=" (stringFromInt64 (- n 1))))
                                   (stringContains? third.stdout (str "printReparse: checked=" (stringFromInt64 n) " passed=" (stringFromInt64 n) " bugs=0 cached=" (stringFromInt64 (- n 1)))))))) ]
    (do
      (assert (= made.exitCode 0) "fresh HOME directory created")
      (assert (and (= copiedA.exitCode 0) (= copiedB.exitCode 0)) "two fresh snapshot copies made")
      (assert (and (= first.exitCode 0) (stringContains? first.stdout "cached=0")) (str "first snapshot is cold: " first.stdout))
      (assert (and (= second.exitCode 0) allWarm) (str "second distinct snapshot hits all " (stringFromInt64 n) " files in every suite: " second.stdout))
      (assert (and (= copiedC.exitCode 0) (ok? edited)) "third fresh snapshot has exactly one changed probe file")
      (assert (and (= third.exitCode 0) oneChanged) (str "one changed file misses while " (stringFromInt64 (- n 1)) " remain cached: " third.stdout))
      (assert (and (= copiedNoHome.exitCode 0) (and (= noHome.exitCode 0) (> (countFiles! (str snapNoHome "/.asl/cache/corpus")) 0))) "unset HOME falls back to the cwd-relative corpus cache")
      (assert (and (= copiedEmptyHome.exitCode 0) (and (= emptyHome.exitCode 0) (> (countFiles! (str snapEmptyHome "/.asl/cache/corpus")) 0))) "empty HOME falls back to the cwd-relative corpus cache")
      (assert (and (= copiedEmptyCache.exitCode 0) (and (= madeEmptyCacheHome.exitCode 0) (= emptyCacheEnv.exitCode 0))) (str "empty ASL_CORPUS_CACHE run succeeds: " emptyCacheEnv.stdout))
      (assert (and (> (countFiles! (str emptyCacheHome "/.asl/run/corpusCache")) 0) (= (countFiles! (str snapEmptyCache "/.asl/cache/corpus")) 0)) "empty ASL_CORPUS_CACHE uses the HOME default, not the cwd fallback")
      (and allWarm oneChanged)))

fn replaceRoot roots: (List (Pair String String)) from: String to: String -> (List (Pair String String))
  (map (fn [(r (Pair String String))] -> (Pair String String) (if (= (pairFirst r) from) (pair to (pairSecond r)) r)) roots)

fn pathCoveredByRoots? roots: (List (Pair String String)) path: String -> Bool
  (not (listEmpty? (filter (fn [(r (Pair String String))] -> Bool
                              (or (= path (pairFirst r)) (stringStartsWith? path (str (pairFirst r) "/" (pairSecond r))))) roots)))

fn testMissingRootsDisableCache! tmp: String root: String files: String -> Bool
  (let [(cwd (str tmp "/missingRoots"))
        (home (str tmp "/missingRootsHome"))
        (made (sh! (str "mkdir -p '" cwd "' '" home "'")))
        (copied (probeFilesOnly! cwd))
        (first (snapshotProbe! root cwd home files))
        (second (snapshotProbe! root cwd home files))
        (cachePath (str home "/.asl/run/corpusCache"))]
    (do
      (assert (and (= made.exitCode 0) (= copied.exitCode 0)) "missing-root snapshot contains only probe inputs")
      (assert (and (= first.exitCode 0) (stringContains? first.stdout "cached=0")) (str "first missing-root run is cold: " first.stdout))
      (assert (and (= second.exitCode 0) (stringContains? second.stdout "cached=0")) (str "missing fingerprint roots never reuse verdicts: " second.stdout))
      (assert (= (countFiles! cachePath) 0) (str "missing fingerprint roots write no shared cache entries: " (stringFromInt64 (countFiles! cachePath))))
      (and (stringContains? second.stdout "cached=0") (= (countFiles! cachePath) 0))))

fn ! testDefaultRootCoverage! tmp: String -> Bool
  (let [(roots (cc/defaultRoots))
        (closure (list "asl/packages/asl-parser/src/ast.asl"
                       "asl/packages/asl-parser/src/astConverter.asl"
                       "asl/packages/asl-parser/src/astPrinter.asl"
                       "asl/packages/asl-parser/src/reader.asl"
                       "asl/packages/asl-parser/src/indentParser.asl"
                       "asl/packages/asl-syntax/src/asl/layout.asl"
                       "asl/packages/asl-syntax/src/asl/lex.asl"
                       "asl/packages/asl-syntax/src/asl/paren.asl"
                       "asl/packages/asl-syntax/src/core/source.asl"
                       "asl/packages/asl-syntax/src/core/tree.asl"
                       "asl/packages/asl-parser/tests/printReparseLib.asl"
                       "asl/packages/asl-parser/tests/liftLowerIdentityTest.asl"
                       "asl/packages/asl-syntax/tests/asl/layoutCorpusLib.asl"
                       "asl/packages/asl-syntax/tests/asl/corpusCache.asl"
                       "asl/prelude/prelude.asl"
                       "asl/host/src/loader.c"
                       "asl/host/out/asl-host"
                       "asl/packages/asl-json/src/json.asl"
                       "asl/packages/asl-forms/src/main.asl"))
        (uncovered (filter (fn [(path String)] -> Bool (not (pathCoveredByRoots? roots path))) closure))
        (emptyDir (str tmp "/emptyFingerprintRoot"))
        (made (sh! (str "mkdir -p '" emptyDir "'")))
        (emptyRoots (replaceRoot roots "asl/prelude" emptyDir))]
    (do
      (assert (= made.exitCode 0) "empty root fixture created")
      (assert (not (cc/rootsAvailable?! emptyRoots)) "an existing root with no matching fingerprint files disables caching")
      (assert (listEmpty? uncovered) (str "cache suite dependency paths including host executable covered by defaultRoots: " (stringJoin uncovered " ")))
      (and (listEmpty? uncovered) (not (cc/rootsAvailable?! emptyRoots)))))

fn testParserChangeInvalidates! tmp: String -> Bool
  (let [(files (fixedFiles))
        (n (listLength files))
        (copied (sh! (str "cp -R asl/packages/asl-parser/src '" tmp "/parserSrc'")))
        (roots (replaceRoot (cc/defaultRoots) "asl/packages/asl-parser/src" (str tmp "/parserSrc")))
        (fpA (cc/fingerprintRoots! roots))
        (fpAgain (cc/fingerprintRoots! roots))
        (cacheA (cc/cacheAt (str tmp "/inval") fpA))
        (warmA (do (layoutRun! cacheA files) (printRun! cacheA files) (layoutRun! cacheA files)))
        (edited (fileWrite (str tmp "/parserSrc/reader.asl") (str (resultOr (fileReadString (str tmp "/parserSrc/reader.asl")) "") "\n")))
        (fpB (cc/fingerprintRoots! roots))
        (cacheB (cc/cacheAt (str tmp "/inval") fpB))
        (layB (layoutRun! cacheB files))
        (prB (printRun! cacheB files))]
    (do
      (assert (= copied.exitCode 0) (str "copy of asl-parser/src: " copied.stderr))
      (assert (testDefaultRootCoverage! tmp) "cache-suite paths are fingerprinted and empty roots disable caching")
      (assert (= fpA fpAgain) "fingerprint is deterministic")
      (assert (= warmA.cached n) "entries under the first fingerprint hit")
      (assert (ok? edited) "one asl-parser/src file edited in the copy")
      (assert (!= fpA fpB) "editing one asl-parser/src file changes the fingerprint")
      (assert (and (= layB.cached 0) (= prB.cached 0)) (str "after the parser edit every entry misses: layoutCorpus hits " (stringFromInt64 layB.cached) ", printReparse hits " (stringFromInt64 prB.cached)))
      (assert (and (= layB.matched n) (= prB.passed n)) "after the parser edit every file is re-checked and passes")
      (and (!= fpA fpB) (and (= layB.cached 0) (= prB.cached 0)))))

fn testContentChangeRechecks! tmp: String fp: String -> Bool
  (let [(path (str tmp "/probe.asl"))
        (cache (cc/cacheAt (str tmp "/content") fp))
        (original (resultOr (fileReadString "asl/packages/asl-syntax/src/core/bytesText.asl") ""))
        (w1 (fileWrite path original))
        (first (layoutRun! cache (list path)))
        (second (layoutRun! cache (list path)))
        (w2 (fileWrite path (str original "\nfn probeAdded -> Int64\n  (+ 1 2)\n")))
        (third (layoutRun! cache (list path)))
        (fourth (layoutRun! cache (list path)))]
    (do
      (assert (and (ok? w1) (ok? w2)) "probe file written twice")
      (assert (and (= first.cached 0) (= second.cached 1)) "unchanged content hits")
      (assert (and (= third.cached 0) (= third.matched 1)) "changed content misses and is re-checked")
      (assert (= fourth.cached 1) "the re-checked content is cached")
      (and (= third.cached 0) (= fourth.cached 1))))

fn probeSuite! cacheDir: String suite: String files: String -> ProcessOutput
  (sh! (str "CORPUS_CACHE_PROBE_SUITES='" suite "' ASL_CORPUS_CACHE='" cacheDir "' CORPUS_CACHE_PROBE_FILES='" files "' asl/host/out/asl-host test asl/packages/asl-parser/tests/corpusCacheProbe.asl 2>&1"))

fn testBrokenNeverCached! tmp: String fp: String -> Bool
  (let [(broken (str tmp "/broken.asl"))
        (good "asl/packages/asl-syntax/src/core/bytesText.asl")
        (brokenSrc "fn broken -> Int64\n  (+ 1 2\n")
        (w (fileWrite broken brokenSrc))
        (dir (str tmp "/broken"))
        (suites (list (pair "layoutCorpus" (list "matched" "excluded")) (pair "printReparse" (list "passed")) (pair "liftLower" (list "passed"))))
        (runs (map (fn [(s (Pair String (List String)))] -> (Pair Int64 Int64)
                     (pair (probeSuite! dir (pairFirst s) (str good " " broken)).exitCode
                           (probeSuite! dir (pairFirst s) (str good " " broken)).exitCode))
                   suites))
        (cache (cc/cacheAt dir fp))
        (brokenHits (filter (fn [(s (Pair String (List String)))] -> Bool (some? (cc/lookupVerdict! cache (pairFirst s) broken brokenSrc (pairSecond s)))) suites))
        (goodSrc (resultOr (fileReadString good) ""))
        (goodHits (filter (fn [(s (Pair String (List String)))] -> Bool (some? (cc/lookupVerdict! cache (pairFirst s) good goodSrc (pairSecond s)))) suites))]
    (do
      (assert (ok? w) "broken file written")
      (assert (listEmpty? (filter (fn [(r (Pair Int64 Int64))] -> Bool (or (= (pairFirst r) 0) (= (pairSecond r) 0))) runs)) "every suite fails on the broken file in both runs")
      (assert (listEmpty? brokenHits) (str "the broken file has no entry: " (stringJoin (map (fn [(s (Pair String (List String)))] -> String (pairFirst s)) brokenHits) " ")))
      (assert (= (listLength goodHits) 3) "the passing file checked before it has an entry per suite")
      (assert (= (countFiles! dir) 3) (str "cache holds exactly the 3 passing entries: " (stringFromInt64 (countFiles! dir))))
      (and (listEmpty? brokenHits) (= (countFiles! dir) 3))))

fn fakeNames -> (List String)
  (list "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd" "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")

fn makeFakeDirs! dir: String fresh: (List String) stale: (List String) -> ProcessOutput
  (sh! (str "mkdir -p '" dir "/keepme' && cd '" dir "' && touch -t 202601010100 keepme"
           (stringJoin (map (fn [(n String)] -> String (str " && mkdir -p " n " && echo x > " n "/entry")) (listAppend fresh stale)) "")
           (stringJoin (map (fn [(n String)] -> String (str " && touch -t 202601010100 " n)) stale) "")))

fn dirPresent! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isDir) ((err _) false))

fn hexDirs! dir: String -> (List String)
  (filter (fn [(n String)] -> Bool (and (= (stringLength n) 64) (not (stringContains? n ".")))) (resultOr (dirList dir) (list)))

fn testSharedFingerprintsRetained! tmp: String fp: String -> Bool
  (let [(fresh (listTake (fakeNames) 2))
        (stale (listTake (listDrop (fakeNames) 2) 2))
        (dir (str tmp "/sharedCache"))
        (made (makeFakeDirs! dir fresh stale))
        (run (probeSuite! dir "layoutCorpus" "asl/packages/asl-syntax/src/core/bytesText.asl"))
        (left (hexDirs! dir))
        (expected (listSort (listAppend fresh (list fp))))]
    (do
      (assert (= made.exitCode 0) (str "two fresh and two stale fingerprint directories made: " made.stdout made.stderr))
      (assert (= run.exitCode 0) (str "probe opens shared cache and passes: " run.stdout))
      (assert (listAll? (fn [(n String)] -> Bool (listContains? left n)) (list fp)) (str "the current fingerprint is written: " (stringJoin left " ")))
      (assert (listAll? (fn [(n String)] -> Bool (listContains? left n)) fresh) (str "recently used fingerprints of concurrent snapshots are kept: " (stringJoin left " ")))
      (assert (listEmpty? (filter (fn [(n String)] -> Bool (listContains? left n)) stale)) (str "fingerprints idle past the eviction age are removed: " (stringJoin left " ")))
      (assert (dirPresent! (str dir "/keepme")) "a directory that is not a fingerprint is never evicted")
      (and (= left expected) (dirPresent! (str dir "/keepme")))))

fn ! runTests -> Bool
  (let [(made (sh! "mktemp -d"))
        (tmp (stringTrim made.stdout))
        (fp (cc/fingerprintRoots! (cc/defaultRoots)))]
    (do
      (assert (and (= made.exitCode 0) (not (stringEmpty? tmp))) "temporary directory created")
      (assert (fileExists? "asl/host/out/asl-host") "asl/host/out/asl-host is built")
      (let [(r1 (testSecondRunHits! tmp fp))
            (r2 (testDefaultSnapshotCache! tmp))
            (r2a (testMissingRootsDisableCache! tmp (stringTrim (sh! "pwd").stdout) "probeFiles/bytesText.asl probeFiles/print.asl probeFiles/outline.asl"))
            (r3 (testParserChangeInvalidates! tmp))
            (r4 (testContentChangeRechecks! tmp fp))
            (r5 (testBrokenNeverCached! tmp fp))
            (r6 (testSharedFingerprintsRetained! tmp fp))
            (removed (pathRemove tmp))]
        (do
          (assert (ok? removed) "temporary directory removed")
          (and r1 (and r2 (and r2a (and r3 (and r4 (and r5 r6))))))))))
