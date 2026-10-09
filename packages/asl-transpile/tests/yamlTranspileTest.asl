(module asl-transpile/yamlTranspileTest :x [testYamlBasicMapping testYamlSequences testYamlNestedMapping testYamlListOfMaps testYamlCommentsAndQuotes testYamlRoundtrip testYamlNegative runTests] :i [(asl-transpile/yamlTranspile :a yt)])

fn testYamlBasicMapping -> Bool
  (let [(res (yt/yamlToAsn "name: qwen\ntokens: 1200\nactive: true"))] (assert res.success "basic yaml mapping succeeds") (assert (stringContains? res.output ":name qwen") "contains name") (assert (stringContains? res.output ":tokens 1200") "contains tokens") (assert (stringContains? res.output ":active true") "contains active") (assert (>= res.savingsPercent 20.0) "savings >= 20%") true)

fn testYamlSequences -> Bool
  (let [(res (yt/yamlToAsn "items:\n  - apple\n  - banana\n  - cherry"))] (assert res.success "yaml sequence succeeds") (assert (stringContains? res.output ":items [") "contains vector items") (assert (stringContains? res.output "apple") "contains apple") (assert (stringContains? res.output "banana") "contains banana") (assert (stringContains? res.output "cherry") "contains cherry") true)

fn testYamlNestedMapping -> Bool
  (let [(res (yt/yamlToAsn "server:\n  host: localhost\n  port: 8080"))] (assert res.success "nested mapping succeeds") (assert (stringContains? res.output ":server (") "contains nested server record") (assert (stringContains? res.output ":host localhost") "contains host") (assert (stringContains? res.output ":port 8080") "contains port") true)

fn testYamlListOfMaps -> Bool
  (let [(res (yt/yamlToAsn "tasks:\n  - id: 1\n  - id: 2"))] (assert res.success "yaml list of maps succeeds") (assert (stringContains? res.output ":tasks [") "contains tasks vector") (assert (stringContains? res.output "(:id 1)") "contains first map item") (assert (stringContains? res.output "(:id 2)") "contains second map item") true)

fn testYamlCommentsAndQuotes -> Bool
  (let [(res (yt/yamlToAsn "# Configuration file\ntitle: \"Hello: World\"\nendpoint: \"http://api.local\"\n# End of config"))] (assert res.success "commented yaml succeeds") (assert (stringContains? res.output "\"Hello: World\"") "preserves colon inside quoted string") (assert (stringContains? res.output "\"http://api.local\"") "preserves endpoint") (assert (not (stringContains? res.output "#")) "strips comment characters") true)

fn testYamlRoundtrip -> Bool
  (let [(res1 (yt/asnToYaml "(:name qwen :tokens 1200 :active true)")) (res2 (yt/asnToYaml "(:items [apple banana])")) (res3 (yt/asnToYaml "(:server (:host localhost :port 8080))"))] (assert res1.success "asn to yaml mapping succeeds") (assert (stringContains? res1.output "name: qwen") "output contains name") (assert (stringContains? res1.output "tokens: 1200") "output contains tokens") (assert res2.success "asn to yaml vector succeeds") (assert (stringContains? res2.output "items:") "contains items header") (assert (stringContains? res2.output "- apple") "contains sequence item apple") (assert (stringContains? res2.output "- banana") "contains sequence item banana") (assert res3.success "asn to yaml nested succeeds") (assert (stringContains? res3.output "server:") "contains server header") (assert (stringContains? res3.output "host: localhost") "contains nested host") true)

fn testYamlNegative -> Bool
  (let [(rEmptyY (yt/yamlToAsn "")) (rEmptyA (yt/asnToYaml "")) (rBadA (yt/asnToYaml "not an asn"))] (assert (not rEmptyY.success) "empty yaml rejected") (assert (not rEmptyA.success) "empty asn rejected") (assert (not rBadA.success) "invalid asn root rejected") true)

fn runTests -> Bool
  (do (assert (testYamlBasicMapping) "basic mapping") (assert (testYamlSequences) "sequences") (assert (testYamlNestedMapping) "nested mapping") (assert (testYamlListOfMaps) "list of maps") (assert (testYamlCommentsAndQuotes) "comments and quotes") (assert (testYamlRoundtrip) "roundtrip") (assert (testYamlNegative) "negative") true)
