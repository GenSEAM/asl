(module aslGateway/health
  :x [HealthRow healthRows providerRows pruneCandidates neverServed attemptsPerTurnX100 requestsText healthRowText healthReport defaultHealthHours pruneMinCalls pruneOkPercent healthDir healthFileName]
  :i [(aslGateway/usageLedger :a ul)
      (aslGateway/limits :a lim)
      (aslGateway/requestLog :a rq)
      (aslGateway/usage :a g)
      (aslGateway/wire :a wire)])

; (:m :ref GW-HEALTH-REPORT :do "what the usage ledger shows of one provider and alias (or of a whole provider with an empty alias) over a window: sent calls, ok calls, upstream 429s, our own refusals (rows that sent nothing), other failures, p50 and p95 latency of the ok calls in ms and the tokens in, out and cached")
(schema HealthRow
  (:f provider String)
  (:f alias String)
  (:f calls Int64)
  (:f ok Int64)
  (:f up429 Int64)
  (:f own Int64)
  (:f failed Int64)
  (:f p50 Int64)
  (:f p95 Int64)
  (:f tokIn Int64)
  (:f tokOut Int64)
  (:f tokCached Int64))

fn defaultHealthHours -> Int64
  24

fn pruneMinCalls -> Int64
  30

fn pruneOkPercent -> Int64
  20

fn percentile xs: (List Int64) pct: Int64 -> Int64
  (let [(n (listLength xs))
        (sorted (listSort xs))]
    (if (= n 0) 0
      (optionOr (listGet sorted (max 0 (- (/ (+ (* pct n) 99) 100) 1))) 0)))

fn countOutcome rows: (List ul/CallRow) outcome: String -> Int64
  (listLength (filter (fn [(r ul/CallRow)] -> Bool (= r.outcome outcome)) rows))

fn healthRowOf provider: String alias: String group: (List ul/CallRow) -> HealthRow
  (let [(sent (filter lim/sentRow? group))
        (oks (filter (fn [(r ul/CallRow)] -> Bool (= r.outcome "ok")) sent))
        (lat (map (fn [(r ul/CallRow)] -> Int64 (optionOr r.ms 0)) (filter (fn [(r ul/CallRow)] -> Bool (some? r.ms)) oks)))
        (calls (listLength sent))
        (up429 (countOutcome sent "429"))]
    (HealthRow :provider provider :alias alias :calls calls :ok (listLength oks) :up429 up429
               :own (- (listLength group) calls) :failed (- calls (+ (listLength oks) up429))
               :p50 (percentile lat 50) :p95 (percentile lat 95)
               :tokIn (fold (fn [(n Int64) (r ul/CallRow)] -> Int64 (+ n r.inTokens)) 0 sent)
               :tokOut (fold (fn [(n Int64) (r ul/CallRow)] -> Int64 (+ n r.outTokens)) 0 sent)
               :tokCached (fold (fn [(n Int64) (r ul/CallRow)] -> Int64 (+ n r.cachedTokens)) 0 sent)))

fn groupRows rows: (List ul/CallRow) key: (fn [ul/CallRow] -> String) -> (Map String (List ul/CallRow))
  (fold (fn [(acc (Map String (List ul/CallRow))) (r ul/CallRow)] -> (Map String (List ul/CallRow))
          (mapSet acc (key r) (cons r (optionOr (mapGet acc (key r)) (list)))))
    (mapEmpty) rows)

; (:m :ref GW-HEALTH-REPORT :do "one row per provider and alias seen in rows, busiest first")
fn healthRows rows: (List ul/CallRow) -> (List HealthRow)
  (let [(groups (groupRows rows (fn [(r ul/CallRow)] -> String (str r.provider "|" r.alias))))
        (hs (map (fn [(k String)] -> HealthRow
                   (let [(parts (stringSplit k "|"))]
                     (healthRowOf (optionOr (listHead parts) "") (optionOr (listGet parts 1) "") (optionOr (mapGet groups k) (list)))))
                 (mapKeys groups)))]
    (listReverse (listSortBy (fn [(h HealthRow)] -> Int64 h.calls) hs)))

; (:m :ref GW-HEALTH-REPORT :do "one row per provider summing its aliases (alias empty)")
fn providerRows rows: (List ul/CallRow) -> (List HealthRow)
  (let [(groups (groupRows rows (fn [(r ul/CallRow)] -> String r.provider)))
        (hs (map (fn [(k String)] -> HealthRow (healthRowOf k "" (optionOr (mapGet groups k) (list)))) (mapKeys groups)))]
    (listReverse (listSortBy (fn [(h HealthRow)] -> Int64 h.calls) hs)))

; (:m :ref GW-HEALTH-REPORT :do "the models with an ok share under 20 percent over at least 30 sent calls: prune candidates")
fn pruneCandidates hs: (List HealthRow) -> (List HealthRow)
  (filter (fn [(h HealthRow)] -> Bool (and (>= h.calls (pruneMinCalls)) (< (* 100 h.ok) (* (pruneOkPercent) h.calls)))) hs)

; (:m :ref GW-HEALTH-REPORT :do "the configured aliases that have no ok call in the window")
fn neverServed configured: (List String) hs: (List HealthRow) -> (List String)
  (filter (fn [(a String)] -> Bool (not (listAny? (fn [(h HealthRow)] -> Bool (and (= h.alias a) (> h.ok 0))) hs))) configured)

; (:m :ref GW-HEALTH-REPORT :do "average attempts per turn times 100, over the rows that carry a session and a turn; 0 when none do")
fn attemptsPerTurnX100 rows: (List ul/CallRow) -> Int64
  (let [(keyed (filter (fn [(r ul/CallRow)] -> Bool (and (some? r.session) (some? r.turn))) (filter lim/sentRow? rows)))
        (groups (groupRows keyed (fn [(r ul/CallRow)] -> String (str (optionOr r.session "") "#" (stringFromInt64 (optionOr r.turn 0))))))
        (turns (listLength (mapKeys groups)))]
    (if (= turns 0) 0 (/ (* 100 (listLength keyed)) turns)))

fn pct ok: Int64 calls: Int64 -> Int64
  (if (= calls 0) 0 (/ (* 100 ok) calls))

fn healthRowText h: HealthRow -> String
  (str "(:m :provider \"" (wire/asnEscape h.provider) "\" :alias \"" (wire/asnEscape h.alias) "\" :calls " (stringFromInt64 h.calls) " :ok " (stringFromInt64 h.ok)
       " :okPct " (stringFromInt64 (pct h.ok h.calls)) " :up429 " (stringFromInt64 h.up429) " :own " (stringFromInt64 h.own) " :failed " (stringFromInt64 h.failed)
       " :p50Ms " (stringFromInt64 h.p50) " :p95Ms " (stringFromInt64 h.p95) " :tokIn " (stringFromInt64 h.tokIn) " :tokOut " (stringFromInt64 h.tokOut) " :tokCached " (stringFromInt64 h.tokCached) ")")

fn outcomeCount reqs: (List rq/ReqRow) outcome: String -> Int64
  (listLength (filter (fn [(r rq/ReqRow)] -> Bool (and (= r.phase "done") (= r.outcome outcome))) reqs))

; (:m :ref GW-HEALTH-REPORT :do "the request accounting of the window: accepted, done, lost, stuck now and the done rows per outcome")
fn requestsText reqs: (List rq/ReqRow) sinceMs: Int64 nowMs: Int64 deadlineSec: Int64 -> String
  (let [(inWin (filter (fn [(r rq/ReqRow)] -> Bool (>= r.atMs sinceMs)) reqs))
        (outcomes (list "ok" "limit" "noRoute" "timeout" "upstreamError" "gatewayError" "clientGone" "lost"))]
    (str "(:requests :accepted " (stringFromInt64 (listLength (filter (fn [(r rq/ReqRow)] -> Bool (= r.phase "accepted")) inWin)))
         " :done " (stringFromInt64 (listLength (filter (fn [(r rq/ReqRow)] -> Bool (= r.phase "done")) inWin)))
         " :lost " (stringFromInt64 (outcomeCount inWin "lost"))
         " :stuck " (stringFromInt64 (listLength (rq/stuckRows reqs nowMs deadlineSec)))
         " :outcomes (" (stringJoin (map (fn [(o String)] -> String (str "(" o " " (stringFromInt64 (outcomeCount inWin o)) ")")) outcomes) " ") "))"))

fn listText xs: (List String) -> String
  (stringJoin (map (fn [(s String)] -> String (str "\"" (wire/asnEscape s) "\"")) xs) " ")

; (:m :ref GW-HEALTH-REPORT :do "the ASN health report of the ledger rows and request rows of the last hours: per provider and per model counts, ok share, upstream 429 against our own refusals, latency percentiles and tokens, the request accounting, prune candidates, configured aliases that never served and attempts per turn")
fn healthReport rows: (List ul/CallRow) reqs: (List rq/ReqRow) configured: (List String) nowMs: Int64 hours: Int64 deadlineSec: Int64 -> String
  (let [(sinceMs (- nowMs (* hours 3600000)))
        (inWin (filter (fn [(r ul/CallRow)] -> Bool (>= r.atMs sinceMs)) rows))
        (models (healthRows inWin))
        (provs (providerRows inWin))]
    (str "(:health :at " (stringFromInt64 nowMs) " :hours " (stringFromInt64 hours) " :rows " (stringFromInt64 (listLength inWin)) "\n"
         "  :providers (" (stringJoin (map healthRowText provs) "\n    ") ")\n"
         "  :models (" (stringJoin (map healthRowText models) "\n    ") ")\n"
         "  " (requestsText reqs sinceMs nowMs deadlineSec) "\n"
         "  :prune (" (stringJoin (map healthRowText (pruneCandidates models)) "\n    ") ")\n"
         "  :neverServed (" (listText (neverServed configured models)) ")\n"
         "  :attemptsPerTurnX100 " (stringFromInt64 (attemptsPerTurnX100 inWin)) ")\n"))

fn healthDir home: String -> String
  (g/posixJoin home ".asl/run/usage/health")

fn healthFileName nowMs: Int64 -> String
  (str "health-" (stringFromInt64 nowMs) ".asn")
