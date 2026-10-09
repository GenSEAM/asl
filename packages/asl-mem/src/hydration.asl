(module aslMem/hydration :x [ContextBuffer makeContextBuffer checkCompressionThreshold cascadeCompress evictRawContext defaultCoreAxioms hydrateIntentSummary synthesizeIntentSummary defaultModernDecisions hydrateModernIntent nowMs] :i [(viewLayer :a vl)])

(schema ContextBuffer (:f id Str) (:f activeTokens I64) (:f messages (List Str)) (:f chunks (List vl/MemoryChunk)))

fn makeContextBuffer id: Str tokens: I64 messages: (List Str) chunks: (List vl/MemoryChunk) -> ContextBuffer
  (ContextBuffer :id id :activeTokens tokens :messages messages :chunks chunks)

fn checkCompressionThreshold tokens: I64 threshold: I64 -> Bool
  (>= tokens threshold)

fn isFact? msg: Str -> Bool
  (let [(lower (stringLower (stringTrim msg)))] (or (stringStartsWith? lower "fact") (stringStartsWith? lower "[fact]")))

fn isDirective? msg: Str -> Bool
  (let [(lower (stringLower (stringTrim msg)))] (or (stringStartsWith? lower "directive") (stringStartsWith? lower "[directive]")))

fn isOther? msg: Str -> Bool
  (and (not (isFact? msg)) (not (isDirective? msg)))

fn nowMs base: I64 delta: I64 -> I64
  (+ base delta)

fn extractFacts msgs: (List Str) -> (List Str)
  (filter isFact? msgs)

fn extractDirectives msgs: (List Str) -> (List Str)
  (filter isDirective? msgs)

fn extractSummary msgs: (List Str) bufId: Str -> Str
  (if (listEmpty? msgs) "Empty context buffer compressed" (let [(other (filter isOther? msgs))] (if (listEmpty? other) (str "Folded " (stringFromInt64 (listLength msgs)) " operational messages for buffer " bufId) (stringJoin other " | "))))

fn cascadeCompress buffer: ContextBuffer threshold: I64 parentRefs: (List Str) baseTs: I64 -> (Pair MemoryChunk ContextBuffer)
  (let [(bufId buffer.id) (msgs buffer.messages) (ts (if (> baseTs 0) (nowMs baseTs 0) 1)) (cId (str "chunk-" bufId "-" (stringFromInt64 ts))) (facts (extractFacts msgs)) (directives (extractDirectives msgs)) (summary (extractSummary msgs bufId)) (chunk (vl/makeMemoryChunk cId ts 0.95 summary facts directives parentRefs)) (newChunks (listAppend buffer.chunks (list chunk))) (newBuf (ContextBuffer :id bufId :activeTokens 0 :messages (list) :chunks newChunks))] (pair chunk newBuf))

fn evictRawContext buffer: ContextBuffer -> ContextBuffer
  (let [(msgs buffer.messages)] (if (listEmpty? msgs) (with buffer :activeTokens 0 :messages (list)) (let [(bufId buffer.id) (ts 1) (cId (str "chunk-" bufId "-evicted-" (stringFromInt64 (listLength buffer.chunks)))) (facts (extractFacts msgs)) (directives (extractDirectives msgs)) (summary (extractSummary msgs bufId)) (chunk (vl/makeMemoryChunk cId ts 0.95 summary facts directives (list))) (newChunks (listAppend buffer.chunks (list chunk)))] (ContextBuffer :id bufId :activeTokens 0 :messages (list) :chunks newChunks))))

fn defaultCoreAxioms -> (List Str)
  (list "D0015: Token Arbitrage (-70% tokens, pure ASN, zero JSON/YAML, zero emojis)" "D0016: Agent-Native Autonomy (machine-first, balanced delimiters, deterministic AST)" "D0017: Falsifiable Observability (7 verification gates, zero comments C0001, physical receipts)" "D0018: In-Memory State Surgery (RAM VFS, batch RPC, speculative racing, clean supervisor)")

fn hydrateIntentSummary axioms: (List Str) -> Str
  (if (listEmpty? axioms) "Axioms: Token Arbitrage | Agent-Native Autonomy | Falsifiable Observability | In-Memory State Surgery" (stringJoin axioms " | "))

fn synthesizeIntentSummary rawLedger: Str -> Str
  (if (or (stringContains? rawLedger "D0015") (stringContains? rawLedger "Token Arbitrage")) (hydrateIntentSummary (defaultCoreAxioms)) "Axioms: Ungrounded")

fn defaultModernDecisions -> (List Str)
  (list "D0019: Pure ASL Differential Test Runner & Falsifiable Gate Invariant" "D0020: Zero-Copy Token Regex Engine & CAS Mutators" "D0021: In-Memory AST Equivalence E-Graphs & Congruence Closure" "D0022: In-Memory Speculative VFS Branching & Pruning" "D0023: Grammar-Trie Constrained Decoding Engine" "D0024: Memory TaskStore State Machine & Priority Scheduler" "D0025: Multi-Agent Supervisor & Dual-Temperature Speculative Racing" "D0026: Pure ASL WASI Lowering & Node Annihilation" "D0027: Dense Tabular Pyramid & Sparkline Compaction" "D0028: Universal Cross-Reference URIs & AST Dependency Graph" "D0029: Decoupled Amnesia Runtime Context Eviction & Retention Audit")

fn hydrateModernIntent id: Str -> Str
  (cond ((= id "D0019") "D0019: Pure ASL Differential Test Runner & Falsifiable Gate Invariant") ((= id "D0020") "D0020: Zero-Copy Token Regex Engine & CAS Mutators") ((= id "D0021") "D0021: In-Memory AST Equivalence E-Graphs & Congruence Closure") ((= id "D0022") "D0022: In-Memory Speculative VFS Branching & Pruning") ((= id "D0023") "D0023: Grammar-Trie Constrained Decoding Engine") ((= id "D0024") "D0024: Memory TaskStore State Machine & Priority Scheduler") ((= id "D0025") "D0025: Multi-Agent Supervisor & Dual-Temperature Speculative Racing") ((= id "D0026") "D0026: Pure ASL WASI Lowering & Node Annihilation") ((= id "D0027") "D0027: Dense Tabular Pyramid & Sparkline Compaction") ((= id "D0028") "D0028: Universal Cross-Reference URIs & AST Dependency Graph") ((= id "D0029") "D0029: Decoupled Amnesia Runtime Context Eviction & Retention Audit") (else ""))
