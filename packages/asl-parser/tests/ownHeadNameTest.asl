(module asl-parser/tests/ownHeadNameTest
  :x [runTests])

; (:m :ref MISS-ABSORB :do "a module that defines % calls its own function, by execution: the reader takes (% a b) as (mod a b) only where the module does not use the name itself")
fn % a: Int64 b: Int64 -> Int64
  (+ (* a 100) b)

fn viaLet n: Int64 -> Int64
  (let [(k (% n 3))] (+ k 1))

fn ! runTests -> Bool
  (do
    (assert (= (viaLet 7) 704) (str "the module's own % runs, not mod: 704, got " (stringFromInt64 (viaLet 7))))
    (assert (= (% (viaLet 7) 3) 70403) (str "also as a direct call: 70403, got " (stringFromInt64 (% (viaLet 7) 3))))
    true)
