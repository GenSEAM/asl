(module asl/agentLoop/tests/diffTest
  :x [runTests]
  :i [(asl/agentLoop/diff :a diff)
      (asl/agentLoop/core :a c)])

fn getStr kv: (List (Pair String c/KvVal)) key: String -> String
  (mt (listHead kv)
    ((none) "")
    ((some p)
      (if (= (pairFirst p) key)
        (mt (pairSecond p)
          ((c/kvStr s) s)
          ((c/kvInt i) i))
        (getStr (optionOr (listTail kv) (list)) key))))

fn testDiffCase! form: String -> Bool
  (let [(kv (c/parseKv form))
        (id (getStr kv "id"))
        (a (getStr kv "a"))
        (b (getStr kv "b"))
        (fromName (getStr kv "from"))
        (toName (getStr kv "to"))
        (ctxStr (getStr kv "context"))
        (context (optionOr (stringToInt64 ctxStr) 3))
        (expected (getStr kv "expected"))
        (actual (diff/unifiedDiff! a b fromName toName context))]
    (do (assert (= actual expected) (str "unifiedDiff parity failed on: " id)) true))

fn testRatioCase! form: String -> Bool
  (let [(kv (c/parseKv form))
        (id (getStr kv "id"))
        (a (getStr kv "a"))
        (b (getStr kv "b"))
        (expectedStr (getStr kv "expected"))
        (expected (stringToFloat64 expectedStr))
        (actual (diff/ratio a b))]
    (do (assert (= (some actual) expected) (str "ratio exact float equality failed on: " id)) true))

fn headOfForm f: String -> String
  (let [(kv (c/parseKv f))]
    (getStr kv "_head"))

fn runForms! forms: (List String) diffCount: Int64 ratioCount: Int64 -> (Pair Int64 Int64)
  (mt (listHead forms)
    ((none) (pair diffCount ratioCount))
    ((some f)
      (let [(tl (optionOr (listTail forms) (list)))
            (h (headOfForm f))]
        (cond
          ((= h "diffTest")
            (let [(_ (testDiffCase! f))]
              (runForms! tl (+ diffCount 1) ratioCount)))
          ((= h "ratioTest")
            (let [(_ (testRatioCase! f))]
              (runForms! tl diffCount (+ ratioCount 1))))
          (else
            (runForms! tl diffCount ratioCount))))))

fn repeatStr n: Int64 s: String acc: (List String) -> (List String)
  (if (<= n 0)
    acc
    (repeatStr (- n 1) s (cons s acc)))


fn opcodeEq a: diff/DiffOpcode b: diff/DiffOpcode -> Bool
  (and (= a.tag b.tag)
       (and (= a.i1 b.i1)
            (and (= a.i2 b.i2)
                 (and (= a.j1 b.j1)
                      (= a.j2 b.j2)))))

fn opcodesEq a: (List diff/DiffOpcode) b: (List diff/DiffOpcode) -> Bool
  (mt (listHead a)
    ((none) (listEmpty? b))
    ((some oa)
      (mt (listHead b)
        ((none) false)
        ((some ob)
          (and (opcodeEq oa ob)
               (opcodesEq (optionOr (listTail a) (list)) (optionOr (listTail b) (list))))))))

fn testPopularityBoundary! -> Bool
  (let [(a (list "k"))
        (b1 (cons "x" (repeatStr 3 "k" (repeatStr 196 "x" (list)))))
        (b2 (cons "x" (repeatStr 2 "k" (repeatStr 197 "x" (list)))))
        (expected1 (list (diff/DiffOpcode :tag "insert" :i1 0 :i2 0 :j1 0 :j2 1)
                         (diff/DiffOpcode :tag "equal" :i1 0 :i2 1 :j1 1 :j2 2)
                         (diff/DiffOpcode :tag "insert" :i1 1 :i2 1 :j1 2 :j2 200)))
        (expected2 (list (diff/DiffOpcode :tag "insert" :i1 0 :i2 0 :j1 0 :j2 1)
                         (diff/DiffOpcode :tag "equal" :i1 0 :i2 1 :j1 1 :j2 2)
                         (diff/DiffOpcode :tag "insert" :i1 1 :i2 1 :j1 2 :j2 200)))
        (actual1 (diff/getOpcodes a b1))
        (actual2 (diff/getOpcodes a b2))]
    (assert (= (listLength b1) 200) "b1 has 200 lines")
    (assert (= (listLength b2) 200) "b2 has 200 lines")
    (assert (opcodesEq actual1 expected1) "popularity boundary n//100+1 matches expected opcodes")
    (assert (opcodesEq actual2 expected2) "popularity boundary n//100 matches expected opcodes")
    true)

fn ! runTests -> Bool
  (let [(fixturePath "asl/agentLoop/tests/diffFixtures.asn")
        (readRes (fileReadString fixturePath))
        (content (resultOr readRes ""))
        (forms (c/parseForms content))
        (counts (runForms! forms 0 0))
        (diffCount (pairFirst counts))
        (ratioCount (pairSecond counts))
        (_ (testPopularityBoundary!))]
    (assert (>= diffCount 20) (str "At least 20 diff fixtures executed: " (stringFromInt64 diffCount)))
    (assert (>= ratioCount 20) (str "At least 20 ratio pairs executed: " (stringFromInt64 ratioCount)))
    true)
