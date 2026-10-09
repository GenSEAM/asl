(module aslAgentBus/transportPatch :x [serializeFrameType parseFrameType envelope->canonicalWireFrame getPart canonicalWireFrame->envelope] :i [(transport :a tr) (wire :a wire)])

fn serializeFrameType t: tr/TransportFrameType -> Str
  (mt t ((tr/frameHandshake) "HND") ((tr/frameHeartbeat) "HRT") ((tr/frameRpcReq) "REQ") ((tr/frameRpcRes) "RES") ((tr/frameStreamChunk) "CHK") ((tr/frameClose) "CLS"))

fn parseFrameType s: Str -> tr/TransportFrameType
  (cond ((= s "HND") (tr/frameHandshake)) ((= s "HRT") (tr/frameHeartbeat)) ((= s "RES") (tr/frameRpcRes)) ((= s "CHK") (tr/frameStreamChunk)) ((= s "CLS") (tr/frameClose)) (else (tr/frameRpcReq)))

fn envelope->canonicalWireFrame env: tr/TransportEnvelope -> wire/CanonicalWireFrame
  (wire/CanonicalWireFrame :identity env.id :sessionId (str "sess-" env.sender) :causality (str (serializeFrameType env.frameType) ":" (stringFromInt64 env.seq) ":" env.target ":" (stringFromInt64 env.timestamp)) :payload env.payload :digest (str "sha256-" env.id))

fn getPart s: Str idx: I64 -> Str
  (if (= idx 0) (let [(p (stringIndexOf s ":"))] (mt p ((none) s) ((some i) (optionOr (stringSlice s 0 i) "")))) (let [(p (stringIndexOf s ":"))] (mt p ((none) "") ((some i) (getPart (optionOr (stringSlice s (+ i 1) (stringLength s)) "") (- idx 1))))))

fn canonicalWireFrame->envelope frame: wire/CanonicalWireFrame -> tr/TransportEnvelope
  (let [(sess frame.sessionId) (sender (if (stringStartsWith? sess "sess-") (stringReplace sess "sess-" "") sess)) (caus frame.causality) (tStr (getPart caus 0)) (seqStr (getPart caus 1)) (targetStr (getPart caus 2)) (tsStr (getPart caus 3))] (tr/TransportEnvelope :id frame.identity :frameType (parseFrameType tStr) :sender sender :target (if (= targetStr "") "broadcast" targetStr) :seq (optionOr (stringToInt64 seqStr) 0) :payload frame.payload :timestamp (optionOr (stringToInt64 tsStr) 0)))
