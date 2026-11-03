(module aslAgent/tests/runStepKeepsWriteTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/main :a m) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-OWNS-ALL-20261018 :do "a shell run step's own side effects (files it writes directly, outside the declared write/edit ops) are settled by runOps.asl's settle!, which asks core.asl's changePlan whether each changed file should be kept or restored. changePlan fed checkOwns the raw, un-normalized owns list, so with :owns left unset every file the shell step touched looked outside owns and got reverted by settle! the instant the run step finished -- the opposite of 'no :owns means write anywhere in :root', and a silent one: the run op itself still reports status ok")

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "runStepKeepsWriteTest" "run-step-keeps-write-test@example.invalid"))

fn readSideFile! root: String -> String
  (resultOr (fileReadString (str root "/sidefile.txt")) "")

fn driveReply! root: String reply: String -> m/MainResult
  (let [fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        _fixture (fileWrite (str fixtureDir "/runStepKeepsWrite.asn") (rk/scriptFixtureTextFromReplies! "runStepKeepsWrite" (list reply)))
        form (str "(:agent :task \"Run a shell command that writes sidefile.txt, then finish.\" :backend \"script/runStepKeepsWrite\" :root \""
                  (c/escapeAsn root) "\" :mode \"scout\" :budget 3 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")]
    (m/mainWithRoots (list form) repoRoot repoRoot))

fn runTests -> Bool
  (let [root (rk/freshRecorderRoot! "runStepKeepsWrite")
        ready (initRepo! root "before\n")
        reply (str "(:step :op \"run\" :cmd \"echo hi > sidefile.txt\")\n(:done)")
        res (driveReply! root reply)
        sideContent (readSideFile! root)
        cleaned (ok? (pathRemove root))]
    (do
      (assert ready "the baseline repo is tracked and committed")
      (assert (= res.exitCode 0) "the run step itself reports success regardless of whether settle! later reverts its effect")
      (assert (stringContains? sideContent "hi")
        "the file the shell step wrote must survive settle!'s keep/restore pass when :owns is left unset -- a reverted write would leave this empty or missing")
      (assert cleaned "the fixture root is removed")
      true))
