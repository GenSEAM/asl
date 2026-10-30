(module aslGateway/tests/limitWindowTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (usageLedger :a ul)
      (limits :a lim)])

; (:m :ref GW-LIMIT-WINDOWS :do "now is Thursday 2026-10-29 19:00 UTC; rows and limits are built here so each case names only what it changes")
fn nowMs -> Int64
  1793300400000

fn row at: Int64 provider: String alias: String outcome: String inTok: Int64 outTok: Int64 -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias alias :provider provider :model alias
              :inTokens inTok :cachedTokens 0 :outTokens outTok :reasoningTokens 0 :ttftMs none :ms none
              :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none)

fn okRow at: Int64 alias: String -> ul/CallRow
  (row at "nim" alias "ok" 10 10)

fn limit window: String scope: String model: String calls: Int64 tokens: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "nim" :scope scope :model model :window window :calls calls :tokens tokens)

fn verdict ls: (List c/GatewayLimit) rows: (List ul/CallRow) alias: String at: Int64 -> String
  (match (lim/decide ls rows "nim" alias at) ((some v) v.outcome) ((none) "none"))

fn times n: Int64 at: Int64 alias: String -> (List ul/CallRow)
  (if (<= n 0) (list) (cons (okRow at alias) (times (- n 1) at alias)))

fn ! drive! step: ch/ChatStep labels: String fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone _) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels (- fuel 1)))
         ((ch/effLimit _ alias)
          (drive! (k (ch/outStrings (if (= alias "m1") (list "limit:day" "provider fp day limit spent") (list)))) (str labels "|limit:" alias) (- fuel 1)))
         ((ch/effUsageNote _ _ outcome _) (drive! (k ch/outDone) (str labels "|note:" outcome) (- fuel 1)))
         ((ch/effHttp _ m _ _ _ _ _ _)
          (drive! (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}")))
                  (str labels "|http:" m) (- fuel 1)))
         (_ (drive! (k ch/outDone) labels (- fuel 1)))))))

fn cfg limits: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 5) (:model :id m2 :provider fp :name \"n2\" :rpm 5)) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default))" limits ")")

fn ! parsed limits: String -> (Result c/GatewayTable String)
  (c/gateway_config_parse! (cfg limits) "default" ".asl/mem/calibration/index.asn")

fn ! run! limits: String -> String
  (match (parsed limits)
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-LIM-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" 200)))))

fn ! runTests -> Bool
  (let [(today 1793235600000)
        (yesterday 1793228400000)
        (dayCap (list (limit "day" "account" "" 3 0)))
        (hourTok (list (limit "hour" "account" "" 0 1000)))
        (weekLim (limit "week" "account" "" 3 0))
        (minuteOne (list (limit "minute" "model" "a1" 1 0)))
        (recent (- (nowMs) 10000))
        (accountMinute (list (limit "minute" "account" "" 1 0)))
        (two (list (limit "hour" "account" "" 10 0) (limit "minute" "account" "" 2 0)))
        (unsent (list (row recent "nim" "a1" "throttled" 1 1) (row recent "nim" "a1" "breaker open" 1 1) (row recent "nim" "a1" "daily" 1 1)
                      (row recent "nim" "a1" "limit:day" 1 1) (row recent "nim" "a1" "pace:day" 1 1) (row recent "nim" "a1" "skipped" 1 1) (okRow recent "a1")))
        (withLimits (run! " :limits ((:limit :provider fp :scope model :model m1 :window day :calls 5))"))
        (none_ (run! ""))
        (bad (parsed " :limits ((:limit :provider fp :window decade :calls 5) (:limit :provider fp :window day :calls 5))"))]
    (do (assert (= (lim/windowStartMs "day" (nowMs)) 1793232000000) "day starts 00:00 UTC")
        (assert (= (lim/windowStartMs "week" (nowMs)) 1792972800000) "week starts Monday 00:00 UTC")
        (assert (= (lim/windowStartMs "month" (nowMs)) 1790812800000) "month starts on the 1st")
        (assert (= (lim/windowEndMs "month" (nowMs)) 1793491200000) "month ends on the next 1st")
        (assert (= (lim/windowEndMs "month" 1797292800000) 1798761600000) "december ends on January 1st")
        (assert (= (lim/windowStartMs "hour" (nowMs)) (- (nowMs) 3600000)) "an hour trails the clock")
        (assert (= (lim/windowStartMs "fiveHour" (nowMs)) (- (nowMs) 18000000)) "fiveHour trails the clock")
        (assert (= (verdict dayCap (listAppend (times 3 today "a1") (times 5 yesterday "a1")) "a1" (nowMs)) "limit:day") "a spent day cap skips")
        (assert (= (verdict dayCap (times 5 yesterday "a1") "a1" (nowMs)) "none") "yesterday's rows are ignored")
        (assert (= (verdict dayCap (times 2 today "a1") "a1" (nowMs)) "none") "under the cap goes ahead")
        (assert (= (verdict hourTok (list (row (- (nowMs) 1800000) "nim" "a1" "ok" 600 500)) "a1" (nowMs)) "limit:hour") "an hour token cap counts in plus out")
        (assert (= (verdict hourTok (list (row (- (nowMs) 5400000) "nim" "a1" "ok" 600 500)) "a1" (nowMs)) "none") "tokens older than the hour are ignored")
        (assert (= (lim/usedCalls weekLim (list (okRow 1792972800000 "a1") (okRow 1793232000000 "a1") (okRow 1792972799999 "a1")) (nowMs)) 2) "the week counts from Monday, not the Sunday before")
        (assert (= (verdict minuteOne (list (okRow recent "a1")) "a1" (nowMs)) "limit:minute") "a model-scoped limit binds its model")
        (assert (= (verdict minuteOne (list (okRow recent "a1")) "a2" (nowMs)) "none") "a model-scoped limit leaves other aliases alone")
        (assert (= (verdict accountMinute (list (okRow recent "a1")) "a2" (nowMs)) "limit:minute") "an account-scoped limit counts every alias")
        (assert (= (verdict two (listAppend (times 4 recent "a1") (list)) "a1" (nowMs)) "limit:minute") "of two rules the spent one binds")
        (assert (= (lim/usedCalls (limit "minute" "account" "" 1 0) unsent (nowMs)) 1) "breaker, skipped, daily, limit, pace and throttled rows are not calls")
        (assert (= (verdict dayCap (list) "a1" (nowMs)) "none") "an empty ledger goes ahead")
        (assert (= (verdict (list (limit "day" "account" "" 1000 0)) (times 300 today "a1") "a1" today) "pace:day") "a day cap running ahead of an even spread paces")
        (assert (= (verdict (list (limit "day" "account" "" 1000 0)) (times 100 today "a1") "a1" today) "none") "a day cap within an even spread goes ahead")
        (assert (stringContains? withLimits "|limit:m1") (str "a provider with a limit row asks: " withLimits))
        (assert (and (stringContains? withLimits "|note:limit:day") (stringContains? withLimits "|http:n2")) (str "a spent member is noted and the cascade goes on: " withLimits))
        (assert (not (stringContains? withLimits "|http:n1")) (str "a skipped member sends nothing: " withLimits))
        (assert (not (stringContains? none_ "|limit:")) (str "a config with no limit rows never asks: " none_))
        (assert (stringContains? none_ "|http:n1") (str "and sends as before: " none_))
        (assert (match bad ((ok t) (and (= (listLength t.limits) 1) (listAny? (fn [(w String)] -> Bool (stringContains? w "window must be")) t.warnings))) ((err _) false)) "a bad limit row is dropped and named, a good one kept")
        (assert (lim/needsSeed? 0 (nowMs)) "never seeded asks for a seed")
        (assert (not (lim/needsSeed? (- (nowMs) 1000) (nowMs))) "a recent seed is reused, no ledger read per attempt")
        (assert (lim/needsSeed? (- (nowMs) (lim/seedTtlMs)) (nowMs)) "a seed older than the ttl is refreshed")
        (assert (= (lim/longestStartMs (list (limit "day" "account" "" 1 0) (limit "month" "account" "" 1 0)) (nowMs)) 1790812800000) "the month window sets how far back rows are kept")
        (assert (= (lim/longestStartMs (list) (nowMs)) (nowMs)) "no limits keep nothing")
        (assert (= (listLength (lim/keepRows (list (okRow 1790812799999 "a1") (okRow 1790812800000 "a1")) 1790812800000)) 1) "rows before the longest window are dropped at seeding")
        (assert (= (listLength (lim/withOwnRow (list) 0 (okRow recent "a1"))) 0) "before the first seed an own row waits for the ledger read")
        (assert (= (listLength (lim/withOwnRow (list) (nowMs) (okRow recent "a1"))) 1) "after the seed an own row is counted without a read")
        true))
