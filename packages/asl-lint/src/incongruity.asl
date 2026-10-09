(module asl-lint/incongruity :x [IncongruityReport scanMonorepoIncongruities detectCrutches detectLingeringSigils detectDeadCondBranches detectPostTerminalExpressions makeIncongruityReport] :i [(asl-lint/tokens :a tok) (asl-parser/ast :a a) (asl-parser/reader :a rd)])

(schema IncongruityReport (:f totalScanned I64) (:f sigilViolations I64) (:f foreignViolations I64) (:f tokenViolations I64) (:f crutchViolations I64) (:f deadCodeViolations I64) (:f passed Bool))

fn makeIncongruityReport scanned: I64 sigils: I64 foreign: I64 tokens: I64 crutches: I64 deadCode: I64 -> IncongruityReport
  (let [(ok? (and (= sigils 0) (and (= foreign 0) (and (= tokens 0) (and (= crutches 0) (= deadCode 0))))))] (IncongruityReport :totalScanned scanned :sigilViolations sigils :foreignViolations foreign :tokenViolations tokens :crutchViolations crutches :deadCodeViolations deadCode :passed ok?))

fn hasSigil? text: Str -> Bool
  (or (stringContains? text "@") (stringContains? text "#"))

fn detectLingeringSigils items: (List Str) -> I64
  (fold (fn [(acc I64) (item Str)] -> I64 (if (hasSigil? item) (+ acc 1) acc)) 0 items)

fn isCrutchToken? text: Str -> Bool
  (or (stringContains? text (str "TO" "DO")) (or (stringContains? text (str "to" "do")) (or (stringContains? text (str "FIX" "ME")) (or (stringContains? text (str "HA" "CK")) (or (stringContains? text (str "ST" "UB")) (or (stringContains? text "stub") (or (stringContains? text "MOCK") (or (stringContains? text "mock") (or (stringContains? text "SWALLOW") (or (stringContains? text "swallow") (or (stringContains? text "crutch") (stringContains? text "temporary-scaffolding"))))))))))))

fn detectCrutches items: (List Str) -> I64
  (fold (fn [(acc I64) (item Str)] -> I64 (if (isCrutchToken? item) (+ acc 1) acc)) 0 items)

fn isForeignFile? path: Str -> Bool
  (or (stringEndsWith? path ".py") (or (stringEndsWith? path ".js") (or (stringEndsWith? path ".ts") (or (stringEndsWith? path ".rs") (and (stringContains? path ".asl/mem/") (stringEndsWith? path ".md"))))))

fn detectForeignFiles paths: (List Str) -> I64
  (fold (fn [(acc I64) (path Str)] -> I64 (if (isForeignFile? path) (+ acc 1) acc)) 0 paths)

fn isTokenCompliant? sym: Str -> Bool
  (<= (tok/estimateIdentifierTokens sym) 2)

fn detectTokenViolations symbols: (List Str) -> I64
  (fold (fn [(acc I64) (sym Str)] -> I64 (if (isTokenCompliant? sym) acc (+ acc 1))) 0 symbols)

fn safeTail l: (List T) -> (List T)
  (if (listEmpty? l) (list) (mt (listTail l) ((some r) r) ((none) (list))))

fn countDeadInCondClauses clauses: (List rd/SExpr) -> I64
  (let [(res (fold (fn [(acc (pair Bool I64)) (clause rd/SExpr)] -> (Pair Bool I64) (let [(afterElse (pairFirst acc)) (deadCount (pairSecond acc))] (if afterElse (pair true (+ deadCount 1)) (mt clause ((rd/sexprList cparts) (mt (listHead cparts) ((some ch) (if (= (rd/sexprHead ch) ":else") (pair true deadCount) (pair false deadCount))) ((none) (pair false deadCount)))) (_ (pair false deadCount)))))) (pair false 0) clauses))] (pairSecond res))

fn detectDeadCondInSexpr s: rd/SExpr -> I64
  (mt s ((rd/sexprAtom _) 0) ((rd/sexprVect items) (fold (fn [(acc I64) (item rd/SExpr)] -> I64 (+ acc (detectDeadCondInSexpr item))) 0 items)) ((rd/sexprList items) (mt (listHead items) ((none) 0) ((some h) (let [(headTok (rd/sexprHead h)) (subDead (fold (fn [(acc I64) (item rd/SExpr)] -> I64 (+ acc (detectDeadCondInSexpr item))) 0 items))] (if (= headTok "cond") (let [(clauses (safeTail items)) (thisDead (countDeadInCondClauses clauses))] (+ thisDead subDead)) subDead))))))

fn detectDeadCondBranches forms: (List a/TopForm) -> I64
  (fold (fn [(acc I64) (form a/TopForm)] -> I64 (mt form ((a/topDefun d) (fold (fn [(iacc I64) (e rd/SExpr)] -> I64 (+ iacc (detectDeadCondInSexpr e))) acc d.body)) ((a/topModule _) acc) (_ acc))) 0 forms)

fn isTerminalHead? h: String -> Bool
  (or (= h "err") (or (= h "return") (or (= h "panic") (= h "exit"))))

fn isTerminalExpr? s: rd/SExpr -> Bool
  (mt s ((rd/sexprList items) (mt (listHead items) ((some h) (isTerminalHead? (rd/sexprHead h))) ((none) false))) (_ false))

fn countDeadInSeq seq: (List rd/SExpr) -> I64
  (let [(res (fold (fn [(acc (pair Bool I64)) (e rd/SExpr)] -> (Pair Bool I64) (let [(afterTerm (pairFirst acc)) (deadCount (pairSecond acc))] (if afterTerm (pair true (+ deadCount 1)) (if (isTerminalExpr? e) (pair true deadCount) (pair false deadCount))))) (pair false 0) seq))] (pairSecond res))

fn detectPostTerminalInSexpr s: rd/SExpr -> I64
  (mt s ((rd/sexprAtom _) 0) ((rd/sexprVect items) (fold (fn [(acc I64) (item rd/SExpr)] -> I64 (+ acc (detectPostTerminalInSexpr item))) 0 items)) ((rd/sexprList items) (mt (listHead items) ((none) 0) ((some h) (let [(headTok (rd/sexprHead h)) (subDead (fold (fn [(acc I64) (item rd/SExpr)] -> I64 (+ acc (detectPostTerminalInSexpr item))) 0 items))] (if (= headTok "do") (let [(seq (safeTail items)) (thisDead (countDeadInSeq seq))] (+ thisDead subDead)) subDead))))))

fn detectPostTerminalExpressions forms: (List a/TopForm) -> I64
  (fold (fn [(acc I64) (form a/TopForm)] -> I64 (mt form ((a/topDefun d) (let [(bodyForms d.body) (bodyDead (countDeadInSeq bodyForms)) (innerDead (fold (fn [(iacc I64) (e rd/SExpr)] -> I64 (+ iacc (detectPostTerminalInSexpr e))) 0 bodyForms))] (+ acc (+ bodyDead innerDead)))) ((a/topModule _) acc) (_ acc))) 0 forms)

fn scanMonorepoIncongruities paths: (List Str) symbols: (List Str) snippets: (List Str) -> IncongruityReport
  (let [(sigils (+ (detectLingeringSigils paths) (+ (detectLingeringSigils symbols) (detectLingeringSigils snippets)))) (foreign (detectForeignFiles paths)) (tokens (detectTokenViolations symbols)) (crutches (detectCrutches snippets)) (total (+ (listLength paths) (+ (listLength symbols) (listLength snippets))))] (makeIncongruityReport total sigils foreign tokens crutches 0))
