(module asl-ir/tests/ssaPrimTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)])

fn raw name: String t: ty/SsaTy -> ty/SsaParam
  (ty/ssaParam name t)

fn prim dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opPrim name args))

fn moduleOf params: (List ty/SsaParam) instrs: (List ty/SsaInstr) result: String retTy: ty/SsaTy -> ty/SsaModule
  (ty/ssaModule "prims" (list) (list) (list) (list) (list)
    (list (ty/ssaFunction "f" (list) params retTy
            (list (ty/ssaBlock "entry" (list) instrs (ty/termReturn result))))))

fn mixedParams -> (List ty/SsaParam)
  (list (raw "i" (ty/tyI64)) (raw "j" (ty/tyI64)) (raw "x" (ty/tyF64)) (raw "y" (ty/tyF64)) (raw "p" (ty/tyI1)) (raw "q" (ty/tyI1)) (raw "v" (ty/tyVal))
        (raw "u" (ty/tyI32)) (raw "w" (ty/tyI32)) (raw "ptr1" (ty/tyPtr)))

fn verifyOne ins: ty/SsaInstr -> (Result Unit (List ty/IrDiag))
  (vfy/verifySsa (moduleOf (mixedParams) (list ins) ins.dest ins.ty))

fn codes res: (Result Unit (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err diags) (map (fn [(d ty/IrDiag)] -> String d.code) diags)))

fn accepts? ins: ty/SsaInstr -> Bool
  (ok? (verifyOne ins))

fn rejects? ins: ty/SsaInstr code: String -> Bool
  (listContains? (codes (verifyOne ins)) code)

fn testWellTyped -> Bool
  (do (assert (accepts? (prim "r" (ty/tyI64) "addInt" (list "i" "j"))) "addInt i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "subInt" (list "i" "j"))) "subInt i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "mulInt" (list "i" "j"))) "mulInt i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "quotInt" (list "i" "j"))) "quotInt i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "remInt" (list "i" "j"))) "remInt i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI1) "ltInt" (list "i" "j"))) "ltInt i64 i64 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "geInt" (list "i" "j"))) "geInt i64 i64 -> i1")
      (assert (accepts? (prim "r" (ty/tyF64) "divFloat" (list "x" "y"))) "divFloat f64 f64 -> f64")
      (assert (accepts? (prim "r" (ty/tyI1) "neFloat" (list "x" "y"))) "neFloat f64 f64 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "andBool" (list "p" "q"))) "andBool i1 i1 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "notBool" (list "p"))) "notBool i1 -> i1")
      (assert (accepts? (prim "r" (ty/tyF64) "intToFloat" (list "i"))) "intToFloat i64 -> f64")
      (assert (accepts? (prim "r" (ty/tyI64) "floatToInt" (list "x"))) "floatToInt f64 -> i64")
      true)

fn testMixedRejected -> Bool
  (do (assert (rejects? (prim "r" (ty/tyI64) "addInt" (list "i" "x")) "ERR_IR_TYPE_MISMATCH") "addInt of i64 and f64 is rejected: Int and Float never mix")
      (assert (rejects? (prim "r" (ty/tyF64) "addFloat" (list "x" "i")) "ERR_IR_TYPE_MISMATCH") "addFloat of f64 and i64 is rejected")
      (assert (rejects? (prim "r" (ty/tyI1) "ltInt" (list "x" "y")) "ERR_IR_TYPE_MISMATCH") "ltInt of two f64 is rejected")
      (assert (rejects? (prim "r" (ty/tyI1) "andBool" (list "p" "i")) "ERR_IR_TYPE_MISMATCH") "andBool of i1 and i64 is rejected")
      (assert (rejects? (prim "r" (ty/tyF64) "intToFloat" (list "x")) "ERR_IR_TYPE_MISMATCH") "intToFloat of an f64 is rejected")
      true)

fn testValRejected -> Bool
  (do (assert (rejects? (prim "r" (ty/tyI64) "addInt" (list "i" "v")) "ERR_IR_TYPE_MISMATCH") "a Val operand is rejected: primitives are raw only")
      (assert (rejects? (prim "r" (ty/tyI1) "notBool" (list "v")) "ERR_IR_TYPE_MISMATCH") "notBool of a Val is rejected")
      (assert (rejects? (prim "r" (ty/tyVal) "addInt" (list "i" "j")) "ERR_IR_TYPE_MISMATCH") "a Val result is rejected")
      true)

fn testResultAndArity -> Bool
  (do (assert (rejects? (prim "r" (ty/tyI64) "ltInt" (list "i" "j")) "ERR_IR_TYPE_MISMATCH") "a compare yields i1, not i64")
      (assert (rejects? (prim "r" (ty/tyF64) "addInt" (list "i" "j")) "ERR_IR_TYPE_MISMATCH") "addInt yields i64, not f64")
      (assert (rejects? (prim "r" (ty/tyI64) "addInt" (list "i")) "ERR_IR_ARITY") "addInt with one operand is an arity error")
      (assert (rejects? (prim "r" (ty/tyI1) "notBool" (list "p" "q")) "ERR_IR_ARITY") "notBool with two operands is an arity error")
      (assert (= (codes (verifyOne (prim "r" (ty/tyI64) "powInt" (list "i" "j")))) (list "ERR_IR_UNKNOWN_PRIM")) "an unknown primitive name is rejected")
      (assert (= (codes (verifyOne (prim "r" (ty/tyI64) "addInt" (list "i" "ghost")))) (list "ERR_IR_UNDEFINED_VALUE")) "prim operands are uses: an undefined one is reported")
      true)

fn testDominance -> Bool
  (let [(m (ty/ssaModule "prims" (list) (list) (list) (list) (list)
             (list (ty/ssaFunction "f" (list) (list (raw "i" (ty/tyI64))) (ty/tyI64)
                     (list (ty/ssaBlock "entry" (list)
                             (list (prim "s" (ty/tyI64) "addInt" (list "i" "t"))
                                   (prim "t" (ty/tyI64) "addInt" (list "i" "i")))
                             (ty/termReturn "s")))))))]
    (do (assert (= (codes (vfy/verifySsa m)) (list "ERR_IR_UNDEFINED_VALUE")) "a prim operand defined later in the block is a use before definition")
        true))

fn testPrinter -> Bool
  (let [(m (moduleOf (mixedParams)
             (list (prim "s" (ty/tyI64) "addInt" (list "i" "j"))
                   (prim "c" (ty/tyI1) "ltFloat" (list "x" "y"))
                   (prim "n" (ty/tyI1) "notBool" (list "c")))
             "s" (ty/tyI64)))
        (text (prn/printSsa m))]
    (do (assert (ok? (vfy/verifySsa m)) "the printed module verifies")
        (assert (stringContains? text "(let s i64 (prim addInt i j))") "addInt prints with its operands")
        (assert (stringContains? text "(let c i1 (prim ltFloat x y))") "ltFloat prints")
        (assert (stringContains? text "(let n i1 (prim notBool c))") "notBool prints")
        true))

fn testRawWellTyped -> Bool
  (do (assert (accepts? (prim "r" (ty/tyI64) "rawAddI64" (list "i" "j"))) "rawAddI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawSubI64" (list "i" "j"))) "rawSubI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawMulI64" (list "i" "j"))) "rawMulI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawAndI64" (list "i" "j"))) "rawAndI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawOrI64" (list "i" "j"))) "rawOrI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawXorI64" (list "i" "j"))) "rawXorI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawShlI64" (list "i" "j"))) "rawShlI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawLshrI64" (list "i" "j"))) "rawLshrI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI64) "rawAshrI64" (list "i" "j"))) "rawAshrI64 i64 i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI32) "rawAddI32" (list "u" "w"))) "rawAddI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawSubI32" (list "u" "w"))) "rawSubI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawMulI32" (list "u" "w"))) "rawMulI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawAndI32" (list "u" "w"))) "rawAndI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawOrI32" (list "u" "w"))) "rawOrI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawXorI32" (list "u" "w"))) "rawXorI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawShlI32" (list "u" "w"))) "rawShlI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawLshrI32" (list "u" "w"))) "rawLshrI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawAshrI32" (list "u" "w"))) "rawAshrI32 i32 i32 -> i32")
      (assert (accepts? (prim "r" (ty/tyI1) "rawEqI32" (list "u" "w"))) "rawEqI32 i32 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawNeI32" (list "u" "w"))) "rawNeI32 i32 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawLtI32" (list "u" "w"))) "rawLtI32 i32 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawLeI32" (list "u" "w"))) "rawLeI32 i32 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawGtI32" (list "u" "w"))) "rawGtI32 i32 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawGeI32" (list "u" "w"))) "rawGeI32 i32 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI64) "rawWidenI32" (list "u"))) "rawWidenI32 i32 -> i64")
      (assert (accepts? (prim "r" (ty/tyI32) "rawNarrowI32" (list "i"))) "rawNarrowI32 i64 -> i32")
      (assert (accepts? (prim "r" (ty/tyI1) "rawPtrIsNull" (list "ptr1"))) "rawPtrIsNull ptr -> i1")
      (assert (accepts? (prim "r" (ty/tyI64) "rawPtrToInt" (list "ptr1"))) "rawPtrToInt ptr -> i64")
      (assert (accepts? (prim "r" (ty/tyPtr) "rawIntToPtr" (list "i"))) "rawIntToPtr i64 -> ptr")
      (assert (accepts? (prim "r" (ty/tyI32) "rawLoadI8" (list "ptr1" "i"))) "rawLoadI8 ptr i64 -> i32")
      (assert (accepts? (prim "r" (ty/tyI32) "rawLoadI32" (list "ptr1" "i"))) "rawLoadI32 ptr i64 -> i32")
      (assert (accepts? (prim "r" (ty/tyI64) "rawLoadI64" (list "ptr1" "i"))) "rawLoadI64 ptr i64 -> i64")
      (assert (accepts? (prim "r" (ty/tyI1) "rawStoreI8" (list "ptr1" "i" "u"))) "rawStoreI8 ptr i64 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawStoreI32" (list "ptr1" "i" "u"))) "rawStoreI32 ptr i64 i32 -> i1")
      (assert (accepts? (prim "r" (ty/tyI1) "rawStoreI64" (list "ptr1" "i" "j"))) "rawStoreI64 ptr i64 i64 -> i1")
      true)

fn testRawRejected -> Bool
  (do (assert (rejects? (prim "r" (ty/tyI32) "rawAddI32" (list "u" "i")) "ERR_IR_TYPE_MISMATCH") "rawAddI32 of i32 and i64 is rejected")
      (assert (rejects? (prim "r" (ty/tyI64) "rawAddI64" (list "u" "w")) "ERR_IR_TYPE_MISMATCH") "rawAddI64 of two i32 is rejected: result must be i64 but operands are i32")
      (assert (rejects? (prim "r" (ty/tyI1) "rawEqI32" (list "i" "j")) "ERR_IR_TYPE_MISMATCH") "rawEqI32 of two i64 is rejected")
      (assert (rejects? (prim "r" (ty/tyI32) "rawWidenI32" (list "u")) "ERR_IR_TYPE_MISMATCH") "rawWidenI32 yields i64, not i32")
      (assert (rejects? (prim "r" (ty/tyI64) "rawNarrowI32" (list "i")) "ERR_IR_TYPE_MISMATCH") "rawNarrowI32 yields i32, not i64")
      (assert (rejects? (prim "r" (ty/tyI1) "rawPtrIsNull" (list "i")) "ERR_IR_TYPE_MISMATCH") "rawPtrIsNull of an i64 is rejected: not a ptr")
      (assert (rejects? (prim "r" (ty/tyI64) "rawIntToPtr" (list "i")) "ERR_IR_TYPE_MISMATCH") "rawIntToPtr yields ptr, not i64")
      (assert (rejects? (prim "r" (ty/tyPtr) "rawIntToPtr" (list "ptr1")) "ERR_IR_TYPE_MISMATCH") "rawIntToPtr takes an i64, not a ptr")
      (assert (rejects? (prim "r" (ty/tyI32) "rawLoadI32" (list "ptr1" "ptr1")) "ERR_IR_TYPE_MISMATCH") "rawLoadI32 offset must be i64, not ptr")
      (assert (rejects? (prim "r" (ty/tyI1) "rawStoreI32" (list "ptr1" "i" "j")) "ERR_IR_TYPE_MISMATCH") "rawStoreI32 value must be i32, not i64")
      (assert (rejects? (prim "r" (ty/tyI1) "rawStoreI8" (list "ptr1" "i")) "ERR_IR_ARITY") "rawStoreI8 with two operands is an arity error: it takes ptr, offset and value")
      true)

fn runTests -> Bool
  (do (assert (testWellTyped) "testWellTyped")
      (assert (testMixedRejected) "testMixedRejected")
      (assert (testValRejected) "testValRejected")
      (assert (testResultAndArity) "testResultAndArity")
      (assert (testDominance) "testDominance")
      (assert (testPrinter) "testPrinter")
      (assert (testRawWellTyped) "testRawWellTyped")
      (assert (testRawRejected) "testRawRejected")
      true)
