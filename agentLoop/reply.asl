(module asl/agentLoop/reply
  :x [RepairItem repairItem CutInfo AutoRepair RunRead runUnchanged runHint runStep FormTok formTok Fence fence RawBind NeedsConfirm ReplyFacts
      pyStrip charsBefore isKeywordStart commitMessageError commitNamesHead! repairInnerQuotes formChunks chunkOps recPairs
      coreRepairDelimiters repairReceiptItems repairRefOffset offsetToLinecol delimiterFixDesc splitChunkLines hasUnclosedForm
      locateParseFailure describeParseFailure autoRepairReply parseReply parseCutInfo detectCutForm topLevelSpans degenerateCut
      capReply replyFacts needsConfirmReceipt! shlexSplit runAsRead! tokenizeForm rawFences hoistInlineRaw bindRawBlocks unfence
      replyMaxBytes rawRequiredBytes]
  :i [(asl/agentLoop/core :a c) (asl-forms/repair :a rep) (asl-proc/coreProcess :a cp)])

enum RepairItem
  (repairItem kind: String tok: String line: Int64 col: Int64)

(schema CutInfo
  (:f offset Int64)
  (:f bytes Int64)
  (:f head (Option String))
  (:f op (Option String))
  (:f file (Option String))
  (:f start Int64)
  (:f text String))

(schema AutoRepair
  (:f text String)
  (:f notice (Option String))
  (:f kinds (List String))
  (:f left Int64)
  (:f quoteCount Int64)
  (:f leftSpans (Option (List (Pair Int64 Int64)))))

enum RunRead
  (runUnchanged)
  (runHint argv: String form: String message: String)
  (runStep file: String fromRun: String form: String span: (Option (Pair Int64 Int64)))

enum FormTok
  (formTok text: String start: Int64 end: Int64)

enum Fence
  (fence start: Int64 end: Int64 content: String)

(schema RawBind
  (:f text String)
  (:f count Int64)
  (:f missing (List (Pair String String))))

(schema NeedsConfirm
  (:f id String)
  (:f op String)
  (:f message String))

(schema ReplyFacts
  (:f ops (List (List (Pair String c/KvVal))))
  (:f repeated Int64)
  (:f forms (List String))
  (:f prose Bool)
  (:f dataFindings (List String))
  (:f cut (Option CutInfo)))

fn replyMaxBytes -> Int64
  400000

fn rawRequiredBytes -> Int64
  400

fn at bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn isSpaceB b: Int64 -> Bool
  (or (= b 32) (or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 31))))

fn isDigitB b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isAsciiAlpha b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn isAlphaB b: Int64 -> Bool
  (or (isAsciiAlpha b) (>= b 128))

fn isWordB b: Int64 -> Bool
  (or (isAlphaB b) (or (isDigitB b) (= b 95)))

fn isHexB b: Int64 -> Bool
  (or (isDigitB b) (or (and (>= b 97) (<= b 102)) (and (>= b 65) (<= b 70))))

fn isCloser b: Int64 -> Bool
  (or (= b 41) (or (= b 93) (= b 125)))

fn isOpener b: Int64 -> Bool
  (or (= b 40) (or (= b 91) (= b 123)))

fn sl s: String a: Int64 b: Int64 -> String
  (let [n (stringLength s)
        a2 (max 0 (min a n))
        b2 (max 0 (min b n))]
    (if (>= a2 b2) "" (c/sliceOf s a2 b2)))

fn skipWhile bs: Bytes n: Int64 i: Int64 test: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (test (bytesGet bs i))) (skipWhile bs n (+ i 1) test) i)

fn backWhile bs: Bytes j: Int64 test: (fn [Int64] -> Bool) -> Int64
  (if (and (> j 0) (test (bytesGet bs (- j 1)))) (backWhile bs (- j 1) test) j)

fn pyStrip s: String -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        a (skipWhile bs n 0 isSpaceB)
        b (backWhile bs n isSpaceB)]
    (sl s a b))

fn pyLstrip s: String -> String
  (let [bs (stringToBytes s)]
    (sl s (skipWhile bs (bytesLength bs) 0 isSpaceB) (stringLength s)))

fn pyRstrip s: String -> String
  (let [bs (stringToBytes s)]
    (sl s 0 (backWhile bs (bytesLength bs) isSpaceB)))

fn charsBefore s: String i: Int64 -> Int64
  (c/charLen (sl s 0 i))

fn charCut s: String k: Int64 -> String
  (c/charPrefix s k)

fn byteOfChar s: String k: Int64 -> Int64
  (if (<= k 0) 0 (c/charIndex s (stringLength s) 0 k))

fn joinWith xs: (List String) sep: String -> String
  (c/joinSep xs sep)

fn member x: String xs: (List String) -> Bool
  (listAny? (fn [y] (= x y)) xs)

fn hex2 v: Int64 -> String
  (let [d "0123456789abcdef"]
    (str (c/sliceOf d (/ v 16) (+ (/ v 16) 1)) (c/sliceOf d (mod v 16) (+ (mod v 16) 1))))

fn reprLoop s: String bs: Bytes n: Int64 i: Int64 q: String acc: (List String) -> String
  (if (>= i n)
    (c/joinAll (listReverse acc))
    (let [b (bytesGet bs i)
          nb (at bs n (+ i 1))]
      (cond
        ((= b 92) (reprLoop s bs n (+ i 1) q (cons "\\\\" acc)))
        ((= b 10) (reprLoop s bs n (+ i 1) q (cons "\\n" acc)))
        ((= b 13) (reprLoop s bs n (+ i 1) q (cons "\\r" acc)))
        ((= b 9) (reprLoop s bs n (+ i 1) q (cons "\\t" acc)))
        ((or (< b 32) (= b 127)) (reprLoop s bs n (+ i 1) q (cons (str "\\x" (hex2 b)) acc)))
        ((= (c/sliceOf s i (+ i 1)) q) (reprLoop s bs n (+ i 1) q (cons (str "\\" q) acc)))
        ((and (= b 194) (or (and (>= nb 128) (<= nb 160)) (= nb 173)))
          (reprLoop s bs n (+ i 2) q (cons (str "\\x" (hex2 nb)) acc)))
        (else (reprLoop s bs n (+ i 1) q (cons (c/sliceOf s i (+ i 1)) acc))))))

fn pyRepr s: String -> String
  (let [q (if (and (stringContains? s "'") (not (stringContains? s "\""))) "\"" "'")
        bs (stringToBytes s)]
    (str q (reprLoop s bs (bytesLength bs) 0 q (list)) q))

fn isKeywordStart s: String idx: Int64 -> Bool
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (and (= (at bs n idx) 58) (isAlphaB (at bs n (+ idx 1)))))

fn cmStrEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) j)
    ((= (bytesGet bs j) 92) (cmStrEnd bs n (+ j 2)))
    ((= (bytesGet bs j) 34) j)
    (else (cmStrEnd bs n (+ j 1))))

fn isAtomEnd b: Int64 -> Bool
  (or (isSpaceB b) (or (isOpener b) (or (isCloser b) (= b 34))))

fn cmScan text: String bs: Bytes n: Int64 i: Int64 depth: Int64 closed: Int64 cnt: Int64 toks: (List (Pair String String)) -> (Result (Pair (List (Pair String String)) (Pair Int64 Int64)) String)
  (if (>= i n)
    (ok (pair (listReverse toks) (pair depth closed)))
    (let [b (bytesGet bs i)]
      (cond
        ((isSpaceB b) (cmScan text bs n (+ i 1) depth closed cnt toks))
        ((>= closed 0) (err "the message must be exactly one form"))
        ((= b 34)
          (let [j (cmStrEnd bs n (+ i 1))]
            (if (>= j n)
              (err "a string is opened but never closed")
              (cmScan text bs n (+ j 1) depth closed (+ cnt 1) (cons (pair "str" (sl text (+ i 1) j)) toks)))))
        ((isOpener b) (cmScan text bs n (+ i 1) (+ depth 1) closed (+ cnt 1) (cons (pair "open" (sl text i (+ i 1))) toks)))
        ((isCloser b)
          (if (< (- depth 1) 0)
            (err "a bracket closes that was never opened")
            (cmScan text bs n (+ i 1) (- depth 1) (if (= depth 1) (+ cnt 1) closed) (+ cnt 1) (cons (pair "close" (sl text i (+ i 1))) toks))))
        (else
          (let [j (skipWhile bs n i (fn [x] (not (isAtomEnd x))))]
            (cmScan text bs n j depth closed (+ cnt 1) (cons (pair "atom" (sl text i j)) toks)))))))

fn tokAt toks: (List (Pair String String)) k: Int64 -> (Pair String String)
  (mt (listGet toks k) ((some t) t) (none (pair "" "")))

fn cmKeys toks: (List (Pair String String)) len: Int64 k: Int64 keys: (List String) -> (Result (List String) String)
  (if (>= k (- len 1))
    (ok keys)
    (let [t (tokAt toks k)
          kind (pairFirst t)
          val (pairSecond t)]
      (if (or (!= kind "atom") (not (stringStartsWith? val ":")))
        (if (and (not (listEmpty? keys)) (= (pairFirst (tokAt toks (- k 1))) "atom"))
          (err (str "the :" (c/firstOf keys) " value contains a space and must be a quoted string"))
          (err (str "expected a :keyword, found " (pyRepr val))))
        (let [key (sl val 1 (stringLength val))
              v (tokAt toks (+ k 1))]
          (cond
            ((>= (+ k 1) (- len 1)) (err (str ":" key " has no value")))
            ((or (= (pairFirst v) "open") (or (= (pairFirst v) "close") (and (= (pairFirst v) "atom") (stringStartsWith? (pairSecond v) ":"))))
              (err (str ":" key " has no value")))
            (else (cmKeys toks len (+ k 2) (cons key keys))))))))

fn commitMessageError msg: String -> (Option String)
  (cond
    ((= (pyStrip msg) "") (some "the message is empty"))
    ((or (stringContains? msg "\n") (stringContains? msg "\r")) (some "the message must be one line"))
    (else
      (let [text (pyStrip msg)
            bs (stringToBytes text)]
        (if (not (stringStartsWith? text "("))
          (some "the message must be one (:c ...) form")
          (mt (cmScan text bs (bytesLength bs) 0 0 -1 0 (list))
            ((err e) (some e))
            ((ok r)
              (mt r
                ((pair toks st)
                  (let [depth (pairFirst st)
                        closed (pairSecond st)
                        len (listLength toks)]
                    (cond
                      ((!= depth 0) (some "a bracket is opened but never closed"))
                      ((or (< len 2) (or (!= (tokAt toks 0) (pair "open" "(")) (or (!= (pairFirst (tokAt toks (- len 1))) "close") (!= closed len))))
                        (some "the message must be one balanced (:c ...) form"))
                      ((!= (tokAt toks 1) (pair "atom" ":c")) (some "the form's head must be :c"))
                      (else
                        (mt (cmKeys toks len 2 (list))
                          ((err e) (some e))
                          ((ok keys)
                            (cond
                              ((not (member "a" keys)) (some "the form must carry :a"))
                              ((not (member "do" keys)) (some "the form must carry :do"))
                              (else none)))))))))))))))

fn allHex bs: Bytes n: Int64 i: Int64 -> Bool
  (cond ((>= i n) true) ((isHexB (bytesGet bs i)) (allHex bs n (+ i 1))) (else false))

fn procError e: cp/ProcessError -> String
  (mt e
    ((cp/notFound b) (str "git not found: " b))
    ((cp/timeout ms) (str "git timed out after " (stringFromInt64 ms) " ms"))
    ((cp/permissionDenied p) (str "git not executable: " p))
    ((cp/executionFailed code m) (str "git failed: " m)))

fn ! commitNamesHead! msg: String rootDir: String -> (Result Bool String)
  (let [s (pyStrip msg)
        bs (stringToBytes s)
        n (bytesLength bs)]
    (if (or (< n 7) (or (> n 40) (or (not (allHex bs n 0)) (= rootDir ""))))
      (ok false)
      (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" (list "rev-parse" "HEAD")) rootDir) 60000))
        ((err e) (err (procError e)))
        ((ok out)
          (let [head (if (= out.exitCode 0) (pyStrip out.stdout) "")]
            (ok (and (!= head "") (stringStartsWith? head (stringLower s)))))))))

fn skipSpaces bs: Bytes n: Int64 i: Int64 -> Int64
  (skipWhile bs n i isSpaceB)

fn innerQuote s: String bs: Bytes n: Int64 i: Int64 -> Bool
  (let [k (skipSpaces bs n (+ i 1))]
    (cond
      ((>= k n) false)
      ((isKeywordStart s k) false)
      ((isCloser (bytesGet bs k))
        (let [m (skipSpaces bs n (+ k 1))]
          (not (or (>= m n) (or (isCloser (bytesGet bs m)) (or (= (bytesGet bs m) 40) (isKeywordStart s m)))))))
      (else true)))

fn iqLoop s: String bs: Bytes n: Int64 i: Int64 inStr: Bool esc: Bool start: Int64 count: Int64 acc: (List String) -> (Pair String Int64)
  (if (>= i n)
    (pair (c/joinAll (listReverse (cons (sl s start n) acc))) count)
    (let [b (bytesGet bs i)]
      (cond
        ((and inStr esc) (iqLoop s bs n (+ i 1) true false start count acc))
        ((and inStr (= b 92)) (iqLoop s bs n (+ i 1) true true start count acc))
        ((and inStr (= b 34))
          (if (innerQuote s bs n i)
            (iqLoop s bs n (+ i 1) true false (+ i 1) (+ count 1) (cons "\\\"" (cons (sl s start i) acc)))
            (iqLoop s bs n (+ i 1) false false start count acc)))
        (inStr (iqLoop s bs n (+ i 1) true false start count acc))
        ((= b 34) (iqLoop s bs n (+ i 1) true false start count acc))
        (else (iqLoop s bs n (+ i 1) false false start count acc)))))

fn repairInnerQuotes text: String -> (Pair String Int64)
  (let [bs (stringToBytes text)]
    (iqLoop text bs (bytesLength bs) 0 false false 0 0 (list)))

fn formClose bs: Bytes n: Int64 j: Int64 depth: Int64 inStr: Bool esc: Bool -> (Pair Int64 Int64)
  (if (or (>= j n) (<= depth 0))
    (pair j depth)
    (let [b (bytesGet bs j)]
      (cond
        (esc (formClose bs n (+ j 1) depth inStr false))
        ((and (= b 92) inStr) (formClose bs n (+ j 1) depth inStr true))
        ((= b 34) (formClose bs n (+ j 1) depth (not inStr) false))
        (inStr (formClose bs n (+ j 1) depth inStr false))
        ((= b 40) (formClose bs n (+ j 1) (+ depth 1) inStr false))
        ((= b 41) (formClose bs n (+ j 1) (- depth 1) inStr false))
        (else (formClose bs n (+ j 1) depth inStr false)))))

fn lineFormAt bs: Bytes n: Int64 p: Int64 -> Bool
  (and (or (= p 0) (= (at bs n (- p 1)) 10))
    (= (at bs n (skipWhile bs n p (fn [b] (or (= b 32) (= b 9))))) 40))

fn nextLineForm bs: Bytes n: Int64 p: Int64 -> (Option Int64)
  (cond
    ((>= p n) none)
    ((lineFormAt bs n p) (some p))
    (else (nextLineForm bs n (+ p 1))))

fn skipComment bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (!= (bytesGet bs i) 10)) (skipComment bs n (+ i 1)) i)

fn chunksLoop bs: Bytes n: Int64 i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (let [b (bytesGet bs i)]
      (cond
        ((isSpaceB b) (chunksLoop bs n (+ i 1) acc))
        ((= b 59) (chunksLoop bs n (skipComment bs n i) acc))
        ((!= b 40) (chunksLoop bs n (+ i 1) acc))
        (else
          (mt (formClose bs n (+ i 1) 1 false false)
            ((pair j depth)
              (if (= depth 0)
                (chunksLoop bs n j (cons (pair i j) acc))
                (mt (nextLineForm bs n (+ i 1))
                  ((some m) (chunksLoop bs n m (cons (pair i m) acc)))
                  (none (chunksLoop bs n n (cons (pair i n) acc)))))))))))

fn formChunks reply: String -> (List (Pair Int64 Int64))
  (let [bs (stringToBytes reply)]
    (chunksLoop bs (bytesLength bs) 0 (list)))

fn chunkOps text: String -> (Result (List (List (Pair String c/KvVal))) String)
  (let [ops (replyFacts text none).ops]
    (if (and (not (listEmpty? ops)) (none? (locateParseFailure text)))
      (ok ops)
      (err "no ops in form")))

fn putPair kv: (List (Pair String String)) k: String v: String -> (List (Pair String String))
  (if (listAny? (fn [p] (= (pairFirst p) k)) kv)
    (map (fn [p] (if (= (pairFirst p) k) (pair k v) p)) kv)
    (listAppend kv (list (pair k v))))

fn recLoop items: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (if (or (listEmpty? items) (listEmpty? (c/restOf items)))
    acc
    (recLoop (c/restOf (c/restOf items)) (putPair acc (c/firstOf items) (c/firstOf (c/restOf items)))))

fn recPairs items: (List String) -> (List (Pair String String))
  (recLoop items (list))

fn serBody s: String -> String
  (let [q (c/serString s)]
    (sl q 1 (- (stringLength q) 1)))

fn coreRepairDelimiters text: String lang: String -> (Pair String String)
  (let [res (rep/repairAtSite text lang)]
    (pair (c/asnUnescape (serBody (rep/repairResultText res))) (c/asnUnescape (serBody (rep/repairResultReceipt res)))))

fn litLoop bs: Bytes lb: Bytes p: Int64 i: Int64 k: Int64 -> Bool
  (cond ((>= i k) true) ((= (bytesGet bs (+ p i)) (bytesGet lb i)) (litLoop bs lb p (+ i 1) k)) (else false))

fn litAt bs: Bytes n: Int64 p: Int64 lit: String -> Bool
  (let [lb (stringToBytes lit)
        k (bytesLength lb)]
    (and (>= p 0) (and (<= (+ p k) n) (litLoop bs lb p 0 k))))

fn spaces1 bs: Bytes n: Int64 p: Int64 -> Int64
  (if (< p 0) -1 (let [q (skipSpaces bs n p)] (if (> q p) q -1)))

fn rxStrBody bs: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (bytesGet bs j) 34) j)
    ((= (bytesGet bs j) 92) (if (and (< (+ j 1) n) (!= (bytesGet bs (+ j 1)) 10)) (rxStrBody bs n (+ j 2)) -1))
    (else (rxStrBody bs n (+ j 1))))

fn digitsRun bs: Bytes n: Int64 p: Int64 -> Int64
  (if (< p 0) -1 (let [q (skipWhile bs n p isDigitB)] (if (> q p) q -1)))

fn rxKeyInt bs: Bytes n: Int64 p: Int64 key: String -> (Pair Int64 Int64)
  (if (not (litAt bs n p key))
    (pair -1 -1)
    (let [a (spaces1 bs n (+ p (stringLength key)))]
      (pair a (digitsRun bs n a))))

fn rxItem s: String bs: Bytes n: Int64 p: Int64 -> (Option (Pair RepairItem Int64))
  (let [a (spaces1 bs n (+ p 5))
        q0 (if (< a 0) -1 (if (= (at bs n a) 34) (+ a 1) a))
        w (if (< q0 0) -1 (skipWhile bs n q0 isWordB))
        q1 (if (or (< w 0) (= w q0)) -1 (if (= (at bs n w) 34) (+ w 1) w))
        t0 (spaces1 bs n q1)
        t1 (if (not (litAt bs n t0 ":tok")) -1 (spaces1 bs n (+ t0 4)))
        sb (if (or (< t1 0) (!= (at bs n t1) 34)) -1 (+ t1 1))
        se (if (< sb 0) -1 (rxStrBody bs n sb))
        l0 (if (< se 0) -1 (spaces1 bs n (+ se 1)))
        ln (rxKeyInt bs n l0 ":line")
        c0 (spaces1 bs n (pairSecond ln))
        co (rxKeyInt bs n c0 ":col")]
    (if (< (pairSecond co) 0)
      none
      (some (pair (repairItem (sl s q0 w) (c/asnUnescape (sl s sb se))
                    (optionOr (stringToInt64 (sl s (pairFirst ln) (pairSecond ln))) 0)
                    (optionOr (stringToInt64 (sl s (pairFirst co) (pairSecond co))) 0))
                  (pairSecond co)))))

fn rxItems s: String bs: Bytes n: Int64 p: Int64 acc: (List RepairItem) -> (List RepairItem)
  (cond
    ((>= p n) (listReverse acc))
    ((litAt bs n p ":kind")
      (mt (rxItem s bs n p)
        ((some r) (rxItems s bs n (pairSecond r) (cons (pairFirst r) acc)))
        (none (rxItems s bs n (+ p 1) acc))))
    (else (rxItems s bs n (+ p 1) acc)))

fn repairReceiptItems receipt: String -> (List RepairItem)
  (let [bs (stringToBytes receipt)]
    (rxItems receipt bs (bytesLength bs) 0 (list)))

fn backOpen bs: Bytes i: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (< i 1)
    -1
    (let [b (bytesGet bs i)]
      (cond
        ((and inStr esc) (backOpen bs (- i 1) depth true false))
        ((and inStr (= b 92)) (backOpen bs (- i 1) depth true true))
        ((and inStr (= b 34)) (backOpen bs (- i 1) depth false false))
        (inStr (backOpen bs (- i 1) depth true false))
        ((= b 34) (backOpen bs (- i 1) depth true false))
        ((= b 41) (backOpen bs (- i 1) (+ depth 1) false false))
        ((= b 40) (if (= (- depth 1) 0) i (backOpen bs (- i 1) (- depth 1) false false)))
        (else (backOpen bs (- i 1) depth false false)))))

fn repairRefOffset chunk: String -> Int64
  (let [bs (stringToBytes chunk)
        n (bytesLength bs)
        end (backWhile bs n isSpaceB)]
    (if (or (<= end 1) (!= (bytesGet bs (- end 1)) 41))
      end
      (let [openAt (backOpen bs (- end 1) 0 false false)]
        (if (<= openAt 1)
          end
          (let [before (backWhile bs openAt isSpaceB)]
            (if (<= before 1)
              end
              (let [w (backWhile bs before isWordB)]
                (if (and (< w before) (and (>= w 1) (and (= (bytesGet bs (- w 1)) 58) (or (isAsciiAlpha (bytesGet bs w)) (= (bytesGet bs w) 95)))))
                  end
                  before))))))))

fn lastNewline bs: Bytes j: Int64 -> Int64
  (cond ((<= j 0) -1) ((= (bytesGet bs (- j 1)) 10) (- j 1)) (else (lastNewline bs (- j 1))))

fn offsetToLinecol text: String offset: Int64 -> (Pair Int64 Int64)
  (let [prefix (sl text 0 offset)
        bs (stringToBytes prefix)
        nl (lastNewline bs (bytesLength bs))]
    (pair (+ 1 (stringCountChar prefix "\n")) (+ 1 (c/charLen (sl prefix (+ nl 1) (stringLength prefix))))))

fn isCloserTok t: String -> Bool
  (or (= t "") (stringContains? ")]}" t))

fn fixPart it: RepairItem -> String
  (mt it ((repairItem kind tok _ _)
    (cond
      ((and (= kind "insert") (isCloserTok tok)) (str "close " tok))
      ((= kind "insert") (str "insert " tok))
      (else (str "drop " tok)))))

fn delimiterFixDesc items: (List RepairItem) -> String
  (charCut (joinWith (map fixPart (listTake items 5)) "; ") 120)

fn lineForms bs: Bytes n: Int64 p: Int64 acc: (List Int64) -> (List Int64)
  (mt (nextLineForm bs n p)
    ((some m) (lineForms bs n (+ m 1) (cons m acc)))
    (none (listReverse acc)))

fn pieceStep acc: (Pair Int64 (Pair Bool (List String))) m: Int64 text: String -> (Pair Int64 (Pair Bool (List String)))
  (mt acc ((pair prev pr)
    (if (and (pairFirst pr) (> m prev))
      (pair m (pair true (cons (sl text prev m) (pairSecond pr))))
      (pair prev (pair true (pairSecond pr))))))

fn splitChunkLines text: String -> (List String)
  (let [bs (stringToBytes text)
        starts (lineForms bs (bytesLength bs) 0 (list))
        st (fold (fn [acc m] (pieceStep acc m text)) (pair 0 (pair false (list))) starts)]
    (mt st ((pair prev pr) (listReverse (cons (sl text prev (stringLength text)) (pairSecond pr))))))

fn unclosedLoop bs: Bytes n: Int64 i: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (>= i n)
    depth
    (let [b (bytesGet bs i)]
      (cond
        (esc (unclosedLoop bs n (+ i 1) depth inStr false))
        ((= b 92) (unclosedLoop bs n (+ i 1) depth inStr inStr))
        ((= b 34) (unclosedLoop bs n (+ i 1) depth (not inStr) false))
        (inStr (unclosedLoop bs n (+ i 1) depth inStr false))
        ((= b 40) (unclosedLoop bs n (+ i 1) (+ depth 1) inStr false))
        ((= b 41) (unclosedLoop bs n (+ i 1) (- depth 1) inStr false))
        (else (unclosedLoop bs n (+ i 1) depth inStr false)))))

fn hasUnclosedForm reply: String -> Bool
  (let [bs (stringToBytes reply)]
    (> (unclosedLoop bs (bytesLength bs) 0 0 false false) 0))

fn lpfForm bs: Bytes n: Int64 start: Int64 j: Int64 depth: Int64 inStr: Bool esc: Bool strOpen: Int64 -> (Pair Int64 (Option (Pair Int64 String)))
  (if (or (>= j n) (<= depth 0))
    (if (> depth 0)
      (pair j (some (if inStr (pair strOpen "string opened") (pair start "form opened"))))
      (pair j none))
    (let [b (bytesGet bs j)]
      (cond
        (esc (lpfForm bs n start (+ j 1) depth inStr false strOpen))
        ((and (= b 92) inStr) (lpfForm bs n start (+ j 1) depth inStr true strOpen))
        ((= b 34)
          (if inStr
            (let [nx (at bs n (+ j 1))]
              (if (and (>= nx 0) (and (not (isSpaceB nx)) (and (not (isOpener nx)) (not (isCloser nx)))))
                (pair j (some (pair j "string closed")))
                (lpfForm bs n start (+ j 1) depth false false strOpen)))
            (lpfForm bs n start (+ j 1) depth true false j)))
        (inStr (lpfForm bs n start (+ j 1) depth inStr false strOpen))
        ((= b 40) (lpfForm bs n start (+ j 1) (+ depth 1) inStr false strOpen))
        ((= b 41) (lpfForm bs n start (+ j 1) (- depth 1) inStr false strOpen))
        (else (lpfForm bs n start (+ j 1) depth inStr false strOpen)))))

fn lpfLoop bs: Bytes n: Int64 i: Int64 -> (Option (Pair Int64 String))
  (cond
    ((>= i n) none)
    ((!= (bytesGet bs i) 40) (lpfLoop bs n (+ i 1)))
    (else
      (mt (lpfForm bs n i (+ i 1) 1 false false -1)
        ((pair j found) (mt found ((some f) (some f)) (none (lpfLoop bs n j)))))))

fn locateParseFailure text: String -> (Option (Pair Int64 String))
  (let [bs (stringToBytes text)]
    (lpfLoop bs (bytesLength bs) 0))

fn describeParseFailure text: String -> (Option String)
  (mt (locateParseFailure text)
    (none none)
    ((some loc)
      (mt loc ((pair boff what)
        (let [off (charsBefore text boff)
              excerpt (stringReplace (sl text (byteOfChar text (max 0 (- off 30))) (byteOfChar text (+ off 30))) "\n" "\\n")
              tail (if (!= what "string closed") " and never closes" "")]
          (some (str what " at char " (stringFromInt64 off) tail ": \"" excerpt "\"")))))))

enum Ar
  (ar kept: (List String) repaired: (List String) left: (List String) spans: (List (Pair Int64 Int64)) kinds: (List String) quote: Int64)

fn addKind kinds: (List String) k: String -> (List String)
  (if (member k kinds) kinds (listAppend kinds (list k)))

fn nearOf chunk: String -> String
  (c/escapeAsn (charCut (pyStrip chunk) 60))

fn leftItem idx: Int64 why: String chunk: String -> String
  (str "(:at " (stringFromInt64 idx) " :why \"" (c/escapeAsn why) "\" :near \"" (nearOf chunk) "\")")

fn errText r: (Result (List (List (Pair String c/KvVal))) String) -> String
  (mt r ((err e) e) ((ok _) ""))

fn arFinal st: Ar chunk: String s: Int64 e: Int64 idx: Int64 why0: String -> Ar
  (mt st ((ar kept rep left spans kinds q)
    (let [pieces (splitChunkLines chunk)
          pk (filter (fn [p] (ok? (chunkOps p))) pieces)]
      (if (and (> (listLength pieces) 1) (not (listEmpty? pk)))
        (let [kept2 (fold (fn [acc p] (cons p acc)) kept pk)]
          (if (< (listLength pk) (listLength pieces))
            (ar kept2 rep (cons (leftItem idx "unreadable form" chunk) left) (cons (pair s e) spans) kinds q)
            (ar kept2 rep left spans kinds q)))
        (let [why (mt (describeParseFailure chunk) ((some d) d) (none (if (= why0 "") "form does not parse" why0)))]
          (ar kept rep (cons (leftItem idx (charCut why 120) chunk) left) (cons (pair s e) spans) kinds q))))))

fn itemCloser it: RepairItem -> Bool
  (mt it ((repairItem k t _ _) (and (= k "insert") (isCloserTok t))))

fn itemAt it: RepairItem ref: (Pair Int64 Int64) -> Bool
  (mt it ((repairItem _ _ l co) (and (= l (pairFirst ref)) (= co (pairSecond ref)))))

fn arDelim st: Ar chunk: String s: Int64 e: Int64 idx: Int64 why0: String -> Ar
  (let [fixed (coreRepairDelimiters chunk "asn")
        newText (pairFirst fixed)
        receipt (pairSecond fixed)
        items (repairReceiptItems receipt)
        closerOnly (and (not (listEmpty? items)) (listAll? itemCloser items))
        ref (offsetToLinecol chunk (repairRefOffset chunk))
        local (and closerOnly (listAll? (fn [it] (itemAt it ref)) items))
        would (and closerOnly (and (stringContains? receipt ":left ()") (ok? (chunkOps newText))))]
    (mt st ((ar kept rep left spans kinds q)
      (cond
        ((and would local)
          (ar (cons newText kept) (cons (str "(\"delimiter\" :at " (stringFromInt64 idx) " :fix \"" (c/escapeAsn (delimiterFixDesc items)) "\")") rep) left spans (addKind kinds "delimiter") q))
        (would
          (mt (c/firstOf items) ((repairItem _ _ ln0 co0)
            (ar kept rep (cons (leftItem idx (str "delimiter repair not local: insert at line " (stringFromInt64 ln0) " col " (stringFromInt64 co0) " swallows later content") chunk) left) (cons (pair s e) spans) kinds q))))
        (else (arFinal st chunk s e idx why0))))))

fn arChunk reply: String st: Ar s: Int64 e: Int64 idx: Int64 -> Ar
  (let [chunk (sl reply s e)
        first (chunkOps chunk)]
    (if (ok? first)
      (mt st ((ar kept rep left spans kinds q) (ar (cons chunk kept) rep left spans kinds q)))
      (let [qr (repairInnerQuotes chunk)
            qText (pairFirst qr)
            qCount (pairSecond qr)]
        (if (and (> qCount 0) (ok? (chunkOps qText)))
          (mt st ((ar kept rep left spans kinds q)
            (ar (cons qText kept) (cons (str "(\"quote\" :at " (stringFromInt64 idx) ")") rep) left spans (addKind kinds "quote") (+ q qCount))))
          (arDelim st chunk s e idx (errText first))))))

fn arLoop reply: String spans: (List (Pair Int64 Int64)) idx: Int64 st: Ar -> Ar
  (if (listEmpty? spans)
    st
    (mt (c/firstOf spans) ((pair s e)
      (arLoop reply (c/restOf spans) (+ idx 1) (arChunk reply st s e idx)))))

fn autoRepairReply reply: String -> AutoRepair
  (let [spans (formChunks reply)]
    (if (listEmpty? spans)
      (AutoRepair :text "" :notice (some (str "(:left ((:why \"no forms\" :near \"" (c/escapeAsn (charCut (pyStrip reply) 60)) "\")))")) :kinds (list) :left 1 :quoteCount 0 :leftSpans none)
      (mt (arLoop reply spans 1 (ar (list) (list) (list) (list) (list) 0))
        ((ar kept rep left sp kinds q)
          (AutoRepair :text (joinWith (listReverse kept) "\n")
                      :notice (if (and (listEmpty? rep) (listEmpty? left)) none (some (str "(:repaired (" (joinWith (listReverse rep) " ") ") :left (" (joinWith (listReverse left) " ") "))")))
                      :kinds kinds :left (listLength left) :quoteCount q :leftSpans (some (listReverse sp)))))))

fn parseReply reply: String -> (List (List (Pair String c/KvVal)))
  (c/parseReply (bindRawBlocks reply).text)

fn isHeadB b: Int64 -> Bool
  (or (isAsciiAlpha b) (or (isDigitB b) (or (= b 95) (= b 45))))

fn isCutAtom b: Int64 -> Bool
  (not (or (isSpaceB b) (or (isOpener b) (or (isCloser b) (or (= b 34) (= b 59))))))

fn ctToks s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [b (bytesGet bs i)]
      (cond
        ((= b 34)
          (let [e (rxStrBody bs n (+ i 1))]
            (if (>= e 0) (ctToks s bs n (+ e 1) (cons (sl s i (+ e 1)) acc)) (ctToks s bs n (+ i 1) acc))))
        ((= b 59) (let [j (skipComment bs n i)] (ctToks s bs n j (cons (pyStrip (sl s i j)) acc))))
        ((or (isOpener b) (isCloser b)) (ctToks s bs n (+ i 1) (cons (sl s i (+ i 1)) acc)))
        ((isSpaceB b) (ctToks s bs n (+ i 1) acc))
        (else (let [j (skipWhile bs n i isCutAtom)] (ctToks s bs n j (cons (sl s i j) acc)))))))

fn cutUnescapeOf b: Int64 -> String
  (cond ((= b 110) "\n") ((= b 114) "\r") ((= b 116) "\t") ((= b 34) "\"") ((= b 92) "\\") (else ""))

fn cutUnescLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (c/joinAll (listReverse (cons (sl s start n) acc))))
    ((and (= (bytesGet bs i) 92) (!= (cutUnescapeOf (at bs n (+ i 1))) ""))
      (cutUnescLoop s bs n (+ i 2) (+ i 2) (cons (cutUnescapeOf (bytesGet bs (+ i 1))) (cons (sl s start i) acc))))
    (else (cutUnescLoop s bs n (+ i 1) start acc)))

fn cutUnescape s: String -> String
  (let [bs (stringToBytes s)] (cutUnescLoop s bs (bytesLength bs) 0 0 (list)))

fn lstripColons s: String -> String
  (let [bs (stringToBytes s)] (sl s (skipWhile bs (bytesLength bs) 0 (fn [b] (= b 58))) (stringLength s)))

fn cutVal nxt: String -> String
  (if (and (>= (stringLength nxt) 2) (and (stringStartsWith? nxt "\"") (stringEndsWith? nxt "\"")))
    (cutUnescape (sl nxt 1 (- (stringLength nxt) 1)))
    (lstripColons nxt))

fn ctFields toks: (List String) op: (Option String) file: (Option String) -> (Pair (Option String) (Option String))
  (if (or (listEmpty? toks) (listEmpty? (c/restOf toks)))
    (pair op file)
    (let [tok (c/firstOf toks)
          v (cutVal (c/firstOf (c/restOf toks)))]
      (cond
        ((and (= tok ":op") (none? op)) (ctFields (c/restOf toks) (some v) file))
        ((and (or (= tok ":file") (= tok ":path")) (none? file)) (ctFields (c/restOf toks) op (some v)))
        (else (ctFields (c/restOf toks) op file)))))

fn strOpenAt bs: Bytes n: Int64 i: Int64 inStr: Bool esc: Bool start: Int64 -> Int64
  (if (>= i n)
    (if inStr start -1)
    (let [b (bytesGet bs i)]
      (cond
        (esc (strOpenAt bs n (+ i 1) inStr false start))
        ((and (= b 92) inStr) (strOpenAt bs n (+ i 1) inStr true start))
        ((= b 34) (if inStr (strOpenAt bs n (+ i 1) false false -1) (strOpenAt bs n (+ i 1) true false i)))
        (else (strOpenAt bs n (+ i 1) inStr false start)))))

fn cutHead bs: Bytes n: Int64 s: String -> (Option String)
  (if (!= (at bs n 0) 40)
    none
    (let [a (skipSpaces bs n 1)
          b (if (= (at bs n a) 58) (+ a 1) a)
          e (skipWhile bs n b isHeadB)]
      (if (> e b) (some (sl s b e)) none)))

fn parseCutInfo cutStart: Int64 cutText: String fullText: String -> CutInfo
  (let [bs (stringToBytes cutText)
        n (bytesLength bs)
        head (cutHead bs n cutText)
        so (strOpenAt bs n 0 false false -1)
        prefix (if (>= so 0) (sl cutText 0 so) cutText)
        pb (stringToBytes prefix)
        toks (ctToks prefix pb (bytesLength pb) 0 (list))
        of (ctFields toks none none)
        op0 (pairFirst of)
        op (if (and (none? op0) (mt head ((some h) (member h (list "read" "write" "edit" "run" "tree" "outline"))) (none false))) head op0)]
    (CutInfo :offset (stringLength (sl fullText 0 cutStart)) :bytes n :head head :op op :file (pairSecond of) :start cutStart :text cutText))

fn dcLoop text: String bs: Bytes n: Int64 i: Int64 last: Int64 -> (Option CutInfo)
  (if (>= i n)
    none
    (let [b (bytesGet bs i)]
      (cond
        ((isSpaceB b) (dcLoop text bs n (+ i 1) last))
        ((= b 59) (dcLoop text bs n (skipComment bs n i) last))
        ((!= b 40) (dcLoop text bs n (+ i 1) last))
        (else
          (mt (formClose bs n (+ i 1) 1 false false)
            ((pair j depth)
              (if (= depth 0)
                (dcLoop text bs n j j)
                (if (>= last 0)
                  (let [tail (sl text last n)
                        ls (pyLstrip tail)]
                    (if (stringStartsWith? ls "(")
                      (let [cs (+ last (- (stringLength tail) (stringLength ls)))]
                        (some (parseCutInfo cs (sl text cs n) text)))
                      (dcLoop text bs n j last)))
                  (dcLoop text bs n j last)))))))))

fn detectCutForm text: String -> (Option CutInfo)
  (let [bs (stringToBytes text)]
    (dcLoop text bs (bytesLength bs) 0 -1))

fn tlsLoop bs: Bytes n: Int64 i: Int64 depth: Int64 inStr: Bool start: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (let [b (bytesGet bs i)]
      (cond
        ((and inStr (= b 92)) (tlsLoop bs n (+ i 2) depth inStr start acc))
        (inStr (tlsLoop bs n (+ i 1) depth (!= b 34) start acc))
        ((= b 34) (tlsLoop bs n (+ i 1) depth true start acc))
        ((= b 40) (tlsLoop bs n (+ i 1) (+ depth 1) false (if (= depth 0) i start) acc))
        ((= b 41)
          (cond
            ((and (= depth 1) (>= start 0)) (tlsLoop bs n (+ i 1) 0 false -1 (cons (pair start (+ i 1)) acc)))
            ((< (- depth 1) 0) (tlsLoop bs n (+ i 1) 0 false start acc))
            (else (tlsLoop bs n (+ i 1) (- depth 1) false start acc))))
        (else (tlsLoop bs n (+ i 1) depth false start acc)))))

fn topLevelSpans reply: String -> (List (Pair Int64 Int64))
  (let [bs (stringToBytes reply)]
    (tlsLoop bs (bytesLength bs) 0 0 false -1 (list)))

enum SpanCp
  (spanCp a: Int64 b: Int64 ca: Int64 cb: Int64)

fn cpLoop reply: String spans: (List (Pair Int64 Int64)) prev: Int64 cprev: Int64 acc: (List SpanCp) -> (List SpanCp)
  (if (listEmpty? spans)
    (listReverse acc)
    (mt (c/firstOf spans) ((pair a b)
      (let [ca (+ cprev (c/charLen (sl reply prev a)))
            cb (+ ca (c/charLen (sl reply a b)))]
        (cpLoop reply (c/restOf spans) b cb (cons (spanCp a b ca cb) acc))))))

fn spA x: SpanCp -> Int64
  (mt x ((spanCp a _ _ _) a))

fn spB x: SpanCp -> Int64
  (mt x ((spanCp _ b _ _) b))

fn blockEnd xs: (List SpanCp) ca: Int64 -> (Option Int64)
  (cond
    ((listEmpty? xs) none)
    ((>= (- (mt (c/firstOf xs) ((spanCp _ _ _ cb) cb)) ca) 400) (some (spB (c/firstOf xs))))
    (else (blockEnd (c/restOf xs) ca)))

fn dropBelow es: (List Int64) t: Int64 -> (List Int64)
  (if (and (not (listEmpty? es)) (< (c/firstOf es) t)) (dropBelow (c/restOf es) t) es)

fn occLoop reply: String block: String len: Int64 xs: (List SpanCp) es: (List Int64) count: Int64 p0: Int64 p1: Int64 best: Int64 -> (Pair Int64 Int64)
  (cond
    ((listEmpty? xs) (pair count p1))
    ((and (>= best 0) (and (>= count 2) (>= p1 best))) (pair -1 p1))
    (else
      (let [a (spA (c/firstOf xs))
            t (+ a len)
            es2 (dropBelow es t)
            hit (and (not (listEmpty? es2)) (and (= (c/firstOf es2) t) (= (sl reply a t) block)))]
        (if hit
          (occLoop reply block len (c/restOf xs) es2 (+ count 1) (if (= count 0) a p0) (if (= count 1) a p1) best)
          (occLoop reply block len (c/restOf xs) es2 count p0 p1 best)))))

fn dgLoop reply: String rest: (List SpanCp) all: (List SpanCp) ends: (List Int64) best: (Option (Pair Int64 Int64)) -> (Option (Pair Int64 Int64))
  (if (listEmpty? rest)
    best
    (mt (c/firstOf rest) ((spanCp a _ ca _)
      (mt (blockEnd rest ca)
        (none (dgLoop reply (c/restOf rest) all ends best))
        ((some e)
          (let [block (sl reply a e)
                bestPos (mt best ((some bp) (pairFirst bp)) (none -1))
                r (occLoop reply block (- e a) all ends 0 -1 -1 bestPos)
                count (pairFirst r)
                second (pairSecond r)]
            (if (and (>= count 3) (or (< bestPos 0) (< second bestPos)))
              (dgLoop reply (c/restOf rest) all ends (some (pair second count)))
              (dgLoop reply (c/restOf rest) all ends best))))))))

fn degenerateCut reply: String -> (Option (Pair Int64 Int64))
  (if (< (c/charLen reply) 1200)
    none
    (let [spans (cpLoop reply (topLevelSpans reply) 0 0 (list))]
      (dgLoop reply spans spans (map spB spans) none)))

fn capScan bs: Bytes n: Int64 i: Int64 end: Int64 depth: Int64 inStr: Bool -> Int64
  (if (>= i n)
    end
    (let [b (bytesGet bs i)]
      (cond
        ((and inStr (= b 92)) (capScan bs n (+ i 2) end depth inStr))
        (inStr (capScan bs n (+ i 1) end depth (!= b 34)))
        ((= b 34) (capScan bs n (+ i 1) end depth true))
        ((= b 40) (capScan bs n (+ i 1) end (+ depth 1) false))
        ((= b 41) (if (<= (- depth 1) 0) (capScan bs n (+ i 1) (+ i 1) 0 false) (capScan bs n (+ i 1) end (- depth 1) false)))
        (else (capScan bs n (+ i 1) end depth false)))))

fn isContB b: Int64 -> Bool
  (and (>= b 128) (<= b 191))

fn utf8Need b: Int64 -> Int64
  (cond ((< b 128) 1) ((and (>= b 192) (<= b 223)) 2) ((and (>= b 224) (<= b 239)) 3) ((>= b 240) 4) (else 1))

fn dropPartial s: String -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        k (backWhile bs n isContB)
        lead (- k 1)]
    (if (or (< lead 0) (< (- n k) 0) (> (- n k) 3))
      s
      (if (< (- n lead) (utf8Need (bytesGet bs lead))) (sl s 0 lead) s)))

fn capReply reply: String -> (Pair String Int64)
  (let [n (stringLength reply)]
    (if (<= n (replyMaxBytes))
      (pair reply 0)
      (let [bs (stringToBytes reply)
            end (capScan bs (min n (replyMaxBytes)) 0 0 0 false)]
        (pair (if (> end 0) (sl reply 0 end) (dropPartial (sl reply 0 (replyMaxBytes)))) n))))

fn replyFacts replyText: String declared: (Option (List String)) -> ReplyFacts
  (let [text (bindRawBlocks replyText).text
        parsed (c/parseReply text)
        ops (c/uniqueSteps parsed)]
    (ReplyFacts :ops ops :repeated (- (listLength parsed) (listLength ops)) :forms (c/parseForms text) :prose (c/isProseWrapped text)
                :dataFindings (mt declared ((some d) (c/dataFindings text d)) (none (list))) :cut (detectCutForm text)))

fn ! receiptId! -> String
  (sl (bytesSha256 (stringToBytes (str (stringFromInt64 (nowNs)) ":" (stringFromInt64 (procSelf)) ":" (stringFromInt64 (monotonicNs))))) 0 12)

fn ! needsConfirmReceipt! opName: String -> NeedsConfirm
  (NeedsConfirm :id (receiptId!) :op opName
    :message (str "not executed: '" opName "' is an outward effect that needs the principal's confirmation; the run goes on"))

fn isShSpace b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 13) (= b 10))))

fn tokText tok: (List String) -> String
  (c/joinAll (listReverse tok))

fn shLoop s: String bs: Bytes n: Int64 i: Int64 state: Int64 escState: Int64 tok: (List String) toks: (List String) -> (Result (List String) String)
  (if (>= i n)
    (cond
      ((or (= state 2) (= state 3)) (err "No closing quotation"))
      ((= state 4) (err "No escaped character"))
      ((= state 1) (ok (listReverse (cons (tokText tok) toks))))
      (else (ok (listReverse toks))))
    (let [b (bytesGet bs i)
          ch (sl s i (+ i 1))]
      (cond
        ((= state 0)
          (cond
            ((isShSpace b) (shLoop s bs n (+ i 1) 0 escState tok toks))
            ((= b 92) (shLoop s bs n (+ i 1) 4 1 tok toks))
            ((= b 39) (shLoop s bs n (+ i 1) 2 escState tok toks))
            ((= b 34) (shLoop s bs n (+ i 1) 3 escState tok toks))
            (else (shLoop s bs n (+ i 1) 1 escState (list ch) toks))))
        ((= state 2)
          (if (= b 39) (shLoop s bs n (+ i 1) 1 escState tok toks) (shLoop s bs n (+ i 1) 2 escState (cons ch tok) toks)))
        ((= state 3)
          (cond
            ((= b 34) (shLoop s bs n (+ i 1) 1 escState tok toks))
            ((= b 92) (shLoop s bs n (+ i 1) 4 3 tok toks))
            (else (shLoop s bs n (+ i 1) 3 escState (cons ch tok) toks))))
        ((= state 4)
          (let [tok2 (if (and (= escState 3) (and (!= b 92) (!= b 34))) (cons "\\" tok) tok)]
            (shLoop s bs n (+ i 1) escState escState (cons ch tok2) toks)))
        (else
          (cond
            ((isShSpace b) (shLoop s bs n (+ i 1) 0 escState (list) (cons (tokText tok) toks)))
            ((= b 39) (shLoop s bs n (+ i 1) 2 escState tok toks))
            ((= b 34) (shLoop s bs n (+ i 1) 3 escState tok toks))
            ((= b 92) (shLoop s bs n (+ i 1) 4 1 tok toks))
            (else (shLoop s bs n (+ i 1) 1 escState (cons ch tok) toks)))))))

fn shlexSplit s: String -> (Result (List String) String)
  (let [bs (stringToBytes s)]
    (shLoop s bs (bytesLength bs) 0 0 1 (list) (list)))

fn baseName p: String -> String
  (let [bs (stringToBytes p)
        k (backWhile bs (bytesLength bs) (fn [b] (!= b 47)))]
    (sl p k (stringLength p)))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr t) t) ((c/kvInt t) (mt (stringToInt64 t) ((some i) (stringFromInt64 i)) (none t))))

fn opStr op: (List (Pair String c/KvVal)) k: String -> String
  (mt (c/dictGet op k) ((some v) (kvText v)) (none ""))

fn isDigits s: String -> Bool
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (and (> n 0) (= (skipWhile bs n 0 isDigitB) n)))

fn joinRoot root: String a: String -> String
  (cond
    ((stringStartsWith? a "/") a)
    ((or (= root "") (stringEndsWith? root "/")) (str root a))
    (else (str root "/" a)))

fn ! isFile? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn lineCount bs: Bytes n: Int64 i: Int64 k: Int64 open: Bool -> Int64
  (if (>= i n)
    (if open (+ k 1) k)
    (let [b (bytesGet bs i)]
      (cond
        ((and (= b 13) (= (at bs n (+ i 1)) 10)) (lineCount bs n (+ i 2) (+ k 1) false))
        ((or (= b 13) (= b 10)) (lineCount bs n (+ i 1) (+ k 1) false))
        (else (lineCount bs n (+ i 1) k true)))))

fn indexIn xs: (List String) x: String i: Int64 -> Int64
  (cond ((listEmpty? xs) -1) ((= (c/firstOf xs) x) i) (else (indexIn (c/restOf xs) x (+ i 1))))

fn firstSome xs: (List String) f: (fn [String] -> (Option String)) -> (Option String)
  (if (listEmpty? xs) none (mt (f (c/firstOf xs)) ((some v) (some v)) (none (firstSome (c/restOf xs) f))))

fn countArg rest: (List String) -> String
  (let [c1 (optionOr (firstSome rest (fn [a] (if (and (stringStartsWith? a "-") (isDigits (sl a 1 (stringLength a)))) (some (sl a 1 (stringLength a))) none))) "")
        ni (indexIn rest "-n" 0)
        c2 (if (and (>= ni 0) (< (+ ni 1) (listLength rest))) (mt (listGet rest (+ ni 1)) ((some v) v) (none c1)) c1)]
    (if (!= c2 "")
      c2
      (optionOr (firstSome rest (fn [a] (if (and (stringStartsWith? a "-n") (isDigits (lstripPlus (sl a 2 (stringLength a))))) (some (sl a 2 (stringLength a))) none))) "")))

fn lstripPlus s: String -> String
  (let [bs (stringToBytes s)] (sl s (skipWhile bs (bytesLength bs) 0 (fn [b] (= b 43))) (stringLength s)))

fn toInt s: String -> Int64
  (optionOr (stringToInt64 s) 0)

fn sedSpan a: String -> (Option (Pair Int64 Int64))
  (if (not (stringEndsWith? a "p"))
    none
    (let [body (sl a 0 (- (stringLength a) 1))
          parts (stringSplit body ",")]
      (cond
        ((and (= (listLength parts) 1) (isDigits body)) (some (pair (toInt body) (toInt body))))
        ((and (= (listLength parts) 2) (and (isDigits (c/firstOf parts)) (isDigits (c/firstOf (c/restOf parts)))))
          (some (pair (toInt (c/firstOf parts)) (toInt (c/firstOf (c/restOf parts))))))
        (else none))))

fn firstSpan xs: (List String) -> (Option (Pair Int64 Int64))
  (if (listEmpty? xs) none (mt (sedSpan (c/firstOf xs)) ((some v) (some v)) (none (firstSpan (c/restOf xs)))))

fn hasMeta cmd: String -> Bool
  (listAny? (fn [m] (stringContains? cmd m)) (list "|" ";" "&" ">" "<" "`" "$"))

fn isSepWord w: String -> Bool
  (or (member w (list "|" ";" "&&" "||" ">" ">>" "<")) (or (stringStartsWith? w ">") (stringStartsWith? w "|")))

fn stepMsg files: (List String) -> String
  (if (listEmpty? files)
    "a read by run bypasses the window; use (:step :op \"read\" :file f) or (:step :op \"outline\" :file f)"
    (str "a read by run bypasses the window; use one step per file: "
      (joinWith (map (fn [f] (str "(:step :op \"read\" :file \"" (c/escapeAsn f) "\")")) files) " ")))

fn ! runAsRead! op: (List (Pair String c/KvVal)) rootDir: String -> (Result RunRead String)
  (if (or (!= (opStr op "type") "step") (!= (opStr op "op") "run"))
    (ok (runUnchanged))
    (let [cmd (cond ((c/truthy (c/dictGet op "argv")) (opStr op "argv")) ((c/truthy (c/dictGet op "cmd")) (opStr op "cmd")) (else ""))
          form (opStr op "form")]
      (mt (shlexSplit cmd)
        ((err _) (ok (runUnchanged)))
        ((ok words)
          (let [tool (if (listEmpty? words) "" (baseName (c/firstOf words)))]
            (if (or (not (member tool (list "cat" "less" "more" "nl" "head" "tail" "sed" "grep" "rg"))) (or (listAny? isSepWord words) (hasMeta cmd)))
              (ok (runUnchanged))
              (let [args (c/restOf words)
                    files (filter (fn [a] (and (not (stringStartsWith? a "-")) (isFile? (joinRoot rootDir a)))) args)]
                (cond
                  ((or (= tool "grep") (= tool "rg"))
                    (ok (runHint cmd form "a search by run bypasses the window; use (:step :op \"query\" :query s [:in text]) or (:step :op \"read\" :file f :anchor s)")))
                  ((!= (listLength files) 1) (ok (runHint cmd form (stepMsg files))))
                  (else (readStep! tool cmd form (c/firstOf files) (filter (fn [a] (!= a (c/firstOf files))) args) rootDir))))))))))

fn ! readStep! tool: String cmd: String form: String file: String rest: (List String) rootDir: String -> (Result RunRead String)
  (let [count (countArg rest)
        step (fn [sp] (runStep file cmd form sp))]
    (cond
      ((= tool "head") (ok (step (some (pair 1 (max 1 (if (isDigits count) (toInt count) 10)))))))
      ((= tool "tail")
        (mt (fileReadBytes (joinRoot rootDir file))
          ((err e) (err e))
          ((ok data)
            (let [total (lineCount data (bytesLength data) 0 0 false)
                  tailArg (sl count 1 (stringLength count))
                  start (if (and (stringStartsWith? count "+") (isDigits tailArg)) (toInt tailArg) (+ (- total (if (isDigits count) (toInt count) 10)) 1))]
              (ok (step (some (pair (max 1 start) (max 1 total)))))))))
      ((= tool "sed")
        (mt (firstSpan rest)
          ((some sp) (if (member "-n" rest) (ok (step (some sp))) (ok (runUnchanged))))
          (none (ok (runUnchanged)))))
      ((or (listEmpty? rest) (= tool "nl")) (ok (step none)))
      (else (ok (runUnchanged)))))

fn isKwB b: Int64 -> Bool
  (or (isAsciiAlpha b) (or (isDigitB b) (or (= b 95) (= b 45))))

fn tfLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List FormTok) -> (List FormTok)
  (if (>= i n)
    (listReverse acc)
    (let [b (bytesGet bs i)]
      (cond
        ((= b 34)
          (let [e (rxStrBody bs n (+ i 1))]
            (if (>= e 0) (tfLoop s bs n (+ e 1) (cons (formTok (sl s i (+ e 1)) i (+ e 1)) acc)) (tfLoop s bs n (+ i 1) acc))))
        ((= b 59) (tfLoop s bs n (skipComment bs n i) acc))
        ((or (isOpener b) (isCloser b)) (tfLoop s bs n (+ i 1) (cons (formTok (sl s i (+ i 1)) i (+ i 1)) acc)))
        ((and (= b 58) (isKwB (at bs n (+ i 1))))
          (let [j (skipWhile bs n (+ i 1) isKwB)] (tfLoop s bs n j (cons (formTok (sl s i j) i j) acc))))
        ((isSpaceB b) (tfLoop s bs n (+ i 1) acc))
        (else (let [j (skipWhile bs n i isCutAtom)] (tfLoop s bs n j (cons (formTok (sl s i j) i j) acc)))))))

fn tokenizeForm formText: String -> (List FormTok)
  (let [bs (stringToBytes formText)]
    (tfLoop formText bs (bytesLength bs) 0 (list)))

fn isSpTab b: Int64 -> Bool
  (or (= b 32) (= b 9))

fn isFenceTag b: Int64 -> Bool
  (or (isAsciiAlpha b) (or (isDigitB b) (or (= b 95) (or (= b 46) (= b 45)))))

fn nextLineStart bs: Bytes n: Int64 p: Int64 -> Int64
  (cond ((>= p n) (+ n 1)) ((= (bytesGet bs p) 10) (+ p 1)) (else (nextLineStart bs n (+ p 1))))

fn closeLineEnd bs: Bytes n: Int64 l: Int64 k: Int64 -> Int64
  (let [q (skipWhile bs n l isSpTab)
        e (skipWhile bs n q (fn [b] (= b 96)))]
    (if (!= (- e q) k)
      -1
      (let [r (skipWhile bs n e isSpTab)]
        (cond
          ((>= r n) r)
          ((= (bytesGet bs r) 10) (+ r 1))
          ((and (= (bytesGet bs r) 13) (= (at bs n (+ r 1)) 10)) (+ r 2))
          (else -1)))))

fn findClose bs: Bytes n: Int64 l: Int64 k: Int64 -> (Pair Int64 Int64)
  (if (> l n)
    (pair -1 -1)
    (let [e (closeLineEnd bs n l k)]
      (if (>= e 0) (pair l e) (findClose bs n (nextLineStart bs n l) k))))

fn fenceAt s: String bs: Bytes n: Int64 p: Int64 -> (Option Fence)
  (let [q (skipWhile bs n p isSpTab)
        e (skipWhile bs n q (fn [b] (= b 96)))]
    (if (< (- e q) 3)
      none
      (let [r (skipWhile bs n (skipWhile bs n e isFenceTag) isSpTab)
            r2 (if (= (at bs n r) 13) (+ r 1) r)]
        (if (!= (at bs n r2) 10)
          none
          (mt (findClose bs n (+ r2 1) (- e q))
            ((pair l end) (if (< l 0) none (some (fence p end (sl s (+ r2 1) l))))))))))

fn rfLoop s: String bs: Bytes n: Int64 p: Int64 acc: (List Fence) -> (List Fence)
  (if (> p n)
    (listReverse acc)
    (mt (fenceAt s bs n p)
      ((some f) (mt f ((fence _ end _) (rfLoop s bs n (if (> end p) end (nextLineStart bs n p)) (cons f acc)))))
      (none (rfLoop s bs n (nextLineStart bs n p) acc))))

fn rawFences reply: String -> (List Fence)
  (let [bs (stringToBytes reply)]
    (rfLoop reply bs (bytesLength bs) 0 (list)))

fn fStart f: Fence -> Int64
  (mt f ((fence a _ _) a))

fn fEnd f: Fence -> Int64
  (mt f ((fence _ b _) b))

fn afterRaw bs: Bytes p: Int64 -> Bool
  (let [k (backWhile bs p isSpaceB)]
    (and (>= k 4) (and (= (bytesGet bs (- k 4)) 58) (and (= (bytesGet bs (- k 3)) 114) (and (= (bytesGet bs (- k 2)) 97) (= (bytesGet bs (- k 1)) 119))))))

fn rstripNl s: String -> String
  (let [bs (stringToBytes s)] (sl s 0 (backWhile bs (bytesLength bs) (fn [b] (= b 10)))))

fn hoistClose bs: Bytes n: Int64 j: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (>= j n)
    j
    (let [b (bytesGet bs j)]
      (cond
        (esc (hoistClose bs n (+ j 1) depth inStr false))
        (inStr (hoistClose bs n (+ j 1) depth (!= b 34) (= b 92)))
        ((= b 34) (hoistClose bs n (+ j 1) depth true false))
        ((= b 40) (hoistClose bs n (+ j 1) (+ depth 1) false false))
        ((= b 41) (if (= (- depth 1) 0) j (hoistClose bs n (+ j 1) (- depth 1) false false)))
        (else (hoistClose bs n (+ j 1) depth false false)))))

fn nextOpen bs: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 40)) i (nextOpen bs n (+ i 1)))

fn takeBlocks blocks: (List (Pair Int64 String)) end: Int64 acc: (List String) -> (Pair (List String) (List (Pair Int64 String)))
  (if (and (not (listEmpty? blocks)) (< (pairFirst (c/firstOf blocks)) end))
    (takeBlocks (c/restOf blocks) end (cons (pairSecond (c/firstOf blocks)) acc))
    (pair (listReverse acc) blocks))

fn hoistLoop text: String bs: Bytes n: Int64 i: Int64 blocks: (List (Pair Int64 String)) out: (List String) -> String
  (if (>= i n)
    (c/joinAll (listReverse (fold (fn [acc b] (cons (pairSecond b) acc)) out blocks)))
    (if (!= (bytesGet bs i) 40)
      (let [j (nextOpen bs n i)] (hoistLoop text bs n j blocks (cons (sl text i j) out)))
      (let [end (min (+ (hoistClose bs n i 0 false false) 1) n)
            tb (takeBlocks blocks end (list))
            mine (pairFirst tb)
            out2 (cons (sl text i end) out)]
        (hoistLoop text bs n end (pairSecond tb) (if (listEmpty? mine) out2 (cons (str "\n" (c/joinAll mine)) out2))))))

fn hoistInlineRaw reply: String -> String
  (let [bs (stringToBytes reply)
        inline (filter (fn [f] (afterRaw bs (fStart f))) (rawFences reply))]
    (if (listEmpty? inline)
      reply
      (let [st (fold (fn [acc f]
                       (mt acc ((pair pos pr)
                         (mt pr ((pair kept blocks)
                           (let [piece (sl reply pos (fStart f))
                                 klen (+ (listLength kept) 0)]
                             (pair (fEnd f) (pair (cons piece kept) (cons (pair (c/joinAll (listReverse (cons piece kept))) (str (rstripNl (sl reply (fStart f) (fEnd f))) "\n")) blocks)))))))))
                     (pair 0 (pair (list) (list))) inline)
            pos (pairFirst st)
            kept (pairFirst (pairSecond st))
            text (c/joinAll (listReverse (cons (sl reply pos (stringLength reply)) kept)))
            blocks (listReverse (map (fn [b] (pair (stringLength (pairFirst b)) (pairSecond b))) (pairSecond (pairSecond st))))
            tbs (stringToBytes text)]
        (hoistLoop text tbs (bytesLength tbs) 0 blocks (list)))))

fn skipFence fences: (List Fence) i: Int64 -> (Pair Int64 (List Fence))
  (let [fs (dropFences fences i)]
    (if (and (not (listEmpty? fs)) (<= (fStart (c/firstOf fs)) i))
      (pair (fEnd (c/firstOf fs)) fs)
      (pair -1 fs)))

fn dropFences fences: (List Fence) i: Int64 -> (List Fence)
  (if (and (not (listEmpty? fences)) (<= (fEnd (c/firstOf fences)) i)) (dropFences (c/restOf fences) i) fences)

fn brForms s: String bs: Bytes n: Int64 i: Int64 fences: (List Fence) acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (mt (skipFence fences i)
      ((pair jump fs)
        (if (>= jump 0)
          (brForms s bs n jump fs acc)
          (let [b (bytesGet bs i)]
            (cond
              ((isSpaceB b) (brForms s bs n (+ i 1) fs acc))
              ((= b 59) (brForms s bs n (skipComment bs n i) fs acc))
              ((!= b 40) (brForms s bs n (+ i 1) fs acc))
              (else
                (mt (formClose bs n (+ i 1) 1 false false)
                  ((pair j depth) (brForms s bs n j fs (if (= depth 0) (cons (pair i j) acc) acc)))))))))))

fn tokT t: FormTok -> String
  (mt t ((formTok x _ _) x))

fn stripQuotes s: String -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        a (skipWhile bs n 0 (fn [b] (= b 34)))
        b (backWhile bs n (fn [x] (= x 34)))]
    (sl s a (max a b)))

enum RawField
  (rawField name: String start: Int64 end: Int64)

fn rfName r: RawField -> String
  (mt r ((rawField nm _ _) nm))

fn scanFields toks: (List FormTok) op: (Option String) file: (Option String) raws: (List RawField) -> (Pair (Pair (Option String) (Option String)) (List RawField))
  (if (or (listEmpty? toks) (listEmpty? (c/restOf toks)))
    (pair (pair op file) (listReverse raws))
    (let [t (tokT (c/firstOf toks))
          nx (c/firstOf (c/restOf toks))
          nxt (tokT nx)
          val (lstripColons (stripQuotes nxt))
          rest (c/restOf toks)]
      (cond
        ((and (= t ":op") (none? op)) (scanFields rest (some val) file raws))
        ((and (or (= t ":file") (= t ":path")) (none? file)) (scanFields rest op (some val) raws))
        ((and (member t (list ":content" ":old" ":new")) (= nxt ":raw"))
          (mt nx ((formTok _ ns ne) (scanFields rest op file (cons (rawField (sl t 1 (stringLength t)) ns ne) raws)))))
        (else (scanFields rest op file raws)))))

enum Repl
  (repl start: Int64 end: Int64 text: String)

fn rStart r: Repl -> Int64
  (mt r ((repl a _ _) a))

fn lastParen s: String -> Int64
  (let [bs (stringToBytes s)
        k (backWhile bs (bytesLength bs) (fn [b] (!= b 41)))]
    (- k 1))

fn insertBeforeLast s: String extra: String -> String
  (let [p (lastParen s)]
    (if (< p 0) (str s extra) (str (sl s 0 p) extra ")" (sl s (+ p 1) (stringLength s)))))

enum BrState
  (brState consumed: (List Int64) count: Int64 missing: (List (Pair String String)) repls: (List Repl))

fn indexed xs: (List Fence) i: Int64 -> (List (Pair Int64 Fence))
  (if (listEmpty? xs) (list) (cons (pair i (c/firstOf xs)) (indexed (c/restOf xs) (+ i 1))))

fn applyTok s: String reps: (List Repl) -> String
  (fold (fn [acc r] (mt r ((repl a b t) (str (sl acc 0 a) t (sl acc b (stringLength acc)))))) s
    (listReverse (listSortBy rStart reps)))

fn brForm reply: String fences: (List (Pair Int64 Fence)) st: BrState span: (Pair Int64 Int64) -> BrState
  (mt span ((pair fs fe)
    (let [ftext (sl reply fs fe)
          toks (tokenizeForm ftext)
          head (if (> (listLength toks) 1) (lstripColons (tokT (c/firstOf (c/restOf toks)))) "")
          op0 (if (member head (list "write" "edit")) (some head) none)
          scanned (scanFields toks op0 none (list))
          op (optionOr (pairFirst (pairFirst scanned)) "")
          file (optionOr (pairSecond (pairFirst scanned)) "")
          raws0 (pairSecond scanned)
          raws (if (= op "edit") (listAppend (filter (fn [r] (= (rfName r) "old")) raws0) (filter (fn [r] (!= (rfName r) "old")) raws0)) raws0)]
      (mt st ((brState consumed count missing repls)
        (if (or (not (member op (list "write" "edit"))) (listEmpty? raws))
          st
          (let [avail (filter (fn [p] (and (not (listAny? (fn [c] (= c (pairFirst p))) consumed)) (>= (fStart (pairSecond p)) fe))) fences)]
            (if (< (listLength avail) (listLength raws))
              (brState consumed count (cons (pair op file) missing) (cons (repl fs fe (insertBeforeLast ftext " :error \"ERR_RAW_MISSING\"")) repls))
              (let [used (listTake avail (listLength raws))
                    pairs (zip raws used)
                    tokReps (map (fn [pr] (mt pr ((pair r fp) (mt r ((rawField _ ns ne) (mt (pairSecond fp) ((fence _ _ content) (repl ns ne (str "\"" (c/escapeAsn content) "\""))))))))) pairs)
                    fenceReps (map (fn [fp] (repl (fStart (pairSecond fp)) (fEnd (pairSecond fp)) "")) used)
                    bound (applyTok ftext tokReps)
                    tagged (insertBeforeLast bound (str " :rawFields \"" (joinWith (map rfName raws) " ") "\""))]
                (brState (listAppend consumed (map pairFirst used)) (+ count (listLength raws)) missing
                  (cons (repl fs fe tagged) (fold (fn [acc r] (cons r acc)) repls fenceReps))))))))))))

fn assemble reply: String reps: (List Repl) last: Int64 acc: (List String) -> String
  (if (listEmpty? reps)
    (c/joinAll (listReverse (cons (sl reply last (stringLength reply)) acc)))
    (mt (c/firstOf reps) ((repl a b t)
      (assemble reply (c/restOf reps) b (cons t (cons (sl reply last a) acc))))))

fn bindRawBlocks reply: String -> RawBind
  (if (= reply "")
    (RawBind :text reply :count 0 :missing (list))
    (let [text (hoistInlineRaw reply)
          bs (stringToBytes text)
          fences (rawFences text)
          forms (brForms text bs (bytesLength bs) 0 fences (list))
          st (fold (fn [acc sp] (brForm text (indexed fences 0) acc sp)) (brState (list) 0 (list) (list)) forms)]
      (mt st ((brState _ count missing repls)
        (RawBind :text (assemble text (listSortBy rStart repls) 0 (list)) :count count :missing (listReverse missing))))))

fn tagEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (skipWhile bs n i (fn [b] (or (isAsciiAlpha b) (or (isDigitB b) (or (= b 95) (= b 45))))))

fn findTicks bs: Bytes n: Int64 p: Int64 -> Int64
  (cond ((> (+ p 3) n) -1) ((litAt bs n p "```") p) (else (findTicks bs n (+ p 1))))

fn ufLoop s: String bs: Bytes n: Int64 p: Int64 acc: (List String) -> (List String)
  (let [q (findTicks bs n p)]
    (if (< q 0)
      (listReverse acc)
      (let [r (skipWhile bs n (tagEnd bs n (+ q 3)) isSpTab)]
        (if (!= (at bs n r) 10)
          (ufLoop s bs n (+ q 1) acc)
          (let [e (findTicks bs n (+ r 1))]
            (if (< e 0)
              (listReverse acc)
              (ufLoop s bs n (+ e 3) (cons (sl s (+ r 1) e) acc))))))))

fn unfence reply: String -> String
  (let [bs (stringToBytes reply)
        forms (filter (fn [b] (stringStartsWith? b "(")) (map pyStrip (ufLoop reply bs (bytesLength bs) 0 (list))))]
    (if (listEmpty? forms) reply (joinWith forms "\n")))
