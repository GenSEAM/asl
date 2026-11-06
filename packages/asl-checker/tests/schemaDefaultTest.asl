(module asl-checker/schemaDefaultTest :x [runTests] :i [(ast :a a) (resolve :a r) (types :a ty)])

fn hasCode diags: (List ty/Diagnostic) wantCode: String -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool (or acc (= d.code wantCode))) false diags)

fn ctorDiag src: String -> Bool
  (match (a/parse src)
    ((err _) true)
    ((ok forms) (hasCode (r/resolveModule (r/collectSummary forms "test.asl") forms (mapEmpty)) "ctor")))

fn fieldsOf src: String -> (List a/AstField)
  (match (a/parse src)
    ((err _) (list))
    ((ok forms) (listFlatMap (fn [(f a/TopForm)] -> (List a/AstField) (match f ((a/topSchema sn) sn.fields) (_ (list)))) forms)))

fn fieldNamed fs: (List a/AstField) name: String -> (Option a/AstField)
  (listFind (fn [(f a/AstField)] -> Bool (= f.name name)) fs)

fn jsonOf fs: (List a/AstField) name: String -> (Option String)
  (match (fieldNamed fs name) ((some f) f.json) ((none) (none)))

fn hasDefaultOf fs: (List a/AstField) name: String -> Bool
  (match (fieldNamed fs name) ((some f) (some? f.default)) ((none) false))

; (:m :ref SCHEMA-DEFAULT-INDENT :do "a :default on a field of an indentation-form schema (schema R with its (:f name T :default v) lines under it) survives the parse: the constructor of that record may omit the field, as it may for the parenthesised (schema R ...) form; a field without a default is still missing, and the default may be a string, a number or a list value")
fn runTests -> Bool
  (do (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b String :default \"\")\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "an indentation-form schema: a string default may be omitted")
      (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b Int64 :default 0)\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "a number default may be omitted")
      (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b (List String) :default (list))\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "a list default may be omitted")
      (assert (not (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b String :default \"\" \"doc\")\n  (:f c Int64)\n\nfn mk -> Rec\n  (Rec :a 1 :c 2)\n")) "a default in the middle of the schema may be omitted")
      (assert (ctorDiag "schema Rec\n  (:f a Int64)\n  (:f b String)\n\nfn mk -> Rec\n  (Rec :a 1)\n") "a field without a default is still missing")
      (assert (not (ctorDiag "(schema Rec (:f a Int64) (:f b String :default \"\"))\n\nfn mk -> Rec\n  (Rec :a 1)\n")) "the parenthesised form keeps working")
      (assert (some? (jsonOf (fieldsOf "schema Rec\n  (:f a Int64)\n  (:f b String :json bName)\n") "b")) "a :json key on a bare-form schema field is kept")
      (assert (= (jsonOf (fieldsOf "schema Rec\n  (:f a Int64)\n  (:f b String :json bName)\n") "b") (jsonOf (fieldsOf "(schema Rec (:f a Int64) (:f b String :json bName))\n") "b")) "and equals what the parenthesised form keeps")
      (assert (and (hasDefaultOf (fieldsOf "schema Rec\n  (:f a Int64)\n  (:f b Int64 \"doc\" :default 0)\n") "b") (hasDefaultOf (fieldsOf "schema Rec\n  (:f a Int64)\n  (:f b Int64 :default 0 \"doc\")\n") "b")) "a default survives a doc before it and a doc after it")
      (assert (and (hasDefaultOf (fieldsOf "schema Rec\n  (:f a Int64)\n  (:f b Int64 :default 0 :json bName)\n") "b") (some? (jsonOf (fieldsOf "schema Rec\n  (:f a Int64)\n  (:f b Int64 :default 0 :json bName)\n") "b"))) "a default and a :json on one field both survive")
      true)
