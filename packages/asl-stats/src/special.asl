(module asl-stats/special
  :x [lgamma betaInc gammaIncP normalCdf normalQuantile studentCdf studentQuantile betaQuantile]
  :i [])

; (:m :ref workspace-20261031-experimentStats :do "special functions in Float64 with no builtin support: Lanczos lgamma (g 7, 9 terms), regularized incomplete beta and gamma by series and modified Lentz continued fraction, quantiles by bisection on the monotone cdf; stated accuracy about 1e-12 absolute, tests use 1e-9")
fn pi -> Float64
  3.141592653589793

fn lanczos -> (List Float64)
  (list 0.99999999999980993 676.5203681218851 -1259.1392167224028 771.32342877765313 -176.61502916214059 12.507343278686905 -0.13857109526572012 9.9843695780195716e-6 1.5056327351493116e-7)

fn ! lanczosSum! cs: (List Float64) x: Float64 i: Int64 acc: Float64 -> Float64
  (match (listHead cs)
    ((none) acc)
    ((some c) (lanczosSum! (optionOr (listTail cs) (list)) x (+ i 1) (+ acc (/ c (+ x (int64ToFloat64 i)))))))

fn lgamma x: Float64 -> Float64
  (if (< x 0.5)
    (- (log (/ (pi) (abs (sin (* (pi) x))))) (lgamma (- 1.0 x)))
    (let [(y (- x 1.0))
          (cs (lanczos))
          (a (lanczosSum! (optionOr (listTail cs) (list)) y 1 (optionOr (listHead cs) 0.0)))
          (t (+ y 7.5))]
      (+ (+ (* 0.5 (log (* 2.0 (pi)))) (* (+ y 0.5) (log t))) (+ (- 0.0 t) (log a)))))

fn ! betaCf! x: Float64 a: Float64 b: Float64 m: Int64 c: Float64 d: Float64 h: Float64 -> Float64
  (if (> m 400) h
    (let [(mf (int64ToFloat64 m))
          (m2 (* 2.0 mf))
          (qab (+ a b))
          (qap (+ a 1.0))
          (qam (- a 1.0))
          (aa1 (/ (* (* mf (- b mf)) x) (* (+ qam m2) (+ a m2))))
          (d1 (tiny (+ 1.0 (* aa1 d))))
          (c1 (tiny (+ 1.0 (/ aa1 c))))
          (dd1 (/ 1.0 d1))
          (h1 (* h (* dd1 c1)))
          (aa2 (/ (* (* (- 0.0 (+ a mf)) (+ qab mf)) x) (* (+ a m2) (+ qap m2))))
          (d2 (tiny (+ 1.0 (* aa2 dd1))))
          (c2 (tiny (+ 1.0 (/ aa2 c1))))
          (dd2 (/ 1.0 d2))
          (del (* dd2 c2))
          (h2 (* h1 del))]
      (if (< (abs (- del 1.0)) 3.0e-16) h2 (betaCf! x a b (+ m 1) c2 dd2 h2))))

fn tiny v: Float64 -> Float64
  (if (< (abs v) 1.0e-300) 1.0e-300 v)

fn betaCfStart x: Float64 a: Float64 b: Float64 -> Float64
  (let [(d0 (tiny (- 1.0 (/ (* (+ a b) x) (+ a 1.0)))))
        (d1 (/ 1.0 d0))]
    (betaCf! x a b 1 1.0 d1 d1))

fn betaInc x: Float64 a: Float64 b: Float64 -> Float64
  (cond
    ((<= x 0.0) 0.0)
    ((>= x 1.0) 1.0)
    (else
      (let [(bt (exp (+ (+ (- (lgamma (+ a b)) (+ (lgamma a) (lgamma b))) (* a (log x))) (* b (log (- 1.0 x))))))]
        (if (< x (/ (+ a 1.0) (+ (+ a b) 2.0)))
          (/ (* bt (betaCfStart x a b)) a)
          (- 1.0 (/ (* bt (betaCfStart (- 1.0 x) b a)) b))))))

fn ! gammaSeries! a: Float64 x: Float64 n: Int64 term: Float64 sum: Float64 -> Float64
  (if (> n 1000) sum
    (let [(ap (+ a (int64ToFloat64 n)))
          (t (* term (/ x ap)))
          (s (+ sum t))]
      (if (< (abs t) (* (abs s) 1.0e-17)) s (gammaSeries! a x (+ n 1) t s))))

fn ! gammaCf! a: Float64 x: Float64 i: Int64 b: Float64 c: Float64 d: Float64 h: Float64 -> Float64
  (if (> i 1000) h
    (let [(fi (int64ToFloat64 i))
          (an (* (- 0.0 fi) (- fi a)))
          (b1 (+ b 2.0))
          (d1 (/ 1.0 (tiny (+ (* an d) b1))))
          (c1 (tiny (+ b1 (/ an c))))
          (del (* d1 c1))
          (h1 (* h del))]
      (if (< (abs (- del 1.0)) 3.0e-16) h1 (gammaCf! a x (+ i 1) b1 c1 d1 h1))))

fn gammaIncP a: Float64 x: Float64 -> Float64
  (cond
    ((<= x 0.0) 0.0)
    ((< x (+ a 1.0))
      (* (gammaSeries! a x 1 (/ 1.0 a) (/ 1.0 a)) (exp (- (- (* a (log x)) x) (lgamma a)))))
    (else
      (let [(b (+ (- x a) 1.0))
            (c (/ 1.0 1.0e-300))
            (d (/ 1.0 b))
            (h (gammaCf! a x 1 b c d d))]
        (- 1.0 (* (exp (- (- (* a (log x)) x) (lgamma a))) h)))))

fn normalCdf z: Float64 -> Float64
  (let [(p (gammaIncP 0.5 (/ (* z z) 2.0)))]
    (if (>= z 0.0) (* 0.5 (+ 1.0 p)) (* 0.5 (- 1.0 p))))

fn ! bisect! f: (fn [Float64] -> Float64) target: Float64 lo: Float64 hi: Float64 n: Int64 -> Float64
  (if (<= n 0) (/ (+ lo hi) 2.0)
    (let [(mid (/ (+ lo hi) 2.0))]
      (if (< (f mid) target)
        (bisect! f target mid hi (- n 1))
        (bisect! f target lo mid (- n 1)))))

fn normalQuantile p: Float64 -> Float64
  (bisect! normalCdf p -40.0 40.0 120)

fn studentCdf t: Float64 df: Float64 -> Float64
  (let [(i (betaInc (/ df (+ df (* t t))) (/ df 2.0) 0.5))]
    (if (> t 0.0) (- 1.0 (* 0.5 i)) (* 0.5 i)))

fn studentQuantile p: Float64 df: Float64 -> Float64
  (bisect! (fn [(t Float64)] -> Float64 (studentCdf t df)) p -1.0e7 1.0e7 200)

fn betaQuantile p: Float64 a: Float64 b: Float64 -> Float64
  (bisect! (fn [(x Float64)] -> Float64 (betaInc x a b)) p 0.0 1.0 200)
