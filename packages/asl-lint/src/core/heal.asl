(module asl-lint/heal
  :d "AgentScript native autonomous repair rules, AST patch recipes, and auto-fixer."
  :x [FixType PatchAction FixResult
           canAutoRepair isFixSuccessful formatFixDescription])

(dfe FixType
  (:c addPrefixUnused          [] "Prefix unused variable with underscore to satisfy linter")
  (:c exportMissingSchemaType [] "Automatically export type referenced in exported schema (Rule 13)")
  (:c mergeDuplicateArms       [] "Consolidate duplicate pattern match arm bodies")
  (:c canonicalizeFormatting    [] "Standardize S-expression indentation and parenthesis balance"))

(dfs PatchAction
  (:f fixType FixType "Classification of the auto-repair applied")
  (:f file String "Path to target ASL source file")
  (:f line Int64 "1-indexed line where patch is applied")
  (:f targetText String "Original code snippet being replaced")
  (:f replacementText String "Canonical repaired replacement snippet")
  (:f applied Bool "True if patch was written to disk"))

(dfs FixResult
  (:f totalFixes Int64 "Total candidate patches identified")
  (:f appliedFixes Int64 "Total patches successfully applied")
  (:f newQualityScore Int64 "Quality score post-repair (0 to 100)"))

(df canAutoRepair [(ft FixType)] -> Bool
  :d "Returns true if this fix type is safe for non-destructive automated repair."
  (mt ft
    ((addPrefixUnused)          true)
    ((exportMissingSchemaType) true)
    ((mergeDuplicateArms)       true)
    ((canonicalizeFormatting)    true)))

(df isFixSuccessful [(res FixResult)] -> Bool
  :d "Returns true if all identified patches were applied and score meets quality gate."
  (if (= (.-totalFixes res) (.-appliedFixes res))
    (>= (.-newQualityScore res) 70)
    false))

(df formatFixDescription [(ft FixType)] -> String
  :d "Human-readable description of automated repair action."
  (mt ft
    ((addPrefixUnused)          "Prefixed unused binder with '_'")
    ((exportMissingSchemaType) "Appended referenced type to module :export declaration")
    ((mergeDuplicateArms)       "Merged redundant pattern match arms")
    ((canonicalizeFormatting)    "Canonicalized S-expression indentation")))
