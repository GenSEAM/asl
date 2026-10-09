(module asl-compiler/wasm :x [leb128EncodeU32 leb128EncodeI32 encodeUtf8 byteLength flattenByteLists wasmMagicHeader encodeSection encodeFuncType encodeTypeSection encodeFunctionSection encodeMemorySection encodeImportEntry encodeImportSection encodeExportEntry encodeExportSection encodeLocalEntry encodeFunctionBody encodeCodeSection wasmOpcode emitInstrConstI32 emitInstrConstI64 emitInstrLocalGet emitInstrLocalSet emitInstrCall emitInstrBinaryOp emitInstrIf wasmValType sexprToAtomStr buildFunctionTypeIndexOffset buildFunctionTypeIndex lowerAstExpr lowerAstFunction lowerAstTopForms lowerAstTopFormsWithImports emitWasmMemorySection emitWasmRpcExports emitWasmCapabilityDenial emitWasmBinaryBytes emitWasmBinaryTarget encodeDataSegment encodeDataSection emitWasiBinaryBytes emitWasiBinaryTarget wasiStandardImportEntries wasiStandardImportTypes] :i [(asl-parser/ast :a a) (asl-parser/reader :a rd)])

fn leb128EncodeU32Step n: Int64 acc: (List Int64) -> (List Int64)
  (let [(rem (mod n 128)) (nextN (/ n 128))] (if (= nextN 0) (listAppend acc (list rem)) (leb128EncodeU32Step nextN (listAppend acc (list (+ rem 128))))))

fn leb128EncodeU32 n: Int64 -> (List Int64)
  (leb128EncodeU32Step n (list))

fn leb128EncodeI32Step n: Int64 acc: (List Int64) -> (List Int64)
  (let [(rem (mod n 128)) (rawByte (if (< rem 0) (+ rem 128) rem)) (nextN (if (< rem 0) (- (/ n 128) 1) (/ n 128))) (isDone (or (and (= nextN 0) (< rawByte 64)) (and (= nextN -1) (>= rawByte 64))))] (if isDone (listAppend acc (list rawByte)) (leb128EncodeI32Step nextN (listAppend acc (list (+ rawByte 128))))))

fn leb128EncodeI32 n: Int64 -> (List Int64)
  (leb128EncodeI32Step n (list))

fn charToByte ch: Str -> Int64
  (cond ((= ch "\t") 9) ((= ch "\n") 10) ((= ch "\r") 13) (else (let [(chars " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~") (idx (optionOr (stringIndexOf chars ch) -1))] (if (>= idx 0) (+ idx 32) 0))))

fn encodeUtf8 s: Str -> (List Int64)
  (map (fn [(ch Str)] -> Int64 (charToByte ch)) (stringChars s))

fn byteLength bytes: (List Int64) -> Int64
  (listLength bytes)

fn flattenByteLists lists: (List (List Int64)) -> (List Int64)
  (fold (fn [(acc (List Int64)) (item (List Int64))] -> (List Int64) (listAppend acc item)) (list) lists)

fn wasmMagicHeader -> (List Int64)
  (list 0 97 115 109 1 0 0 0)

fn encodeSection sectionId: Int64 payload: (List Int64) -> (List Int64)
  (let [(lenBytes (leb128EncodeU32 (listLength payload)))] (listAppend (list sectionId) (listAppend lenBytes payload)))

fn encodeFuncType paramTypes: (List Int64) retTypes: (List Int64) -> (List Int64)
  (let [(pCount (leb128EncodeU32 (listLength paramTypes))) (rCount (leb128EncodeU32 (listLength retTypes)))] (listAppend (list 96) (listAppend pCount (listAppend paramTypes (listAppend rCount retTypes)))))

fn encodeTypeSection types: (List (List Int64)) -> (List Int64)
  (let [(count (leb128EncodeU32 (listLength types))) (payload (listAppend count (flattenByteLists types)))] (encodeSection 1 payload))

fn encodeImportEntry modName: Str fieldName: Str kind: Int64 typeOrDescIdx: Int64 -> (List Int64)
  (let [(mBytes (encodeUtf8 modName)) (mLen (leb128EncodeU32 (listLength mBytes))) (fBytes (encodeUtf8 fieldName)) (fLen (leb128EncodeU32 (listLength fBytes))) (idxBytes (leb128EncodeU32 typeOrDescIdx))] (listAppend mLen (listAppend mBytes (listAppend fLen (listAppend fBytes (listAppend (list kind) idxBytes))))))

fn encodeImportSection imports: (List (List Int64)) -> (List Int64)
  (let [(count (leb128EncodeU32 (listLength imports))) (payload (listAppend count (flattenByteLists imports)))] (encodeSection 2 payload))

fn encodeFunctionSection typeIndices: (List Int64) -> (List Int64)
  (let [(count (leb128EncodeU32 (listLength typeIndices))) (indices (flattenByteLists (map (fn [(idx Int64)] -> (List Int64) (leb128EncodeU32 idx)) typeIndices))) (payload (listAppend count indices))] (encodeSection 3 payload))

fn encodeMemorySection minPages: Int64 maxPages: Int64 -> (List Int64)
  (let [(hasMax (>= maxPages 0)) (limits (if hasMax (listAppend (list 1) (listAppend (leb128EncodeU32 minPages) (leb128EncodeU32 maxPages))) (listAppend (list 0) (leb128EncodeU32 minPages)))) (payload (listAppend (leb128EncodeU32 1) limits))] (encodeSection 5 payload))

fn encodeExportEntry name: Str kind: Int64 index: Int64 -> (List Int64)
  (let [(nameBytes (encodeUtf8 name)) (nameLen (leb128EncodeU32 (listLength nameBytes))) (idxBytes (leb128EncodeU32 index))] (listAppend nameLen (listAppend nameBytes (listAppend (list kind) idxBytes))))

fn encodeExportSection exports: (List (List Int64)) -> (List Int64)
  (let [(count (leb128EncodeU32 (listLength exports))) (payload (listAppend count (flattenByteLists exports)))] (encodeSection 7 payload))

fn encodeLocalEntry count: Int64 valType: Int64 -> (List Int64)
  (listAppend (leb128EncodeU32 count) (list valType))

fn encodeFunctionBody locals: (List (List Int64)) instructions: (List Int64) -> (List Int64)
  (let [(localsCount (leb128EncodeU32 (listLength locals))) (localsBytes (flattenByteLists locals)) (fullBody (listAppend localsCount (listAppend localsBytes instructions))) (bodyLen (leb128EncodeU32 (listLength fullBody)))] (listAppend bodyLen fullBody))

fn encodeCodeSection bodies: (List (List Int64)) -> (List Int64)
  (let [(count (leb128EncodeU32 (listLength bodies))) (payload (listAppend count (flattenByteLists bodies)))] (encodeSection 10 payload))

fn wasmOpcode name: Str -> Int64
  (cond ((= name "unreachable") 0) ((= name "nop") 1) ((= name "block") 2) ((= name "loop") 3) ((= name "if") 4) ((= name "else") 5) ((= name "end") 11) ((= name "br") 12) ((= name "br_if") 13) ((= name "return") 15) ((= name "call") 16) ((= name "drop") 26) ((= name "local.get") 32) ((= name "local.set") 33) ((= name "local.tee") 34) ((= name "global.get") 35) ((= name "global.set") 36) ((= name "i32.load") 40) ((= name "i64.load") 41) ((= name "i32.store") 54) ((= name "i64.store") 55) ((= name "memory.size") 63) ((= name "memory.grow") 64) ((= name "i32.const") 65) ((= name "i64.const") 66) ((= name "i32.eqz") 69) ((= name "i32.eq") 70) ((= name "i32.ne") 71) ((= name "i32.lt_s") 72) ((= name "i32.gt_s") 74) ((= name "i32.le_s") 76) ((= name "i32.ge_s") 78) ((= name "i64.eqz") 80) ((= name "i64.eq") 81) ((= name "i64.ne") 82) ((= name "i64.lt_s") 83) ((= name "i64.gt_s") 85) ((= name "i64.le_s") 87) ((= name "i64.ge_s") 89) ((= name "i32.clz") 103) ((= name "i32.ctz") 104) ((= name "i32.popcnt") 105) ((= name "i32.add") 106) ((= name "i32.sub") 107) ((= name "i32.mul") 108) ((= name "i32.div_s") 109) ((= name "i32.rem_s") 111) ((= name "i32.and") 113) ((= name "i32.or") 114) ((= name "i32.xor") 115) ((= name "i32.shl") 116) ((= name "i32.shr_s") 117) ((= name "i64.add") 124) ((= name "i64.sub") 125) ((= name "i64.mul") 126) ((= name "i64.div_s") 127) ((= name "i64.rem_s") 129) ((= name "i64.and") 131) ((= name "i64.or") 132) ((= name "i64.xor") 133) ((= name "i64.shl") 134) ((= name "i64.shr_s") 135) (else -1))

fn emitInstrConstI32 val: Int64 -> (List Int64)
  (listAppend (list 65) (leb128EncodeI32 val))

fn emitInstrConstI64 val: Int64 -> (List Int64)
  (listAppend (list 66) (leb128EncodeI32 val))

fn emitInstrLocalGet localIdx: Int64 -> (List Int64)
  (listAppend (list 32) (leb128EncodeU32 localIdx))

fn emitInstrLocalSet localIdx: Int64 -> (List Int64)
  (listAppend (list 33) (leb128EncodeU32 localIdx))

fn emitInstrCall funcIdx: Int64 -> (List Int64)
  (listAppend (list 16) (leb128EncodeU32 funcIdx))

fn emitInstrBinaryOp opStr: Str typeStr: Str -> (List Int64)
  (if (or (or (= typeStr "i32") (= typeStr "I32")) (or (= typeStr "Bool") (= typeStr "bool"))) (cond ((or (= opStr "+") (= opStr "add")) (list 106)) ((or (= opStr "-") (= opStr "sub")) (list 107)) ((or (= opStr "*") (= opStr "mul")) (list 108)) ((or (= opStr "/") (= opStr "div")) (list 109)) ((or (= opStr "mod") (= opStr "rem")) (list 111)) ((= opStr "and") (list 113)) ((= opStr "or") (list 114)) ((= opStr "xor") (list 115)) ((or (= opStr "=") (= opStr "eq")) (list 70)) ((or (= opStr "!=") (= opStr "ne")) (list 71)) ((or (= opStr "<") (= opStr "lt")) (list 72)) ((or (= opStr ">") (= opStr "gt")) (list 74)) ((or (= opStr "<=") (= opStr "le")) (list 76)) ((or (= opStr ">=") (= opStr "ge")) (list 78)) (else (list 106))) (cond ((or (= opStr "+") (= opStr "add")) (list 124)) ((or (= opStr "-") (= opStr "sub")) (list 125)) ((or (= opStr "*") (= opStr "mul")) (list 126)) ((or (or (= opStr "/") (= opStr "div")) (= opStr "checkedDiv")) (list 127)) ((or (or (= opStr "mod") (= opStr "rem")) (= opStr "checkedMod")) (list 129)) ((= opStr "and") (list 131)) ((= opStr "or") (list 132)) ((= opStr "xor") (list 133)) ((or (= opStr "=") (= opStr "eq")) (list 81)) ((or (= opStr "!=") (= opStr "ne")) (list 82)) ((or (= opStr "<") (= opStr "lt")) (list 83)) ((or (= opStr ">") (= opStr "gt")) (list 85)) ((or (= opStr "<=") (= opStr "le")) (list 87)) ((or (= opStr ">=") (= opStr "ge")) (list 89)) (else (list 124))))

fn emitInstrIf blockType: Int64 thenInstrs: (List Int64) elseInstrs: (List Int64) -> (List Int64)
  (if (listEmpty? elseInstrs) (listAppend (list 4 blockType) (listAppend thenInstrs (list 11))) (listAppend (list 4 blockType) (listAppend thenInstrs (listAppend (list 5) (listAppend elseInstrs (list 11))))))

fn sexprToAtomStr s: rd/SExpr -> Str
  (mt s ((sexprAtom v) v) ((sexprList items) (if (listEmpty? items) "" (sexprToAtomStr (optionOr (listGet items 0) (rd/makeAtom ""))))) ((sexprVect items) (if (listEmpty? items) "" (sexprToAtomStr (optionOr (listGet items 0) (rd/makeAtom ""))))))

fn wasmValType ty: Str -> Int64
  (cond ((or (or (or (= ty "I64") (= ty "Int")) (= ty "i64")) (= ty "Int64")) 126) ((or (or (or (= ty "I32") (= ty "Bool")) (or (= ty "bool") (= ty "i32"))) (= ty "Int32")) 127) ((or (or (= ty "F64") (= ty "Float")) (= ty "Float64")) 124) ((= ty "F32") 125) (else 126))

fn buildFunctionTypeIndexOffset forms: (List a/TopForm) offset: Int64 -> (Map Str Int64)
  (let [(fnList (fold (fn [(acc (List Str)) (f a/TopForm)] (mt f ((topDefun d) (listAppend acc (list d.name))) (else acc))) (list) forms))] (fold (fn [(acc (Map Str Int64)) (idx Int64)] (let [(name (optionOr (listGet fnList idx) ""))] (mapSet acc name (+ idx offset)))) (mapEmpty) (range 0 (listLength fnList))))

fn buildFunctionTypeIndex forms: (List a/TopForm) -> (Map Str Int64)
  (buildFunctionTypeIndexOffset forms 0)

fn formsHaveTopExpr? forms: (List a/TopForm) -> Bool
  (fold (fn [(acc Bool) (f a/TopForm)] -> Bool (or acc (mt f ((topExpr _) true) (else false)))) false forms)

fn lowerAstExpr expr: rd/SExpr locals: (Map Str Int64) fnIndices: (Map Str Int64) retType: Str -> (List Int64)
  (mt expr ((sexprAtom v) (let [(isNum (or (stringStartsWith? v "-") (and (>= (optionOr (stringSlice v 0 1) "") "0") (<= (optionOr (stringSlice v 0 1) "") "9"))))] (cond (isNum (let [(n (optionOr (stringToInt64 v) 0))] (if (= (wasmValType retType) 127) (emitInstrConstI32 n) (emitInstrConstI64 n)))) ((= v "true") (emitInstrConstI32 1)) ((= v "false") (emitInstrConstI32 0)) ((mapHas? locals v) (let [(idx (optionOr (mapGet locals v) 0))] (emitInstrLocalGet idx))) (else (if (= (wasmValType retType) 127) (emitInstrConstI32 0) (emitInstrConstI64 0)))))) ((sexprList items) (if (listEmpty? items) (if (= (wasmValType retType) 127) (emitInstrConstI32 0) (emitInstrConstI64 0)) (let [(head (sexprToAtomStr (optionOr (listGet items 0) (rd/makeAtom ""))))] (cond ((= head "if") (let [(condExpr (optionOr (listGet items 1) (rd/makeAtom ""))) (thenExpr (optionOr (listGet items 2) (rd/makeAtom ""))) (elseExpr (optionOr (listGet items 3) (rd/makeAtom ""))) (condInstrs (lowerAstExpr condExpr locals fnIndices "Bool")) (thenInstrs (lowerAstExpr thenExpr locals fnIndices retType)) (elseInstrs (if (>= (listLength items) 4) (lowerAstExpr elseExpr locals fnIndices retType) (list))) (blockType (wasmValType retType))] (listAppend condInstrs (emitInstrIf blockType thenInstrs elseInstrs)))) ((or (or (or (or (= head "+") (= head "-")) (or (= head "*") (= head "/"))) (or (or (= head "mod") (= head "=")) (or (= head "!=") (= head "<")))) (or (or (or (= head "<=") (= head ">")) (or (= head ">=") (= head "and"))) (or (= head "or") (= head "xor")))) (if (>= (listLength items) 3) (let [(lhs (optionOr (listGet items 1) (rd/makeAtom ""))) (rhs (optionOr (listGet items 2) (rd/makeAtom ""))) (opType (if (or (or (or (= head "=") (= head "!=")) (or (= head "<") (= head ">"))) (or (= head "<=") (= head ">="))) "i64" retType)) (lhsInstrs (lowerAstExpr lhs locals fnIndices opType)) (rhsInstrs (lowerAstExpr rhs locals fnIndices opType)) (opInstrs (emitInstrBinaryOp head opType))] (listAppend lhsInstrs (listAppend rhsInstrs opInstrs))) (if (= (listLength items) 2) (let [(arg (optionOr (listGet items 1) (rd/makeAtom ""))) (argInstrs (lowerAstExpr arg locals fnIndices retType))] (if (= head "-") (listAppend (emitInstrConstI64 0) (listAppend argInstrs (emitInstrBinaryOp "-" retType))) argInstrs)) (emitInstrConstI64 0)))) ((= head "do") (let [(args (optionOr (listSlice items 1 (listLength items)) (list)))] (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64) (lowerAstExpr arg locals fnIndices retType)) args)))) ((= head "drop") (let [(arg (optionOr (listGet items 1) (rd/makeAtom "")))] (listAppend (lowerAstExpr arg locals fnIndices retType) (list 26)))) ((= head "fd_write") (let [(targetIdx (optionOr (mapGet fnIndices head) 0)) (args (optionOr (listSlice items 1 (listLength items)) (list))) (argInstrs (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64) (lowerAstExpr arg locals fnIndices "I32")) args))) (callInstr (emitInstrCall targetIdx))] (if (or (= retType "Unit") (= retType "unit")) (listAppend argInstrs (listAppend callInstr (list 26))) (listAppend argInstrs callInstr)))) ((= head "proc_exit") (let [(targetIdx (optionOr (mapGet fnIndices head) 4)) (args (optionOr (listSlice items 1 (listLength items)) (list))) (argInstrs (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64) (lowerAstExpr arg locals fnIndices "I32")) args))) (callInstr (emitInstrCall targetIdx))] (listAppend argInstrs callInstr))) ((mapHas? fnIndices head) (let [(targetIdx (optionOr (mapGet fnIndices head) 0)) (args (optionOr (listSlice items 1 (listLength items)) (list))) (argInstrs (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64) (lowerAstExpr arg locals fnIndices "i64")) args))) (callInstr (emitInstrCall targetIdx))] (listAppend argInstrs callInstr))) (else (if (= (wasmValType retType) 127) (emitInstrConstI32 0) (emitInstrConstI64 0))))))) ((sexprVect _) (if (= (wasmValType retType) 127) (emitInstrConstI32 0) (emitInstrConstI64 0))))

fn lowerAstFunction d: a/DefunNode fnIndices: (Map Str Int64) -> (List Int64)
  (let [(paramsList d.params) (paramsMap (fold (fn [(acc (Map Str Int64)) (idx Int64)] (let [(p (optionOr (listGet paramsList idx) (a/Param :name "" :type "I64")))] (mapSet acc p.name idx))) (mapEmpty) (range 0 (listLength paramsList)))) (bodyList d.body) (instrs (if (listEmpty? bodyList) (list) (flattenByteLists (map (fn [(expr rd/SExpr)] -> (List Int64) (lowerAstExpr expr paramsMap fnIndices d.retType)) bodyList)))) (fullInstrs (listAppend instrs (list 11)))] (encodeFunctionBody (list) fullInstrs))

fn lowerAstTopForms forms: (List a/TopForm) -> (List Int64)
  (do (assert (not (formsHaveTopExpr? forms)) "ERR_WASM_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook (start section) in this MVP emitter") (let [(fnIndices (buildFunctionTypeIndex forms)) (defuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)] (mt f ((topDefun d) (listAppend acc (list d))) (else acc))) (list) forms)) (hdr (wasmMagicHeader)) (typeEntries (map (fn [(d a/DefunNode)] -> (List Int64) (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType p.type)) d.params)) (rTypes (if (or (= d.retType "Unit") (= d.retType "unit")) (list) (list (wasmValType d.retType))))] (encodeFuncType pTypes rTypes))) defuns)) (typeSec (encodeTypeSection typeEntries)) (typeIdxs (range 0 (listLength defuns))) (funcSec (encodeFunctionSection typeIdxs)) (exportEntries (map (fn [(idx Int64)] -> (List Int64) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list))))] (encodeExportEntry d.name 0 idx))) typeIdxs)) (exportSec (encodeExportSection exportEntries)) (bodyEntries (map (fn [(d a/DefunNode)] -> (List Int64) (lowerAstFunction d fnIndices)) defuns)) (codeSec (encodeCodeSection bodyEntries))] (listAppend hdr (listAppend typeSec (listAppend funcSec (listAppend exportSec codeSec))))))

fn lowerAstTopFormsWithImports forms: (List a/TopForm) importEntries: (List (List Int64)) importTypes: (List (List Int64)) importedFnNames: (Map Str Int64) -> (List Int64)
  (do (assert (not (formsHaveTopExpr? forms)) "ERR_WASM_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook (start section) in this MVP emitter") (let [(importCount (listLength importEntries)) (baseFnIndices (buildFunctionTypeIndexOffset forms importCount)) (fnIndices (fold (fn [(acc (Map Str Int64)) (k Str)] (mapSet acc k (optionOr (mapGet importedFnNames k) 0))) baseFnIndices (mapKeys importedFnNames))) (defuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)] (mt f ((topDefun d) (listAppend acc (list d))) (else acc))) (list) forms)) (hdr (wasmMagicHeader)) (userTypeEntries (map (fn [(d a/DefunNode)] -> (List Int64) (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType p.type)) d.params)) (rTypes (if (or (= d.retType "Unit") (= d.retType "unit")) (list) (list (wasmValType d.retType))))] (encodeFuncType pTypes rTypes))) defuns)) (allTypeEntries (listAppend importTypes userTypeEntries)) (typeSec (encodeTypeSection allTypeEntries)) (importSec (if (> importCount 0) (encodeImportSection importEntries) (list))) (typeIdxs (range (listLength importTypes) (+ (listLength importTypes) (listLength defuns)))) (funcSec (encodeFunctionSection typeIdxs)) (exportEntries (map (fn [(idx Int64)] -> (List Int64) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list))))] (encodeExportEntry d.name 0 (+ idx importCount)))) (range 0 (listLength defuns)))) (exportSec (encodeExportSection exportEntries)) (bodyEntries (map (fn [(d a/DefunNode)] -> (List Int64) (lowerAstFunction d fnIndices)) defuns)) (codeSec (encodeCodeSection bodyEntries))] (listAppend hdr (listAppend typeSec (listAppend importSec (listAppend funcSec (listAppend exportSec codeSec)))))))

fn emitWasmMemorySection -> (List Int64)
  (encodeMemorySection 1 256)

fn emitWasmRpcExports allocIdx: Int64 freeIdx: Int64 dispatchIdx: Int64 -> (List (List Int64))
  (list (encodeExportEntry "memory" 2 0) (encodeExportEntry "aslAlloc" 0 allocIdx) (encodeExportEntry "aslFree" 0 freeIdx) (encodeExportEntry "aslRpcDispatch" 0 dispatchIdx))

fn emitWasmCapabilityDenial capName: Str -> (List Int64)
  (listAppend (emitInstrConstI32 403) (list 11))

fn emitRpcDispatchInstructions -> (List Int64)
  (let [(resp "(:batch-res :status \"completed\" :bridge \"asl-core\" :zero-socket true :results [])\n") (bytes (encodeUtf8 resp)) (storeInstrs (fold (fn [(acc (List Int64)) (idx Int64)] (let [(b (optionOr (listGet bytes idx) 0))] (listAppend acc (listAppend (emitInstrLocalGet 2) (listAppend (emitInstrConstI32 b) (listAppend (list 58 0) (leb128EncodeU32 idx))))))) (list) (range 0 (listLength bytes)))) (nullTerm (listAppend (emitInstrLocalGet 2) (listAppend (emitInstrConstI32 0) (listAppend (list 58 0) (leb128EncodeU32 (listLength bytes)))))) (ifBlock (listAppend (emitInstrLocalGet 2) (listAppend (list 4 64) (listAppend storeInstrs (listAppend nullTerm (list 11))))))] (listAppend ifBlock (listAppend (emitInstrConstI32 0) (list 11))))

fn emitWasmBinaryBytes forms: (List a/TopForm) -> (List Int64)
  (do (assert (not (formsHaveTopExpr? forms)) "ERR_WASM_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook (start section) in this MVP emitter") (let [(fnIndices (buildFunctionTypeIndex forms)) (rawDefuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)] (mt f ((topDefun d) (listAppend acc (list d))) (else acc))) (list) forms)) (userDefuns (if (listEmpty? rawDefuns) (list (a/DefunNode :name "main" :typeVars (list) :isExported true :effect false :params (list) :retType "I64" :docstring "" :body (list (rd/makeAtom "0")))) rawDefuns)) (uCount (listLength userDefuns)) (allocIdx uCount) (freeIdx (+ uCount 1)) (dispatchIdx (+ uCount 2)) (userTypeEntries (map (fn [(d a/DefunNode)] -> (List Int64) (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType p.type)) d.params)) (rTypes (if (or (= d.retType "Unit") (= d.retType "unit")) (list) (list (wasmValType d.retType))))] (encodeFuncType pTypes rTypes))) userDefuns)) (allocType (encodeFuncType (list 127) (list 127))) (freeType (encodeFuncType (list 127 127) (list))) (dispatchType (encodeFuncType (list 127 127 127) (list 127))) (allTypeEntries (listAppend userTypeEntries (list allocType freeType dispatchType))) (typeSec (encodeTypeSection allTypeEntries)) (allTypeIdxs (range 0 (+ uCount 3))) (funcSec (encodeFunctionSection allTypeIdxs)) (memSec (emitWasmMemorySection)) (userExports (map (fn [(idx Int64)] -> (List Int64) (let [(d (optionOr (listGet userDefuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list))))] (encodeExportEntry d.name 0 idx))) (range 0 uCount))) (rpcExports (emitWasmRpcExports allocIdx freeIdx dispatchIdx)) (allExports (listAppend userExports rpcExports)) (exportSec (encodeExportSection allExports)) (userBodies (map (fn [(d a/DefunNode)] -> (List Int64) (lowerAstFunction d fnIndices)) userDefuns)) (allocBody (encodeFunctionBody (list (list 2 127)) (list 65 0 40 2 0 34 1 69 4 64 65 128 8 33 1 11 32 1 32 0 106 34 2 63 0 65 128 128 4 108 79 4 64 65 2 64 0 26 11 65 0 32 2 54 2 0 32 1 11))) (freeBody (encodeFunctionBody (list) (list 11))) (dispatchBody (encodeFunctionBody (list) (emitRpcDispatchInstructions))) (allBodies (listAppend userBodies (list allocBody freeBody dispatchBody))) (codeSec (encodeCodeSection allBodies))] (listAppend (wasmMagicHeader) (listAppend typeSec (listAppend funcSec (listAppend memSec (listAppend exportSec codeSec)))))))

fn emitWasmBinaryTarget forms: (List a/TopForm) -> Str
  (stringJoin (map (fn [(b Int64)] -> Str (stringFromInt64 b)) (emitWasmBinaryBytes forms)) ",")

fn encodeDataSegment offset: Int64 data: (List Int64) -> (List Int64)
  (listAppend (list 0 65) (listAppend (leb128EncodeI32 offset) (listAppend (list 11) (listAppend (leb128EncodeU32 (listLength data)) data))))

fn encodeDataSection segments: (List (List Int64)) -> (List Int64)
  (let [(count (leb128EncodeU32 (listLength segments))) (payload (listAppend count (flattenByteLists segments)))] (encodeSection 11 payload))

fn emitWasiBinaryBytes forms: (List a/TopForm) -> (List Int64)
  (do (assert (not (formsHaveTopExpr? forms)) "ERR_WASM_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook (start section) in this MVP emitter") (let [(wasiImportEntries (list (encodeImportEntry "wasi_snapshot_preview1" "fd_write" 0 0) (encodeImportEntry "wasi_snapshot_preview1" "fd_read" 0 0) (encodeImportEntry "wasi_snapshot_preview1" "path_open" 0 1) (encodeImportEntry "wasi_snapshot_preview1" "fd_close" 0 2) (encodeImportEntry "wasi_snapshot_preview1" "proc_exit" 0 3))) (wasiImportTypes (list (encodeFuncType (list 127 127 127 127) (list 127)) (encodeFuncType (list 127 127 127 127 127 126 126 127 127) (list 127)) (encodeFuncType (list 127) (list 127)) (encodeFuncType (list 127) (list)))) (wasiImportNames (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "fd_write" 0) "fd_read" 1) "path_open" 2) "fd_close" 3) "proc_exit" 4)) (importCount 5) (rawDefuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)] (mt f ((topDefun d) (listAppend acc (list d))) (else acc))) (list) forms)) (defuns (if (listEmpty? rawDefuns) (list (a/DefunNode :name "_start" :typeVars (list) :isExported true :effect false :params (list) :retType "Unit" :docstring "" :body (list (rd/makeList (list (rd/makeAtom "proc_exit") (rd/makeAtom "0")))))) rawDefuns)) (uCount (listLength defuns)) (baseFnIndices (buildFunctionTypeIndexOffset forms importCount)) (fnIndices (fold (fn [(acc (Map Str Int64)) (k Str)] (mapSet acc k (optionOr (mapGet wasiImportNames k) 0))) baseFnIndices (mapKeys wasiImportNames))) (userTypeEntries (map (fn [(d a/DefunNode)] -> (List Int64) (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType p.type)) d.params)) (rTypes (if (or (= d.retType "Unit") (= d.retType "unit")) (list) (list (wasmValType d.retType))))] (encodeFuncType pTypes rTypes))) defuns)) (allTypeEntries (listAppend wasiImportTypes userTypeEntries)) (typeSec (encodeTypeSection allTypeEntries)) (importSec (encodeImportSection wasiImportEntries)) (typeIdxs (range 4 (+ 4 uCount))) (funcSec (encodeFunctionSection typeIdxs)) (memSec (encodeMemorySection 1 256)) (userExports (map (fn [(idx Int64)] -> (List Int64) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list)))) (targetIdx (+ idx importCount))] (encodeExportEntry d.name 0 targetIdx))) (range 0 uCount))) (hasStart (fold (fn [(acc Bool) (d a/DefunNode)] (or acc (= d.name "_start"))) false defuns)) (mainIdx (fold (fn [(acc Int64) (idx Int64)] (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))] (if (= d.name "main") (+ idx importCount) acc))) -1 (range 0 uCount))) (extraExports (listAppend (list (encodeExportEntry "memory" 2 0)) (if hasStart (list) (if (>= mainIdx 0) (list (encodeExportEntry "_start" 0 mainIdx)) (list (encodeExportEntry "_start" 0 importCount)))))) (exportSec (encodeExportSection (listAppend userExports extraExports))) (bodies (map (fn [(d a/DefunNode)] -> (List Int64) (lowerAstFunction d fnIndices)) defuns)) (codeSec (encodeCodeSection bodies)) (ciovecBytes (list 32 0 0 0 13 0 0 0)) (msgBytes (list 72 101 108 108 111 44 32 87 65 83 73 33 10)) (dataSec (encodeDataSection (list (encodeDataSegment 16 ciovecBytes) (encodeDataSegment 32 msgBytes))))] (listAppend (wasmMagicHeader) (listAppend typeSec (listAppend importSec (listAppend funcSec (listAppend memSec (listAppend exportSec (listAppend codeSec dataSec)))))))))

fn emitWasiBinaryTarget forms: (List a/TopForm) -> Str
  (stringJoin (map (fn [(b Int64)] -> Str (stringFromInt64 b)) (emitWasiBinaryBytes forms)) ",")

fn wasiStandardImportEntries -> (List (List Int64))
  (list (encodeImportEntry "wasi_snapshot_preview1" "fd_write" 0 0) (encodeImportEntry "wasi_snapshot_preview1" "fd_read" 0 0) (encodeImportEntry "wasi_snapshot_preview1" "path_open" 0 1) (encodeImportEntry "wasi_snapshot_preview1" "fd_close" 0 2) (encodeImportEntry "wasi_snapshot_preview1" "proc_exit" 0 3))

fn wasiStandardImportTypes -> (List (List Int64))
  (list (encodeFuncType (list 127 127 127 127) (list 127)) (encodeFuncType (list 127 127 127 127 127 126 126 127 127) (list 127)) (encodeFuncType (list 127) (list 127)) (encodeFuncType (list 127) (list)))
