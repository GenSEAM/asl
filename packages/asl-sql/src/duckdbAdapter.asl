(module duckdbAdapter
  :d "DuckDB analytical telemetry query engine adapter with vectorized columnar scans and percentile latency calculation (ADR D87)."
  :x [initDuckdbQueryEngine makeTelemetryRow makeEmptyAgg ingestTelemetryBatch queryTelemetryVectorized computePercentile makeTelemetrySummary renderTelemetryReceipt DuckdbQueryEngineState TelemetryRow TelemetryAgg TelemetrySummary]
  :i [(reader :a rd)])

(dfs TelemetryRow
  (:f phase Str "Phase identifier")
  (:f task Str "Task identifier")
  (:f durationMs Int "Execution duration in milliseconds")
  (:f asserts Int "Executed assertions count")
  (:f refutes Int "Executed refutations count"))

(dfs DuckdbQueryEngineState
  (:f columns (List Str) "List of column definitions")
  (:f rowCount Int "Total row count")
  (:f rows (List TelemetryRow) "Stored telemetry rows"))

(dfs TelemetryAgg
  (:f taskCount Int "Total tasks in phase")
  (:f totalDurationMs Int "Total duration across tasks")
  (:f totalAsserts Int "Total assertions across tasks")
  (:f totalRefutes Int "Total refutations across tasks"))

(dfs TelemetrySummary
  (:f phase Str "Phase name")
  (:f taskCount Int "Task count")
  (:f totalDurationMs Int "Total duration")
  (:f totalAsserts Int "Total asserts")
  (:f totalRefutes Int "Total refutes")
  (:f p50 Int "P50 latency")
  (:f p90 Int "P90 latency")
  (:f p99 Int "P99 latency"))

(df initDuckdbQueryEngine [] -> DuckdbQueryEngineState
  :d "Initializes DuckDB analytical engine state with empty columns, row count zero, and empty rows."
  (DuckdbQueryEngineState
    :columns (list)
    :rowCount 0
    :rows (list)))

(df makeTelemetryRow [(phase Str) (task Str) (durationMs Int) (asserts Int) (refutes Int)] -> TelemetryRow
  :d "Constructs a TelemetryRow record with phase, task, duration, asserts, and refutes."
  (TelemetryRow
    :phase phase
    :task task
    :durationMs durationMs
    :asserts asserts
    :refutes refutes))

(df makeEmptyAgg [] -> TelemetryAgg
  :d "Constructs an empty TelemetryAgg record with zero counters."
  (TelemetryAgg
    :taskCount 0
    :totalDurationMs 0
    :totalAsserts 0
    :totalRefutes 0))

(df ingestTelemetryBatch [(st DuckdbQueryEngineState) (batch (List TelemetryRow))] -> (Result DuckdbQueryEngineState Str)
  :d "Appends batch to rows, increments rowCount by batch length, returns updated engine state."
  (let [(updatedRows (list-append (.-rows st) batch))
        (addedCount (list-length batch))
        (updatedCount (+ (.-rowCount st) addedCount))]
    (ok (DuckdbQueryEngineState
          :columns (.-columns st)
          :rowCount updatedCount
          :rows updatedRows))))

(df aggregateRowsLoop [(rows (List TelemetryRow)) (phase Str) (taskCount Int) (totalDurationMs Int) (totalAsserts Int) (totalRefutes Int)] -> TelemetryAgg
  :d "Recursively aggregates telemetry rows matching the given phase."
  (if (list-empty? rows)
    (TelemetryAgg
      :taskCount taskCount
      :totalDurationMs totalDurationMs
      :totalAsserts totalAsserts
      :totalRefutes totalRefutes)
    (let [(headRow (option-or (list-head rows) (makeTelemetryRow "" "" 0 0 0)))
          (tailRows (option-or (list-tail rows) (list)))]
      (if (= (.-phase headRow) phase)
        (aggregateRowsLoop tailRows phase (+ taskCount 1) (+ totalDurationMs (.-durationMs headRow)) (+ totalAsserts (.-asserts headRow)) (+ totalRefutes (.-refutes headRow)))
        (aggregateRowsLoop tailRows phase taskCount totalDurationMs totalAsserts totalRefutes)))))

(df queryTelemetryVectorized [(st DuckdbQueryEngineState) (phase Str)] -> (Result TelemetryAgg Str)
  :d "Filters rows where phase matches, sums taskCount, durationMs, asserts, refutes. Returns ok TelemetryAgg."
  (let [(agg (aggregateRowsLoop (.-rows st) phase 0 0 0 0))]
    (ok agg)))

(df computePercentile [(latencies (List Int)) (p Int)] -> Int
  :d "Calculates percentile latency using nearest-rank formula over sorted latencies."
  (if (list-empty? latencies)
    0
    (if (or (< p 0) (> p 100))
      0
      (let [(sorted (list-sort latencies))
            (n (list-length sorted))]
        (if (= p 0)
          (option-or (list-get sorted 0) 0)
          (let [(rank (/ (+ (* p n) 99) 100))
                (index (if (> rank n)
                         (- n 1)
                         (if (< rank 1)
                           0
                           (- rank 1))))]
            (option-or (list-get sorted index) 0)))))))

(df makeTelemetrySummary [(phase Str) (taskCount Int) (totalDurationMs Int) (totalAsserts Int) (totalRefutes Int) (p50 Int) (p90 Int) (p99 Int)] -> TelemetrySummary
  :d "Constructs a TelemetrySummary record."
  (TelemetrySummary
    :phase phase
    :taskCount taskCount
    :totalDurationMs totalDurationMs
    :totalAsserts totalAsserts
    :totalRefutes totalRefutes
    :p50 p50
    :p90 p90
    :p99 p99))

(df renderTelemetryReceipt [(s TelemetrySummary)] -> Str
  :d "Renders formatted ASN telemetry receipt string for the given summary."
  (str "(:telemetryReceipt :phase \"" (.-phase s) "\" :taskCount " (.-taskCount s) " :totalDurationMs " (.-totalDurationMs s) " :totalAsserts " (.-totalAsserts s) " :totalRefutes " (.-totalRefutes s) " :p50 " (.-p50 s) " :p90 " (.-p90 s) " :p99 " (.-p99 s) ")"))
