(module asl-parquet/tests/readerParityTest
  :x [runTests]
  :i [(asl-parquet/reader :a r) (asl-parquet/writer :a pq)])

fn sameI64! a: I64Array b: I64Array i: Int64 -> Bool
  (if (= i (i64ArrayLen a)) (= (i64ArrayLen a) (i64ArrayLen b))
    (and (= (i64ArrayGet a i) (i64ArrayGet b i)) (sameI64! a b (+ i 1))))

fn sameI8! a: I8Array b: I8Array i: Int64 -> Bool
  (if (= i (i8ArrayLen a)) (= (i8ArrayLen a) (i8ArrayLen b))
    (and (= (i8ArrayGet a i) (i8ArrayGet b i)) (sameI8! a b (+ i 1))))

fn sameF64! a: F64Array b: F64Array i: Int64 -> Bool
  (if (= i (f64ArrayLen a)) (= (f64ArrayLen a) (f64ArrayLen b))
    (and (= (f64ArrayGet a i) (f64ArrayGet b i)) (sameF64! a b (+ i 1))))

fn checkColumn! path: String name: String rg: Int64 -> Bool
  (mt (parquetOpen path)
    ((err e) (assert false (str "host open failed " path ": " e)))
    ((ok native)
     (mt (r/parquetOpen path)
       ((err e) (assert false (str "ASL open failed " path ": " e)))
       ((ok pure)
        (let [(kind (parquetColumnType native name))]
          (cond
            ((= kind "int64")
             (do (assert (sameI64! (parquetReadI64 native name rg) (r/parquetReadI64 pure name rg) 0)
                 (str path " " name " row group " rg " I64 parity")) true))
            ((= kind "int8")
             (do (assert (sameI8! (parquetReadI8 native name rg) (r/parquetReadI8 pure name rg) 0)
                 (str path " " name " row group " rg " I8 parity")) true))
            ((= kind "double")
             (do (assert (sameF64! (parquetReadF64 native name rg) (r/parquetReadF64 pure name rg) 0)
                 (str path " " name " row group " rg " F64 parity")) true))
            (else true)))))))

fn checkColumns! path: String columns: (List String) groups: Int64 -> Bool
  (if (= (listLength columns) 0) true
    (let [(name (optionOr (listHead columns) ""))]
      (and (checkGroup! path name 0 groups)
        (checkColumns! path (optionOr (listTail columns) (list)) groups))))

fn checkGroup! path: String name: String group: Int64 groups: Int64 -> Bool
  (if (>= group groups) true
    (and (checkColumn! path name group) (checkGroup! path name (+ group 1) groups)))

fn checkFixture! path: String columns: (List String) -> Bool
  (mt (parquetOpen path)
    ((err e) (assert false (str "fixture native open: " path ": " e)))
    ((ok h) (checkColumns! path columns (parquetNumRowGroups h))))

fn checkRejected! path: String -> Bool
  (let [(native (parquetOpen path))
        (pure (r/parquetOpen path))]
    (do
      (assert (and (not (ok? native)) (not (ok? pure)))
        (str "both readers reject malformed fixture " path))
      true))

fn checkWritten! path: String codec: String -> Bool
  (let [(ints (i64ArrayGenerate 7 (fn [i] (- (* i i) 12))))
        (floats (f64ArrayGenerate 7 (fn [i] (/ (int64ToFloat64 (- (* i 7) 9)) 4.0))))
        (small (i8ArrayGenerate 7 (fn [i] (- i 3))))
        (columns (list (pq/i64Column "ints" ints "PLAIN")
                       (pq/f64Column "floats" floats "PLAIN")
                       (pq/i8Column "small" small "PLAIN")))
        (options (list (list "compression" codec) (list "level" "3")
                       (list "dictionary" "false") (list "rowGroupRows" "3")))
        (written (pq/parquetWrite path columns options (list)))]
    (do
      (assert (ok? written) (str "writer fixture " codec ": " (mt written ((ok _) "ok") ((err e) e))))
      (let [(parity (checkFixture! path (list "ints" "floats" "small")))
            (removed (pathRemove path))]
        (do (assert (ok? removed) (str "remove temporary fixture " path)) parity))))

fn ! runTests -> Bool
  (do
    (checkFixture! "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-uncompressed.parquet"
      (list "tsUs" "tradeId" "price" "amount" "side"))
    (checkFixture! "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-zstdPageV2.parquet"
      (list "tsUs" "tradeId" "price" "amount" "side"))
    (checkFixture! "tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10k.parquet"
      (list "tsUs" "tradeId" "price" "amount" "side"))
    (checkFixture! "tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10kCanonical.parquet"
      (list "tsUs" "price" "qty" "side" "tradeId"))
    (checkFixture! "tests/acceptance/r1Host/fixtures/parquet/big3e6.parquet" (list "price" "side"))
    (checkRejected! "tests/acceptance/r1Host/fixtures/parquet/badMagic.parquet")
    (checkRejected! "tests/acceptance/r1Host/fixtures/parquet/headOnly.parquet")
    (checkRejected! "tests/acceptance/r1Host/fixtures/parquet/truncatedFooter.parquet")
    (checkRejected! "tests/acceptance/r1Host/fixtures/parquet/zeroLength.parquet")
    (checkRejected! "tests/acceptance/vtbotDataPlane/fixtures/truncatedPage.parquet")
    (checkRejected! "tests/acceptance/vtbotDataPlane/fixtures/unknownEncoding.parquet")
    (checkWritten! "/tmp/aslParquetReaderNone.parquet" "none")
    (checkWritten! "/tmp/aslParquetReaderZstd.parquet" "zstd")
    (do
      (mt (parquetOpen "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-snappy.parquet")
        ((err e) (assert (= e "host does not support fixture") "host opens SNAPPY fixture"))
        ((ok native)
         (mt (r/parquetOpen "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-snappy.parquet")
           ((ok _) (assert false "SNAPPY must be rejected by the pure reader"))
           ((err e) (assert (= e "snappy unsupported") "SNAPPY reports unsupported")))))
      true))
