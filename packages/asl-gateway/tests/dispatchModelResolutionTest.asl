(module aslGateway/tests/dispatchModelResolutionTest
  :x [runTests]
  :i [(aslGateway/dispatch :a dp) (aslGateway/config :a cfg) (aslGateway/upstream :a u) (aslGateway/balancer :a bl) (asl-json/json :a j)])

; (:m :ref GW-UNKNOWN-MODEL-FALLTHROUGH :do "a table with mA on fixa (chat-a) and mB on fixb (chat-b), with and without a balancer section that prefers mB; plans are pure, so a refused plan has sent nothing")

fn scratchDir -> String
  "/tmp/dispatchModelResolutionTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

fn noon -> Int64 43200000

fn config balancer: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/a/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id fixb :kind openai :base \"http://127.0.0.1:9/b/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\" :tier free :budgets (aDay) :quality 300)"
       " (:model :id mB :provider fixb :name \"chat-b\" :tier sub :budgets (bDay) :quality 900))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))" balancer ")\n")

fn section -> String
  (str " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\""
       " :budgets ((:budget :id aDay :window day :unit req :size 5 :useOrLose true) (:budget :id bDay :window day :unit req :size 5 :useOrLose true)))")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXA_KEY" "aKey") (pair "HOME" (scratchDir))))

fn ! wiringOf text: String -> (Result dp/Wiring String)
  (match (cfg/gatewayProfilesLoadText! (str (scratchDir) "/.asl/gateway.asn") true (ok text) "")
    ((err e) (err e))
    ((ok table)
      (match (u/upstreamSettings (testEnv))
        ((err e) (err e))
        ((ok st) (dp/wiringFromConfig (some table) text st (testEnv) (dp/builtinFamilies))))))

fn request model: String -> u/UpstreamRequest
  (u/UpstreamRequest :url "http://127.0.0.1:9/a/v1/chat/completions" :fragment "" :method "POST"
    :headers (list (pair "Content-Type" "application/json") (pair "Authorization" "Bearer aKey"))
    :data (str "{\"model\":\"" model "\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"))

fn ! planOf w: dp/Wiring provider: String model: String -> dp/Plan
  (dp/plan w (dp/RouteHint :provider provider :model model :intent "" :role "coder" :promptTokens 10) (request model) (testEnv) (noon))

fn bodyModel data: String -> String
  (match (j/jsonParse data) ((ok v) (match (j/jsonGet v "model") ((some (j/jstr s)) s) (_ ""))) ((err _) ""))

fn outcome p: dp/Plan -> String
  (match p
    ((dp/planSend slot _ req _) (str "send " slot " " (bodyModel req.data) " " req.url))
    ((dp/planReject status reason _) (str "reject " status " " reason))
    (_ "wait"))

fn ! testUnknown text: String label: String -> Bool
  (match (wiringOf text)
    ((err e) (do (assert false (str label " wiring builds: " e)) false))
    ((ok w)
      (let [(unknown (outcome (planOf w "openrouter" "noSuchModelX")))
            (known (outcome (planOf w "fixa" "chat-a")))
            (claimed (outcome (planOf w "gemini" "gemini-2.5-pro")))]
        (do
          (assert (stringStartsWith? unknown "reject 400 (:err :code ERR_UNKNOWN_MODEL :status 400 :model \"noSuchModelX\"") (str label ": an unknown id is refused locally, naming it: " unknown))
          (assert (stringStartsWith? known "send ") (str label ": a table model is sent: " known))
          (assert (stringContains? known "http://127.0.0.1:9/a/v1") (str label ": to its own provider fixa: " known))
          (assert (stringContains? known " chat-a ") (str label ": with its own upstream name: " known))
          (assert (not (stringStartsWith? claimed "reject 400")) (str label ": a raw name a provider row claims by prefix still goes out: " claimed))
          true))))

fn ! testNoTable -> Bool
  (match (u/upstreamSettings (testEnv))
    ((err e) (do (assert false (str "settings: " e)) false))
    ((ok st)
      (let [(raw (outcome (planOf (dp/emptyWiring st) "openrouter" "noSuchModelX")))]
        (do
          (assert (not (stringStartsWith? raw "reject 400")) (str "without a gateway table a raw name is dispatched as before: " raw))
          true))))

; (:m :ref GW-HONOUR-NAME-MATCH :do "the pool prefers mB, so only honouring keeps a request on mA")
fn ! testHonourNames -> Bool
  (match (wiringOf (config (section)))
    ((err e) (do (assert false (str "balancer wiring builds: " e)) false))
    ((ok w)
      (let [(suffixed (outcome (planOf w "fixa" "chat-a:low")))
            (byId (outcome (planOf w "fixa" "mA")))
            (free (outcome (planOf w "fixa" "chat-a:turbo")))]
        (do
          (assert (stringStartsWith? suffixed "send mA ") (str "an effort-suffixed target is honoured as its pool alias: " suffixed))
          (assert (stringStartsWith? byId "send mA ") (str "a target that is the model row id is honoured: " byId))
          (assert (stringStartsWith? free "reject 400") (str "a suffix that is no effort level is another name, unknown here: " free))
          (assert (= (bl/modelKey "gemini-3.8-flash:low") "gemini-3.8-flash") "modelKey drops an effort suffix")
          (assert (= (bl/modelKey "nemotron:free") "nemotron:free") "and keeps :free")
          (assert (= (bl/modelKey ":high") ":high") "a bare suffix is a name")
          true))))

fn ! runTests -> Bool
  (let [(made (dirCreate (scratchDir)))
        (wrote (fileWrite (ledgerPath) ""))]
    (do
      (assert (and (ok? made) (ok? wrote)) "the scratch ledger exists")
      (assert (testUnknown (config "") "router") "router path")
      (assert (testUnknown (config (section)) "balancer") "balancer path")
      (assert (testNoTable) "no table")
      (assert (testHonourNames) "honour names")
      (assert (ok? (pathRemove (ledgerPath))) "the scratch ledger is removed")
      true))
