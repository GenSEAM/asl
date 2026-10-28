(module aslGateway/tests/balancerReserveTest
  :x [runTests]
  :i [(aslGateway/dispatch :a dp) (aslGateway/config :a cfg) (aslGateway/upstream :a u) (aslGateway/balancer :a bl)])

; (:m :ref AUDIT11-A3 :do "requests planned before any settle against one hard budget: mA free with a daily request quota already spent, mB sub at 2 of 3 requests, or mB alone on a 1000-token daily budget; each plan is threaded through planReserving as the server threads its wiring")

fn scratchDir -> String
  "/tmp/balancerReserveTest"

fn ledgerPath -> String
  (str (scratchDir) "/calls.asn")

fn noon -> Int64 43200000

fn config models: String budgets: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id fixb :kind openai :base \"http://127.0.0.1:9/b/v1\" :keyEnv FIXA_KEY))"
       " :models (" models ")"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mB)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledgerPath) "\" :budgets (" budgets ")))\n")

fn reqConfig -> String
  (config "(:model :id mA :provider fixa :name \"chat-a\" :tier free :budgets (aDay) :quality 300) (:model :id mB :provider fixb :name \"chat-b\" :tier sub :budgets (bDay) :quality 900)"
          "(:budget :id aDay :window day :unit req :size 1 :soft 100 :useOrLose true) (:budget :id bDay :window day :unit req :size 3 :soft 100 :useOrLose true)")

fn tokConfig -> String
  (config "(:model :id mB :provider fixb :name \"chat-b\" :tier sub :budgets (tDay) :quality 900)"
          "(:budget :id tDay :window day :unit tok :size 1000 :soft 100 :useOrLose true)")

fn callLine alias: String model: String -> String
  (str "(:call :at 1000 :profile default :intent any :alias " alias " :provider fixb :model \"" model "\" :in 10 :cached 0 :out 5 :reasoning 0 :ttftMs absent :ms absent :outcome ok :charge 0 :tag absent :temperature absent :topP absent :maxTokens absent :effort absent :api chat :stream false :toolCount 0 :promptBytes 0 :sysHash h)\n")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXA_KEY" "aKey") (pair "HOME" (scratchDir))))

fn hint prompt: Int64 -> dp/RouteHint
  (dp/RouteHint :provider "fixb" :model "chat-b" :intent "" :role "coder" :promptTokens prompt)

fn chatRequest -> u/UpstreamRequest
  (u/UpstreamRequest :url "http://fixture.invalid/v1/chat/completions" :fragment "" :method "POST"
    :headers (list (pair "Content-Type" "application/json") (pair "Authorization" "Bearer aKey"))
    :data "{\"model\":\"chat-b\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")

fn ! wiringFor text: String ledger: String -> (Result dp/Wiring String)
  (match (fileWrite (ledgerPath) ledger)
    ((err e) (err e))
    ((ok _)
      (match (cfg/gatewayProfilesLoadText! (str (scratchDir) "/.asl/gateway.asn") true (ok text) "")
        ((err e) (err e))
        ((ok table)
          (match (u/upstreamSettings (testEnv))
            ((err e) (err e))
            ((ok st) (dp/wiringFromConfig (some table) text st (testEnv) (dp/builtinFamilies))))))))

fn ! planAt w: dp/Wiring prompt: Int64 nowMs: Int64 -> (Pair dp/Plan dp/Wiring)
  (dp/planReserving w (hint prompt) (chatRequest) (testEnv) nowMs)

fn sentSlot planned: dp/Plan -> String
  (match planned ((dp/planSend slot _ _ _) slot) ((dp/planReject status _ _) (str "reject " status)) (_ "wait"))

fn ! testConcurrentReqCap -> Bool
  (match (wiringFor (reqConfig) (str (callLine "mA" "chat-a") (callLine "mB" "chat-b") (callLine "mB" "chat-b")))
    ((err e) (do (assert false (str "wiring builds: " e)) false))
    ((ok w)
      (let [(p1 (planAt w 10 (noon)))
            (p2 (planAt (pairSecond p1) 10 (+ (noon) 1)))
            (p3 (planAt (pairSecond p2) 10 (+ (noon) 2)))
            (settled (pairFirst (dp/settle (pairSecond p3) "mB" "fixb" 20 5 true (+ (noon) 3))))
            (p4 (planAt settled 10 (+ (noon) 4)))]
        (do
          (assert (= (sentSlot (pairFirst p1)) "mB") (str "the first of three concurrent plans takes mB's last request: " (sentSlot (pairFirst p1))))
          (assert (= (sentSlot (pairFirst p2)) "reject 429") (str "the second, planned before any settle, sees the hold and is refused: " (sentSlot (pairFirst p2))))
          (assert (= (sentSlot (pairFirst p3)) "reject 429") "so is the third")
          (assert (= (sentSlot (pairFirst p4)) "reject 429") "after settle the hold became the charge, so the cap still holds")
          true))))

fn ! testRefundOnLowerActual -> Bool
  (match (wiringFor (tokConfig) "")
    ((err e) (do (assert false (str "tok wiring builds: " e)) false))
    ((ok w)
      (let [(p1 (planAt w 300 (noon)))
            (p2 (planAt (pairSecond p1) 300 (+ (noon) 1)))
            (low (pairFirst (dp/settle (pairSecond p2) "mB" "fixb" 100 5 true (+ (noon) 2))))
            (p3 (planAt low 300 (+ (noon) 3)))
            (failedW (pairFirst (dp/settle (pairSecond p1) "mB" "fixb" 0 5 false (+ (noon) 2))))
            (p4 (planAt failedW 300 (+ (noon) 3)))
            (lapsed (planAt (pairSecond p1) 300 (+ (noon) 600001)))]
        (do
          (assert (= (sentSlot (pairFirst p1)) "mB") "a 300-token prompt holds its 600-token estimate of the 1000-token budget")
          (assert (= (sentSlot (pairFirst p2)) "reject 429") "a second 600-token estimate does not fit beside the hold")
          (assert (= (sentSlot (pairFirst p3)) "mB") "settling the first at 100 actual tokens frees the other 500, so the next plan fits")
          (assert (= (sentSlot (pairFirst p4)) "mB") "a failed call releases its hold as well")
          (assert (= (sentSlot (pairFirst lapsed)) "mB") "a hold no settle released lapses after ten minutes")
          true))))

; (:m :ref GW-HOLD-PRUNE :do "pure: mA on a daily budget of 10 requests; a hold placed at 1000 lapses at 601000")
fn prunePool -> bl/Pool
  (bl/poolFromParts
    (bl/makeBalancer (list (bl/PoolModel :id "mA" :provider "pa" :tier (bl/tierFree) :why "fixture" :budgets (list "aDay") :costMicros 0 :declaredQuality (none)))
                     (list (bl/Budget :id "aDay" :windowMs 86400000 :anchorMs 0 :headerWindowMs 0 :unit "req" :size 10 :softPct 100 :hardPct 100 :useOrLose true :source "declared"))
                     (list) (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100))
    (bl/emptyUse)
    (mapFromPairs (list (pair "mA" (pair "pa" "model-a")))))

fn usedAt p: bl/Pool nowMs: Int64 -> Int64
  (match (mapGet p.bal.budgets "aDay") ((some b) (bl/budgetUsed (bl/effectiveUse p nowMs) b nowMs)) ((none) -1))

fn holdTimes p: bl/Pool -> String
  (stringJoin (map (fn [(h bl/Hold)] -> String (stringFromInt64 h.atMs)) p.holds) " ")

fn testPrune -> Bool
  (let [(p0 (prunePool))
        (late (bl/poolReserve (bl/poolReserve p0 "mA" 1000 0) "mA" 700000 0))
        (stale (with p0 :holds (list (bl/Hold :alias "mA" :atMs 1000 :tokens 0) (bl/Hold :alias "mA" :atMs 699000 :tokens 0) (bl/Hold :alias "mA" :atMs 700000 :tokens 0))))
        (releasedAt (bl/poolReleaseAt stale "mA" 700001))
        (released (bl/poolRelease stale "mA"))]
    (do
      (assert (= (holdTimes late) "700000") (str "a reserve prunes the hold that lapsed before it: " (holdTimes late)))
      (assert (= (usedAt stale 700001) 2) "the stale pool counts only its two live holds")
      (assert (= (usedAt releasedAt 700001) 1) (str "release at a clock drops the oldest live hold, not the lapsed older one: " (holdTimes releasedAt)))
      (assert (= (holdTimes releasedAt) "700000") "and leaves the newer live hold and no lapsed one")
      (assert (= (holdTimes released) "700000") (str "release without a clock takes the newest hold as now and does the same: " (holdTimes released)))
      true))

fn ! runTests -> Bool
  (let [(made (dirCreate (scratchDir)))]
    (do
      (assert (testPrune) "prune")
      (assert (ok? made) "the scratch dir exists")
      (assert (testConcurrentReqCap) "concurrent request cap")
      (assert (testRefundOnLowerActual) "refund on lower actual")
      (assert (ok? (pathRemove (ledgerPath))) "the scratch ledger is removed")
      true))
