(module asl-target-llvm/tests/fixtures/recordUnbox/soa
  :x [main]
  :i [])

(schema Rec
  (:f a Int64)
  (:f b Int64)
  (:f c Int64)
  (:f d Int64))

fn build i: Int64 n: Int64 acc: (List Rec) -> (List Rec)
  (if (= i n) acc
    (build (+ i 1) n (cons (Rec :a (mod (+ (* i 3) 1) 1000003)
                                :b (mod (+ (* i 7) 2) 1000003)
                                :c (mod (+ (* i 11) 3) 1000003)
                                :d (mod (+ (* i 13) 4) 1000003))
                           acc)))

fn ! main args: (List String) -> (Result Unit String)
  (let [(rs (build 0 3000 (list)))
        (sumB (fold (fn [(acc Int64) (r Rec)] -> Int64 (+ acc r.b)) 0 rs))
        (sumAll (fold (fn [(acc Int64) (r Rec)] -> Int64 (+ acc (+ r.a (+ r.c r.d)))) 0 rs))]
    (do (println (str "sums " sumB " " sumAll))
        (println (str "first " (optionOr (listHead rs) (Rec :a 0 :b 0 :c 0 :d 0))))
        (println (str "eq " (= (listHead rs) (listHead rs)) " " (= (Rec :a 1 :b 2 :c 3 :d 4) (Rec :d 4 :c 3 :b 2 :a 1))))
        (ok ())))
