(module asl-eddie/eddie
  :doc "EDDIE: 3-Layer Superposition Swarm Orchestrator in ASL Nano"
  :export [TaskTier TaskIntent TriageVerdict TaskItem TaskPool OrchestrationPlan
           fast-triage consult-and-refine plan-execution evaluate-circuit-breaker]
  :import [(core/strings :as s)])

(dfe TriageVerdict
  (:case instant [] "Layer 1: Instant execution (<0.04ms)")
  (:case consult [] "Layer 2: Consultative clarification")
  (:case swarm [] "Layer 3: Task pool delegation"))

(dfe TaskTier
  (:case tier-0 [] "Fast-Track")
  (:case tier-1 [] "Specialist")
  (:case tier-2 [] "Superposition"))

(dfe TaskIntent
  (:case code-gen [] "code generation")
  (:case web-search [] "web search")
  (:case browser-nav [] "browser nav")
  (:case sys-command [] "sys command")
  (:case voice-dialog [] "voice dialog")
  (:case chat-rag [] "chat rag"))

(dfs TaskItem
  (:field id Str "task id")
  (:field title Str "title")
  (:field assigned-agent Str "agent id")
  (:field status Str "status")
  (:field duration-ms F64 "duration in ms"))

(dfs TaskPool
  (:field leader-task-id Str "leader id")
  (:field prompt Str "prompt")
  (:field subtasks (List TaskItem) "subtask dag")
  (:field follow-ups (List Str) "follow-ups")
  (:field total-completed I64 "completed count"))

(dfs OrchestrationPlan
  (:field task-id Str "task id")
  (:field intent TaskIntent "intent")
  (:field tier TaskTier "tier")
  (:field triage TriageVerdict "triage")
  (:field assigned-agents (List Str) "agents")
  (:field follow-up-needed Bool "follow-up flag")
  (:field speculative-branches I64 "speculative branch count")
  (:field circuit-breaker-limit I64 "max failure count"))

(df fast-triage [(prompt Str)] -> TriageVerdict
  :doc "Layer 1: Ultra-fast triage"
  (if (= (s/concat prompt "") "help")
      (:consult)
      (:swarm)))

(df consult-and-refine [(prompt Str) (ambiguous Bool)] -> OrchestrationPlan
  :doc "Layer 2: Consultative refinement"
  (if ambiguous
      ["eddie-consult" (:chat-rag) (:tier-0) (:consult) ["agent-consultant"] true 1 1]
      ["eddie-task" (:code-gen) (:tier-2) (:swarm) ["agent-planner" "agent-coder" "agent-reviewer"] false 2 2]))

(df plan-execution [(task-id Str) (prompt Str)] -> OrchestrationPlan
  :doc "Layer 3: Builds task plan"
  [task-id (:code-gen) (:tier-2) (:swarm) ["agent-planner" "agent-coder" "agent-reviewer"] false 2 2])

(df evaluate-circuit-breaker [(failures I64) (threshold I64)] -> Bool
  :doc "Evaluates circuit breaker"
  (>= failures threshold))
