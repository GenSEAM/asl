(module asl/agentLoop/tests/gitGlobalOptsTest
  :x [runTests]
  :i [(asl/agentLoop/runOps :a r)])

; (:m :ref LEON-GIT-C-BYPASS :do "auditor: the run guard took the first non-flag word after git as the subcommand, so the value of a global option (-c user.email=x, -C dir, --git-dir d, --work-tree w) hid commit, reset and the rest; every such form is refused like the bare one, and read-only forms behind the same options stay allowed")

fn refused? cmd: String -> Bool
  (some? (r/checkRunGitGuard cmd))

fn nameOf cmd: String -> String
  (match (r/checkRunGitGuard cmd) ((some p) (pairFirst p)) ((none) ""))

fn ! runTests -> Bool
  (do
    (assert (refused? "git commit -m x") "bare git commit is refused")
    (assert (= (nameOf "git -c user.email=x commit -m y") "git commit") "git -c K=V commit is refused as git commit")
    (assert (= (nameOf "git -c a=1 -c b=2 commit -m y") "git commit") "two -c options before commit are skipped")
    (assert (= (nameOf "git -C /tmp/repo commit -m y") "git commit") "git -C DIR commit is refused")
    (assert (= (nameOf "git --git-dir .git commit -m y") "git commit") "git --git-dir DIR commit is refused")
    (assert (= (nameOf "git --git-dir=.git commit -m y") "git commit") "git --git-dir=DIR commit is refused")
    (assert (= (nameOf "git --work-tree . reset --hard") "git reset") "git --work-tree DIR reset is refused")
    (assert (= (nameOf "git --namespace n --no-pager tag v1") "git tag") "--namespace and --no-pager before tag are skipped")
    (assert (= (nameOf "git --config-env k=V commit") "git commit") "--config-env K=V before commit is skipped")
    (assert (= (nameOf "git -C . -c x=y checkout -- a.txt") "git checkout") "checkout of files behind global options is refused")
    (assert (= (nameOf "sh -c 'git -c user.name=n commit -m x'") "git commit") "the same form inside sh -c is refused")
    (assert (not (refused? "git -C . -c x=y checkout -b topic")) "checkout -b behind global options stays allowed")
    (assert (not (refused? "git -c core.pager=cat log -3")) "a read-only log behind -c stays allowed")
    (assert (not (refused? "git -C sub status")) "status behind -C stays allowed")
    true)
