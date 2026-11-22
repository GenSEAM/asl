(module asl-tools/coord/tests/mergeBisectTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-SOLO-BISECT :do "bisection by the real batchVerdicts: a red no branch carries splits the unmerged members in halves, a half of one is solo, a larger one carries its own await tag; the fixture runs trains until nothing is left and counts them")
fn mixedRed bs: (List String) -> String
  (str "(:train :head \"abc\" :merged \"def\" :branches () :changed 2 :selected 2 :cached 0 :ran 2 :green 1 :invariants 0 :red (\"x.asl\" \"" (stringJoin bs "+") "\" 1 1 :kind suite :why interaction) :preexisting () :assertLoss () :baseKnown 0 :knownRed () :blocked (:fresh 1 :preexisting 0) :seconds 9)")

; (:m :do "one train on a group: green when the culprit is absent, else the batch red of a combination (a lone culprit is its own red); returns trains used, merged branches and the next groups")
fn trainOn g: (List String) culprit: String -> (Pair (List String) (List (List String)))
  (if (not (listContains? g culprit)) (pair g (list))
    (if (= (listLength g) 1) (pair (list) (list))
      (let [(vs (cd/batchVerdicts g 1 (mixedRed g) (list)))
            (tags (fold (fn [(a (List String)) (t String)] -> (List String) (if (listContains? a t) a (listAppend a (list t)))) (list) vs))]
        (pair (list) (listAppend (map (fn [(t String)] -> (List String) (map pairFirst (filter (fn [(p (Pair String String))] -> Bool (= (pairSecond p) t)) (cd/zipPairs g vs)))) (filter (fn [(t String)] -> Bool (!= t "solo")) tags)) (map (fn [(p (Pair String String))] -> (List String) (list (pairFirst p))) (filter (fn [(p (Pair String String))] -> Bool (= (pairSecond p) "solo")) (cd/zipPairs g vs))))))))

; (:m :do "trains to drain k branches with one culprit, counting the first red batch train")
fn drain groups: (List (List String)) culprit: String trains: Int64 merged: Int64 -> (Pair Int64 Int64)
  (match (listHead groups)
    ((none) (pair trains merged))
    ((some g) (let [(r (trainOn g culprit))]
                (drain (listAppend (listDrop groups 1) (pairSecond r)) culprit (+ trains 1) (+ merged (listLength (pairFirst r)))))))

fn ! testHalves -> Bool
  (let [(six (list "sh/A" "sh/B" "sh/C" "sh/D" "sh/E" "sh/F"))
        (v (cd/batchVerdicts six 1 (mixedRed six) (list)))
        (two (cd/batchVerdicts (list "sh/A" "sh/B") 1 (mixedRed (list "sh/A" "sh/B")) (list)))
        (landed (cd/batchVerdicts (list "sh/A" "sh/B" "sh/C") 124 "(:fleetRun :verdict :timeout :timeoutMs 3600000)" (list "sh/A")))
        (results (map (fn [(c String)] -> (Pair Int64 Int64) (drain (list six) c 0 0)) six))
        (worst (fold (fn [(a Int64) (r (Pair Int64 Int64))] -> Int64 (max a (pairFirst r))) 0 results))]
    (do (assert (= v (list "bisect:sh/A/3" "bisect:sh/A/3" "bisect:sh/A/3" "bisect:sh/D/3" "bisect:sh/D/3" "bisect:sh/D/3")) (str "six members with an unattributed red become two groups of three: " (stringJoin v ",")))
        (assert (= two (list "solo" "solo")) (str "a pair splits into two solo members: " (stringJoin two ",")))
        (assert (= landed (list "merged" "solo" "solo")) (str "a member landed before a kill is merged, the rest split: " (stringJoin landed ",")))
        (assert (= (map pairSecond results) (list 5 5 5 5 5 5)) "every non-culprit unit merges whichever one is the culprit")
        (assert (<= worst 7) (str "six units with one culprit drain in at most 1 + 2*ceil(log2 6) = 7 trains counting the red batch train, as many as all-solo takes in the worst position and 5 in the best: worst " (stringFromInt64 worst) " per culprit " (stringJoin (map (fn [(r (Pair Int64 Int64))] -> String (stringFromInt64 (pairFirst r))) results) ",")))
        (assert (= (pairFirst (drain (list (list "sh/A" "sh/B" "sh/C") (list "sh/D" "sh/E" "sh/F")) "none" 1 0)) 3) "a red no unit carries (a kill, a flake) drains six units in 3 trains, all-solo takes 7")
        (assert (cd/batchable? (with (pf/cuIn "G" "merging" "" "sh/G") :await "bisect:sh/A/3")) "a member of a bisect group may ride with its group")
        (assert (and (cd/heldAwait? "solo") (cd/retryVerdict? "bisect:sh/A/3") (not (cd/heldAwait? "baseRed:x y"))) "tags are retries and held marks, a base hold is neither")
        (assert (testConvert (str (pf/scratch "mergeBisect" "w") "/conv")) "legacy solo units convert once to one bisect group")
        true))

; (:m :do "soloConvert!: three legacy solo units become one bisect:legacy/3 group, a launched one and a lone remainder stay, and a second call converts nothing")
fn ! testConvert dir: String -> Bool
  (let [(_ (pf/cleanup dir))
        (_ (dirCreate dir))
        (_ (dirCreate (cd/cuDir dir)))
        (mk (fn [(id String) (await String) (launched Int64)] -> Bool (ok? (cd/writeCUnit! dir (with (pf/cuIn id "merging" "" (str "sh/" id)) :await await :launched launched)))))
        (_ (list (mk "S01" "solo" 0) (mk "S02" "solo" 0) (mk "S03" "solo" 0) (mk "S04" "solo" 0) (mk "S05" "solo" 0) (mk "S06" "solo" 0) (mk "S07" "solo" 0) (mk "S08" "solo" 0) (mk "S09" "solo" 0) (mk "L1" "solo" 1) (mk "P1" "" 0)))
        (_ (fileWrite (str dir "/ladder.asn") "(:train :batch 4)\n"))
        (n1 (cd/soloConvert! dir))
        (cus (cd/readCUnits! dir))
        (aw (fn [(id String)] -> String (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) cus) (pf/cuIn id "gone" "" "")).await))
        (_ (cd/writeCUnit! dir (with (pf/cuIn "S10" "merging" "" "sh/S10") :await "solo")))
        (n2 (cd/soloConvert! dir))
        (_ (pf/cleanup dir))]
    (do (assert (= n1 2) (str "nine solo units at batch 4 make groups 4+4+1, two real groups: " (stringFromInt64 n1)))
        (assert (and (= (aw "S01") "bisect:legacy0/4") (= (aw "S04") "bisect:legacy0/4") (= (aw "S05") "bisect:legacy1/4") (= (aw "S08") "bisect:legacy1/4")) "groups of at most the batch size, in order")
        (assert (= (aw "S09") "solo") "the group of one stays solo")
        (assert (and (= (aw "L1") "solo") (= (aw "P1") "")) "a launched solo unit and a plain unit keep their await")
        (assert (= n2 0) "the second call converts nothing")
        true))

; (:m :ref MERGE-SOLO-BISECT :do "a kill by one hung member of four: the owner of the suite still running goes solo and the other three return to the batch; one more train merges the three and the hung one's own solo train is its second kill, where it parks")
fn ! testHung -> Bool
  (let [(bs (list "sh/A" "sh/B" "sh/C" "sh/D"))
        (owners (map (fn [(b String)] -> (Pair String (List String)) (pair b (list (str "asl/packages/p" (stringReplace b "sh/" "") "/src/x.asl") (str "asl/packages/p" (stringReplace b "sh/" "") "/tests/xTest.asl")))) bs))
        (out "(:trainRunning :items (\"asl/packages/pB/tests/xTest.asl\" \"asl/packages/pA/tests/xTest.asl\"))\n(:itemDone \"asl/packages/pA/tests/xTest.asl\" 0)\n(:fleetRun :verdict :timeout :timeoutMs 3600000)")
        (v (cd/batchVerdictsOwned bs 124 out (list) owners))
        (none (cd/batchVerdictsOwned bs 124 "(:fleetRun :verdict :timeout :timeoutMs 3600000)" (list) owners))
        (foreign (cd/batchVerdictsOwned bs 124 "(:trainRunning :items (\"elsewhere/zTest.asl\"))\n(:fleetRun :verdict :timeout :timeoutMs 3600000)" (list) owners))
        (rest (list "sh/A" "sh/C" "sh/D"))
        (green (cd/batchVerdictsOwned rest 0 "" rest owners))]
    (do (assert (= v (list "rebatch" "solo" "rebatch" "rebatch")) (str "the owner of the running suite is solo, the others return to the batch: " (stringJoin v ",")))
        (assert (= none (list "solo" "solo" "solo" "solo")) (str "a kill with nothing running sends everyone solo: " (stringJoin none ",")))
        (assert (= foreign (list "solo" "solo" "solo" "solo")) "a running suite no member owns sends everyone solo")
        (assert (= green (list "merged" "merged" "merged")) "the three innocents merge in the one train after the kill")
        true))

; (:m :ref MERGE-SOLO-BISECT :do "with no batch size the solo units stay and no marker is written, so a later ladder row still converts them; a new group index starts past the highest legacy index already in the store")
fn ! testConvertEdge dir: String -> Bool
  (let [(_ (pf/cleanup dir))
        (_ (dirCreate dir))
        (_ (dirCreate (cd/cuDir dir)))
        (mk (fn [(id String) (await String)] -> Bool (ok? (cd/writeCUnit! dir (with (pf/cuIn id "merging" "" (str "sh/" id)) :await await)))))
        (_ (list (mk "E1" "solo") (mk "E2" "solo") (mk "E0" "bisect:legacy3/2")))
        (n0 (cd/soloConvert! dir))
        (markerA (fileExists? (str dir "/bisectConverted")))
        (_ (fileWrite (str dir "/ladder.asn") "(:train :batch 4)\n"))
        (n1 (cd/soloConvert! dir))
        (cus (cd/readCUnits! dir))
        (aw (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id "E1")) cus) (pf/cuIn "E1" "gone" "" "")).await)
        (_ (pf/cleanup dir))]
    (do (assert (and (= n0 0) (not markerA)) "no batch size: nothing converts and no marker")
        (assert (= n1 1) "a later ladder row converts them")
        (assert (= aw "bisect:legacy4/2") (str "the new index starts past the highest existing one: " aw))
        true))

fn ! runTests -> Bool
  (and (testHalves) (and (testHung) (testConvertEdge (str (pf/scratch "mergeBisect" "w") "/edge"))))
