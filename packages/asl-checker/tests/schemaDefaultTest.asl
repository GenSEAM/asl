(module asl-checker/schemaDefaultTest :x [runTests] :i [(ast :a a) (resolve :a r) (types :a ty)])

fn hasCode diags: (List ty/Diagnostic) wantCode: String -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool (or acc (= d.code wantCode))) false diags)

fn ctorDiag src: String -> Bool
  (match (a/parse src)
    ((err _) true)
    ((ok forms) (hasCode (r/resolveModule (r/collectSummary forms "test.asl") forms (mapEmpty)) "ctor")))

; (:m :ref SCHEMA-DEFAULT-INDENT :do "a :default on a field of an indentation-form schema (schema R with its (:f name T :default v) lines under it) survives the parse: the constructor of that record may omit the field, as it may for the parenthesised (schema R ...) form; a field without a default is still missing, and the default may be a string, a number or a list value")
fn runTests -> Bool
  (do (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b String :default \"\")\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "an indentation-form schema: a string default may be omitted")
      (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b Int64 :default 0)\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "a number default may be omitted")
      (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b (List String) :default (list))\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "a list default may be omitted")
      (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b String :default \"\" \"doc\")\n  (:f c Int64)\n\nfn mk -> Rec\n  (Rec :a 1 :c 2)\n")) "a default in the middle of the schema may be omitted")
      (assert (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b String)\n\nfn mk -> Rec\n  (Rec :a 1)\n") "a field without a default is still missing")
      (assert (not (ctorDiag "(schema Rec (:f a Int64) (:f b String :default \"\"))\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "the parenthesised form keeps working")
      true)
