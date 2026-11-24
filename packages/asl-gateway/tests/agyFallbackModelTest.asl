(module asl-gateway/tests/agyFallbackModelTest
  :x [runTests]
  :i [(chat :a ch)
      (config :a c)
      (upstream :a u)
      (asl-json/json :a j)])

; (:m :do "the agy model name is one config lookup (agyConfigModel: alias agy, then antigravity) shared by agyFallbackLive and by cliDispatch's agy/antigravity branch; a config alias changes both, and gemini-3.8-flash is only the schema default when no alias resolves")

fn params -> c/GatewayParams
  (c/GatewayParams :topP none :temperature none :effort none :effortDialect none
                   :maxTokens none :contextBudget none :timeoutSec none :firstByteSec none
                   :reasoning none :rpm none :api none :prefill none :retry none
                   :nativeTools none :temperatureFixed none :stream none :idleSec none)

fn provider -> c/GatewayProvider
  (c/GatewayProvider :id "agy" :kind "cli" :base "" :keyEnv "" :secret ""
                     :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0
                     :rpm 0.0 :rpmShared false :dropEmptyTools false :assistantReasoning false
                     :idleSec 0.0 :pool none :retry none)

fn model name: String -> c/GatewayModel
  (c/GatewayModel :id "agy" :provider "agy" :name name :calibration none
                  :params (params) :shown (list) :gone false)

fn tableWith name: String -> c/GatewayTable
  (c/GatewayTable :version 2 :defaultProfile "" :profiles (mapEmpty) :profileOrder (list)
                  :models (mapFromPairs (list (pair "agy" (model name))))
                  :modelOrder (list "agy")
                  :providers (mapFromPairs (list (pair "agy" (provider))))
                  :intents (mapEmpty) :uses (mapEmpty) :useOrder (list)
                  :source "" :registry "" :registryError none :warnings (list)
                  :undeclaredIntents (mapEmpty) :keyFiles (list) :limits (list)
                  :bucketWaitSec 0.0 :queueBudgetSec 0.0)

fn tableAlias key: String name: String -> c/GatewayTable
  (c/GatewayTable :version 2 :defaultProfile "" :profiles (mapEmpty) :profileOrder (list)
                  :models (mapFromPairs (list (pair key (model name))))
                  :modelOrder (list key)
                  :providers (mapFromPairs (list (pair "agy" (provider))))
                  :intents (mapEmpty) :uses (mapEmpty) :useOrder (list)
                  :source "" :registry "" :registryError none :warnings (list)
                  :undeclaredIntents (mapEmpty) :keyFiles (list) :limits (list)
                  :bucketWaitSec 0.0 :queueBudgetSec 0.0)

fn tableEmpty -> c/GatewayTable
  (c/GatewayTable :version 2 :defaultProfile "" :profiles (mapEmpty) :profileOrder (list)
                  :models (mapEmpty) :modelOrder (list)
                  :providers (mapFromPairs (list (pair "agy" (provider))))
                  :intents (mapEmpty) :uses (mapEmpty) :useOrder (list)
                  :source "" :registry "" :registryError none :warnings (list)
                  :undeclaredIntents (mapEmpty) :keyFiles (list) :limits (list)
                  :bucketWaitSec 0.0 :queueBudgetSec 0.0)

fn judge -> c/JudgeRules
  (c/JudgeRules :empty false :truncated false :stepIntents (list) :stepHeads (list))

fn ! withCtx tbl: c/GatewayTable k: (fn [ch/Ctx] -> Bool) -> Bool
  (match (u/upstreamSettings (mapEmpty))
    ((ok st)
     (k (ch/Ctx :req (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{}")
                :world (ch/ChatWorld :env (mapEmpty) :rootDir "/tmp" :settings st
                                     :agyPromptMaxBytes 10000 :table (ok tbl))
                :path "/v1/chat/completions" :asn false :sanitize false
                :intent "" :role "" :workspace "/tmp" :explicitModel "agy"
                :profileRouted false :profileName "" :table (some tbl)
                :reqKeys (list) :headerEff none :envEff none
                :tempExplicit false :timeoutExplicit false
                :baseBody (j/jobj (list)) :cascadeLen 1
                :spread (list) :cooldownSec 0
                :session "" :stuck "" :dropOnSwitch false
                :stickWaitSec 0.0 :sticking false
                :mode "route" :judge (judge) :excludeModel "")))
    ((err _) false))

fn argStrAt args: (List (Pair String j/Json)) key: String -> String
  (match (listHead args)
    ((none) "")
    ((some p)
     (if (= (pairFirst p) key)
       (match (pairSecond p) ((j/jstr s) s) (_ ""))
       (argStrAt (optionOr (listTail args) (list)) key))))

fn argStr args: (List (Pair String j/Json)) key: String -> String
  (argStrAt args key)

fn ! driveModel step: ch/ChatStep fuel: Int64 -> String
  (if (<= fuel 0)
    ""
    (match step
      ((ch/stepDone _) "")
      ((ch/stepRaised _ _) "")
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effCli _ args) (argStr args "model"))
         ((ch/effBreakerDown _) (driveModel (k (ch/outFloat 0.0)) (- fuel 1)))
         ((ch/effBreakerDownAll _) (driveModel (k (ch/outFloats (list 0.0))) (- fuel 1)))
         ((ch/effBucket _ _ _) (driveModel (k (ch/outBool false)) (- fuel 1)))
         ((ch/effRealpath _) (driveModel (k (ch/outPath "/tmp")) (- fuel 1)))
         ((ch/effIsDir _) (driveModel (k (ch/outBool true)) (- fuel 1)))
         ((ch/effClock) (driveModel (k (ch/outFloat 1.0)) (- fuel 1)))
         ((ch/effHttp _ _ _ _ _ _ _ _) "")
         ((ch/effPoolHttp _ _ _ _ _ _) "")
         (_ (driveModel (k ch/outDone) (- fuel 1)))))))

fn ! runTests -> Bool
  (let [(tbl (tableWith "gemini-9.9-test"))
        (empty (tableEmpty))]
    (do
      (assert (withCtx tbl (fn [(cx ch/Ctx)] -> Bool (= (ch/agyConfigModel cx) "gemini-9.9-test")))
              "agyConfigModel reads the agy alias name")
      (assert (withCtx empty (fn [(cx ch/Ctx)] -> Bool (= (ch/agyConfigModel cx) "gemini-3.8-flash")))
              "no agy alias: gemini-3.8-flash is the schema default")
      (assert (withCtx (tableAlias "antigravity" "gemini-7.7-alt")
                (fn [(cx ch/Ctx)] -> Bool (= (ch/agyConfigModel cx) "gemini-7.7-alt")))
              "antigravity alias is the second lookup")
      (assert (withCtx tbl
                (fn [(cx ch/Ctx)] -> Bool
                  (= (driveModel (ch/agyFallbackLive cx "hi"
                                    (fn [(_r (Option ch/CliReply))] -> ch/ChatStep
                                      (ch/stepRaised "done" "done"))) 300)
                     "gemini-9.9-test")))
              "agyFallbackLive sends the config model")
      (assert (withCtx tbl
                (fn [(cx ch/Ctx)] -> Bool
                  (= (driveModel (ch/chatStart!
                                    (ch/ChatRequest :path "/v1/chat/completions" :headers (list)
                                                    :body "{\"model\":\"agy\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                                    cx.world) 400)
                     "gemini-9.9-test")))
              "cliDispatch agy/antigravity sends the config model")
      true))
