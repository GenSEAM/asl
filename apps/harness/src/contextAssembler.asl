(module aslHarness/contextAssembler :x [ContextBlock AgentCtxOp ContextAssemblyConfig AssembledPrompt makeContextBlock makeAgentCtxOp makeDefaultConfig totalBlocksTokens formatContextBlocks assembleBaselineContext assembleReceiptsContext assembleWatermarkContext assembleJitContext hydrateJitBlocks assembleAgentDirectedContext applyUniversalDefaultCanvas isCoreBlock? isKnowledgeBlock? isDeltaBlock? isOtherCanvasBlock? parseAgentCtxOp assemblePrompt] :i [(compactor :a comp) (contextPriority :a cp) (engineGateway :a eg) (asl-text/text :a txt)])

(schema ContextBlock (:f id Str) (:f kind Str) (:f tokens I64) (:f payload Str))

(schema AgentCtxOp (:f retain (List Str)) (:f evict (List Str)) (:f prefetch (List Str)))

(schema ContextAssemblyConfig (:f strategy Str) (:f tokenCeiling I64) (:f keepRecent I64))

(schema AssembledPrompt (:f strategy Str) (:f totalTokens I64) (:f promptStr Str) (:f retainedCount I64) (:f evictedCount I64))

fn makeContextBlock id: Str kind: Str tokens: I64 payload: Str -> ContextBlock
  (let [(tok (if (> tokens 0) tokens (txt/estimateTokens payload)))] (ContextBlock :id id :kind kind :tokens tok :payload payload))

fn makeAgentCtxOp retain: (List Str) evict: (List Str) prefetch: (List Str) -> AgentCtxOp
  (AgentCtxOp :retain retain :evict evict :prefetch prefetch)

fn makeDefaultConfig strategy: Str -> ContextAssemblyConfig
  (ContextAssemblyConfig :strategy strategy :tokenCeiling 4096 :keepRecent 2)

fn formatContextBlocks blocks: (List ContextBlock) -> Str
  (if (listEmpty? blocks) "(:ctx [])" (let [(lines (map (fn [(b ContextBlock)] -> Str (if (or (= b.kind "prefetched-ast") (stringStartsWith? b.payload "(")) (str "    (:block :id \"" b.id "\" :kind \"" b.kind "\" :tokens " (stringFromInt64 b.tokens) " :data " b.payload ")") (let [(escaped (stringReplace (stringReplace b.payload "\\" "\\\\") "\"" "\\\""))] (str "    (:block :id \"" b.id "\" :kind \"" b.kind "\" :tokens " (stringFromInt64 b.tokens) " :data \"" escaped "\")")))) blocks))] (str "(:ctx [\n" (stringJoin lines "\n") "\n  ])")))

(schema BlockAccumulator (:f retained (List ContextBlock)) (:f evicted (List ContextBlock)) (:f tokens I64))

fn accumulateBlocksLoop remaining: (List ContextBlock) ceiling: I64 acc: BlockAccumulator -> BlockAccumulator
  (if (listEmpty? remaining) acc (let [(defaultB (ContextBlock :id "" :kind "" :tokens 0 :payload "")) (headB (optionOr (listHead remaining) defaultB)) (tailB (optionOr (listTail remaining) (list))) (tok headB.tokens)] (if (<= (+ acc.tokens tok) ceiling) (accumulateBlocksLoop tailB ceiling (with acc :retained (listAppend acc.retained (list headB)) :tokens (+ acc.tokens tok))) (accumulateBlocksLoop tailB ceiling (with acc :evicted (listAppend acc.evicted (list headB)))))))

fn assembleBaselineContext blocks: (List ContextBlock) ceiling: I64 -> AssembledPrompt
  (let [(acc (BlockAccumulator :retained (list) :evicted (list) :tokens 0)) (res (accumulateBlocksLoop blocks ceiling acc)) (retained res.retained) (pStr (formatContextBlocks retained))] (AssembledPrompt :strategy "baseline" :totalTokens res.tokens :promptStr pStr :retainedCount (listLength retained) :evictedCount (listLength res.evicted)))

fn isHistoryBlock? b: ContextBlock -> Bool
  (let [(k b.kind)] (or (= k "history") (or (= k "turn") (= k "tool-return"))))

fn compactBlockIfHistory b: ContextBlock -> ContextBlock
  (if (isHistoryBlock? b) (let [(compacted (comp/compactReceipt b.payload)) (tok (txt/estimateTokens compacted))] (with b :kind "receipt" :tokens tok :payload compacted)) b)

(schema HistoryFoldAcc (:f count I64) (:f blocks (List ContextBlock)))

fn processReceiptsBlocks blocks: (List ContextBlock) keepRecent: I64 -> (List ContextBlock)
  (let [(historyBlocks (filter (fn [(b ContextBlock)] -> Bool (isHistoryBlock? b)) blocks)) (histLen (listLength historyBlocks)) (cutoff (max 0 (- histLen keepRecent)))] (if (<= cutoff 0) blocks (let [(initAcc (HistoryFoldAcc :count 0 :blocks (list))) (finalAcc (fold (fn [(acc HistoryFoldAcc) (b ContextBlock)] -> HistoryFoldAcc (if (isHistoryBlock? b) (let [(cnt acc.count)] (if (< cnt cutoff) (HistoryFoldAcc :count (+ cnt 1) :blocks (listAppend acc.blocks (list (compactBlockIfHistory b)))) (HistoryFoldAcc :count (+ cnt 1) :blocks (listAppend acc.blocks (list b))))) (HistoryFoldAcc :count acc.count :blocks (listAppend acc.blocks (list b))))) initAcc blocks))] finalAcc.blocks)))

fn assembleReceiptsContext blocks: (List ContextBlock) ceiling: I64 keepRecent: I64 -> AssembledPrompt
  (let [(transformed (processReceiptsBlocks blocks keepRecent)) (acc (BlockAccumulator :retained (list) :evicted (list) :tokens 0)) (res (accumulateBlocksLoop transformed ceiling acc)) (retained res.retained) (pStr (formatContextBlocks retained))] (AssembledPrompt :strategy "receipts" :totalTokens res.tokens :promptStr pStr :retainedCount (listLength retained) :evictedCount (listLength res.evicted)))

fn totalBlocksTokens blocks: (List ContextBlock) -> I64
  (fold (fn [(acc I64) (b ContextBlock)] -> I64 (+ acc b.tokens)) 0 blocks)

fn assembleWatermarkContext blocks: (List ContextBlock) ceiling: I64 keepRecentCfg: I64 -> AssembledPrompt
  (let [(currTok (totalBlocksTokens blocks)) (pct (if (<= ceiling 0) 0 (/ (* currTok 100) ceiling))) (keepRecent (cond ((>= pct 80) 2) ((>= pct 60) 5) (else keepRecentCfg))) (res (assembleReceiptsContext blocks ceiling keepRecent))] (AssembledPrompt :strategy "watermark" :totalTokens res.totalTokens :promptStr res.promptStr :retainedCount res.retainedCount :evictedCount res.evictedCount))

fn resultToContextBlock r: eg/EngineResult -> ContextBlock
  (let [(payload (str "(:jit-result :tier \"" r.tier "\" :title \"" r.title "\" :snippet \"" r.snippet "\")"))] (ContextBlock :id (str "jit-" r.tier "-" r.title) :kind "working-set" :tokens (txt/estimateTokens payload) :payload payload))

fn hydrateJitBlocks queries: (List Str) limit: I64 -> (List ContextBlock)
  (let [(fetchQuery (fn [(q Str)] -> (List ContextBlock) (let [(results (eg/queryGateway q "tier-0-ast" limit true))] (map resultToContextBlock results)))) (nested (map fetchQuery queries))] (fold (fn [(acc (List ContextBlock)) (bs (List ContextBlock))] -> (List ContextBlock) (listAppend acc bs)) (list) nested))

fn assembleJitContext blocks: (List ContextBlock) ceiling: I64 -> AssembledPrompt
  (let [(essentialBlocks (filter (fn [(b ContextBlock)] -> Bool (not (isHistoryBlock? b))) blocks)) (acc (BlockAccumulator :retained (list) :evicted (list) :tokens 0)) (res (accumulateBlocksLoop essentialBlocks ceiling acc)) (retained res.retained) (pStr (formatContextBlocks retained)) (historyDropped (filter (fn [(b ContextBlock)] -> Bool (isHistoryBlock? b)) blocks)) (totalEvicted (+ (listLength res.evicted) (listLength historyDropped)))] (AssembledPrompt :strategy "jit-memory" :totalTokens res.tokens :promptStr pStr :retainedCount (listLength retained) :evictedCount totalEvicted))

fn listContainsStr? items: (List Str) needle: Str -> Bool
  (if (listEmpty? items) false (let [(headS (optionOr (listHead items) "")) (tailS (optionOr (listTail items) (list)))] (if (= headS needle) true (listContainsStr? tailS needle))))

fn assembleAgentDirectedContext blocks: (List ContextBlock) ceiling: I64 op: AgentCtxOp -> AssembledPrompt
  (let [(filteredNotEvicted (filter (fn [(b ContextBlock)] -> Bool (not (listContainsStr? op.evict b.id))) blocks)) (prefetchedBlocks (map (fn [(target Str)] -> ContextBlock (let [(pl (str "(:prefetch-sym \"" target "\")"))] (ContextBlock :id (str "prefetch-" target) :kind "prefetched-ast" :tokens (txt/estimateTokens pl) :payload pl))) op.prefetch)) (mergedCandidate (listAppend filteredNotEvicted prefetchedBlocks)) (prioritizedRetained (filter (fn [(b ContextBlock)] -> Bool (listContainsStr? op.retain b.id)) mergedCandidate)) (otherBlocks (filter (fn [(b ContextBlock)] -> Bool (not (listContainsStr? op.retain b.id))) mergedCandidate)) (finalCandidate (listAppend prioritizedRetained otherBlocks)) (acc (BlockAccumulator :retained (list) :evicted (list) :tokens 0)) (res (accumulateBlocksLoop finalCandidate ceiling acc)) (retained res.retained) (pStr (formatContextBlocks retained)) (explicitlyEvicted (filter (fn [(b ContextBlock)] -> Bool (listContainsStr? op.evict b.id)) blocks)) (totalEvicted (+ (listLength res.evicted) (listLength explicitlyEvicted)))] (AssembledPrompt :strategy "agent-directed" :totalTokens res.tokens :promptStr pStr :retainedCount (listLength retained) :evictedCount totalEvicted))

fn extractQuotedTokens raw: Str -> (List Str)
  (let [(clean1 (stringReplace raw "[" "")) (clean2 (stringReplace clean1 "]" "")) (clean3 (stringReplace clean2 "\"" "")) (clean4 (stringReplace clean3 "'" "")) (parts (stringSplit clean4 " ")) (filtered (filter (fn [(s Str)] -> Bool (let [(trimmed (stringTrim s))] (not (stringEmpty? trimmed)))) parts))] (map (fn [(s Str)] -> Str (stringTrim s)) filtered))

fn extractSectionTokens text: Str tag: Str -> (List Str)
  (let [(idxOpt (stringIndexOf text tag))] (mt idxOpt ((some idx) (let [(sub (optionOr (stringSlice text (+ idx (stringLength tag)) (stringLength text)) "")) (openBr (stringIndexOf sub "[")) (closeBr (stringIndexOf sub "]"))] (mt openBr ((some ob) (mt closeBr ((some cb) (if (< ob cb) (let [(inner (optionOr (stringSlice sub (+ ob 1) cb) ""))] (extractQuotedTokens inner)) (list))) ((none) (list)))) ((none) (list))))) ((none) (list))))

fn parseAgentCtxOp raw: Str -> (Option AgentCtxOp)
  (if (not (stringContains? raw ":ctx-op")) (none) (let [(retainItems (extractSectionTokens raw ":retain")) (evictItems (extractSectionTokens raw ":evict")) (prefetchItems (extractSectionTokens raw ":prefetch"))] (some (AgentCtxOp :retain retainItems :evict evictItems :prefetch prefetchItems))))

fn isCoreBlock? b: ContextBlock -> Bool
  (let [(k b.kind)] (or (= k "sys-mandate") (= k "task-spec")))

fn isKnowledgeBlock? b: ContextBlock -> Bool
  (= b.kind "knowledge")

fn isDeltaBlock? b: ContextBlock -> Bool
  (let [(k b.kind)] (or (= k "delta") (or (= k "error") (= k "gate-rejection"))))

fn isOtherCanvasBlock? b: ContextBlock -> Bool
  (and (not (isCoreBlock? b)) (and (not (isKnowledgeBlock? b)) (and (not (isDeltaBlock? b)) (not (isHistoryBlock? b)))))

fn applyUniversalDefaultCanvas blocks: (List ContextBlock) ceiling: I64 keepRecentOverride: I64 agentOp: (Option AgentCtxOp) -> AssembledPrompt
  (mt agentOp ((some op) (assembleAgentDirectedContext blocks ceiling op)) ((none) (let [(coreBlocks (filter (fn [(b ContextBlock)] -> Bool (isCoreBlock? b)) blocks)) (knowledgeBlocks (filter (fn [(b ContextBlock)] -> Bool (isKnowledgeBlock? b)) blocks)) (otherBlocks (filter (fn [(b ContextBlock)] -> Bool (isOtherCanvasBlock? b)) blocks)) (deltaBlocks (filter (fn [(b ContextBlock)] -> Bool (isDeltaBlock? b)) blocks)) (historyCandidates (filter (fn [(b ContextBlock)] -> Bool (isHistoryBlock? b)) blocks)) (currTok (totalBlocksTokens blocks)) (pct (if (<= ceiling 0) 0 (/ (* currTok 100) ceiling))) (watermarkRecent (cond ((>= pct 80) 1) ((>= pct 60) 3) (else 5))) (keepRecent (if (> keepRecentOverride 0) keepRecentOverride watermarkRecent)) (receiptBlocks (processReceiptsBlocks historyCandidates keepRecent)) (prefixBlocks (listAppend (listAppend coreBlocks knowledgeBlocks) otherBlocks)) (orderedCandidates (listAppend prefixBlocks (listAppend receiptBlocks deltaBlocks))) (acc (BlockAccumulator :retained (list) :evicted (list) :tokens 0)) (res (accumulateBlocksLoop orderedCandidates ceiling acc)) (retained res.retained) (pStr (formatContextBlocks retained))] (AssembledPrompt :strategy "universal-default" :totalTokens res.tokens :promptStr pStr :retainedCount (listLength retained) :evictedCount (listLength res.evicted)))))

fn assemblePrompt blocks: (List ContextBlock) cfg: ContextAssemblyConfig agentOp: (Option AgentCtxOp) -> AssembledPrompt
  (let [(strat cfg.strategy) (ceiling cfg.tokenCeiling) (recent cfg.keepRecent)] (cond ((= strat "baseline") (assembleBaselineContext blocks ceiling)) ((= strat "receipts") (assembleReceiptsContext blocks ceiling recent)) ((= strat "watermark") (assembleWatermarkContext blocks ceiling recent)) ((= strat "jit-memory") (assembleJitContext blocks ceiling)) ((= strat "agent-directed") (mt agentOp ((some op) (assembleAgentDirectedContext blocks ceiling op)) ((none) (assembleReceiptsContext blocks ceiling recent)))) ((= strat "universal-default") (applyUniversalDefaultCanvas blocks ceiling recent agentOp)) ((= strat "golden-default") (applyUniversalDefaultCanvas blocks ceiling recent agentOp)) (true (assembleBaselineContext blocks ceiling))))
