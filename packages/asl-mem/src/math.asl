(module aslMem/math :x [sqrt fastInvSqrt vectorDot vectorNorm vectorCosineSim cosineSimilarity vectorAdd vectorScale vectorRelu vectorSoftmax bytesFromListF64! bytesToListF64 vectorDotBytes vectorNormBytes vectorCosineSimBytes fastLn])

"Newton-Raphson approximation for square root with fixed 10-step convergence"
fn sqrt x: F64 -> F64
  (if (<= x 0.0) 0.0 (let [(g0 (/ x 2.0)) (g1 (/ (+ g0 (/ x g0)) 2.0)) (g2 (/ (+ g1 (/ x g1)) 2.0)) (g3 (/ (+ g2 (/ x g2)) 2.0)) (g4 (/ (+ g3 (/ x g3)) 2.0)) (g5 (/ (+ g4 (/ x g4)) 2.0)) (g6 (/ (+ g5 (/ x g5)) 2.0)) (g7 (/ (+ g6 (/ x g6)) 2.0)) (g8 (/ (+ g7 (/ x g7)) 2.0)) (g9 (/ (+ g8 (/ x g8)) 2.0))] (/ (+ g9 (/ x g9)) 2.0)))

"Reciprocal square root (1 / sqrt(x))"
fn fastInvSqrt x: F64 -> F64
  (if (<= x 0.0) 0.0 (/ 1.0 (sqrt x)))

fn vectorDotHelper a: (List F64) b: (List F64) acc: F64 -> F64
  (if (or (listEmpty? a) (listEmpty? b)) acc (let [(hA (optionOr (listHead a) 0.0)) (hB (optionOr (listHead b) 0.0)) (tA (optionOr (listTail a) (list))) (tB (optionOr (listTail b) (list)))] (vectorDotHelper tA tB (+ acc (* hA hB)))))

"Dot product of two Float64 vectors"
fn vectorDot a: (List F64) b: (List F64) -> F64
  (vectorDotHelper a b 0.0)

"Euclidean L2 norm of a vector"
fn vectorNorm v: (List F64) -> F64
  (sqrt (vectorDot v v))

"Cosine similarity between two Float64 vectors in range [-1.0, 1.0]"
fn vectorCosineSim a: (List F64) b: (List F64) -> F64
  (let [(normA (vectorNorm a)) (normB (vectorNorm b))] (if (or (<= normA 0.0) (<= normB 0.0)) 0.0 (/ (vectorDot a b) (* normA normB))))

"Cosine similarity between two Float64 vectors in range [-1.0, 1.0]"
fn cosineSimilarity a: (List F64) b: (List F64) -> F64
  (vectorCosineSim a b)

fn bytesFromListLoop! b: Bytes xs: (List F64) idx: I64 -> Bytes
  (mt (listHead xs) ((none) b) ((some h) (do (bytesSetFloat64 b idx h) (mt (listTail xs) ((some rest) (bytesFromListLoop! b rest (+ idx 1))) ((none) b)))))

fn bytesFromListF64! xs: (List F64) -> Bytes
  (let [(count (listLength xs)) (b (bytesAlloc (* count 8)))] (bytesFromListLoop! b xs 0))

fn bytesToListLoop b: Bytes idx: I64 count: I64 acc: (List F64) -> (List F64)
  (if (>= idx count) acc (bytesToListLoop b (+ idx 1) count (listAppend acc (list (bytesGetFloat64 b idx)))))

fn bytesToListF64 b: Bytes -> (List F64)
  (let [(count (/ (bytesLength b) 8))] (bytesToListLoop b 0 count (list)))

fn vectorDotBytesLoop a: Bytes b: Bytes idx: I64 count: I64 acc: F64 -> F64
  (if (>= idx count) acc (vectorDotBytesLoop a b (+ idx 1) count (+ acc (* (bytesGetFloat64 a idx) (bytesGetFloat64 b idx)))))

fn vectorDotBytes a: Bytes b: Bytes -> F64
  (let [(lenA (bytesLength a)) (lenB (bytesLength b))] (if (!= lenA lenB) 0.0 (let [(count (/ lenA 8))] (if (<= count 0) 0.0 (vectorDotBytesLoop a b 0 count 0.0)))))

fn vectorNormBytes v: Bytes -> F64
  (let [(dot (vectorDotBytes v v))] (if (<= dot 0.0) 0.0 (sqrt dot)))

fn vectorCosineSimBytes a: Bytes b: Bytes -> F64
  (let [(normA (vectorNormBytes a)) (normB (vectorNormBytes b))] (if (or (<= normA 0.0) (<= normB 0.0)) 0.0 (let [(rawSim (/ (vectorDotBytes a b) (* normA normB)))] (if (> rawSim 1.0) 1.0 (if (< rawSim -1.0) -1.0 rawSim)))))

fn vectorAddHelper a: (List F64) b: (List F64) acc: (List F64) -> (List F64)
  (if (or (listEmpty? a) (listEmpty? b)) acc (let [(hA (optionOr (listHead a) 0.0)) (hB (optionOr (listHead b) 0.0)) (tA (optionOr (listTail a) (list))) (tB (optionOr (listTail b) (list)))] (vectorAddHelper tA tB (listAppend acc (list (+ hA hB))))))

"Element-wise vector addition"
fn vectorAdd a: (List F64) b: (List F64) -> (List F64)
  (vectorAddHelper a b (list))

"Scale vector by scalar factor"
fn vectorScale v: (List F64) s: F64 -> (List F64)
  (map (fn [(x F64)] (* x s)) v)

"Element-wise Rectified Linear Unit activation"
fn vectorRelu v: (List F64) -> (List F64)
  (map (fn [(x F64)] (if (> x 0.0) x 0.0)) v)

"Softmax normalization (exp(x_i) / sum(exp(x_j)))"
fn vectorSoftmax v: (List F64) -> (List F64)
  (let [(exps (map (fn [(x F64)] (let [(expApprox (if (< x 0.0) (/ 1.0 (+ 1.0 (+ (- 0.0 x) (/ (* x x) 2.0)))) (+ 1.0 (+ x (/ (* x x) 2.0)))))] (if (> expApprox 0.0) expApprox 0.0001))) v)) (total (fold (fn [(acc F64) (x F64)] (+ acc x)) 0.0 exps))] (if (<= total 0.0) v (map (fn [(x F64)] (/ x total)) exps)))

"Pure ASL natural logarithm approximation using hyperbolic series."
fn fastLn x: F64 -> F64
  (if (<= x 0.0) -10.0 (let [(z (/ (- x 1.0) (+ x 1.0))) (z2 (* z z)) (term1 z) (term2 (* term1 z2)) (term3 (* term2 z2)) (term4 (* term3 z2))] (* 2.0 (+ term1 (+ (/ term2 3.0) (+ (/ term3 5.0) (/ term4 7.0)))))))
