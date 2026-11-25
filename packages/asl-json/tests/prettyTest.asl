(module asl-json/tests/prettyTest
  :x [runTests]
  :i [(asl-json/json :a j) (asl-json/pretty :a p)])

fn doc -> j/Json
  (j/jobj
    (list
      (pair "name" (j/jstr "Ada"))
      (pair "tags" (j/jarr (list (j/jstr "a") (j/jstr "b"))))
      (pair "meta" (j/jobj (list (pair "ok" (j/jbool true)) (pair "n" (j/jint 3)))))))

fn expected -> String
  (str "{\n"
       "  \"name\": \"Ada\",\n"
       "  \"tags\": [\n"
       "    \"a\",\n"
       "    \"b\"\n"
       "  ],\n"
       "  \"meta\": {\n"
       "    \"ok\": true,\n"
       "    \"n\": 3\n"
       "  }\n"
       "}")

fn testPrettyText -> Bool
  (do
    (assert (= (p/jsonPretty (doc) 2) (expected)) "pretty text at indent 2")
    true)

fn testRoundTrip -> Bool
  (match (j/jsonParse (p/jsonPretty (doc) 2))
    ((err _) (do (assert false "pretty output parses") true))
    ((ok v) (do (assert (= (p/jsonCanonical v) (p/jsonCanonical (doc))) "parse of pretty equals the document") true)))

fn testCanonical -> Bool
  (let [(a (j/jobj (list (pair "b" (j/jint 2)) (pair "a" (j/jint 1)))))
        (b (j/jobj (list (pair "a" (j/jint 1)) (pair "b" (j/jint 2)))))]
    (do
      (assert (= (p/jsonCanonical a) (p/jsonCanonical b)) "canonical ignores key order")
      (assert (= (p/jsonCanonical a) "{\"a\":1,\"b\":2}") "canonical text")
      true))

fn testInlineEmpty -> Bool
  (do
    (assert (= (p/jsonPretty (j/jobj (list)) 2) "{}") "empty object inline")
    (assert (= (p/jsonPretty (j/jarr (list)) 2) "[]") "empty array inline")
    true)

fn testLeafEscaping -> Bool
  (let [(s "a\"b\nc")]
    (do
      (assert (= (p/jsonPretty (j/jstr s) 2) (j/jsonEmit (j/jstr s))) "leaf uses jsonEmit")
      true))

fn ! runTests -> Bool
  (do
    (assert (testPrettyText) "pretty text")
    (assert (testRoundTrip) "round trip")
    (assert (testCanonical) "canonical")
    (assert (testInlineEmpty) "inline empty")
    (assert (testLeafEscaping) "leaf escaping")
    true)
