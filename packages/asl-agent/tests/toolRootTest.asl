(module aslAgent/tests/toolRootTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (asl-json/json :a j)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-TOOLROOT :do "a worktree whose native CLI is stale (its bin/asl answers ERR_NATIVE_STALE) with :toolRoot naming a good tree: the check op runs <toolRoot>/bin/asl with the run root as cwd and the stale tree's bin/asl is never run; without :toolRoot the op fails ERR_NATIVE_STALE as before; the stale tree is a symlink clone of this checkout with bin/asl replaced; the good tree is a clone whose bin/asl logs and execs this checkout; the run carries :wallBudget 240 so a run rooted in it by mistake ends by its budget and fails the asserts")

fn ! linkEntries! from: String to: String skip: (List String) -> Bool
  (listAll? (fn [n] (or (listAny? (fn [k] (= k n)) skip) (ok? (pathSymlink (str from "/" n) (str to "/" n)))))
    (resultOr (dirList from) (list "?")))

fn ! cloneTree! dir: String repo: String script: String -> Bool
  (and (ok? (dirCreate (str dir "/bin")))
    (and (linkEntries! repo dir (list "bin" ".asl" ".git"))
      (and (linkEntries! (str repo "/bin") (str dir "/bin") (list "asl"))
        (and (ok? (fileWrite (str dir "/bin/asl") script))
          (ok? (fileChmod (str dir "/bin/asl") 493))))))

fn ! runWith! tag: String stale: String tool: String -> String
  (let [root (rk/freshRecorderRoot! tag)
        w (fileWrite (str root "/subject.txt") "red\n")
        repo (gk/initGitRepo! root "toolRoot" "tool-root@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        d (dirCreate fixtureDir)
        f (fileWrite (str fixtureDir "/t" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "t" tag) (list "(:step :op \"check\" :file \"subject.txt\")" "(:step :op \"write\" :file \"new.txt\" :content \"made\")" "(:step :op \"edit\" :file \"subject.txt\" :old \"red\" :new \"green\")" "(:step :op \"write\" :file \"other.txt\" :content \"nope\")" "(:done)")))
        form (str "(:agent :task \"check subject\" :backend \"script/t" tag "\" :root \"" (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\" \"new.txt\") :budget 8 :wallBudget 240 :contextTokens 8000"
               (if (stringEmpty? tool) "" (str " :toolRoot \"" (c/escapeAsn tool) "\"")) ")")
        res (m/mainWithRoots (list form) stale root)
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        jn (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? jn) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" jn)) ""))]
    (str root "\n" res.stdout "\n" text))

fn ! walk! dir: String -> (List String)
  (listFlatMap (fn [n] (let [p (str dir "/" n)
                         st (fileLstat p)]
                     (cons p (match st
                               ((ok x) (if (and x.isDir (not x.isSymlink)) (walk! p) (list)))
                               ((err _) (list))))))
    (resultOr (dirList dir) (list)))

; (:m :ref TOOLROOT-59-FLAKE :do "the checkout .asl is listed whole except the dirs and files other runs write while this test runs (cache holds the native CLI builds and test caches, ratchet.lock the gate lock), so a suite running beside this one cannot turn the listing red; a dry run that wrote anywhere else under .asl still does")
fn sharedAsl -> (List String)
  (list "cache" "ratchet.lock")

fn ! aslWatch! repo: String -> (List String)
  (map (fn [n] (str repo "/.asl/" n))
    (filter (fn [n] (not (listContains? (sharedAsl) n))) (resultOr (dirList (str repo "/.asl")) (list))))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        base (str (optionOr (envGet "TMPDIR") "/tmp") "/toolRootTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))
        stale (str base "/stale")
        good (str base "/good")
        staleLog (str base "/stale.log")
        goodLog (str base "/good.log")
        a (cloneTree! stale repo (str "#!/bin/sh\necho \"$PWD|$1\" >> " staleLog "\necho '(:asl :status :failed :error ERR_NATIVE_STALE :message \"stale\")'\nexit 2\n"))
        b (cloneTree! good repo (str "#!/bin/sh\necho \"$PWD|$1\" >> " goodLog "\nexec " repo "/bin/asl \"$@\"\n"))
        withTool (runWith! "with" stale good)
        withoutTool (runWith! "without" stale "")
        runRoot (optionOr (listHead (stringLines withTool)) "?")
        rootNew (resultOr (fileReadString (str runRoot "/new.txt")) "")
        rootSubject (resultOr (fileReadString (str runRoot "/subject.txt")) "")
        rootOther (fileExists? (str runRoot "/other.txt"))
        toolHas (or (fileExists? (str good "/new.txt")) (or (fileExists? (str good "/subject.txt")) (or (fileExists? (str good "/other.txt")) (fileExists? (str good "/.asl")))))
        goodText (resultOr (fileReadString goodLog) "")
        staleText (resultOr (fileReadString staleLog) "")
        withoutRoot (optionOr (listHead (stringLines withoutTool)) "?")
        badRoot (m/mainWithRoots (list (str "(:agent :task \"x\" :backend \"script/none\" :root \"" (c/escapeAsn repo) "\" :toolRoot \"" (c/escapeAsn base) "/missing\")")) repo repo)
        notExec (let [p (str base "/noexec")
                      w (dirCreate (str p "/bin"))
                      f (fileWrite (str p "/bin/asl") "#!/bin/sh\n")
                      r (m/runArgsOf (list (pair "toolRoot" (j/jstr p))) 0 0 false)]
                  (m/toolRootUsable? r))
        resumedRoot (let [ra (m/runArgsOf (list (pair "toolRoot" (j/jstr "/x/tool"))) 0 0 false)
                          st (m/ResumeState :session "s" :journal "j" :task "t" :modeHint none :intent none :owns (list) :gates (list) :base "main"
                               :contextTokens none :note "" :result none :history (list) :turn 0 :reply "" :plan none)]
                      (m/resumed ra st).toolRoot)
        promptRoot (m/toolRootOr (m/runArgsOf (list (pair "toolRoot" (j/jstr "/x/tool"))) 0 0 false) "/repo")
        dryTree (str base "/dry")
        agentSrc "asl/packages/asl-agent/src"
        dryMade (and (ok? (dirCreate (str dryTree "/bin")))
                  (and (linkEntries! repo dryTree (list "bin" "asl" ".asl" ".git"))
                    (and (ok? (dirCreate (str dryTree "/asl/packages/asl-agent/src")))
                      (and (linkEntries! (str repo "/asl") (str dryTree "/asl") (list "packages"))
                        (and (linkEntries! (str repo "/asl/packages") (str dryTree "/asl/packages") (list "asl-agent"))
                          (and (linkEntries! (str repo "/asl/packages/asl-agent") (str dryTree "/asl/packages/asl-agent") (list "src"))
                            (and (linkEntries! (str repo "/" agentSrc) (str dryTree "/" agentSrc) (list "effects.asn"))
                              (and (ok? (fileWrite (str dryTree "/bin/asl") "#!/bin/sh\n"))
                                (and (ok? (fileChmod (str dryTree "/bin/asl") 493))
                                  (ok? (fileWrite (str dryTree "/" agentSrc "/effects.asn") "(:effects :id probe :entries ((:effect :op \"zzprobeop\" :class :outward :doc \"probe\")))")))))))))))
        dryRoot (rk/freshRecorderRoot! "dry")
        dryGit (gk/initGitRepo! dryRoot "dryRun" "dry-run@example.invalid")
        dryForm (fn [extra] (str "(:agent :task \"x\" :dryRun true :root \"" (c/escapeAsn dryRoot) "\"" extra ")"))
        watched (listAppend (aslWatch! repo) (list dryTree dryRoot))
        runsBefore (listFlatMap walk! watched)
        dryWith (m/mainWithRoots (list (dryForm (str " :toolRoot \"" (c/escapeAsn dryTree) "\""))) repo dryRoot)
        dryWithout (m/mainWithRoots (list (dryForm "")) repo dryRoot)
        runsAfter (listFlatMap walk! watched)
        cleaned (and (ok? (pathRemove base)) (and (ok? (pathRemove runRoot)) (and (ok? (pathRemove withoutRoot)) (ok? (pathRemove dryRoot)))))]
    (do
      (assert (and a b) "the two tree clones were built")
      (assert (and (stringContains? badRoot.stdout "ERR_TOOLROOT") (not (= badRoot.exitCode 0))) "a :toolRoot without bin/asl is refused ERR_TOOLROOT")
      (assert (not notExec) "a bin/asl that exists but is not executable makes the :toolRoot unusable")
      (assert (= resumedRoot "/x/tool") "a resumed run keeps its :toolRoot")
      (assert (= promptRoot "/x/tool") "toolRootOr gives the dry-run prompt the toolRoot tree, not the checkout")
      (assert dryMade "the dry-run probe tree was built")
      (assert (stringContains? dryWith.stdout "zzprobeop") "a dry run builds its system prompt from the :toolRoot tree")
      (assert (not (stringContains? dryWithout.stdout "zzprobeop")) "a dry run without :toolRoot builds it from the checkout, which has no such op")
      (assert (= runsBefore runsAfter) "the dry runs write nothing into the checkout's .asl or the probe tree, by a recursive listing that does not follow links")
      (assert cleaned "the clones and both run roots were removed")
      (assert (and (= rootNew "made") (stringContains? rootSubject "green")) "with :toolRoot a written and an edited owned file land in the run root")
      (assert (not toolHas) "the :toolRoot tree gets none of the run's files, no journal and no write")
      (assert (and (not rootOther) (stringContains? withTool "ERR_OWNS")) "a write outside :owns is refused in the run root")
      (assert (stringContains? goodText "|(:check") "with :toolRoot the check op ran <toolRoot>/bin/asl")
      (assert (stringContains? goodText (optionOr (listHead (stringLines withTool)) "?")) "the tool ran with the run root as cwd")
      (assert (not (stringContains? withTool "ERR_NATIVE_STALE")) "with :toolRoot no step is refused ERR_NATIVE_STALE")
      (assert (stringContains? withoutTool "ERR_NATIVE_STALE") "without :toolRoot the stale tree refuses the op as before")
      (assert (stringContains? staleText "|(:check") "without :toolRoot the stale tree's bin/asl is the one that ran")
      (assert (not (stringContains? (stringJoin (filter (fn [l] (stringContains? l "|(:check")) (stringLines goodText)) "") "stale")) "the good tree log holds only its own runs")
      true))
