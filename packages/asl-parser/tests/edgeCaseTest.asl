(module asl-parser/edgeCaseTest
  :d "Dual-polarity edge-case verification for Task 54503: Parser Hardening & Macro Anomaly Triage."
  :x [runTests
      RunTests
      testBracketedParameterLists
      testSymbolsWithQuestionAndBang
      testDocstringPreservationAndExtraction
      testArrowPatternMatchingAndNestedMatch
      testStringEscapeNormalization
      testRoundtripIdempotenceProperty
      testDualPolarityFalsifications]
  :i [(indentPrinter :a ipr) (indentParser :a ip) (reader :a rd)])

(df testBracketedParameterLists [] -> Bool
  :d "Verifies bracketed parameter vectors are lowered to canonical parameter vectors."
  (let [(src1 "fn calculate [x Int64 y Int64] -> Int64\n  match x\n    0 -> y\n    _ -> (+ x y)\n")
        (res1 (ip/parseIndented src1))]
    (mt res1
      ((ok s1)
       (let [(r1 (rd/renderSexpr s1))]
         (assert (string-contains? r1 "df calculate") "Must declare df calculate")
         (assert (string-contains? r1 "[(x Int64) (y Int64)]") "Must normalize bracketed pairs to parameter vector")
         (assert (string-contains? r1 "-> Int64") "Must retain return type Int64")
         (assert (string-contains? r1 "match x") "Must retain match x construct")
         (refute (string-contains? r1 "[x Int64 y Int64]") "Must refute unnormalized bracketed parameter syntax")
         (refute (string-contains? r1 "-> ->") "Must refute duplicated arrows")))
      ((err msg1)
       (assert false (str "Failed to parse bracketed params: " msg1))
       (refute true "Refutes bracketed parse failure")))
    (let [(src2 "fn add [(a Int) (b Int)] -> Int\n  (+ a b)\n")
          (res2 (ip/parseIndented src2))]
      (mt res2
        ((ok s2)
         (let [(r2 (rd/renderSexpr s2))]
           (assert (string-contains? r2 "df add") "Must declare df add")
           (assert (string-contains? r2 "[(a Int) (b Int)]") "Must preserve bracketed tuples in parameter vector")
           (assert (string-contains? r2 "(+ a b)") "Must retain body form (+ a b)")
           (refute (string-contains? r2 "fn add") "Must refute raw fn keyword in AST")
           (refute (string-contains? r2 "error") "Must refute errors in valid syntax")))
        ((err msg2)
         (assert false (str "Failed to parse bracketed tuples: " msg2))
         (refute true "Refutes bracketed tuple parse failure"))))
    true))

(df testSymbolsWithQuestionAndBang [] -> Bool
  :d "Verifies symbols ending in ? and ! do not fragment into separated tokens."
  (let [(src1 "fn is-empty? [s String] -> Bool\n  string-empty? s\n")
        (res1 (ip/parseIndented src1))]
    (mt res1
      ((ok s1)
       (let [(r1 (rd/renderSexpr s1))]
         (assert (string-contains? r1 "df is-empty?") "Predicate fn name retains trailing question mark")
         (assert (string-contains? r1 "(string-empty? s)") "Body predicate call retains trailing question mark")
         (refute (string-contains? r1 "is-empty ?") "Refutes token fragmentation of is-empty?")
         (refute (string-contains? r1 "string-empty ?") "Refutes token fragmentation of string-empty?")))
      ((err msg1)
       (assert false (str "Failed to parse predicate symbols: " msg1))
       (refute true "Refutes predicate parse failure")))
    (let [(src2 "fn swap! [a Ref b Ref] -> Unit\n  set! a b\n")
          (res2 (ip/parseIndented src2))]
      (mt res2
        ((ok s2)
         (let [(r2 (rd/renderSexpr s2))]
           (assert (string-contains? r2 "df swap!") "Mutation fn name retains trailing bang")
           (assert (string-contains? r2 "(set! a b)") "Body mutation call retains trailing bang")
           (refute (string-contains? r2 "swap !") "Refutes token fragmentation of swap!")
           (refute (string-contains? r2 "set !") "Refutes token fragmentation of set!")))
        ((err msg2)
         (assert false (str "Failed to parse mutation symbols: " msg2))
         (refute true "Refutes mutation parse failure"))))
    (let [(src3 "fn updateState ! [s State] -> State\n  modify! s\n")
          (res3 (ip/parseIndented src3))]
      (mt res3
        ((ok s3)
         (let [(r3 (rd/renderSexpr s3))]
           (assert (string-contains? r3 "df updateState") "Effectful fn name is declared")
           (assert (string-contains? r3 "! [(s State)]") "Effect marker ! is attached before parameters")
           (refute (string-contains? r3 "df updateState!") "Effectful name should not concatenate effect marker into identifier")
           (refute (string-contains? r3 "error") "Refutes error on effect marker")))
        ((err msg3)
         (assert false (str "Failed to parse effect marker: " msg3))
         (refute true "Refutes effect marker parse failure"))))
    true))

(df testDocstringPreservationAndExtraction [] -> Bool
  :d "Verifies that docstrings are extracted from indented functions and roundtripped."
  (let [(src "fn area [s Shape] -> Float\n  :d \"Computes geometric area.\"\n  match s\n    0 -> 0.0\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok s)
       (let [(r (rd/renderSexpr s))]
         (assert (string-contains? r "df area") "Function name area defined")
         (assert (string-contains? r ":d \"Computes geometric area.\"") "Docstring preserved in canonical df form")
         (assert (string-contains? r "match s") "Match form retained after docstring")
         (refute (string-contains? r "(:d \"Computes geometric area.\")") "Docstring must not be wrapped in extraneous nested list")
         (refute (string-contains? r "(:d (:d") "Docstring must not be duplicated")
         (refute (string-contains? r "error") "Must refute parse errors")))
      ((err msg)
       (assert false (str "Failed to parse function with docstring: " msg))
       (refute true "Refutes docstring parse failure")))
    (let [(srcHeader "fn compute [x Int] -> Int :d \"Header docstring.\"\n  (+ x 1)\n")
          (resHeader (ip/parseIndented srcHeader))]
      (mt resHeader
        ((ok sh)
         (let [(rh (rd/renderSexpr sh))]
           (assert (string-contains? rh "df compute") "Function compute defined")
           (assert (string-contains? rh ":d \"Header docstring.\"") "Header docstring extracted into canonical df form")
           (refute (string-contains? rh "error") "Header docstring refutes error")))
        ((err msgH)
         (assert false (str "Failed to parse header docstring: " msgH))
         (refute true "Refutes header docstring parse failure"))))
    true))

(df testArrowPatternMatchingAndNestedMatch [] -> Bool
  :d "Verifies complex nested pattern matching arms with arrow syntax."
  (let [(src "match opt\n  Some v ->\n    match v\n      Ok n -> n\n      Err _ -> 0\n  None -> -1\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok s)
       (let [(r (rd/renderSexpr s))]
         (assert (string-contains? r "match opt") "Outer match on opt construct preserved")
         (assert (string-contains? r "Some v") "Outer Some v pattern arm preserved")
         (assert (string-contains? r "match v") "Nested match on v construct preserved")
         (assert (string-contains? r "Ok n") "Nested Ok n pattern arm preserved")
         (assert (string-contains? r "Err _") "Nested Err _ pattern arm preserved")
         (assert (string-contains? r "None") "Outer None pattern arm preserved")
         (refute (string-contains? r "Some v ->") "Arrow syntax lowered out of pattern arm")
         (refute (string-contains? r "Ok n ->") "Arrow syntax lowered out of nested arm")
         (refute (string-contains? r "Err _ ->") "Arrow syntax lowered out of error arm")
         (refute (string-contains? r "None ->") "Arrow syntax lowered out of None arm")))
      ((err msg)
       (assert false (str "Failed to parse nested match: " msg))
       (refute true "Refutes nested match parse failure")))
    (let [(srcLit "match code\n  200 -> \"OK\"\n  404 -> \"Not Found\"\n  _ -> \"Unknown\"\n")
          (resLit (ip/parseIndented srcLit))]
      (mt resLit
        ((ok sLit)
         (let [(rLit (rd/renderSexpr sLit))]
           (assert (string-contains? rLit "match code") "Literal match on code preserved")
           (assert (string-contains? rLit "200 \"OK\"") "Literal 200 arm formatted cleanly")
           (refute (string-contains? rLit "200 ->") "Literal arrow lowered")
           (refute (string-contains? rLit "error") "Literal match refutes error")))
        ((err msgLit)
         (assert false (str "Failed to parse literal match: " msgLit))
         (refute true "Refutes literal match parse failure"))))
    true))

(df testStringEscapeNormalization [] -> Bool
  :d "Verifies that escape sequences inside strings are preserved cleanly."
  (let [(src (str "val = \"hello\tworld\"\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok s)
       (let [(r (rd/renderSexpr s))]
         (assert (string-contains? r "val =") "Assignment target preserved")
         (assert (string-contains? r "hello\\tworld") "Tab character in string is normalized to \\t escape")
         (refute (string-contains? r "syntax error") "Refutes syntax error in string escape parsing")
         (refute (string-contains? r "\t") "Refutes raw unescaped tab in SExpr rendering")
         true))
      ((err msg)
       (assert false (str "Failed to parse string escapes: " msg))
       (refute true "Refutes string escape parse failure")
       false)))
  (let [(srcQ "val = \"hello \\\"world\\\"\"\n")
        (resQ (ip/parseIndented srcQ))]
    (mt resQ
      ((ok sQ)
       (let [(rQ (rd/renderSexpr sQ))]
         (assert (string-contains? rQ "hello \\\"world\\\"") "Escaped quotes preserved in string literal")
         (refute (string-contains? rQ "syntax error") "Refutes syntax error on escaped quote")
         true))
      ((err msgQ)
       (assert false (str "Failed to parse escaped quotes: " msgQ))
       (refute true "Refutes escaped quote parse failure")
       false)))
  true)

(df testRoundtripIdempotenceProperty [] -> Bool
  :d "Verifies roundtrip idempotence print(parse(print(ast))) == print(ast)."
  (let [(subPlus (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))
        (arm2 (rd/makeList (list (rd/makeAtom "_") subPlus)))
        (arm1 (rd/makeList (list (rd/makeAtom "0") (rd/makeAtom "y"))))
        (arms (rd/makeList (list arm1 arm2)))
        (matchForm (rd/makeList (list (rd/makeAtom "match") (rd/makeAtom "x") arms)))
        (paramX (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int64"))))
        (paramY (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int64"))))
        (params (rd/makeVect (list paramX paramY)))
        (ast1 (rd/makeList (list (rd/makeAtom "df")
                                 (rd/makeAtom "calc")
                                 params
                                 (rd/makeAtom "->")
                                 (rd/makeAtom "Int64")
                                 (rd/makeAtom ":d")
                                 (rd/makeAtom "\"Calculate sum.\"")
                                 matchForm)))
        (p1 (ipr/formatIndented ast1))
        (parseRes1 (ip/parseIndented p1))]
    (assert (> (string-length p1) 0) "Formatted output p1 must not be empty")
    (refute (= (string-length p1) 0) "Formatted output p1 refutes empty string")
    (assert (is-ok? parseRes1) "Reparsed result of p1 must succeed")
    (refute (is-err? parseRes1) "Reparsed result of p1 refutes error")
    (mt parseRes1
      ((ok ast1Reparsed)
       (let [(p2 (ipr/formatIndented ast1Reparsed))]
         (assert (= p1 p2) (str "Roundtrip idempotence check 1 failed:\np1:\n" p1 "\np2:\n" p2))
         (refute (!= p1 p2) "Roundtrip idempotence check 1 refutes inequality")))
      ((err msg)
       (assert false (str "Parse error in roundtrip 1: " msg))
       (refute true "Refutes parse failure in roundtrip 1")))
    (let [(stParam (rd/makeList (list (rd/makeAtom "st") (rd/makeAtom "State"))))
          (stParams (rd/makeVect (list stParam)))
          (swapCall (rd/makeList (list (rd/makeAtom "swap!") (rd/makeAtom "st") (rd/makeAtom "st"))))
          (ast2 (rd/makeList (list (rd/makeAtom "df")
                                   (rd/makeAtom "mutateState!")
                                   (rd/makeAtom "!")
                                   stParams
                                   (rd/makeAtom "->")
                                   (rd/makeAtom "State")
                                   swapCall)))
          (p1_2 (ipr/formatIndented ast2))
          (parseRes2 (ip/parseIndented p1_2))]
      (assert (> (string-length p1_2) 0) "Formatted output p1_2 must not be empty")
      (refute (= (string-length p1_2) 0) "Formatted output p1_2 refutes empty string")
      (assert (is-ok? parseRes2) "Reparsed result of p1_2 must succeed")
      (refute (is-err? parseRes2) "Reparsed result of p1_2 refutes error")
      (mt parseRes2
        ((ok ast2Reparsed)
         (let [(p2_2 (ipr/formatIndented ast2Reparsed))]
           (assert (= p1_2 p2_2) (str "Roundtrip idempotence check 2 failed:\np1_2:\n" p1_2 "\np2_2:\n" p2_2))
           (refute (!= p1_2 p2_2) "Roundtrip idempotence check 2 refutes inequality")))
        ((err msg2)
         (assert false (str "Parse error in roundtrip 2: " msg2))
         (refute true "Refutes parse failure in roundtrip 2")))
      true)))

(df testDualPolarityFalsifications [] -> Bool
  :d "Verifies rejection of invalid syntaxes and dual-polarity negative assertions."
  (let [(r1 (ip/parseIndented ""))
        (r2 (ip/parseIndented "   \n\n"))
        (r3 (ip/parseIndented "fn foo [x Int -> Int\n  x\n"))
        (r4 (ip/parseIndented "val = \"unclosed {interp\"\n"))]
    (assert (is-err? r1) "Empty string must return err")
    (refute (is-ok? r1) "Empty string refutes ok")
    (assert (is-err? r2) "Whitespace-only input must return err")
    (refute (is-ok? r2) "Whitespace-only input refutes ok")
    (assert (is-err? r3) "Unclosed parameter bracket must return err")
    (refute (is-ok? r3) "Unclosed parameter bracket refutes ok")
    (assert (is-err? r4) "Unclosed interpolation expression must return err")
    (refute (is-ok? r4) "Unclosed interpolation expression refutes ok")
    true))

(df runTests [] -> Bool
  :d "Executes all edgeCaseTest fixtures with dual polarity."
  (let [(ok (and (testBracketedParameterLists)
                 (and (testSymbolsWithQuestionAndBang)
                      (and (testDocstringPreservationAndExtraction)
                           (and (testArrowPatternMatchingAndNestedMatch)
                                (and (testStringEscapeNormalization)
                                     (and (testRoundtripIdempotenceProperty)
                                          (testDualPolarityFalsifications))))))))]
    (if ok
      (do (println "PASS")
          true)
      false)))

(df RunTests [] -> Bool
  :d "Export alias for uppercase test runners."
  (runTests))
