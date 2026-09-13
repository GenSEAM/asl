(module asl-codec/yamlTranspileTest
  :d "Unit verification test suite for Indentation-Aware YAML <-> ASN Transpiler"
  :x [testYamlBasicMapping
      testYamlSequences
      testYamlNestedMapping
      testYamlListOfMaps
      testYamlCommentsAndQuotes
      testYamlRoundtrip
      testYamlNegative
      runTests]
  :i [(asl-codec/yamlTranspile :a yt)])

(df testYamlBasicMapping [] -> Bool
  :d "Verifies basic key-value YAML mapping conversion."
  (let [(res (yt/yamlToAsn "name: qwen\ntokens: 1200\nactive: true"))]
    (assert (.-success res) "basic yaml mapping succeeds")
    (assert (string-contains? (.-output res) ":name qwen") "contains name")
    (assert (string-contains? (.-output res) ":tokens 1200") "contains tokens")
    (assert (string-contains? (.-output res) ":active true") "contains active")
    (assert (>= (.-savingsPercent res) 20.0) "savings >= 20%")
    true))

(df testYamlSequences [] -> Bool
  :d "Verifies YAML list/sequence conversion."
  (let [(res (yt/yamlToAsn "items:\n  - apple\n  - banana\n  - cherry"))]
    (assert (.-success res) "yaml sequence succeeds")
    (assert (string-contains? (.-output res) ":items [") "contains vector items")
    (assert (string-contains? (.-output res) "apple") "contains apple")
    (assert (string-contains? (.-output res) "banana") "contains banana")
    (assert (string-contains? (.-output res) "cherry") "contains cherry")
    true))

(df testYamlNestedMapping [] -> Bool
  :d "Verifies nested YAML mapping hierarchy."
  (let [(res (yt/yamlToAsn "server:\n  host: localhost\n  port: 8080"))]
    (assert (.-success res) "nested mapping succeeds")
    (assert (string-contains? (.-output res) ":server (") "contains nested server record")
    (assert (string-contains? (.-output res) ":host localhost") "contains host")
    (assert (string-contains? (.-output res) ":port 8080") "contains port")
    true))

(df testYamlListOfMaps [] -> Bool
  :d "Verifies YAML list containing mappings."
  (let [(res (yt/yamlToAsn "tasks:\n  - id: 1\n  - id: 2"))]
    (assert (.-success res) "yaml list of maps succeeds")
    (assert (string-contains? (.-output res) ":tasks [") "contains tasks vector")
    (assert (string-contains? (.-output res) "(:id 1)") "contains first map item")
    (assert (string-contains? (.-output res) "(:id 2)") "contains second map item")
    true))

(df testYamlCommentsAndQuotes [] -> Bool
  :d "Verifies YAML comment stripping and quoted strings with colons."
  (let [(res (yt/yamlToAsn "# Configuration file\ntitle: \"Hello: World\"\nendpoint: \"http://api.local\"\n# End of config"))]
    (assert (.-success res) "commented yaml succeeds")
    (assert (string-contains? (.-output res) "\"Hello: World\"") "preserves colon inside quoted string")
    (assert (string-contains? (.-output res) "\"http://api.local\"") "preserves endpoint")
    (assert (not (string-contains? (.-output res) "#")) "strips comment characters")
    true))

(df testYamlRoundtrip [] -> Bool
  :d "Verifies ASN to YAML serialization and roundtrip fidelity."
  (let [(res1 (yt/asnToYaml "(:name qwen :tokens 1200 :active true)"))
        (res2 (yt/asnToYaml "(:items [apple banana])"))
        (res3 (yt/asnToYaml "(:server (:host localhost :port 8080))"))]
    (assert (.-success res1) "asn to yaml mapping succeeds")
    (assert (string-contains? (.-output res1) "name: qwen") "output contains name")
    (assert (string-contains? (.-output res1) "tokens: 1200") "output contains tokens")
    (assert (.-success res2) "asn to yaml vector succeeds")
    (assert (string-contains? (.-output res2) "items:") "contains items header")
    (assert (string-contains? (.-output res2) "- apple") "contains sequence item apple")
    (assert (string-contains? (.-output res2) "- banana") "contains sequence item banana")
    (assert (.-success res3) "asn to yaml nested succeeds")
    (assert (string-contains? (.-output res3) "server:") "contains server header")
    (assert (string-contains? (.-output res3) "host: localhost") "contains nested host")
    true))

(df testYamlNegative [] -> Bool
  :d "Verifies rejection of empty or malformed inputs."
  (let [(rEmptyY (yt/yamlToAsn ""))
        (rEmptyA (yt/asnToYaml ""))
        (rBadA (yt/asnToYaml "not an asn"))]
    (assert (not (.-success rEmptyY)) "empty yaml rejected")
    (assert (not (.-success rEmptyA)) "empty asn rejected")
    (assert (not (.-success rBadA)) "invalid asn root rejected")
    true))

(df runTests [] -> Bool
  :d "Runs all YAML transpiler unit tests."
  (do
    (assert (testYamlBasicMapping) "basic mapping")
    (assert (testYamlSequences) "sequences")
    (assert (testYamlNestedMapping) "nested mapping")
    (assert (testYamlListOfMaps) "list of maps")
    (assert (testYamlCommentsAndQuotes) "comments and quotes")
    (assert (testYamlRoundtrip) "roundtrip")
    (assert (testYamlNegative) "negative")
    true))
