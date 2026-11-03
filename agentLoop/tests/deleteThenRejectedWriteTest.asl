(module asl/agentLoop/tests/deleteThenRejectedWriteTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/main :a m) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEONDELETE :do "a reply that deletes an owned file and then rewrites it (the delete+write idiom) in a write that is refused, once ERR_USE_RAW for large escaped content and since LEON-RAW-PROTOCOL a :raw field with no fenced block, and the delete used to have run already, leaving the pre-existing file deleted; a delete whose path a later write in the same reply targets is now superseded, so a refused write leaves the original file intact")

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "deleteThenRejectedWriteTest" "delete-then-rejected-write@example.invalid"))

fn readText! path: String -> String
  (match (fileReadString path) ((ok t) t) ((err _) "<missing>"))

fn driveReply! root: String reply: String -> m/MainResult
  (let [fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        _fixture (fileWrite (str fixtureDir "/deleteThenRejectedWrite.asn") (rk/scriptFixtureTextFromReplies! "deleteThenRejectedWrite" (list reply)))
        form (str "(:agent :task \"Rewrite subject.txt, then finish.\" :backend \"script/deleteThenRejectedWrite\" :root \""
                  (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :budget 3 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")]
    (m/mainWithRoots (list form) repoRoot repoRoot))

fn runTests -> Bool
  (let [root (rk/freshRecorderRoot! "deleteThenRejectedWrite")
        ready (initRepo! root "before\n")
        reply "(:step :op \"delete\" :file \"subject.txt\")\n(:step :op \"write\" :file \"subject.txt\" :content :raw)\n(:done)"
        res (driveReply! root reply)
        after (readText! (str root "/subject.txt"))
        cleaned (ok? (pathRemove root))]
    (do
      (assert ready "the baseline repo is tracked and committed")
      (assert (= res.exitCode 0) "the run closes")
      (assert (= after "before\n") "a refused rewrite must leave the pre-existing owned file as it was, not deleted")
      (assert cleaned "the fixture root is removed")
      true))
