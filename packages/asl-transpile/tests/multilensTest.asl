(module asl-transpile/multilensTest :x [testProjectLensHtml testProjectLensCss testProjectLensYaml testProjectLensJson testProjectLensToml testProjectLensDispatcher testEmitMultilensBundle testMultilensRefutations runTests] :i [(asl-transpile/multilens :a ml)])

fn sampleModelText -> Str
  (str "(:doc " ":meta (:title \"Service Dashboard\" :version \"1.0.0\" :lang \"en\") " ":styles (:vars [(:primary \"#007acc\") (:bg \"#ffffff\")] :rules [(:rule :selector \"body\" :props [(:margin \"0\") (:font-family \"sans-serif\")])]) " ":content (main (:class \"dashboard\") (h1 \"Service Metrics\")) " ":data (:metrics [(:id \"cpu\" :value 42) (:id \"mem\" :value 78)]) " ":config (:port 8080 :env \"production\"))")

fn testProjectLensHtml -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (res (ml/projectLensHtml m opts))] (assert res.success "projectLensHtml succeeds") (assert (= res.lens "html") "lens is html") (assert (stringContains? res.output "<!DOCTYPE html>") "contains DOCTYPE") (assert (stringContains? res.output "<title>Service Dashboard</title>") "contains title from meta") (assert (stringContains? res.output "<style>") "contains style tag") (assert (stringContains? res.output "--primary: #007acc;") "contains css custom property") (assert (stringContains? res.output "<main class=\"dashboard\">") "contains vdom content") (assert (stringContains? res.output "</html>") "ends with html tag") true)

fn testProjectLensCss -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (res (ml/projectLensCss m opts))] (assert res.success "projectLensCss succeeds") (assert (= res.lens "css") "lens is css") (assert (stringContains? res.output ":root {") "contains :root block") (assert (stringContains? res.output "--primary: #007acc;") "contains primary var") (assert (stringContains? res.output "body {") "contains body rule") (assert (stringContains? res.output "margin: 0;") "contains margin prop") true)

fn testProjectLensYaml -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (res (ml/projectLensYaml m opts))] (assert res.success "projectLensYaml succeeds") (assert (= res.lens "yaml") "lens is yaml") (assert (stringContains? res.output "port: 8080") "contains port config") (assert (stringContains? res.output "env: production") "contains env config") true)

fn testProjectLensJson -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (res (ml/projectLensJson m opts))] (assert res.success "projectLensJson succeeds") (assert (= res.lens "json") "lens is json") (assert (stringContains? res.output "\"metrics\"") "contains metrics in json") (assert (stringContains? res.output "\"cpu\"") "contains cpu id in json") true)

fn testProjectLensToml -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (res (ml/projectLensToml m opts))] (assert res.success "projectLensToml succeeds") (assert (= res.lens "toml") "lens is toml") (assert (stringContains? res.output "port = 8080") "contains port in toml") true)

fn testProjectLensDispatcher -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (rH (ml/projectLens "html" m opts)) (rC (ml/projectLens "css" m opts)) (rY (ml/projectLens "yaml" m opts)) (rJ (ml/projectLens "json" m opts)) (rT (ml/projectLens "toml" m opts)) (rBad (ml/projectLens "unknown" m opts))] (assert rH.success "dispatch html succeeds") (assert rC.success "dispatch css succeeds") (assert rY.success "dispatch yaml succeeds") (assert rJ.success "dispatch json succeeds") (assert rT.success "dispatch toml succeeds") (refute rBad.success "dispatch unknown fails") (assert (stringContains? rBad.errorMsg "Unsupported lens") "errorMsg on unknown lens") true)

fn testEmitMultilensBundle -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (bundle (ml/emitMultilensBundle m (list "html" "css" "yaml" "json" "toml") opts))] (assert bundle.success "bundle emission succeeds") (assert (> (stringLength bundle.html) 0) "bundle has html output") (assert (> (stringLength bundle.css) 0) "bundle has css output") (assert (> (stringLength bundle.yaml) 0) "bundle has yaml output") (assert (> (stringLength bundle.json) 0) "bundle has json output") (assert (> (stringLength bundle.toml) 0) "bundle has toml output") (assert (= (listLength bundle.artifacts) 5) "bundle has 5 artifacts") (let [(savings (ml/measureBundleSavings bundle))] (assert (>= savings 0.0) "bundle savings is non-negative") true))

fn testMultilensRefutations -> Bool
  (let [(m (ml/parseUnifiedModel (sampleModelText))) (opts (ml/defaultLensOptions)) (rBad (ml/projectLens "xml" m opts)) (bundle (ml/emitMultilensBundle m (list) opts))] (refute rBad.success "unknown lens must refute success") (refute (= rBad.output "<xml>") "unknown lens must not produce output") (refute (listEmpty? bundle.artifacts) "emitMultilensBundle must refute empty artifacts list") true)

fn runTests -> Bool
  (do (assert (testProjectLensHtml) "testProjectLensHtml") (assert (testProjectLensCss) "testProjectLensCss") (assert (testProjectLensYaml) "testProjectLensYaml") (assert (testProjectLensJson) "testProjectLensJson") (assert (testProjectLensToml) "testProjectLensToml") (assert (testProjectLensDispatcher) "testProjectLensDispatcher") (assert (testEmitMultilensBundle) "testEmitMultilensBundle") (assert (testMultilensRefutations) "testMultilensRefutations") true)
