(module asl-tools/coord/tests/baseRedConfirmTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref BASE-RED-FALSE-HOLD :do "a train that reports only a base red is confirmed before the hold: the dev clone's stand-in train prints a baseRed receipt and its test word runs the suite alone, green or red by the file .git/testGreen; green alone gives verdict baseFlaky, which finish! retries with no failure count and no baseRed hold twice, then counts as a failure; red alone, or green with no executed assertion, keeps the baseRed hold")
fn standIn -> String
  "#!/bin/sh\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\nif [ \"$1\" = test ]; then echo \"$2\" >> \"$D/.git/testArgs\"; if [ -f \"$D/.git/testGreen\" ]; then N=$(cat \"$D/.git/testGreen\"); echo \"(:gate)\"; echo \"$N assertion(s) executed ($N passed)\"; exit 0; fi; echo \"FAIL $2\"; exit 1; fi\necho \"$@\" >> \"$D/.git/trainArgs\"\nif [ -f \"$D/.git/trainOut\" ]; then cat \"$D/.git/trainOut\"; exit 1; fi\nexit 0\n"

fn trainOut -> String
  (str "(:redLive \"asl/b/bTest.asl\" 1 0 :kind suite :err (\"ERR_ASSERT: load\"))\n"
       "(:train :head \"abc\" :merged \"def\" :branches (\"sh/F1\") :changed 1 :selected 1 :cached 0 :ran 1 :green 0 :invariants 0"
       " :red () :preexisting ((\"asl/b/bTest.asl\" \"sh/F1\" 1 0 :kind suite :why preexisting)) :assertLoss () :baseKnown 1 :seconds 9)\n")

fn stubPass rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (pair 0 "(:mergeCheck :verdict pass)")

fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "baseRedConfirmTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (pf/cuIn id "gone" "" ""))

fn ! claimed! dir: String id: String wt: String -> cd/CUnit
  (let [(epoch (match (st/claim! dir id "baseRedConfirmTest" 600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0)))
        (c (with (pf/cuIn id "merging" wt (str "sh/" id)) :epoch epoch :launched 1))
        (_ (cd/writeCUnit! dir c))]
    c)

fn ! count text: String needle: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l needle)) (stringLines text)))

fn ! testRun root: String -> Bool
  (let [(repo (pf/repoIn root))
        (store (str root "/store"))
        (_ (fileWrite (cd/repoPath store) repo))
        (dev (pf/devCloneFor! root))
        (_ (fileWrite (str dev "/bin/asl") (standIn)))
        (rc (cd/realCfg (list "--repo" (str root "/repo") "--dev-repo" dev "--dev" "dev" "--worktrees" (str root "/wts") "--home" (str root "/home")) store))
        (ctx (ctxOf store))
        (u (with (pf/unitIn "F1" "true") :owns (list "f1.txt")))
        (w (pf/seedUnit! root u "merging" "f1.txt"))
        (c0 (claimed! store "F1" w))
        (_ (dirCreate (cd/runsDir store)))
        (_ (fileWrite (str dev "/.git/trainOut") (trainOut)))
        (rRed (cd/mergeResWith rc store u c0 stubPass))
        (_ (cd/finish! ctx u c0 rRed))
        (held (cuOf store "F1"))
        (_ (cd/writeCUnit! store (with held :await "" :launched 1)))
        (_ (fileWrite (str dev "/.git/testGreen") "0"))
        (rZero (cd/mergeResWith rc store u (cuOf store "F1") stubPass))
        (_ (fileWrite (str dev "/.git/testGreen") "66"))
        (rFlaky (cd/mergeResWith rc store u (cuOf store "F1") stubPass))
        (runsBefore (count (resultOr (fileReadString (str dev "/.git/testArgs")) "") "asl/b/bTest.asl"))
        (rShort (cd/mergeResWith (with rc :stageSec 100) store u (cuOf store "F1") stubPass))
        (runsAfter (count (resultOr (fileReadString (str dev "/.git/testArgs")) "") "asl/b/bTest.asl"))
        (_ (cd/finish! ctx u (cuOf store "F1") rFlaky))
        (f1 (cuOf store "F1"))
        (_ (cd/writeCUnit! store (with f1 :launched 1)))
        (_ (cd/finish! ctx u (cuOf store "F1") rFlaky))
        (f2 (cuOf store "F1"))
        (_ (cd/writeCUnit! store (with f2 :launched 1)))
        (_ (cd/finish! ctx u (cuOf store "F1") rFlaky))
        (f3 (cuOf store "F1"))
        (journal (stringJoin (pf/journalLines store) "\n"))
        (tests (resultOr (fileReadString (str dev "/.git/testArgs")) ""))]
    (do (assert (and (not (stringEmpty? repo)) (and (not (stringEmpty? dev)) (not (stringEmpty? w)))) "fixture: dev clone with the stand-in train and one unit")
        (assert (and (!= rRed.verdict "baseFlaky") (stringStartsWith? rRed.sig "train baseRed:")) (str "a suite still red alone is no flake: " rRed.verdict " " rRed.sig))
        (assert (stringStartsWith? held.await "baseRed:") (str "and the unit is held: " held.await))
        (assert (!= rZero.verdict "baseFlaky") (str "green with no executed assertion confirms nothing: " rZero.verdict))
        (assert (= rFlaky.verdict "baseFlaky") (str "green alone with executed assertions is flaky: " rFlaky.verdict))
        (assert (and (!= rShort.verdict "baseFlaky") (stringStartsWith? rShort.sig "train baseRed:")) (str "with the stage's remainder under the check limit the hold stays: " rShort.verdict " " rShort.sig))
        (assert (= runsBefore runsAfter) "and the suite is not run at all")
        (assert (= (cd/baseConfirmEach 100 1) 0) "the limit comes from the remainder: nothing under 60 s each")
        (assert (and (= (cd/baseConfirmEach 5400 1) 500) (= (cd/baseConfirmEach 200 3) 0)) "a long remainder gives 500 s, a short one split over three suites gives none")
        (assert (stringContains? tests "asl/b/bTest.asl") (str "the suite ran alone through the dev head's bin/asl test: " tests))
        (assert (and (= f1.st "merging") (and (= f1.fails 0) (not (stringStartsWith? f1.await "baseRed:")))) (str "the first flake retries without a hold or a count: " f1.st " " (stringFromInt64 f1.fails) " " f1.await))
        (assert (and (= f2.st "merging") (and (= f2.fails 0) (not (stringStartsWith? f2.await "baseRed:")))) (str "the second flake retries too: " (stringFromInt64 f2.fails)))
        (assert (and (= f3.fails 1) (not (stringStartsWith? f3.await "baseRed:"))) (str "the third counts as a failure, never a hold: " (stringFromInt64 f3.fails) " " f3.await))
        (assert (= (count journal "(:baseFlaky :unit \"F1\" :n ") 3) (str "three baseFlaky rows: " (stringFromInt64 (count journal "(:baseFlaky :unit \"F1\" :n "))))
        (assert (and (= (count journal ":action retry") 2) (= (count journal ":action count") 1)) "two retries and one counted flake in the journal")
        true))

fn ! cleanup! root: String -> Bool
  (let [(_ (pf/cleanup root))] true)

fn ! runTests -> Bool
  (let [(root (pf/scratch "baseRedConfirm" "w"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (run (testRun (str root "/run")))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (listEmpty? (cd/baseRedPaths "train baseRed:")) "no path after the prefix")
        (assert (= (cd/baseRedPaths "train baseRed: a/aTest.asl b/bTest.asl") (list "a/aTest.asl" "b/bTest.asl")) "the suites a base red names")
        (assert run "the base red is confirmed alone before any hold")
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
