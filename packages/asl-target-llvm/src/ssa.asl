(module asl-target-llvm/ssa
  :x [emitLlvmModule emitLlvmProgram emitLlvmModuleWasm32 emitLlvmProgramWasm32 trapLowering llvmName llvmBytes llvmFloat runtimeDecls cDeclFits? overwideCDecls builtinTables builtinTableSym cRuntimeModule ModEnv FnEnv NameIndex nameIndexSet tailCall? linkInits definesInit? ensureInit]

  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/rtFormat :a fmt)
      (asl-target-llvm/rtError :a rterr)
      (asl-target-llvm/rtOps :a opsrt)
      (asl-target-llvm/rtObject :a objrt)
      (asl-target-llvm/rtValue :a valrt)
      (asl-target-llvm/target :a target)])

(schema ModEnv (:f name String) (:f functions NameIndex) (:f externs NameIndex) (:f types NameIndex) (:f strings NameIndex) (:f records NameIndex))

(schema ListCells (:f lines (List String)) (:f index Int64) (:f tail String))

(schema FnEnv (:f mod ModEnv) (:f defs NameIndex) (:f blocks NameIndex) (:f order (List ty/SsaBlock)) (:f retTy ty/SsaTy) (:f name String) (:f fused NameIndex) (:f records NameIndex) (:f wants NameIndex) (:f preds NameIndex) (:f size Int64))

(enum NameIndex
  (:c nameIndexEmpty [])
  (:c nameIndexNode [(key String) (value V) (left NameIndex) (right NameIndex) (height Int64)]))

fn nameIndexHeight tree: NameIndex -> Int64
  (mt tree
    ((nameIndexEmpty) 0)
    ((nameIndexNode _ _ _ _ height) height))

fn nameIndexNodeOf key: String value: V left: NameIndex right: NameIndex -> NameIndex
  (nameIndexNode key value left right (+ 1 (max (nameIndexHeight left) (nameIndexHeight right))))

fn nameIndexRotateRight key: String value: V left: NameIndex right: NameIndex -> NameIndex
  (mt left
    ((nameIndexEmpty) (nameIndexNodeOf key value left right))
    ((nameIndexNode lk lv ll lr _)
      (if (>= (nameIndexHeight ll) (nameIndexHeight lr))
        (nameIndexNodeOf lk lv ll (nameIndexNodeOf key value lr right))
        (mt lr
          ((nameIndexEmpty) (nameIndexNodeOf key value left right))
          ((nameIndexNode pk pv pl pr _)
            (nameIndexNodeOf pk pv (nameIndexNodeOf lk lv ll pl) (nameIndexNodeOf key value pr right)))))))

fn nameIndexRotateLeft key: String value: V left: NameIndex right: NameIndex -> NameIndex
  (mt right
    ((nameIndexEmpty) (nameIndexNodeOf key value left right))
    ((nameIndexNode rk rv rl rr _)
      (if (>= (nameIndexHeight rr) (nameIndexHeight rl))
        (nameIndexNodeOf rk rv (nameIndexNodeOf key value left rl) rr)
        (mt rl
          ((nameIndexEmpty) (nameIndexNodeOf key value left right))
          ((nameIndexNode pk pv pl pr _)
            (nameIndexNodeOf pk pv (nameIndexNodeOf key value left pl) (nameIndexNodeOf rk rv pr rr)))))))

fn nameIndexBalance key: String value: V left: NameIndex right: NameIndex -> NameIndex
  (let [(lh (nameIndexHeight left)) (rh (nameIndexHeight right))]
    (cond
      ((> lh (+ rh 1)) (nameIndexRotateRight key value left right))
      ((> rh (+ lh 1)) (nameIndexRotateLeft key value left right))
      (else (nameIndexNodeOf key value left right))))

fn nameIndexSet tree: NameIndex key: String value: V -> NameIndex
  (mt tree
    ((nameIndexEmpty) (nameIndexNodeOf key value (nameIndexEmpty) (nameIndexEmpty)))
    ((nameIndexNode k v left right _)
      (cond
        ((= key k) (nameIndexNodeOf key value left right))
        ((< key k) (nameIndexBalance k v (nameIndexSet left key value) right))
        (else (nameIndexBalance k v left (nameIndexSet right key value))))))

fn nameIndexGet tree: NameIndex key: String -> (Option V)
  (mt tree
    ((nameIndexEmpty) (none))
    ((nameIndexNode k v left right _)
      (cond
        ((= key k) (some v))
        ((< key k) (nameIndexGet left key))
        (else (nameIndexGet right key)))))

fn nameIndexHas? tree: NameIndex key: String -> Bool
  (some? (nameIndexGet tree key))

fn nameIndexEmpty? tree: NameIndex -> Bool
  (mt tree ((nameIndexEmpty) true) (_ false))

fn nameIndexAdd tree: NameIndex key: String n: Int64 -> NameIndex
  (nameIndexSet tree key (+ n (optionOr (nameIndexGet tree key) 0)))

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn byteAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn byteCode b: String -> Int64
  (optionOr (stringIndexOf (byteTable) b) 0)

fn hexByte n: Int64 -> String
  (str (byteAt "0123456789ABCDEF" (/ n 16)) (byteAt "0123456789ABCDEF" (mod n 16)))

fn nameByte? c: Int64 first: Bool -> Bool
  (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (= c 95) (and (not first) (>= c 48) (<= c 57)))

fn llvmName s: String -> String
  (if (stringEmpty? s)
    "$"
    (stringJoin (map (fn [(i Int64)] -> String
                        (let [(b (byteAt s i)) (c (byteCode b))]
                          (if (nameByte? c (= i 0)) b (str "$" (hexByte c)))))
                      (range 0 (stringLength s))) ""))

fn llvmBytes s: String -> String
  (stringJoin (map (fn [(i Int64)] -> String
                      (let [(b (byteAt s i)) (c (byteCode b))]
                        (if (and (>= c 32) (<= c 126) (!= c 34) (!= c 92)) b (str "\x5c" (hexByte c)))))
                    (range 0 (stringLength s))) "")

fn llvmFloat x: Float64 -> String
  (let [(s (stringFromFloat64 x))]
    (cond
      ((= s "inf") "0x7FF0000000000000")
      ((= s "-inf") "0xFFF0000000000000")
      ((or (= s "nan") (= s "-nan")) "0x7FF8000000000000")
      ((stringContains? s ".") s)
      ((stringContains? s "e") (stringReplace s "e" ".0e"))
      (else (str s ".0"))))

fn llTy t: ty/SsaTy -> String
  (mt t ((ty/tyVal) "%Val") ((ty/tyRec _) "%Val") ((ty/tyI64) "i64") ((ty/tyF64) "double") ((ty/tyI1) "i1") ((ty/tyPtr) "ptr") ((ty/tyI32) "i32"))

fn nativeTy? t: ty/SsaTy -> Bool
  (let [(n (ty/ssaTyName t))] (or (= n "ptr") (= n "i32")))

fn nativeExtern? e: ty/SsaExtern -> Bool
  (or e.variadic (listAny? nativeTy? (listAppend e.params (list e.ret))))

fn valTag p: String base: String -> String
  (str "  " p ".vtagw = extractvalue %Val " base ", 0\n  " p ".vtag = trunc i64 " p ".vtagw to i32\n")

fn valObj p: String base: String -> String
  (str "  " p ".objw = extractvalue %Val " base ", 1\n  " p ".obj = inttoptr i64 " p ".objw to ptr\n")

fn valAux p: String base: String -> String
  (str "  " p ".auxw = extractvalue %Val " base ", 0\n  " p ".auxhi = lshr i64 " p ".auxw, 32\n  " p ".aux = trunc i64 " p ".auxhi to i32\n")

fn boxInline lhs: String dest: String src: ty/SsaTy v: String -> String
  (let [(bits (str "%" (llvmName dest) ".bits"))]
    (mt src
      ((ty/tyI64) (str lhs "insertvalue %Val { i64 2, i64 0 }, i64 " v ", 1\n"))
      ((ty/tyF64) (str "  " bits " = bitcast double " v " to i64\n" lhs "insertvalue %Val { i64 3, i64 0 }, i64 " bits ", 1\n"))
      ((ty/tyI1) (str "  " bits " = zext i1 " v " to i64\n" lhs "insertvalue %Val { i64 1, i64 0 }, i64 " bits ", 1\n"))
      ((ty/tyVal) (str lhs "freeze %Val " v "\n"))
      ((ty/tyRec _) (str lhs "freeze %Val " v "\n"))
      ((ty/tyI32) (str "  " bits " = sext i32 " v " to i64\n" lhs "insertvalue %Val { i64 2, i64 0 }, i64 " bits ", 1\n"))
      ((ty/tyPtr) (str "  " bits " = ptrtoint ptr " v " to i64\n" lhs "insertvalue %Val { i64 2, i64 0 }, i64 " bits ", 1\n"))))

fn rawKind t: ty/SsaTy -> String
  (mt t ((ty/tyVal) "val") ((ty/tyRec _) "val") ((ty/tyI64) "int") ((ty/tyF64) "float") ((ty/tyI1) "bool") ((ty/tyI32) "int") ((ty/tyPtr) "val"))

fn val name: String -> String
  (str "%" (llvmName name))

fn label name: String -> String
  (str "bb." (llvmName name))

fn fnSym name: String -> String
  (if (= name "main")
    "@asl_main"
    (str "@" (llvmName name)))

fn nameSym name: String -> String
  (str "@name." (llvmName name))

fn variantsSym name: String -> String
  (str "@variants." (llvmName name))

fn variantIdsSym name: String -> String
  (str "@variantIds." (llvmName name))

fn variantIdsReadySym name: String -> String
  (str "@variantIdsReady." (llvmName name))

fn variantIdsInitSym name: String -> String
  (str "@variantIdsInit." (llvmName name))

fn fieldIdSym name: String -> String
  (str "@fieldId." (llvmName name))

fn fieldIdReadySym name: String -> String
  (str "@fieldIdReady." (llvmName name))

fn fieldIdInitSym name: String -> String
  (str "@fieldIdInit." (llvmName name))

fn ctorIdSym name: String -> String
  (str "@ctorId." (llvmName name))

fn ctorIdReadySym name: String -> String
  (str "@ctorIdReady." (llvmName name))

fn ctorIdInitSym name: String -> String
  (str "@ctorIdInit." (llvmName name))

fn schemaIdSym name: String -> String
  (str "@schemaId." (llvmName name))

fn schemaIdReadySym name: String -> String
  (str "@schemaIdReady." (llvmName name))

fn schemaIdInitSym name: String -> String
  (str "@schemaIdInit." (llvmName name))

fn keyIdsSym name: String -> String
  (str "@keyIds." (llvmName name))

fn nameIdCellSym name: String -> String
  (str "@nameId." (llvmName name))

fn strCellSym index: Int64 -> String
  (str "@strVal." index)

fn nameIdArgs name: String -> String
  (str "ptr " (nameIdCellSym name) ", ptr " (nameSym name) ", i64 " (stringLength name))

fn fieldMiss lhs: String base: String field: String -> String
  (str lhs "call %Val @objrt.field(%Val " base ", " (nameIdArgs field) ")\n")

fn internId reg: String name: String -> String
  (str "  " reg " = call i32 @valrt.intern(ptr " (nameSym name) ", i64 " (stringLength name) ")\n")

fn protoSym name: String -> String
  (str "@proto." (llvmName name))

fn protoName callee: String -> String
  (if (stringContains? callee "@lambda")
    "lambda"
    (let [(parts (stringSplit callee "."))]
      (optionOr (listGet parts (- (listLength parts) 1)) callee)))

fn wrappedCallee f: ty/SsaFunction -> (Option String)
  (if (or (listEmpty? f.params) (not (listAll? (fn [(p ty/SsaParam)] -> Bool (stringStartsWith? p.name "@")) f.params)))
    (none)
    (listHead (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
                      (listAppend acc (fold (fn [(found (List String)) (i ty/SsaInstr)] -> (List String)
                                              (mt i.op ((ty/opCall callee _) (listAppend found (list callee))) (_ found)))
                                            (list) b.instrs)))
                    (list) f.blocks)))

fn protoNameIn functions: NameIndex callee: String -> String
  (mt (nameIndexGet functions callee)
    ((some f) (mt (wrappedCallee f) ((some w) (protoName w)) ((none) (protoName callee))))
    ((none) (protoName callee)))

fn protoNameSym name: String -> String
  (str "@protoName." (llvmName name))

fn globalSym name: String -> String
  (str "@global." (llvmName name))

fn externGlobalSym name: String -> String
  (str "@" (llvmName name))

fn codeSym name: String -> String
  (str "@" (llvmName name) ".code")

fn initSym moduleName: String -> String
  (str "@init." (llvmName moduleName))

fn globalReadySym name: String -> String
  (str "@globalReady." (llvmName name))

fn sharedGlobal? g: ty/SsaGlobal -> Bool
  (stringStartsWith? g.name "asl-target-llvm/")

fn definesInit? text: String moduleName: String -> Bool
  (stringContains? text (str "define void " (initSym moduleName) "() {"))

fn ensureInit text: String moduleName: String -> String
  (if (definesInit? text moduleName)
    text
    (str text "\ndefine void " (initSym moduleName) "() {\nbb.entry:\n  ret void\n}\n"))

fn linkInits text: String moduleNames: (List String) -> (Result String String)
  (let [(wanted (filter (fn [(n String)] -> Bool (not (definesInit? text n))) moduleNames))
        (anchor (reportInit))
        (count (- (listLength (stringSplit text anchor)) 1))]
    (cond
      ((listEmpty? wanted) (ok text))
      ((!= count 1) (err (str "entry IR holds " count " @main report anchors, not 1")))
      (else (ok (str (stringReplace text anchor (str anchor (stringJoin (map (fn [(n String)] -> String (str "  call void " (initSym n) "()\n")) wanted) "")))
                     "\n" (stringJoin (map (fn [(n String)] -> String (str "declare void " (initSym n) "()\n")) wanted) ""))))))

fn runtimeDecls -> (List String)
  (list "declare void @asl_rt_init()"
        "declare %Val @asl_rt_builtin_sys(ptr, i64, ptr)"
        "declare %Val @asl_rt_builtin_sysNet(ptr, i64, ptr)"
        "declare %Val @asl_rt_builtin_parallel(ptr, i64, ptr)"
        "declare ptr @asl_alloc(i32, i64)"
        "declare ptr @asl_alloc_raw(i32, i64)"
        "declare ptr @asl_alloc_cons()"
        "declare void @asl_rt_global_root(ptr)")

fn nativeBuiltinEntries -> (List ty/SsaBuiltin)
  (filter (fn [(b ty/SsaBuiltin)] -> Bool (!= b.kind "wrap")) (ty/builtinEntries))

fn builtinSym b: ty/SsaBuiltin -> String
  (if (= b.kind "intrinsic") (str "llvm." b.symbol ".f64") b.symbol)

fn builtinTables -> (List (Pair String (List String)))
  (list (pair "sys" (list "fdRead" "fdWrite" "fdClose" "fdPoll" "fdNonBlocking" "fileLock" "fileLockWait" "fileAppend" "fileLockAt" "fileReadAt" "fileWriteAt"
                          "procSpawnv" "procWaitPid" "procKill" "procSelf" "procExePath" "procExecv" "envList" "procWaitAny" "procPoll" "cpuCount" "procRusage" "platformInfo" "localDate" "procAlive?"))
        (pair "sysNet" (list "tcpListen" "tcpConnect" "sockAccept" "sockLocalPort" "unixListen" "unixConnect"))
        (pair "parallel" (list "parMap" "parFold")))

fn builtinTableSym name: String -> (Option String)
  (fold (fn [(acc (Option String)) (t (Pair String (List String)))] -> (Option String)
          (if (and (none? acc) (listContains? (pairSecond t) name)) (some (str "asl_rt_builtin_" (pairFirst t))) acc))
        (none) (builtinTables))

fn tableCall lhs: String name: String n: Int64 arr: String -> String
  (mt (builtinTableSym name)
    ((some sym) (str lhs "call %Val @" sym "(ptr " (nameSym name) ", i64 " n ", " arr ")\n"))
    ((none) ""))

fn entryDecl b: ty/SsaBuiltin -> String
  (str "declare " (llTy b.result) " @" (builtinSym b) "(" (stringJoin (map llTy b.args) ", ") ")")

fn intrinsicDecls -> (List String)
  (listAppend
    (list "declare void @llvm.trap()"
        "declare i1 @llvm.expect.i1(i1, i1)"
        "declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)"
        "declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)"
        "declare {i64, i1} @llvm.smul.with.overflow.i64(i64, i64)")
    (map entryDecl (nativeBuiltinEntries)))

fn declSymbol decl: String -> String
  (let [(at (optionOr (stringIndexOf decl "@") 0))
        (open (optionOr (stringIndexOf decl "(") (stringLength decl)))]
    (optionOr (stringSlice decl at (+ open 1)) decl))

fn usedDecls text: String decls: (List String) -> (List String)
  (filter (fn [(d String)] -> Bool (stringContains? text (declSymbol d))) decls)

fn usedRuntimeDecls text: String -> (List String)
  (usedDecls text (runtimeDecls))

fn defType env: FnEnv name: String -> ty/SsaTy
  (optionOr (nameIndexGet env.defs name) (ty/tyVal))

fn constStringLength env: FnEnv index: Int64 -> Int64
  (stringLength (optionOr (nameIndexGet env.mod.strings (stringFromInt64 index)) ""))

fn variantTag env: FnEnv typeName: String variant: String -> Int64
  (let [(names (map (fn [(v ty/SsaVariant)] -> String v.name) (optionOr (nameIndexGet env.mod.types typeName) (list))))]
    (optionOr (listIndexOf names variant) 0))

fn termOperands t: ty/SsaTerm -> (List String)
  (listAppend
    (mt t
      ((ty/termReturn v) (list v))
      ((ty/termBranch c _ _) (list c))
      ((ty/termSwitch s _ _ _) (list s))
      (_ (list)))
    (fold (fn [(acc (List String)) (e ty/SsaEdge)] -> (List String) (listAppend acc e.args)) (list) (ty/termEdges t)))

fn allInstrs f: ty/SsaFunction -> (List ty/SsaInstr)
  (listReverse (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (fold (fn [(a (List ty/SsaInstr)) (ins ty/SsaInstr)] -> (List ty/SsaInstr) (cons ins a)) acc b.instrs)) (list) f.blocks))

fn addCounts m: NameIndex names: (List String) -> NameIndex
  (fold (fn [(acc NameIndex) (n String)] -> NameIndex (nameIndexSet acc n (+ 1 (optionOr (nameIndexGet acc n) 0)))) m names)

fn useCounts f: ty/SsaFunction -> NameIndex
  (fold (fn [(acc NameIndex) (b ty/SsaBlock)] -> NameIndex
          (addCounts (fold (fn [(a NameIndex) (ins ty/SsaInstr)] -> NameIndex (addCounts a (ty/opOperands ins.op))) acc b.instrs)
                     (termOperands b.term)))
        (nameIndexEmpty) f.blocks)

fn unboxedValues f: ty/SsaFunction -> NameIndex
  (fold (fn [(acc NameIndex) (ins ty/SsaInstr)] -> NameIndex (mt ins.op ((ty/opUnbox v) (nameIndexSet acc v true)) (_ acc))) (nameIndexEmpty) (allInstrs f))

fn fieldOrVariantField? op: ty/SsaOp -> Bool
  (mt op ((ty/opField _ _) true) ((ty/opVariantField _ _) true) (_ false))

fn fusedInstrs f: ty/SsaFunction -> (List ty/SsaInstr)
  (let [(uc (useCounts f)) (unboxed (unboxedValues f))]
    (filter (fn [(ins ty/SsaInstr)] -> Bool
              (and (fieldOrVariantField? ins.op)
                   (and (= (optionOr (nameIndexGet uc ins.dest) 0) 1) (nameIndexHas? unboxed ins.dest))))
            (allInstrs f)))

fn fusedMap f: ty/SsaFunction -> NameIndex
  (fold (fn [(acc NameIndex) (ins ty/SsaInstr)] -> NameIndex (nameIndexSet acc ins.dest ins.op)) (nameIndexEmpty) (fusedInstrs f))

fn fusedFieldNamesIn f: ty/SsaFunction -> (List String)
  (listReverse (fold (fn [(acc (List String)) (ins ty/SsaInstr)] -> (List String) (mt ins.op ((ty/opField _ field) (cons field acc)) (_ acc))) (list) (fusedInstrs f)))

fn fusedFieldNames m: ty/SsaModule -> (List String)
  (distinct (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String) (listAppend acc (fusedFieldNamesIn f))) (list) m.functions))

fn typedFieldNamesIn menv: ModEnv f: ty/SsaFunction -> (List String)
  (let [(recs (recordMap f)) (defs (functionDefs f)) (fused (fusedMap f))]
    (listReverse (fold (fn [(acc (List String)) (ins ty/SsaInstr)] -> (List String)
            (mt ins.op
              ((ty/opField base field) (if (and (not (some? (nameIndexGet fused ins.dest))) (some? (typedFieldIndexFor menv recs defs base field)))
                                         (cons field acc)
                                         acc))
              (_ acc)))
          (list) (allInstrs f))))

fn fieldIdNames m: ty/SsaModule -> (List String)
  (let [(menv (moduleEnv m))]
    (distinct (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String) (listAppend acc (typedFieldNamesIn menv f))) (fusedFieldNames m) m.functions)))

fn recordMap f: ty/SsaFunction -> NameIndex
  (fold (fn [(acc NameIndex) (ins ty/SsaInstr)] -> NameIndex
          (mt ins.op ((ty/opRecord _ _ _) (nameIndexSet acc ins.dest ins.op)) (_ acc)))
        (nameIndexEmpty) (allInstrs f))

fn opRecordFields op: ty/SsaOp -> (Option (List String))
  (mt op ((ty/opRecord _ fields _) (some fields)) (_ (none)))

fn recordFieldsFor recs: NameIndex base: String -> (Option (List String))
  (mt (nameIndexGet recs base)
    ((some op) (opRecordFields op))
    ((none) (none)))

fn fieldStaticIndexFor recs: NameIndex base: String field: String -> (Option Int64)
  (mt (recordFieldsFor recs base)
    ((some fields) (listIndexOf fields field))
    ((none) (none)))

fn staticFieldIndex env: FnEnv base: String field: String -> (Option Int64)
  (fieldStaticIndexFor env.records base field)

fn typedFieldIndexFor menv: ModEnv recs: NameIndex defs: NameIndex base: String field: String -> (Option Int64)
  (if (some? (nameIndexGet recs base))
    (none)
    (mt (nameIndexGet defs base)
      ((some t) (mt t
                  ((ty/tyRec schema) (mt (nameIndexGet menv.records schema)
                                       ((some fields) (listIndexOf fields field))
                                       ((none) (none))))
                  (_ (none))))
      ((none) (none))))

fn typedFieldIndex env: FnEnv base: String field: String -> (Option Int64)
  (typedFieldIndexFor env.mod env.records env.defs base field)

fn fusedTagNum kind: String -> Int64
  (cond ((= kind "bool") 1) ((= kind "int") 2) ((= kind "float") 3) (else 0))

fn fusedFastLoad p: String kind: String lty: String -> String
  (if (= kind "bool")
    (str "  " p ".rawi64 = load i64, ptr " p ".valp\n  " p ".fastval = trunc i64 " p ".rawi64 to i1\n")
    (str "  " p ".fastval = load " lty ", ptr " p ".valp\n"))

fn unboxPayload lhs: String prefix: String kind: String base: String -> String
  (cond
    ((= kind "bool") (str "  " prefix ".w = extractvalue %Val " base ", 1\n" lhs "trunc i64 " prefix ".w to i1\n"))
    ((= kind "float") (str "  " prefix ".w = extractvalue %Val " base ", 1\n" lhs "bitcast i64 " prefix ".w to double\n"))
    (else (str lhs "extractvalue %Val " base ", 1\n")))



fn typeTrap p: String lbl: String expect: Int64 -> String
  (str lbl ".trap:\n  call void @rterr.type(i32 " p ".vtag, i32 " expect ")\n  unreachable\n")

fn emitUnboxInline lhs: String dest: String t: ty/SsaTy v: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (kind (rawKind t)) (expect (fusedTagNum kind)) (vv (val v))]
    (str (valTag p vv)
         "  " p ".tagok = icmp eq i32 " p ".vtag, " expect "\n"
         "  br i1 " p ".tagok, label %" lbl ".ok, label %" lbl ".trap\n"
         (typeTrap p lbl expect)
         lbl ".ok:\n"
         (unboxPayload lhs p kind vv)))

fn entryUnboxWho name: String -> String
  (if (= name "stringSlice") "@.strrt.who.stringSlice" "@.strrt.who.stringFromInt64")

fn entryUnboxes f: ty/SsaFunction -> NameIndex
  (let [(uc (useCounts f))]
    (fold (fn [(acc NameIndex) (b ty/SsaBlock)] -> NameIndex
            (let [(positions (pairSecond (fold (fn [(walk (Pair Int64 NameIndex)) (ins ty/SsaInstr)] -> (Pair Int64 NameIndex)
                                                (pair (+ (pairFirst walk) 1) (if (nameIndexHas? (pairSecond walk) ins.dest) (pairSecond walk) (nameIndexSet (pairSecond walk) ins.dest (pairFirst walk)))))
                                              (pair 0 (nameIndexEmpty)) b.instrs)))
                  (unboxed (fold (fn [(u NameIndex) (ins ty/SsaInstr)] -> NameIndex (if (plainUnbox? ins.op) (nameIndexSet u ins.dest true) u)) (nameIndexEmpty) b.instrs))]
              (fold (fn [(m NameIndex) (ins ty/SsaInstr)] -> NameIndex
                      (mt ins.op
                        ((ty/opEntry name args)
                         (if (or (and (= name "stringFromInt64") (= (listLength args) 1)) (and (= name "stringSlice") (= (listLength args) 3)))
                           (let [(text (if (= name "stringSlice") (optionOr (listHead args) "") ""))
                                 (ints (if (= name "stringSlice") (optionOr (listTail args) (list)) args))]
                             (fold (fn [(mm NameIndex) (a String)] -> NameIndex
                                     (if (and (nameIndexHas? unboxed a) (= (optionOr (nameIndexGet uc a) 0) (listLength (filter (fn [(x String)] -> Bool (= x a)) args))))
                                       (let [(before (or (not (nameIndexHas? positions text))
                                                         (< (optionOr (nameIndexGet positions text) 0) (optionOr (nameIndexGet positions a) 0))))]
                                         (nameIndexSet mm a (pair (entryUnboxWho name) (if before text ""))))
                                       mm))
                                   m ints))
                           m))
                        (_ m)))
                    acc b.instrs)))
          (nameIndexEmpty) f.blocks))

fn emitEntryUnbox lhs: String dest: String t: ty/SsaTy v: String w: (Pair String String) -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (kind (rawKind t)) (expect (fusedTagNum kind)) (vv (val v))
        (who (pairFirst w)) (text (pairSecond w))]
    (str (valTag p vv)
         "  " p ".tagok = icmp eq i32 " p ".vtag, " expect "\n"
         "  br i1 " p ".tagok, label %" lbl ".ok, label %" lbl (if (stringEmpty? text) ".want" ".text") "\n"
         (if (stringEmpty? text)
           ""
           (str lbl ".text:\n"
                (valTag (str p ".s") (val text))
                "  " p ".s.isStr = icmp eq i32 " p ".s.vtag, 5\n"
                "  br i1 " p ".s.isStr, label %" lbl ".want, label %" lbl ".notStr\n"
                (wantTrap (str lbl ".notStr") who 5 (str p ".s.vtag"))))
         (wantTrap (str lbl ".want") who expect (str p ".vtag"))
         lbl ".ok:\n"
         (unboxPayload lhs p kind vv)))

fn emitFusedVariantUnbox lhs: String dest: String t: ty/SsaTy base: String index: Int64 -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (kind (rawKind t)) (lty (llTy t))
        (tagOff (+ 16 (* index 16))) (valOff (+ tagOff 8)) (expect (fusedTagNum kind))]
    (str (valTag p base)
         "  " p ".isCtor = icmp eq i32 " p ".vtag, 8\n"
         "  br i1 " p ".isCtor, label %" lbl ".ctor, label %" lbl ".slow\n"
         lbl ".ctor:\n"
         (valObj p base)
         "  " p ".np = getelementptr inbounds i8, ptr " p ".obj, i64 12\n"
         "  " p ".n = load i32, ptr " p ".np\n"
         "  " p ".n64 = sext i32 " p ".n to i64\n"
         "  " p ".inRange = icmp slt i64 " index ", " p ".n64\n"
         "  br i1 " p ".inRange, label %" lbl ".chk, label %" lbl ".slow\n"
         lbl ".chk:\n"
         "  " p ".ftagp = getelementptr inbounds i8, ptr " p ".obj, i64 " tagOff "\n"
         "  " p ".ftag = load i32, ptr " p ".ftagp\n"
         "  " p ".rightTag = icmp eq i32 " p ".ftag, " expect "\n"
         "  br i1 " p ".rightTag, label %" lbl ".fast, label %" lbl ".slow\n"
         lbl ".fast:\n"
         "  " p ".valp = getelementptr inbounds i8, ptr " p ".obj, i64 " valOff "\n"
         (fusedFastLoad p kind lty)
         "  br label %" lbl ".join\n"
         lbl ".slow:\n"
         "  " p ".slowfield = call %Val @objrt.variantField(%Val " base ", i64 " index ")\n"
         (valTag (str p ".sf") (str p ".slowfield"))
         "  " p ".sf.ok = icmp eq i32 " p ".sf.vtag, " expect "\n"
         "  br i1 " p ".sf.ok, label %" lbl ".slowok, label %" lbl ".trap\n"
         (typeTrap (str p ".sf") lbl expect)
         lbl ".slowok:\n"
         (unboxPayload (str "  " p ".slowval = ") (str p ".slowval") kind (str p ".slowfield"))
         "  br label %" lbl ".join\n"
         lbl ".join:\n"
         lhs "phi " lty " [ " p ".fastval, %" lbl ".fast ], [ " p ".slowval, %" lbl ".slowok ]\n"))

fn emitVariantFieldVal lhs: String dest: String base: String index: Int64 -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (fieldOff (+ 16 (* index 16)))]
    (str (valTag p base)
         "  " p ".isCtor = icmp eq i32 " p ".vtag, 8\n"
         "  br i1 " p ".isCtor, label %" lbl ".ctor, label %" lbl ".slow\n"
         lbl ".ctor:\n"
         (valObj p base)
         "  " p ".np = getelementptr inbounds i8, ptr " p ".obj, i64 12\n"
         "  " p ".n = load i32, ptr " p ".np\n"
         "  " p ".n64 = sext i32 " p ".n to i64\n"
         "  " p ".inRange = icmp slt i64 " index ", " p ".n64\n"
         "  br i1 " p ".inRange, label %" lbl ".fast, label %" lbl ".slow\n"
         lbl ".fast:\n"
         "  " p ".fp = getelementptr inbounds i8, ptr " p ".obj, i64 " fieldOff "\n"
         "  " p ".fastval = load %Val, ptr " p ".fp\n"
         "  br label %" lbl ".join\n"
         lbl ".slow:\n"
         "  " p ".slowval = call %Val @objrt.variantField(%Val " base ", i64 " index ")\n"
         "  br label %" lbl ".join\n"
         lbl ".join:\n"
         lhs "phi %Val [ " p ".fastval, %" lbl ".fast ], [ " p ".slowval, %" lbl ".slow ]\n"))

fn recordKeysPrelude p: String lbl: String base: String field: String -> String
  (str lbl ".rec:\n"
       (valObj p base)
       "  " p ".np = getelementptr inbounds i8, ptr " p ".obj, i64 12\n"
       "  " p ".n = load i32, ptr " p ".np\n"
       "  " p ".keysp = getelementptr inbounds i8, ptr " p ".obj, i64 16\n"
       "  " p ".keys = load ptr, ptr " p ".keysp\n"
       "  " p ".ready = load i1, ptr " (fieldIdReadySym field) "\n"
       "  br i1 " p ".ready, label %" lbl ".scan, label %" lbl ".resolve\n"
       lbl ".resolve:\n"
       "  call void " (fieldIdInitSym field) "()\n"
       "  br label %" lbl ".scan\n"
       lbl ".scan:\n"
       "  " p ".fid = load i32, ptr " (fieldIdSym field) "\n")

fn staticKeyProbe p: String lbl: String index: Int64 hit: String miss: String -> String
  (str "  " p ".sIn = icmp slt i32 " index ", " p ".n\n"
       "  br i1 " p ".sIn, label %" lbl ".sprobe, label %" miss "\n"
       lbl ".sprobe:\n"
       "  " p ".skeyp = getelementptr inbounds i32, ptr " p ".keys, i64 " index "\n"
       "  " p ".skey = load i32, ptr " p ".skeyp\n"
       "  " p ".skeyOk = icmp eq i32 " p ".skey, " p ".fid\n"
       "  br i1 " p ".skeyOk, label %" hit ", label %" miss "\n")

fn emitTypedFieldRead lhs: String dest: String base: String field: String index: Int64 -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (slotOff (+ 24 (* index 16)))]
    (str (valTag p base)
         "  " p ".isRec = icmp eq i32 " p ".vtag, 7\n"
         "  br i1 " p ".isRec, label %" lbl ".rec, label %" lbl ".slow\n"
         (recordKeysPrelude p lbl base field)
         (staticKeyProbe p lbl index (str lbl ".fast") (str lbl ".slow"))
         lbl ".fast:\n"
         "  " p ".slotp = getelementptr inbounds i8, ptr " p ".obj, i64 " slotOff "\n"
         "  " p ".fastval = load %Val, ptr " p ".slotp\n"
         "  br label %" lbl ".join\n"
         lbl ".slow:\n"
         (fieldMiss (str "  " p ".slowval = ") base field)
         "  br label %" lbl ".join\n"
         lbl ".join:\n"
         lhs "phi %Val [ " p ".fastval, %" lbl ".fast ], [ " p ".slowval, %" lbl ".slow ]\n"))

fn emitFusedFieldUnbox lhs: String dest: String t: ty/SsaTy base: String field: String static: (Option Int64) -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (kind (rawKind t)) (lty (llTy t)) (expect (fusedTagNum kind))]
    (str (valTag p base)
         "  " p ".isRec = icmp eq i32 " p ".vtag, 7\n"
         "  br i1 " p ".isRec, label %" lbl ".rec, label %" lbl ".slow\n"
         (recordKeysPrelude p lbl base field)
         (mt static
           ((none) (str "  br label %" lbl ".loop\n"
                        lbl ".loop:\n"
                        "  " p ".i = phi i32 [ 0, %" lbl ".scan ], [ " p ".inext, %" lbl ".body ]\n"))
           ((some idx) (str (staticKeyProbe p lbl idx (str lbl ".found") (str lbl ".loop"))
                            lbl ".loop:\n"
                            "  " p ".i = phi i32 [ 0, %" lbl ".scan ], [ 0, %" lbl ".sprobe ], [ " p ".inext, %" lbl ".body ]\n")))
         "  " p ".inRange = icmp slt i32 " p ".i, " p ".n\n"
         "  br i1 " p ".inRange, label %" lbl ".body, label %" lbl ".slow\n"
         lbl ".body:\n"
         "  " p ".keyp = getelementptr inbounds i32, ptr " p ".keys, i32 " p ".i\n"
         "  " p ".key = load i32, ptr " p ".keyp\n"
         "  " p ".inext = add i32 " p ".i, 1\n"
         "  " p ".match = icmp eq i32 " p ".key, " p ".fid\n"
         "  br i1 " p ".match, label %" lbl ".found, label %" lbl ".loop\n"
         lbl ".found:\n"
         (mt static
           ((none) (str "  " p ".idx64 = sext i32 " p ".i to i64\n"))
           ((some idx) (str "  " p ".fi = phi i32 [ " p ".i, %" lbl ".body ], [ " idx ", %" lbl ".sprobe ]\n"
                            "  " p ".idx64 = sext i32 " p ".fi to i64\n")))
         "  " p ".off = mul i64 " p ".idx64, 16\n"
         "  " p ".tagoff = add i64 24, " p ".off\n"
         "  " p ".valoff = add i64 32, " p ".off\n"
         "  " p ".ftagp = getelementptr inbounds i8, ptr " p ".obj, i64 " p ".tagoff\n"
         "  " p ".ftag = load i32, ptr " p ".ftagp\n"
         "  " p ".rightTag = icmp eq i32 " p ".ftag, " expect "\n"
         "  br i1 " p ".rightTag, label %" lbl ".fast, label %" lbl ".slow\n"
         lbl ".fast:\n"
         "  " p ".valp = getelementptr inbounds i8, ptr " p ".obj, i64 " p ".valoff\n"
         (fusedFastLoad p kind lty)
         "  br label %" lbl ".join\n"
         lbl ".slow:\n"
         (fieldMiss (str "  " p ".slowfield = ") base field)
         (valTag (str p ".sf") (str p ".slowfield"))
         "  " p ".sf.ok = icmp eq i32 " p ".sf.vtag, " expect "\n"
         "  br i1 " p ".sf.ok, label %" lbl ".slowok, label %" lbl ".trap\n"
         (typeTrap (str p ".sf") lbl expect)
         lbl ".slowok:\n"
         (unboxPayload (str "  " p ".slowval = ") (str p ".slowval") kind (str p ".slowfield"))
         "  br label %" lbl ".join\n"
         lbl ".join:\n"
         lhs "phi " lty " [ " p ".fastval, %" lbl ".fast ], [ " p ".slowval, %" lbl ".slowok ]\n"))

fn emitFieldIdInit field: String -> String
  (str "define internal void " (fieldIdInitSym field) "() {\nbb.entry:\n"
       (internId "%kw.aux" field)
       "  store i32 %kw.aux, ptr " (fieldIdSym field) "\n"
       "  store i1 true, ptr " (fieldIdReadySym field) "\n  ret void\n}\n")

fn emitCtorIdInit variant: String -> String
  (str "define internal void " (ctorIdInitSym variant) "() {\nbb.entry:\n"
       (internId "%kw.aux" variant)
       "  store i32 %kw.aux, ptr " (ctorIdSym variant) "\n"
       "  store i1 true, ptr " (ctorIdReadySym variant) "\n  ret void\n}\n")

fn emitSchemaIdInit schema: String fields: (List String) -> String
  (let [(n (listLength fields))]
    (str "define internal void " (schemaIdInitSym schema) "() {\nbb.entry:\n"
         (internId "%kw.aux" schema)
         "  store i32 %kw.aux, ptr " (schemaIdSym schema) "\n"
         (stringJoin (map (fn [(k Int64)] -> String
                            (str (internId (str "%fkw." k ".aux") (optionOr (listGet fields k) ""))
                                 "  %fslot." k " = getelementptr inbounds [" n " x i32], ptr " (keyIdsSym schema) ", i64 0, i64 " k "\n"
                                 "  store i32 %fkw." k ".aux, ptr %fslot." k "\n"))
                          (range 0 n)) "")
         "  store i1 true, ptr " (schemaIdReadySym schema) "\n  ret void\n}\n"))

fn emitCtorAlloc labelPrefix: String variant: String fieldVals: (List String) -> String
  (let [(p (str "%" labelPrefix)) (lbl labelPrefix) (n (listLength fieldVals)) (bytes (+ 16 (* n 16)))
        (stores (stringJoin (map (fn [(i Int64)] -> String
                                    (str "  " p ".f" i "p = getelementptr inbounds i8, ptr " p ".objp, i64 " (+ 16 (* i 16)) "\n"
                                         "  store %Val " (optionOr (listGet fieldVals i) "") ", ptr " p ".f" i "p\n"))
                                  (range 0 n)) ""))]
    (str "  " p ".ready = load i1, ptr " (ctorIdReadySym variant) "\n"
         "  br i1 " p ".ready, label %" lbl ".alloc, label %" lbl ".resolve\n"
         lbl ".resolve:\n"
         "  call void " (ctorIdInitSym variant) "()\n"
         "  br label %" lbl ".alloc\n"
         lbl ".alloc:\n"
         "  " p ".ctor = load i32, ptr " (ctorIdSym variant) "\n"
         "  " p ".objp = call ptr @asl_alloc_raw(i32 3, i64 " bytes ")\n"
         "  " p ".ctorp = getelementptr inbounds i8, ptr " p ".objp, i64 8\n"
         "  store i32 " p ".ctor, ptr " p ".ctorp\n"
         "  " p ".np = getelementptr inbounds i8, ptr " p ".objp, i64 12\n"
         "  store i32 " n ", ptr " p ".np\n"
         stores
         "  " p ".objw = ptrtoint ptr " p ".objp to i64\n"))

fn emitConstruct lhs: String dest: String variant: String fields: (List String) -> String
  (let [(lbl (llvmName dest))]
    (str (emitCtorAlloc lbl variant (map val fields))
         lhs "insertvalue %Val { i64 8, i64 0 }, i64 %" lbl ".objw, 1\n"))

fn emitRecord lhs: String dest: String schemaName: String fields: (List String) values: (List String) declared: (List String) -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (n (listLength values))
        (full (= fields declared)) (bytes (+ 24 (* n (if full 16 20))))
        (stores (stringJoin (map (fn [(i Int64)] -> String
                                    (str "  " p ".f" i "p = getelementptr inbounds i8, ptr " p ".objp, i64 " (+ 24 (* i 16)) "\n"
                                         "  store %Val " (val (optionOr (listGet values i) "")) ", ptr " p ".f" i "p\n"))
                                  (range 0 n)) ""))
        (keyStores (if full "" (stringJoin (map (fn [(i Int64)] -> String
                                       (let [(field (optionOr (listGet fields i) ""))
                                             (idx (optionOr (listIndexOf declared field) 0))
                                             (slot (str "%" (llvmName dest) ".key" i))
                                             (src (str "%" (llvmName dest) ".src" i))]
                                         (str "  " src " = getelementptr inbounds [" (listLength declared) " x i32], ptr " (keyIdsSym schemaName) ", i64 0, i64 " idx "\n"
                                              "  " slot " = getelementptr inbounds i32, ptr " p ".keyarr, i32 " i "\n"
                                              "  " slot ".id = load i32, ptr " src "\n"
                                              "  store i32 " slot ".id, ptr " slot "\n")))
                                     (range 0 n)) "")))]
    (str "  " p ".ready = load i1, ptr " (schemaIdReadySym schemaName) "\n"
         "  br i1 " p ".ready, label %" lbl ".alloc, label %" lbl ".resolve\n"
         lbl ".resolve:\n"
         "  call void " (schemaIdInitSym schemaName) "()\n"
         "  br label %" lbl ".alloc\n"
         lbl ".alloc:\n"
         "  " p ".schema = load i32, ptr " (schemaIdSym schemaName) "\n"
         "  " p ".objp = call ptr @asl_alloc_raw(i32 2, i64 " bytes ")\n"
         "  " p ".schemap = getelementptr inbounds i8, ptr " p ".objp, i64 8\n"
         "  store i32 " p ".schema, ptr " p ".schemap\n"
         "  " p ".np = getelementptr inbounds i8, ptr " p ".objp, i64 12\n"
         "  store i32 " n ", ptr " p ".np\n"
         "  " p ".keysp = getelementptr inbounds i8, ptr " p ".objp, i64 16\n"
         (if full (str "  store ptr " (keyIdsSym schemaName) ", ptr " p ".keysp\n")
             (str "  " p ".keyarr = getelementptr inbounds i8, ptr " p ".objp, i64 " (+ 24 (* n 16)) "\n"
                  "  store ptr " p ".keyarr, ptr " p ".keysp\n"))
         stores
         keyStores
         "  " p ".objw = ptrtoint ptr " p ".objp to i64\n"
         lhs "insertvalue %Val { i64 7, i64 0 }, i64 " p ".objw, 1\n"))

fn emitMakeClosure lhs: String dest: String callee: String caps: (List String) -> String
  (let [(p (str "%" (llvmName dest))) (n (listLength caps)) (bytes (+ 24 (* n 16)))
        (stores (stringJoin (map (fn [(i Int64)] -> String
                                    (str "  " p ".c" i "p = getelementptr inbounds i8, ptr " p ".objp, i64 " (+ 24 (* i 16)) "\n"
                                         "  store %Val " (val (optionOr (listGet caps i) "")) ", ptr " p ".c" i "p\n"))
                                  (range 0 n)) ""))]
    (str "  " p ".objp = call ptr @asl_alloc_raw(i32 4, i64 " bytes ")\n"
         "  " p ".pp = getelementptr inbounds i8, ptr " p ".objp, i64 8\n"
         "  store ptr " (protoSym callee) ", ptr " p ".pp\n"
         "  " p ".np = getelementptr inbounds i8, ptr " p ".objp, i64 16\n"
         "  store i32 " n ", ptr " p ".np\n"
         stores
         "  " p ".objw = ptrtoint ptr " p ".objp to i64\n"
         lhs "insertvalue %Val { i64 9, i64 0 }, i64 " p ".objw, 1\n"))

fn idResolvedOp? op: ty/SsaOp -> Bool
  (mt op ((ty/opConstruct _ _ _) true) ((ty/opRecord _ _ _) true) ((ty/opBuiltin name args) (partialCtor? name (listLength args))) (_ false))

fn inlinedEntryName? name: String -> Bool
  (listContains? (list "cons" "listHead" "listTail" "listEmpty?" "bytesLength" "bytesGet" "bytesSet") name)

fn stringEntryName? name: String -> Bool
  (listContains? (list "stringLength" "stringConcat" "stringSlice" "stringStartsWith?" "stringContains?" "stringToBytes") name)

fn helperEntryName? name: String -> Bool
  (or (stringEntryName? name) (listContains? (list "bytesAlloc" "@listHeadOr" "@listTailOr" "@listGetOr" "@stringSliceOr" "@listFirst" "@listRest") name))

fn nativeEntryName? name: String -> Bool
  (or (inlinedEntryName? name) (or (helperEntryName? name) (opsrt/opsEntry? name)))

fn helperEntrySym name: String -> String
  (cond ((opsrt/opsEntry? name) (opsrt/opsEntrySym name))
        ((= name "bytesAlloc") "@bytesrt.alloc")
        ((= name "stringLength") "@strrt.length")
        ((= name "stringConcat") "@strrt.concat")
        ((= name "stringSlice") "@strrt.slice")
        ((= name "stringStartsWith?") "@strrt.startsWith")
        ((= name "stringContains?") "@strrt.contains")
        ((= name "stringToBytes") "@strrt.toBytes")
        ((= name "@listHeadOr") "@listrt.headOr")
        ((= name "@listTailOr") "@listrt.tailOr")
        ((= name "@listGetOr") "@listrt.getOr")
        ((= name "@stringSliceOr") "@listrt.sliceOr")
        ((= name "@listFirst") "@listrt.first")
        (else "@listrt.rest"))

fn inlinedEntrySuffix op: ty/SsaOp -> String
  (mt op
    ((ty/opEntry name _) (if (inlinedEntryName? name) "join" ""))
    (_ ""))

fn wantTrap lbl: String who: String want: Int64 tag: String -> String
  (str lbl ":\n  call void @mathrt.want(ptr " who ", i32 " want ", i32 " tag ")\n  unreachable\n")

fn emitCons lhs: String dest: String a: String b: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (av (val a)) (bv (val b))]
    (str (valTag p bv)
         "  " p ".isList = icmp eq i32 " p ".vtag, 6\n"
         "  br i1 " p ".isList, label %" lbl ".alloc, label %" lbl ".bad\n"
         lbl ".alloc:\n"
         "  " p ".objp = call ptr @asl_alloc_cons()\n"
         "  " p ".carp = getelementptr inbounds i8, ptr " p ".objp, i64 8\n"
         "  store %Val " av ", ptr " p ".carp\n"
         "  " p ".cdrp = getelementptr inbounds i8, ptr " p ".objp, i64 24\n"
         "  store %Val " bv ", ptr " p ".cdrp\n"
         "  " p ".objw = ptrtoint ptr " p ".objp to i64\n"
         "  " p ".fastval = insertvalue %Val { i64 6, i64 0 }, i64 " p ".objw, 1\n"
         "  br label %" lbl ".join\n"
         (wantTrap (str lbl ".bad") "@.listrt.who.cons" 6 (str p ".vtag"))
         lbl ".join:\n"
         lhs "phi %Val [ " p ".fastval, %" lbl ".alloc ]\n"))

fn emitListEmpty lhs: String dest: String xs: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (xv (val xs))]
    (str (valTag p xv)
         "  " p ".isList = icmp eq i32 " p ".vtag, 6\n"
         "  br i1 " p ".isList, label %" lbl ".chk, label %" lbl ".bad\n"
         lbl ".chk:\n"
         (valObj p xv)
         "  " p ".fastval = icmp eq ptr " p ".obj, null\n"
         "  br label %" lbl ".join\n"
         (wantTrap (str lbl ".bad") "@.listrt.who.listEmpty" 6 (str p ".vtag"))
         lbl ".join:\n"
         lhs "phi i1 [ " p ".fastval, %" lbl ".chk ]\n"))

fn emitBytesLength lhs: String dest: String xs: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (xv (val xs))]
    (str (valTag p xv)
         "  " p ".isBytes = icmp eq i32 " p ".vtag, 11\n"
         "  br i1 " p ".isBytes, label %" lbl ".chk, label %" lbl ".bad\n"
         lbl ".chk:\n"
         (valObj p xv)
         "  " p ".lenp = getelementptr inbounds i8, ptr " p ".obj, i64 8\n"
         "  " p ".fastval = load i64, ptr " p ".lenp\n"
         "  br label %" lbl ".join\n"
         (wantTrap (str lbl ".bad") "@.bytesrt.who.bytesLength" 11 (str p ".vtag"))
         lbl ".join:\n"
         lhs "phi i64 [ " p ".fastval, %" lbl ".chk ]\n"))

fn emitListExtract lhs: String dest: String xs: String fieldOff: Int64 who: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (xv (val xs))
        (noneLbl (str lbl ".none")) (someLbl (str lbl ".some"))
        (noneDone (str lbl ".none.alloc")) (someDone (str lbl ".some.alloc"))]
    (str (valTag p xv)
         "  " p ".isList = icmp eq i32 " p ".vtag, 6\n"
         "  br i1 " p ".isList, label %" lbl ".chk, label %" lbl ".bad\n"
         lbl ".chk:\n"
         (valObj p xv)
         "  " p ".isNil = icmp eq ptr " p ".obj, null\n"
         "  br i1 " p ".isNil, label %" noneLbl ", label %" someLbl "\n"
         noneLbl ":\n"
         (emitCtorAlloc noneLbl "none" (list))
         "  %" noneLbl ".val = insertvalue %Val { i64 8, i64 0 }, i64 %" noneLbl ".objw, 1\n"
         "  br label %" lbl ".join\n"
         someLbl ":\n"
         "  %" someLbl ".fp = getelementptr inbounds i8, ptr " p ".obj, i64 " fieldOff "\n"
         "  %" someLbl ".fv = load %Val, ptr %" someLbl ".fp\n"
         (emitCtorAlloc someLbl "some" (list (str "%" someLbl ".fv")))
         "  %" someLbl ".val = insertvalue %Val { i64 8, i64 0 }, i64 %" someLbl ".objw, 1\n"
         "  br label %" lbl ".join\n"
         (wantTrap (str lbl ".bad") who 6 (str p ".vtag"))
         lbl ".join:\n"
         lhs "phi %Val [ %" noneLbl ".val, %" noneDone " ], [ %" someLbl ".val, %" someDone " ]\n"))

fn emitBytesGet lhs: String dest: String xs: String idx: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (xv (val xs)) (iv (val idx))]
    (str (valTag p xv)
         "  " p ".isBytes = icmp eq i32 " p ".vtag, 11\n"
         "  br i1 " p ".isBytes, label %" lbl ".chk, label %" lbl ".bad\n"
         lbl ".chk:\n"
         (valObj p xv)
         "  " p ".lenp = getelementptr inbounds i8, ptr " p ".obj, i64 8\n"
         "  " p ".len = load i64, ptr " p ".lenp\n"
         "  " p ".inRange = icmp ult i64 " iv ", " p ".len\n"
         "  br i1 " p ".inRange, label %" lbl ".fast, label %" lbl ".range\n"
         lbl ".fast:\n"
         "  " p ".datap = getelementptr inbounds i8, ptr " p ".obj, i64 24\n"
         "  " p ".data = load ptr, ptr " p ".datap\n"
         "  " p ".bp = getelementptr inbounds i8, ptr " p ".data, i64 " iv "\n"
         "  " p ".b8 = load i8, ptr " p ".bp\n"
         "  " p ".fastval = zext i8 " p ".b8 to i64\n"
         "  br label %" lbl ".join\n"
         (wantTrap (str lbl ".bad") "@.bytesrt.who.bytesGet" 11 (str p ".vtag"))
         lbl ".range:\n"
         "  call void @bytesrt.slotBad(ptr @.bytesrt.who.bytesGet, i64 " iv ", i64 " p ".len)\n"
         "  unreachable\n"
         lbl ".join:\n"
         lhs "phi i64 [ " p ".fastval, %" lbl ".fast ]\n"))

fn emitBytesSet lhs: String dest: String xs: String idx: String byteVal: String -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (xv (val xs)) (iv (val idx)) (bv (val byteVal))]
    (str (valTag p xv)
         "  " p ".isBytes = icmp eq i32 " p ".vtag, 11\n"
         "  br i1 " p ".isBytes, label %" lbl ".chk, label %" lbl ".bad\n"
         lbl ".chk:\n"
         (valObj p xv)
         "  " p ".lenp = getelementptr inbounds i8, ptr " p ".obj, i64 8\n"
         "  " p ".len = load i64, ptr " p ".lenp\n"
         "  " p ".iok = icmp ult i64 " iv ", " p ".len\n"
         "  br i1 " p ".iok, label %" lbl ".byte, label %" lbl ".range\n"
         lbl ".byte:\n"
         "  " p ".bok = icmp ult i64 " bv ", 256\n"
         "  br i1 " p ".bok, label %" lbl ".fast, label %" lbl ".notByte\n"
         lbl ".fast:\n"
         "  " p ".datap = getelementptr inbounds i8, ptr " p ".obj, i64 24\n"
         "  " p ".data = load ptr, ptr " p ".datap\n"
         "  " p ".bp = getelementptr inbounds i8, ptr " p ".data, i64 " iv "\n"
         "  " p ".b8 = trunc i64 " bv " to i8\n"
         "  store i8 " p ".b8, ptr " p ".bp\n"
         "  br label %" lbl ".join\n"
         (wantTrap (str lbl ".bad") "@.bytesrt.who.bytesSet" 11 (str p ".vtag"))
         lbl ".range:\n"
         "  call void @bytesrt.slotBad(ptr @.bytesrt.who.bytesSet, i64 " iv ", i64 " p ".len)\n"
         "  unreachable\n"
         lbl ".notByte:\n"
         "  call void @bytesrt.notByte(i64 " bv ")\n"
         "  unreachable\n"
         lbl ".join:\n"
         lhs "phi %Val [ { i64 0, i64 0 }, %" lbl ".fast ]\n"))

fn emitInlinedEntry lhs: String dest: String name: String args: (List String) -> String
  (let [(a0 (optionOr (listGet args 0) "")) (a1 (optionOr (listGet args 1) "")) (a2 (optionOr (listGet args 2) ""))]
    (cond
      ((= name "cons") (emitCons lhs dest a0 a1))
      ((= name "listHead") (emitListExtract lhs dest a0 8 "@.listrt.who.listHead"))
      ((= name "listTail") (emitListExtract lhs dest a0 24 "@.listrt.who.listTail"))
      ((= name "listEmpty?") (emitListEmpty lhs dest a0))
      ((= name "bytesLength") (emitBytesLength lhs dest a0))
      ((= name "bytesGet") (emitBytesGet lhs dest a0 a1))
      (else (emitBytesSet lhs dest a0 a1 a2))))

fn emitNativeEntry lhs: String dest: String b: ty/SsaBuiltin args: (List String) -> String
  (if (inlinedEntryName? b.name)
    (emitInlinedEntry lhs dest b.name args)
    (str lhs "call " (llTy b.result) " " (helperEntrySym b.name) "(" (typedArgs args b.args) ")\n"))

fn nativeEntry name: String n: Int64 -> (Option ty/SsaBuiltin)
  (if (nativeEntryName? name) (ty/builtinEntry name n) (none))

fn seqBuiltin? name: String n: Int64 -> Bool
  (or (= name "partial")
      (or (and (= n 2) (= name "bytesGetFloat64"))
          (and (= n 3) (= name "bytesSetFloat64"))))

fn partialCtor? name: String n: Int64 -> Bool
  (and (= name "partial") (> n 0))

fn emitSeqBuiltin lhs: String dest: String name: String args: (List String) -> String
  (let [(vals (stringJoin (map (fn [(a String)] -> String (str "%Val " (val a))) args) ", "))]
    (cond
      ((partialCtor? name (listLength args))
        (let [(lbl (llvmName dest))]
          (str (emitCtorAlloc lbl "partial" (map val args))
               lhs "insertvalue %Val { i64 8, i64 0 }, i64 %" lbl ".objw, 1\n")))
      ((= name "partial") (str lhs "call %Val @listrt.partialNone()\n"))
      ((= name "bytesGetFloat64") (str lhs "call %Val @bytesrt.getFloat64(" vals ")\n"))
      (else (str lhs "call %Val @bytesrt.setFloat64(" vals ")\n"))))

fn listCell p: String acc: ListCells item: String kept: String -> ListCells
  (let [(k (- acc.index 1))
        (c (str p ".c" k))
        (store (if (stringEmpty? kept) "" (str "  store %Val " c ", ptr " kept "\n")))]
    (ListCells :lines (cons (str "  " c " = call %Val @listrt.cell(%Val " (val item) ", %Val " acc.tail ")\n" store) acc.lines)
               :index k
               :tail c))

fn emitListLiteral lhs: String dest: String items: (List String) -> String
  (emitListLiteralKept lhs dest items "")

fn emitListLiteralKept lhs: String dest: String items: (List String) kept: String -> String
  (let [(p (str "%" (llvmName dest)))
        (built (fold (fn [(acc ListCells) (item String)] -> ListCells (listCell p acc item kept))
                     (ListCells :lines (list) :index (listLength items) :tail "{ i64 6, i64 0 }")
                     (listReverse items)))]
    (str (stringJoin (listReverse built.lines) "")
         lhs "insertvalue %Val " built.tail ", i64 6, 0\n"))

fn emitStaticFieldRead lhs: String env: FnEnv dest: String base: String index: Int64 -> String
  (let [(p (str "%" (llvmName dest))) (lbl (llvmName dest)) (b (val base)) (tagOff (+ 24 (* index 16)))]
    (str (valTag p b)
         "  " p ".isRec = icmp eq i32 " p ".vtag, 7\n"
         "  br i1 " p ".isRec, label %" lbl ".chk, label %" lbl ".bad\n"
         lbl ".bad:\n"
         "  call void @rterr.match(ptr " (nameSym env.name) ")\n"
         "  unreachable\n"
         lbl ".chk:\n"
         (valObj p b)
         "  " p ".np = getelementptr inbounds i8, ptr " p ".obj, i64 12\n"
         "  " p ".n = load i32, ptr " p ".np\n"
         "  " p ".n64 = sext i32 " p ".n to i64\n"
         "  " p ".inRange = icmp slt i64 " index ", " p ".n64\n"
         "  br i1 " p ".inRange, label %" lbl ".fast, label %" lbl ".bad\n"
         lbl ".fast:\n"
         "  " p ".slotp = getelementptr inbounds i8, ptr " p ".obj, i64 " tagOff "\n"
         lhs "load %Val, ptr " p ".slotp\n"))

fn staticFieldInstr? env: FnEnv ins: ty/SsaInstr -> Bool
  (mt ins.op
    ((ty/opField base field) (and (not (some? (nameIndexGet env.fused ins.dest))) (some? (staticFieldIndex env base field))))
    (_ false))

fn typedFieldInstr? env: FnEnv ins: ty/SsaInstr -> Bool
  (mt ins.op
    ((ty/opField base field) (and (not (some? (nameIndexGet env.fused ins.dest)))
                                  (and (not (some? (staticFieldIndex env base field))) (some? (typedFieldIndex env base field)))))
    (_ false))

fn arrayItems op: ty/SsaOp -> (List String)
  (mt op
    ((ty/opBuiltin name args) (if (or (errorBuiltin? name (listLength args)) (or (mathBuiltin? name (listLength args)) (or (seqBuiltin? name (listLength args)) (opsrt/opsBuiltin? name (listLength args))))) (list) args))
    ((ty/opEntry name args) (if (some? (ty/builtinEntry name (listLength args))) (list) args))
    ((ty/opCallClosure _ args) args)
    (_ (list)))

fn arrayName dest: String -> String
  (str "%" (llvmName dest) ".argv")

fn allocaFor ins: ty/SsaInstr -> String
  (let [(n (listLength (arrayItems ins.op)))]
    (if (= n 0) "" (str "  " (arrayName ins.dest) " = alloca [" n " x %Val]\n")))

fn arrayArg dest: String n: Int64 -> String
  (if (= n 0) "ptr null" (str "ptr " (arrayName dest)))

fn fillArray dest: String items: (List String) -> String
  (let [(n (listLength items))]
    (stringJoin (map (fn [(i Int64)] -> String
                        (let [(slot (str "%" (llvmName dest) ".a" i))]
                          (str "  " slot " = getelementptr [" n " x %Val], ptr " (arrayName dest) ", i64 0, i64 " i "\n"
                               "  store %Val " (val (optionOr (listGet items i) "")) ", ptr " slot "\n")))
                      (range 0 n)) ""))

fn typedArgs args: (List String) types: (List ty/SsaTy) -> String
  (stringJoin (map (fn [(i Int64)] -> String
                      (str (llTy (optionOr (listGet types i) (ty/tyVal))) " " (val (optionOr (listGet args i) ""))))
                    (range 0 (listLength args))) ", ")

fn signatureTypes f: ty/SsaFunction -> (List ty/SsaTy)
  (map (fn [(p ty/SsaParam)] -> ty/SsaTy p.ty) (listAppend f.captures f.params))

fn spillGprLimit -> Int64
  6

fn spillFprLimit -> Int64
  8

fn spillCapacity -> Int64
  1024

fn gprWords t: ty/SsaTy -> Int64
  (mt t ((ty/tyVal) 2) ((ty/tyRec _) 2) ((ty/tyI64) 1) ((ty/tyI1) 1) ((ty/tyF64) 0) ((ty/tyPtr) 1) ((ty/tyI32) 1))

fn fprWords t: ty/SsaTy -> Int64
  (mt t ((ty/tyF64) 1) (_ 0))

fn spillSlotsFrom types: (List ty/SsaTy) i: Int64 gpr: Int64 fpr: Int64 slot: Int64 -> (List Int64)
  (mt (listGet types i)
    ((none) (list))
    ((some t) (let [(g (+ gpr (gprWords t))) (fl (+ fpr (fprWords t)))]
                (if (and (<= g (spillGprLimit)) (<= fl (spillFprLimit)))
                  (cons -1 (spillSlotsFrom types (+ i 1) g fl slot))
                  (cons slot (spillSlotsFrom types (+ i 1) gpr fpr (+ slot 1)))))))

fn spillSlots types: (List ty/SsaTy) -> (List Int64)
  (spillSlotsFrom types 0 0 0 0)

fn spillCount types: (List ty/SsaTy) -> Int64
  (listLength (filter (fn [(k Int64)] -> Bool (>= k 0)) (spillSlots types)))

fn spillSlotPtr p: String k: Int64 -> String
  (str "  " p " = getelementptr inbounds [" (spillCapacity) " x %Val], ptr @asl_rt_spill, i64 0, i64 " k "\n")

fn tailCallArgs dest: String args: (List String) types: (List ty/SsaTy) -> (Pair String String)
  (let [(slots (spillSlots types))
        (ix (range 0 (listLength args)))
        (one (fn [(i Int64)] -> String (str (llTy (optionOr (listGet types i) (ty/tyVal))) " " (val (optionOr (listGet args i) "")))))
        (stores (stringJoin (map (fn [(i Int64)] -> String
                                    (let [(k (optionOr (listGet slots i) -1)) (p (str "%" (llvmName dest) ".spill" i))]
                                      (if (< k 0) "" (str (spillSlotPtr p k) "  store " (one i) ", ptr " p "\n"))))
                                  ix) ""))
        (regs (stringJoin (map one (filter (fn [(i Int64)] -> Bool (< (optionOr (listGet slots i) -1) 0)) ix)) ", "))]
    (pair stores regs))

fn spillLoads params: (List ty/SsaParam) -> String
  (let [(slots (spillSlots (map (fn [(p ty/SsaParam)] -> ty/SsaTy p.ty) params)))]
    (stringJoin (map (fn [(i Int64)] -> String
                       (mt (listGet params i)
                         ((none) "")
                         ((some p) (let [(k (optionOr (listGet slots i) -1)) (sp (str (val p.name) ".spillp"))]
                                     (if (< k 0) "" (str (spillSlotPtr sp k) "  " (val p.name) " = load " (llTy p.ty) ", ptr " sp "\n"))))))
                     (range 0 (listLength params))) ""))

fn registerParams params: (List ty/SsaParam) -> (List ty/SsaParam)
  (let [(slots (spillSlots (map (fn [(p ty/SsaParam)] -> ty/SsaTy p.ty) params)))]
    (map (fn [(i Int64)] -> ty/SsaParam (optionOr (listGet params i) (ty/ssaParam "" (ty/tyVal))))
         (filter (fn [(i Int64)] -> Bool (< (optionOr (listGet slots i) -1) 0)) (range 0 (listLength params)))))

fn tailCall lhs: String dest: String retTy: ty/SsaTy callee: String args: (List String) types: (List ty/SsaTy) -> String
  (let [(parts (tailCallArgs dest args types))]
    (str (pairFirst parts) lhs "call tailcc " (llTy retTy) " " (fnSym callee) "(" (pairSecond parts) ")\n"))

fn externCallType e: ty/SsaExtern -> String
  (str (llTy e.ret) " (" (stringJoin (listAppend (map llTy e.params) (if e.variadic (list "...") (list))) ", ") ")")

fn nativeArgs env: FnEnv args: (List String) types: (List ty/SsaTy) -> String
  (stringJoin (map (fn [(i Int64)] -> String
                      (let [(nm (optionOr (listGet args i) ""))]
                        (mt (listGet types i)
                          ((some t) (str (llTy t) " " (val nm)))
                          ((none) (str (llTy (optionOr (nameIndexGet env.defs nm) (ty/tyVal))) " " (val nm))))))
                    (range 0 (listLength args))) ", ")

fn emitCall env: FnEnv lhs: String dest: String callee: String args: (List String) -> String
  (mt (nameIndexGet env.mod.functions callee)
    ((some f) (tailCall lhs dest f.retTy callee args (signatureTypes f)))
    ((none)
      (mt (nameIndexGet env.mod.externs callee)
        ((some e)
          (cond
            ((not e.typed) (str lhs "call %Val " (fnSym callee) "(" (typedArgs args (list)) ")\n"))
            ((nativeExtern? e) (str lhs "call " (externCallType e) " " (fnSym callee) "(" (nativeArgs env args e.params) ")\n"))
            (else (tailCall lhs dest e.ret callee args e.params))))
        ((none)
          (str lhs "call %Val " (fnSym callee) "(" (typedArgs args (list)) ")\n")))))

fn emitConst env: FnEnv lhs: String dest: String t: ty/SsaTy c: ty/SsaConst -> String
  (let [(tn (ty/ssaTyName t))]
    (mt c
      ((ty/constInt n) (cond ((= tn "i64") (str lhs "bitcast i64 " n " to i64\n"))
                              ((= tn "i32") (str lhs "bitcast i32 " n " to i32\n"))
                              (else (str lhs "insertvalue %Val { i64 2, i64 0 }, i64 " n ", 1\n"))))
      ((ty/constFloat x) (if (= tn "f64") (str lhs "bitcast double " (llvmFloat x) " to double\n") (boxInline lhs dest (ty/tyF64) (llvmFloat x))))
      ((ty/constBool b) (if (= tn "i1") (str lhs "bitcast i1 " (if b "true" "false") " to i1\n") (str lhs "insertvalue %Val { i64 1, i64 0 }, i64 " (if b "1" "0") ", 1\n")))
      ((ty/constStr i) (if (= tn "ptr") (str lhs "bitcast ptr @str." i " to ptr\n") (str lhs "call %Val @objrt.str(ptr " (strCellSym i) ", ptr @str." i ", i64 " (constStringLength env i) ")\n")))
      ((ty/constUnit) (str lhs "insertvalue %Val { i64 0, i64 0 }, i64 0, 1\n"))
      ((ty/constKeyword n) (let [(p (val dest))]
                             (str "  " p ".id = call i32 @objrt.nameId(" (nameIdArgs n) ")\n"
                                  "  " p ".idw = zext i32 " p ".id to i64\n"
                                  "  " p ".idhi = shl i64 " p ".idw, 32\n"
                                  "  " p ".word = or i64 " p ".idhi, 4\n"
                                  lhs "insertvalue %Val { i64 0, i64 0 }, i64 " p ".word, 0\n")))
      ((ty/constSymbol n) (str lhs "call %Val @objrt.symbol(ptr " (nameSym n) ")\n"))))


fn calleeArity menv: ModEnv callee: String -> Int64
  (mt (nameIndexGet menv.functions callee) ((some f) (listLength f.params)) ((none) 0))

fn primPart dest: String part: String -> String
  (str "%" (llvmName dest) ".p." part)

fn trapping? op: ty/SsaOp -> Bool
  (mt op
    ((ty/opPrim name _) (or (listContains? (list "addInt" "subInt" "mulInt" "quotInt" "remInt" "floatToInt" "addIntHost" "subIntHost" "mulIntHost" "divIntHost" "modIntHost" "negIntHost") name)
                             (= name "rawNarrowI32")))
    (_ false))

fn trapUnless dest: String okCond: String bad: Bool -> String
  (let [(trap (str (llvmName dest) ".p.trap")) (ok (str (llvmName dest) ".p.ok"))]
    (str "  br i1 " okCond ", label %" (if bad trap ok) ", label %" (if bad ok trap) "\n"
         trap ":\n  call void @llvm.trap()\n  unreachable\n"
         ok ":\n"))

fn hostTrapUnless dest: String bad: String kind: String -> String
  (let [(trap (str (llvmName dest) ".p.trap")) (ok (str (llvmName dest) ".p.ok"))]
    (str "  br i1 " bad ", label %" trap ", label %" ok "\n"
         trap ":\n  call void @rterr.int(i32 " kind ")\n  unreachable\n"
         ok ":\n"))

fn hostOverflowPrim lhs: String dest: String intrinsic: String kind: String a: String b: String -> String
  (let [(pair (primPart dest "pair")) (bad (primPart dest "bad"))]
    (str "  " pair " = call {i64, i1} @llvm." intrinsic ".with.overflow.i64(i64 " a ", i64 " b ")\n"
         lhs "extractvalue {i64, i1} " pair ", 0\n"
         "  " bad " = extractvalue {i64, i1} " pair ", 1\n"
         (hostTrapUnless dest bad kind)))

fn hostDivPrim lhs: String dest: String a: String b: String -> String
  (let [(zero (primPart dest "zero")) (min (primPart dest "min")) (neg (primPart dest "neg")) (over (primPart dest "over")) (bad (primPart dest "bad")) (kind (primPart dest "kind"))
        (q (primPart dest "q")) (r (primPart dest "r")) (signs (primPart dest "signs")) (anyNeg (primPart dest "anyNeg")) (unlikely (primPart dest "unlikely")) (fixed (primPart dest "fixed"))]
    (str "  " zero " = icmp eq i64 " b ", 0\n"
         "  " min " = icmp eq i64 " a ", -9223372036854775808\n"
         "  " neg " = icmp eq i64 " b ", -1\n"
         "  " over " = and i1 " min ", " neg "\n"
         "  " bad " = or i1 " zero ", " over "\n"
         "  " kind " = select i1 " zero ", i32 5, i32 3\n"
         "  br i1 " bad ", label %" (llvmName dest) ".p.trap, label %" (llvmName dest) ".p.nz\n"
         (llvmName dest) ".p.trap:\n  call void @rterr.int(i32 " kind ")\n  unreachable\n"
         (llvmName dest) ".p.nz:\n"
         "  " q " = sdiv i64 " a ", " b "\n"
         "  " r " = srem i64 " a ", " b "\n"
         "  " signs " = or i64 " r ", " b "\n"
         "  " anyNeg " = icmp slt i64 " signs ", 0\n"
         "  " unlikely " = call i1 @llvm.expect.i1(i1 " anyNeg ", i1 false)\n"
         "  br i1 " unlikely ", label %" (llvmName dest) ".p.fix, label %" (llvmName dest) ".p.ok\n"
         (llvmName dest) ".p.fix:\n"
         "  " fixed " = call i64 @mathrt.floorDivFix(i64 " q ", i64 " r ", i64 " b ")\n"
         "  br label %" (llvmName dest) ".p.ok\n"
         (llvmName dest) ".p.ok:\n"
         lhs "phi i64 [ " q ", %" (llvmName dest) ".p.nz ], [ " fixed ", %" (llvmName dest) ".p.fix ]\n"))

fn hostModPrim lhs: String dest: String a: String b: String -> String
  (let [(zero (primPart dest "zero")) (neg (primPart dest "neg")) (divisor (primPart dest "divisor")) (r (primPart dest "r"))
        (signs (primPart dest "signs")) (anyNeg (primPart dest "anyNeg")) (unlikely (primPart dest "unlikely")) (fixed (primPart dest "fixed"))
        (lbl (llvmName dest))]
    (str "  " zero " = icmp eq i64 " b ", 0\n"
         "  br i1 " zero ", label %" lbl ".p.trap, label %" lbl ".p.nz\n"
         lbl ".p.trap:\n  call void @rterr.int(i32 6)\n  unreachable\n"
         lbl ".p.nz:\n"
         "  " neg " = icmp eq i64 " b ", -1\n"
         "  " divisor " = select i1 " neg ", i64 1, i64 " b "\n"
         "  " r " = srem i64 " a ", " divisor "\n"
         "  " signs " = or i64 " r ", " b "\n"
         "  " anyNeg " = icmp slt i64 " signs ", 0\n"
         "  " unlikely " = call i1 @llvm.expect.i1(i1 " anyNeg ", i1 false)\n"
         "  br i1 " unlikely ", label %" lbl ".p.fix, label %" lbl ".p.ok\n"
         lbl ".p.fix:\n"
         "  " fixed " = call i64 @mathrt.floorModFix(i64 " r ", i64 " b ")\n"
         "  br label %" lbl ".p.ok\n"
         lbl ".p.ok:\n"
         lhs "phi i64 [ " r ", %" lbl ".p.nz ], [ " fixed ", %" lbl ".p.fix ]\n"))

fn hostNegPrim lhs: String dest: String a: String -> String
  (let [(bad (primPart dest "bad"))]
    (str "  " bad " = icmp eq i64 " a ", -9223372036854775808\n"
         (hostTrapUnless dest bad "1")
         lhs "sub i64 0, " a "\n"))

fn overflowPrim lhs: String dest: String intrinsic: String a: String b: String -> String
  (let [(pair (primPart dest "pair")) (bad (primPart dest "bad"))]
    (str "  " pair " = call {i64, i1} @llvm." intrinsic ".with.overflow.i64(i64 " a ", i64 " b ")\n"
         lhs "extractvalue {i64, i1} " pair ", 0\n"
         "  " bad " = extractvalue {i64, i1} " pair ", 1\n"
         (trapUnless dest bad true)))

fn quotPrim lhs: String dest: String a: String b: String -> String
  (let [(zero (primPart dest "zero")) (min (primPart dest "min")) (neg (primPart dest "neg")) (over (primPart dest "over")) (bad (primPart dest "bad"))]
    (str "  " zero " = icmp eq i64 " b ", 0\n"
         "  " min " = icmp eq i64 " a ", -9223372036854775808\n"
         "  " neg " = icmp eq i64 " b ", -1\n"
         "  " over " = and i1 " min ", " neg "\n"
         "  " bad " = or i1 " zero ", " over "\n"
         (trapUnless dest bad true)
         lhs "sdiv i64 " a ", " b "\n"))

fn remPrim lhs: String dest: String a: String b: String -> String
  (let [(bad (primPart dest "bad")) (neg (primPart dest "neg")) (divisor (primPart dest "divisor"))]
    (str "  " bad " = icmp eq i64 " b ", 0\n"
         (trapUnless dest bad true)
         "  " neg " = icmp eq i64 " b ", -1\n"
         "  " divisor " = select i1 " neg ", i64 1, i64 " b "\n"
         lhs "srem i64 " a ", " divisor "\n"))

fn floatToIntPrim lhs: String dest: String a: String -> String
  (let [(low (primPart dest "low")) (high (primPart dest "high")) (fits (primPart dest "fits")) (bad (primPart dest "bad"))]
    (str "  " low " = fcmp oge double " a ", 0xC3E0000000000000\n"
         "  " high " = fcmp olt double " a ", 0x43E0000000000000\n"
         "  " fits " = and i1 " low ", " high "\n"
         "  " bad " = xor i1 " fits ", true\n"
         (hostTrapUnless dest bad "8")
         lhs "fptosi double " a " to i64\n"))

fn binaryInstr name: String -> String
  (cond
    ((= name "eqInt") "icmp eq i64") ((= name "neInt") "icmp ne i64")
    ((= name "ltInt") "icmp slt i64") ((= name "leInt") "icmp sle i64")
    ((= name "gtInt") "icmp sgt i64") ((= name "geInt") "icmp sge i64")
    ((= name "addFloat") "fadd double") ((= name "subFloat") "fsub double")
    ((= name "mulFloat") "fmul double") ((= name "divFloat") "fdiv double")
    ((= name "eqFloat") "fcmp oeq double") ((= name "neFloat") "fcmp une double")
    ((= name "ltFloat") "fcmp olt double") ((= name "leFloat") "fcmp ole double")
    ((= name "gtFloat") "fcmp ogt double") ((= name "geFloat") "fcmp oge double")
    ((= name "andBool") "and i1") ((= name "orBool") "or i1")
    ((= name "eqBool") "icmp eq i1") ((= name "neBool") "icmp ne i1")
    ((= name "rawAddI64") "add i64") ((= name "rawSubI64") "sub i64") ((= name "rawMulI64") "mul i64")
    ((= name "rawAndI64") "and i64") ((= name "rawOrI64") "or i64") ((= name "rawXorI64") "xor i64")
    ((= name "rawAddI32") "add i32") ((= name "rawSubI32") "sub i32") ((= name "rawMulI32") "mul i32")
    ((= name "rawAndI32") "and i32") ((= name "rawOrI32") "or i32") ((= name "rawXorI32") "xor i32")
    ((= name "rawEqI32") "icmp eq i32") ((= name "rawNeI32") "icmp ne i32")
    ((= name "rawLtI32") "icmp slt i32") ((= name "rawLeI32") "icmp sle i32")
    ((= name "rawGtI32") "icmp sgt i32") ((= name "rawGeI32") "icmp sge i32")
    (else ""))

fn shiftRaw lhs: String dest: String op: String ty: String maskVal: Int64 a: String b: String -> String
  (let [(m (primPart dest "m"))]
    (str "  " m " = and " ty " " b ", " maskVal "\n"
         lhs op " " ty " " a ", " m "\n"))

fn narrowI32Prim lhs: String dest: String a: String -> String
  (let [(low (primPart dest "low")) (high (primPart dest "high")) (fits (primPart dest "fits")) (bad (primPart dest "bad"))]
    (str "  " low " = icmp sge i64 " a ", -2147483648\n"
         "  " high " = icmp sle i64 " a ", 2147483647\n"
         "  " fits " = and i1 " low ", " high "\n"
         "  " bad " = xor i1 " fits ", true\n"
         (hostTrapUnless dest bad "7")
         lhs "trunc i64 " a " to i32\n"))

fn rawLoadSame lhs: String dest: String base: String offset: String ty: String -> String
  (let [(gep (primPart dest "gep"))]
    (str "  " gep " = getelementptr inbounds i8, ptr " base ", i64 " offset "\n"
         lhs "load " ty ", ptr " gep "\n"))

fn rawLoadI8Prim lhs: String dest: String base: String offset: String -> String
  (let [(gep (primPart dest "gep")) (raw (primPart dest "raw"))]
    (str "  " gep " = getelementptr inbounds i8, ptr " base ", i64 " offset "\n"
         "  " raw " = load i8, ptr " gep "\n"
         lhs "zext i8 " raw " to i32\n"))

fn rawStoreSame lhs: String dest: String base: String offset: String value: String ty: String -> String
  (let [(gep (primPart dest "gep"))]
    (str "  " gep " = getelementptr inbounds i8, ptr " base ", i64 " offset "\n"
         "  store " ty " " value ", ptr " gep "\n"
         lhs "bitcast i1 true to i1\n"))

fn rawStoreI8Prim lhs: String dest: String base: String offset: String value: String -> String
  (let [(gep (primPart dest "gep")) (trunc (primPart dest "trunc"))]
    (str "  " gep " = getelementptr inbounds i8, ptr " base ", i64 " offset "\n"
         "  " trunc " = trunc i32 " value " to i8\n"
         "  store i8 " trunc ", ptr " gep "\n"
         lhs "bitcast i1 true to i1\n"))

fn emitPrim lhs: String dest: String name: String args: (List String) -> String
  (let [(a (val (optionOr (listGet args 0) ""))) (b (val (optionOr (listGet args 1) ""))) (c (val (optionOr (listGet args 2) "")))]
    (cond
      ((= name "addInt") (overflowPrim lhs dest "sadd" a b))
      ((= name "subInt") (overflowPrim lhs dest "ssub" a b))
      ((= name "mulInt") (overflowPrim lhs dest "smul" a b))
      ((= name "quotInt") (quotPrim lhs dest a b))
      ((= name "remInt") (remPrim lhs dest a b))
      ((= name "floatToInt") (floatToIntPrim lhs dest a))
      ((= name "addIntHost") (hostOverflowPrim lhs dest "sadd" "0" a b))
      ((= name "subIntHost") (hostOverflowPrim lhs dest "ssub" "1" a b))
      ((= name "mulIntHost") (hostOverflowPrim lhs dest "smul" "2" a b))
      ((= name "divIntHost") (hostDivPrim lhs dest a b))
      ((= name "modIntHost") (hostModPrim lhs dest a b))
      ((= name "negIntHost") (hostNegPrim lhs dest a))
      ((= name "negFloat") (str lhs "fneg double " a "\n"))
      ((= name "intToFloat") (str lhs "sitofp i64 " a " to double\n"))
      ((= name "notBool") (str lhs "xor i1 " a ", true\n"))
      ((= name "rawWidenI32") (str lhs "sext i32 " a " to i64\n"))
      ((= name "rawNarrowI32") (narrowI32Prim lhs dest a))
      ((= name "rawPtrIsNull") (str lhs "icmp eq ptr " a ", null\n"))
      ((= name "rawPtrToInt") (str lhs "ptrtoint ptr " a " to i64\n"))
      ((= name "rawIntToPtr") (str lhs "inttoptr i64 " a " to ptr\n"))
      ((= name "rawShlI64") (shiftRaw lhs dest "shl" "i64" 63 a b))
      ((= name "rawLshrI64") (shiftRaw lhs dest "lshr" "i64" 63 a b))
      ((= name "rawAshrI64") (shiftRaw lhs dest "ashr" "i64" 63 a b))
      ((= name "rawShlI32") (shiftRaw lhs dest "shl" "i32" 31 a b))
      ((= name "rawLshrI32") (shiftRaw lhs dest "lshr" "i32" 31 a b))
      ((= name "rawAshrI32") (shiftRaw lhs dest "ashr" "i32" 31 a b))
      ((= name "rawLoadI8") (rawLoadI8Prim lhs dest a b))
      ((= name "rawLoadI32") (rawLoadSame lhs dest a b "i32"))
      ((= name "rawLoadI64") (rawLoadSame lhs dest a b "i64"))
      ((= name "rawStoreI8") (rawStoreI8Prim lhs dest a b c))
      ((= name "rawStoreI32") (rawStoreSame lhs dest a b c "i32"))
      ((= name "rawStoreI64") (rawStoreSame lhs dest a b c "i64"))
      (else (str lhs (binaryInstr name) " " a ", " b "\n"))))

fn fusedUnbox? env: FnEnv op: ty/SsaOp -> Bool
  (mt op ((ty/opUnbox v) (some? (nameIndexGet env.fused v))) (_ false))

fn plainUnbox? op: ty/SsaOp -> Bool
  (mt op ((ty/opUnbox _) true) (_ false))

fn unfusedVariantField? env: FnEnv ins: ty/SsaInstr -> Bool
  (mt ins.op ((ty/opVariantField _ _) (not (some? (nameIndexGet env.fused ins.dest)))) (_ false))

fn exitLabel env: FnEnv b: ty/SsaBlock -> String
  (let [(afterInstrs (fold (fn [(acc String) (ins ty/SsaInstr)] -> String
                             (let [(entrySuffix (inlinedEntrySuffix ins.op))]
                               (cond
                                 ((trapping? ins.op) (str (llvmName ins.dest) ".p.ok"))
                                 ((fusedUnbox? env ins.op) (str (llvmName ins.dest) ".join"))
                                 ((staticFieldInstr? env ins) (str (llvmName ins.dest) ".fast"))
                                 ((typedFieldInstr? env ins) (str (llvmName ins.dest) ".join"))
                                 ((plainUnbox? ins.op) (str (llvmName ins.dest) ".ok"))
                                 ((unfusedVariantField? env ins) (str (llvmName ins.dest) ".join"))
                                 ((idResolvedOp? ins.op) (str (llvmName ins.dest) ".alloc"))
                                 ((!= entrySuffix "") (str (llvmName ins.dest) "." entrySuffix))
                                 (else acc))))
                           (label b.label) b.instrs))]
    (mt b.term
      ((ty/termSwitch _ _ _ _) (str (label b.label) ".match"))
      ((ty/termBranch c _ _) (if (= (ty/ssaTyName (defType env c)) "i1") afterInstrs (str (label b.label) ".cond.ok")))
      (_ afterInstrs)))

fn emitInstr env: FnEnv ins: ty/SsaInstr -> String
  (let [(d ins.dest)
        (t ins.ty)
        (op ins.op)
        (lhs (str "  " (val d) " = "))
        (items (arrayItems op))
        (arr (arrayArg d (listLength items)))]
    (mt op
      ((ty/opField base field) (if (some? (nameIndexGet env.fused d)) ""
                                  (mt (staticFieldIndex env base field)
                                    ((some idx) (emitStaticFieldRead lhs env d base idx))
                                    ((none) (mt (typedFieldIndex env base field)
                                              ((some idx) (emitTypedFieldRead lhs d (val base) field idx))
                                              ((none) (fieldMiss lhs (val base) field)))))))
      ((ty/opVariantField base i) (if (some? (nameIndexGet env.fused d)) "" (emitVariantFieldVal lhs d (val base) i)))
      ((ty/opUnbox v) (mt (nameIndexGet env.fused v)
                        ((none) (mt (nameIndexGet env.wants d)
                                  ((some w) (emitEntryUnbox lhs d t v w))
                                  ((none) (emitUnboxInline lhs d t v))))
                        ((some fusedOp) (mt fusedOp
                                          ((ty/opField base field) (emitFusedFieldUnbox lhs d t (val base) field (typedFieldIndex env base field)))
                                          ((ty/opVariantField base i) (emitFusedVariantUnbox lhs d t (val base) i))
                                          (_ (emitUnboxInline lhs d t v))))))
      ((ty/opConstruct _ variant fields) (emitConstruct lhs d variant fields))
      ((ty/opRecord schemaName fields values) (emitRecord lhs d schemaName fields values (optionOr (nameIndexGet env.mod.records schemaName) (list))))
      ((ty/opMakeClosure callee caps) (emitMakeClosure lhs d callee caps))
      ((ty/opEntry name args) (mt (nativeEntry name (listLength args))
                                 ((some b) (emitNativeEntry lhs d b args))
                                 ((none) (if (formatEntryName? name) (emitFormatEntry lhs name args)
                                           (str (fillArray d items)
                                             (mt (ty/builtinEntry name (listLength args))
                                               ((some b) (str lhs "call " (llTy b.result) " @" (builtinSym b) "(" (typedArgs args b.args) ")\n"))
                                               ((none) (tableCall lhs name (listLength args) arr))))))))
      ((ty/opList xs) (emitListLiteral lhs d xs))
      ((ty/opBuiltin name args) (cond
                                    ((and (= name "floatNan") (listEmpty? args))
                                      (emitConst env lhs d t (ty/constFloat (floatNan))))
                                    ((and (= name "floatInf") (listEmpty? args))
                                      (emitConst env lhs d t (ty/constFloat (floatInf))))
                                    ((and (= name "floatNegInf") (listEmpty? args))
                                      (emitConst env lhs d t (ty/constFloat (floatNegInf))))
                                    ((errorBuiltin? name (listLength args)) (emitErrorBuiltin lhs d name args))
                                    ((mathBuiltin? name (listLength args)) (emitMathBuiltin lhs name args))
                                    ((seqBuiltin? name (listLength args)) (emitSeqBuiltin lhs d name args))
                                    ((opsrt/opsBuiltin? name (listLength args)) (opsrt/opsBuiltinCall lhs (val d) name (map val args)))
                                    (else (str (fillArray d items)
                                         (if (rtFormatBuiltin? name) (emitFormatBuiltin d name args arr)
                                           (tableCall lhs name (listLength args) arr))))))
      (_ (str (fillArray d items)
         (mt op
           ((ty/opConst c) (emitConst env lhs d t c))
           ((ty/opCall callee args) (emitCall env lhs d callee args))
           ((ty/opCallClosure c args) (str lhs "call %Val @objrt.call(%Val " (val c) ", i64 " (listLength args) ", " arr ")\n"))
           ((ty/opGlobal g) (str lhs "load %Val, ptr " (globalSym g) "\n"))
           ((ty/opLoadGlobal g) (str lhs "load ptr, ptr " (externGlobalSym g) "\n"))
           ((ty/opBox v) (boxInline lhs d (defType env v) (val v)))
           ((ty/opPrim name args) (emitPrim lhs d name args))
           (_ ""))))))


fn countTarget edges: (List ty/SsaEdge) target: String -> Int64
  (listLength (filter (fn [(e ty/SsaEdge)] -> Bool (= e.target target)) edges))

fn blockParamCount env: FnEnv target: String -> Int64
  (mt (nameIndexGet env.blocks target) ((some b) (listLength b.params)) ((none) 0))

fn splitEdge? env: FnEnv edges: (List ty/SsaEdge) e: ty/SsaEdge -> Bool
  (and (> (blockParamCount env e.target) 0) (> (countTarget edges e.target) 1))

fn edgeBlock from: String k: Int64 -> String
  (str (label from) ".e" k)

fn edgeLabel env: FnEnv from: String edges: (List ty/SsaEdge) k: Int64 -> String
  (mt (listGet edges k)
    ((none) (label from))
    ((some e) (if (splitEdge? env edges e) (edgeBlock from k) (label e.target))))

fn predecessors blocks: (List ty/SsaBlock) -> NameIndex
  (fold (fn [(acc NameIndex) (b ty/SsaBlock)] -> NameIndex
          (pairSecond (fold (fn [(walk (Pair Int64 NameIndex)) (e ty/SsaEdge)] -> (Pair Int64 NameIndex)
                              (pair (+ (pairFirst walk) 1)
                                    (nameIndexSet (pairSecond walk) e.target (cons (pair b (pairFirst walk)) (optionOr (nameIndexGet (pairSecond walk) e.target) (list))))))
                            (pair 0 acc) (ty/termEdges b.term))))
        (nameIndexEmpty) blocks)

fn incoming env: FnEnv target: String index: Int64 -> (List String)
  (fold (fn [(acc (List String)) (p (Pair ty/SsaBlock Int64))] -> (List String)
          (let [(b (pairFirst p)) (k (pairSecond p)) (edges (ty/termEdges b.term))]
            (mt (listGet edges k)
              ((none) acc)
              ((some e) (if (tailCall? env b)
                          acc
                          (cons (str "[ " (val (optionOr (listGet e.args index) "")) ", %" (if (splitEdge? env edges e) (edgeBlock b.label k) (exitLabel env b)) " ]") acc))))))
        (list) (optionOr (nameIndexGet env.preds target) (list)))

fn emitPhis env: FnEnv b: ty/SsaBlock -> String
  (let [(params b.params)]
    (stringJoin (map (fn [(i Int64)] -> String
                        (let [(p (optionOr (listGet params i) (ty/ssaParam "" (ty/tyVal))))
                              (ins (incoming env b.label i))]
                          (if (listEmpty? ins)
                            (str "  " (val p.name) " = freeze " (llTy p.ty) " poison\n")
                            (str "  " (val p.name) " = phi " (llTy p.ty) " " (stringJoin ins ", ") "\n"))))
                      (range 0 (listLength params))) ""))

fn emitTerm env: FnEnv from: String term: ty/SsaTerm -> String
  (let [(edges (ty/termEdges term))
        (to (fn [(k Int64)] -> String (str "%" (edgeLabel env from edges k))))]
    (mt term
      ((ty/termReturn v) (str "  ret " (llTy env.retTy) " " (val v) "\n"))
      ((ty/termJump _) (str "  br label " (to 0) "\n"))
      ((ty/termBranch c _ _)
        (if (= (ty/ssaTyName (defType env c)) "i1")
          (str "  br i1 " (val c) ", label " (to 0) ", label " (to 1) "\n")
          (let [(p (str "%" (label from) ".c")) (lbl (str (label from) ".cond"))]
            (str (valTag p (val c))
                 "  " p ".ok = icmp eq i32 " p ".vtag, 1\n"
                 "  br i1 " p ".ok, label %" lbl ".ok, label %" lbl ".trap\n"
                 (typeTrap p lbl 1)
                 lbl ".ok:\n"
                 (unboxPayload (str "  " p ".bit = ") p "bool" (val c))
                 "  br i1 " p ".bit, label " (to 0) ", label " (to 1) "\n"))))
      ((ty/termSwitch s typeName cases d)
        (let [(n (listLength cases))
              (fallback (mt d ((some e) (if (trapEdge? env e) (str "%" (label from) ".nomatch") (to n))) ((none) (str "%" (label from) ".nomatch"))))
              (arms (stringJoin (map (fn [(k Int64)] -> String
                                        (mt (listGet cases k)
                                          ((none) "")
                                          ((some c) (str "    i64 " (variantTag env typeName c.variant) ", label " (to k) "\n"))))
                                      (range 0 n)) ""))]
          (str (variantTagLookup env from (val s) typeName (map (fn [(c ty/SsaCase)] -> String c.variant) cases))
               "  switch i64 %" (label from) ".tag, label " fallback " [\n" arms "  ]\n")))
      ((ty/termUnreachable) (str "  call void @rterr.match(ptr " (nameSym env.name) ")\n  unreachable\n"))))

fn patternArityCheck env: FnEnv p: String blk: String typeName: String armed: (List String) -> String
  (let [(variants (optionOr (nameIndexGet env.mod.types typeName) (list)))
        (arms (filter (fn [(v ty/SsaVariant)] -> Bool (listContains? armed v.name)) variants))
        (tagOf (fn [(v ty/SsaVariant)] -> Int64 (variantTag env typeName v.name)))
        (chain (fn [(prefix String) (ty String) (start String) (pick (fn [ty/SsaVariant] -> String))] -> String
                 (stringJoin (map (fn [(i Int64)] -> String
                                    (let [(v (optionOr (listGet arms i) (ty/ssaVariant "" 0)))]
                                      (str "  " p "." prefix ".is" i " = icmp eq i64 " p ".tag, " (tagOf v) "\n"
                                           "  " p "." prefix i " = select i1 " p "." prefix ".is" i ", " ty " " (pick v) ", " ty " " (if (= i 0) start (str p "." prefix (- i 1))) "\n")))
                                  (range 0 (listLength arms))) "")))
        (last (str (- (listLength arms) 1)))]
    (if (listEmpty? arms)
      (str "  br i1 " p ".found, label " p ".match, label " p ".miss\n")
      (str "  " p ".np = getelementptr inbounds i8, ptr " p ".obj, i64 12\n"
           "  " p ".n = load i32, ptr " p ".np\n"
           (chain "want" "i32" "-1" (fn [(v ty/SsaVariant)] -> String (str v.arity)))
           "  " p ".armed = icmp sge i32 " p ".want" last ", 0\n"
           "  " p ".differs = icmp ne i32 " p ".want" last ", " p ".n\n"
           "  " p ".badArity = and i1 " p ".armed, " p ".differs\n"
           "  br i1 " p ".badArity, label " p ".arity, label " p ".check\n"
           blk ".arity:\n"
           (chain "pname" "ptr" "null" (fn [(v ty/SsaVariant)] -> String (nameSym v.name)))
           "  call void @objrt.patternArity(ptr " p ".pname" last ", i32 " p ".want" last ", i32 " p ".n)\n"
           "  unreachable\n"
           blk ".check:\n"
           "  br i1 " p ".found, label " p ".match, label " p ".miss\n")))

fn variantTagLookup env: FnEnv from: String s: String typeName: String armed: (List String) -> String
  (let [(p (str "%" (label from)))
        (blk (label from))
        (n (listLength (typeVariants env.mod typeName)))
        (scan (stringJoin (map (fn [(k Int64)] -> String
                                 (str "  " p ".idp" k " = getelementptr inbounds [" n " x i32], ptr " (variantIdsSym typeName) ", i64 0, i64 " k "\n"
                                      "  " p ".id" k " = load i32, ptr " p ".idp" k "\n"
                                      "  " p ".eq" k " = icmp eq i32 " p ".ctor, " p ".id" k "\n"))
                               (range 0 n)) ""))
        (sels (if (= n 0)
                (str "  " p ".tag = add i64 0, -1\n")
                (stringJoin (map (fn [(j Int64)] -> String
                                   (let [(k (- (- n 1) j))]
                                     (str "  " p (if (= k 0) ".tag" (str ".sel" k)) " = select i1 " p ".eq" k ", i64 " k ", i64 " (if (= j 0) "-1" (str p ".sel" (+ k 1))) "\n")))
                                 (range 0 n)) "")))]
    (str (valTag p s)
         "  " p ".isCtor = icmp eq i32 " p ".vtag, 8\n"
         "  br i1 " p ".isCtor, label " p ".variant, label " p ".miss\n"
         blk ".variant:\n"
         (valObj p s)
         "  " p ".ctorp = getelementptr inbounds i8, ptr " p ".obj, i64 8\n"
         "  " p ".ctor = load i32, ptr " p ".ctorp\n"
         "  " p ".ready = load i1, ptr " (variantIdsReadySym typeName) "\n"
         "  br i1 " p ".ready, label " p ".scan, label " p ".resolve\n"
         blk ".resolve:\n"
         "  call void " (variantIdsInitSym typeName) "()\n"
         "  br label " p ".scan\n"
         blk ".scan:\n"
         scan sels
         "  " p ".found = icmp sge i64 " p ".tag, 0\n"
         (patternArityCheck env p blk typeName armed)
         blk ".miss:\n"
         "  " p ".missIsCtor = icmp eq i32 " p ".vtag, 8\n"
         "  br i1 " p ".missIsCtor, label " p ".foreign, label " p ".typeFail\n"
         blk ".foreign:\n"
         "  call void @rterr.matchValue(%Val " s ", ptr " (nameSym env.name) ")\n"
         "  unreachable\n"
         blk ".typeFail:\n"
         "  call void @rterr.type(i32 " p ".vtag, i32 8)\n"
         "  unreachable\n"
         blk ".match:\n"))

fn emitVariantIdsInit menv: ModEnv typeName: String -> String
  (let [(names (typeVariants menv typeName))
        (n (listLength names))]
    (str "define internal void " (variantIdsInitSym typeName) "() {\nbb.entry:\n"
         (stringJoin (map (fn [(k Int64)] -> String
                            (str (internId (str "%kw." k ".aux") (optionOr (listGet names k) ""))
                                 "  %slot." k " = getelementptr inbounds [" n " x i32], ptr " (variantIdsSym typeName) ", i64 0, i64 " k "\n"
                                 "  store i32 %kw." k ".aux, ptr %slot." k "\n"))
                          (range 0 n)) "")
         "  store i1 true, ptr " (variantIdsReadySym typeName) "\n  ret void\n}\n"))

fn trapEdge? env: FnEnv e: ty/SsaEdge -> Bool
  (and (listEmpty? e.args)
       (mt (nameIndexGet env.blocks e.target)
         ((some b) (and (listEmpty? b.instrs) (and (listEmpty? b.params) (mt b.term ((ty/termUnreachable) true) (_ false)))))
         ((none) false)))

fn emitEdgeBlocks env: FnEnv b: ty/SsaBlock -> String
  (let [(from b.label)
        (edges (ty/termEdges b.term))
        (splits (stringJoin (map (fn [(k Int64)] -> String
                                    (mt (listGet edges k)
                                      ((none) "")
                                      ((some e) (if (splitEdge? env edges e)
                                                  (str (edgeBlock from k) ":\n  br label %" (label e.target) "\n")
                                                  ""))))
                                  (range 0 (listLength edges))) ""))
        (nomatch (mt b.term
                   ((ty/termSwitch s _ _ d) (mt d ((some e) (if (trapEdge? env e) (str (label from) ".nomatch:\n  call void @rterr.matchValue(%Val " (val s) ", ptr " (nameSym env.name) ")\n  unreachable\n") "")) ((none) (str (label from) ".nomatch:\n  unreachable\n"))))
                   (_ "")))]
    (str splits nomatch))

fn lastInstr b: ty/SsaBlock -> (Option ty/SsaInstr)
  (listGet b.instrs (- (listLength b.instrs) 1))

fn returnsParam? env: FnEnv target: String fuel: Int64 -> Bool
  (mt (nameIndexGet env.blocks target)
    ((none) false)
    ((some j) (and (listEmpty? j.instrs)
                   (mt (listHead j.params)
                     ((none) false)
                     ((some p) (and (= (listLength j.params) 1)
                                    (mt j.term
                                      ((ty/termReturn v) (= v p.name))
                                      ((ty/termJump e) (and (> fuel 0)
                                                            (and (= e.args (list p.name))
                                                                 (returnsParam? env e.target (- fuel 1)))))
                                      (_ false))))))))

fn tailCall? env: FnEnv b: ty/SsaBlock -> Bool
  (mt (lastInstr b)
    ((none) false)
    ((some ins)
      (mt ins.op
        ((ty/opCall callee _)
          (mt (nameIndexGet env.mod.functions callee)
            ((none) false)
            ((some f) (and (not (stringContains? callee "sysRoute."))
                           (and (= (ty/ssaAbiName f.retTy) (ty/ssaAbiName env.retTy))
                             (mt b.term
                             ((ty/termReturn v) (= v ins.dest))
                             ((ty/termJump e) (and (= e.args (list ins.dest)) (returnsParam? env e.target env.size)))
                             (_ false)))))))
        (_ false))))

fn emitTailCall env: FnEnv ins: ty/SsaInstr -> String
  (mt ins.op
    ((ty/opCall callee args) (str (emitCall env (str "  " (val ins.dest) " = musttail ") ins.dest callee args)
                                  "  ret " (llTy env.retTy) " " (val ins.dest) "\n"))
    (_ (emitInstr env ins)))

fn emitBlock env: FnEnv allocas: String isEntry: Bool frame: NameIndex b: ty/SsaBlock -> String
  (let [(tail (tailCall? env b))
        (instrs b.instrs)
        (n (listLength instrs))
        (body (if tail (listTake instrs (- n 1)) instrs))
        (framed (not (nameIndexEmpty? frame)))
        (emitOne (fn [(ins ty/SsaInstr)] -> String
                   (mt (nameIndexGet frame ins.dest)
                     ((none) (emitInstr env ins))
                     ((some k) (mt ins.op
                                 ((ty/opList xs) (str (rootSlot ins.dest k)
                                                      (emitListLiteralKept (str "  " (val ins.dest) " = ") ins.dest xs (rootSlotPtr ins.dest))
                                                      (rootStore ins.dest)))
                                 (_ (str (emitInstr env ins) (rootSlot ins.dest k) (rootStore ins.dest))))))))]
    (str (label b.label) ":\n"
         (if isEntry allocas "")
         (emitPhis env b)
         (stringJoin (map (fn [(p ty/SsaParam)] -> String (rootKeep frame p.name)) b.params) "")
         (stringJoin (map emitOne body) "")
         (if tail
           (str (if framed (rootPop) "") (mt (lastInstr b) ((some ins) (emitTailCall env ins)) ((none) "")))
           (str (mt b.term ((ty/termReturn _) (if framed (rootPop) "")) (_ ""))
                (emitTerm env b.label b.term) (emitEdgeBlocks env b)))))

fn rootSlotPtr name: String -> String
  (str (val name) ".root")

fn rootSlot name: String k: Int64 -> String
  (str "  " (rootSlotPtr name) " = getelementptr inbounds %Val, ptr %rt.frame, i64 " k "\n")

fn rootStore name: String -> String
  (str "  store %Val " (val name) ", ptr " (rootSlotPtr name) "\n")

fn rootKeep frame: NameIndex name: String -> String
  (mt (nameIndexGet frame name) ((none) "") ((some k) (str (rootSlot name k) (rootStore name))))

fn rootPop -> String
  "  store i64 %rt.prev, ptr @asl_gc_shadow_top\n"

fn shadowTopDecl -> String
  "@asl_gc_shadow_top = external global i64"

fn rootFrameSetup n: Int64 -> String
  (str "  %rt.frame = alloca [" (+ n 1) " x %Val], align 8\n"
       "  %rt.prev = load i64, ptr @asl_gc_shadow_top\n"
       "  %rt.head = insertvalue %Val { i64 0, i64 " n " }, i64 %rt.prev, 0\n"
       "  store %Val %rt.head, ptr %rt.frame\n"
       "  %rt.slots = getelementptr inbounds %Val, ptr %rt.frame, i64 1\n"
       "  store [" n " x %Val] zeroinitializer, ptr %rt.slots\n"
       "  %rt.self = ptrtoint ptr %rt.frame to i64\n"
       "  store i64 %rt.self, ptr @asl_gc_shadow_top\n")

fn heapVal? t: ty/SsaTy -> Bool
  (= (llTy t) "%Val")

fn rootedInstr? env: FnEnv ins: ty/SsaInstr -> Bool
  (and (heapVal? ins.ty)
       (and (none? (nameIndexGet env.fused ins.dest))
            (mt ins.op ((ty/opBox _) false) (_ true))))

fn rootSlots env: FnEnv f: ty/SsaFunction -> (List String)
  (let [(params (map (fn [(p ty/SsaParam)] -> String p.name)
                     (filter (fn [(p ty/SsaParam)] -> Bool (heapVal? p.ty)) (listAppend f.captures f.params))))
        (inBlock (fn [(b ty/SsaBlock)] -> (List String)
                   (let [(instrs b.instrs)
                         (body (if (tailCall? env b) (listTake instrs (- (listLength instrs) 1)) instrs))
                         (phis (filter (fn [(i Int64)] -> Bool
                                         (mt (listGet b.params i)
                                           ((none) false)
                                           ((some p) (and (heapVal? p.ty) (not (listEmpty? (incoming env b.label i)))))))
                                       (range 0 (listLength b.params))))]
                     (listAppend (map (fn [(i Int64)] -> String (mt (listGet b.params i) ((some p) p.name) ((none) ""))) phis)
                                 (map (fn [(ins ty/SsaInstr)] -> String ins.dest) (filter (fn [(ins ty/SsaInstr)] -> Bool (rootedInstr? env ins)) body))))))]
    (listReverse (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (fold (fn [(a (List String)) (n String)] -> (List String) (cons n a)) acc (inBlock b))) (listReverse params) f.blocks)))

fn functionDefs f: ty/SsaFunction -> NameIndex
  (let [(addParams (fn [(acc NameIndex) (ps (List ty/SsaParam))] -> NameIndex
                     (fold (fn [(m NameIndex) (p ty/SsaParam)] -> NameIndex (nameIndexSet m p.name p.ty)) acc ps)))
        (base (addParams (addParams (nameIndexEmpty) f.captures) f.params))]
    (fold (fn [(acc NameIndex) (b ty/SsaBlock)] -> NameIndex
            (fold (fn [(m NameIndex) (ins ty/SsaInstr)] -> NameIndex (nameIndexSet m ins.dest ins.ty))
                  (addParams acc b.params) b.instrs))
          base f.blocks))

fn emitFunctionRooted menv: ModEnv f: ty/SsaFunction rooted: Bool -> String
  (let [(blocks f.blocks)
        (env (FnEnv :mod menv
                    :defs (functionDefs f)
                    :blocks (fold (fn [(acc NameIndex) (b ty/SsaBlock)] -> NameIndex (nameIndexSet acc b.label b)) (nameIndexEmpty) blocks)
                    :order blocks
                    :retTy f.retTy
                    :name f.name
                    :fused (fusedMap f)
                    :records (recordMap f)
                    :wants (entryUnboxes f)
                    :preds (predecessors blocks)
                    :size (listLength blocks)))
        (allocas (stringJoin (map (fn [(b ty/SsaBlock)] -> String (stringJoin (map allocaFor b.instrs) "")) blocks) ""))
        (allParams (listAppend f.captures f.params))
        (params (stringJoin (map (fn [(p ty/SsaParam)] -> String (str (llTy p.ty) " " (val p.name))) (registerParams allParams)) ", "))
        (slotNames (if rooted (rootSlots env f) (list)))
        (frame (pairSecond (fold (fn [(acc (Pair Int64 NameIndex)) (name String)] -> (Pair Int64 NameIndex) (pair (+ (pairFirst acc) 1) (nameIndexSet (pairSecond acc) name (pairFirst acc))))
                                 (pair 1 (nameIndexEmpty)) slotNames)))
        (frameText (if (listEmpty? slotNames) ""
                     (str (rootFrameSetup (listLength slotNames))
                          (stringJoin (map (fn [(p ty/SsaParam)] -> String (rootKeep frame p.name)) allParams) ""))))
        (entryText (str allocas (spillLoads allParams) frameText))
        (body (mt (listHead blocks)
                ((none) "")
                ((some first) (str (emitBlock env entryText true frame first)
                                   (stringJoin (map (fn [(b ty/SsaBlock)] -> String (emitBlock env entryText false frame b)) (optionOr (listTail blocks) (list))) "")))))]
    (str "define tailcc " (llTy f.retTy) " " (fnSym f.name) "(" params ") {\n" body "}\n"))

fn listBuilderNames -> (List String)
  (list "prelude.map" "prelude.filter")

fn listBuilder? f: ty/SsaFunction -> Bool
  (and (listContains? (listBuilderNames) f.name)
       (= (map (fn [(p ty/SsaParam)] -> String (ty/ssaTyName p.ty)) (listAppend f.captures f.params)) (list "val" "val"))
       (= (ty/ssaTyName f.retTy) "val")
       (= (map (fn [(p ty/SsaParam)] -> String p.name) f.params) (list "f" "xs")))

fn listBuilderText f: ty/SsaFunction -> String
  (let [(keepsAll (= f.name "prelude.map"))
        (call (str "  %argp = getelementptr [1 x %Val], ptr %argv, i64 0, i64 0\n"
                   "  store %Val %x, ptr %argp\n"
                   "  %y = call %Val @objrt.call(%Val %f, i64 1, ptr %argv)\n"))
        (link (str "link:\n"
                   "  %cell = call ptr @asl_alloc_cons()\n"
                   "  %ccar = getelementptr inbounds i8, ptr %cell, i64 8\n"
                   "  store %Val " (if keepsAll "%y" "%x") ", ptr %ccar\n"
                   "  %ccdr = getelementptr inbounds i8, ptr %cell, i64 24\n"
                   "  store %Val { i64 6, i64 0 }, ptr %ccdr\n"
                   "  %cellw = ptrtoint ptr %cell to i64\n"
                   "  %cellv = insertvalue %Val { i64 6, i64 0 }, i64 %cellw, 1\n"
                   "  %first = icmp eq ptr %tailp, null\n"
                   "  br i1 %first, label %linked, label %append\n"
                   "append:\n"
                   "  store %Val %cellv, ptr %tailp\n"
                   "  br label %linked\n"
                   "linked:\n"
                   "  %head1 = select i1 %first, %Val %cellv, %Val %head\n"
                   "  br label %loop\n"))
        (test (if keepsAll
                "  br label %link\n"
                (str "  %y.vtagw = extractvalue %Val %y, 0\n"
                     "  %y.vtag = trunc i64 %y.vtagw to i32\n"
                     "  %y.ok = icmp eq i32 %y.vtag, 1\n"
                     "  br i1 %y.ok, label %cond.ok, label %cond.trap\n"
                     (typeTrap "%y" "cond" 1)
                     "cond.ok:\n"
                     (unboxPayload "  %keep = " "%y" "bool" "%y")
                     "  br i1 %keep, label %link, label %skip\n"
                     "skip:\n"
                     "  br label %loop\n")))]
    (str "define tailcc %Val " (fnSym f.name) "(%Val %f, %Val %xs) {\n"
         "entry:\n"
         "  %argv = alloca [1 x %Val]\n"
         "  br label %loop\n"
         "loop:\n"
         "  %cur = phi %Val [ %xs, %entry ], [ %next, %linked ]" (if keepsAll "" ", [ %next, %skip ]") "\n"
         "  %head = phi %Val [ { i64 6, i64 0 }, %entry ], [ %head1, %linked ]" (if keepsAll "" ", [ %head, %skip ]") "\n"
         "  %tailp = phi ptr [ null, %entry ], [ %ccdr, %linked ]" (if keepsAll "" ", [ %tailp, %skip ]") "\n"
         "  %cur.vtagw = extractvalue %Val %cur, 0\n"
         "  %cur.vtag = trunc i64 %cur.vtagw to i32\n"
         "  %isList = icmp eq i32 %cur.vtag, 6\n"
         "  br i1 %isList, label %chk, label %bad\n"
         "bad:\n"
         "  call void @mathrt.want(ptr @.listrt.who.listEmpty, i32 6, i32 %cur.vtag)\n"
         "  unreachable\n"
         "chk:\n"
         "  %objw = extractvalue %Val %cur, 1\n"
         "  %obj = inttoptr i64 %objw to ptr\n"
         "  %empty = icmp eq ptr %obj, null\n"
         "  br i1 %empty, label %done, label %step\n"
         "step:\n"
         "  %carp = getelementptr inbounds i8, ptr %obj, i64 8\n"
         "  %x = load %Val, ptr %carp\n"
         "  %cdrp = getelementptr inbounds i8, ptr %obj, i64 24\n"
         "  %next = load %Val, ptr %cdrp\n"
         call
         test
         link
         "done:\n"
         "  ret %Val %head\n"
         "}\n"))

fn emitCaptureInline i: Int64 -> String
  (let [(p (str "%cap" i)) (lbl (str "cap" i)) (off (+ 24 (* i 16)))]
    (str "  " p ".tagw = extractvalue %Val %env, 0\n"
         "  " p ".tag = trunc i64 " p ".tagw to i32\n"
         "  " p ".isFn = icmp eq i32 " p ".tag, 9\n"
         "  br i1 " p ".isFn, label %" lbl ".fn, label %" lbl ".slow\n"
         lbl ".fn:\n"
         "  " p ".objw = extractvalue %Val %env, 1\n"
         "  " p ".obj = inttoptr i64 " p ".objw to ptr\n"
         "  " p ".np = getelementptr inbounds i8, ptr " p ".obj, i64 16\n"
         "  " p ".n = load i32, ptr " p ".np\n"
         "  " p ".n64 = sext i32 " p ".n to i64\n"
         "  " p ".inRange = icmp slt i64 " i ", " p ".n64\n"
         "  br i1 " p ".inRange, label %" lbl ".fast, label %" lbl ".slow\n"
         lbl ".fast:\n"
         "  " p ".fp = getelementptr inbounds i8, ptr " p ".obj, i64 " off "\n"
         "  " p ".fastval = load %Val, ptr " p ".fp\n"
         "  br label %" lbl ".join\n"
         lbl ".slow:\n"
         "  " p ".slowval = call %Val @objrt.capture(%Val %env, i64 " i ")\n"
         "  br label %" lbl ".join\n"
         lbl ".join:\n"
         "  " p " = phi %Val [ " p ".fastval, %" lbl ".fast ], [ " p ".slowval, %" lbl ".slow ]\n"))

fn emitTrampoline f: ty/SsaFunction -> String
  (let [(caps (listLength f.captures))
        (n (listLength f.params))
        (capLines (stringJoin (map emitCaptureInline (range 0 caps)) ""))
        (argLines (stringJoin (map (fn [(i Int64)] -> String
                                      (str "  %arg" i ".slot = getelementptr %Val, ptr %argv, i64 " i "\n"
                                           "  %arg" i " = load %Val, ptr %arg" i ".slot\n"))
                                    (range 0 n)) ""))
        (callArgs (listAppend (map (fn [(i Int64)] -> String (str "cap" i)) (range 0 caps))
                              (map (fn [(i Int64)] -> String (str "arg" i)) (range 0 n))))]
    (str "define internal %Val " (codeSym f.name) "(%Val %env, i64 %argc, ptr %argv) {\nbb.entry:\n"
         capLines argLines
         (tailCall "  %result = " "result" f.retTy f.name callArgs (signatureTypes f))
         "  ret %Val %result\n}\n"))


fn allOps m: ty/SsaModule -> (List ty/SsaOp)
  (listReverse (fold (fn [(acc (List ty/SsaOp)) (f ty/SsaFunction)] -> (List ty/SsaOp)
                       (fold (fn [(a (List ty/SsaOp)) (ins ty/SsaInstr)] -> (List ty/SsaOp) (cons ins.op a)) acc (allInstrs f)))
                     (list) m.functions))

fn opNames op: ty/SsaOp -> (List String)
  (mt op
    ((ty/opConst c) (mt c ((ty/constKeyword n) (list n)) ((ty/constSymbol n) (list n)) (_ (list))))
    ((ty/opBuiltin name args) (cond ((errorBuiltin? name (listLength args)) (list))
                                    ((mathBuiltin? name (listLength args)) (if (= name "float64ToInt64") (list "some" "none") (list)))
                                    ((partialCtor? name (listLength args)) (list "partial"))
                                    ((seqBuiltin? name (listLength args)) (list))
                                    ((opsrt/opsBuiltin? name (listLength args)) (list))
                                    (else (list name))))
    ((ty/opConstruct _ variant _) (list variant))
    ((ty/opRecord schemaName _ _) (list schemaName))
    ((ty/opField _ field) (list field))
    ((ty/opEntry name _) (if (optionEntry? name) (list "some" "none") (list)))
    (_ (list)))

fn distinct xs: (List String) -> (List String)
  (let [(indexed (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List (Pair String Int64)))) (x String)] -> (Pair Int64 (List (Pair String Int64)))
                                                  (pair (+ (pairFirst acc) 1) (cons (pair x (pairFirst acc)) (pairSecond acc))))
                                                (pair 0 (list)) xs))))
        (byName (listSortBy (fn [(p (Pair String Int64))] -> String (pairFirst p)) indexed))
        (firsts (fold (fn [(acc (List (Pair String Int64))) (p (Pair String Int64))] -> (List (Pair String Int64))
                        (mt (listHead acc)
                          ((some q) (if (= (pairFirst q) (pairFirst p)) acc (cons p acc)))
                          ((none) (cons p acc))))
                      (list) byName))]
    (map (fn [(p (Pair String Int64))] -> String (pairFirst p))
         (listSortBy (fn [(p (Pair String Int64))] -> Int64 (pairSecond p)) firsts)))

fn gather f: (fn [ty/SsaOp] -> (List String)) ops: (List ty/SsaOp) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (op ty/SsaOp)] -> (List String)
                       (fold (fn [(a (List String)) (n String)] -> (List String) (cons n a)) acc (f op)))
                     (list) ops))

fn switchTypes m: ty/SsaModule -> (List String)
  (distinct (listReverse (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                    (fold (fn [(a (List String)) (b ty/SsaBlock)] -> (List String)
                            (mt b.term ((ty/termSwitch _ typeName _ _) (cons typeName a)) (_ a)))
                          acc f.blocks))
                  (list) m.functions)))

fn typeVariants menv: ModEnv typeName: String -> (List String)
  (map (fn [(v ty/SsaVariant)] -> String v.name) (optionOr (nameIndexGet menv.types typeName) (list)))

fn moduleNames m: ty/SsaModule -> (List String)
  (let [(menv (moduleEnv m))]
    (distinct (listAppend
                (listAppend
                  (gather opNames (allOps m))
                  (fold (fn [(acc (List String)) (r ty/SsaRecordDecl)] -> (List String) (listAppend acc (cons r.name r.fields))) (list) m.records))
                (listAppend
                  (fold (fn [(acc (List String)) (t String)] -> (List String) (listAppend acc (typeVariants menv t))) (list) (switchTypes m))
                  (trappingFunctions m)))))

fn hasStaticFieldRead? f: ty/SsaFunction -> Bool
  (let [(recs (recordMap f)) (fused (fusedMap f))]
    (not (listEmpty? (filter (fn [(ins ty/SsaInstr)] -> Bool
                                (mt ins.op ((ty/opField base field) (and (not (some? (nameIndexGet fused ins.dest))) (some? (fieldStaticIndexFor recs base field)))) (_ false)))
                              (allInstrs f)))))

fn trappingFunctions m: ty/SsaModule -> (List String)
  (map (fn [(f ty/SsaFunction)] -> String f.name)
       (filter (fn [(f ty/SsaFunction)] -> Bool
                 (or (not (listEmpty? (filter (fn [(b ty/SsaBlock)] -> Bool
                                                (mt b.term
                                                  ((ty/termUnreachable) true)
                                                  ((ty/termSwitch _ _ _ _) true)
                                                  (_ false))) f.blocks)))
                     (hasStaticFieldRead? f)))
               m.functions))

fn closureTargets m: ty/SsaModule -> (List String)
  (distinct (gather (fn [(op ty/SsaOp)] -> (List String) (mt op ((ty/opMakeClosure callee _) (list callee)) (_ (list)))) (allOps m)))

fn optionEntry? name: String -> Bool
  (listContains? (list "listHead" "listTail" "stringSlice") name)

fn constructedVariants m: ty/SsaModule -> (List String)
  (distinct (gather (fn [(op ty/SsaOp)] -> (List String)
                      (mt op
                        ((ty/opConstruct _ variant _) (list variant))
                        ((ty/opEntry name _) (if (optionEntry? name) (list "some" "none") (list)))
                        ((ty/opBuiltin name args) (cond ((and (= name "float64ToInt64") (mathBuiltin? name (listLength args))) (list "some" "none"))
                                                        ((partialCtor? name (listLength args)) (list "partial"))
                                                        (else (list))))
                        (_ (list))))
                    (allOps m)))

fn constructedSchemas m: ty/SsaModule -> (List String)
  (distinct (gather (fn [(op ty/SsaOp)] -> (List String) (mt op ((ty/opRecord s _ _) (list s)) (_ (list)))) (allOps m)))

fn loadGlobalNames m: ty/SsaModule -> (List String)
  (distinct (gather (fn [(op ty/SsaOp)] -> (List String) (mt op ((ty/opLoadGlobal name) (list name)) (_ (list)))) (allOps m)))

fn recordSchemaFields m: ty/SsaModule schema: String -> (List String)
  (mt (listHead (filter (fn [(r ty/SsaRecordDecl)] -> Bool (= r.name schema)) m.records))
    ((some r) r.fields)
    ((none) (list)))

fn idCellNames m: ty/SsaModule -> (List String)
  (distinct (gather (fn [(op ty/SsaOp)] -> (List String)
                      (mt op
                        ((ty/opConst c) (mt c ((ty/constKeyword n) (list n)) (_ (list))))
                        ((ty/opField _ field) (list field))
                        (_ (list))))
                    (allOps m)))

fn valStringIndices m: ty/SsaModule -> (List Int64)
  (listReverse (pairSecond (fold (fn [(acc (Pair NameIndex (List Int64))) (f ty/SsaFunction)] -> (Pair NameIndex (List Int64))
          (fold (fn [(a (Pair NameIndex (List Int64))) (ins ty/SsaInstr)] -> (Pair NameIndex (List Int64))
                  (mt ins.op
                    ((ty/opConst c) (mt c
                                      ((ty/constStr i) (if (or (= (ty/ssaTyName ins.ty) "ptr") (nameIndexHas? (pairFirst a) (stringFromInt64 i))) a (pair (nameIndexSet (pairFirst a) (stringFromInt64 i) true) (cons i (pairSecond a)))))
                                      (_ a)))
                    (_ a)))
                acc (allInstrs f)))
        (pair (nameIndexEmpty) (list)) m.functions)))

fn protoNames m: ty/SsaModule -> (List String)
  (let [(functions (moduleEnv m).functions)]
    (distinct (map (fn [(t String)] -> String (protoNameIn functions t)) (closureTargets m))))

fn emitProto menv: ModEnv callee: String wasm: Bool -> String
  (let [(name (protoNameSym (protoNameIn menv.functions callee)))
        (arity (calleeArity menv callee))]
    (if wasm
      (str (protoSym callee) " = private unnamed_addr constant { ptr, i32, ptr, i32, i32, i32, ptr, i32, i32, i32, ptr, i32, i32, i32, ptr, i32 } "
           "{ ptr " name ", i32 0, ptr @protoFile.compiled, i32 0, i32 " arity ", i32 0, ptr null, i32 0, i32 0, i32 0, ptr null, i32 0, i32 0, i32 0, ptr " (codeSym callee) ", i32 0 }\n")
      (str (protoSym callee) " = private unnamed_addr constant { ptr, ptr, i32, i32, ptr, i32, i32, ptr, i32, i32, ptr } "
           "{ ptr " name ", ptr @protoFile.compiled, i32 " arity ", i32 0, ptr null, i32 0, i32 0, ptr null, i32 0, i32 0, ptr " (codeSym callee) " }\n")))

fn byteArray bytes: String n: Int64 -> String
  (str "[" (+ n 1) " x i8] c\"" bytes "\x5c00\"")

fn ptrTable sym: String names: (List String) -> String
  (if (listEmpty? names)
    (str sym " = private unnamed_addr constant [0 x ptr] zeroinitializer\n")
    (str sym " = private unnamed_addr constant [" (listLength names) " x ptr] [" (stringJoin (map (fn [(x String)] -> String (str "ptr " (nameSym x))) names) ", ") "]\n"))

fn emitConstants m: ty/SsaModule wasm: Bool -> String
  (let [(menv (moduleEnv m))
        (strings m.strings)
        (strLines (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List String))) (s String)] -> (Pair Int64 (List String))
                                             (pair (+ (pairFirst acc) 1) (cons (str "@str." (pairFirst acc) " = private unnamed_addr constant " (byteArray (llvmBytes s) (stringLength s)) "\n") (pairSecond acc))))
                                           (pair 0 (list)) strings))))
        (nameLines (map (fn [(n String)] -> String
                          (str (nameSym n) " = private unnamed_addr constant [" (+ (stringLength n) 1) " x i8] c\"" (llvmBytes n) "\x5c00\"\n"))
                        (moduleNames m)))
        (keyLines (map (fn [(t String)] -> String (ptrTable (variantsSym t) (typeVariants menv t))) (switchTypes m)))
        (idLines (map (fn [(t String)] -> String
                        (str (variantIdsSym t) " = internal global [" (listLength (typeVariants menv t)) " x i32] zeroinitializer\n"
                             (variantIdsReadySym t) " = internal global i1 false\n"))
                      (switchTypes m)))
        (fieldIdLines (map (fn [(fld String)] -> String
                             (str (fieldIdSym fld) " = internal global i32 0\n"
                                  (fieldIdReadySym fld) " = internal global i1 false\n"))
                           (fieldIdNames m)))
        (ctorIdLines (map (fn [(v String)] -> String
                            (str (ctorIdSym v) " = internal global i32 0\n"
                                 (ctorIdReadySym v) " = internal global i1 false\n"))
                          (constructedVariants m)))
        (schemaIdLines (map (fn [(s String)] -> String
                              (str (schemaIdSym s) " = internal global i32 0\n"
                                   (schemaIdReadySym s) " = internal global i1 false\n"
                                   (keyIdsSym s) " = internal global [" (listLength (recordSchemaFields m s)) " x i32] zeroinitializer\n"))
                            (constructedSchemas m)))
        (protoLines (if (listEmpty? (closureTargets m))
                      (list)
                      (listAppend (cons "@protoFile.compiled = private unnamed_addr constant [11 x i8] c\"<compiled>\x5c00\"\n"
                                        (map (fn [(n String)] -> String
                                               (str (protoNameSym n) " = private unnamed_addr constant [" (+ (stringLength n) 1) " x i8] c\"" (llvmBytes n) "\x5c00\"\n"))
                                             (protoNames m)))
                                  (map (fn [(t String)] -> String (emitProto menv t wasm)) (closureTargets m)))))
        (cellLines (listAppend (map (fn [(n String)] -> String (str (nameIdCellSym n) " = internal global i32 -1\n")) (idCellNames m))
                               (map (fn [(i Int64)] -> String (str (strCellSym i) " = internal global %Val zeroinitializer\n")) (valStringIndices m))))
        (globalLines (map (fn [(g ty/SsaGlobal)] -> String
                            (if (sharedGlobal? g)
                              (str (globalSym g.name) " = weak global %Val zeroinitializer\n" (globalReadySym g.name) " = weak global i1 false\n")
                              (str (globalSym g.name) " = internal global %Val zeroinitializer\n")))
                          m.globals))]
    (stringJoin (listAppend (listAppend strLines nameLines)
                             (listAppend (listAppend keyLines (listAppend idLines fieldIdLines))
                                         (listAppend (listAppend ctorIdLines schemaIdLines) (listAppend protoLines (listAppend cellLines globalLines))))) ""))

fn emitInit m: ty/SsaModule -> String
  (let [(globals m.globals)]
    (if (listEmpty? globals)
      ""
      (str "define void " (initSym m.name) "() {\nbb.entry:\n"
           (stringJoin (map (fn [(g ty/SsaGlobal)] -> String (if (sharedGlobal? g) "" (str "  call void @asl_rt_global_root(ptr " (globalSym g.name) ")\n"))) globals) "")
           (stringJoin (map (fn [(i Int64)] -> String
                               (mt (listGet globals i)
                                 ((none) "")
                                 ((some g) (if (sharedGlobal? g) (emitSharedInit i g)
                                             (str "  %g." i " = call tailcc %Val " (fnSym g.init) "()\n  store %Val %g." i ", ptr " (globalSym g.name) "\n")))))
                             (range 0 (listLength globals))) "")
           "  ret void\n}\n")))

fn emitSharedInit i: Int64 g: ty/SsaGlobal -> String
  (let [(ready (globalReadySym g.name)) (sym (globalSym g.name)) (lbl (str "bb.global." i))]
    (str "  %ready." i " = load i1, ptr " ready "\n"
         "  br i1 %ready." i ", label %" lbl ".done, label %" lbl ".init\n"
         lbl ".init:\n"
         "  store i1 true, ptr " ready "\n"
         "  call void @asl_rt_global_root(ptr " sym ")\n"
         "  %g." i " = call tailcc %Val " (fnSym g.init) "()\n"
         "  store %Val %g." i ", ptr " sym "\n"
         "  br label %" lbl ".done\n"
         lbl ".done:\n"))

fn moduleEnv m: ty/SsaModule -> ModEnv
  (ModEnv :name m.name
          :functions (fold (fn [(acc NameIndex) (f ty/SsaFunction)] -> NameIndex (nameIndexSet acc f.name f)) (nameIndexEmpty) m.functions)
          :externs (fold (fn [(acc NameIndex) (e ty/SsaExtern)] -> NameIndex (nameIndexSet acc e.name e)) (nameIndexEmpty) m.externs)
          :types (fold (fn [(acc NameIndex) (d ty/SsaTypeDecl)] -> NameIndex (nameIndexSet acc d.name d.variants)) (nameIndexEmpty) m.types)
          :strings (pairSecond (fold (fn [(acc (Pair Int64 NameIndex)) (s String)] -> (Pair Int64 NameIndex) (pair (+ (pairFirst acc) 1) (nameIndexSet (pairSecond acc) (stringFromInt64 (pairFirst acc)) s))) (pair 0 (nameIndexEmpty)) m.strings))
          :records (fold (fn [(acc NameIndex) (r ty/SsaRecordDecl)] -> NameIndex (nameIndexSet acc r.name r.fields)) (nameIndexEmpty) m.records))

fn rtFormatBuiltin? name: String -> Bool
  (or (= name "str") (= name "print") (= name "println") (= name "eprintln")
      (= name "stringFromFloat64") (= name "stringToFloat64"))

fn formatEntryName? name: String -> Bool
  (listContains? (list "stringFromFloat64" "stringToFloat64" "stringFromInt64") name)

fn emitFormatEntry lhs: String name: String args: (List String) -> String
  (let [(a0 (val (optionOr (listGet args 0) "")))]
    (cond ((= name "stringFromFloat64") (str lhs "call %Val @asl_rt_format_float(double " a0 ")\n"))
          ((= name "stringFromInt64") (str lhs "call %Val @asl_rt_format_i64(i64 " a0 ")\n"))
          (else (str lhs "call %Val @asl_rt_format_parse_value(%Val " a0 ")\n"))))

fn formatOp? op: ty/SsaOp -> Bool
  (mt op
    ((ty/opBuiltin name _) (rtFormatBuiltin? name))
    ((ty/opEntry name _) (formatEntryName? name))
    (_ false))

fn formatFloatCall dest: String arg: String -> String
  (let [(p (val dest)) (v (val arg))]
    (str "  " p " = call %Val @asl_rt_format_float_value(%Val " v ")\n"))

fn formatParseCall dest: String arg: String -> String
  (str "  " (val dest) " = call %Val @asl_rt_format_parse_value(%Val " (val arg) ")\n")

fn formatManyCall dest: String arr: String count: Int64 -> String
  (str "  " (val dest) " = call %Val @asl_rt_format_many(" arr ", i64 " count ", i32 0)\n")

fn formatOutputCall dest: String name: String arr: String count: Int64 -> String
  (let [(p (val dest))
        (mode (cond ((= name "print") 1) ((= name "println") 2) (else 3)))
        (fd (if (= name "eprintln") 2 1))]
    (str "  " p ".format.text = call %Val @asl_rt_format_many(" arr ", i64 " count ", i32 " mode ")\n"
         "  call void @asl_rt_format_write(%Val " p ".format.text, i32 " fd ")\n"
         "  " p " = insertvalue %Val { i64 0, i64 0 }, i64 0, 1\n"))

fn emitFormatBuiltin dest: String name: String args: (List String) arr: String -> String
  (cond
    ((= name "stringFromFloat64") (formatFloatCall dest (optionOr (listGet args 0) "")))
    ((= name "stringToFloat64") (formatParseCall dest (optionOr (listGet args 0) "")))
    ((= name "str") (formatManyCall dest arr (listLength args)))
    (else (formatOutputCall dest name arr (listLength args))))

fn errorBuiltin? name: String n: Int64 -> Bool
  (or (and (= name "trap") (= n 2))
      (and (or (= name "assert") (= name "refute")) (and (>= n 1) (<= n 2))))

fn emitErrorBuiltin lhs: String dest: String name: String args: (List String) -> String
  (let [(a0 (val (optionOr (listGet args 0) "")))
        (message (mt (listGet args 1) ((some m) (val m)) ((none) "zeroinitializer")))]
    (if (= name "trap")
      (str lhs "call %Val @rterr.trap(%Val " a0 ", %Val " message ")\n")
      (str "  call void @rterr." name "(%Val " a0 ", %Val " message ")\n"
           lhs "insertvalue %Val { i64 0, i64 0 }, i64 0, 1\n")))

fn mathBuiltin? name: String n: Int64 -> Bool
  (or (and (= n 1) (or (= name "abs") (or (= name "int64ToFloat64") (or (= name "float64ToInt64") (= name "~")))))
      (or (and (= n 2) (or (= name "min") (or (= name "max") (or (= name "<<") (or (= name ">>") (or (= name "&") (or (= name "|") (= name "^"))))))))
          (and (= n 3) (= name "clamp"))))

fn mathSym name: String -> String
  (cond ((= name "<<") "@mathrt.shiftLeft")
        ((= name ">>") "@mathrt.shiftRight")
        ((= name "&") "@mathrt.bitAnd") ((= name "|") "@mathrt.bitOr") ((= name "^") "@mathrt.bitXor") ((= name "~") "@mathrt.bitNot")
        (else (str "@mathrt." name)))

fn emitMathBuiltin lhs: String name: String args: (List String) -> String
  (str lhs "call %Val " (mathSym name) "(" (stringJoin (map (fn [(a String)] -> String (str "%Val " (val a))) args) ", ") ")\n")

fn mathText sym: String text: String -> String
  (str sym " = private unnamed_addr constant [" (+ (stringLength text) 1) " x i8] c\"" text "\\00\"")

fn mathConstants -> (List (Pair String String))
  (map (fn [(p (Pair String String))] -> (Pair String String) (pair (pairFirst p) (mathText (pairFirst p) (pairSecond p))))
       (list (pair "@.mathrt.who.abs" "abs") (pair "@.mathrt.who.min" "min") (pair "@.mathrt.who.max" "max") (pair "@.mathrt.who.clamp" "clamp")
             (pair "@.mathrt.who.int64ToFloat64" "int64ToFloat64") (pair "@.mathrt.who.float64ToInt64" "float64ToInt64")
             (pair "@.mathrt.who.shiftLeft" "<<") (pair "@.mathrt.who.shiftRight" ">>")
             (pair "@.mathrt.who.bitAnd" "&") (pair "@.mathrt.who.bitOr" "|") (pair "@.mathrt.who.bitXor" "^") (pair "@.mathrt.who.bitNot" "~")
             (pair "@.mathrt.want" "%s expects %s, got %s") (pair "@.mathrt.pair" "%s expects two Int or two Float, got %s and %s")
             (pair "@.mathrt.clampRange" "clamp: lo <= hi required, got lo=%f hi=%f") (pair "@.mathrt.absMin" "abs of INT64_MIN")))

fn mathTagOf p: String v: String -> String
  (str "  " p ".tagw = extractvalue %Val " v ", 0\n  " p ".tag = trunc i64 " p ".tagw to i32\n  " p ".bits = extractvalue %Val " v ", 1\n")

fn mathWant name: String who: String want: Int64 next: String -> String
  (str (mathTagOf (str "%" name) (str "%" name))
       "  %" name ".ok = icmp eq i32 %" name ".tag, " want "\n"
       "  br i1 %" name ".ok, label %" next ", label %" name ".bad\n"
       name ".bad:\n"
       "  call void @mathrt.want(ptr @.mathrt.who." who ", i32 " want ", i32 %" name ".tag)\n"
       "  unreachable\n")

fn mathFunctions -> (List (Pair String String))
  (list
    (pair "@mathrt.floorModFix"
      (stringJoin (list
        "define internal i64 @mathrt.floorModFix(i64 %r, i64 %b) noinline cold {"
        "entry:"
        "  %rnz = icmp ne i64 %r, 0"
        "  %rneg = icmp slt i64 %r, 0"
        "  %bneg = icmp slt i64 %b, 0"
        "  %diff = xor i1 %rneg, %bneg"
        "  %up = and i1 %rnz, %diff"
        "  %shifted = add i64 %r, %b"
        "  %fixed = select i1 %up, i64 %shifted, i64 %r"
        "  ret i64 %fixed"
        "}") "\n"))
    (pair "@mathrt.floorDivFix"
      (stringJoin (list
        "define internal i64 @mathrt.floorDivFix(i64 %q, i64 %r, i64 %b) noinline cold {"
        "entry:"
        "  %rnz = icmp ne i64 %r, 0"
        "  %rneg = icmp slt i64 %r, 0"
        "  %bneg = icmp slt i64 %b, 0"
        "  %diff = xor i1 %rneg, %bneg"
        "  %down = and i1 %rnz, %diff"
        "  %step = zext i1 %down to i64"
        "  %fixed = sub i64 %q, %step"
        "  ret i64 %fixed"
        "}") "\n"))
    (pair "@mathrt.want"
      (stringJoin (list
        "define internal void @mathrt.want(ptr %who, i32 %want, i32 %got) noreturn {"
        "entry:"
        "  %buf = alloca [4096 x i8]"
        "  store i8 0, ptr %buf"
        "  %wantName = call ptr @rterr.tagName(i32 %want)"
        "  %gotName = call ptr @rterr.tagName(i32 %got)"
        "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.mathrt.want, ptr %who, ptr %wantName, ptr %gotName)"
        "  %len = call i64 @strlen(ptr %buf)"
        "  call void @rterr.raise(ptr @.rterr.c.ERR_TYPE, ptr %buf, i64 %len)"
        "  unreachable"
        "}") "\n"))
    (pair "@mathrt.pair"
      (stringJoin (list
        "define internal void @mathrt.pair(ptr %who, i32 %a, i32 %b) noreturn {"
        "entry:"
        "  %buf = alloca [4096 x i8]"
        "  store i8 0, ptr %buf"
        "  %aName = call ptr @rterr.tagName(i32 %a)"
        "  %bName = call ptr @rterr.tagName(i32 %b)"
        "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.mathrt.pair, ptr %who, ptr %aName, ptr %bName)"
        "  %len = call i64 @strlen(ptr %buf)"
        "  call void @rterr.raise(ptr @.rterr.c.ERR_TYPE, ptr %buf, i64 %len)"
        "  unreachable"
        "}") "\n"))
    (pair "@mathrt.abs"
      (str "define internal %Val @mathrt.abs(%Val %v) {\nentry:\n"
           (mathTagOf "%v" "%v")
           "  %v.isInt = icmp eq i32 %v.tag, 2\n"
           "  br i1 %v.isInt, label %int, label %notInt\n"
           "int:\n"
           "  %isMin = icmp eq i64 %v.bits, -9223372036854775808\n"
           "  br i1 %isMin, label %intMin, label %intOk\n"
           "intMin:\n"
           "  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.mathrt.absMin, i64 16)\n"
           "  unreachable\n"
           "intOk:\n"
           "  %negated = sub i64 0, %v.bits\n"
           "  %isNeg = icmp slt i64 %v.bits, 0\n"
           "  %magnitude = select i1 %isNeg, i64 %negated, i64 %v.bits\n"
           "  %intVal = insertvalue %Val { i64 2, i64 0 }, i64 %magnitude, 1\n"
           "  ret %Val %intVal\n"
           "notInt:\n"
           "  %v.isFloat = icmp eq i32 %v.tag, 3\n"
           "  br i1 %v.isFloat, label %float, label %bad\n"
           "float:\n"
           "  %cleared = and i64 %v.bits, 9223372036854775807\n"
           "  %floatVal = insertvalue %Val { i64 3, i64 0 }, i64 %cleared, 1\n"
           "  ret %Val %floatVal\n"
           "bad:\n"
           "  call void @mathrt.want(ptr @.mathrt.who.abs, i32 3, i32 %v.tag)\n"
           "  unreachable\n}"))
    (pair "@mathrt.minmax"
      (stringJoin (list
        "define internal %Val @mathrt.minmax(%Val %a, %Val %b, i1 %isMax, ptr %who) {"
        "entry:"
        "  %a.tagw = extractvalue %Val %a, 0"
        "  %a.tag = trunc i64 %a.tagw to i32"
        "  %b.tagw = extractvalue %Val %b, 0"
        "  %b.tag = trunc i64 %b.tagw to i32"
        "  %same = icmp eq i32 %a.tag, %b.tag"
        "  %isInt = icmp eq i32 %a.tag, 2"
        "  %isFloat = icmp eq i32 %a.tag, 3"
        "  %numeric = or i1 %isInt, %isFloat"
        "  %ok = and i1 %same, %numeric"
        "  br i1 %ok, label %compare, label %bad"
        "bad:"
        "  call void @mathrt.pair(ptr %who, i32 %a.tag, i32 %b.tag)"
        "  unreachable"
        "compare:"
        "  %a.bits = extractvalue %Val %a, 1"
        "  %b.bits = extractvalue %Val %b, 1"
        "  br i1 %isInt, label %int, label %float"
        "int:"
        "  %intGt = icmp sgt i64 %a.bits, %b.bits"
        "  br label %pick"
        "float:"
        "  %a.f = bitcast i64 %a.bits to double"
        "  %b.f = bitcast i64 %b.bits to double"
        "  %floatGt = fcmp ogt double %a.f, %b.f"
        "  br label %pick"
        "pick:"
        "  %gt = phi i1 [ %intGt, %int ], [ %floatGt, %float ]"
        "  %takeA = icmp eq i1 %gt, %isMax"
        "  %r = select i1 %takeA, %Val %a, %Val %b"
        "  ret %Val %r"
        "}") "\n"))
    (pair "@mathrt.min" "define internal %Val @mathrt.min(%Val %a, %Val %b) {\nentry:\n  %r = call %Val @mathrt.minmax(%Val %a, %Val %b, i1 false, ptr @.mathrt.who.min)\n  ret %Val %r\n}")
    (pair "@mathrt.max" "define internal %Val @mathrt.max(%Val %a, %Val %b) {\nentry:\n  %r = call %Val @mathrt.minmax(%Val %a, %Val %b, i1 true, ptr @.mathrt.who.max)\n  ret %Val %r\n}")
    (pair "@mathrt.clamp"
      (str "define internal %Val @mathrt.clamp(%Val %lo, %Val %hi, %Val %x) {\nentry:\n"
           (mathWant "lo" "clamp" 3 "hiCheck")
           "hiCheck:\n"
           (mathWant "hi" "clamp" 3 "xCheck")
           "xCheck:\n"
           (mathWant "x" "clamp" 3 "values")
           "values:\n"
           "  %lo.f = bitcast i64 %lo.bits to double\n"
           "  %hi.f = bitcast i64 %hi.bits to double\n"
           "  %x.f = bitcast i64 %x.bits to double\n"
           "  %ordered = fcmp ole double %lo.f, %hi.f\n"
           "  br i1 %ordered, label %limit, label %range\n"
           "range:\n"
           "  %buf = alloca [4096 x i8]\n"
           "  store i8 0, ptr %buf\n"
           "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.mathrt.clampRange, double %lo.f, double %hi.f)\n"
           "  %len = call i64 @strlen(ptr %buf)\n"
           "  call void @rterr.raise(ptr @.rterr.c.ERR_RANGE, ptr %buf, i64 %len)\n"
           "  unreachable\n"
           "limit:\n"
           "  %isNan = fcmp uno double %x.f, %x.f\n"
           "  %below = fcmp olt double %x.f, %lo.f\n"
           "  %above = fcmp ogt double %x.f, %hi.f\n"
           "  %capped = select i1 %above, double %hi.f, double %x.f\n"
           "  %limited = select i1 %below, double %lo.f, double %capped\n"
           "  %result = select i1 %isNan, double %x.f, double %limited\n"
           "  %result.bits = bitcast double %result to i64\n"
           "  %r = insertvalue %Val { i64 3, i64 0 }, i64 %result.bits, 1\n"
           "  ret %Val %r\n}"))
    (pair "@mathrt.int64ToFloat64"
      (str "define internal %Val @mathrt.int64ToFloat64(%Val %v) {\nentry:\n"
           (mathWant "v" "int64ToFloat64" 2 "convert")
           "convert:\n"
           "  %f = sitofp i64 %v.bits to double\n"
           "  %f.bits = bitcast double %f to i64\n"
           "  %r = insertvalue %Val { i64 3, i64 0 }, i64 %f.bits, 1\n"
           "  ret %Val %r\n}"))
    (pair "@mathrt.float64ToInt64"
      (str "define internal %Val @mathrt.float64ToInt64(%Val %v) {\nentry:\n"
           (mathWant "v" "float64ToInt64" 3 "convert")
           "convert:\n"
           "  %d = bitcast i64 %v.bits to double\n"
           "  %fromMin = fcmp oge double %d, 0xC3E0000000000000\n"
           "  %belowMax = fcmp olt double %d, 0x43E0000000000000\n"
           "  %inRange = and i1 %fromMin, %belowMax\n"
           "  br i1 %inRange, label %isSome, label %isNone\n"
           "isSome:\n"
           "  %n = fptosi double %d to i64\n"
           "  %n.val = insertvalue %Val { i64 2, i64 0 }, i64 %n, 1\n"
           (emitCtorAlloc "some" "some" (list "%n.val"))
           "  %someVal = insertvalue %Val { i64 8, i64 0 }, i64 %some.objw, 1\n"
           "  ret %Val %someVal\n"
           "isNone:\n"
           (emitCtorAlloc "none" "none" (list))
           "  %noneVal = insertvalue %Val { i64 8, i64 0 }, i64 %none.objw, 1\n"
           "  ret %Val %noneVal\n}"))
    (pair "@mathrt.shiftLeft" (mathShift "shiftLeft" "shl"))
    (pair "@mathrt.shiftRight" (mathShift "shiftRight" "ashr"))
    (pair "@mathrt.bitAnd" (mathBitwise "bitAnd" "and"))
    (pair "@mathrt.bitOr" (mathBitwise "bitOr" "or"))
    (pair "@mathrt.bitXor" (mathBitwise "bitXor" "xor"))
    (pair "@mathrt.bitNot" (str "define internal %Val @mathrt.bitNot(%Val %a) {\nentry:\n"
                                (mathWant "a" "bitNot" 2 "flip")
                                "flip:\n"
                                "  %r = xor i64 %a.bits, -1\n"
                                "  %v = insertvalue %Val { i64 2, i64 0 }, i64 %r, 1\n"
                                "  ret %Val %v\n}")))

fn mathBitwise who: String instr: String -> String
  (str "define internal %Val @mathrt." who "(%Val %a, %Val %b) {\nentry:\n"
       (mathWant "a" who 2 "second")
       "second:\n"
       (mathWant "b" who 2 "apply")
       "apply:\n"
       "  %r = " instr " i64 %a.bits, %b.bits\n"
       "  %v = insertvalue %Val { i64 2, i64 0 }, i64 %r, 1\n"
       "  ret %Val %v\n}")

fn mathShift who: String instr: String -> String
  (str "define internal %Val @mathrt." who "(%Val %a, %Val %b) {\nentry:\n"
       (mathWant "a" who 2 "second")
       "second:\n"
       (mathWant "b" who 2 "shift")
       "shift:\n"
       "  %count = and i64 %b.bits, 63\n"
       "  %r = " instr " i64 %a.bits, %count\n"
       "  %v = insertvalue %Val { i64 2, i64 0 }, i64 %r, 1\n"
       "  ret %Val %v\n}")

fn mathPieces -> (List (Pair String String))
  (listAppend (mathConstants) (mathFunctions))

fn seqConstants -> (List (Pair String String))
  (map (fn [(p (Pair String String))] -> (Pair String String) (pair (pairFirst p) (mathText (pairFirst p) (pairSecond p))))
       (list (pair "@.listrt.who.cons" "cons") (pair "@.listrt.who.listHead" "listHead") (pair "@.listrt.who.listTail" "listTail")
             (pair "@.listrt.who.listEmpty" "listEmpty?") (pair "@.listrt.who.stringSlice" "stringSlice")
             (pair "@.bytesrt.who.bytesLength" "bytesLength") (pair "@.bytesrt.who.bytesGet" "bytesGet") (pair "@.bytesrt.who.bytesSet" "bytesSet")
             (pair "@.bytesrt.who.bytesGetFloat64" "bytesGetFloat64") (pair "@.bytesrt.who.bytesSetFloat64" "bytesSetFloat64")
             (pair "@.bytesrt.slot" "%s: slot %lld outside %zu bytes") (pair "@.bytesrt.notByte" "bytesSet: %lld is not a byte")
             (pair "@.bytesrt.negative" "bytesAlloc: negative size %lld") (pair "@.bytesrt.oom" "cannot allocate %zu bytes")
             (pair "@.bytesrt.c.ERR_OOM" "ERR_OOM") (pair "@.listrt.partialNone" (partialNoneText))
             (pair "@.listrt.first" "listFirst of an empty list or a %s") (pair "@.listrt.rest" "listRest of an empty list or a %s")))

fn partialNoneText -> String
  "partial expects a function"

fn seqTag v: String -> String
  (str "  %" v ".tagw = extractvalue %Val %" v ", 0\n  %" v ".tag = trunc i64 %" v ".tagw to i32\n")

fn seqObj v: String -> String
  (str "  %" v ".objw = extractvalue %Val %" v ", 1\n  %" v ".obj = inttoptr i64 %" v ".objw to ptr\n")

fn seqWant v: String who: String want: Int64 next: String -> String
  (str (seqTag v)
       "  %" v ".ok = icmp eq i32 %" v ".tag, " want "\n"
       "  br i1 %" v ".ok, label %" next ", label %" v ".bad\n"
       v ".bad:\n"
       "  call void @mathrt.want(ptr " who ", i32 " want ", i32 %" v ".tag)\n"
       "  unreachable\n")

fn optionPart sym: String who: String fieldOff: Int64 -> String
  (str "define internal %Val " sym "(%Val %xs, %Val %d) {\nentry:\n"
       (seqWant "xs" who 6 "list")
       "list:\n"
       (seqObj "xs")
       "  %nil = icmp eq ptr %xs.obj, null\n"
       "  br i1 %nil, label %empty, label %cell\n"
       "empty:\n"
       "  ret %Val %d\n"
       "cell:\n"
       "  %fieldp = getelementptr inbounds i8, ptr %xs.obj, i64 " fieldOff "\n"
       "  %field = load %Val, ptr %fieldp\n"
       "  ret %Val %field\n}")

fn cellPart sym: String format: String fieldOff: Int64 -> String
  (str "define internal %Val " sym "(%Val %xs) {\nentry:\n"
       (seqTag "xs")
       "  %isList = icmp eq i32 %xs.tag, 6\n"
       (seqObj "xs")
       "  %full = icmp ne ptr %xs.obj, null\n"
       "  %ok = and i1 %isList, %full\n"
       "  br i1 %ok, label %cell, label %bad\n"
       "bad:\n"
       "  %name = call ptr @rterr.tagName(i32 %xs.tag)\n"
       "  call void @rterr.raiseText(ptr @.rterr.c.ERR_INTERNAL, ptr " format ", ptr %name)\n"
       "  unreachable\n"
       "cell:\n"
       "  %fieldp = getelementptr inbounds i8, ptr %xs.obj, i64 " fieldOff "\n"
       "  %field = load %Val, ptr %fieldp\n"
       "  ret %Val %field\n}")

fn seqFunctions -> (List (Pair String String))
  (list
    (pair "@bytesrt.slotBad"
      (stringJoin (list
        "define internal void @bytesrt.slotBad(ptr %who, i64 %slot, i64 %len) noreturn {"
        "entry:"
        "  %buf = alloca [4096 x i8]"
        "  store i8 0, ptr %buf"
        "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.bytesrt.slot, ptr %who, i64 %slot, i64 %len)"
        "  %count = call i64 @strlen(ptr %buf)"
        "  call void @rterr.raise(ptr @.rterr.c.ERR_RANGE, ptr %buf, i64 %count)"
        "  unreachable"
        "}") "\n"))
    (pair "@bytesrt.notByte"
      (stringJoin (list
        "define internal void @bytesrt.notByte(i64 %v) noreturn {"
        "entry:"
        "  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_RANGE, ptr @.bytesrt.notByte, i64 %v)"
        "  unreachable"
        "}") "\n"))
    (pair "@bytesrt.alloc"
      (stringJoin (list
        "define internal %Val @bytesrt.alloc(i64 %n) {"
        "entry:"
        "  %negative = icmp slt i64 %n, 0"
        "  br i1 %negative, label %bad, label %make"
        "bad:"
        "  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_RANGE, ptr @.bytesrt.negative, i64 %n)"
        "  unreachable"
        "make:"
        "  %obj = call ptr @asl_alloc(i32 6, i64 32)"
        "  %size = add i64 %n, 1"
        "  %data = call ptr @calloc(i64 %size, i64 1)"
        "  %failed = icmp eq ptr %data, null"
        "  br i1 %failed, label %oom, label %ready"
        "oom:"
        "  call void @rterr.raiseNumber(ptr @.bytesrt.c.ERR_OOM, ptr @.bytesrt.oom, i64 %n)"
        "  unreachable"
        "ready:"
        "  %lenp = getelementptr inbounds i8, ptr %obj, i64 8"
        "  store i64 %n, ptr %lenp"
        "  %elemp = getelementptr inbounds i8, ptr %obj, i64 16"
        "  store i64 1, ptr %elemp"
        "  %datap = getelementptr inbounds i8, ptr %obj, i64 24"
        "  store ptr %data, ptr %datap"
        "  %accounted = call i64 @gcAccount(ptr %obj, i64 %n)"
        "  %objw = ptrtoint ptr %obj to i64"
        "  %r = insertvalue %Val { i64 11, i64 0 }, i64 %objw, 1"
        "  ret %Val %r"
        "}") "\n"))
    (pair "@bytesrt.slot8"
      (str "define internal ptr @bytesrt.slot8(%Val %b, %Val %i, ptr %who) {\nentry:\n"
           (seqWant "b" "%who" 11 "index")
           "index:\n"
           (seqWant "i" "%who" 2 "range")
           "range:\n"
           (seqObj "b")
           "  %lenp = getelementptr inbounds i8, ptr %b.obj, i64 8\n"
           "  %len = load i64, ptr %lenp\n"
           "  %slots = udiv i64 %len, 8\n"
           "  %slot = extractvalue %Val %i, 1\n"
           "  %inside = icmp ult i64 %slot, %slots\n"
           "  br i1 %inside, label %address, label %outside\n"
           "outside:\n"
           "  call void @bytesrt.slotBad(ptr %who, i64 %slot, i64 %len)\n"
           "  unreachable\n"
           "address:\n"
           "  %datap = getelementptr inbounds i8, ptr %b.obj, i64 24\n"
           "  %data = load ptr, ptr %datap\n"
           "  %offset = mul i64 %slot, 8\n"
           "  %at = getelementptr inbounds i8, ptr %data, i64 %offset\n"
           "  ret ptr %at\n}"))
    (pair "@bytesrt.getFloat64"
      (stringJoin (list
        "define internal %Val @bytesrt.getFloat64(%Val %b, %Val %i) {"
        "entry:"
        "  %at = call ptr @bytesrt.slot8(%Val %b, %Val %i, ptr @.bytesrt.who.bytesGetFloat64)"
        "  %bits = load i64, ptr %at, align 1"
        "  %r = insertvalue %Val { i64 3, i64 0 }, i64 %bits, 1"
        "  ret %Val %r"
        "}") "\n"))
    (pair "@bytesrt.setFloat64"
      (str "define internal %Val @bytesrt.setFloat64(%Val %b, %Val %i, %Val %v) {\nentry:\n"
           "  %at = call ptr @bytesrt.slot8(%Val %b, %Val %i, ptr @.bytesrt.who.bytesSetFloat64)\n"
           "  br label %value\n"
           "value:\n"
           (seqWant "v" "@.bytesrt.who.bytesSetFloat64" 3 "store")
           "store:\n"
           "  %bits = extractvalue %Val %v, 1\n"
           "  store i64 %bits, ptr %at, align 1\n"
           "  ret %Val { i64 0, i64 0 }\n}"))
    (pair "@listrt.cell"
      (stringJoin (list
        "define internal %Val @listrt.cell(%Val %car, %Val %cdr) {"
        "entry:"
        "  %obj = call ptr @asl_alloc(i32 1, i64 40)"
        "  %carp = getelementptr inbounds i8, ptr %obj, i64 8"
        "  store %Val %car, ptr %carp"
        "  %cdrp = getelementptr inbounds i8, ptr %obj, i64 24"
        "  store %Val %cdr, ptr %cdrp"
        "  %objw = ptrtoint ptr %obj to i64"
        "  %r = insertvalue %Val { i64 6, i64 0 }, i64 %objw, 1"
        "  ret %Val %r"
        "}") "\n"))
    (pair "@listrt.headOr" (optionPart "@listrt.headOr" "@.listrt.who.listHead" 8))
    (pair "@listrt.tailOr" (optionPart "@listrt.tailOr" "@.listrt.who.listTail" 24))
    (pair "@listrt.getOr"
      (str "define internal %Val @listrt.getOr(%Val %xs, i64 %i, %Val %d) {\nentry:\n"
           "  %negative = icmp slt i64 %i, 0\n"
           "  br i1 %negative, label %miss, label %check\n"
           "check:\n"
           (seqWant "xs" "@.listrt.who.listEmpty" 6 "walk")
           "walk:\n"
           (seqObj "xs")
           "  br label %loop\n"
           "loop:\n"
           "  %cell = phi ptr [ %xs.obj, %walk ], [ %next, %step ]\n"
           "  %k = phi i64 [ %i, %walk ], [ %k1, %step ]\n"
           "  %nil = icmp eq ptr %cell, null\n"
           "  br i1 %nil, label %miss, label %visit\n"
           "visit:\n"
           "  %hit = icmp eq i64 %k, 0\n"
           "  br i1 %hit, label %found, label %advance\n"
           "found:\n"
           "  %carp = getelementptr inbounds i8, ptr %cell, i64 8\n"
           "  %car = load %Val, ptr %carp\n"
           "  ret %Val %car\n"
           "advance:\n"
           "  %cdrp = getelementptr inbounds i8, ptr %cell, i64 24\n"
           "  %cdr = load %Val, ptr %cdrp\n"
           (seqWant "cdr" "@.listrt.who.listEmpty" 6 "step")
           "step:\n"
           "  %cdr.objw = extractvalue %Val %cdr, 1\n"
           "  %next = inttoptr i64 %cdr.objw to ptr\n"
           "  %k1 = sub i64 %k, 1\n"
           "  br label %loop\n"
           "miss:\n"
           "  ret %Val %d\n}"))
    (pair "@listrt.sliceOr"
      (str "define internal %Val @listrt.sliceOr(%Val %s, i64 %from, i64 %to, %Val %d) {\nentry:\n"
           (seqWant "s" "@.listrt.who.stringSlice" 5 "text")
           "text:\n"
           (seqObj "s")
           "  %lenp = getelementptr inbounds i8, ptr %s.obj, i64 8\n"
           "  %len = load i64, ptr %lenp\n"
           "  %before = icmp slt i64 %from, 0\n"
           "  %backward = icmp slt i64 %to, %from\n"
           "  %past = icmp ugt i64 %to, %len\n"
           "  %outside = or i1 %before, %backward\n"
           "  %bad = or i1 %outside, %past\n"
           "  br i1 %bad, label %miss, label %copy\n"
           "miss:\n"
           "  ret %Val %d\n"
           "copy:\n"
           "  %n = sub i64 %to, %from\n"
           "  %bytes = add i64 %n, 17\n"
           "  %new = call ptr @asl_alloc(i32 0, i64 %bytes)\n"
           "  %newLenp = getelementptr inbounds i8, ptr %new, i64 8\n"
           "  store i64 %n, ptr %newLenp\n"
           "  %src.objw = extractvalue %Val %s, 1\n"
           "  %src.obj = inttoptr i64 %src.objw to ptr\n"
           "  %srcText = getelementptr inbounds i8, ptr %src.obj, i64 16\n"
           "  %srcAt = getelementptr inbounds i8, ptr %srcText, i64 %from\n"
           "  %dst = getelementptr inbounds i8, ptr %new, i64 16\n"
           "  %copied = call ptr @memcpy(ptr %dst, ptr %srcAt, i64 %n)\n"
           "  %end = getelementptr inbounds i8, ptr %dst, i64 %n\n"
           "  store i8 0, ptr %end\n"
           "  %neww = ptrtoint ptr %new to i64\n"
           "  %r = insertvalue %Val { i64 5, i64 0 }, i64 %neww, 1\n"
           "  ret %Val %r\n}"))
    (pair "@listrt.first" (cellPart "@listrt.first" "@.listrt.first" 8))
    (pair "@listrt.rest" (cellPart "@listrt.rest" "@.listrt.rest" 24))
    (pair "@listrt.partialNone"
      (str "define internal %Val @listrt.partialNone() {\nentry:\n"
           "  call void @rterr.raise(ptr @.rterr.c.ERR_ARITY, ptr @.listrt.partialNone, i64 " (stringLength (partialNoneText)) ")\n"
           "  unreachable\n}")))

fn seqDecls -> (List String)
  (list "declare ptr @calloc(i64, i64)" "declare ptr @memcpy(ptr, ptr, i64)" "declare i64 @gcAccount(ptr, i64)")

fn strConstants -> (List (Pair String String))
  (map (fn [(p (Pair String String))] -> (Pair String String) (pair (pairFirst p) (mathText (pairFirst p) (pairSecond p))))
       (list (pair "@.strrt.who.stringLength" "stringLength") (pair "@.strrt.who.stringConcat" "stringConcat") (pair "@.strrt.who.stringSlice" "stringSlice")
             (pair "@.strrt.who.stringFromInt64" "stringFromInt64") (pair "@.strrt.who.stringStartsWith" "stringStartsWith?")
             (pair "@.strrt.who.stringContains" "stringContains?") (pair "@.strrt.who.stringToBytes" "stringToBytes")))

fn strLength v: String -> String
  (str (seqObj v) "  %" v ".lenp = getelementptr inbounds i8, ptr %" v ".obj, i64 8\n  %" v ".len = load i64, ptr %" v ".lenp\n")

fn strText v: String into: String -> String
  (str "  %" into ".objw = extractvalue %Val %" v ", 1\n  %" into ".obj = inttoptr i64 %" into ".objw to ptr\n"
       "  %" into " = getelementptr inbounds i8, ptr %" into ".obj, i64 16\n")

fn strMatchHead sym: String who: String -> String
  (str "define internal i1 " sym "(%Val %x, %Val %y) {\nentry:\n"
       (seqWant "x" who 5 "second")
       "second:\n"
       (seqWant "y" who 5 "compare")
       "compare:\n"
       (strLength "x") (strLength "y")
       "  %xText = getelementptr inbounds i8, ptr %x.obj, i64 16\n"
       "  %yText = getelementptr inbounds i8, ptr %y.obj, i64 16\n")

fn strFunctions -> (List (Pair String String))
  (list
    (pair "@strrt.length"
      (str "define internal i64 @strrt.length(%Val %s) {\nentry:\n"
           (seqWant "s" "@.strrt.who.stringLength" 5 "text")
           "text:\n"
           (strLength "s")
           "  ret i64 %s.len\n}"))
    (pair "@strrt.concat"
      (str "define internal %Val @strrt.concat(%Val %a, %Val %b) {\nentry:\n"
           (seqWant "a" "@.strrt.who.stringConcat" 5 "second")
           "second:\n"
           (seqWant "b" "@.strrt.who.stringConcat" 5 "join")
           "join:\n"
           (strLength "a") (strLength "b")
           "  %n = add i64 %a.len, %b.len\n"
           "  %bytes = add i64 %n, 17\n"
           "  %new = call ptr @asl_alloc(i32 0, i64 %bytes)\n"
           "  %newLenp = getelementptr inbounds i8, ptr %new, i64 8\n"
           "  store i64 %n, ptr %newLenp\n"
           (strText "a" "aText") (strText "b" "bText")
           "  %dst = getelementptr inbounds i8, ptr %new, i64 16\n"
           "  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %aText, i64 %a.len, i1 false)\n"
           "  %dstB = getelementptr inbounds i8, ptr %dst, i64 %a.len\n"
           "  call void @llvm.memcpy.p0.p0.i64(ptr %dstB, ptr %bText, i64 %b.len, i1 false)\n"
           "  %end = getelementptr inbounds i8, ptr %dst, i64 %n\n"
           "  store i8 0, ptr %end\n"
           "  %neww = ptrtoint ptr %new to i64\n"
           "  %r = insertvalue %Val { i64 5, i64 0 }, i64 %neww, 1\n"
           "  ret %Val %r\n}"))
    (pair "@strrt.slice"
      (str "define internal %Val @strrt.slice(%Val %s, i64 %from, i64 %to) {\nentry:\n"
           (seqWant "s" "@.strrt.who.stringSlice" 5 "text")
           "text:\n"
           (strLength "s")
           "  %before = icmp slt i64 %from, 0\n"
           "  %backward = icmp slt i64 %to, %from\n"
           "  %past = icmp ugt i64 %to, %s.len\n"
           "  %outside = or i1 %before, %backward\n"
           "  %bad = or i1 %outside, %past\n"
           "  br i1 %bad, label %miss, label %copy\n"
           "miss:\n"
           (emitCtorAlloc "none" "none" (list))
           "  %noneVal = insertvalue %Val { i64 8, i64 0 }, i64 %none.objw, 1\n"
           "  ret %Val %noneVal\n"
           "copy:\n"
           "  %n = sub i64 %to, %from\n"
           "  %bytes = add i64 %n, 17\n"
           "  %new = call ptr @asl_alloc(i32 0, i64 %bytes)\n"
           "  %newLenp = getelementptr inbounds i8, ptr %new, i64 8\n"
           "  store i64 %n, ptr %newLenp\n"
           (strText "s" "sText")
           "  %srcAt = getelementptr inbounds i8, ptr %sText, i64 %from\n"
           "  %dst = getelementptr inbounds i8, ptr %new, i64 16\n"
           "  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %srcAt, i64 %n, i1 false)\n"
           "  %end = getelementptr inbounds i8, ptr %dst, i64 %n\n"
           "  store i8 0, ptr %end\n"
           "  %neww = ptrtoint ptr %new to i64\n"
           "  %piece = insertvalue %Val { i64 5, i64 0 }, i64 %neww, 1\n"
           (emitCtorAlloc "some" "some" (list "%piece"))
           "  %someVal = insertvalue %Val { i64 8, i64 0 }, i64 %some.objw, 1\n"
           "  ret %Val %someVal\n}"))
    (pair "@strrt.startsWith"
      (str (strMatchHead "@strrt.startsWith" "@.strrt.who.stringStartsWith")
           "  %fits = icmp ule i64 %y.len, %x.len\n"
           "  br i1 %fits, label %scan, label %no\n"
           "scan:\n"
           "  %c = call i32 @memcmp(ptr %xText, ptr %yText, i64 %y.len)\n"
           "  %same = icmp eq i32 %c, 0\n"
           "  ret i1 %same\n"
           "no:\n"
           "  ret i1 false\n}"))
    (pair "@strrt.contains"
      (str (strMatchHead "@strrt.contains" "@.strrt.who.stringContains")
           "  %empty = icmp eq i64 %y.len, 0\n"
           "  br i1 %empty, label %yes, label %fit\n"
           "fit:\n"
           "  %fits = icmp ule i64 %y.len, %x.len\n"
           "  br i1 %fits, label %start, label %no\n"
           "start:\n"
           "  %last = sub i64 %x.len, %y.len\n"
           "  br label %loop\n"
           "loop:\n"
           "  %i = phi i64 [ 0, %start ], [ %next, %advance ]\n"
           "  %at = getelementptr inbounds i8, ptr %xText, i64 %i\n"
           "  %c = call i32 @memcmp(ptr %at, ptr %yText, i64 %y.len)\n"
           "  %same = icmp eq i32 %c, 0\n"
           "  br i1 %same, label %yes, label %advance\n"
           "advance:\n"
           "  %next = add i64 %i, 1\n"
           "  %more = icmp ule i64 %next, %last\n"
           "  br i1 %more, label %loop, label %no\n"
           "yes:\n"
           "  ret i1 true\n"
           "no:\n"
           "  ret i1 false\n}"))
    (pair "@strrt.toBytes"
      (str "define internal %Val @strrt.toBytes(%Val %s) {\nentry:\n"
           (seqWant "s" "@.strrt.who.stringToBytes" 5 "copy")
           "copy:\n"
           (strLength "s")
           "  %b = call %Val @bytesrt.alloc(i64 %s.len)\n"
           "  %b.objw = extractvalue %Val %b, 1\n"
           "  %b.obj = inttoptr i64 %b.objw to ptr\n"
           "  %datap = getelementptr inbounds i8, ptr %b.obj, i64 24\n"
           "  %data = load ptr, ptr %datap\n"
           (strText "s" "sText")
           "  call void @llvm.memcpy.p0.p0.i64(ptr %data, ptr %sText, i64 %s.len, i1 false)\n"
           "  ret %Val %b\n}")))

fn strDecls -> (List String)
  (list "declare i32 @memcmp(ptr, ptr, i64)" "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)")

fn hostConstants -> (List (Pair String String))
  (listAppend (map (fn [(p (Pair String String))] -> (Pair String String) (pair (pairFirst p) (mathText (pairFirst p) (pairSecond p))))
                   (list (pair "@.hostrt.logVar" "ASL_SPAWN_LOG") (pair "@.hostrt.append" "a") (pair "@.hostrt.empty" "")))
              (list (pair "@.hostrt.lineFormat" "@.hostrt.lineFormat = private unnamed_addr constant [7 x i8] c\"%s %s\\0A\\00\"")))

fn hostFunctions -> (List (Pair String String))
  (list
    (pair "@mkBytes"
      (str "define internal %Val @mkBytes(ptr %p, i64 %n) {\nentry:\n"
           "  %b = call %Val @bytesrt.alloc(i64 %n)\n"
           "  %empty = icmp eq ptr %p, null\n"
           "  br i1 %empty, label %done, label %copy\n"
           "copy:\n"
           (seqObj "b")
           "  %datap = getelementptr inbounds i8, ptr %b.obj, i64 24\n"
           "  %data = load ptr, ptr %datap\n"
           "  call void @llvm.memcpy.p0.p0.i64(ptr %data, ptr %p, i64 %n, i1 false)\n"
           "  br label %done\n"
           "done:\n"
           "  ret %Val %b\n}"))
    (pair "@aslLogSpawn"
      (stringJoin (list
        "define internal i64 @aslLogSpawn(ptr %argv0) {"
        "entry:"
        "  %cwd = alloca [4096 x i8]"
        "  %line = alloca [8256 x i8]"
        "  %log = call ptr @getenv(ptr @.hostrt.logVar)"
        "  %unset = icmp eq ptr %log, null"
        "  br i1 %unset, label %done, label %named"
        "named:"
        "  %first = load i8, ptr %log"
        "  %blank = icmp eq i8 %first, 0"
        "  br i1 %blank, label %done, label %where"
        "where:"
        "  %got = call ptr @getcwd(ptr %cwd, i64 4096)"
        "  %lost = icmp eq ptr %got, null"
        "  br i1 %lost, label %noCwd, label %format"
        "noCwd:"
        "  store i8 0, ptr %cwd"
        "  br label %format"
        "format:"
        "  %anon = icmp eq ptr %argv0, null"
        "  %name = select i1 %anon, ptr @.hostrt.empty, ptr %argv0"
        "  %len = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %line, i64 8256, ptr @.hostrt.lineFormat, ptr %name, ptr %cwd)"
        "  %nothing = icmp sle i32 %len, 0"
        "  br i1 %nothing, label %done, label %open"
        "open:"
        "  %len64 = sext i32 %len to i64"
        "  %over = icmp sge i64 %len64, 8256"
        "  %count = select i1 %over, i64 8255, i64 %len64"
        "  %file = call ptr @fopen(ptr %log, ptr @.hostrt.append)"
        "  %closed = icmp eq ptr %file, null"
        "  br i1 %closed, label %done, label %write"
        "write:"
        "  %wrote = call i64 @fwrite(ptr %line, i64 1, i64 %count, ptr %file)"
        "  %shut = call i32 @fclose(ptr %file)"
        "  br label %done"
        "done:"
        "  ret i64 0"
        "}") "\n")))

fn hostDecls -> (List String)
  (list "declare ptr @getenv(ptr)" "declare ptr @getcwd(ptr, i64)" "declare ptr @fopen(ptr, ptr)" "declare i64 @fwrite(ptr, i64, i64, ptr)" "declare i32 @fclose(ptr)")

fn hostDefined? name: String -> Bool
  (listContains? (list "mkBytes" "aslLogSpawn") name)

fn mathRefers? text: String name: String -> Bool
  (and (stringContains? text name)
       (listAny? (fn [(d String)] -> Bool (stringContains? text (str name d))) (list "(" ")" "," " " "\n")))

fn mathClose text: String chosen: (List String) pieces: (List (Pair String String)) -> (List String)
  (let [(fresh (filter (fn [(p (Pair String String))] -> Bool (and (not (listContains? chosen (pairFirst p))) (mathRefers? text (pairFirst p)))) pieces))]
    (if (listEmpty? fresh)
      chosen
      (mathClose (str (rterr/tailOf text) "\n" (stringJoin (map (fn [(p (Pair String String))] -> String (pairSecond p)) fresh) "\n")) (listAppend chosen (map (fn [(p (Pair String String))] -> String (pairFirst p)) fresh)) pieces)))

fn mathDefinitions text: String -> (List String)
  (let [(pieces (listAppend (listAppend (listAppend (mathPieces) (listAppend (listAppend (seqConstants) (seqFunctions)) (listAppend (strConstants) (strFunctions)))) (opsrt/rtOpsPieces)) (listAppend (objrt/rtObjectPieces) (listAppend (hostConstants) (hostFunctions)))))
        (chosen (mathClose text (list) pieces))]
    (map (fn [(p (Pair String String))] -> String (pairSecond p)) (filter (fn [(p (Pair String String))] -> Bool (listContains? chosen (pairFirst p))) pieces)))

fn formatHelpers -> (List String)
  (listAppend (listAppend (listAppend (listAppend (fmt/rtFormatLlvm) (fmt/rtFormatValueLlvm)) (fmt/rtFormatValLlvm)) (fmt/rtFormatManyLlvm))
              (fmt/rtFormatTerminalLlvm))

fn emitDefinitionsRooted m: ty/SsaModule entryCalls: String rooted: Bool -> (List String)
  (let [(menv (moduleEnv m))
        (framed (map (fn [(f ty/SsaFunction)] -> String (if (and (not rooted) (listBuilder? f)) (listBuilderText f) (emitFunctionRooted menv f rooted))) m.functions))
        (fns (if (listAny? (fn [(t String)] -> Bool (stringContains? t "@asl_gc_shadow_top")) framed) (cons (shadowTopDecl) framed) framed))
        (targets (closureTargets m))
        (tramps (map emitTrampoline (filter (fn [(f ty/SsaFunction)] -> Bool (listContains? targets f.name)) m.functions)))
        (resolvers (map (fn [(t String)] -> String (emitVariantIdsInit menv t)) (switchTypes m)))
        (fieldResolvers (map emitFieldIdInit (fieldIdNames m)))
        (ctorResolvers (map emitCtorIdInit (constructedVariants m)))
        (schemaResolvers (map (fn [(s String)] -> String (emitSchemaIdInit s (recordSchemaFields m s))) (constructedSchemas m)))
        (init (emitInit m))]
    (let [(core (listAppend (listAppend (listAppend (listAppend (listAppend (listAppend fns tramps) resolvers) fieldResolvers) ctorResolvers) schemaResolvers)
                            (if (stringEmpty? init) (list) (list init))))
          (base (listAppend core (mathDefinitions (stringJoin core "\n"))))
          (baseText (str (stringJoin base "\n") "\n" entryCalls))
          (reached (stringJoin (rterr/rtErrorDefinitions baseText) "\n"))
          (rendering (or (stringContains? reached "@asl_rt_format_") (stringContains? reached "@rtfmt_render(")))
          (callers (if (or rendering (listAny? formatOp? (allOps m))) (listAppend base (formatHelpers)) base))
          (callerText (str (stringJoin callers "\n") "\n" entryCalls))]
      (listAppend callers (rterr/rtErrorDefinitions callerText))))

fn exportDefinitions roots: String calls: Bool -> (List String)
  (let [(callDefs (if calls (mathDefinitions "@aslCall(") (list)))]
    (listAppend callDefs (rterr/rtErrorDefinitions (str roots "\n" (stringJoin callDefs "\n")))))

fn valueExports defs: (List String) -> (List String)
  (let [(text (stringJoin defs "\n"))]
    (filter (fn [(piece String)] -> Bool (not (stringContains? text (stringTrim piece))))
            (exportDefinitions (valrt/rtValueExportRoots) (stringContains? text "call %Val @asl_rt_builtin_"))))

fn cRuntimeModule -> String
  (let [(wrappers (stringJoin (list "define i32 @intern(ptr %text, i64 %length) {" "entry:" "  %id = call i32 @valrt.intern(ptr %text, i64 %length)" "  ret i32 %id" "}" ""
                                    "define %Val @mkStr(ptr %text, i64 %length) {" "entry:" "  %value = call %Val @valrt.str(ptr %text, i64 %length)" "  ret %Val %value" "}")
                              "\n"))
        (defs (str wrappers "\n" (stringJoin (exportDefinitions (str (valrt/rtValueExportRoots) " @aslHandlerSlot( @aslErrorText( @valrt.intern( @valrt.str(") true) "\n")))
        (defined (filter (fn [(l String)] -> Bool (stringStartsWith? l "define ")) (stringSplit defs "\n")))
        (decls (fold (fn [(acc (List String)) (d String)] -> (List String)
                       (if (or (listAny? (fn [(e String)] -> Bool (= (declSymbol e) (declSymbol d))) acc)
                               (listAny? (fn [(l String)] -> Bool (stringContains? l (declSymbol d))) defined))
                         acc
                         (listAppend acc (list d))))
                     (list)
                     (usedDecls defs (listAppend (listAppend (listAppend (rterr/rtErrorDecls) (valrt/rtValueDecls)) (objrt/rtObjectDecls)) (runtimeDecls)))))]
    (str "source_filename = \"aslRuntime\"\n\n%Val = type { i64, i64 }\n\n" defs "\n" (stringJoin decls "\n") "\n"))

fn assemble m: ty/SsaModule definitions: (List String) wasm: Bool -> String
  (let [(consts (emitConstants m wasm))
        (defs (stringJoin definitions "\n"))
        (externs (map (fn [(e ty/SsaExtern)] -> String
                        (cond
                          ((not e.typed) (str "declare %Val " (fnSym e.name) "(" (stringJoin (map (fn [(i Int64)] -> String "%Val") (range 0 e.arity)) ", ") ")"))
                          ((nativeExtern? e) (str "declare " (llTy e.ret) " " (fnSym e.name) "(" (stringJoin (listAppend (map llTy e.params) (if e.variadic (list "...") (list))) ", ") ")"))
                          (else (str "declare tailcc " (llTy e.ret) " " (fnSym e.name) "(" (stringJoin (map (fn [(p ty/SsaParam)] -> String (llTy p.ty)) (registerParams (map (fn [(t ty/SsaTy)] -> ty/SsaParam (ty/ssaParam "" t)) e.params))) ", ") ")"))))
                      (filter (fn [(e ty/SsaExtern)] -> Bool (not (or (hostDefined? e.name) (valrt/rtValueDefines? defs e.name)))) m.externs)))
        (spill (if (stringContains? defs "@asl_rt_spill") (list (str "@asl_rt_spill = external global [" (spillCapacity) " x %Val]")) (list)))
        (externGlobals (map (fn [(n String)] -> String (str (externGlobalSym n) " = external global ptr")) (loadGlobalNames m)))
        (moduleDecls (listAppend (listAppend (listAppend externs spill) externGlobals) (listAppend (usedRuntimeDecls defs) (usedDecls defs (intrinsicDecls)))))
        (formatDecls (fold (fn [(acc (List String)) (d String)] -> (List String)
                             (if (listAny? (fn [(e String)] -> Bool (= (declSymbol e) (declSymbol d))) (listAppend moduleDecls acc)) acc (listAppend acc (list d))))
                           (list) (usedDecls defs (listAppend (listAppend (listAppend (listAppend (listAppend (fmt/rtFormatDecls) (rterr/rtErrorDecls)) (seqDecls)) (strDecls)) (opsrt/rtOpsDecls)) (listAppend (listAppend (objrt/rtObjectDecls) (hostDecls)) (valrt/rtValueDecls))))))
        (decls (filter (fn [(d String)] -> Bool (not (valueDefinedDecl? defs d))) (listAppend moduleDecls formatDecls)))]
    (str "source_filename = \"" (llvmBytes m.name) "\"\n\n"
         (if (stringContains? (str defs (stringJoin decls "\n")) "%Val") "%Val = type { i64, i64 }\n\n" "")

         (if (stringEmpty? consts) "" (str consts "\n"))
         defs
         (if (listEmpty? decls) "" (str "\n" (stringJoin decls "\n") "\n"))))

fn valueDefinedDecl? defs: String decl: String -> Bool
  (let [(sym (declSymbol decl))
        (name (optionOr (stringSlice sym 1 (- (stringLength sym) 1)) ""))]
    (and (listContains? (valrt/valueShimNames) name) (valrt/rtValueDefines? defs name)))

fn spillDiag name: String types: (List ty/SsaTy) -> (List ty/IrDiag)
  (if (> (spillCount types) (spillCapacity))
    (list (ty/makeIrDiag "ERR_LLVM_ARITY" (str "'" name "' passes " (spillCount types) " arguments through asl_rt_spill, more than its " (spillCapacity) " slots") name))
    (list))

fn declParams decl: String -> (List String)
  (let [(open (optionOr (stringIndexOf decl "(") 0))
        (inner (optionOr (stringSlice decl (+ open 1) (- (stringLength decl) 1)) ""))]
    (if (stringEmpty? inner) (list) (stringSplit inner ", ")))

fn cDeclFits? decl: String -> Bool
  (let [(ps (declParams decl))
        (gpr (fold (fn [(acc Int64) (p String)] -> Int64 (+ acc (cond ((= p "%Val") 2) ((= p "double") 0) (else 1)))) 0 ps))
        (fpr (listLength (filter (fn [(p String)] -> Bool (= p "double")) ps)))]
    (and (<= gpr (spillGprLimit)) (<= fpr (spillFprLimit))))

fn overwideCDecls -> (List String)
  (filter (fn [(d String)] -> Bool (not (cDeclFits? d))) (runtimeDecls))

fn spillDiags m: ty/SsaModule -> (List ty/IrDiag)
  (listAppend
    (listAppend (fold (fn [(acc (List ty/IrDiag)) (f ty/SsaFunction)] -> (List ty/IrDiag) (listAppend acc (spillDiag f.name (signatureTypes f)))) (list) m.functions)
                (fold (fn [(acc (List ty/IrDiag)) (e ty/SsaExtern)] -> (List ty/IrDiag) (if (and e.typed (not (nativeExtern? e))) (listAppend acc (spillDiag e.name e.params)) acc)) (list) m.externs))
    (map (fn [(d String)] -> ty/IrDiag (ty/makeIrDiag "ERR_LLVM_ABI" (str "runtime declaration needs stack arguments: " d) (declSymbol d))) (overwideCDecls)))

fn nativeBuiltin? name: String n: Int64 -> Bool
  (or (and (= n 0) (or (= name "floatNan") (or (= name "floatInf") (= name "floatNegInf"))))
      (or (errorBuiltin? name n)
      (or (mathBuiltin? name n)
          (or (seqBuiltin? name n)
              (or (opsrt/opsBuiltin? name n)
                  (or (rtFormatBuiltin? name) (some? (builtinTableSym name))))))))

fn nativeEntryCall? name: String n: Int64 -> Bool
  (or (some? (nativeEntry name n))
      (or (formatEntryName? name)
          (or (some? (ty/builtinEntry name n)) (some? (builtinTableSym name)))))

fn unsupportedBuiltin op: ty/SsaOp -> (Option String)
  (mt op
    ((ty/opBuiltin name args) (if (nativeBuiltin? name (listLength args)) (none) (some (str "'" name "' of " (listLength args) " operand(s)"))))
    ((ty/opEntry name args) (if (nativeEntryCall? name (listLength args)) (none) (some (str "'" name "' of " (listLength args) " operand(s)"))))
    (_ (none)))

fn builtinDiags m: ty/SsaModule -> (List ty/IrDiag)
  (fold (fn [(acc (List ty/IrDiag)) (f ty/SsaFunction)] -> (List ty/IrDiag)
          (fold (fn [(a (List ty/IrDiag)) (b ty/SsaBlock)] -> (List ty/IrDiag)
                  (fold (fn [(d (List ty/IrDiag)) (ins ty/SsaInstr)] -> (List ty/IrDiag)
                          (mt (unsupportedBuiltin ins.op)
                            ((some what) (listAppend d (list (ty/makeIrDiag "ERR_LOWER_UNSUPPORTED" (str "builtin " what " has no native definition") f.name))))
                            ((none) d)))
                        a b.instrs))
                acc f.blocks))
        (list) m.functions)

fn entryInstrs ins: ty/SsaInstr -> (List ty/SsaInstr)
  (mt ins.op
    ((ty/opBuiltin name args)
      (mt (if (nativeBuiltin? name (listLength args)) (none) (ty/builtinEntry name (listLength args)))
        ((none) (list ins))
        ((some b)
          (let [(d ins.dest)
                (raw? (fn [(t ty/SsaTy)] -> Bool (!= (ty/ssaTyName t) "val")))
                (typed (zip (range 0 (listLength args)) (zip args b.args)))
                (operand (fn [(p (Pair Int64 (Pair String ty/SsaTy)))] -> String (if (raw? (pairSecond (pairSecond p))) (str d "#" (pairFirst p)) (pairFirst (pairSecond p)))))
                (unboxes (map (fn [(p (Pair Int64 (Pair String ty/SsaTy)))] -> ty/SsaInstr (ty/ssaInstr (operand p) (pairSecond (pairSecond p)) (ty/opUnbox (pairFirst (pairSecond p)))))
                              (filter (fn [(p (Pair Int64 (Pair String ty/SsaTy)))] -> Bool (raw? (pairSecond (pairSecond p)))) typed)))
                (call (ty/opEntry name (map operand typed)))]
            (listAppend unboxes
              (if (raw? b.result)
                (list (ty/ssaInstr (str d "#r") b.result call) (ty/ssaInstr d ins.ty (ty/opBox (str d "#r"))))
                (list (ty/ssaInstr d ins.ty call))))))))
    (_ (list ins)))

fn entryBuiltin? ins: ty/SsaInstr -> Bool
  (mt ins.op
    ((ty/opBuiltin name args) (and (not (nativeBuiltin? name (listLength args))) (some? (ty/builtinEntry name (listLength args)))))
    (_ false))

fn entryBuiltins m: ty/SsaModule -> ty/SsaModule
  (ty/ssaModule m.name m.strings m.types m.records m.externs m.globals
    (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction
           (ty/ssaFunction f.name f.captures f.params f.retTy
             (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
                    (if (listAny? entryBuiltin? b.instrs)
                      (ty/ssaBlock b.label b.params
                        (listReverse (fold (fn [(acc (List ty/SsaInstr)) (ins ty/SsaInstr)] -> (List ty/SsaInstr)
                                             (fold (fn [(a (List ty/SsaInstr)) (i ty/SsaInstr)] -> (List ty/SsaInstr) (cons i a)) acc (entryInstrs ins)))
                                           (list) b.instrs))
                        b.term)
                      b))
                  f.blocks)))
         m.functions))

fn emitDiags m: ty/SsaModule -> (List ty/IrDiag)
  (listAppend (spillDiags m) (builtinDiags m))

fn emitLlvmModule m: ty/SsaModule -> (Result String (List ty/IrDiag))
  (emitModuleWith m false)

fn emitLlvmModuleWasm32 m: ty/SsaModule -> (Result String (List ty/IrDiag))
  (emitModuleWith m true)

fn emitModuleWith m: ty/SsaModule wasm: Bool -> (Result String (List ty/IrDiag))
  (mt (vfy/verifySsa m)
    ((err diags) (err diags))
    ((ok _) (let [(e (entryBuiltins m)) (bad (emitDiags e))] (if (listEmpty? bad) (ok (assemble e (emitDefinitionsRooted e "" wasm) wasm)) (err bad)))))

fn replaceFunction text: String signature: String replacement: String -> String
  (mt (stringIndexOf text signature)
    ((none) text)
    ((some start)
      (let [(tail (optionOr (stringSlice text start (stringLength text)) ""))
            (close (optionOr (stringIndexOf tail "\n}") (stringLength tail)))
            (end (+ start close 2))]
        (str (optionOr (stringSlice text 0 start) "") replacement
             (optionOr (stringSlice text end (stringLength text)) "")))))

fn trapLowering text: String facts: target/TargetFacts -> String
  (if (!= facts.trapMechanism "wasm-trap")
    text
    (let [(withFeatures (replaceFunction text "define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn \"target-features\"=\"+tail-call\" {" (rterr/wasmRaiseFunction)))
          (raised (if (!= withFeatures text) withFeatures (replaceFunction text "define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {" (rterr/wasmRaiseFunction))))
          (noLongjmp (stringReplace raised "declare void @longjmp(ptr, i32) noreturn\n" ""))]
      (if (stringContains? noLongjmp "@rterr.raise(ptr %code")
        (str noLongjmp "\n" (rterr/wasmTrapImport))
        noLongjmp)))

fn entryDiag message: String locus: String -> (List ty/IrDiag)
  (list (ty/makeIrDiag "ERR_LLVM_ENTRY" message locus))

fn reportInit -> String
  "  call void @rterr.reportInit()\n"

fn emitArgsMain m: ty/SsaModule f: ty/SsaFunction -> String
  (str "define i32 @main(i32 %argc, ptr %argv) {\nbb.entry:\n"
       "  call void @asl_rt_init()\n"
       (reportInit)
       (if (listEmpty? m.globals) "" (str "  call void " (initSym m.name) "()\n"))
       "  %args = call %Val @valrt.args(i32 %argc, ptr %argv)\n"
       "  %result = call tailcc %Val " (fnSym f.name) "(%Val %args)\n"
       "  %code = call i32 @rterr.exit(%Val %result)\n"
       "  ret i32 %code\n}\n")

fn takesArgList f: ty/SsaFunction -> Bool
  (and (listEmpty? f.captures)
       (and (= (listLength f.params) 1)
            (and (= (ty/ssaTyName f.retTy) "val")
                 (listEmpty? (filter (fn [(p ty/SsaParam)] -> Bool (!= (ty/ssaTyName p.ty) "val")) f.params)))))

fn emitMain m: ty/SsaModule f: ty/SsaFunction usesRuntime: Bool -> String
  (let [(retTy (if (ty/ssaIsRec? f.retTy) (ty/tyVal) f.retTy))
        (prologue (str "define i32 @main() {\nbb.entry:\n"
                       (if usesRuntime "  call void @asl_rt_init()\n" "")
                       (reportInit)
                       (if (listEmpty? m.globals) "" (str "  call void " (initSym m.name) "()\n"))))]
    (mt retTy
      ((ty/tyVal)
        (str prologue
             "  %result = call tailcc %Val " (fnSym f.name) "()\n"
             (valTag "%result" "%result")
             "  %is_int = icmp eq i32 %result.vtag, 2\n"
             "  br i1 %is_int, label %bb.int, label %bb.result\n"
             "bb.int:\n"
             "  %value = extractvalue %Val %result, 1\n"
             "  %code.int = trunc i64 %value to i32\n"
             "  ret i32 %code.int\n"
             "bb.result:\n"
             "  %code.res = call i32 @rterr.exit(%Val %result)\n"
             "  ret i32 %code.res\n}\n"))
      (_
        (let [(convert (mt retTy
                         ((ty/tyI64) "  %code = trunc i64 %result to i32\n")
                         ((ty/tyI1) "  %code = zext i1 %result to i32\n")
                         ((ty/tyF64) "  %code = fptosi double %result to i32\n")
                         (_ "")))]
          (str prologue
               "  %result = call tailcc " (llTy retTy) " " (fnSym f.name) "()\n"
               convert
               "  ret i32 %code\n}\n")))))

fn emitLlvmProgram m: ty/SsaModule entry: String -> (Result String (List ty/IrDiag))
  (emitProgramWith m entry false)

fn emitLlvmProgramWasm32 m: ty/SsaModule entry: String -> (Result String (List ty/IrDiag))
  (emitProgramWith m entry true)

fn emitProgramWith m: ty/SsaModule entry: String wasm: Bool -> (Result String (List ty/IrDiag))
  (mt (vfy/verifySsa m)
    ((err diags) (err diags))
    ((ok _)
      (let [(found (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name entry)) m.functions))]
        (mt (listHead found)
          ((none) (err (entryDiag (str "entry function '" entry "' is not defined in the module") entry)))
          ((some _) (let [(e (entryBuiltins m)) (bad (emitDiags e))] (if (not (listEmpty? bad)) (err bad) (emitEntry e entry wasm))))))))

fn emitEntry m: ty/SsaModule entry: String wasm: Bool -> (Result String (List ty/IrDiag))
  (let [(found (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name entry)) m.functions))]
        (mt (listHead found)
          ((none) (err (entryDiag (str "entry function '" entry "' is not defined in the module") entry)))

          ((some f)
            (cond
              ((takesArgList f) (let [(defs (emitDefinitionsRooted m (emitArgsMain m f) wasm))]
                                  (ok (assemble m (listAppend (listAppend defs (valueExports defs)) (list (emitArgsMain m f))) wasm))))
              ((not (and (listEmpty? f.params) (listEmpty? f.captures))) (err (entryDiag (str "entry function '" entry "' must take no parameters, or one Val parameter (the argument list) and return a Val Result, and no captures") entry)))
              (else
                (let [(defs (emitDefinitionsRooted m (emitMain m f false) wasm))
                      (usesRuntime (or (not (listEmpty? (usedRuntimeDecls (stringJoin defs "\n")))) (= (ty/ssaAbiName f.retTy) "val")))]
                  (ok (assemble m (listAppend (if usesRuntime (listAppend defs (valueExports defs)) defs) (list (emitMain m f usesRuntime))) wasm))))))))
