(module asl-tools/coord/tests/docRowsGateBoundTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRowsGate :a dg) (aslAgent/gateLimit :a gl) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref WALL-SLOW-GATES :do "docRowsGate under a limit on a fixture repo whose bin/asl is a fake that logs its calls and sleeps 90 s when .fakeSlow exists: since rule docs (DOC-THIN) the gate never starts the know tool, so with --limit 60 it answers well inside the limit even with the slow tool armed (red before: 140 know runs hit the limit in 72 h on node2), a repeat on the same tree is served from the memo in the worktree git dir, ASL_GATE_LIMIT_SEC sets the limit and a changed file is a memo miss")
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
        (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#\" :text \"Prefix lookups for the router, kept apart so the hot path allocates nothing\")\n"))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (_ (g repo "add -A"))
        (_ (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))
        (_ (g repo (str "worktree add -q -b sh/A " wt " main")))
        (_ (fileWrite (str wt "/asl/packages/asl-utils/src/trie.asl") (trieNew)))
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
        (first (dg/runGate (list wt "main" "--writer" "--limit" "60")))
        (spent (- (nowSec) t0))
        (t1 (nowSec))
        (again (dg/runGate (list wt "main" "--limit" "60")))
        (spentAgain (- (nowSec) t1))
        (memoFile (str (stringTrim (g wt "rev-parse --absolute-git-dir").out) "/docRowsGate.memo"))
        (memoText (resultOr (fileReadString memoFile) ""))
        (sharedMemo (fileExists? (str root "/repo/.git/docRowsGate.memo")))
        (_ (fileAppend (str wt "/asl/packages/asl-utils/src/trie.asl") "\n; env\n"))
        (keyBefore (dg/memoKey wt "main"))
        (viaEnv (dg/runGateEnv (list wt "main" "--writer") "60"))
        (_ (fileAppend (str wt "/asl/packages/asl-utils/src/trie.asl") "\n; changed2\n"))
        (keyAfter (dg/memoKey wt "main"))
        (runs (toolRuns wt))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? wt)) "fixture worktree exists")
        (assert (< (gl/innerBudgetSec (gl/gateLimitSec)) (gl/gateLimitSec)) "the inner budget is strictly below the gate limit")
        (assert (= (gl/innerBudgetSec 60) 20) (str "innerBudgetSec derives from the limit and one margin: " (stringFromInt64 (gl/innerBudgetSec 60))))
        (assert (= (pairFirst first) 0) (str "a new export without a row: exit 0: " (textOf first)))
        (assert (stringContains? (textOf first) "assert docRows: no doc row the unit added or touched breaks rule docs") (str "complete answer: " (textOf first)))
        (assert (< spent 30) (str "the slow tool armed, the gate still answers well inside the 60 s limit, took " (stringFromInt64 spent)))
        (assert (= runs 0) (str "the know tool is never started: " (logOf wt)))
        (assert (= (textOf again) (textOf first)) "the repeat equals the first answer")
        (assert (< spentAgain 4) (str "the repeat is served from the memo, took " (stringFromInt64 spentAgain)))
        (assert (and (stringContains? memoText "done") (stringContains? memoFile "/.git/")) (str "the memo is in the worktree git dir: " memoFile))
        (assert (not sharedMemo) "the memo is per worktree: the git dir every worktree shares holds none (judged inside the fixture, so a checkout under ~/.asl, as admission scratches are, is no red)")
        (assert (= (pairFirst viaEnv) 0) (str "ASL_GATE_LIMIT_SEC=60 without --limit runs the gate: " (textOf viaEnv)))
        (assert (!= keyBefore keyAfter) "a changed file changes the memo key")
        (assert (and (= (dg/envLimit "0" 300) 300) (and (= (dg/envLimit "abc" 300) 300) (and (= (dg/envLimit "-5" 300) 300) (and (= (dg/envLimit "" 300) 300) (= (dg/envLimit "45" 300) 45))))) "an env limit under 1 or not a number falls back to the default")
        true))
