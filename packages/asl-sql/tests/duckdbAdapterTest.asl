(module asl-sql/tests/duckdbAdapterTest
  :d "Unit tests and D77 dual-polarity refutations for DuckDB analytical telemetry query engine adapter (ADR D87, D81)."
  :x [runTests
      RunTests
      testDuckdbEngineInitialization
      testTelemetryRowCreation
      testBatchIngestionAndAccumulation
      testVectorizedQueryAggregation
      testPercentileLatencyCalculation
      testStructuredReceiptRendering
      testDualPolarityRefutations]
  :i [(../src/duckdbAdapter :a da)])

(df testDuckdbEngineInitialization [] -> Bool
  :d "Verifies clean initialization of DuckDB query engine state with zero counters."
  (let [(st (da/initDuckdbQueryEngine))]
    (assert (= (list-length (.-columns st)) 0) "Initial columns list is empty")
    (assert (= (.-rowCount st) 0) "Initial row count is zero")
    (assert (= (list-length (.-rows st)) 0) "Initial rows list is empty")
    (refute (!= (.-rowCount st) 0) "Initial row count must refute non-zero")
    (refute (!= (list-length (.-rows st)) 0) "Initial rows list must refute non-empty")
    true))

(df testTelemetryRowCreation [] -> Bool
  :d "Verifies creation and field access of TelemetryRow records."
  (let [(row (da/makeTelemetryRow "Phase101" "Task10101" 150 12 4))]
    (assert (= (.-phase row) "Phase101") "Phase matches Phase101")
    (assert (= (.-task row) "Task10101") "Task matches Task10101")
    (assert (= (.-durationMs row) 150) "Duration matches 150ms")
    (assert (= (.-asserts row) 12) "Asserts match 12")
    (assert (= (.-refutes row) 4) "Refutes match 4")
    (refute (!= (.-phase row) "Phase101") "Phase must refute divergence")
    (refute (!= (.-durationMs row) 150) "Duration must refute divergence")
    true))

(df testBatchIngestionAndAccumulation [] -> Bool
  :d "Verifies batch ingestion, state immutability, and multi-batch accumulation."
  (let [(st0 (da/initDuckdbQueryEngine))
        (b1 (list (da/makeTelemetryRow "PhaseA" "T1" 100 10 5)
                  (da/makeTelemetryRow "PhaseA" "T2" 200 20 10)
                  (da/makeTelemetryRow "PhaseB" "T3" 300 30 15)))
        (res1 (da/ingestTelemetryBatch st0 b1))]
    (assert (is-ok? res1) "First batch ingestion returns ok")
    (refute (is-err? res1) "First batch ingestion must not error")
    (let [(st1 (option-or (mt res1 ((ok s) (some s)) ((err _) (none))) st0))]
      (assert (= (.-rowCount st1) 3) "State 1 has 3 rows")
      (assert (= (list-length (.-rows st1)) 3) "State 1 row list has 3 items")
      (assert (= (.-rowCount st0) 0) "Original state st0 remains unchanged (immutable)")
      (refute (!= (.-rowCount st0) 0) "st0 row count must refute mutation")
      (let [(b2 (list (da/makeTelemetryRow "PhaseB" "T4" 150 15 5)
                      (da/makeTelemetryRow "PhaseC" "T5" 250 25 10)))
            (res2 (da/ingestTelemetryBatch st1 b2))]
        (assert (is-ok? res2) "Second batch ingestion returns ok")
        (let [(st2 (option-or (mt res2 ((ok s) (some s)) ((err _) (none))) st1))]
          (assert (= (.-rowCount st2) 5) "State 2 has 5 total rows")
          (assert (= (list-length (.-rows st2)) 5) "State 2 row list has 5 items")
          (refute (!= (.-rowCount st2) 5) "st2 row count must refute non-5")
          true)))))

(df testVectorizedQueryAggregation [] -> Bool
  :d "Verifies vectorized phase filtering and sum aggregation across tasks."
  (let [(st0 (da/initDuckdbQueryEngine))
        (rows (list (da/makeTelemetryRow "PhaseA" "T1" 100 10 2)
                    (da/makeTelemetryRow "PhaseA" "T2" 200 20 4)
                    (da/makeTelemetryRow "PhaseA" "T3" 300 30 6)
                    (da/makeTelemetryRow "PhaseB" "T4" 400 40 8)
                    (da/makeTelemetryRow "PhaseB" "T5" 500 50 10)))
        (ingestRes (da/ingestTelemetryBatch st0 rows))]
    (let [(st1 (option-or (mt ingestRes ((ok s) (some s)) ((err _) (none))) st0))
          (qResA (da/queryTelemetryVectorized st1 "PhaseA"))
          (qResB (da/queryTelemetryVectorized st1 "PhaseB"))
          (qResNone (da/queryTelemetryVectorized st1 "UnknownPhase"))]
      (assert (is-ok? qResA) "Query PhaseA returns ok")
      (assert (is-ok? qResB) "Query PhaseB returns ok")
      (assert (is-ok? qResNone) "Query UnknownPhase returns ok")
      (let [(aggA (option-or (mt qResA ((ok a) (some a)) ((err _) (none))) (da/makeEmptyAgg)))
            (aggB (option-or (mt qResB ((ok b) (some b)) ((err _) (none))) (da/makeEmptyAgg)))
            (aggNone (option-or (mt qResNone ((ok n) (some n)) ((err _) (none))) (da/makeEmptyAgg)))]
        (assert (= (.-taskCount aggA) 3) "PhaseA task count is 3")
        (assert (= (.-totalDurationMs aggA) 600) "PhaseA total duration is 100+200+300=600ms")
        (assert (= (.-totalAsserts aggA) 60) "PhaseA total asserts is 10+20+30=60")
        (assert (= (.-totalRefutes aggA) 12) "PhaseA total refutes is 2+4+6=12")
        (refute (!= (.-taskCount aggA) 3) "PhaseA task count refutes non-3")
        (refute (!= (.-totalDurationMs aggA) 600) "PhaseA duration refutes non-600")
        (assert (= (.-taskCount aggB) 2) "PhaseB task count is 2")
        (assert (= (.-totalDurationMs aggB) 900) "PhaseB total duration is 400+500=900ms")
        (assert (= (.-totalAsserts aggB) 90) "PhaseB total asserts is 40+50=90")
        (assert (= (.-totalRefutes aggB) 18) "PhaseB total refutes is 8+10=18")
        (refute (!= (.-taskCount aggB) 2) "PhaseB task count refutes non-2")
        (assert (= (.-taskCount aggNone) 0) "UnknownPhase task count is 0")
        (assert (= (.-totalDurationMs aggNone) 0) "UnknownPhase duration is 0")
        (refute (!= (.-taskCount aggNone) 0) "UnknownPhase task count refutes non-0")
        true))))

(df testPercentileLatencyCalculation [] -> Bool
  :d "Verifies nearest-rank percentile latency calculations over sorted and unsorted sets."
  (let [(lat10 (list 10 20 30 40 50 60 70 80 90 100))
        (p0 (da/computePercentile lat10 0))
        (p25 (da/computePercentile lat10 25))
        (p50 (da/computePercentile lat10 50))
        (p75 (da/computePercentile lat10 75))
        (p90 (da/computePercentile lat10 90))
        (p99 (da/computePercentile lat10 99))
        (p100 (da/computePercentile lat10 100))]
    (assert (= p0 10) "P0 of lat10 is 10")
    (assert (= p25 30) "P25 of lat10 is 30")
    (assert (= p50 50) "P50 of lat10 is 50")
    (assert (= p75 80) "P75 of lat10 is 80")
    (assert (= p90 90) "P90 of lat10 is 90")
    (assert (= p99 100) "P99 of lat10 is 100")
    (assert (= p100 100) "P100 of lat10 is 100")
    (assert (<= p0 p25) "P0 <= P25")
    (assert (<= p25 p50) "P25 <= P50")
    (assert (<= p50 p75) "P50 <= P75")
    (assert (<= p75 p90) "P75 <= P90")
    (assert (<= p90 p99) "P90 <= P99")
    (assert (<= p99 p100) "P99 <= P100")
    (refute (> p50 p90) "P50 must not exceed P90")
    (refute (> p90 p99) "P90 must not exceed P99")
    (let [(latUnsorted (list 300 100 200))
          (uP0 (da/computePercentile latUnsorted 0))
          (uP50 (da/computePercentile latUnsorted 50))
          (uP100 (da/computePercentile latUnsorted 100))]
      (assert (= uP0 100) "P0 of unsorted is minimum 100")
      (assert (= uP50 200) "P50 of unsorted is median 200")
      (assert (= uP100 300) "P100 of unsorted is maximum 300")
      (refute (!= uP50 200) "P50 must refute non-200")
      (let [(latSingle (list 42))
            (sP50 (da/computePercentile latSingle 50))]
        (assert (= sP50 42) "P50 of single item is 42")
        (refute (!= sP50 42) "P50 of single item refutes non-42")
        true))))

(df testStructuredReceiptRendering [] -> Bool
  :d "Verifies creation of summary records and rendering formatted ASN receipts."
  (let [(summary (da/makeTelemetrySummary "Phase532" 4 550 100 75 85 180 200))
        (receipt (da/renderTelemetryReceipt summary))]
    (assert (= (.-phase summary) "Phase532") "Summary phase matches")
    (assert (= (.-taskCount summary) 4) "Summary taskCount matches")
    (assert (= (.-totalDurationMs summary) 550) "Summary totalDurationMs matches")
    (assert (= (.-totalAsserts summary) 100) "Summary totalAsserts matches")
    (assert (= (.-totalRefutes summary) 75) "Summary totalRefutes matches")
    (assert (= (.-p50 summary) 85) "Summary p50 matches")
    (assert (= (.-p90 summary) 180) "Summary p90 matches")
    (assert (= (.-p99 summary) 200) "Summary p99 matches")
    (assert (> (string-length receipt) 0) "Receipt text is non-empty")
    (assert (string-contains? receipt ":telemetryReceipt") "Receipt contains :telemetryReceipt")
    (assert (string-contains? receipt ":phase \"Phase532\"") "Receipt contains phase key")
    (assert (string-contains? receipt ":taskCount 4") "Receipt contains taskCount key")
    (assert (string-contains? receipt ":totalDurationMs 550") "Receipt contains totalDurationMs key")
    (assert (string-contains? receipt ":totalAsserts 100") "Receipt contains totalAsserts key")
    (assert (string-contains? receipt ":totalRefutes 75") "Receipt contains totalRefutes key")
    (assert (string-contains? receipt ":p50 85") "Receipt contains p50 key")
    (assert (string-contains? receipt ":p90 180") "Receipt contains p90 key")
    (assert (string-contains? receipt ":p99 200") "Receipt contains p99 key")
    (refute (string-contains? receipt "invalid_receipt") "Receipt refutes invalid_receipt")
    (refute (string-contains? receipt "nil") "Receipt refutes nil")
    true))

(df testDualPolarityRefutations [] -> Bool
  :d "Executes comprehensive D77 dual-polarity refutations against invalid inputs and empty states."
  (let [(emptyList (list))
        (badNeg (da/computePercentile (list 10 20) -5))
        (badOver (da/computePercentile (list 10 20) 105))
        (badEmpty (da/computePercentile emptyList 50))]
    (assert (= badNeg 0) "Negative percentile yields 0")
    (assert (= badOver 0) "Percentile above 100 yields 0")
    (assert (= badEmpty 0) "Percentile of empty list yields 0")
    (refute (!= badNeg 0) "Negative percentile refutes non-zero")
    (refute (!= badOver 0) "Percentile above 100 refutes non-zero")
    (refute (!= badEmpty 0) "Percentile of empty list refutes non-zero")
    (let [(emptyAgg (da/makeEmptyAgg))]
      (assert (= (.-taskCount emptyAgg) 0) "Empty agg taskCount is 0")
      (assert (= (.-totalDurationMs emptyAgg) 0) "Empty agg totalDurationMs is 0")
      (assert (= (.-totalAsserts emptyAgg) 0) "Empty agg totalAsserts is 0")
      (assert (= (.-totalRefutes emptyAgg) 0) "Empty agg totalRefutes is 0")
      (refute (!= (.-taskCount emptyAgg) 0) "Empty agg taskCount refutes non-zero")
      (refute (!= (.-totalDurationMs emptyAgg) 0) "Empty agg duration refutes non-zero"))
    (let [(st (da/initDuckdbQueryEngine))
          (eIngest (da/ingestTelemetryBatch st (list)))]
      (assert (is-ok? eIngest) "Empty batch ingest returns ok")
      (refute (is-err? eIngest) "Empty batch ingest refutes error")
      (let [(qEmpty (da/queryTelemetryVectorized st "PhaseX"))]
        (assert (is-ok? qEmpty) "Querying empty engine returns ok")
        (refute (is-err? qEmpty) "Querying empty engine refutes error")
        (let [(agg (option-or (mt qEmpty ((ok a) (some a)) ((err _) (none))) (da/makeEmptyAgg)))]
          (assert (= (.-taskCount agg) 0) "Querying empty engine has 0 taskCount")
          (refute (!= (.-taskCount agg) 0) "Empty engine taskCount refutes non-zero"))))
    (let [(stA (da/initDuckdbQueryEngine))
          (stB (da/initDuckdbQueryEngine))]
      (assert (= (.-rowCount stA) (.-rowCount stB)) "Two new engines have equal row counts")
      (refute (!= (.-rowCount stA) (.-rowCount stB)) "Two new engines refute row count difference"))
    true))

(df runTests [] -> Bool
  :d "Executes all unit tests for duckdbAdapter module."
  (do
    (assert (testDuckdbEngineInitialization) "testDuckdbEngineInitialization passed")
    (assert (testTelemetryRowCreation) "testTelemetryRowCreation passed")
    (assert (testBatchIngestionAndAccumulation) "testBatchIngestionAndAccumulation passed")
    (assert (testVectorizedQueryAggregation) "testVectorizedQueryAggregation passed")
    (assert (testPercentileLatencyCalculation) "testPercentileLatencyCalculation passed")
    (assert (testStructuredReceiptRendering) "testStructuredReceiptRendering passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true))

(df RunTests [] -> Bool
  :d "Canonical runner export for duckdbAdapterTest."
  (runTests))
