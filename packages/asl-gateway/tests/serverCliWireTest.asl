(module aslGateway/tests/serverCliWireTest
  :x [runTests]
  :i [(server :a srv) (aslGateway/balancer :a bl) (aslGateway/config :a cfg) (aslGateway/dispatch :a dp) (aslGateway/upstream :a u)
      (aslGateway/chat :a ch) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b) (aslGateway/omniApi :a om) (asl-json/json :a j)])

; (:m :ref GW-BALANCER-CLI-WIRE :do "one vendor CLI model on a weekly use-or-lose budget of 1 request; the first run is admitted and charges it, the second is refused by the budget and a refused effCli answers none (chat then tries its next candidate) without starting a vendor; a pool with no cli lane admits every run")
fn config -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mH :provider fixa :name \"chat-a\" :tier free :budgets (hDay) :quality 300)"
       " (:model :id mC :provider claude :name \"opus\" :tier paid :budgets (cWeek) :quality 900)"
       " (:model :id mU :provider codex :name \"gpt\" :tier sub :budgets (uDay) :quality 900))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mH)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"/tmp/serverCliWireTest.calls.asn\""
       " :budgets ((:budget :id hDay :window day :unit req :size 50 :soft 100 :useOrLose true)"
       " (:budget :id cWeek :window week :unit req :size 1 :soft 100 :useOrLose true)"
       " (:budget :id uDay :window day :unit req :size 50 :soft 100 :useOrLose true))))\n")

fn ! poolOf -> (Result bl/Pool String)
  (match (cfg/gatewayProfilesLoadText! "/tmp/serverCliWireTest/.asl/gateway.asn" true (ok (config)) "")
    ((err e) (err e))
    ((ok table)
      (match (bl/loadPool! (config) (some table) "/tmp" (fn [(pid String)] -> Bool (= pid "fixa")))
        ((err e) (err e))
        ((ok (none)) (err "no pool"))
        ((ok (some p)) (ok p)))))

fn wiringWith w: dp/Wiring pool: (Option bl/Pool) -> dp/Wiring
  (with w :pool pool)

fn loopOf pool: (Option bl/Pool) -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home "/tmp" :rootDir "/tmp" :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (cfg/emptyProfilesCache)
    :wiring (wiringWith (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0)) pool)
    :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :startMs 0)

fn cliOut o: ch/ChatOutcome -> Bool
  (match o ((ch/outCli (none)) true) (_ false))

fn ! runTests -> Bool
  (match (poolOf)
    ((err e) (do (assert false (str "pool loads: " e)) false))
    ((ok pool)
      (let [(args (list (pair "prompt" (j/jstr "hello there"))))
            (loop0 (loopOf (some pool)))
            (first (srv/cliAdmit! loop0 "claude" args))
            (second (srv/cliAdmit! (pairFirst first) "claude" args))
            (refusedRun (srv/runEffect! (pairFirst first) (ch/effCli "claude" args)))
            (open (srv/cliAdmit! (loopOf none) "claude" args))
            (other (srv/cliAdmit! (pairFirst first) "codex" args))
            (unknown (srv/cliAdmit! (pairFirst first) "agy" args))]
        (do
          (assert (pairSecond first) "the first CLI run is admitted")
          (assert (not (pairSecond second)) "the second run is refused: the first one charged the cli alias against its budget")
          (assert (cliOut (pairSecond refusedRun)) "a refused effCli answers none, so chat tries its next candidate")
          (assert (pairSecond open) "with no pool every run is admitted")
          (assert (pairSecond other) "codex is admitted while claude is at its cap: each client is judged by its own aliases")
          (assert (pairSecond unknown) "a client with no cli alias is admitted")
          true))))
