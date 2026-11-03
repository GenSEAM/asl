(module asl-checker/tests/schemaAliasImportTest :x [runTests] :i [(types :a ty) (ast :a a) (resolve :a r)])

; (:m :ref CHECK-SCHEMA-ALIAS-UNRESOLVED :do "an alias used only in a schema field type, its import removed, is reported as not imported; loopState.asl without its pv import (pv/Turn kept in a fn-typed field) is the case the row names")
fn diagsOf src: String -> (List ty/Diagnostic)
  (match (a/parse src)
    ((err _) (list (ty/Diagnostic :path "test.asl" :line 0 :col 0 :code "parse" :message "parse" :msg "parse")))
    ((ok forms) (r/resolveModule (r/collectSummary forms "test.asl") forms (mapEmpty))))

fn names? diags: (List ty/Diagnostic) text: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.message text)) diags)

fn withField imports: String fieldType: String -> String
  (str "(module t/a\n  :x [main]\n  :i [" imports "])\n\n(schema Holder (:f slot " fieldType "))\n\nfn main -> Int64\n  0\n")

fn ! runTests -> Bool
  (let [(missing "pv/Turn: alias pv is not imported")]
    (do
      (assert (names? (diagsOf (withField "" "pv/Turn")) missing) "a plain field type with no pv import names pv/Turn")
      (assert (names? (diagsOf (withField "" "(List pv/Turn)")) missing) "a type argument of a field names pv/Turn")
      (assert (names? (diagsOf (withField "" "(fn [String String] -> pv/Turn)")) missing) "a fn-typed field's return names pv/Turn, as in loopState.asl")
      (assert (names? (diagsOf (withField "" "(fn [pv/Turn] -> Int64)")) missing) "a fn-typed field's parameter names pv/Turn")
      (assert (names? (diagsOf (withField "(asl/agentLoop/exec :a x)" "(fn [String String] -> pv/Turn)")) missing) "other imports kept do not cover the removed alias")
      (refute (names? (diagsOf (withField "(asl/agentLoop/providers :a pv)" "(fn [String String] -> pv/Turn)")) "alias pv is not imported") "with the import the alias is not reported")
      true))
