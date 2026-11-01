(module asl-tools/fleet/tests/mutateTest
  :x [runTests]
  :i [(asl-tools/fleet/mutate :a mu) (asl-tools/fleet/run :a fr)])

; (:m :ref MUTANT-IN-COPY :do "a fixture repo whose writer worktree has a committed file, an uncommitted edit and an untracked file: the mutant runs in a copy that sees all three, goes red there, and leaves the writer's tree byte for byte; a run killed mid-gate leaves its copy, which the next start sweeps; scratch dirs live under this worktree's .asl/cache")

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/mutateTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! git dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))) (fr/limits 60 8))

fn ! snapshot wt: String -> String
  (str (git wt (list "status" "--porcelain" "--untracked-files=all")).out "\n" (git wt (list "diff" "HEAD")).out "\n" (resultOr (fileReadString (str wt "/f.txt")) "") (resultOr (fileReadString (str wt "/u.txt")) ""))

fn ! fixture! root: String -> String
  (let [(wt (str root "/repo"))
        (_ (dirCreate wt))
        (_ (git wt (list "init" "--quiet" "-b" "main")))
        (_ (fileWrite (str wt "/f.txt") "a = 1\n"))
        (_ (git wt (list "add" "f.txt")))
        (_ (git wt (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "--quiet" "-m" "c0")))
        (_ (fileWrite (str wt "/f.txt") "a = 1\nb = 1\n"))
        (_ (fileWrite (str wt "/u.txt") "untracked\n"))]
    wt)

fn gate -> String
  "grep -q 'a = 1' f.txt && grep -q 'b = 1' f.txt && test -f u.txt && echo '3 assertion(s) executed (3 passed)'"

fn ! waitFor! path: String tries: Int64 -> Bool
  (cond ((fileExists? path) true) ((<= tries 0) false) (else (do (sleepMs 100) (waitFor! path (- tries 1)))))

fn ! testRedInCopy -> Bool
  (let [(root (scratch "red"))
        (_ (cleanup root))
        (wt (fixture! root))
        (sc (str root "/mutants"))
        (before (snapshot wt))
        (same (mu/mutantRun! wt sc (mu/mutant "f.txt" "b = 1" "b = 1") (gate) (fr/limits 60 16)))
        (red (mu/mutantRun! wt sc (mu/mutant "f.txt" "a = 1" "a = 2") (gate) (fr/limits 60 16)))
        (absent (mu/mutantRun! wt sc (mu/mutant "f.txt" "zzz" "y") (gate) (fr/limits 60 16)))
        (after (snapshot wt))
        (left (mu/mutantDirs! sc))
        (listed (git wt (list "worktree" "list")))
        (_ (cleanup root))]
    (do (assert (and same.applied (= same.exit 0) (= same.executed 3)) (str "the copy holds the commit, the uncommitted edit and the untracked file: " same.out))
        (assert (and red.applied (!= red.exit 0)) (str "the mutant goes red in the copy: " red.out))
        (assert (and (not absent.applied) (stringContains? absent.out "mutantNotApplied")) (str "a mutant whose text is absent is not run: " absent.out))
        (assert (= before after) "the writer's worktree is unchanged byte for byte")
        (assert (listEmpty? left) (str "every copy is removed: " left))
        (assert (not (stringContains? listed.out "/mutants/mut-")) (str "no copy stays registered: " listed.out))
        true))

fn ! testKilledMidGate -> Bool
  (let [(root (scratch "kill"))
        (_ (cleanup root))
        (wt (fixture! root))
        (sc (str root "/mutants"))
        (marker (str root "/inGate"))
        (before (snapshot wt))
        (slow (str "touch '" marker "'; sleep 30"))
        (killed (match (fr/forkLimited! (str root "/child.log") (fr/limits 60 64)
                         (fn [] -> Int64 (let [(o (mu/mutantRun! wt sc (mu/mutant "f.txt" "a = 1" "a = 2") slow (fr/limits 60 16)))] o.exit)))
                  ((ok f) (let [(up (waitFor! marker 200))] (pair up (fr/forkKill! f "test"))))
                  ((err e) (pair false (fr/ForkEnd :exit -2 :verdict "forkFailed" :desc 0 :note e)))))
        (kend (pairSecond killed))
        (mid (snapshot wt))
        (stale (mu/mutantDirs! sc))
        (next (mu/mutantRun! wt sc (mu/mutant "f.txt" "b = 1" "b = 1") (gate) (fr/limits 60 16)))
        (after (snapshot wt))
        (left (mu/mutantDirs! sc))
        (listed (git wt (list "worktree" "list")))
        (_ (cleanup root))]
    (do (assert (pairFirst killed) "the forked run reached its gate before the kill")
        (assert (= kend.verdict "test") (str "the run was killed: " kend.note))
        (assert (= before mid) "a run killed mid-gate leaves the writer's worktree unchanged")
        (assert (= (listLength stale) 1) (str "the killed run's copy is left behind: " stale))
        (assert (and next.applied (= next.exit 0)) (str "the next run works: " next.out))
        (assert (listEmpty? left) (str "the next start swept the stale copy: " left))
        (assert (not (stringContains? listed.out "/mutants/mut-")) (str "its registration is pruned: " listed.out))
        (assert (= before after) "still unchanged after the sweep")
        true))

fn ! fixtureCli! root: String -> String
  (let [(wt (str root "/repo"))
        (_ (dirCreate (str wt "/src")))
        (_ (git wt (list "init" "--quiet" "-b" "main")))
        (_ (fileWrite (str wt "/f.txt") "a = 1\n"))
        (_ (fileWrite (str wt "/src/cli.txt") "c = 1\n"))
        (_ (git wt (list "add" "f.txt" "src/cli.txt")))
        (_ (git wt (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "--quiet" "-m" "c0")))]
    wt)

fn ! lineCount! path: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString path) ""))))

; (:m :ref MUTANT-INVALID :do "a nonzero exit is red only when an assertion ran or failed: a mutant that does not parse or check, and a gate killed before its first assertion, are invalid and not red; a passing gate is pass and a mutant not found is notApplied")
fn ! testVerdicts -> Bool
  (let [(root (scratch "verdict"))
        (_ (cleanup root))
        (wt (fixture! root))
        (sc (str root "/mutants"))
        (m (mu/mutant "f.txt" "a = 1" "a = 2"))
        (load (mu/mutantRun! wt sc m "echo \"FAIL t.asl: t.asl:1:1: parse unclosed ( at end of file (after 0 asserts)\"; exit 1" (fr/limits 60 16)))
        (killed (mu/mutantRun! wt sc m "exit 125" (fr/limits 60 16)))
        (assertFail (mu/mutantRun! wt sc m "echo \"t.asl:5:9: ERR_ASSERT: assertion failed: x\"; echo \"FAIL t.asl: ERR_ASSERT: assertion failed: x (after 0 asserts)\"; exit 1" (fr/limits 60 16)))
        (late (mu/mutantRun! wt sc m "echo \"FAIL t.asl: t.asl:9:9: ERR_ARITY (after 7 asserts)\"; exit 1" (fr/limits 60 16)))
        (pass (mu/mutantRun! wt sc m "echo \"1 assertion(s) executed (1 passed)\"" (fr/limits 60 16)))
        (absent (mu/mutantRun! wt sc (mu/mutant "f.txt" "zzz" "y") (gate) (fr/limits 60 16)))
        (_ (cleanup root))]
    (do (assert (and load.applied (= load.verdict "invalid") (not load.red)) (str "a mutant that does not load is invalid, not red: " load.verdict))
        (assert (and (= killed.verdict "invalid") (not killed.red)) (str "a gate killed before any assertion is invalid: " killed.verdict))
        (assert (and assertFail.red (= assertFail.verdict "red")) (str "a failed assertion is red: " assertFail.verdict))
        (assert (and late.red (= late.executed 7)) (str "an error after assertions ran is red: " late.verdict))
        (assert (and (= pass.verdict "pass") (not pass.red)) (str "a passing gate is pass: " pass.verdict))
        (assert (and (not absent.applied) (= absent.verdict "notApplied") (not absent.red)) "a mutant not found is notApplied and not red")
        true))

fn stubGate cache: String count: String -> String
  (str "H='" cache "/head'$(pwd -P | tr / _); if test -r \"$H\"; then echo pinned; else echo built >> '" count "'; fi; echo '1 assertion(s) executed (1 passed)'")

; (:m :ref MUTANT-SHARED-CLI :do "a stub builder (the gate builds when the copy has no head pointer in the cache and counts it) is called 0 times for a mutant and an uncommitted change outside the deps of the pinned CLI, whose pointer is read from the writer's tree; it is called for a mutated deps file, for a writer's uncommitted deps file, and without a pin; the copy's pointer is removed after each run and the writer's pointer is untouched")
fn ! testPinnedCli -> Bool
  (let [(root (scratch "pin"))
        (_ (cleanup root))
        (wt (fixtureCli! root))
        (sc (str root "/mutants"))
        (cache (str root "/cache"))
        (pinDir (str root "/pin"))
        (count (str root "/builds"))
        (g (stubGate cache count))
        (m (mu/mutant "f.txt" "a = 1" "a = 2"))
        (nopin (mu/mutantRunIn! wt sc cache m g (fr/limits 60 16)))
        (n0 (lineCount! count))
        (_ (dirCreate cache))
        (_ (dirCreate pinDir))
        (_ (fileWrite (str pinDir "/bin") "x"))
        (_ (fileWrite (str pinDir "/deps") "src/cli.txt\nasl/seed\n"))
        (head (mu/headFile cache (resultOr (realPath wt) wt)))
        (_ (fileWrite head (str pinDir "\n")))
        (reuse (mu/mutantRunIn! wt sc cache m g (fr/limits 60 16)))
        (n1 (lineCount! count))
        (hit (mu/mutantRunIn! wt sc cache (mu/mutant "src/cli.txt" "c = 1" "c = 2") g (fr/limits 60 16)))
        (n2 (lineCount! count))
        (sub (mu/mutantRunIn! wt sc cache (mu/mutant "src/cli.txt" "c = 1" "c = 1") g (fr/limits 60 16)))
        (_ (fileWrite (str wt "/src/cli.txt") "c = 1\nd = 1\n"))
        (dirty (mu/mutantRunIn! wt sc cache m g (fr/limits 60 16)))
        (n3 (lineCount! count))
        (_ (fileWrite (str wt "/src/cli.txt") "c = 1\n"))
        (_ (fileWrite (str wt "/untracked.txt") "u\n"))
        (untr (mu/mutantRunIn! wt sc cache m g (fr/limits 60 16)))
        (n4 (lineCount! count))
        (_ (fileWrite head "/nonexistent\n"))
        (missing (mu/pinOf! cache wt))
        (stale (str sc "/mut-4100123-1"))
        (_ (dirCreate stale))
        (_ (dirCreate (str sc "/heads")))
        (_ (fileWrite (str sc "/heads/mut-4100123-1") (str cache "/headstale")))
        (_ (fileWrite (str cache "/headstale") "x\n"))
        (swept (mu/sweepIn! sc wt cache))
        (heads (filter (fn [(n String)] -> Bool (stringStartsWith? n "head")) (resultOr (dirList cache) (list))))
        (left (mu/mutantDirs! sc))
        (_ (cleanup root))]
    (do (assert (and (= nopin.cli "cold") (= n0 1)) (str "without a pin the copy builds: " nopin.cli " " n0))
        (assert (and reuse.applied (= reuse.exit 0) (= reuse.cli "pinned") (= n1 1)) (str "a mutant outside the deps reuses the pinned CLI, 0 builder calls: " reuse.cli " " n1))
        (assert (and (= hit.cli "cold") (= n2 2)) (str "a mutated deps file builds: " hit.cli " " n2))
        (assert (= sub.cli "cold") "a deps file under a listed name counts, even when the text is unchanged")
        (assert (and (= dirty.cli "cold") (= n3 4)) (str "an uncommitted deps file of the writer builds: " dirty.cli " " n3))
        (assert (and (= untr.cli "pinned") (= n4 4)) (str "an untracked file outside the deps still reuses: " untr.cli " " n4))
        (assert (= heads (list (optionOr (stringSlice head (+ (stringLength cache) 1) (stringLength head)) ""))) (str "only the writer's pointer remains in the cache: " heads))
        (assert (listEmpty? left) "every copy is removed")
        (assert (stringEmpty? missing) (str "a pointer to a build dir that is gone is no pin: " missing))
        (assert (and (= swept 1) (not (fileExists? (str cache "/headstale"))) (not (fileExists? (str sc "/heads/mut-4100123-1")))) "the sweep removes a killed run copy together with its head pointer")
        (assert (and (mu/seedable "p" (list "a") (list "b")) (not (mu/seedable "p" (list "a") (list "a/x"))) (not (mu/seedable "" (list "a") (list "b"))) (not (mu/seedable "p" (list) (list "b")))) "seedable: a pin, a deps list and no changed deps file")
        true))

fn ! testVerdictOf -> Bool
  (let [(quoted (mu/verdictOf 1 0 "note: the text ERR_ASSERT is only quoted here
"))
        (laterDies (mu/verdictOf 1 5 "t1.asl: 5 assertion(s) executed (5 passed)
suite two died with no FAIL line
"))
        (assertFail (mu/verdictOf 1 0 "t.asl:5:9: ERR_ASSERT: assertion failed: x
FAIL t.asl: ERR_ASSERT: assertion failed: x (after 0 asserts)
"))
        (secondFails (mu/verdictOf 1 2 "t1.asl: 5 assertion(s) executed (5 passed)
FAIL t2.asl: ERR_ASSERT: assertion failed: y (after 2 asserts)
"))
        (lateError (mu/verdictOf 1 7 "FAIL t.asl: t.asl:9:9: ERR_ARITY (after 7 asserts)
"))
        (loadError (mu/verdictOf 1 0 "FAIL t.asl: t.asl:1:1: parse unclosed ( (after 0 asserts)
"))
        (pass (mu/verdictOf 0 3 "3 assertion(s) executed (3 passed)
"))]
    (do (assert (= quoted "invalid") (str "ERR_ASSERT quoted with 0 executed is invalid: " quoted))
        (assert (= laterDies "invalid") (str "a later suite dying after an earlier suite's assertions is invalid: " laterDies))
        (assert (= assertFail "red") (str "a FAIL line with ERR_ASSERT is red: " assertFail))
        (assert (= secondFails "red") (str "a second suite failing an assertion is red: " secondFails))
        (assert (= lateError "red") (str "a FAIL after executed assertions is red: " lateError))
        (assert (= loadError "invalid") (str "a load error with 0 executed is invalid: " loadError))
        (assert (= pass "pass") (str "exit 0 is pass: " pass))
        true))

fn ! testDropHeadScope -> Bool
  (let [(root (scratch "dropscope"))
        (_ (cleanup root))
        (wt (fixture! root))
        (sc (str root "/mutants"))
        (cache (str root "/cache"))
        (outside (str root "/outside.txt"))
        (inside (str cache "/headx"))
        (_ (dirCreate cache))
        (_ (dirCreate (str sc "/heads")))
        (_ (dirCreate (str sc "/mut-4100124-1")))
        (_ (dirCreate (str sc "/mut-4100125-1")))
        (_ (dirCreate (str sc "/mut-4100126-1")))
        (_ (fileWrite outside "keep
"))
        (_ (fileWrite inside "x
"))
        (_ (fileWrite (str sc "/heads/mut-4100124-1") outside))
        (_ (fileWrite (str sc "/heads/mut-4100125-1") inside))
        (_ (fileWrite (str sc "/heads/mut-4100126-1") (str cache "/../outside.txt")))
        (swept (mu/sweepIn! sc wt cache))
        (journal (resultOr (fileReadString (str sc "/headSkips.log")) ""))
        (kept (fileExists? outside))
        (gone (not (fileExists? inside)))
        (markers (filter (fn [(n String)] -> Bool (stringStartsWith? n "mut-")) (resultOr (dirList (str sc "/heads")) (list))))
        (_ (cleanup root))]
    (do (assert (= swept 3) (str "all three stale copies are swept: " swept))
        (assert kept "a marker naming a path outside the cache dir removes nothing")
        (assert gone "a marker naming a file under the cache dir removes it")
        (assert (listEmpty? markers) "every marker is removed")
        (assert (and (stringContains? journal outside) (stringContains? journal "mut-4100124-1") (stringContains? journal "mut-4100126-1") (not (stringContains? journal "mut-4100125-1"))) (str "each skipped path is journaled once, the removed one is not: " journal))
        true))
fn ! runTests -> Bool
  (do (assert (testRedInCopy) "a mutant runs red in a copy and the writer's tree is untouched")
      (assert (testKilledMidGate) "a run killed mid-gate is swept at the next start")
      (assert (testVerdicts) "an invalid mutant is never red")
      (assert (testPinnedCli) "a non-CLI mutant reuses the pinned CLI")
      (assert (testVerdictOf) "red needs a runner FAIL line")
      (assert (testDropHeadScope) "a head marker removes only under the cache dir")
      true)
