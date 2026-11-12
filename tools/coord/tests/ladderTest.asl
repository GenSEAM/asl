(module asl/tools/coord/tests/ladderTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/grade :a g)])

fn lane alias: String tier: String n: Int64 -> l/Lane
  (l/Lane :alias alias :tier tier :allowance n :quality 0)

fn pool -> (List l/Lane)
  (list (lane "flashLow" "free" 5) (lane "orNemotronUltraFree" "free" 5) (lane "nimNemotronUltra" "free" 5) (lane "ocLongcat" "free" 5)
        (lane "ocDeepseekFlash" "paid" 5) (lane "tgGlm53Flash" "paid" 5)
        (lane "ccKimi31Pro" "strong" 5))

fn unit risk: String closure: Bool -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task "fix the bound in listTake" :risk risk :closureChanged closure :writerAlias "flashHigh" :writerChannel "agy"
                :startRung "" :fixesUsed 0 :prior (list))

fn goodGates -> String
  (str "(:receipt U1 :gates ((:gate ladderTest :exit 0 :executed 12)) :redBefore ((:gate ladderTest :exit 1 :executed 0)))")

fn noRedGates -> String
  (str "(:receipt U1 :gates ((:gate ladderTest :exit 0 :executed 12)))")

fn passReply -> String
  "(:verdict :pass :defects () :model m)"

fn failReply -> String
  "(:verdict :fail :defects (\"listTake overruns the slice in clip\") :model m)"

fn lookup replies: (List (Pair String String)) alias: String -> String
  (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) alias)) replies))
    ((some p) (pairSecond p))
    ((none) "no reply"))

fn run u: l/ReviewUnit gates: String lanes: (List l/Lane) replies: (List (Pair String String)) -> l/Ruling
  (match (l/review u "+ a\n- b" gates lanes (fn [(a String) (p String)] -> (Result String String) (ok (lookup replies a))))
    ((ok r) r)
    ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e)))

fn models r: l/Ruling -> (List String)
  (map (fn [(v l/Verdict)] -> String v.model) r.verdicts)

fn rungs r: l/Ruling -> (List String)
  (map (fn [(v l/Verdict)] -> String v.rung) r.verdicts)

fn rows -> (List rd)
  (list)

fn testFamilies -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))]
    (do (assert (= (l/familyIn rs "ocDeepseekFlash") "deepseek") "deepseek flash is deepseek not google")
        (assert (= (l/familyIn rs "orDsFlash0731") "deepseek") "or ds alias is deepseek")
        (assert (= (l/familyIn rs "flashHigh") "google") "agy flash alias is google")
        (assert (= (l/familyIn rs "claude-opus-5-5") "anthropic") "model names map too")
        (assert (= (l/familyIn rs "ccKimi31Pro") "moonshot") "kimi is moonshot")
        (assert (= (l/familyIn rs "ocCatJam") "") "an unknown alias has no family")
        (assert (= (listLength (l/familyRows "(:families")) 0) "a broken table yields no rows")
        true))

fn testSelect -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))
        (fam (fn [(a String)] -> String (l/familyIn rs a)))]
    (do (match (l/selectFree rs "flashHigh" (pool))
          ((l/pickOk ls)
            (do (assert (= (listLength ls) 2) "R1 picks two reviewers")
                (assert (not (listContains? (map (fn [(x l/Lane)] -> String (fam x.alias)) ls) "google")) "R1 never picks the writer's family")
                (assert (let [(fs (map (fn [(x l/Lane)] -> String (fam x.alias)) ls))] (!= (optionOr (listGet fs 0) "") (optionOr (listGet fs 1) ""))) "R1 reviewers are of different families")
                true))
          ((l/pickAwait a w) (do (assert false "R1 should pick") true)))
        (match (l/selectOne rs "ocDeepseekFlash" "paid" (pool))
          ((l/pickOk ls) (assert (= (optionOr (listHead (map (fn [(x l/Lane)] -> String x.alias) ls)) "") "tgGlm53Flash") "R2 skips the writer's family"))
          ((l/pickAwait a w) (assert false "R2 should pick")))
        (match (l/selectOne rs "ccKimi31Pro" "strong" (pool))
          ((l/pickOk ls) (assert false "R3 must not pick the writer's own family"))
          ((l/pickAwait a w) (assert (= a "strong") "R3 waits on the strong tier when its only lane is the writer family")))
        (match (l/selectFree rs "mimoMimoV26Pro+olGptOss120b+ccInclusionaiLing31Flash" (pool))
          ((l/pickOk ls) (assert (= (listLength ls) 2) "R1 picks two non-overlapping reviewers when writer used a multi-family profile"))
          ((l/pickAwait a w) (assert false "multi-family writer profile must not stall on writerFamily")))
        (assert (= (l/reviewWriter "unknown" "") "unknown") "an unknown writer with no configured alias stays unknown, not replaced by a guessed alias")
        (assert (= (l/reviewWriter "" "") "") "no writer evidence at all stays empty, distinct from the literal unknown")
        (assert (= (l/reviewWriter "" "ccKimi31Pro") "ccKimi31Pro") "an empty model takes the configured writer alias")
        (match (l/selectOne rs (l/reviewWriter "unknown" "") "strong" (pool))
          ((l/pickOk ls) (assert false "a review of an unknown writer must not pick a lane"))
          ((l/pickAwait a w) (assert (= a "writerFamily") "a review of an unknown writer waits on writerFamily")))
        (match (l/selectFree rs "unknown" (pool))
          ((l/pickOk ls) (assert false "R1 for the literal unknown writer must still wait"))
          ((l/pickAwait a w) (assert (= a "writerFamily") "R1 for the literal unknown writer waits on writerFamily")))
        (match (l/selectFree rs "" (pool))
          ((l/pickOk ls) (assert (= (listLength ls) 2) "R1 with no writer evidence picks two reviewers of different families, no exclusion"))
          ((l/pickAwait a w) (assert false (str "R1 with no writer evidence must not defer: " w))))
        (match (l/selectOne rs "" "paid" (pool))
          ((l/pickOk ls) (assert (= (listLength ls) 1) "R2 with no writer evidence picks a paid lane"))
          ((l/pickAwait a w) (assert false (str "R2 with no writer evidence must not defer: " w))))
        (match (l/selectOne rs "" "strong" (pool))
          ((l/pickOk ls) (assert (= (optionOr (listHead (map (fn [(x l/Lane)] -> String x.alias) ls)) "") "ccKimi31Pro") "R3 with no writer evidence picks the strong lane"))
          ((l/pickAwait a w) (assert false (str "R3 with no writer evidence must not defer: " w))))
        true))

fn testVerdicts -> Bool
  (let [(v (fn [(t String)] -> l/Verdict (l/parseVerdict t "m" "R1")))]
    (do (assert (= (v (passReply)).outcome "pass") "well formed pass")
        (assert (= (v (failReply)).outcome "fail") "fail with a defect")
        (assert (= (v "```\n(:verdict :pass :defects () :model m)\n```").outcome "pass") "a fenced reply parses")
        (assert (= (v "looks good to me").outcome "abstain") "prose is abstain, not pass")
        (assert (= (v "(:verdict :pass").outcome "abstain") "unbalanced is abstain")
        (assert (= (v "(:verdict :fail :defects ())").outcome "abstain") "fail without a defect is abstain")
        (assert (= (v "(:verdict :pass :fail)").outcome "abstain") "both pass and fail is abstain")
        (assert (= (v "(:verdict :maybe)").outcome "abstain") "unknown outcome is abstain")
        (assert (= (v "").outcome "abstain") "empty is abstain")
        true))

fn testMerge -> Bool
  (let [(r (run (unit "low" false) (goodGates) (pool) (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)))))]
    (do (assert (= r.action "merge") "R1 both pass with red-before gates and low risk merges")
        (assert (= (listLength r.verdicts) 2) "two R1 verdicts")
        (assert (not (listContains? (models r) "flashLow")) "the writer's family is never asked")
        (assert (listEmpty? (g/statsProblems (optionOr (listHead r.rows) ""))) "the merge row is a valid grade row")
        (assert (stringContains? (optionOr (listHead r.rows) "") ":verdict accept") "merge is an accept grade")
        (let [(m (run (unit "med" false) (goodGates) (pool) (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)))))
              (n (run (unit "low" false) (noRedGates) (pool) (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)))))]
          (do (assert (= m.action "merge") "med risk with both pass merges per the plan row")
              (assert (= n.action "fix") "gates not proven red-before go back to the writer, never merge")
              true))))

fn testSplitAndAbstain -> Bool
  (let [(split (run (unit "low" false) (goodGates) (pool)
                 (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" (passReply)))))
        (junk (run (unit "low" false) (goodGates) (pool)
                 (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" "LGTM") (pair "ocDeepseekFlash" "LGTM") (pair "ccKimi31Pro" "LGTM"))))
        (bothFail (run (unit "low" false) (goodGates) (pool)
                 (list (pair "orNemotronUltraFree" (failReply)) (pair "ocLongcat" (failReply)))))]
    (do (assert (= (rungs split) (list "R1" "R1" "R2")) "a split at R1 escalates to R2")
        (assert (= split.action "merge") "R2 tie-break pass makes the majority")
        (assert (= split.rung "R2") "merged on R2")
        (assert (!= junk.action "merge") "an abstaining reviewer never counts as a pass")
        (assert (= junk.action "blocked") (str "pass 1 fail 0 with garbage answers keeps the tiebreak block, never defers: " junk.action))
        (assert (= bothFail.action "fix") "both fail with defects goes back to the writer")
        (assert (not (listEmpty? bothFail.defects)) "the fix round carries the defects")
        true))

fn testFixCap -> Bool
  (let [(u (l/ReviewUnit :id "U1" :task "t" :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "" :fixesUsed 1 :prior (list)))
        (r (run u (goodGates) (pool) (list (pair "orNemotronUltraFree" (failReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" (failReply)) (pair "ccKimi31Pro" (failReply)))))]
    (do (assert (= (rungs r) (list "R1" "R1" "R2")) "R1 failing after its fix round climbs to R2 instead of a second R1 fix")
        (assert (and (= r.action "fix") (= r.rung "R2")) "the fresh rung gets its own single fix round")
        (let [(u3 (l/ReviewUnit :id "U1" :task "t" :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "R3" :fixesUsed 1 :prior (list)))
              (r3 (run u3 (goodGates) (pool) (list (pair "ccKimi31Pro" (failReply)))))]
          (assert (= r3.action "blocked") "a fail at R3 after its fix round is blocked"))
        true))

fn testRisk -> Bool
  (let [(high (run (unit "high" false) (goodGates) (pool) (list (pair "ocDeepseekFlash" (passReply)))))
        (closure (run (unit "low" true) (goodGates) (pool)
                   (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)) (pair "ocDeepseekFlash" (passReply)))))]
    (do (assert (= (rungs high) (list "R2")) "high risk skips R1 and asks only R2")
        (assert (= high.action "merge") "a single R2 pass merges at high risk")
        (assert (= (rungs closure) (list "R1" "R1" "R2")) "a closure change escalates one rung even when R1 passes")
        (assert (= closure.action "merge") "closure change merges after R2 passes")
        true))

fn testAwait -> Bool
  (let [(none (list (lane "flashLow" "free" 5) (lane "orNemotronUltraFree" "free" 0) (lane "ocLongcat" "free" 0) (lane "ocDeepseekFlash" "paid" 5)))
        (one (list (lane "orNemotronUltraFree" "free" 5) (lane "nimNemotronUltra" "free" 5) (lane "ocLongcat" "free" 0)))
        (a (run (unit "low" false) (goodGates) none (list)))
        (b (run (unit "low" false) (goodGates) one (list)))
        (c (run (unit "high" false) (goodGates) (list (lane "ocDeepseekFlash" "paid" 0)) (list)))
        (d (run (unit "low" false) (goodGates) (list (lane "orNemotronUltraFree" "free" 5) (lane "ocLongcat" "free" 5) (lane "ocDeepseekFlash" "paid" 0))
                (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)))))]
    (do (assert (and (= a.action "await") (= a.awaitLane "orNemotronUltraFree")) "no free allowance awaits the first out-of-allowance eligible free lane")
        (assert (and (= b.action "await") (= b.awaitLane "ocLongcat")) "one family left awaits the lane of a second family")
        (assert (and (= c.action "await") (= c.awaitLane "ocDeepseekFlash strong") (= c.rung "R2")) (str "high risk with no paid or strong allowance awaits at R2 on the paid lane and the strong tier: " c.awaitLane))
        (assert (and (= d.action "await") (= d.rung "R2") (= (listLength d.verdicts) 2)) "a split with no R2 allowance awaits R2 and keeps the R1 verdicts")
        true))

; (:m :ref REVIEW-EMPTY-QUORUM-BLOCKS :do "a reviewer with no verdict is absent, not a vote: at the last rung pass 1 fail 0 and pass 0 fail 0 (the rest absent) defer to the lanes that did not answer, only a real split (a pass and a fail) blocks, and verdicts that exist and meet the quorum still pass")
fn testAbsentQuorum -> Bool
  (let [(one (run (unit "low" false) (goodGates) (pool)
              (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" "") (pair "ocDeepseekFlash" "") (pair "ccKimi31Pro" ""))))
        (nobody (run (unit "low" false) (goodGates) (pool)
              (list (pair "orNemotronUltraFree" "") (pair "ocLongcat" "") (pair "ocDeepseekFlash" "") (pair "ccKimi31Pro" ""))))
        (split (run (unit "low" false) (goodGates) (pool)
              (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" "") (pair "ccKimi31Pro" ""))))
        (rowOf (fn [(r l/Ruling)] -> String (optionOr (listHead (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:await")) r.rows)) "")))]
    (do (assert (and (= one.action "await") (not (stringEmpty? one.awaitLane))) (str "pass 1 fail 0 awaits the absent lanes: " one.action " " one.awaitLane))
        (assert (stringContains? (rowOf one) "did not answer at the last rung (pass 1 fail 0") (str "the await row says why: " (rowOf one)))
        (assert (and (= nobody.action "await") (not (stringEmpty? nobody.awaitLane))) (str "pass 0 fail 0 awaits, never blocks: " nobody.action " " nobody.awaitLane))
        (assert (stringContains? (rowOf nobody) "pass 0 fail 0") (str "the await row names the tally: " (rowOf nobody)))
        (assert (= split.action "blocked") (str "a pass and a fail is still a split and blocks: " split.action))
        (assert (= one.awaitLane "ccKimi31Pro") (str "the await target is exactly the absent aliases: " one.awaitLane))
        (assert (stringContains? (rowOf one) ":why \"quorumStarved: ") (str "a starved defer is marked for the conductor's cap: " (rowOf one)))
        true))

; (:m :ref CONDWIRE-A :do "only absence defers: garbled text, a fail without a defect and a blank reply are told apart, a failed call (429, no credit) is absence; the old tiebreak block stays for the rest")
fn testAbsenceKinds -> Bool
  (let [(garbage (run (unit "low" false) (goodGates) (pool)
              (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" "") (pair "ocDeepseekFlash" "") (pair "ccKimi31Pro" "garbled"))))
        (sloppy (run (unit "low" false) (goodGates) (pool)
              (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" "(:verdict :fail :defects ())") (pair "ocDeepseekFlash" "") (pair "ccKimi31Pro" "(:verdict :fail :defects ())"))))
        (rate (match (l/review (unit "low" false) "+ a\n- b" (goodGates) (pool)
                       (fn [(a String) (p String)] -> (Result String String)
                         (if (= a "ccKimi31Pro") (err "http 429 rate limited")
                           (if (= a "orNemotronUltraFree") (ok (passReply)) (ok "")))))
                ((ok r) r)
                ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e))))
        (credit (match (l/review (unit "low" false) "+ a\n- b" (goodGates) (pool)
                         (fn [(a String) (p String)] -> (Result String String)
                           (if (= a "ccKimi31Pro") (err "http 400 insufficient credits")
                             (if (= a "orNemotronUltraFree") (ok (passReply)) (ok "")))))
                  ((ok r) r)
                  ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e))))]
    (do (assert (= garbage.action "blocked") (str "a garbled reviewer does not defer: " garbage.action " " garbage.why))
        (assert (stringStartsWith? garbage.why "tiebreak: reviewers split at the last rung") (str "the old tiebreak reason stays: " garbage.why))
        (assert (= sloppy.action "blocked") (str "pass plus a fail without a defect keeps the old outcome: " sloppy.action))
        (assert (and (= rate.action "await") (= rate.awaitLane "ccKimi31Pro")) (str "a 429 is absence: " rate.action " " rate.awaitLane))
        (assert (and (= credit.action "blocked") (stringContains? credit.why "review: no live lane on tier strong (permanent: ccKimi31Pro credits)") (stringContains? (stringJoin credit.rows " ") ":laneUnavailable") (stringContains? (stringJoin credit.rows " ") "(:escalate :unit U1")) (str "no credit is permanent, not absence: the sole strong lane leaves the pool and the ruling blocks at once, visibly: " credit.action " " credit.why))
        true))

; (:m :ref LANE-PERMANENT-ERROR :do "a lane that fails permanently (400 insufficient credits, 401, 403, 404) leaves the pool for the review: one laneUnavailable warn row, the rung is picked again and the review reaches the next lane; 429 and 5xx stay absence and still defer; a status code inside a longer number is no status")
fn testPermanentLane -> Bool
  (let [(lanes (list (lane "orNemotronUltraFree" "free" 5) (lane "ocLongcat" "free" 5) (lane "orKimiFree" "free" 5) (lane "ccKimi31Pro" "strong" 5)))
        (via (fn [(deadAlias String) (msg String)] -> l/Ruling
               (match (l/review (unit "low" false) "+ a\n- b" (goodGates) lanes
                        (fn [(a String) (p String)] -> (Result String String) (if (= a deadAlias) (err msg) (ok (passReply)))))
                 ((ok r) r)
                 ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e)))))
        (warns (fn [(r l/Ruling)] -> (List String) (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:laneUnavailable ")) r.rows)))
        (credit (via "ocLongcat" "http 400 insufficient credits"))
        (kimiDead (via "ocLongcat" "http 401 unauthorized"))
        (gone (via "orNemotronUltraFree" "HTTP 404 model not found"))
        (rate (via "ocLongcat" "http 429 rate limited"))
        (longNum (via "ocLongcat" "failed after 4040 ms"))]
    (do (assert (and (= credit.action "merge") (not (listContains? (models credit) "ocLongcat"))) (str "400 insufficient credits: the dead lane is skipped and the review merges on the others: " credit.action " " (stringJoin (models credit) ",")))
        (assert (and (= (listLength (warns credit)) 1) (stringContains? (optionOr (listHead (warns credit)) "") ":lane ocLongcat ") (stringContains? (optionOr (listHead (warns credit)) "") ":sev warn")) (str "one warn row names the lane: " (stringJoin credit.rows " | ")))
        (assert (not (stringStartsWith? (optionOr (listHead credit.rows) "") "(:reviewCall")) "the head row is still the grade row")
        (assert (and (= kimiDead.action "merge") (= (listLength (warns kimiDead)) 1)) (str "401 is permanent too: " kimiDead.action " " (stringJoin kimiDead.rows " | ")))
        (assert (and (= gone.action "merge") (= (listLength (warns gone)) 1) (not (listContains? (models gone) "orNemotronUltraFree"))) (str "404 is permanent: " gone.action " " (stringJoin (models gone) ",")))
        (assert (and (listEmpty? (warns rate)) (not (stringContains? (stringJoin rate.rows " ") ":laneUnavailable"))) "429 is not permanent")
        (assert (listEmpty? (warns longNum)) "4040 ms is no 404")
        true))

; (:m :ref LANE-PERMANENT-ERROR-FIX :do "a sole strong lane that fails with 401 blocks in one ruling with the sig, the escalate row and one laneUnavailable row, never an await on a tier name; permanent needs a real status: the numbers inside retry or timing text stay transient, a 429 or 5xx mark wins, HTTP 401 and insufficient credits stay permanent")
fn testSoleLaneBlocks -> Bool
  (let [(r (match (l/review (unit "low" false) "+ a\n- b" (goodGates) (pool)
                    (fn [(a String) (p String)] -> (Result String String)
                      (if (= a "ccKimi31Pro") (err "HTTP 401 unauthorized") (if (= a "orNemotronUltraFree") (ok (passReply)) (ok "")))))
             ((ok x) x)
             ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e))))
        (warns (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:laneUnavailable ")) r.rows))]
    (do (assert (= r.action "blocked") (str "blocked within one ruling: " r.action " " r.awaitLane " " r.why))
        (assert (stringContains? r.why "review: no live lane on tier strong (permanent: ccKimi31Pro 401)") (str "the sig names tier, alias and cause: " r.why))
        (assert (= (listLength warns) 1) (str "one warn row: " (stringJoin r.rows " | ")))
        (assert (stringStartsWith? (optionOr (listHead r.rows) "") "(:grade ") "the head row is the grade row")
        (assert (stringContains? (stringJoin r.rows " ") "(:escalate :unit U1") "an escalate row is emitted")
        (assert (and (l/permanentError? "HTTP 401") (l/permanentError? "http 400 insufficient credits") (l/permanentError? "401 unauthorized") (l/permanentError? "status 403") (l/permanentError? "HTTP 404 model not found")) "real statuses are permanent")
        (assert (not (l/permanentError? "429 retry after 403 s")) "retry text is transient")
        (assert (not (l/permanentError? "req-404-ab failed")) "an id is no status")
        (assert (not (l/permanentError? "timeout after 401 ms")) "timing text is transient")
        (assert (not (l/permanentError? "HTTP 503 upstream said 401")) "a 5xx mark wins")
        (assert (not (l/permanentError? "http 429 rate limited")) "429 is transient")
        (assert (not (l/permanentError? "HTTP 403 forbidden, 429 rate limited, retry later")) "a message that also carries a transient mark is transient")
        true))

fn testBlocked -> Bool
  (let [(r (run (unit "low" false) (goodGates) (pool)
             (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" "garbled") (pair "ccKimi31Pro" "garbled"))))
        (row (optionOr (listHead (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:escalate")) r.rows)) ""))]
    (do (assert (= r.action "blocked") "an R3 split is blocked for Claude")
        (assert (= r.rung "R3") "blocked at R3")
        (assert (stringStartsWith? row "(:escalate :unit U1") "an escalate row is emitted")
        (assert (stringContains? row ":disagree") "the escalate row names the disagreement")
        (assert (and (stringContains? row "orNemotronUltraFree pass") (stringContains? row "ocLongcat fail")) "the disagreement names both reviewers' verdicts")
        (assert (stringContains? row ":seen") "the escalate row names what was seen")
        (assert (and (stringContains? row " :need tiebreak :usedModels (") (stringContains? row "ocLongcat")) (str "a split at the last rung asks for a tiebreak and names the models used: " row))
        (assert (stringContains? r.why "tiebreak: reviewers split at the last rung (pass 1 fail 1)") (str "the blocked reason says so: " r.why))
        (assert (and (stringContains? row ":to queue ") (not (stringContains? row ":to claude")) (stringContains? row ":tiers (claude)")) (str "the escalation goes to the queue with Claude as the last tier once the strong lane has been asked: " row))
        true))

; (:m :ref REVIEW-DIFF-INCOMPLETE :do "node2 2026-11-11: reviewers failed STD-DOTENV, STD-SEMVER and THROUGHPUT-DAILY for a missing test file and bodiless functions while their gates were green, because the brief kept only the first 60 diff lines; a 90-line diff reaches the reviewer whole, and a diff past the cap says how much was cut")
fn testBriefWholeDiff -> Bool
  (let [(u (l/ReviewUnit :id "U2" :task "t" :risk "low" :closureChanged false :writerAlias "x" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list)))
        (lines (fn [(n Int64)] -> String (stringJoin (map (fn [(i Int64)] -> String (str "+ line " (stringFromInt64 i))) (range 0 n)) "\n")))
        (b90 (l/reviewBrief u (lines 90) ""))
        (bBig (l/reviewBrief u (lines 5000) ""))]
    (do (assert (stringContains? b90 "+ line 89") "the last line of a 90-line diff reaches the reviewer")
        (refute (stringContains? b90 "diff clipped") "a diff under the cap carries no clip note")
        (assert (stringContains? bBig "diff clipped") "a diff past the cap says it was clipped")
        true))

; (:m :ref REVIEW-SCRUB-SILENT :do "a code line naming tokens is withheld with a marker in its place, never dropped silently")
fn testBriefWithheldMarker -> Bool
  (let [(u (l/ReviewUnit :id "U3" :task "t" :risk "low" :closureChanged false :writerAlias "x" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list)))
        (b (l/reviewBrief u "+ (list (+ a 1)\n+       (+ b r.inTokens)\n+       (+ c 2))" ""))]
    (do (assert (stringContains? b "line withheld by the secret filter") (str "a filtered line leaves a marker: " b))
        (refute (stringContains? b "inTokens") "the filtered line itself does not go out")
        (assert (stringContains? b "(+ c 2)") "the lines around it are kept")
        true))

fn testBrief -> Bool
  (let [(u (l/ReviewUnit :id "U1" :task "fix bound\nsee .asl/mem/plan.asn\nkey sk-or-abc123" :risk "low" :closureChanged false :writerAlias "x" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list)))
        (b (l/reviewBrief u "+ ok line\n+ TOKEN=abc\n+ path .asl/mem/x\n- gone" "(:receipt U1 :gates ())"))]
    (do (assert (stringContains? b "fix bound") "unit text is kept")
        (assert (stringContains? b "+ ok line") "diff excerpt is kept")
        (assert (not (stringContains? b ".asl/mem")) "no memory path or contents go out")
        (assert (not (stringContains? b "sk-or-")) "no key-looking text goes out")
        (assert (not (stringContains? b "TOKEN=")) "no token line goes out")
        (assert (listContains? (l/scrubLines "+ (let [toks (tokenize text)]" 10 120) "+ (let [toks (tokenize text)]") "tokenize identifier is not scrubbed as a secret")
        (assert (listEmpty? (l/scrubLines "+ (:token \"abc123\")" 10 120)) "an ASN :token row is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ \"token\": \"abc123\"" 10 120)) "a JSON token field is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ secret = \"hunter2\"" 10 120)) "a spaced secret assignment is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ (:secret \"xyz\")" 10 120)) "an ASN :secret row is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ accessToken = abc" 10 120)) "a camelCase token name is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ Authorization: Bearer xyz" 10 120)) "a bearer header is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ (:key \"sk-3f9a0c1d2e\")" 10 120)) "a plain sk- key in quotes is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ DEEPSEEK=sk-3f9a0c1d2e" 10 120)) "a plain sk- key after = is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ (:g \"AIzaSyA1b2C3d4\")" 10 120)) "a Google API key is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ github_pat_11ABCD" 10 120)) "a GitHub fine-grained token is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ xoxp-1234-abcd" 10 120)) "a Slack user token is scrubbed")
        (assert (listEmpty? (l/scrubLines "+ db passwd=hunter2" 10 120)) "a passwd assignment is scrubbed")
        (assert (listContains? (l/scrubLines "+ (fn [task-id] (run task-id))" 10 120) "+ (fn [task-id] (run task-id))") "task- is not mistaken for an sk- key")
        (assert (= (l/scrubLines "+ ok1\n+ -----BEGIN OPENSSH PRIVATE KEY-----\n+ b3BlbnNzaC1rZXktdjEAAAAABG5vbmU\n+ AAAAC3NzaC1lZDI1NTE5AAAAIOx\n+ -----END OPENSSH PRIVATE KEY-----\n+ ok2" 10 120) (list "+ ok1" "+ ok2")) "a PEM block is dropped whole, body lines included")
        (assert (listEmpty? (l/scrubLines (str "+ x sk-" "abcdefghijklmnopqrstuvwx y") 10 120)) "every egress shape is scrubbed by the ladder too")
        (assert (not (stringContains? b "\n")) "the brief is a single line")
        (assert (stringStartsWith? b "(:review :unit \"U1\"") "the brief is an ASN form")
        true))

fn gatewayAliases -> (List String)
  (stringSplit (stringJoin (list "flashLow flashHigh flashMedium opus astra agyOpus geminiApiFlash geminiApiFlashLite lagunaS ocGlmFlash"
    "ocMimoFlash ocDeepseekFlash ocKimi31Pro ccKimi31Pro orKimi31Pro vcKimi31Pro vcNemotronLightningFree"
    "vcLagunaFree vcBeamFree orNemotronUltraFree orNemotronSuperFree orGemma431Free ocMuse ocLongcat ocCatJam"
    "ocDeepseekPro ocGlm53 ocMinimaxM3 ccDeepseekFlash ccGlmFlash ccLingFlash ccLaguna ccMimoPro ccBeam ocBeam"
    "ccMinimaxFlash ccGlyph orLaguna orNorthCode orMinimaxFlash orNemotronLightning orNemotronSuperVl orDots3"
    "nimNemotronUltra nimNemotronLightning nimGlm53 nimGlm53Flash orNemotronUltra groqQwen mimoPro mimoFlash"
    "groqGptOss tgGlm53Flash tgBonsai ifmK2Horizon orDsFlash0731 orDs41Flash"
    "orNvidiaNemotron3NanoOmni30bA3bReasoningFree orOpenrouterFree orRecursiveFlintV10Free gmGemini3FlashPreview"
    "gmGemini31FlashLite gmGemini31FlashLitePreview gmGemini35Flash gmGemini36Flash gmGeminiFlashLiteLatest"
    "gmGemma426bA4bIt nimNvidiaNemotron3NanoOmni30bA3bReasoning nimNvidiaNemotron35BoltE4b"
    "nimNvidiaNemotron35SuperVl120bA12b nimOpenaiGptOss20b vcReflectionBeam ocClaudeHaiku55 ocGemini4Argon ocGlm51"
    "ocGlm52 ocGpt56Luna ocGpt6Luna ocGrok46 ocGrok47 ocHy3 ocHy4Preview ocIcemanContributorFree ocLongcat20"
    "ocMimoV25 ocMimoV26Pro ocMinimaxM25 ocMinimaxM27 ocMinimaxM31Flash ocMuseSpark12Contributor ocOmenAlpha"
    "ocQwen36Plus ocQwen37Max ocQwen37Plus ocQwen38Flash ocQwen38Max ocStep5Preview ccDeepseekDeepseekV4Flash"
    "ccDeepseekDeepseekV4FlashFast ccDeepseekDeepseekV4FlashVisionExp ccDeepseekDeepseekV4Pro"
    "ccDeepseekDeepseekV41FlashFast ccGoogleGemini37Flash ccGoogleGemini38Flash ccGpt56Luna ccGpt56Sol ccGpt6Luna"
    "ccMeituanLongcat20 ccMetaMuseSpark12 ccMetaMuseSpark12Contributor ccMetaMuseSpark13"
    "ccMetaMuseSpark13Contributor ccMetaMuseSparkOpen ccMinimaxMinimaxM31Flash ccMinimaxaiMinimaxM25"
    "ccMinimaxaiMinimaxM3 ccMistralMistralLarge4 ccMoonshotaiKimiK25 ccMoonshotaiKimiK26 ccMoonshotaiKimiK27Code"
    "ccMoonshotaiKimiK27CodeHighspeed ccMoonshotaiKimiK3 ccNvidiaNemotron3Ultra550bA55b ccNvidiaNemotron35SuperVl"
    "ccOrnithOrnith15122b ccQwenQwen36Plus ccQwenQwen37Flash ccQwenQwen37Max ccQwenQwen37Plus ccQwenQwen3827b"
    "ccQwenQwen38Flash ccQwenQwen38Max ccQwenQwen38Max0902 ccQwenQwen38MaxPrime ccQwenQwen38OmniFlash"
    "ccStepfunStep37Flash ccStepfunStep5Preview ccTencentHy4Preview ccXaiGrok45 ccXaiGrok46 ccXaiGrok47"
    "ccXiaomiMimoV26Flash ccXiaomiMimoV26ProUltraspeed ccZAiGlm53Flashx ccZaiOrgGlm5 ccZaiOrgGlm52"
    "ccZaiOrgGlm52Fast ccZaiOrgGlm53 ifmIfmJais3Mova36bA4b olBeam olGemma431b olGptOss120b olGptOss20b"
    "olNemotron3Nano30b olNemotron3Super olNemotron3Ultra") " ") " ")

fn unknownAliases -> (List String)
  (list "ocCatJam" "ocIcemanContributorFree" "ocOmenAlpha" "ccGlyph" "ccOrnithOrnith15122b" "orOpenrouterFree" "orRecursiveFlintV10Free" "orDots3")

fn testTokens -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))]
    (do (assert (= (l/tokensOf "ocDeepseekFlash") (list "oc" "deepseek" "flash")) "camelCase splits")
        (assert (= (l/tokensOf "claude-opus-5-5") (list "claude" "opus" "5" "5")) "separators and digits split")
        (assert (= (l/tokensOf "orDsFlash0731") (list "or" "ds" "flash" "0731")) "letter digit boundary splits")
        (assert (= (l/tokensOf "ccNvidiaNemotron35SuperVl") (list "cc" "nvidia" "nemotron" "35" "super" "vl")) "short acronym is one token")
        (assert (= (l/familyIn rs "ocWordsX") "") "ds inside words is not deepseek")
        (assert (= (l/familyIn rs "ocBeamer") "") "beam inside beamer is not reflection")
        (assert (= (l/familyIn rs "ocDarling") "") "ling inside darling is not inclusionai")
        (assert (= (l/familyIn rs "ocLing") "inclusionai") "ling as a whole token is")
        (assert (= (l/familyIn rs "ocGlmDeepseek") "") "two families make an alias unknown")
        (assert (= (l/familyIn rs "ocGpt6Luna") "openai") "two rows of one family resolve")
        true))

fn testCoverage -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))
        (all (l/coverageProblems rs (gatewayAliases) (unknownAliases)))]
    (do (assert (> (listLength (gatewayAliases)) 100) "the fixture holds the gateway alias list")
        (assert (listEmpty? all) (str "every gateway alias resolves to one family or is listed unknown: " (stringJoin all "; ")))
        (assert (not (listEmpty? (l/coverageProblems rs (list "ocMysteryModel") (list)))) "an unlisted unknown alias is a problem")
        (assert (not (listEmpty? (l/coverageProblems rs (list "ocGlmDeepseek") (list "ocGlmDeepseek")))) "an ambiguous alias is a problem even when listed")
        (assert (not (listEmpty? (l/coverageProblems rs (list "ocGlm53") (list "ocGlm53")))) "a stale unknown entry is a problem")
        true))

fn testRank -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))
        (ls (list (l/Lane :alias "ocLongcat" :tier "free" :allowance 5 :quality 0)
                  (l/Lane :alias "orNemotronUltraFree" :tier "free" :allowance 5 :quality 7)
                  (l/Lane :alias "orGemma431Free" :tier "free" :allowance 5 :quality 9)
                  (l/Lane :alias "groqQwen" :tier "free" :allowance 5 :quality 7)))]
    (do (assert (= (map (fn [(x l/Lane)] -> String x.alias) (l/rankLanes ls)) (list "orGemma431Free" "orNemotronUltraFree" "groqQwen" "ocLongcat")) "higher quality first, ties keep caller order")
        (match (l/selectFree rs "flashHigh" ls)
          ((l/pickOk ps) (assert (= (map (fn [(x l/Lane)] -> String x.alias) ps) (list "orNemotronUltraFree" "groqQwen")) "R1 takes the best non-writer-family reviewers (gemma is the writer's family)"))
          ((l/pickAwait a w) (assert false "R1 should pick")))
        (match (l/selectFree rs "ocDeepseekFlash" ls)
          ((l/pickOk ps) (assert (= (map (fn [(x l/Lane)] -> String x.alias) ps) (list "orGemma431Free" "orNemotronUltraFree")) "R1 takes the two best quality lanes of different families"))
          ((l/pickAwait a w) (assert false "R1 should pick")))
        true))

; (:m :ref REVIEW-DEFER :do "a paid rung with no lane falls through to the strong rung instead of parking: high risk with paid allowance 0 and a strong lane merges on one R3 pass; with no strong lane either the R2 await stands on its paid lane and its row names both rungs")
fn testFallThrough -> Bool
  (let [(open (run (unit "high" false) (goodGates) (list (lane "ocDeepseekFlash" "paid" 0) (lane "ccKimi31Pro" "strong" 5)) (list (pair "ccKimi31Pro" (passReply)))))
        (shut (run (unit "high" false) (goodGates) (list (lane "ocDeepseekFlash" "paid" 0) (lane "ccKimi31Pro" "strong" 0)) (list)))
        (row (optionOr (listHead shut.rows) ""))]
    (do (assert (= (rungs open) (list "R3")) (str "the strong rung is asked when the paid rung has no lane: " (stringJoin (rungs open) ",")))
        (assert (= open.action "merge") (str "and its pass merges: " open.action))
        (assert (and (= shut.action "await") (and (= shut.rung "R2") (= shut.awaitLane "ocDeepseekFlash ccKimi31Pro"))) (str "no strong lane either: the R2 await stands on the paid and the strong lane: " shut.rung " " shut.awaitLane))
        (assert (stringStartsWith? row "(:await :unit U1 :rung R2 :lane \"ocDeepseekFlash ccKimi31Pro\" :why ") (str "the await is a journal row: " row))
        (assert (and (stringContains? row "no paid lane") (stringContains? row "R3: no strong lane")) (str "naming both rungs: " row))
        true))

fn ! runTests -> Bool
  (do (assert (testFamilies) "families")
      (assert (testTokens) "tokens")
      (assert (testCoverage) "coverage")
      (assert (testRank) "rank")
      (assert (testSelect) "selection")
      (assert (testVerdicts) "verdict parsing")
      (assert (testMerge) "merge rules")
      (assert (testSplitAndAbstain) "split and abstain")
      (assert (testAbsentQuorum) "absent reviewers are not votes")
      (assert (testFixCap) "fix cap")
      (assert (testRisk) "risk and closure")
      (assert (testAwait) "await")
      (assert (testFallThrough) "paid falls through to strong")
      (assert (testAbsenceKinds) "only absence defers")
      (assert (testPermanentLane) "permanent lane errors skip the lane")
      (assert (testSoleLaneBlocks) "a sole lane that dies blocks visibly, statuses are real statuses")
      (assert (testBlocked) "blocked")
      (assert (testBrief) "brief")
      (assert (testBriefWholeDiff) "whole diff reaches the reviewer")
      (assert (testBriefWithheldMarker) "a withheld diff line leaves a marker")
      true)
