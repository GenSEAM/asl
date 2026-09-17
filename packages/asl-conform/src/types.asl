(module aslConform/types
  :d "Pure AgentScript record definitions for target semantics conformance"
  :x [TargetProfile
      SemanticsMutant
      SemanticsRule
      TargetSemanticsContract
      ConformanceCase
      ConformanceResult
      ConformReceipt
      makeProfile
      makeMutant
      makeRule
      makeContract
      makeCase
      makeResult
      makeReceipt])

(dfs TargetProfile
  (:f id Str "Profile identifier")
  (:f name Str "Human readable profile name")
  (:f compiler Str "Compilation command")
  (:f tier Str "Target maturity tier"))

(dfs SemanticsMutant
  (:f id Str "Unique mutant identifier")
  (:f target Str "Target package mutated")
  (:f desc Str "Description of mutation defect")
  (:f kills Str "Case ID killed by mutant"))

(dfs SemanticsRule
  (:f id Str "Rule identifier")
  (:f tier Str "Rule maturity tier")
  (:f name Str "Rule name")
  (:f summary Str "Semantic specification summary")
  (:f cases (List Str) "List of case directory paths")
  (:f mutants (List SemanticsMutant) "List of mandatory refutation mutants"))

(dfs TargetSemanticsContract
  (:f version I64 "Contract schema version")
  (:f profiles (List TargetProfile) "Configured execution target profiles")
  (:f tiers (List Str) "Configured maturity tiers")
  (:f rules (List SemanticsRule) "Declared target semantics rules"))

(dfs ConformanceCase
  (:f id Str "Case unique identifier")
  (:f rule Str "Target rule identifier")
  (:f tier Str "Maturity tier")
  (:f oracle Str "Provenance oracle")
  (:f srcPath Str "Relative path to case.asl")
  (:f expectStdout Str "Expected standard output")
  (:f expectExit I64 "Expected exit code"))

(dfs ConformanceResult
  (:f caseId Str "Evaluated case identifier")
  (:f profile Str "Target profile")
  (:f passed Bool "Pass status")
  (:f actualStdout Str "Observed standard output")
  (:f actualExit I64 "Observed exit code")
  (:f reason Str "Failure description"))

(dfs ConformReceipt
  (:f profile Str "Target profile evaluated")
  (:f totalCases I64 "Total cases executed")
  (:f passedCases I64 "Cases passed")
  (:f failedCases I64 "Cases failed")
  (:f results (List ConformanceResult) "Detailed results")
  (:f mutantsChecked (List Str) "Mutant IDs verified")
  (:f invertedReachable Bool "Status of inverted polarity test"))

(df makeProfile [(id Str) (name Str) (compiler Str) (tier Str)] -> TargetProfile
  :d "Constructs a TargetProfile record."
  (TargetProfile :id id :name name :compiler compiler :tier tier))

(df makeMutant [(id Str) (target Str) (desc Str) (kills Str)] -> SemanticsMutant
  :d "Constructs a SemanticsMutant record."
  (SemanticsMutant :id id :target target :desc desc :kills kills))

(df makeRule [(id Str) (tier Str) (name Str) (summary Str) (cases (List Str)) (mutants (List SemanticsMutant))] -> SemanticsRule
  :d "Constructs a SemanticsRule record."
  (SemanticsRule :id id :tier tier :name name :summary summary :cases cases :mutants mutants))

(df makeContract [(version I64) (profiles (List TargetProfile)) (tiers (List Str)) (rules (List SemanticsRule))] -> TargetSemanticsContract
  :d "Constructs a TargetSemanticsContract record."
  (TargetSemanticsContract :version version :profiles profiles :tiers tiers :rules rules))

(df makeCase [(id Str) (rule Str) (tier Str) (oracle Str) (srcPath Str) (expectStdout Str) (expectExit I64)] -> ConformanceCase
  :d "Constructs a ConformanceCase record."
  (ConformanceCase :id id :rule rule :tier tier :oracle oracle :srcPath srcPath :expectStdout expectStdout :expectExit expectExit))

(df makeResult [(caseId Str) (profile Str) (passed Bool) (actualStdout Str) (actualExit I64) (reason Str)] -> ConformanceResult
  :d "Constructs a ConformanceResult record."
  (ConformanceResult :caseId caseId :profile profile :passed passed :actualStdout actualStdout :actualExit actualExit :reason reason))

(df makeReceipt [(profile Str) (totalCases I64) (passedCases I64) (failedCases I64) (results (List ConformanceResult)) (mutantsChecked (List Str)) (invertedReachable Bool)] -> ConformReceipt
  :d "Constructs a ConformReceipt record."
  (ConformReceipt :profile profile :totalCases totalCases :passedCases passedCases :failedCases failedCases :results results :mutantsChecked mutantsChecked :invertedReachable invertedReachable))
