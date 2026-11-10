(module aslAgent/tests/gateTimeoutRaiseTest
  :x [runTests]
  :i [(aslAgent/gates :a gd) (aslAgent/gitOps :a go)])

fn writeFixture path: String -> Bool
  (match (fileWrite path "(:suiteTime :suite \"raiseTest.asl\" :ms 4000)\n(:suiteTime :suite \"hugeTest.asl\" :ms 3000000)\n(:suiteTime :suite \"sleepTest.asl\" :ms 4000)\n")
    ((ok _) true)
    ((err _) false))

fn ! runTests -> Bool
  (let [tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/gateTimeoutRaise" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        real (resultOr (realPath tmp) tmp)
        path (str real "/gateTimes.asn")
        wrote (writeFixture path)
        recs (go/runGatesIn! (list (pair "g1" "true raiseTest.asl") (pair "g2" "true hugeTest.asl") (pair "g3" "true plainTest.asl") (pair "g4" "/bin/sh -c 'sleep 3' sleepTest.asl")) real 2 (none) (none) path)
        r1 (optionOr (listGet recs 0) (list))
        r2 (optionOr (listGet recs 1) (list))
        r3 (optionOr (listGet recs 2) (list))
        r4 (optionOr (listGet recs 3) (list))
        removed (pathRemove real)]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert wrote "the fixture times file is written")
      (assert (= (listLength recs) 4) "one record per gate")
      (assert (= (gd/gateRaisedSec 4000) 6) "4000 ms x 1.5 raises to 6 s")
      (assert (= (gd/gateRaisedSec 4001) 7) "the raised value rounds up")
      (assert (= (gd/gateTimeoutCapSec) 3600) "the cap is 3600 s")
      (assert (= (go/recGet r1 "exit") (some (go/rInt 0))) "the over-timeout gate ran and exited 0")
      (assert (none? (go/recGet r1 "skipped")) "the over-timeout gate is not skipped")
      (assert (= (go/recGet r1 "timeoutSec") (some (go/rInt 6))) "the receipt carries the raised timeoutSec 6")
      (assert (= (go/recGet r1 "recordedMs") (some (go/rInt 4000))) "the receipt carries recordedMs")
      (assert (= (go/recGet r1 "raised") (some (go/rStr "gateTimes"))) "the receipt says raised by gateTimes")
      (assert (= (go/recGet r2 "skipped") (some (go/rStr "gateTimeoutFit"))) "a record beyond the cap is still skipped")
      (assert (some? (go/recGet r2 "hint")) "the cap skip keeps its hint")
      (assert (= (go/recGet r2 "timeoutSec") (some (go/rInt 2))) "the skip reports the plain timeout")
      (assert (= (go/recGet r3 "exit") (some (go/rInt 0))) "a gate without a record runs")
      (assert (none? (go/recGet r3 "raised")) "a gate without a record is not raised")
      (assert (none? (go/recGet r3 "timeoutSec")) "a gate without a record keeps the plain timeout")
      (assert (= (go/recGet r4 "exit") (some (go/rInt 0))) "a 3 s gate recorded at 4000 ms with timeout 2 finishes under the raised timeout")
      (assert (none? (go/recGet r4 "timeout")) "the 3 s gate did not time out")
      (assert (ok? removed) "the fixture directory is removed")
      true))
