(module asl-forms/tests/parenBenchTest
  :x [runTests]
  :i [(asl-forms/bench/parenMutants :a pm) (asl-forms/bench/parenBench :a pb) (asl-forms/indent :a ind)])

; (:m :ref PAREN-BENCH :do "gates the paren bench: segmenting, trail sites, the three mutation kinds and their closer arithmetic, determinism of a seed, the restored/balancedOther/unbalanced classification against asl-forms/indent, and a bounded run over three real source files; the 20000-mutant tracked-tree figure lives in bench/results.lock.asn")
fn fixture -> String
  "fn h x: Int64 -> Int64\n  (let [(y (+ x 1))\n        (z (* y 2))]\n    (if (> z 2)\n      (+ z 1)\n      (- z 1)))\n"

fn closers s: String -> Int64
  (fold (fn [(a Int64) (l String)] -> Int64 (+ a (listLength (filter (fn [(d (Pair Int64 Int64))] -> Bool (pm/closer? (pairSecond d))) (pm/lexOf l false).delims)))) 0 (stringSplit s "\n"))

fn testSegments -> Bool
  (let [(ss (pm/segments "(module a/b)\n\nfn f x: Int64 -> Int64\n  (+ x 1)\n; note\nfn g x: Int64 -> Int64\n  (+ x 2)\n)\n"))]
    (do
      (assert (= (listLength ss) 3) "a column-0 form starts a segment; a comment, a blank and a closer line do not")
      (assert (stringContains? (optionOr (listGet ss 2) "") "(+ x 2)\n)") "a column-0 closer line stays with the segment it closes")
      true))

fn testBalanced -> Bool
  (do
    (assert (pm/balanced? (fixture)) "the fixture balances")
    (assert (not (pm/balanced? "fn f -> Int64\n  (+ 1 2\n")) "an unclosed form is unbalanced")
    (assert (not (pm/balanced? "fn f -> Int64\n  (+ 1 2))\n")) "a stray closer is unbalanced")
    (assert (not (pm/balanced? "fn f -> Int64\n  (+ 1 2]\n")) "a wrong-kind closer is unbalanced")
    (assert (pm/balanced? "fn f -> String\n  \"( [ {\" ; ((\n") "delimiters inside a string or a comment do not count")
    true)

fn testTrailSites -> Bool
  (let [(sites (pm/trailSites (fixture)))]
    (do
      (assert (= (listLength sites) 10) "every closer that ends a line's code is a site: the fixture has 10")
      (assert (= (optionOr (listHead (map (fn [(s pm/Site)] -> Int64 s.line) sites)) -1) 1) "sites are in source order, the first on the let binding line")
      true))

fn tally seg: String seed: Int64 n: Int64 deletes: Int64 inserts: Int64 moves: Int64 bad: Int64 restoredDeletes: Int64 -> (List Int64)
  (if (<= n 0)
    (list deletes inserts moves bad restoredDeletes)
    (let [(r (pm/mutate seg seed))]
      (match (pairFirst r)
        ((none) (tally seg (pairSecond r) (- n 1) deletes inserts moves bad restoredDeletes))
        ((some m)
         (let [(delta (- (closers m.text) (closers seg)))
               (ok (and (not (= m.text seg))
                        (cond ((= m.kind "delete") (= delta -1)) ((= m.kind "insert") (= delta 1)) (else (= delta 0)))))
               (o (pb/outcomeOf seg m))]
           (tally seg (pairSecond r) (- n 1)
                  (+ deletes (if (= m.kind "delete") 1 0)) (+ inserts (if (= m.kind "insert") 1 0)) (+ moves (if (= m.kind "move") 1 0))
                  (+ bad (if ok 0 1))
                  (+ restoredDeletes (if (and (= m.kind "delete") (= o.res "restored")) 1 0))))))))

fn testMutationKinds -> Bool
  (let [(t (tally (fixture) 7 120 0 0 0 0 0))]
    (do
      (assert (= (optionOr (listGet t 3) -1) 0) "delete removes one closer, insert adds one, move keeps the count, and none returns the segment unchanged")
      (assert (> (optionOr (listGet t 0) 0) 10) "delete is drawn")
      (assert (> (optionOr (listGet t 1) 0) 10) "insert is drawn")
      (assert (> (optionOr (listGet t 2) 0) 10) "move is drawn")
      (assert (= (optionOr (listGet t 4) -1) (optionOr (listGet t 0) 0)) "indentation repair restores every deleted closer of the fixture")
      true))

fn testSeedDeterministic -> Bool
  (let [(a (pm/mutate (fixture) 11)) (b (pm/mutate (fixture) 11)) (c (pm/mutate (fixture) 12))]
    (do
      (assert (= (pairSecond a) (pairSecond b)) "one seed, one successor state")
      (assert (= (pairFirst a) (pairFirst b)) "one seed, one mutant")
      (assert (not (= (pairSecond a) (pairSecond c))) "another seed, another state")
      (assert (= (pm/stepRng 1) 1015568748) "the generator is the 32-bit LCG: 1*1664525+1013904223 mod 2^32")
      true))

fn testClassification -> Bool
  (let [(seg (fixture))
        (restored (pb/outcomeOf seg (pm/Mutant :kind "delete" :text (stringReplace seg "(- z 1)))" "(- z 1))"))))
        (other (pb/outcomeOf "fn f -> Int64\n  1\n" (pm/Mutant :kind "delete" :text (fixture))))
        (bad (pb/outcomeOf seg (pm/Mutant :kind "insert" :text "fn h x: Int64 -> Int64\n  (let [(y (+ x 1)\n    (if (> y 2) y 0)\n")))]
    (do
      (assert (= restored.res "restored") "guide returning the original segment is restored")
      (assert (= restored.dyck "dyckCatches") "a missing closer unbalances the text")
      (assert (= other.res "balancedOther") "a balanced result that is not the original is balancedOther")
      (assert (not (= bad.res "restored")) "a wrong result is not restored")
      true))

fn testEligible -> Bool
  (do
    (assert (pm/eligible? (fixture)) "a balanced 4+ line segment that guide leaves alone is a mutation source")
    (assert (not (pm/eligible? "fn f x: Int64 -> Int64\n  (let ((y (+ x 1))\n    (if (> y 2) y 0)))\n  \n")) "a balanced misnest that guide rewrites is not")
    (assert (not (pm/eligible? "fn f x: Int64 -> Int64\n  (+ x 1)\n")) "a segment under 4 lines is not")
    (assert (not (pm/eligible? "fn f x: Int64 -> Int64\n  (let [(y 1)]\n    (+ y 1)\n")) "an unbalanced segment is not")
    true)

fn testRateText -> Bool
  (do
    (assert (= (pb/permille 2350 2902) 810) "2350 of 2902 rounds to 810 per mille")
    (assert (= (pb/rateText 810) "0.810") "810 prints 0.810")
    (assert (= (pb/rateText 5) "0.005") "5 prints 0.005")
    (assert (= (pb/rateText 1000) "1.000") "1000 prints 1.000")
    (assert (= (pb/permille 0 0) 0) "no mutants is rate 0")
    true)

fn testBoundedRun -> Bool
  (let [(pop (pb/collect (list "asl/packages/asl-forms/src/indent.asl" "asl/packages/asl-forms/src/repair.asl" "asl/packages/asl-forms/src/ops.asl") (list) 0 0))
        (n (listLength pop.segs))
        (dr (pb/drawIdx 400 n (pb/stepRng0 7) (list)))
        (res (pb/walk pop.segs 0 (pairFirst dr) (pairSecond dr) (list)))
        (rows (pairFirst res))
        (del (filter (fn [(o pb/Outcome)] -> Bool (= o.kind "delete")) rows))
        (delOk (filter (fn [(o pb/Outcome)] -> Bool (= o.res "restored")) del))
        (all (filter (fn [(o pb/Outcome)] -> Bool (= o.res "restored")) rows))]
    (do
      (assert (= pop.files 3) "three files read")
      (assert (> n 20) "the three files hold more than 20 eligible segments")
      (assert (> (listLength rows) 150) "most of 400 draws give a mutant")
      (assert (>= (* 100 (listLength delOk)) (* 95 (listLength del))) "indentation repair restores 95%+ of missing closers on real source")
      (assert (>= (* 100 (listLength all)) (* 60 (listLength rows))) "and 60%+ of all one-closer mutants")
      (assert (< (listLength all) (listLength rows)) "the bench does not count every mutant restored")
      true))

fn testBaselineClasses -> Bool
  (let [(o (pb/outcomeOf (fixture) (pm/Mutant :kind "move" :text (fixture))))
        (missing (pb/Outcome :kind "delete" :dyck "dyckCatches" :res "restored"
                             :mutated "fn h x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)\n"
                             :orig "fn h x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0))\n"))]
    (do
      (assert (= (pb/fixResult missing) "ambiguous") "the older repair cannot pick between the closers that balance a mid-form deletion")
      (assert (listContains? (list "restored" "wrongRepair" "ambiguous" "unrepairable") (pb/fixResult (pb/Outcome :kind "insert" :dyck "dyckCatches" :res "restored" :mutated "fn h x: Int64 -> Int64\n  (+ x 1))\n" :orig "fn h x: Int64 -> Int64\n  (+ x 1)\n"))) "an unbalanced text gets one of the four repair verdicts")
      (assert (= (pb/fixResult (pb/Outcome :kind "delete" :dyck "dyckBlind" :res "restored" :mutated (fixture) :orig (fixture))) "saysBalanced") "the older repair reports a balanced text as balanced")
      true))

fn runTests -> Bool
  (do
    (assert (testSegments) "testSegments")
    (assert (testBalanced) "testBalanced")
    (assert (testTrailSites) "testTrailSites")
    (assert (testMutationKinds) "testMutationKinds")
    (assert (testSeedDeterministic) "testSeedDeterministic")
    (assert (testClassification) "testClassification")
    (assert (testEligible) "testEligible")
    (assert (testRateText) "testRateText")
    (assert (testBoundedRun) "testBoundedRun")
    (assert (testBaselineClasses) "testBaselineClasses")
    true)
