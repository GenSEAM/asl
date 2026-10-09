(module aslCrawler/kinetics
  :x [Point KineticsProfile BehavioralNoiseConfig makePoint defaultKineticsProfile makeDefaultNoiseConfig evaluateBezier computeFittsTime computeScrollDecay computeTremorJitter generateKineticTrajectory computeOvershootPoint generateErraticTrajectory]
  :i [])

(schema Point
  (:f x I64)
  (:f y I64))

(schema KineticsProfile
  (:f a I64)
  (:f b I64)
  (:f tremorFreqHz I64)
  (:f maxJitterPixels I64))

(schema BehavioralNoiseConfig
  (:f enableTwitch Bool)
  (:f enableSafeClicks Bool)
  (:f enableHarmlessKeys Bool)
  (:f twitchMinPx I64)
  (:f twitchMaxPx I64)
  (:f idleIntervalMs I64))

fn makePoint x: I64 y: I64 -> Point
  (Point :x x :y y)

fn defaultKineticsProfile -> KineticsProfile
  (KineticsProfile :a 150 :b 120 :tremorFreqHz 10 :maxJitterPixels 3)

fn makeDefaultNoiseConfig -> BehavioralNoiseConfig
  (BehavioralNoiseConfig
    :enableTwitch true
    :enableSafeClicks true
    :enableHarmlessKeys true
    :twitchMinPx 1
    :twitchMaxPx 4
    :idleIntervalMs 2500)

fn evaluateBezier p0: Point p1: Point p2: Point p3: Point t: F64 -> Point
  (let [(u (- 1.0 t))
        (u2 (* u u))
        (u3 (* u2 u))
        (t2 (* t t))
        (t3 (* t2 t))
        (c0 u3)
        (c1 (* (* 3.0 u2) t))
        (c2 (* (* 3.0 u) t2))
        (c3 t3)
        (x0 (int64ToFloat64 p0.x))
        (y0 (int64ToFloat64 p0.y))
        (x1 (int64ToFloat64 p1.x))
        (y1 (int64ToFloat64 p1.y))
        (x2 (int64ToFloat64 p2.x))
        (y2 (int64ToFloat64 p2.y))
        (x3 (int64ToFloat64 p3.x))
        (y3 (int64ToFloat64 p3.y))
        (resX (+ (+ (* c0 x0) (* c1 x1)) (+ (* c2 x2) (* c3 x3))))
        (resY (+ (+ (* c0 y0) (* c1 y1)) (+ (* c2 y2) (* c3 y3))))
        (intX (wholeInt (+ resX 0.5)))
        (intY (wholeInt (+ resY 0.5)))]
    (Point :x intX :y intY))

fn approxLog2 n: I64 -> I64
  (if (<= n 1) 0
    (if (<= n 2) 1
      (if (<= n 4) 2
        (if (<= n 8) 3
          (if (<= n 16) 4
            (if (<= n 32) 5
              (if (<= n 64) 6
                (if (<= n 128) 7
                  (if (<= n 256) 8
                    (if (<= n 512) 9
                      (if (<= n 1024) 10
                        (if (<= n 2048) 11
                          (if (<= n 4096) 12
                            (+ 13 (approxLog2 (/ n 8192))))))))))))))))

fn computeFittsTime prof: KineticsProfile distance: I64 targetWidth: I64 -> I64
  (let [(d (if (<= distance 0) 1 distance))
        (w (if (<= targetWidth 0) 1 targetWidth))
        (ratio (+ 1 (/ (* 2 d) w)))
        (id (approxLog2 ratio))
        (calcTime (+ prof.a (* prof.b id)))]
    (if (< calcTime 100) 100 calcTime))

fn computeScrollDecay v0: I64 elapsedMs: I64 lambdaDecay: F64 -> I64
  (if (<= v0 0) 0
    (if (<= elapsedMs 0) v0
      (let [(decayFactor (+ 1.0 (* lambdaDecay (int64ToFloat64 elapsedMs))))
            (currV (/ (int64ToFloat64 v0) decayFactor))
            (intV (wholeInt currV))]
        (if (< intV 0) 0 intV))))

fn computeTremorJitter prof: KineticsProfile stepIndex: I64 -> Point
  (let [(freq prof.tremorFreqHz)
        (maxAmp prof.maxJitterPixels)
        (cycle (mod stepIndex 4))
        (jx (cond ((== cycle 0) maxAmp)
                  ((== cycle 1) 0)
                  ((== cycle 2) (- 0 maxAmp))
                  (else 0)))
        (jy (cond ((== cycle 0) 0)
                  ((== cycle 1) maxAmp)
                  ((== cycle 2) 0)
                  (else (- 0 maxAmp))))]
    (Point :x jx :y jy))

fn generateKineticTrajectory p0: Point p3: Point stepsCount: I64 -> (List Point)
  (let [(steps (if (<= stepsCount 2) 2 stepsCount))
        (dx (- p3.x p0.x))
        (dy (- p3.y p0.y))
        (p1 (Point :x (+ p0.x (/ dx 4)) :y (+ p0.y (/ dy 2))))
        (p2 (Point :x (+ p0.x (/ (* 3 dx) 4)) :y (+ p0.y (/ (* 3 dy) 4))))]
    (list p0 p1 p2 p3))

fn computeOvershootPoint p0: Point p3: Point ratio: F64 -> Point
  (let [(dx (- p3.x p0.x))
        (dy (- p3.y p0.y))
        (addX (wholeInt (+ (* (int64ToFloat64 dx) ratio) 1.0)))
        (addY (wholeInt (+ (* (int64ToFloat64 dy) ratio) 1.0)))
        (ox (+ p3.x addX))
        (oy (+ p3.y addY))]
    (Point :x ox :y oy))

fn generateErraticTrajectory p0: Point p3: Point stepsCount: I64 -> (List Point)
  (let [(overshoot (computeOvershootPoint p0 p3 0.08))
        (dx (- p3.x p0.x))
        (dy (- p3.y p0.y))
        (p1 (Point :x (+ p0.x (/ dx 3)) :y (+ (+ p0.y (/ dy 3)) 6)))
        (p2 (Point :x (+ p0.x (/ (* 2 dx) 3)) :y (- (+ p0.y (/ (* 2 dy) 3)) 4)))]
    (list p0 p1 overshoot p2 p3))

fn wholeInt x: F64 -> I64
  (let [(n (float64ToInt64 x))]
    (do (assert (some? n) "wholeInt: x must be finite and within Int64")
        (optionOr n 0)))
