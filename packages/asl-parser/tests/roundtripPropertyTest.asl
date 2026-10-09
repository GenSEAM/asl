(module asl-parser/roundtripPropertyTest :x [runTests] :i [(indentPrinter :a ipr) (indentParser :a ip) (reader :a rd)])

fn verifyRoundtrip ast: rd/SExpr name: String -> Bool
  (let [(printed (ipr/formatIndented ast))
        (reparsedRes (ip/parseIndented printed))]
    (mt reparsedRes
      ((ok reparsed)
        (let [(rOrig (rd/renderSexpr ast))
              (rReparsed (rd/renderSexpr reparsed))]
          (assert (= rOrig rReparsed) (str "Roundtrip mismatch for " name ":\n  orig:     " rOrig "\n  printed:  " printed "\n  reparsed: " rReparsed))
          true))
      ((err msg)
        (assert false (str "Failed to re-parse printed AST for " name ": " msg "\nPrinted code:\n" printed))
        false)))

fn testFunctionWithMatchRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "area") (rd/makeVect (list (rd/makeList (list (rd/makeAtom "s") (rd/makeAtom "Shape"))))) (rd/makeAtom "->") (rd/makeAtom "Float") (rd/makeList (list (rd/makeAtom "match") (rd/makeAtom "s") (rd/makeList (list (rd/makeList (list (rd/makeList (list (rd/makeAtom "Circle") (rd/makeAtom "r"))) (rd/makeList (list (rd/makeAtom "mul") (rd/makeAtom "pi") (rd/makeList (list (rd/makeAtom "mul") (rd/makeAtom "r") (rd/makeAtom "r"))))))))))))))]
    (verifyRoundtrip ast "function definition with match"))

fn testMultiParamFunctionRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "add") (rd/makeVect (list (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int"))) (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int"))))) (rd/makeAtom "->") (rd/makeAtom "Int") (rd/makeList (list (rd/makeAtom "add") (rd/makeAtom "x") (rd/makeAtom "y"))))))]
    (verifyRoundtrip ast "multi-param function"))

fn testDotAccessRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom ".-email") (rd/makeList (list (rd/makeAtom ".-profile") (rd/makeAtom "user"))))))]
    (verifyRoundtrip ast "compound dot access"))

fn testInterpolationRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "str") (rd/makeAtom "\"User: \"") (rd/makeAtom "name") (rd/makeAtom "\" logged in\""))))]
    (verifyRoundtrip ast "string interpolation"))

fn testInlineListRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "list") (rd/makeAtom "1") (rd/makeAtom "2") (rd/makeAtom "3"))))]
    (verifyRoundtrip ast "inline list"))

fn testSchemaRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "schema") (rd/makeAtom "Point") (rd/makeList (list (rd/makeAtom ":field") (rd/makeAtom "x") (rd/makeAtom "Int") (rd/makeAtom "\"\""))) (rd/makeList (list (rd/makeAtom ":field") (rd/makeAtom "y") (rd/makeAtom "Int") (rd/makeAtom "\"\""))))))]
    (verifyRoundtrip ast "schema declaration"))

fn testEnumRoundtrip -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "enum") (rd/makeAtom "Color") (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Red") (rd/makeVect (list)) (rd/makeAtom "\"\""))) (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Green") (rd/makeVect (list)) (rd/makeAtom "\"\""))) (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Blue") (rd/makeVect (list)) (rd/makeAtom "\"\""))))))]
    (verifyRoundtrip ast "enum declaration"))

fn testVariedGeneratedAstRoundtrips -> Bool
  (let [(ast1 (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "inc") (rd/makeVect (list (rd/makeList (list (rd/makeAtom "n") (rd/makeAtom "Int"))))) (rd/makeAtom "->") (rd/makeAtom "Int") (rd/makeList (list (rd/makeAtom "add") (rd/makeAtom "n") (rd/makeAtom "1"))))))
        (ast2 (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "isZero") (rd/makeVect (list (rd/makeList (list (rd/makeAtom "v") (rd/makeAtom "Int"))))) (rd/makeAtom "->") (rd/makeAtom "Bool") (rd/makeList (list (rd/makeAtom "=") (rd/makeAtom "v") (rd/makeAtom "0"))))))
        (ast3 (rd/makeList (list (rd/makeAtom "fn") (rd/makeAtom "negate") (rd/makeVect (list (rd/makeList (list (rd/makeAtom "b") (rd/makeAtom "Bool"))))) (rd/makeAtom "->") (rd/makeAtom "Bool") (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "b"))))))]
    (and (verifyRoundtrip ast1 "inc function")
         (and (verifyRoundtrip ast2 "isZero function")
              (verifyRoundtrip ast3 "negate function"))))

fn runTests -> Bool
  (do
    (assert (testFunctionWithMatchRoundtrip) "testFunctionWithMatchRoundtrip passed")
    (assert (testMultiParamFunctionRoundtrip) "testMultiParamFunctionRoundtrip passed")
    (assert (testDotAccessRoundtrip) "testDotAccessRoundtrip passed")
    (assert (testInterpolationRoundtrip) "testInterpolationRoundtrip passed")
    (assert (testInlineListRoundtrip) "testInlineListRoundtrip passed")
    (assert (testSchemaRoundtrip) "testSchemaRoundtrip passed")
    (assert (testEnumRoundtrip) "testEnumRoundtrip passed")
    (assert (testVariedGeneratedAstRoundtrips) "testVariedGeneratedAstRoundtrips passed")
    true)
