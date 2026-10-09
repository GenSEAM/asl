(module asl-target-llvm/tests/irE2eTest
  :x [runTests main]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssa :a ssa)])

fn valParam name: String -> ty/SsaParam
  (ty/ssaParam name (ty/tyVal))

fn letVal dest: String op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) op)

fn valInt dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opConst (ty/constInt n)))

fn rawInt dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI64) (ty/opConst (ty/constInt n)))

fn rawBool dest: String b: Bool -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI1) (ty/opConst (ty/constBool b)))

fn edge target: String args: (List String) -> ty/SsaEdge
  (ty/ssaEdge target args)

fn block label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn plainModule name: String functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule name (list) (list) (list) (list) (list) functions)

fn fibFunction -> ty/SsaFunction
  (ty/ssaFunction "fib" (list) (list (valParam "n")) (ty/tyVal)
    (list (block "entry" (list (valInt "two" 2) (letVal "small" (ty/opBuiltin "<" (list "n" "two"))))
            (ty/termBranch "small" (edge "base" (list)) (edge "recur" (list))))
          (block "base" (list) (ty/termReturn "n"))
          (block "recur"
            (list (valInt "one" 1)
                  (letVal "n1" (ty/opBuiltin "-" (list "n" "one")))
                  (letVal "f1" (ty/opCall "fib" (list "n1")))
                  (letVal "n2" (ty/opBuiltin "-" (list "n" "two")))
                  (letVal "f2" (ty/opCall "fib" (list "n2")))
                  (letVal "sum" (ty/opBuiltin "+" (list "f1" "f2"))))
            (ty/termReturn "sum"))))

fn fibModule -> ty/SsaModule
  (plainModule "fib"
    (list (fibFunction)
          (ty/ssaFunction "fibMain" (list) (list) (ty/tyVal)
            (list (block "entry" (list (valInt "ten" 10) (letVal "result" (ty/opCall "fib" (list "ten")))) (ty/termReturn "result"))))))

fn pickFunction -> ty/SsaFunction
  (ty/ssaFunction "pick" (list) (list (ty/ssaParam "flag" (ty/tyI1)) (ty/ssaParam "ifTrue" (ty/tyI64)) (ty/ssaParam "ifFalse" (ty/tyI64))) (ty/tyI64)
    (list (block "entry" (list) (ty/termBranch "flag" (edge "join" (list "ifTrue")) (edge "join" (list "ifFalse"))))
          (ty/ssaBlock "join" (list (ty/ssaParam "chosen" (ty/tyI64))) (list) (ty/termReturn "chosen"))))

fn swapMainFunction -> ty/SsaFunction
  (ty/ssaFunction "swapMain" (list) (list) (ty/tyI64)
    (list (block "entry" (list (rawBool "first" true) (rawInt "five" 5) (rawInt "answer" 42)) (ty/termJump (edge "head" (list "first" "five" "answer"))))
          (ty/ssaBlock "head" (list (ty/ssaParam "again" (ty/tyI1)) (ty/ssaParam "a" (ty/tyI64)) (ty/ssaParam "b" (ty/tyI64))) (list)
            (ty/termBranch "again" (edge "body" (list)) (edge "exit" (list))))
          (block "body" (list (rawBool "stop" false)) (ty/termJump (edge "head" (list "stop" "b" "a"))))
          (block "exit" (list (ty/ssaInstr "picked" (ty/tyI64) (ty/opCall "pick" (list "again" "b" "a")))) (ty/termReturn "picked"))))

fn loopModule -> ty/SsaModule
  (plainModule "loop" (list (pickFunction) (swapMainFunction)))

fn shapeType -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Shape" (list (ty/ssaVariant "circle" 1) (ty/ssaVariant "square" 1) (ty/ssaVariant "empty" 0)))

fn switchModule -> ty/SsaModule
  (ty/ssaModule "switch" (list) (list (shapeType)) (list) (list) (list)
    (list (ty/ssaFunction "size" (list) (list (valParam "shape")) (ty/tyVal)
            (list (block "entry" (list (valInt "zero" 0))
                    (ty/termSwitch "shape" "Shape"
                      (list (ty/ssaCase "square" (edge "onSquare" (list)))
                            (ty/ssaCase "circle" (edge "onCircle" (list))))
                      (some (edge "join" (list "zero")))))
                  (block "onCircle" (list (letVal "r" (ty/opVariantField "shape" 0))) (ty/termJump (edge "join" (list "r"))))
                  (block "onSquare" (list (letVal "side" (ty/opVariantField "shape" 0))) (ty/termJump (edge "join" (list "side"))))
                  (ty/ssaBlock "join" (list (valParam "result")) (list) (ty/termReturn "result"))))
          (ty/ssaFunction "isEmpty" (list) (list (valParam "shape")) (ty/tyI1)
            (list (block "entry" (list)
                    (ty/termSwitch "shape" "Shape"
                      (list (ty/ssaCase "circle" (edge "no" (list)))
                            (ty/ssaCase "square" (edge "no" (list)))
                            (ty/ssaCase "empty" (edge "yes" (list))))
                      (none)))
                  (block "no" (list (rawBool "f" false)) (ty/termReturn "f"))
                  (block "yes" (list (rawBool "t" true)) (ty/termReturn "t"))))))

fn opsModule -> ty/SsaModule
  (ty/ssaModule "ops/demo" (list "hi \"there\"\n" "") (list (shapeType)) (list (ty/ssaRecordDecl "Point" (list "x" "y"))) (list (ty/ssaExtern "net/fetch" 2)) (list (ty/ssaGlobal "origin" "makeOrigin"))
    (list (ty/ssaFunction "adder" (list (valParam "n")) (list (valParam "x")) (ty/tyVal)
            (list (block "entry" (list (letVal "sum" (ty/opBuiltin "+" (list "n" "x")))) (ty/termReturn "sum"))))
          (ty/ssaFunction "makeOrigin" (list) (list) (ty/tyVal)
            (list (block "entry" (list (valInt "zero" 0) (letVal "p" (ty/opRecord "Point" (list "x" "y") (list "zero" "zero")))) (ty/termReturn "p"))))
          (ty/ssaFunction "demo" (list) (list (valParam "url")) (ty/tyVal)
            (list (block "entry"
                    (list (ty/ssaInstr "rawFive" (ty/tyI64) (ty/opConst (ty/constInt 5)))
                          (letVal "five" (ty/opBox "rawFive"))
                          (letVal "add5" (ty/opMakeClosure "adder" (list "five")))
                          (letVal "one" (ty/opConst (ty/constFloat 1.0)))
                          (letVal "six" (ty/opCallClosure "add5" (list "one")))
                          (ty/ssaInstr "half" (ty/tyF64) (ty/opConst (ty/constFloat -0.5)))
                          (letVal "halfVal" (ty/opBox "half"))
                          (letVal "greeting" (ty/opConst (ty/constStr 0)))
                          (letVal "empty" (ty/opConst (ty/constStr 1)))
                          (letVal "unit" (ty/opConst (ty/constUnit)))
                          (letVal "kw" (ty/opConst (ty/constKeyword "doc")))
                          (letVal "sym" (ty/opConst (ty/constSymbol "a-b")))
                          (letVal "yes" (ty/opConst (ty/constBool true)))
                          (letVal "circle" (ty/opConstruct "Shape" "circle" (list "six")))
                          (letVal "none" (ty/opConstruct "Shape" "empty" (list)))
                          (letVal "origin" (ty/opGlobal "origin"))
                          (letVal "ox" (ty/opField "origin" "x"))
                          (letVal "body" (ty/opCall "net/fetch" (list "url" "greeting")))
                          (ty/ssaInstr "rawSix" (ty/tyI64) (ty/opUnbox "six"))
                          (ty/ssaInstr "ok" (ty/tyI1) (ty/opUnbox "yes"))
                          (letVal "all" (ty/opList (list "circle" "none" "ox" "body" "empty" "unit" "kw" "sym" "halfVal"))))
                    (ty/termBranch "ok" (edge "done" (list "all")) (edge "done" (list "unit"))))
                  (ty/ssaBlock "done" (list (valParam "out")) (list) (ty/termReturn "out"))))))

fn prim dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opPrim name args))

fn rawFloat dest: String x: Float64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyF64) (ty/opConst (ty/constFloat x)))

fn fibRawModule -> ty/SsaModule
  (plainModule "fibRaw"
    (list (ty/ssaFunction "fib" (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyI64)
            (list (block "entry" (list (rawInt "two" 2) (prim "small" (ty/tyI1) "ltInt" (list "n" "two")))
                    (ty/termBranch "small" (edge "base" (list)) (edge "recur" (list))))
                  (block "base" (list) (ty/termReturn "n"))
                  (block "recur"
                    (list (rawInt "one" 1)
                          (prim "n1" (ty/tyI64) "subInt" (list "n" "one"))
                          (ty/ssaInstr "f1" (ty/tyI64) (ty/opCall "fib" (list "n1")))
                          (prim "n2" (ty/tyI64) "subInt" (list "n" "two"))
                          (ty/ssaInstr "f2" (ty/tyI64) (ty/opCall "fib" (list "n2")))
                          (prim "sum" (ty/tyI64) "addInt" (list "f1" "f2")))
                    (ty/termReturn "sum"))))
          (ty/ssaFunction "fibMain" (list) (list) (ty/tyI64)
            (list (block "entry" (list (rawInt "ten" 10) (ty/ssaInstr "result" (ty/tyI64) (ty/opCall "fib" (list "ten")))) (ty/termReturn "result"))))))

fn intIs dest: String name: String a: Int64 b: Int64 want: Int64 -> (List ty/SsaInstr)
  (list (rawInt (str dest "a") a) (rawInt (str dest "b") b) (rawInt (str dest "want") want)
        (prim (str dest "got") (ty/tyI64) name (list (str dest "a") (str dest "b")))
        (prim dest (ty/tyI1) "eqInt" (list (str dest "got") (str dest "want"))))

fn cmpIs dest: String name: String a: Int64 b: Int64 want: Bool -> (List ty/SsaInstr)
  (list (rawInt (str dest "a") a) (rawInt (str dest "b") b)
        (prim (str dest "got") (ty/tyI1) name (list (str dest "a") (str dest "b")))
        (prim dest (ty/tyI1) (if want "andBool" "notBool") (if want (list (str dest "got") (str dest "got")) (list (str dest "got")))))

fn floatIs dest: String name: String a: Float64 b: Float64 want: Float64 -> (List ty/SsaInstr)
  (list (rawFloat (str dest "a") a) (rawFloat (str dest "b") b) (rawFloat (str dest "want") want)
        (prim (str dest "got") (ty/tyF64) name (list (str dest "a") (str dest "b")))
        (prim dest (ty/tyI1) "eqFloat" (list (str dest "got") (str dest "want"))))

fn fcmpIs dest: String name: String a: Float64 b: Float64 want: Bool -> (List ty/SsaInstr)
  (list (rawFloat (str dest "a") a) (rawFloat (str dest "b") b)
        (prim (str dest "got") (ty/tyI1) name (list (str dest "a") (str dest "b")))
        (prim dest (ty/tyI1) (if want "andBool" "notBool") (if want (list (str dest "got") (str dest "got")) (list (str dest "got")))))

fn floatSame dest: String a: String b: String -> (List ty/SsaInstr)
  (list (prim (str dest "eq") (ty/tyI1) "eqFloat" (list a b))
        (prim (str dest "aOrdered") (ty/tyI1) "eqFloat" (list a a))
        (prim (str dest "bOrdered") (ty/tyI1) "eqFloat" (list b b))
        (prim (str dest "aIsNan") (ty/tyI1) "notBool" (list (str dest "aOrdered")))
        (prim (str dest "bIsNan") (ty/tyI1) "notBool" (list (str dest "bOrdered")))
        (prim (str dest "bothNan") (ty/tyI1) "andBool" (list (str dest "aIsNan") (str dest "bIsNan")))
        (rawFloat (str dest "one") 1.0)
        (prim (str dest "ra") (ty/tyF64) "divFloat" (list (str dest "one") a))
        (prim (str dest "rb") (ty/tyF64) "divFloat" (list (str dest "one") b))
        (prim (str dest "sameSign") (ty/tyI1) "eqFloat" (list (str dest "ra") (str dest "rb")))
        (prim (str dest "eqAndSign") (ty/tyI1) "andBool" (list (str dest "eq") (str dest "sameSign")))
        (prim dest (ty/tyI1) "orBool" (list (str dest "bothNan") (str dest "eqAndSign"))))

fn mathIs1 dest: String builtin: String a: Float64 want: Float64 -> (List ty/SsaInstr)
  (listAppend
    (list (rawFloat (str dest "a") a) (ty/ssaInstr (str dest "r") (ty/tyF64) (ty/opEntry builtin (list (str dest "a")))) (rawFloat (str dest "want") want))
    (floatSame dest (str dest "r") (str dest "want")))

fn mathIs2 dest: String builtin: String a: Float64 b: Float64 want: Float64 -> (List ty/SsaInstr)
  (listAppend
    (list (rawFloat (str dest "a") a) (rawFloat (str dest "b") b)
          (ty/ssaInstr (str dest "r") (ty/tyF64) (ty/opEntry builtin (list (str dest "a") (str dest "b"))))
          (rawFloat (str dest "want") want))
    (floatSame dest (str dest "r") (str dest "want")))

fn mathChecks -> (List (List ty/SsaInstr))
  (list
    (mathIs1 "floorPos" "floor" 2.7 (floor 2.7)) (mathIs1 "floorNeg" "floor" -2.5 (floor -2.5)) (mathIs1 "floorNegHalf" "floor" -0.5 (floor -0.5))
    (mathIs1 "floorNegZero" "floor" (- 0.0) (floor (- 0.0))) (mathIs1 "floorInf" "floor" (floatInf) (floor (floatInf))) (mathIs1 "floorNan" "floor" (floatNan) (floor (floatNan)))
    (mathIs1 "ceilPos" "ceil" 2.3 (ceil 2.3)) (mathIs1 "ceilNeg" "ceil" -2.5 (ceil -2.5)) (mathIs1 "ceilNegZero" "ceil" (- 0.0) (ceil (- 0.0)))
    (mathIs1 "ceilNegInf" "ceil" (floatNegInf) (ceil (floatNegInf)))
    (mathIs1 "roundHalf" "round" 2.5 (round 2.5)) (mathIs1 "roundNegHalf" "round" -2.5 (round -2.5))
    (mathIs1 "roundUp" "round" 2.6 (round 2.6)) (mathIs1 "roundDown" "round" 2.4 (round 2.4))
    (mathIs1 "roundNan" "round" (floatNan) (round (floatNan))) (mathIs1 "roundInf" "round" (floatInf) (round (floatInf)))
    (mathIs1 "sqrtPos" "sqrt" 2.0 (sqrt 2.0)) (mathIs1 "sqrtZero" "sqrt" 0.0 (sqrt 0.0)) (mathIs1 "sqrtNegZero" "sqrt" (- 0.0) (sqrt (- 0.0)))
    (mathIs1 "sqrtNeg" "sqrt" -1.0 (sqrt -1.0)) (mathIs1 "sqrtInf" "sqrt" (floatInf) (sqrt (floatInf)))
    (mathIs2 "powBasic" "pow" 2.0 10.0 (pow 2.0 10.0)) (mathIs2 "powLarge" "pow" 2.0 62.0 (pow 2.0 62.0))
    (mathIs2 "powZeroNeg" "pow" 0.0 -1.0 (pow 0.0 -1.0)) (mathIs2 "powNegFrac" "pow" -1.0 0.5 (pow -1.0 0.5)) (mathIs2 "powNan" "pow" (floatNan) 2.0 (pow (floatNan) 2.0))
    (mathIs1 "expOne" "exp" 1.0 (exp 1.0)) (mathIs1 "expLarge" "exp" 700.0 (exp 700.0)) (mathIs1 "expOverflow" "exp" 710.0 (exp 710.0)) (mathIs1 "expNan" "exp" (floatNan) (exp (floatNan)))
    (mathIs1 "logNormal" "log" 2.718281828459045 (log 2.718281828459045)) (mathIs1 "logZero" "log" 0.0 (log 0.0))
    (mathIs1 "logNeg" "log" -1.0 (log -1.0)) (mathIs1 "logInf" "log" (floatInf) (log (floatInf)))
    (mathIs1 "log2Basic" "log2" 8.0 (log2 8.0)) (mathIs1 "log2Zero" "log2" 0.0 (log2 0.0))
    (mathIs1 "log10Basic" "log10" 1000.0 (log10 1000.0)) (mathIs1 "log10Neg" "log10" -5.0 (log10 -5.0))
    (mathIs1 "sinZero" "sin" 0.0 (sin 0.0)) (mathIs1 "sinInf" "sin" (floatInf) (sin (floatInf)))
    (mathIs1 "cosZero" "cos" 0.0 (cos 0.0)) (mathIs1 "cosLarge" "cos" 123456.789 (cos 123456.789))
    (mathIs1 "tanZero" "tan" 0.0 (tan 0.0)) (mathIs1 "tanLarge" "tan" 1000000.0 (tan 1000000.0))
    (mathIs2 "atan2Basic" "atan2" 1.0 1.0 (atan2 1.0 1.0)) (mathIs2 "atan2NegZero" "atan2" (- 0.0) -1.0 (atan2 (- 0.0) -1.0)) (mathIs2 "atan2Nan" "atan2" (floatNan) 1.0 (atan2 (floatNan) 1.0))
    (mathIs2 "atan2PosPosZero" "atan2" 0.0 0.0 (atan2 0.0 0.0)) (mathIs2 "atan2NegPosZero" "atan2" (- 0.0) 0.0 (atan2 (- 0.0) 0.0))
    (mathIs2 "atan2PosNegZero" "atan2" 0.0 (- 0.0) (atan2 0.0 (- 0.0))) (mathIs2 "atan2NegNegZero" "atan2" (- 0.0) (- 0.0) (atan2 (- 0.0) (- 0.0))))

fn primChecks -> (List (List ty/SsaInstr))
  (listAppend (primChecksBase) (mathChecks))

fn primChecksBase -> (List (List ty/SsaInstr))
  (list (intIs "add" "addInt" 40 2 42)
        (intIs "sub" "subInt" 5 7 -2)
        (intIs "mul" "mulInt" -6 7 -42)
        (intIs "quot" "quotInt" -7 2 -3)
        (intIs "rem" "remInt" -7 2 -1)
        (intIs "remNeg" "remInt" 7 -1 0)
        (intIs "addMax" "addInt" 9223372036854775806 1 9223372036854775807)
        (list (rawInt "min" -9223372036854775808) (rawInt "minNeg" -1) (prim "minRem" (ty/tyI64) "remInt" (list "min" "minNeg")) (rawInt "minZero" 0)
              (prim "minRemOk" (ty/tyI1) "eqInt" (list "minRem" "minZero")))
        (cmpIs "eq" "eqInt" 3 3 true) (cmpIs "eqNot" "eqInt" 3 4 false)
        (cmpIs "ne" "neInt" 3 4 true) (cmpIs "neNot" "neInt" 3 3 false)
        (cmpIs "lt" "ltInt" -1 0 true) (cmpIs "ltNot" "ltInt" 0 0 false)
        (cmpIs "le" "leInt" 0 0 true) (cmpIs "leNot" "leInt" 1 0 false)
        (cmpIs "gt" "gtInt" 0 -1 true) (cmpIs "gtNot" "gtInt" 0 0 false)
        (cmpIs "ge" "geInt" 0 0 true) (cmpIs "geNot" "geInt" -1 0 false)
        (floatIs "fadd" "addFloat" 1.5 2.25 3.75)
        (floatIs "fsub" "subFloat" 1.5 2.25 -0.75)
        (floatIs "fmul" "mulFloat" 1.5 -2.0 -3.0)
        (floatIs "fdiv" "divFloat" 3.0 4.0 0.75)
        (fcmpIs "feq" "eqFloat" 0.5 0.5 true) (fcmpIs "fne" "neFloat" 0.5 0.25 true)
        (fcmpIs "flt" "ltFloat" 0.25 0.5 true) (fcmpIs "fltNot" "ltFloat" 0.5 0.5 false)
        (fcmpIs "fle" "leFloat" 0.5 0.5 true) (fcmpIs "fgt" "gtFloat" 0.5 0.25 true)
        (fcmpIs "fge" "geFloat" 0.5 0.5 true) (fcmpIs "fgeNot" "geFloat" 0.25 0.5 false)
        (list (rawFloat "nanZero" 0.0) (prim "nan" (ty/tyF64) "divFloat" (list "nanZero" "nanZero"))
              (prim "nanNe" (ty/tyI1) "neFloat" (list "nan" "nan")) (prim "nanEq" (ty/tyI1) "eqFloat" (list "nan" "nan"))
              (prim "nanLe" (ty/tyI1) "leFloat" (list "nan" "nan")) (prim "nanOrdered" (ty/tyI1) "orBool" (list "nanEq" "nanLe"))
              (prim "nanUnordered" (ty/tyI1) "notBool" (list "nanOrdered")) (prim "nanOk" (ty/tyI1) "andBool" (list "nanNe" "nanUnordered")))
        (list (rawBool "yes" true) (rawBool "no" false)
              (prim "andNo" (ty/tyI1) "andBool" (list "yes" "no")) (prim "orYes" (ty/tyI1) "orBool" (list "no" "yes"))
              (prim "andNoNot" (ty/tyI1) "notBool" (list "andNo")) (prim "logicOk" (ty/tyI1) "andBool" (list "andNoNot" "orYes")))
        (list (rawInt "three" 3) (prim "threeF" (ty/tyF64) "intToFloat" (list "three")) (rawFloat "threeWant" 3.0)
              (prim "toFloatOk" (ty/tyI1) "eqFloat" (list "threeF" "threeWant")))
        (list (rawFloat "negFrac" -2.75) (prim "negTrunc" (ty/tyI64) "floatToInt" (list "negFrac")) (rawInt "negWant" -2)
              (prim "toIntOk" (ty/tyI1) "eqInt" (list "negTrunc" "negWant")))
        (list (rawInt "lowInt" -9223372036854775808) (prim "lowF" (ty/tyF64) "intToFloat" (list "lowInt")) (prim "lowBack" (ty/tyI64) "floatToInt" (list "lowF"))
              (prim "lowOk" (ty/tyI1) "eqInt" (list "lowBack" "lowInt"))))

fn lastDest instrs: (List ty/SsaInstr) -> String
  (mt (listGet instrs (- (listLength instrs) 1)) ((some i) i.dest) ((none) ""))

fn checkLabel k: Int64 count: Int64 -> String
  (if (= k count) "done" (str "check" k))

fn checkBlock k: Int64 count: Int64 instrs: (List ty/SsaInstr) -> (List ty/SsaBlock)
  (let [(counter (str "count" k)) (next (str "next" k))]
    (list (ty/ssaBlock (checkLabel k count) (list (ty/ssaParam counter (ty/tyI64)))
            (listAppend instrs (list (prim next (ty/tyI64) "addInt" (list counter "one"))))
            (ty/termBranch (lastDest instrs) (edge (checkLabel (+ k 1) count) (list next)) (edge (str "fail" k) (list))))
          (block (str "fail" k) (list (rawInt (str "code" k) (+ k 1))) (ty/termReturn (str "code" k)))))

fn primCheckFunction -> ty/SsaFunction
  (let [(checks (primChecks))
        (n (listLength checks))
        (body (fold (fn [(acc (List ty/SsaBlock)) (k Int64)] -> (List ty/SsaBlock)
                      (listAppend acc (checkBlock k n (optionOr (listGet checks k) (list)))))
                    (list) (range 0 n)))]
    (ty/ssaFunction "primCheck" (list) (list) (ty/tyI64)
      (listAppend
        (cons (block "entry" (list (rawInt "zero" 0) (rawInt "one" 1)) (ty/termJump (edge "check0" (list "zero")))) body)
        (list (ty/ssaBlock "done" (list (ty/ssaParam "total" (ty/tyI64)))
                (list (rawInt "expected" n) (prim "allRan" (ty/tyI1) "eqInt" (list "total" "expected")))
                (ty/termBranch "allRan" (edge "passed" (list)) (edge "miscounted" (list))))
              (block "passed" (list) (ty/termReturn "zero"))
              (block "miscounted" (list (rawInt "bad" 100)) (ty/termReturn "bad"))))))

fn primCheckModule -> ty/SsaModule
  (plainModule "primCheck" (list (primCheckFunction)))

fn binaryFn name: String prim: String -> ty/SsaFunction
  (ty/ssaFunction name (list) (list (ty/ssaParam "a" (ty/tyI64)) (ty/ssaParam "b" (ty/tyI64))) (ty/tyI64)
    (list (block "entry" (list (ty/ssaInstr "r" (ty/tyI64) (ty/opPrim prim (list "a" "b")))) (ty/termReturn "r"))))

fn trapEntry name: String callee: String a: Int64 b: Int64 -> ty/SsaFunction
  (ty/ssaFunction name (list) (list) (ty/tyI64)
    (list (block "entry" (list (rawInt "a" a) (rawInt "b" b) (ty/ssaInstr "r" (ty/tyI64) (ty/opCall callee (list "a" "b")))) (ty/termReturn "r"))))

fn floatTrapEntry name: String numerator: Float64 denominator: Float64 -> ty/SsaFunction
  (ty/ssaFunction name (list) (list) (ty/tyI64)
    (list (block "entry" (list (rawFloat "x" numerator) (rawFloat "y" denominator)
                               (prim "q" (ty/tyF64) "divFloat" (list "x" "y"))
                               (ty/ssaInstr "r" (ty/tyI64) (ty/opCall "toInt" (list "q"))))
            (ty/termReturn "r"))))

fn narrowEntry name: String x: Int64 -> ty/SsaFunction
  (ty/ssaFunction name (list) (list) (ty/tyI64)
    (list (block "entry" (list (rawInt "x" x) (prim "n" (ty/tyI32) "rawNarrowI32" (list "x")) (prim "w" (ty/tyI64) "rawWidenI32" (list "n"))) (ty/termReturn "w"))))

fn trapModule -> ty/SsaModule
  (plainModule "traps"
    (list (binaryFn "add" "addInt") (binaryFn "sub" "subInt") (binaryFn "mul" "mulInt") (binaryFn "quot" "quotInt") (binaryFn "rem" "remInt")
          (ty/ssaFunction "toInt" (list) (list (ty/ssaParam "x" (ty/tyF64))) (ty/tyI64)
            (list (block "entry" (list (prim "r" (ty/tyI64) "floatToInt" (list "x"))) (ty/termReturn "r"))))
          (trapEntry "control" "quot" 7 2)
          (trapEntry "quotZero" "quot" 7 0)
          (trapEntry "quotMin" "quot" -9223372036854775808 -1)
          (trapEntry "remZero" "rem" 7 0)
          (trapEntry "addOver" "add" 9223372036854775807 1)
          (trapEntry "subOver" "sub" -9223372036854775807 2)
          (trapEntry "mulOver" "mul" 4611686018427387904 2)
          (floatTrapEntry "floatControl" -7.0 2.0)
          (floatTrapEntry "floatNan" 0.0 0.0)
          (floatTrapEntry "floatHuge" 1e19 1.0)
          (narrowEntry "narrowControl" 42)
          (narrowEntry "narrowOver" 9223372036854775807)))

fn trapEntries -> (List String)
  (list "quotZero" "quotMin" "remZero" "addOver" "subOver" "mulOver")

fn hostMsgEntries -> (List String)
  (list "floatNan" "floatHuge" "narrowOver")

fn fixture name: String -> (Result String (List ty/IrDiag))
  (cond
    ((= name "fib") (llvm/emitLlvmProgram (fibModule) "fibMain"))
    ((= name "loop") (llvm/emitLlvmProgram (loopModule) "swapMain"))
    ((= name "switch") (llvm/emitLlvmModule (switchModule)))
    ((= name "ops") (llvm/emitLlvmModule (opsModule)))
    ((= name "fibRaw") (llvm/emitLlvmProgram (fibRawModule) "fibMain"))
    ((= name "primCheck") (llvm/emitLlvmProgram (primCheckModule) "primCheck"))
    ((= name "traps") (llvm/emitLlvmModule (trapModule)))
    ((stringStartsWith? name "trap:") (llvm/emitLlvmProgram (trapModule) (optionOr (stringSlice name 5 (stringLength name)) "")))
    (else (err (list (ty/makeIrDiag "ERR_FIXTURE" (str "unknown fixture " name) name)))))

fn diagText diags: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) diags) "; ")

fn ! main args: (List String) -> (Result Int64 String)
  (mt (listHead args)
    ((none) (err "usage: irE2eTest.asl fib|loop|switch|ops|fibRaw|primCheck|traps|trap:ENTRY"))
    ((some name) (mt (fixture name)
                   ((ok text) (do (print text) (ok 0)))
                   ((err diags) (err (diagText diags))))))

fn golden! name: String -> String
  (mt (fileReadString (str "asl/packages/asl-target-llvm/tests/golden/" name ".ll"))
    ((ok text) text)
    ((err e) (str "missing golden " name ": " e)))

fn ! matchesGolden? name: String -> Bool
  (mt (fixture name)
    ((ok text) (= text (golden! name)))
    ((err _) false))

fn codes res: (Result String (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err diags) (map (fn [(d ty/IrDiag)] -> String d.code) diags)))

fn testGoldens! -> Bool
  (do (assert (matchesGolden? "fib") "fib over Val: builtin calls with hoisted argv, recursion, Val branch inlines its own tag check and trap (RT-MEMORY M2), program wrapper unboxes the result")
      (assert (matchesGolden? "loop") "raw loop: head phis swap a and b on the back edge; pick splits both edges into join so each phi entry has its own predecessor")
      (assert (matchesGolden? "switch") "switch: tags by declaration position, default edge carries the join argument, exhaustive switch falls to an unreachable block")
      (assert (matchesGolden? "ops") "every Val operation lowers to its asl_rt_* call, closures get a trampoline, globals an init function, only used runtime functions are declared")
      (assert (matchesGolden? "fibRaw") "raw fib: i64 params, icmp slt, overflow-checked sub and add trapping through llvm.trap, direct recursion, no runtime")
      (assert (matchesGolden? "primCheck") "every primitive lowers natively; phis after a trapping primitive name its continuation block")
      (assert (matchesGolden? "traps") "quot and rem guard the divisor, floatToInt guards NaN and range, each trapping primitive branches to llvm.trap")
      true)

fn testVerifierGuards -> Bool
  (let [(broken (plainModule "broken" (list (ty/ssaFunction "f" (list) (list) (ty/tyI64) (list (block "entry" (list) (ty/termReturn "ghost")))))))
        (mainClash (plainModule "clash" (list (ty/ssaFunction "main" (list) (list) (ty/tyI64) (list (block "entry" (list (rawInt "z" 0)) (ty/termReturn "z")))))))]
    (do (assert (= (codes (llvm/emitLlvmModule broken)) (list "ERR_IR_UNDEFINED_VALUE")) "a module that fails verifySsa is not emitted")
        (assert (= (codes (llvm/emitLlvmProgram (loopModule) "nowhere")) (list "ERR_LLVM_ENTRY")) "a missing entry function is rejected")
        (assert (= (codes (llvm/emitLlvmProgram (loopModule) "pick")) (list "ERR_LLVM_ENTRY")) "an entry function with parameters is rejected")
        (assert (ok? (llvm/emitLlvmProgram mainClash "main")) "a module function named main is accepted by the wrapper")
        (assert (ok? (llvm/emitLlvmModule mainClash)) "a module function named main is fine without the wrapper")
        true))

fn testRawPrograms -> Bool
  (let [(fibText (mt (fixture "fibRaw") ((ok t) t) ((err _) "")))
        (badPrim (plainModule "bad" (list (ty/ssaFunction "f" (list) (list (ty/ssaParam "x" (ty/tyF64))) (ty/tyI64)
                                              (list (block "entry" (list (rawInt "one" 1) (prim "r" (ty/tyI64) "addInt" (list "x" "one"))) (ty/termReturn "r")))))))]
    (do (refute (stringContains? fibText "asl_rt_") "raw fib needs no runtime function")
        (assert (stringContains? fibText "declare void @llvm.trap()") "raw fib declares llvm.trap for its checked arithmetic")
        (assert (= (codes (llvm/emitLlvmModule badPrim)) (list "ERR_IR_TYPE_MISMATCH")) "a prim mixing f64 and i64 is not emitted")
        (assert (listEmpty? (filter (fn [(e String)] -> Bool (err? (fixture (str "trap:" e)))) (cons "control" (cons "floatControl" (cons "narrowControl" (listAppend (trapEntries) (hostMsgEntries))))))) "every trap entry emits as a program")
        true))

fn testNames -> Bool
  (do (assert (= (ssa/llvmName "fibMain") "fibMain") "letters and digits stay")
      (assert (= (ssa/llvmName "a-b") "a$2Db") "a hyphen is hex-escaped")
      (assert (= (ssa/llvmName "9lives") "$39lives") "a leading digit is escaped")
      (assert (= (ssa/llvmName "$") "$24") "the escape character escapes itself")
      (assert (= (ssa/llvmName "") "$") "the empty name has its own encoding")
      (assert (= (ssa/llvmName "x.y") "x$2Ey") "a dot is escaped, so emitter-made names never collide")
      (assert (= (ssa/llvmName "é") "$C3$A9") "non-ASCII escapes byte by byte")
      (assert (= (ssa/llvmBytes "a\"\\\n\x00é") "a\\22\\5C\\0A\\00\\C3\\A9") "string bytes escape quote, backslash, controls and non-ASCII")
      (assert (= (ssa/llvmFloat 2.0) "2.0") "an integral float keeps its point")
      (assert (= (ssa/llvmFloat 1e300) "1.0e+300") "an exponent gets a point")
      (assert (= (ssa/llvmFloat (floatInf)) "0x7FF0000000000000") "infinity is written in hex")
      (assert (= (ssa/llvmFloat (floatNan)) "0x7FF8000000000000") "NaN is written in hex")
      true)

fn wideExternModule n: Int64 -> ty/SsaModule
  (ty/ssaModule "wideExtern" (list) (list) (list)
    (list (ty/ssaExternTyped "other/wide" (map (fn [(i Int64)] -> ty/SsaTy (ty/tyVal)) (range 0 n)) (ty/tyVal))) (list) (list))

fn testAbiLimits -> Bool
  (do (assert (listEmpty? (ssa/overwideCDecls)) (str "every runtime C declaration fits the argument registers: " (stringJoin (ssa/overwideCDecls) "; ")))
      (assert (ssa/cDeclFits? "declare %Val @sixWords(%Val, i64, i64, %Val)") "six integer words fit")
      (assert (not (ssa/cDeclFits? "declare %Val @wide(%Val, %Val, %Val, i64)")) "seven integer words are flagged")
      (assert (not (ssa/cDeclFits? "declare double @f(double, double, double, double, double, double, double, double, double)")) "nine doubles are flagged")
      (assert (= (codes (ssa/emitLlvmModule (wideExternModule 1040))) (list "ERR_LLVM_ARITY")) "a typed extern spilling 1037 arguments is ERR_LLVM_ARITY")
      (assert (= (codes (ssa/emitLlvmModule (wideExternModule 1027))) (list)) "a typed extern spilling exactly 1024 arguments emits")
      true)

fn ! runTests -> Bool
  (do (assert (testGoldens!) "testGoldens")
      (assert (testVerifierGuards) "testVerifierGuards")
      (assert (testRawPrograms) "testRawPrograms")
      (assert (testNames) "testNames")
      (assert (testAbiLimits) "testAbiLimits")
      true)
