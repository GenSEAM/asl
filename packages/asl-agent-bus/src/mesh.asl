(module aslAgentBus/mesh :x [MeshNode RoutingTable TransportProtocol createRoutingTable registerMeshNode routePacket isNodeAlive TaskConstraint TaskContract makeTaskConstraint makeTaskContract delegateContract ControlSignalFrame makeControlSignal formatControlSignal ComputeTier tierEdge tierFog tierCloud getComputeTierName DaemonPeer PeerRegistry makeDaemonPeer createPeerRegistry registerDaemonPeer findDaemonPeer detectWorkspaceCollisions BufferLease MutexRegistry makeBufferLease createMutexRegistry leaseExpired? acquireBufferLease releaseBufferLease evictDeadPeers getBufferLease isBufferLocked? AgentMeshNode joinMeshCluster CausalTraceFrame CausalTraceGap MergedMeshTrace makeCausalTraceFrame makeCausalTraceGap emptyCausalTraceFrame frameCausallyPrecedes? insertCausalFrame sortCausalFrames detectTraceGaps mergeMeshTraces formatFrameForReflect formatMeshTraceForReflect] :i [])

(enum TransportProtocol (:c ipcUds [] "Unix domain socket IPC") (:c inMemory [] "In-memory fast ring transport") (:c sseStream [] "Server-Sent Events streaming transport") (:c wasmChannel [] "Wasm linear memory direct channel") (:c clusterNet [] "Remote cluster TCP/WebSocket transport"))

(schema MeshNode (:f id Str) (:f role Str) (:f tier Str) (:f inboxSize I64) (:f isAlive Bool))

(schema RoutingTable (:f nodes (Map Str MeshNode)) (:f defaultTransport TransportProtocol))

fn createRoutingTable -> RoutingTable
  (RoutingTable :nodes (mapEmpty) :defaultTransport (inMemory))

fn registerMeshNode rt: RoutingTable node: MeshNode -> RoutingTable
  (with rt :nodes (mapSet rt.nodes node.id node))

fn isNodeAlive node: MeshNode -> Bool
  node.isAlive

fn routePacket rt: RoutingTable from: Str to: Str payload: Str -> Str
  (str "(packet :from \"" from "\" :to \"" to "\" :data " payload ")")

(schema TaskConstraint (:f id Str) (:f rule Str) (:f severity Str))

(schema TaskContract (:f taskId Str) (:f originPrompt Str) (:f constraints (List TaskConstraint)) (:f acceptanceCriteria (List Str)) (:f delegationMode Str) (:f assignedRoles (List Str)))

fn makeTaskConstraint id: Str rule: Str severity: Str -> TaskConstraint
  (TaskConstraint :id id :rule rule :severity severity)

fn makeTaskContract taskId: Str originPrompt: Str constraints: (List TaskConstraint) acceptanceCriteria: (List Str) delegationMode: Str assignedRoles: (List Str) -> TaskContract
  (TaskContract :taskId taskId :originPrompt originPrompt :constraints constraints :acceptanceCriteria acceptanceCriteria :delegationMode delegationMode :assignedRoles assignedRoles)

fn delegateContract contract: TaskContract targetRole: Str -> Str
  (str "(:contract-dispatch :task-id \"" contract.taskId "\" :role \"" targetRole "\" :mode \"" contract.delegationMode "\")")

(schema ControlSignalFrame (:f signalType Str) (:f taskId Str) (:f targetCluster Str) (:f vfsDescriptorUri Str) (:f payload Str))

fn makeControlSignal signalType: Str taskId: Str targetCluster: Str vfsDescriptorUri: Str payload: Str -> ControlSignalFrame
  (ControlSignalFrame :signalType signalType :taskId taskId :targetCluster targetCluster :vfsDescriptorUri vfsDescriptorUri :payload payload)

fn formatControlSignal frame: ControlSignalFrame -> Str
  (str "(:signal \"" frame.signalType "\" :task-id \"" frame.taskId "\" :cluster \"" frame.targetCluster "\" :vfs \"" frame.vfsDescriptorUri "\" :data " frame.payload ")")

(enum ComputeTier (:c tier0Deterministic [] "Deterministic ripgrep/AWK/syntax tools under 1ms") (:c tier1EdgeMediator [] "Edge SLM on WebGPU DOM accessibility tree 15-50ms") (:c tier2Workhorse [] "Gemma 31B/Haiku sub-second workhorse 400-900ms") (:c tier3FrontierReasoning [] "Frontier reasoning Claude 3.5 Sonnet/O1 2-8s"))

fn getComputeTierName tier: ComputeTier -> Str
  (mt tier ((tier0Deterministic) "tier-0-deterministic") ((tier1EdgeMediator) "tier-1-edge-mediator") ((tier2Workhorse) "tier-2-workhorse") ((tier3FrontierReasoning) "tier-3-frontier-reasoning"))

(schema DaemonPeer (:f daemonId Str) (:f workspaceHash Str) (:f pid I64) (:f socketPath Str) (:f port I64) (:f role Str) (:f heartbeatEpoch I64) (:f status Str))

(schema PeerRegistry (:f peers (Map Str DaemonPeer)) (:f localWorkspaceHash Str))

fn makeDaemonPeer daemonId: Str workspaceHash: Str pid: I64 socketPath: Str port: I64 role: Str heartbeatEpoch: I64 -> DaemonPeer
  (DaemonPeer :daemonId daemonId :workspaceHash workspaceHash :pid pid :socketPath socketPath :port port :role role :heartbeatEpoch heartbeatEpoch :status "active")

fn createPeerRegistry workspaceHash: Str -> PeerRegistry
  (PeerRegistry :peers (mapEmpty) :localWorkspaceHash workspaceHash)

fn registerDaemonPeer reg: PeerRegistry peer: DaemonPeer -> PeerRegistry
  (with reg :peers (mapSet reg.peers peer.daemonId peer))

fn findDaemonPeer reg: PeerRegistry daemonId: Str -> (Option DaemonPeer)
  (mapGet reg.peers daemonId)

fn detectWorkspaceCollisions peers: (List DaemonPeer) targetWs: Str -> (List DaemonPeer)
  (filter (fn [(p DaemonPeer)] -> Bool (and (= p.workspaceHash targetWs) (= p.status "active"))) peers)

(schema BufferLease (:f bufferId Str) (:f holderId Str) (:f acquiredEpoch I64) (:f ttlSeconds I64))

(schema MutexRegistry (:f leases (Map Str BufferLease)) (:f registryEpoch I64))

fn makeBufferLease bufferId: Str holderId: Str acquiredEpoch: I64 ttlSeconds: I64 -> BufferLease
  (BufferLease :bufferId bufferId :holderId holderId :acquiredEpoch acquiredEpoch :ttlSeconds ttlSeconds)

fn createMutexRegistry -> MutexRegistry
  (MutexRegistry :leases (mapEmpty) :registryEpoch 0)

fn leaseExpired? lease: BufferLease currentEpoch: I64 -> Bool
  (>= (- currentEpoch lease.acquiredEpoch) lease.ttlSeconds)

fn acquireBufferLease reg: MutexRegistry bufferId: Str peerId: Str currentEpoch: I64 ttlSeconds: I64 expectedEpoch: I64 -> (Option MutexRegistry)
  (if (and (!= expectedEpoch -1) (!= reg.registryEpoch expectedEpoch))
    (none)
    (let [(existing (mapGet reg.leases bufferId))]
      (mt existing
        ((some lease)
          (if (or (= lease.holderId peerId) (leaseExpired? lease currentEpoch))
            (let [(newLease (makeBufferLease bufferId peerId currentEpoch ttlSeconds))
                  (updatedLeases (mapSet reg.leases bufferId newLease))
                  (nextEpoch (+ reg.registryEpoch 1))]
              (some (MutexRegistry :leases updatedLeases :registryEpoch nextEpoch)))
            (none)))
        ((none)
          (let [(newLease (makeBufferLease bufferId peerId currentEpoch ttlSeconds))
                (updatedLeases (mapSet reg.leases bufferId newLease))
                (nextEpoch (+ reg.registryEpoch 1))]
            (some (MutexRegistry :leases updatedLeases :registryEpoch nextEpoch)))))))

fn releaseBufferLease reg: MutexRegistry bufferId: Str peerId: Str -> MutexRegistry
  (let [(existing (mapGet reg.leases bufferId))]
    (mt existing
      ((some lease)
        (if (= lease.holderId peerId)
          (MutexRegistry :leases (mapRemove reg.leases bufferId) :registryEpoch (+ reg.registryEpoch 1))
          reg))
      ((none) reg)))

fn getBufferLease reg: MutexRegistry bufferId: Str -> (Option BufferLease)
  (mapGet reg.leases bufferId)

fn isBufferLocked? reg: MutexRegistry bufferId: Str currentEpoch: I64 -> Bool
  (let [(existing (mapGet reg.leases bufferId))] (mt existing ((some lease) (not (leaseExpired? lease currentEpoch))) ((none) false)))

fn evictDeadPeers reg: PeerRegistry currentEpoch: I64 ttlThreshold: I64 -> PeerRegistry
  (let [(alivePeers (filter (fn [(p DaemonPeer)] -> Bool (<= (- currentEpoch p.heartbeatEpoch) ttlThreshold)) (mapValues reg.peers))) (newMap (fold (fn [(acc (Map Str DaemonPeer)) (p DaemonPeer)] -> (Map Str DaemonPeer) (mapSet acc p.daemonId p)) (mapEmpty) alivePeers))] (with reg :peers newMap))

(schema AgentMeshNode (:f nodeId Str) (:f role Str) (:f endpoint Str) (:f status Str) (:f lastSeenEpoch I64))

fn joinMeshCluster rt: RoutingTable node: AgentMeshNode -> RoutingTable
  (let [(meshNode (MeshNode :id node.nodeId :role node.role :tier "tier-1-sovereign" :inboxSize 0 :isAlive true))] (registerMeshNode rt meshNode))

(schema CausalTraceFrame (:f frameId Str) (:f sessionId Str) (:f runtimeTarget Str) (:f senderId Str) (:f parentDigest Str) (:f sequence I64) (:f causalClock I64) (:f timestamp I64) (:f op Str) (:f target Str) (:f status Str) (:f digest Str))

(schema CausalTraceGap (:f sessionId Str) (:f runtimeTarget Str) (:f expectedSequence I64) (:f foundSequence I64) (:f reason Str))

(schema MergedMeshTrace (:f frames (List CausalTraceFrame)) (:f gaps (List CausalTraceGap)) (:f totalFrames I64) (:f gapCount I64))

fn makeCausalTraceFrame frameId: Str sessionId: Str runtimeTarget: Str senderId: Str parentDigest: Str sequence: I64 causalClock: I64 timestamp: I64 op: Str target: Str status: Str digest: Str -> CausalTraceFrame
  (CausalTraceFrame :frameId frameId :sessionId sessionId :runtimeTarget runtimeTarget :senderId senderId :parentDigest parentDigest :sequence sequence :causalClock causalClock :timestamp timestamp :op op :target target :status status :digest digest)

fn makeCausalTraceGap sessionId: Str runtimeTarget: Str expectedSeq: I64 foundSeq: I64 reason: Str -> CausalTraceGap
  (CausalTraceGap :sessionId sessionId :runtimeTarget runtimeTarget :expectedSequence expectedSeq :foundSequence foundSeq :reason reason)

fn emptyCausalTraceFrame -> CausalTraceFrame
  (CausalTraceFrame :frameId "" :sessionId "" :runtimeTarget "" :senderId "" :parentDigest "" :sequence 0 :causalClock 0 :timestamp 0 :op "" :target "" :status "" :digest "")

fn frameCausallyPrecedes? a: CausalTraceFrame b: CausalTraceFrame -> Bool
  (if (and (!= b.parentDigest "") (= b.parentDigest a.digest)) true (if (and (!= a.parentDigest "") (= a.parentDigest b.digest)) false (if (and (= a.sessionId b.sessionId) (= a.runtimeTarget b.runtimeTarget)) (< a.sequence b.sequence) (if (!= a.causalClock b.causalClock) (< a.causalClock b.causalClock) (< a.timestamp b.timestamp)))))

fn insertCausalFrame item: CausalTraceFrame sorted: (List CausalTraceFrame) -> (List CausalTraceFrame)
  (if (listEmpty? sorted) (list item) (let [(headF (optionOr (listHead sorted) (emptyCausalTraceFrame))) (tailF (optionOr (listTail sorted) (list)))] (if (frameCausallyPrecedes? item headF) (cons item sorted) (cons headF (insertCausalFrame item tailF)))))

fn sortCausalFramesLoop unsorted: (List CausalTraceFrame) sorted: (List CausalTraceFrame) -> (List CausalTraceFrame)
  (if (listEmpty? unsorted) sorted (let [(item (optionOr (listHead unsorted) (emptyCausalTraceFrame))) (rest (optionOr (listTail unsorted) (list)))] (sortCausalFramesLoop rest (insertCausalFrame item sorted))))

fn sortCausalFrames frames: (List CausalTraceFrame) -> (List CausalTraceFrame)
  (sortCausalFramesLoop frames (list))

fn detectGapsLoop frames: (List CausalTraceFrame) seqMap: (Map Str I64) seenDigests: (Map Str Bool) gaps: (List CausalTraceGap) -> (List CausalTraceGap)
  (if (listEmpty? frames) gaps (let [(f (optionOr (listHead frames) (emptyCausalTraceFrame))) (rest (optionOr (listTail frames) (list))) (key (str f.sessionId "::" f.runtimeTarget)) (curSeq f.sequence) (prevSeqOpt (mapGet seqMap key)) (expectedSeq (mt prevSeqOpt ((some prev) (+ prev 1)) ((none) 1))) (hasSeqGap (> curSeq expectedSeq)) (newGaps1 (if hasSeqGap (cons (makeCausalTraceGap f.sessionId f.runtimeTarget expectedSeq curSeq "sequence-gap-detected") gaps) gaps)) (pd f.parentDigest) (hasParentGap (and (!= pd "") (!= pd "root") (not (mapHas? seenDigests pd)))) (newGaps2 (if hasParentGap (cons (makeCausalTraceGap f.sessionId f.runtimeTarget 0 0 (str "missing-parent-digest-" pd)) newGaps1) newGaps1)) (nextSeqMap (mapSet seqMap key curSeq)) (nextSeen (if (!= f.digest "") (mapSet seenDigests f.digest true) seenDigests))] (detectGapsLoop rest nextSeqMap nextSeen newGaps2)))

fn detectTraceGaps frames: (List CausalTraceFrame) -> (List CausalTraceGap)
  (detectGapsLoop frames (mapEmpty) (mapEmpty) (list))

fn mergeMeshTraces traces: (List (List CausalTraceFrame)) -> MergedMeshTrace
  (let [(flatFrames (fold (fn [(acc (List CausalTraceFrame)) (tr (List CausalTraceFrame))] -> (List CausalTraceFrame) (listAppend acc tr)) (list) traces)) (sortedFrames (sortCausalFrames flatFrames)) (detectedGaps (detectTraceGaps sortedFrames)) (frameCnt (listLength sortedFrames)) (gapCnt (listLength detectedGaps))] (MergedMeshTrace :frames sortedFrames :gaps detectedGaps :totalFrames frameCnt :gapCount gapCnt))

fn formatFrameForReflect f: CausalTraceFrame -> Str
  (str "(:trace-entry :timestamp " (stringFromInt64 f.timestamp) " :step " (stringFromInt64 f.sequence) " :sessionId \"" f.sessionId "\"" " :runtimeTarget \"" f.runtimeTarget "\"" " :seq " (stringFromInt64 f.sequence) " :parentDigest \"" f.parentDigest "\"" " :op \"" f.op "\"" " :target \"" f.target "\"" " :status \"" f.status "\"" " :digest \"" f.digest "\"" " :durationMs 0)")

fn formatMeshTraceForReflect merged: MergedMeshTrace -> Str
  (fold (fn [(acc Str) (f CausalTraceFrame)] -> Str (let [(line (formatFrameForReflect f))] (if (= acc "") line (str acc "\n" line)))) "" merged.frames)
