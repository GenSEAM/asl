(module asl/packages/asl-mesh/tests/scannerTest :x [runTests] :i [(asl-mesh/scanner :a scan) (asl-parser/reader :a rd)])

fn testScannerVacuous -> Bool
  (let [(vacuousSrc "(df test [] -> Bool (assert (= 1 1) \"always\"))") (defects (scan/checkVacuousTests vacuousSrc "test.asl")) (firstDefect (optionOr (listGet defects 0) mapEmpty))] (assert (= (listLength defects) 1) "One vacuous defect found") (assert (= firstDefect.defectId "def-vacuous-1") "Defect ID matches") (refute (= (listLength defects) 0) "Defects list is not empty") true)

fn testScannerAstVisitor -> Bool
  (let [(atom (rd/makeAtom "foo")) (lst (rd/makeList (list atom))) (res (scan/astVisitor lst (fn [(n rd/SExpr)] -> (List Map) (list {:visited 1})))) (emptyRes (scan/astVisitor lst (fn [(n rd/SExpr)] -> (List Map) (list))))] (assert (= res.visited 2) "Visitor covers the list and its atom") (refute (!= res.visited 2) "Visited count refutes missed AST nodes") (assert (= emptyRes.visited 0) "Empty visitor result counts zero") true)

fn runTests -> Bool
  (let [(r1 (testScannerVacuous)) (r2 (testScannerAstVisitor))] (assert (and r1 r2) "All scanner tests pass") true)
