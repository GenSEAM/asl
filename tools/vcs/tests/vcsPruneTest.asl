(module asl/tools/vcs/tests/vcsPruneTest
  :x [runTests]
  :i [(asl-tools/vcs/git :a gb) (asl-tools/fleet/run :a fr)])

; (:m :ref VCS-WORKTREE-PRUNE-VERB :do "worktreePrune! over a temp repo with two worktrees: the one whose directory is gone loses its record, the live one keeps it, and a directory that is no repo is an error")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsPruneTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! gitDone dir: String args: (List String) -> fr/Done
  (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args))

fn ! git dir: String args: (List String) -> String
  (stringTrim (gitDone dir args).out)

; (:m :ref VCSPRUNE-FLAKE-CAUSE :do "one fixture step as name, exit, fleet verdict (exit, or timeout or runaway when the bound killed it) and output, so a red fixture names the step that failed")
fn step name: String d: fr/Done -> String
  (str "(" name " :exit " (stringFromInt64 d.exit) " :verdict \"" d.verdict "\" :out \"" (stringTrim d.out) "\") ")

fn ok d: fr/Done -> Bool
  (and (= d.exit 0) (= d.verdict "exit"))

fn hexChar? c: String -> Bool
  (stringContains? "0123456789abcdef" c)

fn sha? s: String -> Bool
  (and (= (stringLength s) 40) (listAll? hexChar? (stringChars s)))

fn ! runTests -> Bool
  (let [(dir (scratch))
        (repo (str dir "/r"))
        (live (str dir "/live"))
        (stale (str dir "/stale"))
        (bare (str dir "/none"))
        (_ (pathRemove dir))
        (mk (sh "." (list "mkdir" "-p" repo bare)))
        (gi (gitDone repo (list "init" "-q" "-b" "main")))
        (w (ok? (fileWrite (str repo "/a.txt") "0\n")))
        (ga (gitDone repo (list "add" "-A")))
        (gc (gitDone repo (list "commit" "-q" "-m" "c0")))
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
    (do (assert (and (ok mk) (and w (and (ok gi) (and (ok ga) (and (ok gc) (sha? head)))))) (str "fixture repo with one commit: " (step "mkdir" mk) (step "init" gi) "(write " (if w "ok" "failed") ") " (step "add" ga) (step "commit" gc) "(head \"" head "\")"))
        (assert (and (= al.exit 0) (= as.exit 0)) (str "two worktrees are added: " al.out as.out))
        (assert (stringContains? before "/stale\n") (str "the stale worktree is recorded before the prune: " before))
        (assert (= pr.exit 0) (str "worktreePrune! succeeds: " pr.out))
        (assert (not (stringContains? after "/stale\n")) (str "the record of the removed directory is gone: " after))
        (assert (stringContains? after "/live\n") (str "the live worktree keeps its record: " after))
        (assert (!= nr.exit 0) (str "a directory that is no repo is an error: " nr.out))
        (assert (= rl.exit 0) (str "the live worktree is removed at the end: " rl.out))
        true))
