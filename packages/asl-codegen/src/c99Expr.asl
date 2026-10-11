(module asl-codegen/c99Expr :x [LowerCtx emptyLowerCtx ctxWithVar ctxVarType lowerCExpr lowerCAtom lowerCLet lowerCIf lowerCCond lowerCMatch lowerCCall lowerCFieldAccess lowerCRecordInit lowerCDo wrapBlockWithReturn isC99Keyword? mangleCIdent mangleCTypeName c99TypeStr isIntegerLiteral? isFloatLiteral? inferCType] :i [(reader :a rd)])

(schema LowerCtx (:f vars (List (pair String String))) (:f substs (List (pair String String))) (:f fns (List (pair String String))) (:f retTy String))

fn emptyLowerCtx -> LowerCtx
  (LowerCtx :vars (list) :substs (list) :fns (list) :retTy "")

fn ctxWithVar ctx: LowerCtx name: String cType: String -> LowerCtx
  (with ctx :vars (cons (pair name cType) ctx.vars))

fn ctxWithSubst ctx: LowerCtx name: String cExpr: String -> LowerCtx
  (with ctx :substs (cons (pair name cExpr) ctx.substs))

fn ctxFnRetType ctx: LowerCtx name: String -> (Option String)
  (ctxSubstStep ctx.fns 0 (listLength ctx.fns) name)

fn ctxSubstStep ss: (List (Pair String String)) idx: Int64 len: Int64 name: String -> (Option String)
  (if (>= idx len) (none) (let [(p (optionOr (listGet ss idx) (pair "" "")))] (if (= (pairFirst p) name) (some (pairSecond p)) (ctxSubstStep ss (+ idx 1) len name))))

fn ctxSubst ctx: LowerCtx name: String -> (Option String)
  (ctxSubstStep ctx.substs 0 (listLength ctx.substs) name)

fn ctxVarTypeStep vars: (List (Pair String String)) idx: Int64 len: Int64 name: String -> (Option String)
  (if (>= idx len) (none) (let [(p (optionOr (listGet vars idx) (pair "" "")))] (if (= (pairFirst p) name) (some (pairSecond p)) (ctxVarTypeStep vars (+ idx 1) len name))))

fn ctxVarType ctx: LowerCtx name: String -> (Option String)
  (ctxVarTypeStep ctx.vars 0 (listLength ctx.vars) name)

fn sliceStrOr s: String start: Int64 end: Int64 fallback: String -> String
  (optionOr (stringSlice s start end) fallback)

fn stripModulePrefix s: String -> String
  (if (stringContains? s "/") (mt (stringIndexOf s "/") ((some idx) (sliceStrOr s (+ idx 1) (stringLength s) s)) ((none) s)) s)

fn isC99Keyword? s: String -> Bool
  (let [(kwList (list "auto" "break" "case" "char" "const" "continue" "default" "do" "double" "else" "enum" "extern" "float" "for" "goto" "if" "inline" "int" "long" "register" "restrict" "return" "short" "signed" "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void" "volatile" "while" "_Bool" "_Complex" "_Imaginary" "main" "exit" "abort" "index"))] (listContains? kwList s))

fn isDigitChar? c: String -> Bool
  (and (>= c "0") (<= c "9"))

fn isDigitsOnly? s: String idx: Int64 len: Int64 -> Bool
  (if (>= idx len) true (let [(ch (sliceStrOr s idx (+ idx 1) ""))] (if (isDigitChar? ch) (isDigitsOnly? s (+ idx 1) len) false)))

fn isIntegerLiteral? s: String -> Bool
  (let [(sLen (stringLength s))] (if (<= sLen 0) false (if (stringEndsWith? s "LL") (let [(stemLen (- sLen 2))] (if (<= stemLen 0) false (isIntegerLiteral? (sliceStrOr s 0 stemLen "")))) (if (stringStartsWith? s "-") (if (<= sLen 1) false (isDigitsOnly? s 1 sLen)) (isDigitsOnly? s 0 sLen)))))

fn isFloatLiteral? s: String -> Bool
  (let [(sLen (stringLength s))] (if (or (<= sLen 2) (not (stringContains? s "."))) false (let [(dotIdx (stringIndexOf s "."))] (mt dotIdx ((some idx) (let [(prefix (sliceStrOr s 0 idx "")) (suffix (sliceStrOr s (+ idx 1) sLen "")) (pValid (or (isIntegerLiteral? prefix) (and (stringStartsWith? prefix "-") (isIntegerLiteral? (sliceStrOr prefix 1 (stringLength prefix) ""))))) (sValid (isDigitsOnly? suffix 0 (stringLength suffix)))] (and pValid sValid))) ((none) false)))))

fn capitalizeSeg seg: String -> String
  (let [(segLen (stringLength seg))] (if (<= segLen 0) "" (let [(head (stringUpper (sliceStrOr seg 0 1 ""))) (tail (stringLower (sliceStrOr seg 1 segLen "")))] (str head tail))))

fn pascalIdent s: String -> String
  (if (and (not (stringContains? s "-")) (not (stringContains? s "_"))) (if (and (> (stringLength s) 0) (= (stringUpper (sliceStrOr s 0 1 "")) (sliceStrOr s 0 1 ""))) s (capitalizeSeg s)) (let [(norm (stringReplace s "_" "-")) (segs (stringSplit norm "-")) (caps (map capitalizeSeg segs))] (stringJoin caps "")))

fn mangleCTypeName s: String -> String
  (let [(clean (if (stringStartsWith? s ":") (sliceStrOr s 1 (stringLength s) "") s))] (cond ((or (= clean "Int64") (= clean "I64")) "int64_t") ((or (= clean "Int32") (= clean "I32")) "int32_t") ((or (= clean "Float64") (= clean "F64")) "double") ((or (= clean "Float32") (= clean "F32")) "float") ((= clean "Bool") "bool") ((or (= clean "Unit") (= clean "void")) "void") ((or (= clean "String") (= clean "Str")) "asl_string_t") (else (let [(p (pascalIdent clean))] (if (stringStartsWith? p "Asl") p (str "Asl" p))))))

fn c99TypeStr s: String -> String
  (mangleCTypeName s)

fn mangleCIdent s: String -> String
  (let [(sLen (stringLength s))] (if (<= sLen 0) "" (let [(base1 (if (and (> sLen 1) (stringEndsWith? s "?")) (let [(stem (sliceStrOr s 0 (- sLen 1) ""))] (if (stringStartsWith? stem "is-") (str "is_" (sliceStrOr stem 3 (stringLength stem) "")) (str "is_" stem))) s)) (len1 (stringLength base1)) (base2 (if (and (> len1 1) (stringEndsWith? base1 "!")) (str (sliceStrOr base1 0 (- len1 1) "") "_mut") base1)) (snaked (stringReplace (stringReplace base2 "-" "_") "/" "_"))] (if (isC99Keyword? snaked) (str "asl_" snaked) snaked))))

fn getAtomStr e: rd/SExpr -> String
  (mt e ((rd/sexprAtom v) v) ((rd/sexprList _) "") ((rd/sexprVect _) ""))

fn nthAtom items: (List rd/SExpr) idx: Int64 -> String
  (getAtomStr (optionOr (listGet items idx) (rd/sexprAtom "")))

fn sliceFrom1 items: (List T) -> (List T)
  (if (> (listLength items) 1) (optionOr (listSlice items 1 (listLength items)) (list)) (list))

fn sliceTail items: (List rd/SExpr) start: Int64 -> (List rd/SExpr)
  (if (> (listLength items) start) (optionOr (listSlice items start (listLength items)) (list)) (list))

fn lowerCAtom s: String -> String
  (cond ((= s "true") "true") ((= s "false") "false") ((or (= s "nil") (= s "()")) "(void)0") ((stringStartsWith? s "\"") (let [(sLen (stringLength s)) (contentLen (if (>= sLen 2) (- sLen 2) 0))] (str "(asl_string_t){ .data = " s ", .len = " (stringFromInt64 contentLen) " }"))) ((isIntegerLiteral? s) (if (stringEndsWith? s "LL") s (str s "LL"))) ((isFloatLiteral? s) s) (else (mangleCIdent s)))

fn isBinaryOp? op: String -> Bool
  (let [(ops (list "+" "-" "*" "/" "%" "&" "|" "^" "<<" ">>" "=" "!=" "<" "<=" ">" ">=" "and" "or"))] (listContains? ops op))

fn opToC op: String -> String
  (cond ((= op "=") "==") ((= op "!=") "!=") ((= op "<") "<") ((= op "<=") "<=") ((= op ">") ">") ((= op ">=") ">=") ((= op "and") "&&") ((= op "or") "||") (else op))

fn lowerCFieldAccess target: String field: String -> String
  (let [(clean (if (stringStartsWith? field ".-") (sliceStrOr field 2 (stringLength field) "") (if (stringStartsWith? field ".") (sliceStrOr field 1 (stringLength field) "") field)))] (str target "." (mangleCIdent clean)))

fn lowerCRecordField ctx: LowerCtx items: (List rd/SExpr) idx: Int64 -> String
  (let [(kPos (+ 1 (* idx 2))) (vPos (+ 2 (* idx 2))) (kAtom (nthAtom items kPos)) (kClean (if (stringStartsWith? kAtom ":") (sliceStrOr kAtom 1 (stringLength kAtom) kAtom) kAtom)) (vNode (optionOr (listGet items vPos) (rd/sexprAtom "()"))) (vVal (lowerCExpr ctx vNode))] (str "." (mangleCIdent kClean) " = " vVal))

fn lowerCRecordFieldsStep ctx: LowerCtx items: (List rd/SExpr) idx: Int64 numPairs: Int64 acc: (List String) -> (List String)
  (if (>= idx numPairs) acc (lowerCRecordFieldsStep ctx items (+ idx 1) numPairs (listAppend acc (list (lowerCRecordField ctx items idx)))))

fn lowerCRecordInit ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(rawName (nthAtom items 0)) (recName (stripModulePrefix rawName)) (recType (mangleCTypeName recName)) (itemsLen (listLength items))] (if (<= itemsLen 1) (str "(" recType "){ 0 }") (let [(numPairs (/ (- itemsLen 1) 2)) (fieldStrs (lowerCRecordFieldsStep ctx items 0 numPairs (list)))] (str "(" recType "){ " (stringJoin fieldStrs ", ") " }"))))

fn isNonEmptyStr? s: String -> Bool
  (> (stringLength s) 0)

fn wrapBlockWithReturn s: String -> String
  (let [(t (stringTrim s))] (if (and (stringStartsWith? t "{") (stringEndsWith? t "}")) (if (or (stringStartsWith? t "{ return") (or (stringContains? t "switch") (or (stringContains? t "abort") (stringContains? t "return")))) t (let [(inner (stringTrim (sliceStrOr t 1 (- (stringLength t) 1) "")))] (let [(parts (stringSplit inner ";")) (pCount (listLength parts))] (if (<= pCount 1) (if (stringEmpty? inner) "{ return; }" (if (or (stringStartsWith? inner "return") (or (stringStartsWith? inner "switch") (or (stringStartsWith? inner "abort") (or (stringStartsWith? inner "if") (or (stringStartsWith? inner "{") (or (stringStartsWith? inner "}") (stringEndsWith? inner "}"))))))) (str "{ " inner "; }") (str "{ return " inner "; }"))) (let [(nonEmpty (filter isNonEmptyStr? (map stringTrim parts))) (nLen (listLength nonEmpty))] (if (<= nLen 0) "{ return; }" (if (= nLen 1) (let [(s0 (optionOr (listGet nonEmpty 0) ""))] (if (or (stringStartsWith? s0 "return") (or (stringStartsWith? s0 "switch") (or (stringStartsWith? s0 "abort") (or (stringStartsWith? s0 "if") (or (stringStartsWith? s0 "{") (or (stringStartsWith? s0 "}") (stringEndsWith? s0 "}"))))))) (str "{ " s0 "; }") (str "{ return " s0 "; }"))) (let [(inits (optionOr (listSlice nonEmpty 0 (- nLen 1)) (list))) (lastS (optionOr (listGet nonEmpty (- nLen 1)) "")) (retLast (if (or (stringStartsWith? lastS "return") (or (stringStartsWith? lastS "switch") (or (stringStartsWith? lastS "abort") (or (stringStartsWith? lastS "if") (or (stringStartsWith? lastS "{") (or (stringStartsWith? lastS "}") (stringEndsWith? lastS "}"))))))) lastS (str "return " lastS)))] (str "{ " (stringJoin inits "; ") "; " retLast "; }"))))))))) (if (or (stringStartsWith? t "return") (or (stringStartsWith? t "switch") (or (stringStartsWith? t "abort") (or (stringStartsWith? t "if") (or (stringStartsWith? t "{") (or (stringStartsWith? t "}") (stringEndsWith? t "}"))))))) t (str "return " t ";"))))

fn lowerCIf ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(condExpr (lowerCExpr ctx (optionOr (listGet items 1) (rd/sexprAtom "false")))) (rawThen (lowerCExpr ctx (optionOr (listGet items 2) (rd/sexprAtom "(void)0")))) (rawElse (if (> (listLength items) 3) (lowerCExpr ctx (optionOr (listGet items 3) (rd/sexprAtom "(void)0"))) "(void)0")) (tTrim (stringTrim rawThen)) (eTrim (stringTrim rawElse)) (thenIsBlock (stringStartsWith? tTrim "{")) (elseIsBlock (stringStartsWith? eTrim "{")) (thenHasFlow (or thenIsBlock (or (stringContains? rawThen "return ") (stringContains? rawThen "switch")))) (elseHasFlow (or elseIsBlock (or (stringContains? rawElse "return ") (stringContains? rawElse "switch"))))] (if (or thenHasFlow elseHasFlow) (let [(tStmt (wrapBlockWithReturn rawThen)) (eStmt (wrapBlockWithReturn rawElse))] (let [(tFinal (if (stringStartsWith? tStmt "{") tStmt (str "{ " tStmt " }"))) (eFinal (if (stringStartsWith? eStmt "{") eStmt (str "{ " eStmt " }")))] (str "if (" condExpr ") " tFinal " else " eFinal))) (str "((" condExpr ") ? (" rawThen ") : (" rawElse "))")))

fn lowerCCondClause ctx: LowerCtx clause: rd/SExpr -> (Pair String String)
  (let [(cList (rd/sexprToList clause))] (if (<= (listLength cList) 0) (pair "false" "(void)0") (let [(head (nthAtom cList 0)) (isElse (or (= head ":else") (= head "else")))] (if isElse (let [(bVal (lowerCExpr ctx (optionOr (listGet cList 1) (rd/sexprAtom "(void)0"))))] (pair ":else" bVal)) (let [(cVal (lowerCExpr ctx (optionOr (listGet cList 0) (rd/sexprAtom "false")))) (bVal (lowerCExpr ctx (optionOr (listGet cList 1) (rd/sexprAtom "(void)0"))))] (pair cVal bVal))))))

fn hasCondFlow? ctx: LowerCtx clauses: (List rd/SExpr) idx: Int64 -> Bool
  (if (>= idx (listLength clauses)) false (let [(cNode (optionOr (listGet clauses idx) (rd/sexprAtom "()"))) (p (lowerCCondClause ctx cNode)) (rawBody (pairSecond p))] (if (or (stringStartsWith? rawBody "return") (or (stringStartsWith? rawBody "switch") (stringStartsWith? rawBody "{"))) true (hasCondFlow? ctx clauses (+ idx 1)))))

fn lowerCCondStmtLoop ctx: LowerCtx clauses: (List rd/SExpr) idx: Int64 -> String
  (if (>= idx (listLength clauses)) "" (let [(cNode (optionOr (listGet clauses idx) (rd/sexprAtom "()"))) (p (lowerCCondClause ctx cNode)) (cCond (pairFirst p)) (rawBody (pairSecond p)) (stmt (wrapBlockWithReturn rawBody))] (let [(wrapped (if (stringStartsWith? stmt "{") stmt (str "{ " stmt " }")))] (if (= cCond ":else") (str "else " wrapped " ") (if (= idx 0) (str "if (" cCond ") " wrapped " " (lowerCCondStmtLoop ctx clauses (+ idx 1))) (str "else if (" cCond ") " wrapped " " (lowerCCondStmtLoop ctx clauses (+ idx 1))))))))

fn lowerCCondExprLoop ctx: LowerCtx clauses: (List rd/SExpr) idx: Int64 -> String
  (if (>= idx (listLength clauses)) "(void)0" (let [(cNode (optionOr (listGet clauses idx) (rd/sexprAtom "()"))) (p (lowerCCondClause ctx cNode)) (cCond (pairFirst p)) (rawBody (pairSecond p))] (if (= cCond ":else") rawBody (let [(restExpr (lowerCCondExprLoop ctx clauses (+ idx 1)))] (str "((" cCond ") ? (" rawBody ") : (" restExpr "))")))))

fn lowerCCond ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(clauses (sliceFrom1 items))] (if (hasCondFlow? ctx clauses 0) (lowerCCondStmtLoop ctx clauses 0) (lowerCCondExprLoop ctx clauses 0)))

fn inferCTypeOfExpr ctx: LowerCtx e: rd/SExpr valExpr: String -> String
  (mt e ((rd/sexprVect _) "") ((rd/sexprAtom v) (cond ((isIntegerLiteral? v) "int64_t") ((isFloatLiteral? v) "double") ((or (= v "true") (= v "false")) "bool") ((stringStartsWith? v "\"") "asl_string_t") (else (mt (ctxVarType ctx v) ((some t) t) ((none) ""))))) ((rd/sexprList items) (if (<= (listLength items) 0) "" (let [(head (stripModulePrefix (nthAtom items 0)))] (if (= head "str") "asl_string_t" (mt (ctxFnRetType ctx head) ((some t) t) ((none) "")))))))

fn inferCType ctx: LowerCtx e: rd/SExpr valExpr: String -> String
  (let [(declared (inferCTypeOfExpr ctx e valExpr))] (if (not (= declared "")) declared (cond ((and (stringEndsWith? valExpr "LL") (not (stringContains? valExpr "("))) "int64_t") ((or (= valExpr "true") (= valExpr "false")) "bool") (else "__auto_type"))))

fn typeNodeToStr e: rd/SExpr -> String
  (mt e ((rd/sexprAtom v) (mangleCTypeName v)) ((rd/sexprList items) (if (<= (listLength items) 0) "void" (let [(head (nthAtom items 0))] (cond ((= head "List") (let [(elem (if (> (listLength items) 1) (typeNodeToStr (optionOr (listGet items 1) (rd/sexprAtom ""))) "asl_string_t"))] (str "AslSlice_" elem))) ((= head "Option") (let [(inner (if (> (listLength items) 1) (typeNodeToStr (optionOr (listGet items 1) (rd/sexprAtom ""))) "void"))] (str "AslOption_" inner))) ((= head "Pair") (let [(t1 (if (> (listLength items) 1) (typeNodeToStr (optionOr (listGet items 1) (rd/sexprAtom ""))) "asl_string_t")) (t2 (if (> (listLength items) 2) (typeNodeToStr (optionOr (listGet items 2) (rd/sexprAtom ""))) "asl_string_t"))] (str "AslPair_" t1 "_" t2))) ((= head "Map") (let [(t1 (if (> (listLength items) 1) (typeNodeToStr (optionOr (listGet items 1) (rd/sexprAtom ""))) "asl_string_t")) (t2 (if (> (listLength items) 2) (typeNodeToStr (optionOr (listGet items 2) (rd/sexprAtom ""))) "asl_string_t"))] (str "AslMap_" t1 "_" t2))) ((= head "Result") (let [(t1 (if (> (listLength items) 1) (typeNodeToStr (optionOr (listGet items 1) (rd/sexprAtom ""))) "void")) (t2 (if (> (listLength items) 2) (typeNodeToStr (optionOr (listGet items 2) (rd/sexprAtom ""))) "asl_string_t"))] (str "AslResult_" t1 "_" t2))) (else (mangleCTypeName head)))))) ((rd/sexprVect _) ""))

fn ctxWithBindingsStep ctx: LowerCtx bs: (List rd/SExpr) idx: Int64 len: Int64 -> LowerCtx
  (if (>= idx len) ctx (let [(b (optionOr (listGet bs idx) (rd/sexprAtom "()"))) (pair (rd/sexprToList b)) (pLen (listLength pair))] (if (>= pLen 3) (let [(rawName (nthAtom pair 0)) (ty (typeNodeToStr (optionOr (listGet pair 1) (rd/sexprAtom ""))))] (ctxWithBindingsStep (ctxWithVar ctx rawName ty) bs (+ idx 1) len)) (if (= pLen 2) (let [(rawName (nthAtom pair 0)) (valNode (optionOr (listGet pair 1) (rd/sexprAtom "()"))) (ty (inferCType ctx valNode (lowerCExpr ctx valNode)))] (if (!= ty "__auto_type") (ctxWithBindingsStep (ctxWithVar ctx rawName ty) bs (+ idx 1) len) (ctxWithBindingsStep ctx bs (+ idx 1) len))) (ctxWithBindingsStep ctx bs (+ idx 1) len)))))

fn lowerCLetBinding ctx: LowerCtx b: rd/SExpr -> String
  (let [(pair (rd/sexprToList b)) (pairLen (listLength pair))] (cond ((>= pairLen 3) (let [(vName (mangleCIdent (nthAtom pair 0))) (vType (typeNodeToStr (optionOr (listGet pair 1) (rd/sexprAtom "")))) (vVal (lowerCExpr ctx (optionOr (listGet pair 2) (rd/sexprAtom "()"))))] (if (= vType "void") (str vVal ";") (if (stringStartsWith? vVal "switch") (str vType " " vName "; " (stringReplace vVal "return " (str vName " = "))) (str vType " " vName " = " vVal ";"))))) ((= pairLen 2) (let [(rawName (nthAtom pair 0)) (vName (mangleCIdent rawName)) (vVal (lowerCExpr ctx (optionOr (listGet pair 1) (rd/sexprAtom "()")))) (vType (inferCType ctx (optionOr (listGet pair 1) (rd/sexprAtom "()")) vVal))] (if (or (stringStartsWith? rawName "unused") (or (stringStartsWith? vVal "println(") (or (stringStartsWith? vVal "eprintln(") (or (stringStartsWith? vVal "print(") (stringStartsWith? vVal "eprint("))))) (str vVal ";") (if (stringStartsWith? vVal "switch") (str vType " " vName "; " (stringReplace vVal "return " (str vName " = "))) (str vType " " vName " = " vVal ";"))))) (else "")))

fn isBlockStmt? s: String -> Bool
  (and (stringEndsWith? s "}") (or (stringStartsWith? s "{") (stringStartsWith? s "switch")))

fn lowerCLetBodyStmt ctx: LowerCtx e: rd/SExpr -> String
  (let [(s (lowerCExpr ctx e))] (if (or (stringEndsWith? s ";") (isBlockStmt? s)) s (str s ";")))

fn lowerCLet ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(bindingsNode (optionOr (listGet items 1) (rd/sexprVect (list)))) (bodyNodes (sliceTail items 2)) (bindList (rd/sexprToList bindingsNode)) (bodyCtx (ctxWithBindingsStep ctx bindList 0 (listLength bindList))) (decls (lowerCLetBindingsStep ctx bindList 0 (listLength bindList) (list))) (validDecls (filter isNonEmptyStr? decls)) (bodyLen (listLength bodyNodes))] (if (<= bodyLen 0) (str "{ " (stringJoin validDecls " ") " }") (let [(bodyStmts (lowerCLetBodyStmtsStep bodyCtx bodyNodes 0 (listLength bodyNodes) (list)))] (str "{ " (stringJoin validDecls " ") " " (stringJoin bodyStmts " ") " }"))))

fn anyTrue? bools: (List Bool) -> Bool
  (if (<= (listLength bools) 0) false (if (optionOr (listGet bools 0) false) true (anyTrue? (sliceFrom1 bools))))

fn constructorFieldName ctor: String idx: Int64 -> String
  (let [(c (stripModulePrefix ctor))] (cond ((or (= c "topModule") (or (= c "topSchema") (or (= c "topEnum") (= c "topDefun")))) (if (= idx 0) "node" "")) ((= c "fEval") (if (= idx 0) "expr" "")) ((= c "fTryInner") (if (= idx 0) "valVar" "")) ((= c "fIfCond") (if (= idx 0) "thenE" (if (= idx 1) "elseE" (if (= idx 2) "env" "")))) ((= c "fIfThen") (if (= idx 0) "elseE" (if (= idx 1) "thenTy" (if (= idx 2) "env" "")))) ((= c "fLetVal") (if (= idx 0) "bname" (if (= idx 1) "bindingsRest" (if (= idx 2) "tailExprs" (if (= idx 3) "env" ""))))) ((= c "fCall") (if (= idx 0) "calleeName" (if (= idx 1) "calleeTy" (if (= idx 2) "argsDone" (if (= idx 3) "argsPending" (if (= idx 4) "env" "")))))) ((= c "sexprAtom") (if (= idx 0) "val" "")) ((or (= c "sexprList") (= c "sexprVect")) (if (= idx 0) "items" "")) ((= c "stepContinue") (if (= idx 0) "mode" "")) ((or (= c "valInt") (or (= c "valFloat") (or (= c "valStr") (= c "valBool")))) (if (= idx 0) "v" "")) ((= c "valError") (if (= idx 0) "msg" "")) ((or (= c "valList") (= c "valVect")) (if (= idx 0) "items" "")) ((= c "valMap") (if (= idx 0) "entries" "")) ((= c "valClosure") (if (= idx 0) "name" (if (= idx 1) "params" (if (= idx 2) "body" (if (= idx 3) "env" ""))))) ((= c "tyCon") (if (= idx 0) "name" (if (= idx 1) "args" (if (= idx 2) "mod" (if (= idx 3) "shown" ""))))) ((= c "tyVar") (if (= idx 0) "id" (if (= idx 1) "kind" ""))) ((= c "tyFun") (if (= idx 0) "params" (if (= idx 1) "ret" ""))) ((= c "uOk") (if (= idx 0) "subst" "")) ((= c "uErr") (if (= idx 0) "msg" (if (= idx 1) "numeric" ""))) ((= c "argPos") (if (= idx 0) "val" "")) ((= c "argKw") (if (= idx 0) "key" (if (= idx 1) "val" ""))) ((= c "tokSymbol") (if (= idx 0) "name" "")) ((= c "tokKeyword") (if (= idx 0) "key" "")) ((= c "tokString") (if (= idx 0) "val" "")) ((= c "tokInt") (if (= idx 0) "n" "")) ((= c "tokFloat") (if (= idx 0) "f" "")) ((= c "tokError") (if (= idx 0) "msg" "")) (else "")))

fn isUnitExpr? e: rd/SExpr -> Bool
  (mt e ((rd/sexprAtom v) (or (= v "()") (= v "(void)0"))) ((rd/sexprList items) (<= (listLength items) 0)) ((rd/sexprVect items) false))

fn payloadAccessor subj: String pHead: String idx: Int64 -> String
  (let [(mHead (mangleCIdent (stripModulePrefix pHead))) (fld (constructorFieldName pHead idx))] (if (stringEmpty? fld) (str "((" subj ").data." mHead ")") (str "((" subj ").data." mHead "." fld ")")))

fn payloadSubstCtx ctx: LowerCtx subj: String pHead: String pItems: (List rd/SExpr) idx: Int64 len: Int64 -> LowerCtx
  (if (>= idx len) ctx (let [(rawName (nthAtom pItems (+ idx 1)))] (if (or (= rawName "_") (= rawName "")) (payloadSubstCtx ctx subj pHead pItems (+ idx 1) len) (payloadSubstCtx (ctxWithSubst ctx rawName (payloadAccessor subj pHead idx)) subj pHead pItems (+ idx 1) len))))

fn lowerCMatchArmStmts bodyStmts: (List String) -> String
  (let [(cnt (listLength bodyStmts))] (cond ((<= cnt 0) "") ((= cnt 1) (let [(s (optionOr (listGet bodyStmts 0) ""))] (if (or (stringStartsWith? s "return") (or (stringStartsWith? s "switch") (or (stringStartsWith? s "abort") (stringStartsWith? s "{")))) (str (wrapBlockWithReturn s) " ") (str "return " s " ")))) (else (let [(initStmts (optionOr (listSlice bodyStmts 0 (- cnt 1)) (list))) (lastS (optionOr (listGet bodyStmts (- cnt 1)) "")) (retLast (if (or (stringStartsWith? lastS "return") (or (stringStartsWith? lastS "switch") (or (stringStartsWith? lastS "abort") (stringStartsWith? lastS "{")))) (wrapBlockWithReturn lastS) (str "return " lastS)))] (str (stringJoin initStmts " ") " " retLast " ")))))

fn lowerCMatchArm ctx: LowerCtx arm: rd/SExpr subj: String -> String
  (mt arm ((rd/sexprList aItems) (if (<= (listLength aItems) 0) "" (let [(patNode (optionOr (listGet aItems 0) (rd/sexprAtom "_"))) (bodyTail (sliceFrom1 aItems))] (mt patNode ((rd/sexprAtom v) (let [(bodyStr (lowerCMatchArmStmts (lowerCLetBodyStmtsStep ctx bodyTail 0 (listLength bodyTail) (list))))] (if (or (= v "_") (= v ":else") (= v "else")) (str "default: { " bodyStr "break; }") (str "case " (caseTagConst v) ": { " bodyStr "break; }")))) ((rd/sexprList pItems) (let [(pHead (nthAtom pItems 0)) (tag (caseTagConst pHead)) (argCount (- (listLength pItems) 1)) (armCtx (payloadSubstCtx ctx subj pHead pItems 0 argCount)) (bodyStr (lowerCMatchArmStmts (lowerCLetBodyStmtsStep armCtx bodyTail 0 (listLength bodyTail) (list))))] (str "case " tag ": { " bodyStr "break; }"))) ((rd/sexprVect _) ""))))) ((rd/sexprVect aItems) (lowerCMatchArm ctx (rd/sexprList aItems) subj)) ((rd/sexprAtom _) ""))

fn isDefaultArm? s: String -> Bool
  (stringStartsWith? s "default:")

fn lowerCMatchArmsStep ctx: LowerCtx arms: (List rd/SExpr) subj: String idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(armStr (lowerCMatchArm ctx (optionOr (listGet arms idx) (rd/sexprAtom "")) subj))] (lowerCMatchArmsStep ctx arms subj (+ idx 1) len (listAppend acc (list armStr)))))

fn lowerCMatch ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(subj (lowerCExpr ctx (optionOr (listGet items 1) (rd/sexprAtom "val")))) (arms (sliceTail items 2)) (armStrs (lowerCMatchArmsStep ctx arms subj 0 (listLength arms) (list))) (validArms (filter isNonEmptyStr? armStrs)) (hasDefault (anyTrue? (map isDefaultArm? validArms))) (defaultGuard (if hasDefault "" "default: { abort(); break; }")) (allClauses (if (> (stringLength defaultGuard) 0) (listAppend validArms (list defaultGuard)) validArms))] (str "switch ((int)((" subj ").tag)) { " (stringJoin allClauses " ") " }"))

fn isStringExpr? e: rd/SExpr -> Bool
  (mt e ((rd/sexprAtom v) (or (stringStartsWith? v "\"") (or (stringStartsWith? v ".-") (or (= v "s") (or (= v "str") (or (= v "name") (or (= v "fnName") (or (= v "targetFn") (or (= v "p") (or (= v "path") (or (= v "msg") (or (= v "line") (or (= v "op") (or (= v "atomStr") (or (= v "as") (or (= v "bs") (or (= v "entryFile") (or (= v "retTy") (= v "typeName"))))))))))))))))))) ((rd/sexprList items) (let [(h (nthAtom items 0))] (or (= h "str") (or (= h "stringReplace") (or (= h "stringJoin") (or (= h "sliceStrOr") (or (= h "sliceOr") (or (= h "stringTrim") (or (= h "stringUpper") (or (= h "stringLower") (or (= h "int-to-string") (or (= h "stringFromInt64") (or (= h "mangleCIdent") (or (stringEndsWith? h "sexprHead") (stringEndsWith? h "Head"))))))))))))))) ((rd/sexprVect _) false))

fn foldBinaryOpStep ctx: LowerCtx cOp: String restArgs: (List rd/SExpr) idx: Int64 len: Int64 acc: String -> String
  (if (>= idx len) acc (let [(argNode (optionOr (listGet restArgs idx) (rd/sexprAtom "0LL"))) (nextAcc (str "((" acc ") " cOp " (" (lowerCExpr ctx argNode) "))"))] (foldBinaryOpStep ctx cOp restArgs (+ idx 1) len nextAcc)))

fn protectMacroArg s: String -> String
  (if (stringContains? s "{") (str "(" s ")") s)

fn caseTagConst patHead: String -> String
  (str "ASL_TAG_" (stringUpper (stringReplace (stripModulePrefix patHead) "-" "_")))

fn lowerCExprsStep ctx: LowerCtx es: (List rd/SExpr) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(e (optionOr (listGet es idx) (rd/sexprAtom "()")))] (lowerCExprsStep ctx es (+ idx 1) len (listAppend acc (list (lowerCExpr ctx e))))))

fn lowerCLetBindingsStep ctx: LowerCtx bs: (List rd/SExpr) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(b (optionOr (listGet bs idx) (rd/sexprAtom "()")))] (lowerCLetBindingsStep ctx bs (+ idx 1) len (listAppend acc (list (lowerCLetBinding ctx b))))))

fn lowerCLetBodyStmtsStep ctx: LowerCtx es: (List rd/SExpr) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(e (optionOr (listGet es idx) (rd/sexprAtom "()")))] (lowerCLetBodyStmtsStep ctx es (+ idx 1) len (listAppend acc (list (lowerCLetBodyStmt ctx e))))))

fn lowerCStrConcat ctx: LowerCtx args: (List rd/SExpr) idx: Int64 len: Int64 -> String
  (if (>= idx len) "((asl_string_t){ .data = \"\", .len = 0 })" (let [(here (lowerCExpr ctx (optionOr (listGet args idx) (rd/sexprAtom "\"\""))))] (if (= idx (- len 1)) here (str "string_concat2(" here ", " (lowerCStrConcat ctx args (+ idx 1) len) ")"))))

fn argCType ctx: LowerCtx e: rd/SExpr -> (Option String)
  (mt e ((rd/sexprAtom v) (ctxVarType ctx v)) ((rd/sexprList _) (none)) ((rd/sexprVect _) (none)))

fn typedAccessorCall ctx: LowerCtx head: String rawArgs: (List rd/SExpr) -> String
  (let [(bare (stripModulePrefix head)) (a0 (optionOr (listGet rawArgs 0) (rd/sexprAtom "()"))) (retTy ctx.retTy) (tyOpt (argCType ctx a0))] (if (and (stringStartsWith? retTy "AslResult_") (and (or (= bare "ok") (= bare "err")) (> (listLength rawArgs) 0))) (str "asl_" bare "_" retTy "(" (lowerCExpr ctx a0) ")") (mt tyOpt ((none) "") ((some cTy) (let [(isSlice (stringStartsWith? cTy "AslSlice_")) (isOpt (stringStartsWith? cTy "AslOption_")) (s0 (lowerCExpr ctx a0))] (cond ((and isSlice (= bare "listGet")) (str "asl_list_get_" cTy "(" s0 ", " (lowerCExpr ctx (optionOr (listGet rawArgs 1) (rd/sexprAtom "0"))) ")")) ((and isSlice (= bare "listHead")) (str "asl_list_head_" cTy "(" s0 ")")) ((and isSlice (= bare "listTail")) (str "asl_list_tail_" cTy "(" s0 ")")) ((and isOpt (= bare "optionOr")) (str "asl_option_or_" cTy "(" s0 ", " (lowerCExpr ctx (optionOr (listGet rawArgs 1) (rd/sexprAtom "()"))) ")")) (else "")))))))

fn lowerCCall ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(head (nthAtom items 0)) (rawArgs (sliceFrom1 items))] (cond ((stringStartsWith? head ".-") (let [(field (sliceStrOr head 2 (stringLength head) "")) (target (if (> (listLength rawArgs) 0) (lowerCExpr ctx (optionOr (listGet rawArgs 0) (rd/sexprAtom "()"))) "()"))] (lowerCFieldAccess target field))) ((= head "not") (let [(arg (if (> (listLength rawArgs) 0) (lowerCExpr ctx (optionOr (listGet rawArgs 0) (rd/sexprAtom "false"))) "false"))] (str "(!(" arg "))"))) ((= head "str") (lowerCStrConcat ctx rawArgs 0 (listLength rawArgs))) ((isBinaryOp? head) (let [(argCount (listLength rawArgs)) (cOp (opToC head))] (cond ((= argCount 1) (let [(a0 (lowerCExpr ctx (optionOr (listGet rawArgs 0) (rd/sexprAtom "0LL"))))] (str "(-(" a0 "))"))) ((>= argCount 2) (let [(raw0 (optionOr (listGet rawArgs 0) (rd/sexprAtom "0LL"))) (raw1 (optionOr (listGet rawArgs 1) (rd/sexprAtom "0LL"))) (firstArg (lowerCExpr ctx raw0)) (secondArg (lowerCExpr ctx raw1)) (isStr (or (stringContains? firstArg "asl_string_") (or (stringContains? secondArg "asl_string_") (or (isStringExpr? raw0) (isStringExpr? raw1)))))] (if (and isStr (or (= head "=") (= head "!="))) (if (= head "=") (str "asl_string_eq(" firstArg ", " secondArg ")") (str "(!asl_string_eq(" firstArg ", " secondArg "))")) (let [(restArgs (sliceFrom1 rawArgs))] (foldBinaryOpStep ctx cOp restArgs 0 (listLength restArgs) firstArg))))) (else "")))) ((and (> (stringLength head) 0) (stringStartsWith? head ":")) (lowerCRecordInit ctx items)) ((and (> (stringLength (stripModulePrefix head)) 0) (let [(c0 (sliceStrOr (stripModulePrefix head) 0 1 ""))] (and (>= c0 "A") (<= c0 "Z"))) (> (listLength items) 1) (stringStartsWith? (nthAtom items 1) ":")) (lowerCRecordInit ctx items)) ((and (= (stripModulePrefix head) "ok") (or (<= (listLength rawArgs) 0) (or (= (nthAtom rawArgs 0) "()") (isUnitExpr? (optionOr (listGet rawArgs 0) (rd/sexprAtom "")))))) (if (and (> (stringLength ctx.retTy) 0) (stringStartsWith? ctx.retTy "AslResult_")) (str "asl_ok_" ctx.retTy "()") "okUnit()")) ((not (= "" (typedAccessorCall ctx head rawArgs))) (typedAccessorCall ctx head rawArgs)) (else (let [(fnName (mangleCIdent (stripModulePrefix head))) (rawArgStrs (lowerCExprsStep ctx rawArgs 0 (listLength rawArgs) (list))) (args (map protectMacroArg rawArgStrs))] (str fnName "(" (stringJoin args ", ") ")")))))

fn lowerCDo ctx: LowerCtx items: (List rd/SExpr) -> String
  (let [(stmts (sliceFrom1 items)) (stmtCount (listLength stmts))] (cond ((<= stmtCount 0) "(void)0") ((= stmtCount 1) (lowerCExpr ctx (optionOr (listGet stmts 0) (rd/sexprAtom "()")))) (else (let [(exprs (lowerCExprsStep ctx stmts 0 (listLength stmts) (list)))] (str "(" (stringJoin exprs ", ") ")")))))

fn lowerCExpr ctx: LowerCtx e: rd/SExpr -> String
  (mt e ((rd/sexprAtom v) (mt (ctxSubst ctx v) ((some cExpr) cExpr) ((none) (lowerCAtom v)))) ((rd/sexprVect items) (str "{" (stringJoin (lowerCExprsStep ctx items 0 (listLength items) (list)) ", ") "}")) ((rd/sexprList items) (if (<= (listLength items) 0) "(void)0" (let [(head (nthAtom items 0))] (cond ((= head "fn") "(void*)0") ((= head "let") (lowerCLet ctx items)) ((= head "if") (lowerCIf ctx items)) ((= head "cond") (lowerCCond ctx items)) ((or (= head "match") (= head "mt")) (lowerCMatch ctx items)) ((= head "do") (lowerCDo ctx items)) (else (lowerCCall ctx items)))))))
