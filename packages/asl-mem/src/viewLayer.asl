(module aslMem/viewLayer :x [MemoryChunk makeMemoryChunk hydrateToMarkdown renderSummaryCard] :i [])

(schema MemoryChunk (:f id Str) (:f ts I64) (:f conf F64) (:f summary Str) (:f facts (List Str)) (:f directives (List Str)) (:f refs (List Str)))

fn makeMemoryChunk id: Str ts: I64 conf: F64 summary: Str facts: (List Str) directives: (List Str) refs: (List Str) -> MemoryChunk
  (MemoryChunk :id id :ts ts :conf conf :summary summary :facts facts :directives directives :refs refs)

fn formatFactsRows facts: (List Str) idx: I64 -> Str
  (if (listEmpty? facts) "" (let [(head (optionOr (listHead facts) "")) (tail (optionOr (listTail facts) (list))) (row (str "| " (stringFromInt64 idx) " | " head " |\n"))] (str row (formatFactsRows tail (+ idx 1)))))

fn formatFactsTable facts: (List Str) -> Str
  (if (listEmpty? facts) "*No scalar facts recorded.*" (str "| Index | Fact |\n|---|---|\n" (formatFactsRows facts 1)))

fn formatDirectivesRows directives: (List Str) -> Str
  (if (listEmpty? directives) "" (let [(head (optionOr (listHead directives) "")) (tail (optionOr (listTail directives) (list))) (line (str "> - " head "\n"))] (str line (formatDirectivesRows tail))))

fn formatDirectives directives: (List Str) -> Str
  (if (listEmpty? directives) "*No operational directives.*" (str "> [!IMPORTANT]\n> **Directives**:\n" (formatDirectivesRows directives)))

fn formatRefsRows refs: (List Str) -> Str
  (if (listEmpty? refs) "" (let [(head (optionOr (listHead refs) "")) (tail (optionOr (listTail refs) (list))) (line (str "- " head "\n"))] (str line (formatRefsRows tail))))

fn formatCausalRefs refs: (List Str) -> Str
  (if (listEmpty? refs) "*Root node (zero parent references).*" (formatRefsRows refs))

fn hydrateToMarkdown chunk: MemoryChunk -> Str
  (let [(header (str "# Memory Chunk: " chunk.id "\n\n")) (meta (str "**Timestamp**: " (stringFromInt64 chunk.ts) " | **Confidence**: " (stringFromFloat64 chunk.conf) "\n\n")) (summary (str "### Summary\n" chunk.summary "\n\n")) (facts (str "### Facts\n" (formatFactsTable chunk.facts) "\n\n")) (directives (str "### Directives\n" (formatDirectives chunk.directives) "\n\n")) (causality (str "### Causal References\n" (formatCausalRefs chunk.refs)))] (str header meta summary facts directives causality))

fn renderSummaryCard chunk: MemoryChunk -> Str
  (str "[Chunk: " chunk.id "] (" (stringFromFloat64 chunk.conf) ") " chunk.summary " (" (stringFromInt64 chunk.ts) " ms)")
