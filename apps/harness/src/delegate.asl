(module aslHarness/delegate :x [DelegationMode DelegationPlan makeDelegationPlan delegateTaskExecution multiplexContextSlices] :i [])

(enum DelegationMode (:c self [] "Direct single-turn execution by supervisor") (:c single [] "Single dedicated worker assigned to a task") (:c speculativeRace [] "Concurrent dual-trajectory race across asymmetric temperature configurations") (:c cleanSupervisor [] "Stateless audit evaluation with empty context"))

(schema DelegationPlan (:f taskId Str) (:f mode DelegationMode) (:f lanes (List Str)) (:f temperatures (List Float)) (:f maxTurns Int64))

fn multiplexContextSlices baseSpec: Str lanes: (List Str) -> (List Str)
  (if (listEmpty? lanes) (list) (let [(head (optionOr (listHead lanes) "")) (tail (optionOr (listTail lanes) (list))) (slice (str "(:context-slice :lane \"" head "\" :spec \"" baseSpec "\")"))] (cons slice (multiplexContextSlices baseSpec tail))))

fn makeDelegationPlan taskId: Str mode: DelegationMode -> DelegationPlan
  (match mode ((speculativeRace) (DelegationPlan :taskId taskId :mode mode :lanes (list "alpha" "beta") :temperatures (list 0.1 0.7) :maxTurns 3)) ((single) (DelegationPlan :taskId taskId :mode mode :lanes (list "alpha") :temperatures (list 0.2) :maxTurns 5)) ((cleanSupervisor) (DelegationPlan :taskId taskId :mode mode :lanes (list "audit") :temperatures (list 0.0) :maxTurns 1)) ((self) (DelegationPlan :taskId taskId :mode mode :lanes (list "supervisor") :temperatures (list 0.0) :maxTurns 1)))

fn delegateTaskExecution plan: DelegationPlan spec: Str -> (List Str)
  (multiplexContextSlices spec plan.lanes)
