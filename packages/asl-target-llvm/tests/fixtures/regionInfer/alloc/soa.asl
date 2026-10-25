(module asl-target-llvm/tests/fixtures/regionInfer/alloc/soa
  :x [main]
  :i [])

; (:m :ref WAVE6 :do "bench/native/soa with the record list also read after its sum (listLength aos in the output): the read after the slice is a regionInfer guard (return), so the list stays on the per-cell RC path and the untraced soak keeps a per-element free workload")

(schema Rec
  (:f a Int64)
  (:f b Int64)
  (:f c Int64)
  (:f d Int64))

fn buildAos i: Int64 n: Int64 acc: (List Rec) -> (List Rec)
  (if (= i n) acc
    (buildAos (+ i 1) n (cons (Rec :a (mod (+ (* i 3) 1) 1000003)
                                    :b (mod (+ (* i 7) 2) 1000003)
                                    :c (mod (+ (* i 11) 3) 1000003)
                                    :d (mod (+ (* i 13) 4) 1000003))
                               acc)))

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "1000")) 1000))
        (aos (buildAos 0 n (list)))
        (sumAos (fold (fn [(a Int64) (r Rec)] -> Int64 (+ a r.b)) 0 aos))
        (colB (i64ArrayGenerate n (fn [(i Int64)] -> Int64 (mod (+ (* i 7) 2) 1000003))))
        (sumSoa (i64ArraySum colB))]
    (do (println (str (stringFromInt64 sumAos) " " (stringFromInt64 sumSoa) " " (stringFromInt64 (listLength aos))))
        (ok ())))
