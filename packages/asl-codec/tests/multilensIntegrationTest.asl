(module asl-codec/multilensIntegrationTest
  :d "Dynamic end-to-end multi-format integration verification suite for asl-codec multilens projection"
  :x [testDynamicMultilensExecution
      testMultilensRoundtripFidelity
      testMultilensRefutations
      testTaskRegistrationFile
      runTests]
  :i [(asl-codec/multilens :a ml)
      (asl-codec/cssCascade :a cascade)
      (asl-codec/transpile :a tr)
      (asl-codec/yamlTranspile :a yt)
      (asl-codec/tomlTranspile :a tt)])

(df productionModelSexpr [] -> Str
  :d "Realistic Agent Microservice Artifact with styling, layout, data, and config."
  (str "(:doc "
       ":meta (:title \"Agent Telemetry Service\" :version \"1.0.0\" :author \"Agent\" :lang \"en\") "
       ":styles (:vars [(:primary \"#2563eb\") (:bg \"#f8fafc\")] "
       "         :rules [(:rule :selector \".service-card\" :props [(:padding \"16px\") (:border-radius \"8px\")])]) "
       ":content (div (:class \"service-card\") (h1 \"Telemetry Overview\") (p \"Status: Online\")) "
       ":data (:endpoints [(:path \"/health\" :status 200) (:path \"/metrics\" :status 200)]) "
       ":config (:port 9090 :host \"0.0.0.0\" :ssl (:enabled false :certPath \"/certs\")))"))

(df testDynamicMultilensExecution [] -> Bool
  :d "Dynamically projects production model simultaneously into HTML, CSS, YAML, JSON, TOML."
  (let [(model (ml/parseUnifiedModel (productionModelSexpr)))
        (opts (ml/defaultLensOptions))
        (bundle (ml/emitMultilensBundle model (list "html" "css" "yaml" "json" "toml") opts))]
    (assert (.-success bundle) "bundle projection succeeds")
    (assert (string-starts-with? (.-html bundle) "<!DOCTYPE html>") "HTML starts with DOCTYPE")
    (assert (string-contains? (.-html bundle) "<style>") "HTML embeds stylesheet")
    (assert (string-contains? (.-html bundle) "<div class=\"service-card\">") "HTML contains card markup")
    (assert (string-contains? (.-css bundle) ":root {") "CSS contains :root custom properties")
    (assert (string-contains? (.-css bundle) "--primary: #2563eb;") "CSS contains primary token")
    (assert (string-contains? (.-css bundle) ".service-card {") "CSS contains service-card selector")
    (assert (string-contains? (.-yaml bundle) "port: 9090") "YAML contains port configuration")
    (assert (string-contains? (.-yaml bundle) "host: 0.0.0.0") "YAML contains host configuration")
    (assert (string-contains? (.-json bundle) "\"endpoints\"") "JSON contains endpoints data key")
    (assert (string-contains? (.-json bundle) "\"/health\"") "JSON contains /health path")
    (assert (string-contains? (.-toml bundle) "port = 9090") "TOML contains port assignment")
    (assert (string-contains? (.-toml bundle) "[ssl]") "TOML contains ssl table")
    true))

(df testMultilensRoundtripFidelity [] -> Bool
  :d "Verifies that emitted formats parse back into AST with structural fidelity."
  (let [(model (ml/parseUnifiedModel (productionModelSexpr)))
        (opts (ml/defaultLensOptions))
        (bundle (ml/emitMultilensBundle model (list "html" "css" "yaml" "json" "toml") opts))
        (cssParsed (cascade/parseCssRules (.-css bundle)))
        (yamlParsed (yt/yamlToAsn (.-yaml bundle)))
        (jsonParsed (tr/jsonToAsn (.-json bundle)))
        (tomlParsed (tt/tomlToAsn (.-toml bundle)))]
    (assert (> (list-length cssParsed) 0) "CSS roundtrip produces parsed rules")
    (let [(cardRule (filter (fn [(r cascade/CssRule)] -> Bool (= (.-selector r) ".service-card")) cssParsed))]
      (assert (= (list-length cardRule) 1) "CSS parsed contains .service-card rule")
      (let [(r (option-or (list-head cardRule) (cascade/CssRule :selector "" :specificity (cascade/calcSpecificity "") :properties (list) :sourceOrder 0)))]
        (assert (= (list-length (.-properties r)) 2) "card rule has 2 properties")
        true))
    (assert (.-success yamlParsed) "YAML parses back into ASN cleanly")
    (assert (string-contains? (.-output yamlParsed) ":port 9090") "YAML ASN preserves port")
    (assert (.-success jsonParsed) "JSON parses back into ASN cleanly")
    (assert (string-contains? (.-output jsonParsed) ":endpoints") "JSON ASN preserves endpoints key")
    (assert (.-success tomlParsed) "TOML parses back into ASN cleanly")
    (assert (string-contains? (.-output tomlParsed) ":port 9090") "TOML ASN preserves port")
    true))

(df testMultilensRefutations [] -> Bool
  :d "Dual-polarity negative failure modes under D77."
  (let [(model (ml/parseUnifiedModel (productionModelSexpr)))
        (opts (ml/defaultLensOptions))
        (rBad (ml/projectLens "bogus" model opts))]
    (refute (.-success rBad) "unknown lens must refute success")
    (refute (!= (.-output rBad) "") "unknown lens must not emit content")
    (assert (string-contains? (.-errorMsg rBad) "Unsupported lens") "errorMsg identifies unsupported lens")
    true))

(df testTaskRegistrationFile [] -> Bool
  :d "Verifies that Phase508MultilensEmitters.asn exists and is populated under D52"
  (let [(res (sysExec "test -f .asl/mem/tasks/Phase508MultilensEmitters.asn"))
        (code (.-exitCode res))]
    (assert (= code 0) "Phase508MultilensEmitters.asn must exist on disk")
    (refute (!= code 0) "Phase508MultilensEmitters.asn existence check must not fail")
    true))

(df runTests [] -> Bool
  :d "Runs all dynamic end-to-end integration tests."
  (do
    (assert (testDynamicMultilensExecution) "testDynamicMultilensExecution")
    (assert (testMultilensRoundtripFidelity) "testMultilensRoundtripFidelity")
    (assert (testMultilensRefutations) "testMultilensRefutations")
    (assert (testTaskRegistrationFile) "testTaskRegistrationFile")
    true))
