(module asl-lint/heal :x [FixType PatchAction FixResult canAutoRepair isFixSuccessful formatFixDescription healDelimiters] :i [(asl-parser/balance :a bal)])

(enum FixType (:c addPrefixUnused [] "Prefix unused variable with underscore to satisfy linter") (:c exportMissingSchemaType [] "Automatically export type referenced in exported schema (Rule 13)") (:c mergeDuplicateArms [] "Consolidate duplicate pattern match arm bodies") (:c canonicalizeFormatting [] "Standardize S-expression indentation and parenthesis balance"))

(schema PatchAction (:f fixType FixType) (:f file String) (:f line Int64) (:f targetText String) (:f replacementText String) (:f applied Bool))

(schema FixResult (:f totalFixes Int64) (:f appliedFixes Int64) (:f newQualityScore Int64))

fn canAutoRepair ft: FixType -> Bool
  (mt ft ((addPrefixUnused) true) ((exportMissingSchemaType) true) ((mergeDuplicateArms) true) ((canonicalizeFormatting) true))

fn isFixSuccessful res: FixResult -> Bool
  (if (= res.totalFixes res.appliedFixes) (>= res.newQualityScore 70) false)

fn formatFixDescription ft: FixType -> String
  (mt ft ((addPrefixUnused) "Prefixed unused binder with '_'") ((exportMissingSchemaType) "Appended referenced type to module :export declaration") ((mergeDuplicateArms) "Merged redundant pattern match arms") ((canonicalizeFormatting) "Canonicalized S-expression indentation"))

fn healDelimiters raw: String -> String
  (bal/balanceDelimiters raw)
