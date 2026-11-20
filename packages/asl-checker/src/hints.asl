(module asl-checker/hints
  :x [Hint hintTable unboundName diagKind hintFor headerExports exportersOf! Prior priorTable priorFor priorNames priorFix headerFixes]
  :i [(asl-checker/types :a ty) (asl-checker/resolve :a r)])

; (:m :do "STATICHINT 2026-10-28: one short ASN hint per checker diagnostic, chosen by a data table (code plus a message fragment); the two context hints, nearest known name and exporting module, are built by the caller from heal symbolCandidates and exportersOf! and passed in, so no name-matching logic is copied here")

(schema Hint (:f code String) (:f when String) (:f say String))

fn hintTable -> (List Hint)
  (list
    (Hint :code "ERR_TYPE_MISMATCH" :when "(Option " :say "listGet/listHead/mapGet return Option: unwrap with match (some v)/(none) or optionOr")
    (Hint :code "ERR_TYPE_MISMATCH" :when "(Result " :say "fileReadString and parse fns return Result: unwrap with match (ok v)/(err e) or resultOr")
    (Hint :code "ERR_ARITY" :when "" :say "pass exactly the declared parameter count; read the callee signature by symbol")
    (Hint :code "ERR_TYPE_ARITY" :when "" :say "a type takes its declared number of type arguments: (List T) (Option T) (Map K V)")
    (Hint :code "ERR_NOT_EXPORTED" :when "" :say "add the name to the :x list of the module that defines it"))

; (:m :do "the checker reports some codes only inside the message (rule-9 carries ERR_NOT_EXPORTED:, type-arity is a bare code): diagKind folds them to one code")
fn diagKind d: ty/Diagnostic -> String
  (cond
    ((stringStartsWith? d.message "ERR_NOT_EXPORTED") "ERR_NOT_EXPORTED")
    ((= d.code "type-arity") "ERR_TYPE_ARITY")
    (else d.code))

fn slice s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn unboundName d: ty/Diagnostic -> (Option String)
  (cond
    ((stringStartsWith? d.message "unbound symbol: ") (some (optionOr (listHead (stringSplit (slice d.message 16 (stringLength d.message)) ";")) "")))
    ((stringEndsWith? d.message " is not defined") (some (slice d.message 0 (- (stringLength d.message) 15))))
    (else none))

; (:m :ref MISS-ABSORB :do "foreign priors (FABLE-LANG-05A): a name a model brings from Python, Lisp or TypeScript, the canonical names asl heal tries in its place (kept only when the check improves), and the fix a diagnostic prints when no rename is mechanical; in hintFor this table is consulted before the edit-distance nearest-name guess, so a foreign name always names its canonical asl target; rows come from the 2026-11-13 generation bench and the L-11 audit")
(schema Prior (:f names (List String)) (:f to (List String)) (:f fix String))

fn priorTable -> (List Prior)
  (list
    (Prior :names (list "len" "length" "size" "count" "strlen") :to (list "listLength" "stringLength" "mapSize") :fix "(listLength xs) or (stringLength s)")
    (Prior :names (list "string_length" "string-length") :to (list "stringLength") :fix "(stringLength s)")
    (Prior :names (list "every") :to (list "listAll?") :fix "(listAll? pred xs)")
    (Prior :names (list "any") :to (list "listAny?") :fix "(listAny? pred xs)")
    (Prior :names (list "substr" "substring") :to (list "stringSlice") :fix "(stringSlice s i j) returns (Option String)")
    (Prior :names (list "listCons" "prepend") :to (list "cons") :fix "(cons x xs)")
    (Prior :names (list "listConcat" "append" "concat" "listExtend") :to (list "listAppend") :fix "(listAppend xs ys)")
    (Prior :names (list "intMod" "int64Mod" "modulo") :to (list "mod") :fix "(mod a b)")
    (Prior :names (list "intDiv" "int64Div") :to (list "/") :fix "(/ a b)")
    (Prior :names (list "rem" "remainder") :to (list) :fix "(mod a b) floors, its result takes the sign of b; a truncating remainder differs once an operand is negative")
    (Prior :names (list "div" "quot") :to (list) :fix "(/ a b) floors on Int64; a truncating quotient differs once an operand is negative")
    (Prior :names (list "%") :to (list) :fix "(mod a b); % is read as mod only as a call head in a module that does not use the name itself")
    (Prior :names (list "==") :to (list) :fix "(= a b)")
    (Prior :names (list "intToString" "int64ToString" "toString" "intToStr" "stringFromInt" "itoa") :to (list "stringFromInt64") :fix "(stringFromInt64 n)")
    (Prior :names (list "stringEq?" "stringEquals?" "stringEqual?" "eq?" "equal?" "string=?") :to (list "=") :fix "(= a b)")
    (Prior :names (list "listFilter") :to (list "filter") :fix "(filter pred xs)")
    (Prior :names (list "listMap") :to (list "map") :fix "(map f xs)")
    (Prior :names (list "listFold" "listReduce" "reduce" "foldl") :to (list "fold") :fix "(fold f init xs)")
    (Prior :names (list "listNew" "emptyList") :to (list "list") :fix "(list)")
    (Prior :names (list "mapNew" "dict" "hashMap") :to (list "mapEmpty") :fix "(mapEmpty)")
    (Prior :names (list "stringToList" "chars" "stringToChars") :to (list "stringChars") :fix "(stringChars s)")
    (Prior :names (list "first" "head" "car") :to (list "listHead") :fix "(listHead xs) returns (Option T)")
    (Prior :names (list "rest" "tail" "cdr") :to (list "listTail") :fix "(listTail xs) returns (Option (List T))")
    (Prior :names (list "nth" "listNth") :to (list "listGet") :fix "(listGet xs i) returns (Option T)")
    (Prior :names (list "listPush" "push" "listAdd") :to (list) :fix "(listAppend xs (list x))")
    (Prior :names (list "nil" "null" "None" "undefined") :to (list "none") :fix "(none) for an absent value, (list) for an empty list")
    (Prior :names (list "defn" "define" "def" "defun" "function") :to (list) :fix "fn name a: T b: U -> R, then the body indented two spaces")
    (Prior :names (list "letrec" "let*" "begin" "progn") :to (list) :fix "(let [(a 1) (b 2)] body); a helper is its own top-level fn")
    (Prior :names (list "lambda") :to (list) :fix "(fn [(x T)] -> R body)")
    (Prior :names (list "else") :to (list) :fix "else only heads the last cond clause: (cond (test value) (else value))")
    (Prior :names (list "cond" "match" "let" "if") :to (list) :fix "a body is one parenthesised form: (cond ...), (match x ...), (let [...] ...)"))

fn priorFor name: String -> (Option Prior)
  (listFind (fn [(p Prior)] -> Bool (listContains? p.names name)) (priorTable))

fn priorNames name: String -> (List String)
  (match (priorFor name) ((some p) p.to) ((none) (list)))

; (:m :ref MISS-ABSORB :do "the one-turn suffix of an unbound-symbol diagnostic: the canonical form as a :fix snippet, empty when the name is no known prior")
fn priorFix d: ty/Diagnostic -> String
  (match (unboundName d)
    ((none) "")
    ((some name) (match (priorFor name) ((some p) (str " :fix \"" p.fix "\"")) ((none) ""))))

fn tableHint d: ty/Diagnostic -> (Option String)
  (let [(kind (diagKind d))
        (hit (filter (fn [(h Hint)] -> Bool (and (= h.code kind) (stringContains? d.message h.when))) (hintTable)))]
    (match (listHead hit) ((some h) (some h.say)) ((none) none)))

fn aliasOf modName: String -> String
  (optionOr (listLast (stringSplit modName "/")) modName)

; (:m :do "hintFor: unbound symbol with an exporting module names the import, else with a nearest known name names that; every other code reads the table; at most one hint, none when nothing applies. owners are the modules whose :x lists the name, near the nearest-name candidates")
fn hintFor d: ty/Diagnostic near: (List String) owners: (List String) -> (Option String)
  (match (unboundName d)
    ((some name)
      (cond
        ((= (listLength owners) 1)
          (let [(m (optionOr (listHead owners) ""))]
            (some (str "exported by " m ": add (" m " :a " (aliasOf m) ") to :i and call " (aliasOf m) "/" name))))
        ((> (listLength owners) 1) (some (str name " is exported by " (stringJoin owners " ") ": import the one you mean with :a")))
        ((some? (priorFor name)) (match (priorFor name) ((some p) (some (if (listEmpty? p.to) p.fix (str "did you mean " (stringJoin p.to " or ") " (canonical asl name)")))) ((none) none)))
        ((not (listEmpty? near)) (some (str "nearest known name: " (optionOr (listHead near) ""))))
        (else none)))
    ((none) (tableHint d)))

fn headerExports text: String -> (List String)
  (match (stringIndexOf text ":x [")
    ((none) (list))
    ((some i)
      (let [(rest (slice text (+ i 4) (stringLength text)))]
        (match (stringIndexOf rest "]")
          ((none) (list))
          ((some j) (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
                            (stringSplit (stringReplace (stringReplace (slice rest 0 j) "\n" " ") "\t" " ") " ")))))))

fn ! readModule! root: String path: String -> String
  (match (fileReadString path)
    ((ok s) s)
    ((err _) (resultOr (fileReadString (str root "/" path)) "")))

; (:m :do "name -> modules whose header :x lists it, over the package index of root (tests dirs skipped); one read per module, built only when a caller has unbound names to place")
fn ! exportersOf! root: String names: (List String) -> (Map String (List String))
  (if (listEmpty? names)
    (mapEmpty)
    (let [(ix (r/ensureIndex! root (r/emptyModIndex)))]
      (fold (fn [(acc (Map String (List String))) (m r/IdxMod)] -> (Map String (List String))
              (if (stringContains? m.path "/tests/")
                acc
                (let [(ex (headerExports (readModule! root m.path)))]
                  (fold (fn [(a (Map String (List String))) (n String)] -> (Map String (List String))
                          (if (listContains? ex n) (mapSet a n (listAppend (optionOr (mapGet a n) (list)) (list m.name))) a))
                        acc names))))
            (mapEmpty) ix.mods)))

; (:m :ref FABLE-LANG-02 :do "fn header repair: a column-0 line shaped as (defn n [a b]), (define (n a b)), a wrapped (fn n [a: T]) with colon params, a Python def n(a: T) -> R: or fn n(a: T) -> R:, or a canonical header whose body starts in column 0, maps to the canonical fn header of that very function; untyped params print a: T and a missing return prints R")
(schema TokSt (:f cur String) (:f depth Int64) (:f out (List String)))

fn flushTok st: TokSt -> TokSt
  (if (stringEmpty? st.cur) st (with (with st :out (listAppend st.out (list st.cur))) :cur ""))

fn tokStep seps: (List String) st: TokSt c: String -> TokSt
  (cond
    ((and (= st.depth 0) (listContains? seps c)) (flushTok st))
    ((or (= c "(") (= c "[")) (with (with st :cur (str st.cur c)) :depth (+ st.depth 1)))
    ((or (= c ")") (= c "]")) (if (= st.depth 0) (flushTok st) (with (with st :cur (str st.cur c)) :depth (- st.depth 1))))
    (else (with st :cur (str st.cur c))))

fn splitTop s: String seps: (List String) -> (List String)
  (let [(st (flushTok (fold (fn [(acc TokSt) (c String)] -> TokSt (tokStep seps acc c)) (TokSt :cur "" :depth 0 :out (list)) (stringChars s))))]
    st.out)

fn dropColon s: String -> String
  (if (stringEndsWith? s ":") (slice s 0 (- (stringLength s) 1)) s)

fn nonEmpty xs: (List String) fallback: String -> String
  (if (listEmpty? xs) fallback (stringJoin xs " "))

fn groupParam t: String -> String
  (let [(ws (splitTop (slice t 1 (- (stringLength t) 1)) (list " ")))]
    (str (dropColon (optionOr (listHead ws) "x")) ": " (nonEmpty (optionOr (listTail ws) (list)) "T")))

fn paramsFromTokens ts: (List String) -> (List String)
  (match (listHead ts)
    ((none) (list))
    ((some t)
      (let [(rest (optionOr (listTail ts) (list)))]
        (cond
          ((and (stringEndsWith? t ":") (not (listEmpty? rest)))
            (cons (str t " " (optionOr (listHead rest) "T")) (paramsFromTokens (optionOr (listTail rest) (list)))))
          ((stringStartsWith? t "(") (cons (groupParam t) (paramsFromTokens rest)))
          (else (cons (str t ": T") (paramsFromTokens rest)))))))

fn unwrap t: String -> String
  (slice t 1 (- (stringLength t) 1))

fn retAfter ts: (List String) -> String
  (match (listFind (fn [(t String)] -> Bool (= t "->")) ts)
    ((none) "R")
    ((some _) (let [(after (optionOr (listTail (dropUntilArrow ts)) (list)))] (optionOr (listHead after) "R"))))

fn dropUntilArrow ts: (List String) -> (List String)
  (match (listHead ts)
    ((none) (list))
    ((some t) (if (= t "->") ts (dropUntilArrow (optionOr (listTail ts) (list))))))

fn headerText name: String params: (List String) ret: String -> String
  (str "fn " name " " (if (listEmpty? params) "" (str (stringJoin params " ") " ")) "-> " ret)

fn tokAt ts: (List String) i: Int64 -> String
  (optionOr (listGet ts i) "")

fn wrappedHeader line: String -> (Option String)
  (let [(ts (splitTop (slice line 1 (stringLength line)) (list " " "\t")))
        (head (tokAt ts 0))
        (second (tokAt ts 1))
        (foreign (listContains? (list "defn" "define" "def" "defun" "function") head))
        (fnHead (listContains? (list "fn" "df") head))]
    (cond
      ((not (or foreign fnHead)) (none))
      ((stringStartsWith? second "(")
        (let [(inner (splitTop (unwrap second) (list " ")))]
          (if foreign
            (some (headerText (tokAt inner 0) (paramsFromTokens (optionOr (listTail inner) (list))) (retAfter ts)))
            (none))))
      ((stringStartsWith? (tokAt ts 2) "[")
        (let [(raw (splitTop (unwrap (tokAt ts 2)) (list " ")))]
          (if (or foreign (listAny? (fn [(t String)] -> Bool (stringEndsWith? t ":")) raw))
            (some (headerText second (paramsFromTokens raw) (retAfter ts)))
            (none))))
      (foreign (some (headerText second (list) (retAfter ts))))
      (else (none))))

fn matchClose cs: (List String) i: Int64 depth: Int64 -> Int64
  (match (listHead cs)
    ((none) -1)
    ((some c)
      (let [(rest (optionOr (listTail cs) (list)))]
        (cond
          ((or (= c "(") (= c "[")) (matchClose rest (+ i 1) (+ depth 1)))
          ((or (= c ")") (= c "]")) (if (= depth 0) i (matchClose rest (+ i 1) (- depth 1))))
          (else (matchClose rest (+ i 1) depth))))))

fn pyParam p: String -> String
  (let [(parts (stringSplit (stringTrim p) ":"))
        (nm (stringTrim (optionOr (listHead parts) "")))
        (ty (stringTrim (stringJoin (optionOr (listTail parts) (list)) ":")))
        (ty2 (optionOr (listHead (stringSplit ty "=")) ""))]
    (str nm ": " (if (stringEmpty? (stringTrim ty2)) "T" (stringTrim ty2))))

fn pyHeader line: String start: Int64 -> (Option String)
  (let [(rest (slice line start (stringLength line)))
        (nm (stringTrim (optionOr (listHead (stringSplit rest "(")) "")))]
    (if (or (not (stringContains? rest "(")) (stringEmpty? nm) (stringContains? nm " ") (stringContains? nm ":"))
      (none)
      (let [(after (slice rest (+ (stringLength nm) 1) (stringLength rest)))
            (close (matchClose (stringChars after) 0 0))]
        (if (< close 0)
          (none)
          (let [(params (filter (fn [(p String)] -> Bool (not (stringEmpty? (stringTrim p)))) (splitTop (slice after 0 close) (list ","))))
                (tail (stringTrim (slice after (+ close 1) (stringLength after))))
                (ret (if (stringStartsWith? tail "->") (stringTrim (dropColon (stringTrim (slice tail 2 (stringLength tail))))) "R"))]
            (some (headerText nm (map pyParam params) (if (stringEmpty? ret) "R" ret))))))))

fn nextContent lines: (List String) i: Int64 -> (Option String)
  (match (listGet lines i)
    ((none) (none))
    ((some l) (if (stringEmpty? (stringTrim l)) (nextContent lines (+ i 1)) (some l))))

fn col0BodyStarts? l: String -> Bool
  (and (not (stringStartsWith? l " ")) (and (not (stringStartsWith? l "\t"))
    (not (listAny? (fn [(k String)] -> Bool (stringStartsWith? l k)) (list ";" "fn " "schema " "enum " "module" "exports " "import " "doc ")))))

fn headerFix line: String lines: (List String) i: Int64 -> (Option String)
  (cond
    ((stringStartsWith? line "(") (wrappedHeader line))
    ((stringStartsWith? line "def ") (pyHeader line 4))
    ((stringStartsWith? line "fn ")
      (match (pyHeader line 3)
        ((some h) (some h))
        ((none) (match (nextContent lines (+ i 1))
                  ((some n) (if (col0BodyStarts? n) (some (stringTrim line)) (none)))
                  ((none) (none))))))
    (else (none)))

fn headerFixesFrom ls: (List String) all: (List String) i: Int64 acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (match (listHead ls)
    ((none) (listReverse acc))
    ((some l)
      (headerFixesFrom (optionOr (listTail ls) (list)) all (+ i 1)
        (match (headerFix l all i) ((some h) (cons (pair (+ i 1) h) acc)) ((none) acc)))))

fn headerFixes src: String -> (List (Pair Int64 String))
  (let [(ls (stringSplit src "\n"))] (headerFixesFrom ls ls 0 (list)))
