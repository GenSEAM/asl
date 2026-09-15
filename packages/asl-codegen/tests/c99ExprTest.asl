(module asl-codegen/c99ExprTest
  :d "Unit tests for pure ISO C99 expression lowering pipeline."
  :x [testC99Atoms
      testC99ArithmeticAndPrecedence
      testC99LogicAndComparisons
      testC99ConditionalsAndLet
      testC99RecordsAndMatching
      runTests]
  :i [(c99Expr :a ex)
      (reader :a rd)])

(df testC99Atoms [] -> Bool
  :d "Verifies atom, literal, and identifier mangling into ISO C99."
  (let [(a1 (ex/lowerCAtom "true"))
        (a2 (ex/lowerCAtom "false"))
        (a3 (ex/lowerCAtom "nil"))
        (a4 (ex/lowerCAtom "42"))
        (a5 (ex/lowerCAtom "-42"))
        (a6 (ex/lowerCAtom "0"))
        (a7 (ex/lowerCAtom "3.14"))
        (a8 (ex/lowerCAtom "\"hello\""))
        (a9 (ex/lowerCAtom "int"))
        (a10 (ex/lowerCAtom "return"))
        (a11 (ex/lowerCAtom "is-empty?"))
        (a12 (ex/lowerCAtom "make-vector!"))]
    (assert (= a1 "true") "true literal")
    (assert (= a2 "false") "false literal")
    (assert (= a3 "(void)0") "nil literal")
    (assert (= a4 "42LL") "integer literal 42LL")
    (assert (= a5 "-42LL") "negative integer -42LL")
    (assert (= a6 "0LL") "zero literal 0LL")
    (assert (= a7 "3.14") "floating point literal")
    (assert (= a8 "(asl_string_t){ .data = \"hello\", .len = 5 }") "string literal")
    (assert (= a9 "asl_int") "c99 keyword int mangling")
    (assert (= a10 "asl_return") "c99 keyword return mangling")
    (assert (= a11 "is_empty") "predicate identifier mangling")
    (assert (= a12 "make_vector_mut") "mutator identifier mangling")
    (refute (ex/isC99Keyword? "my_var") "user var is not c99 keyword")
    (refute (not (ex/isC99Keyword? "volatile")) "volatile is c99 keyword")
    (refute (not (ex/isC99Keyword? "restrict")) "restrict is c99 keyword")
    (refute (string-contains? a11 "?") "mangled identifier has no question mark")
    (refute (string-contains? a12 "!") "mangled identifier has no bang")
    (refute (string-contains? (ex/mangleCIdent "foo-bar-baz") "-") "mangled identifier has no dashes")
    true))

(df testC99ArithmeticAndPrecedence [] -> Bool
  :d "Verifies arithmetic expression lowering and defensive parenthesization."
  (let [(addNode (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "1") (rd/sexprAtom "2"))))
        (subNode (rd/sexprList (list (rd/sexprAtom "-") (rd/sexprAtom "10") (rd/sexprAtom "5"))))
        (negNode (rd/sexprList (list (rd/sexprAtom "-") (rd/sexprAtom "42"))))
        (divNode (rd/sexprList (list (rd/sexprAtom "/") (rd/sexprAtom "20") (rd/sexprAtom "4"))))
        (mulNode (rd/sexprList (list (rd/sexprAtom "*") addNode (rd/sexprAtom "3"))))
        (eAdd (ex/lowerCExpr (ex/emptyLowerCtx) addNode))
        (eSub (ex/lowerCExpr (ex/emptyLowerCtx) subNode))
        (eNeg (ex/lowerCExpr (ex/emptyLowerCtx) negNode))
        (eDiv (ex/lowerCExpr (ex/emptyLowerCtx) divNode))
        (eMul (ex/lowerCExpr (ex/emptyLowerCtx) mulNode))]
    (assert (= eAdd "((1LL) + (2LL))") "addition parenthesized")
    (assert (= eSub "((10LL) - (5LL))") "subtraction parenthesized")
    (assert (= eNeg "(-(42LL))") "unary negation parenthesized")
    (assert (= eDiv "((20LL) / (4LL))") "division parenthesized")
    (assert (= eMul "((((1LL) + (2LL))) * (3LL))") "nested precedence parenthesized")
    (refute (not (string-starts-with? eDiv "((")) "division starts with double parens")
    (refute (not (string-ends-with? eDiv "))")) "division ends with double parens")
    (refute (not (string-contains? eDiv " / ")) "division contains operator")
    (refute (string-contains? eMul "+ 2LL *") "multiplication never loses nested parens")
    true))

(df testC99LogicAndComparisons [] -> Bool
  :d "Verifies logical operators and comparison expressions in C99."
  (let [(eqNode (rd/sexprList (list (rd/sexprAtom "=") (rd/sexprAtom "x") (rd/sexprAtom "y"))))
        (neqNode (rd/sexprList (list (rd/sexprAtom "!=") (rd/sexprAtom "x") (rd/sexprAtom "y"))))
        (ltNode (rd/sexprList (list (rd/sexprAtom "<") (rd/sexprAtom "x") (rd/sexprAtom "y"))))
        (andNode (rd/sexprList (list (rd/sexprAtom "and") (rd/sexprAtom "a") (rd/sexprAtom "b"))))
        (orNode (rd/sexprList (list (rd/sexprAtom "or") (rd/sexprAtom "a") (rd/sexprAtom "b"))))
        (notNode (rd/sexprList (list (rd/sexprAtom "not") (rd/sexprAtom "c"))))
        (eEq (ex/lowerCExpr (ex/emptyLowerCtx) eqNode))
        (eNeq (ex/lowerCExpr (ex/emptyLowerCtx) neqNode))
        (eLt (ex/lowerCExpr (ex/emptyLowerCtx) ltNode))
        (eAnd (ex/lowerCExpr (ex/emptyLowerCtx) andNode))
        (eOr (ex/lowerCExpr (ex/emptyLowerCtx) orNode))
        (eNot (ex/lowerCExpr (ex/emptyLowerCtx) notNode))]
    (assert (= eEq "((x) == (y))") "equality uses double equals")
    (assert (= eNeq "((x) != (y))") "inequality lowered")
    (assert (= eLt "((x) < (y))") "less than lowered")
    (assert (= eAnd "((a) && (b))") "and lowered to logical and")
    (assert (= eOr "((a) || (b))") "or lowered to logical or")
    (assert (= eNot "(!(c))") "not lowered to logical not")
    (refute (string-contains? eEq " = ") "equality never lowers to single assignment equals")
    (refute (not (string-contains? eAnd "&&")) "and contains double ampersand")
    (refute (not (string-contains? eOr "||")) "or contains double pipe")
    true))

(df testC99ConditionalsAndLet [] -> Bool
  :d "Verifies ternary conditional and scoped compound let statement block lowering."
  (let [(ifNode (rd/sexprList (list (rd/sexprAtom "if") (rd/sexprAtom "true") (rd/sexprAtom "1") (rd/sexprAtom "0"))))
        (eIf (ex/lowerCExpr (ex/emptyLowerCtx) ifNode))
        (bPair1 (rd/sexprVect (list (rd/sexprAtom "x") (rd/sexprAtom "10"))))
        (bPair2 (rd/sexprVect (list (rd/sexprAtom "y") (rd/sexprAtom "20"))))
        (bindings (rd/sexprVect (list bPair1 bPair2)))
        (addBody (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "x") (rd/sexprAtom "y"))))
        (letNode (rd/sexprList (list (rd/sexprAtom "let") bindings addBody)))
        (eLet (ex/lowerCExpr (ex/emptyLowerCtx) letNode))
        (bTypedPair (rd/sexprVect (list (rd/sexprAtom "z") (rd/sexprAtom "Int64") (rd/sexprAtom "50"))))
        (bindingsTyped (rd/sexprVect (list bTypedPair)))
        (letTypedNode (rd/sexprList (list (rd/sexprAtom "let") bindingsTyped (rd/sexprAtom "z"))))
        (eLetTyped (ex/lowerCExpr (ex/emptyLowerCtx) letTypedNode))]
    (assert (= eIf "((true) ? (1LL) : (0LL))") "if lowered to ternary")
    (assert (= eLet "{ int64_t x = 10LL; int64_t y = 20LL; ((x) + (y)); }") "let block with inferred types")
    (assert (= eLetTyped "{ int64_t z = 50LL; z; }") "let block with explicit type")
    (refute (not (string-starts-with? eLet "{")) "let block starts with open brace")
    (refute (not (string-ends-with? eLet "}")) "let block ends with close brace")
    (refute (not (string-contains? eLet "int64_t x = 10LL;")) "let block contains typed variable x")
    (refute (not (string-contains? eLet "int64_t y = 20LL;")) "let block contains typed variable y")
    true))

(df testC99RecordsAndMatching [] -> Bool
  :d "Verifies record instantiation, field access, and exhaustive switch match lowering."
  (let [(fAccess (ex/lowerCFieldAccess "person" "age"))
        (fAccessExpr (rd/sexprList (list (rd/sexprAtom ".-age") (rd/sexprAtom "person"))))
        (eField (ex/lowerCExpr (ex/emptyLowerCtx) fAccessExpr))
        (recNode (rd/sexprList (list (rd/sexprAtom "Person")
                                     (rd/sexprAtom ":name")
                                     (rd/sexprAtom "\"Alice\"")
                                     (rd/sexprAtom ":age")
                                     (rd/sexprAtom "30"))))
        (eRec (ex/lowerCExpr (ex/emptyLowerCtx) recNode))
        (arm1 (rd/sexprList (list (rd/sexprList (list (rd/sexprAtom "some") (rd/sexprAtom "x")))
                                  (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "x") (rd/sexprAtom "1"))))))
        (arm2 (rd/sexprList (list (rd/sexprList (list (rd/sexprAtom "none")))
                                  (rd/sexprAtom "0"))))
        (matchNode (rd/sexprList (list (rd/sexprAtom "match") (rd/sexprAtom "val") arm1 arm2)))
        (eMatch (ex/lowerCExpr (ex/emptyLowerCtx) matchNode))
        (armQual (rd/sexprList (list (rd/sexprAtom "rd/sexprAtom") (rd/sexprAtom "42"))))
        (matchQualNode (rd/sexprList (list (rd/sexprAtom "match") (rd/sexprAtom "v") armQual)))
        (eMatchQual (ex/lowerCExpr (ex/emptyLowerCtx) matchQualNode))]
    (assert (= fAccess "person.age") "field access direct")
    (assert (= eField "person.age") "field access expr")
    (assert (= eRec "(AslPerson){ .name = (asl_string_t){ .data = \"Alice\", .len = 5 }, .age = 30LL }") "record compound literal")
    (assert (string-contains? eMatch "switch ((val).tag)") "match contains switch on tag")
    (assert (string-contains? eMatch "case ASL_TAG_SOME:") "match contains some tag case")
    (assert (string-contains? eMatch "case ASL_TAG_NONE:") "match contains none tag case")
    (assert (string-contains? eMatchQual "case ASL_TAG_SEXPRATOM:") "match on a qualified case drops the module alias so the tag matches the alias emitCaseTagAlias emits for the bare case name")
    (refute (string-contains? eMatchQual "ASL_TAG_RD_") "a module alias in the tag names a constant no enum ever defines")
    (assert (string-contains? eMatch "break;") "match cases have break")
    (assert (string-contains? eMatch "default: { abort(); break; }") "match contains unreachable default guard")
    (refute (not (string-contains? eRec "(AslPerson){")) "record contains type cast")
    (refute (not (string-contains? eRec ".name =")) "record contains designated name field")
    (refute (not (string-contains? eRec ".age =")) "record contains designated age field")
    (refute (not (string-contains? eMatch "break;")) "match never falls through without break")
    (refute (not (string-contains? eMatch "abort();")) "match never omits default abort guard")
    (refute (string-contains? eMatchQual "ASL_TAG_RD/") "match tag must not contain slash")
    true))

(df testC99VariadicStr [] -> Bool
  :d "Verifies that the variadic str builtin lowers to right-nested pairwise concatenation instead of an undeclared variadic call."
  (let [(sA (rd/sexprAtom "\"a\""))
        (sB (rd/sexprAtom "\"b\""))
        (sC (rd/sexprAtom "\"c\""))
        (zero (ex/lowerCExpr (ex/emptyLowerCtx) (rd/sexprList (list (rd/sexprAtom "str")))))
        (one (ex/lowerCExpr (ex/emptyLowerCtx) (rd/sexprList (list (rd/sexprAtom "str") sA))))
        (two (ex/lowerCExpr (ex/emptyLowerCtx) (rd/sexprList (list (rd/sexprAtom "str") sA sB))))
        (three (ex/lowerCExpr (ex/emptyLowerCtx) (rd/sexprList (list (rd/sexprAtom "str") sA sB sC))))]
    (assert (string-contains? zero ".len = 0") "empty str lowers to the empty string literal")
    (refute (string-contains? one "string_concat2") "single argument str needs no concatenation")
    (assert (string-contains? two "string_concat2(") "two argument str concatenates")
    (assert (string-contains? three "string_concat2(") "three argument str concatenates")
    (refute (string-contains? two "str(") "str must never survive as a variadic C call")
    (refute (string-contains? three "str(") "str must never survive as a variadic C call")
    true))

(df runTests [] -> Bool
  :d "Executes all unit tests in c99ExprTest."
  (do
    (assert (testC99Atoms) "testC99Atoms must pass")
    (assert (testC99ArithmeticAndPrecedence) "testC99ArithmeticAndPrecedence must pass")
    (assert (testC99LogicAndComparisons) "testC99LogicAndComparisons must pass")
    (assert (testC99ConditionalsAndLet) "testC99ConditionalsAndLet must pass")
    (assert (testC99RecordsAndMatching) "testC99RecordsAndMatching must pass")
    (assert (testC99VariadicStr) "testC99VariadicStr must pass")
    true))
