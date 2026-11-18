(module aslAgent/tests/absorbFileFormTest
  :x [runTests]
  :i [(aslAgent/exec :a ex)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)])

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "K4 and K10 (node2 2026-11-17): a pasted (:m ...) or other source-file form is answered as file text with the write step, not as an undeclared op, in a step and inside a txn; an :owns element of two paths joined by an escaped quote pair is those two paths")
fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn opOf form: String -> (List (Pair String c/KvVal))
  (optionOr (listHead (c/parseReply form)) (list))

fn prepText p: t/TxnPrep -> String
  (match p
    ((t/prepDone rec) (str "done " (t/serReceipt rec)))
    ((t/prepRun owns _ _ form) (str "run " (c/joinSep owns ",") " " form)))

fn ! runTests -> Bool
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        root (str base "/absorbFileFormTest-" (stringFromInt64 (nowNs)))
        made (ok? (dirCreate root))
        effects (list (pair "read" "local") (pair "write" "local") (pair "edit" "local"))
        env (ex/makeExecEnv root root "auto" (list "**") false "HEAD" (list) effects "" (list) 20000 60 (none) "absorbFileFormTest" (none))
        idf (fn [] "id1")
        snap (fn [s] false)
        onKeep (fn [a b n] true)
        run (fn [f d] (t/aslRun 0 "" ""))
        meta (ex/execOp! (opOf "(:m :ref X :do \"y\")") env (r/newProcs) idf snap onKeep run).rec
        doc (ex/execOp! (opOf "(:doc \"y\")") env (r/newProcs) idf snap onKeep run).rec
        frob (ex/execOp! (opOf "(:frob)") env (r/newProcs) idf snap onKeep run).rec
        inTxn (prepText (t/txnPrepare "(:txn :owns (\"a.txt\") (:m :ref X :do \"y\"))" (list "a.txt") root effects "r1" idf))
        joined (prepText (t/txnPrepare "(:txn :owns (\"a.txt\\\" \\\"b.txt\") (:write :file \"b.txt\" :content \"x\"))" (list "a.txt" "b.txt") root effects "r2" idf))
        plain (prepText (t/txnPrepare "(:txn :owns (\"a.txt\" \"b.txt\") (:write :file \"b.txt\" :content \"x\"))" (list "a.txt" "b.txt") root effects "r3" idf))
        cleaned (ok? (pathRemove root))]
    (do
      (assert made "the fixture root was made")
      (assert (and (= (strField meta "error") "ERR_EFFECT_UNDECLARED") (and (stringContains? (strField meta "message") "text from a source file") (stringContains? (strField meta "message") ":op \"write\""))) (str "a pasted (:m ...) form is answered as file text with the write step, got " (c/joinSep (map (fn [p] (str (pairFirst p) "=" (strField meta (pairFirst p)))) meta) " ")))
      (assert (stringContains? (strField doc "message") "text from a source file") (str "a pasted (:doc ...) form too, got " (strField doc "message")))
      (assert (= (strField frob "message") "Operation 'frob' not declared in effects registry") (str "any other unknown head keeps the registry answer, got " (strField frob "message")))
      (assert (and (stringStartsWith? inTxn "done ") (stringContains? inTxn "text from a source file")) (str "inside a txn the (:m ...) form is answered the same way, got " inTxn))
      (assert (stringStartsWith? joined "run a.txt,b.txt ") (str "an :owns element of two paths joined by an escaped quote pair is those two paths, got " joined))
      (assert (stringStartsWith? plain "run a.txt,b.txt ") (str "plain :owns stays as it was, got " plain))
      (assert cleaned "the fixture root was removed")
      true))
