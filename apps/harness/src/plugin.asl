(module aslHarness/plugin :x [PluginCapability AgentPlugin PluginRegistry createPlugin registryCreate registryAdd registryFind registryGetTools buildStandardHarnessPlugins evaluatePluginGuards containsString?] :i [(config :a cfg) (asl-text/string :a s)])

(schema PluginCapability (:f providedTools (List Str)) (:f systemPrompts (List Str)) (:f hooks (List cfg/PluginHook)) (:f dependencies (List Str)) (:f conflicts (List Str)) (:f predicates (List cfg/HookPredicate)))

(schema AgentPlugin (:f id Str) (:f name Str) (:f version Str) (:f enabled Bool) (:f priority I64) (:f capability PluginCapability))

(schema PluginRegistry (:f plugins (List AgentPlugin)) (:f activeCount I64))

fn createPlugin id: Str name: Str ver: Str prio: I64 cap: PluginCapability -> AgentPlugin
  (AgentPlugin :id id :name name :version ver :enabled true :priority prio :capability cap)

fn registryCreate -> PluginRegistry
  (PluginRegistry :plugins (list) :activeCount 0)

fn registryAdd reg: PluginRegistry plugin: AgentPlugin -> PluginRegistry
  (let [(filtered (filter (fn [(p AgentPlugin)] -> Bool (!= p.id plugin.id)) reg.plugins)) (updated (listAppend filtered (list plugin))) (active (listLength (filter (fn [(p AgentPlugin)] -> Bool p.enabled) updated)))] (PluginRegistry :plugins updated :activeCount active))

fn registryFind reg: PluginRegistry pluginId: Str -> (Option AgentPlugin)
  (fold (fn [(acc (Option AgentPlugin)) (p AgentPlugin)] -> (Option AgentPlugin) (mt acc ((some _) acc) ((none) (if (= p.id pluginId) (some p) (none))))) (none) reg.plugins)

fn registryGetTools reg: PluginRegistry -> (List Str)
  (fold (fn [(acc (List Str)) (p AgentPlugin)] -> (List Str) (if p.enabled (let [(tools p.capability.providedTools)] (fold (fn [(iacc (List Str)) (t Str)] -> (List Str) (if (containsString? iacc t) iacc (listAppend iacc (list t)))) acc tools)) acc)) (list) reg.plugins)

fn containsString? items: (List Str) needle: Str -> Bool
  (fold (fn [(found Bool) (item Str)] -> Bool (or found (= item needle))) false items)

fn buildStandardHarnessPlugins -> PluginRegistry
  (let [(pIntel (createPlugin "builtin-code-intel" "Codebase Intelligence & Horizon Paging" "1.0.0" 1 (PluginCapability :providedTools (list "intel-preload" "intel-impact" "intel-health") :systemPrompts (list "Always use intel-preload before modifying unknown files.") :hooks (list (cfg/hookPreCall)) :dependencies (list) :conflicts (list) :predicates (list)))) (pGuard (createPlugin "builtin-ast-guard" "AST Mutation Gate & Trace Sanitizer" "1.0.0" 1 (PluginCapability :providedTools (list "audit-ast-mutation" "sanitize-trace") :systemPrompts (list "Never delete protected assertions; verify AST deltas.") :hooks (list (cfg/hookPostCall)) :dependencies (list) :conflicts (list) :predicates (list)))) (pCss (createPlugin "builtin-css-cascade" "CSS Cascade & Variable Extractor" "1.0.0" 2 (PluginCapability :providedTools (list "extract-css-variables" "resolve-computed-style") :systemPrompts (list "Compute CSS cascade specificity inline without bloated external tools.") :hooks (list) :dependencies (list) :conflicts (list) :predicates (list)))) (pComp (createPlugin "builtin-component-mapper" "Component Usage Mapper & Design Policy Guard" "1.0.0" 2 (PluginCapability :providedTools (list "scan-component-usages" "batch-transform-classes" "audit-design-policy") :systemPrompts (list "Enforce design system component usage; ban raw input tags.") :hooks (list (cfg/hookPreCall)) :dependencies (list) :conflicts (list) :predicates (list)))) (pPoly (createPlugin "builtin-polyglot-sandbox" "Polyglot AST & In-Memory Script Sandbox" "1.0.0" 2 (PluginCapability :providedTools (list "extract-ast-outline" "run-sandboxed-script") :systemPrompts (list "Run untrusted polyglot code in isolated in-memory sandboxes.") :hooks (list (cfg/hookError)) :dependencies (list) :conflicts (list) :predicates (list)))) (reg0 (registryCreate)) (reg1 (registryAdd reg0 pIntel)) (reg2 (registryAdd reg1 pGuard)) (reg3 (registryAdd reg2 pCss)) (reg4 (registryAdd reg3 pComp)) (reg5 (registryAdd reg4 pPoly))] reg5)

fn hookTag h: cfg/PluginHook -> Str
  (mt h ((cfg/hookPreCall) "pre") ((cfg/hookPostCall) "post") ((cfg/hookModelResponse) "resp") ((cfg/hookError) "err"))

fn hookEq? h1: cfg/PluginHook h2: cfg/PluginHook -> Bool
  (= (hookTag h1) (hookTag h2))

fn evaluatePluginGuards plugin: AgentPlugin hook: cfg/PluginHook toolName: Str -> Bool
  (if (not plugin.enabled) true (let [(cap plugin.capability) (preds cap.predicates) (hooks cap.hooks) (hasHook (fold (fn [(found Bool) (h cfg/PluginHook)] -> Bool (or found (hookEq? h hook))) false hooks))] (if (not hasHook) true (let [(denied (fold (fn [(isDenied Bool) (p cfg/HookPredicate)] -> Bool (if isDenied true (if (and (hookEq? p.hookType hook) (cfg/evaluateHookPredicate p toolName "guard")) (= p.actionOverride "deny") false))) false preds))] (not denied)))))
