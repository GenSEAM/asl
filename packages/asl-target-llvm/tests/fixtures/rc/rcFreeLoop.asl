(module rcFreeLoop
  :x [main]
  :i [])

(schema Flat (:f a Int64) (:f b Int64) (:f c Int64) (:f d Int64))

(schema Named (:f n Int64) (:f label String))

(schema Outer (:f k Int64) (:f inner Named))

fn flats i: Int64 n: Int64 acc: (List Flat) -> (List Flat)
  (if (>= i n) acc (flats (+ i 1) n (cons (Flat :a i :b (* i 2) :c (* i 3) :d (* i 4)) acc)))

fn nameds i: Int64 n: Int64 acc: (List Named) -> (List Named)
  (if (>= i n) acc (nameds (+ i 1) n (cons (Named :n i :label (stringFromInt64 i)) acc)))

fn outers i: Int64 n: Int64 acc: (List Outer) -> (List Outer)
  (if (>= i n) acc (outers (+ i 1) n (cons (Outer :k i :inner (Named :n (* i 5) :label (stringFromInt64 (* i 7)))) acc)))

fn sumFlat xs: (List Flat) -> Int64
  (fold (fn [(s Int64) (r Flat)] -> Int64 (+ s r.b)) 0 xs)

fn sumNamed xs: (List Named) -> Int64
  (fold (fn [(s Int64) (r Named)] -> Int64 (+ s (+ r.n (stringLength r.label)))) 0 xs)

fn sumOuter xs: (List Outer) -> Int64
  (fold (fn [(s Int64) (r Outer)] -> Int64 (+ s (+ r.k (+ r.inner.n (stringLength r.inner.label))))) 0 xs)

fn round k: Int64 acc: Int64 -> Int64
  (if (>= k 10) acc
    (round (+ k 1) (+ acc (+ (sumFlat (flats 0 1000 (list))) (+ (sumNamed (nameds 0 1000 (list))) (sumOuter (outers 0 1000 (list))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (round 0 0)))
      (ok 0))
