(module aslAgent/tests/toolMemoLoopTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)
      (aslAgent/aslOps :a o) (aslAgent/txn :a t) (aslAgent/core :a c)])

; (:m :ref LEON-PREFIX-CACHE-TOOLMEMO :do "real loop runs with :toolMemo true: the memo scope opens at run start and the memo dir is gone after a run that succeeds and after a run that ends on its budget")
fn ! setup! tag: String -> String
  (let [root (rk/freshRecorderRoot! tag)
        _a (fileWrite (str root "/subject.txt") "before\n")
        _b (gk/initGitRepo! root "memoLoopTest" "memo-loop-test@example.invalid")
        _c (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :toolMemo true))\n")]
    root)

fn memoGone? root: String -> Bool
  (listEmpty? (resultOr (dirList (str root "/.asl/run/agentLoop/memo")) (list)))

fn okReplies -> (List String)
  (list "(:step :op \"read\" :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")"
        "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)")

fn failReplies -> (List String)
  (list "(:step :op \"read\" :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")")

fn ! tempDir -> String
  (let [path (str "/tmp/asl-tool-memo-loop-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) path))

fn ! fakeRunIn root: String form: String r: String -> t/AslRun
  (let [file (resultOr (fileReadString (str root "/f.txt")) "")]
    (t/aslRun 0 (str "(:read :file \"f.txt\" :start 1 :content \"" file "\")") ""))

fn ! receiptFor op: String root: String rid: String -> String
  (o/serReceipt (o/execAslOpMemo! (c/parseKv op) (list) root "s1" (fn [] rid) (fn [f] true) (fn [form r] (fakeRunIn root form r)) 8000 none))

fn ! ageOneMemo! dir: String name: String oldTs: Int64 -> Bool
  (let [path (str dir "/" name)
        text (resultOr (fileReadString path) "")]
    (match (stringIndexOf text "\n")
      ((none) false)
      ((some nl)
        (let [header (c/sliceOf text 0 nl)
              parts (stringSplit header " ")
              body (c/sliceOf text (+ nl 1) (stringLength text))
              newHeader (str (optionOr (listGet parts 0) "0") " " (optionOr (listGet parts 1) "0") " " (optionOr (listGet parts 2) "") " " (stringFromInt64 oldTs))
              newText (str newHeader "\n" body)]
          (ok? (fileWrite path newText))))))

fn ! ageMemoFiles! dir: String oldTs: Int64 -> Bool
  (let [names (resultOr (dirList dir) (list))
        files (filter (fn [n] (stringEndsWith? n ".memo")) names)]
    (listAll? (fn [n] (ageOneMemo! dir n oldTs)) files))

fn ! directMemoTest -> Bool
  (let [root (tempDir)
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:toolMemo true))\n")
        began (o/memoRunBegin! root "s1")
        _a (fileWrite (str root "/f.txt") "alpha\nbeta\n")
        readOp "(:step :op \"read\" :file \"f.txt\")"
        first (receiptFor readOp root "first-rid")
        second (receiptFor readOp root "second-rid")
        rangeOp "(:step :op \"read\" :file \"f.txt\" :start 1 :end 1)"
        rangeR (receiptFor rangeOp root "range-rid")
        dir (optionOr (o/memoRunDir! root "s1") "")
        aged (ageMemoFiles! dir (- (nowNs) 700000000000))
        oldR (receiptFor readOp root "old-rid")
        ended (o/memoRunEnd! root "s1")]
    (do
      (assert (ok? began) "direct: run scope opened")
      (assert (stringContains? first "alpha") "direct: first read returns the file content")
      (assert (not (stringContains? first "identical to that earlier result")) "direct: first read is not a same marker")
      (assert (stringContains? second "(:same :id") "direct: repeated read returns the same marker")
      (assert (stringContains? second "first-rid") "direct: the same marker names the first read's id")
      (assert (stringContains? second "identical to that earlier result") "direct: the same marker carries the note")
      (assert (stringContains? rangeR "alpha") "direct: a different range returns full content")
      (assert (not (stringContains? rangeR "identical to that earlier result")) "direct: a different range is not a same marker")
      (assert aged "direct: memo files aged")
      (assert (stringContains? oldR "alpha") "direct: an old entry returns full content")
      (assert (not (stringContains? oldR "identical to that earlier result")) "direct: an old entry is not a same marker")
      (assert ended "direct: run scope closed")
      (assert (ok? (pathRemove root)) "direct: scratch root removed")
      true))

fn ! runTests -> Bool
  (let [direct (directMemoTest)
        rootA (setup! "memoLoopOk")
        runA (rk/runRecordedAgentLoopWithReplies! rootA "memoLoopOk" (okReplies) (list "subject.txt") "read twice then write green" 10 8000)
        goneA (memoGone? rootA)
        rootB (setup! "memoLoopFail")
        runB (rk/runRecordedAgentLoopWithReplies! rootB "memoLoopFail" (failReplies) (list "subject.txt") "read forever" 2 8000)
        goneB (memoGone? rootB)]
    (do
      (assert (= runA.exitCode 0) "the successful run exits 0")
      (assert (stringContains? runA.journal "memo") "the repeated read in the run was served from the memo")
      (assert (stringContains? runA.journal "(:same :id") "the repeated read in the run returns the same marker")
      (assert goneA "no memo dir is left after a successful run")
      (assert (!= runB.exitCode 0) "the budget-limited run does not succeed")
      (assert goneB "no memo dir is left after a failing run")
      (assert (ok? (pathRemove rootA)) "scratch root A removed")
      (assert (ok? (pathRemove rootB)) "scratch root B removed")
      (assert direct "direct memo assertions pass")
      true))
