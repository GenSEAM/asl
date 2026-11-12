(module aslAgent/tests/gateBuildFailSkipTest
  :x [runTests]
  :i [(aslAgent/gitOps :a go)])

fn skippedOf rec: (List (Pair String go/RVal)) -> String
  (match (go/recGet rec "skipped")
    ((some v) (match v ((go/rStr s) s) (_ "")))
    ((none) ""))

fn exitNull? rec: (List (Pair String go/RVal)) -> Bool
  (match (go/recGet rec "exit")
    ((some v) (match v ((go/rNull) true) (_ false)))
    ((none) false))

fn ! runTests -> Bool
  (let [tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/gateBuildFailSkip" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        times (str tmp "/gateTimes.asn")
        failRecs (go/runGatesIn! (list (pair "b" "false build.sh") (pair "t" "true aTest.asl") (pair "u" "true bTest.asl")) tmp 300 (none) (none) times)
        failThird (optionOr (listGet failRecs 2) (list))
        failSecond (optionOr (listGet failRecs 1) (list))
        failKeys (map (fn [kv] (pairFirst kv)) failSecond)
        okRecs (go/runGatesIn! (list (pair "b" "true build.sh") (pair "t" "true aTest.asl")) tmp 300 (none) (none) times)
        okSecond (optionOr (listGet okRecs 1) (list))
        okKeys (map (fn [kv] (pairFirst kv)) okSecond)
        removed (pathRemove tmp)]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert (= (listLength failRecs) 3) "runGatesIn! returns one record per gate")
      (assert (= (skippedOf failThird) "afterBuildFail") "every later gate after a failed build.sh stays skipped, not only the next one")
      (assert (= (skippedOf failSecond) "afterBuildFail") "the gate after a failed build.sh is skipped with afterBuildFail")
      (assert (exitNull? failSecond) "the skipped gate has a null exit")
      (refute (listContains? failKeys "stdout") "the skipped gate was not run")
      (assert (= (listLength okRecs) 2) "runGatesIn! returns one record per gate when the build passes")
      (refute (listContains? okKeys "skipped") "the gate after a successful build.sh is not skipped")
      (assert (listContains? okKeys "stdout") "the gate after a successful build.sh ran")
      (assert (ok? removed) "the fixture directory is removed")
      true))
