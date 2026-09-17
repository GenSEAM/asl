(module asl-ir/types
  :d "Type definitions and AST node schemas for AgentScript Core IR"
  :x [IrType
      IrParam
      IrExpr
      IrSwitchCase
      IrStmt
      IrFunction
      IrModule
      IrDiag
      makeIrType
      makeIrParam
      makeIrLet
      makeIrDrop
      makeIrReturn
      makeIrSwitch
      makeIrFunction
      makeIrModule
      makeIrDiag]
  :i [])

(dfs IrType
  (:f kind Str "Type primitive kind: i64, i32, f64, bool, unit, str, buf, option, closure, adt")
  (:f repr Str "Representation strategy: tagged, nullable, raw")
  (:f isSecondClass Bool "True if type is non-escaping second-class stack type like Buf"))

(dfs IrParam
  (:f name Str "Parameter identifier")
  (:f ty IrType "Parameter type"))

(dfs IrSwitchCase
  (:f tag Str "Variant tag identifier")
  (:f bindings (List Str) "Field binding names")
  (:f body (List Any) "Statements for this arm"))

(dfs IrExpr
  (:f kind Str "Expression kind: atom, binop, cmp, call, alloc, load, closure")
  (:f op Str "Operator symbol if applicable")
  (:f left Str "Left operand variable")
  (:f right Str "Right operand variable")
  (:f args (List Str) "Arguments list")
  (:f ty IrType "Expression result type")
  (:f wrap Str "Wrap arithmetic strategy: wrap, trap")
  (:f shiftMask Bool "True if shift count is masked")
  (:f divModFloor Bool "True if division/mod rounds towards negative infinity")
  (:f codeLabel Str "Closure code target"))

(dfs IrStmt
  (:f kind Str "Statement kind: let, drop, store, return, jump, switch, loop")
  (:f target Str "Target variable for let/drop/store")
  (:f field Str "Field identifier for store")
  (:f value Str "Value identifier for store or return")
  (:f ty IrType "Type of statement target")
  (:f expr IrExpr "Bound expression for let")
  (:f label Str "Label for jump or loop")
  (:f args (List Str) "Arguments for jump")
  (:f scrutinee Str "Scrutinee variable for switch")
  (:f cases (List IrSwitchCase) "Arms for switch")
  (:f defaultBody (List Any) "Mandatory default arm for switch")
  (:f loopBody (List Any) "Statements inside loop"))

(dfs IrFunction
  (:f name Str "Function identifier")
  (:f params (List IrParam) "Formal parameters")
  (:f retType IrType "Return type")
  (:f body (List IrStmt) "Linear basic block statements in ANF"))

(dfs IrModule
  (:f name Str "Module identifier")
  (:f profile Str "Target profile: c11, py, wasm, ts")
  (:f funcs (List IrFunction) "Lowered functions"))

(dfs IrDiag
  (:f code Str "Diagnostic error code")
  (:f message Str "Detailed diagnostic description")
  (:f locus Str "Source locus or node symbol"))

(df makeIrType [(kind Str) (repr Str) (isSecondClass Bool)] -> IrType
  :d "Constructs an IrType record."
  (IrType :kind kind :repr repr :isSecondClass isSecondClass))

(df makeIrParam [(name Str) (ty IrType)] -> IrParam
  :d "Constructs an IrParam record."
  (IrParam :name name :ty ty))

(df makeIrLet [(target Str) (ty IrType) (expr IrExpr)] -> IrStmt
  :d "Constructs an IrLet statement."
  (IrStmt :kind "let"
          :target target
          :field ""
          :value ""
          :ty ty
          :expr expr
          :label ""
          :args (list)
          :scrutinee ""
          :cases (list)
          :defaultBody (list)
          :loopBody (list)))

(df makeIrDrop [(target Str) (ty IrType)] -> IrStmt
  :d "Constructs an IrDrop statement."
  (IrStmt :kind "drop"
          :target target
          :field ""
          :value ""
          :ty ty
          :expr (IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty ty :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "")
          :label ""
          :args (list)
          :scrutinee ""
          :cases (list)
          :defaultBody (list)
          :loopBody (list)))

(df makeIrReturn [(value Str) (ty IrType)] -> IrStmt
  :d "Constructs an IrReturn statement."
  (IrStmt :kind "return"
          :target ""
          :field ""
          :value value
          :ty ty
          :expr (IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty ty :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "")
          :label ""
          :args (list)
          :scrutinee ""
          :cases (list)
          :defaultBody (list)
          :loopBody (list)))

(df makeIrSwitch [(scrutinee Str) (cases (List IrSwitchCase)) (defaultBody (List Any))] -> IrStmt
  :d "Constructs an IrSwitch statement."
  (IrStmt :kind "switch"
          :target ""
          :field ""
          :value ""
          :ty (makeIrType "unit" "raw" false)
          :expr (IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty (makeIrType "unit" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "")
          :label ""
          :args (list)
          :scrutinee scrutinee
          :cases cases
          :defaultBody defaultBody
          :loopBody (list)))

(df makeIrFunction [(name Str) (params (List IrParam)) (retType IrType) (body (List IrStmt))] -> IrFunction
  :d "Constructs an IrFunction record."
  (IrFunction :name name :params params :retType retType :body body))

(df makeIrModule [(name Str) (profile Str) (funcs (List IrFunction))] -> IrModule
  :d "Constructs an IrModule record."
  (IrModule :name name :profile profile :funcs funcs))

(df makeIrDiag [(code Str) (message Str) (locus Str)] -> IrDiag
  :d "Constructs an IrDiag record."
  (IrDiag :code code :message message :locus locus))
