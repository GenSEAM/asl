(module asl-know/tests/examplesAslParquetCoverTest
  :x [runTests]
  :i [(asl-know/examples/aslParquet :a exParquet) (asl-parquet/writer :a pq)])

fn ! putBytes! out: Bytes at: Int64 values: (List Int64) -> Int64
  (if (listEmpty? values) at
    (match (listHead values)
      ((none) at)
      ((some v)
        (do
          (bytesSet out at v)
          (putBytes! out (+ at 1) (listDrop values 1))))))

fn ! writeZeroRowParquet! path: String -> Bool
  (let [(file (bytesAlloc 40))]
    (do
      (putBytes! file 0
        (list 80 65 82 49
          21 2 25 44 72 6 115 99 104 101 109 97 21 2 0 21 4 37 0 24 1 118 0 22 0 25 12 0
          28 0 0 0
          80 65 82 49))
      (match (fileWrite path file)
        ((ok _) true)
        ((err _) false))))

fn ! withRows! path: String n: Int64 -> Bool
  (let [(values (i64ArrayGenerate n (fn [i] (+ i 1))))
        (columns (list (pq/i64Column "v" values "PLAIN")))
        (options (list (list "compression" "none") (list "level" "3") (list "dictionary" "false") (list "rowGroupRows" (stringFromInt64 (max 1 n)))))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) (str "write " n "-row fixture: " (match written ((ok _) "ok") ((err e) e))))
      (assert (= (exParquet/rowCount! path) n) (str "rowCount! reports " n " rows, got " (stringFromInt64 (exParquet/rowCount! path))))
      (assert (ok? (pathRemove path)) (str "cleanup " path))
      true))

fn ! runTests -> Bool
  (do
    (assert (= (exParquet/rowCount! "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-uncompressed.parquet") 10000) "normal case: 10k fixture reports exactly 10000 rows")
    (assert (= (exParquet/rowCount! "tests/acceptance/r1Host/fixtures/parquet/zeroLength.parquet") -1) "boundary/error: zero-length file fails parquetOpen, rowCount! returns -1")
    (assert (= (exParquet/rowCount! "tests/acceptance/r1Host/fixtures/parquet/headOnly.parquet") -1) "error path: header-only file returns -1")
    (assert (= (exParquet/rowCount! "tests/acceptance/r1Host/fixtures/parquet/truncatedFooter.parquet") -1) "error path: truncated footer returns -1")
    (assert (= (exParquet/rowCount! "tests/acceptance/r1Host/fixtures/parquet/badMagic.parquet") -1) "error path: bad magic returns -1")
    (assert (= (exParquet/rowCount! "no/such.parquet") -1) "error path: missing file returns -1")
    (assert (= (exParquet/rowCount! "tests/acceptance/r1Host/fixtures/parquet/big3e6.parquet") 3000000) "max boundary: big fixture reports exactly 3000000 rows")
    (let [(zeroPath "/tmp/aslParquetRowCountZero.parquet")]
      (do
        (assert (writeZeroRowParquet! zeroPath) "zero boundary: wrote a valid zero-row parquet fixture")
        (assert (= (exParquet/rowCount! zeroPath) 0) (str "zero boundary: rowCount! reports 0 rows for a valid zero-row parquet, got " (stringFromInt64 (exParquet/rowCount! zeroPath))))
        (assert (ok? (pathRemove zeroPath)) "zero boundary: cleanup")))
    (assert (withRows! "/tmp/aslParquetRowCountOne.parquet" 1) "single row: rowCount! reports 1")
    (assert (withRows! "/tmp/aslParquetRowCountThree.parquet" 3) "three rows: rowCount! reports 3")
    true)
