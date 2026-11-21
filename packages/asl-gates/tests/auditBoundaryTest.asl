(module asl-gates/tests/auditBoundaryTest
  :x [runTests]
  :i [(asl-gates/auditGates :a ag)])

; (:m :ref RED-AT-GATE :do "the package-boundary audit: a package source whose module header imports a tools/, tests/, harness/ or bench/ module is a finding, one inside asl/ is not, and the repository itself is clean")
fn ! runTests -> Bool
  (let [real (ag/boundaryCheck! ".")]
    (do (assert (ag/importsOutsideAsl? "(module asl-gates/x\n  :x [f]\n  :i [(tools/tests/base :a b)])\n\nfn f -> Int64 1") "an import rooted at tools/ is outside asl/")
        (assert (ag/importsOutsideAsl? "(module m :x [] :i [(asl-parser/lexer :a l) (harness/x :a h)])\n") "any import entry counts, not only the first")
        (refute (ag/importsOutsideAsl? "(module m :x [] :i [(asl-parser/lexer :a l) (asl-gates/gates :a g)])\n\nfn f -> String \"(tools/x)\"") "a package import is inside asl/ and a body string is not a header")
        (assert (= (listLength real) 1) "the real tree gives one pass row")
        (assert (= (optionOr (listHead (map (fn [(c ag/Check)] -> String c.status) real)) "") ":passed") "the repository has no new package import outside asl/")
        true))
