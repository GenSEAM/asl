(module asl/agentLoop/main
  :x [knownParams acceptedKeys nearestKey! tokenizeAsn Invocation paramGet parseInvocation
      ResumeTurn ResumeState RunArgs resumeReport journalResume journalModeHint
      NeedsConfirm OwnsRejection Usage Batching LoopResult formatReceipt receiptFieldsIn receiptFieldNames
      formatDryRun MainResult supportedBackends defaultModel liveAdvisor liveReviewer liveHooks! liveOwnsItems liveUsage livePlan
      providerUsageLine liveJournalUsage! liveProviderRetry! liveBody! loopResultOf main mainCli]
  :i [(asl/agentLoop/core :a c)
      (asl/agentLoop/diff :a diff)
      (asl/agentLoop/providers :a pv)
      (asl/agentLoop/context :a ctx)
      (asl/agentLoop/journal :a jr)
      (asl/agentLoop/gitOps :a go)
      (asl/agentLoop/runLoop :a rl)
      (asl/agentLoop/loopState :a ls)
      (asl/agentLoop/turn :a tr)
      (asl/agentLoop/exec :a ex)
      (asl/agentLoop/gates :a g)
      (asl/agentLoop/aslOps :a ao)
      (asl/agentLoop/txn :a tx)
      (asl/agentLoop/retry :a rt)
      (asl/agentLoop/plan :a pl)
      (asl/agentLoop/gateIntegrity :a gi)
      (asl/agentLoop/claims :a cl)
      (asl-json/json :a j)])

(schema Invocation
  (:f params (List (Pair String j/Json)))
  (:f unknownOps (List String))
  (:f syntaxError (Option String))
  (:f contextFileError (Option (Pair String String))))

(schema ResumeTurn
  (:f turn Int64)
  (:f sent String)
  (:f got String))

(schema ResumeState
  (:f session String)
  (:f journal String)
  (:f task String)
  (:f modeHint (Option String))
  (:f intent (Option String))
  (:f owns (List String))
  (:f gates (List String))
  (:f base String)
  (:f contextTokens (Option Int64))
  (:f note String)
  (:f result (Option String))
  (:f history (List ResumeTurn))
  (:f turn Int64)
  (:f reply String)
  (:f plan (Option pl/Plan)))

(schema NeedsConfirm
  (:f op String)
  (:f error String))

(schema OwnsRejection
  (:f turn Int64)
  (:f op String)
  (:f file String))

(schema Usage
  (:f input Int64)
  (:f cached Int64)
  (:f output Int64))

(schema Batching
  (:f turns Int64)
  (:f ops Int64)
  (:f single Int64))

(schema LoopResult
  (:f status String)
  (:f modeHint (Option String))
  (:f deliver (Option String))
  (:f phases (List String))
  (:f session (Option String))
  (:f journal (Option String))
  (:f unbacked Int64)
  (:f unbackedClaims (List String))
  (:f contextTokens (Option Int64))
  (:f turns (Option Int64))
  (:f gates (List j/Json))
  (:f escalate (Option String))
  (:f patch (Option String))
  (:f restored (List String))
  (:f written (List String))
  (:f needsConfirm (List NeedsConfirm))
  (:f ownsRejected (List OwnsRejection))
  (:f error (Option String))
  (:f gatePreflight (List (List (Pair String go/RVal))))
  (:f parseDefect Bool)
  (:f parseDefectTurn (Option Int64))
  (:f findings (Option (List String)))
  (:f queueWaitSec (Option Float64))
  (:f execSec (Option Float64))
  (:f usage (Option Usage))
  (:f batching (Option Batching))
  (:f plan (Option pl/PlanSummary)))

(schema MainResult
  (:f stdout String)
  (:f exitCode Int64))

(schema RunArgs
  (:f task String)
  (:f modeHint (Option String))
  (:f owns (List String))
  (:f gates (List String))
  (:f backend String)
  (:f model String)
  (:f timeout Int64)
  (:f timeoutSet Bool)
  (:f queueTimeout Int64)
  (:f budget Int64)
  (:f gateTimeout Int64)
  (:f wallBudget (Option Int64))
  (:f intent (Option String))
  (:f base String)
  (:f contextTokens (Option Int64))
  (:f plan Bool)
  (:f resume (Option ResumeState)))

fn knownParams -> (List String)
  (list "agent" "task" "mode" "intent" "root" "owns" "gates" "backend" "budget" "dryRun" "resume" "answer" "role"
        "model" "timeout" "contextFile" "base" "queueTimeout" "contextTokens" "gateTimeout" "wallBudget" "plan")

fn acceptedKeys -> (List String)
  (listSortBy (fn [k] k) (filter (fn [k] (not (listContains? (list "agent" "mode" "role") k))) (knownParams)))

fn keywordValued -> (List String)
  (list "intent" "mode" "role")

fn nearestLoop! unknown: String keys: (List String) best: String bestRatio: Float64 -> String
  (if (listEmpty? keys)
    best
    (let [k (c/firstOf keys)
          r (diff/ratio k unknown)
          better (or (> r bestRatio) (and (= r bestRatio) (> k best)))]
      (nearestLoop! unknown (c/restOf keys) (if better k best) (if better r bestRatio))))

fn nearestKey! unknown: String -> String
  (let [keys (acceptedKeys)]
    (nearestLoop! unknown (c/restOf keys) (c/firstOf keys) (diff/ratio (c/firstOf keys) unknown)))


fn byteAt bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn spaceWidth bs: Bytes n: Int64 i: Int64 -> Int64
  (let [b (byteAt bs n i)
        b1 (byteAt bs n (+ i 1))
        b2 (byteAt bs n (+ i 2))]
    (cond
      ((or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32))) 1)
      ((and (= b 194) (or (= b1 133) (= b1 160))) 2)
      ((and (= b 225) (= b1 154) (= b2 128)) 3)
      ((and (= b 226) (= b1 128) (or (and (>= b2 128) (<= b2 138)) (= b2 168) (= b2 169) (= b2 175))) 3)
      ((and (= b 226) (= b1 129) (= b2 159)) 3)
      ((and (= b 227) (= b1 128) (= b2 128)) 3)
      (else 0)))

fn spacesEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (let [w (spaceWidth bs n i)]
    (if (> w 0) (spacesEnd bs n (+ i w)) i))

fn charWidth b: Int64 -> Int64
  (cond ((>= b 240) 4) ((>= b 224) 3) ((>= b 192) 2) (else 1))

fn isDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isAlphaByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn isWordByte b: Int64 -> Bool
  (or (isAlphaByte b) (isDigitByte b) (= b 95))

fn runEnd bs: Bytes n: Int64 i: Int64 test: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (test (bytesGet bs i))) (runEnd bs n (+ i 1) test) i)

fn dropFirst s: String -> String
  (c/sliceOf s 1 (stringLength s))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (dropFirst s)) s)

fn underscoreDigits bs: Bytes n: Int64 i: Int64 acc: (List String) -> (Option String)
  (cond
    ((>= i n) (some (stringJoin (listReverse acc) "")))
    ((isDigitByte (bytesGet bs i)) (underscoreDigits bs n (+ i 1) (cons (stringFromInt64 (- (bytesGet bs i) 48)) acc)))
    ((and (= (bytesGet bs i) 95) (> i 0) (isDigitByte (byteAt bs n (- i 1))) (isDigitByte (byteAt bs n (+ i 1))))
      (underscoreDigits bs n (+ i 1) acc))
    (else none))

fn pyIntText s: String -> (Option Int64)
  (let [t (pv/pyStrip s)
        signed (or (stringStartsWith? t "-") (stringStartsWith? t "+"))
        sign (if (stringStartsWith? t "-") "-" "")
        body (if signed (dropFirst t) t)
        bs (stringToBytes body)
        n (bytesLength bs)]
    (if (= n 0)
      none
      (mt (underscoreDigits bs n 0 (list))
        ((some digits) (stringToInt64 (str sign digits)))
        ((none) none))))

fn truthy v: j/Json -> Bool
  (mt v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint i) (!= i 0))
    ((j/jfloat f) (!= f 0.0))
    ((j/jnum f) (!= f 0.0))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj kvs) (not (listEmpty? kvs))))

fn pyIntOf v: j/Json -> (Option Int64)
  (mt v
    ((j/jint i) (some i))
    ((j/jbool b) (some (if b 1 0)))
    ((j/jstr s) (pyIntText s))
    (_ none))

fn intValue v: j/Json -> (Option Int64)
  (mt v ((j/jint i) (some i)) (_ none))

fn textValue v: j/Json -> String
  (pv/pyStr v)

fn listValue v: j/Json -> (List String)
  (mt v
    ((j/jarr xs) (map (fn [x] (pv/pyStr x)) xs))
    (_ (list)))


fn isDelimByte b: Int64 -> Bool
  (or (= b 40) (= b 41) (= b 91) (= b 93) (= b 34) (= b 59))

fn stringTokenEnd bs: Bytes n: Int64 i: Int64 esc: Bool -> (Option Int64)
  (cond
    ((>= i n) none)
    (esc (stringTokenEnd bs n (+ i 1) false))
    ((= (bytesGet bs i) 92) (stringTokenEnd bs n (+ i 1) true))
    ((= (bytesGet bs i) 34) (some (+ i 1)))
    (else (stringTokenEnd bs n (+ i 1) false)))

fn atomEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (> (spaceWidth bs n i) 0) (isDelimByte (bytesGet bs i))) i (atomEnd bs n (+ i 1)))

fn lineEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (lineEnd bs n (+ i 1)))

fn tokenScan s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (Result (List String) String)
  (if (>= i n)
    (ok (listReverse acc))
    (let [w (spaceWidth bs n i)
          b (bytesGet bs i)]
      (cond
        ((> w 0) (tokenScan s bs n (+ i w) acc))
        ((= b 59) (tokenScan s bs n (lineEnd bs n i) acc))
        ((or (= b 40) (= b 41) (= b 91) (= b 93)) (tokenScan s bs n (+ i 1) (cons (c/sliceOf s i (+ i 1)) acc)))
        ((= b 34)
          (mt (stringTokenEnd bs n (+ i 1) false)
            ((none) (err "Unclosed string in ASN form"))
            ((some e) (tokenScan s bs n e (cons (c/sliceOf s i e) acc)))))
        (else (let [e (atomEnd bs n i)] (tokenScan s bs n e (cons (c/sliceOf s i e) acc)))))))

fn tokenizeAsn text: String -> (Result (List String) String)
  (let [bs (stringToBytes text)]
    (tokenScan text bs (bytesLength bs) 0 (list)))

fn tokenUnescape s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (stringJoin (listReverse (cons (c/sliceOf s start n) acc)) ""))
    ((and (= (bytesGet bs i) 92) (< (+ i 1) n))
      (let [nx (bytesGet bs (+ i 1))
            w (charWidth nx)
            rep (cond ((= nx 110) "\n") ((= nx 116) "\t") ((= nx 114) "\r") (else (c/sliceOf s (+ i 1) (min n (+ i 1 w)))))]
        (tokenUnescape s bs n (+ i 1 w) (+ i 1 w) (cons rep (cons (c/sliceOf s start i) acc)))))
    (else (tokenUnescape s bs n (+ i 1) start acc)))

fn unescapeToken tok: String -> String
  (let [body (c/sliceOf tok 1 (- (stringLength tok) 1))
        bs (stringToBytes body)]
    (tokenUnescape body bs (bytesLength bs) 0 0 (list)))

fn parseItems toks: (List String) closing: String acc: (List j/Json) -> (Pair j/Json (List String))
  (cond
    ((listEmpty? toks) (pair (j/jarr (listReverse acc)) toks))
    ((= (c/firstOf toks) closing) (pair (j/jarr (listReverse acc)) (c/restOf toks)))
    (else (mt (parseValue toks) ((pair v rest) (parseItems rest closing (cons v acc))))))

fn parseValue toks: (List String) -> (Pair j/Json (List String))
  (let [tok (c/firstOf toks)
        rest (c/restOf toks)]
    (cond
      ((or (= tok "(") (= tok "[")) (parseItems rest (if (= tok "(") ")" "]") (list)))
      ((and (stringStartsWith? tok "\"") (stringEndsWith? tok "\"")) (pair (j/jstr (unescapeToken tok)) rest))
      ((= tok "true") (pair (j/jbool true) rest))
      ((= tok "false") (pair (j/jbool false) rest))
      (else (mt (pyIntText tok)
              ((some v) (pair (j/jint v) rest))
              ((none) (pair (j/jstr tok) rest))))))

fn paramGet ps: (List (Pair String j/Json)) key: String -> (Option j/Json)
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) ps))
    ((some p) (some (pairSecond p)))
    ((none) none))

fn paramHas ps: (List (Pair String j/Json)) key: String -> Bool
  (some? (paramGet ps key))

fn paramOr ps: (List (Pair String j/Json)) key: String fallback: j/Json -> j/Json
  (optionOr (paramGet ps key) fallback)

fn paramSet ps: (List (Pair String j/Json)) key: String v: j/Json -> (List (Pair String j/Json))
  (listAppend (filter (fn [p] (!= (pairFirst p) key)) ps) (list (pair key v)))

fn listParam v: j/Json -> j/Json
  (mt v
    ((j/jarr xs) (j/jarr (map (fn [x] (j/jstr (pv/pyStr x))) xs)))
    (_ (j/jarr (if (truthy v) (list (j/jstr (pv/pyStr v))) (list)))))

fn intParam v: j/Json fallback: Int64 -> j/Json
  (j/jint (optionOr (pyIntOf v) fallback))

fn intOrNull v: j/Json -> j/Json
  (mt v ((j/jint i) (j/jint i)) (_ (j/jnull)))

fn strParam v: j/Json -> j/Json
  (j/jstr (pv/pyStr v))

fn applyKey ps: (List (Pair String j/Json)) key: String v: j/Json -> (Pair (List (Pair String j/Json)) (Option String))
  (cond
    ((listContains? (list "task" "root" "backend" "resume" "answer" "model" "contextFile" "base") key)
      (pair (paramSet ps key (strParam v)) none))
    ((= key "mode") (pair (paramSet ps "modeHint" (j/jstr (lstripColons (pv/pyStr v)))) none))
    ((or (= key "intent") (= key "role")) (pair (paramSet ps key (j/jstr (lstripColons (pv/pyStr v)))) none))
    ((or (= key "owns") (= key "gates")) (pair (paramSet ps key (listParam v)) none))
    ((= key "budget") (pair (paramSet ps key (intParam v 3000)) none))
    ((= key "timeout") (pair (paramSet ps key (intParam v 600)) none))
    ((= key "queueTimeout") (pair (paramSet ps key (intParam v 1200)) none))
    ((= key "dryRun")
      (pair (paramSet ps key (j/jbool (mt v ((j/jbool b) b) ((j/jstr s) (= s "true")) (_ false)))) none))
    ((= key "contextTokens")
      (pair (paramSet ps key (mt (pyIntOf v) ((some i) (j/jint i)) ((none) (j/jnull)))) none))
    ((or (= key "gateTimeout") (= key "wallBudget")) (pair (paramSet ps key (intOrNull v)) none))
    ((= key "plan") (pair (paramSet ps key (mt v ((j/jbool b) (j/jbool b)) (_ (j/jnull)))) none))
    ((= key "agent") (pair ps none))
    (else (pair ps (some key))))

fn paramLoop toks: (List String) ps: (List (Pair String j/Json)) unknown: (List String) -> (Pair (List (Pair String j/Json)) (List String))
  (if (or (listEmpty? toks) (= (c/firstOf toks) ")"))
    (pair ps (listReverse unknown))
    (let [t (c/firstOf toks)
          rest (c/restOf toks)]
      (if (not (stringStartsWith? t ":"))
        (paramLoop rest ps unknown)
        (let [key (dropFirst t)
              taken (if (or (listEmpty? rest) (= (c/firstOf rest) ")"))
                      (pair (j/jbool true) rest)
                      (let [nx (c/firstOf rest)]
                        (if (and (stringStartsWith? nx ":") (listContains? (knownParams) (dropFirst nx))
                                 (not (listContains? (keywordValued) key)))
                          (pair (j/jbool true) rest)
                          (parseValue rest))))]
          (mt taken
            ((pair v after)
              (mt (applyKey ps key v)
                ((pair next unk)
                  (paramLoop after next (mt unk ((some k) (cons k unknown)) ((none) unknown)))))))))))

fn ! isDir path: String -> Bool
  (mt (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! isFile path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn pyJoin a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn joinTask task: String content: String -> String
  (cond
    ((stringEmpty? task) content)
    ((stringEndsWith? task "\n\n") (str task content))
    ((stringEndsWith? task "\n") (str task "\n" content))
    (else (str task "\n\n" content)))

fn ! applyContextFile ps: (List (Pair String j/Json)) rootDir: String -> (Pair (List (Pair String j/Json)) (Option (Pair String String)))
  (let [cf (textValue (paramOr ps "contextFile" (j/jstr "")))
        root (if (and (not (stringEmpty? rootDir)) (isDir rootDir)) rootDir (resultOr (realPath ".") "."))
        full (go/pyNormpath (pyJoin root cf))
        rel (go/pyRelpath! (go/pyRealpath! full) (go/pyRealpath! root))]
    (cond
      ((stringEmpty? cf) (pair ps none))
      ((stringStartsWith? rel "..") (pair ps (some (pair "outside_repo" cf))))
      ((not (isFile full)) (pair ps (some (pair "not_found" cf))))
      (else
        (mt (fileReadString full)
          ((err e) (pair ps (some (pair "read_error" e))))
          ((ok content)
            (pair (paramSet ps "task" (j/jstr (joinTask (textValue (paramOr ps "task" (j/jstr ""))) content))) none))))))

fn invocationOf ps: (List (Pair String j/Json)) unknown: (List String) syntax: (Option String) cfErr: (Option (Pair String String)) -> Invocation
  (Invocation :params ps :unknownOps unknown :syntaxError syntax :contextFileError cfErr)

fn ! parseInvocation formText: String rootDir: String -> Invocation
  (if (stringEmpty? (pv/pyStrip formText))
    (invocationOf (list) (list) none none)
    (mt (tokenizeAsn formText)
      ((err e) (invocationOf (list) (list) (some e) none))
      ((ok toks)
        (if (or (listEmpty? toks) (!= (c/firstOf toks) "("))
          (invocationOf (list) (list) (some "invocation must be an ASN parenthesised form") none)
          (let [body (c/restOf toks)
                start (if (and (not (listEmpty? body)) (or (= (c/firstOf body) ":agent") (= (c/firstOf body) "agent")))
                        (c/restOf body)
                        body)]
            (mt (paramLoop start (list) (list))
              ((pair ps unknown)
                (if (paramHas ps "contextFile")
                  (mt (applyContextFile ps rootDir) ((pair ps2 cfErr) (invocationOf ps2 unknown none cfErr)))
                  (invocationOf ps unknown none none)))))))))


fn quotedEnd bs: Bytes n: Int64 i: Int64 -> (Option Int64)
  (cond
    ((>= i n) none)
    ((= (bytesGet bs i) 34) (some (+ i 1)))
    ((= (bytesGet bs i) 92)
      (if (or (>= (+ i 1) n) (= (bytesGet bs (+ i 1)) 10)) none (quotedEnd bs n (+ i 2))))
    (else (quotedEnd bs n (+ i 1))))

fn quotedAt s: String bs: Bytes n: Int64 i: Int64 -> (Option (Pair String Int64))
  (if (!= (byteAt bs n i) 34)
    none
    (mt (quotedEnd bs n (+ i 1))
      ((some e) (some (pair (c/sliceOf s (+ i 1) (- e 1)) e)))
      ((none) none)))

fn gapEnd bs: Bytes n: Int64 i: Int64 anySpace: Bool -> (Option Int64)
  (if anySpace
    (let [e (spacesEnd bs n i)] (if (> e i) (some e) none))
    (if (= (byteAt bs n i) 32) (some (+ i 1)) none))

fn litAt s: String i: Int64 lit: String -> Bool
  (= (optionOr (stringSlice s i (+ i (stringLength lit))) "") lit)

fn searchFrom s: String lit: String start: Int64 matcher: (fn [Int64] -> (Option T)) -> (Option T)
  (mt (stringIndexOf (c/sliceOf s start (stringLength s)) lit)
    ((none) none)
    ((some off)
      (let [p (+ start off)]
        (mt (matcher p)
          ((some v) (some v))
          ((none) (searchFrom s lit (+ p 1) matcher))))))

fn quotedField s: String key: String anySpace: Bool -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (searchFrom s key 0
      (fn [p] (mt (gapEnd bs n (+ p (stringLength key)) anySpace)
                ((none) none)
                ((some q) (mt (quotedAt s bs n q) ((some hit) (some (pairFirst hit))) ((none) none)))))))

fn removeQuotedField s: String key: String anySpace: Bool -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (removeLoop s bs n key anySpace 0 0 (list)))

fn removeLoop s: String bs: Bytes n: Int64 key: String anySpace: Bool from: Int64 kept: Int64 acc: (List String) -> String
  (mt (stringIndexOf (c/sliceOf s from n) key)
    ((none) (stringJoin (listReverse (cons (c/sliceOf s kept n) acc)) ""))
    ((some off)
      (let [p (+ from off)
            hit (mt (gapEnd bs n (+ p (stringLength key)) anySpace)
                  ((none) none)
                  ((some q) (mt (quotedAt s bs n q) ((some h) (some (pairSecond h))) ((none) none))))]
        (mt hit
          ((some e) (removeLoop s bs n key anySpace e e (cons (c/sliceOf s kept p) acc)))
          ((none) (removeLoop s bs n key anySpace (+ p 1) kept acc))))))

fn keywordField s: String key: String -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (searchFrom s key 0
      (fn [p] (mt (gapEnd bs n (+ p (stringLength key)) true)
                ((none) none)
                ((some q)
                  (if (!= (byteAt bs n q) 58)
                    none
                    (let [e (runEnd bs n (+ q 1) isWordByte)]
                      (if (> e (+ q 1)) (some (c/sliceOf s (+ q 1) e)) none))))))))

fn journalModeHint header: String -> (Option String)
  (let [head (removeQuotedField header ":task" true)]
    (mt (quotedField head ":modeHint" true)
      ((some raw) (some (c/asnUnescape raw)))
      ((none)
        (mt (keywordField head ":mode")
          ((some m) (if (= m "auto") none (some m)))
          ((none) none)))))

fn intDigits sign: String digits: String -> String
  (let [bs (stringToBytes digits)
        n (bytesLength bs)
        first (runEnd bs n 0 (fn [b] (= b 48)))
        body (if (= first n) "0" (c/sliceOf digits first n))]
    (if (or (= body "0") (stringEmpty? sign)) body (str sign body)))

fn turnAtStart s: String -> (Option Int64)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (not (litAt s 0 "(:turn"))
      none
      (mt (gapEnd bs n 6 true)
        ((none) none)
        ((some q)
          (let [e (runEnd bs n q isDigitByte)]
            (if (> e q) (stringToInt64 (c/sliceOf s q e)) none))))))

fn noteLine s: String -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (not (litAt s 0 "(:turn"))
      none
      (mt (gapEnd bs n 6 true)
        ((none) none)
        ((some q)
          (let [e (runEnd bs n q isDigitByte)]
            (if (= e q)
              none
              (mt (gapEnd bs n e true)
                ((none) none)
                ((some k)
                  (if (not (litAt s k ":note"))
                    none
                    (mt (gapEnd bs n (+ k 5) true)
                      ((none) none)
                      ((some v)
                        (mt (quotedAt s bs n v)
                          ((some hit) (if (= (+ (pairSecond hit) 1) n) (if (litAt s (pairSecond hit) ")") (some (pairFirst hit)) none) none))
                          ((none) none)))))))))))))

fn gateLine s: String -> (Option (Pair String String))
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (not (litAt s 0 "(:gate"))
      none
      (mt (gapEnd bs n 6 true)
        ((none) none)
        ((some a)
          (if (not (litAt s a ":cmd"))
            none
            (mt (gapEnd bs n (+ a 4) true)
              ((none) none)
              ((some b)
                (mt (quotedAt s bs n b)
                  ((none) none)
                  ((some hit)
                    (mt (gapEnd bs n (pairSecond hit) true)
                      ((none) none)
                      ((some k)
                        (if (not (litAt s k ":exit"))
                          none
                          (mt (gapEnd bs n (+ k 5) true)
                            ((none) none)
                            ((some v)
                              (let [neg (= (byteAt bs n v) 45)
                                    d0 (if neg (+ v 1) v)
                                    e (runEnd bs n d0 isDigitByte)]
                                (if (= e d0)
                                  none
                                  (some (pair (pairFirst hit) (intDigits (if neg "-" "") (c/sliceOf s d0 e))))))))))))))))))))

fn statusField s: String -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (searchFrom s ":status" 0
      (fn [p] (mt (gapEnd bs n (+ p 7) true)
                ((none) none)
                ((some q)
                  (if (!= (byteAt bs n q) 58)
                    none
                    (let [e (runEnd bs n (+ q 1) isAlphaByte)]
                      (if (> e (+ q 1)) (some (c/sliceOf s (+ q 1) e)) none))))))))


fn sessionChar b: Int64 -> Bool
  (or (isAlphaByte b) (isDigitByte b) (= b 46) (= b 95) (= b 45))

fn sessionOk session: String -> Bool
  (let [body (if (stringEndsWith? session "\n") (c/sliceOf session 0 (- (stringLength session) 1)) session)
        bs (stringToBytes body)
        n (bytesLength bs)]
    (and (> n 0)
         (or (isAlphaByte (bytesGet bs 0)) (isDigitByte (bytesGet bs 0)))
         (= (runEnd bs n 0 sessionChar) n)
         (not (stringContains? session ".."))))

fn noJournal session: String exit: Int64 -> MainResult
  (MainResult :stdout (str "(:agentReceipt :status :rejected :error ERR_NO_JOURNAL :session \"" (c/escapeAsn session)
                           "\" :message \"no journal at .asl/run/agentLoop/" (c/escapeAsn session) ".journal\")")
              :exitCode exit)

fn journalPathOf rootDir: String session: String -> String
  (pyJoin (pyJoin rootDir ".asl/run/agentLoop") (str session ".journal"))

(schema ReportState
  (:f task String)
  (:f hint (Option String))
  (:f lastTurn Int64)
  (:f note (Option String))
  (:f gates (List (Pair String String)))
  (:f prevGate Bool)
  (:f result (Option String)))

fn reportLine st: ReportState line: String -> ReportState
  (let [s (pv/pyStrip line)]
    (cond
      ((stringStartsWith? s "(:session ")
        (with st :task (optionOr (quotedField s ":task" true) st.task) :hint (journalModeHint s) :prevGate false))
      ((stringStartsWith? s "(:turn ")
        (with st :lastTurn (mt (turnAtStart s) ((some t) (max t st.lastTurn)) ((none) st.lastTurn)) :note (mt (noteLine s) ((some raw) (some raw)) ((none) st.note)) :prevGate false))
      ((stringStartsWith? s "(:gate ")
        (mt (gateLine s)
          ((none) st)
          ((some g)
            (with st :gates (listAppend (if st.prevGate st.gates (list)) (list g)) :prevGate true))))
      ((stringStartsWith? s "(:result ")
        (with st :prevGate false :result (some (optionOr (statusField s) "unknown"))))
      (else st)))

fn ! stagedUnder dir: String rel: String -> (List String)
  (mt (dirList dir)
    ((err _) (list))
    ((ok names)
      (let [kinds (map (fn [name]
                         (let [path (pyJoin dir name)
                               isLink (mt (fileLstat path) ((ok ls) ls.isSymlink) ((err _) false))
                               dirLike (isDir path)]
                           (pair name (if dirLike (if isLink "skip" "dir") "file"))))
                       names)
            files (map (fn [k] (pyJoin rel (pairFirst k))) (filter (fn [k] (= (pairSecond k) "file")) kinds))
            dirs (filter (fn [k] (= (pairSecond k) "dir")) kinds)]
        (fold (fn [acc k] (listAppend acc (stagedUnder (pyJoin dir (pairFirst k)) (pyJoin rel (pairFirst k)))))
              files dirs))))

fn quoteEach xs: (List String) -> String
  (stringJoin (map (fn [x] (str "\"" (c/escapeAsn x) "\"")) xs) " ")

fn ! resumeReport session: String rootDir: String -> MainResult
  (let [path (journalPathOf rootDir session)]
    (if (or (not (sessionOk session)) (not (isFile path)))
      (noJournal session 1)
      (mt (fileReadString path)
        ((err e)
          (MainResult :stdout (str "(:agentReceipt :status :rejected :error ERR_JOURNAL_READ :session \"" (c/escapeAsn session)
                                   "\" :message \"" (c/escapeAsn e) "\")")
                      :exitCode 1))
        ((ok text)
          (let [st (fold reportLine
                         (ReportState :task "" :hint none :lastTurn 0 :note none :gates (list) :prevGate false :result none)
                         (go/pySplitLines (pv/universalNewlines text) false))
                status (mt st.result ((none) "resumable") ((some r) (if (= r "ok") "done" "escalated")))
                stageDir (pyJoin (pyJoin rootDir ".asl/vfs") session)
                staged (if (isDir stageDir) (stagedUnder stageDir "") (list))
                shown (listTake staged 20)]
            (MainResult
              :stdout (str "(:agentReceipt :status :" status " :session \"" (c/escapeAsn session) "\""
                           " :task \"" st.task "\""
                           (mt st.hint ((some h) (if (stringEmpty? h) "" (str " :modeHint \"" (c/escapeAsn h) "\""))) ((none) ""))
                           " :lastTurn " (stringFromInt64 st.lastTurn)
                           (mt st.note ((some raw) (str " :note \"" raw "\"")) ((none) ""))
                           " :lastGates (" (stringJoin (map (fn [g] (str "(:cmd \"" (pairFirst g) "\" :exit " (pairSecond g) ")")) st.gates) " ") ")"
                           " :result " (mt st.result ((some r) (str ":" r)) ((none) "none"))
                           " :staged " (stringFromInt64 (listLength staged))
                           " :stagedPaths (" (quoteEach shown) ")"
                           " :more " (stringFromInt64 (- (listLength staged) (listLength shown))) ")")
              :exitCode 0))))))


(schema TurnSlot
  (:f turn Int64)
  (:f sent (Option String))
  (:f got (Option String)))

(schema ResumeScan
  (:f header (Option ResumeState))
  (:f malformed (Option String))
  (:f slots (List TurnSlot))
  (:f note String)
  (:f result (Option String))
  (:f text String))

fn turnEntry s: String -> (Option (Pair Int64 (Pair String String)))
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (not (litAt s 0 "(:turn "))
      none
      (let [e (runEnd bs n 7 isDigitByte)]
        (if (or (= e 7) (not (litAt s e " :")))
          none
          (let [kindEnd (runEnd bs n (+ e 2) isAlphaByte)
                kind (c/sliceOf s (+ e 2) kindEnd)]
            (if (or (not (listContains? (list "reply" "observation" "retryBrief" "answer" "note") kind)) (not (litAt s kindEnd " ")))
              none
              (mt (quotedAt s bs n (+ kindEnd 1))
                ((none) none)
                ((some hit)
                  (if (and (= (+ (pairSecond hit) 1) n) (litAt s (pairSecond hit) ")"))
                    (mt (stringToInt64 (c/sliceOf s 7 e))
                      ((some t) (some (pair t (pair kind (pairFirst hit)))))
                      ((none) none))
                    none)))))))))

fn listStrings s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (Option (List String))
  (let [k (spacesEnd bs n i)]
    (mt (quotedAt s bs n k)
      ((some hit) (listStrings s bs n (pairSecond hit) (cons (pairFirst hit) acc)))
      ((none) (if (= (byteAt bs n k) 41) (some (listReverse acc)) none))))

fn listField s: String key: String -> (List String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        lit (str key " (")]
    (map c/asnUnescape
      (optionOr (searchFrom s lit 0 (fn [p] (listStrings s bs n (+ p (stringLength lit)) (list)))) (list))))

fn contextTokensField s: String -> (Option Int64)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (searchFrom s ":contextTokens " 0
      (fn [p] (let [q (+ p 15) e (runEnd bs n q isDigitByte)]
                (if (> e q) (stringToInt64 (c/sliceOf s q e)) none)))))

fn headerOf session: String journal: String line: String text: String -> (Result ResumeState String)
  (mt (quotedField line ":task" false)
    ((none) (err "the session header has no :task string"))
    ((some rawTask)
      (let [intent (quotedField (removeQuotedField line ":task" false) ":intent" false)]
        (ok (ResumeState :session session :journal journal :task (c/asnUnescape rawTask) :modeHint (journalModeHint line)
                         :intent (mt intent ((some raw) (if (= raw "auto") none (some (c/asnUnescape raw)))) ((none) none))
                         :owns (listField line ":owns") :gates (listField line ":gates")
                         :base (mt (quotedField line ":base" false) ((some raw) (c/asnUnescape raw)) ((none) ""))
                         :contextTokens (contextTokensField line) :note "" :result none :history (list) :turn 0 :reply ""
                         :plan (if (stringEndsWith? line " :plan true)") (some (pl/planReplay text)) none))))))

fn slotPut slots: (List TurnSlot) turn: Int64 kind: String text: String -> (List TurnSlot)
  (let [old (optionOr (listHead (filter (fn [t] (= t.turn turn)) slots)) (TurnSlot :turn turn :sent none :got none))
        slot (cond
               ((= kind "note") old)
               ((= kind "reply") (TurnSlot :turn turn :sent (some text) :got old.got))
               (else (TurnSlot :turn turn :sent old.sent :got (some text))))]
    (listAppend (filter (fn [t] (!= t.turn turn)) slots) (list slot)))

fn scanLine session: String journal: String sc: ResumeScan line: String -> ResumeScan
  (if (some? sc.malformed)
    sc
    (let [withHeader (if (and (stringStartsWith? line "(:session ") (none? sc.header))
                       (mt (headerOf session journal line sc.text)
                         ((ok h) (with sc :header (some h) :malformed none))
                         ((err e) (with sc :header none :malformed (some e))))
                       sc)
          withTurn (mt (turnEntry line)
                     ((none) withHeader)
                     ((some entry)
                       (let [turn (pairFirst entry)
                             kind (pairFirst (pairSecond entry))
                             text (c/asnUnescape (pairSecond (pairSecond entry)))]
                         (ResumeScan :header withHeader.header :malformed withHeader.malformed
                                     :slots (slotPut withHeader.slots turn kind text)
                                     :note (if (= kind "note") (str "(:note \"" (c/escapeAsn text) "\")") withHeader.note)
                                     :result withHeader.result :text text))))]
      (if (stringStartsWith? line "(:result ")
        (mt (keywordField line ":status")
          ((some r) (ResumeScan :header withTurn.header :malformed withTurn.malformed :slots withTurn.slots
                                :note withTurn.note :result (some r) :text withTurn.text))
          ((none) (ResumeScan :header withTurn.header :malformed (some "a result line has no :status keyword") :slots withTurn.slots
                              :note withTurn.note :result withTurn.result :text withTurn.text)))
        withTurn)))

fn resumeError session: String message: String -> String
  (str "(:agentReceipt :status :rejected :error ERR_RESUME :session \"" (c/escapeAsn session) "\" :message \"" message "\")")

fn ! journalResume session: String rootDir: String -> (Result ResumeState String)
  (let [path (journalPathOf rootDir session)]
    (if (or (not (sessionOk session)) (not (isFile path)))
      (err (noJournal session 2).stdout)
      (mt (fileReadString path)
        ((err e) (err (str "(:agentReceipt :status :rejected :error ERR_JOURNAL_READ :session \"" (c/escapeAsn session) "\" :message \"" (c/escapeAsn e) "\")")))
        ((ok raw)
          (let [text (pv/universalNewlines raw)
                sc (fold (fn [acc line] (scanLine session path acc line))
                         (ResumeScan :header none :malformed none :slots (list) :note "" :result none :text text)
                         (go/pySplitLines text false))
                replied (listSortBy (fn [t] t.turn) (filter (fn [t] (some? t.sent)) sc.slots))]
            (mt sc.malformed
              ((some m) (err (str "(:agentReceipt :status :rejected :error ERR_JOURNAL_READ :session \"" (c/escapeAsn session) "\" :message \"" (c/escapeAsn m) "\")")))
              ((none)
                (mt sc.header
                  ((none) (err (resumeError session "the journal holds no session header or no turn")))
                  ((some h)
                    (cond
                      ((listEmpty? replied) (err (resumeError session "the journal holds no session header or no turn")))
                      ((= sc.result (some "ok")) (err (resumeError session "the session ended :ok")))
                      (else
                        (let [last (optionOr (listLast replied) (c/firstOf replied))
                              older (listTake replied (- (listLength replied) 1))]
                          (ok (ResumeState :session session :journal path :task h.task :modeHint h.modeHint :intent h.intent
                                           :owns h.owns :gates h.gates :base h.base :contextTokens h.contextTokens
                                           :note sc.note :result sc.result
                                           :history (map (fn [t] (ResumeTurn :turn t.turn :sent (optionOr t.sent "") :got (optionOr t.got ""))) older)
                                           :turn last.turn :reply (optionOr last.sent "") :plan h.plan))))))))))))))


fn unbackedList texts: (List String) -> String
  (if (listEmpty? texts) "" (str " :unbackedClaims (" (quoteEach texts) ")"))

fn nonEmpty o: (Option String) -> (Option String)
  (mt o ((some s) (if (stringEmpty? s) none (some s))) ((none) none))

fn gateCmd g: j/Json -> String
  (mt (j/jsonGet g "cmd") ((some v) (pv/pyStr v)) ((none) ""))

fn keptFindings xs: (List String) -> (List String)
  (filter (fn [f] (not (stringEmpty? f))) (map pv/pyStrip xs))

fn formatReceipt r: LoopResult -> String
  (str "(:agentReceipt :status :" r.status
       (mt (nonEmpty r.modeHint) ((some m) (str " :modeHint \"" (c/escapeAsn m) "\"")) ((none) ""))
       (mt (nonEmpty r.deliver) ((some d) (str " :deliver :" d)) ((none) ""))
       " :phases (" (stringJoin r.phases " ") ")"
       (mt (nonEmpty r.session) ((some s) (str " :session \"" s "\"")) ((none) ""))
       (mt (nonEmpty r.journal) ((some p) (str " :journal \"" p "\"")) ((none) ""))
       " :unbacked " (stringFromInt64 r.unbacked) (unbackedList r.unbackedClaims)
       (mt r.contextTokens ((some t) (if (= t 0) "" (str " :contextTokens " (stringFromInt64 t)))) ((none) ""))
       (mt r.turns ((some t) (str " :turns " (stringFromInt64 t))) ((none) ""))
       (if (listEmpty? r.gates)
         ""
         (str " :gates (" (stringJoin (map (fn [g] (str "(:cmd \"" (c/escapeAsn (gateCmd g)) "\" " (ctx/gateOutcome g) ")")) r.gates) " ") ")"))
       (mt (nonEmpty r.escalate) ((some e) (str " :escalate (" e ")")) ((none) ""))
       (jr/handBackFields (nonEmpty r.patch) r.restored) (jr/writtenField r.written)
       (if (listEmpty? r.needsConfirm)
         ""
         (let [items (stringJoin (map (fn [x] (if (stringEmpty? x.error)
                                                (str "(:op \"" x.op "\" :blocked true)")
                                                (str "(:op \"" x.op "\" :error " x.error ")")))
                                      r.needsConfirm)
                                 " ")]
           (str " :needsConfirm (" items ")")))
       (if (listEmpty? r.ownsRejected)
         ""
         (str " :ownsRejected ("
              (stringJoin (map (fn [o] (str "(:turn " (stringFromInt64 o.turn) " :op \"" (c/escapeAsn o.op)
                                            "\" :file \"" (c/escapeAsn o.file) "\" :error ERR_OWNS)"))
                               r.ownsRejected)
                          " ")
              ")"))
       (mt (nonEmpty r.error) ((some e) (str " :error " e)) ((none) ""))
       (if (listEmpty? r.gatePreflight) "" (str " :gatePreflight (" (go/formatGatePreflight r.gatePreflight) ")"))
       (if r.parseDefect
         (str " :turn " (stringFromInt64 (mt r.parseDefectTurn ((some t) (if (= t 0) 1 t)) ((none) 1))) " :parse-defect true")
         "")
       (mt r.findings ((some fs) (str " :findings (" (stringJoin (keptFindings fs) " ") ")")) ((none) ""))
       (mt r.queueWaitSec ((some q) (str " :queueWaitSec " (stringFromFloat64 q))) ((none) ""))
       (mt r.execSec ((some e) (str " :execSec " (stringFromFloat64 e))) ((none) ""))
       (mt r.usage
         ((some u) (str " :usage (:input " (stringFromInt64 u.input) " :cached " (stringFromInt64 u.cached)
                        " :output " (stringFromInt64 u.output) ")"))
         ((none) ""))
       (mt r.batching
         ((some b)
           (let [rates (rt/batchingRates b.turns b.ops b.single)]
             (str " :batching (:opsPerTurn " (stringFromFloat64 (pairFirst rates)) " :singleOpShare " (stringFromFloat64 (pairSecond rates))
                  " :opTurns " (stringFromInt64 b.turns) ")")))
         ((none) ""))
       (mt r.plan ((some p) (pl/planField p)) ((none) ""))
       ")")


fn blockEnd source: String from: Int64 -> Int64
  (let [tail (c/sliceOf source from (stringLength source))
        ends (map (fn [o] (optionOr o 0)) (filter (fn [o] (some? o)) (map (fn [m] (stringIndexOf tail m)) (list "\nfn " "\n(schema " "\nenum "))))]
    (mt (listMin ends)
      ((some e) (+ from e))
      ((none) (stringLength source))))

fn fnBody source: String name: String -> (Option String)
  (let [src (str "\n" source)]
    (mt (stringIndexOf src (str "\nfn " name " "))
      ((none) none)
      ((some at) (some (c/sliceOf src (+ at 1) (blockEnd src (+ at 1)))))))

fn literalsIn s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse acc))
    ((= (bytesGet bs i) 59) (literalsIn s bs n (lineEnd bs n i) acc))
    ((= (bytesGet bs i) 34)
      (mt (stringTokenEnd bs n (+ i 1) false)
        ((some e) (literalsIn s bs n e (cons (c/sliceOf s (+ i 1) (- e 1)) acc)))
        ((none) (listReverse acc))))
    (else (literalsIn s bs n (+ i 1) acc)))

fn keyByte b: Int64 -> Bool
  (or (isWordByte b) (= b 45))

fn keysIn s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse acc))
    ((and (= (bytesGet bs i) 58) (isAlphaByte (byteAt bs n (+ i 1))))
      (let [e (runEnd bs n (+ i 1) keyByte)]
        (keysIn s bs n e (cons (c/sliceOf s (+ i 1) e) acc))))
    (else (keysIn s bs n (+ i 1) acc)))

fn keysOf s: String -> (List String)
  (let [bs (stringToBytes s)] (keysIn s bs (bytesLength bs) 0 (list)))

fn dedupe xs: (List String) acc: (List String) -> (List String)
  (cond
    ((listEmpty? xs) (listReverse acc))
    ((listContains? acc (c/firstOf xs)) (dedupe (c/restOf xs) acc))
    (else (dedupe (c/restOf xs) (cons (c/firstOf xs) acc))))

fn afterHead keys: (List String) -> (Option (List String))
  (cond
    ((listEmpty? keys) none)
    ((= (c/firstOf keys) "agentReceipt") (some (c/restOf keys)))
    (else (afterHead (c/restOf keys))))

fn receiptFieldsIn source: String -> (Result (List String) String)
  (mt (fnBody source "formatReceipt")
    ((none) (err "asl/agentLoop/main.asl has no fn formatReceipt"))
    ((some body)
      (let [bs (stringToBytes body)
            keys (fold (fn [acc lit] (listAppend acc (keysOf lit))) (list) (literalsIn body bs (bytesLength bs) 0 (list)))]
        (mt (afterHead keys)
          ((none) (err "formatReceipt writes no (:agentReceipt form"))
          ((some fields) (ok (dedupe (filter (fn [k] (not (listContains? (list "cmd" "exit" "op" "blocked") k))) fields) (list))))))))

fn ! receiptFieldNames rootDir: String -> (Result (List String) String)
  (mt (fileReadString (pyJoin rootDir "asl/agentLoop/main.asl"))
    ((err e) (err e))
    ((ok source) (receiptFieldsIn source)))


fn infoText info: j/Json key: String -> String
  (mt (j/jsonGet info key) ((some v) (pv/pyStr v)) ((none) ""))

fn infoItems v: (Option j/Json) -> (List j/Json)
  (mt v ((some x) (mt x ((j/jarr xs) xs) (_ (list)))) ((none) (list)))

fn infoFlag info: j/Json key: String -> String
  (mt (j/jsonGet info key)
    ((some v) (if (truthy v) (str " :" key " \"" (pv/pyStr v) "\"") ""))
    ((none) ""))

fn formatDryRun info: j/Json systemPrompt: String owns: (List String) -> String
  (str "(:dryRunReceipt :vendor \"" (infoText info "vendor") "\" :owns (" (quoteEach owns) ")"
       " :cwd \"" (infoText info "cwd") "\""
       (mt (j/jsonGet info "request")
         ((some req)
           (str " :request (:url \"" (infoText req "url") "\" :model \"" (infoText req "model") "\" :agent \"" (infoText req "agent") "\""
                " :addDirs (" (stringJoin (map (fn [d] (str "\"" (pv/pyStr d) "\"")) (infoItems (j/jsonGet req "addDirs"))) " ") ")"
                " :workspace \"" (infoText req "workspace") "\" :timeout " (infoText req "timeout")
                " :queue_timeout " (infoText req "queue_timeout") ")"
                " :note \"gateway replaces --agent aslLoop --print-timeout --output-format json\""))
         ((none)
           (mt (j/jsonGet info "argv")
             ((some a) (if (truthy a) (str " :argv \"" (c/escapeAsn (stringJoin (map pv/pyStr (infoItems (some a))) " ")) "\"") ""))
             ((none) ""))))
       (infoFlag info "agentFile") (infoFlag info "agentFrontmatter") (infoFlag info "modelInstructionsFile")
       (mt (j/jsonGet info "stdinRedirected") ((some v) (if (truthy v) " :stdinRedirected true" "")) ((none) ""))
       " :systemPrompt \"" (c/escapeAsn systemPrompt) "\")")


fn rejectWith fields: String exit: Int64 -> MainResult
  (MainResult :stdout (str "(:agentReceipt :status :rejected " fields ")") :exitCode exit)

fn unknownArg! uop: String -> MainResult
  (rejectWith (str ":error ERR_UNKNOWN_ARG :key \"" uop "\" :nearest \"" (nearestKey! uop) "\""
                   " :accepted (" (stringJoin (map (fn [k] (str "\"" k "\"")) (acceptedKeys)) " ") ")"
                   " :message \"" (c/escapeAsn (str "unknown argument '" uop "' is not a recognised parameter (not an op; see ERR_EFFECT_UNDECLARED for ops inside the loop)")) "\"")
              2)

fn contextFileRejection kind: String path: String -> MainResult
  (let [message (cond
                  ((= kind "outside_repo") (str "contextFile outside repository: " path))
                  ((= kind "not_found") (str "contextFile not found: " path))
                  (else (str "contextFile could not be read: " path)))]
    (rejectWith (str ":error ERR_CONTEXT_FILE :path \"" (c/escapeAsn path) "\" :message \"" (c/escapeAsn message) "\"") 2))

fn inRange o: (Option Int64) lo: Int64 hi: Int64 -> Bool
  (mt o ((some v) (and (>= v lo) (<= v hi))) ((none) false))

fn rstripSlash s: String -> String
  (if (and (stringEndsWith? s "/") (> (stringLength s) 0)) (rstripSlash (c/sliceOf s 0 (- (stringLength s) 1))) s)

fn ! expandUser p: String -> String
  (if (not (stringStartsWith? p "~"))
    p
    (let [cut (mt (stringIndexOf (c/sliceOf p 1 (stringLength p)) "/") ((some off) (+ off 1)) ((none) (stringLength p)))]
      (if (!= cut 1)
        p
        (mt (envGet "HOME")
          ((some home) (let [r (str (rstripSlash home) (c/sliceOf p cut (stringLength p)))] (if (stringEmpty? r) "/" r)))
          ((none) p)))))

fn supportedBackends -> (List String)
  (list "agy" "codex" "claude")

fn defaultModel backend: String -> String
  (if (= backend "agy") "gemini-3.8-flash" backend)

fn optText v: (Option j/Json) -> (Option String)
  (mt v ((some x) (some (textValue x))) ((none) none))

fn modeOf hint: (Option String) -> (Option String)
  (mt hint ((some m) (if (or (= m "auto") (= m "")) none (some m))) ((none) none))

fn hexByte b: Int64 -> String
  (str (c/sliceOf "0123456789abcdef" (/ b 16) (+ (/ b 16) 1)) (c/sliceOf "0123456789abcdef" (mod b 16) (+ (mod b 16) 1)))

fn ! newSessionId -> (Result String String)
  (mt (fileReadRange "/dev/urandom" 0 8)
    ((err e) (err e))
    ((ok bs)
      (if (= (bytesLength bs) 8)
        (ok (stringJoin (map (fn [i] (hexByte (bytesGet bs i))) (list 0 1 2 3 4 5 6 7)) ""))
        (err "/dev/urandom gave fewer than 8 bytes"))))

fn liveOpName op: (List (Pair String c/KvVal)) -> String
  (mt (c/dictGet op "op")
    ((some value) (mt value ((c/kvStr name) name) (_ "")))
    ((none) ""))

fn liveOpPath op: (List (Pair String c/KvVal)) -> String
  (mt (c/dictGet op "file")
    ((some value) (mt value ((c/kvStr path) path) (_ "")))
    ((none) (mt (c/dictGet op "path") ((some value) (mt value ((c/kvStr path) path) (_ ""))) ((none) ""))))

fn liveConfirmReceipt out: ex/ExecOut -> (Option j/Json)
  (let [rec out.rec]
    (mt (ex/recGet rec "needsConfirm")
      ((some value) (mt value ((ex/vBool requested) (if requested (some (ls/execRecJson rec)) none)) (_ none)))
      ((none) none)))

fn liveConfirmStr row: j/Json key: String fallback: String -> String
  (mt (j/jsonGet row key) ((some v) (mt v ((j/jstr s) s) (_ fallback))) ((none) fallback))

fn liveConfirmItems value: (Option j/Json) -> (List NeedsConfirm)
  (mt value
    ((some raw) (mt raw
      ((j/jarr items) (map (fn [item] (NeedsConfirm :op (liveConfirmStr item "op" "unknown") :error (liveConfirmStr item "error" ""))) items))
      (_ (list))))
    ((none) (list)))

fn ! liveAdvisor provider: pv/Provider sys: String msg: String -> (Result (Option String) String)
  (mt (pv/advise! provider sys msg)
    ((none) (err "provider has no advisor channel"))
    ((some turn)
      (mt turn.reply
        ((err e) (err (pv/errorMessage e)))
        ((ok reply) (ok reply)))))

fn ! liveReviewer provider: pv/Provider sys: String msg: String -> (Result (Option String) String)
  (let [turn (pv/review! provider sys msg)]
    (mt turn.reply
      ((err e) (err (pv/errorMessage e)))
        ((ok reply) (ok reply))))

fn liveReviewerAvailable? provider: pv/Provider -> Bool
  (mt provider
    ((pv/vendorProvider _) true)
    ((pv/scriptFixtureProvider _ fixture _) (some? fixture.reviewer))
    (_ false))

fn liveHookOk? result: (Result (Option String) String) -> Bool
  (mt result ((err _) false) ((ok _) true))

fn liveReviewAccepts? result: (Result (Option String) String) -> Bool
  (mt result
    ((err _) false)
    ((ok reply)
      (mt reply
        ((none) false)
        ((some text)
          (mt (ctx/parseSpecVerdict (some text))
            ((some verdict) (pairFirst verdict))
            ((none) false))))))

fn ! appendLiveHook! path: String turn: Int64 name: String result: (Result (Option String) String) -> Bool
  (mt result
    ((err e) (ok? (fileAppend path (str "(:liveHook :turn " (stringFromInt64 turn) " :name \"" name
      "\" :error \"" (c/escapeAsn e) "\")\n"))))
    ((ok text)
      (mt text
        ((some value) (ok? (fileAppend path (str "(:liveHook :turn " (stringFromInt64 turn) " :name \"" name
          "\" :text \"" (c/escapeAsn value) "\")\n"))))
        ((none) (ok? (fileAppend path (str "(:liveHook :turn " (stringFromInt64 turn) " :name \"" name "\" :text \"\")\n")))))))

fn ! liveHooks! provider: pv/Provider -> (Pair (fn [String String] -> (Result (Option String) String)) (fn [String String] -> (Result (Option String) String)))
  (pair (fn [sys msg] (liveAdvisor provider sys msg))
        (fn [sys msg] (liveReviewer provider sys msg)))

fn liveOwnsItems items: (List j/Json) -> (List OwnsRejection)
  (map (fn [item]
    (OwnsRejection :turn (optionOr (intValue (optionOr (j/jsonGet item "turn") (j/jint 0))) 0)
      :op (liveConfirmStr item "op" "unknown") :file (liveConfirmStr item "file" ""))) items)

fn liveUsage value: (Option j/Json) -> (Option Usage)
  (mt value
    ((some raw)
      (some (Usage
        :input (optionOr (intValue (optionOr (j/jsonGet raw "inputTokens") (j/jint 0))) 0)
        :cached (optionOr (intValue (optionOr (j/jsonGet raw "cachedTokens") (j/jint 0))) 0)
        :output (optionOr (intValue (optionOr (j/jsonGet raw "outputTokens") (j/jint 0))) 0))))
    ((none) none))

fn providerUsageInt fields: (List (Pair String j/Json)) key: String -> Int64
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) fields))
    ((some p) (optionOr (intValue (pairSecond p)) 0))
    ((none) 0))

fn providerUsageLine meta: pv/TurnMeta -> (Option String)
  (mt meta.usage
    ((some fields) (some (str "(:liveUsage :input " (stringFromInt64 (providerUsageInt fields "inputTokens"))
      " :cached " (stringFromInt64 (providerUsageInt fields "cachedTokens"))
      " :output " (stringFromInt64 (providerUsageInt fields "outputTokens")) ")")))
    ((none) none))

fn liveUsageInt line: String key: String -> Int64
  (mt (listHead (filter (fn [field] (= (pairFirst field) key)) (c/parseKv line)))
    ((some field) (mt (pairSecond field)
      ((c/kvInt digits) (optionOr (stringToInt64 digits) 0))
      ((c/kvStr _) 0)))
    ((none) 0))

fn ! liveJournalUsage! rootDir: String journal: (Option String) -> (Option Usage)
  (mt journal
    ((some journalPath)
      (let [path (pyJoin rootDir journalPath)]
      (mt (fileReadString path)
        ((err _) none)
        ((ok text)
          (let [lines (filter (fn [line] (stringStartsWith? line "(:liveUsage ")) (stringSplit text "\n"))]
            (mt (listLast lines)
              ((some line)
                (some (Usage
                  :input (liveUsageInt line "input")
                  :cached (liveUsageInt line "cached")
                  :output (liveUsageInt line "output"))))
              ((none) none)))))))
    ((none) none))

fn livePlan value: (Option j/Json) -> (Option pl/PlanSummary)
  (mt value
    ((some raw)
      (some (pl/summaryOf
        (optionOr (intValue (optionOr (j/jsonGet raw "steps") (j/jint 0))) 0)
        (optionOr (intValue (optionOr (j/jsonGet raw "done") (j/jint 0))) 0)
        (optionOr (intValue (optionOr (j/jsonGet raw "dropped") (j/jint 0))) 0)
        (optionOr (intValue (optionOr (j/jsonGet raw "revisions") (j/jint 0))) 0))))
    ((none) none))

fn livePlanJson forms: (List String) -> (Option j/Json)
  (mt (listHead (filter (fn [form] (stringStartsWith? (stringTrim form) "(:plan")) forms))
    ((some form)
      (let [summary (pl/planSummary (pl/parsePlanState form))]
        (some (j/jobj (list
          (pair "steps" (j/jint (pl/summarySteps summary)))
          (pair "done" (j/jint (pl/summaryDone summary)))
          (pair "dropped" (j/jint (pl/summaryDropped summary)))
          (pair "revisions" (j/jint (pl/summaryRevisions summary))))))))
    ((none) none))

fn ! appendRetryLines! path: String turn: Int64 retries: Int64 -> Bool
  (if (<= retries 0)
    true
    (do
      (fileAppend path (str "(:retry :turn " (stringFromInt64 turn) " :attempt " (stringFromInt64 retries) ")\n"))
      (appendRetryLines! path turn (- retries 1))))

fn ! liveProviderRetry! provider: pv/Provider call: (fn [pv/Provider Int64] -> pv/Turn) wallBudget: (Option Int64) sleep: (fn [Int64] -> Bool) -> (Pair pv/Turn Int64)
  (rt/retryTurn! provider call 3 (list 1 2 4) wallBudget sleep)

fn liveWriteStatus out: ex/ExecOut -> Bool
  (mt (ex/recGet out.rec "status")
    ((some value) (mt value ((ex/vStr status) (= status "ok")) (_ false)))
    ((none) false))

fn liveUnwritten written: jr/Written target: String -> jr/Written
  (jr/Written :root written.root
    :files (mt written.files
      ((some files) (some (filter (fn [entry] (!= (pairFirst entry) target)) files)))
      ((none) none))
    :startHead written.startHead)

fn liveOwnsRejected? out: ex/ExecOut -> Bool
  (mt (ex/recGet out.rec "error")
    ((some value) (mt value ((ex/vStr code) (= code "ERR_OWNS")) (_ false)))
    ((none) false))

fn ! liveOwnsField! rootDir: String journal: (Option String) -> String
  (mt journal
    ((some journalPath)
      (let [path (pyJoin rootDir journalPath)]
      (mt (fileReadString path)
        ((err _) "")
        ((ok text)
          (let [rows (filter (fn [line] (stringStartsWith? line "(:liveOwnsRejected ")) (stringSplit text "\n"))
                forms (map (fn [line]
                  (let [start (optionOr (stringIndexOf line "(:turn") 0)]
                    (c/sliceOf line start (- (stringLength line) 1)))) rows)]
            (if (listEmpty? forms) "" (str " :ownsRejected (" (stringJoin forms " ") ")")))))))
    ((none) ""))

fn ! liveExecOps! ops: (List (List (Pair String c/KvVal))) ra: RunArgs rootDir: String repoRoot: String sid: String journal: String env: ex/ExecEnv run: rl/LoopRun -> (Pair rl/LoopRun (Pair String Bool))
  (if (listEmpty? ops)
    (pair run (pair "" false))
    (let [op (c/firstOf ops)
          opName (liveOpName op)
          target (liveOpPath op)
          mutating (listContains? (list "write" "edit" "delete") opName)
          owned (and mutating (and (not (stringEmpty? target)) (c/checkOwns target ra.owns rootDir)))
          before (if owned (jr/snapshotBeforeWrite run.written target) (ok run.written))
          runOp (fn [form root] (let [r (ao/runAsl repoRoot form root ra.timeout none "subprocess")]
                                  (tx/aslRun (ao/runExit r) (ao/runStdout r) (ao/runStderr r))))
          out (mt before
            ((err e) (ex/ExecOut :rec (list (pair "id" (ex/vStr sid)) (pair "op" (ex/vStr opName))
                (pair "status" (ex/vStr "rejected")) (pair "error" (ex/vStr "ERR_JOURNAL"))
                (pair "message" (ex/vStr e))) :procs run.procs))
            ((ok written)
              (ex/execOp! op env run.procs (fn [] (resultOr (newSessionId) sid))
                (fn [path] (listContains? (rl/writtenPaths written) path))
                (fn [path patch mode] (listContains? (rl/writtenPaths written) path)) runOp)))
          receipt (ex/formatOpReceipt out.rec env.readCap)
          _ownsLogged (if (liveOwnsRejected? out)
            (ok? (fileAppend journal (str "(:liveOwnsRejected (:turn " (stringFromInt64 run.state.turn)
              " :op \"" (c/escapeAsn opName) "\" :file \"" (c/escapeAsn target) "\" :error ERR_OWNS))\n")))
            true)
          wrote (and owned (and (listContains? (list "write" "edit") opName) (liveWriteStatus out)))
          snapWritten (mt before
            ((err _) run.written)
            ((ok written)
              (if (and (and owned (listContains? (list "write" "edit") opName))
                       (and (not (liveWriteStatus out))
                            (not (listContains? (rl/writtenPaths run.written) target))))
                (liveUnwritten written target)
                written)))
          snapRun (rl/withWritten run snapWritten)
          nextRun (rl/withProcs snapRun out.procs)
          rejection (if (liveOwnsRejected? out)
            (some (j/jobj (list (pair "turn" (j/jint run.state.turn))
              (pair "op" (j/jstr opName)) (pair "file" (j/jstr target)))))
            none)
          nextRunRejected (mt rejection
            ((some item) (let [state nextRun.state
              updated (rl/withOwnsRejections state (listAppend state.ownsRejections (list item)))]
              (rl/withState nextRun updated)))
            ((none) nextRun))
          nextRunConfirm (mt (liveConfirmReceipt out)
            ((some confirm) (rl/withState nextRunRejected
              (rl/withFindings nextRunRejected.state nextRunRejected.state.findingsList
                (listAppend nextRunRejected.state.needsConfirmList (list confirm)))))
            ((none) nextRunRejected))
          rest (liveExecOps! (c/restOf ops) ra rootDir repoRoot sid journal env nextRunConfirm)]
      (pair (pairFirst rest)
        (pair (str receipt (if (stringEmpty? (pairFirst (pairSecond rest))) "" (str "\n" (pairFirst (pairSecond rest)))))
              (or wrote (pairSecond (pairSecond rest)))))))

fn liveGateStr row: (List (Pair String go/RVal)) key: String fallback: String -> String
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (mt (pairSecond p) ((go/rStr v) v) (_ fallback)))
    ((none) fallback))

fn liveGateInt row: (List (Pair String go/RVal)) key: String fallback: Int64 -> Int64
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (mt (pairSecond p) ((go/rInt v) v) (_ fallback)))
    ((none) fallback))

fn liveGateBool row: (List (Pair String go/RVal)) key: String -> Bool
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (mt (pairSecond p) ((go/rBool v) v) (_ false)))
    ((none) false))

fn liveGateResult row: (List (Pair String go/RVal)) -> g/GateResult
  (g/makeGateResult (liveGateStr row "cmd" "") (liveGateInt row "exit" 1)
    (liveGateStr row "stdout" "") (liveGateStr row "stderr" "") (liveGateBool row "timeout") (liveGateInt row "seconds" 0))

fn liveLastGateMap gates: (List g/GateResult) old: (Map String j/Json) -> (Map String j/Json)
  (fold (fn [acc gate] (mapSet acc (g/gateCmd gate) (ls/gateJson gate))) old gates)

fn ! runLiveGates! gates: (List String) rootDir: String timeout: Int64 -> (List g/GateResult)
  (map liveGateResult (go/runGates! (map (fn [p] (pair (stringFromInt64 (+ (pairFirst p) 1)) (pairSecond p))) (enumerate gates)) rootDir timeout none))

fn liveDoneOps? ops: (List (List (Pair String c/KvVal))) -> Bool
  (listAny? (fn [op] (mt (c/dictGet op "type") ((some v) (mt v ((c/kvStr t) (= t "done")) (_ false))) ((none) false))) ops)

fn liveIntentDeliver ops: (List (List (Pair String c/KvVal))) current: (Option String) -> (Option String)
  (if (listEmpty? ops)
    current
    (let [op (c/firstOf ops)
          next (if (= (liveOpName op) "intent")
            (let [rec (ex/intentReceipt op "intent")
                  okStatus (mt (ex/recGet rec "status") ((some v) (mt v ((ex/vStr s) (= s "ok")) (_ false))) ((none) false))]
              (if okStatus
                (mt (ex/recGet rec "deliver") ((some v) (mt v ((ex/vStr d) (some d)) (_ current))) ((none) current))
                current))
            current)]
      (liveIntentDeliver (c/restOf ops) next)))

fn liveCommitMessage ops: (List (List (Pair String c/KvVal))) -> (Option String)
  (if (listEmpty? ops)
    none
    (let [op (c/firstOf ops)
          done (mt (c/dictGet op "type") ((some v) (mt v ((c/kvStr t) (= t "done")) (_ false))) ((none) false))]
      (if done
        (let [form (mt (c/dictGet op "form") ((some v) (mt v ((c/kvStr text) text) (_ ""))) ((none) ""))
              fields (c/parseKv form)]
          (mt (c/dictGet fields "commit") ((some v) (mt v ((c/kvStr message) (some message)) (_ none))) ((none) none)))
        (liveCommitMessage (c/restOf ops)))))

fn liveGateResultsGreen? gates: (List g/GateResult) -> Bool
  (cond
    ((listEmpty? gates) true)
    ((= (g/gateExit (c/firstOf gates)) 0) (liveGateResultsGreen? (c/restOf gates)))
    (else false))

fn ! liveBody! ra: RunArgs repoRoot: String rootDir: String path: String system: String env: ls/LoopEnv
    providerCall: (fn [pv/Provider String String] -> pv/Turn) wrapped: rl/ProviderRun -> (Pair rl/ProviderRun ls/Step)
  (let [run wrapped.run
        state run.state
        turn state.turn
        transcript (ctx/renderTranscript wrapped.history state.transcriptChars)
        advisorInvoked (= (optionOr ra.intent "") "reinforce")
        advisorResult (if advisorInvoked
          (env.advise (ctx/advisorSystem) (str "Task: " ra.task "\n\n" transcript))
          (ok none))
        advisorLogged (if advisorInvoked (appendLiveHook! path turn "advisor" advisorResult) true)
        advisorText (mt advisorResult ((ok value) (optionOr value "")) ((err _) ""))
        user (str "Task: " ra.task (if (stringEmpty? transcript) "" (str "\n\n" transcript))
          (if (stringEmpty? advisorText) "" (str "\n\nAdvisor: " advisorText))
          (if run.lastDefect "\n\nThe prior reply contained no actionable operations; retry with a valid operation or terminal form." ""))
        _ (fileAppend path (str "(:turn " (stringFromInt64 turn) " :sent \"" (c/escapeAsn user) "\")\n"))
        retried (liveProviderRetry! wrapped.provider
          (fn [p attempt] (providerCall p system user)) env.wallBudget env.sleep)
        _retryLogged (appendRetryLines! path turn (pairSecond retried))
        response (pairFirst retried)
        _usageLogged (mt (providerUsageLine response.meta)
          ((some form) (ok? (fileAppend path (str form "\n")))) ((none) true))]
    (mt response.reply
      ((err e)
        (do
          (fileAppend path (str "(:turn " (stringFromInt64 turn) " :error :" (pv/errorCode e) " :message \"" (c/escapeAsn (pv/errorMessage e)) "\")\n"))
          (let [nextState (rl/withHeadState state turn state.readStreak state.writesPersisted none
                    state.allGateResults state.lastGates "failed" none none state.runStarted)
                nextRun (rl/withState run nextState)]
            (pair (rl/ProviderRun :run nextRun :provider response.provider :history wrapped.history) (stop)))))
      ((ok replyOpt)
        (mt replyOpt
          ((none)
            (do
              (fileAppend path (str "(:turn " (stringFromInt64 turn) " :error :ERR_NO_REPLY)\n"))
              (let [nextState (rl/withHeadState state turn state.readStreak state.writesPersisted none
                        state.allGateResults state.lastGates "failed" none none state.runStarted)
                    nextRun (rl/withState run nextState)]
                (pair (rl/ProviderRun :run nextRun :provider response.provider :history wrapped.history) (stop)))))
          ((some reply)
            (let [clean (tr/turnReply reply (some ra.gates))
                  normalized clean.text
                  facts clean.facts
                  operations facts.ops
                  findingForms facts.dataFindings
                  priorFindings (map ctx/pyStr state.findingsList)
                  mergedFindingForms (fold (fn [acc form] (pairFirst (cl/mergeFindings form acc))) priorFindings findingForms)
                  effects (resultOr (tx/loadEffects! repoRoot) (list))
                  execEnv (ex/makeExecEnv rootDir repoRoot (optionOr (modeOf ra.modeHint) "auto") ra.owns state.writesPersisted ra.base
                    ra.gates effects "" (list) (ctx/readPayloadChars (optionOr state.contextTokens 24000))
                    ra.timeout none run.session none)
                  parseDefect (or (listEmpty? operations)
                    (or (listEmpty? facts.forms) (stringEmpty? (stringTrim normalized))))
                  execResult (if parseDefect (pair run (pair "" false))
                    (liveExecOps! operations ra rootDir repoRoot run.session path execEnv run))
                  executedRaw (pairFirst execResult)
                  executed (mt (if ra.plan (livePlanJson facts.forms) none)
                    ((some planState) (rl/withState executedRaw (rl/withPlan executedRaw.state planState)))
                    ((none) executedRaw))
                  opReceipts (pairFirst (pairSecond execResult))
                  wrote (pairSecond (pairSecond execResult))
                  got (str normalized (if (stringEmpty? opReceipts) "" (str "\n" opReceipts)))
                  newGates (if parseDefect (list) (runLiveGates! ra.gates rootDir ra.gateTimeout))
                  allGates (listAppend state.allGateResults newGates)
                  lastGates (liveLastGateMap newGates state.lastGates)
                  history (listAppend wrapped.history
                    (list (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr user)) (pair "got" (j/jstr got))))))
                  _ (fold (fn [acc gate] (and acc (ok? (fileAppend path (str "(:gate :cmd \"" (c/escapeAsn (g/gateCmd gate)) "\" :exit "
                       (stringFromInt64 (g/gateExit gate)) (if (g/gateTimeout gate) " :timeout true" "") ")\n"))))) true newGates)
                  _ (fileAppend path (str "(:turn " (stringFromInt64 turn) " :reply \"" (c/escapeAsn normalized) "\")\n"))
                  _ (if parseDefect (ok? (fileAppend path (str "(:turn " (stringFromInt64 turn) " :parse-defect true)\n"))) true)
                  done (liveDoneOps? operations)
                  findingsDelivery (and (not (listEmpty? findingForms))
                    (listContains? (list "scout" "review") (optionOr (modeOf ra.modeHint) "")))
                  intentDeliver (liveIntentDeliver operations none)
                  deliver (cond
                    (findingsDelivery (some "findings"))
                    ((some? intentDeliver) intentDeliver)
                    ((and done (= (optionOr (modeOf ra.modeHint) "") "implement")) (some "patch"))
                    (else state.deliver))
                  writesPersisted (or state.writesPersisted wrote)
                  gatesGreen (and (liveGateResultsGreen? newGates)
                    (or (listEmpty? ra.gates) (not (listEmpty? newGates))))
                  patchReady (if (listEmpty? ra.gates)
                    (or (!= (optionOr deliver "") "patch") writesPersisted)
                    writesPersisted)
                  gatesTerminal (and (not (listEmpty? ra.gates)) (not state.commitRequested))
                  terminal (or findingsDelivery (and gatesGreen (and (or done gatesTerminal) patchReady)))
                  reviewInvoked (and terminal (and (= (optionOr (modeOf ra.modeHint) "") "review")
                    (or (liveReviewerAvailable? wrapped.provider) (= (optionOr ra.intent "") "reinforce"))))
                  reviewResult (if reviewInvoked
                    (env.review (ctx/findingsCheckSystem)
                      (str "Task: " ra.task "\n\nLive response:\n" normalized))
                    (ok none))
                  reviewLogged (if reviewInvoked (appendLiveHook! path turn "reviewer" reviewResult) true)
                  integrity (if (and terminal (not (listEmpty? ra.gates)))
                    (gi/gateIntegrity! ra.gates ra.owns rootDir newGates ra.gateTimeout none)
                    (pair true "not required"))
                  _ (if (and terminal (not (listEmpty? ra.gates)))
                    (ok? (fileAppend path (str "(:gateIntegrity :ok " (if (pairFirst integrity) "true" "false")
                      " :message \"" (c/escapeAsn (pairSecond integrity)) "\")\n"))) true)
                  reviewOk (if reviewInvoked (liveReviewAccepts? reviewResult) true)
                  hooksOk (and (liveHookOk? advisorResult) reviewOk)
                  status (if (or (not (pairFirst integrity)) (not hooksOk))
                    "failed" (if terminal "ok" "running"))
                  nextState0 (rl/withHeadState executed.state turn state.readStreak writesPersisted
                    deliver allGates lastGates
                    status none none state.runStarted)
                  nextState (rl/withFindings nextState0 (map (fn [form] (j/jstr form)) mergedFindingForms)
                    executed.state.needsConfirmList)
                  withCommit (mt (liveCommitMessage operations)
                    ((some message) (rl/withCommitMessage executed (some message)))
                    ((none) executed))
                  notedRun (rl/noteParseTurn (rl/withState withCommit nextState) turn parseDefect)
                  nextRun (if (and terminal (not (pairFirst integrity)))
                    (rl/withState notedRun (rl/withHeadState nextState turn nextState.readStreak writesPersisted deliver allGates lastGates
                      "failed" none (some (pairSecond integrity)) state.runStarted))
                    notedRun)]
              (pair (rl/ProviderRun :run nextRun :provider response.provider :history history)
                    (if terminal (stop) (nextTurn)))))))))

fn ! liveJournal ra: RunArgs rootDir: String -> (Result (Pair String String) String)
  (mt (dirCreate (pyJoin rootDir ".asl/run/agentLoop"))
    ((err e) (err e))
    ((ok _)
      (let [chosen (mt ra.resume
                     ((some st) (ok (pair st.session st.journal)))
                     ((none) (mt (newSessionId) ((err e) (err e)) ((ok sid) (ok (pair sid (journalPathOf rootDir sid)))))))]
        (mt chosen
          ((err e) (err e))
          ((ok sp) (mt (fileAppend (pairSecond sp) "") ((err e) (err e)) ((ok _) (ok sp))))))))

fn receiptPhases result: ls/RunResult -> (List String)
  (let [findingsReceipt (if (listEmpty? result.findings)
                          none
                          (ctx/receiptPhase (j/jobj (list (pair "type" (j/jstr "findings"))))))]
    (mt findingsReceipt
      ((some phase) (if (listContains? result.phases phase) result.phases (listAppend result.phases (list phase))))
      ((none) result.phases)))

fn loopResultOf ra: RunArgs rootDir: String result: ls/RunResult usage: (Option Usage) -> LoopResult
  (let [counts result.batching
        countAt (fn [key] (optionOr (intValue (optionOr (j/jsonGet counts key) (j/jint 0))) 0))
        batching (some (Batching :turns (countAt "turns") :ops (countAt "ops") :single (countAt "single")))]
  (LoopResult :status result.status :modeHint (modeOf ra.modeHint)
    :deliver (if (= (optionOr result.deliver "") "findings") none result.deliver)
    :phases (receiptPhases result) :session (some result.session)
    :journal result.journal :unbacked result.unbacked
    :unbackedClaims (map pv/pyStr result.unbackedClaims) :contextTokens result.contextTokens
    :turns (some result.turns) :gates (map ls/gateJson result.gates)
    :escalate (mt result.escalate ((some e) (some (pv/pyStr e))) ((none) none))
    :patch result.patch :restored result.restored :written result.written
    :needsConfirm (liveConfirmItems result.needsConfirm) :ownsRejected (liveOwnsItems result.ownsRejected) :error result.error :gatePreflight (list)
    :parseDefect result.parseDefect :parseDefectTurn result.parseDefectTurn
    :findings (some (map pv/pyStr result.findings)) :queueWaitSec result.queueWaitSec
    :execSec result.execSec :usage (mt (liveUsage result.usage) ((some u) (some u)) ((none) usage))
    :batching batching :plan (livePlan result.planSummary)))

fn ! executeLive ra: RunArgs repoRoot: String rootDir: String env: pv/ProviderEnv -> MainResult
  (mt (pv/makeProvider! ra.backend "auto" rootDir ra.model ra.timeout "" ra.queueTimeout ra.timeoutSet env)
    ((err e) (rejectWith (str ":error ERR_BACKEND :message \"" (c/escapeAsn (pv/errorMessage e)) "\"") 1))
    ((ok provider)
      (mt (liveJournal ra rootDir)
        ((err e) (rejectWith (str ":error ERR_JOURNAL :message \"" (c/escapeAsn e) "\"") 1))
        ((ok sp)
          (let [session (pairFirst sp)
                path (pairSecond sp)
                model (if (stringEmpty? ra.model) (defaultModel ra.backend) ra.model)
                tokens (ctx/contextTokensFor (some model) (mt ra.contextTokens ((some t) (j/jint t)) ((none) (j/jnull)))
                  (listContains? (supportedBackends) ra.backend))
                prompt (jr/buildSystemPrompt repoRoot ra.task rootDir ra.base
                         ra.gates (some tokens) ra.plan)]
            (mt prompt
              ((err e) (rejectWith (str ":error ERR_HARNESS :message \"" (c/escapeAsn e) "\"") 1))
              ((ok system)
                (let [call (fn [sys user] (pv/nextTurn! provider sys user))
                      providerCall (fn [p sys user] (pv/nextTurn! p sys user))
                      hooks (liveHooks! provider)
                      liveEnv (ls/LoopEnv :provider call :task ra.task :modeHint (modeOf ra.modeHint)
                        :owns ra.owns :gates ra.gates :rootDir rootDir :budget ra.budget
                        :journalPath path :maxRetries 3 :sessionId (some session) :base (some ra.base)
                        :contextTokens (some tokens) :model (some model) :gateTimeout (some ra.gateTimeout)
                        :wallBudget ra.wallBudget :resume none :intent ra.intent :plan ra.plan :specCheck true
                        :next call :advise (pairFirst hooks) :review (pairSecond hooks)
                        :newId (fn [] session) :now (fn [] (ao/nowMono))
                        :sleep (fn [seconds] (do (if (> seconds 0) (sleepMs (* seconds 1000)) ()) true)))
                      result (rl/runLoopWithProvider! liveEnv provider (fn [le wrapped] (liveBody! ra repoRoot rootDir path system le providerCall wrapped)))
                      receipt (loopResultOf ra rootDir result (liveJournalUsage! rootDir result.journal))
                      line (formatReceipt receipt)]
                  (MainResult :stdout line :exitCode (if (and (= receipt.status "ok") (= receipt.unbacked 0)) 0 1))))))))))

fn ! executeDryRun ra: RunArgs repoRoot: String rootDir: String env: pv/ProviderEnv -> MainResult
  (mt (pv/buildDryRunInfo! ra.backend "auto" rootDir ra.model ra.timeout ra.queueTimeout env)
    ((err e) (rejectWith (str ":error ERR_BACKEND :message \"" (c/escapeAsn (pv/errorMessage e)) "\"") 1))
    ((ok info)
      (let [backend ra.backend
            model (if (stringEmpty? ra.model) (defaultModel backend) ra.model)
            tokens (ctx/contextTokensFor (some model) (mt ra.contextTokens ((some t) (j/jint t)) ((none) (j/jnull)))
                                         (listContains? (supportedBackends) backend))]
        (mt (jr/buildSystemPrompt repoRoot ra.task rootDir ra.base ra.gates (some tokens) ra.plan)
          ((err e) (rejectWith (str ":error ERR_HARNESS :message \"" (c/escapeAsn e) "\"") 1))
          ((ok prompt)
            (let [receipt (formatDryRun info prompt ra.owns)
                  bad (go/gatePreflight! ra.gates rootDir none)]
              (if (listEmpty? bad)
                (MainResult :stdout receipt :exitCode 0)
                (MainResult :stdout (str (c/sliceOf receipt 0 (- (stringLength receipt) 1)) " :error ERR_GATE_UNPARSABLE :gatePreflight ("
                                         (go/formatGatePreflight bad) "))")
                            :exitCode 1))))))))

fn ! execute ra: RunArgs dry: Bool repoRoot: String rootDir: String -> MainResult
  (let [env (pv/providerEnv!)]
    (if dry (executeDryRun ra repoRoot rootDir env) (executeLive ra repoRoot rootDir env)))

fn resumed ra: RunArgs st: ResumeState -> RunArgs
  (RunArgs :task st.task :modeHint st.modeHint :owns st.owns :gates st.gates :backend ra.backend
           :model ra.model :timeout ra.timeout :timeoutSet ra.timeoutSet :queueTimeout ra.queueTimeout
           :budget ra.budget :gateTimeout ra.gateTimeout :wallBudget ra.wallBudget
           :intent (mt ra.intent ((some i) (some i)) ((none) st.intent))
           :base st.base
           :contextTokens (mt ra.contextTokens ((some t) (if (= t 0) st.contextTokens (some t))) ((none) st.contextTokens))
           :plan ra.plan :resume (some st))

fn ! dispatch ps: (List (Pair String j/Json)) repoRoot: String rootDir: String timeout: Int64 queueTimeout: Int64 plan: Bool -> MainResult
  (let [resumeV (paramOr ps "resume" (j/jnull))
        ra (RunArgs :task (textValue (paramOr ps "task" (j/jstr ""))) :modeHint (optText (paramGet ps "modeHint"))
                    :owns (listValue (paramOr ps "owns" (j/jarr (list)))) :gates (listValue (paramOr ps "gates" (j/jarr (list))))
                    :backend (textValue (paramOr ps "backend" (j/jstr "agy"))) :model (optionOr (optText (paramGet ps "model")) "")
                    :timeout timeout :timeoutSet (paramHas ps "timeout") :queueTimeout queueTimeout
                    :budget (optionOr (intValue (paramOr ps "budget" (j/jint 3000))) 3000)
                    :gateTimeout (optionOr (intValue (paramOr ps "gateTimeout" (j/jint 300))) 300)
                    :wallBudget (some (optionOr (intValue (paramOr ps "wallBudget" (j/jint (min 86400 (+ timeout queueTimeout)))))
                                                  (min 86400 (+ timeout queueTimeout))))
                    :intent (optText (paramGet ps "intent"))
                    :base (textValue (paramOr ps "base" (j/jstr ""))) :contextTokens (intValue (paramOr ps "contextTokens" (j/jnull)))
                    :plan plan :resume none)
        dry (mt (paramOr ps "dryRun" (j/jbool false)) ((j/jbool b) b) (_ false))]
    (cond
      ((and (truthy resumeV) (not (paramHas ps "answer"))) (resumeReport (textValue resumeV) rootDir))
      ((truthy resumeV)
        (mt (journalResume (textValue resumeV) rootDir)
          ((err receipt) (MainResult :stdout receipt :exitCode 2))
          ((ok st) (execute (resumed ra st) dry repoRoot rootDir))))
      (else (execute ra dry repoRoot rootDir))))

fn ! checkWall ps: (List (Pair String j/Json)) repoRoot: String rootDir: String -> MainResult
  (let [given (optionOr (intValue (paramOr ps "timeout" (j/jint 600))) 600)
        queueTimeout (optionOr (intValue (paramOr ps "queueTimeout" (j/jint 1200))) 1200)
        wall (intValue (paramOr ps "wallBudget" (j/jnull)))
        timeout (mt wall ((some w) (if (paramHas ps "timeout") given (max given (- w queueTimeout)))) ((none) given))
        limit (min 86400 (+ timeout queueTimeout))
        planEnv (optionOr (envGet "ASL_LEON_PLAN") "")
        planNull (mt (paramGet ps "plan") ((some v) (mt v ((j/jnull) true) (_ false))) ((none) false))
        plan (mt (paramGet ps "plan") ((some v) (mt v ((j/jbool b) b) (_ false))) ((none) (= planEnv "1")))]
    (cond
      ((or planNull (not (listContains? (list "" "0" "1") planEnv)))
        (rejectWith (str ":error ERR_INVALID_ARG :key \"" (if planNull "plan" "ASL_LEON_PLAN") "\" :value \"" (c/escapeAsn (if planNull "" planEnv)) "\""
                         " :message \"plan is true or false; ASL_LEON_PLAN is 1 or 0 and sets it when :plan is absent\"")
                    2))
      ((not (inRange (intValue (paramOr ps "wallBudget" (j/jint limit))) 1 limit))
        (rejectWith (str ":error ERR_INVALID_ARG :key \"wallBudget\" :limit " (stringFromInt64 limit)
                         " :message \"wallBudget must be an integer of seconds from 1 to timeout + queueTimeout, at most 86400 (bin/asl kills the dispatch 30 s after that); raise :timeout, or leave it out and :wallBudget sets it\"")
                    2))
      (else (dispatch ps repoRoot rootDir timeout queueTimeout plan))))

fn ! checkBounds ps: (List (Pair String j/Json)) repoRoot: String rootDir: String -> MainResult
  (cond
    ((and (paramHas ps "contextTokens") (not (inRange (intValue (paramOr ps "contextTokens" (j/jnull))) 4000 2000000)))
      (rejectWith ":error ERR_INVALID_ARG :key \"contextTokens\" :message \"contextTokens must be an integer from 4000 to 2000000\"" 2))
    ((not (inRange (intValue (paramOr ps "gateTimeout" (j/jint 300))) 1 86400))
      (rejectWith ":error ERR_INVALID_ARG :key \"gateTimeout\" :message \"gateTimeout must be an integer of seconds from 1 to 86400\"" 2))
    (else (checkWall ps repoRoot rootDir)))

fn ! checkRoot ps: (List (Pair String j/Json)) repoRoot: String rootDir: String -> MainResult
  (let [rootV (paramOr ps "root" (j/jnull))]
    (if (not (truthy rootV))
      (checkBounds ps repoRoot rootDir)
      (let [raw (textValue rootV)
            target (go/pyRealpath! (pyJoin rootDir (expandUser raw)))]
        (if (isDir target)
          (checkBounds ps repoRoot target)
          (rejectWith (str ":error ERR_INVALID_ARG :key \"root\" :value \"" (c/escapeAsn raw) "\" :message \"root is not a directory: " (c/escapeAsn target) "\"") 2)))))

fn ! checkInvocation inv: Invocation repoRoot: String rootDir: String -> MainResult
  (let [ps inv.params]
    (cond
      ((some? inv.syntaxError) (rejectWith (str ":error ERR_SYNTAX :message \"" (c/escapeAsn (optionOr inv.syntaxError "")) "\"") 2))
      ((paramHas ps "role") (rejectWith ":error ERR_ROLE_DEPRECATED :message \"use :intent or state the task\"" 2))
      ((not (listEmpty? inv.unknownOps)) (unknownArg! (c/firstOf inv.unknownOps)))
      ((some? inv.contextFileError)
        (let [e (optionOr inv.contextFileError (pair "" ""))] (contextFileRejection (pairFirst e) (pairSecond e))))
      ((and (not (truthy (paramOr ps "task" (j/jstr "")))) (not (truthy (paramOr ps "resume" (j/jnull)))))
        (rejectWith ":error ERR_MISSING_ARG :message \"missing :task\"" 2))
      (else (checkRoot ps repoRoot rootDir))))

fn ! mainWithRoots argv: (List String) repoRoot: String rootDir: String -> MainResult
  (if (listEmpty? argv)
    (rejectWith ":error ERR_MISSING_ARG :message \"no form provided\"" 2)
    (checkInvocation (parseInvocation (c/firstOf argv) rootDir) repoRoot rootDir))

fn ! mainCli argv: (List String) -> Int64
  (let [repoRoot (resultOr (realPath ".") ".")
        rootDir (mt (envGet "ASL_ROOT_DIR") ((some r) (if (stringEmpty? r) repoRoot r)) ((none) repoRoot))
        res (mainWithRoots argv repoRoot rootDir)]
    (do
      (println res.stdout)
      res.exitCode))

fn ! main argv: (List String) -> Int64
  (mainCli argv)
