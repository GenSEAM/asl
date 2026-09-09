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
        (res-num (tr/json-to-asn "{\"count\": -42, \"ratio\": 3.14, \"large\": 999999}"))
        (res-str (tr/json-to-asn "{\"desc\": \"step 1: host, port 8080\", \"tags\": \"a, b: {c}\"}"))
        (res-nest (tr/json-to-asn "{\"user\": {\"name\": \"Alice\", \"role\": \"admin\"}, \"score\": 100}"))
        (res-bad (tr/json-to-asn "not an object"))]
    (assert (.-success res) "json to asn object succeeds")
    (assert (string-contains? (.-output res) "(:model \"qwen\"") "output contains model")
    (assert (>= (.-savings-percent res) 30.0) "savings >= 30%")
    (assert (.-success res-num) "negative and float numbers succeed")
    (assert (string-contains? (.-output res-num) ":count -42") "contains negative int")
    (assert (string-contains? (.-output res-num) ":ratio 3.14") "contains float")
    (assert (.-success res-str) "strings with punctuation succeed")
    (assert (string-contains? (.-output res-str) "\"step 1: host, port 8080\"") "preserves punctuation inside string")
    (assert (.-success res-nest) "nested objects succeed")
    (assert (string-contains? (.-output res-nest) "(:user (:name \"Alice\" :role \"admin\") :score 100)") "nested record matches ASN")
    (assert (not (.-success res-bad)) "reject non-object json root")
    true))

(df test-json-to-asn-array [] -> Bool
  :d "Tests JSON array conversion"
  (let [(res (tr/json-to-asn "[1, 2, 3]"))
        (res-objs (tr/json-to-asn "[{\"id\": 1}, {\"id\": 2}]"))
        (res-mixed (tr/json-to-asn "[1, \"two\", true, null, -5.5]"))
        (res-bad (tr/json-to-asn "not an array"))]
    (assert (.-success res) "json to asn array succeeds")
    (assert (string-contains? (.-output res) "[1 2 3]") "output contains array elements")
    (assert (.-success res-objs) "array of objects succeeds")
    (assert (string-contains? (.-output res-objs) "[(:id 1) (:id 2)]") "array of records matches ASN")
    (assert (.-success res-mixed) "heterogeneous array succeeds")
    (assert (string-contains? (.-output res-mixed) "[1 \"two\" true _ -5.5]") "mixed elements match ASN")
    (assert (not (.-success res-bad)) "reject non-array json root")
    true))

(df test-asn-to-json [] -> Bool
  :d "Tests round-trip ASN to JSON conversion"
  (let [(res1 (tr/asn-to-json "(:model \"qwen\" :tokens 2048 :active true)"))
        (res2 (tr/asn-to-json "[1 2 3]"))
        (res-neg (tr/asn-to-json "(:desc \"step 1: test 2\" :count -42 :ratio 3.14 :active false :empty _)"))
        (res-nest (tr/asn-to-json "(:user (:name \"Alice\" :active true) :items [1 2 3])"))
        (res-bad (tr/asn-to-json "not an asn"))]
    (assert (.-success res1) "asn to json record succeeds")
    (assert (string-contains? (.-output res1) "\"model\": \"qwen\"") "contains model")
    (assert (string-contains? (.-output res1) "\"tokens\": 2048") "contains tokens")
    (assert (.-success res2) "asn to json vector succeeds")
    (assert (string-contains? (.-output res2) "[1, 2, 3]") "contains vector elements")
    (assert (.-success res-neg) "asn with negatives and strings succeeds")
    (assert (string-contains? (.-output res-neg) "\"desc\": \"step 1: test 2\"") "string content with digits not corrupted")
    (assert (string-contains? (.-output res-neg) "\"count\": -42") "negative number serialized")
    (assert (string-contains? (.-output res-neg) "\"ratio\": 3.14") "float serialized")
    (assert (string-contains? (.-output res-neg) "\"empty\": null") "nil serialized to null")
    (assert (.-success res-nest) "nested asn record succeeds")
    (assert (string-contains? (.-output res-nest) "\"user\": {\"name\": \"Alice\", \"active\": true}") "nested record serialized to json object")
    (assert (string-contains? (.-output res-nest) "\"items\": [1, 2, 3]") "nested vector serialized to json array")
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
        (res-tbl (tr/html-to-vdom-asn "<table><thead><tr><th>Name</th></tr></thead><tbody><tr><td>Alice</td></tr></tbody></table>"))
        (res-form (tr/html-to-vdom-asn "<form action=\"/api\" method=\"post\"><label>User</label><input type=\"text\" name=\"user\" required/><button type=\"submit\" disabled>Send</button></form>"))
        (res-mixed (tr/html-to-vdom-asn "<p>Hello <b>world</b>!</p>"))
        (res-void (tr/html-to-vdom-asn "<img src=\"avatar.png\" alt=\"pic\"/><br/><hr/>"))
        (res-bad (tr/html-to-vdom-asn "not an html"))
        (res-empty (tr/html-to-vdom-asn ""))]
    (assert (.-success res) "html to vdom succeeds")
    (assert (string-contains? (.-output res) "(div (:class \"btn\")") "contains div class")
    (assert (string-contains? (.-output res) "(img (:src \"logo.png\"))") "contains img tag")
    (assert (.-success res-tbl) "table hierarchy succeeds")
    (assert (string-contains? (.-output res-tbl) "(table (thead") "contains table thead")
    (assert (string-contains? (.-output res-tbl) "(td \"Alice\")") "contains table data")
    (assert (.-success res-form) "form and boolean attributes succeed")
    (assert (string-contains? (.-output res-form) ":action \"/api\"") "contains form action")
    (assert (string-contains? (.-output res-form) ":required true") "contains boolean attribute required")
    (assert (string-contains? (.-output res-form) ":disabled true") "contains boolean attribute disabled")
    (assert (.-success res-mixed) "mixed inline elements succeed")
    (assert (string-contains? (.-output res-mixed) "(b \"world\")") "contains inline bold element")
    (assert (.-success res-void) "void elements without closing tags succeed")
    (assert (string-contains? (.-output res-void) "(br)") "contains br void element")
    (assert (string-contains? (.-output res-void) "(hr)") "contains hr void element")
    (assert (not (.-success res-bad)) "reject non-html input")
    (assert (not (.-success res-empty)) "reject empty input")
    true))

(df test-vdom-asn-to-html [] -> Bool
  :d "Tests VDOM S-expression serialization to HTML"
  (let [(res (tr/vdom-asn-to-html "(div (:class \"btn\") (span \"Click\"))"))
        (res-tbl (tr/vdom-asn-to-html "(table (tr (th \"A\") (th \"B\")) (tr (td \"1\") (td \"2\")))"))
        (res-form (tr/vdom-asn-to-html "(form (:action \"/api\") (input (:type \"text\")) (button (:disabled true) \"Submit\"))"))
        (res-void (tr/vdom-asn-to-html "(div (img (:src \"logo.png\")) (br) (hr))"))
        (res-bad (tr/vdom-asn-to-html "not a vdom"))
        (res-empty (tr/vdom-asn-to-html ""))]
    (assert (.-success res) "vdom to html succeeds")
    (assert (string-contains? (.-output res) "<div class=\"btn\"><span>Click</span></div>") "output matches html")
    (assert (.-success res-tbl) "table serialization succeeds")
    (assert (string-contains? (.-output res-tbl) "<table><tr><th>A</th><th>B</th></tr>") "table markup matches")
    (assert (.-success res-form) "form with boolean attribute succeeds")
    (assert (string-contains? (.-output res-form) "<button disabled>Submit</button>") "boolean attribute rendered cleanly")
    (assert (.-success res-void) "void elements rendered self-closing")
    (assert (string-contains? (.-output res-void) "<br/>") "br self-closing")
    (assert (string-contains? (.-output res-void) "<hr/>") "hr self-closing")
    (assert (not (.-success res-bad)) "reject invalid vdom root")
    (assert (not (.-success res-empty)) "reject empty input")
    true))

(df test-measure-savings [] -> Bool
  :d "Tests token compaction measurement"
  (let [(payload "{\"package\": \"asl-harness\", \"version\": \"1.0.0\", \"description\": \"Universal Agent Harness with Cognitive Gateway\", \"active\": true}")
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
