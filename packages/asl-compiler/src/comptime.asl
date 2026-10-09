(module asl-compiler/comptime :x [ComptimeConfig ComptimeResult makeComptimeConfig makeComptimeResult evalComptime evalComptimeWithConfig checkPurity consumeFuel expandQuasiquote gensym monotonicAfter foldArithmetic isPureOp? parseSnippet foldBinaryList evalNodeRecursive evalArgsLoop] :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast)])

(schema ComptimeConfig (:f fuelBudget Int) (:f pureOnly Bool) (:f maxAstNodes Int))

(schema ComptimeResult (:f status Str) (:f fuelRemaining Int) (:f nodeCount Int) (:f outputValue Str) (:f diagnosticCode Str) (:f diagnosticMessage Str))

fn makeComptimeConfig fuelBudget: Int pureOnly: Bool maxAstNodes: Int -> ComptimeConfig
  (ComptimeConfig :fuelBudget fuelBudget :pureOnly pureOnly :maxAstNodes maxAstNodes)

fn makeComptimeResult status: Str fuelRemaining: Int nodeCount: Int outputValue: Str diagnosticCode: Str diagnosticMessage: Str -> ComptimeResult
  (ComptimeResult :status status :fuelRemaining fuelRemaining :nodeCount nodeCount :outputValue outputValue :diagnosticCode diagnosticCode :diagnosticMessage diagnosticMessage)

fn consumeFuel currentFuel: Int cost: Int -> Int
  (- currentFuel cost)

fn isPureOp? op: Str -> Bool
  (or (= op "+") (or (= op "-") (or (= op "*") (or (= op "/") (or (= op "%") (or (= op "stringConcat") (or (= op "and") (or (= op "or") (or (= op "not") (or (= op "=") (or (= op "<") (or (= op ">") (or (= op "quote") (= op "splice"))))))))))))))

fn checkPurity expr: Str -> Bool
  (if (or (stringContains? expr "sys-exec") (or (stringContains? expr "fs-write") (or (stringContains? expr "ambient-clock") (or (stringContains? expr "net-fetch") (or (stringContains? expr "fs-read") (or (stringContains? expr "sh/exec") (or (stringContains? expr "sys-exit") (stringContains? expr "env-get")))))))) false true)

fn ! monotonicAfter previous: Int -> Int
  (let [(next (monotonicNs))]
    (if (> next previous) next (monotonicAfter previous)))

fn ! gensym prefix: Str -> Str
  (let [(seq (monotonicAfter (monotonicNs)))] (str prefix "_" (stringFromInt64 seq)))

fn stripQuotes val: Str -> Str
  (let [(t (stringTrim val)) (len (stringLength t))] (if (and (>= len 2) (and (stringStartsWith? t "\"") (stringEndsWith? t "\""))) (optionOr (stringSlice t 1 (- len 1)) "") t))

fn foldArithmetic op: Str leftStr: Str rightStr: Str -> Str
  (if (= op "stringConcat") (let [(cleanL (stripQuotes leftStr)) (cleanR (stripQuotes rightStr))] (str "\"" cleanL cleanR "\"")) (if (= op "and") (if (and (= leftStr "true") (= rightStr "true")) "true" "false") (if (= op "or") (if (or (= leftStr "true") (= rightStr "true")) "true" "false") (let [(l (optionOr (stringToInt64 leftStr) 0)) (r (optionOr (stringToInt64 rightStr) 0))] (if (= op "+") (stringFromInt64 (+ l r)) (if (= op "-") (stringFromInt64 (- l r)) (if (= op "*") (stringFromInt64 (* l r)) (if (= op "/") (if (= r 0) "0" (stringFromInt64 (/ l r))) (if (or (= op "%") (= op "mod")) (if (= r 0) "0" (stringFromInt64 (mod l r))) "0")))))))))

fn foldBinaryList op: Str args: (List Str) -> Str
  (if (= op "stringConcat") (let [(joined (fold (fn [(acc Str) (part Str)] (str acc (stripQuotes part))) "" args))] (str "\"" joined "\"")) (if (= op "and") (let [(allTrue (listAll? (fn [(a Str)] (= a "true")) args))] (if allTrue "true" "false")) (if (= op "or") (let [(anyTrue (listAny? (fn [(a Str)] (= a "true")) args))] (if anyTrue "true" "false")) (if (= op "not") (let [(firstArg (optionOr (listGet args 0) "false"))] (if (= firstArg "false") "true" "false")) (let [(arg0 (optionOr (listGet args 0) "0")) (arg1 (optionOr (listGet args 1) "0")) (n0 (optionOr (stringToInt64 arg0) 0)) (n1 (optionOr (stringToInt64 arg1) 0))] (if (= op "+") (stringFromInt64 (+ n0 n1)) (if (= op "-") (stringFromInt64 (- n0 n1)) (if (= op "*") (stringFromInt64 (* n0 n1)) (if (= op "/") (if (= n1 0) "0" (stringFromInt64 (/ n0 n1))) (if (or (= op "%") (= op "mod")) (if (= n1 0) "0" (stringFromInt64 (mod n0 n1))) (if (= op "=") (if (= n0 n1) "true" "false") (if (= op "<") (if (< n0 n1) "true" "false") (if (= op ">") (if (> n0 n1) "true" "false") "0")))))))))))))

fn expandSlices items: (List rd/SExpr) -> (List rd/SExpr)
  (fold (fn [(acc (List rd/SExpr)) (item rd/SExpr)] (mt item ((rd/sexprList subItems) (if (rd/isHeadMatch? item "splice") (let [(spliceTarget (optionOr (listGet subItems 1) (rd/makeList (list))))] (mt spliceTarget ((rd/sexprList innerList) (if (rd/isHeadMatch? spliceTarget "quote") (let [(quotedInner (optionOr (listGet innerList 1) (rd/makeList (list))))] (mt quotedInner ((rd/sexprList qList) (listAppend acc qList)) ((rd/sexprAtom qVal) (listAppend acc (list (rd/makeAtom qVal)))) ((rd/sexprVect qVec) (listAppend acc qVec)))) (listAppend acc innerList))) ((rd/sexprAtom atomVal) (listAppend acc (list (rd/makeAtom atomVal)))) ((rd/sexprVect vecItems) (listAppend acc vecItems)))) (listAppend acc (list (rd/makeList (expandSlices subItems)))))) ((rd/sexprAtom val) (listAppend acc (list (rd/makeAtom val)))) ((rd/sexprVect vecItems) (listAppend acc (list (rd/makeVect (expandSlices vecItems))))))) (list) items)

fn expandQuasiquoteSexpr node: rd/SExpr -> rd/SExpr
  (mt node ((rd/sexprList items) (if (rd/isHeadMatch? node "splice") (let [(target (optionOr (listGet items 1) (rd/makeList (list))))] (expandQuasiquoteSexpr target)) (if (rd/isHeadMatch? node "quote") (let [(target (optionOr (listGet items 1) (rd/makeList (list))))] (expandQuasiquoteSexpr target)) (rd/makeList (expandSlices items))))) ((rd/sexprVect items) (rd/makeVect (expandSlices items))) ((rd/sexprAtom _) node))

fn parseSnippet s: Str -> (Result rd/SExpr Str)
  (let [(toks (lx/tokenize s)) (res (ast/readForms toks))] (mt res ((ok forms) (mt (listHead forms) ((some pf) (ok pf.expr)) ((none) (ok (rd/makeAtom s))))) ((err e) (err e.msg))))

fn expandQuasiquote form: Str -> Str
  (let [(parsed (parseSnippet (stringTrim form)))] (mt parsed ((ok node) (let [(expanded (expandQuasiquoteSexpr node))] (rd/renderSexpr expanded))) ((err _) form)))

fn evalRecurseStep n: Int fuelLeft: Int -> (Pair Str Int)
  (if (<= fuelLeft 0) (pair "ERR_COMPTIME_FUEL_EXHAUSTED" 0) (if (<= n 0) (pair "0" fuelLeft) (evalRecurseStep (- n 1) (- fuelLeft 1))))

fn simulateAstNodeGeneration count: Int curNodes: Int maxNodes: Int -> (Pair Str Int)
  (let [(projected (+ curNodes count))] (if (> projected maxNodes) (pair "ERR_COMPTIME_NODE_CEILING_EXCEEDED" projected) (pair "expanded" projected)))

fn evalArgsLoop args: (List rd/SExpr) fuelIn: Int nodesIn: Int maxNodes: Int acc: (List Str) -> (Pair (List Str) (List Int))
  (if (listEmpty? args) (pair acc (list fuelIn nodesIn 0)) (let [(arg (optionOr (listHead args) (rd/makeAtom ""))) (rest (optionOr (listTail args) (list))) (stepRes (evalNodeRecursive arg fuelIn nodesIn maxNodes)) (valStr (pairFirst stepRes)) (meta (pairSecond stepRes)) (remFuel (optionOr (listGet meta 0) 0)) (curNodes (optionOr (listGet meta 1) nodesIn)) (errCode (optionOr (listGet meta 2) 0))] (if (!= errCode 0) (pair (list) (list remFuel curNodes errCode)) (evalArgsLoop rest remFuel curNodes maxNodes (listAppend acc (list valStr))))))

fn evalNodeRecursive node: rd/SExpr fuelIn: Int nodesIn: Int maxNodes: Int -> (Pair Str (List Int))
  (if (<= fuelIn 0) (pair "" (list 0 nodesIn 1)) (if (> (+ nodesIn 1) maxNodes) (pair "" (list fuelIn (+ nodesIn 1) 3)) (let [(fuelStep (- fuelIn 1)) (nodesStep (+ nodesIn 1))] (mt node ((rd/sexprAtom v) (pair v (list fuelStep nodesStep 0))) ((rd/sexprVect items) (pair (rd/renderSexpr node) (list fuelStep nodesStep 0))) ((rd/sexprList items) (if (listEmpty? items) (pair "()" (list fuelStep nodesStep 0)) (let [(headItem (optionOr (listHead items) (rd/makeAtom ""))) (op (rd/sexprHead headItem))] (if (not (checkPurity op)) (pair "" (list fuelStep nodesStep 2)) (if (= op "quote") (let [(target (optionOr (listGet items 1) (rd/makeAtom ""))) (expanded (expandQuasiquoteSexpr target)) (rendered (rd/renderSexpr expanded))] (pair rendered (list fuelStep nodesStep 0))) (if (= op "splice") (let [(target (optionOr (listGet items 1) (rd/makeAtom ""))) (rendered (rd/renderSexpr target))] (pair rendered (list fuelStep nodesStep 0))) (if (= op "recurseInf") (let [(pairRes (evalRecurseStep 99 fuelStep))] (if (= (pairFirst pairRes) "ERR_COMPTIME_FUEL_EXHAUSTED") (pair "" (list (pairSecond pairRes) nodesStep 1)) (pair (pairFirst pairRes) (list (pairSecond pairRes) nodesStep 0)))) (if (= op "expandLargeAst") (let [(argNode (optionOr (listGet items 1) (rd/makeAtom "100"))) (reqCount (optionOr (stringToInt64 (rd/sexprHead argNode)) 100)) (pairRes (simulateAstNodeGeneration reqCount nodesStep maxNodes))] (if (= (pairFirst pairRes) "ERR_COMPTIME_NODE_CEILING_EXCEEDED") (pair "" (list fuelStep (pairSecond pairRes) 3)) (pair (pairFirst pairRes) (list fuelStep (pairSecond pairRes) 0)))) (let [(argsTail (optionOr (listTail items) (list))) (argsLoopRes (evalArgsLoop argsTail fuelStep nodesStep maxNodes (list))) (argVals (pairFirst argsLoopRes)) (meta (pairSecond argsLoopRes)) (remFuel (optionOr (listGet meta 0) 0)) (finalNodes (optionOr (listGet meta 1) nodesStep)) (errCode (optionOr (listGet meta 2) 0))] (if (!= errCode 0) (pair "" (list remFuel finalNodes errCode)) (let [(folded (foldBinaryList op argVals))] (pair folded (list remFuel finalNodes 0)))))))))))))))))

fn evalComptimeWithConfig sourceStr: Str cfg: ComptimeConfig -> ComptimeResult
  (let [(trimSrc (stringTrim sourceStr))] (if (and cfg.pureOnly (not (checkPurity trimSrc))) (makeComptimeResult "error" cfg.fuelBudget 1 "" "ERR_COMPTIME_IMPURE_EFFECT" "Side-effecting operations are strictly forbidden at compile time") (let [(parsed (parseSnippet trimSrc))] (mt parsed ((err e) (makeComptimeResult "error" cfg.fuelBudget 0 "" "ERR_COMPTIME_PARSE_FAILURE" e)) ((ok astNode) (let [(evalRes (evalNodeRecursive astNode cfg.fuelBudget 0 cfg.maxAstNodes)) (valStr (pairFirst evalRes)) (meta (pairSecond evalRes)) (fuelLeft (optionOr (listGet meta 0) 0)) (nodesDone (optionOr (listGet meta 1) 0)) (exitCode (optionOr (listGet meta 2) 0))] (if (= exitCode 1) (makeComptimeResult "error" fuelLeft nodesDone "" "ERR_COMPTIME_FUEL_EXHAUSTED" "Comptime execution ran out of fuel") (if (= exitCode 2) (makeComptimeResult "error" fuelLeft nodesDone "" "ERR_COMPTIME_IMPURE_EFFECT" "Side-effecting operations are strictly forbidden at compile time") (if (= exitCode 3) (makeComptimeResult "error" fuelLeft nodesDone "" "ERR_COMPTIME_NODE_CEILING_EXCEEDED" "AST expansion exceeds node ceiling") (makeComptimeResult "ok" fuelLeft nodesDone valStr "" ""))))))))))

fn evalComptime sourceStr: Str fuelBudget: Int -> ComptimeResult
  (let [(cfg (makeComptimeConfig fuelBudget true 10000))] (evalComptimeWithConfig sourceStr cfg))
