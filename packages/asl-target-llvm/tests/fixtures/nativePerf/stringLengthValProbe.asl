(module asl-target-llvm/tests/fixtures/nativePerf/stringLengthValProbe
  :x [main]
  :i [])

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "split out of trapProbe.asl's stringLengthVal case: applies stringLength to an Int64 instead of a String, a genuine static type error, not a runtime trap; asserted as a rejection by nativePerfTest's testStaticTypeRejections")
fn arg args: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (listGet args i) "0")) 0)

fn ! main args: (List String) -> (Result Unit String)
  (let [(a (arg args 1))]
    (do (println (str ((fn [s] (stringLength s)) a))) (ok ())))
