(module asl-target-llvm/tests/fixtures/nativePerf/bitNotTextProbe
  :x [main]
  :i [])

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "split out of bitProbe.asl's notText case: ~ applied to a String Val, a genuine static type error, not a runtime trap; asserted as a rejection by nativePerfTest's testBits")
fn ! main args: (List String) -> (Result Unit String)
  (let [(which (optionOr (listHead args) ""))]
    (do (println (str ((fn [x] (~ x)) which))) (ok ())))
