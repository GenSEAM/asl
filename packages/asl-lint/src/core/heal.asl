(module asl-lint/heal
  :doc "AgentScript native autonomous repair rules, AST patch recipes, and auto-fixer."
  :export [FixType PatchAction FixResult
           can-auto-repair is-fix-successful format-fix-description])

(defenum FixType
  (:case add-prefix-unused          [] "Prefix unused variable with underscore to satisfy linter")
  (:case export-missing-schema-type [] "Automatically export type referenced in exported schema (Rule 13)")
  (:case merge-duplicate-arms       [] "Consolidate duplicate pattern match arm bodies")
  (:case canonicalize-formatting    [] "Standardize S-expression indentation and parenthesis balance"))

(defschema PatchAction
  (:field fix-type FixType "Classification of the auto-repair applied")
  (:field file String "Path to target ASL source file")
  (:field line Int64 "1-indexed line where patch is applied")
  (:field target-text String "Original code snippet being replaced")
  (:field replacement-text String "Canonical repaired replacement snippet")
  (:field applied Bool "True if patch was written to disk"))

(defschema FixResult
  (:field total-fixes Int64 "Total candidate patches identified")
  (:field applied-fixes Int64 "Total patches successfully applied")
  (:field new-quality-score Int64 "Quality score post-repair (0 to 100)"))

(defun can-auto-repair [(ft FixType)] -> Bool
  :doc "Returns true if this fix type is safe for non-destructive automated repair."
  (match ft
    ((add-prefix-unused)          true)
    ((export-missing-schema-type) true)
    ((merge-duplicate-arms)       true)
    ((canonicalize-formatting)    true)))

(defun is-fix-successful [(res FixResult)] -> Bool
  :doc "Returns true if all identified patches were applied and score meets quality gate."
  (if (== (.-total-fixes res) (.-applied-fixes res))
    (>= (.-new-quality-score res) 70)
    false))

(defun format-fix-description [(ft FixType)] -> String
  :doc "Human-readable description of automated repair action."
  (match ft
    ((add-prefix-unused)          "Prefixed unused binder with '_'")
    ((export-missing-schema-type) "Appended referenced type to module :export declaration")
    ((merge-duplicate-arms)       "Merged redundant pattern match arms")
    ((canonicalize-formatting)    "Canonicalized S-expression indentation")))
