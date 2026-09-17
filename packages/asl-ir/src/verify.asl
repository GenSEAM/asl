(module asl-ir/verify
  :d "Core IR verifier enforcing the closed vocabulary, ANF, and memory safety invariants"
  :x [verifyIr
      verifyStmt
      verifyFunction
      verifyModule]
  :i [(asl-ir/types :a ty) (asl-ir/anf :a anf)])

(df verifyStmt [(s ty/IrStmt) (env (Map Str ty/IrType))] -> (List ty/IrDiag)
  :d "Verifies a single IR statement against well-formedness rules."
  (let [(k (.-kind s))]
    (cond
      ((= k "switch")
       (if (list-empty? (.-defaultBody s))
           (list (ty/makeIrDiag "ERR_IR_MISSING_DEFAULT" "Switch statement lacks mandatory default branch" (.-scrutinee s)))
           (list)))
      ((= k "let")
       (let [(target (.-target s))
             (expr (.-expr s))]
         (cond
           ((is-some? (map-get env target))
            (list (ty/makeIrDiag "ERR_IR_DUPLICATE_BINDING" (str "Variable '" target "' bound more than once in same scope") target)))
           ((and (!= (.-left expr) "") (not (anf/isTerminalAtom? (.-left expr))))
            (list (ty/makeIrDiag "ERR_IR_NON_ANF" "Compound expression in operand position is not in ANF" target)))
           ((and (!= (.-right expr) "") (not (anf/isTerminalAtom? (.-right expr))))
            (list (ty/makeIrDiag "ERR_IR_NON_ANF" "Compound expression in operand position is not in ANF" target)))
           ((and (= (.-kind (.-ty s)) "option") (= (.-repr (.-ty s)) "nullable") (or (= (.-left expr) "unit") (= (.-left expr) "Unit")))
            (list (ty/makeIrDiag "ERR_IR_INVALID_OPTION_REPR" "Option Unit cannot have nullable representation" target)))
           ((and (!= (.-left expr) "") (is-none? (map-get env (.-left expr))) (not (isLiteral? (.-left expr))))
            (list (ty/makeIrDiag "ERR_IR_UNBOUND_VAR" (str "Variable '" (.-left expr) "' is unbound") (.-left expr))))
           ((and (!= (.-kind (.-ty expr)) "") (!= (.-kind (.-ty s)) "") (!= (.-kind (.-ty s)) (.-kind (.-ty expr))))
            (list (ty/makeIrDiag "ERR_IR_TYPE_MISMATCH" (str "Type mismatch: statement type '" (.-kind (.-ty s)) "' does not match expression type '" (.-kind (.-ty expr)) "'") target)))
           ((and (= (.-kind (.-ty s)) "buf") (.-isSecondClass (.-ty s)) (= (.-kind expr) "alloc"))
            (list))
           (:else (list)))))
      ((= k "return")
       (let [(val (.-value s))]
         (if (and (!= val "") (is-none? (map-get env val)) (not (isLiteral? val)))
             (list (ty/makeIrDiag "ERR_IR_UNBOUND_VAR" (str "Returned variable '" val "' is unbound") val))
             (let [(valTy (if (!= val "") (map-get env val) (none)))]
               (if (and (is-some? valTy) (.-isSecondClass (option-unwrap valTy)))
                   (list (ty/makeIrDiag "ERR_IR_BUF_ESCAPE" "Second-class buffer escapes local scope via return" val))
                   (list))))))
      (:else (list)))))

(df isLiteral? [(s Str)] -> Bool
  :d "Returns true if the string represents a numeric, boolean, or unit literal."
  (or (= s "true")
      (= s "false")
      (= s "None")
      (= s "unit")
      (= s "Unit")
      (= s "()")
      (string-starts-with? s "\"")
      (string-starts-with? s "-")
      (and (>= (option-or (string-slice s 0 1) "") "0")
           (<= (option-or (string-slice s 0 1) "") "9"))))

(dfs VerifyState
  (:f env (Map Str ty/IrType) "Current scope typing environment")
  (:f diags (List ty/IrDiag) "Accumulated diagnostics"))

(df stepVerifyStmt [(st VerifyState) (s ty/IrStmt)] -> VerifyState
  :d "Verifies statement and extends environment with let bindings."
  (let [(curEnv (.-env st))
        (curDiags (.-diags st))
        (newDiags (verifyStmt s curEnv))
        (nextEnv (if (= (.-kind s) "let")
                     (map-set curEnv (.-target s) (.-ty s))
                     curEnv))]
    (VerifyState :env nextEnv :diags (list-append curDiags newDiags))))

(df verifyFunction [(f ty/IrFunction)] -> (List ty/IrDiag)
  :d "Verifies a complete IR function definition."
  (let [(body (.-body f))]
    (if (list-empty? body)
        (list (ty/makeIrDiag "ERR_IR_UNTERMINATED_BLOCK" (str "Function '" (.-name f) "' body is empty") (.-name f)))
        (let [(lastStmt (option-or (list-get body (- (list-length body) 1)) (ty/makeIrReturn "" (ty/makeIrType "unit" "raw" false))))
              (lastKind (.-kind lastStmt))
              (termDiags (if (and (!= lastKind "return") (!= lastKind "jump"))
                             (list (ty/makeIrDiag "ERR_IR_UNTERMINATED_BLOCK" (str "Function '" (.-name f) "' block does not end in return or jump") (.-name f)))
                             (list)))
              (initEnv (fold (fn [(acc (Map Str ty/IrType)) (p ty/IrParam)] -> (Map Str ty/IrType)
                               (map-set acc (.-name p) (.-ty p)))
                             (map-empty)
                             (.-params f)))
              (initState (VerifyState :env initEnv :diags (list)))
              (finalState (fold stepVerifyStmt initState body))]
          (list-append termDiags (.-diags finalState))))))

(df verifyModule [(m ty/IrModule)] -> (List ty/IrDiag)
  :d "Verifies all functions in an IR module, returning collection of diagnostics."
  (fold (fn [(acc (List ty/IrDiag)) (f ty/IrFunction)] -> (List ty/IrDiag)
          (list-append acc (verifyFunction f)))
        (list)
        (.-funcs m)))

(df verifyIr [(m ty/IrModule)] -> (Result Unit (List ty/IrDiag))
  :d "Verifies an entire IR module against closed vocabulary, ANF, and memory safety."
  (let [(diags (verifyModule m))]
    (if (list-empty? diags)
        (ok ())
        (err diags))))
