(module asl-target-llvm/tests/fixtures/sliceView/alloc/slice
  :x [main]
  :i [])

fn len -> Int64 2000003
fn sliceLen -> Int64 128

fn sumOf v: I64Array -> Int64
  (i64ArraySum v)

fn runSlices s: Int64 n: Int64 base: I64Array total: Int64 -> Int64
  (if (= s n) total
    (let [(start (mod (* s 997) (- (len) (sliceLen))))
          (view (i64ArraySlice base start (+ start (sliceLen))))
          (sum (sumOf view))]
      (runSlices (+ s 1) n base (mod (+ total sum) 1000000007))))

fn ! main args: (List String) -> (Result Unit String)
  (let [(numSlices (optionOr (stringToInt64 (optionOr (listHead args) "1000")) 1000))
        (base (i64ArrayGenerate (len) (fn [(i Int64)] -> Int64 (mod (* i 31) 1000003))))
        (total (runSlices 0 numSlices base 0))]
    (do (println (stringFromInt64 total))
        (ok ())))
