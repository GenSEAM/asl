(module asl-know/examples/aslCsv :x [cell selfTest] :i [(asl-csv/csv :a csv)])

fn cell text: String row: Int64 col: Int64 -> String
  (match (csv/csvParseRows text)
    ((err _) "")
    ((ok rows) (optionOr (listGet (optionOr (listGet rows row) []) col) "")))

fn selfTest -> Bool
  (and (= (cell "a,b\nc,\"d,e\"\n" 1 1) "d,e") (= (cell "a,b\n" 5 0) ""))
