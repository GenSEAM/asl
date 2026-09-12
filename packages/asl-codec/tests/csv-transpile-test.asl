(module asl-codec/csv-transpile-test
  :d "Unit verification test suite for RFC 4180 CSV / TSV <-> ASN Tabular Transpiler"
  :x [test-csv-basic-table
      test-csv-quoted-fields-and-commas
      test-tsv-tabs
      test-csv-roundtrip
      test-csv-negative
      run-tests]
  :i [(asl-codec/csv-transpile :a ct)])

(df test-csv-basic-table [] -> Bool
  :d "Verifies simple CSV document conversion to ASN table."
  (let [(res (ct/csv-to-asn "id,name,role\n1,Alice,admin\n2,Bob,developer"))]
    (assert (.-success res) "basic csv succeeds")
    (assert (string-contains? (.-output res) "[:id :name :role]") "contains header vector")
    (assert (string-contains? (.-output res) "[1 \"Alice\" \"admin\"]") "contains first row")
    (assert (string-contains? (.-output res) "[2 \"Bob\" \"developer\"]") "contains second row")
    (assert (>= (.-savings-percent res) 20.0) "savings >= 20%")
    true))

(df test-csv-quoted-fields-and-commas [] -> Bool
  :d "Verifies RFC 4180 quotes with embedded commas and escaped double quotes."
  (let [(csv-payload "id,name,location\n1,\"Smith, John\",\"New York, NY\"\n2,\"Alice \"\"The Boss\"\"\",London")
        (res (ct/csv-to-asn csv-payload))]
    (assert (.-success res) "quoted csv succeeds")
    (assert (string-contains? (.-output res) "\"Smith, John\"") "preserves comma inside quotes")
    (assert (string-contains? (.-output res) "\"New York, NY\"") "preserves location with comma")
    (assert (string-contains? (.-output res) "Alice \"The Boss\"") "decodes double quotes correctly")
    true))

(df test-tsv-tabs [] -> Bool
  :d "Verifies tab-separated TSV conversion to ASN table."
  (let [(tsv-payload "id\tname\tscore\n1\tAlice\t98.5\n2\tBob\t87.0")
        (res (ct/tsv-to-asn tsv-payload))]
    (assert (.-success res) "tsv succeeds")
    (assert (string-contains? (.-output res) "[:id :name :score]") "contains tsv headers")
    (assert (string-contains? (.-output res) "98.5") "contains float score 98.5")
    (assert (string-contains? (.-output res) "87.0") "contains float score 87.0")
    true))

(df test-csv-roundtrip [] -> Bool
  :d "Verifies ASN table serialization back to valid CSV format."
  (let [(asn-payload "([:id :name :role] [[1 \"Alice\" \"admin\"] [2 \"Smith, John\" \"developer\"]])")
        (res (ct/asn-to-csv asn-payload))]
    (assert (.-success res) "asn to csv succeeds")
    (assert (string-contains? (.-output res) "id,name,role") "contains csv header")
    (assert (string-contains? (.-output res) "1,Alice,admin") "contains unquoted row")
    (assert (string-contains? (.-output res) "\"Smith, John\"") "quotes row containing comma")
    true))

(df test-csv-negative [] -> Bool
  :d "Verifies rejection of empty or malformed inputs."
  (let [(r-empty-c (ct/csv-to-asn ""))
        (r-empty-a (ct/asn-to-csv ""))
        (r-bad-a (ct/asn-to-csv "not an asn"))]
    (assert (not (.-success r-empty-c)) "empty csv rejected")
    (assert (not (.-success r-empty-a)) "empty asn rejected")
    (assert (not (.-success r-bad-a)) "invalid asn root rejected")
    true))

(df run-tests [] -> Bool
  :d "Runs all CSV and TSV transpiler unit tests."
  (do
    (assert (test-csv-basic-table) "basic table")
    (assert (test-csv-quoted-fields-and-commas) "quoted fields and commas")
    (assert (test-tsv-tabs) "tsv tabs")
    (assert (test-csv-roundtrip) "roundtrip")
    (assert (test-csv-negative) "negative")
    true))
