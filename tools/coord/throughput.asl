(module asl-tools/coord/throughput
  :x [ProviderDay dailyByProvider renderProviderDay cacheShareOf]
  :i [(aslGateway/usageLedger :a ul)])

; (:m :ref THROUGHPUT-DAILY :do "one row per UTC day and provider, read from the gateway ledger without writing it: calls, ok, 429s, token sums and the cached share of input tokens")
(schema ProviderDay
  (:f day String)
  (:f provider String)
  (:f calls Int64)
  (:f ok Int64)
  (:f rate429 Int64)
  (:f inTokens Int64)
  (:f cachedTokens Int64)
  (:f outTokens Int64)
  (:f cacheShare Float64))

fn cacheShareOf inTok: Int64 cached: Int64 -> Float64
  (if (= inTok 0) 0.0 (/ (int64ToFloat64 cached) (int64ToFloat64 inTok)))

fn okOutcome? outcome: String -> Bool
  (= outcome "ok")

fn rate429Outcome? outcome: String -> Bool
  (or (stringContains? outcome "429") (stringContains? (stringLower outcome) "rate"))

fn keyOf r: ul/CallRow -> String
  (str (ul/dayKeyOf r.atMs) "|" r.provider)

fn bumpRow r: ul/CallRow d: ProviderDay -> ProviderDay
  (with d
    :calls (+ d.calls 1)
    :ok (+ d.ok (if (okOutcome? r.outcome) 1 0))
    :rate429 (+ d.rate429 (if (rate429Outcome? r.outcome) 1 0))
    :inTokens (+ d.inTokens r.inTokens)
    :cachedTokens (+ d.cachedTokens r.cachedTokens)
    :outTokens (+ d.outTokens r.outTokens)
    :cacheShare (cacheShareOf (+ d.inTokens r.inTokens) (+ d.cachedTokens r.cachedTokens)))

fn indexOfKey rows: (List ProviderDay) key: String i: Int64 -> (Option Int64)
  (match (listHead rows)
    ((none) (none))
    ((some x) (if (= (str x.day "|" x.provider) key) (some i) (indexOfKey (optionOr (listTail rows) (list)) key (+ i 1)))))

fn replaceAt rows: (List ProviderDay) idx: Int64 i: Int64 row: ProviderDay -> (List ProviderDay)
  (match (listHead rows)
    ((none) (list))
    ((some x) (cons (if (= i idx) row x) (replaceAt (optionOr (listTail rows) (list)) idx (+ i 1) row))))

fn freshDay r: ul/CallRow -> ProviderDay
  (ProviderDay :day (ul/dayKeyOf r.atMs) :provider r.provider :calls 0 :ok 0 :rate429 0
    :inTokens 0 :cachedTokens 0 :outTokens 0 :cacheShare 0.0)

fn step acc: (List ProviderDay) r: ul/CallRow -> (List ProviderDay)
  (let [(key (keyOf r))]
    (match (indexOfKey acc key 0)
      ((some i) (replaceAt acc i 0 (bumpRow r (optionOr (listGet acc i) (freshDay r)))))
      ((none) (listAppend acc (list (bumpRow r (freshDay r)))))))

; (:m :ref THROUGHPUT-DAILY :do "rows grouped by ul/dayKeyOf atMs and provider, sorted by day then provider")
fn dailyByProvider rows: (List ul/CallRow) -> (List ProviderDay)
  (listSortBy (fn [(d ProviderDay)] -> String (str d.day "|" d.provider)) (fold step (list) rows))

fn asnStr s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

; (:m :ref THROUGHPUT-DAILY :do "one ASN line a reader or a parser can take back")
fn renderProviderDay d: ProviderDay -> String
  (str "(:providerDay :day " (asnStr d.day)
       " :provider " (asnStr d.provider)
       " :calls " (stringFromInt64 d.calls)
       " :ok " (stringFromInt64 d.ok)
       " :rate429 " (stringFromInt64 d.rate429)
       " :inTokens " (stringFromInt64 d.inTokens)
       " :cachedTokens " (stringFromInt64 d.cachedTokens)
       " :outTokens " (stringFromInt64 d.outTokens)
       " :cacheShare " (stringFromFloat64 d.cacheShare) ")")
