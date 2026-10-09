(module aslBus/presenceTest :x [testRoomCreateAndJoin testRoomPeerLookup testRoomLeave testNegotiationHandshakeAccept testNegotiationHandshakeDecline testFormatPresenceRoster testBridgeExternalDispatch testClaimPathAndRoster runPresenceTests runTests] :i [(presence :a p) (bridge :a b)])

fn testRoomCreateAndJoin -> Bool
  (let [(r0 (p/createSwarmRoom "refactor-matrix" "Polyglot Refactoring Swarm")) (p1 (p/SwarmPeer :agentId "claude-code-1" :role "coder" :room "refactor-matrix" :status (p/statusIdle) :capabilities (list "react-ast" "css-cascade") :lastPingEpoch 1757160000 :claims (list))) (p2 (p/SwarmPeer :agentId "gemini-architect" :role "planner" :room "refactor-matrix" :status (p/statusBusy) :capabilities (list "dag-planning") :lastPingEpoch 1757160000 :claims (list))) (r1 (p/joinSwarmRoom r0 p1)) (r2 (p/joinSwarmRoom r1 p2))] (assert (= (listLength (p/listRoomPeers r2)) 2) "Room peers length must be 2") (assert (= r2.roomName "refactor-matrix") "Room name must be refactor-matrix") true)

fn testRoomPeerLookup -> Bool
  (let [(r0 (p/createSwarmRoom "benchmarks" "Model Telemetry")) (p1 (p/SwarmPeer :agentId "slm-m1-worker" :role "benchmarker" :room "benchmarks" :status (p/statusListening) :capabilities (list "m1-telemetry") :lastPingEpoch 1757160000 :claims (list))) (r1 (p/joinSwarmRoom r0 p1)) (found (p/findPeerInRoom r1 "slm-m1-worker")) (missing (p/findPeerInRoom r1 "unknown-agent"))] (assert (some? found) "Found peer must be some") (assert (none? missing) "Missing peer must be none") (assert (mt found ((some p) (= p.role "benchmarker")) (_ false)) "Peer role must be benchmarker") true)

fn testRoomLeave -> Bool
  (let [(r0 (p/createSwarmRoom "eval-room" "SWE-bench")) (p1 (p/SwarmPeer :agentId "agent-a" :role "coder" :room "eval-room" :status (p/statusIdle) :capabilities (list) :lastPingEpoch 0 :claims (list))) (r1 (p/joinSwarmRoom r0 p1)) (r2 (p/leaveSwarmRoom r1 "agent-a"))] (assert (= (listLength (p/listRoomPeers r1)) 1) "Room peers before leave must be 1") (assert (= (listLength (p/listRoomPeers r2)) 0) "Room peers after leave must be 0") true)

fn testNegotiationHandshakeAccept -> Bool
  (let [(prop (p/proposeTask "coordinator-1" "claude-code-1" "batch-refactor-navbar" "bid-001")) (acc (p/acceptTask "bid-001" "claude-code-1" "coordinator-1" 15))] (assert (= prop.bidId "bid-001") "Bid ID must match bid-001") (assert (= acc.etaSeconds 15) "ETA seconds must be 15") (assert (mt acc.kind ((p/kindAccept) true) (_ false)) "Response kind must be kind-accept") true)

fn testNegotiationHandshakeDecline -> Bool
  (let [(dec (p/declineTask "bid-002" "busy-agent" "coordinator-1" "busy-running-integration-gates"))] (assert (= dec.bidId "bid-002") "Bid ID must match bid-002") (assert (= dec.reason "busy-running-integration-gates") "Reason must match") (assert (mt dec.kind ((p/kindDecline) true) (_ false)) "Response kind must be kind-decline") true)

fn testFormatPresenceRoster -> Bool
  (let [(r0 (p/createSwarmRoom "ops" "Cluster Operations")) (p1 (p/SwarmPeer :agentId "gate-keeper" :role "auditor" :room "ops" :status (p/statusIdle) :capabilities (list "gate.sh") :lastPingEpoch 0 :claims (list))) (r1 (p/joinSwarmRoom r0 p1)) (roster (p/formatPresenceRoster r1))] (assert (stringContains? roster "Swarm Room: ops") "Roster must contain room name") (assert (stringContains? roster "gate-keeper") "Roster must contain peer agent-id") (assert (stringContains? roster "auditor") "Roster must contain peer role") (assert (stringContains? roster "*idle*") "Roster must contain status idle") true)

fn testBridgeExternalDispatch -> Bool
  (let [(schema (b/formatExternalToolSchema)) (r0 (p/createSwarmRoom "bridge-room" "External Bridge")) (cmd (b/ExternalToolCommand :action "join-room" :agentId "claude-code" :roomName "bridge-room" :payload "()")) (res (b/dispatchExternalCommand r0 cmd))] (assert (stringContains? schema "asl_swarm_bus") "Schema must contain asl_swarm_bus") (assert (stringContains? res "Successfully joined room bridge-room") "Response must confirm joining room") true)

fn testClaimPathAndRoster -> Bool
  (let [(p0 (p/SwarmPeer :agentId "worker-1" :role "coder" :room "swarm" :status (p/statusIdle) :capabilities (list) :lastPingEpoch 100 :claims (list))) (p1 (p/claimPath p0 "engine/asl.c" (p/claimWrite) 100 60)) (p2 (p/claimPath p1 "asl/packages/asl-mem/src/vfs.asl" (p/claimRead) 100 60)) (p3 (p/releaseClaim p2 "engine/asl.c")) (room (p/joinSwarmRoom (p/createSwarmRoom "swarm" "testing") p2)) (roster (p/formatPresenceRoster room))] (assert (= (listLength p2.claims) 2) "p2 must have 2 claims") (assert (not (p/isClaimExpired? (optionOr (listHead p2.claims) (p/PathClaim :path "" :mode (p/claimRead) :holder "" :epoch 0 :ttlSeconds 0)) 120)) "claim must not be expired at 120") (assert (p/isClaimExpired? (optionOr (listHead p2.claims) (p/PathClaim :path "" :mode (p/claimRead) :holder "" :epoch 0 :ttlSeconds 0)) 170) "claim must be expired at 170") (assert (= (listLength p3.claims) 1) "p3 must have 1 claim after release") (assert (stringContains? roster "engine/asl.c") "roster must contain claimed path") true)

fn runTests -> Bool
  (and (testRoomCreateAndJoin) (testRoomPeerLookup) (testRoomLeave) (testNegotiationHandshakeAccept) (testNegotiationHandshakeDecline) (testFormatPresenceRoster) (testBridgeExternalDispatch) (testClaimPathAndRoster))

fn runPresenceTests -> Bool
  (runTests)
