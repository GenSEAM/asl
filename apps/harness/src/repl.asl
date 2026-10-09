(module aslHarness/repl :x [ReplSession EvalOutcome newReplSession evalExpression patchAstNode formatSemanticError] :i [])

(schema ReplSession (:f sessionId Str) (:f bindings (Map Str Str)) (:f history (List Str)))

(schema EvalOutcome (:f success Bool) (:f output Str) (:f latencyMicros I64) (:f errorDetail Str))

fn formatSemanticError formName: Str reason: Str line: I64 -> Str
  (str "[SemanticError] form: (" formName ") at line " (stringFromInt64 line) ": " reason)

fn newReplSession sessionId: Str -> ReplSession
  (ReplSession :sessionId sessionId :bindings (mapEmpty) :history (list))

fn patchAstNode source: Str targetSymbol: Str replacement: Str -> Str
  (if (or (stringEmpty? targetSymbol) (not (stringContains? source targetSymbol))) source (stringReplace source targetSymbol replacement))

fn checkDelimiters s: Str -> Bool
  (let [(chars (stringChars s)) (openP (fold (fn [(acc I64) (c Str)] -> I64 (if (= c "(") (+ acc 1) acc)) 0 chars)) (closeP (fold (fn [(acc I64) (c Str)] -> I64 (if (= c ")") (+ acc 1) acc)) 0 chars)) (openB (fold (fn [(acc I64) (c Str)] -> I64 (if (= c "[") (+ acc 1) acc)) 0 chars)) (closeB (fold (fn [(acc I64) (c Str)] -> I64 (if (= c "]") (+ acc 1) acc)) 0 chars)) (openC (fold (fn [(acc I64) (c Str)] -> I64 (if (= c "{") (+ acc 1) acc)) 0 chars)) (closeC (fold (fn [(acc I64) (c Str)] -> I64 (if (= c "}") (+ acc 1) acc)) 0 chars))] (and (= openP closeP) (and (= openB closeB) (= openC closeC))))


fn listFilterEmpty lst: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (let [(trimmed (stringTrim item))] (if (stringEmpty? trimmed) acc (listAppend acc (list trimmed))))) (list) lst)

fn resolveValue sess: ReplSession token: Str -> Str
  (let [(bound (mapGet sess.bindings token))] (optionOr bound token))

fn evalBinaryOp sess: ReplSession op: Str aRaw: Str bRaw: Str -> EvalOutcome
  (let [(valA (resolveValue sess aRaw)) (valB (resolveValue sess bRaw)) (numA (stringToInt64 valA)) (numB (stringToInt64 valB))] (mt numA ((none) (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError op (str "Invalid integer operand: " valA) 1))) ((some a) (mt numB ((none) (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError op (str "Invalid integer operand: " valB) 1))) ((some b) (cond ((= op "+") (EvalOutcome :success true :output (stringFromInt64 (+ a b)) :latencyMicros 3 :errorDetail "")) ((= op "-") (EvalOutcome :success true :output (stringFromInt64 (- a b)) :latencyMicros 3 :errorDetail "")) ((= op "*") (EvalOutcome :success true :output (stringFromInt64 (* a b)) :latencyMicros 3 :errorDetail "")) ((= op "/") (if (= b 0) (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError "/" "Division by zero" 1)) (EvalOutcome :success true :output (stringFromInt64 (/ a b)) :latencyMicros 3 :errorDetail ""))) (else (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError op "Unknown arithmetic operator" 1)))))))))

fn evalExpression sess: ReplSession expr: Str -> EvalOutcome
  (let [(trimmed (stringTrim expr))] (cond ((stringEmpty? trimmed) (EvalOutcome :success false :output "" :latencyMicros 1 :errorDetail (formatSemanticError "eval" "Empty expression" 1))) ((not (checkDelimiters trimmed)) (EvalOutcome :success false :output "" :latencyMicros 1 :errorDetail (formatSemanticError "eval" "Unbalanced delimiters in expression" 1))) ((some? (mapGet sess.bindings trimmed)) (EvalOutcome :success true :output (optionOr (mapGet sess.bindings trimmed) "") :latencyMicros 1 :errorDetail "")) ((or (= trimmed "true") (= trimmed "false")) (EvalOutcome :success true :output trimmed :latencyMicros 1 :errorDetail "")) ((some? (stringToInt64 trimmed)) (EvalOutcome :success true :output trimmed :latencyMicros 1 :errorDetail "")) ((and (stringStartsWith? trimmed "\"") (stringEndsWith? trimmed "\"")) (EvalOutcome :success true :output trimmed :latencyMicros 1 :errorDetail "")) ((and (stringStartsWith? trimmed "(") (stringEndsWith? trimmed ")")) (let [(inner (stringSlice trimmed 1 (- (stringLength trimmed) 1))) (innerClean (stringTrim (optionOr inner ""))) (parts (listFilterEmpty (stringSplit innerClean " "))) (op (optionOr (listGet parts 0) "")) (argCount (- (listLength parts) 1))] (cond ((or (= op "+") (or (= op "-") (or (= op "*") (= op "/")))) (if (< argCount 2) (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError op "Insufficient arguments for operator" 1)) (evalBinaryOp sess op (optionOr (listGet parts 1) "") (optionOr (listGet parts 2) "")))) ((= op "=") (if (< argCount 2) (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError op "Insufficient arguments for equality" 1)) (let [(valA (resolveValue sess (optionOr (listGet parts 1) ""))) (valB (resolveValue sess (optionOr (listGet parts 2) "")))] (EvalOutcome :success true :output (if (= valA valB) "true" "false") :latencyMicros 2 :errorDetail "")))) ((= op "str") (if (< argCount 2) (EvalOutcome :success false :output "" :latencyMicros 2 :errorDetail (formatSemanticError op "Insufficient arguments for str" 1)) (let [(valA (stringReplace (resolveValue sess (optionOr (listGet parts 1) "")) "\"" "")) (valB (stringReplace (resolveValue sess (optionOr (listGet parts 2) "")) "\"" ""))] (EvalOutcome :success true :output (str valA valB) :latencyMicros 3 :errorDetail "")))) (else (EvalOutcome :success true :output trimmed :latencyMicros 4 :errorDetail ""))))) (else (EvalOutcome :success false :output "" :latencyMicros 1 :errorDetail (formatSemanticError "eval" (str "Unbound symbol: " trimmed) 1)))))
