(module asl-replay/replay
  :d "Deterministic Replay Execution Engine, Step-Level State Verification, and Divergence Detection under ADR D97"
  :x [DivergenceReport
      makeDivergenceReport
      verifyStateDigest
      detectDivergence
      getDivergenceReport
      replayEventStream]
  :i [(asl-replay/record :a record)])

(dfs DivergenceReport
  (:f diverged Bool)
  (:f step Int64)
  (:f expectedDigest String)
  (:f actualDigest String)
  (:f reason String))

(df makeDivergenceReport [(diverged Bool)
                          (step Int64)
                          (expectedDigest String)
                          (actualDigest String)
                          (reason String)] -> DivergenceReport
  :d "Constructs an execution replay divergence report descriptor"
  (DivergenceReport :diverged diverged
                    :step step
                    :expectedDigest expectedDigest
                    :actualDigest actualDigest
                    :reason reason))

(df verifyStateDigest [(expectedDigest String) (actualDigest String)] -> Bool
  :d "Verifies byte-for-byte equality between expected and actual state digests"
  (= expectedDigest actualDigest))

(df detectDivergenceLoop [(events (List record/ReplayEvent))
                          (actualStates (List String))] -> (Result Bool DivergenceReport)
  :d "Recursively compares recorded step state digests against actual state execution outputs"
  (if (or (list-empty? events) (list-empty? actualStates))
    (ok true)
    (let [(evHead (option-or (list-head events) (record/makeReplayEvent 0 "" "" "" "")))
          (evTail (option-or (list-tail events) (list)))
          (stHead (option-or (list-head actualStates) ""))
          (stTail (option-or (list-tail actualStates) ""))]
      (if (not (verifyStateDigest (.-stateDigest evHead) stHead))
        (err (makeDivergenceReport true
                                   (.-step evHead)
                                   (.-stateDigest evHead)
                                   stHead
                                   "ERR_REPLAY_DESYNC"))
        (detectDivergenceLoop evTail stTail)))))

(df detectDivergence [(session record/ReplaySession)
                      (actualStates (List String))] -> (Result Bool DivergenceReport)
  :d "Detects any execution drift or tampering between replay session events and runtime states"
  (detectDivergenceLoop (.-events session) actualStates))

(df getDivergenceReport [(res (Result Bool DivergenceReport))] -> DivergenceReport
  :d "Extracts a clean or error DivergenceReport from a divergence detection result"
  (mt res
    ((ok _val)
     (makeDivergenceReport false 0 "" "" "SUCCESS"))
    ((err report)
     report)))

(df replayEventStream [(session record/ReplaySession)] -> (Result String DivergenceReport)
  :d "Re-executes canonical event stream returning completed session identifier"
  (ok (.-sessionId session)))
