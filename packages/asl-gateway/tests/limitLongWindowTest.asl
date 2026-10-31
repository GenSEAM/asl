(module aslGateway/tests/limitLongWindowTest
  :x [runTests]
  :i [(chat :a ch)
      (config :a c)
      (usageLedger :a ul)
      (limits :a lim)
      (localTime :a lt)
      (server :a srv)
      (poolDispatch :a pd)
      (breaker :a b)
      (upstream :a u)
      (dispatch :a dp)
      (omniApi :a om)])

; (:m :ref GW-LIMIT-LONG-WINDOW :do "now is Thursday 2026-10-29 19:00 UTC, UTC day 20755; Oct 10 is day 20736 and the month ends on day 20758")
fn nowMs -> Int64
  1793300400000

fn dayMs -> Int64
  86400000

fn today -> Int64
  20755

fn row at: Int64 provider: String alias: String outcome: String -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias alias :provider provider :model alias
              :inTokens 10 :cachedTokens 0 :outTokens 10 :reasoningTokens 0 :ttftMs none :ms none
              :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn okAt at: Int64 -> ul/CallRow
  (row at "nim" "a1" "ok")

fn okRows n: Int64 from: Int64 -> (List ul/CallRow)
  (map (fn [(i Int64)] -> ul/CallRow (okAt (- from (* i 60000)))) (range 0 n))

fn dayRow day: Int64 calls: Int64 lastMs: Int64 -> ul/DayRow
  (ul/DayRow :day day :provider "nim" :alias "a1" :calls calls :inTokens (* 10 calls) :outTokens (* 10 calls) :cachedTokens 0 :lastMs lastMs)

fn capped window: String calls: Int64 tokens: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "nim" :scope "account" :model "" :window window :calls calls :tokens tokens)

fn verdict ls: (List c/GatewayLimit) rows: (List ul/CallRow) days: (List ul/DayRow) at: Int64 -> String
  (match (lim/decideWith (c/emptyLimitScope) ls rows days "nim" "a1" at) ((some v) v.outcome) ((none) "none"))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "a month window counts the day rows of pruned generations, a trailing window does not, and live rows at or before the rollup's :last are not counted twice")
fn countChecks -> Bool
  (let [(early (list (dayRow 20736 9 (+ (* 20736 (dayMs)) 1000))))
        (one (okRows 1 (- (nowMs) 3600000)))
        (lastMs (- (nowMs) 7200000))
        (overlap (listAppend (okRows 5 lastMs) (okRows 1 (- (nowMs) 60000))))
        (todayDays (list (dayRow (today) 5 lastMs)))]
    (do
      (assert (= (verdict (list (capped "month" 10 0)) one early (nowMs)) "limit:month") "9 rolled-up calls on Oct 10 and 1 live call spend a 10-call month")
      (assert (= (verdict (list (capped "month" 10 0)) one (list) (nowMs)) "none") "without the day rows the same month sees 1 call")
      (assert (= (verdict (list (capped "month" 0 200)) one early (nowMs)) "limit:month") "day-row tokens count: 180 rolled up and 20 live spend 200 tokens")
      (assert (= (verdict (list (capped "month" 0 201)) one early (nowMs)) "none") "200 tokens leave a 201-token month unspent")
      (assert (= (verdict (list (capped "month" 7 0)) overlap todayDays (nowMs)) "none") "5 live rows at or before :last are the day row's 5, so 6 calls, not 11, against 7")
      (assert (= (verdict (list (capped "month" 6 0)) overlap todayDays (nowMs)) "limit:month") "the live row after :last counts: 6 calls spend 6")
      (assert (= (verdict (list (capped "fiveHour" 2 0)) (list) (list (dayRow (today) 10 (- (nowMs) 1000))) (nowMs)) "none") "a trailing fiveHour window counts live rows only")
      (assert (= (verdict (list (capped "week" 10 0)) one (list (dayRow 20753 9 (+ (* 20753 (dayMs)) 1000))) (nowMs)) "limit:week") "a week window (Monday Oct 26 on) counts Tuesday's day row")
      (assert (= (verdict (list (capped "week" 10 0)) one early (nowMs)) "none") "a day row before the week starts is outside it")
      true))

fn monthFrom reset: Int64 -> c/GatewayLimit
  (with (capped "month" 10 0) :resetDay reset)

fn startDay reset: Int64 day: Int64 -> Int64
  (/ (lim/windowStartFor (monthFrom reset) (+ (* day (dayMs)) 43200000)) (dayMs))

fn endDay reset: Int64 day: Int64 -> Int64
  (/ (lim/windowEndFor (monthFrom reset) (+ (* day (dayMs)) 43200000)) (dayMs))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "a month window with :resetDay starts on that day of the month, clamped to the month's length; day 1 is the calendar month")
fn resetChecks -> Bool
  (let [(oct29 (lt/daysFromCivil 2026 10 29))
        (oct28 (lt/daysFromCivil 2026 10 28))
        (sep29 (lt/daysFromCivil 2026 9 29))
        (nov29 (lt/daysFromCivil 2026 11 29))
        (jan29 (lt/daysFromCivil 2027 1 29))
        (feb27 (lt/daysFromCivil 2027 2 27))
        (feb28 (lt/daysFromCivil 2027 2 28))
        (mar29 (lt/daysFromCivil 2027 3 29))
        (oct31 (lt/daysFromCivil 2026 10 31))
        (nov30 (lt/daysFromCivil 2026 11 30))]
    (do
      (assert (= (startDay 29 oct29) oct29) "resetDay 29 on Oct 29 starts the window that day")
      (assert (= (endDay 29 oct29) nov29) "and it ends on Nov 29")
      (assert (= (startDay 29 oct28) sep29) "on Oct 28 the window started on Sep 29")
      (assert (= (startDay 29 feb28) feb28) "February 2027 has 28 days, so resetDay 29 starts on Feb 28")
      (assert (= (startDay 29 feb27) jan29) "on Feb 27 the window started on Jan 29")
      (assert (= (endDay 29 feb27) feb28) "the window from Jan 29 ends on the clamped Feb 28")
      (assert (= (endDay 29 feb28) mar29) "the window from Feb 28 ends on Mar 29")
      (assert (= (startDay 31 nov30) nov30) "resetDay 31 starts on Nov 30 in November")
      (assert (= (startDay 31 (- nov30 1)) oct31) "on Nov 29 the resetDay-31 window started on Oct 31")
      (assert (= (lim/windowStartFor (monthFrom 1) (nowMs)) (lim/windowStartMs "month" (nowMs))) "resetDay 1 is the calendar month")
      true))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "rollingDay trails 24 h and never paces; :pace off lets a calendar row burst and stops it only at its cap")
fn rollingChecks -> Bool
  (let [(hour 3600000)]
    (do
      (assert (= (verdict (list (capped "rollingDay" 3 0)) (okRows 3 (- (nowMs) (* 23 hour))) (list) (nowMs)) "limit:rollingDay") "3 calls 23 h ago spend a 3-call rollingDay")
      (assert (= (verdict (list (capped "rollingDay" 3 0)) (okRows 3 (- (nowMs) (* 25 hour))) (list) (nowMs)) "none") "calls 25 h ago are outside the rolling 24 h")
      (assert (= (verdict (list (capped "rollingDay" 10 0)) (okRows 9 (- (nowMs) 60000)) (list) (nowMs)) "none") "rollingDay never paces: 9 of 10 at once pass")
      (assert (= (verdict (list (capped "rollingDay" 2 0)) (list) (list (dayRow (today) 10 (- (nowMs) 1000))) (nowMs)) "none") "rollingDay counts live rows, not day rows")
      (assert (= (verdict (list (with (capped "day" 10 0) :pace "off")) (okRows 9 (- (nowMs) 60000)) (list) (nowMs)) "none") "a day row with :pace off lets 9 of 10 through at 19 h")
      (assert (= (verdict (list (with (capped "day" 10 0) :pace "off")) (okRows 10 (- (nowMs) 60000)) (list) (nowMs)) "limit:day") "and stops at its cap")
      (assert (= (verdict (list (capped "day" 10 0)) (okRows 9 (- (nowMs) 60000)) (list) (nowMs)) "pace:day") "the same day row paced evenly refuses the 9th call")
      true))

fn paced pace: String -> c/GatewayLimit
  (with (capped "month" 100 0) :pace pace)

; (:m :ref GW-LIMIT-LONG-WINDOW :do ":pace remaining: 40 of 100 spent before today, 3 days left today included, 19 h into the day: today may reach 40 + 60/3 x (19/24 + 0.1) = 57.8 calls; an even spread allows 102.9 by now")
fn remainingChecks -> Bool
  (let [(before (list (dayRow 20736 40 (+ (* 20736 (dayMs)) 1000))))
        (seventeen (okRows 17 (- (nowMs) 60000)))
        (eighteen (okRows 18 (- (nowMs) 60000)))]
    (do
      (assert (= (verdict (list (paced "remaining")) seventeen before (nowMs)) "none") "57 calls are within what is left spread over the days left")
      (assert (= (verdict (list (paced "remaining")) eighteen before (nowMs)) "pace:month") "58 calls are ahead of remaining/daysLeft and pace")
      (assert (= (verdict (list (paced "even")) eighteen before (nowMs)) "none") "the even spread lets the same 58 calls through")
      (assert (= (verdict (list (with (capped "day" 10 0) :pace "remaining")) (okRows 9 (- (nowMs) 60000)) (list) (nowMs)) "pace:day") "on a day window remaining is the even spread: 9 of 10 at 19 h pace")
      true))

fn atList rows: (List ul/CallRow) -> (List Int64)
  (map (fn [(r ul/CallRow)] -> Int64 r.atMs) rows)

fn sentAfter rows: (List ul/CallRow) through: Int64 -> Int64
  (listLength (filter (fn [(r ul/CallRow)] -> Bool (and (> r.atMs through) (ul/sentOutcome? r.outcome))) rows))

fn dayCalls days: (List ul/DayRow) -> Int64
  (fold (fn [(n Int64) (d ul/DayRow)] -> Int64 (+ n d.calls)) 0 days)

fn rollRow i: Int64 -> ul/CallRow
  (cond
    ((< i 6) (okAt (+ (* 20750 (dayMs)) i)))
    ((< i 9) (row (+ (* 20750 (dayMs)) i) "nim" "a1" "pace:day"))
    (else (okAt (+ (* 20751 (dayMs)) i))))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "rotation at three rows per file with keep 1 prunes generations; every sent call is then in a day row or a live row after :last, exactly once, and pace rows are in neither")
fn ! rollupChecks -> Bool
  (let [(home "/tmp/limitLongWindowTestRoll")
        (_ (pathRemove home))
        (made (dirCreate home))
        (path (str home "/calls.asn"))
        (ru (ul/Rollup :path (ul/defaultRollupPath path) :keepDays 62))
        (maxBytes (* 3 (stringLength (ul/callRowLine (rollRow 0)))))
        (wrote (listAll? (fn [(i Int64)] -> Bool (ok? (ul/appendCallRowRolled! path (rollRow i) maxBytes 1 ru))) (range 0 12)))
        (days (resultOr (ul/readDays! ru.path) (list)))
        (live (resultOr (ul/readRows! path) (list)))
        (through (ul/daysThrough days))
        (plain (str home "/plain.asn"))
        (wrotePlain (listAll? (fn [(i Int64)] -> Bool (ok? (ul/appendCallRowWith! plain (rollRow i) maxBytes 1))) (range 0 12)))]
    (do
      (assert (and wrote (= (listLength (ul/generations! path)) 1)) (str "keep 1 leaves one generation: " (stringJoin (map stringFromInt64 (ul/generations! path)) " ")))
      (assert (> (dayCalls days) 0) "pruned generations left day rows")
      (assert (= (+ (dayCalls days) (sentAfter live through)) 9) (str "9 sent calls, each counted once: " (stringFromInt64 (dayCalls days)) " rolled up + " (stringFromInt64 (sentAfter live through)) " live"))
      (assert (listAll? (fn [(d ul/DayRow)] -> Bool (or (= d.day 20750) (= d.day 20751))) days) "day rows are keyed by the calls' UTC day")
      (assert (and wrotePlain (not (ok? (fileStat (ul/defaultRollupPath plain))))) "appendCallRowWith! writes no day rows")
      (do (pathRemove home) true)))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "day rows round-trip through their line, and keptDays drops rows more than keepDays before the newest")
fn rowChecks -> Bool
  (let [(d (dayRow 20755 4 1793300400000))
        (kept (ul/keptDays (list (dayRow 100 1 0) (dayRow 38 1 0) (dayRow 39 1 0)) 62))]
    (do
      (assert (= (ul/dayRowParse (ul/dayRowLine d)) (some d)) "a day row parses back from its line")
      (assert (= (ul/dayRowParse "(:call :at 1)") none) "a call row is not a day row")
      (assert (= (map (fn [(x ul/DayRow)] -> Int64 x.day) kept) (list 100 39)) "keepDays 62 keeps days 39..100 and drops day 38")
      (assert (= (ul/foldCalls (list) (list (row 5 "nim" "a1" "limit:day") (row 6 "nim" "a1" "breaker"))) (list)) "limit and breaker rows never fold into a day row")
      true))

fn ledgerDir -> String
  "/tmp/limitLongWindowTestSrv"

fn ! loopFor text: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home (ledgerDir) :rootDir (ledgerDir) :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText (some text) :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn ! refused! text: String -> Bool
  (match (pairSecond (srv/runEffect! (loopFor text) (ch/effLimit "fp" "m1")))
    ((ch/outStrings xs) (not (listEmpty? xs)))
    (_ false))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "the server seeds the day rows from the shared ledger's .days file, or from :ledgerRollupPath: 9 rolled-up calls earlier this month and 1 live call spend a 10-call month row")
fn ! serverChecks! -> Bool
  (let [(_ (pathRemove (ledgerDir)))
        (made (dirCreate (ledgerDir)))
        (ledger (str (ledgerDir) "/calls.asn"))
        (clock (/ (nowNs) 1000000))
        (start (lim/windowStartMs "month" clock))
        (dayOne (/ start (dayMs)))
        (live (fileWrite ledger (ul/callRowLine (row (- clock 1000) "fp" "m1" "ok"))))
        (rolled (ul/writeDays! (ul/defaultRollupPath ledger) (list (with (dayRow dayOne 9 (+ start 1000)) :provider "fp" :alias "m1"))))
        (other (str (ledgerDir) "/elsewhere.days"))
        (text (fn [(extra String)] -> String (str "(:gateway :v 2 :sharedUsagePath \"" ledger "\"" extra " :limits ((:limit :provider fp :window month :calls 10)))")))
        (byDefault (refused! (text "")))
        (pointedAway (refused! (text (str " :ledgerRollupPath \"" other "\""))))
        (_ (pathRemove (ledgerDir)))]
    (do
      (assert (and (ok? live) (ok? rolled)) "fixture ledger and day rows written")
      (assert byDefault "the month row counts the ledger's .days rows and refuses the 11th call")
      (assert (not pointedAway) "with :ledgerRollupPath at an empty file the same month sees 1 call and admits")
      true))

fn ! checked limits: String extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)) :limits (" limits "))\n") "src" ".asl/mem/calibration/index.asn")

fn ! refusedWith limits: String extra: String name: String -> Bool
  (let [(r (checked limits extra))]
    (and (>= (pairSecond r) 1) (stringContains? (pairFirst r) name)))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "config check: :resetDay 1..31 on month windows only, :pace even or remaining with remaining on calendar windows, :ledgerRollupKeepDays 62..3660, :ledgerRollupPath a non-empty quoted path")
fn ! configChecks -> Bool
  (do
    (assert (= (pairSecond (checked "(:limit :provider fp :window month :calls 10 :resetDay 29 :pace remaining)" " :ledgerRollupKeepDays 62 :ledgerRollupPath \"/tmp/x.days\"")) 0) "a month row with :resetDay 29 and :pace remaining and the rollup rows check clean")
    (assert (refusedWith "(:limit :provider fp :window month :calls 10 :resetDay 0)" "" "resetDay") "config check refuses :resetDay 0")
    (assert (refusedWith "(:limit :provider fp :window month :calls 10 :resetDay 32)" "" "resetDay") "config check refuses :resetDay 32")
    (assert (refusedWith "(:limit :provider fp :window day :calls 10 :resetDay 29)" "" "resetDay") "config check refuses :resetDay on a day window")
    (assert (refusedWith "(:limit :provider fp :window month :calls 10 :pace fast)" "" "pace") "config check refuses :pace fast")
    (assert (refusedWith "(:limit :provider fp :window hour :calls 10 :pace remaining)" "" "pace") "config check refuses :pace remaining on a trailing window")
    (assert (refusedWith "" " :ledgerRollupKeepDays 61" "ledgerRollupKeepDays") "config check refuses :ledgerRollupKeepDays 61")
    (assert (= (pairSecond (checked "(:limit :provider fp :window rollingDay :tokensOut 5000000) (:limit :provider fp :window day :tokensIn 500000000 :pace off)" "")) 0) "a rollingDay row and a day row with :pace off check clean")
    (assert (refusedWith "(:limit :provider fp :window rollingDay :calls 10 :pace remaining)" "" "pace") "config check refuses :pace remaining on rollingDay")
    (assert (refusedWith "" " :ledgerRollupPath 7" "ledgerRollupPath") "config check refuses a :ledgerRollupPath that is not a quoted path")
    true)

fn ! runTests -> Bool
  (and (countChecks) (and (resetChecks) (and (remainingChecks) (and (rollingChecks) (and (rollupChecks) (and (rowChecks) (and (serverChecks!) (configChecks))))))))
