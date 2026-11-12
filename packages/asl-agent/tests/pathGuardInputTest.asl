(module aslAgent/tests/pathGuardInputTest
  :x [runTests]
  :i [(aslAgent/exec :a ex) (aslAgent/runOps :a r) (aslAgent/core :a c) (aslAgent/txn :a t)])

fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn hasField rec: (List (Pair String ex/Val)) k: String -> Bool
  (some? (ex/recGet rec k))

fn blockedOp file: String -> (List (Pair String c/KvVal))
  (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr "read")) (pair "file" (c/kvStr file)))

fn runTests -> Bool
  (let [env (ex/makeExecEnv "." "." "auto" (list "asl/packages/asl-agent/src/exec.asl") false "HEAD" (list)
              (list (pair "read" "local")) "" (list) 20000 60 (none) "pathGuardInputTest" (none))
        idf (fn [] "id1")
        snap (fn [s] false)
        onKeep (fn [a b n] true)
        run (fn [f d] (t/aslRun 0 "" ""))
        out1 (ex/execOp! (blockedOp ".asl/run/agentLoop/journal.asn") env (r/newProcs) idf snap onKeep run)
        out2 (ex/execOp! (blockedOp ".asl/run/agentLoop/journal.asn") env out1.procs idf snap onKeep run)
        out3 (ex/execOp! (blockedOp ".asl/run/other.asn") env out2.procs idf snap onKeep run)
        rec1 out1.rec
        rec2 out2.rec
        rec3 out3.rec]
    (do
      (assert (= (strField rec1 "status") "rejected") "a harness path is refused")
      (assert (= (strField rec1 "error") "ERR_HARNESS_PATH") "the first refusal is ERR_HARNESS_PATH")
      (assert (= (strField rec1 "root") ".") "the refusal carries :root")
      (assert (hasField rec1 "owns") "the refusal carries :owns")
      (assert (stringContains? (strField rec1 "hint") ".asl/mem/work") "the refusal says task inputs live under .asl/mem/work")
      (assert (= (strField rec2 "error") "ERR_HARNESS_PATH_REPEAT") "an identical op on the same blocked path is refused ERR_HARNESS_PATH_REPEAT")
      (assert (= (strField rec2 "file") ".asl/run/agentLoop/journal.asn") "the repeat refusal names the same path")
      (assert (= (strField rec3 "error") "ERR_HARNESS_PATH") "a different blocked path is still ERR_HARNESS_PATH, not a repeat")
      (assert (listEmpty? out3.procs.ids) "blocked keys never enter the spawned-process id list")
      (assert (= (listLength out3.procs.blocked) 2) "each distinct blocked op|path is kept once in procs.blocked")
      true))
