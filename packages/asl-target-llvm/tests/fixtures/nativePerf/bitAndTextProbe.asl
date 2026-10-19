(module asl-target-llvm/tests/fixtures/nativePerf/bitAndTextProbe
  :x [main]
  :i [])

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "split out of bitProbe.asl's andText case: & applied to a String Val, a genuine static type error, not a runtime trap; asserted as a rejection by nativePerfTest's testBits")
fn arg args: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (listGet args i) "0")) 0)

fn ! main args: (List String) -> (Result Unit String)
  (let [(which (optionOr (listHead args) "")) (a (arg args 1))]
    (do (println (str ((fn [x y] (& x y)) a which))) (ok ())))
