(module asl-parquet/tests/footerStatsTest
  :x [runTests]
  :i [(asl-parquet/footer :a foot) (asl-parquet/writer :a pq) (asl-parquet/reader :a rd)])

; (:m :ref V0021-PQ-STATS :do "expected bounds come from pyarrow row_group(g).column(c).statistics on the fixture, an oracle independent of the reader under test")
fn fixture -> String
  "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-zstdPageV2.parquet"

fn checkInt64! column: String group: Int64 low: Int64 high: Int64 -> Bool
  (match (foot/parquetColumnStatsInt64 (fixture) column group)
    ((err e) (assert false (str "int64 stats " column " group " (stringFromInt64 group) ": " e)))
    ((ok s)
      (do
        (assert (= s.min low) (str column " group " (stringFromInt64 group) " min " (stringFromInt64 s.min)))
        (assert (= s.max high) (str column " group " (stringFromInt64 group) " max " (stringFromInt64 s.max)))
        (assert (= s.nulls 0) (str column " group " (stringFromInt64 group) " null count"))
        true)))

fn checkFloat64! column: String group: Int64 low: Float64 high: Float64 -> Bool
  (match (foot/parquetColumnStatsFloat64 (fixture) column group)
    ((err e) (assert false (str "float64 stats " column " group " (stringFromInt64 group) ": " e)))
    ((ok s)
      (do
        (assert (= s.min low) (str column " group " (stringFromInt64 group) " min " (stringFromFloat64 s.min)))
        (assert (= s.max high) (str column " group " (stringFromInt64 group) " max " (stringFromFloat64 s.max)))
        (assert (= s.nulls 0) (str column " group " (stringFromInt64 group) " null count"))
        true)))



fn ! checkRejections! -> Bool
  (do
    (assert (err? (foot/parquetColumnStatsFloat64 (fixture) "tsUs" 0)) "an int64 column refuses the float64 reader")
    (assert (err? (foot/parquetColumnStatsInt64 (fixture) "price" 0)) "a double column refuses the int64 reader")
    (assert (err? (foot/parquetColumnStatsInt64 (fixture) "side" 0)) "an int32 column refuses the int64 reader")
    (assert (err? (foot/parquetColumnStatsInt64 (fixture) "noSuchColumn" 0)) "an unknown column is an error")
    (assert (err? (foot/parquetColumnStatsInt64 (fixture) "tsUs" 3)) "a row group past the end is an error")
    (assert (err? (foot/parquetColumnStatsInt64 (fixture) "tsUs" -1)) "a negative row group is an error")
    (assert (err? (foot/parquetColumnStatsInt64 "tests/acceptance/r1Host/fixtures/parquet/badMagic.parquet" "tsUs" 0)) "a file without PAR1 is an error")
    true)

; (:m :ref V0021-PQ-STATS :do "the writer's own files carry per-row-group statistics: two groups of three rows, a negative minimum, a delta-encoded and a plain column, and the file still reads back through the pure reader")
fn ! checkWritten! -> Bool
  (let [(path "/tmp/aslParquetFooterStatsWritten.parquet")
        (ints (i64ArrayGenerate 6 (fn [i] (cond ((= i 0) -5) ((= i 1) 7) ((= i 2) 3) ((= i 3) -2) ((= i 4) 9) (else 1)))))
        (floats (f64ArrayGenerate 6 (fn [i] (cond ((= i 0) 0.5) ((= i 1) -1.25) ((= i 2) 2.0) ((= i 3) 8.0) ((= i 4) -3.5) (else 4.0)))))
        (small (i8ArrayGenerate 6 (fn [i] (cond ((= i 0) -3) ((= i 1) 4) ((= i 2) 1) ((= i 3) 0) ((= i 4) 9) (else -7)))))
        (columns (list (pq/i64Column "ints" ints "DELTA_BINARY_PACKED") (pq/f64Column "floats" floats "PLAIN") (pq/i8Column "small" small "PLAIN")))
        (written (pq/parquetWrite path columns (list (list "compression" "none") (list "dictionary" "false") (list "rowGroupRows" "3")) (list)))]
    (do
      (assert (ok? written) "writer fixture with statistics is written")
      (match (foot/parquetColumnStatsInt64 path "ints" 0)
        ((err e) (assert false e))
        ((ok s) (do (assert (and (= s.min -5) (= s.max 7)) "written ints group 0 bounds") (assert (= s.nulls 0) "written ints null count"))))
      (match (foot/parquetColumnStatsInt64 path "ints" 1)
        ((err e) (assert false e))
        ((ok s) (assert (and (= s.min -2) (= s.max 9)) "written ints group 1 bounds")))
      (match (foot/parquetColumnStatsFloat64 path "floats" 0)
        ((err e) (assert false e))
        ((ok s) (assert (and (= s.min -1.25) (= s.max 2.0)) "written floats group 0 bounds")))
      (match (foot/parquetColumnStatsFloat64 path "floats" 1)
        ((err e) (assert false e))
        ((ok s) (assert (and (= s.min -3.5) (= s.max 8.0)) "written floats group 1 bounds")))
      (match (rd/parquetOpen path)
        ((err e) (assert false (str "pure reader opens the written file: " e)))
        ((ok h) (do (assert (and (= (rd/parquetNumRowGroups h) 2) (= (i64ArraySum (rd/parquetReadI64 h "ints" 1)) 8)) "pure reader still reads the written file") (assert (= (i8ArrayGet (rd/parquetReadI8 h "small" 1) 1) 9) "pure reader reads the int8 column of the written file"))))
      (match (fileReadBytes path)
        ((err e) (assert false e))
        ((ok raw)
          (let [(stop (- (bytesLength raw) 9))]
            (assert (and (= (bytesGet raw (- stop 1)) 0) (and (= (bytesGet raw (- stop 2)) 0) (and (= (bytesGet raw (- stop 3)) 28)
                         (and (= (bytesGet raw (- stop 6)) 28) (= (bytesGet raw (- stop 9)) 28))))) "footer ends with a TypeDefinedOrder column order per leaf column"))))
      (assert (ok? (pathRemove path)) "temporary fixture removed")
      true))

; (:m :ref V0021-PQ-STATS :do "a chunk holding NaN gets no statistics, so the reader reports an error instead of a bound a NaN would corrupt")
fn ! checkNaN! -> Bool
  (let [(path "/tmp/aslParquetFooterStatsNaN.parquet")
        (floats (f64ArrayGenerate 3 (fn [i] (if (= i 1) (sqrt -1.0) 1.0))))
        (written (pq/parquetWrite path (list (pq/f64Column "floats" floats "PLAIN")) (list (list "compression" "none") (list "dictionary" "false") (list "rowGroupRows" "3")) (list)))]
    (do
      (assert (ok? written) "NaN fixture is written")
      (assert (err? (foot/parquetColumnStatsFloat64 path "floats" 0)) "a NaN chunk has no statistics")
      (assert (ok? (pathRemove path)) "NaN fixture removed")
      true))

fn ! runTests -> Bool
  (do
    (checkInt64! "tsUs" 0 1782864090013919 1783010805663592)
    (checkInt64! "tsUs" 1 1783010940814814 1783212467982568)
    (checkInt64! "tsUs" 2 1783212947923969 1783315035412213)
    (checkInt64! "tradeId" 2 24644075 24646074)
    (checkFloat64! "price" 0 0.04648 0.04932)
    (checkFloat64! "amount" 2 0.75 164270.0)
    (checkRejections!)
    (checkWritten!)
    (checkNaN!)
    true)
