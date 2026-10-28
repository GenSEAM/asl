(module aslGateway/tests/balancerHonourTest
  :x [runTests]
  :i [(aslGateway/dispatch :a dp) (aslGateway/config :a cfg) (aslGateway/upstream :a u) (asl-json/json :a j)])

; (:m :ref GW-MODEL-SUBSTITUTION :do "the pool prefers mB (sub, quality 900) over mA (free, quality 300); a request naming chat-a on fixa must still reach mA, and only a refused mA is substituted, with a receipt saying so")

fn scratchDir -> String
  "/tmp/balancerHonourTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

fn noon -> Int64 43200000

fn config -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id fixb :kind openai :base \"http://127.0.0.1:9/b/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\" :tier free :budgets (aDay) :quality 300)"
       " (:model :id mB :provider fixb :name \"chat-b\" :tier sub :budgets (bDay) :quality 900))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\""
       " :budgets ((:budget :id aDay :window day :unit req :size 2 :soft 100 :useOrLose true) (:budget :id bDay :window day :unit req :size 5 :soft 100 :useOrLose true))))\n")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXA_KEY" "aKey") (pair "HOME" (scratchDir))))

fn hint model: String -> dp/RouteHint
  (dp/RouteHint :provider "fixa" :model model :intent "" :role "coder" :promptTokens 10)

fn chatRequest model: String -> u/UpstreamRequest
  (u/UpstreamRequest :url "http://127.0.0.1:9/v1/chat/completions" :fragment "" :method "POST"
    :headers (list (pair "Content-Type" "application/json") (pair "Authorization" "Bearer aKey"))
    :data (str "{\"model\":\"" model "\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"))

fn ! wiring -> (Result dp/Wiring String)
  (match (fileWrite (ledgerPath) "")
    ((err e) (err e))
    ((ok _)
      (match (cfg/gatewayProfilesLoadText! (str (scratchDir) "/.asl/gateway.asn") true (ok (config)) "")
        ((err e) (err e))
        ((ok table)
          (match (u/upstreamSettings (testEnv))
            ((err e) (err e))
            ((ok st) (dp/wiringFromConfig (some table) (config) st (testEnv) (dp/builtinFamilies))))))))

fn ! planAt w: dp/Wiring model: String nowMs: Int64 -> dp/Plan
  (dp/plan w (hint model) (chatRequest model) (testEnv) nowMs)

fn bodyModel data: String -> String
  (match (j/jsonParse data) ((ok v) (match (j/jsonGet v "model") ((some (j/jstr s)) s) (_ ""))) ((err _) ""))

fn sent planned: dp/Plan -> String
  (match planned ((dp/planSend slot _ request _) (str slot " " (bodyModel request.data))) ((dp/planReject status _ _) (str "reject " status)) (_ "wait"))

fn receipt planned: dp/Plan -> String
  (match planned ((dp/planSend _ _ _ row) (dp/decisionText row)) ((dp/planReject _ _ row) (dp/decisionText row)) ((dp/planWait _ _ _ row _ _) (dp/decisionText row)))

fn ! settleAt w: dp/Wiring slot: String ok: Bool nowMs: Int64 -> dp/Wiring
  (pairFirst (dp/settle w slot "fixa" 20 5 ok nowMs))

fn ! runTests -> Bool
  (let [(made (dirCreate (scratchDir)))]
    (match (wiring)
      ((err e) (do (assert false (str "wiring builds: " e)) false))
      ((ok w)
        (let [(free (planAt w "gemini-free-choice" (noon)))
              (asked (planAt w "chat-a" (noon)))
              (failed (settleAt w "mA" false (noon)))
              (rested (planAt failed "chat-a" (+ (noon) 1)))
              (full (settleAt (settleAt w "mA" true (noon)) "mA" true (noon)))
              (capped (planAt full "chat-a" (+ (noon) 1)))
              (exhausted (planAt (dp/observeReply w "mA" 429 (list (pair "retry-after" "60")) (noon)) "chat-a" (+ (noon) 1)))]
          (do
            (assert (ok? made) "the scratch dir exists")
            (assert (= (sent free) "mB chat-b") (str "a hint naming no pool model lets the balancer choose its preferred mB: " (sent free)))
            (assert (stringContains? (receipt free) "(:asked \"fixa/gemini-free-choice\" :inPool false :served mB)") (str "and the receipt says the named model is no pool model and which alias served: " (receipt free)))
            (assert (= (sent asked) "mA chat-a") (str "a request naming chat-a is honoured though the pool prefers mB: " (sent asked)))
            (assert (stringContains? (receipt asked) "(:honoured true)") (str "the receipt says the named model was honoured: " (receipt asked)))
            (assert (= (sent rested) "mB chat-b") (str "after mA failed it rests, and the request is substituted: " (sent rested)))
            (assert (stringContains? (receipt rested) "(:substituted :asked \"fixa/chat-a\" :served mB :reason \"the asked model mA rests after a failure\")") (str "the receipt names the substitution: " (receipt rested)))
            (assert (= (sent capped) "mB chat-b") "with mA at its hard cap the request is substituted")
            (assert (stringContains? (receipt capped) "is at its hard cap: aDay") (str "and the receipt says why: " (receipt capped)))
            (assert (stringContains? (receipt exhausted) ":served mB :reason \"the asked model mA is exhausted by its provider") (str "a provider 429 on mA substitutes too: " (receipt exhausted)))
            (assert (ok? (pathRemove (ledgerPath))) "the scratch ledger is removed")
            true)))))
