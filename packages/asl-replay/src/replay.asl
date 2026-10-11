(module asl-replay/replay  :x [DivergenceReport makeDivergenceReport verifyStateDigest detectDivergence getDivergenceReport replayEventStream] :i [(asl-replay/record :a record)])

(schema DivergenceReport (:f diverged Bool) (:f step Int64) (:f expectedDigest String) (:f actualDigest String) (:f reason String))

fn makeDivergenceReport diverged: Bool step: Int64 expectedDigest: String actualDigest: String reason: String -> DivergenceReport
  (DivergenceReport :diverged diverged :step step :expectedDigest expectedDigest :actualDigest actualDigest :reason reason)

fn verifyStateDigest expectedDigest: String actualDigest: String -> Bool
  (= expectedDigest actualDigest)

fn detectDivergenceLoop events: (List record/ReplayEvent) actualStates: (List String) -> (Result Bool DivergenceReport)
  (if (or (listEmpty? events) (listEmpty? actualStates)) (ok true) (let [(evHead (optionOr (listHead events) (record/makeReplayEvent 0 "" "" "" ""))) (evTail (optionOr (listTail events) (list))) (stHead (optionOr (listHead actualStates) "")) (stTail (optionOr (listTail actualStates) (list)))] (if (not (verifyStateDigest evHead.stateDigest stHead)) (err (makeDivergenceReport true evHead.step evHead.stateDigest stHead "ERR_REPLAY_DESYNC")) (detectDivergenceLoop evTail stTail))))

fn detectDivergence session: record/ReplaySession actualStates: (List String) -> (Result Bool DivergenceReport)
  (detectDivergenceLoop session.events actualStates)

fn getDivergenceReport res: (Result Bool DivergenceReport) -> DivergenceReport
  (mt res ((ok _val) (makeDivergenceReport false 0 "" "" "SUCCESS")) ((err report) report))

fn replayEventStream session: record/ReplaySession -> (Result String DivergenceReport)
  (ok session.sessionId)
