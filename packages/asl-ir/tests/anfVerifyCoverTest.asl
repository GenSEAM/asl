(module asl-ir/tests/anfVerifyCoverTest :x [runTests] :i [(asl-ir/types :a ir)])

; (:m :ref COVBATCH2 :do "verifyAnfStmt and verifyAnfFunction: each statement kind, the first diagnostic of a function wins")
fn codeOf d: (Option ir/IrDiag) -> String
  (match d ((some x) x.code) ((none) ""))

fn kindOf s: ir/IrStmt kind: String -> ir/IrStmt
  (with s :kind kind)

fn runTests -> Bool
  (let [(ty (ir/makeIrType "i64" "raw" false))
        (ret (ir/makeIrReturn "v" ty))
        (noRet (ir/makeIrReturn "" ty))
        (drop (ir/makeIrDrop "a" ty))
        (noDrop (ir/makeIrDrop "" ty))
        (letOk (with ret :kind "let" :target "x"))
        (letBad (with ret :kind "let" :target ""))
        (sw (ir/makeIrSwitch "s" (list) (list)))
        (swBad (ir/makeIrSwitch "" (list) (list)))
        (fnOf (fn [(name String) (body (List ir/IrStmt))] -> ir/IrFunction (ir/makeIrFunction name (list) ty body)))]
    (do
      (assert (none? (ir/verifyAnfStmt ret)) "a return with a value passes")
      (assert (= (codeOf (ir/verifyAnfStmt noRet)) "ERR_ANF_EMPTY_RETURN") "a return without a value fails")
      (assert (none? (ir/verifyAnfStmt drop)) "a drop with a target passes")
      (assert (= (codeOf (ir/verifyAnfStmt noDrop)) "ERR_ANF_EMPTY_DROP") "a drop without a target fails")
      (assert (none? (ir/verifyAnfStmt letOk)) "a let with a target passes")
      (assert (= (codeOf (ir/verifyAnfStmt letBad)) "ERR_ANF_EMPTY_TARGET") "a let without a target fails")
      (assert (none? (ir/verifyAnfStmt sw)) "a switch with a scrutinee passes")
      (assert (= (codeOf (ir/verifyAnfStmt swBad)) "ERR_ANF_EMPTY_SCRUTINEE") "a switch without a scrutinee fails")
      (assert (none? (ir/verifyAnfStmt (kindOf ret "store"))) "store passes")
      (assert (none? (ir/verifyAnfStmt (kindOf ret "jump"))) "jump passes")
      (assert (none? (ir/verifyAnfStmt (kindOf ret "loop"))) "loop passes")
      (assert (= (codeOf (ir/verifyAnfStmt (kindOf ret "bogus"))) "ERR_ANF_INVALID_STMT_KIND") "an unknown kind fails")
      (assert (match (ir/verifyAnfStmt (kindOf ret "bogus")) ((some d) (stringContains? d.message "bogus")) ((none) false)) "the message names the kind")
      (assert (none? (ir/verifyAnfFunction (fnOf "f" (list ret drop)))) "a clean function passes")
      (assert (none? (ir/verifyAnfFunction (fnOf "f" (list)))) "a function without statements passes")
      (assert (= (codeOf (ir/verifyAnfFunction (fnOf "" (list ret)))) "ERR_ANF_ANONYMOUS_FN") "an unnamed function fails")
      (assert (= (codeOf (ir/verifyAnfFunction (fnOf "f" (list ret noDrop)))) "ERR_ANF_EMPTY_DROP") "a bad statement fails the function")
      (assert (= (codeOf (ir/verifyAnfFunction (fnOf "f" (list noRet noDrop)))) "ERR_ANF_EMPTY_RETURN") "the first bad statement wins")
      true))
