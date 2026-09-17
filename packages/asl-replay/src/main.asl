(module asl-replay
  :d "Pure AgentScript Deterministic Execution Replay and Canonical Event Streamer Substrate"
  :x [ReplayEvent
      ReplaySession
      makeReplayEvent
      recordAgentEvent
      normalizeVolatileFields
      calculateEventDigest
      createReplaySession
      DivergenceReport
      makeDivergenceReport
      verifyStateDigest
      detectDivergence
      getDivergenceReport
      replayEventStream]
  :i [(asl-replay/record :a record)
      (asl-replay/replay :a replay)])
