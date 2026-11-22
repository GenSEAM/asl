(module asl-tools/coord/tests/reviewRepeatTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf) (asl-tools/vcs/vcs :a v)])

; (:m :ref COND-REDBEFORE-REVIEW-LOOP :do "two review refusals for the same reason in a row, here a fail and then a block that both say the gates are not proven red-before, park the unit blocked with await witness, one (:witness) journal row and an escalate row for claude only, and offerStrong! does not take it back; two different reasons keep the old path, a block with strong tiers that offerStrong! offers; a pass clears the count")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "reviewRepeatTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn resOf verdict: String sig: String tiers: String -> cd/Res
  (cd/Res :tiers tiers :ok 0 :wt "" :branch "" :model "m" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 0 :asserts 0 :verdict verdict)

fn ! cuOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (pf/cuIn id "gone" "" ""))

fn ! reviewing! dir: String id: String -> cd/CUnit
  (let [(epoch (match (st/claim! dir id "reviewRepeatTest" 600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0)))
        (c (with (pf/cuIn id "reviewing" "" (str "sh/" id)) :epoch epoch :launched 1))
        (_ (cd/writeCUnit! dir c))]
    c)

fn ! round! ctx: cd/Ctx u: st/Task v: String sig: String tiers: String -> cd/CUnit
  (let [(c (reviewing! ctx.dir u.id))
        (_ (cd/finish! ctx u c (resOf v sig tiers)))]
    (cuOf ctx.dir u.id))

fn ! count text: String needle: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l needle)) (stringLines text)))

fn ! runTests -> Bool
  (let [(root (pf/scratch "reviewRepeat" "w"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (ctx (ctxOf store))
        (ua (pf/unitIn "A1" "true"))
        (ub (pf/unitIn "B1" "true"))
        (uc (pf/unitIn "C1" "true"))
        (_ (st/put! store ua))
        (_ (st/put! store ub))
        (_ (st/put! store uc))
        (ud (pf/unitIn "D1" "true"))
        (ue (pf/unitIn "E1" "true"))
        (ug (pf/unitIn "G1" "true"))
        (_ (st/put! store ud))
        (_ (st/put! store ue))
        (wg (pf/seedUnit! root ug "reviewing" "impl.txt"))
        (a1 (round! ctx ua "fail" "gates not proven red-before with executed assertions" ""))
        (a2 (round! ctx ua "block" "gates not proven after a fix round" "strong"))
        (aWhy (fileExists? (cd/reviewWhyPath store "A1")))
        (offered (cd/offerStrong! ctx (fn [] -> (List (Pair String Int64)) (list (pair "strong" 5)))))
        (a3 (cuOf store "A1"))
        (b1 (round! ctx ub "fail" "reviewer asks for the missing bound check" ""))
        (b2 (round! ctx ub "block" "gates not proven after a fix round" "strong"))
        (offeredB (cd/offerStrong! ctx (fn [] -> (List (Pair String Int64)) (list (pair "strong" 5)))))
        (b3 (cuOf store "B1"))
        (c1 (round! ctx uc "fail" "gates not proven red-before with executed assertions" ""))
        (cWhy1 (resultOr (fileReadString (cd/reviewWhyPath store "C1")) ""))
        (c2 (round! ctx uc "pass" "" ""))
        (cWhy2 (fileExists? (cd/reviewWhyPath store "C1")))
        (d1 (round! ctx ud "fail" "ladder: gateway unreachable" ""))
        (d2 (round! ctx ud "fail" "ladder: gateway unreachable" ""))
        (e1 (round! ctx ue "fail" "test x not proven to cover the bound" ""))
        (e2 (round! ctx ue "block" "claim y not proven by the receipt" "strong"))
        (headG (cd/unitHead! store "G1"))
        (g1 (round! ctx ug "fail" "gates not proven red-before with executed assertions" ""))
        (_ (fileWrite (str wg "/fix.txt") "fix\n"))
        (moved (v/commit! wg wg (list "fix.txt") "(:c :a t :do \"fix\" :g none :ev (G1))" "warn"))
        (headG2 (cd/unitHead! store "G1"))
        (g2 (round! ctx ug "block" "gates not proven after a fix round" "strong"))
        (journal (resultOr (fileReadString (cd/journalPath store)) ""))
        (esc (resultOr (fileReadString (cd/escalationsPath store)) ""))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (and (not (stringEmpty? repo)) (= a1.st "ready")) (str "the first refusal is a fix round: " a1.st))
        (assert (and (= a2.st "blocked") (= a2.await "witness")) (str "the second one for the same reason blocks with a witness: " a2.st " " a2.await))
        (assert (= (count journal "(:witness :unit \"A1\" :stage review") 1) (str "one witness row for A1: " journal))
        (assert (not aWhy) "the witness clears the reason file")
        (assert (and (= offered 0) (= a3.st "blocked")) (str "offerStrong! leaves the witness block alone: " (stringFromInt64 offered) " " a3.st))
        (assert (and (stringContains? esc "(:escalate :unit \"A1\"") (stringContains? esc ":tiers (claude)")) (str "the escalate row is for claude: " esc))
        (assert (not (stringContains? (cd/lastTiers (stringLines esc) "A1") "strong")) "and offers no strong tier")
        (assert (and (= b1.st "ready") (= b2.st "blocked") (not (= b2.await "witness"))) (str "two different reasons keep the old block: " b2.st " " b2.await))
        (assert (and (= offeredB 0) (= b3.st "blocked")) (str "a block whose reason is gates not proven is a fact of the receipt, offerStrong! does not reopen it: " (stringFromInt64 offeredB) " " b3.st))
        (assert (and (= c1.st "ready") (stringContains? cWhy1 "gates not proven") (and (= c2.st "admitting") (not cWhy2))) (str "a pass clears the count and goes to admission (on by default): " c1.st " " c2.st))
        (assert (and (= d1.st "ready") (and (= d2.st "ready") (not (= d2.await "witness")))) (str "a ladder error twice is infrastructure, no witness: " d1.st " " d2.st " " d2.await))
        (assert (and (= e1.st "ready") (and (= e2.st "blocked") (not (= e2.await "witness")))) (str "two different not proven reasons are no witness: " e2.st " " e2.await))
        (assert (and (= moved.code 0) (and (!= headG headG2) (and (= g2.st "blocked") (= g2.await "witness")))) (str "two red-before refusals at different heads, a fix round between, are a witness: " (stringFromInt64 moved.code) " " g2.st " " g2.await))
        (assert (= (count journal "(:witness :unit \"D1\"") 0) "no witness row for the ladder errors")
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
