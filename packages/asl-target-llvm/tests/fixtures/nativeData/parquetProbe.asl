(module asl-target-llvm/tests/fixtures/nativeData/parquetProbe
  :x [main]
  :i [])

fn polyStep acc: Int64 x: Int64 -> Int64
  (mod (+ (* acc 31) (mod x 1000000007)) 1000000007)

fn floatStep acc: Float64 x: Float64 -> Float64
  (+ (* acc 0.5) x)

fn ! columnLine h: ParquetHandle name: String rg: Int64 -> String
  (let [(t (parquetColumnType h name))]
    (cond
      ((= t "double")
        (let [(xs (parquetReadF64 h name rg))
              (n (f64ArrayLen xs))]
          (str name " " t " rg" rg " n" n " fold " (f64ArrayFold floatStep 0.0 xs) " sum " (f64ArraySum xs)
               (if (> n 0) (str " first " (f64ArrayGet xs 0) " last " (f64ArrayGet xs (- n 1))) ""))))
      ((= t "int64")
        (let [(xs (parquetReadI64 h name rg))
              (n (i64ArrayLen xs))]
          (str name " " t " rg" rg " n" n " poly " (i64ArrayFold polyStep 0 xs)
               (if (> n 0) (str " first " (i64ArrayGet xs 0) " last " (i64ArrayGet xs (- n 1))) ""))))
      ((= t "int8")
        (let [(xs (parquetReadI8 h name rg))
              (n (i8ArrayLen xs))]
          (str name " " t " rg" rg " n" n " poly " (i8ArrayFold polyStep 0 xs) " sum " (i8ArraySum xs) " ones " (i8ArrayCountEq xs 1))))
      (else (str name " " t))))

fn ! probe path: String cols: (List String) -> Bool
  (do
    (println (str "file " path))
    (mt (parquetOpen path)
      ((err e) (do (println (str "open err " e)) true))
      ((ok h)
        (let [(groups (parquetNumRowGroups h))]
          (do
            (println (str "rows " (parquetNumRows h) " groups " groups))
            (println (str "kv " (resultOr (parquetKvMetadata h "vtbot.dataset") "missing")))
            (println (str "kvAbsent " (mt (parquetKvMetadata h "noSuchKey") ((ok v) (str "ok " v)) ((err e) (str "err " e)))))
            (fold (fn [(acc Bool) (c String)] -> Bool
                    (fold (fn [(a Bool) (rg Int64)] -> Bool (do (println (columnLine h c rg)) a)) acc (range 0 groups)))
                  true cols))))))

fn ! main -> (Result Unit String)
  (let [(sei (list "tsUs" "tradeId" "price" "amount" "side"))
        (canonical (list "tsUs" "price" "qty" "side" "tradeId"))
        (fx "tests/acceptance/r1Host/fixtures/parquet/")]
    (do
      (probe "tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10k.parquet" sei)
      (probe (str fx "seiSpotDeals10k-snappy.parquet") sei)
      (probe (str fx "seiSpotDeals10k-uncompressed.parquet") sei)
      (probe (str fx "seiSpotDeals10k-zstdPageV2.parquet") sei)
      (probe "tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10kCanonical.parquet" canonical)
      (probe (str fx "big3e6.parquet") (list "price" "side"))
      (probe (str fx "badMagic.parquet") (list))
      (probe (str fx "truncatedFooter.parquet") (list))
      (probe (str fx "zeroLength.parquet") (list))
      (probe (str fx "headOnly.parquet") (list))
      (probe (str fx "missing.parquet") (list))
      (probe "tests/acceptance/vtbotDataPlane/fixtures/unknownEncoding.parquet" (list))
      (probe "tests/acceptance/vtbotDataPlane/fixtures/truncatedPage.parquet" (list))
      (ok ())))
