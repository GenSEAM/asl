(module asl-syntax/tests/asl/fromJsonCorpusLib
  :x [allCorpusFiles!
      shardFiles
      expectedShardCount
      emptyCorpusStats
      verifyCorpusFile!
      runShardFiles!
      reportCorpusStats!
      loadRootSchema!
      runCorpusShard!
      formsToJsonString
      CorpusStats]
  :i [(asl-syntax/asl/fromJson :a fj)
      (asl-syntax/asl/astSchema :a asch)
      (asl-parser/ast :a a)
      (asl-parser/astConverter :a cv)
      (asl-parser/reader :a rd)
      (asl-json/json :a j)
      (asl-syntax/tests/asl/layoutCorpusLib :a lib)])

(schema CorpusStats
  (:f checked Int64)
  (:f passed Int64)
  (:f bugs Int64))

fn emptyCorpusStats -> CorpusStats
  (CorpusStats :checked 0 :passed 0 :bugs 0)

fn bumpPassed s: CorpusStats -> CorpusStats
  (with s :checked (+ s.checked 1) :passed (+ s.passed 1))

fn bumpBug s: CorpusStats -> CorpusStats
  (with s :checked (+ s.checked 1) :bugs (+ s.bugs 1))

fn allCorpusFiles! -> (Result (List String) String)
  (lib/allCorpusFiles!)

fn shardFiles files: (List String) n: Int64 k: Int64 -> (List String)
  (lib/shardFiles files n k)

fn expectedShardCount total: Int64 n: Int64 k: Int64 -> Int64
  (lib/expectedShardCount total n k)

fn loadRootSchema! -> (Result j/Json String)
  (mt (fileRead "asl/grammar/aslAst.schema.json")
    ((err e) (err (str "Failed reading aslAst.schema.json: " e)))
    ((ok text)
     (mt (j/jsonParse text)
       ((err e) (err (str "Failed parsing aslAst.schema.json: " e)))
       ((ok root) (ok root)))))

fn hasDigit? s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (or acc (stringContains? "0123456789" c))) false (stringChars s))

fn isFloatStr? s: String -> Bool
  (and (not (stringStartsWith? s "\""))
       (and (hasDigit? s)
            (and (or (stringContains? s ".") (or (stringContains? s "e") (stringContains? s "E")))
                 (listAll? (fn [(c String)] -> Bool (stringContains? "+-0123456789.eE" c)) (stringChars s)))))

fn atomEquivalent? a: String b: String -> Bool
  (or (= a b)
      (and (isFloatStr? a)
           (and (isFloatStr? b)
                (and (some? (stringToFloat64 a)) (= (stringToFloat64 a) (stringToFloat64 b))))))

fn dropListHead items: (List rd/SExpr) -> (Option (List rd/SExpr))
  (mt (listHead items)
    ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) "list")) (some (optionOr (listTail items) (list))) (none)))
    ((none) (none)))

fn itemsEquivalent? xs: (List rd/SExpr) ys: (List rd/SExpr) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (fold (fn [(acc Bool) (p (Pair rd/SExpr rd/SExpr))] -> Bool
            (and acc (sexprEquivalent? (pairFirst p) (pairSecond p))))
          true (zip xs ys)))

fn vectListEquivalent? vItems: (List rd/SExpr) lItems: (List rd/SExpr) -> Bool
  (mt (dropListHead lItems)
    ((some rest) (itemsEquivalent? vItems rest))
    ((none) false))

fn sexprEquivalent? x: rd/SExpr y: rd/SExpr -> Bool
  (mt x
    ((rd/sexprAtom vx)
     (mt y
       ((rd/sexprAtom vy) (atomEquivalent? vx vy))
       (_ false)))
    ((rd/sexprList lx)
     (mt y
       ((rd/sexprList ly) (itemsEquivalent? lx ly))
       ((rd/sexprVect vy) (vectListEquivalent? vy lx))
       (_ false)))
    ((rd/sexprVect vx)
     (mt y
       ((rd/sexprVect vy) (itemsEquivalent? vx vy))
       ((rd/sexprList ly) (vectListEquivalent? vx ly))
       (_ false))))

fn topFormEffectEquivalent? x: a/TopForm y: a/TopForm -> Bool
  (mt x
    ((a/topDefun dx) (mt y ((a/topDefun dy) (= dx.effect dy.effect)) (_ false)))
    ((a/topModule mx) (mt y ((a/topModule my) (topFormsEffectsEquivalent? mx.defs my.defs)) (_ false)))
    (_ true))

fn topFormsEffectsEquivalent? xs: (List a/TopForm) ys: (List a/TopForm) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (fold (fn [(acc Bool) (p (Pair a/TopForm a/TopForm))] -> Bool
            (and acc (topFormEffectEquivalent? (pairFirst p) (pairSecond p))))
          true (zip xs ys)))

fn topFormsEquivalent? xs: (List a/TopForm) ys: (List a/TopForm) -> Bool
  (if (!= (listLength xs) (listLength ys))
    false
    (and (topFormsEffectsEquivalent? xs ys)
         (fold (fn [(acc Bool) (p (Pair a/TopForm a/TopForm))] -> Bool
                 (and acc (sexprEquivalent? (cv/topFormToSexpr (pairFirst p)) (cv/topFormToSexpr (pairSecond p)))))
               true (zip xs ys))))

fn validateTopForms rootSchema: j/Json forms: (List a/TopForm) -> (Result Bool String)
  (fold (fn [(acc (Result Bool String)) (tf a/TopForm)] -> (Result Bool String)
          (mt acc
            ((err e) (err e))
            ((ok _) (asch/validateTopFormWithSchema rootSchema (fj/topFormToJson tf)))))
        (ok true) forms)

fn formsToJsonString forms: (List a/TopForm) -> String
  (mt (listHead forms)
    ((some tf0)
     (mt tf0
       ((a/topModule _) (fj/topFormToJsonString tf0))
       (_ (fj/topFormsToJsonString forms))))
    ((none) (fj/topFormsToJsonString forms)))

fn verifyCorpusFile! path: String stats: CorpusStats rootSchema: j/Json -> CorpusStats
  (mt (fileRead path)
    ((err e)
     (do
       (assert false (str path " read error: " e))
       (bumpBug stats)))
    ((ok src)
     (mt (a/parse src)
       ((err e)
        (do
          (assert false (str path " initial parse error: " e.msg))
          (bumpBug stats)))
       ((ok origForms)
        (mt (validateTopForms rootSchema origForms)
          ((err e)
           (do
             (assert false (str path " top forms failed schema validation: " e))
             (bumpBug stats)))
          ((ok _)
           (let [(jsonAll (formsToJsonString origForms))]
             (mt (fj/fromJsonToAsl jsonAll)
               ((err e)
                (do
                  (assert false (str path " fromJsonToAsl failed: " e))
                  (bumpBug stats)))
               ((ok aslText)
                (mt (a/parse aslText)
                  ((err e)
                   (do
                     (assert false (str path " reparse failed: " e.msg))
                     (bumpBug stats)))
                  ((ok reparsedForms)
                   (let [(equiv (topFormsEquivalent? origForms reparsedForms))]
                     (do
                       (assert equiv (str path " roundtrip equivalence"))
                       (if equiv (bumpPassed stats) (bumpBug stats)))))))))))))))

fn runShardFiles! files: (List String) stats: CorpusStats rootSchema: j/Json -> CorpusStats
  (if (listEmpty? files)
    stats
    (let [(f (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (runShardFiles! rest (verifyCorpusFile! f stats rootSchema) rootSchema)))

fn reportCorpusStats! label: String s: CorpusStats -> Bool
  (do
    (print (str label ": checked=" (stringFromInt64 s.checked)
                " passed=" (stringFromInt64 s.passed)
                " bugs=" (stringFromInt64 s.bugs) "\n"))
    (assert (= s.bugs 0) (str label " zero fromJson bugs"))
    (= s.bugs 0))

fn runCorpusShard! label: String n: Int64 k: Int64 -> Bool
  (mt (allCorpusFiles!)
    ((err e)
     (do
       (assert false (str label " git ls-files failed: " e))
       false))
    ((ok allFiles)
     (mt (loadRootSchema!)
       ((err e)
        (do
          (assert false (str label " root schema: " e))
          false))
       ((ok rootSchema)
        (let [(shard (shardFiles allFiles n k))
              (expected (expectedShardCount (listLength allFiles) n k))
              (shardLen (listLength shard))
              (shareOk (= shardLen expected))]
          (do
            (assert shareOk (str "shard " (stringFromInt64 k) " of " (stringFromInt64 n) " has expected share " (stringFromInt64 expected)))
            (let [(stats (runShardFiles! shard (emptyCorpusStats) rootSchema))
                  (processedOk (= stats.passed shardLen))]
              (do
                (assert processedOk "processed count equals shard size")
                (and (reportCorpusStats! label stats) (and shareOk processedOk))))))))))
