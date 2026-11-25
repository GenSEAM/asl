(module asl-cli/irSplit
  :x [Body Split split splitWith inlineLimit declOf externOf Named splitModules splitBuckets bucketOf refsOf renameLocal groupOf]
  :i [])

(schema Body
  (:f head String)
  (:f text String)
  (:f size Int64))

(schema Split
  (:f shared (List String))
  (:f owned (List String))
  (:f bodies (List Body)))

fn paramType p: String -> String
  (let [(words (stringSplit p " "))]
    (if (< (listLength words) 2) p (stringJoin (listTake words (- (listLength words) 1)) " ")))

fn declOf head: String -> (Option String)
  (let [(rest (stringReplace (stringReplace (optionOr (stringSlice head 7 (stringLength head)) "") "internal " "") "weak " ""))]
    (match (stringIndexOf rest "(")
      ((none) (none))
      ((some open) (match (stringIndexOf rest ")")
        ((none) (none))
        ((some close) (let [(params (optionOr (stringSlice rest (+ open 1) close) ""))]
                        (some (str "declare " (optionOr (stringSlice rest 0 open) "") "("
                                   (if (stringEmpty? params) "" (stringJoin (map paramType (stringSplit params ", ")) ", ")) ")"))))))))

fn externOf line: String -> (Option String)
  (match (stringIndexOf line " global ")
    ((none) (none))
    ((some at) (let [(name (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " = ") 0)) ""))
                     (init (optionOr (stringSlice line (+ at 8) (stringLength line)) ""))
                     (typed (optionOr (listHead (stringSplit init ", align ")) init))
                     (words (stringSplit typed " "))
                     (ty (stringJoin (listTake words (max 0 (- (listLength words) 1))) " "))]
                 (cond
                   ((or (stringEmpty? name) (stringEmpty? ty)) (none))
                   ((stringStartsWith? (definition line) "weak global ") (some (str name " = external global " ty)))
                   (else (some (str name " = external hidden global " ty)))))))

fn definition line: String -> String
  (match (stringIndexOf line " = ") ((none) "") ((some i) (optionOr (stringSlice line (+ i 3) (stringLength line)) "")))

fn owned? line: String -> Bool
  (and (stringStartsWith? line "@") (or (stringStartsWith? (definition line) "internal global ") (stringStartsWith? (definition line) "weak global ")))

fn bodyOf piece: String -> (Result (Pair Body String) String)
  (let [(whole (str piece "\n"))]
    (match (stringIndexOf whole "\n}\n")
      ((none) (err "a define has no closing brace line"))
      ((some end) (let [(text (str "define " (optionOr (stringSlice whole 0 (+ end 3)) "")))
                        (head (optionOr (stringSlice text 0 (optionOr (stringIndexOf text "\n") (stringLength text))) ""))]
                    (ok (pair (Body :head head :text text :size (stringLength text)) (optionOr (stringSlice whole (+ end 3) (stringLength whole)) "")))))))

fn bodiesOf pieces: (List String) bodies: (List Body) tails: (List String) -> (Result (Pair (List Body) (List String)) String)
  (match (listHead pieces)
    ((none) (ok (pair (listReverse bodies) tails)))
    ((some p) (match (bodyOf p)
      ((err e) (err e))
      ((ok u) (bodiesOf (optionOr (listTail pieces) (list)) (cons (pairFirst u) bodies) (cons (pairSecond u) tails))))))

fn parse text: String -> (Result Split String)
  (let [(pieces (stringSplit text "\ndefine "))]
    (match (bodiesOf (optionOr (listTail pieces) (list)) (list) (list))
      ((err e) (err e))
      ((ok found) (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l)))
                                       (stringLines (stringJoin (cons (str (optionOr (listHead pieces) "") "\n") (pairSecond found)) "\n"))))]
                    (ok (Split :shared (filter (fn [(l String)] -> Bool (not (owned? l))) lines)
                               :owned (filter owned? lines)
                               :bodies (pairFirst found)))))))

fn assign bodies: (List Body) n: Int64 -> (List Int64)
  (let [(total (fold (fn [(acc Int64) (u Body)] -> Int64 (+ acc u.size)) 0 bodies))
        (per (max 1 (/ (+ total (- n 1)) n)))]
    (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List Int64))) (u Body)] -> (Pair Int64 (List Int64))
                                     (let [(before (pairFirst acc))]
                                       (pair (+ before u.size) (cons (min (- n 1) (/ before per)) (pairSecond acc)))))
                                   (pair 0 (list)) bodies))))

fn ownText u: Body -> String
  (if (stringStartsWith? u.head "define internal ") (str "define hidden " (optionOr (stringSlice u.text 16 (stringLength u.text)) "")) u.text)

; (:m :ref BUILDPAR :do "a body at most limit bytes long (2000: on asl1.asl split 8 ways, fixedNt +4.0% with no copies, +3.3% at 800, +0.79% at 1500, +0.16% at 2000, 2026-10-25) is also given to every other part as available_externally, so a small helper (a closure code wrapper, a prelude accessor) still inlines across a part boundary as it does in the whole module; only internal bodies and bodies with default linkage qualify, never main, a weak or a linkonce body")
fn inlineLimit -> Int64
  2000

fn linkageWord? w: String -> Bool
  (listContains? (list "weak" "weak_odr" "linkonce" "linkonce_odr" "private" "hidden" "protected" "available_externally" "external" "extern_weak" "common" "appending" "dllexport") w)

fn plainDefine? head: String -> Bool
  (not (linkageWord? (optionOr (listHead (stringSplit (optionOr (stringSlice head 7 (stringLength head)) "") " ")) "")))

fn copyText u: Body limit: Int64 -> (Option String)
  (cond
    ((or (> u.size limit) (stringContains? u.head " @main(")) (none))
    ((stringStartsWith? u.head "define internal ") (some (str "define available_externally " (optionOr (stringSlice u.text 16 (stringLength u.text)) ""))))
    ((plainDefine? u.head) (some (str "define available_externally " (optionOr (stringSlice u.text 7 (stringLength u.text)) ""))))
    (else (none)))

fn otherText u: Body limit: Int64 -> (Result String String)
  (cond
    ((stringStartsWith? u.head "define linkonce_odr ") (ok u.text))
    ((some? (copyText u limit)) (ok (optionOr (copyText u limit) "")))
    ((and (stringStartsWith? u.head "define internal ") (stringEndsWith? u.head " alwaysinline {"))
      (ok (str "define available_externally " (optionOr (stringSlice u.text 16 (stringLength u.text)) ""))))
    (else (match (declOf u.head)
            ((none) (err (str "cannot declare " u.head)))
            ((some d) (ok (if (stringStartsWith? u.head "define internal ") (str "declare hidden " (optionOr (stringSlice d 8 (stringLength d)) "")) d))))))

fn ownedText k: Int64 line: String -> (Result String String)
  (if (= k 0)
    (let [(rhs (definition line))]
      (ok (if (stringStartsWith? rhs "internal global ")
            (str (optionOr (stringSlice line 0 (- (stringLength line) (stringLength rhs))) "") "hidden global " (optionOr (stringSlice rhs 16 (stringLength rhs)) ""))
            line)))
    (match (externOf line) ((none) (err (str "cannot declare " line))) ((some d) (ok d))))

fn collect xs: (List (Result String String)) acc: (List String) -> (Result (List String) String)
  (match (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some r) (match r ((err e) (err e)) ((ok s) (collect (optionOr (listTail xs) (list)) (cons s acc))))))

fn part s: Split owners: (List Int64) k: Int64 limit: Int64 -> (Result String String)
  (match (collect (map (fn [(l String)] -> (Result String String) (ownedText k l)) s.owned) (list))
    ((err e) (err e))
    ((ok globals) (match (collect (map (fn [(p (Pair Int64 Body))] -> (Result String String)
                                       (if (= (pairFirst p) k) (ok (ownText (pairSecond p))) (otherText (pairSecond p) limit)))
                                     (zip owners s.bodies)) (list))
      ((err e) (err e))
      ((ok bodies) (ok (str (stringJoin s.shared "\n") "\n" (stringJoin globals "\n") "\n" (stringJoin bodies "\n") "\n"))))))

fn split text: String n: Int64 -> (Result (List String) String)
  (splitWith text n (inlineLimit))

fn splitWith text: String n: Int64 limit: Int64 -> (Result (List String) String)
  (match (parse text)
    ((err e) (err e))
    ((ok s) (let [(parts (max 1 (min n (listLength s.bodies))))
                  (owners (assign s.bodies parts))]
              (collect (map (fn [(k Int64)] -> (Result String String) (part s owners k limit)) (range 0 parts)) (list)))))

; (:m :ref BUILD-CACHE :do "a module part is the bodies one source module owns (a body's module is the path segment of its mangled name that holds a slash, so a prelude clone specialised for a caller goes with the caller; bodies with no slash form the rt part) plus only what they reach: the constants, declarations and externs they name and the copies otherText gives for bodies of other parts; every owned global except the string cells is defined once in the @globals part with the appending globals. A part's text then changes only when its own bodies or what they reach change, so its object can be cached by the digest of that text")
(schema Named
  (:f name String)
  (:f text String))

fn identByte? c: Int64 -> Bool
  (or (and (>= c 48) (<= c 57)) (or (and (>= c 65) (<= c 90)) (or (and (>= c 97) (<= c 122)) (or (= c 36) (or (= c 46) (or (= c 95) (= c 45)))))))

fn identEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (identByte? (bytesGet bs i))) (identEnd bs (+ i 1) n) i)

fn quoteEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet bs i) 34) i) (else (quoteEnd bs (+ i 1) n)))

fn nextMark bs: Bytes i: Int64 n: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet bs i) 64) i) ((= (bytesGet bs i) 34) i) (else (nextMark bs (+ i 1) n)))

; (:m :ref BUILD-CACHE :do "the global names a text references, in order of appearance, quoted text (c\"..\", metadata strings) skipped")
fn scanRefs s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (let [(j (nextMark bs i n))]
    (cond
      ((>= j n) (listReverse acc))
      ((= (bytesGet bs j) 34) (scanRefs s bs (+ (quoteEnd bs (+ j 1) n) 1) n acc))
      (else (let [(e (identEnd bs (+ j 1) n))]
              (if (> e (+ j 1))
                (scanRefs s bs e n (cons (optionOr (stringSlice s (+ j 1) e) "") acc))
                (scanRefs s bs (+ j 1) n acc))))))

fn refsOf text: String -> (List String)
  (scanRefs text (stringToBytes text) 0 (stringLength text) (list))

fn digitsFrom bs: Bytes i: Int64 n: Int64 -> Bool
  (cond ((>= i n) true) ((and (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 57)) (digitsFrom bs (+ i 1) n)) (else false))

fn digits? s: String -> Bool
  (and (not (stringEmpty? s)) (digitsFrom (stringToBytes s) 0 (stringLength s)))

fn numbered? name: String prefix: String -> Bool
  (and (stringStartsWith? name prefix) (digits? (optionOr (stringSlice name (stringLength prefix) (stringLength name)) "")))

; (:m :ref BUILD-CACHE :do "the string constants and their cells are numbered across the whole program, so a literal added in one module renumbers every later one; inside a part they are renumbered by first appearance, which keeps a part's text stable while only other modules gain or lose literals")
fn localNames refs: (List String) -> (Map String String)
  (pairFirst (fold (fn [(acc (Pair (Map String String) (Pair Int64 Int64))) (r String)] -> (Pair (Map String String) (Pair Int64 Int64))
                     (let [(m (pairFirst acc)) (ns (pairSecond acc))]
                       (cond
                         ((mapHas? m r) acc)
                         ((numbered? r "str.") (pair (mapSet m r (str "str." (stringFromInt64 (pairFirst ns)))) (pair (+ (pairFirst ns) 1) (pairSecond ns))))
                         ((numbered? r "strVal.") (pair (mapSet m r (str "strVal." (stringFromInt64 (pairSecond ns)))) (pair (pairFirst ns) (+ (pairSecond ns) 1))))
                         (else acc))))
                   (pair (mapEmpty) (pair 0 0)) refs))

fn renameScan s: String bs: Bytes i: Int64 n: Int64 start: Int64 names: (Map String String) acc: (List String) -> String
  (let [(j (nextMark bs i n))]
    (cond
      ((>= j n) (stringJoin (listReverse (cons (optionOr (stringSlice s start n) "") acc)) ""))
      ((= (bytesGet bs j) 34) (renameScan s bs (+ (quoteEnd bs (+ j 1) n) 1) n start names acc))
      (else (let [(e (identEnd bs (+ j 1) n))
                  (id (optionOr (stringSlice s (+ j 1) e) ""))]
              (match (mapGet names id)
                ((none) (renameScan s bs (max e (+ j 1)) n start names acc))
                ((some to) (renameScan s bs e n e names (cons to (cons (optionOr (stringSlice s start (+ j 1)) "") acc)))))))))

fn renameLocal text: String -> String
  (let [(names (localNames (refsOf text)))]
    (if (= (mapSize names) 0) text (renameScan text (stringToBytes text) 0 (stringLength text) 0 names (list))))

fn nameOf head: String -> String
  (let [(at (optionOr (stringIndexOf head "@") 0))
        (rest (optionOr (stringSlice head (+ at 1) (stringLength head)) ""))]
    (optionOr (listHead (stringSplit rest "(")) rest))

fn lineName line: String -> String
  (optionOr (stringSlice line 1 (optionOr (stringIndexOf line " = ") 1)) "")

fn groupOf name: String -> String
  (match (stringIndexOf name "$2F")
    ((none) (if (or (= name "main") (= name "asl.main")) "@entry" "rt"))
    ((some p) (let [(before (optionOr (stringSlice name 0 p) ""))
                    (lastPiece (optionOr (listLast (stringSplit before "$24")) before))
                    (start (- p (stringLength lastPiece)))
                    (after (optionOr (stringSlice name p (stringLength name)) ""))
                    (end (match (stringIndexOf after "$2E") ((none) (stringLength name)) ((some k) (+ p k))))]
                (optionOr (stringSlice name start end) name))))

fn stringCell? name: String -> Bool
  (numbered? name "strVal.")

(schema BodyRef
  (:f idx Int64)
  (:f group String)
  (:f body Body))

(schema Index
  (:f header (List String))
  (:f consts (Map String (Pair Int64 String)))
  (:f appending (List String))
  (:f decls (Map String (Pair Int64 String)))
  (:f owned (Map String (Pair Int64 String)))
  (:f ownedLines (List String))
  (:f bodyAt (Map String BodyRef))
  (:f order (List String))
  (:f members (Map String (List BodyRef))))

fn byName lines: (List String) key: (fn [String] -> String) -> (Map String (Pair Int64 String))
  (pairFirst (fold (fn [(acc (Pair (Map String (Pair Int64 String)) Int64)) (l String)] -> (Pair (Map String (Pair Int64 String)) Int64)
                     (pair (mapSet (pairFirst acc) (key l) (pair (pairSecond acc) l)) (+ (pairSecond acc) 1)))
                   (pair (mapEmpty) 0) lines))

fn hexDigit c: Int64 -> Int64
  (cond ((and (>= c 48) (<= c 57)) (- c 48)) ((and (>= c 97) (<= c 102)) (- c 87)) (else 0))

fn hexPrefix bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (hexPrefix bs (+ i 1) n (+ (* acc 16) (hexDigit (bytesGet bs i)))))

; (:m :ref BUILD-CACHE :do "a module group goes to bucket sha256(group) mod n, so the bucket of a module never depends on the sizes or the set of the other modules; @globals and @entry stay parts of their own, and n 0 keeps one part per module")
fn bucketOf group: String n: Int64 -> String
  (if (or (<= n 0) (stringStartsWith? group "@")) group
    (str "bucket" (stringFromInt64 (mod (hexPrefix (stringToBytes (bytesSha256 (stringToBytes group))) 0 7 0) n))))

fn refOf n: Int64 p: (Pair Int64 Body) -> BodyRef
  (let [(u (pairSecond p))] (BodyRef :idx (pairFirst p) :group (bucketOf (groupOf (nameOf u.head)) n) :body u))

fn indexSplit s: Split n: Int64 -> Index
  (let [(at? (fn [(l String)] -> Bool (stringStartsWith? l "@")))
        (decl? (fn [(l String)] -> Bool (stringStartsWith? l "declare ")))
        (app? (fn [(l String)] -> Bool (stringStartsWith? (definition l) "appending global ")))
        (refs (map (fn [(p (Pair Int64 Body))] -> BodyRef (refOf n p)) (enumerate s.bodies)))
        (grouped (fold (fn [(acc (Pair (Map String (List BodyRef)) (List String))) (r BodyRef)] -> (Pair (Map String (List BodyRef)) (List String))
                         (let [(m (pairFirst acc))]
                           (pair (mapSet m r.group (cons r (mapGetOr m r.group (list))))
                                 (if (mapHas? m r.group) (pairSecond acc) (cons r.group (pairSecond acc))))))
                       (pair (mapEmpty) (list)) refs))]
    (Index :header (filter (fn [(l String)] -> Bool (not (or (at? l) (decl? l)))) s.shared)
           :consts (byName (filter (fn [(l String)] -> Bool (and (at? l) (not (app? l)))) s.shared) lineName)
           :appending (filter (fn [(l String)] -> Bool (and (at? l) (app? l))) s.shared)
           :decls (byName (filter decl? s.shared) nameOf)
           :owned (byName s.owned lineName) :ownedLines s.owned
           :bodyAt (fold (fn [(m (Map String BodyRef)) (r BodyRef)] -> (Map String BodyRef) (mapSet m (nameOf r.body.head) r)) (mapEmpty) refs)
           :order (listReverse (pairSecond grouped))
           :members (pairFirst grouped)))

(schema Reach
  (:f seen (Map String Bool))
  (:f consts (List (Pair Int64 String)))
  (:f owned (List (Pair Int64 String)))
  (:f decls (List (Pair Int64 String)))
  (:f others (List (Pair Int64 String))))

; (:m :ref BUILD-CACHE :do "one step of the reach of a part: a name already seen, or a body the part owns, adds nothing; a constant, an owned global, a declaration or another part's body (as otherText gives it) is recorded once and the names its own text references are queued")
fn reachStep ix: Index group: String limit: Int64 todo: (List String) r: Reach -> (Result Reach String)
  (match (listHead todo)
    ((none) (ok r))
    ((some n)
     (let [(rest (optionOr (listTail todo) (list)))]
       (if (mapHas? r.seen n)
         (reachStep ix group limit rest r)
         (let [(seen (mapSet r.seen n true))]
           (match (mapGet ix.consts n)
             ((some c) (reachStep ix group limit (listAppend (refsOf (pairSecond c)) rest) (with r :seen seen :consts (cons c r.consts))))
             ((none) (match (mapGet ix.owned n)
               ((some o) (if (stringCell? n)
                           (reachStep ix group limit (listAppend (refsOf (definition (pairSecond o))) rest) (with r :seen seen :owned (cons o r.owned)))
                           (match (ownedText 1 (pairSecond o))
                             ((err e) (err e))
                             ((ok d) (reachStep ix group limit rest (with r :seen seen :owned (cons (pair (pairFirst o) d) r.owned)))))))
               ((none) (match (mapGet ix.decls n)
                 ((some d) (reachStep ix group limit rest (with r :seen seen :decls (cons d r.decls))))
                 ((none) (match (mapGet ix.bodyAt n)
                   ((none) (reachStep ix group limit rest (with r :seen seen)))
                   ((some b) (if (= b.group group)
                               (reachStep ix group limit rest (with r :seen seen))
                               (match (otherText b.body limit)
                                 ((err e) (err e))
                                 ((ok other) (reachStep ix group limit (if (stringStartsWith? other "define ") (listAppend (refsOf other) rest) rest)
                                                        (with r :seen seen :others (cons (pair b.idx other) r.others)))))))))))))))))))

fn ordered xs: (List (Pair Int64 String)) -> (List String)
  (map pairSecond (listSortBy pairFirst xs))

fn partText ix: Index r: Reach bodies: (List String) tail: (List String) -> String
  (renameLocal (str (stringJoin ix.header "\n") "\n" (stringJoin (ordered r.consts) "\n") "\n" (stringJoin (ordered r.owned) "\n") "\n"
                    (stringJoin (ordered r.decls) "\n") "\n" (stringJoin bodies "\n") "\n" (stringJoin tail "\n") "\n"))

fn emptyReach -> Reach
  (Reach :seen (mapEmpty) :consts (list) :owned (list) :decls (list) :others (list))

fn groupPart ix: Index group: String limit: Int64 mine: (List BodyRef) -> (Result Named String)
  (let [(own (map (fn [(b BodyRef)] -> (Pair Int64 String) (pair b.idx (ownText b.body))) mine))]
    (match (reachStep ix group limit (listFlatMap (fn [(p (Pair Int64 String))] -> (List String) (refsOf (pairSecond p))) own) (emptyReach))
      ((err e) (err e))
      ((ok r) (ok (Named :name group :text (partText ix r (ordered (listAppend own r.others)) (list)))))))

; (:m :ref BUILD-CACHE :do "the @globals part defines every owned global but the string cells, hidden where it was internal, and the appending globals (constructors, compiler.used) exactly once; the bodies its initialisers name are only declared")
fn globalsPart ix: Index -> (Result Named String)
  (let [(mine (filter (fn [(l String)] -> Bool (not (stringCell? (lineName l)))) ix.ownedLines))
        (seed (fold (fn [(m (Map String Bool)) (l String)] -> (Map String Bool) (mapSet m (lineName l) true)) (mapEmpty) mine))]
    (match (reachStep ix "@globals" 0 (listFlatMap (fn [(l String)] -> (List String) (refsOf (definition l))) (listAppend mine ix.appending)) (with (emptyReach) :seen seed))
      ((err e) (err e))
      ((ok r) (match (collect (map (fn [(l String)] -> (Result String String) (ownedText 0 l)) mine) (list))
        ((err e) (err e))
        ((ok defs) (ok (Named :name "@globals" :text (partText ix r (ordered r.others) (listAppend defs ix.appending)))))))))

; (:m :ref BUILD-CACHE :do "the C entry main and its asl.main wrapper are a part of their own, @entry, built without copies of what it calls, so an edit of the program's main body compiles that module's part alone and not the runtime part")
; (:m :ref BUILD-CACHE :do "the module split: the @globals part then one part per module group, in the order the module's first body appears, so the same IR always splits into the same named texts")
fn splitModules text: String limit: Int64 -> (Result (List Named) String)
  (splitBuckets text limit 0)

; (:m :ref BUILD-CACHE :do "the bucketed split: module groups hashed into n buckets (128 for the CLI, near one part per module; 16 was about 9 MB of IR each), so a cold build compiles a few large parts and a body edit compiles the one bucket that holds the module")
fn splitBuckets text: String limit: Int64 n: Int64 -> (Result (List Named) String)
  (match (parse text)
    ((err e) (err e))
    ((ok s) (let [(ix (indexSplit s n))]
              (match (globalsPart ix)
                ((err e) (err e))
                ((ok g) (match (collectNamed (map (fn [(grp String)] -> (Result Named String) (groupPart ix grp (if (= grp "@entry") 0 limit) (listReverse (mapGetOr ix.members grp (list))))) ix.order) (list))
                  ((err e) (err e))
                  ((ok parts) (ok (cons g parts)))))))))

fn collectNamed xs: (List (Result Named String)) acc: (List Named) -> (Result (List Named) String)
  (match (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some r) (match r ((err e) (err e)) ((ok s) (collectNamed (optionOr (listTail xs) (list)) (cons s acc))))))
