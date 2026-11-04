(module aslAgent/tests/toolMemoLoopTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-PREFIX-CACHE-TOOLMEMO :do "real loop runs with :toolMemo true: the memo scope opens at run start and the memo dir is gone after a run that succeeds and after a run that ends on its budget")
fn ! setup! tag: String -> String
  (let [root (rk/freshRecorderRoot! tag)
        _a (fileWrite (str root "/subject.txt") "before\n")
        _b (gk/initGitRepo! root "memoLoopTest" "memo-loop-test@example.invalid")
        _c (fileWrite (str root "/.asl.config.asn") "(:agentLoop (:specCheck false) :toolMemo true)\n")]
    root)

fn memoGone? root: String -> Bool
  (listEmpty? (resultOr (dirList (str root "/.asl/run/agentLoop/memo")) (list)))

fn okReplies -> (List String)
  (list "(:step :op \"read\" :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")"
        "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)")

fn failReplies -> (List String)
  (list "(:step :op \"read\" :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")")

fn ! runTests -> Bool
  (let [rootA (setup! "memoLoopOk")
        runA (rk/runRecordedAgentLoopWithReplies! rootA "memoLoopOk" (okReplies) (list "subject.txt") "read twice then write green" 10 8000)
        goneA (memoGone? rootA)
        rootB (setup! "memoLoopFail")
        runB (rk/runRecordedAgentLoopWithReplies! rootB "memoLoopFail" (failReplies) (list "subject.txt") "read forever" 2 8000)
        goneB (memoGone? rootB)]
    (do
      (assert (= runA.exitCode 0) "the successful run exits 0")
      (assert (stringContains? runA.journal "memo") "the repeated read in the run was served from the memo")
      (assert goneA "no memo dir is left after a successful run")
      (assert (!= runB.exitCode 0) "the budget-limited run does not succeed")
      (assert goneB "no memo dir is left after a failing run")
      (assert (ok? (pathRemove rootA)) "scratch root A removed")
      (assert (ok? (pathRemove rootB)) "scratch root B removed")
      true))
