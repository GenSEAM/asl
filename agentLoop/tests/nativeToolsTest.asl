(module asl/agentLoop/tests/nativeToolsTest
  :x [runTests]
  :i [(asl/agentLoop/nativeTools :a nt) (asl/agentLoop/core :a c) (asl-json/json :a j) (asl/agentLoop/providers :a pv)])

; (:m :ref PROTO-STUDY :do "native tool calling: op shapes become function schemas, and every tool_call reads back as the ASN form the text protocol carries, so parsing after the reply is unchanged")

fn shapes -> (List String)
  (list "(:step :op \"read\" :file f [:symbol name] [:start n :end m])"
        "(:step :op \"gate\" [:n i])"
        "(:step :op \"edit\" :file f :old :raw|s :new :raw|s)"
        "(:txn :owns (f ...) ...)"
        "(:done [:commit s])"
        "(:step :op \"diff\")")

fn call name: String args: String -> j/Json
  (j/jobj (list (pair "id" (j/jstr "c1")) (pair "type" (j/jstr "function"))
    (pair "function" (j/jobj (list (pair "name" (j/jstr name)) (pair "arguments" (j/jstr args)))))))

fn testSpecs -> Bool
  (let [specs (nt/toolSpecs (shapes))
        text (j/jsonEmit (j/jarr specs))
        read (nt/shapeTool (c/firstOf (shapes)))]
    (do (assert (= (listLength specs) 5) "five simple shapes become tools; the nested txn shape is not offered")
        (assert (stringContains? text "\"name\":\"diff\"") "a shape with no keys ends its name at the op, not at the closing paren")
        (assert (stringContains? text "\"name\":\"read\"") "a step op keeps its op name")
        (assert (stringContains? text "\"name\":\"done\"") "a terminal head becomes a tool named by its head")
        (assert (stringContains? text "\"start\":{\"type\":\"integer\"}") "an n placeholder is an integer")
        (assert (stringContains? text "\"required\":[\"file\"]") "only keys outside brackets are required")
        (assert (match read ((some t) (= (listLength t.params) 4)) ((none) false)) "read has file, symbol, start and end")
        (assert (stringContains? (j/jsonEmit (nt/stepToolSpec)) "\"required\":[\"form\"]") "the single step tool takes one form string")
        (assert (nt/validTools? "ops") "ops is a valid value")
        (assert (not (nt/validTools? "all")) "an unknown value is refused")
        true))

fn testCalls -> Bool
  (let [read (nt/callForm "read" "{\"file\":\"src/a.asl\",\"symbol\":\"f\",\"start\":3}")
        gate (nt/callForm "gate" "{}")
        done (nt/callForm "done" "{}")
        edit (nt/callForm "edit" "{\"file\":\"a.asl\",\"old\":\"x \\\"y\\\"\",\"new\":\"z\"}")
        step (nt/callForm "step" "{\"form\":\"(:step :op \\\"gate\\\")\"}")
        both (nt/callsText "" (list (call "read" "{\"file\":\"a.asl\"}") (call "gate" "")))
        none (nt/callsText "(:done)" (list))]
    (do (assert (= read "(:step :op \"read\" :file \"src/a.asl\" :symbol \"f\" :start 3)") "a read call is the read step")
        (assert (= gate "(:step :op \"gate\")") "empty arguments give the bare step")
        (assert (= done "(:done)") "done is the terminal form, not a step")
        (assert (stringStartsWith? edit "(:step :op \"edit\" :file \"a.asl\" :old :raw :new \"z\")\n```\nx \"y\"\n```") "a quoted string goes out as a raw block")
        (assert (= step "(:step :op \"gate\")") "the step tool carries the form text itself")
        (assert (= both "(:step :op \"read\" :file \"a.asl\")\n(:step :op \"gate\")") "calls keep their order, one form per line")
        (assert (= none "(:done)") "no calls leaves the text content as the reply")
        true))

fn replyOf body: String -> String
  (match (pairFirst (pv/readJsonReply body))
    ((ok (some t)) t)
    ((ok (none)) "<none>")
    ((err e) (str "<err " (pv/errorCode e) ">")))

; (:m :do "the provider side: a JSON reply whose message has tool_calls and null content is the forms of the calls, a text reply is unchanged, and a call offering tools asks for JSON instead of the ASN wire")
fn testProvider -> Bool
  (let [withCalls "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"file\\\":\\\"a.asl\\\"}\"}}]}}]}"
        textOnly "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"(:done)\"}}]}"
        conf (pv/curlConfig "http://127.0.0.1:1/v1" "{}" (pv/acceptHeader (list (nt/stepToolSpec))) "10" true)
        confAsn (pv/curlConfig "http://127.0.0.1:1/v1" "{}" (pv/acceptHeader (list)) "10" true)]
    (do (assert (= (replyOf withCalls) "(:step :op \"read\" :file \"a.asl\")") "a tool call with null content is the read step, not an empty reply")
        (assert (= (replyOf textOnly) "(:done)") "a text reply is unchanged")
        (assert (stringContains? conf "Accept: application/json") "a call offering tools asks for JSON")
        (assert (not (stringContains? conf "asn+sexpr")) "and not also for the ASN wire")
        (assert (stringContains? confAsn "Accept: application/asn+sexpr") "no tools keeps the ASN wire")
        true))

fn runTests -> Bool
  (and (testSpecs) (and (testCalls) (testProvider)))
