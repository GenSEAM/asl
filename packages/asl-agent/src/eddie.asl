(module aslAgent/eddie :x [TaskTier TaskIntent TriageVerdict TaskItem TaskPool OrchestrationPlan fastTriage consultAndRefine planExecution evaluateCircuitBreaker agentRun! agentVersion agentBanner gsaRun! gsaVersion gsaBanner eddieRun! eddieVersion eddieBanner addieRun! addieVersion addieBanner] :i [(asl-text/string :a s) (policy :a pol) (agent :a ag) (feedback :a fb) (tui :a tui)])

(enum TriageVerdict (:c instant [] "Layer 1: Instant execution (<0.04ms)") (:c consult [] "Layer 2: Consultative clarification") (:c swarm [] "Layer 3: Task pool delegation"))

(enum TaskTier (:c tier0 [] "Fast-Track") (:c tier1 [] "Specialist") (:c tier2 [] "Superposition"))

(enum TaskIntent (:c codeGen [] "code generation") (:c webSearch [] "web search") (:c browserNav [] "browser nav") (:c sysCommand [] "sys command") (:c voiceDialog [] "voice dialog") (:c chatRag [] "chat rag"))

(schema TaskItem (:f id String) (:f title String) (:f assignedAgent String) (:f status String) (:f durationMs Float))

(schema TaskPool (:f leaderTaskId String) (:f prompt String) (:f subtasks (List TaskItem)) (:f followUps (List String)) (:f totalCompleted Int64))

(schema OrchestrationPlan (:f taskId String) (:f intent TaskIntent) (:f tier TaskTier) (:f triage TriageVerdict) (:f assignedAgents (List String)) (:f followUpNeeded Bool) (:f speculativeBranches Int64) (:f circuitBreakerLimit Int64))

fn fastTriage prompt: String -> TriageVerdict
  (if (= prompt "help") (consult) (swarm))

fn consultAndRefine prompt: String ambiguous: Bool -> OrchestrationPlan
  (if ambiguous (OrchestrationPlan :taskId "addie-consult" :intent (chatRag) :tier (tier0) :triage (consult) :assignedAgents (list "agent-consultant") :followUpNeeded true :speculativeBranches 1 :circuitBreakerLimit 1) (OrchestrationPlan :taskId "addie-task" :intent (codeGen) :tier (tier2) :triage (swarm) :assignedAgents (list "agent-planner" "agent-coder" "agent-reviewer") :followUpNeeded false :speculativeBranches 2 :circuitBreakerLimit 2))

fn planExecution taskId: String prompt: String -> OrchestrationPlan
  (OrchestrationPlan :taskId taskId :intent (codeGen) :tier (tier2) :triage (swarm) :assignedAgents (list "agent-planner" "agent-coder" "agent-reviewer") :followUpNeeded false :speculativeBranches 2 :circuitBreakerLimit 2)

fn evaluateCircuitBreaker failures: Int64 threshold: Int64 -> Bool
  (>= failures threshold)

fn agentVersion -> Str
  "0.1.0"

fn gsaVersion -> Str
  (agentVersion)

fn addieVersion -> Str
  "0.1.0"

fn eddieVersion -> Str
  (addieVersion)

fn agentBanner -> Str
  "=== GSA (GenSEAM Agent) - Pure ASL Autonomous Coding Agent ==="

fn gsaBanner -> Str
  (agentBanner)

fn addieBanner -> Str
  "=== GSA (GenSEAM Agent) - Pure ASL Autonomous Coding Agent ==="

fn eddieBanner -> Str
  (addieBanner)

fn addieRun! prompt: Str workspaceRoot: Str autonomy: pol/AutonomyLevel -> Str
  (let [(manifest (pol/makeManifest workspaceRoot (list) "/tmp" false)) (req (fb/refineUserPrompt prompt (list workspaceRoot)))] (if req.isAmbiguous (let [(opts (list (fb/ClarificationOption :key "1" :label "Execute in current workspace") (fb/ClarificationOption :key "2" :label "Run in isolated worktree"))) (q (fb/formatClarifyingQuestion req opts))] q) (let [(sess (ag/makeAutonomySession req.clarifiedGoal manifest autonomy)) (s1 (ag/stepAgent! sess "exec" prompt "")) (s2 (ag/stepAgent! s1.session "finish" "" "task completed successfully")) (h (tui/makeTuiHeader "gemma-4-31b-it" autonomy)) (summary (tui/formatSessionSummary h 2))] (str (tui/formatTuiHeader h) "\n" (fb/formatConciseDirective req) "\n" summary))))

fn eddieRun! prompt: Str workspaceRoot: Str autonomy: pol/AutonomyLevel -> Str
  (addieRun! prompt workspaceRoot autonomy)

fn agentRun! prompt: Str workspaceRoot: Str autonomy: pol/AutonomyLevel -> Str
  (addieRun! prompt workspaceRoot autonomy)

fn gsaRun! prompt: Str workspaceRoot: Str autonomy: pol/AutonomyLevel -> Str
  (addieRun! prompt workspaceRoot autonomy)
