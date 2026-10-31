(module aslGateway/limits
  :x [seedTtlMs needsSeed? longestStartMs keepRows withOwnRow Verdict windowStartMs windowEndMs sentRow? usedCalls usedTokens decide hasLimitFor?
      decideIn decideWith windowStartFor windowEndFor spentRatioWith paceRatioWith coversIn covers? usedCallsIn usedTokensIn usedUsdIn spentRatioIn Lease concurrencyOf liveLeases full? admit release limitKey]
  :i [(aslGateway/config :a c)
      (aslGateway/usageLedger :a ul)
      (aslGateway/localTime :a lt)])

; (:m :ref GW-LIMIT-WINDOWS :do "provider limit windows over the usage ledger: minute, hour and fiveHour trail the clock; day, week (Monday) and month are UTC calendar windows, the way providers reset them. A spent window answers limit:<window> and the member is skipped; a calendar window running ahead of an even spread answers pace:<window> so the pool lasts to the reset")
(schema Verdict
  (:f outcome String)
  (:f reason String))

fn dayMs -> Int64
  86400000

fn trailingMs window: String -> Int64
  (cond
    ((= window "minute") 60000)
    ((= window "hour") 3600000)
    ((= window "fiveHour") 18000000)
    ((= window "rollingDay") 86400000)
    (else 0))

fn monthStartDays days: Int64 offset: Int64 -> Int64
  (let [(ymd (lt/civilFromDays days))
        (y (optionOr (listGet ymd 0) 1970))
        (m (+ (- (optionOr (listGet ymd 1) 1) 1) offset))
        (y2 (+ y (/ m 12)))
        (m2 (+ (mod m 12) 1))]
    (lt/daysFromCivil y2 m2 1))

fn windowStartMs window: String nowMs: Int64 -> Int64
  (let [(days (/ nowMs (dayMs)))]
    (cond
      ((> (trailingMs window) 0) (- nowMs (trailingMs window)))
      ((= window "day") (* days (dayMs)))
      ((= window "week") (* (- days (mod (+ days 3) 7)) (dayMs)))
      (else (* (monthStartDays days 0) (dayMs)))))

fn windowEndMs window: String nowMs: Int64 -> Int64
  (let [(days (/ nowMs (dayMs)))]
    (cond
      ((> (trailingMs window) 0) nowMs)
      ((= window "day") (* (+ days 1) (dayMs)))
      ((= window "week") (* (+ (- days (mod (+ days 3) 7)) 7) (dayMs)))
      (else (* (monthStartDays days 1) (dayMs)))))

fn ymOf days: Int64 -> (Pair Int64 Int64)
  (let [(ymd (lt/civilFromDays days))]
    (pair (optionOr (listGet ymd 0) 1970) (optionOr (listGet ymd 1) 1)))

fn monthDay y: Int64 m: Int64 reset: Int64 -> Int64
  (let [(first (lt/daysFromCivil y m 1))]
    (+ first (- (min reset (- (monthStartDays first 1) first)) 1)))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "a month window with :resetDay R starts on day R of the month at 00:00 UTC, clamped to that month's last day, so a cycle renewing on the 29th starts on 28 February; day 1 is the calendar month")
fn resetStartDays days: Int64 reset: Int64 -> Int64
  (let [(ym (ymOf days))
        (this (monthDay (pairFirst ym) (pairSecond ym) reset))]
    (if (>= days this)
      this
      (let [(prev (ymOf (- (lt/daysFromCivil (pairFirst ym) (pairSecond ym) 1) 1)))]
        (monthDay (pairFirst prev) (pairSecond prev) reset))))

fn resetEndDays days: Int64 reset: Int64 -> Int64
  (let [(next (ymOf (monthStartDays (resetStartDays days reset) 1)))]
    (monthDay (pairFirst next) (pairSecond next) reset))

fn windowStartFor lim: c/GatewayLimit nowMs: Int64 -> Int64
  (if (and (= lim.window "month") (> lim.resetDay 1))
    (* (resetStartDays (/ nowMs (dayMs)) lim.resetDay) (dayMs))
    (windowStartMs lim.window nowMs))

fn windowEndFor lim: c/GatewayLimit nowMs: Int64 -> Int64
  (if (and (= lim.window "month") (> lim.resetDay 1))
    (* (resetEndDays (/ nowMs (dayMs)) lim.resetDay) (dayMs))
    (windowEndMs lim.window nowMs))

; (:m :ref GW-LIMIT-WINDOWS :do "a real attempt: rows the gateway answered itself never reached the provider and do not count; same rule as rateLearn notSent?, kept in usageLedger sentOutcome? so the day rollup counts the same calls")
fn sentRow? r: ul/CallRow -> Bool
  (ul/sentOutcome? r.outcome)

; (:m :ref GW-LIMIT-SCOPES :do "whether a call by provider/alias is inside a limit row's scope: account every alias of the provider, model one alias of it, group the aliases a (:group) row lists for that provider, endpoint every provider whose :base is the row's :endpoint")
fn groupHas? sc: c/LimitScope id: String provider: String alias: String -> Bool
  (listAny? (fn [(g c/GatewayGroup)] -> Bool (and (= g.id id) (and (= g.provider provider) (listContains? g.models alias)))) sc.groups)

fn baseOf sc: c/LimitScope provider: String -> String
  (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) provider)) sc.bases)
    ((some p) (pairSecond p))
    ((none) ""))

fn coversIn sc: c/LimitScope lim: c/GatewayLimit provider: String alias: String -> Bool
  (cond
    ((= lim.scope "account") (= lim.provider provider))
    ((= lim.scope "model") (and (= lim.provider provider) (= lim.model alias)))
    ((= lim.scope "group") (groupHas? sc lim.group provider alias))
    ((= lim.scope "endpoint") (let [(b (baseOf sc provider))] (and (not (stringEmpty? b)) (= b lim.endpoint))))
    (else false))

fn covers? lim: c/GatewayLimit provider: String alias: String -> Bool
  (coversIn (c/emptyLimitScope) lim provider alias)

; (:m :ref GW-LIMIT-SCOPES :do "the cheap pre-check that decides whether a member asks the server at all: a group or endpoint row cannot be resolved without the config's group and provider rows, so it always asks")
fn hasLimitFor? limits: (List c/GatewayLimit) provider: String alias: String -> Bool
  (listAny? (fn [(l c/GatewayLimit)] -> Bool (or (= l.scope "group") (or (= l.scope "endpoint") (covers? l provider alias)))) limits)

fn windowed? lim: c/GatewayLimit -> Bool
  (not (stringEmpty? lim.window))

fn priceOf sc: c/LimitScope alias: String -> (Pair Float64 Float64)
  (match (listFind (fn [(p (Pair String (Pair Float64 Float64)))] -> Bool (= (pairFirst p) alias)) sc.prices)
    ((some p) (pairSecond p))
    ((none) (pair 0.0 0.0)))

; (:m :ref GW-LIMIT-SCOPES :do "usd units: a row's cost is its input tokens at the model's :priceInPerM plus its output tokens at :priceOutPerM, per million; a model with no price costs 0 and never spends a usd limit")
fn rowUsd sc: c/LimitScope r: ul/CallRow -> Float64
  (let [(pr (priceOf sc r.alias))]
    (/ (+ (* (int64ToFloat64 r.inTokens) (pairFirst pr)) (* (int64ToFloat64 r.outTokens) (pairSecond pr))) 1000000.0))

fn inWindowIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> (List ul/CallRow)
  (let [(from (windowStartFor lim nowMs))]
    (filter (fn [(r ul/CallRow)] -> Bool
              (and (>= r.atMs from) (and (<= r.atMs nowMs) (and (sentRow? r) (coversIn sc lim r.provider r.alias)))))
      rows))

fn usedCallsIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Int64
  (listLength (inWindowIn sc lim rows nowMs))

fn usedCalls lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Int64
  (usedCallsIn (c/emptyLimitScope) lim rows nowMs)

fn sumRows rows: (List ul/CallRow) pick: (fn [ul/CallRow] -> Int64) -> Int64
  (fold (fn [(acc Int64) (r ul/CallRow)] -> Int64 (+ acc (pick r))) 0 rows)

fn usedTokensIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Int64
  (sumRows (inWindowIn sc lim rows nowMs) (fn [(r ul/CallRow)] -> Int64 (+ r.inTokens r.outTokens)))

fn usedTokens lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Int64
  (usedTokensIn (c/emptyLimitScope) lim rows nowMs)

fn usedUsdIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (fold (fn [(acc Float64) (r ul/CallRow)] -> Float64 (+ acc (rowUsd sc r))) 0.0 (inWindowIn sc lim rows nowMs))

fn ratio used: Int64 cap: Int64 -> Float64
  (if (> cap 0) (/ (int64ToFloat64 used) (int64ToFloat64 cap)) 0.0)

(schema Used
  (:f calls Int64)
  (:f inTokens Int64)
  (:f outTokens Int64)
  (:f cachedTokens Int64)
  (:f usd Float64))

fn noUse -> Used
  (Used :calls 0 :inTokens 0 :outTokens 0 :cachedTokens 0 :usd 0.0)

fn rowUse sc: c/LimitScope u: Used r: ul/CallRow -> Used
  (with u :calls (+ u.calls 1) :inTokens (+ u.inTokens r.inTokens) :outTokens (+ u.outTokens r.outTokens)
          :cachedTokens (+ u.cachedTokens r.cachedTokens) :usd (+ u.usd (rowUsd sc r)))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "usd of a day row is derived from its tokens at the model's current price, the way a live row's is, never stored")
fn dayUse sc: c/LimitScope u: Used d: ul/DayRow -> Used
  (let [(pr (priceOf sc d.alias))]
    (with u :calls (+ u.calls d.calls) :inTokens (+ u.inTokens d.inTokens) :outTokens (+ u.outTokens d.outTokens)
            :cachedTokens (+ u.cachedTokens d.cachedTokens)
            :usd (+ u.usd (/ (+ (* (int64ToFloat64 d.inTokens) (pairFirst pr)) (* (int64ToFloat64 d.outTokens) (pairSecond pr))) 1000000.0))))

fn calendar? lim: c/GatewayLimit -> Bool
  (= (trailingMs lim.window) 0)

; (:m :ref GW-LIMIT-LONG-WINDOW :do "a calendar window counts the day rows of its days plus the live rows after the rollup's :last, which are in no day row; a trailing window never spans a pruned generation and counts live rows only. Both bounds are inclusive and day aligned for a calendar window, so a day row is whole inside or outside")
fn usedBetween sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) days: (List ul/DayRow) fromMs: Int64 toMs: Int64 -> Used
  (let [(cal (calendar? lim))
        (through (if cal (ul/daysThrough days) 0))
        (live (fold (fn [(u Used) (r ul/CallRow)] -> Used
                      (if (and (>= r.atMs fromMs) (and (<= r.atMs toMs) (and (> r.atMs through) (and (sentRow? r) (coversIn sc lim r.provider r.alias)))))
                        (rowUse sc u r) u))
                    (noUse) rows))]
    (if (not cal)
      live
      (fold (fn [(u Used) (d ul/DayRow)] -> Used
              (if (and (>= (* d.day (dayMs)) fromMs) (and (<= (* d.day (dayMs)) toMs) (coversIn sc lim d.provider d.alias)))
                (dayUse sc u d) u))
            live days)))

; (:m :ref GW-LIMIT-SCOPES :do "a row with several units is as spent as its most spent unit: calls, tokens (in plus out), tokensIn, tokensOut, tokensCached, usd")
fn spentOf lim: c/GatewayLimit u: Used -> Float64
  (max (ratio u.calls lim.calls)
    (max (ratio (+ u.inTokens u.outTokens) lim.tokens)
      (max (ratio u.inTokens lim.tokensIn)
        (max (ratio u.outTokens lim.tokensOut)
          (max (ratio u.cachedTokens lim.tokensCached)
            (if (> lim.usd 0.0) (/ u.usd lim.usd) 0.0))))))

fn spentRatioWith sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) days: (List ul/DayRow) nowMs: Int64 -> Float64
  (if (not (windowed? lim)) 0.0
    (spentOf lim (usedBetween sc lim rows days (windowStartFor lim nowMs) nowMs)))

fn spentRatioIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (spentRatioWith sc lim rows (list) nowMs)

; (:m :ref GW-LIMIT-LONG-WINDOW :do ":pace remaining: what was spent before today stays spent, and today may use what is left over the days left, today included, spread over the day plus a tenth of today's share as burst; on a day window it is the even spread")
fn remainingAllowed sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) days: (List ul/DayRow) start: Int64 end: Int64 nowMs: Int64 -> Float64
  (let [(dayStart (* (/ nowMs (dayMs)) (dayMs)))
        (before (if (<= dayStart start) 0.0 (spentOf lim (usedBetween sc lim rows days start (- dayStart 1)))))
        (daysLeft (max 1 (/ (+ (- end dayStart) (- (dayMs) 1)) (dayMs))))
        (share (/ (int64ToFloat64 (- nowMs dayStart)) (int64ToFloat64 (dayMs))))]
    (+ before (/ (* (max 0.0 (- 1.0 before)) (+ share 0.1)) (int64ToFloat64 daysLeft))))

; (:m :ref GW-LIMIT-WINDOWS :do "adopted: an even spread of the cap over the window plus a tenth of the cap as burst allowance; only calendar windows pace, a trailing minute or hour is already its own spread")
fn paceRatioWith sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) days: (List ul/DayRow) nowMs: Int64 -> Float64
  (if (or (not (windowed? lim)) (or (> (trailingMs lim.window) 0) (= lim.pace "off"))) 0.0
    (let [(start (windowStartFor lim nowMs))
          (end (windowEndFor lim nowMs))
          (spent (spentRatioWith sc lim rows days nowMs))]
      (if (= lim.pace "remaining")
        (/ spent (remainingAllowed sc lim rows days start end nowMs))
        (/ spent (+ (/ (int64ToFloat64 (- nowMs start)) (int64ToFloat64 (- end start))) 0.1)))))

fn paceRatioIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (paceRatioWith sc lim rows (list) nowMs)

fn worst lim: c/GatewayLimit best: (Option (Pair c/GatewayLimit Float64)) score: Float64 -> (Option (Pair c/GatewayLimit Float64))
  (match best
    ((none) (some (pair lim score)))
    ((some b) (if (> score (pairSecond b)) (some (pair lim score)) best)))

fn paceReason lim: c/GatewayLimit -> String
  (if (= lim.pace "remaining") " use is ahead of what is left spread over the days left" " use is ahead of an even spread")

; (:m :ref GW-LIMIT-SCOPES :do "the binding rule decides, now over every scope: among the windowed limits whose scope contains this call, the spent one with the highest use wins and skips the member, so the tightest budget binds; with none spent, the calendar window furthest ahead of its spread paces. GW-LIMIT-LONG-WINDOW: days are the shared ledger's day rows, so a week or month counts calls whose generation was pruned")
fn decideWith sc: c/LimitScope limits: (List c/GatewayLimit) rows: (List ul/CallRow) days: (List ul/DayRow) provider: String alias: String nowMs: Int64 -> (Option Verdict)
  (let [(mine (filter (fn [(l c/GatewayLimit)] -> Bool (and (windowed? l) (coversIn sc l provider alias))) limits))
        (spent (fold (fn [(acc (Option (Pair c/GatewayLimit Float64))) (l c/GatewayLimit)] -> (Option (Pair c/GatewayLimit Float64))
                       (let [(s (spentRatioWith sc l rows days nowMs))] (if (>= s 1.0) (worst l acc s) acc)))
                 none mine))
        (paced (fold (fn [(acc (Option (Pair c/GatewayLimit Float64))) (l c/GatewayLimit)] -> (Option (Pair c/GatewayLimit Float64))
                       (let [(s (paceRatioWith sc l rows days nowMs))] (if (>= s 1.0) (worst l acc s) acc)))
                 none mine))]
    (match spent
      ((some p) (some (Verdict :outcome (str "limit:" (pairFirst p).window) :reason (str "provider " provider " " (pairFirst p).scope " " (pairFirst p).window " limit spent"))))
      ((none)
       (match paced
         ((some p) (some (Verdict :outcome (str "pace:" (pairFirst p).window) :reason (str "provider " provider " " (pairFirst p).window (paceReason (pairFirst p))))))
         ((none) none)))))

fn decideIn sc: c/LimitScope limits: (List c/GatewayLimit) rows: (List ul/CallRow) provider: String alias: String nowMs: Int64 -> (Option Verdict)
  (decideWith sc limits rows (list) provider alias nowMs)

fn decide limits: (List c/GatewayLimit) rows: (List ul/CallRow) provider: String alias: String nowMs: Int64 -> (Option Verdict)
  (decideIn (c/emptyLimitScope) limits rows provider alias nowMs)

; (:m :ref GW-LIMIT-SCOPES :do "concurrency: a call that passed its windows takes a slot in every :concurrency limit whose scope contains it, held until a sent usage row for its provider and alias frees the oldest, or until the lease runs out; when any covering limit is full the call parks and asks again. The key names a limit's scope")
(schema Lease
  (:f provider String)
  (:f alias String)
  (:f keys (List String))
  (:f atMs Int64))

fn limitKey lim: c/GatewayLimit -> String
  (str lim.scope "|" lim.provider "|" lim.model "|" lim.group "|" lim.endpoint)

fn concurrencyOf sc: c/LimitScope limits: (List c/GatewayLimit) provider: String alias: String -> (List c/GatewayLimit)
  (filter (fn [(l c/GatewayLimit)] -> Bool (and (> l.concurrency 0) (coversIn sc l provider alias))) limits)

fn liveLeases leases: (List Lease) nowMs: Int64 leaseMs: Int64 -> (List Lease)
  (filter (fn [(x Lease)] -> Bool (> x.atMs (- nowMs leaseMs))) leases)

fn heldUnder leases: (List Lease) key: String -> Int64
  (listLength (filter (fn [(x Lease)] -> Bool (listContains? x.keys key)) leases))

fn full? lims: (List c/GatewayLimit) leases: (List Lease) -> Bool
  (listAny? (fn [(l c/GatewayLimit)] -> Bool (>= (heldUnder leases (limitKey l)) l.concurrency)) lims)

fn admit leases: (List Lease) lims: (List c/GatewayLimit) provider: String alias: String nowMs: Int64 -> (List Lease)
  (cons (Lease :provider provider :alias alias :keys (map limitKey lims) :atMs nowMs) leases)

fn release leases: (List Lease) provider: String alias: String -> (List Lease)
  (pairFirst (fold (fn [(acc (Pair (List Lease) Bool)) (x Lease)] -> (Pair (List Lease) Bool)
                     (if (and (not (pairSecond acc)) (and (= x.provider provider) (= x.alias alias)))
                       (pair (pairFirst acc) true)
                       (pair (cons x (pairFirst acc)) (pairSecond acc))))
               (pair (list) false) (listReverse leases)))

; (:m :ref LIMITS-LEDGER-COST :do "the server counts limit windows from rows it holds, not from a whole-file ledger read per attempt: it seeds them once from the shared ledger, adds each row it writes itself, and reseeds every seedTtlMs to pick up other writers. Adopted: 300 s")
fn seedTtlMs -> Int64
  300000

fn needsSeed? seededMs: Int64 nowMs: Int64 -> Bool
  (or (<= seededMs 0) (>= (- nowMs seededMs) (seedTtlMs)))

; (:m :ref LIMITS-LEDGER-COST :do "the oldest instant any configured window can still count: rows before it are dropped at seeding, so a month window is the only thing that keeps a month of rows")
fn longestStartMs limits: (List c/GatewayLimit) nowMs: Int64 -> Int64
  (fold (fn [(acc Int64) (l c/GatewayLimit)] -> Int64 (if (windowed? l) (min acc (windowStartFor l nowMs)) acc)) nowMs limits)

fn keepRows rows: (List ul/CallRow) fromMs: Int64 -> (List ul/CallRow)
  (filter (fn [(r ul/CallRow)] -> Bool (>= r.atMs fromMs)) rows)

; (:m :ref LIMITS-LEDGER-COST :do "a row this server just wrote joins the held rows only once they were seeded; before that the first seed reads it from the ledger")
fn withOwnRow rows: (List ul/CallRow) seededMs: Int64 row: ul/CallRow -> (List ul/CallRow)
  (if (> seededMs 0) (cons row rows) rows)
