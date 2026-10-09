(module asl-parser/balance :x [BalanceResult checkDelimiterBalance checkDelimiterBalanceIn isDelimiterBalanced? isPlainDelimiterBalanced? countUnclosedParens balanceDelimiters checkDyck1Balance isDyck1Balanced?])

(schema BalanceResult (:f balanced Bool) (:f openParens I64) (:f openBrackets I64) (:f openBraces I64))

fn stackCountSymbol stack: (List Str) sym: Str -> I64
  (fold (fn [(acc I64) (item Str)] -> I64 (if (= item sym) (+ acc 1) acc)) 0 stack)

(schema BalanceScanState (:f stack (List Str)) (:f inQuote Bool) (:f escape Bool) (:f inComment Bool) (:f earlyError Bool))

(schema Dyck1ScanState (:f depth I64) (:f inQuote Bool) (:f escape Bool) (:f inComment Bool) (:f earlyError Bool))

fn dyck1ScanStep state: Dyck1ScanState c: Str -> Dyck1ScanState
  (if state.earlyError
    state
    (if state.inComment
      (if (= c "\n")
        (with state :inQuote false :escape false :inComment false :earlyError false)
        state)
      (if state.inQuote
        (if state.escape
          (with state :inQuote true :escape false :inComment false :earlyError false)
          (if (= c "\\")
            (with state :inQuote true :escape true :inComment false :earlyError false)
            (if (= c "\"")
              (with state :inQuote false :escape false :inComment false :earlyError false)
              (with state :inQuote true :escape false :inComment false :earlyError false))))
        (if (= c "\"")
          (with state :inQuote true :escape false :inComment false :earlyError false)
          (if (= c ";")
            (with state :inQuote false :escape false :inComment true :earlyError false)
            (cond
              ((= c "(")
                (Dyck1ScanState :depth (+ state.depth 1) :inQuote false :escape false :inComment false :earlyError false))
              ((= c ")")
                (if (<= state.depth 0)
                  (Dyck1ScanState :depth -1 :inQuote false :escape false :inComment false :earlyError true)
                  (Dyck1ScanState :depth (- state.depth 1) :inQuote false :escape false :inComment false :earlyError false)))
              (else state)))))))

fn checkDyck1Balance code: Str -> BalanceResult
  (let [(initState (Dyck1ScanState :depth 0 :inQuote false :escape false :inComment false :earlyError false))
        (finalState (fold dyck1ScanStep initState (stringChars code)))]
    (if finalState.earlyError
      (BalanceResult :balanced false :openParens -1 :openBrackets 0 :openBraces 0)
      (let [(d finalState.depth)
            (isBal (and (= d 0) (not finalState.inQuote)))]
        (BalanceResult :balanced isBal :openParens d :openBrackets 0 :openBraces 0))))

fn isDyck1Balanced? code: Str -> Bool
  (checkDyck1Balance code).balanced

fn balanceScanStepIn aslComments: Bool state: BalanceScanState c: Str -> BalanceScanState
  (if state.earlyError state (if state.inComment (if (= c "\n") (with state :inQuote false :escape false :inComment false :earlyError false) state) (if state.inQuote (if state.escape (with state :inQuote true :escape false :inComment false :earlyError false) (if (= c "\\") (with state :inQuote true :escape true :inComment false :earlyError false) (if (= c "\"") (with state :inQuote false :escape false :inComment false :earlyError false) (with state :inQuote true :escape false :inComment false :earlyError false)))) (if (= c "\"") (with state :inQuote true :escape false :inComment false :earlyError false) (if (and aslComments (= c ";")) (with state :inQuote false :escape false :inComment true :earlyError false) (cond ((= c "(") (BalanceScanState :stack (cons "(" state.stack) :inQuote false :escape false :inComment false :earlyError false)) ((= c ")") (if (listEmpty? state.stack) (BalanceScanState :stack (list) :inQuote false :escape false :inComment false :earlyError true) (let [(top (optionOr (listHead state.stack) "")) (stkRst (optionOr (listTail state.stack) (list)))] (if (= top "(") (BalanceScanState :stack stkRst :inQuote false :escape false :inComment false :earlyError false) (with state :inQuote false :escape false :inComment false :earlyError true))))) ((= c "[") (BalanceScanState :stack (cons "[" state.stack) :inQuote false :escape false :inComment false :earlyError false)) ((= c "]") (if (listEmpty? state.stack) (BalanceScanState :stack (list) :inQuote false :escape false :inComment false :earlyError true) (let [(top (optionOr (listHead state.stack) "")) (stkRst (optionOr (listTail state.stack) (list)))] (if (= top "[") (BalanceScanState :stack stkRst :inQuote false :escape false :inComment false :earlyError false) (with state :inQuote false :escape false :inComment false :earlyError true))))) ((= c "{") (BalanceScanState :stack (cons "{" state.stack) :inQuote false :escape false :inComment false :earlyError false)) ((= c "}") (if (listEmpty? state.stack) (BalanceScanState :stack (list) :inQuote false :escape false :inComment false :earlyError true) (let [(top (optionOr (listHead state.stack) "")) (stkRst (optionOr (listTail state.stack) (list)))] (if (= top "{") (BalanceScanState :stack stkRst :inQuote false :escape false :inComment false :earlyError false) (with state :inQuote false :escape false :inComment false :earlyError true))))) (else state)))))))

fn balanceScanStep state: BalanceScanState c: Str -> BalanceScanState
  (balanceScanStepIn true state c)

fn checkDelimiterBalance code: Str -> BalanceResult
  (checkDelimiterBalanceIn true code)

fn checkDelimiterBalanceIn aslComments: Bool code: Str -> BalanceResult
  (let [(initState (BalanceScanState :stack (list) :inQuote false :escape false :inComment false :earlyError false)) (finalState (fold (fn [(st BalanceScanState) (c Str)] -> BalanceScanState (balanceScanStepIn aslComments st c)) initState (stringChars code))) (p (stackCountSymbol finalState.stack "(")) (b (stackCountSymbol finalState.stack "[")) (br (stackCountSymbol finalState.stack "{")) (isBal (and (not finalState.earlyError) (and (= p 0) (and (= b 0) (and (= br 0) (and (listEmpty? finalState.stack) (not finalState.inQuote)))))))] (BalanceResult :balanced isBal :openParens (if finalState.earlyError -1 p) :openBrackets (if finalState.earlyError -1 b) :openBraces (if finalState.earlyError -1 br)))

fn isDelimiterBalanced? code: Str -> Bool
  (checkDelimiterBalance code).balanced

fn isPlainDelimiterBalanced? code: Str -> Bool
  (checkDelimiterBalanceIn false code).balanced

fn countUnclosedParens code: Str -> I64
  (let [(dRes (checkDyck1Balance code))]
    (if (and (not dRes.balanced) (> dRes.openParens 0))
      dRes.openParens
      (let [(res (checkDelimiterBalance code))]
        (if (and (not res.balanced) (> res.openParens 0)) res.openParens 0))))

fn balanceDelimiters raw: Str -> Str
  (let [(delta (countUnclosedParens raw))] (if (> delta 0) (let [(closers (fold (fn [(acc Str) (_ I64)] -> Str (str acc ")")) "" (range 0 delta)))] (str raw closers)) raw))
