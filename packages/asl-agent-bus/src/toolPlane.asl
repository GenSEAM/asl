(module aslAgentBus/toolPlane :x [ToolRouter makeToolRouter registerToolRunbook getToolRunbook getToolGuidance isToolEligible? routeTools countRoutedTools] :i [(aslContracts/toolPlane :a tp)])

(schema ToolRouter (:f tools (List ToolDescriptor)) (:f runbooks (Map Str ToolRunbook)))

fn makeToolRouter tools: (List ToolDescriptor) -> ToolRouter
  (ToolRouter :tools tools :runbooks (mapEmpty))

fn registerToolRunbook router: ToolRouter toolId: Str runbook: ToolRunbook -> ToolRouter
  (with router :runbooks (mapSet router.runbooks toolId runbook))

fn getToolRunbook router: ToolRouter toolId: Str -> Option
  (mapGet router.runbooks toolId)

fn getToolGuidance router: ToolRouter toolId: Str -> Str
  (let [(matches (filter (fn [t] (= t.id toolId)) router.tools))] (if (listEmpty? matches) "" (mt (listHead matches) ((some t) t.guidance) ((none) ""))))

fn isToolEligible? tool: ToolDescriptor ctx: ToolScopeContext -> Bool
  (and (tp/isToolInScope? tool ctx.activeRepo) (and (tp/isAgentAuthorized? tool ctx.agentRole) (tp/isSafetyPermitted? tool ctx.safetyCeiling)))

fn routeTools router: ToolRouter ctx: ToolScopeContext redact?: Bool -> (List ToolDescriptor)
  (let [(filtered (filter (fn [t] (isToolEligible? t ctx)) router.tools))] (if redact? (map (fn [t] (tp/maskToolSecrets t)) filtered) filtered))

fn countRoutedTools router: ToolRouter ctx: ToolScopeContext -> I64
  (listLength (routeTools router ctx false))
