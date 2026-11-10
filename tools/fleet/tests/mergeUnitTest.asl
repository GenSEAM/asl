(module asl/tools/fleet/tests/mergeUnitTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/mergeUnit :a mu) (asl-tools/vcs/git :a vg) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref BASH-EXIT-MERGE :do "mergeUnit on a temp repo built through gitInitKit and the vcs module: a green gate merges, a gate red in the worktree and on main is BASE-RED and merges, a gate red in the worktree and green on main is NEW-RED and blocks, a main that moved before the merge is rebased onto and the merge lands on the retry, a failing audit blocks, and waitPid! returns only once the pid is gone; nothing touches the real main or ~/.asl (lock and logs live in the temp dir)")

fn ! write path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! commitIn! dir: String file: String text: String -> Bool
  (let [(w (write (str dir "/" file) text))
        (tx (vg/prepare! dir (list file)))]
    (and w (and tx.ok (= (vg/finish! dir tx (str "add " file) (list file)).exit 0))))

fn ! addUnit! main: String wtRoot: String briefs: String unit: String file: String gates: String -> Bool
  (let [(wt (str wtRoot "/asex-" unit))
        (a (vg/worktreeAdd! main wt "HEAD"))
        (s (vg/switch! wt (str "fix/" unit) "main"))
        (c (commitIn! wt file (str unit "\n")))
        (b (write (str briefs "/" unit "-leon.asn") (str "(:brief :task \"t\" :owns (\"" file "\") :gates (" gates "))\n")))]
    (and (= a.exit 0) (and (= s.exit 0) (and c b))))

fn ! logOf path: String -> String
  (resultOr (fileReadString path) "")

fn has? text: String event: String -> Bool
  (stringContains? text (str ":event :" event))

fn ! runTests -> Bool
  (let [(tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/mergeUnitTest" (stringFromInt64 (nowNs))))
        (main (str tmp "/main"))
        (wtRoot (str tmp "/wt"))
        (briefs (str tmp "/briefs"))
        (dirs (and (ok? (dirCreate main)) (and (ok? (dirCreate wtRoot)) (ok? (dirCreate briefs)))))
        (base (write (str main "/base.txt") "base\n"))
        (init (gk/initGitRepoWith! main "mergeUnitTest" "merge-unit@example.invalid" (list "base.txt")))
        (ua (addUnit! main wtRoot briefs "a" "a.txt" "\"test -f a.txt\""))
        (ub (addUnit! main wtRoot briefs "b" "b.txt" "\"test -f nothere.txt\" \"test -f b.txt\""))
        (uc (addUnit! main wtRoot briefs "c" "c.txt" "\"test ! -f c.txt\""))
        (ud (addUnit! main wtRoot briefs "d" "d.txt" "\"test -f d.txt\""))
        (ue (addUnit! main wtRoot briefs "e" "e.txt" "\"test -f e.txt\""))
        (cfg (with (mu/defaultCfg) :main main :worktrees wtRoot :briefDir briefs :lock (str tmp "/mainbuild.lock") :audit "none" :gateSecs 60))
        (logA (str tmp "/a.log"))
        (okA (mu/mergeUnit! (with cfg :log logA) "a"))
        (la (logOf logA))
        (logB (str tmp "/b.log"))
        (okB (mu/mergeUnit! (with cfg :log logB) "b"))
        (lb (logOf logB))
        (logC (str tmp "/c.log"))
        (okC (mu/mergeUnit! (with cfg :log logC) "c"))
        (lc (logOf logC))
        (logD (str tmp "/d.log"))
        (okD (mu/mergeUnitWith! (with cfg :log logD) "d" (fn [] (commitIn! main "moved.txt" "moved\n"))))
        (ld (logOf logD))
        (logE (str tmp "/e.log"))
        (okE (mu/mergeUnit! (with (with cfg :log logE) :audit "echo audit consistency: failed") "e"))
        (le (logOf logE))
        (pidOut (fr/runOneLimited (fr/job (list "sh" "-c" "sleep 1 >/dev/null 2>&1 & echo $!") "." (fr/childEnv (list))) (fr/limits 20 8)))
        (pid (optionOr (stringToInt64 (stringTrim pidOut.out)) 0))
        (aliveBefore (resultOr (procAlive? pid) false))
        (gone (mu/waitPid! pid 30))
        (aliveAfter (resultOr (procAlive? pid) false))
        (cleaned (ok? (pathRemove tmp)))]
    (do
      (assert (and dirs (and base init)) "the temp main repo is built through gitInitKit")
      (assert (and ua (and ub (and uc (and ud ue)))) "the unit worktrees and briefs are built through the vcs module")
      (assert (and okA (has? la "MERGED") (has? la "GATE") (not (has? la "BASE-RED"))) "a green gate merges")
      (assert (and okB (has? lb "BASE-RED") (has? lb "MERGED") (not (has? lb "NEW-RED"))) "a gate red on main too is BASE-RED and does not block the merge")
      (assert (and (not okC) (has? lc "NEW-RED") (has? lc "GATE-FAIL") (not (has? lc "MERGED"))) "a gate red in the worktree and green on main is NEW-RED and blocks")
      (assert (and okD (has? ld "REBASED-ONTO-MOVED-MAIN") (has? ld "MERGED")) "a main that moved before the merge is rebased onto and the merge lands on the retry")
      (assert (and (not okE) (has? le "AUDIT-FAIL") (not (has? le "MERGED"))) "a failing audit blocks the merge")
      (assert (and aliveBefore gone (not aliveAfter)) "waitPid! returns once the pid is gone")
      (assert cleaned "the temp tree is removed")
      true))
