(module asl-csv/csv
  :x [CsvTable csvParseRows csvParseColumns csvNumRows csvColumnF64 csvColumnI64 csvColumnI8]
  :i [])

(schema CsvTable (:f rows I64) (:f types (List Str)) (:f rawRows (List (List Str))))
(schema CsvField (:f valid Bool) (:f value Str) (:f next I64) (:f message Str))
(schema CsvRowScan (:f fields (List Str)) (:f next I64))

fn csvSlice text: String start: Int64 end: Int64 -> String
  (optionOr (stringSlice text start end) "")

fn csvTypeList spec: String -> (Result (List String) String)
  (let [(bytes (stringToBytes spec)) (n (bytesLength bytes))
        (loop (fn [loop start pos acc] -> (Result (List String) String)
          (if (>= pos n)
            (let [(last (csvSlice spec start pos))]
              (if (or (= last "f64") (or (= last "i64") (= last "i8")))
                (ok (listReverse (cons last acc))) (err (str "unsupported CSV type: " last))))
            (if (= (bytesGet bytes pos) 44)
              (let [(part (csvSlice spec start pos))]
                (if (or (= part "f64") (or (= part "i64") (= part "i8")))
                  (loop loop (+ pos 1) (+ pos 1) (cons part acc))
                  (err (str "unsupported CSV type: " part))))
              (loop loop start (+ pos 1) acc)))))]
    (if (= n 0) (err "empty CSV type specification") (loop loop 0 0 (list))))

fn csvScanField text: String bytes: Bytes pos: Int64 -> CsvField
  (let [(n (bytesLength bytes)) (firstByte (bytesGet bytes pos))]
    (if (= firstByte 34)
      (let [(quoted (fn [quoted chunk pos acc] -> CsvField
              (if (>= pos n) (CsvField :valid false :value "" :next pos :message "unterminated quoted CSV field")
          (if (= (bytesGet bytes pos) 34)
            (if (and (< (+ pos 1) n) (= (bytesGet bytes (+ pos 1)) 34))
              (quoted quoted (+ pos 2) (+ pos 2) (str acc (csvSlice text chunk pos) "\""))
              (let [(value (str acc (csvSlice text chunk pos))) (next (+ pos 1))]
                (if (or (= next n) (or (= (bytesGet bytes next) 44) (or (= (bytesGet bytes next) 10) (= (bytesGet bytes next) 13))))
                  (CsvField :valid true :value value :next next :message "") (CsvField :valid false :value "" :next next :message "characters after closing CSV quote"))))
            (quoted quoted chunk (+ pos 1) acc)))))]
        (quoted quoted (+ pos 1) (+ pos 1) ""))
      (let [(plain (fn [plain i] -> CsvField
        (if (>= i n) (CsvField :valid true :value (csvSlice text pos i) :next i :message "")
          (let [(b (bytesGet bytes i))]
            (if (or (= b 44) (or (= b 10) (= b 13))) (CsvField :valid true :value (csvSlice text pos i) :next i :message "")
              (if (= b 34) (CsvField :valid false :value "" :next i :message "quote inside unquoted CSV field") (plain plain (+ i 1))))))))]
        (plain plain pos))))

fn csvScanRow text: String bytes: Bytes pos: Int64 -> (Result CsvRowScan String)
  (let [(n (bytesLength bytes))
        (loop (fn [loop at acc] -> (Result CsvRowScan String)
          (let [(field (csvScanField text bytes at))]
            (if (not field.valid) (err field.message)
              (let [(value field.value) (next field.next)]
              (if (>= next n) (ok (CsvRowScan :fields (listReverse (cons value acc)) :next n))
                (let [(sep (bytesGet bytes next))]
                  (if (= sep 44)
                    (if (= (+ next 1) n) (ok (CsvRowScan :fields (listReverse (cons "" (cons value acc))) :next n))
                      (loop loop (+ next 1) (cons value acc)))
                    (if (= sep 10) (ok (CsvRowScan :fields (listReverse (cons value acc)) :next (+ next 1)))
                      (if (= sep 13)
                        (if (and (< (+ next 1) n) (= (bytesGet bytes (+ next 1)) 10))
                          (ok (CsvRowScan :fields (listReverse (cons value acc)) :next (+ next 2)))
                          (err "bare carriage return in CSV"))
                      (err "invalid CSV field boundary")))))))))))]
    (loop loop pos (list)))

fn csvParseRows text: String -> (Result (List (List String)) String)
  (let [(bytes (stringToBytes text)) (n (bytesLength bytes))
        (loop (fn [loop pos width acc] -> (Result (List (List String)) String)
          (if (>= pos n) (ok (listReverse acc))
            (if (or (= (bytesGet bytes pos) 10) (= (bytesGet bytes pos) 13))
              (if (= (bytesGet bytes pos) 13)
                (if (and (< (+ pos 1) n) (= (bytesGet bytes (+ pos 1)) 10))
                  (loop loop (+ pos 2) width acc) (err "bare carriage return in CSV"))
                (loop loop (+ pos 1) width acc))
              (mt (csvScanRow text bytes pos)
                ((err e) (err e))
                ((ok row)
                  (let [(fields row.fields)
                        (after row.next)
                        (fieldCount (listLength fields))]
                      (if (and (> width 0) (!= width fieldCount))
                        (err (str "inconsistent CSV row width at row " (stringFromInt64 (listLength acc)) ": expected " (stringFromInt64 width) " fields, got " (stringFromInt64 fieldCount)))
                        (loop loop after fieldCount (cons fields acc))))))))))]
    (if (= n 0) (ok (list)) (loop loop 0 0 (list))))

fn csvRowsRest rows: (List (List String)) -> (List (List String))
  (optionOr (listTail rows) (list))

fn csvFloatArray rows: (List (List String)) col: Int64 -> F64Array
  (let [(loop (fn [loop rest acc] -> (List F64Array)
          (mt (listHead rest)
            ((none) (listReverse acc))
            ((some row)
              (let [(value (optionOr (stringToFloat64 (optionOr (listGet row col) "")) 0.0))]
                (loop loop (csvRowsRest rest) (cons (f64ArrayGenerate 1 (fn [i] value)) acc)))))))]
    (f64ArrayConcat (loop loop rows (list))))

fn csvIntArray rows: (List (List String)) col: Int64 -> I64Array
  (let [(loop (fn [loop rest acc] -> (List I64Array)
          (mt (listHead rest)
            ((none) (listReverse acc))
            ((some row)
              (let [(value (optionOr (stringToInt64 (optionOr (listGet row col) "")) 0))]
                (loop loop (csvRowsRest rest) (cons (i64ArrayGenerate 1 (fn [i] value)) acc)))))))]
    (i64ArrayConcat (loop loop rows (list))))

fn csvByteArray rows: (List (List String)) col: Int64 -> I8Array
  (let [(loop (fn [loop rest acc] -> (List I8Array)
          (mt (listHead rest)
            ((none) (listReverse acc))
            ((some row)
              (let [(value (optionOr (stringToInt64 (optionOr (listGet row col) "")) 0))]
                (loop loop (csvRowsRest rest) (cons (i8ArrayGenerate 1 (fn [i] value)) acc)))))))]
    (i8ArrayConcat (loop loop rows (list))))

fn csvValidateCell typeName: String value: String -> Bool
  (if (= typeName "f64")
    (some? (stringToFloat64 value))
    (if (= typeName "i64")
      (some? (stringToInt64 value))
      (let [(parsed (stringToInt64 value))]
        (if (some? parsed)
          (let [(number (optionOr parsed 0))]
            (and (>= number -128) (<= number 127)))
          false))))

fn csvValidateRow types: (List String) row: (List String) col: Int64 rowIndex: Int64 -> (Result Bool String)
  (mt (listHead types)
    ((none) (ok true))
    ((some typeName)
      (mt (listHead row)
        ((none) (err "CSV internal column bounds error"))
        ((some value)
          (if (csvValidateCell typeName value)
            (csvValidateRow (optionOr (listTail types) (list)) (optionOr (listTail row) (list)) (+ col 1) rowIndex)
            (err (str "invalid " typeName " CSV value at row " (stringFromInt64 rowIndex) " column " (stringFromInt64 col))))))))

fn csvValidateRows types: (List String) rows: (List (List String)) rowIndex: Int64 -> (Result Bool String)
  (mt (listHead rows)
    ((none) (ok true))
    ((some row)
      (mt (csvValidateRow types row 0 rowIndex)
        ((err e) (err e))
        ((ok _) (csvValidateRows types (csvRowsRest rows) (+ rowIndex 1))))))

fn csvParseColumns typeSpec: String text: String -> (Result CsvTable String)
  (mt (csvTypeList typeSpec)
    ((err e) (err e))
    ((ok types)
      (mt (csvParseRows text)
        ((err e) (err e))
        ((ok rows)
          (if (and (not (listEmpty? rows)) (!= (csvCountFields rows) (listLength types)))
            (err "CSV row width does not match type specification")
            (mt (csvValidateRows types rows 0)
              ((err e) (err e))
              ((ok _) (ok (CsvTable :rows (listLength rows) :types types :rawRows rows)))))))))

fn csvCountFields rows: (List (List String)) -> Int64
  (if (listEmpty? rows) 0 (listLength (optionOr (listHead rows) (list))))

fn csvNumRows table: CsvTable -> Int64
  table.rows

fn csvColumnCheck table: CsvTable col: Int64 typeName: String -> (Result Bool String)
  (let [(width (listLength table.types))]
    (if (or (< col 0) (>= col width))
      (err (str "CSV column " (stringFromInt64 col) " is out of range for " (stringFromInt64 width) " columns"))
      (let [(declared (optionOr (listGet table.types col) ""))]
        (if (= declared typeName)
          (ok true)
          (err (str "CSV column " (stringFromInt64 col) " has type " declared ", not " typeName))))))

fn csvColumnF64 table: CsvTable col: Int64 -> (Result F64Array String)
  (mt (csvColumnCheck table col "f64")
    ((err e) (err e))
    ((ok _) (ok (csvFloatArray table.rawRows col))))

fn csvColumnI64 table: CsvTable col: Int64 -> (Result I64Array String)
  (mt (csvColumnCheck table col "i64")
    ((err e) (err e))
    ((ok _) (ok (csvIntArray table.rawRows col))))

fn csvColumnI8 table: CsvTable col: Int64 -> (Result I8Array String)
  (mt (csvColumnCheck table col "i8")
    ((err e) (err e))
    ((ok _) (ok (csvByteArray table.rawRows col))))
