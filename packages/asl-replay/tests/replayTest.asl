(module asl-replay/tests/replayTest :x [RunTests runTests] :i [(asl-replay/record :a record) (asl-replay/replay :a replay)])

fn testEventRecordingAndSerialization -> Bool
  (let [(e1 (record/recordAgentEvent 1 "input" "prompt" "digest1")) (norm (record/normalizeVolatileFields e1)) (d (record/calculateEventDigest e1)) (sess (record/createReplaySession "s1" (list e1) "init"))] (assert (= e1.step 1) "Event step is 1") (assert (> (stringLength norm) 0) "Normalized string is non-empty") (assert (> (stringLength d) 0) "Calculated digest is non-empty") (assert (= sess.sessionId "s1") "Session id matches s1") (refute (= e1.step 0) "Refutation: Step must not be 0") (refute (= d "") "Refutation: Digest must not be empty") true)

fn testReplayAndDivergenceDetection -> Bool
  (let [(matchTrue (replay/verifyStateDigest "hash" "hash")) (matchFalse (replay/verifyStateDigest "hash1" "hash2")) (e1 (record/recordAgentEvent 1 "tool" "op" "expected-hash")) (sess (record/createReplaySession "s1" (list e1) "init")) (cleanRes (replay/detectDivergence sess (list "expected-hash"))) (divRes (replay/detectDivergence sess (list "diverged-hash"))) (cleanRep (replay/getDivergenceReport cleanRes)) (divRep (replay/getDivergenceReport divRes))] (assert matchTrue "Matching digests match") (assert (not matchFalse) "Mismatched digests do not match") (assert (ok? cleanRes) "Clean detection succeeds") (assert (err? divRes) "Diverged detection errors") (assert (not cleanRep.diverged) "Clean report not diverged") (assert divRep.diverged "Diverged report diverged") (assert (= divRep.step 1) "Divergence at step 1") (refute (not matchTrue) "Refutation: Matching digests must succeed") (refute matchFalse "Refutation: Mismatched digests must fail") (refute (err? cleanRes) "Refutation: Clean detection must not error") true)

fn runTests -> Bool
  (let [(okRec (testEventRecordingAndSerialization)) (okRep (testReplayAndDivergenceDetection))] (and okRec okRep))

fn RunTests -> Bool
  (runTests)
