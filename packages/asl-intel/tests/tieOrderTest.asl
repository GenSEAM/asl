(module asl-intel/tests/tieOrderTest :x [runTests] :i [(asl-intel/trace :a tr) (asl-intel/graph :a g) (asl-intel/host :a h)])

fn hit f: String c: Int64 -> tr/FunctionHit
  (tr/FunctionHit :symbol "s" :module "m" :file f :calls c :micros 0 :status "hot" :branches 0 :asserts 0)

fn files hs: (List tr/FunctionHit) -> (List String)
  (map (fn [(h tr/FunctionHit)] -> String h.file) hs)

; (:m :ref INTEL-PARITY-RED-20261031 :do "tied rows and same-name candidates are ordered by key, not by walk or index order")
fn runTests -> Bool
  (do
    (assert (= (files (tr/sortHits (list (hit "z.asl" 3) (hit "b.asl" 3) (hit "a.asl" 3)))) (list "a.asl" "b.asl" "z.asl")) "tied calls: reverse file order sorts file ascending")
    (assert (= (files (tr/sortHits (list (hit "a.asl" 3) (hit "b.asl" 3) (hit "z.asl" 3)))) (list "a.asl" "b.asl" "z.asl")) "tied calls: file order stays")
    (assert (= (files (tr/sortHits (list (hit "a.asl" 1) (hit "z.asl" 5) (hit "b.asl" 5)))) (list "b.asl" "z.asl" "a.asl")) "calls desc outranks file asc")
    (assert (= (map (fn [(h tr/FunctionHit)] -> Int64 h.calls) (tr/sortHits (list (hit "a.asl" 2) (hit "a.asl" 2)))) (list 2 2)) "equal calls and file keep both rows")
    (assert (= (g/pickByRank (list (pair 7 0) (pair 9 1))) 7) "eta before zeta: lowest rank is the lowest index")
    (assert (= (g/pickByRank (list (pair 7 1) (pair 9 0))) 9) "zeta indexed after eta but ranked first wins")
    (assert (= (g/pickByRank (list (pair 7 1) (pair 9 1))) 7) "equal rank keeps the first")
    (assert (= (g/pickByRank (list (pair -1 0) (pair 9 5))) 9) "a negative node is skipped")
    (assert (= (g/pickByRank (list (pair -1 0))) -1) "no candidate is -1")
    (assert (= (g/pickByRank (list)) -1) "empty is -1")
    (assert (= (h/sortedTree (list "r/z" "r/a") (list "r/z.asl" "r/b.asl" "r/a.asl")) (h/sortedTree (list "r/a" "r/z") (list "r/a.asl" "r/b.asl" "r/z.asl"))) "reversed walk input gives the same tree")
    (assert (= (h/sortedTree (list) (list "r/z.asl" "r/a.asl")) (h/Tree :dirs (list) :files (list "r/a.asl" "r/z.asl"))) "files ascend")
    (assert (= (h/sortedTree (list "r/z" "r/a") (list)) (h/Tree :dirs (list "r/a" "r/z") :files (list))) "dirs ascend")
    true)
