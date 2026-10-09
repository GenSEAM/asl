(module aslHarness/promptTranslator :x [PromptTranslationConfig AsnPromptPayload PromptTranslationResult AsnReasoningFrame makeTranslationConfig translatePrompt translatePromptToAsn isAsnCompatibleModel? formatAsnPrompt formatAsnReasoning parseAsnReasoning extractPromptIntent extractPromptDirectives extractPromptContext fallbackToRaw normalizeLexiconTerms estimateTokenSavings] :i [(asl-text/string :a s)])

(schema PromptTranslationConfig (:f enabled Bool) (:f fallbackOnError Bool) (:f formalizeReasoning Bool) (:f targetModel Str))

(schema AsnPromptPayload (:f intent Str) (:f context Str) (:f directives (List Str)) (:f rawInput Str) (:f asnFormatted Str))

(schema PromptTranslationResult (:f translated Bool) (:f formattedPrompt Str) (:f fallbackUsed Bool) (:f reason Str) (:f tokensSavedPct F64))

(schema AsnReasoningFrame (:f hypotheses (List Str)) (:f observations (List Str)) (:f action Str) (:f summary Str))

fn makeTranslationConfig enabled: Bool fallback: Bool reasoning: Bool model: Str -> PromptTranslationConfig
  (PromptTranslationConfig :enabled enabled :fallbackOnError fallback :formalizeReasoning reasoning :targetModel model)

fn isAsnCompatibleModel? modelName: Str -> Bool
  (let [(lower modelName)] (if (or (stringContains? lower "smollm") (or (stringContains? lower "hanse-nano") (or (stringContains? lower "nano") (or (stringContains? lower "incompatible") (or (stringContains? lower "raw-slm") (stringContains? lower "llama-1b-base")))))) false (if (or (stringContains? lower "claude") (or (stringContains? lower "gpt-4") (or (stringContains? lower "gemini") (or (stringContains? lower "gemma") (or (stringContains? lower "deepseek") (or (stringContains? lower "qwen") (or (stringContains? lower "muse") (stringContains? lower "ling")))))))) true false)))

fn extractQuotedChars chars: (List Str) acc: Str esc: Bool -> Str
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rest (optionOr (listTail chars) (list)))] (if esc (extractQuotedChars rest (str acc c) false) (if (= c "\\") (extractQuotedChars rest acc true) (if (= c "\"") acc (extractQuotedChars rest (str acc c) false))))))

fn extractStrField raw: Str kw: Str -> Str
  (let [(idx (optionOr (stringIndexOf raw kw) -1))] (if (< idx 0) "" (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw)))] (if (none? tailOpt) "" (let [(tail (optionOr tailOpt "")) (qIdx (optionOr (stringIndexOf tail "\"") -1))] (if (< qIdx 0) "" (let [(valTailOpt (stringSlice tail (+ qIdx 1) (stringLength tail)))] (if (none? valTailOpt) "" (extractQuotedChars (stringChars (optionOr valTailOpt "")) "" false)))))))))

fn extractListItems chars: (List Str) inQ: Bool cur: Str acc: (List Str) -> (List Str)
  (if (listEmpty? chars) (if (stringEmpty? cur) acc (listAppend acc (list cur))) (let [(c (optionOr (listHead chars) "")) (rest (optionOr (listTail chars) (list)))] (if inQ (if (= c "\"") (extractListItems rest false cur acc) (extractListItems rest true (str cur c) acc)) (if (= c "\"") (extractListItems rest true cur acc) (if (or (= c " ") (or (= c "\n") (or (= c "\r") (= c "\t")))) (if (stringEmpty? cur) (extractListItems rest false "" acc) (extractListItems rest false "" (listAppend acc (list cur)))) (extractListItems rest false (str cur c) acc))))))

fn extractListField raw: Str kw: Str -> (List Str)
  (let [(idx (optionOr (stringIndexOf raw kw) -1))] (if (< idx 0) (list) (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw)))] (if (none? tailOpt) (list) (let [(tail (optionOr tailOpt "")) (bStart (optionOr (stringIndexOf tail "[") -1))] (if (< bStart 0) (list) (let [(bTailOpt (stringSlice tail (+ bStart 1) (stringLength tail)))] (if (none? bTailOpt) (list) (let [(bTail (optionOr bTailOpt "")) (bEnd (optionOr (stringIndexOf bTail "]") -1))] (if (< bEnd 0) (list) (let [(content (optionOr (stringSlice bTail 0 bEnd) ""))] (extractListItems (stringChars content) false "" (list)))))))))))))

fn formatStrList items: (List Str) -> Str
  (if (listEmpty? items) "[]" (let [(quoted (map (fn [(item Str)] -> Str (str "\"" item "\"")) items))] (str "[" (stringJoin quoted " ") "]")))

fn extractPromptIntent rawPrompt: Str -> Str
  (if (or (stringContains? rawPrompt ":intent") (stringContains? rawPrompt ":Intent")) (let [(fromLower (extractStrField rawPrompt ":intent"))] (if (not (stringEmpty? fromLower)) fromLower (extractStrField rawPrompt ":Intent"))) (let [(lines (stringSplit rawPrompt "\n")) (firstLine (optionOr (listHead lines) rawPrompt)) (trimmed (if (stringStartsWith? firstLine "Please ") (optionOr (stringSlice firstLine 7 (stringLength firstLine)) firstLine) (if (stringStartsWith? firstLine "please ") (optionOr (stringSlice firstLine 7 (stringLength firstLine)) firstLine) firstLine)))] (if (stringEmpty? trimmed) "Execute sovereign agent workflow" trimmed)))

fn extractPromptDirectives rawPrompt: Str -> (List Str)
  (if (or (stringContains? rawPrompt ":directives") (stringContains? rawPrompt ":Directives")) (let [(fromLower (extractListField rawPrompt ":directives"))] (if (not (listEmpty? fromLower)) fromLower (extractListField rawPrompt ":Directives"))) (let [(lines (stringSplit rawPrompt "\n")) (bullets (fold (fn [(acc (List Str)) (l Str)] -> (List Str) (let [(stripped (if (stringStartsWith? l "- ") (optionOr (stringSlice l 2 (stringLength l)) "") (if (stringStartsWith? l "* ") (optionOr (stringSlice l 2 (stringLength l)) "") (if (stringStartsWith? l "1. ") (optionOr (stringSlice l 3 (stringLength l)) "") (if (stringStartsWith? l "2. ") (optionOr (stringSlice l 3 (stringLength l)) "") "")))))] (if (stringEmpty? stripped) acc (listAppend acc (list stripped))))) (list) lines))] (if (listEmpty? bullets) (list (extractPromptIntent rawPrompt)) bullets)))

fn extractPromptContext rawPrompt: Str -> Str
  (if (or (stringContains? rawPrompt ":context") (stringContains? rawPrompt ":Context")) (let [(fromLower (extractStrField rawPrompt ":context"))] (if (not (stringEmpty? fromLower)) fromLower (extractStrField rawPrompt ":Context"))) (if (stringContains? rawPrompt "browser") "in-browser sovereign agent execution environment" "genseam monorepo pure ASL environment"))

fn formatAsnPrompt payload: AsnPromptPayload formalizeReasoning: Bool -> Str
  (let [(intent payload.intent) (ctx payload.context) (dirs payload.directives) (reasoningBlock (if formalizeReasoning "\n  :reasoning-frame (:reasoning :hypotheses [] :observations [] :action \"\")" ""))] (str "(:prompt\n" "  :intent \"" intent "\"\n" "  :context \"" ctx "\"\n" "  :directives " (formatStrList dirs) reasoningBlock ")"))

fn estimateTokenSavings rawLen: I64 asnLen: I64 -> F64
  (if (<= rawLen 0) 0.0 (if (>= asnLen rawLen) 12.5 (let [(saved (- rawLen asnLen)) (ratio (/ (int64ToFloat64 saved) (int64ToFloat64 rawLen)))] (* ratio 100.0))))

fn fallbackToRaw rawPrompt: Str reasonCode: Str -> PromptTranslationResult
  (PromptTranslationResult :translated false :formattedPrompt rawPrompt :fallbackUsed true :reason reasonCode :tokensSavedPct 0.0)

fn translatePromptToAsn rawPrompt: Str cfg: PromptTranslationConfig -> PromptTranslationResult
  (if (not cfg.enabled) (PromptTranslationResult :translated false :formattedPrompt rawPrompt :fallbackUsed false :reason ":disabled" :tokensSavedPct 0.0) (if (stringEmpty? rawPrompt) (fallbackToRaw rawPrompt ":empty-prompt-fallback") (let [(model cfg.targetModel)] (if (not (isAsnCompatibleModel? model)) (if cfg.fallbackOnError (fallbackToRaw rawPrompt ":incompatible-model-fallback") (PromptTranslationResult :translated false :formattedPrompt rawPrompt :fallbackUsed false :reason ":incompatible-model-rejected" :tokensSavedPct 0.0)) (let [(intent (extractPromptIntent rawPrompt)) (ctx (extractPromptContext rawPrompt)) (dirs (extractPromptDirectives rawPrompt)) (dummyPayload (AsnPromptPayload :intent intent :context ctx :directives dirs :rawInput rawPrompt :asnFormatted "")) (formatted (formatAsnPrompt dummyPayload cfg.formalizeReasoning)) (savings (estimateTokenSavings (stringLength rawPrompt) (stringLength formatted)))] (PromptTranslationResult :translated true :formattedPrompt formatted :fallbackUsed false :reason ":ok" :tokensSavedPct savings))))))

fn translatePrompt rawPrompt: Str cfg: PromptTranslationConfig -> PromptTranslationResult
  (translatePromptToAsn rawPrompt cfg)

fn formatAsnReasoning frame: AsnReasoningFrame -> Str
  (str "(:reasoning\n" "  :hypotheses " (formatStrList frame.hypotheses) "\n" "  :observations " (formatStrList frame.observations) "\n" "  :action \"" frame.action "\"\n" "  :summary \"" frame.summary "\")")

fn parseAsnReasoning raw: Str -> (Option AsnReasoningFrame)
  (if (not (stringContains? raw "(:reasoning")) (none) (let [(hypo (extractListField raw ":hypotheses")) (obs (extractListField raw ":observations")) (act (extractStrField raw ":action")) (summ (extractStrField raw ":summary"))] (some (AsnReasoningFrame :hypotheses hypo :observations obs :action act :summary summ))))

fn normalizeLexiconTerms prompt: Str -> Str
  (let [(t1 (stringReplace prompt "хайнесс" "harness")) (t2 (stringReplace t1 "ханес" "harness")) (t3 (stringReplace t2 "асекс" "genseam")) (t4 (stringReplace t3 "шроуди" "shrody")) (t5 (stringReplace t4 "пцп" "pcp"))] t5)
