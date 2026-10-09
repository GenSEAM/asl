(module aslHarness/componentMapper :x [ElementUsage ComponentMap BatchTransformRule BatchTransformResult PolicyViolation PolicyAuditReport ResidueMatch ResidueReport scanComponentUsages batchTransformClasses auditDesignPolicy huntLibraryResidues formatComponentMap] :i [(asl-text/string :a s)])

(schema ElementUsage (:f tagName Str) (:f isNative Bool) (:f filePath Str) (:f line I64) (:f classNames (List Str)))

(schema ComponentMap (:f filePath Str) (:f usages (List ElementUsage)) (:f totalComponents I64) (:f totalNative I64))

(schema BatchTransformRule (:f targetTag Str) (:f oldClass Str) (:f newClass Str) (:f scopePattern Str))

(schema BatchTransformResult (:f occurrencesReplaced I64) (:f modifiedContent Str))

(schema PolicyViolation (:f filePath Str) (:f line I64) (:f forbiddenTag Str) (:f recommendedReplacement Str) (:f ruleName Str))

(schema PolicyAuditReport (:f passed Bool) (:f violations (List PolicyViolation)))

(schema ResidueMatch (:f filePath Str) (:f line I64) (:f libraryName Str) (:f snippet Str))

(schema ResidueReport (:f clean Bool) (:f matches (List ResidueMatch)))

fn isUppercaseChar? c: Str -> Bool
  (and (>= c "A") (<= c "Z"))

fn isNativeTag? tagName: Str -> Bool
  (if (stringEmpty? tagName) true (not (isUppercaseChar? (optionOr (stringSlice tagName 0 1) ""))))

fn extractClassesFromLine line: Str -> (List Str)
  (let [(cIdx (stringIndexOf line "className=\""))] (mt cIdx ((none) (let [(c2Idx (stringIndexOf line "class=\""))] (mt c2Idx ((none) (list)) ((some idx) (let [(rest (optionOr (stringSlice line (+ idx 7) (stringLength line)) "")) (qIdx (stringIndexOf rest "\""))] (mt qIdx ((none) (list)) ((some q) (let [(val (optionOr (stringSlice rest 0 q) "")) (tokens (stringSplit (stringTrim val) " "))] (filter (fn [(t Str)] -> Bool (> (stringLength t) 0)) tokens))))))))) ((some idx) (let [(rest (optionOr (stringSlice line (+ idx 11) (stringLength line)) "")) (qIdx (stringIndexOf rest "\""))] (mt qIdx ((none) (list)) ((some q) (let [(val (optionOr (stringSlice rest 0 q) "")) (tokens (stringSplit (stringTrim val) " "))] (filter (fn [(t Str)] -> Bool (> (stringLength t) 0)) tokens))))))))

fn scanLineForTags line: Str filePath: Str lineNum: I64 -> (List ElementUsage)
  (if (not (stringContains? line "<")) (list) (let [(parts (stringSplit line "<")) (tagParts (optionOr (listTail parts) (list)))] (fold (fn [(acc (List ElementUsage)) (part Str)] -> (List ElementUsage) (let [(trimmed (stringTrim part))] (if (or (stringEmpty? trimmed) (or (stringStartsWith? trimmed "/") (or (stringStartsWith? trimmed "!") (stringStartsWith? trimmed "?")))) acc (let [(spaceIdx (stringIndexOf trimmed " ")) (gtIdx (stringIndexOf trimmed ">")) (slashIdx (stringIndexOf trimmed "/")) (endIdx (minValidIndex spaceIdx gtIdx slashIdx (stringLength trimmed))) (tagName (optionOr (stringSlice trimmed 0 endIdx) ""))] (if (and (> (stringLength tagName) 0) (isValidTagName? tagName)) (let [(native (isNativeTag? tagName)) (classes (extractClassesFromLine line)) (usage (ElementUsage :tagName tagName :isNative native :filePath filePath :line lineNum :classNames classes))] (listAppend acc (list usage))) acc))))) (list) tagParts)))

fn minValidIndex s: (Option I64) g: (Option I64) sl: (Option I64) fallback: I64 -> I64
  (let [(v1 (mt s ((none) fallback) ((some i) (if (> i 0) i fallback)))) (v2 (mt g ((none) v1) ((some i) (if (and (> i 0) (< i v1)) i v1)))) (v3 (mt sl ((none) v2) ((some i) (if (and (> i 0) (< i v2)) i v2))))] v3)

fn isValidTagName? tag: Str -> Bool
  (and (not (stringContains? tag "=")) (and (not (stringContains? tag "\"")) (not (stringContains? tag "{"))))

fn scanComponentUsages sourceCode: Str filePath: Str -> ComponentMap
  (let [(lines (stringSplit sourceCode "\n")) (usages (fold (fn [(acc (List ElementUsage)) (idx I64)] -> (List ElementUsage) (let [(line (optionOr (listGet lines idx) "")) (lineUsages (scanLineForTags line filePath (+ idx 1)))] (listAppend acc lineUsages))) (list) (range 0 (listLength lines)))) (compCount (listLength (filter (fn [(u ElementUsage)] -> Bool (not u.isNative)) usages))) (natCount (listLength (filter (fn [(u ElementUsage)] -> Bool u.isNative) usages)))] (ComponentMap :filePath filePath :usages usages :totalComponents compCount :totalNative natCount))

fn countDelimitedMatches src: Str target: Str -> I64
  (let [(c1 (- (listLength (stringSplit src (str "\"" target "\""))) 1)) (c2 (- (listLength (stringSplit src (str "\"" target " "))) 1)) (c3 (- (listLength (stringSplit src (str " " target "\""))) 1)) (c4 (- (listLength (stringSplit src (str " " target " "))) 1)) (c5 (- (listLength (stringSplit src (str "'" target "'"))) 1)) (c6 (- (listLength (stringSplit src (str "'" target " "))) 1)) (c7 (- (listLength (stringSplit src (str " " target "'"))) 1))] (+ c1 (+ c2 (+ c3 (+ c4 (+ c5 (+ c6 c7)))))))

fn replaceDelimitedClass src: Str target: Str replacement: Str -> Str
  (let [(s1 (stringReplace src (str "\"" target "\"") (str "\"" replacement "\""))) (s2 (stringReplace s1 (str "\"" target " ") (str "\"" replacement " "))) (s3 (stringReplace s2 (str " " target "\"") (str " " replacement "\""))) (s4 (stringReplace s3 (str " " target " ") (str " " replacement " "))) (s5 (stringReplace s4 (str "'" target "'") (str "'" replacement "'"))) (s6 (stringReplace s5 (str "'" target " ") (str "'" replacement " "))) (s7 (stringReplace s6 (str " " target "'") (str " " replacement "'")))] s7)

fn batchTransformClasses sourceCode: Str rule: BatchTransformRule -> BatchTransformResult
  (let [(targetStr rule.oldClass) (replaceStr rule.newClass) (delimitedCount (countDelimitedMatches sourceCode targetStr))] (if (> delimitedCount 0) (let [(modified (replaceDelimitedClass sourceCode targetStr replaceStr))] (BatchTransformResult :occurrencesReplaced delimitedCount :modifiedContent modified)) (BatchTransformResult :occurrencesReplaced 0 :modifiedContent sourceCode)))

fn auditDesignPolicy map: ComponentMap forbiddenNativeTags: (List Str) replacementComponent: Str -> PolicyAuditReport
  (let [(usages map.usages) (violations (fold (fn [(acc (List PolicyViolation)) (u ElementUsage)] -> (List PolicyViolation) (if (and u.isNative (listContains? forbiddenNativeTags u.tagName)) (let [(v (PolicyViolation :filePath u.filePath :line u.line :forbiddenTag u.tagName :recommendedReplacement replacementComponent :ruleName "no-raw-native-inputs"))] (listAppend acc (list v))) acc)) (list) usages))] (PolicyAuditReport :passed (listEmpty? violations) :violations violations))

fn huntLibraryResidues sourceCode: Str filePath: Str decommissionedLib: Str knownSymbols: (List Str) -> ResidueReport
  (let [(lines (stringSplit sourceCode "\n")) (matches (fold (fn [(acc (List ResidueMatch)) (idx I64)] -> (List ResidueMatch) (let [(line (optionOr (listGet lines idx) ""))] (if (or (stringContains? line decommissionedLib) (anySymbolInLine? line knownSymbols)) (let [(m (ResidueMatch :filePath filePath :line (+ idx 1) :libraryName decommissionedLib :snippet (stringTrim line)))] (listAppend acc (list m))) acc))) (list) (range 0 (listLength lines))))] (ResidueReport :clean (listEmpty? matches) :matches matches))

fn anySymbolInLine? line: Str symbols: (List Str) -> Bool
  (fold (fn [(matched Bool) (sym Str)] -> Bool (or matched (stringContains? line sym))) false symbols)

fn formatComponentMap cMap: ComponentMap -> Str
  (let [(comps (filter (fn [u] (not u.isNative)) cMap.usages)) (compNames (stringJoin (map (fn [u] u.tagName) comps) " "))] (str "(:component-map :file \"" cMap.filePath "\" " ":components " (stringFromInt64 cMap.totalComponents) " " ":native " (stringFromInt64 cMap.totalNative) " " ":tags [" compNames "])"))
