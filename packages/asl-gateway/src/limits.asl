(module aslGateway/limits
  :x [seedTtlMs needsSeed? longestStartMs keepRows withOwnRow Verdict windowStartMs windowEndMs sentRow? usedCalls usedTokens decide hasLimitFor?
      decideIn coversIn covers? usedCallsIn usedTokensIn usedUsdIn spentRatioIn Lease concurrencyOf liveLeases full? admit release limitKey]
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

; (:m :ref GW-LIMIT-WINDOWS :do "a real attempt: rows the gateway answered itself (open breaker, skipped member, daily cap, a limit or pace skip, a local bucket throttle) never reached the provider and do not count; same rule as rateLearn notSent?")
fn sentRow? r: ul/CallRow -> Bool
  (let [(o r.outcome)]
    (not (or (stringStartsWith? o "breaker") (or (stringStartsWith? o "skipped") (or (stringStartsWith? o "daily") (or (stringStartsWith? o "limit") (or (stringStartsWith? o "pace") (= o "throttled"))))))))

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
  (let [(from (windowStartMs lim.window nowMs))]
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

; (:m :ref GW-LIMIT-SCOPES :do "a row with several units is as spent as its most spent unit: calls, tokens (in plus out), tokensIn, tokensOut, tokensCached, usd")
fn spentRatioIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (if (not (windowed? lim)) 0.0
    (let [(inw (inWindowIn sc lim rows nowMs))]
      (max (ratio (listLength inw) lim.calls)
        (max (ratio (sumRows inw (fn [(r ul/CallRow)] -> Int64 (+ r.inTokens r.outTokens))) lim.tokens)
          (max (ratio (sumRows inw (fn [(r ul/CallRow)] -> Int64 r.inTokens)) lim.tokensIn)
            (max (ratio (sumRows inw (fn [(r ul/CallRow)] -> Int64 r.outTokens)) lim.tokensOut)
              (max (ratio (sumRows inw (fn [(r ul/CallRow)] -> Int64 r.cachedTokens)) lim.tokensCached)
                (if (> lim.usd 0.0) (/ (fold (fn [(acc Float64) (r ul/CallRow)] -> Float64 (+ acc (rowUsd sc r))) 0.0 inw) lim.usd) 0.0))))))))

; (:m :ref GW-LIMIT-WINDOWS :do "adopted: an even spread of the cap over the window plus a tenth of the cap as burst allowance; only calendar windows pace, a trailing minute or hour is already its own spread")
fn paceRatioIn sc: c/LimitScope lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (if (or (not (windowed? lim)) (> (trailingMs lim.window) 0)) 0.0
    (let [(start (windowStartMs lim.window nowMs))
          (end (windowEndMs lim.window nowMs))
          (share (/ (int64ToFloat64 (- nowMs start)) (int64ToFloat64 (- end start))))
          (allowed (+ share 0.1))]
      (/ (spentRatioIn sc lim rows nowMs) allowed)))

fn worst lim: c/GatewayLimit best: (Option (Pair c/GatewayLimit Float64)) score: Float64 -> (Option (Pair c/GatewayLimit Float64))
  (match best
    ((none) (some (pair lim score)))
    ((some b) (if (> score (pairSecond b)) (some (pair lim score)) best)))

; (:m :ref GW-LIMIT-SCOPES :do "the binding rule decides, now over every scope: among the windowed limits whose scope contains this call, the spent one with the highest use wins and skips the member, so the tightest budget binds; with none spent, the calendar window furthest ahead of its even spread paces")
fn decideIn sc: c/LimitScope limits: (List c/GatewayLimit) rows: (List ul/CallRow) provider: String alias: String nowMs: Int64 -> (Option Verdict)
  (let [(mine (filter (fn [(l c/GatewayLimit)] -> Bool (and (windowed? l) (coversIn sc l provider alias))) limits))
        (spent (fold (fn [(acc (Option (Pair c/GatewayLimit Float64))) (l c/GatewayLimit)] -> (Option (Pair c/GatewayLimit Float64))
                       (let [(s (spentRatioIn sc l rows nowMs))] (if (>= s 1.0) (worst l acc s) acc)))
                 none mine))
        (paced (fold (fn [(acc (Option (Pair c/GatewayLimit Float64))) (l c/GatewayLimit)] -> (Option (Pair c/GatewayLimit Float64))
                       (let [(s (paceRatioIn sc l rows nowMs))] (if (>= s 1.0) (worst l acc s) acc)))
                 none mine))]
    (match spent
      ((some p) (some (Verdict :outcome (str "limit:" (pairFirst p).window) :reason (str "provider " provider " " (pairFirst p).scope " " (pairFirst p).window " limit spent"))))
      ((none)
       (match paced
         ((some p) (some (Verdict :outcome (str "pace:" (pairFirst p).window) :reason (str "provider " provider " " (pairFirst p).window " use is ahead of an even spread"))))
         ((none) none)))))

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
  (fold (fn [(acc Int64) (l c/GatewayLimit)] -> Int64 (if (windowed? l) (min acc (windowStartMs l.window nowMs)) acc)) nowMs limits)

fn keepRows rows: (List ul/CallRow) fromMs: Int64 -> (List ul/CallRow)
  (filter (fn [(r ul/CallRow)] -> Bool (>= r.atMs fromMs)) rows)

; (:m :ref LIMITS-LEDGER-COST :do "a row this server just wrote joins the held rows only once they were seeded; before that the first seed reads it from the ledger")
fn withOwnRow rows: (List ul/CallRow) seededMs: Int64 row: ul/CallRow -> (List ul/CallRow)
  (if (> seededMs 0) (cons row rows) rows)
