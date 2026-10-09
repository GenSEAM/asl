(module aslAgentBus/tests/networkBridgeTest
  :x [runTests RunTests testBridgeInitialization testPeerRegistrationValidation testSendRemoteMessage testReceiveRemoteFrame testDualPolarityRefutations]
  :i [(networkBridge :a nb)])

fn testBridgeInitialization -> Bool
  (let [(bridge (nb/makeNetworkBridge "node-alpha"))]
    (assert (= (nb/getPeerCount bridge) 0) "initial bridge has 0 registered peers")
    (refute (!= (nb/getPeerCount bridge) 0) "initial peer count refutes non-zero")
    (assert (= bridge.sentCount 0) "initial sent count is 0")
    (assert (= bridge.receivedCount 0) "initial received count is 0")
    (refute (!= bridge.sentCount 0) "sent count refutes divergence"))
  true

fn testPeerRegistrationValidation -> Bool
  (let [(bridge0 (nb/makeNetworkBridge "node-local"))
        (regRes (nb/bridgeRegisterPeer bridge0 "peer-beta" "10.0.0.2" 9100 12))]
    (assert (ok? regRes) "registering valid peer succeeds")
    (refute (err? regRes) "registering valid peer refutes error")
    (mt regRes
      ((ok bridge1)
        (assert (= (nb/getPeerCount bridge1) 1) "bridge has 1 peer after registration")
        (assert (nb/isPeerRegistered? bridge1 "peer-beta") "peer-beta is registered")
        (refute (not (nb/isPeerRegistered? bridge1 "peer-beta")) "peer-beta registration refutes false")
        (let [(badEmpty (nb/bridgeRegisterPeer bridge1 "" "10.0.0.3" 9100 13))
              (badPort (nb/bridgeRegisterPeer bridge1 "peer-gamma" "10.0.0.3" 70000 13))
              (badSocket (nb/bridgeRegisterPeer bridge1 "peer-gamma" "10.0.0.3" 9100 1))
              (dupPeer (nb/bridgeRegisterPeer bridge1 "peer-beta" "10.0.0.2" 9100 12))]
          (assert (err? badEmpty) "empty peer ID is rejected")
          (assert (err? badPort) "out-of-range port is rejected")
          (assert (err? badSocket) "invalid socket fd is rejected")
          (assert (err? dupPeer) "duplicate peer registration is rejected")))
      ((err _)
        (assert false "unexpected registration failure")
        (refute true "unexpected registration failure"))))
  true

fn testSendRemoteMessage -> Bool
  (let [(bridge0 (nb/makeNetworkBridge "node-sender"))
        (regRes (nb/bridgeRegisterPeer bridge0 "peer-target" "127.0.0.1" 8888 10))
        (bridge1 (mt regRes ((ok b) b) ((err _) bridge0)))
        (sendRes (nb/bridgeSendRemote bridge1 "peer-target" "(:task :action \"ping\")"))]
    (assert (ok? sendRes) "send to registered peer succeeds")
    (refute (err? sendRes) "send to registered peer refutes error")
    (mt sendRes
      ((ok bridge2)
        (assert (= bridge2.sentCount 1) "sentCount incremented to 1")
        (refute (!= bridge2.sentCount 1) "sentCount refutes non-1"))
      ((err _)
        (assert false "unexpected send error")
        (refute true "unexpected send error"))))
  true

fn testReceiveRemoteFrame -> Bool
  (let [(bridge0 (nb/makeNetworkBridge "node-receiver"))
        (validFrame "(:seambus-frame :src \"node-remote\" :dst \"node-receiver\" :payload \"(:status ok)\")")
        (recvRes (nb/bridgeReceiveRemote bridge0 validFrame))]
    (assert (ok? recvRes) "receive valid frame succeeds")
    (refute (err? recvRes) "receive valid frame refutes error")
    (mt recvRes
      ((ok pairVal)
        (let [(bUpdated (pairFirst pairVal))
              (payload (pairSecond pairVal))]
          (assert (= bUpdated.receivedCount 1) "receivedCount is 1")
          (assert (= payload validFrame) "received payload matches incoming frame")))
      ((err _)
        (assert false "unexpected receive error")
        (refute true "unexpected receive error"))))
  true

fn testDualPolarityRefutations -> Bool
  (let [(bridge (nb/makeNetworkBridge "node-tester"))
        (sendUnknown (nb/bridgeSendRemote bridge "unknown-peer" "payload"))
        (badFrame "invalid raw text not starting with seambus frame")
        (recvBad (nb/bridgeReceiveRemote bridge badFrame))]
    (assert (err? sendUnknown) "sending to unknown peer fails")
    (refute (ok? sendUnknown) "sending to unknown peer refutes ok")
    (assert (err? recvBad) "receiving malformed frame fails")
    (refute (ok? recvBad) "receiving malformed frame refutes ok"))
  true

fn runTests -> Bool
  (do
    (assert (testBridgeInitialization) "testBridgeInitialization passed")
    (assert (testPeerRegistrationValidation) "testPeerRegistrationValidation passed")
    (assert (testSendRemoteMessage) "testSendRemoteMessage passed")
    (assert (testReceiveRemoteFrame) "testReceiveRemoteFrame passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
