(module asl-transpile/csvTranspileTest :x [testCsvBasicTable testCsvQuotedFieldsAndCommas testTsvTabs testCsvRoundtrip testCsvNegative runTests] :i [(asl-transpile/csvTranspile :a ct)])

fn testCsvBasicTable -> Bool
  (let [(res (ct/csvToAsn "id,name,role\n1,Alice,admin\n2,Bob,developer"))] (assert res.success "basic csv succeeds") (assert (stringContains? res.output "[:id :name :role]") "contains header vector") (assert (stringContains? res.output "[1 \"Alice\" \"admin\"]") "contains first row") (assert (stringContains? res.output "[2 \"Bob\" \"developer\"]") "contains second row") (assert (>= res.savingsPercent 20.0) "savings >= 20%") true)

fn testCsvQuotedFieldsAndCommas -> Bool
  (let [(csvPayload "id,name,location\n1,\"Smith, John\",\"New York, NY\"\n2,\"Alice \"\"The Boss\"\"\",London") (res (ct/csvToAsn csvPayload))] (assert res.success "quoted csv succeeds") (assert (stringContains? res.output "\"Smith, John\"") "preserves comma inside quotes") (assert (stringContains? res.output "\"New York, NY\"") "preserves location with comma") (assert (stringContains? res.output "Alice \"The Boss\"") "decodes double quotes correctly") true)

fn testTsvTabs -> Bool
  (let [(tsvPayload "id\tname\tscore\n1\tAlice\t98.5\n2\tBob\t87.0") (res (ct/tsvToAsn tsvPayload))] (assert res.success "tsv succeeds") (assert (stringContains? res.output "[:id :name :score]") "contains tsv headers") (assert (stringContains? res.output "98.5") "contains float score 98.5") (assert (stringContains? res.output "87.0") "contains float score 87.0") true)

fn testCsvRoundtrip -> Bool
  (let [(asnPayload "([:id :name :role] [[1 \"Alice\" \"admin\"] [2 \"Smith, John\" \"developer\"]])") (res (ct/asnToCsv asnPayload))] (assert res.success "asn to csv succeeds") (assert (stringContains? res.output "id,name,role") "contains csv header") (assert (stringContains? res.output "1,Alice,admin") "contains unquoted row") (assert (stringContains? res.output "\"Smith, John\"") "quotes row containing comma") true)

fn testCsvNegative -> Bool
  (let [(rEmptyC (ct/csvToAsn "")) (rEmptyA (ct/asnToCsv "")) (rBadA (ct/asnToCsv "not an asn"))] (assert (not rEmptyC.success) "empty csv rejected") (assert (not rEmptyA.success) "empty asn rejected") (assert (not rBadA.success) "invalid asn root rejected") true)

fn runTests -> Bool
  (do (assert (testCsvBasicTable) "basic table") (assert (testCsvQuotedFieldsAndCommas) "quoted fields and commas") (assert (testTsvTabs) "tsv tabs") (assert (testCsvRoundtrip) "roundtrip") (assert (testCsvNegative) "negative") true)
