(module aslAgentBus/gateway :x [GatewayChannel MultiplexedFrame GatewayInspectionVerdict demuxStreamContent detectEshViolation calculateLcsGrounding inspectGatewayTurn formatGatewayVerdict isAsnToolCall? formatAsnProtocolHeaders adaptAnthropicRequest formatAnthropicResponse proxyContractToMesh validateRelayWritePermission] :i [(mesh :a mesh) (cluster :a cluster)])

(enum GatewayChannel (:c channelUi [] "Channel A: direct conversational output") (:c channelThink [] "Channel B: quarantined CoT reasoning") (:c channelTool [] "Channel C: structured tool execution frames"))

(schema MultiplexedFrame (:f channel GatewayChannel) (:f content Str) (:f metadata Str))

(schema GatewayInspectionVerdict (:f allowed Bool) (:f quarantinedReasoning Str) (:f sanitizedUserOutput Str) (:f toolFrames (List Str)) (:f rejectionReason Str))

fn extractThinkBlocks text: Str -> (Pair Str Str)
  (let [(openTag "<think>") (closeTag "</think>") (idxOpen (stringIndexOf text openTag))] (mt idxOpen ((none) (pair "" text)) ((some o) (let [(afterOpen (optionOr (stringSlice text (+ o 7) (stringLength text)) "")) (idxClose (stringIndexOf afterOpen closeTag))] (mt idxClose ((none) (pair (stringTrim afterOpen) (optionOr (stringSlice text 0 o) ""))) ((some c) (let [(thinkContent (optionOr (stringSlice afterOpen 0 c) "")) (prefix (optionOr (stringSlice text 0 o) "")) (suffix (optionOr (stringSlice afterOpen (+ c 8) (stringLength afterOpen)) "")) (remaining (stringTrim (str prefix " " suffix)))] (pair (stringTrim thinkContent) remaining))))))))

fn isAsnToolCall? expr: Str -> Bool
  (let [(trimmed (stringTrim expr))] (or (stringStartsWith? trimmed "(call :tool") (or (stringStartsWith? trimmed "(:call :tool") (stringStartsWith? trimmed "(:call "))))

fn formatAsnProtocolHeaders -> (List (Pair Str Str))
  (list (pair "X-ASL-Wire-Protocol" "asn/1.0") (pair "X-Tool-Call-Dialect" "asn-sexpr") (pair "Accept" "application/asn+sexpr, application/json"))

fn extractToolCalls text: Str -> (Pair (List Str) Str)
  (let [(lines (stringSplit text "\n")) (res (fold (fn [(acc (pair (List Str) (List Str))) (ln Str)] -> (Pair (List Str) (List Str)) (let [(trimmed (stringTrim ln))] (if (isAsnToolCall? trimmed) (pair (listAppend (pairFirst acc) (list trimmed)) (pairSecond acc)) (pair (pairFirst acc) (listAppend (pairSecond acc) (list ln)))))) (pair (list) (list)) lines))] (pair (pairFirst res) (stringTrim (stringJoin (pairSecond res) "\n"))))

fn demuxStreamContent rawStream: Str -> (List MultiplexedFrame)
  (let [(thinkSplit (extractThinkBlocks rawStream)) (thinkContent (pairFirst thinkSplit)) (nonThink (pairSecond thinkSplit)) (toolSplit (extractToolCalls nonThink)) (toolCalls (pairFirst toolSplit)) (uiContent (pairSecond toolSplit)) (frames0 (list))] (let [(frames1 (if (stringEmpty? thinkContent) frames0 (listAppend frames0 (list (MultiplexedFrame :channel (channelThink) :content thinkContent :metadata "quarantined-cot"))))) (frames2 (fold (fn [(acc (List MultiplexedFrame)) (tc Str)] -> (List MultiplexedFrame) (listAppend acc (list (MultiplexedFrame :channel (channelTool) :content tc :metadata "structured-call")))) frames1 toolCalls)) (frames3 (if (stringEmpty? uiContent) frames2 (listAppend frames2 (list (MultiplexedFrame :channel (channelUi) :content uiContent :metadata "user-facing")))))] frames3))

fn detectEshViolation text: Str -> Bool
  (let [(lower (stringLower text))] (or (stringContains? lower "i have run the tests and they pass") (or (stringContains? lower "all tests pass") (or (stringContains? lower "all tests passed") (or (stringContains? lower "tests are passing") (or (stringContains? lower "i ran the tests and verified") (or (stringContains? lower "everything is verified and passing") (or (stringContains? lower "build succeeded cleanly") (stringContains? lower "test suite passing cleanly")))))))))

fn calculateLcsGrounding modelSnippet: Str referenceSource: Str -> F64
  (let [(trimmedSnippet (stringTrim modelSnippet))] (cond ((stringEmpty? trimmedSnippet) 1.0) ((stringEmpty? referenceSource) 0.0) ((stringContains? referenceSource trimmedSnippet) 1.0) (else (let [(lines (filter (fn [(l Str)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit trimmedSnippet "\n"))) (total (listLength lines))] (if (<= total 0) 1.0 (let [(matched (fold (fn [(count I64) (ln Str)] -> I64 (if (stringContains? referenceSource (stringTrim ln)) (+ count 1) count)) 0 lines))] (/ (int64ToFloat64 matched) (int64ToFloat64 total))))))))

fn inspectGatewayTurn rawCompletion: Str hasVerifiedExecution: Bool -> GatewayInspectionVerdict
  (let [(frames (demuxStreamContent rawCompletion)) (thinks (filter (fn [(f MultiplexedFrame)] -> Bool (mt f.channel ((channelThink) true) ((channelUi) false) ((channelTool) false))) frames)) (tools (filter (fn [(f MultiplexedFrame)] -> Bool (mt f.channel ((channelTool) true) ((channelUi) false) ((channelThink) false))) frames)) (uis (filter (fn [(f MultiplexedFrame)] -> Bool (mt f.channel ((channelUi) true) ((channelThink) false) ((channelTool) false))) frames)) (quarantined (stringJoin (map (fn [(f MultiplexedFrame)] -> Str f.content) thinks) "\n")) (userOutput (stringJoin (map (fn [(f MultiplexedFrame)] -> Str f.content) uis) "\n")) (toolCalls (map (fn [(f MultiplexedFrame)] -> Str f.content) tools))] (if (and (detectEshViolation userOutput) (not hasVerifiedExecution)) (GatewayInspectionVerdict :allowed false :quarantinedReasoning quarantined :sanitizedUserOutput userOutput :toolFrames toolCalls :rejectionReason "Verbal self-declared execution without verified runtime proof (ESH violation)") (GatewayInspectionVerdict :allowed true :quarantinedReasoning quarantined :sanitizedUserOutput userOutput :toolFrames toolCalls :rejectionReason "")))

fn formatGatewayVerdict verdict: GatewayInspectionVerdict -> Str
  (if verdict.allowed (str "(:gateway-verdict :allowed true :tool-count " (stringFromInt64 (listLength verdict.toolFrames)) ")") (str "(:gateway-verdict :allowed false :reason \"" verdict.rejectionReason "\")"))

fn adaptAnthropicRequest messagesJson: Str toolsJson: Str -> Str
  (str "(:anthropic-turn :messages " messagesJson " :tools " toolsJson ")")

fn formatAnthropicResponse verdict: GatewayInspectionVerdict model: Str -> Str
  (if verdict.allowed (let [(content verdict.sanitizedUserOutput) (tools verdict.toolFrames)] (if (listEmpty? tools) (str "{\"id\": \"msg_asl\", \"type\": \"message\", \"role\": \"assistant\", \"model\": \"" model "\", \"content\": [{\"type\": \"text\", \"text\": \"" (stringReplace content "\"" "\\\"") "\"}]}") (let [(tc (optionOr (listHead tools) ""))] (str "{\"id\": \"msg_asl\", \"type\": \"message\", \"role\": \"assistant\", \"model\": \"" model "\", \"content\": [{\"type\": \"text\", \"text\": \"" (stringReplace content "\"" "\\\"") "\"}, {\"type\": \"tool_use\", \"id\": \"call_asl\", \"name\": \"tool\", \"input\": {\"call\": \"" (stringReplace tc "\"" "\\\"") "\"}}]}")))) (str "{\"id\": \"msg_err\", \"type\": \"error\", \"error\": {\"type\": \"gateway_rejection\", \"message\": \"" verdict.rejectionReason "\"}}"))

fn proxyContractToMesh contract: mesh/TaskContract targetCluster: Str isReachable: Bool -> Str
  (if isReachable (str "(:control-dispatch :task-id \"" contract.taskId "\" :cluster \"" targetCluster "\" :vfs \"mem://vfs/" contract.taskId "\" :status \"proxied\")") (str "(:remote-unreachable :cluster \"" targetCluster "\" :fallback \"local-vfs\" :preserved-contract \"" contract.taskId "\")"))

fn validateRelayWritePermission reg: cluster/RelayLeaseRegistry logicalPath: Str sessionId: Str digest: Str now: I64 -> (Result Bool Str)
  (cluster/relayVerifyWrite reg logicalPath sessionId digest now)
