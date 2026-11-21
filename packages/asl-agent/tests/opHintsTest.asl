(module aslAgent/tests/opHintsTest
  :x [runTests]
  :i [(aslAgent/exec :a ex)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)
      (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-OP-HINTS :do "OP-ALIASES: (:step :op test :path F), op synonyms and the key aliases of help are read as the registered op, a step naming no op answers ERR_NO_OP with its inferred form, the repeat key of a blocked path ignores ./ and the absolute spelling, and a run outside :root offers the same run rewritten root-relative")

fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn stepOp opName: String keys: (List (Pair String String)) -> (List (Pair String c/KvVal))
  (listAppend (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr opName)))
    (map (fn [p] (pair (pairFirst p) (c/kvStr (pairSecond p)))) keys))

fn noOp -> (List (Pair String c/KvVal))
  (list (pair "type" (c/kvStr "step")) (pair "file" (c/kvStr "src/a.asl")))

fn envAt root: String -> ex/ExecEnv
  (ex/makeExecEnv root root "auto" (list) false "HEAD" (list)
    (list (pair "test" "local") (pair "help" "local") (pair "tree" "local") (pair "read" "local") (pair "run" "local") (pair "step" "local")) "" (list) 20000 60 (none) "opHintsTest" (none))

fn ! exec! env: ex/ExecEnv procs: r/Procs op: (List (Pair String c/KvVal)) -> ex/ExecOut
  (ex/execOp! op env procs (fn [] "id1") (fn [s] false) (fn [a b n] true) (fn [f d] (t/aslRun 0 f "")))

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "opHints")
        sub (dirCreate (str root "/sub"))
        wrote (fileWrite (str root "/sub/f.txt") "x\n")
        env (envAt root)
        p0 (r/newProcs)
        viaPath (exec! env p0 (stepOp "test" (list (pair "path" "tests/t.asl")))).rec
        viaSyn (exec! env p0 (stepOp "tests" (list (pair "file" "tests/t.asl")))).rec
        viaFile (exec! env p0 (stepOp "test" (list (pair "file" "tests/t.asl")))).rec
        helpAbout (exec! env p0 (stepOp "help" (list (pair "about" "stringSplit")))).rec
        none (exec! env p0 (noOp)).rec
        h1 (exec! env p0 (stepOp "read" (list (pair "file" "./.asl/run/x.asn"))))
        h2 (exec! env h1.procs (stepOp "read" (list (pair "file" ".asl/run/x.asn"))))
        h3 (exec! env h2.procs (stepOp "read" (list (pair "file" (str root "/.asl/run/x.asn")))))
        okDot (exec! env p0 (stepOp "read" (list (pair "file" "./sub/f.txt")))).rec
        okAbs (exec! env p0 (stepOp "read" (list (pair "file" (str root "/sub/f.txt"))))).rec
        out (exec! env p0 (stepOp "run" (list (pair "argv" "touch /elsewhere/clone/sub/f.txt")))).rec
        unbal (t/txnRefusal "(:write :status :rejected :error ERR_UNBALANCED :file \"f.asl\" :balanced false :byte 42 :expected \")\")" "" "ERR_WRITE_FAILED" (some "a\nb\nc\n  (d"))
        mism (t/txnRefusal "(:write :status :rejected :error ERR_UNBALANCED :file \"f.asl\" :balanced false :byte 3 :expected \")\")" "" "ERR_WRITE_FAILED" (some "(a ]"))
        cleaned (ok? (pathRemove root))]
    (do
      (assert (!= (strField viaPath "status") "rejected") (str "(:step :op test :path F) is accepted: " (strField viaPath "status") " " (strField viaPath "error")))
      (assert (stringContains? (ex/formatOpReceipt viaPath 4000) ":out \"(:test :file \\\"tests/t.asl\\\")\"") (str "the form sent to asl carries :file from :path: " (ex/formatOpReceipt viaPath 4000)))
      (assert (stringContains? (strField viaPath "canonical") ":op \"test\" :file \"tests/t.asl\"") (str "the receipt teaches the canonical form: " (strField viaPath "canonical")))
      (assert (!= (strField viaSyn "status") "rejected") (str "op tests is read as test: " (strField viaSyn "error")))
      (assert (stringContains? (strField viaSyn "canonical") ":op \"test\"") "the synonym receipt names the registered op")
      (assert (= (strField viaFile "canonical") "") "the canonical spelling gets no canonical note")
      (assert (= (strField helpAbout "status") "ok") (str "(:step :op help :about N) answers the builtin: " (strField helpAbout "status")))
      (assert (= (strField none "error") "ERR_NO_OP") (str "a step without op answers ERR_NO_OP: " (strField none "error")))
      (assert (stringContains? (strField none "fix") ":op \"read\" :file \"src/a.asl\"") (str "ERR_NO_OP carries the form its keys imply: " (strField none "fix")))
      (assert (= (strField h1.rec "error") "ERR_HARNESS_PATH") "the first ./.asl/run path is refused")
      (assert (= (strField h2.rec "error") "ERR_HARNESS_PATH_REPEAT") (str "the same path without ./ is the repeat: " (strField h2.rec "error")))
      (assert (= (strField h3.rec "error") "ERR_HARNESS_PATH_REPEAT") (str "the absolute spelling inside :root is the repeat: " (strField h3.rec "error")))
      (assert (!= (strField okDot "error") "ERR_HARNESS_PATH") "./sub/f.txt in :root is not a harness path")
      (assert (!= (strField okAbs "error") "ERR_HARNESS_PATH") "an absolute path inside :root is not a harness path")
      (assert (= (strField out "error") "ERR_RUN_OUTSIDE_ROOT") (str "the outside path is refused: " (strField out "error") (strField out "message")))
      (assert (stringContains? (strField out "fix") "touch sub/f.txt") (str "the receipt offers the root-relative run: " (strField out "fix")))
      (assert (stringContains? (pairSecond unbal) "line 4 col 3") (str "the agent refusal names line and column of the unclosed opener: " (pairSecond unbal)))
      (assert (stringContains? (pairSecond mism) "line 1 col 4") (str "a mismatched closer is named at its own line and column: " (pairSecond mism)))
      (assert (not (listAny? (fn [n] (or (listContains? (ex/fileFormHeads) n) (listContains? (list "step" "evidence" "findings" "finding" "done" "escalate" "patch" "txn") n))) (ex/opSynonymNames))) "no op synonym is a form head the loop reads as text or data")
      (assert cleaned "the scratch root is removed")
      true))
