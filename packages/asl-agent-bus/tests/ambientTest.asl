(module aslAgentBus/ambientTest :x [testAmbientFrameCreation testAmbientFrameValidation testAmbientFrameTokenEconomy testDaemonPeerRegistration testWorkspaceCollisionDetection testBufferLeaseLifecycle testDeadPeersEviction runTests] :i [(ambient :a amb) (mesh :a m)])

fn testAmbientFrameCreation -> Bool
  (let [(frame (amb/createAmbientFrame "d-751f1272" 0.05 (list "buf-01" "buf-02") 1757160000))] (assert (= frame.peerId "d-751f1272")) (assert (= frame.load 0.05)) (assert (= (listLength frame.claimed) 2)) (assert (= frame.ts 1757160000)) (assert (amb/validateAmbientFrame frame)) true)

fn testAmbientFrameValidation -> Bool
  (let [(validFrame (amb/createAmbientFrame "d-active" 0.5 (list) 100)) (badEmptyId (amb/createAmbientFrame "" 0.1 (list) 100)) (badNegLoad (amb/createAmbientFrame "d-1" -0.1 (list) 100)) (badHighLoad (amb/createAmbientFrame "d-1" 1.5 (list) 100)) (badNegTs (amb/createAmbientFrame "d-1" 0.5 (list) -10))] (assert (amb/validateAmbientFrame validFrame)) (assert (not (amb/validateAmbientFrame badEmptyId))) (assert (not (amb/validateAmbientFrame badNegLoad))) (assert (not (amb/validateAmbientFrame badHighLoad))) (assert (not (amb/validateAmbientFrame badNegTs))) true)

fn testAmbientFrameTokenEconomy -> Bool
  (let [(frame (amb/createAmbientFrame "d-751f1272" 0.05 (list "buf-01" "buf-02") 1757160000)) (encoded (amb/encodeAmbientAsn frame)) (emptyFrame (amb/createAmbientFrame "d-idle" 0.0 (list) 1000)) (emptyEncoded (amb/encodeAmbientAsn emptyFrame))] (assert (stringContains? encoded "(:ambient :peer-id \"d-751f1272\"")) (assert (stringContains? encoded ":load 0.05")) (assert (stringContains? encoded ":claimed [\"buf-01\" \"buf-02\"]")) (assert (stringContains? encoded ":ts 1757160000")) (assert (stringContains? emptyEncoded ":claimed []")) (assert (< (stringLength encoded) 200)) (assert (< (stringLength emptyEncoded) 200)) true)

fn testDaemonPeerRegistration -> Bool
  (let [(reg0 (m/createPeerRegistry "751f1272")) (peerA (m/makeDaemonPeer "d-a" "751f1272" 1001 "/tmp/sock_a" 0 ":master" 1000)) (peerB (m/makeDaemonPeer "d-b" "751f1272" 1002 "/tmp/sock_b" 0 ":secondary" 1000)) (reg1 (m/registerDaemonPeer reg0 peerA)) (reg2 (m/registerDaemonPeer reg1 peerB)) (foundA (m/findDaemonPeer reg2 "d-a")) (missing (m/findDaemonPeer reg2 "unknown"))] (assert (= reg0.localWorkspaceHash "751f1272")) (assert (= (mapSize reg1.peers) 1)) (assert (= (mapSize reg2.peers) 2)) (assert (some? foundA)) (assert (none? missing)) (assert (mt foundA ((some p) (and (= p.role ":master") (= p.pid 1001))) (_ false))) true)

fn testWorkspaceCollisionDetection -> Bool
  (let [(peerA (m/makeDaemonPeer "d-a" "ws-alpha" 1001 "/tmp/sock_a" 0 ":master" 1000)) (peerB (m/makeDaemonPeer "d-b" "ws-alpha" 1002 "/tmp/sock_b" 0 ":secondary" 1000)) (peerC (m/makeDaemonPeer "d-c" "ws-beta" 1003 "/tmp/sock_c" 0 ":master" 1000)) (peers (list peerA peerB peerC)) (collisions (m/detectWorkspaceCollisions peers "ws-alpha")) (disjoint (m/detectWorkspaceCollisions peers "ws-gamma"))] (assert (= (listLength collisions) 2)) (assert (= (listLength disjoint) 0)) true)

fn testBufferLeaseLifecycle -> Bool
  (let [(reg0 (m/createMutexRegistry))
        (optReg1 (m/acquireBufferLease reg0 "buf-alpha" "peer-a" 1000 30 0))]
    (do
      (assert (some? optReg1))
      (let [(reg1 (mt optReg1 ((some r) r) (_ reg0)))]
        (do
          (assert (= reg1.registryEpoch 1))
          (assert (m/isBufferLocked? reg1 "buf-alpha" 1010))
          (let [(leaseOpt (m/getBufferLease reg1 "buf-alpha"))]
            (do
              (assert (some? leaseOpt))
              (assert (mt leaseOpt ((some l) (= l.holderId "peer-a")) (_ false)))))
          (let [(optStale (m/acquireBufferLease reg1 "buf-beta" "peer-c" 1010 30 0))]
            (assert (none? optStale)))
          (let [(optConflict (m/acquireBufferLease reg1 "buf-alpha" "peer-b" 1010 30 1))]
            (assert (none? optConflict)))
          (let [(optRenew (m/acquireBufferLease reg1 "buf-alpha" "peer-a" 1020 30 1))]
            (assert (some? optRenew)))
          (let [(regBadRel (m/releaseBufferLease reg1 "buf-alpha" "peer-b"))]
            (assert (m/isBufferLocked? regBadRel "buf-alpha" 1015)))
          (let [(regRel (m/releaseBufferLease reg1 "buf-alpha" "peer-a"))]
            (do
              (assert (not (m/isBufferLocked? regRel "buf-alpha" 1015)))
              (assert (= regRel.registryEpoch 2))
              (let [(lease (m/makeBufferLease "buf-exp" "peer-a" 1000 30))]
                (do
                  (assert (not (m/leaseExpired? lease 1020)))
                  (assert (m/leaseExpired? lease 1030))))
              (let [(optExp (m/acquireBufferLease regRel "buf-alpha" "peer-b" 1035 30 2))]
                (assert (some? optExp)))))))
      true))

fn testDeadPeersEviction -> Bool
  (let [(reg0 (m/createPeerRegistry "ws-main")) (pLive (m/makeDaemonPeer "p-live" "ws-main" 2001 "/tmp/live" 0 ":master" 1000)) (pDead (m/makeDaemonPeer "p-dead" "ws-main" 2002 "/tmp/dead" 0 ":secondary" 950)) (reg1 (m/registerDaemonPeer reg0 pLive)) (reg2 (m/registerDaemonPeer reg1 pDead))] (assert (= (mapSize reg2.peers) 2)) (let [(regEvicted (m/evictDeadPeers reg2 1000 30))] (assert (= (mapSize regEvicted.peers) 1)) (assert (some? (m/findDaemonPeer regEvicted "p-live"))) (assert (none? (m/findDaemonPeer regEvicted "p-dead")))) true)

fn runTests -> Bool
  (do (assert (testAmbientFrameCreation)) (assert (testAmbientFrameValidation)) (assert (testAmbientFrameTokenEconomy)) (assert (testDaemonPeerRegistration)) (assert (testWorkspaceCollisionDetection)) (assert (testBufferLeaseLifecycle)) (assert (testDeadPeersEviction)) true)
