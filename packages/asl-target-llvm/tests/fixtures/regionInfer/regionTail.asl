(module regionTail
  :x [main]
  :i [])

; (:m :ref SOAREGION :do "drive builds a list and hands it to step, which tail-calls drive again: a region around the step call would reach its own owner and nest one arena per round, so the call stays a tail call")
schema Rec
  a: Int64
  b: Int64

fn build i: Int64 n: Int64 acc: (List Rec) -> (List Rec)
  (if (= i n) acc (build (+ i 1) n (cons (Rec :a i :b (* i 3)) acc)))

fn sumB xs: (List Rec) acc: Int64 -> Int64
  (if (listEmpty? xs)
    acc
    (sumB (optionOr (listTail xs) (list)) (+ acc (match (listHead xs) ((some r) r.b) ((none) 0)))))

fn step xs: (List Rec) k: Int64 acc: Int64 -> Int64
  (if (= k 0) (+ acc (sumB xs 0)) (drive (- k 1) (+ acc (sumB xs 0))))

fn drive k: Int64 acc: Int64 -> Int64
  (step (build 0 10 (list)) k acc)

; (:m :ref SOAREGION :do "nested is not a tail call but its slice still reaches nested through stepN: kept by the owner check alone")
fn stepN xs: (List Rec) k: Int64 acc: Int64 -> Int64
  (if (= k 0) (+ acc (sumB xs 0)) (+ 1 (nested (- k 1) (+ acc (sumB xs 0)))))

fn nested k: Int64 acc: Int64 -> Int64
  (+ 0 (stepN (build 0 10 (list)) k acc))

; (:m :ref SOAREGION :do "the consumer is the tail call of a recursive function and its slice does not reach the owner: kept by the tail check alone")
fn tailRec k: Int64 acc: Int64 -> Int64
  (if (= k 0) (sumB (build 0 10 (list)) acc) (tailRec (- k 1) (+ acc 1)))

fn ! main args: (List String) -> (Result Unit String)
  (do (println (str (drive 1000000 0)))
      (println (str (nested 10 0)))
      (println (str (tailRec 10 0)))
      (ok ()))
