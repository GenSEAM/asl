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

fn ! runTests -> Bool
  (do (assert (testRedInCopy) "a mutant runs red in a copy and the writer's tree is untouched")
      (assert (testKilledMidGate) "a run killed mid-gate is swept at the next start")
      true)
