(module asl-tools/coord/tests/admissionTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-ADMISSION :do "the admission step between review pass and merging: a review pass moves the unit to admitting, not merging; a refused admission (a suite red only with the branch) goes back to the writer as a fix round whose brief carries the admission log tail and never reaches merging; an admission whose only red is red on the dev head too is admitted; a conflict goes back to the writer; two units admit at once while the one merge slot is busy; the (:admission ...) ladder row turns it off and bounds it")

fn refusedOut -> String
  "(:trainPhase :name \"prepare\" :ms 5)\n(:redLive \"a/tests/aTest.asl\" 1 1 :kind suite :err (\"ERR_ASSERT lib value is 3\"))\n(:admission :verdict refused :branch \"sh/R1\" :onto \"o\" :merged \"m\" :red ((\"a/tests/aTest.asl\" \"sh/R1\" 1 1 :kind suite :why only :err (\"ERR_ASSERT lib value is 3\"))) :assertLoss () :baseRed () :flaky () :unrun () :cached 0 :phasesMs (:rebase 5 :select 2) :suiteMs ((\"a/tests/aTest.asl\" 40)))"

fn baseRedOut -> String
  "(:admission :verdict admitted :branch \"sh/B1\" :onto \"o\" :merged \"m\" :red () :assertLoss () :baseRed (\"a/tests/aTest.asl\") :flaky () :unrun () :cached 0 :phasesMs (:rebase 5 :select 2) :suiteMs ((\"a/tests/aTest.asl\" 40)))"

fn conflictOut -> String
  "(:train :head \"o\" :branches (\"sh/C1\") :red () (:conflict :branch \"sh/C1\" :files (\"impl.txt\")))\n(:admission :verdict conflict :branch \"sh/C1\" :onto \"o\" :why \"(:conflict :branch \\\"sh/C1\\\" :files (\\\"impl.txt\\\"))\" :phasesMs (:rebase 7))"

fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "admissionTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuOf dir: String id: String -> (Option cd/CUnit)
  (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir))

fn ! stOf dir: String id: String -> String
  (match (cuOf dir id) ((some c) c.st) ((none) ""))

fn ! launchedOf dir: String id: String -> Int64
  (match (cuOf dir id) ((some c) c.launched) ((none) -1))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! storeOf root: String name: String ids: (List String) -> String
  (let [(dir (str root "/" name))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (_ (map (fn [(id String)] -> Bool (ok? (st/put! dir (pf/unitIn id "true")))) ids))]
    dir)

fn unitAt id: String stateName: String -> cd/CUnit
  (pf/cuIn id stateName "" (str "sh/" id))

fn testRows -> Bool
  (do (assert (listEmpty? (cd/admissionErrors "(:admission :on true :jobs 4 :limitS 1800)")) "a valid admission row")
      (assert (not (listEmpty? (cd/admissionErrors "(:admission :on maybe)"))) ":on takes true or false")
      (assert (not (listEmpty? (cd/admissionErrors "(:admission :jobs 0)"))) "zero jobs is rejected")
      (assert (not (listEmpty? (cd/admissionErrors "(:admission :limitS 10)"))) "a limit under 60 s is rejected")
      (assert (not (listEmpty? (cd/admissionErrors "(:admission :on true :speed 3)"))) "an unknown key is rejected")
      (assert (cd/admissionOn? "") "no row: admission is on")
      (assert (cd/admissionOn? "(:admission :on maybe)") "a rejected row: admission stays on")
      (assert (not (cd/admissionOn? "(:admission :on false)")) "an explicit :on false turns it off")
      (assert (= (cd/admissionJobsOf "") 2) "no row: -j 2")
      (assert (= (cd/admissionJobsOf "(:admission :on true :jobs 6)") 6) "a valid row sets -j")
      (assert (= (cd/admitLimitOf "" -1) 3600) "no estimate: 3600 s")
      (assert (= (cd/admitLimitOf "" 5800) 8700) "a 5800 s estimate gets half again: 8700 s")
      (assert (= (cd/admitLimitOf "(:admission :limitS 9000)" 1000) 9000) "never under :limitS")
      (assert (= (cd/admitLimitOf "" 20000) 14400) "never over 14400 s")
      (assert (= (cd/scaledEstimateS 1000 4 2) 2000) "a train estimate at -j 4 is twice as long at -j 2")
      (assert (= (cd/admissionMaxParallelOf "") 2) "no row: two admissions at once")
      (assert (= (cd/admissionMaxParallelOf "(:admission :maxParallel 5)") 5) "a valid row sets :maxParallel")
      (assert (not (listEmpty? (cd/admissionErrors "(:admission :maxParallel 0)"))) "zero parallel admissions is rejected")
      (assert (= (cd/admitArgv "/d" "sh/X" "/h/.asl/run/admit/X" "(:admission :jobs 3)")
                 (list "/d/bin/asl" "train" "sh/X" "--onto" "HEAD" "--repo" "/d" "--scratch" "/h/.asl/run/admit/X" "--admit" "--class" "writer" "-j" "3"))
              "the admission argv: the dev clone train, the branch alone onto the dev head, its own scratch, --admit, the writer class, no --commit")
      true)

fn testResOf -> Bool
  (let [(refused (cd/admitResOf 1 (refusedOut) 9))
        (base (cd/admitResOf 0 (baseRedOut) 9))
        (conflict (cd/admitResOf 3 (conflictOut) 9))
        (green (cd/admitResOf 0 "(:admission :verdict admitted :branch \"b\" :onto \"o\" :merged \"m\" :red () :assertLoss () :baseRed () :flaky () :unrun () :cached 2 :phasesMs (:rebase 1) :suiteMs ())" 9))
        (killed (cd/admitResOf 124 "killed: timeout" 9))
        (lying (cd/admitResOf 0 "(:admission :verdict refused :branch \"b\")" 9))]
    (do (assert (and (= refused.verdict "refused") (= refused.ok 0)) (str "a refused receipt is no pass: " (cd/renderRes refused)))
        (assert (stringContains? refused.sig "admitRed: (\"a/tests/aTest.asl\"") (str "its signature names the branch's own red suite: " refused.sig))
        (assert (and (= base.verdict "admit") (= base.ok 1)) (str "a red that is red on the dev head too admits: " (cd/renderRes base)))
        (assert (stringContains? base.sig "baseRed: \"a/tests/aTest.asl\"") (str "and reports the base red: " base.sig))
        (assert (and (= conflict.verdict "conflict") (= conflict.ok 0)) (str "a conflict receipt: " (cd/renderRes conflict)))
        (assert (stringContains? conflict.sig "admitConflict: ") (str "with an admitConflict signature: " conflict.sig))
        (assert (and (= green.verdict "admit") (stringEmpty? green.sig)) (str "a green admission: " (cd/renderRes green)))
        (assert (= killed.verdict "unverified") (str "a killed admission is no verdict on the branch: " (cd/renderRes killed)))
        (assert (= lying.verdict "unverified") (str "a receipt whose verdict disagrees with the exit is not trusted: " (cd/renderRes lying)))
        true))

; (:m :ref MERGE-ADMISSION :do "gate (a): a review pass goes to admitting; the refused admission sends the unit to ready with a fix owed and the admission log tail in its brief, its journal never reaches merging; with (:admission :on false) the same pass merges as before")
fn ! testRefusedNeverMerges root: String -> Bool
  (let [(dir (storeOf root "refused" (list "R1")))
        (ctx (ctxOf dir))
        (u (pf/unitIn "R1" "true"))
        (c0 (unitAt "R1" "reviewing"))
        (_ (cd/writeCUnit! dir c0))
        (pass (with (cd/failRes "") :ok 1 :exit 0 :verdict "pass"))
        (_ (cd/finish! ctx u c0 pass))
        (afterReview (stOf dir "R1"))
        (_ (dirCreate (cd/runsDir dir)))
        (_ (fileWrite (cd/admitLogPath dir "R1") (refusedOut)))
        (c1 (optionOr (cuOf dir "R1") c0))
        (_ (cd/finish! ctx u c1 (cd/admitResOf 1 (refusedOut) 42)))
        (c2 (optionOr (cuOf dir "R1") c0))
        (note (readOr (cd/admitRedPath dir "R1")))
        (journal (readOr (cd/journalPath dir)))
        (tos (pf/tosOf dir "R1"))
        (offDir (storeOf root "off" (list "F1")))
        (_ (fileWrite (str offDir "/ladder.asn") "(:admission :on false)\n"))
        (f0 (unitAt "F1" "reviewing"))
        (_ (cd/writeCUnit! offDir f0))
        (_ (cd/finish! (ctxOf offDir) (pf/unitIn "F1" "true") f0 pass))]
    (do (assert (= afterReview "admitting") (str "a review pass goes to admitting, not merging: " afterReview))
        (assert (= c2.st "ready") (str "a refused admission goes back to the writer: " c2.st))
        (assert (= c2.owed 1) (str "with a fix round owed: " (cd/renderCUnit c2)))
        (assert (stringStartsWith? c2.sig "admitRed: ") (str "under the admission signature: " c2.sig))
        (assert (stringContains? note "(:admissionRed :verdict refused :round 1 ") (str "the fix brief is an admissionRed form: " note))
        (assert (stringContains? note "ERR_ASSERT lib value is 3") (str "it carries the suite log tail: " note))
        (assert (stringContains? (cd/admitRedNote! dir "R1") ":must ") "the writer brief reads the note")
        (assert (stringContains? journal "(:admission :unit \"R1\" :action fixRound :verdict refused :round 1 ") (str "one fixRound row: " journal))
        (refute (listContains? tos "merging") (str "the unit never reaches merging: " (stringJoin tos ",")))
        (assert (= (stOf offDir "F1") "merging") (str "with :on false a review pass merges as before: " (stOf offDir "F1")))
        true))

; (:m :ref MERGE-ADMISSION :do "gate (b): an admission red only on suites red on the dev head too admits the unit to merging and journals the base red")
fn ! testBaseRedAdmits root: String -> Bool
  (let [(dir (storeOf root "base" (list "B1")))
        (ctx (ctxOf dir))
        (c0 (unitAt "B1" "admitting"))
        (_ (cd/writeCUnit! dir c0))
        (_ (cd/finish! ctx (pf/unitIn "B1" "true") c0 (cd/admitResOf 0 (baseRedOut) 42)))
        (journal (readOr (cd/journalPath dir)))]
    (do (assert (= (stOf dir "B1") "merging") (str "a base red admits: " (stOf dir "B1")))
        (assert (stringContains? journal "admitted baseRed: ") (str "the base red is reported: " journal))
        (assert (stringContains? journal "(:admission :unit \"B1\" :verdict admit :ms 42 ") (str "one admission row with its ms: " journal))
        (refute (fileExists? (cd/admitRedPath dir "B1")) "no fix brief for an admitted unit")
        true))

; (:m :ref MERGE-ADMISSION :do "gate (c): a branch that conflicts with the dev head goes back to the writer with a conflict brief; after maxSame rounds the next refusal escalates")
fn ! testConflictBack root: String -> Bool
  (let [(dir (storeOf root "conflict" (list "C1")))
        (ctx (ctxOf dir))
        (u (pf/unitIn "C1" "true"))
        (c0 (unitAt "C1" "admitting"))
        (_ (cd/writeCUnit! dir c0))
        (_ (dirCreate (cd/runsDir dir)))
        (_ (fileWrite (cd/admitLogPath dir "C1") (conflictOut)))
        (res (cd/admitResOf 3 (conflictOut) 7))
        (_ (cd/finish! ctx u c0 res))
        (st1 (stOf dir "C1"))
        (note (readOr (cd/admitRedPath dir "C1")))
        (again (fn [(k Int64)] -> String (let [(_ (cd/writeCUnit! dir (unitAt "C1" "admitting"))) (_ (cd/finish! ctx u (unitAt "C1" "admitting") res))] (stOf dir "C1"))))
        (st2 (again 2))
        (st3 (again 3))
        (st4 (again 4))]
    (do (assert (= st1 "ready") (str "a conflict goes back to the writer: " st1))
        (assert (stringContains? note "(:admissionRed :verdict conflict :round 1 ") (str "with a conflict brief: " note))
        (assert (stringContains? note "bring the dev head into the branch") (str "that says what to do: " note))
        (assert (and (= st2 "ready") (= st3 "ready")) (str "rounds two and three go back too: " st2 " " st3))
        (assert (= st4 "blocked") (str "the fourth refusal escalates: " st4))
        true))

; (:m :ref MERGE-ADMISSION :do "gate (e): admission is not the serial merge slot: with one merge child live (M1 merging, launched) a second merging unit waits unlaunched, while two admitting units both launch in the same tick")
fn ! testParallel root: String -> Bool
  (let [(dir (storeOf root "parallel" (list "M1" "M2" "A1" "A2")))
        (ctx (ctxOf dir))
        (_ (cd/writeCUnit! dir (with (unitAt "M1" "merging") :launched 1)))
        (_ (cd/writeCUnit! dir (unitAt "M2" "merging")))
        (_ (cd/writeCUnit! dir (unitAt "A1" "admitting")))
        (_ (cd/writeCUnit! dir (unitAt "A2" "admitting")))
        (_ (cd/launch! ctx (pf/unitIn "M2" "true") (unitAt "M2" "merging")))
        (_ (cd/launch! ctx (pf/unitIn "A1" "true") (unitAt "A1" "admitting")))
        (_ (cd/launch! ctx (pf/unitIn "A2" "true") (unitAt "A2" "admitting")))
        (a1 (launchedOf dir "A1"))
        (a2 (launchedOf dir "A2"))
        (m2 (launchedOf dir "M2"))]
    (do (assert (= m2 0) (str "the merge slot is serial: a second merge waits: " (cd/renderCUnit (optionOr (cuOf dir "M2") (unitAt "M2" "")))))
        (assert (> a1 0) (str "the first admission launches while a merge runs: " (stringFromInt64 a1)))
        (assert (> a2 0) (str "and the second at the same time: " (stringFromInt64 a2)))
        (assert (fileExists? (cd/runPath dir "A1" "admit" "run")) "A1 has an admit run row")
        (assert (fileExists? (cd/runPath dir "A2" "admit" "run")) "A2 has an admit run row")
        true))

; (:m :ref MERGE-ADMISSION :do "a killed admission that streamed a red suite knownRed does not list is refused on that suite; a known red only, or no red row, stays unverified; a run with a receipt keeps the receipt's verdict")
fn testResWith -> Bool
  (let [(killed "(:trainPhase :name \"prepare\" :ms 5)\n(:redLive \"a/tests/wideTest.asl\" 1 4 :kind suite :err (\"ERR_ASSERT x\"))\nkilled: timeout")
        (own (cd/admitResWith 124 killed 9 (list)))
        (known (cd/admitResWith 124 killed 9 (list "a/tests/wideTest.asl")))
        (quiet (cd/admitResWith 124 "killed: timeout" 9 (list)))
        (kept (cd/admitResWith 0 (baseRedOut) 9 (list)))]
    (do (assert (= own.verdict "refused") (str "a kill with an own red streamed is refused: " (cd/renderRes own)))
        (assert (stringContains? own.sig "a/tests/wideTest.asl") (str "on that suite: " own.sig))
        (assert (= known.verdict "unverified") (str "a kill whose only red is known red stays unverified: " (cd/renderRes known)))
        (assert (= quiet.verdict "unverified") (str "a kill with no red row stays unverified: " (cd/renderRes quiet)))
        (assert (= kept.verdict "admit") (str "a receipt keeps its verdict: " (cd/renderRes kept)))
        (assert (stringContains? (cd/admissionCounts (list "(:admission :unit \"A\" :verdict unverified :ms 1 :sig \"\" :at 1)" "(:admission :unit \"B\" :verdict admit :ms 1 :sig \"\" :at 1)" "(:admission :unit \"C\" :verdict unverified :ms 2 :sig \"\" :at 1)")) ":admitted 1 :refused 0 :conflict 0 :unverified 2") "status counts admission outcomes, unverified among them")
        true))

; (:m :ref MERGE-ADMISSION :do "M1: with two admissions launched (the default :maxParallel 2) a third admitting unit waits unlaunched; M2: an admission whose last log estimated 5800 s gets a stage deadline of its limit 8700 s plus 300 s, not the 60 s stage deadline")
fn ! testCapAndDeadline root: String -> Bool
  (let [(dir (storeOf root "cap" (list "A1" "A2" "A3")))
        (ctx (ctxOf dir))
        (_ (dirCreate (cd/runsDir dir)))
        (_ (fileWrite (cd/admitLogPath dir "A1") "(:trainEstimate :tier (:estimateS 5800 :heavyS 0))\n"))
        (_ (map (fn [(id String)] -> Bool (do (cd/writeCUnit! dir (unitAt id "admitting")) true)) (list "A1" "A2" "A3")))
        (_ (cd/launch! ctx (pf/unitIn "A1" "true") (unitAt "A1" "admitting")))
        (_ (cd/launch! ctx (pf/unitIn "A2" "true") (unitAt "A2" "admitting")))
        (_ (cd/launch! ctx (pf/unitIn "A3" "true") (unitAt "A3" "admitting")))
        (run (readOr (cd/runPath dir "A1" "admit" "run")))
        (num (fn [(k String)] -> Int64 (optionOr (stringToInt64 (optionOr (listHead (stringSplit (stringReplace (stringReplace (optionOr (listGet (stringSplit run k) 1) "") ")" " ") "\n" " ") " ")) "")) 0)))
        (spanS (/ (- (num ":deadlineMs ") (num ":startedMs ")) 1000))]
    (do (assert (and (> (launchedOf dir "A1") 0) (> (launchedOf dir "A2") 0)) "two admissions launch")
        (assert (= (launchedOf dir "A3") 0) (str "a third waits under :maxParallel 2: " (stringFromInt64 (launchedOf dir "A3"))))
        (assert (>= spanS 9000) (str "the admission deadline follows its estimate: " (stringFromInt64 spanS) " s: " run))
        true))

; (:m :ref MERGE-ADMISSION :do "M3: the sweep removes the admission scratch of a unit that left admitting, ready and writing (merging here) and keeps the scratch of a unit back in ready for its fix round")
fn ! testSweep root: String -> Bool
  (let [(dir (storeOf root "sweep" (list "S1" "S2" "S3")))
        (_ (cd/writeCUnit! dir (unitAt "S1" "merging")))
        (_ (cd/writeCUnit! dir (unitAt "S2" "ready")))
        (_ (cd/writeCUnit! dir (with (unitAt "S3" "admitting") :launched 1)))
        (_ (dirCreate (str dir "/admit")))
        (_ (dirCreate (cd/admitScratchOf dir "S1")))
        (_ (dirCreate (cd/admitScratchOf dir "S2")))
        (_ (dirCreate (cd/admitScratchOf dir "S3")))
        (_ (fileWrite (str (cd/admitScratchOf dir "S1") "/marker") "x"))
        (swept (cd/admitSweep! dir))]
    (do (assert (= swept 1) (str "one scratch swept: " (stringFromInt64 swept)))
        (refute (fileExists? (cd/admitScratchOf dir "S1")) "the merging unit's scratch is gone")
        (assert (fileExists? (cd/admitScratchOf dir "S2")) "the ready unit's scratch stays for its next round")
        (assert (fileExists? (cd/admitScratchOf dir "S3")) "the scratch of an admission still running stays")
        (assert (stringContains? (readOr (cd/journalPath dir)) "(:admitSweep :unit \"S1\" ") "one sweep row")
        true))

; (:m :ref MERGE-ADMISSION :do "L8: a suite the newest kept train of a unit in the store marked :preexisting is a base red, so a killed admission that streamed it red stays unverified")
fn ! testPreexisting root: String -> Bool
  (let [(dir (storeOf root "pre" (list "P1")))
        (_ (dirCreate (str dir "/trains")))
        (_ (dirCreate (str dir "/trains/T1")))
        (_ (fileWrite (str dir "/trains/T1/000001.out") "(:trainPhase :name \"prepare\" :ms 1)\n(:train :head \"h\" :red () :preexisting ((\"a/tests/wideTest.asl\" \"sh/T1\" 1 4 :kind suite :why preexisting)) :assertLoss ())\n"))
        (pre (cd/trainPreexisting! dir))
        (killed "(:redLive \"a/tests/wideTest.asl\" 1 4 :kind suite :err (\"ERR_ASSERT x\"))\nkilled: timeout")
        (r (cd/admitResWith 124 killed 9 pre))]
    (do (assert (= pre (list "a/tests/wideTest.asl")) (str "the preexisting suites of the newest kept train: " (stringJoin pre ",")))
        (assert (= r.verdict "unverified") (str "a kill whose only red the last train found preexisting stays unverified: " (cd/renderRes r)))
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "admissionTest" "root"))
        (_ (pf/cleanup root))
        (r (and (testRows) (and (testResOf) (and (testRefusedNeverMerges root) (and (testBaseRedAdmits root) (and (testConflictBack root) (and (testParallel root) (and (testResWith) (and (testCapAndDeadline root) (and (testSweep root) (testPreexisting root)))))))))))
        (_ (pf/cleanup root))]
    r)
