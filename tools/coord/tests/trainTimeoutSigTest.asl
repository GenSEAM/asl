(module asl-tools/coord/tests/trainTimeoutSigTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (tools/fleet/train :a trn)])

; (:m :ref TRAIN-NEVER-LANDS :do "a train the merge stage kills at its limit is reported with the timeout and the items still running, read from the rows the train streams (runningRow, itemDoneRow); two such kills with different running sets are the same merge failure, so the retry count reaches maxSame and the unit escalates; a red train keeps its old signature")
fn item kind: String path: String -> trn/Item
  (trn/Item :kind kind :path path)

fn res path: String code: Int64 -> trn/Res
  (trn/Res :kind "suite" :path path :exit code :executed 1 :errors (list) :ms 1)

fn killRow -> String
  "(:fleetRun :verdict :timeout :pid 4242 :desc 9 :timeoutMs 3600000 :maxDesc 200 :left 0)"

fn ! runTests -> Bool
  (let [(items (list (item "suite" "a/tests/slowTest.asl") (item "suite" "a/tests/quickTest.asl") (item "suite" "b/tests/heavyTest.asl") (item "audit" "audit consistency")))
        (start (trn/runningRow items))
        (killed (stringJoin (list "(:train :status :started)" start (trn/itemDoneRow (res "a/tests/quickTest.asl" 0)) (trn/itemDoneRow (res "audit consistency" 0)) (killRow)) "\n"))
        (sig (cd/gateSig killed))
        (left (cd/stillRunning (stringLines killed)))
        (other (cd/gateSig (stringJoin (list start (trn/itemDoneRow (res "a/tests/slowTest.asl" 0)) (killRow)) "\n")))
        (bare (cd/gateSig (killRow)))
        (red (cd/gateSig (stringJoin (list start (trn/itemDoneRow (res "a/tests/quickTest.asl" 1)) "(:redLive \"a/tests/quickTest.asl\" 1 0 :kind suite)" "(:train :head \"x\" :red ((\"a/tests/quickTest.asl\" 1)) :preexisting () :assertLoss ())") "\n")))]
    (do
      (assert (= left (list "a/tests/slowTest.asl" "b/tests/heavyTest.asl")) (str "the items with no done row are still running: " (stringJoin left " ")))
      (assert (stringStartsWith? sig "killed: timeout after 3600 s") (str "the signature names the timeout first: " sig))
      (assert (stringContains? sig " :running 2 a/tests/slowTest.asl b/tests/heavyTest.asl") (str "the signature names the suites still running: " sig))
      (assert (not (stringContains? sig "quickTest")) (str "a finished suite is not named as running: " sig))
      (assert (stringContains? other " :running 3 ") (str "another attempt names its own running set: " other))
      (assert (!= sig other) "the two kills read differently")
      (assert (= (cd/mergeSigKey sig) (cd/mergeSigKey other)) (str "but count as the same merge failure: " (cd/mergeSigKey sig)))
      (assert (= (cd/mergeSigKey sig) (cd/mergeSigKey bare)) "and as a kill that streamed no rows")
      (assert (= bare "killed: timeout after 3600 s") (str "a kill with no streamed rows keeps the old signature: " bare))
      (assert (= red "train red: a/tests/quickTest.asl") (str "a red train keeps its signature: " red))
      (assert (!= (cd/mergeSigKey red) (cd/mergeSigKey sig)) "a red is not the same failure as a timeout")
      true))
