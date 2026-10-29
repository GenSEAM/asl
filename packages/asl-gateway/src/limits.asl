(module aslGateway/limits
  :x [Verdict windowStartMs windowEndMs sentRow? usedCalls usedTokens decide hasLimitFor?]
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

fn covers? lim: c/GatewayLimit provider: String alias: String -> Bool
  (and (= lim.provider provider) (or (= lim.scope "account") (= lim.model alias)))

fn hasLimitFor? limits: (List c/GatewayLimit) provider: String alias: String -> Bool
  (listAny? (fn [(l c/GatewayLimit)] -> Bool (covers? l provider alias)) limits)

fn inWindow lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> (List ul/CallRow)
  (let [(from (windowStartMs lim.window nowMs))]
    (filter (fn [(r ul/CallRow)] -> Bool
              (and (>= r.atMs from) (and (<= r.atMs nowMs) (and (sentRow? r) (covers? lim r.provider r.alias)))))
      rows))

fn usedCalls lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Int64
  (listLength (inWindow lim rows nowMs))

fn usedTokens lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Int64
  (fold (fn [(acc Int64) (r ul/CallRow)] -> Int64 (+ acc (+ r.inTokens r.outTokens))) 0 (inWindow lim rows nowMs))

fn ratio used: Int64 cap: Int64 -> Float64
  (if (> cap 0) (/ (int64ToFloat64 used) (int64ToFloat64 cap)) 0.0)

fn spentRatio lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (max (ratio (usedCalls lim rows nowMs) lim.calls) (ratio (usedTokens lim rows nowMs) lim.tokens))

; (:m :ref GW-LIMIT-WINDOWS :do "adopted: an even spread of the cap over the window plus a tenth of the cap as burst allowance; only calendar windows pace, a trailing minute or hour is already its own spread")
fn paceRatio lim: c/GatewayLimit rows: (List ul/CallRow) nowMs: Int64 -> Float64
  (let [(start (windowStartMs lim.window nowMs))
        (end (windowEndMs lim.window nowMs))
        (share (/ (int64ToFloat64 (- nowMs start)) (int64ToFloat64 (- end start))))
        (allowed (+ share 0.1))]
    (if (> (trailingMs lim.window) 0) 0.0
      (/ (spentRatio lim rows nowMs) allowed)))

fn worst lim: c/GatewayLimit best: (Option (Pair c/GatewayLimit Float64)) score: Float64 -> (Option (Pair c/GatewayLimit Float64))
  (match best
    ((none) (some (pair lim score)))
    ((some b) (if (> score (pairSecond b)) (some (pair lim score)) best)))

; (:m :ref GW-LIMIT-WINDOWS :do "the binding rule decides: among the limits covering this provider and alias, the spent one with the highest use wins and skips the member; with none spent, the calendar window furthest ahead of its even spread paces")
fn decide limits: (List c/GatewayLimit) rows: (List ul/CallRow) provider: String alias: String nowMs: Int64 -> (Option Verdict)
  (let [(mine (filter (fn [(l c/GatewayLimit)] -> Bool (covers? l provider alias)) limits))
        (spent (fold (fn [(acc (Option (Pair c/GatewayLimit Float64))) (l c/GatewayLimit)] -> (Option (Pair c/GatewayLimit Float64))
                       (let [(s (spentRatio l rows nowMs))] (if (>= s 1.0) (worst l acc s) acc)))
                 none mine))
        (paced (fold (fn [(acc (Option (Pair c/GatewayLimit Float64))) (l c/GatewayLimit)] -> (Option (Pair c/GatewayLimit Float64))
                       (let [(s (paceRatio l rows nowMs))] (if (>= s 1.0) (worst l acc s) acc)))
                 none mine))]
    (match spent
      ((some p) (some (Verdict :outcome (str "limit:" (pairFirst p).window) :reason (str "provider " provider " " (pairFirst p).scope " " (pairFirst p).window " limit spent"))))
      ((none)
       (match paced
         ((some p) (some (Verdict :outcome (str "pace:" (pairFirst p).window) :reason (str "provider " provider " " (pairFirst p).window " use is ahead of an even spread"))))
         ((none) none)))))
