(module asl-vector/tests/vectorTest
  :x [RunTests runTests testVectorDotProductFast testVectorNormFast testVectorCosineSimilarityFast]
  :i [(asl-vector/vector :a vec)])

fn testVectorDotProductFast -> Bool
  (let [(v1 (vec/makeVector (list 1 2 3 4)))
        (v2 (vec/makeVector (list 1 2 3 4)))
        (dot (vec/vectorDotProductFast v1 v2))]
    (assert (= dot 30) "dot product of [1,2,3,4] with itself is 30")
    (refute (!= dot 30) "dot product refutes non-30")
    true)

fn testVectorNormFast -> Bool
  (let [(v (vec/makeVector (list 3 4 0 0)))
        (norm (vec/vectorNormFast v))]
    (assert (= norm 5.0) "norm of [3,4,0,0] is 5")
    true)

fn testVectorCosineSimilarityFast -> Bool
  (let [(v1 (vec/makeVector (list 1 0 0 0)))
        (v2 (vec/makeVector (list 1 0 0 0)))
        (sim (vec/vectorCosineSimilarityFast v1 v2))]
    (assert (= sim 1000) "cosine similarity of identical unit vectors is scaled 1000")
    true)

fn RunTests -> Bool
  (and
    (testVectorDotProductFast)
    (testVectorNormFast)
    (testVectorCosineSimilarityFast))

fn runTests -> Bool
  (RunTests)
