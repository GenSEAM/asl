(module aslAgent/tests/gatesParallelTest
  :x [runTests]
  :i [(aslAgent/gitOps :a go)])

fn exitOf rec: (List (Pair String go/RVal)) -> Int64
  (match (go/recGet rec "exit")
    ((some v) (match v ((go/rInt x) x) (_ -1)))
    ((none) -2))

fn textOf rec: (List (Pair String go/RVal)) key: String -> String
  (match (go/recGet rec key)
    ((some v) (match v ((go/rStr s) s) (_ "")))
    ((none) ""))

fn ! runTests -> Bool
  (let [tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/gatesParallel" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        times (str tmp "/gateTimes.asn")
        gates (list (pair "1" "sleep 2; echo one") (pair "2" "sleep 2; echo two; exit 1") (pair "3" "sleep 2; echo three"))
        t0 (monotonicNs)
        recs (go/runGatesIn! gates tmp 60 (none) (none) times)
        wallMs (/ (- (monotonicNs) t0) 1000000)
        r1 (optionOr (listGet recs 0) (list))
        r2 (optionOr (listGet recs 1) (list))
        r3 (optionOr (listGet recs 2) (list))
        t1 (monotonicNs)
        buildRecs (go/runGatesIn! (list (pair "b" "true build.sh") (pair "1" "sleep 1; echo a") (pair "2" "sleep 1; echo b")) tmp 60 (none) (none) times)
        buildMs (/ (- (monotonicNs) t1) 1000000)
        removed (pathRemove tmp)]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert (= (listLength recs) 3) "one receipt per gate")
      (assert (and (= (textOf r1 "id") "1") (and (= (textOf r2 "id") "2") (= (textOf r3 "id") "3"))) "receipts keep the original gate order")
      (assert (and (= (exitOf r1) 0) (and (= (exitOf r2) 1) (= (exitOf r3) 0))) "each gate keeps its own exit code")
      (assert (and (stringContains? (textOf r1 "stdout") "one") (and (stringContains? (textOf r2 "stdout") "two") (stringContains? (textOf r3 "stdout") "three"))) "each receipt holds its own stdout")
      (assert (< wallMs 5000) "three 2 s gates finish under 5 s, so they overlap")
      (assert (and (= (listLength buildRecs) 3) (and (= (exitOf (optionOr (listGet buildRecs 0) (list))) 0) (= (exitOf (optionOr (listGet buildRecs 2) (list))) 0))) "gates after a passing build.sh run and report in order")
      (assert (< buildMs 2000) "two 1 s gates after build.sh overlap")
      (assert (ok? removed) "the fixture directory is removed")
      true))
