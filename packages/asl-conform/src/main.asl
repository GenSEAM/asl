(module aslConform/main :x [loadTargetSemantics runConformCase! applyMutant runIsolatedMutantTrial! conformReceipt invertComparison runConform! validateRuleMutants] :i [(aslConform/types :a ty) (aslConform/semantics :a sem) (aslConform/compare :a cmp) (aslConform/mutant :a mut) (aslConform/runner :a run)])

fn loadTargetSemantics -> ty/TargetSemanticsContract
  (sem/loadTargetSemantics)

fn runConformCase! casePath: Str profileId: Str invert: Bool -> ty/ConformanceResult
  (run/runConformCase! casePath profileId invert)

fn applyMutant m: ty/SemanticsMutant code: Str -> Str
  (mut/applyMutant m code)

fn runIsolatedMutantTrial! m: ty/SemanticsMutant casePath: Str -> ty/ConformanceResult
  (mut/runIsolatedMutantTrial! m casePath)

fn conformReceipt receipt: ty/ConformReceipt -> Str
  (run/formatReceipt receipt)

fn invertComparison actOut: Str actExit: I64 expOut: Str expExit: I64 -> Bool
  (cmp/invertComparison actOut actExit expOut expExit)

fn validateRuleMutants contract: ty/TargetSemanticsContract -> Bool
  (listAll? (fn [(r ty/SemanticsRule)] -> Bool (sem/ruleHasMutants? r)) (sem/getAllRules contract))

fn runConform! profileId: Str ruleFilter: Str invert: Bool -> (Result Str Str)
  (let [(contract (loadTargetSemantics))] (if (not (validateRuleMutants contract)) (err "Conformance harness error: one or more rules lack mandatory refutation mutants") (let [(receipt (run/runConformProfile! profileId ruleFilter invert))] (if (> receipt.failedCases 0) (err (str (run/formatReceipt receipt) "\nFailed cases: " (stringFromInt64 receipt.failedCases))) (ok (run/formatReceipt receipt))))))
