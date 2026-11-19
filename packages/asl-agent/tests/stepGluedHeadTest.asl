(module aslAgent/tests/stepGluedHeadTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/turn :a tr)])

; (:m :ref LEON-STEP-BODY-LOST :do "node2 2026-11-17: the model glued the step head to its op, (:stepnop\"read\" :file ... :symbol ...), and the step was parsed with op stepnop; glued heads of a known op read as that op, and an unknown glued word stays as sent")
fn argOf op: (List (Pair String c/KvVal)) key: String -> String
  (match (c/dictGet op key) ((some (c/kvStr s)) s) (_ "?"))

fn ! ops reply: String -> String
  (stringJoin (map (fn [op] (argOf op "op")) (tr/turnReply reply (some (list))).facts.ops) " ")

fn ! firstArg reply: String key: String -> String
  (match (listHead (tr/turnReply reply (some (list))).facts.ops) ((some op) (argOf op key)) ((none) "?"))

fn ! runTests -> Bool
  (let [nop "(:stepnop\"read\" :file \"a.asl\" :symbol \"f\")\n(:step :op \"read\" :file \"a.asl\" :symbol \"g\")"
        opq "(:stepop\"read\" :file \"a.asl\")"
        colon "(:step:op\"outline\" :file \"a.asl\")"
        bare "(:stepread :file \"a.asl\" :start 1 :end 9)"
        unknown "(:stepfoo :file \"a.asl\")"]
    (do
      (assert (= (ops nop) "read read") (str "(:stepnop\"read\" ...) is a read step beside the plain one: " (ops nop)))
      (assert (= (firstArg nop "symbol") "f") "the glued step keeps its other fields")
      (assert (= (ops opq) "read") (str "(:stepop\"read\" ...) is a read step: " (ops opq)))
      (assert (= (ops colon) "outline") (str "(:step:op\"outline\" ...) is an outline step: " (ops colon)))
      (assert (and (= (ops bare) "read") (= (firstArg bare "file") "a.asl")) (str "(:stepread ...) is a read step: " (ops bare)))
      (assert (!= (ops unknown) "foo") (str "an unknown glued word is not read as an op: " (ops unknown)))
      true))
