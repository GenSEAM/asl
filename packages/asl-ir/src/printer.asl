(module asl-ir/printer :x [printIr printFunction printStmt printExpr printType printSsa printSsaFunction printSsaOp printSsaTerm quoteString] :i [(asl-ir/types :a ty)])

fn concatOnto rlists: (List (List T)) acc: (List T) -> (List T)
  (mt (listHead rlists) ((some xs) (concatOnto (optionOr (listTail rlists) (list)) (listAppend xs acc))) ((none) acc))

fn concatLists lists: (List (List T)) -> (List T)
  (concatOnto (listReverse lists) (list))

fn printType t: ty/IrType -> Str
  (let [(repr t.repr)] (if (= repr "raw") (str "(ir/type :" t.kind ")") (str "(ir/type :" t.kind " :repr :" repr ")")))

fn printExpr e: ty/IrExpr -> Str
  (let [(k e.kind)] (cond ((= k "binop") (str "(ir/binop :" e.op " " e.left " " e.right (if e.shiftMask " :shiftMask true" "") (if e.divModFloor " :divModFloor true" "") ")")) ((= k "cmp") (str "(ir/cmp :" e.op " " e.left " " e.right ")")) ((= k "call") (str "(ir/call " e.op " [" (stringJoin e.args " ") "])")) ((= k "alloc") (str "(ir/alloc " (printType e.ty) " [" (stringJoin e.args " ") "])")) ((= k "atom") e.left) (else (str "(ir/" k ")"))))

fn printStmt s: ty/IrStmt -> Str
  (let [(k s.kind)] (cond ((= k "let") (str "  (ir/let " s.target " " (printType s.ty) " " (printExpr s.expr) ")")) ((= k "return") (if (= s.value "") "  (ir/return)" (str "  (ir/return " s.value ")"))) ((= k "drop") (str "  (ir/drop " s.target " " (printType s.ty) ")")) ((= k "switch") (str "  (ir/switch " s.scrutinee " :cases [" (stringJoin (map (fn [(c ty/IrSwitchCase)] -> Str (str "(:case :" c.tag " [" (stringJoin c.bindings " ") "])")) s.cases) " ") "] :default [...])")) (else (str "  (ir/" k ")"))))

fn printFunction f: ty/IrFunction -> Str
  (let [(pStrs (map (fn [(p ty/IrParam)] -> Str (str "(" p.name " " (printType p.ty) ")")) f.params)) (bStrs (map printStmt f.body))] (str "(ir/func " f.name " [" (stringJoin pStrs " ") "] " (printType f.retType) "\n" (stringJoin bStrs "\n") ")"))

fn printIr m: ty/IrModule -> Str
  (let [(fStrs (map printFunction m.funcs))] (str "(:ir-module :name \"" m.name "\" :profile \"" m.profile "\"\n" (stringJoin fStrs "\n\n") "\n)"))

fn quoteString s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") "\"")

fn form head: String items: (List String) -> String
  (str "(" (stringJoin (cons head items) " ") ")")

fn printSsaParam p: ty/SsaParam -> String
  (str "(" p.name " " (ty/ssaTyName p.ty) ")")

fn printSsaConst c: ty/SsaConst -> String
  (mt c
    ((ty/constInt n) (str "(const int " (stringFromInt64 n) ")"))
    ((ty/constFloat x) (str "(const float " (stringFromFloat64 x) ")"))
    ((ty/constBool b) (if b "(const bool true)" "(const bool false)"))
    ((ty/constStr i) (str "(const str " (stringFromInt64 i) ")"))
    ((ty/constUnit) "(const unit)")
    ((ty/constKeyword name) (str "(const keyword " name ")"))
    ((ty/constSymbol name) (str "(const symbol " name ")")))

fn printSsaOp op: ty/SsaOp -> String
  (mt op
    ((ty/opConst c) (printSsaConst c))
    ((ty/opCall callee args) (form "call" (cons callee args)))
    ((ty/opBuiltin name args) (form "builtin" (cons (quoteString name) args)))
    ((ty/opEntry name args) (form "entry" (cons (quoteString name) args)))
    ((ty/opCallClosure c args) (form "call-closure" (cons c args)))
    ((ty/opMakeClosure callee caps) (form "make-closure" (cons callee caps)))
    ((ty/opConstruct typeName variant fields) (form "construct" (cons typeName (cons variant fields))))
    ((ty/opRecord schemaName keys values) (form "record" (cons schemaName (recordFields keys values (list)))))
    ((ty/opField base field) (form "field" (list base field)))
    ((ty/opVariantField base i) (form "variant-field" (list base (stringFromInt64 i))))
    ((ty/opList items) (form "list" items))
    ((ty/opGlobal name) (form "global" (list name)))
    ((ty/opLoadGlobal name) (form "load-global" (list name)))
    ((ty/opBox v) (form "box" (list v)))
    ((ty/opUnbox v) (form "unbox" (list v)))
    ((ty/opPrim name args) (form "prim" (cons name args))))

fn recordFields keys: (List String) values: (List String) out: (List String) -> (List String)
  (mt (listHead keys)
    ((none) (listReverse out))
    ((some k) (recordFields (optionOr (listTail keys) (list)) (optionOr (listTail values) (list)) (cons (str "(" k " " (optionOr (listHead values) "?") ")") out))))

fn printSsaEdge e: ty/SsaEdge -> String
  (form e.target e.args)

fn printSsaTerm t: ty/SsaTerm -> String
  (mt t
    ((ty/termReturn v) (form "return" (list v)))
    ((ty/termJump e) (form "jump" (list (printSsaEdge e))))
    ((ty/termBranch c a b) (form "branch" (list c (printSsaEdge a) (printSsaEdge b))))
    ((ty/termSwitch s typeName cases d) (form "switch" (listAppend (list s typeName)
                                                          (listAppend (map (fn [(k ty/SsaCase)] -> String (form k.variant (list (printSsaEdge k.edge)))) cases)
                                                                       (mt d ((some e) (list (form "default" (list (printSsaEdge e))))) ((none) (list)))))))
    ((ty/termUnreachable) "(unreachable)"))

fn printSsaBlock b: ty/SsaBlock -> (List String)
  (listAppend
    (cons (str "    (block " b.label " (" (stringJoin (map printSsaParam b.params) " ") ")")
               (map (fn [(i ty/SsaInstr)] -> String (str "      (let " i.dest " " (ty/ssaTyName i.ty) " " (printSsaOp i.op) ")")) b.instrs))
    (list (str "      " (printSsaTerm b.term) ")")))

fn closeLast lines: (List String) -> (List String)
  (mt (listSlice lines 0 (- (listLength lines) 1))
    ((none) lines)
    ((some front) (listAppend front (list (str (optionOr (listGet lines (- (listLength lines) 1)) "") ")")))))

fn printSsaFunction f: ty/SsaFunction -> (List String)
  (closeLast (cons (str "  (fn " f.name " " (form "captures" (map printSsaParam f.captures)) " " (form "params" (map printSsaParam f.params)) " (returns " (ty/ssaTyName f.retTy) ")")
                        (concatLists (map printSsaBlock f.blocks))))

fn printSsa m: ty/SsaModule -> String
  (let [(header (list (str "(ssa-module " (quoteString m.name))
                      (str "  " (form "strings" (map quoteString m.strings)))))
        (types (map (fn [(d ty/SsaTypeDecl)] -> String (str "  " (form "type" (cons d.name (map (fn [(v ty/SsaVariant)] -> String (form v.name (list (stringFromInt64 v.arity)))) d.variants))))) m.types))
        (records (map (fn [(r ty/SsaRecordDecl)] -> String (str "  " (form "record" (cons r.name r.fields)))) m.records))
        (externs (map (fn [(e ty/SsaExtern)] -> String (str "  " (form "extern" (list e.name (stringFromInt64 e.arity))))) m.externs))
        (globals (map (fn [(g ty/SsaGlobal)] -> String (str "  " (form "global" (list g.name g.init)))) m.globals))
        (functions (concatLists (map printSsaFunction m.functions)))]
    (stringJoin (closeLast (listAppend header (listAppend types (listAppend records (listAppend externs (listAppend globals functions)))))) "\n"))
