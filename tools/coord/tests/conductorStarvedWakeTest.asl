(module asl-tools/coord/tests/conductorStarvedWakeTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd)])

; (:m :ref REVIEW-STARVED-WAKE :do "pure wake plan over fixture journal lines: a quorumStarved await excludes its unit until a passing reviewCall for its lane follows the round that closed it, or until its closing transition row is older than the TTL; an unanswered young starved unit, a pass of another alias and a pass from the starved round itself keep it parked")
fn cu id: String await: String -> cd/CUnit
  (cd/CUnit :id id :st "awaitReview" :lane "review" :fails 0 :sig "" :waited 0 :parked 1 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await await)

fn awaitRow id: String lane: String -> String
  (str "(:await :unit " id " :rung R3 :lane " lane " :why \"quorumStarved: reviewers did not answer at the last rung (pass 1 fail 0, quorum 2): " lane " call failed: 502 ERR_NO_UPSTREAM\")")

fn closeRow id: String at: Int64 -> String
  (str "(:t :unit \"" id "\" :from reviewing :to awaitReview :stage review :model \"\" :tokens 0 :costUsd 0 :verdict \"defer\" :ms 0 :at " (stringFromInt64 at) ")")

fn passRow alias: String -> String
  (str "(:reviewCall :unit \"X9\" :rung R3 :alias " alias " :verdict pass :defects 0 :tokens 0 :ms 5 :empty false)")

fn failRow alias: String -> String
  (str "(:reviewCall :unit \"X9\" :rung R3 :alias " alias " :verdict abstain :defects 0 :tokens 0 :ms 5 :empty true)")

fn idsOf plan: cd/AvailPlan -> List String
  (map (fn [(p (Pair cd/CUnit String))] -> String (let [(c (pairFirst p))] c.id)) plan.go)

fn planOf lines: (List String) now: Int64 ttlMs: Int64 -> (List String)
  (idsOf (cd/availPlanAt (list (cu "N1" "kmK31Pro") (cu "N2" "kmK31Pro") (cu "N3" "kmK31Pro") (cu "N4" "kmK31Pro") (cu "N5" "kmK31Pro")) (list (pair "kmK31Pro" 9)) (list) lines (mapEmpty) now ttlMs))

fn ! testStarvedWake -> Bool
  (let [(base (list (awaitRow "N1" "kmK31Pro") (closeRow "N1" 1000)
                    (awaitRow "N2" "kmK31Pro") (closeRow "N2" 1000)
                    (awaitRow "N3" "kmK31Pro") (closeRow "N3" 1000)
                    "(:await :unit N4 :rung R3 :lane kmK31Pro :why \"no strong lane\")" (closeRow "N4" 1000)
                    (awaitRow "N5" "kmK31Pro") (closeRow "N5" 1000)))
        (young (* 60 60000))
        (noNews (planOf base 2000 young))
        (withPass (planOf (listAppend base (list (passRow "kmK31Pro"))) 2000 young))
        (otherPass (planOf (listAppend base (list (passRow "ocOther") (failRow "kmK31Pro"))) 2000 young))
        (passBefore (planOf (listAppend (list (passRow "kmK31Pro")) base) 2000 young))
        (aged (planOf base (+ 1000 young) young))
        (justYoung (planOf base (- (+ 1000 young) 1) young))
        (ttlOff (planOf base (+ 1000 (* 99 young)) 0))
        (sameRound (idsOf (cd/availPlanAt (list (cu "N1" "kmK31Pro")) (list (pair "kmK31Pro" 9)) (list) (list (awaitRow "N1" "kmK31Pro") (passRow "kmK31Pro") (closeRow "N1" 1000)) (mapEmpty) 2000 young)))
        (plain (idsOf (cd/availPlan (list (cu "N1" "kmK31Pro")) (list (pair "kmK31Pro" 9)) (list) (list (awaitRow "N1" "kmK31Pro") (closeRow "N1" 1000) (passRow "kmK31Pro")) (mapEmpty))))
        (tierWait (idsOf (cd/availPlanAt (list (cu "T1" "paid strong")) (list (pair "paid" 5) (pair "strong" 5) (pair "kmK31Pro" 0)) (list) (list) (mapEmpty) 0 0)))]
    (do (assert (= noNews (list "N4")) (str "no newer success and younger than the TTL: only N4 (its newest await is no starved row) wakes: " (stringJoin noNews ",")))
        (assert (= withPass (list "N1" "N2" "N3" "N4" "N5")) (str "a successful reviewCall for the alias after the starved rounds wakes all five: " (stringJoin withPass ",")))
        (assert (= otherPass (list "N4")) (str "a pass of another alias and an abstain of the same alias do not wake: " (stringJoin otherPass ",")))
        (assert (= sameRound (list)) (str "a pass journalled inside the starved round itself does not wake: " (stringJoin sameRound ",")))
        (assert (= passBefore (list "N4")) (str "a pass older than the starved row does not wake: " (stringJoin passBefore ",")))
        (assert (= aged (list "N1" "N2" "N3" "N4" "N5")) (str "a starved row older than the TTL wakes: " (stringJoin aged ",")))
        (assert (= justYoung (list "N4")) (str "one ms short of the TTL stays parked: " (stringJoin justYoung ",")))
        (assert (= ttlOff (list "N4")) (str "TTL 0 is off: " (stringJoin ttlOff ",")))
        (assert (= plain (list "N1")) (str "availPlan keeps the pass rule without a clock: " (stringJoin plain ",")))
        (assert (= tierWait (list)) (str "a unit waiting on tier names is still not woken here, the tier mapping is not reachable from availPlan: " (stringJoin tierWait ",")))
        true))

fn ! runTests -> Bool
  (do (assert (testStarvedWake) "a starved await unit wakes on a newer reviewer success or after the TTL")
      (assert (cdErrorsOk) "starvedWakeMin is a known key bounded 1..10080")
      true)

fn cdErrorsOk -> Bool
  (and (listEmpty? (cd/cdErrors "(:conductor :starvedWakeMin 30)"))
       (and (not (listEmpty? (cd/cdErrors "(:conductor :starvedWakeMin 0)")))
            (not (listEmpty? (cd/cdErrors "(:conductor :starvedWakeMin 10081)")))))
