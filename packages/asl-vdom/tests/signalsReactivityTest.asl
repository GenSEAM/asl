(module asl/packages/asl-vdom/tests/signalsReactivityTest
  :x [runTests RunTests testSignalReactivity testComputedInvalidation testDualPolarityRefutations]
  :i [(aslVdom/signals :a sig)])

fn testSignalReactivity -> Bool
  (let [(sig0 (sig/makeSignal "temperature" "20"))
        (sigSub (sig/signalSubscribe sig0 "widget-thermo"))
        (sig1 (sig/signalSet sigSub "25"))]
    (assert (= (sig/signalGet sig1) "25") "signal reflects updated value")
    (refute (!= (sig/signalGet sig1) "25") "signal refutes old value")
    (assert (listContains? sig1.subscribers "widget-thermo") "subscriber preserved on update")
    (refute (listEmpty? sig1.subscribers) "subscribers list refutes empty"))
  true

fn testComputedInvalidation -> Bool
  (let [(comp0 (sig/makeComputed "fahrenheit" "68" (list "temperature")))
        (res0 (sig/computedGet comp0 "77"))
        (c1 (pairFirst res0))
        (v0 (pairSecond res0))
        (cDirty (sig/computedInvalidate c1))
        (res1 (sig/computedGet cDirty "77"))
        (v1 (pairSecond res1))]
    (assert (= v0 "68") "clean computed returns cached value")
    (refute (!= v0 "68") "clean computed refutes non-cached value")
    (assert cDirty.dirty "invalidated computed is dirty")
    (refute (not cDirty.dirty) "dirty flag refutes false")
    (assert (= v1 "77") "dirty computed propagates recomputed value")
    (refute (!= v1 "77") "computed refutes divergence"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(sigA (sig/makeSignal "a" "10"))
        (sigDup (sig/signalSubscribe (sig/signalSubscribe sigA "sub1") "sub1"))]
    (assert (= (listLength sigDup.subscribers) 1) "subscribing existing subscriber is idempotent")
    (refute (!= (listLength sigDup.subscribers) 1) "subscribers count refutes duplication"))
  true

fn runTests -> Bool
  (do
    (assert (testSignalReactivity) "testSignalReactivity passed")
    (assert (testComputedInvalidation) "testComputedInvalidation passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
