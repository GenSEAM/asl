(module asl-know/examples/aslParquet :x [rowCount! selfTest] :i [])

fn ! rowCount! path: String -> Int64
  (match (parquetOpen path)
    ((err _) -1)
    ((ok h) (parquetNumRows h)))

fn ! selfTest -> Bool
  (and (= (rowCount! "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-uncompressed.parquet") 10000)
       (= (rowCount! "no/such.parquet") -1))
