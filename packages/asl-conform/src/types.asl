(module aslConform/types :x [TargetProfile SemanticsMutant SemanticsRule TargetSemanticsContract ConformanceCase ConformanceResult ConformReceipt makeProfile makeMutant makeRule makeContract makeCase makeResult makeReceipt])

(schema TargetProfile (:f id Str) (:f name Str) (:f compiler Str) (:f tier Str))

(schema SemanticsMutant (:f id Str) (:f target Str) (:f desc Str) (:f kills Str))

(schema SemanticsRule (:f id Str) (:f tier Str) (:f name Str) (:f summary Str) (:f cases (List Str)) (:f mutants (List SemanticsMutant)))

(schema TargetSemanticsContract (:f version I64) (:f profiles (List TargetProfile)) (:f tiers (List Str)) (:f rules (List SemanticsRule)))

(schema ConformanceCase (:f id Str) (:f rule Str) (:f tier Str) (:f oracle Str) (:f srcPath Str) (:f expectStdout Str) (:f expectExit I64))

(schema ConformanceResult (:f caseId Str) (:f profile Str) (:f passed Bool) (:f actualStdout Str) (:f actualExit I64) (:f reason Str))

(schema ConformReceipt (:f profile Str) (:f totalCases I64) (:f passedCases I64) (:f failedCases I64) (:f results (List ConformanceResult)) (:f mutantsChecked (List Str)) (:f invertedReachable Bool))

fn makeProfile id: Str name: Str compiler: Str tier: Str -> TargetProfile
  (TargetProfile :id id :name name :compiler compiler :tier tier)

fn makeMutant id: Str target: Str desc: Str kills: Str -> SemanticsMutant
  (SemanticsMutant :id id :target target :desc desc :kills kills)

fn makeRule id: Str tier: Str name: Str summary: Str cases: (List Str) mutants: (List SemanticsMutant) -> SemanticsRule
  (SemanticsRule :id id :tier tier :name name :summary summary :cases cases :mutants mutants)

fn makeContract version: I64 profiles: (List TargetProfile) tiers: (List Str) rules: (List SemanticsRule) -> TargetSemanticsContract
  (TargetSemanticsContract :version version :profiles profiles :tiers tiers :rules rules)

fn makeCase id: Str rule: Str tier: Str oracle: Str srcPath: Str expectStdout: Str expectExit: I64 -> ConformanceCase
  (ConformanceCase :id id :rule rule :tier tier :oracle oracle :srcPath srcPath :expectStdout expectStdout :expectExit expectExit)

fn makeResult caseId: Str profile: Str passed: Bool actualStdout: Str actualExit: I64 reason: Str -> ConformanceResult
  (ConformanceResult :caseId caseId :profile profile :passed passed :actualStdout actualStdout :actualExit actualExit :reason reason)

fn makeReceipt profile: Str totalCases: I64 passedCases: I64 failedCases: I64 results: (List ConformanceResult) mutantsChecked: (List Str) invertedReachable: Bool -> ConformReceipt
  (ConformReceipt :profile profile :totalCases totalCases :passedCases passedCases :failedCases failedCases :results results :mutantsChecked mutantsChecked :invertedReachable invertedReachable)
