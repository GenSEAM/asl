(module aslGateway/tests/subPaceServerTest
  :x [runTests]
  :i [(server :a srv) (aslGateway/config :a c) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b) (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp) (aslGateway/chat :a ch) (aslGateway/omniApi :a om) (aslGateway/subPace :a sp)])

; (:m :ref SUBPACE :do "the live hook: runEffect! on effSpreadOrder reads the HOME subscriptions file and the shared ledger through its one-minute cache; a member whose subscription is over its hard pace is not in the answer, a member whose window reset has passed is, and no subscriptions file leaves the answer as the spread was")

fn loopAt home: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :startMs 0)

fn stringsOutcome o: ch/ChatOutcome -> (List String)
  (match o ((ch/outStrings xs) xs) (_ (list)))

fn pools -> (List (Pair String String))
  (list (pair "aOver" "overSub:aOver") (pair "aRecovered" "resetSub:aRecovered") (pair "aFree" "nim:aFree"))

fn spread -> (List (Pair String Int64))
  (list (pair "aOver" 5) (pair "aRecovered" 5) (pair "aFree" 5))

fn ! orderAt! l: srv/GatewayLoop -> (Pair srv/GatewayLoop (List String))
  (let [(ran (srv/runEffect! l (ch/effSpreadOrder "p" "coder" (spread) 60 (pools))))]
    (pair (pairFirst ran) (stringsOutcome (pairSecond ran))))

fn ! runTests -> Bool
  (let [(home (str "/tmp/gwSubPaceServer-" (procSelf) "-" (nowNs)))
        (bare (str home "-bare"))
        (_a (dirCreate home))
        (_b (dirCreate (str home "/.asl")))
        (_c (dirCreate bare))
        (subs (str "(:subscriptions :v 1 :updated \"2099-01-01\"\n"
                   "  (:sub :id overSub :renews \"2099-02-01\" :windows ((:monthly :resets \"2099-02-01\" :usedPercent 90 :src opencodeApi :at \"2099-01-01\")))\n"
                   "  (:sub :id resetSub :renews \"2099-02-01\" :windows ((:monthly :resets \"2020-01-01\" :usedPercent 99 :src opencodeApi :at \"2019-12-31\"))))\n"))
        (w (fileWrite (str home "/.asl/subscriptions.asn") subs))
        (first (orderAt! (loopAt home)))
        (second (orderAt! (pairFirst first)))
        (cached (optionOr (mapGet (pairFirst second).spreadState (sp/paceCacheKey)) (mapEmpty)))
        (plain (orderAt! (loopAt bare)))
        (r0 (pathRemove (str home "/.asl/subscriptions.asn")))
        (r00 (pathRemove (str home "/.asl")))
        (r1 (pathRemove home))
        (r2 (pathRemove bare))]
    (do
      (assert (ok? w) "the fixture subscriptions file is written")
      (assert (and (not (listContains? (pairSecond first) "aOver")) (listContains? (pairSecond first) "aRecovered") (listContains? (pairSecond first) "aFree")) (str "the over-pace sub is out, the recovered one and the free one stay: " (pairSecond first)))
      (assert (= (listLength (pairSecond first)) 2) "two members left in the order")
      (assert (and (> (optionOr (mapGet cached "overSub") 1) -1) (= (optionOr (mapGet cached "overSub") 1) 0) (> (optionOr (mapGet cached "resetSub") 0) 1000)) (str "the server keeps the factors in its spread state: over 0, recovered above 1: " (optionOr (mapGet cached "overSub") -1)))
      (assert (= (listSortBy (fn [(s String)] -> String s) (pairSecond second)) (listSortBy (fn [(s String)] -> String s) (pairSecond first))) "the second call reads the cache and answers the same members")
      (assert (= (listLength (pairSecond plain)) 3) (str "no subscriptions file leaves the spread whole: " (pairSecond plain)))
      true))
