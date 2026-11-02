(module asl/agentLoop/txn
  :x [RVal AslRun TxnStep TxnPrep AbortAid WidenItem Effect FileText
      execTxn! txnPrepare txnFinish! serReceipt serValue balanceAid txnRefusal abortAid! abortAidOn applySteps stepsOf
      intelSubop widenWanted widenPick widenForm widenToSymbol! insideRoot normPath parseEffects loadEffects! checkEffect readText! splitLines outlineItems stripRightAt
      langForPath tryRepairText! orderSubs moduleHints moduleOf importsOf expectedModule txnSubs]
  :i [(asl/agentLoop/core :a c)
      (asl/agentLoop/diff :a diff)
      (asl-forms/repair :a rep)
      (asl-forms/heal :a heal)])

enum RVal
  (rStr text: String)
  (rInt n: Int64)
  (rBool b: Bool)
  (rList xs: (List String))
  (rNone)

enum AslRun
  (aslRun exit: Int64 out: String err: String)

enum TxnStep
  (txnStep op: String file: String kv: (List (Pair String c/KvVal)))

enum TxnPrep
  (prepDone receipt: (List (Pair String RVal)))
  (prepRun owns: (List String) targets: (List String) steps: (List TxnStep) form: String)

enum AbortAid
  (abortAidOf line: Int64 arrived: String hint: String)

enum WidenItem
  (widenItem start: Int64 end: Int64 name: String kind: String)

enum Effect
  (effectAllowed)
  (effectUndeclared)
  (effectConfirm)

enum FileText
  (fileAbsent)
  (fileText text: String)
  (fileFailed why: String)

enum BalState
  (balGo inStr: Bool stack: (List (Pair String Int64)) start: Int64 head: String)
  (balStop msg: String)

fn ch s: String i: Int64 -> String
  (if (and (>= i 0) (< i (stringLength s))) (c/sliceOf s i (+ i 1)) "")

fn tailFrom s: String i: Int64 -> String
  (c/sliceOf s (min i (stringLength s)) (stringLength s))

fn isDigit c: String -> Bool
  (and (>= c "0") (<= c "9"))

fn isWord c: String -> Bool
  (or (isDigit c)
    (or (and (>= c "a") (<= c "z"))
      (or (and (>= c "A") (<= c "Z"))
        (or (= c "_") (>= c (c/sliceOf "À" 1 2))))))

fn isSpace c: String -> Bool
  (or (= c " ") (or (and (>= c "\t") (<= c "\r")) (and (>= c "\u001c") (<= c "\u001f"))))

fn isCont c: String -> Bool
  (and (>= c (c/sliceOf "À" 1 2)) (<= c (c/sliceOf "¿" 1 2)))

fn runEnd s: String n: Int64 i: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (< i n) (test (ch s i))) (runEnd s n (+ i 1) test) i)

fn cpCountLoop s: String n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) k)
    ((isCont (ch s i)) (cpCountLoop s n (+ i 1) k))
    (else (cpCountLoop s n (+ i 1) (+ k 1))))

fn cpCount s: String -> Int64
  (cpCountLoop s (stringLength s) 0 0)

fn cpIndex s: String n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((isCont (ch s i)) (cpIndex s n (+ i 1) k))
    ((= k 0) i)
    (else (cpIndex s n (+ i 1) (- k 1))))

fn cpPrefix s: String k: Int64 -> String
  (c/sliceOf s 0 (cpIndex s (stringLength s) 0 k))

fn cpSuffix s: String k: Int64 -> String
  (let [total (cpCount s)]
    (if (<= total k) s (tailFrom s (cpIndex s (stringLength s) 0 (- total k)))))

fn stripRightAt s: String j: Int64 -> Int64
  (if (and (> j 0) (isSpace (ch s (- j 1)))) (stripRightAt s (- j 1)) j)

fn pyStrip s: String -> String
  (let [n (stringLength s)
        i (runEnd s n 0 isSpace)]
    (c/sliceOf s i (max i (stripRightAt s n))))

fn trimChar s: String t: String -> String
  (let [n (stringLength s)
        i (runEnd s n 0 (fn [x] (= x t)))
        j (stripRightWith s n (fn [x] (= x t)))]
    (c/sliceOf s i (max i j)))

fn stripRightWith s: String j: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (> j 0) (test (ch s (- j 1)))) (stripRightWith s (- j 1) test) j)

fn litAt s: String p: Int64 lit: String -> Bool
  (= (c/sliceOf s p (min (stringLength s) (+ p (stringLength lit)))) lit)

fn dropZeros s: String -> String
  (let [i (runEnd s (stringLength s) 0 (fn [x] (= x "0")))]
    (if (>= i (stringLength s)) "0" (tailFrom s i)))

fn kvText v: c/KvVal -> String
  (match v ((c/kvStr t) t) ((c/kvInt t) t))

fn kvGet kv: (List (Pair String c/KvVal)) key: String -> String
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (kvText (pairSecond p)))
    (none ""))

fn kvIsInt kv: (List (Pair String c/KvVal)) key: String -> Bool
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (match (pairSecond p) ((c/kvInt _) true) ((c/kvStr _) false)))
    (none false))

fn dedup xs: (List String) -> (List String)
  (listReverse (fold (fn [acc x] (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn quotedEnd s: String n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (ch s j) "\"") j)
    ((= (ch s j) "\\") (if (and (< (+ j 1) n) (!= (ch s (+ j 1)) "\n")) (quotedEnd s n (+ j 2)) -1))
    (else (quotedEnd s n (+ j 1))))

fn serValue v: RVal -> String
  (match v
    ((rStr t) (c/serString t))
    ((rInt k) (stringFromInt64 k))
    ((rBool b) (if b "true" "false"))
    ((rList xs) (str "(list" (c/joinAll (map (fn [x] (str " " (c/serString x))) xs)) ")"))
    ((rNone) "null"))

fn serReceipt r: (List (Pair String RVal)) -> String
  (str "(receipt" (c/joinAll (map (fn [p] (str " (" (pairFirst p) " " (serValue (pairSecond p)) ")")) r)) ")")

fn lineDigits s: String n: Int64 p: Int64 -> String
  (cond
    ((> (+ p 4) n) "")
    ((and (litAt s p "line") (or (= p 0) (not (isWord (ch s (- p 1))))))
      (let [r (runEnd s n (+ p 4) isSpace)
            e (runEnd s n r isDigit)]
        (if (and (> r (+ p 4)) (> e r)) (c/sliceOf s r e) (lineDigits s n (+ p 1)))))
    (else (lineDigits s n (+ p 1))))

fn errorCodeAt s: String n: Int64 p: Int64 -> String
  (cond
    ((>= p n) "")
    ((litAt s p ":error-code")
      (let [r (runEnd s n (+ p 11) isSpace)
            q (if (and (< r n) (= (ch s r) "\"")) (+ r 1) r)
            k (if (and (< q n) (= (ch s q) ":")) (+ q 1) q)
            e (runEnd s n k isWord)]
        (if (and (> r (+ p 11)) (> e k)) (c/sliceOf s k e) (errorCodeAt s n (+ p 1)))))
    (else (errorCodeAt s n (+ p 1))))

fn errorCodeIn s: String -> String
  (errorCodeAt s (stringLength s) 0)

fn errorTagAt s: String n: Int64 p: Int64 -> String
  (cond
    ((>= p n) "")
    ((litAt s p ":error")
      (let [r (runEnd s n (+ p 6) isSpace)
            k (if (and (< r n) (= (ch s r) ":")) (+ r 1) r)
            e (if (litAt s k "ERR_") (runEnd s n (+ k 4) isWord) k)]
        (if (and (> r (+ p 6)) (> e (+ k 4))) (c/sliceOf s k e) (errorTagAt s n (+ p 1)))))
    (else (errorTagAt s n (+ p 1))))

fn messageAt s: String n: Int64 p: Int64 -> (Option String)
  (cond
    ((>= p n) none)
    ((litAt s p ":message")
      (let [r (runEnd s n (+ p 8) isSpace)
            e (if (and (> r (+ p 8)) (and (< r n) (= (ch s r) "\""))) (quotedEnd s n (+ r 1)) -1)]
        (if (>= e 0) (some (c/sliceOf s (+ r 1) e)) (messageAt s n (+ p 1)))))
    (else (messageAt s n (+ p 1))))

fn messageIn s: String -> (Option String)
  (messageAt s (stringLength s) 0)

fn syntaxMessageAt s: String n: Int64 p: Int64 -> (Option String)
  (cond
    ((>= p n) none)
    ((litAt s p ":syntaxMessage")
      (let [r (runEnd s n (+ p 14) isSpace)
            e (if (and (> r (+ p 14)) (and (< r n) (= (ch s r) "\""))) (quotedEnd s n (+ r 1)) -1)]
        (if (>= e 0) (some (c/sliceOf s (+ r 1) e)) (syntaxMessageAt s n (+ p 1)))))
    (else (syntaxMessageAt s n (+ p 1))))

fn digitsAfter s: String n: Int64 p: Int64 lit: String -> String
  (cond
    ((>= p n) "")
    ((litAt s p lit)
      (let [b (+ p (stringLength lit))
            e (runEnd s n b isDigit)]
        (if (> e b) (c/sliceOf s b e) (digitsAfter s n (+ p 1) lit))))
    (else (digitsAfter s n (+ p 1) lit)))

fn newlinesBefore s: String at: String -> Int64
  (let [k (optionOr (stringToInt64 (dropZeros at)) (stringLength s))
        cut (c/sliceOf s 0 (min k (stringLength s)))]
    (stringCountChar cut "\n"))

fn txnRefusal stdout: String stderr: String fallback: String content: (Option String) -> (Pair String String)
  (let [n (stringLength stdout)
        code (errorCodeIn stdout)
        tag (if (= code "") (errorTagAt stdout n 0) code)
        err (if (= tag "") fallback tag)
        bal0 (digitsAfter stdout n 0 ":balanced false :byte ")
        bal (if (and (= bal0 "") (or (stringContains? stdout ":ERR_UNBALANCED") (stringContains? stdout "unclosed delimiter")))
              (digitsAfter stdout n 0 ":byte ")
              bal0)]
    (if (!= bal "")
      (let [at (dropZeros bal)
            where (match content
                    ((some t) (str "byte " at " (line " (stringFromInt64 (+ (newlinesBefore t bal) 1)) " of :content)"))
                    (none (str "byte " at " of the file after the change")))]
        (pair err (str "refused: the delimiters ( ) [ ] { } and quotes do not balance at " where "; nothing was written")))
      (match (messageIn stdout)
        ((some m) (pair err m))
        (none
          (match (syntaxMessageAt stdout n 0)
            ((some sm) (pair err sm))
            (none
              (let [t (cpSuffix (pyStrip stderr) 300)]
                (pair err (if (!= t "") t (str fallback ": " (cpSuffix (pyStrip stdout) 300)))))))))))

fn plural k: Int64 -> String
  (if (> k 1) "s" "")

fn itemWhere start: Int64 head: String -> String
  (str "its top-level form starts at line " (stringFromInt64 start) " (" head ")")

fn bottomOf stack: (List (Pair String Int64)) -> (Pair String Int64)
  (optionOr (listLast stack) (pair "(" 0))

fn neverClosed stack: (List (Pair String Int64)) before: String start: Int64 head: String -> String
  (let [b (bottomOf stack)
        k (listLength stack)]
    (str "line " (stringFromInt64 (pairSecond b)) " opens a " (pairFirst b) " that is never closed: " (stringFromInt64 k) " closer" (plural k)
      " missing" before "; " (itemWhere start head)))

fn openerOf c: String -> String
  (cond ((= c ")") "(") ((= c "]") "[") (else "{"))

fn itemHead raw: String -> String
  (cpPrefix (pyStrip raw) 40)

fn balChars raw: String n: Int64 i: Int64 ln: Int64 st: BalState -> BalState
  (match st
    ((balStop m) st)
    ((balGo inStr stack start head)
      (if (>= i n)
        st
        (let [x (ch raw i)]
          (cond
            (inStr
              (cond
                ((= x "\\") (balChars raw n (+ i 2) ln st))
                ((= x "\"") (balChars raw n (+ i 1) ln (balGo false stack start head)))
                (else (balChars raw n (+ i 1) ln st))))
            ((= x ";") st)
            ((= x "\"") (balChars raw n (+ i 1) ln (balGo true stack start head)))
            ((or (= x "(") (or (= x "[") (= x "{")))
              (let [fresh (and (listEmpty? stack) (= start 0))]
                (balChars raw n (+ i 1) ln
                  (balGo false (cons (pair x ln) stack) (if fresh ln start) (if fresh (itemHead raw) head)))))
            ((or (= x ")") (or (= x "]") (= x "}")))
              (if (and (not (listEmpty? stack)) (= (pairFirst (c/firstOf stack)) (openerOf x)))
                (balChars raw n (+ i 1) ln (balGo false (c/restOf stack) start head))
                (let [extra (+ 1 (stringCountChar (tailFrom raw (+ i 1)) x))
                      col (+ (cpCount (c/sliceOf raw 0 i)) 1)
                      where (if (> start 0) (str "; " (itemWhere start head)) "")]
                  (balStop (str "line " (stringFromInt64 ln) " column " (stringFromInt64 col) " closes " (stringFromInt64 extra)
                             " more " x " than are open" where)))))
            (else (balChars raw n (+ i 1) ln st)))))))

fn balLines lines: (List String) ln: Int64 st: BalState -> BalState
  (match st
    ((balStop m) st)
    ((balGo inStr stack start head)
      (if (listEmpty? lines)
        st
        (let [raw (c/firstOf lines)
              first (ch raw 0)
              atCol0 (and (not inStr) (not (or (= first "") (or (= first " ") (or (= first "\t") (= first ";"))))))]
          (cond
            ((and atCol0 (not (listEmpty? stack)))
              (balStop (neverClosed stack (str " before line " (stringFromInt64 ln)) start head)))
            (else
              (let [st1 (if atCol0 (balGo inStr stack ln (itemHead raw)) st)]
                (balLines (c/restOf lines) (+ ln 1) (balChars raw (stringLength raw) 0 ln st1)))))))))

fn balanceAid text: String -> (Option String)
  (if (= text "")
    none
    (match (balLines (stringSplit text "\n") 1 (balGo false (list) 0 ""))
      ((balStop m) (some m))
      ((balGo inStr stack start head)
        (if (listEmpty? stack) none (some (neverClosed stack "" start head))))))

fn endLen line: String -> Int64
  (let [n (stringLength line)
        last (ch line (- n 1))]
    (cond
      ((= n 0) 0)
      ((stringEndsWith? line "\r\n") 2)
      ((or (stringEndsWith? line " ") (stringEndsWith? line " ")) 3)
      ((stringEndsWith? line "\u0085") 2)
      ((or (and (>= last "\n") (<= last "\r")) (and (>= last "\u001c") (<= last "\u001e"))) 1)
      (else 0)))

fn splitLines text: String -> (List String)
  (map (fn [l] (c/sliceOf l 0 (- (stringLength l) (endLen l)))) (diff/splitLinesKeepEnds text))

fn universalNewlines t: String -> String
  (if (stringContains? t "\r") (stringReplace (stringReplace t "\r\n" "\n") "\r" "\n") t)

fn ! readText! path: String -> FileText
  (match (fileStat path)
    ((err _) (fileAbsent))
    ((ok st)
      (if st.isDir
        (fileFailed (str path ": is a directory"))
        (match (fileReadString path)
          ((ok t) (fileText (universalNewlines t)))
          ((err e) (fileFailed (str path ": " e)))))))

fn replaceFirst s: String old: String new: String -> (Option String)
  (if (= old "")
    (some (str new s))
    (match (stringIndexOf s old)
      ((some i) (some (str (c/sliceOf s 0 i) new (tailFrom s (+ i (stringLength old))))))
      (none none)))

fn applySteps text: String steps: (List TxnStep) target: String -> (Option String)
  (fold (fn [acc s]
          (match acc
            ((some cur)
              (match s
                ((txnStep op file kv)
                  (cond
                    ((!= file target) acc)
                    ((= op "write") (some (kvGet kv "content")))
                    ((= op "edit") (replaceFirst cur (kvGet kv "old") (kvGet kv "new")))
                    (else acc)))))
            (none none)))
    (some text) steps)

fn stepOp kv: (List (Pair String c/KvVal)) -> String
  (let [head (kvGet kv "_head")]
    (if (= head "step") (kvGet kv "op") head))

fn stepsOf subs: (List String) -> (List TxnStep)
  (map (fn [f] (let [kv (c/parseKv f)] (txnStep (stepOp kv) (kvGet kv "file") kv))) subs)

fn decodedHint -> String
  "this is the text as decoded from your reply; in ASN strings a backslash is written \\\\ and a double quote \\\""

fn joinPath root: String p: String -> String
  (if (stringStartsWith? p "/") p (str root "/" p))

fn abortAidOn text: String steps: (List TxnStep) target: String digits: String extra: String -> (Option AbortAid)
  (match (applySteps text steps target)
    ((some cur)
      (let [lines (splitLines cur)
            k (optionOr (stringToInt64 (dropZeros digits)) 0)]
        (if (and (>= k 1) (<= k (listLength lines)))
          (some (abortAidOf k (cpPrefix (optionOr (listGet lines (- k 1)) "") 200)
                  (if (!= extra "") (str (decodedHint) "; " extra) (decodedHint))))
          none)))
    (none none))

fn ! abortAid! root: String target: String steps: (List TxnStep) fullMsg: String extra: String -> (Option AbortAid)
  (let [digits (lineDigits fullMsg (stringLength fullMsg) 0)]
    (if (or (= digits "") (= target ""))
      none
      (match (readText! (joinPath root target))
        ((fileAbsent) (abortAidOn "" steps target digits extra))
        ((fileText t) (abortAidOn t steps target digits extra))
        ((fileFailed _) none))))

fn opWords s: String n: Int64 p: Int64 acc: (List String) -> (List String)
  (cond
    ((>= p n) (listReverse acc))
    ((litAt s p ":op")
      (let [r (runEnd s n (+ p 3) isSpace)
            q (if (and (< r n) (= (ch s r) ":")) (+ r 1) r)
            k (if (and (< q n) (= (ch s q) "\"")) (+ q 1) q)
            e (runEnd s n k isWord)]
        (if (and (> r (+ p 3)) (> e k))
          (opWords s n e (cons (c/sliceOf s k e) acc))
          (opWords s n (+ p 1) acc))))
    (else (opWords s n (+ p 1) acc)))

fn intelSubop sub: String form: String -> String
  (if (!= sub "")
    (tailFrom sub (runEnd sub (stringLength sub) 0 (fn [x] (= x ":"))))
    (optionOr (listHead (filter (fn [w] (!= w "intel")) (opWords form (stringLength form) 0 (list)))) ""))

fn allDigits s: String -> Bool
  (and (> (stringLength s) 0) (= (runEnd s (stringLength s) 0 isDigit) (stringLength s)))

; (:m :adopted NormativeAndEmpiricalAreNotMixed)
fn widenLines -> Int64
  120

; (:m :adopted NormativeAndEmpiricalAreNotMixed)
fn widenMinLeft -> Float64
  5.0

fn widenWanted start: String end: String budgetLeft: (Option Float64) -> Bool
  (if (not (and (allDigits start) (allDigits end)))
    false
    (match (stringToInt64 (dropZeros start))
      ((some a)
        (match (stringToInt64 (dropZeros end))
          ((some b)
            (and (>= b a) (and (< (+ (- b a) 1) (widenLines))
              (match budgetLeft ((some left) (>= left (widenMinLeft))) (none true)))))
          (none false)))
      (none false)))

fn widenForm filePath: String -> String
  (str "(:intel :op outline :file \"" (c/escapeAsn filePath) "\")")

fn intAt s: String a: Int64 b: Int64 -> Int64
  (optionOr (stringToInt64 (dropZeros (c/sliceOf s a b))) -1)

fn outlineItems s: String n: Int64 p: Int64 acc: (List WidenItem) -> (List WidenItem)
  (cond
    ((>= p n) (listReverse acc))
    ((litAt s p "(:item :name \"")
      (let [nb (+ p 14)
            ne (quotedEnd s n nb)
            kb (+ ne 9)
            ke (if (and (>= ne 0) (litAt s ne "\" :kind \"")) (runEnd s n kb isWord) -1)
            sb (+ ke 9)
            se (if (and (> ke kb) (litAt s ke "\" :start ")) (runEnd s n sb isDigit) -1)
            eb (+ se 6)
            ee (if (and (> se sb) (litAt s se " :end ")) (runEnd s n eb isDigit) -1)]
        (if (and (> ee eb) (litAt s ee ")"))
          (outlineItems s n (+ ee 1) (cons (widenItem (intAt s sb se) (intAt s eb ee) (c/sliceOf s nb ne) (c/sliceOf s kb ke)) acc))
          (outlineItems s n (+ p 1) acc))))
    (else (outlineItems s n (+ p 1) acc)))

fn widenKinds -> (List String)
  (list "def" "class" "function" "method" "fn" "struct" "impl" "module")

fn span w: WidenItem -> Int64
  (match w ((widenItem a b _ _) (- b a)))

fn keepLines lines: (List String) i: Int64 a: Int64 b: Int64 acc: Int64 -> Int64
  (if (or (listEmpty? lines) (> i b))
    acc
    (keepLines (c/restOf lines) (+ i 1) a b (if (>= i a) (+ acc (cpCount (c/firstOf lines))) acc)))

fn linesKeep text: String -> (List String)
  (let [parts (stringSplit text "\n")
        k (listLength parts)]
    (filter (fn [l] (!= l ""))
      (map (fn [p] (if (< (pairFirst p) (- k 1)) (str (pairSecond p) "\n") (pairSecond p))) (enumerate parts))))

fn widenPick start: Int64 end: Int64 exit: Int64 stdout: String file: FileText readCap: Int64 -> (Option WidenItem)
  (let [around (filter (fn [w] (match w ((widenItem a b _ k)
                                       (and (listContains? (widenKinds) k) (and (<= a start) (and (>= b end) (not (and (= a start) (= b end)))))))))
                 (outlineItems stdout (stringLength stdout) 0 (list)))]
    (if (or (!= exit 0) (listEmpty? around))
      none
      (let [inner (fold (fn [best w] (if (< (span w) (span best)) w best)) (c/firstOf around) (c/restOf around))]
        (match file
          ((fileText t)
            (match inner ((widenItem a b _ _) (if (<= (keepLines (linesKeep t) 1 a b 0) readCap) (some inner) none))))
          ((fileAbsent) none)
          ((fileFailed _) none)))))

; (:m :tags (budget))
fn ! widenToSymbol! filePath: String start: String end: String root: String readCap: Int64 budgetLeft: (Option Float64) run: (fn [String String] -> AslRun) -> (Option WidenItem)
  (if (not (widenWanted start end budgetLeft))
    none
    (match (run (widenForm filePath) root)
      ((aslRun code out _)
        (widenPick (intAt start 0 (stringLength start)) (intAt end 0 (stringLength end)) code out (readText! (joinPath root filePath)) readCap))))

fn normParts parts: (List String) abs: Bool acc: (List String) -> (List String)
  (cond
    ((listEmpty? parts) (listReverse acc))
    (else
      (let [x (c/firstOf parts)
            rest (c/restOf parts)]
        (cond
          ((or (= x "") (= x ".")) (normParts rest abs acc))
          ((and (= x "..") (and (not (listEmpty? acc)) (!= (c/firstOf acc) ".."))) (normParts rest abs (c/restOf acc)))
          ((and (= x "..") (and abs (listEmpty? acc))) (normParts rest abs acc))
          (else (normParts rest abs (cons x acc)))))))

fn normPath p: String -> String
  (if (= p "")
    "."
    (let [lead (cond
                 ((not (stringStartsWith? p "/")) "")
                 ((and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) "//")
                 (else "/"))
          body (c/joinSep (normParts (stringSplit p "/") (!= lead "") (list)) "/")
          out (str lead body)]
      (if (= out "") "." out)))

fn comps p: String -> (List String)
  (filter (fn [x] (and (!= x "") (!= x "."))) (stringSplit p "/"))

fn prefixLen a: (List String) b: (List String) k: Int64 -> Int64
  (if (or (listEmpty? a) (or (listEmpty? b) (!= (c/firstOf a) (c/firstOf b))))
    k
    (prefixLen (c/restOf a) (c/restOf b) (+ k 1)))

fn within root: String target: String -> Bool
  (let [r (comps root)]
    (= (prefixLen r (comps target) 0) (listLength r)))

fn relFrom path: String start: String -> String
  (let [p (comps path)
        s (comps start)
        i (prefixLen p s 0)
        rel (listAppend (map (fn [_] "..") (range i (listLength s))) (listDrop p i))]
    (if (listEmpty? rel) "." (c/joinSep rel "/")))

fn dirName p: String -> String
  (let [parts (stringSplit p "/")
        k (listLength parts)]
    (if (<= k 1) "" (let [d (c/joinSep (listTake parts (- k 1)) "/")] (if (= d "") "/" d))))

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn ! realLoose p: String -> String
  (match (realPath p)
    ((ok r) r)
    ((err _)
      (if (or (= p "/") (= (dirName p) ""))
        p
        (let [d (realLoose (dirName p))]
          (if (= d "/") (str "/" (baseName p)) (str d "/" (baseName p)))))))

fn ! pathInRepo path: String root: String -> Bool
  (let [s (pyStrip path)]
    (if (= s "")
      true
      (let [norm (normPath s)]
        (if (or (= norm "..") (stringStartsWith? norm "../"))
          false
          (let [absTarget (normPath (joinPath root s))
                absRoot (normPath root)]
            (or (within absRoot absTarget) (within (realLoose root) (realLoose absTarget))))))))

; (:m :tags (owns))
fn ! insideRoot path: String root: String -> Bool
  (let [absRoot (normPath root)
        rel (normPath (relFrom (normPath (joinPath absRoot path)) absRoot))]
    (and (pathInRepo path root) (!= (c/firstOf (stringSplit rel "/")) ".git")))

fn effectPairs s: String n: Int64 p: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (cond
    ((>= p n) acc)
    ((litAt s p ":op")
      (let [r (runEnd s n (+ p 3) isSpace)
            qe (if (and (> r (+ p 3)) (and (< r n) (= (ch s r) "\""))) (runEnd s n (+ r 1) (fn [x] (!= x "\""))) -1)
            ok1 (and (> qe (+ r 1)) (< qe n))
            w (if ok1 (runEnd s n (+ qe 1) isSpace) -1)
            ok2 (and ok1 (and (> w (+ qe 1)) (litAt s w ":class")))
            v (if ok2 (runEnd s n (+ w 6) isSpace) -1)
            ok3 (and ok2 (and (> v (+ w 6)) (litAt s v ":")))
            e (if ok3 (runEnd s n (+ v 1) isWord) -1)]
        (if (and ok3 (> e (+ v 1)))
          (effectPairs s n e (putEffect acc (c/sliceOf s (+ r 1) qe) (c/sliceOf s (+ v 1) e)))
          (effectPairs s n (+ p 1) acc))))
    (else (effectPairs s n (+ p 1) acc)))

fn putEffect acc: (List (Pair String String)) op: String cls: String -> (List (Pair String String))
  (if (listAny? (fn [p] (= (pairFirst p) op)) acc)
    (map (fn [p] (if (= (pairFirst p) op) (pair op cls) p)) acc)
    (listAppend acc (list (pair op cls))))

; (:m :ref scripts/agentLoop/effects.asn)
fn parseEffects text: String -> (List (Pair String String))
  (effectPairs text (stringLength text) 0 (list))

fn ! loadEffects! repoRoot: String -> (Result (List (Pair String String)) String)
  (let [selfHostedPath (str repoRoot "/asl/agentLoop/effects.asn")
        legacyPath (str repoRoot "/scripts/agentLoop/effects.asn")
        path (if (fileExists? selfHostedPath) selfHostedPath legacyPath)]
    (match (fileStat path)
      ((err _) (ok (list)))
      ((ok st)
        (if (not st.isFile)
          (ok (list))
          (match (fileReadString path)
            ((ok t) (ok (parseEffects t)))
            ((err e) (err (str path ": " e))))))))

fn checkEffect effects: (List (Pair String String)) op: String -> Effect
  (match (listHead (filter (fn [p] (= (pairFirst p) op)) effects))
    ((some p) (if (listContains? (list "outward" "irreversible" "needsConfirm") (pairSecond p)) (effectConfirm) (effectAllowed)))
    (none (effectUndeclared)))

fn quotedAll s: String n: Int64 p: Int64 acc: (List String) -> (List String)
  (cond
    ((>= p n) (listReverse acc))
    ((= (ch s p) "\"")
      (let [e (quotedEnd s n (+ p 1))]
        (if (>= e 0) (quotedAll s n (+ e 1) (cons (c/sliceOf s (+ p 1) e) acc)) (quotedAll s n (+ p 1) acc))))
    (else (quotedAll s n (+ p 1) acc)))

fn spaceWords s: String -> (List String)
  (filter (fn [w] (!= w "")) (stringSplit (c/joinAll (map (fn [x] (if (isSpace x) " " x)) (stringChars s))) " "))

fn ownsGroup s: String n: Int64 p: Int64 -> (Option String)
  (cond
    ((>= p n) none)
    ((litAt s p ":owns")
      (let [r (runEnd s n (+ p 5) isSpace)
            e (if (and (> r (+ p 5)) (and (< r n) (= (ch s r) "("))) (runEnd s n (+ r 1) (fn [x] (!= x ")"))) -1)]
        (if (and (> e r) (< e n)) (some (c/sliceOf s (+ r 1) e)) (ownsGroup s n (+ p 1)))))
    (else (ownsGroup s n (+ p 1))))

fn txnOwnsOf form: String owns: (List String) -> (List String)
  (match (ownsGroup form (stringLength form) 0)
    ((some g)
      (let [q (quotedAll g (stringLength g) 0 (list))]
        (if (listEmpty? q)
          (map (fn [w] (trimChar (trimChar (pyStrip w) "\"") "'")) (spaceWords g))
          q)))
    (none owns))

fn ownsReceipt rid: String op: String path: String owns: (List String) -> (List (Pair String RVal))
  (list (pair "id" (rStr rid)) (pair "op" (rStr op)) (pair "status" (rStr "rejected")) (pair "error" (rStr "ERR_OWNS"))
    (pair "file" (rStr path)) (pair "owns" (rList owns))
    (pair "message" (rStr (str "'" path "' is outside :owns; nothing in this step was written; the run goes on"))))

fn rootReceipt rid: String op: String path: String -> (List (Pair String RVal))
  (list (pair "id" (rStr rid)) (pair "op" (rStr op)) (pair "status" (rStr "rejected")) (pair "error" (rStr "ERR_ROOT"))
    (pair "file" (rStr path))
    (pair "message" (rStr (str "'" path "' is outside :root; nothing in this step was written; the run goes on"))))

fn simpleReject rid: String op: RVal err: String msg: String -> (List (Pair String RVal))
  (list (pair "id" (rStr rid)) (pair "op" op) (pair "status" (rStr "rejected")) (pair "error" (rStr err)) (pair "message" (rStr msg)))

fn confirmReceipt rid: String op: String -> (List (Pair String RVal))
  (list (pair "id" (rStr rid)) (pair "op" (rStr op)) (pair "status" (rStr "needsConfirm")) (pair "needsConfirm" (rBool true))
    (pair "message" (rStr (str "not executed: '" op "' is an outward effect that needs the principal's confirmation; the run goes on"))))

enum TxnW
  (txnW form: String file: String mod: String imps: (List String))

; (:m :ref TXN-WRITE-ORDER :do "the module a source text declares: the first word after (module when the text starts with it, else empty")
fn moduleOf text: String -> String
  (let [t (pyStrip text)]
    (if (stringStartsWith? t "(module ")
      (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit (optionOr (stringSlice t 8 (stringLength t)) "") "\n")) "") " ")) "")
      ""))

; (:m :ref TXN-WRITE-ORDER :do "the module names in the :i [ ... ] list of a source text, the first word of each (name :a alias) item")
fn importsOf text: String -> (List String)
  (match (listGet (stringSplit text ":i [") 1)
    (none (list))
    ((some r)
      (let [body (optionOr (listHead (stringSplit r "]")) "")]
        (filter (fn [w] (not (stringEmpty? w)))
          (map (fn [piece] (optionOr (listHead (stringSplit (pyStrip piece) " ")) ""))
               (optionOr (listTail (stringSplit body "(")) (list)))))))

fn noW -> TxnW
  (txnW "" "" "" (list))

fn writeOf f: String -> (Option TxnW)
  (let [kv (c/parseKv f)
        head (kvGet kv "_head")
        op (if (= head "step") (kvGet kv "op") head)
        content (kvGet kv "content")]
    (if (and (= op "write") (stringEndsWith? (kvGet kv "file") ".asl"))
      (some (txnW f (kvGet kv "file") (moduleOf content) (importsOf content)))
      none))

fn wForm w: TxnW -> String
  (match w ((txnW f _ _ _) f))

fn wFile w: TxnW -> String
  (match w ((txnW _ file _ _) file))

fn wMod w: TxnW -> String
  (match w ((txnW _ _ m _) m))

fn wImps w: TxnW -> (List String)
  (match w ((txnW _ _ _ i) i))

fn writesOf subs: (List String) -> (List TxnW)
  (fold (fn [acc f] (match (writeOf f) ((some w) (listAppend acc (list w))) (none acc))) (list) subs)

; (:m :ref TXN-WRITE-ORDER :do "stable order of the staged .asl writes so a module comes before the writes that import it: the first pending write none of whose imports is declared by another pending write goes next; a cycle emits the first pending write unchanged")
fn topoWrites pending: (List TxnW) done: (List TxnW) -> (List TxnW)
  (if (listEmpty? pending)
    (listReverse done)
    (let [mods (map wMod pending)
          blocked (fn [w] (listAny? (fn [m] (and (!= m (wMod w)) (listContains? mods m))) (wImps w)))
          idx (optionOr (listFind (fn [i] (not (blocked (optionOr (listGet pending i) (noW))))) (range 0 (listLength pending))) 0)
          pick (optionOr (listGet pending idx) (noW))]
      (topoWrites (map (fn [i] (optionOr (listGet pending i) pick)) (filter (fn [i] (!= i idx)) (range 0 (listLength pending)))) (cons pick done))))

fn editsOf f: String -> String
  (let [kv (c/parseKv f)
        head (kvGet kv "_head")]
    (if (= (if (= head "step") (kvGet kv "op") head) "edit") (kvGet kv "file") ""))

; (:m :ref TXN-WRITE-ORDER :do "files staged in one txn resolve against each other whatever order the model wrote them in: the .asl write steps are re-slotted by topoWrites into the positions the writes held; nothing moves when fewer than two writes, when an edit step targets a file the txn also writes, or when the order already holds")
fn orderSubs subs: (List String) -> (List String)
  (let [writes (writesOf subs)
        files (map wFile writes)
        editsWritten (listAny? (fn [f] (let [e (editsOf f)] (and (!= e "") (listContains? files e)))) subs)
        sorted (map wForm (topoWrites writes (list)))]
    (if (or (< (listLength writes) 2) (or editsWritten (= sorted (map wForm writes))))
      subs
      (pairSecond
        (fold (fn [acc f]
                (if (some? (writeOf f))
                  (pair (optionOr (listTail (pairFirst acc)) (list)) (listAppend (pairSecond acc) (list (optionOr (listHead (pairFirst acc)) f))))
                  (pair (pairFirst acc) (listAppend (pairSecond acc) (list f)))))
              (pair sorted (list)) subs))))

; (:m :ref TXN-WRITE-ORDER :do "the module name the path calls for: asl/tools/X -> asl-tools/X, asl/packages/P/src|tests/X -> P/X, else the path without .asl")
fn expectedModule file: String -> String
  (let [base (if (stringEndsWith? file ".asl") (optionOr (stringSlice file 0 (- (stringLength file) 4)) file) file)
        parts (stringSplit base "/")]
    (cond
      ((and (> (listLength parts) 4) (and (= (optionOr (listGet parts 0) "") "asl") (and (= (optionOr (listGet parts 1) "") "packages") (listContains? (list "src" "tests") (optionOr (listGet parts 3) "")))))
        (stringJoin (cons (optionOr (listGet parts 2) "") (optionOr (listSlice parts 4 (listLength parts)) (list))) "/"))
      ((and (> (listLength parts) 2) (and (= (optionOr (listGet parts 0) "") "asl") (= (optionOr (listGet parts 1) "") "tools")))
        (str "asl-tools/" (stringJoin (optionOr (listSlice parts 2 (listLength parts)) (list)) "/")))
      (else base)))

fn lastSeg s: String -> String
  (optionOr (listLast (stringSplit s "/")) s)

; (:m :ref TXN-WRITE-ORDER :do "a static hint for staged .asl writes whose module header cannot belong to the file: the last segment of the module is not the file's base name (a src file carrying its test's module name, a test carrying the src's), or two writes of the txn declare one module; empty when all are fine")
fn moduleHints subs: (List String) -> String
  (let [writes (writesOf subs)
        names (map wMod writes)
        bad (filter (fn [w] (and (!= (wMod w) "") (!= (lastSeg (wMod w)) (lastSeg (expectedModule (wFile w)))))) writes)
        dup (filter (fn [w] (and (!= (wMod w) "") (> (listLength (filter (fn [m] (= m (wMod w))) names)) 1))) writes)
        mis (map (fn [w] (str "module '" (wMod w) "' in " (wFile w) " does not fit its path, the module is named after the file: expected '" (expectedModule (wFile w)) "'; a src file must not reuse its test's module name")) bad)
        dups (map (fn [w] (str (wFile w) " declares module '" (wMod w) "' that another write of this txn declares too; each file has its own module name")) (filter (fn [w] (not (listAny? (fn [b] (= (wFile b) (wFile w))) bad))) dup))]
    (stringJoin (listAppend mis dups) "; "))

fn txnSubs form: String -> (List String)
  (let [n (stringLength form)
        inner (if (>= n 2) (c/sliceOf form 1 (- n 1)) "")]
    (filter (fn [f] (stringStartsWith? (pyStrip f) "(:")) (c/parseForms inner)))

enum SubAcc
  (subGo forms: (List String) targets: (List String))
  (subStop receipt: (List (Pair String RVal)))

fn quoteEach xs: (List String) -> String
  (c/joinSep (map (fn [o] (str "\"" o "\"")) xs) " ")

fn ! mapSub kv: (List (Pair String c/KvVal)) owns: (List String) txnOwns: (List String) root: String effects: (List (Pair String String)) rid: String newId: (fn [] -> String) forms: (List String) targets: (List String) -> SubAcc
  (let [head (kvGet kv "_head")
        isStep (= head "step")
        intOp (and isStep (kvIsInt kv "op"))
        op (if isStep (kvGet kv "op") head)
        file (kvGet kv "file")]
    (cond
      (intOp (subStop (simpleReject rid (rInt (optionOr (stringToInt64 op) 0)) "ERR_EFFECT_UNDECLARED" (str "Operation '" op "' not declared in effects registry"))))
      ((= op "flush") (subGo forms targets))
      ((or (= op "write") (= op "edit"))
        (cond
          ((or (= file "") (and (kvIsInt kv "file") (= file "0"))) (subStop (simpleReject rid (rStr "txn") "ERR_MISSING_ARG" "Missing file in inner step")))
          ((not (insideRoot file root)) (subStop (rootReceipt rid "txn" file)))
          ((not (c/checkOwns file owns root)) (subStop (ownsReceipt rid "txn" file owns)))
          ((not (c/checkOwns file txnOwns root)) (subStop (ownsReceipt rid "txn" file txnOwns)))
          ((= op "write")
            (subGo (listAppend forms (list (str "(:write :file \"" file "\" :content \"" (c/escapeAsn (kvGet kv "content")) "\""
                                             (if (= (kvGet kv "force") "true") " :force true" "") ")")))
              (listAppend targets (list file))))
          (else
            (subGo (listAppend forms (list (str "(:edit :file \"" file "\" :old \"" (c/escapeAsn (kvGet kv "old")) "\" :new \"" (c/escapeAsn (kvGet kv "new")) "\")")))
              (listAppend targets (list file))))))
      ((= op "read") (subGo (listAppend forms (list (str "(:read :file \"" file "\")"))) targets))
      ((= op "check") (subGo (listAppend forms (list (str "(:check :file \"" file "\")"))) targets))
      ((= op "diff") (subGo (listAppend forms (list "(:diff)")) targets))
      (else
        (match (checkEffect effects op)
          ((effectUndeclared) (subStop (simpleReject rid (rStr op) "ERR_EFFECT_UNDECLARED" (str "Operation '" op "' not declared in effects registry"))))
          ((effectConfirm) (subStop (confirmReceipt (newId) op)))
          ((effectAllowed) (subGo forms targets))))))

; (:m :ref LEON-OWNS-ALL-20261018 :do "no :owns on the session means the session may write anywhere inside :root; sessionOwns stands in for that case so a :txn with no :owns of its own inherits unrestricted scope, while a :txn that spells out :owns () still narrows to nothing -- this now shares c/effectiveOwns, the one normalization, instead of keeping its own independent (correct but redundant) copy")
fn ! txnPrepare form: String owns: (List String) root: String effects: (List (Pair String String)) rid: String newId: (fn [] -> String) -> TxnPrep
  (let [sessionOwns (c/effectiveOwns owns)
        txnOwns (txnOwnsOf form sessionOwns)
        unowned (filter (fn [p] (not (c/checkOwns p sessionOwns root))) txnOwns)]
    (if (not (listEmpty? unowned))
      (prepDone (ownsReceipt rid "txn" (c/firstOf unowned) owns))
      (let [subs (orderSubs (txnSubs form))
            acc (fold (fn [a f] (match a
                                  ((subGo fs ts) (mapSub (c/parseKv f) sessionOwns txnOwns root effects rid newId fs ts))
                                  ((subStop _) a)))
                  (subGo (list) (list)) subs)]
        (match acc
          ((subStop r) (prepDone r))
          ((subGo fs ts)
            (if (listEmpty? fs)
              (prepDone (list (pair "id" (rStr rid)) (pair "op" (rStr "txn")) (pair "status" (rStr "ok")) (pair "owns" (rList txnOwns))
                          (pair "flushed" (rList (list))) (pair "exit" (rInt 0)) (pair "persisted" (rBool false))))
              (prepRun txnOwns ts (stepsOf subs) (str "(:txn :owns (" (quoteEach txnOwns) ") " (c/joinSep fs " ") ")"))))))))

fn refusedMark -> String
  "refused: the delimiters"

fn largeFileHint -> String
  "write a large file in parts: the first part with write, the rest with edit ops anchored on its last line"

fn runErr out: String -> String
  (cond
    ((stringContains? out "ERR_OWNS") "ERR_OWNS")
    ((stringContains? out "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
    ((stringContains? out "ERR_TXN_FLUSH_FAILED") "ERR_TXN_FLUSH_FAILED")
    (else (let [code (errorCodeIn out)] (if (= code "") "ERR_TXN_FAILED" code))))

fn opt key: String v: (Option String) -> (List (Pair String RVal))
  (match v ((some t) (list (pair key (rStr t)))) (none (list)))

; (:m :tags (repair))
fn langForPath path: String -> (Option String)
  (cond
    ((stringEndsWith? path ".asn") (some "asn"))
    ((stringEndsWith? path ".asl") (some "asl"))
    (else none))

; (:m :ref REFUSE-AUTOREPAIR :do "the checker verdict a landed repair carries: ok, or the count and the first three diagnostics with line:col, so the writer sees them in the turn the write lands")
fn checkField res: heal/HealResult -> String
  (if (listEmpty? res.left)
    "ok"
    (str "(:diags " (stringFromInt64 (listLength res.left)) " :first (" (stringJoin (map (fn [d] (str "\"" (c/escapeAsn (heal/diagText d)) "\"")) (listTake res.left 3)) " ") "))"))

fn parseLeft? res: heal/HealResult -> Bool
  (listAny? (fn [d] (= d.code "parse")) res.left)

; (:m :ref REFUSE-AUTOREPAIR :do "a balance-refusal heal lands when it changed the text, balances it and left no parse error; diagnostics such as an import the same reply writes next are expected mid multi-file edit and ride along as :check")
fn balanceHealed res: heal/HealResult -> (Option (Pair String (Pair String String)))
  (if (and res.changed (and (none? (balanceAid res.text)) (not (parseLeft? res))))
    (some (pair res.text (pair res.receipt (checkField res))))
    none)

; (:m :ref G4 :tags (repair) :do "an .asl text goes through the one heal pipeline (asl-forms/heal); a checker abort (clean) is accepted only when nothing is left over; a balance refusal through balanceHealed, which also lands the parse-level repair heal! keeps when the text's imports do not load yet (importsUnloaded left); an .asn text through asl-forms/repair, accepted only when nothing is left and the result balances")
fn tryRepairText! cur: (Option String) tf: String root: String clean: Bool -> (Option (Pair String (Pair String String)))
  (match cur
    ((none) none)
    ((some t)
      (match (langForPath tf)
        ((none) none)
        ((some lang)
          (if (= lang "asl")
            (match (heal/heal! (joinPath root tf) t (list root) (joinPath root "asl/prelude/prelude.asl") 24)
              ((ok res) (if clean
                          (if (and res.changed (listEmpty? res.left)) (some (pair res.text (pair res.receipt (checkField res)))) none)
                          (balanceHealed res)))
              ((err _) none))
            (let [res (rep/repairAtSite t lang)]
              (if (and (listEmpty? (rep/repairResultLeft res)) (none? (balanceAid (rep/repairResultText res))))
                (some (pair (rep/repairResultText res) (pair (rep/repairResultReceipt res) "")))
                none)))))))

fn repairedReceipt rid: String txnOwns: (List String) tf: String receipt: String check: String cmd: String -> (List (Pair String RVal))
  (listAppend
    (list (pair "id" (rStr rid)) (pair "op" (rStr "txn")) (pair "status" (rStr "ok"))
      (pair "owns" (rList txnOwns)) (pair "flushed" (rList (list tf)))
      (pair "error" (rNone)) (pair "message" (rNone))
      (pair "cmd" (rStr cmd))
      (pair "repaired" (rStr receipt)))
    (listAppend (if (stringEmpty? check) (list) (list (pair "check" (rStr check))))
      (list (pair "exit" (rInt 0)) (pair "stdout" (rStr "")) (pair "persisted" (rBool true)))))

fn ! defaultReceipt rid: String txnOwns: (List String) tf: String steps: (List TxnStep) root: String cmd: String okRun: Bool err: String msg: String balance: (Option String) code: Int64 out: String errText: String -> (List (Pair String RVal))
  (let [extra (if (or (= err "ERR_TXN_FLUSH_FAILED") (stringContains? msg "the delimiters ( ) [ ] { } and quotes do not balance")) (largeFileHint) "")
        aid (if okRun none (abortAid! root tf steps (str msg " " out " " errText) extra))
        hint0 (match aid ((some x) (match x ((abortAidOf _ _ h) (some h)))) (none none))
        tmpl (str "(:step :op \"write\" :file \"" tf "\" :content :raw)")
        hint (if (and (not okRun) (and (or (= err "ERR_TXN_FLUSH_FAILED") (= err "ERR_TXN_ABORTED")) (!= tf "")))
               (some (match hint0 ((some h) (str h "; " tmpl)) (none tmpl)))
               hint0)]
    (listAppend
      (list (pair "id" (rStr rid)) (pair "op" (rStr "txn")) (pair "status" (rStr (if okRun "ok" "rejected")))
        (pair "owns" (rList txnOwns)) (pair "flushed" (rList (if okRun txnOwns (list))))
        (pair "error" (if okRun (rNone) (rStr err))) (pair "message" (if okRun (rNone) (rStr msg)))
        (pair "cmd" (rStr cmd)))
      (listAppend (opt "balance" balance)
        (listAppend
          (list (pair "exit" (rInt code)) (pair "stdout" (rStr out)) (pair "persisted" (rBool okRun)))
          (listAppend
            (match aid ((some x) (match x ((abortAidOf k a _) (list (pair "line" (rInt k)) (pair "arrived" (rStr a)))))) (none (list)))
            (opt "hint" hint))))))

fn lineOfAid aid: String -> (Option Int64)
  (if (stringStartsWith? aid "line ") (stringToInt64 (optionOr (listGet (stringSplit aid " ") 1) "")) none)

fn numbered lines: (List String) i: Int64 -> (List String)
  (match (listHead lines)
    ((none) (list))
    ((some l) (cons (str (stringFromInt64 i) ": " l) (numbered (optionOr (listTail lines) (list)) (+ i 1)))))

; (:m :ref REFUSE-AUTOREPAIR :do "the content lines around the line a balance aid names, numbered, so the writer sees the unmatched delimiter in place; empty when the aid names no line")
fn aroundLines text: String aid: String -> String
  (match (lineOfAid aid)
    ((none) "")
    ((some k)
      (let [lines (stringSplit text "\n")
            from (max 1 (- k 1))
            to (min (listLength lines) (+ k 1))]
        (stringJoin (numbered (listTake (listDrop lines (- from 1)) (+ (- to from) 1)) from) "\n"))))

fn withAround r: (List (Pair String RVal)) cur: (Option String) balance: (Option String) -> (List (Pair String RVal))
  (match balance
    ((none) r)
    ((some aid)
      (let [around (aroundLines (optionOr cur "") aid)]
        (if (stringEmpty? around) r (listAppend r (list (pair "around" (rStr around))))))))

; (:m :ref G4 :tags (repair txn) :do "a balance-flagged refusal, and for an .asl target a checker abort, is retried once through the repair pipeline before it reaches the model; only a payload repair cannot fix still refuses")
fn ! txnFinish! prep: TxnPrep result: AslRun root: String rid: String -> (List (Pair String RVal))
  (match prep
    ((prepDone r) r)
    ((prepRun txnOwns targets steps form)
      (match result
        ((aslRun code out errText)
          (let [cmd (str "asl txn (" (quoteEach txnOwns) ")")
                okRun (= code 0)
                err (runErr out)
                msg0 (optionOr (messageIn out) errText)
                uniq (dedup targets)
                tf (if (= (listLength uniq) 1) (c/firstOf uniq) "")
                cur (if (and (not okRun) (and (!= tf "") (not (stringContains? msg0 (refusedMark)))))
                      (applySteps (match (readText! (joinPath root tf)) ((fileText t) t) ((fileAbsent) "") ((fileFailed _) "")) steps tf)
                      none)
                tMsg (match cur ((some t) (pairSecond (txnRefusal out errText err (some t)))) (none ""))
                msg (if (stringContains? tMsg (refusedMark)) tMsg msg0)
                balance (match cur
                          ((some t) (if (or (= err "ERR_TXN_FLUSH_FAILED") (stringContains? tMsg (refusedMark))) (balanceAid t) none))
                          (none none))
                healable (or (some? balance) (and (not okRun) (and (= err "ERR_TXN_ABORTED") (stringEndsWith? tf ".asl"))))
                repaired (if healable (tryRepairText! cur tf root (none? balance)) none)]
            (match repaired
              ((some fix)
                (match (fileWrite (joinPath root tf) (pairFirst fix))
                  ((ok _) (repairedReceipt rid txnOwns tf (pairFirst (pairSecond fix)) (pairSecond (pairSecond fix)) cmd))
                  ((err _) (withAround (defaultReceipt rid txnOwns tf steps root cmd okRun err msg balance code out errText) cur balance))))
              ((none) (withAround (defaultReceipt rid txnOwns tf steps root cmd okRun err msg balance code out errText) cur balance))))))))

fn ! snapAll snap: (fn [String] -> Bool) targets: (List String) -> String
  (cond
    ((listEmpty? targets) "")
    ((snap (c/firstOf targets)) (snapAll snap (c/restOf targets)))
    (else (c/firstOf targets)))

; (:m :ref TXN-WRITE-ORDER :do "the module hint rides on the receipt, ok or rejected, as the field moduleHint; no hint adds nothing")
fn withHint r: (List (Pair String RVal)) hint: String -> (List (Pair String RVal))
  (if (stringEmpty? hint) r (listAppend r (list (pair "moduleHint" (rStr hint)))))

; (:m :tags (txn))
fn ! execTxn! form: String owns: (List String) root: String effects: (List (Pair String String)) newId: (fn [] -> String) snap: (fn [String] -> Bool) run: (fn [String String] -> AslRun) -> (List (Pair String RVal))
  (let [rid (newId)
        prep (txnPrepare form owns root effects rid newId)]
    (match prep
      ((prepDone r) r)
      ((prepRun _ targets _ sent)
        (let [failed (snapAll snap targets)]
          (if (!= failed "")
            (simpleReject rid (rStr "txn") "ERR_SNAPSHOT" (str "'" failed "' could not be snapshotted before the write; nothing was sent"))
            (withHint (txnFinish! prep (run sent root) root rid) (moduleHints (txnSubs form))))))))
