(module aslAgent/corridor :x [FreedomCorridor makeCorridor defaultCorridor isActionPermittedByCorridor? formatCorridorSummary corridorToAsn] :i [])

(schema FreedomCorridor (:f corridorId Str) (:f immutableInvariants (List Str)) (:f allowedExplorations (List Str)) (:f acceptanceCriteria (List Str)) (:f maxReviewRounds I64) (:f maxStepBudget I64))

fn makeCorridor id: Str invariants: (List Str) explorations: (List Str) criteria: (List Str) -> FreedomCorridor
  (FreedomCorridor :corridorId id :immutableInvariants invariants :allowedExplorations explorations :acceptanceCriteria criteria :maxReviewRounds 2 :maxStepBudget 20)

fn defaultCorridor id: Str -> FreedomCorridor
  (makeCorridor id (list "C1: zero comments in ASL" "C2: zero emojis in ASN" "gate-integrity: zero gate weakening" "pure-asl: zero foreign code in packages") (list "ast-refactoring: structural AST edits permitted" "ui-composition: VDOM and terminal TUI exploration permitted" "model-routing: multi-model selection per task role permitted" "test-expansion: authoring dual-polarity test suites permitted") (list "all 7 verification gates pass cleanly" "test coverage >= 90.0%" "zero vacuous assertions"))

fn isActionPermittedByCorridor? corridor: FreedomCorridor actionDesc: Str targetPath: Str -> Bool
  (let [(act (stringLower actionDesc))] (cond ((stringContains? act "weaken") false) ((stringContains? act "loosen") false) ((stringContains? act "skip gate") false) ((stringContains? act "bypass gate") false) ((stringContains? act "add comment") false) ((stringContains? act "insert comment") false) ((stringContains? act "delete test") false) ((stringContains? act "skip test") false) ((stringContains? act "rubber-stamp") false) (else true)))

fn formatCorridorSummary corridor: FreedomCorridor -> Str
  (str "Corridor [" corridor.corridorId "]: Invariants (" (stringFromInt64 (listLength corridor.immutableInvariants)) "), Explorations (" (stringFromInt64 (listLength corridor.allowedExplorations)) "), Criteria (" (stringFromInt64 (listLength corridor.acceptanceCriteria)) "), Review Ceiling (" (stringFromInt64 corridor.maxReviewRounds) " rounds)")

fn corridorToAsn corridor: FreedomCorridor -> Str
  (let [(invStr (fold (fn [(acc Str) (inv Str)] -> Str (str acc "\"" inv "\" ")) "" corridor.immutableInvariants)) (expStr (fold (fn [(acc Str) (exp Str)] -> Str (str acc "\"" exp "\" ")) "" corridor.allowedExplorations)) (crtStr (fold (fn [(acc Str) (crt Str)] -> Str (str acc "\"" crt "\" ")) "" corridor.acceptanceCriteria))] (str "(:corridor :id \"" corridor.corridorId "\" :max-reviews " (stringFromInt64 corridor.maxReviewRounds) " :invariants [" (stringTrim invStr) "] :explorations [" (stringTrim expStr) "] :criteria [" (stringTrim crtStr) "])"))
