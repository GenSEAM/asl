(module aslAgent/toolCalls
  :x [untagToolCalls ShapeFix canonSteps]
  :i [(aslAgent/core :a c) (aslAgent/context :a cx)])

enum Evt
  (evt end: Int64 open: Bool)
fn at s: String i: Int64 t: String -> Bool
  (and (<= (+ i (stringLength t)) (stringLength s)) (= (c/sliceOf s i (+ i (stringLength t))) t))
fn scan s: String n: Int64 i: Int64 q: Bool e: Bool a: (List Evt) -> (List Evt)
  (if (>= i n) (listReverse a) (let [c0 (c/ch s i)]
    (cond (q (cond (e (scan s n (+ i 1) true false a))
      ((= c0 "\\") (scan s n (+ i 1) true true a))
      ((= c0 "\"") (scan s n (+ i 1) false false a))
      (else (scan s n (+ i 1) true false a))))
      ((= c0 "\"") (scan s n (+ i 1) true false a))
      ((at s i "<tool_call>") (scan s n (+ i 11) false false (cons (evt (+ i 11) true) a)))
      ((at s i "</tool_call>") (scan s n (+ i 12) false false (cons (evt (+ i 12) false) a)))
      ((at s i "]]>") (scan s n (+ i 3) false false (cons (evt (+ i 3) false) a)))
      (else (scan s n (+ i 1) false false a)))))
fn hasOpen es: (List Evt) -> Bool
  (if (listEmpty? es) false (match (c/firstOf es) ((evt end open) (or open (hasOpen (c/restOf es))))))
fn depth s: String n: Int64 i: Int64 d: Int64 q: Bool e: Bool -> Int64
  (if (>= i n) d (let [c0 (c/ch s i)]
    (cond (q (cond (e (depth s n (+ i 1) d true false))
      ((= c0 "\\") (depth s n (+ i 1) d true true))
      ((= c0 "\"") (depth s n (+ i 1) d false false))
      (else (depth s n (+ i 1) d true false))))
      ((= c0 "\"") (depth s n (+ i 1) d true false))
      ((= c0 "(") (depth s n (+ i 1) (+ d 1) false false))
      ((= c0 ")") (depth s n (+ i 1) (- d 1) false false))
      (else (depth s n (+ i 1) d false false)))))
fn digitsOnly s: String i: Int64 -> Bool
  (if (>= i (stringLength s)) true (and (c/isDigit (c/ch s i)) (digitsOnly s (+ i 1))))
fn integerText s: String -> Bool
  (cond ((stringEmpty? s) false)
    ((= (c/ch s 0) "-") (and (> (stringLength s) 1) (digitsOnly s 1)))
    (else (digitsOnly s 0)))
fn pyGapEnd b: String n: Int64 i: Int64 -> Int64
  (let [tail (c/sliceOf b i n) trimmed (cx/pyStrip tail)]
    (+ i (- (stringLength tail) (stringLength trimmed))))
fn keyClose b: String n: Int64 from: Int64 -> (Option (Pair Int64 Int64))
  (match (stringIndexOf (c/sliceOf b from n) "</arg_key>")
    ((none) (none))
    ((some rel)
      (let [ke (+ from rel) ws (pyGapEnd b n (+ ke 10))]
        (if (at b ws "<arg_value>") (some (pair ke ws)) (keyClose b n (+ ke 10))))))
fn argFields b: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (match (stringIndexOf (c/sliceOf b i n) "<arg_key>")
    ((none) (listReverse acc))
    ((some rel)
      (let [ks (+ i rel 9)]
        (match (keyClose b n ks) ((none) (listReverse acc)) ((some kw)
          (let [ke (pairFirst kw) vs (+ (pairSecond kw) 11) vr (stringIndexOf (c/sliceOf b vs n) "</arg_value>")]
            (match vr ((none) (listReverse acc)) ((some endrel)
              (let [ve (+ vs endrel) key (cx/pyStrip (c/sliceOf b ks ke))
                    v (c/sliceOf b vs ve) bare (cx/pyStrip v)
                    field (if (integerText bare) (str ":" key " " bare)
                      (str ":" key " \"" (c/escapeAsn v) "\""))]
                (argFields b n (+ ve 12) (cons field acc)))))))))))
fn rewrite raw: String -> String
  (let [b (cx/pyStrip raw) n (stringLength b) a (stringIndexOf b "<arg_key>")]
    (cond ((= n 0) "")
      ((and (some? a) (not (listEmpty? (argFields b n (optionOr a 0) (list))))) (match a ((some p)
        (let [name (cx/pyStrip (c/sliceOf b 0 p)) fields (argFields b n p (list))]
          (if (stringEmpty? name) "" (str "(:step :op \"" (c/escapeAsn name) "\" " (stringJoin fields " ") ")"))))
        ((none) b)))
      (else (let [f (if (stringStartsWith? b "(") b (if (stringStartsWith? b "step") (str "(:" b) (str "(" b)))
        d (depth f (stringLength f) 0 0 false false)]
        (cond ((> d 0) (str f (stringRepeat ")" d)))
          ((< d 0) (let [z (stringRepeat ")" (- 0 d))]
            (if (stringEndsWith? f z) (c/sliceOf f 0 (+ (stringLength f) d)) f)))
          (else f))))))
fn wrap raw: String -> String
  (let [r (rewrite raw)] (if (stringEmpty? r) "" (str "\n" r "\n")))
fn run s: String es: (List Evt) cur: Int64 active: Int64 out: (List String) count: Int64 -> (Pair String Int64)
  (if (listEmpty? es)
    (let [tail (if (>= active 0) (wrap (c/sliceOf s active (stringLength s))) (c/sliceOf s cur (stringLength s)))
      xs (if (stringEmpty? tail) out (cons tail out))
      n (if (and (>= active 0) (not (stringEmpty? tail))) 1 0)]
      (pair (stringJoin (listReverse xs) "") (+ count n)))
    (match (c/firstOf es) ((evt end open)
      (if open
        (if (>= active 0) (let [r (wrap (c/sliceOf s active (- end 11))) xs (if (stringEmpty? r) out (cons r out))]
          (run s (c/restOf es) end end xs (+ count (if (stringEmpty? r) 0 1))))
          (let [p (c/sliceOf s cur (- end 11))]
            (run s (c/restOf es) end end (if (stringEmpty? p) out (cons p out)) count)))
        (if (>= active 0) (let [r (wrap (c/sliceOf s active (- end (if (at s (- end 3) "]]>") 3 12))))
            xs (if (stringEmpty? r) out (cons r out))]
          (run s (c/restOf es) end -1 xs (+ count (if (stringEmpty? r) 0 1))))
          (run s (c/restOf es) cur -1 out count))))))
fn untagToolCalls input: String -> (Pair String Int64)
  (let [s (if (stringEmpty? input) "" input) es (scan s (stringLength s) 0 false false (list))]
    (if (hasOpen es) (run s es 0 -1 (list) 0) (pair s 0)))

; (:m :ref LEON-WRITE-FAIL-TOP :do "node2 2026-11-17, 136 write stages: cheap models sent step forms the parser turned into an unnamed op that only drew ERR_NO_OP, such as (:step<arg_key>op</arg_key><arg_value>read</arg_value>...), (:step@@) before the real step, and :op read without quotes; each such form is rewritten to the canonical step only when op and its named args map one to one, else it is left as sent and named in :left")
(schema ShapeFix
  (:f text String)
  (:f repaired (List String))
  (:f left (List String)))

fn alpha? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (and (>= c "A") (<= c "Z")))

fn wordEnd s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (or (alpha? (c/ch s i)) (c/isDigit (c/ch s i)))) (wordEnd s n (+ i 1)) i)

fn spaceEnd s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (c/isSpace (c/ch s i))) (spaceEnd s n (+ i 1)) i)

fn formEndAt s: String n: Int64 i: Int64 d: Int64 q: Bool e: Bool -> Int64
  (if (>= i n) -1 (let [c0 (c/ch s i)]
    (cond (q (cond (e (formEndAt s n (+ i 1) d true false))
                   ((= c0 "\\") (formEndAt s n (+ i 1) d true true))
                   ((= c0 "\"") (formEndAt s n (+ i 1) d false false))
                   (else (formEndAt s n (+ i 1) d true false))))
          ((= c0 "\"") (formEndAt s n (+ i 1) d true false))
          ((= c0 "(") (formEndAt s n (+ i 1) (+ d 1) false false))
          ((= c0 ")") (if (<= d 1) (+ i 1) (formEndAt s n (+ i 1) (- d 1) false false)))
          (else (formEndAt s n (+ i 1) d false false)))))

; (:m :ref LEON-WRITE-FAIL-TOP :do "top-level forms of the text it is given as (start end) spans, skipping double-quoted strings and ``` fenced blocks of that text; turnReply passes the reply after raw blocks are bound and fences dropped, so content written through a raw block already sits in a string; an unclosed form ends the scan")
fn topForms s: String n: Int64 i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (cond ((>= i n) (listReverse acc))
    ((at s i "```") (match (stringIndexOf (c/sliceOf s (+ i 3) n) "```")
      ((some rel) (topForms s n (+ i rel 6) acc))
      ((none) (listReverse acc))))
    ((= (c/ch s i) "(") (let [e (formEndAt s n (+ i 1) 1 false false)]
      (if (< e 0) (listReverse acc) (topForms s n e (cons (pair i e) acc)))))
    (else (topForms s n (+ i 1) acc)))

; (:m :ref LEON-WRITE-FAIL-TOP :do "the <arg_key>K</arg_key><arg_value>V</arg_value> chain from i to the closing paren as :K fields, or none when anything else sits between the pairs or the form does not close right after the last one")
fn argChain b: String n: Int64 i: Int64 acc: (List (Pair String String)) -> (Option (List (Pair String String)))
  (let [p (spaceEnd b n i)]
    (cond ((and (= p (- n 1)) (= (c/ch b p) ")")) (if (listEmpty? acc) none (some (listReverse acc))))
      ((not (at b p "<arg_key>")) none)
      (else (match (stringIndexOf (c/sliceOf b (+ p 9) n) "</arg_key>")
        ((none) none)
        ((some kr) (let [ke (+ p 9 kr) key (c/sliceOf b (+ p 9) ke) vs (spaceEnd b n (+ ke 10))]
          (if (or (not (at b vs "<arg_value>")) (or (stringEmpty? key) (!= (wordEnd key (stringLength key) 0) (stringLength key))))
            none
            (match (stringIndexOf (c/sliceOf b (+ vs 11) n) "</arg_value>")
              ((none) none)
              ((some vr) (argChain b n (+ vs 11 vr 12) (cons (pair key (c/sliceOf b (+ vs 11) (+ vs 11 vr))) acc)))))))))))

; (:m :ref LEON-WRITE-FAIL-TOP :do "an integer as parseKv keeps it whole: no leading zero, an optional minus before a nonzero digit (grade 3: 007 ran as 7, file 0123 wrote 123)")
fn canonInt? v: String -> Bool
  (let [d (if (stringStartsWith? v "-") (c/sliceOf v 1 (stringLength v)) v)]
    (and (integerText v) (or (= v "0") (and (not (stringEmpty? d)) (!= (c/ch d 0) "0")))))

fn numericKey? k: String -> Bool
  (listContains? (list "start" "end" "line" "n" "limit" "depth") k)

; (:m :ref LEON-WRITE-FAIL-TOP :do "an arg_value goes unquoted only for a numeric key holding a canonical integer; content, file, cmd, old, new and every other key stay strings, so the model's text reaches the op unchanged")
fn argField kv: (Pair String String) -> String
  (let [v (pairSecond kv)]
    (if (and (numericKey? (pairFirst kv)) (canonInt? v))
      (str ":" (pairFirst kv) " " v)
      (str ":" (pairFirst kv) " \"" (c/escapeAsn v) "\"")))

fn dedupeKeys xs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? xs) acc (dedupeKeys (c/restOf xs) (if (listContains? acc (c/firstOf xs)) acc (cons (c/firstOf xs) acc))))

; (:m :ref LEON-WRITE-FAIL-TOP :do "an arg_key chain maps only when it names op once and no key twice; a repeated key is left (grade of dc02ed63e)")
fn argKeyStep form: String -> (Option String)
  (let [n (stringLength form)]
    (match (argChain form n 6 (list))
      ((none) none)
      ((some kvs) (let [ops (filter (fn [kv] (= (pairFirst kv) "op")) kvs) rest (filter (fn [kv] (!= (pairFirst kv) "op")) kvs)]
        (if (or (!= (listLength ops) 1) (!= (listLength (dedupeKeys (map pairFirst kvs) (list))) (listLength kvs)))
          none
          (let [op (c/firstOf ops) name (pairSecond op)]
            (if (or (stringEmpty? name) (!= (wordEnd name (stringLength name) 0) (stringLength name)))
              none
              (some (str "(:step " (stringJoin (map argField (cons op rest)) " ") ")")))))))))

; (:m :ref LEON-WRITE-FAIL-TOP :do "a (:step...) form with no key at all, such as (:step@@) or (:step): nothing in it names an op")
fn emptyStep? form: String -> Bool
  (let [inner (c/sliceOf form 6 (- (stringLength form) 1))]
    (and (stringStartsWith? form "(:step") (and (not (stringContains? inner ":")) (and (not (stringContains? inner "\"")) (not (stringContains? inner "("))))))

fn simpleTok? t: String -> Bool
  (and (not (stringEmpty? t)) (not (listAny? (fn [x] (stringContains? t x)) (list " " "\t" "\n" "\"" "'" "\\" "(" ")"))))

fn strClose s: String n: Int64 i: Int64 e: Bool -> Int64
  (cond ((>= i n) -1)
    (e (strClose s n (+ i 1) false))
    ((= (c/ch s i) "\\") (strClose s n (+ i 1) true))
    ((= (c/ch s i) "\"") (+ i 1))
    (else (strClose s n (+ i 1) false)))

fn digitEnd s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (c/isDigit (c/ch s i))) (digitEnd s n (+ i 1)) i)

fn boundary? s: String n: Int64 j: Int64 -> Bool
  (and (< j n) (or (c/isSpace (c/ch s j)) (= (c/ch s j) ")")))

; (:m :ref LEON-WRITE-FAIL-TOP :do "one value at v for key: (token kind end), kind empty when the value is kept as sent; none when it does not map one to one: a double-quoted string, an integer, true or false are kept, a single-quoted value without space, quote, backslash or paren becomes double-quoted, a bare word only after :op; anything else, such as 'don't', 'hello world', 'it\\'s' or a bare multi-word value, is left (grade of dc02ed63e)")
fn valueAt s: String n: Int64 v: Int64 key: String -> (Option (Pair String (Pair String Int64)))
  (let [c0 (c/ch s v)]
    (cond ((= c0 "\"") (let [e (strClose s n (+ v 1) false)]
            (if (and (> e 0) (boundary? s n e)) (some (pair (c/sliceOf s v e) (pair "" e))) none)))
      ((= c0 "'") (match (stringIndexOf (c/sliceOf s (+ v 1) n) "'")
        ((none) none)
        ((some r) (let [q (+ v 1 r) inner (c/sliceOf s (+ v 1) q)]
          (if (and (simpleTok? inner) (boundary? s n (+ q 1)))
            (some (pair (str "\"" inner "\"") (pair (if (= key "op") "opQuote" "argQuote") (+ q 1))))
            none)))))
      ((or (c/isDigit c0) (and (= c0 "-") (c/isDigit (c/ch s (+ v 1))))) (let [e (digitEnd s n (+ v 1))]
        (if (and (boundary? s n e) (canonInt? (c/sliceOf s v e))) (some (pair (c/sliceOf s v e) (pair "" e))) none)))
      ((alpha? c0) (let [we (wordEnd s n v) w (c/sliceOf s v we)]
        (cond ((not (boundary? s n we)) none)
          ((= key "op") (some (pair (str "\"" w "\"") (pair "bareOp" we))))
          ((or (= w "true") (= w "false")) (some (pair w (pair "" we))))
          (else none))))
      (else none)))

; (:m :ref LEON-WRITE-FAIL-TOP :do "the whole (:step ...) form from i as distinct :key value pairs up to its closing paren, with the kinds rewritten; none when any token is not part of a pair, a key repeats or a value does not map one to one")
fn pairsFrom s: String n: Int64 i: Int64 keys: (List String) out: (List String) kinds: (List String) -> (Option (Pair (List String) (List String)))
  (let [p (spaceEnd s n i)]
    (cond ((>= p n) none)
      ((= (c/ch s p) ")") (if (and (= p (- n 1)) (listContains? keys "op")) (some (pair (listReverse out) kinds)) none))
      ((or (= p i) (!= (c/ch s p) ":")) none)
      (else (let [ke (wordEnd s n (+ p 1)) key (c/sliceOf s (+ p 1) ke)]
        (if (or (stringEmpty? key) (or (listContains? keys key) (not (and (< ke n) (c/isSpace (c/ch s ke))))))
          none
          (match (valueAt s n (spaceEnd s n ke) key)
            ((none) none)
            ((some tv) (let [kind (pairFirst (pairSecond tv))]
              (pairsFrom s n (pairSecond (pairSecond tv)) (cons key keys) (cons (str ":" key " " (pairFirst tv)) out)
                (if (or (stringEmpty? kind) (listContains? kinds kind)) kinds (listAppend kinds (list kind))))))))))))

; (:m :ref LEON-WRITE-FAIL-TOP :do "(:step :op read ...) and (:step :op 'read' ...): rewritten only when the whole form parses as pairs without loss (pairsFrom); a form whose :op is already double-quoted is kept as sent, any other unparsed form is left as opShape")
fn opWordStep form: String -> (Pair (Option String) (List String))
  (match (pairsFrom form (stringLength form) 6 (list) (list) (list))
    ((some r) (if (listEmpty? (pairSecond r)) (pair none (list))
      (pair (some (str "(:step " (stringJoin (pairFirst r) " ") ")")) (pairSecond r))))
    ((none) (if (stringContains? form ":op \"") (pair none (list)) (pair none (list "opShape")))))

fn named? form: String -> Bool
  (and (stringStartsWith? form "(:step") (not (emptyStep? form)))

fn fixForm form: String others: Bool -> (Pair (Option String) (Pair (List String) (List String)))
  (cond ((not (stringStartsWith? form "(:step")) (pair none (pair (list) (list))))
    ((stringStartsWith? form "(:step<arg_key>")
      (match (argKeyStep form)
        ((some f) (pair (some f) (pair (list "argKey") (list))))
        ((none) (pair none (pair (list) (list "argKey"))))))
    ((emptyStep? form) (if others (pair (some "") (pair (list "emptyStep") (list))) (pair none (pair (list) (list "emptyStep")))))
    (else (let [r (opWordStep form)]
      (match (pairFirst r)
        ((some f) (pair (some f) (pair (pairSecond r) (list))))
        ((none) (pair none (pair (list) (pairSecond r))))))))

fn applyFixes s: String spans: (List (Pair Int64 Int64)) others: Bool cur: Int64 out: (List String) rep: (List String) left: (List String) -> ShapeFix
  (if (listEmpty? spans)
    (ShapeFix :text (stringJoin (listReverse (cons (c/sliceOf s cur (stringLength s)) out)) "") :repaired rep :left left)
    (let [sp (c/firstOf spans) rest (c/restOf spans) a (pairFirst sp) b (pairSecond sp) r (fixForm (c/sliceOf s a b) others)
          rep2 (listAppend rep (pairFirst (pairSecond r))) left2 (listAppend left (pairSecond (pairSecond r)))]
      (match (pairFirst r)
        ((some f) (applyFixes s rest others b (cons f (cons (c/sliceOf s cur a) out)) rep2 left2))
        ((none) (applyFixes s rest others cur out rep2 left2)))))

; (:m :ref LEON-WRITE-FAIL-TOP :do "canonical step forms for a reply: every top-level (:step ...) form in an alternate wire shape that maps unambiguously is rewritten, an empty (:step@@) beside a named step is dropped; :repaired and :left name each kind once per form, the text is unchanged when nothing was repaired")
fn canonSteps input: String -> ShapeFix
  (let [n (stringLength input)
        spans (topForms input n 0 (list))
        others (listAny? (fn [sp] (let [f (c/sliceOf input (pairFirst sp) (pairSecond sp))]
                 (or (and (named? f) (not (stringStartsWith? f "(:step<arg_key>"))) (some? (argKeyStep f))))) spans)]
    (applyFixes input spans others 0 (list) (list) (list)))
