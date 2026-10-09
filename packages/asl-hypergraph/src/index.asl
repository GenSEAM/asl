(module asl-hypergraph/index :x [extractSymbolsFromSexpr extractNodesAndEdgesFromModule buildHypergraphFromModules serializeHyperIndex deserializeHyperIndex loadOrBuildHyperIndex!] :i [(asl-hypergraph/model :a model) (asl-parser/reader :a rd) (asl-parser/lexer :a lx)])

(schema ReaderFrame (:field items (List rd/SExpr)) (:field paren Bool))

(schema ReaderState (:field stack (List ReaderFrame)) (:field out (List rd/SExpr)) (:field fail (Option Str)))

fn pushReaderFrame st: ReaderState paren: Bool -> ReaderState
  (with st :stack (cons (ReaderFrame :items (list) :paren paren) st.stack))

fn emitReaderNode st: ReaderState node: rd/SExpr -> ReaderState
  (mt (listHead st.stack) ((some f) (with st :stack (cons (ReaderFrame :items (cons node f.items) :paren f.paren) (optionOr (listTail st.stack) (list))) :fail (none))) ((none) (ReaderState :stack (list) :out (cons node st.out) :fail (none))))

fn finishReaderFrame st: ReaderState f: ReaderFrame -> ReaderState
  (let [(items (listReverse f.items)) (node (if f.paren (rd/makeList items) (rd/makeVect items))) (popped (with st :stack (optionOr (listTail st.stack) (list)) :fail (none)))] (emitReaderNode popped node))

fn closeReaderFrame st: ReaderState paren: Bool -> ReaderState
  (mt (listHead st.stack) ((some f) (if (= f.paren paren) (finishReaderFrame st f) (with st :fail (some "mismatched delimiter")))) ((none) (with st :stack (list) :fail (some "unexpected closing delimiter"))))

fn finishReader st: ReaderState -> ReaderState
  (mt (listHead st.stack) ((some _) (with st :fail (some "unclosed delimiter"))) ((none) st))

fn readTokenStep st: ReaderState t: lx/Token -> ReaderState
  (mt t.kind ((lx/tokLparen) (pushReaderFrame st true)) ((lx/tokLbracket) (pushReaderFrame st false)) ((lx/tokRparen) (closeReaderFrame st true)) ((lx/tokRbracket) (closeReaderFrame st false)) ((lx/tokEof) (finishReader st)) ((lx/tokError m) (with st :fail (some m))) (_ (emitReaderNode st (rd/makeAtom t.rawText))))

fn parseSexprForms src: Str -> (Result (List rd/SExpr) Str)
  (let [(toks (lx/tokenize src)) (st (fold (fn [(s ReaderState) (t lx/Token)] -> ReaderState (mt s.fail ((some _) s) ((none) (readTokenStep s t)))) (ReaderState :stack (list) :out (list) :fail (none)) toks))] (mt st.fail ((some e) (err e)) ((none) (ok (listReverse st.out)))))

fn isSpecialForm? sym: Str -> Bool
  (let [(forms (list "let" "if" "mt" "do" "cond" "fn" "module" "df" "dfs" "dfe" "assert" "refute" "str" "list" "pair" "and" "or" "not" "=" "!=" "+" "-" "*" "/" ".-"))] (or (stringStartsWith? sym ":") (fold (fn [(acc Bool) (f Str)] -> Bool (or acc (= sym f))) false forms)))

fn extractSymbolsFromSexpr form: rd/SExpr -> (List Str)
  (mt form ((rd/sexprList items) (mt (listHead items) ((some headNode) (let [(restNodes (optionOr (listTail items) (list))) (subSymbols (fold (fn [(acc (List Str)) (child rd/SExpr)] -> (List Str) (listAppend acc (extractSymbolsFromSexpr child))) (list) restNodes))] (if (rd/isAtom? headNode) (let [(headSym (rd/sexprHead headNode))] (if (or (isSpecialForm? headSym) (stringEmpty? headSym)) subSymbols (cons headSym subSymbols))) (listAppend (extractSymbolsFromSexpr headNode) subSymbols)))) ((none) (list)))) (_ (list)))

fn unquoteText s: Str -> Str
  (let [(len (stringLength s))] (if (and (>= len 2) (stringStartsWith? s "\"") (stringEndsWith? s "\"")) (optionOr (stringSlice s 1 (- len 1)) "") s))

fn findDocstring items: (List rd/SExpr) -> Str
  (mt (listHead items) ((some it) (let [(rest (optionOr (listTail items) (list)))] (if (and (rd/isAtom? it) (= (rd/sexprHead it) ":d")) (mt (listHead rest) ((some valNode) (unquoteText (rd/sexprHead valNode))) ((none) "")) (findDocstring rest)))) ((none) ""))

fn extractNodesAndEdgesFromModule modName: Str sourceText: Str -> (Pair (List model/HyperNode) (List model/HyperEdge))
  (mt (parseSexprForms sourceText) ((err _) (pair (list) (list))) ((ok forms) (fold (fn [(acc (Pair (List model/HyperNode) (List model/HyperEdge))) (form rd/SExpr)] -> (Pair (List model/HyperNode) (List model/HyperEdge)) (let [(nodes (pairFirst acc)) (edges (pairSecond acc))] (mt form ((rd/sexprList items) (let [(head (mt (listHead items) ((some h) (rd/sexprHead h)) ((none) "")))] (cond ((or (= head "df") (= head "df!")) (let [(tailItems (optionOr (listTail items) (list))) (isBang (= head "df!")) (effectiveTail (if (and (not isBang) (mt (listHead tailItems) ((some h) (= (rd/sexprHead h) "!")) ((none) false))) (optionOr (listTail tailItems) (list)) tailItems)) (fnName (mt (listHead effectiveTail) ((some n) (rd/sexprHead n)) ((none) "anonymous"))) (fnDoc (findDocstring items)) (fullId (str modName ":" fnName)) (kind (if (or (stringStartsWith? fnName "test") (stringContains? modName "/tests/") (stringContains? modName "tests/")) "test" "function")) (fnNode (model/makeHyperNode fullId kind modName fnName fnDoc)) (callees (extractSymbolsFromSexpr form)) (callEdges (fold (fn [(eAcc (List model/HyperEdge)) (callee Str)] -> (List model/HyperEdge) (let [(isTestKind (= kind "test")) (rel (if isTestKind "tests" "calls")) (edge (model/makeHyperEdge fullId rel callee "body"))] (listAppend eAcc (list edge)))) (list) callees))] (pair (listAppend nodes (list fnNode)) (listAppend edges callEdges)))) ((or (= head "dfs") (= head "defschema")) (let [(tailItems (optionOr (listTail items) (list))) (structName (mt (listHead tailItems) ((some n) (rd/sexprHead n)) ((none) "anonymous"))) (structDoc (findDocstring items)) (fullId (str modName ":" structName)) (structNode (model/makeHyperNode fullId "struct" modName structName structDoc))] (pair (listAppend nodes (list structNode)) edges))) ((or (= head "dfe") (= head "defenum")) (let [(tailItems (optionOr (listTail items) (list))) (enumName (mt (listHead tailItems) ((some n) (rd/sexprHead n)) ((none) "anonymous"))) (enumDoc (findDocstring items)) (fullId (str modName ":" enumName)) (enumNode (model/makeHyperNode fullId "type" modName enumName enumDoc))] (pair (listAppend nodes (list enumNode)) edges))) (else acc)))) (_ acc)))) (pair (list) (list)) forms)))

fn buildHypergraphFromModules modules: (List (Pair Str Str)) -> model/HyperIndex
  (let [(combined (fold (fn [(acc (Pair (List model/HyperNode) (List model/HyperEdge))) (modEntry (Pair Str Str))] -> (Pair (List model/HyperNode) (List model/HyperEdge)) (let [(modName (pairFirst modEntry)) (srcText (pairSecond modEntry)) (modRes (extractNodesAndEdgesFromModule modName srcText))] (pair (listAppend (pairFirst acc) (pairFirst modRes)) (listAppend (pairSecond acc) (pairSecond modRes))))) (pair (list) (list)) modules))] (model/makeHyperIndex 1 (pairFirst combined) (pairSecond combined) 1789720000000))

fn renderHyperNode n: model/HyperNode -> Str
  (str "    (:node :id \"" n.id "\" :kind \"" n.kind "\" :module \"" n.module "\" :symbol \"" n.symbol "\" :doc \"" n.doc "\")")

fn renderHyperEdge e: model/HyperEdge -> Str
  (str "    (:edge :source \"" e.source "\" :relation \"" e.relation "\" :target \"" e.target "\" :anchor \"" e.anchor "\")")

fn serializeHyperIndex idx: model/HyperIndex -> Str
  (let [(nodeLines (map (fn [(n model/HyperNode)] -> Str (renderHyperNode n)) idx.nodes)) (edgeLines (map (fn [(e model/HyperEdge)] -> Str (renderHyperEdge e)) idx.edges))] (str "(:hyperIndex\n" "  :version " (stringFromInt64 idx.version) "\n" "  :timestamp " (stringFromInt64 idx.timestamp) "\n" "  :nodes [\n" (stringJoin nodeLines "\n") "\n  ]\n" "  :edges [\n" (stringJoin edgeLines "\n") "\n  ])\n"))

fn findKvAtom items: (List rd/SExpr) key: Str -> Str
  (mt (listHead items) ((some it) (let [(rest (optionOr (listTail items) (list)))] (if (and (rd/isAtom? it) (= (rd/sexprHead it) key)) (mt (listHead rest) ((some valNode) (unquoteText (rd/sexprHead valNode))) ((none) "")) (findKvAtom rest key)))) ((none) ""))

fn findKvNode items: (List rd/SExpr) key: Str -> (Option rd/SExpr)
  (mt (listHead items) ((some it) (let [(rest (optionOr (listTail items) (list)))] (if (and (rd/isAtom? it) (= (rd/sexprHead it) key)) (listHead rest) (findKvNode rest key)))) ((none) (none)))

fn parseHyperNode form: rd/SExpr -> (Option model/HyperNode)
  (mt form ((rd/sexprList items) (let [(head (mt (listHead items) ((some h) (rd/sexprHead h)) ((none) "")))] (if (and (!= head ":node") (!= head "node")) (none) (let [(id (findKvAtom items ":id")) (kind (findKvAtom items ":kind")) (module (findKvAtom items ":module")) (symbol (findKvAtom items ":symbol")) (doc (findKvAtom items ":doc"))] (if (stringEmpty? id) (none) (some (model/makeHyperNode id kind module symbol doc))))))) (_ (none)))

fn parseHyperEdge form: rd/SExpr -> (Option model/HyperEdge)
  (mt form ((rd/sexprList items) (let [(head (mt (listHead items) ((some h) (rd/sexprHead h)) ((none) "")))] (if (and (!= head ":edge") (!= head "edge")) (none) (let [(source (findKvAtom items ":source")) (relation (findKvAtom items ":relation")) (target (findKvAtom items ":target")) (anchor (findKvAtom items ":anchor"))] (if (or (stringEmpty? source) (stringEmpty? target)) (none) (some (model/makeHyperEdge source relation target anchor))))))) (_ (none)))

fn deserializeHyperIndex text: Str -> (Result model/HyperIndex Str)
  (if (stringEmpty? (stringTrim text)) (ok (model/makeHyperIndex 1 (list) (list) 0)) (mt (parseSexprForms text) ((err msg) (err (str "Failed to parse hyper index ASN: " msg))) ((ok forms) (mt (listHead forms) ((none) (err "Empty hyper index input")) ((some rootForm) (mt rootForm ((rd/sexprList items) (let [(nodesOpt (findKvNode items ":nodes")) (edgesOpt (findKvNode items ":edges")) (nodeForms (mt nodesOpt ((some nv) (mt nv ((rd/sexprVect v) v) ((rd/sexprList l) l) ((rd/sexprAtom _) (list)))) ((none) (list)))) (edgeForms (mt edgesOpt ((some ev) (mt ev ((rd/sexprVect v) v) ((rd/sexprList l) l) ((rd/sexprAtom _) (list)))) ((none) (list)))) (nodesRes (fold (fn [(acc (Result (List model/HyperNode) Str)) (nf rd/SExpr)] -> (Result (List model/HyperNode) Str) (mt acc ((err e) (err e)) ((ok ns) (mt (parseHyperNode nf) ((some n) (ok (listAppend ns (list n)))) ((none) (err "Corrupted node definition in hyper index")))))) (ok (list)) nodeForms)) (edgesRes (fold (fn [(acc (Result (List model/HyperEdge) Str)) (ef rd/SExpr)] -> (Result (List model/HyperEdge) Str) (mt acc ((err e) (err e)) ((ok es) (mt (parseHyperEdge ef) ((some e) (ok (listAppend es (list e)))) ((none) (err "Corrupted edge definition in hyper index")))))) (ok (list)) edgeForms))] (mt nodesRes ((err e) (err e)) ((ok ns) (mt edgesRes ((err e) (err e)) ((ok es) (ok (model/makeHyperIndex 1 ns es 1789720000000)))))))) (_ (err "Hyper index root must be an S-expression list"))))))))

fn loadOrBuildHyperIndex! indexPath: Str fallbackModules: (List (Pair Str Str)) -> model/HyperIndex
  (let [(readRes (fileRead indexPath))] (mt readRes ((ok content) (let [(parsedRes (deserializeHyperIndex content))] (mt parsedRes ((ok idx) idx) ((err _) (buildHypergraphFromModules fallbackModules))))) ((err _) (let [(idx (buildHypergraphFromModules fallbackModules)) (rendered (serializeHyperIndex idx)) (_ (fileWrite indexPath rendered))] idx))))
