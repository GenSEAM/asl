(module prelude/tests/preludeListAllocTest
  :x [runTests main]
  :i [(tools/fleet/run :a fr)])

fn ! main args: (List String) -> (Result Int64 String)
  (let [(sc (optionOr (listHead args) ""))
        (xs (range 0 10000))]
    (cond
      ((= sc "build") (do (println (str "result " (listLength xs))) (ok 0)))
      ((= sc "take") (let [(k (optionOr (stringToInt64 (optionOr (listGet args 1) "")) 0))]
                       (do (println (str "result " (listLength (listTake xs k)))) (ok 0))))
      ((= sc "drop") (let [(k (optionOr (stringToInt64 (optionOr (listGet args 1) "")) 0))]
                       (do (println (str "result " (listLength (listDrop xs k)))) (ok 0))))
      ((= sc "all") (do (println (str "result " (listAll? (fn [(x Int64)] -> Bool (>= x 0)) xs))) (ok 0)))
      ((= sc "any") (do (println (str "result " (listAny? (fn [(x Int64)] -> Bool (= x -1)) xs))) (ok 0)))
      (else (err (str "unknown scenario " sc)))))

fn ! testListTakeCorrectness -> Bool
  (do
    (assert (= (listTake (list) 3) (list)) "listTake of an empty list is empty")
    (assert (= (listTake (list 1 2 3) 0) (list)) "listTake n<=0 is empty")
    (assert (= (listTake (list 1 2 3) -5) (list)) "listTake of a negative n is empty")
    (assert (= (listTake (list 1 2 3) 2) (list 1 2)) "listTake takes the first n")
    (assert (= (listTake (list 1 2 3) 10) (list 1 2 3)) "listTake n > length returns the whole list unchanged")
    true)

fn ! testListDropCorrectness -> Bool
  (do
    (assert (= (listDrop (list) 3) (list)) "listDrop of an empty list is empty")
    (assert (= (listDrop (list 1 2 3) 0) (list 1 2 3)) "listDrop n<=0 is the whole list")
    (assert (= (listDrop (list 1 2 3) -5) (list 1 2 3)) "listDrop of a negative n is the whole list")
    (assert (= (listDrop (list 1 2 3) 2) (list 3)) "listDrop drops the first n")
    (assert (= (listDrop (list 1 2 3) 10) (list)) "listDrop n > length is empty")
    true)

fn allOnlyFirst x: Int64 -> Bool
  (if (= x 1) false (preludeHead (list)))

fn anyOnlyFirst x: Int64 -> Bool
  (if (= x 1) true (preludeHead (list)))

fn ! testListAllCorrectness -> Bool
  (do
    (assert (listAll? (fn [(x Int64)] -> Bool (>= x 0)) (list)) "listAll? of an empty list is true")
    (assert (listAll? (fn [(x Int64)] -> Bool (>= x 0)) (list 1 2 3)) "listAll? true when every element matches")
    (refute (listAll? (fn [(x Int64)] -> Bool (>= x 0)) (list 1 -2 3)) "listAll? false when one element fails")
    (refute (listAll? allOnlyFirst (list 1 2 3)) "listAll? exits at the first failing element without forcing the rest")
    true)

fn ! testListAnyCorrectness -> Bool
  (do
    (refute (listAny? (fn [(x Int64)] -> Bool (>= x 0)) (list)) "listAny? of an empty list is false")
    (assert (listAny? (fn [(x Int64)] -> Bool (= x 2)) (list 1 2 3)) "listAny? true when one element matches")
    (refute (listAny? (fn [(x Int64)] -> Bool (= x 9)) (list 1 2 3)) "listAny? false when none match")
    (assert (listAny? anyOnlyFirst (list 1 2 3)) "listAny? exits at the first matching element without forcing the rest")
    true)

fn statsLine text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringLines text))) "")

fn tokenAfter tokens: (List String) key: String -> (Option String)
  (mt (listIndexOf tokens key)
    ((some i) (listGet tokens (+ i 1)))
    (none none))

fn objectsAllocated line: String -> Int64
  (optionOr (mt (tokenAfter (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")) ":objectsAllocated")
              ((some v) (stringToInt64 (stringReplace v ")" "")))
              (none none))
            -1)

fn ! runScenario extraArgs: (List String) -> (Pair Int64 String)
  (let [(argv (listAppend (list (fr/host!) "run" "asl/prelude/tests/preludeListAllocTest.asl") extraArgs))
        (d (fr/runOneLimited (fr/job argv "." (fr/childEnv (list "ASL_GC_STATS=1"))) (fr/limits 20 6)))]
    (do
      (assert (= d.exit 0) (str (fr/quoteArgv extraArgs) " subprocess exits 0 (verdict " d.verdict "): " d.out))
      (pair (objectsAllocated (statsLine d.out)) d.out)))

fn ! testListTakeAllocation -> Bool
  (let [(base (pairFirst (runScenario (list "build"))))
        (r (runScenario (list "take" "5000")))
        (marginal (- (pairFirst r) base))]
    (do
      (assert (> base 0) (str "a (:gcStats ...) line was captured for the build baseline: " (pairSecond r)))
      (assert (< marginal 7000) (str "listTake of 5000 elements out of 10000 allocates about k objects (the k cons cells; measured ~5025), "
                                      "not k extra via optionOr's wasted allocation per element (measured ~10025 before the fix): marginal=" marginal " " (pairSecond r)))
      true))

fn ! testListDropAllocation -> Bool
  (let [(base (pairFirst (runScenario (list "build"))))
        (r (runScenario (list "drop" "5000")))
        (marginal (- (pairFirst r) base))]
    (do
      (assert (< marginal 2000) (str "listDrop builds nothing new, so dropping 5000 of 10000 elements allocates near zero extra objects "
                                      "(measured ~25), not one per dropped element via optionOr (measured ~5025 before the fix): marginal=" marginal " " (pairSecond r)))
      true))

fn ! testListAllAllocation -> Bool
  (let [(base (pairFirst (runScenario (list "build"))))
        (r (runScenario (list "all")))
        (marginal (- (pairFirst r) base))]
    (do
      (assert (< marginal 2000) (str "listAll? over all 10000 elements returns a Bool and allocates near zero extra objects "
                                      "(measured ~1), not one per element via optionOr (measured ~9975 before the fix): marginal=" marginal " " (pairSecond r)))
      true))

fn ! testListAnyAllocation -> Bool
  (let [(base (pairFirst (runScenario (list "build"))))
        (r (runScenario (list "any")))
        (marginal (- (pairFirst r) base))]
    (do
      (assert (< marginal 2000) (str "listAny? forced over all 10000 elements returns a Bool and allocates near zero extra objects "
                                      "(measured ~1), not one per element via optionOr (measured ~9975 before the fix): marginal=" marginal " " (pairSecond r)))
      true))

fn ! runTests -> Bool
  (do
    (assert (testListTakeCorrectness) "listTake edge cases: empty, n<=0, negative n, n > length")
    (assert (testListDropCorrectness) "listDrop edge cases: empty, n<=0, negative n, n > length")
    (assert (testListAllCorrectness) "listAll? edge cases, including early exit on the first failure")
    (assert (testListAnyCorrectness) "listAny? edge cases, including early exit on the first match")
    (assert (testListTakeAllocation) "listTake allocates ~k objects for a 10k list, not k extra via optionOr")
    (assert (testListDropAllocation) "listDrop allocates ~0 extra objects for a 10k list, not one per dropped element")
    (assert (testListAllAllocation) "listAll? allocates ~0 extra objects over a 10k list, not one per element")
    (assert (testListAnyAllocation) "listAny? allocates ~0 extra objects over a 10k list, not one per element")
    true)
