(module aslAgent/tests/txnSnapshotTest
  :x [runTests]
  :i [(aslAgent/main :a m)
      (aslAgent/core :a c)
      (aslHarness/tests/agentLoopRecorderKit :a rk)
      (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-TXN-SNAPSHOT :do "a (:step :op \"txn\" ...) whose inner edit targets an owned file never written earlier in the run was rejected with ERR_SNAPSHOT 'could not be snapshotted before the write; nothing was sent': liveExecOps! snapshotted only a top-level write/edit/delete target, so execTxn!'s snapAll found the inner target missing from writtenPaths. This is the regression: the txn receipt must be :status :ok and the inner edit must land on disk, for a file this run never wrote before")

fn initRepo! root: String -> Bool
  (and (ok? (fileWrite (str root "/task.txt") "before\n"))
    (ok? (fileWrite (str root "/other.txt") "other\n"))
    ; (:m :ref LEON-TXN-SNAPSHOT :do "initGitRepo! tracks only subject.txt, which this fixture never creates, so git add failed and the whole run was skipped; initGitRepoWith! tracks exactly the files the txn edits and reads")
    (gk/initGitRepoWith! root "txnSnapshotTest" "txn-snapshot-test@example.invalid" (list "task.txt" "other.txt")))

fn readFile root: String name: String -> String
  (resultOr (fileReadString (str root "/" name)) "")

fn txnOp form: String -> (List (Pair String c/KvVal))
  (list (pair "form" (c/kvStr form)))

fn runTests -> Bool
  (let [form "(:txn :owns (\"task.txt\") (:edit :file \"task.txt\" :old \"before\" :new \"after\") (:read :file \"other.txt\"))"
        targets (m/liveTxnTargets (txnOp form))
        root (rk/freshRecorderRoot! "txnSnapshot")
        ready (initRepo! root)
        reply (str "(:intent :deliver patch :why \"edit task.txt through one txn\")\n"
                "(:step :op \"txn\" :owns (\"task.txt\") (:edit :file \"task.txt\" :old \"before\" :new \"after\") (:read :file \"other.txt\"))\n"
                "(:step :op \"check\" :file \"task.txt\")\n"
                "(:done)")
        run (rk/runRecordedAgentLoopWithReplies! root "txnSnapshot" (list reply "(:done)") (list "task.txt")
              "Edit task.txt from before to after inside one txn, then finish." 3 8000)
        cleaned (ok? (pathRemove root))]
    (do
      (assert (= (listLength targets) 1)
        "liveTxnTargets keeps only the txn's write/edit targets, not its read target")
      (assert (listContains? targets "task.txt")
        "liveTxnTargets names the file its inner edit targets")
      (assert ready "the fixture repo with task.txt and other.txt is committed")
      (assert (stringContains? run.journal "(:turn 1 :reply")
        "turn 1's scripted txn reply is the one actually executed")
      (assert (not (stringContains? run.journal "ERR_SNAPSHOT"))
        "the txn is not rejected with ERR_SNAPSHOT for an owned file this run never wrote before")
      (assert (stringContains? run.journal ":op \\\"txn\\\" :status :ok")
        "the txn receipt is ok, so its inner edit was snapshotted before the write and sent")
      (assert (stringContains? run.journal ":staged true :replacements 1")
        "the inner edit replaced before with after and was flushed (an escalated run restores the tree afterwards, so the journal is the evidence)")
      (assert cleaned "the fixture root is removed")
      true))
