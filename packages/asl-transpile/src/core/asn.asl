(module asl-transpile/asn :x [AsnValue AsnEntry AsnField asnRead asnWrite valueOk? isVec? isKw? vecItems asnIntValue asnFloatValue asnStringValue] :i [(lexer :a lx) (asl-text/text :a txt)])

(schema AsnField (:f key String) (:f val AsnValue))

(schema AsnEntry (:f key AsnValue) (:f val AsnValue) (:f paren Bool))

(enum AsnValue (:c asnNil [] "The nil sentinel `_`") (:c asnBool [(b Bool)] "true or false") (:c asnUnit [] "The unit literal `()`") (:c asnInt [(lex String)] "Integer literal, held as its source lexeme") (:c asnFloat [(lex String)] "Float literal, held as its source lexeme") (:c asnStr [(lex String)] "String literal, held as its source lexeme with quotes") (:c asnKw [(k String)] "Keyword scalar, including its leading colon") (:c asnSym [(name String)] "A bare name. Legal as a head, never as a value") (:c asnVec [(items (List AsnValue))] "A bracketed vector") (:c asnMap [(entries (List AsnEntry))] "A brace map") (:c asnRec [(fields (List AsnField))] "An anonymous record `(:k v ...)`") (:c asnCtor [(name String) (fields (List AsnField))] "Named construction `(Name :k v ...)`") (:c asnRows [(name String) (rows (List AsnValue))] "Schema-grouped rows `(Name [..] ..)`") (:c asnTable [(cols (List AsnValue)) (rows (List AsnValue))] "Ad-hoc table `([:c ..] [[..]])`") (:c asnCase [(name String) (args (List AsnValue))] "Union case value `(name v ..)`") (:c asnPair [(key AsnValue) (val AsnValue)] "A parenthesised map entry, legal only in a map"))

fn valueOk? v: AsnValue -> Bool
  (mt v ((asnSym _) false) ((asnPair _ _) false) (_ true))

fn asnIntValue v: AsnValue -> (Option Int64)
  (mt v ((asnInt lex) (stringToInt64 lex)) (_ (none)))

fn asnFloatValue v: AsnValue -> (Option Float64)
  (mt v ((asnFloat lex) (stringToFloat64 lex)) (_ (none)))

fn asnStringValue v: AsnValue -> (Option String)
  (mt v ((asnStr lex) (some (unescape (txt/stripQuotes lex)))) (_ (none)))

(schema UnState (:f out (List String)) (:f esc Bool))

fn escapeChar c: String -> String
  (cond ((= c "n") "\n") ((= c "t") "\t") ((= c "r") "\r") ((= c "0") "\x00") (else c))

fn unStep st: UnState c: String -> UnState
  (if st.esc (UnState :out (cons (escapeChar c) st.out) :esc false) (if (= c "\\") (with st :esc true) (UnState :out (cons c st.out) :esc false)))

fn unescape body: String -> String
  (stringJoin (listReverse (fold unStep (UnState :out (list) :esc false) (stringChars body)).out) "")

(schema Frame (:f open String) (:f line Int64) (:f col Int64) (:f items (List AsnValue)))

(schema ReadState (:f toks (List lx/Token)) (:f stack (List Frame)) (:f done (List AsnValue)) (:f code String))

fn rst toks: (List lx/Token) stack: (List Frame) done: (List AsnValue) code: String -> ReadState
  (ReadState :toks toks :stack stack :done done :code code)

fn tokTail toks: (List lx/Token) -> (List lx/Token)
  (optionOr (listTail toks) (list))

fn frameTail fs: (List Frame) -> (List Frame)
  (optionOr (listTail fs) (list))

fn itemTail items: (List AsnValue) -> (List AsnValue)
  (optionOr (listTail items) (list))

fn fail st: ReadState code: String -> ReadState
  (rst (list) (list) (list) code)

fn isOpen? raw: String -> Bool
  (or (= raw "(") (or (= raw "[") (= raw "{")))

fn isClose? raw: String -> Bool
  (or (= raw ")") (or (= raw "]") (= raw "}")))

fn opener close: String -> String
  (cond ((= close ")") "(") ((= close "]") "[") (else "{"))

fn isUpper? c: String -> Bool
  (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" c)

fn isLower? c: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyz" c)

(enum HeadKind (:c headType [] "A PascalCase head: named construction or row groups") (:c headCase [] "A kebab-case head: a union case value") (:c headBad [] "Not a head shape Core §2 can produce"))

fn allCharsIn? s: String allowed: String -> Bool
  (and (not (stringEmpty? s)) (listEmpty? (filter (fn [(c String)] -> Bool (not (stringContains? allowed c))) (stringChars s))))

fn kebabOk? s: String -> Bool
  (and (not (stringEmpty? s)) (and (isLower? (firstChar s)) (and (not (stringContains? s "--")) (and (not (stringEndsWith? s "-")) (allCharsIn? s "abcdefghijklmnopqrstuvwxyz0123456789-")))))

fn stripIdentSuffix s: String -> String
  (if (or (stringEndsWith? s "?") (stringEndsWith? s "!")) (optionOr (stringSlice s 0 (- (stringLength s) 1)) "") s)

fn identOk? s: String -> Bool
  (kebabOk? (stripIdentSuffix s))

fn typeNameOk? s: String -> Bool
  (and (not (stringEmpty? s)) (and (isUpper? (firstChar s)) (allCharsIn? s "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")))

fn bareHeadKind s: String -> HeadKind
  (cond ((typeNameOk? s) (headType)) ((identOk? s) (headCase)) (else (headBad)))

fn partAt parts: (List String) i: Int64 -> String
  (mt (listGet parts i) ((some p) p) ((none) ""))

fn headKind name: String -> HeadKind
  (let [(parts (stringSplit name "/"))] (cond ((= (listLength parts) 1) (bareHeadKind name)) ((= (listLength parts) 2) (if (kebabOk? (partAt parts 0)) (bareHeadKind (partAt parts 1)) (headBad))) (else (headBad))))

fn firstChar s: String -> String
  (mt (stringSlice s 0 1) ((some c) c) ((none) ""))

fn symValue s: String -> AsnValue
  (cond ((= s "true") (asnBool true)) ((= s "false") (asnBool false)) ((= s "_") (asnNil)) (else (asnSym s)))

fn atomValue t: lx/Token -> (Result AsnValue String)
  (mt t.kind ((lx/tokInt _) (ok (asnInt t.rawText))) ((lx/tokFloat _) (ok (asnFloat t.rawText))) ((lx/tokString _) (ok (asnStr t.rawText))) ((lx/tokKeyword _) (ok (asnKw t.rawText))) ((lx/tokSymbol s) (ok (symValue s))) ((lx/tokError _) (err "parse")) ((lx/tokEof) (err "parse")) ((lx/tokLparen) (err "parse")) ((lx/tokRparen) (err "parse")) ((lx/tokLbracket) (err "parse")) ((lx/tokRbracket) (err "parse")))

fn allValues? items: (List AsnValue) -> Bool
  (listEmpty? (filter (fn [(v AsnValue)] -> Bool (not (valueOk? v))) items))

fn allVectors? items: (List AsnValue) -> Bool
  (listEmpty? (filter (fn [(v AsnValue)] -> Bool (not (isVec? v))) items))

fn isVec? v: AsnValue -> Bool
  (mt v ((asnVec _) true) (_ false))

fn allKeywords? items: (List AsnValue) -> Bool
  (listEmpty? (filter (fn [(v AsnValue)] -> Bool (not (isKw? v))) items))

fn isKw? v: AsnValue -> Bool
  (mt v ((asnKw _) true) (_ false))

fn vecItems v: AsnValue -> (List AsnValue)
  (mt v ((asnVec items) items) (_ (list)))

fn fieldsOf items: (List AsnValue) acc: (List AsnField) -> (Result (List AsnField) String)
  (mt (listHead items) ((none) (ok (listReverse acc))) ((some k) (mt k ((asnKw key) (mt (listHead (itemTail items)) ((some v) (if (valueOk? v) (fieldsOf (itemTail (itemTail items)) (cons (AsnField :key key :val v) acc)) (err "parse"))) ((none) (err "parse")))) (_ (err "parse")))))

fn buildRecord items: (List AsnValue) -> (Result AsnValue String)
  (mt (fieldsOf items (list)) ((ok fs) (if (listEmpty? fs) (err "parse") (ok (asnRec fs)))) ((err c) (err c)))

fn buildNamed name: String rest: (List AsnValue) -> (Result AsnValue String)
  (mt (headKind name) ((headType) (buildSchemaHead name rest)) ((headCase) (if (allValues? rest) (ok (asnCase name rest)) (err "parse"))) ((headBad) (err "parse")))

fn buildSchemaHead name: String rest: (List AsnValue) -> (Result AsnValue String)
  (mt (listHead rest) ((none) (ok (asnCtor name (list)))) ((some h) (mt h ((asnVec _) (if (allVectors? rest) (ok (asnRows name rest)) (err "parse"))) ((asnKw _) (mt (fieldsOf rest (list)) ((ok fs) (ok (asnCtor name fs))) ((err c) (err c)))) (_ (err "parse")))))

fn buildTable items: (List AsnValue) -> (Result AsnValue String)
  (if (= (listLength items) 2) (let [(cols (vecItems (nthValue items 0))) (rows (vecItems (nthValue items 1)))] (if (and (isVec? (nthValue items 1)) (and (allKeywords? cols) (allVectors? rows))) (ok (asnTable cols rows)) (err "parse"))) (err "parse"))

fn nthValue items: (List AsnValue) i: Int64 -> AsnValue
  (mt (listGet items i) ((some v) v) ((none) (asnNil)))

fn buildPair items: (List AsnValue) -> (Result AsnValue String)
  (if (= (listLength items) 2) (let [(v (nthValue items 1))] (if (valueOk? v) (ok (asnPair (nthValue items 0) v)) (err "parse"))) (err "parse"))

fn buildParen fr: Frame items: (List AsnValue) t: lx/Token -> (Result AsnValue String)
  (mt (listHead items) ((none) (if (and (= fr.line t.line) (= (+ fr.col 1) t.col)) (ok (asnUnit)) (err "parse"))) ((some h) (mt h ((asnKw _) (buildRecord items)) ((asnSym s) (buildNamed s (itemTail items))) ((asnVec _) (buildTable items)) ((asnStr _) (buildPair items)) ((asnInt _) (buildPair items)) ((asnBool _) (buildPair items)) (_ (err "parse")))))

fn entriesOf items: (List AsnValue) acc: (List AsnEntry) -> (Result (List AsnEntry) String)
  (mt (listHead items) ((none) (ok (listReverse acc))) ((some h) (mt h ((asnKw key) (mt (listHead (itemTail items)) ((some v) (if (valueOk? v) (entriesOf (itemTail (itemTail items)) (cons (AsnEntry :key (asnKw key) :val v :paren false) acc)) (err "parse"))) ((none) (err "parse")))) ((asnPair k v) (entriesOf (itemTail items) (cons (AsnEntry :key k :val v :paren true) acc))) ((asnRec fs) (if (= (listLength fs) 1) (entriesOf (itemTail items) (cons (AsnEntry :key (asnKw (fieldKey fs)) :val (fieldVal fs) :paren true) acc)) (err "parse"))) (_ (err "parse")))))

fn fieldKey fs: (List AsnField) -> String
  (mt (listHead fs) ((some f) f.key) ((none) ""))

fn fieldVal fs: (List AsnField) -> AsnValue
  (mt (listHead fs) ((some f) f.val) ((none) (asnNil)))

fn buildMap items: (List AsnValue) -> (Result AsnValue String)
  (mt (entriesOf items (list)) ((ok es) (ok (asnMap es))) ((err c) (err c)))

fn buildForm fr: Frame t: lx/Token -> (Result AsnValue String)
  (let [(items (listReverse fr.items))] (cond ((= fr.open "[") (if (allValues? items) (ok (asnVec items)) (err "parse"))) ((= fr.open "{") (buildMap items)) (else (buildParen fr items t))))

fn emit st: ReadState v: AsnValue -> ReadState
  (mt (listHead st.stack) ((some fr) (rst st.toks (cons (Frame :open fr.open :line fr.line :col fr.col :items (cons v fr.items)) (frameTail st.stack)) st.done st.code)) ((none) (rst st.toks st.stack (cons v st.done) st.code)))

fn pushFrame st: ReadState raw: String t: lx/Token -> ReadState
  (rst st.toks (cons (Frame :open raw :line t.line :col t.col :items (list)) st.stack) st.done st.code)

fn closeFrame st: ReadState raw: String t: lx/Token -> ReadState
  (mt (listHead st.stack) ((some fr) (if (= fr.open (opener raw)) (mt (buildForm fr t) ((ok v) (emit (rst st.toks (frameTail st.stack) st.done st.code) v)) ((err c) (fail st c))) (fail st "parse"))) ((none) (fail st "parse")))

fn readToken st: ReadState t: lx/Token -> ReadState
  (let [(raw t.rawText) (advanced (rst (tokTail st.toks) st.stack st.done st.code))] (cond ((stringEmpty? raw) (rst (list) st.stack st.done st.code)) ((isOpen? raw) (pushFrame advanced raw t)) ((isClose? raw) (closeFrame advanced raw t)) (else (mt (atomValue t) ((ok v) (emit advanced v)) ((err c) (fail st c))))))

fn readTick st: ReadState tick: Int64 -> ReadState
  (if (stringEmpty? st.code) (mt (listHead st.toks) ((some t) (readToken st t)) ((none) st)) st)

fn readRun st: ReadState budget: Int64 -> ReadState
  (let [(next (fold readTick st (range 0 budget)))] (if (listEmpty? next.toks) next (readRun next (* budget 2))))


fn asnRead src: String -> (Result AsnValue String)
  (finish (readRun (rst (lx/tokenize src) (list) (list) "") 64))

fn finish st: ReadState -> (Result AsnValue String)
  (cond ((not (stringEmpty? st.code)) (err st.code)) ((not (listEmpty? st.stack)) (err "parse")) ((not (= (listLength st.done) 1)) (err "parse")) (else (mt (listHead st.done) ((some v) (if (valueOk? v) (ok v) (err "parse"))) ((none) (err "parse")))))

(enum WItem (:c wText [(t String)] "Literal output text, already final") (:c wVal [(v AsnValue)] "A value still to expand"))

(schema WState (:f work (List WItem)) (:f out (List String)))

fn wTail items: (List WItem) -> (List WItem)
  (optionOr (listTail items) (list))

fn wAtom? v: AsnValue -> Bool
  (mt v ((asnNil) true) ((asnBool _) true) ((asnUnit) true) ((asnInt _) true) ((asnFloat _) true) ((asnStr _) true) ((asnKw _) true) ((asnSym _) true) (_ false))

fn wAtom v: AsnValue -> String
  (mt v ((asnNil) "_") ((asnBool b) (if b "true" "false")) ((asnUnit) "()") ((asnInt lex) lex) ((asnFloat lex) lex) ((asnStr lex) lex) ((asnKw k) k) ((asnSym s) s) (_ ""))

fn wOpen v: AsnValue -> String
  (mt v ((asnVec _) "[") ((asnMap _) "{") (_ "("))

fn wClose v: AsnValue -> String
  (mt v ((asnVec _) "]") ((asnMap _) "}") (_ ")"))

fn wFields fs: (List AsnField) -> (List WItem)
  (fold (fn [(acc (List WItem)) (f AsnField)] -> (List WItem) (listAppend acc (list (wText f.key) (wVal f.val)))) (list) fs)

fn wEntries es: (List AsnEntry) -> (List WItem)
  (fold (fn [(acc (List WItem)) (e AsnEntry)] -> (List WItem) (listAppend acc (if e.paren (list (wVal (asnPair e.key e.val))) (list (wVal e.key) (wVal e.val))))) (list) es)

fn wVals vs: (List AsnValue) -> (List WItem)
  (map (fn [(v AsnValue)] -> WItem (wVal v)) vs)

fn wChildren v: AsnValue -> (List WItem)
  (mt v ((asnVec items) (wVals items)) ((asnMap es) (wEntries es)) ((asnRec fs) (wFields fs)) ((asnCtor n fs) (cons (wText n) (wFields fs))) ((asnRows n rows) (cons (wText n) (wVals rows))) ((asnTable cs rs) (list (wVal (asnVec cs)) (wVal (asnVec rs)))) ((asnCase n args) (cons (wText n) (wVals args))) ((asnPair k val) (list (wVal k) (wVal val))) (_ (list)))

fn wSeparated items: (List WItem) -> (List WItem)
  (mt (listHead items) ((some h) (cons h (listReverse (fold (fn [(acc (List WItem)) (x WItem)] -> (List WItem) (cons x (cons (wText " ") acc))) (list) (wTail items))))) ((none) (list)))

fn wWrap v: AsnValue -> (List WItem)
  (cons (wText (wOpen v)) (listAppend (wSeparated (wChildren v)) (list (wText (wClose v)))))

fn wTick st: WState tick: Int64 -> WState
  (mt (listHead st.work) ((some it) (let [(rest (wTail st.work))] (mt it ((wText t) (WState :work rest :out (cons t st.out))) ((wVal v) (if (wAtom? v) (WState :work rest :out (cons (wAtom v) st.out)) (with st :work (listAppend (wWrap v) rest))))))) ((none) st))

fn wRun st: WState budget: Int64 -> WState
  (let [(limit budget) (next (fold wTick st (range 0 limit)))] (cond ((listEmpty? next.work) next) (else (wRun next (+ budget budget)))))

fn asnWrite v: AsnValue -> String
  (stringJoin (listReverse (wRun (WState :work (list (wVal v)) :out (list)) 64).out) "")
