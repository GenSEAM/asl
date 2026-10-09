(module asl-forms/wire :x [Workspace WNode wireCamel wireTokens wireReceipt! wireError hintFor toolOps] :i [(asl-forms/kernel :a k) (asl-forms/similarity :a sm)])


(schema Workspace (:f root String) (:f roots (List String)) (:f ops (List String)))

(enum WNode (:c wAtom [(text String)]) (:c wList [(items (List WNode))]))

(schema StepParts (:f op String) (:f status String) (:f rest (List WNode)))


fn hintFor code: String -> String
  (cond
    ((or (= code "ERR_UNIMPLEMENTED") (= code "ERR_NOT_PORTED")) "(:tools) lists the implemented forms and their params")
    ((= code "ERR_FILE_NOT_FOUND") "paths resolve against the workspace root; :nearest, when present, names entries beside the missing one")
    ((= code "ERR_BOUNDARY_VIOLATION") "paths resolve against the workspace root and must stay inside it")
    ((= code "ERR_UNBALANCED") "a paren, bracket or string in the input does not close; nothing ran")
    ((= code "ERR_BINARY") "binary files are never returned as text; inspect them with a native tool such as file, otool or xxd")
    (else ""))

fn wireError code: String message: String extra: String -> String
  (let [(hint (hintFor code))]
    (str "(:batch :status :failed :error " code extra " :message \"" (k/escapeAsnVal message) "\"" (if (stringEmpty? hint) "" (str " :hint \"" hint "\"")) ")"))

fn leadingLetters s: String i: Int64 -> Int64
  (let [(c (charCode (k/charAt s i)))]
    (if (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122))) (leadingLetters s (+ i 1)) i))

fn toolOps toolsText: String -> (List String)
  (let [(pieces (optionOr (listTail (stringSplit toolsText "(:op :")) (list)))
        (names (filter (fn [(x String)] -> Bool (not (stringEmpty? x)))
                       (map (fn [(p String)] -> String (optionOr (stringSlice p 0 (leadingLetters p 0)) "")) pieces)))]
    (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (optionOr (listLast acc) "") x) acc (listAppend acc (list x)))) (list) (listSort names)))

fn opName? s: String -> Bool
  (let [(n (stringLength s))
        (ok (fn [(i Int64)] -> Bool
              (let [(c (charCode (k/charAt s i)))]
                (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (and (> i 0) (or (and (>= c 48) (<= c 57)) (= c 45)))))))]
    (and (> n 0) (listAll? ok (range 0 n))))

fn camelKey? tok: String -> Bool
  (let [(n (stringLength tok))
        (mid (fn [(c Int64)] -> Bool (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (and (>= c 48) (<= c 57)) (= c 45))))
        (lastC (charCode (k/charAt tok (- n 1))))]
    (and (>= n 3)
         (opName? (optionOr (stringSlice tok 1 (- n 1)) ""))
         (or (and (>= lastC 65) (<= lastC 90)) (and (>= lastC 97) (<= lastC 122)) (and (>= lastC 48) (<= lastC 57)) (= lastC 63) (= lastC 33))))

fn capitalize p: String -> String
  (str (stringUpper (k/charAt p 0)) (optionOr (stringSlice p 1 (stringLength p)) ""))

fn wireCamel tok: String -> String
  (if (and (stringStartsWith? tok ":") (stringContains? tok "-") (camelKey? tok))
    (let [(parts (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit (optionOr (stringSlice tok 1 (stringLength tok)) "") "-")))]
      (str ":" (optionOr (listHead parts) "") (stringJoin (map capitalize (optionOr (listTail parts) (list))) "")))
    tok)

fn wsByte? c: Int64 -> Bool
  (or (= c 32) (and (>= c 9) (<= c 13)) (and (>= c 28) (<= c 31)))

fn stringEnd b: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (bytesGet b j) 34) j)
    ((= (bytesGet b j) 92) (stringEnd b n (+ j 2)))
    (else (stringEnd b n (+ j 1))))

fn atomEnd b: Bytes n: Int64 j: Int64 -> Int64
  (if (< j n)
    (let [(c (bytesGet b j))]
      (if (or (wsByte? c) (= c 40) (= c 41) (= c 91) (= c 93) (= c 34)) j (atomEnd b n (+ j 1))))
    j)

fn tokLoop b: Bytes text: String n: Int64 i: Int64 acc: (List String) -> (Result (List String) String)
  (if (>= i n)
    (ok (listReverse acc))
    (let [(c (bytesGet b i))]
      (cond
        ((wsByte? c) (tokLoop b text n (+ i 1) acc))
        ((or (= c 40) (= c 91)) (tokLoop b text n (+ i 1) (cons "(" acc)))
        ((or (= c 41) (= c 93)) (tokLoop b text n (+ i 1) (cons ")" acc)))
        ((= c 34)
          (let [(e (stringEnd b n (+ i 1)))]
            (if (< e 0) (err "unterminated string") (tokLoop b text n (+ e 1) (cons (optionOr (stringSlice text i (+ e 1)) "") acc)))))
        (else
          (let [(e (atomEnd b n i))]
            (tokLoop b text n e (cons (optionOr (stringSlice text i e) "") acc)))))))

fn wireTokens text: String -> (Result (List String) String)
  (tokLoop (stringToBytes text) text (stringLength text) 0 (list))

fn treeLoop toks: (List String) stack: (List (List WNode)) -> (Result (List WNode) String)
  (mt (listHead toks)
    ((none)
      (if (= (listLength stack) 1) (ok (listReverse (optionOr (listHead stack) (list)))) (err "unbalanced")))
    ((some t)
      (let [(rest (optionOr (listTail toks) (list)))
            (top (optionOr (listHead stack) (list)))
            (below (optionOr (listTail stack) (list)))]
        (cond
          ((= t "(") (treeLoop rest (cons (list) stack)))
          ((= t ")")
            (if (listEmpty? below)
              (err "unbalanced")
              (treeLoop rest (cons (cons (wList (listReverse top)) (optionOr (listHead below) (list))) (optionOr (listTail below) (list))))))
          (else (treeLoop rest (cons (cons (wAtom t) top) below)))))))

fn atomText n: WNode -> (Option String)
  (mt n ((wAtom t) (some t)) ((wList _) (none)))

fn isAtom? n: WNode x: String -> Bool
  (= (atomText n) (some x))

fn stripOuterQuotes s: String -> String
  (if (and (stringStartsWith? s "\"") (> (stringLength s) 0)) (stripOuterQuotes (optionOr (stringSlice s 1 (stringLength s)) "")) (stripTrailingQuotes s))

fn stripTrailingQuotes s: String -> String
  (if (stringEndsWith? s "\"") (stripTrailingQuotes (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")) s)

fn lstripColon s: String -> String
  (if (stringStartsWith? s ":") (lstripColon (optionOr (stringSlice s 1 (stringLength s)) "")) s)

fn digits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (and (>= (charCode c) 48) (<= (charCode c) 57))) (stringChars s)))

fn stepWalk items: (List WNode) acc: StepParts -> StepParts
  (mt (listHead items)
    ((none) (with acc :rest (listReverse acc.rest)))
    ((some kNode)
      (let [(tl (optionOr (listTail items) (list)))
            (kTok (optionOr (atomText kNode) ""))
            (vTok (mt (listHead tl) ((some v) (atomText v)) ((none) (none))))
            (tl2 (optionOr (listTail tl) (list)))]
        (mt vTok
          ((some v)
            (cond
              ((and (= kTok ":id") (digits? v)) (stepWalk tl2 acc))
              ((and (= kTok ":op") (= acc.op "\u0000") (stringStartsWith? v "\""))
                (stepWalk tl2 (with acc :op (optionOr (stringSlice v 1 (- (stringLength v) 1)) ""))))
              ((and (= kTok ":status") (= acc.status "\u0000"))
                (stepWalk tl2 (with acc :status (lstripColon (stripOuterQuotes v)))))
              ((or (= kTok ":error-code") (= kTok ":errorCode"))
                (stepWalk tl2 (with acc :rest (cons (wAtom (lstripColon (stripOuterQuotes v))) (cons (wAtom ":error") acc.rest)))))
              (else (stepWalk tl (with acc :rest (cons kNode acc.rest))))))
          ((none) (stepWalk tl (with acc :rest (cons kNode acc.rest))))))))

fn valueAfter items: (List WNode) key: String -> (Option WNode)
  (mt (listHead items)
    ((none) (none))
    ((some x)
      (let [(tl (optionOr (listTail items) (list)))]
        (if (and (isAtom? x key) (not (listEmpty? tl))) (listHead tl) (valueAfter tl key)))))

fn stringValueAfter items: (List WNode) key: String quoted: Bool -> (Option String)
  (mt (listHead items)
    ((none) (none))
    ((some x)
      (let [(tl (optionOr (listTail items) (list)))
            (v (mt (listHead tl) ((some y) (atomText y)) ((none) (none))))]
        (mt v
          ((some s) (if (and (isAtom? x key) (or (not quoted) (stringStartsWith? s "\""))) (some s) (stringValueAfter tl key quoted)))
          ((none) (stringValueAfter tl key quoted))))))

fn afterNotFound msg: String -> String
  (mt (stringIndexOf msg "not found: ")
    ((none) "")
    ((some p)
      (let [(tail (optionOr (stringSlice msg (+ p 11) (stringLength msg)) ""))]
        (if (and (stringEndsWith? tail "\"") (> (stringLength tail) 1) (not (stringContains? tail "\n")))
          (optionOr (stringSlice tail 0 (- (stringLength tail) 1)) "")
          ""))))

fn existingDirUp! p: String -> String
  (if (and (not (stringEmpty? p)) (not (k/isDir! p)) (!= p (k/dirName p))) (existingDirUp! (k/dirName p)) p)

fn wireNearest! ws: Workspace code: String op: String rest: (List WNode) -> (List String)
  (cond
    ((and (= code "ERR_UNIMPLEMENTED") (not (stringEmpty? op))) (sm/getCloseMatches op ws.ops 3 0.5))
    ((and (= code "ERR_NOT_PORTED") (not (stringEmpty? op))) (sm/getCloseMatches op (filter (fn [(o String)] -> Bool (!= o op)) ws.ops) 3 0.5))
    ((= code "ERR_FILE_NOT_FOUND")
      (let [(fromFile (mt (stringValueAfter rest ":file" true) ((some s) (some (optionOr (stringSlice s 1 (- (stringLength s) 1)) ""))) ((none) (none))))
            (missing (mt fromFile ((some s) s) ((none) (afterNotFound (optionOr (stringValueAfter rest ":message" false) "")))))]
        (if (stringEmpty? missing)
          (list)
          (let [(full (if (stringStartsWith? missing "/") missing (k/joinPath ws.root missing)))
                (parent (existingDirUp! (k/dirName full)))]
            (mt (dirList parent)
              ((err _) (list))
              ((ok names)
                (map (fn [(nm String)] -> String (k/relPath (k/joinPath parent nm) ws.root))
                     (sm/getCloseMatches (k/baseName full) (filter (fn [(nm String)] -> Bool (not (stringStartsWith? nm "."))) names) 3 0.4))))))))
    (else (list)))

fn quoteAtom s: String -> WNode
  (wAtom (str "\"" (k/escapeAsnVal s) "\""))

fn wireStep! ws: Workspace items: (List WNode) failed: Bool head: String -> (List WNode)
  (if (not (isAtom? (optionOr (listHead items) (wAtom "")) ":step"))
    items
    (let [(none0 "\u0000")
          (parts (stepWalk (optionOr (listTail items) (list)) (StepParts :op none0 :status none0 :rest (list))))
          (op0 (if (opName? head) head parts.op))
          (op (if (= op0 none0) "" op0))
          (rest parts.rest)
          (headNodes (if (opName? op) (list (wAtom (wireCamel (str ":" op)))) (list (wAtom ":step") (wAtom ":op") (wAtom (str "\"" op "\"")))))
          (errCode (mt (valueAfter rest ":error") ((some n) (optionOr (atomText n) "\u0001list")) ((none) "")))
          (hint (hintFor errCode))
          (addHint (and (not (stringEmpty? hint)) (not (listAny? (fn [(n WNode)] -> Bool (isAtom? n ":hint")) rest))))
          (near (if addHint (wireNearest! ws errCode op rest) (list)))
          (rest2 (listAppend rest (listAppend (if (listEmpty? near) (list) (list (wAtom ":nearest") (wList (map quoteAtom near))))
                                              (if addHint (list (wAtom ":hint") (wAtom (str "\"" hint "\""))) (list)))))
          (st0 parts.status)
          (status (if (and failed (or (= st0 none0) (= st0 "ok"))) "failed" st0))
          (statusNodes (if (or (= status none0) (stringEmpty? status) (= status "ok")) (list) (list (wAtom ":status") (wAtom (wireCamel (str ":" status))))))
          (hasSee (listAny? (fn [(n WNode)] -> Bool (isAtom? n ":see")) rest2))
          (seeOp (if (and (not (stringEmpty? op)) (!= errCode "ERR_NOT_PORTED") (listContains? ws.ops op)) op "tools"))
          (rest3 (if (and (or (= status "rejected") (not (stringEmpty? errCode))) (not hasSee))
                   (listAppend rest2 (list (wAtom ":see") (wAtom (str "\"(:help :op " (k/escapeAsnVal seeOp) ")\""))))
                   rest2))]
      (listAppend headNodes (listAppend statusNodes rest3))))

fn replaceIn s: String old: String new: String -> String
  (if (stringContains? s old) (stringReplace s old new) s)

fn relativize roots: (List String) body: String -> String
  (let [(b0 (if (listContains? roots body) "." body))]
    (fold (fn [(acc String) (r String)] -> String (replaceIn acc (str r "/") "")) b0 roots))

fn wireStr roots: (List String) tok: String rel: Bool -> String
  (let [(body (replaceIn (replaceIn (optionOr (stringSlice tok 1 (- (stringLength tok) 1)) "") "\r" "") "\n" "\\n"))]
    (str "\"" (if rel (relativize roots body) body) "\""))

fn verbatimKey? key: String -> Bool
  (or (= key ":content") (= key ":old") (= key ":new"))

fn outItems roots: (List String) items: (List WNode) prev: String acc: (List String) -> (List String)
  (mt (listHead items)
    ((none) (listReverse acc))
    ((some x)
      (outItems roots (optionOr (listTail items) (list)) (optionOr (atomText x) "") (cons (wireOut roots x prev) acc))))

fn wireOut roots: (List String) node: WNode key: String -> String
  (mt node
    ((wList xs) (str "(" (stringJoin (outItems roots xs "" (list)) " ") ")"))
    ((wAtom t) (if (stringStartsWith? t "\"") (wireStr roots t (not (verbatimKey? key))) (wireCamel t))))

fn searchQuoted text: String key: String pred: (fn [String] -> Bool) from: Int64 -> String
  (let [(rest (optionOr (stringSlice text from (stringLength text)) ""))]
    (mt (stringIndexOf rest key)
      ((none) "")
      ((some p)
        (let [(st (+ from p (stringLength key)))
              (after (optionOr (stringSlice text st (stringLength text)) ""))
              (e (optionOr (stringIndexOf after "\"") -1))
              (cand (optionOr (stringSlice after 0 (max e 0)) ""))]
          (if (and (>= e 0) (pred cand)) cand (searchQuoted text key pred (+ from p 1)))))))

fn lowerDash? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (or (and (>= (charCode c) 97) (<= (charCode c) 122)) (= c "-"))) (stringChars s)))

fn rawReceipt text: String failed: Bool head: String -> String
  (let [(name (if (opName? head) head (searchQuoted text ":op \"" opName? 0)))
        (headTok (if (stringEmpty? name) ":step" (wireCamel (str ":" name))))
        (st (searchQuoted text ":status \"" lowerDash? 0))
        (stV (if (and (not (stringEmpty? st)) (!= st "ok")) st (if failed "failed" "")))]
    (str "(" headTok (if (stringEmpty? stV) "" (str " :status :" stV)) " :raw \"" (k/escapeAsnVal (stringTrim text)) "\")"))

fn wireReceipt! ws: Workspace text: String failed: Bool head: String -> String
  (mt (wireTokens text)
    ((err _) (rawReceipt text failed head))
    ((ok toks)
      (mt (treeLoop toks (list (list)))
        ((err _) (rawReceipt text failed head))
        ((ok forms)
          (stringJoin (map (fn [(f WNode)] -> String
                             (mt f
                               ((wList xs) (wireOut ws.roots (wList (wireStep! ws xs failed head)) ""))
                               ((wAtom _) (wireOut ws.roots f ""))))
                           forms)
                      " ")))))
