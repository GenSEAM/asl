(module asl-parser/tests/corpusCacheProbe
  :x [runTests]
  :i [(asl-syntax/tests/asl/layoutCorpusLib :a lay)
      (asl-parser/tests/printReparseLib :a pr)
      (asl-parser/tests/liftLowerIdentityTest :a ll)
      (asl-syntax/tests/asl/corpusCache :a cc)])

fn words v: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit v " "))

fn runSuite! cache: cc/Cache suite: String files: (List String) -> Bool
  (cond
    ((= suite "layoutCorpus")
     (lay/reportCorpusStats! "layoutCorpus" (fold (fn [(s lay/CorpusStats) (f String)] -> lay/CorpusStats (lay/verifyCorpusFile! f s)) (lay/emptyCorpusStatsWith cache) files)))
    ((= suite "printReparse")
     (pr/reportCorpusStats! "printReparse" (fold (fn [(s pr/CorpusStats) (f String)] -> pr/CorpusStats (pr/verifyCorpusFile! f s)) (pr/emptyCorpusStatsWith cache) files)))
    ((= suite "liftLower")
     (let [(verdicts (map (fn [(f String)] -> (Pair Bool Bool) (ll/verifyCorpusFile! cache f)) files))]
       (do
         (print (str "liftLower: cached=" (stringFromInt64 (listLength (filter (fn [(v (Pair Bool Bool))] -> Bool (pairSecond v)) verdicts))) "\n"))
         (listEmpty? (filter (fn [(v (Pair Bool Bool))] -> Bool (not (pairFirst v))) verdicts)))))
    (else (do (assert false (str "known probe suite: " suite)) false)))

fn ! runTests -> Bool
  (let [(cache (cc/cacheFromEnv!))
        (suites (words (optionOr (envGet "CORPUS_CACHE_PROBE_SUITES") "layoutCorpus printReparse liftLower")))]
    (mt (envGet "CORPUS_CACHE_PROBE_FILES")
      ((none) (do (assert false "CORPUS_CACHE_PROBE_FILES is set") false))
      ((some v) (fold (fn [(acc Bool) (s String)] -> Bool (and (runSuite! cache s (words v)) acc)) true suites))))
