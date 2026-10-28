(module aslGateway/tests/spreadStartTest
  :x [runTests]
  :i [(aslGateway/router :a rt)])

fn noneDown alias: String -> Bool
  false

fn pickLoop members: (List (Pair String Int64)) state: (Map String Int64) n: Int64 acc: (List String) -> (List String)
  (if (<= n 0) acc
    (let [(stepped (rt/spreadOrder 0 60 members (mapEmpty) noneDown state))]
      (pickLoop members (pairSecond stepped) (- n 1) (listAppend acc (list (optionOr (listHead (pairFirst stepped)) ""))))))

fn countOf xs: (List String) x: String -> Int64
  (listLength (filter (fn [(s String)] -> Bool (= s x)) xs))

; (:m :ref GW-SPREAD-START-20261028 :do "seed 0 keeps the old start; different seeds open on different members; every seed keeps the 3:1 ratio over a full cycle")
fn ! testSeedsOpenOnDifferentMembers -> Bool
  (let [(members (list (pair "a" 3) (pair "b" 1)))
        (first (fn [(seed Int64)] -> String (optionOr (listHead (pickLoop members (rt/spreadSeedState members seed) 1 (list))) "")))
        (opens (map first (list 0 1 2 3)))]
    (do
      (assert (= (first 0) "a") "seed 0 opens on the first member as before")
      (assert (and (listContains? opens "a") (listContains? opens "b")) (str "different seeds must open on different members, got " opens))
      (assert (= (rt/spreadSeedState members 4) (rt/spreadSeedState members 0)) "the seed wraps at the total weight")
      (assert (= (rt/spreadSeedState members (- 0 1)) (rt/spreadSeedState members 1)) "a negative seed is folded, not an error")
      true))

fn ! testSeededCycleKeepsRatio -> Bool
  (let [(members (list (pair "a" 3) (pair "b" 1)))
        (picks (pickLoop members (rt/spreadSeedState members 2) 8 (list)))]
    (do
      (assert (= (countOf picks "a") 6) (str "seeded rotation keeps weight 3 of 4 over 8 picks, got " picks))
      (assert (= (countOf picks "b") 2) (str "seeded rotation keeps weight 1 of 4 over 8 picks, got " picks))
      (assert (= (rt/spreadSeedState (list) 5) (mapEmpty)) "no members seed to empty state")
      true))

fn ! runTests -> Bool
  (and (testSeedsOpenOnDifferentMembers) (testSeededCycleKeepsRatio))
