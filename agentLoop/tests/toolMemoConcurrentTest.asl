(module asl/agentLoop/tests/toolMemoConcurrentTest
  :x [runTests]
  :i [(asl/agentLoop/aslOps :a o)
      (asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

; (:m :ref TOOLMEMO-CONCURRENT-ROOT :do "two runs open in one scratch root: each run's memo survives the other's begin and end, and pruning removes only dirs whose pid is dead (pid 2000000000 is never allocated) and never touches a live one or anything outside the memo dir")
fn ! tempDir -> String
  (let [path (str "/tmp/asl-tool-memo-cc-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) path))

fn ! fakeRunIn root: String form: String r: String -> t/AslRun
  (let [_ (fileAppend (str root "/runs.log") (str form "\n"))
        file (resultOr (fileReadString (str root "/f.txt")) "")]
    (t/aslRun 0 (str "(:read :file \"f.txt\" :content \"" file "\")") ""))

fn ! readAs root: String session: String -> String
  (o/serReceipt (o/execAslOpMemo! (c/parseKv "(:step :op \"read\" :file \"f.txt\")") (list) root session (fn [] "rid") (fn [f] true) (fn [form r] (fakeRunIn root form r)) 8000 none))

fn ! runCount root: String -> Int64
  (listLength (filter (fn [l] (stringContains? l ":read")) (stringSplit (resultOr (fileReadString (str root "/runs.log")) "") "\n")))

fn ! runTests -> Bool
  (let [root (tempDir)
        memo (str root "/.asl/run/agentLoop/memo")
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:toolMemo true))\n")
        _f (fileWrite (str root "/f.txt") "alpha")
        _a (o/memoRunBegin! root "A")
        _ra (readAs root "A")
        _b (o/memoRunBegin! root "B")
        aSurvivesBegin (readAs root "A")
        n1 (runCount root)
        _rb (readAs root "B")
        n2 (runCount root)
        _endB (o/memoRunEnd! root "B")
        aSurvivesEnd (readAs root "A")
        n3 (runCount root)
        bDirGone (not (fileExists? (str memo "/" (o/memoRunId "B"))))
        deadDir (str memo "/2000000000-dead")
        _d (dirCreate deadDir)
        _c (o/memoRunBegin! root "C")
        deadGone (not (fileExists? deadDir))
        aStill (fileExists? (str memo "/" (o/memoRunId "A")))
        outside (str root "/keep.txt")
        _k (fileWrite outside "keep")
        _p (o/memoPrune! root)]
    (do
      (assert (stringContains? aSurvivesBegin "hit") "run A's memo survives run B beginning in the same root")
      (assert (= n1 1) "A's second read did not reach the run")
      (assert (= n2 2) "B starts with its own empty memo, so its first read runs")
      (assert (stringContains? aSurvivesEnd "hit") "run A's memo survives run B ending")
      (assert (= n3 2) "A's read after B ended did not reach the run")
      (assert bDirGone "run end removes only that run's dir")
      (assert deadGone "a dir of a dead pid is pruned at the next begin")
      (assert aStill "a live run's dir is not pruned")
      (assert (fileExists? outside) "pruning never touches anything outside the memo dir")
      (assert (not (o/memoSessionOk? "../x")) "a session id that climbs out of the memo dir is refused")
      (assert (ok? (pathRemove root)) "scratch root removed")
      true))
