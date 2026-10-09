(module asl-ir/verify :x [verifyIr verifyStmt verifyFunction verifyModule verifySsa verifySsaDiags] :i [(asl-ir/types :a ty) (asl-ir/anf :a anf)])

fn verifyStmt s: ty/IrStmt env: (Map Str ty/IrType) -> (List ty/IrDiag)
  (let [(k s.kind)] (cond ((= k "switch") (if (listEmpty? s.defaultBody) (list (ty/makeIrDiag "ERR_IR_MISSING_DEFAULT" "Switch statement lacks mandatory default branch" s.scrutinee)) (list))) ((= k "let") (let [(target s.target) (expr s.expr)] (cond ((some? (mapGet env target)) (list (ty/makeIrDiag "ERR_IR_DUPLICATE_BINDING" (str "Variable '" target "' bound more than once in same scope") target))) ((and (!= expr.left "") (not (anf/isTerminalAtom? expr.left))) (list (ty/makeIrDiag "ERR_IR_NON_ANF" "Compound expression in operand position is not in ANF" target))) ((and (!= expr.right "") (not (anf/isTerminalAtom? expr.right))) (list (ty/makeIrDiag "ERR_IR_NON_ANF" "Compound expression in operand position is not in ANF" target))) ((and (= s.ty.kind "option") (= s.ty.repr "nullable") (or (= expr.left "unit") (= expr.left "Unit"))) (list (ty/makeIrDiag "ERR_IR_INVALID_OPTION_REPR" "Option Unit cannot have nullable representation" target))) ((and (!= expr.left "") (none? (mapGet env expr.left)) (not (isLiteral? expr.left))) (list (ty/makeIrDiag "ERR_IR_UNBOUND_VAR" (str "Variable '" expr.left "' is unbound") expr.left))) ((and (!= expr.ty.kind "") (!= s.ty.kind "") (!= s.ty.kind expr.ty.kind)) (list (ty/makeIrDiag "ERR_IR_TYPE_MISMATCH" (str "Type mismatch: statement type '" s.ty.kind "' does not match expression type '" expr.ty.kind "'") target))) ((and (= s.ty.kind "buf") s.ty.isSecondClass (= expr.kind "alloc")) (list)) (else (list))))) ((= k "return") (let [(val s.value)] (if (and (!= val "") (none? (mapGet env val)) (not (isLiteral? val))) (list (ty/makeIrDiag "ERR_IR_UNBOUND_VAR" (str "Returned variable '" val "' is unbound") val)) (let [(valTy (if (!= val "") (mapGet env val) (none)))] (if (mt valTy ((some t) t.isSecondClass) ((none) false)) (list (ty/makeIrDiag "ERR_IR_BUF_ESCAPE" "Second-class buffer escapes local scope via return" val)) (list)))))) (else (list))))

fn isLiteral? s: Str -> Bool
  (or (= s "true") (= s "false") (= s "None") (= s "unit") (= s "Unit") (= s "()") (stringStartsWith? s "\"") (stringStartsWith? s "-") (and (>= (optionOr (stringSlice s 0 1) "") "0") (<= (optionOr (stringSlice s 0 1) "") "9")))

(schema VerifyState (:f env (Map Str ty/IrType)) (:f diags (List ty/IrDiag)))

fn stepVerifyStmt st: VerifyState s: ty/IrStmt -> VerifyState
  (let [(curEnv st.env) (curDiags st.diags) (newDiags (verifyStmt s curEnv)) (nextEnv (if (= s.kind "let") (mapSet curEnv s.target s.ty) curEnv))] (VerifyState :env nextEnv :diags (listAppend curDiags newDiags)))

fn verifyFunction f: ty/IrFunction -> (List ty/IrDiag)
  (let [(body f.body)] (if (listEmpty? body) (list (ty/makeIrDiag "ERR_IR_UNTERMINATED_BLOCK" (str "Function '" f.name "' body is empty") f.name)) (let [(lastStmt (optionOr (listGet body (- (listLength body) 1)) (ty/makeIrReturn "" (ty/makeIrType "unit" "raw" false)))) (lastKind lastStmt.kind) (termDiags (if (and (!= lastKind "return") (!= lastKind "jump")) (list (ty/makeIrDiag "ERR_IR_UNTERMINATED_BLOCK" (str "Function '" f.name "' block does not end in return or jump") f.name)) (list))) (initEnv (fold (fn [(acc (Map Str ty/IrType)) (p ty/IrParam)] -> (Map Str ty/IrType) (mapSet acc p.name p.ty)) (mapEmpty) f.params)) (initState (VerifyState :env initEnv :diags (list))) (finalState (fold stepVerifyStmt initState body))] (listAppend termDiags finalState.diags))))

fn verifyModule m: ty/IrModule -> (List ty/IrDiag)
  (fold (fn [(acc (List ty/IrDiag)) (f ty/IrFunction)] -> (List ty/IrDiag) (listAppend acc (verifyFunction f))) (list) m.funcs)

fn verifyIr m: ty/IrModule -> (Result Unit (List ty/IrDiag))
  (let [(diags (verifyModule m))] (if (listEmpty? diags) (ok ()) (err diags)))

(schema SsaCtx (:f arities (Map String Int64)) (:f externs (Map String ty/SsaExtern)) (:f functions (Map String ty/SsaFunction)) (:f types (Map String (List ty/SsaVariant))) (:f records (Map String (List String))) (:f globals (Map String Bool)) (:f stringCount Int64))

(schema DefSite (:f block String) (:f index Int64) (:f ty ty/SsaTy))

(enum DefIndex
  (:c defIndexEmpty [] "Empty SSA definition index")
  (:c defIndexNode [(key String) (site DefSite) (left DefIndex) (right DefIndex) (height Int64)] "AVL node keyed by SSA value"))

(schema DefState (:f defs DefIndex) (:f diags (List ty/IrDiag)))

(schema DefWalk (:f state DefState) (:f index Int64))

(schema DupState (:f seen (Map String Bool)) (:f diags (List ty/IrDiag)))

(schema InstrWalk (:f index Int64) (:f diags (List ty/IrDiag)))

(schema FnCtx (:f name String) (:f defs DefIndex) (:f blocks (Map String ty/SsaBlock)) (:f entry String) (:f doms (Map String (List String))) (:f retTy ty/SsaTy))

fn defIndexHeight tree: DefIndex -> Int64
  (mt tree ((defIndexEmpty) 0) ((defIndexNode _ _ _ _ height) height))

fn defIndexNodeOf key: String site: DefSite left: DefIndex right: DefIndex -> DefIndex
  (defIndexNode key site left right (+ 1 (max (defIndexHeight left) (defIndexHeight right))))

fn defIndexBalance key: String site: DefSite left: DefIndex right: DefIndex -> DefIndex
  (let [(lh (defIndexHeight left)) (rh (defIndexHeight right))]
    (cond
      ((> lh (+ rh 1))
        (mt left
          ((defIndexEmpty) (defIndexNodeOf key site left right))
          ((defIndexNode leftKey leftSite leftLeft leftRight _)
            (if (>= (defIndexHeight leftLeft) (defIndexHeight leftRight))
              (defIndexNodeOf leftKey leftSite leftLeft (defIndexNodeOf key site leftRight right))
              (mt leftRight
                ((defIndexEmpty) (defIndexNodeOf key site left right))
                ((defIndexNode pivotKey pivotSite pivotLeft pivotRight _)
                  (defIndexNodeOf pivotKey pivotSite
                    (defIndexNodeOf leftKey leftSite leftLeft pivotLeft)
                    (defIndexNodeOf key site pivotRight right))))))))
      ((> rh (+ lh 1))
        (mt right
          ((defIndexEmpty) (defIndexNodeOf key site left right))
          ((defIndexNode rightKey rightSite rightLeft rightRight _)
            (if (>= (defIndexHeight rightRight) (defIndexHeight rightLeft))
              (defIndexNodeOf rightKey rightSite (defIndexNodeOf key site left rightLeft) rightRight)
              (mt rightLeft
                ((defIndexEmpty) (defIndexNodeOf key site left right))
                ((defIndexNode pivotKey pivotSite pivotLeft pivotRight _)
                  (defIndexNodeOf pivotKey pivotSite
                    (defIndexNodeOf key site left pivotLeft)
                    (defIndexNodeOf rightKey rightSite pivotRight rightRight))))))))
      (else (defIndexNodeOf key site left right))))

fn defIndexSet tree: DefIndex key: String site: DefSite -> DefIndex
  (mt tree
    ((defIndexEmpty) (defIndexNodeOf key site (defIndexEmpty) (defIndexEmpty)))
    ((defIndexNode currentKey currentSite left right _)
      (cond
        ((= key currentKey) (defIndexNodeOf key site left right))
        ((< key currentKey) (defIndexBalance currentKey currentSite (defIndexSet left key site) right))
        (else (defIndexBalance currentKey currentSite left (defIndexSet right key site))))))

fn defIndexGet tree: DefIndex key: String -> (Option DefSite)
  (mt tree
    ((defIndexEmpty) (none))
    ((defIndexNode currentKey site left right _)
      (cond
        ((= key currentKey) (some site))
        ((< key currentKey) (defIndexGet left key))
        (else (defIndexGet right key)))))

fn ssaDiag code: String message: String locus: String -> ty/IrDiag
  (ty/makeIrDiag code message locus)

fn concatDiags lists: (List (List ty/IrDiag)) -> (List ty/IrDiag)
  (fold (fn [(acc (List ty/IrDiag)) (ds (List ty/IrDiag))] -> (List ty/IrDiag) (listAppend acc ds)) (list) lists)

fn duplicateNames kind: String names: (List String) locus: String -> (List ty/IrDiag)
  (fold (fn [(st DupState) (n String)] -> DupState
                   (if (mapHas? st.seen n)
                     (DupState :seen st.seen :diags (listAppend st.diags (list (ssaDiag "ERR_IR_DUPLICATE_DEFINITION" (str kind " '" n "' is defined more than once") (str locus n)))))
                     (DupState :seen (mapSet st.seen n true) :diags st.diags)))
                 (DupState :seen (mapEmpty) :diags (list)) names).diags

fn buildCtx m: ty/SsaModule -> SsaCtx
  (let [(fnArities (fold (fn [(acc (Map String Int64)) (f ty/SsaFunction)] -> (Map String Int64) (if (mapHas? acc f.name) acc (mapSet acc f.name (listLength f.params)))) (mapEmpty) m.functions))
        (arities (fold (fn [(acc (Map String Int64)) (e ty/SsaExtern)] -> (Map String Int64) (if (mapHas? acc e.name) acc (mapSet acc e.name e.arity))) fnArities m.externs))
        (functions (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (if (mapHas? acc f.name) acc (mapSet acc f.name f))) (mapEmpty) m.functions))
        (types (fold (fn [(acc (Map String (List ty/SsaVariant))) (d ty/SsaTypeDecl)] -> (Map String (List ty/SsaVariant)) (if (mapHas? acc d.name) acc (mapSet acc d.name d.variants))) (mapEmpty) m.types))
        (records (fold (fn [(acc (Map String (List String))) (r ty/SsaRecordDecl)] -> (Map String (List String)) (if (mapHas? acc r.name) acc (mapSet acc r.name r.fields))) (mapEmpty) m.records))
        (externMap (fold (fn [(acc (Map String ty/SsaExtern)) (e ty/SsaExtern)] -> (Map String ty/SsaExtern) (if (mapHas? acc e.name) acc (mapSet acc e.name e))) (mapEmpty) m.externs))
        (globals (fold (fn [(acc (Map String Bool)) (g ty/SsaGlobal)] -> (Map String Bool) (mapSet acc g.name true)) (mapEmpty) m.globals))]
    (SsaCtx :arities arities :externs externMap :functions functions :types types :records records :globals globals :stringCount (listLength m.strings)))

fn checkGlobal ctx: SsaCtx locus: String g: ty/SsaGlobal -> (List ty/IrDiag)
  (let [(at (str locus g.name))]
    (mt (mapGet ctx.functions g.init)
      ((none) (list (ssaDiag "ERR_IR_UNKNOWN_FUNCTION" (str "global '" g.name "' is initialised by '" g.init "', which is not a module function") at)))
      ((some f) (cond
                  ((not (and (listEmpty? f.params) (listEmpty? f.captures))) (list (ssaDiag "ERR_IR_ARITY" (str "global initialiser '" g.init "' must take no params and no captures") at)))
                  ((ty/ssaIsRaw? f.retTy) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "global initialiser '" g.init "' must return val") at)))
                  (else (list))))))

fn findVariant variants: (List ty/SsaVariant) name: String -> (Option ty/SsaVariant)
  (listHead (filter (fn [(v ty/SsaVariant)] -> Bool (= v.name name)) variants))

fn addDef st: DefState name: String site: DefSite locus: String -> DefState
  (if (some? (defIndexGet st.defs name))
    (with st :diags (listAppend st.diags (list (ssaDiag "ERR_IR_DUPLICATE_DEFINITION" (str "value '" name "' is defined more than once") (str locus name)))))
    (with st :defs (defIndexSet st.defs name site)))

fn collectBlockDefs st: DefState b: ty/SsaBlock locus: String -> DefState
  (let [(label b.label)
        (at (str locus label "/"))
        (withParams (fold (fn [(acc DefState) (p ty/SsaParam)] -> DefState (addDef acc p.name (DefSite :block label :index -1 :ty p.ty) at)) st b.params))
        (walk (fold (fn [(w DefWalk) (ins ty/SsaInstr)] -> DefWalk
                      (DefWalk :state (addDef w.state ins.dest (DefSite :block label :index w.index :ty ins.ty) at) :index (+ w.index 1)))
                    (DefWalk :state withParams :index 0) b.instrs))]
    walk.state)

fn collectDefs f: ty/SsaFunction -> DefState
  (let [(locus (str f.name "/"))
        (start (fold (fn [(st DefState) (p ty/SsaParam)] -> DefState (addDef st p.name (DefSite :block "" :index -1 :ty p.ty) locus))
                     (DefState :defs (defIndexEmpty) :diags (list))
                     (listAppend f.captures f.params)))]
    (fold (fn [(st DefState) (b ty/SsaBlock)] -> DefState (collectBlockDefs st b locus)) start f.blocks))

fn successorMap blocks: (List ty/SsaBlock) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (b ty/SsaBlock)] -> (Map String (List String))
          (mapSet acc b.label (listAppend (optionOr (mapGet acc b.label) (list)) (map (fn [(e ty/SsaEdge)] -> String e.target) (ty/termEdges b.term)))))
        (mapEmpty) blocks)

fn reachable work: (List String) seen: (Map String Bool) succs: (Map String (List String)) -> (Map String Bool)
  (mt (listHead work)
    ((none) seen)
    ((some b) (let [(rest (optionOr (listTail work) (list)))]
                (if (mapHas? seen b)
                  (reachable rest seen succs)
                  (reachable (listAppend (optionOr (mapGet succs b) (list)) rest) (mapSet seen b true) succs)))))

fn predecessorMap succs: (Map String (List String)) reach: (Map String Bool) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (b String)] -> (Map String (List String))
          (if (mapHas? reach b)
            (fold (fn [(inner (Map String (List String))) (s String)] -> (Map String (List String)) (mapSet inner s (listAppend (optionOr (mapGet inner s) (list)) (list b))))
                  acc (optionOr (mapGet succs b) (list)))
            acc))
        (mapEmpty) (mapKeys succs))

fn domRound labels: (List String) entry: String preds: (Map String (List String)) reach: (Map String Bool) doms: (Map String (List String)) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (b String)] -> (Map String (List String))
          (if (or (= b entry) (not (mapHas? reach b)))
            acc
            (let [(sets (map (fn [(p String)] -> (List String) (optionOr (mapGet acc p) labels)) (optionOr (mapGet preds b) (list))))
                  (common (filter (fn [(l String)] -> Bool (fold (fn [(inAll Bool) (s (List String))] -> Bool (and inAll (listContains? s l))) true sets)) labels))]
              (mapSet acc b (if (listContains? common b) common (listAppend common (list b)))))))
        doms labels)

fn domFix labels: (List String) entry: String preds: (Map String (List String)) reach: (Map String Bool) doms: (Map String (List String)) rounds: Int64 -> (Map String (List String))
  (let [(updated (domRound labels entry preds reach doms))]
    (if (or (<= rounds 0) (= (mapValues updated) (mapValues doms)))
      updated
      (domFix labels entry preds reach updated (- rounds 1))))

fn dominators labels: (List String) entry: String preds: (Map String (List String)) reach: (Map String Bool) -> (Map String (List String))
  (let [(initial (fold (fn [(acc (Map String (List String))) (l String)] -> (Map String (List String))
                         (if (= l entry) (mapSet acc l (list l)) (mapSet acc l labels)))
                       (mapEmpty) labels))
        (n (listLength labels))]
    (domFix labels entry preds reach initial (+ (* n n) 2)))

fn checkUse fc: FnCtx label: String index: Int64 name: String locus: String -> (List ty/IrDiag)
  (mt (defIndexGet fc.defs name)
    ((none) (list (ssaDiag "ERR_IR_UNDEFINED_VALUE" (str "value '" name "' is not defined") locus)))
    ((some d) (cond
                ((= d.block "") (list))
                ((= d.block label) (if (< d.index index) (list) (list (ssaDiag "ERR_IR_UNDEFINED_VALUE" (str "value '" name "' is used before its definition") locus))))
                ((listContains? (optionOr (mapGet fc.doms label) (list)) d.block) (list))
                (else (list (ssaDiag "ERR_IR_UNDEFINED_VALUE" (str "value '" name "' is defined in block '" d.block "', which does not dominate '" label "'") locus))))))

fn expectTy fc: FnCtx name: String want: ty/SsaTy locus: String -> (List ty/IrDiag)
  (mt (defIndexGet fc.defs name)
    ((none) (list))
    ((some d) (if (= (ty/ssaAbiName d.ty) (ty/ssaAbiName want))
                (list)
                (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "value '" name "' is " (ty/ssaTyName d.ty) " where " (ty/ssaTyName want) " is required") locus)))))

fn expectVals fc: FnCtx names: (List String) locus: String -> (List ty/IrDiag)
  (concatDiags (map (fn [(n String)] -> (List ty/IrDiag) (expectTy fc n (ty/tyVal) locus)) names))

fn variadicArgAllowed? n: String -> Bool
  (or (= n "i32") (= n "i64") (= n "f64") (= n "ptr"))

fn expectVariadicArg fc: FnCtx name: String locus: String -> (List ty/IrDiag)
  (mt (defIndexGet fc.defs name)
    ((none) (list))
    ((some d) (if (variadicArgAllowed? (ty/ssaTyName d.ty))
                (list)
                (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "variadic argument '" name "' is " (ty/ssaTyName d.ty) "; only i32, i64, f64 or ptr may pass through ...") locus)))))

fn classicRawName? n: String -> Bool
  (or (= n "i64") (= n "f64") (= n "i1"))

fn expectRaw fc: FnCtx name: String locus: String -> (List ty/IrDiag)
  (mt (defIndexGet fc.defs name)
    ((none) (list))
    ((some d) (if (classicRawName? (ty/ssaTyName d.ty)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "box of '" name "', which is " (ty/ssaTyName d.ty) ", not i64, f64 or i1") locus)))))

fn resultVal t: ty/SsaTy locus: String -> (List ty/IrDiag)
  (if (ty/ssaIsRaw? t) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "result is " (ty/ssaTyName t) " where val is required") locus)) (list))

fn constAllows tn: String raw: String locus: String -> (List ty/IrDiag)
  (if (or (= tn "val") (= tn raw)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "this constant cannot be " tn) locus)))

fn constAllowsAny tn: String raws: (List String) locus: String -> (List ty/IrDiag)
  (if (or (= tn "val") (listContains? raws tn)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "this constant cannot be " tn) locus)))

fn i32Range? n: Int64 -> Bool
  (and (>= n -2147483648) (<= n 2147483647))

fn checkConst ctx: SsaCtx locus: String t: ty/SsaTy c: ty/SsaConst -> (List ty/IrDiag)
  (let [(tn (ty/ssaTyName t))]
    (mt c
      ((ty/constInt n) (listAppend (constAllowsAny tn (list "i64" "i32") locus)
                                    (if (and (= tn "i32") (not (i32Range? n)))
                                      (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "i32 constant " n " is outside -2147483648..2147483647") locus))
                                      (list))))
      ((ty/constFloat _) (constAllows tn "f64" locus))
      ((ty/constBool _) (constAllows tn "i1" locus))
      ((ty/constStr i) (listAppend (constAllowsAny tn (list "ptr") locus) (if (and (>= i 0) (< i ctx.stringCount)) (list) (list (ssaDiag "ERR_IR_STRING_INDEX" (str "string index " i " is outside the pool of " ctx.stringCount) locus)))))
      ((ty/constUnit) (constAllows tn "val" locus))
      ((ty/constKeyword _) (constAllows tn "val" locus))
      ((ty/constSymbol _) (constAllows tn "val" locus))))

fn argTypes fc: FnCtx args: (List String) params: (List ty/SsaParam) locus: String -> (List ty/IrDiag)
  (concatDiags (map (fn [(i Int64)] -> (List ty/IrDiag)
                      (mt (listGet args i)
                        ((none) (list))
                        ((some a) (mt (listGet params i)
                                    ((none) (list))
                                    ((some p) (expectTy fc a p.ty locus))))))
                    (range 0 (listLength args))))

fn resultTy t: ty/SsaTy want: ty/SsaTy locus: String -> (List ty/IrDiag)
  (if (= (ty/ssaAbiName t) (ty/ssaAbiName want)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "result is " (ty/ssaTyName t) " where the callee returns " (ty/ssaTyName want)) locus)))

fn checkCall ctx: SsaCtx fc: FnCtx t: ty/SsaTy callee: String args: (List String) locus: String -> (List ty/IrDiag)
  (mt (mapGet ctx.functions callee)
    ((some f) (cond
                ((not (listEmpty? f.captures)) (list (ssaDiag "ERR_IR_CLOSURE_CODE" (str "'" callee "' has captures and is reached only through make-closure") locus)))
                ((!= (listLength f.params) (listLength args)) (list (ssaDiag "ERR_IR_ARITY" (str "'" callee "' takes " (listLength f.params) " argument(s), got " (listLength args)) locus)))
                (else (listAppend (argTypes fc args f.params locus) (resultTy t f.retTy locus)))))
    ((none) (mt (mapGet ctx.externs callee)
              ((some e)
                (cond
                  ((if e.variadic (< (listLength args) e.arity) (!= e.arity (listLength args)))
                   (list (ssaDiag "ERR_IR_ARITY" (str "extern '" callee "' takes " (if e.variadic "at least " "") e.arity " argument(s), got " (listLength args)) locus)))
                  ((not e.typed) (listAppend (expectVals fc args locus) (resultVal t locus)))
                  (else
                    (listAppend
                      (concatDiags (map (fn [(i Int64)] -> (List ty/IrDiag)
                                          (mt (listGet args i)
                                            ((none) (list))
                                            ((some a) (mt (listGet e.params i)
                                                        ((none) (if e.variadic (expectVariadicArg fc a locus) (list)))
                                                        ((some pTy) (expectTy fc a pTy locus))))))
                                        (range 0 (listLength args))))
                      (resultTy t e.ret locus)))))
              ((none)
                (mt (mapGet ctx.arities callee)
                  ((none) (list (ssaDiag "ERR_IR_UNKNOWN_FUNCTION" (str "call of undeclared function '" callee "'") locus)))
                  ((some n) (if (= n (listLength args))
                              (listAppend (expectVals fc args locus) (resultVal t locus))
                              (list (ssaDiag "ERR_IR_ARITY" (str "extern '" callee "' takes " n " argument(s), got " (listLength args)) locus)))))))))

fn allVal params: (List ty/SsaParam) -> Bool
  (listEmpty? (filter (fn [(p ty/SsaParam)] -> Bool (ty/ssaIsRaw? p.ty)) params))

fn checkClosure ctx: SsaCtx fc: FnCtx callee: String caps: (List String) locus: String -> (List ty/IrDiag)
  (mt (mapGet ctx.functions callee)
    ((none) (list (ssaDiag "ERR_IR_UNKNOWN_FUNCTION" (str "make-closure of '" callee "', which is not a module function") locus)))
    ((some f) (cond
                ((!= (listLength f.captures) (listLength caps)) (list (ssaDiag "ERR_IR_ARITY" (str "'" callee "' captures " (listLength f.captures) " value(s), got " (listLength caps)) locus)))
                ((not (and (allVal f.params) (not (ty/ssaIsRaw? f.retTy)))) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "closure code '" callee "' must take and return val, the indirect-call ABI") locus)))
                (else (argTypes fc caps f.captures locus)))))

fn checkConstruct ctx: SsaCtx typeName: String variant: String fields: (List String) locus: String -> (List ty/IrDiag)
  (mt (mapGet ctx.types typeName)
    ((none) (list (ssaDiag "ERR_IR_UNKNOWN_TYPE" (str "construct of undeclared type '" typeName "'") locus)))
    ((some variants) (mt (findVariant variants variant)
                       ((none) (list (ssaDiag "ERR_IR_UNKNOWN_VARIANT" (str "type '" typeName "' has no variant '" variant "'") locus)))
                       ((some v) (if (= v.arity (listLength fields)) (list) (list (ssaDiag "ERR_IR_ARITY" (str "variant '" variant "' has " v.arity " field(s), got " (listLength fields)) locus)))))))

fn recordKeysInOrder? declared: (List String) keys: (List String) -> Bool
  (mt (listHead keys)
    ((none) true)
    ((some key) (mt (listHead declared)
                  ((none) false)
                  ((some field) (if (= key field)
                                 (recordKeysInOrder? (optionOr (listTail declared) (list)) (optionOr (listTail keys) (list)))
                                 (recordKeysInOrder? (optionOr (listTail declared) (list)) keys))))))

fn checkRecord ctx: SsaCtx schemaName: String keys: (List String) values: (List String) locus: String -> (List ty/IrDiag)
  (mt (mapGet ctx.records schemaName)
    ((none) (list (ssaDiag "ERR_IR_UNKNOWN_RECORD" (str "record of undeclared schema '" schemaName "'") locus)))
    ((some declared)
     (if (!= (listLength keys) (listLength values))
       (list (ssaDiag "ERR_IR_ARITY" (str "record '" schemaName "' names " (listLength keys) " field(s) for " (listLength values) " value(s)") locus))
       (if (> (listLength keys) (listLength declared))
         (list (ssaDiag "ERR_IR_ARITY" (str "record '" schemaName "' has " (listLength declared) " field(s), got " (listLength keys)) locus))
         (if (recordKeysInOrder? declared keys)
           (list)
           (list (ssaDiag "ERR_IR_UNKNOWN_FIELD" (str "record '" schemaName "' fields must be an ordered subset of " (stringJoin declared " ")) locus)))))))

fn checkPrim fc: FnCtx t: ty/SsaTy name: String args: (List String) locus: String -> (List ty/IrDiag)
  (mt (ty/primSignature name)
    ((none) (list (ssaDiag "ERR_IR_UNKNOWN_PRIM" (str "unknown primitive '" name "'") locus)))
    ((some sig) (if (= (listLength sig.args) (listLength args))
                  (listAppend (argTypes fc args (map (fn [(a ty/SsaTy)] -> ty/SsaParam (ty/ssaParam "" a)) sig.args) locus)
                               (if (= (ty/ssaTyName t) (ty/ssaTyName sig.result)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "primitive '" name "' yields " (ty/ssaTyName sig.result) ", not " (ty/ssaTyName t)) locus))))
                  (list (ssaDiag "ERR_IR_ARITY" (str "primitive '" name "' takes " (listLength sig.args) " operand(s), got " (listLength args)) locus)))))

fn checkEntry fc: FnCtx t: ty/SsaTy name: String args: (List String) locus: String -> (List ty/IrDiag)
  (mt (ty/builtinEntry name (listLength args))
    ((none) (list (ssaDiag "ERR_IR_UNKNOWN_FUNCTION" (str "no runtime entry '" name "' takes " (listLength args) " operand(s)") locus)))
    ((some b) (listAppend (argTypes fc args (map (fn [(a ty/SsaTy)] -> ty/SsaParam (ty/ssaParam "" a)) b.args) locus)
                          (if (= (ty/ssaTyName t) (ty/ssaTyName b.result)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "entry '" name "' yields " (ty/ssaTyName b.result) ", not " (ty/ssaTyName t)) locus))))))

fn checkOp ctx: SsaCtx fc: FnCtx locus: String t: ty/SsaTy op: ty/SsaOp -> (List ty/IrDiag)
  (mt op
    ((ty/opConst c) (checkConst ctx locus t c))
    ((ty/opCall callee args) (checkCall ctx fc t callee args locus))
    ((ty/opBuiltin name args) (concatDiags (list (resultVal t locus) (expectVals fc args locus) (if (stringEmpty? name) (list (ssaDiag "ERR_IR_UNKNOWN_FUNCTION" "builtin call without a name" locus)) (list)))))
    ((ty/opEntry name args) (checkEntry fc t name args locus))
    ((ty/opCallClosure c args) (listAppend (resultVal t locus) (expectVals fc (cons c args) locus)))
    ((ty/opMakeClosure callee caps) (listAppend (resultVal t locus) (checkClosure ctx fc callee caps locus)))
    ((ty/opConstruct typeName variant fields) (concatDiags (list (resultVal t locus) (expectVals fc fields locus) (checkConstruct ctx typeName variant fields locus))))
    ((ty/opRecord schemaName keys values) (concatDiags (list (resultVal t locus) (expectVals fc values locus) (checkRecord ctx schemaName keys values locus))))
    ((ty/opField base _) (listAppend (resultVal t locus) (expectVals fc (list base) locus)))
    ((ty/opVariantField base i) (concatDiags (list (resultVal t locus) (expectVals fc (list base) locus) (if (< i 0) (list (ssaDiag "ERR_IR_ARITY" (str "negative variant field index " i) locus)) (list)))))
    ((ty/opList items) (listAppend (resultVal t locus) (expectVals fc items locus)))
    ((ty/opGlobal name) (listAppend (resultVal t locus) (if (mapHas? ctx.globals name) (list) (list (ssaDiag "ERR_IR_UNKNOWN_GLOBAL" (str "read of undeclared global '" name "'") locus)))))
    ((ty/opLoadGlobal _) (if (= (ty/ssaTyName t) "ptr") (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" "opLoadGlobal result must be ptr" locus))))
    ((ty/opBox v) (listAppend (resultVal t locus) (expectRaw fc v locus)))
    ((ty/opUnbox v) (listAppend (if (classicRawName? (ty/ssaTyName t)) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" "unbox result must be i64, f64 or i1" locus))) (expectVals fc (list v) locus)))
    ((ty/opPrim name args) (checkPrim fc t name args locus)))

fn checkInstr ctx: SsaCtx fc: FnCtx label: String index: Int64 ins: ty/SsaInstr -> (List ty/IrDiag)
  (let [(locus (str fc.name "/" label "/" ins.dest))
        (op ins.op)
        (uses (concatDiags (map (fn [(u String)] -> (List ty/IrDiag) (checkUse fc label index u locus)) (ty/opOperands op))))]
    (listAppend uses (checkOp ctx fc locus ins.ty op)))

fn checkEdge fc: FnCtx label: String index: Int64 e: ty/SsaEdge locus: String -> (List ty/IrDiag)
  (let [(target e.target)
        (args e.args)
        (uses (concatDiags (map (fn [(a String)] -> (List ty/IrDiag) (checkUse fc label index a locus)) args)))]
    (listAppend uses
      (mt (mapGet fc.blocks target)
        ((none) (list (ssaDiag "ERR_IR_MISSING_BLOCK" (str "edge to missing block '" target "'") locus)))
        ((some dest) (cond
                       ((= target fc.entry) (list (ssaDiag "ERR_IR_ENTRY_TARGET" "the entry block cannot be an edge target" locus)))
                       ((!= (listLength args) (listLength dest.params)) (list (ssaDiag "ERR_IR_ARITY" (str "block '" target "' takes " (listLength dest.params) " argument(s), got " (listLength args)) locus)))
                       (else (argTypes fc args dest.params locus)))))))

fn checkCondition fc: FnCtx name: String locus: String -> (List ty/IrDiag)
  (mt (defIndexGet fc.defs name)
    ((none) (list))
    ((some d) (let [(tn (ty/ssaTyName d.ty))]
                (if (or (= tn "val") (= tn "i1")) (list) (list (ssaDiag "ERR_IR_TYPE_MISMATCH" (str "branch condition '" name "' is " tn " where i1 or val is required") locus))))))

fn unknownCases typeName: String variants: (List ty/SsaVariant) names: (List String) locus: String -> (List ty/IrDiag)
  (concatDiags (map (fn [(n String)] -> (List ty/IrDiag)
                      (mt (findVariant variants n)
                        ((some _) (list))
                        ((none) (list (ssaDiag "ERR_IR_UNKNOWN_VARIANT" (str "type '" typeName "' has no variant '" n "'") locus)))))
                    names))

fn checkSwitch ctx: SsaCtx typeName: String cases: (List ty/SsaCase) defaultEdge: (Option ty/SsaEdge) locus: String -> (List ty/IrDiag)
  (mt (mapGet ctx.types typeName)
    ((none) (list (ssaDiag "ERR_IR_UNKNOWN_TYPE" (str "switch over undeclared type '" typeName "'") locus)))
    ((some variants) (let [(names (map (fn [(c ty/SsaCase)] -> String c.variant) cases))
                           (covered (filter (fn [(v ty/SsaVariant)] -> Bool (listContains? names v.name)) variants))
                           (missing (if (and (none? defaultEdge) (< (listLength covered) (listLength variants)))
                                      (list (ssaDiag "ERR_IR_MISSING_DEFAULT" (str "switch over '" typeName "' covers " (listLength covered) " of " (listLength variants) " variants and has no default") locus))
                                      (list)))]
                       (concatDiags (list (unknownCases typeName variants names locus) (duplicateNames "switch case" names (str locus "/")) missing)))))

fn checkTermOwn ctx: SsaCtx fc: FnCtx label: String index: Int64 term: ty/SsaTerm locus: String -> (List ty/IrDiag)
  (mt term
    ((ty/termReturn v) (listAppend (checkUse fc label index v locus) (expectTy fc v fc.retTy locus)))
    ((ty/termJump _) (list))
    ((ty/termBranch c _ _) (listAppend (checkUse fc label index c locus) (checkCondition fc c locus)))
    ((ty/termSwitch s typeName cases d) (concatDiags (list (checkUse fc label index s locus) (expectVals fc (list s) locus) (checkSwitch ctx typeName cases d locus))))
    ((ty/termUnreachable) (list)))

fn checkTerm ctx: SsaCtx fc: FnCtx label: String index: Int64 term: ty/SsaTerm -> (List ty/IrDiag)
  (let [(locus (str fc.name "/" label))
        (edges (concatDiags (map (fn [(e ty/SsaEdge)] -> (List ty/IrDiag) (checkEdge fc label index e locus)) (ty/termEdges term))))]
    (listAppend (checkTermOwn ctx fc label index term locus) edges))

fn verifySsaBlock ctx: SsaCtx fc: FnCtx b: ty/SsaBlock -> (List ty/IrDiag)
  (let [(label b.label)
        (walk (fold (fn [(w InstrWalk) (ins ty/SsaInstr)] -> InstrWalk
                      (InstrWalk :index (+ w.index 1) :diags (listAppend w.diags (checkInstr ctx fc label w.index ins))))
                    (InstrWalk :index 0 :diags (list)) b.instrs))]
    (listAppend walk.diags (checkTerm ctx fc label walk.index b.term)))

fn verifySsaBlocks ctx: SsaCtx f: ty/SsaFunction entryBlock: ty/SsaBlock -> (List ty/IrDiag)
  (let [(name f.name)
        (blocks f.blocks)
        (labels (map (fn [(b ty/SsaBlock)] -> String b.label) blocks))
        (blockMap (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (if (mapHas? acc b.label) acc (mapSet acc b.label b))) (mapEmpty) blocks))
        (entry entryBlock.label)
        (labelDiags (duplicateNames "block" labels (str name "/")))
        (entryDiags (if (listEmpty? entryBlock.params) (list) (list (ssaDiag "ERR_IR_ENTRY_PARAMS" "the entry block cannot have block parameters" (str name "/" entry)))))
        (defState (collectDefs f))
        (succs (successorMap blocks))
        (reach (reachable (list entry) (mapEmpty) succs))
        (preds (predecessorMap succs reach))
        (doms (dominators labels entry preds reach))
        (fc (FnCtx :name name :defs defState.defs :blocks blockMap :entry entry :doms doms :retTy f.retTy))
        (blockDiags (concatDiags (map (fn [(b ty/SsaBlock)] -> (List ty/IrDiag) (verifySsaBlock ctx fc b)) blocks)))]
    (concatDiags (list labelDiags entryDiags defState.diags blockDiags)))

fn verifySsaFunction ctx: SsaCtx f: ty/SsaFunction -> (List ty/IrDiag)
  (mt (listHead f.blocks)
    ((none) (list (ssaDiag "ERR_IR_EMPTY_FUNCTION" (str "function '" f.name "' has no blocks") f.name)))
    ((some entryBlock) (verifySsaBlocks ctx f entryBlock)))

fn declarationDiags ctx: SsaCtx m: ty/SsaModule locus: String -> (List ty/IrDiag)
  (concatDiags (list
    (duplicateNames "function" (listAppend (map (fn [(f ty/SsaFunction)] -> String f.name) m.functions) (map (fn [(e ty/SsaExtern)] -> String e.name) m.externs)) locus)
    (duplicateNames "global" (map (fn [(g ty/SsaGlobal)] -> String g.name) m.globals) locus)
    (duplicateNames "type" (map (fn [(d ty/SsaTypeDecl)] -> String d.name) m.types) locus)
    (duplicateNames "record" (map (fn [(r ty/SsaRecordDecl)] -> String r.name) m.records) locus)
    (concatDiags (map (fn [(d ty/SsaTypeDecl)] -> (List ty/IrDiag) (duplicateNames "variant" (map (fn [(v ty/SsaVariant)] -> String v.name) d.variants) (str locus d.name "/"))) m.types))
    (concatDiags (map (fn [(r ty/SsaRecordDecl)] -> (List ty/IrDiag) (duplicateNames "field" r.fields (str locus r.name "/"))) m.records))
    (concatDiags (map (fn [(g ty/SsaGlobal)] -> (List ty/IrDiag) (checkGlobal ctx locus g)) m.globals))))

fn verifySsaDiags m: ty/SsaModule -> (List ty/IrDiag)
  (let [(ctx (buildCtx m))
        (fnDiags (concatDiags (map (fn [(f ty/SsaFunction)] -> (List ty/IrDiag) (verifySsaFunction ctx f)) m.functions)))]
    (listAppend (declarationDiags ctx m (str m.name "/")) fnDiags))

fn verifySsa m: ty/SsaModule -> (Result Unit (List ty/IrDiag))
  (let [(diags (verifySsaDiags m))]
    (if (listEmpty? diags) (ok ()) (err diags)))
