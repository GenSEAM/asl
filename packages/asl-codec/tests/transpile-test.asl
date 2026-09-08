(module asl-codec/transpile-test
  :d "Unit verification test suite for Universal Format Transpiler"
  :x [test-json-to-asn-object test-json-to-asn-array test-asn-to-json
      test-yaml-to-asn test-asn-to-yaml test-html-to-vdom-asn
      test-vdom-asn-to-html test-measure-savings test-empty-and-malformed
      run-tests]
  :i [(transpile :a tr)])

(df test-json-to-asn-object [] -> Bool
  :d "Tests JSON object conversion into compact ASN"
  (let [(res (tr/json-to-asn "{\"model\": \"qwen\", \"tokens\": 1200, \"active\": true}"))
        (res-bad (tr/json-to-asn "not an object"))]
    (assert (.-success res) "json to asn object succeeds")
    (assert (string-contains? (.-output res) "(:model \"qwen\"") "output contains model")
    (assert (>= (.-savings-percent res) 30.0) "savings >= 30%")
    (assert (not (.-success res-bad)) "reject non-object json root")
    true))

(df test-json-to-asn-array [] -> Bool
  :d "Tests JSON array conversion"
  (let [(res (tr/json-to-asn "[1, 2, 3]"))
        (res-bad (tr/json-to-asn "not an array"))]
    (assert (.-success res) "json to asn array succeeds")
    (assert (string-contains? (.-output res) "[1 2 3]") "output contains array elements")
    (assert (not (.-success res-bad)) "reject non-array json root")
    true))

(df test-asn-to-json [] -> Bool
  :d "Tests round-trip ASN to JSON conversion"
  (let [(res1 (tr/asn-to-json "(:model \"qwen\" :tokens 2048 :active true)"))
        (res2 (tr/asn-to-json "[1 2 3]"))
        (res-bad (tr/asn-to-json "not an asn"))]
    (assert (.-success res1) "asn to json record succeeds")
    (assert (string-contains? (.-output res1) "\"model\": \"qwen\"") "contains model")
    (assert (string-contains? (.-output res1) "\"tokens\": 2048") "contains tokens")
    (assert (.-success res2) "asn to json vector succeeds")
    (assert (string-contains? (.-output res2) "[1, 2, 3]") "contains vector elements")
    (assert (not (.-success res-bad)) "reject invalid asn root")
    true))

(df test-yaml-to-asn [] -> Bool
  :d "Tests YAML key-value hierarchy conversion"
  (let [(res (tr/yaml-to-asn "model: qwen\ntokens: 1200"))
        (res-bad (tr/yaml-to-asn ""))]
    (assert (.-success res) "yaml to asn succeeds")
    (assert (string-contains? (.-output res) "(:model qwen") "output contains model")
    (assert (not (.-success res-bad)) "reject empty yaml")
    true))

(df test-asn-to-yaml [] -> Bool
  :d "Tests ASN to YAML serialization"
  (let [(res (tr/asn-to-yaml "(:model qwen :tokens 1200)"))
        (res-bad (tr/asn-to-yaml ""))]
    (assert (.-success res) "asn to yaml succeeds")
    (assert (string-contains? (.-output res) "model: qwen") "output contains model")
    (assert (not (.-success res-bad)) "reject empty asn")
    true))

(df test-html-to-vdom-asn [] -> Bool
  :d "Tests HTML element and void tag conversion into VDOM S-expression"
  (let [(res (tr/html-to-vdom-asn "<div class=\"btn\"><img src=\"logo.png\"><span>Click</span></div>"))
        (res-bad (tr/html-to-vdom-asn "not an html"))]
    (assert (.-success res) "html to vdom succeeds")
    (assert (string-contains? (.-output res) "(div (:class \"btn\")") "contains div class")
    (assert (string-contains? (.-output res) "(img (:src \"logo.png\"))") "contains img tag")
    (assert (not (.-success res-bad)) "reject non-html input")
    true))

(df test-vdom-asn-to-html [] -> Bool
  :d "Tests VDOM S-expression serialization to HTML"
  (let [(res (tr/vdom-asn-to-html "(div (:class \"btn\") (span \"Click\"))"))
        (res-bad (tr/vdom-asn-to-html "not a vdom"))]
    (assert (.-success res) "vdom to html succeeds")
    (assert (string-contains? (.-output res) "<div class=\"btn\"><span>Click</span></div>") "output matches html")
    (assert (not (.-success res-bad)) "reject invalid vdom root")
    true))

(df test-measure-savings [] -> Bool
  :d "Tests token compaction measurement"
  (let [(payload "{\"package\": \"@genseam/harness\", \"version\": \"1.0.0\", \"description\": \"Universal Agent Harness with Cognitive Gateway\", \"active\": true}")
        (res (tr/measure-transpile-savings payload "json"))
        (res-bad (tr/measure-transpile-savings "" "json"))]
    (assert (.-success res) "measure savings succeeds")
    (assert (>= (.-savings-percent res) 45.0) "savings >= 45%")
    (assert (not (.-success res-bad)) "reject empty payload in savings measurement")
    true))

(df test-empty-and-malformed [] -> Bool
  :d "Tests graceful error handling on empty or invalid inputs"
  (let [(r-empty (tr/json-to-asn ""))
        (r-malformed (tr/html-to-vdom-asn "not an html"))
        (r-valid (tr/json-to-asn "{\"valid\": true}"))]
    (assert (.-success r-valid) "valid json succeeds")
    (assert (not (.-success r-empty)) "empty json rejected")
    (assert (not (.-success r-malformed)) "malformed html rejected")
    true))

(df run-tests [] -> Bool
  :d "Runs all transpiler unit tests"
  (do
    (assert (test-json-to-asn-object) "json to asn object")
    (assert (test-json-to-asn-array) "json to asn array")
    (assert (test-asn-to-json) "asn to json")
    (assert (test-yaml-to-asn) "yaml to asn")
    (assert (test-asn-to-yaml) "asn to yaml")
    (assert (test-html-to-vdom-asn) "html to vdom")
    (assert (test-vdom-asn-to-html) "vdom to html")
    (assert (test-measure-savings) "measure savings")
    (assert (test-empty-and-malformed) "empty and malformed")
    true))
