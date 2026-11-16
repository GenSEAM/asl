(module asl-csv/tests/csvCoverTest
  :x [runTests]
  :i [(asl-csv/csv :a csv)])

fn rowField rows: (List (List String)) row: Int64 col: Int64 -> String
  (optionOr (listGet (optionOr (listGet rows row) (list)) col) "")

fn f64Value table: csv/CsvTable col: Int64 expected: F64 -> Bool
  (match (csv/csvColumnF64 table col)
    ((err _) false)
    ((ok values) (= (f64ArrayGet values 0) expected)))

fn i64Value table: csv/CsvTable col: Int64 expected: Int64 -> Bool
  (match (csv/csvColumnI64 table col)
    ((err _) false)
    ((ok values) (= (i64ArrayGet values 0) expected)))

fn i8Value table: csv/CsvTable col: Int64 expected: Int64 -> Bool
  (match (csv/csvColumnI8 table col)
    ((err _) false)
    ((ok values) (= (i8ArrayGet values 0) expected)))

fn f64Empty table: csv/CsvTable -> Bool
  (match (csv/csvColumnF64 table 0)
    ((err _) false)
    ((ok values)
      (= (f64ArrayLen values) 0)))

fn i64Empty table: csv/CsvTable -> Bool
  (match (csv/csvColumnI64 table 0)
    ((err _) false)
    ((ok values)
      (= (i64ArrayLen values) 0)))

fn i8Empty table: csv/CsvTable -> Bool
  (match (csv/csvColumnI8 table 0)
    ((err _) false)
    ((ok values)
      (= (i8ArrayLen values) 0)))

fn f64Fails table: csv/CsvTable col: Int64 -> Bool
  (match (csv/csvColumnF64 table col)
    ((err _) true)
    ((ok _) false))

fn i64Fails table: csv/CsvTable col: Int64 -> Bool
  (match (csv/csvColumnI64 table col)
    ((err _) true)
    ((ok _) false))

fn i8Fails table: csv/CsvTable col: Int64 -> Bool
  (match (csv/csvColumnI8 table col)
    ((err _) true)
    ((ok _) false))

fn ! runTests -> Bool
  (let [(rowsNormal (csv/csvParseRows "a,b\r\nc,d"))
        (rowsEmpty (csv/csvParseRows ""))
        (rowsZero (csv/csvParseRows "0"))
        (rowsMax (csv/csvParseRows "9223372036854775807"))
        (rowsQuoted (csv/csvParseRows "\"a\",b"))
        (rowsBadQuote (csv/csvParseRows "a,\"b"))
        (rowsBadWidth (csv/csvParseRows "a,b\nc"))
        (tableNormal (csv/csvParseColumns "f64,i64,i8" "1.5,2,3"))
        (tableZero (csv/csvParseColumns "f64,i64,i8" "0.0,0,0"))
        (tableMax (csv/csvParseColumns "f64,i64,i8" "1.7976931348623157e308,9223372036854775807,127"))
        (tableMinI8 (csv/csvParseColumns "i8" "-128"))
        (tableRows (csv/csvParseColumns "i64" "1\n2"))
        (tableEmptyF64 (csv/csvParseColumns "f64" ""))
        (tableEmptyI64 (csv/csvParseColumns "i64" ""))
        (tableEmptyI8 (csv/csvParseColumns "i8" ""))
        (colsEmptySpec (csv/csvParseColumns "" "1"))
        (colsBadType (csv/csvParseColumns "f32" "1"))
        (colsBadWidth (csv/csvParseColumns "f64,i64" "1,2,3"))
        (colsBadF64 (csv/csvParseColumns "f64" "abc"))
        (colsBadI64 (csv/csvParseColumns "i64" "abc"))
        (colsBadI8 (csv/csvParseColumns "i8" "abc"))
        (colsI64Over (csv/csvParseColumns "i64" "9223372036854775808"))
        (colsI8Over (csv/csvParseColumns "i8" "128"))
        (colsI8Under (csv/csvParseColumns "i8" "-129"))]
    (assert (match rowsNormal
      ((err _) false)
      ((ok rows) (= (listLength rows) 2)))
      "csvParseRows normal case reads two rows")
    (assert (match rowsNormal
      ((err _) false)
      ((ok rows) (= (rowField rows 0 0) "a")))
      "csvParseRows normal row zero column zero")
    (assert (match rowsNormal
      ((err _) false)
      ((ok rows) (= (rowField rows 0 1) "b")))
      "csvParseRows normal row zero column one")
    (assert (match rowsNormal
      ((err _) false)
      ((ok rows) (= (rowField rows 1 0) "c")))
      "csvParseRows normal row one column zero")
    (assert (match rowsNormal
      ((err _) false)
      ((ok rows) (= (rowField rows 1 1) "d")))
      "csvParseRows normal row one column one")
    (assert (match rowsEmpty
      ((err _) false)
      ((ok rows) (listEmpty? rows)))
      "csvParseRows empty input returns an empty row list")
    (assert (match rowsZero
      ((err _) false)
      ((ok rows) (= (listLength rows) 1)))
      "csvParseRows zero input returns one row")
    (assert (match rowsZero
      ((err _) false)
      ((ok rows) (= (rowField rows 0 0) "0")))
      "csvParseRows preserves a zero field")
    (assert (match rowsMax
      ((err _) false)
      ((ok rows) (= (rowField rows 0 0) "9223372036854775807")))
      "csvParseRows preserves a maximum i64 token")
    (assert (match rowsQuoted
      ((err _) false)
      ((ok rows) (= (rowField rows 0 0) "a")))
      "csvParseRows removes surrounding quotes")
    (assert (match rowsBadQuote
      ((err e) (= e "unterminated quoted CSV field"))
      ((ok _) false))
      "csvParseRows reports an unterminated quoted field")
    (assert (match rowsBadWidth
      ((err _) true)
      ((ok _) false))
      "csvParseRows rejects inconsistent row widths")
    (assert (match tableRows
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 2)))
      "csvNumRows normal case counts two rows")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 1)))
      "csvNumRows counts a normal typed row")
    (assert (match tableZero
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 1)))
      "csvNumRows counts a row containing zero values")
    (assert (match tableMax
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 1)))
      "csvNumRows counts a row containing maximum values")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (f64Value table 0 1.5)))
      "csvColumnF64 normal case returns the declared f64 value")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (i64Value table 1 2)))
      "csvColumnI64 normal case returns the declared i64 value")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (i8Value table 2 3)))
      "csvColumnI8 normal case returns the declared i8 value")
    (assert (match tableZero
      ((err _) false)
      ((ok table) (f64Value table 0 0.0)))
      "csvColumnF64 preserves zero")
    (assert (match tableZero
      ((err _) false)
      ((ok table) (i64Value table 1 0)))
      "csvColumnI64 preserves zero")
    (assert (match tableZero
      ((err _) false)
      ((ok table) (i8Value table 2 0)))
      "csvColumnI8 preserves zero")
    (assert (match tableMax
      ((err _) false)
      ((ok table) (f64Value table 0 1.7976931348623157e308)))
      "csvColumnF64 accepts the maximum finite f64")
    (assert (match tableMax
      ((err _) false)
      ((ok table) (i64Value table 1 9223372036854775807)))
      "csvColumnI64 accepts the maximum i64")
    (assert (match tableMax
      ((err _) false)
      ((ok table) (i8Value table 2 127)))
      "csvColumnI8 accepts the maximum i8")
    (assert (match tableMinI8
      ((err _) false)
      ((ok table) (i8Value table 0 -128)))
      "csvColumnI8 accepts the minimum i8")
    (assert (match tableEmptyF64
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 0)))
      "csvNumRows returns zero for an empty f64 table")
    (assert (match tableEmptyF64
      ((err _) false)
      ((ok table) (f64Empty table)))
      "csvColumnF64 empty table returns an empty array")
    (assert (match tableEmptyI64
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 0)))
      "csvNumRows returns zero for an empty i64 table")
    (assert (match tableEmptyI64
      ((err _) false)
      ((ok table) (i64Empty table)))
      "csvColumnI64 empty table returns an empty array")
    (assert (match tableEmptyI8
      ((err _) false)
      ((ok table) (= (csv/csvNumRows table) 0)))
      "csvNumRows returns zero for an empty i8 table")
    (assert (match tableEmptyI8
      ((err _) false)
      ((ok table) (i8Empty table)))
      "csvColumnI8 empty table returns an empty array")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (f64Fails table 1)))
      "csvColumnF64 rejects a column declared as i64")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (f64Fails table 3)))
      "csvColumnF64 rejects a past-end column index")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (i64Fails table 0)))
      "csvColumnI64 rejects a column declared as f64")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (i64Fails table -1)))
      "csvColumnI64 rejects a negative column index")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (i8Fails table 0)))
      "csvColumnI8 rejects a column declared as f64")
    (assert (match tableNormal
      ((err _) false)
      ((ok table) (i8Fails table 3)))
      "csvColumnI8 rejects a past-end column index")
    (assert (match colsEmptySpec
      ((err e) (= e "empty CSV type specification"))
      ((ok _) false))
      "csvParseColumns rejects an empty type specification")
    (assert (match colsBadType
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects an unsupported type")
    (assert (match colsBadWidth
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects a row width mismatch")
    (assert (match colsBadF64
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects a nonnumeric f64 cell")
    (assert (match colsBadI64
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects a nonnumeric i64 cell")
    (assert (match colsBadI8
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects a nonnumeric i8 cell")
    (assert (match colsI64Over
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects i64 overflow")
    (assert (match colsI8Over
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects i8 overflow")
    (assert (match colsI8Under
      ((err _) true)
      ((ok _) false))
      "csvParseColumns rejects i8 underflow")
    true)
