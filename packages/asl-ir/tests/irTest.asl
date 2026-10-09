(module asl-ir/tests/irTest
  :x [testLoweringOptions testVerifyDetectsUnterminatedBlock testVerifyPassesValidFunction testVerifyCatchesUnboundVar testVerifyCatchesBufEscape testAstPatchOperations testAstDigest runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lowering :a low)
      (asl-ir/verify :a vfy)
      (asl-ir/patch :a patch)
      (asl-ir/main :a ir)])

fn testLoweringOptions -> Bool
  (do
    (assert (= (ir/assignOptionRepr "c11" "str") "nullable") "c11 str is nullable")
    (refute (= (ir/assignOptionRepr "c11" "str") "tagged") "c11 str refutes tagged")
    (assert (= (ir/assignOptionRepr "c11" "unit") "tagged") "c11 unit is tagged")
    (assert (= (ir/assignOptionRepr "c11" "i64") "tagged") "c11 i64 is tagged")
    (assert (= (ir/assignOptionRepr "wasm" "str") "tagged") "wasm str is tagged")
    (refute (= (ir/assignOptionRepr "wasm" "str") "nullable") "wasm str refutes nullable")
    (assert (= (ir/assignOptionRepr "py" "i64") "nullable") "py i64 is nullable")
    (assert (= (ir/assignOptionRepr "py" "unit") "tagged") "py unit is tagged")
    (assert (= (ir/assignOptionRepr "ts" "buf") "nullable") "ts buf is nullable")
    true)

fn testVerifyDetectsUnterminatedBlock -> Bool
  (let [(f (ty/makeIrFunction "emptyFn" (list) (ty/makeIrType "unit" "raw" false) (list)))
        (m (ty/makeIrModule "mod1" "c11" (list f)))
        (res (ir/verifyIr m))]
    (do
      (assert (err? res) "empty function is error")
      (refute (ok? res) "unterminated block refutes ok")
      (mt res
        ((ok _) false)
        ((err diags)
          (do
            (assert (= (listLength diags) 1) "exactly 1 diagnostic")
            (mt (listHead diags)
              ((some d) (assert (= d.code "ERR_IR_UNTERMINATED_BLOCK") "code matches"))
              ((none) (assert false "expected diagnostic")))
            true)))))

fn testVerifyPassesValidFunction -> Bool
  (let [(p (ty/makeIrParam "x" (ty/makeIrType "i64" "raw" false)))
        (ret (ty/makeIrReturn "x" (ty/makeIrType "i64" "raw" false)))
        (f (ty/makeIrFunction "idFn" (list p) (ty/makeIrType "i64" "raw" false) (list ret)))
        (m (ty/makeIrModule "modValid" "c11" (list f)))
        (res (ir/verifyIr m))]
    (do
      (assert (ok? res) "valid function verifies cleanly")
      (refute (err? res) "valid function refutes err")
      true))

fn testVerifyCatchesUnboundVar -> Bool
  (let [(ret (ty/makeIrReturn "unboundVar" (ty/makeIrType "i64" "raw" false)))
        (f (ty/makeIrFunction "badFn" (list) (ty/makeIrType "i64" "raw" false) (list ret)))
        (m (ty/makeIrModule "modBad" "c11" (list f)))
        (res (ir/verifyIr m))]
    (do
      (assert (err? res) "unbound var is error")
      (refute (ok? res) "unbound var refutes ok")
      (mt res
        ((ok _) false)
        ((err diags)
          (do
            (assert (>= (listLength diags) 1) "at least 1 diagnostic")
            (mt (listHead diags)
              ((some d) (assert (= d.code "ERR_IR_UNBOUND_VAR") "error is ERR_IR_UNBOUND_VAR"))
              ((none) (assert false "expected diagnostic")))
            true)))))

fn testVerifyCatchesBufEscape -> Bool
  (let [(bufTy (ty/makeIrType "buf" "raw" true))
        (p (ty/makeIrParam "b" bufTy))
        (ret (ty/makeIrReturn "b" bufTy))
        (f (ty/makeIrFunction "escapeFn" (list p) bufTy (list ret)))
        (m (ty/makeIrModule "modEscape" "c11" (list f)))
        (res (ir/verifyIr m))]
    (do
      (assert (err? res) "buffer escape is error")
      (refute (ok? res) "buffer escape refutes ok")
      (mt res
        ((ok _) false)
        ((err diags)
          (do
            (assert (>= (listLength diags) 1) "at least 1 diagnostic")
            (mt (listHead diags)
              ((some d) (assert (= d.code "ERR_IR_BUF_ESCAPE") "error is ERR_IR_BUF_ESCAPE"))
              ((none) (assert false "expected diagnostic")))
            true)))))

fn testAstPatchOperations -> Bool
  (let [(p (ir/makeReplacePatch "patch1" "my/mod" "mySym" "anchor1" "(+ 1 2)" "(+ 1 3)"))]
    (do
      (assert (= p.id "patch1") "patch id")
      (refute (!= p.id "patch1") "patch id refutes divergence")
      (assert (= p.targetModule "my/mod") "targetModule")
      (assert (= (listLength p.ops) 1) "1 op")
      (let [(inv (ir/invertPatch p))]
        (do
          (assert (= (str inv.id) "patch1:inv") "inverted patch id")
          (assert (= (listLength inv.ops) 1) "1 inverted op")
          true))))

fn testAstDigest -> Bool
  (let [(d1 (patch/computeAstDigest "(module foo)"))
        (d2 (patch/computeAstDigest "(module bar)"))]
    (do
      (assert (stringStartsWith? d1 "d") "digest starts with d")
      (assert (!= d1 d2) "digests differ for different ASTs")
      (refute (= d1 d2) "different ASTs refute identical digest")
      true))

fn runTests -> Bool
  (do
    (assert (testLoweringOptions) "testLoweringOptions")
    (assert (testVerifyDetectsUnterminatedBlock) "testVerifyDetectsUnterminatedBlock")
    (assert (testVerifyPassesValidFunction) "testVerifyPassesValidFunction")
    (assert (testVerifyCatchesUnboundVar) "testVerifyCatchesUnboundVar")
    (assert (testVerifyCatchesBufEscape) "testVerifyCatchesBufEscape")
    (assert (testAstPatchOperations) "testAstPatchOperations")
    (assert (testAstDigest) "testAstDigest")
    true)
