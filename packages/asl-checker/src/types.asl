(module asl-checker/types :x [Type Diagnostic genericRows genericMulti? genericAlias genericConcrete genericCandidates genericRenamed genericAliasNames stringBuiltinNames renamedHint genericName? genericSigName receiverOver isTyVar? resolveTypeAlias unorderedType? intRangeBounds preludeUnionCases isNumericType? isIntegralType? builtinSig parseTypeStr showTypes showType collectTvars] :i [(lowLevelSigs :a ll)])

(enum Type (:c tyCon [(name String) (args (List Type)) (mod (Option String)) (shown (Option String))] "A nominal or constructed type") (:c tyVar [(id Int64) (kind String)] "A type variable metavariable: any, num, or int") (:c tyFun [(params (List Type)) (ret Type)] "A function type"))

(schema Diagnostic (:f code String) (:f message String) (:f msg String) (:f line Int64) (:f col Int64) (:f path String))

fn resolveTypeAlias name: String -> String
  (cond ((= name "Bool") "Bool") ((= name "F32") "Float64") ((= name "F64") "Float64") ((= name "Float") "Float64") ((= name "I32") "Int32") ((= name "I64") "Int64") ((= name "Int") "Int64") ((= name "Num") "Float64") ((= name "Str") "String") ((= name "Unit") "Unit") ((= name "Bytes") "Bytes") (else name))

fn unorderedType? name: String -> Bool
  (or (= name "Float64") (= name "IoError"))

fn intRangeBounds name: String -> (Option (Pair Int64 Int64))
  (cond ((= name "U8") (some (pair 0 255))) ((= name "I8") (some (pair -128 127))) ((= name "U16") (some (pair 0 65535))) ((= name "I16") (some (pair -32768 32767))) ((= name "U32") (some (pair 0 4294967295))) ((= name "U64") (some (pair 0 9223372036854775807))) ((= name "Int32") (some (pair -2147483648 2147483647))) ((= name "Int64") (some (pair -9223372036854775808 9223372036854775807))) (else (none)))

fn preludeUnionCases caseName: String -> (Option String)
  (cond ((= caseName "alreadyExists") (some "IoError")) ((= caseName "interrupted") (some "IoError")) ((= caseName "invalidPath") (some "IoError")) ((= caseName "notFound") (some "IoError")) ((= caseName "other") (some "IoError")) ((= caseName "permissionDenied") (some "IoError")) ((= caseName "some") (some "Option")) ((= caseName "none") (some "Option")) ((= caseName "ok") (some "Result")) ((= caseName "err") (some "Result")) ((= caseName "list") (some "List")) ((= caseName "cons") (some "List")) ((= caseName "preludeLeaf") (some "PreludeTree")) ((= caseName "preludeNode") (some "PreludeTree")) (else (none)))

fn isNumericType? name: String -> Bool
  (or (listContains? (ll/sizedIntNames) name) (or (= name "Int32") (or (= name "Int64") (= name "Float64"))))

fn isIntegralType? name: String -> Bool
  (or (listContains? (ll/sizedIntNames) name) (or (= name "Int32") (= name "Int64")))

fn sigFn params: (List String) ret: String -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair false ret)))

fn sigVar params: (List String) ret: String -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair true ret)))

fn numBinopSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "N" "N") "N")

fn shiftBinopSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "Int64" "Int64") "Int64")

fn bitNotSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "Int64") "Int64")

fn cmpBinopSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "T" "T") "Bool")

fn ioerrorCtorSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list) "IoError")

fn strPredSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "String" "String") "Bool")

fn listOptSig -> (Option (Pair (List String) (Pair Bool String)))
  (sigFn (list "(List T)") "(Option T)")

fn arrayBuiltinSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond
    ((= name "f64ArrayLen") (sigFn (list "F64Array") "Int64"))
    ((= name "f64ArrayGet") (sigFn (list "F64Array" "Int64") "Float64"))
    ((= name "f64ArraySlice") (sigFn (list "F64Array" "Int64" "Int64") "F64Array"))
    ((= name "f64ArrayConcat") (sigFn (list "(List F64Array)") "F64Array"))
    ((= name "f64ArrayGenerate") (sigFn (list "Int64" "(fn [Int64] -> Float64)") "F64Array"))
    ((= name "f64ArraySum") (sigFn (list "F64Array") "Float64"))
    ((= name "f64ArrayCountEq") (sigFn (list "F64Array" "Float64") "Int64"))
    ((= name "f64ArrayFold") (sigFn (list "(fn [B Float64] -> B)" "B" "F64Array") "B"))
    ((= name "f64ArrayScan") (sigFn (list "(fn [Float64 Float64] -> Float64)" "Float64" "F64Array") "F64Array"))
    ((= name "i64ArrayLen") (sigFn (list "I64Array") "Int64"))
    ((= name "i64ArrayGet") (sigFn (list "I64Array" "Int64") "Int64"))
    ((= name "i64ArraySlice") (sigFn (list "I64Array" "Int64" "Int64") "I64Array"))
    ((= name "i64ArrayConcat") (sigFn (list "(List I64Array)") "I64Array"))
    ((= name "i64ArrayGenerate") (sigFn (list "Int64" "(fn [Int64] -> Int64)") "I64Array"))
    ((= name "i64ArraySum") (sigFn (list "I64Array") "Int64"))
    ((= name "i64ArrayCountEq") (sigFn (list "I64Array" "Int64") "Int64"))
    ((= name "i64ArrayFold") (sigFn (list "(fn [Int64 Int64] -> Int64)" "Int64" "I64Array") "Int64"))
    ((= name "i64ArrayScan") (sigFn (list "(fn [Int64 Int64] -> Int64)" "Int64" "I64Array") "I64Array"))
    ((= name "i8ArrayLen") (sigFn (list "I8Array") "Int64"))
    ((= name "i8ArrayGet") (sigFn (list "I8Array" "Int64") "Int64"))
    ((= name "i8ArraySlice") (sigFn (list "I8Array" "Int64" "Int64") "I8Array"))
    ((= name "i8ArrayConcat") (sigFn (list "(List I8Array)") "I8Array"))
    ((= name "i8ArrayGenerate") (sigFn (list "Int64" "(fn [Int64] -> Int64)") "I8Array"))
    ((= name "i8ArraySum") (sigFn (list "I8Array") "Int64"))
    ((= name "i8ArrayCountEq") (sigFn (list "I8Array" "Int64") "Int64"))
    ((= name "i8ArrayFold") (sigFn (list "(fn [Int64 Int64] -> Int64)" "Int64" "I8Array") "Int64"))
    ((= name "i8ArrayScan") (sigFn (list "(fn [Int64 Int64] -> Int64)" "Int64" "I8Array") "I8Array"))
    ((= name "dot") (sigFn (list "F64Array" "F64Array") "Float64"))
    ((= name "axpy") (sigFn (list "Float64" "F64Array" "F64Array") "F64Array"))
    ((= name "gemm") (sigFn (list "Int64" "Int64" "Int64" "F64Array" "F64Array") "F64Array"))
    (else (none)))

fn builtinSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond ((= name "fnv1a64") (sigFn (list "String") "Int64")) ((some? (ll/lowLevelSig name)) (ll/lowLevelSig name)) (else (match (arrayBuiltinSig name) ((some signature) (some signature)) ((none) (match (builtinSigFallback name) ((some signature) (some signature)) ((none) (hostBuiltinSig name)))))))

fn hostBuiltinSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond ((= name "fdClose") (sigFn (list "Int64") "(Result Unit String)"))
        ((= name "fdPoll") (sigFn (list "(List (Pair Int64 Int64))" "Int64") "(Result (List (Pair Int64 Int64)) String)"))
        ((= name "procWaitPid") (sigFn (list "Int64" "Bool") "(Result (Option Int64) String)"))
        ((= name "procSpawnv") (sigFn (list "(List String)" "(Option String)" "(Option (List String))") "(Result SpawnedProc String)"))
        ((= name "procExecv") (sigFn (list "(List String)" "(Option (List String))") "(Result Unit String)"))
        ((= name "envList") (sigFn (list) "(List String)"))
        ((= name "procKill") (sigFn (list "Int64" "String") "(Result Unit String)"))
        ((= name "procSelf") (sigFn (list) "Int64"))
        ((= name "argInt") (sigFn (list "(List String)" "Int64" "Int64") "Int64"))
        ((= name "argStr") (sigFn (list "(List String)" "Int64" "String") "String"))
        ((= name "preludeMainDone") (sigFn (list "Unit") "(Result Unit String)"))
        ((= name "preludeScriptFail") (sigFn (list "Int64" "Int64" "String") "(Result Int64 String)"))
        ((= name "fdWrite") (sigFn (list "Int64" "String") "(Result Int64 String)"))
        ((= name "fdNonBlocking") (sigFn (list "Int64" "Bool") "(Result Unit String)"))
        ((= name "cpuCount") (sigFn (list) "(Result Int64 String)"))
        ((= name "procAlive?") (sigFn (list "Int64") "(Result Bool String)"))
        ((= name "procWaitAny") (sigFn (list "(List Int64)" "Int64") "(Result (Option (Pair Int64 Int64)) String)"))
        ((= name "procPoll") (sigFn (list "(List (Pair Int64 Int64))" "(List Int64)" "Int64") "(Result (Pair (List (Pair Int64 Int64)) (List (Pair Int64 Int64))) String)"))
        ((= name "floatInf") (sigFn (list) "Float64"))
        ((= name "floatNan") (sigFn (list) "Float64"))
        ((= name "floatNegInf") (sigFn (list) "Float64"))
        ((= name "pathSymlink") (sigFn (list "String" "String") "(Result Unit String)"))
        ((= name "fileLstat") (sigFn (list "String") "(Result LinkStat String)"))
        ((= name "fileUtime") (sigFn (list "String" "Int64") "(Result Unit String)"))
        ((= name "platformInfo") (sigFn (list) "(Result PlatformInfo String)"))
        ((= name "preludeHead") (sigFn (list "(List T)") "T"))
        ((= name "preludeTail") (sigFn (list "(List T)") "(List T)"))
        ((= name "stringLines") (sigFn (list "String") "(List String)"))
        ((= name "charCode") (sigFn (list "String") "Int64"))
        ((= name "stringConcat") (sigFn (list "String" "String") "String"))
        ((= name "fileChmod") (sigFn (list "String" "Int64") "(Result Unit String)"))
        ((= name "fileFsync") (sigFn (list "String") "(Result Unit String)"))
        ((= name "getHomeDir") (sigFn (list) "(Result String String)"))
        ((= name "localDate") (sigFn (list) "(Result String String)"))
        ((= name "procRusage") (sigFn (list) "(Result Rusage String)"))
        ((= name "zstdDecompress") (sigFn (list "Bytes") "(Result Bytes String)"))
        ((= name "popcount64") (sigFn (list "Int64") "Int64"))
        ((= name "parquetOpen") (sigFn (list "String") "(Result ParquetHandle String)"))
        ((= name "parquetNumRowGroups") (sigFn (list "ParquetHandle") "Int64"))
        ((= name "parquetNumRows") (sigFn (list "ParquetHandle") "Int64"))
        ((= name "parquetColumnType") (sigFn (list "ParquetHandle" "String") "String"))
        ((= name "parquetKvMetadata") (sigFn (list "ParquetHandle" "String") "(Result String String)"))
        ((= name "parquetReadF64") (sigFn (list "ParquetHandle" "String" "Int64") "F64Array"))
        ((= name "parquetReadI64") (sigFn (list "ParquetHandle" "String" "Int64") "I64Array"))
        ((= name "parquetReadI8") (sigFn (list "ParquetHandle" "String" "Int64") "I8Array"))
        ((= name "preludeIoError") (sigFn (list "String") "IoError"))
        ((= name "preludeFnvStep") (sigFn (list "Bytes" "Int64" "Int64" "Int64") "Int64"))
        ((= name "zstdAslPack64") (sigFn (list "Int64" "Int64") "Int64"))
        ((= name "zstdAslAdd64") (sigFn (list "Int64" "Int64") "Int64"))
        ((= name "zstdAslMul64") (sigFn (list "Int64" "Int64") "Int64"))
        ((= name "zstdAslPow64") (sigFn (list "Int64") "Int64"))
        ((= name "zstdAslXxhHash") (sigFn (list "Bytes") "Int64"))
        ((= name "zstdAslDecompress") (sigFn (list "Bytes") "(Result Bytes String)"))
        ((= name "preludeTree") (sigFn (list "(Map K V)") "(PreludeTree K V)"))
        ((= name "preludeLeaf") (sigFn (list) "(PreludeTree K V)"))
        ((= name "preludeNode") (sigFn (list "K" "V" "Int64" "(PreludeTree K V)" "(PreludeTree K V)") "(PreludeTree K V)"))
        ((= name "hashMapEmpty") (sigFn (list) "(HashMap K V)"))
        ((= name "hashMapWithCapacity") (sigFn (list "Int64") "(HashMap K V)"))
        ((= name "hashMapSet") (sigFn (list "(HashMap K V)" "K" "V") "(HashMap K V)"))
        ((= name "hashMapGet") (sigFn (list "(HashMap K V)" "K") "(Option V)"))
        ((= name "hashMapGetOr") (sigFn (list "(HashMap K V)" "K" "V") "V"))
        ((= name "hashMapHas?") (sigFn (list "(HashMap K V)" "K") "Bool"))
        ((= name "hashMapRemove") (sigFn (list "(HashMap K V)" "K") "(HashMap K V)"))
        ((= name "hashMapLength") (sigFn (list "(HashMap K V)") "Int64"))
        ((= name "hashMapFold") (sigFn (list "(HashMap K V)" "B" "(fn [B K V] -> B)") "B"))
        ((= name "hashMapPairs") (sigFn (list "(HashMap K V)") "(List (Pair K V))"))
        ((= name "hashMapFromPairs") (sigFn (list "(List (Pair K V))") "(HashMap K V)"))
        (else (none)))

fn builtinSigFallback name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond ((or (= name "sqrt") (or (= name "floor") (or (= name "ceil") (= name "round")))) (sigFn (list "Float64") "Float64")) ((or (= name "exp") (or (= name "log") (or (= name "log2") (or (= name "log10") (or (= name "sin") (or (= name "cos") (= name "tan"))))))) (sigFn (list "Float64") "Float64")) ((or (= name "pow") (= name "atan2")) (sigFn (list "Float64" "Float64") "Float64")) ((= name "clamp") (sigFn (list "Float64" "Float64" "Float64") "Float64")) ((or (= name "!=") (or (= name "=") (or (= name "==") (or (= name "<") (or (= name "<=") (or (= name ">") (= name ">="))))))) (cmpBinopSig)) ((or (= name "*") (or (= name "+") (or (= name "-") (= name "/")))) (numBinopSig)) ((or (= name "<<") (or (= name ">>") (or (= name "&") (or (= name "|") (= name "^"))))) (shiftBinopSig)) ((= name "~") (bitNotSig)) ((or (= name "abs") (= name "neg")) (sigFn (list "N") "N")) ((or (= name "alreadyExists") (or (= name "interrupted") (or (= name "invalidPath") (or (= name "notFound") (or (= name "other") (= name "permissionDenied")))))) (ioerrorCtorSig)) ((= name "and") (sigVar (list "Bool") "Bool")) ((= name "bytesAlloc") (sigFn (list "Int64") "Bytes")) ((= name "bytesLength") (sigFn (list "Bytes") "Int64")) ((= name "bytesGet") (sigFn (list "Bytes" "Int64") "Int64")) ((= name "bytesGetFloat64") (sigFn (list "Bytes" "Int64") "Float64")) ((= name "bytesSet") (sigFn (list "Bytes" "Int64" "Int64") "Unit")) ((= name "bytesSetFloat64") (sigFn (list "Bytes" "Int64" "Float64") "Unit")) ((= name "bytesSha256") (sigFn (list "Bytes") "String")) ((= name "bytesToBase64") (sigFn (list "Bytes") "String")) ((= name "bytesFromBase64") (sigFn (list "String") "(Result Bytes String)")) ((or (= name "checkedDiv") (= name "checkedMod")) (sigFn (list "N" "N") "(Option N)")) ((or (= name "eprintln") (or (= name "print") (= name "println"))) (sigVar (list "A") "Unit")) ((= name "dirList") (sigFn (list "String") "(Result (List String) String)")) ((= name "err") (sigFn (list "E") "(Result T E)")) ((= name "processRun") (sigFn (list "String") "ProcessOutput")) ((= name "nowNs") (sigFn (list) "Int64")) ((= name "monotonicNs") (sigFn (list) "Int64")) ((= name "sleepMs") (sigFn (list "Int64") "Unit")) ((= name "envGet") (sigFn (list "String") "(Option String)")) ((= name "processSpawn") (sigFn (list "String") "(Result Int64 String)")) ((= name "processWait") (sigFn (list "Int64" "Int64") "(Result ProcessOutput String)")) ((= name "fileLock") (sigFn (list "String" "Bool") "(Result Int64 String)")) ((= name "fileLockWait") (sigVar (list "String") "(Result Int64 String)")) ((= name "fileCreateExclusive") (sigFn (list "String" "String") "(Result Unit String)")) ((= name "fileLockAt") (sigFn (list "String" "String" "Bool") "(Result Int64 String)")) ((= name "fileReadAt") (sigFn (list "String" "String") "(Result String String)")) ((= name "fileWriteAt") (sigFn (list "String" "String" "String") "(Result Unit String)")) ((= name "dirCreate") (sigFn (list "String") "(Result Unit String)")) ((= name "pathRemove") (sigFn (list "String") "(Result Unit String)")) ((= name "pathRename") (sigFn (list "String" "String") "(Result Unit String)")) ((or (= name "file-append") (or (= name "fileWrite") (= name "fileAppend"))) (sigFn (list "String" "X") "(Result Unit String)")) ((= name "fileExists?") (sigFn (list "String") "Bool")) ((= name "fileReadString") (sigFn (list "String") "(Result String String)")) ((= name "fileReadBytes") (sigFn (list "String") "(Result Bytes String)")) ((= name "stringCountChar") (sigFn (list "String" "String") "Int64")) ((= name "isNan?") (sigFn (list "Float64") "Bool")) ((= name "isFinite?") (sigFn (list "Float64") "Bool")) ((= name "stringRepeat") (sigFn (list "String" "Int64") "String")) ((= name "fileStat") (sigFn (list "String") "(Result FileStat String)")) ((= name "fileReadRange") (sigFn (list "String" "Int64" "Int64") "(Result Bytes String)")) ((= name "fileSize") (sigFn (list "String") "(Result Int64 String)")) ((= name "filter") (sigFn (list "(fn [T] -> Bool)" "(List T)") "(List T)")) ((= name "float64ToInt64") (sigFn (list "Float64") "(Option Int64)")) ((= name "arenaRun") (sigFn (list "(fn [] -> T)") "T")) ((= name "fold") (sigFn (list "(fn [B A] -> B)" "B" "(List A)") "B")) ((= name "int32ToInt64") (sigFn (list "Int32") "Int64")) ((= name "int64ToFloat64") (sigFn (list "Int64") "Float64")) ((= name "int64ToInt32") (sigFn (list "Int64") "(Option Int32)")) ((or (= name "err?") (= name "ok?")) (sigFn (list "(Result T E)") "Bool")) ((or (= name "none?") (= name "some?")) (sigFn (list "(Option T)") "Bool")) ((= name "list") (sigVar (list "T") "(List T)")) ((= name "listAppend") (sigFn (list "(List T)" "(List T)") "(List T)")) ((= name "listDrop") (sigFn (list "(List T)" "Int64") "(List T)")) ((= name "listTake") (sigFn (list "(List T)" "Int64") "(List T)")) ((= name "listFind") (sigFn (list "(fn [T] -> Bool)" "(List T)") "(Option T)")) ((= name "listCount") (sigFn (list "(fn [T] -> Bool)" "(List T)") "Int64")) ((= name "listFlatMap") (sigFn (list "(fn [A] -> (List B))" "(List A)") "(List B)")) ((= name "listAny?") (sigFn (list "(fn [T] -> Bool)" "(List T)") "Bool")) ((= name "listAll?") (sigFn (list "(fn [T] -> Bool)" "(List T)") "Bool")) ((= name "listLast") (sigFn (list "(List T)") "(Option T)")) ((= name "enumerate") (sigFn (list "(List T)") "(List (Pair Int64 T))")) ((= name "cons") (sigFn (list "T" "(List T)") "(List T)")) ((= name "listContains?") (sigFn (list "(List T)" "T") "Bool")) ((= name "listEmpty?") (sigFn (list "(List T)") "Bool")) ((= name "listGet") (sigFn (list "(List T)" "Int64") "(Option T)")) ((or (= name "listHead") (or (= name "listMax") (= name "listMin"))) (listOptSig)) ((= name "listIndexOf") (sigFn (list "(List T)" "T") "(Option Int64)")) ((= name "listLength") (sigFn (list "(List T)") "Int64")) ((or (= name "listReverse") (= name "listSort")) (sigFn (list "(List T)") "(List T)")) ((= name "listSlice") (sigFn (list "(List T)" "Int64" "Int64") "(Option (List T))")) ((= name "listSortBy") (sigFn (list "(fn [T] -> K)" "(List T)") "(List T)")) ((= name "listSum") (sigFn (list "(List Int64)") "Int64")) ((= name "listSumFloat64") (sigFn (list "(List Float64)") "Float64")) ((= name "listTail") (sigFn (list "(List T)") "(Option (List T))")) ((= name "map") (sigFn (list "(fn [A] -> B)" "(List A)") "(List B)")) ((= name "parMap") (sigFn (list "(fn [A] -> B)" "(List A)" "Int64") "(List B)")) ((= name "parFold") (sigFn (list "(fn [B A] -> B)" "(fn [B B] -> B)" "B" "(List A)" "Int64") "B")) ((= name "mapEmpty") (sigFn (list) "(Map K V)")) ((= name "mapFromPairs") (sigFn (list "(List (Pair K V))") "(Map K V)")) ((= name "mapGet") (sigFn (list "(Map K V)" "K") "(Option V)")) ((= name "mapGetOr") (sigFn (list "(Map K V)" "K" "V") "V")) ((= name "mapHas?") (sigFn (list "(Map K V)" "K") "Bool")) ((= name "mapKeys") (sigFn (list "(Map K V)") "(List K)")) ((= name "mapPairs") (sigFn (list "(Map K V)") "(List (Pair K V))")) ((= name "mapRemove") (sigFn (list "(Map K V)" "K") "(Map K V)")) ((= name "mapSet") (sigFn (list "(Map K V)" "K" "V") "(Map K V)")) ((= name "mapSize") (sigFn (list "(Map K V)") "Int64")) ((= name "mapValues") (sigFn (list "(Map K V)") "(List V)")) ((or (= name "max") (or (= name "min") (= name "mod"))) (numBinopSig)) ((= name "none") (sigFn (list) "(Option T)")) ((= name "not") (sigFn (list "Bool") "Bool")) ((= name "ok") (sigFn (list "T") "(Result T E)")) ((= name "optionMap") (sigFn (list "(fn [A] -> B)" "(Option A)") "(Option B)")) ((= name "optionOr") (sigFn (list "(Option T)" "T") "T")) ((= name "optionToResult") (sigFn (list "(Option T)" "E") "(Result T E)")) ((= name "or") (sigVar (list "Bool") "Bool")) ((= name "pair") (sigFn (list "A" "B") "(Pair A B)")) ((= name "pairFirst") (sigFn (list "(Pair A B)") "A")) ((= name "pairSecond") (sigFn (list "(Pair A B)") "B")) ((= name "range") (sigFn (list "Int64" "Int64") "(List Int64)")) ((= name "read-all") (sigFn (list) "(Result String IoError)")) ((= name "read-line") (sigFn (list) "(Result (Option String) IoError)")) ((= name "resultMap") (sigFn (list "(Result A E)" "(fn [A] -> B)") "(Result B E)")) ((= name "resultMapErr") (sigFn (list "(fn [E] -> F)" "(Result T E)") "(Result T F)")) ((= name "resultOr") (sigFn (list "(Result T E)" "T") "T")) ((= name "resultToOption") (sigFn (list "(Result T E)") "(Option T)")) ((= name "some") (sigFn (list "T") "(Option T)")) ((= name "str") (sigVar (list "A") "String")) ((= name "stringChars") (sigFn (list "String") "(List String)")) ((or (= name "stringContains?") (or (= name "stringEndsWith?") (= name "stringStartsWith?"))) (strPredSig)) ((= name "stringEmpty?") (sigFn (list "String") "Bool")) ((= name "stringFromFloat64") (sigFn (list "Float64") "String")) ((= name "stringFromInt64") (sigFn (list "Int64") "String")) ((= name "stringIndexOf") (sigFn (list "String" "String") "(Option Int64)")) ((= name "stringJoin") (sigFn (list "(List String)" "String") "String")) ((= name "stringLength") (sigFn (list "String") "Int64")) ((or (= name "stringLower") (or (= name "stringReverse") (or (= name "stringTrim") (= name "stringUpper")))) (sigFn (list "String") "String")) ((= name "stringReplace") (sigFn (list "String" "String" "String") "String")) ((= name "stringSlice") (sigFn (list "String" "Int64" "Int64") "(Option String)")) ((= name "stringSliceUtf8") (sigFn (list "String" "Int64" "Int64") "(Option String)")) ((= name "stringSplit") (sigFn (list "String" "String") "(List String)")) ((= name "stringToBytes") (sigFn (list "String") "Bytes")) ((= name "stringToFloat64") (sigFn (list "String") "(Option Float64)")) ((= name "stringToInt64") (sigFn (list "String") "(Option Int64)")) ((= name "zip") (sigFn (list "(List A)" "(List B)") "(List (Pair A B))")) ((= name "trap") (sigFn (list "String" "String") "T")) ((= name "foreign") (sigFn (list "String" "String" "String") "T")) ((= name "tcpListen") (sigFn (list "Int64") "(Result Int64 String)")) ((= name "tcpConnect") (sigFn (list "Int64") "(Result Int64 String)")) ((= name "sockAccept") (sigFn (list "Int64") "(Result Int64 String)")) ((= name "sockLocalPort") (sigFn (list "Int64") "(Result Int64 String)")) ((= name "unixListen") (sigFn (list "String") "(Result Int64 String)")) ((= name "unixConnect") (sigFn (list "String") "(Result Int64 String)")) ((= name "unixSocketPair") (sigFn (list) "(Result (Pair Int64 Int64) String)")) ((= name "sockSendFd") (sigFn (list "Int64" "Int64") "(Result Int64 String)")) ((= name "sockRecvFd") (sigFn (list "Int64") "(Result Int64 String)")) ((= name "realPath") (sigFn (list "String") "(Result String String)")) ((= name "fileReadlink") (sigFn (list "String") "(Result String String)")) ((= name "procExePath") (sigFn (list) "(Result String String)")) ((= name "fdRead") (sigFn (list "Int64" "Int64") "(Result String String)")) ((= name "hostSocketOpen") (sigFn (list "String" "Int64" "Bool") "(Result Int64 String)")) ((= name "hostSocketBind") (sigFn (list "Int64" "String" "Int64") "(Result Bool String)")) ((= name "hostSocketListen") (sigFn (list "Int64" "Int64") "(Result Bool String)")) ((= name "hostSocketAccept") (sigFn (list "Int64") "(Result Int64 String)")) ((= name "hostSocketRead") (sigFn (list "Int64" "Int64") "(Result String String)")) ((= name "hostSocketWrite") (sigFn (list "Int64" "String") "(Result Int64 String)")) ((= name "hostSocketClose") (sigFn (list "Int64") "(Result Bool String)")) ((= name "hostSocketPoll") (sigFn (list "Int64" "Int64") "(Result String String)")) ((= name "hostSurfaceInit") (sigFn (list "String" "Int64" "Int64") "(Result Int64 String)")) ((= name "hostSurfacePresent") (sigFn (list "Int64" "String" "Int64") "(Result Bool String)")) ((= name "hostSurfaceResize") (sigFn (list "Int64" "Int64" "Int64") "(Result Bool String)")) ((= name "hostSurfacePollEvents") (sigFn (list "Int64") "(Result String String)")) (else (none)))
fn showTypes ts: (List Type) -> (List String)
  (map (fn [(t Type)] -> String (showType t)) ts)

fn stripFirstChar s: String -> String
  (match (stringSlice s 1 (stringLength s)) ((some sub) sub) ((none) s))

fn showType t: Type -> String
  (match t ((tyVar id kind) (cond ((= kind "num") "a number") ((= kind "int") "an integer") ((= kind "text") "String or Bytes") (else "_"))) ((tyFun params ret) (str "(fn [" (stringJoin (showTypes params) " ") "] -> " (showType ret) ")")) ((tyCon name args mod shown) (let [(head (match shown ((some rest) rest) ((none) (if (stringStartsWith? name "#") (stripFirstChar name) name))))] (if (listEmpty? args) head (str "(" head " " (stringJoin (showTypes args) " ") ")")))))

(schema TypeTokState (:f toks (List String) "Token accumulator, reversed") (:f cur String "Current atom accumulator"))

fn flushCur toks: (List String) cur: String -> (List String)
  (if (stringEmpty? cur) toks (cons cur toks))

fn tokenizeTypeStep st: TypeTokState c: String -> TypeTokState
  (cond ((or (= c "(") (or (= c ")") (or (= c "[") (= c "]")))) (let [(toks1 (flushCur st.toks st.cur))] (TypeTokState :toks (cons c toks1) :cur ""))) ((or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r")))) (TypeTokState :toks (flushCur st.toks st.cur) :cur "")) (else (with st :cur (str st.cur c))))

fn tokenizeTypeStr s: String -> (List String)
  (let [(st (fold tokenizeTypeStep (TypeTokState :toks (list) :cur "") (stringChars s)))] (listReverse (flushCur st.toks st.cur)))

fn getTypevarId name: String typevars: (List String) -> Int64
  (match (listIndexOf typevars name) ((some i) (+ i 1)) ((none) 1))

fn makeQualPair member: String alias: (Option String) head: String -> (Pair String (Pair (Option String) (Option String)))
  (let [(optH (some head))] (pair (resolveTypeAlias member) (pair alias optH)))

fn parseConName head: String -> (Pair String (Pair (Option String) (Option String)))
  (if (not (stringContains? head "/")) (pair (resolveTypeAlias head) (pair (none) (none))) (let [(parts (stringSplit head "/")) (alias (listGet parts 0))] (match (listGet parts 1) ((some s) (makeQualPair s alias head)) ((none) (makeQualPair head alias head)))))

fn safeToksTail toks: (List String) -> (List String)
  (if (listEmpty? toks) (list) (match (listSlice toks 1 (listLength toks)) ((some rest) rest) ((none) (list))))

fn skipDelim toks: (List String) delim: String -> (List String)
  (match (listHead toks) ((some str) (if (= str delim) (safeToksTail toks) toks)) ((none) toks))

fn parseTypeToks toks: (List String) typevars: (List String) -> (Pair Type (List String))
  (match (listHead toks) ((none) (pair (tyCon "Unit" (list) (none) (none)) (list))) ((some s) (let [(rest (safeToksTail toks))] (if (= s "(") (match (listHead rest) ((none) (pair (tyCon "Unit" (list) (none) (none)) (list))) ((some sSym) (let [(rest2 (safeToksTail rest))] (if (= sSym ")") (pair (tyCon "Unit" (list) (none) (none)) rest2) (if (or (= sSym "fn") (= sSym "Fn")) (fnTypeAfter rest2 typevars) (let [(argsRes (parseTypeArgs rest2 typevars (list))) (args (pairFirst argsRes)) (afterArgs (pairSecond argsRes)) (conInfo (parseConName sSym)) (cName (pairFirst conInfo)) (cMod (pairFirst (pairSecond conInfo))) (cShown (pairSecond (pairSecond conInfo)))] (pair (tyCon cName args cMod cShown) afterArgs))))))) (if (listContains? typevars s) (let [(varId (getTypevarId s typevars)) (kind (if (= s "N") "num" (if (or (= s "A") (or (= s "B") (or (= s "T") (= s "E")))) "any" "any")))] (pair (tyVar varId kind) rest)) (let [(conInfo (parseConName s)) (cName (pairFirst conInfo)) (cMod (pairFirst (pairSecond conInfo))) (cShown (pairSecond (pairSecond conInfo)))] (pair (tyCon cName (list) cMod cShown) rest)))))))

fn parseDelimitedTypes toks: (List String) typevars: (List String) closing: String acc: (List Type) -> (Pair (List Type) (List String))
  (match (listHead toks) ((none) (pair (listReverse acc) (list))) ((some str) (if (= str closing) (let [(revAcc (listReverse acc)) (remToks (safeToksTail toks))] (pair revAcc remToks)) (let [(res (parseTypeToks toks typevars))] (parseDelimitedTypes (pairSecond res) typevars closing (cons (pairFirst res) acc))))))

fn parseTypeArgs toks: (List String) typevars: (List String) acc: (List Type) -> (Pair (List Type) (List String))
  (parseDelimitedTypes toks typevars ")" acc)

fn parseFnParams toks: (List String) typevars: (List String) acc: (List Type) -> (Pair (List Type) (List String))
  (parseDelimitedTypes toks typevars "]" acc)

; (:m :ref FN-BARE-PARAMS :do "a fn type is spelled three ways: (fn [A B] -> R) with bracketed params, (Fn A B -> R) bare up to the arrow, and (Fn A B R) where the last type is the return, the type-constructor spelling ten files still use; reading Fn like fn must keep all three")
fn bareFnToks toks: (List String) depth: Int64 acc: (List String) -> (Pair (List String) (List String))
  (match (listHead toks)
    ((none) (pair (listReverse acc) (list)))
    ((some t) (let [(tl (safeToksTail toks))]
                (cond ((and (= t ")") (= depth 0)) (pair (listReverse acc) tl))
                      ((or (= t "(") (= t "[")) (bareFnToks tl (+ depth 1) (cons t acc)))
                      ((or (= t ")") (= t "]")) (bareFnToks tl (- depth 1) (cons t acc)))
                      (else (bareFnToks tl depth (cons t acc)))))))

fn splitArrow toks: (List String) depth: Int64 acc: (List String) -> (Option (Pair (List String) (List String)))
  (match (listHead toks)
    ((none) (none))
    ((some t) (let [(tl (safeToksTail toks))]
                (cond ((and (= t "->") (= depth 0)) (some (pair (listReverse acc) tl)))
                      ((or (= t "(") (= t "[")) (splitArrow tl (+ depth 1) (cons t acc)))
                      ((or (= t ")") (= t "]")) (splitArrow tl (- depth 1) (cons t acc)))
                      (else (splitArrow tl depth (cons t acc)))))))

fn typesOf toks: (List String) typevars: (List String) -> (List Type)
  (pairFirst (parseDelimitedTypes (listAppend toks (list ")")) typevars ")" (list)))

fn fnTypeAfter toks: (List String) typevars: (List String) -> (Pair Type (List String))
  (let [(t (skipDelim toks "!"))
        (unit (tyCon "Unit" (list) (none) (none)))]
    (if (= (optionOr (listHead t) "") "[")
      (let [(pRes (parseFnParams (safeToksTail t) typevars (list)))
            (retRes (parseTypeToks (skipDelim (pairSecond pRes) "->") typevars))]
        (pair (tyFun (pairFirst pRes) (pairFirst retRes)) (skipDelim (pairSecond retRes) ")")))
      (let [(split (bareFnToks t 0 (list)))
            (inner (pairFirst split))
            (rest (pairSecond split))]
        (match (splitArrow inner 0 (list))
          ((some ba) (pair (tyFun (typesOf (pairFirst ba) typevars) (pairFirst (parseTypeToks (pairSecond ba) typevars))) rest))
          ((none) (let [(all (typesOf inner typevars))
                        (n (listLength all))]
                    (if (= n 0) (pair (tyFun (list) unit) rest)
                      (pair (tyFun (listTake all (- n 1)) (optionOr (listGet all (- n 1)) unit)) rest))))))))

fn parseTypeStr s: String typevars: (List String) -> Type
  (let [(toks (tokenizeTypeStr s))] (pairFirst (parseTypeToks toks typevars)))

fn collectTvars params: (List String) ret: String -> (List String)
  (let [(allStrs (listAppend params (list ret)))]
    (fold (fn [(acc (List String)) (s String)] -> (List String)
            (fold (fn [(aacc (List String)) (w String)] -> (List String)
                    (if (and (= (stringLength w) 1) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" w))
                      (if (listContains? aacc w) aacc (listAppend aacc (list w)))
                      aacc))
                  acc
                  (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace s "(" " ") ")" " ") "[" " ") "]" " ") " ")))
          (list)
          allStrs))

fn genericRows -> (List (Pair String String))
  (list (pair "length/String" "stringLength") (pair "length/List" "listLength") (pair "length/Bytes" "bytesLength") (pair "length/Map" "mapSize") (pair "length/I64Array" "i64ArrayLen") (pair "length/I8Array" "i8ArrayLen") (pair "length/F64Array" "f64ArrayLen")
        (pair "empty?/String" "stringEmpty?") (pair "empty?/List" "listEmpty?")
        (pair "get/List" "listGet") (pair "get/Bytes" "bytesGet") (pair "get/Map" "mapGet") (pair "get/I64Array" "i64ArrayGet") (pair "get/I8Array" "i8ArrayGet") (pair "get/F64Array" "f64ArrayGet")
        (pair "set/Bytes" "bytesSet") (pair "set/Map" "mapSet")
        (pair "slice/String" "stringSlice") (pair "slice/List" "listSlice") (pair "slice/I64Array" "i64ArraySlice") (pair "slice/I8Array" "i8ArraySlice") (pair "slice/F64Array" "f64ArraySlice")
        (pair "contains?/String" "stringContains?") (pair "contains?/List" "listContains?") (pair "contains?/Map" "mapHas?")
        (pair "indexOf/String" "stringIndexOf") (pair "indexOf/List" "listIndexOf") (pair "reverse/String" "stringReverse") (pair "reverse/List" "listReverse")
        (pair "append/String" "stringConcat") (pair "append/List" "listAppend")
        (pair "sum/List" "listSum") (pair "sum/I64Array" "i64ArraySum") (pair "sum/I8Array" "i8ArraySum") (pair "sum/F64Array" "f64ArraySum")
        (pair "countEq/I64Array" "i64ArrayCountEq") (pair "countEq/I8Array" "i8ArrayCountEq") (pair "countEq/F64Array" "f64ArrayCountEq")
        (pair "length/Buf" "bufLength") (pair "get/Buf" "bufGet") (pair "set/Buf" "bufSet") (pair "slice/Buf" "bufSlice"))

fn genericMulti? name: String -> Bool
  (listContains? (list "length" "empty?" "get" "set" "slice" "contains?" "indexOf" "reverse" "append" "sum" "countEq") name)

fn genericAlias name: String -> String
  (cond
    ((= name "head") "listHead")
    ((= name "tail") "listTail")
    ((= name "last") "listLast")
    ((= name "take") "listTake")
    ((= name "drop") "listDrop")
    ((= name "all?") "listAll?")
    ((= name "any?") "listAny?")
    ((= name "sort") "listSort")
    ((= name "sortBy") "listSortBy")
    ((= name "startsWith?") "stringStartsWith?")
    ((= name "endsWith?") "stringEndsWith?")
    ((= name "split") "stringSplit")
    ((= name "join") "stringJoin")
    ((= name "replace") "stringReplace")
    ((= name "trim") "stringTrim")
    ((= name "chars") "stringChars")
    ((= name "lines") "stringLines")
    ((= name "upper") "stringUpper")
    ((= name "lower") "stringLower")
    ((= name "repeat") "stringRepeat")
    ((= name "countChar") "stringCountChar")
    ((= name "keys") "mapKeys")
    ((= name "values") "mapValues")
    ((= name "pairs") "mapPairs")
    ((= name "remove") "mapRemove")
    ((= name "getFloat64") "bytesGetFloat64")
    ((= name "setFloat64") "bytesSetFloat64")
    ((= name "sha256") "bytesSha256")
    (else ""))

fn genericConcrete name: String over: String -> String
  (let [(key (str name "/" over))]
    (cond
      ((= key "length/String") "stringLength")
      ((= key "length/List") "listLength")
      ((= key "length/Bytes") "bytesLength")
      ((= key "length/Map") "mapSize")
      ((= key "length/I64Array") "i64ArrayLen")
      ((= key "length/I8Array") "i8ArrayLen")
      ((= key "length/F64Array") "f64ArrayLen")
      ((= key "length/Buf") "bufLength")
      ((= key "get/Buf") "bufGet")
      ((= key "set/Buf") "bufSet")
      ((= key "slice/Buf") "bufSlice")
      ((= key "empty?/String") "stringEmpty?")
      ((= key "empty?/List") "listEmpty?")
      ((= key "get/List") "listGet")
      ((= key "get/Bytes") "bytesGet")
      ((= key "get/Map") "mapGet")
      ((= key "get/I64Array") "i64ArrayGet")
      ((= key "get/I8Array") "i8ArrayGet")
      ((= key "get/F64Array") "f64ArrayGet")
      ((= key "set/Bytes") "bytesSet")
      ((= key "set/Map") "mapSet")
      ((= key "slice/String") "stringSlice")
      ((= key "slice/List") "listSlice")
      ((= key "slice/I64Array") "i64ArraySlice")
      ((= key "slice/I8Array") "i8ArraySlice")
      ((= key "slice/F64Array") "f64ArraySlice")
      ((= key "contains?/String") "stringContains?")
      ((= key "contains?/List") "listContains?")
      ((= key "contains?/Map") "mapHas?")
      ((= key "indexOf/String") "stringIndexOf")
      ((= key "indexOf/List") "listIndexOf")
      ((= key "reverse/String") "stringReverse")
      ((= key "reverse/List") "listReverse")
      ((= key "append/String") "stringConcat")
      ((= key "append/List") "listAppend")
      ((= key "sum/List") "listSum")
      ((= key "sum/I64Array") "i64ArraySum")
      ((= key "sum/I8Array") "i8ArraySum")
      ((= key "sum/F64Array") "f64ArraySum")
      ((= key "countEq/I64Array") "i64ArrayCountEq")
      ((= key "countEq/I8Array") "i8ArrayCountEq")
      ((= key "countEq/F64Array") "f64ArrayCountEq")
      (else "")))

fn genericCandidates name: String -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String (optionOr (listGet (stringSplit (pairFirst p) "/") 1) "")) (filter (fn [(p (Pair String String))] -> Bool (stringStartsWith? (pairFirst p) (str name "/"))) (genericRows))) ", ")

fn receiverOver t: Type -> String
  (match t
    ((tyVar _ _) "")
    ((tyCon name _ _ _) (if (listContains? (list "String" "List" "Bytes" "Map" "I64Array" "I8Array" "F64Array" "Buf") name) name "?"))
    (_ "?"))

fn isTyVar? t: Type -> Bool
  (match t ((tyVar _ _) true) (_ false))

fn genericRenamed name: String -> String
  (let [(multi (filter (fn [(p (Pair String String))] -> Bool (= (pairSecond p) name)) (genericRows)))]
    (match (listHead multi)
      ((some p) (optionOr (listHead (stringSplit (pairFirst p) "/")) ""))
      ((none) (optionOr (listHead (map (fn [(n String)] -> String n) (filter (fn [(n String)] -> Bool (= (genericAlias n) name)) (genericAliasNames)))) ""))))

fn genericAliasNames -> (List String)
  (list "head" "tail" "last" "take" "drop" "all?" "any?" "sort" "sortBy" "startsWith?" "endsWith?" "split" "join" "replace" "trim" "chars" "lines" "upper" "lower" "repeat" "countChar" "keys" "values" "pairs" "remove" "getFloat64" "setFloat64" "sha256")

fn stringBuiltinNames -> (List String)
  (list "str" "stringChars" "stringConcat" "stringContains?" "stringCountChar" "stringEmpty?" "stringEndsWith?" "stringFromFloat64" "stringFromInt64" "stringIndexOf" "stringJoin" "stringLength" "stringLines" "stringLower" "stringRepeat" "stringReplace" "stringReverse" "stringSlice" "stringSliceUtf8" "stringSplit" "stringStartsWith?" "stringToBytes" "stringToFloat64" "stringToInt64" "stringTrim" "stringUpper")

fn renamedHint name: String -> String
  (let [(renamed (genericRenamed name))] (if (stringEmpty? renamed) "" (str "; renamed to " renamed " (D159)")))

fn genericName? name: String -> Bool
  (or (genericMulti? name) (not (stringEmpty? (genericAlias name))))

fn genericSigName name: String -> String
  (let [(alias (genericAlias name))] (if (stringEmpty? alias) name alias))
