(module asl-ir/printer
  :d "S-expression and ASN text printer for AgentScript Core IR"
  :x [printIr
      printFunction
      printStmt
      printExpr
      printType]
  :i [(asl-ir/types :a ty)])

(df printType [(t ty/IrType)] -> Str
  :d "Formats an IrType as ASN notation."
  (let [(repr (.-repr t))]
    (if (= repr "raw")
        (str "(ir/type :" (.-kind t) ")")
        (str "(ir/type :" (.-kind t) " :repr :" repr ")"))))

(df printExpr [(e ty/IrExpr)] -> Str
  :d "Formats an IrExpr as an S-expression form."
  (let [(k (.-kind e))]
    (cond
      ((= k "binop")
       (str "(ir/binop :" (.-op e) " " (.-left e) " " (.-right e)
            (if (.-shiftMask e) " :shiftMask true" "")
            (if (.-divModFloor e) " :divModFloor true" "")
            ")"))
      ((= k "cmp")
       (str "(ir/cmp :" (.-op e) " " (.-left e) " " (.-right e) ")"))
      ((= k "call")
       (str "(ir/call " (.-target e) " [" (string-join (.-args e) " ") "])"))
      ((= k "alloc")
       (str "(ir/alloc " (printType (.-ty e)) " [" (string-join (.-args e) " ") "])"))
      ((= k "atom")
       (.-left e))
      (:else
       (str "(ir/" k ")")))))

(df printStmt [(s ty/IrStmt)] -> Str
  :d "Formats an IrStmt as an S-expression form."
  (let [(k (.-kind s))]
    (cond
      ((= k "let")
       (str "  (ir/let " (.-target s) " " (printType (.-ty s)) " " (printExpr (.-expr s)) ")"))
      ((= k "return")
       (if (= (.-value s) "")
           "  (ir/return)"
           (str "  (ir/return " (.-value s) ")")))
      ((= k "drop")
       (str "  (ir/drop " (.-target s) " " (printType (.-ty s)) ")"))
      ((= k "switch")
       (str "  (ir/switch " (.-scrutinee s) " :cases ["
            (string-join (map (fn [(c ty/IrSwitchCase)] -> Str
                                (str "(:case :" (.-tag c) " [" (string-join (.-bindings c) " ") "])"))
                              (.-cases s)) " ")
            "] :default [...])"))
      (:else
       (str "  (ir/" k ")")))))

(df printFunction [(f ty/IrFunction)] -> Str
  :d "Formats an IrFunction as an S-expression block."
  (let [(pStrs (map (fn [(p ty/IrParam)] -> Str (str "(" (.-name p) " " (printType (.-ty p)) ")")) (.-params f)))
        (bStrs (map printStmt (.-body f)))]
    (str "(ir/func " (.-name f) " [" (string-join pStrs " ") "] " (printType (.-retType f)) "\n"
         (string-join bStrs "\n") ")")))

(df printIr [(m ty/IrModule)] -> Str
  :d "Formats an entire IrModule as ASN intermediate representation text."
  (let [(fStrs (map printFunction (.-funcs m)))]
    (str "(:ir-module :name \"" (.-name m) "\" :profile \"" (.-profile m) "\"\n"
         (string-join fStrs "\n\n") "\n)")))
