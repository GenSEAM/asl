(module asl-forms/kernel :x [toolEnv! charAt isSpaceChar countDyck1 isBalanced escapeAsnVal concatAll universalNewlines findFrom asnUnescape extractSteps batchSeq ParsedStep EditOutcome parseStep kwOr normalizePath dirName baseName joinPath relPath resolveInRoot! relToRoot resolveEditTarget! binaryKind isFile! isDir! realChild? lstripColons lineEnds splitLinesKeepEnds] :i [])


(schema ParsedStep (:f op String) (:f kwargs (Map String String)) (:f args (List String)))

(schema EditOutcome (:f lines (List String)) (:f errCount Int64))


fn ! envText! name: String -> String
  (optionOr (envGet name) "")

fn ! toolEnv! name: String -> String
  (cond
    ((or (not (stringEmpty? (envText! "ROOT_DIR"))) (not (stringEmpty? (envText! "SCRIPT_DIR")))) (envText! name))
    ((= name "ROOT_DIR") (envText! "ASL_CLI_ROOT"))
    ((= name "SCRIPT_DIR") (envText! "ASL_CLI_SCRIPT_DIR"))
    (else (envText! name)))


fn sepLen b: Bytes n: Int64 i: Int64 c: Int64 -> Int64
  (cond
    ((or (= c 10) (= c 11) (= c 12) (= c 28) (= c 29) (= c 30)) 1)
    ((= c 13) (if (and (< (+ i 1) n) (= (bytesGet b (+ i 1)) 10)) 2 1))
    ((and (= c 194) (< (+ i 1) n) (= (bytesGet b (+ i 1)) 133)) 2)
    ((and (= c 226) (< (+ i 2) n) (= (bytesGet b (+ i 1)) 128) (or (= (bytesGet b (+ i 2)) 168) (= (bytesGet b (+ i 2)) 169))) 3)
    (else 0))

fn endsScan b: Bytes n: Int64 i: Int64 start: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n)
    (listReverse (if (< start n) (cons n acc) acc))
    (let [(k (sepLen b n i (bytesGet b i)))]
      (if (= k 0) (endsScan b n (+ i 1) start acc) (endsScan b n (+ i k) (+ i k) (cons (+ i k) acc)))))

fn lineEnds text: String -> (List Int64)
  (endsScan (stringToBytes text) (stringLength text) 0 0 (list))

fn splitLinesKeepEnds text: String -> (List String)
  (let [(ends (lineEnds text))]
    (map (fn [(p (Pair Int64 Int64))] -> String (optionOr (stringSlice text (pairFirst p) (pairSecond p)) ""))
         (zip (cons 0 ends) ends)))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn isSpaceChar c: String -> Bool
  (or (= c " ") (= c "\t") (= c "\n") (= c "\r") (= c "\x0b") (= c "\x0c") (= c "\x1c") (= c "\x1d") (= c "\x1e") (= c "\x1f"))

fn dyckLoop text: String i: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (>= i n)
    (if inStr -1 depth)
    (let [(c (charAt text i))]
      (cond
        (esc (dyckLoop text (+ i 1) n depth inStr false))
        ((= c "\\") (dyckLoop text (+ i 1) n depth inStr inStr))
        ((= c "\"") (dyckLoop text (+ i 1) n depth (not inStr) false))
        (inStr (dyckLoop text (+ i 1) n depth inStr false))
        ((< depth 0) -1)
        ((= c "(") (dyckLoop text (+ i 1) n (+ depth 1) inStr false))
        ((= c ")") (dyckLoop text (+ i 1) n (- depth 1) inStr false))
        (else (dyckLoop text (+ i 1) n depth inStr false)))))

fn countDyck1 text: String -> Int64
  (dyckLoop text 0 (stringLength text) 0 false false)

fn isBalanced text: String -> Bool
  (let [(c (stringTrim text))]
    (and (> (stringLength c) 0) (= (countDyck1 c) 0)))

fn concatAll parts: (List String) -> String
  (if (<= (listLength parts) 1)
    (optionOr (listHead parts) "")
    (concatAll (pairUp parts (list))))

fn pairUp parts: (List String) acc: (List String) -> (List String)
  (mt (listHead parts)
    ((none) (listReverse acc))
    ((some a)
      (let [(rest (optionOr (listTail parts) (list)))]
        (mt (listHead rest)
          ((none) (listReverse (cons a acc)))
          ((some b) (pairUp (optionOr (listTail rest) (list)) (cons (stringConcat a b) acc)))))))

fn escapeScan s: String b: Bytes n: Int64 i: Int64 from: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (optionOr (stringSlice s from n) "") acc))
    (let [(c (bytesGet b i))
          (rep (cond ((= c 92) "\\\\") ((= c 34) "\\\"") ((= c 10) "\\n") (else "")))]
      (if (stringEmpty? rep)
        (escapeScan s b n (+ i 1) from acc)
        (escapeScan s b n (+ i 1) (+ i 1) (cons rep (cons (optionOr (stringSlice s from i) "") acc))))))

fn escapeAsnVal s: String -> String
  (if (or (stringContains? s "\\") (stringContains? s "\"") (stringContains? s "\n"))
    (concatAll (escapeScan s (stringToBytes s) (stringLength s) 0 0 (list)))
    s)

fn crScan s: String b: Bytes n: Int64 i: Int64 from: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (optionOr (stringSlice s from n) "") acc))
    (if (= (bytesGet b i) 13)
      (let [(skip (if (and (< (+ i 1) n) (= (bytesGet b (+ i 1)) 10)) 2 1))]
        (crScan s b n (+ i skip) (+ i skip) (cons "\n" (cons (optionOr (stringSlice s from i) "") acc))))
      (crScan s b n (+ i 1) from acc)))

fn universalNewlines s: String -> String
  (if (stringContains? s "\r") (concatAll (crScan s (stringToBytes s) (stringLength s) 0 0 (list))) s)

fn findScan b: Bytes s: String needle: String first: Int64 k: Int64 i: Int64 last: Int64 -> Int64
  (cond
    ((> i last) -1)
    ((and (= (bytesGet b i) first) (= (optionOr (stringSlice s i (+ i k)) "") needle)) i)
    (else (findScan b s needle first k (+ i 1) last)))

fn findFrom s: String b: Bytes needle: String from: Int64 -> Int64
  (let [(k (stringLength needle))]
    (if (= k 0)
      (if (<= from (stringLength s)) from -1)
      (findScan b s needle (bytesGet (stringToBytes needle) 0) k (max 0 from) (- (stringLength s) k))))

fn unescapeLoop s: String i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(c (charAt s i))]
      (if (and (= c "\\") (< (+ i 1) n))
        (let [(nx (charAt s (+ i 1)))
              (rep (cond ((= nx "n") "\n") ((= nx "t") "\t") ((= nx "\"") "\"") ((= nx "\\") "\\") (else (str "\\" nx))))]
          (unescapeLoop s (+ i 2) n (cons rep acc)))
        (unescapeLoop s (+ i 1) n (cons c acc)))))

fn asnUnescape s: String -> String
  (if (stringContains? s "\\") (unescapeLoop s 0 (stringLength s) (list)) s)

fn formEnd s: String i: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (>= i n)
    -1
    (let [(c (charAt s i))]
      (cond
        (esc (formEnd s (+ i 1) n depth inStr false))
        ((= c "\\") (formEnd s (+ i 1) n depth inStr inStr))
        ((= c "\"") (formEnd s (+ i 1) n depth (not inStr) false))
        (inStr (formEnd s (+ i 1) n depth inStr false))
        ((= c "(") (formEnd s (+ i 1) n (+ depth 1) inStr false))
        ((= c ")") (if (= depth 1) i (formEnd s (+ i 1) n (- depth 1) inStr false)))
        (else (formEnd s (+ i 1) n depth inStr false)))))

fn stepsLoop inner: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (if (= (charAt inner i) "(")
      (let [(e (formEnd inner i n 0 false false))]
        (if (< e 0)
          (listReverse acc)
          (stepsLoop inner (+ e 1) n (cons (optionOr (stringSlice inner i (+ e 1)) "") acc))))
      (stepsLoop inner (+ i 1) n acc)))

fn rstrip s: String -> String
  (let [(n (stringLength s))]
    (if (and (> n 0) (isSpaceChar (charAt s (- n 1))))
      (rstrip (optionOr (stringSlice s 0 (- n 1)) ""))
      s))

fn extractSteps payload: String -> (List String)
  (let [(s0 (stringTrim payload))
        (s (if (and (not (stringStartsWith? s0 "(")) (stringStartsWith? s0 ":")) (str "(" s0 ")") s0))
        (skip (cond ((stringStartsWith? s "(:batch") 7) ((stringStartsWith? s "(batch") 6) (else 0)))
        (cut (rstrip (optionOr (stringSlice s skip (stringLength s)) "")))
        (inner (cond
                 ((= skip 0) s)
                 ((stringEndsWith? cut ")") (optionOr (stringSlice cut 0 (- (stringLength cut) 1)) ""))
                 (else cut)))]
    (if (stringEmpty? s0) (list) (stepsLoop inner 0 (stringLength inner) (list))))

fn isWordChar c: String -> Bool
  (let [(k (charCode c))]
    (or (and (>= k 48) (<= k 57)) (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)) (= k 95)))

fn skipSpace s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (isSpaceChar (charAt s i))) (skipSpace s (+ i 1) n) i)

fn seqTrueAt head: String i: Int64 -> Bool
  (let [(n (stringLength head))
        (j (skipSpace head (+ i 4) n))
        (k (if (= (charAt head j) ":") (+ j 1) j))]
    (and (> j (+ i 4))
         (= (optionOr (stringSlice head k (+ k 4)) "") "true")
         (or (>= (+ k 4) n) (not (isWordChar (charAt head (+ k 4)))))))

fn seqScan head: String from: Int64 -> Bool
  (let [(rest (optionOr (stringSlice head from (stringLength head)) ""))]
    (mt (stringIndexOf rest ":seq")
      ((none) false)
      ((some p) (or (seqTrueAt head (+ from p)) (seqScan head (+ from p 1))))))

fn batchSeq payload: String -> Bool
  (if (or (stringStartsWith? payload "(:batch") (stringStartsWith? payload "(batch"))
    (let [(tail (optionOr (stringSlice payload 1 (stringLength payload)) ""))
          (head (optionOr (listHead (stringSplit tail "(")) ""))]
      (seqScan head 0))
    false)

fn stringTokEnd s: String i: Int64 n: Int64 esc: Bool -> Int64
  (if (>= i n)
    n
    (let [(c (charAt s i))]
      (cond
        (esc (stringTokEnd s (+ i 1) n false))
        ((= c "\\") (stringTokEnd s (+ i 1) n true))
        ((= c "\"") (+ i 1))
        (else (stringTokEnd s (+ i 1) n false)))))

fn groupTokEnd s: String i: Int64 n: Int64 openC: String closeC: String depth: Int64 inQ: Bool esc: Bool -> Int64
  (if (>= i n)
    n
    (let [(c (charAt s i))]
      (cond
        (esc (groupTokEnd s (+ i 1) n openC closeC depth inQ false))
        ((= c "\\") (groupTokEnd s (+ i 1) n openC closeC depth inQ inQ))
        ((= c "\"") (groupTokEnd s (+ i 1) n openC closeC depth (not inQ) false))
        (inQ (groupTokEnd s (+ i 1) n openC closeC depth inQ false))
        ((= c openC) (groupTokEnd s (+ i 1) n openC closeC (+ depth 1) inQ false))
        ((= c closeC) (if (= depth 1) (+ i 1) (groupTokEnd s (+ i 1) n openC closeC (- depth 1) inQ false)))
        (else (groupTokEnd s (+ i 1) n openC closeC depth inQ false)))))

fn bareTokEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (isSpaceChar (charAt s i)))) (bareTokEnd s (+ i 1) n) i)

fn tokenize s: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (let [(st (skipSpace s i n))]
    (if (>= st n)
      (listReverse acc)
      (let [(c (charAt s st))
            (e (cond
                 ((= c "\"") (stringTokEnd s (+ st 1) n false))
                 ((= c "(") (groupTokEnd s st n "(" ")" 0 false false))
                 ((= c "[") (groupTokEnd s st n "[" "]" 0 false false))
                 (else (bareTokEnd s st n))))]
        (tokenize s e n (cons (optionOr (stringSlice s st e) "") acc)))))

fn subArgKey? k: String -> Bool
  (listContains? (list "mode" "action" "status" "distill" "engine" "op" "stepOp" "direction" "kind" "format" "role" "depth" "service" "type" "profile" "lenses" "target" "model" "subcmd" "tier" "level" "scope" "topic") k)

fn unquote tok: String -> String
  (let [(n (stringLength tok))]
    (if (and (>= n 2) (stringStartsWith? tok "\"") (stringEndsWith? tok "\""))
      (asnUnescape (optionOr (stringSlice tok 1 (- n 1)) ""))
      tok))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (optionOr (stringSlice s 1 (stringLength s)) "")) s)

fn parseArgs toks: (List String) kw: (Map String String) args: (List String) -> (Pair (Map String String) (List String))
  (mt (listHead toks)
    ((none) (pair kw (listReverse args)))
    ((some tok)
      (let [(rest (optionOr (listTail toks) (list)))]
        (if (stringStartsWith? tok ":")
          (let [(key (lstripColons tok))]
            (mt (listHead rest)
              ((none) (parseArgs rest (mapSet kw key "true") args))
              ((some nextTok)
                (let [(after (optionOr (listTail rest) (list)))
                      (hasSubArg (mt (listHead after) ((none) false) ((some t2) (not (stringStartsWith? t2 ":")))))
                      (takes (or (not (stringStartsWith? nextTok ":"))
                                 (and (not hasSubArg) (or (subArgKey? key) (listEmpty? after)))))]
                  (if takes
                    (parseArgs after (mapSet kw key (unquote nextTok)) args)
                    (parseArgs rest (mapSet kw key "true") args))))))
          (parseArgs rest kw (cons (unquote tok) args))))))

fn parseStep stepStr: String -> ParsedStep
  (let [(t (stringTrim stepStr))
        (s (if (and (stringStartsWith? t "(") (stringEndsWith? t ")"))
             (stringTrim (optionOr (stringSlice t 1 (- (stringLength t) 1)) ""))
             t))
        (toks (tokenize s 0 (stringLength s) (list)))]
    (mt (listHead toks)
      ((none) (ParsedStep :op "" :kwargs (mapEmpty) :args (list)))
      ((some first)
        (let [(parsed (parseArgs (optionOr (listTail toks) (list)) (mapEmpty) (list)))]
          (ParsedStep :op (lstripColons first) :kwargs (pairFirst parsed) :args (pairSecond parsed))))))

fn kwOr kw: (Map String String) key: String fallback: String -> String
  (let [(v (optionOr (mapGet kw key) ""))]
    (if (stringEmpty? v) fallback v))

fn normParts parts: (List String) isAbs: Bool acc: (List String) -> (List String)
  (mt (listHead parts)
    ((none) (listReverse acc))
    ((some p)
      (let [(rest (optionOr (listTail parts) (list)))]
        (cond
          ((or (= p "") (= p ".")) (normParts rest isAbs acc))
          ((= p "..")
            (cond
              ((and (not isAbs) (listEmpty? acc)) (normParts rest isAbs (cons ".." acc)))
              ((= (optionOr (listHead acc) "") "..") (normParts rest isAbs (cons ".." acc)))
              ((listEmpty? acc) (normParts rest isAbs acc))
              (else (normParts rest isAbs (optionOr (listTail acc) (list))))))
          (else (normParts rest isAbs (cons p acc)))))))

fn normalizePath path: String -> String
  (let [(isAbs (stringStartsWith? path "/"))
        (joined (stringJoin (normParts (stringSplit path "/") isAbs (list)) "/"))]
    (cond
      (isAbs (str "/" joined))
      ((stringEmpty? joined) ".")
      (else joined)))

fn lastSlash s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (charAt s i) "/") i) (else (lastSlash s (- i 1))))

fn rstripSlashes s: String -> String
  (if (stringEndsWith? s "/")
    (rstripSlashes (optionOr (stringSlice s 0 (- (stringLength s) 1)) ""))
    s)

fn dirName p: String -> String
  (let [(head (optionOr (stringSlice p 0 (+ (lastSlash p (- (stringLength p) 1)) 1)) ""))]
    (if (and (not (stringEmpty? head)) (not (stringEmpty? (stringReplace head "/" "")))) (rstripSlashes head) head))

fn baseName p: String -> String
  (optionOr (stringSlice p (+ (lastSlash p (- (stringLength p) 1)) 1) (stringLength p)) "")

fn commonLen a: (List String) b: (List String) n: Int64 -> Int64
  (mt (listHead a)
    ((none) n)
    ((some x)
      (mt (listHead b)
        ((none) n)
        ((some y) (if (= x y) (commonLen (optionOr (listTail a) (list)) (optionOr (listTail b) (list)) (+ n 1)) n)))))

fn pathParts p: String -> (List String)
  (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit p "/"))

fn relPath target: String base: String -> String
  (let [(t (pathParts (normalizePath target)))
        (b (pathParts (normalizePath base)))
        (k (commonLen t b 0))
        (ups (map (fn [(x String)] -> String "..") (listDrop b k)))
        (parts (listAppend ups (listDrop t k)))]
    (if (listEmpty? parts) "." (stringJoin parts "/")))

fn relToRoot root: String p: String -> String
  (relPath p root)

fn isFile! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isFile) ((err _) false))

fn isDir! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isDir) ((err _) false))

fn existingProbe! p: String -> String
  (if (fileExists? p)
    p
    (let [(parent (dirName p))]
      (if (= parent p) p (existingProbe! parent))))

fn joinPath a: String b: String -> String
  (if (stringEndsWith? a "/") (str a b) (str a "/" b))

fn resolveInRoot! root: String p: String -> (Pair String String)
  (if (stringEmpty? p)
    (pair "" "Missing path")
    (let [(cand (normalizePath (if (stringStartsWith? p "/") p (joinPath root p))))
          (probe (existingProbe! cand))
          (realProbe (resultOr (realPath probe) probe))
          (tail (if (= probe cand) "" (relPath cand probe)))
          (resolved (if (or (stringEmpty? tail) (= tail ".")) realProbe (normalizePath (joinPath realProbe tail))))]
      (if (or (= resolved root) (stringStartsWith? resolved (str root "/")))
        (pair resolved "")
        (pair "" (str "Path escapes workspace boundary: " p)))))

fn ! realChild? dir: String name: String -> Bool
  (= (resultOr (realPath (joinPath dir name)) "") (joinPath dir name))

fn excludedEditDir? name: String -> Bool
  (or (= name ".git") (= name "node_modules") (= name ".asl"))

fn findNamed! dir: String target: String acc: (List String) -> (List String)
  (mt (dirList dir)
    ((err _) acc)
    ((ok names)
      (fold (fn [(a (List String)) (name String)] -> (List String)
              (let [(full (joinPath dir name))]
                (if (isDir! full)
                  (if (or (excludedEditDir? name) (not (realChild? dir name))) a (findNamed! full target a))
                  (if (= name target) (cons full a) a))))
            acc
            names)))

fn resolveEditTarget! root: String p: String -> (Pair String String)
  (if (stringEmpty? p)
    (pair "" "Missing path")
    (let [(res (resolveInRoot! root p))
          (direct (pairFirst res))]
      (cond
        ((not (stringEmpty? (pairSecond res))) (pair "" (pairSecond res)))
        ((or (fileExists? direct) (stringContains? p "/")) (pair direct ""))
        (else
          (let [(matches (listSort (findNamed! root p (list))))
                (n (listLength matches))]
            (cond
              ((= n 1) (pair (optionOr (listHead matches) direct) ""))
              ((> n 1) (pair "" (str "Ambiguous bare filename matches " (stringFromInt64 n) " files; pass a path relative to the workspace root")))
              (else (pair direct ""))))))))

fn binaryKind content: String -> String
  (let [(head (optionOr (stringSlice content 0 (min 8192 (stringLength content))) content))]
    (cond
      ((or (stringStartsWith? head "\xcf\xfa\xed\xfe") (stringStartsWith? head "\xce\xfa\xed\xfe")) "machO")
      ((or (stringStartsWith? head "\xfe\xed\xfa\xcf") (stringStartsWith? head "\xfe\xed\xfa\xce")) "machO")
      ((stringStartsWith? head "\xca\xfe\xba\xbe") "machOFat")
      ((stringStartsWith? head "\x7fELF") "elf")
      ((stringStartsWith? head "\x00asm") "wasm")
      ((stringStartsWith? head "\x1f\x8b") "gzip")
      ((stringStartsWith? head "PK\x03\x04") "zip")
      ((stringStartsWith? head "\x89PNG\r\n\x1a\n") "png")
      ((stringStartsWith? head "\xff\xd8\xff") "jpeg")
      ((stringContains? head "\x00") (if (stringStartsWith? head "MZ") "pe" "binary"))
      (else "")))
