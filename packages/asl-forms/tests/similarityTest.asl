(module asl-forms/tests/similarityTest :x [runTests] :i [(asl-forms/similarity :a sm)])

fn testRatio -> Bool
  (do
    (assert (= (sm/ratio "abcd" "bcda") 0.75) "SequenceMatcher(None, abcd, bcda).ratio() is 0.75")
    (assert (= (sm/ratio "abc" "xyz") 0.0) "disjoint strings have ratio 0")
    (assert (= (sm/ratio "" "") 1.0) "two empty strings have ratio 1")
    true)

fn testCloseMatchOrder -> Bool
  (do
    (assert (= (sm/getCloseMatches "reed" (list "tree" "read" "research" "reef" "seed") 3 0.5) (list "tree" "seed" "reef")) "equal scores rank by word descending, as heapq.nlargest")
    (assert (= (sm/getCloseMatches "ab" (list "ba" "ab2" "ac" "bc") 4 0.1) (list "ab2" "bc" "ba" "ac")) "higher score first, then word descending")
    true)

fn testNearestSymbols -> Bool
  (do
    (assert (= (sm/nearestSymbols "alp" (list "alpha" "alpha" "Beta") 5) (list "alpha")) "names are deduplicated before matching")
    (assert (= (sm/nearestSymbols "Tect" (list "zzDetectLang" "b") 5) (list "zzDetectLang")) "a case-insensitive substring fills the list")
    true)

fn runTests -> Bool
  (do
    (assert (testRatio) "testRatio")
    (assert (testCloseMatchOrder) "testCloseMatchOrder")
    (assert (testNearestSymbols) "testNearestSymbols")
    true)
