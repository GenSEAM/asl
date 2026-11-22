(module asl/examples/tests/jsonDemoTest
  :x [runTests]
  :i [(asl/examples/jsonDemo :a jsonDemo)])

fn runTests -> Bool
  (do
    (assert (= (jsonDemo/nameOf "{\"name\": \"Ada\"}") (some "Ada")) "nameOf string value")
    (assert (= (jsonDemo/nameOf "{\"other\": \"Ada\"}") none) "nameOf missing key")
    (assert (= (jsonDemo/nameOf "{\"name\": 42}") none) "nameOf non-string value")
    (assert (= (jsonDemo/nameOf "not json") none) "nameOf bad JSON")
    true)
