(module asl/agentLoop/core
  :x [asnUnescape escapeAsn parseForms stripForms parseKv parseReply isProseWrapped checkOwns fieldVal evidenceKey mergeSpans spanSeen recordRead renderSeen renderTranscript renderWindow makeTurn serString serOps serKey serSpans joinAll editDistance nearestOp terminalForms dataFindings uniqueSteps gateVerdict noteStep runOutward changePlan harnessPath hiddenPath runReadOnly firstOf restOf sliceOf ch dictGet isSpace isWordByte joinSep KvVal kvInt kvStr windowOf isDigit truthy headOf dictHas dictOr formEnd mapBytes progName runEnd strBodyEnd stripLeft stripRight trimSpace charIndex charLen charPrefix Turn
      residueWordCount hasFormResidue joinForms]
  :i [])

enum KvVal
  (kvStr text: String)
  (kvInt digits: String)

enum Turn
  (turnOf turn: String sent: String got: String)

; (:m :ref D148)
fn firstOf xs: (List T) -> T
  (mt (listHead xs) ((some x) x))

fn restOf xs: (List T) -> (List T)
  (mt (listTail xs) ((some t) t))

fn sliceOf s: String i: Int64 j: Int64 -> String
  (mt (stringSlice s i j) ((some t) t))

fn ch s: String i: Int64 -> String
  (sliceOf s i (+ i 1))

fn highByte -> String
  (sliceOf "À" 1 2)

fn isContinuation c: String -> Bool
  (and (>= c (sliceOf "À" 1 2)) (<= c (sliceOf "¿" 1 2)))

fn isDigit c: String -> Bool
  (and (>= c "0") (<= c "9"))

fn isWordByte c: String -> Bool
  (or (isDigit c)
    (or (and (>= c "a") (<= c "z"))
      (or (and (>= c "A") (<= c "Z"))
        (or (= c "_") (>= c (highByte))))))

fn isSpace c: String -> Bool
  (or (= c " ") (and (>= c "\t") (<= c "\r")))

fn runEnd s: String n: Int64 i: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (< i n) (test (ch s i))) (runEnd s n (+ i 1) test) i)

fn joinPairs xs: (List String) acc: (List String) -> (List String)
  (cond
    ((listEmpty? xs) (listReverse acc))
    ((listEmpty? (restOf xs)) (listReverse (cons (firstOf xs) acc)))
    (else (joinPairs (restOf (restOf xs)) (cons (stringConcat (firstOf xs) (firstOf (restOf xs))) acc))))

fn joinAll xs: (List String) -> String
  (cond
    ((listEmpty? xs) "")
    ((listEmpty? (restOf xs)) (firstOf xs))
    (else (joinAll (joinPairs xs (list)))))

fn joinSep xs: (List String) sep: String -> String
  (if (listEmpty? xs) ""
    (joinAll (cons (firstOf xs) (fold (fn [acc x] (cons sep (cons x acc))) (list) (listReverse (restOf xs))))))

fn mapBytes s: String n: Int64 i: Int64 start: Int64 table: (fn [String] -> String) acc: (List String) -> String
  (if (>= i n)
    (joinAll (listReverse (cons (sliceOf s start n) acc)))
    (let [m (table (ch s i))]
      (if (= m "")
        (mapBytes s n (+ i 1) start table acc)
        (mapBytes s n (+ i 1) (+ i 1) table (cons m (cons (sliceOf s start i) acc))))))

fn asnEscapeByte c: String -> String
  (cond
    ((= c "\\") "\\\\")
    ((= c "\"") "\\\"")
    ((= c "\n") "\\n")
    (else ""))

fn serEscapeByte c: String -> String
  (cond
    ((= c "\r") "\\r")
    ((= c "\t") "\\t")
    (else (asnEscapeByte c)))

fn escapeAsn s: String -> String
  (mapBytes s (stringLength s) 0 0 asnEscapeByte (list))

fn serString s: String -> String
  (str "\"" (mapBytes s (stringLength s) 0 0 serEscapeByte (list)) "\"")

fn unescapeOf c: String -> String
  (cond
    ((= c "n") "\n")
    ((= c "t") "\t")
    ((= c "\"") "\"")
    ((= c "\\") "\\")
    (else ""))

fn unescapeLoop s: String n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (joinAll (listReverse (cons (sliceOf s start n) acc))))
    ((and (= (ch s i) "\\") (< (+ i 1) n))
      (let [m (unescapeOf (ch s (+ i 1)))]
        (if (= m "")
          (unescapeLoop s n (+ i 2) start acc)
          (unescapeLoop s n (+ i 2) (+ i 2) (cons m (cons (sliceOf s start i) acc))))))
    (else (unescapeLoop s n (+ i 1) start acc)))

fn asnUnescape s: String -> String
  (unescapeLoop s (stringLength s) 0 0 (list))

fn formEnd s: String n: Int64 j: Int64 depth: Int64 inStr: Bool esc: Bool -> (Pair Int64 Int64)
  (if (or (>= j n) (<= depth 0))
    (pair j depth)
    (let [c (ch s j)]
      (cond
        (esc (formEnd s n (+ j 1) depth inStr false))
        ((and (= c "\\") inStr) (formEnd s n (+ j 1) depth inStr true))
        ((= c "\"") (formEnd s n (+ j 1) depth (not inStr) false))
        (inStr (formEnd s n (+ j 1) depth inStr false))
        ((= c "(") (formEnd s n (+ j 1) (+ depth 1) inStr false))
        ((= c ")") (formEnd s n (+ j 1) (- depth 1) inStr false))
        (else (formEnd s n (+ j 1) depth inStr false)))))

fn formsLoop s: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse acc))
    ((= (ch s i) "(")
      (mt (formEnd s n (+ i 1) 1 false false)
        ((pair j d) (formsLoop s n j (if (= d 0) (cons (sliceOf s i j) acc) acc)))))
    (else (formsLoop s n (+ i 1) acc)))

fn parseForms text: String -> (List String)
  (formsLoop text (stringLength text) 0 (list))

fn stripLoop s: String n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (joinAll (listReverse (cons (sliceOf s start n) acc))))
    ((= (ch s i) "(")
      (mt (formEnd s n (+ i 1) 1 false false)
        ((pair j _) (stripLoop s n j j (cons " " (cons (sliceOf s start i) acc))))))
    (else (stripLoop s n (+ i 1) start acc)))

fn stripForms text: String -> String
  (stripLoop text (stringLength text) 0 0 (list))

fn wordCount s: String n: Int64 i: Int64 inWord: Bool k: Int64 -> Int64
  (cond
    ((>= i n) k)
    ((isSpace (ch s i)) (wordCount s n (+ i 1) false k))
    (inWord (wordCount s n (+ i 1) true k))
    (else (wordCount s n (+ i 1) true (+ k 1))))

; (:m :adopted NormativeAndEmpiricalAreNotMixed)
fn isProseWrapped reply: String -> Bool
  (if (stringContains? reply "```")
    true
    (let [p (stripForms reply)]
      (> (wordCount p (stringLength p) 0 false 0) 40)))

; (:m :ref PROSE-THRESHOLD :do "no 40-word/``` floor, so it trips on the same short trailing-text cases metrics.asl classifyDefect already flags as prose")
fn residueWordCount reply: String -> Int64
  (let [p (stripForms reply)]
    (wordCount p (stringLength p) 0 false 0))

fn hasFormResidue reply: String -> Bool
  (> (residueWordCount reply) 0)

fn joinForms reply: String -> String
  (joinSep (parseForms reply) "\n")

fn dictGet d: (List (Pair String KvVal)) k: String -> (Option KvVal)
  (cond
    ((listEmpty? d) none)
    (else (mt (firstOf d) ((pair ek v) (if (= ek k) (some v) (dictGet (restOf d) k))))))

fn dictHas d: (List (Pair String KvVal)) k: String -> Bool
  (some? (dictGet d k))

fn dictSet d: (List (Pair String KvVal)) k: String v: KvVal -> (List (Pair String KvVal))
  (if (dictHas d k)
    (map (fn [p] (mt p ((pair ek ev) (if (= ek k) (pair k v) p)))) d)
    (listAppend d (list (pair k v))))

fn dictOr d: (List (Pair String KvVal)) k: String -> KvVal
  (optionOr (dictGet d k) (kvStr ""))

fn truthy o: (Option KvVal) -> Bool
  (mt o
    ((some v) (mt v ((kvStr t) (!= t "")) ((kvInt t) (!= t "0"))))
    (none false))

fn dropZeros s: String i: Int64 -> String
  (if (and (< i (- (stringLength s) 1)) (= (ch s i) "0")) (dropZeros s (+ i 1)) (sliceOf s i (stringLength s)))

fn headOf s: String -> String
  (let [n (stringLength s)]
    (if (or (= n 0) (!= (ch s 0) "("))
      ""
      (let [i (runEnd s n 1 isSpace)]
        (if (and (< i n) (= (ch s i) ":"))
          (sliceOf s (+ i 1) (runEnd s n (+ i 1) isWordByte))
          ""))))

fn isKeyStart c: String -> Bool
  (and (not (isDigit c))
    (and (not (isSpace c))
      (and (!= c "(") (and (!= c ")") (and (!= c "[") (and (!= c "]") (and (!= c "{") (and (!= c "}") (and (!= c "\"") (and (!= c ":") (!= c ";")))))))))))

fn keyAt s: String n: Int64 p: Int64 -> (Pair Int64 Int64)
  (if (or (!= (ch s p) ":") (or (>= (+ p 1) n) (not (isKeyStart (ch s (+ p 1))))))
    (pair -1 -1)
    (let [q (runEnd s n (+ p 1) isWordByte)
          r (runEnd s n q isSpace)]
      (if (or (= q (+ p 1)) (= r q)) (pair -1 -1) (pair q r))))

fn strBodyEnd s: String n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (ch s i) "\"") i)
    ((= (ch s i) "\\") (if (< (+ i 1) n) (strBodyEnd s n (+ i 2)) -1))
    (else (strBodyEnd s n (+ i 1))))

fn stepFrom s: String n: Int64 p: Int64 -> Int64
  (if (= (ch s p) "\"")
    (let [e (strBodyEnd s n (+ p 1))] (if (< e 0) n (+ e 1)))
    (+ p 1))

fn putString kv: (List (Pair String KvVal)) key: String v: String -> (List (Pair String KvVal))
  (if (dictHas kv key)
    (if (and (= key "op") (and (= (dictGet kv "op") (some (kvStr "help"))) (not (dictHas kv "name"))))
      (dictSet kv "name" (kvStr v))
      kv)
    (dictSet kv key (kvStr v)))

fn strPass s: String n: Int64 p: Int64 kv: (List (Pair String KvVal)) -> (List (Pair String KvVal))
  (if (>= p n) kv
    (mt (keyAt s n p)
      ((pair q r)
        (let [e (if (and (>= q 0) (and (< r n) (= (ch s r) "\""))) (strBodyEnd s n (+ r 1)) -1)]
          (if (< e 0)
            (strPass s n (stepFrom s n p) kv)
            (strPass s n (+ e 1) (putString kv (sliceOf s (+ p 1) q) (asnUnescape (sliceOf s (+ r 1) e)))))))))

fn intPass s: String n: Int64 p: Int64 kv: (List (Pair String KvVal)) -> (List (Pair String KvVal))
  (if (>= p n) kv
    (mt (keyAt s n p)
      ((pair q r)
        (let [e (if (>= q 0) (runEnd s n r isDigit) -1)]
          (if (or (< e 0) (or (= e r) (or (>= e n) (not (or (isSpace (ch s e)) (= (ch s e) ")"))))))
            (intPass s n (stepFrom s n p) kv)
            (let [key (sliceOf s (+ p 1) q)]
              (intPass s n e (if (dictHas kv key) kv (dictSet kv key (kvInt (dropZeros (sliceOf s r e) 0)))))))))))

fn isAtomByte c: String -> Bool
  (not (or (isSpace c) (or (= c "(") (or (= c ")") (or (= c "[") (or (= c "]") (= c "\"")))))))

fn dropColons s: String -> String
  (sliceOf s (runEnd s (stringLength s) 0 (fn [c] (= c ":"))) (stringLength s))

fn atomPass s: String n: Int64 p: Int64 kv: (List (Pair String KvVal)) -> (List (Pair String KvVal))
  (if (>= p n) kv
    (mt (keyAt s n p)
      ((pair q r)
        (let [e (if (>= q 0) (runEnd s n r isAtomByte) -1)]
          (if (or (< e 0) (= e r))
            (atomPass s n (stepFrom s n p) kv)
            (let [key (sliceOf s (+ p 1) q)]
              (atomPass s n e (if (or (dictHas kv key) (= key "_head")) kv (dictSet kv key (kvStr (dropColons (sliceOf s r e))))))))))))

fn parseKv form: String -> (List (Pair String KvVal))
  (let [n (stringLength form)
        h (headOf form)
        kv0 (if (= h "") (list) (list (pair "_head" (kvStr h))))]
    (atomPass form n 0 (intPass form n 0 (strPass form n 0 kv0))))

fn isFileOp o: (Option KvVal) -> Bool
  (mt o
    ((some v) (mt v ((kvStr t) (listContains? (list "read" "edit" "write" "check" "test" "fix") t)) ((kvInt _) false)))
    (none false))

fn pathAlias e: (List (Pair String KvVal)) -> (List (Pair String KvVal))
  (if (and (= (dictGet e "type") (some (kvStr "step")))
        (and (not (truthy (dictGet e "file")))
          (and (truthy (dictGet e "path")) (isFileOp (dictGet e "op")))))
    (dictSet e "file" (dictOr e "path"))
    e)

fn evidenceOps nested: (List String) -> (List (List (Pair String KvVal)))
  (fold (fn [acc nf]
          (let [nkv (parseKv nf)]
            (if (dictHas nkv "cmd")
              (listAppend acc (list (list (pair "type" (kvStr "evidence")) (pair "cmd" (dictOr nkv "cmd"))
                                           (pair "exit" (optionOr (dictGet nkv "exit") (kvInt "0"))) (pair "form" (kvStr nf)))))
              acc)))
    (list) nested)

fn nativeOp kv: (List (Pair String KvVal)) head: String form: String -> (List (Pair String KvVal))
  (let [e0 (fold (fn [e p] (mt p ((pair k v) (if (= k "_head") e (dictSet e k v))))) (list (pair "type" (kvStr "step"))) kv)
        e1 (dictSet (dictSet e0 "op" (kvStr head)) "form" (kvStr form))]
    (if (and (= head "help") (and (truthy (dictGet kv "op")) (not (dictHas kv "name"))))
      (dictSet e1 "name" (dictOr kv "op"))
      e1))

fn stepOp kv: (List (Pair String KvVal)) form: String -> (List (Pair String KvVal))
  (fold (fn [e p] (mt p ((pair k v) (if (listContains? (list "_head" "type" "form") k) e (dictSet e k v)))))
    (list (pair "type" (kvStr "step")) (pair "op" (dictOr kv "op")) (pair "form" (kvStr form)))
    kv)

fn formOps form: String -> (List (List (Pair String KvVal)))
  (let [kv (parseKv form)
        head (mt (dictOr kv "_head") ((kvStr t) t) ((kvInt t) t))]
    (cond
      ((= head "step") (list (stepOp kv form)))
      ((= head "evidence") (evidenceOps (parseForms (sliceOf form 1 (stringLength form)))))
      ((or (= head "findings") (= head "finding")) (list (list (pair "type" (kvStr "findings")) (pair "form" (kvStr form)))))
      ((or (= head "done") (= head "escalate")) (list (list (pair "type" (kvStr head)) (pair "form" (kvStr form)))))
      ((or (= head "patch") (= head "txn")) (list (list (pair "type" (kvStr "step")) (pair "op" (kvStr head)) (pair "form" (kvStr form)))))
      ((!= head "") (list (nativeOp kv head form)))
      (else (list))))

fn parseReply reply: String -> (List (List (Pair String KvVal)))
  (let [forms (filter (fn [f] (!= (headOf f) "")) (parseForms reply))]
    (if (listEmpty? forms)
      (list (list (pair "type" (kvStr "raw")) (pair "text" (kvStr reply))))
      (map pathAlias (fold (fn [acc f] (listAppend acc (formOps f))) (list) forms))))

fn firstTruthy xs: (List (Option KvVal)) -> KvVal
  (cond
    ((listEmpty? xs) (kvStr ""))
    ((truthy (firstOf xs)) (optionOr (firstOf xs) (kvStr "")))
    (else (firstTruthy (restOf xs))))

fn fieldVal isInt: Bool v: String -> KvVal
  (if isInt (kvInt v) (kvStr v))

fn withSlice op: (List (Pair String KvVal)) key: (List KvVal) -> (List KvVal)
  (if (or (dictHas op "start") (dictHas op "end"))
    (listAppend key (list (dictOr op "start") (dictOr op "end")))
    key)

fn withGiven op: (List (Pair String KvVal)) key: (List KvVal) names: (List String) -> (List KvVal)
  (listAppend key (fold (fn [acc k] (if (dictHas op k) (listAppend acc (list (kvStr k) (dictOr op k))) acc)) (list) names))

fn evidenceKey op: (List (Pair String KvVal)) mode: String base: String -> (List KvVal)
  (let [name (dictOr op "op")
        g (fn [k] (dictOr op k))]
    (cond
      ((= name (kvStr "read")) (withGiven op (list name (g "file") (g "symbol") (g "from") (g "to") (g "start") (g "end")) (list "anchor")))
      ((or (= name (kvStr "query")) (= name (kvStr "q")))
        (withGiven op (list (kvStr "query") (firstTruthy (list (dictGet op "query") (dictGet op "text")))) (list "in" "limit")))
      ((= name (kvStr "gitDiff"))
        (withSlice op (list name (g "path")
          (if (truthy (some (g "base"))) (g "base") (kvStr (if (or (= mode "scout") (= mode "implement")) base ""))))))
      ((= name (kvStr "gitLog")) (withSlice op (list name (g "path") (g "limit"))))
      ((= name (kvStr "gitShow")) (withSlice op (list name (g "rev") (g "path"))))
      ((= name (kvStr "run")) (list name (g "argv")))
      ((= name (kvStr "observe")) (list name (g "dim") (g "symbol") (g "path") (g "module") (g "spec") (g "id") (g "scope") (g "limit")))
      (else (list name (firstTruthy (list (dictGet op "path") (dictGet op "file") (dictGet op "name")))))))

fn serVal v: KvVal -> String
  (mt v ((kvStr t) (serString t)) ((kvInt t) t))

fn serOps ops: (List (List (Pair String KvVal))) -> String
  (str "(ops"
    (joinAll (map (fn [op] (str " (op" (joinAll (map (fn [p] (mt p ((pair k v) (str " (" k " " (serVal v) ")")))) op)) ")")) ops))
    ")")

fn serKey key: (List KvVal) -> String
  (str "(key" (joinAll (map (fn [v] (str " " (serVal v))) key)) ")")

fn pathParts p: String -> (List String)
  (listReverse
    (fold (fn [acc x]
            (cond
              ((or (= x "") (= x ".")) acc)
              ((= x "..") (if (listEmpty? acc) acc (restOf acc)))
              (else (cons x acc))))
      (list) (stringSplit p "/")))

fn commonLen a: (List String) b: (List String) k: Int64 -> Int64
  (if (or (listEmpty? a) (or (listEmpty? b) (!= (firstOf a) (firstOf b))))
    k
    (commonLen (restOf a) (restOf b) (+ k 1)))

fn relPath path: String root: String -> String
  (let [pp (pathParts path)
        rp (pathParts root)
        i (commonLen pp rp 0)
        rel (listAppend (map (fn [_] "..") (range i (listLength rp))) (optionOr (listSlice pp i (listLength pp)) (list)))]
    (if (listEmpty? rel) "." (joinSep rel "/")))

fn stripLeft s: String test: (fn [String] -> Bool) -> String
  (sliceOf s (runEnd s (stringLength s) 0 test) (stringLength s))

fn stripRightAt s: String j: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (> j 0) (test (ch s (- j 1)))) (stripRightAt s (- j 1) test) j)

fn stripRight s: String test: (fn [String] -> Bool) -> String
  (sliceOf s 0 (stripRightAt s (stringLength s) test))

fn stripBoth s: String test: (fn [String] -> Bool) -> String
  (stripRight (stripLeft s test) test)

fn stripDotSlash s: String -> String
  (cond
    ((= s ".") "")
    ((stringStartsWith? s "./") (stripDotSlash (optionOr (stringSlice s 2 (stringLength s)) "")))
    (else s))

enum GlobToken
  (globStar)
  (globAny)
  (globLit c: String)
  (globSet negated: Bool ranges: (List (Pair String String)))

fn setRanges cs: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (cond
    ((listEmpty? cs) acc)
    ((and (>= (listLength cs) 3) (= (optionOr (listGet cs 1) "") "-"))
      (setRanges (optionOr (listSlice cs 3 (listLength cs)) (list))
        (cons (pair (firstOf cs) (optionOr (listGet cs 2) "")) acc)))
    (else (setRanges (restOf cs) (cons (pair (firstOf cs) (firstOf cs)) acc))))

fn setClose cs: (List String) j: Int64 -> Int64
  (cond
    ((>= j (listLength cs)) -1)
    ((= (optionOr (listGet cs j) "") "]") j)
    (else (setClose cs (+ j 1))))

fn globTokens cs: (List String) i: Int64 acc: (List GlobToken) -> (List GlobToken)
  (if (>= i (listLength cs))
    (listReverse acc)
    (let [c (optionOr (listGet cs i) "")]
      (cond
        ((= c "*") (globTokens cs (+ i 1) (if (and (not (listEmpty? acc)) (= (firstOf acc) (globStar))) acc (cons (globStar) acc))))
        ((= c "?") (globTokens cs (+ i 1) (cons (globAny) acc)))
        ((= c "[")
          (let [j0 (+ i 1)
                neg (= (optionOr (listGet cs j0) "") "!")
                j1 (if neg (+ j0 1) j0)
                j2 (if (= (optionOr (listGet cs j1) "") "]") (+ j1 1) j1)
                k (setClose cs j2)]
            (if (< k 0)
              (globTokens cs (+ i 1) (cons (globLit "[") acc))
              (globTokens cs (+ k 1)
                (cons (globSet neg (setRanges (optionOr (listSlice cs j1 k) (list)) (list))) acc)))))
        (else (globTokens cs (+ i 1) (cons (globLit c) acc))))))

fn inRanges c: String rs: (List (Pair String String)) -> Bool
  (cond
    ((listEmpty? rs) false)
    (else (mt (firstOf rs) ((pair lo hi) (if (and (>= c lo) (<= c hi)) true (inRanges c (restOf rs)))))))

fn globMatch ts: (List GlobToken) cs: (List String) -> Bool
  (if (listEmpty? ts)
    (listEmpty? cs)
    (mt (firstOf ts)
      ((globStar) (if (globMatch (restOf ts) cs) true (if (listEmpty? cs) false (globMatch ts (restOf cs)))))
      ((globAny) (if (listEmpty? cs) false (globMatch (restOf ts) (restOf cs))))
      ((globLit c) (if (and (not (listEmpty? cs)) (= (firstOf cs) c)) (globMatch (restOf ts) (restOf cs)) false))
      ((globSet neg rs)
        (if (and (not (listEmpty? cs)) (!= (inRanges (firstOf cs) rs) neg)) (globMatch (restOf ts) (restOf cs)) false))))

fn ownsEntry rel: String pattern: String -> Bool
  (let [pat (stripDotSlash (stripBoth (stripBoth (stripBoth pattern isSpace) (fn [c] (= c "\""))) (fn [c] (= c "'"))))]
    (or (= rel pat)
      (or (stringStartsWith? rel (str (stripRight pat (fn [c] (= c "/"))) "/"))
        (globMatch (globTokens (stringChars pat) 0 (list)) (stringChars rel)))))

; (:m :tags (owns))
fn checkOwns path: String owns: (List String) root: String -> Bool
  (if (listEmpty? owns)
    false
    (let [rel (relPath (if (stringStartsWith? path "/") path (str root "/" path)) root)]
      (cond
        ((or (= rel "..") (stringStartsWith? rel "../")) false)
        ((= rel ".") (fold (fn [hit p] (or hit (ownsEntry "" p))) false owns))
        (else (fold (fn [hit p] (or hit (ownsEntry rel p))) false owns)))))

fn spanLess x: (Pair Int64 Int64) y: (Pair Int64 Int64) -> Bool
  (mt x ((pair a b) (mt y ((pair c d) (or (< a c) (and (= a c) (< b d)))))))

fn insertSpan s: (Pair Int64 Int64) xs: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (cond
    ((listEmpty? xs) (list s))
    ((spanLess (firstOf xs) s) (cons (firstOf xs) (insertSpan s (restOf xs))))
    (else (cons s xs)))

fn mergeSpans spans: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (listReverse
    (fold (fn [out s]
            (mt s ((pair a b)
              (if (listEmpty? out)
                (list s)
                (mt (firstOf out) ((pair la lb)
                  (if (<= a (+ lb 1)) (cons (pair la (max lb b)) (restOf out)) (cons s out))))))))
      (list) (fold (fn [acc s] (insertSpan s acc)) (list) spans)))

fn coverageOf coverage: (List (Pair String (List (Pair Int64 Int64)))) path: String -> (List (Pair Int64 Int64))
  (cond
    ((listEmpty? coverage) (list))
    (else (mt (firstOf coverage) ((pair p sp) (if (= p path) sp (coverageOf (restOf coverage) path))))))

fn spanSeen coverage: (List (Pair String (List (Pair Int64 Int64)))) path: String a: Int64 b: Int64 -> Bool
  (fold (fn [hit s] (or hit (mt s ((pair x y) (and (<= x a) (<= b y)))))) false (coverageOf coverage path))

fn recordRead coverage: (List (Pair String (List (Pair Int64 Int64)))) path: String a: Int64 b: Int64 -> (Pair Bool (List (Pair String (List (Pair Int64 Int64)))))
  (if (spanSeen coverage path a b)
    (pair false coverage)
    (let [merged (mergeSpans (listAppend (coverageOf coverage path) (list (pair a b))))]
      (pair true
        (if (listEmpty? (filter (fn [e] (mt e ((pair p _) (= p path)))) coverage))
          (listAppend coverage (list (pair path merged)))
          (map (fn [e] (mt e ((pair p _) (if (= p path) (pair p merged) e)))) coverage)))))

fn serSpan s: (Pair Int64 Int64) -> String
  (mt s ((pair a b) (str "(" (stringFromInt64 a) " " (stringFromInt64 b) ")")))

fn serSpans spans: (List (Pair Int64 Int64)) -> String
  (str "(spans" (joinAll (map (fn [s] (str " " (serSpan s))) spans)) ")")

fn renderSeen coverage: (List (Pair String (List (Pair Int64 Int64)))) -> String
  (if (listEmpty? coverage)
    ""
    (str "(:seen "
      (joinSep (map (fn [e] (mt e ((pair p sp) (str "(\"" (escapeAsn p) "\" " (joinSep (map serSpan sp) " ") ")")))) coverage) " ")
      ")"))

fn makeTurn turn: String sent: String got: String -> Turn
  (turnOf turn sent got)

fn charCount s: String n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) k)
    ((isContinuation (ch s i)) (charCount s n (+ i 1) k))
    (else (charCount s n (+ i 1) (+ k 1))))

fn charLen s: String -> Int64
  (charCount s (stringLength s) 0 0)

fn charIndex s: String n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((isContinuation (ch s i)) (charIndex s n (+ i 1) k))
    ((= k 0) i)
    (else (charIndex s n (+ i 1) (- k 1))))

fn charPrefix s: String k: Int64 -> String
  (sliceOf s 0 (charIndex s (stringLength s) 0 k))

fn litAt s: String n: Int64 p: Int64 lit: String -> Bool
  (let [k (stringLength lit)]
    (and (<= (+ p k) n) (= (sliceOf s p (+ p k)) lit)))

fn cutReads s: String n: Int64 p: Int64 acc: (List String) -> (List String)
  (if (>= p n)
    (listReverse acc)
    (let [pre ":op \"read\" :status :ok :file \""]
      (if (not (litAt s n p pre))
        (cutReads s n (+ p 1) acc)
        (let [b (+ p (stringLength pre))
              e (strBodyEnd s n b)
              d1 (+ e 10)
              d1e (if (and (>= e 0) (litAt s n (+ e 1) " :lines (")) (runEnd s n d1 isDigit) -1)
              d2e (if (and (> d1e d1) (litAt s n d1e " ")) (runEnd s n (+ d1e 1) isDigit) -1)]
          (if (and (> d2e (+ d1e 1)) (litAt s n d2e ")"))
            (cutReads s n (+ d2e 1)
              (cons (str "\"" (sliceOf s b e) "\" :start " (sliceOf s d1 d1e) " :end " (sliceOf s (+ d1e 1) d2e)) acc))
            (cutReads s n (+ p 1) acc))))))

fn formsOnly s: String n: Int64 i: Int64 seen: Bool -> Bool
  (cond
    ((>= i n) seen)
    ((isSpace (ch s i)) (formsOnly s n (+ i 1) seen))
    ((= (ch s i) "(")
      (mt (formEnd s n (+ i 1) 1 false false)
        ((pair j d) (if (= d 0) (formsOnly s n j true) false))))
    (else false))

fn trimSpace s: String -> String
  (let [n (stringLength s)
        a (runEnd s n 0 isSpace)
        b (spaceStart s a n)]
    (sliceOf s a b))

fn spaceStart s: String a: Int64 b: Int64 -> Int64
  (if (and (> b a) (isSpace (ch s (- b 1)))) (spaceStart s a (- b 1)) b)

fn nestText s: String -> String
  (let [t (trimSpace s)]
    (if (formsOnly t (stringLength t) 0 false) t (str "\"" (escapeAsn s) "\"")))

fn turnForm turn: String sent: String got: String -> String
  (str "(:turn " turn " :sent " (nestText sent) " :got " (nestText got) ")")

; (:m :adopted NormativeAndEmpiricalAreNotMixed)
fn cutTurn h: Turn -> String
  (mt h ((turnOf turn sent got)
    (let [sent2 (if (> (charLen sent) 300) (str (charPrefix sent 300) " ...") sent)
          got2 (if (> (charLen got) 300)
                 (let [reads (cutReads got (stringLength got) 0 (list))
                       again (if (listEmpty? reads) "its lines are in your note if you kept them" (str "cut reads " (joinSep reads "; ")))]
                   (str (charPrefix got 300) " ... [" (stringFromInt64 (charLen got)) " chars, " again "]"))
                 got)]
      (turnForm turn sent2 got2))))

fn wholeTurn h: Turn -> String
  (mt h ((turnOf turn sent got) (turnForm turn sent got)))

fn turnId h: Turn -> String
  (mt h ((turnOf turn _ _) turn))

fn at xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn sumRange xs: (List Int64) a: Int64 b: Int64 -> Int64
  (listSum (optionOr (listSlice xs a b) (list)))

fn elidedLine d: Int64 -> String
  (str "(:elided " (stringFromInt64 d) ")")

fn windowSize cl: (List Int64) wl: (List Int64) m: Int64 c: Int64 d: Int64 lastLen: Int64 -> Int64
  (+ (+ (if (> d 0) (+ (stringLength (elidedLine d)) 1) 0) (sumRange cl d c))
     (+ (sumRange wl c m) lastLen))

fn compactCut cl: (List Int64) wl: (List Int64) m: Int64 c: Int64 d: Int64 lastLen: Int64 target: Int64 -> Int64
  (if (or (>= c m) (<= (windowSize cl wl m c d lastLen) target)) c (compactCut cl wl m (+ c 1) d lastLen target))

fn compactDrop cl: (List Int64) wl: (List Int64) m: Int64 c: Int64 d: Int64 lastLen: Int64 target: Int64 -> Int64
  (if (or (>= d c) (<= (windowSize cl wl m c d lastLen) target)) d (compactDrop cl wl m c (+ d 1) lastLen target))

enum Window
  (windowOf text: String last: String cut: Int64 dropped: Int64 used: Int64 whole: (List String))

; (:m :tags (window cache))
fn renderWindow history: (List Turn) budget: Int64 cut0: Int64 drop0: Int64 pinned: (List String) -> Window
  (if (listEmpty? history)
    (windowOf "" "" 0 0 0 (list))
    (let [n (listLength history)
          m (- n 1)
          older (optionOr (listSlice history 0 m) (list))
          newest (firstOf (optionOr (listSlice history m n) (list)))
          whole (map wholeTurn older)
          cut (map (fn [h] (if (memberOf (turnId h) pinned) (wholeTurn h) (cutTurn h))) older)
          wl (map (fn [s] (+ (stringLength s) 1)) whole)
          cl (map (fn [s] (+ (stringLength s) 1)) cut)
          last (wholeTurn newest)
          lastLen (stringLength last)
          d0 (min (max drop0 0) m)
          c0 (min (max cut0 d0) m)
          fits (<= (windowSize cl wl m c0 d0 lastLen) budget)
          c (if fits c0 (compactCut cl wl m c0 d0 lastLen (/ budget 2)))
          d (if fits d0 (compactDrop cl wl m c d0 lastLen budget))
          lines (listAppend (listAppend (if (> d 0) (list (elidedLine d)) (list)) (optionOr (listSlice cut d c) (list)))
                  (optionOr (listSlice whole c m) (list)))]
      (windowOf (joinAll (map (fn [l] (str l "\n")) lines)) last c d (windowSize cl wl m c d lastLen)
        (listAppend (listAppend (filter (fn [t] (memberOf t pinned)) (map turnId (optionOr (listSlice older d c) (list))))
                                (map turnId (optionOr (listSlice older c m) (list))))
          (list (turnId newest))))))

fn renderTranscript history: (List Turn) budget: Int64 -> String
  (mt (renderWindow history budget 0 0 (list)) ((windowOf text last _ _ _ _) (str text last)))

fn memberOf x: String xs: (List String) -> Bool
  (listAny? (fn [y] (= x y)) xs)

fn progName w: String -> String
  (optionOr (listHead (listReverse (stringSplit w "/"))) w)

fn bodyFlags -> (List String)
  (list "-d" "--data" "--data-binary" "--data-raw" "--data-urlencode" "--json" "-F" "--form" "-T" "--upload-file"
    "--post-data" "--post-file" "--body-data" "--body-file")

fn writeMethods -> (List String)
  (list "POST" "PUT" "DELETE" "PATCH")

fn suffixFrom a: String k: Int64 -> String
  (sliceOf a k (stringLength a))

fn sendsBody args: (List String) -> Bool
  (if (listEmpty? args)
    false
    (let [a (firstOf args)
          rest (restOf args)
          key (optionOr (listHead (stringSplit a "=")) a)]
      (cond
        ((or (memberOf a (bodyFlags)) (memberOf key (bodyFlags))) true)
        ((and (memberOf a (list "-X" "--request" "--method")) (and (not (listEmpty? rest)) (memberOf (stringUpper (firstOf rest)) (writeMethods)))) true)
        ((and (stringStartsWith? a "-X") (memberOf (stringUpper (suffixFrom a 2)) (writeMethods))) true)
        ((and (stringStartsWith? a "--method=") (memberOf (stringUpper (suffixFrom a 9)) (writeMethods))) true)
        (else (sendsBody rest)))))

fn segmentOutward words: (List String) owns: (List String) root: String -> String
  (if (listEmpty? words)
    ""
    (let [prog (progName (firstOf words))
          args (restOf words)
          plain (filter (fn [a] (not (stringStartsWith? a "-"))) args)]
      (cond
        ((and (= prog "git") (memberOf "push" plain)) "it pushes")
        ((and (memberOf prog (list "npm" "pnpm" "yarn" "cargo" "pip" "pip3" "poetry" "gem")) (memberOf "publish" plain)) "it publishes")
        ((and (= prog "twine") (memberOf "upload" plain)) "it publishes")
        ((and (or (= prog "curl") (= prog "wget")) (sendsBody args)) (str prog " sends a request body or method"))
        ((or (= prog "rm") (= prog "mv"))
          (let [out (filter (fn [a] (not (checkOwns a owns root))) plain)]
            (if (listEmpty? out) "" (str prog " of " (firstOf out) ", outside :owns"))))
        (else ""))))

fn runSeparators -> (List String)
  (list ";" "&&" "||" "|" "&" "(" ")")

fn commandSegments words: (List String) -> (List (List String))
  (mt (fold (fn [st w]
              (mt st ((pair done cur)
                (if (memberOf w (runSeparators))
                  (pair (cons (listReverse cur) done) (list))
                  (pair done (cons w cur))))))
        (pair (list) (list)) words)
    ((pair done cur) (listReverse (cons (listReverse cur) done))))

fn readOnlyGit -> (List String)
  (list "status" "log" "diff" "show" "grep" "ls-files" "blame")

fn readOnlySegment words: (List String) -> Bool
  (if (listEmpty? words)
    true
    (let [prog (progName (firstOf words))
          args (restOf words)]
      (cond
        ((= prog "find") (not (listAny? (fn [a] (memberOf a (list "-delete" "-exec" "-execdir" "-ok" "-okdir" "-fprint" "-fprintf" "-fls"))) args)))
        ((= prog "git") (listAny? (fn [a] (memberOf a (readOnlyGit))) (filter (fn [a] (not (stringStartsWith? a "-"))) (optionOr (listSlice args 0 1) (list)))))
        (else (memberOf prog (list "grep" "rg" "ls" "cat" "head" "tail" "wc" "pwd" "file" "stat" "du" "tree" "diff" "cmp"))))))

; (:m :tags (signals))
fn runReadOnly words: (List String) -> Bool
  (and (not (listAny? (fn [w] (memberOf w (list ">" ">>" ">&" "&>" "<>" ">|"))) words))
       (listAll? readOnlySegment (commandSegments words)))

; (:m :tags (harness))
fn harnessPath p: String root: String -> Bool
  (let [parts (pathParts (if (stringStartsWith? p "/") (relPath p root) p))]
    (and (>= (listLength parts) 2) (and (= (firstOf parts) ".asl") (= (firstOf (restOf parts)) "run"))))

; (:m :tags (harness))
fn hiddenPath p: String dirs: (List String) root: String -> Bool
  (let [parts (pathParts (if (stringStartsWith? p "/") p (str root "/" p)))]
    (listAny? (fn [d] (let [dp (pathParts d)]
                        (and (> (listLength dp) 0)
                             (and (>= (listLength parts) (listLength dp))
                                  (= (optionOr (listSlice parts 0 (listLength dp)) (list)) dp)))))
      (filter (fn [d] (not (= d ""))) dirs)))

; (:m :tags (owns))
fn runOutward words: (List String) owns: (List String) root: String -> String
  (if (listAny? (fn [w] (or (stringContains? w "git push") (stringContains? w " publish"))) words)
    "it pushes or publishes"
    (fold (fn [acc seg] (if (= acc "") (segmentOutward seg owns root) acc)) "" (commandSegments words)))

; (:m :tags (owns))
fn changePlan paths: (List String) owns: (List String) root: String -> (List String)
  (map (fn [p] (if (checkOwns p owns root) "keep" "restore")) paths)

fn levRow ca: String b: String j: Int64 n: Int64 prevRest: (List Int64) diag: Int64 left: Int64 acc: (List Int64) -> (List Int64)
  (if (> j n)
    (listReverse acc)
    (let [up (firstOf prevRest)
          v (min (+ up 1) (min (+ left 1) (+ diag (if (= ca (ch b (- j 1))) 0 1))))]
      (levRow ca b (+ j 1) n (restOf prevRest) up v (cons v acc))))

fn levRows a: String b: String i: Int64 m: Int64 n: Int64 prev: (List Int64) -> Int64
  (if (> i m)
    (optionOr (listGet prev n) 0)
    (levRows a b (+ i 1) m n (levRow (ch a (- i 1)) b 1 n (restOf prev) (firstOf prev) i (list i))))

fn editDistance a: String b: String -> Int64
  (levRows a b 1 (stringLength a) (stringLength b) (range 0 (+ (stringLength b) 1)))

fn opAlias name: String -> String
  (cond
    ((or (= name "append") (= name "create")) "write")
    ((or (= name "modify") (= name "replace")) "edit")
    ((or (= name "show") (= name "cat")) "read")
    ((or (= name "find") (= name "grep")) "query")
    ((= name "run") "test")
    (else ""))

fn closest u: String accepted: (List String) best: String bestD: Int64 -> (Pair String Int64)
  (if (listEmpty? accepted)
    (pair best bestD)
    (let [d (editDistance u (stringLower (firstOf accepted)))]
      (if (< d bestD)
        (closest u (restOf accepted) (firstOf accepted) d)
        (closest u (restOf accepted) best bestD))))

fn nearestOp unknown: String accepted: (List String) -> String
  (let [u (stringLower (stringTrim unknown))
        alias (opAlias u)]
    (if (and (!= alias "") (listContains? accepted alias))
      alias
      (mt (closest u accepted "" 1000000)
        ((pair best d)
          (if (and (!= best "") (or (<= d 2) (<= (* 3 d) (stringLength u)))) best "")))))

fn terminalForms mode: String -> (List String)
  (if (= mode "scout")
    (list "(:findings (:claim s :file f))" "(:escalate :reason s)")
    (list "(:done)" "(:escalate :reason s)"))

fn isDataOp op: (List (Pair String KvVal)) declared: (List String) -> Bool
  (let [name (mt (dictOr op "op") ((kvStr t) t) ((kvInt t) t))
        form (mt (dictOr op "form") ((kvStr t) t) ((kvInt t) t))
        h (headOf form)]
    (or
      (and (= (dictGet op "type") (some (kvStr "findings")))
        (not (listContains? declared h)))
      (and (= (dictGet op "type") (some (kvStr "step")))
        (and (= h name)
          (and (not (listContains? declared name))
            (not (listContains? (list "step" "txn" "patch") name)))))))

fn dataFindingForm op: (List (Pair String KvVal)) -> String
  (let [form (mt (dictOr op "form") ((kvStr t) t) ((kvInt t) t))]
    (if (= (dictGet op "type") (some (kvStr "findings")))
      form
      (str "(:findings " form ")")))

fn dataFindings reply: String declared: (List String) -> (List String)
  (let [ops (parseReply reply)]
    (if (fold (fn [acc op] (and acc (isDataOp op declared))) true ops)
      (map dataFindingForm ops)
      (list)))

fn withoutForm op: (List (Pair String KvVal)) -> (List (Pair String KvVal))
  (filter (fn [p] (mt p ((pair k _) (!= k "form")))) op)

fn uniqueSteps ops: (List (List (Pair String KvVal))) -> (List (List (Pair String KvVal)))
  (mt (fold (fn [st op]
              (mt st ((pair seen out)
                (let [k (withoutForm op)]
                  (if (and (= (dictGet op "type") (some (kvStr "step"))) (listContains? seen k))
                    st
                    (pair (cons k seen) (cons op out)))))))
        (pair (list) (list)) ops)
    ((pair _ out) (listReverse out)))

fn intOf o: (Option KvVal) -> Int64
  (mt o
    ((some v) (mt v ((kvInt t) (optionOr (stringToInt64 t) -1)) ((kvStr t) -1)))
    (none -1))

fn gateCounts out: String -> (Pair Int64 Int64)
  (fold (fn [acc line]
          (let [t (stringTrim line)
                kv (parseKv t)
                n (intOf (dictGet kv "asserts"))
                m (intOf (dictGet kv "failed"))]
            (if (and (= (headOf t) "gate") (and (>= n 0) (>= m 0))) (pair n m) acc)))
    (pair -1 -1) (stringSplit out "\n"))

fn missingText s: String -> Bool
  (or (stringContains? s "No such file") (or (stringContains? s "not found") (or (stringContains? s "can't open") (stringContains? s "No module named"))))

; (:m :ref gates)
fn gateVerdict reverted: Bool code: Int64 out: String err: String -> String
  (mt (gateCounts out)
    ((pair n m)
      (cond
        ((and (not reverted) (< n 0)) (if (= code 0) "asserted" "vacuous"))
        ((not reverted) (if (and (> n 0) (= m 0)) "asserted" "vacuous"))
        ((> m 0) "failsOnRevert")
        ((and (< n 0) (and (!= code 0) (not (or (= code 126) (or (= code 127) (or (missingText err) (missingText out))))))) "failsOnRevert")
        ((or (= code 126) (or (= code 127) (or (missingText err) (missingText out)))) "missingOnRevert")
        ((= code 0) "passesOnRevert")
        (else "vacuous"))))

fn firstString s: String -> (Pair Bool String)
  (let [n (stringLength s)
        q (runEnd s n 0 (fn [c] (!= c "\"")))
        e (if (< q n) (strBodyEnd s n (+ q 1)) -1)]
    (if (< e 0) (pair false "") (pair true (asnUnescape (sliceOf s (+ q 1) e)))))

fn noteText form: String -> (Pair Bool String)
  (mt (dictGet (parseKv form) "text")
    ((some v) (mt v ((kvStr t) (pair true t)) ((kvInt t) (pair true t))))
    (none (if (= (headOf form) "note") (firstString form) (pair false ""))))

; (:m :tags (journal))
fn noteStep form: String cap: Int64 -> String
  (mt (noteText form)
    ((pair has t)
      (let [k (charLen t)
            status (cond ((not has) "missing") ((> k cap) "rejected") (else "ok"))
            slot (if (= k 0) "" (str "(:note \"" (escapeAsn t) "\")"))]
        (str "(note " status " " (stringFromInt64 k) " " (serString t) " " (serString slot) ")"))))
