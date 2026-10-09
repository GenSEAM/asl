(module asl-ir/tests/printerTest
  :x [testPrintExprCall testPrintStmtCall runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/printer :a prn)])

fn testPrintExprCall -> Bool
  (let [(e (ty/IrExpr :kind "call" :op "calculate" :left "" :right "" :args (list "x" "y") :ty (ty/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))]
    (do
      (assert (= (prn/printExpr e) "(ir/call calculate [x y])") "printExpr call uses op field as callee")
      true))

fn testPrintStmtCall -> Bool
  (let [(e (ty/IrExpr :kind "call" :op "calculate" :left "" :right "" :args (list "x" "y") :ty (ty/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (s (ty/makeIrLet "res" (ty/makeIrType "i64" "raw" false) e))]
    (do
      (assert (= (prn/printStmt s) "  (ir/let res (ir/type :i64) (ir/call calculate [x y]))") "printStmt renders let with call expr")
      true))

fn runTests -> Bool
  (do
    (assert (testPrintExprCall) "testPrintExprCall")
    (assert (testPrintStmtCall) "testPrintStmtCall")
    true)
