(module asl-codec/transpile-test
  :d "Unit verification test suite for Universal Format Transpiler"
  :x [test-json-to-asn-object test-json-to-asn-array test-asn-to-json
      test-yaml-to-asn test-asn-to-yaml test-html-to-vdom-asn
      test-vdom-asn-to-html test-measure-savings test-empty-and-malformed
      run-tests]
  :i [(transpile :a tr)])

(df test-json-to-asn-object [] -> Bool
  :d "Tests JSON object conversion into compact ASN"
  (let [(res (tr/json-to-asn "{\"model\": \"qwen\", \"tokens\": 1200, \"active\": true}"))]
    (and (.-success res)
         (and (string-contains? (.-output res) "(:model \"qwen\"")
              (>= (.-savings-percent res) 30.0)))))

(df test-json-to-asn-array [] -> Bool
  :d "Tests JSON array conversion"
  (let [(res (tr/json-to-asn "[1, 2, 3]"))]
    (and (.-success res)
         (string-contains? (.-output res) "[1 2 3]"))))

(df test-asn-to-json [] -> Bool
  :d "Tests round-trip ASN to JSON conversion"
  (let [(res1 (tr/asn-to-json "(:model \"qwen\" :tokens 2048 :active true)"))
        (res2 (tr/asn-to-json "[1 2 3]"))]
    (and (and (.-success res1)
              (and (string-contains? (.-output res1) "\"model\": \"qwen\"")
                   (and (string-contains? (.-output res1) "\"tokens\": 2048")
                        (string-contains? (.-output res1) "\"active\": true"))))
         (and (.-success res2)
              (string-contains? (.-output res2) "[1, 2, 3]")))))


(df test-yaml-to-asn [] -> Bool
  :d "Tests YAML key-value hierarchy conversion"
  (let [(res (tr/yaml-to-asn "model: qwen\ntokens: 1200"))]
    (and (.-success res)
         (string-contains? (.-output res) "(:model qwen"))))

(df test-asn-to-yaml [] -> Bool
  :d "Tests ASN to YAML serialization"
  (let [(res (tr/asn-to-yaml "(:model qwen :tokens 1200)"))]
    (and (.-success res)
         (string-contains? (.-output res) "model: qwen"))))

(df test-html-to-vdom-asn [] -> Bool
  :d "Tests HTML element and void tag conversion into VDOM S-expression"
  (let [(res (tr/html-to-vdom-asn "<div class=\"btn\"><img src=\"logo.png\"><span>Click</span></div>"))]
    (and (.-success res)
         (and (string-contains? (.-output res) "(div (:class \"btn\")")
              (string-contains? (.-output res) "(img (:src \"logo.png\"))")))))

(df test-vdom-asn-to-html [] -> Bool
  :d "Tests VDOM S-expression serialization to HTML"
  (let [(res (tr/vdom-asn-to-html "(div (:class \"btn\") (span \"Click\"))"))]
    (and (.-success res)
         (string-contains? (.-output res) "<div class=\"btn\"><span>Click</span></div>"))))

(df test-measure-savings [] -> Bool
  :d "Tests token compaction measurement"
  (let [(payload "{\"package\": \"@genseam/harness\", \"version\": \"1.0.0\", \"description\": \"Universal Agent Harness with Cognitive Gateway\", \"active\": true}")
        (res (tr/measure-transpile-savings payload "json"))]
    (and (.-success res)
         (>= (.-savings-percent res) 45.0))))

(df test-empty-and-malformed [] -> Bool
  :d "Tests graceful error handling on empty or invalid inputs"
  (let [(r-empty (tr/json-to-asn ""))
        (r-malformed (tr/html-to-vdom-asn "not an html"))]
    (and (not (.-success r-empty))
         (not (.-success r-malformed)))))

(df run-tests [] -> Bool
  :d "Runs all transpiler unit tests"
  (do
    (assert (test-json-to-asn-object))
    (assert (test-json-to-asn-array))
    (assert (test-asn-to-json))
    (assert (test-yaml-to-asn))
    (assert (test-asn-to-yaml))
    (assert (test-html-to-vdom-asn))
    (assert (test-vdom-asn-to-html))
    (assert (test-measure-savings))
    (assert (test-empty-and-malformed))))
