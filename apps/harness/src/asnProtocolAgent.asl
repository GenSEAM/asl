(module aslHarness/asnProtocolAgent :x [AsnAgentState AsnToolDefinition AsnToolCall AsnToolReturn AsnParsedCompletion formatAsnToolSchema formatAsnAgentPrompt parseAsnCompletion formatAsnToolReturn] :i [])

(schema AsnAgentState (:f sessionId Str) (:f turns I64) (:f context (List Str)) (:f activeTools (List Str)))

(schema AsnToolDefinition (:f name Str) (:f desc Str) (:f params (List Str)))

(schema AsnToolCall (:f id Str) (:f tool Str) (:f args (List Str)))

(schema AsnToolReturn (:f callId Str) (:f status Str) (:f payload Str))

(schema AsnParsedCompletion (:f intent Str) (:f reveal (List Str)) (:f toolCalls (List AsnToolCall)) (:f delta Str) (:f summary Str))

fn formatStrList items: (List Str) -> Str
  (if (listEmpty? items) "[]" (let [(quoted (map (fn [(s Str)] -> Str (str "\"" s "\"")) items))] (str "[" (stringJoin quoted " ") "]")))

fn formatSingleTool tool: AsnToolDefinition -> Str
  (str "(:tool :name \"" tool.name "\" :desc \"" tool.desc "\" :params " (formatStrList tool.params) ")")

fn formatAsnToolSchema tools: (List AsnToolDefinition) -> Str
  (if (listEmpty? tools) "(:tools [])" (let [(rendered (map (fn [(t AsnToolDefinition)] -> Str (formatSingleTool t)) tools))] (str "(:tools [" (stringJoin rendered " ") "])")))

fn formatAsnAgentPrompt state: AsnAgentState tools: (List AsnToolDefinition) -> Str
  (str "(:asn-prompt :session-id \"" state.sessionId "\" :turns " (stringFromInt64 state.turns) " :ctx " (formatStrList state.context) " :active-tools " (formatStrList state.activeTools) " " (formatAsnToolSchema tools) ")")

fn formatAsnToolReturn ret: AsnToolReturn -> Str
  (str "(:return :call-id \"" ret.callId "\" :status \"" ret.status "\" :payload \"" ret.payload "\")")

fn extractQuotedChars chars: (List Str) acc: Str esc: Bool -> Str
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if esc (extractQuotedChars rst (str acc c) false) (if (= c "\\") (extractQuotedChars rst (str acc c) true) (if (= c "\"") acc (extractQuotedChars rst (str acc c) false))))))

fn extractStrField raw: Str kw: Str -> Str
  (let [(idxOpt (stringIndexOf raw kw))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw))) (tail (optionOr tailOpt "")) (qOpt (stringIndexOf tail "\""))] (mt qOpt ((some qIdx) (let [(valTailOpt (stringSlice tail (+ qIdx 1) (stringLength tail))) (valTail (optionOr valTailOpt ""))] (extractQuotedChars (stringChars valTail) "" false))) ((none) "")))) ((none) "")))

fn extractListItems chars: (List Str) inStr: Bool cur: Str acc: (List Str) -> (List Str)
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if inStr (if (= c "\"") (extractListItems rst false "" (listAppend acc (list cur))) (extractListItems rst true (str cur c) acc)) (if (= c "\"") (extractListItems rst true "" acc) (extractListItems rst false "" acc)))))

fn extractListField raw: Str kw: Str -> (List Str)
  (let [(idxOpt (stringIndexOf raw kw))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw))) (tail (optionOr tailOpt "")) (bStart (stringIndexOf tail "["))] (mt bStart ((some bIdx) (let [(bTailOpt (stringSlice tail (+ bIdx 1) (stringLength tail))) (bTail (optionOr bTailOpt "")) (bEnd (stringIndexOf bTail "]"))] (mt bEnd ((some endIdx) (let [(content (optionOr (stringSlice bTail 0 endIdx) ""))] (extractListItems (stringChars content) false "" (list)))) ((none) (list))))) ((none) (list))))) ((none) (list))))

fn findMatchingParenChars chars: (List Str) depth: I64 inQuote: Bool escape: Bool idx: I64 -> (Option I64)
  (if (listEmpty? chars) (none) (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if escape (findMatchingParenChars rst depth inQuote false (+ idx 1)) (if inQuote (if (= c "\\") (findMatchingParenChars rst depth true true (+ idx 1)) (if (= c "\"") (findMatchingParenChars rst depth false false (+ idx 1)) (findMatchingParenChars rst depth true false (+ idx 1)))) (if (= c "\"") (findMatchingParenChars rst depth true false (+ idx 1)) (if (= c "(") (findMatchingParenChars rst (+ depth 1) false false (+ idx 1)) (if (= c ")") (if (= depth 1) (some idx) (findMatchingParenChars rst (- depth 1) false false (+ idx 1))) (findMatchingParenChars rst depth false false (+ idx 1)))))))))

fn findMatchingParen raw: Str start: I64 -> (Option I64)
  (let [(len (stringLength raw))] (if (>= (+ start 1) len) (none) (let [(tailOpt (stringSlice raw (+ start 1) len))] (mt tailOpt ((some tail) (findMatchingParenChars (stringChars tail) 1 false false (+ start 1))) ((none) (none))))))

fn findNextCallIndex raw: Str startIdx: I64 -> (Option I64)
  (let [(len (stringLength raw))] (if (>= startIdx len) (none) (let [(slice (optionOr (stringSlice raw startIdx len) "")) (idxCall (stringIndexOf slice "(:call")) (idxToolCall (stringIndexOf slice "(:tool-call"))] (mt idxCall ((some c) (mt idxToolCall ((some tc) (if (< c tc) (some (+ startIdx c)) (some (+ startIdx tc)))) ((none) (some (+ startIdx c))))) ((none) (mt idxToolCall ((some tc) (some (+ startIdx tc))) ((none) (none))))))))

fn parseSingleToolCall callStr: Str -> AsnToolCall
  (let [(id (extractStrField callStr ":id")) (toolRaw (extractStrField callStr ":tool")) (tool (if (stringEmpty? toolRaw) (extractStrField callStr ":name") toolRaw)) (argsRaw (extractListField callStr ":args")) (args (if (listEmpty? argsRaw) (extractListField callStr ":params") argsRaw))] (AsnToolCall :id id :tool tool :args args))

fn parseToolCallsLoop raw: Str offset: I64 acc: (List AsnToolCall) -> (List AsnToolCall)
  (let [(nextOpt (findNextCallIndex raw offset))] (mt nextOpt ((none) acc) ((some callStart) (let [(closeOpt (findMatchingParen raw callStart))] (mt closeOpt ((none) acc) ((some callEnd) (let [(callSlice (optionOr (stringSlice raw callStart (+ callEnd 1)) "")) (parsed (parseSingleToolCall callSlice)) (newAcc (listAppend acc (list parsed)))] (parseToolCallsLoop raw (+ callEnd 1) newAcc))))))))

fn parseAsnCompletion rawCompletion: Str -> AsnParsedCompletion
  (let [(intent (extractStrField rawCompletion ":intent")) (reveal (extractListField rawCompletion ":reveal")) (calls (parseToolCallsLoop rawCompletion 0 (list))) (delta (extractStrField rawCompletion ":delta")) (summaryRaw (extractStrField rawCompletion ":summary")) (summary (if (stringEmpty? summaryRaw) (extractStrField rawCompletion ":desc") summaryRaw))] (AsnParsedCompletion :intent intent :reveal reveal :toolCalls calls :delta delta :summary summary))
