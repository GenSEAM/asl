(module asl/agentLoop/tests/toolMemoTest
  :x [runTests]
  :i [(asl/agentLoop/aslOps :a o)
      (asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

; (:m :ref LEON-PREFIX-CACHE-20261026 :do "the fake run appends every form it executes to runs.log in the scratch root, so a memo hit shows as a read that did not reach the run; the body it returns embeds the file's bytes so a changed file is visible in the receipt")
fn ! tempDir -> String
  (let [path (str "/tmp/asl-tool-memo-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) path))

fn ! fakeRunIn root: String form: String r: String -> t/AslRun
  (let [_ (fileAppend (str root "/runs.log") (str form "\n"))
        file (resultOr (fileReadString (str root "/f.txt")) "")]
    (t/aslRun 0 (str "(:read :file \"f.txt\" :start 1 :content \"" file "\")") ""))

fn ! receiptFor op: String root: String -> String
  (o/serReceipt (o/execAslOpMemo! (c/parseKv op) (list) root "s1" (fn [] "rid") (fn [f] true) (fn [form r] (fakeRunIn root form r)) 8000 none))

fn ! runCount root: String -> Int64
  (listLength (filter (fn [l] (stringContains? l ":read")) (stringSplit (resultOr (fileReadString (str root "/runs.log")) "") "\n")))

fn ! runTests -> Bool
  (let [root (tempDir)
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:toolMemo true))\n")
        began (o/memoRunBegin! root "s1")
        readOp "(:step :op \"read\" :file \"f.txt\")"
        _a (fileWrite (str root "/f.txt") "alpha")
        first (receiptFor readOp root)
        n1 (runCount root)
        second (receiptFor readOp root)
        n2 (runCount root)
        _b (fileWrite (str root "/f.txt") "beta")
        third (receiptFor readOp root)
        n3 (runCount root)
        testOp "(:step :op \"test\" :file \"f.txt\")"
        _c (receiptFor testOp root)
        _d (receiptFor testOp root)
        shellRuns (listLength (filter (fn [l] (stringContains? l ":test")) (stringSplit (resultOr (fileReadString (str root "/runs.log")) "") "\n")))]
    (do
      (assert (ok? began) "a run scope is opened")
      (assert (= n1 1) "the first read runs the form")
      (assert (and (= n2 1) (stringContains? second "memo") (stringContains? second "hit")) "the identical second read does not run the form and carries the hit marker")
      (assert (not (stringContains? first "memo")) "a miss carries no marker")
      (assert (= (stringReplace (stringReplace second "(memo \"hit\")" "") " " "") (stringReplace first " " "")) "the hit receipt equals the miss receipt apart from the marker")
      (assert (and (= n3 2) (stringContains? third "beta") (not (stringContains? third "memo"))) "a write to the file makes the next read miss and return the new bytes")
      (assert (= shellRuns 2) "an op other than read is never memoised")
      (assert (not (o/toolMemoIn "(:aslConfig :note \":toolMemo true\" :agentLoop (:specCheck false))")) "the text inside a string or outside :agentLoop does not enable the memo")
      (assert (o/toolMemoIn "(:aslConfig :agentLoop (:toolMemo true))") "the :agentLoop key enables it")
      (assert (not (o/toolMemoIn "(:aslConfig :agentLoop (:toolMemo false))")) "false keeps it off")
      (assert (o/memoRunEnd! root "s1") "run end removes its own run dir")
      (assert (not (fileExists? (str root "/.asl/run/agentLoop/memo/" (o/memoRunId "s1")))) "no run dir is left behind")
      (assert (let [_ (o/memoRunBegin! root "s1")
                    before (runCount root)
                    _r (receiptFor readOp root)]
                (= (runCount root) (+ before 1))) "the next run's first read is a miss")
      (assert (o/memoRunEnd! root "s1") "second run end removes the memo dir")
      (assert (let [_b (o/memoRunBegin! root "s1")
                    dir (optionOr (o/memoRunDir! root "s1") "")
                    _gone (pathRemove dir)
                    _blocker (fileWrite dir "x")
                    _r (fileWrite (str root "/f.txt") "gamma")
                    skipped (receiptFor readOp root)]
                (and (stringContains? skipped "skipped") (stringContains? skipped "gamma"))) "a memo that cannot be written is reported as skipped and the read still answers")
      (assert (o/memoRunEnd! root "s1") "third run end removes the memo dir")
      (assert (let [before (runCount root)
                    _r (receiptFor readOp root)]
                (= (runCount root) (+ before 1))) "with no run scope open nothing is memoised")
      true))
