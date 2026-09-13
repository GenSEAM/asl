(module asl-codec/csvTranspileTest
  :d "Unit verification test suite for RFC 4180 CSV / TSV <-> ASN Tabular Transpiler"
  :x [testCsvBasicTable
      testCsvQuotedFieldsAndCommas
      testTsvTabs
      testCsvRoundtrip
      testCsvNegative
      runTests]
  :i [(asl-codec/csvTranspile :a ct)])

(df testCsvBasicTable [] -> Bool
  :d "Verifies simple CSV document conversion to ASN table."
  (let [(res (ct/csvToAsn "id,name,role\n1,Alice,admin\n2,Bob,developer"))]
    (assert (.-success res) "basic csv succeeds")
    (assert (string-contains? (.-output res) "[:id :name :role]") "contains header vector")
    (assert (string-contains? (.-output res) "[1 \"Alice\" \"admin\"]") "contains first row")
    (assert (string-contains? (.-output res) "[2 \"Bob\" \"developer\"]") "contains second row")
    (assert (>= (.-savingsPercent res) 20.0) "savings >= 20%")
    true))

(df testCsvQuotedFieldsAndCommas [] -> Bool
  :d "Verifies RFC 4180 quotes with embedded commas and escaped double quotes."
  (let [(csvPayload "id,name,location\n1,\"Smith, John\",\"New York, NY\"\n2,\"Alice \"\"The Boss\"\"\",London")
        (res (ct/csvToAsn csvPayload))]
    (assert (.-success res) "quoted csv succeeds")
    (assert (string-contains? (.-output res) "\"Smith, John\"") "preserves comma inside quotes")
    (assert (string-contains? (.-output res) "\"New York, NY\"") "preserves location with comma")
    (assert (string-contains? (.-output res) "Alice \"The Boss\"") "decodes double quotes correctly")
    true))

(df testTsvTabs [] -> Bool
  :d "Verifies tab-separated TSV conversion to ASN table."
  (let [(tsvPayload "id\tname\tscore\n1\tAlice\t98.5\n2\tBob\t87.0")
        (res (ct/tsvToAsn tsvPayload))]
    (assert (.-success res) "tsv succeeds")
    (assert (string-contains? (.-output res) "[:id :name :score]") "contains tsv headers")
    (assert (string-contains? (.-output res) "98.5") "contains float score 98.5")
    (assert (string-contains? (.-output res) "87.0") "contains float score 87.0")
    true))

(df testCsvRoundtrip [] -> Bool
  :d "Verifies ASN table serialization back to valid CSV format."
  (let [(asnPayload "([:id :name :role] [[1 \"Alice\" \"admin\"] [2 \"Smith, John\" \"developer\"]])")
        (res (ct/asnToCsv asnPayload))]
    (assert (.-success res) "asn to csv succeeds")
    (assert (string-contains? (.-output res) "id,name,role") "contains csv header")
    (assert (string-contains? (.-output res) "1,Alice,admin") "contains unquoted row")
    (assert (string-contains? (.-output res) "\"Smith, John\"") "quotes row containing comma")
    true))

(df testCsvNegative [] -> Bool
  :d "Verifies rejection of empty or malformed inputs."
  (let [(rEmptyC (ct/csvToAsn ""))
        (rEmptyA (ct/asnToCsv ""))
        (rBadA (ct/asnToCsv "not an asn"))]
    (assert (not (.-success rEmptyC)) "empty csv rejected")
    (assert (not (.-success rEmptyA)) "empty asn rejected")
    (assert (not (.-success rBadA)) "invalid asn root rejected")
    true))

(df runTests [] -> Bool
  :d "Runs all CSV and TSV transpiler unit tests."
  (do
    (assert (testCsvBasicTable) "basic table")
    (assert (testCsvQuotedFieldsAndCommas) "quoted fields and commas")
    (assert (testTsvTabs) "tsv tabs")
    (assert (testCsvRoundtrip) "roundtrip")
    (assert (testCsvNegative) "negative")
    true))
