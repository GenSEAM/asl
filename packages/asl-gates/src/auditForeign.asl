(module asl-gates/auditForeign
  :x [Check ForeignRun InlineReport esc countLines normalizeNewlines embeddedPyLines inlineForeignCounts inlineAll! langFromHead foreignLangOf! measureForeign! parseAllowlist parseBaseline foreignAudit! lowerBaseline! runForeign! main]
  :i [(asl-proc/coreProcess :a p)])

(schema Check
  (:f id String)
  (:f status String)
  (:f err String)
  (:f ev String)
  (:f n (Option Int64)))

(schema Entry
  (:f kind String)
  (:f until String)
  (:f reason String))

(schema Row
  (:f lang String)
  (:f lines Int64)
  (:f py Int64))

(schema Raise
  (:f path String)
  (:f lang String)
  (:f lines Int64)
  (:f py Int64)
  (:f reason String)
  (:f date String)
  (:f form String))

(schema Allow
  (:f order (List String))
  (:f entries (Map String Entry))
  (:f bad (List String)))

(schema Baseline
  (:f order (List String))
  (:f rows (Map String Row))
  (:f raises (List Raise))
  (:f bad (List String)))

(schema Audit
  (:f checks (List Check))
  (:f head String)
  (:f tail String))

(schema ForeignRun
  (:f receipt String)
  (:f summary String)
  (:f exitCode Int64))

(schema Tracked
  (:f order (List String))
  (:f langs (Map String String))
  (:f unlisted (List String)))

(schema Scan
  (:f found (List (Pair String String)))
  (:f unlisted (List String))
  (:f allowRest (List String))
  (:f prev String)
  (:f dir String)
  (:f dirReal String))

(schema InlineReport
  (:f counts (Map String Int64))
  (:f files (List String))
  (:f total Int64))

(schema Lowered
  (:f rows (List String))
  (:f lowered Int64))

fn allowlistRel -> String
  "scripts/audit/foreignAllowlist.asn"

fn baselineRel -> String
  "scripts/audit/foreignBaseline.asn"

fn kindNames -> String
  "javascript machO powershell python shell stage0Host testGenerator"

fn byteAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn cut s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn isSpaceByte b: Int64 -> Bool
  (or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32)))

fn isDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isAlnumByte b: Int64 -> Bool
  (or (isDigitByte b) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn isWordByte b: Int64 -> Bool
  (or (isAlnumByte b) (= b 95))

fn skipSpace bs: Bytes n: Int64 i: Int64 -> Int64
  (if (isSpaceByte (byteAt bs n i)) (skipSpace bs n (+ i 1)) i)

fn skipWord bs: Bytes n: Int64 i: Int64 -> Int64
  (if (isWordByte (byteAt bs n i)) (skipWord bs n (+ i 1)) i)

fn skipAlnum bs: Bytes n: Int64 i: Int64 -> Int64
  (if (isAlnumByte (byteAt bs n i)) (skipAlnum bs n (+ i 1)) i)

fn skipDigitsDots bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (byteAt bs n i))]
    (if (or (isDigitByte b) (= b 46)) (skipDigitsDots bs n (+ i 1)) i))

fn litLoop bs: Bytes lb: Bytes i: Int64 k: Int64 m: Int64 -> Bool
  (cond
    ((>= k m) true)
    ((= (bytesGet bs (+ i k)) (bytesGet lb k)) (litLoop bs lb i (+ k 1) m))
    (else false))

fn litAt bs: Bytes n: Int64 i: Int64 lit: String -> Bool
  (let [(m (stringLength lit))]
    (and (>= i 0) (<= (+ i m) n) (= (bytesGet bs i) (charCode lit)) (litLoop bs (stringToBytes lit) i 1 m)))

fn litP bs: Bytes n: Int64 i: Int64 lit: String -> Int64
  (if (litAt bs n i lit) (+ i (stringLength lit)) -1)

fn findLit bs: Bytes n: Int64 i: Int64 lit: String -> Int64
  (cond
    ((> (+ i (stringLength lit)) n) -1)
    ((litAt bs n i lit) i)
    (else (findLit bs n (+ i 1) lit)))

fn countLines s: String -> Int64
  (+ (- (listLength (stringSplit s "\n")) 1) (if (and (not (stringEmpty? s)) (not (stringEndsWith? s "\n"))) 1 0))

fn normalizeNewlines s: String -> String
  (if (stringContains? s "\r") (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n") s)

fn stripAll s: String -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs)) (a (skipSpace bs n 0))]
    (cut s a (rstripEnd bs n)))

fn rstripEnd bs: Bytes n: Int64 -> Int64
  (if (and (> n 0) (isSpaceByte (bytesGet bs (- n 1)))) (rstripEnd bs (- n 1)) n)

fn escByte b: Int64 -> String
  (cond
    ((= b 92) "\\\\")
    ((= b 34) "\\\"")
    ((= b 13) "")
    ((= b 10) "\\n")
    ((and (>= b 32) (<= b 126)) (cut (printable) (- b 32) (- b 31)))
    (else "?"))

fn printable -> String
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

fn escLoop bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))]
      (cond
        ((and (>= b 128) (< b 192)) (escLoop bs n (+ i 1) acc))
        ((>= b 192) (escLoop bs n (+ i 1) (cons "?" acc)))
        (else (escLoop bs n (+ i 1) (cons (escByte b) acc))))))

fn esc text: String limit: Int64 -> String
  (let [(bs (stringToBytes text)) (s (escLoop bs (bytesLength bs) 0 (list)))]
    (if (> (stringLength s) limit) (cut s 0 limit) s))

fn itos k: Int64 -> String
  (stringFromInt64 k)

fn splitLinesKeep text: String -> (List String)
  (let [(pieces (stringSplit text "\n"))
        (k (listLength pieces))
        (lastPiece (optionOr (listLast pieces) ""))
        (full (map (fn [(x String)] -> String (str x "\n")) (listTake pieces (- k 1))))]
    (if (stringEmpty? lastPiece) full (listAppend full (list lastPiece))))

fn chop line: String -> String
  (if (stringEndsWith? line "\n") (cut line 0 (- (stringLength line) 1)) line)

fn commentLine? bs: Bytes n: Int64 -> Bool
  (= (byteAt bs n (skipSpace bs n 0)) 35)

fn heredocDelim bs: Bytes n: Int64 t: String i: Int64 -> (Option String)
  (cond
    ((> (+ i 2) n) (none))
    ((litAt bs n i "<<")
     (let [(a (+ i 2))
           (b (if (= (byteAt bs n a) 45) (+ a 1) a))
           (c (skipSpace bs n b))
           (q (byteAt bs n c))
           (d (if (or (= q 39) (= q 34)) (+ c 1) c))
           (e (skipWord bs n d))]
       (if (> e d) (some (cut t d e)) (heredocDelim bs n t (+ i 1)))))
    (else (heredocDelim bs n t (+ i 1))))

fn prefixByte? b: Int64 -> Bool
  (or (isSpaceByte b) (= b 59) (= b 38) (= b 124) (= b 96) (= b 36) (= b 40) (= b 41))

fn boundary? bs: Bytes n: Int64 e: Int64 -> Bool
  (!= (isWordByte (byteAt bs n (- e 1))) (isWordByte (byteAt bs n e)))

fn pyRunBoundary? bs: Bytes n: Int64 e: Int64 lo: Int64 -> Bool
  (cond
    ((< e lo) false)
    ((boundary? bs n e) true)
    (else (pyRunBoundary? bs n (- e 1) lo)))

fn pyWordAt? bs: Bytes n: Int64 q: Int64 -> Bool
  (cond
    ((litAt bs n q "python") (pyRunBoundary? bs n (skipDigitsDots bs n (+ q 6)) (+ q 6)))
    ((litAt bs n q "${PY}") (boundary? bs n (+ q 5)))
    ((litAt bs n q "$PY") (boundary? bs n (+ q 3)))
    (else false))

fn pathPyWord? bs: Bytes n: Int64 c: Int64 k: Int64 -> Bool
  (cond
    ((>= k n) false)
    ((isSpaceByte (bytesGet bs k)) false)
    ((and (= (bytesGet bs k) 47) (pyWordAt? bs n (+ k 1))) true)
    (else (pathPyWord? bs n c (+ k 1))))

fn directPyAt? bs: Bytes n: Int64 c: Int64 -> Bool
  (and (or (= c 0) (prefixByte? (byteAt bs n (- c 1))))
       (or (pyWordAt? bs n c)
           (and (= (byteAt bs n c) 47) (not (isSpaceByte (byteAt bs n (+ c 1)))) (pathPyWord? bs n c (+ c 2)))))

fn directPy? bs: Bytes n: Int64 c: Int64 -> Bool
  (cond
    ((> c n) false)
    ((directPyAt? bs n c) true)
    (else (directPy? bs n (+ c 1))))

fn heredocEnd? bs: Bytes n: Int64 e: Int64 -> Bool
  (or (= e n) (litAt bs n (skipSpace bs n e) "<<"))

fn readVarFrom bs: Bytes n: Int64 t: String i: Int64 -> String
  (cond
    ((>= i n) "")
    ((isWordByte (bytesGet bs i))
     (let [(e (skipWord bs n i))]
       (if (heredocEnd? bs n e) (cut t i e) (readVarFrom bs n t (+ i 1)))))
    (else (readVarFrom bs n t (+ i 1))))

fn readVar bs: Bytes n: Int64 t: String s: Int64 -> String
  (cond
    ((> (+ s 4) n) "")
    ((and (litAt bs n s "read") (not (isWordByte (byteAt bs n (+ s 4)))))
     (let [(v (readVarFrom bs n t (+ s 4)))]
       (if (stringEmpty? v) (readVar bs n t (+ s 1)) v)))
    (else (readVar bs n t (+ s 1))))

fn varRefAt? bs: Bytes n: Int64 b: Int64 ref: String -> Bool
  (and (litAt bs n b "-c")
       (isSpaceByte (byteAt bs n (+ b 2)))
       (let [(w (skipSpace bs n (+ b 2))) (q (byteAt bs n w))]
         (or (litAt bs n w ref) (and (or (= q 34) (= q 39)) (litAt bs n (+ w 1) ref)))))

fn varRefFrom? bs: Bytes n: Int64 b: Int64 ref: String -> Bool
  (cond
    ((> (+ b 2) n) false)
    ((varRefAt? bs n b ref) true)
    (else (varRefFrom? bs n (+ b 1) ref)))

fn pyCallEnd bs: Bytes n: Int64 s: Int64 -> Int64
  (cond
    ((litAt bs n s "python") (skipDigitsDots bs n (+ s 6)))
    ((litAt bs n s "$PY") (+ s 3))
    (else -1))

fn usesVarLine? bs: Bytes n: Int64 s: Int64 ref: String -> Bool
  (cond
    ((>= s n) false)
    ((let [(a (pyCallEnd bs n s))]
       (and (>= a 0) (isSpaceByte (byteAt bs n a)) (varRefFrom? bs n (+ a 1) ref)))
     true)
    (else (usesVarLine? bs n (+ s 1) ref)))

fn usedInPy? lines: (List String) ref: String -> Bool
  (listAny? (fn [(l String)] -> Bool (let [(bs (stringToBytes l))] (usesVarLine? bs (bytesLength bs) 0 ref))) lines)

fn pyHeredoc? bs: Bytes n: Int64 t: String delim: String all: (List String) -> Bool
  (or (directPy? bs n 0)
      (stringContains? (stringLower delim) "py")
      (let [(v (readVar bs n t 0)) (lv (stringLower v))]
        (and (not (stringEmpty? v))
             (or (stringContains? lv "py") (stringContains? lv "server_script") (usedInPy? all (str "$" v))))))

fn heredocBody lines: (List String) delim: String tabs: Bool count: Int64 -> (Pair Int64 (List String))
  (mt (listHead lines)
    ((none) (pair count (list)))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))
           (cur (rstripCrLf (if tabs (lstripTabs line) line)))]
       (if (= cur delim) (pair count rest) (heredocBody rest delim tabs (+ count 1))))))

fn lstripTabs s: String -> String
  (if (stringStartsWith? s "\t") (lstripTabs (cut s 1 (stringLength s))) s)

fn rstripCrLf s: String -> String
  (if (or (stringEndsWith? s "\n") (stringEndsWith? s "\r")) (rstripCrLf (cut s 0 (- (stringLength s) 1))) s)

fn optionEnd bs: Bytes n: Int64 p: Int64 -> Int64
  (if (and (= (byteAt bs n p) 45) (isAlnumByte (byteAt bs n (+ p 1))))
    (let [(q (skipAlnum bs n (+ p 1)))]
      (if (isSpaceByte (byteAt bs n q)) (skipSpace bs n q) -1))
    -1)

fn optionStarts bs: Bytes n: Int64 p: Int64 acc: (List Int64) -> (List Int64)
  (let [(q (optionEnd bs n p))]
    (if (< q 0) (cons p acc) (optionStarts bs n q (cons p acc))))

fn dashCFrom starts: (List Int64) bs: Bytes n: Int64 -> Int64
  (mt (listHead starts)
    ((none) -1)
    ((some p) (if (litAt bs n p "-c") (skipSpace bs n (+ p 2)) (dashCFrom (optionOr (listTail starts) (list)) bs n))))

fn firstSpace bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((isSpaceByte (bytesGet bs i)) i)
    (else (firstSpace bs n (+ i 1))))

fn lastSlash bs: Bytes i: Int64 lo: Int64 -> Int64
  (cond
    ((< i lo) -1)
    ((= (bytesGet bs i) 47) i)
    (else (lastSlash bs (- i 1) lo)))

fn pyCmdExact? bs: Bytes n: Int64 q: Int64 e: Int64 -> Bool
  (cond
    ((litAt bs n q "python") (= (skipDigitsDots bs n (+ q 6)) e))
    ((litAt bs n q "${PY}") (= (+ q 5) e))
    ((litAt bs n q "$PY") (= (+ q 3) e))
    (else false))

fn pyCAt bs: Bytes n: Int64 c: Int64 -> Int64
  (let [(e (firstSpace bs n c))]
    (if (< e 0)
      -1
      (let [(k (lastSlash bs (- e 1) c))
            (cmdOk (or (pyCmdExact? bs n c e) (and (= (byteAt bs n c) 47) (>= k (+ c 2)) (pyCmdExact? bs n (+ k 1) e))))]
        (if cmdOk (dashCFrom (optionStarts bs n (skipSpace bs n e) (list)) bs n) -1))))

fn pyCMatch bs: Bytes n: Int64 s: Int64 -> (Option (Pair Int64 Int64))
  (if (> s n)
    (none)
    (let [(viaCaret (if (= s 0) (pyCAt bs n 0) -1))
          (viaPrefix (if (and (< viaCaret 0) (prefixByte? (byteAt bs n s))) (pyCAt bs n (+ s 1)) -1))
          (r (if (>= viaCaret 0) viaCaret viaPrefix))]
      (if (>= r 0) (some (pair s r)) (pyCMatch bs n (+ s 1)))))

fn commentBefore? pre: String -> Bool
  (mt (stringIndexOf pre "#")
    ((none) false)
    ((some k) (or (= k 0) (listContains? (list " " "\t" ";" "&") (cut pre (- k 1) k)))))

fn varRefRest? rest: String -> Bool
  (let [(bs (stringToBytes rest)) (n (bytesLength bs)) (q (skipQuotes bs n 0))]
    (and (= (byteAt bs n q) 36) (isWordByte (byteAt bs n (+ q 1)))))

fn skipQuotes bs: Bytes n: Int64 i: Int64 -> Int64
  (if (= (byteAt bs n i) 34) (skipQuotes bs n (+ i 1)) i)

fn singleQuoted lines: (List String) acc: (List String) -> (Pair String (List String))
  (mt (listHead lines)
    ((none) (pair (stringJoin (listReverse acc) "") (list)))
    ((some l)
     (let [(rest (optionOr (listTail lines) (list)))]
       (mt (stringIndexOf l "'")
         ((some q) (pair (stringJoin (listReverse (cons (cut l 0 q) acc)) "") rest))
         ((none) (singleQuoted rest (cons l acc)))))))

fn dqClose bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet bs i) 92) (dqClose bs n (+ i 2)))
    ((= (bytesGet bs i) 34) i)
    (else (dqClose bs n (+ i 1))))

fn doubleQuoted cur: String lines: (List String) acc: (List String) -> (Pair String (List String))
  (let [(bs (stringToBytes cur)) (k (dqClose bs (bytesLength bs) 0))]
    (if (>= k 0)
      (pair (stringJoin (listReverse (cons (cut cur 0 k) acc)) "") lines)
      (mt (listHead lines)
        ((none) (pair (stringJoin (listReverse (cons cur acc)) "") (list)))
        ((some l) (doubleQuoted l (optionOr (listTail lines) (list)) (cons cur acc))))))

fn pyCStep t: String bs: Bytes n: Int64 rest: (List String) all: (List String) acc: Int64 -> Int64
  (mt (pyCMatch bs n 0)
    ((none) (embeddedLoop rest all acc))
    ((some m)
     (let [(code (cut t (pairSecond m) n))]
       (cond
         ((commentBefore? (cut t 0 (pairFirst m))) (embeddedLoop rest all acc))
         ((varRefRest? code) (embeddedLoop rest all acc))
         ((stringStartsWith? code "'")
          (let [(after (cut code 1 (stringLength code)))]
            (mt (stringIndexOf after "'")
              ((some q) (embeddedLoop rest all (+ acc (countLines (cut after 0 q)))))
              ((none)
               (let [(r (singleQuoted rest (list (str after "\n"))))]
                 (embeddedLoop (pairSecond r) all (+ acc (countLines (pairFirst r)))))))))
         ((stringStartsWith? code "\"")
          (let [(r (doubleQuoted (cut code 1 (stringLength code)) rest (list)))]
            (embeddedLoop (pairSecond r) all (+ acc (countLines (pairFirst r))))))
         (else (embeddedLoop rest all acc))))))

fn embeddedLoop lines: (List String) all: (List String) acc: Int64 -> Int64
  (mt (listHead lines)
    ((none) acc)
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))
           (t (chop line))
           (bs (stringToBytes t))
           (n (bytesLength bs))]
       (if (commentLine? bs n)
         (embeddedLoop rest all acc)
         (mt (heredocDelim bs n t 0)
           ((some delim)
            (if (pyHeredoc? bs n t delim all)
              (let [(r (heredocBody rest delim (stringContains? t "<<-") 0))]
                (embeddedLoop (pairSecond r) all (+ acc (pairFirst r))))
              (pyCStep t bs n rest all acc)))
           ((none) (pyCStep t bs n rest all acc)))))))

fn embeddedPyLines text: String -> Int64
  (let [(lines (splitLinesKeep text))]
    (embeddedLoop lines lines 0))

fn inlineStringEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (byteAt bs n i) 34) (+ i 1))
    ((= (byteAt bs n i) 92) (inlineStringEnd bs n (+ i 2)))
    (else (inlineStringEnd bs n (+ i 1))))

fn inlineLiteralSum text: String bs: Bytes n: Int64 i: Int64 -> (Pair Int64 Int64)
  (let [(e (inlineStringEnd bs n (+ i 1)))]
    (pair (countLines (cut text (+ i 1) (- e 1))) e))

fn inlineSpace bs: Bytes n: Int64 i: Int64 -> Int64
  (if (isSpaceByte (byteAt bs n i)) (inlineSpace bs n (+ i 1)) i)

fn inlineLineEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (byteAt bs n i) 10)) i (inlineLineEnd bs n (+ i 1)))

fn inlineSkipForm bs: Bytes n: Int64 i: Int64 depth: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (byteAt bs n i) 34) (inlineSkipForm bs n (inlineStringEnd bs n (+ i 1)) depth))
    ((= (byteAt bs n i) 59) (inlineSkipForm bs n (inlineLineEnd bs n i) depth))
    ((= (byteAt bs n i) 40) (inlineSkipForm bs n (+ i 1) (+ depth 1)))
    ((= (byteAt bs n i) 41) (if (= depth 1) (+ i 1) (inlineSkipForm bs n (+ i 1) (- depth 1))))
    (else (inlineSkipForm bs n (+ i 1) depth)))

fn inlineStrArgs text: String bs: Bytes n: Int64 i: Int64 total: Int64 -> (Pair Int64 Int64)
  (let [(j (inlineSpace bs n i))]
    (cond
      ((>= j n) (pair total n))
      ((= (byteAt bs n j) 41) (pair total (+ j 1)))
      ((= (byteAt bs n j) 59) (inlineStrArgs text bs n (inlineLineEnd bs n j) total))
      ((= (byteAt bs n j) 40) (inlineStrArgs text bs n (inlineSkipForm bs n j 0) total))
      ((= (byteAt bs n j) 34)
       (let [(v (inlineLiteralSum text bs n j))]
         (inlineStrArgs text bs n (pairSecond v) (+ total (pairFirst v)))))
      (else (inlineStrArgs text bs n (+ j 1) total))))

fn inlineExpr text: String bs: Bytes n: Int64 i: Int64 -> (Pair Int64 Int64)
  (let [(j (inlineSpace bs n i))]
    (cond
      ((and (< j n) (= (byteAt bs n j) 34)) (inlineLiteralSum text bs n j))
      ((and (< j n) (= (byteAt bs n j) 40) (litAt bs n (+ j 1) "str")
            (not (isWordByte (byteAt bs n (+ j 4)))))
       (inlineStrArgs text bs n (+ j 5) 0))
      (else (pair 0 j))))

fn inlineLang bs: Bytes n: Int64 i: Int64 -> String
  (cond
    ((litAt bs n i "js") "javascript")
    ((litAt bs n i "py") "python")
    ((litAt bs n i "sh") "shell")
    ((litAt bs n i "sql") "sql")
    ((litAt bs n i "html") "html")
    ((litAt bs n i "css") "css")
    ((litAt bs n i "llvm") "llvm")
    ((litAt bs n i "c") "c")
    (else ""))

fn inlineLangWidth lang: String -> Int64
  (if (listContains? (list "javascript" "python" "shell") lang) 2 (stringLength lang))

fn inlineCall text: String bs: Bytes n: Int64 i: Int64 alias: String -> (Option (Pair String (Pair Int64 Int64)))
  (let [(an (bytesLength (stringToBytes alias))) (a (+ i 1))]
    (if (and (litAt bs n a alias) (= (byteAt bs n (+ a an)) 47))
      (let [(langAt (+ a an 1)) (lang (inlineLang bs n (+ a an 1)))]
        (if (and (not (stringEmpty? lang))
                 (not (isWordByte (byteAt bs n (+ langAt (inlineLangWidth lang))))) )
          (let [(headEnd (+ langAt (inlineLangWidth lang)))
                (expr (inlineExpr text bs n headEnd))]
            (some (pair lang expr)))
          (none)))
      (none)))

fn inlineLoop text: String bs: Bytes n: Int64 i: Int64 alias: String acc: (Map String Int64) -> (Map String Int64)
  (cond
    ((>= i n) acc)
    ((= (byteAt bs n i) 34) (inlineLoop text bs n (inlineStringEnd bs n (+ i 1)) alias acc))
    ((= (byteAt bs n i) 59) (inlineLoop text bs n (inlineLineEnd bs n i) alias acc))
    ((= (byteAt bs n i) 40)
     (mt (inlineCall text bs n i alias)
       ((none) (inlineLoop text bs n (+ i 1) alias acc))
       ((some call)
        (let [(lang (pairFirst call)) (expr (pairSecond call)) (k (pairSecond expr)) (v (pairFirst expr))]
          (inlineLoop text bs n (max (+ i 1) k) alias (addLang acc lang v))))))
    (else (inlineLoop text bs n (+ i 1) alias acc)))

fn inlineAliasAfterHead text: String bs: Bytes n: Int64 headEnd: Int64 -> String
  (let [(a (inlineSpace bs n headEnd))]
    (if (and (litAt bs n a ":a") (not (isWordByte (byteAt bs n (+ a 2)))))
      (let [(j (inlineSpace bs n (+ a 2))) (k (tokEnd bs n (inlineSpace bs n (+ a 2))))]
        (if (> k j) (cut text j k) ""))
      ""))


fn inlineLocalBlock? rel: String -> Bool
  (stringContains? rel "asl/packages/asl-foreign/")

fn inlineImportAlias text: String bs: Bytes n: Int64 i: Int64 local: Bool -> String
  (cond
    ((>= i n) "")
    ((= (byteAt bs n i) 34) (inlineImportAlias text bs n (inlineStringEnd bs n (+ i 1)) local))
    ((= (byteAt bs n i) 59) (inlineImportAlias text bs n (inlineLineEnd bs n i) local))
    ((= (byteAt bs n i) 93) "")
    ((and (= (byteAt bs n i) 40) (litAt bs n i "(asl-foreign/block")
          (not (isWordByte (byteAt bs n (+ i (stringLength "(asl-foreign/block"))))))
     (inlineAliasAfterHead text bs n (+ i (stringLength "(asl-foreign/block"))))
    ((and local (= (byteAt bs n i) 40) (litAt bs n i "(block")
          (not (isWordByte (byteAt bs n (+ i (stringLength "(block"))))))
     (inlineAliasAfterHead text bs n (+ i (stringLength "(block"))))
    (else (inlineImportAlias text bs n (+ i 1) local)))

fn inlineHeaderScan text: String bs: Bytes n: Int64 i: Int64 local: Bool -> String
  (cond
    ((>= i n) "")
    ((and (= (byteAt bs n i) 10) (= (byteAt bs n (+ i 1)) 10)) "")
    ((= (byteAt bs n i) 34) (inlineHeaderScan text bs n (inlineStringEnd bs n (+ i 1)) local))
    ((= (byteAt bs n i) 59) (inlineHeaderScan text bs n (inlineLineEnd bs n i) local))
    ((and (litAt bs n i ":i") (not (isWordByte (byteAt bs n (+ i 2)))))
     (let [(j (inlineSpace bs n (+ i 2)))]
       (if (= (byteAt bs n j) 91)
         (inlineImportAlias text bs n (+ j 1) local)
         (inlineHeaderScan text bs n (+ i 2) local))))
    (else (inlineHeaderScan text bs n (+ i 1) local)))

fn inlineAlias text: String local: Bool -> String
  (let [(bs (stringToBytes text))]
    (inlineHeaderScan text bs (bytesLength bs) 0 local))

fn inlineForeignCounts text: String rel: String -> (Map String Int64)
  (let [(alias (inlineAlias text (inlineLocalBlock? rel)))]
    (if (stringEmpty? alias) (mapEmpty)
      (let [(bs (stringToBytes text))]
        (inlineLoop text bs (bytesLength bs) 0 alias (mapEmpty)))))

fn inlineTotal counts: (Map String Int64) -> Int64
  (sumBy (map (fn [(k String)] -> Int64 (optionOr (mapGet counts k) 0)) (mapKeys counts)))

fn inlineAddCounts acc: (Map String Int64) counts: (Map String Int64) -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (k String)] -> (Map String Int64)
          (addLang m k (optionOr (mapGet counts k) 0))) acc (mapKeys counts))

fn inlineAll! root: String paths: (List String) acc: InlineReport -> (Result InlineReport String)
  (mt (listHead paths)
    ((none) (ok acc))
    ((some rel)
     (if (not (stringEndsWith? rel ".asl"))
       (inlineAll! root (optionOr (listTail paths) (list)) acc)
       (mt (readText! (str root "/" rel))
         ((err e) (err e))
         ((ok maybe)
          (mt maybe
            ((none) (inlineAll! root (optionOr (listTail paths) (list)) acc))
            ((some text)
             (let [(counts (inlineForeignCounts text rel)) (n (inlineTotal counts))
                   (files (if (> n 0) (cons (str rel " " (itos n)) acc.files) acc.files))
                   (next (InlineReport :counts (inlineAddCounts acc.counts counts) :files files :total (+ acc.total n)))]
               (inlineAll! root (optionOr (listTail paths) (list)) next)))))))))

fn baseName path: String -> String
  (let [(parts (stringSplit path "/"))]
    (optionOr (listLast parts) path))

fn dirName path: String -> String
  (let [(bs (stringToBytes path)) (k (lastSlash bs (- (bytesLength bs) 1) 0))]
    (if (< k 0) "." (if (= k 0) "/" (cut path 0 k))))

fn extTable -> (List (Pair String String))
  (list (pair ".c" "c") (pair ".h" "c") (pair ".py" "python") (pair ".pyw" "python") (pair ".sh" "shell") (pair ".bash" "shell") (pair ".zsh" "shell")
        (pair ".js" "javascript") (pair ".mjs" "javascript") (pair ".cjs" "javascript") (pair ".jsx" "javascript") (pair ".ts" "typescript")
        (pair ".tsx" "typescript") (pair ".rs" "rust") (pair ".go" "go") (pair ".swift" "swift") (pair ".rb" "ruby") (pair ".java" "java") (pair ".kt" "kotlin")
        (pair ".cpp" "cpp") (pair ".cc" "cpp") (pair ".hpp" "cpp") (pair ".m" "objc") (pair ".mm" "objc") (pair ".zig" "zig") (pair ".lua" "lua") (pair ".pl" "perl")
        (pair ".php" "php") (pair ".ps1" "powershell"))

fn lookup table: (List (Pair String String)) key: String -> String
  (mt (listHead (filter (fn [(kv (Pair String String))] -> Bool (= (pairFirst kv) key)) table))
    ((some kv) (pairSecond kv))
    ((none) ""))

fn hasNonDot bs: Bytes i: Int64 k: Int64 -> Bool
  (cond
    ((>= i k) false)
    ((!= (bytesGet bs i) 46) true)
    (else (hasNonDot bs (+ i 1) k)))

fn extLang name: String -> String
  (let [(bs (stringToBytes name)) (n (bytesLength bs)) (k (lastDot bs (- n 1)))]
    (if (and (> k 0) (hasNonDot bs 0 k)) (lookup (extTable) (stringLower (cut name k n))) ""))

fn lastDot bs: Bytes i: Int64 -> Int64
  (cond
    ((< i 0) -1)
    ((= (bytesGet bs i) 46) i)
    (else (lastDot bs (- i 1))))

fn shebangChar b: Int64 -> String
  (if (and (>= b 32) (<= b 126)) (cut (printable) (- b 32) (- b 31)) "~")

fn shebangWords bs: Bytes n: Int64 i: Int64 cur: (List String) acc: (List String) -> (List String)
  (let [(flush (if (listEmpty? cur) acc (cons (stringJoin (listReverse cur) "") acc)))]
    (cond
      ((or (>= i n) (= (bytesGet bs i) 10)) (listReverse flush))
      ((isSpaceByte (bytesGet bs i)) (shebangWords bs n (+ i 1) (list) flush))
      (else (shebangWords bs n (+ i 1) (cons (shebangChar (bytesGet bs i)) cur) acc))))

fn versionSuffix? r: String -> Bool
  (let [(bs (stringToBytes r)) (n (bytesLength bs))
        (a (if (listContains? (list 45 95 46) (byteAt bs n 0)) 1 0))
        (b (if (or (= (byteAt bs n a) 118) (= (byteAt bs n a) 86)) (+ a 1) a))]
    (or (= n 0) (and (isDigitByte (byteAt bs n b)) (versionTail? bs n (+ b 1)))))

fn versionTail? bs: Bytes n: Int64 i: Int64 -> Bool
  (cond
    ((>= i n) true)
    ((or (isDigitByte (bytesGet bs i)) (listContains? (list 45 95 46) (bytesGet bs i))) (versionTail? bs n (+ i 1)))
    (else false))

fn shebangNames -> (List (Pair String String))
  (list (pair "python" "python") (pair "bash" "shell") (pair "sh" "shell") (pair "zsh" "shell") (pair "dash" "shell") (pair "ksh" "shell")
        (pair "node" "javascript") (pair "perl" "perl") (pair "ruby" "ruby"))

fn alnumOnly s: String -> String
  (stringJoin (filter (fn [(c String)] -> Bool (and (= (stringLength c) 1) (isAlnumByte (charCode c)))) (stringChars s)) "")

fn shebangLang name: String -> String
  (let [(lower (stringLower name))
        (hit (filter (fn [(kv (Pair String String))] -> Bool
                       (and (stringStartsWith? lower (pairFirst kv))
                            (versionSuffix? (cut lower (stringLength (pairFirst kv)) (stringLength lower)))))
                     (shebangNames)))]
    (mt (listHead hit)
      ((some kv) (pairSecond kv))
      ((none) (let [(a (alnumOnly name))] (str "shebang." (if (stringEmpty? a) "empty" a))))))

fn magic4? hb: Bytes a: Int64 b: Int64 c: Int64 d: Int64 -> Bool
  (and (= (bytesGet hb 0) a) (= (bytesGet hb 1) b) (= (bytesGet hb 2) c) (= (bytesGet hb 3) d))

fn langFromHead hb: Bytes name: String -> String
  (let [(n (bytesLength hb))]
    (cond
      ((and (>= n 4) (or (magic4? hb 207 250 237 254) (magic4? hb 254 237 250 207))) "machO")
      ((and (>= n 4) (magic4? hb 202 254 186 190)) "machOUniversal")
      ((and (>= n 4) (magic4? hb 127 69 76 70)) "elf")
      ((and (>= n 4) (magic4? hb 0 97 115 109)) "wasm")
      ((and (>= n 2) (= (bytesGet hb 0) 35) (= (bytesGet hb 1) 33))
       (let [(words (shebangWords hb n 2 (list) (list)))
             (first (optionOr (listHead words) ""))
             (argv (if (= (baseName first) "env") (filter (fn [(w String)] -> Bool (not (stringStartsWith? w "-"))) (optionOr (listTail words) (list))) words))]
         (shebangLang (baseName (optionOr (listHead argv) "")))))
      (else (extLang name))))

fn binaryLang? lang: String -> Bool
  (listContains? (list "machO" "machOUniversal" "elf" "wasm") lang)

fn osError e: String path: String -> String
  (let [(errno (cond ((stringStartsWith? e "notFound") "2") ((stringStartsWith? e "permission") "13") ((stringStartsWith? e "isDirectory") "21") (else "")))
        (parts (stringSplit e ": "))
        (why (optionOr (listLast parts) e))]
    (if (stringEmpty? errno) e (str "[Errno " errno "] " why ": '" path "'")))

fn foreignLangOf! full: String rel: String -> (Result String String)
  (mt (fileReadRange full 0 256)
    ((err e) (err (osError e full)))
    ((ok hb) (ok (langFromHead hb (baseName rel)))))

fn measureForeign! full: String lang: String -> (Result (Pair Int64 Int64) String)
  (if (binaryLang? lang)
    (ok (pair 0 0))
    (mt (fileReadString full)
      ((err e) (err (osError e full)))
      ((ok raw)
       (let [(text (normalizeNewlines raw))
             (lines (countLines text))
             (py (if (= lang "shell") (embeddedPyLines text) 0))]
         (ok (pair lines (min py lines)))))))

fn notQuoteEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (< i 0)
    -1
    (let [(k (findLit bs n i "\""))]
      (if (> k i) k -1)))

fn tokEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (< i 0)
    -1
    (let [(k (tokRun bs n i))]
      (if (> k i) k -1)))

fn tokRun bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (byteAt bs n i))]
    (if (or (isAlnumByte b) (= b 46)) (tokRun bs n (+ i 1)) i))

fn digitsEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (< i 0)
    -1
    (let [(k (digitRun bs n i))]
      (if (> k i) k -1)))

fn digitRun bs: Bytes n: Int64 i: Int64 -> Int64
  (if (isDigitByte (byteAt bs n i)) (digitRun bs n (+ i 1)) i)

fn digitsExact bs: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (if (and (>= i 0) (>= (- (digitRun bs n i) i) k)) (+ i k) -1)

fn strEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((or (< i 0) (>= i n)) -1)
    ((= (bytesGet bs i) 34) i)
    ((= (bytesGet bs i) 92) (if (and (< (+ i 1) n) (!= (bytesGet bs (+ i 1)) 10)) (strEnd bs n (+ i 2)) -1))
    (else (strEnd bs n (+ i 1))))

fn unescLoop bs: Bytes n: Int64 i: Int64 s: String start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (stringJoin (listReverse (cons (cut s start n) acc)) ""))
    ((and (= (bytesGet bs i) 92) (< (+ i 1) n) (!= (bytesGet bs (+ i 1)) 10))
     (unescLoop bs n (+ i 2) s (+ i 1) (cons (cut s start i) acc)))
    (else (unescLoop bs n (+ i 1) s start acc)))

fn unesc s: String -> String
  (let [(bs (stringToBytes s))]
    (unescLoop bs (bytesLength bs) 0 s 0 (list)))

fn toInt s: String -> Int64
  (optionOr (stringToInt64 s) 0)

fn charIndex bs: Bytes i: Int64 k: Int64 acc: Int64 -> Int64
  (cond
    ((>= i k) acc)
    ((and (>= (bytesGet bs i) 128) (< (bytesGet bs i) 192)) (charIndex bs (+ i 1) k acc))
    (else (charIndex bs (+ i 1) k (+ acc 1))))

fn charsAhead bs: Bytes n: Int64 i: Int64 left: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((and (>= (bytesGet bs i) 128) (< (bytesGet bs i) 192)) (charsAhead bs n (+ i 1) left))
    ((= left 0) i)
    (else (charsAhead bs n (+ i 1) (- left 1))))

fn unparsed what: String text: String bs: Bytes n: Int64 at: Int64 -> String
  (let [(snippet (cut text at (charsAhead bs n at 120)))
        (line (optionOr (listHead (stringSplit snippet "\n")) ""))]
    (str "unparsed " what " form at byte " (itos (charIndex bs 0 at 0)) ": " line))

fn openers bs: Bytes n: Int64 i: Int64 lit: String acc: (List Int64) -> (List Int64)
  (let [(k (findLit bs n i lit))]
    (if (< k 0) (listReverse acc) (openers bs n (+ k (stringLength lit)) lit (cons k acc))))

fn entryAt text: String bs: Bytes n: Int64 at: Int64 -> (Option (Pair String Entry))
  (let [(a (litP bs n at "(:path \""))
        (b (notQuoteEnd bs n a))
        (c (litP bs n b "\" :kind :"))
        (d (tokEnd bs n c))
        (e (litP bs n d " :rationale \""))
        (f (strEnd bs n e))
        (g (litP bs n f "\" :until :"))
        (u1 (litP bs n g "R1"))
        (u (if (>= u1 0) u1 (litP bs n g "none")))
        (r1 (litP bs n u " :reason \""))
        (r2 (strEnd bs n r1))
        (r3 (litP bs n r2 "\")"))
        (plain (litP bs n u ")"))]
    (cond
      ((< u 0) (none))
      ((>= r3 0) (some (pair (cut text a b) (Entry :kind (cut text c d) :until (cut text g u) :reason (unesc (cut text r1 r2))))))
      ((>= plain 0) (some (pair (cut text a b) (Entry :kind (cut text c d) :until (cut text g u) :reason ""))))
      (else (none))))

fn addEntry text: String bs: Bytes n: Int64 acc: Allow at: Int64 -> Allow
  (mt (entryAt text bs n at)
    ((none) (with acc :bad (cons (unparsed "allowlist" text bs n at) acc.bad)))
    ((some pe)
     (let [(path (pairFirst pe)) (seen (mapHas? acc.entries path))]
       (Allow :order (if seen acc.order (cons path acc.order))
              :entries (mapSet acc.entries path (pairSecond pe))
              :bad (if seen (cons (str "duplicate allowlist entry " path) acc.bad) acc.bad)))))

fn parseAllowlist text: String -> Allow
  (let [(bs (stringToBytes text)) (n (bytesLength bs))
        (r (fold (fn [(acc Allow) (at Int64)] -> Allow (addEntry text bs n acc at))
                 (Allow :order (list) :entries (mapEmpty) :bad (list))
                 (openers bs n 0 "(:path " (list))))]
    (Allow :order (listReverse r.order) :entries r.entries
           :bad (listAppend (listReverse (filter (fn [(s String)] -> Bool (stringStartsWith? s "unparsed")) r.bad))
                            (listReverse (filter (fn [(s String)] -> Bool (not (stringStartsWith? s "unparsed"))) r.bad)))))

fn fileRowAt text: String bs: Bytes n: Int64 at: Int64 -> (Option (Pair String Row))
  (let [(a (litP bs n at "(:file :path \""))
        (b (notQuoteEnd bs n a))
        (c (litP bs n b "\" :lang :"))
        (d (tokEnd bs n c))
        (e (litP bs n d " :lines "))
        (f (digitsEnd bs n e))
        (g (litP bs n f " :py "))
        (h (digitsEnd bs n g))
        (z (litP bs n h ")"))]
    (if (< z 0)
      (none)
      (some (pair (cut text a b) (Row :lang (cut text c d) :lines (toInt (cut text e f)) :py (toInt (cut text g h)))))))

fn raiseAt text: String bs: Bytes n: Int64 at: Int64 -> (Option Raise)
  (let [(a (litP bs n at "(:raise :path \""))
        (b (notQuoteEnd bs n a))
        (c (litP bs n b "\" :lang :"))
        (d (tokEnd bs n c))
        (e (litP bs n d " :lines "))
        (f (digitsEnd bs n e))
        (g (litP bs n f " :py "))
        (h (digitsEnd bs n g))
        (i (litP bs n h " :reason \""))
        (j (strEnd bs n i))
        (k (litP bs n j "\" :date \""))
        (y (digitsExact bs n k 4))
        (m1 (digitsExact bs n (litP bs n y "-") 2))
        (d1 (digitsExact bs n (litP bs n m1 "-") 2))
        (z (litP bs n d1 "\")"))]
    (if (< z 0)
      (none)
      (some (Raise :path (cut text a b) :lang (cut text c d) :lines (toInt (cut text e f)) :py (toInt (cut text g h))
                   :reason (unesc (cut text i j)) :date (cut text k d1) :form (cut text at z)))))

fn addRow text: String bs: Bytes n: Int64 acc: Baseline at: Int64 -> Baseline
  (mt (fileRowAt text bs n at)
    ((none) (with acc :bad (cons (unparsed "baseline :file" text bs n at) acc.bad)))
    ((some pr)
     (let [(path (pairFirst pr)) (seen (mapHas? acc.rows path))]
       (with acc :order (if seen acc.order (cons path acc.order)) :rows (mapSet acc.rows path (pairSecond pr)) :bad (if seen (cons (str "duplicate baseline row " path) acc.bad) acc.bad)))))

fn addRaise text: String bs: Bytes n: Int64 acc: Baseline at: Int64 -> Baseline
  (mt (raiseAt text bs n at)
    ((none) (with acc :bad (cons (unparsed "baseline :raise (needs :path :lang :lines :py :reason :date)" text bs n at) acc.bad)))
    ((some r) (with acc :raises (cons r acc.raises))))

fn emptyReasonBad raises: (List Raise) -> (List String)
  (map (fn [(r Raise)] -> String (str "raise for " r.path " has an empty :reason"))
       (filter (fn [(r Raise)] -> Bool (stringEmpty? (stripAll r.reason))) raises))

fn parseBaseline text: String -> Baseline
  (let [(bs (stringToBytes text)) (n (bytesLength bs))
        (b0 (Baseline :order (list) :rows (mapEmpty) :raises (list) :bad (list)))
        (fileUnparsed (fold (fn [(acc Baseline) (at Int64)] -> Baseline (addRow text bs n acc at)) b0 (openers bs n 0 "(:file " (list))))
        (withRaises (fold (fn [(acc Baseline) (at Int64)] -> Baseline (addRaise text bs n acc at))
                          (Baseline :order fileUnparsed.order :rows fileUnparsed.rows :raises (list) :bad (list))
                          (openers bs n 0 "(:raise " (list))))
        (fileBad (listReverse (filter (fn [(s String)] -> Bool (stringStartsWith? s "unparsed")) fileUnparsed.bad)))
        (dupBad (listReverse (filter (fn [(s String)] -> Bool (not (stringStartsWith? s "unparsed"))) fileUnparsed.bad)))
        (raises (listReverse withRaises.raises))]
    (Baseline :order (listReverse withRaises.order) :rows withRaises.rows :raises raises
              :bad (listAppend fileBad (listAppend (listReverse withRaises.bad) (listAppend dupBad (emptyReasonBad raises))))))

fn passCheck id: String n: Int64 -> Check
  (Check :id id :status ":passed" :err "" :ev "" :n (some n))

fn failCheck id: String err: String ev: String -> Check
  (Check :id id :status ":failed" :err err :ev ev :n (none))

fn withN c: Check n: Int64 -> Check
  (with c :n (some n))

fn perItem id: String bad: (List String) err: String n: Int64 -> (List Check)
  (if (listEmpty? bad)
    (list (passCheck id n))
    (let [(k (listLength bad))
          (shown (map (fn [(b String)] -> Check (failCheck id err b)) (listTake bad 50)))
          (out (if (> k 50) (listAppend shown (list (failCheck id err (str (itos (- k 50)) " more not listed")))) shown))]
      (cons (withN (optionOr (listHead out) (failCheck id err "")) n) (optionOr (listTail out) (list)))))

fn fmtCheck c: Check -> String
  (str "(:check :id " c.id " :status " c.status
       (mt c.n ((some k) (str " :n " (itos k))) ((none) ""))
       (if (stringEmpty? c.err) "" (str " :err " c.err))
       (if (stringEmpty? c.ev) "" (str " :ev \"" (esc c.ev 400) "\""))
       ")")

fn failedOf checks: (List Check) -> (List Check)
  (filter (fn [(c Check)] -> Bool (!= c.status ":passed")) checks)

fn emit sub: String checks: (List Check) head: String tail: String -> ForeignRun
  (let [(failed (failedOf checks))
        (status (if (or (not (listEmpty? failed)) (listEmpty? checks)) ":failed" ":passed"))
        (parts (listAppend (listAppend (cons (str "(:audit :sub " sub " :status " status) (if (stringEmpty? head) (list) (list head)))
                                       (map fmtCheck checks))
                           (if (stringEmpty? tail) (list) (list tail))))
        (summary (str "audit " sub ": " (cut status 1 (stringLength status)) ", " (itos (listLength checks)) " checks, " (itos (listLength failed)) " not passed"
                      (stringJoin (map (fn [(c Check)] -> String (str "; " c.id " " c.err)) (listTake failed 5)) "")))]
    (ForeignRun :receipt (str (stringJoin parts " ") ")") :summary summary :exitCode (if (= status ":passed") 0 1)))

fn internal e: String -> ForeignRun
  (emit "foreign" (list (failCheck "internal" "ERR_AUDIT_INTERNAL" e)) "" "")

fn gitCmd root: String args: (List String) -> p/ProcessCmd
  (p/withTimeout (p/withCwd (p/cmd "git" args) root) 600000)

fn gitRun! root: String args: (List String) -> (Result p/ProcessOutput String)
  (mt (p/exec! (gitCmd root args))
    ((ok o) (ok o))
    ((err pe) (err (procErrText args pe))))

fn procErrText args: (List String) pe: p/ProcessError -> String
  (mt pe
    ((p/notFound b) (str "ERR_TOOL_ABSENT: " b " is not on PATH"))
    ((p/permissionDenied b) (str "ERR_TOOL_ABSENT: " b " is not executable"))
    ((p/timeout ms) (str "git " (stringJoin args " ") ": timeout after " (itos ms) "ms"))
    ((p/executionFailed code msg) (str "git " (stringJoin args " ") ": " msg)))

fn git! root: String args: (List String) -> (Result String String)
  (mt (gitRun! root args)
    ((err e) (err e))
    ((ok o) (if (= o.exitCode 0) (ok (normalizeNewlines o.stdout)) (err (str "git " (stringJoin args " ") ": " (stringTrim o.stderr))))))

fn gitLoose! root: String args: (List String) -> (Result String String)
  (mt (gitRun! root args)
    ((err e) (err e))
    ((ok o) (ok (if (= o.exitCode 0) (normalizeNewlines o.stdout) ""))))

fn gitOk! root: String args: (List String) -> (Result Bool String)
  (mt (gitRun! root args)
    ((err e) (err e))
    ((ok o) (ok (= o.exitCode 0))))

fn foreignBase! root: String baseEnv: String -> (Result String String)
  (let [(given (stringTrim baseEnv))]
    (mt (if (stringEmpty? given)
          (mt (gitOk! root (list "rev-parse" "--verify" "-q" "refs/heads/main"))
            ((err e) (err e))
            ((ok hasMain) (if hasMain (resultMap (gitLoose! root (list "merge-base" "HEAD" "main")) (fn [(s String)] -> String (stringTrim s))) (ok ""))))
          (ok given))
      ((err e) (err e))
      ((ok found)
       (let [(rev (if (stringEmpty? found) "HEAD" found))]
         (mt (gitLoose! root (list "rev-parse" "--verify" "-q" (str rev "^{commit}")))
           ((err e) (err e))
           ((ok out)
            (let [(sha (stringTrim out))]
              (if (stringEmpty? sha) (err (str "foreign ratchet base " rev " does not name a commit")) (ok sha)))))))))

fn atRevision! root: String sha: String rel: String -> (Result (Option String) String)
  (mt (gitRun! root (list "show" (str sha ":" rel)))
    ((err e) (err e))
    ((ok o) (ok (if (= o.exitCode 0) (some (normalizeNewlines o.stdout)) (none)))))

fn ! plainFile? full: String dirReal: String -> Bool
  (mt (realPath full)
    ((err _) false)
    ((ok rp)
     (and (not (stringEmpty? dirReal))
          (= rp (str (if (= dirReal "/") "" dirReal) "/" (baseName full)))
          (mt (fileStat full) ((ok st) st.isFile) ((err _) false)))))

fn dropBelow xs: (List String) p: String -> (List String)
  (mt (listHead xs)
    ((some x) (if (< x p) (dropBelow (optionOr (listTail xs) (list)) p) xs))
    ((none) xs))

fn allowed? sc: Scan sorted: (List String) rel: String -> (Pair Bool (List String))
  (if (< rel sc.prev)
    (pair (listContains? sorted rel) sc.allowRest)
    (let [(rest (dropBelow sc.allowRest rel))]
      (pair (= (optionOr (listHead rest) "") rel) rest)))

fn scanFile! root: String sorted: (List String) sc: Scan rel: String -> (Result Scan String)
  (let [(full (str root "/" rel))
        (dir (dirName full))
        (dirReal (if (= dir sc.dir) sc.dirReal (resultOr (realPath dir) "")))
        (member (allowed? sc sorted rel))
        (sc1 (with sc :allowRest (pairSecond member) :prev rel :dir dir :dirReal dirReal))]
    (if (not (plainFile? full dirReal))
      (ok sc1)
      (mt (foreignLangOf! full rel)
        ((err e) (err e))
        ((ok lang)
         (cond
           ((pairFirst member) (ok (Scan :found (cons (pair rel lang) sc1.found) :unlisted sc1.unlisted :allowRest sc1.allowRest :prev rel :dir dir :dirReal dirReal)))
           ((stringEmpty? lang) (ok sc1))
           (else (ok (Scan :found sc1.found :unlisted (cons (str "unlisted foreign " rel " (" lang ")") sc1.unlisted) :allowRest sc1.allowRest :prev rel :dir dir :dirReal dirReal))))))))

fn addFound t: Tracked f: (Pair String String) -> Tracked
  (let [(rel (pairFirst f)) (seen (mapHas? t.langs rel))]
    (with t :order (if seen t.order (cons rel t.order)) :langs (mapSet t.langs rel (pairSecond f))))

fn scanFiles! root: String sorted: (List String) files: (List String) sc: Scan -> (Result Tracked String)
  (mt (listHead files)
    ((none)
     (let [(t (fold addFound (Tracked :order (list) :langs (mapEmpty) :unlisted (list)) (listReverse sc.found)))]
       (ok (Tracked :order (listReverse t.order) :langs t.langs :unlisted (listReverse sc.unlisted)))))
    ((some rel)
     (mt (scanFile! root sorted sc rel)
       ((err e) (err e))
       ((ok sc1) (scanFiles! root sorted (optionOr (listTail files) (list)) sc1)))))

fn readText! full: String -> (Result (Option String) String)
  (mt (fileStat full)
    ((err _) (ok (none)))
    ((ok st)
     (if (not st.isFile)
       (ok (none))
       (mt (fileReadString full)
         ((err e) (err (osError e full)))
         ((ok s) (ok (some (normalizeNewlines s))))))))

fn langOr lang: String fallback: String -> String
  (if (stringEmpty? lang) fallback lang)

fn baselineRow path: String lang: String lines: Int64 py: Int64 -> String
  (str "(:file :path \"" path "\" :lang :" lang " :lines " (itos lines) " :py " (itos py) ")")

fn langsOf t: Tracked p: String -> String
  (optionOr (mapGet t.langs p) "")

fn kindFinding allow: Allow t: Tracked p: String -> (List String)
  (let [(kind (optionMap (fn [(e Entry)] -> String e.kind) (mapGet allow.entries p)))
        (k (optionOr kind ""))
        (lang (langsOf t p))
        (want (lookupKind k))]
    (cond
      ((none? want) (list (str p " :kind :" k " is not one of " (kindNames))))
      ((listContains? (optionOr want (list)) lang) (list))
      (else (list (str p " :kind :" k " but the file is " (langOr lang "not foreign (no magic, #! or foreign extension)"))))))

fn lookupKind k: String -> (Option (List String))
  (cond
    ((= k "shell") (some (list "shell")))
    ((= k "python") (some (list "python")))
    ((= k "javascript") (some (list "javascript")))
    ((= k "powershell") (some (list "powershell")))
    ((= k "machO") (some (list "machO" "machOUniversal")))
    ((= k "stage0Host") (some (list "c" "shell")))
    ((= k "testGenerator") (some (list "python" "shell")))
    (else (none)))

fn measureAll! root: String t: Tracked paths: (List String) acc: (Map String (Pair Int64 Int64)) -> (Result (Map String (Pair Int64 Int64)) String)
  (mt (listHead paths)
    ((none) (ok acc))
    ((some rel)
     (mt (measureForeign! (str root "/" rel) (langsOf t rel))
       ((err e) (err e))
       ((ok m) (measureAll! root t (optionOr (listTail paths) (list)) (mapSet acc rel m))))))

fn measuredOf ms: (Map String (Pair Int64 Int64)) p: String -> (Pair Int64 Int64)
  (optionOr (mapGet ms p) (pair 0 0))

fn growthOf t: Tracked b: Baseline ms: (Map String (Pair Int64 Int64)) p: String -> (List String)
  (mt (mapGet b.rows p)
    ((none) (list))
    ((some row)
     (let [(m (measuredOf ms p)) (lines (pairFirst m)) (py (pairSecond m)) (lang (langsOf t p))]
       (listAppend
         (if (!= (langOr lang "none") row.lang) (list (str p " is " (langOr lang "not foreign") ", the baseline pins :" row.lang)) (list))
         (listAppend
           (if (> lines row.lines) (list (str p " :lines " (itos lines) " > baseline " (itos row.lines) " (+" (itos (- lines row.lines)) ")")) (list))
           (if (> py row.py) (list (str p " embedded python :py " (itos py) " > baseline " (itos row.py) " (+" (itos (- py row.py)) ")")) (list)))))))

fn covered? raises: (List Raise) p: String row: Row -> Bool
  (listAny? (fn [(r Raise)] -> Bool (and (= r.path p) (= r.lang row.lang) (>= r.lines row.lines) (>= r.py row.py))) raises)

fn raisedFinding b: Baseline baseRows: (Map String Row) base: String p: String -> (List String)
  (let [(row (optionOr (mapGet b.rows p) (Row :lang "" :lines 0 :py 0)))
        (old (mapGet baseRows p))
        (kept (mt old ((some o) (and (= row.lang o.lang) (<= row.lines o.lines) (<= row.py o.py))) ((none) false)))]
    (if (or kept (covered? b.raises p row))
      (list)
      (let [(was (mt old ((some o) (str ":" o.lang " :lines " (itos o.lines) " :py " (itos o.py))) ((none) "absent")))]
        (list (str p " raised to :" row.lang " :lines " (itos row.lines) " :py " (itos row.py) " from " was " at " (cut base 0 12) " without a covering (:raise ... :reason :date)")))))

fn sumBy xs: (List Int64) -> Int64
  (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 xs)

fn addLang acc: (Map String Int64) k: String v: Int64 -> (Map String Int64)
  (mapSet acc k (+ (optionOr (mapGet acc k) 0) v))

fn langCountsText totals: (Map String Int64) -> String
  (stringJoin (map (fn [(k String)] -> String (str ":" k " " (itos (optionOr (mapGet totals k) 0)))) (listSort (mapKeys totals))) " ")

fn byLangText t: Tracked ms: (Map String (Pair Int64 Int64)) -> String
  (let [(totals (fold (fn [(acc (Map String Int64)) (p String)] -> (Map String Int64)
                        (let [(m (measuredOf ms p)) (py (pairSecond m)) (a1 (addLang acc (langOr (langsOf t p) "none") (- (pairFirst m) py)))]
                          (if (> py 0) (addLang a1 "python" py) a1)))
                      (mapEmpty) t.order))]
    (langCountsText totals))

fn raiseForm r: Raise -> String
  (str "(:raise :path \"" r.path "\" :lang :" r.lang " :lines " (itos r.lines) " :py " (itos r.py) " :reason \"" (esc r.reason 200) "\" :date \"" r.date "\")")

fn sortedKeys ks: (List String) -> (List String)
  (listSort ks)

fn foreignAudit! root: String showAll: Bool baseEnv: String -> (Result Audit String)
  (mt (readText! (str root "/" (allowlistRel)))
    ((err e) (err e))
    ((ok maybe)
     (mt maybe
       ((none) (ok (Audit :checks (list (failCheck "gate4Foreign" "ERR_FOREIGN" "scripts/audit/foreignAllowlist.asn absent")) :head "" :tail "")))
       ((some text) (auditAllowlist! root showAll baseEnv text)))))

fn auditAllowlist! root: String showAll: Bool baseEnv: String text: String -> (Result Audit String)
     (let [(allow (parseAllowlist text))]
       (mt (git! root (list "ls-files" "-z"))
         ((err e) (err e))
         ((ok listing)
          (let [(files (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit listing "\u0000")))]
            (mt (inlineAll! root files (InlineReport :counts (mapEmpty) :files (list) :total 0))
              ((err e) (err e))
              ((ok inline)
               (mt (scanFiles! root (listSort allow.order) files (Scan :found (list) :unlisted (list) :allowRest (listSort allow.order) :prev "" :dir "" :dirReal ""))
                 ((err e) (err e))
                 ((ok t) (auditTracked! root showAll baseEnv allow files t inline)))))))))

fn auditTracked! root: String showAll: Bool baseEnv: String allow: Allow files: (List String) t: Tracked inline: InlineReport -> (Result Audit String)
  (let [(stale (sortedKeys (filter (fn [(p String)] -> Bool (not (mapHas? t.langs p))) allow.order)))
        (c1 (listAppend (perItem "gate4Foreign" t.unlisted "ERR_FOREIGN" (listLength files))
                        (perItem "foreignAllowlist" (listAppend (map (fn [(p String)] -> String (str "entry names no tracked file " p)) stale) allow.bad) "ERR_STALE_ALLOWLIST" (listLength allow.order))))
        (langPaths (sortedKeys t.order))
        (kindBad (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (kindFinding allow t p))) (list) langPaths))
        (c2 (listAppend c1 (perItem "foreignKind" kindBad "ERR_FOREIGN_KIND" (listLength t.order))))]
    (mt (readText! (str root "/" (baselineRel)))
      ((err e) (err e))
      ((ok maybe)
       (mt maybe
         ((none) (ok (Audit :checks (listAppend c2 (list (failCheck "foreignBaseline" "ERR_FOREIGN_BASELINE" (str (baselineRel) " absent; seed it with audit foreign --lower")))) :head "" :tail "")))
         ((some btext) (auditMeasured! root showAll baseEnv allow t btext c2 inline))))))

fn auditMeasured! root: String showAll: Bool baseEnv: String allow: Allow t: Tracked btext: String c2: (List Check) inline: InlineReport -> (Result Audit String)
       (let [(b (parseBaseline btext))]
         (mt (measureAll! root t t.order (mapEmpty))
           ((err e) (err e))
           ((ok ms) (auditBaseline! root showAll baseEnv allow t b ms c2 inline))))

fn auditBaseline! root: String showAll: Bool baseEnv: String allow: Allow t: Tracked b: Baseline ms: (Map String (Pair Int64 Int64)) c2: (List Check) inline: InlineReport -> (Result Audit String)
  (let [(langPaths (sortedKeys t.order))
        (unbaselined (filter (fn [(p String)] -> Bool (not (mapHas? b.rows p))) langPaths))
        (orphan (sortedKeys (filter (fn [(p String)] -> Bool (not (mapHas? allow.entries p))) b.order)))
        (rowCount (listLength b.order))
        (c3 (listAppend c2 (perItem "foreignBaseline"
                                    (listAppend b.bad
                                                (listAppend (map (fn [(p String)] -> String
                                                                   (let [(m (measuredOf ms p))]
                                                                     (str "allowlisted path has no baseline row; add " (baselineRow p (langOr (langsOf t p) "none") (pairFirst m) (pairSecond m)) " and a matching (:raise)")))
                                                                 unbaselined)
                                                            (map (fn [(p String)] -> String (str "baseline row names no allowlist entry; delete it: " p)) orphan)))
                                    "ERR_FOREIGN_BASELINE" rowCount)))
        (perFile (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (growthOf t b ms p))) (list) langPaths))
        (totalLines (sumBy (map (fn [(p String)] -> Int64 (pairFirst (measuredOf ms p))) t.order)))
        (totalPy (sumBy (map (fn [(p String)] -> Int64 (pairSecond (measuredOf ms p))) t.order)))
        (rowList (map (fn [(p String)] -> Row (optionOr (mapGet b.rows p) (Row :lang "" :lines 0 :py 0))) b.order))
        (limitLines (sumBy (map (fn [(r Row)] -> Int64 r.lines) rowList)))
        (limitPy (sumBy (map (fn [(r Row)] -> Int64 r.py) rowList)))
        (entryCount (listLength allow.order))
        (grown (listAppend perFile
                 (listAppend (if (> entryCount rowCount) (list (str "allowlist entries " (itos entryCount) " > baseline rows " (itos rowCount))) (list))
                   (listAppend (if (> totalLines limitLines) (list (str "total foreign lines " (itos totalLines) " > baseline " (itos limitLines) " (+" (itos (- totalLines limitLines)) ")")) (list))
                               (if (> totalPy limitPy) (list (str "total embedded python lines " (itos totalPy) " > baseline " (itos limitPy) " (+" (itos (- totalPy limitPy)) ")")) (list))))))
        (c4 (listAppend c3 (perItem "foreignGrowth" grown "ERR_FOREIGN_GROWTH" rowCount)))]
    (mt (foreignBase! root baseEnv)
      ((err e) (err e))
      ((ok base)
       (mt (atRevision! root base (baselineRel))
         ((err e) (err e))
         ((ok baseText)
          (mt (atRevision! root base (allowlistRel))
            ((err e) (err e))
            ((ok baseAllow) (ok (auditRatchet showAll allow t b ms c4 base baseText baseAllow totalLines limitLines totalPy inline)))))))))

fn auditRatchet showAll: Bool allow: Allow t: Tracked b: Baseline ms: (Map String (Pair Int64 Int64)) c4: (List Check) base: String baseText: (Option String) baseAllow: (Option String) totalLines: Int64 limitLines: Int64 totalPy: Int64 inline: InlineReport -> Audit
  (let [(rowCount (listLength b.order))
        (baseB (mt baseText ((some bt) (parseBaseline bt)) ((none) (Baseline :order (list) :rows (mapEmpty) :raises (list) :bad (list)))))
        (raisedBad (mt baseText
                     ((none) (list))
                     ((some _) (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (raisedFinding b baseB.rows base p))) (list) (sortedKeys b.order)))))
        (c5 (listAppend c4 (perItem "foreignRaise" raisedBad "ERR_BASELINE_RAISED" rowCount)))
        (baseEntries (mt baseAllow ((some ba) (parseAllowlist ba).entries) ((none) (mapEmpty))))
        (fresh (filter (fn [(p String)] -> Bool (not (mapHas? baseEntries p))) (sortedKeys allow.order)))
        (untilBad (map (fn [(p String)] -> String (str "new entry " p " has :until :none and no :reason"))
                       (filter (fn [(p String)] -> Bool
                                 (mt (mapGet allow.entries p)
                                   ((some e) (and (= e.until "none") (stringEmpty? (stripAll e.reason))))
                                   ((none) false)))
                               fresh)))
        (checks (listAppend c5 (perItem "foreignUntil" untilBad "ERR_UNTIL_NONE_REASON" (listLength fresh))))
        (baseForms (map (fn [(r Raise)] -> String r.form) baseB.raises))
        (newRaises (filter (fn [(r Raise)] -> Bool (not (listContains? baseForms r.form))) b.raises))
        (failEv (str (stringJoin (map (fn [(c Check)] -> String c.ev) (failedOf checks)) " ") " "))
        (inlineSummary (if (> inline.total 0) (str " :inlineForeignLines " (itos inline.total) " :inlineForeignByFile (" (stringJoin (listReverse inline.files) " ") ") :inlineByLang (" (langCountsText inline.counts) ")") ""))
        (head (str ":entries " (itos (listLength allow.order)) " :baselineRows " (itos rowCount) " :lines " (itos totalLines) " :limit " (itos limitLines)
                   " :embeddedPy " (itos totalPy) " :byLang (" (byLangText t ms) ") :base \"" (cut base 0 12) "\" :raiseBase " (if (some? baseText) ":present" ":none")
                   " :raises " (itos (listLength b.raises)) " :newRaises " (itos (listLength newRaises)) inlineSummary))
        (shown (filter (fn [(r Raise)] -> Bool (or showAll (not (listContains? baseForms r.form)) (stringContains? failEv (str r.path " ")))) b.raises))]
    (Audit :checks checks :head head :tail (stringJoin (map raiseForm shown) " ")))

fn civil days: Int64 -> String
  (let [(z (+ days 719468))
        (era (/ (if (>= z 0) z (- z 146096)) 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (- (+ doe (/ doe 36524)) (/ doe 1460)) (/ doe 146096)) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str (itos y) "-" (pad2 m) "-" (pad2 d)))

fn pad2 k: Int64 -> String
  (if (< k 10) (str "0" (itos k)) (itos k))

fn localOffsetS! root: String -> (Result Int64 String)
  (mt (git! root (list "-c" "user.name=aslAudit" "-c" "user.email=aslAudit@localhost" "var" "GIT_COMMITTER_IDENT"))
    ((err e) (err e))
    ((ok ident)
     (let [(tz (optionOr (listLast (stringSplit (stringTrim ident) " ")) ""))
           (sign (if (stringStartsWith? tz "-") -1 1))
           (hh (stringToInt64 (cut tz 1 3)))
           (mm (stringToInt64 (cut tz 3 5)))]
       (if (and (= (stringLength tz) 5) (some? hh) (some? mm))
         (ok (* sign (+ (* 3600 (optionOr hh 0)) (* 60 (optionOr mm 0)))))
         (err (str "git var GIT_COMMITTER_IDENT: no timezone in " ident))))))

fn localDate! root: String -> (Result String String)
  (mt (localOffsetS! root)
    ((err e) (err e))
    ((ok off)
     (let [(secs (+ (/ (nowNs) 1000000000) off))
           (days (if (>= secs 0) (/ secs 86400) (- (/ (+ secs 1) 86400) 1)))]
       (ok (civil days)))))

fn baselineHead date: String -> String
  (str "(:foreignBaseline :v 1 :owner \"GF2\" :date \"" date "\"\n"
       "  :doc \"foreign volume ratchet read by audit foreign: one (:file) row per foreignAllowlist.asn entry with the file language and its"
       " line count; :py counts the lines of python embedded in a shell file (heredocs fed to python, python -c strings) and is part of :lines;"
       " binaries are :lines 0. The audit fails when a file, the total or the entry count exceeds these rows or a language differs."
       " Rows may be lowered freely (audit foreign --lower writes measured values, never higher ones); a row above its value at the ratchet"
       " base (ASL_FOREIGN_BASE, else merge-base HEAD main) or new since it passes only with a :raise form (:path :lang :lines :py :reason :date)"
       " covering it; the receipt counts :raises and :newRaises and prints in full the :raise forms new since that base, those naming a failing path, or all with --raises\"\n")

fn lowerRow! root: String seeded: Bool b: Baseline acc: Lowered rel: String -> (Result Lowered String)
  (let [(full (str root "/" rel))]
    (if (not (plainFile? full (resultOr (realPath (dirName full)) "")))
      (ok acc)
      (mt (foreignLangOf! full rel)
        ((err e) (err e))
        ((ok found)
         (let [(lang (langOr found "none"))]
           (mt (measureForeign! full lang)
             ((err e) (err e))
             ((ok m)
              (let [(lines (pairFirst m)) (py (pairSecond m)) (row (mapGet b.rows rel))]
                (cond
                  (seeded (ok (with acc :rows (cons (baselineRow rel lang lines py) acc.rows))))
                  (else
                   (mt row
                     ((none) (ok acc))
                     ((some r)
                      (if (and (= r.lang lang) (<= lines r.lines) (<= py r.py))
                        (ok (Lowered :rows (cons (baselineRow rel lang lines py) acc.rows)
                                     :lowered (+ acc.lowered (if (and (= lines r.lines) (= py r.py)) 0 1))))
                        (ok (with acc :rows (cons (baselineRow rel r.lang r.lines r.py) acc.rows))))))))))))))))

fn lowerRows! root: String seeded: Bool b: Baseline paths: (List String) acc: Lowered -> (Result Lowered String)
  (mt (listHead paths)
    ((none) (ok (with acc :rows (listReverse acc.rows))))
    ((some rel)
     (mt (lowerRow! root seeded b acc rel)
       ((err e) (err e))
       ((ok a1) (lowerRows! root seeded b (optionOr (listTail paths) (list)) a1)))))

fn rstripNewlines s: String -> String
  (if (stringEndsWith? s "\n") (rstripNewlines (cut s 0 (- (stringLength s) 1))) s)

fn lowerBaseline! root: String -> (Result (Pair Int64 Int64) String)
  (mt (readText! (str root "/" (allowlistRel)))
    ((err e) (err e))
    ((ok maybe)
     (mt maybe
       ((none) (err "scripts/audit/foreignAllowlist.asn absent"))
       ((some text) (lowerFrom! root text)))))

fn lowerFrom! root: String text: String -> (Result (Pair Int64 Int64) String)
     (let [(allow (parseAllowlist text))
           (bpath (str root "/" (baselineRel)))]
       (mt (readText! bpath)
         ((err e) (err e))
         ((ok btext)
          (let [(b (mt btext ((some bt) (parseBaseline bt)) ((none) (Baseline :order (list) :rows (mapEmpty) :raises (list) :bad (list)))))
                (bad (listAppend allow.bad b.bad))]
            (if (not (listEmpty? bad))
              (err (str "allowlist or baseline does not parse: " (optionOr (listHead bad) "")))
              (mt (lowerRows! root (none? btext) b allow.order (Lowered :rows (list) :lowered 0))
                ((err e) (err e))
                ((ok low)
                 (mt (localDate! root)
                   ((err e) (err e))
                   ((ok date)
                    (let [(body (str (stringJoin (map (fn [(r String)] -> String (str "  " r "\n")) low.rows) "")
                                     (stringJoin (map (fn [(r Raise)] -> String (str "  " r.form "\n")) b.raises) "")))
                          (tmp (str bpath ".tmp"))]
                      (mt (fileWrite tmp (str (baselineHead date) (rstripNewlines body) ")\n"))
                        ((err e) (err (osError (str e) tmp)))
                        ((ok _)
                         (mt (pathRename tmp bpath)
                           ((err e) (err (osError e tmp)))
                           ((ok _) (ok (pair low.lowered (listLength low.rows)))))))))))))))))

fn usageOk? args: (List String) -> Bool
  (and (listAll? (fn [(a String)] -> Bool (or (= a "--lower") (= a "--raises"))) args)
       (= (listLength args) (listLength (fold (fn [(acc (List String)) (a String)] -> (List String) (if (listContains? acc a) acc (cons a acc))) (list) args))))

fn runForeign! root: String args: (List String) baseEnv: String -> ForeignRun
  (if (not (usageOk? args))
    (emit "foreign" (list (failCheck "usage" "ERR_USAGE" (str "foreign takes --lower and --raises, got " (stringJoin args " ")))) "" "")
    (mt (if (listContains? args "--lower")
          (resultMap (lowerBaseline! root) (fn [(lw (Pair Int64 Int64))] -> String (str ":lowered " (itos (pairFirst lw)) " :written " (itos (pairSecond lw)) " ")))
          (ok ""))
      ((err e) (internal e))
      ((ok lowHead)
       (mt (foreignAudit! root (listContains? args "--raises") baseEnv)
         ((err e) (internal e))
         ((ok a) (emit "foreign" a.checks (str lowHead a.head) a.tail))))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (git! "." (list "rev-parse" "--show-toplevel"))
    ((err e) (let [(r (internal e))] (do (eprintln r.summary) (println r.receipt) (ok r.exitCode))))
    ((ok top)
     (let [(r (runForeign! (stringTrim top) args (optionOr (envGet "ASL_FOREIGN_BASE") "")))]
       (do (eprintln r.summary) (println r.receipt) (ok r.exitCode)))))
