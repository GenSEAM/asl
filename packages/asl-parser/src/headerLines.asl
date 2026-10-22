(module asl-parser/headerLines
  :x [HeaderError normalizeHeader headerError strictHeaders lineHeader? oldHeader? oldTypeDeclLine]
  :i [])

(schema HeaderError (:f msg String) (:f line Int64) (:f col Int64))

(schema HLine (:f kind Int64) (:f text String) (:f no Int64))

(schema HScan (:f lines (List HLine)) (:f rest (List String)) (:f no Int64) (:f err (Option HeaderError)))

fn strictHeaders -> Bool
  false

fn kModule -> Int64
  0

fn kDoc -> Int64
  1

fn kExports -> Int64
  2

fn kImport -> Int64
  3

fn kBlank -> Int64
  4

fn kComment -> Int64
  5

fn kDocMore -> Int64
  6

fn words s: String -> (List String)
  (filter (fn [w] (not (stringEmpty? w))) (stringSplit (stringReplace (stringTrim s) "\t" " ") " "))

fn sliceFrom s: String i: Int64 -> String
  (optionOr (stringSlice s i (stringLength s)) "")

fn blank? s: String -> Bool
  (stringEmpty? (stringTrim s))

fn comment? s: String -> Bool
  (stringStartsWith? (stringTrim s) ";")

fn keyLine? s: String key: String -> Bool
  (or (= s key) (stringStartsWith? s (str key " ")))

fn quoteEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet b i) 92) (quoteEnd b n (+ i 2)))
    ((= (bytesGet b i) 34) i)
    (else (quoteEnd b n (+ i 1))))

fn byteAt b: Bytes n: Int64 i: Int64 c: Int64 -> Int64
  (cond ((>= i n) -1) ((= (bytesGet b i) c) i) (else (byteAt b n (+ i 1) c)))

fn firstQuote s: String -> Int64
  (let [(b (stringToBytes s))] (byteAt b (bytesLength b) 0 34))

fn openAfter s: String from: Int64 -> Bool
  (let [(b (stringToBytes s))] (< (quoteEnd b (bytesLength b) from) 0))

fn firstContent lines: (List String) no: Int64 -> (Option (Pair String Int64))
  (match (listHead lines)
    ((none) (none))
    ((some l) (if (or (blank? l) (comment? l)) (firstContent (optionOr (listTail lines) (list)) (+ no 1)) (some (pair l no)))))

fn lineHeader? src: String -> Bool
  (match (firstContent (stringSplit src "\n") 1)
    ((some p) (keyLine? (pairFirst p) "module"))
    ((none) false))

fn oldHeader? src: String -> Bool
  (match (firstContent (stringSplit src "\n") 1)
    ((some p) (stringStartsWith? (pairFirst p) "(module"))
    ((none) false))

fn bad msg: String no: Int64 -> (Option HeaderError)
  (some (HeaderError :msg (str "ERR_READ_HEADER " msg) :line no :col 1))

fn checkLine l: String no: Int64 -> (Option HeaderError)
  (let [(ws (words l)) (n (listLength ws))]
    (cond
      ((keyLine? l "module") (if (= n 2) (none) (bad "a module line is: module path" no)))
      ((keyLine? l "exports") (if (>= n 2) (none) (bad "an exports line names at least one symbol: exports a b c" no)))
      ((keyLine? l "import") (if (or (= n 2) (and (= n 4) (= (optionOr (listGet ws 2) "") "as"))) (none) (bad "an import line is: import path as alias, or import path" no)))
      ((keyLine? l "doc") (bad "a doc line is retired prose (D158): move the text to the package doc.asn (asl doc)" no))
      (else (none))))

fn kindOf l: String -> Int64
  (cond
    ((keyLine? l "module") (kModule))
    ((keyLine? l "doc") (kDoc))
    ((keyLine? l "exports") (kExports))
    ((keyLine? l "import") (kImport))
    ((blank? l) (kBlank))
    ((comment? l) (kComment))
    (else -1))

fn docMore st: HScan open: Bool -> HScan
  (if (not open) st
    (match (listHead st.rest)
      ((none) (with st :err (bad "the doc string is not closed" st.no)))
      ((some l) (let [(b (stringToBytes l)) (e (quoteEnd b (bytesLength b) 0))
                      (next (HScan :lines (cons (HLine :kind (kDocMore) :text l :no st.no) st.lines) :rest (optionOr (listTail st.rest) (list)) :no (+ st.no 1) :err st.err))]
                  (if (>= e 0) next (docMore next true))))))

fn scanLines st: HScan first: Bool -> HScan
  (if (hasErr st.err) st
    (match (listHead st.rest)
      ((none) st)
      ((some l) (let [(k (if first (if (keyLine? l "module") (kModule) -1) (kindOf l)))]
                  (cond
                    ((or (< k 0) (and (not first) (= k (kModule)))) st)
                    (else (match (checkLine l st.no)
                            ((some e) (with st :err (some e)))
                            ((none) (let [(next (HScan :lines (cons (HLine :kind k :text l :no st.no) st.lines) :rest (optionOr (listTail st.rest) (list)) :no (+ st.no 1) :err st.err))
                                          (q (firstQuote l))]
                                      (scanLines (if (= k (kDoc)) (docMore next (openAfter l (+ q 1))) next) false))))))))))

fn hasErr o: (Option HeaderError) -> Bool
  (match o ((some _) true) ((none) false))

fn leading lines: (List String) no: Int64 acc: (List String) -> (Pair (List String) (Pair (List String) Int64))
  (match (listHead lines)
    ((none) (pair (listReverse acc) (pair (list) no)))
    ((some l) (if (or (blank? l) (comment? l)) (leading (optionOr (listTail lines) (list)) (+ no 1) (cons l acc)) (pair (listReverse acc) (pair lines no)))))

fn scanSource src: String -> (Pair (List String) HScan)
  (let [(lead (leading (stringSplit src "\n") 1 (list)))
        (st (scanLines (HScan :lines (list) :rest (pairFirst (pairSecond lead)) :no (pairSecond (pairSecond lead)) :err (none)) true))]
    (pair (pairFirst lead) (with st :lines (listReverse st.lines))))

fn contentKinds hs: (List HLine) -> (List HLine)
  (filter (fn [h] (and (!= h.kind (kBlank)) (and (!= h.kind (kComment)) (!= h.kind (kDocMore))))) hs)

fn runs hs: (List HLine) k: Int64 -> Int64
  (pairSecond (fold (fn [acc h] (let [(inRun (= h.kind k))] (pair inRun (if (and inRun (not (pairFirst acc))) (+ (pairSecond acc) 1) (pairSecond acc))))) (pair false 0) hs))

fn shapeError hs: (List HLine) -> (Option HeaderError)
  (let [(cs (contentKinds hs))
        (lastNo (match (listLast cs) ((some h) h.no) ((none) 1)))]
    (cond
      ((> (listLength (filter (fn [h] (= h.kind (kDoc))) cs)) 1) (bad "a module has at most one doc line" lastNo))
      ((> (runs cs (kExports)) 1) (bad "exports lines must be adjacent" lastNo))
      ((> (runs cs (kImport)) 1) (bad "import lines must be adjacent" lastNo))
      (else (none))))

fn oldTypeDeclLine src: String -> Int64
  (pairSecond (fold (fn [acc l] (let [(no (+ (pairFirst acc) 1))] (pair no (if (and (= (pairSecond acc) 0) (or (stringStartsWith? l "(schema ") (stringStartsWith? l "(enum "))) no (pairSecond acc))))) (pair 0 0) (stringSplit src "\n")))

fn strictError src: String -> (Option HeaderError)
  (cond
    ((oldHeader? src) (bad "the (module p :x [..] :i [..]) header is retired: write column-0 lines module p, exports a b, import q as c (tools/codemod/headers.asl --apply)" (match (firstContent (stringSplit src "\n") 1) ((some p) (pairSecond p)) ((none) 1))))
    ((> (oldTypeDeclLine src) 0) (bad "a (schema ..) or (enum ..) form is retired: write schema T then one name: Type field per indented line (tools/codemod/headers.asl --apply)" (oldTypeDeclLine src)))
    (else (none)))

fn headerError src: String strict: Bool -> (Option HeaderError)
  (if (lineHeader? src)
    (let [(sc (pairSecond (scanSource src)))]
      (match sc.err
        ((some e) (some e))
        ((none) (match (shapeError sc.lines) ((some e) (some e)) ((none) (if strict (strictError src) (none)))))))
    (if strict (strictError src) (none)))

fn importText l: String -> String
  (let [(ws (words l))] (if (= (listLength ws) 2) (str "(" (optionOr (listGet ws 1) "") ")") (str "(" (optionOr (listGet ws 1) "") " :a " (optionOr (listGet ws 3) "") ")")))

fn namesText l: String -> String
  (stringJoin (optionOr (listTail (words l)) (list)) " ")

fn lineText h: HLine prev: Int64 next: Int64 last: Bool -> String
  (let [(k h.kind)
        (body (cond
                ((= k (kModule)) (str "(module " (optionOr (listGet (words h.text) 1) "")))
                ((= k (kDoc)) (str " :doc " (stringTrim (sliceFrom h.text 3))))
                ((= k (kExports)) (str (if (= prev (kExports)) " " " :x [") (namesText h.text) (if (= next (kExports)) "" "]")))
                ((= k (kImport)) (str (if (= prev (kImport)) " " " :i [") (importText h.text) (if (= next (kImport)) "" "]")))
                (else h.text)))]
    (if last (str body ")") body))

fn lastContentNo hs: (List HLine) -> Int64
  (fold (fn [acc h] (if (or (= h.kind (kBlank)) (= h.kind (kComment))) acc h.no)) 0 hs)

fn kindAfter hs: (List HLine) -> Int64
  (match (listHead (contentKinds hs)) ((some h) h.kind) ((none) -1))

fn render hs: (List HLine) prev: Int64 endNo: Int64 acc: (List String) -> (List String)
  (match (listHead hs)
    ((none) (listReverse acc))
    ((some h) (let [(tail (optionOr (listTail hs) (list)))
                    (content (and (!= h.kind (kBlank)) (and (!= h.kind (kComment)) (!= h.kind (kDocMore)))))
                    (text (if content (lineText h prev (kindAfter tail) (= h.no endNo))
                            (if (and (= h.kind (kDocMore)) (= h.no endNo)) (str h.text ")") h.text)))]
                (render tail (if content h.kind prev) endNo (cons text acc)))))

fn normalizeHeader src: String -> String
  (if (not (lineHeader? src)) src
    (let [(scanned (scanSource src)) (sc (pairSecond scanned))]
      (if (or (hasErr sc.err) (hasErr (shapeError sc.lines))) src
        (stringJoin (listAppend (pairFirst scanned) (listAppend (render sc.lines -1 (lastContentNo sc.lines) (list)) sc.rest)) "\n"))))
