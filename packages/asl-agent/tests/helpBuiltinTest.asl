(module aslAgent/tests/helpBuiltinTest
  :x [runTests]
  :i [(aslAgent/exec :a ex)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)])

; (:m :ref TOOLCARD-B :do "(:step :op help :name N) on a builtin answers the checker's signature line from the harness; an op name and an unknown name are not answered this way")

fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn helpOp name: String -> (List (Pair String c/KvVal))
  (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr "help")) (pair "name" (c/kvStr name)))

fn ! runTests -> Bool
  (let [env (ex/makeExecEnv "." "." "auto" (list) false "HEAD" (list) (list (pair "help" "local")) "" (list) 20000 60 (none) "helpBuiltinTest" (none))
        run (fn [name] (ex/execOp! (helpOp name) env (r/newProcs) (fn [] "id1") (fn [s] false) (fn [a b n] true) (fn [f d] (t/aslRun 0 "" ""))))
        split (run "stringSplit").rec
        opt (run "optionOr").rec
        opHelp (run "read").rec
        unknown (run "noSuchBuiltinName").rec
        receipt (ex/formatOpReceipt split 2000)]
    (do
      (assert (= (strField split "status") "ok") "help on a builtin answers ok")
      (assert (= (strField split "content") "stringSplit String String -> (List String)") (str "the answer is the checker's signature line: " (strField split "content")))
      (assert (stringStartsWith? (strField opt "content") "optionOr ") "another builtin answers its own line")
      (assert (stringContains? receipt ":content \"stringSplit String String -> (List String)\"") "the receipt shows the line")
      (assert (not (stringStartsWith? (strField opHelp "content") "read ")) "an op name keeps the op help, not a signature line")
      (assert (= (strField unknown "content") "") "an unknown name gets no signature line")
      true))
