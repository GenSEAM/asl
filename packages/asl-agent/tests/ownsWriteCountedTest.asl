(module aslAgent/tests/ownsWriteCountedTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-WRITE-NOT-COUNTED-20261018 :do "regression for a real escalated-despite-success run: a session with no :owns declared (the common case for a quick ad hoc task) writes a file, the write receipt comes back :status :ok and the file reads back correctly on disk, yet writesPersisted never becomes true and the run escalates nothing written -- because liveExecOps!'s owned check fed checkOwns the raw, un-normalized owns list (empty list is false by definition) while exec.asl's own writeCheck normalizes an empty owns to the unrestricted ** scope before deciding whether to allow the write at all. The two checks disagreed about what counts as owned for the exact same write")

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "ownsWriteCountedTest" "owns-write-counted-test@example.invalid"))

fn readFile root: String name: String -> String
  (resultOr (fileReadString (str root "/" name)) "")

fn runTests -> Bool
  (let [root (rk/freshRecorderRoot! "ownsWriteCounted")
        ready (initRepo! root "before\n")
        reply (str "(:intent :deliver patch :why \"create hello.txt\")\n"
                "(:step :op \"write\" :file \"hello.txt\" :content \"hello\")\n"
                "(:step :op \"check\" :file \"hello.txt\")\n(:done)")
        run (rk/runRecordedAgentLoopWithReplies! root "ownsWriteCounted" (list reply) (list)
              "Create file hello.txt containing exactly the word hello, then finish." 3 8000)
        helloFile (readFile root "hello.txt")
        cleaned (ok? (pathRemove root))]
    (do
      (assert ready "the baseline repo is tracked and committed")
      (assert (stringContains? run.journal "(:turn 1 :reply \"(:intent :deliver patch")
        "turn 1's scripted reply (intent deliver patch, write, check, done) is the one actually executed")
      (assert (= helloFile "hello") "the file genuinely lands on disk with exactly the scripted content, with or without the fix")
      (assert (= run.exitCode 0)
        "a declared, accepted, on-disk write with no :owns must count as persisted and let patch delivery close on turn 1 -- any other exit code means the write was not counted")
      (assert (stringContains? run.journal "(:result :status :ok")
        "the run reaches a successful terminal receipt on the same turn as its only write, instead of carrying on past it")
      (assert (not (stringContains? run.journal "(:turn 2"))
        "the run closes after turn 1 and never needs a second turn -- a second turn here means writesPersisted was not set from this turn's write")
      (assert cleaned "the fixture root is removed")
      true))
