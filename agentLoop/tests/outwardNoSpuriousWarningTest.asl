(module asl/agentLoop/tests/outwardNoSpuriousWarningTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/main :a m) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-OWNS-ALL-20261018 :do "core.asl's segmentOutward flags a shell rm/mv as outward the moment any of its target paths fails checkOwns, which runOutward/execRunOp! turns into a needsConfirm instead of running the command. With :owns left unset, segmentOutward used to feed checkOwns the raw, un-normalized owns list, so every rm/mv target looked outside owns and every such command needed confirmation -- even one touching a file plainly inside :root on an ordinary, unrestricted session. runOutward now normalizes via c/effectiveOwns before calling segmentOutward")

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "outwardNoSpuriousWarningTest" "outward-no-spurious-warning-test@example.invalid"))

fn fileExists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn driveReply! root: String reply: String -> m/MainResult
  (let [fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        _fixture (fileWrite (str fixtureDir "/outwardNoSpuriousWarning.asn") (rk/scriptFixtureTextFromReplies! "outwardNoSpuriousWarning" (list reply)))
        form (str "(:agent :task \"Remove subject.txt with a shell command, then finish.\" :backend \"script/outwardNoSpuriousWarning\" :root \""
                  (c/escapeAsn root) "\" :mode \"scout\" :budget 3 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")]
    (m/mainWithRoots (list form) repoRoot repoRoot))

fn runTests -> Bool
  (let [root (rk/freshRecorderRoot! "outwardNoSpuriousWarning")
        ready (initRepo! root "before\n")
        reply (str "(:step :op \"run\" :cmd \"rm subject.txt\")\n(:done)")
        res (driveReply! root reply)
        stillThere (fileExists?! (str root "/subject.txt"))
        cleaned (ok? (pathRemove root))]
    (do
      (assert ready "the baseline repo is tracked and committed")
      (assert (not (stringContains? res.stdout ":needsConfirm"))
        "an rm of a file plainly inside :root must not need confirmation just because :owns was left unset")
      (assert (= res.exitCode 0) "a single-turn rm-then-done run closes cleanly once rm is actually allowed to run")
      (assert (not stillThere)
        "the file is genuinely gone -- a spurious outward warning would have left rm unexecuted and the file in place")
      (assert cleaned "the fixture root is removed")
      true))
