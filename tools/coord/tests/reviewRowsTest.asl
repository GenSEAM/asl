(module asl/tools/coord/tests/reviewRowsTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/reviewStage :a rs)])

fn lane alias: String tier: String -> l/Lane
  (l/Lane :alias alias :tier tier :allowance 5 :quality 0)

fn unit risk: String -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task "fix the bound in listTake" :risk risk :closureChanged false :writerAlias "flashHigh" :writerChannel "agy"
                :startRung (if (= risk "high") "R1" "") :fixesUsed 0 :prior (list))

fn gates -> String
  (str "(:receipt U1 :gates ((:gate ladderTest :exit 0 :executed 12)) :redBefore ((:gate ladderTest :exit 1 :executed 0)))")

fn lookup replies: (List (Pair String String)) alias: String -> String
  (optionOr (listHead (map pairSecond (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) alias)) replies))) "no reply")

fn ruled u: l/ReviewUnit lanes: (List l/Lane) replies: (List (Pair String String)) -> l/Ruling
  (match (l/review u "+ a\n- b" (gates) lanes (fn [(a String) (p String)] -> (Result String String) (ok (lookup replies a))))
    ((ok r) r)
    ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e)))

fn callsOf r: l/Ruling -> (List String)
  (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:reviewCall ")) r.rows)

fn rowFor calls: (List String) alias: String -> String
  (optionOr (listHead (filter (fn [(x String)] -> Bool (stringContains? x (str " :alias " alias " "))) calls)) "")

; (:m :ref TRIAL-REVIEW-ROWS :do "a pass, a fail with one defect and an empty reply each leave one reviewCall row with the verdict, the defect count and :empty true only for the blank reply")
fn testRows -> Bool
  (let [(lanes (list (lane "orNemotronUltraFree" "free") (lane "ocLongcat" "free")))
        (r1 (ruled (unit "low") lanes (list (pair "ocLongcat" "(:verdict :pass :defects () :model m)")
                                             (pair "orNemotronUltraFree" "(:verdict :fail :defects (\"listTake overruns the slice in clip\") :model m)"))))
        (c1 (callsOf r1))
        (pass (rowFor c1 "ocLongcat"))
        (fail (rowFor c1 "orNemotronUltraFree"))
        (r2 (ruled (unit "low") lanes (list (pair "ocLongcat" "(:verdict :pass :defects () :model m)") (pair "orNemotronUltraFree" ""))))
        (blank (rowFor (callsOf r2) "orNemotronUltraFree"))]
    (do (assert (= (listLength c1) (listLength r1.verdicts)) (str "one reviewCall row per reviewer call: " (stringJoin r1.rows " | ")))
        (assert (= (listLength c1) 2) "two reviewers were asked")
        (assert (and (stringContains? pass ":verdict pass") (and (stringContains? pass ":defects 0") (stringContains? pass ":empty false"))) (str "pass row: " pass))
        (assert (and (stringContains? fail ":verdict fail") (and (stringContains? fail ":defects 1") (stringContains? fail ":empty false"))) (str "fail row: " fail))
        (assert (and (stringContains? blank ":verdict abstain") (and (stringContains? blank ":defects 0") (stringContains? blank ":empty true"))) (str "empty row: " blank))
        (assert (listAll? (fn [(x String)] -> Bool (and (stringContains? x ":unit U1 :rung R1 ") (and (stringContains? x " :tokens 0 :ms ") (stringContains? x " :empty ")))) c1) (str "row shape: " (stringJoin c1 " | ")))
        true))

; (:m :ref TRIAL-REVIEW-ROWS :do "the rows of a rung that escalated survive: a high-risk unit asks R1 and then R2, and the ruling carries the reviewCall rows of both")
fn testEscalated -> Bool
  (let [(lanes (list (lane "orNemotronUltraFree" "free") (lane "ocLongcat" "free") (lane "ocDeepseekFlash" "paid")))
        (replies (list (pair "ocLongcat" "(:verdict :pass :defects () :model m)")
                       (pair "orNemotronUltraFree" "(:verdict :pass :defects () :model m)")
                       (pair "ocDeepseekFlash" "(:verdict :pass :defects () :model m)")))
        (r (ruled (unit "high") lanes replies))
        (calls (callsOf r))]
    (do (assert (= r.action "merge") (str "escalated ruling merges: " r.action " " r.why))
        (assert (= (listLength calls) (listLength r.verdicts)) (str "rows of both rungs kept: " (stringJoin r.rows " | ")))
        (assert (listAny? (fn [(x String)] -> Bool (stringContains? x " :rung R1 ")) calls) "R1 row kept")
        (assert (listAny? (fn [(x String)] -> Bool (stringContains? x " :rung R2 ")) calls) "R2 row kept")
        true))

; (:m :ref TRIAL-REVIEW-ROWS :do "the stage fills :tokens from the usage rows of the same alias in call order and leaves rows without a usage row at 0")
fn testTokens -> Bool
  (let [(rows (list "(:reviewCall :unit U1 :rung R1 :alias a :verdict pass :defects 0 :tokens 0 :ms 5 :empty false)"
                    "(:grade U1)"
                    "(:reviewCall :unit U1 :rung R1 :alias b :verdict pass :defects 0 :tokens 0 :ms 5 :empty false)"
                    "(:reviewCall :unit U1 :rung R2 :alias a :verdict pass :defects 0 :tokens 0 :ms 5 :empty false)"
                    "(:reviewCall :unit U1 :rung R2 :alias c :verdict pass :defects 0 :tokens 0 :ms 5 :empty false)"))
        (usage "(:usage :alias a :tokens 11 :costMicros 0)\n(:usage :alias b :tokens 22 :costMicros 0)\n(:usage :alias a :tokens 33 :costMicros 0)\n")
        (out (rs/tokensFilled rows usage))]
    (do (assert (stringContains? (optionOr (listGet out 0) "") ":tokens 11 ") "first a takes 11")
        (assert (= (optionOr (listGet out 1) "") "(:grade U1)") "other rows untouched")
        (assert (stringContains? (optionOr (listGet out 2) "") ":tokens 22 ") "b takes 22")
        (assert (stringContains? (optionOr (listGet out 3) "") ":tokens 33 ") "second a takes 33")
        (assert (stringContains? (optionOr (listGet out 4) "") ":tokens 0 ") "no usage row, stays 0")
        true))

fn ! runTests -> Bool
  (do (assert (testRows) "one reviewCall row per reviewer call")
      (assert (testEscalated) "rows survive an escalation")
      (assert (testTokens) "tokens filled from usage rows")
      true)

