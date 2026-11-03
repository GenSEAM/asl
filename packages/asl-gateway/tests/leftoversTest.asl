(module aslGateway/tests/leftoversTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (usageLedger :a ul)
      (server :a srv)
      (poolDispatch :a pd)
      (breaker :a b)
      (dispatch :a dp)
      (omniApi :a om)
      (asl-json/json :a j)])

; (:m :ref GW-LIMIT-LEFTOVERS :do "three leftovers of the limit scopes: :queueBudgetSec above 3600 is a config error and the runtime default 30, a park that ends in limit:concurrency leaves a usage-ledger row with that outcome (it already did; this guards it end to end through the real effUsageNote path), and the 503s the gateway makes itself carry Retry-After from (:gateway :busyRetrySec), default 1")
fn cfgWith extra: String -> String
  (cfgChain "m1 m2" extra)

fn cfgChain chain: String extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\") (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (" chain "))))) :uses ((:use :for default :profile default)))")

fn checkOf extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (cfgWith extra) "src" ".asl/mem/calibration/index.asn")

fn headersOf o: ch/ChatOutcome -> (List (Pair String String))
  (match o
    ((ch/outHttp r) (match r ((ch/httpError _ _ h _) h) (_ (list))))
    (_ (list)))

fn statusOfOut o: ch/ChatOutcome -> Int64
  (match o
    ((ch/outHttp r) (match r ((ch/httpError s _ _ _) s) (_ 0)))
    (_ 0))

fn headerOf o: ch/ChatOutcome name: String -> String
  (fold (fn [(acc String) (h (Pair String String))] -> String (if (= (pairFirst h) name) (pairSecond h) acc)) "-" (headersOf o))

fn ! parsed! extra: String -> (Result c/GatewayTable String)
  (c/gatewayConfigParse! (cfgWith extra) "default" ".asl/mem/calibration/index.asn")

fn queueSecOf r: (Result c/GatewayTable String) -> Float64
  (match r ((ok t) t.queueBudgetSec) ((err _) -1.0))

fn warnsAbout r: (Result c/GatewayTable String) word: String -> Bool
  (match r ((ok t) (listAny? (fn [(w String)] -> Bool (stringContains? w word)) t.warnings)) ((err _) false))

fn ! loopAt home: String wt: (Option String) -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText wt :families (list) :outbox (list)
    :pendingCall (some (srv/PendingCall :intent "coder" :model "m" :latencyMs 10 :charge 0 :tag "t" :params (ul/defaultCallParams) :profile "p" :status 0 :reason ""))
    :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

; (:m :ref GW-LIMIT-LEFTOVERS :do "every ask is answered park, so the call parks until its queue budget is gone and the member is skipped; each usage note runs the real effUsageNote path against the loop's ledger")
fn ! drive! s: srv/GatewayLoop step: ch/ChatStep labels: String fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone _) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! s (k (ch/outPath "/tmp")) labels (- fuel 1)))
         ((ch/effIsDir _) (drive! s (k (ch/outBool true)) labels (- fuel 1)))
         ((ch/effClock) (drive! s (k (ch/outFloat 1.0)) labels (- fuel 1)))
         ((ch/effBreakerDown _) (drive! s (k (ch/outFloat 0.0)) labels (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! s (k (ch/outFloats (list 0.0))) labels (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! s (k (ch/outBool true)) labels (- fuel 1)))
         ((ch/effCli _ _) (drive! s (k (ch/outCli none)) labels (- fuel 1)))
         ((ch/effSleepMs ms) (drive! s (k ch/outDone) labels (- fuel 1)))
         ((ch/effLimit _ alias)
          (drive! s (k (ch/outStrings (if (= alias "m1") (list "park" "provider concurrency limit full" "50") (list)))) labels (- fuel 1)))
         ((ch/effUsageNote _ _ outcome _)
          (let [(ran (srv/runEffect! s eff))]
            (drive! (pairFirst ran) (k ch/outDone) (str labels "|note:" outcome) (- fuel 1))))
         ((ch/effHttp _ m _ _ _ _ _ _)
          (drive! s (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))) (str labels "|http:" m) (- fuel 1)))
         (_ (drive! s (k ch/outDone) labels (- fuel 1)))))))

fn ! parkedRun! home: String -> String
  (match (c/gatewayConfigParse! (cfgChain "m1" " :limits ((:limit :provider fp :scope model :model m1 :concurrency 1))") "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (loopAt home none)
                  (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list (pair "X-ASL-Queue-Ms" "100")) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-LEFT-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" 200)))))

fn ! runTests -> Bool
  (let [(ok3600 (checkOf " :queueBudgetSec 3600"))
        (over (checkOf " :queueBudgetSec 3601"))
        (huge (checkOf " :queueBudgetSec 86400"))
        (pOver (parsed! " :queueBudgetSec 3601"))
        (pEdge (parsed! " :queueBudgetSec 3600"))
        (pLow (parsed! " :queueBudgetSec 4"))
        (busyOk (checkOf " :busyRetrySec 5"))
        (busyZero (checkOf " :busyRetrySec 0"))
        (busyHigh (checkOf " :busyRetrySec 3601"))
        (dflt (srv/busyOutcomeIn "(:gateway :v 2)" "endpoint gone"))
        (tuned (srv/busyOutcomeIn "(:gateway :v 2 :busyRetrySec 7)" "endpoint gone"))
        (bad (srv/busyOutcomeIn "(:gateway :v 2 :busyRetrySec 9999)" "endpoint gone"))
        (home "/tmp/leftoversTest")
        (_ (pathRemove home))
        (made (dirCreate home))
        (viaLoop (srv/busyOutcome (loopAt home (some "(:gateway :v 2 :busyRetrySec 4)")) "warm"))
        (plan503 (srv/planOutcome (loopAt home none) 503 "no endpoint admitted"))
        (plan429 (srv/planOutcome (loopAt home none) 429 "rate"))
        (shared (ul/defaultSharedUsagePath home))
        (ran (parkedRun! home))
        (rows (resultOr (ul/readRows! shared) (list)))
        (skipRows (filter (fn [(r ul/CallRow)] -> Bool (= r.outcome "limit:concurrency")) rows))
        (_ (pathRemove home))]
    (do
      (assert (= (pairSecond ok3600) 0) (str "a queue budget of 3600 s is the top of the range: " (pairFirst ok3600)))
      (assert (and (= (pairSecond over) 1) (stringContains? (pairFirst over) "queueBudgetSec") (stringContains? (pairFirst over) "3600")) (str "a queue budget above 3600 s is a config error naming the bound: " (pairFirst over)))
      (assert (= (pairSecond huge) 1) (str "a day-long queue budget is a config error: " (pairFirst huge)))
      (assert (and (= (queueSecOf pOver) 30.0) (warnsAbout pOver "queueBudgetSec")) "at runtime an over-range queue budget warns and keeps the 30 s default")
      (assert (and (= (queueSecOf pEdge) 3600.0) (not (warnsAbout pEdge "queueBudgetSec"))) "3600 s loads whole without a warning")
      (assert (= (queueSecOf pLow) 4.0) "an in-range queue budget is kept")
      (assert (= (pairSecond busyOk) 0) (str "busyRetrySec 5 is in range: " (pairFirst busyOk)))
      (assert (and (= (pairSecond busyZero) 1) (stringContains? (pairFirst busyZero) "busyRetrySec")) (str "busyRetrySec 0 is a config error: " (pairFirst busyZero)))
      (assert (and (= (pairSecond busyHigh) 1) (stringContains? (pairFirst busyHigh) "busyRetrySec")) (str "busyRetrySec above 3600 is a config error: " (pairFirst busyHigh)))
      (assert (and (= (statusOfOut dflt) 503) (= (headerOf dflt "Retry-After") "1")) (str "a gateway-made 503 carries Retry-After 1 by default: " (headerOf dflt "Retry-After")))
      (assert (= (headerOf dflt (ch/gatewayOriginHeader)) "gateway") "the 503 still names the gateway as its origin")
      (assert (= (headerOf tuned "Retry-After") "7") (str "(:gateway :busyRetrySec 7) sets the Retry-After: " (headerOf tuned "Retry-After")))
      (assert (= (headerOf bad "Retry-After") "1") (str "an out-of-range busyRetrySec keeps the default: " (headerOf bad "Retry-After")))
      (assert (= (headerOf viaLoop "Retry-After") "4") (str "the loop form reads busyRetrySec from the wiring text: " (headerOf viaLoop "Retry-After")))
      (assert (and (= (statusOfOut plan503) 503) (= (headerOf plan503 "Retry-After") "1")) "a planner 503 (no endpoint admitted) carries Retry-After")
      (assert (and (= (statusOfOut plan429) 429) (= (headerOf plan429 "Retry-After") "-")) "a planner status other than 503 stays a plain error without Retry-After")
      (assert (and (stringContains? ran "|note:limit:concurrency") (not (stringContains? ran "|http:n"))) (str "a park that outlasts its queue budget on the last member is skipped with a limit:concurrency note: " ran))
      (assert (= (listLength skipRows) 1) (str "the skipped park leaves one usage-ledger row with outcome limit:concurrency: " (stringFromInt64 (listLength rows)) " rows"))
      true))
