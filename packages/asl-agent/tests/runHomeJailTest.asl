(module aslAgent/tests/runHomeJailTest
  :x [runTests]
  :i [(aslAgent/runOps :a r) (aslAgent/core :a c) (aslAgent/jail :a jl)
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

; (:m :ref LEON-RUN-HOME-JAIL :do "B-02: the env of a unit child is an allowlist and its jail is a generated sandbox profile; the end-to-end escapes are in runOsJailTest, which also compiles on the tree before the sandbox")
fn namesOf rows: (List String) -> (List String)
  (map jl/envKey rows)

fn ! allowlistGates! root: String -> Bool
  (let [ctx (r/makeRunCtx root (list) "homeJail" 20 (list) root)
        fed (list "OPENAI_API_KEY=v" "ASL_GATEWAY_TOKEN=v" "MY_SECRET=v" "ASL_ROOT=/x" "ASL_PRELUDE=/x" "EDITOR=vi" "PATH=/usr/bin:/bin" "LANG=C" "LC_ALL=C" "HOME=/real" "ASL_FLEET_TAG=t")
        fedRows (r/spawnEnvOf! ctx root fed)
        fedNames (namesOf fedRows)
        hiddenNames (namesOf (r/spawnEnvOf! (r/makeRunCtx root (list) "homeJail" 20 (list "LANG") root) root fed))
        dropped (list "OPENAI_API_KEY" "ASL_GATEWAY_TOKEN" "MY_SECRET" "ASL_ROOT" "ASL_PRELUDE" "EDITOR")
        closed (jl/Jail :mode "os" :tool "sandbox-exec" :root "/r/unit" :writes (list "/r/unit" "/r/unit/.asl/run/agentLoop/home") :reads (list "/h/repo/.git") :lists (list "/h/work") :realHome "/h" :net false)
        open (with closed :net true)
        profile (jl/seatbeltProfile closed)
        linux (with closed :tool "/usr/bin/bwrap")
        argv (jl/bwrapArgs linux)
        netCtx (r/withNet ctx true)]
    (do
      (assert (not (listAny? (fn [n] (listContains? dropped n)) fedNames)) (str "inherited rows outside the allowlist are dropped, kept " (c/joinSep fedNames " ")))
      (assert (and (listContains? fedNames "PATH") (and (listContains? fedNames "LANG") (and (listContains? fedNames "LC_ALL") (listContains? fedNames "ASL_FLEET_TAG")))) "allowlisted rows pass")
      (assert (and (listContains? fedRows (str "HOME=" (r/jailHome root))) (not (listContains? fedRows "HOME=/real"))) "the inherited HOME is replaced by the jail home")
      (assert (not (listContains? hiddenNames "LANG")) "a name the run hides is dropped from the allowlisted rows")
      (assert (and (jl/secretName? "ASL_MODAL_API_KEY") (and (jl/secretName? "github_token") (not (jl/secretName? "PATH")))) "names that look like credentials are recognised in any case")
      (assert (not (jl/passName? "ASL_NATIVE_CLI_CACHE_KEY")) "a credential-like name never passes, even with an allowlisted prefix")
      (assert (not ctx.net) "a run context denies network by default")
      (assert netCtx.net "withNet carries the unit's :net true")
      (assert (stringContains? profile "(deny network*)") "the default profile denies network")
      (assert (stringContains? profile "(allow network-outbound (remote ip \"localhost:*\"))") "the default profile keeps loopback")
      (assert (not (stringContains? (jl/seatbeltProfile open) "network")) "a :net true profile has no network rule")
      (assert (stringContains? profile "(deny file-write*)(allow file-write* (subpath \"/r/unit\") (subpath \"/r/unit/.asl/run/agentLoop/home\")") "writes are denied and re-allowed for the root and the jail home")
      (assert (stringContains? profile "(deny file-write* (subpath \"/r/unit/.git\"))") "the root's .git is denied after the root is allowed")
      (assert (stringContains? profile "(deny file-read* (subpath \"/h\"))") "reads under the real HOME are denied")
      (assert (stringContains? profile "(allow file-read* (literal \"/h/work\"))") "an ancestor of the root is listable, not its subtree")
      (assert (= (jl/jailWrap! closed (list "/bin/sh" "-c" "true")) (list "/usr/bin/sandbox-exec" "-p" profile "/bin/sh" "-c" "true")) "the child argv is wrapped in sandbox-exec with the profile")
      (assert (= (jl/jailWrap! (jl/lexicalJail "/r/unit" false) (list "/bin/sh" "-c" "true")) (list "/bin/sh" "-c" "true")) "a lexical jail leaves the argv alone")
      (assert (and (listContains? argv "--unshare-net") (not (listContains? (jl/bwrapArgs (with linux :net true)) "--unshare-net"))) "bwrap unshares the network unless :net true")
      (assert (= (listTake argv 6) (list "/usr/bin/bwrap" "--die-with-parent" "--unshare-pid" "--ro-bind" "/" "/")) "bwrap starts from its own process namespace and a read-only file system")
      (assert (stringContains? (c/joinSep argv " ") "--tmpfs /h --ro-bind /h/repo/.git /h/repo/.git --bind /r/unit /r/unit") "bwrap hides the real HOME, then binds reads read-only and writes read-write")
      (assert (jl/denialText? "sh: x: Operation not permitted") "a seatbelt refusal is recognised in the output")
      true))

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
        cacheRows (r/jailCacheEnv! root (r/jailHome root))
        cacheKept (map pairFirst (jl/cacheSources! (list) fakeHome))
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
        allowlist (allowlistGates! root)
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
      (assert (listContains? cacheRows (str "ASL_NATIVE_CLI_CACHE=" (r/jailHome root) "/.asl/run/nativeCli")) "the child env names a private native CLI cache under the jail home, never the shared one")
      (assert (= cacheKept (list "ASL_NATIVE_CLI_CACHE")) "only a shared cache directory that exists is a read-only source")
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
