(module asl-ir/tests/externNativeTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)])

fn mkParam name: String -> ty/SsaParam
  (ty/ssaParam name (ty/tyVal))

fn letTy dest: String t: ty/SsaTy op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest t op)

fn intConst dest: String t: ty/SsaTy n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opConst (ty/constInt n)))

fn strConst dest: String t: ty/SsaTy i: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opConst (ty/constStr i)))

fn mkBlock label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn simpleFn name: String retTy: ty/SsaTy blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction name (list) (list) retTy blocks)

fn paramFn name: String params: (List String) retTy: ty/SsaTy instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaFunction
  (ty/ssaFunction name (list) (map mkParam params) retTy (list (mkBlock "entry" instrs term)))

fn oneBlockFn name: String retTy: ty/SsaTy instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaFunction
  (simpleFn name retTy (list (mkBlock "entry" instrs term)))

fn moduleOf strings: (List String) externs: (List ty/SsaExtern) functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" strings (list) (list) externs (list) functions)

fn codes res: (Result Unit (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err diags) (map (fn [(d ty/IrDiag)] -> String d.code) diags)))

fn getpidModule -> ty/SsaModule
  (moduleOf (list) (list (ty/ssaExternTyped "getpid" (list) (ty/tyI32)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (letTy "pid" (ty/tyI32) (ty/opCall "getpid" (list)))
                  (intConst "zero" (ty/tyI64) 0))
            (ty/termReturn "zero"))))

fn writeModule -> ty/SsaModule
  (moduleOf (list "ok\n") (list (ty/ssaExternTyped "write" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (intConst "fd" (ty/tyI32) 1)
                  (strConst "msg" (ty/tyPtr) 0)
                  (intConst "len" (ty/tyI64) 3)
                  (letTy "n" (ty/tyI64) (ty/opCall "write" (list "fd" "msg" "len"))))
            (ty/termReturn "n"))))

fn openModule flagsVal: Int64 modeVal: Int64 -> ty/SsaModule
  (moduleOf (list "/tmp/externNativeTest.path") (list (ty/ssaExternVariadic "open" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (strConst "path" (ty/tyPtr) 0)
                  (intConst "flags" (ty/tyI32) flagsVal)
                  (intConst "mode" (ty/tyI32) modeVal)
                  (letTy "fd" (ty/tyI32) (ty/opCall "open" (list "path" "flags" "mode")))
                  (intConst "zero" (ty/tyI64) 0))
            (ty/termReturn "zero"))))

fn openTooFewModule -> ty/SsaModule
  (moduleOf (list "/tmp/externNativeTest.path") (list (ty/ssaExternVariadic "open" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (strConst "path" (ty/tyPtr) 0)
                  (letTy "fd" (ty/tyI32) (ty/opCall "open" (list "path")))
                  (intConst "zero" (ty/tyI64) 0))
            (ty/termReturn "zero"))))

fn openVariadicBoolModule -> ty/SsaModule
  (moduleOf (list "/tmp/externNativeTest.path") (list (ty/ssaExternVariadic "open" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (strConst "path" (ty/tyPtr) 0)
                  (intConst "flags" (ty/tyI32) 0)
                  (ty/ssaInstr "bit" (ty/tyI1) (ty/opConst (ty/constBool true)))
                  (letTy "fd" (ty/tyI32) (ty/opCall "open" (list "path" "flags" "bit")))
                  (intConst "zero" (ty/tyI64) 0))
            (ty/termReturn "zero"))))

fn openVariadicValModule -> ty/SsaModule
  (moduleOf (list "/tmp/externNativeTest.path") (list (ty/ssaExternVariadic "open" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (strConst "path" (ty/tyPtr) 0)
                  (intConst "flags" (ty/tyI32) 0)
                  (ty/ssaInstr "boxed" (ty/tyVal) (ty/opConst (ty/constUnit)))
                  (letTy "fd" (ty/tyI32) (ty/opCall "open" (list "path" "flags" "boxed")))
                  (intConst "zero" (ty/tyI64) 0))
            (ty/termReturn "zero"))))

fn i32OutOfRangeModule -> ty/SsaModule
  (moduleOf (list) (list)
    (list (oneBlockFn "run" (ty/tyI32)
            (list (intConst "big" (ty/tyI32) 2147483648))
            (ty/termReturn "big"))))

fn writeMismatchModule -> ty/SsaModule
  (moduleOf (list "ok\n") (list (ty/ssaExternTyped "write" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (intConst "fd" (ty/tyI32) 1)
                  (strConst "msg" (ty/tyVal) 0)
                  (intConst "len" (ty/tyI64) 3)
                  (letTy "n" (ty/tyI64) (ty/opCall "write" (list "fd" "msg" "len"))))
            (ty/termReturn "n"))))

fn boxPtrModule -> ty/SsaModule
  (moduleOf (list "x") (list)
    (list (oneBlockFn "run" (ty/tyVal)
            (list (strConst "p" (ty/tyPtr) 0)
                  (letTy "boxed" (ty/tyVal) (ty/opBox "p")))
            (ty/termReturn "boxed"))))

fn unboxToI32Module -> ty/SsaModule
  (moduleOf (list) (list)
    (list (paramFn "run" (list "v") (ty/tyI32)
            (list (letTy "u" (ty/tyI32) (ty/opUnbox "v")))
            (ty/termReturn "u"))))

fn testTypesRoundTrip -> Bool
  (do (assert (= (ty/ssaTyName (ty/tyPtr)) "ptr") "ssaTyName of tyPtr is \"ptr\"")
      (assert (= (ty/ssaTyName (ty/tyI32)) "i32") "ssaTyName of tyI32 is \"i32\"")
      (assert (ty/ssaIsRaw? (ty/tyPtr)) "tyPtr is raw")
      (assert (ty/ssaIsRaw? (ty/tyI32)) "tyI32 is raw")
      true)

fn testTypedExterns -> Bool
  (do (assert (= (codes (vfy/verifySsa (getpidModule))) (list)) "getpid() -> i32 verifies")
      (assert (= (codes (vfy/verifySsa (writeModule))) (list)) "write(i32, ptr, i64) -> i64 verifies")
      true)

fn testVariadic -> Bool
  (do (assert (= (codes (vfy/verifySsa (openModule 513 384))) (list)) "open(ptr, i32, ...) with a third argument past arity 2 verifies")
      (assert (= (codes (vfy/verifySsa (openTooFewModule))) (list "ERR_IR_ARITY")) "open called with fewer than its declared arity is ERR_IR_ARITY")
      (assert (= (codes (vfy/verifySsa (openVariadicBoolModule))) (list "ERR_IR_TYPE_MISMATCH")) "an i1 past arity is rejected: no C default promotion for i1 in ...")
      (assert (= (codes (vfy/verifySsa (openVariadicValModule))) (list "ERR_IR_TYPE_MISMATCH")) "a val past arity is rejected: no C default promotion for val in ...")
      true)

fn testMismatch -> Bool
  (do (assert (= (codes (vfy/verifySsa (writeMismatchModule))) (list "ERR_IR_TYPE_MISMATCH")) "write's ptr parameter rejects a val argument")
      (assert (= (codes (vfy/verifySsa (boxPtrModule))) (list "ERR_IR_TYPE_MISMATCH")) "opBox of a raw ptr is rejected")
      (assert (= (codes (vfy/verifySsa (unboxToI32Module))) (list "ERR_IR_TYPE_MISMATCH")) "opUnbox to i32 is rejected")
      (assert (= (codes (vfy/verifySsa (i32OutOfRangeModule))) (list "ERR_IR_TYPE_MISMATCH")) "an i32 constant past INT32_MAX is rejected")
      true)

fn ! runTests -> Bool
  (do (assert (testTypesRoundTrip) "testTypesRoundTrip")
      (assert (testTypedExterns) "testTypedExterns")
      (assert (testVariadic) "testVariadic")
      (assert (testMismatch) "testMismatch")
      true)
