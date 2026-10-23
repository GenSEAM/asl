(module asl-target-llvm/tests/musttailRoutedCalleeTest
  :x [runTests]
  :i [])

; (:m :ref LLVM-TAILCALL-UNSUPPORTED-20261022 :do "the lambda's odd branch is a musttail call into the routed f64ArrayGet while the even branch only reads its payload; with that callee internal, Apple clang 17 DeadArgumentElimination rewrote its return type and the backend aborted on the musttail site")
fn interleave lo: F64Array hi: F64Array -> F64Array
  (f64ArrayGenerate (* 2 (f64ArrayLen hi))
                    (fn [(s Int64)] -> Float64 (if (= (mod s 2) 0) (+ 0.5 (f64ArrayGet lo (/ s 2))) (f64ArrayGet hi (/ s 2)))))

fn ! runTests -> Bool
  (let [(lo (f64ArrayGenerate 3 (fn [(i Int64)] -> Float64 (* 2.0 (int64ToFloat64 i)))))
        (hi (f64ArrayGenerate 3 (fn [(i Int64)] -> Float64 (+ 10.0 (int64ToFloat64 i)))))
        (mixed (interleave lo hi))]
    (do
      (assert (= (f64ArrayLen mixed) 6) "interleave yields two slots per input index")
      (assert (= (f64ArrayGet mixed 0) 0.5) "even slot 0 is lo[0] + 0.5")
      (assert (= (f64ArrayGet mixed 1) 10.0) "odd slot 1 is the tail-called hi[0]")
      (assert (= (f64ArrayGet mixed 4) 4.5) "even slot 4 is lo[2] + 0.5")
      (assert (= (f64ArrayGet mixed 5) 12.0) "odd slot 5 is the tail-called hi[2]")
      (assert (= (f64ArraySum mixed) 40.5) "slots sum to 0.5 + 2.5 + 4.5 + 10 + 11 + 12")
      true))
