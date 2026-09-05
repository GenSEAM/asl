(module asl-eddie/triage
  :d "Formal AST intent triage and multi-query collapse engine."
  :x [WorkspaceContext TriageDecision
      make-workspace-context make-triage-decision
      is-setup-command? is-admin-command? is-question? is-dev-command?
      has-multi-aspect? has-explicit-split?
      triage-request]
  :i [])

(dfs WorkspaceContext
  (:f project-name Str "Name of current project or 'general'")
  (:f root-path Str "Root directory path")
  (:f is-git Bool "True if current directory is a git repo")
  (:f known-projects (List Str) "List of registered projects in workspace"))

(dfs TriageDecision
  (:f kind Str "Intent kind: dev, non-dev, question, setup, admin")
  (:f target-project Str "Target project identifier")
  (:f shape Str "Execution shape: single, workflow, group")
  (:f collapsed-single Bool "True if multi-aspect query collapsed into single task frame")
  (:f reason Str "Explanation of triage decision"))

(df make-workspace-context [(project-name Str) (root-path Str) (is-git Bool) (known-projects (List Str))] -> WorkspaceContext
  :d "Constructs a WorkspaceContext record."
  (WorkspaceContext
    :project-name project-name
    :root-path root-path
    :is-git is-git
    :known-projects known-projects))

(df make-triage-decision [(kind Str) (target-project Str) (shape Str) (collapsed-single Bool) (reason Str)] -> TriageDecision
  :d "Constructs a TriageDecision record."
  (TriageDecision
    :kind kind
    :target-project target-project
    :shape shape
    :collapsed-single collapsed-single
    :reason reason))

(df is-setup-command? [(s Str)] -> Bool
  :d "Detects setup and project provisioning commands (@pcp:d-1a1a)."
  (let [(low (string-lower s))]
    (cond
      ((string-starts-with? low "git init") true)
      ((string-starts-with? low "init ") true)
      ((= low "init") true)
      ((string-starts-with? low "git clone") true)
      ((string-starts-with? low "clone ") true)
      ((string-starts-with? low "git branch") true)
      ((string-starts-with? low "branch ") true)
      ((string-starts-with? low "checkout ") true)
      ((string-contains? low "project.init") true)
      ((string-contains? low "project.clone") true)
      ((string-contains? low "project.branch") true)
      ((string-contains? low "setup workspace") true)
      (:else false))))

(df is-admin-command? [(s Str)] -> Bool
  :d "Detects administrative operations."
  (let [(low (string-lower s))]
    (cond
      ((string-starts-with? low "voice.") true)
      ((string-starts-with? low "config.") true)
      ((string-starts-with? low "cancel") true)
      ((string-starts-with? low "drop") true)
      ((string-starts-with? low "status") true)
      ((= low "help") true)
      (:else false))))

(df is-question? [(s Str)] -> Bool
  :d "Detects informational inquiries."
  (let [(low (string-lower s))]
    (cond
      ((string-contains? low "?") true)
      ((string-starts-with? low "what ") true)
      ((string-starts-with? low "how ") true)
      ((string-starts-with? low "why ") true)
      ((string-starts-with? low "where ") true)
      ((string-starts-with? low "who ") true)
      ((string-starts-with? low "when ") true)
      ((string-starts-with? low "tell me") true)
      ((string-starts-with? low "explain") true)
      ((string-starts-with? low "summarize") true)
      ((string-starts-with? low "расскажи") true)
      ((string-starts-with? low "объясни") true)
      ((string-starts-with? low "что ") true)
      ((string-starts-with? low "как ") true)
      ((string-starts-with? low "почему ") true)
      (:else false))))

(df is-dev-command? [(s Str)] -> Bool
  :d "Detects code editing and engineering development requests."
  (let [(low (string-lower s))]
    (cond
      ((string-contains? low "fix ") true)
      ((string-contains? low "bug") true)
      ((string-contains? low "implement") true)
      ((string-contains? low "refactor") true)
      ((string-contains? low "compile") true)
      ((string-contains? low "build") true)
      ((string-contains? low "test") true)
      ((string-contains? low "patch") true)
      ((string-contains? low "function") true)
      ((string-contains? low "class") true)
      ((string-contains? low "почини") true)
      ((string-contains? low "исправь") true)
      ((string-contains? low "напиши код") true)
      (:else false))))

(df has-multi-aspect? [(s Str)] -> Bool
  :d "Detects queries containing multiple coordination aspects."
  (let [(low (string-lower s))]
    (cond
      ((string-contains? low " and ") true)
      ((string-contains? low " also ") true)
      ((string-contains? low " plus ") true)
      ((string-contains? low " as well as ") true)
      ((string-contains? low " и ") true)
      ((string-contains? low " также ") true)
      ((string-contains? low " а еще ") true)
      (:else false))))

(df has-explicit-split? [(s Str)] -> Bool
  :d "Detects explicit request to fracture work into separate board tasks."
  (let [(low (string-lower s))]
    (cond
      ((string-contains? low "split into tasks") true)
      ((string-contains? low "create separate tasks") true)
      ((string-contains? low "separate tasks") true)
      ((string-contains? low "отдельные задачи") true)
      ((string-contains? low "разбей на задачи") true)
      ((string-contains? low "разные задачи") true)
      (:else false))))

(df triage-request [(input Str) (ctx WorkspaceContext)] -> TriageDecision
  :d "Deterministically triages input query into execution decision with multi-aspect collapse (@pcp:d-374e)."
  (cond
    ((is-setup-command? input)
     (make-triage-decision "setup" "general" "single" false "setup command routed to workspace setup (@pcp:d-1a1a)"))
    ((is-admin-command? input)
     (make-triage-decision "admin" (.-project-name ctx) "single" false "administrative command"))
    ((is-question? input)
     (let [(multi (has-multi-aspect? input))
           (split (has-explicit-split? input))]
       (if (and multi split)
         (make-triage-decision "question" (.-project-name ctx) "workflow" false "explicit split requested")
         (make-triage-decision "question" (.-project-name ctx) "single" multi "informational query collapsed to single task frame (@pcp:d-374e)"))))
    ((is-dev-command? input)
     (let [(split (has-explicit-split? input))]
       (if split
         (make-triage-decision "dev" (.-project-name ctx) "workflow" false "explicit dev split requested")
         (make-triage-decision "dev" (.-project-name ctx) "single" false "development task frame"))))
    (:else
     (let [(multi (has-multi-aspect? input))
           (split (has-explicit-split? input))]
       (if (and multi split)
         (make-triage-decision "non-dev" (.-project-name ctx) "workflow" false "explicit non-dev split requested")
         (make-triage-decision "non-dev" (.-project-name ctx) "single" multi "errand collapsed to single task frame (@pcp:d-374e)"))))))
