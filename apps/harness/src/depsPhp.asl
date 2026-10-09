(module aslHarness/depsPhp :x [PhpAttribute PhpCompatibilityReport extractComposerVersion extractPhpAttributes auditPhpCompatibility formatPhpCompatibility] :i [(asl-text/string :a s)])

(schema PhpAttribute (:f targetSymbol Str) (:f attributeName Str) (:f arguments Str) (:f line I64))

(schema PhpCompatibilityReport (:f targetVersion Str) (:f violations (List Str)) (:f compatible Bool))

fn extractComposerVersion composerLockContent: Str pkgName: Str -> (Option Str)
  (let [(lines (stringSplit composerLockContent "\n")) (needle (str "\"name\": \"" pkgName "\""))] (fold (fn [(acc (Option Str)) (pair (Tuple2 I64 Str))] -> (Option Str) (mt acc ((some _) acc) ((none) (let [(idx (pairFirst pair)) (line (pairSecond pair))] (if (stringContains? line needle) (findVersionInSlice lines (+ idx 1) (+ idx 10)) (none)))))) (none) (enumerate lines)))

fn findVersionInSlice lines: (List Str) start: I64 end: I64 -> (Option Str)
  (let [(len (listLength lines)) (boundedEnd (if (> end len) len end))] (fold (fn [(acc (Option Str)) (i I64)] -> (Option Str) (mt acc ((some _) acc) ((none) (let [(line (optionOr (listGet lines i) ""))] (if (stringContains? line "\"version\":") (extractJsonStringValue line "\"version\":") (none)))))) (none) (range start boundedEnd)))

fn extractJsonStringValue line: Str key: Str -> (Option Str)
  (let [(kIdx (stringIndexOf line key))] (mt kIdx ((none) (none)) ((some idx) (let [(rest (optionOr (stringSlice line (+ idx (stringLength key)) (stringLength line)) "")) (q1Idx (stringIndexOf rest "\""))] (mt q1Idx ((none) (none)) ((some q1) (let [(rest2 (optionOr (stringSlice rest (+ q1 1) (stringLength rest)) "")) (q2Idx (stringIndexOf rest2 "\""))] (mt q2Idx ((none) (none)) ((some q2) (some (optionOr (stringSlice rest2 0 q2) "")))))))))))

fn extractPhpAttributes code: Str -> (List PhpAttribute)
  (let [(lines (stringSplit code "\n")) (pendingAttr (none)) (attrs (list))] (fold (fn [(acc (List PhpAttribute)) (pair (Tuple2 I64 Str))] -> (List PhpAttribute) (let [(lineNum (+ (pairFirst pair) 1)) (rawLine (pairSecond pair)) (trimmed (stringTrim rawLine))] (if (and (stringStartsWith? trimmed "#[") (stringEndsWith? trimmed "]")) (let [(inner (optionOr (stringSlice trimmed 2 (- (stringLength trimmed) 1)) "")) (parenIdx (stringIndexOf inner "(")) (attrName (mt parenIdx ((none) (stringTrim inner)) ((some p) (stringTrim (optionOr (stringSlice inner 0 p) ""))))) (attrArgs (mt parenIdx ((none) "") ((some p) (optionOr (stringSlice inner (+ p 1) (- (stringLength inner) 1)) ""))))] (listAppend acc (list (PhpAttribute :targetSymbol "" :attributeName attrName :arguments attrArgs :line lineNum)))) acc))) attrs (enumerate lines)))

fn auditPhpCompatibility code: Str targetVersion: Str -> PhpCompatibilityReport
  (let [(lines (stringSplit code "\n")) (isPhp8 (or (stringStartsWith? targetVersion "8.") (stringStartsWith? targetVersion "9."))) (deprecatedFns (list "create_function(" "each(" "ereg(" "eregi(" "split(")) (violations (list))] (if (not isPhp8) (PhpCompatibilityReport :targetVersion targetVersion :violations (list) :compatible true) (let [(found (fold (fn [(acc (List Str)) (pair (Tuple2 I64 Str))] -> (List Str) (let [(lineNum (+ (pairFirst pair) 1)) (line (pairSecond pair))] (fold (fn [(vacc (List Str)) (fnCall Str)] -> (List Str) (if (stringContains? line fnCall) (listAppend vacc (list (str "Deprecated function '" fnCall "' called at line " (str lineNum) " (removed in PHP 8.0+)"))) vacc)) acc deprecatedFns))) violations (enumerate lines)))] (PhpCompatibilityReport :targetVersion targetVersion :violations found :compatible (= (listLength found) 0)))))

fn formatPhpCompatibility report: PhpCompatibilityReport -> Str
  (if report.compatible (str "✓ PHP Compatibility Audit (" report.targetVersion "): Fully Compatible\n") (let [(hdr (str "✗ PHP Compatibility Audit (" report.targetVersion "): " (str (listLength report.violations)) " Violations Found\n"))] (fold (fn [(acc Str) (v Str)] -> Str (str acc "  - " v "\n")) hdr report.violations)))
