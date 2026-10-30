(module asl-parquet/tests/footerStatsTest
  :x [runTests]
  :i [(asl-parquet/footer :a foot) (asl-parquet/writer :a pq)])

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
  (let [(path "/tmp/aslParquetFooterStats.parquet")
        (columns (list (pq/i64Column "ints" (i64ArrayGenerate 4 (fn [i] (* i 3))) "PLAIN")))
        (written (pq/parquetWrite path columns (list (list "compression" "none") (list "dictionary" "false") (list "rowGroupRows" "4")) (list)))]
    (do
      (assert (err? (foot/parquetColumnStatsFloat64 (fixture) "tsUs" 0)) "an int64 column refuses the float64 reader")
      (assert (err? (foot/parquetColumnStatsInt64 (fixture) "price" 0)) "a double column refuses the int64 reader")
      (assert (err? (foot/parquetColumnStatsInt64 (fixture) "side" 0)) "an int32 column refuses the int64 reader")
      (assert (err? (foot/parquetColumnStatsInt64 (fixture) "noSuchColumn" 0)) "an unknown column is an error")
      (assert (err? (foot/parquetColumnStatsInt64 (fixture) "tsUs" 3)) "a row group past the end is an error")
      (assert (err? (foot/parquetColumnStatsInt64 (fixture) "tsUs" -1)) "a negative row group is an error")
      (assert (err? (foot/parquetColumnStatsInt64 "tests/acceptance/r1Host/fixtures/parquet/badMagic.parquet" "tsUs" 0)) "a file without PAR1 is an error")
      (assert (ok? written) "writer fixture without statistics is written")
      (assert (err? (foot/parquetColumnStatsInt64 path "ints" 0)) "a footer without statistics is an error, not a guess")
      (assert (ok? (pathRemove path)) "temporary fixture removed")
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
    true)
