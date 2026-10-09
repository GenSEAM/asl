(module asl-parser/tests/liftLowerIdentityTest
  :x [runTests verifyCorpusFile!]
  :i [(ast :a a) (astConverter :a ac) (reader :a rd) (asl-syntax/tests/asl/layoutCorpusLib :a lib) (asl-syntax/tests/asl/corpusCache :a cc)])

fn hasDigit? s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (or acc (stringContains? "0123456789" c))) false (stringChars s))

fn isFloatStr? s: String -> Bool
  (and (hasDigit? s) (or (stringContains? s ".") (or (stringContains? s "e") (stringContains? s "E"))))

fn atomEquivalent? a: String b: String -> Bool
  (or (= a b)
      (and (isFloatStr? a)
           (and (isFloatStr? b)
                (and (some? (stringToFloat64 a)) (= (stringToFloat64 a) (stringToFloat64 b))))))

fn sexprEquivalent? a: rd/SExpr b: rd/SExpr -> Bool
  (mt a
    ((rd/sexprAtom va)
     (mt b
       ((rd/sexprAtom vb) (atomEquivalent? va vb))
       (_ false)))
    ((rd/sexprList la)
     (mt b
       ((rd/sexprList lb)
        (if (!= (listLength la) (listLength lb))
          false
          (fold (fn [(acc Bool) (p (Pair rd/SExpr rd/SExpr))] -> Bool
                  (and acc (sexprEquivalent? (pairFirst p) (pairSecond p))))
                true (zip la lb))))
       (_ false)))
    ((rd/sexprVect va)
     (mt b
       ((rd/sexprVect vb)
        (if (!= (listLength va) (listLength vb))
          false
          (fold (fn [(acc Bool) (p (Pair rd/SExpr rd/SExpr))] -> Bool
                  (and acc (sexprEquivalent? (pairFirst p) (pairSecond p))))
                true (zip va vb))))
       (_ false))))

fn checkBodyForms name: String body: (List rd/SExpr) -> (Option String)
  (fold (fn [(errOpt (Option String)) (b rd/SExpr)] -> (Option String)
          (mt errOpt
            ((some _) errOpt)
            ((none)
             (let [(orig b)
                   (rt (ac/lower (ac/lift b)))]
               (if (not (sexprEquivalent? orig rt))
                 (some (str "fn " name " diff:\n  ORIG: " (rd/renderSexpr orig) "\n  LIFT: " (rd/renderSexpr rt)))
                 (none))))))
        (none) body)

fn checkFileDefuns forms: (List a/TopForm) -> (Option String)
  (fold (fn [(errOpt (Option String)) (tf a/TopForm)] -> (Option String)
          (mt errOpt
            ((some _) errOpt)
            ((none)
             (mt tf
               ((a/topDefun d)
                (checkBodyForms d.name d.body))
               (_ (none))))))
        (none) forms)

fn verifySource! cache: cc/Cache path: String src: String -> Bool
  (mt (a/parse src)
    ((err e)
     (do
       (assert false (str path " parse error: " e.msg))
       false))
    ((ok forms)
     (let [(diffOpt (checkFileDefuns forms))]
       (do
         (assert (none? diffOpt)
           (mt diffOpt
             ((some diff) (str path " diff: " diff))
             ((none) (str path " lift/lower identity preserved"))))
         (if (none? diffOpt) (cc/storeVerdict! cache "liftLower" path src "passed") false)
         (none? diffOpt)))))

fn verifyCorpusFile! cache: cc/Cache path: String -> (Pair Bool Bool)
  (mt (lib/knownMisparseReason path)
    ((some _) (pair true false))
    ((none)
     (mt (fileRead path)
       ((err e)
        (do
          (assert false (str path " read error: " e))
          (pair false false)))
       ((ok src)
        (mt (cc/lookupVerdict! cache "liftLower" path src (list "passed"))
          ((some outcome)
           (do
             (assert (= outcome "passed") (str path " lift/lower identity preserved (cached)"))
             (pair true true)))
          ((none) (pair (verifySource! cache path src) false)))))))

fn runCorpusFilesLoop! cache: cc/Cache files: (List String) runCount: Int64 passCount: Int64 cachedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (print (str "run=" (stringFromInt64 runCount) " passed=" (stringFromInt64 passCount) " cached=" (stringFromInt64 cachedCount) "\n"))
      (= runCount passCount))
    (let [(f (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (lib/knownMisparseReason f)
        ((some _)
         (runCorpusFilesLoop! cache rest runCount passCount cachedCount))
        ((none)
         (let [(verdict (verifyCorpusFile! cache f))]
           (runCorpusFilesLoop! cache rest (+ runCount 1) (if (pairFirst verdict) (+ passCount 1) passCount) (if (pairSecond verdict) (+ cachedCount 1) cachedCount)))))))

fn testConverterMutants -> Bool
  (let [(unknownHead (rd/makeList (list (rd/makeAtom "invalidDeclarationHead") (rd/makeAtom "x"))))
        (underFn (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "bad"))))
        (underSchema (rd/makeList (list (rd/makeAtom "schema"))))
        (underEnum (rd/makeList (list (rd/makeAtom "enum"))))
        (emptyModule (rd/makeList (list (rd/makeAtom "module"))))
        (resUnknown (ac/sexprToTopForm unknownHead))
        (resUnderFn (ac/sexprToTopForm underFn))
        (resUnderSchema (ac/sexprToTopForm underSchema))
        (resUnderEnum (ac/sexprToTopForm underEnum))
        (resEmptyMod (ac/sexprToTopForm emptyModule))]
    (do
      (assert (err? resUnknown) "unknown declaration head must return err")
      (assert (err? resUnderFn) "under-length fn form must return err")
      (assert (err? resUnderSchema) "under-length schema form must return err")
      (assert (err? resUnderEnum) "under-length enum form must return err")
      (assert (err? resEmptyMod) "missing module path must return err")
      true))

fn envInt! key: String defaultVal: Int64 -> Int64
  (mt (envGet key)
    ((some v) (optionOr (stringToInt64 v) defaultVal))
    ((none) defaultVal))

fn testTailrecTestRoundtrip! -> Bool
  (let [(path "tests/host/tailrecTest.asl")]
    (mt (fileRead path)
      ((err e) (do (assert false (str path " read error: " e)) false))
      ((ok src) (verifySource! (cc/cacheFromEnv!) path src))))

fn ! runTests -> Bool
  (let [(tailrecOk (testTailrecTestRoundtrip!))
        (mutantsOk (testConverterMutants))]
    (mt (lib/allCorpusFiles!)
      ((err e)
       (do
         (assert false (str "git ls-files failed: " e))
         false))
      ((ok allFiles)
       (let [(numShards (envInt! "LIFT_LOWER_NUM_SHARDS" 1))
             (shardIdx (envInt! "LIFT_LOWER_SHARD" 1))
             (shard (lib/shardFiles allFiles numShards shardIdx))]
         (and tailrecOk (and mutantsOk (runCorpusFilesLoop! (cc/cacheFromEnv!) shard 0 0 0)))))))
