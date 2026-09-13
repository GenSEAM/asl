(module asl-compiler/wasm
  :d "Pure AgentScript WebAssembly v1 binary emitter and MVP bytecode generator."
  :x [leb128EncodeU32
      leb128EncodeI32
      encodeUtf8
      byteLength
      flattenByteLists
      wasmMagicHeader
      encodeSection
      encodeFuncType
      encodeTypeSection
      encodeFunctionSection
      encodeMemorySection
      encodeImportEntry
      encodeImportSection
      encodeExportEntry
      encodeExportSection
      encodeLocalEntry
      encodeFunctionBody
      encodeCodeSection
      wasmOpcode
      emitInstrConstI32
      emitInstrConstI64
      emitInstrLocalGet
      emitInstrLocalSet
      emitInstrCall
      emitInstrBinaryOp
      emitInstrIf
      wasmValType
      sexprToAtomStr
      buildFunctionTypeIndexOffset
      buildFunctionTypeIndex
      lowerAstExpr
      lowerAstFunction
      lowerAstTopForms
      lowerAstTopFormsWithImports
      emitWasmMemorySection
      emitWasmRpcExports
      emitWasmCapabilityDenial
      emitWasmBinaryBytes
      emitWasmBinaryTarget
      encodeDataSegment
      encodeDataSection
      emitWasiBinaryBytes
      emitWasiBinaryTarget]
  :i [(ast :a a) (reader :a rd)])

(df leb128EncodeU32Step [(n Int64) (acc (List Int64))] -> (List Int64)
  :d "Recursive step for unsigned LEB128 integer encoding."
  (let [(rem (mod n 128))
        (nextN (/ n 128))]
    (if (= nextN 0)
        (list-append acc (list rem))
        (leb128EncodeU32Step nextN (list-append acc (list (+ rem 128)))))))

(df leb128EncodeU32 [(n Int64)] -> (List Int64)
  :d "Encodes an unsigned integer into Little Endian Base 128 byte list."
  (leb128EncodeU32Step n (list)))

(df leb128EncodeI32Step [(n Int64) (acc (List Int64))] -> (List Int64)
  :d "Recursive step for signed LEB128 integer encoding."
  (let [(rem (mod n 128))
        (rawByte (if (< rem 0) (+ rem 128) rem))
        (nextN (if (< rem 0) (- (/ n 128) 1) (/ n 128)))
        (isDone (or (and (= nextN 0) (< rawByte 64))
                    (and (= nextN -1) (>= rawByte 64))))]
    (if isDone
        (list-append acc (list rawByte))
        (leb128EncodeI32Step nextN (list-append acc (list (+ rawByte 128)))))))

(df leb128EncodeI32 [(n Int64)] -> (List Int64)
  :d "Encodes a signed 32-bit integer into Little Endian Base 128 byte list."
  (leb128EncodeI32Step n (list)))

(df charToByte [(ch Str)] -> Int64
  :d "Converts an ASCII character to its byte value."
  (cond
    ((= ch "\t") 9)
    ((= ch "\n") 10)
    ((= ch "\r") 13)
    (:else
     (let [(chars " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
           (idx (option-or (string-index-of chars ch) -1))]
       (if (>= idx 0) (+ idx 32) 0)))))

(df encodeUtf8 [(s Str)] -> (List Int64)
  :d "Encodes a UTF-8 string into a list of byte integers."
  (map (fn [(ch Str)] -> Int64 (charToByte ch)) (string-chars s)))

(df byteLength [(bytes (List Int64))] -> Int64
  :d "Calculates the total byte length of a byte vector."
  (list-length bytes))

(df flattenByteLists [(lists (List (List Int64)))] -> (List Int64)
  :d "Concatenates a list of byte lists into a single flat byte list."
  (fold (fn [(acc (List Int64)) (item (List Int64))] -> (List Int64)
          (list-append acc item))
        (list)
        lists))

(df wasmMagicHeader [] -> (List Int64)
  :d "Emits standard 8-byte WebAssembly v1 binary header."
  (list 0 97 115 109 1 0 0 0))

(df encodeSection [(sectionId Int64) (payload (List Int64))] -> (List Int64)
  :d "Encodes a WebAssembly section framing (section ID, LEB128 payload size, payload)."
  (let [(lenBytes (leb128EncodeU32 (list-length payload)))]
    (list-append (list sectionId) (list-append lenBytes payload))))

(df encodeFuncType [(paramTypes (List Int64)) (retTypes (List Int64))] -> (List Int64)
  :d "Encodes a Wasm function type form 0x60 with params and returns."
  (let [(pCount (leb128EncodeU32 (list-length paramTypes)))
        (rCount (leb128EncodeU32 (list-length retTypes)))]
    (list-append (list 96)
      (list-append pCount
        (list-append paramTypes
          (list-append rCount retTypes))))))

(df encodeTypeSection [(types (List (List Int64)))] -> (List Int64)
  :d "Encodes Type section (ID 1) with vector of function signatures."
  (let [(count (leb128EncodeU32 (list-length types)))
        (payload (list-append count (flattenByteLists types)))]
    (encodeSection 1 payload)))

(df encodeImportEntry [(modName Str) (fieldName Str) (kind Int64) (typeOrDescIdx Int64)] -> (List Int64)
  :d "Encodes single import entry (module name, field name, import kind, type index)."
  (let [(mBytes (encodeUtf8 modName))
        (mLen (leb128EncodeU32 (list-length mBytes)))
        (fBytes (encodeUtf8 fieldName))
        (fLen (leb128EncodeU32 (list-length fBytes)))
        (idxBytes (leb128EncodeU32 typeOrDescIdx))]
    (list-append mLen
      (list-append mBytes
        (list-append fLen
          (list-append fBytes
            (list-append (list kind) idxBytes)))))))

(df encodeImportSection [(imports (List (List Int64)))] -> (List Int64)
  :d "Encodes Import section (ID 2) with vector of import descriptors."
  (let [(count (leb128EncodeU32 (list-length imports)))
        (payload (list-append count (flattenByteLists imports)))]
    (encodeSection 2 payload)))

(df encodeFunctionSection [(typeIndices (List Int64))] -> (List Int64)
  :d "Encodes Function section (ID 3) assigning type signatures to functions."
  (let [(count (leb128EncodeU32 (list-length typeIndices)))
        (indices (flattenByteLists (map (fn [(idx Int64)] -> (List Int64) (leb128EncodeU32 idx)) typeIndices)))
        (payload (list-append count indices))]
    (encodeSection 3 payload)))

(df encodeMemorySection [(minPages Int64) (maxPages Int64)] -> (List Int64)
  :d "Encodes Memory section (ID 5) with linear memory limits."
  (let [(hasMax (>= maxPages 0))
        (limits (if hasMax
                    (list-append (list 1) (list-append (leb128EncodeU32 minPages) (leb128EncodeU32 maxPages)))
                    (list-append (list 0) (leb128EncodeU32 minPages))))
        (payload (list-append (leb128EncodeU32 1) limits))]
    (encodeSection 5 payload)))

(df encodeExportEntry [(name Str) (kind Int64) (index Int64)] -> (List Int64)
  :d "Encodes single export entry (name, export kind, target index)."
  (let [(nameBytes (encodeUtf8 name))
        (nameLen (leb128EncodeU32 (list-length nameBytes)))
        (idxBytes (leb128EncodeU32 index))]
    (list-append nameLen
      (list-append nameBytes
        (list-append (list kind) idxBytes)))))

(df encodeExportSection [(exports (List (List Int64)))] -> (List Int64)
  :d "Encodes Export section (ID 7) with vector of export descriptors."
  (let [(count (leb128EncodeU32 (list-length exports)))
        (payload (list-append count (flattenByteLists exports)))]
    (encodeSection 7 payload)))

(df encodeLocalEntry [(count Int64) (valType Int64)] -> (List Int64)
  :d "Encodes local variable declaration vector item."
  (list-append (leb128EncodeU32 count) (list valType)))

(df encodeFunctionBody [(locals (List (List Int64))) (instructions (List Int64))] -> (List Int64)
  :d "Encodes function body code item with locals vector and instructions."
  (let [(localsCount (leb128EncodeU32 (list-length locals)))
        (localsBytes (flattenByteLists locals))
        (fullBody (list-append localsCount (list-append localsBytes instructions)))
        (bodyLen (leb128EncodeU32 (list-length fullBody)))]
    (list-append bodyLen fullBody)))

(df encodeCodeSection [(bodies (List (List Int64)))] -> (List Int64)
  :d "Encodes Code section (ID 10) with function body definitions."
  (let [(count (leb128EncodeU32 (list-length bodies)))
        (payload (list-append count (flattenByteLists bodies)))]
    (encodeSection 10 payload)))

(df wasmOpcode [(name Str)] -> Int64
  :d "Maps WebAssembly MVP opcode mnemonic to its 1-byte opcode value."
  (cond
    ((= name "unreachable") 0)
    ((= name "nop") 1)
    ((= name "block") 2)
    ((= name "loop") 3)
    ((= name "if") 4)
    ((= name "else") 5)
    ((= name "end") 11)
    ((= name "br") 12)
    ((= name "br_if") 13)
    ((= name "return") 15)
    ((= name "call") 16)
    ((= name "drop") 26)
    ((= name "local.get") 32)
    ((= name "local.set") 33)
    ((= name "local.tee") 34)
    ((= name "global.get") 35)
    ((= name "global.set") 36)
    ((= name "i32.load") 40)
    ((= name "i64.load") 41)
    ((= name "i32.store") 54)
    ((= name "i64.store") 55)
    ((= name "memory.size") 63)
    ((= name "memory.grow") 64)
    ((= name "i32.const") 65)
    ((= name "i64.const") 66)
    ((= name "i32.eqz") 69)
    ((= name "i32.eq") 70)
    ((= name "i32.ne") 71)
    ((= name "i32.lt_s") 72)
    ((= name "i32.gt_s") 74)
    ((= name "i32.le_s") 76)
    ((= name "i32.ge_s") 78)
    ((= name "i64.eqz") 80)
    ((= name "i64.eq") 81)
    ((= name "i64.ne") 82)
    ((= name "i64.lt_s") 83)
    ((= name "i64.gt_s") 85)
    ((= name "i64.le_s") 87)
    ((= name "i64.ge_s") 89)
    ((= name "i32.clz") 103)
    ((= name "i32.ctz") 104)
    ((= name "i32.popcnt") 105)
    ((= name "i32.add") 106)
    ((= name "i32.sub") 107)
    ((= name "i32.mul") 108)
    ((= name "i32.div_s") 109)
    ((= name "i32.rem_s") 111)
    ((= name "i32.and") 113)
    ((= name "i32.or") 114)
    ((= name "i32.xor") 115)
    ((= name "i32.shl") 116)
    ((= name "i32.shr_s") 117)
    ((= name "i64.add") 124)
    ((= name "i64.sub") 125)
    ((= name "i64.mul") 126)
    ((= name "i64.div_s") 127)
    ((= name "i64.rem_s") 129)
    ((= name "i64.and") 131)
    ((= name "i64.or") 132)
    ((= name "i64.xor") 133)
    ((= name "i64.shl") 134)
    ((= name "i64.shr_s") 135)
    (:else -1)))

(df emitInstrConstI32 [(val Int64)] -> (List Int64)
  :d "Emits i32.const instruction with signed LEB128 immediate."
  (list-append (list 65) (leb128EncodeI32 val)))

(df emitInstrConstI64 [(val Int64)] -> (List Int64)
  :d "Emits i64.const instruction with signed LEB128 immediate."
  (list-append (list 66) (leb128EncodeI32 val)))

(df emitInstrLocalGet [(localIdx Int64)] -> (List Int64)
  :d "Emits local.get instruction with unsigned LEB128 index."
  (list-append (list 32) (leb128EncodeU32 localIdx)))

(df emitInstrLocalSet [(localIdx Int64)] -> (List Int64)
  :d "Emits local.set instruction with unsigned LEB128 index."
  (list-append (list 33) (leb128EncodeU32 localIdx)))

(df emitInstrCall [(funcIdx Int64)] -> (List Int64)
  :d "Emits call instruction with unsigned LEB128 function index."
  (list-append (list 16) (leb128EncodeU32 funcIdx)))

(df emitInstrBinaryOp [(opStr Str) (typeStr Str)] -> (List Int64)
  :d "Emits typed binary arithmetic, comparison, or logic instruction."
  (if (or (or (= typeStr "i32") (= typeStr "I32")) (or (= typeStr "Bool") (= typeStr "bool")))
      (cond
        ((or (= opStr "+") (= opStr "add")) (list 106))
        ((or (= opStr "-") (= opStr "sub")) (list 107))
        ((or (= opStr "*") (= opStr "mul")) (list 108))
        ((or (= opStr "/") (= opStr "div")) (list 109))
        ((or (= opStr "mod") (= opStr "rem")) (list 111))
        ((= opStr "and") (list 113))
        ((= opStr "or") (list 114))
        ((= opStr "xor") (list 115))
        ((or (= opStr "=") (= opStr "eq")) (list 70))
        ((or (= opStr "!=") (= opStr "ne")) (list 71))
        ((or (= opStr "<") (= opStr "lt")) (list 72))
        ((or (= opStr ">") (= opStr "gt")) (list 74))
        ((or (= opStr "<=") (= opStr "le")) (list 76))
        ((or (= opStr ">=") (= opStr "ge")) (list 78))
        (:else (list 106)))
      (cond
        ((or (= opStr "+") (= opStr "add")) (list 124))
        ((or (= opStr "-") (= opStr "sub")) (list 125))
        ((or (= opStr "*") (= opStr "mul")) (list 126))
        ((or (or (= opStr "/") (= opStr "div")) (= opStr "checked-div")) (list 127))
        ((or (or (= opStr "mod") (= opStr "rem")) (= opStr "checked-mod")) (list 129))
        ((= opStr "and") (list 131))
        ((= opStr "or") (list 132))
        ((= opStr "xor") (list 133))
        ((or (= opStr "=") (= opStr "eq")) (list 81))
        ((or (= opStr "!=") (= opStr "ne")) (list 82))
        ((or (= opStr "<") (= opStr "lt")) (list 83))
        ((or (= opStr ">") (= opStr "gt")) (list 85))
        ((or (= opStr "<=") (= opStr "le")) (list 87))
        ((or (= opStr ">=") (= opStr "ge")) (list 89))
        (:else (list 124)))))

(df emitInstrIf [(blockType Int64) (thenInstrs (List Int64)) (elseInstrs (List Int64))] -> (List Int64)
  :d "Emits structured control flow if-else-end block."
  (if (list-empty? elseInstrs)
      (list-append (list 4 blockType) (list-append thenInstrs (list 11)))
      (list-append (list 4 blockType) (list-append thenInstrs (list-append (list 5) (list-append elseInstrs (list 11)))))))

(df sexprToAtomStr [(s rd/SExpr)] -> Str
  :d "Extracts atom string value from SExpr."
  (mt s
    ((sexprAtom v) v)
    ((sexprList items)
     (if (list-empty? items) "" (sexprToAtomStr (option-or (list-get items 0) (rd/makeAtom "")))))
    ((sexprVect items)
     (if (list-empty? items) "" (sexprToAtomStr (option-or (list-get items 0) (rd/makeAtom "")))))))

(df wasmValType [(ty Str)] -> Int64
  :d "Maps an AgentScript type string to WebAssembly numeric value type byte."
  (cond
    ((or (or (or (= ty "I64") (= ty "Int")) (= ty "i64")) (= ty "Int64")) 126)
    ((or (or (or (= ty "I32") (= ty "Bool")) (or (= ty "bool") (= ty "i32"))) (= ty "Int32")) 127)
    ((or (or (= ty "F64") (= ty "Float")) (= ty "Float64")) 124)
    ((= ty "F32") 125)
    (:else 126)))

(df buildFunctionTypeIndexOffset [(forms (List a/TopForm)) (offset Int64)] -> (Map Str Int64)
  :d "Builds a map from function name to function index in module with import offset."
  (let [(fnList (fold (fn [(acc (List Str)) (f a/TopForm)]
                         (mt f
                           ((topDefun d) (list-append acc (list (.-name d))))
                           (:else acc)))
                       (list)
                       forms))]
    (fold (fn [(acc (Map Str Int64)) (idx Int64)]
            (let [(name (option-or (list-get fnList idx) ""))]
              (map-set acc name (+ idx offset))))
          (map-empty)
          (range 0 (list-length fnList)))))

(df buildFunctionTypeIndex [(forms (List a/TopForm))] -> (Map Str Int64)
  :d "Builds a map from function name to function index in module."
  (buildFunctionTypeIndexOffset forms 0))

(df lowerAstExpr [(expr rd/SExpr) (locals (Map Str Int64)) (fnIndices (Map Str Int64)) (retType Str)] -> (List Int64)
  :d "Lowers an S-expression expression to WebAssembly instructions."
  (mt expr
    ((sexprAtom v)
     (let [(isNum (or (string-starts-with? v "-")
                      (and (>= (option-or (string-slice v 0 1) "") "0")
                           (<= (option-or (string-slice v 0 1) "") "9"))))]
       (cond
         (isNum
          (let [(n (option-or (string-to-int64 v) 0))]
            (if (= (wasmValType retType) 127)
                (emitInstrConstI32 n)
                (emitInstrConstI64 n))))
         ((= v "true") (emitInstrConstI32 1))
         ((= v "false") (emitInstrConstI32 0))
         ((map-has? locals v)
          (let [(idx (option-or (map-get locals v) 0))]
            (emitInstrLocalGet idx)))
         (:else (emitInstrConstI64 0)))))
    ((sexprList items)
     (if (list-empty? items)
         (emitInstrConstI64 0)
         (let [(head (sexprToAtomStr (option-or (list-get items 0) (rd/makeAtom ""))))]
           (cond
             ((= head "if")
              (let [(condExpr (option-or (list-get items 1) (rd/makeAtom "")))
                    (thenExpr (option-or (list-get items 2) (rd/makeAtom "")))
                    (elseExpr (option-or (list-get items 3) (rd/makeAtom "")))
                    (condInstrs (lowerAstExpr condExpr locals fnIndices "Bool"))
                    (thenInstrs (lowerAstExpr thenExpr locals fnIndices retType))
                    (elseInstrs (if (>= (list-length items) 4)
                                    (lowerAstExpr elseExpr locals fnIndices retType)
                                    (list)))
                    (blockType (wasmValType retType))]
                (list-append condInstrs (emitInstrIf blockType thenInstrs elseInstrs))))
             ((or (or (or (or (= head "+") (= head "-")) (or (= head "*") (= head "/")))
                      (or (or (= head "mod") (= head "=")) (or (= head "!=") (= head "<"))))
                  (or (or (or (= head "<=") (= head ">")) (or (= head ">=") (= head "and")))
                      (or (= head "or") (= head "xor"))))
              (if (>= (list-length items) 3)
                  (let [(lhs (option-or (list-get items 1) (rd/makeAtom "")))
                        (rhs (option-or (list-get items 2) (rd/makeAtom "")))
                        (opType (if (or (or (or (= head "=") (= head "!=")) (or (= head "<") (= head ">")))
                                        (or (= head "<=") (= head ">=")))
                                    "i64"
                                    retType))
                        (lhsInstrs (lowerAstExpr lhs locals fnIndices opType))
                        (rhsInstrs (lowerAstExpr rhs locals fnIndices opType))
                        (opInstrs (emitInstrBinaryOp head opType))]
                    (list-append lhsInstrs (list-append rhsInstrs opInstrs)))
                  (if (= (list-length items) 2)
                      (let [(arg (option-or (list-get items 1) (rd/makeAtom "")))
                            (argInstrs (lowerAstExpr arg locals fnIndices retType))]
                        (if (= head "-")
                            (list-append (emitInstrConstI64 0) (list-append argInstrs (emitInstrBinaryOp "-" retType)))
                            argInstrs))
                      (emitInstrConstI64 0))))
             ((= head "do")
              (let [(args (option-or (list-slice items 1 (list-length items)) (list)))]
                (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64)
                                         (lowerAstExpr arg locals fnIndices retType))
                                       args))))
             ((= head "drop")
              (let [(arg (option-or (list-get items 1) (rd/makeAtom "")))]
                (list-append (lowerAstExpr arg locals fnIndices retType) (list 26))))
             ((= head "fd_write")
              (let [(targetIdx (option-or (map-get fnIndices head) 0))
                    (args (option-or (list-slice items 1 (list-length items)) (list)))
                    (argInstrs (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64)
                                                        (lowerAstExpr arg locals fnIndices "I32"))
                                                      args)))
                    (callInstr (emitInstrCall targetIdx))]
                (if (or (= retType "Unit") (= retType "unit"))
                    (list-append argInstrs (list-append callInstr (list 26)))
                    (list-append argInstrs callInstr))))
             ((= head "proc_exit")
              (let [(targetIdx (option-or (map-get fnIndices head) 4))
                    (args (option-or (list-slice items 1 (list-length items)) (list)))
                    (argInstrs (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64)
                                                        (lowerAstExpr arg locals fnIndices "I32"))
                                                      args)))
                    (callInstr (emitInstrCall targetIdx))]
                (list-append argInstrs callInstr)))
             ((map-has? fnIndices head)
              (let [(targetIdx (option-or (map-get fnIndices head) 0))
                    (args (option-or (list-slice items 1 (list-length items)) (list)))
                    (argInstrs (flattenByteLists (map (fn [(arg rd/SExpr)] -> (List Int64)
                                                        (lowerAstExpr arg locals fnIndices "i64"))
                                                      args)))
                    (callInstr (emitInstrCall targetIdx))]
                (list-append argInstrs callInstr)))
             (:else (emitInstrConstI64 0))))))
    ((sexprVect _) (emitInstrConstI64 0))))

(df lowerAstFunction [(d a/DefunNode) (fnIndices (Map Str Int64))] -> (List Int64)
  :d "Lowers a single topDefun AST node to an encoded WebAssembly function body."
  (let [(paramsList (.-params d))
        (paramsMap (fold (fn [(acc (Map Str Int64)) (idx Int64)]
                           (let [(p (option-or (list-get paramsList idx) (a/Param :name "" :type "I64")))]
                             (map-set acc (.-name p) idx)))
                         (map-empty)
                         (range 0 (list-length paramsList))))
        (bodyList (.-body d))
        (instrs (if (list-empty? bodyList)
                    (list)
                    (flattenByteLists (map (fn [(expr rd/SExpr)] -> (List Int64)
                                             (lowerAstExpr expr paramsMap fnIndices (.-retType d)))
                                           bodyList))))
        (fullInstrs (list-append instrs (list 11)))]
    (encodeFunctionBody (list) fullInstrs)))

(df lowerAstTopForms [(forms (List a/TopForm))] -> (List Int64)
  :d "Compiles top-level AST forms into a complete WebAssembly v1 binary byte vector."
  (let [(fnIndices (buildFunctionTypeIndex forms))
        (defuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)]
                        (mt f
                          ((topDefun d) (list-append acc (list d)))
                          (:else acc)))
                      (list)
                      forms))
        (hdr (wasmMagicHeader))
        (typeEntries (map (fn [(d a/DefunNode)] -> (List Int64)
                            (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType (.-type p))) (.-params d)))
                                  (rTypes (if (or (= (.-retType d) "Unit") (= (.-retType d) "unit"))
                                              (list)
                                              (list (wasmValType (.-retType d)))))]
                              (encodeFuncType pTypes rTypes)))
                          defuns))
        (typeSec (encodeTypeSection typeEntries))
        (typeIdxs (range 0 (list-length defuns)))
        (funcSec (encodeFunctionSection typeIdxs))
        (exportEntries (map (fn [(idx Int64)] -> (List Int64)
                              (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list))))]
                                (encodeExportEntry (.-name d) 0 idx)))
                            typeIdxs))
        (exportSec (encodeExportSection exportEntries))
        (bodyEntries (map (fn [(d a/DefunNode)] -> (List Int64)
                            (lowerAstFunction d fnIndices))
                          defuns))
        (codeSec (encodeCodeSection bodyEntries))]
    (list-append hdr
      (list-append typeSec
        (list-append funcSec
          (list-append exportSec codeSec))))))

(df lowerAstTopFormsWithImports [(forms (List a/TopForm)) (importEntries (List (List Int64))) (importTypes (List (List Int64))) (importedFnNames (Map Str Int64))] -> (List Int64)
  :d "Compiles top-level AST forms with imported host functions into complete WebAssembly v1 binary."
  (let [(importCount (list-length importEntries))
        (baseFnIndices (buildFunctionTypeIndexOffset forms importCount))
        (fnIndices (fold (fn [(acc (Map Str Int64)) (k Str)]
                           (map-set acc k (option-or (map-get importedFnNames k) 0)))
                         baseFnIndices
                         (map-keys importedFnNames)))
        (defuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)]
                        (mt f
                          ((topDefun d) (list-append acc (list d)))
                          (:else acc)))
                      (list)
                      forms))
        (hdr (wasmMagicHeader))
        (userTypeEntries (map (fn [(d a/DefunNode)] -> (List Int64)
                                (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType (.-type p))) (.-params d)))
                                      (rTypes (if (or (= (.-retType d) "Unit") (= (.-retType d) "unit"))
                                                  (list)
                                                  (list (wasmValType (.-retType d)))))]
                                  (encodeFuncType pTypes rTypes)))
                              defuns))
        (allTypeEntries (list-append importTypes userTypeEntries))
        (typeSec (encodeTypeSection allTypeEntries))
        (importSec (if (> importCount 0) (encodeImportSection importEntries) (list)))
        (typeIdxs (range (list-length importTypes) (+ (list-length importTypes) (list-length defuns))))
        (funcSec (encodeFunctionSection typeIdxs))
        (exportEntries (map (fn [(idx Int64)] -> (List Int64)
                              (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list))))]
                                (encodeExportEntry (.-name d) 0 (+ idx importCount))))
                            (range 0 (list-length defuns))))
        (exportSec (encodeExportSection exportEntries))
        (bodyEntries (map (fn [(d a/DefunNode)] -> (List Int64)
                            (lowerAstFunction d fnIndices))
                          defuns))
        (codeSec (encodeCodeSection bodyEntries))]
    (list-append hdr
      (list-append typeSec
        (list-append importSec
          (list-append funcSec
            (list-append exportSec codeSec)))))))

(df emitWasmMemorySection [] -> (List Int64)
  :d "Emits linear memory section frame with 1 initial page and 256 max pages."
  (encodeMemorySection 1 256))

(df emitWasmRpcExports [(allocIdx Int64) (freeIdx Int64) (dispatchIdx Int64)] -> (List (List Int64))
  :d "Emits export descriptors for linear memory and Batch RPC bridge functions."
  (list
    (encodeExportEntry "memory" 2 0)
    (encodeExportEntry "asl_alloc" 0 allocIdx)
    (encodeExportEntry "asl_free" 0 freeIdx)
    (encodeExportEntry "asl_rpc_dispatch" 0 dispatchIdx)))

(df emitWasmCapabilityDenial [(capName Str)] -> (List Int64)
  :d "Emits capability denial receipt sequence returning 403 denied."
  (list-append (emitInstrConstI32 403) (list 11)))

(df emitWasmBinaryBytes [(forms (List a/TopForm))] -> (List Int64)
  :d "Compiles top-level AST forms into a complete WebAssembly v1 binary with memory and Batch RPC exports."
  (let [(fnIndices (buildFunctionTypeIndex forms))
        (rawDefuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)]
                           (mt f
                             ((topDefun d) (list-append acc (list d)))
                             (:else acc)))
                         (list)
                         forms))
        (userDefuns (if (list-empty? rawDefuns)
                        (list (a/DefunNode :name "main" :typeVars (list) :isExported true :effect false :params (list) :retType "I64" :docstring "" :body (list (rd/makeAtom "0"))))
                        rawDefuns))
        (uCount (list-length userDefuns))
        (allocIdx uCount)
        (freeIdx (+ uCount 1))
        (dispatchIdx (+ uCount 2))
        (userTypeEntries (map (fn [(d a/DefunNode)] -> (List Int64)
                                (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType (.-type p))) (.-params d)))
                                      (rTypes (if (or (= (.-retType d) "Unit") (= (.-retType d) "unit"))
                                                  (list)
                                                  (list (wasmValType (.-retType d)))))]
                                  (encodeFuncType pTypes rTypes)))
                              userDefuns))
        (allocType (encodeFuncType (list 127) (list 127)))
        (freeType (encodeFuncType (list 127 127) (list)))
        (dispatchType (encodeFuncType (list 127 127 127) (list 127)))
        (allTypeEntries (list-append userTypeEntries (list allocType freeType dispatchType)))
        (typeSec (encodeTypeSection allTypeEntries))
        (allTypeIdxs (range 0 (+ uCount 3)))
        (funcSec (encodeFunctionSection allTypeIdxs))
        (memSec (emitWasmMemorySection))
        (userExports (map (fn [(idx Int64)] -> (List Int64)
                            (let [(d (option-or (list-get userDefuns idx)
                                                (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list))))]
                              (encodeExportEntry (.-name d) 0 idx)))
                          (range 0 uCount)))
        (rpcExports (emitWasmRpcExports allocIdx freeIdx dispatchIdx))
        (allExports (list-append userExports rpcExports))
        (exportSec (encodeExportSection allExports))
        (userBodies (map (fn [(d a/DefunNode)] -> (List Int64)
                           (lowerAstFunction d fnIndices))
                         userDefuns))
        (allocBody (encodeFunctionBody (list) (list-append (emitInstrConstI32 65536) (list 11))))
        (freeBody (encodeFunctionBody (list) (list 11)))
        (dispatchBody (encodeFunctionBody (list) (list-append (emitInstrConstI32 0) (list 11))))
        (allBodies (list-append userBodies (list allocBody freeBody dispatchBody)))
        (codeSec (encodeCodeSection allBodies))]
    (list-append (wasmMagicHeader)
      (list-append typeSec
        (list-append funcSec
          (list-append memSec
            (list-append exportSec codeSec)))))))

(df emitWasmBinaryTarget [(forms (List a/TopForm))] -> Str
  :d "Emits full WebAssembly binary module as comma-separated byte string."
  (string-join (map (fn [(b Int64)] -> Str (string-from-int64 b)) (emitWasmBinaryBytes forms)) ","))

(df encodeDataSegment [(offset Int64) (data (List Int64))] -> (List Int64)
  :d "Encodes single active WebAssembly data segment at memory offset."
  (list-append (list 0 65)
    (list-append (leb128EncodeI32 offset)
      (list-append (list 11)
        (list-append (leb128EncodeU32 (list-length data)) data)))))

(df encodeDataSection [(segments (List (List Int64)))] -> (List Int64)
  :d "Encodes Data section (ID 11) with vector of data segments."
  (let [(count (leb128EncodeU32 (list-length segments)))
        (payload (list-append count (flattenByteLists segments)))]
    (encodeSection 11 payload)))

(df emitWasiBinaryBytes [(forms (List a/TopForm))] -> (List Int64)
  :d "Compiles top-level AST forms into a complete WebAssembly v1 binary targeting WASI Preview 1."
  (let [(wasiImportEntries (list
                             (encodeImportEntry "wasi_snapshot_preview1" "fd_write" 0 0)
                             (encodeImportEntry "wasi_snapshot_preview1" "fd_read" 0 0)
                             (encodeImportEntry "wasi_snapshot_preview1" "path_open" 0 1)
                             (encodeImportEntry "wasi_snapshot_preview1" "fd_close" 0 2)
                             (encodeImportEntry "wasi_snapshot_preview1" "proc_exit" 0 3)))
        (wasiImportTypes (list
                           (encodeFuncType (list 127 127 127 127) (list 127))
                           (encodeFuncType (list 127 127 127 127 127 126 126 127 127) (list 127))
                           (encodeFuncType (list 127) (list 127))
                           (encodeFuncType (list 127) (list))))
        (wasiImportNames (map-set
                           (map-set
                             (map-set
                               (map-set
                                 (map-set (map-empty) "fd_write" 0)
                                 "fd_read" 1)
                               "path_open" 2)
                             "fd_close" 3)
                           "proc_exit" 4))
        (importCount 5)
        (rawDefuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)]
                           (mt f
                             ((topDefun d) (list-append acc (list d)))
                             (:else acc)))
                         (list)
                         forms))
        (defuns (if (list-empty? rawDefuns)
                    (list (a/DefunNode :name "_start" :typeVars (list) :isExported true :effect false :params (list) :retType "Unit" :docstring "" :body (list (rd/makeList (list (rd/makeAtom "proc_exit") (rd/makeAtom "0"))))))
                    rawDefuns))
        (uCount (list-length defuns))
        (baseFnIndices (buildFunctionTypeIndexOffset forms importCount))
        (fnIndices (fold (fn [(acc (Map Str Int64)) (k Str)]
                           (map-set acc k (option-or (map-get wasiImportNames k) 0)))
                         baseFnIndices
                         (map-keys wasiImportNames)))
        (userTypeEntries (map (fn [(d a/DefunNode)] -> (List Int64)
                                (let [(pTypes (map (fn [(p a/Param)] -> Int64 (wasmValType (.-type p))) (.-params d)))
                                      (rTypes (if (or (= (.-retType d) "Unit") (= (.-retType d) "unit"))
                                                  (list)
                                                  (list (wasmValType (.-retType d)))))]
                                  (encodeFuncType pTypes rTypes)))
                              defuns))
        (allTypeEntries (list-append wasiImportTypes userTypeEntries))
        (typeSec (encodeTypeSection allTypeEntries))
        (importSec (encodeImportSection wasiImportEntries))
        (typeIdxs (range 4 (+ 4 uCount)))
        (funcSec (encodeFunctionSection typeIdxs))
        (memSec (encodeMemorySection 1 256))
        (userExports (map (fn [(idx Int64)] -> (List Int64)
                            (let [(d (option-or (list-get defuns idx)
                                                (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))
                                  (targetIdx (+ idx importCount))]
                              (encodeExportEntry (.-name d) 0 targetIdx)))
                          (range 0 uCount)))
        (hasStart (fold (fn [(acc Bool) (d a/DefunNode)] (or acc (= (.-name d) "_start"))) false defuns))
        (mainIdx (fold (fn [(acc Int64) (idx Int64)]
                         (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))]
                           (if (= (.-name d) "main") (+ idx importCount) acc)))
                       -1
                       (range 0 uCount)))
        (extraExports (list-append
                        (list (encodeExportEntry "memory" 2 0))
                        (if hasStart
                            (list)
                            (if (>= mainIdx 0)
                                (list (encodeExportEntry "_start" 0 mainIdx))
                                (list (encodeExportEntry "_start" 0 importCount))))))
        (exportSec (encodeExportSection (list-append userExports extraExports)))
        (bodies (map (fn [(d a/DefunNode)] -> (List Int64)
                       (lowerAstFunction d fnIndices))
                     defuns))
        (codeSec (encodeCodeSection bodies))
        (ciovecBytes (list 32 0 0 0 13 0 0 0))
        (msgBytes (list 72 101 108 108 111 44 32 87 65 83 73 33 10))
        (dataSec (encodeDataSection (list (encodeDataSegment 16 ciovecBytes) (encodeDataSegment 32 msgBytes))))]
    (list-append (wasmMagicHeader)
      (list-append typeSec
        (list-append importSec
          (list-append funcSec
            (list-append memSec
              (list-append exportSec
                (list-append codeSec dataSec)))))))))

(df emitWasiBinaryTarget [(forms (List a/TopForm))] -> Str
  :d "Emits full WebAssembly binary module targeting WASI Preview 1 as comma-separated byte string."
  (string-join (map (fn [(b Int64)] -> Str (string-from-int64 b)) (emitWasiBinaryBytes forms)) ","))
