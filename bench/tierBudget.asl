(module aslBench/tierBudget :x [TierBudgetResult TierSpec makeTierBudgetResult evaluateTierBudget checkSemanticPreservation isUnderBudget? runTests] :i [])

(schema TierBudgetResult (:f tierId Str) (:f tokenCount I64) (:f byteCount I64) (:f ruleCount I64) (:f opCount I64) (:f underBudget? Bool) (:f mandatoryPreserved? Bool) (:f maxMinimalTokens I64) (:f overflowPolicy Str))

(schema TierSpec (:f tierId Str) (:f tokenBudget I64) (:f maxMinimalTokens I64) (:f overflowPolicy Str))

fn makeTierBudgetResult tierId: Str tokenCount: I64 byteCount: I64 ruleCount: I64 opCount: I64 underBudget?: Bool mandatoryPreserved?: Bool maxMinimalTokens: I64 overflowPolicy: Str -> TierBudgetResult
  (TierBudgetResult :tierId tierId :tokenCount tokenCount :byteCount byteCount :ruleCount ruleCount :opCount opCount :underBudget? underBudget? :mandatoryPreserved? mandatoryPreserved? :maxMinimalTokens maxMinimalTokens :overflowPolicy overflowPolicy)

fn isUnderBudget? tokenCount: I64 budget: I64 -> Bool
  (<= tokenCount budget)

fn checkSemanticPreservation hasSemantics: Bool hasGates: Bool hasGrading: Bool hasConcepts: Bool hasForeign: Bool hasOneStep: Bool hasHiddenTests: Bool -> Bool
  (and hasSemantics (and hasGates (and hasGrading (and hasConcepts (and hasForeign (and hasOneStep hasHiddenTests))))))

fn evaluateTierBudget tierId: Str tokenCount: I64 byteCount: I64 ruleCount: I64 opCount: I64 hasSemantics: Bool hasGates: Bool hasGrading: Bool hasConcepts: Bool hasForeign: Bool hasOneStep: Bool hasHiddenTests: Bool -> TierBudgetResult
  (let [(maxTokens (if (= tierId "essential") 1000 8000)) (under? (<= tokenCount maxTokens)) (preserved? (checkSemanticPreservation hasSemantics hasGates hasGrading hasConcepts hasForeign hasOneStep hasHiddenTests)) (policy (if under? "admit" "reject"))] (makeTierBudgetResult tierId tokenCount byteCount ruleCount opCount under? preserved? maxTokens policy))

(:budgetSpecification :maxMinimalTokens 1000 :overflowPolicy :reject :pinnedTokenizer "cl100k_base" :canonicalTiers [:essential :hot :affordance :orientation :heuristic :pack :full])

fn runTests -> Bool
  (let [(essentialRes (evaluateTierBudget "essential" 780 3524 7 11 true true true true true true true))] (assert (= essentialRes.tierId "essential") "Tier ID must match") (assert (= essentialRes.underBudget? true) "Essential tier must be under budget") (assert (= essentialRes.mandatoryPreserved? true) "Invariants must be preserved") (assert (= essentialRes.ruleCount 7) "Must have 7 invariant rules") (let [(overflowRes (evaluateTierBudget "essential" 1250 5800 7 11 true true true true true true true))] (assert (= overflowRes.underBudget? false) "Overflow count must report not under budget") (assert (= overflowRes.overflowPolicy "reject") "Overflow must trigger reject policy")) true)
