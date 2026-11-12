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

fn stampsOf text: String id: String kind: String -> (List Int64)
  (map (fn [l] (optionOr (stringToInt64 (optionOr (listGet (stringSplit l " ") 2) "")) -1))
    (filter (fn [l] (and (= (optionOr (listGet (stringSplit l " ") 0) "") id) (= (optionOr (listGet (stringSplit l " ") 1) "") kind)))
      (stringLines text)))

fn firstOf xs: (List Int64) -> Int64
  (optionOr (listHead xs) -1)

fn minOf xs: (List Int64) -> Int64
  (fold (fn [a x] (if (or (< a 0) (< x a)) x a)) -1 xs)

fn maxOf xs: (List Int64) -> Int64
  (fold (fn [a x] (if (> x a) x a)) -1 xs)

fn ! stamped id: String secs: Int64 tail: String -> String
  (str "sh ./stamp.sh " id " S; sleep " (stringFromInt64 secs) "; sh ./stamp.sh " id " E; " tail)

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! runTests -> Bool
  (let [tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/gatesParallel" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        script (fileWrite (str tmp "/stamp.sh") "perl -MTime::HiRes=time -e 'printf \"%s %s %.0f\\n\",$ARGV[0],$ARGV[1],time*1000' \"$1\" \"$2\" >> stamps\n")
        times (str tmp "/gateTimes.asn")
        gates (list (pair "1" (stamped "1" 2 "echo one")) (pair "2" (stamped "2" 2 "echo two; exit 1")) (pair "3" (stamped "3" 2 "echo three")))
        recs (go/runGatesIn! gates tmp 60 (none) (none) times)
        st (readOr (str tmp "/stamps"))
        r1 (optionOr (listGet recs 0) (list))
        r2 (optionOr (listGet recs 1) (list))
        r3 (optionOr (listGet recs 2) (list))
        starts (map (fn [i] (firstOf (stampsOf st i "S"))) (list "1" "2" "3"))
        ends (map (fn [i] (firstOf (stampsOf st i "E"))) (list "1" "2" "3"))
        wipe (fileWrite (str tmp "/stamps") "")
        seqRecs (go/runGatesPar! gates tmp 60 (none) (none) 1)
        sq (readOr (str tmp "/stamps"))
        sqStart (map (fn [i] (firstOf (stampsOf sq i "S"))) (list "1" "2" "3"))
        sqEnd (map (fn [i] (firstOf (stampsOf sq i "E"))) (list "1" "2" "3"))
        wipe2 (fileWrite (str tmp "/stamps") "")
        buildGates (list (pair "b" (stamped "b" 1 "true build.sh")) (pair "1" (stamped "1" 1 "echo a")) (pair "2" (stamped "2" 1 "echo b")))
        buildRecs (go/runGatesIn! buildGates tmp 60 (none) (none) times)
        bs (readOr (str tmp "/stamps"))
        bEnd (firstOf (stampsOf bs "b" "E"))
        postStarts (list (firstOf (stampsOf bs "1" "S")) (firstOf (stampsOf bs "2" "S")))
        postEnds (list (firstOf (stampsOf bs "1" "E")) (firstOf (stampsOf bs "2" "E")))
        removed (pathRemove tmp)]
    (do
      (assert (and (ok? made) (ok? script)) "the fixture directory and stamp script are created")
      (assert (= (listLength recs) 3) "one receipt per gate")
      (assert (and (= (textOf r1 "id") "1") (and (= (textOf r2 "id") "2") (= (textOf r3 "id") "3"))) "receipts keep the original gate order")
      (assert (and (= (exitOf r1) 0) (and (= (exitOf r2) 1) (= (exitOf r3) 0))) "each gate keeps its own exit code")
      (assert (and (stringContains? (textOf r1 "stdout") "one") (and (stringContains? (textOf r2 "stdout") "two") (stringContains? (textOf r3 "stdout") "three"))) "each receipt holds its own stdout")
      (assert (and (> (minOf starts) 0) (and (> (minOf ends) 0) (< (maxOf starts) (minOf ends)))) "the three gates overlap: the last start precedes the first end")
      (assert (and (= (listLength seqRecs) 3) (and (= (exitOf (optionOr (listGet seqRecs 1) (list))) 1) (= (textOf (optionOr (listGet seqRecs 2) (list)) "id") "3"))) "limit 1 returns the same receipts in order")
      (assert (and (> (firstOf sqStart) 0) (and (>= (optionOr (listGet sqStart 1) 0) (optionOr (listGet sqEnd 0) 1)) (>= (optionOr (listGet sqStart 2) 0) (optionOr (listGet sqEnd 1) 1)))) "limit 1 runs the gates strictly in sequence")
      (assert (and (= (listLength buildRecs) 3) (and (= (exitOf (optionOr (listGet buildRecs 0) (list))) 0) (= (exitOf (optionOr (listGet buildRecs 2) (list))) 0))) "gates after a passing build.sh run and report in order")
      (assert (and (> bEnd 0) (and (>= (minOf postStarts) bEnd) (< (maxOf postStarts) (minOf postEnds)))) "the gates after build.sh start after it ends and overlap each other")
      (assert (ok? removed) "the fixture directory is removed")
      true))
