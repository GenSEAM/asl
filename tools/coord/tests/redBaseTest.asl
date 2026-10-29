(module asl-tools/coord/tests/redBaseTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd)])

; (:m :ref REDBEFORE-SHARE :do "the red-before memo: a genuine red at a sha and gate runs once and is reused by the next gate stage of the unit; another sha or gate, a timeout exit, a green base and a damaged memo all run afresh; the counter file counts real runs")
fn ! runs counter: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString counter) ""))))

fn ! fake counter: String r: (Pair Int64 Int64) -> (fn [] -> (Pair Int64 Int64))
  (fn [] -> (Pair Int64 Int64) (do (fileAppend counter "x\n") r))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/redBaseTest-" (stringFromInt64 (procSelf))))
        (_ (dirCreate dir))
        (memo (str dir "/u-redbase.asn"))
        (ctr (str dir "/count"))
        (red (pair 1 5))
        (a (cd/redCached! memo "aaa" "asl test x" (fake ctr red)))
        (_ (assert (and (= (pairFirst a) 1) (= (pairSecond a) 5) (= (runs ctr) 1)) "the first stage runs the gate at the base"))
        (_ (assert (fileExists? memo) "a genuine red is remembered"))
        (b (cd/redCached! memo "aaa" "asl test x" (fake ctr (pair 9 9))))
        (_ (assert (and (= (pairFirst b) 1) (= (pairSecond b) 5) (= (runs ctr) 1)) "the same sha and gate reuses the memo without running"))
        (_ (cd/redCached! memo "bbb" "asl test x" (fake ctr red)))
        (_ (assert (= (runs ctr) 2) "another base sha runs afresh"))
        (_ (cd/redCached! memo "bbb" "asl test y" (fake ctr red)))
        (_ (assert (= (runs ctr) 3) "another gate runs afresh"))
        (_ (cd/redCached! memo "ccc" "g" (fake ctr (pair 124 0))))
        (_ (cd/redCached! memo "ccc" "g" (fake ctr (pair 124 0))))
        (_ (assert (= (runs ctr) 5) "a timeout exit is never remembered"))
        (_ (cd/redCached! memo "ddd" "g" (fake ctr (pair 0 4))))
        (_ (cd/redCached! memo "ddd" "g" (fake ctr (pair 0 4))))
        (_ (assert (= (runs ctr) 7) "a green base is never remembered"))
        (_ (fileWrite memo "garbage"))
        (_ (cd/redCached! memo "aaa" "asl test x" (fake ctr red)))
        (_ (assert (= (runs ctr) 8) "a damaged memo runs afresh"))
        (_ (assert (stringContains? (cd/redBaseRow "s" "g \"q\"" red) ":gate \"g \\\"q\\\"\"") "the gate text is quoted in the row"))
        (_ (pathRemove dir))]
    true)
