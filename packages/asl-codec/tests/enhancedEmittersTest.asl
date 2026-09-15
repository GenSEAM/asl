(module asl-codec/enhancedEmittersTest
  :d "Unit verification test suite for standalone HTML5 document synthesizer and deep YAML/TOML serialization"
  :x [testHtml5DocumentSynthesis
      testYamlStreamAndBlockScalars
      testTomlDocumentAndDottedPaths
      testEnhancedEmittersRefutations
      runTests]
  :i [(asl-codec/transpile :a tr)
      (asl-codec/yamlTranspile :a yt)
      (asl-codec/tomlTranspile :a tt)])

(df testHtml5DocumentSynthesis [] -> Bool
  :d "Verifies standalone HTML5 document synthesis with doctype, head, and embedded css."
  (let [(title "Microservice Dashboard")
        (css "body { margin: 0; background: #fafafa; }")
        (body "<main class=\"app\"><h1>Welcome</h1></main>")
        (docPretty (tr/renderHtml5Document title "en" css body false))
        (docMin (tr/renderHtml5Document title "en" css body true))]
    (assert (string-starts-with? docPretty "<!DOCTYPE html>") "pretty html starts with DOCTYPE")
    (assert (string-starts-with? docMin "<!DOCTYPE html>") "min html starts with DOCTYPE")
    (assert (string-contains? docPretty "<html lang=\"en\">") "pretty html has lang attribute")
    (assert (string-contains? docPretty "<title>Microservice Dashboard</title>") "pretty html has title")
    (assert (string-contains? docPretty "<style>") "pretty html embeds style tag")
    (assert (string-contains? docPretty css) "pretty html contains raw css without escaping")
    (assert (string-contains? docPretty "<body>") "pretty html has body tag")
    (assert (string-contains? docPretty body) "pretty html has inner body markup")
    (assert (string-ends-with? (string-trim docPretty) "</html>") "pretty html ends with </html>")
    (assert (string-ends-with? docMin "</html>") "min html ends with </html>")
    (refute (string-contains? docMin "\n") "min html has zero newlines")
    true))

(df testYamlStreamAndBlockScalars [] -> Bool
  :d "Verifies multi-document YAML streams and multiline block scalars."
  (let [(streamAsn "(:doc \"first\" :version 1) (:doc \"second\" :version 2)")
        (streamRes (yt/asnToYamlStream streamAsn))]
    (assert (.-success streamRes) "yaml stream succeeds")
    (assert (string-contains? (.-output streamRes) "---") "stream contains --- separator")
    (assert (string-contains? (.-output streamRes) "doc: first") "contains first doc key")
    (assert (string-contains? (.-output streamRes) "doc: second") "contains second doc key")
    (let [(multilineText "line 1\nline 2\nline 3")
          (blockOut (yt/formatYamlBlockScalar multilineText 1 false))]
      (assert (string-starts-with? blockOut "|") "literal block scalar starts with |")
      (assert (string-contains? blockOut "  line 1") "indented line 1")
      (assert (string-contains? blockOut "  line 2") "indented line 2")
      (assert (string-contains? blockOut "  line 3") "indented line 3")
      true)))

(df testTomlDocumentAndDottedPaths [] -> Bool
  :d "Verifies TOML document ordering and dotted table paths."
  (let [(p1 (tt/formatTomlTablePath "server" "network"))
        (p2 (tt/formatTomlTablePath "" "root"))]
    (assert (= p1 "server.network") "nested table path is server.network")
    (assert (= p2 "root") "empty parent produces child name")
    (let [(asnDoc "(:appName \"test\" :server (:host \"localhost\" :network (:timeout 30)) :databases [(:name \"main\")])")
          (docRes (tt/asnToTomlDocument asnDoc))]
      (assert (.-success docRes) "toml doc succeeds")
      (let [(out (.-output docRes))]
        (assert (string-contains? out "appName = \"test\"") "scalar key emitted")
        (assert (string-contains? out "[server]") "server section header emitted")
        (assert (string-contains? out "host = \"localhost\"") "server scalar emitted")
        (assert (string-contains? out "[server.network]") "nested section header emitted")
        (assert (string-contains? out "timeout = 30") "nested scalar emitted")
        (assert (string-contains? out "[[databases]]") "array of tables emitted")
        (let [(appIdx (string-index-of out "appName ="))
              (secIdx (string-index-of out "[server]"))]
          (mt appIdx
            ((some ai)
             (mt secIdx
               ((some si)
                (assert (< ai si) "root scalar is emitted before section header")
                true)
               ((none) false)))
            ((none) false)))))))

(df testEnhancedEmittersRefutations [] -> Bool
  :d "Dual-polarity refutations under D77 for enhanced emitters."
  (let [(doc (tr/renderHtml5Document "Title" "en" "" "<p>Test</p>" false))
        (rEmptyStream (yt/asnToYamlStream ""))
        (rEmptyToml (tt/asnToTomlDocument ""))]
    (refute (not (string-contains? doc "</html>")) "renderHtml5Document must not omit closing html tag")
    (refute (not (string-contains? doc "</body>")) "renderHtml5Document must not omit closing body tag")
    (refute (string-contains? doc "<style>") "renderHtml5Document must not emit style tag when css is empty")
    (refute (.-success rEmptyStream) "empty yaml stream rejected")
    (refute (.-success rEmptyToml) "empty toml document rejected")
    true))

(df runTests [] -> Bool
  :d "Runs all enhanced emitters unit tests."
  (do
    (assert (testHtml5DocumentSynthesis) "testHtml5DocumentSynthesis")
    (assert (testYamlStreamAndBlockScalars) "testYamlStreamAndBlockScalars")
    (assert (testTomlDocumentAndDottedPaths) "testTomlDocumentAndDottedPaths")
    (assert (testEnhancedEmittersRefutations) "testEnhancedEmittersRefutations")
    true))
