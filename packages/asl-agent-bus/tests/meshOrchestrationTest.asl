(module agent-bus/meshOrchestrationTest :x [testDaemonPeerRegistration testWorkspacePartitioning testBufferMutexAcquisition testMeshRoutingPacket testPeerHeartbeatTimeout runTests] :i [(mesh :a m)])

fn testDaemonPeerRegistration -> Bool
  (let [(reg (m/createPeerRegistry "genseam-hash")) (peer (m/makeDaemonPeer "node-1" "genseam-hash" 1234 "/tmp/asl_hub.sock" 8443 "orchestrator" 1773490000000)) (reg2 (m/registerDaemonPeer reg peer)) (found (m/findDaemonPeer reg2 "node-1")) (peerList (mapValues reg2.peers))] (assert (= (listLength peerList) 1) "Registry must have 1 peer") (assert (not (none? found)) "Peer must be found in registry") (mt found ((some p) (assert (= p.daemonId "node-1") "Found peer ID must match node-1")) ((none) (assert false "Peer must exist"))) true)

fn testWorkspacePartitioning -> Bool
  (let [(p1 (m/makeDaemonPeer "n1" "project-alpha" 100 "/tmp/s1.sock" 8441 "worker" 1773490000000)) (p2 (m/makeDaemonPeer "n2" "project-alpha" 200 "/tmp/s2.sock" 8442 "worker" 1773490000000)) (p3 (m/makeDaemonPeer "n3" "project-beta" 300 "/tmp/s3.sock" 8443 "worker" 1773490000000)) (peers (list p1 p2 p3)) (collisions (m/detectWorkspaceCollisions peers "project-alpha")) (emptyCollisions (m/detectWorkspaceCollisions peers "project-gamma"))] (assert (= (listLength collisions) 2) "Must detect 2 peers sharing project-alpha workspace") (refute (> (listLength emptyCollisions) 0) "Must not detect collisions for unused project-gamma") true)

fn testBufferMutexAcquisition -> Bool
  (let [(reg (m/createMutexRegistry)) (optReg (m/acquireBufferLease reg "src/main.asl" "agent-1" 1773490000000 3600 0))] (mt optReg ((some regLocked) (let [(isLocked (m/isBufferLocked? regLocked "src/main.asl" 1773490001000)) (regReleased (m/releaseBufferLease regLocked "src/main.asl" "agent-1")) (isUnlocked (not (m/isBufferLocked? regReleased "src/main.asl" 1773490001000)))] (assert isLocked "Buffer must be locked after lease acquisition") (assert isUnlocked "Buffer must be unlocked after lease release"))) ((none) (assert false "Acquiring unheld buffer lease must succeed"))) true)

fn testMeshRoutingPacket -> Bool
  (let [(table (m/createRoutingTable)) (node (m/MeshNode :id "remote-slm" :role "infer" :tier "tier-1" :inboxSize 0 :isAlive true)) (table2 (m/registerMeshNode table node)) (routed (m/routePacket table2 "local" "remote-slm" "payload"))] (assert (m/isNodeAlive node) "Node must be alive within threshold") (assert (stringContains? routed "remote-slm") "Packet must be successfully routed to alive node") true)

fn testPeerHeartbeatTimeout -> Bool
  (let [(reg (m/createPeerRegistry "ws-hash")) (deadPeer (m/makeDaemonPeer "dead-node" "ws-hash" 500 "/tmp/dead.sock" 8440 "worker" 1773490000000)) (reg2 (m/registerDaemonPeer reg deadPeer)) (regClean (m/evictDeadPeers reg2 1773490020000 15000)) (peerList (mapValues regClean.peers))] (assert (= (listLength peerList) 0) "Dead peer must be evicted after 15s timeout") (refute (mapHas? regClean.peers "dead-node") "Dead peer must not remain in registry") true)

fn runTests -> Bool
  (and (testDaemonPeerRegistration) (and (testWorkspacePartitioning) (and (testBufferMutexAcquisition) (and (testMeshRoutingPacket) (testPeerHeartbeatTimeout)))))
