(module asl-tools/coord/tests/docRowsGateBoundTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRowsGate :a dg) (aslAgent/gateLimit :a gl) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref WALL-SLOW-GATES :do "docRowsGate under a limit on a fixture repo whose bin/asl is a fake: the know run sleeps 90 s when .fakeSlow exists. With --limit 60 the inner budget is 20 s, so the gate answers a (:partial ...) line and exit 0 in well under the limit (red before: the whole 300 s went to the know run and the gate outlived the limit), a repeat on the same tree is served from the memo in the worktree's own git dir without starting the tool, a changed file reruns it, and a complete answer is memoised the same way")
fn fakeTool -> String
  "#!/bin/sh\necho \"$@\" >> \"$ASL_ROOT.fakeLog\"\nif [ \"$1\" = check ]; then exit 0; fi\nif [ -f \"$ASL_ROOT.fakeSlow\" ]; then sleep 90; fi\necho \"(:know :missing :new 0)\"\n"

fn trieBase -> String
  "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  1\n"

fn trieNew -> String
  "(module asl-utils/trie\n  :x [empty insert]\n  :i [])\n\nfn empty -> Int64\n  1\n\nfn insert k: Int64 -> Int64\n  k\n"

fn sh c: String -> String
  (pf/sh c)

fn ! g dir: String words: String -> fr/Done
  (cd/gitOut dir (stringSplit words " "))

fn ! unitOf! root: String -> String
  (let [(repo (str root "/repo"))
        (wt (str root "/wts/w-A"))
        (w (sh (str "mkdir -p " repo "/bin " repo "/asl/packages/asl-utils/src " root "/wts && echo initOk")))
        (_ (g repo "init -q -b main"))
        (_ (fileWrite (str repo "/bin/asl") (fakeTool)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/src/trie.asl") (trieBase)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#\" :text \"tries\")\n"))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (_ (g repo "add -A"))
        (_ (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))
        (_ (g repo (str "worktree add -q -b sh/A " wt " main")))
        (_ (fileWrite (str wt "/asl/packages/asl-utils/src/trie.asl") (trieNew)))
        (_ (fileAppend (str wt "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#insert\" :text \"inserts\")\n"))
        (_ (g wt "add -A"))
        (_ (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (stringContains? w "initOk") wt ""))

fn logOf wt: String -> String
  (resultOr (fileReadString (str wt ".fakeLog")) "")

fn toolRuns wt: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l "know.asl")) (stringLines (logOf wt))))

fn nowSec -> Int64
  (/ (monotonicNs) 1000000000)

fn textOf r: (Pair Int64 (List String)) -> String
  (stringJoin (pairSecond r) "\n")

fn ! runTests -> Bool
  (let [(root (pf/scratch "drgb" "x"))
        (_ (pf/cleanup root))
        (wt (unitOf! root))
        (_ (fileWrite (str wt ".fakeSlow") "1"))
        (t0 (nowSec))
        (slow (dg/runGate (list wt "main" "--writer" "--limit" "60")))
        (spent (- (nowSec) t0))
        (runsAfterSlow (toolRuns wt))
        (t1 (nowSec))
        (again (dg/runGate (list wt "main" "--writer" "--limit" "60")))
        (runsAfterAgain (toolRuns wt))
        (t2 (nowSec))
        (third (dg/runGate (list wt "main" "--limit" "60")))
        (spentThird (- (nowSec) t2))
        (runsAfterThird (toolRuns wt))
        (memoFile (str (stringTrim (g wt "rev-parse --absolute-git-dir").out) "/docRowsGate.memo"))
        (memoText (resultOr (fileReadString memoFile) ""))
        (_ (fileAppend (str wt "/asl/packages/asl-utils/src/trie.asl") "\n; env\n"))
        (viaEnv (dg/runGateEnv (list wt "main" "--writer") "60"))
        (_ (sh (str "rm -f " wt ".fakeSlow")))
        (_ (fileAppend (str wt "/asl/packages/asl-utils/src/trie.asl") "\n; changed2\n"))
        (fast (dg/runGate (list wt "main" "--writer" "--limit" "60")))
        (runsAfterFast (toolRuns wt))
        (fastAgain (dg/runGate (list wt "main" "--writer" "--limit" "60")))
        (runsAfterFastAgain (toolRuns wt))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? wt)) "fixture worktree exists")
        (assert (< (gl/innerBudgetSec (gl/gateLimitSec)) (gl/gateLimitSec)) "the inner budget is strictly below the gate limit")
        (assert (= (gl/innerBudgetSec 60) 20) (str "innerBudgetSec derives from the limit and one margin: " (stringFromInt64 (gl/innerBudgetSec 60))))
        (assert (= (pairFirst slow) 0) (str "slow know run under --writer: exit 0, not a kill: " (textOf slow)))
        (assert (stringContains? (textOf slow) "(:partial :docRows :ran false :partial true") (str "the verdict is a (:partial ...) line: " (textOf slow)))
        (assert (< spent 60) (str "the gate answers strictly inside the limit (60 s), took " (stringFromInt64 spent)))
        (assert (>= spent 15) (str "the know run was given its budget, not skipped, took " (stringFromInt64 spent)))
        (assert (= runsAfterSlow 1) "the know tool started once")
        (assert (= runsAfterAgain 2) "a know timeout is retried once on the same tree")
        (assert (= (pairFirst third) 2) (str "without --writer a partial is exit 2, as a check that cannot run: " (textOf third)))
        (assert (< spentThird 4) (str "the second partial is served from the memo, took " (stringFromInt64 spentThird)))
        (assert (= runsAfterThird 2) "the memo hit did not start the tool")
                (assert (and (stringContains? memoText "partial") (stringContains? memoFile "/.git/")) (str "the memo is in the worktree git dir: " memoFile))
        (assert (not (stringStartsWith? memoFile (str (optionOr (envGet "HOME") "/nonexistent") "/.asl/"))) "the memo is not under ~/.asl")
        (assert (stringContains? (textOf viaEnv) ":limitSec 60 :budgetSec 20") (str "ASL_GATE_LIMIT_SEC=60 without --limit sets the limit: " (textOf viaEnv)))
        (assert (and (= (dg/envLimit "0" 300) 300) (and (= (dg/envLimit "abc" 300) 300) (and (= (dg/envLimit "-5" 300) 300) (and (= (dg/envLimit "" 300) 300) (= (dg/envLimit "45" 300) 45))))) "an env limit under 1 or not a number falls back to the default")
        (assert (= (pairFirst fast) 0) (str "changed file, fast tool: complete answer: " (textOf fast)))
        (assert (= runsAfterFast 4) "a changed file is a memo miss and reruns the tool")
        (assert (stringContains? (textOf fast) "assert docRows: no new exported symbol lacks its contract row") (str "complete: " (textOf fast)))
        (assert (= runsAfterFastAgain 4) "the complete answer is memoised too")
        (assert (= (textOf fastAgain) (textOf fast)) "the memoised complete answer equals the first")
        true))
