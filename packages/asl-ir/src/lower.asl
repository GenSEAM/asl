(module asl-ir/lower :x [LinkScope lowerModule lowerWithPrelude lowerLinked lowerLinkedAs lowerSource declPositions builtinArity builtinArityFor] :i [(asl-ir/types :a ty) (asl-parser/ast :a ast) (asl-parser/reader :a rd)])

(schema Ctor (:f typeName String) (:f variant String) (:f arity Int64))

(schema ModInfo
  (:f arities (Map String Int64))
  (:f late (Map String Int64))
  (:f ctors (Map String Ctor))
  (:f records (Map String (List String)))
  (:f defaults (Map String (Map String rd/SExpr)))
  (:f types (List ty/SsaTypeDecl))
  (:f targets (Map String String))
  (:f foreign (List ty/SsaTypeDecl))
  (:f aliases (Map String String))
  (:f hidden (Map String String))
  (:f linked Bool)
  (:f sigs (Map String FnSig))
  (:f variants (Map String (List String))))

(schema FnSig (:f params (List ty/SsaTy)) (:f ret ty/SsaTy))

(schema LinkScope
  (:f path String)
  (:f imports (Map String (List ast/TopForm)))
  (:f prelude (List ast/TopForm))
  (:f strings (List String))
  (:f only (Option (List String))))

(schema LowerCtx (:f fnName String) (:f pos String) (:f info ModInfo))

(schema Arm (:f kind String) (:f variant String) (:f typeName String) (:f binds (List String)) (:f name String) (:f body (List rd/SExpr)))

(schema KeyedExpr (:f key String) (:f expr rd/SExpr))

(schema LowerState
  (:f next Int64)
  (:f labels Int64)
  (:f strings StringPool)
  (:f done (List ty/SsaBlock))
  (:f label String)
  (:f params (List ty/SsaParam))
  (:f instrs (List ty/SsaInstr))
  (:f lifted (List ty/SsaFunction))
  (:f lambdas Int64)
  (:f types TypeIndex)
  (:f twins TypeIndex))

(enum TypeIndex
  (:c typeIndexEmpty [] "Empty type index")
  (:c typeIndexNode [(key String) (value V) (left TypeIndex) (right TypeIndex) (height Int64)] "AVL node indexed by SSA value name"))

(schema Lowered (:f st LowerState) (:f value String))

(schema LoweredList (:f st LowerState) (:f values (List String)))

(schema Bound (:f st LowerState) (:f env (Map String String)))

(schema LoweredFn (:f function ty/SsaFunction) (:f lifted (List ty/SsaFunction)) (:f strings StringPool))

(schema StringPool (:f items (List String)) (:f count Int64) (:f index TypeIndex))

(schema Lambda (:f params (List String)) (:f types (List ty/SsaTy)) (:f body (List rd/SExpr)))

(schema ModAcc (:f strings StringPool) (:f functions (List ty/SsaFunction)) (:f diags (List ty/IrDiag)))

fn builtinArity name: String -> (Option Int64)
  (cond
    ((= name "+") (some 2)) ((= name "-") (some 2)) ((= name "*") (some 2))
    ((= name "/") (some 2)) ((= name "mod") (some 2)) ((= name "<") (some 2))
    ((= name "<=") (some 2)) ((= name ">") (some 2)) ((= name ">=") (some 2))
    ((= name "=") (some 2)) ((= name "==") (some 2)) ((= name "!=") (some 2))
    ((= name "not") (some 1)) ((= name "abs") (some 1)) ((= name "min") (some 2))
    ((= name "max") (some 2)) ((= name "<<") (some 2)) ((= name ">>") (some 2))
    ((= name "&") (some 2)) ((= name "|") (some 2)) ((= name "^") (some 2)) ((= name "~") (some 1))
    ((= name "trap") (some 2)) ((= name "str") (some -1)) ((= name "stringConcat") (some 2))
    ((= name "stringLength") (some 1)) ((= name "stringFromInt64") (some 1)) ((= name "print") (some -1))
    ((= name "println") (some -1)) ((= name "parMap") (some 3)) ((= name "parFold") (some 5))
    ((= name "listTail") (some 1)) ((= name "listHead") (some 1)) ((= name "listEmpty?") (some 1))
    ((= name "cons") (some 2)) ((= name "stringSlice") (some 3)) ((= name "stringFromFloat64") (some 1))
    ((= name "stringToFloat64") (some 1)) ((= name "int64ToFloat64") (some 1)) ((= name "float64ToInt64") (some 1))
    ((= name "floatNan") (some 0)) ((= name "floatInf") (some 0)) ((= name "floatNegInf") (some 0))
    ((= name "fileReadBytes") (some 1)) ((= name "fileReadString") (some 1)) ((= name "realPath") (some 1))
    ((= name "fileReadlink") (some 1)) ((= name "zstdDecompress") (some 1)) ((= name "bytesSha256") (some 1))
    ((= name "bytesLength") (some 1)) ((= name "stringStartsWith?") (some 2)) ((= name "stringContains?") (some 2))
    ((= name "eprintln") (some -1)) ((= name "fileWrite") (some 2)) ((= name "fileAppend") (some 2))
    ((= name "fileLock") (some 2)) ((= name "fileLockWait") (some -1)) ((= name "dirList") (some 1))
    ((= name "fileStat") (some 1)) ((= name "processRun") (some 1)) ((= name "processSpawn") (some 1))
    ((= name "processWait") (some 2)) ((= name "fileReadRange") (some 3)) ((= name "getHomeDir") (some 0))
    ((= name "fileCreateExclusive") (some 2)) ((= name "fileChmod") (some 2)) ((= name "fileFsync") (some 1))
    ((= name "fileLstat") (some 1)) ((= name "pathSymlink") (some 2)) ((= name "fileUtime") (some 2))
    ((= name "bytesAlloc") (some 1)) ((= name "bytesGet") (some 2)) ((= name "bytesSet") (some 3))
    ((= name "bytesGetFloat64") (some 2)) ((= name "bytesSetFloat64") (some 3)) ((= name "stringToBytes") (some 1))
    ((= name "partial") (some -1)) ((= name "i64ArrayLen") (some 1)) ((= name "i64ArrayGet") (some 2))
    ((= name "i64ArraySlice") (some 3)) ((= name "i64ArrayConcat") (some 1)) ((= name "i64ArrayGenerate") (some 2))
    ((= name "i64ArraySum") (some 1)) ((= name "i64ArrayCountEq") (some 2)) ((= name "i64ArrayFold") (some 3))
    ((= name "i64ArrayScan") (some 3)) ((= name "i8ArrayLen") (some 1)) ((= name "i8ArrayGet") (some 2))
    ((= name "i8ArraySlice") (some 3)) ((= name "i8ArrayConcat") (some 1)) ((= name "i8ArrayGenerate") (some 2))
    ((= name "i8ArraySum") (some 1)) ((= name "i8ArrayCountEq") (some 2)) ((= name "i8ArrayFold") (some 3))
    ((= name "i8ArrayScan") (some 3)) ((= name "envGet") (some 1)) ((= name "dirCreate") (some 1))
    ((= name "pathRemove") (some 1)) ((= name "pathRename") (some 2)) ((= name "monotonicNs") (some 0))
    ((= name "nowNs") (some 0)) ((= name "sleepMs") (some 1)) ((= name "fdRead") (some 2))
    ((= name "fdWrite") (some 2)) ((= name "fdClose") (some 1)) ((= name "envList") (some 0))
    ((= name "procSpawnv") (some 3)) ((= name "procPoll") (some 3)) ((= name "procExecv") (some 2))
    ((= name "procSelf") (some 0)) ((= name "procExePath") (some 0)) ((= name "procWaitPid") (some 2))
    ((= name "procKill") (some 2)) ((= name "fdPoll") (some 2)) ((= name "fdNonBlocking") (some 2))
    ((= name "cpuCount") (some 0)) ((= name "platformInfo") (some 0)) ((= name "localDate") (some 0))
    ((= name "procAlive?") (some 1)) ((= name "fileLockAt") (some 3)) ((= name "fileReadAt") (some 2))
    ((= name "fileWriteAt") (some 3)) ((= name "procWaitAny") (some 2)) ((= name "procRusage") (some 0))
    ((= name "sqrt") (some 1)) ((= name "floor") (some 1)) ((= name "ceil") (some 1))
    ((= name "round") (some 1)) ((= name "clamp") (some 3)) ((= name "pow") (some 2))
    ((= name "exp") (some 1)) ((= name "log") (some 1)) ((= name "log2") (some 1))
    ((= name "log10") (some 1)) ((= name "sin") (some 1)) ((= name "cos") (some 1))
    ((= name "tan") (some 1)) ((= name "atan2") (some 2)) ((= name "tcpListen") (some 1))
    ((= name "tcpConnect") (some 1)) ((= name "sockAccept") (some 1)) ((= name "sockLocalPort") (some 1))
    ((= name "unixListen") (some 1)) ((= name "unixConnect") (some 1)) ((= name "unixSocketPair") (some 0))
    ((= name "sockSendFd") (some 2)) ((= name "sockRecvFd") (some 1)) ((= name "f64ArrayLen") (some 1))
    ((= name "f64ArrayGet") (some 2)) ((= name "f64ArrayGenerate") (some 2)) ((= name "f64ArraySlice") (some 3))
    ((= name "f64ArrayConcat") (some 1)) ((= name "f64ArraySum") (some 1)) ((= name "f64ArrayCountEq") (some 2))
    ((= name "f64ArrayFold") (some 3)) ((= name "f64ArrayScan") (some 3)) ((= name "dot") (some 2))
    ((= name "axpy") (some 3)) ((= name "gemm") (some 5)) ((= name "parquetOpen") (some 1))
    ((= name "parquetNumRowGroups") (some 1)) ((= name "parquetNumRows") (some 1)) ((= name "parquetColumnType") (some 2))
    ((= name "parquetReadF64") (some 3)) ((= name "parquetReadI64") (some 3)) ((= name "parquetReadI8") (some 3))
    ((= name "parquetKvMetadata") (some 2))
    (else none))

fn builtinAltArity name: String -> (Option Int64)
  (cond ((= name "parMap") (some 2)) ((= name "parFold") (some 4)) (else none))

fn builtinArityFor name: String argc: Int64 -> (Option Int64)
  (let [(alt (builtinAltArity name))
        (altMatch (if (= (optionOr alt -1) argc) alt (none)))]
    (mt (builtinArity name)
      ((none) altMatch)
      ((some a) (if (or (< a 0) (= a argc)) (some a) altMatch))))

fn locus ctx: LowerCtx -> String
  (str ctx.fnName "@" ctx.pos)

fn lowerDiag ctx: LowerCtx code: String what: String -> ty/IrDiag
  (ty/makeIrDiag code (str what " in '" ctx.fnName "' at " ctx.pos) (locus ctx))

fn unsupported ctx: LowerCtx construct: String why: String -> ty/IrDiag
  (lowerDiag ctx "ERR_LOWER_UNSUPPORTED" (str "'" construct "' " why))

fn outside ctx: LowerCtx construct: String -> ty/IrDiag
  (unsupported ctx construct "is outside the lowered subset")

fn symbolOf ctx: LowerCtx name: String -> String
  (optionOr (mapGet ctx.info.targets name) name)

fn qualified? name: String -> Bool
  (mt (stringIndexOf name "/")
    ((some i) (and (> i 0) (< (+ i 1) (stringLength name))))
    ((none) false))

fn qualifiedDiag ctx: LowerCtx name: String -> ty/IrDiag
  (let [(i (optionOr (stringIndexOf name "/") 0))
        (alias (optionOr (stringSlice name 0 i) ""))
        (member (optionOr (stringSlice name (+ i 1) (stringLength name)) ""))]
    (mt (mapGet ctx.info.aliases alias)
      ((none) (lowerDiag ctx "ERR_LOWER_UNKNOWN_ALIAS" (str "'" name "' names the alias '" alias "', which the module does not import")))
      ((some m) (if (mapHas? ctx.info.hidden name)
                  (lowerDiag ctx "ERR_LOWER_UNEXPORTED" (str "'" name "': module " m " does not export '" member "'"))
                  (lowerDiag ctx "ERR_LOWER_UNKNOWN_SYMBOL" (str "'" name "': module " m " declares no '" member "'"))))))

fn tailOf xs: (List rd/SExpr) -> (List rd/SExpr)
  (optionOr (listTail xs) (list))

fn nthOf xs: (List rd/SExpr) i: Int64 -> rd/SExpr
  (optionOr (listGet xs i) (rd/makeAtom ""))

fn stateWith st: LowerState next: Int64 labels: Int64 strings: StringPool -> LowerState
  (with st :next next :labels labels :strings strings)

fn typeIndexHeight tree: TypeIndex -> Int64
  (mt tree
    ((typeIndexEmpty) 0)
    ((typeIndexNode _ _ _ _ height) height))

fn typeIndexNodeOf key: String value: V left: TypeIndex right: TypeIndex -> TypeIndex
  (typeIndexNode key value left right (+ 1 (max (typeIndexHeight left) (typeIndexHeight right))))

fn typeIndexBalance key: String value: V left: TypeIndex right: TypeIndex -> TypeIndex
  (let [(lh (typeIndexHeight left)) (rh (typeIndexHeight right))]
    (cond
      ((> lh (+ rh 1))
        (mt left
          ((typeIndexEmpty) (typeIndexNodeOf key value left right))
          ((typeIndexNode leftKey leftValue leftLeft leftRight _)
            (if (>= (typeIndexHeight leftLeft) (typeIndexHeight leftRight))
              (typeIndexNodeOf leftKey leftValue leftLeft (typeIndexNodeOf key value leftRight right))
              (mt leftRight
                ((typeIndexEmpty) (typeIndexNodeOf key value left right))
                ((typeIndexNode pivotKey pivotValue pivotLeft pivotRight _)
                  (typeIndexNodeOf pivotKey pivotValue
                    (typeIndexNodeOf leftKey leftValue leftLeft pivotLeft)
                    (typeIndexNodeOf key value pivotRight right))))))))
      ((> rh (+ lh 1))
        (mt right
          ((typeIndexEmpty) (typeIndexNodeOf key value left right))
          ((typeIndexNode rightKey rightValue rightLeft rightRight _)
            (if (>= (typeIndexHeight rightRight) (typeIndexHeight rightLeft))
              (typeIndexNodeOf rightKey rightValue (typeIndexNodeOf key value left rightLeft) rightRight)
              (mt rightLeft
                ((typeIndexEmpty) (typeIndexNodeOf key value left right))
                ((typeIndexNode pivotKey pivotValue pivotLeft pivotRight _)
                  (typeIndexNodeOf pivotKey pivotValue
                    (typeIndexNodeOf key value left pivotLeft)
                    (typeIndexNodeOf rightKey rightValue pivotRight rightRight))))))))
      (else (typeIndexNodeOf key value left right))))

fn typeIndexSet tree: TypeIndex key: String value: V -> TypeIndex
  (mt tree
    ((typeIndexEmpty) (typeIndexNodeOf key value (typeIndexEmpty) (typeIndexEmpty)))
    ((typeIndexNode currentKey currentValue left right _)
      (cond
        ((= key currentKey) (typeIndexNodeOf key value left right))
        ((< key currentKey) (typeIndexBalance currentKey currentValue (typeIndexSet left key value) right))
        (else (typeIndexBalance currentKey currentValue left (typeIndexSet right key value))))))

fn typeIndexGet tree: TypeIndex key: String -> (Option V)
  (mt tree
    ((typeIndexEmpty) (none))
    ((typeIndexNode currentKey value left right _)
      (cond
        ((= key currentKey) (some value))
        ((< key currentKey) (typeIndexGet left key))
        (else (typeIndexGet right key)))))

fn typeIndexHas? tree: TypeIndex key: String -> Bool
  (some? (typeIndexGet tree key))

fn typeIndexAdd tree: TypeIndex key: String n: Int64 -> TypeIndex
  (typeIndexSet tree key (+ n (optionOr (typeIndexGet tree key) 0)))

fn typeFromName name: String -> ty/SsaTy
  (cond
    ((= name "i64") (ty/tyI64))
    ((= name "f64") (ty/tyF64))
    ((= name "i1") (ty/tyI1))
    ((= name "ptr") (ty/tyPtr))
    ((= name "i32") (ty/tyI32))
    ((stringStartsWith? name "rec:") (ty/tyRec (optionOr (stringSlice name 4 (stringLength name)) "")))
    (else (ty/tyVal)))

fn valueName n: Int64 -> String
  (str "%" (stringFromInt64 n))

fn withType st: LowerState v: String t: ty/SsaTy -> LowerState
  (with st :types (mt t ((ty/tyVal) st.types) (_ (typeIndexSet st.types v (ty/ssaTyName t)))))

fn tagCurrent st: LowerState v: String t: ty/SsaTy -> LowerState
  (with st :instrs (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr (if (= i.dest v) (ty/ssaInstr v t i.op) i)) st.instrs))

fn tyOf st: LowerState v: String -> ty/SsaTy
  (typeFromName (optionOr (typeIndexGet st.types v) "val"))

fn emitAs st: LowerState t: ty/SsaTy op: ty/SsaOp -> Lowered
  (let [(dest (valueName st.next))]
    (Lowered :st (withType (with st :next (+ st.next 1) :instrs (cons (ty/ssaInstr dest t op) st.instrs))
                           dest t)
             :value dest))

fn emit st: LowerState op: ty/SsaOp -> Lowered
  (emitAs st (ty/tyVal) op)

fn coerce st: LowerState v: String want: ty/SsaTy -> Lowered
  (let [(have (tyOf st v))
        (twin (optionOr (typeIndexGet st.twins v) ""))]
    (cond
      ((= (ty/ssaAbiName have) (ty/ssaAbiName want)) (Lowered :st st :value v))
      ((and (not (stringEmpty? twin)) (= (ty/ssaAbiName (tyOf st twin)) (ty/ssaAbiName want))) (Lowered :st st :value twin))
      ((not (ty/ssaIsRaw? want)) (twinOf (emit st (ty/opBox v)) v))
      ((not (ty/ssaIsRaw? have)) (twinOf (emitAs st want (ty/opUnbox v)) v))
      (else (let [(boxed (emit st (ty/opBox v)))] (emitAs boxed.st want (ty/opUnbox boxed.value))))))

fn twinOf r: Lowered source: String -> Lowered
  (let [(st r.st)]
    (with r :st (LowerState :next st.next :labels st.labels :strings st.strings :done st.done :label st.label :params st.params :instrs st.instrs :lifted st.lifted :lambdas st.lambdas :types st.types :twins (typeIndexSet st.twins r.value source))))

fn coerceAll st: LowerState vs: (List String) wants: (List ty/SsaTy) -> LoweredList
  (mt (listHead vs)
    ((none) (LoweredList :st st :values (list)))
    ((some v) (let [(c (coerce st v (optionOr (listHead wants) (ty/tyVal))))
                    (rest (coerceAll c.st (optionOr (listTail vs) (list)) (optionOr (listTail wants) (list))))]
                (LoweredList :st rest.st :values (cons c.value rest.values)))))

fn boxAll st: LowerState vs: (List String) -> LoweredList
  (coerceAll st vs (list))

fn condition st: LowerState v: String -> Lowered
  (if (= (ty/ssaTyName (tyOf st v)) "i64")
    (emit st (ty/opBox v))
    (if (= (ty/ssaTyName (tyOf st v)) "f64") (emit st (ty/opBox v)) (Lowered :st st :value v)))

fn fresh st: LowerState -> Lowered
  (Lowered :st (stateWith st (+ st.next 1) st.labels st.strings) :value (valueName st.next))

fn closeBlock st: LowerState term: ty/SsaTerm nextLabel: String nextParams: (List ty/SsaParam) -> LowerState
  (with st :done (cons (ty/ssaBlock st.label st.params (listReverse st.instrs) term) st.done) :label nextLabel :params nextParams :instrs (list))

fn jumpTo target: String value: String -> ty/SsaTerm
  (ty/termJump (ty/ssaEdge target (list value)))

fn poolOf strings: (List String) -> StringPool
  (fold (fn [(pool StringPool) (s String)] -> StringPool (StringPool :items (cons s pool.items) :count (+ pool.count 1) :index (if (typeIndexHas? pool.index s) pool.index (typeIndexSet pool.index s pool.count)))) (StringPool :items (list) :count 0 :index (typeIndexEmpty)) strings)

fn poolAdd pool: StringPool s: String -> (Pair StringPool Int64)
  (mt (typeIndexGet pool.index s)
    ((some i) (pair pool i))
    ((none) (pair (StringPool :items (cons s pool.items) :count (+ pool.count 1) :index (typeIndexSet pool.index s pool.count)) pool.count)))

fn poolList pool: StringPool -> (List String)
  (listReverse pool.items)

fn intern st: LowerState s: String -> (Pair LowerState Int64)
  (let [(added (poolAdd st.strings s))]
    (pair (stateWith st st.next st.labels (pairFirst added)) (pairSecond added)))

fn allChars? allowed: String s: String -> Bool
  (and (not (stringEmpty? s)) (fold (fn [(acc Bool) (c String)] -> Bool (and acc (stringContains? allowed c))) true (stringChars s)))

fn digits? s: String -> Bool
  (allChars? "0123456789" s)

fn unsigned s: String -> String
  (if (or (stringStartsWith? s "-") (stringStartsWith? s "+")) (optionOr (stringSlice s 1 (stringLength s)) "") s)

fn mantissaText? s: String -> Bool
  (let [(parts (stringSplit s "."))]
    (or (and (= (listLength parts) 1) (digits? s))
        (and (= (listLength parts) 2) (and (digits? (optionOr (listGet parts 0) "")) (digits? (optionOr (listGet parts 1) ""))))))

fn floatText? s: String -> Bool
  (let [(parts (stringSplit (stringReplace (unsigned s) "E" "e") "e"))
        (mantissa (optionOr (listGet parts 0) ""))]
    (cond
      ((= (listLength parts) 1) (and (stringContains? mantissa ".") (mantissaText? mantissa)))
      ((= (listLength parts) 2) (and (mantissaText? mantissa) (digits? (unsigned (optionOr (listGet parts 1) "")))))
      (else false)))

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn byteChar n: Int64 -> String
  (optionOr (stringSlice (byteTable) n (+ n 1)) "")

fn hexOf cs: (List String) -> Int64
  (fold (fn [(acc Int64) (c String)] -> Int64
          (let [(d (optionOr (stringIndexOf "0123456789abcdef" (stringLower c)) -1))]
            (if (or (< acc 0) (or (< d 0) (!= (stringLength c) 1))) -1 (+ (* acc 16) d))))
        0 cs)

fn utf8Of cp: Int64 -> String
  (cond
    ((< cp 128) (byteChar cp))
    ((< cp 2048) (str (byteChar (+ 192 (/ cp 64))) (byteChar (+ 128 (mod cp 64)))))
    ((< cp 65536) (str (byteChar (+ 224 (/ cp 4096))) (byteChar (+ 128 (mod (/ cp 64) 64))) (byteChar (+ 128 (mod cp 64)))))
    (else (str (byteChar (+ 240 (/ cp 262144))) (byteChar (+ 128 (mod (/ cp 4096) 64))) (byteChar (+ 128 (mod (/ cp 64) 64))) (byteChar (+ 128 (mod cp 64))))))

fn dropChars cs: (List String) n: Int64 -> (List String)
  (optionOr (listSlice cs n (listLength cs)) (list))

fn hexEscape cs: (List String) width: Int64 -> Int64
  (if (< (listLength cs) width) -1 (hexOf (optionOr (listSlice cs 0 width) (list))))

fn scalarValue? cp: Int64 -> Bool
  (and (>= cp 0) (and (<= cp 1114111) (or (< cp 55296) (> cp 57343))))

fn unicodeEscape cs: (List String) -> (Pair Int64 Int64)
  (let [(width (if (= (optionOr (listHead cs) "") "{") (optionOr (listIndexOf cs "}") -1) 4))
        (cp (cond
              ((= width 4) (hexEscape cs 4))
              ((and (>= width 2) (<= width 7)) (hexOf (optionOr (listSlice cs 1 width) (list))))
              (else -1)))]
    (if (scalarValue? cp) (pair cp (if (= width 4) 4 (+ width 1))) (pair -1 0)))

fn unescapeChars cs: (List String) out: String -> (Result String String)
  (mt (listHead cs)
    ((none) (ok out))
    ((some c) (if (!= c "\\")
                (unescapeChars (dropChars cs 1) (str out c))
                (let [(e (optionOr (listGet cs 1) ""))
                      (after (dropChars cs 2))
                      (u (unicodeEscape after))]
                  (cond
                    ((= e "n") (unescapeChars after (str out "\n")))
                    ((= e "t") (unescapeChars after (str out "\t")))
                    ((= e "r") (unescapeChars after (str out "\r")))
                    ((or (= e "\\") (= e "\"")) (unescapeChars after (str out e)))
                    ((and (= e "x") (>= (hexEscape after 2) 0)) (unescapeChars (dropChars after 2) (str out (byteChar (hexEscape after 2)))))
                    ((= e "x") (err "\\x needs exactly 2 hex digits"))
                    ((and (= e "u") (>= (pairFirst u) 0)) (unescapeChars (dropChars after (pairSecond u)) (str out (utf8Of (pairFirst u)))))
                    ((= e "u") (err "\\u needs 4 hex digits or {1 to 6 hex digits} naming a scalar value"))
                    (else (err (str "unknown escape \\" e))))))))

fn unescape ctx: LowerCtx text: String -> (Result String ty/IrDiag)
  (let [(n (stringLength text))]
    (if (or (< n 2) (not (stringEndsWith? text "\"")))
      (err (unsupported ctx text "is an unterminated string literal"))
      (mt (unescapeChars (stringChars (optionOr (stringSlice text 1 (- n 1)) "")) "")
        ((ok s) (ok s))
        ((err why) (err (lowerDiag ctx "ERR_BAD_ESCAPE" (str "string literal " text ": " why)))))))

fn constTy c: ty/SsaConst -> ty/SsaTy
  (mt c ((ty/constInt _) (ty/tyI64)) ((ty/constFloat _) (ty/tyF64)) ((ty/constBool _) (ty/tyI1)) (_ (ty/tyVal)))

fn constOf st: LowerState c: ty/SsaConst -> (Result Lowered ty/IrDiag)
  (ok (emitAs st (constTy c) (ty/opConst c)))

fn lowerString ctx: LowerCtx st: LowerState v: String -> (Result Lowered ty/IrDiag)
  (mt (unescape ctx v)
    ((err d) (err d))
    ((ok s) (let [(interned (intern st s))]
              (constOf (pairFirst interned) (ty/constStr (pairSecond interned))))))

fn lowerAtom ctx: LowerCtx env: (Map String String) st: LowerState v: String -> (Result Lowered ty/IrDiag)
  (cond
    ((= v "true") (constOf st (ty/constBool true)))
    ((= v "false") (constOf st (ty/constBool false)))
    ((= v "()") (constOf st (ty/constUnit)))
    ((stringStartsWith? v "\"") (lowerString ctx st v))
    ((and (stringStartsWith? v ":") (> (stringLength v) 1)) (constOf st (ty/constKeyword (optionOr (stringSlice v 1 (stringLength v)) ""))))
    ((some? (stringToInt64 v)) (constOf st (ty/constInt (optionOr (stringToInt64 v) 0))))
    ((and (floatText? v) (some? (stringToFloat64 v))) (constOf st (ty/constFloat (optionOr (stringToFloat64 v) 0.0))))
    ((mapHas? env v) (ok (Lowered :st st :value (optionOr (mapGet env v) ""))))
    ((mapHas? ctx.info.arities v) (functionValue ctx env st v (optionOr (mapGet ctx.info.arities v) 0)))
    ((mapHas? ctx.info.late v) (functionValue ctx env st v (optionOr (mapGet ctx.info.late v) 0)))
    ((and (mapHas? ctx.info.ctors v) (= (ctorOf ctx v).arity 0)) (ok (emit st (ty/opConstruct (ctorOf ctx v).typeName (ctorOf ctx v).variant (list)))))
    ((mapHas? ctx.info.ctors v) (liftLambda ctx env st (builtinLambda v (ctorOf ctx v).arity)))
    ((not (stringEmpty? (genericAlias v))) (lowerAtom ctx env st (genericAlias v)))
    ((and (genericMulti? v) (not (mapHas? ctx.info.late v))) (err (ambiguousDiag ctx v)))
    ((>= (optionOr (builtinArity v) -1) 0) (liftLambda ctx env st (builtinLambda v (optionOr (builtinArity v) 0))))
    ((and ctx.info.linked (qualified? v)) (err (qualifiedDiag ctx v)))
    (else (err (lowerDiag ctx "ERR_LOWER_UNKNOWN_SYMBOL" (str "unknown symbol '" v "'")))))

fn builtinLambda name: String arity: Int64 -> Lambda
  (let [(params (map (fn [(i Int64)] -> String (str "@" (stringFromInt64 i))) (range 0 arity)))]
    (Lambda :params params :types (list) :body (list (rd/makeList (cons (rd/makeAtom name) (map rd/makeAtom params))))))

fn annotTy t: String -> ty/SsaTy
  (cond ((= t "Int64") (ty/tyI64)) ((= t "Float64") (ty/tyF64)) ((= t "Bool") (ty/tyI1)) ((stringEmpty? t) (ty/tyVal)) (else (ty/tyRec t)))

fn resolveTy info: ModInfo t: ty/SsaTy -> ty/SsaTy
  (mt t
    ((ty/tyRec schema) (mt (mapGet info.records schema)
                         ((none) (ty/tyVal))
                         ((some _) (ty/tyRec (optionOr (mapGet info.targets schema) schema)))))
    (_ t))

fn resolveSig info: ModInfo sig: FnSig -> FnSig
  (FnSig :params (map (fn [(t ty/SsaTy)] -> ty/SsaTy (resolveTy info t)) sig.params) :ret (resolveTy info sig.ret))

fn resolveTyFor info: ModInfo callee: String t: ty/SsaTy -> ty/SsaTy
  (mt t
    ((ty/tyRec schema)
     (if (not (stringContains? callee "/")) (resolveTy info t)
     (fold (fn [(resolved ty/SsaTy) (alias String)] -> ty/SsaTy
             (let [(source (str alias "/" schema))]
               (if (and (stringStartsWith? callee (str alias "/")) (some? (mapGet info.records source)))
                 (resolveTy info (ty/tyRec source))
                 resolved)))
           (resolveTy info t) (mapKeys info.aliases))))
    (_ t))

fn resolveSigFor info: ModInfo callee: String sig: FnSig -> FnSig
  (FnSig :params (map (fn [(t ty/SsaTy)] -> ty/SsaTy (resolveTyFor info callee t)) sig.params) :ret (resolveTyFor info callee sig.ret))

fn sigOf d: ast/DefunNode -> FnSig
  (if (= d.name "main")
    (FnSig :params (map (fn [(p ast/Param)] -> ty/SsaTy (ty/tyVal)) d.params) :ret (ty/tyVal))
    (FnSig :params (map (fn [(p ast/Param)] -> ty/SsaTy (annotTy p.type)) d.params) :ret (annotTy d.retType)))

fn valSig arity: Int64 -> FnSig
  (FnSig :params (map (fn [(i Int64)] -> ty/SsaTy (ty/tyVal)) (range 0 arity)) :ret (ty/tyVal))

fn sigFor ctx: LowerCtx name: String arity: Int64 -> FnSig
  (resolveSigFor ctx.info name (optionOr (mapGet ctx.info.sigs name) (valSig arity)))

fn rawSig? s: FnSig -> Bool
  (or (ty/ssaIsRaw? s.ret) (listAny? (fn [(t ty/SsaTy)] -> Bool (ty/ssaIsRaw? t)) s.params))

fn foreignSymbol? ctx: LowerCtx v: String -> Bool
  (let [(sym (symbolOf ctx v))
        (dot (stringIndexOf ctx.fnName "."))]
    (mt dot
      ((none) false)
      ((some i) (let [(modPrefix (optionOr (stringSlice ctx.fnName 0 (+ i 1)) ""))]
                  (not (stringStartsWith? sym modPrefix))))))

fn functionValue ctx: LowerCtx env: (Map String String) st: LowerState v: String arity: Int64 -> (Result Lowered ty/IrDiag)
  (if (or (rawSig? (sigFor ctx v arity)) (foreignSymbol? ctx v))
    (liftLambda ctx env st (builtinLambda v arity))
    (ok (emit st (ty/opMakeClosure (symbolOf ctx v) (list)))))

fn lowerArgs ctx: LowerCtx env: (Map String String) st: LowerState args: (List rd/SExpr) -> (Result LoweredList ty/IrDiag)
  (mt (listHead args)
    ((none) (ok (LoweredList :st st :values (list))))
    ((some a) (mt (lowerExpr ctx env st a)
                ((err d) (err d))
                ((ok r) (mt (lowerArgs ctx env r.st (tailOf args))
                          ((err d) (err d))
                          ((ok rest) (ok (LoweredList :st rest.st :values (cons r.value rest.values)))))))))

fn lowerSeq ctx: LowerCtx env: (Map String String) st: LowerState forms: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (if (listEmpty? forms)
    (constOf st (ty/constUnit))
    (mt (lowerArgs ctx env st forms)
      ((err d) (err d))
      ((ok r) (ok (Lowered :st r.st :value (optionOr (listGet r.values (- (listLength r.values) 1)) ""))))))

fn sameRecordType st: LowerState values: (List String) -> Bool
  (mt (listHead values)
    ((none) false)
    ((some first) (let [(name (ty/ssaTyName (tyOf st first)))]
                    (and (ty/ssaIsRec? (tyOf st first))
                         (listAll? (fn [(v String)] -> Bool (= (ty/ssaTyName (tyOf st v)) name)) values)))))

fn joinTy st: LowerState values: (List String) -> ty/SsaTy
  (let [(raws (fold (fn [(acc (List String)) (v String)] -> (List String)
                      (let [(n (ty/ssaTyName (tyOf st v)))] (if (or (= n "val") (listContains? acc n)) acc (cons n acc))))
                    (list) values))
        (anyVal (listAny? (fn [(v String)] -> Bool (not (ty/ssaIsRaw? (tyOf st v)))) values))
        (rawTy (listHead (filter (fn [(v String)] -> Bool (ty/ssaIsRaw? (tyOf st v))) values)))]
    (if (sameRecordType st values)
      (tyOf st (optionOr (listHead values) ""))
      (if (or (!= (listLength raws) 1) anyVal)
        (ty/tyVal)
        (mt rawTy ((some v) (tyOf st v)) ((none) (ty/tyVal))))))

fn patchBlock blocks: (List ty/SsaBlock) label: String ins: ty/SsaInstr term: ty/SsaTerm -> (List ty/SsaBlock)
  (mt (listHead blocks)
    ((none) blocks)
    ((some b) (if (= b.label label)
                (cons (ty/ssaBlock label b.params (listAppend b.instrs (list ins)) term) (optionOr (listTail blocks) (list)))
                (cons b (patchBlock (optionOr (listTail blocks) (list)) label ins term)))))

fn convertExit st: LowerState joinL: String exit: (Pair String String) t: ty/SsaTy -> LowerState
  (mt (listHead (filter (fn [(w String)] -> Bool (= (ty/ssaAbiName (tyOf st w)) (ty/ssaAbiName t)))
                        (cons (pairSecond exit) (mt (typeIndexGet st.twins (pairSecond exit)) ((some w) (list w)) ((none) (list))))))
    ((some twin) (with st :done (retargetBlock st.done (pairFirst exit) (jumpTo joinL twin))))
    ((none) (newConvertExit st joinL exit t)))

fn retargetBlock blocks: (List ty/SsaBlock) label: String term: ty/SsaTerm -> (List ty/SsaBlock)
  (mt (listHead blocks)
    ((none) blocks)
    ((some b) (if (= b.label label)
                (cons (ty/ssaBlock label b.params b.instrs term) (optionOr (listTail blocks) (list)))
                (cons b (retargetBlock (optionOr (listTail blocks) (list)) label term)))))

fn newConvertExit st: LowerState joinL: String exit: (Pair String String) t: ty/SsaTy -> LowerState
  (let [(dest (valueName st.next))
        (ins (ty/ssaInstr dest t (if (ty/ssaIsRaw? t) (ty/opUnbox (pairSecond exit)) (ty/opBox (pairSecond exit)))))]
    (withType (with st :next (+ st.next 1) :done (patchBlock st.done (pairFirst exit) ins (jumpTo joinL dest)))
              dest t))

fn joinExits st: LowerState joinL: String exits: (List (Pair String String)) last: String -> Lowered
  (let [(t (joinTy st (listAppend (map pairSecond exits) (list last))))
        (lastC (coerce st last t))
        (patched (fold (fn [(acc LowerState) (e (Pair String String))] -> LowerState
                         (if (= (ty/ssaTyName (tyOf acc (pairSecond e))) (ty/ssaTyName t)) acc (convertExit acc joinL e t)))
                       lastC.st exits))
        (r (fresh patched))]
    (Lowered :st (closeBlock (withType r.st r.value t) (jumpTo joinL lastC.value) joinL (list (ty/ssaParam r.value t))) :value r.value))

fn lowerIf ctx: LowerCtx env: (Map String String) st: LowerState args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (if (!= (listLength args) 3)
    (err (unsupported ctx "if" (str "with " (listLength args) " operand(s) is outside the lowered subset, which takes a condition, a then and an else")))
    (mt (lowerExpr ctx env st (nthOf args 0))
      ((err d) (err d))
      ((ok c0) (let [(cr (condition c0.st c0.value))
                     (k (stringFromInt64 cr.st.labels))
                     (thenL (str "then" k))
                     (elseL (str "else" k))
                     (joinL (str "join" k))
                     (bumped (stateWith cr.st cr.st.next (+ cr.st.labels 1) cr.st.strings))
                     (st1 (closeBlock bumped (ty/termBranch cr.value (ty/ssaEdge thenL (list)) (ty/ssaEdge elseL (list))) thenL (list)))]
                 (mt (lowerExpr ctx env st1 (nthOf args 1))
                   ((err d) (err d))
                   ((ok tr) (mt (lowerExpr ctx env (closeBlock tr.st (jumpTo joinL tr.value) elseL (list)) (nthOf args 2))
                              ((err d) (err d))
                              ((ok fr) (ok (joinExits fr.st joinL (list (pair tr.st.label tr.value)) fr.value))))))))))

fn elseTest? e: rd/SExpr -> Bool
  (and (rd/isAtom? e) (= (rd/sexprHead e) "else"))

fn clauseTest c: rd/SExpr -> rd/SExpr
  (nthOf (rd/sexprToList c) 0)

fn clauseShapeOk? c: rd/SExpr -> Bool
  (and (rd/isList? c) (>= (listLength (rd/sexprToList c)) 2))

fn lowerClauses ctx: LowerCtx env: (Map String String) st: LowerState k: String joinL: String clauses: (List rd/SExpr) i: Int64 exits: (List (Pair String String)) -> (Result Lowered ty/IrDiag)
  (mt (listHead clauses)
    ((none) (let [(u (emit st (ty/opConst (ty/constUnit))))]
              (ok (joinExits u.st joinL exits u.value))))
    ((some c) (let [(test (clauseTest c))
                    (body (tailOf (rd/sexprToList c)))]
                (if (elseTest? test)
                  (mt (lowerSeq ctx env st body)
                    ((err d) (err d))
                    ((ok br) (ok (joinExits br.st joinL exits br.value))))
                  (mt (lowerExpr ctx env st test)
                    ((err d) (err d))
                    ((ok t0) (let [(tr (condition t0.st t0.value))
                                   (n (stringFromInt64 i))
                                   (caseL (str "case" k "." n))
                                   (nextL (str "next" k "." n))
                                   (st1 (closeBlock tr.st (ty/termBranch tr.value (ty/ssaEdge caseL (list)) (ty/ssaEdge nextL (list))) caseL (list)))]
                               (mt (lowerSeq ctx env st1 body)
                                 ((err d) (err d))
                                 ((ok br) (lowerClauses ctx env (closeBlock br.st (jumpTo joinL br.value) nextL (list)) k joinL (tailOf clauses) (+ i 1) (listAppend exits (list (pair br.st.label br.value)))))))))))))

fn lowerCond ctx: LowerCtx env: (Map String String) st: LowerState clauses: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (let [(n (listLength clauses))
        (elseAt (listIndexOf (map (fn [(c rd/SExpr)] -> Bool (elseTest? (clauseTest c))) clauses) true))]
    (cond
      ((not (fold (fn [(acc Bool) (c rd/SExpr)] -> Bool (and acc (clauseShapeOk? c))) true clauses)) (err (unsupported ctx "cond" "with a clause that is not (test body ...) is outside the lowered subset")))
      ((and (some? elseAt) (!= (optionOr elseAt -1) (- n 1))) (err (unsupported ctx "cond" "with clauses after else is outside the lowered subset")))
      (else (let [(k (stringFromInt64 st.labels))]
               (lowerClauses ctx env (stateWith st st.next (+ st.labels 1) st.strings) k (str "join" k) clauses 0 (list))))))

fn bindingVector e: rd/SExpr -> (Option (List rd/SExpr))
  (cond
    ((rd/isVect? e) (some (rd/sexprToList e)))
    ((and (rd/isList? e) (= (rd/sexprHead e) "list")) (some (tailOf (rd/sexprToList e))))
    (else (none)))

fn pairUp items: (List rd/SExpr) -> (List rd/SExpr)
  (if (< (listLength items) 2)
    items
    (cons (rd/makeList (optionOr (listSlice items 0 2) (list))) (pairUp (optionOr (listSlice items 2 (listLength items)) (list)))))

fn letBindings e: rd/SExpr -> (Option (List rd/SExpr))
  (optionMap (fn [(items (List rd/SExpr))] -> (List rd/SExpr) (if (rd/isAtom? (nthOf items 0)) (pairUp items) items)) (bindingVector e))

fn bindingName b: rd/SExpr -> String
  (let [(items (rd/sexprToList b))
        (name (nthOf items 0))]
    (if (and (rd/isList? b) (and (or (= (listLength items) 2) (= (listLength items) 3)) (and (rd/isAtom? name) (not (stringStartsWith? (rd/sexprHead name) ":")))))
      (rd/sexprHead name)
      ""))

fn bindTyped st: LowerState v: String t: ty/SsaTy -> Lowered
  (cond
    ((ty/ssaIsRaw? t) (coerce st v t))
    ((ty/ssaIsRec? t) (let [(c (coerce st v t))] (Lowered :st (tagCurrent (withType c.st c.value t) c.value t) :value c.value)))
    (else (Lowered :st st :value v)))

fn lowerBindings ctx: LowerCtx env: (Map String String) st: LowerState bindings: (List rd/SExpr) -> (Result Bound ty/IrDiag)
  (mt (listHead bindings)
    ((none) (ok (Bound :st st :env env)))
    ((some b) (let [(name (bindingName b))
                    (items (rd/sexprToList b))
                    (typed (= (listLength items) 3))
                    (init (nthOf items (if typed 2 1)))]
                (cond
                  ((stringEmpty? name) (err (unsupported ctx "let" "with a binding other than (name expr) or (name Type expr) is outside the lowered subset")))
                  ((selfRecursive? name init) (err (unsupported ctx name "is a let-bound lambda that calls itself; recursion through a let-bound lambda is outside the lowered subset, use a module function")))
                  (else (mt (lowerExpr ctx env st init)
                           ((err d) (err d))
                           ((ok r) (let [(bound (if typed (bindTyped r.st r.value (resolveTy ctx.info (annotTy (rd/sexprHead (nthOf items 1))))) r))]
                                     (lowerBindings ctx (mapSet env name bound.value) bound.st (tailOf bindings))))))))))

fn lowerLet ctx: LowerCtx env: (Map String String) st: LowerState args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (mt (letBindings (nthOf args 0))
    ((none) (err (unsupported ctx "let" "without a binding vector is outside the lowered subset")))
    ((some bindings) (if (< (listLength args) 2)
                       (err (unsupported ctx "let" "without a body is outside the lowered subset"))
                       (mt (lowerBindings ctx env st bindings)
                         ((err d) (err d))
                         ((ok bound) (lowerSeq ctx bound.env bound.st (tailOf args)))))))

fn lowerCall ctx: LowerCtx env: (Map String String) st: LowerState name: String arity: Int64 args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (if (!= arity (listLength args))
    (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "'" name "' takes " arity " argument(s), got " (listLength args))))
    (mt (lowerArgs ctx env st args)
      ((err d) (err d))
      ((ok r) (let [(sig (sigFor ctx name arity))
                    (c (coerceAll r.st r.values sig.params))]
                (ok (emitAs c.st sig.ret (ty/opCall (symbolOf ctx name) c.values)))))))

fn lowerBuiltin ctx: LowerCtx env: (Map String String) st: LowerState name: String arity: Int64 args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (if (and (>= arity 0) (and (!= arity (listLength args)) (not (and (= name "-") (= (listLength args) 1)))))
    (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "builtin '" name "' takes " arity " argument(s), got " (listLength args))))
    (mt (lowerArgs ctx env st args)
      ((err d) (err d))
      ((ok r) (ok (typedBuiltin r.st (if (= name "==") "=" name) r.values)))))

fn binaryKind name: String ta: String tb: String -> String
  (cond
    ((= ta tb) (if (= ta "val") "" ta))
    ((or (= name "=") (= name "!=")) "")
    ((and (= tb "val") (or (= ta "i64") (= ta "f64"))) ta)
    ((and (= ta "val") (or (= tb "i64") (= tb "f64"))) tb)
    (else ""))

fn binaryPrim name: String k: String -> String
  (cond
    ((= k "i64") (cond ((= name "+") "addIntHost") ((= name "-") "subIntHost") ((= name "*") "mulIntHost") ((= name "/") "divIntHost") ((= name "mod") "modIntHost")
                       ((= name "<") "ltInt") ((= name "<=") "leInt") ((= name ">") "gtInt") ((= name ">=") "geInt") ((= name "=") "eqInt") ((= name "!=") "neInt") (else "")))
    ((= k "f64") (cond ((= name "+") "addFloat") ((= name "-") "subFloat") ((= name "*") "mulFloat") ((= name "/") "divFloat")
                       ((= name "<") "ltFloat") ((= name "<=") "leFloat") ((= name ">") "gtFloat") ((= name ">=") "geFloat") ((= name "=") "eqFloat") ((= name "!=") "neFloat") (else "")))
    ((= k "i1") (cond ((= name "=") "eqBool") ((= name "!=") "neBool") (else "")))
    (else ""))

fn unaryPrim name: String ta: String -> String
  (cond
    ((and (= name "-") (= ta "i64")) "negIntHost")
    ((and (= name "-") (= ta "f64")) "negFloat")
    ((and (= name "not") (= ta "i1")) "notBool")
    ((and (= name "int64ToFloat64") (= ta "i64")) "intToFloat")
    (else ""))

fn bitPrim name: String ta: String tb: String -> String
  (if (and (= ta "i64") (= tb "i64"))
    (cond ((= name "&") "rawAndI64") ((= name "|") "rawOrI64") ((= name "^") "rawXorI64") ((= name "<<") "rawShlI64") ((= name ">>") "rawAshrI64") (else ""))
    "")

fn preludeBitOp? ctx: LowerCtx name: String -> Bool
  (and (or (= name "&") (= name "|") (= name "^") (= name "~"))
       (and (and (mapHas? ctx.info.arities name) (= (symbolOf ctx name) (str "prelude." name)))
            (let [(sig (sigFor ctx name (if (= name "~") 1 2)))]
              (and (= (listLength sig.params) (if (= name "~") 1 2))
                   (and (= (ty/ssaTyName sig.ret) "i64") (listAll? (fn [(t ty/SsaTy)] -> Bool (= (ty/ssaTyName t) "i64")) sig.params))))))

fn lowerPreludeBit ctx: LowerCtx env: (Map String String) st: LowerState name: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (let [(n (if (= name "~") 1 2))]
    (if (!= n (listLength args))
      (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "'" name "' takes " n " argument(s), got " (listLength args))))
      (mt (lowerArgs ctx env st args)
        ((err d) (err d))
        ((ok r) (let [(c (coerceAll r.st r.values (sigFor ctx name n).params))]
                  (ok (if (= n 1)
                        (notOn c.st (optionOr (listGet c.values 0) ""))
                        (primOn c.st (bitPrim name "i64" "i64") c.values))))))))

fn notOn st: LowerState v: String -> Lowered
  (let [(m (emitAs st (ty/tyI64) (ty/opConst (ty/constInt -1))))]
    (primOn m.st "rawXorI64" (list v m.value)))

fn primOn st: LowerState p: String vs: (List String) -> Lowered
  (let [(sig (optionOr (ty/primSignature p) (ty/SsaPrim :args (list) :result (ty/tyVal))))
        (c (coerceAll st vs sig.args))]
    (emitAs c.st sig.result (ty/opPrim p c.values)))

fn typedBuiltin st: LowerState name: String vs: (List String) -> Lowered
  (let [(n (listLength vs))
        (ta (ty/ssaTyName (tyOf st (optionOr (listGet vs 0) ""))))
        (tb (ty/ssaTyName (tyOf st (optionOr (listGet vs 1) ""))))
        (bits (if (= n 2) (bitPrim name ta tb) ""))
        (binary (if (= n 2) (binaryPrim name (binaryKind name ta tb)) ""))
        (unary (if (= n 1) (unaryPrim name ta) ""))]
    (cond
      ((not (stringEmpty? bits)) (primOn st bits vs))
      ((and (= n 1) (and (= name "~") (= ta "i64"))) (notOn st (optionOr (listGet vs 0) "")))
      ((not (stringEmpty? binary)) (primOn st binary vs))
      ((not (stringEmpty? unary)) (primOn st unary vs))
      (else (mt (ty/builtinEntry name n)
               ((some b) (let [(c (coerceAll st vs b.args))] (emitAs c.st b.result (ty/opEntry name c.values))))
               ((none) (let [(c (boxAll st vs))] (emit c.st (ty/opBuiltin name c.values))))))))

fn joinBool st: LowerState value: String joinL: String -> Lowered
  (let [(r (fresh st))]
    (Lowered :st (closeBlock (withType r.st r.value (ty/tyI1)) (jumpTo joinL value) joinL (list (ty/ssaParam r.value (ty/tyI1)))) :value r.value))

fn bumpLabels st: LowerState -> LowerState
  (stateWith st st.next (+ st.labels 1) st.strings)

fn lowerLogicChain ctx: LowerCtx env: (Map String String) st: LowerState isAnd: Bool k: String operands: (List rd/SExpr) i: Int64 -> (Result Lowered ty/IrDiag)
  (mt (lowerExpr ctx env st (nthOf operands 0))
    ((err d) (err d))
    ((ok r0) (let [(r (coerce r0.st r0.value (ty/tyI1)))
                  (joinL (str "join" k))
                  (rest (tailOf operands))]
              (if (listEmpty? rest)
                (ok (joinBool r.st r.value joinL))
                (let [(rhsL (str "rhs" k "." (stringFromInt64 i)))
                      (onward (ty/ssaEdge rhsL (list)))
                      (decided (ty/ssaEdge joinL (list r.value)))
                      (term (if isAnd (ty/termBranch r.value onward decided) (ty/termBranch r.value decided onward)))]
                  (lowerLogicChain ctx env (closeBlock r.st term rhsL (list)) isAnd k rest (+ i 1)))))))

fn lowerLogic ctx: LowerCtx env: (Map String String) st: LowerState isAnd: Bool operands: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (if (listEmpty? operands)
    (constOf st (ty/constBool isAnd))
    (lowerLogicChain ctx env (bumpLabels st) isAnd (stringFromInt64 st.labels) operands 1))

fn ctorOf ctx: LowerCtx name: String -> Ctor
  (optionOr (mapGet ctx.info.ctors name) (Ctor :typeName "" :variant "" :arity 0))

fn lowerConstruct ctx: LowerCtx env: (Map String String) st: LowerState name: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (let [(c (ctorOf ctx name))]
    (if (!= c.arity (listLength args))
      (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "constructor '" name "' of " c.typeName " takes " c.arity " field(s), got " (listLength args))))
      (mt (lowerArgs ctx env st args)
        ((err d) (err d))
        ((ok r) (let [(b (boxAll r.st r.values))]
                  (ok (emit b.st (ty/opConstruct c.typeName c.variant b.values))))))))

fn keyedExprs ctx: LowerCtx schemaName: String declared: (List String) args: (List rd/SExpr) -> (Result (List KeyedExpr) ty/IrDiag)
  (mt (listHead args)
    ((none) (ok (list)))
    ((some k) (let [(key (rd/sexprHead k))
                    (items (rd/sexprToList k))
                    (nestedKey (optionOr (listGet items 1) (rd/makeAtom "")))
                    (questionBase (if (and (rd/isList? k) (= key "mt")) (rd/sexprHead nestedKey) ""))
                    (questionField (and (stringStartsWith? questionBase ":")
                                        (listContains? declared (str (optionOr (stringSlice questionBase 1 (stringLength questionBase)) "") "?"))))
                    (nestedPair (and (rd/isList? k) (not (= key "mt")) (> (listLength items) 1)))
                    (value (if nestedPair (listGet items 1) (listGet args 1)))
                    (rest (if nestedPair (tailOf args) (tailOf (tailOf args))))
                    (field (if questionField (str (optionOr (stringSlice questionBase 1 (stringLength questionBase)) "") "?")
                              (if nestedPair (let [(nestedName (rd/sexprHead (optionOr (listHead items) (rd/makeAtom ""))))]
                                               (if (stringStartsWith? nestedName ":") (optionOr (stringSlice nestedName 1 (stringLength nestedName)) "") nestedName))
                                (if (stringStartsWith? key ":") (optionOr (stringSlice key 1 (stringLength key)) "") key))))]
                (cond
                  ((and (rd/isAtom? k) (and (not (stringEmpty? key)) (and (not (stringStartsWith? key ":")) (not (listContains? declared key)))))
                   (err (lowerDiag ctx "ERR_LOWER_POSITIONAL_RECORD" (str "positional record literal: write " (keyedLiteral schemaName declared args)))))
                  ((or (stringEmpty? key) (not (some? value)))
                   (err (unsupported ctx schemaName "construction other than :field value pairs is outside the lowered subset")))
                  (else
                  (mt (keyedExprs ctx schemaName declared rest)
                    ((err d) (err d))
                    ((ok pairs) (ok (cons (KeyedExpr :key field :expr (optionOr value (rd/makeAtom ""))) pairs)))))))))

fn keyedLiteral schemaName: String declared: (List String) args: (List rd/SExpr) -> String
  (let [(pairs (fold (fn [(acc (List String)) (f String)] -> (List String)
                       (mt (listGet args (listLength acc))
                         ((some v) (listAppend acc (list (str ":" f " " (rd/renderSexpr v)))))
                         ((none) acc)))
                     (list) declared))]
    (str "(" schemaName (if (listEmpty? pairs) "" (str " " (stringJoin pairs " "))) ")"))

fn hasDuplicates xs: (List String) seen: (Map String Bool) -> Bool
  (mt (listHead xs)
    ((none) false)
    ((some x) (if (mapHas? seen x) true (hasDuplicates (optionOr (listTail xs) (list)) (mapSet seen x true)))))

fn recordFieldDiag ctx: LowerCtx schemaName: String declared: (List String) keys: (List String) -> (Option ty/IrDiag)
  (let [(unknown (filter (fn [(k String)] -> Bool (not (listContains? declared k))) keys))
        (duplicates (hasDuplicates keys (mapEmpty)))]
    (cond
      ((not (listEmpty? unknown)) (some (lowerDiag ctx "ERR_LOWER_UNKNOWN_FIELD" (str "schema '" schemaName "' has no field '" (optionOr (listHead unknown) "") "'"))))
      (duplicates (some (lowerDiag ctx "ERR_LOWER_DUPLICATE_FIELD" (str "schema '" schemaName "' construction repeats a field"))))
      (else (none))))

fn lowerRecord ctx: LowerCtx env: (Map String String) st: LowerState name: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (let [(declared (optionOr (mapGet ctx.info.records name) (list)))
        (sDefaults (optionOr (mapGet ctx.info.defaults name) (mapEmpty)))]
    (mt (keyedExprs ctx name declared args)
      ((err d) (err d))
      ((ok pairs)
       (let [(keys (map (fn [(p KeyedExpr)] -> String p.key) pairs))]
         (mt (recordFieldDiag ctx name declared keys)
           ((some d) (err d))
           ((none)
            (let [(missing (filter (fn [(f String)] -> Bool (not (listContains? keys f))) declared))
                  (defaultPairs (map (fn [(f String)] -> KeyedExpr
                                       (KeyedExpr :key f :expr (optionOr (mapGet sDefaults f) (rd/makeAtom "()"))))
                                     (filter (fn [(f String)] -> Bool (mapHas? sDefaults f)) missing)))
                  (allPairs (listAppend pairs defaultPairs))
                  (allKeys (map (fn [(p KeyedExpr)] -> String p.key) allPairs))]
              (mt (lowerArgs ctx env st (map (fn [(p KeyedExpr)] -> rd/SExpr p.expr) allPairs))
                ((err d) (err d))
                ((ok r)
                 (let [(byKey (mapFromPairs (map (fn [(i Int64)] -> (Pair String String)
                                                   (pair (optionOr (listGet allKeys i) "") (optionOr (listGet r.values i) "")))
                                                 (range 0 (listLength allKeys)))))
                       (present (filter (fn [(f String)] -> Bool (mapHas? byKey f)) declared))
                       (b (boxAll r.st (map (fn [(f String)] -> String (optionOr (mapGet byKey f) "")) present)))]
                   (ok (emit b.st (ty/opRecord (symbolOf ctx name) present b.values)))))))))))))

fn lowerField ctx: LowerCtx env: (Map String String) st: LowerState name: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (if (!= (listLength args) 1)
    (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "field access '" name "' takes 1 argument, got " (listLength args))))
    (mt (lowerExpr ctx env st (nthOf args 0))
      ((err d) (err d))
      ((ok r0) (let [(field (optionOr (stringSlice name 2 (stringLength name)) ""))
                     (raw (mt (tyOf r0.st r0.value)
                            ((ty/tyRec schema) (mt (mapGet ctx.info.sigs (fieldSigKey schema field)) ((some sig) (some sig.ret)) ((none) (none))))
                            (_ (none))))
                     (r (coerce r0.st r0.value (ty/tyVal)))
                     (read (emit r.st (ty/opField r.value field)))]
                 (mt raw
                   ((none) (ok read))
                   ((some t) (ok (coerce read.st read.value t))))))))

fn bindName? e: rd/SExpr -> Bool
  (and (rd/isAtom? e) (let [(v (rd/sexprHead e))] (and (not (stringEmpty? v)) (and (not (stringStartsWith? v ":")) (and (not (stringStartsWith? v "\"")) (none? (stringToInt64 v)))))))

fn armFamily ctx: LowerCtx bare: Bool arm: rd/SExpr -> String
  (let [(pat (nthOf (rd/sexprToList arm) 0))
        (head (if bare (if (rd/isAtom? pat) (rd/sexprHead pat) "") (if (and (rd/isList? pat) (rd/isAtom? (nthOf (rd/sexprToList pat) 0))) (rd/sexprHead pat) "")))]
    (if (and (rd/isList? arm) (mapHas? ctx.info.ctors head)) (ctorOf ctx head).typeName ""))

fn matchFamily ctx: LowerCtx arms: (List rd/SExpr) -> String
  (let [(firstOf (fn [(bare Bool)] -> String (fold (fn [(acc String) (arm rd/SExpr)] -> String (if (= acc "") (armFamily ctx bare arm) acc)) "" arms)))
        (applied (firstOf false))]
    (if (= applied "") (firstOf true) applied))

fn classifyArm ctx: LowerCtx kw: String family: String arm: rd/SExpr -> (Result Arm ty/IrDiag)
  (let [(items (rd/sexprToList arm))
        (pat (nthOf items 0))
        (body (tailOf items))
        (head (rd/sexprHead pat))]
    (cond
      ((or (not (rd/isList? arm)) (< (listLength items) 2)) (err (unsupported ctx kw "with an arm that is not (pattern body ...) is outside the lowered subset")))
      ((and (rd/isAtom? pat) (or (= head "_") (= head "else"))) (ok (Arm :kind "wild" :variant "" :typeName "" :binds (list) :name "" :body body)))
      ((and (rd/isAtom? pat) (and (mapHas? ctx.info.ctors head) (= (ctorOf ctx head).typeName family))) (let [(c (ctorOf ctx head))] (if (!= c.arity 0) (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "pattern '" head "' of " c.typeName " binds 0 field(s), the variant has " c.arity))) (ok (Arm :kind "ctor" :variant c.variant :typeName c.typeName :binds (list) :name "" :body body)))))
      ((bindName? pat) (ok (Arm :kind "var" :variant "" :typeName "" :binds (list) :name head :body body)))
      ((not (and (rd/isList? pat) (rd/isAtom? (nthOf (rd/sexprToList pat) 0)))) (err (unsupported ctx (rd/renderSexpr pat) "is a pattern outside the lowered subset, which takes (constructor name ...), _ or a name")))
      ((and (qualified? head) (not (mapHas? ctx.info.ctors head))) (err (if ctx.info.linked (qualifiedDiag ctx head) (unsupported ctx head "is an imported constructor, outside the lowered subset"))))
      ((not (mapHas? ctx.info.ctors head)) (err (lowerDiag ctx "ERR_LOWER_UNKNOWN_CONSTRUCTOR" (str "unknown constructor '" head "' in a " kw " pattern"))))
      (else (let [(fields (tailOf (rd/sexprToList pat)))
                   (c (ctorOf ctx head))]
               (cond
                 ((!= (listLength fields) c.arity) (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "pattern '" head "' of " c.typeName " binds " (listLength fields) " field(s), the variant has " c.arity))))
                 ((not (fold (fn [(acc Bool) (f rd/SExpr)] -> Bool (and acc (bindName? f))) true fields)) (err (unsupported ctx head "with a nested payload pattern is outside the lowered subset, which binds names or _")))
                 (else (ok (Arm :kind "ctor" :variant c.variant :typeName c.typeName :binds (map rd/sexprHead fields) :name "" :body body))))))))

fn classifyArms ctx: LowerCtx kw: String family: String arms: (List rd/SExpr) -> (Result (List Arm) ty/IrDiag)
  (mt (listHead arms)
    ((none) (ok (list)))
    ((some a) (mt (classifyArm ctx kw family a)
                ((err d) (err d))
                ((ok arm) (mt (classifyArms ctx kw family (tailOf arms))
                            ((err d) (err d))
                            ((ok rest) (ok (cons arm rest))))))))

fn matchShapeDiag ctx: LowerCtx kw: String arms: (List Arm) -> (Option ty/IrDiag)
  (let [(ctorArms (filter (fn [(a Arm)] -> Bool (= a.kind "ctor")) arms))
        (variants (map (fn [(a Arm)] -> String a.variant) ctorArms))
        (typeName (mt (listHead ctorArms) ((some a) a.typeName) ((none) "")))
        (catchAt (listIndexOf (map (fn [(a Arm)] -> Bool (!= a.kind "ctor")) arms) true))
        (foreign (map (fn [(a Arm)] -> String a.typeName) (filter (fn [(a Arm)] -> Bool (!= a.typeName typeName)) ctorArms)))
        (repeated (filter (fn [(i Int64)] -> Bool (listContains? (optionOr (listSlice variants 0 i) (list)) (optionOr (listGet variants i) ""))) (range 0 (listLength variants))))]
    (cond
      ((not (listEmpty? foreign)) (some (lowerDiag ctx "ERR_LOWER_PATTERN_TYPE" (str kw " arms mix constructors of '" typeName "' and '" (optionOr (listHead foreign) "") "'"))))
      ((not (listEmpty? repeated)) (some (lowerDiag ctx "ERR_LOWER_DUPLICATE_ARM" (str kw " repeats the arm for '" (optionOr (listGet variants (optionOr (listHead repeated) 0)) "") "'"))))
      (else (none))))

fn missingVariants ctx: LowerCtx arms: (List Arm) -> (List String)
  (let [(ctorArms (filter (fn [(a Arm)] -> Bool (= a.kind "ctor")) arms))
        (variants (map (fn [(a Arm)] -> String a.variant) ctorArms))
        (typeName (mt (listHead ctorArms) ((some a) a.typeName) ((none) "")))
        (declared (optionOr (mapGet ctx.info.variants typeName) (list)))]
    (filter (fn [(v String)] -> Bool (not (listContains? variants v))) declared))

fn withTrapBlock st: LowerState label: String -> LowerState
  (with st :done (cons (ty/ssaBlock label (list) (list) (ty/termUnreachable)) st.done))

fn lowerNoArms scrutinee: Lowered -> (Result Lowered ty/IrDiag)
  (let [(k (stringFromInt64 scrutinee.st.labels))]
    (constOf (closeBlock (bumpLabels scrutinee.st) (ty/termUnreachable) (str "dead" k) (list)) (ty/constUnit)))

fn bindPayload st: LowerState env: (Map String String) scrutinee: String binds: (List String) i: Int64 -> Bound
  (mt (listHead binds)
    ((none) (Bound :st st :env env))
    ((some b) (if (= b "_")
                (bindPayload st env scrutinee (optionOr (listTail binds) (list)) (+ i 1))
                (let [(r (emit st (ty/opVariantField scrutinee i)))]
                  (bindPayload r.st (mapSet env b r.value) scrutinee (optionOr (listTail binds) (list)) (+ i 1))))))

fn armLabel k: String i: Int64 -> String
  (str "arm" k "." (stringFromInt64 i))

fn lowerArms ctx: LowerCtx kw: String env: (Map String String) st: LowerState scrutinee: String k: String arms: (List Arm) i: Int64 exits: (List (Pair String String)) -> (Result Lowered ty/IrDiag)
  (mt (listHead arms)
    ((none) (err (unsupported ctx kw "without arms is outside the lowered subset")))
    ((some a) (let [(bound (cond
                             ((= a.kind "ctor") (bindPayload st env scrutinee a.binds 0))
                             ((= a.kind "var") (Bound :st st :env (mapSet env a.name scrutinee)))
                             (else (Bound :st st :env env))))
                    (rest (optionOr (listTail arms) (list)))]
                (mt (lowerSeq ctx bound.env bound.st a.body)
                  ((err d) (err d))
                  ((ok br) (if (listEmpty? rest)
                             (ok (joinExits br.st (str "join" k) exits br.value))
                             (lowerArms ctx kw env (closeBlock br.st (jumpTo (str "join" k) br.value) (armLabel k (+ i 1)) (list)) scrutinee k rest (+ i 1)
                                        (listAppend exits (list (pair br.st.label br.value))))))))))

fn upToCatchAll arms: (List Arm) -> (List Arm)
  (mt (listIndexOf (map (fn [(a Arm)] -> Bool (!= a.kind "ctor")) arms) true)
    ((some i) (optionOr (listSlice arms 0 (+ i 1)) arms))
    ((none) arms))

fn lowerMatch ctx: LowerCtx env: (Map String String) st: LowerState kw: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (mt (resultMap (classifyArms ctx kw (matchFamily ctx (tailOf args)) (tailOf args)) upToCatchAll)
    ((err d) (err d))
    ((ok arms) (mt (matchShapeDiag ctx kw arms)
                 ((some d) (err d))
                 ((none) (if (not (stringEmpty? (listMatch ctx env (nthOf args 0) arms)))
                           (lowerListMatch ctx env st (listMatch ctx env (nthOf args 0) arms) arms (nthOf (rd/sexprToList (nthOf args 0)) 1))
                           (mt (lowerExpr ctx env st (nthOf args 0))
                           ((err d) (err d))
                           ((ok s0) (let [(sr (coerce s0.st s0.value (ty/tyVal)))
                                          (k (stringFromInt64 sr.st.labels))
                                          (indexed (map (fn [(i Int64)] -> (Pair Int64 Arm) (pair i (optionOr (listGet arms i) (Arm :kind "" :variant "" :typeName "" :binds (list) :name "" :body (list))))) (range 0 (listLength arms))))
                                          (cases (map (fn [(p (Pair Int64 Arm))] -> ty/SsaCase (ty/ssaCase (pairSecond p).variant (ty/ssaEdge (armLabel k (pairFirst p)) (list))))
                                                      (filter (fn [(p (Pair Int64 Arm))] -> Bool (= (pairSecond p).kind "ctor")) indexed)))
                                          (catchAt (listIndexOf (map (fn [(a Arm)] -> Bool (!= a.kind "ctor")) arms) true))
                                          (trap (and (none? catchAt) (not (listEmpty? (missingVariants ctx arms)))))
                                          (defaultEdge (mt catchAt ((some i) (some (ty/ssaEdge (armLabel k i) (list)))) ((none) (if trap (some (ty/ssaEdge (str "nomatch" k) (list))) (none)))))
                                          (typeName (mt (listHead (filter (fn [(a Arm)] -> Bool (= a.kind "ctor")) arms)) ((some a) a.typeName) ((none) "")))
                                          (bumped (bumpLabels sr.st))
                                          (switched (closeBlock bumped (ty/termSwitch sr.value typeName cases defaultEdge) (armLabel k 0) (list)))]
                                      (cond
                                        ((listEmpty? arms) (lowerNoArms sr))
                                        ((listEmpty? cases) (lowerArms ctx kw env bumped sr.value k arms 0 (list)))
                                        (else (lowerArms ctx kw env (if trap (withTrapBlock switched (str "nomatch" k)) switched) sr.value k arms 0 (list))))))))))))

fn listMatch ctx: LowerCtx env: (Map String String) scrutinee: rd/SExpr arms: (List Arm) -> String
  (let [(items (rd/sexprToList scrutinee))
        (h (rd/sexprHead (nthOf items 0)))
        (optionArms (filter (fn [(a Arm)] -> Bool (= a.typeName "Option")) arms))
        (plain (fold (fn [(acc Bool) (a Arm)] -> Bool (and acc (or (= a.kind "wild") (= a.typeName "Option")))) true arms))]
    (cond
      ((not (and (rd/isList? scrutinee) (and (rd/isAtom? (nthOf items 0)) (= (listLength items) 2)))) "")
      ((or (listEmpty? optionArms) (not plain)) "")
      ((not (builtinName? ctx env h)) "")
      ((= h "listHead") "@listFirst")
      ((= h "listTail") "@listRest")
      (else "")))

fn armFor arms: (List Arm) variant: String -> (Option Arm)
  (mt (listHead (filter (fn [(a Arm)] -> Bool (= a.variant variant)) arms))
    ((some a) (some a))
    ((none) (listHead (filter (fn [(a Arm)] -> Bool (= a.kind "wild")) arms))))

fn lowerListArm ctx: LowerCtx env: (Map String String) st: LowerState payload: String xs: String a: Arm -> (Result Lowered ty/IrDiag)
  (let [(name (optionOr (listHead a.binds) "_"))]
    (if (or (!= a.variant "some") (= name "_"))
      (lowerSeq ctx env st a.body)
      (let [(x (emit st (ty/opEntry payload (list xs))))]
        (lowerSeq ctx (mapSet env name x.value) x.st a.body))))

fn lowerListMatch ctx: LowerCtx env: (Map String String) st: LowerState payload: String arms: (List Arm) listExpr: rd/SExpr -> (Result Lowered ty/IrDiag)
  (mt (lowerExpr ctx env st listExpr)
    ((err d) (err d))
    ((ok l0) (let [(l (coerce l0.st l0.value (ty/tyVal)))
                   (empty (emitAs l.st (ty/tyI1) (ty/opEntry "listEmpty?" (list l.value))))
                   (k (stringFromInt64 empty.st.labels))
                   (joinL (str "join" k))
                   (someArm (armFor arms "some"))
                   (noneArm (armFor arms "none"))
                   (someL (if (some? someArm) (armLabel k 0) (str "nomatch" k)))
                   (noneL (if (some? noneArm) (armLabel k 1) (str "nomatch" k)))
                   (branched (closeBlock (bumpLabels empty.st) (ty/termBranch empty.value (ty/ssaEdge noneL (list)) (ty/ssaEdge someL (list))) (if (some? someArm) someL noneL) (list)))
                   (ready (if (and (some? someArm) (some? noneArm)) branched (withTrapBlock branched (str "nomatch" k))))]
               (mt someArm
                 ((none) (mt noneArm
                           ((none) (err (unsupported ctx "mt" "without arms is outside the lowered subset")))
                           ((some na) (mt (lowerListArm ctx env ready payload l.value na)
                                        ((err d) (err d))
                                        ((ok nr) (ok (joinExits nr.st joinL (list) nr.value)))))))
                 ((some sa) (mt (lowerListArm ctx env ready payload l.value sa)
                              ((err d) (err d))
                              ((ok sr) (mt noneArm
                                         ((none) (ok (joinExits sr.st joinL (list) sr.value)))
                                         ((some na) (mt (lowerListArm ctx env (closeBlock sr.st (jumpTo joinL sr.value) noneL (list)) payload l.value na)
                                                      ((err d) (err d))
                                                      ((ok nr) (ok (joinExits nr.st joinL (list (pair sr.st.label sr.value)) nr.value)))))))))))))

fn paramName p: rd/SExpr -> String
  (let [(items (rd/sexprToList p))]
    (cond
      ((bindName? p) (rd/sexprHead p))
      ((and (rd/isList? p) (and (= (listLength items) 2) (bindName? (nthOf items 0)))) (rd/sexprHead (nthOf items 0)))
      (else "")))

fn lambdaOf args: (List rd/SExpr) -> (Option Lambda)
  (mt (bindingVector (nthOf args 0))
    ((none) (none))
    ((some ps) (let [(names (map paramName ps))
                     (rest (tailOf args))
                     (typed (and (rd/isAtom? (nthOf rest 0)) (= (rd/sexprHead (nthOf rest 0)) "->")))]
                 (if (listContains? names "")
                   (none)
                   (some (Lambda :params names :types (map paramType ps) :body (if typed (tailOf (tailOf rest)) rest)))))))

fn paramType p: rd/SExpr -> ty/SsaTy
  (let [(items (rd/sexprToList p))]
    (if (and (rd/isList? p) (and (= (listLength items) 2) (rd/isAtom? (nthOf items 1))))
      (annotTy (rd/sexprHead (nthOf items 1)))
      (ty/tyVal)))

fn freeInAll bound: (List String) acc: (List String) es: (List rd/SExpr) -> (List String)
  (fold (fn [(a (List String)) (e rd/SExpr)] -> (List String) (freeIn bound a e)) acc es)

fn freeInLet bound: (List String) acc: (List String) bindings: (List rd/SExpr) body: (List rd/SExpr) -> (List String)
  (mt (listHead bindings)
    ((none) (freeInAll bound acc body))
    ((some b) (freeInLet (cons (bindingName b) bound) (freeIn bound acc (nthOf (rd/sexprToList b) 1)) (tailOf bindings) body)))

fn patternNames pat: rd/SExpr -> (List String)
  (if (rd/isAtom? pat) (list (rd/sexprHead pat)) (map rd/sexprHead (tailOf (rd/sexprToList pat))))

fn freeInArms bound: (List String) acc: (List String) arms: (List rd/SExpr) -> (List String)
  (fold (fn [(a (List String)) (arm rd/SExpr)] -> (List String)
          (let [(items (rd/sexprToList arm))]
            (freeInAll (listAppend (patternNames (nthOf items 0)) bound) a (tailOf items))))
        acc arms)

fn freeIn bound: (List String) acc: (List String) e: rd/SExpr -> (List String)
  (mt e
    ((rd/sexprAtom v) (if (or (listContains? bound v) (listContains? acc v)) acc (listAppend acc (list v))))
    ((rd/sexprVect items) (freeInAll bound acc items))
    ((rd/sexprList items) (let [(h (nthOf items 0))
                                (head (if (rd/isAtom? h) (rd/sexprHead h) ""))
                                (args (tailOf items))]
                            (cond
                              ((= head "fn") (mt (lambdaOf args)
                                               ((none) (freeInAll bound acc args))
                                               ((some l) (freeInAll (listAppend l.params bound) acc l.body))))
                              ((= head "let") (mt (letBindings (nthOf args 0))
                                                ((none) (freeInAll bound acc args))
                                                ((some bs) (freeInLet bound acc bs (tailOf args)))))
                              ((or (= head "mt") (= head "match")) (freeInArms bound (freeIn bound acc (nthOf args 0)) (tailOf args)))
                              (else (freeInAll bound acc items))))))

fn selfRecursive? name: String e: rd/SExpr -> Bool
  (and (rd/isList? e)
       (and (= (rd/sexprHead (nthOf (rd/sexprToList e) 0)) "fn")
            (mt (lambdaOf (tailOf (rd/sexprToList e)))
              ((none) false)
              ((some l) (listContains? (freeInAll l.params (list) l.body) name)))))

fn valParams names: (List String) -> (List ty/SsaParam)
  (map (fn [(n String)] -> ty/SsaParam (ty/ssaParam n (ty/tyVal))) names)

fn repeated? names: (List String) -> Bool
  (fold (fn [(acc Bool) (i Int64)] -> Bool (or acc (listContains? (optionOr (listSlice names 0 i) (list)) (optionOr (listGet names i) ""))))
        false (range 0 (listLength names)))

fn liftLambda ctx: LowerCtx env: (Map String String) st: LowerState l: Lambda -> (Result Lowered ty/IrDiag)
  (let [(caps (filter (fn [(v String)] -> Bool (mapHas? env v)) (freeInAll l.params (list) l.body)))
        (n st.lambdas)
        (name (str ctx.fnName "@lambda" (stringFromInt64 n)))
        (innerEnv (mapFromPairs (map (fn [(v String)] -> (Pair String String) (pair v v)) (listAppend caps l.params))))
        (inner (with st :next 0 :labels 0 :done (list) :label "entry" :params (list) :instrs (list) :lambdas (+ n 1) :types (typeIndexEmpty) :twins (typeIndexEmpty)))
        (capTypes (map (fn [(v String)] -> ty/SsaTy (tyOf st (optionOr (mapGet env v) ""))) caps))
        (entry (unboxNamed inner innerEnv (listAppend caps l.params) (listAppend capTypes (map (fn [(t ty/SsaTy)] -> ty/SsaTy (resolveTy ctx.info t)) l.types))))]
    (mt (lowerSeq ctx entry.env entry.st l.body)
      ((err d) (err d))
      ((ok r0) (let [(r (coerce r0.st r0.value (ty/tyVal)))
                     (final (closeBlock r.st (ty/termReturn r.value) "" (list)))
                     (code (ty/ssaFunction name (valParams caps) (valParams l.params) (ty/tyVal) (listReverse final.done)))
                     (captured (boxAll st (map (fn [(v String)] -> String (optionOr (mapGet env v) "")) caps)))
                     (cst captured.st)
                     (outer (LowerState :next cst.next :labels cst.labels :strings final.strings :done cst.done :label cst.label :params cst.params :instrs cst.instrs
                                        :lifted (listAppend final.lifted (list code)) :lambdas final.lambdas :types cst.types :twins cst.twins))]
                 (ok (emit outer (ty/opMakeClosure name captured.values)))))))

fn unboxNamed st: LowerState env: (Map String String) names: (List String) types: (List ty/SsaTy) -> Bound
  (fold (fn [(acc Bound) (i Int64)] -> Bound
          (let [(t (optionOr (listGet types i) (ty/tyVal)))
                (v (optionOr (listGet names i) ""))]
            (cond
              ((ty/ssaIsRaw? t) (let [(u (twinOf (emitAs acc.st t (ty/opUnbox v)) v))]
                                  (Bound :st u.st :env (mapSet acc.env v u.value))))
              ((ty/ssaIsRec? t) (Bound :st (withType acc.st v t) :env acc.env))
              (else acc))))
        (Bound :st st :env env) (range 0 (listLength names)))

fn lowerLambda ctx: LowerCtx env: (Map String String) st: LowerState args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (mt (lambdaOf args)
    ((none) (err (unsupported ctx "fn" "with a parameter list other than [name ...] or [(name Type) ...] is outside the lowered subset")))
    ((some l) (cond
                ((listEmpty? l.body) (err (unsupported ctx "fn" "without a body is outside the lowered subset")))
                ((repeated? l.params) (err (unsupported ctx "fn" "with a repeated parameter name is outside the lowered subset")))
                (else (liftLambda ctx env st l)))))

fn listOf st: LowerState values: (List String) -> Lowered
  (let [(b (boxAll st values))]
    (emit b.st (ty/opList b.values)))

fn lowerCallClosure ctx: LowerCtx env: (Map String String) st: LowerState head: rd/SExpr args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (mt (lowerExpr ctx env st head)
    ((err d) (err d))
    ((ok h) (mt (lowerArgs ctx env h.st args)
              ((err d) (err d))
              ((ok r) (let [(b (boxAll r.st (cons h.value r.values)))]
                        (ok (emit b.st (ty/opCallClosure (optionOr (listHead b.values) "") (optionOr (listTail b.values) (list))))))))))

fn preludeName? ctx: LowerCtx env: (Map String String) name: String -> Bool
  (and (not (mapHas? env name)) (and (not (mapHas? ctx.info.arities name)) (mapHas? ctx.info.late name)))

fn builtinName? ctx: LowerCtx env: (Map String String) name: String -> Bool
  (and (not (mapHas? env name)) (and (not (mapHas? ctx.info.arities name)) (and (not (mapHas? ctx.info.ctors name)) (not (mapHas? ctx.info.records name)))))

fn moduleBoundName? ctx: LowerCtx name: String -> Bool
  (or (mapHas? ctx.info.arities name) (or (mapHas? ctx.info.ctors name) (mapHas? ctx.info.records name)))

fn optionSource ctx: LowerCtx env: (Map String String) e: rd/SExpr -> String
  (let [(items (rd/sexprToList e))
        (h (rd/sexprHead (nthOf items 0)))
        (n (- (listLength items) 1))]
    (cond
      ((not (and (rd/isList? e) (rd/isAtom? (nthOf items 0)))) "")
      ((and (= h "listHead") (and (= n 1) (builtinName? ctx env h))) "@listHeadOr")
      ((and (= h "listTail") (and (= n 1) (builtinName? ctx env h))) "@listTailOr")
      ((and (= h "stringSlice") (and (= n 3) (builtinName? ctx env h))) "@stringSliceOr")
      ((and (= h "listGet") (and (= n 2) (preludeName? ctx env h))) "@listGetOr")
      (else "")))

fn lowerOptionOr ctx: LowerCtx env: (Map String String) st: LowerState entryName: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (mt (lowerArgs ctx env st (listAppend (tailOf (rd/sexprToList (nthOf args 0))) (list (nthOf args 1))))
    ((err d) (err d))
    ((ok r) (ok (typedBuiltin r.st entryName r.values))))

fn lowerHead ctx: LowerCtx env: (Map String String) st: LowerState name: String args: (List rd/SExpr) -> (Result Lowered ty/IrDiag)
  (cond
    ((= name "if") (lowerIf ctx env st args))
    ((= name "cond") (lowerCond ctx env st args))
    ((= name "let") (lowerLet ctx env st args))
    ((= name "do") (lowerSeq ctx env st args))
    ((= name "and") (lowerLogic ctx env st true args))
    ((= name "or") (lowerLogic ctx env st false args))
    ((or (= name "mt") (= name "match")) (lowerMatch ctx env st name args))
    ((= name "list") (mt (lowerArgs ctx env st args) ((err d) (err d)) ((ok r) (ok (listOf r.st r.values)))))
    ((= name "fn") (lowerLambda ctx env st args))
    ((or (= name "assert") (= name "refute"))
      (if (or (listEmpty? args) (> (listLength args) 2))
        (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "'" name "' takes a condition and an optional message, got " (listLength args) " operand(s)")))
        (lowerBuiltin ctx env st name -1 args)))
    ((and (= name "optionOr") (and (= (listLength args) 2) (and (preludeName? ctx env name) (not (stringEmpty? (optionSource ctx env (nthOf args 0)))))))
      (lowerOptionOr ctx env st (optionSource ctx env (nthOf args 0)) args))
    ((or (= name "when") (= name "unless"))
      (if (listEmpty? args)
        (err (lowerDiag ctx "ERR_LOWER_ARITY" (str "'" name "' needs a condition")))
        (let [(body (rd/makeList (cons (rd/makeAtom "do") (tailOf args))))
              (unit (rd/makeAtom "()"))]
          (lowerIf ctx env st (if (= name "when") (list (nthOf args 0) body unit) (list (nthOf args 0) unit body))))))
    ((and (or (= name "loop") (= name "recur") (= name "try") (= name "return") (= name "quote")) (not (moduleBoundName? ctx name))) (err (outside ctx name)))
    ((mapHas? env name) (lowerCallClosure ctx env st (rd/makeAtom name) args))
    ((preludeBitOp? ctx name) (lowerPreludeBit ctx env st name args))
    ((mapHas? ctx.info.arities name) (lowerCall ctx env st name (optionOr (mapGet ctx.info.arities name) 0) args))
    ((mapHas? ctx.info.ctors name) (lowerConstruct ctx env st name args))
    ((mapHas? ctx.info.records name) (lowerRecord ctx env st name args))
    ((and (stringStartsWith? name ".-") (> (stringLength name) 2)) (lowerField ctx env st name args))
    ((and (or (= name "+") (= name "*")) (> (listLength args) 2)) (lowerExpr ctx env st (rd/makeList (list (rd/makeAtom name) (rd/makeList (listAppend (list (rd/makeAtom name)) (optionOr (listSlice args 0 (- (listLength args) 1)) (list)))) (nthOf args (- (listLength args) 1))))))
    ((not (stringEmpty? (genericAlias name))) (lowerHead ctx env st (genericAlias name) args))
    ((and (genericMulti? name) (not (mapHas? ctx.info.late name))) (err (ambiguousDiag ctx name)))
    ((some? (builtinArity name)) (lowerBuiltin ctx env st name (optionOr (builtinArityFor name (listLength args)) (optionOr (builtinArity name) 0)) args))
    ((mapHas? ctx.info.late name) (lowerCall ctx env st name (optionOr (mapGet ctx.info.late name) 0) args))
    ((and ctx.info.linked (qualified? name)) (err (qualifiedDiag ctx name)))
    ((stringContains? name "/") (err (unsupported ctx name "is a call of an imported function, outside the lowered subset")))
    (else (err (unsupported ctx name "is neither a module function nor a builtin of the lowered subset"))))

fn lowerExpr ctx: LowerCtx env: (Map String String) st: LowerState e: rd/SExpr -> (Result Lowered ty/IrDiag)
  (mt e
    ((rd/sexprAtom v) (lowerAtom ctx env st v))
    ((rd/sexprVect items) (mt (lowerArgs ctx env st items) ((err d) (err d)) ((ok r) (ok (listOf r.st r.values)))))
    ((rd/sexprList items) (mt (listHead items)
                            ((none) (constOf st (ty/constUnit)))
                            ((some h) (if (rd/isAtom? h)
                                        (lowerHead ctx env st (rd/sexprHead h) (tailOf items))
                                        (lowerCallClosure ctx env st h (tailOf items)))))))

fn genericConcrete name: String kind: String -> String
  (if (= kind "*") (genericStar name) (genericKinded name kind))

fn genericStar name: String -> String
  (cond
    ((= name "head") "listHead") ((= name "tail") "listTail") ((= name "startsWith?") "stringStartsWith?")
    ((= name "getFloat64") "bytesGetFloat64") ((= name "setFloat64") "bytesSetFloat64") ((= name "sha256") "bytesSha256")
    ((= name "last") "listLast") ((= name "take") "listTake") ((= name "drop") "listDrop")
    ((= name "all?") "listAll?") ((= name "any?") "listAny?") ((= name "sort") "listSort")
    ((= name "sortBy") "listSortBy") ((= name "endsWith?") "stringEndsWith?") ((= name "split") "stringSplit")
    ((= name "join") "stringJoin") ((= name "replace") "stringReplace") ((= name "trim") "stringTrim")
    ((= name "chars") "stringChars") ((= name "lines") "stringLines") ((= name "upper") "stringUpper")
    ((= name "lower") "stringLower") ((= name "repeat") "stringRepeat") ((= name "countChar") "stringCountChar")
    ((= name "keys") "mapKeys") ((= name "values") "mapValues") ((= name "pairs") "mapPairs")
    ((= name "remove") "mapRemove")
    (else ""))

fn genericKinded name: String kind: String -> String
  (cond
    ((= name "length")
      (cond
        ((= kind "String") "stringLength") ((= kind "List") "listLength") ((= kind "Bytes") "bytesLength")
        ((= kind "Map") "mapSize") ((= kind "I64Array") "i64ArrayLen") ((= kind "I8Array") "i8ArrayLen")
        ((= kind "F64Array") "f64ArrayLen")
        (else "")))
    ((= name "empty?")
      (cond
        ((= kind "String") "stringEmpty?") ((= kind "List") "listEmpty?")
        (else "")))
    ((= name "get")
      (cond
        ((= kind "List") "listGet") ((= kind "Bytes") "bytesGet") ((= kind "Map") "mapGet")
        ((= kind "I64Array") "i64ArrayGet") ((= kind "I8Array") "i8ArrayGet") ((= kind "F64Array") "f64ArrayGet")
        (else "")))
    ((= name "set")
      (cond
        ((= kind "Bytes") "bytesSet") ((= kind "Map") "mapSet")
        (else "")))
    ((= name "slice")
      (cond
        ((= kind "String") "stringSlice") ((= kind "List") "listSlice") ((= kind "I64Array") "i64ArraySlice")
        ((= kind "I8Array") "i8ArraySlice") ((= kind "F64Array") "f64ArraySlice")
        (else "")))
    ((= name "contains?")
      (cond
        ((= kind "String") "stringContains?") ((= kind "List") "listContains?") ((= kind "Map") "mapHas?")
        (else "")))
    ((= name "indexOf")
      (cond
        ((= kind "String") "stringIndexOf") ((= kind "List") "listIndexOf")
        (else "")))
    ((= name "reverse")
      (cond
        ((= kind "String") "stringReverse") ((= kind "List") "listReverse")
        (else "")))
    ((= name "append")
      (cond
        ((= kind "String") "stringConcat") ((= kind "List") "listAppend")
        (else "")))
    ((= name "sum")
      (cond
        ((= kind "List") "listSum") ((= kind "I64Array") "i64ArraySum") ((= kind "I8Array") "i8ArraySum")
        ((= kind "F64Array") "f64ArraySum")
        (else "")))
    ((= name "countEq")
      (cond
        ((= kind "I64Array") "i64ArrayCountEq") ((= kind "I8Array") "i8ArrayCountEq") ((= kind "F64Array") "f64ArrayCountEq")
        (else "")))
    (else ""))

fn genericAlias name: String -> String
  (genericConcrete name "*")

fn genericMulti? name: String -> Bool
  (or (= name "length") (= name "empty?") (= name "get") (= name "set")
      (= name "slice") (= name "contains?") (= name "indexOf") (= name "reverse")
      (= name "append") (= name "sum") (= name "countEq"))

fn ambiguousDiag ctx: LowerCtx name: String -> ty/IrDiag
  (lowerDiag ctx "ERR_AMBIGUOUS_OVERLOAD" (str name ": the receiver kind is not known here; candidates " (stringJoin (filter (fn [(k String)] -> Bool (not (stringEmpty? (genericConcrete name k)))) (list "String" "List" "Bytes" "Map" "I64Array" "I8Array" "F64Array")) ", ") "; annotate the receiver (D159)"))

fn kindOfType t: rd/SExpr -> String
  (let [(h (rd/sexprHead t))]
    (cond ((rd/isAtom? t) (cond ((or (= h "String") (= h "Str")) "String") ((or (= h "Bytes") (= h "I64Array") (= h "I8Array") (= h "F64Array")) h) (else "")))
          ((rd/isList? t) (cond ((= h "List") "List") ((= h "Map") "Map") (else "")))
          (else "")))

fn kindOfAnnotation t: String -> String
  (cond ((or (= t "String") (= t "Str")) "String") ((or (= t "Bytes") (= t "I64Array") (= t "I8Array") (= t "F64Array")) t)
        ((stringStartsWith? t "(List ") "List") ((stringStartsWith? t "(Map ") "Map") (else ""))

fn kindReturned name: String recv: String -> String
  (cond ((or (= name "list") (= name "cons") (= name "map") (= name "filter")
            (= name "range") (= name "listReverse") (= name "listAppend") (= name "listTake")
            (= name "listDrop") (= name "listSort") (= name "listSortBy") (= name "stringSplit")
            (= name "stringChars") (= name "stringLines") (= name "mapKeys") (= name "mapValues")
            (= name "mapPairs") (= name "split") (= name "chars") (= name "lines")
            (= name "keys") (= name "values") (= name "pairs") (= name "sort")
            (= name "sortBy") (= name "take") (= name "drop") (= name "zip")
            (= name "enumerate")) "List")
        ((or (= name "str") (= name "stringConcat") (= name "stringFromInt64") (= name "stringFromFloat64")
            (= name "stringReverse") (= name "stringJoin") (= name "stringReplace") (= name "stringTrim")
            (= name "stringUpper") (= name "stringLower") (= name "stringRepeat") (= name "join")
            (= name "replace") (= name "trim") (= name "upper") (= name "lower")
            (= name "repeat")) "String")
        ((or (= name "stringToBytes") (= name "bytesAlloc")) "Bytes")
        ((or (= name "mapEmpty") (= name "mapSet") (= name "mapFromPairs") (= name "mapRemove")
            (= name "remove")) "Map")
        ((or (= name "i64ArrayGenerate") (= name "i64ArraySlice") (= name "i64ArrayConcat") (= name "i64ArrayScan")) "I64Array")
        ((or (= name "i8ArrayGenerate") (= name "i8ArraySlice") (= name "i8ArrayConcat") (= name "i8ArrayScan")) "I8Array")
        ((or (= name "f64ArrayGenerate") (= name "f64ArraySlice") (= name "f64ArrayConcat") (= name "f64ArrayScan")) "F64Array")
        ((or (= name "append") (= name "reverse")) recv)
        (else ""))

fn shadowed? ctx: LowerCtx kinds: (Map String String) name: String -> Bool
  (or (mapHas? kinds name) (mapHas? ctx.info.arities name))

fn kindOf ctx: LowerCtx kinds: (Map String String) e: rd/SExpr -> String
  (mt e
    ((rd/sexprAtom v) (if (stringStartsWith? v "\"") "String" (optionOr (mapGet kinds v) "")))
    ((rd/sexprVect _) "List")
    ((rd/sexprList items) (let [(h (rd/sexprHead e)) (args (tailOf items))]
                            (if (or (stringEmpty? h) (shadowed? ctx kinds h)) ""
                              (kindReturned h (if (listEmpty? args) "" (kindOf ctx kinds (nthOf args 0))))))))

fn bindAll kinds: (Map String String) e: rd/SExpr -> (Map String String)
  (mt e
    ((rd/sexprAtom v) (if (or (stringEmpty? v) (stringStartsWith? v ":") (stringStartsWith? v "\"")) kinds (mapSet kinds v "")))
    ((rd/sexprVect items) (fold bindAll kinds items))
    ((rd/sexprList items) (fold bindAll kinds items)))

fn resolveAll ctx: LowerCtx kinds: (Map String String) xs: (List rd/SExpr) -> (List rd/SExpr)
  (map (fn [(x rd/SExpr)] -> rd/SExpr (resolveGenerics ctx kinds x)) xs)

fn resolveBinding ctx: LowerCtx kinds: (Map String String) items: (List rd/SExpr) -> (Pair (List rd/SExpr) (Map String String))
  (let [(name (nthOf items 0)) (typed (= (listLength items) 3))
        (value (resolveGenerics ctx kinds (nthOf items (if typed 2 1))))
        (kind (if typed (kindOfType (nthOf items 1)) (kindOf ctx kinds value)))
        (next (if (rd/isAtom? name) (mapSet kinds (rd/sexprHead name) kind) (bindAll kinds name)))]
    (pair (if typed (list name (nthOf items 1) value) (list name value)) next))

fn resolveLet ctx: LowerCtx kinds: (Map String String) bindings: (List rd/SExpr) acc: (List rd/SExpr) flat: Bool -> (Pair (List rd/SExpr) (Map String String))
  (mt (listHead bindings)
    ((none) (pair (listReverse acc) kinds))
    ((some b) (let [(one (resolveBinding ctx kinds (rd/sexprToList b)))
                    (acc2 (if flat (listAppend (listReverse (pairFirst one)) acc) (cons (rd/makeList (pairFirst one)) acc)))]
                (resolveLet ctx (pairSecond one) (tailOf bindings) acc2 flat))))

fn resolveLetForm ctx: LowerCtx kinds: (Map String String) items: (List rd/SExpr) -> rd/SExpr
  (let [(vec (nthOf items 1))]
    (mt (bindingVector vec)
      ((none) (rd/makeList (cons (nthOf items 0) (resolveAll ctx kinds (tailOf items)))))
      ((some raw) (if (listEmpty? raw) (rd/makeList (cons (nthOf items 0) (resolveAll ctx kinds (tailOf items))))
                    (let [(flat (rd/isAtom? (nthOf raw 0)))
                          (done (resolveLet ctx kinds (if flat (pairUp raw) raw) (list) flat))
                          (bound (if (rd/isVect? vec) (rd/sexprVect (pairFirst done)) (rd/makeList (cons (rd/makeAtom "list") (pairFirst done)))))]
                      (rd/makeList (cons (nthOf items 0) (cons bound (resolveAll ctx (pairSecond done) (optionOr (listSlice items 2 (listLength items)) (list)))))))))))

fn resolveArm ctx: LowerCtx kinds: (Map String String) arm: rd/SExpr -> rd/SExpr
  (mt arm
    ((rd/sexprList items) (mt (listHead items)
                            ((none) arm)
                            ((some p) (rd/makeList (cons p (resolveAll ctx (bindAll kinds p) (tailOf items)))))))
    (_ arm))

fn resolveLambda ctx: LowerCtx kinds: (Map String String) items: (List rd/SExpr) -> rd/SExpr
  (let [(params (rd/sexprToList (nthOf items 1)))
        (inner (fold (fn [(k (Map String String)) (p rd/SExpr)] -> (Map String String)
                       (if (rd/isAtom? p) (mapSet k (rd/sexprHead p) "")
                         (let [(ps (rd/sexprToList p))] (mapSet k (rd/sexprHead (nthOf ps 0)) (kindOfType (nthOf ps 1))))))
                     kinds params))]
    (rd/makeList (cons (nthOf items 0) (cons (nthOf items 1) (resolveAll ctx inner (optionOr (listSlice items 2 (listLength items)) (list)))))))

fn resolveCall ctx: LowerCtx kinds: (Map String String) items: (List rd/SExpr) -> rd/SExpr
  (let [(h (rd/sexprHead (nthOf items 0))) (args (resolveAll ctx kinds (tailOf items)))
        (alias (genericAlias h))
        (conc (cond ((shadowed? ctx kinds h) "")
                    ((not (stringEmpty? alias)) alias)
                    ((listEmpty? args) "")
                    ((not (genericMulti? h)) "")
                    (else (let [(k (kindOf ctx kinds (nthOf args 0)))] (if (stringEmpty? k) "" (genericConcrete h k))))))]
    (rd/makeList (cons (if (stringEmpty? conc) (nthOf items 0) (rd/makeAtom conc)) args)))

fn resolveGenerics ctx: LowerCtx kinds: (Map String String) e: rd/SExpr -> rd/SExpr
  (mt e
    ((rd/sexprAtom v) (let [(alias (genericAlias v))] (if (or (stringEmpty? alias) (shadowed? ctx kinds v)) e (rd/makeAtom alias))))
    ((rd/sexprVect items) (rd/sexprVect (resolveAll ctx kinds items)))
    ((rd/sexprList items) (mt (listHead items)
                            ((none) e)
                            ((some h) (if (not (rd/isAtom? h)) (rd/makeList (resolveAll ctx kinds items))
                                        (let [(name (rd/sexprHead h))]
                                          (cond ((shadowed? ctx kinds name) (rd/makeList (cons h (resolveAll ctx kinds (tailOf items)))))
                                                ((= name "let") (resolveLetForm ctx kinds items))
                                                ((= name "fn") (resolveLambda ctx kinds items))
                                                ((or (= name "mt") (= name "match")) (rd/makeList (cons h (cons (resolveGenerics ctx kinds (nthOf items 1)) (map (fn [(a rd/SExpr)] -> rd/SExpr (resolveArm ctx kinds a)) (optionOr (listSlice items 2 (listLength items)) (list)))))))
                                                ((or (stringStartsWith? name ":") (stringStartsWith? name "\"")) (rd/makeList (cons h (resolveAll ctx kinds (tailOf items)))))
                                                (else (resolveCall ctx kinds items)))))))))

fn lowerFunction ctx: LowerCtx strings: StringPool d: ast/DefunNode -> (Result LoweredFn ty/IrDiag)
  (let [(names (map (fn [(p ast/Param)] -> String p.name) d.params))
        (sig (resolveSig ctx.info (sigOf d)))
        (params (map (fn [(i Int64)] -> ty/SsaParam (ty/ssaParam (optionOr (listGet names i) "") (optionOr (listGet sig.params i) (ty/tyVal)))) (range 0 (listLength names))))
        (env (mapFromPairs (map (fn [(n String)] -> (Pair String String) (pair n n)) names)))
        (types (fold (fn [(m TypeIndex) (p ty/SsaParam)] -> TypeIndex
                       (if (or (ty/ssaIsRaw? p.ty) (ty/ssaIsRec? p.ty))
                         (typeIndexSet m p.name (ty/ssaTyName p.ty)) m)) (typeIndexEmpty) params))
        (st0 (LowerState :next 0 :labels 0 :strings strings :done (list) :label "entry" :params (list) :instrs (list) :lifted (list) :lambdas 0 :types types :twins (typeIndexEmpty)))
        (kinds (fold (fn [(k (Map String String)) (p ast/Param)] -> (Map String String) (mapSet k p.name (kindOfAnnotation p.type))) (mapEmpty) d.params))]
    (mt (lowerSeq ctx env st0 (if (and (preludeBitOp? ctx d.name) (= ctx.fnName (str "prelude." d.name)))
                                (list (rd/makeList (cons (rd/makeAtom d.name) (map rd/makeAtom names))))
                                (resolveAll ctx kinds d.body)))
      ((err e) (err e))
      ((ok r0) (let [(r (coerce r0.st r0.value sig.ret))
                     (final (closeBlock r.st (ty/termReturn r.value) "" (list)))]
                (ok (LoweredFn :function (ty/ssaFunction ctx.fnName (list) params sig.ret (listReverse final.done))
                               :lifted final.lifted
                               :strings final.strings))))))

fn ctxFor name: String positions: (Map String String) info: ModInfo -> LowerCtx
  (LowerCtx :fnName (optionOr (mapGet info.targets name) name) :pos (optionOr (mapGet positions name) "?") :info info)

fn addLowered acc: ModAcc lf: LoweredFn -> ModAcc
  (ModAcc :strings lf.strings :functions (fold (fn [(fs (List ty/SsaFunction)) (f ty/SsaFunction)] -> (List ty/SsaFunction) (cons f fs)) acc.functions (cons lf.function lf.lifted)) :diags acc.diags)

fn withDiag acc: ModAcc d: ty/IrDiag -> ModAcc
  (with acc :diags (listAppend acc.diags (list d)))

fn wanted? only: (Option (Map String Bool)) name: String -> Bool
  (or (stringContains? name "@init$") (mt only ((none) true) ((some names) (mapHas? names name))))

fn schemaDefaultAcc positions: (Map String String) info: ModInfo acc: ModAcc s: ast/SchemaNode -> ModAcc
  (let [(fieldTypes (schemaFieldTypes s)) (defaults (schemaDefaults s))]
    (fold (fn [(a ModAcc) (fieldName String)] -> ModAcc
            (let [(bareThunk (defaultThunkBareName s.name fieldName))
                  (fieldTy (optionOr (mapGet fieldTypes fieldName) ""))
                  (defExpr (optionOr (mapGet defaults fieldName) (rd/sexprAtom "")))
                  (synth (ast/DefunNode :name bareThunk :typeVars (list) :isExported false :effect false :params (list) :retType fieldTy :docstring "" :body (list defExpr) :bodyPos (list)))]
              (mt (lowerFunction (ctxFor bareThunk positions info) a.strings synth)
                ((err e) (withDiag a e))
                ((ok lf) (addLowered a lf)))))
          acc (mapKeys defaults)))

fn lowerTop positions: (Map String String) info: ModInfo only: (Option (Map String Bool)) acc: ModAcc t: ast/TopForm -> ModAcc
  (mt t
    ((ast/topModule _) acc)
    ((ast/topSchema s) (schemaDefaultAcc positions info acc s))
    ((ast/topEnum _) acc)
    ((ast/topDefun d) (if (not (wanted? only d.name))
                        acc
                        (mt (lowerFunction (ctxFor d.name positions info) acc.strings d)
                          ((err e) (withDiag acc e))
                          ((ok lf) (addLowered acc lf)))))
    ((ast/topExpr p) (let [(initName (str "@init$" (stringFromInt64 p.line) "_" (stringFromInt64 p.col)))
                           (synth (ast/DefunNode :name initName :typeVars (list) :isExported false :effect true :params (list) :retType "" :docstring "\"\"" :body (list p.expr) :bodyPos (list p)))]
                       (mt (lowerFunction (ctxFor initName positions info) acc.strings synth)
                         ((err e) (withDiag acc e))
                         ((ok lf) (addLowered acc lf))))))

fn moduleHeader forms: (List ast/TopForm) -> (Option ast/ModuleNode)
  (fold (fn [(acc (Option ast/ModuleNode)) (t ast/TopForm)] -> (Option ast/ModuleNode)
          (mt acc ((some _) acc) ((none) (mt t ((ast/topModule m) (some m)) ((ast/topSchema _) acc) ((ast/topEnum _) acc) ((ast/topDefun _) acc) ((ast/topExpr _) acc)))))
        (none) forms)

fn moduleName forms: (List ast/TopForm) -> String
  (mt (moduleHeader forms) ((some m) m.path) ((none) ""))

fn functionArities forms: (List ast/TopForm) -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (t ast/TopForm)] -> (Map String Int64)
          (mt t ((ast/topDefun d) (mapSet acc d.name (listLength d.params))) ((ast/topModule _) acc) ((ast/topSchema _) acc) ((ast/topEnum _) acc) ((ast/topExpr _) acc)))
        (mapEmpty) forms)

fn preludeTypes -> (List ty/SsaTypeDecl)
  (list (ty/ssaTypeDecl "Option" (list (ty/ssaVariant "some" 1) (ty/ssaVariant "none" 0)))
        (ty/ssaTypeDecl "Result" (list (ty/ssaVariant "ok" 1) (ty/ssaVariant "err" 1))))

fn qualify prefix: String name: String -> String
  (if (stringEmpty? prefix) name (str prefix "." name))

fn caseArity c: ast/EnumCase -> Int64
  (listLength c.fields)

fn enumDecl prefix: String e: ast/EnumNode -> ty/SsaTypeDecl
  (ty/ssaTypeDecl (qualify prefix e.name) (map (fn [(c ast/EnumCase)] -> ty/SsaVariant (ty/ssaVariant c.name (caseArity c))) e.cases))

fn enumDecls forms: (List ast/TopForm) prefix: String -> (List ty/SsaTypeDecl)
  (fold (fn [(acc (List ty/SsaTypeDecl)) (t ast/TopForm)] -> (List ty/SsaTypeDecl)
          (mt t
            ((ast/topEnum e) (cons (enumDecl prefix e) acc))
            ((ast/topModule _) acc) ((ast/topSchema _) acc) ((ast/topDefun _) acc) ((ast/topExpr _) acc)))
        (list) (listReverse forms))

fn schemaFields s: ast/SchemaNode -> (List String)
  (map (fn [(f ast/AstField)] -> String f.name) s.fields)

fn schemaDefaults s: ast/SchemaNode -> (Map String rd/SExpr)
  (fold (fn [(m (Map String rd/SExpr)) (f ast/AstField)] -> (Map String rd/SExpr)
          (mt f.default
            ((some e) (mapSet m f.name e))
            ((none) m)))
        (mapEmpty) s.fields)

fn schemaFieldTypes s: ast/SchemaNode -> (Map String String)
  (fold (fn [(m (Map String String)) (f ast/AstField)] -> (Map String String) (mapSet m f.name f.type)) (mapEmpty) s.fields)

fn fieldSigKey schema: String field: String -> String
  (str "field:" schema "." field)

fn withFieldSigs sigs: (Map String FnSig) schema: String s: ast/SchemaNode -> (Map String FnSig)
  (fold (fn [(m (Map String FnSig)) (f ast/AstField)] -> (Map String FnSig)
          (let [(t (annotTy f.type))]
            (if (ty/ssaIsRaw? t) (mapSet m (fieldSigKey schema f.name) (FnSig :params (list) :ret t)) m)))
        sigs s.fields)

fn defaultThunkBareName schemaName: String fieldName: String -> String
  (str schemaName "$default$" fieldName)

fn visWithSchemaDefaults v: Vis key: String modName: String s: ast/SchemaNode keyPrefix: String -> Vis
  (let [(fieldTypes (schemaFieldTypes s))]
    (fold (fn [(acc Vis) (fieldName String)] -> Vis
            (let [(bareThunk (defaultThunkBareName s.name fieldName))
                  (sourceThunk (str keyPrefix bareThunk))
                  (fieldTy (optionOr (mapGet fieldTypes fieldName) ""))
                  (callExpr (rd/sexprList (list (rd/sexprAtom sourceThunk))))
                  (prevForKey (optionOr (mapGet acc.defaults key) (mapEmpty)))]
              (Vis :arities (mapSet acc.arities sourceThunk 0) :ctors acc.ctors :records acc.records
                   :defaults (mapSet acc.defaults key (mapSet prevForKey fieldName callExpr))
                   :targets (mapSet acc.targets sourceThunk (qualify modName bareThunk)) :foreign acc.foreign :hidden acc.hidden
                   :sigs (mapSet acc.sigs sourceThunk (FnSig :params (list) :ret (annotTy fieldTy))))))
          v (mapKeys (schemaDefaults s))))

fn recordDecls forms: (List ast/TopForm) prefix: String -> (List ty/SsaRecordDecl)
  (fold (fn [(acc (List ty/SsaRecordDecl)) (t ast/TopForm)] -> (List ty/SsaRecordDecl)
          (mt t
            ((ast/topSchema s) (cons (ty/ssaRecordDecl (qualify prefix s.name) (schemaFields s)) acc))
            ((ast/topModule _) acc) ((ast/topEnum _) acc) ((ast/topDefun _) acc) ((ast/topExpr _) acc)))
        (list) (listReverse forms))

fn addCtorsAs keyPrefix: String acc: (Map String Ctor) d: ty/SsaTypeDecl -> (Map String Ctor)
  (fold (fn [(m (Map String Ctor)) (v ty/SsaVariant)] -> (Map String Ctor) (mapSet m (str keyPrefix v.name) (Ctor :typeName d.name :variant v.name :arity v.arity)))
        acc d.variants)

fn addCtors acc: (Map String Ctor) d: ty/SsaTypeDecl -> (Map String Ctor)
  (addCtorsAs "" acc d)

(schema Vis
  (:f arities (Map String Int64))
  (:f ctors (Map String Ctor))
  (:f records (Map String (List String)))
  (:f defaults (Map String (Map String rd/SExpr)))
  (:f targets (Map String String))
  (:f foreign (List ty/SsaTypeDecl))
  (:f hidden (Map String String))
  (:f sigs (Map String FnSig)))

fn visible? exports: (Option (Map String Bool)) name: String -> Bool
  (mt exports ((none) true) ((some names) (mapHas? names name)))

fn hide v: Vis key: String modName: String -> Vis
  (with v :hidden (mapSet v.hidden key modName))

fn addDecl keyPrefix: String modName: String exports: (Option (Map String Bool)) foreign: Bool v: Vis t: ast/TopForm -> Vis
  (mt t
    ((ast/topModule _) v)
    ((ast/topDefun d) (let [(key (str keyPrefix d.name))]
                        (if (visible? exports d.name)
                          (with v :arities (mapSet (mapSet v.arities key (listLength d.params)) (qualify modName d.name) (listLength d.params)) :targets (mapSet v.targets key (qualify modName d.name)) :sigs (mapSet (mapSet v.sigs key (sigOf d)) (qualify modName d.name) (sigOf d)))
                          (hide v key modName))))
    ((ast/topSchema s) (let [(key (str keyPrefix s.name))]
                         (if (visible? exports s.name)
                           (visWithSchemaDefaults
                             (with v :records (mapSet v.records key (schemaFields s)) :targets (mapSet v.targets key (qualify modName s.name)) :sigs (withFieldSigs v.sigs (qualify modName s.name) s))
                             key modName s keyPrefix)
                           (hide v key modName))))
    ((ast/topEnum e) (let [(decl (enumDecl modName e))
                           (decls (if foreign (cons decl v.foreign) v.foreign))
                           (visibleCase? (fn [(c ast/EnumCase)] -> Bool (or (visible? exports e.name) (visible? exports c.name))))
                           (newCtors (fold (fn [(m (Map String Ctor)) (c ast/EnumCase)] -> (Map String Ctor)
                                             (if (visibleCase? c) (mapSet m (str keyPrefix c.name) (Ctor :typeName decl.name :variant c.name :arity (caseArity c))) m))
                                           v.ctors e.cases))
                           (newHidden (fold (fn [(m (Map String String)) (c ast/EnumCase)] -> (Map String String)
                                              (if (visibleCase? c) m (mapSet m (str keyPrefix c.name) modName)))
                                            v.hidden e.cases))]
                       (with v :ctors newCtors :foreign decls :hidden newHidden)))
    ((ast/topExpr _) v))

fn addDecls v: Vis forms: (List ast/TopForm) keyPrefix: String modName: String exports: (Option (Map String Bool)) foreign: Bool -> Vis
  (fold (fn [(acc Vis) (t ast/TopForm)] -> Vis (addDecl keyPrefix modName exports foreign acc t)) v forms)

fn baseVis -> Vis
  (Vis :arities (mapEmpty) :ctors (fold addCtors (mapEmpty) (preludeTypes)) :records (mapEmpty) :defaults (mapEmpty) :targets (mapEmpty) :foreign (list) :hidden (mapEmpty) :sigs (mapEmpty))

fn variantIndex decls: (List ty/SsaTypeDecl) -> (Map String (List String))
  (fold (fn [(m (Map String (List String))) (d ty/SsaTypeDecl)] -> (Map String (List String))
          (if (mapHas? m d.name) m (mapSet m d.name (map (fn [(v ty/SsaVariant)] -> String v.name) d.variants))))
        (mapEmpty) decls)

fn infoOf forms: (List ast/TopForm) v: Vis late: (Map String Int64) prefix: String aliases: (Map String String) linked: Bool -> ModInfo
  (let [(own (addDecls v forms "" prefix (none) false))
        (types (enumDecls forms prefix))
        (foreign (listReverse own.foreign))]
    (ModInfo :arities own.arities :late late :ctors own.ctors :records own.records :defaults own.defaults :types types :sigs own.sigs
             :targets own.targets :foreign foreign :aliases aliases :hidden own.hidden :linked linked
             :variants (variantIndex (listAppend types (listAppend foreign (preludeTypes))))))

fn sysAlias imp: (Pair String String) -> String
  (if (stringEmpty? (pairSecond imp)) (pairFirst imp) (pairSecond imp))

fn sysImports forms: (List ast/TopForm) -> (List (Pair String String))
  (mt (moduleHeader forms) ((some m) (filter (fn [(imp (Pair String String))] -> Bool (= (pairFirst imp) "sys")) m.imports)) ((none) (list)))

fn sysAliases forms: (List ast/TopForm) -> (Map String String)
  (fold (fn [(acc (Map String String)) (imp (Pair String String))] -> (Map String String) (mapSet acc (sysAlias imp) "sys")) (mapEmpty) (sysImports forms))

fn moduleInfo forms: (List ast/TopForm) -> ModInfo
  (infoOf forms (baseVis) (mapEmpty) "" (sysAliases forms) false)

fn nameSetOf names: (List String) -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (n String)] -> (Map String Bool) (mapSet m n true)) (mapEmpty) names)

fn importVis v: Vis alias: String forms: (List ast/TopForm) -> Vis
  (addDecls v forms (str alias "/") (moduleName forms) (some (nameSetOf (mt (moduleHeader forms) ((some m) m.exported) ((none) (list))))) true)

fn importedCtors scope: LinkScope -> (Map String Ctor)
  (let [(walked (fold (fn [(acc (Pair (Map String Bool) (List ty/SsaTypeDecl))) (a String)] -> (Pair (Map String Bool) (List ty/SsaTypeDecl))
                        (let [(forms (optionOr (mapGet scope.imports a) (list)))
                              (seen (pairFirst acc))
                              (fresh (filter (fn [(d ty/SsaTypeDecl)] -> Bool (not (mapHas? seen d.name))) (enumDecls forms (moduleName forms))))]
                          (pair (fold (fn [(m (Map String Bool)) (d ty/SsaTypeDecl)] -> (Map String Bool) (mapSet m d.name true)) seen fresh)
                                (fold (fn [(ds (List ty/SsaTypeDecl)) (d ty/SsaTypeDecl)] -> (List ty/SsaTypeDecl) (cons d ds)) (pairSecond acc) fresh))))
                      (pair (mapEmpty) (list)) (mapKeys scope.imports)))
        (all (listReverse (fold (fn [(acc (List Ctor)) (d ty/SsaTypeDecl)] -> (List Ctor)
                                  (fold (fn [(cs (List Ctor)) (c Ctor)] -> (List Ctor) (cons c cs)) acc (mapValues (addCtors (mapEmpty) d))))
                                (list) (listReverse (pairSecond walked)))))
        (counts (fold (fn [(m (Map String Int64)) (c Ctor)] -> (Map String Int64) (mapSet m c.variant (+ (optionOr (mapGet m c.variant) 0) 1))) (mapEmpty) all))]
    (fold (fn [(acc (Map String Ctor)) (c Ctor)] -> (Map String Ctor)
            (if (= (optionOr (mapGet counts c.variant) 0) 1) (mapSet acc c.variant c) acc))
          (mapEmpty) all))

fn withBareCtors v: Vis bare: (Map String Ctor) -> Vis
  (with v :ctors (fold (fn [(acc (Map String Ctor)) (k String)] -> (Map String Ctor) (if (mapHas? acc k) acc (mapSet acc k (optionOr (mapGet bare k) (Ctor :typeName "" :variant "" :arity 0)))))
                    v.ctors (mapKeys bare)))

fn preludeVisOf prelude: (List ast/TopForm) -> Vis
  (addDecls (baseVis) prelude "" (moduleName prelude) (none) true)

fn belowModule preludeVis: Vis -> Vis
  (with preludeVis :arities (mapEmpty))

fn linkedInfoAs forms: (List ast/TopForm) scope: LinkScope prefix: String -> ModInfo
  (let [(preludeVis (preludeVisOf scope.prelude))
        (withPrelude (belowModule preludeVis))
        (aliasNames (mapKeys scope.imports))
        (withImports (withBareCtors (fold (fn [(v Vis) (a String)] -> Vis (importVis v a (optionOr (mapGet scope.imports a) (list)))) withPrelude aliasNames) (importedCtors scope)))
        (aliases (fold (fn [(m (Map String String)) (a String)] -> (Map String String) (mapSet m a (moduleName (optionOr (mapGet scope.imports a) (list))))) (sysAliases forms) aliasNames))]
    (infoOf forms withImports preludeVis.arities prefix aliases true))

fn linkedInfo forms: (List ast/TopForm) scope: LinkScope -> ModInfo
  (linkedInfoAs forms scope (moduleName forms))

fn typesUsedBy f: ty/SsaFunction -> (List String)
  (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
          (fold (fn [(names (List String)) (i ty/SsaInstr)] -> (List String) (mt i.op ((ty/opConstruct tn _ _) (cons tn names)) (_ names)))
                (mt b.term ((ty/termSwitch _ tn _ _) (cons tn acc)) (_ acc))
                b.instrs))
        (list) f.blocks)

fn dedupeTypes decls: (List ty/SsaTypeDecl) -> (List ty/SsaTypeDecl)
  (listReverse (pairSecond (fold (fn [(acc (Pair (Map String Bool) (List ty/SsaTypeDecl))) (d ty/SsaTypeDecl)] -> (Pair (Map String Bool) (List ty/SsaTypeDecl))
                                   (if (mapHas? (pairFirst acc) d.name) acc (pair (mapSet (pairFirst acc) d.name true) (cons d (pairSecond acc)))))
                                 (pair (mapEmpty) (list)) decls)))

fn moduleTypes info: ModInfo functions: (List ty/SsaFunction) -> (List ty/SsaTypeDecl)
  (let [(used (fold (fn [(acc (Map String Bool)) (f ty/SsaFunction)] -> (Map String Bool)
                      (fold (fn [(m (Map String Bool)) (n String)] -> (Map String Bool) (mapSet m n true)) acc (typesUsedBy f)))
                    (mapEmpty) functions))
        (own (fold (fn [(m (Map String Bool)) (d ty/SsaTypeDecl)] -> (Map String Bool) (mapSet m d.name true)) (mapEmpty) info.types))
        (allForeign (listAppend info.foreign (preludeTypes)))]
    (listAppend info.types
                (dedupeTypes (filter (fn [(d ty/SsaTypeDecl)] -> Bool (and (mapHas? used d.name) (not (mapHas? own d.name)))) allForeign))))

fn recordsUsedBy f: ty/SsaFunction -> (List ty/SsaRecordDecl)
  (fold (fn [(acc (List ty/SsaRecordDecl)) (b ty/SsaBlock)] -> (List ty/SsaRecordDecl)
          (fold (fn [(recs (List ty/SsaRecordDecl)) (i ty/SsaInstr)] -> (List ty/SsaRecordDecl)
                  (mt i.op
                    ((ty/opRecord s fields _) (cons (ty/ssaRecordDecl s fields) recs))
                    (_ recs)))
                acc b.instrs))
        (list) f.blocks)

fn dedupeRecords decls: (List ty/SsaRecordDecl) -> (List ty/SsaRecordDecl)
  (listReverse (pairSecond (fold (fn [(acc (Pair (Map String Bool) (List ty/SsaRecordDecl))) (d ty/SsaRecordDecl)] -> (Pair (Map String Bool) (List ty/SsaRecordDecl))
                                   (if (mapHas? (pairFirst acc) d.name) acc (pair (mapSet (pairFirst acc) d.name true) (cons d (pairSecond acc)))))
                                 (pair (mapEmpty) (list)) decls)))

fn moduleRecords forms: (List ast/TopForm) prefix: String functions: (List ty/SsaFunction) -> (List ty/SsaRecordDecl)
  (let [(own (recordDecls forms prefix))
        (used (listReverse (fold (fn [(acc (List ty/SsaRecordDecl)) (f ty/SsaFunction)] -> (List ty/SsaRecordDecl)
                                   (fold (fn [(rs (List ty/SsaRecordDecl)) (r ty/SsaRecordDecl)] -> (List ty/SsaRecordDecl) (cons r rs)) acc (recordsUsedBy f)))
                                 (list) functions)))]
    (dedupeRecords (listAppend own used)))

fn opExternRefs op: ty/SsaOp -> (List String)
  (mt op
    ((ty/opCall callee _) (list callee))
    ((ty/opMakeClosure callee _) (list callee))
    (_ (list)))

fn functionExternRefs f: ty/SsaFunction -> (List String)
  (listReverse (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
                       (fold (fn [(names (List String)) (i ty/SsaInstr)] -> (List String) (fold (fn [(ns (List String)) (n String)] -> (List String) (cons n ns)) names (opExternRefs i.op))) acc b.instrs))
                     (list) f.blocks))

fn dedupeStrings xs: (List String) -> (List String)
  (listReverse (pairSecond (fold (fn [(acc (Pair TypeIndex (List String))) (s String)] -> (Pair TypeIndex (List String))
                                   (if (typeIndexHas? (pairFirst acc) s) acc (pair (typeIndexSet (pairFirst acc) s true) (cons s (pairSecond acc)))))
                                 (pair (typeIndexEmpty) (list)) xs)))

fn targetSources info: ModInfo -> (Map String String)
  (fold (fn [(acc (Map String String)) (k String)] -> (Map String String)
          (let [(target (optionOr (mapGet info.targets k) ""))]
            (if (and (qualified? k) (not (mapHas? acc target))) (mapSet acc target k) acc)))
        (mapEmpty) (mapKeys info.targets))

fn externSig info: ModInfo sources: (Map String String) n: String sig: FnSig -> FnSig
  (mt (mapGet sources n)
    ((some source) (resolveSigFor info source sig))
    ((none) (resolveSig info sig)))

fn moduleExterns info: ModInfo functions: (List ty/SsaFunction) -> (List ty/SsaExtern)
  (let [(defined (fold (fn [(acc (Map String Bool)) (f ty/SsaFunction)] -> (Map String Bool) (mapSet acc f.name true)) (mapEmpty) functions))
        (refs (listReverse (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                                   (fold (fn [(a (List String)) (n String)] -> (List String) (cons n a)) acc (functionExternRefs f)))
                                 (list) functions)))
        (needed (filter (fn [(n String)] -> Bool (not (mapHas? defined n))) (dedupeStrings refs)))
        (sources (targetSources info))]
    (map (fn [(n String)] -> ty/SsaExtern
           (mt (mapGet info.sigs n)
             ((some sig) (let [(resolved (externSig info sources n sig))] (ty/ssaExternTyped n resolved.params resolved.ret)))
             ((none)
               (mt (mapGet info.arities n)
                 ((some a) (ty/ssaExtern n a))
                 ((none) (ty/ssaExtern n 0))))))
         needed))

(schema SplitWalk (:f index Int64) (:f defined Int64) (:f ended Int64) (:f open (List ty/SsaParam)) (:f last Int64) (:f cuts (List (Pair Int64 (List ty/SsaParam)))))

fn splitPartSize -> Int64
  1024

fn splitLiveLimit -> Int64
  8

fn positionKey i: Int64 -> String
  (stringFromInt64 i)

fn lastUses instrs: (List ty/SsaInstr) result: String -> TypeIndex
  (let [(walked (fold (fn [(acc (Pair Int64 TypeIndex)) (ins ty/SsaInstr)] -> (Pair Int64 TypeIndex)
                        (pair (+ (pairFirst acc) 1)
                              (fold (fn [(m TypeIndex) (v String)] -> TypeIndex (typeIndexSet m v (pairFirst acc)))
                                    (pairSecond acc) (ty/opOperands ins.op))))
                      (pair 0 (typeIndexEmpty)) instrs))]
    (typeIndexSet (pairSecond walked) result (pairFirst walked)))

fn endsAt uses: TypeIndex inputs: (List ty/SsaParam) instrs: (List ty/SsaInstr) -> TypeIndex
  (let [(fromInputs (fold (fn [(m TypeIndex) (p ty/SsaParam)] -> TypeIndex
                            (mt (typeIndexGet uses p.name)
                              ((some u) (typeIndexAdd m (positionKey u) 1))
                              ((none) m)))
                          (typeIndexEmpty) inputs))]
    (pairSecond (fold (fn [(acc (Pair Int64 TypeIndex)) (ins ty/SsaInstr)] -> (Pair Int64 TypeIndex)
                        (pair (+ (pairFirst acc) 1)
                              (typeIndexAdd (pairSecond acc) (positionKey (optionOr (typeIndexGet uses ins.dest) (pairFirst acc))) 1)))
                      (pair 0 fromInputs) instrs)))

fn splitCuts inputs: (List ty/SsaParam) instrs: (List ty/SsaInstr) result: String -> (List (Pair Int64 (List ty/SsaParam)))
  (let [(n (listLength instrs))
        (uses (lastUses instrs result))
        (ends (endsAt uses inputs instrs))
        (used (filter (fn [(p ty/SsaParam)] -> Bool (typeIndexHas? uses p.name)) inputs))
        (start (SplitWalk :index 0 :defined (listLength used) :ended 0 :open (listReverse used) :last 0 :cuts (list)))
        (walked (fold (fn [(w SplitWalk) (ins ty/SsaInstr)] -> SplitWalk
                        (let [(i w.index)
                              (ended (+ w.ended (if (> i 0) (optionOr (typeIndexGet ends (positionKey (- i 1))) 0) 0)))
                              (cut (and (>= (- i w.last) (splitPartSize)) (<= (- w.defined ended) (splitLiveLimit))))
                              (open (if cut (filter (fn [(p ty/SsaParam)] -> Bool (>= (optionOr (typeIndexGet uses p.name) -1) i)) w.open) w.open))]
                          (SplitWalk :index (+ i 1) :defined (+ w.defined 1) :ended ended
                                     :open (cons (ty/ssaParam ins.dest ins.ty) open)
                                     :last (if cut i w.last)
                                     :cuts (if cut (cons (pair i (listReverse open)) w.cuts) w.cuts))))
                      start instrs))]
    (if (> n 0) (listReverse walked.cuts) (list)))

fn chunksAt instrs: (List ty/SsaInstr) cuts: (List Int64) -> (List (List ty/SsaInstr))
  (let [(walked (fold (fn [(acc (Pair (Pair Int64 (List Int64)) (Pair (List ty/SsaInstr) (List (List ty/SsaInstr))))) (ins ty/SsaInstr)] -> (Pair (Pair Int64 (List Int64)) (Pair (List ty/SsaInstr) (List (List ty/SsaInstr))))
                        (let [(i (pairFirst (pairFirst acc)))
                              (pending (pairSecond (pairFirst acc)))
                              (current (pairFirst (pairSecond acc)))
                              (done (pairSecond (pairSecond acc)))]
                          (if (= (optionOr (listHead pending) -1) i)
                            (pair (pair (+ i 1) (optionOr (listTail pending) (list))) (pair (list ins) (cons (listReverse current) done)))
                            (pair (pair (+ i 1) pending) (pair (cons ins current) done)))))
                      (pair (pair 0 cuts) (pair (list) (list))) instrs))]
    (listReverse (cons (listReverse (pairFirst (pairSecond walked))) (pairSecond (pairSecond walked)))))

fn partName name: String k: Int64 -> String
  (str name "$part" (stringFromInt64 k))

fn splitParts f: ty/SsaFunction b: ty/SsaBlock result: String cuts: (List (Pair Int64 (List ty/SsaParam))) -> (List ty/SsaFunction)
  (let [(chunks (chunksAt b.instrs (map pairFirst cuts)))
        (k (listLength cuts))
        (ins (cons (list) (map pairSecond cuts)))
        (build (fn [(acc (Pair Int64 (Pair (List (List ty/SsaParam)) (List ty/SsaFunction)))) (chunk (List ty/SsaInstr))] -> (Pair Int64 (Pair (List (List ty/SsaParam)) (List ty/SsaFunction)))
                 (let [(i (pairFirst acc))
                       (live (pairFirst (pairSecond acc)))
                       (here (optionOr (listHead live) (list)))
                       (rest (optionOr (listTail live) (list)))
                       (next (optionOr (listHead rest) (list)))
                       (dest (str "%split" (stringFromInt64 (+ i 1))))
                       (body (if (< i k)
                               (ty/ssaBlock b.label (if (= i 0) b.params (list))
                                            (listAppend chunk (list (ty/ssaInstr dest f.retTy (ty/opCall (partName f.name (+ i 1)) (map (fn [(p ty/SsaParam)] -> String p.name) next)))))
                                            (ty/termReturn dest))
                               (ty/ssaBlock b.label (if (= i 0) b.params (list)) chunk b.term)))
                       (fun (if (= i 0)
                              (ty/ssaFunction f.name f.captures f.params f.retTy (list body))
                              (ty/ssaFunction (partName f.name i) (list) here f.retTy (list body))))]
                   (pair (+ i 1) (pair rest (cons fun (pairSecond (pairSecond acc))))))))]
    (listReverse (pairSecond (pairSecond (fold build (pair 0 (pair ins (list))) chunks)))))

fn splitFunction f: ty/SsaFunction -> (List ty/SsaFunction)
  (mt (if (= (listLength f.blocks) 1) (listHead f.blocks) (none))
    ((some b) (mt b.term
                ((ty/termReturn result)
                  (if (or (stringContains? f.name "@init$") (< (listLength b.instrs) (* 2 (splitPartSize))))
                    (list f)
                    (let [(cuts (splitCuts (listAppend f.captures f.params) b.instrs result))]
                      (if (listEmpty? cuts) (list f) (splitParts f b result cuts)))))
                (_ (list f))))
    (_ (list f)))

fn splitFunctions functions: (List ty/SsaFunction) -> (List ty/SsaFunction)
  (listReverse (fold (fn [(acc (List ty/SsaFunction)) (f ty/SsaFunction)] -> (List ty/SsaFunction)
                       (fold (fn [(a (List ty/SsaFunction)) (g ty/SsaFunction)] -> (List ty/SsaFunction) (cons g a)) acc (splitFunction f)))
                     (list) functions))

fn lowerWith forms: (List ast/TopForm) positions: (Map String String) info: ModInfo prefix: String strings: (List String) only: (Option (List String)) -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(name (moduleName forms))
        (onlySet (mt only ((none) (none)) ((some xs) (some (nameSetOf xs)))))
        (acc (fold (fn [(a ModAcc) (t ast/TopForm)] -> ModAcc (lowerTop positions info onlySet a t)) (ModAcc :strings (poolOf strings) :functions (list) :diags (list)) forms))
        (functions (splitFunctions (listReverse acc.functions)))
        (diags (if (stringEmpty? name) (cons (ty/makeIrDiag "ERR_LOWER_NO_MODULE" "the source has no module header" "?") acc.diags) acc.diags))
        (inits (filter (fn [(f ty/SsaFunction)] -> Bool (and (stringContains? f.name "@init$") (not (stringContains? f.name "@lambda")))) functions))
        (globals (map (fn [(f ty/SsaFunction)] -> ty/SsaGlobal (ty/ssaGlobal (str f.name "$g") f.name)) inits))]
    (if (listEmpty? diags)
      (ok (ty/ssaModule name (poolList acc.strings) (moduleTypes info functions) (moduleRecords forms prefix functions) (moduleExterns info functions) globals functions))
      (err diags)))

fn lowerModule forms: (List ast/TopForm) positions: (Map String String) -> (Result ty/SsaModule (List ty/IrDiag))
  (lowerWith forms positions (moduleInfo forms) "" (list) (none))

fn lowerWithPrelude forms: (List ast/TopForm) positions: (Map String String) prelude: (List ast/TopForm) -> (Result ty/SsaModule (List ty/IrDiag))
  (let [(preludeVis (preludeVisOf prelude))]
    (lowerWith forms positions (infoOf forms (belowModule preludeVis) preludeVis.arities "" (sysAliases forms) false) "" (list) (none)))

fn locatedPositions scope: LinkScope positions: (Map String String) prefix: String -> (Map String String)
  (if (stringEmpty? prefix)
    positions
    (mapFromPairs (map (fn [(k String)] -> (Pair String String) (pair k (str scope.path ":" (optionOr (mapGet positions k) "?")))) (mapKeys positions))))

fn lowerLinkedAs forms: (List ast/TopForm) positions: (Map String String) scope: LinkScope prefix: String -> (Result ty/SsaModule (List ty/IrDiag))
  (lowerWith forms (locatedPositions scope positions prefix) (linkedInfoAs forms scope prefix) prefix scope.strings scope.only)

fn lowerLinked forms: (List ast/TopForm) positions: (Map String String) scope: LinkScope -> (Result ty/SsaModule (List ty/IrDiag))
  (lowerLinkedAs forms positions scope (moduleName forms))

fn leadingSpaces s: String -> Int64
  (pairFirst (fold (fn [(acc (Pair Int64 Bool)) (c String)] -> (Pair Int64 Bool)
                   (if (and (pairSecond acc) (or (= c " ") (= c "\t"))) (pair (+ (pairFirst acc) 1) true) (pair (pairFirst acc) false)))
                 (pair 0 true) (stringChars s)))

fn declHead? w: String -> Bool
  (or (= w "fn") (= w "fn!") (= w "defun") (= w "df") (= w "schema") (= w "defschema") (= w "dfs") (= w "enum") (= w "defenum") (= w "dfe"))

fn isDeclModifier? w: String -> Bool
  (or (= w "!") (or (= w "tailrec") (= w ":tailrec")))

fn stripDeclModifiers words: (List String) -> (List String)
  (mt (listHead words)
    ((none) (list))
    ((some w) (if (isDeclModifier? w) (stripDeclModifiers (optionOr (listTail words) (list))) words)))

fn declName line: String -> String
  (let [(trimmed (optionOr (stringSlice line (leadingSpaces line) (stringLength line)) ""))
        (bare (if (stringStartsWith? trimmed "(") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "") trimmed))
        (words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit bare " ")))
        (rest (stripDeclModifiers (optionOr (listTail words) (list))))
        (name (optionOr (listHead rest) ""))]
    (if (and (declHead? (optionOr (listHead words) "")) (and (not (stringEmpty? name)) (not (stringContains? "[({\"" (optionOr (stringSlice name 0 1) "")))))
      name
      ""))

fn declPositions src: String -> (Map String String)
  (let [(srcLines (stringSplit src "\n"))
        (final (fold (fn [(acc (Pair (Map String String) Int64)) (line String)] -> (Pair (Map String String) Int64)
                       (let [(m (pairFirst acc))
                             (i (pairSecond acc))
                             (name (declName line))]
                         (pair (if (or (stringEmpty? name) (mapHas? m name))
                                 m
                                 (mapSet m name (str (stringFromInt64 (+ i 1)) ":" (stringFromInt64 (+ (leadingSpaces line) 1)))))
                               (+ i 1))))
                     (pair (mapEmpty) 0) srcLines))]
    (pairFirst final))

fn lowerSource src: String -> (Result ty/SsaModule (List ty/IrDiag))
  (mt (ast/parse src)
    ((err e) (err (list (parseDiag e (str e.line ":" e.col)))))
    ((ok forms) (lowerModule forms (declPositions src))))

fn parseDiag pe: ast/ParseError locus: String -> ty/IrDiag
  (if (stringStartsWith? pe.msg "ERR_DEPTH ")
    (ty/makeIrDiag "ERR_DEPTH" (optionOr (stringSlice pe.msg 10 (stringLength pe.msg)) pe.msg) locus)
    (ty/makeIrDiag "ERR_LOWER_PARSE" pe.msg locus))
