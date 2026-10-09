(module asl-syntax/asl/asn
  :x [AsnValue
      AsnField
      AsnEntry
      AsnStep
      asnRead
      asnReadForms
      asnWrite
      parseStep
      cstToAsnValue
      nodeToAsnValue
      nodeToStep
      isVec?
      isKw?
      valueOk?
      vecItems
      asnIntValue
      asnFloatValue
      asnStringValue
      asnUnescape]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/asl/paren :a prn)])

(schema AsnField
  (:f key String)
  (:f val AsnValue))

(schema AsnEntry
  (:f key AsnValue)
  (:f val AsnValue)
  (:f paren Bool))

(schema AsnStep
  (:f op String)
  (:f kwargs (Map String String))
  (:f args (List String)))

(enum AsnValue
  (:c asnNil [])
  (:c asnBool [(b Bool)])
  (:c asnUnit [])
  (:c asnInt [(lex String)])
  (:c asnFloat [(lex String)])
  (:c asnStr [(lex String)])
  (:c asnKw [(k String)])
  (:c asnSym [(name String)])
  (:c asnVec [(items (List AsnValue))])
  (:c asnMap [(entries (List AsnEntry))])
  (:c asnRec [(fields (List AsnField))])
  (:c asnCtor [(name String) (fields (List AsnField))])
  (:c asnRows [(name String) (rows (List AsnValue))])
  (:c asnTable [(cols (List AsnValue)) (rows (List AsnValue))])
  (:c asnCase [(name String) (args (List AsnValue))])
  (:c asnPair [(key AsnValue) (val AsnValue)]))

fn valueOk? v: AsnValue -> Bool
  (mt v
    ((asnSym _) false)
    ((asnPair _ _) false)
    (_ true))

fn isVec? v: AsnValue -> Bool
  (mt v
    ((asnVec _) true)
    (_ false))

fn isKw? v: AsnValue -> Bool
  (mt v
    ((asnKw _) true)
    (_ false))

fn vecItems v: AsnValue -> (List AsnValue)
  (mt v
    ((asnVec items) items)
    (_ (list)))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn sliceToken text: String tok: tr/Token -> String
  (optionOr (stringSlice text tok.start tok.end) "")

fn sliceElem text: String elem: tr/TreeElement -> String
  (optionOr (stringSlice text (tr/elementStart elem) (tr/elementEnd elem)) "")

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn byteChar n: Int64 -> String
  (optionOr (stringSlice (byteTable) n (+ n 1)) "")

fn utf8Of cp: Int64 -> String
  (cond
    ((< cp 128) (byteChar cp))
    ((< cp 2048) (str (byteChar (+ 192 (/ cp 64))) (byteChar (+ 128 (mod cp 64)))))
    ((< cp 65536) (str (byteChar (+ 224 (/ cp 4096))) (byteChar (+ 128 (mod (/ cp 64) 64))) (byteChar (+ 128 (mod cp 64)))))
    (else (str (byteChar (+ 240 (/ cp 262144))) (byteChar (+ 128 (mod (/ cp 4096) 64))) (byteChar (+ 128 (mod (/ cp 64) 64))) (byteChar (+ 128 (mod cp 64))))))

fn hexDigitAt s: String i: Int64 -> Int64
  (let [(c (charAt s i))]
    (if (= (stringLength c) 1) (optionOr (stringIndexOf "0123456789abcdef" (stringLower c)) -1) -1))

fn hexRun s: String i: Int64 count: Int64 acc: Int64 -> Int64
  (if (<= count 0)
    acc
    (let [(d (hexDigitAt s i))]
      (if (< d 0) -1 (hexRun s (+ i 1) (- count 1) (+ (* acc 16) d)))))

fn scalarValue? cp: Int64 -> Bool
  (and (>= cp 0) (and (<= cp 1114111) (or (< cp 55296) (> cp 57343))))

fn bracedRun s: String i: Int64 count: Int64 acc: Int64 -> (Pair Int64 Int64)
  (let [(d (hexDigitAt s i))]
    (cond
      ((= (charAt s i) "}") (if (and (> count 0) (scalarValue? acc)) (pair acc (+ i 1)) (pair -1 i)))
      ((and (>= d 0) (< count 6)) (bracedRun s (+ i 1) (+ count 1) (+ (* acc 16) d)))
      (else (pair -1 i))))

fn unicodeAt s: String i: Int64 -> (Pair Int64 Int64)
  (if (= (charAt s i) "{")
    (bracedRun s (+ i 1) 0 0)
    (let [(cp (hexRun s i 4 0))]
      (if (scalarValue? cp) (pair cp (+ i 4)) (pair -1 i))))

fn unescapeLoop s: String i: Int64 n: Int64 acc: (List String) -> (Result String String)
  (if (>= i n)
    (ok (stringJoin (listReverse acc) ""))
    (let [(c (charAt s i))]
      (if (!= c "\\")
        (unescapeLoop s (+ i 1) n (cons c acc))
        (let [(nx (charAt s (+ i 1)))
              (x (hexRun s (+ i 2) 2 0))
              (u (if (= nx "u") (unicodeAt s (+ i 2)) (pair -1 i)))]
          (cond
            ((= nx "n") (unescapeLoop s (+ i 2) n (cons "\n" acc)))
            ((= nx "t") (unescapeLoop s (+ i 2) n (cons "\t" acc)))
            ((= nx "r") (unescapeLoop s (+ i 2) n (cons "\r" acc)))
            ((or (= nx "\"") (= nx "\\")) (unescapeLoop s (+ i 2) n (cons nx acc)))
            ((and (= nx "x") (>= x 0)) (unescapeLoop s (+ i 4) n (cons (byteChar x) acc)))
            ((= nx "x") (err (str "ERR_BAD_ESCAPE at " (stringFromInt64 i) ": \\x needs exactly 2 hex digits")))
            ((>= (pairFirst u) 0) (unescapeLoop s (pairSecond u) n (cons (utf8Of (pairFirst u)) acc)))
            ((= nx "u") (err (str "ERR_BAD_ESCAPE at " (stringFromInt64 i) ": \\u needs 4 hex digits or {1 to 6 hex digits} naming a scalar value")))
            (else (err (str "ERR_BAD_ESCAPE at " (stringFromInt64 i) ": unknown escape \\" nx))))))))

fn asnUnescape s: String -> (Result String String)
  (if (stringContains? s "\\")
    (unescapeLoop s 0 (stringLength s) (list))
    (ok s))

fn stripQuotes s: String -> String
  (let [(n (stringLength s))]
    (if (and (>= n 2) (stringStartsWith? s "\"") (stringEndsWith? s "\""))
      (optionOr (stringSlice s 1 (- n 1)) "")
      s))

fn asnIntValue v: AsnValue -> (Option Int64)
  (mt v
    ((asnInt lex) (stringToInt64 lex))
    (_ (none)))

fn asnFloatValue v: AsnValue -> (Option Float64)
  (mt v
    ((asnFloat lex) (stringToFloat64 lex))
    (_ (none)))

fn asnStringValue v: AsnValue -> (Option String)
  (mt v
    ((asnStr lex) (mt (asnUnescape (stripQuotes lex)) ((ok v) (some v)) ((err _) (none))))
    (_ (none)))

(enum WItem
  (:c wText [(t String)])
  (:c wVal [(v AsnValue)]))

(schema WState
  (:f work (List WItem))
  (:f out (List String)))

fn wAtom? v: AsnValue -> Bool
  (mt v
    ((asnNil) true)
    ((asnBool _) true)
    ((asnUnit) true)
    ((asnInt _) true)
    ((asnFloat _) true)
    ((asnStr _) true)
    ((asnKw _) true)
    ((asnSym _) true)
    (_ false))

fn wAtom v: AsnValue -> String
  (mt v
    ((asnNil) "_")
    ((asnBool b) (if b "true" "false"))
    ((asnUnit) "()")
    ((asnInt lex) lex)
    ((asnFloat lex) lex)
    ((asnStr lex) lex)
    ((asnKw k) k)
    ((asnSym s) s)
    (_ ""))

fn wOpen v: AsnValue -> String
  (mt v
    ((asnVec _) "[")
    ((asnMap _) "{")
    (_ "("))

fn wClose v: AsnValue -> String
  (mt v
    ((asnVec _) "]")
    ((asnMap _) "}")
    (_ ")"))

fn wFields fs: (List AsnField) -> (List WItem)
  (fold (fn [(acc (List WItem)) (f AsnField)] -> (List WItem)
          (listAppend acc (list (wText f.key) (wVal f.val))))
        (list) fs)

fn wEntries es: (List AsnEntry) -> (List WItem)
  (fold (fn [(acc (List WItem)) (e AsnEntry)] -> (List WItem)
          (listAppend acc
                      (if e.paren
                        (list (wVal (asnPair e.key e.val)))
                        (list (wVal e.key) (wVal e.val)))))
        (list) es)

fn wVals vs: (List AsnValue) -> (List WItem)
  (map (fn [(v AsnValue)] -> WItem (wVal v)) vs)

fn wChildren v: AsnValue -> (List WItem)
  (mt v
    ((asnVec items) (wVals items))
    ((asnMap es) (wEntries es))
    ((asnRec fs) (wFields fs))
    ((asnCtor n fs) (cons (wText n) (wFields fs)))
    ((asnRows n rows) (cons (wText n) (wVals rows)))
    ((asnTable cs rs) (list (wVal (asnVec cs)) (wVal (asnVec rs))))
    ((asnCase n args) (cons (wText n) (wVals args)))
    ((asnPair k val) (list (wVal k) (wVal val)))
    (_ (list)))

fn wSeparated items: (List WItem) -> (List WItem)
  (mt (listHead items)
    ((some h)
     (let [(tailItems (optionOr (listTail items) (list)))]
       (cons h (listReverse (fold (fn [(acc (List WItem)) (x WItem)] -> (List WItem)
                                    (cons x (cons (wText " ") acc)))
                                  (list) tailItems)))))
    ((none) (list)))

fn wWrap v: AsnValue -> (List WItem)
  (cons (wText (wOpen v))
        (listAppend (wSeparated (wChildren v)) (list (wText (wClose v)))))

fn wTick st: WState tick: Int64 -> WState
  (mt (listHead st.work)
    ((some it)
     (let [(rest (optionOr (listTail st.work) (list)))]
       (mt it
         ((wText t) (WState :work rest :out (cons t st.out)))
         ((wVal v)
          (if (wAtom? v)
            (WState :work rest :out (cons (wAtom v) st.out))
            (with st :work (listAppend (wWrap v) rest)))))))
    ((none) st))

fn wRun st: WState budget: Int64 -> WState
  (let [(next (fold wTick st (range 0 budget)))]
    (if (listEmpty? next.work)
      next
      (wRun next (+ budget budget))))

fn asnWrite v: AsnValue -> String
  (stringJoin (listReverse (wRun (WState :work (list (wVal v)) :out (list)) 64).out) "")

fn isUpper? c: String -> Bool
  (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" c)

fn isLower? c: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyz" c)

(enum HeadKind
  (:c headType [])
  (:c headCase [])
  (:c headBad []))

fn allCharsIn? s: String allowed: String -> Bool
  (and (not (stringEmpty? s))
       (listEmpty? (filter (fn [(c String)] -> Bool (not (stringContains? allowed c))) (stringChars s))))

fn firstChar s: String -> String
  (mt (stringSlice s 0 1) ((some c) c) ((none) ""))

fn kebabOk? s: String -> Bool
  (and (not (stringEmpty? s))
       (and (isLower? (firstChar s))
            (and (not (stringContains? s "--"))
                 (and (not (stringEndsWith? s "-"))
                      (allCharsIn? s "abcdefghijklmnopqrstuvwxyz0123456789-")))))

fn stripIdentSuffix s: String -> String
  (if (or (stringEndsWith? s "?") (stringEndsWith? s "!"))
    (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")
    s)

fn identOk? s: String -> Bool
  (kebabOk? (stripIdentSuffix s))

fn typeNameOk? s: String -> Bool
  (and (not (stringEmpty? s))
       (and (isUpper? (firstChar s))
            (allCharsIn? s "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")))

fn bareHeadKind s: String -> HeadKind
  (cond
    ((typeNameOk? s) (headType))
    ((identOk? s) (headCase))
    (else (headBad)))

fn partAt parts: (List String) i: Int64 -> String
  (mt (listGet parts i) ((some p) p) ((none) ""))

fn headKind name: String -> HeadKind
  (let [(parts (stringSplit name "/"))]
    (cond
      ((= (listLength parts) 1) (bareHeadKind name))
      ((= (listLength parts) 2)
       (if (kebabOk? (partAt parts 0))
         (bareHeadKind (partAt parts 1))
         (headBad)))
      (else (headBad))))

fn nthValue items: (List AsnValue) i: Int64 -> AsnValue
  (mt (listGet items i) ((some v) v) ((none) (asnNil)))

fn allValues? items: (List AsnValue) -> Bool
  (listEmpty? (filter (fn [(v AsnValue)] -> Bool (not (valueOk? v))) items))

fn allVectors? items: (List AsnValue) -> Bool
  (listEmpty? (filter (fn [(v AsnValue)] -> Bool (not (isVec? v))) items))

fn allKeywords? items: (List AsnValue) -> Bool
  (listEmpty? (filter (fn [(v AsnValue)] -> Bool (not (isKw? v))) items))

fn fieldKey fs: (List AsnField) -> String
  (mt (listHead fs) ((some f) f.key) ((none) ""))

fn fieldVal fs: (List AsnField) -> AsnValue
  (mt (listHead fs) ((some f) f.val) ((none) (asnNil)))

fn fieldsOf items: (List AsnValue) acc: (List AsnField) -> (Result (List AsnField) String)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some k)
     (mt k
       ((asnKw key)
        (let [(tail (optionOr (listTail items) (list)))]
          (mt (listHead tail)
            ((some v)
             (if (valueOk? v)
               (fieldsOf (optionOr (listTail tail) (list)) (cons (AsnField :key key :val v) acc))
               (err "parse")))
            ((none) (err "parse")))))
       (_ (err "parse")))))

fn buildRecord items: (List AsnValue) -> (Result AsnValue String)
  (mt (fieldsOf items (list))
    ((ok fs)
     (if (listEmpty? fs)
       (err "parse")
       (ok (asnRec fs))))
    ((err c) (err c)))

fn buildSchemaHead name: String rest: (List AsnValue) -> (Result AsnValue String)
  (mt (listHead rest)
    ((none) (ok (asnCtor name (list))))
    ((some h)
     (mt h
       ((asnVec _) (if (allVectors? rest) (ok (asnRows name rest)) (err "parse")))
       ((asnKw _) (mt (fieldsOf rest (list)) ((ok fs) (ok (asnCtor name fs))) ((err c) (err c))))
       (_ (err "parse")))))

fn buildNamed name: String rest: (List AsnValue) -> (Result AsnValue String)
  (mt (headKind name)
    ((headType) (buildSchemaHead name rest))
    ((headCase) (if (allValues? rest) (ok (asnCase name rest)) (err "parse")))
    ((headBad) (err "parse")))

fn buildTable items: (List AsnValue) -> (Result AsnValue String)
  (if (= (listLength items) 2)
    (let [(cols (vecItems (nthValue items 0)))
          (rows (vecItems (nthValue items 1)))]
      (if (and (isVec? (nthValue items 1)) (and (allKeywords? cols) (allVectors? rows)))
        (ok (asnTable cols rows))
        (err "parse")))
    (err "parse"))

fn buildPair items: (List AsnValue) -> (Result AsnValue String)
  (if (= (listLength items) 2)
    (let [(v (nthValue items 1))]
      (if (valueOk? v)
        (ok (asnPair (nthValue items 0) v))
        (err "parse")))
    (err "parse"))

fn entriesOf items: (List AsnValue) acc: (List AsnEntry) -> (Result (List AsnEntry) String)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some h)
     (let [(tail (optionOr (listTail items) (list)))]
       (mt h
         ((asnKw key)
          (mt (listHead tail)
            ((some v)
             (if (valueOk? v)
               (entriesOf (optionOr (listTail tail) (list)) (cons (AsnEntry :key (asnKw key) :val v :paren false) acc))
               (err "parse")))
            ((none) (err "parse"))))
         ((asnPair k v)
          (entriesOf tail (cons (AsnEntry :key k :val v :paren true) acc)))
         ((asnRec fs)
          (if (= (listLength fs) 1)
            (entriesOf tail (cons (AsnEntry :key (asnKw (fieldKey fs)) :val (fieldVal fs) :paren true) acc))
            (err "parse")))
         (_ (err "parse"))))))

fn isTriviaElem elem: tr/TreeElement -> Bool
  (mt elem
    ((tr/elemToken tok) (tr/isTrivia tok))
    ((tr/elemNode _) false))

fn filterMeaningfulKids kids: (List tr/TreeElement) -> (List tr/TreeElement)
  (filter (fn [(e tr/TreeElement)] -> Bool (not (isTriviaElem e))) kids)

fn dropFirstAndLast elems: (List tr/TreeElement) -> (List tr/TreeElement)
  (mt (listTail elems)
    ((none) (list))
    ((some tail1)
     (let [(rev (listReverse tail1))]
       (mt (listTail rev)
         ((none) (list))
         ((some revTail) (listReverse revTail))))))

fn tokenToAsnValue text: String tok: tr/Token -> (Result AsnValue String)
  (let [(k tok.kind)
        (raw (sliceToken text tok))]
    (cond
      ((= k "int") (ok (asnInt raw)))
      ((= k "float") (ok (asnFloat raw)))
      ((= k "string") (ok (asnStr raw)))
      ((= k "keyword") (ok (asnKw raw)))
      ((= k "symbol")
       (cond
         ((= raw "true") (ok (asnBool true)))
         ((= raw "false") (ok (asnBool false)))
         ((= raw "_") (ok (asnNil)))
         (else (ok (asnSym raw)))))
      (else (err "parse"))))

fn elementsToValues text: String elems: (List tr/TreeElement) acc: (List AsnValue) -> (Result (List AsnValue) String)
  (mt (listHead elems)
    ((none) (ok (listReverse acc)))
    ((some elem)
     (let [(rest (optionOr (listTail elems) (list)))]
       (mt (cstToAsnValue text elem)
         ((ok v) (elementsToValues text rest (cons v acc)))
         ((err e) (err e))))))

fn buildCstVector text: String kids: (List tr/TreeElement) -> (Result AsnValue String)
  (let [(inner (dropFirstAndLast kids))]
    (mt (elementsToValues text inner (list))
      ((ok vals)
       (if (allValues? vals)
         (ok (asnVec vals))
         (err "parse")))
      ((err e) (err e))))

fn buildCstMap text: String kids: (List tr/TreeElement) -> (Result AsnValue String)
  (let [(inner (dropFirstAndLast kids))]
    (mt (elementsToValues text inner (list))
      ((ok vals)
       (mt (entriesOf vals (list))
         ((ok es) (ok (asnMap es)))
         ((err e) (err e))))
      ((err e) (err e))))

fn buildCstList text: String kids: (List tr/TreeElement) -> (Result AsnValue String)
  (let [(inner (dropFirstAndLast kids))]
    (if (listEmpty? inner)
      (if (= (listLength kids) 2)
        (let [(oElem (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))
              (cElem (optionOr (listHead (optionOr (listTail kids) (list))) (tr/elemToken (tr/makeToken "" 0 0))))]
          (mt oElem
            ((tr/elemToken oTok)
             (mt cElem
               ((tr/elemToken cTok)
                (if (and (= oTok.kind "lparen") (= cTok.kind "rparen"))
                  (if (= oTok.end cTok.start)
                    (ok (asnUnit))
                    (err "parse"))
                  (err "parse")))
               ((tr/elemNode _) (err "parse"))))
            ((tr/elemNode _) (err "parse"))))
        (err "parse"))
      (mt (elementsToValues text inner (list))
        ((ok items)
         (mt (listHead items)
           ((none) (err "parse"))
           ((some h)
            (mt h
              ((asnKw _) (buildRecord items))
              ((asnSym s) (buildNamed s (optionOr (listTail items) (list))))
              ((asnVec _) (buildTable items))
              ((asnStr _) (buildPair items))
              ((asnInt _) (buildPair items))
              ((asnBool _) (buildPair items))
              (_ (err "parse"))))))
        ((err e) (err e)))))

fn nodeToAsnValue text: String node: tr/Node -> (Result AsnValue String)
  (let [(k node.kind)]
    (cond
      ((= k "vector")
       (buildCstVector text (filterMeaningfulKids node.children)))
      ((= k "map")
       (buildCstMap text (filterMeaningfulKids node.children)))
      ((= k "list")
       (buildCstList text (filterMeaningfulKids node.children)))
      (else (err "parse"))))

fn cstToAsnValue text: String elem: tr/TreeElement -> (Result AsnValue String)
  (mt elem
    ((tr/elemToken tok) (tokenToAsnValue text tok))
    ((tr/elemNode node) (nodeToAsnValue text node)))

fn readError text: String -> String
  (mt (listHead (filter (fn [(t tr/Token)] -> Bool (and (tr/isErrorToken t) (stringStartsWith? (sliceToken text t) "\""))) (lx/tokenize text)))
    ((none) "parse")
    ((some t) (mt (asnUnescape (stripQuotes (sliceToken text t)))
                ((err e) e)
                ((ok _) "parse"))))

fn asnRead text: String -> (Result AsnValue String)
  (let [(root (prn/parseString text))]
    (if (prn/hasErrors root)
      (err (readError text))
      (let [(forms (prn/topLevelForms root))]
        (if (!= (listLength forms) 1)
          (err "parse")
          (mt (listHead forms)
            ((none) (err "parse"))
            ((some form)
             (mt (cstToAsnValue text form)
               ((ok v) (if (valueOk? v) (ok v) (err "parse")))
               ((err e) (err e)))))))))

fn asnReadForms text: String -> (Result (List AsnValue) String)
  (let [(root (prn/parseString text))]
    (if (prn/hasErrors root)
      (err (readError text))
      (let [(forms (prn/topLevelForms root))]
        (elementsToValues text forms (list)))))

fn isKeywordElem elem: tr/TreeElement -> Bool
  (mt elem
    ((tr/elemToken tok) (= tok.kind "keyword"))
    ((tr/elemNode _) false))

fn subArgKey? k: String -> Bool
  (listContains? (list "mode" "action" "status" "distill" "engine" "op" "stepOp" "direction" "kind" "format" "role" "depth" "service" "type" "profile" "lenses" "target" "model" "subcmd" "tier" "level" "scope" "topic") k)

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":")
    (lstripColons (optionOr (stringSlice s 1 (stringLength s)) ""))
    s)

fn isSpaceChar c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn skipSpaces s: String i: Int64 n: Int64 -> Int64
  (if (>= i n)
    i
    (let [(c (charAt s i))]
      (if (isSpaceChar c)
        (skipSpaces s (+ i 1) n)
        i)))

fn scanStringEnd s: String i: Int64 n: Int64 esc: Bool -> Int64
  (if (>= i n)
    i
    (let [(c (charAt s i))]
      (if esc
        (scanStringEnd s (+ i 1) n false)
        (if (= c "\\")
          (scanStringEnd s (+ i 1) n true)
          (if (= c "\"")
            (+ i 1)
            (scanStringEnd s (+ i 1) n false))))))

fn scanBracketEnd s: String i: Int64 n: Int64 depth: Int64 openC: String closeC: String inQ: Bool esc: Bool -> Int64
  (if (>= i n)
    i
    (let [(c (charAt s i))]
      (cond
        (esc
         (scanBracketEnd s (+ i 1) n depth openC closeC inQ false))
        ((= c "\\")
         (scanBracketEnd s (+ i 1) n depth openC closeC inQ inQ))
        ((= c "\"")
         (scanBracketEnd s (+ i 1) n depth openC closeC (not inQ) false))
        (inQ
         (scanBracketEnd s (+ i 1) n depth openC closeC inQ false))
        ((= c openC)
         (scanBracketEnd s (+ i 1) n (+ depth 1) openC closeC false false))
        ((= c closeC)
         (if (= depth 1)
           (+ i 1)
           (scanBracketEnd s (+ i 1) n (- depth 1) openC closeC false false)))
        (else
         (scanBracketEnd s (+ i 1) n depth openC closeC false false)))))

fn scanBareEnd s: String i: Int64 n: Int64 -> Int64
  (if (>= i n)
    i
    (let [(c (charAt s i))]
      (if (isSpaceChar c)
        i
        (scanBareEnd s (+ i 1) n))))

fn stepTokensLoop s: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (let [(pos (skipSpaces s i n))]
    (if (>= pos n)
      (listReverse acc)
      (let [(c (charAt s pos))]
        (cond
          ((= c "\"")
           (let [(endIdx (scanStringEnd s (+ pos 1) n false))
                 (tok (optionOr (stringSlice s pos endIdx) ""))]
             (stepTokensLoop s endIdx n (cons tok acc))))
          ((or (= c "(") (= c "["))
           (let [(closeC (if (= c "(") ")" "]"))
                 (endIdx (scanBracketEnd s pos n 0 c closeC false false))
                 (tok (optionOr (stringSlice s pos endIdx) ""))]
             (stepTokensLoop s endIdx n (cons tok acc))))
          (else
           (let [(endIdx (scanBareEnd s pos n))
                 (tok (optionOr (stringSlice s pos endIdx) ""))]
             (stepTokensLoop s endIdx n (cons tok acc))))))))

fn tokenizeStep s: String -> (List String)
  (let [(trimmed (stringTrim s))
        (stripped (if (and (stringStartsWith? trimmed "(") (stringEndsWith? trimmed ")"))
                    (stringTrim (optionOr (stringSlice trimmed 1 (- (stringLength trimmed) 1)) ""))
                    trimmed))]
    (stepTokensLoop stripped 0 (stringLength stripped) (list)))

fn unquoteTok tok: String -> (Result String String)
  (if (and (stringStartsWith? tok "\"") (and (stringEndsWith? tok "\"") (>= (stringLength tok) 2)))
    (asnUnescape (optionOr (stringSlice tok 1 (- (stringLength tok) 1)) ""))
    (ok tok))

fn parseStepTokLoop toks: (List String) kw: (Map String String) args: (List String) -> (Result (Pair (Map String String) (List String)) String)
  (mt (listHead toks)
    ((none) (ok (pair kw (listReverse args))))
    ((some tok)
     (let [(rest (optionOr (listTail toks) (list)))]
       (if (stringStartsWith? tok ":")
         (let [(key (lstripColons tok))]
           (mt (listHead rest)
             ((none) (parseStepTokLoop rest (mapSet kw key "true") args))
             ((some nextTok)
              (let [(after (optionOr (listTail rest) (list)))
                    (hasSubArg (mt (listHead after)
                                 ((none) false)
                                 ((some t2) (not (stringStartsWith? t2 ":")))))
                    (nextIsKw (stringStartsWith? nextTok ":"))
                    (takes (or (not nextIsKw)
                               (and (not hasSubArg) (or (subArgKey? key) (listEmpty? after)))))]
                (if takes
                  (mt (unquoteTok nextTok)
                    ((ok val) (parseStepTokLoop after (mapSet kw key val) args))
                    ((err e) (err e)))
                  (parseStepTokLoop rest (mapSet kw key "true") args))))))
         (mt (unquoteTok tok)
           ((ok val) (parseStepTokLoop rest kw (cons val args)))
           ((err e) (err e)))))))

fn parseStep stepStr: String -> (Result AsnStep String)
  (let [(toks (tokenizeStep stepStr))]
    (mt (listHead toks)
      ((none) (ok (AsnStep :op "" :kwargs (mapEmpty) :args (list))))
      ((some firstTok)
       (let [(op (lstripColons firstTok))
             (rest (optionOr (listTail toks) (list)))]
         (mt (parseStepTokLoop rest (mapEmpty) (list))
           ((ok parsed) (ok (AsnStep :op op :kwargs (pairFirst parsed) :args (pairSecond parsed))))
           ((err e) (err e)))))))

fn nodeToStep text: String node: tr/Node -> (Result AsnStep String)
  (parseStep (sliceElem text (tr/elemNode node)))
