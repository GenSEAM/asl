(module asl-runtime/math
  :x [WelfordState clampToGrid runningEma initWelford welfordUpdate welfordVariance welfordStdDev]
  :i [])

(schema WelfordState
  (:f count Int64)
  (:f mean Float)
  (:f m2 Float))

fn clampToGrid val: Float step: Float -> Float
  (do
    (assert (and (isFinite? step) (> step 0.0)) "clampToGrid: step must be finite and positive")
    (let [(ratio (/ val step))
          (ticks (float64ToInt64 (+ ratio (if (>= ratio 0.0) 0.5 -0.5))))]
      (do (assert (some? ticks) "clampToGrid: val / step must be a finite number within Int64")
          (* (int64ToFloat64 (optionOr ticks 0)) step))))

fn runningEma prevEma: Float val: Float alpha: Float -> Float
  (let [(a (if (< alpha 0.0) 0.0 (if (> alpha 1.0) 1.0 alpha)))]
    (+ (* a val) (* (- 1.0 a) prevEma)))

fn initWelford -> WelfordState
  (WelfordState
    :count 0
    :mean 0.0
    :m2 0.0)

fn welfordUpdate state: WelfordState val: Float -> WelfordState
  (let [(newCount (+ state.count 1))
        (delta (- val state.mean))
        (newMean (+ state.mean (/ delta (int64ToFloat64 newCount))))
        (delta2 (- val newMean))
        (newM2 (+ state.m2 (* delta delta2)))]
    (WelfordState
      :count newCount
      :mean newMean
      :m2 newM2))

fn welfordVariance state: WelfordState -> Float
  (if (< state.count 2)
    0.0
    (/ state.m2 (int64ToFloat64 (- state.count 1))))

fn welfordStdDev state: WelfordState -> Float
  (let [(v (welfordVariance state))]
    (if (<= v 0.0) 0.0 (sqrt v)))
