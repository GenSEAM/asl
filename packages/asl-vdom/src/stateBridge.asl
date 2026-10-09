(module aslVdom/stateBridge :x [StateBridge UIEvent initBridge updateBridgeSync parseNativeEvent isFallbackEvent? eventToAction dispatchBridgeEvent serializePatchItem serializePatches formatBridgeBusEvent extractJsonField] :i [(state :a s)])

(schema StateBridge (:f channel String) (:f agentId String) (:f lastSyncEpoch Int64))

(schema UIEvent (:f componentId String) (:f action String) (:f value String))

fn initBridge channel: String agentId: String -> StateBridge
  (StateBridge :channel channel :agentId agentId :lastSyncEpoch 0)

fn updateBridgeSync bridge: StateBridge epoch: Int64 -> StateBridge
  (with bridge :lastSyncEpoch epoch)

fn extractJsonField jsonStr: String key: String -> (Option String)
  (let [(kQuoted (str "\"" key "\"")) (idx1 (stringIndexOf jsonStr kQuoted))] (mt idx1 ((some pos) (let [(afterKey (optionOr (stringSlice jsonStr (+ pos (stringLength kQuoted)) (stringLength jsonStr)) "")) (colonIdx (stringIndexOf afterKey ":"))] (mt colonIdx ((some cPos) (let [(afterColon (optionOr (stringSlice afterKey (+ cPos 1) (stringLength afterKey)) "")) (firstQuote (stringIndexOf afterColon "\""))] (mt firstQuote ((some q1) (let [(valStart (+ q1 1)) (afterQuote (optionOr (stringSlice afterColon valStart (stringLength afterColon)) "")) (secondQuote (stringIndexOf afterQuote "\""))] (mt secondQuote ((some q2) (stringSlice afterQuote 0 q2)) ((none) (none))))) ((none) (let [(trimmed (stringTrim afterColon))] (if (stringStartsWith? trimmed "null") (some "") (let [(commaIdx (stringIndexOf trimmed ",")) (braceIdx (stringIndexOf trimmed "}")) (endPos (mt commaIdx ((some cp) (mt braceIdx ((some bp) (if (< cp bp) cp bp)) ((none) cp))) ((none) (mt braceIdx ((some bp) bp) ((none) (stringLength trimmed))))))] (some (stringTrim (optionOr (stringSlice trimmed 0 endPos) "")))))))))) ((none) (none))))) ((none) (let [(kAsn (str ":" key)) (idx2 (stringIndexOf jsonStr kAsn))] (mt idx2 ((some pos2) (let [(afterKey2 (optionOr (stringSlice jsonStr (+ pos2 (stringLength kAsn)) (stringLength jsonStr)) "")) (firstQ (stringIndexOf afterKey2 "\""))] (mt firstQ ((some q1) (let [(afterQ (optionOr (stringSlice afterKey2 (+ q1 1) (stringLength afterKey2)) "")) (secondQ (stringIndexOf afterQ "\""))] (mt secondQ ((some q2) (stringSlice afterQ 0 q2)) ((none) (none))))) ((none) (none))))) ((none) (none)))))))

fn isFallbackEvent? event: UIEvent -> Bool
  (or (= event.componentId "fallback") (= event.action "fallback"))

fn parseNativeEvent rawPayload: String -> UIEvent
  (let [(cOpt (extractJsonField rawPayload "componentId")) (aOpt (extractJsonField rawPayload "action")) (vOpt (extractJsonField rawPayload "value"))] (mt cOpt ((some comp) (mt aOpt ((some act) (UIEvent :componentId comp :action act :value (mt vOpt ((some val) val) ((none) "")))) ((none) (UIEvent :componentId comp :action "none" :value (mt vOpt ((some val) val) ((none) "")))))) ((none) (mt aOpt ((some act) (UIEvent :componentId "unknown" :action act :value (mt vOpt ((some val) val) ((none) "")))) ((none) (UIEvent :componentId "fallback" :action "fallback" :value ""))))))

fn eventToAction event: UIEvent -> s/Action
  (let [(payload (mapSet (mapSet (mapEmpty) "componentId" event.componentId) "value" event.value))] (s/Action :name event.action :payload payload))

fn dispatchBridgeEvent bridge: StateBridge store: s/StateStore rawPayload: String reducer: (fn [(Map String String) s/Action] -> (Map String String)) -> s/StateStore
  (let [(uiEvent (parseNativeEvent rawPayload))] (if (isFallbackEvent? uiEvent) store (let [(action (eventToAction uiEvent))] (s/dispatchAction store action reducer))))

fn serializePatchItem patch: s/StatePatch -> String
  (str "{\"path\": \"" patch.path "\", \"op\": \"" patch.op "\", \"value\": \"" patch.value "\"}")

fn serializePatches version: Int64 patches: (List s/StatePatch) -> String
  (let [(patchStrs (map (fn [(p s/StatePatch)] -> String (serializePatchItem p)) patches)) (joinedPatches (stringJoin patchStrs ", "))] (str "{\"version\": " (stringFromInt64 version) ", \"patches\": [" joinedPatches "]}"))

fn formatBridgeBusEvent bridge: StateBridge serializedPayload: String -> String
  (str "(! bus/event :channel \"" bridge.channel "\"" " :sender \"" bridge.agentId "\"" " :epoch " (stringFromInt64 bridge.lastSyncEpoch) " :payload " serializedPayload ")")
