(module asl/tools/vcs/tests/vcsPruneTest
  :x [runTests]
  :i [(asl-tools/vcs/git :a gb) (asl-tools/fleet/run :a fr)])

; (:m :ref VCS-WORKTREE-PRUNE-VERB :do "worktreePrune! over a temp repo with two worktrees: the one whose directory is gone loses its record, the live one keeps it, and a directory that is no repo is an error")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsPruneTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! git dir: String args: (List String) -> String
  (stringTrim (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).out)

fn ! runTests -> Bool
  (let [(dir (scratch))
        (repo (str dir "/r"))
        (live (str dir "/live"))
        (stale (str dir "/stale"))
        (bare (str dir "/none"))
        (_ (pathRemove dir))
        (mk (sh "." (list "mkdir" "-p" repo bare)))
        (_ (git repo (list "init" "-q" "-b" "main")))
        (w (ok? (fileWrite (str repo "/a.txt") "0\n")))
        (_ (git repo (list "add" "-A")))
        (_ (git repo (list "commit" "-q" "-m" "c0")))
        (head (git repo (list "rev-parse" "--verify" "HEAD")))
        (al (gb/worktreeAdd! repo live "HEAD"))
        (as (gb/worktreeAdd! repo stale "HEAD"))
        (_ (pathRemove stale))
        (before (git repo (list "worktree" "list" "--porcelain")))
        (pr (gb/worktreePrune! repo))
        (after (git repo (list "worktree" "list" "--porcelain")))
        (nr (gb/worktreePrune! bare))
        (rl (gb/worktreeRemove! repo live))
        (_ (pathRemove dir))]
    (do (assert (and (= mk.exit 0) w (> (stringLength head) 0)) (str "fixture repo with one commit: mkdir exit " (stringFromInt64 mk.exit) " " mk.out " write " (str w) " head [" head "]"))
        (assert (and (= al.exit 0) (= as.exit 0)) (str "two worktrees are added: " al.out as.out))
        (assert (stringContains? before "/stale\n") (str "the stale worktree is recorded before the prune: " before))
        (assert (= pr.exit 0) (str "worktreePrune! succeeds: " pr.out))
        (assert (not (stringContains? after "/stale\n")) (str "the record of the removed directory is gone: " after))
        (assert (stringContains? after "/live\n") (str "the live worktree keeps its record: " after))
        (assert (!= nr.exit 0) (str "a directory that is no repo is an error: " nr.out))
        (assert (= rl.exit 0) (str "the live worktree is removed at the end: " rl.out))
        true))
