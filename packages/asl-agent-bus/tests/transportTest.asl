(module aslBus/transportTest :x [testEnvelopeCreation testSessionLifecycle testSessionCounters testFrameHeaderFormatting testEnvelopeValidation runTests] :i [(transport :a tr)])

fn testEnvelopeCreation -> Bool
  (let [(env (tr/makeTransportEnvelope "env-101" (tr/frameRpcReq) "agent:planner" "agent:worker" 1 "(:batch (:out \"main.asl\"))" 1725700000))] (assert (= env.id "env-101") "Envelope id must match") (assert (= env.sender "agent:planner") "Sender must match") (assert (= env.target "agent:worker") "Target must match") (assert (= env.seq 1) "Sequence number must match 1") (assert (= env.payload "(:batch (:out \"main.asl\"))") "Payload must match") true)

fn testSessionLifecycle -> Bool
  (let [(s0 (tr/initTransportSession "sess-001" "node-peer-42")) (s1 (tr/sessionSetState s0 (tr/transportConnecting))) (s2 (tr/sessionSetState s1 (tr/transportConnected))) (s3 (tr/sessionSetState s2 (tr/transportClosed)))] (assert (not (tr/isSessionActive? s0)) "Initial session must not be active") (assert (not (tr/isSessionActive? s1)) "Connecting session must not be active") (assert (tr/isSessionActive? s2) "Connected session must be active") (assert (not (tr/isSessionActive? s3)) "Closed session must not be active") true)

fn testSessionCounters -> Bool
  (let [(s0 (tr/initTransportSession "sess-002" "node-peer-43")) (s1 (tr/sessionRecordSent s0 10)) (s2 (tr/sessionRecordSent s1 11)) (s3 (tr/sessionRecordReceived s2 12))] (assert (= s3.framesSent 2) "Frames sent must be 2") (assert (= s3.framesReceived 1) "Frames received must be 1") (assert (= s3.lastSeq 12) "Last sequence number must be 12") true)

fn testFrameHeaderFormatting -> Bool
  (let [(env (tr/makeTransportEnvelope "f-99" (tr/frameHeartbeat) "nodeA" "nodeB" 42 "ping" 1000)) (hdr (tr/formatFrameHeader env))] (assert (= hdr "FRAME:f-99:42:nodeA->nodeB") "Frame header must match FRAME:id:seq:sender->target format") (assert (not (stringContains? hdr "nodeB->nodeA")) "Frame header direction must not be reversed") (assert (not (stringContains? hdr "FRAME:f-99:0:")) "Frame header sequence must not be 0") true)

fn testEnvelopeValidation -> Bool
  (let [(valid (tr/makeTransportEnvelope "f-01" (tr/frameRpcRes) "src" "dst" 1 "ok" 500)) (invalidId (tr/makeTransportEnvelope "" (tr/frameRpcRes) "src" "dst" 1 "ok" 500)) (invalidSeq (tr/makeTransportEnvelope "f-02" (tr/frameRpcRes) "src" "dst" -1 "ok" 500))] (assert (tr/validateTransportEnvelope valid) "Valid envelope must pass validation") (assert (not (tr/validateTransportEnvelope invalidId)) "Empty id envelope must fail validation") (assert (not (tr/validateTransportEnvelope invalidSeq)) "Negative sequence envelope must fail validation") true)

fn runTests -> Bool
  (and (testEnvelopeCreation) (testSessionLifecycle) (testSessionCounters) (testFrameHeaderFormatting) (testEnvelopeValidation))
