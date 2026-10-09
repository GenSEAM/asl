(module aslHarness/llmProtocol :x [LLMProtocolConfig LLMResponseEnvelope ProtocolEnvelope formatProtocolEnvelope formatAffirmativeEnvelope parseProtocolResponse parseAffirmativeResponse] :i [(asl-parser/balance :a bal)])

(schema LLMProtocolConfig (:f model Str) (:f position Str) (:f targetTokens I64) (:f systemPrompt Str) (:f schemaMode Str))

(schema LLMResponseEnvelope (:f intent Str) (:f refs (List Str)) (:f markers (List Str)) (:f delta Str) (:f state Str) (:f d Str) (:f valid Bool) (:f errorCode Str))

(schema ProtocolEnvelope (:f intent Str) (:f delta Str) (:f gateCheck Str) (:f d Str) (:f valid Bool) (:f errorCode Str))

fn formatProtocolEnvelope cfg: LLMProtocolConfig -> Str
  (str "(:protocol-envelope :version \"1.2\" :position \"" cfg.position "\" :model \"" cfg.model "\" :mode \"" cfg.schemaMode "\" (:affirmative-schema (:intent :delta :gate-check :d)) (:rules [:pure-asn :dense-deltas]))")


fn formatAffirmativeEnvelope intent: Str -> Str
  (str "(:affirmative-envelope :intent \"" intent "\" (:affirmative-schema (:intent :delta :gate-check :d)))")

fn extractStrField raw: Str kw: Str -> Str
  (let [(needle (str kw " ")) (idxOpt (let [(i (stringIndexOf raw needle))] (if (some? i) i (stringIndexOf raw (str kw "\"")))))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw))) (tail (optionOr tailOpt "")) (qOpt (stringIndexOf tail "\""))] (mt qOpt ((some qIdx) (let [(valTailOpt (stringSlice tail (+ qIdx 1) (stringLength tail))) (valTail (optionOr valTailOpt "")) (q2Opt (stringIndexOf valTail "\""))] (mt q2Opt ((some q2Idx) (optionOr (stringSlice valTail 0 q2Idx) "")) ((none) "")))) ((none) "")))) ((none) "")))

fn extractDeltaChars chars: (List Str) acc: Str esc: Bool -> Str
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if esc (extractDeltaChars rst (stringConcat acc c) false) (if (= c "\\") (extractDeltaChars rst (stringConcat acc c) true) (if (= c "\"") acc (extractDeltaChars rst (stringConcat acc c) false))))))

fn extractDeltaField raw: Str -> Str
  (let [(idxOpt (stringIndexOf raw ":delta"))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength ":delta")) (stringLength raw))) (tail (optionOr tailOpt "")) (qOpt (stringIndexOf tail "\""))] (mt qOpt ((some qIdx) (let [(valTailOpt (stringSlice tail (+ qIdx 1) (stringLength tail))) (valTail (optionOr valTailOpt ""))] (extractDeltaChars (stringChars valTail) "" false))) ((none) "")))) ((none) "")))

fn extractListItems chars: (List Str) inStr: Bool cur: Str acc: (List Str) -> (List Str)
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if inStr (if (= c "\"") (extractListItems rst false "" (listAppend acc (list cur))) (extractListItems rst true (stringConcat cur c) acc)) (if (= c "\"") (extractListItems rst true "" acc) (extractListItems rst false "" acc)))))

fn extractListField raw: Str kw: Str -> (List Str)
  (let [(idxOpt (stringIndexOf raw kw))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw))) (tail (optionOr tailOpt "")) (bStart (stringIndexOf tail "["))] (mt bStart ((some bIdx) (let [(bTailOpt (stringSlice tail (+ bIdx 1) (stringLength tail))) (bTail (optionOr bTailOpt "")) (bEnd (stringIndexOf bTail "]"))] (mt bEnd ((some endIdx) (let [(content (optionOr (stringSlice bTail 0 endIdx) ""))] (extractListItems (stringChars content) false "" (list)))) ((none) (list))))) ((none) (list))))) ((none) (list))))

fn checkDelimitersBalanced chars: (List Str) p: I64 b: I64 q: Bool -> Bool
  (bal/isDelimiterBalanced? (stringJoin chars ""))

fn isFillerPhrase? s: Str -> Bool
  (or (stringContains? s "Sure,") (or (stringContains? s "Certainly") (or (stringContains? s "Here is") (or (stringContains? s "Here's") (or (stringContains? s "I'd be happy") (stringContains? s "I will now"))))))

fn hasCodeFence? s: Str -> Bool
  (stringContains? s "`")

fn parseProtocolResponse raw: Str -> LLMResponseEnvelope
  (let [(trimmed (stringTrim raw))] (if (stringEmpty? trimmed) (LLMResponseEnvelope :intent "" :refs (list) :markers (list) :delta "" :state "" :d "" :valid false :errorCode "ERR_EMPTY_PAYLOAD") (if (hasCodeFence? raw) (LLMResponseEnvelope :intent "" :refs (list) :markers (list) :delta "" :state "" :d "" :valid false :errorCode "ERR_MARKDOWN_FENCE") (if (or (isFillerPhrase? raw) (not (stringStartsWith? trimmed "("))) (LLMResponseEnvelope :intent "" :refs (list) :markers (list) :delta "" :state "" :d "" :valid false :errorCode "ERR_CONVERSATIONAL_FILLER") (if (not (bal/isDelimiterBalanced? raw)) (LLMResponseEnvelope :intent "" :refs (list) :markers (list) :delta "" :state "" :d "" :valid false :errorCode "ERR_UNBALANCED_DELIMITERS") (LLMResponseEnvelope :intent (extractStrField raw ":intent") :refs (extractListField raw ":refs") :markers (extractListField raw ":markers") :delta (extractDeltaField raw) :state (extractStrField raw ":state") :d (extractStrField raw ":d") :valid true :errorCode ""))))))

fn parseAffirmativeResponse raw: Str -> ProtocolEnvelope
  (let [(trimmed (stringTrim raw))] (if (stringEmpty? trimmed) (ProtocolEnvelope :intent "" :delta "" :gateCheck "" :d "" :valid false :errorCode "ERR_EMPTY_PAYLOAD") (if (hasCodeFence? raw) (ProtocolEnvelope :intent "" :delta "" :gateCheck "" :d "" :valid false :errorCode "ERR_MARKDOWN_FENCE") (if (or (isFillerPhrase? raw) (not (stringStartsWith? trimmed "("))) (ProtocolEnvelope :intent "" :delta "" :gateCheck "" :d "" :valid false :errorCode "ERR_CONVERSATIONAL_FILLER") (if (not (bal/isDelimiterBalanced? raw)) (ProtocolEnvelope :intent "" :delta "" :gateCheck "" :d "" :valid false :errorCode "ERR_UNBALANCED_DELIMITERS") (ProtocolEnvelope :intent (extractStrField raw ":intent") :delta (extractDeltaField raw) :gateCheck (extractStrField raw ":gate-check") :d (extractStrField raw ":d") :valid true :errorCode ""))))))
