(module asl-transpile/tests/asnToTsvTest :x [runTests] :i [(asl-transpile/csvTranspile :a ct)])

; (:m :ref COVBATCH4 :do "asnToTsv writes tab separated rows and quotes only what needs it")
fn runTests -> Bool
  (let [(asn "([:id :name :role] [[1 \"Alice\" \"admin\"] [2 \"Smith, John\" \"developer\"]])")
        (res (ct/asnToTsv asn))
        (csv (ct/asnToCsv asn))
        (empty (ct/asnToTsv ""))
        (bad (ct/asnToTsv "not an asn"))]
    (do
      (assert res.success "a table converts")
      (assert (stringContains? res.output "id\tname\trole") "the header is tab separated")
      (assert (stringContains? res.output "1\tAlice\tadmin") "a row is tab separated")
      (assert (stringContains? res.output "2\tSmith, John\tdeveloper") "a comma needs no quotes in tsv")
      (assert (stringContains? csv.output "\"Smith, John\"") "the same comma is quoted in csv")
      (assert (not (stringContains? res.output ",developer")) "no comma separators in tsv")
      (assert (not empty.success) "empty input fails")
      (assert (not bad.success) "a non-table fails")
      (assert (= (ct/tsvToAsn "") (ct/csvToAsn "")) "tsvToAsn is csvToAsn")
      true))
