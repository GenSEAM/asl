(module aslGateway/tests/limitScopeTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (usageLedger :a ul)
      (limits :a lim)
      (server :a srv)
      (poolDispatch :a pd)
      (breaker :a b)
      (dispatch :a dp)
      (omniApi :a om)
      (asl-tools/fleet/run :a fr)
      (asl-json/json :a j)])

; (:m :ref GW-LIMIT-SCOPES :do "limit rows over scopes account|group|model|endpoint and units calls, tokens, tokensIn, tokensOut, tokensCached, usd and concurrency: a group row shares one budget across its models, an endpoint row across the providers on one base, the tightest budget binds, separate model rows stay separate, a concurrency slot is held from the limit check to the sent usage row, config check rejects what the runtime would drop, and a call parked behind a full limit sleeps and asks again until its queue budget runs out. Now is Thursday 2026-10-29 19:00 UTC")
fn nowMs -> Int64
  1793300400000

fn row at: Int64 provider: String alias: String inTok: Int64 outTok: Int64 cached: Int64 -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias alias :provider provider :model alias
              :inTokens inTok :cachedTokens cached :outTokens outTok :reasoningTokens 0 :ttftMs none :ms none
              :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn calls n: Int64 provider: String alias: String -> (List ul/CallRow)
  (if (<= n 0) (list) (cons (row (- (nowMs) 10000) provider alias 10 10 0) (calls (- n 1) provider alias)))

fn groupG -> c/GatewayGroup
  (c/GatewayGroup :id "G" :provider "nim" :models (list "a1" "a2"))

fn scope -> c/LimitScope
  (c/LimitScope :groups (list (groupG)) :bases (list (pair "nim" "http://x") (pair "groq" "http://x") (pair "other" "http://y"))
                :prices (list (pair "a1" (pair 1.0 2.0))))

fn groupLimit window: String n: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "" :scope "group" :model "" :window window :calls n :tokens 0 :group "G")

fn modelLimit alias: String window: String n: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "nim" :scope "model" :model alias :window window :calls n :tokens 0)

fn verdict ls: (List c/GatewayLimit) rows: (List ul/CallRow) provider: String alias: String -> String
  (match (lim/decideIn (scope) ls rows provider alias (nowMs)) ((some v) v.outcome) ((none) "none"))

fn concLimit scopeName: String group: String alias: String n: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "nim" :scope scopeName :model alias :window "" :calls 0 :tokens 0 :group group :concurrency n)

fn cfgWith extra: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :priceInPerM 1.0 :priceOutPerM 2.0) (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default))" extra ")")

fn checkOf extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (cfgWith extra) "src" ".asl/mem/calibration/index.asn")

fn ! drive! step: ch/ChatStep labels: String parks: Int64 fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone _) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels parks (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels parks (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels parks (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels parks (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels parks (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels parks (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels parks (- fuel 1)))
         ((ch/effSleepMs ms) (drive! (k ch/outDone) (str labels "|sleep:" (stringFromInt64 ms)) parks (- fuel 1)))
         ((ch/effLimit _ alias)
          (drive! (k (ch/outStrings (if (and (= alias "m1") (> parks 0)) (list "park" "provider concurrency limit full" "50") (list))))
                  (str labels "|limit:" alias) (if (= alias "m1") (- parks 1) parks) (- fuel 1)))
         ((ch/effUsageNote _ _ outcome _) (drive! (k ch/outDone) (str labels "|note:" outcome) parks (- fuel 1)))
         ((ch/effHttp _ m _ _ _ _ _ _)
          (drive! (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}")))
                  (str labels "|http:" m) parks (- fuel 1)))
         (_ (drive! (k ch/outDone) labels parks (- fuel 1)))))))

fn ! run! limits: String parks: Int64 queueMs: String -> String
  (match (c/gatewayConfigParse! (cfgWith limits) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (if (stringEmpty? queueMs) (list) (list (pair "X-ASL-Queue-Ms" queueMs))) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-LIM-2"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" parks 200)))))

fn ! loopAt home: String text: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText (some text) :families (list) :outbox (list)
    :pendingCall (some (srv/PendingCall :intent "coder" :model "m" :latencyMs 10 :charge 0 :tag "t" :params (ul/defaultCallParams) :profile "p" :status 0 :reason ""))
    :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn answer o: ch/ChatOutcome -> String
  (match o ((ch/outStrings xs) (stringJoin xs "/")) (_ "other"))

fn ! askLimit! s: srv/GatewayLoop -> (Pair srv/GatewayLoop String)
  (let [(r (srv/runEffect! s (ch/effLimit "fp" "m1")))]
    (pair (pairFirst r) (answer (pairSecond r))))

fn ! runTests -> Bool
  (let [(dayG (list (groupLimit "day" 3)))
        (inG (listAppend (calls 2 "nim" "a1") (calls 1 "nim" "a2")))
        (endpoint (list (c/GatewayLimit :provider "" :scope "endpoint" :model "" :window "day" :calls 2 :tokens 0 :endpoint "http://x")))
        (tokIn (list (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 0 :tokens 0 :tokensIn 100)))
        (tokOut (list (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 0 :tokens 0 :tokensOut 100)))
        (tokCached (list (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 0 :tokens 0 :tokensCached 100)))
        (usd (list (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 0 :tokens 0 :usd 1.0)))
        (recent (- (nowMs) 10000))
        (separate (list (modelLimit "a1" "minute" 1) (modelLimit "a2" "minute" 1)))
        (concOnly (list (concLimit "account" "" "" 2)))
        (conc2 (list (concLimit "group" "G" "" 2)))
        (t0 (nowMs))
        (l0 (lim/admit (list) conc2 "nim" "a1" t0))
        (l1 (lim/admit l0 conc2 "nim" "a2" (+ t0 1)))
        (tight (list (concLimit "group" "G" "" 3) (concLimit "model" "" "a1" 1)))
        (acct (list (concLimit "account" "" "" 1)))
        (good (checkOf " :groups ((:group :id G :provider fp :models (m1 m2))) :limits ((:limit :scope group :group G :window day :calls 100) (:limit :scope endpoint :endpoint \"http://127.0.0.1:1\" :window day :usd 5.0 :tokensIn 1000 :tokensOut 1000 :tokensCached 10) (:limit :provider fp :scope model :model m1 :concurrency 2))"))
        (badScope (checkOf " :limits ((:limit :provider fp :scope planet :window day :calls 5))"))
        (badGroupModel (checkOf " :groups ((:group :id G :provider fp :models (m1 nope)))"))
        (badGroupRef (checkOf " :limits ((:limit :scope group :group Z :window day :calls 5))"))
        (badConc (checkOf " :limits ((:limit :provider fp :concurrency 5000))"))
        (badPoll (checkOf " :concurrencyPollMs 1"))
        (badLease (checkOf " :concurrencyLeaseSec 5"))
        (badUsd (checkOf " :limits ((:limit :provider fp :window day :usd -1.0))"))
        (noUnit (checkOf " :limits ((:limit :provider fp :window day))"))
        (parked (run! " :limits ((:limit :provider fp :scope model :model m1 :concurrency 1))" 2 ""))
        (exhausted (run! " :limits ((:limit :provider fp :scope model :model m1 :concurrency 1))" 100 "120"))
        (home (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/limitScopeTest.XXXXXX" 5000) "")))
        (text (cfgWith " :limits ((:limit :provider fp :scope model :model m1 :concurrency 1))"))
        (s0 (loopAt home text))
        (r1 (askLimit! s0))
        (r2 (askLimit! (pairFirst r1)))
        (freed (srv/runEffect! (pairFirst r2) (ch/effUsageNote "fp" "m1" "ok" (j/jobj (list)))))
        (r3 (askLimit! (pairFirst freed)))
        (skippedNote (srv/runEffect! (pairFirst r3) (ch/effUsageNote "fp" "m1" "limit:day" (j/jobj (list)))))
        (r4 (askLimit! (pairFirst skippedNote)))
        (cleaned (fr/shellOut (str "/bin/rm -rf " home) 5000))]
    (do
      (assert (= (verdict dayG inG "nim" "a1") "limit:day") "a group limit counts every model of the group together")
      (assert (= (verdict dayG inG "nim" "a3") "none") "a model outside the group is not under the group limit")
      (assert (= (verdict dayG (calls 3 "groq" "a1") "nim" "a1") "none") "rows of another provider's alias do not count for the group")
      (assert (= (verdict dayG (calls 2 "nim" "a2") "nim" "a1") "none") "under the group cap goes ahead")
      (assert (= (verdict endpoint (listAppend (calls 1 "nim" "a1") (calls 1 "groq" "z")) "nim" "a1") "limit:day") "an endpoint limit counts the providers on one base together")
      (assert (= (verdict endpoint (calls 2 "other" "z") "nim" "a1") "none") "a provider on another base is outside the endpoint")
      (assert (= (verdict tokIn (list (row recent "nim" "a1" 60 5000 0) (row recent "nim" "a2" 60 0 0)) "nim" "a1") "limit:hour") "tokensIn counts input tokens only")
      (assert (= (verdict tokIn (list (row recent "nim" "a1" 60 5000 0)) "nim" "a1") "none") "output tokens do not spend a tokensIn cap")
      (assert (= (verdict tokOut (list (row recent "nim" "a1" 5000 60 0) (row recent "nim" "a1" 0 60 0)) "nim" "a1") "limit:hour") "tokensOut counts output tokens only")
      (assert (= (verdict tokCached (list (row recent "nim" "a1" 0 0 60) (row recent "nim" "a1" 0 0 60)) "nim" "a1") "limit:hour") "tokensCached counts cached tokens")
      (assert (= (verdict usd (list (row recent "nim" "a1" 600000 200000 0)) "nim" "a1") "limit:hour") "usd prices input and output tokens per million")
      (assert (= (verdict usd (list (row recent "nim" "a1" 500000 0 0)) "nim" "a1") "none") "half the usd cap goes ahead")
      (assert (= (verdict usd (list (row recent "nim" "a2" 5000000 5000000 0)) "nim" "a2") "none") "a model with no price costs nothing")
      (assert (= (verdict (list (groupLimit "hour" 2) (modelLimit "a1" "minute" 3)) (calls 3 "nim" "a1") "nim" "a1") "limit:hour") "of two spent limits the one used up the furthest binds")
      (assert (= (verdict (list (groupLimit "hour" 100) (modelLimit "a1" "minute" 3)) (calls 3 "nim" "a1") "nim" "a1") "limit:minute") "the tighter model limit binds under a roomy group")
      (assert (and (= (verdict separate (calls 1 "nim" "a1") "nim" "a1") "limit:minute") (= (verdict separate (calls 1 "nim" "a1") "nim" "a2") "none")) "separate model rows keep separate budgets")
      (assert (= (verdict concOnly (calls 50 "nim" "a1") "nim" "a1") "none") "a concurrency-only row has no window to spend")
      (assert (= (lim/longestStartMs concOnly (nowMs)) (nowMs)) "a concurrency-only row keeps no ledger rows")
      (assert (= (listLength (lim/concurrencyOf (scope) conc2 "nim" "a1")) 1) "a concurrency limit covers a model of its group")
      (assert (= (listLength (lim/concurrencyOf (scope) conc2 "nim" "a3")) 0) "and not one outside it")
      (assert (and (lim/full? conc2 l1) (not (lim/full? conc2 l0))) "a group cap of 2 is full after two calls, whichever models made them")
      (assert (not (lim/full? conc2 (lim/release l1 "nim" "a1"))) "a sent usage row frees a slot")
      (assert (= (listLength (lim/release l1 "nim" "a9")) 2) "a row for a call that held nothing frees nothing")
      (assert (= (listLength (lim/liveLeases l1 (+ t0 700000) 600000)) 0) "a lease older than the lease time is dropped")
      (assert (= (listLength (lim/liveLeases l1 (+ t0 100) 600000)) 2) "a young lease is kept")
      (assert (lim/full? tight (lim/admit (list) tight "nim" "a1" t0)) "the tightest concurrency limit binds: the model cap of 1 is full under a group cap of 3")
      (assert (lim/full? acct (lim/admit (list) acct "nim" "a1" t0)) "an account concurrency cap counts every alias")
      (assert (= (pairSecond good) 0) (str "a config using every scope and unit is clean: " (pairFirst good)))
      (assert (and (= (pairSecond badScope) 1) (stringContains? (pairFirst badScope) ":scope must be account, group, model or endpoint")) (str "an unknown scope is an error: " (pairFirst badScope)))
      (assert (and (= (pairSecond badGroupModel) 1) (stringContains? (pairFirst badGroupModel) "nope")) (str "a group naming an unknown model is an error: " (pairFirst badGroupModel)))
      (assert (and (= (pairSecond badGroupRef) 1) (stringContains? (pairFirst badGroupRef) "not declared")) (str "a limit naming an undeclared group is an error: " (pairFirst badGroupRef)))
      (assert (and (= (pairSecond badConc) 1) (stringContains? (pairFirst badConc) "concurrency")) (str "concurrency 5000 is out of range: " (pairFirst badConc)))
      (assert (and (= (pairSecond badPoll) 1) (stringContains? (pairFirst badPoll) "concurrencyPollMs")) (str "a poll of 1 ms is out of range: " (pairFirst badPoll)))
      (assert (and (= (pairSecond badLease) 1) (stringContains? (pairFirst badLease) "concurrencyLeaseSec")) (str "a lease of 5 s is out of range: " (pairFirst badLease)))
      (assert (= (pairSecond badUsd) 1) (str "a negative usd cap is an error: " (pairFirst badUsd)))
      (assert (= (pairSecond noUnit) 1) (str "a row with a window and no unit is an error: " (pairFirst noUnit)))
      (assert (and (stringContains? parked "|limit:m1|sleep:50|limit:m1|sleep:50|limit:m1|http:n1") (not (stringContains? parked "outOfFuel"))) (str "a full concurrency limit parks the call: it sleeps the poll interval, asks again and then sends: " parked))
      (assert (and (stringContains? exhausted "|note:limit:concurrency") (stringContains? exhausted "|http:n2") (not (stringContains? exhausted "|http:n1"))) (str "after the queue budget the member is skipped with limit:concurrency and the cascade goes on: " exhausted))
      (assert (and (= (pairSecond r1) "") (stringContains? (pairSecond r2) "park/provider concurrency limit full/250")) (str "the server admits the first call and parks the second: " (pairSecond r1) " then " (pairSecond r2)))
      (assert (= (pairSecond r3) "") (str "a sent usage row frees the slot for the next call: " (pairSecond r3)))
      (assert (stringContains? (pairSecond r4) "park") (str "a skipped usage row frees nothing: " (pairSecond r4)))
      (assert (ok? cleaned) "temp dir removed")
      true))
