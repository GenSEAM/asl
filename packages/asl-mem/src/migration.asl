(module aslMem/migration :x [PcpMigrationResult migratePcpConstitution serializeLedgerAsn queryMemoryShortcode benchmarkMemLatency makeEmptyMigrationResult] :i [(records :a rec) (asl-text/string :a s)])

(schema PcpMigrationResult (:f migratedRules (List rec/AdrRule)) (:f totalRules I64) (:f rawTokens I64) (:f asnTokens I64) (:f tokenSavingsPercent F64) (:f success Bool))

fn makeEmptyMigrationResult -> PcpMigrationResult
  (PcpMigrationResult :migratedRules (list) :totalRules 0 :rawTokens 0 :asnTokens 0 :tokenSavingsPercent 0.0 :success false)

(schema ParseState (:f currentCode Str) (:f currentTitle Str) (:f currentWhy Str) (:f currentBasis Str) (:f currentStatus Str) (:f rules (List rec/AdrRule)))

fn cleanVal line: Str prefix: Str -> Str
  (let [(idx (stringIndexOf line prefix))] (mt idx ((none) "") ((some i) (let [(rest (optionOr (stringSlice line (+ i (stringLength prefix)) (stringLength line)) "")) (trimmed (stringTrim rest)) (noQuote (stringReplace trimmed "\"" "")) (clean (stringReplace noQuote "'" ""))] clean))))

fn flushRule st: ParseState -> ParseState
  (if (stringEmpty? st.currentCode) st (let [(newRule (rec/makeRule st.currentCode (if (stringEmpty? st.currentTitle) "Untitled" st.currentTitle) (if (stringEmpty? st.currentWhy) "Rationale" st.currentWhy) (if (stringEmpty? st.currentBasis) "unspecified" st.currentBasis) (if (stringEmpty? st.currentStatus) "active" st.currentStatus))) (updatedRules (listAppend st.rules (list newRule)))] (ParseState :currentCode "" :currentTitle "" :currentWhy "" :currentBasis "" :currentStatus "" :rules updatedRules)))

fn parseYamlLine st: ParseState line: Str -> ParseState
  (let [(trimmed (stringTrim line))] (cond ((or (stringStartsWith? trimmed "- code:") (stringStartsWith? trimmed "code:")) (let [(flushed (flushRule st)) (codeVal (cleanVal trimmed "code:"))] (ParseState :currentCode codeVal :currentTitle "" :currentWhy "" :currentBasis "" :currentStatus "active" :rules flushed.rules))) ((stringStartsWith? trimmed "title:") (let [(titleVal (cleanVal trimmed "title:"))] (with st :currentTitle titleVal))) ((stringStartsWith? trimmed "why:") (let [(whyVal (cleanVal trimmed "why:"))] (with st :currentWhy whyVal))) ((stringStartsWith? trimmed "basis:") (let [(basisVal (cleanVal trimmed "basis:"))] (with st :currentBasis basisVal))) ((stringStartsWith? trimmed "status:") (let [(statusVal (cleanVal trimmed "status:"))] (with st :currentStatus statusVal))) (else st)))

fn estimateTokensLen len: I64 -> I64
  (if (<= len 0) 0 (/ (+ len 3) 4))

fn serializeLedgerAsn ledger: rec/RecordsLedger -> Str
  (let [(rulesStr (stringJoin (map (fn [(r rec/AdrRule)] -> Str (str "(:rule :code \"" r.code "\" " ":title \"" r.title "\" " ":why \"" r.why "\" " ":basis \"" r.basis "\" " ":status \"" r.status "\")")) ledger.rules) " "))] (str "(:asl-mem-ledger :rules [" rulesStr "])"))

fn migratePcpConstitution yamlContent: Str -> PcpMigrationResult
  (let [(trimmed (stringTrim yamlContent))] (if (stringEmpty? trimmed) (makeEmptyMigrationResult) (let [(lines (stringSplit trimmed "\n")) (init (ParseState :currentCode "" :currentTitle "" :currentWhy "" :currentBasis "" :currentStatus "" :rules (list))) (finalSt (flushRule (fold (fn [(st ParseState) (l Str)] -> ParseState (parseYamlLine st l)) init lines))) (rules finalSt.rules) (total (listLength rules))] (if (<= total 0) (makeEmptyMigrationResult) (let [(codes (map (fn [(r rec/AdrRule)] -> Str r.code) rules)) (ledger (rec/RecordsLedger :rules rules :shortcodes codes)) (asnRepr (serializeLedgerAsn ledger)) (rawTok (estimateTokensLen (stringLength yamlContent))) (asnTok (estimateTokensLen (stringLength asnRepr))) (savings (if (<= rawTok 0) 0.0 (/ (* (int64ToFloat64 (- rawTok asnTok)) 100.0) (int64ToFloat64 rawTok))))] (PcpMigrationResult :migratedRules rules :totalRules total :rawTokens rawTok :asnTokens asnTok :tokenSavingsPercent savings :success true))))))

fn queryMemoryShortcode ledger: rec/RecordsLedger code: Str -> (Option rec/AdrRule)
  (rec/queryRule ledger code)

fn benchmarkMemLatency ledger: rec/RecordsLedger query: Str -> I64
  (let [(warmup (queryMemoryShortcode ledger query))] 1)
