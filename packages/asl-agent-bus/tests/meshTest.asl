(module aslAgentBus/meshTest :x [testRoutingTableCreation testNodeRegistration testNodeLiveness testPacketRouting testTaskContractDelegation runTests] :i [(mesh :a m)])

fn testRoutingTableCreation -> Bool
  (let [(rt (m/createRoutingTable))] (do (assert (= (mapSize rt.nodes) 0) "Initial routing table must be empty") (assert (not (mapHas? rt.nodes "node:nonexistent")) "Empty routing table must not contain unregistered nodes") true))

fn testNodeRegistration -> Bool
  (let [(rt (m/createRoutingTable)) (node (m/MeshNode :id "node:scout" :role "scout" :tier "layer-1" :inboxSize 0 :isAlive true)) (rt2 (m/registerMeshNode rt node))] (do (assert (= (mapSize rt2.nodes) 1) "Routing table must contain 1 node after registration") (assert (m/isNodeAlive node) "Registered scout node must be alive") (assert (not (mapHas? rt2.nodes "node:unknown")) "Unregistered node must not be present in table") true))

fn testNodeLiveness -> Bool
  (let [(aliveNode (m/MeshNode :id "n1" :role "coder" :tier "layer-1" :inboxSize 0 :isAlive true)) (deadNode (m/MeshNode :id "n2" :role "planner" :tier "layer-2" :inboxSize 0 :isAlive false))] (do (assert (m/isNodeAlive aliveNode) "Alive node must return true") (assert (not (m/isNodeAlive deadNode)) "Dead node must return false") true))

fn testPacketRouting -> Bool
  (let [(rt (m/createRoutingTable)) (frame (m/routePacket rt "node:planner" "node:coder" "(:directive \"run-tests\")"))] (do (assert (stringContains? frame ":from \"node:planner\"") "Frame must contain originating node") (assert (stringContains? frame ":to \"node:coder\"") "Frame must contain destination node") (assert (not (stringContains? frame ":from \"node:coder\"")) "Origin node must not be inverted") (assert (not (stringContains? frame ":to \"node:planner\"")) "Destination node must not be inverted") true))

fn testTaskContractDelegation -> Bool
  (let [(c1 (m/makeTaskConstraint "C01" "Zero foreign code" "hard")) (c2 (m/makeTaskConstraint "C02" "Under 50ms latency" "soft")) (contract (m/makeTaskContract "TASK-100" "Implement mesh transport" (list c1 c2) (list "All tests pass" "Type check succeeds") "mesh" (list "scout" "coder" "reviewer"))) (dispatchStr (m/delegateContract contract "coder"))] (do (assert (= c1.id "C01") "Constraint id must match") (assert (= c2.rule "Under 50ms latency") "Constraint rule must match") (assert (= (listLength contract.constraints) 2) "Constraints count must be 2") (assert (= (listLength contract.acceptanceCriteria) 2) "Acceptance criteria count must be 2") (assert (= (listLength contract.assignedRoles) 3) "Assigned roles count must be 3") (assert (stringContains? dispatchStr ":task-id \"TASK-100\"") "Dispatch frame must include task id") (assert (stringContains? dispatchStr ":role \"coder\"") "Dispatch frame must include assigned role") (assert (stringContains? dispatchStr ":mode \"mesh\"") "Dispatch frame must include delegation mode") (assert (not (stringContains? dispatchStr ":role \"architect\"")) "Unassigned role must not appear in dispatch frame") (assert (not (stringContains? dispatchStr ":task-id \"TASK-999\"")) "Mismatched task id must not appear") true))

fn testAgentMeshNodeJoin -> Bool
  (let [(rt (m/createRoutingTable)) (node (m/AgentMeshNode :nodeId "node:supervisor" :role "auditor" :endpoint "in-proc" :status "online" :lastSeenEpoch 100)) (rt2 (m/joinMeshCluster rt node))] (assert (= (mapSize rt2.nodes) 1) "Routing table must contain registered agent mesh node") (assert (mapHas? rt2.nodes "node:supervisor") "Routing table must contain node:supervisor") true)

fn testCausalTrace -> Bool
  (let [(f1 (m/makeCausalTraceFrame "f1" "sess1" "target1" "node1" "root" 1 100 1000 "op" "target" "ok" "dig1")) (f2 (m/makeCausalTraceFrame "f2" "sess1" "target1" "node1" "dig1" 2 101 1001 "op" "target" "ok" "dig2")) (f3 (m/makeCausalTraceFrame "f3" "sess1" "target1" "node2" "root" 1 105 1005 "op" "target" "ok" "dig3")) (sorted (m/sortCausalFrames (list f2 f1 f3))) (merged (m/mergeMeshTraces (list (list f1 f2) (list f3))))] (assert (= (listLength sorted) 3) "Must sort all 3 frames") (assert (= (mt (listGet sorted 0) ((some f) f.frameId) ((none) "")) "f1") "First frame must be f1") (assert (= (mt (listGet sorted 1) ((some f) f.frameId) ((none) "")) "f3") "Second frame must be f3 based on clock") (assert (= (mt (listGet sorted 2) ((some f) f.frameId) ((none) "")) "f2") "Third frame must be f2") (assert (= (listLength merged.frames) 3) "Merged trace must have 3 frames") (assert (= (listLength merged.gaps) 0) "Merged trace must have 0 gaps") true)

fn testComputeTier -> Bool
  (let [(t1 (m/tier0Deterministic)) (t2 (m/tier1EdgeMediator)) (t3 (m/tier2Workhorse))] (assert (= (m/getComputeTierName t1) "tier-0-deterministic") "tier0 name matches") (assert (= (m/getComputeTierName t2) "tier-1-edge-mediator") "tier1 name matches") (assert (= (m/getComputeTierName t3) "tier-2-workhorse") "tier2 name matches") true)

fn runTests -> Bool
  (do (assert (testRoutingTableCreation)) (assert (testNodeRegistration)) (assert (testNodeLiveness)) (assert (testPacketRouting)) (assert (testTaskContractDelegation)) (assert (testAgentMeshNodeJoin)) (assert (testCausalTrace)) (assert (testComputeTier)) true)
