(module aslAgentBus/presence :x [AgentStatus ClaimMode PathClaim SwarmPeer SwarmRoom NegotiationKind NegotiationOffer createSwarmRoom joinSwarmRoom leaveSwarmRoom listRoomPeers findPeerInRoom claimPath releaseClaim isClaimExpired? proposeTask acceptTask declineTask formatPresenceRoster PeerTraceAttachment makePeerTraceAttachment] :i [(mesh :a mesh)])

(enum AgentStatus (:c statusIdle [] "Agent is online and ready for task assignment") (:c statusBusy [] "Agent is actively processing a task queue") (:c statusListening [] "Agent is registered in passive listener/observer mode") (:c statusOffline [] "Agent heartbeat has expired or node disconnected"))

(enum ClaimMode (:c claimRead [] "Advisory read hold") (:c claimWrite [] "Advisory write hold"))

(schema PathClaim (:f path Str) (:f mode ClaimMode) (:f holder Str) (:f epoch I64) (:f ttlSeconds I64))

(schema SwarmPeer (:f agentId Str) (:f role Str) (:f room Str) (:f status AgentStatus) (:f capabilities (List Str)) (:f lastPingEpoch I64) (:f claims (List PathClaim)))

(schema SwarmRoom (:f roomName Str) (:f topic Str) (:f peers (List SwarmPeer)))

(enum NegotiationKind (:c kindPropose [] "Task assignment proposal from coordinator") (:c kindAccept [] "Task acceptance confirmation with ETA") (:c kindDecline [] "Task rejection with diagnostic reason") (:c kindComplete [] "Task completion receipt with result"))

(schema NegotiationOffer (:f bidId Str) (:f taskName Str) (:f fromAgent Str) (:f toAgent Str) (:f kind NegotiationKind) (:f etaSeconds I64) (:f reason Str))

fn createSwarmRoom name: Str topic: Str -> SwarmRoom
  (SwarmRoom :roomName name :topic topic :peers (list))

fn joinSwarmRoom room: SwarmRoom peer: SwarmPeer -> SwarmRoom
  (let [(filtered (filter (fn [(p SwarmPeer)] -> Bool (not (= p.agentId peer.agentId))) room.peers))] (with room :peers (listAppend filtered (list peer))))

fn leaveSwarmRoom room: SwarmRoom agentId: Str -> SwarmRoom
  (let [(filtered (filter (fn [(p SwarmPeer)] -> Bool (not (= p.agentId agentId))) room.peers))] (with room :peers filtered))

fn listRoomPeers room: SwarmRoom -> (List SwarmPeer)
  room.peers

fn findPeerInRoom room: SwarmRoom agentId: Str -> (Option SwarmPeer)
  (let [(matches (filter (fn [(p SwarmPeer)] -> Bool (= p.agentId agentId)) room.peers))] (listHead matches))

fn isClaimExpired? claim: PathClaim nowEpoch: I64 -> Bool
  (> nowEpoch (+ claim.epoch claim.ttlSeconds))

fn claimPath peer: SwarmPeer path: Str mode: ClaimMode nowEpoch: I64 ttl: I64 -> SwarmPeer
  (let [(newClaim (PathClaim :path path :mode mode :holder peer.agentId :epoch nowEpoch :ttlSeconds ttl)) (active (filter (fn [(c PathClaim)] -> Bool (and (not (= c.path path)) (not (isClaimExpired? c nowEpoch)))) peer.claims))] (with peer :lastPingEpoch nowEpoch :claims (listAppend active (list newClaim))))

fn releaseClaim peer: SwarmPeer path: Str -> SwarmPeer
  (let [(active (filter (fn [(c PathClaim)] -> Bool (not (= c.path path))) peer.claims))] (with peer :claims active))

fn proposeTask fromId: Str toId: Str taskName: Str bidId: Str -> NegotiationOffer
  (NegotiationOffer :bidId bidId :taskName taskName :fromAgent fromId :toAgent toId :kind (kindPropose) :etaSeconds 0 :reason "Task proposal pending review")

fn acceptTask bidId: Str fromId: Str toId: Str eta: I64 -> NegotiationOffer
  (NegotiationOffer :bidId bidId :taskName "" :fromAgent fromId :toAgent toId :kind (kindAccept) :etaSeconds eta :reason "Task accepted into active execution queue")

fn declineTask bidId: Str fromId: Str toId: Str reason: Str -> NegotiationOffer
  (NegotiationOffer :bidId bidId :taskName "" :fromAgent fromId :toAgent toId :kind (kindDecline) :etaSeconds 0 :reason reason)

fn formatPresenceRoster room: SwarmRoom -> Str
  (let [(hdr (str "### Swarm Room: " room.roomName " (" room.topic ")
" "| Agent ID | Role | Status | Capabilities | Claims |
" "|---|---|---|---|---|
"))] (fold (fn [(acc Str) (p SwarmPeer)] -> Str (let [(stStr (mt p.status ((statusIdle) "idle") ((statusBusy) "busy") ((statusListening) "listening") ((statusOffline) "offline"))) (capsStr (stringJoin p.capabilities ", ")) (claimsStr (if (listEmpty? p.claims) "none" (stringJoin (map (fn [(c PathClaim)] -> Str (str c.path " (" (mt c.mode ((claimRead) "r") ((claimWrite) "w")) ")")) p.claims) ", ")))] (str acc "| `" p.agentId "` | " p.role " | *" stStr "* | " capsStr " | " claimsStr " |
"))) hdr room.peers))

(schema PeerTraceAttachment (:f peerId Str) (:f sessionId Str) (:f runtimeTarget Str) (:f traceFrames (List mesh/CausalTraceFrame)))

fn makePeerTraceAttachment peerId: Str sessionId: Str runtimeTarget: Str frames: (List mesh/CausalTraceFrame) -> PeerTraceAttachment
  (PeerTraceAttachment :peerId peerId :sessionId sessionId :runtimeTarget runtimeTarget :traceFrames frames)
