(module asl-parser/roundtripPropertyTest
  :d "Property test verifying read(print(t)) == t round-trip preservation across ASTs."
  :x [runTests]
  :i [(indentPrinter :a ipr) (indentParser :a ip) (reader :a rd)])

(df verifyRoundtrip [(ast rd/SExpr) (name String)] -> Bool
  :d "Asserts that printing and re-parsing an AST yields structurally identical AST."
  (let [(printed (ipr/formatIndented ast))
        (reparsedRes (ip/parseIndented printed))]
    (mt reparsedRes
      ((ok reparsed)
       (let [(rOrig (rd/renderSexpr ast))
             (rReparsed (rd/renderSexpr reparsed))]
         (assert (= rOrig rReparsed)
                 (str "Roundtrip mismatch for " name ":\n  orig:     " rOrig "\n  printed:  " printed "\n  reparsed: " rReparsed))
         true))
      ((err msg)
       (assert false (str "Failed to re-parse printed AST for " name ": " msg "\nPrinted code:\n" printed))
       false))))

(df testFunctionRoundtrip [] -> Bool
  :d "Roundtrip test on function definition."
  (let [(ast (rd/makeList (list (rd/makeAtom "df")
                                (rd/makeAtom "area")
                                (rd/makeVect (list (rd/makeList (list (rd/makeAtom "s") (rd/makeAtom "Shape")))))
                                (rd/makeAtom "->")
                                (rd/makeAtom "Float")
                                (rd/makeList (list (rd/makeAtom "match")
                                                   (rd/makeAtom "s")
                                                   (rd/makeList (list (rd/makeList (list (rd/makeList (list (rd/makeAtom "Circle") (rd/makeAtom "r")))
                                                                                         (rd/makeList (list (rd/makeAtom "mul")
                                                                                                            (rd/makeAtom "pi")
                                                                                                            (rd/makeList (list (rd/makeAtom "mul")
                                                                                                                               (rd/makeAtom "r")
                                                                                                                               (rd/makeAtom "r"))))))))))))))]
    (verifyRoundtrip ast "function definition with match")))

(df testDotAccessRoundtrip [] -> Bool
  :d "Roundtrip test on compound dot access."
  (let [(ast (rd/makeList (list (rd/makeAtom ".-email")
                                (rd/makeList (list (rd/makeAtom ".-profile") (rd/makeAtom "user"))))))]
    (verifyRoundtrip ast "compound dot access")))

(df testInterpolationRoundtrip [] -> Bool
  :d "Roundtrip test on string interpolation."
  (let [(ast (rd/makeList (list (rd/makeAtom "str")
                                (rd/makeAtom "\"User: \"")
                                (rd/makeAtom "name")
                                (rd/makeAtom "\" logged in\""))))]
    (verifyRoundtrip ast "string interpolation")))

(df testInlineListRoundtrip [] -> Bool
  :d "Roundtrip test on inline list."
  (let [(ast (rd/makeList (list (rd/makeAtom "list")
                                (rd/makeAtom "1")
                                (rd/makeAtom "2")
                                (rd/makeAtom "3"))))]
    (verifyRoundtrip ast "inline list")))

(df testGeneratedAstRoundtrips [(count Int64)] -> Bool
  :d "Runs parameterized property roundtrips across synthesized AST variants."
  (let [(indices (string-chars (string-repeat "x" count)))]
    (let [(passed (fold (fn [(acc Bool) (_ String)] -> Bool
                          (if (not acc)
                            false
                            (let [(fnAst (rd/makeList (list (rd/makeAtom "df")
                                                            (rd/makeAtom "compute")
                                                            (rd/makeVect (list (rd/makeList (list (rd/makeAtom "n") (rd/makeAtom "Int")))))
                                                            (rd/makeAtom "->")
                                                            (rd/makeAtom "Int")
                                                            (rd/makeList (list (rd/makeAtom "add") (rd/makeAtom "n") (rd/makeAtom "1"))))))]
                              (verifyRoundtrip fnAst "synthesized function"))))
                        true
                        indices))]
      (assert passed "All generated AST property roundtrips must pass")
      true)))

(df runTests [] -> Bool
  :d "Runs roundtrip property test suite."
  (assert (testFunctionRoundtrip) "testFunctionRoundtrip passed")
  (assert (testDotAccessRoundtrip) "testDotAccessRoundtrip passed")
  (assert (testInterpolationRoundtrip) "testInterpolationRoundtrip passed")
  (assert (testInlineListRoundtrip) "testInlineListRoundtrip passed")
  (assert (testGeneratedAstRoundtrips 100) "100 generated property roundtrips passed")
  true)
