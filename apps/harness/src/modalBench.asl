(module aslHarness/modalBench :x [TaskResult computeBenchMetrics] :i [])

(schema TaskResult (:f taskId Str) (:f passed Bool) (:f exitCode I64) (:f durationMs I64))

fn computeBenchMetrics results: (List TaskResult) -> Str
  (let [(total (listLength results)) (passed (listLength (filter (fn [(r TaskResult)] -> Bool r.passed) results))) (failed (- total passed)) (rate (if (= total 0) 0.0 (* (/ (int64ToFloat64 passed) (int64ToFloat64 total)) 100.0)))] (str "(:bench-metrics" " :total " (stringFromInt64 total) " :passed " (stringFromInt64 passed) " :failed " (stringFromInt64 failed) " :pass-rate-pct " (if (= rate 0.0) "0.0" (if (= rate 100.0) "100.0" (stringFromFloat64 rate))) ")"))
