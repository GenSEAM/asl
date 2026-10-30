(module asl/tools/coord/tests/gradeTest
  :x [runTests]
  :i [(asl-tools/coord/grade :a g) (tools/fleet/model :a fm)])

fn agyFlash -> g/Candidate
  (g/Candidate :channel "agy" :model "gemini-3.8-flash-high" :available true)

fn leonFlash -> g/Candidate
  (g/Candidate :channel "leon" :model "gemini-3.8-flash" :available true)

fn claudeOpus avail: Bool -> g/Candidate
  (g/Candidate :channel "claude" :model "claude-opus-5-5" :available avail)

fn codexLuna -> g/Candidate
  (g/Candidate :channel "codex" :model "gpt-6-luna" :available true)

fn flashWriter -> g/Writer
  (g/Writer :unit "U1" :channel "agy" :model "gemini-3.8-flash-high")

fn pickedChannel r: (Result g/Candidate String) -> String
  (match r ((ok c) c.channel) ((err _) ""))

fn errText r: (Result g/Candidate String) -> String
  (match r ((err e) e) ((ok c) ""))

fn testFamilies -> Bool
  (do (assert (= (g/familyOf "gemini-3.8-flash-high") (g/familyOf "gemini-3.8-flash")) "flash variants share a family")
      (assert (!= (g/familyOf "gemini-3.8-flash") (g/familyOf "claude-opus-5-5")) "gemini and claude differ")
      (assert (= (g/familyOf "") "") "an empty model has no family")
      true)

fn testPick -> Bool
  (let [(w (flashWriter))
        (all (list (agyFlash) (leonFlash) (claudeOpus false) (codexLuna)))]
    (do (assert (= (pickedChannel (g/pickGrader w all)) "codex") "agy/flash writer: the other-channel other-family available candidate is picked")
        (assert (= (pickedChannel (g/pickGrader w (list (agyFlash) (leonFlash)))) "") "agy/flash writer never gets an agy/flash grader")
        (assert (stringContains? (errText (g/pickGrader w (list (leonFlash)))) "same model family") "flash through another channel is refused for family")
        (assert (stringContains? (errText (g/pickGrader w (list (claudeOpus false)))) "unavailable") "an unavailable candidate is refused")
        (assert (= (pickedChannel (g/pickGrader w (list (claudeOpus true) (codexLuna)))) "claude") "candidate order is the caller's preference")
        (assert (stringContains? (errText (g/pickGrader (g/Writer :unit "U" :channel "claude" :model "claude-sonnet-5-5") (list (claudeOpus true)))) "same channel") "a claude writer never gets a claude grader")
        (assert (stringContains? (errText (g/pickGrader (g/Writer :unit "U" :channel "x" :model "") all)) "unknown model family") "a writer of unknown family cannot be separated")
        true))

fn goodReceipt -> String
  (str "(:receipt U1 :head \"abc\" :owns (\"asl/tools/coord/grade.asl\")"
       " :gates ((:gate gradeTest :kind correctness :exit 0 :executed 12 :new true))"
       " :redBefore ((:gate gradeTest :exit 1 :executed 0)))")

fn neverRanReceipt -> String
  (str "(:receipt U1 :head \"abc\" :owns (\"asl/tools/coord/grade.asl\")"
       " :gates ((:gate gradeTest :kind correctness :new true))"
       " :redBefore ((:gate gradeTest :exit 1 :executed 0)))")

fn noRedReceipt -> String
  (str "(:receipt U1 :head \"abc\" :owns (\"asl/tools/coord/grade.asl\")"
       " :gates ((:gate gradeTest :kind correctness :exit 0 :executed 12)))")

fn suiteSrc cond: String -> String
  (str "(module fx/t :x [runTests] :i [])\n\nfn runTests -> Bool\n  (do (assert " cond " \"c\") true)\n")

fn cleanSources -> (List g/Source)
  (list (g/Source :path "a.asl" :text (suiteSrc "(= (stringLength \"ab\") 2)")))

fn constSources -> (List g/Source)
  (list (g/Source :path "b.asl" :text (suiteSrc "true")))

fn refusedRow p: g/Plan -> String
  (match p ((g/planRefused r _) r) ((g/planGo _) ""))

fn refusedProblems p: g/Plan -> String
  (match p ((g/planRefused _ ps) (stringJoin ps "; ")) ((g/planGo _) ""))

fn goChannel p: g/Plan -> String
  (match p ((g/planGo c) c.channel) ((g/planRefused _ _) ""))

fn ! testPlan -> Bool
  (match (fm/loadText (resultOr (fileReadString (fm/fleetPath)) ""))
    ((err e) (do (assert false (str "fleet.asn loads: " e)) false))
    ((ok fleet)
      (let [(w (flashWriter))
            (all (list (agyFlash) (leonFlash) (codexLuna)))
            (go (g/plan w fleet (goodReceipt) (cleanSources) all))
            (ran (g/plan w fleet (neverRanReceipt) (cleanSources) all))
            (noRed (g/plan w fleet (noRedReceipt) (cleanSources) all))
            (junk (g/plan w fleet "(:receipt U1" (cleanSources) all))
            (konst (g/plan w fleet (goodReceipt) (constSources) all))
            (noGrader (g/plan w fleet (goodReceipt) (cleanSources) (list (agyFlash) (leonFlash))))]
        (do (assert (= (goChannel go) "codex") "a good receipt and clean gates go to the codex grader")
            (assert (stringContains? (refusedProblems ran) "never ran") "a gate that never ran is refused")
            (assert (stringContains? (refusedRow ran) "refused before any model call") "refusal row says no model call was made")
            (assert (stringContains? (refusedRow ran) ":verdict reject") "refusal is a reject grade")
            (assert (stringContains? (refusedProblems noRed) "no redBefore receipt") "a receipt without a redBefore receipt is refused")
            (assert (stringContains? (refusedProblems junk) "does not parse") "a receipt that does not parse is refused")
            (assert (stringContains? (refusedProblems konst) "constant gate assertion") "a constant gate assertion is refused")
            (assert (= (goChannel konst) "") "constant gate does not reach a grader")
            (assert (stringContains? (refusedRow noGrader) ":verdict pending") "no eligible grader leaves the unit pending")
            (assert (listEmpty? (g/statsProblems (refusedRow ran))) "a refusal row parses in the workerStats shape")
            true))))

fn testRows -> Bool
  (let [(run (g/runRow "U1" "agy" "gemini-3.8-flash-high" "done" "pending" 2 0 17 "a note with \"quotes\""))
        (grade (g/gradeRow "U1" "codex" "gpt-6-luna" "agy" "acceptWithFixes" "fix: bound"))
        (real "(:run :unit H1b :worker agy :model gemini-3.8-flash-high :start \"22:55\" :end \"23:12\" :wallMin 17 :commits 1 :exit 0 :outcome done :grade acceptWithFixes :note \"continuation run\")")]
    (do (assert (listEmpty? (g/statsProblems run)) (str "run row parses: " run))
        (assert (listEmpty? (g/statsProblems grade)) (str "grade row parses: " grade))
        (assert (listEmpty? (g/statsProblems real)) "a real workerStats row passes the same check")
        (assert (stringStartsWith? run "(:run :unit U1 :worker agy :model \"gemini-3.8-flash-high\"") "run row key order follows workerStats")
        (assert (not (listEmpty? (g/statsProblems "(:run :unit U1 :worker agy :model m :outcome weird)"))) "an unknown outcome is a problem")
        (assert (not (listEmpty? (g/statsProblems "(:grade :unit U1 :worker codex :model m :writer agy)"))) "a grade row without a verdict is a problem")
        (assert (not (listEmpty? (g/statsProblems "(:run :unit"))) "an unparsable row is a problem")
        (assert (stringContains? (g/runRow "a b" "agy" "m" "done" "pending" -1 -1 -1 "") ":unit \"a b\"") "an unsafe atom is quoted")
        true))

fn ! runTests -> Bool
  (do (assert (testFamilies) "families")
      (assert (testPick) "grader pick")
      (assert (testPlan) "pre-checks and plan")
      (assert (testRows) "rows")
      true)
