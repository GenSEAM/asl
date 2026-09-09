(module asl-codec/yaml-transpile-test
  :d "Unit verification test suite for Indentation-Aware YAML <-> ASN Transpiler"
  :x [test-yaml-basic-mapping
      test-yaml-sequences
      test-yaml-nested-mapping
      test-yaml-list-of-maps
      test-yaml-comments-and-quotes
      test-yaml-roundtrip
      test-yaml-negative
      run-tests]
  :i [(yaml-transpile :a yt)])

(df test-yaml-basic-mapping [] -> Bool
  :d "Verifies basic key-value YAML mapping conversion."
  (let [(res (yt/yaml-to-asn "name: qwen\ntokens: 1200\nactive: true"))]
    (assert (.-success res) "basic yaml mapping succeeds")
    (assert (string-contains? (.-output res) ":name qwen") "contains name")
    (assert (string-contains? (.-output res) ":tokens 1200") "contains tokens")
    (assert (string-contains? (.-output res) ":active true") "contains active")
    (assert (>= (.-savings-percent res) 20.0) "savings >= 20%")
    true))

(df test-yaml-sequences [] -> Bool
  :d "Verifies YAML list/sequence conversion."
  (let [(res (yt/yaml-to-asn "items:\n  - apple\n  - banana\n  - cherry"))]
    (assert (.-success res) "yaml sequence succeeds")
    (assert (string-contains? (.-output res) ":items [") "contains vector items")
    (assert (string-contains? (.-output res) "apple") "contains apple")
    (assert (string-contains? (.-output res) "banana") "contains banana")
    (assert (string-contains? (.-output res) "cherry") "contains cherry")
    true))

(df test-yaml-nested-mapping [] -> Bool
  :d "Verifies nested YAML mapping hierarchy."
  (let [(res (yt/yaml-to-asn "server:\n  host: localhost\n  port: 8080"))]
    (assert (.-success res) "nested mapping succeeds")
    (assert (string-contains? (.-output res) ":server (") "contains nested server record")
    (assert (string-contains? (.-output res) ":host localhost") "contains host")
    (assert (string-contains? (.-output res) ":port 8080") "contains port")
    true))

(df test-yaml-list-of-maps [] -> Bool
  :d "Verifies YAML list containing mappings."
  (let [(res (yt/yaml-to-asn "tasks:\n  - id: 1\n  - id: 2"))]
    (assert (.-success res) "yaml list of maps succeeds")
    (assert (string-contains? (.-output res) ":tasks [") "contains tasks vector")
    (assert (string-contains? (.-output res) "(:id 1)") "contains first map item")
    (assert (string-contains? (.-output res) "(:id 2)") "contains second map item")
    true))

(df test-yaml-comments-and-quotes [] -> Bool
  :d "Verifies YAML comment stripping and quoted strings with colons."
  (let [(res (yt/yaml-to-asn "# Configuration file\ntitle: \"Hello: World\"\nendpoint: \"http://api.local\"\n# End of config"))]
    (assert (.-success res) "commented yaml succeeds")
    (assert (string-contains? (.-output res) "\"Hello: World\"") "preserves colon inside quoted string")
    (assert (string-contains? (.-output res) "\"http://api.local\"") "preserves endpoint")
    (assert (not (string-contains? (.-output res) "#")) "strips comment characters")
    true))

(df test-yaml-roundtrip [] -> Bool
  :d "Verifies ASN to YAML serialization and roundtrip fidelity."
  (let [(res1 (yt/asn-to-yaml "(:name qwen :tokens 1200 :active true)"))
        (res2 (yt/asn-to-yaml "(:items [apple banana])"))
        (res3 (yt/asn-to-yaml "(:server (:host localhost :port 8080))"))]
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

(df test-yaml-negative [] -> Bool
  :d "Verifies rejection of empty or malformed inputs."
  (let [(r-empty-y (yt/yaml-to-asn ""))
        (r-empty-a (yt/asn-to-yaml ""))
        (r-bad-a (yt/asn-to-yaml "not an asn"))]
    (assert (not (.-success r-empty-y)) "empty yaml rejected")
    (assert (not (.-success r-empty-a)) "empty asn rejected")
    (assert (not (.-success r-bad-a)) "invalid asn root rejected")
    true))

(df run-tests [] -> Bool
  :d "Runs all YAML transpiler unit tests."
  (do
    (assert (test-yaml-basic-mapping) "basic mapping")
    (assert (test-yaml-sequences) "sequences")
    (assert (test-yaml-nested-mapping) "nested mapping")
    (assert (test-yaml-list-of-maps) "list of maps")
    (assert (test-yaml-comments-and-quotes) "comments and quotes")
    (assert (test-yaml-roundtrip) "roundtrip")
    (assert (test-yaml-negative) "negative")
    true))
