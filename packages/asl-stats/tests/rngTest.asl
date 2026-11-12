(module asl-stats/tests/rngTest
  :x [runTests]
  :i [(asl-stats/rng :a rg)])

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn ! draws! n: Int64 r: rg/Rng -> (List Int64)
  (if (<= n 0) (list)
    (let [(p (rg/rngNext r))]
      (cons (pairFirst p) (draws! (- n 1) (pairSecond p)))))

fn ! floats! n: Int64 r: rg/Rng -> (List Float64)
  (if (<= n 0) (list)
    (let [(p (rg/rngFloat r))]
      (cons (pairFirst p) (floats! (- n 1) (pairSecond p)))))

fn ! normals! n: Int64 r: rg/Rng -> (List Float64)
  (if (<= n 0) (list)
    (let [(p (rg/rngNormal r))]
      (cons (pairFirst p) (normals! (- n 1) (pairSecond p)))))

fn ! gammas! a: Float64 n: Int64 r: rg/Rng -> (List Float64)
  (if (<= n 0) (list)
    (match (rg/gammaDraw a r)
      ((err e) (do (assert false e) (list)))
      ((ok p) (cons (pairFirst p) (gammas! a (- n 1) (pairSecond p))))))

fn ! betas! a: Float64 b: Float64 n: Int64 r: rg/Rng -> (List Float64)
  (if (<= n 0) (list)
    (match (rg/betaDraw a b r)
      ((err e) (do (assert false e) (list)))
      ((ok p) (cons (pairFirst p) (betas! a b (- n 1) (pairSecond p))))))

fn allNear? xs: (List Float64) ys: (List Float64) eps: Float64 -> Bool
  (and (= (listLength xs) (listLength ys))
       (listAll? (fn [(p (Pair Float64 Float64))] -> Bool (near? (pairFirst p) (pairSecond p) eps)) (zip xs ys)))

fn ! testXoshiro! -> Bool
  (do
    (assert (= (draws! 6 (rg/rngFromState 1 2 3 4)) (list 11520 0 1509978240 1215971899390074240 1216172134540287360 607988272756665600)) "xoshiro256** from state 1 2 3 4 gives the published outputs 11520 0 1509978240 ...")
    (assert (= (rg/lsr -1 1) 9223372036854775807) "lsr of -1 by 1 is Int64 max")
    (assert (= (rg/lsr -9223372036854775808 63) 1) "lsr of Int64 min by 63 is 1")
    true)

fn ! testSeed! -> Bool
  (let [(r (rg/rngSeed 42))]
    (do
      (assert (= (list r.s0 r.s1 r.s2 r.s3) (list -4767286540954276203 2949826092126892291 5139283748462763858 6349198060258255764)) "splitmix64 expansion of seed 42 (python oracle)")
      (assert (= (draws! 3 r) (list 1546998764402558742 6990951692964543102 -5902157311460992607)) "the first three draws of seed 42 (python oracle)")
      (assert (= (draws! 50 r) (draws! 50 (rg/rngSeed 42))) "a fixed seed reproduces every draw bit for bit")
      (assert (not (= (draws! 5 r) (draws! 5 (rg/rngSeed 43)))) "a different seed gives a different stream")
      (assert (allNear? (floats! 3 r) (list 0.08386297105988216 0.3789802506626686 0.6800434110281394) 1.0e-15) "floats are the top 53 bits times 2^-53")
      (assert (listAll? (fn [(x Float64)] -> Bool (and (>= x 0.0) (< x 1.0))) (floats! 500 r)) "500 floats stay in [0,1)")
      true))

fn mean xs: (List Float64) -> Float64
  (/ (fold (fn [(a Float64) (b Float64)] -> Float64 (+ a b)) 0.0 xs) (int64ToFloat64 (listLength xs)))

fn ! testDraws! -> Bool
  (let [(r (rg/rngSeed 42))]
    (do
      (assert (allNear? (normals! 3 r) (list -0.303263064678738 1.3438117634372808 0.3834617912676943) 1.0e-9) "normals of seed 42 match the python Box-Muller oracle")
      (assert (allNear? (gammas! 2.5 3 r) (list 1.750229907953055 7.524247262571115 3.8591678421538815) 1.0e-9) "gamma(2.5) draws of seed 42 match the oracle")
      (assert (allNear? (gammas! 0.5 3 r) (list 0.7428777669905297 1.1789992763525554 0.016186327781303623) 1.0e-9) "gamma(0.5) draws take the shape+1 boost and match the oracle")
      (assert (allNear? (betas! 2.0 3.0 3 r) (list 0.13501141924065524 0.6303497723364194 0.49317196011764836) 1.0e-9) "beta(2,3) draws of seed 42 match the oracle")
      (assert (near? (mean (betas! 2.0 3.0 4000 r)) 0.4 0.02) "the mean of 4000 beta(2,3) draws is near 2/5")
      (assert (near? (mean (gammas! 3.0 4000 r)) 3.0 0.15) "the mean of 4000 gamma(3) draws is near 3")
      (assert (near? (mean (normals! 4000 r)) 0.0 0.06) "the mean of 4000 normals is near 0")
      (assert (stringStartsWith? (match (rg/gammaDraw 0.0 r) ((err e) e) ((ok _) "")) "statsRange") "a non-positive gamma shape is statsRange")
      (assert (stringStartsWith? (match (rg/betaDraw 1.0 -2.0 r) ((err e) e) ((ok _) "")) "statsRange") "a negative beta parameter is statsRange")
      true))

fn ! runTests -> Bool
  (do
    (testXoshiro!)
    (testSeed!)
    (testDraws!)
    true)
