(module asl-replay/record
  :d "Deterministic Agent Event Streaming Recorder and Volatile Metadata Masking under ADR D97"
  :x [ReplayEvent
      ReplaySession
      makeReplayEvent
      recordAgentEvent
      normalizeVolatileFields
      calculateEventDigest
      createReplaySession]
  :i [])

(dfs ReplayEvent
  (:f step Int64)
  (:f kind String)
  (:f payload String)
  (:f stateDigest String)
  (:f volatileMetadata String))

(dfs ReplaySession
  (:f sessionId String)
  (:f events (List ReplayEvent))
  (:f initialDigest String))

(df makeReplayEvent [(step Int64)
                     (kind String)
                     (payload String)
                     (stateDigest String)
                     (volatileMetadata String)] -> ReplayEvent
  :d "Constructs a raw recorded replay event descriptor"
  (ReplayEvent :step step
               :kind kind
               :payload payload
               :stateDigest stateDigest
               :volatileMetadata volatileMetadata))

(df recordAgentEvent [(step Int64)
                      (kind String)
                      (payload String)
                      (stateDigest String)] -> ReplayEvent
  :d "Records an atomic agent execution step event"
  (ReplayEvent :step step
               :kind kind
               :payload payload
               :stateDigest stateDigest
               :volatileMetadata ""))

(df normalizeVolatileFields [(event ReplayEvent)] -> String
  :d "Produces canonical deterministic string representation masking non-deterministic volatile metadata"
  (str-concat (.-kind event)
              (str-concat ":"
                          (str-concat (.-payload event)
                                      (str-concat ":" (.-stateDigest event))))))

(df calculateEventDigest [(event ReplayEvent)] -> String
  :d "Calculates deterministic digest across normalized event contents"
  (let [(norm (normalizeVolatileFields event))
        (len (string-length norm))]
    (str-concat "digest-"
                (str-concat (.-kind event)
                            (str-concat "-"
                                        (str-concat (int-to-string (.-step event))
                                                    (str-concat "-" (int-to-string len))))))))

(df createReplaySession [(sessionId String)
                         (events (List ReplayEvent))
                         (initialDigest String)] -> ReplaySession
  :d "Constructs an immutable replay session descriptor"
  (ReplaySession :sessionId sessionId
                 :events events
                 :initialDigest initialDigest))
