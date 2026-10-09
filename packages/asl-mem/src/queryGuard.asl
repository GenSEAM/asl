(module aslMem/queryGuard :x [QueryGuardState makeQueryGuard makeQueryGuardWithLimits recordHelpQuery recordInvalidInvocation recordEmptyInvocation recordProductiveAction recordProductiveActionWithAction isTripped? isTripped remainingHelpBudget remainingInvalidBudget formatEscalationDiagnostic formatEscalationDiagnosticWithReason formatHelpBudget formatCircuitWarning resetQueryGuard formatQueryGuardState] :i [])

(schema QueryGuardState (:f sessionId Str) (:f helpCount I64) (:f emptyCount I64) (:f invalidCount I64) (:f hardHelpLimit I64) (:f hardInvalidLimit I64) (:f isTripped Bool) (:f lastAction Str))

fn makeQueryGuard sessionId: Str -> QueryGuardState
  (QueryGuardState :sessionId sessionId :helpCount 0 :emptyCount 0 :invalidCount 0 :hardHelpLimit 2 :hardInvalidLimit 3 :isTripped false :lastAction "init")

fn makeQueryGuardWithLimits sessionId: Str hardHelpLimit: I64 hardInvalidLimit: I64 -> QueryGuardState
  (QueryGuardState :sessionId sessionId :helpCount 0 :emptyCount 0 :invalidCount 0 :hardHelpLimit hardHelpLimit :hardInvalidLimit hardInvalidLimit :isTripped false :lastAction "init")

fn recordHelpQuery guard: QueryGuardState -> QueryGuardState
  (let [(newCount (+ guard.helpCount 1)) (tripped (or guard.isTripped (> newCount guard.hardHelpLimit)))] (with guard :helpCount newCount :isTripped tripped :lastAction "help"))

fn recordInvalidInvocation guard: QueryGuardState -> QueryGuardState
  (let [(newCount (+ guard.invalidCount 1)) (tripped (or guard.isTripped (>= newCount guard.hardInvalidLimit)))] (with guard :invalidCount newCount :isTripped tripped :lastAction "invalid"))

fn recordEmptyInvocation guard: QueryGuardState -> QueryGuardState
  (let [(newEmpty (+ guard.emptyCount 1)) (newInvalid (+ guard.invalidCount 1)) (tripped (or guard.isTripped (>= newInvalid guard.hardInvalidLimit)))] (with guard :emptyCount newEmpty :invalidCount newInvalid :isTripped tripped :lastAction "empty"))

fn recordProductiveAction guard: QueryGuardState -> QueryGuardState
  (with guard :helpCount 0 :emptyCount 0 :invalidCount 0 :isTripped false :lastAction "productive")

fn recordProductiveActionWithAction guard: QueryGuardState action: Str -> QueryGuardState
  (with guard :helpCount 0 :emptyCount 0 :invalidCount 0 :isTripped false :lastAction action)

fn isTripped? guard: QueryGuardState -> Bool
  guard.isTripped

fn isTripped guard: QueryGuardState -> Bool
  guard.isTripped

fn remainingHelpBudget guard: QueryGuardState -> I64
  (let [(rem (- guard.hardHelpLimit guard.helpCount))] (if (< rem 0) 0 rem))

fn remainingInvalidBudget guard: QueryGuardState -> I64
  (let [(rem (- guard.hardInvalidLimit guard.invalidCount))] (if (< rem 0) 0 rem))

fn formatEscalationDiagnosticWithReason guard: QueryGuardState reason: Str -> Str
  (str "(:circuit-breaker :status :tripped :tool \"mem\" :reason \"" reason "\" :escalate :operator)")

fn formatEscalationDiagnostic guard: QueryGuardState -> Str
  (let [(reason (cond ((> guard.helpCount guard.hardHelpLimit) "Hard help query limit exceeded (3 consecutive calls without state progression)") ((>= guard.invalidCount guard.hardInvalidLimit) "Hard invalid query limit exceeded (3 consecutive syntax/usage errors)") (else "Hard query limit exceeded")))] (formatEscalationDiagnosticWithReason guard reason))

fn formatHelpBudget guard: QueryGuardState -> Str
  (str "(:budget {:helpRemaining " (stringFromInt64 (remainingHelpBudget guard)) "})")

fn formatCircuitWarning guard: QueryGuardState -> Str
  "[CIRCUIT_WARNING] 1 remaining before hard lockout"

fn resetQueryGuard guard: QueryGuardState -> QueryGuardState
  (recordProductiveAction guard)

fn formatQueryGuardState guard: QueryGuardState -> Str
  (str "(:query-guard" " :sessionId \"" guard.sessionId "\"" " :helpCount " (stringFromInt64 guard.helpCount) " :emptyCount " (stringFromInt64 guard.emptyCount) " :invalidCount " (stringFromInt64 guard.invalidCount) " :hardHelpLimit " (stringFromInt64 guard.hardHelpLimit) " :hardInvalidLimit " (stringFromInt64 guard.hardInvalidLimit) " :isTripped " (if guard.isTripped "true" "false") " :lastAction \"" guard.lastAction "\")")
