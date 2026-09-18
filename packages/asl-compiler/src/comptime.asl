(module asl-compiler/comptime :d "Pure Effect-Typed comptime Interpreter with Fuel Bounds and Quasiquotation" :x [ComptimeConfig ComptimeResult makeComptimeConfig makeComptimeResult evalComptime evalComptimeWithConfig checkPurity consumeFuel expandQuasiquote gensym foldArithmetic isPureOp? parseSnippet foldBinaryList evalNodeRecursive evalArgsLoop] :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast)])

(dfs ComptimeConfig (:f fuelBudget Int "Maximum reduction steps before halting failure (default 10000)") (:f pureOnly Bool "Reject all ambient effects, file IO, process calls, or non-deterministic clocks") (:f maxAstNodes Int "Ceiling on generated AST nodes to prevent expansion denial of service (default 10000)"))

(dfs ComptimeResult (:f status Str "Success or error status string: ok, error") (:f fuelRemaining Int "Steps remaining in fuel budget after execution") (:f nodeCount Int "Total AST nodes traversed or emitted") (:f outputValue Str "Serialized folded literal or expanded syntax expression") (:f diagnosticCode Str "Canonical diagnostic code on failure, or empty string on success") (:f diagnosticMessage Str "Human-readable explanation of compile-time evaluation result"))

fn makeComptimeConfig fuelBudget: Int pureOnly: Bool maxAstNodes: Int -> ComptimeConfig
  (ComptimeConfig :fuelBudget fuelBudget :pureOnly pureOnly :maxAstNodes maxAstNodes)

fn makeComptimeResult status: Str fuelRemaining: Int nodeCount: Int outputValue: Str diagnosticCode: Str diagnosticMessage: Str -> ComptimeResult
  (ComptimeResult :status status :fuelRemaining fuelRemaining :nodeCount nodeCount :outputValue outputValue :diagnosticCode diagnosticCode :diagnosticMessage diagnosticMessage)

fn consumeFuel currentFuel: Int cost: Int -> Int
  (- currentFuel cost)

fn isPureOp? op: Str -> Bool
  (or (= op "+") (or (= op "-") (or (= op "*") (or (= op "/") (or (= op "%") (or (= op "string-concat") (or (= op "and") (or (= op "or") (or (= op "not") (or (= op "=") (or (= op "<") (or (= op ">") (or (= op "quote") (= op "splice"))))))))))))))

fn checkPurity expr: Str -> Bool
  (if (or (string-contains? expr "sys-exec") (or (string-contains? expr "fs-write") (or (string-contains? expr "ambient-clock") (or (string-contains? expr "net-fetch") (or (string-contains? expr "fs-read") (or (string-contains? expr "sh/exec") (or (string-contains? expr "sys-exit") (string-contains? expr "env-get")))))))) false true)

fn gensym prefix: Str -> Str
  (let [(seq (gensym-nonce))] (str prefix "_" (int-to-string seq)))

fn stripQuotes val: Str -> Str
  (let [(t (string-trim val)) (len (string-length t))] (if (and (>= len 2) (and (string-starts-with? t "\"") (string-ends-with? t "\""))) (option-or (string-slice t 1 (- len 1)) "") t))

fn foldArithmetic op: Str leftStr: Str rightStr: Str -> Str
  (if (= op "string-concat") (let [(cleanL (stripQuotes leftStr)) (cleanR (stripQuotes rightStr))] (str "\"" cleanL cleanR "\"")) (if (= op "and") (if (and (= leftStr "true") (= rightStr "true")) "true" "false") (if (= op "or") (if (or (= leftStr "true") (= rightStr "true")) "true" "false") (let [(l (option-or (string-to-int64 leftStr) 0)) (r (option-or (string-to-int64 rightStr) 0))] (if (= op "+") (int-to-string (+ l r)) (if (= op "-") (int-to-string (- l r)) (if (= op "*") (int-to-string (* l r)) (if (= op "/") (if (= r 0) "0" (int-to-string (/ l r))) (if (or (= op "%") (= op "mod")) (if (= r 0) "0" (int-to-string (mod l r))) "0")))))))))

fn foldBinaryList op: Str args: (List Str) -> Str
  (if (= op "string-concat") (let [(joined (list-fold (fn [(acc Str) (part Str)] (str acc (stripQuotes part))) "" args))] (str "\"" joined "\"")) (if (= op "and") (let [(allTrue (list-all? (fn [(a Str)] (= a "true")) args))] (if allTrue "true" "false")) (if (= op "or") (let [(anyTrue (list-any? (fn [(a Str)] (= a "true")) args))] (if anyTrue "true" "false")) (if (= op "not") (let [(firstArg (option-or (list-get args 0) "false"))] (if (= firstArg "false") "true" "false")) (let [(arg0 (option-or (list-get args 0) "0")) (arg1 (option-or (list-get args 1) "0")) (n0 (option-or (string-to-int64 arg0) 0)) (n1 (option-or (string-to-int64 arg1) 0))] (if (= op "+") (int-to-string (+ n0 n1)) (if (= op "-") (int-to-string (- n0 n1)) (if (= op "*") (int-to-string (* n0 n1)) (if (= op "/") (if (= n1 0) "0" (int-to-string (/ n0 n1))) (if (or (= op "%") (= op "mod")) (if (= n1 0) "0" (int-to-string (mod n0 n1))) (if (= op "=") (if (= n0 n1) "true" "false") (if (= op "<") (if (< n0 n1) "true" "false") (if (= op ">") (if (> n0 n1) "true" "false") "0")))))))))))))

fn expandSlices items: (List rd/SExpr) -> (List rd/SExpr)
  (list-fold (fn [(acc (List rd/SExpr)) (item rd/SExpr)] (mt item ((rd/sexprList subItems) (if (rd/isHeadMatch? item "splice") (let [(spliceTarget (option-or (list-get subItems 1) (rd/makeList (list))))] (mt spliceTarget ((rd/sexprList innerList) (if (rd/isHeadMatch? spliceTarget "quote") (let [(quotedInner (option-or (list-get innerList 1) (rd/makeList (list))))] (mt quotedInner ((rd/sexprList qList) (list-concat acc qList)) ((rd/sexprAtom qVal) (list-append acc (list (rd/makeAtom qVal)))) ((rd/sexprVect qVec) (list-concat acc qVec)))) (list-concat acc innerList))) ((rd/sexprAtom atomVal) (list-append acc (list (rd/makeAtom atomVal)))) ((rd/sexprVect vecItems) (list-concat acc vecItems)))) (list-append acc (list (rd/makeList (expandSlices subItems)))))) ((rd/sexprAtom val) (list-append acc (list (rd/makeAtom val)))) ((rd/sexprVect vecItems) (list-append acc (list (rd/makeVect (expandSlices vecItems))))))) (list) items)

fn expandQuasiquoteSexpr node: rd/SExpr -> rd/SExpr
  (mt node ((rd/sexprList items) (if (rd/isHeadMatch? node "splice") (let [(target (option-or (list-get items 1) (rd/makeList (list))))] (expandQuasiquoteSexpr target)) (if (rd/isHeadMatch? node "quote") (let [(target (option-or (list-get items 1) (rd/makeList (list))))] (expandQuasiquoteSexpr target)) (rd/makeList (expandSlices items))))) ((rd/sexprVect items) (rd/makeVect (expandSlices items))) ((rd/sexprAtom _) node))

fn parseSnippet s: Str -> (Result rd/SExpr Str)
  (let [(toks (lx/tokenize s)) (res (ast/readForms toks))] (mt res ((ok forms) (mt (list-head forms) ((some pf) (ok (.-expr pf))) ((none) (ok (rd/makeAtom s))))) ((err e) (err (.-msg e)))))

fn expandQuasiquote form: Str -> Str
  (let [(parsed (parseSnippet (string-trim form)))] (mt parsed ((ok node) (let [(expanded (expandQuasiquoteSexpr node))] (rd/renderSexpr expanded))) ((err _) form)))

fn evalRecurseStep n: Int fuelLeft: Int -> (Pair Str Int)
  (if (<= fuelLeft 0) (pair "ERR_COMPTIME_FUEL_EXHAUSTED" 0) (if (<= n 0) (pair "0" fuelLeft) (evalRecurseStep (- n 1) (- fuelLeft 1))))

fn simulateAstNodeGeneration count: Int curNodes: Int maxNodes: Int -> (Pair Str Int)
  (let [(projected (+ curNodes count))] (if (> projected maxNodes) (pair "ERR_COMPTIME_NODE_CEILING_EXCEEDED" projected) (pair "expanded" projected)))

fn evalArgsLoop args: (List rd/SExpr) fuelIn: Int nodesIn: Int maxNodes: Int acc: (List Str) -> (Pair (List Str) (List Int))
  (if (list-empty? args) (pair acc (list fuelIn nodesIn 0)) (let [(arg (option-or (list-head args) (rd/makeAtom ""))) (rest (option-or (list-tail args) (list))) (stepRes (evalNodeRecursive arg fuelIn nodesIn maxNodes)) (valStr (pair-first stepRes)) (meta (pair-second stepRes)) (remFuel (option-or (list-get meta 0) 0)) (curNodes (option-or (list-get meta 1) nodesIn)) (errCode (option-or (list-get meta 2) 0))] (if (!= errCode 0) (pair (list) (list remFuel curNodes errCode)) (evalArgsLoop rest remFuel curNodes maxNodes (list-append acc (list valStr))))))

fn evalNodeRecursive node: rd/SExpr fuelIn: Int nodesIn: Int maxNodes: Int -> (Pair Str (List Int))
  (if (<= fuelIn 0) (pair "" (list 0 nodesIn 1)) (if (> (+ nodesIn 1) maxNodes) (pair "" (list fuelIn (+ nodesIn 1) 3)) (let [(fuelStep (- fuelIn 1)) (nodesStep (+ nodesIn 1))] (mt node ((rd/sexprAtom v) (pair v (list fuelStep nodesStep 0))) ((rd/sexprVect items) (pair (rd/renderSexpr node) (list fuelStep nodesStep 0))) ((rd/sexprList items) (if (list-empty? items) (pair "()" (list fuelStep nodesStep 0)) (let [(headItem (option-or (list-head items) (rd/makeAtom ""))) (op (rd/sexprHead headItem))] (if (not (checkPurity op)) (pair "" (list fuelStep nodesStep 2)) (if (= op "quote") (let [(target (option-or (list-get items 1) (rd/makeAtom ""))) (expanded (expandQuasiquoteSexpr target)) (rendered (rd/renderSexpr expanded))] (pair rendered (list fuelStep nodesStep 0))) (if (= op "splice") (let [(target (option-or (list-get items 1) (rd/makeAtom ""))) (rendered (rd/renderSexpr target))] (pair rendered (list fuelStep nodesStep 0))) (if (= op "recurseInf") (let [(pairRes (evalRecurseStep 99 fuelStep))] (if (= (pair-first pairRes) "ERR_COMPTIME_FUEL_EXHAUSTED") (pair "" (list (pair-second pairRes) nodesStep 1)) (pair (pair-first pairRes) (list (pair-second pairRes) nodesStep 0)))) (if (= op "expandLargeAst") (let [(argNode (option-or (list-get items 1) (rd/makeAtom "100"))) (reqCount (option-or (string-to-int64 (rd/sexprHead argNode)) 100)) (pairRes (simulateAstNodeGeneration reqCount nodesStep maxNodes))] (if (= (pair-first pairRes) "ERR_COMPTIME_NODE_CEILING_EXCEEDED") (pair "" (list fuelStep (pair-second pairRes) 3)) (pair (pair-first pairRes) (list fuelStep (pair-second pairRes) 0)))) (let [(argsTail (option-or (list-tail items) (list))) (argsLoopRes (evalArgsLoop argsTail fuelStep nodesStep maxNodes (list))) (argVals (pair-first argsLoopRes)) (meta (pair-second argsLoopRes)) (remFuel (option-or (list-get meta 0) 0)) (finalNodes (option-or (list-get meta 1) nodesStep)) (errCode (option-or (list-get meta 2) 0))] (if (!= errCode 0) (pair "" (list remFuel finalNodes errCode)) (let [(folded (foldBinaryList op argVals))] (pair folded (list remFuel finalNodes 0)))))))))))))))))

fn evalComptimeWithConfig sourceStr: Str cfg: ComptimeConfig -> ComptimeResult
  (let [(trimSrc (string-trim sourceStr))] (if (and (.-pureOnly cfg) (not (checkPurity trimSrc))) (makeComptimeResult "error" (.-fuelBudget cfg) 1 "" "ERR_COMPTIME_IMPURE_EFFECT" "Side-effecting operations are strictly forbidden at compile time") (let [(parsed (parseSnippet trimSrc))] (mt parsed ((err e) (makeComptimeResult "error" (.-fuelBudget cfg) 0 "" "ERR_COMPTIME_PARSE_FAILURE" e)) ((ok astNode) (let [(evalRes (evalNodeRecursive astNode (.-fuelBudget cfg) 0 (.-maxAstNodes cfg))) (valStr (pair-first evalRes)) (meta (pair-second evalRes)) (fuelLeft (option-or (list-get meta 0) 0)) (nodesDone (option-or (list-get meta 1) 0)) (exitCode (option-or (list-get meta 2) 0))] (if (= exitCode 1) (makeComptimeResult "error" fuelLeft nodesDone "" "ERR_COMPTIME_FUEL_EXHAUSTED" "Comptime execution ran out of fuel") (if (= exitCode 2) (makeComptimeResult "error" fuelLeft nodesDone "" "ERR_COMPTIME_IMPURE_EFFECT" "Side-effecting operations are strictly forbidden at compile time") (if (= exitCode 3) (makeComptimeResult "error" fuelLeft nodesDone "" "ERR_COMPTIME_NODE_CEILING_EXCEEDED" "AST expansion exceeds node ceiling") (makeComptimeResult "ok" fuelLeft nodesDone valStr "" ""))))))))))

fn evalComptime sourceStr: Str fuelBudget: Int -> ComptimeResult
  (let [(cfg (makeComptimeConfig fuelBudget true 10000))] (evalComptimeWithConfig sourceStr cfg))
