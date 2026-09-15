(module aslBench/tierBudget
  :d "Budget measurement and evaluation of minimal and full instruction and rule tiers under ADR-0081."
  :x [TierBudgetResult
      TierSpec
      makeTierBudgetResult
      evaluateTierBudget
      checkSemanticPreservation
      isUnderBudget?
      runTests]
  :i [])

(dfs TierBudgetResult
  (:f tierId Str "Tier identifier: essential, affordance, full")
  (:f tokenCount I64 "Token count under pinned tokenizer")
  (:f byteCount I64 "Raw byte length")
  (:f ruleCount I64 "Number of rules included")
  (:f opCount I64 "Number of RPC operations included")
  (:f underBudget? Bool "True if within allocated budget")
  (:f mandatoryPreserved? Bool "True if all mandatory invariant rules and authority preserved")
  (:f maxMinimalTokens I64 "Pinned tokenizer maximum token budget")
  (:f overflowPolicy Str "Policy on budget exceedance"))

(dfs TierSpec
  (:f tierId Str "Tier name")
  (:f tokenBudget I64 "Maximum token allowance")
  (:f maxMinimalTokens I64 "Declared engineering target")
  (:f overflowPolicy Str "Overflow policy"))

(df makeTierBudgetResult [(tierId Str)
                             (tokenCount I64)
                             (byteCount I64)
                             (ruleCount I64)
                             (opCount I64)
                             (underBudget? Bool)
                             (mandatoryPreserved? Bool)
                             (maxMinimalTokens I64)
                             (overflowPolicy Str)] -> TierBudgetResult
  :d "Constructs verified TierBudgetResult record"
  (TierBudgetResult
    :tierId tierId
    :tokenCount tokenCount
    :byteCount byteCount
    :ruleCount ruleCount
    :opCount opCount
    :underBudget? underBudget?
    :mandatoryPreserved? mandatoryPreserved?
    :maxMinimalTokens maxMinimalTokens
    :overflowPolicy overflowPolicy))

(df isUnderBudget? [(tokenCount I64) (budget I64)] -> Bool
  :d "Checks if token count is within budget limit"
  (<= tokenCount budget))

(df checkSemanticPreservation [(hasSemantics Bool)
                                 (hasGates Bool)
                                 (hasGrading Bool)
                                 (hasConcepts Bool)
                                 (hasForeign Bool)
                                 (hasOneStep Bool)
                                 (hasHiddenTests Bool)] -> Bool
  :d "Verifies all 7 mandatory invariants are preserved without omissions"
  (and hasSemantics
       (and hasGates
            (and hasGrading
                 (and hasConcepts
                      (and hasForeign
                           (and hasOneStep hasHiddenTests)))))))

(df evaluateTierBudget [(tierId Str)
                          (tokenCount I64)
                          (byteCount I64)
                          (ruleCount I64)
                          (opCount I64)
                          (hasSemantics Bool)
                          (hasGates Bool)
                          (hasGrading Bool)
                          (hasConcepts Bool)
                          (hasForeign Bool)
                          (hasOneStep Bool)
                          (hasHiddenTests Bool)] -> TierBudgetResult
  :d "Evaluates tier payload token budget and semantic invariant preservation"
  (let [(maxTokens (if (= tierId "essential") 1000 8000))
        (under? (<= tokenCount maxTokens))
        (preserved? (checkSemanticPreservation hasSemantics
                                                hasGates
                                                hasGrading
                                                hasConcepts
                                                hasForeign
                                                hasOneStep
                                                hasHiddenTests))
        (policy (if under? "admit" "reject"))]
    (makeTierBudgetResult tierId
                             tokenCount
                             byteCount
                             ruleCount
                             opCount
                             under?
                             preserved?
                             maxTokens
                             policy)))

(:budgetSpecification
  :maxMinimalTokens 1000
  :overflowPolicy :reject
  :pinnedTokenizer "cl100k_base"
  :canonicalTiers [:essential :hot :affordance :orientation :heuristic :pack :full])

(df runTests [] -> Bool
  :d "Executes self-contained tier budget evaluation assertions"
  (let [(essentialRes (evaluateTierBudget "essential" 780 3524 7 11 true true true true true true true))]
    (assert (= (.-tierId essentialRes) "essential") "Tier ID must match")
    (assert (= (.-underBudget? essentialRes) true) "Essential tier must be under budget")
    (assert (= (.-mandatoryPreserved? essentialRes) true) "Invariants must be preserved")
    (assert (= (.-ruleCount essentialRes) 7) "Must have 7 invariant rules")
    (let [(overflowRes (evaluateTierBudget "essential" 1250 5800 7 11 true true true true true true true))]
      (assert (= (.-underBudget? overflowRes) false) "Overflow count must report not under budget")
      (assert (= (.-overflowPolicy overflowRes) "reject") "Overflow must trigger reject policy"))
    true))
