(module aslGateway/tests/spreadTest
  :x [runTests]
  :i [(aslGateway/router :a rt)])

fn noneDown alias: String -> Bool
  false

fn listAppendOne xs: (List T) x: T -> (List T)
  (listAppend xs (list x))

fn pickLoop now: Int64 cooldownSec: Int64 members: (List (Pair String Int64)) last429: (Map String Int64) breakerOpen?: (fn [String] -> Bool) state: (Map String Int64) n: Int64 acc: (List String) -> (Pair (List String) (Map String Int64))
  (if (<= n 0) (pair acc state)
    (let [(stepped (rt/spreadOrder now cooldownSec members last429 breakerOpen? state))
          (order (pairFirst stepped))
          (nextState (pairSecond stepped))
          (picked (optionOr (listHead order) ""))]
      (pickLoop now cooldownSec members last429 breakerOpen? nextState (- n 1) (listAppendOne acc picked))))

fn countOf xs: (List String) x: String -> Int64
  (listLength (filter (fn [(s String)] -> Bool (= s x)) xs))

; (:m :do "GW-SPREAD-20261017 gate: weights (3 1) give picks a a b a a a b a -- nginx's smooth weighted round-robin, verified by direct simulation, not assumed -- exactly 6:2 (3:1) over 8 calls")
fn ! testSwrrRatioMatchesWeights -> Bool
  (let [(members (list (pair "a" 3) (pair "b" 1)))
        (picks (pairFirst (pickLoop 0 60 members (mapEmpty) noneDown (mapEmpty) 8 (list))))]
    (do
      (assert (= picks (list "a" "a" "b" "a" "a" "a" "b" "a")) (str "SPREAD: weights (3 1) must pick a a b a a a b a over 8 calls, got " picks))
      (assert (= (countOf picks "a") 6) (str "SPREAD: a must be picked 6 times (weight 3 of 4 total) over 8 calls, got " (countOf picks "a")))
      (assert (= (countOf picks "b") 2) (str "SPREAD: b must be picked 2 times (weight 1 of 4 total) over 8 calls, got " (countOf picks "b")))
      true))

; (:m :do "GW-SPREAD-20261017 gate: the rest of the order (after the SWRR pick) is every other available member sorted by descending bumped current weight -- the order they would have won in, had the round continued -- never the configured order and never alphabetical")
fn ! testSpreadOrderRestIsDescendingWeight -> Bool
  (let [(members (list (pair "a" 1) (pair "b" 5) (pair "c" 2)))
        (stepped (rt/spreadOrder 0 60 members (mapEmpty) noneDown (mapEmpty)))
        (order (pairFirst stepped))]
    (do
      (assert (= (optionOr (listHead order) "") "b") (str "SPREAD: the heaviest member (b, weight 5) must be picked first, got " order))
      (assert (= order (list "b" "c" "a")) (str "SPREAD: the rest must follow by descending bumped weight (c=2 before a=1), got " order))
      true))

; (:m :do "GW-SPREAD-20261017 gate: a member that returned 429 is skipped for the pick until now - last429AtMs >= cooldownSec*1000; its stored current weight is untouched while skipped, so it resumes rotation rather than restarting cold once cooldown elapses")
fn ! testCooldownSkipsMemberUntilElapsed -> Bool
  (let [(members (list (pair "heavy" 3) (pair "light" 1)))
        (warm (pickLoop 0 60 members (mapEmpty) noneDown (mapEmpty) 1 (list)))
        (stateAfterWarm (pairSecond warm))
        (last429 (mapFromPairs (list (pair "heavy" 1000))))
        (duringCooldown (pickLoop 31000 60 members last429 noneDown stateAfterWarm 3 (list)))
        (picksDuring (pairFirst duringCooldown))
        (afterCooldown (rt/spreadOrder 61001 60 members last429 noneDown (pairSecond duringCooldown)))
        (orderAfter (pairFirst afterCooldown))]
    (do
      (assert (not (listContains? picksDuring "heavy")) (str "SPREAD: heavy must never be picked while within its 60s 429 cooldown, got " picksDuring))
      (assert (listAll? (fn [(p String)] -> Bool (= p "light")) picksDuring) (str "SPREAD: every pick during heavy's cooldown must be light, the only available member, got " picksDuring))
      (assert (listContains? orderAfter "heavy") (str "SPREAD: heavy must be eligible again once now - last429AtMs >= cooldownSec*1000, got " orderAfter))
      true))

; (:m :do "GW-SPREAD-20261017 gate: a breaker-open member is skipped for the pick exactly like an in-cooldown one, independent of 429 tracking")
fn ! testBreakerOpenSkipsMember -> Bool
  (let [(members (list (pair "a" 1) (pair "b" 1)))
        (aDown (fn [(alias String)] -> Bool (= alias "a")))
        (stepped (rt/spreadOrder 0 60 members (mapEmpty) aDown (mapEmpty)))
        (order (pairFirst stepped))]
    (do
      (assert (= order (list "b")) (str "SPREAD: a breaker-open member must be entirely absent from the order, got " order))
      true))

; (:m :do "GW-SPREAD-20261017 gate: every member in cooldown or breaker-open at once leaves nothing to pick, never an error and never a stale/default member")
fn ! testAllUnavailableYieldsEmptyOrder -> Bool
  (let [(members (list (pair "a" 1) (pair "b" 1)))
        (allDown (fn [(alias String)] -> Bool true))
        (stepped (rt/spreadOrder 0 60 members (mapEmpty) allDown (mapEmpty)))
        (order (pairFirst stepped))]
    (do
      (assert (listEmpty? order) (str "SPREAD: every member unavailable must yield an empty order, got " order))
      true))

fn ! runTests -> Bool
  (and (testSwrrRatioMatchesWeights)
    (and (testSpreadOrderRestIsDescendingWeight)
      (and (testCooldownSkipsMemberUntilElapsed)
        (and (testBreakerOpenSkipsMember) (testAllUnavailableYieldsEmptyOrder)))))
