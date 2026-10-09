(module aslAgentBus/networkBridge
  :x [RemotePeer NetworkBridge makeNetworkBridge bridgeRegisterPeer bridgeSendRemote bridgeReceiveRemote isPeerRegistered? getPeerCount]
  :i [])

(schema RemotePeer
  (:f peerId String)
  (:f host String)
  (:f port Int64)
  (:f socketFd Int64)
  (:f active Bool))

(schema NetworkBridge
  (:f localNodeId String)
  (:f peers (List RemotePeer))
  (:f sentCount Int64)
  (:f receivedCount Int64))

fn makeNetworkBridge localNodeId: String -> NetworkBridge
  (NetworkBridge
    :localNodeId localNodeId
    :peers (list)
    :sentCount 0
    :receivedCount 0)

fn getPeerCount bridge: NetworkBridge -> Int64
  (listLength bridge.peers)

fn isPeerRegistered? bridge: NetworkBridge targetId: String -> Bool
  (listAny? (fn [(p RemotePeer)] (= p.peerId targetId)) bridge.peers)

fn bridgeRegisterPeer bridge: NetworkBridge peerId: String host: String port: Int64 socketFd: Int64 -> (Result NetworkBridge String)
  (if (stringEmpty? peerId)
    (err "ERR_BRIDGE_EMPTY_PEER_ID")
    (if (or (< port 1) (> port 65535))
      (err "ERR_BRIDGE_INVALID_PORT")
      (if (or (< socketFd 3) (> socketFd 256))
        (err "ERR_BRIDGE_INVALID_SOCKET")
        (if (isPeerRegistered? bridge peerId)
          (err "ERR_BRIDGE_PEER_ALREADY_REGISTERED")
          (let [(newPeer (RemotePeer :peerId peerId :host host :port port :socketFd socketFd :active true))
                (updatedPeers (listAppend bridge.peers (list newPeer)))]
            (ok (with bridge :peers updatedPeers)))))))

fn findPeer peers: (List RemotePeer) targetId: String -> (Option RemotePeer)
  (let [(matches (filter (fn [(p RemotePeer)] (= p.peerId targetId)) peers))]
    (listHead matches))

fn bridgeSendRemote bridge: NetworkBridge targetPeerId: String payload: String -> (Result NetworkBridge String)
  (let [(peerOpt (findPeer bridge.peers targetPeerId))]
    (mt peerOpt
      ((none)
        (err "ERR_PEER_NOT_FOUND"))
      ((some peer)
        (if (not peer.active)
          (err "ERR_PEER_INACTIVE")
          (let [(newSent (+ bridge.sentCount 1))]
            (ok (with bridge :sentCount newSent)))))))

fn bridgeReceiveRemote bridge: NetworkBridge rawFrame: String -> (Result (Pair NetworkBridge String) String)
  (if (not (stringStartsWith? rawFrame "(:seambus-frame"))
    (err "ERR_INVALID_FRAME_HEADER")
    (let [(newRecv (+ bridge.receivedCount 1))
          (updatedBridge (with bridge :receivedCount newRecv))]
      (ok (pair updatedBridge rawFrame))))
