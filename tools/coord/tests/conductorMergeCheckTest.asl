(module asl-tools/coord/tests/conductorMergeCheckTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref CONDUCTOR-MERGE-CHECK :do "the merge stage runs mergeCheck before the train, on a temp source repo with unit branches and a temp dev clone whose bin/asl answers audit with a canned receipt and records train calls; a clean branch merges and journals an exit 0 receipt, a branch that grows knownRed.asn is blocked with dev and train untouched, an unverifiable check holds the unit with one lead-stream row, and finish! parks a block or a hold without a failure count")
fn ! gitIn dir: String args: String -> String
  (stringTrim (pf/sh (str "git -C " dir " " args)))

fn ! devClone! root: String -> String
  (let [(dev (str root "/dev"))
        (made (pf/sh (str "git clone -q " root "/repo " dev " && cd " dev " && git config user.email t@example.invalid && git config user.name t && git checkout -q -b dev && mkdir -p bin"
                          " && printf '#!/bin/sh\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\nif [ \"$1\" = audit ]; then if [ \"$(cat \"$D/.git/auditMode\" 2>/dev/null)\" = junk ]; then echo nothing; exit 0; fi; echo \"(:audit :sub $2 :status :passed)\"; exit 0; fi\necho \"$@\" >> \"$D/.git/trainArgs\"\ngit -C \"$D\" merge --no-ff -q -m \"(:c :a t :do train)\" \"$2\" || exit 1\nexit 0\n' > bin/asl && chmod 755 bin/asl && echo bin/asl >> .git/info/exclude && echo madeOk")))]
    (if (stringContains? made "madeOk") dev ""))

; (:m :do "a unit branch whose one commit grows the shrink-only ledger .asl/mem/knownRed.asn")
fn ! seedGrowth! root: String u: st/Task -> String
  (let [(wt (pf/seedUnit! root u "merging" ""))
        (made (pf/sh (str "cd " wt " && mkdir -p .asl/mem && printf '(:suite \"t/aTest.asl\" :cause \"x\" :failedAssertDigest \"d1\")\\n' > .asl/mem/knownRed.asn && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm '(:c :a t :do grow)' && echo madeOk")))]
    (if (stringContains? made "madeOk") wt ""))

fn stubUnverified rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (pair 3 "(:mergeCheck :verdict unverified :unverified (\"gates:deadline\") :structure () :regressions ())")

; (:m :ref CONDUCTOR-MERGE-CHECK-FIX :do "exit 2 is a check that could not run (checkout failed), never a pass: it holds like exit 3; the recording stub writes the base it was given so the test can compare it with the fork point")
fn stubCannotRun rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (pair 2 "(:mergeCheck :verdict block :error \"cannot check out base and head\")")

fn ! stubRecord rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (let [(_ (fileWrite (str rc.home "/baseSeen") base))]
    (pair 0 "(:mergeCheck :verdict pass)"))

fn rowsOf root: String needle: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l needle)) (stringLines (resultOr (fileReadString (str root "/lead/stream.asn")) ""))))

fn journalOf root: String -> String
  (resultOr (fileReadString (cd/journalPath (str root "/store"))) "")

fn resOf ok: Int64 verdict: String sig: String -> cd/Res
  (cd/Res :ok ok :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict verdict :tiers "")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "mcTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 4 4))

fn ! parkOf! root: String id: String verdict: String sig: String -> cd/CUnit
  (let [(dir (str root "/store"))
        (u (pf/unitIn id "sh check.sh impl.txt"))
        (_ (st/put! dir u))
        (_ (cd/writeCUnit! dir (pf/cuIn id "merging" "" (str "sh/" id))))
        (c (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" "")))
        (_ (cd/finish! (ctxFor root) u c (resOf 0 verdict sig)))]
    (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" "")))

; (:m :ref MERGECHECK-BUDGET-LOWS :do "the budgets are read from the source because they are literals there: the digits after a marker, -1 when the marker is absent")
fn numAfter text: String marker: String -> Int64
  (let [(parts (stringSplit text marker))]
    (if (< (listLength parts) 2) -1
      (let [(rest (optionOr (listGet parts 1) ""))
            (digits (optionOr (listHead (stringSplit (stringReplace (stringReplace rest ")" " ") "\n" " ") " ")) ""))]
        (optionOr (stringToInt64 digits) -1))))

; (:m :ref MERGECHECK-BUDGET-LOWS :do "gates the stage budgets: the stage child's argv carries --merge-check-sec when the conductor was given it, the flag reaches RealCfg, and the merge-check budget plus the train limit stay under the stage deadline (both literals in conductor.asl: the stage-sec default and the (fr/limits N 200) of the train run)")
fn ! testBudgets -> Bool
  (let [(dir "/tmp/mcBudgetStore")
        (src (resultOr (fileReadString "asl/tools/coord/conductor.asl") ""))
        (stageDefault (cd/stageSecDefault))
        (trainLimit (cd/trainLimitSec))
        (usesTrainLimit (stringContains? src "(fr/limits (trainLimitSec) 200)"))
        (rcBig (cd/realCfg (list "--repo" "/r" "--dev-repo" "/r" "--dev" "dev" "--merge-check-sec" "99999") dir))
        (rcSmallStage (cd/realCfg (list "--repo" "/r" "--dev-repo" "/r" "--dev" "dev" "--stage-sec" "3000") dir))
        (u (pf/unitIn "BG1" "sh check.sh impl.txt"))
        (c (pf/cuIn "BG1" "merging" "" "sh/BG1"))
        (withFlag ((cd/realLaunch (list "--repo" "/r" "--merge-check-sec" "777") dir) "merge" u c))
        (without ((cd/realLaunch (list "--repo" "/r") dir) "merge" u c))
        (at (fn [(argv (List String))] -> Int64 (optionOr (listIndexOf argv "--merge-check-sec") -1)))
        (rcFlag (cd/realCfg (list "--repo" "/r" "--dev-repo" "/r" "--dev" "dev" "--merge-check-sec" "777") dir))
        (rcDefault (cd/realCfg (list "--repo" "/r" "--dev-repo" "/r" "--dev" "dev") dir))
        (ctxDef (cd/realCtx (list "--repo" "/r") dir rcDefault))
        (ctxFlag (cd/realCtx (list "--repo" "/r" "--stage-sec" "777") dir rcFlag))]
    (do (assert (and (>= (at withFlag) 0) (= (optionOr (listGet withFlag (+ (at withFlag) 1)) "") "777")) (str "the stage child gets --merge-check-sec with the given value: " (stringJoin withFlag " ")))
        (assert (< (at without) 0) "without the flag the child argv carries none, so the default applies in the child too")
        (assert (= rcFlag.mergeCheckSec 777) (str "the flag reaches RealCfg: " (stringFromInt64 rcFlag.mergeCheckSec)))
        (assert (> rcDefault.mergeCheckSec 0) "the default merge-check budget is set")
        (assert (and usesTrainLimit (and (= ctxDef.stageSec stageDefault) (= ctxFlag.stageSec 777))) (str "the train child uses the one limit literal, and the Ctx the conductor runs with takes its stage deadline from --stage-sec or the one default: " (stringFromInt64 ctxDef.stageSec) " " (stringFromInt64 ctxFlag.stageSec)))
        (assert (< (+ rcBig.mergeCheckSec trainLimit) stageDefault) (str "a huge --merge-check-sec is clamped under the stage deadline: " (stringFromInt64 rcBig.mergeCheckSec)))
        (assert (and (> rcSmallStage.mergeCheckSec 0) (<= rcSmallStage.mergeCheckSec 60)) (str "a stage deadline below the train limit leaves the 60 s floor: " (stringFromInt64 rcSmallStage.mergeCheckSec)))
        (assert (< (+ rcDefault.mergeCheckSec trainLimit) stageDefault) (str "default merge-check budget plus train limit stay under the stage deadline: " (stringFromInt64 rcDefault.mergeCheckSec) " + " (stringFromInt64 trainLimit) " vs " (stringFromInt64 stageDefault)))
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "condMc" "w"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (wtClean (pf/seedUnit! root (pf/unitIn "C1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtGrow (seedGrowth! root (pf/unitIn "K1" "sh check.sh impl.txt")))
        (wtHold (pf/seedUnit! root (pf/unitIn "H1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtStub (pf/seedUnit! root (pf/unitIn "H2" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtTwo (pf/seedUnit! root (pf/unitIn "H3" "sh check.sh impl.txt") "merging" "impl.txt"))
        (_ (pf/sh (str "cd " root "/repo && git branch -f sh/ORPH $(git commit-tree $(git hash-object -t tree /dev/null) -m '(:c :a t :do orphan)')")))
        (wtBase (pf/seedUnit! root (pf/unitIn "B1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (dev (devClone! root))
        (forkPoint (gitIn repo "rev-parse main"))
        (_ (pf/sh (str "cd " dev " && printf later > later.txt && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm '(:c :a t :do later)' && echo ok")))
        (devTip (gitIn dev "rev-parse HEAD"))
        (rc (cd/realCfg (list "--repo" (str root "/repo") "--dev-repo" dev "--dev" "dev" "--worktrees" (str root "/wts") "--home" (str root "/home")) (str root "/store")))
        (store (str root "/store"))
        (head0 (gitIn dev "rev-parse HEAD"))
        (rGrow (cd/mergeRes rc store (pf/unitIn "K1" "sh check.sh impl.txt") (pf/cuIn "K1" "merging" wtGrow "sh/K1")))
        (headGrow (gitIn dev "rev-parse HEAD"))
        (argsGrow (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
        (_ (fileWrite (str dev "/.git/auditMode") "junk"))
        (rHold (cd/mergeRes rc store (pf/unitIn "H1" "sh check.sh impl.txt") (pf/cuIn "H1" "merging" wtHold "sh/H1")))
        (headHold (gitIn dev "rev-parse HEAD"))
        (_ (fileWrite (str dev "/.git/auditMode") "ok"))
        (rStub (cd/mergeResWith rc store (pf/unitIn "H2" "sh check.sh impl.txt") (pf/cuIn "H2" "merging" wtStub "sh/H2") stubUnverified))
        (headStub (gitIn dev "rev-parse HEAD"))
        (head2a (gitIn dev "rev-parse HEAD"))
        (rTwo (cd/mergeResWith rc store (pf/unitIn "H3" "sh check.sh impl.txt") (pf/cuIn "H3" "merging" wtTwo "sh/H3") stubCannotRun))
        (headTwo (gitIn dev "rev-parse HEAD"))
        (argsTwo (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
        (rOrph (cd/mergeResWith rc store (pf/unitIn "O1" "sh check.sh impl.txt") (pf/cuIn "O1" "merging" "" "sh/ORPH") stubRecord))
        (headOrph (gitIn dev "rev-parse HEAD"))
        (argsOrph (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
        (rFetch (cd/mergeResWith rc store (pf/unitIn "F1" "sh check.sh impl.txt") (pf/cuIn "F1" "merging" "" "sh/NOBRANCH") stubUnverified))
        (nF1 (rowsOf root "F1"))
        (rBase (cd/mergeResWith rc store (pf/unitIn "B1" "sh check.sh impl.txt") (pf/cuIn "B1" "merging" wtBase "sh/B1") stubRecord))
        (baseSeen (resultOr (fileReadString (str root "/home/baseSeen")) ""))
        (rOk (cd/mergeRes rc store (pf/unitIn "C1" "sh check.sh impl.txt") (pf/cuIn "C1" "merging" wtClean "sh/C1")))
        (headOk (gitIn dev "rev-parse HEAD"))
        (argsOk (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
        (journal (journalOf root))
        (blockedC (parkOf! root "P1" "block" "mergeCheck: ledgerGrew"))
        (heldC (parkOf! root "P2" "hold" "mergeCheck unverified exit 3: gates:deadline"))
        (nHold (rowsOf root "mergeCheckHold"))
        (nH1 (rowsOf root "H1"))
        (nH2 (rowsOf root "H2"))
        (nH3 (rowsOf root "H3"))
        (nO1 (rowsOf root "O1"))
        (statusText (cd/status! (ctxFor root)))
        (wtKept (fileExists? (str wtGrow "/.git")))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))
        (stubLeft (fr/stubDirsOwnedBy (procSelf)))]
    (do (assert (and stubGone (listEmpty? stubLeft)) (str "the stand-in host dir of this run is removed before any assert, so a red run leaves none: " (stringJoin stubLeft " ")))
        (assert (testBudgets) "the stage budgets hold")
        (assert (and (not (stringEmpty? repo)) (and (not (stringEmpty? dev)) (and (not (stringEmpty? wtClean)) (and (not (stringEmpty? wtGrow)) (and (not (stringEmpty? wtHold)) (not (stringEmpty? wtStub))))))) "fixture: source repo, dev clone and four unit branches are up")
        (assert (and (= rGrow.ok 0) (= rGrow.verdict "block") (stringStartsWith? rGrow.sig "mergeCheck:") (stringContains? rGrow.sig "ledgerGrew")) (str "a branch that grows knownRed.asn is blocked with the ledger in the signature: " rGrow.verdict " " rGrow.sig))
        (assert (and (= headGrow head0) (stringEmpty? argsGrow)) (str "a blocked check leaves dev where it was and never starts the train: " argsGrow))
        (assert wtKept "a blocked check keeps the unit worktree")
        (assert (and (= rHold.ok 0) (= rHold.verdict "hold") (stringContains? rHold.sig "mergeCheck unverified exit 3")) (str "an audit with no receipt is unverified and holds the unit: " rHold.verdict " " rHold.sig))
        (assert (= headHold head0) "a held unit leaves dev where it was")
        (assert (and (= rStub.verdict "hold") (stringContains? rStub.sig "gates:deadline") (= headStub head0)) (str "a stubbed unverified check holds with its unverified step in the signature: " rStub.sig))
        (assert (and (= rFetch.ok 0) (= rFetch.verdict "fail") (stringStartsWith? rFetch.sig "merge: ") (stringContains? rFetch.sig "sh/NOBRANCH") (not (stringContains? rFetch.sig "mergeCheck")) (= nF1 0)) (str "a failed branch fetch (the branch is not in the source repo) skips the check: no hold, no lead row, the train fails with its own signature: " rFetch.verdict " " rFetch.sig))
        (assert (and (= rOrph.verdict "hold") (stringContains? rOrph.sig "noMergeBase") (= headOrph head2a) (not (stringContains? argsOrph "O1"))) (str "a good fetch with no merge base holds as unverified, no train, dev unchanged: " rOrph.verdict " " rOrph.sig))
        (assert (and (= nHold 4) (and (= nH1 1) (and (= nH2 1) (and (= nH3 1) (= nO1 1))))) (str "one lead-stream row per held unit: " (stringFromInt64 nHold)))
        (assert (and (= rTwo.verdict "hold") (= rTwo.ok 0) (stringContains? rTwo.sig "exit 2") (= headTwo head2a) (not (stringContains? argsTwo "H3"))) (str "a check that could not run (exit 2) holds the unit, no train, dev unchanged: " rTwo.verdict " " rTwo.sig))
        (assert (and (not (stringEmpty? baseSeen)) (= baseSeen forkPoint) (!= baseSeen devTip)) (str "the check gets the fork point of the branch, not the dev head: seen " baseSeen " fork " forkPoint " dev " devTip))
        (assert (stringContains? statusText "(:held (\"P2\"))") (str "status! lists a held unit: " statusText))
        (assert (and (= rOk.ok 1) (stringEmpty? rOk.sig) (!= headOk head0)) (str "a clean branch passes the check and merges: " rOk.sig))
        (assert (stringContains? argsOk "train sh/C1 --onto HEAD") (str "the train ran for the clean branch only: " argsOk))
        (assert (and (stringContains? journal "(:mergeReceipt :unit \"C1\" :exit 0 ") (stringContains? journal "(:mergeReceipt :unit \"K1\" :exit 1 ") (stringContains? journal "(:mergeReceipt :unit \"H1\" :exit 3 ")) "the journal holds the mergeCheck receipt of a pass, a block and a hold")
        (assert (and (= blockedC.st "blocked") (= blockedC.fails 0) (stringContains? blockedC.sig "ledgerGrew") (stringEmpty? blockedC.await)) (str "finish! parks a block as blocked with no failure count: " blockedC.st " " (stringFromInt64 blockedC.fails)))
        (assert (and (= heldC.st "blocked") (= heldC.fails 0) (= heldC.await "mergeHold")) (str "finish! parks a hold as blocked await mergeHold with no failure count: " heldC.st " " heldC.await))
        true))
