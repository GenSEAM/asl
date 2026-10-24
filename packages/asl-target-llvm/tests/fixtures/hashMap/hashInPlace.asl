(module hashInPlace
  :x [main]
  :i [])

; (:m :ref INTHASHMAP :do "a unique map grown by 50000 sets, then alias sets for String keys (general mode) and Int64 keys (raw mode, the fused set): a set, a remove and an insert on an alias must not reach the original; prints the sums and the alias reads on one line")
fn fill i: Int64 n: Int64 m: (HashMap Int64 Int64) -> (HashMap Int64 Int64)
  (if (= i n) m (fill (+ i 1) n (hashMapSet m (mod (* i 48271) 2147483647) i)))

fn sumHits i: Int64 n: Int64 m: (HashMap Int64 Int64) acc: Int64 -> Int64
  (if (= i n) acc (sumHits (+ i 1) n m (+ acc (hashMapGetOr m (mod (* i 48271) 2147483647) 0))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(big (fill 0 50000 (hashMapEmpty)))
        (a (hashMapSet (hashMapSet (hashMapEmpty) "x" 1) "y" 2))
        (b (hashMapSet a "x" 10))
        (c (hashMapRemove a "y"))
        (d (hashMapSet a "z" 3))
        (ai (hashMapSet (hashMapSet (hashMapEmpty) 7 1) 9 2))
        (bi (hashMapSet ai 7 10))
        (ci (hashMapRemove ai 9))
        (di (hashMapSet ai 11 3))]
    (do (println (str (hashMapLength big) " " (sumHits 0 50000 big 0) " "
                      (hashMapGetOr a "x" 0) " " (hashMapGetOr b "x" 0) " "
                      (hashMapGetOr a "y" 0) " " (hashMapGetOr c "y" 0) " "
                      (hashMapGetOr a "z" 0) " " (hashMapGetOr d "z" 0) " " (hashMapLength a) " "
                      (hashMapGetOr ai 7 0) " " (hashMapGetOr bi 7 0) " " (hashMapGetOr ai 9 0) " " (hashMapGetOr ci 9 0) " "
                      (hashMapGetOr ai 11 0) " " (hashMapGetOr di 11 0) " " (hashMapLength ai)))
        (ok 0)))
