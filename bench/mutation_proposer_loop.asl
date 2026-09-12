(module asl-bench/mutation-proposer-loop
  :d "LLM test case proposal inside a mutation feedback loop with ownership defense and non-vacuity enforcement under ADR-0081."
  :x [ProposedCase
      ProposalEvaluation
      ProposerSessionReport
      EvaluateProposedCase
      CalculateProposerCost
      RunTests]
  :i [])

(dfs ProposedCase
  (:f id Str "Proposed case identifier")
  (:f target-symbol Str "Target symbol whose mutant survived")
  (:f target-mutant Str "Target surviving mutant identifier")
  (:f case-source Str "Proposed ASL test code")
  (:f target-path Str "Proposed file path destination"))

(dfs ProposalEvaluation
  (:f case-id Str "Proposed case identifier")
  (:f target-mutant Str "Target surviving mutant identifier")
  (:f kills-mutant? Bool "True if case kills previously surviving mutant")
  (:f non-vacuous? Bool "True if case passes non-vacuity assertion inversion check")
  (:f is-duplicate? Bool "True if case duplicates an existing test")
  (:f modifies-existing-assert? Bool "True if attempt to edit existing assertions")
  (:f targets-grader-path? Bool "True if targeting grader-owned acceptance path")
  (:f disposition Str "Outcome: kept, discarded, refused")
  (:f refusal-reason Str "Written justification for refusal or discard"))

(dfs ProposerSessionReport
  (:f package Str "Target package name")
  (:f budget-tokens I64 "Token budget allocated for proposal loop")
  (:f tokens-consumed I64 "Actual tokens consumed in session")
  (:f cost-usd Str "Calculated dollar cost formatted string")
  (:f proposed-count I64 "Total candidates proposed by LLM")
  (:f kept-count I64 "Candidates kept (killed mutant and non-vacuous)")
  (:f discarded-count I64 "Candidates discarded (non-killing, duplicate, vacuous)")
  (:f refused-count I64 "Candidates refused by ownership enforcement"))

(df EvaluateProposedCase [(c ProposedCase)
                          (kills-mutant? Bool)
                          (non-vacuous? Bool)
                          (is-duplicate? Bool)
                          (modifies-existing? Bool)
                          (targets-grader? Bool)] -> ProposalEvaluation
  :d "Evaluates candidate case; model never decides pass or fail, never edits existing assertions, and never writes to grader-owned acceptance paths"
  (if targets-grader?
      (ProposalEvaluation
        :case-id (.-id c)
        :target-mutant (.-target-mutant c)
        :kills-mutant? kills-mutant?
        :non-vacuous? non-vacuous?
        :is-duplicate? is-duplicate?
        :modifies-existing-assert? modifies-existing?
        :targets-grader-path? targets-grader?
        :disposition "refused"
        :refusal-reason "Grader-owned path modification prohibited by ownership enforcement")
      (if modifies-existing?
          (ProposalEvaluation
            :case-id (.-id c)
            :target-mutant (.-target-mutant c)
            :kills-mutant? kills-mutant?
            :non-vacuous? non-vacuous?
            :is-duplicate? is-duplicate?
            :modifies-existing-assert? modifies-existing?
            :targets-grader-path? targets-grader?
            :disposition "refused"
            :refusal-reason "Editing existing assertions prohibited by ownership enforcement")
          (if is-duplicate?
              (ProposalEvaluation
                :case-id (.-id c)
                :target-mutant (.-target-mutant c)
                :kills-mutant? kills-mutant?
                :non-vacuous? non-vacuous?
                :is-duplicate? is-duplicate?
                :modifies-existing-assert? modifies-existing?
                :targets-grader-path? targets-grader?
                :disposition "discarded"
                :refusal-reason "Duplicate proposed case discarded")
              (if (and kills-mutant? non-vacuous?)
                  (ProposalEvaluation
                    :case-id (.-id c)
                    :target-mutant (.-target-mutant c)
                    :kills-mutant? kills-mutant?
                    :non-vacuous? non-vacuous?
                    :is-duplicate? is-duplicate?
                    :modifies-existing-assert? modifies-existing?
                    :targets-grader-path? targets-grader?
                    :disposition "kept"
                    :refusal-reason "")
                  (ProposalEvaluation
                    :case-id (.-id c)
                    :target-mutant (.-target-mutant c)
                    :kills-mutant? kills-mutant?
                    :non-vacuous? non-vacuous?
                    :is-duplicate? is-duplicate?
                    :modifies-existing-assert? modifies-existing?
                    :targets-grader-path? targets-grader?
                    :disposition "discarded"
                    :refusal-reason "Proposed case passes without killing target mutant or fails non-vacuity check"))))))

(df CalculateProposerCost [(tokens-consumed I64) (rate-per-million I64)] -> Str
  :d "Calculates dollar cost of tokens consumed during LLM proposal loop"
  (let [(cents (/ (* tokens-consumed rate-per-million) 10000))]
    (let [(dollars (/ cents 100))
          (c (mod cents 100))]
      (let [(c-str (if (< c 10) (str-concat "0" (str c)) (str c)))]
        (str-concat (str-concat (str-concat "$" (str dollars)) ".") c-str)))))

(df RunTests [] -> Bool
  :d "Executes internal verification tests for mutation proposer feedback loop"
  (let [(c1 (ProposedCase :id "p1" :target-symbol "eval-add" :target-mutant "mut-01" :case-source "(assert (= (eval-add 2 3) 5))" :target-path "tests/conformance/eval_test.asl"))
        (c2 (ProposedCase :id "p2" :target-symbol "eval-add" :target-mutant "mut-01" :case-source "(assert true)" :target-path "tests/conformance/eval_test.asl"))
        (c-grader (ProposedCase :id "p3" :target-symbol "assert-equal" :target-mutant "mut-02" :case-source "(assert false)" :target-path "tests/acceptance/d81/Task44406.asl"))
        (c-mod (ProposedCase :id "p4" :target-symbol "assert-equal" :target-mutant "mut-02" :case-source "(assert true)" :target-path "asl/packages/asl-gates/tests/gates_test.asl"))]
    (let [(eval-kept (EvaluateProposedCase c1 true true false false false))
          (eval-nokill (EvaluateProposedCase c2 false true false false false))
          (eval-dup (EvaluateProposedCase c1 true true true false false))
          (eval-grader (EvaluateProposedCase c-grader true true false false true))
          (eval-mod (EvaluateProposedCase c-mod true true false true false))]
      (assert (= (.-disposition eval-kept) "kept") "Case killing mutant and non-vacuous must be kept")
      (assert (= (.-disposition eval-nokill) "discarded") "Case passing without killing mutant must be discarded")
      (assert (= (.-disposition eval-dup) "discarded") "Duplicate case must be discarded")
      (assert (= (.-disposition eval-grader) "refused") "Attempt to write to grader path must be refused")
      (assert (= (.-disposition eval-mod) "refused") "Attempt to edit existing assertions must be refused")
      (let [(cost (CalculateProposerCost 50000 3))]
        (assert (= cost "$0.15") "Must compute token cost string")
        true))))
