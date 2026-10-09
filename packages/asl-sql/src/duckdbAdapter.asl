(module duckdbAdapter :x [initDuckdbQueryEngine makeTelemetryRow makeEmptyAgg ingestTelemetryBatch queryTelemetryVectorized computePercentile makeTelemetrySummary renderTelemetryReceipt DuckdbQueryEngineState TelemetryRow TelemetryAgg TelemetrySummary] :i [(reader :a rd)])

(schema TelemetryRow (:f phase Str) (:f task Str) (:f durationMs Int) (:f asserts Int) (:f refutes Int))

(schema DuckdbQueryEngineState (:f columns (List Str)) (:f rowCount Int) (:f rows (List TelemetryRow)))

(schema TelemetryAgg (:f taskCount Int) (:f totalDurationMs Int) (:f totalAsserts Int) (:f totalRefutes Int))

(schema TelemetrySummary (:f phase Str) (:f taskCount Int) (:f totalDurationMs Int) (:f totalAsserts Int) (:f totalRefutes Int) (:f p50 Int) (:f p90 Int) (:f p99 Int))

fn initDuckdbQueryEngine -> DuckdbQueryEngineState
  (DuckdbQueryEngineState :columns (list) :rowCount 0 :rows (list))

fn makeTelemetryRow phase: Str task: Str durationMs: Int asserts: Int refutes: Int -> TelemetryRow
  (TelemetryRow :phase phase :task task :durationMs durationMs :asserts asserts :refutes refutes)

fn makeEmptyAgg -> TelemetryAgg
  (TelemetryAgg :taskCount 0 :totalDurationMs 0 :totalAsserts 0 :totalRefutes 0)

fn ingestTelemetryBatch st: DuckdbQueryEngineState batch: (List TelemetryRow) -> (Result DuckdbQueryEngineState Str)
  (let [(updatedRows (listAppend st.rows batch)) (addedCount (listLength batch)) (updatedCount (+ st.rowCount addedCount))] (ok (with st :rowCount updatedCount :rows updatedRows)))

fn aggregateRowsLoop rows: (List TelemetryRow) phase: Str taskCount: Int totalDurationMs: Int totalAsserts: Int totalRefutes: Int -> TelemetryAgg
  (if (listEmpty? rows) (TelemetryAgg :taskCount taskCount :totalDurationMs totalDurationMs :totalAsserts totalAsserts :totalRefutes totalRefutes) (let [(headRow (optionOr (listHead rows) (makeTelemetryRow "" "" 0 0 0))) (tailRows (optionOr (listTail rows) (list)))] (if (= headRow.phase phase) (aggregateRowsLoop tailRows phase (+ taskCount 1) (+ totalDurationMs headRow.durationMs) (+ totalAsserts headRow.asserts) (+ totalRefutes headRow.refutes)) (aggregateRowsLoop tailRows phase taskCount totalDurationMs totalAsserts totalRefutes))))

fn queryTelemetryVectorized st: DuckdbQueryEngineState phase: Str -> (Result TelemetryAgg Str)
  (let [(agg (aggregateRowsLoop st.rows phase 0 0 0 0))] (ok agg))

fn computePercentile latencies: (List Int) p: Int -> Int
  (if (listEmpty? latencies) 0 (if (or (< p 0) (> p 100)) 0 (let [(sorted (listSort latencies)) (n (listLength sorted))] (if (= p 0) (optionOr (listGet sorted 0) 0) (let [(rank (/ (+ (* p n) 99) 100)) (index (if (> rank n) (- n 1) (if (< rank 1) 0 (- rank 1))))] (optionOr (listGet sorted index) 0))))))

fn makeTelemetrySummary phase: Str taskCount: Int totalDurationMs: Int totalAsserts: Int totalRefutes: Int p50: Int p90: Int p99: Int -> TelemetrySummary
  (TelemetrySummary :phase phase :taskCount taskCount :totalDurationMs totalDurationMs :totalAsserts totalAsserts :totalRefutes totalRefutes :p50 p50 :p90 p90 :p99 p99)

fn renderTelemetryReceipt s: TelemetrySummary -> Str
  (str "(:telemetryReceipt :phase \"" s.phase "\" :taskCount " s.taskCount " :totalDurationMs " s.totalDurationMs " :totalAsserts " s.totalAsserts " :totalRefutes " s.totalRefutes " :p50 " s.p50 " :p90 " s.p90 " :p99 " s.p99 ")")
