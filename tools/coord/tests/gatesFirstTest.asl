(module asl-tools/coord/tests/gatesFirstTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref GATES-PROVEN-FIRST :do "a receipt without a red-before proof is refused before any reviewer is called: first time a fix ruling naming the gate defect, after a fix round blocked, and a proven receipt still reaches the models")
fn lane alias: String tier: String -> l/Lane
  (l/Lane :alias alias :tier tier :allowance 5 :quality 0)

fn unitOf fixes: Int64 -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task "t" :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "" :fixesUsed fixes :prior (list))

fn ! runOnce counter: String u: l/ReviewUnit gates: String -> l/Ruling
  (match (l/review u "+ a" gates (list (lane "orNemotronUltraFree" "free") (lane "ocLongcat" "free") (lane "ocDeepseekFlash" "paid") (lane "ccKimi31Pro" "strong"))
           (fn [(a String) (p String)] -> (Result String String) (do (fileAppend counter "x\n") (ok "(:verdict :pass :defects () :model m)"))))
    ((ok r) r)
    ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e)))

fn ! calls counter: String -> Int64
  (listLength (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringLines (resultOr (fileReadString counter) ""))))

fn ! runTests -> Bool
  (let [(dir (pf/scratch "gatesFirst" "g"))
        (_ (dirCreate dir))
        (c1 (str dir "/c1"))
        (c2 (str dir "/c2"))
        (c3 (str dir "/c3"))
        (noRed "(:receipt U1 :gates ((:gate g :exit 0 :executed 12)))")
        (red "(:receipt U1 :gates ((:gate g :exit 0 :executed 12)) :redBefore ((:gate g :exit 1 :executed 0)))")
        (a (runOnce c1 (unitOf 0) noRed))
        (b (runOnce c2 (unitOf 1) noRed))
        (m (runOnce c3 (unitOf 0) red))
        (n1 (calls c1))
        (n2 (calls c2))
        (n3 (calls c3))
        (_ (pathRemove dir))]
    (do (assert (and (= a.action "fix") (= n1 0)) (str "no red-before: fix with 0 model calls: " a.action " " (stringFromInt64 n1)))
        (assert (stringContains? (stringJoin a.defects ";") "red-before") "the defect names the red-before proof")
        (assert (and (= b.action "blocked") (= n2 0)) (str "after a fix round: blocked with 0 model calls: " b.action " " (stringFromInt64 n2)))
        (assert (and (= m.action "merge") (> n3 0)) (str "a proven receipt reaches the models and merges: " m.action " " (stringFromInt64 n3)))
        true))
