(module aslGateway/tests/leonWireAcceptanceTest
  :x [runTests]
  :i [(asl/agentLoop/providers :a pv)
      (asl-json/json :a j)])

fn field fields: (List (Pair String String)) key: String -> (Option String)
  (fold (fn [(found (Option String)) (p (Pair String String))] -> (Option String)
           (if (= (pairFirst p) key) (some (pairSecond p)) found))
        (none)
        fields)

fn numbered fields: (List (Pair String j/Json)) key: String -> String
  (mt (fold (fn [(found (Option j/Json)) (p (Pair String j/Json))] -> (Option j/Json)
               (if (= (pairFirst p) key) (some (pairSecond p)) found))
             (none)
             fields)
    ((some value) (pv/pyRepr value))
    ((none) "missing"))

fn runTests -> Bool
  (let [(reply "(:reply :model \"asl-role:coder\" :role \"coder\" :content (:step :ok) :finish \"stop\" :usage (:input 5730 :cached 4003 :output 310) :asl (:pool \"agy\" :queueWaitSec 0.25 :execSec 12.5))")
        (parsed (pv/parseAsnReply reply))
        (numbers (pv/asnNumbers reply))
        (served (pv/servedFields (list (pair "alias" (j/jstr "coder"))
                                       (pair "model" (j/jstr "gemini-3.8-flash"))
                                       (pair "effort" (j/jstr "high"))
                                       (pair "temperature" (j/jfloat 0.2))
                                       (pair "ignored" (j/jstr "discard")))))
        (bad (pv/parseAsnReply "(:reply :content \"unterminated"))]
    (mt parsed
      ((err _) false)
      ((ok hf)
        (mt numbers
          ((err _) false)
          ((ok nums)
            (do
              (assert (ok? parsed) "ASN reply form parses")
              (assert (= (pairFirst hf) "reply") "reply head is recognized")
              (assert (= (field (pairSecond hf) "model") (some "asl-role:coder")) "reply model string is unescaped")
              (assert (= (field (pairSecond hf) "role") (some "coder")) "reply role is retained")
              (assert (= (field (pairSecond hf) "content") (some "(:step :ok)")) "nested ASN content is retained")
              (assert (= (field (pairSecond hf) "finish") (some "stop")) "finish reason is retained")
              (assert (stringContains? (optionOr (field (pairSecond hf) "usage") "") ":input 5730") "usage ASN field is retained")
              (assert (stringContains? (optionOr (field (pairSecond hf) "asl") "") ":queueWaitSec 0.25") "timing ASN field is retained")
              (assert (= (numbered nums "input") "5730") "input token count is parsed")
              (assert (= (numbered nums "cached") "4003") "cached token count is parsed")
              (assert (= (numbered nums "output") "310") "output token count is parsed")
              (assert (= (field (pairSecond hf) "missing") none) "absent reply field remains absent")
              (assert (= (field (pairSecond hf) "pool") none) "nested pool field is not mistaken for a top-level field")
              (assert (some? served) "served model fields are recognized")
              (assert (stringContains? (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) (optionOr served (list))) "|") "coder") "served alias is preserved")
              (assert (stringContains? (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) (optionOr served (list))) "|") "gemini-3.8-flash") "served model is preserved")
              (assert (stringContains? (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) (optionOr served (list))) "|") "high") "served effort is preserved")
              (assert (not (stringContains? (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) (optionOr served (list))) "|") "ignored")) "unknown served fields are omitted")
              (assert (err? bad) "malformed ASN string is rejected")
              (assert (err? (pv/parseAsnReply "text")) "non-ASN reply is rejected")
              (assert (err? (pv/parseAsnReply "(:reply :content \"x\") trailing")) "trailing wire data is rejected")
              true))))))