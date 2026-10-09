(module asl-target-llvm/tests/fixtures/nativeData/parquetTrap
  :x [main]
  :i [])

fn ! main args: (List String) -> (Result Unit String)
  (mt (parquetOpen "tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10k.parquet")
    ((err e) (err e))
    ((ok h)
      (let [(which (optionOr (listHead args) ""))]
        (do
          (println (str "trap " which))
          (cond
            ((= which "type") (println (i64ArrayLen (parquetReadI64 h "price" 0))))
            ((= which "column") (println (f64ArrayLen (parquetReadF64 h "noSuchColumn" 0))))
            ((= which "group") (println (f64ArrayLen (parquetReadF64 h "price" 99))))
            (else (println "none")))
          (ok ())))))
