(module aslAgent/tests/neutralHistoryTest
  :x [runTests]
  :i [(aslAgent/context :a ctx) (asl-json/json :a j)])

; (:m :ref CTX-HANDOFF :do "a run's calls cascade across models (130 of 155 node2 sessions on 2026-10-29 were served by 2 or more); a reply with one model's own markup (<think>, </think>, <tool_call>) kept in the transcript reached the next model, and 183 of 186 turns whose prompt carried it ended with no actionable op, against 589 of 8189 without. The rendered history keeps the ASN steps and receipts only")

fn histEntry turn: Int64 got: String -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr (str "sent" (stringFromInt64 turn)))) (pair "got" (j/jstr got))
    (pair "ops" (j/jstr "read")) (pair "files" (j/jstr "a.asl")) (pair "gates" (j/jstr ""))))

fn render history: (List j/Json) -> String
  (ctx/renderTranscriptBounded history 8 1500 50 16000)

fn ! runTests -> Bool
  (let [(thinkThenStep (histEntry 1 "I should read the file first.</think>(:step :op \"read\" :file \"a.asl\")\n(:receipt :id \"r1\" :op \"read\" :status :ok :file \"a.asl\" :content \"x\")"))
        (nativeCall (histEntry 2 "Let me look.<tool_call>read :file \"a.asl\"</tool_call>"))
        (thinkBlock (histEntry 3 "<think>plan the edit</think>\n(:step :op \"gate\")"))
        (receiptMarkup (histEntry 4 "(:step :op \"read\" :file \"p.asl\")\n(:receipt :id \"r4\" :op \"read\" :status :ok :file \"p.asl\" :content \"; a model may answer <tool_call>name</tool_call>\")"))
        (one (render (list thinkThenStep)))
        (two (render (list thinkThenStep nativeCall)))
        (three (render (list thinkThenStep nativeCall thinkBlock)))
        (four (render (list receiptMarkup)))]
    (do
      (assert (not (stringContains? one "</think>")) (str "a reply's reasoning up to </think> is not carried to the next model: " one))
      (assert (not (stringContains? one "I should read the file first")) "the reasoning text before </think> is dropped")
      (assert (stringContains? one "(:step :op \\\"read\\\" :file \\\"a.asl\\\")") "the ASN step after </think> is kept")
      (assert (stringContains? one ":content \\\"x\\\"") "the receipt of the turn is kept")
      (assert (not (stringContains? two "<tool_call>")) (str "a native tool-call block is not carried: " two))
      (assert (stringContains? two "(:replyDropped :turn 2") "a reply with no ASN form left is replaced by one neutral marker")
      (assert (not (stringContains? three "<think>")) "a <think> block is dropped")
      (assert (stringContains? three "(:step :op \\\"gate\\\")") "the step after a <think> block is kept")
      (assert (stringContains? four "<tool_call>name</tool_call>") "markup inside a receipt (file content the model asked for) is kept byte for byte")
      (assert (stringStartsWith? three two) "neutral rendering keeps the earlier turns' bytes as a prefix")
      true))
