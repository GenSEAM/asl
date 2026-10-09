(module aslHarness/streamDemuxer :x [StreamDemuxer DemuxResult ReasoningQuarantine demuxLlmStream normalizeToolcallOutput makeStreamDemuxer makeDemuxResult makeQuarantine extractThoughtChannel extractContentChannel] :i [(asl-text/text :a txt)])

(schema ReasoningQuarantine (:f thoughtTokens Str) (:f quarantined Bool) (:f tokenCount I64))

(schema DemuxResult (:f content Str) (:f quarantine ReasoningQuarantine) (:f hasToolcall Bool) (:f modelFamily Str))

(schema StreamDemuxer (:f modelId Str) (:f stripThoughts Bool) (:f normalizeJson Bool))

fn makeQuarantine thought: Str quarantined: Bool tokens: I64 -> ReasoningQuarantine
  (ReasoningQuarantine :thoughtTokens thought :quarantined quarantined :tokenCount tokens)

fn makeStreamDemuxer model: Str strip: Bool norm: Bool -> StreamDemuxer
  (StreamDemuxer :modelId model :stripThoughts strip :normalizeJson norm)

fn makeDemuxResult content: Str quarantine: ReasoningQuarantine hasTc: Bool family: Str -> DemuxResult
  (DemuxResult :content content :quarantine quarantine :hasToolcall hasTc :modelFamily family)

fn extractThoughtChannel raw: Str -> ReasoningQuarantine
  (cond ((stringEmpty? raw) (makeQuarantine "" false 0)) ((and (stringContains? raw "<think>") (stringContains? raw "</think>")) (let [(p1 (stringSplit raw "<think>")) (rest (optionOr (listHead (listDrop p1 1)) "")) (p2 (stringSplit rest "</think>")) (think (optionOr (listHead p2) "")) (trimmed (stringTrim think))] (makeQuarantine trimmed true (txt/estimateTokens trimmed)))) ((and (stringContains? raw "[THOUGHT]") (stringContains? raw "[/THOUGHT]")) (let [(p1 (stringSplit raw "[THOUGHT]")) (rest (optionOr (listHead (listDrop p1 1)) "")) (p2 (stringSplit rest "[/THOUGHT]")) (think (optionOr (listHead p2) "")) (trimmed (stringTrim think))] (makeQuarantine trimmed true (txt/estimateTokens trimmed)))) (true (makeQuarantine "" false 0)))

fn extractContentChannel raw: Str -> Str
  (cond ((stringEmpty? raw) "") ((and (stringContains? raw "<think>") (stringContains? raw "</think>")) (let [(p1 (stringSplit raw "<think>")) (pre (optionOr (listHead p1) "")) (rest (optionOr (listHead (listDrop p1 1)) "")) (p2 (stringSplit rest "</think>")) (post (optionOr (listHead (listDrop p2 1)) ""))] (stringTrim (str pre post)))) ((and (stringContains? raw "[THOUGHT]") (stringContains? raw "[/THOUGHT]")) (let [(p1 (stringSplit raw "[THOUGHT]")) (pre (optionOr (listHead p1) "")) (rest (optionOr (listHead (listDrop p1 1)) "")) (p2 (stringSplit rest "[/THOUGHT]")) (post (optionOr (listHead (listDrop p2 1)) ""))] (stringTrim (str pre post)))) (true (stringTrim raw)))

fn normalizeToolcallOutput raw: Str -> Str
  (let [(trimmed (stringTrim raw))] (cond ((stringEmpty? trimmed) "") ((stringStartsWith? trimmed "(:call") trimmed) ((stringContains? trimmed "name:") (let [(s1 (stringReplace trimmed "{" "(:call ")) (s2 (stringReplace s1 "}" ")")) (s3 (stringReplace s2 "name:" ":tool")) (s4 (stringReplace s3 "arguments:" ":args")) (s5 (stringReplace s4 "parameters:" ":args"))] (stringTrim s5))) (true trimmed)))

fn demuxLlmStream demuxer: StreamDemuxer raw: Str -> DemuxResult
  (let [(quarantine (extractThoughtChannel raw)) (rawContent (if demuxer.stripThoughts (extractContentChannel raw) raw)) (cleanContent (if demuxer.normalizeJson (normalizeToolcallOutput rawContent) rawContent)) (hasTc (or (stringContains? cleanContent "(:call") (stringContains? cleanContent "tool_calls"))) (model demuxer.modelId)] (makeDemuxResult cleanContent quarantine hasTc model))
