(module asl-ir/tests/recordKindsTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/link :a lk)
      (asl-ir/lower :a low)])

fn joinLines xs: (List String) -> String
  (stringJoin xs "\n")

fn schemaSource -> String
  (joinLines (list
    "(module kindsfx :x [main Rec Mixed Alias Wrap] :i [])"
    ""
    "(schema Rec (:f a Int64) (:f b Int64) (:f c Int64) (:f d Int64))"
    "(schema Mixed (:f name String) (:f n Int64) (:f x Float64) (:f ok Bool))"
    "(schema Alias (:f a Int) (:f b Float) (:f c (Option Int64)) (:f d (List Int64)))"
    "(schema Wrap (:f v T) (:f w Str))"
    ""
    "fn main -> Int64"
    "  0"))

fn declsOf -> (List ty/SsaRecordDecl)
  (match (low/lowerSource (schemaSource))
    ((ok m) m.records)
    ((err _) (list)))

fn declNamed name: String -> ty/SsaRecordDecl
  (optionOr (listHead (filter (fn [(d ty/SsaRecordDecl)] -> Bool (= d.name name)) (declsOf))) (ty/ssaRecordDecl "missing" (list)))

fn moduleOf records: (List ty/SsaRecordDecl) -> ty/SsaModule
  (ty/ssaModule "fixture" (list) (list) records (list) (list) (list))

fn codesOf m: ty/SsaModule -> (List String)
  (match (vfy/verifySsa m) ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn countCode code: String codes: (List String) -> Int64
  (listLength (filter (fn [(c String)] -> Bool (= c code)) codes))

fn testLowering -> Bool
  (do
    (assert (= (listLength (declsOf)) 4) "all four fixture schemas lower to record decls")
    (assert (= (declNamed "Rec").kinds (list 2 2 2 2)) "soa Rec of four Int64 fields has kinds 2 2 2 2")
    (assert (= (declNamed "Mixed").kinds (list 255 2 3 1)) "String Int64 Float64 Bool map to 255 2 3 1")
    (assert (= (declNamed "Alias").kinds (list 2 3 255 255)) "Int and Float spellings are raw, Option and List fields are boxed")
    (assert (= (declNamed "Wrap").kinds (list 255 255)) "a type variable and an unknown alias stay boxed")
    (assert (= (declNamed "Mixed").fields (list "name" "n" "x" "ok")) "fields stay in declared order")
    true)

fn testConstructors -> Bool
  (let [(plain (ty/ssaRecordDecl "P" (list "a" "b")))
        (typed (ty/ssaRecordDeclTyped "P" (list "a" "b") (list 2 255)))]
    (do
      (assert (= plain.kinds (list 255 255)) "the two-argument constructor marks every field boxed")
      (assert (not (ty/ssaRecordRaw? plain)) "an all-boxed decl is not raw")
      (assert (ty/ssaRecordRaw? typed) "a decl with a raw kind is raw")
      true))

fn firstKinds ds: (List ty/SsaRecordDecl) -> (List Int64)
  (match (listHead ds) ((some d) d.kinds) ((none) (list)))

fn testLinkDedupe -> Bool
  (let [(plain (ty/ssaRecordDecl "P" (list "a" "b")))
        (typed (ty/ssaRecordDeclTyped "P" (list "a" "b") (list 2 255)))
        (other (ty/ssaRecordDeclTyped "P" (list "a" "b") (list 2 2)))
        (q (ty/ssaRecordDecl "Q" (list "z")))
        (viaPlainFirst (lk/firstRecordByName (list plain q typed)))
        (viaTypedFirst (lk/firstRecordByName (list typed plain)))
        (viaDifferentFields (lk/firstRecordByName (list plain (ty/ssaRecordDeclTyped "P" (list "a" "c") (list 2 2)))))]
    (do
      (assert (= (map (fn [(d ty/SsaRecordDecl)] -> String d.name) viaPlainFirst) (list "P" "Q")) "dedupe keeps first-seen order")
      (assert (= (firstKinds viaPlainFirst) (list 2 255)) "an all-boxed first decl yields to a typed decl of the same fields")
      (assert (= (listLength viaTypedFirst) 1) "typed then plain dedupes to one decl")
      (assert (= (firstKinds viaTypedFirst) (list 2 255)) "a typed first decl is kept")
      (assert (= (firstKinds (lk/firstRecordByName (list typed other))) (list 2 255)) "of two typed decls the first wins")
      (assert (= (firstKinds viaDifferentFields) (list 255 255)) "a typed decl with other fields does not replace the first")
      true))

fn testVerify -> Bool
  (let [(typed (ty/ssaRecordDeclTyped "P" (list "a" "b") (list 2 255)))
        (other (ty/ssaRecordDeclTyped "P" (list "a" "b") (list 2 2)))
        (plain (ty/ssaRecordDecl "P" (list "a" "b")))
        (short (ty/ssaRecordDeclTyped "S" (list "a" "b") (list 2)))]
    (do
      (assert (= (countCode "ERR_IR_RECORD_KIND_CONFLICT" (codesOf (moduleOf (list typed other)))) 1) "two decls of one name with different raw kinds give exactly one kind-conflict diag")
      (assert (= (countCode "ERR_IR_RECORD_KIND_CONFLICT" (codesOf (moduleOf (list plain typed)))) 0) "a boxed twin of a typed decl is not a kind conflict")
      (assert (= (codesOf (moduleOf (list typed (ty/ssaRecordDecl "Q" (list "x"))))) (list)) "distinct typed and plain decls verify clean")
      (assert (= (codesOf (moduleOf (list short))) (list "ERR_IR_RECORD_KINDS")) "kinds shorter than fields is ERR_IR_RECORD_KINDS")
      true))

fn ! runTests -> Bool
  (do
    (assert (testLowering) "schema field types lower to per-field kinds")
    (assert (testConstructors) "constructors set kinds")
    (assert (testLinkDedupe) "link dedupe compares kinds")
    (assert (testVerify) "verify reports conflicting and malformed kinds")
    true)
