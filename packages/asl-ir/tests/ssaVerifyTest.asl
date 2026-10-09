(module asl-ir/tests/ssaVerifyTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)])

fn mkParam name: String -> ty/SsaParam
  (ty/ssaParam name (ty/tyVal))

fn letVal dest: String op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) op)

fn intConst dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opConst (ty/constInt n)))

fn mkRet name: String -> ty/SsaTerm
  (ty/termReturn name)

fn mkJump target: String args: (List String) -> ty/SsaTerm
  (ty/termJump (ty/ssaEdge target args))

fn mkBlock label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn simpleFn name: String params: (List String) blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction name (list) (map mkParam params) (ty/tyVal) blocks)

fn shapeType -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Shape" (list (ty/ssaVariant "circle" 1) (ty/ssaVariant "square" 1) (ty/ssaVariant "empty" 0)))

fn moduleOf functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" (list "hello" "line\n\"quoted\" \\") (list (shapeType)) (list (ty/ssaRecordDecl "Point" (list "x" "y"))) (list (ty/ssaExtern "net/fetch" 2)) (list) functions)

fn codes res: (Result Unit (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err diags) (map (fn [(d ty/IrDiag)] -> String d.code) diags)))

fn onlyCode res: (Result Unit (List ty/IrDiag)) code: String -> Bool
  (= (codes res) (list code))

fn adderFn -> ty/SsaFunction
  (ty/ssaFunction "adder" (list (mkParam "n")) (list (mkParam "x")) (ty/tyVal)
    (list (mkBlock "entry" (list (letVal "sum" (ty/opBuiltin "+" (list "n" "x")))) (mkRet "sum"))))

fn closureModule -> ty/SsaModule
  (moduleOf (list (adderFn)
    (simpleFn "main" (list)
      (list (mkBlock "entry"
        (list (intConst "five" 5)
              (letVal "addFive" (ty/opMakeClosure "adder" (list "five")))
              (intConst "one" 1)
              (letVal "six" (ty/opCallClosure "addFive" (list "one"))))
        (mkRet "six"))))))

fn ctorModule -> ty/SsaModule
  (moduleOf (list
    (simpleFn "makeShapes" (list)
      (list (mkBlock "entry"
        (list (ty/ssaInstr "radius" (ty/tyVal) (ty/opConst (ty/constFloat 1.5)))
              (letVal "circle" (ty/opConstruct "Shape" "circle" (list "radius")))
              (letVal "empty" (ty/opConstruct "Shape" "empty" (list)))
              (intConst "x" 3)
              (intConst "y" 4)
              (letVal "point" (ty/opRecord "Point" (list "x" "y") (list "x" "y")))
              (letVal "px" (ty/opField "point" "x"))
              (letVal "all" (ty/opList (list "circle" "empty" "point" "px"))))
        (mkRet "all"))))))

fn switchFn name: String cases: (List ty/SsaCase) fallback: (Option ty/SsaEdge) -> ty/SsaFunction
  (simpleFn name (list "shape")
    (list (mkBlock "entry" (list (intConst "zero" 0)) (ty/termSwitch "shape" "Shape" cases fallback))
          (mkBlock "onCircle" (list (letVal "r" (ty/opVariantField "shape" 0))) (mkJump "join" (list "r")))
          (mkBlock "onSquare" (list (letVal "side" (ty/opVariantField "shape" 0))) (mkJump "join" (list "side")))
          (mkBlock "onEmpty" (list) (mkJump "join" (list "zero")))
          (ty/ssaBlock "join" (list (mkParam "result")) (list (letVal "tagged" (ty/opList (list "result" "zero")))) (mkRet "tagged"))))

fn allCases -> (List ty/SsaCase)
  (list (ty/ssaCase "circle" (ty/ssaEdge "onCircle" (list)))
        (ty/ssaCase "square" (ty/ssaEdge "onSquare" (list)))
        (ty/ssaCase "empty" (ty/ssaEdge "onEmpty" (list))))

fn partialCases -> (List ty/SsaCase)
  (list (ty/ssaCase "circle" (ty/ssaEdge "onCircle" (list)))
        (ty/ssaCase "square" (ty/ssaEdge "onSquare" (list))))

fn stringModule -> ty/SsaModule
  (moduleOf (list
    (simpleFn "greet" (list)
      (list (mkBlock "entry"
        (list (letVal "text" (ty/opConst (ty/constStr 1)))
              (letVal "size" (ty/opBuiltin "stringLength" (list "text")))
              (letVal "tag" (ty/opConst (ty/constKeyword "ok")))
              (letVal "unit" (ty/opConst (ty/constUnit)))
              (letVal "pair" (ty/opList (list "tag" "size" "unit"))))
        (mkRet "pair"))))))

fn branchModule -> ty/SsaModule
  (moduleOf (list
    (ty/ssaFunction "pick" (list) (list (ty/ssaParam "flag" (ty/tyI1))) (ty/tyI64)
      (list (mkBlock "entry" (list (ty/ssaInstr "a" (ty/tyI64) (ty/opConst (ty/constInt 1))))
              (ty/termBranch "flag" (ty/ssaEdge "join" (list "a")) (ty/ssaEdge "other" (list))))
            (mkBlock "other" (list (ty/ssaInstr "b" (ty/tyI64) (ty/opConst (ty/constInt 2)))) (mkJump "join" (list "b")))
            (ty/ssaBlock "join" (list (ty/ssaParam "out" (ty/tyI64))) (list) (mkRet "out"))))
    (simpleFn "boxed" (list)
      (list (mkBlock "entry"
        (list (ty/ssaInstr "flag" (ty/tyI1) (ty/opConst (ty/constBool true)))
              (ty/ssaInstr "wide" (ty/tyI64) (ty/opCall "pick" (list "flag")))
              (letVal "boxedWide" (ty/opBox "wide")))
        (mkRet "boxedWide"))))))

fn globalModule -> ty/SsaModule
  (ty/ssaModule "globals" (list) (list) (list) (list (ty/ssaExtern "net/fetch" 2)) (list (ty/ssaGlobal "answer" "answerInit"))
    (list (simpleFn "answerInit" (list) (list (mkBlock "entry" (list (intConst "n" 42)) (mkRet "n"))))
          (simpleFn "useAnswer" (list "url")
            (list (mkBlock "entry"
              (list (letVal "a" (ty/opGlobal "answer"))
                    (letVal "b" (ty/opCall "net/fetch" (list "url" "a"))))
              (mkRet "b"))))))

fn testClosure -> Bool
  (let [(res (vfy/verifySsa (closureModule)))]
    (do (assert (ok? res) "closure module: make-closure with captures and indirect call verify")
        (assert (= (codes res) (list)) "closure module has no diagnostics")
        true))

fn testCtorRecordList -> Bool
  (let [(res (vfy/verifySsa (ctorModule)))]
    (do (assert (ok? res) "construct, record, field and list verify")
        true))

fn testSwitch -> Bool
  (let [(exhaustive (vfy/verifySsa (moduleOf (list (switchFn "area" (allCases) (none))))))
        (withDefault (vfy/verifySsa (moduleOf (list (switchFn "area" (partialCases) (some (ty/ssaEdge "onEmpty" (list))))))))]
    (do (assert (ok? exhaustive) "switch covering every variant needs no default")
        (assert (ok? withDefault) "partial switch with a default verifies")
        true))

fn testStringLiteral -> Bool
  (let [(res (vfy/verifySsa (stringModule)))
        (text (prn/printSsa (stringModule)))]
    (do (assert (ok? res) "string pool reference, keyword and unit verify")
        (assert (stringContains? text "(strings \"hello\" \"line\\n\\\"quoted\\\" \\\\\")") "pool strings print escaped")
        (assert (stringContains? text "(let text val (const str 1))") "string constant prints as a pool index")
        (assert (stringContains? text "(let tag val (const keyword ok))") "keyword constant prints")
        true))

fn loadGlobalModule -> ty/SsaModule
  (moduleOf (list (ty/ssaFunction "readEnviron" (list) (list) (ty/tyPtr)
    (list (mkBlock "entry" (list (ty/ssaInstr "p" (ty/tyPtr) (ty/opLoadGlobal "environ"))) (ty/termReturn "p"))))))

fn testRawTypesAndGlobals -> Bool
  (do (assert (ok? (vfy/verifySsa (branchModule))) "raw i1/i64 values, branch and block params verify")
      (assert (ok? (vfy/verifySsa (globalModule))) "globals and extern calls verify")
      (assert (ok? (vfy/verifySsa (loadGlobalModule))) "a raw ptr-typed opLoadGlobal of a foreign C global verifies")
      true)

fn loopFn exitValue: String -> ty/SsaFunction
  (simpleFn "count" (list "limit")
    (list (mkBlock "entry" (list (intConst "start" 0)) (mkJump "head" (list "start")))
          (ty/ssaBlock "head" (list (mkParam "i")) (list (letVal "done" (ty/opBuiltin ">=" (list "i" "limit"))))
            (ty/termBranch "done" (ty/ssaEdge "exit" (list)) (ty/ssaEdge "body" (list))))
          (mkBlock "body" (list (intConst "one" 1) (letVal "next" (ty/opBuiltin "+" (list "i" "one")))) (mkJump "head" (list "next")))
          (mkBlock "exit" (list) (mkRet exitValue))))

fn testLoop -> Bool
  (let [(fine (vfy/verifySsa (moduleOf (list (loopFn "i")))))
        (leak (vfy/verifySsa (moduleOf (list (loopFn "next")))))]
    (do (assert (ok? fine) "a loop header parameter dominates the body and the exit")
        (assert (onlyCode leak "ERR_IR_UNDEFINED_VALUE") "a value of the loop body does not dominate the exit")
        true))

fn testUndefinedValue -> Bool
  (let [(unknown (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list) (mkRet "ghost")))))))
        (beforeDef (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "a" (ty/opList (list "b"))) (intConst "b" 1)) (mkRet "a")))))))
        (notDominating (moduleOf (list (simpleFn "f" (list "flag")
          (list (mkBlock "entry" (list) (ty/termBranch "flag" (ty/ssaEdge "left" (list)) (ty/ssaEdge "right" (list))))
                (mkBlock "left" (list (intConst "l" 1)) (mkJump "join" (list)))
                (mkBlock "right" (list) (mkJump "join" (list)))
                (mkBlock "join" (list) (mkRet "l")))))))]
    (do (assert (onlyCode (vfy/verifySsa unknown) "ERR_IR_UNDEFINED_VALUE") "use of a never-defined value is rejected")
        (assert (onlyCode (vfy/verifySsa beforeDef) "ERR_IR_UNDEFINED_VALUE") "use before definition in the same block is rejected")
        (assert (onlyCode (vfy/verifySsa notDominating) "ERR_IR_UNDEFINED_VALUE") "use of a value from a non-dominating block is rejected")
        true))

fn testMissingBlock -> Bool
  (let [(res (vfy/verifySsa (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list) (mkJump "nowhere" (list))))))))) ]
    (do (assert (onlyCode res "ERR_IR_MISSING_BLOCK") "jump to a missing block is rejected")
        true))

fn testArity -> Bool
  (let [(shortCall (moduleOf (list (simpleFn "two" (list "a" "b") (list (mkBlock "entry" (list) (mkRet "a"))))
                                   (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "x" 1) (letVal "y" (ty/opCall "two" (list "x")))) (mkRet "y")))))))
        (externCall (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "x" 1) (letVal "y" (ty/opCall "net/fetch" (list "x" "x" "x")))) (mkRet "y")))))))
        (captureCount (moduleOf (list (adderFn) (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "c" (ty/opMakeClosure "adder" (list)))) (mkRet "c")))))))
        (ctorFields (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "k" 1) (letVal "c" (ty/opConstruct "Shape" "empty" (list "k")))) (mkRet "c")))))))
        (jumpArgs (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list) (mkJump "join" (list))) (ty/ssaBlock "join" (list (mkParam "p")) (list) (mkRet "p")))))))]
    (do (assert (onlyCode (vfy/verifySsa shortCall) "ERR_IR_ARITY") "known call with too few arguments is rejected")
        (assert (onlyCode (vfy/verifySsa externCall) "ERR_IR_ARITY") "extern call with too many arguments is rejected")
        (assert (onlyCode (vfy/verifySsa captureCount) "ERR_IR_ARITY") "make-closure with the wrong capture count is rejected")
        (assert (onlyCode (vfy/verifySsa ctorFields) "ERR_IR_ARITY") "construct with the wrong field count is rejected")
        (assert (onlyCode (vfy/verifySsa jumpArgs) "ERR_IR_ARITY") "jump arguments must match block parameters")
        true))

fn testSwitchDefault -> Bool
  (let [(res (vfy/verifySsa (moduleOf (list (switchFn "area" (partialCases) (none))))))
        (unknownVariant (vfy/verifySsa (moduleOf (list (switchFn "area" (list (ty/ssaCase "triangle" (ty/ssaEdge "onCircle" (list)))) (some (ty/ssaEdge "onEmpty" (list))))))))]
    (do (assert (onlyCode res "ERR_IR_MISSING_DEFAULT") "non-exhaustive switch without default is rejected")
        (assert (onlyCode unknownVariant "ERR_IR_UNKNOWN_VARIANT") "switch on an undeclared variant is rejected")
        true))

fn testDuplicates -> Bool
  (let [(dupValue (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "x" 1) (intConst "x" 2)) (mkRet "x")))))))
        (dupParam (moduleOf (list (simpleFn "f" (list "x") (list (mkBlock "entry" (list (intConst "x" 2)) (mkRet "x")))))))
        (dupBlock (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list) (mkJump "next" (list))) (mkBlock "next" (list (intConst "a" 1)) (mkRet "a")) (mkBlock "next" (list (intConst "b" 1)) (mkRet "b")))))))
        (dupFn (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "a" 1)) (mkRet "a")))) (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "a" 1)) (mkRet "a")))))))
        (dupCase (vfy/verifySsa (moduleOf (list (switchFn "area" (listAppend (allCases) (list (ty/ssaCase "circle" (ty/ssaEdge "onCircle" (list))))) (none))))))]
    (do (assert (onlyCode (vfy/verifySsa dupValue) "ERR_IR_DUPLICATE_DEFINITION") "a value defined twice is rejected")
        (assert (onlyCode (vfy/verifySsa dupParam) "ERR_IR_DUPLICATE_DEFINITION") "an instruction redefining a parameter is rejected")
        (assert (onlyCode (vfy/verifySsa dupBlock) "ERR_IR_DUPLICATE_DEFINITION") "two blocks with one label are rejected")
        (assert (onlyCode (vfy/verifySsa dupFn) "ERR_IR_DUPLICATE_DEFINITION") "two functions with one name are rejected")
        (assert (onlyCode dupCase "ERR_IR_DUPLICATE_DEFINITION") "a switch naming one variant twice is rejected")
        true))

fn testOtherRejections -> Bool
  (let [(badString (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "s" (ty/opConst (ty/constStr 7)))) (mkRet "s")))))))
        (rawArg (moduleOf (list (adderFn) (simpleFn "f" (list) (list (mkBlock "entry" (list (ty/ssaInstr "n" (ty/tyI64) (ty/opConst (ty/constInt 1))) (letVal "c" (ty/opMakeClosure "adder" (list "n")))) (mkRet "c")))))))
        (rawString (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (ty/ssaInstr "s" (ty/tyI64) (ty/opConst (ty/constStr 0))) (letVal "b" (ty/opBox "s"))) (mkRet "b")))))))
        (unknownFn (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "y" (ty/opCall "missing" (list)))) (mkRet "y")))))))
        (unknownType (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "y" (ty/opConstruct "Tree" "leaf" (list)))) (mkRet "y")))))))
        (recordFields (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (intConst "x" 1) (letVal "p" (ty/opRecord "Point" (list "x" "z") (list "x" "x")))) (mkRet "p")))))))
        (unknownGlobal (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "g" (ty/opGlobal "nothing"))) (mkRet "g")))))))
        (loadGlobalBadType (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (letVal "g" (ty/opLoadGlobal "environ"))) (mkRet "g")))))))
        (entryTarget (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list) (mkJump "loop" (list))) (mkBlock "loop" (list) (mkJump "entry" (list))))))))
        (noBlocks (moduleOf (list (simpleFn "f" (list) (list)))))
        (wrongReturn (moduleOf (list (simpleFn "f" (list) (list (mkBlock "entry" (list (ty/ssaInstr "n" (ty/tyI64) (ty/opConst (ty/constInt 1)))) (mkRet "n")))))))]
    (do (assert (onlyCode (vfy/verifySsa badString) "ERR_IR_STRING_INDEX") "string reference outside the pool is rejected")
        (assert (onlyCode (vfy/verifySsa rawArg) "ERR_IR_TYPE_MISMATCH") "raw i64 passed where a Val is required is rejected")
        (assert (onlyCode (vfy/verifySsa rawString) "ERR_IR_TYPE_MISMATCH") "a string constant cannot be raw")
        (assert (onlyCode (vfy/verifySsa unknownFn) "ERR_IR_UNKNOWN_FUNCTION") "call of an undeclared function is rejected")
        (assert (onlyCode (vfy/verifySsa unknownType) "ERR_IR_UNKNOWN_TYPE") "construct of an undeclared type is rejected")
        (assert (onlyCode (vfy/verifySsa recordFields) "ERR_IR_UNKNOWN_FIELD") "record with fields other than declared is rejected")
        (assert (onlyCode (vfy/verifySsa unknownGlobal) "ERR_IR_UNKNOWN_GLOBAL") "read of an undeclared global is rejected")
        (assert (onlyCode (vfy/verifySsa loadGlobalBadType) "ERR_IR_TYPE_MISMATCH") "opLoadGlobal typed as Val instead of ptr is rejected")
        (assert (onlyCode (vfy/verifySsa entryTarget) "ERR_IR_ENTRY_TARGET") "a jump to the entry block is rejected")
        (assert (onlyCode (vfy/verifySsa noBlocks) "ERR_IR_EMPTY_FUNCTION") "a function without blocks is rejected")
        (assert (onlyCode (vfy/verifySsa wrongReturn) "ERR_IR_TYPE_MISMATCH") "returning i64 from a Val function is rejected")
        true))

fn goldenText -> String
  (stringJoin (list
    "(ssa-module \"fixture\""
    "  (strings \"hello\" \"line\\n\\\"quoted\\\" \\\\\")"
    "  (type Shape (circle 1) (square 1) (empty 0))"
    "  (record Point x y)"
    "  (extern net/fetch 2)"
    "  (fn adder (captures (n val)) (params (x val)) (returns val)"
    "    (block entry ()"
    "      (let sum val (builtin \"+\" n x))"
    "      (return sum)))"
    "  (fn main (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let five val (const int 5))"
    "      (let addFive val (make-closure adder five))"
    "      (let one val (const int 1))"
    "      (let six val (call-closure addFive one))"
    "      (return six))))") "\n")

fn testPrinter -> Bool
  (let [(textA (prn/printSsa (closureModule)))
        (textB (prn/printSsa (closureModule)))
        (switchText (prn/printSsa (moduleOf (list (switchFn "area" (partialCases) (some (ty/ssaEdge "onEmpty" (list))))))))]
    (do (assert (= textA (goldenText)) "closure module prints the golden text")
        (assert (= textA textB) "printing is deterministic")
        (assert (stringContains? switchText "(switch shape Shape (circle (onCircle)) (square (onSquare)) (default (onEmpty)))") "switch prints cases and default")
        (assert (stringContains? switchText "(block join ((result val))") "block parameters print")
        (assert (stringContains? switchText "(jump (join r))") "jump prints its edge arguments")
        (refute (= textA switchText) "different modules print differently")
        true))

fn runTests -> Bool
  (do (assert (testClosure) "testClosure")
      (assert (testCtorRecordList) "testCtorRecordList")
      (assert (testSwitch) "testSwitch")
      (assert (testStringLiteral) "testStringLiteral")
      (assert (testRawTypesAndGlobals) "testRawTypesAndGlobals")
      (assert (testLoop) "testLoop")
      (assert (testUndefinedValue) "testUndefinedValue")
      (assert (testMissingBlock) "testMissingBlock")
      (assert (testArity) "testArity")
      (assert (testSwitchDefault) "testSwitchDefault")
      (assert (testDuplicates) "testDuplicates")
      (assert (testOtherRejections) "testOtherRejections")
      (assert (testPrinter) "testPrinter")
      true)
