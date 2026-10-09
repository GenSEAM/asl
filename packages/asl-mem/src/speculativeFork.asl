(module aslMem/speculativeFork :x [SpeculativeMutant SpeculativeFuzzResult createSpeculativeMutant forkMutantCluster evaluateMutantSurvival summarizeFuzzRun])

(schema SpeculativeMutant (:f id Str) (:f mutationType Str) (:f targetSymbol Str) (:f mutatedContent Str) (:f survived Bool))

(schema SpeculativeFuzzResult (:f targetSymbol Str) (:f totalMutants I64) (:f killedMutants I64) (:f survivingMutants I64) (:f killRatePct I64))

fn createSpeculativeMutant id: Str mType: Str sym: Str mutated: Str -> SpeculativeMutant
  (SpeculativeMutant :id id :mutationType mType :targetSymbol sym :mutatedContent mutated :survived false)

fn forkMutantCluster baseContent: Str targetSym: Str -> (List SpeculativeMutant)
  (let [(m1Txt (if (stringContains? baseContent "(if ") (stringReplace baseContent "(if " "(if (not ") (str baseContent "\n;; mutant-invert-cond"))) (m2Txt (if (stringContains? baseContent "(assert ") (stringReplace baseContent "(assert " "(assert (not ") (str baseContent "\n;; mutant-negate-assert"))) (m3Txt (if (stringContains? baseContent " 0)") (stringReplace baseContent " 0)" " -1)") (if (stringContains? baseContent " 10)") (stringReplace baseContent " 10)" " 999)") (str baseContent "\n;; mutant-perturb-const")))) (mutant1 (createSpeculativeMutant (str targetSym "-mut-1") "invert-cond" targetSym m1Txt)) (mutant2 (createSpeculativeMutant (str targetSym "-mut-2") "negate-assert" targetSym m2Txt)) (mutant3 (createSpeculativeMutant (str targetSym "-mut-3") "perturb-const" targetSym m3Txt))] (list mutant1 mutant2 mutant3))

fn evaluateMutantSurvival mutant: SpeculativeMutant testPasses: Bool -> SpeculativeMutant
  (with mutant :survived testPasses)

fn summarizeFuzzRun targetSym: Str mutants: (List SpeculativeMutant) -> SpeculativeFuzzResult
  (let [(total (listLength mutants)) (survivedCount (fold (fn [(acc I64) (m SpeculativeMutant)] -> I64 (if m.survived (+ acc 1) acc)) 0 mutants)) (killedCount (- total survivedCount)) (killRate (if (<= total 0) 0 (/ (* killedCount 100) total)))] (SpeculativeFuzzResult :targetSymbol targetSym :totalMutants total :killedMutants killedCount :survivingMutants survivedCount :killRatePct killRate))
