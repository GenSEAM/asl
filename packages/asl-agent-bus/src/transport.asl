(module aslAgentBus/transport :x [TransportFrameType TransportState TransportEnvelope TransportSession makeTransportEnvelope initTransportSession sessionRecordSent sessionRecordReceived sessionSetState isSessionActive? formatFrameHeader validateTransportEnvelope envelope->canonicalWireFrame canonicalWireFrame->envelope] :i [(wire :a wire)])

(enum TransportFrameType (:c frameHandshake [] "Connection handshake and protocol negotiation frame") (:c frameHeartbeat [] "Periodic liveness ping or pong frame") (:c frameRpcReq [] "Synchronous or batch RPC request frame") (:c frameRpcRes [] "RPC outcome or failure response frame") (:c frameStreamChunk [] "Chunked streaming payload frame") (:c frameClose [] "Graceful transport termination frame"))

(enum TransportState (:c transportIdle [] "Transport initialized but connection not established") (:c transportConnecting [] "Transport handshake in flight") (:c transportConnected [] "Transport active and streaming frames") (:c transportClosing [] "Transport draining pending frames prior to termination") (:c transportClosed [] "Transport fully terminated"))

(schema TransportEnvelope (:f id Str) (:f frameType TransportFrameType) (:f sender Str) (:f target Str) (:f seq I64) (:f payload Str) (:f timestamp I64))

(schema TransportSession (:f sessionId Str) (:f state TransportState) (:f remoteNode Str) (:f lastSeq I64) (:f framesSent I64) (:f framesReceived I64))

fn makeTransportEnvelope id: Str frameType: TransportFrameType sender: Str target: Str seq: I64 payload: Str timestamp: I64 -> TransportEnvelope
  (TransportEnvelope :id id :frameType frameType :sender sender :target target :seq seq :payload payload :timestamp timestamp)

fn initTransportSession sessionId: Str remoteNode: Str -> TransportSession
  (TransportSession :sessionId sessionId :state (transportIdle) :remoteNode remoteNode :lastSeq 0 :framesSent 0 :framesReceived 0)

fn sessionRecordSent session: TransportSession seq: I64 -> TransportSession
  (with session :lastSeq seq :framesSent (+ session.framesSent 1))

fn sessionRecordReceived session: TransportSession seq: I64 -> TransportSession
  (with session :lastSeq seq :framesReceived (+ session.framesReceived 1))

fn sessionSetState session: TransportSession newState: TransportState -> TransportSession
  (with session :state newState)

fn isSessionActive? session: TransportSession -> Bool
  (mt session.state ((transportConnected) true) ((transportIdle) false) ((transportConnecting) false) ((transportClosing) false) ((transportClosed) false))

fn formatFrameHeader env: TransportEnvelope -> Str
  (str "FRAME:" env.id ":" (stringFromInt64 env.seq) ":" env.sender "->" env.target)

fn validateTransportEnvelope env: TransportEnvelope -> Bool
  (and (not (stringEmpty? env.id)) (and (not (stringEmpty? env.sender)) (and (not (stringEmpty? env.target)) (>= env.seq 0))))

fn serializeFrameType t: TransportFrameType -> Str
  (mt t ((frameHandshake) "HND") ((frameHeartbeat) "HRT") ((frameRpcReq) "REQ") ((frameRpcRes) "RES") ((frameStreamChunk) "CHK") ((frameClose) "CLS"))

fn parseFrameType s: Str -> TransportFrameType
  (cond ((= s "HND") (frameHandshake)) ((= s "HRT") (frameHeartbeat)) ((= s "RES") (frameRpcRes)) ((= s "CHK") (frameStreamChunk)) ((= s "CLS") (frameClose)) (else (frameRpcReq)))

fn envelope->canonicalWireFrame env: TransportEnvelope -> wire/CanonicalWireFrame
  (wire/CanonicalWireFrame :identity env.id :sessionId (str "sess-" env.sender) :causality (str "(:type \"" (serializeFrameType env.frameType) "\" :seq \"" (stringFromInt64 env.seq) "\" :target \"" env.target "\" :ts \"" (stringFromInt64 env.timestamp) "\")") :payload env.payload :digest (str "sha256-" env.id))

fn canonicalWireFrame->envelope frame: wire/CanonicalWireFrame -> TransportEnvelope
  (let [(sess frame.sessionId) (sender (if (stringStartsWith? sess "sess-") (stringReplace sess "sess-" "") sess)) (caus frame.causality) (tStr (wire/extractWireField caus ":type")) (seqStr (wire/extractWireField caus ":seq")) (targetStr (wire/extractWireField caus ":target")) (tsStr (wire/extractWireField caus ":ts"))] (TransportEnvelope :id frame.identity :frameType (parseFrameType tStr) :sender sender :target (if (= targetStr "") "broadcast" targetStr) :seq (optionOr (stringToInt64 seqStr) 0) :payload frame.payload :timestamp (optionOr (stringToInt64 tsStr) 0)))

fn RunTests -> Bool
  (let [(env (makeTransportEnvelope "env-001" (frameRpcReq) "agent-alpha" "agent-beta" 1 "(:ping true)" 1000))] (assert (validateTransportEnvelope env) "Valid envelope passes validation") (assert (= (formatFrameHeader env) "FRAME:env-001:1:agent-alpha->agent-beta") "Header formatting correct") (let [(frame (envelope->canonicalWireFrame env))] (assert (= frame.identity "env-001") "Identity maps cleanly") (assert (= frame.sessionId "sess-agent-alpha") "Session maps cleanly") (assert (= frame.causality "(:type \"REQ\" :seq \"1\" :target \"agent-beta\" :ts \"1000\")") "Causality maps cleanly") (assert (= frame.payload "(:ping true)") "Payload maps cleanly") (let [(valRes (wire/validateWireFrame frame))] (assert valRes.valid? "Converted frame passes ingress validation") (assert (wire/roundtripTransports? frame) "Converted frame roundtrips across all four transports") (let [(back (canonicalWireFrame->envelope frame))] (assert (= back.id "env-001") "Envelope id restored") (assert (= back.payload "(:ping true)") "Envelope payload restored") (assert (= back.seq 1) "Envelope seq restored") (assert (= back.target "agent-beta") "Envelope target restored") (assert (= back.timestamp 1000) "Envelope timestamp restored") true))))
