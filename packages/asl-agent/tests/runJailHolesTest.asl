(module aslAgent/tests/runJailHolesTest
  :x [runTests]
  :i [(aslAgent/runOps :a r) (aslAgent/aslOps :a o) (aslAgent/jail :a jl) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk) (asl-tools/fleet/run :a fr)])

; (:m :ref FABLE-BLIND-03 :do "gate of the holes the grade of a59ebb44f left open, each asserted end to end with symbols that exist before the fix, so the file compiles there and fails on the claims: a test op is a jailed unit child (no credential name, no write outside the root); the cache variables name private directories, never the shared cache the harness runs with; a unit child has no ps outside the sandbox (the outsider carries a fake mark in its command line and its environment; macOS 26.1 ps prints no environment even unsandboxed, so the command line is what turns the assertion red) and cannot signal it; a refused jail never runs the command; temporary files go under TMPDIR and the refusal says so. Every path is under one /private/tmp/leonjail-holes-<ns> directory removed at the end; the key is a fake set only on fixture processes and only the count of ps lines naming it is kept, never ps output; the outsider is a sleep that ends by itself after 90 s and is killed with its tree. The asl test op clones the machine's shared caches into the fixture root (copy-on-write, read only on the shared side), as a real unit does")
fn ! runWith! ctx: r/RunCtx cmd: String -> String
  (let [res (r/execRunOp! (c/parseKv (str "(:step :op \"run\" :argv \"" (c/escapeAsn cmd) "\")")) ctx (r/newProcs) "r1" (fn [rel pre mode] true))]
    (r/serRec res.rec))

fn ! readText! p: String -> String
  (resultOr (fileReadString p) "")

fn leaky? name: String -> Bool
  (let [up (stringUpper name)]
    (or (stringContains? up "KEY") (or (stringContains? up "TOKEN") (stringContains? up "SECRET"))))

fn linesOf text: String -> (List String)
  (filter (fn [n] (not (stringEmpty? n))) (stringSplit text "\n"))

fn evilTestText sibling: String -> String
  (str "(module evilTest\n  :x [runTests]\n  :i [])\n\n"
    "fn ! runTests -> Bool\n"
    "  (let [planted (fileWrite \"" sibling "/testop.txt\" \"planted\\n\")\n"
    "        names (fileWrite \"testopNames.txt\" (stringJoin (map (fn [r] (optionOr (listHead (stringSplit r \"=\")) r)) (envList)) \"\\n\"))]\n"
    "    (do (assert (ok? names) \"the env names were written inside the root\") true))\n")

fn ! runTests -> Bool
  (let [base (str "/private/tmp/leonjail-holes-" (stringFromInt64 (monotonicNs)))
        root (str base "/root")
        sibling (str base "/sibling")
        shared (str base "/sharedCheck")
        repo (resultOr (realPath ".") ".")
        madeDirs (and (ok? (dirCreate base)) (and (ok? (dirCreate root)) (and (ok? (dirCreate sibling)) (ok? (dirCreate shared)))))
        wroteSubject (fileWrite (str root "/subject.txt") "subject\n")
        gitRepo (gk/initGitRepo! root "leonJail" "leon-jail@example.invalid")
        fakeKey "LEONJAIL_FAKE_API_KEY=fakeNotASecret"
        ctx (r/makeRunCtx root (list) "leonJail" 60 (list) root)
        wroteEvil (fileWrite (str root "/evilTest.asl") (evilTestText sibling))
        testRun (o/runAsl repo "(:test :file \"evilTest.asl\")" root 300 (some (listAppend (envList) (list fakeKey))) "subprocess")
        testNames (linesOf (readText! (str root "/testopNames.txt")))
        testPlanted (ok? (fileStat (str sibling "/testop.txt")))
        fedRows (r/spawnEnvOf! ctx root (list "PATH=/usr/bin:/bin" (str "ASL_CHECK_CACHE=" shared)))
        checkRow (optionOr (listHead (filter (fn [row] (stringStartsWith? row "ASL_CHECK_CACHE=")) fedRows)) "")
        wroteCache (fileWrite (str root "/cache.sh") "printf %s \"$ASL_NATIVE_CLI_CACHE\" > cliRow.txt\nprintf %s \"$ASL_HOST_CACHE_DIR\" > hostRow.txt\n")
        cacheRec (runWith! ctx "sh cache.sh")
        cliRow (readText! (str root "/cliRow.txt"))
        hostRow (readText! (str root "/hostRow.txt"))
        outsiderPid (match (fr/spawn 0 (fr/job (list "/bin/sh" "-c" "sleep 90 > /dev/null 2>&1; : LEONJAIL_FAKE_MARK") base (list "PATH=/usr/bin:/bin" "LEONJAIL_FAKE_MARK=fakeNotASecret"))) ((ok run) run.pid) ((err _) 0))
        outPid (stringFromInt64 outsiderPid)
        wrotePs (fileWrite (str root "/ps.sh")
                  (str "ps axeww 2> /dev/null | grep -c \"[L]EONJAIL_FAKE\" > psAll.txt\n"
                    "kill -URG " outPid " 2> /dev/null; echo \"kill=$?\" > kill.txt\n"
                    "sleep 20 & kill $!; echo \"ownKill=$?\" > ownKill.txt\n"))
        psRec (runWith! ctx "sh ps.sh")
        psSeen (stringTrim (readText! (str root "/psAll.txt")))
        killSeen (readText! (str root "/kill.txt"))
        ownKillSeen (readText! (str root "/ownKill.txt"))
        killedTree (if (> outsiderPid 0) (fr/killTree! outsiderPid) 0)
        refused (with (jl/lexicalJail root false) :mode "refused")
        refusedArgv (jl/jailWrap! refused (list "/bin/sh" "-c" (str "echo ran > " root "/refusedRan.txt")))
        refusedRun (fr/runOneLimited (fr/job refusedArgv root (list "PATH=/usr/bin:/bin")) (fr/limits 30 16))
        refusedRan (ok? (fileStat (str root "/refusedRan.txt")))
        tmpName (str "/tmp/leonjail-holes-denied-" (stringFromInt64 (monotonicNs)))
        wroteTmp (fileWrite (str root "/tmp.sh") (str "f=$(mktemp \"$TMPDIR/leonjail.XXXXXX\") && printf %s \"$f\" > mktemp.txt\n" "echo x > " tmpName "\n"))
        tmpRec (runWith! ctx "sh tmp.sh")
        mktempSeen (readText! (str root "/mktemp.txt"))
        tmpLeft (ok? (fileStat tmpName))
        sweptTmp (pathRemove tmpName)
        home (r/jailHome root)
        cleaned (pathRemove base)]
    (do
      (assert (and madeDirs (and (and (ok? wroteSubject) gitRepo) (and (ok? wroteEvil) (and (ok? wroteCache) (and (ok? wrotePs) (ok? wroteTmp)))))) "the fixture (root repo, sibling, shared cache stand-in, scripts) was built")
      (assert (listContains? testNames "PATH") (str "the test op ran the unit's test file: exit " (stringFromInt64 (o/runExit testRun)) " " (o/runStdout testRun) " " (o/runStderr testRun)))
      (assert (= (o/runExit testRun) 0) (str "a test op that stays inside its jail passes: " (o/runStdout testRun) " " (o/runStderr testRun)))
      (assert (not (listAny? leaky? testNames)) (str "no env name of a test op child matches KEY, TOKEN or SECRET, got " (c/joinSep (filter leaky? testNames) " ")))
      (assert (listContains? testNames "ASL_ROOT") "the test op child still gets ASL_ROOT")
      (assert (not testPlanted) "a test file run by a test op cannot write outside the root")
      (assert (= checkRow (str "ASL_CHECK_CACHE=" home "/.asl/cache/check")) (str "a cache variable the harness runs with is replaced by a private directory under the jail home, got " checkRow))
      (assert (and (stringContains? cacheRec "(status \"ok\")") (= cliRow (str home "/.asl/run/nativeCli"))) (str "a run op child's native CLI cache is private to its jail home, got " cliRow " " cacheRec))
      (assert (= hostRow (str home "/.asl/run/hosts")) (str "a run op child's host cache is private to its jail home, got " hostRow))
      (assert (> outsiderPid 0) "the outsider process with the fake mark started")
      (assert (= psSeen "0") (str "ps does not run outside the sandbox for a unit child, so it shows no other process's command line or environment (ps lines naming the fake mark): " psSeen))
      (assert (and (stringContains? killSeen "kill=") (not (stringContains? killSeen "kill=0"))) (str "a unit child cannot signal a process outside its sandbox: " killSeen " " psRec))
      (assert (stringContains? ownKillSeen "ownKill=0") (str "a unit child still signals its own children: " ownKillSeen))
      (assert (not (listContains? refusedArgv (str "echo ran > " root "/refusedRan.txt"))) "a refused jail does not hand back the command")
      (assert (and (= refusedRun.exit 126) (not refusedRan)) (str "a refused jail runs nothing and exits 126, got " (stringFromInt64 refusedRun.exit)))
      (assert (stringContains? refusedRun.out "ERR_RUN_SANDBOX_ABSENT") (str "the refusal names its error: " refusedRun.out))
      (assert (stringStartsWith? mktempSeen (str home "/tmp/")) (str "mktemp in a unit child lands under the private TMPDIR, got " mktempSeen))
      (assert (not tmpLeft) "a unit child cannot create a file in the shared /tmp")
      (assert (and (stringContains? tmpRec "ERR_RUN_SANDBOX") (stringContains? tmpRec "$TMPDIR")) (str "the refusal of a /tmp write names TMPDIR: " tmpRec))
      (assert (ok? cleaned) "the fixture directory was removed")
      true))
