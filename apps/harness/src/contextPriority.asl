(module aslHarness/contextPriority :x [ContextPriorityRecord scoreContextChunk rankContextChunks applyTokenBudget filterRetainedChunks totalRetainedTokens] :i [])

(schema ContextPriorityRecord (:f chunkId Str) (:f kind Str) (:f rawTokens I64) (:f relevance F64) (:f priorityScore F64) (:f retained Bool))

fn scoreContextChunk chunkId: Str kind: Str tokens: I64 relevance: F64 -> ContextPriorityRecord
  (let [(fTok (int64ToFloat64 tokens)) (score (/ (* relevance 1000.0) (+ fTok 10.0)))] (ContextPriorityRecord :chunkId chunkId :kind kind :rawTokens tokens :relevance relevance :priorityScore score :retained false))

fn insertChunk item: ContextPriorityRecord sorted: (List ContextPriorityRecord) -> (List ContextPriorityRecord)
  (if (listEmpty? sorted) (list item) (let [(defaultChunk (ContextPriorityRecord :chunkId "" :kind "" :rawTokens 0 :relevance 0.0 :priorityScore 0.0 :retained false)) (headC (optionOr (listHead sorted) defaultChunk)) (tailC (optionOr (listTail sorted) (list)))] (if (> item.priorityScore headC.priorityScore) (cons item sorted) (cons headC (insertChunk item tailC)))))

fn sortChunksLoop unsorted: (List ContextPriorityRecord) sorted: (List ContextPriorityRecord) -> (List ContextPriorityRecord)
  (if (listEmpty? unsorted) sorted (let [(defaultChunk (ContextPriorityRecord :chunkId "" :kind "" :rawTokens 0 :relevance 0.0 :priorityScore 0.0 :retained false)) (headC (optionOr (listHead unsorted) defaultChunk)) (tailC (optionOr (listTail unsorted) (list)))] (sortChunksLoop tailC (insertChunk headC sorted))))

fn rankContextChunks chunks: (List ContextPriorityRecord) -> (List ContextPriorityRecord)
  (sortChunksLoop chunks (list))

fn applyBudgetLoop chunks: (List ContextPriorityRecord) budget: I64 accumulated: I64 acc: (List ContextPriorityRecord) -> (List ContextPriorityRecord)
  (if (listEmpty? chunks) acc (let [(defaultChunk (ContextPriorityRecord :chunkId "" :kind "" :rawTokens 0 :relevance 0.0 :priorityScore 0.0 :retained false)) (headC (optionOr (listHead chunks) defaultChunk)) (tailC (optionOr (listTail chunks) (list))) (tok headC.rawTokens)] (if (<= (+ accumulated tok) budget) (let [(updated (ContextPriorityRecord :chunkId headC.chunkId :kind headC.kind :rawTokens tok :relevance headC.relevance :priorityScore headC.priorityScore :retained true))] (applyBudgetLoop tailC budget (+ accumulated tok) (listAppend acc (list updated)))) (let [(updated (ContextPriorityRecord :chunkId headC.chunkId :kind headC.kind :rawTokens tok :relevance headC.relevance :priorityScore headC.priorityScore :retained false))] (applyBudgetLoop tailC budget accumulated (listAppend acc (list updated)))))))

fn applyTokenBudget ranked: (List ContextPriorityRecord) budgetTokens: I64 -> (List ContextPriorityRecord)
  (applyBudgetLoop ranked budgetTokens 0 (list))

fn filterRetainedChunks prioritized: (List ContextPriorityRecord) -> (List ContextPriorityRecord)
  (filter (fn [(c ContextPriorityRecord)] -> Bool c.retained) prioritized)

fn sumRetainedTokensLoop chunks: (List ContextPriorityRecord) sum: I64 -> I64
  (if (listEmpty? chunks) sum (let [(defaultChunk (ContextPriorityRecord :chunkId "" :kind "" :rawTokens 0 :relevance 0.0 :priorityScore 0.0 :retained false)) (headC (optionOr (listHead chunks) defaultChunk)) (tailC (optionOr (listTail chunks) (list))) (nextSum (if headC.retained (+ sum headC.rawTokens) sum))] (sumRetainedTokensLoop tailC nextSum)))

fn totalRetainedTokens chunks: (List ContextPriorityRecord) -> I64
  (sumRetainedTokensLoop chunks 0)
