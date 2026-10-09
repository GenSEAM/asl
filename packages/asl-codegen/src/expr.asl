(module asl-codegen/expr :x [emitExpr emitAtom emitPattern emitBodySeq isIdent? cloneIfIdent resolveQualifiedCase sliceStrOr] :i [(reader :a rd) (mangle :a m) (builtins :a b) (rtypes :a cgTy)])

fn sliceStrOr s: String start: Int64 end: Int64 fallback: String -> String
  (optionOr (stringSlice s start end) fallback)

fn isIdent? s: String -> Bool
  (let [(sLen (stringLength s))] (if (<= sLen 0) false (let [(c0 (sliceStrOr s 0 1 ""))] (and (not (stringContains? s " ")) (and (not (stringContains? s "(")) (and (not (stringContains? s "{")) (and (not (stringContains? s "[")) (and (not (stringContains? s "\"")) (and (not (stringContains? s ".")) (and (not (stringContains? s "::")) (or (and (>= c0 "a") (<= c0 "z")) (or (and (>= c0 "A") (<= c0 "Z")) (= c0 "_")))))))))))))

fn cloneIfIdent s: String -> String
  (if (isIdent? s) (str s ".clone()") s)

fn caseCall tgt: String args: (List String) -> String
  (if (> (listLength args) 0) (str tgt "(" (stringJoin args ", ") ")") tgt)

fn formatCall fnName: String args: (List String) -> String
  (str fnName "(" (stringJoin args ", ") ")")

fn escapeRawString s: String -> String
  (let [(s1 (stringReplace s "\n" "\\n")) (s2 (stringReplace s1 "\r" "\\r")) (s3 (stringReplace s2 "\t" "\\t"))] s3)

fn resolveEnumAlias v: String aliases: (Map String String) -> String
  (mt (mapGet aliases v) ((some tgt) (if (or (stringStartsWith? tgt "crate::") (stringContains? tgt "::")) tgt (m/mangleIdent v))) ((none) (m/mangleIdent v)))

fn emitAtom s: String aliases: (Map String String) -> String
  (cond ((= s "true") "true") ((= s "false") "false") ((or (= s "nil") (= s "()")) "()") ((stringStartsWith? s "\"") (str (escapeRawString s) ".to_string()")) ((and (stringStartsWith? s "-") (> (stringLength s) 1)) (str "(" s ")")) ((stringContains? s "/") (let [(parts (stringSplit s "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) "")) (modOpt (mapGet aliases alias))] (mt modOpt ((some mpath) (let [(enumOpt (mapGet aliases (str mpath "/" member)))] (mt enumOpt ((some tgt) tgt) ((none) (str "crate::" (m/rustModName mpath) "::" (m/mangleIdent member)))))) ((none) (let [(enumOpt (mapGet aliases s))] (mt enumOpt ((some tgt) tgt) ((none) (str (m/mangleIdent alias) "::" (m/mangleIdent member))))))))) ((= s "none") "None") ((= s "ok") "Ok") ((= s "err") "Err") ((= s "some") "Some") ((= s "notFound") "rt::IoError::NotFound") ((= s "permissionDenied") "rt::IoError::PermissionDenied") ((= s "alreadyExists") "rt::IoError::AlreadyExists") ((= s "invalidPath") "rt::IoError::InvalidPath") ((= s "interrupted") "rt::IoError::Interrupted") ((= s "other") "rt::IoError::Other") (else (resolveEnumAlias s aliases)))

fn getAtomStr e: rd/SExpr -> String
  (mt e ((rd/sexprAtom v) v) ((rd/sexprList _) "") ((rd/sexprVect _) ""))

fn nthAtom items: (List rd/SExpr) idx: I64 -> String
  (getAtomStr (optionOr (listGet items idx) (rd/sexprAtom "")))

fn sliceFrom1 items: (List rd/SExpr) -> (List rd/SExpr)
  (if (> (listLength items) 1) (optionOr (listSlice items 1 (listLength items)) (list)) (list))

fn sliceTail items: (List rd/SExpr) start: I64 -> (List rd/SExpr)
  (if (> (listLength items) start) (optionOr (listSlice items start (listLength items)) (list)) (list))

fn emitFnParam p: rd/SExpr -> String
  (mt p ((rd/sexprVect pItems) (m/mangleIdent (nthAtom pItems 0))) ((rd/sexprList pItems) (m/mangleIdent (nthAtom pItems 0))) ((rd/sexprAtom v) (m/mangleIdent v)))

fn resolveQualifiedCase head: String aliases: (Map String String) -> String
  (if (stringContains? head "/") (let [(parts (stringSplit head "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) "")) (modOpt (mapGet aliases alias))] (mt modOpt ((some mpath) (let [(enumOpt (mapGet aliases (str mpath "/" member)))] (mt enumOpt ((some tgt) tgt) ((none) (str "crate::" (m/rustModName mpath) "::" (m/pascalIdent member)))))) ((none) (let [(enumOpt (mapGet aliases head))] (mt enumOpt ((some tgt) tgt) ((none) (str (m/mangleIdent alias) "::" (m/pascalIdent member)))))))) (mt (mapGet aliases head) ((some tgt) tgt) ((none) (m/pascalIdent head))))

fn nthPattern items: (List rd/SExpr) idx: I64 aliases: (Map String String) -> String
  (emitPattern (optionOr (listGet items idx) (rd/sexprAtom "_")) aliases)

fn emitPattern p: rd/SExpr aliases: (Map String String) -> String
  (mt p ((rd/sexprAtom v) (cond ((= v "_") "_") ((= v "none") "None") ((= v "true") "true") ((= v "false") "false") ((stringStartsWith? v "\"") (escapeRawString v)) (else (resolveEnumAlias v aliases)))) ((rd/sexprVect items) (if (<= (listLength items) 0) "[]" (str "[" (stringJoin (map (fn [(it rd/SExpr)] -> String (emitPattern it aliases)) items) ", ") "]"))) ((rd/sexprList items) (if (<= (listLength items) 0) "()" (let [(head (nthAtom items 0))] (cond ((= head "ok") (str "Ok(" (nthPattern items 1 aliases) ")")) ((= head "err") (str "Err(" (nthPattern items 1 aliases) ")")) ((= head "some") (str "Some(" (nthPattern items 1 aliases) ")")) ((= head "none") "None") ((= head "pair") (str "(" (nthPattern items 1 aliases) ", " (nthPattern items 2 aliases) ")")) ((= head "list") "[]") ((= head "cons") (str "[" (nthPattern items 1 aliases) ", " (nthPattern items 2 aliases) " @ ..]")) (else (let [(pHead (resolveQualifiedCase head aliases)) (rest (if (> (listLength items) 1) (listTail items) (none)))] (mt rest ((none) pHead) ((some rItems) (if (<= (listLength rItems) 0) pHead (str pHead "(" (stringJoin (map (fn [(it rd/SExpr)] -> String (emitPattern it aliases)) rItems) ", ") ")")))))))))))

fn emitBodySeq body: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(bodyLen (listLength body))] (if (<= bodyLen 0) "()" (if (= bodyLen 1) (emitExpr (optionOr (listGet body 0) (rd/sexprAtom "()")) aliases) (let [(stmts (map (fn [(e rd/SExpr)] -> String (str (emitExpr e aliases) "; ")) body)) (lastIdx (- bodyLen 1)) (lastExpr (emitExpr (optionOr (listGet body lastIdx) (rd/sexprAtom "()")) aliases)) (priorStmts (listSlice stmts 0 lastIdx))] (mt priorStmts ((some ps) (str (stringJoin ps "") lastExpr)) ((none) lastExpr))))))

fn emitLet items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(bindingsNode (optionOr (listGet items 1) (rd/sexprVect (list)))) (body (sliceTail items 2)) (bindList (rd/sexprToList bindingsNode)) (letStmts (map (fn [(b rd/SExpr)] -> String (let [(pair (rd/sexprToList b))] (if (>= (listLength pair) 2) (let [(bName (m/mangleIdent (nthAtom pair 0))) (bVal (cloneIfIdent (emitExpr (optionOr (listGet pair 1) (rd/sexprAtom "()")) aliases)))] (str "let " bName " = " bVal "; ")) ""))) bindList)) (bodyStr (emitBodySeq body aliases))] (str "{ " (stringJoin letStmts "") bodyStr " }"))

fn emitIf items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(c (emitExpr (optionOr (listGet items 1) (rd/sexprAtom "false")) aliases)) (th (emitExpr (optionOr (listGet items 2) (rd/sexprAtom "()")) aliases)) (el (emitExpr (optionOr (listGet items 3) (rd/sexprAtom "()")) aliases))] (str "if " c " { " th " } else { " el " }"))

fn emitCondClause c: rd/SExpr isFirst: Bool aliases: (Map String String) -> String
  (mt c ((rd/sexprList cItems) (let [(head (nthAtom cItems 0)) (bodyTail (sliceFrom1 cItems))] (if (or (= head ":else") (= head "else")) (str "} else { " (emitBodySeq bodyTail aliases) " }") (let [(condExpr (emitExpr (optionOr (listGet cItems 0) (rd/sexprAtom "false")) aliases)) (prefix (if isFirst "if " "} else if "))] (str prefix condExpr " { " (emitBodySeq bodyTail aliases) " "))))) ((rd/sexprVect cItems) (emitCondClause (rd/sexprList cItems) isFirst aliases)) ((rd/sexprAtom _) ""))

fn emitCond items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(clauses (sliceFrom1 items))] (if (<= (listLength clauses) 0) "()" (let [(c0 (emitCondClause (optionOr (listGet clauses 0) (rd/sexprAtom "")) true aliases)) (restClauses (sliceFrom1 clauses)) (restParts (map (fn [(c rd/SExpr)] -> String (emitCondClause c false aliases)) restClauses))] (str c0 (stringJoin restParts " ")))))

fn isListArm? arm: rd/SExpr -> Bool
  (mt arm ((rd/sexprList items) (if (<= (listLength items) 0) false (let [(pat (optionOr (listGet items 0) (rd/sexprAtom "")))] (mt pat ((rd/sexprVect _) true) ((rd/sexprList pItems) (let [(pHead (nthAtom pItems 0))] (or (= pHead "list") (= pHead "cons")))) (_ false))))) (_ false))

fn isStringArm? arm: rd/SExpr -> Bool
  (mt arm ((rd/sexprList items) (if (<= (listLength items) 0) false (let [(pat (optionOr (listGet items 0) (rd/sexprAtom "")))] (mt pat ((rd/sexprAtom v) (stringStartsWith? v "\"")) (_ false))))) (_ false))

fn emitMatch items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(subj (emitExpr (optionOr (listGet items 1) (rd/sexprAtom "()")) aliases)) (arms (sliceTail items 2)) (isSlice (cgTy/anyTrue? (map isListArm? arms))) (isStr (cgTy/anyTrue? (map isStringArm? arms))) (subjBase (if (isIdent? subj) (str subj ".clone()") subj)) (subjArg (cond (isSlice (str subjBase ".as_slice()")) (isStr (str subjBase ".as_str()")) (else subjBase))) (armStrs (map (fn [(arm rd/SExpr)] -> String (mt arm ((rd/sexprList aItems) (let [(patNode (optionOr (listGet aItems 0) (rd/sexprAtom "_"))) (patStr (emitPattern patNode aliases)) (body (sliceFrom1 aItems)) (bodyStr (emitBodySeq body aliases)) (isCons? (mt patNode ((rd/sexprList pItems) (= (nthAtom pItems 0) "cons")) (_ false)))] (if isCons? (let [(pItems (mt patNode ((rd/sexprList pi) pi) (_ (list)))) (hName (m/mangleIdent (nthAtom pItems 1))) (tName (m/mangleIdent (nthAtom pItems 2)))] (str patStr " => { let " hName " = " hName ".clone(); let " tName " = " tName ".to_vec(); " bodyStr " },")) (str patStr " => { " bodyStr " },")))) ((rd/sexprVect aItems) (emitMatch (list (rd/sexprAtom "mt") (optionOr (listGet items 1) (rd/sexprAtom "()")) arm) aliases)) ((rd/sexprAtom _) ""))) arms)) (unreach (if isSlice " _ => unreachable!()," ""))] (str "match " subjArg " { " (stringJoin armStrs " ") unreach " }"))

fn emitTry items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(inner (emitExpr (optionOr (listGet items 1) (rd/sexprAtom "()")) aliases))] (str "(" inner ")?"))

fn emitFn items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(hasBang? (and (> (listLength items) 1) (= (nthAtom items 1) "!"))) (pIdx (if hasBang? 2 1)) (bIdx (if hasBang? 3 2)) (paramsNode (optionOr (listGet items pIdx) (rd/sexprVect (list)))) (pList (rd/sexprToList paramsNode)) (pStrs (map emitFnParam pList)) (body (if (> (listLength items) bIdx) (let [(tail (sliceTail items bIdx)) (firstHead (nthAtom tail 0))] (if (and (= firstHead "->") (> (listLength tail) 2)) (sliceTail tail 2) tail)) (list))) (bodyStr (emitBodySeq body aliases))] (str "|" (stringJoin pStrs ", ") "| { " bodyStr " }"))

fn emitRecordInit items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(recName (nthAtom items 0)) (cleanRec (if (stringContains? recName "/") (let [(parts (stringSplit recName "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) "")) (modOpt (mapGet aliases alias))] (mt modOpt ((some mpath) (str "crate::" (m/rustModName mpath) "::" (m/pascalIdent member))) ((none) (str (m/mangleIdent alias) "::" (m/pascalIdent member))))) (m/pascalIdent recName))) (itemsLen (listLength items))] (let [(inits (range 0 (/ (- itemsLen 1) 2))) (fieldStrs (map (fn [(idx Int64)] -> String (let [(kPos (+ 1 (* idx 2))) (vPos (+ 2 (* idx 2))) (kAtom (nthAtom items kPos)) (kClean (if (stringStartsWith? kAtom ":") (sliceStrOr kAtom 1 (stringLength kAtom) kAtom) kAtom)) (vNode (optionOr (listGet items vPos) (rd/sexprAtom "()"))) (vVal (emitExpr vNode aliases)) (vCloned (cloneIfIdent vVal))] (str (m/mangleIdent kClean) ": " vCloned))) inits))] (str cleanRec " { " (stringJoin fieldStrs ", ") " }")))

fn isPascalHead? head: String -> Bool
  (if (< (stringLength head) 1) false (let [(member (if (stringContains? head "/") (let [(parts (stringSplit head "/"))] (optionOr (listGet parts 1) head)) head)) (c0 (sliceStrOr member 0 1 ""))] (and (= (stringUpper c0) c0) (not (= c0 "_")))))

fn emitCall items: (List rd/SExpr) aliases: (Map String String) -> String
  (let [(head (nthAtom items 0)) (rawArgs (sliceFrom1 items)) (args (map (fn [(a rd/SExpr)] -> String (cloneIfIdent (emitExpr a aliases))) rawArgs))] (cond ((stringStartsWith? head ".-") (let [(field (sliceStrOr head 2 (stringLength head) "")) (target (optionOr (listGet args 0) "()"))] (cond ((= field "first") (str target ".0.clone()")) ((= field "second") (str target ".1.clone()")) (else (str target "." (m/mangleIdent field) ".clone()"))))) ((some? (b/builtinTemplate head)) (optionOr (b/renderBuiltin head args) "")) ((and (>= (stringLength head) 2) (stringStartsWith? head ":")) (emitRecordInit items aliases)) ((isPascalHead? head) (if (and (> (listLength items) 1) (stringStartsWith? (nthAtom items 1) ":")) (emitRecordInit items aliases) (caseCall (resolveQualifiedCase head aliases) args))) ((stringContains? head "/") (let [(parts (stringSplit head "/")) (alias (optionOr (listGet parts 0) "")) (member (optionOr (listGet parts 1) "")) (modOpt (mapGet aliases alias))] (mt modOpt ((some mpath) (let [(enumOpt (mapGet aliases (str mpath "/" member)))] (mt enumOpt ((some tgt) (caseCall tgt args)) ((none) (formatCall (str "crate::" (m/rustModName mpath) "::" (m/mangleIdent member)) args))))) ((none) (let [(enumOpt (mapGet aliases head))] (mt enumOpt ((some tgt) (caseCall tgt args)) ((none) (formatCall (str (m/mangleIdent alias) "::" (m/mangleIdent member)) args)))))))) (else (let [(enumOpt (mapGet aliases head))] (mt enumOpt ((some tgt) (caseCall tgt args)) ((none) (formatCall (emitAtom head aliases) args)))))))

fn emitExpr e: rd/SExpr aliases: (Map String String) -> String
  (mt e ((rd/sexprAtom v) (emitAtom v aliases)) ((rd/sexprVect items) (str "vec![" (stringJoin (map (fn [(it rd/SExpr)] -> String (emitExpr it aliases)) items) ", ") "]")) ((rd/sexprList items) (if (<= (listLength items) 0) "()" (let [(head (nthAtom items 0))] (cond ((= head "let") (emitLet items aliases)) ((= head "if") (emitIf items aliases)) ((= head "cond") (emitCond items aliases)) ((or (= head "match") (= head "mt")) (emitMatch items aliases)) ((= head "try") (emitTry items aliases)) ((= head "fn") (emitFn items aliases)) (else (emitCall items aliases)))))))
