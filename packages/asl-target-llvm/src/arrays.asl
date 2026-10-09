(module asl-target-llvm/arrays
  :x [ArrCtx arrayBuiltinNames functionName arrStrings arrExterns arrFunctions helperDefinitions]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/rtError :a rterr)])

schema ArrCtx
  pool: (Map String Int64)

fn pn name: String -> String
  (str "asl-target-llvm/arrays." name)

fn kinds -> (List String)
  (list "f64" "i64" "i8")

fn ops -> (List String)
  (list "Len" "Get" "Slice" "Concat" "Generate" "Sum" "CountEq" "Fold" "Scan")

fn kernelNames -> (List String)
  (list "dot" "axpy" "gemm")

fn arrayBuiltinNames -> (List String)
  (listAppend (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (map (fn [(op String)] -> String (str p "Array" op)) (ops))))
                    (list) (kinds))
              (kernelNames))

fn functionName builtin: String -> String
  (pn builtin)

fn tagInt -> Int64
  2

fn tagFloat -> Int64
  3

fn tagList -> Int64
  6

fn tagF64 -> Int64
  12

fn objArr -> Int64
  6

fn maxElements -> Int64
  16777216

fn messageBytes -> Int64
  4096

fn tagOfKind kind: String -> Int64
  (cond ((= kind "f64") 12) ((= kind "i64") 13) (else 14))

fn elemOfKind kind: String -> Int64
  (if (= kind "i8") 1 8)

fn typeOfKind kind: String -> String
  (cond ((= kind "f64") "F64Array") ((= kind "i64") "I64Array") (else "I8Array"))

fn tagNames -> (List String)
  (list "Unit" "Bool" "Int" "Float" "Keyword" "String" "List" "Record" "Variant" "Fn" "Builtin" "Bytes" "F64Array" "I64Array" "I8Array" "Handle")

fn formats -> (List String)
  (list "%s expects %s, got %s" "%s expects Int, got %s" "%s expects Float, got %s" "%s expects (List %s), got %s"
        "%s index %lld outside length %lld" "%s [%lld, %lld) outside length %lld" "%s: negative length %lld"
        "%s: element must be Float, got %s" "%s: element must be Int, got %s" "%s: %lld outside I8" "%s leaves int64"
        "%s: accumulator must be Int, got %s" "%s of %lld elements exceeds the array allocation limit" "cannot allocate %s of %lld elements"
        "dot: array lengths differ (%lld vs %lld)" "axpy expects (Float, F64Array, F64Array)" "axpy: array lengths differ (%lld vs %lld)"
        "gemm expects (m: Int, n: Int, k: Int, a: F64Array, b: F64Array)" "gemm: negative matrix dimensions (m=%lld, n=%lld, k=%lld)"
        "gemm: m * k exceeds addressable range" "gemm: k * n exceeds addressable range" "gemm: m * n exceeds addressable range"
        "gemm: array A length %lld does not match m*k = %lld" "gemm: array B length %lld does not match k*n = %lld"
        "cannot allocate an error message")

fn arrStrings -> (List String)
  (listAppend (list "ERR_TYPE" "ERR_RANGE" "ERR_INT_OVERFLOW" "ERR_SHAPE" "ERR_OOM" "?")
    (listAppend (formats) (listAppend (arrayBuiltinNames) (tagNames))))

fn appendAll lists: (List (List V)) -> (List V)
  (fold (fn [(acc (List V)) (l (List V))] -> (List V) (listAppend acc l)) (list) lists)

fn i1 -> ty/SsaTy
  (ty/tyI1)

fn i64 -> ty/SsaTy
  (ty/tyI64)

fn i32 -> ty/SsaTy
  (ty/tyI32)

fn f64 -> ty/SsaTy
  (ty/tyF64)

fn ptr -> ty/SsaTy
  (ty/tyPtr)

fn val -> ty/SsaTy
  (ty/tyVal)

fn ins d: String t: ty/SsaTy op: ty/SsaOp -> (List ty/SsaInstr)
  (list (ty/ssaInstr d t op))

fn k d: String n: Int64 -> (List ty/SsaInstr)
  (ins d (i64) (ty/opConst (ty/constInt n)))

fn k32 d: String n: Int64 -> (List ty/SsaInstr)
  (ins d (i32) (ty/opConst (ty/constInt n)))

fn kf d: String x: Float64 -> (List ty/SsaInstr)
  (ins d (f64) (ty/opConst (ty/constFloat x)))

fn pr d: String t: ty/SsaTy name: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opPrim name args))

fn ex d: String t: ty/SsaTy callee: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opCall callee args))

fn hp d: String t: ty/SsaTy name: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opCall (pn name) args))

fn box d: String x: String -> (List ty/SsaInstr)
  (ins d (val) (ty/opBox x))

fn unbox d: String t: ty/SsaTy v: String -> (List ty/SsaInstr)
  (ins d t (ty/opUnbox v))

fn i2p d: String i: String -> (List ty/SsaInstr)
  (pr d (ptr) "rawIntToPtr" (list i))

fn p2i d: String p: String -> (List ty/SsaInstr)
  (pr d (i64) "rawPtrToInt" (list p))

fn add d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawAddI64" (list a b))

fn addK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (add d a (str d ".k"))))

fn sub d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawSubI64" (list a b))

fn mul d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawMulI64" (list a b))

fn mulK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (mul d a (str d ".k"))))

fn cmp d: String name: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) name (list a b))

fn cmpK d: String name: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (cmp d name a (str d ".k"))))

fn orB d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) "orBool" (list a b))

fn andB d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) "andBool" (list a b))

fn bandK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (pr d (i64) "rawAndI64" (list a (str d ".k")))))

fn ld d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (pr d (i64) "rawLoadI64" (list (str d ".p") (str d ".o")))))

fn tagOf d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".a") (ptr) "aslArrWord0" (list v)) (p2i (str d ".x") (str d ".a")) (bandK d (str d ".x") 4294967295)))

fn objOf d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".b") (ptr) "aslArrWord1" (list v)) (p2i d (str d ".b"))))

fn lenOf d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (objOf (str d ".obj") v) (ld d (str d ".obj") 8)))

fn dataOf d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (objOf (str d ".o") v) (ld (str d ".i") (str d ".o") 24) (i2p d (str d ".i"))))

fn offset d: String base: String idx: String elem: Int64 -> (List ty/SsaInstr)
  (appendAll (list (p2i (str d ".b") base) (mulK (str d ".n") idx elem) (add (str d ".s") (str d ".b") (str d ".n")) (i2p d (str d ".s"))))

fn loadElem kind: String d: String data: String idx: String -> (List ty/SsaInstr)
  (cond
    ((= kind "f64") (ex d (f64) "aslArrLoadF64" (list data idx)))
    ((= kind "i64") (appendAll (list (mulK (str d ".o") idx 8) (pr d (i64) "rawLoadI64" (list data (str d ".o"))))))
    (else (appendAll (list (pr (str d ".b") (i32) "rawLoadI8" (list data idx)) (pr (str d ".u") (i64) "rawWidenI32" (list (str d ".b")))
                           (bandK (str d ".h") (str d ".u") 128) (mulK (str d ".s") (str d ".h") 2) (sub d (str d ".u") (str d ".s"))))))

fn loadBoxed kind: String d: String data: String idx: String -> (List ty/SsaInstr)
  (appendAll (list (loadElem kind (str d ".r") data idx) (box d (str d ".r"))))

fn rawTy kind: String -> ty/SsaTy
  (if (= kind "f64") (f64) (i64))

fn poolAt c: ArrCtx text: String -> Int64
  (optionOr (mapGet c.pool text) -1)

fn cs c: ArrCtx d: String text: String -> (List ty/SsaInstr)
  (ins d (ptr) (ty/opConst (ty/constStr (poolAt c text))))

fn block label: String parts: (List (List ty/SsaInstr)) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) (appendAll parts) term)

fn paramBlock label: String params: (List ty/SsaParam) parts: (List (List ty/SsaInstr)) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label params (appendAll parts) term)

fn jump label: String args: (List String) -> ty/SsaTerm
  (ty/termJump (ty/ssaEdge label args))

fn branch c: String yes: String no: String -> ty/SsaTerm
  (ty/termBranch c (ty/ssaEdge yes (list)) (ty/ssaEdge no (list)))

fn argBranch c: String yes: String yesArgs: (List String) no: String noArgs: (List String) -> ty/SsaTerm
  (ty/termBranch c (ty/ssaEdge yes yesArgs) (ty/ssaEdge no noArgs))

fn returnTerm v: String -> ty/SsaTerm
  (ty/termReturn v)

fn pI name: String -> ty/SsaParam
  (ty/ssaParam name (i64))

fn pF name: String -> ty/SsaParam
  (ty/ssaParam name (f64))

fn pV name: String -> ty/SsaParam
  (ty/ssaParam name (val))

fn function name: String params: (List ty/SsaParam) retTy: ty/SsaTy blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction (pn name) (list) params retTy blocks)

fn raiseBlocks c: ArrCtx label: String pre: (List (List ty/SsaInstr)) code: String fmt: String args: (List String) -> (List ty/SsaBlock)
  (let [(fmtL (str label ".fmt")) (noMem (str label ".nomem"))]
    (list
      (block label (listAppend pre (list (k (str label ".size") (messageBytes)) (ex (str label ".buf") (ptr) "malloc" (list (str label ".size")))
                                     (pr (str label ".null") (i1) "rawPtrIsNull" (list (str label ".buf")))))
        (branch (str label ".null") noMem fmtL))
      (block fmtL (list (cs c (str fmtL ".f") fmt)
                    (ex (str fmtL ".n") (i32) "snprintf" (listAppend (list (str label ".buf") (str label ".size") (str fmtL ".f")) args))
                    (ex (str fmtL ".len") (i64) "strlen" (list (str label ".buf")))
                    (if (listContains? (rterr/rtErrorTrapCodes) code)
                      (appendAll (list (ex (str fmtL ".msg") (val) "mkStr" (list (str label ".buf") (str fmtL ".len")))
                                       (ex (str fmtL ".free") (i64) "free" (list (str label ".buf")))
                                       (ins (str fmtL ".code") (val) (ty/opConst (ty/constStr (poolAt c code))))
                                       (ins (str fmtL ".trap") (val) (ty/opBuiltin "trap" (list (str fmtL ".code") (str fmtL ".msg"))))))
                      (appendAll (list (cs c (str fmtL ".code") code)
                                       (ex (str fmtL ".raise") (i32) "aslArrRaise" (list (str fmtL ".code") (str label ".buf") (str fmtL ".len")))))))
        (ty/termUnreachable))
      (block noMem (list (cs c (str noMem ".code") "ERR_OOM") (cs c (str noMem ".msg") "cannot allocate an error message")
                     (ex (str noMem ".len") (i64) "strlen" (list (str noMem ".msg")))
                     (ex (str noMem ".raise") (i32) "aslArrRaise" (list (str noMem ".code") (str noMem ".msg") (str noMem ".len"))))
        (ty/termUnreachable))))

fn tagNameOf d: String tag: String -> (List ty/SsaInstr)
  (hp d (ptr) "tagName" (list tag))

fn tagNameFn c: ArrCtx -> ty/SsaFunction
  (let [(n (listLength (tagNames)))]
    (function "tagName" (list (pI "tag")) (ptr)
      (appendAll
        (list
          (map (fn [(i Int64)] -> ty/SsaBlock
                 (let [(here (if (= i 0) "entry" (str "t" i)))
                       (next (if (= i (- n 1)) "unknown" (str "t" (+ i 1))))]
                   (block here (list (cmpK (str here ".eq") "eqInt" "tag" i)) (branch (str here ".eq") (str "n" i) next))))
               (range 0 n))
          (map (fn [(i Int64)] -> ty/SsaBlock
                 (block (str "n" i) (list (cs c (str "n" i ".s") (optionOr (listGet (tagNames) i) "?"))) (returnTerm (str "n" i ".s"))))
               (range 0 n))
          (list (block "unknown" (list (cs c "unknown.s" "?")) (returnTerm "unknown.s")))))))

fn checkTag c: ArrCtx label: String v: String want: Int64 okLabel: String fmt: String args: (List String) -> (List ty/SsaBlock)
  (listAppend
    (list (block label (list (tagOf (str label ".t") v) (cmpK (str label ".ok") "eqInt" (str label ".t") want)) (branch (str label ".ok") okLabel (str label ".bad"))))
    (raiseBlocks c (str label ".bad") (list (tagNameOf (str label ".bad.n") (str label ".t"))) "ERR_TYPE" fmt (listAppend args (list (str label ".bad.n")))))

fn checkArr c: ArrCtx kind: String label: String v: String who: String okLabel: String -> (List ty/SsaBlock)
  (checkTag c label v (tagOfKind kind) okLabel "%s expects %s, got %s" (list "who" (str label ".type")))

fn whoAnd c: ArrCtx label: String who: String kind: String -> (List (List ty/SsaInstr))
  (list (cs c "who" who) (cs c (str label ".type") (typeOfKind kind)))

fn checkInt c: ArrCtx label: String v: String okLabel: String -> (List ty/SsaBlock)
  (checkTag c label v (tagInt) okLabel "%s expects Int, got %s" (list "who"))

fn newArrayFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(elem (elemOfKind kind))]
    (function (str "new" kind) (list (pI "n")) (val)
      (appendAll
        (list
          (list (block "entry" (list (cs c "type" (typeOfKind kind)) (cmpK "huge" "gtInt" "n" (maxElements))) (branch "huge" "range" "alloc")))
          (raiseBlocks c "range" (list) "ERR_RANGE" "%s of %lld elements exceeds the array allocation limit" (list "type" "n"))
          (list (block "alloc" (list (mulK "bytes" "n" elem) (ex "will" (i64) "gcWillAllocate" (list "bytes")) (k32 "otype" (objArr)) (k "arrSize" 32)
                                 (ex "obj" (ptr) "aslArrAlloc" (list "otype" "arrSize")) (p2i "objI" "obj")
                                 (k "elem" elem) (st "se" "objI" 16 "elem") (st "sn" "objI" 8 "n")
                                 (addK "dataBytes" "bytes" 1) (ex "data" (ptr) "malloc" (list "dataBytes")) (pr "null" (i1) "rawPtrIsNull" (list "data")))
                  (branch "null" "oom" "ready")))
          (raiseBlocks c "oom" (list) "ERR_OOM" "cannot allocate %s of %lld elements" (list "type" "n"))
          (list (block "ready" (list (p2i "dataI" "data") (st "sd" "objI" 24 "dataI") (ex "accounted" (i64) "gcAccount" (list "obj" "bytes"))
                                 (k "tag" (tagOfKind kind)) (mkv "arr" "tag" "objI"))
                  (returnTerm "arr")))))))

fn st d: String addr: String off: Int64 v: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (pr d (i1) "rawStoreI64" (list (str d ".p") (str d ".o") v))))

fn mkv d: String w0: String w1: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".a") w0) (i2p (str d ".b") w1) (ex d (val) "aslArrMakeVal" (list (str d ".a") (str d ".b")))))

fn storeBlocks c: ArrCtx kind: String label: String v: String arr: String idx: String next: String nextArgs: (List String) -> (List ty/SsaBlock)
  (let [(put (str label ".put"))
        (isF (= kind "f64"))
        (tagCheck (checkTag c label v (if isF (tagFloat) (tagInt)) put (if isF "%s: element must be Float, got %s" "%s: element must be Int, got %s") (list "who")))]
    (listAppend tagCheck
      (cond
        (isF (list (block put (list (unbox (str put ".x") (f64) v) (dataOf (str put ".d") arr)
                                (ex (str put ".s") (i32) "aslArrStoreF64" (list (str put ".d") idx (str put ".x"))))
                     (jump next nextArgs))))
        ((= kind "i64") (list (block put (list (unbox (str put ".x") (i64) v) (dataOf (str put ".d") arr) (mulK (str put ".o") idx 8)
                                           (pr (str put ".s") (i1) "rawStoreI64" (list (str put ".d") (str put ".o") (str put ".x"))))
                                (jump next nextArgs))))
        (else (listAppend
                (list (block put (list (unbox (str put ".x") (i64) v) (cmpK (str put ".lo") "ltInt" (str put ".x") -128) (cmpK (str put ".hi") "gtInt" (str put ".x") 127)
                                   (orB (str put ".out") (str put ".lo") (str put ".hi")))
                        (branch (str put ".out") (str put ".range") (str put ".byte")))
                      (block (str put ".byte") (list (pr (str put ".w") (i32) "rawNarrowI32" (list (str put ".x"))) (dataOf (str put ".d") arr)
                                                 (pr (str put ".s") (i1) "rawStoreI8" (list (str put ".d") idx (str put ".w"))))
                        (jump next nextArgs)))
                (raiseBlocks c (str put ".range") (list) "ERR_RANGE" "%s: %lld outside I8" (list "who" (str put ".x"))))))))

fn who kind: String op: String -> String
  (str kind "Array" op)

fn lenFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "Len"))]
    (function w (list (pV "a")) (val)
      (appendAll
        (list
          (list (block "entry" (whoAnd c "a" w kind) (jump "a" (list))))
          (checkArr c kind "a" "a" w "ok")
          (list (block "ok" (list (lenOf "n" "a") (box "r" "n")) (returnTerm "r")))))))

fn getFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "Get"))]
    (function w (list (pV "a") (pV "i")) (val)
      (appendAll
        (list
          (list (block "entry" (whoAnd c "a" w kind) (jump "a" (list))))
          (checkArr c kind "a" "a" w "i")
          (checkInt c "i" "i" "range")
          (list (block "range" (list (unbox "iv" (i64) "i") (lenOf "n" "a") (cmpK "neg" "ltInt" "iv" 0) (cmp "past" "geInt" "iv" "n") (orB "bad" "neg" "past"))
                  (branch "bad" "oob" "load")))
          (raiseBlocks c "oob" (list) "ERR_RANGE" "%s index %lld outside length %lld" (list "who" "iv" "n"))
          (list (block "load" (list (dataOf "d" "a") (loadBoxed kind "r" "d" "iv")) (returnTerm "r")))))))

fn sliceFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "Slice")) (elem (elemOfKind kind))]
    (function w (list (pV "a") (pV "s") (pV "e")) (val)
      (appendAll
        (list
          (list (block "entry" (whoAnd c "a" w kind) (jump "a" (list))))
          (checkArr c kind "a" "a" w "s")
          (checkInt c "s" "s" "e")
          (checkInt c "e" "e" "range")
          (list (block "range" (list (unbox "sv" (i64) "s") (unbox "ev" (i64) "e") (lenOf "n" "a")
                                 (cmpK "neg" "ltInt" "sv" 0) (cmp "back" "ltInt" "ev" "sv") (cmp "past" "gtInt" "ev" "n") (orB "bad0" "neg" "back") (orB "bad" "bad0" "past"))
                  (branch "bad" "oob" "copy")))
          (raiseBlocks c "oob" (list) "ERR_RANGE" "%s [%lld, %lld) outside length %lld" (list "who" "sv" "ev" "n"))
          (list (block "copy" (list (sub "m" "ev" "sv") (hp "r" (val) (str "new" kind) (list "m")) (dataOf "rd" "r") (dataOf "xd" "a")
                                (offset "src" "xd" "sv" elem) (mulK "bytes" "m" elem) (ex "cp" (ptr) "memcpy" (list "rd" "src" "bytes")))
                  (returnTerm "r")))))))

fn concatFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "Concat")) (elem (elemOfKind kind))]
    (function w (list (pV "xs")) (val)
      (appendAll
        (list
          (list (block "entry" (listAppend (whoAnd c "car" w kind) (list (tagOf "t" "xs") (cmpK "isList" "eqInt" "t" (tagList)))) (branch "isList" "sum0" "notList")))
          (raiseBlocks c "notList" (list (tagNameOf "tn" "t")) "ERR_TYPE" "%s expects (List %s), got %s" (list "who" "car.type" "tn"))
          (list (block "sum0" (list (objOf "head" "xs") (k "zero" 0)) (jump "sumLoop" (list "head" "zero")))
                (paramBlock "sumLoop" (list (pI "cell") (pI "n")) (list (cmpK "nil" "eqInt" "cell" 0)) (argBranch "nil" "alloc" (list "n") "car" (list))))
          (checkTagWord c "car" "cell" (tagOfKind kind) "sumAdd" "%s expects %s, got %s" (list "who" "car.type"))
          (list (block "sumAdd" (list (ld "co" "cell" 16) (ld "cl" "co" 8) (add "n2" "n" "cl") (ld "next" "cell" 32)) (jump "sumLoop" (list "next" "n2")))
                (paramBlock "alloc" (list (pI "total")) (list (hp "r" (val) (str "new" kind) (list "total")) (dataOf "rd" "r") (objOf "first" "xs") (k "at0" 0))
                  (jump "copyLoop" (list "first" "at0")))
                (paramBlock "copyLoop" (list (pI "c") (pI "at")) (list (cmpK "end" "eqInt" "c" 0)) (branch "end" "done" "copy"))
                (block "copy" (list (ld "xo" "c" 16) (ld "xl" "xo" 8) (ld "xdi" "xo" 24) (i2p "xd" "xdi") (offset "dst" "rd" "at" elem) (mulK "bytes" "xl" elem)
                                (ex "cp" (ptr) "memcpy" (list "dst" "xd" "bytes")) (add "at2" "at" "xl") (ld "cnext" "c" 32))
                  (jump "copyLoop" (list "cnext" "at2")))
                (block "done" (list) (returnTerm "r")))))))

fn checkTagWord c: ArrCtx label: String cell: String want: Int64 okLabel: String fmt: String args: (List String) -> (List ty/SsaBlock)
  (listAppend
    (list (block label (list (ld (str label ".w") cell 8) (bandK (str label ".t") (str label ".w") 4294967295) (cmpK (str label ".ok") "eqInt" (str label ".t") want))
            (branch (str label ".ok") okLabel (str label ".bad"))))
    (raiseBlocks c (str label ".bad") (list (tagNameOf (str label ".bad.n") (str label ".t"))) "ERR_TYPE" fmt (listAppend args (list (str label ".bad.n")))))

fn generateFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "Generate"))]
    (function w (list (pV "n") (pV "f")) (val)
      (appendAll
        (list
          (list (block "entry" (list (cs c "who" w)) (jump "n" (list))))
          (checkInt c "n" "n" "neg")
          (list (block "neg" (list (unbox "nv" (i64) "n") (cmpK "isNeg" "ltInt" "nv" 0)) (branch "isNeg" "negBad" "alloc")))
          (raiseBlocks c "negBad" (list) "ERR_RANGE" "%s: negative length %lld" (list "who" "nv"))
          (list (block "alloc" (list (hp "r" (val) (str "new" kind) (list "nv")) (k "i0" 0)) (jump "loop" (list "i0")))
                (paramBlock "loop" (list (pI "i")) (list (cmp "done" "geInt" "i" "nv")) (branch "done" "fin" "call"))
                (block "call" (list (box "iv" "i") (ins "v" (val) (ty/opCallClosure "f" (list "iv")))) (jump "set" (list))))
          (storeBlocks c kind "set" "v" "r" "i" "step" (list))
          (list (block "step" (list (addK "i2" "i" 1)) (jump "loop" (list "i2")))
                (block "fin" (list) (returnTerm "r")))))))

fn sumFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "Sum"))]
    (function w (list (pV "a")) (val)
      (appendAll
        (list
          (list (block "entry" (whoAnd c "a" w kind) (jump "a" (list))))
          (checkArr c kind "a" "a" w "init")
          (if (= kind "f64")
            (list
              (block "init" (list (lenOf "n" "a") (dataOf "d" "a") (k "i0" 0) (kf "z" 0.0)) (jump "loop" (list "i0" "z" "z")))
              (paramBlock "loop" (list (pI "i") (pF "s") (pF "c")) (list (cmp "done" "geInt" "i" "n")) (branch "done" "fin" "body"))
              (block "body" (list (loadElem kind "v" "d" "i") (pr "u" (f64) "addFloat" (list "s" "v"))
                              (ex "as" (f64) "aslArrFabs" (list "s")) (ex "av" (f64) "aslArrFabs" (list "v")) (cmp "ge" "geFloat" "as" "av"))
                (branch "ge" "big" "small"))
              (block "big" (list (pr "b1" (f64) "subFloat" (list "s" "u")) (pr "b2" (f64) "addFloat" (list "b1" "v"))) (jump "join" (list "b2")))
              (block "small" (list (pr "m1" (f64) "subFloat" (list "v" "u")) (pr "m2" (f64) "addFloat" (list "m1" "s"))) (jump "join" (list "m2")))
              (paramBlock "join" (list (pF "t")) (list (pr "c2" (f64) "addFloat" (list "c" "t")) (addK "i2" "i" 1)) (jump "loop" (list "i2" "u" "c2")))
              (block "fin" (list (kf "fz" 0.0) (cmp "nz" "neFloat" "c" "fz") (pr "cc" (f64) "subFloat" (list "c" "c")) (cmp "finite" "eqFloat" "cc" "fz") (andB "use" "nz" "finite"))
                (branch "use" "comp" "plain"))
              (block "comp" (list (pr "sc" (f64) "addFloat" (list "s" "c")) (box "rc" "sc")) (returnTerm "rc"))
              (block "plain" (list (box "rp" "s")) (returnTerm "rp")))
            (list
              (block "init" (list (lenOf "n" "a") (dataOf "d" "a") (k "i0" 0)) (jump "loop" (list "i0" "i0")))
              (paramBlock "loop" (list (pI "i") (pI "s")) (list (cmp "done" "geInt" "i" "n")) (branch "done" "fin" "body"))
              (block "body" (list (loadElem kind "v" "d" "i") (add "s2" "s" "v") (pr "x1" (i64) "rawXorI64" (list "s" "s2")) (pr "x2" (i64) "rawXorI64" (list "v" "s2"))
                              (pr "x3" (i64) "rawAndI64" (list "x1" "x2")) (cmpK "ovf" "ltInt" "x3" 0))
                (branch "ovf" "overflow" "step"))
              (block "step" (list (addK "i2" "i" 1)) (jump "loop" (list "i2" "s2")))
              (block "fin" (list (box "r" "s")) (returnTerm "r"))))
          (if (= kind "f64") (list) (raiseBlocks c "overflow" (list) "ERR_INT_OVERFLOW" "%s leaves int64" (list "who")))))))

fn countEqFn c: ArrCtx kind: String -> ty/SsaFunction
  (let [(w (who kind "CountEq")) (isF (= kind "f64"))]
    (function w (list (pV "a") (pV "x")) (val)
      (appendAll
        (list
          (list (block "entry" (whoAnd c "a" w kind) (jump "a" (list))))
          (checkArr c kind "a" "a" w "x")
          (if isF (checkTag c "x" "x" (tagFloat) "start" "%s expects Float, got %s" (list "who")) (checkInt c "x" "x" "start"))
          (list (block "start" (list (unbox "xv" (rawTy kind) "x") (lenOf "n" "a") (dataOf "d" "a") (k "z" 0)) (jump "loop" (list "z" "z")))
                (paramBlock "loop" (list (pI "i") (pI "cnt")) (list (cmp "done" "geInt" "i" "n")) (branch "done" "fin" "body"))
                (block "body" (list (loadElem kind "v" "d" "i") (cmp "eq" (if isF "eqFloat" "eqInt") "v" "xv")) (branch "eq" "hit" "miss"))
                (block "hit" (list (addK "cnt2" "cnt" 1)) (jump "step" (list "cnt2")))
                (block "miss" (list) (jump "step" (list "cnt")))
                (paramBlock "step" (list (pI "cnt3")) (list (addK "i2" "i" 1)) (jump "loop" (list "i2" "cnt3")))
                (block "fin" (list (box "r" "cnt")) (returnTerm "r")))))))

fn foldScanFn c: ArrCtx kind: String keep: Bool -> ty/SsaFunction
  (let [(w (who kind (if keep "Scan" "Fold")))]
    (function w (list (pV "f") (pV "init") (pV "xs")) (val)
      (appendAll
        (list
          (list (block "entry" (whoAnd c "xs" w kind) (jump "xs" (list))))
          (checkArr c kind "xs" "xs" w "start")
          (list (block "start" (list (lenOf "n" "xs") (if keep (hp "out" (val) (str "new" kind) (list "n")) (list)) (k "i0" 0)) (jump "loop" (list "i0" "init")))
                (paramBlock "loop" (list (pI "i") (pV "acc")) (list (cmp "done" "geInt" "i" "n")) (branch "done" "fin" "body"))
                (block "body" (list (dataOf "d" "xs") (loadBoxed kind "x" "d" "i") (ins "acc2" (val) (ty/opCallClosure "f" (list "acc" "x"))))
                  (jump (if keep "set" "step") (list))))
          (if keep (storeBlocks c kind "set" "acc2" "out" "i" "step" (list)) (list))
          (list (block "step" (list (addK "i2" "i" 1)) (jump "loop" (list "i2" "acc2"))))
          (cond
            (keep (list (block "fin" (list) (returnTerm "out"))))
            ((= kind "f64") (list (block "fin" (list) (returnTerm "acc"))))
            (else (listAppend (checkTag c "fin" "acc" (tagInt) "ret" "%s: accumulator must be Int, got %s" (list "who"))
                              (list (block "ret" (list) (returnTerm "acc"))))))))))

fn sizeLimit -> Int64
  2305843009213693951

fn dotFn c: ArrCtx -> ty/SsaFunction
  (function "dot" (list (pV "a") (pV "b")) (val)
    (appendAll
      (list
        (list (block "entry" (whoAnd c "a" "dot" "f64") (jump "a" (list))))
        (checkArr c "f64" "a" "a" "dot" "b")
        (checkTag c "b" "b" (tagF64) "shape" "%s expects %s, got %s" (list "who" "a.type"))
        (list (block "shape" (list (lenOf "la" "a") (lenOf "lb" "b") (cmp "differ" "neInt" "la" "lb")) (branch "differ" "bad" "start")))
        (raiseBlocks c "bad" (list) "ERR_SHAPE" "dot: array lengths differ (%lld vs %lld)" (list "la" "lb"))
        (list (block "start" (list (dataOf "pa" "a") (dataOf "pb" "b") (k "i0" 0) (kf "z" 0.0)) (jump "loop" (list "i0" "z")))
              (paramBlock "loop" (list (pI "i") (pF "s")) (list (cmp "done" "geInt" "i" "la")) (branch "done" "fin" "body"))
              (block "body" (list (loadElem "f64" "x" "pa" "i") (loadElem "f64" "y" "pb" "i") (ex "s2" (f64) "aslArrMulAdd" (list "x" "y" "s")) (addK "i2" "i" 1))
                (jump "loop" (list "i2" "s2")))
              (block "fin" (list (box "r" "s")) (returnTerm "r"))))))

fn axpyFn c: ArrCtx -> ty/SsaFunction
  (function "axpy" (list (pV "alpha") (pV "x") (pV "y")) (val)
    (appendAll
      (list
        (list (block "entry" (list (tagOf "ta" "alpha") (tagOf "tx" "x") (tagOf "ty" "y") (cmpK "okA" "eqInt" "ta" (tagFloat)) (cmpK "okX" "eqInt" "tx" (tagF64))
                               (cmpK "okY" "eqInt" "ty" (tagF64)) (andB "ok0" "okA" "okX") (andB "ok" "ok0" "okY"))
                (branch "ok" "shape" "bad")))
        (raiseBlocks c "bad" (list) "ERR_TYPE" "axpy expects (Float, F64Array, F64Array)" (list))
        (list (block "shape" (list (lenOf "lx" "x") (lenOf "ly" "y") (cmp "differ" "neInt" "lx" "ly")) (branch "differ" "shapeBad" "alloc")))
        (raiseBlocks c "shapeBad" (list) "ERR_SHAPE" "axpy: array lengths differ (%lld vs %lld)" (list "lx" "ly"))
        (list (block "alloc" (list (unbox "av" (f64) "alpha") (hp "r" (val) "newf64" (list "lx")) (dataOf "px" "x") (dataOf "py" "y") (dataOf "po" "r") (k "i0" 0))
                (jump "loop" (list "i0")))
              (paramBlock "loop" (list (pI "i")) (list (cmp "done" "geInt" "i" "lx")) (branch "done" "fin" "body"))
              (block "body" (list (loadElem "f64" "xv" "px" "i") (loadElem "f64" "yv" "py" "i") (ex "o" (f64) "aslArrMulAdd" (list "av" "xv" "yv"))
                              (ex "s" (i32) "aslArrStoreF64" (list "po" "i" "o")) (addK "i2" "i" 1))
                (jump "loop" (list "i2")))
              (block "fin" (list) (returnTerm "r"))))))

fn productCheck c: ArrCtx label: String a: String b: String next: String message: String -> (List ty/SsaBlock)
  (listAppend
    (list (block label (list (cmpK (str label ".ap") "gtInt" a 0) (cmpK (str label ".bp") "gtInt" b 0) (andB (str label ".both") (str label ".ap") (str label ".bp")))
            (branch (str label ".both") (str label ".q") next))
          (block (str label ".q") (list (k (str label ".lim") (sizeLimit)) (pr (str label ".quot") (i64) "quotInt" (list (str label ".lim") b))
                                    (cmp (str label ".over") "gtInt" a (str label ".quot")))
            (branch (str label ".over") (str label ".bad") next)))
    (raiseBlocks c (str label ".bad") (list) "ERR_RANGE" message (list)))

fn gemmFn c: ArrCtx -> ty/SsaFunction
  (function "gemm" (list (pV "m") (pV "n") (pV "k") (pV "a") (pV "b")) (val)
    (appendAll
      (list
        (list (block "entry" (list (tagOf "tm" "m") (tagOf "tn" "n") (tagOf "tk" "k") (tagOf "ta" "a") (tagOf "tb" "b")
                               (cmpK "okM" "eqInt" "tm" (tagInt)) (cmpK "okN" "eqInt" "tn" (tagInt)) (cmpK "okK" "eqInt" "tk" (tagInt))
                               (cmpK "okA" "eqInt" "ta" (tagF64)) (cmpK "okB" "eqInt" "tb" (tagF64))
                               (andB "ok0" "okM" "okN") (andB "ok1" "ok0" "okK") (andB "ok2" "ok1" "okA") (andB "ok" "ok2" "okB"))
                (branch "ok" "neg" "bad")))
        (raiseBlocks c "bad" (list) "ERR_TYPE" "gemm expects (m: Int, n: Int, k: Int, a: F64Array, b: F64Array)" (list))
        (list (block "neg" (list (unbox "mv" (i64) "m") (unbox "nv" (i64) "n") (unbox "kv" (i64) "k")
                             (cmpK "negM" "ltInt" "mv" 0) (cmpK "negN" "ltInt" "nv" 0) (cmpK "negK" "ltInt" "kv" 0) (orB "neg0" "negM" "negN") (orB "anyNeg" "neg0" "negK"))
                (branch "anyNeg" "negBad" "mk")))
        (raiseBlocks c "negBad" (list) "ERR_RANGE" "gemm: negative matrix dimensions (m=%lld, n=%lld, k=%lld)" (list "mv" "nv" "kv"))
        (productCheck c "mk" "mv" "kv" "kn" "gemm: m * k exceeds addressable range")
        (productCheck c "kn" "kv" "nv" "mn" "gemm: k * n exceeds addressable range")
        (productCheck c "mn" "mv" "nv" "sizes" "gemm: m * n exceeds addressable range")
        (list (block "sizes" (list (mul "needA" "mv" "kv") (mul "needB" "kv" "nv") (mul "needC" "mv" "nv") (lenOf "la" "a") (cmp "badA" "neInt" "la" "needA"))
                (branch "badA" "shapeA" "checkB")))
        (raiseBlocks c "shapeA" (list) "ERR_SHAPE" "gemm: array A length %lld does not match m*k = %lld" (list "la" "needA"))
        (list (block "checkB" (list (lenOf "lb" "b") (cmp "badB" "neInt" "lb" "needB")) (branch "badB" "shapeB" "alloc")))
        (raiseBlocks c "shapeB" (list) "ERR_SHAPE" "gemm: array B length %lld does not match k*n = %lld" (list "lb" "needB"))
        (list (block "alloc" (list (hp "r" (val) "newf64" (list "needC")) (cmpK "emptyC" "eqInt" "needC" 0)) (branch "emptyC" "fin" "zero"))
              (block "zero" (list (dataOf "pc" "r") (dataOf "pa" "a") (dataOf "pb" "b") (mulK "bytes" "needC" 8) (k32 "zeroByte" 0)
                              (ex "cleared" (ptr) "memset" (list "pc" "zeroByte" "bytes")) (cmpK "emptyK" "eqInt" "kv" 0) (k "i0" 0))
                (argBranch "emptyK" "fin" (list) "iLoop" (list "i0")))
              (paramBlock "iLoop" (list (pI "i")) (list (cmp "iDone" "geInt" "i" "mv") (k "p0" 0)) (argBranch "iDone" "fin" (list) "pLoop" (list "p0")))
              (paramBlock "pLoop" (list (pI "p")) (list (cmp "pDone" "geInt" "p" "kv")) (branch "pDone" "iNext" "pBody"))
              (block "pBody" (list (mul "ai0" "i" "kv") (add "ai" "ai0" "p") (loadElem "f64" "aip" "pa" "ai") (k "j0" 0)) (jump "jLoop" (list "j0")))
              (paramBlock "jLoop" (list (pI "j")) (list (cmp "jDone" "geInt" "j" "nv")) (branch "jDone" "pNext" "jBody"))
              (block "jBody" (list (mul "bi0" "p" "nv") (add "bi" "bi0" "j") (mul "ci0" "i" "nv") (add "ci" "ci0" "j")
                               (loadElem "f64" "bv" "pb" "bi") (loadElem "f64" "cv" "pc" "ci") (ex "nc" (f64) "aslArrMulAdd" (list "aip" "bv" "cv"))
                               (ex "s" (i32) "aslArrStoreF64" (list "pc" "ci" "nc")) (addK "j2" "j" 1))
                (jump "jLoop" (list "j2")))
              (block "pNext" (list (addK "p2" "p" 1)) (jump "pLoop" (list "p2")))
              (block "iNext" (list (addK "i2" "i" 1)) (jump "iLoop" (list "i2")))
              (block "fin" (list) (returnTerm "r"))))))

fn helperExterns -> (List ty/SsaExtern)
  (list (ty/ssaExternTyped "aslArrWord0" (list (val)) (ptr)) (ty/ssaExternTyped "aslArrWord1" (list (val)) (ptr))
        (ty/ssaExternTyped "aslArrMakeVal" (list (ptr) (ptr)) (val)) (ty/ssaExternTyped "aslArrAlloc" (list (i32) (i64)) (ptr))
        (ty/ssaExternTyped "aslArrLoadF64" (list (ptr) (i64)) (f64)) (ty/ssaExternTyped "aslArrStoreF64" (list (ptr) (i64) (f64)) (i32))
        (ty/ssaExternTyped "aslArrFabs" (list (f64)) (f64)) (ty/ssaExternTyped "aslArrMulAdd" (list (f64) (f64) (f64)) (f64))
        (ty/ssaExternTyped "aslArrRaise" (list (ptr) (ptr) (i64)) (i32)))

fn arrExterns -> (List ty/SsaExtern)
  (listAppend (helperExterns)
    (list (ty/ssaExternTyped "malloc" (list (i64)) (ptr)) (ty/ssaExternTyped "free" (list (ptr)) (i64))
          (ty/ssaExternTyped "memcpy" (list (ptr) (ptr) (i64)) (ptr)) (ty/ssaExternTyped "memset" (list (ptr) (i32) (i64)) (ptr))
          (ty/ssaExternTyped "strlen" (list (ptr)) (i64)) (ty/ssaExternVariadic "snprintf" (list (ptr) (i64) (ptr)) (i32))
          (ty/ssaExternTyped "mkStr" (list (ptr) (i64)) (val))
          (ty/ssaExternTyped "gcWillAllocate" (list (i64)) (i64)) (ty/ssaExternTyped "gcAccount" (list (ptr) (i64)) (i64))))

fn helperDefinitions -> (List (Pair String String))
  (list (pair "declare ptr @aslArrWord0(%Val)"
              "define internal ptr @aslArrWord0(%Val %v) {\n  %w = extractvalue %Val %v, 0\n  %p = inttoptr i64 %w to ptr\n  ret ptr %p\n}")
        (pair "declare ptr @aslArrWord1(%Val)"
              "define internal ptr @aslArrWord1(%Val %v) {\n  %w = extractvalue %Val %v, 1\n  %p = inttoptr i64 %w to ptr\n  ret ptr %p\n}")
        (pair "declare %Val @aslArrMakeVal(ptr, ptr)"
              "define internal %Val @aslArrMakeVal(ptr %a, ptr %b) {\n  %x = ptrtoint ptr %a to i64\n  %y = ptrtoint ptr %b to i64\n  %v0 = insertvalue %Val undef, i64 %x, 0\n  %v1 = insertvalue %Val %v0, i64 %y, 1\n  ret %Val %v1\n}")
        (pair "declare ptr @aslArrAlloc(i32, i64)"
              "define internal ptr @aslArrAlloc(i32 %t, i64 %n) {\n  %o = call ptr @asl_alloc(i32 %t, i64 %n)\n  ret ptr %o\n}")
        (pair "declare double @aslArrLoadF64(ptr, i64)"
              "define internal double @aslArrLoadF64(ptr %d, i64 %i) {\n  %p = getelementptr double, ptr %d, i64 %i\n  %x = load double, ptr %p\n  ret double %x\n}")
        (pair "declare i32 @aslArrStoreF64(ptr, i64, double)"
              "define internal i32 @aslArrStoreF64(ptr %d, i64 %i, double %x) {\n  %p = getelementptr double, ptr %d, i64 %i\n  store double %x, ptr %p\n  ret i32 0\n}")
        (pair "declare tailcc double @aslArrFabs(double)"
              "define internal tailcc double @aslArrFabs(double %x) {\n  %r = call double @llvm.fabs.f64(double %x)\n  ret double %r\n}")
        (pair "declare tailcc double @aslArrMulAdd(double, double, double)"
              "define internal tailcc double @aslArrMulAdd(double %a, double %b, double %c) {\n  %r = call double @llvm.fmuladd.f64(double %a, double %b, double %c)\n  ret double %r\n}")
        (pair "declare i32 @aslArrRaise(ptr, ptr, i64)"
              "define internal i32 @aslArrRaise(ptr %code, ptr %msg, i64 %len) {\n  call void @rterr.raise(ptr %code, ptr %msg, i64 %len)\n  unreachable\n}"))

fn arrFunctions pool: (Map String Int64) -> (List ty/SsaFunction)
  (let [(c (ArrCtx :pool pool))]
    (appendAll
      (list
        (list (tagNameFn c))
        (map (fn [(kd String)] -> ty/SsaFunction (newArrayFn c kd)) (kinds))
        (fold (fn [(acc (List ty/SsaFunction)) (kd String)] -> (List ty/SsaFunction)
                (listAppend acc (list (lenFn c kd) (getFn c kd) (sliceFn c kd) (concatFn c kd) (generateFn c kd) (sumFn c kd) (countEqFn c kd)
                                      (foldScanFn c kd false) (foldScanFn c kd true))))
              (list) (kinds))
        (list (dotFn c) (axpyFn c) (gemmFn c)))))
