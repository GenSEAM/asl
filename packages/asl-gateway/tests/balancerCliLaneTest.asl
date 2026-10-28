(module aslGateway/tests/balancerCliLaneTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl) (aslGateway/config :a cfg) (aslGateway/dispatch :a dp) (aslGateway/upstream :a u)])

; (:m :ref GW-BALANCER-CLI-LANES :do "one HTTP model mH, weak and free, and two vendor CLI models on the built-in claude and codex providers: mC strong on a use-or-lose weekly subscription budget, mU with only a plain daily budget; the ledger is a scratch file")

fn scratchDir -> String
  "/tmp/balancerCliLaneTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

fn config instance: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mH :provider fixa :name \"chat-a\" :tier free :budgets (hDay) :quality 300)"
       " (:model :id mC :provider claude :name \"opus\" :tier paid :why \"hard fixes on the subscription\" :budgets (cWeek) :quality 900)"
       " (:model :id mU :provider codex :name \"gpt\" :tier sub :budgets (uDay) :quality 900))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mH)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\"" instance
       " :budgets ((:budget :id hDay :window day :unit req :size 50 :soft 100 :useOrLose true)"
       " (:budget :id cWeek :window week :unit req :size 4 :soft 100 :useOrLose true)"
       " (:budget :id uDay :window day :unit req :size 50 :soft 100))))\n")

fn callLine atMs: Int64 alias: String -> String
  (str "(:call :at " atMs " :profile default :intent any :alias " alias " :provider claude :model opus :in 10 :cached 0 :out 5 :reasoning 0 :ttftMs absent :ms absent :outcome ok :charge 0 :tag absent :temperature absent :topP absent :maxTokens absent :effort absent :api chat :stream false :toolCount 0 :promptBytes 0 :sysHash h)\n")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXA_KEY" "aKey") (pair "HOME" (scratchDir))))

fn ! tableOf text: String -> (Result cfg/GatewayTable String)
  (cfg/gatewayProfilesLoadText! (str (scratchDir) "/.asl/gateway.asn") true (ok text) "")

fn ! poolOf text: String -> (Result bl/Pool String)
  (match (tableOf text)
    ((err e) (err e))
    ((ok table)
      (match (bl/loadPool! text (some table) (scratchDir) (fn [(pid String)] -> Bool (= pid "fixa")))
        ((err e) (err e))
        ((ok (none)) (err "no pool"))
        ((ok (some p)) (ok p)))))

fn pickedId p: bl/Pick -> String
  (match p ((bl/picked id _ _ _) id) ((bl/refused r) (str "refused " r)))

fn modelNamed pool: bl/Pool id: String -> (Option bl/PoolModel)
  (listFind (fn [(m bl/PoolModel)] -> Bool (= m.id id)) pool.bal.models)

fn paceOf pool: bl/Pool id: String now: Int64 -> Int64
  (match (modelNamed pool id) ((some m) (bl/modelPacing pool.bal (bl/effectiveUse pool now) m now)) ((none) -1))

fn hasNote pool: bl/Pool needle: String -> Bool
  (listAny? (fn [(n String)] -> Bool (stringContains? n needle)) pool.notes)

fn ! testLocalLanes now: Int64 -> Bool
  (let [(cleared (fileWrite (ledgerPath) ""))]
    (match (poolOf (config ""))
      ((err e) (do (assert false (str "local pool loads: " e)) false))
      ((ok pool)
        (let [(req (bl/poolRequest pool "any" now 10))
              (cli (bl/poolPickLanes pool req (list "cli")))
              (c1 (bl/poolCharge pool "mC" now 10))
              (c4 (bl/poolCharge (bl/poolCharge (bl/poolCharge c1 "mC" now 10) "mC" now 10) "mC" now 10))]
          (do
            (assert (ok? cleared) "the scratch ledger starts empty")
            (assert (= (bl/laneOf pool "mC") "cli") "a model on the built-in claude CLI provider is a cli lane")
            (assert (= (bl/laneOf pool "mH") "http") "a model on an openai provider dispatch sends to is an http lane")
            (assert (match (modelNamed pool "mC") ((some m) (= (bl/tierName m.tier) "sub")) ((none) false)) "a cli lane is paced as a subscription, tier sub, though its row says paid")
            (assert (none? (modelNamed pool "mU")) "a cli model with no use-or-lose budget is not in the pool")
            (assert (hasNote pool "mU: cli lane names no use-or-lose budget") (str "the pool notes why mU is out: " (stringJoin pool.notes "; ")))
            (assert (= (pickedId (bl/poolPick pool req)) "mH") "the dispatch pick stays on http lanes though the cli model scores higher")
            (assert (= (pickedId cli) "mC") (str "a cli-lane pick offers the vendor CLI: " (pickedId cli)))
            (assert (< (paceOf c1 "mC" now) (paceOf pool "mC" now)) (str "a cli call charged early in the week paces the subscription down: " (paceOf c1 "mC" now) " from " (paceOf pool "mC" now)))
            (assert (stringStartsWith? (pickedId (bl/poolPickLanes c4 (bl/poolRequest c4 "any" now 10) (list "cli"))) "refused every model in mode balanced is at its hard cap")
                    "four cli calls fill the weekly subscription and the cli lane is refused")
            true)))))

fn ! testLedgerPacesCli now: Int64 -> Bool
  (let [(wrote (fileWrite (ledgerPath) (str (callLine (- now 3) "mC") (callLine (- now 2) "mC") (callLine (- now 1) "mC") (callLine now "mC"))))]
    (match (poolOf (config ""))
      ((err e) (do (assert false (str "pool with cli ledger rows loads: " e)) false))
      ((ok pool)
        (do
          (assert (ok? wrote) "the ledger holds four claude CLI calls this week")
          (assert (stringStartsWith? (pickedId (bl/poolPickLanes pool (bl/poolRequest pool "any" now 10) (list "cli"))) "refused")
                  "CLI calls in the shared ledger are charged to the cli lane, so its weekly cap holds across restarts")
          (assert (= (pickedId (bl/poolPickLanes pool (bl/poolRequest pool "any" now 10) (list "http" "cli"))) "mH") "a pick over both lanes falls back to http when the subscription is spent")
          true))))

fn ! testRemoteInstance now: Int64 -> Bool
  (let [(cleared (fileWrite (ledgerPath) ""))]
    (match (poolOf (config " :instance remote"))
      ((err e) (do (assert false (str "remote pool loads: " e)) false))
      ((ok pool)
        (do
          (assert (ok? cleared) "the scratch ledger is empty again")
          (assert (none? (modelNamed pool "mC")) "a remote instance offers no vendor CLI lane")
          (assert (none? (bl/poolTarget pool "mC")) "nor a target for it")
          (assert (hasNote pool "mC: cli lane is local only, left out on instance remote") (str "the pool notes why: " (stringJoin pool.notes "; ")))
          (assert (stringStartsWith? (pickedId (bl/poolPickLanes pool (bl/poolRequest pool "any" now 10) (list "cli"))) "refused") "a cli-lane pick on a remote instance is refused")
          (assert (= (pickedId (bl/poolPick pool (bl/poolRequest pool "any" now 10))) "mH") "http lanes still serve")
          true))))

fn ! testBadInstance -> Bool
  (match (poolOf (config " :instance vps"))
    ((ok _) (do (assert false "an unknown :instance is refused") false))
    ((err e) (do (assert (stringContains? e ":instance is local or remote, not vps") (str "the error names the choice: " e)) true)))

fn testLaneFor -> Bool
  (do
    (assert (= (bl/laneFor "gateway" false "remote") (some "gateway")) "a federation row is a lane on a remote instance, the only way it reaches a CLI")
    (assert (= (bl/laneFor "cli" true "remote") (none)) "a vendor CLI is never a lane on a remote instance")
    (assert (= (bl/laneFor "cli" false "local") (some "cli")) "a vendor CLI is a lane on a local instance")
    (assert (= (bl/laneFor "openai" false "local") (none)) "a provider dispatch cannot send to is no lane")
    (assert (= (bl/laneFor "anthropic" true "remote") (some "http")) "a routable HTTP provider is an http lane anywhere")
    true)

; (:m :do "end to end through dispatch: with the cli model in the pool and scoring higher, a planned HTTP request still goes to mH")
fn ! testDispatchSkipsCli now: Int64 -> Bool
  (let [(cleared (fileWrite (ledgerPath) ""))
        (text (config ""))]
    (match (tableOf text)
      ((err e) (do (assert false (str "table loads: " e)) false))
      ((ok table)
        (match (u/upstreamSettings (testEnv))
          ((err e) (do (assert false (str "settings: " e)) false))
          ((ok st)
            (match (dp/wiringFromConfig (some table) text st (testEnv) (dp/builtinFamilies))
              ((err e) (do (assert false (str "wiring builds: " e)) false))
              ((ok w)
                (let [(planned (dp/plan w (dp/RouteHint :provider "fixa" :model "chat-a" :intent "" :role "coder" :promptTokens 10)
                                        (u/UpstreamRequest :url "http://fixture.invalid/v1/chat/completions" :fragment "" :method "POST"
                                          :headers (list (pair "Content-Type" "application/json") (pair "Authorization" "Bearer aKey"))
                                          :data "{\"model\":\"chat-a\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                                        (testEnv) now))]
                  (do
                    (assert (ok? cleared) "the ledger is empty for the dispatch case")
                    (assert (match w.pool ((some p) (= (bl/laneOf p "mC") "cli")) ((none) false)) "the dispatch wiring pool holds the cli lane")
                    (assert (match planned ((dp/planSend slot _ _ _) (= slot "mH")) (_ false)) "dispatch sends to the http model, never the cli lane")
                    true)))))))))

fn ! runTests -> Bool
  (let [(made (dirCreate (scratchDir)))
        (now 1000000)]
    (do
      (assert (ok? made) "the scratch dir exists")
      (assert (testLocalLanes now) "local lanes")
      (assert (testLedgerPacesCli now) "ledger paces cli")
      (assert (testRemoteInstance now) "remote instance")
      (assert (testBadInstance) "bad instance")
      (assert (testLaneFor) "lane for")
      (assert (testDispatchSkipsCli now) "dispatch skips cli")
      (assert (ok? (pathRemove (ledgerPath))) "the scratch ledger is removed")
      true))
