(module asl/agentLoop/main
  :x [withRemote knownParams acceptedKeys nearestKey! tokenizeAsn Invocation paramGet parseInvocation
      ResumeTurn ResumeState RunArgs resumeReport journalResume journalModeHint
      NeedsConfirm OwnsRejection Usage Batching LoopResult formatReceipt stopCause lastStepIn receiptFieldsIn receiptFieldNames
      formatDryRun MainResult supportedBackends defaultModel liveAdvisor liveReviewer liveHooks! liveOwnsItems liveUsage livePlan
      providerUsageLine liveJournalUsage! liveProviderRetry! liveBody! attractorProvider validPrefix? prefixDrop focusTail parentWatch! parentUnwatch! loopResultOf Checked Valid valid invalid checkInvocation liveTurn! appendRetryLines! paramHas LiveAsk LiveSession LivePrep prepared prepRejected liveSetup! liveResult liveAsk! liveApply! liveGone! parentGone? wallLeft runArgsOf main mainCli mainWithRoots]
  :i [(asl/agentLoop/core :a c)
      (asl/agentLoop/diff :a diff)
      (asl/agentLoop/providers :a pv)
      (asl/agentLoop/attractor :a at) (asl/agentLoop/nativeTools :a nt)
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
      (asl/agentLoop/claimBacking :a cb)
      (asl/agentLoop/agentConfig :a ac)
      (asl/agentLoop/poolOps :a po)
      (aslGateway/codeRoute :a cr)
      (aslGateway/config :a gc)
      (asl-tools/fleet/run :a fr)
      (asl-json/json :a j)
      (asl/agentLoop/grounding :a gr)])

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
  (:f plan (Option pl/PlanSummary))
  (:f vacuousGates (List String))
  (:f specCheck (Option ls/SpecVerdict))
  (:f stop (Option String))
  (:f lastStep (Option String)))

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
  (:f inputTokenBudget Int64)
  (:f gateTimeout Int64)
  (:f wallBudget (Option Int64))
  (:f intent (Option String))
  (:f base String)
  (:f remote String)
  (:f contextTokens (Option Int64))
  (:f plan Bool)
  (:f attractor String :default "")
  (:f nativeTools String :default "")
  (:f prefix String :default "")
  (:f resume (Option ResumeState))
  (:f pool (Option po/PoolSelf))
  (:f parentPid (Option Int64))
  (:f route (Option RouteSetup)))

fn knownParams -> (List String)
  (list "agent" "task" "mode" "intent" "root" "owns" "gates" "backend" "budget" "inputTokenBudget" "dryRun" "resume" "answer" "role"
        "model" "timeout" "contextFile" "base" "queueTimeout" "contextTokens" "gateTimeout" "wallBudget" "plan" "attractor" "nativeTools" "prefix" "poolChan" "poolIdx" "parentPid" "remote")

fn acceptedKeys -> (List String)
  (listSortBy (fn [k] k) (filter (fn [k] (not (listContains? (list "agent" "mode" "role" "poolChan" "poolIdx" "parentPid") k))) (knownParams)))

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
      (match (underscoreDigits bs n 0 (list))
        ((some digits) (stringToInt64 (str sign digits)))
        ((none) none))))

fn truthy v: j/Json -> Bool
  (match v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint i) (!= i 0))
    ((j/jfloat f) (!= f 0.0))
    ((j/jnum f) (!= f 0.0))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj kvs) (not (listEmpty? kvs))))

fn pyIntOf v: j/Json -> (Option Int64)
  (match v
    ((j/jint i) (some i))
    ((j/jbool b) (some (if b 1 0)))
    ((j/jstr s) (pyIntText s))
    (_ none))

fn intValue v: j/Json -> (Option Int64)
  (match v ((j/jint i) (some i)) (_ none))

fn textValue v: j/Json -> String
  (pv/pyStr v)

fn listValue v: j/Json -> (List String)
  (match v
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
          (match (stringTokenEnd bs n (+ i 1) false)
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
    (else (match (parseValue toks) ((pair v rest) (parseItems rest closing (cons v acc))))))

fn parseValue toks: (List String) -> (Pair j/Json (List String))
  (let [tok (c/firstOf toks)
        rest (c/restOf toks)]
    (cond
      ((or (= tok "(") (= tok "[")) (parseItems rest (if (= tok "(") ")" "]") (list)))
      ((and (stringStartsWith? tok "\"") (stringEndsWith? tok "\"")) (pair (j/jstr (unescapeToken tok)) rest))
      ((= tok "true") (pair (j/jbool true) rest))
      ((= tok "false") (pair (j/jbool false) rest))
      (else (match (pyIntText tok)
              ((some v) (pair (j/jint v) rest))
              ((none) (pair (j/jstr tok) rest))))))

fn paramGet ps: (List (Pair String j/Json)) key: String -> (Option j/Json)
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) ps))
    ((some p) (some (pairSecond p)))
    ((none) none))

fn paramHas ps: (List (Pair String j/Json)) key: String -> Bool
  (some? (paramGet ps key))

fn paramOr ps: (List (Pair String j/Json)) key: String fallback: j/Json -> j/Json
  (optionOr (paramGet ps key) fallback)

fn paramSet ps: (List (Pair String j/Json)) key: String v: j/Json -> (List (Pair String j/Json))
  (listAppend (filter (fn [p] (!= (pairFirst p) key)) ps) (list (pair key v)))

fn listParam v: j/Json -> j/Json
  (match v
    ((j/jarr xs) (j/jarr (map (fn [x] (j/jstr (pv/pyStr x))) xs)))
    (_ (j/jarr (if (truthy v) (list (j/jstr (pv/pyStr v))) (list)))))

fn intParam v: j/Json fallback: Int64 -> j/Json
  (j/jint (optionOr (pyIntOf v) fallback))

fn intOrNull v: j/Json -> j/Json
  (match v ((j/jint i) (j/jint i)) (_ (j/jnull)))

fn strParam v: j/Json -> j/Json
  (j/jstr (pv/pyStr v))

fn applyKey ps: (List (Pair String j/Json)) key: String v: j/Json -> (Pair (List (Pair String j/Json)) (Option String))
  (cond
    ((listContains? (list "task" "root" "backend" "resume" "answer" "model" "contextFile" "base" "poolChan" "remote") key)
      (pair (paramSet ps key (strParam v)) none))
    ((= key "mode") (pair (paramSet ps "modeHint" (j/jstr (lstripColons (pv/pyStr v)))) none))
    ((or (= key "intent") (= key "role")) (pair (paramSet ps key (j/jstr (lstripColons (pv/pyStr v)))) none))
    ((or (= key "owns") (= key "gates")) (pair (paramSet ps key (listParam v)) none))
    ((= key "budget") (pair (paramSet ps key (intParam v 3000)) none))
    ((= key "poolIdx") (pair (paramSet ps key (intParam v -1)) none))
    ((= key "inputTokenBudget") (pair (paramSet ps key (intParam v 0)) none))
    ((= key "timeout") (pair (paramSet ps key (intParam v 600)) none))
    ((= key "queueTimeout") (pair (paramSet ps key (intParam v 1200)) none))
    ((= key "dryRun")
      (pair (paramSet ps key (j/jbool (match v ((j/jbool b) b) ((j/jstr s) (= s "true")) (_ false)))) none))
    ((= key "contextTokens")
      (pair (paramSet ps key (match (pyIntOf v) ((some i) (j/jint i)) ((none) (j/jnull)))) none))
    ((or (= key "gateTimeout") (or (= key "wallBudget") (= key "parentPid"))) (pair (paramSet ps key (intOrNull v)) none))
    ((= key "plan") (pair (paramSet ps key (match v ((j/jbool b) (j/jbool b)) (_ (j/jnull)))) none))
    ((= key "attractor") (pair (paramSet ps key (j/jstr (lstripColons (pv/pyStr v)))) none))
    ((= key "nativeTools") (pair (paramSet ps key (j/jstr (lstripColons (pv/pyStr v)))) none))
    ((= key "prefix") (pair (paramSet ps key (j/jstr (lstripColons (pv/pyStr v)))) none))
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
          (match taken
            ((pair v after)
              (match (applyKey ps key v)
                ((pair next unk)
                  (paramLoop after next (match unk ((some k) (cons k unknown)) ((none) unknown)))))))))))

fn ! isDir path: String -> Bool
  (match (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! isFile path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

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
        (match (fileReadString full)
          ((err e) (pair ps (some (pair "read_error" e))))
          ((ok content)
            (pair (paramSet ps "task" (j/jstr (joinTask (textValue (paramOr ps "task" (j/jstr ""))) content))) none))))))

fn invocationOf ps: (List (Pair String j/Json)) unknown: (List String) syntax: (Option String) cfErr: (Option (Pair String String)) -> Invocation
  (Invocation :params ps :unknownOps unknown :syntaxError syntax :contextFileError cfErr)

fn ! parseInvocation formText: String rootDir: String -> Invocation
  (if (stringEmpty? (pv/pyStrip formText))
    (invocationOf (list) (list) none none)
    (match (tokenizeAsn formText)
      ((err e) (invocationOf (list) (list) (some e) none))
      ((ok toks)
        (if (or (listEmpty? toks) (!= (c/firstOf toks) "("))
          (invocationOf (list) (list) (some "invocation must be an ASN parenthesised form") none)
          (let [body (c/restOf toks)
                start (if (and (not (listEmpty? body)) (or (= (c/firstOf body) ":agent") (= (c/firstOf body) "agent")))
                        (c/restOf body)
                        body)]
            (match (paramLoop start (list) (list))
              ((pair ps unknown)
                (if (paramHas ps "contextFile")
                  (match (applyContextFile ps rootDir) ((pair ps2 cfErr) (invocationOf ps2 unknown none cfErr)))
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
    (match (quotedEnd bs n (+ i 1))
      ((some e) (some (pair (c/sliceOf s (+ i 1) (- e 1)) e)))
      ((none) none)))

fn gapEnd bs: Bytes n: Int64 i: Int64 anySpace: Bool -> (Option Int64)
  (if anySpace
    (let [e (spacesEnd bs n i)] (if (> e i) (some e) none))
    (if (= (byteAt bs n i) 32) (some (+ i 1)) none))

fn litAt s: String i: Int64 lit: String -> Bool
  (= (optionOr (stringSlice s i (+ i (stringLength lit))) "") lit)

fn searchFrom s: String lit: String start: Int64 matcher: (fn [Int64] -> (Option T)) -> (Option T)
  (match (stringIndexOf (c/sliceOf s start (stringLength s)) lit)
    ((none) none)
    ((some off)
      (let [p (+ start off)]
        (match (matcher p)
          ((some v) (some v))
          ((none) (searchFrom s lit (+ p 1) matcher))))))

fn quotedField s: String key: String anySpace: Bool -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (searchFrom s key 0
      (fn [p] (match (gapEnd bs n (+ p (stringLength key)) anySpace)
                ((none) none)
                ((some q) (match (quotedAt s bs n q) ((some hit) (some (pairFirst hit))) ((none) none)))))))

fn removeQuotedField s: String key: String anySpace: Bool -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (removeLoop s bs n key anySpace 0 0 (list)))

fn removeLoop s: String bs: Bytes n: Int64 key: String anySpace: Bool from: Int64 kept: Int64 acc: (List String) -> String
  (match (stringIndexOf (c/sliceOf s from n) key)
    ((none) (stringJoin (listReverse (cons (c/sliceOf s kept n) acc)) ""))
    ((some off)
      (let [p (+ from off)
            hit (match (gapEnd bs n (+ p (stringLength key)) anySpace)
                  ((none) none)
                  ((some q) (match (quotedAt s bs n q) ((some h) (some (pairSecond h))) ((none) none))))]
        (match hit
          ((some e) (removeLoop s bs n key anySpace e e (cons (c/sliceOf s kept p) acc)))
          ((none) (removeLoop s bs n key anySpace (+ p 1) kept acc))))))

fn keywordField s: String key: String -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (searchFrom s key 0
      (fn [p] (match (gapEnd bs n (+ p (stringLength key)) true)
                ((none) none)
                ((some q)
                  (if (!= (byteAt bs n q) 58)
                    none
                    (let [e (runEnd bs n (+ q 1) isWordByte)]
                      (if (> e (+ q 1)) (some (c/sliceOf s (+ q 1) e)) none))))))))

fn journalModeHint header: String -> (Option String)
  (let [head (removeQuotedField header ":task" true)]
    (match (quotedField head ":modeHint" true)
      ((some raw) (some (c/asnUnescape raw)))
      ((none)
        (match (keywordField head ":mode")
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
      (match (gapEnd bs n 6 true)
        ((none) none)
        ((some q)
          (let [e (runEnd bs n q isDigitByte)]
            (if (> e q) (stringToInt64 (c/sliceOf s q e)) none))))))

fn noteLine s: String -> (Option String)
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (not (litAt s 0 "(:turn"))
      none
      (match (gapEnd bs n 6 true)
        ((none) none)
        ((some q)
          (let [e (runEnd bs n q isDigitByte)]
            (if (= e q)
              none
              (match (gapEnd bs n e true)
                ((none) none)
                ((some k)
                  (if (not (litAt s k ":note"))
                    none
                    (match (gapEnd bs n (+ k 5) true)
                      ((none) none)
                      ((some v)
                        (match (quotedAt s bs n v)
                          ((some hit) (if (= (+ (pairSecond hit) 1) n) (if (litAt s (pairSecond hit) ")") (some (pairFirst hit)) none) none))
                          ((none) none)))))))))))))

fn gateLine s: String -> (Option (Pair String String))
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (not (litAt s 0 "(:gate"))
      none
      (match (gapEnd bs n 6 true)
        ((none) none)
        ((some a)
          (if (not (litAt s a ":cmd"))
            none
            (match (gapEnd bs n (+ a 4) true)
              ((none) none)
              ((some b)
                (match (quotedAt s bs n b)
                  ((none) none)
                  ((some hit)
                    (match (gapEnd bs n (pairSecond hit) true)
                      ((none) none)
                      ((some k)
                        (if (not (litAt s k ":exit"))
                          none
                          (match (gapEnd bs n (+ k 5) true)
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
      (fn [p] (match (gapEnd bs n (+ p 7) true)
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
        (with st :lastTurn (match (turnAtStart s) ((some t) (max t st.lastTurn)) ((none) st.lastTurn)) :note (match (noteLine s) ((some raw) (some raw)) ((none) st.note)) :prevGate false))
      ((stringStartsWith? s "(:gate ")
        (match (gateLine s)
          ((none) st)
          ((some g)
            (with st :gates (listAppend (if st.prevGate st.gates (list)) (list g)) :prevGate true))))
      ((stringStartsWith? s "(:result ")
        (with st :prevGate false :result (some (optionOr (statusField s) "unknown"))))
      (else st)))

fn ! stagedUnder dir: String rel: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (let [kinds (map (fn [name]
                         (let [path (pyJoin dir name)
                               isLink (match (fileLstat path) ((ok ls) ls.isSymlink) ((err _) false))
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
      (match (fileReadString path)
        ((err e)
          (MainResult :stdout (str "(:agentReceipt :status :rejected :error ERR_JOURNAL_READ :session \"" (c/escapeAsn session)
                                   "\" :message \"" (c/escapeAsn e) "\")")
                      :exitCode 1))
        ((ok text)
          (let [st (fold reportLine
                         (ReportState :task "" :hint none :lastTurn 0 :note none :gates (list) :prevGate false :result none)
                         (go/pySplitLines (pv/universalNewlines text) false))
                status (match st.result ((none) "resumable") ((some r) (if (= r "ok") "done" "escalated")))
                stageDir (pyJoin (pyJoin rootDir ".asl/vfs") session)
                staged (if (isDir stageDir) (stagedUnder stageDir "") (list))
                shown (listTake staged 20)]
            (MainResult
              :stdout (str "(:agentReceipt :status :" status " :session \"" (c/escapeAsn session) "\""
                           " :task \"" st.task "\""
                           (match st.hint ((some h) (if (stringEmpty? h) "" (str " :modeHint \"" (c/escapeAsn h) "\""))) ((none) ""))
                           " :lastTurn " (stringFromInt64 st.lastTurn)
                           (match st.note ((some raw) (str " :note \"" raw "\"")) ((none) ""))
                           " :lastGates (" (stringJoin (map (fn [g] (str "(:cmd \"" (pairFirst g) "\" :exit " (pairSecond g) ")")) st.gates) " ") ")"
                           " :result " (match st.result ((some r) (str ":" r)) ((none) "none"))
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
              (match (quotedAt s bs n (+ kindEnd 1))
                ((none) none)
                ((some hit)
                  (if (and (= (+ (pairSecond hit) 1) n) (litAt s (pairSecond hit) ")"))
                    (match (stringToInt64 (c/sliceOf s 7 e))
                      ((some t) (some (pair t (pair kind (pairFirst hit)))))
                      ((none) none))
                    none)))))))))

fn listStrings s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (Option (List String))
  (let [k (spacesEnd bs n i)]
    (match (quotedAt s bs n k)
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
  (match (quotedField line ":task" false)
    ((none) (err "the session header has no :task string"))
    ((some rawTask)
      (let [intent (quotedField (removeQuotedField line ":task" false) ":intent" false)]
        (ok (ResumeState :session session :journal journal :task (c/asnUnescape rawTask) :modeHint (journalModeHint line)
                         :intent (match intent ((some raw) (if (= raw "auto") none (some (c/asnUnescape raw)))) ((none) none))
                         :owns (listField line ":owns") :gates (listField line ":gates")
                         :base (match (quotedField line ":base" false) ((some raw) (c/asnUnescape raw)) ((none) ""))
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
                       (match (headerOf session journal line sc.text)
                         ((ok h) (with sc :header (some h) :malformed none))
                         ((err e) (with sc :header none :malformed (some e))))
                       sc)
          withTurn (match (turnEntry line)
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
        (match (keywordField line ":status")
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
      (match (fileReadString path)
        ((err e) (err (str "(:agentReceipt :status :rejected :error ERR_JOURNAL_READ :session \"" (c/escapeAsn session) "\" :message \"" (c/escapeAsn e) "\")")))
        ((ok raw)
          (let [text (pv/universalNewlines raw)
                sc (fold (fn [acc line] (scanLine session path acc line))
                         (ResumeScan :header none :malformed none :slots (list) :note "" :result none :text text)
                         (go/pySplitLines text false))
                replied (listSortBy (fn [t] t.turn) (filter (fn [t] (some? t.sent)) sc.slots))]
            (match sc.malformed
              ((some m) (err (str "(:agentReceipt :status :rejected :error ERR_JOURNAL_READ :session \"" (c/escapeAsn session) "\" :message \"" (c/escapeAsn m) "\")")))
              ((none)
                (match sc.header
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
  (match o ((some s) (if (stringEmpty? s) none (some s))) ((none) none))

fn gateCmd g: j/Json -> String
  (match (j/jsonGet g "cmd") ((some v) (pv/pyStr v)) ((none) ""))

fn keptFindings xs: (List String) -> (List String)
  (filter (fn [f] (not (stringEmpty? f))) (map pv/pyStrip xs))

fn unavailableSpecText reasons: (List String) -> String
  (str " :specCheck (:verdict unavailable :reviewer unavailable :reasons ("
       (stringJoin (map (fn [x] (str "\"" (c/escapeAsn x) "\"")) reasons) " ") "))")

; (:m :ref LEON-WRITE-FAIL-CLASSIFY :do "why the run stopped, for a receipt the conductor journal cuts short: the loop signal that ended it (turnBudget wallBudget tokenBudget readStreak noWrite parseDefect repeatFailure provider noReply gateIntegrity), else error for a run that failed with an error, gateVacuous for a failed run whose declared gates were green before any write, done for ok, and the status otherwise")
fn stopCause status: String signal: (Option String) error: (Option String) vacuous: (List String) -> String
  (match (nonEmpty signal)
    ((some s) s)
    ((none)
      (cond
        ((some? (nonEmpty error)) "error")
        ((= status "ok") "done")
        ((and (= status "failed") (not (listEmpty? vacuous))) "gateVacuous")
        (else status))))

fn replyOp reply: String -> String
  (match (stringIndexOf reply ":op \\\"")
    ((some at)
      (let [rest (c/sliceOf reply (+ at 6) (stringLength reply))]
        (c/sliceOf rest 0 (optionOr (stringIndexOf rest "\\") (stringLength rest)))))
    ((none)
      (cond
        ((stringEmpty? (stringTrim reply)) "empty")
        ((stringStartsWith? reply "(:")
          (let [rest (c/sliceOf reply 2 (stringLength reply))
                ends (map (fn [o] (optionOr o 0)) (filter (fn [o] (some? o)) (list (stringIndexOf rest " ") (stringIndexOf rest ")"))))]
            (c/sliceOf rest 0 (optionOr (listMin ends) (stringLength rest)))))
        (else "prose"))))

; (:m :ref LEON-WRITE-FAIL-CLASSIFY :do "the last reply the journal holds, as (:turn N :op name): the op of a (:step :op ...) reply, else the head of its first form, empty or prose")
fn lastStepIn text: String -> (Option String)
  (let [replies (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit text "\n"))]
    (match (listLast replies)
      ((none) none)
      ((some l)
        (let [at (optionOr (stringIndexOf l " :reply \"") 0)
              body (c/sliceOf l (+ at 9) (max (+ at 9) (- (stringLength l) 2)))]
          (some (str "(:turn " (c/sliceOf l 7 at) " :op \"" (c/escapeAsn (replyOp body)) "\")"))))))

fn ! liveLastStep! rootDir: String journal: (Option String) -> (Option String)
  (match journal
    ((some p) (match (fileReadString (pyJoin rootDir p)) ((ok text) (lastStepIn text)) ((err _) none)))
    ((none) none))

fn formatReceipt r: LoopResult -> String
  (str "(:agentReceipt :status :" r.status
       (match (nonEmpty r.stop) ((some s) (str " :stop " s)) ((none) ""))
       (match (nonEmpty r.lastStep) ((some l) (str " :lastStep " l)) ((none) ""))
       (match (nonEmpty r.modeHint) ((some m) (str " :modeHint \"" (c/escapeAsn m) "\"")) ((none) ""))
       (match (nonEmpty r.deliver) ((some d) (str " :deliver :" d)) ((none) ""))
       " :phases (" (stringJoin r.phases " ") ")"
       (match (nonEmpty r.session) ((some s) (str " :session \"" s "\"")) ((none) ""))
       (match (nonEmpty r.journal) ((some p) (str " :journal \"" p "\"")) ((none) ""))
       " :unbacked " (stringFromInt64 r.unbacked) (unbackedList r.unbackedClaims)
       (match r.contextTokens ((some t) (if (= t 0) "" (str " :contextTokens " (stringFromInt64 t)))) ((none) ""))
       (match r.turns ((some t) (str " :turns " (stringFromInt64 t))) ((none) ""))
       (if (listEmpty? r.gates)
         ""
         (str " :gates (" (stringJoin (map (fn [g] (str "(:cmd \"" (c/escapeAsn (gateCmd g)) "\" " (ctx/gateOutcome g) ")")) r.gates) " ") ")"))
       (match (nonEmpty r.escalate) ((some e) (str " :escalate (" e ")")) ((none) ""))
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
       (match (nonEmpty r.error) ((some e) (str " :error " e)) ((none) ""))
       (if (listEmpty? r.gatePreflight) "" (str " :gatePreflight (" (go/formatGatePreflight r.gatePreflight) ")"))
       (if r.parseDefect
         (str " :turn " (stringFromInt64 (match r.parseDefectTurn ((some t) (if (= t 0) 1 t)) ((none) 1))) " :parse-defect true")
         "")
       (match r.findings ((some fs) (str " :findings (" (stringJoin (keptFindings fs) " ") ")")) ((none) ""))
       (match r.queueWaitSec ((some q) (str " :queueWaitSec " (stringFromFloat64 q))) ((none) ""))
       (match r.execSec ((some e) (str " :execSec " (stringFromFloat64 e))) ((none) ""))
       (match r.usage
         ((some u) (str " :usage (:input " (stringFromInt64 u.input) " :cached " (stringFromInt64 u.cached)
                        " :output " (stringFromInt64 u.output) ")"))
         ((none) ""))
       (match r.batching
         ((some b)
           (let [rates (rt/batchingRates b.turns b.ops b.single)]
             (str " :batching (:opsPerTurn " (stringFromFloat64 (pairFirst rates)) " :singleOpShare " (stringFromFloat64 (pairSecond rates))
                  " :opTurns " (stringFromInt64 b.turns) ")")))
         ((none) ""))
       (match r.plan ((some p) (pl/planField p)) ((none) ""))
       (if (listEmpty? r.vacuousGates) "" (str " :vacuousGates (" (stringJoin (map (fn [g] (str "\"" (c/escapeAsn g) "\"")) r.vacuousGates) " ") ")"))
       (match r.specCheck
         ((some v) (cond
                     ((= v.verdict "skipped") " :specCheck (:verdict skipped :reason noGrader)")
                     ((= v.verdict "unavailable") (unavailableSpecText v.reasons))
                     (else (str " :specCheck (:verdict " v.verdict " :model \"" (c/escapeAsn v.model) "\" :reasons ("
                        (stringJoin (map (fn [x] (str "\"" (c/escapeAsn x) "\"")) v.reasons) " ") "))"))))
         ((none) ""))
       ")")


fn blockEnd source: String from: Int64 -> Int64
  (let [tail (c/sliceOf source from (stringLength source))
        ends (map (fn [o] (optionOr o 0)) (filter (fn [o] (some? o)) (map (fn [m] (stringIndexOf tail m)) (list "\nfn " "\n(schema " "\nenum "))))]
    (match (listMin ends)
      ((some e) (+ from e))
      ((none) (stringLength source))))

fn fnBody source: String name: String -> (Option String)
  (let [src (str "\n" source)]
    (match (stringIndexOf src (str "\nfn " name " "))
      ((none) none)
      ((some at) (some (c/sliceOf src (+ at 1) (blockEnd src (+ at 1)))))))

fn literalsIn s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse acc))
    ((= (bytesGet bs i) 59) (literalsIn s bs n (lineEnd bs n i) acc))
    ((= (bytesGet bs i) 34)
      (match (stringTokenEnd bs n (+ i 1) false)
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
  (match (fnBody source "formatReceipt")
    ((none) (err "asl/agentLoop/main.asl has no fn formatReceipt"))
    ((some body)
      (let [bs (stringToBytes body)
            keys (fold (fn [acc lit] (listAppend acc (keysOf lit))) (list) (literalsIn body bs (bytesLength bs) 0 (list)))]
        (match (afterHead keys)
          ((none) (err "formatReceipt writes no (:agentReceipt form"))
          ((some fields) (ok (dedupe (filter (fn [k] (not (listContains? (list "cmd" "exit" "op" "blocked") k))) fields) (list))))))))

fn ! receiptFieldNames rootDir: String -> (Result (List String) String)
  (match (fileReadString (pyJoin rootDir "asl/agentLoop/main.asl"))
    ((err e) (err e))
    ((ok source) (receiptFieldsIn source)))


fn infoText info: j/Json key: String -> String
  (match (j/jsonGet info key) ((some v) (pv/pyStr v)) ((none) ""))

fn infoItems v: (Option j/Json) -> (List j/Json)
  (match v ((some x) (match x ((j/jarr xs) xs) (_ (list)))) ((none) (list)))

fn infoFlag info: j/Json key: String -> String
  (match (j/jsonGet info key)
    ((some v) (if (truthy v) (str " :" key " \"" (pv/pyStr v) "\"") ""))
    ((none) ""))

fn formatDryRun info: j/Json systemPrompt: String owns: (List String) -> String
  (str "(:dryRunReceipt :vendor \"" (infoText info "vendor") "\" :owns (" (quoteEach owns) ")"
       " :cwd \"" (infoText info "cwd") "\""
       (match (j/jsonGet info "request")
         ((some req)
           (str " :request (:url \"" (infoText req "url") "\" :model \"" (infoText req "model") "\" :agent \"" (infoText req "agent") "\""
                " :addDirs (" (stringJoin (map (fn [d] (str "\"" (pv/pyStr d) "\"")) (infoItems (j/jsonGet req "addDirs"))) " ") ")"
                " :workspace \"" (infoText req "workspace") "\" :timeout " (infoText req "timeout")
                " :queue_timeout " (infoText req "queue_timeout") ")"
                " :note \"gateway replaces --agent aslLoop --print-timeout --output-format json\""))
         ((none)
           (match (j/jsonGet info "argv")
             ((some a) (if (truthy a) (str " :argv \"" (c/escapeAsn (stringJoin (map pv/pyStr (infoItems (some a))) " ")) "\"") ""))
             ((none) ""))))
       (infoFlag info "agentFile") (infoFlag info "agentFrontmatter") (infoFlag info "modelInstructionsFile")
       (match (j/jsonGet info "stdinRedirected") ((some v) (if (truthy v) " :stdinRedirected true" "")) ((none) ""))
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
  (match o ((some v) (and (>= v lo) (<= v hi))) ((none) false))

fn rstripSlash s: String -> String
  (if (and (stringEndsWith? s "/") (> (stringLength s) 0)) (rstripSlash (c/sliceOf s 0 (- (stringLength s) 1))) s)

fn ! expandUser p: String -> String
  (if (not (stringStartsWith? p "~"))
    p
    (let [cut (match (stringIndexOf (c/sliceOf p 1 (stringLength p)) "/") ((some off) (+ off 1)) ((none) (stringLength p)))]
      (if (!= cut 1)
        p
        (match (envGet "HOME")
          ((some home) (let [r (str (rstripSlash home) (c/sliceOf p cut (stringLength p)))] (if (stringEmpty? r) "/" r)))
          ((none) p)))))

fn supportedBackends -> (List String)
  (list "agy" "codex" "claude")

fn defaultModel backend: String -> String
  (if (= backend "agy") "gemini-3.8-flash" backend)

fn optText v: (Option j/Json) -> (Option String)
  (match v ((some x) (some (textValue x))) ((none) none))

fn modeOf hint: (Option String) -> (Option String)
  (match hint ((some m) (if (or (= m "auto") (= m "")) none (some m))) ((none) none))

fn hexByte b: Int64 -> String
  (str (c/sliceOf "0123456789abcdef" (/ b 16) (+ (/ b 16) 1)) (c/sliceOf "0123456789abcdef" (mod b 16) (+ (mod b 16) 1)))

fn ! newSessionId -> (Result String String)
  (match (fileReadRange "/dev/urandom" 0 8)
    ((err e) (err e))
    ((ok bs)
      (if (= (bytesLength bs) 8)
        (ok (stringJoin (map (fn [i] (hexByte (bytesGet bs i))) (list 0 1 2 3 4 5 6 7)) ""))
        (err "/dev/urandom gave fewer than 8 bytes"))))

; (:m :ref LEON-REPEAT-OP :do "a turn whose op receipts include a rejected, error or failed one and that persisted nothing is a failed turn; the same reply failing on failureCap consecutive turns escalates instead of repeating to the wall budget")
fn withCounts st: ls/LoopState counts: (Map String Int64) -> ls/LoopState
  (with st :failureCounts counts)

fn repeatFailureCap -> Int64
  3

fn failedReceipts? receipts: String -> Bool
  (or (stringContains? receipts ":status :rejected") (or (stringContains? receipts ":status :error") (stringContains? receipts ":status :failed")))

; (:m :ref PER-TURN-GATE :do "a turn whose ops all only read, or only write and edit without persisting a change (an edit whose :old is not in the file), changes nothing the gates see, so it reuses the last verdict instead of rerunning the task gates (a suite gate cost minutes per read turn; one calibration run repeated a failing edit 24 times and gated each); a turn that wrote, any other op, an unnamed form or (:done) still runs them")
fn readOnlyOps -> (List String)
  (list "read" "query" "outline" "tree" "diff" "tools" "help" "gitDiff" "gitLog" "gitShow" "note" "observe")

fn unchangedTurn? names: (List String) wrote: Bool -> Bool
  (and (not wrote) (and (not (listEmpty? names)) (listAll? (fn [n] (listContains? (listAppend (readOnlyOps) (list "write" "edit")) n)) names)))

fn liveOpName op: (List (Pair String c/KvVal)) -> String
  (match (c/dictGet op "op")
    ((some value) (match value ((c/kvStr name) name) (_ "")))
    ((none) ""))

fn liveOpPath op: (List (Pair String c/KvVal)) -> String
  (match (c/dictGet op "file")
    ((some value) (match value ((c/kvStr path) path) (_ "")))
    ((none) (match (c/dictGet op "path") ((some value) (match value ((c/kvStr path) path) (_ ""))) ((none) ""))))

fn liveConfirmReceipt out: ex/ExecOut -> (Option j/Json)
  (let [rec out.rec]
    (match (ex/recGet rec "needsConfirm")
      ((some value) (match value ((ex/vBool requested) (if requested (some (ls/execRecJson rec)) none)) (_ none)))
      ((none) none)))

fn liveConfirmStr row: j/Json key: String fallback: String -> String
  (match (j/jsonGet row key) ((some v) (match v ((j/jstr s) s) (_ fallback))) ((none) fallback))

fn liveConfirmItems value: (Option j/Json) -> (List NeedsConfirm)
  (match value
    ((some raw) (match raw
      ((j/jarr items) (map (fn [item] (NeedsConfirm :op (liveConfirmStr item "op" "unknown") :error (liveConfirmStr item "error" ""))) items))
      (_ (list))))
    ((none) (list)))

fn ! liveAdvisor provider: pv/Provider sys: String msg: String -> (Result (Option String) String)
  (match (pv/advise! provider sys msg)
    ((none) (err "provider has no advisor channel"))
    ((some turn)
      (match turn.reply
        ((err e) (err (pv/errorMessage e)))
        ((ok reply) (ok reply)))))

fn servedModel meta: pv/TurnMeta -> (Option String)
  (match meta.served
    ((some fields) (optionMap pairSecond (listHead (filter (fn [p] (= (pairFirst p) "model")) fields))))
    ((none) none))

; (:m :ref LEON-CAPS :do "the grader call is its own gateway request for the configured intent and profile; its served model is journaled as (:graderServed ...) so the spec check can compare it with the writer's")
fn ! liveGrader provider: pv/Provider intent: String profile: String path: String sys: String msg: String -> (Result (Option String) String)
  (let [turn (pv/grade! provider intent profile sys msg)
        _ (match (servedModel turn.meta)
            ((some model) (ok? (fileAppend path (str "(:graderServed :model \"" (c/escapeAsn model) "\")\n"))))
            ((none) true))]
    (match turn.reply
      ((err e) (err (pv/errorMessage e)))
      ((ok reply) (ok reply))))

fn ! liveReviewer provider: pv/Provider sys: String msg: String -> (Result (Option String) String)
  (let [turn (pv/review! provider sys msg)]
    (match turn.reply
      ((err e) (err (pv/errorMessage e)))
        ((ok reply) (ok reply))))

fn liveReviewerAvailable? provider: pv/Provider -> Bool
  (match provider
    ((pv/vendorProvider _) true)
    ((pv/scriptFixtureProvider _ fixture _) (some? fixture.reviewer))
    (_ false))

fn liveHookOk? result: (Result (Option String) String) -> Bool
  (match result ((err _) false) ((ok _) true))

fn liveReviewAccepts? result: (Result (Option String) String) -> Bool
  (match result
    ((err _) false)
    ((ok reply)
      (match reply
        ((none) false)
        ((some text)
          (match (ctx/parseSpecVerdict (some text))
            ((some verdict) (pairFirst verdict))
            ((none) false))))))

fn ! appendLiveHook! path: String turn: Int64 name: String result: (Result (Option String) String) -> Bool
  (match result
    ((err e) (ok? (fileAppend path (str "(:liveHook :turn " (stringFromInt64 turn) " :name \"" name
      "\" :error \"" (c/escapeAsn e) "\")\n"))))
    ((ok text)
      (match text
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
  (match value
    ((some raw)
      (some (Usage
        :input (optionOr (intValue (optionOr (j/jsonGet raw "inputTokens") (j/jint 0))) 0)
        :cached (optionOr (intValue (optionOr (j/jsonGet raw "cachedTokens") (j/jint 0))) 0)
        :output (optionOr (intValue (optionOr (j/jsonGet raw "outputTokens") (j/jint 0))) 0))))
    ((none) none))

fn providerUsageInt fields: (List (Pair String j/Json)) key: String -> Int64
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) fields))
    ((some p) (optionOr (intValue (pairSecond p)) 0))
    ((none) 0))

fn providerUsageLine meta: pv/TurnMeta -> (Option String)
  (match meta.usage
    ((some fields) (some (str "(:liveUsage :input " (stringFromInt64 (providerUsageInt fields "inputTokens"))
      " :cached " (stringFromInt64 (providerUsageInt fields "cachedTokens"))
      " :output " (stringFromInt64 (providerUsageInt fields "outputTokens")) ")")))
    ((none) none))

fn liveUsageInt line: String key: String -> Int64
  (match (listHead (filter (fn [field] (= (pairFirst field) key)) (c/parseKv line)))
    ((some field) (match (pairSecond field)
      ((c/kvInt digits) (optionOr (stringToInt64 digits) 0))
      ((c/kvStr _) 0)))
    ((none) 0))

fn ! liveJournalUsage! rootDir: String journal: (Option String) -> (Option Usage)
  (match journal
    ((some journalPath)
      (let [path (pyJoin rootDir journalPath)]
      (match (fileReadString path)
        ((err _) none)
        ((ok text)
          (let [lines (filter (fn [line] (stringStartsWith? line "(:liveUsage ")) (stringSplit text "\n"))]
            (match (listLast lines)
              ((some line)
                (some (Usage
                  :input (liveUsageInt line "input")
                  :cached (liveUsageInt line "cached")
                  :output (liveUsageInt line "output"))))
              ((none) none)))))))
    ((none) none))

fn livePlan value: (Option j/Json) -> (Option pl/PlanSummary)
  (match value
    ((some raw)
      (some (pl/summaryOf
        (optionOr (intValue (optionOr (j/jsonGet raw "steps") (j/jint 0))) 0)
        (optionOr (intValue (optionOr (j/jsonGet raw "done") (j/jint 0))) 0)
        (optionOr (intValue (optionOr (j/jsonGet raw "dropped") (j/jint 0))) 0)
        (optionOr (intValue (optionOr (j/jsonGet raw "revisions") (j/jint 0))) 0))))
    ((none) none))

fn livePlanJson forms: (List String) -> (Option j/Json)
  (match (listHead (filter (fn [form] (stringStartsWith? (stringTrim form) "(:plan")) forms))
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

; (:m :ref LEON-WALLBUDGET-ORPHAN :do "seconds left of the run's :wallBudget; a model call and a gate never get longer than that, so the run ends near its budget even inside a slow call")
fn wallLeft wallBudget: (Option Int64) elapsed: Float64 -> (Option Int64)
  (match wallBudget
    ((some w) (if (> w 0) (some (max 1 (- w (optionOr (float64ToInt64 elapsed) 0)))) none))
    ((none) none))

; (:m :ref WALL-GRACEFUL :do "documented defaults of the two wall settings in .asl.config.asn :agentLoop: :wallReserveSec is held back from :wallBudget for the finish (hand-back, grader, commit) and the dispatch kill margin, :wallGateMinSec is the least wall a gate run may start with; a run that cannot start its gate ends with :stop wallBudget instead of being killed")
fn defaultWallReserveSec -> Int64
  120

fn defaultWallGateMinSec -> Int64
  60

fn wallSetting cfgText: String key: String fallback: Int64 -> Int64
  (match (ac/agentLoopValue cfgText key)
    ((some v) (optionOr (ac/positiveInt v) fallback))
    ((none) fallback))

fn reservedWall wallBudget: (Option Int64) reserve: Int64 -> (Option Int64)
  (match wallBudget
    ((some w) (if (> w 0) (some (max 1 (- w reserve))) wallBudget))
    ((none) none))

fn wallTooShort? left: (Option Int64) need: Int64 -> Bool
  (match left ((some l) (< l need)) ((none) false))

fn wallCapped base: Int64 left: (Option Int64) -> Int64
  (match left ((some l) (max 1 (min base l))) ((none) base))

fn wallCappedProvider p: pv/Provider left: (Option Int64) -> pv/Provider
  (match left ((some l) (pv/capTimeouts p l)) ((none) p))

; (:m :ref LEONATTR :do "the provider a live turn calls: wall-capped, and carrying the prefill only when the attractor set one, so an off turn sends the request as before")
; (:m :ref NATIVE-TOOLS-DEFAULT :do "the tool schemas a session offers on its main turns: one per local op shape for ops, none for off or false, and the single step(form) tool otherwise, so absent means step (PROTO-STUDY: 24/27 sessions green across 9 aliases, beam 0/9 -> 7/9, no loss on any alias that worked); a route that rejects tools is marked :nativeTools false in its gateway row, never here; advisor and grader calls never carry them")
fn sessionTools v: String -> (List j/Json)
  (cond
    ((= v "ops") (nt/toolSpecs (map pairSecond (filter (fn [p] (not (listContains? (list "diff" "flush" "discard") (pairFirst p)))) (ex/opShapes)))))
    ((or (= v "off") (= v "false")) (list))
    (else (list (nt/stepToolSpec))))

; (:m :ref L0-PREFIX :do "the :prefix value is a comma list: section ids or groups the system prompt drops, and focus, which ends each turn with the goal, gate and next op form; empty is the full prompt and no tail")
fn prefixTokens -> (List String)
  (list "rules" "protocol" "orient" "authority" "evidence" "reply" "scope" "abstain" "breaker" "task" "work" "memory" "language" "git"
        "attractors" "clientRules" "glossary" "ops" "opsLean" "needsConfirm" "batch" "pool" "aslCard" "focus")

fn prefixList v: String -> (List String)
  (filter (fn [t] (not (stringEmpty? t))) (map stringTrim (stringSplit v ",")))

fn validPrefix? v: String -> Bool
  (listEmpty? (filter (fn [t] (not (listContains? (prefixTokens) t))) (prefixList v)))

fn prefixDrop v: String -> (List String)
  (filter (fn [t] (not (= t "focus"))) (prefixList v))

fn focusTail v: String task: String gates: (List String) persisted: Bool -> String
  (if (not (listContains? (prefixList v) "focus")) ""
    (str "\n\n(:focus :goal \"" (c/escapeAsn (if (> (stringLength task) 400) (optionOr (stringSlice task 0 400) task) task))
      "\" :gate \"" (c/escapeAsn (optionOr (listHead gates) "")) "\" :next "
      (if persisted "(:step :op \"gate\")" "(:step :op \"read\"|\"edit\"|\"write\" ...)") ")"))

fn attractorProvider p: pv/Provider prefill: String left: (Option Int64) -> pv/Provider
  (if (stringEmpty? prefill) (wallCappedProvider p left) (pv/withPrefill (wallCappedProvider p left) prefill))

fn ! liveProviderRetry! provider: pv/Provider call: (fn [pv/Provider Int64] -> pv/Turn) wallBudget: (Option Int64) sleep: (fn [Int64] -> Bool) now: (fn [] -> Float64) -> (Pair pv/Turn Int64)
  (rt/retryTurn! provider call 3 (list 1 2 4) wallBudget sleep now)

fn liveWriteStatus out: ex/ExecOut -> Bool
  (match (ex/recGet out.rec "status")
    ((some value) (match value ((ex/vStr status) (= status "ok")) (_ false)))
    ((none) false))

fn liveUnwritten written: jr/Written target: String -> jr/Written
  (jr/Written :root written.root
    :files (match written.files
      ((some files) (some (filter (fn [entry] (!= (pairFirst entry) target)) files)))
      ((none) none))
    :startHead written.startHead)

fn liveOwnsRejected? out: ex/ExecOut -> Bool
  (match (ex/recGet out.rec "error")
    ((some value) (match value ((ex/vStr code) (= code "ERR_OWNS")) (_ false)))
    ((none) false))

fn ! liveOwnsField! rootDir: String journal: (Option String) -> String
  (match journal
    ((some journalPath)
      (let [path (pyJoin rootDir journalPath)]
      (match (fileReadString path)
        ((err _) "")
        ((ok text)
          (let [rows (filter (fn [line] (stringStartsWith? line "(:liveOwnsRejected ")) (stringSplit text "\n"))
                forms (map (fn [line]
                  (let [start (optionOr (stringIndexOf line "(:turn") 0)]
                    (c/sliceOf line start (- (stringLength line) 1)))) rows)]
            (if (listEmpty? forms) "" (str " :ownsRejected (" (stringJoin forms " ") ")")))))))
    ((none) ""))

; (:m :ref LEON-REMOTE-TOOLS :do "a task-level :remote UNIT sets :remote on every remote-capable step that names none, so the whole run edits and tests in that VPS worktree")
fn withRemote op: (List (Pair String c/KvVal)) unit: String -> (List (Pair String c/KvVal))
  (if (or (stringEmpty? unit) (listAny? (fn [p] (= (pairFirst p) "remote")) op)) op (listAppend op (list (pair "remote" (c/kvStr unit)))))

fn ! liveExecOps! ops: (List (List (Pair String c/KvVal))) ra: RunArgs rootDir: String repoRoot: String sid: String journal: String env: ex/ExecEnv run: rl/LoopRun -> (Pair rl/LoopRun (Pair String Bool))
  (if (listEmpty? ops)
    (pair run (pair "" false))
    (let [op (c/firstOf ops)
          opName (liveOpName op)
          target (liveOpPath op)
          mutating (listContains? (list "write" "edit" "delete") opName)
          ; (:m :ref LEON-WRITE-NOT-COUNTED-20261018 :do "a session with no :owns writes anywhere inside :root, but this 'owned' flag used to feed ra.owns raw into checkOwns: checkOwns on an empty list is false by definition, never true, so a real, accepted, on-disk write with no :owns declared never counted as owned, writesPersisted stayed false forever, and the run escalated nothing written by turn 20 even though the write succeeded and read back correctly. c/effectiveOwns (LEON-OWNS-ONE-RULE-20261018) is the single normalization exec.asl's writeCheck now shares, so the two owns checks can no longer drift out of sync")
          ; (:m :ref LEONDELETE :do "a delete whose path a later write in the same reply targets is superseded and not run: the write overwrites the file anyway, and a refused write (ERR_USE_RAW, ERR_OWNS) after an executed delete left the pre-existing owned file deleted")
          superseded (and (= opName "delete") (and (not (stringEmpty? target))
                       (listAny? (fn [o] (and (= (liveOpName o) "write") (= (liveOpPath o) target))) (c/restOf ops))))
          owned (and mutating (and (not superseded) (and (not (stringEmpty? target)) (c/checkOwns target (c/effectiveOwns ra.owns) rootDir))))
          before (if owned (jr/snapshotBeforeWrite run.written target) (ok run.written))
          runOp (fn [form root] (let [r (ao/runAsl repoRoot form root ra.timeout none "subprocess")]
                                  (tx/aslRun (ao/runExit r) (ao/runStdout r) (ao/runStderr r))))
          ; (:m :ref LEON-POOL-ASK-OP :do "(:ask) and (:answer) are pool ops: poolOps runs them and exec never sees them")
          pooled (po/poolOp? op)
          out (if superseded
            (ex/ExecOut :rec (list (pair "id" (ex/vStr sid)) (pair "op" (ex/vStr "delete")) (pair "status" (ex/vStr "ok")) (pair "file" (ex/vStr target))
                (pair "message" (ex/vStr "not deleted: a later write in this reply replaces the file"))) :procs run.procs)
            (if pooled (ex/ExecOut :rec (list) :procs run.procs) (match before
            ((err e) (ex/ExecOut :rec (list (pair "id" (ex/vStr sid)) (pair "op" (ex/vStr opName))
                (pair "status" (ex/vStr "rejected")) (pair "error" (ex/vStr "ERR_JOURNAL"))
                (pair "message" (ex/vStr e))) :procs run.procs))
            ((ok written)
              (ex/execOp! (withRemote op ra.remote) env run.procs (fn [] (resultOr (newSessionId) sid))
                (fn [path] (listContains? (rl/writtenPaths written) path))
                (fn [path patch mode] (listContains? (rl/writtenPaths written) path)) runOp)))))
          receipt (if pooled (po/poolOpReceipt! ra.pool op) (ex/formatOpReceipt out.rec env.readCap))
          _ownsLogged (if (liveOwnsRejected? out)
            (ok? (fileAppend journal (str "(:liveOwnsRejected (:turn " (stringFromInt64 run.state.turn)
              " :op \"" (c/escapeAsn opName) "\" :file \"" (c/escapeAsn target) "\" :error ERR_OWNS))\n")))
            true)
          wrote (and owned (and (listContains? (list "write" "edit") opName) (liveWriteStatus out)))
          snapWritten (match before
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
          nextRunRejected (match rejection
            ((some item) (let [state nextRun.state
              updated (rl/withOwnsRejections state (listAppend state.ownsRejections (list item)))]
              (rl/withState nextRun updated)))
            ((none) nextRun))
          nextRunConfirm (match (liveConfirmReceipt out)
            ((some confirm) (rl/withState nextRunRejected
              (rl/withFindings nextRunRejected.state nextRunRejected.state.findingsList
                (listAppend nextRunRejected.state.needsConfirmList (list confirm)))))
            ((none) nextRunRejected))
          rest (liveExecOps! (c/restOf ops) ra rootDir repoRoot sid journal env nextRunConfirm)]
      (pair (pairFirst rest)
        (pair (str receipt (if (stringEmpty? (pairFirst (pairSecond rest))) "" (str "\n" (pairFirst (pairSecond rest)))))
              (or wrote (pairSecond (pairSecond rest)))))))

fn liveGateStr row: (List (Pair String go/RVal)) key: String fallback: String -> String
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (match (pairSecond p) ((go/rStr v) v) (_ fallback)))
    ((none) fallback))

fn liveGateInt row: (List (Pair String go/RVal)) key: String fallback: Int64 -> Int64
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (match (pairSecond p) ((go/rInt v) v) (_ fallback)))
    ((none) fallback))

fn liveGateBool row: (List (Pair String go/RVal)) key: String -> Bool
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (match (pairSecond p) ((go/rBool v) v) (_ false)))
    ((none) false))

fn liveGateResult row: (List (Pair String go/RVal)) -> g/GateResult
  (g/makeGateResult (liveGateStr row "cmd" "") (liveGateInt row "exit" 1)
    (liveGateStr row "stdout" "") (liveGateStr row "stderr" "") (liveGateBool row "timeout") (liveGateInt row "seconds" 0))

fn liveLastGateMap gates: (List g/GateResult) old: (Map String j/Json) -> (Map String j/Json)
  (fold (fn [acc gate] (mapSet acc (g/gateCmd gate) (ls/gateJson gate))) old gates)

fn ! runLiveGates! gates: (List String) rootDir: String timeout: Int64 parent: (Option Int64) -> (List g/GateResult)
  (map liveGateResult (go/runGatesWatched! (map (fn [p] (pair (stringFromInt64 (+ (pairFirst p) 1)) (pairSecond p))) (enumerate gates)) rootDir timeout none parent))

; (:m :ref LEON-ORPHAN-PARENT :do "the calling CLI passes its pid as :parentPid; once that process is gone nobody reads this run, so Leon ends at the next turn boundary, and a gate it waits on is killed with its group")
fn ! parentGone? parent: (Option Int64) -> Bool
  (match parent
    ((some pid) (and (> pid 0) (not (resultOr (procAlive? pid) true))))
    ((none) false))

; (:m :ref LEON-CONTEXT-RESEND-20261017 :do "a deterministic gate-verdict summary for the turn's receipt line; feeds the aged-out-turn summary in ctx/renderTranscriptBounded instead of that turn's raw model text")
fn liveGateSummary gates: (List g/GateResult) -> String
  (if (listEmpty? gates)
    ""
    (let [total (listLength gates)
          green (listLength (filter (fn [gt] (= (g/gateExit gt) 0)) gates))]
      (if (= green total)
        (str (stringFromInt64 green) "/" (stringFromInt64 total) " green")
        (str (stringFromInt64 green) "/" (stringFromInt64 total) " green, red: "
          (c/joinSep (map g/gateCmd (filter (fn [gt] (!= (g/gateExit gt) 0)) gates)) "; ")))))

fn liveDoneOps? ops: (List (List (Pair String c/KvVal))) -> Bool
  (listAny? (fn [op] (match (c/dictGet op "type") ((some v) (match v ((c/kvStr t) (= t "done")) (_ false))) ((none) false))) ops)

fn liveIntentDeliver ops: (List (List (Pair String c/KvVal))) current: (Option String) -> (Option String)
  (if (listEmpty? ops)
    current
    (let [op (c/firstOf ops)
          next (if (= (liveOpName op) "intent")
            (let [rec (ex/intentReceipt op "intent")
                  okStatus (match (ex/recGet rec "status") ((some v) (match v ((ex/vStr s) (= s "ok")) (_ false))) ((none) false))]
              (if okStatus
                (match (ex/recGet rec "deliver") ((some v) (match v ((ex/vStr d) (some d)) (_ current))) ((none) current))
                current))
            current)]
      (liveIntentDeliver (c/restOf ops) next)))

fn liveCommitMessage ops: (List (List (Pair String c/KvVal))) -> (Option String)
  (if (listEmpty? ops)
    none
    (let [op (c/firstOf ops)
          done (match (c/dictGet op "type") ((some v) (match v ((c/kvStr t) (= t "done")) (_ false))) ((none) false))]
      (if done
        (let [form (match (c/dictGet op "form") ((some v) (match v ((c/kvStr text) text) (_ ""))) ((none) ""))
              fields (c/parseKv form)]
          (match (c/dictGet fields "commit") ((some v) (match v ((c/kvStr message) (some message)) (_ none))) ((none) none)))
        (liveCommitMessage (c/restOf ops)))))

fn liveGateResultsGreen? gates: (List g/GateResult) -> Bool
  (cond
    ((listEmpty? gates) true)
    ((= (g/gateExit (c/firstOf gates)) 0) (liveGateResultsGreen? (c/restOf gates)))
    (else false))

; (:m :ref LEON-ORPHAN-RESIDUE :do "a model call blocks this thread, so while it runs a forked sidecar polls the parent pid; once the parent is gone it logs parentGone, kills every descendant of this run (the vendor CLI or curl, which ends the call), and after a short grace kills the run itself, so a dead parent ends a call within a bound instead of at the next turn boundary")
fn ! parentIsGone? pid: Int64 -> Bool
  (and (> pid 0) (not (resultOr (procAlive? pid) true)))

fn ! killBelow! leon: Int64 keep: Int64 -> Int64
  (fold (fn [(n Int64) (p Int64)] -> Int64 (if (= p keep) n (match (procKill p "SIGKILL") ((ok _) (+ n 1)) ((err _) n))))
        0 (fr/descendantsOf (fr/psSnapshot) leon))

fn ! watchParent! pid: Int64 leon: Int64 path: String turn: Int64 -> Int64
  (cond
    ((not (resultOr (procAlive? leon) false)) 0)
    ((not (parentIsGone? pid)) (do (sleepMs 250) (watchParent! pid leon path turn)))
    (else
      (let [_ (fileAppend path (str "(:turn " (stringFromInt64 turn) " :signal :parentGone :reason \"parent pid " (stringFromInt64 pid) " is gone during the model call\")\n"))
            _ (killBelow! leon (procSelf))
            _ (sleepMs 2000)]
        (if (resultOr (procAlive? leon) false) (do (procKill leon "SIGKILL") 0) 0))))

fn ! parentWatch! parent: (Option Int64) path: String turn: Int64 spanS: Int64 -> (Option fr/Forked)
  (match parent
    ((some pid)
      (if (> pid 0)
        (let [leon (procSelf)]
          (match (fr/forkLimited! "/dev/null" (fr/limits spanS 8) (fn [] -> Int64 (watchParent! pid leon path turn)))
            ((ok f) (some f))
            ((err _) none)))
        none))
    ((none) none))

fn ! parentUnwatch! watcher: (Option fr/Forked) -> Bool
  (match watcher
    ((some f) (do (fr/forkKill! f "done") true))
    ((none) true))

; (:m :ref CODE-WIRE-20261028 :do "a code-intent run whose gateway config declares a :codeRoute id code drives the gateway codeRoute step machine for its model call: the writer alias is asked with the turn's prompt, Leon's own task gates judge the answer, the raw gate output is fed back, then one escalation; no declared route, or an intent other than code, keeps the plain provider call")
(schema RouteSetup
  (:f row gc/CodeRoute)
  (:f penv pv/ProviderEnv))

fn ! codeRouteSetup! intent: (Option String) cfgText: String repoRoot: String penv: pv/ProviderEnv -> (Option RouteSetup)
  (if (!= (optionOr intent "") "code")
    none
    (let [path (optionOr (ac/agentLoopValue cfgText ":gatewayConfig") penv.gatewayConfig)]
      (match (fileReadString path)
        ((err _) none)
        ((ok text)
          (match (gc/gatewayCodeRoute! text "code" (str repoRoot "/asl/grammar/calibration.asn"))
            ((ok row) (some (RouteSetup :row row :penv penv)))
            ((err _) none))))))

fn routeStatus message: String -> Int64
  (match (stringIndexOf message "HTTP error ")
    ((none) 500)
    ((some at) (optionOr (stringToInt64 (c/sliceOf message (+ at 11) (min (stringLength message) (+ at 14)))) 500)))

fn routeReplyOf reply: (Result (Option String) pv/ProviderError) -> cr/RouteReply
  (match reply
    ((ok o) (match o ((some t) (cr/RouteReply :status 200 :text t)) ((none) (cr/RouteReply :status 204 :text ""))))
    ((err e) (cr/RouteReply :status (routeStatus (pv/errorMessage e)) :text (pv/errorMessage e))))

fn ! routeCall! ra: RunArgs rs: RouteSetup rootDir: String sid: String prov: pv/Provider alias: String prompt: String timeoutSec: Float64 system: String -> pv/Turn
  (if (or (stringStartsWith? ra.backend "script/") (stringStartsWith? ra.backend "replay/"))
    (pv/nextTurn! prov system prompt)
    (match (pv/makeProvider! ra.backend "auto" rootDir alias (if (> timeoutSec 0.0) (optionOr (float64ToInt64 timeoutSec) ra.timeout) ra.timeout) sid ra.queueTimeout ra.timeoutSet rs.penv "code")
      ((err e) (pv/Turn :provider prov :reply (err e) :meta (pv/emptyMeta)))
      ((ok p) (let [t (pv/nextTurn! p system prompt)] (pv/Turn :provider prov :reply t.reply :meta t.meta)))))

; (:m :ref CODE-WIRE-20261028 :do "usage of the route's calls is summed per key so the turn books the whole route, not the last call")
fn routeUsageAdd acc: (List (Pair String j/Json)) meta: pv/TurnMeta -> (List (Pair String j/Json))
  (match meta.usage
    ((none) acc)
    ((some fields)
      (map (fn [key] (pair key (j/jint (+ (providerUsageInt acc key) (providerUsageInt fields key)))))
           (list "inputTokens" "cachedTokens" "outputTokens"))))

fn ! driveRoute! step: cr/RouteStep prov: pv/Provider usage: (List (Pair String j/Json)) ra: RunArgs rs: RouteSetup rootDir: String sid: String system: String gate: (fn [String] -> cr/GateVerdict) fuel: Int64 -> (Pair cr/RouteResult (Pair pv/Provider (List (Pair String j/Json))))
  (if (<= fuel 0)
    (pair (cr/RouteResult :passed false :stage "none" :text "" :error "route out of fuel" :calls 0 :trail (list)) (pair prov usage))
    (match step
      ((cr/routeDone r) (pair r (pair prov usage)))
      ((cr/routeAsk alias prompt t k)
        (let [turn (routeCall! ra rs rootDir sid prov alias prompt t system)]
          (driveRoute! (k (routeReplyOf turn.reply)) turn.provider (routeUsageAdd usage turn.meta) ra rs rootDir sid system gate (- fuel 1))))
      ((cr/routeGate text k) (driveRoute! (k (gate text)) prov usage ra rs rootDir sid system gate (- fuel 1)))))

; (:m :ref CODE-WIRE-20261028 :do "the gate judges an answer in a scratch copy of the run root: its ops and the task gates run there and the copy is removed, so the real tree is written once, by the turn that replays the final answer; the error is the failing gates' own cmd, exit, stdout and stderr verbatim")
fn ! routeVerdict! text: String ra: RunArgs rootDir: String repoRoot: String path: String mkEnv: (fn [String] -> ex/ExecEnv) run: rl/LoopRun left: (Option Int64) -> cr/GateVerdict
  (let [clean (tr/turnReply text (some ra.gates))
        ops clean.facts.ops
        defect (or (listEmpty? ops) (or (listEmpty? clean.facts.forms) (stringEmpty? (stringTrim clean.text))))]
    (if defect
      (cr/GateVerdict :passed false :error "the reply contained no actionable operations")
      (let [scratch (str (optionOr (envGet "TMPDIR") "/tmp") "/leonRoute_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))
            copied (go/scratchTree! rootDir scratch)]
        (match copied
          ((err e) (cr/GateVerdict :passed false :error (str "route scratch copy failed: " e)))
          ((ok kind)
            (let [ran (liveExecOps! ops ra scratch repoRoot run.session (str scratch "/.routeJournal") (mkEnv scratch) run)
                  gates (runLiveGates! ra.gates scratch (wallCapped ra.gateTimeout left) ra.parentPid)
                  red (filter (fn [gt] (!= (g/gateExit gt) 0)) gates)
                  removed (go/scratchDrop! rootDir scratch kind)]
              (cr/GateVerdict :passed (listEmpty? red)
                :error (c/joinSep (map (fn [gt] (str (g/gateCmd gt) " exit " (stringFromInt64 (g/gateExit gt)) "\n" (g/gateStdout gt) (g/gateStderr gt))) red) "\n"))))))))

fn ! routedCall! ra: RunArgs rs: RouteSetup rootDir: String path: String turn: Int64 sid: String system: String user: String prov: pv/Provider gate: (fn [String] -> cr/GateVerdict) -> (Pair pv/Turn Int64)
  (let [driven (driveRoute! (cr/codeRouteStart rs.row user) prov (list) ra rs rootDir sid system gate 64)
        r (pairFirst driven)
        p (pairFirst (pairSecond driven))
        usage (pairSecond (pairSecond driven))
        meta (pv/TurnMeta :timing none :usage (if (listEmpty? usage) none (some usage)) :served none :finish none :truncated false)
        _ (fileAppend path (str "(:codeRoute :turn " (stringFromInt64 turn) " :passed " (if r.passed "true" "false") " :stage \"" r.stage "\" :calls " (stringFromInt64 r.calls) " :trail (" (c/joinSep (map (fn [t] (str "\"" (c/escapeAsn t) "\"")) r.trail) " ") "))\n"))]
    (pair
      (if (and (not r.passed) (stringEmpty? r.text))
        (pv/Turn :provider p :reply (err (pv/providerError "ERR_VENDOR" r.error)) :meta meta)
        (pv/Turn :provider p :reply (ok (some r.text)) :meta meta))
      (max 0 (- r.calls 1))))

; (:m :ref SE3-POOL-DRIVER :do "the orphan stop of one turn, apart from liveBody! so a pool driver stops its sessions the same way: journal the signal, escalate with reason parentGone")
fn ! liveGone! ra: RunArgs path: String wrapped: rl/ProviderRun -> (Pair rl/ProviderRun ls/Step)
    (let [state wrapped.run.state
          pid (stringFromInt64 (optionOr ra.parentPid 0))
          _ (fileAppend path (str "(:turn " (stringFromInt64 state.turn) " :signal :parentGone :reason \"parent pid " pid " is gone\")\n"))
          next (rl/withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
                 state.allGateResults state.lastGates "escalated" (some "parentGone")
                 (some (str "(:escalate :reason \"parent pid " pid " is gone after " (stringFromInt64 state.turn) " turns\")")) state.runStarted)]
      (pair (rl/ProviderRun :run (rl/withState wrapped.run next) :provider wrapped.provider :history wrapped.history) (stop)))

fn ! liveBody! ra: RunArgs repoRoot: String rootDir: String path: String system: String env: ls/LoopEnv
    providerCall: (fn [pv/Provider String String] -> pv/Turn) wrapped: rl/ProviderRun -> (Pair rl/ProviderRun ls/Step)
  (if (parentGone? ra.parentPid)
    (liveGone! ra path wrapped)
    (liveTurn! ra repoRoot rootDir path system env providerCall wrapped))

; (:m :ref LEON-ECHO-GUARD :do "every user turn ends with one imperative line naming the next required form, so a weak model that continues the prompt text has an instruction to follow")
fn nextFormLine persisted: Bool -> String
  (if persisted
    "\n\nReply with ASN forms only; the next form is a (:step :op \"gate\") or the (:done)."
    "\n\nReply with ASN forms only; the next form is a (:step :op ...).")

; (:m :ref SE2-LIVETURN-SPLIT :do "what the first half of a turn hands the second: the system and user text and prefill the model call needs, the sent text the history records, the attractor card names the journal logs and whether the advisor hook was acceptable; liveTurn! composes liveAsk!, the blocking call and liveApply! so its behaviour is unchanged, and a pool runs the call between the two")
(schema LiveAsk
  (:f sysA String)
  (:f user String)
  (:f prefill String)
  (:f turnOwnSent String)
  (:f cardNames (List String))
  (:f advisorOk Bool))

fn ! liveAsk! ra: RunArgs repoRoot: String rootDir: String path: String system: String env: ls/LoopEnv wrapped: rl/ProviderRun -> LiveAsk
  (let [run wrapped.run
        state run.state
        turn state.turn
        transcript (ctx/renderTranscriptBounded wrapped.history (ctx/contextKeepTurnsFor! rootDir) (ctx/contextToolCapBytesFor! rootDir) (ctx/contextMaxOlderLinesFor! rootDir)
          (ctx/contextLatestCapBytes (optionOr state.contextTokens 24000)))
        advisorInvoked (= (optionOr ra.intent "") "reinforce")
        advisorResult (if advisorInvoked
          (env.advise (ctx/advisorSystem) (str "Task: " ra.task "\n\n" transcript))
          (ok none))
        advisorLogged (if advisorInvoked (appendLiveHook! path turn "advisor" advisorResult) true)
        advisorText (match advisorResult ((ok value) (optionOr value "")) ((err _) ""))
        turnsSoFar (max 0 (- turn 1))
        writeNudge (if (and (= (optionOr state.deliver "") "patch")
                        (and (not state.writesPersisted) (>= turnsSoFar (ctx/noWriteNudgeTurns))))
          (str "\n\n" (stringFromInt64 turnsSoFar) " turns and nothing written; the run stops at turn "
            (stringFromInt64 (ctx/noWriteTurns)) " without a write. Write now to "
            (c/joinSep ra.owns ", ") " -- stop re-reading and make the edit.")
          "")
        prefetched (rl/firstTurnPrefetch state)
        shapes (map pairSecond (ex/opShapes))
        sysA (at/attractorSystem ra.attractor shapes system)
        prefill (at/attractorPrefill ra.attractor)
        cards (at/attractorCards ra.attractor (gr/lastGot wrapped.history) run.lastDefect state.writesPersisted turnsSoFar)
        tail (at/attractorTail cards)
        expects (gr/rejectHints (gr/lastGot wrapped.history) (ex/opShapes))
        user (str tail "Task: " ra.task (if (stringEmpty? prefetched) "" (str "\n\n" prefetched)) (if (stringEmpty? transcript) "" (str "\n\n" transcript))
          (if (stringEmpty? expects) "" (str "\n\n" expects))
          (if (stringEmpty? advisorText) "" (str "\n\nAdvisor: " advisorText))
          (if run.lastDefect "\n\nThe prior reply contained no actionable operations; retry with a valid operation or terminal form." "")
          writeNudge
          (focusTail ra.prefix ra.task ra.gates state.writesPersisted)
          (nextFormLine state.writesPersisted))
        turnOwnSent (str "Task: " ra.task (if (stringEmpty? prefetched) "" (str "\n\n" prefetched))
          (if (stringEmpty? advisorText) "" (str "\n\nAdvisor: " advisorText))
          (if run.lastDefect "\n\nThe prior reply contained no actionable operations; retry with a valid operation or terminal form." "")
          writeNudge)
        _ (fileAppend path (str "(:turn " (stringFromInt64 turn) " :sent \"" (c/escapeAsn user) "\")\n"))]
    (LiveAsk :sysA sysA :user user :prefill prefill :turnOwnSent turnOwnSent :cardNames (map pairFirst cards) :advisorOk (liveHookOk? advisorResult)))

fn ! liveTurn! ra: RunArgs repoRoot: String rootDir: String path: String system: String env: ls/LoopEnv
    providerCall: (fn [pv/Provider String String] -> pv/Turn) wrapped: rl/ProviderRun -> (Pair rl/ProviderRun ls/Step)
  (let [ask (liveAsk! ra repoRoot rootDir path system env wrapped)
        run wrapped.run
        state run.state
        turn state.turn
        sysA ask.sysA
        user ask.user
        prefill ask.prefill
        watcher (parentWatch! ra.parentPid path turn (min 86400 (+ (+ ra.timeout ra.queueTimeout) 300)))
        routeEnvFor (fn [root] (ex/makeExecEnv root repoRoot (optionOr (modeOf ra.modeHint) "auto") ra.owns state.writesPersisted ra.base
          ra.gates (resultOr (tx/loadEffects! repoRoot) (list)) "" (list) (ctx/readPayloadChars (optionOr state.contextTokens 24000))
          ra.timeout none run.session none))
        routeLeft (wallLeft env.wallBudget (- (env.now) state.runStarted))
        retried (match ra.route
          ((some rs) (routedCall! ra rs rootDir path turn run.session sysA user wrapped.provider
            (fn [text] (routeVerdict! text ra rootDir repoRoot path routeEnvFor run routeLeft))))
          ((none) (liveProviderRetry! wrapped.provider
          (fn [p attempt] (providerCall (attractorProvider p prefill (wallLeft env.wallBudget (- (env.now) state.runStarted))) sysA user))
          (match env.wallBudget
            ((some w) (some (max 0 (- w (optionOr (float64ToInt64 (- (env.now) state.runStarted)) 0)))))
            ((none) none))
          env.sleep env.now)))
        _unwatched (parentUnwatch! watcher)
        _retryLogged (appendRetryLines! path turn (pairSecond retried))]
    (liveApply! ra repoRoot rootDir path env wrapped ask (pairFirst retried) (pairSecond retried)))

fn ! liveApply! ra: RunArgs repoRoot: String rootDir: String path: String env: ls/LoopEnv wrapped: rl/ProviderRun ask: LiveAsk response: pv/Turn retries: Int64 -> (Pair rl/ProviderRun ls/Step)
  (let [run wrapped.run
        state run.state
        turn state.turn
        prefill ask.prefill
        turnOwnSent ask.turnOwnSent
        shapes (map pairSecond (ex/opShapes))
        _usageLogged (match (providerUsageLine response.meta)
          ((some form) (ok? (fileAppend path (str form "\n")))) ((none) true))
        _servedLogged (match (servedModel response.meta)
          ((some model) (ok? (fileAppend path (str "(:served :turn " (stringFromInt64 turn) " :model \"" (c/escapeAsn model) "\")\n"))))
          ((none) true))]
    (match response.reply
      ((err e)
        (do
          (fileAppend path (str "(:turn " (stringFromInt64 turn) " :error :" (pv/errorCode e) " :message \"" (c/escapeAsn (pv/errorMessage e)) "\")\n"))
          (fileAppend path (str "(:err :turn " (stringFromInt64 turn) " :class :" (rt/errorClass (pv/errorCode e) (pv/errorMessage e))
            " :code :" (pv/errorCode e) " :retries " (stringFromInt64 retries) " :message \"" (c/escapeAsn (pv/errorMessage e)) "\")\n"))
          (let [nextState (rl/withHeadState state turn state.readStreak state.writesPersisted none
                    state.allGateResults state.lastGates "failed" (some "provider") none state.runStarted)
                nextRun (rl/withState run nextState)]
            (pair (rl/ProviderRun :run nextRun :provider response.provider :history wrapped.history) (stop)))))
      ((ok replyOpt)
        (match replyOpt
          ((none)
            (do
              (fileAppend path (str "(:turn " (stringFromInt64 turn) " :error :ERR_NO_REPLY)\n"))
              (let [nextState (rl/withHeadState state turn state.readStreak state.writesPersisted none
                        state.allGateResults state.lastGates "failed" (some "noReply") none state.runStarted)
                    nextRun (rl/withState run nextState)]
                (pair (rl/ProviderRun :run nextRun :provider response.provider :history wrapped.history) (stop)))))
          ((some replyRaw)
            (let [reply (at/continueReply prefill replyRaw)
                  clean (tr/turnReply reply (some ra.gates))
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
                  gateMin (wallSetting (ac/configText! rootDir) ":wallGateMinSec" (defaultWallGateMinSec))
                  gateOpStop (and (not (listEmpty? ra.gates))
                    (and (listAny? (fn [o] (= (liveOpName o) "gate")) operations)
                      (wallTooShort? (wallLeft env.wallBudget (- (env.now) state.runStarted)) gateMin)))
                  execOps (if gateOpStop (filter (fn [o] (!= (liveOpName o) "gate")) operations) operations)
                  execResult (if parseDefect (pair run (pair "" false))
                    (liveExecOps! execOps ra rootDir repoRoot run.session path execEnv run))
                  executedRaw (pairFirst execResult)
                  executed0 (match (if ra.plan (livePlanJson facts.forms) none)
                    ((some planState) (rl/withState executedRaw (rl/withPlan executedRaw.state planState)))
                    ((none) executedRaw))
                  turnUsageIn (match response.meta.usage ((some fields) (providerUsageInt fields "inputTokens")) ((none) 0))
                  turnUsageCached (match response.meta.usage ((some fields) (providerUsageInt fields "cachedTokens")) ((none) 0))
                  turnUsageOut (match response.meta.usage ((some fields) (providerUsageInt fields "outputTokens")) ((none) 0))
                  executedUsage (rl/withState executed0 (rl/withUsageTotals executed0.state
                    (rl/usageTotalsPlus executed0.state.usageTotals turnUsageIn turnUsageCached turnUsageOut)))
                  executed (rl/withState executedUsage (rl/withBatching executedUsage.state
                    (rl/batchingPlus executedUsage.state.batching (listLength operations))))
                  opReceipts (pairFirst (pairSecond execResult))
                  wrote (pairSecond (pairSecond execResult))
                  ; (:m :ref LEON-POOL-ASK-OP :do "between turns the asks other pool tasks sent this one reach the model as a (:poolAsks ...) observation")
                  poolAsks (po/servePending! ra.pool)
                  got (str normalized (if (stringEmpty? opReceipts) "" (str "\n" opReceipts)) (if (stringEmpty? poolAsks) "" (str "\n" poolAsks)))
                  gateLeft (wallLeft env.wallBudget (- (env.now) state.runStarted))
                  wantGates (not (or parseDefect (unchangedTurn? (map liveOpName operations) wrote)))
                  wallStop (or gateOpStop (and wantGates (and (not (listEmpty? ra.gates)) (wallTooShort? gateLeft gateMin))))
                  newGates (if (or (not wantGates) wallStop) (list) (runLiveGates! ra.gates rootDir (wallCapped ra.gateTimeout gateLeft) ra.parentPid))
                  allGates (listAppend state.allGateResults newGates)
                  lastGates (liveLastGateMap newGates state.lastGates)
                  turnOpNames (c/joinSep (map liveOpName operations) " ")
                  turnOpFiles (c/joinSep (filter (fn [p] (not (stringEmpty? p))) (map liveOpPath operations)) " ")
                  turnGateSummary (liveGateSummary newGates)
                  history (listAppend wrapped.history
                    (list (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr turnOwnSent)) (pair "got" (j/jstr got))
                      (pair "ops" (j/jstr turnOpNames)) (pair "files" (j/jstr turnOpFiles)) (pair "gates" (j/jstr turnGateSummary))))))
                  _ (fold (fn [acc gate] (and acc (ok? (fileAppend path (str "(:gate :cmd \"" (c/escapeAsn (g/gateCmd gate)) "\" :exit "
                       (stringFromInt64 (g/gateExit gate)) (if (g/gateTimeout gate) " :timeout true" "") ")\n"))))) true newGates)
                  _ (fileAppend path (str "(:turn " (stringFromInt64 turn) " :reply \"" (c/escapeAsn normalized) "\")\n"))
                  _ (let [(edits (jr/editReceiptsOf opReceipts))] (if (stringEmpty? edits) true (ok? (fileAppend path (str "(:turn " (stringFromInt64 turn) " :observation \"" (c/escapeAsn edits) "\")\n")))))
                  _ (if parseDefect (ok? (fileAppend path (str "(:turn " (stringFromInt64 turn) " :parse-defect true)\n"))) true)
                  _ (fileAppend path (str "(:turn " (stringFromInt64 turn) " :proseChars " (stringFromInt64 (at/proseChars reply)) ")\n"))
                  _ (if (at/attractorOn? ra.attractor)
                      (ok? (fileAppend path (str "(:turn " (stringFromInt64 turn) " :prefixHash \"" (at/prefixHash ra.attractor shapes) "\" :attractors (" (c/joinSep ask.cardNames " ") "))\n")))
                      true)
                  _ (if (> (c/echoCount normalized) 0) (ok? (fileAppend path (str (c/malformedLine turn (c/echoCount normalized)) "\n"))) true)
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
                    (gi/gateIntegrityWritten! ra.gates ra.owns rootDir newGates (wallCapped ra.gateTimeout (wallLeft env.wallBudget (- (env.now) state.runStarted))) none (rl/writtenPaths executed.written) ra.parentPid)
                    (pair true "not required"))
                  _ (if (and terminal (not (listEmpty? ra.gates)))
                    (ok? (fileAppend path (str "(:gateIntegrity :ok " (if (pairFirst integrity) "true" "false")
                      " :message \"" (c/escapeAsn (pairSecond integrity)) "\")\n"))) true)
                  reviewOk (if reviewInvoked (liveReviewAccepts? reviewResult) true)
                  hooksOk (and ask.advisorOk reviewOk)
                  status (if (or (not (pairFirst integrity)) (not hooksOk))
                    "failed" (if terminal "ok" "running"))
                  nextState0 (rl/withHeadState executed.state turn state.readStreak writesPersisted
                    deliver allGates lastGates
                    status none none state.runStarted)
                  nextState1 (rl/withFindings nextState0 (map (fn [form] (j/jstr form)) mergedFindingForms)
                    executed.state.needsConfirmList)
                  unbackedNow (if terminal (cb/unbackedGateClaims reply ra.gates allGates) (list))
                  nextState (if terminal (rl/withUnbacked nextState1 (map (fn [t] (j/jstr t)) unbackedNow)) nextState1)
                  withCommit (match (liveCommitMessage operations)
                    ((some message) (rl/withCommitMessage executed (some message)))
                    ((none) executed))
                  notedRun (rl/noteParseTurn (rl/withState withCommit nextState) turn parseDefect)
                  nextRun0 (if (and terminal (not (pairFirst integrity)))
                    (rl/withState notedRun (rl/withHeadState nextState turn nextState.readStreak writesPersisted deliver allGates lastGates
                      "failed" (some "gateIntegrity") (some (pairSecond integrity)) state.runStarted))
                    notedRun)
                  repeatKey (stringTrim normalized)
                  repeats (if (and (not parseDefect) (and (not wrote) (failedReceipts? opReceipts)))
                    (+ 1 (optionOr (mapGet state.failureCounts repeatKey) 0)) 0)
                  counts (if (> repeats 0) (mapSet (mapEmpty) repeatKey repeats) (mapEmpty))
                  repeatStop (and (not terminal) (>= repeats (repeatFailureCap)))
                  repeatReason (str "the same reply failed and changed nothing " (stringFromInt64 repeats) " turns in a row")
                  _ (if repeatStop (ok? (fileAppend path (str "(:turn " (stringFromInt64 turn) " :signal :repeatFailure :reason \"" repeatReason "\")\n"))) true)
                  wallHalt (and wallStop (not terminal))
                  wallReason (str (stringFromInt64 (optionOr gateLeft 0)) " s of the wall budget left, under the " (stringFromInt64 gateMin) " s a gate run needs")
                  _ (if wallHalt (ok? (fileAppend path (str "(:turn " (stringFromInt64 turn) " :signal :wallBudget :reason \"" wallReason "\")\n"))) true)
                  nextRun (cond
                    (wallHalt
                      (rl/withState nextRun0 (withCounts (rl/withHeadState nextRun0.state turn nextRun0.state.readStreak writesPersisted deliver allGates lastGates
                        "escalated" (some "wallBudget") (some (str "(:escalate :reason \"" wallReason "\")")) state.runStarted) counts)))
                    (repeatStop
                      (rl/withState nextRun0 (withCounts (rl/withHeadState nextRun0.state turn nextRun0.state.readStreak writesPersisted deliver allGates lastGates
                        "escalated" (some "repeatFailure") (some (str "(:escalate :reason \"" repeatReason "\")")) state.runStarted) counts)))
                    (else (rl/withState nextRun0 (withCounts nextRun0.state counts))))]
              (pair (rl/ProviderRun :run nextRun :provider response.provider :history history)
                    (if (or terminal (or repeatStop wallHalt)) (stop) (nextTurn)))))))))

fn ! liveJournal ra: RunArgs rootDir: String -> (Result (Pair String String) String)
  (match (dirCreate (pyJoin rootDir ".asl/run/agentLoop"))
    ((err e) (err e))
    ((ok _)
      (let [chosen (match ra.resume
                     ((some st) (ok (pair st.session st.journal)))
                     ((none) (match (newSessionId) ((err e) (err e)) ((ok sid) (ok (pair sid (journalPathOf rootDir sid)))))))]
        (match chosen
          ((err e) (err e))
          ((ok sp) (match (fileAppend (pairSecond sp) "") ((err e) (err e)) ((ok _) (ok sp))))))))

fn receiptPhases result: ls/RunResult -> (List String)
  (let [findingsReceipt (if (listEmpty? result.findings)
                          none
                          (ctx/receiptPhase (j/jobj (list (pair "type" (j/jstr "findings"))))))]
    (match findingsReceipt
      ((some phase) (if (listContains? result.phases phase) result.phases (listAppend result.phases (list phase))))
      ((none) result.phases)))

fn loopResultOf ra: RunArgs rootDir: String result: ls/RunResult usage: (Option Usage) lastStep: (Option String) -> LoopResult
  (let [counts result.batching
        countAt (fn [key] (optionOr (intValue (optionOr (j/jsonGet counts key) (j/jint 0))) 0))
        batching (some (Batching :turns (countAt "turns") :ops (countAt "ops") :single (countAt "single")))]
  (LoopResult :status result.status :modeHint (modeOf ra.modeHint)
    :deliver (if (= (optionOr result.deliver "") "findings") none result.deliver)
    :phases (receiptPhases result) :session (some result.session)
    :journal result.journal :unbacked result.unbacked
    :unbackedClaims (map pv/pyStr result.unbackedClaims) :contextTokens result.contextTokens
    :turns (some result.turns) :gates (map ls/gateJson result.gates)
    :escalate (match result.escalate ((some e) (some (pv/pyStr e))) ((none) none))
    :patch result.patch :restored result.restored :written result.written
    :needsConfirm (liveConfirmItems result.needsConfirm) :ownsRejected (liveOwnsItems result.ownsRejected) :error result.error :gatePreflight (list)
    :parseDefect result.parseDefect :parseDefectTurn result.parseDefectTurn
    :findings (some (map pv/pyStr result.findings)) :queueWaitSec result.queueWaitSec
    :execSec result.execSec :usage (match (liveUsage result.usage) ((some u) (some u)) ((none) usage))
    :batching batching :plan (livePlan result.planSummary) :vacuousGates result.vacuousGates
    :specCheck result.specCheck :stop (some (stopCause result.status result.signal result.error result.vacuousGates)) :lastStep lastStep))

; (:m :ref LEON-SPECCHECK-REVIEWER-DOWN :do "exit 0 for an ok run, and for a gated run that only lacks a reviewer: its status stays needsReview in the receipt")
fn liveExitCode r: LoopResult -> Int64
  (let [reviewerOnly (and (= r.status "needsReview")
                      (and (not (listEmpty? r.gates))
                        (match r.specCheck ((some v) (= v.verdict "unavailable")) ((none) false))))]
    (if (and (or (= r.status "ok") reviewerOnly) (= r.unbacked 0)) 0 1))

; (:m :ref SE3-POOL-DRIVER :do "executeLive in two halves: liveSetup! builds everything a run needs (journal, provider, system prompt, loop env) or the rejection, liveRun runs it blocking and liveResult turns a run result into the receipt; a pool driver prepares many sessions with liveSetup! and ends each with liveResult")
schema LiveSession
  (:f ra RunArgs)
  (:f repoRoot String)
  (:f rootDir String)
  (:f path String)
  (:f system String)
  (:f env ls/LoopEnv)
  (:f turnProvider pv/Provider)
  (:f providerCall (fn [pv/Provider String String] -> pv/Turn))

enum LivePrep
  (prepared LiveSession)
  (prepRejected MainResult)

fn ! liveSetup! ra0: RunArgs repoRoot: String rootDir: String env: pv/ProviderEnv -> LivePrep
  (let [ra (with ra0 :route (codeRouteSetup! ra0.intent (ac/configText! rootDir) repoRoot env))]
  (match (liveJournal ra rootDir)
    ((err e) (prepRejected (rejectWith (str ":error ERR_JOURNAL :message \"" (c/escapeAsn e) "\"") 1)))
    ((ok sp)
      ; (:m :ref LEON-ATTRIB-20261028 :do "the provider is made with the journal's session id, so the X-ASL-Session of every gateway call is the id the journal and the receipt carry and the ledger row joins the session")
      (match (pv/makeProvider! ra.backend "auto" rootDir ra.model ra.timeout (pairFirst sp) ra.queueTimeout ra.timeoutSet env (optionOr ra.intent "auto"))
        ((err e) (prepRejected (rejectWith (str ":error ERR_BACKEND :message \"" (c/escapeAsn (pv/errorMessage e)) "\"") 1)))
        ((ok provider0)
          (let [provider provider0
                turnProvider (pv/withTools provider0 (sessionTools ra.nativeTools))
                session (pairFirst sp)
                path (pairSecond sp)
                model (if (stringEmpty? ra.model) (defaultModel ra.backend) ra.model)
                tokens (ctx/contextTokensFor (some model) (match ra.contextTokens ((some t) (j/jint t)) ((none) (j/jnull)))
                  (listContains? (supportedBackends) ra.backend))
                prompt (jr/buildSystemPromptDrop repoRoot ra.task rootDir ra.base
                         ra.gates (some tokens) ra.plan (prefixDrop ra.prefix))]
            (match prompt
              ((err e) (prepRejected (rejectWith (str ":error ERR_HARNESS :message \"" (c/escapeAsn e) "\"") 1)))
              ((ok system0)
                (let [system system0
                      call (fn [sys user] (pv/nextTurn! turnProvider sys user))
                      providerCall (fn [p sys user] (pv/nextTurn! p sys user))
                      hooks (liveHooks! provider)
                      cfgText (ac/configText! rootDir)
                      graderIntent (optionOr (ac/agentLoopValue cfgText ":graderIntent") "grade")
                      graderProfile (optionOr (ac/agentLoopValue cfgText ":graderProfile") "")
                      specOn (!= (optionOr (ac/agentLoopValue cfgText ":specCheck") "true") "false")
                      liveEnv (ls/LoopEnv :provider call :task ra.task :modeHint (modeOf ra.modeHint)
                        :owns ra.owns :gates ra.gates :rootDir rootDir :budget ra.budget :inputTokenBudget ra.inputTokenBudget
                        :journalPath path :maxRetries 3 :sessionId (some session) :base (some ra.base)
                        :contextTokens (some tokens) :model (some model) :gateTimeout (some ra.gateTimeout)
                        :wallBudget (reservedWall ra.wallBudget (wallSetting cfgText ":wallReserveSec" (defaultWallReserveSec))) :resume none :intent ra.intent :plan ra.plan :specCheck specOn :commit false
                        :next call :advise (pairFirst hooks) :review (pairSecond hooks)
                        :grade (fn [role sys msg] (liveGrader provider graderIntent graderProfile path sys msg))
                        :newId (fn [] session) :now (fn [] (ao/nowMono))
                        :sleep (fn [seconds] (do (if (> seconds 0) (sleepMs (* seconds 1000)) ()) true)))]
                  (prepared (LiveSession :ra ra :repoRoot repoRoot :rootDir rootDir :path path :system system :env liveEnv :turnProvider turnProvider :providerCall providerCall)))))))))))

fn ! liveResult ls: LiveSession result: ls/RunResult -> MainResult
  (let [receipt (loopResultOf ls.ra ls.rootDir result (liveJournalUsage! ls.rootDir result.journal) (liveLastStep! ls.rootDir result.journal))]
    (MainResult :stdout (formatReceipt receipt) :exitCode (liveExitCode receipt)))

fn ! liveRun ls: LiveSession -> MainResult
  (liveResult ls (rl/runLoopWithProviderWatched! ls.env ls.turnProvider ls.ra.parentPid
    (fn [le wrapped] (liveBody! ls.ra ls.repoRoot ls.rootDir ls.path ls.system le ls.providerCall wrapped))))

fn ! executeLive ra0: RunArgs repoRoot: String rootDir: String env: pv/ProviderEnv -> MainResult
  (match (liveSetup! ra0 repoRoot rootDir env)
    ((prepRejected r) r)
    ((prepared ls) (liveRun ls)))

fn ! executeDryRun ra: RunArgs repoRoot: String rootDir: String env: pv/ProviderEnv -> MainResult
  (match (pv/buildDryRunInfo! ra.backend "auto" rootDir ra.model ra.timeout ra.queueTimeout env)
    ((err e) (rejectWith (str ":error ERR_BACKEND :message \"" (c/escapeAsn (pv/errorMessage e)) "\"") 1))
    ((ok info)
      (let [backend ra.backend
            model (if (stringEmpty? ra.model) (defaultModel backend) ra.model)
            tokens (ctx/contextTokensFor (some model) (match ra.contextTokens ((some t) (j/jint t)) ((none) (j/jnull)))
                                         (listContains? (supportedBackends) backend))]
        (match (jr/buildSystemPrompt repoRoot ra.task rootDir ra.base ra.gates (some tokens) ra.plan)
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
  (let [env (pv/providerEnv! rootDir)]
    (if dry (executeDryRun ra repoRoot rootDir env) (executeLive ra repoRoot rootDir env)))

fn resumed ra: RunArgs st: ResumeState -> RunArgs
  (RunArgs :task st.task :modeHint st.modeHint :owns st.owns :gates st.gates :backend ra.backend
           :model ra.model :timeout ra.timeout :timeoutSet ra.timeoutSet :queueTimeout ra.queueTimeout
           :budget ra.budget :inputTokenBudget ra.inputTokenBudget :gateTimeout ra.gateTimeout :wallBudget ra.wallBudget
           :intent (match ra.intent ((some i) (some i)) ((none) st.intent))
           :base st.base
           :remote ra.remote
           :contextTokens (match ra.contextTokens ((some t) (if (= t 0) st.contextTokens (some t))) ((none) st.contextTokens))
           :plan ra.plan :attractor ra.attractor :nativeTools ra.nativeTools :prefix ra.prefix :resume (some st) :pool ra.pool :parentPid ra.parentPid :route ra.route)

; (:m :ref SE3-POOL-DRIVER :do "the run arguments of an invocation's parameters, as dispatch builds them, so a pool driver starts a run from the same parameters")
fn ! runArgsOf ps: (List (Pair String j/Json)) timeout: Int64 queueTimeout: Int64 plan: Bool -> RunArgs
  (RunArgs :task (textValue (paramOr ps "task" (j/jstr ""))) :modeHint (optText (paramGet ps "modeHint"))
                    :owns (listValue (paramOr ps "owns" (j/jarr (list)))) :gates (listValue (paramOr ps "gates" (j/jarr (list))))
                    :backend (textValue (paramOr ps "backend" (j/jstr "agy"))) :model (optionOr (optText (paramGet ps "model")) "")
                    :timeout timeout :timeoutSet (paramHas ps "timeout") :queueTimeout queueTimeout
                    :budget (optionOr (intValue (paramOr ps "budget" (j/jint 3000))) 3000)
                    :inputTokenBudget (optionOr (intValue (paramOr ps "inputTokenBudget" (j/jint 0))) 0)
                    :gateTimeout (optionOr (intValue (paramOr ps "gateTimeout" (j/jint 300))) 300)
                    :wallBudget (some (optionOr (intValue (paramOr ps "wallBudget" (j/jint (min 86400 (+ timeout queueTimeout)))))
                                                  (min 86400 (+ timeout queueTimeout))))
                    :intent (optText (paramGet ps "intent"))
                    :base (textValue (paramOr ps "base" (j/jstr ""))) :remote (textValue (paramOr ps "remote" (j/jstr ""))) :contextTokens (intValue (paramOr ps "contextTokens" (j/jnull)))
                    :plan plan :attractor (textValue (paramOr ps "attractor" (j/jstr ""))) :nativeTools (textValue (paramOr ps "nativeTools" (j/jstr ""))) :prefix (textValue (paramOr ps "prefix" (j/jstr ""))) :resume none :parentPid (intValue (paramOr ps "parentPid" (j/jnull))) :route none
                    :pool (po/poolSelf (textValue (paramOr ps "poolChan" (j/jstr ""))) (optionOr (intValue (paramOr ps "poolIdx" (j/jint -1))) -1)))

fn ! dispatch ps: (List (Pair String j/Json)) repoRoot: String rootDir: String timeout: Int64 queueTimeout: Int64 plan: Bool -> MainResult
  (let [resumeV (paramOr ps "resume" (j/jnull))
        ra (runArgsOf ps timeout queueTimeout plan)
        dry (match (paramOr ps "dryRun" (j/jbool false)) ((j/jbool b) b) (_ false))]
    (cond
      ((and (truthy resumeV) (not (paramHas ps "answer"))) (resumeReport (textValue resumeV) rootDir))
      ((truthy resumeV)
        (match (journalResume (textValue resumeV) rootDir)
          ((err receipt) (MainResult :stdout receipt :exitCode 2))
          ((ok st) (execute (resumed ra st) dry repoRoot rootDir))))
      (else (execute ra dry repoRoot rootDir))))

; (:m :ref SE3F-POOL-PARITY :do "the CLI check chain returns what it decided instead of running it: valid carries the checked parameters, roots and wall, invalid carries the rejection receipt; mainWithRoots dispatches a valid one, and a pool driver starts a run from the same valid one, so both reject the same invocations with the same receipt")
schema Checked
  (:f ps (List (Pair String j/Json)))
  (:f repoRoot String)
  (:f rootDir String)
  (:f timeout Int64)
  (:f queueTimeout Int64)
  (:f plan Bool)

enum Valid
  (valid Checked)
  (invalid MainResult)

fn rejectValid fields: String exit: Int64 -> Valid
  (invalid (rejectWith fields exit))

fn unknownValid! uop: String -> Valid
  (invalid (unknownArg! uop))

fn contextValid kind: String path: String -> Valid
  (invalid (contextFileRejection kind path))

fn ! checkWall ps: (List (Pair String j/Json)) repoRoot: String rootDir: String -> Valid
  (let [given (optionOr (intValue (paramOr ps "timeout" (j/jint 600))) 600)
        queueTimeout (optionOr (intValue (paramOr ps "queueTimeout" (j/jint 1200))) 1200)
        wall (intValue (paramOr ps "wallBudget" (j/jnull)))
        timeout (match wall ((some w) (if (paramHas ps "timeout") given (max given (- w queueTimeout)))) ((none) given))
        limit (min 86400 (+ timeout queueTimeout))
        planEnv (optionOr (envGet "ASL_LEON_PLAN") "")
        planNull (match (paramGet ps "plan") ((some v) (match v ((j/jnull) true) (_ false))) ((none) false))
        plan (match (paramGet ps "plan") ((some v) (match v ((j/jbool b) b) (_ false))) ((none) (= planEnv "1")))]
    (cond
      ((or planNull (not (listContains? (list "" "0" "1") planEnv)))
        (rejectValid (str ":error ERR_INVALID_ARG :key \"" (if planNull "plan" "ASL_LEON_PLAN") "\" :value \"" (c/escapeAsn (if planNull "" planEnv)) "\""
                         " :message \"plan is true or false; ASL_LEON_PLAN is 1 or 0 and sets it when :plan is absent\"")
                    2))
      ((not (at/validAttractor? (textValue (paramOr ps "attractor" (j/jstr "")))))
        (rejectValid ":error ERR_INVALID_ARG :key \"attractor\" :message \"attractor is asn or off; absent means off\"" 2))
      ((not (nt/validTools? (textValue (paramOr ps "nativeTools" (j/jstr "")))))
        (rejectValid ":error ERR_INVALID_ARG :key \"nativeTools\" :message \"nativeTools is step, ops or off; absent means step\"" 2))
      ((not (validPrefix? (textValue (paramOr ps "prefix" (j/jstr "")))))
        (rejectValid (str ":error ERR_INVALID_ARG :key \"prefix\" :message \"prefix is a comma list of " (c/joinSep (prefixTokens) " ") "\"") 2))
      ((not (inRange (intValue (paramOr ps "wallBudget" (j/jint limit))) 1 limit))
        (rejectValid (str ":error ERR_INVALID_ARG :key \"wallBudget\" :limit " (stringFromInt64 limit)
                         " :message \"wallBudget must be an integer of seconds from 1 to timeout + queueTimeout, at most 86400 (bin/asl kills the dispatch 30 s after that); raise :timeout, or leave it out and :wallBudget sets it\"")
                    2))
      (else (valid (Checked :ps ps :repoRoot repoRoot :rootDir rootDir :timeout timeout :queueTimeout queueTimeout :plan plan)))))

fn ! checkBounds ps: (List (Pair String j/Json)) repoRoot: String rootDir: String -> Valid
  (cond
    ((and (paramHas ps "contextTokens") (not (inRange (intValue (paramOr ps "contextTokens" (j/jnull))) 4000 2000000)))
      (rejectValid ":error ERR_INVALID_ARG :key \"contextTokens\" :message \"contextTokens must be an integer from 4000 to 2000000\"" 2))
    ((not (inRange (intValue (paramOr ps "gateTimeout" (j/jint 300))) 1 86400))
      (rejectValid ":error ERR_INVALID_ARG :key \"gateTimeout\" :message \"gateTimeout must be an integer of seconds from 1 to 86400\"" 2))
    (else (checkWall ps repoRoot rootDir)))

fn ! checkRoot ps: (List (Pair String j/Json)) repoRoot: String rootDir: String -> Valid
  (let [rootV (paramOr ps "root" (j/jnull))]
    (if (not (truthy rootV))
      (checkBounds ps repoRoot rootDir)
      (let [raw (textValue rootV)
            target (go/pyRealpath! (pyJoin rootDir (expandUser raw)))]
        (if (isDir target)
          (checkBounds ps repoRoot target)
          (rejectValid (str ":error ERR_INVALID_ARG :key \"root\" :value \"" (c/escapeAsn raw) "\" :message \"root is not a directory: " (c/escapeAsn target) "\"") 2)))))

fn ! checkInvocation inv: Invocation repoRoot: String rootDir: String -> Valid
  (let [ps inv.params]
    (cond
      ((some? inv.syntaxError) (rejectValid (str ":error ERR_SYNTAX :message \"" (c/escapeAsn (optionOr inv.syntaxError "")) "\"") 2))
      ((paramHas ps "role") (rejectValid ":error ERR_ROLE_DEPRECATED :message \"use :intent or state the task\"" 2))
      ((not (listEmpty? inv.unknownOps)) (unknownValid! (c/firstOf inv.unknownOps)))
      ((some? inv.contextFileError)
        (let [e (optionOr inv.contextFileError (pair "" ""))] (contextValid (pairFirst e) (pairSecond e))))
      ((and (not (truthy (paramOr ps "task" (j/jstr "")))) (not (truthy (paramOr ps "resume" (j/jnull)))))
        (rejectValid ":error ERR_MISSING_ARG :message \"missing :task\"" 2))
      (else (checkRoot ps repoRoot rootDir))))

fn ! mainWithRoots argv: (List String) repoRoot: String rootDir: String -> MainResult
  (if (listEmpty? argv)
    (rejectWith ":error ERR_MISSING_ARG :message \"no form provided\"" 2)
    (match (checkInvocation (parseInvocation (c/firstOf argv) rootDir) repoRoot rootDir)
      ((invalid r) r)
      ((valid c) (dispatch c.ps c.repoRoot c.rootDir c.timeout c.queueTimeout c.plan))))

fn ! mainCli argv: (List String) -> Int64
  (let [repoRoot (resultOr (realPath ".") ".")
        rootDir (match (envGet "ASL_ROOT_DIR") ((some r) (if (stringEmpty? r) repoRoot r)) ((none) repoRoot))
        res (mainWithRoots argv repoRoot rootDir)]
    (do
      (println res.stdout)
      res.exitCode))

fn ! main argv: (List String) -> Int64
  (mainCli argv)
