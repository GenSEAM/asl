(module aslAgent/tests/toolRootTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-TOOLROOT :do "a worktree whose native CLI is stale (its bin/asl answers ERR_NATIVE_STALE) with :toolRoot naming a good tree: the check op runs <toolRoot>/bin/asl with the run root as cwd and the stale tree's bin/asl is never run; without :toolRoot the op fails ERR_NATIVE_STALE as before; trees are symlink clones of this checkout with only bin/asl replaced")

fn ! sh command: String -> Int64
  (processRun command).exitCode

fn ! cloneTree! dir: String repo: String script: String -> Bool
  (and (= (sh (str "mkdir -p " dir "/bin && for e in " repo "/* " repo "/.[!.]*; do b=$(basename $e); [ $b = bin ] || [ $b = .asl ] || [ $b = .git ] || ln -s $e " dir "/$b; done; for e in " repo "/bin/*; do b=$(basename $e); [ $b = asl ] || ln -s $e " dir "/bin/$b; done")) 0)
    (ok? (fileWrite (str dir "/bin/asl") script)))

fn ! runWith! tag: String stale: String tool: String -> String
  (let [root (rk/freshRecorderRoot! tag)
        w (fileWrite (str root "/subject.txt") "red\n")
        repo (gk/initGitRepo! root "toolRoot" "tool-root@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        d (dirCreate fixtureDir)
        f (fileWrite (str fixtureDir "/t" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "t" tag) (list "(:step :op \"check\" :file \"subject.txt\")" "(:done)")))
        form (str "(:agent :task \"check subject\" :backend \"script/t" tag "\" :root \"" (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :budget 4 :contextTokens 8000"
               (if (stringEmpty? tool) "" (str " :toolRoot \"" (c/escapeAsn tool) "\"")) ")")
        res (m/mainWithRoots (list form) stale root)
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        jn (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? jn) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" jn)) ""))]
    (str root "\n" res.stdout "\n" text))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        base (str (optionOr (envGet "TMPDIR") "/tmp") "/toolRootTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))
        stale (str base "/stale")
        good (str base "/good")
        staleLog (str base "/stale.log")
        goodLog (str base "/good.log")
        a (cloneTree! stale repo (str "#!/bin/sh\necho \"$PWD|$1\" >> " staleLog "\necho '(:asl :status :failed :error ERR_NATIVE_STALE :message \"stale\")'\nexit 2\n"))
        b (cloneTree! good repo (str "#!/bin/sh\necho \"$PWD|$1\" >> " goodLog "\necho '(:asl :status :ok :message \"fakeGoodTree\")'\nexit 0\n"))
        chmod (sh (str "chmod +x " stale "/bin/asl " good "/bin/asl"))
        withTool (runWith! "with" stale good)
        withoutTool (runWith! "without" stale "")
        goodText (resultOr (fileReadString goodLog) "")
        staleText (resultOr (fileReadString staleLog) "")
        cleaned (sh (str "rm -rf " base))]
    (do
      (assert (and a b) "the two tree clones were built")
      (assert (stringContains? goodText "|(:check") "with :toolRoot the check op ran <toolRoot>/bin/asl")
      (assert (stringContains? goodText (optionOr (listHead (stringLines withTool)) "?")) "the tool ran with the run root as cwd")
      (assert (not (stringContains? withTool "ERR_NATIVE_STALE")) "with :toolRoot no step is refused ERR_NATIVE_STALE")
      (assert (stringContains? withoutTool "ERR_NATIVE_STALE") "without :toolRoot the stale tree refuses the op as before")
      (assert (stringContains? staleText "|(:check") "without :toolRoot the stale tree's bin/asl is the one that ran")
      (assert (not (stringContains? (stringJoin (filter (fn [l] (stringContains? l "|(:check")) (stringLines goodText)) "") "stale")) "the good tree log holds only its own runs")
      true))
