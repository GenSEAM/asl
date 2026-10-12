(module servedFixture/unsupportedProbe :x [runTests] :i [])

; (:m :ref HL-VERBS-REST :do "local let-bound 'recur' still rejected by native lowering")
fn runTests -> Bool
  (let [(recur (fn [(n Int64)] -> Int64 (+ n 1)))]
    (do (assert (= (recur 41) 42) "a local variable named 'recur' still runs when asl-host serves the suite")
        true))
