(module aslAgent/tests/gateTimeoutGuardTest
  :x [runTests]
  :i [(aslAgent/gates :a gd) (aslAgent/gitOps :a go)])

fn writeFixture path: String -> Bool
  (match (fileWrite path "(:suiteTime :suite \"slowTest.asl\" :ms 5000000)\n(:suiteTime :suite \"fastTest.asl\" :ms 1000)\n")
    ((ok _) true)
    ((err _) false))

fn ! runTests -> Bool
  (let [tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/gateTimeoutGuard" (stringFromInt64 (nowNs)))
        path (str tmp "/gateTimes.asn")
        made (dirCreate tmp)
        wrote (writeFixture path)
        slow (gd/gateTimeoutFit! path "asl test slowTest.asl" 300)
        fast (gd/gateTimeoutFit! path "asl test fastTest.asl" 300)
        unknown (gd/gateTimeoutFit! path "asl test unknownTest.asl" 300)
        recs (go/runGatesIn! (list (pair "g1" "true slowTest.asl") (pair "g2" "true fastTest.asl")) tmp 300 (none) (none) path)
        slowRec (optionOr (listGet recs 0) (list))
        fastRec (optionOr (listGet recs 1) (list))
        slowKeys (map (fn [kv] (pairFirst kv)) slowRec)
        fastKeys (map (fn [kv] (pairFirst kv)) fastRec)
        removed (pathRemove tmp)]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert wrote "the fixture times file is written")
      (assert (some? slow) "a suite recorded at 5000000 ms with timeout 300 is skipped")
      (assert (= (optionOr slow 0) 5000000) "the skip carries the recorded ms")
      (assert (none? fast) "a suite recorded at 1000 ms with timeout 300 runs")
      (assert (none? unknown) "an unknown suite runs")
      (assert (= (listLength recs) 2) "runGatesIn! returns one record per gate")
      (assert (listContains? slowKeys "skipped") "runGatesIn! skips the slow gate with a skipped field instead of running it")
      (assert (listContains? slowKeys "recordedMs") "the skip record carries recordedMs")
      (assert (listContains? slowKeys "hint") "the skip record carries a hint")
      (refute (listContains? slowKeys "stdout") "the skipped gate was not run")
      (refute (listContains? fastKeys "skipped") "the fast gate is not skipped")
      (assert (listContains? fastKeys "stdout") "the fast gate ran")
      (assert (ok? removed) "the fixture directory is removed")
      true))
