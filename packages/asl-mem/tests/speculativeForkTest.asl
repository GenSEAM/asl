(module aslMem/tests/speculativeForkTest :x [runTests TestMutantClusterCreation TestMutantSurvivalEvaluation TestFuzzSummaryComputation] :i [(speculativeFork :a sf)])

fn TestMutantClusterCreation -> Bool
  (let [(code "(fn calculate [(x I64)] -> I64 (if (> x 0) (assert (= x x)) 10))") (cluster (sf/forkMutantCluster code "calculate"))] (assert (= (listLength cluster) 3) "Cluster must contain exactly 3 mutants") (let [(m1 (optionOr (listGet cluster 0) (sf/SpeculativeMutant :id "" :mutationType "" :targetSymbol "" :mutatedContent "" :survived false))) (m2 (optionOr (listGet cluster 1) (sf/SpeculativeMutant :id "" :mutationType "" :targetSymbol "" :mutatedContent "" :survived false))) (m3 (optionOr (listGet cluster 2) (sf/SpeculativeMutant :id "" :mutationType "" :targetSymbol "" :mutatedContent "" :survived false)))] (assert (= m1.mutationType "invert-cond") "Mutant 1 must be invert-cond") (assert (= m2.mutationType "negate-assert") "Mutant 2 must be negate-assert") (assert (= m3.mutationType "perturb-const") "Mutant 3 must be perturb-const") (assert (stringContains? m1.mutatedContent "(if (not ") "Mutant 1 must invert condition") (assert (stringContains? m2.mutatedContent "(assert (not ") "Mutant 2 must negate assert") (assert (stringContains? m3.mutatedContent " -1)") "Mutant 3 must perturb zero constant")) true)

fn TestMutantSurvivalEvaluation -> Bool
  (let [(m (sf/createSpeculativeMutant "mut-1" "invert-cond" "fn1" "code")) (killed (sf/evaluateMutantSurvival m false)) (survived (sf/evaluateMutantSurvival m true))] (assert (not killed.survived) "Failing test suite must kill mutant") (assert survived.survived "Passing test suite on mutant indicates mutant survived") true)

fn TestFuzzSummaryComputation -> Bool
  (let [(m1 (sf/createSpeculativeMutant "m1" "t1" "f1" "c1")) (m2 (sf/createSpeculativeMutant "m2" "t2" "f1" "c2")) (eval1 (sf/evaluateMutantSurvival m1 false)) (eval2 (sf/evaluateMutantSurvival m2 true)) (summary (sf/summarizeFuzzRun "f1" (list eval1 eval2)))] (assert (= summary.totalMutants 2) "Total mutants must be 2") (assert (= summary.killedMutants 1) "Killed mutants must be 1") (assert (= summary.survivingMutants 1) "Surviving mutants must be 1") (assert (= summary.killRatePct 50) "Kill rate must be 50%") true)

fn runTests -> Bool
  (and (TestMutantClusterCreation) (and (TestMutantSurvivalEvaluation) (TestFuzzSummaryComputation)))
