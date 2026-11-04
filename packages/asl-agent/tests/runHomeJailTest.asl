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


fn ! passed! cmds: (List String) root: String -> (List String)
  (if (listEmpty? cmds)
    (list)
    (if (refused! (c/firstOf cmds) root) (passed! (c/restOf cmds) root) (cons (c/firstOf cmds) (passed! (c/restOf cmds) root))))

fn ! blocked! cmds: (List String) root: String -> (List String)
  (if (listEmpty? cmds)
    (list)
    (if (refused! (c/firstOf cmds) root) (cons (c/firstOf cmds) (blocked! (c/restOf cmds) root)) (blocked! (c/restOf cmds) root)))

fn bypassCmds -> (List String)
  (list "rm -rf ~pi/asex" "rm -rf $PWD/.." "rm -rf \"$(dirname $PWD)\"" "rm -rf `dirname $PWD`" "rm -rf $UNSET/x" "echo $(rm -rf ../x)"
    "find .. -delete" "find ../x -exec rm -rf {} +" "find . -exec rm -rf ../x {} +" "find . -exec sh -c 'rm -rf ../x' ;" "echo ../x | xargs rm -rf" "git ls-files | xargs -I{} rm {}"
    "rsync --delete e/ ../x/" "rsync -a --remove-source-files ../x e/" "unlink ../x" "rmdir ../x" "truncate -s0 ../x/f" "dd if=a of=../x" "cp a ../x" "cp -t ../x a" "install a ../x" "echo a | tee ../x/f" "mkdir ../x" "touch ../x/f"
    "eval rm -rf ../x" "bash -lc 'rm -rf ../x'" "sh -ec 'rm -rf ../x'" "zsh -xc 'rm -rf /tmp/zz'"
    "python3 -c \"import shutil; shutil.rmtree('../x')\"" "python3 -c \"import shutil; shutil.rmtree('/tmp/zzz')\"" "python3 -c \"import os; print(os.path.expanduser('~'))\"" "perl -e 'unlink \"../x\"'" "ruby -e 'p ENV[\"HOME\"]'" "node -e 'process.chdir(\"..\")'"
    "nice -n 19 rm -rf ../x" "env -i rm -rf ../x" "env -u FOO rm -rf ../x" "timeout 5 rm -rf ../x" "timeout -s KILL 5 rm -rf ../x" "sudo -u x rm -rf ../x" "nohup rm -rf ../x" "stdbuf -oL rm -rf ../x" "ionice -c 3 rm -rf ../x" "FOO=1 rm -rf ../x"
    "GIT_WORK_TREE=../x git clean -fdx" "GIT_DIR=/tmp/x git status" "env GIT_DIR=../x git status" "git -c core.worktree=../x clean -fdx"
    "rm -rf link/*" "rm -rf link/" "echo rm -rf ../x | bash" "echo rm -rf ../x | sh" "echo rm -rf ../x | sh -s" "cat x | python3" "cat x | python3 -" "echo x | perl" "bash <<EOF" "sh < x.sh" "echo y | sudo -u x bash")

fn stillAllowed -> (List String)
  (list "rm -rf build" "rm build/a.o" "rm -rf $PWD/build" "rm -rf ~/x" "find . -name '*.o'" "find . -name x -delete" "find . -exec rm {} +" "find .. -name x" "rsync -a --delete e/ out/" "rsync -a ../x e/"
    "cp a b" "cp -t sub a" "install a sub/b" "echo x | tee out.txt" "dd if=a of=b" "mkdir -p a/b" "touch a" "truncate -s0 f" "rmdir a" "unlink a"
    "python3 -c 'print(1)'" "python3 -c \"print(1 / 2)\"" "perl -e 'print 1..3'" "node -e 'console.log(1)'" "bash -lc 'rm -rf build'" "sh -ec 'echo hi'" "eval rm -rf build" "echo $(date)"
    "nice -n 19 rm -rf build" "env -i rm -rf build" "timeout 5 rm -rf build" "sudo -u x rm -rf build" "nohup rm -rf build" "stdbuf -oL cat a" "FOO=1 rm -rf build"
    "echo hi | cat" "git log | head" "bash build.sh" "python3 gen.py" "python3 --version" "xargs echo" "echo a | xargs echo" "git status" "git -c user.name=x status" "GIT_DIR=.git git status" "GIT_WORK_TREE=. git status" "git -C sub status" "rm link")

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
        fakeHome (str root "-fakeHome")
        madeFake (and (ok? (dirCreate fakeHome)) (and (ok? (dirCreate (str fakeHome "/.asl"))) (and (ok? (dirCreate (str fakeHome "/.asl/run"))) (ok? (dirCreate (str fakeHome "/.asl/run/nativeCli"))))))
        cacheRows (r/jailCacheEnv! root fakeHome (list))
        cacheKept (r/jailCacheEnv! root fakeHome (list "ASL_NATIVE_CLI_CACHE"))
        linkOut (str root "-linkTarget")
        madeLinkOut (dirCreate linkOut)
        madeLink (pathSymlink linkOut (str root "/link"))
        missed (blocked! (stillAllowed) root)
        slipped (passed! (bypassCmds) root)
        unreachRun (runCmd! root "test ! -e \"$HOME/asex\" && test ! -e \"$HOME/.ssh\" && test ! -e \"$HOME/.asl/mem\" && echo unreachable > unreach.txt")
        unreachSeen (resultOr (fileReadString (str root "/unreach.txt")) "")
        homeRun (runCmd! root "printf %s \"$HOME\" > home.txt")
        okRun (runCmd! root "echo fine > ok.txt")
        homeSeen (resultOr (fileReadString (str root "/home.txt")) "")
        okSeen (resultOr (fileReadString (str root "/ok.txt")) "")
        cleaned (pathRemove root)
        cleanedOut (pathRemove outside)
        cleanedFake (pathRemove fakeHome)
        cleanedLink (pathRemove linkOut)]
    (do
      (assert (listContains? rows (str "HOME=" (r/jailHome root))) "the child HOME is the jail inside the root")
      (assert (listContains? rows (str "TMPDIR=" (r/jailHome root) "/tmp")) "the child TMPDIR is under the jail")
      (assert (not (listContains? rows (str "HOME=" home))) "the real HOME is not passed")
      (assert (= homeSeen (r/jailHome root)) (str "a command run in the root sees the jail HOME, got " homeSeen))
      (assert (stringContains? okSeen "fine") "a normal command in the root still runs")
      (assert (stringContains? rmOut "ERR_RUN_OUTSIDE_ROOT") "rm -rf of a fixture file outside the root is refused with the receipt error")
      (assert (stringContains? keptOut "keep") "the file outside the root is still there")
      (assert madeFake "the fake real HOME with a native CLI cache was created")
      (assert (listContains? cacheRows (str "ASL_NATIVE_CLI_CACHE=" fakeHome "/.asl/run/nativeCli")) "the child env names the real native CLI cache when it exists")
      (assert (and (not (listAny? (fn [r] (stringStartsWith? r "ASL_HOST_CACHE_DIR=")) cacheRows)) (not (listAny? (fn [r] (stringStartsWith? r "ASL_NATIVE_CLI_CACHE=")) cacheKept))) "a cache directory that is absent or already set is not named")
      (assert (and (ok? madeLinkOut) (ok? madeLink)) "the symlink fixture inside the root exists")
      (assert (listEmpty? slipped) (str "every outside-root bypass is refused, still allowed: " (c/joinSep slipped " | ")))
      (assert (listEmpty? missed) (str "ordinary in-root work is not refused, wrongly refused: " (c/joinSep missed " | ")))
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
