(module asl/agentLoop/tests/metricsUnbalancedWriteTest
  :x [runTests]
  :i [(asl/agentLoop/metrics :a m)])

; (:m :ref PAREN-LEON-JOURNAL :do "the journal rows Leon now writes for a rejected unbalanced write and the good write after it: the edit metrics class the first as syntax_unbalanced, the same class an error naming unbalanced gets")
fn rejectedReceipt -> String
  "(:receipt :id \\\"a1\\\" :op \\\"write\\\" :status :rejected :file \\\"bad.asl\\\" :error :ERR_TXN_ABORTED :message \\\"repair left 1 item(s); nothing staged (resend with :pick K.N)\\\" :line 5 :arrived \\\"    (+ y 2)\\\")"

fn okReceipt -> String
  "(:receipt :id \\\"b2\\\" :op \\\"write\\\" :status :ok :file \\\"bad.asl\\\")"

fn journal -> String
  (stringJoin (list
    "(:session :id \"s1\" :task \"write bad.asl\")"
    "(:turn 1 :reply \"(:step :op \\\"write\\\" :file \\\"bad.asl\\\" :content \\\"(module bad :x [f])\\\")\")"
    (str "(:turn 1 :observation \"" (rejectedReceipt) "\")")
    "(:turn 2 :reply \"(:step :op \\\"write\\\" :file \\\"bad.asl\\\" :content \\\"(module bad :x [f])\\\")\")"
    (str "(:turn 2 :observation \"" (okReceipt) "\")")
    "(:result :status :ok)") "\n")

fn testUnbalancedWriteClassed -> Bool
  (let [(res (m/analyzeEditJournals (list (pair "s1.journal" (journal)))))
        (k res.failuresByKind)]
    (do
      (assert (= res.totalFailures 1) (str "one failed attempt: " (stringFromInt64 res.totalFailures)))
      (assert (= k.syntaxUnbalanced 1) (str "the rejected write with 'repair left' is syntax_unbalanced, not semantic_other: " (stringFromInt64 k.syntaxUnbalanced)))
      (assert (= k.semanticOther 0) "and not semantic_other")
      true))

fn runTests -> Bool
  (do
    (assert (testUnbalancedWriteClassed) "testUnbalancedWriteClassed")
    true)
