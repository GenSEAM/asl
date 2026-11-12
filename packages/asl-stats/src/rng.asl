(module asl-stats/rng
  :x [Rng rngFromState rngSeed rngNext rngFloat rngNormal gammaDraw betaDraw lsr]
  :i [])

; (:m :ref workspace-20261031-experimentStats :do "xoshiro256** over four Int64 words; mulWrap, addWrap and rotateLeft have no native lowering yet so the wrapping adds, the times 5 and 9 and the 64-bit multiply in seeding are built from 32-bit halves, shifts and masks; the generator is a value, every draw returns the new state, so a fixed seed reproduces every draw bit for bit; rngSeed expands one Int64 with splitmix64; a float is the top 53 bits times 2^-53; normals by Box-Muller, gamma by Marsaglia-Tsang, beta as two gammas")
schema Rng
  (:f s0 Int64)
  (:f s1 Int64)
  (:f s2 Int64)
  (:f s3 Int64)

fn lsr x: Int64 n: Int64 -> Int64
  (& (>> x n) (+ (* (- (<< 1 (- 63 n)) 1) 2) 1))

fn addW a: Int64 b: Int64 -> Int64
  (let [(lo (+ (& a 4294967295) (& b 4294967295)))
        (hi (+ (+ (lsr a 32) (lsr b 32)) (>> lo 32)))]
    (| (<< (& hi 4294967295) 32) (& lo 4294967295)))

fn rotl x: Int64 k: Int64 -> Int64
  (| (<< x k) (lsr x (- 64 k)))

fn mulSoft! a: Int64 b: Int64 acc: Int64 i: Int64 -> Int64
  (if (>= i 64) acc
    (mulSoft! (<< a 1) b (if (= (& (>> b i) 1) 1) (addW acc a) acc) (+ i 1)))

fn rngFromState a: Int64 b: Int64 c: Int64 d: Int64 -> Rng
  (Rng :s0 a :s1 b :s2 c :s3 d)

fn splitmix z0: Int64 -> (Pair Int64 Int64)
  (let [(z (addW z0 -7046029254386353131))
        (a (mulSoft! (^ z (lsr z 30)) -4658895280553007687 0 0))
        (b (mulSoft! (^ a (lsr a 27)) -7723592293110705685 0 0))]
    (pair z (^ b (lsr b 31))))

fn rngSeed seed: Int64 -> Rng
  (let [(p1 (splitmix seed))
        (p2 (splitmix (pairFirst p1)))
        (p3 (splitmix (pairFirst p2)))
        (p4 (splitmix (pairFirst p3)))]
    (Rng :s0 (pairSecond p1) :s1 (pairSecond p2) :s2 (pairSecond p3) :s3 (pairSecond p4)))

fn rngNext r: Rng -> (Pair Int64 Rng)
  (let [(result (let [(m5 (addW (<< r.s1 2) r.s1)) (x (rotl m5 7))] (addW (<< x 3) x)))
        (t (<< r.s1 17))
        (s2 (^ r.s2 r.s0))
        (s3 (^ r.s3 r.s1))
        (s1 (^ r.s1 s2))
        (s0 (^ r.s0 s3))]
    (pair result (Rng :s0 s0 :s1 s1 :s2 (^ s2 t) :s3 (rotl s3 45))))

fn rngFloat r: Rng -> (Pair Float64 Rng)
  (let [(p (rngNext r))]
    (pair (* (int64ToFloat64 (lsr (pairFirst p) 11)) 1.1102230246251565e-16) (pairSecond p)))

fn rngNormal r: Rng -> (Pair Float64 Rng)
  (let [(a (rngFloat r))
        (b (rngFloat (pairSecond a)))
        (u1 (- 1.0 (pairFirst a)))
        (u2 (pairFirst b))]
    (pair (* (sqrt (* -2.0 (log u1))) (cos (* (* 2.0 3.141592653589793) u2))) (pairSecond b)))

fn ! gammaLoop! d: Float64 c: Float64 r: Rng -> (Pair Float64 Rng)
  (let [(n (rngNormal r))
        (x (pairFirst n))
        (t (+ 1.0 (* c x)))
        (v (* (* t t) t))
        (u (rngFloat (pairSecond n)))]
    (if (<= v 0.0)
      (gammaLoop! d c (pairSecond u))
      (if (< (log (pairFirst u)) (+ (* (* 0.5 x) x) (+ (- d (* d v)) (* d (log v)))))
        (pair (* d v) (pairSecond u))
        (gammaLoop! d c (pairSecond u)))))

fn ! gammaDraw alpha: Float64 r: Rng -> (Result (Pair Float64 Rng) String)
  (cond
    ((not (> alpha 0.0)) (err "statsRange: gamma shape must be positive"))
    ((< alpha 1.0)
      (match (gammaDraw (+ alpha 1.0) r)
        ((err e) (err e))
        ((ok g)
          (let [(u (rngFloat (pairSecond g)))
                (uu (max (pairFirst u) 1.0e-300))]
            (ok (pair (* (pairFirst g) (pow uu (/ 1.0 alpha))) (pairSecond u)))))))
    (else
      (let [(d (- alpha (/ 1.0 3.0)))]
        (ok (gammaLoop! d (/ 1.0 (sqrt (* 9.0 d))) r)))))

; (:m :ref DSSTATS-LOWS :do "the log of a gamma draw: for a shape below 1 the boost g*u^(1/a) is taken as log g + log(u)/a, which stays finite where u^(1/a) underflows to 0 (a = 0.001)")
fn ! logGammaDraw alpha: Float64 r: Rng -> (Result (Pair Float64 Rng) String)
  (cond
    ((not (> alpha 0.0)) (err "statsRange: gamma shape must be positive"))
    ((< alpha 1.0)
      (match (gammaDraw (+ alpha 1.0) r)
        ((err e) (err e))
        ((ok g)
          (let [(u (rngFloat (pairSecond g)))
                (uu (max (pairFirst u) 1.0e-300))]
            (ok (pair (+ (log (pairFirst g)) (/ (log uu) alpha)) (pairSecond u)))))))
    (else (match (gammaDraw alpha r) ((err e) (err e)) ((ok g) (ok (pair (log (pairFirst g)) (pairSecond g)))))))

; (:m :ref DSSTATS-LOWS :do "beta = X/(X+Y) computed as 1/(1+exp(log Y - log X)) from log gamma draws, so tiny shapes give 0 or 1 at the extremes instead of 0/0 = NaN")
fn ! betaDraw a: Float64 b: Float64 r: Rng -> (Result (Pair Float64 Rng) String)
  (match (logGammaDraw a r)
    ((err e) (err e))
    ((ok x)
      (match (logGammaDraw b (pairSecond x))
        ((err e) (err e))
        ((ok y) (ok (pair (/ 1.0 (+ 1.0 (exp (- (pairFirst y) (pairFirst x))))) (pairSecond y)))))))
