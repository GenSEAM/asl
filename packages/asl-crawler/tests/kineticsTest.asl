(module aslCrawlerTests/kineticsTest
  :x [testBezierEndpoints testBezierInterpolation testFittsLawTiming testScrollDecayVelocity testKineticsProfileDefaults testBehavioralNoiseAndErraticTrajectory runTests]
  :i [(kinetics :a kn)])

fn testBezierEndpoints -> Bool
  (let [(p0 (kn/makePoint 100 100))
        (p1 (kn/makePoint 150 200))
        (p2 (kn/makePoint 250 300))
        (p3 (kn/makePoint 400 500))
        (startPt (kn/evaluateBezier p0 p1 p2 p3 0.0))
        (endPt (kn/evaluateBezier p0 p1 p2 p3 1.0))]
    (do
      (assert (== startPt.x 100) "Bezier start X must equal P0 X")
      (assert (== startPt.y 100) "Bezier start Y must equal P0 Y")
      (assert (== endPt.x 400) "Bezier end X must equal P3 X")
      (assert (== endPt.y 500) "Bezier end Y must equal P3 Y")
      (refute (== startPt.x 400) "start X refutes end X")
      true))

fn testBezierInterpolation -> Bool
  (let [(p0 (kn/makePoint 0 0))
        (p1 (kn/makePoint 0 100))
        (p2 (kn/makePoint 100 100))
        (p3 (kn/makePoint 100 0))
        (midPt (kn/evaluateBezier p0 p1 p2 p3 0.5))]
    (do
      (assert (== midPt.x 50) "Symmetric Bezier mid X must be 50")
      (assert (== midPt.y 75) "Symmetric Bezier mid Y must be 75")
      (refute (== midPt.y 0) "mid Y refutes zero")
      true))

fn testFittsLawTiming -> Bool
  (let [(prof (kn/defaultKineticsProfile))
        (tShort (kn/computeFittsTime prof 100 50))
        (tLong (kn/computeFittsTime prof 800 50))
        (tSmallTarget (kn/computeFittsTime prof 800 10))]
    (do
      (assert (> tLong tShort) "Long distance must require more time than short")
      (assert (> tSmallTarget tLong) "Smaller target width must require more time")
      (assert (>= tShort 100) "Movement time must have a non-zero physiological minimum")
      (refute (<= tShort 0) "Movement time refutes non-positive")
      true))

fn testScrollDecayVelocity -> Bool
  (let [(v0 1000)
        (v1 (kn/computeScrollDecay v0 100 0.005))
        (v2 (kn/computeScrollDecay v0 300 0.005))
        (v3 (kn/computeScrollDecay v0 600 0.005))]
    (do
      (assert (< v1 v0) "Velocity after 100ms must be lower than v0")
      (assert (< v2 v1) "Velocity after 300ms must be lower than 100ms")
      (assert (< v3 v2) "Velocity after 600ms must be lower than 300ms")
      (assert (>= v3 0) "Velocity must remain non-negative")
      (refute (== v1 v0) "v1 refutes unchanged v0")
      true))

fn testKineticsProfileDefaults -> Bool
  (let [(prof (kn/defaultKineticsProfile))]
    (do
      (assert (== prof.a 150) "default Fitts intercept a")
      (assert (== prof.b 120) "default Fitts slope b")
      (assert (== prof.tremorFreqHz 10) "physiological tremor frequency in 8-12Hz band")
      (assert (> prof.maxJitterPixels 0) "jitter pixels positive")
      true))

fn testBehavioralNoiseAndErraticTrajectory -> Bool
  (let [(cfg (kn/makeDefaultNoiseConfig))
        (p0 (kn/makePoint 10 10))
        (p3 (kn/makePoint 200 300))
        (erratic (kn/generateErraticTrajectory p0 p3 5))
        (overshoot (kn/computeOvershootPoint p0 p3 0.1))]
    (do
      (assert cfg.enableTwitch "twitch enabled in default config")
      (assert cfg.enableSafeClicks "safe clicks enabled")
      (assert (> (listLength erratic) 2) "erratic trajectory contains intermediate points")
      (assert (> overshoot.x p3.x) "overshoot X extends past target")
      true))

fn runTests -> Bool
  (and (testBezierEndpoints)
       (testBezierInterpolation)
       (testFittsLawTiming)
       (testScrollDecayVelocity)
       (testKineticsProfileDefaults)
       (testBehavioralNoiseAndErraticTrajectory))
