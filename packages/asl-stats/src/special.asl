(module asl-stats/special
  :x [lgamma betaInc gammaIncP gammaIncQ normalCdf normalSurvival normalPdf normalQuantile normalQuantileChecked studentCdf studentQuantile studentQuantileChecked betaQuantile]
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
  (if (> m 4000) h
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

fn ! gammaUpper! a: Float64 x: Float64 -> Float64
  (let [(b (+ (- x a) 1.0))
        (c (/ 1.0 1.0e-300))
        (d (/ 1.0 b))
        (h (gammaCf! a x 1 b c d d))]
    (* (exp (- (- (* a (log x)) x) (lgamma a))) h))

fn gammaIncP a: Float64 x: Float64 -> Float64
  (cond
    ((<= x 0.0) 0.0)
    ((< x (+ a 1.0))
      (* (gammaSeries! a x 1 (/ 1.0 a) (/ 1.0 a)) (exp (- (- (* a (log x)) x) (lgamma a)))))
    (else (- 1.0 (gammaUpper! a x))))

; (:m :ref NUM-LINALG-STATS :do "upper regularized incomplete gamma Q = 1 - P taken straight from the continued fraction for x >= a+1, so far tails keep full relative accuracy instead of cancelling to 0")
fn gammaIncQ a: Float64 x: Float64 -> Float64
  (cond
    ((<= x 0.0) 1.0)
    ((< x (+ a 1.0)) (- 1.0 (gammaIncP a x)))
    (else (gammaUpper! a x)))

; (:m :ref NUM-LINALG-STATS :do "normalCdf uses P(1/2,z^2/2) for z >= 0 and Q(1/2,z^2/2)/2 for z < 0, so the lower tail is accurate to about 1e-14 relative down to z = -37 (Phi(-10) = 7.619853024160527e-24 to 1e-13 relative) where 1 - P would give 0")
fn normalCdf z: Float64 -> Float64
  (if (>= z 0.0)
    (* 0.5 (+ 1.0 (gammaIncP 0.5 (/ (* z z) 2.0))))
    (* 0.5 (gammaIncQ 0.5 (/ (* z z) 2.0))))

fn normalSurvival z: Float64 -> Float64
  (normalCdf (- 0.0 z))

fn normalPdf z: Float64 -> Float64
  (/ (exp (* -0.5 (* z z))) (sqrt (* 2.0 (pi))))

fn ! bisect! f: (fn [Float64] -> Float64) target: Float64 lo: Float64 hi: Float64 n: Int64 -> Float64
  (if (<= n 0) (/ (+ lo hi) 2.0)
    (let [(mid (/ (+ lo hi) 2.0))]
      (if (< (f mid) target)
        (bisect! f target mid hi (- n 1))
        (bisect! f target lo mid (- n 1)))))

fn normalQuantile p: Float64 -> Float64
  (if (> p 0.5)
    (- 0.0 (bisect! normalCdf (- 1.0 p) -40.0 40.0 120))
    (bisect! normalCdf p -40.0 40.0 120))

fn stG1 x: Float64 -> Float64
  (/ (+ (* x (* x x)) x) 4.0)

fn stG2 x: Float64 -> Float64
  (let [(x2 (* x x))]
    (/ (* x (+ (* x2 (+ (* 5.0 x2) 16.0)) 3.0)) 96.0))

fn stG3 x: Float64 -> Float64
  (let [(x2 (* x x))]
    (/ (* x (+ (* x2 (+ (* x2 (+ (* 3.0 x2) 19.0)) 17.0)) -15.0)) 384.0))

fn stG4 x: Float64 -> Float64
  (let [(x2 (* x x))]
    (/ (* x (+ (* x2 (+ (* x2 (+ (* x2 (+ (* 79.0 x2) 776.0)) 1482.0)) -1920.0)) -945.0)) 92160.0))

fn stCorrection x: Float64 n: Float64 -> Float64
  (+ (/ (stG1 x) n) (+ (/ (stG2 x) (* n n)) (+ (/ (stG3 x) (* n (* n n))) (/ (stG4 x) (* (* n n) (* n n))))))

fn ! stInvert! t: Float64 n: Float64 x: Float64 k: Int64 -> Float64
  (if (<= k 0) x (stInvert! t n (- t (stCorrection x n)) (- k 1)))

fn log1pAcc u: Float64 -> Float64
  (let [(w (+ 1.0 u))]
    (if (= w 1.0) u (/ (* (log w) u) (- w 1.0))))

; (:m :ref NUM-LINALG-STATS :do "ratio Gamma(a+1/2)/Gamma(a): the asymptotic series sqrt(a)(1-1/(8a)+1/(128a^2)+5/(1024a^3)-21/(32768a^4)-399/(262144a^5)) for a >= 50 (error about 1e-15), else lgamma difference; the difference of two lgamma at a = 5e4 would lose 1e-11")
fn gammaHalfRatio a: Float64 -> Float64
  (if (>= a 50.0)
    (let [(r (/ 1.0 a))]
      (* (sqrt a) (+ 1.0 (* r (+ -0.125 (* r (+ 0.0078125 (* r (+ 0.0048828125 (* r (+ -0.000640869140625 (* r -0.0015220642089844))))))))))))
    (exp (- (lgamma (+ a 0.5)) (lgamma a))))

fn studentBt t2: Float64 df: Float64 -> Float64
  (let [(a (/ df 2.0))]
    (/ (* (* (gammaHalfRatio a) (exp (* (- 0.0 a) (log1pAcc (/ t2 df))))) (sqrt (/ t2 (+ df t2)))) (sqrt (pi))))

fn studentTail t2: Float64 df: Float64 -> Float64
  (let [(a (/ df 2.0))
        (x (/ df (+ df t2)))
        (y (/ t2 (+ df t2)))
        (bt (studentBt t2 df))]
    (if (< x (/ (+ a 1.0) (+ a 2.5)))
      (/ (* 0.5 (* bt (betaCfStart x a 0.5))) a)
      (- 0.5 (* bt (betaCfStart y 0.5 a)))))

; (:m :ref NUM-LINALG-STATS :do "Student cdf in two ranges: df >= 1e5 and |t| < 40 inverts the Abramowitz-Stegun 26.7.5 Cornish-Fisher series t = x + g1/n + g2/n^2 + g3/n^3 + g4/n^4 by fixed point and returns Phi(x); otherwise the tail 0.5*I_x(n/2,1/2), x = n/(n+t^2), by the continued fraction when x < (n/2+1)/(n/2+5/2) (t^2 above about 3, tail computed without subtraction), else 0.5 - I_y(1/2,n/2) y = t^2/(n+t^2) near the centre; the prefactor uses an asymptotic Gamma ratio and exp(-a log1p(t^2/n)), no lgamma difference; both forms equal at the switch")
fn studentCdf t: Float64 df: Float64 -> Float64
  (cond
    ((= t 0.0) 0.5)
    ((and (>= df 1.0e5) (< (abs t) 40.0)) (normalCdf (stInvert! t df t 12)))
    (else
      (let [(tail (studentTail (* t t) df))]
        (if (> t 0.0) (- 1.0 tail) tail))))

fn studentQuantile p: Float64 df: Float64 -> Float64
  (cond
    ((>= df 1.0e5)
      (let [(x (normalQuantile p))]
        (+ x (stCorrection x df))))
    ((> p 0.5)
      (- 0.0 (bisect! (fn [(t Float64)] -> Float64 (studentCdf t df)) (- 1.0 p) -1.0e7 1.0e7 200)))
    (else
      (bisect! (fn [(t Float64)] -> Float64 (studentCdf t df)) p -1.0e7 1.0e7 200)))

fn betaQuantile p: Float64 a: Float64 b: Float64 -> Float64
  (bisect! (fn [(x Float64)] -> Float64 (betaInc x a b)) p 0.0 1.0 200)

; (:m :ref NUM-LINALG-STATS :do "checked quantiles: p strictly inside (0,1) and a Student df finite and positive, else (err statsRange ...); the upper half p > 0.5 is answered by symmetry from the exact complement 1-p, so p = 1-1e-14 keeps full accuracy (accuracy is relative to the double p given, the spacing of doubles near 1 is 1.1e-16); measured against scipy 1.17: normal quantile within 1e-12 absolute for p in [1e-300, 1-1e-14]; Student df >= 1e5 by the 26.7.5 series within 1e-14 relative; df < 1e5 by bisection of the cdf, asserted within 1e-10 relative of scipy down to p = 1e-300 (the cdf is relative to 1e-12); an answer beyond 1e7 is reported as statsRange")
fn normalQuantileChecked p: Float64 -> (Result Float64 String)
  (if (and (> p 0.0) (< p 1.0))
    (ok (normalQuantile p))
    (err "statsRange: p must be in (0,1)"))

fn studentQuantileChecked p: Float64 df: Float64 -> (Result Float64 String)
  (cond
    ((not (and (> p 0.0) (< p 1.0))) (err "statsRange: p must be in (0,1)"))
    ((not (and (> df 0.0) (< df 1.0e15))) (err "statsRange: df must be positive and finite"))
    (else
      (let [(q (studentQuantile p df))]
        (if (< (abs q) 9.99e6)
          (ok q)
          (err "statsRange: Student quantile beyond 1e7, df too small for this p")))))
