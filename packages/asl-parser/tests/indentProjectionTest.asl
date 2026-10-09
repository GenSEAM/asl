(module asl/packages/asl-parser/tests/indentProjectionTest
  :x [runTests RunTests testIndentedFunctionProjection testIndentedLetProjection testRoundtripProjectionProperty testDualPolarityProbes]
  :i [(asl-parser/reader :a rd)
      (asl-parser/indentPrinter :a ip)
      (asl-parser/astPrinter :a ap)
      (asl-parser/astConverter :a cv)])

fn testIndentedFunctionProjection -> Bool
  (let [(fnSexpr (rd/makeList (list
                    (rd/makeAtom "fn")
                    (rd/makeAtom "multiply")
                    (rd/makeList (list
                      (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "I64")))
                      (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "I64")))))
                    (rd/makeAtom "->")
                    (rd/makeAtom "I64")
                    (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "x") (rd/makeAtom "y"))))))
        (projected (ip/formatIndented fnSexpr))]
    (assert (> (stringLength projected) 0) "projected function is non-empty")
    (refute (= (stringLength projected) 0) "projected function refutes empty string")
    (assert (stringStartsWith? projected "fn multiply x: I64 y: I64 -> I64") "projected signature matches indented syntax")
    (refute (stringContains? projected "(fn multiply") "projected function refutes raw enclosing parens on fn")
    (let [(topRes (cv/sexprToTopForm fnSexpr))]
      (assert (ok? topRes) "sexprToTopForm succeeds on pure Dyck-1 defun")
      (mt topRes
        ((ok tf)
          (let [(rendered (ap/printTopForm tf))]
            (assert (stringContains? rendered "fn multiply") "astPrinter renders modern fn multiply")
            (refute (stringContains? rendered "df multiply") "astPrinter refutes legacy df multiply")))
        ((err _) (assert false "failed sexprToTopForm")))))
  true

fn testIndentedLetProjection -> Bool
  (let [(letSexpr (rd/makeList (list
                    (rd/makeAtom "let")
                    (rd/makeList (list
                      (rd/makeList (list (rd/makeAtom "val") (rd/makeAtom "100")))))
                    (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "val") (rd/makeAtom "1"))))))
        (letAst (cv/liftExpr letSexpr))
        (printed (ap/printAstExpr letAst 0))]
    (assert (> (stringLength printed) 0) "printed let expression is non-empty")
    (refute (= (stringLength printed) 0) "printed let expression refutes empty string")
    (assert (stringContains? printed "(let ((val 100))") "printed let has canonical binding")
    (refute (stringContains? printed "(let [") "printed let refutes legacy bracketed vector"))
  true

fn testRoundtripProjectionProperty -> Bool
  (let [(exprSexpr (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "1") (rd/makeAtom "2"))))
        (ast (cv/liftExpr exprSexpr))
        (lowered (cv/lowerExpr ast))]
    (assert (rd/isList? lowered) "lowered expression is sexprList")
    (refute (not (rd/isList? lowered)) "lowered expression refutes non-list")
    (assert (= (rd/sexprHead lowered) "+") "head symbol matches +")
    (refute (!= (rd/sexprHead lowered) "+") "head symbol refutes mismatch"))
  true

fn testDualPolarityProbes -> Bool
  (let [(emptyList (rd/makeList (list)))
        (renderedEmpty (ip/formatIndented emptyList))]
    (assert (= renderedEmpty "()") "empty list projects to ()")
    (refute (!= renderedEmpty "()") "empty list refutes non-unit string"))
  (let [(atomSexpr (rd/makeAtom "standaloneAtom"))
        (renderedAtom (ip/formatIndented atomSexpr))]
    (assert (= renderedAtom "standaloneAtom") "atom projects to its string value")
    (refute (!= renderedAtom "standaloneAtom") "atom refutes wrong value"))
  true

fn runTests -> Bool
  (do
    (assert (testIndentedFunctionProjection) "testIndentedFunctionProjection passed")
    (assert (testIndentedLetProjection) "testIndentedLetProjection passed")
    (assert (testRoundtripProjectionProperty) "testRoundtripProjectionProperty passed")
    (assert (testDualPolarityProbes) "testDualPolarityProbes passed")
    true)

fn RunTests -> Bool
  (runTests)
