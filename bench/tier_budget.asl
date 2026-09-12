(module asl-bench/tier-budget
  :d "Budget measurement and evaluation of minimal and full instruction and rule tiers under ADR-0081."
  :x [TierBudgetResult
      TierSpec
      make-tier-budget-result
      evaluate-tier-budget
      check-semantic-preservation
      is-under-budget?
      run-tests]
  :i [])

(dfs TierBudgetResult
  (:f tier-id Str "Tier identifier: essential, affordance, full")
  (:f token-count I64 "Token count under pinned tokenizer")
  (:f byte-count I64 "Raw byte length")
  (:f rule-count I64 "Number of rules included")
  (:f op-count I64 "Number of RPC operations included")
  (:f under-budget? Bool "True if within allocated budget")
  (:f mandatory-preserved? Bool "True if all mandatory invariant rules and authority preserved")
  (:f max-minimal-tokens I64 "Pinned tokenizer maximum token budget")
  (:f overflow-policy Str "Policy on budget exceedance"))

(dfs TierSpec
  (:f tier-id Str "Tier name")
  (:f token-budget I64 "Maximum token allowance")
  (:f max-minimal-tokens I64 "Declared engineering target")
  (:f overflow-policy Str "Overflow policy"))

(df make-tier-budget-result [(tier-id Str)
                             (token-count I64)
                             (byte-count I64)
                             (rule-count I64)
                             (op-count I64)
                             (under-budget? Bool)
                             (mandatory-preserved? Bool)
                             (max-minimal-tokens I64)
                             (overflow-policy Str)] -> TierBudgetResult
  :d "Constructs verified TierBudgetResult record"
  (TierBudgetResult
    :tier-id tier-id
    :token-count token-count
    :byte-count byte-count
    :rule-count rule-count
    :op-count op-count
    :under-budget? under-budget?
    :mandatory-preserved? mandatory-preserved?
    :max-minimal-tokens max-minimal-tokens
    :overflow-policy overflow-policy))

(df is-under-budget? [(token-count I64) (budget I64)] -> Bool
  :d "Checks if token count is within budget limit"
  (<= token-count budget))

(df check-semantic-preservation [(has-semantics Bool)
                                 (has-gates Bool)
                                 (has-grading Bool)
                                 (has-concepts Bool)
                                 (has-foreign Bool)
                                 (has-one-step Bool)
                                 (has-hidden-tests Bool)] -> Bool
  :d "Verifies all 7 mandatory invariants are preserved without omissions"
  (and has-semantics
       (and has-gates
            (and has-grading
                 (and has-concepts
                      (and has-foreign
                           (and has-one-step has-hidden-tests)))))))

(df evaluate-tier-budget [(tier-id Str)
                          (token-count I64)
                          (byte-count I64)
                          (rule-count I64)
                          (op-count I64)
                          (has-semantics Bool)
                          (has-gates Bool)
                          (has-grading Bool)
                          (has-concepts Bool)
                          (has-foreign Bool)
                          (has-one-step Bool)
                          (has-hidden-tests Bool)] -> TierBudgetResult
  :d "Evaluates tier payload token budget and semantic invariant preservation"
  (let [(max-tokens (if (= tier-id "essential") 1000 8000))
        (under? (<= token-count max-tokens))
        (preserved? (check-semantic-preservation has-semantics
                                                has-gates
                                                has-grading
                                                has-concepts
                                                has-foreign
                                                has-one-step
                                                has-hidden-tests))
        (policy (if under? "admit" "reject"))]
    (make-tier-budget-result tier-id
                             token-count
                             byte-count
                             rule-count
                             op-count
                             under?
                             preserved?
                             max-tokens
                             policy)))

(:budgetSpecification
  :max-minimal-tokens 1000
  :overflow-policy :reject
  :pinned-tokenizer "cl100k_base"
  :canonical-tiers [:essential :hot :affordance :orientation :heuristic :pack :full])

(df run-tests [] -> Bool
  :d "Executes self-contained tier budget evaluation assertions"
  (let [(essential-res (evaluate-tier-budget "essential" 780 3524 7 11 true true true true true true true))]
    (assert (= (.-tier-id essential-res) "essential") "Tier ID must match")
    (assert (= (.-under-budget? essential-res) true) "Essential tier must be under budget")
    (assert (= (.-mandatory-preserved? essential-res) true) "Invariants must be preserved")
    (assert (= (.-rule-count essential-res) 7) "Must have 7 invariant rules")
    (let [(overflow-res (evaluate-tier-budget "essential" 1250 5800 7 11 true true true true true true true))]
      (assert (= (.-under-budget? overflow-res) false) "Overflow count must report not under budget")
      (assert (= (.-overflow-policy overflow-res) "reject") "Overflow must trigger reject policy"))
    true))
