(module asl-parser/readerTest :x [projParse projHeads renderAll closureHeads ClosureHeads testReaderSeparatedRendering runTests] :i [(ast :a a) (reader :a rd)])

(schema ClosureHeads (:f calls (List String)) (:f defs (List String)) (:f qualified (List String)))

(schema CState (:f work (List rd/SExpr)) (:f calls (List String)) (:f defs (List String)) (:f qualified (List String)))

fn tailForms xs: (List a/TopForm) -> (List a/TopForm)
  (optionOr (listTail xs) (list))

fn errText e: a/ParseError -> String
  (str (stringFromInt64 e.line) ":" (stringFromInt64 e.col) ": " e.msg)

fn projParse src: String -> String
  (mt (a/parse src) ((err e) (errText e)) ((ok forms) (if (listEmpty? forms) "none" (stringJoin (map (fn [(t a/TopForm)] -> String (projForm t)) forms) "|"))))

fn projForm t: a/TopForm -> String
  (mt t ((a/topModule m) (projModule m)) ((a/topSchema s) (projSchema s)) ((a/topEnum e) (projEnum e)) ((a/topDefun d) (projDefun d)) ((a/topExpr p) (str "expr|" (rd/renderSexpr p.expr))))

fn projModule m: a/ModuleNode -> String
  (str "module|" m.path "|" m.docstring "|" (stringFromInt64 (listLength m.exported)) "|" (stringFromInt64 (listLength m.imports)) "|" (stringFromInt64 (listLength m.defs)))

fn projSchema s: a/SchemaNode -> String
  (let [(jc (mt s.jsonCase ((some v) v) ((none) "none")))] (str "schema|" s.name "|" (stringFromInt64 (listLength s.fields)) "|" jc))

fn projEnum e: a/EnumNode -> String
  (str "enum|" e.name "|" (stringFromInt64 (listLength e.cases)))

fn projDefun d: a/DefunNode -> String
  (str "defun|" d.name "|" (if d.effect "T" "F") "|" (stringFromInt64 (listLength d.params)) "|" d.retType "|" (if d.isExported "T" "F"))

fn projHeads src: String -> String
  (mt (a/parse src) ((err e) (errText e)) ((ok forms) (str (mt (listHead forms) ((some t) (mt t ((a/topModule mn) (projModuleHeads mn)) ((a/topSchema _) "") ((a/topEnum _) "") ((a/topDefun _) "") ((a/topExpr _) ""))) ((none) "")) (headDecls (tailForms forms)))))

fn projModuleHeads mn: a/ModuleNode -> String
  (str mn.docstring "|" (stringJoin mn.exported ",") "|" (stringJoin (map (fn [(p (pair String String))] -> String (str (pairFirst p) ":" (pairSecond p))) mn.imports) ","))

fn headDecls forms: (List a/TopForm) -> String
  (if (listEmpty? forms) "" (str "|" (stringJoin (map (fn [(t a/TopForm)] -> String (headDecl t)) forms) "|")))

fn headDecl t: a/TopForm -> String
  (mt t ((a/topModule _) "module") ((a/topSchema s) (str "schema|" s.name "|" (stringJoin (map (fn [(f a/AstField)] -> String (str f.name ":" f.type ":" f.docstring)) s.fields) ",") "|" (mt s.jsonCase ((some v) v) ((none) "none")))) ((a/topEnum e) (str "enum|" e.name "|" (stringJoin (map (fn [(c a/EnumCase)] -> String (str c.name ":" c.docstring)) e.cases) ","))) ((a/topDefun d) (str "defun|" d.name "|" (if d.effect "T" "F") "|" (stringFromInt64 (listLength d.params)) "|" d.retType "|" d.docstring "|" (stringJoin (map (fn [(b rd/SExpr)] -> String (rd/renderSexpr b)) d.body) " "))) ((a/topExpr p) (str "expr|" (rd/renderSexpr p.expr))))

fn renderAll src: String -> (Result String a/ParseError)
  (mt (a/parse src) ((err e) (err e)) ((ok forms) (ok (stringJoin (map (fn [(t a/TopForm)] -> String (a/renderNode t)) forms) "\n"))))

fn tailExprs items: (List rd/SExpr) -> (List rd/SExpr)
  (optionOr (listTail items) (list))

fn sexprItems s: rd/SExpr -> (List rd/SExpr)
  (mt s ((rd/sexprList items) items) ((rd/sexprVect items) items) ((rd/sexprAtom _) (list)))

fn nthExpr items: (List rd/SExpr) i: Int64 -> rd/SExpr
  (mt (listGet items i) ((some s) s) ((none) (rd/makeAtom "")))

fn firstItem items: (List rd/SExpr) -> rd/SExpr
  (mt (listHead items) ((some s) s) ((none) (rd/makeAtom "")))

fn firstChar s: String -> String
  (mt (stringSlice s 0 1) ((some c) c) ((none) ""))

fn charsIn? allowed: String s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (stringContains? allowed c))) true (stringChars s))

fn dropMarker s: String -> String
  (let [(n (stringLength s))] (cond ((<= n 0) s) ((or (stringEndsWith? s "?") (stringEndsWith? s "!")) (optionOr (stringSlice s 0 (- n 1)) "")) (else s)))

fn kebabIdent? s: String -> Bool
  (let [(core (dropMarker s))] (and (not (stringEmpty? core)) (and (stringContains? "abcdefghijklmnopqrstuvwxyz" (firstChar core)) (charsIn? "abcdefghijklmnopqrstuvwxyz0123456789-" core))))

fn kwHead? h: String -> Bool
  (= (firstChar h) ":")

fn dotHead? h: String -> Bool
  (= (firstChar h) ".")

fn upperTail? h: String -> Bool
  (let [(s (lastOf (stringSplit h "/")))] (and (not (stringEmpty? s)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (firstChar s))))

fn slashHead? h: String -> Bool
  (let [(segs (stringSplit h "/"))] (and (> (listLength segs) 1) (not (stringEmpty? (lastOf segs)))))

fn lastOf xs: (List String) -> String
  (mt (listHead (listReverse xs)) ((some s) s) ((none) ""))

fn pascalHead? h: String -> Bool
  (and (not (stringEmpty? h)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (firstChar h)))

fn opHead? h: String -> Bool
  (or (= h "=") (or (= h "+") (or (= h "-") (or (= h "*") (or (= h "/") (or (= h "<") (or (= h ">") (or (= h "<=") (or (= h ">=") (= h "!="))))))))))

fn ctorHead? h: String -> Bool
  (or (= h "ok") (or (= h "err") (or (= h "some") (or (= h "none") (or (= h "pair") (= h "list"))))))

fn cCall st: CState h: String -> CState
  (with st :calls (cons h st.calls))

fn cQual st: CState h: String -> CState
  (with st :qualified (cons h st.qualified))

fn c-def st: CState h: String -> CState
  (with st :defs (cons h st.defs))

fn cEnqueueMany st: CState xs: (List rd/SExpr) -> CState
  (with st :work (listAppend xs st.work))

fn cWalkTails st: CState items: (List rd/SExpr) -> CState
  (cEnqueueMany st (tailExprs items))

fn cWalkArms st: CState arms: (List rd/SExpr) -> CState
  (fold (fn [(acc CState) (arm rd/SExpr)] -> CState (cEnqueueMany acc (tailExprs (sexprItems arm)))) st arms)

fn cWalkClauses st: CState cls: (List rd/SExpr) -> CState
  (fold (fn [(acc CState) (cl rd/SExpr)] -> CState (cEnqueueMany acc (sexprItems cl))) st cls)

fn cWalkBindings st: CState v: rd/SExpr -> CState
  (fold (fn [(acc CState) (b rd/SExpr)] -> CState (cEnqueueMany acc (tailExprs (sexprItems b)))) st (sexprItems v))

fn fnBody rest: (List rd/SExpr) -> (List rd/SExpr)
  (let [(r1 (if (isHeadText rest "!") (tailExprs rest) rest)) (r2 (if (rd/isVect? (firstItem r1)) (tailExprs r1) r1)) (r3 (if (isHeadText r2 "->") (tailExprs (tailExprs r2)) r2))] r3)

fn isHeadText items: (List rd/SExpr) t: String -> Bool
  (= (rd/sexprHead (firstItem items)) t)

fn cMatch st: CState items: (List rd/SExpr) -> CState
  (cWalkArms (cEnqueueMany st (list (nthExpr items 1))) (tailExprs (tailExprs items)))

fn cCond st: CState items: (List rd/SExpr) -> CState
  (cWalkClauses st (tailExprs items))

fn cLet st: CState items: (List rd/SExpr) -> CState
  (cEnqueueMany (cWalkBindings st (nthExpr items 1)) (tailExprs (tailExprs items)))

fn cFn st: CState items: (List rd/SExpr) -> CState
  (cEnqueueMany st (fnBody (tailExprs items)))

fn cAtomicHead st: CState h: String items: (List rd/SExpr) -> CState
  (cond ((kwHead? h) st) ((= h "match") (cMatch st items)) ((= h "cond") (cCond st items)) ((= h "let") (cLet st items)) ((= h "fn") (cFn st items)) ((or (= h "try") (= h "if")) (cWalkTails st items)) ((ctorHead? h) (cWalkTails st items)) ((dotHead? h) (cWalkTails st items)) ((slashHead? h) (if (upperTail? h) (cWalkTails st items) (cWalkTails (cQual st h) items))) ((pascalHead? h) (cWalkTails st items)) ((or (or (kebabIdent? h) (opHead? h)) (= h "cons")) (cWalkTails (cCall st h) items)) (else (cWalkTails st items)))

fn cList st: CState items: (List rd/SExpr) -> CState
  (if (listEmpty? items) st (let [(h0 (rd/sexprHead (firstItem items)))] (if (or (rd/isList? (firstItem items)) (rd/isVect? (firstItem items))) (cWalkTails (cEnqueueMany st (list (firstItem items))) items) (cAtomicHead st h0 items))))

fn cClassify st: CState s: rd/SExpr -> CState
  (mt s ((rd/sexprAtom _) st) ((rd/sexprVect _) st) ((rd/sexprList items) (cList st items)))

fn cPop st: CState -> CState
  (with st :work (tailExprs st.work))

fn cTick st: CState n: Int64 -> CState
  (mt (listHead st.work) ((some item) (cClassify (cPop st) item)) ((none) st))

fn cRun st: CState budget: Int64 -> CState
  (if (listEmpty? st.work) st (let [(batch (range 0 budget)) (stepped (fold cTick st batch))] (mt (listEmpty? stepped.work) (true stepped) (false (cRun stepped (+ budget budget))))))

fn cTop st: CState t: a/TopForm -> CState
  (mt t ((a/topModule _) st) ((a/topSchema _) st) ((a/topEnum e) (fold (fn [(acc CState) (c a/EnumCase)] -> CState (c-def acc c.name)) st e.cases)) ((a/topDefun d) (cEnqueueMany (c-def st d.name) d.body)) ((a/topExpr p) (cClassify st p.expr)))

fn closureHeads src: String -> (Result ClosureHeads a/ParseError)
  (mt (a/parse src) ((err e) (err e)) ((ok forms) (let [(done (cRun (fold cTop (CState :work (list) :calls (list) :defs (list) :qualified (list)) forms) 64))] (ok (ClosureHeads :calls (listReverse done.calls) :defs (listReverse done.defs) :qualified (listReverse done.qualified))))))

fn testReaderSeparatedRendering -> Bool
  (let [(a1 (rd/makeAtom "first"))
        (a2 (rd/makeAtom "second"))
        (a3 (rd/makeAtom "third"))
        (l (rd/makeList (list a1 a2 a3)))
        (rendered (rd/renderSexpr l))]
    (do
      (assert (= rendered "(first second third)") "renderSexpr produces (first second third)")
      (refute (!= rendered "(first second third)") "renderSexpr refutes non-matching string")
      (assert (stringStartsWith? rendered "(") "renderSexpr starts with (")
      (assert (stringEndsWith? rendered ")") "renderSexpr ends with )")
      true))

fn runTests -> Bool
  (let [(parsed (projParse "(module m) (fn f [] -> Int64 1)")) (heads (projHeads "(module m) (fn f [] -> Int64 1)")) (closed (closureHeads "(module m) (fn f [] -> Int64 1)"))]
    (assert (stringContains? parsed "module|m|") "module projection")
    (assert (stringContains? parsed "defun|f|F|0|Int64|F") "defun projection")
    (assert (stringStartsWith? heads "||") (str "heads projection has no source doc, exports or imports: " heads))
    (assert (mt closed ((ok _) true) ((err _) false)) "closure heads ok")
    (assert (testReaderSeparatedRendering) "testReaderSeparatedRendering")
    true)
