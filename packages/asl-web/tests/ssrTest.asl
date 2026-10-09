(module asl-web/tests/ssrTest
  :x [runTests RunTests testSerializeAndParseHydrationState testRenderDocumentHtml testScriptTagEscaping testDualPolarityRefutations]
  :i [(asl-web/ssr :a ssr)])

fn testSerializeAndParseHydrationState -> Bool
  (let [(stateAsn "(:app-state :user \"Alice\" :theme \"dark\" :counter 42)")
        (serialized (ssr/serializeHydrationState stateAsn))
        (parsedOpt (ssr/parseHydrationState serialized))]
    (assert (stringContains? serialized "__ASL_HYDRATION__") "serialized tag contains marker ID")
    (refute (not (stringContains? serialized "__ASL_HYDRATION__")) "marker ID refutes missing")
    (assert (some? parsedOpt) "hydration state parses back to some")
    (refute (none? parsedOpt) "hydration parse refutes none")
    (mt parsedOpt
      ((some val)
        (assert (= val stateAsn) "parsed state matches original ASN state")
        (refute (!= val stateAsn) "parsed state refutes mismatch"))
      ((none)
        (assert false "unreachable none")
        (refute true "unreachable none"))))
  true

fn testRenderDocumentHtml -> Bool
  (let [(title "My App")
        (body "<h1>Hello World</h1>")
        (state "(:counter 1)")
        (docHtml (ssr/renderDocumentHtml title body state))]
    (assert (stringContains? docHtml "<!DOCTYPE html>") "contains HTML5 DOCTYPE")
    (assert (stringContains? docHtml "<title>My App</title>") "contains document title")
    (assert (stringContains? docHtml "<h1>Hello World</h1>") "contains body markup")
    (assert (stringContains? docHtml "__ASL_HYDRATION__") "contains serialized hydration state")
    (refute (not (stringContains? docHtml "</html>")) "document closes with html tag"))
  true

fn testScriptTagEscaping -> Bool
  (let [(maliciousState "alert('evil');</script><script>exploit()</script>")
        (escaped (ssr/escapeScriptTag maliciousState))]
    (assert (stringContains? escaped "<\\/script>") "closing script tag is safely escaped")
    (refute (stringContains? escaped "</script>") "raw closing script tag refutes existence"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(invalidHtml "<div>No hydration block here</div>")
        (parseRes (ssr/parseHydrationState invalidHtml))]
    (assert (none? parseRes) "html without hydration block returns none")
    (refute (some? parseRes) "html without hydration block refutes some"))
  true

fn runTests -> Bool
  (do
    (assert (testSerializeAndParseHydrationState) "testSerializeAndParseHydrationState passed")
    (assert (testRenderDocumentHtml) "testRenderDocumentHtml passed")
    (assert (testScriptTagEscaping) "testScriptTagEscaping passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
