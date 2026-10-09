(module aslHarness/slmBrowserProfile :x [SlmBrowserTool SlmAffirmativeSchema FsmDelimiterMask SlmBrowserProfile makeBrowserSlmTools calculateSchemaTokens makeBrowserSlmSchema initFsmDelimiterMask fsmFeedChar validateSlmTokenStream formatSlmBrowserPriming makeBrowserSlmProfile validateBrowserModelCeiling makeNanoSlmTools makeNanoSlmSchema makeNanoBrowserSlmProfile] :i [])

(schema SlmBrowserTool (:f name Str) (:f signature Str) (:f summary Str) (:f tokenCost I64))

(schema SlmAffirmativeSchema (:f tools (List SlmBrowserTool)) (:f totalTokens I64) (:f maxTools I64) (:f affirmativeRule Str))

(schema FsmDelimiterMask (:f depth I64) (:f inString Bool) (:f isEscaped Bool) (:f isValid Bool) (:f charCount I64) (:f maxDepth I64) (:f errorReason Str))

(schema SlmBrowserProfile (:f modelName Str) (:f contextBudget I64) (:f primingTokenCount I64) (:f primingPrompt Str) (:f schema SlmAffirmativeSchema) (:f fsmMask FsmDelimiterMask))

fn makeBrowserSlmTools -> (List SlmBrowserTool)
  (let [(tDom (SlmBrowserTool :name "get_dom" :signature "(:act :get_dom)" :summary "Inspect active DOM outline" :tokenCost 14)) (tClick (SlmBrowserTool :name "click" :signature "(:act :click :selector Str)" :summary "Dispatch click to selector" :tokenCost 16)) (tType (SlmBrowserTool :name "type" :signature "(:act :type :selector Str :text Str)" :summary "Input text into targeted field" :tokenCost 18)) (tEval (SlmBrowserTool :name "eval" :signature "(:act :eval :expression Str)" :summary "Evaluate JS in isolated sandbox" :tokenCost 16))] (list tDom tClick tType tEval))

fn calculateSchemaTokens tools: (List SlmBrowserTool) -> I64
  (fold (fn [(acc I64) (t SlmBrowserTool)] -> I64 (+ acc t.tokenCost)) 0 tools)

fn makeBrowserSlmSchema -> SlmAffirmativeSchema
  (let [(tools (makeBrowserSlmTools)) (tokens (calculateSchemaTokens tools))] (SlmAffirmativeSchema :tools tools :totalTokens tokens :maxTools 4 :affirmativeRule "Emit exactly one affirmative S-expression action. Never hallucinate non-existent tools."))

fn initFsmDelimiterMask maxDepth: I64 -> FsmDelimiterMask
  (FsmDelimiterMask :depth 0 :inString false :isEscaped false :isValid true :charCount 0 :maxDepth maxDepth :errorReason "")

fn fsmFeedChar mask: FsmDelimiterMask ch: Str -> FsmDelimiterMask
  (if (not mask.isValid) mask (let [(depth mask.depth) (inStr mask.inString) (escaped mask.isEscaped) (count (+ mask.charCount 1)) (maxD mask.maxDepth)] (if inStr (if escaped (FsmDelimiterMask :depth depth :inString true :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason "") (if (= ch "\\") (FsmDelimiterMask :depth depth :inString true :isEscaped true :isValid true :charCount count :maxDepth maxD :errorReason "") (if (= ch "\"") (FsmDelimiterMask :depth depth :inString false :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason "") (FsmDelimiterMask :depth depth :inString true :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason "")))) (if (= ch "\"") (FsmDelimiterMask :depth depth :inString true :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason "") (cond ((or (= ch "(") (= ch "[")) (let [(nextDepth (+ depth 1))] (if (> nextDepth maxD) (FsmDelimiterMask :depth nextDepth :inString false :isEscaped false :isValid false :charCount count :maxDepth maxD :errorReason "Max nesting depth exceeded") (FsmDelimiterMask :depth nextDepth :inString false :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason "")))) ((or (= ch ")") (= ch "]")) (if (<= depth 0) (FsmDelimiterMask :depth -1 :inString false :isEscaped false :isValid false :charCount count :maxDepth maxD :errorReason "Unmatched closing delimiter") (FsmDelimiterMask :depth (- depth 1) :inString false :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason ""))) (else (FsmDelimiterMask :depth depth :inString false :isEscaped false :isValid true :charCount count :maxDepth maxD :errorReason "")))))))

fn validateSlmTokenStream mask: FsmDelimiterMask stream: Str -> FsmDelimiterMask
  (let [(chars (stringChars stream)) (stepped (fold (fn [(acc FsmDelimiterMask) (c Str)] -> FsmDelimiterMask (fsmFeedChar acc c)) mask chars))] (if (not stepped.isValid) stepped (if stepped.inString (FsmDelimiterMask :depth stepped.depth :inString true :isEscaped stepped.isEscaped :isValid false :charCount stepped.charCount :maxDepth stepped.maxDepth :errorReason "Unclosed string literal at end of stream") (if (> stepped.depth 0) (FsmDelimiterMask :depth stepped.depth :inString false :isEscaped stepped.isEscaped :isValid false :charCount stepped.charCount :maxDepth stepped.maxDepth :errorReason "Unclosed delimiter at end of stream") stepped))))

fn formatSlmBrowserPriming model: Str schema: SlmAffirmativeSchema -> Str
  (str "(:slm-profile :model \"" model "\" :priming 118 :contract \"Addie Browser SLM Agent. Allowed actions: get_dom click type eval. Emit exactly one valid S-expression. Zero prose.\")")

fn makeBrowserSlmProfile modelName: Str contextBudget: I64 -> SlmBrowserProfile
  (let [(schema (makeBrowserSlmSchema)) (priming (formatSlmBrowserPriming modelName schema)) (mask (initFsmDelimiterMask 16))] (SlmBrowserProfile :modelName modelName :contextBudget contextBudget :primingTokenCount 118 :primingPrompt priming :schema schema :fsmMask mask))

fn validateBrowserModelCeiling modelName: Str -> Bool
  (if (or (stringContains? modelName "7B") (or (stringContains? modelName "7b") (or (stringContains? modelName "8B") (or (stringContains? modelName "8b") (or (stringContains? modelName "9B") (or (stringContains? modelName "9b") (or (stringContains? modelName "14B") (or (stringContains? modelName "14b") (or (stringContains? modelName "31B") (or (stringContains? modelName "31b") (or (stringContains? modelName "70B") (stringContains? modelName "70b")))))))))))) false true)

fn makeNanoSlmTools -> (List SlmBrowserTool)
  (let [(tTag (SlmBrowserTool :name "tag" :signature "(:act :tag :text Str :label Str)" :summary "Classify token or phrase" :tokenCost 14)) (tMatch (SlmBrowserTool :name "match" :signature "(:act :match :pattern Str :target Str)" :summary "Extract regex or token match" :tokenCost 16))] (list tTag tMatch))

fn makeNanoSlmSchema -> SlmAffirmativeSchema
  (let [(tools (makeNanoSlmTools)) (tokens (calculateSchemaTokens tools))] (SlmAffirmativeSchema :tools tools :totalTokens tokens :maxTools 2 :affirmativeRule "Emit single token classification or match action. Never emit nested forms."))

fn makeNanoBrowserSlmProfile modelName: Str contextBudget: I64 -> SlmBrowserProfile
  (let [(schema (makeNanoSlmSchema)) (priming (str "(:nano-profile :model \"" modelName "\" :weight \"100MB\" :priming 30 :contract \"Nano Agent. Allowed: tag match.\")")) (mask (initFsmDelimiterMask 4))] (SlmBrowserProfile :modelName modelName :contextBudget contextBudget :primingTokenCount 30 :primingPrompt priming :schema schema :fsmMask mask))
