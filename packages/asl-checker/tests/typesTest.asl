(module asl-checker/typesTest :x [testTypes runTests RunTests] :i [(asl-checker/types :a ty)])

fn checkBounds res: (Option (Pair Int64 Int64)) -> Bool
  (mt res ((none) false) ((some b) (and (= (pairFirst b) -2147483648) (= (pairSecond b) 2147483647))))

fn checkSigPlus res: (Option (Pair (List String) (Pair Bool String))) -> Bool
  (mt res ((none) false) ((some sig) (let [(args (pairFirst sig)) (variadic (pairFirst (pairSecond sig))) (ret (pairSecond (pairSecond sig)))] (and (not variadic) (and (= ret "N") (= (listLength args) 2))))))

fn checkSigStr res: (Option (Pair (List String) (Pair Bool String))) -> Bool
  (mt res ((none) false) ((some sig) (let [(variadic (pairFirst (pairSecond sig)))] variadic)))

fn checkSigShift res: (Option (Pair (List String) (Pair Bool String))) -> Bool
  (mt res ((none) false) ((some sig) (let [(args (pairFirst sig)) (variadic (pairFirst (pairSecond sig))) (ret (pairSecond (pairSecond sig)))] (and (not variadic) (and (= ret "Int64") (= args (list "Int64" "Int64")))))))

fn testTypes -> Bool
  (let [(t1 (ty/parseTypeStr "Int" (list))) (t2 (ty/parseTypeStr "(List Int)" (list))) (t3 (ty/parseTypeStr "(fn [Int64] -> Bool)" (list))) (t4 (ty/parseTypeStr "(Result A String)" (list "A")))] (assert (= (ty/showType t1) "Int64") "t1 alias") (refute (= (ty/showType t1) "String") "t1 is not String") (assert (= (ty/showType t2) "(List Int64)") "t2 list") (assert (= (ty/showType t3) "(fn [Int64] -> Bool)") "t3 fn") (assert (ty/unorderedType? "Float64") "unordered float") (assert (ty/unorderedType? "IoError") "unordered io") (refute (ty/unorderedType? "Int64") "Int64 is not unordered") (refute (ty/unorderedType? "String") "String is not unordered") (assert (checkBounds (ty/intRangeBounds "Int32")) "int32 bounds") (refute (none? (ty/intRangeBounds "Int32")) "Int32 bounds must exist") (refute (some? (ty/intRangeBounds "UnknownInt")) "UnknownInt must not have bounds") (assert (= (ty/preludeUnionCases "some") (some "Option")) "some union") (assert (= (ty/preludeUnionCases "notFound") (some "IoError")) "notFound union") (assert (checkSigPlus (ty/builtinSig "+")) "builtin + sig") (assert (checkSigStr (ty/builtinSig "str")) "builtin str sig") (assert (checkSigShift (ty/builtinSig "<<")) "builtin << sig is (Int64 Int64) -> Int64") (assert (checkSigShift (ty/builtinSig ">>")) "builtin >> sig is (Int64 Int64) -> Int64") (assert (= (ty/showType (ty/tyVar 1 "any")) "_") "show var any") (assert (= (ty/showType (ty/tyVar 1 "num")) "a number") "show var num") (assert (= (ty/showType (ty/tyVar 1 "int")) "an integer") "show var int") true)

fn testCamelCaseBuiltins -> Bool
  (do
    (assert (some? (ty/builtinSig "stringContains?")) "stringContains? sig must exist")
    (assert (some? (ty/builtinSig "stringStartsWith?")) "stringStartsWith? sig must exist")
    (assert (some? (ty/builtinSig "stringEndsWith?")) "stringEndsWith? sig must exist")
    (assert (some? (ty/builtinSig "stringLength")) "stringLength sig must exist")
    (assert (some? (ty/builtinSig "stringJoin")) "stringJoin sig must exist")
    (assert (some? (ty/builtinSig "stringSplit")) "stringSplit sig must exist")
    (assert (some? (ty/builtinSig "fileRead")) "fileRead sig must exist")
    (assert (some? (ty/builtinSig "fileExists?")) "fileExists? sig must exist")
    (assert (some? (ty/builtinSig "fileWrite")) "fileWrite sig must exist")
    (assert (some? (ty/builtinSig "fileAppend")) "fileAppend sig must exist")
    (assert (some? (ty/builtinSig "fileLock")) "fileLock sig must exist")
    (assert (some? (ty/builtinSig "fileLockWait")) "fileLockWait sig must exist")
    (assert (some? (ty/builtinSig "fileLockAt")) "fileLockAt sig must exist")
    (assert (some? (ty/builtinSig "fileReadAt")) "fileReadAt sig must exist")
    (assert (some? (ty/builtinSig "fileWriteAt")) "fileWriteAt sig must exist")
    (assert (some? (ty/builtinSig "tcpListen")) "tcpListen sig must exist")
    (assert (some? (ty/builtinSig "tcpConnect")) "tcpConnect sig must exist")
    (assert (some? (ty/builtinSig "sockAccept")) "sockAccept sig must exist")
    (assert (some? (ty/builtinSig "sockLocalPort")) "sockLocalPort sig must exist")
    (assert (some? (ty/builtinSig "unixListen")) "unixListen sig must exist")
    (assert (some? (ty/builtinSig "unixConnect")) "unixConnect sig must exist")
    (assert (some? (ty/builtinSig "listGet")) "listGet sig must exist")
    (assert (some? (ty/builtinSig "listLength")) "listLength sig must exist")
    (assert (some? (ty/builtinSig "mapGet")) "mapGet sig must exist")
    (refute (none? (ty/builtinSig "stringContains?")) "stringContains? must refute none")
    true)

fn sigText res: (Option (Pair (List String) (Pair Bool String))) -> String
  (mt res ((none) "none") ((some sig) (str (if (pairFirst (pairSecond sig)) "variadic " "") (stringJoin (pairFirst sig) " ") " -> " (pairSecond (pairSecond sig)))))

fn arraySigTable -> (List (Pair String String))
  (list (pair "f64ArrayLen" "F64Array -> Int64") (pair "f64ArrayGet" "F64Array Int64 -> Float64") (pair "f64ArraySlice" "F64Array Int64 Int64 -> F64Array")
        (pair "f64ArrayConcat" "(List F64Array) -> F64Array") (pair "f64ArrayGenerate" "Int64 (fn [Int64] -> Float64) -> F64Array") (pair "f64ArraySum" "F64Array -> Float64")
        (pair "f64ArrayCountEq" "F64Array Float64 -> Int64") (pair "f64ArrayFold" "(fn [B Float64] -> B) B F64Array -> B")
        (pair "f64ArrayScan" "(fn [Float64 Float64] -> Float64) Float64 F64Array -> F64Array")
        (pair "dot" "F64Array F64Array -> Float64") (pair "axpy" "Float64 F64Array F64Array -> F64Array") (pair "gemm" "Int64 Int64 Int64 F64Array F64Array -> F64Array")
        (pair "i64ArrayLen" "I64Array -> Int64") (pair "i64ArrayGet" "I64Array Int64 -> Int64") (pair "i64ArraySlice" "I64Array Int64 Int64 -> I64Array")
        (pair "i64ArrayConcat" "(List I64Array) -> I64Array") (pair "i64ArrayGenerate" "Int64 (fn [Int64] -> Int64) -> I64Array") (pair "i64ArraySum" "I64Array -> Int64")
        (pair "i64ArrayCountEq" "I64Array Int64 -> Int64") (pair "i64ArrayFold" "(fn [Int64 Int64] -> Int64) Int64 I64Array -> Int64")
        (pair "i64ArrayScan" "(fn [Int64 Int64] -> Int64) Int64 I64Array -> I64Array")
        (pair "i8ArrayLen" "I8Array -> Int64") (pair "i8ArrayGet" "I8Array Int64 -> Int64") (pair "i8ArraySlice" "I8Array Int64 Int64 -> I8Array")
        (pair "i8ArrayConcat" "(List I8Array) -> I8Array") (pair "i8ArrayGenerate" "Int64 (fn [Int64] -> Int64) -> I8Array") (pair "i8ArraySum" "I8Array -> Int64")
        (pair "i8ArrayCountEq" "I8Array Int64 -> Int64") (pair "i8ArrayFold" "(fn [Int64 Int64] -> Int64) Int64 I8Array -> Int64")
        (pair "i8ArrayScan" "(fn [Int64 Int64] -> Int64) Int64 I8Array -> I8Array"))

fn testArrayBuiltinSigs -> Bool
  (do
    (assert (= (listLength (arraySigTable)) 30) "the array table covers 27 typed array builtins and 3 kernels")
    (map (fn [(row (Pair String String))] -> Bool
           (let [(got (sigText (ty/builtinSig (pairFirst row))))]
             (do (assert (= got (pairSecond row)) (str (pairFirst row) " signature: expected " (pairSecond row) ", found " got)) true)))
         (arraySigTable))
    (refute (some? (ty/builtinSig "f64ArrayFoldl")) "a misspelled array builtin has no signature")
    true)

fn runTests -> Bool
  (do (assert (testTypes) "test-types must pass") (assert (testCamelCaseBuiltins) "testCamelCaseBuiltins must pass") (assert (testArrayBuiltinSigs) "testArrayBuiltinSigs must pass") true)

fn RunTests -> Bool
  (runTests)
