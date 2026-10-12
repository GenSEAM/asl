(module asl-runtime/tests/mathTest
  :x [testClampToGrid testClampToGridStepZero! testRunningEma testWelfordVariance testWelfordStdDevLarge runTests main]
  :i [(asl-runtime/math :a math)])

fn testClampToGrid -> Bool
  (let [(c1 (math/clampToGrid 105.4321 0.01))
        (c2 (math/clampToGrid 0.085432 0.00001))
        (c3 (math/clampToGrid 100.0 0.5))
        (c4 (math/clampToGrid 1.23e-7 1.0e-9))]
    (assert (<= (- c1 105.43) 0.0001) "105.4321 clamped to 0.01 must be 105.43")
    (assert (<= (- c2 0.08543) 0.000001) "0.085432 clamped to 0.00001 must be 0.08543")
    (assert (= c3 100.0) "100.0 clamped to 0.5 must be 100.0")
    (assert (= c4 1.23e-7) "1.23e-7 clamped to 1.0e-9 must be 1.23e-7")
    (refute (= c1 105.4321) "c1 must not equal unclamped value")
    true)

fn testClampToGridStepZero! -> Bool
  (let [(res (processRun "bin/asl run asl/packages/asl-runtime/tests/mathTest.asl stepZero"))]
    (assert (= res.exitCode 1) "clampToGrid with step 0.0 must fail")
    true)

fn testRunningEma -> Bool
  (let [(ema0 100.0)
        (ema1 (math/runningEma ema0 110.0 0.2))]
    (assert (= ema1 102.0) "Running EMA with alpha 0.2 must be 102.0")
    (refute (= ema1 100.0) "Running EMA must move toward new value")
    true)

fn testWelfordVariance -> Bool
  (let [(w0 (math/initWelford))
        (w1 (math/welfordUpdate w0 10.0))
        (w2 (math/welfordUpdate w1 20.0))
        (w3 (math/welfordUpdate w2 30.0))]
    (assert (= w3.count 3) "Welford count must be 3")
    (assert (= w3.mean 20.0) "Welford mean must be 20.0")
    (assert (> (math/welfordVariance w3) 0.0) "Sample variance must be strictly positive")
    (assert (> (math/welfordStdDev w3) 0.0) "Standard deviation must be strictly positive")
    (refute (<= (math/welfordVariance w3) 0.0) "Variance must refute non-positive")
    true)

fn testWelfordStdDevLarge -> Bool
  (let [(w (math/welfordUpdate (math/welfordUpdate (math/welfordUpdate (math/initWelford) -100000000.0) 0.0) 100000000.0))
        (sd (math/welfordStdDev w))]
    (assert (= (math/welfordVariance w) 10000000000000000.0) "variance of -1e8 0 1e8 is 1e16")
    (assert (< (abs (- sd 100000000.0)) 0.001) "std dev of variance 1e16 is 1e8")
    true)

fn ! runTests -> Bool
  (do
    (assert (testClampToGrid) "Clamp to grid test must pass")
    (assert (testClampToGridStepZero!) "Clamp to grid zero step test must pass")
    (assert (testRunningEma) "Running EMA test must pass")
    (assert (testWelfordVariance) "Welford variance test must pass")
    (assert (testWelfordStdDevLarge) "Welford std dev on large variance must pass")
    true)

fn main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listHead args) ""))]
    (cond
      ((= mode "stepZero")
        (let [(r (math/clampToGrid 100.0 0.0))]
          (ok 0)))
      (else (ok 0))))
