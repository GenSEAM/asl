(module asl-target-llvm/ffiRoute
  :x [foreign? foreignNames routeForeign rejectForeign cParamTypes cReturnType]
  :i [(asl-ir/types :a ty)
      (asl-checker/foreign :a fsig)])

; (:m :ref FFI1 :do "a fn whose whole body is (foreign lib symbol sig) lowers to a stub holding opBuiltin foreign over constant strings; this route rebuilds each stub as a checked C ABI wrapper (unbox, range-check, copy, call, free, widen, box or Result) and adds the typed extern, so no foreign builtin reaches the emitter")
(schema Gen
  (:f label String)
  (:f params (List ty/SsaParam))
  (:f instrs (List ty/SsaInstr))
  (:f done (List ty/SsaBlock))
  (:f frees (List String))
  (:f strings (List String))
  (:f n Int64)
  (:f result Bool)
  (:f who String)
  (:f errno String)
  (:f closes (List String)))

(schema Built
  (:f function ty/SsaFunction)
  (:f externs (List ty/SsaExtern))
  (:f strings (List String)))

fn foreignInstr? i: ty/SsaInstr -> Bool
  (match i.op ((ty/opBuiltin name _) (= name "foreign")) (_ false))

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks)

fn holdsForeign? f: ty/SsaFunction -> Bool
  (listAny? foreignInstr? (instrsOf f))

fn foreign? m: ty/SsaModule -> Bool
  (listAny? holdsForeign? m.functions)

fn foreignNames m: ty/SsaModule -> (List String)
  (map (fn [(f ty/SsaFunction)] -> String f.name) (filter holdsForeign? m.functions))

fn diag code: String message: String locus: String -> ty/IrDiag
  (ty/makeIrDiag code message locus)

fn rejectForeign m: ty/SsaModule triple: String -> (List ty/IrDiag)
  (map (fn [(name String)] -> ty/IrDiag (diag "ERR_FOREIGN_TARGET" (str name " calls C through foreign, which only the native LLVM targets link; target " triple " has no C ABI") name)) (foreignNames m))

fn cParamTypes kind: String -> (List ty/SsaTy)
  (cond
    ((or (= (fsig/kindBase kind) "handle") (= (fsig/kindBase kind) "close")) (list (ty/tyPtr)))
    ((or (= kind "i32") (or (= kind "u32") (= kind "bool"))) (list (ty/tyI32)))
    ((or (= kind "i64") (= kind "u64")) (list (ty/tyI64)))
    ((= kind "f64") (list (ty/tyF64)))
    ((= kind "cstr") (list (ty/tyPtr)))
    ((or (= kind "str") (= kind "bytes")) (list (ty/tyPtr) (ty/tyI64)))
    ((or (= kind "str32") (= kind "bytes32")) (list (ty/tyPtr) (ty/tyI32)))
    (else (list)))

fn cReturnType kind: String -> ty/SsaTy
  (cond
    ((or (= kind "i32") (or (= kind "u32") (= kind "bool"))) (ty/tyI32))
    ((= kind "f64") (ty/tyF64))
    ((or (= kind "cstr") (= (fsig/kindBase kind) "handle")) (ty/tyPtr))
    (else (ty/tyI64)))

fn helperExterns -> (List ty/SsaExtern)
  (list (ty/ssaExternTyped "malloc" (list (ty/tyI64)) (ty/tyPtr))
        (ty/ssaExternTyped "free" (list (ty/tyPtr)) (ty/tyI64))
        (ty/ssaExternTyped "valToCStr" (list (ty/tyVal) (ty/tyI32)) (ty/tyPtr))
        (ty/ssaExternTyped "strlen" (list (ty/tyPtr)) (ty/tyI64))
        (ty/ssaExternTyped "mkStr" (list (ty/tyPtr) (ty/tyI64)) (ty/tyVal))
        (ty/ssaExternTyped "ffiMkHandle" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyVal))
        (ty/ssaExternTyped "ffiHandlePtr" (list (ty/tyVal)) (ty/tyPtr))
        (ty/ssaExternTyped "ffiHandleFin" (list (ty/tyVal)) (ty/tyPtr))
        (ty/ssaExternTyped "ffiHandleClear" (list (ty/tyVal)) (ty/tyPtr)))

fn errnoExterns accessor: String -> (List ty/SsaExtern)
  (list (ty/ssaExternTyped accessor (list) (ty/tyPtr))
        (ty/ssaExternTyped "strerror" (list (ty/tyI32)) (ty/tyPtr)))

fn emit g: Gen dest: String t: ty/SsaTy op: ty/SsaOp -> Gen
  (with g :instrs (cons (ty/ssaInstr dest t op) g.instrs))

fn prim g: Gen dest: String t: ty/SsaTy name: String args: (List String) -> Gen
  (emit g dest t (ty/opPrim name args))

fn int64 g: Gen dest: String v: Int64 -> Gen
  (emit g dest (ty/tyI64) (ty/opConst (ty/constInt v)))

fn int32 g: Gen dest: String v: Int64 -> Gen
  (emit g dest (ty/tyI32) (ty/opConst (ty/constInt v)))

fn call g: Gen dest: String t: ty/SsaTy callee: String args: (List String) -> Gen
  (emit g dest t (ty/opCall callee args))

fn close g: Gen term: ty/SsaTerm next: String nextParams: (List ty/SsaParam) -> Gen
  (with g :done (cons (ty/ssaBlock g.label g.params (listReverse g.instrs) term) g.done) :label next :params nextParams :instrs (list))

fn tick g: Gen -> Gen
  (with g :n (+ g.n 1))

fn label g: Gen stem: String -> String
  (str "ffi." stem (stringFromInt64 g.n))

fn pooled g: Gen text: String -> (Pair Gen Int64)
  (match (listIndexOf g.strings text)
    ((some i) (pair g i))
    ((none) (pair (with g :strings (listAppend g.strings (list text))) (listLength g.strings))))

fn addBlock g: Gen b: ty/SsaBlock -> Gen
  (with g :done (cons b g.done))

fn holding g: Gen ptr: String -> Gen
  (with g :frees (cons ptr g.frees))

fn clearFrees g: Gen -> Gen
  (with g :frees (list))

fn failBlock g: Gen name: String code: String message: String -> Gen
  (let [(frees (map (fn [(p String)] -> ty/SsaInstr (ty/ssaInstr (str name "." p ".free") (ty/tyI64) (ty/opCall "free" (list p)))) g.frees))]
    (if g.result
      (let [(text (pooled g (str code ": " message)))
            (g1 (pairFirst text))
            (body (listAppend frees (list (ty/ssaInstr (str name ".text") (ty/tyVal) (ty/opConst (ty/constStr (pairSecond text))))
                                          (ty/ssaInstr (str name ".v") (ty/tyVal) (ty/opConstruct "Result" "err" (list (str name ".text")))))))]
        (addBlock g1 (ty/ssaBlock name (list) body (ty/termReturn (str name ".v")))))
      (let [(c (pooled g code))
            (m (pooled (pairFirst c) message))
            (g2 (pairFirst m))
            (body (listAppend frees (list (ty/ssaInstr (str name ".code") (ty/tyVal) (ty/opConst (ty/constStr (pairSecond c))))
                                          (ty/ssaInstr (str name ".text") (ty/tyVal) (ty/opConst (ty/constStr (pairSecond m))))
                                          (ty/ssaInstr (str name ".trap") (ty/tyVal) (ty/opBuiltin "trap" (list (str name ".code") (str name ".text")))))))]
        (addBlock g2 (ty/ssaBlock name (list) body (ty/termUnreachable))))))

fn guard g: Gen bad: String code: String message: String -> Gen
  (let [(g1 (tick g))
        (failName (label g1 "fail"))
        (next (label g1 "ok"))
        (g2 (failBlock g1 failName code message))]
    (close g2 (ty/termBranch bad (ty/ssaEdge failName (list)) (ty/ssaEdge next (list))) next (list)))

fn outside g: Gen prefix: String v: String lo: Int64 hi: Int64 -> Gen
  (let [(g1 (int64 (int64 g (str prefix ".lo") lo) (str prefix ".hi") hi))
        (g2 (prim (prim g1 (str prefix ".below") (ty/tyI1) "ltInt" (list v (str prefix ".lo"))) (str prefix ".above") (ty/tyI1) "gtInt" (list v (str prefix ".hi"))))]
    (prim g2 (str prefix ".out") (ty/tyI1) "orBool" (list (str prefix ".below") (str prefix ".above"))))

fn rangeCheck g: Gen prefix: String v: String lo: Int64 hi: Int64 message: String -> Gen
  (guard (outside g prefix v lo hi) (str prefix ".out") "ERR_RANGE" message)

fn rawOf g: Gen p: ty/SsaParam want: ty/SsaTy dest: String -> (Pair Gen String)
  (if (= (ty/ssaTyName p.ty) (ty/ssaTyName want))
    (pair g p.name)
    (pair (emit g dest want (ty/opUnbox p.name)) dest))

fn argMessage g: Gen i: Int64 kind: String -> String
  (str g.who " argument " (stringFromInt64 (+ i 1)) " is outside C " kind)

fn copyBytes g: Gen prefix: String v: String -> (Pair Gen (Pair String String))
  (let [(n (str prefix ".len")) (ptr (str prefix ".ptr"))
        (g1 (int64 (emit g n (ty/tyI64) (ty/opEntry "bytesLength" (list v))) (str prefix ".one") 1))
        (g2 (call (prim g1 (str prefix ".size") (ty/tyI64) "rawAddI64" (list n (str prefix ".one"))) ptr (ty/tyPtr) "malloc" (list (str prefix ".size"))))
        (g3 (guard (prim g2 (str prefix ".null") (ty/tyI1) "rawPtrIsNull" (list ptr)) (str prefix ".null") "ERR_FOREIGN_NOMEM" (str g.who ": no memory for a Bytes copy")))
        (g4 (holding g3 ptr))
        (head (str prefix ".loop")) (body (str prefix ".body")) (exit (str prefix ".copied")) (i (str prefix ".i"))
        (g5 (close (int64 g4 (str prefix ".zero") 0) (ty/termJump (ty/ssaEdge head (list (str prefix ".zero")))) head (list (ty/ssaParam i (ty/tyI64)))))
        (g6 (close (prim g5 (str prefix ".end") (ty/tyI1) "geInt" (list i n)) (ty/termBranch (str prefix ".end") (ty/ssaEdge exit (list)) (ty/ssaEdge body (list))) body (list)))
        (g7 (prim (prim (emit g6 (str prefix ".byte") (ty/tyI64) (ty/opEntry "bytesGet" (list v i))) (str prefix ".byte32") (ty/tyI32) "rawNarrowI32" (list (str prefix ".byte")))
                  (str prefix ".stored") (ty/tyI1) "rawStoreI8" (list ptr i (str prefix ".byte32"))))
        (g8 (close (prim g7 (str prefix ".next") (ty/tyI64) "rawAddI64" (list i (str prefix ".one"))) (ty/termJump (ty/ssaEdge head (list (str prefix ".next")))) exit (list)))]
    (pair g8 (pair ptr n)))

fn copyString g: Gen prefix: String v: String -> (Pair Gen (Pair String String))
  (let [(ptr (str prefix ".ptr")) (n (str prefix ".len"))
        (g1 (call (int32 g (str prefix ".repr") 0) ptr (ty/tyPtr) "valToCStr" (list v (str prefix ".repr"))))
        (g2 (emit (holding g1 ptr) n (ty/tyI64) (ty/opEntry "stringLength" (list v))))]
    (pair g2 (pair ptr n)))

; (:m :ref FFI1 :do "rawNarrowI32 traps outside the signed range, so a checked u32 in [0, 2^32-1] is first moved to the signed value with the same low 32 bits: ((v + 2^31) & 0xFFFFFFFF) - 2^31")
fn wrapU32 g: Gen prefix: String v: String -> (Pair Gen String)
  (let [(g1 (int64 (int64 (int64 g (str prefix ".bias") 2147483648) (str prefix ".mask") 4294967295) (str prefix ".unbias") -2147483648))
        (g2 (prim (prim g1 (str prefix ".biased") (ty/tyI64) "rawAddI64" (list v (str prefix ".bias"))) (str prefix ".low") (ty/tyI64) "rawAndI64" (list (str prefix ".biased") (str prefix ".mask"))))
        (g3 (prim g2 (str prefix ".signed") (ty/tyI64) "rawAddI64" (list (str prefix ".low") (str prefix ".unbias"))))]
    (pair (prim g3 (str prefix ".c") (ty/tyI32) "rawNarrowI32" (list (str prefix ".signed"))) (str prefix ".c")))

fn narrowLength g: Gen prefix: String n: String i: Int64 kind: String -> (Pair Gen String)
  (wrapU32 (rangeCheck g (str prefix ".len32") n 0 4294967295 (argMessage g i kind)) (str prefix ".len32") n)

fn boolArg g: Gen prefix: String b: String -> (Pair Gen String)
  (let [(yes (str prefix ".true")) (no (str prefix ".false")) (join (str prefix ".joined")) (out (str prefix ".c"))
        (g1 (close g (ty/termBranch b (ty/ssaEdge yes (list)) (ty/ssaEdge no (list))) yes (list)))
        (g2 (close (int32 g1 (str prefix ".one") 1) (ty/termJump (ty/ssaEdge join (list (str prefix ".one")))) no (list)))
        (g3 (close (int32 g2 (str prefix ".zero") 0) (ty/termJump (ty/ssaEdge join (list (str prefix ".zero")))) join (list (ty/ssaParam out (ty/tyI32)))))]
    (pair g3 out))

fn marshal g: Gen i: Int64 p: ty/SsaParam kind: String -> (Pair Gen (List String))
  (let [(prefix (str "ffi.a" (stringFromInt64 i)))]
    (cond
      ((or (= kind "i64") (or (= kind "u64") (or (= kind "i32") (= kind "u32"))))
        (let [(raw (rawOf g p (ty/tyI64) (str prefix ".n")))
              (g1 (pairFirst raw)) (v (pairSecond raw))]
          (cond
            ((= kind "i64") (pair g1 (list v)))
            ((= kind "u64") (pair (rangeCheck g1 prefix v 0 9223372036854775807 (argMessage g i kind)) (list v)))
            ((= kind "i32") (pair (prim (rangeCheck g1 prefix v -2147483648 2147483647 (argMessage g i kind)) (str prefix ".c") (ty/tyI32) "rawNarrowI32" (list v)) (list (str prefix ".c"))))
            (else (let [(w (wrapU32 (rangeCheck g1 prefix v 0 4294967295 (argMessage g i kind)) prefix v))]
                    (pair (pairFirst w) (list (pairSecond w))))))))
      ((or (= (fsig/kindBase kind) "handle") (= (fsig/kindBase kind) "close")) (handleArg g i p.name kind))
      ((= kind "f64") (let [(raw (rawOf g p (ty/tyF64) (str prefix ".f")))] (pair (pairFirst raw) (list (pairSecond raw)))))
      ((= kind "bool") (let [(raw (rawOf g p (ty/tyI1) (str prefix ".b")))
                             (r (boolArg (pairFirst raw) prefix (pairSecond raw)))]
                         (pair (pairFirst r) (list (pairSecond r)))))
      ((= kind "cstr")
        (let [(c (copyString g prefix p.name))
              (g1 (pairFirst c)) (ptr (pairFirst (pairSecond c))) (n (pairSecond (pairSecond c)))
              (g2 (prim (call g1 (str prefix ".strlen") (ty/tyI64) "strlen" (list ptr)) (str prefix ".nul") (ty/tyI1) "neInt" (list (str prefix ".strlen") n)))]
          (pair (guard g2 (str prefix ".nul") "ERR_FOREIGN_NUL" (str g.who " argument " (stringFromInt64 (+ i 1)) " holds a NUL byte, which a C string cannot carry")) (list ptr))))
      ((or (= kind "str") (= kind "str32"))
        (let [(c (copyString g prefix p.name)) (g1 (pairFirst c)) (ptr (pairFirst (pairSecond c))) (n (pairSecond (pairSecond c)))]
          (if (= kind "str") (pair g1 (list ptr n))
            (let [(nl (narrowLength g1 prefix n i kind))] (pair (pairFirst nl) (list ptr (pairSecond nl)))))))
      (else
        (let [(c (copyBytes g prefix p.name)) (g1 (pairFirst c)) (ptr (pairFirst (pairSecond c))) (n (pairSecond (pairSecond c)))]
          (if (= kind "bytes") (pair g1 (list ptr n))
            (let [(nl (narrowLength g1 prefix n i kind))] (pair (pairFirst nl) (list ptr (pairSecond nl)))))))))

; (:m :ref FFI2 :do "a Handle argument crosses as its C pointer: a closed one is ERR_FOREIGN_CLOSED, and under handle:F or close:F one made with another finaliser is ERR_FOREIGN_HANDLE, so a pointer never reaches a C function of another library")
fn finAddress g: Gen dest: String fin: String -> Gen
  (if (stringEmpty? fin)
    (prim (int64 g (str dest ".zero") 0) dest (ty/tyPtr) "rawIntToPtr" (list (str dest ".zero")))
    (emit g dest (ty/tyPtr) (ty/opLoadGlobal (str "&" fin))))

fn handleArg g: Gen i: Int64 v: String kind: String -> (Pair Gen (List String))
  (let [(prefix (str "ffi.a" (stringFromInt64 i)))
        (ptr (str prefix ".p"))
        (fin (fsig/kindFinaliser kind))
        (g1 (call g ptr (ty/tyPtr) "ffiHandlePtr" (list v)))
        (g2 (guard (prim g1 (str prefix ".closed") (ty/tyI1) "rawPtrIsNull" (list ptr)) (str prefix ".closed") "ERR_FOREIGN_CLOSED" (str g.who " argument " (stringFromInt64 (+ i 1)) " is a closed Handle")))
        (g3 (if (stringEmpty? fin)
              g2
              (let [(h1 (finAddress (call g2 (str prefix ".fin") (ty/tyPtr) "ffiHandleFin" (list v)) (str prefix ".want") fin))
                    (h2 (prim (prim h1 (str prefix ".finw") (ty/tyI64) "rawPtrToInt" (list (str prefix ".fin"))) (str prefix ".wantw") (ty/tyI64) "rawPtrToInt" (list (str prefix ".want"))))
                    (h3 (prim h2 (str prefix ".other") (ty/tyI1) "neInt" (list (str prefix ".finw") (str prefix ".wantw"))))]
                (guard h3 (str prefix ".other") "ERR_FOREIGN_HANDLE" (str g.who " argument " (stringFromInt64 (+ i 1)) " is not a Handle made with " fin)))))]
    (pair (if (= (fsig/kindBase kind) "close") (with g3 :closes (listAppend g3.closes (list v))) g3) (list ptr)))

fn clearClosed g: Gen -> Gen
  (fold (fn [(acc Gen) (v String)] -> Gen (call acc (str "ffi.cleared." v) (ty/tyPtr) "ffiHandleClear" (list v))) g g.closes)

; (:m :ref FFI2 :do "!neg and !null read errno first, before the argument buffers are freed, and build ERR_FOREIGN_ERRNO: who failed: strerror(errno) at run time")
fn errnoFail g: Gen name: String -> Gen
  (let [(frees (map (fn [(p String)] -> ty/SsaInstr (ty/ssaInstr (str name "." p ".free") (ty/tyI64) (ty/opCall "free" (list p)))) g.frees))
        (lead (pooled g (if g.result (str "ERR_FOREIGN_ERRNO: " g.who " failed: ") (str g.who " failed: "))))
        (codeText (pooled (pairFirst lead) "ERR_FOREIGN_ERRNO"))
        (g1 (pairFirst codeText))
        (reason (list (ty/ssaInstr (str name ".loc") (ty/tyPtr) (ty/opCall g.errno (list)))
                      (ty/ssaInstr (str name ".zero") (ty/tyI64) (ty/opConst (ty/constInt 0)))
                      (ty/ssaInstr (str name ".errno") (ty/tyI32) (ty/opPrim "rawLoadI32" (list (str name ".loc") (str name ".zero"))))
                      (ty/ssaInstr (str name ".reason") (ty/tyPtr) (ty/opCall "strerror" (list (str name ".errno"))))
                      (ty/ssaInstr (str name ".reasonLen") (ty/tyI64) (ty/opCall "strlen" (list (str name ".reason"))))
                      (ty/ssaInstr (str name ".reasonText") (ty/tyVal) (ty/opCall "mkStr" (list (str name ".reason") (str name ".reasonLen"))))
                      (ty/ssaInstr (str name ".lead") (ty/tyVal) (ty/opConst (ty/constStr (pairSecond lead))))
                      (ty/ssaInstr (str name ".text") (ty/tyVal) (ty/opEntry "stringConcat" (list (str name ".lead") (str name ".reasonText"))))))
        (tail (if g.result
                (pair (list (ty/ssaInstr (str name ".v") (ty/tyVal) (ty/opConstruct "Result" "err" (list (str name ".text"))))) (ty/termReturn (str name ".v")))
                (pair (list (ty/ssaInstr (str name ".code") (ty/tyVal) (ty/opConst (ty/constStr (pairSecond codeText))))
                            (ty/ssaInstr (str name ".trap") (ty/tyVal) (ty/opBuiltin "trap" (list (str name ".code") (str name ".text")))))
                      (ty/termUnreachable))))]
    (addBlock g1 (ty/ssaBlock name (list) (listAppend reason (listAppend frees (pairFirst tail))) (pairSecond tail))))

fn errnoGuard g: Gen bad: String -> Gen
  (let [(g1 (tick g))
        (failName (label g1 "errno"))
        (next (label g1 "ok"))
        (g2 (errnoFail g1 failName))]
    (close g2 (ty/termBranch bad (ty/ssaEdge failName (list)) (ty/ssaEdge next (list))) next (list)))

fn checkConvention g: Gen sig: fsig/ForeignSig r: String -> Gen
  (cond
    ((= sig.check "neg")
      (let [(wide (if (= sig.ret "i32") "ffi.r.signed" r))
            (g1 (if (= sig.ret "i32") (prim g wide (ty/tyI64) "rawWidenI32" (list r)) g))
            (g2 (prim (int64 g1 "ffi.r.zero0" 0) "ffi.r.failed" (ty/tyI1) "ltInt" (list wide "ffi.r.zero0")))]
        (errnoGuard g2 "ffi.r.failed")))
    ((= sig.check "null") (errnoGuard (prim g "ffi.r.failed" (ty/tyI1) "rawPtrIsNull" (list r)) "ffi.r.failed"))
    (else g))

fn marshalAll g: Gen params: (List ty/SsaParam) kinds: (List String) -> (Pair Gen (List String))
  (fold (fn [(acc (Pair Gen (List String))) (i Int64)] -> (Pair Gen (List String))
          (let [(r (marshal (pairFirst acc) i (optionOr (listGet params i) (ty/ssaParam "" (ty/tyVal))) (optionOr (listGet kinds i) "")))]
            (pair (pairFirst r) (listAppend (pairSecond acc) (pairSecond r)))))
        (pair g (list)) (range 0 (listLength kinds)))

fn freeAll g: Gen -> Gen
  (clearFrees (fold (fn [(acc Gen) (p String)] -> Gen (call acc (str p ".free") (ty/tyI64) "free" (list p))) g g.frees))

fn unmarshal g: Gen kind: String r: String -> (Pair Gen (Pair String ty/SsaTy))
  (cond
    ((= kind "i32") (pair (prim g "ffi.r.n" (ty/tyI64) "rawWidenI32" (list r)) (pair "ffi.r.n" (ty/tyI64))))
    ((= kind "u32") (let [(g1 (int64 (prim g "ffi.r.wide" (ty/tyI64) "rawWidenI32" (list r)) "ffi.r.mask" 4294967295))]
                      (pair (prim g1 "ffi.r.n" (ty/tyI64) "rawAndI64" (list "ffi.r.wide" "ffi.r.mask")) (pair "ffi.r.n" (ty/tyI64)))))
    ((= kind "i64") (pair g (pair r (ty/tyI64))))
    ((= kind "u64") (let [(g1 (prim (int64 g "ffi.r.zero" 0) "ffi.r.big" (ty/tyI1) "ltInt" (list r "ffi.r.zero")))]
                      (pair (guard g1 "ffi.r.big" "ERR_RANGE" (str g.who " result is above the Int64 maximum")) (pair r (ty/tyI64)))))
    ((= kind "f64") (pair g (pair r (ty/tyF64))))
    ((= kind "bool") (pair (prim (int32 g "ffi.r.zero" 0) "ffi.r.b" (ty/tyI1) "rawNeI32" (list r "ffi.r.zero")) (pair "ffi.r.b" (ty/tyI1))))
    ((= kind "cstr") (let [(g1 (guard (prim g "ffi.r.null" (ty/tyI1) "rawPtrIsNull" (list r)) "ffi.r.null" "ERR_FOREIGN_NULL" (str g.who " returned a NULL C string")))
                           (g2 (call (call g1 "ffi.r.len" (ty/tyI64) "strlen" (list r)) "ffi.r.s" (ty/tyVal) "mkStr" (list r "ffi.r.len")))]
                       (pair g2 (pair "ffi.r.s" (ty/tyVal)))))
    ((= (fsig/kindBase kind) "handle")
      (let [(g1 (guard (prim g "ffi.r.null" (ty/tyI1) "rawPtrIsNull" (list r)) "ffi.r.null" "ERR_FOREIGN_NULL" (str g.who " returned a NULL handle")))
            (g2 (call (finAddress g1 "ffi.r.fin" (fsig/kindFinaliser kind)) "ffi.r.h" (ty/tyVal) "ffiMkHandle" (list r "ffi.r.fin")))]
        (pair g2 (pair "ffi.r.h" (ty/tyVal)))))
    (else (pair (emit g "ffi.r.unit" (ty/tyVal) (ty/opConst (ty/constUnit))) (pair "ffi.r.unit" (ty/tyVal)))))

fn raw? t: ty/SsaTy -> Bool
  (let [(n (ty/ssaTyName t))] (or (= n "i64") (or (= n "f64") (= n "i1"))))

fn finish g: Gen v: String vt: ty/SsaTy retTy: ty/SsaTy -> Gen
  (cond
    (g.result (let [(g1 (if (raw? vt) (emit g "ffi.r.box" (ty/tyVal) (ty/opBox v)) g))
                    (boxed (if (raw? vt) "ffi.r.box" v))]
                (close (emit g1 "ffi.r.ok" (ty/tyVal) (ty/opConstruct "Result" "ok" (list boxed))) (ty/termReturn "ffi.r.ok") "" (list))))
    ((and (raw? vt) (not (raw? retTy))) (close (emit g "ffi.r.box" (ty/tyVal) (ty/opBox v)) (ty/termReturn "ffi.r.box") "" (list)))
    (else (close g (ty/termReturn v) "" (list))))

fn stringAt m: ty/SsaModule consts: (Map String Int64) name: String -> (Option String)
  (match (mapGet consts name)
    ((some i) (listGet m.strings i))
    ((none) (none)))

fn constStrings f: ty/SsaFunction -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (i ty/SsaInstr)] -> (Map String Int64)
          (match i.op ((ty/opConst c) (match c ((ty/constStr idx) (mapSet acc i.dest idx)) (_ acc))) (_ acc)))
        (mapEmpty) (instrsOf f))

fn stubArgs f: ty/SsaFunction -> (List String)
  (fold (fn [(acc (List String)) (i ty/SsaInstr)] -> (List String) (match i.op ((ty/opBuiltin name args) (if (= name "foreign") args acc)) (_ acc))) (list) (instrsOf f))

fn stubSpec m: ty/SsaModule f: ty/SsaFunction -> (Result (Pair fsig/ForeignSpec Bool) String)
  (let [(consts (constStrings f))
        (texts (map (fn [(a String)] -> (Option String) (stringAt m consts a)) (stubArgs f)))
        (count (listLength texts))]
    (if (or (< count 3) (or (> count 4) (listAny? (fn [(t (Option String))] -> Bool (none? t)) texts)))
      (err (str f.name ": foreign takes three string literals: library, C symbol, signature"))
      (let [(at (fn [(i Int64)] -> String (optionOr (optionOr (listGet texts i) (none)) "")))]
        (match (fsig/specOfTexts (at 0) (at 1) (at 2))
          ((err e) (err (str f.name ": " e)))
          ((ok spec) (ok (pair spec (= (at 3) "result"))))))))

fn entryFirst blocks: (List ty/SsaBlock) -> (List ty/SsaBlock)
  (listAppend (filter (fn [(b ty/SsaBlock)] -> Bool (= b.label "entry")) blocks) (filter (fn [(b ty/SsaBlock)] -> Bool (!= b.label "entry")) blocks))

fn sole? f: ty/SsaFunction -> Bool
  (= (listLength (filter foreignInstr? (instrsOf f))) 1)

fn buildWrapper errno: String m: ty/SsaModule f: ty/SsaFunction strings: (List String) -> (Result Built String)
  (match (stubSpec m f)
    ((err e) (err e))
    ((ok parsed)
      (let [(spec (pairFirst parsed)) (sig spec.sig)
            (expected (fold (fn [(n Int64) (k String)] -> Int64 (+ n 1)) 0 sig.args))]
        (cond
          ((not (sole? f)) (err (str f.name ": foreign must be the whole body of a top-level fn")))
          ((!= (listLength f.params) expected) (err (str f.name " has " (stringFromInt64 (listLength f.params)) " parameter(s) but its C signature has " (stringFromInt64 expected))))
          ((not (listEmpty? f.captures)) (err (str f.name ": a foreign fn captures nothing")))
          ((and (not (stringEmpty? sig.check)) (stringEmpty? errno)) (err (str f.name ": !" sig.check " reads errno, and this target names no errno accessor")))
          (else
            (let [(g0 (Gen :label "entry" :params (list) :instrs (list) :done (list) :frees (list) :strings strings :n 0 :result (pairSecond parsed) :who (str f.name " (C " spec.symbol ")")
                           :errno errno :closes (list)))
                  (marshalled (marshalAll g0 f.params sig.args))
                  (g1 (checkConvention (clearClosed (call (pairFirst marshalled) "ffi.r" (cReturnType sig.ret) spec.symbol (pairSecond marshalled))) sig "ffi.r"))
                  (out (unmarshal (freeAll g1) sig.ret "ffi.r"))
                  (g2 (finish (pairFirst out) (pairFirst (pairSecond out)) (pairSecond (pairSecond out)) f.retTy))
                  (cTypes (fold (fn [(acc (List ty/SsaTy)) (k String)] -> (List ty/SsaTy) (listAppend acc (cParamTypes k))) (list) sig.args))]
              (ok (Built :function (ty/ssaFunction f.name f.captures f.params f.retTy (entryFirst (listReverse g2.done)))
                         :externs (cons (ty/ssaExternTyped spec.symbol cTypes (cReturnType sig.ret)) (listAppend (helperExterns) (if (stringEmpty? sig.check) (list) (errnoExterns errno))))
                         :strings g2.strings))))))))

fn symbolOf b: Built -> String
  (optionOr (listHead (map (fn [(x ty/SsaExtern)] -> String x.name) b.externs)) "")

fn mergeExterns own: (List ty/SsaExtern) added: (List ty/SsaExtern) -> (Result (List ty/SsaExtern) (List ty/IrDiag))
  (fold (fn [(acc (Result (List ty/SsaExtern) (List ty/IrDiag))) (e ty/SsaExtern)] -> (Result (List ty/SsaExtern) (List ty/IrDiag))
          (match acc
            ((err ds) (err ds))
            ((ok have) (match (listFind (fn [(o ty/SsaExtern)] -> Bool (= o.name e.name)) have)
                         ((none) (ok (listAppend have (list e))))
                         ((some o) (if (= o e) (ok have)
                                     (err (list (diag "ERR_FOREIGN_EXTERN" (str "C symbol " e.name " is declared with two different signatures in one program") e.name)))))))))
        (ok own) added)

fn withResultType types: (List ty/SsaTypeDecl) -> (List ty/SsaTypeDecl)
  (if (listAny? (fn [(d ty/SsaTypeDecl)] -> Bool (= d.name "Result")) types)
    types
    (listAppend types (list (ty/ssaTypeDecl "Result" (list (ty/ssaVariant "ok" 1) (ty/ssaVariant "err" 1))))))

; (:m :ref FFI2 :do "a finaliser named only by handle:F is declared as int F(void *) unless a foreign fn of the program declares F itself")
fn withFinalisers externs: (List ty/SsaExtern) fins: (List String) -> (List ty/SsaExtern)
  (listAppend externs (map (fn [(n String)] -> ty/SsaExtern (ty/ssaExternTyped n (list (ty/tyPtr)) (ty/tyI32)))
                           (filter (fn [(n String)] -> Bool (not (listAny? (fn [(e ty/SsaExtern)] -> Bool (= e.name n)) externs))) fins)))

fn finsIn m: ty/SsaModule f: ty/SsaFunction -> (List String)
  (match (stubSpec m f)
    ((err _) (list))
    ((ok parsed) (let [(spec (pairFirst parsed)) (sig spec.sig)]
                   (filter (fn [(n String)] -> Bool (not (stringEmpty? n))) (map fsig/kindFinaliser (cons sig.ret sig.args))))))

fn routeForeign errno: String m: ty/SsaModule -> (Result ty/SsaModule (List ty/IrDiag))
  (if (not (foreign? m))
    (ok m)
    (let [(names (map (fn [(f ty/SsaFunction)] -> String f.name) m.functions))
          (step (fn [(acc (Result (Pair (List String) (Pair (List ty/SsaFunction) (List ty/SsaExtern))) (List ty/IrDiag))) (f ty/SsaFunction)] -> (Result (Pair (List String) (Pair (List ty/SsaFunction) (List ty/SsaExtern))) (List ty/IrDiag))
                  (match acc
                    ((err ds) (err ds))
                    ((ok st) (let [(strings (pairFirst st)) (fns (pairFirst (pairSecond st))) (externs (pairSecond (pairSecond st)))]
                               (if (not (holdsForeign? f))
                                 (ok (pair strings (pair (cons f fns) externs)))
                                 (match (buildWrapper errno m f strings)
                                   ((err e) (err (list (diag "ERR_FOREIGN_SIG" e f.name))))
                                   ((ok b) (if (listContains? names (symbolOf b))
                                             (err (list (diag "ERR_FOREIGN_NAME" (str f.name " binds C symbol " (symbolOf b) ", which is also the name of a function in this program") f.name)))
                                             (match (mergeExterns externs b.externs)
                                               ((err ds) (err ds))
                                               ((ok merged) (ok (pair b.strings (pair (cons b.function fns) merged))))))))))))))
          (routed (fold step (ok (pair m.strings (pair (list) m.externs))) m.functions))
          (fins (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String) (listAppend acc (filter (fn [(n String)] -> Bool (not (listContains? acc n))) (finsIn m f)))) (list) (filter holdsForeign? m.functions)))]
      (match routed
        ((err ds) (err ds))
        ((ok st) (ok (ty/ssaModule m.name (pairFirst st) (withResultType m.types) m.records (withFinalisers (pairSecond (pairSecond st)) fins) m.globals (listReverse (pairFirst (pairSecond st)))))))))
