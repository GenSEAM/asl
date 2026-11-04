(module aslAgent/tests/batchingCountedTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/main :a m) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-BATCHING-DEAD-20261018 :do "state.batching was declared on LoopState, threaded through every with* copier and rendered into every receipt's :batching form, but nothing anywhere ever incremented it -- ops/single/turns stayed zero for the life of every run, so :opTurns :opsPerTurn :singleOpShare were always zero regardless of how many ops a turn actually ran. batchingPlus/withBatching (runLoop.asl) make it a real running count, folded in once per turn in main.asl beside the usageTotals fold, from that turn's own operations list. The receipt carrying :batching is main's stdout (MainResult.stdout), not the journal file, so this test drives mainWithRoots directly instead of the recorder kit's journal-only RecordedRun")

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "batchingCountedTest" "batching-counted-test@example.invalid"))

fn runTests -> Bool
  (let [root (rk/freshRecorderRoot! "batchingCounted")
        ready (initRepo! root "before\n")
        reply (str "(:step :op \"write\" :file \"hello.txt\" :content \"hello\")\n(:done)")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        _fixture (fileWrite (str fixtureDir "/batchingCounted.asn") (rk/scriptFixtureTextFromReplies! "batchingCounted" (list reply)))
        form (str "(:agent :task \"Create file hello.txt containing exactly the word hello, then finish.\" :backend \"script/batchingCounted\" :root \""
                  (c/escapeAsn root) "\" :mode \"scout\" :budget 3 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)
        journalDir (str root "/.asl/run/agentLoop")
        names (resultOr (dirList journalDir) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        journalText (if (stringEmpty? journalName) "" (resultOr (fileReadString (str journalDir "/" journalName)) ""))
        cleaned (ok? (pathRemove root))]
    (do
      (assert ready "the baseline repo is tracked and committed")
      (assert (stringContains? journalText "(:turn 1 :reply \"(:step :op")
        "turn 1's scripted reply (one write step, one done) is the one actually executed")
      (assert (not (stringContains? journalText "(:turn 2"))
        "the run closes after turn 1 -- a second turn here would mean the 2-op count no longer lands on a single opTurn")
      (assert (= res.exitCode 0) "a single-turn write-then-done run closes cleanly")
      (assert (stringContains? res.stdout ":opTurns 1")
        "the one turn that ran any ops at all is counted exactly once, not left at zero")
      (assert (stringContains? res.stdout ":opsPerTurn 2.0")
        "two ops (write, done) over that one opTurn gives opsPerTurn 2.0, not the dead 0.0 every receipt used to show")
      (assert (stringContains? res.stdout ":singleOpShare 0.0")
        "neither op stood alone in its turn, so singleOpShare is 0.0, not the dead default")
      (assert cleaned "the fixture root is removed")
      true))
