(module aslAgent/tests/txnLinkedHintTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref TXN-CHECK-PER-EDIT :do "a new fn, its call and its export are three edits checked one by one, so any single edit is refused (unbound symbol, undefined export, not exported); the refusal now says to send all three as the inner subforms of one txn step, and one such txn passes")

fn lib -> String
  "(module lib\n  :x [foo])\n\nfn foo -> Int64\n  1\n"

fn ! recordedRun! tag: String replies: (List String) -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/lib.asl") (lib))
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        repo (gk/initGitRepo! root "txnLinked" "txn-linked@example.invalid")
        run (rk/runRecordedAgentLoopWithReplies! root tag replies (list "lib.asl") "add helper to lib" 6 8000)
        cleaned (pathRemove root)]
    run)

fn ! runTests -> Bool
  (let [single (list "(:step :op \"edit\" :file \"lib.asl\" :old \"fn foo -> Int64\\n  1\" :new \"fn foo -> Int64\\n  (helper)\")" "(:step :op \"done\")")
        all3 (list "(:step :op \"txn\" :owns (\"lib.asl\") (:edit :file \"lib.asl\" :old \"fn foo -> Int64\\n  1\" :new \"fn helper -> Int64\\n  2\\n\\nfn foo -> Int64\\n  (helper)\") (:edit :file \"lib.asl\" :old \":x [foo]\" :new \":x [foo helper]\"))" "(:step :op \"done\")")
        oneRun (recordedRun! "linkedOne" single)
        allRun (recordedRun! "linkedAll" all3)]
    (do
      (assert (stringContains? oneRun.journal "so one edit alone cannot pass: send them together as ONE") "an unbound-symbol refusal names the single txn step")
      (assert (not (stringContains? allRun.journal "ERR_")) "one txn holding definition, call and export passes the check together")
      true))
