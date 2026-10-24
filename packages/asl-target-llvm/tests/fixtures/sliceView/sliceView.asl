(module sliceView
  :x [main]
  :i [])

fn fused s: Int64 n: Int64 base: I64Array total: Int64 -> Int64
  (if (= s n) total
    (let [(start (mod (* s 7) 900))
          (view (i64ArraySlice base start (+ start 64)))
          (sum (i64ArraySum view))
          (k (i64ArrayLen view))
          (g (i64ArrayGet view 3))
          (c (i64ArrayCountEq view (* 3 (+ start 5))))]
      (fused (+ s 1) n base (+ total (+ sum (+ k (+ g c)))))))

fn copied s: Int64 n: Int64 base: I64Array total: Int64 -> Int64
  (if (= s n) total
    (let [(start (mod (* s 7) 900))
          (views (list (i64ArraySlice base start (+ start 64))))
          (view (optionOr (listHead views) base))
          (sum (i64ArraySum view))
          (k (i64ArrayLen view))
          (g (i64ArrayGet view 3))
          (c (i64ArrayCountEq view (* 3 (+ start 5))))]
      (copied (+ s 1) n base (+ total (+ sum (+ k (+ g c)))))))

fn kinds -> String
  (let [(f (f64ArrayGenerate 10 (fn [(i Int64)] -> Float64 (* 0.5 (int64ToFloat64 i)))))
        (fv (f64ArraySlice f 2 6))
        (fs (f64ArraySum fv))
        (fg (f64ArrayGet fv 1))
        (b (i8ArrayGenerate 10 (fn [(i Int64)] -> Int64 (- (mod i 3) 1))))
        (bv (i8ArraySlice b 1 8))
        (bc (i8ArrayCountEq bv 0))
        (bs (i8ArraySum bv))
        (bl (i8ArrayLen bv))]
    (str (stringFromFloat64 fs) " " (stringFromFloat64 fg) " " bc " " bs " " bl))

fn edge x: Int64 -> Int64
  (cond ((= x 0) 9223372036854775807) ((= x 1) -1) (else (- x 2)))

fn bigSum a: I64Array -> Int64
  (i64ArraySum (i64ArraySlice a 0 3))

fn badRange a: I64Array -> Int64
  (i64ArraySum (i64ArraySlice a 5 2))

fn badGet a: I64Array -> Int64
  (i64ArrayGet (i64ArraySlice a 3 5) 4)

fn badSum a: I64Array -> Int64
  (i64ArraySum (i64ArraySlice a 0 4))

fn ! ordered a: I64Array -> Int64
  (let [(v (i64ArraySlice a 5 2))
        (said (println "between"))
        (s (i64ArraySum v))]
    s)

fn ! main args: (List String) -> (Result Unit String)
  (let [(mode (optionOr (listHead args) "ok"))
        (base (i64ArrayGenerate 1000 (fn [(i Int64)] -> Int64 (* i 3))))
        (wide (i64ArrayGenerate 4 (fn [(i Int64)] -> Int64 (if (= i 1) 1 (edge i)))))
        (near (i64ArrayGenerate 3 edge))]
    (cond
      ((= mode "range") (do (println (stringFromInt64 (badRange base))) (ok ())))
      ((= mode "get") (do (println (stringFromInt64 (badGet base))) (ok ())))
      ((= mode "ovf") (do (println (stringFromInt64 (badSum wide))) (ok ())))
      ((= mode "order") (do (println (stringFromInt64 (ordered base))) (ok ())))
      (else (do (println (str (fused 0 1000 base 0) " " (copied 0 1000 base 0)))
                (println (kinds))
                (println (stringFromInt64 (bigSum near)))
                (ok ())))))
