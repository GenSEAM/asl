(module asl-parser/ast :x [moduleNode ModuleNode SchemaNode EnumNode DefunNode EnumCase Param AstField TopForm ParseError PosForm KidForm readForms parse parseLegacy parseForTypeCheck retiredProse retiredSpelling retiredSource spellingErrors retiredFormErrors bangedBuiltins parseForChecker renderNode AstLit litInt litFloat litString litBool litUnit AstPattern patWildcard patVar patLit patTuple patRecord patCtor AstMatchArm matchArm makeMatchArm AstExpr exprLit exprIdent exprMember exprCall exprLet exprIf exprMatch exprTry exprBlock exprRecord exprCond exprLambda exprInterpolation AstType typeNamed typeTuple typeRecord typeFn charsWithin? tailExprs sexprItems nthExpr hasTailrec? isInlineBodyCandidate? typeNodeText joinFnHeader readKidForms kidFormsFor findTokenPos findQualifiedTokenPos scriptStepParts scriptStepAt shebangless scriptMainDoc scriptStatementsOf] :i [(lexer :a lx) (reader :a rd) (indentParser :a ip) (asl-syntax/core/tree :a tr) (fnHeader :a fh)])

(schema ParseError (:f msg String) (:f line Int64) (:f col Int64))

(schema Param (:f name String) (:f type String))

(schema AstField (:f name String) (:f type String) (:f docstring String) (:f default (Option rd/SExpr)) (:f json (Option String)))

(schema EnumCase (:f name String) (:f fields (List Param)) (:f docstring String))

(schema ModuleNode (:f path String) (:f docstring String) (:f exported (List String)) (:f imports (List (Pair String String))) (:f defs (List TopForm)))

(schema SchemaNode (:f name String) (:f typeVars (List String)) (:f fields (List AstField)) (:f jsonCase (Option String)))

(schema EnumNode (:f name String) (:f typeVars (List String)) (:f cases (List EnumCase)))

(schema DefunNode (:f name String) (:f typeVars (List String)) (:f isExported Bool) (:f effect Bool) (:f params (List Param)) (:f retType String) (:f docstring String) (:f body (List rd/SExpr)) (:f bodyPos (List PosForm)))

(enum TopForm (:c topModule [(node ModuleNode)] "A module declaration") (:c topSchema [(node SchemaNode)] "A defschema declaration") (:c topEnum [(node EnumNode)] "A defenum declaration") (:c topDefun [(node DefunNode)] "A defun declaration") (:c topExpr [(pos PosForm)] "A bare top-level expression, kept as written; its side effect runs at module load, in declared order"))

(enum AstLit (:c litInt [(val Int64)]) (:c litFloat [(val Float64)]) (:c litString [(val String)]) (:c litBool [(val Bool)]) (:c litUnit []))

(enum AstPattern (:c patWildcard [] "Wildcard _") (:c patVar [(name String)] "Variable binding") (:c patLit [(lit AstLit)] "Literal pattern") (:c patTuple [(elements (List AstPattern))] "Tuple/list pattern") (:c patRecord [(fields (List (Pair String AstPattern)))] "Record pattern") (:c patCtor [(name String) (arg (Option AstPattern))] "Constructor pattern"))

(schema AstMatchArm (:f pat AstPattern) (:f body AstExpr))

(enum AstExpr (:c exprLit [(lit AstLit)] "Literal constant") (:c exprIdent [(name String)] "Variable or symbol reference") (:c exprMember [(target AstExpr) (field String)] "Record/schema field access target.field") (:c exprCall [(func AstExpr) (args (List AstExpr))] "Function or constructor call") (:c exprLet [(bindings (List (Pair AstPattern AstExpr))) (body (List AstExpr))] "Let binding form") (:c exprIf [(cond AstExpr) (thenBranch AstExpr) (elseBranch AstExpr)] "Conditional branch") (:c exprMatch [(target AstExpr) (arms (List AstMatchArm))] "Pattern match form") (:c exprTry [(inner AstExpr)] "Error propagation try operator expr?") (:c exprBlock [(exprs (List AstExpr))] "Block of sequential expressions") (:c exprRecord [(fields (List (Pair String AstExpr))) (rawTokens (List AstExpr))] "Record literal constructor") (:c exprCond [(clauses (List (Pair AstExpr (List AstExpr))))] "Conditional branch cond") (:c exprLambda [(params (List Param)) (retType (Option String)) (body (List AstExpr)) (rawParams rd/SExpr)] "Lambda anonymous function") (:c exprInterpolation [(parts (List AstExpr))] "String interpolation"))

(enum AstType (:c typeNamed [(name String)]) (:c typeTuple [(elements (List AstType))]) (:c typeRecord [(fields (List (Pair String AstType)))]) (:c typeFn [(paramTypes (List AstType)) (retType AstType)]))

fn matchArm pat: AstPattern body: AstExpr -> AstMatchArm
  (AstMatchArm :pat pat :body body)

fn makeMatchArm pat: AstPattern body: AstExpr -> AstMatchArm
  (AstMatchArm :pat pat :body body)
fn headSpellings -> (List String)
  (list "defun" "def" "df" "defschema" "schema" "dfs" "defenum" "enum" "dfe" "match" ":field" ":f" ":case" ":c")

fn headVerboseNames -> (List String)
  (list "defun" "defun" "defun" "defschema" "defschema" "defschema" "defenum" "defenum" "defenum" "match" ":field" ":field" ":case" ":case")

fn optionSpellings -> (List String)
  (list ":doc" ":d" ":export" ":x" ":import" ":i" ":as" ":a")

fn optionVerboseNames -> (List String)
  (list ":doc" ":doc" ":export" ":export" ":import" ":import" ":as" ":as")

fn typeSpellings -> (List String)
  (list "Int" "I64" "I32" "F64" "F32" "Num" "Str" "Bool" "Unit" "Float")

fn typeVerboseNames -> (List String)
  (list "Int64" "Int64" "Int32" "Float64" "Float64" "Float64" "String" "Bool" "Unit" "Float64")

fn aliasLookup spellings: (List String) verbs: (List String) a: String -> String
  (match (listIndexOf spellings a) ((some i) (optionOr (listGet verbs i) a)) ((none) a))

fn headVerbose a: String -> String
  (aliasLookup (headSpellings) (headVerboseNames) a)

fn optionVerbose a: String -> String
  (aliasLookup (optionSpellings) (optionVerboseNames) a)

fn typeVerbose a: String -> String
  (aliasLookup (typeSpellings) (typeVerboseNames) a)

fn resolveTypeText t: String -> String
  (let [(spaced (stringReplace (stringReplace t "(" " ( ") ")" " ) ")) (words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit spaced " "))) (mapped (stringJoin (map (fn [(w String)] -> String (typeVerbose w)) words) " "))] (stringReplace (stringReplace mapped "( " "(") " )" ")"))

fn charsWithin? allowed: String s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (stringContains? allowed c))) true (stringChars s))

fn dropSuffix s: String -> String
  (if (or (stringEndsWith? s "?") (stringEndsWith? s "!")) (optionOr (stringSlice s 0 (- (stringLength s) 1)) "") s)

fn kebabIdent? s: String -> Bool
  (let [(core (dropSuffix s))] (and (not (stringEmpty? core)) (and (stringContains? "abcdefghijklmnopqrstuvwxyz" (lx/charAt core 0)) (charsWithin? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-" core))))

fn fnName? s: String -> Bool
  (let [(toks (lx/tokenize s))] (and (!= s "->") (and (= (listLength toks) 2) (match (listHead toks) ((some t) (match t.kind ((lx/tokSymbol _) true) (_ false))) ((none) false)))))

fn pascalName? s: String -> Bool
  (and (not (stringEmpty? s)) (and (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (lx/charAt s 0)) (charsWithin? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" s)))

fn modPath? s: String -> Bool
  (and (not (stringEmpty? s)) (charsWithin? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/." s))

(schema PosForm (:f expr rd/SExpr) (:f line Int64) (:f col Int64))

(schema KidForm (:f pf PosForm) (:f kids (List (Pair Int64 Int64))) (:f startOffset Int64) (:f endOffset Int64))

(schema Frame (:f items (List rd/SExpr)) (:f paren Bool) (:f line Int64) (:f col Int64) (:f kidPos (List (Pair Int64 Int64))) (:f startOffset Int64) (:f headAtom (Option rd/SExpr)))

(schema ReadState (:f stack (List Frame)) (:f out (List KidForm)) (:f fail (Option ParseError)) (:f curOffset Int64))

fn frameTail fs: (List Frame) -> (List Frame)
  (optionOr (listTail fs) (list))

fn tailExprs items: (List rd/SExpr) -> (List rd/SExpr)
  (optionOr (listTail items) (list))

fn sexprItems s: rd/SExpr -> (List rd/SExpr)
  (match s ((rd/sexprList items) items) ((rd/sexprVect items) items) ((rd/sexprAtom _) (list)))

fn nthExpr items: (List rd/SExpr) i: Int64 -> rd/SExpr
  (match (listGet items i) ((some node) node) ((none) (rd/makeAtom "")))

fn nthString items: (List rd/SExpr) i: Int64 -> String
  (rd/sexprHead (nthExpr items i))

fn listHeadText items: (List rd/SExpr) -> String
  (match (listHead items) ((some h) (rd/sexprHead h)) ((none) ""))

fn atomsToStrings xs: (List rd/SExpr) -> (List String)
  (map (fn [(x rd/SExpr)] -> String (rd/sexprHead x)) xs)

fn findOpt items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead items) ((some it) (if (and (rd/isAtom? it) (= (rd/sexprHead it) key)) (listHead (tailExprs items)) (findOpt (tailExprs items) key))) ((none) (none)))

(schema OptScan (:f acc (List rd/SExpr)) (:f pendingImport Bool))

fn normImportSpec s: rd/SExpr -> rd/SExpr
  (let [(its (sexprItems s))] (if (and (= (listLength its) 3) (= (optionVerbose (nthString its 1)) ":as")) (rd/makeList (list (nthExpr its 0) (rd/makeAtom ":as") (nthExpr its 2))) s))

fn normImportVect v: rd/SExpr -> rd/SExpr
  (match v ((rd/sexprVect specs) (rd/makeVect (map (fn [(s rd/SExpr)] -> rd/SExpr (normImportSpec s)) specs))) ((rd/sexprList _) v) ((rd/sexprAtom _) v))

fn normOptionStep st: OptScan x: rd/SExpr -> OptScan
  (if st.pendingImport (OptScan :acc (cons (normImportVect x) st.acc) :pendingImport false) (if (rd/isAtom? x) (let [(v (optionVerbose (rd/sexprHead x)))] (OptScan :acc (cons (rd/makeAtom v) st.acc) :pendingImport (= v ":import"))) (OptScan :acc (cons x st.acc) :pendingImport false)))

fn normOptions items: (List rd/SExpr) -> (List rd/SExpr)
  (listReverse (fold normOptionStep (OptScan :acc (list) :pendingImport false) items).acc)

fn takesOptions? head: String -> Bool
  (or (= head "module") (= head "defun"))

fn normalizeForm items: (List rd/SExpr) -> (List rd/SExpr)
  (match (listHead items) ((some h) (if (rd/isAtom? h) (let [(v (headVerbose (rd/sexprHead h))) (rest (tailExprs items))] (cons (rd/makeAtom v) (if (takesOptions? v) (normOptions rest) rest))) items)) ((none) items))

fn formDefect items: (List rd/SExpr) -> String
  (if (and (= (listHeadText items) "fn") (= (nthString items 1) "{")) "a lambda takes neither type parameters nor :doc" "")

fn readFail st: ReadState msg: String line: Int64 col: Int64 -> ReadState
  (with st :fail (some (ParseError :msg msg :line line :col col)))

fn emitNode st: ReadState node: rd/SExpr line: Int64 col: Int64 kids: (List (Pair Int64 Int64)) startOff: Int64 endOff: Int64 -> ReadState
  (match (listHead st.stack)
    ((some f) (with st :stack (cons (Frame :items (cons node f.items) :paren f.paren :line f.line :col f.col :kidPos (cons (pair line col) f.kidPos) :startOffset f.startOffset :headAtom (if (listEmpty? f.items) (some node) f.headAtom)) (frameTail st.stack)) :fail (none)))
    ((none) (with st :stack (list) :out (cons (KidForm :pf (PosForm :expr node :line line :col col) :kids kids :startOffset startOff :endOffset endOff) st.out) :fail (none))))

fn pushFrame st: ReadState paren: Bool t: lx/Token -> ReadState
  (with st :stack (cons (Frame :items (list) :paren paren :line t.line :col t.col :kidPos (list) :startOffset st.curOffset :headAtom (none)) st.stack) :fail (none))

fn finishFrame st: ReadState f: Frame t: lx/Token -> ReadState
  (let [(items (listReverse f.items))
        (defect (if f.paren (formDefect items) ""))
        (node (if f.paren (rd/makeList (normalizeForm items)) (rd/makeVect items)))
        (endOff (+ st.curOffset (stringLength t.rawText)))
        (popped (with st :stack (frameTail st.stack) :fail (none)))]
    (if (= defect "")
      (emitNode popped node f.line f.col (listReverse f.kidPos) f.startOffset endOff)
      (readFail st defect t.line t.col)))

fn closeFrame st: ReadState paren: Bool t: lx/Token -> ReadState
  (match (listHead st.stack)
    ((some f) (if (= f.paren paren) (finishFrame st f t) (readFail st (str "mismatched closing delimiter '" t.rawText "'") t.line t.col)))
    ((none) (readFail st (str "unexpected closing delimiter '" t.rawText "'") t.line t.col)))

fn finishRead st: ReadState -> ReadState
  (match (listHead st.stack) ((some f) (readFail st "unclosed delimiter" f.line f.col)) ((none) st))

fn fieldStart? c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" c))

fn wordChars? allowed: String s: String -> Bool
  (listAll? (fn [c] (or (fieldStart? c) (stringContains? allowed c))) (stringChars s))

fn fieldName? s: String -> Bool
  (and (fieldStart? (lx/charAt s 0)) (wordChars? "0123456789-?!" s))

fn fieldOf base: rd/SExpr field: String -> rd/SExpr
  (rd/makeList (list (rd/makeAtom (str ".-" field)) base))

fn fieldChain base: rd/SExpr fields: (List String) -> (Option rd/SExpr)
  (if (listAll? fieldName? fields) (some (fold fieldOf base fields)) (none))

fn dotName raw: String -> rd/SExpr
  (let [(parts (stringSplit raw "."))
        (head (optionOr (listHead parts) ""))]
    (if (or (< (listLength parts) 2) (not (and (fieldStart? (lx/charAt head 0)) (wordChars? "0123456789-?!/" head))))
      (rd/makeAtom raw)
      (optionOr (fieldChain (rd/makeAtom head) (optionOr (listTail parts) (list))) (rd/makeAtom raw))))

fn postfixToken? raw: String -> Bool
  (and (stringStartsWith? raw ".") (fieldStart? (lx/charAt raw 1)))

fn inModuleForm? stack: (List Frame) -> Bool
  (match (listLast stack)
    ((some f) (match f.headAtom ((some h) (and (rd/isAtom? h) (= (rd/sexprHead h) "module"))) ((none) false)))
    ((none) false))

fn postfixFields st: ReadState t: lx/Token -> ReadState
  (let [(fields (optionOr (listTail (stringSplit t.rawText ".")) (list)))
        (bad (readFail st "ERR_READ_FIELD a postfix field chain is .name(.name)* after ')'" t.line t.col))]
    (match (listHead st.stack)
      ((some f) (match (listHead f.items)
        ((some prev) (match (fieldChain prev fields)
          ((some x) (with st :stack (cons (Frame :items (cons x (optionOr (listTail f.items) (list))) :paren f.paren :line f.line :col f.col :kidPos f.kidPos :startOffset f.startOffset :headAtom (if (listEmpty? (optionOr (listTail f.items) (list))) (some x) f.headAtom)) (frameTail st.stack)) :fail (none)))
          ((none) bad)))
        ((none) bad)))
      ((none) (match (listHead st.out)
        ((some k) (match (fieldChain k.pf.expr fields)
          ((some x) (with st :stack (list) :out (cons (KidForm :pf (PosForm :expr x :line k.pf.line :col k.pf.col) :kids k.kids :startOffset k.startOffset :endOffset st.curOffset) (optionOr (listTail st.out) (list))) :fail (none)))
          ((none) bad)))
        ((none) bad)))))

fn symbolAtom st: ReadState t: lx/Token tokStart: Int64 tokEnd: Int64 -> ReadState
  (let [(raw t.rawText)]
    (cond
      ((inModuleForm? st.stack) (emitNode st (rd/makeAtom raw) t.line t.col (list) tokStart tokEnd))
      ((postfixToken? raw) (postfixFields st t))
      (else (emitNode st (dotName raw) t.line t.col (list) tokStart tokEnd))))

fn readToken st: ReadState t: lx/Token -> ReadState
  (let [(tokLen (stringLength t.rawText))
        (tokStart st.curOffset)
        (tokEnd (+ tokStart tokLen))
        (advSt (with st :fail (none) :curOffset tokEnd))]
    (match t.kind
      ((lx/tokLparen) (pushFrame advSt true t))
      ((lx/tokLbracket) (pushFrame advSt false t))
      ((lx/tokRparen) (closeFrame advSt true t))
      ((lx/tokRbracket) (closeFrame advSt false t))
      ((lx/tokEof) (finishRead advSt))
      ((lx/tokError m) (readFail advSt m t.line t.col))
      ((lx/tokSymbol _) (symbolAtom advSt t tokStart tokEnd))
      (_ (emitNode advSt (rd/makeAtom t.rawText) t.line t.col (list) tokStart tokEnd))))

fn readStep st: ReadState t: lx/Token -> ReadState
  (match st.fail ((some _) st) ((none) (readToken st t)))

fn readKidForms toks: (List lx/Token) -> (Result (List KidForm) ParseError)
  (let [(st (fold readStep (ReadState :stack (list) :out (list) :fail (none) :curOffset 0) toks))]
    (match st.fail ((some e) (err e)) ((none) (ok (listReverse st.out)))))

fn readForms toks: (List lx/Token) -> (Result (List PosForm) ParseError)
  (resultMap (readKidForms toks) (fn [(ks (List KidForm))] -> (List PosForm) (map (fn [(k KidForm)] -> PosForm k.pf) ks)))

fn perr msg: String pf: PosForm -> ParseError
  (ParseError :msg msg :line pf.line :col pf.col)

fn wordByte? c: Int64 -> Bool
  (or (and (>= c 97) (<= c 122)) (or (and (>= c 65) (<= c 90)) (or (and (>= c 48) (<= c 57)) (or (= c 45) (or (= c 95) (or (= c 63) (= c 33)))))))

; (:m :ref CHECKER-R1GAPS :do "the type checker and constant-assert/export-resolution walks place a diagnostic at the enclosing statement's or function's position (the only position any of them track), never at the specific offending subform; findTokenPos recovers the real position by a plain word-boundary text search for the offending token's own source spelling, starting at or after a known floor position and falling back to that floor if the needle is not found, so a caller that already knows WHICH token is at fault (a literal, a name, an operator's opening paren) can report where it actually is without threading byte offsets through every expression-evaluation frame")
fn wordChar? ch: String -> Bool
  (and (= (stringLength ch) 1) (wordByte? (charCode ch)))

fn lineColToOffset src: String line: Int64 col: Int64 -> Int64
  (let [(lines (stringLines src))
        (before (optionOr (listSlice lines 0 (- line 1)) (list)))
        (sumBefore (fold (fn [(acc Int64) (l String)] -> Int64 (+ acc (+ (stringLength l) 1))) 0 before))]
    (+ sumBefore (- col 1)))

fn offsetToLineCol src: String offset: Int64 -> (Pair Int64 Int64)
  (let [(pre (optionOr (stringSlice src 0 offset) src))
        (lines (stringLines pre))
        (n (listLength lines))]
    (if (<= n 1) (pair 1 (+ (stringLength pre) 1)) (pair n (+ (stringLength (optionOr (listLast lines) "")) 1))))

fn boundaryOk? src: String start: Int64 end: Int64 needle: String -> Bool
  (let [(beforeCh (optionOr (stringSlice src (- start 1) start) ""))
        (afterCh (optionOr (stringSlice src end (+ end 1)) ""))
        (needleHeadWord (wordChar? (optionOr (stringSlice needle 0 1) "")))
        (needleTailWord (wordChar? (optionOr (stringSlice needle (- (stringLength needle) 1) (stringLength needle)) "")))]
    (and (or (not needleHeadWord) (not (wordChar? beforeCh))) (or (not needleTailWord) (not (wordChar? afterCh)))))

fn tailrec findNeedleFrom src: String floorOffset: Int64 needle: String -> (Option Int64)
  (if (or (> floorOffset (stringLength src)) (stringEmpty? needle)) (none)
    (match (stringIndexOf (optionOr (stringSlice src floorOffset (stringLength src)) "") needle)
      ((none) (none))
      ((some relIdx)
        (let [(start (+ floorOffset relIdx)) (endOff (+ start (stringLength needle)))]
          (if (boundaryOk? src start endOff needle) (some start) (findNeedleFrom src (+ start 1) needle))))))

fn findTokenPos src: String floorLine: Int64 floorCol: Int64 needle: String -> (Pair Int64 Int64)
  (match (findNeedleFrom src (lineColToOffset src floorLine floorCol) needle)
    ((some off) (offsetToLineCol src off))
    ((none) (pair floorLine floorCol)))

; (:m :ref CHECKER-R1GAPS :do "an unexported member is diagnosed by its bare name (member, case tag, or type name), but when the source wrote it qualified (alias/member) the expected position is the start of the whole qualified token, not just the member part; qualifierStart walks left from a found member's offset across a leading '/' and the alias's own word characters, so findQualifiedTokenPos lands on 'alias' in 'alias/member' while still landing on a bare 'member' when there is no alias to walk back across")
fn tailrec qualifierStart src: String idx: Int64 -> Int64
  (if (<= idx 0) 0
    (if (wordChar? (optionOr (stringSlice src (- idx 1) idx) "")) (qualifierStart src (- idx 1)) idx))

; (:m :ref CHECKER-R1GAPS :do "a parameter's type annotation is diagnosed at the function's first body statement (the only position resolve.asl's checkModuleRules tracks for it), which is textually AFTER the parameter list the offending type name lives in, so a forward-only search from that floor never finds it; lastNeedleBefore scans the whole prefix up to the floor and keeps the latest match, giving findQualifiedTokenPos a fallback for names that sit before their recorded floor as well as after it")
fn tailrec lastNeedleBefore src: String needle: String searchFrom: Int64 ceilOffset: Int64 best: (Option Int64) -> (Option Int64)
  (match (findNeedleFrom src searchFrom needle)
    ((none) best)
    ((some off)
      (if (>= off ceilOffset) best
        (lastNeedleBefore src needle (+ off 1) ceilOffset (some off)))))

fn findQualifiedTokenPos src: String floorLine: Int64 floorCol: Int64 needle: String -> (Pair Int64 Int64)
  (let [(floorOff (lineColToOffset src floorLine floorCol))]
    (match (match (findNeedleFrom src floorOff needle) ((some off) (some off)) ((none) (lastNeedleBefore src needle 0 floorOff (none))))
      ((none) (pair floorLine floorCol))
      ((some off)
        (let [(extended (if (= (optionOr (stringSlice src (- off 1) off) "") "/") (qualifierStart src (- off 1)) off))]
          (offsetToLineCol src extended)))))

fn commentLeadEnd bs: Bytes e: Int64 i: Int64 -> Int64
  (if (and (< i e) (or (= (bytesGet bs i) 59) (or (= (bytesGet bs i) 32) (= (bytesGet bs i) 9)))) (commentLeadEnd bs e (+ i 1)) i)

fn bytesAt? bs: Bytes e: Int64 i: Int64 w: String -> Bool
  (let [(wb (stringToBytes w)) (m (bytesLength wb))]
    (and (<= (+ i m) e) (listAll? (fn [k] (= (bytesGet bs (+ i k)) (bytesGet wb k))) (range 0 m))))

fn whyAt? bs: Bytes e: Int64 i: Int64 -> Bool
  (cond
    ((> (+ i 4) e) false)
    ((and (bytesAt? bs e i ":why") (or (= (+ i 4) e) (not (wordByte? (bytesGet bs (+ i 4)))))) true)
    (else (whyAt? bs e (+ i 1))))

fn metaComment? bs: Bytes at: Int64 e: Int64 -> Bool
  (let [(i (commentLeadEnd bs e at))]
    (and (bytesAt? bs e i "(:m") (and (< (+ i 3) e) (and (not (wordByte? (bytesGet bs (+ i 3)))) (not (whyAt? bs e i))))))

fn freeCommentAt bs: Bytes n: Int64 i: Int64 -> (Option Int64)
  (if (>= i n) (none)
    (let [(c (bytesGet bs i))]
      (cond
        ((= c 34) (freeCommentAt bs n (stringEndAt bs n (+ i 1))))
        ((= c 59) (let [(e (lineEndAt bs n i))] (if (metaComment? bs i e) (freeCommentAt bs n e) (some i))))
        (else (freeCommentAt bs n (+ i 1))))))

(schema DocFrame (:f head String) (:f n Int64) (:f prevD Bool))

(schema DocScan (:f stack (List DocFrame)) (:f group DocFrame) (:f hit (Option lx/Token)))

fn docHead? head: String idx: Int64 -> Bool
  (cond
    ((or (= head "module") (or (= head "fn") (or (= head "df") (= head "defn")))) (>= idx 1))
    ((or (= head "schema") (= head "enum")) (= idx 2))
    (else false))

fn closer? t: lx/Token -> Bool
  (match t.kind ((lx/tokRparen) true) ((lx/tokRbracket) true) ((lx/tokSymbol _) (= t.rawText "}")) (_ false))

fn opener t: lx/Token -> (Option DocFrame)
  (match t.kind
    ((lx/tokLparen) (some (DocFrame :head "" :n 0 :prevD false)))
    ((lx/tokLbracket) (some (DocFrame :head "[" :n 1 :prevD false)))
    ((lx/tokSymbol _) (if (= t.rawText "{") (some (DocFrame :head "{" :n 1 :prevD false)) (none)))
    (_ (none)))

fn kidOf f: DocFrame t: lx/Token -> DocFrame
  (with f
    :head (if (= f.n 0) (match t.kind ((lx/tokSymbol _) t.rawText) (_ "")) f.head)
    :n (+ f.n 1)
    :prevD (match t.kind ((lx/tokKeyword _) (or (= t.rawText ":d") (= t.rawText ":doc"))) (_ false)))

fn docHit? f: DocFrame t: lx/Token grouped: Bool -> Bool
  (and (match t.kind ((lx/tokString _) true) (_ false))
    (and f.prevD (if grouped (= f.head "fn") (docHead? f.head (- f.n 1)))))

fn docKid st: DocScan t: lx/Token -> DocScan
  (let [(grouped (listEmpty? st.stack))
        (parent (optionOr (listHead st.stack) st.group))
        (hit (if (docHit? parent t grouped) (some t) (none)))
        (updated (kidOf parent t))
        (rest (optionOr (listTail st.stack) (list)))
        (placed (if grouped (with st :group updated :hit hit) (with st :stack (cons updated rest) :hit hit)))]
    (match (opener t)
      ((some f) (DocScan :stack (cons f placed.stack) :group placed.group :hit placed.hit))
      ((none) placed)))

fn docStep st: DocScan t: lx/Token -> DocScan
  (cond
    ((some? st.hit) st)
    ((closer? t) (with st :stack (optionOr (listTail st.stack) (list))))
    ((match t.kind ((lx/tokEof) true) (_ false)) st)
    ((and (listEmpty? st.stack) (= t.col 1)) (docKid (with st :group (DocFrame :head "" :n 0 :prevD false)) t))
    (else (docKid st t)))

fn lineOfByte bs: Bytes at: Int64 -> Int64
  (+ 1 (listLength (filter (fn [k] (= (bytesGet bs k) 10)) (range 0 at))))

fn keywordEnd? bs: Bytes n: Int64 j: Int64 -> Bool
  (or (>= j n)
    (let [(b (bytesGet bs j))]
      (or (= b 32) (or (= b 9) (or (= b 10) (or (= b 13) (or (= b 40) (or (= b 41) (or (= b 91) (or (= b 93) (or (= b 123) (or (= b 125) (or (= b 34) (or (= b 59) (or (= b 58) (= b 64))))))))))))))))

fn docKeywordAt? bs: Bytes n: Int64 i: Int64 -> Bool
  (cond
    ((>= (+ i 1) n) false)
    ((and (= (bytesGet bs i) 58) (= (bytesGet bs (+ i 1)) 100))
     (if (or (keywordEnd? bs n (+ i 2)) (and (< (+ i 3) n) (and (= (bytesGet bs (+ i 2)) 111) (and (= (bytesGet bs (+ i 3)) 99) (keywordEnd? bs n (+ i 4))))))
       true
       (docKeywordAt? bs n (+ i 2))))
    (else (docKeywordAt? bs n (+ i 1))))

fn isBareLiteralAtom text: String -> Bool
  (or (stringStartsWith? text "\"")
      (or (stringStartsWith? text ":")
          (or (lx/isDigit (lx/charAt text 0))
              (and (= (lx/charAt text 0) "-") (lx/isDigit (lx/charAt text 1))))))

fn findBareLiteralTopExpr forms: (List TopForm) -> (Option PosForm)
  (match (listHead forms)
    ((none) (none))
    ((some f)
      (match f
        ((topExpr pf)
         (if (and (rd/isAtom? pf.expr) (isBareLiteralAtom (rd/sexprHead pf.expr)))
           (some pf)
           (findBareLiteralTopExpr (optionOr (listTail forms) (list)))))
        (_ (findBareLiteralTopExpr (optionOr (listTail forms) (list)))))))

fn rejectBareLiteralTopExpr forms: (List TopForm) -> (Result (List TopForm) ParseError)
  (match (findBareLiteralTopExpr forms)
    ((some pf) (err (perr (str "ERR_READ_BARE_TOPLEVEL a bare literal '" (rd/sexprHead pf.expr) "' is not a top-level form; move it into a declaration or the package's doc.asn") pf)))
    ((none) (ok forms)))

fn retiredProse src: String -> (Option ParseError)
  (let [(bs (stringToBytes src)) (n (bytesLength bs))]
    (match (freeCommentAt bs n 0)
      ((some at) (some (ParseError :msg "ERR_READ_COMMENT free ; comments and (:m :why ...) are retired: move the text to the package doc.asn (asl doc); a comment is one ; (:m ...) meta form" :line (lineOfByte bs at) :col 1)))
      ((none)
        (if (not (docKeywordAt? bs n 0))
          (none)
          (match (fold docStep (DocScan :stack (list) :group (DocFrame :head "" :n 0 :prevD false) :hit (none)) (lx/tokenize src)).hit
            ((some t) (some (ParseError :msg "ERR_READ_DOC :d docstrings are retired: move the text to the package doc.asn (asl doc)" :line t.line :col t.col)))
            ((none) (none)))))))

(schema SpellScan (:f before String) (:f prev String) (:f opens (List String)) (:f errs (List ParseError)))

fn bangedBuiltins -> (List String)
  (list "bytesFromBase64" "bytesSet" "bytesSetFloat64" "bytesSha256" "cpuCount" "dirCreate" "dirList" "envGet" "envList" "eprintln" "execCmd" "fdClose" "fdNonBlocking" "fdPoll" "fdRead" "fdWrite" "file-append" "fileAppend" "fileChmod" "fileCreateExclusive" "fileExists?" "fileFsync" "fileLock" "fileLockAt" "fileLockWait" "fileLstat" "fileReadAt" "fileReadBytes" "fileReadlink" "fileReadRange" "fileReadString" "fileSize" "fileStat" "fileUtime" "fileWrite" "fileWriteAt" "getHomeDir" "localDate" "monotonicNs" "nowNs" "parquetOpen" "parquetReadF64" "parquetReadI64" "parquetReadI8" "pathRemove" "pathRename" "pathSymlink" "platformInfo" "preludeB64Dec" "print" "println" "procAlive?" "processRun" "processSpawn" "processWait" "procExecv" "procExePath" "procKill" "procPoll" "procRusage" "procSelf" "procSpawnv" "procWaitAny" "procWaitPid" "read-all" "read-line" "realPath" "sleepMs" "sockAccept" "sockLocalPort" "sockRecvFd" "sockSendFd" "tcpConnect" "tcpListen" "unixConnect" "unixListen" "unixSocketPair" "zstdAslBackwardInit" "zstdAslBackwardRead" "zstdAslBlocks" "zstdAslCountBlockDone" "zstdAslCountBlocks" "zstdAslDecompress" "zstdAslFillFseNorms" "zstdAslFinishFrame" "zstdAslForwardBits" "zstdAslForwardBitsLoop" "zstdAslFseBuildCell" "zstdAslFseBuildNorms" "zstdAslFseCountFinish" "zstdAslFseCounts" "zstdAslFseDecodeStep" "zstdAslFseInit" "zstdAslFseRead" "zstdAslFseSpread" "zstdAslFseSpreadOne" "zstdAslFseSpreadSkip" "zstdAslFseWeightLoop" "zstdAslFseZeroRun" "zstdAslHufBuild" "zstdAslHufCached" "zstdAslHufCheckWeights" "zstdAslHufCountWeights" "zstdAslHufDirectWeights" "zstdAslHufFill" "zstdAslHufFour" "zstdAslHufFseWeights" "zstdAslHufLiterals" "zstdAslHufOne" "zstdAslHufRead" "zstdAslHufSet16" "zstdAslHufSpread" "zstdAslHufStarts" "zstdAslHufStream" "zstdAslLiteralBlock" "zstdAslNormInit" "zstdAslNormSet" "zstdAslNormZeroRun" "zstdAslRepGet" "zstdAslRepSet" "zstdAslSeqLoad" "zstdAslSeqSave" "zstdAslSeqStateCopy" "zstdAslSeqTable" "zstdAslSequenceAdvance" "zstdAslSequenceCopy" "zstdAslSequenceMatch" "zstdAslSequenceRun" "zstdAslSequences" "zstdAslSequencesTables" "zstdAslSetRaw" "zstdAslSetRle" "zstdDecompress")

fn spellingOpen? x: String -> Bool
  (or (= x "(") (or (= x "[") (= x "{")))

fn spellingClose? x: String -> Bool
  (or (= x ")") (or (= x "]") (= x "}")))

fn spellingSymbol? t: lx/Token -> Bool
  (match t.kind ((lx/tokSymbol _) true) (_ false))

fn bindingPairAt? opens: (List String) before: String -> Bool
  (and (listContains? (list "[ let" "[ fn") (optionOr (listGet opens 1) "")) (or (= before "[") (= before ")")))

fn retiredHeadMessage x: String -> String
  (cond
    ((= x "mt") "ERR_READ_SPELLING (mt subject arm ...) is retired: write (match subject arm ...)")
    ((= x "==") "ERR_READ_SPELLING (== a b) is retired: write (= a b)")
    ((= x "not=") "ERR_READ_SPELLING (not= a b) is retired: write (!= a b)")
    ((= x "%") "ERR_READ_SPELLING (% a b) is not ASL: write (mod a b)")
    (else ""))

; (:m :ref MISS-ABSORB :do "foreign heads the reader takes as their canonical spelling instead of failing: every model of the 2026-11-13 generation bench wrote (== a b) and (% a b), and a rejection costs a model turn while the meaning is not in doubt; spellingErrors and retiredFormErrors still report them, so audits of stored text and asl heal keep the corpus canonical")
fn acceptedHead x: String -> String
  (cond ((= x "==") "= ") ((= x "%") "mod") (else ""))

fn acceptedSpelling? e: ParseError -> Bool
  (or (stringStartsWith? e.msg "ERR_READ_SPELLING (== ") (stringStartsWith? e.msg "ERR_READ_SPELLING (% "))

fn swapHeadAt ln: String col: Int64 -> String
  (let [(n (stringLength ln))
        (from (optionOr (stringSlice ln (- col 1) n) ""))
        (was (if (stringStartsWith? from "==") "==" (if (stringStartsWith? from "%") "%" "")))]
    (if (stringEmpty? was)
      ln
      (str (optionOr (stringSlice ln 0 (- col 1)) "") (acceptedHead was) (optionOr (stringSlice from (stringLength was) (stringLength from)) ""))))

; (:m :ref MISS-ABSORB :do "errs arrive sorted by position; the swaps of one line are applied right to left so an earlier column stays valid after (% grows to (mod")
fn acceptSwaps src: String errs: (List ParseError) -> String
  (if (listEmpty? errs)
    src
    (stringJoin
      (map (fn [(p (Pair Int64 String))] -> String
             (fold (fn [(ln String) (e ParseError)] -> String (if (= e.line (+ (pairFirst p) 1)) (swapHeadAt ln e.col) ln))
                   (pairSecond p) (listReverse errs)))
           (zip (range 0 (listLength (stringSplit src "\n"))) (stringSplit src "\n")))
      "\n"))

fn spellingErr msg: String t: lx/Token -> ParseError
  (ParseError :msg msg :line t.line :col t.col)

; (:m :ref SYN-ARMS-DECISION-20261016 :do "fn ! name stays (E9) and builtins stay bare (E10, reverses EFFECT-BUILTINS-BANG): neither is a retired form any more, so spellingStep only flags the three still-genuine retired heads (mt/==/not=); the earlier fn-header mark check (fnMarkMessage) and bare-builtin-call check (bangedBuiltinMessage/scanErrors' bang arm) are dropped from this scanner, not just from retiredFormErrors (AGENTSURFACE-BANG-STALE already dropped the bang arm there)")
fn spellingStep st: SpellScan t: lx/Token -> SpellScan
  (let [(x t.rawText)
        (afterOpen (= st.prev "("))
        (head (and afterOpen (and (spellingSymbol? t) (not (bindingPairAt? st.opens st.before)))))
        (opens (cond ((spellingOpen? x) (cons (str x " " st.prev) st.opens)) ((spellingClose? x) (optionOr (listTail st.opens) (list))) (else st.opens)))
        (headMsg (if head (retiredHeadMessage x) ""))
        (errs (if (stringEmpty? headMsg) st.errs (cons (spellingErr headMsg t) st.errs)))]
    (with st :before st.prev :prev x :opens opens :errs errs))

fn spellingScan src: String -> SpellScan
  (fold spellingStep (SpellScan :before "" :prev "" :opens (list) :errs (list)) (lx/tokenize src))

fn scanErrors st: SpellScan -> (List ParseError)
  (listSortBy (fn [(e ParseError)] -> Int64 (+ (* e.line 100000) e.col)) (listReverse st.errs))

fn spellingErrors src: String -> (List ParseError)
  (scanErrors (spellingScan src))

fn retiredFormErrors src: String -> (List ParseError)
  (listReverse (spellingScan src).errs)

fn mayHoldRetiredHead? src: String -> Bool
  (or (stringContains? src "mt") (or (stringContains? src "==") (or (stringContains? src "not=") (stringContains? src "(%"))))

fn retiredSpelling src: String -> (Option ParseError)
  (if (mayHoldRetiredHead? src) (listHead (scanErrors (spellingScan src))) (none))

fn retiredSource src: String -> (Option ParseError)
  (match (retiredProse src) ((some e) (some e)) ((none) (retiredSpelling src)))

; (:m :ref MISS-ABSORB :do "the text the parser reads: a retired form is an error, an accepted foreign head is swapped for its canonical spelling; (== keeps every column, (% moves the rest of its line right by two")
fn readableSource src: String -> (Result String ParseError)
  (match (retiredProse src)
    ((some e) (err e))
    ((none)
      (if (not (mayHoldRetiredHead? src))
        (ok src)
        (let [(errs (scanErrors (spellingScan src)))]
          (match (listFind (fn [(e ParseError)] -> Bool (not (acceptedSpelling? e))) errs)
            ((some e) (err e))
            ((none) (ok (acceptSwaps src errs))))))))

; (:m :ref SHEBANG :do "a first line starting with #! is blanked before reading, its newline kept so every later line keeps its number; only line 1 is looked at")
fn shebangless src: String -> String
  (if (stringStartsWith? src "#!")
    (match (stringIndexOf src "\n") ((some i) (optionOr (stringSlice src i (stringLength src)) "")) ((none) ""))
    src)

fn parse raw: String -> (Result (List TopForm) ParseError)
  (match (readableSource (shebangless raw))
    ((err e) (err e))
    ((ok src) (match (parseLegacy src)
      ((err e) (err e))
      ((ok forms) (rejectBareLiteralTopExpr forms)))))

fn parseForTypeCheck raw: String -> (Result (List TopForm) ParseError)
  (match (readableSource (shebangless raw))
    ((err e) (err e))
    ((ok src) (match (parseForChecker src)
      ((err e) (err e))
      ((ok forms) (rejectBareLiteralTopExpr (desugarWith forms))))))

fn parseLegacy src: String -> (Result (List TopForm) ParseError)
  (match (parseForChecker src)
    ((ok forms) (ok (desugarWith (map displayUntypedParams forms))))
    ((err pe) (err pe)))

(schema WithCtx (:f schemas (Map String (List String))) (:f fieldTypes (Map String (Map String String))) (:f rets (Map String String)))

fn localSchemas forms: (List TopForm) -> (Map String (List String))
  (fold (fn [m f] (match f ((topSchema n) (mapSet m n.name (map (fn [x] x.name) n.fields))) (_ m))) (mapEmpty) forms)

fn localFieldTypes forms: (List TopForm) -> (Map String (Map String String))
  (fold (fn [m f] (match f ((topSchema n) (mapSet m n.name (fold (fn [acc x] (mapSet acc x.name x.type)) (mapEmpty) n.fields))) (_ m))) (mapEmpty) forms)

fn localRets forms: (List TopForm) -> (Map String String)
  (fold (fn [m f] (match f ((topDefun d) (mapSet m d.name d.retType)) (_ m))) (mapEmpty) forms)

fn withCtxOf forms: (List TopForm) -> WithCtx
  (WithCtx :schemas (localSchemas forms) :fieldTypes (localFieldTypes forms) :rets (localRets forms))

fn itemAt items: (List rd/SExpr) i: Int64 -> rd/SExpr
  (optionOr (listGet items i) (rd/makeAtom ""))

fn schemaOr wc: WithCtx t: String -> String
  (if (mapHas? wc.schemas t) t "")

fn exprType wc: WithCtx types: (Map String String) e: rd/SExpr -> String
  (match e
    ((rd/sexprAtom v) (schemaOr wc (optionOr (mapGet types v) "")))
    ((rd/sexprList items)
      (let [(h (rd/sexprHead e))]
        (cond
          ((mapHas? types h) "")
          ((mapHas? wc.schemas h) h)
          ((= h "with") (exprType wc types (itemAt items 1)))
          ((= h "let") (exprType wc (unbind (atomsOf (itemAt items 1)) types) (itemAt items (- (listLength items) 1))))
          ((= h "do") (exprType wc types (itemAt items (- (listLength items) 1))))
          ((and (stringStartsWith? h ".-") (= (listLength items) 2))
            (let [(src (exprType wc types (itemAt items 1)))]
              (schemaOr wc (optionOr (mapGet (optionOr (mapGet wc.fieldTypes src) (mapEmpty)) (optionOr (stringSlice h 2 (stringLength h)) "")) ""))))
          (else (schemaOr wc (optionOr (mapGet wc.rets h) ""))))))
    (_ ""))

fn withPairs items: (List rd/SExpr) acc: (Map String rd/SExpr) -> (Option (Map String rd/SExpr))
  (match (listHead items)
    ((none) (some acc))
    ((some k) (match (listGet items 1)
      ((some v) (if (and (rd/isAtom? k) (stringStartsWith? (rd/sexprHead k) ":"))
                  (withPairs (optionOr (listTail (optionOr (listTail items) (list))) (list)) (mapSet acc (optionOr (stringSlice (rd/sexprHead k) 1 (stringLength (rd/sexprHead k))) "") v))
                  (none)))
      ((none) (none)))))

fn atomsOf e: rd/SExpr -> (List String)
  (match e
    ((rd/sexprAtom v) (list v))
    ((rd/sexprList items) (fold (fn [acc k] (listAppend acc (atomsOf k))) (list) items))
    ((rd/sexprVect items) (fold (fn [acc k] (listAppend acc (atomsOf k))) (list) items)))

fn freshName used: (List String) n: Int64 -> String
  (let [(candidate (str "withSource" n))]
    (if (listContains? used candidate) (freshName used (+ n 1)) candidate))

fn withRecord ty: String fields: (List String) repl: (Map String rd/SExpr) src: rd/SExpr -> rd/SExpr
  (rd/makeList (cons (rd/makeAtom ty) (fold (fn [acc f] (listAppend acc (list (rd/makeAtom (str ":" f)) (optionOr (mapGet repl f) (rd/makeList (list (rd/makeAtom (str ".-" f)) src)))))) (list) fields)))

fn withExpand wc: WithCtx types: (Map String String) items: (List rd/SExpr) -> (Option rd/SExpr)
  (let [(x (itemAt items 1))
        (ty (exprType wc types x))]
    (match (mapGet wc.schemas ty)
      ((none) (none))
      ((some fields) (match (withPairs (optionOr (listTail (optionOr (listTail items) (list))) (list)) (mapEmpty))
        ((none) (none))
        ((some repl)
          (cond
            ((not (listAll? (fn [k] (listContains? fields k)) (mapKeys repl))) (none))
            ((rd/isAtom? x) (some (withRecord ty fields repl x)))
            (else
              (let [(s (freshName (atomsOf (rd/makeList items)) 0))]
                (some (rd/makeList (list (rd/makeAtom "let")
                                         (rd/makeVect (list (rd/makeList (list (rd/makeAtom s) x))))
                                         (withRecord ty fields repl (rd/makeAtom s)))))))))))))

fn unbind types: (List String) m: (Map String String) -> (Map String String)
  (fold (fn [acc v] (mapSet acc v "")) m types)

fn bindingParts b: rd/SExpr -> (List rd/SExpr)
  (rd/sexprToList b)

fn withBinding wc: WithCtx acc: (Pair (Map String String) (List rd/SExpr)) b: rd/SExpr -> (Pair (Map String String) (List rd/SExpr))
  (let [(types (pairFirst acc))
        (parts (bindingParts b))
        (n (listLength parts))
        (name (rd/sexprHead (itemAt parts 0)))
        (value (withExpr wc types (itemAt parts (- n 1))))
        (declared (if (= n 3) (schemaOr wc (rd/sexprHead (itemAt parts 1))) ""))
        (t (if (stringEmpty? declared) (exprType wc types value) declared))
        (rebuilt (if (= n 3) (rd/makeList (list (itemAt parts 0) (itemAt parts 1) value)) (rd/makeList (list (itemAt parts 0) value))))]
    (if (and (rd/isList? b) (or (= n 2) (= n 3)))
      (pair (mapSet types name t) (listAppend (pairSecond acc) (list rebuilt)))
      (pair types (listAppend (pairSecond acc) (list (withExpr wc types b))))))

fn pairsOf items: (List rd/SExpr) -> (List rd/SExpr)
  (if (< (listLength items) 2)
    (list)
    (cons (rd/makeList (list (itemAt items 0) (itemAt items 1))) (pairsOf (optionOr (listTail (optionOr (listTail items) (list))) (list)))))

fn flatten pairs: (List rd/SExpr) -> (List rd/SExpr)
  (fold (fn [acc p] (listAppend acc (rd/sexprToList p))) (list) pairs)

fn bindingItems vec: rd/SExpr -> (Option (List rd/SExpr))
  (cond
    ((rd/isVect? vec) (some (rd/sexprToList vec)))
    ((and (rd/isList? vec) (= (rd/sexprHead vec) "list")) (some (optionOr (listTail (rd/sexprToList vec)) (list))))
    (else (none)))

fn withLet wc: WithCtx types: (Map String String) items: (List rd/SExpr) -> rd/SExpr
  (let [(vec (itemAt items 1))]
    (match (bindingItems vec)
      ((none) (rd/makeList (map (fn [k] (withExpr wc types k)) items)))
      ((some bs)
        (let [(flat (and (not (listEmpty? bs)) (rd/isAtom? (itemAt bs 0))))
              (bound (fold (fn [acc b] (withBinding wc acc b)) (pair types (list)) (if flat (pairsOf bs) bs)))
              (newBs (if flat (flatten (pairSecond bound)) (pairSecond bound)))
              (body (map (fn [k] (withExpr wc (pairFirst bound) k)) (optionOr (listTail (optionOr (listTail items) (list))) (list))))
              (newVec (if (rd/isVect? vec) (rd/makeVect newBs) (rd/makeList (cons (rd/makeAtom "list") newBs))))]
          (rd/makeList (cons (itemAt items 0) (cons newVec body)))))))

fn withArm wc: WithCtx types: (Map String String) arm: rd/SExpr -> rd/SExpr
  (match arm
    ((rd/sexprList parts)
      (let [(inner (unbind (atomsOf (itemAt parts 0)) types))]
        (rd/makeList (cons (itemAt parts 0) (map (fn [k] (withExpr wc inner k)) (optionOr (listTail parts) (list)))))))
    (_ (withExpr wc types arm)))

fn withExpr wc: WithCtx types: (Map String String) e: rd/SExpr -> rd/SExpr
  (match e
    ((rd/sexprList items)
      (let [(h (rd/sexprHead e))]
        (cond
          ((= h "let") (withLet wc types items))
          ((= h "match")
            (rd/makeList (cons (itemAt items 0) (cons (withExpr wc types (itemAt items 1)) (map (fn [a] (withArm wc types a)) (optionOr (listTail (optionOr (listTail items) (list))) (list)))))))
          ((or (= h "fn") (= h "lambda"))
            (let [(inner (unbind (atomsOf (itemAt items 1)) types))]
              (rd/makeList (cons (itemAt items 0) (map (fn [k] (withExpr wc inner k)) (optionOr (listTail items) (list)))))))
          (else
            (let [(inner (map (fn [k] (withExpr wc types k)) items))]
              (if (= h "with") (optionOr (withExpand wc types inner) (rd/makeList inner)) (rd/makeList inner)))))))
    ((rd/sexprVect items) (rd/makeVect (map (fn [k] (withExpr wc types k)) items)))
    (_ e))

fn desugarWith forms: (List TopForm) -> (List TopForm)
  (desugarWithIn (withCtxOf forms) forms)

fn desugarWithIn wc: WithCtx forms: (List TopForm) -> (List TopForm)
  (map (fn [f] (match f
                 ((topDefun d)
                   (let [(types (fold (fn [m p] (mapSet m p.name p.type)) (mapEmpty) d.params))]
                     (topDefun (DefunNode :name d.name :typeVars d.typeVars :isExported d.isExported :effect d.effect :params d.params :retType d.retType :docstring d.docstring
                                          :body (map (fn [b] (withExpr wc types b)) d.body)
                                          :bodyPos (map (fn [pf] (PosForm :expr (withExpr wc types pf.expr) :line pf.line :col pf.col)) d.bodyPos)))))
                 ((topModule m) (topModule (ModuleNode :path m.path :docstring m.docstring :exported m.exported :imports m.imports :defs (desugarWithIn (withCtxOf m.defs) m.defs))))
                 (_ f)))
       forms)

fn parseForChecker src: String -> (Result (List TopForm) ParseError)
  (parseWithFallback (shebangless src))

fn displayUntypedParam p: Param -> Param
  (with p :type (if (stringEmpty? p.type) "Any" p.type))

fn displayUntypedParams form: TopForm -> TopForm
  (match form
    ((topModule m)
     (topModule (ModuleNode :path m.path :docstring m.docstring :exported m.exported :imports m.imports :defs (map displayUntypedParams m.defs))))
    ((topDefun d)
     (topDefun (DefunNode :name d.name :typeVars d.typeVars :isExported d.isExported :effect d.effect :params (map displayUntypedParam d.params) :retType d.retType :docstring d.docstring :body d.body :bodyPos d.bodyPos)))
    (_ form))

fn moduleForm? pf: PosForm -> Bool
  (and (rd/isList? pf.expr) (= (rd/sexprHead pf.expr) "module"))

fn secondForm forms: (List PosForm) -> (Option PosForm)
  (match (listTail forms) ((some r) (listHead r)) ((none) (none)))

fn checkModPath m: PosForm -> (Result String ParseError)
  (let [(p (nthString (sexprItems m.expr) 1))] (if (modPath? p) (ok p) (err (perr "module header needs a path" m))))

fn modulePath mods: (List PosForm) -> (Result String ParseError)
  (match (secondForm mods) ((some extra) (err (perr "a second module header" extra))) ((none) (match (listHead mods) ((some m) (checkModPath m)) ((none) (ok "")))))

fn isModulePosForm? p: PosForm -> Bool
  (moduleForm? p)

fn isNotModulePosForm? p: PosForm -> Bool
  (not (moduleForm? p))

fn modsExported mods: (List PosForm) -> (List String)
  (match (listHead mods) ((some m) (moduleExported m.expr)) ((none) (list)))

fn scriptEntries decls: (List TopForm) -> (List String)
  (let [(names (fold (fn [acc t] (match t ((topDefun d) (if (or (= d.name "main") (= d.name "runTests")) (cons d.name acc) acc)) (_ acc))) (list) decls))]
    (listReverse names))

; (:m :ref IMPLICIT-MODULE :do "a source with no module header that defines main or runTests is a script module: the parser synthesises its header with an empty path (the loader names it from its file), no imports and those entries exported; a headerless source without an entry stays a bare fragment")
; (:m :ref TOP-LEVEL-CODE :do "column-0 code forms of a headerless source become the body of a synthesised effectful main args: (List String) -> (Result Int64 String), run in order; each is wrapped in a preludeScriptStep marker carrying its form number, line and column, so the checker types it and places its diagnostics at its own statement, and the linker elaborates a Result-valued step into an early exit; a let with no body scopes over the forms after it; (use path ...) forms become imports aliased by their last segment")
fn scriptStatement? t: TopForm -> Bool
  (match t
    ((topExpr pf) (and (rd/isList? pf.expr) (let [(h (rd/sexprHead pf.expr))] (and (not (stringEmpty? h)) (and (not (stringStartsWith? h ":")) (!= h "use"))))))
    (_ false))

fn useForm? t: TopForm -> Bool
  (match t ((topExpr pf) (and (rd/isList? pf.expr) (= (rd/sexprHead pf.expr) "use"))) (_ false))

fn lastSegment p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn useImports decls: (List TopForm) -> (List (Pair String String))
  (fold (fn [acc t] (match t ((topExpr pf) (if (useForm? t) (listAppend acc (map (fn [m] (pair (rd/sexprHead m) (lastSegment (rd/sexprHead m)))) (tailExprs (sexprItems pf.expr)))) acc)) (_ acc))) (list) decls)

fn scriptStatements decls: (List TopForm) -> (List PosForm)
  (fold (fn [acc t] (match t ((topExpr pf) (if (scriptStatement? t) (listAppend acc (list pf)) acc)) (_ acc))) (list) decls)

fn scriptStepAt n: Int64 pf: PosForm e: rd/SExpr -> rd/SExpr
  (rd/makeList (list (rd/makeAtom "preludeScriptStep") (rd/makeAtom (stringFromInt64 n)) (rd/makeAtom (stringFromInt64 pf.line)) (rd/makeAtom (stringFromInt64 pf.col)) e))

fn scriptStepParts e: rd/SExpr -> (Option (List rd/SExpr))
  (let [(items (sexprItems e))]
    (if (and (rd/isList? e) (and (= (rd/sexprHead e) "preludeScriptStep") (= (listLength items) 5))) (some (tailExprs items)) (none)))

fn scriptLet? e: rd/SExpr -> Bool
  (and (rd/isList? e) (and (= (rd/sexprHead e) "let") (and (= (listLength (sexprItems e)) 2) (some? (bindingItems (nthExpr (sexprItems e) 1))))))

fn scriptBinding n: Int64 pf: PosForm b: rd/SExpr -> rd/SExpr
  (let [(items (sexprItems b)) (k (listLength items))]
    (if (and (rd/isList? b) (>= k 2)) (rd/makeList (listAppend (listTake items (- k 1)) (list (scriptStepAt n pf (nthExpr items (- k 1)))))) b))

fn scriptBindings n: Int64 pf: PosForm vec: rd/SExpr -> rd/SExpr
  (let [(items (optionOr (bindingItems vec) (list)))]
    (if (rd/isAtom? (nthExpr items 0))
      (rd/makeVect (map (fn [i] (if (= (mod i 2) 1) (scriptStepAt n pf (nthExpr items i)) (nthExpr items i))) (range 0 (listLength items))))
      (rd/makeVect (map (fn [b] (scriptBinding n pf b)) items))))

fn scriptDo acc: (List rd/SExpr) last: rd/SExpr -> rd/SExpr
  (if (listEmpty? acc) last (rd/makeList (cons (rd/makeAtom "do") (listReverse (cons last acc)))))

fn scriptRun stmts: (List PosForm) n: Int64 acc: (List rd/SExpr) -> rd/SExpr
  (match (listHead stmts)
    ((none) (scriptDo acc (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "0")))))
    ((some pf) (if (scriptLet? pf.expr)
                 (scriptDo acc (rd/makeList (list (rd/makeAtom "let") (scriptBindings n pf (nthExpr (sexprItems pf.expr) 1)) (scriptRun (tailExprsPos stmts) (+ n 1) (list)))))
                 (scriptRun (tailExprsPos stmts) (+ n 1) (cons (scriptStepAt n pf pf.expr) acc)))))

fn tailExprsPos xs: (List PosForm) -> (List PosForm)
  (optionOr (listTail xs) (list))

; (:m :ref TOP-LEVEL-CODE :do "the inverse of scriptRun: the code forms a synthesised script main was built from, markers removed, so a printer writes the script back as its author wrote it")
fn unstep e: rd/SExpr -> rd/SExpr
  (match (scriptStepParts e) ((some sp) (nthExpr sp 3)) ((none) e))

fn unstepBinding b: rd/SExpr -> rd/SExpr
  (let [(items (sexprItems b)) (k (listLength items))]
    (cond ((some? (scriptStepParts b)) (unstep b))
          ((and (rd/isList? b) (>= k 2)) (rd/makeList (listAppend (listTake items (- k 1)) (list (unstep (nthExpr items (- k 1)))))))
          (else b)))

fn scriptStatementsOf e: rd/SExpr -> (List rd/SExpr)
  (let [(items (sexprItems e)) (h (rd/sexprHead e))]
    (cond
      ((and (rd/isList? e) (= h "do")) (let [(body (tailExprs items)) (n (listLength body))]
                                          (listAppend (map unstep (listTake body (- n 1))) (scriptStatementsOf (nthExpr body (- n 1))))))
      ((and (rd/isList? e) (and (= h "let") (= (listLength items) 3)))
        (cons (rd/makeList (list (rd/makeAtom "let") (rd/makeVect (map unstepBinding (sexprItems (nthExpr items 1)))))) (scriptStatementsOf (nthExpr items 2))))
      ((and (rd/isList? e) (= h "ok")) (list))
      (else (list (unstep e)))))

fn scriptMainDoc -> String
  "the top-level code of this script"

fn scriptMain stmts: (List PosForm) -> TopForm
  (topDefun (DefunNode :name "main" :typeVars (list) :isExported true :effect true :params (list (Param :name "args" :type "(List String)")) :retType "(Result Int64 String)" :docstring (scriptMainDoc) :body (list (scriptRun stmts 1 (list))) :bodyPos (listTake stmts 1)))

fn scriptCode decls: (List TopForm) -> (Result (List TopForm) ParseError)
  (let [(stmts (scriptStatements decls)) (items (filter (fn [t] (not (or (scriptStatement? t) (useForm? t)))) decls))]
    (cond
      ((listEmpty? stmts) (ok (filter (fn [t] (not (useForm? t))) decls)))
      ((listContains? (scriptEntries decls) "main") (err (perr "ERR_SCRIPT_MAIN a script with top-level code has no fn main: its top-level forms are the entry" (optionOr (listHead stmts) (PosForm :expr (rd/makeAtom "") :line 1 :col 1)))))
      (else (ok (listAppend items (list (scriptMain stmts)))))))

fn exportedAs d: DefunNode flag: Bool -> DefunNode
  (with d :isExported flag)

fn scriptModule decls: (List TopForm) -> (Result (List TopForm) ParseError)
  (let [(uses (useImports decls))]
    (match (scriptCode decls)
      ((err e) (err e))
      ((ok body) (let [(entries (scriptEntries body))]
                   (if (and (listEmpty? entries) (listEmpty? uses))
                     (ok body)
                     (let [(exported (exportedSetOf entries)) (marked (map (fn [t] (match t ((topDefun d) (topDefun (exportedAs d (mapHas? exported d.name)))) (_ t))) body))]
                       (ok (cons (topModule (ModuleNode :path "" :docstring "" :exported entries :imports uses :defs marked)) marked))))))))

fn buildModuleDecls mods: (List PosForm) rest: (List KidForm) path: String -> (Result (List TopForm) ParseError)
  (let [(exported (modsExported mods))] (match (declForms rest exported) ((err e) (err e)) ((ok decls) (match (listHead mods) ((some m) (ok (cons (topModule (moduleNode m.expr path decls)) decls))) ((none) (scriptModule decls))))))

fn buildModule forms: (List KidForm) -> (Result (List TopForm) ParseError)
  (let [(mods (filter isModulePosForm? (map (fn [(k KidForm)] -> PosForm k.pf) forms))) (rest (filter (fn [(k KidForm)] -> Bool (isNotModulePosForm? k.pf)) forms))] (match (modulePath mods) ((err e) (err e)) ((ok path) (buildModuleDecls mods rest path))))

(schema LineCol (:f line Int64) (:f col Int64))

fn offsetPosLoop bs: Bytes target: Int64 i: Int64 line: Int64 col: Int64 -> LineCol
  (if (>= i target)
    (LineCol :line line :col col)
    (let [(b (bytesGet bs i))]
      (if (= b 10)
        (offsetPosLoop bs target (+ i 1) (+ line 1) 1)
        (offsetPosLoop bs target (+ i 1) line (+ col 1)))))

fn offsetPos bs: Bytes offset: Int64 -> LineCol
  (offsetPosLoop bs offset 0 1 1)

fn escapeFormLoop text: String len: Int64 i: Int64 state: Int64 acc: (List String) -> String
  (if (>= i len)
    (stringJoin (listReverse acc) "")
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))
          (isNl (= c "\n"))
          (isQuote (= c "\""))
          (isSlash (= c "\\"))
          (isSemi (= c ";"))]
      (cond
        ((= state 1)
         (if isNl
           (escapeFormLoop text len (+ i 1) 0 (cons c acc))
           (escapeFormLoop text len (+ i 1) 1 (cons c acc))))
        ((= state 2)
         (cond
           (isSlash
            (escapeFormLoop text len (+ i 1) 3 (cons c acc)))
           (isQuote
            (escapeFormLoop text len (+ i 1) 0 (cons c acc)))
           (isNl
            (escapeFormLoop text len (+ i 1) 2 (cons "\\n" acc)))
           (else
            (escapeFormLoop text len (+ i 1) 2 (cons c acc)))))
        ((= state 3)
         (escapeFormLoop text len (+ i 1) 2 (cons c acc)))
        (else
         (cond
           (isSemi
            (escapeFormLoop text len (+ i 1) 1 (cons c acc)))
           (isQuote
            (escapeFormLoop text len (+ i 1) 2 (cons c acc)))
           (else
            (escapeFormLoop text len (+ i 1) 0 (cons c acc))))))))

fn escapeFormStringNewlines text: String -> String
  (let [(len (stringLength text))]
    (escapeFormLoop text len 0 0 (list)))

fn formScanMultiline bs: Bytes end: Int64 i: Int64 state: Int64 -> Bool
  (if (>= i end)
    false
    (let [(b (bytesGet bs i))
          (isNl (= b 10))
          (isQuote (= b 34))
          (isSlash (= b 92))
          (isSemi (= b 59))]
      (cond
        ((= state 1)
         (if isNl
           (formScanMultiline bs end (+ i 1) 0)
           (formScanMultiline bs end (+ i 1) 1)))
        ((= state 2)
         (cond
           (isSlash
            (formScanMultiline bs end (+ i 1) 3))
           (isQuote
            (formScanMultiline bs end (+ i 1) 0))
           (isNl
            true)
           (else
            (formScanMultiline bs end (+ i 1) 2))))
        ((= state 3)
         (formScanMultiline bs end (+ i 1) 2))
        (else
         (cond
           (isSemi
            (formScanMultiline bs end (+ i 1) 1))
           (isQuote
            (formScanMultiline bs end (+ i 1) 2))
           (else
            (formScanMultiline bs end (+ i 1) 0)))))))

fn formHasMultilineString? bs: Bytes -> Bool
  (formScanMultiline bs (bytesLength bs) 0 0)

fn adjustKidPos line: Int64 col: Int64 kid: (Pair Int64 Int64) -> (Pair Int64 Int64)
  (let [(kLine (pairFirst kid))
        (kCol (pairSecond kid))
        (adjLine (+ line (- kLine 1)))
        (adjCol (if (= kLine 1) (+ col (- kCol 1)) kCol))]
    (pair adjLine adjCol))

fn joinFnHeader text: String -> String
  (fh/joinFnHeader text)

fn fieldStartByte? c: Int64 -> Bool
  (or (and (>= c 97) (<= c 122)) (or (and (>= c 65) (<= c 90)) (= c 95)))

fn fieldByte? c: Int64 -> Bool
  (or (fieldStartByte? c) (or (and (>= c 48) (<= c 57)) (or (= c 45) (or (= c 63) (= c 33)))))

fn fieldEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (fieldByte? (bytesGet bs i))) (fieldEnd bs n (+ i 1)) i)

fn chainEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< (+ i 1) n) (and (= (bytesGet bs i) 46) (fieldStartByte? (bytesGet bs (+ i 1)))))
    (chainEnd bs n (fieldEnd bs n (+ i 1)))
    i)

fn stringEndAt bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (bytesGet bs i) 34) (+ i 1))
    ((= (bytesGet bs i) 92) (stringEndAt bs n (+ i 2)))
    (else (stringEndAt bs n (+ i 1))))

fn lineEndAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (lineEndAt bs n (+ i 1)))

fn firstPostfix bs: Bytes n: Int64 i: Int64 opens: (List Int64) -> (Option (Pair Int64 (Pair Int64 Int64)))
  (if (>= i n) (none)
    (let [(c (bytesGet bs i))]
      (cond
        ((= c 34) (firstPostfix bs n (stringEndAt bs n (+ i 1)) opens))
        ((= c 59) (firstPostfix bs n (lineEndAt bs n i) opens))
        ((= c 40) (firstPostfix bs n (+ i 1) (cons i opens)))
        ((= c 41) (if (and (< (+ i 2) n) (and (= (bytesGet bs (+ i 1)) 46) (fieldStartByte? (bytesGet bs (+ i 2)))))
                    (some (pair (optionOr (listHead opens) 0) (pair (+ i 1) (chainEnd bs n (+ i 1)))))
                    (firstPostfix bs n (+ i 1) (optionOr (listTail opens) (list)))))
        (else (firstPostfix bs n (+ i 1) opens)))))

fn wrapFields inner: String fields: (List String) -> String
  (fold (fn [acc f] (str "(.-" f " " acc ")")) inner fields)

fn postfixToPrefix text: String -> String
  (let [(bs (stringToBytes text)) (n (bytesLength bs))]
    (match (firstPostfix bs n 0 (list))
      ((none) text)
      ((some at)
        (let [(open (pairFirst at)) (dot (pairFirst (pairSecond at))) (end (pairSecond (pairSecond at)))
              (fields (optionOr (listTail (stringSplit (optionOr (stringSlice text dot end) "") ".")) (list)))]
          (postfixToPrefix (str (optionOr (stringSlice text 0 open) "") (wrapFields (optionOr (stringSlice text open dot) "") fields) (optionOr (stringSlice text end n) "")))))))

fn openerByte? c: Int64 -> Bool
  (or (= c 32) (or (= c 9) (or (= c 10) (or (= c 13) (or (= c 40) (or (= c 91) (or (= c 123) (= c 44))))))))

fn oldFieldAt bs: Bytes n: Int64 i: Int64 -> (Option Int64)
  (if (>= (+ i 2) n) (none)
    (let [(c (bytesGet bs i))]
      (cond
        ((= c 34) (oldFieldAt bs n (stringEndAt bs n (+ i 1))))
        ((= c 59) (oldFieldAt bs n (lineEndAt bs n i)))
        ((and (= c 46) (and (= (bytesGet bs (+ i 1)) 45) (and (fieldStartByte? (bytesGet bs (+ i 2))) (or (= i 0) (openerByte? (bytesGet bs (- i 1))))))) (some i))
        (else (oldFieldAt bs n (+ i 1))))))

fn oldFieldError text: String bs: Bytes at: Int64 -> ip/IndentError
  (let [(pos (offsetPos bs at))
        (end (fieldEnd bs (bytesLength bs) (+ at 2)))
        (field (optionOr (stringSlice text (+ at 2) end) ""))]
    (ip/IndentError :msg (str "ERR_READ_FIELD (.-" field " x) is retired: write x." field ", or (expr)." field " for an expression") :line pos.line :col pos.col))

; (:m :ref unbalancedFormDiagnostic :do "an item is parsed from its own text, so the opener position inside a closes-opened-at message is item-relative while the error position is file-absolute; the opener is rebased the same way, so the message names the real line of the unmatched opener")
fn rebaseOpenedAt msg: String line: Int64 col: Int64 -> String
  (let [(parts (stringSplit msg " opened at "))
        (lc (stringSplit (optionOr (listGet parts 1) "") ":"))]
    (if (or (!= (listLength parts) 2) (!= (listLength lc) 2)) msg
      (match (stringToInt64 (optionOr (listGet lc 0) ""))
        ((none) msg)
        ((some ol) (match (stringToInt64 (optionOr (listGet lc 1) ""))
          ((none) msg)
          ((some oc) (str (optionOr (listGet parts 0) "") " opened at " (stringFromInt64 (+ line (- ol 1))) ":" (stringFromInt64 (if (= ol 1) (+ col (- oc 1)) oc)))))))))

fn lowerTopNodeToKid text: String node: tr/Node startPos: LineCol -> (Result KidForm ParseError)
  (let [(start node.start)
        (end node.end)
        (line startPos.line)
        (col startPos.col)
        (formText (optionOr (stringSlice text start end) ""))
        (formBs (stringToBytes formText))
        (cleanText (postfixToPrefix (joinFnHeader (if (formHasMultilineString? formBs) (escapeFormStringNewlines formText) formText))))
        (old (oldFieldAt formBs (bytesLength formBs) 0))]
    (match (match old ((some at) (err (oldFieldError formText formBs at))) ((none) (ip/parseIndentedFormsPos cleanText)))
      ((err e)
       (let [(eLine e.line)
             (eCol e.col)
             (adjLine (+ line (- eLine 1)))
             (adjCol (if (= eLine 1) (+ col (- eCol 1)) eCol))]
         (err (ParseError :msg (rebaseOpenedAt e.msg line col) :line adjLine :col adjCol))))
      ((ok forms)
       (match (listHead forms)
         ((none) (err (ParseError :msg "no form produced" :line line :col col)))
         ((some f)
          (let [(adjKids (map (fn [(k (Pair Int64 Int64))] -> (Pair Int64 Int64) (adjustKidPos line col k)) f.kids))]
            (ok (KidForm
                  :pf (PosForm :expr f.expr :line line :col col)
                  :kids adjKids
                  :startOffset start
                  :endOffset end))))))))

fn lowerTopNodesLoop text: String bs: Bytes elements: (List tr/TreeElement) at: Int64 pos: LineCol acc: (List KidForm) -> (Result (List KidForm) ParseError)
  (match (listHead elements)
    ((none) (ok (listReverse acc)))
    ((some head)
     (let [(tail (optionOr (listTail elements) (list)))]
       (match head
         ((tr/elemNode node)
          (let [(startPos (offsetPosLoop bs node.start at pos.line pos.col))]
            (match (lowerTopNodeToKid text node startPos)
              ((ok kid) (lowerTopNodesLoop text bs tail node.start startPos (cons kid acc)))
              ((err e) (err e)))))
         ((tr/elemToken _)
          (lowerTopNodesLoop text bs tail at pos acc))))))

fn skipTrivia bs: Bytes len: Int64 i: Int64 inComment: Bool -> Int64
  (if (>= i len)
    len
    (let [(b (bytesGet bs i))]
      (if inComment
        (if (= b 10)
          (skipTrivia bs len (+ i 1) false)
          (skipTrivia bs len (+ i 1) true))
        (cond
          ((or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))
           (skipTrivia bs len (+ i 1) false))
          ((= b 59)
           (skipTrivia bs len (+ i 1) true))
          (else i)))))

fn scanParenEnd bs: Bytes len: Int64 i: Int64 depth: Int64 state: Int64 -> Int64
  (if (or (>= i len) (<= depth 0))
    i
    (let [(b (bytesGet bs i))]
      (cond
        ((= state 1)
         (cond
           ((= b 92) (scanParenEnd bs len (+ i 1) depth 2))
           ((= b 34) (scanParenEnd bs len (+ i 1) depth 0))
           (else (scanParenEnd bs len (+ i 1) depth 1))))
        ((= state 2)
         (scanParenEnd bs len (+ i 1) depth 1))
        ((= state 3)
         (if (= b 10)
           (scanParenEnd bs len (+ i 1) depth 0)
           (scanParenEnd bs len (+ i 1) depth 3)))
        (else
         (cond
           ((= b 34) (scanParenEnd bs len (+ i 1) depth 1))
           ((= b 59) (scanParenEnd bs len (+ i 1) depth 3))
           ((or (= b 40) (or (= b 91) (= b 123)))
            (scanParenEnd bs len (+ i 1) (+ depth 1) 0))
           ((or (= b 41) (or (= b 93) (= b 125)))
            (let [(d (- depth 1))]
              (if (<= d 0)
                (+ i 1)
                (scanParenEnd bs len (+ i 1) d 0))))
           (else
            (scanParenEnd bs len (+ i 1) depth 0)))))))

fn scanDeclEnd bs: Bytes len: Int64 i: Int64 start: Int64 depth: Int64 state: Int64 col: Int64 lastEnd: Int64 -> Int64
  (if (>= i len)
    lastEnd
    (let [(b (bytesGet bs i))]
      (if (and (= col 0) (and (> i start) (and (= depth 0) (and (= state 0) (and (!= b 32) (and (!= b 9) (and (!= b 10) (and (!= b 13) (!= b 59)))))))))
        lastEnd
        (let [(nxtCol (if (= b 10) 0 (+ col 1)))]
          (cond
            ((= state 1)
             (cond
               ((= b 92) (scanDeclEnd bs len (+ i 1) start depth 2 nxtCol (+ i 1)))
               ((= b 34) (scanDeclEnd bs len (+ i 1) start depth 0 nxtCol (+ i 1)))
               (else (scanDeclEnd bs len (+ i 1) start depth 1 nxtCol (+ i 1)))))
            ((= state 2)
             (scanDeclEnd bs len (+ i 1) start depth 1 nxtCol (+ i 1)))
            ((= state 3)
             (if (= b 10)
               (scanDeclEnd bs len (+ i 1) start depth 0 nxtCol lastEnd)
               (scanDeclEnd bs len (+ i 1) start depth 3 nxtCol lastEnd)))
            (else
             (cond
               ((= b 34)
                (scanDeclEnd bs len (+ i 1) start depth 1 nxtCol (+ i 1)))
               ((= b 59)
                (scanDeclEnd bs len (+ i 1) start depth 3 nxtCol lastEnd))
               ((or (= b 40) (or (= b 91) (= b 123)))
                (scanDeclEnd bs len (+ i 1) start (+ depth 1) 0 nxtCol (+ i 1)))
               ((or (= b 41) (or (= b 93) (= b 125)))
                (let [(d (if (> depth 0) (- depth 1) 0))]
                  (scanDeclEnd bs len (+ i 1) start d 0 nxtCol (+ i 1))))
               ((or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))
                (scanDeclEnd bs len (+ i 1) start depth 0 nxtCol lastEnd))
               (else
                (scanDeclEnd bs len (+ i 1) start depth 0 nxtCol (+ i 1))))))))))

fn scanDeclsLoop bs: Bytes len: Int64 i: Int64 acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (let [(start (skipTrivia bs len i false))]
    (if (>= start len)
      (listReverse acc)
      (let [(b0 (bytesGet bs start))]
        (if (= b0 40)
          (let [(end (scanParenEnd bs len (+ start 1) 1 0))
                (node (tr/makeNode "form" start end (list)))]
            (scanDeclsLoop bs len end (cons (tr/elemNode node) acc)))
          (let [(end (scanDeclEnd bs len start start 0 0 0 start))
                (node (tr/makeNode "decl" start end (list)))]
            (scanDeclsLoop bs len end (cons (tr/elemNode node) acc)))))))

fn scanDecls bs: Bytes -> (List tr/TreeElement)
  (scanDeclsLoop bs (bytesLength bs) 0 (list))

fn parseCstKidForms text: String -> (Result (List KidForm) ParseError)
  (let [(bs (stringToBytes text))
        (elems (scanDecls bs))]
    (lowerTopNodesLoop text bs elems 0 (LineCol :line 1 :col 1) (list)))

fn parseIndentedToModule src: String -> (Result (List TopForm) ParseError)
  (match (parseCstKidForms src)
    ((ok forms) (buildModule forms))
    ((err e) (err e)))

fn isIndentedSource? src: String -> Bool
  (or (stringContains? src "\nfn ")
  (or (stringStartsWith? src "fn ")
  (or (stringContains? src "\nfn! ")
  (or (stringContains? src "\nfn ! ")
  (or (stringContains? src "\nschema ")
  (or (stringStartsWith? src "schema ")
  (or (stringContains? src "\nenum ")
      (stringStartsWith? src "enum "))))))))

fn parseParenModule src: String -> (Result (List TopForm) ParseError)
  (match (readKidForms (lx/tokenize src)) ((ok forms) (buildModule forms)) ((err e) (err e)))

fn depthLimit -> Int64
  1000

fn depthErr line: Int64 col: Int64 -> (Option ParseError)
  (some (ParseError :msg (str "ERR_DEPTH expression nested deeper than " (depthLimit)) :line line :col col))

fn depthScan bs: Bytes len: Int64 i: Int64 depth: Int64 state: Int64 line: Int64 col: Int64 -> (Option ParseError)
  (if (>= i len)
    (none)
    (let [(b (bytesGet bs i))
          (nextLine (if (= b 10) (+ line 1) line))
          (nextCol (if (= b 10) 1 (+ col 1)))]
      (cond
        ((= state 1)
         (cond
           ((= b 92) (depthScan bs len (+ i 1) depth 2 nextLine nextCol))
           ((= b 34) (depthScan bs len (+ i 1) depth 0 nextLine nextCol))
           (else (depthScan bs len (+ i 1) depth 1 nextLine nextCol))))
        ((= state 2) (depthScan bs len (+ i 1) depth 1 nextLine nextCol))
        ((= state 3) (depthScan bs len (+ i 1) depth (if (= b 10) 0 3) nextLine nextCol))
        ((or (= b 32) (or (= b 9) (or (= b 10) (= b 13)))) (depthScan bs len (+ i 1) depth (if (= state 4) 4 0) nextLine nextCol))
        ((= b 59) (depthScan bs len (+ i 1) depth 3 nextLine nextCol))
        ((or (= b 41) (or (= b 93) (= b 125))) (depthScan bs len (+ i 1) (max 0 (- depth 1)) 0 nextLine nextCol))
        ((= b 40) (if (>= depth (depthLimit)) (depthErr line col) (depthScan bs len (+ i 1) (+ depth 1) 4 nextLine nextCol)))
        ((or (= b 91) (= b 123)) (if (>= depth (depthLimit)) (depthErr line col) (depthScan bs len (+ i 1) (+ depth 1) 0 nextLine nextCol)))
        ((= b 34) (if (>= depth (depthLimit)) (depthErr line col) (depthScan bs len (+ i 1) depth 1 nextLine nextCol)))
        ((= state 5) (depthScan bs len (+ i 1) depth 5 nextLine nextCol))
        ((and (= state 0) (>= depth (depthLimit))) (depthErr line col))
        (else (depthScan bs len (+ i 1) depth 5 nextLine nextCol)))))

fn depthError src: String -> (Option ParseError)
  (let [(bs (stringToBytes src))]
    (depthScan bs (bytesLength bs) 0 0 0 1 1))

fn parseWithFallback src: String -> (Result (List TopForm) ParseError)
  (match (depthError src)
    ((some e) (err e))
    ((none) (parseWithFallbackChecked src)))

fn parseWithFallbackChecked src: String -> (Result (List TopForm) ParseError)
  (if (isIndentedSource? src)
    (match (parseIndentedToModule src)
      ((ok res) (ok res))
      ((err ie) (match (parseParenModule src) ((ok res) (ok res)) ((err _) (err ie)))))
    (match (parseParenModule src)
      ((ok res) (ok res))
      ((err pe)
       (if (stringStartsWith? (stringTrim src) "(module")
         (err pe)
         (match (parseIndentedToModule src) ((ok res) (ok res)) ((err _) (err pe)))))))

fn kidFormsFor src: String -> (Result (List KidForm) ParseError)
  (match (depthError src)
    ((some e) (err e))
    ((none) (kidFormsForChecked src)))

fn kidFormsForChecked src: String -> (Result (List KidForm) ParseError)
  (if (isIndentedSource? src)
    (match (parseCstKidForms src)
      ((ok ks) (ok ks))
      ((err ie) (match (readKidForms (lx/tokenize src)) ((ok ks) (ok ks)) ((err _) (err ie)))))
    (match (readKidForms (lx/tokenize src))
      ((ok ks) (ok ks))
      ((err pe)
       (if (stringStartsWith? (stringTrim src) "(module")
         (err pe)
         (match (parseCstKidForms src) ((ok ks) (ok ks)) ((err _) (err pe)))))))

fn exportNamesOf v: rd/SExpr -> (List String)
  (match v
    ((rd/sexprList items) (atomsToStrings (if (= (listHeadText items) "list") (optionOr (listTail items) (list)) items)))
    (_ (atomsToStrings (sexprItems v))))

fn moduleExported m: rd/SExpr -> (List String)
  (match (findOpt (sexprItems m) ":export") ((some v) (exportNamesOf v)) ((none) (match (findOpt (sexprItems m) ":x") ((some v) (exportNamesOf v)) ((none) (list)))))

fn moduleImports m: rd/SExpr -> (List (Pair String String))
  (match (findOpt (sexprItems m) ":import") ((some v) (map importPair (filter rd/isList? (sexprItems v)))) ((none) (match (findOpt (sexprItems m) ":i") ((some v) (map importPair (filter rd/isList? (sexprItems v)))) ((none) (list)))))

fn importPair t: rd/SExpr -> (Pair String String)
  (let [(items (sexprItems t))] (pair (nthString items 0) (nthString items 2)))

fn moduleDocstring m: rd/SExpr -> String
  (match (findOpt (sexprItems m) ":doc") ((some v) (rd/sexprHead v)) ((none) (match (findOpt (sexprItems m) ":d") ((some v) (rd/sexprHead v)) ((none) ""))))

fn moduleNode m: rd/SExpr path: String defs: (List TopForm) -> ModuleNode
  (ModuleNode :path path :docstring (moduleDocstring m) :exported (moduleExported m) :imports (moduleImports m) :defs defs)

fn isTag? s: rd/SExpr -> Bool
  (and (rd/isList? s) (let [(h (rd/sexprHead s))] (= h ":tag")))

fn isDeclHead? h: String -> Bool
  (or (= h "defun") (or (= h "df") (or (= h "fn")
  (or (= h "defschema") (or (= h "dfs") (or (= h "schema")
  (or (= h "defenum") (or (= h "dfe") (= h "enum")))))))))

fn exportedSetOf exported: (List String) -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (e String)] -> (Map String Bool) (mapSet m e true)) (mapEmpty) exported)

; (:m :ref SCRIPT-ENTRY :do "a second fn, schema or enum with a name already defined in the module is a parse error at the second one, so check rejects it with its locus instead of a late link or compile failure; fns and types are separate name groups")
fn declKind t: TopForm -> String
  (match t ((topDefun _) "fn") ((topSchema _) "type") ((topEnum _) "type") (_ ""))

fn declName t: TopForm -> String
  (match t ((topDefun d) d.name) ((topSchema sc) sc.name) ((topEnum e) e.name) (_ ""))

fn declKey t: TopForm -> String
  (str (declKind t) " " (declName t))

; (:m :ref SCRIPT-ENTRY-LOWS :do "names already defined are kept in a set keyed by kind and name, so the duplicate check costs one lookup per declaration instead of a scan of the ones before it")
fn appendDecl k: KidForm exported: (Map String Bool) acc: (Pair (List TopForm) (Map String Bool)) -> (Result (Pair (List TopForm) (Map String Bool)) ParseError)
  (let [(pf k.pf) (s pf.expr) (xs (pairFirst acc)) (seen (pairSecond acc))]
    (cond
      ((isTag? s) (ok acc))
      ((not (isDeclHead? (rd/sexprHead s)))
       (ok (pair (cons (topExpr pf) xs) seen)))
      (else
       (match (declForm pf k.kids exported)
         ((ok t) (cond ((stringEmpty? (declKind t)) (ok (pair (cons t xs) seen)))
                       ((mapHas? seen (declKey t)) (err (perr (str "ERR_DUPLICATE_DEF " (declKind t) " " (declName t) " is already defined in this module") pf)))
                       (else (ok (pair (cons t xs) (mapSet seen (declKey t) true))))))
         ((err e) (err e))))))

fn declStep acc: (Result (Pair (List TopForm) (Map String Bool)) ParseError) k: KidForm exported: (Map String Bool) -> (Result (Pair (List TopForm) (Map String Bool)) ParseError)
  (match acc ((err e) (err e)) ((ok a) (appendDecl k exported a)))

fn declForms forms: (List KidForm) exported: (List String) -> (Result (List TopForm) ParseError)
  (let [(exportedSet (exportedSetOf exported))]
    (resultMap (fold (fn [(acc (Result (Pair (List TopForm) (Map String Bool)) ParseError)) (k KidForm)] -> (Result (Pair (List TopForm) (Map String Bool)) ParseError) (declStep acc k exportedSet)) (ok (pair (list) (mapEmpty))) forms) (fn [(a (Pair (List TopForm) (Map String Bool)))] -> (List TopForm) (listReverse (pairFirst a)))))

fn declForm pf: PosForm kids: (List (Pair Int64 Int64)) exported: (Map String Bool) -> (Result TopForm ParseError)
  (let [(s pf.expr) (h (rd/sexprHead s))] (cond ((not (rd/isList? s)) (err (perr "expected a top-level declaration" pf))) ((or (= h "defun") (or (= h "df") (= h "fn"))) (funNode s exported pf kids)) ((or (= h "defschema") (or (= h "dfs") (= h "schema"))) (schemaNode s pf)) ((or (= h "defenum") (or (= h "dfe") (= h "enum"))) (enumNode s pf)) (else (err (perr (str "not a declaration head: '" h "'") pf)))))

fn filterTags items: (List rd/SExpr) -> (List rd/SExpr)
  (filter (fn [(x rd/SExpr)] -> Bool (not (isTag? x))) items)

fn docString items: (List rd/SExpr) -> String
  (match (listHead items) ((some h) (cond ((isTag? h) (docString (tailExprs items))) ((and (rd/isAtom? h) (or (= (rd/sexprHead h) ":doc") (= (rd/sexprHead h) ":d"))) (match (listHead (tailExprs items)) ((some d) (rd/sexprHead d)) ((none) ""))) (else ""))) ((none) ""))

fn docBody items: (List rd/SExpr) -> (List rd/SExpr)
  (match (listHead items) ((some h) (cond ((and (isTag? h) (not (listEmpty? (tailExprs items)))) (docBody (tailExprs items))) ((and (rd/isAtom? h) (or (= (rd/sexprHead h) ":doc") (= (rd/sexprHead h) ":d"))) (tailExprs (tailExprs items))) (else items))) ((none) (list)))

fn paramsVector? v: (Option rd/SExpr) -> Bool
  (match v ((some node) (rd/isVect? node)) ((none) false))

fn hasEffect? firstOpt: (Option rd/SExpr) -> Bool
  (match firstOpt ((some h) (and (rd/isAtom? h) (= (rd/sexprHead h) "!"))) ((none) false))

fn hasTailrec? firstOpt: (Option rd/SExpr) -> Bool
  (match firstOpt
    ((some h) (and (rd/isAtom? h) (let [(v (rd/sexprHead h))] (or (= v "tailrec") (= v ":tailrec")))))
    ((none) false))

fn funParams pslot: (Option rd/SExpr) -> (List Param)
  (match pslot ((some node) (paramList node)) ((none) (list)))

fn typeNodeVect node: rd/SExpr -> rd/SExpr
  (match node
    ((rd/sexprAtom _) node)
    ((rd/sexprVect items) (rd/makeVect (map typeNodeVect items)))
    ((rd/sexprList items) (if (= (listHeadText items) "list")
                            (rd/makeVect (map typeNodeVect (tailExprs items)))
                            (rd/makeList (map typeNodeVect items)))))

fn typeNodeText node: rd/SExpr -> String
  (resolveTypeText (rd/renderSexpr (typeNodeVect node)))

; (:m :ref MAIN-SUGAR :do "fn main with no -> is a Unit main: it is effectful, returns (Result Unit String), and its last statement is passed to preludeMainDone, which takes Unit and returns (ok ()), so a Result it ends on is a type error at that statement, never dropped; the statement count and positions stay; with no parameters it still binds args, the argument list")
; (:m :ref SCRIPT-ENTRY :do "a sugared main is called with the argument list, so it names no parameter or one (List String); anything else is an error at the parameter")
fn mainParamsOk? params: (List Param) -> Bool
  (or (listEmpty? params) (and (= (listLength params) 1) (= (optionMap (fn [(p Param)] -> String p.type) (listHead params)) (some "(List String)"))))

fn paramAt pf: PosForm head: (List rd/SExpr) -> PosForm
  (with pf :col (+ pf.col (+ (stringLength (stringJoin (map rd/sexprHead head) " ")) 1)))

fn mainParams sugar: Bool params: (List Param) -> (List Param)
  (if (and sugar (listEmpty? params)) (list (Param :name "args" :type "(List String)")) params)

fn mainBody sugar: Bool body: (List rd/SExpr) -> (List rd/SExpr)
  (if (or (not sugar) (listEmpty? body))
    body
    (let [(n (listLength body))]
      (listAppend (listTake body (- n 1)) (list (rd/makeList (list (rd/makeAtom "preludeMainDone") (optionOr (listGet body (- n 1)) (rd/makeAtom "()"))))))))

fn funRetType rslot: (Option rd/SExpr) -> String
  (match rslot ((some node) (typeNodeText node)) ((none) ""))

fn padFront xs: (List (Pair Int64 Int64)) n: Int64 fill: (Pair Int64 Int64) -> (List (Pair Int64 Int64))
  (let [(len (listLength xs))] (if (>= len n) (listDrop xs (- len n)) (listAppend (map (fn [(_ Int64)] -> (Pair Int64 Int64) fill) (range 0 (- n len))) xs)))

fn docBodyPos items: (List rd/SExpr) poses: (List (Pair Int64 Int64)) -> (List PosForm)
  (match (listHead items) ((none) (list)) ((some h) (cond ((isTag? h) (docBodyPos (tailExprs items) (listDrop poses 1))) ((and (rd/isAtom? h) (or (= (rd/sexprHead h) ":doc") (= (rd/sexprHead h) ":d"))) (untaggedPos (tailExprs (tailExprs items)) (listDrop poses 2))) (else (untaggedPos items poses)))))

fn untaggedPos items: (List rd/SExpr) poses: (List (Pair Int64 Int64)) -> (List PosForm)
  (filter (fn [(p PosForm)] -> Bool (not (isTag? p.expr))) (map (fn [(i Int64)] -> PosForm (let [(lc (optionOr (listGet poses i) (pair 0 0)))] (PosForm :expr (nthExpr items i) :line (pairFirst lc) :col (pairSecond lc)))) (range 0 (listLength items))))

fn isTypeConstructor? s: String -> Bool
  (or (= s "List") (or (= s "Option") (or (= s "Result") (or (= s "Pair") (or (= s "Map") (or (= s "Array") (or (= s "Set") (= s "Vector"))))))))

fn isInlineBodyCandidate? node: rd/SExpr -> Bool
  (if (rd/isList? node)
    (let [(subItems (sexprItems node))]
      (if (< (listLength subItems) 2)
        false
        (let [(firstSub (nthExpr subItems 0))]
          (if (rd/isList? firstSub)
            true
            (match firstSub
              ((rd/sexprAtom a) (not (isTypeConstructor? a)))
              (_ false))))))
    false)

fn funNode s: rd/SExpr exported: (Map String Bool) pf: PosForm kids: (List (Pair Int64 Int64)) -> (Result TopForm ParseError)
  (let [(items (sexprItems s))
        (rest1 (tailExprs items))
        (eff1 (hasEffect? (listHead rest1)))
        (r1 (if eff1 (tailExprs rest1) rest1))
        (tr1 (hasTailrec? (listHead r1)))
        (r2 (if tr1 (tailExprs r1) r1))
        (eff2 (hasEffect? (listHead r2)))
        (r3 (if eff2 (tailExprs r2) r2))
        (effBefore (or eff1 eff2))
        (name (listHeadText r3))
        (rest4 (tailExprs r3))
        (effAfter1 (hasEffect? (listHead rest4)))
        (r4 (if effAfter1 (tailExprs rest4) rest4))
        (trAfter (hasTailrec? (listHead r4)))
        (r5 (if trAfter (tailExprs r4) r4))
        (effAfter2 (hasEffect? (listHead r5)))
        (rest4Actual (if effAfter2 (tailExprs r5) r5))
        (eff (or effBefore (or effAfter1 effAfter2)))
        (isZeroParam (= (listHeadText rest4Actual) "->"))
        (pslot (if isZeroParam (none) (listHead rest4Actual)))
        (params (if isZeroParam (list) (funParams pslot)))
        (rest5 (if isZeroParam rest4Actual (tailExprs rest4Actual)))
        (arrow (listHeadText rest5))
        (rawRetSlot (listHead (tailExprs rest5)))
        (rawRetNode (match rawRetSlot ((some n) n) ((none) (rd/makeAtom ""))))
        (doc (docString (tailExprs (tailExprs rest5))))
        (rawBody (docBody (tailExprs (tailExprs rest5))))
        (tail (tailExprs (tailExprs rest5)))
        (hasInline (and (listEmpty? rawBody) (isInlineBodyCandidate? rawRetNode)))
        (ret (if hasInline (funRetType (listHead (sexprItems rawRetNode))) (funRetType rawRetSlot)))
        (body (if hasInline (tailExprs (sexprItems rawRetNode)) rawBody))
        (mainSugar (and (= name "main") (= ret ":inferredUnit")))
        (bPos (if hasInline
                (map (fn [(_ rd/SExpr)] -> PosForm (with pf :expr _)) body)
                (docBodyPos tail (padFront kids (listLength tail) (pair pf.line pf.col)))))]
    (cond
      ((not (fnName? name)) (err (perr (str "fn name must be a symbol: '" name "'") pf)))
      ((and (not isZeroParam) (not (paramsVector? pslot))) (err (perr "defun parameters must be a [ ] vector" pf)))
      ((not (= arrow "->")) (err (perr "defun return type must be introduced by ->" pf)))
      ((stringEmpty? ret) (err (perr "defun has no return type" pf)))
      ((listEmpty? body) (err (perr "defun has no body" pf)))
      ((and mainSugar (not (mainParamsOk? params))) (err (perr (str "ERR_MAIN_PARAM a main with no -> takes no parameter or one (List String) parameter, found " (stringJoin (map (fn [(p Param)] -> String (str p.name ": " p.type)) params) " ")) (paramAt pf (listTake items (- (listLength items) (listLength rest4Actual)))))))
      (else (ok (topDefun (DefunNode :name name :typeVars (list) :isExported (mapHas? exported name) :effect (or eff mainSugar) :params (mainParams mainSugar params) :retType (if mainSugar "(Result Unit String)" ret) :docstring doc :body (mainBody mainSugar body) :bodyPos bPos))))))

fn vectItems v: rd/SExpr -> (List rd/SExpr)
  (let [(items (sexprItems v))] (if (and (rd/isList? v) (match (listHead items) ((some h) (and (rd/isAtom? h) (= (rd/sexprHead h) "list"))) ((none) false))) (tailExprs items) items))

fn paramList v: rd/SExpr -> (List Param)
  (map (fn [(p rd/SExpr)] -> Param (paramNode p)) (vectItems v))

fn paramNode p: rd/SExpr -> Param
  (let [(items (sexprItems p))] (Param :name (nthString items 0) :type (typeNodeText (nthExpr items 1))))

fn isFieldHead? h: String -> Bool
  (or (= h ":field") (= h ":f"))

fn isCaseHead? h: String -> Bool
  (or (= h ":case") (or (= h ":c") (or (= h "case") (= h "c"))))

fn allHeads? forms: (List rd/SExpr) head: String -> Bool
  (fold (fn [(acc Bool) (f rd/SExpr)] -> Bool (and acc (= (rd/sexprHead f) head))) true forms)

fn allFieldHeads? forms: (List rd/SExpr) -> Bool
  (fold (fn [(acc Bool) (f rd/SExpr)] -> Bool (and acc (isFieldHead? (rd/sexprHead f)))) true forms)

fn allCaseHeads? forms: (List rd/SExpr) -> Bool
  (fold (fn [(acc Bool) (c rd/SExpr)] -> Bool (and acc (isCaseHead? (rd/sexprHead c)))) true forms)

fn schemaJsonCase items: (List rd/SExpr) -> (Option String)
  (match (findOpt items ":json-case") ((some node) (some (rd/sexprHead node))) ((none) (none)))

fn schemaNode s: rd/SExpr pf: PosForm -> (Result TopForm ParseError)
  (let [(items (sexprItems s)) (rest (tailExprs items)) (name (listHeadText rest)) (fforms (filter (fn [(f rd/SExpr)] -> Bool (and (rd/isList? f) (not (isTag? f)))) (tailExprs rest))) (jc (schemaJsonCase items))] (cond ((not (pascalName? name)) (err (perr (str "defschema name is not PascalCase: '" name "'") pf))) ((listEmpty? fforms) (err (perr "defschema needs at least one field" pf))) ((not (allFieldHeads? fforms)) (err (perr "every defschema member must be a (:field ...) form" pf))) (else (ok (topSchema (SchemaNode :name name :typeVars (list) :fields (map (fn [(f rd/SExpr)] -> AstField (fieldNode f)) fforms) :jsonCase jc))))))

fn fieldNode f: rd/SExpr -> AstField
  (let [(items (sexprItems f))] (AstField :name (nthString items 1) :type (typeNodeText (nthExpr items 2)) :docstring (nthString items 3) :default (findOpt items ":default") :json (optAfterKey items ":json")))

fn optAfterKey items: (List rd/SExpr) key: String -> (Option String)
  (match (findOpt items key) ((some v) (some (rd/sexprHead v))) ((none) (none)))

fn enumNode s: rd/SExpr pf: PosForm -> (Result TopForm ParseError)
  (let [(items (sexprItems s)) (rest (tailExprs items)) (name (listHeadText rest)) (cforms (filter (fn [(c rd/SExpr)] -> Bool (and (rd/isList? c) (not (isTag? c)))) (tailExprs rest)))] (cond ((not (pascalName? name)) (err (perr (str "defenum name is not PascalCase: '" name "'") pf))) ((listEmpty? cforms) (err (perr "defenum needs at least one case" pf))) ((not (allCaseHeads? cforms)) (err (perr "every defenum member must be a (:case ...) form" pf))) (else (ok (topEnum (positionalizeEnumFields (EnumNode :name name :typeVars (list) :cases (map (fn [(c rd/SExpr)] -> EnumCase (caseNode c)) cforms))))))))

fn caseFields items: (List rd/SExpr) -> (List Param)
  (match (listGet items 2)
    ((some node)
     (let [(fields (vectItems node))]
       (if (listAny? (fn [(field rd/SExpr)] -> Bool (match field ((rd/sexprList _) true) (_ false))) fields)
         (map normalizeEnumField (paramList node))
         (flatEnumFields fields))))
    ((none) (list)))

fn normalizeEnumField p: Param -> Param
  (if (= p.name "_") (with p :name "") p)

fn flatEnumFields fields: (List rd/SExpr) -> (List Param)
  (match (listHead fields)
    ((none) (list))
    ((some name)
     (let [(rest (optionOr (listTail fields) (list)))
           (typeNode (optionOr (listHead rest) name))
           (tail (if (listEmpty? rest) (list) (optionOr (listTail rest) (list))))]
       (cons (Param :name (typeNodeText name) :type (if (listEmpty? rest) "" (typeNodeText typeNode))) (flatEnumFields tail)))))

fn positionalizeEnumField p: Param -> Param
  (if (and (not (stringEmpty? p.name)) (stringEmpty? p.type))
    (Param :name "" :type p.name)
    p)

fn positionalizeEnumCase c: EnumCase -> EnumCase
  (with c :fields (map positionalizeEnumField c.fields))

fn positionalizeEnumFields e: EnumNode -> EnumNode
  (with e :cases (map positionalizeEnumCase e.cases))

fn caseNode c: rd/SExpr -> EnumCase
  (let [(items (sexprItems c))] (EnumCase :name (nthString items 1) :fields (caseFields items) :docstring (nthString items 3)))

fn renderNode t: TopForm -> String
  (match t ((topModule m) (renderModule m)) ((topSchema s) (renderSchema s)) ((topEnum e) (renderEnum e)) ((topDefun d) (renderDefun d)) ((topExpr p) (rd/renderSexpr p.expr)))

fn renderModule m: ModuleNode -> String
  (let [(doc (if (stringEmpty? m.docstring) "" (str " :doc " m.docstring))) (exp (if (listEmpty? m.exported) "" (str " :export [" (stringJoin m.exported " ") "]"))) (imp (if (listEmpty? m.imports) "" (str " :import [" (stringJoin (map (fn [(p (Pair String String))] -> String (renderImport p)) m.imports) " ") "]")))] (str "(module " m.path doc exp imp ")"))

fn renderImport p: (Pair String String) -> String
  (str "(" (pairFirst p) " :as " (pairSecond p) ")")

fn renderTypeVars tv: (List String) -> String
  (if (listEmpty? tv) "" (str "{" (stringJoin tv " ") "} "))

fn renderJoined xs: (List String) prefix: String -> String
  (if (listEmpty? xs) "" (str prefix (stringJoin xs " ")))

fn renderDefun d: DefunNode -> String
  (let [(mark (if d.effect "! " "")) (tv (renderTypeVars d.typeVars)) (params (if (listEmpty? d.params) "[]" (str "[" (stringJoin (map (fn [(p Param)] -> String (renderParam p)) d.params) " ") "]"))) (docp (if (= d.docstring "") "" (str " :doc " d.docstring))) (body (renderJoined (map (fn [(b rd/SExpr)] -> String (rd/renderSexpr b)) d.body) " ")) (arrowRet (if (= d.retType ":inferredUnit") "" (str " -> " d.retType)))] (str "(fn " mark tv d.name " " params arrowRet docp body ")"))

fn renderParam p: Param -> String
  (str "(" p.name " " p.type ")")

fn renderJsonCasePart jc: (Option String) -> String
  (match jc ((some v) (str " :json-case " v)) ((none) ""))

fn renderSchema s: SchemaNode -> String
  (let [(tv (renderTypeVars s.typeVars)) (fields (renderJoined (map (fn [(f AstField)] -> String (renderField f)) s.fields) " ")) (jc (renderJsonCasePart s.jsonCase))] (str "(schema " tv s.name jc fields ")"))

fn renderFieldDefault opt: (Option rd/SExpr) -> String
  (match opt ((some v) (str " :default " (rd/renderSexpr v))) ((none) ""))

fn renderFieldJson opt: (Option String) -> String
  (match opt ((some v) (str " :json " v)) ((none) ""))

fn renderField f: AstField -> String
  (let [(defp (renderFieldDefault f.default)) (jsonp (renderFieldJson f.json))] (str "(:field " f.name " " f.type " " f.docstring defp jsonp ")"))

fn renderEnum e: EnumNode -> String
  (let [(tv (renderTypeVars e.typeVars)) (cases (renderJoined (map (fn [(c EnumCase)] -> String (renderCase c)) e.cases) " "))] (str "(enum " tv e.name cases ")"))

fn renderCase c: EnumCase -> String
  (let [(fields (if (listEmpty? c.fields) "[]" (str "[" (stringJoin (map (fn [(p Param)] -> String (renderParam p)) c.fields) " ") "]")))] (str "(:case " c.name " " fields " " c.docstring ")"))
