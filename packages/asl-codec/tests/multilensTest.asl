(module asl-codec/multilensTest
  :d "Unit verification test suite for Multilens Projection Engine and Dispatcher"
  :x [testProjectLensHtml
      testProjectLensCss
      testProjectLensYaml
      testProjectLensJson
      testProjectLensToml
      testProjectLensDispatcher
      testEmitMultilensBundle
      testMultilensRefutations
      runTests]
  :i [(asl-codec/multilens :a ml)])

(df sampleModelText [] -> Str
  (str "(:doc "
       ":meta (:title \"Service Dashboard\" :version \"1.0.0\" :lang \"en\") "
       ":styles (:vars [(:primary \"#007acc\") (:bg \"#ffffff\")] :rules [(:rule :selector \"body\" :props [(:margin \"0\") (:font-family \"sans-serif\")])]) "
       ":content (main (:class \"dashboard\") (h1 \"Service Metrics\")) "
       ":data (:metrics [(:id \"cpu\" :value 42) (:id \"mem\" :value 78)]) "
       ":config (:port 8080 :env \"production\"))"))

(df testProjectLensHtml [] -> Bool
  :d "Verifies projecting model through html lens."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (res (ml/projectLensHtml m opts))]
    (assert (.-success res) "projectLensHtml succeeds")
    (assert (= (.-lens res) "html") "lens is html")
    (assert (string-contains? (.-output res) "<!DOCTYPE html>") "contains DOCTYPE")
    (assert (string-contains? (.-output res) "<title>Service Dashboard</title>") "contains title from meta")
    (assert (string-contains? (.-output res) "<style>") "contains style tag")
    (assert (string-contains? (.-output res) "--primary: #007acc;") "contains css custom property")
    (assert (string-contains? (.-output res) "<main class=\"dashboard\">") "contains vdom content")
    (assert (string-contains? (.-output res) "</html>") "ends with html tag")
    true))

(df testProjectLensCss [] -> Bool
  :d "Verifies projecting model through css lens."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (res (ml/projectLensCss m opts))]
    (assert (.-success res) "projectLensCss succeeds")
    (assert (= (.-lens res) "css") "lens is css")
    (assert (string-contains? (.-output res) ":root {") "contains :root block")
    (assert (string-contains? (.-output res) "--primary: #007acc;") "contains primary var")
    (assert (string-contains? (.-output res) "body {") "contains body rule")
    (assert (string-contains? (.-output res) "margin: 0;") "contains margin prop")
    true))

(df testProjectLensYaml [] -> Bool
  :d "Verifies projecting model through yaml lens."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (res (ml/projectLensYaml m opts))]
    (assert (.-success res) "projectLensYaml succeeds")
    (assert (= (.-lens res) "yaml") "lens is yaml")
    (assert (string-contains? (.-output res) "port: 8080") "contains port config")
    (assert (string-contains? (.-output res) "env: production") "contains env config")
    true))

(df testProjectLensJson [] -> Bool
  :d "Verifies projecting model through json lens."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (res (ml/projectLensJson m opts))]
    (assert (.-success res) "projectLensJson succeeds")
    (assert (= (.-lens res) "json") "lens is json")
    (assert (string-contains? (.-output res) "\"metrics\"") "contains metrics in json")
    (assert (string-contains? (.-output res) "\"cpu\"") "contains cpu id in json")
    true))

(df testProjectLensToml [] -> Bool
  :d "Verifies projecting model through toml lens."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (res (ml/projectLensToml m opts))]
    (assert (.-success res) "projectLensToml succeeds")
    (assert (= (.-lens res) "toml") "lens is toml")
    (assert (string-contains? (.-output res) "port = 8080") "contains port in toml")
    true))

(df testProjectLensDispatcher [] -> Bool
  :d "Verifies polymorphic projectLens dispatcher."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (rH (ml/projectLens "html" m opts))
        (rC (ml/projectLens "css" m opts))
        (rY (ml/projectLens "yaml" m opts))
        (rJ (ml/projectLens "json" m opts))
        (rT (ml/projectLens "toml" m opts))
        (rBad (ml/projectLens "unknown" m opts))]
    (assert (.-success rH) "dispatch html succeeds")
    (assert (.-success rC) "dispatch css succeeds")
    (assert (.-success rY) "dispatch yaml succeeds")
    (assert (.-success rJ) "dispatch json succeeds")
    (assert (.-success rT) "dispatch toml succeeds")
    (refute (.-success rBad) "dispatch unknown fails")
    (assert (string-contains? (.-errorMsg rBad) "Unsupported lens") "errorMsg on unknown lens")
    true))

(df testEmitMultilensBundle [] -> Bool
  :d "Verifies emitMultilensBundle simultaneous projection and token measurement."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (bundle (ml/emitMultilensBundle m (list "html" "css" "yaml" "json" "toml") opts))]
    (assert (.-success bundle) "bundle emission succeeds")
    (assert (> (string-length (.-html bundle)) 0) "bundle has html output")
    (assert (> (string-length (.-css bundle)) 0) "bundle has css output")
    (assert (> (string-length (.-yaml bundle)) 0) "bundle has yaml output")
    (assert (> (string-length (.-json bundle)) 0) "bundle has json output")
    (assert (> (string-length (.-toml bundle)) 0) "bundle has toml output")
    (assert (= (list-length (.-artifacts bundle)) 5) "bundle has 5 artifacts")
    (let [(savings (ml/measureBundleSavings bundle))]
      (assert (>= savings 0.0) "bundle savings is non-negative")
      true)))

(df testMultilensRefutations [] -> Bool
  :d "Dual-polarity refutations under D77 for multilens projection."
  (let [(m (ml/parseUnifiedModel (sampleModelText)))
        (opts (ml/defaultLensOptions))
        (rBad (ml/projectLens "xml" m opts))
        (bundle (ml/emitMultilensBundle m (list) opts))]
    (refute (.-success rBad) "unknown lens must refute success")
    (refute (= (.-output rBad) "<xml>") "unknown lens must not produce output")
    (refute (list-empty? (.-artifacts bundle)) "emitMultilensBundle must refute empty artifacts list")
    true))

(df runTests [] -> Bool
  :d "Runs all Multilens projection engine unit tests."
  (do
    (assert (testProjectLensHtml) "testProjectLensHtml")
    (assert (testProjectLensCss) "testProjectLensCss")
    (assert (testProjectLensYaml) "testProjectLensYaml")
    (assert (testProjectLensJson) "testProjectLensJson")
    (assert (testProjectLensToml) "testProjectLensToml")
    (assert (testProjectLensDispatcher) "testProjectLensDispatcher")
    (assert (testEmitMultilensBundle) "testEmitMultilensBundle")
    (assert (testMultilensRefutations) "testMultilensRefutations")
    true))
