(module asl-utils/tests/textDiffTest :x [runTests] :i [(asl-utils/textDiff :a td)])

fn lines tag: String n: Int64 -> (List String)
  (if (<= n 0)
    (list)
    (cons (str tag n) (lines tag (- n 1))))

fn testIdentical -> Bool
  (let [(src (list "a" "b" "c"))
        (hs (td/textDiff src src))]
    (do (assert (= (td/applyDiff hs) "a\nb\nc\n") "identical reproduces")
        (assert (= (td/textDiff src src) (td/textDiff src src)) "identical deterministic")
        true))

fn testAdd -> Bool
  (let [(src (list "a" "b" "c"))
        (tgt (list "a" "x" "b" "c"))
        (hs (td/textDiff src tgt))]
    (do (assert (= (td/applyDiff hs) "a\nx\nb\nc\n") "add reproduces target")
        (assert (= (listLength hs) 4) "inserting one line costs one add hunk")
        true))

fn testDelete -> Bool
  (let [(src (list "a" "b" "c"))
        (tgt (list "a" "c"))
        (hs (td/textDiff src tgt))]
    (do (assert (= (td/applyDiff hs) "a\nc\n") "delete reproduces target")
        (assert (= (listLength hs) 3) "deleting one line costs one del hunk")
        true))

fn testReplace -> Bool
  (let [(src (list "a" "b" "c"))
        (tgt (list "a" "x" "c"))
        (hs (td/textDiff src tgt))]
    (do (assert (= (td/applyDiff hs) "a\nx\nc\n") "replace reproduces target")
        (assert (= (listLength hs) 4) "replacing one line is one del plus one add")
        true))

fn testAllNew -> Bool
  (let [(src (list))
        (tgt (list "x" "y"))
        (hs (td/textDiff src tgt))]
    (do (assert (= (td/applyDiff hs) "x\ny\n") "all new reproduces target")
        true))

fn testAllDel -> Bool
  (let [(src (list "a" "b"))
        (tgt (list))
        (hs (td/textDiff src tgt))]
    (do (assert (= (td/applyDiff hs) "") "all del reproduces target")
        true))

fn testRender -> Bool
  (let [(src (list "a" "b" "c"))
        (tgt (list "a" "x" "b" "c"))
        (r (td/renderUnified "f.txt" "f.txt" src tgt))]
    (do (assert (stringContains? r "@@ -1,3 +1,4 @@") "render has correct hunk header")
        (assert (stringContains? r "+x") "render shows added line")
        true))

fn testRenderEmptySrc -> Bool
  (let [(src (list))
        (tgt (list "x"))
        (r (td/renderUnified "f.txt" "f.txt" src tgt))]
    (do (assert (stringContains? r "@@ -0,0 +1,1 @@") "empty src renders 0,0")
        true))

fn testDisjoint200 -> Bool
  (let [(src (lines "a" 200))
        (tgt (lines "b" 200))
        (hs (td/textDiff src tgt))]
    (do (assert (= (listLength hs) 400) "two disjoint 200-line inputs diff in linear hunks")
        (assert (= (td/applyDiff hs) (fold (fn [(acc String) (l String)] -> String (str acc l "\n")) "" tgt))
                "disjoint 200-line diff reproduces the target")
        true))

fn runTests -> Bool
  (and (testIdentical) (testAdd) (testDelete) (testReplace)
       (testAllNew) (testAllDel) (testRender) (testRenderEmptySrc)
       (testDisjoint200))
