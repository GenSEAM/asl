(module asl-codec/transpileTest
  :d "Unit verification test suite for Universal Format Transpiler"
  :x [testJsonToAsnObject testJsonToAsnArray testAsnToJson
      testYamlToAsn testAsnToYaml testHtmlToVdomAsn
      testVdomAsnToHtml testMeasureSavings testEmptyAndMalformed
      runTests]
  :i [(asl-codec/transpile :a tr)])

(df testJsonToAsnObject [] -> Bool
  :d "Tests JSON object conversion into compact ASN"
  (let [(res (tr/jsonToAsn "{\"model\": \"qwen\", \"tokens\": 1200, \"active\": true}"))
        (resNum (tr/jsonToAsn "{\"count\": -42, \"ratio\": 3.14, \"large\": 999999}"))
        (resStr (tr/jsonToAsn "{\"desc\": \"step 1: host, port 8080\", \"tags\": \"a, b: {c}\"}"))
        (resNest (tr/jsonToAsn "{\"user\": {\"name\": \"Alice\", \"role\": \"admin\"}, \"score\": 100}"))
        (resBad (tr/jsonToAsn "not an object"))]
    (assert (.-success res) "json to asn object succeeds")
    (assert (string-contains? (.-output res) "(:model \"qwen\"") "output contains model")
    (assert (>= (.-savingsPercent res) 30.0) "savings >= 30%")
    (assert (.-success resNum) "negative and float numbers succeed")
    (assert (string-contains? (.-output resNum) ":count -42") "contains negative int")
    (assert (string-contains? (.-output resNum) ":ratio 3.14") "contains float")
    (assert (.-success resStr) "strings with punctuation succeed")
    (assert (string-contains? (.-output resStr) "\"step 1: host, port 8080\"") "preserves punctuation inside string")
    (assert (.-success resNest) "nested objects succeed")
    (assert (string-contains? (.-output resNest) "(:user (:name \"Alice\" :role \"admin\") :score 100)") "nested record matches ASN")
    (assert (not (.-success resBad)) "reject non-object json root")
    true))

(df testJsonToAsnArray [] -> Bool
  :d "Tests JSON array conversion"
  (let [(res (tr/jsonToAsn "[1, 2, 3]"))
        (resObjs (tr/jsonToAsn "[{\"id\": 1}, {\"id\": 2}]"))
        (resMixed (tr/jsonToAsn "[1, \"two\", true, null, -5.5]"))
        (resBad (tr/jsonToAsn "not an array"))]
    (assert (.-success res) "json to asn array succeeds")
    (assert (string-contains? (.-output res) "[1 2 3]") "output contains array elements")
    (assert (.-success resObjs) "array of objects succeeds")
    (assert (string-contains? (.-output resObjs) "[(:id 1) (:id 2)]") "array of records matches ASN")
    (assert (.-success resMixed) "heterogeneous array succeeds")
    (assert (string-contains? (.-output resMixed) "[1 \"two\" true _ -5.5]") "mixed elements match ASN")
    (assert (not (.-success resBad)) "reject non-array json root")
    true))

(df testAsnToJson [] -> Bool
  :d "Tests round-trip ASN to JSON conversion"
  (let [(res1 (tr/asnToJson "(:model \"qwen\" :tokens 2048 :active true)"))
        (res2 (tr/asnToJson "[1 2 3]"))
        (resNeg (tr/asnToJson "(:desc \"step 1: test 2\" :count -42 :ratio 3.14 :active false :empty _)"))
        (resNest (tr/asnToJson "(:user (:name \"Alice\" :active true) :items [1 2 3])"))
        (resBad (tr/asnToJson "not an asn"))]
    (assert (.-success res1) "asn to json record succeeds")
    (assert (string-contains? (.-output res1) "\"model\": \"qwen\"") "contains model")
    (assert (string-contains? (.-output res1) "\"tokens\": 2048") "contains tokens")
    (assert (.-success res2) "asn to json vector succeeds")
    (assert (string-contains? (.-output res2) "[1, 2, 3]") "contains vector elements")
    (assert (.-success resNeg) "asn with negatives and strings succeeds")
    (assert (string-contains? (.-output resNeg) "\"desc\": \"step 1: test 2\"") "string content with digits not corrupted")
    (assert (string-contains? (.-output resNeg) "\"count\": -42") "negative number serialized")
    (assert (string-contains? (.-output resNeg) "\"ratio\": 3.14") "float serialized")
    (assert (string-contains? (.-output resNeg) "\"empty\": null") "nil serialized to null")
    (assert (.-success resNest) "nested asn record succeeds")
    (assert (string-contains? (.-output resNest) "\"user\": {\"name\": \"Alice\", \"active\": true}") "nested record serialized to json object")
    (assert (string-contains? (.-output resNest) "\"items\": [1, 2, 3]") "nested vector serialized to json array")
    (assert (not (.-success resBad)) "reject invalid asn root")
    true))

(df testYamlToAsn [] -> Bool
  :d "Tests YAML key-value hierarchy conversion"
  (let [(res (tr/yamlToAsn "model: qwen\ntokens: 1200"))
        (resBad (tr/yamlToAsn ""))]
    (assert (.-success res) "yaml to asn succeeds")
    (assert (string-contains? (.-output res) "(:model qwen") "output contains model")
    (assert (not (.-success resBad)) "reject empty yaml")
    true))

(df testAsnToYaml [] -> Bool
  :d "Tests ASN to YAML serialization"
  (let [(res (tr/asnToYaml "(:model qwen :tokens 1200)"))
        (resBad (tr/asnToYaml ""))]
    (assert (.-success res) "asn to yaml succeeds")
    (assert (string-contains? (.-output res) "model: qwen") "output contains model")
    (assert (not (.-success resBad)) "reject empty asn")
    true))

(df testHtmlToVdomAsn [] -> Bool
  :d "Tests HTML element and void tag conversion into VDOM S-expression"
  (let [(res (tr/htmlToVdomAsn "<div class=\"btn\"><img src=\"logo.png\"><span>Click</span></div>"))
        (resTbl (tr/htmlToVdomAsn "<table><thead><tr><th>Name</th></tr></thead><tbody><tr><td>Alice</td></tr></tbody></table>"))
        (resForm (tr/htmlToVdomAsn "<form action=\"/api\" method=\"post\"><label>User</label><input type=\"text\" name=\"user\" required/><button type=\"submit\" disabled>Send</button></form>"))
        (resMixed (tr/htmlToVdomAsn "<p>Hello <b>world</b>!</p>"))
        (resVoid (tr/htmlToVdomAsn "<img src=\"avatar.png\" alt=\"pic\"/><br/><hr/>"))
        (resBad (tr/htmlToVdomAsn "not an html"))
        (resEmpty (tr/htmlToVdomAsn ""))]
    (assert (.-success res) "html to vdom succeeds")
    (assert (string-contains? (.-output res) "(div (:class \"btn\")") "contains div class")
    (assert (string-contains? (.-output res) "(img (:src \"logo.png\"))") "contains img tag")
    (assert (.-success resTbl) "table hierarchy succeeds")
    (assert (string-contains? (.-output resTbl) "(table (thead") "contains table thead")
    (assert (string-contains? (.-output resTbl) "(td \"Alice\")") "contains table data")
    (assert (.-success resForm) "form and boolean attributes succeed")
    (assert (string-contains? (.-output resForm) ":action \"/api\"") "contains form action")
    (assert (string-contains? (.-output resForm) ":required true") "contains boolean attribute required")
    (assert (string-contains? (.-output resForm) ":disabled true") "contains boolean attribute disabled")
    (assert (.-success resMixed) "mixed inline elements succeed")
    (assert (string-contains? (.-output resMixed) "(b \"world\")") "contains inline bold element")
    (assert (.-success resVoid) "void elements without closing tags succeed")
    (assert (string-contains? (.-output resVoid) "(br)") "contains br void element")
    (assert (string-contains? (.-output resVoid) "(hr)") "contains hr void element")
    (assert (not (.-success resBad)) "reject non-html input")
    (assert (not (.-success resEmpty)) "reject empty input")
    true))

(df testVdomAsnToHtml [] -> Bool
  :d "Tests VDOM S-expression serialization to HTML"
  (let [(res (tr/vdomAsnToHtml "(div (:class \"btn\") (span \"Click\"))"))
        (resTbl (tr/vdomAsnToHtml "(table (tr (th \"A\") (th \"B\")) (tr (td \"1\") (td \"2\")))"))
        (resForm (tr/vdomAsnToHtml "(form (:action \"/api\") (input (:type \"text\")) (button (:disabled true) \"Submit\"))"))
        (resVoid (tr/vdomAsnToHtml "(div (img (:src \"logo.png\")) (br) (hr))"))
        (resBad (tr/vdomAsnToHtml "not a vdom"))
        (resEmpty (tr/vdomAsnToHtml ""))]
    (assert (.-success res) "vdom to html succeeds")
    (assert (string-contains? (.-output res) "<div class=\"btn\"><span>Click</span></div>") "output matches html")
    (assert (.-success resTbl) "table serialization succeeds")
    (assert (string-contains? (.-output resTbl) "<table><tr><th>A</th><th>B</th></tr>") "table markup matches")
    (assert (.-success resForm) "form with boolean attribute succeeds")
    (assert (string-contains? (.-output resForm) "<button disabled>Submit</button>") "boolean attribute rendered cleanly")
    (assert (.-success resVoid) "void elements rendered self-closing")
    (assert (string-contains? (.-output resVoid) "<br/>") "br self-closing")
    (assert (string-contains? (.-output resVoid) "<hr/>") "hr self-closing")
    (assert (not (.-success resBad)) "reject invalid vdom root")
    (assert (not (.-success resEmpty)) "reject empty input")
    true))

(df testMeasureSavings [] -> Bool
  :d "Tests token compaction measurement"
  (let [(payload "{\"package\": \"asl-harness\", \"version\": \"1.0.0\", \"description\": \"Universal Agent Harness with Cognitive Gateway\", \"active\": true}")
        (res (tr/measureTranspileSavings payload "json"))
        (resBad (tr/measureTranspileSavings "" "json"))]
    (assert (.-success res) "measure savings succeeds")
    (assert (>= (.-savingsPercent res) 45.0) "savings >= 45%")
    (assert (not (.-success resBad)) "reject empty payload in savings measurement")
    true))

(df testEmptyAndMalformed [] -> Bool
  :d "Tests graceful error handling on empty or invalid inputs"
  (let [(rEmpty (tr/jsonToAsn ""))
        (rMalformed (tr/htmlToVdomAsn "not an html"))
        (rValid (tr/jsonToAsn "{\"valid\": true}"))]
    (assert (.-success rValid) "valid json succeeds")
    (assert (not (.-success rEmpty)) "empty json rejected")
    (assert (not (.-success rMalformed)) "malformed html rejected")
    true))

(df runTests [] -> Bool
  :d "Runs all transpiler unit tests"
  (do
    (assert (testJsonToAsnObject) "json to asn object")
    (assert (testJsonToAsnArray) "json to asn array")
    (assert (testAsnToJson) "asn to json")
    (assert (testYamlToAsn) "yaml to asn")
    (assert (testAsnToYaml) "asn to yaml")
    (assert (testHtmlToVdomAsn) "html to vdom")
    (assert (testVdomAsnToHtml) "vdom to html")
    (assert (testMeasureSavings) "measure savings")
    (assert (testEmptyAndMalformed) "empty and malformed")
    true))
