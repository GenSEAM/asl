(module asl-lint/heal
  :d "AgentScript native autonomous repair rules, AST patch recipes, and auto-fixer."
  :x [FixType PatchAction FixResult
           can-auto-repair is-fix-successful format-fix-description])

(dfe FixType
  (:c add-prefix-unused          [] "Prefix unused variable with underscore to satisfy linter")
  (:c export-missing-schema-type [] "Automatically export type referenced in exported schema (Rule 13)")
  (:c merge-duplicate-arms       [] "Consolidate duplicate pattern match arm bodies")
  (:c canonicalize-formatting    [] "Standardize S-expression indentation and parenthesis balance"))

(dfs PatchAction
  (:f fix-type FixType "Classification of the auto-repair applied")
  (:f file String "Path to target ASL source file")
  (:f line Int64 "1-indexed line where patch is applied")
  (:f target-text String "Original code snippet being replaced")
  (:f replacement-text String "Canonical repaired replacement snippet")
  (:f applied Bool "True if patch was written to disk"))

(dfs FixResult
  (:f total-fixes Int64 "Total candidate patches identified")
  (:f applied-fixes Int64 "Total patches successfully applied")
  (:f new-quality-score Int64 "Quality score post-repair (0 to 100)"))

(df can-auto-repair [(ft FixType)] -> Bool
  :d "Returns true if this fix type is safe for non-destructive automated repair."
  (mt ft
    ((add-prefix-unused)          true)
    ((export-missing-schema-type) true)
    ((merge-duplicate-arms)       true)
    ((canonicalize-formatting)    true)))

(df is-fix-successful [(res FixResult)] -> Bool
  :d "Returns true if all identified patches were applied and score meets quality gate."
  (if (== (.-total-fixes res) (.-applied-fixes res))
    (>= (.-new-quality-score res) 70)
    false))

(df format-fix-description [(ft FixType)] -> String
  :d "Human-readable description of automated repair action."
  (mt ft
    ((add-prefix-unused)          "Prefixed unused binder with '_'")
    ((export-missing-schema-type) "Appended referenced type to module :export declaration")
    ((merge-duplicate-arms)       "Merged redundant pattern match arms")
    ((canonicalize-formatting)    "Canonicalized S-expression indentation")))
