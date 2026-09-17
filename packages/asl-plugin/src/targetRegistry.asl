(module asl-plugin/targetRegistry
  :d "Dynamic target dispatch and capability integration registry for AgentScript pluggable backends under ADR D93."
  :x [TargetRegistry emptyTargetRegistry registerTarget hasTarget? lookupTarget dispatchTargetCodegen listRegisteredTargets]
  :i [(ast :a a) (reader :a rd)])

(dfs TargetRegistry
  (:field targets (Map Str (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str))) "Map of target name to emitter function")
  (:field docstrings (Map Str Str) "Documentation string per target"))

(df emptyTargetRegistry [] -> TargetRegistry
  :d "Initializes an empty dynamic target registry."
  (TargetRegistry :targets (map-empty) :docstrings (map-empty)))

(df registerTarget [(reg TargetRegistry) (name Str) (doc Str) (emitter (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str)))] -> TargetRegistry
  :d "Registers a target name, documentation, and code emitter function in the registry."
  (TargetRegistry :targets (map-set (.-targets reg) name emitter)
                  :docstrings (map-set (.-docstrings reg) name doc)))

(df hasTarget? [(reg TargetRegistry) (name Str)] -> Bool
  :d "Returns true if the target is registered in the registry, false otherwise."
  (option-some? (map-get (.-targets reg) name)))

(df lookupTarget [(reg TargetRegistry) (name Str)] -> (Option (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str)))
  :d "Looks up a registered target emitter function by name."
  (map-get (.-targets reg) name))

(df dispatchTargetCodegen [(reg TargetRegistry) (target Str) (forms (List a/TopForm)) (options (Map Str Str))] -> (Result Str Str)
  :d "Dispatches code generation to the registered target emitter or returns an unsupported-target error."
  (mt (lookupTarget reg target)
    ((some emitter) (emitter forms options))
    ((none) (err (str "unsupported-target: " target)))))

(df listRegisteredTargets [(reg TargetRegistry)] -> (List Str)
  :d "Lists all registered target names in the registry."
  (map-keys (.-targets reg)))
