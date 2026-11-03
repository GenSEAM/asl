(module aslAgent/tests/runHomeJailTest
  :x [runTests]
  :i [(aslAgent/runOps :a r) (aslAgent/core :a c)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-RUN-HOME-JAIL :do "node2 2026-11-03: the repo every worktree links to was deleted while Leon units ran with the real HOME; run ops get HOME and TMPDIR inside the root and refuse rm, mv, ln, chmod, cd and git -C/--git-dir/--work-tree outside :root, absolute paths under the real HOME other than :root, rm or mv of .git, git worktree remove/prune and git gc --prune")

fn ! realHome! -> String
  (optionOr (envGet "HOME") "/nonexistent-home")

fn ! refused! cmd: String root: String -> Bool
  (some? (r/outsideRootVerdict! cmd root))

fn ! dirExists? p: String -> Bool
  (match (fileStat p) ((ok st) st.isDir) ((err _) false))

fn ! runCmd! root: String cmd: String -> String
  (let [ctx (r/makeRunCtx root (list) "homeJail" 20 (list) root)
        res (r/execRunOp! (c/parseKv (str "(:step :op \"run\" :argv \"" (c/escapeAsn cmd) "\")")) ctx (r/newProcs) "r1" (fn [rel pre mode] true))]
    (r/serRec res.rec))

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "homeJail")
        repo (gk/initGitRepo! root "homeJail" "home-jail@example.invalid")
        home (realHome!)
        ctx (r/makeRunCtx root (list) "homeJail" 20 (list) root)
        rows (r/spawnEnv! ctx root)
        outside (str root "-outside")
        madeOut (dirCreate outside)
        wroteOut (fileWrite (str outside "/keep.txt") "keep\n")
        rmOut (runCmd! root (str "rm -rf " outside "/keep.txt"))
        keptOut (resultOr (fileReadString (str outside "/keep.txt")) "")
        cacheDir (let [given (optionOr (envGet "ASL_NATIVE_CLI_CACHE") "")] (if (stringEmpty? given) (str home "/.asl/run/nativeCli") given))
        cacheRun (runCmd! root "printf %s \"$ASL_NATIVE_CLI_CACHE\" > cache.txt")
        cacheSeen (resultOr (fileReadString (str root "/cache.txt")) "")
        unreachRun (runCmd! root "test ! -e \"$HOME/asex\" && test ! -e \"$HOME/.ssh\" && test ! -e \"$HOME/.asl/mem\" && echo unreachable > unreach.txt")
        unreachSeen (resultOr (fileReadString (str root "/unreach.txt")) "")
        homeRun (runCmd! root "printf %s \"$HOME\" > home.txt")
        okRun (runCmd! root "echo fine > ok.txt")
        homeSeen (resultOr (fileReadString (str root "/home.txt")) "")
        okSeen (resultOr (fileReadString (str root "/ok.txt")) "")
        cleaned (pathRemove root)
        cleanedOut (pathRemove outside)]
    (do
      (assert (listContains? rows (str "HOME=" (r/jailHome root))) "the child HOME is the jail inside the root")
      (assert (listContains? rows (str "TMPDIR=" (r/jailHome root) "/tmp")) "the child TMPDIR is under the jail")
      (assert (not (listContains? rows (str "HOME=" home))) "the real HOME is not passed")
      (assert (= homeSeen (r/jailHome root)) (str "a command run in the root sees the jail HOME, got " homeSeen))
      (assert (stringContains? okSeen "fine") "a normal command in the root still runs")
      (assert (stringContains? rmOut "ERR_RUN_OUTSIDE_ROOT") "rm -rf of a fixture file outside the root is refused with the receipt error")
      (assert (stringContains? keptOut "keep") "the file outside the root is still there")
      (assert (or (not (dirExists? cacheDir)) (listContains? rows (str "ASL_NATIVE_CLI_CACHE=" cacheDir))) "the child env names the real native CLI cache when it exists")
      (assert (or (not (dirExists? cacheDir)) (= cacheSeen cacheDir)) "a command in the root sees the cache variable")
      (assert (stringContains? unreachSeen "unreachable") "the jail does not reach HOME/asex, HOME/.ssh or HOME/.asl/mem")
      (assert (not (listAny? (fn [r] (or (stringContains? r (str home "/.ssh")) (or (stringContains? r (str home "/asex")) (stringContains? r (str home "/.asl/mem"))))) rows)) "no env row names the real asex, .ssh or .asl/mem")
      (assert (refused! (str "rm -rf " home "/asex") root) "rm -rf $HOME-style absolute argv is refused")
      (assert (refused! "rm -rf /tmp/some-other-dir" root) "rm of an absolute path outside the root is refused")
      (assert (refused! "rm -rf ../sibling" root) "rm of a parent-relative path outside the root is refused")
      (assert (refused! "mv a.txt /tmp/b.txt" root) "mv to a path outside the root is refused")
      (assert (refused! "ln -s a /tmp/lnk" root) "ln to a path outside the root is refused")
      (assert (refused! "chmod 777 /etc/hosts" root) "chmod of a path outside the root is refused")
      (assert (refused! "cd /tmp && rm -rf x" root) "cd outside the root is refused")
      (assert (refused! "git -C /tmp/other status" root) "git -C outside the root is refused")
      (assert (refused! "git --git-dir=/tmp/o/.git log" root) "git --git-dir= outside the root is refused")
      (assert (refused! "git --work-tree /tmp/o status" root) "git --work-tree outside the root is refused")
      (assert (refused! "rm -rf .git" root) "rm of .git is refused")
      (assert (refused! "mv .git .git.bak" root) "mv of .git is refused")
      (assert (refused! "git worktree remove wt" root) "git worktree remove is refused")
      (assert (refused! "git worktree prune" root) "git worktree prune is refused")
      (assert (refused! "git prune" root) "git prune is refused")
      (assert (refused! "git gc --prune=now" root) "git gc --prune is refused")
      (assert (refused! "sh -c 'rm -rf /tmp/zz'" root) "the same inside sh -c is refused")
      (assert (refused! (str "cat " home "/asex/secret") root) "an absolute path under the real HOME outside the root is refused")
      (assert (not (refused! "rm -rf build" root)) "rm of a path inside the root is allowed")
      (assert (not (refused! "rm -rf ./a/../b" root) ) "rm of a path that stays inside the root is allowed")
      (assert (not (refused! "rm -rf $HOME/asex" root)) "rm of $HOME/x is allowed: the child HOME is the jail")
      (assert (not (refused! "./bin/asl test asl/x/tests/aTest.asl" root)) "a normal asl test command is allowed")
      (assert (not (refused! "git status" root)) "git status is allowed")
      (assert (not (refused! "git -C sub status" root)) "git -C inside the root is allowed")
      (assert (not (refused! (str "ls " root "/src") root)) "an absolute path inside the root is allowed")
      true))
