(module hashPresized
  :x [main]
  :i [])

; (:m :ref INTHASHMAP :do "50000 sets into a map pre-sized for 50000: the table is allocated once and never grows")
fn fill i: Int64 n: Int64 m: (HashMap Int64 Int64) -> (HashMap Int64 Int64)
  (if (= i n) m (fill (+ i 1) n (hashMapSet m (mod (* i 48271) 2147483647) i)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(m (fill 0 50000 (hashMapWithCapacity 50000)))]
    (do (println (str (hashMapLength m) " " (hashMapGetOr m 48271 -1)))
        (ok 0)))
