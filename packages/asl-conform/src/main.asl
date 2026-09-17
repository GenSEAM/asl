(module aslConform/main
  :d "Top-level API for AgentScript cross-platform target conformance harness"
  :x [loadTargetSemantics
      runConformCase
      applyMutant
      runIsolatedMutantTrial
      conformReceipt
      invertComparison
      runConform
      validateRuleMutants]
  :i [(aslConform/types :a ty)
      (aslConform/semantics :a sem)
      (aslConform/compare :a cmp)
      (aslConform/mutant :a mut)
      (aslConform/runner :a run)])

(df loadTargetSemantics [] -> ty/TargetSemanticsContract
  :d "Loads the canonical TargetSemanticsContract."
  (sem/loadTargetSemantics))

(df runConformCase [(casePath Str) (profileId Str) (invert Bool)] -> ty/ConformanceResult
  :d "Executes a single test case for a designated target profile."
  (run/runConformCase casePath profileId invert))

(df applyMutant [(m ty/SemanticsMutant) (code Str)] -> Str
  :d "Applies a code mutant."
  (mut/applyMutant m code))

(df runIsolatedMutantTrial [(m ty/SemanticsMutant) (casePath Str)] -> ty/ConformanceResult
  :d "Runs a mutant execution trial in an isolated workspace."
  (mut/runIsolatedMutantTrial m casePath))

(df conformReceipt [(receipt ty/ConformReceipt)] -> Str
  :d "Formats a ConformReceipt into ASN text."
  (run/formatReceipt receipt))

(df invertComparison [(actOut Str) (actExit I64) (expOut Str) (expExit I64)] -> Bool
  :d "Inverts output and exit code comparison."
  (cmp/invertComparison actOut actExit expOut expExit))

(df validateRuleMutants [(contract ty/TargetSemanticsContract)] -> Bool
  :d "Verifies that every rule in the contract carries at least one mandatory mutant."
  (all (fn [(r ty/SemanticsRule)] -> Bool (sem/ruleHasMutants? r))
       (sem/getAllRules contract)))

(df runConform [(profileId Str) (ruleFilter Str) (invert Bool)] -> (Result Str Str)
  :d "Executes conformance suite and returns formatted receipt or error."
  (let [(contract (loadTargetSemantics))]
    (if (not (validateRuleMutants contract))
        (err "Conformance harness error: one or more rules lack mandatory refutation mutants")
        (let [(receipt (run/runConformProfile profileId ruleFilter invert))]
          (if (> (.-failedCases receipt) 0)
              (err (str (run/formatReceipt receipt) "\nFailed cases: " (string-from-int64 (.-failedCases receipt))))
              (ok (run/formatReceipt receipt)))))))
