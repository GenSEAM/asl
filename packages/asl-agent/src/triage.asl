(module aslAgent/triage :x [WorkspaceContext TriageDecision makeWorkspaceContext makeTriageDecision isSetupCommand? isAdminCommand? isQuestion? isDevCommand? hasMultiAspect? hasExplicitSplit? triageRequest] :i [])

(schema WorkspaceContext (:f projectName Str) (:f rootPath Str) (:f isGit Bool) (:f knownProjects (List Str)))

(schema TriageDecision (:f kind Str) (:f targetProject Str) (:f shape Str) (:f collapsedSingle Bool) (:f reason Str))

fn makeWorkspaceContext projectName: Str rootPath: Str isGit: Bool knownProjects: (List Str) -> WorkspaceContext
  (WorkspaceContext :projectName projectName :rootPath rootPath :isGit isGit :knownProjects knownProjects)

fn makeTriageDecision kind: Str targetProject: Str shape: Str collapsedSingle: Bool reason: Str -> TriageDecision
  (TriageDecision :kind kind :targetProject targetProject :shape shape :collapsedSingle collapsedSingle :reason reason)

fn isSetupCommand? s: Str -> Bool
  (let [(low (stringLower s))] (cond ((stringStartsWith? low "git init") true) ((stringStartsWith? low "init ") true) ((= low "init") true) ((stringStartsWith? low "git clone") true) ((stringStartsWith? low "clone ") true) ((stringStartsWith? low "git branch") true) ((stringStartsWith? low "branch ") true) ((stringStartsWith? low "checkout ") true) ((stringContains? low "project.init") true) ((stringContains? low "project.clone") true) ((stringContains? low "project.branch") true) ((stringContains? low "setup workspace") true) (else false)))

fn isAdminCommand? s: Str -> Bool
  (let [(low (stringLower s))] (cond ((stringStartsWith? low "voice.") true) ((stringStartsWith? low "config.") true) ((stringStartsWith? low "cancel") true) ((stringStartsWith? low "drop") true) ((stringStartsWith? low "status") true) ((= low "help") true) (else false)))

fn isQuestion? s: Str -> Bool
  (let [(low (stringLower s))] (cond ((stringContains? low "?") true) ((stringStartsWith? low "what ") true) ((stringStartsWith? low "how ") true) ((stringStartsWith? low "why ") true) ((stringStartsWith? low "where ") true) ((stringStartsWith? low "who ") true) ((stringStartsWith? low "when ") true) ((stringStartsWith? low "tell me") true) ((stringStartsWith? low "explain") true) ((stringStartsWith? low "summarize") true) ((stringStartsWith? low "расскажи") true) ((stringStartsWith? low "объясни") true) ((stringStartsWith? low "что ") true) ((stringStartsWith? low "как ") true) ((stringStartsWith? low "почему ") true) (else false)))

fn isDevCommand? s: Str -> Bool
  (let [(low (stringLower s))] (cond ((stringContains? low "fix ") true) ((stringContains? low "bug") true) ((stringContains? low "implement") true) ((stringContains? low "refactor") true) ((stringContains? low "compile") true) ((stringContains? low "build") true) ((stringContains? low "test") true) ((stringContains? low "patch") true) ((stringContains? low "function") true) ((stringContains? low "class") true) ((stringContains? low "почини") true) ((stringContains? low "исправь") true) ((stringContains? low "напиши код") true) (else false)))

fn hasMultiAspect? s: Str -> Bool
  (let [(low (stringLower s))] (cond ((stringContains? low " and ") true) ((stringContains? low " also ") true) ((stringContains? low " plus ") true) ((stringContains? low " as well as ") true) ((stringContains? low " и ") true) ((stringContains? low " также ") true) ((stringContains? low " а еще ") true) (else false)))

fn hasExplicitSplit? s: Str -> Bool
  (let [(low (stringLower s))] (cond ((stringContains? low "split into tasks") true) ((stringContains? low "create separate tasks") true) ((stringContains? low "separate tasks") true) ((stringContains? low "отдельные задачи") true) ((stringContains? low "разбей на задачи") true) ((stringContains? low "разные задачи") true) (else false)))

fn triageRequest input: Str ctx: WorkspaceContext -> TriageDecision
  (cond ((isSetupCommand? input) (makeTriageDecision "setup" "general" "single" false "setup command routed to workspace setup (d-1a1a)")) ((isAdminCommand? input) (makeTriageDecision "admin" ctx.projectName "single" false "administrative command")) ((isQuestion? input) (let [(multi (hasMultiAspect? input)) (split (hasExplicitSplit? input))] (if (and multi split) (makeTriageDecision "question" ctx.projectName "workflow" false "explicit split requested") (makeTriageDecision "question" ctx.projectName "single" multi "informational query collapsed to single task frame (d-374e)")))) ((isDevCommand? input) (let [(split (hasExplicitSplit? input))] (if split (makeTriageDecision "dev" ctx.projectName "workflow" false "explicit dev split requested") (makeTriageDecision "dev" ctx.projectName "single" false "development task frame")))) (else (let [(multi (hasMultiAspect? input)) (split (hasExplicitSplit? input))] (if (and multi split) (makeTriageDecision "non-dev" ctx.projectName "workflow" false "explicit non-dev split requested") (makeTriageDecision "non-dev" ctx.projectName "single" multi "errand collapsed to single task frame (d-374e)")))))
