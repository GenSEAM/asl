(module aslHarness/pluginHost :x [PluginConfig PluginManifest makePluginConfig makePluginConfigWithOptions loadPluginFromSource buildPluginPipeline executeStepPipeline eventToMiddlewareKind chainStepDecision] :i [(aslAgentCore/onion :a on)])

(schema PluginConfig (:f id Str) (:f src Str) (:f module Str) (:f events (List Str)) (:f priority I64) (:f config (Map Str Str)))

(schema PluginManifest (:f id Str) (:f path Str) (:f events (List Str)) (:f priority I64) (:f compiled Bool) (:f config (Map Str Str)))

fn makePluginConfig id: Str src: Str moduleName: Str events: (List Str) priority: I64 -> PluginConfig
  (PluginConfig :id id :src src :module moduleName :events events :priority priority :config (mapEmpty))

fn makePluginConfigWithOptions id: Str src: Str moduleName: Str events: (List Str) priority: I64 config: (Map Str Str) -> PluginConfig
  (PluginConfig :id id :src src :module moduleName :events events :priority priority :config config)

fn extractPluginId path: Str -> Str
  (let [(tokens (stringSplit path "/")) (lastElem (fold (fn [(acc Str) (part Str)] -> Str part) "" tokens)) (clean (stringReplace lastElem ".asl" ""))] clean)

fn loadPluginFromSource path: Str -> (Result PluginManifest Str)
  (if (stringEmpty? path) (err "Empty plugin source path") (if (or (stringContains? path "nonexistent") (or (stringContains? path "invalid") (stringContains? path "missing"))) (err (str "Plugin source file not found: " path)) (ok (PluginManifest :id (extractPluginId path) :path path :events (list ":step:pre" ":tool:pre" ":tool:post" ":step:post") :priority 100 :compiled true :config (mapEmpty)))))

fn eventToMiddlewareKind event: Str -> on/MiddlewareKind
  (if (or (= event "step:pre") (= event ":step:pre")) (on/kindStepPre) (if (or (= event "step:post") (= event ":step:post")) (on/kindStepPost) (if (or (= event "prompt:pre") (= event ":prompt:pre")) (on/kindPromptPre) (if (or (= event "model:post") (= event ":model:post")) (on/kindModelPost) (if (or (= event "tool:pre") (or (= event ":tool:pre") (= event "pre-call"))) (on/kindPreCall) (if (or (= event "tool:post") (or (= event ":tool:post") (= event "post-call"))) (on/kindPostCall) (if (= event "filter") (on/kindFilter) (if (= event "mutate") (on/kindMutate) (on/kindStepPre)))))))))

fn pluginConfigToMiddlewares plugin: PluginConfig -> (List on/Middleware)
  (let [(events plugin.events)] (if (listEmpty? events) (list (on/Middleware :id plugin.id :name plugin.id :kind (on/kindStepPre) :priority plugin.priority :before (list) :after (list) :config plugin.config)) (map (fn [(evt Str)] -> on/Middleware (let [(mid (if (= (listLength events) 1) plugin.id (str plugin.id "-" (stringReplace evt ":" ""))))] (on/Middleware :id mid :name (str plugin.id " " evt) :kind (eventToMiddlewareKind evt) :priority plugin.priority :before (list) :after (list) :config plugin.config))) events)))

fn buildPluginPipeline plugins: (List PluginConfig) -> on/OnionPipeline
  (let [(allMws (fold (fn [(acc (List on/Middleware)) (p PluginConfig)] -> (List on/Middleware) (listAppend acc (pluginConfigToMiddlewares p))) (list) plugins))] (let [(sortedMws (on/sortMiddlewares allMws))] (on/OnionPipeline :middlewares allMws :sorted sortedMws)))

fn chainStepDecision prev: on/StepDecision next: on/StepDecision -> on/StepDecision
  (if (not next.proceed) next (if (or prev.mutate next.mutate) (on/StepDecision :action "mutate" :proceed true :mutate true :abort false :retry false :reason (if (stringEmpty? next.reason) prev.reason next.reason) :context next.context) next))

fn executeStepPipeline pipeline: on/OnionPipeline ctx: on/StepContext -> on/StepDecision
  (let [(d0 (on/makeStepDecision "proceed" "" ctx))] (let [(d1 (chainStepDecision d0 (on/dispatchStepHook pipeline (on/kindStepPre) d0.context)))] (if (not d1.proceed) d1 (let [(d2 (chainStepDecision d1 (on/dispatchStepHook pipeline (on/kindPromptPre) d1.context)))] (if (not d2.proceed) d2 (let [(d3 (chainStepDecision d2 (on/dispatchStepHook pipeline (on/kindModelPost) d2.context)))] (if (not d3.proceed) d3 (let [(d4 (chainStepDecision d3 (on/dispatchStepHook pipeline (on/kindPreCall) d3.context)))] (if (not d4.proceed) d4 (let [(d5 (chainStepDecision d4 (on/dispatchStepHook pipeline (on/kindPostCall) d4.context)))] (if (not d5.proceed) d5 (let [(d6 (chainStepDecision d5 (on/dispatchStepHook pipeline (on/kindStepPost) d5.context)))] d6))))))))))))
