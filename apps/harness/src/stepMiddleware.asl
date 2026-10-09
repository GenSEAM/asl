(module aslHarness/stepMiddleware :x [StepHookAdapter wireStepPlugins dispatchStepInterceptors adapterActiveCount adapterHasHook? processTurnInputWithResidentTranslator] :i [(aslAgentCore/onion :a on) (pluginHost :a host) (promptTranslator :a pt)])

(schema StepHookAdapter (:f pipeline on/OnionPipeline) (:f adapterName Str) (:f activeHooks (List Str)))

fn containsHook? hooks: (List Str) needle: Str -> Bool
  (fold (fn [(found Bool) (h Str)] -> Bool (or found (= h needle))) false hooks)

fn collectActiveHooks pipeline: on/OnionPipeline -> (List Str)
  (let [(mws pipeline.sorted)] (fold (fn [(acc (List Str)) (m on/Middleware)] -> (List Str) (let [(tag (on/middlewareKindTag m.kind))] (if (containsHook? acc tag) acc (listAppend acc (list tag))))) (list) mws))

fn wireStepPlugins pipeline: on/OnionPipeline -> StepHookAdapter
  (let [(hooks (collectActiveHooks pipeline))] (StepHookAdapter :pipeline pipeline :adapterName "asl-step-hook-adapter" :activeHooks hooks))

fn dispatchStepInterceptors adapter: StepHookAdapter ctx: on/StepContext -> on/StepDecision
  (host/executeStepPipeline adapter.pipeline ctx)

fn adapterActiveCount adapter: StepHookAdapter -> I64
  (listLength adapter.activeHooks)

fn adapterHasHook? adapter: StepHookAdapter hookTag: Str -> Bool
  (containsHook? adapter.activeHooks hookTag)

fn processTurnInputWithResidentTranslator input: Str modelName: Str -> Str
  (let [(cfg (pt/makeTranslationConfig true true true modelName)) (res (pt/translatePrompt input cfg))] res.formattedPrompt)
