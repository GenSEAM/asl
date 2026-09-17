(module asl-replay/tests/replayTest
  :d "Unit test suite for deterministic execution replay and canonical event streaming"
  :x [RunTests runTests]
  :i [(asl-replay/record :a record)
      (asl-replay/replay :a replay)])

(df testEventRecordingAndSerialization [] -> Bool
  :d "Verifies event recording, field normalization, and session bundling"
  (let [(e1 (record/recordAgentEvent 1 "input" "prompt" "digest1"))
        (norm (record/normalizeVolatileFields e1))
        (d (record/calculateEventDigest e1))
        (sess (record/createReplaySession "s1" (list e1) "init"))]
    (assert (= (.-step e1) 1) "Event step is 1")
    (assert (> (string-length norm) 0) "Normalized string is non-empty")
    (assert (> (string-length d) 0) "Calculated digest is non-empty")
    (assert (= (.-sessionId sess) "s1") "Session id matches s1")
    (refute (= (.-step e1) 0) "Refutation: Step must not be 0")
    (refute (= d "") "Refutation: Digest must not be empty")
    true))

(df testReplayAndDivergenceDetection [] -> Bool
  :d "Verifies state verification, clean detection, and divergence flagging"
  (let [(matchTrue (replay/verifyStateDigest "hash" "hash"))
        (matchFalse (replay/verifyStateDigest "hash1" "hash2"))
        (e1 (record/recordAgentEvent 1 "tool" "op" "expected-hash"))
        (sess (record/createReplaySession "s1" (list e1) "init"))
        (cleanRes (replay/detectDivergence sess (list "expected-hash")))
        (divRes (replay/detectDivergence sess (list "diverged-hash")))
        (cleanRep (replay/getDivergenceReport cleanRes))
        (divRep (replay/getDivergenceReport divRes))]
    (assert matchTrue "Matching digests match")
    (assert (not matchFalse) "Mismatched digests do not match")
    (assert (is-ok? cleanRes) "Clean detection succeeds")
    (assert (is-err? divRes) "Diverged detection errors")
    (assert (not (.-diverged cleanRep)) "Clean report not diverged")
    (assert (.-diverged divRep) "Diverged report diverged")
    (assert (= (.-step divRep) 1) "Divergence at step 1")
    (refute (not matchTrue) "Refutation: Matching digests must succeed")
    (refute matchFalse "Refutation: Mismatched digests must fail")
    (refute (is-err? cleanRes) "Refutation: Clean detection must not error")
    true))

(df runTests [] -> Bool
  :d "Runs all asl-replay unit test suites"
  (let [(okRec (testEventRecordingAndSerialization))
        (okRep (testReplayAndDivergenceDetection))]
    (and okRec okRep)))

(df RunTests [] -> Bool
  :d "Export alias for runTests"
  (runTests))
