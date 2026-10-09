(module aslGateway/tests/pluginTest
  :x [runTests]
  :i [(plugin :a p) (aslGateway/budget :a bgt) (aslGateway/upstream :a up) (aslGateway/cliDispatch :a cli)])

fn missingBin -> String
  "/nonexistent/aslPluginTest/bin"

fn badBinOptions -> cli/DispatchOptions
  (cli/DispatchOptions :model none :effort none :timeout 5 :workspace none :systemPrompt none
    :noTools true :agent none :addDirs (list) :cliBin (some (missingBin)))

fn serverlessCaps batching: p/Batching -> p/PluginCapabilities
  (p/PluginCapabilities :api (p/openaiChat) :batching batching :maxConcurrency 8
    :streaming true :tools true :json false
    :scaleModel (p/serverless 2 30000)
    :priceModel (p/perGpuSecond (list (pair "L4" 0.000222) (pair "A100" 0.00111)))
    :regions (list "us-east" "eu-west") :redirectAfterSec 0)

fn withConcurrency caps: p/PluginCapabilities n: Int64 -> p/PluginCapabilities
  (p/PluginCapabilities :api caps.api :batching caps.batching :maxConcurrency n
    :streaming caps.streaming :tools caps.tools :json caps.json
    :scaleModel caps.scaleModel :priceModel caps.priceModel :regions caps.regions :redirectAfterSec caps.redirectAfterSec)

fn withPrice caps: p/PluginCapabilities price: p/PriceModel -> p/PluginCapabilities
  (p/PluginCapabilities :api caps.api :batching caps.batching :maxConcurrency caps.maxConcurrency
    :streaming caps.streaming :tools caps.tools :json caps.json
    :scaleModel caps.scaleModel :priceModel price :regions caps.regions :redirectAfterSec caps.redirectAfterSec)

fn withScale caps: p/PluginCapabilities scale: p/ScaleModel -> p/PluginCapabilities
  (p/PluginCapabilities :api caps.api :batching caps.batching :maxConcurrency caps.maxConcurrency
    :streaming caps.streaming :tools caps.tools :json caps.json
    :scaleModel scale :priceModel caps.priceModel :regions caps.regions :redirectAfterSec caps.redirectAfterSec)

fn fixtureSend request: p/PluginRequest -> (Result p/PluginReply p/PluginFailure)
  (err (p/cliFailed "fixture send"))

fn fixtureBatch requests: (List p/PluginRequest) -> (Result (List p/PluginReply) p/PluginFailure)
  (err (p/cliFailed (str "fixture batch " (stringFromInt64 (listLength requests)))))

fn fixtureHealth env: (Map String String) -> (Result String String)
  (ok "fixture")

fn statusFor detail: String request: p/LifecycleRequest -> (Result p/LifecycleStatus String)
  (ok (p/LifecycleStatus :endpoint request.endpoint :state (p/warm) :detail detail))

fn fixtureLifecycle -> p/Lifecycle
  (p/Lifecycle
    :deploy (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (statusFor "deploy" r))
    :start (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (statusFor "start" r))
    :stop (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (statusFor "stop" r))
    :status (fn [(r p/LifecycleRequest)] -> (Result p/LifecycleStatus String) (err "status probe failed")))

fn lifecycleRequest cost: Int64 -> p/LifecycleRequest
  (p/LifecycleRequest :endpoint "paid-api" :model "bonsai2" :gpu "L4" :region "us-east" :version "1.0.0" :unit "u1" :expectedCost cost)

fn paidLedger approvals: (List bgt/Approval) -> bgt/Ledger
  (bgt/makeLedger (list (bgt/BudgetLine :id "paid-hour" :scope (bgt/scopeEndpoint "paid-api") :period (bgt/periodHour) :cap 100 :approved false))
    approvals 8)

fn detailOf result: (Result p/LifecycleStatus p/PluginFailure) -> String
  (mt result ((ok s) s.detail) ((err _) ""))

fn failureOf result: (Result p/LifecycleStatus p/PluginFailure) -> (Option p/PluginFailure)
  (mt result ((ok _) none) ((err f) (some f)))

fn sendFailure result: (Result p/PluginReply p/PluginFailure) -> (Option p/PluginFailure)
  (mt result ((ok _) none) ((err f) (some f)))

fn batchFailure result: (Result (List p/PluginReply) p/PluginFailure) -> (Option p/PluginFailure)
  (mt result ((ok _) none) ((err f) (some f)))

fn upstreamError result: (Result up/UpstreamCall up/UpstreamFailure) -> (Option p/PluginFailure)
  (mt result ((ok _) none) ((err f) (some (p/upstreamFailed f))))

fn cliError result: (Result cli/CliParseResult String) -> (Option p/PluginFailure)
  (mt result ((ok _) none) ((err e) (some (p/cliFailed e))))

fn curlAbsent? failure: (Option p/PluginFailure) -> Bool
  (mt failure
    ((some f) (mt f ((p/upstreamFailed u) (mt u ((up/toolAbsent tool _) (= tool "curl")) (_ false))) (_ false)))
    ((none) false))

fn spendGate? failure: (Option p/PluginFailure) -> Bool
  (mt failure
    ((some f) (mt f ((p/spendGate _) true) (_ false)))
    ((none) false))

fn rejected result: (Result p/Plugin String) -> String
  (mt result ((ok _) "") ((err e) e))

fn rateFor rates: (List (Pair String Float64)) gpu: String -> Float64
  (fold (fn [(acc Float64) (rate (Pair String Float64))] -> Float64 (if (= (pairFirst rate) gpu) (pairSecond rate) acc)) -1.0 rates)

fn runpodRow -> up/UpstreamProvider
  (up/UpstreamProvider :id "runpod" :prefixes (list "runpod/") :names (list)
    :url (fn [(st up/UpstreamSettings) (env (Map String String))] -> String (up/envGetOr env "RUNPOD_BASE_URL" ""))
    :key (fn [(st up/UpstreamSettings) (env (Map String String))] -> String (up/envGetOr env "RUNPOD_API_KEY" ""))
    :timeoutSec (fn [(st up/UpstreamSettings)] -> Float64 300.0))

fn ! capabilityChecks -> Bool
  (let [(caps (serverlessCaps (p/continuous)))]
    (do
      (assert (mt caps.api ((p/openaiChat) true) (_ false)) "capability api carries openaiChat")
      (assert (mt caps.batching ((p/continuous) true) (_ false)) "capability batching carries continuous")
      (assert (= caps.maxConcurrency 8) "capability maxConcurrency carries 8")
      (assert caps.streaming "capability streaming carries true")
      (assert caps.tools "capability tools carries true")
      (assert (not caps.json) "capability json carries false")
      (assert (mt caps.scaleModel ((p/serverless idle coldMs) (and (= idle 2) (= coldMs 30000))) (_ false)) "capability scaleModel carries serverless idle and cold start")
      (assert (mt caps.priceModel ((p/perGpuSecond rates) (= (rateFor rates "L4") 0.000222)) (_ false)) "capability priceModel carries a perGpuSecond rate per gpu")
      (assert (= caps.regions (list "us-east" "eu-west")) "capability regions carries the region list")
      (assert (= (p/capabilitiesError caps) none) "a well-formed capability record passes validation")
      (assert (= (p/capabilitiesError (withConcurrency caps 0)) (some "maxConcurrency is below 1")) "maxConcurrency below 1 is rejected")
      (assert (= (p/capabilitiesError (withPrice caps (p/perToken -1.0 2.0))) (some "perToken price is negative")) "negative perToken price is rejected")
      (assert (= (p/capabilitiesError (withPrice caps (p/perGpuSecond (list)))) (some "perGpuSecond has no gpu rate")) "perGpuSecond without a rate is rejected")
      (assert (= (p/capabilitiesError (withScale caps (p/serverless -1 0))) (some "serverless timings are negative")) "negative serverless idle timeout is rejected")
      (assert (= (rejected (p/makePlugin "fx" (serverlessCaps (p/batchEndpoint)) fixtureSend none fixtureHealth none)) "fx: batchEndpoint without sendBatch") "batchEndpoint without sendBatch is rejected")
      (assert (= (rejected (p/makePlugin "fx" caps fixtureSend (some fixtureBatch) fixtureHealth none)) "fx: sendBatch without batchEndpoint") "sendBatch without batchEndpoint is rejected")
      (assert (= (rejected (p/makePlugin "" caps fixtureSend none fixtureHealth none)) "plugin id is empty") "an empty plugin id is rejected")
      (assert (= (rejected (p/makePlugin "fx" (withConcurrency caps 0) fixtureSend none fixtureHealth none)) "fx: maxConcurrency is below 1") "makePlugin applies capability validation")
      (mt (p/makePlugin "fx" (serverlessCaps (p/batchEndpoint)) fixtureSend (some fixtureBatch) fixtureHealth none)
        ((err e) (assert false (str "batchEndpoint plugin builds: " e)))
        ((ok batcher)
          (assert (= (batchFailure (p/pluginSendBatch! batcher (list (p/cliSend "a" (badBinOptions)) (p/cliSend "b" (badBinOptions)))))
                     (some (p/cliFailed "fixture batch 2"))) "pluginSendBatch! delegates to the plugin's sendBatch")))
      (mt (p/makePlugin "fx" caps fixtureSend none fixtureHealth none)
        ((err e) (assert false (str "continuous plugin builds: " e)))
        ((ok plain)
          (do
            (assert (= (batchFailure (p/pluginSendBatch! plain (list))) (some (p/unsupported "fx" "sendBatch"))) "pluginSendBatch! on a plugin without sendBatch is unsupported")
            (assert (= (sendFailure (p/pluginSend! plain (p/cliSend "x" (badBinOptions)))) (some (p/cliFailed "fixture send"))) "pluginSend! delegates to the plugin's send"))))
      true))

fn ! openaiCompatChecks st: up/UpstreamSettings -> Bool
  (let [(badUrl (up/UpstreamRequest :url "https://bad url" :fragment "" :method "POST" :headers (list) :data "{}"))
        (good (up/UpstreamRequest :url "https://fixture.invalid/v1/chat/completions" :fragment "" :method "POST" :headers (list) :data "{}"))
        (noCurl (mapFromPairs (list (pair "PATH" "/nonexistent/aslPluginTest"))))]
    (mt (p/ollama st)
      ((err e) (do (assert false (str "ollama plugin builds: " e)) false))
      ((ok plugin)
        (do
          (assert (= plugin.id "ollama") "ollama adapter takes its id from the provider row")
          (assert (mt plugin.capabilities.api ((p/openaiChat) true) (_ false)) "ollama adapter declares the openaiChat api")
          (assert (= (sendFailure (p/pluginSend! plugin (p/httpSend badUrl (mapEmpty) 1.0)))
                     (upstreamError (up/upstreamCallStart! badUrl (mapEmpty) 1.0))) "openaiCompat send delegates to upstreamCallStart! (url rejected)")
          (assert (some? (sendFailure (p/pluginSend! plugin (p/httpSend badUrl (mapEmpty) 1.0)))) "openaiCompat send reports the rejected url as a failure")
          (assert (= (sendFailure (p/pluginSend! plugin (p/httpSend good noCurl 1.0)))
                     (upstreamError (up/upstreamCallStart! good noCurl 1.0))) "openaiCompat send delegates to upstreamCallStart! (curl absent)")
          (assert (curlAbsent? (sendFailure (p/pluginSend! plugin (p/httpSend good noCurl 1.0)))) "openaiCompat send passes the request env to the transport")
          (assert (= (sendFailure (p/pluginSend! plugin (p/cliSend "hi" (badBinOptions)))) (some (p/unsupported "ollama" "cliSend"))) "openaiCompat refuses a CLI request")
          (assert (= (p/pluginHealth! plugin (mapEmpty)) (ok st.ollamaUrl)) "openaiCompat health reports the row's base URL")
          (mt (p/openaiCompat (runpodRow) st (p/openaiCompatCapabilities 4 (p/serverless 5 20000) (p/perGpuSecond (list (pair "4090" 0.00031))) (list)) none)
            ((err e) (assert false (str "configured row builds: " e)))
            ((ok runpod)
              (do
                (assert (= (p/pluginHealth! runpod (mapEmpty)) (err "runpod: no base URL")) "openaiCompat health fails without a base URL")
                (assert (= (p/pluginHealth! runpod (mapFromPairs (list (pair "RUNPOD_BASE_URL" "https://runpod.example/v1")))) (ok "https://runpod.example/v1")) "a configured endpoint row needs no adapter code")
                (assert (= runpod.capabilities.maxConcurrency 4) "openaiCompat takes its capability record from configuration"))))
          true))))

fn ! cliAdapterCheck name: String built: (Result p/Plugin String) direct: (Result cli/CliParseResult String) expected: String -> Bool
  (mt built
    ((err e) (do (assert false (str name " plugin builds: " e)) false))
    ((ok plugin)
      (do
        (assert (= plugin.id name) (str name " adapter takes its id from the CLI row"))
        (assert (mt plugin.capabilities.api ((p/cliAgent) true) (_ false)) (str name " adapter declares the cliAgent api"))
        (assert (mt plugin.capabilities.batching ((p/unbatched) true) (_ false)) (str name " adapter declares no batching"))
        (assert (= (sendFailure (p/pluginSend! plugin (p/cliSend "hello" (badBinOptions)))) (cliError direct)) (str name " send delegates to its dispatch function"))
        (assert (= (sendFailure (p/pluginSend! plugin (p/cliSend "hello" (badBinOptions)))) (some (p/cliFailed (str expected " not found: " (missingBin))))) (str name " send runs its own CLI"))
        (assert (= (sendFailure (p/pluginSend! plugin (p/httpSend (up/UpstreamRequest :url "https://x" :fragment "" :method "POST" :headers (list) :data "") (mapEmpty) 1.0)))
                   (some (p/unsupported name "httpSend"))) (str name " refuses an HTTP request"))
        (assert (= (mt (p/pluginHealth! plugin (mapEmpty)) ((ok _) true) ((err _) false))
                   (mt (cli/cliProviderNamed name) ((some row) (fileExists? (cli/cliProviderBin! row))) ((none) false))) (str name " health follows its binary"))
        true)))

fn ! lifecycleChecks -> Bool
  (mt (p/makePlugin "modalFixture" (serverlessCaps (p/continuous)) fixtureSend none fixtureHealth (some (fixtureLifecycle)))
    ((err e) (do (assert false (str "lifecycle plugin builds: " e)) false))
    ((ok plugin)
      (let [(unapproved (paidLedger (list)))
            (approved (paidLedger (list (bgt/Approval :endpoint "paid-api" :cap 100))))]
        (do
          (assert (= (failureOf (p/pluginDeploy! plugin none (lifecycleRequest 0) 1000)) (some (p/spendGate "deploy needs a budget ledger"))) "deploy without a ledger is refused")
          (assert (= (failureOf (p/pluginDeploy! plugin (some unapproved) (lifecycleRequest 0) 1000)) (some (p/spendGate "deploy lacks a budget line and approval for its endpoint"))) "deploy the budget gate denies is refused before the plugin runs")
          (assert (= (detailOf (p/pluginDeploy! plugin (some approved) (lifecycleRequest 0) 1000)) "deploy") "deploy the budget gate allows reaches the plugin")
          (assert (= (failureOf (p/pluginStart! plugin none (lifecycleRequest 10) 1000)) (some (p/spendGate "start needs a budget ledger"))) "start without a ledger is refused")
          (assert (spendGate? (failureOf (p/pluginStart! plugin (some approved) (lifecycleRequest 101) 1000))) "start over the budget cap is refused by the spend gate")
          (assert (= (detailOf (p/pluginStart! plugin (some approved) (lifecycleRequest 10) 1000)) "start") "start within the budget cap reaches the plugin")
          (assert (= (detailOf (p/pluginStop! plugin (lifecycleRequest 0))) "stop") "stop needs no ledger")
          (assert (= (failureOf (p/pluginStatus! plugin (lifecycleRequest 0))) (some (p/lifecycleFailed "status probe failed"))) "a lifecycle failure is typed lifecycleFailed")
          (mt (p/makePlugin "plain" (serverlessCaps (p/continuous)) fixtureSend none fixtureHealth none)
            ((err e) (assert false (str "plain plugin builds: " e)))
            ((ok plain) (assert (= (failureOf (p/pluginDeploy! plain (some approved) (lifecycleRequest 0) 1000)) (some (p/unsupported "plain" "deploy"))) "deploy on a plugin without lifecycle is unsupported")))
          true))))

fn ! siteChecks st: up/UpstreamSettings -> Bool
  (let [(env (mapFromPairs (list (pair "RUNPOD_BASE_URL" "https://runpod.example/v1") (pair "RUNPOD_API_KEY" "rpKey"))))
        (withRunpod (listAppend (up/upstreamProviders) (list (runpodRow))))
        (routed (up/getUpstreamForModelIn withRunpod (up/upstreamFallback) st env (some "runpod/bonsai2")))
        (codexLine "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"hi\"}}")]
    (do
      (assert (= routed.provider "runpod") "a provider row added to the table claims its models")
      (assert (= routed.url "https://runpod.example/v1") "the added row resolves its URL")
      (assert (= routed.key "rpKey") "the added row resolves its key")
      (assert (= (up/getUpstreamForModel st env (some "runpod/bonsai2")).provider "openrouter") "without the row the model falls back")
      (assert (= (up/getUpstreamForModelIn (list) (up/upstreamFallback) st env (some "agy")).provider "openrouter") "routing has no provider branch outside the table")
      (assert (= (up/upstreamTimeoutSecIn withRunpod st "runpod") 300.0) "the timeout comes from the provider row")
      (assert (= (up/upstreamTimeoutSec st "ollama") st.ollamaTimeoutSec) "the ollama row keeps its timeout")
      (assert (mt (cli/cliProviderNamed "codex") ((some row) (= (row.parse codexLine) (cli/cliParseResult "codex" codexLine))) ((none) false)) "cliParseResult parses through the CLI row")
      (assert (= (cli/cliProviderNamed "nope") none) "an unknown CLI client has no row")
      (mt (p/defaultPlugins! st)
        ((err e) (assert false (str "default registry builds: " e)))
        ((ok registry)
          (do
            (assert (= (map (fn [(one p/Plugin)] -> String one.id) registry) (list "claude" "codex" "agy" "gemini" "ollama" "groq" "openrouter")) "the default registry holds one plugin per provider row")
            (assert (= (p/pluginNamed registry "agy-cli") none) "cli:// routing rows are not HTTP plugins")
            (assert (mt (p/pluginNamed registry "claude")
                      ((some one) (= (sendFailure (p/pluginSend! one (p/cliSend "hi" (badBinOptions)))) (some (p/cliFailed (str "CLAUDE_BIN not found: " (missingBin))))))
                      ((none) false)) "the core dispatches a CLI provider by id through its plugin record")
            (assert (mt (p/pluginNamed registry "gemini") ((some one) (= (p/pluginHealth! one (mapEmpty)) (ok st.geminiUrl))) ((none) false)) "the gemini row is an openaiCompat plugin"))))
      true))

fn ! runTests -> Bool
  (let [(settingsEnv (mapFromPairs (list (pair "OLLAMA_BASE_URL" "http://127.0.0.1:9000/") (pair "OLLAMA_TIMEOUT_SEC" "7"))))]
    (mt (up/upstreamSettings settingsEnv)
      ((err e) (do (assert false (str "settings build: " e)) false))
      ((ok st)
        (and (capabilityChecks)
             (openaiCompatChecks st)
             (cliAdapterCheck "codex" (p/codex) (cli/dispatchCodexFallback! "hello" (badBinOptions)) "CODEX_BIN")
             (cliAdapterCheck "claude" (p/claude) (cli/dispatchClaudeFallback! "hello" (badBinOptions)) "CLAUDE_BIN")
             (cliAdapterCheck "agy" (p/agy) (cli/dispatchAgyFallback! "hello" (badBinOptions)) "AGY_BIN")
             (lifecycleChecks)
             (siteChecks st)))))
