(module aslMem/testMath :x [runTests RunTests! testFastMathPrimitives testVectorListOperations testBytesVectorOperations!] :i [(aslMem/math :a m)])

fn testFastMathPrimitives -> Bool
  (let [(s4 (m/sqrt 4.0)) (s9 (m/sqrt 9.0)) (s16 (m/sqrt 16.0)) (s0 (m/sqrt 0.0)) (sNeg (m/sqrt -5.0)) (inv4 (m/fastInvSqrt 4.0))] (assert (< (abs (- s4 2.0)) 0.0001) "sqrt 4.0 is approx 2.0") (assert (< (abs (- s9 3.0)) 0.0001) "sqrt 9.0 is approx 3.0") (assert (< (abs (- s16 4.0)) 0.0001) "sqrt 16.0 is approx 4.0") (assert (= s0 0.0) "sqrt 0.0 is 0.0") (assert (= sNeg 0.0) "sqrt negative is 0.0") (assert (< (abs (- inv4 0.5)) 0.0001) "fastInvSqrt 4.0 is approx 0.5") true)

fn testVectorListOperations -> Bool
  (let [(v1 (list 1.0 2.0 3.0)) (v2 (list 4.0 5.0 6.0)) (dot (m/vectorDot v1 v2)) (add (m/vectorAdd v1 v2)) (norm (m/vectorNorm v1))] (assert (= dot 32.0) "vectorDot list 1*4 + 2*5 + 3*6 = 32.0") (assert (= (listLength add) 3) "vectorAdd length is 3") (assert (= (optionOr (listGet add 0) 0.0) 5.0) "add slot 0 is 5.0") (assert (= (optionOr (listGet add 1) 0.0) 7.0) "add slot 1 is 7.0") (assert (= (optionOr (listGet add 2) 0.0) 9.0) "add slot 2 is 9.0") (assert (> norm 3.74) "norm v1 > 3.74") (assert (< norm 3.75) "norm v1 < 3.75") true)

fn testBytesVectorOperations! -> Bool
  (let [(l (list 1.0 2.0 3.0 4.0)) (b (m/bytesFromListF64! l)) (lRestored (m/bytesToListF64 b))] (assert (= (bytesLength b) 32) "4 floats * 8 = 32 bytes") (assert (= (listLength lRestored) 4) "restored list has 4 elements") (assert (= (optionOr (listGet lRestored 0) 0.0) 1.0) "restored 0 is 1.0") (assert (= (optionOr (listGet lRestored 1) 0.0) 2.0) "restored 1 is 2.0") (assert (= (optionOr (listGet lRestored 2) 0.0) 3.0) "restored 2 is 3.0") (assert (= (optionOr (listGet lRestored 3) 0.0) 4.0) "restored 3 is 4.0") (let [(b2 (m/bytesFromListF64! (list 2.0 3.0 4.0 5.0))) (dot (m/vectorDotBytes b b2)) (normB (m/vectorNormBytes b)) (sim (m/vectorCosineSimBytes b b2))] (assert (= dot 40.0) "dot 1*2 + 2*3 + 3*4 + 4*5 = 40.0") (assert (> normB 5.47) "normB > 5.47") (assert (< normB 5.48) "normB < 5.48") (assert (> sim 0.99) "sim > 0.99") (assert (<= sim 1.0) "sim <= 1.0") true))

fn ! runTests -> Bool
  (do (assert (testFastMathPrimitives) "testFastMathPrimitives must pass") (assert (testVectorListOperations) "testVectorListOperations must pass") (assert (testBytesVectorOperations!) "testBytesVectorOperations must pass") true)

fn RunTests! -> Bool
  (runTests)
