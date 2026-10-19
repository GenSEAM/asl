(module asl-target-llvm/tests/fixtures/nativePerf/filterNonBoolProbe
  :x [main]
  :i [])

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "split out of trapProbe.asl's filterNonBool case: filter's predicate returns Int64 (x + b) where a Bool is required, a genuine static type error, not a runtime trap; asserted as a rejection by nativePerfTest's testStaticTypeRejections")
fn arg args: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (listGet args i) "0")) 0)

fn ! main args: (List String) -> (Result Unit String)
  (let [(a (arg args 1)) (b (arg args 2))]
    (do (println (str (filter (fn [x] (+ x b)) (list a 2)))) (ok ())))
