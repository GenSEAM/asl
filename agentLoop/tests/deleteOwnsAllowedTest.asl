(module asl/agentLoop/tests/deleteOwnsAllowedTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/main :a m) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-OWNS-ALL-20261018 :do "a session with no :owns declared writes anywhere inside :root (LEON-OWNS-ONE-RULE made write/edit agree on that), but a delete went through core.asl's changePlan with the raw, un-normalized owns list: checkOwns on an empty list is false by definition, so every delete was rejected ERR_OWNS the instant :owns was left unset, even for a file plainly inside :root. changePlan now normalizes via c/effectiveOwns, same as writeCheck/liveExecOps!, so delete agrees with write")

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "deleteOwnsAllowedTest" "delete-owns-allowed-test@example.invalid"))

fn fileExists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn driveReply! root: String reply: String -> m/MainResult
  (let [fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        _fixture (fileWrite (str fixtureDir "/deleteOwnsAllowed.asn") (rk/scriptFixtureTextFromReplies! "deleteOwnsAllowed" (list reply)))
        form (str "(:agent :task \"Delete subject.txt, then finish.\" :backend \"script/deleteOwnsAllowed\" :root \""
                  (c/escapeAsn root) "\" :mode \"scout\" :budget 3 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")]
    (m/mainWithRoots (list form) repoRoot repoRoot))

fn runTests -> Bool
  (let [root (rk/freshRecorderRoot! "deleteOwnsAllowed")
        ready (initRepo! root "before\n")
        reply (str "(:step :op \"delete\" :file \"subject.txt\")\n(:done)")
        res (driveReply! root reply)
        stillThere (fileExists?! (str root "/subject.txt"))
        cleaned (ok? (pathRemove root))]
    (do
      (assert ready "the baseline repo is tracked and committed")
      (assert (not (stringContains? res.stdout "ERR_OWNS"))
        "a delete of a file plainly inside :root must not be rejected ERR_OWNS just because :owns was left unset")
      (assert (= res.exitCode 0) "a single-turn delete-then-done run closes cleanly when the delete is actually allowed")
      (assert (not stillThere) "the file is genuinely gone from disk -- a rejected delete would have left it in place")
      (assert cleaned "the fixture root is removed")
      true))
