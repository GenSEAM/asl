(module asl-replay/record  :x [ReplayEvent ReplaySession makeReplayEvent recordAgentEvent normalizeVolatileFields calculateEventDigest createReplaySession] :i [])

(schema ReplayEvent (:f step Int64) (:f kind String) (:f payload String) (:f stateDigest String) (:f volatileMetadata String))

(schema ReplaySession (:f sessionId String) (:f events (List ReplayEvent)) (:f initialDigest String))

fn makeReplayEvent step: Int64 kind: String payload: String stateDigest: String volatileMetadata: String -> ReplayEvent
  (ReplayEvent :step step :kind kind :payload payload :stateDigest stateDigest :volatileMetadata volatileMetadata)

fn recordAgentEvent step: Int64 kind: String payload: String stateDigest: String -> ReplayEvent
  (ReplayEvent :step step :kind kind :payload payload :stateDigest stateDigest :volatileMetadata "")

fn normalizeVolatileFields event: ReplayEvent -> String
  (stringConcat event.kind (stringConcat ":" (stringConcat event.payload (stringConcat ":" event.stateDigest))))

fn calculateEventDigest event: ReplayEvent -> String
  (let [(norm (normalizeVolatileFields event)) (len (stringLength norm))] (stringConcat "digest-" (stringConcat event.kind (stringConcat "-" (stringConcat (stringFromInt64 event.step) (stringConcat "-" (stringFromInt64 len)))))))

fn createReplaySession sessionId: String events: (List ReplayEvent) initialDigest: String -> ReplaySession
  (ReplaySession :sessionId sessionId :events events :initialDigest initialDigest)
