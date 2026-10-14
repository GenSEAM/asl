(module asl-forms/search
  :x [KnowCtx KnowOutcome queryStep! noteStep! whereStep! observeStep! observeResult kwOrder localDate! localDateAt! pyStrip pyDecode pySplitWs pyInt utf8Take utf8TakeLast splitLinesPy quoted stepHead okLine badLine procErrorMessage]
  :i [(asl-forms/kernel :a k) (asl-proc/coreProcess :a cp) (asl-forms/vfs :a v)
      (ws/asl/tools/observe/observe :a obs) (ws/asl/tools/observe/common :a oc)])


(schema KnowCtx (:f ws String) (:f toolRoot String) (:f binDir String) (:f vfsDir String) (:f toolsFile String) (:f home String))

(schema KnowOutcome (:f lines (List String)) (:f errCount Int64))

(schema Hit (:f rel String) (:f no Int64) (:f line String))

(schema ScanAcc (:f hits (List Hit)) (:f count Int64) (:f capped Bool) (:f skipped (List String)) (:f failed String))

(schema Cand (:f score Int64) (:f rel String) (:f no Int64) (:f name String) (:f line String))

(schema QueryResult (:f defs (List String)) (:f hits (List String)) (:f more Int64) (:f capped Bool) (:f binSkipped Int64) (:f sections (List (Pair String (List String)))) (:f elsewhere (List (Pair String Int64))) (:f failed String))


fn stepHead id: Int64 op: String -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"" op "\"")

fn okLine line: String -> KnowOutcome
  (KnowOutcome :lines (list line) :errCount 0)

fn badLine line: String -> KnowOutcome
  (KnowOutcome :lines (list line) :errCount 1)

fn quoted s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn rejectedLine id: Int64 op: String code: String tail: String -> KnowOutcome
  (badLine (str (stepHead id op) " :status \"rejected\" :error-code \":" code "\"" tail ")"))

fn slice s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s (max 0 a) (min (stringLength s) b)) "")

fn byteAt b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet b i) -1)

fn tailOf xs: (List String) -> (List String)
  (optionOr (listTail xs) (list))

fn wsLen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (byteAt b n i)) (c1 (byteAt b n (+ i 1))) (c2 (byteAt b n (+ i 2)))]
    (cond
      ((or (= c 32) (and (>= c 9) (<= c 13)) (and (>= c 28) (<= c 31))) 1)
      ((and (= c 194) (or (= c1 133) (= c1 160))) 2)
      ((and (= c 225) (= c1 154) (= c2 128)) 3)
      ((and (= c 226) (= c1 128) (or (and (>= c2 128) (<= c2 138)) (= c2 168) (= c2 169) (= c2 175))) 3)
      ((and (= c 226) (= c1 129) (= c2 159)) 3)
      ((and (= c 227) (= c1 128) (= c2 128)) 3)
      (else 0)))

fn wsLenBefore b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((and (>= i 1) (= (wsLen b n (- i 1)) 1)) 1)
    ((and (>= i 2) (= (wsLen b n (- i 2)) 2)) 2)
    ((and (>= i 3) (= (wsLen b n (- i 3)) 3)) 3)
    (else 0))

fn skipWsFwd b: Bytes n: Int64 i: Int64 -> Int64
  (let [(w (if (< i n) (wsLen b n i) 0))]
    (if (> w 0) (skipWsFwd b n (+ i w)) i))

fn skipWsBack b: Bytes n: Int64 lo: Int64 i: Int64 -> Int64
  (let [(w (if (> i lo) (wsLenBefore b n i) 0))]
    (if (and (> w 0) (>= (- i w) lo)) (skipWsBack b n lo (- i w)) i))

fn pyStrip s: String -> String
  (let [(b (stringToBytes s)) (n (stringLength s)) (l (skipWsFwd b n 0)) (r (skipWsBack b n l n))]
    (slice s l r))

fn pyLstripLen s: String -> Int64
  (skipWsFwd (stringToBytes s) (stringLength s) 0)

fn splitWsLoop s: String b: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [(st (skipWsFwd b n i))]
    (if (>= st n)
      (listReverse acc)
      (let [(e (tokenEnd b n st))]
        (splitWsLoop s b n e (cons (slice s st e) acc)))))

fn tokenEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (> (wsLen b n i) 0)) i (tokenEnd b n (+ i 1)))

fn pySplitWs s: String -> (List String)
  (splitWsLoop s (stringToBytes s) (stringLength s) 0 (list))

fn contByte? c: Int64 -> Bool
  (and (>= c 128) (< c 192))

fn takeLoop b: Bytes n: Int64 i: Int64 left: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((contByte? (bytesGet b i)) (takeLoop b n (+ i 1) left))
    ((= left 0) i)
    (else (takeLoop b n (+ i 1) (- left 1))))

fn utf8Take s: String k: Int64 -> String
  (slice s 0 (takeLoop (stringToBytes s) (stringLength s) 0 k))

fn countChars b: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (countChars b (+ i 1) n (if (contByte? (bytesGet b i)) acc (+ acc 1))))

fn utf8TakeLast s: String k: Int64 -> String
  (let [(b (stringToBytes s)) (n (stringLength s)) (total (countChars b 0 n 0))]
    (if (<= total k) s (slice s (takeLoop b n 0 (- total k)) n)))

fn seqLen c: Int64 -> Int64
  (cond ((< c 128) 1) ((and (>= c 194) (<= c 223)) 2) ((and (>= c 224) (<= c 239)) 3) ((and (>= c 240) (<= c 244)) 4) (else 0))

fn secondOk? c: Int64 d: Int64 -> Bool
  (cond
    ((= c 224) (and (>= d 160) (<= d 191)))
    ((= c 237) (and (>= d 128) (<= d 159)))
    ((= c 240) (and (>= d 144) (<= d 191)))
    ((= c 244) (and (>= d 128) (<= d 143)))
    (else (contByte? d)))

fn validRun b: Bytes n: Int64 i: Int64 want: Int64 got: Int64 -> Int64
  (cond
    ((= got want) got)
    ((>= (+ i got) n) got)
    ((= got 1) (if (secondOk? (bytesGet b i) (bytesGet b (+ i 1))) (validRun b n i want 2) got))
    ((contByte? (bytesGet b (+ i got))) (validRun b n i want (+ got 1)))
    (else got))

fn decodeLoop s: String b: Bytes n: Int64 i: Int64 from: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (slice s from n) acc))
    (let [(c (bytesGet b i)) (want (seqLen c))]
      (cond
        ((= want 1) (decodeLoop s b n (+ i 1) from acc))
        ((= want 0) (decodeLoop s b n (+ i 1) (+ i 1) (cons "\xef\xbf\xbd" (cons (slice s from i) acc))))
        (else
          (let [(got (validRun b n i want 1))]
            (if (= got want)
              (decodeLoop s b n (+ i want) from acc)
              (decodeLoop s b n (+ i got) (+ i got) (cons "\xef\xbf\xbd" (cons (slice s from i) acc)))))))))

fn validUtf8? b: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    true
    (let [(c (bytesGet b i)) (want (seqLen c))]
      (cond
        ((= want 1) (validUtf8? b n (+ i 1)))
        ((= want 0) false)
        ((= (validRun b n i want 1) want) (validUtf8? b n (+ i want)))
        (else false))))

fn pyDecode s: String -> String
  (let [(b (stringToBytes s)) (n (stringLength s))]
    (if (validUtf8? b n 0) s (stringJoin (decodeLoop s b n 0 0 (list)) "")))

fn lineSepLen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (bytesGet b i))]
    (cond
      ((or (= c 10) (= c 11) (= c 12) (= c 28) (= c 29) (= c 30)) 1)
      ((= c 13) (if (= (byteAt b n (+ i 1)) 10) 2 1))
      ((and (= c 194) (= (byteAt b n (+ i 1)) 133)) 2)
      ((and (= c 226) (= (byteAt b n (+ i 1)) 128) (or (= (byteAt b n (+ i 2)) 168) (= (byteAt b n (+ i 2)) 169))) 3)
      (else 0)))

fn splitLinesLoop s: String b: Bytes n: Int64 i: Int64 from: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< from n) (cons (slice s from n) acc) acc))
    (let [(w (lineSepLen b n i))]
      (if (= w 0)
        (splitLinesLoop s b n (+ i 1) from acc)
        (splitLinesLoop s b n (+ i w) (+ i w) (cons (slice s from i) acc)))))

fn splitLinesPy s: String -> (List String)
  (splitLinesLoop s (stringToBytes s) (stringLength s) 0 0 (list))

fn digitByte? c: Int64 -> Bool
  (and (>= c 48) (<= c 57))

fn allDigits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (digitByte? (charCode c))) (stringChars s)))

fn digitsUnderscored? s: String -> Bool
  (let [(parts (stringSplit s "_"))]
    (and (not (stringEmpty? s)) (listAll? allDigits? parts)))

fn parseDigits cs: (List String) acc: Int64 -> Int64
  (mt (listHead cs)
    ((none) acc)
    ((some c) (parseDigits (tailOf cs) (if (= c "_") acc (+ (* acc 10) (- (charCode c) 48))))))

fn pyInt raw: String -> (Option Int64)
  (let [(t (pyStrip raw))
        (neg (stringStartsWith? t "-"))
        (body (if (or neg (stringStartsWith? t "+")) (slice t 1 (stringLength t)) t))]
    (cond
      ((not (digitsUnderscored? body)) (none))
      ((> (stringLength body) 18) (some (if neg -999999999999999999 999999999999999999)))
      (else (let [(v (parseDigits (stringChars body) 0))] (some (if neg (- 0 v) v))))))

fn pyRepr s: String -> String
  (let [(dq (and (stringContains? s "'") (not (stringContains? s "\""))))
        (e1 (stringReplace s "\\" "\\\\"))
        (e2 (stringReplace (stringReplace (stringReplace e1 "\n" "\\n") "\r" "\\r") "\t" "\\t"))]
    (if dq (str "\"" e2 "\"") (str "'" (stringReplace e2 "'" "\\'") "'")))

fn procErrorMessage argv: (List String) e: cp/ProcessError -> String
  (mt e
    ((cp/notFound b) (str "[Errno 2] No such file or directory: " (pyRepr b)))
    ((cp/permissionDenied b) (str "[Errno 13] Permission denied: " (pyRepr b)))
    ((cp/timeout ms) (str "Command '[" (stringJoin (map pyRepr argv) ", ") "]' timed out after " (stringFromInt64 (/ ms 1000)) " seconds"))
    ((cp/executionFailed code msg) msg))

fn runArgv! argv: (List String) cwd: String timeoutMs: Int64 -> (Result cp/ProcessOutput cp/ProcessError)
  (mt (listHead argv)
    ((none) (err (cp/executionFailed -1 "empty argv")))
    ((some bin) (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd bin (tailOf argv)) cwd) timeoutMs))))

fn runObserveArgv! argv: (List String) cwd: String root: String host: String timeoutMs: Int64 -> (Result cp/ProcessOutput cp/ProcessError)
  (mt (listHead argv)
    ((none) (runArgv! argv cwd timeoutMs))
    ((some bin)
      (let [(base (cp/withCwd (cp/cmd bin (tailOf argv)) cwd))
            (withRoot (cp/withEnv base "ASL_CLI_ROOT" root))
            (withHost (cp/withEnv withRoot "ASL_CLI_HOST_BIN" host))]
        (cp/exec! (cp/withTimeout withHost timeoutMs)))))

fn readText! p: String -> (Option String)
  (mt (fileReadString p)
    ((ok t) (some (k/universalNewlines (pyDecode t))))
    ((err _) (none)))

fn binaryOf! p: String -> Bool
  (mt (fileReadRange p 0 8192)
    ((err _) false)
    ((ok head) (headBinary? head (bytesLength head))))

fn startsBytes? b: Bytes n: Int64 magic: (List Int64) i: Int64 -> Bool
  (mt (listHead magic)
    ((none) true)
    ((some m) (and (< i n) (= (bytesGet b i) m) (startsBytes? b n (optionOr (listTail magic) (list)) (+ i 1)))))

fn hasNul? b: Bytes n: Int64 i: Int64 -> Bool
  (cond ((>= i n) false) ((= (bytesGet b i) 0) true) (else (hasNul? b n (+ i 1))))

fn headBinary? b: Bytes n: Int64 -> Bool
  (or (listAny? (fn [(m (List Int64))] -> Bool (startsBytes? b n m 0))
                (list (list 207 250 237 254) (list 206 250 237 254) (list 254 237 250 207) (list 254 237 250 206)
                      (list 202 254 186 190) (list 127 69 76 70) (list 0 97 115 109) (list 31 139) (list 80 75 3 4)
                      (list 137 80 78 71 13 10 26 10) (list 255 216 255)))
      (hasNul? b n 0))

fn languageOf! path: String -> String
  (let [(ext (stringLower (extOf (k/baseName path))))]
    (if (stringEmpty? ext)
      (shebangLanguage! path)
      (optionOr (mapGet (mapFromPairs (list (pair ".asl" "asl") (pair ".asn" "asn") (pair ".ts" "typescript") (pair ".tsx" "typescript") (pair ".mts" "typescript") (pair ".cts" "typescript")
                                            (pair ".js" "javascript") (pair ".jsx" "javascript") (pair ".mjs" "javascript") (pair ".cjs" "javascript") (pair ".py" "python") (pair ".go" "go") (pair ".rs" "rust")
                                            (pair ".c" "c") (pair ".h" "c") (pair ".java" "java") (pair ".sh" "shell") (pair ".bash" "shell") (pair ".md" "markdown") (pair ".json" "json") (pair ".yaml" "yaml")
                                            (pair ".yml" "yaml") (pair ".toml" "toml")))
                        ext)
                "text")))

fn lastDot s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (k/charAt s i) ".") i) (else (lastDot s (- i 1))))

fn leadingDots s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (= (k/charAt s i) ".")) (leadingDots s (+ i 1)) i)

fn extOf base: String -> String
  (let [(d (lastDot base (- (stringLength base) 1)))]
    (if (and (> d 0) (< (leadingDots base 0) d)) (slice base d (stringLength base)) ""))

fn stripVersion s: String -> String
  (let [(n (stringLength s))]
    (if (and (> n 0) (let [(c (k/charAt s (- n 1)))] (or (= c ".") (digitByte? (charCode c)))))
      (stripVersion (slice s 0 (- n 1)))
      s))

fn shebangWord words: (List String) -> String
  (mt (listHead words)
    ((none) "text")
    ((some w)
      (let [(prog (k/baseName w))]
        (if (or (= prog "env") (stringStartsWith? w "-"))
          (shebangWord (tailOf words))
          (optionOr (mapGet (mapFromPairs (list (pair "python" "python") (pair "bash" "shell") (pair "sh" "shell") (pair "zsh" "shell") (pair "dash" "shell") (pair "ksh" "shell") (pair "node" "javascript")))
                            (stripVersion prog))
                    "text")))))

fn firstLineEnd b: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet b i) 10) (+ i 1)) (else (firstLineEnd b n (+ i 1))))

fn shebangLanguage! path: String -> String
  (mt (fileReadString path)
    ((err _) "text")
    ((ok t)
      (let [(head (slice t 0 (firstLineEnd (stringToBytes t) (min 256 (stringLength t)) 0)))]
        (if (stringStartsWith? head "#!")
          (shebangWord (pySplitWs (pyDecode (slice head 2 (stringLength head)))))
          "text"))))

fn blankSegment s: String -> String
  (stringJoin (map (fn [(part String)] -> String (stringRepeat " " (stringLength part))) (stringSplit s "\n")) "\n")

fn applyBlanks text: String ranges: (List (Pair Int64 Int64)) at: Int64 acc: (List String) -> String
  (mt (listHead ranges)
    ((none) (stringJoin (listReverse (cons (slice text at (stringLength text)) acc)) ""))
    ((some r)
      (let [(a (max at (pairFirst r))) (e (min (stringLength text) (pairSecond r)))]
        (if (>= a e)
          (applyBlanks text (optionOr (listTail ranges) (list)) at acc)
          (applyBlanks text (optionOr (listTail ranges) (list)) e (cons (blankSegment (slice text a e)) (cons (slice text at a) acc)))))))

fn findByte b: Bytes n: Int64 i: Int64 c: Int64 -> Int64
  (cond ((>= i n) -1) ((= (bytesGet b i) c) i) (else (findByte b n (+ i 1) c)))

fn lineEndFrom b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (findByte b n i 10))] (if (= j -1) n j))

fn aslStringEnd b: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) j)
    ((= (bytesGet b j) 34) j)
    ((= (bytesGet b j) 92) (aslStringEnd b n (+ j 2)))
    (else (aslStringEnd b n (+ j 1))))

fn maskAslLoop b: Bytes n: Int64 i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (let [(c (bytesGet b i))]
      (cond
        ((= c 59) (let [(j (lineEndFrom b n i))] (maskAslLoop b n j (cons (pair i j) acc))))
        ((= c 34) (let [(j (aslStringEnd b n (+ i 1)))] (maskAslLoop b n (+ j 1) (cons (pair i (min (+ j 1) n)) acc))))
        (else (maskAslLoop b n (+ i 1) acc)))))

fn maskAsl text: String -> String
  (applyBlanks text (maskAslLoop (stringToBytes text) (stringLength text) 0 (list)) 0 (list))

fn alphaB? c: Int64 -> Bool
  (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)))

fn wordB? c: Int64 -> Bool
  (or (alphaB? c) (digitByte? c) (= c 95) (>= c 128))

fn alnumB? c: Int64 -> Bool
  (or (alphaB? c) (digitByte? c) (>= c 128))

fn charLen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(w (seqLen (byteAt b n i)))] (if (= w 0) 1 (min w (- n i))))

fn startsAt? b: Bytes n: Int64 i: Int64 lit: String -> Bool
  (let [(lb (stringToBytes lit)) (ln (stringLength lit))]
    (and (<= (+ i ln) n) (listAll? (fn [(j Int64)] -> Bool (= (bytesGet b (+ i j)) (bytesGet lb j))) (range 0 ln))))

fn findLit b: Bytes n: Int64 i: Int64 lit: String -> Int64
  (cond ((> (+ i (stringLength lit)) n) -1) ((startsAt? b n i lit) i) (else (findLit b n (+ i 1) lit)))

fn quotedEnd b: Bytes n: Int64 j: Int64 qc: Int64 multiline: Bool -> Int64
  (if (>= j n)
    n
    (let [(ch (bytesGet b j))]
      (cond
        ((= ch 92) (quotedEnd b n (+ j 2) qc multiline))
        ((= ch qc) (+ j 1))
        ((and (= ch 10) (not multiline)) j)
        (else (quotedEnd b n (+ j 1) qc multiline)))))

fn pyPrefixByte? c: Int64 -> Bool
  (listContains? (list 114 82 98 66 117 85 102 70) c)

fn quoteLenAt b: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((or (startsAt? b n i "\"\"\"") (startsAt? b n i "'''")) 3)
    ((or (= (byteAt b n i) 34) (= (byteAt b n i) 39)) 1)
    (else 0))

fn pyStrStart b: Bytes n: Int64 i: Int64 -> (Option (Pair Int64 Int64))
  (cond
    ((and (pyPrefixByte? (byteAt b n i)) (pyPrefixByte? (byteAt b n (+ i 1))) (> (quoteLenAt b n (+ i 2)) 0)) (some (pair 2 (quoteLenAt b n (+ i 2)))))
    ((and (pyPrefixByte? (byteAt b n i)) (> (quoteLenAt b n (+ i 1)) 0)) (some (pair 1 (quoteLenAt b n (+ i 1)))))
    ((> (quoteLenAt b n i) 0) (some (pair 0 (quoteLenAt b n i))))
    (else (none)))

fn pyStrEnd b: Bytes n: Int64 j: Int64 q: String -> Int64
  (cond
    ((>= j n) j)
    ((= (bytesGet b j) 92) (pyStrEnd b n (+ j 2) q))
    ((startsAt? b n j q) (+ j (stringLength q)))
    ((and (= (stringLength q) 1) (= (bytesGet b j) 10)) j)
    (else (pyStrEnd b n (+ j 1) q)))

fn rustCommentEnd b: Bytes n: Int64 j: Int64 depth: Int64 -> Int64
  (cond
    ((>= j n) j)
    ((startsAt? b n j "/*") (rustCommentEnd b n (+ j 2) (+ depth 1)))
    ((startsAt? b n j "*/") (if (= (- depth 1) 0) (+ j 2) (rustCommentEnd b n (+ j 2) (- depth 1))))
    (else (rustCommentEnd b n (+ j 1) depth)))

fn templateEnd b: Bytes n: Int64 j: Int64 depth: Int64 -> Int64
  (if (>= j n)
    j
    (let [(ch (bytesGet b j))]
      (cond
        ((= ch 92) (templateEnd b n (+ j 2) depth))
        ((and (= ch 96) (= depth 0)) (+ j 1))
        ((startsAt? b n j "${") (templateEnd b n (+ j 2) (+ depth 1)))
        ((and (= ch 125) (> depth 0)) (templateEnd b n (+ j 1) (- depth 1)))
        (else (templateEnd b n (+ j 1) depth)))))

fn regexEnd b: Bytes n: Int64 j: Int64 inClass: Bool -> Int64
  (if (or (>= j n) (= (bytesGet b j) 10))
    -1
    (let [(ch (bytesGet b j))]
      (cond
        ((= ch 92) (regexEnd b n (+ j 2) inClass))
        (inClass (regexEnd b n (+ j 1) (not (= ch 93))))
        ((= ch 91) (regexEnd b n (+ j 1) true))
        ((= ch 47) (+ j 1))
        (else (regexEnd b n (+ j 1) inClass)))))

fn alphaRun b: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (or (alphaB? (bytesGet b j)) (>= (bytesGet b j) 128))) (alphaRun b n (+ j 1)) j)

fn regexAllowed? prevSig: Int64 prevWord: String -> Bool
  (or (= prevSig -1)
      (listContains? (list 40 44 61 58 91 33 38 124 63 123 125 59 43 45 42 37 60 62 126 94) prevSig)
      (and (= prevSig -2) (listContains? (list "return" "typeof" "case" "do" "else" "in" "of" "void" "yield" "await" "delete" "throw" "new" "instanceof") prevWord)))

fn identStart? c: Int64 -> Bool
  (or (alphaB? c) (= c 95) (= c 36))

fn identRun b: Bytes n: Int64 j: Int64 dot: Bool -> Int64
  (if (and (< j n) (let [(c (bytesGet b j))] (or (wordB? c) (= c 36) (and dot (= c 46)))))
    (identRun b n (+ j 1) dot)
    j)

fn hashRun b: Bytes n: Int64 j: Int64 -> Int64
  (if (= (byteAt b n j) 35) (hashRun b n (+ j 1)) j)

fn rustRawStart b: Bytes n: Int64 i: Int64 -> (Option (Pair Int64 Int64))
  (let [(r (if (and (= (byteAt b n i) 98) (= (byteAt b n (+ i 1)) 114)) (+ i 1) (if (= (byteAt b n i) 114) i -1)))]
    (if (< r 0)
      (none)
      (let [(h (hashRun b n (+ r 1)))]
        (if (= (byteAt b n h) 34) (some (pair (+ h 1) (- h r))) (none)))))

fn charsUntilQuote b: Bytes n: Int64 j: Int64 left: Int64 -> Int64
  (let [(c (byteAt b n j))]
    (if (or (= left 0) (< c 0) (= c 39) (= c 10)) j (charsUntilQuote b n (+ j (charLen b n j)) (- left 1))))

fn rustCharEnd b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c1 (byteAt b n (+ i 1)))]
    (cond
      ((and (= c1 92) (< (+ i 2) n) (not (= (byteAt b n (+ i 2)) 10)))
        (let [(j (charsUntilQuote b n (+ i 2 (charLen b n (+ i 2))) 8))] (if (= (byteAt b n j) 39) (+ j 1) -1)))
      ((or (< c1 0) (= c1 92) (= c1 39) (= c1 10)) -1)
      (else (let [(j (+ i 1 (charLen b n (+ i 1))))] (if (= (byteAt b n j) 39) (+ j 1) -1)))))

fn maskPython b: Bytes n: Int64 i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (if (= (bytesGet b i) 35)
      (let [(j (lineEndFrom b n i))] (maskPython b n j (cons (pair i j) acc)))
      (mt (pyStrStart b n i)
        ((none) (maskPython b n (+ i 1) acc))
        ((some m)
          (if (and (> (pairFirst m) 0) (> i 0) (let [(p (bytesGet b (- i 1)))] (or (alnumB? p) (= p 95))))
            (maskPython b n (+ i 1) acc)
            (let [(q (stringRepeat (if (= (bytesGet b (+ i (pairFirst m))) 34) "\"" "'") (pairSecond m)))
                  (j (pyStrEnd b n (+ i (pairFirst m) (pairSecond m)) q))]
              (maskPython b n j (cons (pair i j) acc))))))))

fn maskBrace lang: String b: Bytes n: Int64 i: Int64 prevSig: Int64 prevWord: String acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (let [(c (bytesGet b i)) (nx (byteAt b n (+ i 1))) (js (or (= lang "typescript") (= lang "javascript")))]
      (cond
        ((and (= c 47) (= nx 47)) (let [(j (lineEndFrom b n i))] (maskBrace lang b n j prevSig prevWord (cons (pair i j) acc))))
        ((and (= c 47) (= nx 42))
          (let [(j (if (= lang "rust") (rustCommentEnd b n i 0) (let [(e (findLit b n (+ i 2) "*/"))] (if (= e -1) n (+ e 2)))))]
            (maskBrace lang b n j prevSig prevWord (cons (pair i j) acc))))
        ((and js (or (= c 34) (= c 39))) (maskBrace lang b n (quotedEnd b n (+ i 1) c false) -2 prevWord (cons (pair i (quotedEnd b n (+ i 1) c false)) acc)))
        ((and js (= c 96)) (maskBrace lang b n (templateEnd b n (+ i 1) 0) -2 prevWord (cons (pair i (templateEnd b n (+ i 1) 0)) acc)))
        ((and js (= c 47) (regexAllowed? prevSig prevWord) (>= (regexEnd b n (+ i 1) false) 0))
          (let [(j (alphaRun b n (regexEnd b n (+ i 1) false)))] (maskBrace lang b n j -2 "" (cons (pair i j) acc))))
        ((and (= lang "go") (or (= c 34) (= c 39))) (maskBrace lang b n (quotedEnd b n (+ i 1) c false) -2 prevWord (cons (pair i (quotedEnd b n (+ i 1) c false)) acc)))
        ((and (= lang "go") (= c 96))
          (let [(e (findByte b n (+ i 1) 96)) (j (if (= e -1) n (+ e 1)))] (maskBrace lang b n j -2 prevWord (cons (pair i j) acc))))
        ((and (= lang "rust") (or (= c 114) (= c 98)) (or (= i 0) (not (let [(p (bytesGet b (- i 1)))] (or (alnumB? p) (= p 95))))) (some? (rustRawStart b n i)))
          (let [(m (optionOr (rustRawStart b n i) (pair i 0)))
                (closer (str "\"" (stringRepeat "#" (pairSecond m))))
                (e (findLit b n (pairFirst m) closer))
                (j (if (= e -1) n (+ e (stringLength closer))))]
            (maskBrace lang b n j prevSig prevWord (cons (pair i j) acc))))
        ((and (= lang "rust") (= c 34)) (maskBrace lang b n (quotedEnd b n (+ i 1) 34 true) prevSig prevWord (cons (pair i (quotedEnd b n (+ i 1) 34 true)) acc)))
        ((and (= lang "rust") (= c 39) (>= (rustCharEnd b n i) 0)) (maskBrace lang b n (rustCharEnd b n i) prevSig prevWord (cons (pair i (rustCharEnd b n i)) acc)))
        ((> (wsLen b n i) 0) (maskBrace lang b n (+ i (wsLen b n i)) prevSig prevWord acc))
        ((identStart? c) (let [(j (identRun b n (+ i 1) false))] (maskBrace lang b n j -2 (bytesSlice b i j) acc)))
        ((digitByte? c) (let [(j (identRun b n (+ i 1) true))] (maskBrace lang b n j -2 (bytesSlice b i j) acc)))
        (else (maskBrace lang b n (+ i 1) c "" acc)))))

fn bytesSlice b: Bytes a: Int64 e: Int64 -> String
  (stringJoin (map (fn [(j Int64)] -> String (asciiChar (bytesGet b j))) (range a e)) "")

fn asciiChar c: Int64 -> String
  (optionOr (stringSlice "\x00\x01\x02\x03\x04\x05\x06\x07\x08\t\n\x0b\x0c\r\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f" c (+ c 1)) "?")

fn maskCode text: String lang: String -> String
  (let [(b (stringToBytes text)) (n (stringLength text))]
    (cond
      ((= lang "python") (applyBlanks text (maskPython b n 0 (list)) 0 (list)))
      ((listContains? (list "typescript" "javascript" "go" "rust") lang) (applyBlanks text (maskBrace lang b n 0 -1 "" (list)) 0 (list)))
      (else text)))

fn spTab b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (= (byteAt b n i) 32) (= (byteAt b n i) 9)) (spTab b n (+ i 1)) i)

fn spTab1 b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (spTab b n i))] (if (> j i) j -1))

fn litAt b: Bytes n: Int64 i: Int64 word: String -> Int64
  (if (and (>= i 0) (startsAt? b n i word)) (+ i (stringLength word)) -1)

fn optKw b: Bytes n: Int64 i: Int64 word: String -> Int64
  (let [(e (litAt b n i word))]
    (if (< e 0) i (let [(s (spTab1 b n e))] (if (< s 0) i s))))

fn optKws b: Bytes n: Int64 i: Int64 words: (List String) -> Int64
  (fold (fn [(p Int64) (w String)] -> Int64 (optKw b n p w)) i words)

fn anyWordWs b: Bytes n: Int64 i: Int64 words: (List String) -> Int64
  (mt (listHead words)
    ((none) -1)
    ((some w)
      (let [(e (litAt b n i w)) (s (if (< e 0) -1 (spTab1 b n e)))]
        (if (>= s 0) s (anyWordWs b n i (tailOf words))))))

fn jsIdentEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (identStart? (byteAt b n i))) (identRun b n (+ i 1) false) -1)

fn pyIdentEnd b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (byteAt b n i))]
    (if (and (>= i 0) (or (alphaB? c) (= c 95))) (wordRun b n (+ i 1)) -1))

fn wordRun b: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (wordB? (bytesGet b j))) (wordRun b n (+ j 1)) j)

fn nameAt s: String a: Int64 e: Int64 -> (Option String)
  (if (and (>= a 0) (> e a)) (some (slice s a e)) (none))

fn identName s: String b: Bytes n: Int64 i: Int64 js: Bool -> (Option String)
  (if (< i 0) (none) (nameAt s i (if js (jsIdentEnd b n i) (pyIdentEnd b n i))))

fn lineStop b: Bytes n: Int64 i: Int64 stops: (List Int64) -> Int64
  (cond ((>= i n) n) ((listContains? stops (bytesGet b i)) i) (else (lineStop b n (+ i 1) stops)))

fn colonThenEq? b: Bytes n: Int64 p: Int64 -> Bool
  (cond
    ((= (byteAt b n p) 61) true)
    ((= (byteAt b n p) 58) (let [(q (lineStop b n (+ p 1) (list 61 10)))] (and (> q (+ p 1)) (= (byteAt b n q) 61))))
    (else false))

fn tsFunction s: String b: Bytes n: Int64 -> (Option String)
  (let [(i (optKws b n (spTab b n 0) (list "export" "default" "declare" "async")))
        (f (litAt b n i "function"))]
    (if (< f 0) (none) (identName s b n (spTab b n (if (= (byteAt b n f) 42) (+ f 1) f)) true)))

fn tsClass s: String b: Bytes n: Int64 -> (Option String)
  (let [(i (optKws b n (spTab b n 0) (list "export" "default" "declare" "abstract")))
        (c (litAt b n i "class"))]
    (if (< c 0) (none) (identName s b n (spTab1 b n c) true)))

fn tsInterface s: String b: Bytes n: Int64 -> (Option String)
  (identName s b n (anyWordWs b n (optKws b n (spTab b n 0) (list "export" "declare")) (list "interface" "enum" "namespace")) true)

fn lastGtOk? b: Bytes n: Int64 lt: Int64 stop: Int64 j: Int64 -> Bool
  (cond
    ((<= j lt) false)
    ((and (= (bytesGet b j) 62) (= (byteAt b n (spTab b n (+ j 1))) 61)) true)
    (else (lastGtOk? b n lt stop (- j 1))))

fn tsType s: String b: Bytes n: Int64 -> (Option String)
  (let [(t (litAt b n (optKws b n (spTab b n 0) (list "export" "declare")) "type"))
        (a (if (< t 0) -1 (spTab1 b n t)))
        (e (if (< a 0) -1 (jsIdentEnd b n a)))]
    (if (< e 0)
      (none)
      (let [(p (spTab b n e))
            (generic (and (= (byteAt b n p) 60) (let [(stop (lineStop b n (+ p 1) (list 61 10)))] (lastGtOk? b n p stop (- stop 1)))))]
        (if (or generic (= (byteAt b n p) 61)) (nameAt s a e) (none)))))

fn tsVariable s: String b: Bytes n: Int64 -> (Option String)
  (let [(k (anyWordWs b n (optKws b n 0 (list "export" "declare")) (list "const" "let" "var")))
        (e (if (< k 0) -1 (jsIdentEnd b n k)))]
    (if (and (>= e 0) (colonThenEq? b n (spTab b n e))) (nameAt s k e) (none)))

fn modifierStops b: Bytes n: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (let [(nx (anyWordWs b n i (list "public" "private" "protected" "static" "readonly" "async" "override" "abstract" "get" "set")))]
    (if (< nx 0) acc (modifierStops b n nx (cons nx acc))))

fn braceAfterParen? b: Bytes n: Int64 r: Int64 -> Bool
  (let [(p (spTab b n (+ r 1)))]
    (or (= (byteAt b n p) 123)
        (and (= (byteAt b n p) 58) (let [(q (lineStop b n (+ p 1) (list 10 123 59)))] (and (> q (+ p 1)) (= (byteAt b n q) 123))))))

fn anyCloseParen? b: Bytes n: Int64 j: Int64 lo: Int64 -> Bool
  (cond
    ((<= j lo) false)
    ((and (= (bytesGet b j) 41) (braceAfterParen? b n j)) true)
    (else (anyCloseParen? b n (- j 1) lo)))

fn methodRest? b: Bytes n: Int64 e: Int64 -> Bool
  (let [(p0 (spTab b n e))
        (p1 (if (= (byteAt b n p0) 60) (let [(g (lineStop b n (+ p0 1) (list 62 10)))] (if (= (byteAt b n g) 62) (spTab b n (+ g 1)) -1)) p0))]
    (and (>= p1 0) (= (byteAt b n p1) 40)
         (anyCloseParen? b n (- (lineEndFrom b n p1) 1) p1)))

fn methodAt s: String b: Bytes n: Int64 starts: (List Int64) -> (Option String)
  (mt (listHead starts)
    ((none) (none))
    ((some a)
      (let [(e (jsIdentEnd b n a))]
        (if (and (>= e 0) (methodRest? b n e)) (nameAt s a e) (methodAt s b n (optionOr (listTail starts) (list)))))))

fn tsMethod s: String b: Bytes n: Int64 -> (Option String)
  (let [(i (spTab1 b n 0))]
    (if (< i 0) (none) (methodAt s b n (modifierStops b n i (list i)))))

fn goRecvVariant b: Bytes n: Int64 q: Int64 -> Int64
  (let [(r (if (= (byteAt b n q) 42) (+ q 1) q))
        (e (pyIdentEnd b n r))
        (e2 (cond ((< e 0) -1) ((= (byteAt b n e) 91) (let [(g (lineStop b n (+ e 1) (list 93 10)))] (if (= (byteAt b n g) 93) (+ g 1) -1))) (else e)))]
    (if (and (>= e2 0) (= (byteAt b n e2) 41)) (spTab b n (+ e2 1)) -1))

fn goFunc s: String b: Bytes n: Int64 -> (Option String)
  (let [(f (litAt b n 0 "func")) (p (if (< f 0) -1 (spTab1 b n f)))]
    (if (< p 0)
      (none)
      (let [(withFirst (if (= (byteAt b n p) 40) (let [(e (pyIdentEnd b n (+ p 1))) (w (if (< e 0) -1 (spTab1 b n e)))] (if (< w 0) -1 (goRecvVariant b n w))) -1))
            (without (if (= (byteAt b n p) 40) (goRecvVariant b n (+ p 1)) -1))]
        (cond
          ((and (>= withFirst 0) (some? (identName s b n withFirst false))) (identName s b n withFirst false))
          ((and (>= without 0) (some? (identName s b n without false))) (identName s b n without false))
          (else (identName s b n p false))))))

fn goType s: String b: Bytes n: Int64 -> (Option String)
  (let [(t (litAt b n 0 "type"))] (if (< t 0) (none) (identName s b n (spTab1 b n t) false)))

fn goVariable s: String b: Bytes n: Int64 -> (Option String)
  (identName s b n (anyWordWs b n 0 (list "var" "const")) false)

fn rustPub b: Bytes n: Int64 i: Int64 -> Int64
  (let [(p (litAt b n i "pub"))]
    (if (< p 0)
      i
      (let [(withParen (if (= (byteAt b n p) 40) (let [(c (lineStop b n (+ p 1) (list 41 10)))] (if (= (byteAt b n c) 41) (spTab1 b n (+ c 1)) -1)) -1))
            (plain (spTab1 b n p))]
        (cond ((>= withParen 0) withParen) ((>= plain 0) plain) (else i)))))

fn rustModifier b: Bytes n: Int64 i: Int64 -> Int64
  (let [(simple (anyWordWs b n i (list "async" "unsafe" "const")))
        (ex (litAt b n i "extern"))]
    (cond
      ((>= simple 0) simple)
      ((< ex 0) -1)
      (else
        (let [(a (spTab1 b n ex))
              (abi (if (and (>= a 0) (= (byteAt b n a) 34)) (let [(q (lineStop b n (+ a 1) (list 34 10)))] (if (= (byteAt b n q) 34) (spTab1 b n (+ q 1)) -1)) -1))]
          (if (>= abi 0) abi (spTab1 b n ex))))))

fn rustModifiers b: Bytes n: Int64 i: Int64 -> Int64
  (let [(nx (rustModifier b n i))] (if (< nx 0) i (rustModifiers b n nx)))

fn rustFn s: String b: Bytes n: Int64 -> (Option String)
  (let [(f (litAt b n (rustModifiers b n (rustPub b n (spTab b n 0))) "fn"))]
    (if (< f 0) (none) (identName s b n (spTab1 b n f) false)))

fn rustType s: String b: Bytes n: Int64 -> (Option String)
  (identName s b n (anyWordWs b n (rustPub b n (spTab b n 0)) (list "struct" "enum" "trait" "type" "mod" "union" "static" "const")) false)

fn forAt b: Bytes n: Int64 p: Int64 -> Int64
  (let [(a (spTab1 b n p)) (f (if (< a 0) -1 (litAt b n a "for")))]
    (if (< f 0) -1 (spTab1 b n f)))

fn implFor s: String b: Bytes n: Int64 p: Int64 stop: Int64 -> (Option String)
  (if (> p stop)
    (none)
    (let [(a (forAt b n p)) (nm (identName s b n a false))]
      (if (and (>= a 0) (some? nm)) nm (implFor s b n (+ p 1) stop))))

fn implRest s: String b: Bytes n: Int64 c: Int64 -> (Option String)
  (if (< c 0)
    (none)
    (let [(viaFor (implFor s b n c (lineStop b n c (list 10 123))))]
      (if (some? viaFor) viaFor (identName s b n c false))))

fn rustImpl s: String b: Bytes n: Int64 -> (Option String)
  (let [(im (litAt b n (optKw b n (spTab b n 0) "unsafe") "impl"))]
    (if (< im 0)
      (none)
      (let [(g (spTab b n im))
            (withGen (if (= (byteAt b n g) 60) (let [(e (lineStop b n (+ g 1) (list 62 10)))] (if (= (byteAt b n e) 62) (implRest s b n (spTab1 b n (+ e 1))) (none))) (none)))]
        (if (some? withGen) withGen (implRest s b n (spTab1 b n im))))))

fn pyDef s: String b: Bytes n: Int64 -> (Option String)
  (let [(d (litAt b n (optKw b n (spTab b n 0) "async") "def"))]
    (if (< d 0) (none) (identName s b n (spTab1 b n d) false)))

fn pyClass s: String b: Bytes n: Int64 -> (Option String)
  (let [(c (litAt b n (spTab b n 0) "class"))]
    (if (< c 0) (none) (identName s b n (spTab1 b n c) false)))

fn pyVariable s: String b: Bytes n: Int64 -> (Option String)
  (let [(e (pyIdentEnd b n 0))]
    (if (< e 0)
      (none)
      (let [(p (spTab b n e))
            (q (cond ((= (byteAt b n p) 61) p)
                     ((= (byteAt b n p) 58) (let [(r (lineStop b n (+ p 1) (list 61 10)))] (if (and (> r (+ p 1)) (= (byteAt b n r) 61)) r -1)))
                     (else -1)))]
        (if (and (>= q 0) (not (= (byteAt b n (+ q 1)) 61))) (nameAt s 0 e) (none)))))

fn linePatterns lang: String -> (List (fn [String Bytes Int64] -> (Option String)))
  (cond
    ((or (= lang "typescript") (= lang "javascript")) (list tsFunction tsClass tsInterface tsType tsVariable tsMethod))
    ((= lang "go") (list goFunc goType goVariable))
    ((= lang "rust") (list rustFn rustType rustImpl))
    ((= lang "python") (list pyDef pyClass pyVariable))
    (else (list)))

fn notMethodName? nm: String -> Bool
  (listContains? (list "if" "for" "while" "switch" "catch" "function" "return" "with" "else" "do" "try" "new" "typeof" "await" "super") nm)

fn firstPattern line: String pats: (List (fn [String Bytes Int64] -> (Option String))) idx: Int64 -> (Option (Pair Int64 String))
  (mt (listHead pats)
    ((none) (none))
    ((some p)
      (mt (p line (stringToBytes line) (stringLength line))
        ((some nm) (some (pair idx nm)))
        ((none) (firstPattern line (optionOr (listTail pats) (list)) (+ idx 1))))))

fn aslHeads -> (List String)
  (list "fn" "defn" "defun" "schema" "defschema" "enum" "defenum" "macro" "struct" "def" "df" "dfs" "const" "type" "test" "deftest" "export")

fn wsRun1 b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (skipWsFwd b n i))] (if (> j i) j -1))

fn headThenWs b: Bytes n: Int64 i: Int64 tabsOnly: Bool -> Int64
  (fold (fn [(best Int64) (h String)] -> Int64
          (if (>= best 0)
            best
            (let [(e (litAt b n i h))]
              (if (< e 0) -1 (if tabsOnly (spTab1 b n e) (wsRun1 b n e))))))
        -1
        (aslHeads))

fn nameByte? b: Bytes n: Int64 i: Int64 -> Bool
  (and (< i n) (= (wsLen b n i) 0) (not (listContains? (list 40 41 91 93 123 125 34 59 44) (bytesGet b i))))

fn nameRun b: Bytes n: Int64 i: Int64 -> Int64
  (if (nameByte? b n i) (nameRun b n (+ i 1)) i)

fn aslNameEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (nameByte? b n i)) (nameRun b n i) -1)

fn kwRun b: Bytes n: Int64 i: Int64 extra: (List Int64) -> Int64
  (if (and (< i n) (let [(c (bytesGet b i))] (or (wordB? c) (= c 45) (listContains? extra c)))) (kwRun b n (+ i 1) extra) i)

fn keywordEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (= (byteAt b n i) 58) (alphaB? (byteAt b n (+ i 1)))) (kwRun b n (+ i 2) (list)) -1)

fn openParen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(p (skipWsFwd b n i))] (if (= (byteAt b n p) 40) (skipWsFwd b n (+ p 1)) -1))

fn aslParenDef s: String b: Bytes n: Int64 i: Int64 -> (Option String)
  (let [(p (openParen b n i)) (h (if (< p 0) -1 (headThenWs b n p false)))]
    (if (< h 0) (none) (nameAt s h (aslNameEnd b n h))))

fn aslIdDef s: String b: Bytes n: Int64 i: Int64 -> (Option String)
  (let [(p (openParen b n i))
        (k (keywordEnd b n p))
        (w (if (< k 0) -1 (wsRun1 b n k)))
        (id (if (< w 0) -1 (litAt b n w ":id")))
        (v (if (< id 0) -1 (wsRun1 b n id)))
        (a (if (and (>= v 0) (= (byteAt b n v) 34)) (+ v 1) v))]
    (if (< a 0) (none) (nameAt s a (aslNameEnd b n a))))

fn aslKwDef s: String b: Bytes n: Int64 i: Int64 allowEnd: Bool -> (Option String)
  (let [(p (openParen b n i))
        (k (keywordEnd b n p))
        (w (if (< k 0) -1 (wsRun1 b n k)))
        (a (if (and (>= w 0) (= (byteAt b n w) 58) (alphaB? (byteAt b n (+ w 1)))) (+ w 1) -1))
        (e (if (< a 0) -1 (kwRun b n (+ a 1) (list 63 33))))
        (after (if (< e 0) -1 (skipWsFwd b n e)))]
    (if (and (>= after 0) (or (= (byteAt b n after) 58) (= (byteAt b n after) 41) (and allowEnd (>= after n))))
      (nameAt s a e)
      (none)))

fn skipBang b: Bytes n: Int64 h: Int64 -> Int64
  (if (and (>= h 0) (and (< (+ h 1) n) (= (bytesGet b h) 33)))
    (let [(after (spTab1 b n (+ h 1)))] (if (< after 0) h after))
    h)

fn aslIndentDef s: String b: Bytes n: Int64 -> (Option String)
  (let [(h (skipBang b n (headThenWs b n 0 true)))]
    (if (< h 0) (none) (nameAt s h (aslNameEnd b n h))))

fn orElse a: (Option String) b: (fn [] -> (Option String)) -> (Option String)
  (if (some? a) a (b))

fn definitionName line: String lang: String -> String
  (let [(b (stringToBytes line)) (n (stringLength line))]
    (if (or (= lang "asl") (= lang "asn"))
      (optionOr (orElse (aslParenDef line b n 0)
                        (fn [] -> (Option String) (orElse (aslIdDef line b n 0)
                          (fn [] -> (Option String) (orElse (aslIndentDef line b n)
                            (fn [] -> (Option String) (aslKwDef line b n 0 true)))))))
                "")
      (mt (firstPattern line (linePatterns lang) 0)
        ((none) "")
        ((some hit) (if (notMethodName? (pairSecond hit)) "" (pairSecond hit))))))

(schema AslScan (:f stack (List (Pair Int64 (Pair Int64 Int64)))) (:f inStr Bool) (:f esc Bool) (:f inComment Bool) (:f line Int64) (:f depths (List Int64)) (:f syms (List (Pair Int64 String))))

fn parenSym s: String b: Bytes n: Int64 start: Int64 -> (Option String)
  (orElse (aslParenDef s b n start) (fn [] -> (Option String) (orElse (aslIdDef s b n start) (fn [] -> (Option String) (aslKwDef s b n start false)))))

fn aslScanStep s: String b: Bytes n: Int64 i: Int64 st: AslScan -> AslScan
  (if (>= i n)
    st
    (let [(c (bytesGet b i))]
      (cond
        (st.inComment
          (aslScanStep s b n (+ i 1) (if (= c 10) (with st :inStr false :esc false :inComment false :line (+ st.line 1) :depths (cons (listLength st.stack) st.depths)) st)))
        (st.inStr
          (aslScanStep s b n (+ i 1)
            (cond
              (st.esc (with st :inStr true :esc false :inComment false))
              ((= c 92) (with st :inStr true :esc true :inComment false))
              ((= c 34) (with st :inStr false :esc false :inComment false))
              ((= c 10) (with st :inStr true :esc false :inComment false :line (+ st.line 1) :depths (cons -1 st.depths)))
              (else st))))
        ((= c 10) (aslScanStep s b n (+ i 1) (with st :inStr false :esc false :inComment false :line (+ st.line 1) :depths (cons (listLength st.stack) st.depths))))
        ((= c 34) (aslScanStep s b n (+ i 1) (with st :inStr true :esc false :inComment false)))
        ((= c 59) (aslScanStep s b n (+ i 1) (with st :inStr false :esc false :inComment true)))
        ((or (= c 40) (= c 91) (= c 123))
          (aslScanStep s b n (+ i 1) (with st :stack (cons (pair c (pair i st.line)) st.stack) :inStr false :esc false :inComment false)))
        ((or (= c 41) (= c 93) (= c 125))
          (mt (listHead st.stack)
            ((none) (aslScanStep s b n (+ i 1) st))
            ((some top)
              (let [(rest (optionOr (listTail st.stack) (list)))
                    (found (if (= (pairFirst top) 40) (parenSym s b n (pairFirst (pairSecond top))) (none)))
                    (syms (mt found ((some nm) (cons (pair (+ (pairSecond (pairSecond top)) 1) nm) st.syms)) ((none) st.syms)))]
                (aslScanStep s b n (+ i 1) (with st :stack rest :inStr false :esc false :inComment false :syms syms))))))
        (else (aslScanStep s b n (+ i 1) st)))))

fn indentSyms lines: (List String) depths: (List Int64) li: Int64 acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (mt (listHead lines)
    ((none) acc)
    ((some ln)
      (let [(d (optionOr (listHead depths) -1))
            (first (k/charAt ln 0))
            (hit (if (and (= d 0) (not (stringEmpty? ln)) (not (listContains? (list " " "\t" "(" ";") first)))
                   (aslIndentDef ln (stringToBytes ln) (stringLength ln))
                   (none)))]
        (indentSyms (tailOf lines) (optionOr (listTail depths) (list)) (+ li 1)
                    (mt hit ((some nm) (cons (pair (+ li 1) nm) acc)) ((none) acc))))))

fn aslDefLines text: String -> (List (Pair Int64 String))
  (let [(b (stringToBytes text)) (n (stringLength text))
        (st (aslScanStep text b n 0 (AslScan :stack (list) :inStr false :esc false :inComment false :line 0 :depths (list 0) :syms (list))))]
    (listAppend st.syms (indentSyms (stringSplit text "\n") (listReverse st.depths) 0 (list))))

fn patternDefLines lines: (List String) lang: String li: Int64 acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (mt (listHead lines)
    ((none) acc)
    ((some ln)
      (let [(hit (firstPattern ln (linePatterns lang) 0))
            (keep (mt hit ((none) (none)) ((some h) (if (and (= (pairFirst h) 5) (notMethodName? (pairSecond h))) (none) (some (pairSecond h))))))]
        (patternDefLines (tailOf lines) lang (+ li 1) (mt keep ((some nm) (cons (pair (+ li 1) nm) acc)) ((none) acc))))))

fn defLines text: String lang: String -> (List (Pair Int64 String))
  (cond
    ((or (= lang "asl") (= lang "asn")) (aslDefLines text))
    ((listContains? (list "typescript" "javascript" "go" "rust" "python") lang) (patternDefLines (stringSplit (maskCode text lang) "\n") lang 0 (list)))
    (else (list)))

fn addSkipped acc: ScanAcc rel: String -> ScanAcc
  (with acc :skipped (if (listContains? acc.skipped rel) acc.skipped (cons rel acc.skipped)))

fn addHit acc: ScanAcc h: Hit cap: Int64 -> ScanAcc
  (with acc :hits (cons h acc.hits) :count (+ acc.count 1) :capped (>= (+ acc.count 1) cap))

fn firstColon s: String from: Int64 -> Int64
  (optionOr (optionMap (fn [(j Int64)] -> Int64 (+ j from)) (stringIndexOf (slice s from (stringLength s)) ":")) -1)

fn gitHitOf line: String -> (Option Hit)
  (let [(c1 (firstColon line 0)) (c2 (if (< c1 0) -1 (firstColon line (+ c1 1))))]
    (if (and (>= c2 0) (allDigits? (slice line (+ c1 1) c2)))
      (some (Hit :rel (slice line 0 c1) :no (optionOr (stringToInt64 (slice line (+ c1 1) c2)) 0) :line (slice line (+ c2 1) (stringLength line))))
      (none)))

fn binaryMatch line: String -> String
  (if (and (stringStartsWith? line "Binary file ") (stringEndsWith? line " matches") (> (stringLength line) 20))
    (slice line 12 (- (stringLength line) 8))
    "")

fn gitScan! ws: String lines: (List String) cap: Int64 acc: ScanAcc -> ScanAcc
  (mt (listHead lines)
    ((none) acc)
    ((some line)
      (let [(next (mt (gitHitOf line)
                    ((some h) (if (binaryOf! (k/joinPath ws h.rel)) (addSkipped acc h.rel) (addHit acc h cap)))
                    ((none) (let [(bin (binaryMatch line))] (if (stringEmpty? bin) acc (addSkipped acc bin))))))]
        (if next.capped next (gitScan! ws (tailOf lines) cap next)))))

fn textLines text: String -> (List String)
  (let [(parts (stringSplit text "\n"))]
    (if (stringEndsWith? text "\n") (listTake parts (- (listLength parts) 1)) (if (stringEmpty? text) (list) parts)))

fn scanTextLines rel: String lines: (List String) no: Int64 low: String cap: Int64 acc: ScanAcc -> ScanAcc
  (mt (listHead lines)
    ((none) acc)
    ((some ln)
      (let [(next (if (stringContains? (stringLower ln) low) (addHit acc (Hit :rel rel :no no :line ln) cap) acc))]
        (if next.capped next (scanTextLines rel (tailOf lines) (+ no 1) low cap next)))))

fn scanFile! fp: String rel: String low: String cap: Int64 acc: ScanAcc -> ScanAcc
  (mt (fileSize fp)
    ((err _) acc)
    ((ok size)
      (cond
        ((> size (* 2 1048576)) acc)
        ((binaryOf! fp) (mt (fileReadString fp) ((ok raw) (if (stringContains? (stringLower raw) low) (addSkipped acc rel) acc)) ((err _) acc)))
        (else (mt (readText! fp) ((some t) (scanTextLines rel (textLines t) 1 low cap acc)) ((none) acc))))))

fn querySkipDir? name: String -> Bool
  (listContains? (list ".git" "node_modules" ".asl" "dist" "build" "target" "__pycache__" ".venv" "venv" ".next" "vendor") name)

fn walkScan! ws: String dir: String low: String cap: Int64 acc: ScanAcc -> ScanAcc
  (mt (dirList dir)
    ((err _) acc)
    ((ok raw)
      (let [(names (listSort raw))
            (isDirs (map (fn [(nm String)] -> Bool (k/isDir! (k/joinPath dir nm))) names))
            (pairs (zip names isDirs))
            (files (map pairFirst (filter (fn [(p (Pair String Bool))] -> Bool (not (pairSecond p))) pairs)))
            (dirs (filter (fn [(nm String)] -> Bool (not (querySkipDir? nm))) (map pairFirst (filter pairSecond pairs))))
            (afterFiles (fold (fn [(a ScanAcc) (f String)] -> ScanAcc
                                (if a.capped a (let [(fp (k/joinPath dir f))] (scanFile! fp (k/relPath fp ws) low cap a))))
                              acc files))]
        (fold (fn [(a ScanAcc) (d String)] -> ScanAcc
                (if (or a.capped (not (k/realChild? dir d))) a (walkScan! ws (k/joinPath dir d) low cap a)))
              afterFiles dirs))))

fn emptyScan -> ScanAcc
  (ScanAcc :hits (list) :count 0 :capped false :skipped (list) :failed "")

fn queryLines! ws: String q: String cap: Int64 -> ScanAcc
  (let [(isGit (or (k/isDir! (k/joinPath ws ".git")) (k/isFile! (k/joinPath ws ".git"))))
        (argv (list "git" "-C" ws "grep" "-n" "-i" "-F" "--no-color" "--untracked" "-e" q))
        (viaGit (if isGit (some (runArgv! argv ws 600000)) (none)))]
    (mt viaGit
      ((none) (walkFallback! ws q cap))
      ((some res)
        (mt res
          ((ok out) (gitScan! ws (stringSplit (k/universalNewlines (pyDecode out.stdout)) "\n") cap (emptyScan)))
          ((err e)
            (mt e
              ((cp/timeout ms) (ScanAcc :hits (list) :count 0 :capped false :skipped (list) :failed (procErrorMessage argv e)))
              (_ (walkFallback! ws q cap))))))))

fn walkFallback! ws: String q: String cap: Int64 -> ScanAcc
  (walkScan! ws ws (stringLower q) cap (emptyScan))

fn queryKind! ws: String rel: String -> String
  (let [(low (str "/" rel)) (base (k/baseName rel)) (lang (languageOf! (k/joinPath ws rel)))]
    (cond
      ((or (stringStartsWith? low "/.asl/mem/") (stringContains? low "/memory/") (= base "MEMORY.md") (= base "memory.md")) "memory")
      ((listContains? (list "asl" "typescript" "javascript" "python" "go" "rust" "c" "java" "shell") lang) "code")
      ((or (= lang "markdown") (= lang "text")) "doc")
      (else "data")))

(schema FileView (:f rel String) (:f text (Option String)) (:f masked (List String)))

fn viewOf! ws: String rel: String -> FileView
  (let [(t (readText! (k/joinPath ws rel))) (lang (languageOf! (k/joinPath ws rel)))]
    (FileView :rel rel :text t
              :masked (mt t ((some x) (stringSplit (if (= lang "asl") (maskAsl x) (maskCode x lang)) "\n")) ((none) (list)))))

fn codeUse? v: FileView h: Hit low: String -> Bool
  (if (or (none? v.text) (>= (- h.no 1) (listLength v.masked)))
    true
    (stringContains? (stringLower (optionOr (listGet v.masked (- h.no 1)) "")) low))

(schema Split (:f code (List Hit)) (:f comment (List Hit)) (:f doc (List Hit)) (:f memory (List Hit)) (:f data (List Hit)) (:f view (Option FileView)))

fn splitHit! ws: String low: String sp: Split h: Hit -> Split
  (let [(kind (queryKind! ws h.rel))]
    (if (= kind "code")
      (let [(v (mt sp.view ((some cur) (if (= cur.rel h.rel) cur (viewOf! ws h.rel))) ((none) (viewOf! ws h.rel))))]
        (if (codeUse? v h low)
          (with sp :code (cons h sp.code) :view (some v))
          (with sp :comment (cons h sp.comment) :view (some v))))
      (cond
        ((= kind "doc") (with sp :doc (cons h sp.doc)))
        ((= kind "memory") (with sp :memory (cons h sp.memory)))
        (else (with sp :data (cons h sp.data))))))

fn padNo no: Int64 -> String
  (let [(s (stringFromInt64 no))] (str (stringRepeat "0" (max 0 (- 12 (stringLength s)))) s))

fn candKey c: Cand -> String
  (str (stringFromInt64 c.score) c.rel "\x00" (padNo c.no))

(schema Confirm (:f defs (List Cand)) (:f rejected (List Hit)) (:f index (Map String (List (Pair Int64 String)))))

fn confirmCands! ws: String cands: (List Cand) limit: Int64 st: Confirm -> Confirm
  (mt (listHead cands)
    ((none) st)
    ((some c)
      (if (>= (listLength st.defs) limit)
        st
        (let [(idx (mt (mapGet st.index c.rel)
                     ((some x) x)
                     ((none) (mt (readText! (k/joinPath ws c.rel)) ((some t) (defLines t (languageOf! (k/joinPath ws c.rel)))) ((none) (list))))))
              (index (mapSet st.index c.rel idx))
              (ok (listAny? (fn [(p (Pair Int64 String))] -> Bool (and (= (pairFirst p) c.no) (= (pairSecond p) c.name))) idx))]
          (confirmCands! ws (optionOr (listTail cands) (list)) limit
                        (if ok
                          (with st :defs (listAppend st.defs (list c)) :index index)
                          (with st :rejected (listAppend st.rejected (list (Hit :rel c.rel :no c.no :line c.line))) :index index)))))))

fn lineStarts b: Bytes n: Int64 i: Int64 want: Int64 acc: (List Int64) count: Int64 -> (List Int64)
  (cond
    ((> count want) (listReverse acc))
    ((>= i n) (listReverse acc))
    ((= (bytesGet b i) 10) (lineStarts b n (+ i 1) want (cons (+ i 1) acc) (+ count 1)))
    (else (lineStarts b n (+ i 1) want acc count)))

fn countAnchor t: String b: Bytes anchor: String pos: Int64 i: Int64 k: Int64 -> Int64
  (if (or (= i -1) (> i pos)) k (countAnchor t b anchor pos (k/findFrom t b anchor (+ i 1)) (+ k 1)))

fn occurrence! ws: String h: Hit anchor: String -> Int64
  (mt (readText! (k/joinPath ws h.rel))
    ((none) 1)
    ((some t)
      (let [(b (stringToBytes t))
            (starts (lineStarts b (stringLength t) 0 h.no (list 0) 1))
            (pos (if (< (- h.no 1) (listLength starts)) (+ (optionOr (listGet starts (- h.no 1)) 0) (pyLstripLen h.line)) 0))]
        (max 1 (countAnchor t b anchor pos (k/findFrom t b anchor 0) 0)))))

fn cellOf! ws: String h: Hit -> String
  (let [(excerpt (utf8Take (pyStrip h.line) 60)) (n (occurrence! ws h excerpt)) (cell (quoted excerpt))]
    (if (> n 1) (str "(" cell " " (stringFromInt64 n) ")") cell))

fn groupCells! ws: String hits: (List Hit) order: (List String) cells: (Map String (List String)) -> (List String)
  (mt (listHead hits)
    ((none) (map (fn [(rel String)] -> String (str (quoted rel) " (" (stringJoin (optionOr (mapGet cells rel) (list)) " ") ")")) (listReverse order)))
    ((some h)
      (let [(rel h.rel) (have (mapGet cells rel))]
        (groupCells! ws (optionOr (listTail hits) (list)) (if (some? have) order (cons rel order))
                    (mapSet cells rel (listAppend (optionOr have (list)) (list (cellOf! ws h))))))))

fn countPairs sp: Split -> (List (Pair String Int64))
  (filter (fn [(p (Pair String Int64))] -> Bool (> (pairSecond p) 0))
          (list (pair "comment" (listLength sp.comment)) (pair "doc" (listLength sp.doc)) (pair "memory" (listLength sp.memory)) (pair "data" (listLength sp.data))))

fn workspaceQuery! ws: String q: String limit: Int64 scope: String -> QueryResult
  (let [(scan (queryLines! ws q 5000))]
    (if (not (stringEmpty? scan.failed))
      (QueryResult :defs (list) :hits (list) :more 0 :capped false :binSkipped 0 :sections (list) :elsewhere (list) :failed scan.failed)
      (let [(low (stringLower q))
            (sp0 (fold (fn [(s Split) (h Hit)] -> Split (splitHit! ws low s h)) (Split :code (list) :comment (list) :doc (list) :memory (list) :data (list) :view (none)) (listReverse scan.hits)))
            (sp (Split :code (listReverse sp0.code) :comment (listReverse sp0.comment) :doc (listReverse sp0.doc) :memory (listReverse sp0.memory) :data (listReverse sp0.data) :view (none)))
            (lines (if (or (= scope "code") (= scope "all")) sp.code (list)))
            (named (map (fn [(h Hit)] -> (Pair Hit String) (pair h (definitionName h.line (languageOf! (k/joinPath ws h.rel))))) lines))
            (isCand (fn [(p (Pair Hit String))] -> Bool (and (not (stringEmpty? (pairSecond p))) (stringContains? (stringLower (pairSecond p)) low))))
            (cands (listSortBy candKey
                     (map (fn [(p (Pair Hit String))] -> Cand
                            (let [(nm (pairSecond p)) (lnm (stringLower (pairSecond p))) (h (pairFirst p))]
                              (Cand :score (cond ((= lnm low) 0) ((stringStartsWith? lnm low) 1) (else 2)) :rel h.rel :no h.no :name nm :line h.line)))
                          (filter isCand named))))
            (plain (map pairFirst (filter (fn [(p (Pair Hit String))] -> Bool (not (isCand p))) named)))
            (conf (confirmCands! ws cands limit (Confirm :defs (list) :rejected (list) :index (mapEmpty))))
            (texts (listAppend conf.rejected plain))
            (shownDefs (map (fn [(c Cand)] -> String (quoted (str c.rel "#" c.name))) (listTake conf.defs limit)))
            (shownTexts (listTake texts (max 0 (- limit (listLength shownDefs)))))
            (hits (groupCells! ws shownTexts (list) (mapEmpty)))
            (more0 (+ (max 0 (- (listLength conf.defs) (listLength shownDefs))) (max 0 (- (listLength texts) (listLength shownTexts)))))
            (kinds (list (pair "comment" sp.comment) (pair "doc" sp.doc) (pair "memory" sp.memory) (pair "data" sp.data)))
            (textScope (or (= scope "text") (= scope "all")))
            (sections (if textScope
                        (filter (fn [(p (Pair String (List String)))] -> Bool (not (listEmpty? (pairSecond p))))
                                (map (fn [(kp (Pair String (List Hit)))] -> (Pair String (List String)) (pair (pairFirst kp) (groupCells! ws (listTake (pairSecond kp) limit) (list) (mapEmpty)))) kinds))
                        (list)))
            (moreText (if textScope (listSum (map (fn [(kp (Pair String (List Hit)))] -> Int64 (max 0 (- (listLength (pairSecond kp)) limit))) kinds)) 0))]
        (QueryResult :defs shownDefs :hits hits :more (+ more0 moreText) :capped scan.capped :binSkipped (listLength scan.skipped)
                     :sections sections :elsewhere (if (= scope "code") (countPairs sp) (list)) :failed ""))))

fn queryStep! ctx: KnowCtx id: Int64 kw: (Map String String) args: (List String) -> KnowOutcome
  (let [(qText (k/kwOr kw "text" (k/kwOr kw "query" (optionOr (listHead args) ""))))
        (limit (max 1 (min 200 (optionOr (pyInt (k/kwOr kw "limit" "20")) 20))))
        (qIn (k/lstripColons (k/kwOr kw "in" "code")))]
    (cond
      ((stringEmpty? qText) (rejectedLine id "q" "ERR_MISSING_ARG" " :message \"Missing query text\""))
      ((not (listContains? (list "code" "text" "all") qIn)) (rejectedLine id "q" "ERR_QUERY_FAILED" (str " :message " (quoted (str ":in takes code, text or all, got " qIn)))))
      (else
        (let [(r (workspaceQuery! ctx.ws qText limit qIn))]
          (if (not (stringEmpty? r.failed))
            (rejectedLine id "q" "ERR_QUERY_FAILED" (str " :message " (quoted r.failed)))
            (let [(more (str (if (> r.more 0) (str " :more " (stringFromInt64 r.more)) "")
                             (if (> r.binSkipped 0) (str " :binarySkipped " (stringFromInt64 r.binSkipped)) "")
                             (if (listEmpty? r.elsewhere) ""
                               (str " :text (" (stringJoin (map (fn [(p (Pair String Int64))] -> String (str ":" (pairFirst p) " " (stringFromInt64 (pairSecond p)))) r.elsewhere) " ") ") :see \"(:query :text ... :in text)\""))))
                  (codePart (if (or (= qIn "code") (= qIn "all")) (str " :defs (" (stringJoin r.defs " ") ") :hits (" (stringJoin r.hits " ") ")") ""))
                  (secPart (stringJoin (map (fn [(p (Pair String (List String)))] -> String (str " :" (pairFirst p) " (" (stringJoin (pairSecond p) " ") ")")) r.sections) ""))]
              (okLine (str (stepHead id "q") " :status \"ok\" :in :" qIn codePart secPart more (if r.capped " :scanCapped true" "") ")"))))))))

fn notesSkeleton -> String
  ";; Machine-Native Observations & Technical Notes Ledger\n(:notesLedger\n  :version \"1.0.0\"\n  :notes [\n  ]\n)\n"

fn ledgerPath ctx: KnowCtx -> String
  (k/joinPath (k/joinPath (k/joinPath ctx.ws ".asl") "mem") "notes.asn")

fn literalEnd b: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (bytesGet b j) 34) (+ j 1))
    ((= (bytesGet b j) 92) (if (or (>= (+ j 1) n) (= (bytesGet b (+ j 1)) 10)) -1 (literalEnd b n (+ j 2))))
    (else (literalEnd b n (+ j 1))))

fn noteFormAt? b: Bytes n: Int64 i: Int64 -> Bool
  (and (startsAt? b n i "(:note") (> (wsLen b n (+ i 6)) 0))

fn countNotes b: Bytes n: Int64 i: Int64 acc: Int64 -> Int64
  (cond
    ((>= i n) acc)
    ((= (bytesGet b i) 34) (let [(e (literalEnd b n (+ i 1)))] (if (< e 0) (countNotes b n (+ i 1) acc) (countNotes b n e acc))))
    ((noteFormAt? b n i) (countNotes b n (+ i 6) (+ acc 1)))
    (else (countNotes b n (+ i 1) acc)))

fn notesCount text: String -> Int64
  (countNotes (stringToBytes text) (stringLength text) 0 0)

fn noteStarts b: Bytes n: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (cond ((>= i n) (listReverse acc)) ((noteFormAt? b n i) (noteStarts b n (+ i 1) (cons i acc))) (else (noteStarts b n (+ i 1) acc)))

fn digitRun b: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (digitByte? (bytesGet b j))) (digitRun b n (+ j 1)) j)

fn noteIds s: String b: Bytes n: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (let [(at (k/findFrom s b ":id \"n" i))]
    (if (< at 0)
      acc
      (let [(d (+ at 6)) (e (digitRun b n d))]
        (noteIds s b n (+ at 1) (if (and (> e d) (= (byteAt b n e) 34)) (cons (optionOr (stringToInt64 (slice s d e)) 0) acc) acc)))))

fn firstIdValue s: String -> String
  (let [(b (stringToBytes s)) (n (stringLength s)) (at (k/findFrom s b ":id \"" 0))]
    (if (< at 0)
      ""
      (let [(e (findByte b n (+ at 5) 34))]
        (if (> e (+ at 5)) (slice s (+ at 5) e) (firstIdValueFrom s b n (+ at 1))))))

fn firstIdValueFrom s: String b: Bytes n: Int64 from: Int64 -> String
  (let [(at (k/findFrom s b ":id \"" from))]
    (if (< at 0)
      ""
      (let [(e (findByte b n (+ at 5) 34))]
        (if (> e (+ at 5)) (slice s (+ at 5) e) (firstIdValueFrom s b n (+ at 1))))))

fn closingVectorAt text: String -> Int64
  (let [(b (stringToBytes text)) (n (stringLength text))
        (e1 (skipWsBack b n 0 n))]
    (if (not (= (byteAt b n (- e1 1)) 41))
      -1
      (let [(e2 (skipWsBack b n 0 (- e1 1)))]
        (if (not (= (byteAt b n (- e2 1)) 93))
          -1
          (let [(e3 (skipTabsBack b (- e2 1)))]
            (if (= (byteAt b n (- e3 1)) 10) (- e3 1) -1))))))

fn skipTabsBack b: Bytes i: Int64 -> Int64
  (if (and (> i 0) (or (= (bytesGet b (- i 1)) 32) (= (bytesGet b (- i 1)) 9))) (skipTabsBack b (- i 1)) i)

(schema DelimScan (:f stack (List (Pair Int64 Int64))) (:f inStr Bool) (:f strStart Int64) (:f inComment Bool))

fn closerOf c: Int64 -> Int64
  (cond ((= c 40) 41) ((= c 91) 93) (else 125))

fn charOf c: Int64 -> String
  (cond ((= c 40) "(") ((= c 41) ")") ((= c 91) "[") ((= c 93) "]") ((= c 123) "{") (else "}"))

fn delimError b: Bytes n: Int64 i: Int64 st: DelimScan -> String
  (if (>= i n)
    (cond
      (st.inStr "unterminated string literal")
      ((not (listEmpty? st.stack))
        (str "unclosed delimiter '" (charOf (pairFirst (optionOr (listHead st.stack) (pair 40 0)))) "' (" (stringFromInt64 (listLength st.stack)) " open containers remain)"))
      (else ""))
    (let [(c (bytesGet b i))]
      (cond
        (st.inComment (delimError b n (+ i 1) (if (= c 10) (with st :inStr false :inComment false) st)))
        (st.inStr
          (cond
            ((= c 92) (delimError b n (+ i 2) st))
            ((= c 34) (delimError b n (+ i 1) (with st :inStr false :inComment false)))
            (else (delimError b n (+ i 1) st))))
        ((= c 34) (delimError b n (+ i 1) (with st :inStr true :strStart i :inComment false)))
        ((= c 59) (delimError b n (+ i 1) (with st :inStr false :inComment true)))
        ((or (= c 40) (= c 91) (= c 123)) (delimError b n (+ i 1) (with st :stack (cons (pair c i) st.stack) :inStr false :inComment false)))
        ((or (= c 41) (= c 93) (= c 125))
          (mt (listHead st.stack)
            ((none) (str "unexpected closing delimiter '" (charOf c) "' at byte " (stringFromInt64 i)))
            ((some top)
              (if (= (closerOf (pairFirst top)) c)
                (delimError b n (+ i 1) (with st :stack (optionOr (listTail st.stack) (list)) :inStr false :inComment false))
                (str "mismatched delimiter '" (charOf c) "' (expected '" (charOf (closerOf (pairFirst top))) "') at byte " (stringFromInt64 i))))))
        (else (delimError b n (+ i 1) st)))))

fn delimiterError text: String -> String
  (delimError (stringToBytes text) (stringLength text) 0 (DelimScan :stack (list) :inStr false :strStart -1 :inComment false))

fn ! linkAt? p: String -> Bool
  (let [(name (k/baseName p)) (listed (mt (dirList (k/dirName p)) ((ok names) (listContains? names name)) ((err _) false)))]
    (and listed (!= (resultOr (realPath p) "") p)))

fn guardParts! root: String cur: String parts: (List String) -> String
  (mt (listHead parts)
    ((none) "")
    ((some part)
      (if (or (stringEmpty? part) (= part "."))
        (guardParts! root cur (tailOf parts))
        (let [(next (k/joinPath cur part))]
          (if (linkAt? next)
            (str "Refusing to write through symlinked path component: " (k/relPath next root))
            (guardParts! root next (tailOf parts)))))))

fn writeGuard! root: String path: String -> String
  (let [(norm (k/normalizePath path))]
    (if (not (or (= norm root) (stringStartsWith? norm (str root "/"))))
      (str "Path escapes workspace boundary: " path)
      (let [(g (guardParts! root root (stringSplit (k/relPath norm root) "/")))]
        (cond
          ((not (stringEmpty? g)) g)
          ((let [(real (resultOr (realPath norm) norm))] (not (or (= real root) (stringStartsWith? real (str root "/"))))) (str "Path escapes workspace boundary: " path))
          (else "")))))

fn mkdirs! p: String -> (Result Unit String)
  (cond
    ((k/isDir! p) (ok ()))
    ((= (k/dirName p) p) (err (str "cannot create " p)))
    (else (mt (mkdirs! (k/dirName p)) ((err e) (err e)) ((ok _) (if (k/isDir! p) (ok ()) (dirCreate p))))))

fn lockLoop! path: String left: Int64 -> (Result Int64 String)
  (mt (fileLock path true)
    ((ok fd) (ok fd))
    ((err e) (if (and (= e "busy") (> left 0)) (do (sleepMs 20) (lockLoop! path (- left 1))) (err (str "notes ledger lock " e ": " path)))))

(schema Appended (:f id String) (:f before Int64) (:f after Int64))

fn withLock! path: String body: (fn [] -> (Result Appended String)) -> (Result Appended String)
  (mt (lockLoop! path 1500)
    ((err e) (err e))
    ((ok fd) (let [(r (body))] (do (fdClose fd) r))))

fn appendNote! ctx: KnowCtx kind: String scope: String date: String claim: String -> (Result Appended String)
  (let [(path (ledgerPath ctx)) (root ctx.ws) (g (writeGuard! root path))]
    (if (not (stringEmpty? g))
      (err g)
      (mt (mkdirs! (k/dirName path))
        ((err e) (err e))
        ((ok _)
          (let [(vroot (v/vfsRoot! ctx.ws ctx.vfsDir ctx.home))]
            (mt (mkdirs! vroot)
              ((err e) (err e))
              ((ok _) (withLock! (k/joinPath vroot "notesLedger.lock") (fn [] -> (Result Appended String) (appendLocked! root path kind scope date claim))))))))))

fn appendLocked! root: String path: String kind: String scope: String date: String claim: String -> (Result Appended String)
  (let [(text (if (k/isFile! path) (optionOr (readText! path) "") (notesSkeleton)))
        (before (notesCount text))
        (b (stringToBytes text))
        (ids (noteIds text b (stringLength text) 0 (list)))
        (nid (str "n" (stringFromInt64 (if (listEmpty? ids) 1 (+ (optionOr (listMax ids) 0) 1)))))
        (at (closingVectorAt text))]
    (if (< at 0)
      (err "notes ledger has no closing :notes vector; refusing to guess an insertion point")
      (let [(entry (str "\n    (:note\n      :id \"" nid "\"\n      :topic \"" (k/escapeAsnVal kind) "\"\n      :author \"agent\"\n      :date \"" (k/escapeAsnVal date)
                        "\"\n      :status \"active\"\n      :scope [\"" (k/escapeAsnVal scope) "\"]\n      :tags []\n      :fact \"" (k/escapeAsnVal claim)
                        "\"\n      :timestamp " (stringFromInt64 (/ (nowNs) 1000000)) ")"))
            (newText (str (slice text 0 at) entry (slice text at (stringLength text))))
            (derr (delimiterError newText))
            (g (writeGuard! root path))]
        (cond
          ((not (stringEmpty? derr)) (err (str "appending would corrupt the ledger: " derr)))
          ((not (stringEmpty? g)) (err g))
          (else
            (mt (v/atomicWrite! path newText)
              ((err e) (err e))
              ((ok _)
                (let [(check (optionOr (readText! path) "")) (after (notesCount check))]
                  (if (or (!= after (+ before 1)) (not (stringContains? check (str ":id \"" nid "\""))))
                    (err "ledger re-read did not show the new note")
                    (ok (Appended :id nid :before before :after after)))))))))))

fn noteQueryIds text: String q: String -> (List String)
  (let [(b (stringToBytes text)) (n (stringLength text)) (starts (noteStarts b n 0 (list))) (low (stringLower q))]
    (map (fn [(p (Pair Int64 Int64))] -> String (quoted (firstIdValue (slice text (pairFirst p) (pairSecond p)))))
         (filter (fn [(p (Pair Int64 Int64))] -> Bool (stringContains? (stringLower (slice text (pairFirst p) (pairSecond p))) low))
                 (zip starts (listAppend (listDrop starts 1) (list n))))))

fn noteStep! ctx: KnowCtx id: Int64 kw: (Map String String) args: (List String) -> KnowOutcome
  (let [(action (k/lstripColons (k/kwOr kw "action" (optionOr (listHead args) "list"))))
        (lpath (ledgerPath ctx))
        (lrel (k/escapeAsnVal (k/relToRoot ctx.ws lpath)))]
    (cond
      ((or (= action "list") (= action "query"))
        (let [(q (k/kwOr kw "query" (k/kwOr kw "text" (k/kwOr kw "claim" (optionOr (listGet args 1) "")))))
              (g (writeGuard! ctx.ws lpath))]
          (cond
            ((not (stringEmpty? g)) (badLine (str (stepHead id "note") " :action \"" action "\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message " (quoted g) ")")))
            ((and (= action "query") (stringEmpty? q)) (badLine (str (stepHead id "note") " :action \"query\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing :query argument\")")))
            (else
              (let [(ltext (if (k/isFile! lpath) (readText! lpath) (some "")))]
                (mt ltext
                  ((none) (badLine (str (stepHead id "note") " :action \"" action "\" :status \"rejected\" :error-code \":ERR_READ_FAILED\" :message " (quoted (str "cannot read " lpath)) ")")))
                  ((some t)
                    (if (= action "list")
                      (okLine (str (stepHead id "note") " :action \"list\" :status \"ok\" :receipt (:notes :count " (stringFromInt64 (notesCount t)) " :status " (if (stringEmpty? t) ":empty" ":active") " :source \"" lrel "\"))"))
                      (let [(hits (noteQueryIds t q))]
                        (okLine (str (stepHead id "note") " :action \"query\" :status \"ok\" :query " (quoted q) " :receipt (:receipt :note :matches " (stringFromInt64 (listLength hits))
                                     " :status :ok :source \"" lrel "\" :ids [" (stringJoin hits " ") "]))")))))))))))
      ((= action "write")
        (let [(claim (k/kwOr kw "claim" (k/kwOr kw "fact" (k/kwOr kw "text" ""))))
              (kind (k/kwOr kw "kind" (k/kwOr kw "topic" "observation")))
              (scope (k/kwOr kw "scope" "workspace"))
              (date (k/kwOr kw "date" (localDate! (/ (nowNs) 1000000000))))]
          (if (stringEmpty? (pyStrip claim))
            (badLine (str (stepHead id "note") " :action \"write\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing :claim argument\")"))
            (mt (appendNote! ctx (k/lstripColons kind) (k/lstripColons scope) date claim)
              ((ok r) (okLine (str (stepHead id "note") " :action \"write\" :status \"ok\" :id \"" r.id "\" :ledger " (quoted (k/relToRoot ctx.ws lpath))
                                   " :countBefore " (stringFromInt64 r.before) " :countAfter " (stringFromInt64 r.after) " :persisted true)")))
              ((err e) (badLine (str (stepHead id "note") " :action \"write\" :status \"rejected\" :error-code \":ERR_NOT_PERSISTED\" :message " (quoted e) ")")))))))
      (else (rejectedLine id "note" "ERR_INVALID_ACTION" (str " :message \"Unknown note action: " (k/escapeAsnVal action) "\"")))))

fn whereStep! ctx: KnowCtx id: Int64 kw: (Map String String) args: (List String) -> KnowOutcome
  (let [(sym (k/kwOr kw "symbol" (k/kwOr kw "name" (optionOr (listHead args) ""))))
        (intel (k/joinPath ctx.binDir "asl"))
        (argv (list intel "intel" "impact" sym))]
    (cond
      ((stringEmpty? sym) (rejectedLine id "where" "ERR_MISSING_ARG" " :message \"Missing symbol argument\""))
      ((not (k/isFile! intel)) (rejectedLine id "where" "ERR_BACKEND_UNAVAILABLE" " :message \"asl intel backend not available; cannot resolve symbol\""))
      (else
        (mt (runArgv! argv ctx.toolRoot 120000)
          ((err e) (rejectedLine id "where" "ERR_EXEC_FAILED" (str " :message " (quoted (procErrorMessage argv e)))))
          ((ok out)
            (if (!= out.exitCode 0)
              (rejectedLine id "where" "ERR_SYMBOL_NOT_FOUND"
                            (str " :symbol " (quoted sym) " :exitCode " (stringFromInt64 out.exitCode)
                                 " :message " (quoted (utf8Take (let [(e (pyStrip out.stderr))] (if (stringEmpty? e) (pyStrip out.stdout) e)) 400))))
              (okLine (str (stepHead id "where") " :status \"ok\" :symbol " (quoted sym) " :receipt\n" (pyStrip out.stdout) ")"))))))))

fn kwTokens s: String b: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [(st (skipWsFwd b n i))]
    (if (>= st n)
      (listReverse acc)
      (let [(c (bytesGet b st))
            (e (cond
                 ((= c 34) (quoteTokEnd b n (+ st 1) false))
                 ((or (= c 40) (= c 91)) (groupTokEnd b n st c (if (= c 40) 41 93) 0 false false))
                 (else (tokenEnd b n st))))]
        (kwTokens s b n e (cons (slice s st e) acc)))))

fn quoteTokEnd b: Bytes n: Int64 i: Int64 esc: Bool -> Int64
  (cond
    ((>= i n) n)
    (esc (quoteTokEnd b n (+ i 1) false))
    ((= (bytesGet b i) 92) (quoteTokEnd b n (+ i 1) true))
    ((= (bytesGet b i) 34) (+ i 1))
    (else (quoteTokEnd b n (+ i 1) false)))

fn groupTokEnd b: Bytes n: Int64 i: Int64 open: Int64 close: Int64 depth: Int64 inQ: Bool esc: Bool -> Int64
  (if (>= i n)
    n
    (let [(c (bytesGet b i))]
      (cond
        (esc (groupTokEnd b n (+ i 1) open close depth inQ false))
        ((= c 92) (groupTokEnd b n (+ i 1) open close depth inQ inQ))
        ((= c 34) (groupTokEnd b n (+ i 1) open close depth (not inQ) false))
        (inQ (groupTokEnd b n (+ i 1) open close depth inQ false))
        ((= c open) (groupTokEnd b n (+ i 1) open close (+ depth 1) inQ false))
        ((= c close) (if (= (- depth 1) 0) (+ i 1) (groupTokEnd b n (+ i 1) open close (- depth 1) inQ false)))
        (else (groupTokEnd b n (+ i 1) open close depth inQ false)))))

fn subArgKey? key: String -> Bool
  (listContains? (list "mode" "action" "status" "distill" "engine" "op" "stepOp" "direction" "kind" "format" "role" "depth" "service" "type" "profile" "lenses" "target" "model" "subcmd" "tier" "level" "scope" "topic") key)

fn keyOrder toks: (List String) acc: (List String) -> (List String)
  (mt (listHead toks)
    ((none) (listReverse acc))
    ((some tok)
      (let [(rest (tailOf toks))]
        (if (not (stringStartsWith? tok ":"))
          (keyOrder rest acc)
          (let [(key (k/lstripColons tok))
                (acc2 (if (listContains? acc key) acc (cons key acc)))
                (takes (mt (listHead rest)
                         ((none) false)
                         ((some nx) (let [(after (tailOf rest))
                                          (hasSub (mt (listHead after) ((none) false) ((some t2) (not (stringStartsWith? t2 ":")))))]
                                      (or (not (stringStartsWith? nx ":")) (and (not hasSub) (or (subArgKey? key) (listEmpty? after))))))))]
            (keyOrder (if takes (tailOf rest) rest) acc2))))))

fn kwOrder stepStr: String -> (List String)
  (let [(t (stringTrim stepStr))
        (s (if (and (stringStartsWith? t "(") (stringEndsWith? t ")")) (stringTrim (slice t 1 (- (stringLength t) 1))) t))
        (toks (kwTokens s (stringToBytes s) (stringLength s) 0 (list)))]
    (keyOrder (tailOf toks) (list)))

fn observeBody out: String -> (Option String)
  (let [(n (stringLength out))]
    (if (and (stringStartsWith? out "(:observe") (stringEndsWith? out ")") (>= n 10))
      (let [(rest (slice out 9 (- n 1)))
            (b (stringToBytes rest)) (rn (stringLength rest))
            (st (if (startsAt? b rn 0 " :status :") (alphaRunAscii b rn 10) -1))]
        (some (if (> st 10) (slice rest st rn) rest)))
      (none)))

fn alphaRunAscii b: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (alphaB? (bytesGet b j))) (alphaRunAscii b n (+ j 1)) j)

fn observeResult id: Int64 code: Int64 stdout: String stderr: String -> KnowOutcome
  (let [(obOut (pyStrip stdout)) (body (observeBody obOut))]
    (mt body
      ((some rest) (if (= code 0)
                     (okLine (str (stepHead id "observe") " :status \"ok\"" rest ")"))
                     (badLine (str (stepHead id "observe") " :status \"rejected\"" rest ")"))))
      ((none)
        (let [(errText (pyStrip stderr))
              (msg (utf8TakeLast (cond ((not (stringEmpty? errText)) errText) ((not (stringEmpty? obOut)) obOut) (else "observe produced no receipt")) 400))]
          (rejectedLine id "observe" "ERR_EXEC_FAILED" (str " :exitCode " (stringFromInt64 code) " :message " (quoted msg)))))))

fn safeObserveInProcessDim? dim: String -> Bool
  (listContains? (list "memory" "session" "tokenCost") dim)

fn obsEnvPair row: String -> (Pair String String)
  (mt (stringIndexOf row "=")
    ((some i) (pair (optionOr (stringSlice row 0 i) row) (optionOr (stringSlice row (+ i 1) (stringLength row)) "")))
    ((none) (pair row "")))

fn notCliRootKey p: (Pair String String) -> Bool
  (!= (pairFirst p) "ASL_CLI_ROOT")

fn observeInProcess! root: String ws: String argv: (List String) id: Int64 -> KnowOutcome
  (let [(baseEnv (filter notCliRootKey (map obsEnvPair (envList))))
        (env (cons (pair "ASL_CLI_ROOT" root) baseEnv))
        (ctx (oc/Ctx :cwd ws :env env :spawnEnv (none) :now (/ (nowNs) 1000000000) :date ""))
        (out (obs/runObserve ctx argv))]
    (observeResult id out.code out.out out.err))

fn observeStep! ctx: KnowCtx id: Int64 kw: (Map String String) args: (List String) keys: (List String) -> KnowOutcome
  (let [(dim (k/lstripColons (k/kwOr kw "dim" (optionOr (listHead args) ""))))
        (extra (fold (fn [(acc (List String)) (key String)] -> (List String)
                       (let [(v (optionOr (mapGet kw key) ""))]
                         (if (or (= key "dim") (stringEmpty? v)) acc (listAppend acc (list (str "--" key) (k/lstripColons v))))))
                     (list) keys))
        (root ctx.toolRoot)]
    (if (safeObserveInProcessDim? dim)
      (observeInProcess! root ctx.ws (listAppend (list "--dim" dim) extra) id)
      (let [(host (optionOr (envGet "ASL_CLI_HOST_BIN") (k/joinPath (k/joinPath root "asl") "host/out/asl-host")))
            (program (k/joinPath (k/joinPath root "asl") "tools/observe/observe.asl"))
            (argv (listAppend (list host "run" program "--dim" dim) extra))]
        (mt (runObserveArgv! argv ctx.ws root host 300000)
          ((err e) (rejectedLine id "observe" "ERR_EXEC_FAILED" (str " :message " (quoted (procErrorMessage argv e)))))
          ((ok out) (observeResult id out.exitCode out.stdout out.stderr))))))

fn floorDiv a: Int64 b: Int64 -> Int64
  (/ a b)

fn daysFromCivil y0: Int64 m: Int64 d: Int64 -> Int64
  (let [(y (if (<= m 2) (- y0 1) y0))
        (era (floorDiv y 400))
        (yoe (- y (* era 400)))
        (mp (if (> m 2) (- m 3) (+ m 9)))
        (doy (+ (/ (+ (* 153 mp) 2) 5) (- d 1)))
        (doe (+ (* yoe 365) (/ yoe 4) (- 0 (/ yoe 100)) doy))]
    (+ (* era 146097) doe -719468))

fn civilFromDays z0: Int64 -> (List Int64)
  (let [(z (+ z0 719468))
        (era (floorDiv z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (+ doe (/ doe 146096)) (+ (/ doe 1460) (/ doe 36524))) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ yoe (* era 400)))]
    (list (if (<= m 2) (+ y 1) y) m d))

fn pad2 v: Int64 -> String
  (if (< v 10) (str "0" (stringFromInt64 v)) (stringFromInt64 v))

fn pad4 v: Int64 -> String
  (let [(s (stringFromInt64 v))] (str (stringRepeat "0" (max 0 (- 4 (stringLength s)))) s))

fn isoDate days: Int64 -> String
  (let [(c (civilFromDays days))]
    (str (pad4 (optionOr (listGet c 0) 1970)) "-" (pad2 (optionOr (listGet c 1) 1)) "-" (pad2 (optionOr (listGet c 2) 1))))

fn be32 b: Bytes i: Int64 -> Int64
  (let [(v (+ (* (bytesGet b i) 16777216) (* (bytesGet b (+ i 1)) 65536) (* (bytesGet b (+ i 2)) 256) (bytesGet b (+ i 3))))]
    (if (>= v 2147483648) (- v 4294967296) v))

fn be64 b: Bytes i: Int64 -> Int64
  (let [(hi (be32 b i)) (lo (be32 b (+ i 4)))]
    (+ (* hi 4294967296) (if (< lo 0) (+ lo 4294967296) lo)))

(schema TzRule (:f stdOff Int64) (:f dstOff Int64) (:f hasDst Bool) (:f start String) (:f startTime Int64) (:f end String) (:f endTime Int64))

fn tzNameEnd s: String i: Int64 -> Int64
  (cond
    ((= (k/charAt s i) "<") (let [(j (optionOr (stringIndexOf (slice s i (stringLength s)) ">") -1))] (if (< j 0) (stringLength s) (+ i j 1))))
    ((and (< i (stringLength s)) (alphaB? (charCode (k/charAt s i)))) (tzNameEnd s (+ i 1)))
    (else i))

fn digitsEnd s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (digitByte? (charCode (k/charAt s i)))) (digitsEnd s (+ i 1)) i)

fn tzClock s: String i0: Int64 -> (Pair Int64 Int64)
  (let [(sign (cond ((= (k/charAt s i0) "-") -1) (else 1)))
        (i (if (or (= (k/charAt s i0) "-") (= (k/charAt s i0) "+")) (+ i0 1) i0))
        (e1 (digitsEnd s i))
        (h (optionOr (stringToInt64 (slice s i e1)) 0))
        (hasM (and (= (k/charAt s e1) ":") (> (digitsEnd s (+ e1 1)) (+ e1 1))))
        (e2 (if hasM (digitsEnd s (+ e1 1)) e1))
        (m (if hasM (optionOr (stringToInt64 (slice s (+ e1 1) e2)) 0) 0))
        (hasS (and hasM (= (k/charAt s e2) ":") (> (digitsEnd s (+ e2 1)) (+ e2 1))))
        (e3 (if hasS (digitsEnd s (+ e2 1)) e2))
        (sec (if hasS (optionOr (stringToInt64 (slice s (+ e2 1) e3)) 0) 0))]
    (pair (* sign (+ (* h 3600) (* m 60) sec)) e3))

fn ruleField s: String i: Int64 -> (Pair String Int64)
  (let [(stop (fold (fn [(best Int64) (c String)] -> Int64 (let [(j (optionOr (stringIndexOf (slice s i (stringLength s)) c) -1))] (if (and (>= j 0) (< (+ i j) best)) (+ i j) best))) (stringLength s) (list "," "/")))]
    (pair (slice s i stop) stop))

fn parseTzRule s: String -> (Option TzRule)
  (let [(n1 (tzNameEnd s 0))
        (std (tzClock s n1))]
    (if (or (= n1 0) (= (pairSecond std) n1))
      (none)
      (let [(stdOff (- 0 (pairFirst std)))
            (d0 (pairSecond std))
            (d1 (tzNameEnd s d0))]
        (if (= d1 d0)
          (some (TzRule :stdOff stdOff :dstOff stdOff :hasDst false :start "" :startTime 7200 :end "" :endTime 7200))
          (let [(hasOff (and (< d1 (stringLength s)) (not (= (k/charAt s d1) ","))))
                (dst (if hasOff (tzClock s d1) (pair (- 0 (+ stdOff 3600)) d1)))
                (r0 (pairSecond dst))
                (rules (if (= (k/charAt s r0) ",") (slice s (+ r0 1) (stringLength s)) "M3.2.0,M11.1.0"))
                (sf (ruleField rules 0))
                (st (if (= (k/charAt rules (pairSecond sf)) "/") (tzClock rules (+ (pairSecond sf) 1)) (pair 7200 (pairSecond sf))))
                (ef (ruleField rules (+ (pairSecond st) 1)))
                (et (if (= (k/charAt rules (pairSecond ef)) "/") (tzClock rules (+ (pairSecond ef) 1)) (pair 7200 (pairSecond ef))))]
            (some (TzRule :stdOff stdOff :dstOff (- 0 (pairFirst dst)) :hasDst true :start (pairFirst sf) :startTime (pairFirst st) :end (pairFirst ef) :endTime (pairFirst et))))))))

fn leapYear? y: Int64 -> Bool
  (and (= (mod y 4) 0) (or (!= (mod y 100) 0) (= (mod y 400) 0)))

fn monthDays y: Int64 m: Int64 -> Int64
  (cond ((= m 2) (if (leapYear? y) 29 28)) ((listContains? (list 4 6 9 11) m) 30) (else 31))

fn ruleDay y: Int64 rule: String -> Int64
  (cond
    ((stringStartsWith? rule "M")
      (let [(parts (stringSplit (slice rule 1 (stringLength rule)) "."))
            (m (optionOr (stringToInt64 (optionOr (listGet parts 0) "1")) 1))
            (w (optionOr (stringToInt64 (optionOr (listGet parts 1) "1")) 1))
            (d (optionOr (stringToInt64 (optionOr (listGet parts 2) "0")) 0))
            (first (daysFromCivil y m 1))
            (wday1 (mod (+ (mod (+ first 4) 7) 7) 7))
            (day (+ 1 (mod (+ (- d wday1) 7) 7) (* (- w 1) 7)))
            (fit (lastFit day (monthDays y m)))]
        (+ first (- fit 1))))
    ((stringStartsWith? rule "J")
      (let [(jn (optionOr (stringToInt64 (slice rule 1 (stringLength rule))) 1))]
        (+ (daysFromCivil y 1 1) (- jn 1) (if (and (leapYear? y) (>= jn 60)) 1 0))))
    (else (+ (daysFromCivil y 1 1) (optionOr (stringToInt64 rule) 0))))

fn lastFit day: Int64 dim: Int64 -> Int64
  (if (> day dim) (lastFit (- day 7) dim) day)

fn ruleOffset r: TzRule t: Int64 -> Int64
  (if (not r.hasDst)
    r.stdOff
    (let [(y (optionOr (listHead (civilFromDays (floorDiv (+ t r.stdOff) 86400))) 1970))
          (startUtc (- (+ (* (ruleDay y r.start) 86400) r.startTime) r.stdOff))
          (endUtc (- (+ (* (ruleDay y r.end) 86400) r.endTime) r.dstOff))
          (inDst (if (< startUtc endUtc) (and (>= t startUtc) (< t endUtc)) (not (and (>= t endUtc) (< t startUtc)))))]
      (if inDst r.dstOff r.stdOff)))

fn lastAtOrBefore b: Bytes base: Int64 size: Int64 count: Int64 t: Int64 i: Int64 best: Int64 -> Int64
  (cond
    ((>= i count) best)
    ((<= (if (= size 8) (be64 b (+ base (* i 8))) (be32 b (+ base (* i 4)))) t) (lastAtOrBefore b base size count t (+ i 1) i))
    (else best))

fn tzifOffset b: Bytes n: Int64 t: Int64 -> Int64
  (if (or (< n 44) (not (startsAt? b n 0 "TZif")))
    0
    (let [(v1 (+ 44 (* (be32 b 32) 5) (* (be32 b 36) 6) (be32 b 40) (* (be32 b 28) 8) (be32 b 24) (be32 b 20)))
          (v2 (and (>= (bytesGet b 4) 50) (>= n (+ v1 44))))
          (h (if v2 v1 0))
          (size (if v2 8 4))
          (timecnt (be32 b (+ h 32)))
          (typecnt (be32 b (+ h 36)))
          (charcnt (be32 b (+ h 40)))
          (leapcnt (be32 b (+ h 28)))
          (isstd (be32 b (+ h 24)))
          (isut (be32 b (+ h 20)))
          (tbase (+ h 44))
          (idxBase (+ tbase (* timecnt size)))
          (typeBase (+ idxBase timecnt))
          (dataEnd (+ typeBase (* typecnt 6) charcnt (* leapcnt (+ size 4)) isstd isut))
          (last (lastAtOrBefore b tbase size timecnt t 0 -1))
          (footer (if (and v2 (< dataEnd n)) (pyStrip (footerText b n (+ dataEnd 1))) ""))
          (typeOff (fn [(ti Int64)] -> Int64 (if (and (>= ti 0) (< ti typecnt)) (be32 b (+ typeBase (* ti 6))) 0)))]
      (cond
        ((> (+ typeBase (* typecnt 6)) n) 0)
        ((and (= last (- timecnt 1)) (not (stringEmpty? footer)) (some? (parseTzRule footer))) (ruleOffset (optionOr (parseTzRule footer) (TzRule :stdOff 0 :dstOff 0 :hasDst false :start "" :startTime 0 :end "" :endTime 0)) t))
        ((< last 0) (typeOff 0))
        (else (typeOff (bytesGet b (+ idxBase last)))))))

fn footerText b: Bytes n: Int64 i: Int64 -> String
  (stringJoin (map (fn [(j Int64)] -> String (asciiChar (bytesGet b j))) (range i (lineEndFrom b n i))) "")

fn zoneFile! name: String -> String
  (let [(tzdir (optionOr (envGet "TZDIR") ""))
        (dirs (listAppend (if (stringEmpty? tzdir) (list) (list tzdir)) (list "/usr/share/zoneinfo" "/var/db/timezone/zoneinfo")))
        (cands (if (stringStartsWith? name "/") (list name) (map (fn [(d String)] -> String (k/joinPath d name)) dirs)))]
    (optionOr (listHead (filter k/isFile! cands)) ""))

fn utcOffset! tz: (Option String) t: Int64 -> Int64
  (let [(spec (mt tz ((none) "/etc/localtime") ((some v) (if (stringStartsWith? v ":") (slice v 1 (stringLength v)) v))))
        (file (if (stringEmpty? spec) "" (zoneFile! spec)))]
    (cond
      ((stringEmpty? spec) 0)
      ((not (stringEmpty? file)) (mt (fileReadBytes file) ((ok b) (tzifOffset b (bytesLength b) t)) ((err _) 0)))
      (else (mt (parseTzRule spec) ((some r) (ruleOffset r t)) ((none) 0)))))

fn localDateAt! tz: (Option String) t: Int64 -> String
  (isoDate (floorDiv (+ t (utcOffset! tz t)) 86400))

fn localDate! t: Int64 -> String
  (localDateAt! (envGet "TZ") t)
