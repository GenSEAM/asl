(module aslGateway/tests/balancerInstanceTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl) (aslGateway/config :a cfg)])

; (:m :ref GW-BALANCER-INSTANCE-DETECT :do "an HTTP model mH and a claude CLI model mC on a weekly subscription; the VPS-shaped config adds a gateway row mac reached through a loopback tunnel, as federationWireTest has it; the ledger is a scratch file")

fn scratchDir -> String
  "/tmp/balancerInstanceTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

fn config gatewayRow: String instance: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY)" gatewayRow ")"
       " :models ((:model :id mH :provider fixa :name \"chat-a\" :tier free :budgets (hDay) :quality 300)"
       " (:model :id mC :provider claude :name \"opus\" :tier sub :budgets (cWeek) :quality 900))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mH)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\"" instance
       " :budgets ((:budget :id hDay :window day :unit req :size 50 :useOrLose true)"
       " (:budget :id cWeek :window week :unit req :size 4 :useOrLose true))))\n")

fn macRow -> String
  " (:provider :id mac :kind gateway :base \"http://127.0.0.1:18080/v1\" :secret macToken)"

fn macRowWith role: String -> String
  (str " (:provider :id mac :kind gateway :base \"http://127.0.0.1:18080/v1\" :secret macToken" role ")")

fn ! poolOf text: String home: String -> (Result bl/Pool String)
  (match (cfg/gatewayProfilesLoadText! (str (scratchDir) "/.asl/gateway.asn") true (ok text) "")
    ((err e) (err e))
    ((ok table)
      (match (bl/loadPool! text (some table) home (fn [(pid String)] -> Bool (= pid "fixa")))
        ((err e) (err e))
        ((ok (none)) (err "no pool"))
        ((ok (some p)) (ok p)))))

fn firstNote pool: bl/Pool -> String
  (optionOr (listGet pool.notes 0) "")

fn hasCli? pool: bl/Pool -> Bool
  (listAny? (fn [(m bl/PoolModel)] -> Bool (= m.id "mC")) pool.bal.models)

fn ! check text: String home: String instance: String cli: Bool note: String -> Bool
  (match (poolOf text home)
    ((err e) (do (assert false (str "pool loads: " e)) false))
    ((ok pool)
      (do
        (assert (= pool.instance instance) (str "instance " instance " expected, got " pool.instance " (" (firstNote pool) ")"))
        (assert (= (hasCli? pool) cli) (str "the claude CLI lane is " (if cli "in" "out of") " the pool"))
        (assert (stringContains? (firstNote pool) note) (str "the first note names the rule: " (firstNote pool)))
        true)))

fn ! runTests -> Bool
  (let [(made (dirCreate (scratchDir)))
        (wrote (fileWrite (ledgerPath) ""))
        (home (scratchDir))]
    (do
      (assert (and (ok? made) (ok? wrote)) "the scratch ledger exists and is empty")
      (assert (check (config "" "") home "local" true "instance local: no gateway row and a local user HOME") "a plain config with a HOME is local and offers the CLI lane")
      (assert (check (config (macRow) "") home "remote" false "instance remote: provider mac is a gateway row to 127.0.0.1 with no :role outward, so vendor CLI lanes stay with that host gateway")
              "a gateway row makes the instance a satellite, though the row reaches its host through a loopback tunnel")
      (assert (check (config (macRow) " :instance local") home "local" true "instance local: declared by :instance") "an explicit :instance local wins over a gateway row")
      (assert (check (config "" " :instance remote") home "remote" false "instance remote: declared by :instance") "an explicit :instance remote wins over a local HOME")
      (assert (check (config "" "") "" "remote" false "instance remote: no HOME") "a gateway with no HOME runs as no local user, so it is remote")
      (assert (check (config (macRowWith " :role outward") "") home "local" true "instance local: gateway rows mac are :role outward and a local user HOME") "a host whose only gateway row federates outward stays local and keeps its CLI lane")
      (assert (check (config (macRowWith " :role satellite") "") home "remote" false "instance remote: provider mac is a gateway row to 127.0.0.1 marked :role satellite") "a row marked satellite makes the instance remote")
      (assert (check (config (str (macRowWith " :role outward") " (:provider :id hub :kind gateway :base \"http://127.0.0.1:18081/v1\" :secret hubToken)") "") home "remote" false "instance remote: provider hub is a gateway row to 127.0.0.1 with no :role outward") "an unmarked row beside an outward one still makes it remote")
      (assert (= (bl/urlHost "https://u:p@Mac.local:8787/v1/chat") "Mac.local") "urlHost drops scheme, userinfo, port and path")
      (assert (= (bl/urlHost "http://[::1]:9/x") "::1") "urlHost unwraps an IPv6 literal")
      (assert (= (bl/urlHost "host") "host") "a bare host is its own host")
      (assert (ok? (pathRemove (ledgerPath))) "the scratch ledger is removed")
      true))
