(module aslGateway/tests/routerBalancerTest
  :x [runTests]
  :i [(aslGateway/dispatch :a dp) (aslGateway/config :a cfg) (aslGateway/upstream :a u) (aslGateway/balancer :a bl)
      (aslGateway/server :a srv) (aslGateway/chat :a ch) (aslGateway/usageLedger :a ul) (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b) (aslGateway/omniApi :a om) (asl-json/json :a j)])

fn scratchDir -> String
  "/tmp/routerBalancerTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

; (:m :do "two HTTP models: mA free and weak, mB sub and strong, so the balancer prefers mB while it has room; quotas of 2 and 1 requests a day make the hard caps reachable in a few plans; no CAL file, the ledger is a scratch path")
fn config base: String balancer: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id fixb :kind openai :base \"" base "/b/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\" :tier free :why \"bulk drafts\" :budgets (aDay) :quality 300)"
       " (:model :id mB :provider fixb :name \"chat-b\" :tier sub :why \"hard fixes\" :budgets (bDay) :quality 900))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       balancer ")\n")

fn section -> String
  (str " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\""
       " :budgets ((:budget :id aDay :window day :unit req :size 2 :soft 100 :useOrLose true) (:budget :id bDay :window day :unit req :size 1 :soft 100 :useOrLose true)))")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXA_KEY" "aKey")))

; (:m :ref GW-MODEL-SUBSTITUTION :do "the chat side named no pool model (gemini-free-choice is claimed by the gemini prefix row but is no pool upstream), so the balancer chooses freely; a hint naming a pool model is honoured, see balancerHonourTest")
fn hint -> dp/RouteHint
  (dp/RouteHint :provider "fixa" :model "gemini-free-choice" :intent "" :role "coder" :promptTokens 10)

fn chatRequest -> u/UpstreamRequest
  (u/UpstreamRequest :url "http://fixture.invalid/v1/chat/completions" :fragment "" :method "POST"
    :headers (list (pair "Content-Type" "application/json") (pair "Authorization" "Bearer aKey"))
    :data "{\"model\":\"chat-a\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")

fn bodyModel data: String -> String
  (match (j/jsonParse data) ((ok v) (match (j/jsonGet v "model") ((some m) (match m ((j/jstr s) s) (_ ""))) ((none) ""))) ((err _) ""))

fn rowOf planned: dp/Plan -> dp/DecisionRow
  (match planned ((dp/planSend _ _ _ row) row) ((dp/planReject _ _ row) row) ((dp/planWait _ _ _ row _ _) row))

fn sentSlot planned: dp/Plan -> String
  (match planned ((dp/planSend slot _ _ _) slot) (_ ""))

fn sentModel planned: dp/Plan -> String
  (match planned ((dp/planSend _ _ request _) (bodyModel request.data)) (_ ""))

fn sentUrl planned: dp/Plan -> String
  (match planned ((dp/planSend _ _ request _) request.url) (_ ""))

fn ! wiringFor text: String -> (Result dp/Wiring String)
  (match (cfg/gatewayProfilesLoadText! "/tmp/routerBalancerTest/.asl/gateway.asn" true (ok text) "")
    ((err e) (err e))
    ((ok table)
      (match (u/upstreamSettings (testEnv))
        ((err e) (err e))
        ((ok st) (dp/wiringFromConfig (some table) text st (testEnv) (dp/builtinFamilies))))))

fn ! planAt w: dp/Wiring nowMs: Int64 -> dp/Plan
  (dp/plan w (hint) (chatRequest) (testEnv) nowMs)

fn ! settleAt w: dp/Wiring slot: String nowMs: Int64 -> dp/Wiring
  (pairFirst (dp/settle w slot "fixa" 20 5 true nowMs))

fn ! testRoutesByBalancer base: String -> Bool
  (match (wiringFor (config base (section)))
    ((err e) (do (assert false (str "balancer wiring builds: " e)) false))
    ((ok w)
      (let [(now 1000)
            (first (planAt w now))
            (w1 (settleAt w (sentSlot first) now))
            (second (planAt w1 (+ now 1)))
            (w2 (settleAt w1 (sentSlot second) (+ now 1)))
            (third (planAt w2 (+ now 2)))
            (w3 (settleAt w2 (sentSlot third) (+ now 2)))
            (fourth (planAt w3 (+ now 3)))
            (receipt (dp/decisionText (rowOf first)))]
        (do
          (assert (some? w.pool) "a balancer section gives the wiring a pool")
          (assert (= (sentSlot first) "mB") (str "the balancer overrides the chat pick chat-a with the stronger sub model: " receipt))
          (assert (= (sentModel first) "chat-b") "the request body is retargeted to the picked upstream model name")
          (assert (stringStartsWith? (sentUrl first) (str base "/b/v1")) "the request goes to the picked provider row")
          (assert (= (rowOf first).rule "balancer") "the route row names the balancer as its rule")
          (assert (stringContains? receipt ":why (:balancer :mode balanced :pick mB :tier sub :pacing ") (str "the receipt carries the score parts: " receipt))
          (assert (stringContains? receipt ":source \"declared\"") "the receipt names where the quality came from")
          (assert (= (sentSlot second) "mA") "after settle charges mB's one request, its hard cap moves traffic to mA")
          (assert (= (sentModel second) "chat-a") "the mA pick keeps the chat-a body")
          (assert (= (sentSlot third) "mA") "mA serves until its own cap of 2")
          (assert (match fourth ((dp/planReject status _ _) (= status 429)) (_ false)) "with every quota at its hard cap the plan is a 429")
          (assert (match fourth ((dp/planReject _ reason _) (and (stringStartsWith? reason "(:balancer :refused :mode balanced :budgets (") (stringContains? reason "aDay") (stringContains? reason "bDay"))) (_ false))
                  (str "the 429 reason is one ASN form naming each budget at its cap: " (match fourth ((dp/planReject _ reason _) reason) (_ "not a reject"))))
          (assert (stringContains? (pairSecond (dp/settle w "mB" "fixb" 20 5 true now)) ":balancer charged") "the charge line says the balancer window was charged")
          true))))

fn ! testWithoutSectionUnchanged base: String -> Bool
  (match (wiringFor (config base ""))
    ((err e) (do (assert false (str "plain wiring builds: " e)) false))
    ((ok w)
      (let [(planned (planAt w 1000))
            (receipt (dp/decisionText (rowOf planned)))]
        (do
          (assert (none? w.pool) "without a balancer section the wiring has no pool")
          (assert (= (sentSlot planned) "fixa") "without a balancer section the chat pick passes through")
          (assert (= (sentModel planned) "chat-a") "the passthrough body is untouched")
          (assert (= (rowOf planned).rule "passthrough") "the route row keeps the passthrough rule")
          (assert (not (stringContains? receipt ":why")) (str "the receipt line is the old form, with no score parts: " receipt))
          (assert (not (stringContains? (pairSecond (dp/settle w "fixa" "fixa" 20 5 true 1000)) ":balancer")) "settle prints the old charge line")
          true))))

fn ! testBadSectionFails base: String -> Bool
  (let [(bad (wiringFor (config base " :balancer (:balancer :mode greedy)")))
        (badRef (wiringFor (stringReplace (config base (section)) ":budgets (bDay)" ":budgets (nope)")))]
    (do
      (assert (match bad ((err e) (stringContains? e ":balancer: balancer: unknown mode greedy")) ((ok _) false)) "an unknown mode fails the wiring with a :balancer error")
      (assert (match badRef ((err e) (stringContains? e "unknown budget nope")) ((ok _) false)) "a model naming an unknown budget fails the wiring")
      true))

fn callLine atMs: Int64 alias: String model: String -> String
  (str "(:call :at " atMs " :profile default :intent any :alias " alias " :provider fixb :model \"" model "\" :in 10 :cached 0 :out 5 :reasoning 0 :ttftMs absent :ms absent :outcome ok :charge 0 :tag absent :temperature absent :topP absent :maxTokens absent :effort absent :api chat :stream false :toolCount 0 :promptBytes 0 :sysHash h)\n")

fn ! testLedgerRebuild base: String -> Bool
  (let [(made (dirCreate (scratchDir)))
        (wrote (fileWrite (ledgerPath) (str (callLine 43000000 "chatAlias" "chat-b") (callLine 43000001 "mA" "chat-a"))))
        (loaded (wiringFor (config base (section))))
        (corrupt (fileWrite (ledgerPath) "(:call :not :even close)\n"))
        (broken (wiringFor (config base (section))))
        (cleaned (pathRemove (ledgerPath)))]
    (do
      (assert (and (ok? made) (ok? wrote) (ok? corrupt) (ok? cleaned)) "scratch ledger writes and cleans up")
      (match loaded
        ((err e) (assert false (str "wiring over a recorded ledger builds: " e)))
        ((ok w)
          (let [(planned (planAt w 43200000))]
            (do
              (assert (= (sentSlot planned) "mA") "today's recorded rows fill mB's quota, so the first plan already goes to mA")
              (assert (match w.pool ((some pool) (= (bl/budgetUsed pool.use (bl/Budget :id "aDay" :windowMs 86400000 :anchorMs 0 :headerWindowMs 0 :unit "req" :size 2 :softPct 100 :hardPct 100 :useOrLose true :source "") 43200000) 1)) ((none) false))
                      "a legacy row under a non-pool chat alias that served chat-b counts for mB, a row under pool alias mA counts for mA")
              true))))
      (assert (match broken ((err e) (stringContains? e "usage ledger")) ((ok _) false)) "a corrupt usage ledger fails the wiring loudly instead of routing blind")
      true))

; (:m :do "GW-BALANCER-ALIAS: mB and mB2 serve the same upstream chat-b; a dispatch picked by the balancer is settled and recorded through runEffect! effUsageNote with the chat alias mA, and the ledger row must name the pool alias so loadPool! charges mB2 and not mB")
fn twinSection -> String
  (str " :balancer (:balancer :mode sub :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\""
       " :budgets ((:budget :id aDay :window day :unit req :size 2 :soft 100 :useOrLose true) (:budget :id bDay :window day :unit req :size 1 :soft 100 :useOrLose true) (:budget :id b2Day :window day :unit req :size 1 :soft 100 :useOrLose true)))")

fn twinConfig base: String -> String
  (stringReplace (config base (twinSection))
                 " :budgets (bDay) :quality 900))"
                 " :budgets (bDay) :quality 900) (:model :id mB2 :provider fixb :name \"chat-b\" :tier sub :why \"twin\" :budgets (b2Day) :quality 950))")

fn ! loopFor w: dp/Wiring home: String pending: srv/PendingCall -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (cfg/emptyProfilesCache) :wiring w
    :wiringText none :families (list) :outbox (list) :pendingCall (some pending) :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn ! testTwinAliasesChargedApart base: String -> Bool
  (let [(home (str (scratchDir) "/home"))
        (made (dirCreate home))
        (sharedPath (ul/defaultSharedUsagePath home))
        (cleared (pathRemove sharedPath))
        (pending (srv/PendingCall :intent "any" :model "chat-b" :latencyMs 5 :charge 0 :tag "" :params (ul/defaultCallParams) :profile "default"))]
    (match (wiringFor (twinConfig base))
      ((err e) (do (assert false (str "twin wiring builds: " e)) false))
      ((ok w)
        (let [(planned (planAt w 1000))
              (w1 (settleAt w (sentSlot planned) 1000))
              (ran (srv/runEffect! (loopFor w1 home pending) (ch/effUsageNote "fixb" "mA" "ok" (j/jnull))))
              (after (pairFirst ran))
              (rows (resultOr (ul/readRows! sharedPath) (list)))
              (ledgerText (resultOr (fileReadString sharedPath) ""))
              (copied (fileWrite (ledgerPath) ledgerText))
              (reloaded (wiringFor (twinConfig base)))
              (removed (pathRemove (ledgerPath)))
              (removedShared (pathRemove sharedPath))
              (b2 (bl/Budget :id "b2Day" :windowMs 86400000 :anchorMs 0 :headerWindowMs 0 :unit "req" :size 1 :softPct 100 :hardPct 100 :useOrLose true :source ""))
              (b1 (bl/Budget :id "bDay" :windowMs 86400000 :anchorMs 0 :headerWindowMs 0 :unit "req" :size 1 :softPct 100 :hardPct 100 :useOrLose true :source ""))
              (nowRow (match (listHead rows) ((some r) r.atMs) ((none) 0)))]
          (do
            (assert (and (ok? made) (ok? copied) (ok? removed) (ok? removedShared)) "scratch home and ledger write and clean up")
            (assert (= (sentSlot planned) "mB2") "the balancer picks the stronger twin mB2")
            (assert (= (listLength rows) 1) "one usage row is written")
            (assert (match (listHead rows) ((some r) (= r.alias "mB2")) ((none) false)) (str "the usage row names the pool alias mB2, not the chat alias mA: " ledgerText))
            (assert (none? after.wiring.settledAlias) "the recorded alias is consumed with the pending call")
            (match reloaded
              ((err e) (assert false (str "reload over the recorded row builds: " e)))
              ((ok w2)
                (assert (match w2.pool ((some pool) (and (= (bl/budgetUsed pool.use b2 nowRow) 1) (= (bl/budgetUsed pool.use b1 nowRow) 0))) ((none) false))
                        "after reload the row charges mB2's window and leaves mB's twin window empty")))
            true)))))

; (:m :do "GW-BALANCER-CASCADE: mB has room for 5, so only the failure moves the retry; a failed settle rests mB for failCooldownMs 1000, the cascade retry goes to mA, and after the cooldown mB is picked again")
fn ! testFailedPickSitsOut base: String -> Bool
  (let [(text (stringReplace (stringReplace (config base (section)) "(:budget :id bDay :window day :unit req :size 1" "(:budget :id bDay :window day :unit req :size 5")
                             ":exploreEvery 0 :cal ()" ":exploreEvery 0 :failCooldownMs 1000 :cal ()"))]
    (match (wiringFor text)
      ((err e) (do (assert false (str "cascade wiring builds: " e)) false))
      ((ok w)
        (let [(first (planAt w 43200000))
              (w1 (pairFirst (dp/settle w (sentSlot first) "fixb" 20 5 false 43200000)))
              (retry (planAt w1 43200001))
              (later (planAt w1 43201001))
              (okSettle (pairFirst (dp/settle w (sentSlot first) "fixb" 20 5 true 43200000)))
              (again (planAt okSettle 43200001))]
          (do
            (assert (= (sentSlot first) "mB") "the stronger model is picked first")
            (assert (= (sentSlot retry) "mA") "after mB fails, the cascade retry inside the cooldown goes to mA")
            (assert (= (sentSlot later) "mB") "after the cooldown mB is routable again")
            (assert (= (sentSlot again) "mB") "a successful settle does not rest the model")
            true)))))

; (:m :do "GW-BALANCER-LIVE-QUOTA through dispatch: the server hands each upstream status and headers to dp/observeReply; a 429 on mB with retry-after rests bDay so the next plan goes to mA, a non-pool slot leaves the wiring as it was")
fn ! testUpstream429ThroughDispatch base: String -> Bool
  (let [(text (stringReplace (config base (section)) "(:budget :id bDay :window day :unit req :size 1" "(:budget :id bDay :window day :unit req :size 5"))]
    (match (wiringFor text)
      ((err e) (do (assert false (str "observe wiring builds: " e)) false))
      ((ok w)
        (let [(first (planAt w 43200000))
              (rested (dp/observeReply w "mB" 429 (list (pair "retry-after" "60")) 43200000))
              (after (planAt rested 43200001))
              (back (planAt rested 43260001))
              (stranger (dp/observeReply w "fixa" 429 (list (pair "retry-after" "60")) 43200000))]
          (do
            (assert (= (sentSlot first) "mB") "mB is picked while its budget has room")
            (assert (= (sentSlot after) "mA") "after an upstream 429 on mB the next plan goes to mA")
            (assert (= (sentSlot back) "mB") "after retry-after mB is picked again")
            (assert (= (sentSlot (planAt stranger 43200001)) "mB") "a reply on a non-pool slot changes nothing")
            true)))))

fn ! runTests -> Bool
  (let [(base "http://127.0.0.1:9")]
    (do
      (assert (testRoutesByBalancer base) "routes by balancer")
      (assert (testWithoutSectionUnchanged base) "without section unchanged")
      (assert (testBadSectionFails base) "bad section fails")
      (assert (testLedgerRebuild base) "ledger rebuild")
      (assert (testTwinAliasesChargedApart base) "twin aliases charged apart")
      (assert (testFailedPickSitsOut base) "failed pick sits out")
      (assert (testUpstream429ThroughDispatch base) "upstream 429 through dispatch")
      true))
