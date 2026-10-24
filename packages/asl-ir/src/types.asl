(module asl-ir/types :x [IrType IrParam IrExpr IrSwitchCase IrStmt IrFunction IrModule IrDiag makeIrType makeIrParam makeIrLet makeIrDrop makeIrReturn makeIrSwitch makeIrFunction makeIrModule makeIrDiag verifyAnfStmt verifyAnfFunction verifyAnfModule SsaTy SsaConst SsaOp SsaEdge SsaCase SsaTerm SsaParam SsaInstr SsaBlock SsaFunction SsaVariant SsaTypeDecl SsaRecordDecl SsaGlobal SsaExtern SsaModule ssaParam ssaInstr ssaEdge ssaCase ssaBlock ssaFunction ssaVariant ssaTypeDecl ssaRecordDecl ssaRecordDeclTyped ssaRecordRaw? ssaGlobal ssaExtern ssaExternTyped ssaExternVariadic ssaModule ssaTyName ssaAbiName ssaIsRec? ssaIsRaw? termEdges opOperands SsaPrim primSignature SsaBuiltin builtinEntries builtinEntry] :i [])

(schema IrType (:f kind Str) (:f repr Str) (:f isSecondClass Bool))

(schema IrParam (:f name Str) (:f ty IrType))

(schema IrSwitchCase (:f tag Str) (:f bindings (List Str)) (:f body (List Any)))

(schema IrExpr (:f kind Str) (:f op Str) (:f left Str) (:f right Str) (:f args (List Str)) (:f ty IrType) (:f wrap Str) (:f shiftMask Bool) (:f divModFloor Bool) (:f codeLabel Str))

(schema IrStmt (:f kind Str) (:f target Str) (:f field Str) (:f value Str) (:f ty IrType) (:f expr IrExpr) (:f label Str) (:f args (List Str)) (:f scrutinee Str) (:f cases (List IrSwitchCase)) (:f defaultBody (List Any)) (:f loopBody (List Any)))

(schema IrFunction (:f name Str) (:f params (List IrParam)) (:f retType IrType) (:f body (List IrStmt)))

(schema IrModule (:f name Str) (:f profile Str) (:f funcs (List IrFunction)))

(schema IrDiag (:f code Str) (:f message Str) (:f locus Str))

fn makeIrType kind: Str repr: Str isSecondClass: Bool -> IrType
  (IrType :kind kind :repr repr :isSecondClass isSecondClass)

fn makeIrParam name: Str ty: IrType -> IrParam
  (IrParam :name name :ty ty)

fn makeIrLet target: Str ty: IrType expr: IrExpr -> IrStmt
  (IrStmt :kind "let" :target target :field "" :value "" :ty ty :expr expr :label "" :args (list) :scrutinee "" :cases (list) :defaultBody (list) :loopBody (list))

fn makeIrDrop target: Str ty: IrType -> IrStmt
  (IrStmt :kind "drop" :target target :field "" :value "" :ty ty :expr (IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty ty :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "" :args (list) :scrutinee "" :cases (list) :defaultBody (list) :loopBody (list))

fn makeIrReturn value: Str ty: IrType -> IrStmt
  (IrStmt :kind "return" :target "" :field "" :value value :ty ty :expr (IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty ty :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "" :args (list) :scrutinee "" :cases (list) :defaultBody (list) :loopBody (list))

fn makeIrSwitch scrutinee: Str cases: (List IrSwitchCase) defaultBody: (List Any) -> IrStmt
  (IrStmt :kind "switch" :target "" :field "" :value "" :ty (makeIrType "unit" "raw" false) :expr (IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty (makeIrType "unit" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "" :args (list) :scrutinee scrutinee :cases cases :defaultBody defaultBody :loopBody (list))

fn makeIrFunction name: Str params: (List IrParam) retType: IrType body: (List IrStmt) -> IrFunction
  (IrFunction :name name :params params :retType retType :body body)

fn makeIrModule name: Str profile: Str funcs: (List IrFunction) -> IrModule
  (IrModule :name name :profile profile :funcs funcs)

fn makeIrDiag code: Str message: Str locus: Str -> IrDiag
  (IrDiag :code code :message message :locus locus)

fn verifyAnfStmt stmt: IrStmt -> (Option IrDiag)
  (let [(k stmt.kind)]
    (cond
      ((= k "let")
        (if (stringEmpty? stmt.target)
          (some (makeIrDiag "ERR_ANF_EMPTY_TARGET" "Let statement missing bound target variable" k))
          (none)))
      ((= k "return")
        (if (stringEmpty? stmt.value)
          (some (makeIrDiag "ERR_ANF_EMPTY_RETURN" "Return statement missing value operand" k))
          (none)))
      ((= k "drop")
        (if (stringEmpty? stmt.target)
          (some (makeIrDiag "ERR_ANF_EMPTY_DROP" "Drop statement missing target variable" k))
          (none)))
      ((= k "switch")
        (if (stringEmpty? stmt.scrutinee)
          (some (makeIrDiag "ERR_ANF_EMPTY_SCRUTINEE" "Switch statement missing scrutinee" k))
          (none)))
      ((or (= k "store") (= k "jump") (= k "loop"))
        (none))
      (else
        (some (makeIrDiag "ERR_ANF_INVALID_STMT_KIND" (str "Invalid statement kind in ANF: " k) k)))))

fn verifyAnfFunction func: IrFunction -> (Option IrDiag)
  (if (stringEmpty? func.name)
    (some (makeIrDiag "ERR_ANF_ANONYMOUS_FN" "Function missing identifier" "fn"))
    (let [(stmts func.body)]
      (fold (fn [(errOpt (Option IrDiag)) (s IrStmt)] -> (Option IrDiag)
              (match errOpt
                ((some _) errOpt)
                ((none) (verifyAnfStmt s))))
            (none) stmts)))

fn verifyAnfModule moduleObj: IrModule -> (Option IrDiag)
  (if (stringEmpty? moduleObj.name)
    (some (makeIrDiag "ERR_ANF_ANONYMOUS_MODULE" "Module missing identifier" "module"))
    (let [(funcs moduleObj.funcs)]
      (fold (fn [(errOpt (Option IrDiag)) (f IrFunction)] -> (Option IrDiag)
              (match errOpt
                ((some _) errOpt)
                ((none) (verifyAnfFunction f))))
            (none) funcs)))

(enum SsaTy
  (:c tyVal [] "Uniform host Val, passed by value in the host ABI")
  (:c tyRec [(schema String)] "A Val known to be a record of schema")
  (:c tyI64 [] "Raw 64-bit integer")
  (:c tyF64 [] "Raw 64-bit float")
  (:c tyI1 [] "Raw boolean")
  (:c tyPtr [] "Raw native pointer, for a C ABI extern's string and buffer arguments")
  (:c tyI32 [] "Raw 32-bit integer, for a C ABI extern's int-sized arguments and results"))

(enum SsaConst
  (:c constInt [(value Int64)] "Integer literal, as Val or raw i64")
  (:c constFloat [(value Float64)] "Float literal, as Val or raw f64")
  (:c constBool [(value Bool)] "Boolean literal, as Val or raw i1")
  (:c constStr [(index Int64)] "String literal by index into the module string pool, always Val")
  (:c constUnit [] "Unit, always Val")
  (:c constKeyword [(name String)] "Interned keyword written without its colon, always Val")
  (:c constSymbol [(name String)] "Interned symbol, always Val"))

(enum SsaOp
  (:c opConst [(value SsaConst)] "Constant")
  (:c opCall [(callee String) (args (List String))] "Direct call of a module function without captures, typed by its signature, or of an extern, all Val; arity is checked")
  (:c opBuiltin [(name String) (args (List String))] "Call of a host builtin by its hyphenated name")
  (:c opEntry [(name String) (args (List String))] "Direct call of the runtime entry builtinEntry gives for the name and operand count, operands and result typed by it")
  (:c opCallClosure [(closure String) (args (List String))] "Indirect call of a closure value")
  (:c opMakeClosure [(callee String) (captures (List String))] "Closure over a module function; captures bind the callee's capture parameters in order, and a function value is a closure with no captures; closure code takes and returns Val")
  (:c opConstruct [(typeName String) (variant String) (fields (List String))] "ADT variant value; its tag is the variant's position in the type declaration")
  (:c opRecord [(schema String) (fields (List String)) (values (List String))] "Record value; fields are the declared ones in declared order")
  (:c opField [(base String) (field String)] "Record field by name")
  (:c opVariantField [(base String) (index Int64)] "Positional field of an ADT variant value, read after a switch selects the variant")
  (:c opList [(items (List String))] "List literal")
  (:c opGlobal [(name String)] "Value of a module global")
  (:c opLoadGlobal [(name String)] "Raw load of a foreign C global variable by name (environ, ...), generalizing the one native global (asl_rt_spill) the LLVM emitter previously hardcoded; result must be ptr, trusted from the instruction's own declared type rather than looked up from any module table, since SsaModule declares no foreign globals of its own -- the emitter declares `@<name> = external global ptr` for every distinct name any opLoadGlobal in the module reads")
  (:c opBox [(value String)] "Raw i64, f64 or i1 to Val")
  (:c opUnbox [(value String)] "Val to the raw type of the destination")
  (:c opPrim [(name String) (args (List String))] "Raw primitive named in primSignature: add, sub and mul of Int trap on overflow; quotInt and remInt truncate toward zero and trap on a zero divisor, quotInt also on INT64_MIN by -1. These trap by a signal (NATIVE-trapMessage: IR-internal, no ASL source path reaches them, so a bare signal was left as is rather than widened to match). Float compares are ordered except neFloat; floatToInt truncates and, like rawNarrowI32 (primSignature below), now fails through asl_rt_int_trap instead of a bare signal (NATIVE-trapMessage): ERR_INT_OVERFLOW 'Float to Int leaves int64' (kind 8) on NaN or a value outside int64. The *Host primitives compute as asl-host does and fail as it does, through asl_rt_int_trap: addIntHost, subIntHost, mulIntHost and negIntHost fail ERR_INT_OVERFLOW; divIntHost and modIntHost floor, fail ERR_DIV_ZERO on a zero divisor, and divIntHost ERR_INT_OVERFLOW on INT64_MIN by -1"))

(schema SsaEdge (:f target String) (:f args (List String)))

(schema SsaCase (:f variant String) (:f edge SsaEdge))

(enum SsaTerm
  (:c termReturn [(value String)] "Return a value of the function's return type")
  (:c termJump [(edge SsaEdge)] "Unconditional jump")
  (:c termBranch [(condition String) (thenEdge SsaEdge) (elseEdge SsaEdge)] "Two-way branch on an i1 or a Val holding a Bool")
  (:c termSwitch [(scrutinee String) (typeName String) (cases (List SsaCase)) (defaultEdge (Option SsaEdge))] "Tag switch over an ADT value; the default is required unless the cases cover every variant")
  (:c termUnreachable [] "Control never reaches here"))

(schema SsaParam (:f name String) (:f ty SsaTy))

(schema SsaInstr (:f dest String) (:f ty SsaTy) (:f op SsaOp))

(schema SsaBlock (:f label String) (:f params (List SsaParam)) (:f instrs (List SsaInstr)) (:f term SsaTerm))

(schema SsaFunction (:f name String) (:f captures (List SsaParam)) (:f params (List SsaParam)) (:f retTy SsaTy) (:f blocks (List SsaBlock)))

(schema SsaVariant (:f name String) (:f arity Int64))

(schema SsaTypeDecl (:f name String) (:f variants (List SsaVariant)))

(schema SsaRecordDecl (:f name String) (:f fields (List String)) (:f kinds (List Int64)))

(schema SsaGlobal (:f name String) (:f init String))

(schema SsaExtern (:f name String) (:f arity Int64) (:f params (List SsaTy)) (:f ret SsaTy) (:f typed Bool) (:f variadic Bool))

(schema SsaModule (:f name String) (:f strings (List String)) (:f types (List SsaTypeDecl)) (:f records (List SsaRecordDecl)) (:f externs (List SsaExtern)) (:f globals (List SsaGlobal)) (:f functions (List SsaFunction)))

fn ssaParam name: String ty: SsaTy -> SsaParam
  (SsaParam :name name :ty ty)

fn ssaInstr dest: String ty: SsaTy op: SsaOp -> SsaInstr
  (SsaInstr :dest dest :ty ty :op op)

fn ssaEdge target: String args: (List String) -> SsaEdge
  (SsaEdge :target target :args args)

fn ssaCase variant: String edge: SsaEdge -> SsaCase
  (SsaCase :variant variant :edge edge)

fn ssaBlock label: String params: (List SsaParam) instrs: (List SsaInstr) term: SsaTerm -> SsaBlock
  (SsaBlock :label label :params params :instrs instrs :term term)

fn ssaFunction name: String captures: (List SsaParam) params: (List SsaParam) retTy: SsaTy blocks: (List SsaBlock) -> SsaFunction
  (SsaFunction :name name :captures captures :params params :retTy retTy :blocks blocks)

fn ssaVariant name: String arity: Int64 -> SsaVariant
  (SsaVariant :name name :arity arity)

fn ssaTypeDecl name: String variants: (List SsaVariant) -> SsaTypeDecl
  (SsaTypeDecl :name name :variants variants)

fn ssaRecordDecl name: String fields: (List String) -> SsaRecordDecl
  (SsaRecordDecl :name name :fields fields :kinds (map (fn [(f String)] -> Int64 255) fields))

fn ssaRecordDeclTyped name: String fields: (List String) kinds: (List Int64) -> SsaRecordDecl
  (SsaRecordDecl :name name :fields fields :kinds kinds)

fn ssaRecordRaw? d: SsaRecordDecl -> Bool
  (listAny? (fn [(k Int64)] -> Bool (!= k 255)) d.kinds)

fn ssaGlobal name: String init: String -> SsaGlobal
  (SsaGlobal :name name :init init)

fn ssaExtern name: String arity: Int64 -> SsaExtern
  (SsaExtern :name name :arity arity :params (list) :ret (tyVal) :typed false :variadic false)

fn ssaExternTyped name: String params: (List SsaTy) ret: SsaTy -> SsaExtern
  (SsaExtern :name name :arity (listLength params) :params params :ret ret :typed true :variadic false)

fn ssaExternVariadic name: String params: (List SsaTy) ret: SsaTy -> SsaExtern
  (SsaExtern :name name :arity (listLength params) :params params :ret ret :typed true :variadic true)

fn ssaModule name: String strings: (List String) types: (List SsaTypeDecl) records: (List SsaRecordDecl) externs: (List SsaExtern) globals: (List SsaGlobal) functions: (List SsaFunction) -> SsaModule
  (SsaModule :name name :strings strings :types types :records records :externs externs :globals globals :functions functions)

fn ssaTyName t: SsaTy -> String
  (match t ((tyVal) "val") ((tyRec schema) (str "rec:" schema)) ((tyI64) "i64") ((tyF64) "f64") ((tyI1) "i1") ((tyPtr) "ptr") ((tyI32) "i32"))

fn ssaAbiName t: SsaTy -> String
  (match t ((tyRec _) "val") (_ (ssaTyName t)))

fn ssaIsRec? t: SsaTy -> Bool
  (match t ((tyRec _) true) (_ false))

fn ssaIsRaw? t: SsaTy -> Bool
  (!= (ssaAbiName t) "val")

fn termEdges t: SsaTerm -> (List SsaEdge)
  (match t
    ((termReturn _) (list))
    ((termJump e) (list e))
    ((termBranch _ a b) (list a b))
    ((termSwitch _ _ cases d) (listAppend (map (fn [(c SsaCase)] -> SsaEdge c.edge) cases) (match d ((some e) (list e)) ((none) (list)))))
    ((termUnreachable) (list)))

fn opOperands op: SsaOp -> (List String)
  (match op
    ((opConst _) (list))
    ((opCall _ args) args)
    ((opBuiltin _ args) args)
    ((opEntry _ args) args)
    ((opCallClosure c args) (cons c args))
    ((opMakeClosure _ caps) caps)
    ((opConstruct _ _ fields) fields)
    ((opRecord _ _ values) values)
    ((opField b _) (list b))
    ((opVariantField b _) (list b))
    ((opList items) items)
    ((opGlobal _) (list))
    ((opLoadGlobal _) (list))
    ((opBox v) (list v))
    ((opUnbox v) (list v))
    ((opPrim _ args) args))

(schema SsaPrim (:f args (List SsaTy)) (:f result SsaTy))

(schema SsaBuiltin (:f name String) (:f symbol String) (:f args (List SsaTy)) (:f result SsaTy) (:f kind String))

fn tyLetter c: String -> SsaTy
  (cond ((= c "i") (tyI64)) ((= c "f") (tyF64)) ((= c "b") (tyI1)) (else (tyVal)))

fn entryK name: String symbol: String args: String result: String kind: String -> SsaBuiltin
  (SsaBuiltin :name name :symbol symbol :args (map tyLetter (stringChars args)) :result (tyLetter result) :kind kind)

fn entry name: String symbol: String args: String result: String -> SsaBuiltin
  (entryK name symbol args result "wrap")

fn intrinsicEntry name: String symbol: String args: String result: String -> SsaBuiltin
  (entryK name symbol args result "intrinsic")

fn libmEntry name: String symbol: String args: String result: String -> SsaBuiltin
  (entryK name symbol args result "libm")

fn builtinEntries -> (List SsaBuiltin)
  (list (entry "+" "add" "vv" "v") (entry "-" "sub" "vv" "v") (entry "*" "mul" "vv" "v") (entry "/" "div" "vv" "v") (entry "mod" "mod" "vv" "v")
        (entry "<" "lt" "vv" "b") (entry "<=" "le" "vv" "b") (entry ">" "gt" "vv" "b") (entry ">=" "ge" "vv" "b") (entry "=" "eq" "vv" "b") (entry "!=" "ne" "vv" "b")
        (entry "not" "not" "v" "b")
        (entry "stringConcat" "stringConcat" "vv" "v") (entry "stringLength" "stringLength" "v" "i") (entry "stringFromInt64" "stringFromInt64" "i" "v")
        (entry "stringSlice" "stringSlice" "vii" "v") (entry "stringStartsWith?" "stringStartsWith" "vv" "b") (entry "stringContains?" "stringContains" "vv" "b")
        (entry "stringFromFloat64" "stringFromFloat64" "f" "v") (entry "stringToFloat64" "stringToFloat64" "v" "v")
        (entry "listTail" "listTail" "v" "v") (entry "listHead" "listHead" "v" "v") (entry "listEmpty?" "listEmpty" "v" "b") (entry "cons" "cons" "vv" "v")
        (entry "bytesLength" "bytesLength" "v" "i") (entry "bytesAlloc" "bytesAlloc" "i" "v") (entry "bytesGet" "bytesGet" "vi" "i") (entry "bytesSet" "bytesSet" "vii" "v")
        (intrinsicEntry "sqrt" "sqrt" "f" "f") (intrinsicEntry "floor" "floor" "f" "f") (intrinsicEntry "ceil" "ceil" "f" "f") (intrinsicEntry "round" "round" "f" "f")
        (libmEntry "pow" "pow" "ff" "f") (libmEntry "exp" "exp" "f" "f") (libmEntry "log" "log" "f" "f") (libmEntry "log2" "log2" "f" "f") (libmEntry "log10" "log10" "f" "f")
        (libmEntry "sin" "sin" "f" "f") (libmEntry "cos" "cos" "f" "f") (libmEntry "tan" "tan" "f" "f") (libmEntry "atan2" "atan2" "ff" "f")
        (entry "stringToBytes" "stringToBytes" "v" "v")
        (entry "@listHeadOr" "listHeadOr" "vv" "v") (entry "@listTailOr" "listTailOr" "vv" "v") (entry "@listGetOr" "listGetOr" "viv" "v") (entry "@stringSliceOr" "stringSliceOr" "viiv" "v")
        (entry "@listFirst" "listFirst" "v" "v") (entry "@listRest" "listRest" "v" "v")
        (entry "@listHeadEmpty?" "listHeadEmpty" "v" "b") (entry "@listTailEmpty?" "listTailEmpty" "v" "b"))

fn builtinEntry name: String arity: Int64 -> (Option SsaBuiltin)
  (cond
    ((and (= name "+") (= arity 2)) (some (entry "+" "add" "vv" "v")))
    ((and (= name "-") (= arity 2)) (some (entry "-" "sub" "vv" "v")))
    ((and (= name "*") (= arity 2)) (some (entry "*" "mul" "vv" "v")))
    ((and (= name "/") (= arity 2)) (some (entry "/" "div" "vv" "v")))
    ((and (= name "mod") (= arity 2)) (some (entry "mod" "mod" "vv" "v")))
    ((and (= name "<") (= arity 2)) (some (entry "<" "lt" "vv" "b")))
    ((and (= name "<=") (= arity 2)) (some (entry "<=" "le" "vv" "b")))
    ((and (= name ">") (= arity 2)) (some (entry ">" "gt" "vv" "b")))
    ((and (= name ">=") (= arity 2)) (some (entry ">=" "ge" "vv" "b")))
    ((and (= name "=") (= arity 2)) (some (entry "=" "eq" "vv" "b")))
    ((and (= name "!=") (= arity 2)) (some (entry "!=" "ne" "vv" "b")))
    ((and (= name "not") (= arity 1)) (some (entry "not" "not" "v" "b")))
    ((and (= name "stringConcat") (= arity 2)) (some (entry "stringConcat" "stringConcat" "vv" "v")))
    ((and (= name "stringLength") (= arity 1)) (some (entry "stringLength" "stringLength" "v" "i")))
    ((and (= name "stringFromInt64") (= arity 1)) (some (entry "stringFromInt64" "stringFromInt64" "i" "v")))
    ((and (= name "stringSlice") (= arity 3)) (some (entry "stringSlice" "stringSlice" "vii" "v")))
    ((and (= name "stringStartsWith?") (= arity 2)) (some (entry "stringStartsWith?" "stringStartsWith" "vv" "b")))
    ((and (= name "stringContains?") (= arity 2)) (some (entry "stringContains?" "stringContains" "vv" "b")))
    ((and (= name "stringFromFloat64") (= arity 1)) (some (entry "stringFromFloat64" "stringFromFloat64" "f" "v")))
    ((and (= name "stringToFloat64") (= arity 1)) (some (entry "stringToFloat64" "stringToFloat64" "v" "v")))
    ((and (= name "listTail") (= arity 1)) (some (entry "listTail" "listTail" "v" "v")))
    ((and (= name "listHead") (= arity 1)) (some (entry "listHead" "listHead" "v" "v")))
    ((and (= name "listEmpty?") (= arity 1)) (some (entry "listEmpty?" "listEmpty" "v" "b")))
    ((and (= name "cons") (= arity 2)) (some (entry "cons" "cons" "vv" "v")))
    ((and (= name "bytesLength") (= arity 1)) (some (entry "bytesLength" "bytesLength" "v" "i")))
    ((and (= name "bytesAlloc") (= arity 1)) (some (entry "bytesAlloc" "bytesAlloc" "i" "v")))
    ((and (= name "bytesGet") (= arity 2)) (some (entry "bytesGet" "bytesGet" "vi" "i")))
    ((and (= name "bytesSet") (= arity 3)) (some (entry "bytesSet" "bytesSet" "vii" "v")))
    ((and (= name "sqrt") (= arity 1)) (some (intrinsicEntry "sqrt" "sqrt" "f" "f")))
    ((and (= name "floor") (= arity 1)) (some (intrinsicEntry "floor" "floor" "f" "f")))
    ((and (= name "ceil") (= arity 1)) (some (intrinsicEntry "ceil" "ceil" "f" "f")))
    ((and (= name "round") (= arity 1)) (some (intrinsicEntry "round" "round" "f" "f")))
    ((and (= name "pow") (= arity 2)) (some (libmEntry "pow" "pow" "ff" "f")))
    ((and (= name "exp") (= arity 1)) (some (libmEntry "exp" "exp" "f" "f")))
    ((and (= name "log") (= arity 1)) (some (libmEntry "log" "log" "f" "f")))
    ((and (= name "log2") (= arity 1)) (some (libmEntry "log2" "log2" "f" "f")))
    ((and (= name "log10") (= arity 1)) (some (libmEntry "log10" "log10" "f" "f")))
    ((and (= name "sin") (= arity 1)) (some (libmEntry "sin" "sin" "f" "f")))
    ((and (= name "cos") (= arity 1)) (some (libmEntry "cos" "cos" "f" "f")))
    ((and (= name "tan") (= arity 1)) (some (libmEntry "tan" "tan" "f" "f")))
    ((and (= name "atan2") (= arity 2)) (some (libmEntry "atan2" "atan2" "ff" "f")))
    ((and (= name "stringToBytes") (= arity 1)) (some (entry "stringToBytes" "stringToBytes" "v" "v")))
    ((and (= name "@listHeadOr") (= arity 2)) (some (entry "@listHeadOr" "listHeadOr" "vv" "v")))
    ((and (= name "@listTailOr") (= arity 2)) (some (entry "@listTailOr" "listTailOr" "vv" "v")))
    ((and (= name "@listGetOr") (= arity 3)) (some (entry "@listGetOr" "listGetOr" "viv" "v")))
    ((and (= name "@stringSliceOr") (= arity 4)) (some (entry "@stringSliceOr" "stringSliceOr" "viiv" "v")))
    ((and (= name "@listFirst") (= arity 1)) (some (entry "@listFirst" "listFirst" "v" "v")))
    ((and (= name "@listRest") (= arity 1)) (some (entry "@listRest" "listRest" "v" "v")))
    ((and (= name "@listHeadEmpty?") (= arity 1)) (some (entry "@listHeadEmpty?" "listHeadEmpty" "v" "b")))
    ((and (= name "@listTailEmpty?") (= arity 1)) (some (entry "@listTailEmpty?" "listTailEmpty" "v" "b")))
    (else (none)))

fn primSignature name: String -> (Option SsaPrim)
  (cond
    ((listContains? (list "addInt" "subInt" "mulInt" "quotInt" "remInt" "addIntHost" "subIntHost" "mulIntHost" "divIntHost" "modIntHost") name) (some (SsaPrim :args (list (tyI64) (tyI64)) :result (tyI64))))
    ((= name "negIntHost") (some (SsaPrim :args (list (tyI64)) :result (tyI64))))
    ((= name "negFloat") (some (SsaPrim :args (list (tyF64)) :result (tyF64))))
    ((listContains? (list "eqBool" "neBool") name) (some (SsaPrim :args (list (tyI1) (tyI1)) :result (tyI1))))
    ((listContains? (list "eqInt" "neInt" "ltInt" "leInt" "gtInt" "geInt") name) (some (SsaPrim :args (list (tyI64) (tyI64)) :result (tyI1))))
    ((listContains? (list "addFloat" "subFloat" "mulFloat" "divFloat") name) (some (SsaPrim :args (list (tyF64) (tyF64)) :result (tyF64))))
    ((listContains? (list "eqFloat" "neFloat" "ltFloat" "leFloat" "gtFloat" "geFloat") name) (some (SsaPrim :args (list (tyF64) (tyF64)) :result (tyI1))))
    ((listContains? (list "andBool" "orBool") name) (some (SsaPrim :args (list (tyI1) (tyI1)) :result (tyI1))))
    ((= name "notBool") (some (SsaPrim :args (list (tyI1)) :result (tyI1))))
    ((= name "intToFloat") (some (SsaPrim :args (list (tyI64)) :result (tyF64))))
    ((= name "floatToInt") (some (SsaPrim :args (list (tyF64)) :result (tyI64))))
    ((listContains? (list "rawAddI64" "rawSubI64" "rawMulI64" "rawAndI64" "rawOrI64" "rawXorI64" "rawShlI64" "rawLshrI64" "rawAshrI64") name) (some (SsaPrim :args (list (tyI64) (tyI64)) :result (tyI64))))
    ((listContains? (list "rawAddI32" "rawSubI32" "rawMulI32" "rawAndI32" "rawOrI32" "rawXorI32" "rawShlI32" "rawLshrI32" "rawAshrI32") name) (some (SsaPrim :args (list (tyI32) (tyI32)) :result (tyI32))))
    ((listContains? (list "rawEqI32" "rawNeI32" "rawLtI32" "rawLeI32" "rawGtI32" "rawGeI32") name) (some (SsaPrim :args (list (tyI32) (tyI32)) :result (tyI1))))
    ((= name "rawWidenI32") (some (SsaPrim :args (list (tyI32)) :result (tyI64))))
    ((= name "rawNarrowI32") (some (SsaPrim :args (list (tyI64)) :result (tyI32))))
    ((= name "rawPtrIsNull") (some (SsaPrim :args (list (tyPtr)) :result (tyI1))))
    ((= name "rawPtrToInt") (some (SsaPrim :args (list (tyPtr)) :result (tyI64))))
    ((= name "rawIntToPtr") (some (SsaPrim :args (list (tyI64)) :result (tyPtr))))
    ((= name "rawLoadI8") (some (SsaPrim :args (list (tyPtr) (tyI64)) :result (tyI32))))
    ((= name "rawLoadI32") (some (SsaPrim :args (list (tyPtr) (tyI64)) :result (tyI32))))
    ((= name "rawLoadI64") (some (SsaPrim :args (list (tyPtr) (tyI64)) :result (tyI64))))
    ((= name "rawStoreI8") (some (SsaPrim :args (list (tyPtr) (tyI64) (tyI32)) :result (tyI1))))
    ((= name "rawStoreI32") (some (SsaPrim :args (list (tyPtr) (tyI64) (tyI32)) :result (tyI1))))
    ((= name "rawStoreI64") (some (SsaPrim :args (list (tyPtr) (tyI64) (tyI64)) :result (tyI1))))
    (else (none)))
