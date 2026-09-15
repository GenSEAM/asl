(module aslBench/mutationProposerLoop
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
  (:f targetSymbol Str "Target symbol whose mutant survived")
  (:f targetMutant Str "Target surviving mutant identifier")
  (:f caseSource Str "Proposed ASL test code")
  (:f targetPath Str "Proposed file path destination"))

(dfs ProposalEvaluation
  (:f caseId Str "Proposed case identifier")
  (:f targetMutant Str "Target surviving mutant identifier")
  (:f killsMutant? Bool "True if case kills previously surviving mutant")
  (:f nonVacuous? Bool "True if case passes non-vacuity assertion inversion check")
  (:f isDuplicate? Bool "True if case duplicates an existing test")
  (:f modifiesExistingAssert? Bool "True if attempt to edit existing assertions")
  (:f targetsGraderPath? Bool "True if targeting grader-owned acceptance path")
  (:f disposition Str "Outcome: kept, discarded, refused")
  (:f refusalReason Str "Written justification for refusal or discard"))

(dfs ProposerSessionReport
  (:f package Str "Target package name")
  (:f budgetTokens I64 "Token budget allocated for proposal loop")
  (:f tokensConsumed I64 "Actual tokens consumed in session")
  (:f costUsd Str "Calculated dollar cost formatted string")
  (:f proposedCount I64 "Total candidates proposed by LLM")
  (:f keptCount I64 "Candidates kept (killed mutant and non-vacuous)")
  (:f discardedCount I64 "Candidates discarded (non-killing, duplicate, vacuous)")
  (:f refusedCount I64 "Candidates refused by ownership enforcement"))

(df EvaluateProposedCase [(c ProposedCase)
                          (killsMutant? Bool)
                          (nonVacuous? Bool)
                          (isDuplicate? Bool)
                          (modifiesExisting? Bool)
                          (targetsGrader? Bool)] -> ProposalEvaluation
  :d "Evaluates candidate case; model never decides pass or fail, never edits existing assertions, and never writes to grader-owned acceptance paths"
  (if targetsGrader?
      (ProposalEvaluation
        :caseId (.-id c)
        :targetMutant (.-targetMutant c)
        :killsMutant? killsMutant?
        :nonVacuous? nonVacuous?
        :isDuplicate? isDuplicate?
        :modifiesExistingAssert? modifiesExisting?
        :targetsGraderPath? targetsGrader?
        :disposition "refused"
        :refusalReason "Grader-owned path modification prohibited by ownership enforcement")
      (if modifiesExisting?
          (ProposalEvaluation
            :caseId (.-id c)
            :targetMutant (.-targetMutant c)
            :killsMutant? killsMutant?
            :nonVacuous? nonVacuous?
            :isDuplicate? isDuplicate?
            :modifiesExistingAssert? modifiesExisting?
            :targetsGraderPath? targetsGrader?
            :disposition "refused"
            :refusalReason "Editing existing assertions prohibited by ownership enforcement")
          (if isDuplicate?
              (ProposalEvaluation
                :caseId (.-id c)
                :targetMutant (.-targetMutant c)
                :killsMutant? killsMutant?
                :nonVacuous? nonVacuous?
                :isDuplicate? isDuplicate?
                :modifiesExistingAssert? modifiesExisting?
                :targetsGraderPath? targetsGrader?
                :disposition "discarded"
                :refusalReason "Duplicate proposed case discarded")
              (if (and killsMutant? nonVacuous?)
                  (ProposalEvaluation
                    :caseId (.-id c)
                    :targetMutant (.-targetMutant c)
                    :killsMutant? killsMutant?
                    :nonVacuous? nonVacuous?
                    :isDuplicate? isDuplicate?
                    :modifiesExistingAssert? modifiesExisting?
                    :targetsGraderPath? targetsGrader?
                    :disposition "kept"
                    :refusalReason "")
                  (ProposalEvaluation
                    :caseId (.-id c)
                    :targetMutant (.-targetMutant c)
                    :killsMutant? killsMutant?
                    :nonVacuous? nonVacuous?
                    :isDuplicate? isDuplicate?
                    :modifiesExistingAssert? modifiesExisting?
                    :targetsGraderPath? targetsGrader?
                    :disposition "discarded"
                    :refusalReason "Proposed case passes without killing target mutant or fails non-vacuity check"))))))

(df CalculateProposerCost [(tokensConsumed I64) (ratePerMillion I64)] -> Str
  :d "Calculates dollar cost of tokens consumed during LLM proposal loop"
  (let [(cents (/ (* tokensConsumed ratePerMillion) 10000))]
    (let [(dollars (/ cents 100))
          (c (mod cents 100))]
      (let [(cStr (if (< c 10) (strConcat "0" (str c)) (str c)))]
        (strConcat (strConcat (strConcat "$" (str dollars)) ".") cStr)))))

(df RunTests [] -> Bool
  :d "Executes internal verification tests for mutation proposer feedback loop"
  (let [(c1 (ProposedCase :id "p1" :targetSymbol "eval-add" :targetMutant "mut-01" :caseSource "(assert (= (eval-add 2 3) 5))" :targetPath "tests/conformance/eval_test.asl"))
        (c2 (ProposedCase :id "p2" :targetSymbol "eval-add" :targetMutant "mut-01" :caseSource "(assert true)" :targetPath "tests/conformance/eval_test.asl"))
        (cGrader (ProposedCase :id "p3" :targetSymbol "assert-equal" :targetMutant "mut-02" :caseSource "(assert false)" :targetPath "tests/acceptance/d81/Task44406.asl"))
        (cMod (ProposedCase :id "p4" :targetSymbol "assert-equal" :targetMutant "mut-02" :caseSource "(assert true)" :targetPath "asl/packages/asl-gates/tests/gates_test.asl"))]
    (let [(evalKept (EvaluateProposedCase c1 true true false false false))
          (evalNokill (EvaluateProposedCase c2 false true false false false))
          (evalDup (EvaluateProposedCase c1 true true true false false))
          (evalGrader (EvaluateProposedCase cGrader true true false false true))
          (evalMod (EvaluateProposedCase cMod true true false true false))]
      (assert (= (.-disposition evalKept) "kept") "Case killing mutant and non-vacuous must be kept")
      (assert (= (.-disposition evalNokill) "discarded") "Case passing without killing mutant must be discarded")
      (assert (= (.-disposition evalDup) "discarded") "Duplicate case must be discarded")
      (assert (= (.-disposition evalGrader) "refused") "Attempt to write to grader path must be refused")
      (assert (= (.-disposition evalMod) "refused") "Attempt to edit existing assertions must be refused")
      (let [(cost (CalculateProposerCost 50000 3))]
        (assert (= cost "$0.15") "Must compute token cost string")
        true))))
