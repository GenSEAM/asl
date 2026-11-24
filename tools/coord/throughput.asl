(module asl-tools/coord/throughput
  :x [ProviderDay dailyByProvider renderProviderDay cacheShareOf UnitDay unitsByDay]
  :i [(aslGateway/usageLedger :a ul) (asl-tools/coord/store :a st)])

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

; (:m :ref THROUGHPUT-DAILY :do "the Task.st values conductor.asl writes for a unit that landed, failed or was escalated; blocked is the state escalate! and parkModelEscalated! move a unit to")
fn mergedStates -> (List String)
  (list "merged")

fn failedStates -> (List String)
  (list "failed")

fn escalatedStates -> (List String)
  (list "blocked")

(schema UnitDay
  (:f day String)
  (:f channel String)
  (:f merged Int64)
  (:f failed Int64)
  (:f escalated Int64))

fn stIn? sts: (List String) s: String -> Bool
  (listContains? sts s)

fn dayOf days: (List (Pair String String)) id: String -> (Option String)
  (match (listHead days)
    ((none) (none))
    ((some p) (if (= (pairFirst p) id) (some (pairSecond p)) (dayOf (optionOr (listTail days) (list)) id))))

fn unitRow u: st/Task days: (List (Pair String String)) -> UnitDay
  (UnitDay :day (optionOr (dayOf days u.id) "")
    :channel u.channel
    :merged (if (stIn? (mergedStates) u.st) 1 0)
    :failed (if (stIn? (failedStates) u.st) 1 0)
    :escalated (if (stIn? (escalatedStates) u.st) 1 0))

fn counted? d: UnitDay -> Bool
  (> (+ d.merged (+ d.failed d.escalated)) 0)

fn dayKeyOf d: UnitDay -> String
  (str d.day "|" d.channel)

fn bumpDay d: UnitDay x: UnitDay -> UnitDay
  (with d
    :merged (+ d.merged x.merged)
    :failed (+ d.failed x.failed)
    :escalated (+ d.escalated x.escalated))

fn indexOfDay rows: (List UnitDay) key: String i: Int64 -> (Option Int64)
  (match (listHead rows)
    ((none) (none))
    ((some x) (if (= (dayKeyOf x) key) (some i) (indexOfDay (optionOr (listTail rows) (list)) key (+ i 1)))))

fn replaceDay rows: (List UnitDay) idx: Int64 i: Int64 row: UnitDay -> (List UnitDay)
  (match (listHead rows)
    ((none) (list))
    ((some x) (cons (if (= i idx) row x) (replaceDay (optionOr (listTail rows) (list)) idx (+ i 1) row))))

fn stepUnit acc: (List UnitDay) u: st/Task days: (List (Pair String String)) -> (List UnitDay)
  (let [(x (unitRow u days))]
    (if (counted? x)
      (match (indexOfDay acc (dayKeyOf x) 0)
        ((some i) (replaceDay acc i 0 (bumpDay (optionOr (listGet acc i) x) x)))
        ((none) (listAppend acc (list x))))
      acc))

fn unitsByDayLoop units: (List st/Task) days: (List (Pair String String)) acc: (List UnitDay) -> (List UnitDay)
  (match (listHead units)
    ((none) acc)
    ((some u) (unitsByDayLoop (optionOr (listTail units) (list)) days (stepUnit acc u days))))

; (:m :ref THROUGHPUT-DAILY :do "accepted units per UTC day and channel: days maps unit id to its day, merged/failed/escalated come from Task.st, queued and in-flight units are ignored, rows sorted by day then channel")
fn unitsByDay units: (List st/Task) days: (List (Pair String String)) -> (List UnitDay)
  (listSortBy dayKeyOf (unitsByDayLoop units days (list)))
