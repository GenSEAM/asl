(module aslHarness/routinglog :x [RoutingEntry RoutingLogSummary makeRoutingEntry appendRoutingEntry filterMisrouted summarizeRoutingLog formatRoutingAsn] :i [])

(schema RoutingEntry (:f entryId Str) (:f timestampMs Int64) (:f taskId Str) (:f promptSnippet Str) (:f entropyScore Float) (:f selectedTier Str) (:f executedLocally Bool) (:f tokensSaved Int64) (:f latencyMs Int64) (:f gateVerdict Str) (:f misrouted Bool))

(schema RoutingLogSummary (:f totalEntries Int64) (:f localCount Int64) (:f remoteCount Int64) (:f localRatio Float) (:f misrouteCount Int64) (:f misrouteRate Float) (:f totalTokensSaved Int64))

fn makeRoutingEntry id: Str ts: Int64 taskId: Str snippet: Str entropy: Float tier: Str local: Bool tokens: Int64 latency: Int64 verdict: Str misrouted: Bool -> RoutingEntry
  (RoutingEntry :entryId id :timestampMs ts :taskId taskId :promptSnippet snippet :entropyScore entropy :selectedTier tier :executedLocally local :tokensSaved tokens :latencyMs latency :gateVerdict verdict :misrouted misrouted)

fn appendRoutingEntry entries: (List RoutingEntry) newEntry: RoutingEntry -> (List RoutingEntry)
  (listAppend entries (list newEntry))

fn filterMisrouted entries: (List RoutingEntry) -> (List RoutingEntry)
  (if (listEmpty? entries) (list) (let [(head (optionOr (listHead entries) (RoutingEntry :entryId "" :timestampMs 0 :taskId "" :promptSnippet "" :entropyScore 0.0 :selectedTier "" :executedLocally false :tokensSaved 0 :latencyMs 0 :gateVerdict "" :misrouted false))) (tail (optionOr (listTail entries) (list)))] (if head.misrouted (cons head (filterMisrouted tail)) (filterMisrouted tail))))

fn countLocalRoutes entries: (List RoutingEntry) -> Int64
  (if (listEmpty? entries) 0 (let [(head (optionOr (listHead entries) (RoutingEntry :entryId "" :timestampMs 0 :taskId "" :promptSnippet "" :entropyScore 0.0 :selectedTier "" :executedLocally false :tokensSaved 0 :latencyMs 0 :gateVerdict "" :misrouted false))) (tail (optionOr (listTail entries) (list))) (inc (if head.executedLocally 1 0))] (+ inc (countLocalRoutes tail))))

fn countMisroutedEntries entries: (List RoutingEntry) -> Int64
  (if (listEmpty? entries) 0 (let [(head (optionOr (listHead entries) (RoutingEntry :entryId "" :timestampMs 0 :taskId "" :promptSnippet "" :entropyScore 0.0 :selectedTier "" :executedLocally false :tokensSaved 0 :latencyMs 0 :gateVerdict "" :misrouted false))) (tail (optionOr (listTail entries) (list))) (inc (if head.misrouted 1 0))] (+ inc (countMisroutedEntries tail))))

fn sumTokensSaved entries: (List RoutingEntry) -> Int64
  (if (listEmpty? entries) 0 (let [(head (optionOr (listHead entries) (RoutingEntry :entryId "" :timestampMs 0 :taskId "" :promptSnippet "" :entropyScore 0.0 :selectedTier "" :executedLocally false :tokensSaved 0 :latencyMs 0 :gateVerdict "" :misrouted false))) (tail (optionOr (listTail entries) (list)))] (+ head.tokensSaved (sumTokensSaved tail))))

fn summarizeRoutingLog entries: (List RoutingEntry) -> RoutingLogSummary
  (let [(total (listLength entries))] (if (<= total 0) (RoutingLogSummary :totalEntries 0 :localCount 0 :remoteCount 0 :localRatio 0.0 :misrouteCount 0 :misrouteRate 0.0 :totalTokensSaved 0) (let [(localC (countLocalRoutes entries)) (remoteC (- total localC)) (misrouteC (countMisroutedEntries entries)) (tokensSum (sumTokensSaved entries)) (totalF (int64ToFloat64 total)) (lRatio (* (/ (int64ToFloat64 localC) totalF) 100.0)) (mRate (* (/ (int64ToFloat64 misrouteC) totalF) 100.0))] (RoutingLogSummary :totalEntries total :localCount localC :remoteCount remoteC :localRatio lRatio :misrouteCount misrouteC :misrouteRate mRate :totalTokensSaved tokensSum))))

fn formatRoutingAsn entry: RoutingEntry -> Str
  (str "(:routing-entry :id \"" entry.entryId "\" :task-id \"" entry.taskId "\" :tier \"" entry.selectedTier "\" :entropy " (stringFromFloat64 entry.entropyScore) " :local " (if entry.executedLocally "true" "false") " :tokens-saved " (stringFromInt64 entry.tokensSaved) " :latency-ms " (stringFromInt64 entry.latencyMs) " :verdict \"" entry.gateVerdict "\" :misrouted " (if entry.misrouted "true" "false") ")")
