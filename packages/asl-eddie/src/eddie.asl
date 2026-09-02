(module asl-eddie/eddie
  :doc "EDDIE: 3-Layer Superposition Swarm Orchestrator in ASL"
  :export [TaskTier TaskIntent TriageVerdict TaskItem TaskPool OrchestrationPlan
           fast-triage consult-and-refine plan-execution evaluate-circuit-breaker]
  :import [(core/strings :as s)])

(defenum TriageVerdict
  (:case instant [] "Layer 1: Instant execution (<0.04ms)")
  (:case consult [] "Layer 2: Consultative clarification")
  (:case swarm [] "Layer 3: Task pool delegation"))

(defenum TaskTier
  (:case tier-0 [] "Fast-Track")
  (:case tier-1 [] "Specialist")
  (:case tier-2 [] "Superposition"))

(defenum TaskIntent
  (:case code-gen [] "code generation")
  (:case web-search [] "web search")
  (:case browser-nav [] "browser nav")
  (:case sys-command [] "sys command")
  (:case voice-dialog [] "voice dialog")
  (:case chat-rag [] "chat rag"))

(defschema TaskItem
  (:field id String "task id")
  (:field title String "title")
  (:field assigned-agent String "agent id")
  (:field status String "status")
  (:field duration-ms Float "duration in ms"))

(defschema TaskPool
  (:field leader-task-id String "leader id")
  (:field prompt String "prompt")
  (:field subtasks (List TaskItem) "subtask dag")
  (:field follow-ups (List String) "follow-ups")
  (:field total-completed Int64 "completed count"))

(defschema OrchestrationPlan
  (:field task-id String "task id")
  (:field intent TaskIntent "intent")
  (:field tier TaskTier "tier")
  (:field triage TriageVerdict "triage")
  (:field assigned-agents (List String) "agents")
  (:field follow-up-needed Bool "follow-up flag")
  (:field speculative-branches Int64 "speculative branch count")
  (:field circuit-breaker-limit Int64 "max failure count"))

(defun fast-triage [(prompt String)] -> TriageVerdict
  :doc "Layer 1: Ultra-fast triage"
  (if (== prompt "help")
    (consult)
    (swarm)))

(defun consult-and-refine [(prompt String) (ambiguous Bool)] -> OrchestrationPlan
  :doc "Layer 2: Consultative refinement"
  (if ambiguous
    (OrchestrationPlan :task-id "eddie-consult" :intent (chat-rag) :tier (tier-0) :triage (consult)
                       :assigned-agents (list "agent-consultant") :follow-up-needed true
                       :speculative-branches 1 :circuit-breaker-limit 1)
    (OrchestrationPlan :task-id "eddie-task" :intent (code-gen) :tier (tier-2) :triage (swarm)
                       :assigned-agents (list "agent-planner" "agent-coder" "agent-reviewer") :follow-up-needed false
                       :speculative-branches 2 :circuit-breaker-limit 2)))

(defun plan-execution [(task-id String) (prompt String)] -> OrchestrationPlan
  :doc "Layer 3: Builds task plan"
  (OrchestrationPlan :task-id task-id :intent (code-gen) :tier (tier-2) :triage (swarm)
                     :assigned-agents (list "agent-planner" "agent-coder" "agent-reviewer") :follow-up-needed false
                     :speculative-branches 2 :circuit-breaker-limit 2))

(defun evaluate-circuit-breaker [(failures Int64) (threshold Int64)] -> Bool
  :doc "Evaluates circuit breaker"
  (>= failures threshold))
