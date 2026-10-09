(module asl-checker/checkParityTypeSemanticsTest
  :x [runTests]
  :i [(asl-checker/types :a ty) (asl-checker/unify :a u) (asl-checker/check :a c)])

fn sigText res: (Option (Pair (List String) (Pair Bool String))) -> String
  (mt res
    ((none) "none")
    ((some sig)
      (str (if (pairFirst (pairSecond sig)) "variadic " "")
           (stringJoin (pairFirst sig) " ")
           " -> "
           (pairSecond (pairSecond sig)))))

fn testLowercasePairNotAliased -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [(p (pair Int64 String))] -> Int64 1)" (mapEmpty) "m.asl"))]
    (and (= (ty/resolveTypeAlias "pair") "pair")
         (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-10")) ds)))

fn testUnsupportedDoubleEquals -> Bool
  (mt (ty/builtinSig "==") ((some _) false) ((none) true))

fn missingPreludeSigTable -> (List (Pair String String))
  (list (pair "fileReadString" "String -> (Result String IoError)")
        (pair "fileReadBytes" "String -> (Result Bytes IoError)")
        (pair "stringCountChar" "String String -> Int64")
        (pair "isNan?" "Float64 -> Bool")
        (pair "isFinite?" "Float64 -> Bool")
        (pair "stringRepeat" "String Int64 -> String")
        (pair "&" "Int64 Int64 -> Int64")
        (pair "|" "Int64 Int64 -> Int64")
        (pair "^" "Int64 Int64 -> Int64"))

fn testMissingPreludeSignatures -> Bool
  (do
    (assert (= (listLength (missingPreludeSigTable)) 9) "missing prelude signature table covers the nine reported builtins")
    (assert (listAll? (fn [(row (Pair String String))] -> Bool
                        (= (sigText (ty/builtinSig (pairFirst row))) (pairSecond row)))
                      (missingPreludeSigTable))
            "each added prelude builtin signature matches its expected type")
    true)

fn testStructuralEquality -> Bool
  (let [(anyTy (ty/tyCon "Any" (list) (none) (none)))
        (intTy (ty/tyCon "Int64" (list) (none) (none)))
        (optionAny (ty/tyCon "Option" (list) (none) (none)))
        (optionInt (ty/tyCon "Option" (list intTy) (none) (none)))]
    (and (not (u/typeEqual? anyTy intTy))
         (not (u/typeEqual? optionAny optionInt))))

fn ! testGenericBuiltinReferenceFiltered -> Bool
  (let [(temp (processRun "mktemp /tmp/asl-checkparity-builtin-reference-B-XXXXXX"))
        (path (stringTrim temp.stdout))
        (src "(module m :x [f]) (fn f [(xs (List Bool))] -> (List Bool) (map and xs))")
        (written (fileWrite path src))
        (raw (c/checkSource src (mapEmpty) path))
        (checked (c/checkFile! path (list ".")))
        (removed (pathRemove path))]
    (do
      (assert (= temp.exitCode 0) "builtin-reference scratch file is unique")
      (assert (ok? written) "generic builtin-reference fixture is written")
      (assert (ok? removed) "generic builtin-reference fixture is removed")
      (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "builtin-reference") (stringContains? d.message "is a builtin, not a value"))) raw) "fixture emits builtin-reference lint before filtering")
      (mt checked
        ((err e) (do (assert false (str "checkFile! succeeds: " e)) false))
        ((ok ds) (do (assert (listEmpty? ds) (str "generic builtin-reference lint is filtered from check errors; diagnostics=" (stringFromInt64 (listLength ds)))) true)))))

fn ! testUndefinedExportLintFiltered -> Bool
  (let [(temp (processRun "mktemp /tmp/asl-checkparity-export-lint-B-XXXXXX"))
        (path (stringTrim temp.stdout))
        (src "(module m :x [notDefined])")
        (written (fileWrite path src))
        (raw (c/checkSource src (mapEmpty) path))
        (checked (c/checkFile! path (list ".")))
        (removed (pathRemove path))]
    (do
      (assert (= temp.exitCode 0) "undefined-export scratch file is unique")
      (assert (ok? written) "undefined-export fixture is written")
      (assert (ok? removed) "undefined-export fixture is removed")
      (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.message "is exported but not defined in this module")) raw) "fixture emits exported-but-undefined lint before filtering")
      (mt checked
        ((err e) (do (assert false (str "checkFile! succeeds: " e)) false))
        ((ok ds) (do (assert (listEmpty? ds) (str "undefined-export lint is filtered from check errors; diagnostics=" (stringFromInt64 (listLength ds)))) true)))))

fn testNullaryBuiltinTypes -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [(p SpawnedProc) (i PlatformInfo) (r Rusage) (s FileStat)] -> Unit ())" (mapEmpty) "m.asl"))]
    (listEmpty? ds))

fn testBareNoneAtomOption -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [] -> (Option Int64) none)" (mapEmpty) "m.asl"))]
    (listEmpty? ds))

fn testPairPatternConstructor -> Bool
  (let [(ds (c/checkSource "(module m :x [sum]) (fn sum [(p (Pair Int64 Int64))] -> Int64 (mt p ((pair left right) (+ left right))))" (mapEmpty) "m.asl"))]
    (do (assert (listEmpty? ds) (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code ": " d.message)) ds) "; ")) true))

fn hasUntypedParamDiag ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "ERR_UNTYPED_PARAM")) ds)

fn testTypedParameterFormatting -> Bool
  (let [(compact (c/checkSource "(module m :x [f]) (fn f [(x Int64)] -> Int64 x)" (mapEmpty) "compact.asl"))
        (multiline (c/checkSource "(module m :x [f])\n(fn f [(x\n Int64)] -> Int64 x)" (mapEmpty) "multiline.asl"))
        (explicitAny (c/checkSource "(module m :x [f]) (fn f [(x Any)] -> Int64 1)" (mapEmpty) "any.asl"))
        (untyped (c/checkSource "(module m :x [f]) (fn f [x] -> Int64 1)" (mapEmpty) "untyped.asl"))]
    (do
      (assert (not (hasUntypedParamDiag compact)) "compact parameter annotation is not mistaken for missing")
      (assert (not (hasUntypedParamDiag multiline)) "multi-line annotation is not mistaken for missing")
      (assert (not (hasUntypedParamDiag explicitAny)) "explicit Any annotation is not mistaken for missing")
      (assert (hasUntypedParamDiag untyped) "unannotated parameter is diagnosed")
      true))

fn testFlatLetSingleBinding -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [a 1] a))" (mapEmpty) "m.asl"))]
    (listEmpty? ds))

fn testFlatLetStepBinding -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [a 1 b 2] (+ a b)))" (mapEmpty) "m.asl"))]
    (listEmpty? ds))

fn testFlatLetSequentialBinding -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [a 1 b (+ a 1)] b))" (mapEmpty) "m.asl"))]
    (listEmpty? ds))

fn testMalformedFlatLet -> Bool
  (let [(ds (c/checkSource "(module m :x [f]) (fn f [] -> Int64 (let [a] a))" (mapEmpty) "m.asl"))]
    (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "ERR_BAD_LET")) ds))

fn testBodyDiagnosticColumnShift -> Bool
  (let [(ds (c/checkSource "(module m :x [f])\n\nfn f [] -> Int64\n  (undefinedProbe 1)\n" (mapEmpty) "m.asl"))
        (rule2Diags (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-2")) ds))]
    (mt (listHead rule2Diags)
      ((some d) (and (= d.line 4) (= d.col 4)))
      ((none) false)))

fn testEffectDiagnosticColumnShift -> Bool
  (let [(ds (c/checkSource "(module m :x [f])\n\nfn f [] -> Int64\n  (println \"hi\")\n" (mapEmpty) "m.asl"))
        (rule12Diags (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-12")) ds))]
    (mt (listHead rule12Diags)
      ((some d) (and (= d.line 4) (= d.col 4)))
      ((none) false)))

fn builtinValueProgram name: String -> String
  (str "(module m :x [f]) (fn f [] -> Int64 (let [(g " name ")] 0))")

fn assertBuiltinIsTypeableValue name: String -> Bool
  (let [(ds (c/checkSource (builtinValueProgram name) (mapEmpty) "m.asl"))]
    (listEmpty? ds))

fn testCheckerBuiltinsAsValues -> Bool
  (and (assertBuiltinIsTypeableValue "procSelf")
       (and (assertBuiltinIsTypeableValue "envList")
            (and (assertBuiltinIsTypeableValue "fdClose")
                 (and (assertBuiltinIsTypeableValue "procWaitPid")
                      (and (assertBuiltinIsTypeableValue "preludeHead")
                           (assertBuiltinIsTypeableValue "stringLines"))))))

fn ! runTests -> Bool
  (do
    (assert (testLowercasePairNotAliased) "lowercase pair is rejected as an unknown type name, not aliased to Pair")
    (assert (testUnsupportedDoubleEquals) "== is not a language builtin operator")
    (assert (testMissingPreludeSignatures) "missing prelude builtins have signatures")
    (assert (testStructuralEquality) "Any and differently parameterized Option types are not structurally equal")
    (assert (testGenericBuiltinReferenceFiltered) "generic builtin-reference diagnostics are filtered without name-specific messages")
    (assert (testUndefinedExportLintFiltered) "undefined export lint is filtered")
    (assert (testNullaryBuiltinTypes) "nullary builtin types SpawnedProc, PlatformInfo, Rusage, FileStat are recognized")
    (assert (testBareNoneAtomOption) "bare none atom types as Option")
    (assert (testPairPatternConstructor) "Pair's pair constructor pattern binds both components")
    (assert (testTypedParameterFormatting) "typed and untyped parameter annotation distinctions")
    (assert (testFlatLetSingleBinding) "flat let single binding resolves without diagnostics")
    (assert (testFlatLetStepBinding) "flat let multiple bindings resolve step without diagnostics")
    (assert (testFlatLetSequentialBinding) "flat let later initializers can refer to earlier bindings")
    (assert (testMalformedFlatLet) "malformed flat let vectors report ERR_BAD_LET")
    (assert (testBodyDiagnosticColumnShift) "body diagnostic column shifting places rule-2 at start of callee atom")
    (assert (testEffectDiagnosticColumnShift) "body diagnostic column shifting places rule-12 at start of callee atom")
    (assert (testCheckerBuiltinsAsValues) "procSelf, envList, fdClose, procWaitPid, preludeHead, stringLines are typeable bare values")
    true)
