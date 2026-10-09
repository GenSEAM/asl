(module aslMem/summarySearch :x [SummaryIndex summaryIndexEmpty indexChunkSummary searchChunksBySummary] :i [(viewLayer :a vl) (simhash :a sh)])

(schema SummaryIndex (:f entries (List (Pair Str (List Str)))) (:f chunks (Map Str vl/MemoryChunk)) (:f size I64))

fn summaryIndexEmpty -> SummaryIndex
  (SummaryIndex :entries (list) :chunks (mapEmpty) :size 0)

fn renderCard chunk: vl/MemoryChunk -> Str
  (str "[Chunk: " chunk.id "] (" (stringFromFloat64 chunk.conf) ") " chunk.summary " (" (stringFromInt64 chunk.ts) " ms)")

fn indexChunkSummary idx: SummaryIndex chunk: vl/MemoryChunk -> SummaryIndex
  (let [(cId chunk.id) (tokens (sh/tokenizeWords chunk.summary)) (entry (pair cId tokens)) (newEntries (listAppend idx.entries (list entry))) (newChunks (mapSet idx.chunks cId chunk)) (newSize (+ idx.size 1))] (SummaryIndex :entries newEntries :chunks newChunks :size newSize))

fn matchAnyToken qTokens: (List Str) docTokens: (List Str) -> Bool
  (mt (listHead qTokens) ((none) false) ((some head) (let [(tail (optionOr (listTail qTokens) (list)))] (if (listContains? docTokens head) true (matchAnyToken tail docTokens)))))

fn searchEntriesStep entries: (List (Pair Str (List Str))) qTokens: (List Str) chunks: (Map Str vl/MemoryChunk) format: Str -> (List Str)
  (mt (listHead entries) ((none) (list)) ((some headEntry) (let [(tailEntries (optionOr (listTail entries) (list))) (cId (pairFirst headEntry)) (docTokens (pairSecond headEntry)) (rest (searchEntriesStep tailEntries qTokens chunks format))] (if (matchAnyToken qTokens docTokens) (mt (mapGet chunks cId) ((none) rest) ((some chunk) (let [(formatted (if (= format "markdown") (renderCard chunk) cId))] (cons formatted rest)))) rest))))

fn searchChunksBySummary idx: SummaryIndex query: Str format: Str -> (List Str)
  (let [(cleanQuery (stringTrim query))] (if (or (stringEmpty? cleanQuery) (= idx.size 0)) (list) (let [(qTokens (sh/tokenizeWords cleanQuery))] (if (listEmpty? qTokens) (list) (searchEntriesStep idx.entries qTokens idx.chunks format)))))
