(module asl-syntax/tests/asl/layoutCorpusLib
  :x [isParenOrInvalidFile
      knownMisparseReason
      allCorpusFiles!
      shardFiles
      expectedShardCount
      emptyCorpusStats!
      emptyCorpusStatsWith
      verifyCorpusFile!
      reportCorpusStats!
      CorpusStats]
  :i [(asl-syntax/asl/layout :a lay)
      (asl-parser/indentParser :a ip)
      (asl-parser/reader :a rd)
      (asl-syntax/tests/asl/corpusCache :a cc)])

fn isParenOrInvalidFile path: String -> Bool
  (or (stringContains? path "tests/fixtures/")
  (or (stringContains? path "asl/grammar/corpus/")
  (or (stringContains? path "closureParity/")
  (or (stringContains? path "scratch/")
  (or (stringContains? path "test_")
  (or (or (stringContains? path "tests/acceptance/r1Host/reader/invalid/") (stringContains? path "tests/acceptance/r1Host/sem/invalid/"))
  (or (stringContains? path "tests/acceptance/vtbotDataPlane/fixtures/invalid/")
  (or (stringContains? path "tests/acceptance/r1Host/generated/float/oracle")
  (or (stringContains? path "tests/acceptance/r1Host/generated/invalid/depth/")
  (or (= path "asl/web/src/components/SkyLoomVisualizer.asl")
  (or (= path "asl/web/src/components/EngineeringBlog.asl")
  (or (= path "asl/web/src/components/InBrowserAgent.asl")
  (or (= path "asl/web/src/views/BlogView.asl")
  (or (= path "asl/web/src/data/blog/posts.asl")
  (or (= path "asl/packages/asl-agent/src/dispatch.asl")
  (or (= path "asl/packages/asl-agent/tests/dispatchTest.asl")
  (or (= path "asl/packages/asl-macro/src/macro.asl")
  (or (= path "asl/packages/asl-ui/src/main.asl")
  (or (= path "asl/packages/asl-mem/src/tasks.asl")
      (= path "tests/acceptance/d81/Task58801IntermediatePolicyTest.asl"))))))))))))))))))))

fn knownMisparseReason path: String -> (Option String)
  (cond
    ((= path "asl/grammar/tests/corpusTest.asl")
     (some "reference parser misparses: re-verified under A6a parser on SA3b, shard2 gate shows lowering still differs from reference render"))
    ((= path "asl/packages/asl-regex/src/regex.asl")
     (some "reference parser misparses: dedent defect corrupts enum Ast case list (65 vs 63 forms, re-verified after A6c)"))
    ((= path "asl/packages/asl-syntax/src/core/corpus.asl")
     (some "reference parser misparses: dedent defect swaps fn runCorpusOnFiles body with an adjacent fn (50 vs 51 forms, re-verified after A6c)"))
    ((= path "asl/packages/asl-syntax/src/xml.asl")
     (some "reference parser misparses: dedent defect swaps fn parseTag body with an adjacent fn (70 vs 72 forms, re-verified after A6c)"))
    ((= path "asl/packages/asl-transpile/src/yamlTranspile.asl")
     (some "reference parser misparses: dedent defect corrupts enum YamlLineKind case list (re-verified after A6c)"))
    ((= path "tests/acceptance/r1Host/reader/surfaceTest.asl")
     (some "reference parser misparses: dedent defect drops enum Shape case list and schema Pt fields (re-verified after A6c)"))
    (else (none)))

fn parseFileList stdout: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit stdout "\n"))

fn allCorpusFiles! -> (Result (List String) String)
  (let [(cmdRes (processRun "git ls-files '*.asl'"))]
    (if (!= cmdRes.exitCode 0)
      (err (str "git ls-files exited " (stringFromInt64 cmdRes.exitCode)))
      (ok (filter (fn [(p String)] -> Bool (not (isParenOrInvalidFile p))) (parseFileList cmdRes.stdout)))))

fn shardFilesLoop files: (List String) n: Int64 targetRem: Int64 idx: Int64 acc: (List String) -> (List String)
  (if (listEmpty? files)
    (listReverse acc)
    (let [(f (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))
          (rem (mod idx n))]
      (if (= rem targetRem)
        (shardFilesLoop rest n targetRem (+ idx 1) (cons f acc))
        (shardFilesLoop rest n targetRem (+ idx 1) acc))))

fn shardFiles files: (List String) n: Int64 k: Int64 -> (List String)
  (shardFilesLoop files n (- k 1) 0 (list))

fn countRemLoop total: Int64 n: Int64 targetRem: Int64 idx: Int64 acc: Int64 -> Int64
  (if (>= idx total)
    acc
    (countRemLoop total n targetRem (+ idx 1) (if (= (mod idx n) targetRem) (+ acc 1) acc)))

fn expectedShardCount total: Int64 n: Int64 k: Int64 -> Int64
  (countRemLoop total n (- k 1) 0 0)

(schema CorpusStats
  (:f checked Int64)
  (:f excluded Int64)
  (:f matched Int64)
  (:f bugs Int64)
  (:f cached Int64)
  (:f cache cc/Cache))

fn emptyCorpusStats! -> CorpusStats
  (emptyCorpusStatsWith (cc/cacheFromEnv!))

fn emptyCorpusStatsWith cache: cc/Cache -> CorpusStats
  (CorpusStats :checked 0 :excluded 0 :matched 0 :bugs 0 :cached 0 :cache cache)

fn bumpChecked s: CorpusStats -> CorpusStats
  (with s :checked (+ s.checked 1))

fn bumpExcluded s: CorpusStats -> CorpusStats
  (bumpChecked (with s :excluded (+ s.excluded 1)))

fn bumpMatched s: CorpusStats -> CorpusStats
  (bumpChecked (with s :matched (+ s.matched 1)))

fn bumpBug s: CorpusStats -> CorpusStats
  (bumpChecked (with s :bugs (+ s.bugs 1)))

fn bumpCached s: CorpusStats -> CorpusStats
  (with s :cached (+ s.cached 1))

fn formsMatch? lForms: (List rd/SExpr) iForms: (List rd/SExpr) -> Bool
  (if (!= (listLength lForms) (listLength iForms))
    false
    (fold (fn [(m Bool) (p (Pair rd/SExpr rd/SExpr))] -> Bool
            (and m (= (rd/renderSexpr (pairFirst p)) (rd/renderSexpr (pairSecond p)))))
          true (zip lForms iForms)))

fn verifyAgainstReference! path: String src: String iForms: (List rd/SExpr) stats: CorpusStats -> CorpusStats
  (mt (lay/lowerString src)
    ((err e)
     (do
       (print (str path ": REAL BUG lowering failed while reference parser accepts: " e "\n"))
       (assert false (str path " layout lower failed: " e))
       (bumpBug stats)))
    ((ok lForms)
     (let [(matched (formsMatch? lForms iForms))]
       (do
         (when (not matched) (print (str path ": REAL BUG lowering differs from reference render\n")))
         (assert matched (str path " lowering matches a/parse renderSexpr"))
         (if matched (cc/storeVerdict! stats.cache "layoutCorpus" path src "matched") false)
         (bumpMatched stats)))))

fn verifyExcludedMisparse! path: String src: String reason: String stats: CorpusStats -> CorpusStats
  (let [(lowered (lay/lowerString src))]
    (do
      (mt lowered
        ((err e) (print (str path ": REAL BUG lowering failed while excluded as a known reference misparse: " e "\n")))
        ((ok _) (print (str path ": excluded (" reason ")\n"))))
      (assert (ok? lowered) (str path " lowers cleanly (excluded: " reason ")"))
      (if (ok? lowered) (cc/storeVerdict! stats.cache "layoutCorpus" path src "excluded") false)
      (bumpExcluded stats)))

fn verifyUncached! path: String src: String stats: CorpusStats -> CorpusStats
  (mt (ip/parseIndentedForms src)
    ((err e)
     (do
       (print (str path ": reference parser rejects: " e "\n"))
       (assert false (str path " reference parser rejects: " e))
       (bumpExcluded stats)))
    ((ok rawForms)
     (let [(iForms (map ip/stripInferredUnit rawForms))]
       (mt (knownMisparseReason path)
         ((some reason) (verifyExcludedMisparse! path src reason stats))
         ((none) (verifyAgainstReference! path src iForms stats))))))

fn verifyCached path: String outcome: String stats: CorpusStats -> CorpusStats
  (if (= outcome "matched")
    (do
      (assert (= outcome "matched") (str path " lowering matches a/parse renderSexpr (cached)"))
      (bumpCached (bumpMatched stats)))
    (do
      (assert (= outcome "excluded") (str path " lowers cleanly (excluded: " (optionOr (knownMisparseReason path) "known misparse") ") (cached)"))
      (bumpCached (bumpExcluded stats))))

fn verifyCorpusFile! path: String stats: CorpusStats -> CorpusStats
  (mt (fileRead path)
    ((err e)
     (do
       (assert false (str path " read error: " e))
       (bumpBug stats)))
    ((ok src)
     (mt (cc/lookupVerdict! stats.cache "layoutCorpus" path src (list "matched" "excluded"))
       ((some outcome) (verifyCached path outcome stats))
       ((none) (verifyUncached! path src stats)))))

fn reportCorpusStats! label: String s: CorpusStats -> Bool
  (do
    (print (str label ": checked=" (stringFromInt64 s.checked)
                " excluded=" (stringFromInt64 s.excluded)
                " matched=" (stringFromInt64 s.matched)
                " bugs=" (stringFromInt64 s.bugs)
                " cached=" (stringFromInt64 s.cached) "\n"))
    (assert (= s.bugs 0) (str label " zero real A3 bugs"))
    true)
