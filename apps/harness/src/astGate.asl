(module aslHarness/astGate :x [AstMutationVerdict auditAstMutation formatMutationVerdict] :i [])

(schema AstMutationVerdict (:f allowed Bool) (:f reason Str) (:f violations (List Str)))

fn lineIsComment line: Str -> Bool
  (let [(trimmed (stringTrim line))] (cond ((stringEmpty? trimmed) true) ((stringStartsWith? trimmed ";") true) ((stringStartsWith? trimmed "#") true) ((stringStartsWith? trimmed "//") true) ((stringStartsWith? trimmed "/*") true) ((stringStartsWith? trimmed "*") true) ((stringStartsWith? trimmed "--") true) (else false)))

fn stripComment line: Str -> Str
  (if (lineIsComment line) "" (let [(s1 (mt (stringIndexOf line ";") ((some idx) (optionOr (stringSlice line 0 idx) line)) ((none) line))) (s2 (mt (stringIndexOf s1 "//") ((some idx) (optionOr (stringSlice s1 0 idx) s1)) ((none) s1))) (s3 (mt (stringIndexOf s2 " #") ((some idx) (optionOr (stringSlice s2 0 idx) s2)) ((none) s2)))] (stringTrim s3)))

fn getActiveCode source: Str -> Str
  (let [(lines (stringSplit source "\n")) (activeLines (fold (fn [(acc (List Str)) (ln Str)] -> (List Str) (let [(code (stripComment ln))] (if (stringEmpty? code) acc (listAppend acc (list code))))) (list) lines))] (stringJoin activeLines "\n"))

fn symbolPresentInActive? source: Str sym: Str -> Bool
  (let [(active (getActiveCode source))] (stringContains? active sym))

fn extractFirstWord text: Str -> Str
  (let [(trimmed (stringTrim text)) (chars (stringChars trimmed)) (tokenChars (fold (fn [(acc (pair (List Str) Bool)) (c Str)] -> (Pair (List Str) Bool) (if (pairSecond acc) acc (if (or (= c " ") (or (= c "\t") (or (= c "[") (or (= c "(") (or (= c ":") (or (= c "{") (or (= c ")") (= c "]")))))))) (pair (pairFirst acc) true) (pair (listAppend (pairFirst acc) (list c)) false)))) (pair (list) false) chars))] (stringJoin (pairFirst tokenChars) ""))

fn extractDefName line: Str -> Str
  (let [(trimmed (stringTrim line)) (s (if (stringStartsWith? trimmed "(") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) trimmed) trimmed))] (cond ((stringStartsWith? s "df ") (extractFirstWord (optionOr (stringSlice s 3 (stringLength s)) ""))) ((stringStartsWith? s "dfs ") (extractFirstWord (optionOr (stringSlice s 4 (stringLength s)) ""))) ((stringStartsWith? s "dfe ") (extractFirstWord (optionOr (stringSlice s 4 (stringLength s)) ""))) ((stringStartsWith? s "def ") (extractFirstWord (optionOr (stringSlice s 4 (stringLength s)) ""))) ((stringStartsWith? s "defun ") (extractFirstWord (optionOr (stringSlice s 6 (stringLength s)) ""))) ((stringStartsWith? s "defn ") (extractFirstWord (optionOr (stringSlice s 5 (stringLength s)) ""))) ((stringStartsWith? s "fn ") (extractFirstWord (optionOr (stringSlice s 3 (stringLength s)) ""))) ((stringStartsWith? s "function ") (extractFirstWord (optionOr (stringSlice s 9 (stringLength s)) ""))) ((stringStartsWith? s "class ") (extractFirstWord (optionOr (stringSlice s 6 (stringLength s)) ""))) ((stringStartsWith? s "struct ") (extractFirstWord (optionOr (stringSlice s 7 (stringLength s)) ""))) (else "")))

fn extractSymbolDefinitions source: Str -> (List Str)
  (let [(lines (stringSplit source "\n"))] (fold (fn [(acc (List Str)) (ln Str)] -> (List Str) (let [(code (stripComment ln)) (sym (extractDefName code))] (if (stringEmpty? sym) acc (if (listContains? acc sym) acc (listAppend acc (list sym)))))) (list) lines))

fn auditAstMutation preSource: Str postSource: Str protectedSymbols: (List Str) -> AstMutationVerdict
  (let [(definedPre (extractSymbolDefinitions preSource)) (violations (fold (fn [(acc (List Str)) (sym Str)] -> (List Str) (let [(inPre (or (listContains? definedPre sym) (symbolPresentInActive? preSource sym)))] (if inPre (cond ((symbolPresentInActive? postSource sym) acc) (else (listAppend acc (list sym)))) acc))) (list) protectedSymbols)) (hasViolations (> (listLength violations) 0))] (if hasViolations (AstMutationVerdict :allowed false :reason (str "Protected symbol violations detected: " (stringJoin violations ", ")) :violations violations) (AstMutationVerdict :allowed true :reason "AST mutation verified: all protected symbols preserved" :violations (list))))

fn formatMutationVerdict verdict: AstMutationVerdict -> Str
  (if verdict.allowed "(:ast-mutation-verdict :allowed true :reason \"All protected symbols preserved\" :violations ())" (str "(:ast-mutation-verdict :allowed false :reason \"" verdict.reason "\" :violations (" (stringJoin verdict.violations " ") "))"))
