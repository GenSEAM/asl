(module asl-eddie/eddie
  :d "EDDIE: 3-Layer Superposition Swarm Orchestrator in ASL"
  :x [TaskTier TaskIntent TriageVerdict TaskItem TaskPool OrchestrationPlan
           fast-triage consult-and-refine plan-execution evaluate-circuit-breaker]
  :i [(core/strings :a s)])

(dfe TriageVerdict
  (:c instant [] "Layer 1: Instant execution (<0.04ms)")
  (:c consult [] "Layer 2: Consultative clarification")
  (:c swarm [] "Layer 3: Task pool delegation"))

(dfe TaskTier
  (:c tier-0 [] "Fast-Track")
  (:c tier-1 [] "Specialist")
  (:c tier-2 [] "Superposition"))

(dfe TaskIntent
  (:c code-gen [] "code generation")
  (:c web-search [] "web search")
  (:c browser-nav [] "browser nav")
  (:c sys-command [] "sys command")
  (:c voice-dialog [] "voice dialog")
  (:c chat-rag [] "chat rag"))

(dfs TaskItem
  (:f id String "task id")
  (:f title String "title")
  (:f assigned-agent String "agent id")
  (:f status String "status")
  (:f duration-ms Float "duration in ms"))

(dfs TaskPool
  (:f leader-task-id String "leader id")
  (:f prompt String "prompt")
  (:f subtasks (List TaskItem) "subtask dag")
  (:f follow-ups (List String) "follow-ups")
  (:f total-completed Int64 "completed count"))

(dfs OrchestrationPlan
  (:f task-id String "task id")
  (:f intent TaskIntent "intent")
  (:f tier TaskTier "tier")
  (:f triage TriageVerdict "triage")
  (:f assigned-agents (List String) "agents")
  (:f follow-up-needed Bool "follow-up flag")
  (:f speculative-branches Int64 "speculative branch count")
  (:f circuit-breaker-limit Int64 "max failure count"))

(df fast-triage [(prompt String)] -> TriageVerdict
  :d "Layer 1: Ultra-fast triage"
  (if (== prompt "help")
    (consult)
    (swarm)))

(df consult-and-refine [(prompt String) (ambiguous Bool)] -> OrchestrationPlan
  :d "Layer 2: Consultative refinement"
  (if ambiguous
    (OrchestrationPlan :task-id "eddie-consult" :intent (chat-rag) :tier (tier-0) :triage (consult)
                       :assigned-agents (list "agent-consultant") :follow-up-needed true
                       :speculative-branches 1 :circuit-breaker-limit 1)
    (OrchestrationPlan :task-id "eddie-task" :intent (code-gen) :tier (tier-2) :triage (swarm)
                       :assigned-agents (list "agent-planner" "agent-coder" "agent-reviewer") :follow-up-needed false
                       :speculative-branches 2 :circuit-breaker-limit 2)))

(df plan-execution [(task-id String) (prompt String)] -> OrchestrationPlan
  :d "Layer 3: Builds task plan"
  (OrchestrationPlan :task-id task-id :intent (code-gen) :tier (tier-2) :triage (swarm)
                     :assigned-agents (list "agent-planner" "agent-coder" "agent-reviewer") :follow-up-needed false
                     :speculative-branches 2 :circuit-breaker-limit 2))

(df evaluate-circuit-breaker [(failures Int64) (threshold Int64)] -> Bool
  :d "Evaluates circuit breaker"
  (>= failures threshold))
