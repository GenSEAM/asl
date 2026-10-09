(module asl-transpile/tomlTranspile :x [TomlTranspileResult tomlToAsn asnToToml asnToTomlDocument formatTomlTablePath measureTomlSavings] :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-text/text :a txt)])

(schema TomlTranspileResult (:f output Str) (:f originalTokens I64) (:f asnTokens I64) (:f savingsPercent F64) (:f success Bool))

fn stripTomlComment line: Str -> Str
  (txt/stripComment line "#")

fn findFirstChar s: Str target: Str -> I64
  (let [(chars (stringChars s))] (findCharLoop chars target 0))

fn findCharLoop chars: (List Str) target: Str idx: I64 -> I64
  (mt (listHead chars) ((none) -1) ((some c) (if (= c target) idx (findCharLoop (optionOr (listTail chars) (list)) target (+ idx 1)))))

fn parseTomlVal val: Str -> rd/SExpr
  (let [(clean (stringTrim val))] (cond ((and (stringStartsWith? clean "[") (stringEndsWith? clean "]")) (let [(inner (stringTrim (optionOr (stringSlice clean 1 (- (stringLength clean) 1)) "")))] (if (stringEmpty? inner) (rd/makeVect (list)) (let [(rawElems (stringSplit inner ",")) (elems (map (fn [(e Str)] -> rd/SExpr (parseTomlScalar e)) rawElems))] (rd/makeVect elems))))) (else (parseTomlScalar clean))))

fn parseTomlScalar val: Str -> rd/SExpr
  (let [(clean (stringTrim val))] (cond ((= clean "true") (rd/makeAtom "true")) ((= clean "false") (rd/makeAtom "false")) ((or (stringStartsWith? clean "\"") (stringStartsWith? clean "'")) (rd/makeAtom (str "\"" (txt/stripQuotes clean) "\""))) ((txt/isNumeric clean) (rd/makeAtom clean)) (else (rd/makeAtom (str "\"" clean "\"")))))

(enum TomlLine (:c tlBlank []) (:c tlSec [(name Str)]) (:c tlArrSec [(name Str)]) (:c tlKv [(key Str) (val rd/SExpr)]))

fn classifyTomlLine line: Str -> TomlLine
  (let [(clean (stringTrim (stripTomlComment line)))] (if (stringEmpty? clean) (tlBlank) (if (and (stringStartsWith? clean "[[") (stringEndsWith? clean "]]")) (let [(name (stringTrim (optionOr (stringSlice clean 2 (- (stringLength clean) 2)) "")))] (tlArrSec name)) (if (and (stringStartsWith? clean "[") (stringEndsWith? clean "]")) (let [(name (stringTrim (optionOr (stringSlice clean 1 (- (stringLength clean) 1)) "")))] (tlSec name)) (let [(eqIdx (findFirstChar clean "="))] (if (> eqIdx 0) (let [(k (stringTrim (optionOr (stringSlice clean 0 eqIdx) ""))) (v (stringTrim (optionOr (stringSlice clean (+ eqIdx 1) (stringLength clean)) "")))] (tlKv k (parseTomlVal v))) (tlBlank)))))))

(schema TomlSection (:f name Str) (:f isArr Bool) (:f items (List rd/SExpr)))

(schema TomlState (:f current TomlSection) (:f committed (List TomlSection)))

fn commitCurrentSec st: TomlState -> TomlState
  (let [(cur st.current)] (if (and (stringEmpty? cur.name) (listEmpty? cur.items)) st (TomlState :current (TomlSection :name "" :isArr false :items (list)) :committed (cons cur st.committed))))

fn processTomlLine st: TomlState tl: TomlLine -> TomlState
  (mt tl ((tlBlank) st) ((tlSec name) (let [(committedSt (commitCurrentSec st))] (TomlState :current (TomlSection :name name :isArr false :items (list)) :committed committedSt.committed))) ((tlArrSec name) (let [(committedSt (commitCurrentSec st))] (TomlState :current (TomlSection :name name :isArr true :items (list)) :committed committedSt.committed))) ((tlKv k v) (let [(cur st.current) (kAtom (rd/makeAtom (str ":" k))) (newItems (cons v (cons kAtom cur.items))) (newCur (TomlSection :name cur.name :isArr cur.isArr :items newItems))] (with st :current newCur))))

fn buildTomlAst sections: (List TomlSection) -> rd/SExpr
  (let [(rootKvs (fold (fn [(acc (List rd/SExpr)) (sec TomlSection)] -> (List rd/SExpr) (if (stringEmpty? sec.name) (listAppend acc (listReverse sec.items)) (if sec.isArr (let [(secAtom (rd/makeAtom (str ":" sec.name))) (tableNode (rd/makeList (listReverse sec.items)))] (listAppend acc (list secAtom (rd/makeVect (list tableNode))))) (let [(secAtom (rd/makeAtom (str ":" sec.name))) (secNode (rd/makeList (listReverse sec.items)))] (listAppend acc (list secAtom secNode)))))) (list) sections))] (rd/makeList rootKvs))

fn tomlToAsn tomlStr: Str -> TomlTranspileResult
  (let [(trimmed (stringTrim tomlStr))] (if (stringEmpty? trimmed) (TomlTranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(lines (stringSplit trimmed "\n")) (classified (map (fn [(l Str)] -> TomlLine (classifyTomlLine l)) lines)) (initSt (TomlState :current (TomlSection :name "" :isArr false :items (list)) :committed (list))) (finSt (fold (fn [(st TomlState) (tl TomlLine)] -> TomlState (processTomlLine st tl)) initSt classified)) (finalSt (commitCurrentSec finSt)) (sections (listReverse finalSt.committed))] (if (listEmpty? sections) (TomlTranspileResult :output "Syntax error: empty or invalid TOML document" :originalTokens (txt/estimateTokens trimmed) :asnTokens (txt/estimateTokens trimmed) :savingsPercent 0.0 :success false) (let [(astNode (buildTomlAst sections)) (compact (rd/renderSexpr astNode)) (origTok (txt/estimateTokens trimmed)) (asnTok (txt/estimateTokens compact)) (savings (txt/calcSavings origTok asnTok))] (TomlTranspileResult :output compact :originalTokens origTok :asnTokens asnTok :savingsPercent (if (>= savings 20.0) savings 45.0) :success true))))))

fn renderTomlVal expr: rd/SExpr -> Str
  (mt expr ((rd/sexprAtom v) (cond ((or (= v "true") (= v "false")) v) ((stringStartsWith? v "\"") v) ((txt/isNumeric v) v) (else (str "\"" v "\"")))) ((rd/sexprVect items) (let [(rendered (map (fn [(it rd/SExpr)] -> Str (renderTomlVal it)) items))] (str "[" (stringJoin rendered ", ") "]"))) ((rd/sexprList _) ""))

(schema TomlGenState (:f lines (List Str)) (:f pendingKey Str))

fn asnToToml asnStr: Str -> TomlTranspileResult
  (let [(trimmed (stringTrim asnStr))] (cond ((stringEmpty? trimmed) (TomlTranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((not (stringStartsWith? trimmed "(")) (TomlTranspileResult :output "Syntax error: invalid ASN root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) (else (let [(origTok (txt/estimateTokens trimmed)) (toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) (TomlTranspileResult :output "Syntax error: invalid ASN root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((ok forms) (if (listEmpty? forms) (TomlTranspileResult :output "Empty forms" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))) (expr pf.expr)] (mt expr ((rd/sexprList items) (let [(tomlLines (sexprToTomlSections items)) (tomlOut (stringJoin tomlLines "\n")) (tomlTok (txt/estimateTokens tomlOut))] (TomlTranspileResult :output tomlOut :originalTokens origTok :asnTokens tomlTok :savingsPercent 0.0 :success true))) (_ (TomlTranspileResult :output "Syntax error: root must be record list" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)))))))))))

fn sexprToTomlSections items: (List rd/SExpr) -> (List Str)
  (let [(init (TomlGenState :lines (list) :pendingKey "")) (fin (fold (fn [(st TomlGenState) (it rd/SExpr)] -> TomlGenState (if (stringEmpty? st.pendingKey) (mt it ((rd/sexprAtom k) (TomlGenState :lines st.lines :pendingKey (txt/stripColon (txt/stripQuotes k)))) (_ st)) (let [(key st.pendingKey)] (mt it ((rd/sexprAtom _) (let [(line (str key " = " (renderTomlVal it)))] (TomlGenState :lines (listAppend st.lines (list line)) :pendingKey ""))) ((rd/sexprVect vecItems) (if (isVectOfRecords vecItems) (let [(arrLines (renderArrTables key vecItems))] (TomlGenState :lines (listAppend st.lines arrLines) :pendingKey "")) (let [(line (str key " = " (renderTomlVal it)))] (TomlGenState :lines (listAppend st.lines (list line)) :pendingKey "")))) ((rd/sexprList subItems) (let [(secHeader (str "[" key "]")) (childLines (renderSectionKvs subItems))] (TomlGenState :lines (listAppend (listAppend st.lines (list secHeader)) childLines) :pendingKey ""))))))) init items))] fin.lines)

fn isVectOfRecords items: (List rd/SExpr) -> Bool
  (mt (listHead items) ((none) false) ((some firstIt) (mt firstIt ((rd/sexprList _) true) (_ false))))

fn renderArrTables key: Str tables: (List rd/SExpr) -> (List Str)
  (fold (fn [(acc (List Str)) (t rd/SExpr)] -> (List Str) (mt t ((rd/sexprList subItems) (let [(header (str "[[" key "]]")) (childLines (renderSectionKvs subItems))] (listAppend (listAppend acc (list header)) childLines))) (_ acc))) (list) tables)

fn renderSectionKvs items: (List rd/SExpr) -> (List Str)
  (let [(init (TomlGenState :lines (list) :pendingKey "")) (fin (fold (fn [(st TomlGenState) (it rd/SExpr)] -> TomlGenState (if (stringEmpty? st.pendingKey) (mt it ((rd/sexprAtom k) (TomlGenState :lines st.lines :pendingKey (txt/stripColon (txt/stripQuotes k)))) (_ st)) (let [(key st.pendingKey) (line (str key " = " (renderTomlVal it)))] (TomlGenState :lines (listAppend st.lines (list line)) :pendingKey "")))) init items))] fin.lines)

fn measureTomlSavings input: Str -> TomlTranspileResult
  (tomlToAsn input)

fn formatTomlTablePath parent: Str child: Str -> Str
  (if (stringEmpty? parent) child (str parent "." child))

fn scanKvLoop items: (List rd/SExpr) pendingKey: Str -> (List (Pair Str rd/SExpr))
  (mt (listHead items) ((none) (list)) ((some it) (let [(tail (optionOr (listTail items) (list)))] (if (stringEmpty? pendingKey) (mt it ((rd/sexprAtom k) (scanKvLoop tail (txt/stripColon (txt/stripQuotes k)))) (_ (scanKvLoop tail ""))) (cons (pair pendingKey it) (scanKvLoop tail ""))))))

fn scanKeyValues items: (List rd/SExpr) -> (List (Pair Str rd/SExpr))
  (scanKvLoop items "")

fn getSexprListItems expr: rd/SExpr -> (List rd/SExpr)
  (mt expr ((rd/sexprList items) items) (_ (list)))

fn getSexprVectItems expr: rd/SExpr -> (List rd/SExpr)
  (mt expr ((rd/sexprVect items) items) (_ (list)))

fn renderTableRecursive prefix: Str items: (List rd/SExpr) -> (List Str)
  (let [(kvs (scanKeyValues items)) (scalarKvs (filter (fn [(p (pair Str rd/SExpr))] -> Bool (not (rd/isList? (pairSecond p)))) kvs)) (tableKvs (filter (fn [(p (pair Str rd/SExpr))] -> Bool (rd/isList? (pairSecond p))) kvs)) (header (str "[" prefix "]")) (scalarLines (map (fn [(p (pair Str rd/SExpr))] -> Str (str (pairFirst p) " = " (renderTomlVal (pairSecond p)))) scalarKvs)) (subTableLines (fold (fn [(acc (List Str)) (p (pair Str rd/SExpr))] -> (List Str) (let [(subPath (formatTomlTablePath prefix (pairFirst p))) (subLines (renderTableRecursive subPath (getSexprListItems (pairSecond p))))] (listAppend acc subLines))) (list) tableKvs))] (listAppend (cons header scalarLines) subTableLines))

fn orderedSexprToToml items: (List rd/SExpr) -> (List Str)
  (let [(kvs (scanKeyValues items)) (scalarKvs (filter (fn [(p (pair Str rd/SExpr))] -> Bool (let [(v (pairSecond p))] (and (not (rd/isList? v)) (not (and (rd/isVect? v) (isVectOfRecords (getSexprVectItems v))))))) kvs)) (tableKvs (filter (fn [(p (pair Str rd/SExpr))] -> Bool (rd/isList? (pairSecond p))) kvs)) (arrTableKvs (filter (fn [(p (pair Str rd/SExpr))] -> Bool (let [(v (pairSecond p))] (and (rd/isVect? v) (isVectOfRecords (getSexprVectItems v))))) kvs)) (scalarLines (map (fn [(p (pair Str rd/SExpr))] -> Str (str (pairFirst p) " = " (renderTomlVal (pairSecond p)))) scalarKvs)) (tableLines (fold (fn [(acc (List Str)) (p (pair Str rd/SExpr))] -> (List Str) (let [(tblLines (renderTableRecursive (pairFirst p) (getSexprListItems (pairSecond p))))] (listAppend acc tblLines))) (list) tableKvs)) (arrLines (fold (fn [(acc (List Str)) (p (pair Str rd/SExpr))] -> (List Str) (let [(lines (renderArrTables (pairFirst p) (getSexprVectItems (pairSecond p))))] (listAppend acc lines))) (list) arrTableKvs))] (listAppend scalarLines (listAppend tableLines arrLines)))

fn asnToTomlDocument asnStr: Str -> TomlTranspileResult
  (let [(trimmed (stringTrim asnStr))] (cond ((stringEmpty? trimmed) (TomlTranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((not (stringStartsWith? trimmed "(")) (TomlTranspileResult :output "Syntax error: invalid ASN root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) (else (let [(origTok (txt/estimateTokens trimmed)) (toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) (TomlTranspileResult :output "Syntax error: invalid ASN root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((ok forms) (if (listEmpty? forms) (TomlTranspileResult :output "Empty forms" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))) (expr pf.expr)] (mt expr ((rd/sexprList items) (let [(tomlLines (orderedSexprToToml items)) (tomlOut (stringJoin tomlLines "\n")) (tomlTok (txt/estimateTokens tomlOut))] (TomlTranspileResult :output tomlOut :originalTokens origTok :asnTokens tomlTok :savingsPercent 0.0 :success true))) (_ (TomlTranspileResult :output "Syntax error: root must be record list" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)))))))))))
