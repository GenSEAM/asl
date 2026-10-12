(module asl/agentLoop/context
  :x [ContextTooLong contextTooLong contextTooLongCode contextTooLongMessage
      Review reviewError reviewVerdict AdviceForm adviceOf AdvisorResult advisorSkipped advisorError advisorAdvice Cover coverOf
      vendorBounds fitVendorCall contextTokensFor modelBase calibrationIndexPath calibrationIndexPath! servedContextTokens servedContextTokens!
      readPayloadChars renderTranscript renderTurnContext renderWindow stableSectionAt stableWindowTurn gateOutcome gateTail gateNow
      noWriteNudge readStreakEscalate noWriteTurns batchingRates costForm reinforceWhyFor escalationNear nowForm stepState! spanHolder seenReceipt failureSignatures
      coreDelta coreStatsLine formEnd sitePath possibleSitesOf readCovers siteNamed openPossible findingsRun possibleSiteList possibleNotice
      hiddenVars hiddenEnv! prefetchPaths! prefetchBlock! receiptPhase taskHintLines unmetForm specUnescape specCheckDiff! parseSpecVerdict
      runSpecCheck! digestLine evidenceDigest askReviewer! runFindingsCheck! advisorSkip advisorGateOutput advisorOpLine advisorSummary
      parseAdvice askAdvisor! adviceNotice progressLine emitProgress!
      pyStr pyTruthy pyRepr pyRound floatRepr pyNormpath pyRelpath pySplitLines pySplitLinesKeep pyStrip sha1Hex jget jgetOr filePatchNew
      specCheckSystem findingsCheckSystem advisorSystem]
  :i [(asl/agentLoop/core :a c) (asl-json/json :a j) (asl-proc/coreProcess :a cp)])

enum ContextTooLong
  (contextTooLong message: String)

fn contextTooLongCode -> String
  "ERR_CONTEXT_TOO_LONG"

fn contextTooLongMessage e: ContextTooLong -> String
  (mt e ((contextTooLong m) m))

enum Review
  (reviewError message: String)
  (reviewVerdict met: Bool missing: (List String))

enum AdviceForm
  (adviceOf next: String why: (Option String) avoid: (Option String))

enum AdvisorResult
  (advisorSkipped why: String)
  (advisorError message: String)
  (advisorAdvice advice: AdviceForm)

enum Cover
  (coverOf path: String first: Int64 last: (Option Int64))


fn sub s: String a: Int64 b: Int64 -> String
  (let [n (stringLength s)
        a2 (max 0 (min a n))
        b2 (max a2 (min b n))]
    (c/sliceOf s a2 b2))

fn at1 s: String i: Int64 -> String
  (sub s i (+ i 1))

fn litAt s: String p: Int64 lit: String -> Bool
  (let [k (stringLength lit)]
    (and (<= (+ p k) (stringLength s)) (= (c/sliceOf s p (+ p k)) lit)))

fn pySpace b: String -> Bool
  (or (= b " ") (and (>= b "\t") (<= b "\r")) (and (>= b "\u001c") (<= b "\u001f")))

fn pyUnicodeSpace cp: Int64 -> Bool
  (or (and (>= cp 9) (<= cp 13)) (and (>= cp 28) (<= cp 32)) (= cp 133) (= cp 160) (= cp 5760)
      (and (>= cp 8192) (<= cp 8202)) (= cp 8232) (= cp 8233) (= cp 8239) (= cp 8287) (= cp 12288))

fn utf8Codepoint bs: Bytes i: Int64 -> Int64
  (let [b0 (bytesGet bs i)
        lead (utf8Lead b0)]
    (cond
      ((= lead 1) b0)
      ((= lead 2) (+ (* (- b0 192) 64) (- (bytesGet bs (+ i 1)) 128)))
      ((= lead 3) (+ (* (- b0 224) 4096) (* (- (bytesGet bs (+ i 1)) 128) 64) (- (bytesGet bs (+ i 2)) 128)))
      (else (+ (* (- b0 240) 262144) (* (- (bytesGet bs (+ i 1)) 128) 4096)
               (* (- (bytesGet bs (+ i 2)) 128) 64) (- (bytesGet bs (+ i 3)) 128)))))

fn pySpaceStart bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (pyUnicodeSpace (utf8Codepoint bs i)))
    (pySpaceStart bs n (+ i (utf8Lead (bytesGet bs i))))
    i)

fn pyBackStart bs: Bytes i: Int64 -> Int64
  (if (and (> i 0) (and (>= (bytesGet bs i) 128) (< (bytesGet bs i) 192)))
    (pyBackStart bs (- i 1)) i)

fn pySpaceEnd bs: Bytes j: Int64 -> Int64
  (if (> j 0)
    (let [start (pyBackStart bs (- j 1))]
      (if (pyUnicodeSpace (utf8Codepoint bs start)) (pySpaceEnd bs start) j))
    0)
fn isDigitB b: String -> Bool
  (and (>= b "0") (<= b "9"))

fn isAlnumB b: String -> Bool
  (or (isDigitB b) (and (>= b "a") (<= b "z")) (and (>= b "A") (<= b "Z")))

fn skipWhile s: String i: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (< i (stringLength s)) (test (at1 s i))) (skipWhile s (+ i 1) test) i)

fn backWhile s: String j: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (> j 0) (test (at1 s (- j 1)))) (backWhile s (- j 1) test) j)

fn pyStrip s: String -> String
  (let [bs (stringToBytes s)
        n (stringLength s)
        a (pySpaceStart bs n 0)
        b (pySpaceEnd bs n)]
    (if (>= a b) "" (sub s a b)))

fn pyLstrip s: String -> String
  (let [bs (stringToBytes s)] (sub s (pySpaceStart bs (stringLength s) 0) (stringLength s)))

fn allDigits s: String -> Bool
  (and (> (stringLength s) 0) (= (skipWhile s 0 isDigitB) (stringLength s)))

fn charPrefix s: String k: Int64 -> String
  (if (<= k 0) "" (c/charPrefix s k))

fn charSuffix s: String k: Int64 -> String
  (let [n (c/charLen s)]
    (if (<= n k) s (sub s (c/charIndex s (stringLength s) 0 (- n k)) (stringLength s))))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (sub s 1 (stringLength s))) s)

fn joinSep xs: (List String) sep: String -> String
  (c/joinSep xs sep)

fn esc s: String -> String
  (c/escapeAsn s)

fn reprChar b: String -> String
  (cond
    ((= b "\\") "\\\\")
    ((= b "'") "\\'")
    ((= b "\n") "\\n")
    ((= b "\r") "\\r")
    ((= b "\t") "\\t")
    (else b))

fn pyRepr v: j/Json -> String
  (mt v
    ((j/jnull) "None")
    ((j/jbool b) (if b "True" "False"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum f) (stringFromFloat64 f))
    ((j/jstr s) (str "'" (c/joinAll (map reprChar (map (fn [i] (at1 s i)) (range 0 (stringLength s))))) "'"))
    ((j/jarr xs) (str "[" (joinSep (map pyRepr xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (joinSep (map (fn [p] (str (pyRepr (j/jstr (pairFirst p))) ": " (pyRepr (pairSecond p)))) kvs) ", ") "}")))

fn pyStr v: j/Json -> String
  (mt v ((j/jstr s) s) (_ (pyRepr v)))

fn pyTruthy v: j/Json -> Bool
  (mt v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint i) (!= i 0))
    ((j/jfloat f) (!= f 0.0))
    ((j/jnum f) (!= f 0.0))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj kvs) (not (listEmpty? kvs))))

fn isNone v: j/Json -> Bool
  (mt v ((j/jnull) true) (_ false))

fn isZero v: j/Json -> Bool
  (mt v
    ((j/jint i) (= i 0))
    ((j/jfloat f) (= f 0.0))
    ((j/jnum f) (= f 0.0))
    ((j/jbool b) (not b))
    (_ false))

fn jget o: j/Json k: String -> (Option j/Json)
  (mt o
    ((j/jobj kvs) (mt (listHead (filter (fn [p] (= (pairFirst p) k)) kvs)) ((some p) (some (pairSecond p))) (none none)))
    (_ none))

fn jgetOr o: j/Json k: String -> j/Json
  (optionOr (jget o k) (j/jnull))

fn has o: j/Json k: String -> Bool
  (some? (jget o k))

fn truthyAt o: j/Json k: String -> Bool
  (pyTruthy (jgetOr o k))

fn strOr o: j/Json k: String -> String
  (let [v (jgetOr o k)]
    (if (pyTruthy v) (pyStr v) ""))

fn firstTruthy o: j/Json keys: (List String) -> j/Json
  (mt (listHead (filter (fn [k] (truthyAt o k)) keys))
    ((some k) (jgetOr o k))
    (none (j/jnull)))

fn strAt o: j/Json k: String -> (Option String)
  (mt (jget o k) ((some v) (mt v ((j/jstr t) (some t)) (_ none))) (none none))

fn items v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn getDefault o: j/Json k: String dflt: String -> String
  (mt (jget o k) ((some v) (pyStr v)) (none dflt))

fn escVal v: j/Json -> String
  (mt v ((j/jnull) "") (_ (esc (pyStr v))))

fn dedupe xs: (List String) -> (List String)
  (listReverse (fold (fn [acc x] (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn pyInt v: j/Json -> (Option Int64)
  (mt v
    ((j/jint i) (some i))
    ((j/jbool b) (some (if b 1 0)))
    ((j/jfloat f) (float64ToInt64 f))
    ((j/jnum f) (float64ToInt64 f))
    ((j/jstr s)
      (let [t (pyStrip s)
            neg (stringStartsWith? t "-")
            body (if (or neg (stringStartsWith? t "+")) (sub t 1 (stringLength t)) t)]
        (if (allDigits body)
          (mt (stringToInt64 body) ((some n) (some (if neg (- 0 n) n))) (none none))
          none)))
    (_ none))


fn lineBreakAt s: String i: Int64 -> Int64
  (let [b (at1 s i)
        n (stringLength s)]
    (cond
      ((= b "\r") (if (and (< (+ i 1) n) (= (at1 s (+ i 1)) "\n")) 2 1))
      ((or (= b "\n") (= b "\u000b") (= b "\u000c") (= b "\u001c") (= b "\u001d") (= b "\u001e")) 1)
      ((litAt s i "\u0085") 2)
      ((or (litAt s i " ") (litAt s i " ")) 3)
      (else 0)))

fn splitLoop s: String i: Int64 start: Int64 keep: Bool acc: (List String) -> (List String)
  (if (>= i (stringLength s))
    (listReverse (if (< start i) (cons (sub s start i) acc) acc))
    (let [w (lineBreakAt s i)]
      (if (= w 0)
        (splitLoop s (+ i 1) start keep acc)
        (splitLoop s (+ i w) (+ i w) keep (cons (sub s start (if keep (+ i w) i)) acc)))))

fn pySplitLines s: String -> (List String)
  (splitLoop s 0 0 false (list))

fn pySplitLinesKeep s: String -> (List String)
  (splitLoop s 0 0 true (list))

fn lastN xs: (List T) k: Int64 -> (List T)
  (let [n (listLength xs)]
    (if (<= n k) xs (listDrop xs (- n k))))

fn normStep acc: (List String) comp: String absolute: Bool -> (List String)
  (cond
    ((or (= comp "") (= comp ".")) acc)
    ((or (!= comp "..") (and (not absolute) (listEmpty? acc)) (and (not (listEmpty? acc)) (= (c/firstOf acc) "..")))
      (cons comp acc))
    ((not (listEmpty? acc)) (c/restOf acc))
    (else acc))

fn pyNormpath p: String -> String
  (let [slashes (cond
                  ((not (stringStartsWith? p "/")) 0)
                  ((and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) 2)
                  (else 1))
        comps (listReverse (fold (fn [acc comp] (normStep acc comp (> slashes 0))) (list) (stringSplit p "/")))
        body (str (stringRepeat "/" slashes) (joinSep comps "/"))]
    (if (stringEmpty? body) "." body))

fn isAbs p: String -> Bool
  (stringStartsWith? p "/")

fn pathJoin a: String b: String -> String
  (cond
    ((isAbs b) b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn commonCount a: (List String) b: (List String) k: Int64 -> Int64
  (if (or (listEmpty? a) (listEmpty? b) (!= (c/firstOf a) (c/firstOf b)))
    k
    (commonCount (c/restOf a) (c/restOf b) (+ k 1)))

fn pyRelpath p: String start: String -> String
  (let [sl (filter (fn [x] (not (stringEmpty? x))) (stringSplit (pyNormpath start) "/"))
        pl (filter (fn [x] (not (stringEmpty? x))) (stringSplit (pyNormpath p) "/"))
        i (commonCount sl pl 0)
        rel (listAppend (map (fn [_] "..") (range i (listLength sl))) (listDrop pl i))]
    (if (listEmpty? rel) "." (joinSep rel "/")))


fn f64Bits x: Float64 -> (List Int64)
  (let [b (bytesAlloc 8)]
    (do (bytesSetFloat64 b 0 x) (map (fn [i] (bytesGet b i)) (range 0 8))))

fn bytesWord bs: (List Int64) lo: Int64 -> Int64
  (fold (fn [acc i] (+ (* acc 256) (optionOr (listGet bs (- (+ lo 3) i)) 0))) 0 (range 0 4))

fn limbBase -> Int64
  1000000000

fn mulSmall limbs: (List Int64) f: Int64 carry: Int64 acc: (List Int64) -> (List Int64)
  (if (listEmpty? limbs)
    (if (= carry 0) (listReverse acc) (mulSmall (list) f (/ carry (limbBase)) (cons (mod carry (limbBase)) acc)))
    (let [v (+ (* (c/firstOf limbs) f) carry)]
      (mulSmall (c/restOf limbs) f (/ v (limbBase)) (cons (mod v (limbBase)) acc))))

fn mulPow5 limbs: (List Int64) k: Int64 -> (List Int64)
  (cond
    ((>= k 13) (mulPow5 (mulSmall limbs 1220703125 0 (list)) (- k 13)))
    ((> k 0) (mulPow5 (mulSmall limbs 5 0 (list)) (- k 1)))
    (else limbs))

fn pad9 v: Int64 -> String
  (let [s (stringFromInt64 v)]
    (str (stringRepeat "0" (- 9 (stringLength s))) s))

fn toLimbs m: Int64 -> (List Int64)
  (list (mod m (limbBase)) (mod (/ m (limbBase)) (limbBase)) (/ m (* (limbBase) (limbBase))))

fn trimLimbs r: (List Int64) -> (List Int64)
  (if (and (> (listLength r) 1) (= (c/firstOf r) 0)) (trimLimbs (c/restOf r)) r)

fn limbsDigits limbs: (List Int64) -> String
  (let [r (trimLimbs (listReverse limbs))]
    (str (stringFromInt64 (c/firstOf r)) (c/joinAll (map pad9 (c/restOf r)))))

fn incDigits s: String -> String
  (let [n (stringLength s)
        k (backWhile s n (fn [b] (= b "9")))]
    (if (= k 0)
      (str "1" (stringRepeat "0" n))
      (str (sub s 0 (- k 1)) (stringFromInt64 (+ (optionOr (stringToInt64 (at1 s (- k 1))) 0) 1)) (stringRepeat "0" (- n k)))))

fn anyNonZero s: String -> Bool
  (listAny? (fn [i] (!= (at1 s i) "0")) (range 0 (stringLength s)))

fn roundDigits m: Int64 e: Int64 d: Int64 -> String
  (if (>= e 0)
    (str (limbsDigits (fold (fn [acc _] (mulSmall acc 2 0 (list))) (toLimbs m) (range 0 e))) "." (stringRepeat "0" d))
    (let [k (- 0 e)
          raw (limbsDigits (mulPow5 (toLimbs m) k))
          digits (if (<= (stringLength raw) k) (str (stringRepeat "0" (+ (- k (stringLength raw)) 1)) raw) raw)
          ip (sub digits 0 (- (stringLength digits) k))
          frac (sub digits (- (stringLength digits) k) (stringLength digits))
          fracD (if (>= (stringLength frac) d) frac (str frac (stringRepeat "0" (- d (stringLength frac)))))
          kept (str ip (sub fracD 0 d))
          rest (sub fracD d (stringLength fracD))
          first (if (stringEmpty? rest) "0" (at1 rest 0))
          lastOdd (let [l (optionOr (stringToInt64 (at1 kept (- (stringLength kept) 1))) 0)] (= (mod l 2) 1))
          up (cond
               ((> first "5") true)
               ((< first "5") false)
               ((anyNonZero (sub rest 1 (stringLength rest))) true)
               (else lastOdd))
          whole (if up (incDigits kept) kept)
          cut (- (stringLength whole) d)]
      (if (= d 0) whole (str (sub whole 0 cut) "." (sub whole cut (stringLength whole))))))

fn pyRound x: Float64 d: Int64 -> Float64
  (if (or (isNan? x) (not (isFinite? x)))
    x
    (let [bs (f64Bits x)
          hi (bytesWord bs 4)
          lo (bytesWord bs 0)
          neg (>= hi 2147483648)
          ex (mod (/ hi 1048576) 2048)
          mant (+ (* (mod hi 1048576) 4294967296) lo)
          m (if (= ex 0) mant (+ mant 4503599627370496))
          e (if (= ex 0) -1074 (- ex 1075))]
      (optionOr (stringToFloat64 (str (if neg "-" "") (roundDigits m e d))) x)))

fn floatRepr x: Float64 -> String
  (stringFromFloat64 x)

fn ratio a: Int64 b: Int64 -> Float64
  (/ (int64ToFloat64 a) (int64ToFloat64 b))

fn jnum v: j/Json -> Float64
  (mt v
    ((j/jint i) (int64ToFloat64 i))
    ((j/jfloat f) f)
    ((j/jnum f) f)
    ((j/jbool b) (if b 1.0 0.0))
    (_ 0.0))

fn jint v: j/Json -> Int64
  (mt v
    ((j/jint i) i)
    ((j/jbool b) (if b 1 0))
    ((j/jfloat f) (optionOr (float64ToInt64 f) 0))
    (_ 0))


fn posInt v: j/Json -> (Option Int64)
  (mt v ((j/jint i) (if (> i 0) (some i) none)) (_ none))

fn vendorBounds timeout: j/Json queueTimeout: j/Json -> (Option (Pair Int64 Int64))
  (mt (posInt timeout)
    ((some t) (mt (posInt queueTimeout) ((some q) (some (pair t q))) (none none)))
    (none none))

fn vendorHttpSlackSec -> Int64
  30

fn vendorMinCallSec -> Int64
  60

fn fitVendorCall bounds: (Option (Pair Int64 Int64)) left: Int64 -> (Pair Bool (Option (Pair Int64 Int64)))
  (let [room (- left (if (some? bounds) (vendorHttpSlackSec) 0))]
    (if (< room (max 2 (vendorMinCallSec)))
      (pair false none)
      (mt bounds
        ((some b) (let [t (min (pairFirst b) (- room 1))]
                    (pair true (some (pair t (max 1 (min (pairSecond b) (- room t))))))))
        (none (pair true none)))))

fn smallContextTokens -> Int64
  8000

fn charsPerToken -> Int64
  3

; (:m :tags (budget))
fn familyTokens -> (List (Pair String Int64))
  (list (pair "gemini" (/ 180000 3)) (pair "claude" 100000) (pair "opus" 100000) (pair "sonnet" 100000)
        (pair "haiku" 100000) (pair "gpt" 100000) (pair "codex" 100000) (pair "glm" 100000)
        (pair "deepseek" 120000) (pair "minimax" 120000))

fn contextTokensFor model: (Option String) contextTokens: j/Json split: Bool -> Int64
  (if (pyTruthy contextTokens)
    (jint contextTokens)
    (let [mid (stringLower (optionOr model ""))
          fams (listAppend (if split (list (pair "gemini" 120000)) (list)) (familyTokens))]
      (mt (listHead (filter (fn [p] (stringContains? mid (pairFirst p))) fams))
        ((some p) (pairSecond p))
        (none (smallContextTokens)))))

fn vendorPrefixes -> (List String)
  (list "agy" "codex" "claude" "ollama" "groq" "openrouter")

fn modelBase name: j/Json -> String
  (let [s (if (pyTruthy name) (pyStr name) "")
        hit (filter (fn [p] (and (stringStartsWith? s p)
                                 (or (= (at1 s (stringLength p)) ":") (= (at1 s (stringLength p)) "/"))))
                    (vendorPrefixes))]
    (stringLower (mt (listHead hit) ((some p) (sub s (+ (stringLength p) 1) (stringLength s))) (none s))))

fn calibrationIndexPath env: (Option String) root: String -> String
  (mt env
    ((some v) (if (stringEmpty? v) (pathJoin root ".asl/mem/calibration/index.asn") v))
    (none (pathJoin root ".asl/mem/calibration/index.asn")))

fn ! calibrationIndexPath! root: String -> String
  (calibrationIndexPath (envGet "ASL_CALIBRATION_INDEX") root)

fn modelRowAt text: String p: Int64 -> (Option (Pair String Int64))
  (let [head "(:model :id \""
        a (+ p (stringLength head))
        q (optionOr (optionMap (fn [k] (+ a k)) (stringIndexOf (sub text a (stringLength text)) "\"")) -1)]
    (if (and (litAt text p head) (> q a)) (some (pair (sub text a q) (+ q 1))) none))

fn nextRowHead text: String from: Int64 -> Int64
  (mt (stringIndexOf (sub text from (stringLength text)) "(:model :id \"")
    ((some k) (+ from k))
    (none (stringLength text)))

fn rowsLoop text: String p: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (mt (stringIndexOf (sub text p (stringLength text)) "(:model :id \"")
    (none (listReverse acc))
    ((some k)
      (mt (modelRowAt text (+ p k))
        (none (rowsLoop text (+ (+ p k) 1) acc))
        ((some r)
          (let [e (nextRowHead text (pairSecond r))]
            (rowsLoop text e (cons (pair (pairFirst r) (sub text (pairSecond r) e)) acc)))))))

fn rowText rows: (List (Pair String String)) id: String -> String
  (fold (fn [acc r] (if (= (pairFirst r) id) (pairSecond r) acc)) "" rows)

fn digitsAt s: String i: Int64 -> Int64
  (skipWhile s i isDigitB)

fn budgetAt s: String p: Int64 -> (Option Int64)
  (let [j0 (+ p (stringLength ":contextBudget"))
        j (skipWhile s j0 pySpace)
        viaV (if (litAt s j "(:v")
               (let [k (skipWhile s (+ j 3) pySpace)
                     e (digitsAt s k)]
                 (if (and (> k (+ j 3)) (> e k)) (stringToInt64 (sub s k e)) none))
               none)
        e2 (digitsAt s j)]
    (cond
      ((= j j0) none)
      ((some? viaV) viaV)
      ((> e2 j) (stringToInt64 (sub s j e2)))
      (else none)))

fn findBudget s: String p: Int64 -> (Option Int64)
  (mt (stringIndexOf (sub s p (stringLength s)) ":contextBudget")
    (none none)
    ((some k) (mt (budgetAt s (+ p k)) ((some v) (some v)) (none (findBudget s (+ (+ p k) 1))))))

; (:m :tags (budget))
fn servedContextTokens served: j/Json split: Bool text: String -> (Option Int64)
  (let [raw (pyStr (let [v (firstTruthy served (list "model" "alias"))] (if (pyTruthy v) v (j/jstr ""))))
        model (modelBase (j/jstr raw))]
    (if (stringEmpty? model)
      none
      (let [rows (rowsLoop text 0 (list))
            effort (jgetOr served "effort")
            named (if (pyTruthy effort) (list model (str model ":" (pyStr effort))) (list model))
            extra (listSort (dedupe (filter (fn [id] (stringStartsWith? id (str model ":"))) (map pairFirst rows))))
            hit (fold (fn [acc id] (if (some? acc) acc (findBudget (rowText rows id) 0))) none (listAppend named extra))]
        (mt hit ((some v) (some v)) (none (some (contextTokensFor (some model) (j/jnull) split)))))))

fn ! servedContextTokens! served: j/Json split: Bool path: String -> (Option Int64)
  (servedContextTokens served split (resultOr (fileReadString path) ""))

fn readPayloadChars contextTokens: Int64 -> Int64
  (if (<= contextTokens (smallContextTokens))
    8000
    (max 8000 (min 40000 (/ (* contextTokens (charsPerToken)) 10))))


fn turnsOf history: (List j/Json) -> (List c/Turn)
  (map (fn [h] (c/makeTurn (pyStr (jgetOr h "turn")) (pyStr (jgetOr h "sent")) (pyStr (jgetOr h "got")))) history)

fn transcriptMaxChars -> Int64
  (* (smallContextTokens) (charsPerToken))

fn renderTranscript history: (List j/Json) budget: Int64 -> String
  (c/renderTranscript (turnsOf history) budget)

fn renderTurnContext coverage: (Option (List (Pair String (List (Pair Int64 Int64))))) history: (List j/Json) budget: Int64 -> (Pair (Option String) String)
  (pair (optionMap c/renderSeen coverage) (renderTranscript history budget))

fn renderWindow coverage: (List (Pair String (List (Pair Int64 Int64)))) history: (List j/Json) budget: Int64 cut: Int64 dropped: Int64 pinned: (List String) -> (Pair String j/Json)
  (mt (c/renderWindow (turnsOf history) budget cut dropped pinned)
    ((c/windowOf text last cutN droppedN used whole)
      (pair (c/renderSeen coverage)
        (j/jobj (list (pair "cut" (j/jint cutN)) (pair "dropped" (j/jint droppedN)) (pair "used" (j/jint used))
                      (pair "whole" (j/jarr (map (fn [i] (j/jint i)) (listSort (map (fn [t] (optionOr (stringToInt64 t) 0)) whole)))))
                      (pair "text" (j/jstr text)) (pair "last" (j/jstr last)))))))

fn stableSectionAt basePrompt: String systemPrompt: String offsetBytes: Int64 -> String
  (cond
    ((< offsetBytes (stringLength basePrompt)) "systemPrompt")
    ((< offsetBytes (stringLength systemPrompt)) "plan")
    (else "window"))

fn turnMarks s: String p: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (mt (stringIndexOf (sub s p (stringLength s)) "(:turn ")
    (none (listReverse acc))
    ((some k)
      (let [a (+ p k)
            d0 (+ a 7)
            d1 (digitsAt s d0)]
        (if (and (> d1 d0) (litAt s d1 " :sent"))
          (turnMarks s (+ d1 6) (cons (pair a (optionOr (stringToInt64 (sub s d0 d1)) 0)) acc))
          (turnMarks s (+ a 1) acc)))))

fn stableWindowTurn winText: String offsetBytes: Int64 windowStartBytes: Int64 -> (Option Int64)
  (let [local (- offsetBytes windowStartBytes)]
    (if (< local 0)
      none
      (fold (fn [acc m] (if (<= (pairFirst m) local) (some (pairSecond m)) acc)) none (turnMarks winText 0 (list)))))


fn gateOutcome g: j/Json -> String
  (if (truthyAt g "timeout")
    (str ":timeout true :seconds " (pyStr (jgetOr g "seconds")))
    (str ":exit " (pyStr (jgetOr g "exit"))))

; (:m :ref WINDOWED-OBSERVATION :do "a FAIL/ERR_ASSERT line or a (:gate ...) anchor with a nonzero :failed count")
fn isFailMarkedLine line: String -> Bool
  (or (stringContains? line "FAIL") (stringContains? line "ERR_ASSERT")
    (and (stringStartsWith? line "(:gate ")
      (mt (countsOnLine line 7) ((some cnt) (!= (pairSecond cnt) "0")) (none false))))

fn failureLines lines: (List String) -> (List String)
  (filter isFailMarkedLine lines)

; (:m :ref WINDOWED-OBSERVATION :do "select FAIL/ERR_ASSERT lines, the failing (:gate ...) anchor from anchoredCounts, and the final line ahead of a plain last-20-line tail, so a failure outside the plain tail still survives; same 20-line/2000-char limits either way")
fn gateTail g: j/Json -> String
  (let [combined (pyStrip (str (strOr g "stdout") "\n" (strOr g "stderr")))
        lines (pySplitLines combined)
        failing (failureLines lines)
        last (optionOr (listLast lines) "")
        selected (if (listEmpty? failing) (list) (dedupe (listAppend failing (if (stringEmpty? last) (list) (list last)))))
        chosen (if (listEmpty? selected) lines selected)]
    (charSuffix (joinSep (lastN chosen 20) "\n") 2000))

fn countsOnLine line: String q: Int64 -> (Option (Pair String String))
  (if (> q (stringLength line))
    none
    (let [a (+ q (stringLength ":asserts "))
          ae (digitsAt line a)
          f (+ ae (stringLength " :failed "))
          fe (digitsAt line f)]
      (if (and (litAt line q ":asserts ") (> ae a) (litAt line ae " :failed ") (> fe f))
        (some (pair (sub line a ae) (sub line f fe)))
        (countsOnLine line (+ q 1)))))

fn anchoredCounts text: String -> (List (Pair String String))
  (fold (fn [acc line]
          (if (stringStartsWith? line "(:gate ")
            (mt (countsOnLine line 7) ((some cnt) (listAppend acc (list cnt))) (none acc))
            acc))
    (list) (stringSplit text "\n"))

fn countsTail counts: (List (Pair String String)) -> String
  (mt (listLast counts)
    ((some cnt) (str " :asserts " (pairFirst cnt) " :failed " (pairSecond cnt)))
    (none ""))

fn gateNow turn: j/Json g: j/Json -> String
  (str "(:cmd \"" (escVal (optionOr (jget g "cmd") (j/jstr ""))) "\" :turn " (pyStr turn) " " (gateOutcome g)
    (countsTail (anchoredCounts (strOr g "stdout"))) ")")

fn readStreakNudge -> Int64
  6

fn readStreakEscalate -> Int64
  12

fn noWriteNudgeTurns -> Int64
  10

fn noWriteTurns -> Int64
  20

fn noWriteNudge deliver: (Option String) wrote: Bool done: Int64 files: (List String) win: (Option (List Int64)) readStreak: Int64 redGate: j/Json -> String
  (cond
    ((and (pyTruthy redGate) (>= readStreak (readStreakNudge)))
      (str (stringFromInt64 readStreak) " turns without a write while gate " (pyStr redGate)
        " is red: write the fix you have, or escalate naming what is missing"))
    ((or (!= deliver (some "patch")) wrote (< done (noWriteNudgeTurns))) "")
    (else
      (let [whole (mt win ((some ts) (joinSep (map stringFromInt64 (listSort ts)) " ")) (none ""))
            fs (if (listEmpty? files) "none" (joinSep files ", "))]
        (str (stringFromInt64 done) " turns and nothing written; files read: " fs ";"
          " receipts still whole: turns " whole "; the run stops at turn " (stringFromInt64 (noWriteTurns)) " without a write"))))

fn batchingRates b: j/Json -> (Pair Float64 Float64)
  (let [turns (jint (jgetOr b "turns"))]
    (if (= turns 0)
      (pair 0.0 0.0)
      (pair (pyRound (ratio (jint (jgetOr b "ops")) turns) 2) (pyRound (ratio (jint (jgetOr b "single")) turns) 2))))

fn costForm b: j/Json tokens: j/Json wallSec: Float64 turnsDone: Int64 -> String
  (let [rates (batchingRates b)
        pace (if (= turnsDone 0) 0.0 (pyRound (/ wallSec (int64ToFloat64 turnsDone)) 1))]
    (str "(:turns " (pyStr (jgetOr b "turns")) " :tokens " (pyStr tokens) " :opsPerTurn " (floatRepr (pairFirst rates))
      " :singleOpShare " (floatRepr (pairSecond rates)) " :secPerTurn " (floatRepr pace) ")"))

fn failureCap -> Int64
  3

fn stallTurns -> Int64
  3

; (:m :tags (signals))
fn escalationNear turn: Int64 budget: Int64 retries: (List (Pair String Int64)) maxRetries: Int64 failureCounts: (List (Pair String Int64)) stalled: Int64 parseDefects: Int64 noWrite: Bool readStreak: Int64 redGate: Bool -> String
  (let [spent (filter (fn [p] (>= (pairSecond p) maxRetries)) retries)]
    (cond
      ((<= turn 1) "")
      ((not (listEmpty? spent)) (str "one more " (pairFirst (c/firstOf spent)) " miss escalates"))
      ((and (not (listEmpty? failureCounts)) (>= (optionOr (listMax (map pairSecond failureCounts)) 0) (- (failureCap) 1)))
        "one more repeat of the same failure escalates")
      ((>= stalled (- (stallTurns) 1)) "one more turn without new evidence escalates")
      ((>= parseDefects maxRetries) "one more parse defect escalates")
      ((and redGate (>= readStreak (- (readStreakEscalate) 1))) "one more turn without a write while a gate is red escalates")
      ((and noWrite (or (>= (* 2 turn) budget) (>= turn (noWriteTurns)))) "the run stops without a write after this turn")
      (else "")))

fn intersectSorted a: (List String) b: (List String) -> (List String)
  (listSort (dedupe (filter (fn [x] (listContains? b x)) a)))

fn reinforceWhyFor turnFacts: j/Json gateSigHistory: (List (List String)) deliver: (Option String) writesPersisted: Bool turnsWithoutEvidence: Int64 turnNum: Int64 budget: Int64 retries: (List (Pair String Int64)) maxRetries: Int64 failureCounts: (List (Pair String Int64)) parseDefectCount: Int64 readStreak: Int64 redGate: j/Json -> String
  (let [n (listLength gateSigHistory)
        twice (if (>= n 2)
                (intersectSorted (optionOr (listGet gateSigHistory (- n 1)) (list)) (optionOr (listGet gateSigHistory (- n 2)) (list)))
                (list))
        patchIdle (and (= deliver (some "patch")) (not writesPersisted))]
    (cond
      ((not (listEmpty? twice)) (str "same gate failure twice in a row: " (charPrefix (c/firstOf twice) 160)))
      ((truthyAt turnFacts "parseDefect") "the last reply was a parse defect")
      ((and (pyTruthy redGate) (>= readStreak (readStreakNudge)))
        (str (stringFromInt64 readStreak) " turns without a write while gate " (pyStr redGate) " is red"))
      ((and patchIdle (>= turnsWithoutEvidence 2))
        (str "patch deliverable and nothing written after " (stringFromInt64 (- turnNum 1)) " turns"))
      (else (escalationNear turnNum budget retries maxRetries failureCounts turnsWithoutEvidence parseDefectCount patchIdle
              readStreak (pyTruthy redGate)))))

fn nowForm turn: Int64 contextTokens: j/Json win: j/Json written: (List String) lastGates: (List (Pair String (Pair j/Json j/Json))) retriesLeft: (List (Pair String Int64)) nudge: String cost: String plan: String -> String
  (let [on (pyTruthy win)]
    (str "(:now :turn " (stringFromInt64 turn) " :context (:tokens " (pyStr contextTokens) " :usedBytes "
      (if on (pyStr (jgetOr win "used")) "0") ")"
      (if (stringEmpty? cost) "" (str " :cost " cost))
      (if (stringEmpty? plan) "" (str " :plan " plan))
      (if (stringEmpty? nudge) "" (str " :noWrite \"" (esc nudge) "\""))
      (if (listEmpty? written) "" (str " :written (" (joinSep (map (fn [p] (str "\"" (esc p) "\"")) written) " ") ")"))
      (if (listEmpty? lastGates) ""
        (str " :gates (" (joinSep (map (fn [e] (gateNow (pairFirst (pairSecond e)) (pairSecond (pairSecond e)))) lastGates) " ") ")"))
      " :retriesLeft (" (joinSep (map (fn [p] (str ":" (pairFirst p) " " (stringFromInt64 (max 0 (pairSecond p))))) retriesLeft) " ") ")"
      (if on (str " :last " (pyStr (jgetOr win "last"))) "")
      ")"))


fn mask32 -> Int64
  4294967295

fn pow2 n: Int64 -> Int64
  (fold (fn [acc _] (* acc 2)) 1 (range 0 n))

fn rotl x: Int64 n: Int64 -> Int64
  (| (& (* x (pow2 n)) (mask32)) (/ x (pow2 (- 32 n))))

fn add32 a: Int64 b: Int64 -> Int64
  (& (+ a b) (mask32))

fn padByte bs: Bytes n: Int64 total: Int64 i: Int64 -> Int64
  (cond
    ((< i n) (bytesGet bs i))
    ((= i n) 128)
    ((< i (- total 8)) 0)
    (else (let [shift (* 8 (- (- total 1) i))
                bits (* n 8)]
            (if (>= shift 62) 0 (mod (/ bits (pow2 shift)) 256)))))

fn blockWords bs: Bytes n: Int64 total: Int64 base: Int64 -> (List Int64)
  (map (fn [w] (fold (fn [acc k] (+ (* acc 256) (padByte bs n total (+ base (+ (* w 4) k))))) 0 (range 0 4))) (range 0 16))

fn roundF t: Int64 b: Int64 cc: Int64 d: Int64 -> Int64
  (cond
    ((< t 20) (| (& b cc) (& (^ b (mask32)) d)))
    ((< t 40) (^ b (^ cc d)))
    ((< t 60) (| (| (& b cc) (& b d)) (& cc d)))
    (else (^ b (^ cc d))))

fn roundK t: Int64 -> Int64
  (cond ((< t 20) 1518500249) ((< t 40) 1859775393) ((< t 60) 2400959708) (else 3395469782))

fn nth xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn sha1Rounds t: Int64 w: (List Int64) st: (List Int64) -> (List Int64)
  (if (>= t 80)
    st
    (let [wt (if (< t 16) (nth w t) (rotl (^ (nth w 13) (^ (nth w 8) (^ (nth w 2) (nth w 0)))) 1))
          w2 (if (< t 16) w (listAppend (listDrop w 1) (list wt)))
          a (nth st 0) b (nth st 1) cc (nth st 2) d (nth st 3) e (nth st 4)
          tmp (add32 (add32 (add32 (rotl a 5) (roundF t b cc d)) (add32 e (roundK t))) wt)]
      (sha1Rounds (+ t 1) w2 (list tmp a (rotl b 30) cc d))))

fn sha1Blocks bs: Bytes n: Int64 total: Int64 base: Int64 h: (List Int64) -> (List Int64)
  (if (>= base total)
    h
    (let [out (sha1Rounds 0 (blockWords bs n total base) h)]
      (sha1Blocks bs n total (+ base 64) (map (fn [i] (add32 (nth h i) (nth out i))) (range 0 5)))))

fn hex8 v: Int64 -> String
  (let [digits "0123456789abcdef"]
    (c/joinAll (map (fn [k] (at1 digits (mod (/ v (pow2 (* 4 (- 7 k)))) 16))) (range 0 8))))

fn sha1Hex bs: Bytes -> String
  (let [n (bytesLength bs)
        total (* 64 (/ (+ n 72) 64))]
    (c/joinAll (map hex8 (sha1Blocks bs n total 0 (list 1732584193 4023233417 2562383102 271733878 3285377520)))))

fn workspaceOps -> (List String)
  (list "query" "q" "tree" "diff" "gitDiff")

fn ! stepState! op: j/Json root: (Option String) workspaceGen: j/Json -> j/Json
  (let [name (getDefault op "op" "")]
    (cond
      ((or (= name "read") (= name "check"))
        (let [f (strOr op "file")
              r (mt root ((some v) (if (stringEmpty? v) "." v)) (none "."))
              full (if (isAbs f) f (pathJoin r f))]
          (if (isDir! full) (j/jnull)
            (mt (fileReadBytes full) ((ok bs) (j/jstr (sha1Hex bs))) ((err _) (j/jnull))))))
      ((listContains? (workspaceOps) name) workspaceGen)
      (else (j/jint 0))))

; (:m :tags (window))
fn spanHolder op: j/Json turnEvidence: (List (Pair Int64 (List (Pair String (Pair Int64 Int64))))) whole: (List Int64) -> (Option (Pair Int64 (Pair Int64 Int64)))
  (if (or (!= (strAt op "type") (some "step")) (!= (strAt op "op") (some "read")) (truthyAt op "symbol"))
    none
    (mt (pyInt (jgetOr op "start"))
      (none none)
      ((some a)
        (mt (pyInt (jgetOr op "end"))
          (none none)
          ((some b)
            (let [f (pyNormpath (strOr op "file"))]
              (fold (fn [acc t]
                      (if (some? acc) acc
                        (let [ev (fold (fn [e2 p] (if (= (pairFirst p) t) (pairSecond p) e2)) (list) turnEvidence)]
                          (mt (listHead (filter (fn [x] (and (= (pyNormpath (pairFirst x)) f)
                                                              (and (<= (pairFirst (pairSecond x)) a) (<= b (pairSecond (pairSecond x))))))
                                                ev))
                            ((some x) (some (pair t (pairSecond x))))
                            (none none)))))
                none (listReverse (listSort whole)))))))))

fn seenReceipt op: j/Json turn: j/Json id: String -> j/Json
  (let [base (list (pair "id" (j/jstr id)) (pair "op" (optionOr (jget op "op") (j/jstr ""))) (pair "status" (j/jstr "seen"))
                   (pair "seenTurn" turn)
                   (pair "message" (j/jstr (str "identical to the step of turn " (pyStr turn) ", whose receipt is whole in the transcript; not run again"))))
        extra (map (fn [k] (pair k (j/jstr (pyStr (jgetOr op k))))) (filter (fn [k] (truthyAt op k)) (list "file" "path")))]
    (j/jobj (listAppend base extra)))

fn lastGateLine out: (List String) tail: (List String) -> String
  (mt (listHead (filter (fn [ln] (stringStartsWith? ln "(:gate ")) (listReverse out)))
    ((some ln) ln)
    (none (optionOr (listLast tail) "")))

fn failureSignatures receipts: (List j/Json) gateResults: (List j/Json) -> (List String)
  (let [status (fn [r] (mt (strAt r "status") ((some s) (or (= s "rejected") (= s "failed"))) (none false)))
        own (map (fn [r] (joinSep (filter (fn [x] (not (stringEmpty? x)))
                                    (list (getDefault r "op" "") (lstripColons (pyStr (jgetOr r "error")))
                                          (pyStr (let [v (firstTruthy r (list "file" "path"))] (if (pyTruthy v) v (j/jstr ""))))))
                              " "))
               (filter (fn [r] (and (status r) (and (truthyAt r "error") (not (truthyAt r "needsConfirm"))))) receipts))
        runs (listAppend gateResults (fold (fn [acc r] (listAppend acc (items (jgetOr r "gateRuns")))) (list) receipts))
        gates (map (fn [g]
                     (let [out (filter (fn [ln] (not (stringEmpty? ln))) (map pyStrip (pySplitLines (strOr g "stdout"))))
                           tail (pySplitLines (gateTail g))]
                       (pyStrip (str "gate \"" (escVal (optionOr (jget g "cmd") (j/jstr ""))) "\" " (gateOutcome g) " " (lastGateLine out tail)))))
                (filter (fn [g] (not (isZero (jgetOr g "exit")))) runs))]
    (dedupe (listAppend own gates)))

fn coreDelta before: j/Json now: j/Json -> j/Json
  (let [d (fn [k] (j/jint (- (jint (jgetOr now k)) (jint (jgetOr before k)))))]
    (j/jobj (list (pair "calls" (d "calls")) (pair "cases" (d "cases"))
                  (pair "sec" (j/jfloat (pyRound (- (jnum (jgetOr now "sec")) (jnum (jgetOr before "sec"))) 4)))
                  (pair "built" (d "built")))))

fn coreStatsLine delta: j/Json -> String
  (str "(:coreHost :calls " (pyStr (jgetOr delta "calls")) " :cases " (pyStr (jgetOr delta "cases")) " :sec "
    (pyStr (jgetOr delta "sec")) " :built " (pyStr (jgetOr delta "built")) ")\n")


fn formEndLoop s: String i: Int64 depth: Int64 inStr: Bool -> Int64
  (if (>= i (stringLength s))
    (stringLength s)
    (let [b (at1 s i)]
      (cond
        (inStr (cond ((= b "\\") (formEndLoop s (+ i 2) depth true))
                     ((= b "\"") (formEndLoop s (+ i 1) depth false))
                     (else (formEndLoop s (+ i 1) depth true))))
        ((= b "\"") (formEndLoop s (+ i 1) depth true))
        ((= b "(") (formEndLoop s (+ i 1) (+ depth 1) false))
        ((= b ")") (if (= depth 1) (+ i 1) (formEndLoop s (+ i 1) (- depth 1) false)))
        (else (formEndLoop s (+ i 1) depth false)))))

fn byteFormEnd s: String start: Int64 -> Int64
  (min (formEndLoop s start 0 false) (stringLength s))

fn formEnd text: String start: Int64 -> Int64
  (let [b (c/charIndex text (stringLength text) 0 start)]
    (c/charLen (sub text 0 (byteFormEnd text b))))

fn sitePath path: j/Json root: j/Json -> String
  (let [p (if (pyTruthy path) (pyStr path) "")
        r (if (pyTruthy root) (pyStr root) "")]
    (pyNormpath (if (and (isAbs p) (not (stringEmpty? r))) (pyRelpath p r) p)))

fn strBodyEnd s: String j: Int64 -> (Option Int64)
  (cond
    ((>= j (stringLength s)) none)
    ((= (at1 s j) "\"") (some j))
    ((= (at1 s j) "\\") (if (and (< (+ j 1) (stringLength s)) (!= (at1 s (+ j 1)) "\n")) (strBodyEnd s (+ j 2)) none))
    (else (strBodyEnd s (+ j 1))))

fn atValues s: String p: Int64 acc: (List String) -> (List String)
  (mt (stringIndexOf (sub s p (stringLength s)) "(")
    (none (listReverse acc))
    ((some k)
      (let [a (+ p k)
            i (skipWhile s (+ a 1) pySpace)
            j (+ i 3)
            q (skipWhile s j pySpace)]
        (if (and (litAt s i ":at") (> q j) (= (at1 s q) "\""))
          (mt (strBodyEnd s (+ q 1))
            ((some e) (atValues s (+ e 1) (cons (sub s (+ q 1) e) acc)))
            (none (atValues s (+ a 1) acc)))
          (atValues s (+ a 1) acc)))))

fn rpartColon s: String -> (Pair String String)
  (let [k (backWhile s (stringLength s) (fn [b] (!= b ":")))]
    (if (= k 0) (pair "" s) (pair (sub s 0 (- k 1)) (sub s k (stringLength s)))))

fn possibleOpen s: String p: Int64 -> (Option Int64)
  (mt (stringIndexOf (sub s p (stringLength s)) ":possible")
    (none none)
    ((some k)
      (let [a (+ p k)
            j (+ a 9)
            q (skipWhile s j pySpace)]
        (if (and (> q j) (= (at1 s q) "(")) (some q) (possibleOpen s (+ a 1))))))

fn possibleSitesOf receipt: j/Json root: j/Json -> (List (Pair String Int64))
  (let [op (strAt receipt "op")]
    (if (not (or (= op (some "observe")) (= op (some "run"))))
      (list)
      (let [text (pyStr (let [v (firstTruthy receipt (list "stdout" "out"))] (if (pyTruthy v) v (j/jstr ""))))]
        (mt (stringIndexOf text "(:observe :dim callers")
          (none (list))
          ((some head)
            (let [body (sub text head (byteFormEnd text head))]
              (mt (possibleOpen body 0)
                (none (list))
                ((some o)
                  (fold (fn [acc at]
                          (let [pl (rpartColon (specUnescape at))]
                            (if (and (not (stringEmpty? (pairFirst pl))) (allDigits (pairSecond pl)))
                              (listAppend acc (list (pair (sitePath (j/jstr (pairFirst pl)) root) (optionOr (stringToInt64 (pairSecond pl)) 0))))
                              acc)))
                    (list) (atValues (sub body o (byteFormEnd body o)) 0 (list)))))))))))

fn readCovers op: j/Json receipt: j/Json root: j/Json -> (Option Cover)
  (let [status (strAt receipt "status")]
    (if (or (!= (strAt receipt "op") (some "read")) (not (or (= status (some "ok")) (= status (some "seen")))))
      none
      (let [path (sitePath (let [v (firstTruthy receipt (list "file"))] (if (pyTruthy v) v (jgetOr op "file"))) root)
            span (jgetOr receipt "span")]
        (cond
          ((pyTruthy span)
            (let [xs (items span)]
              (mt (pyInt (optionOr (listGet xs 0) (j/jnull)))
                ((some a) (mt (pyInt (optionOr (listGet xs 1) (j/jnull))) ((some b) (some (coverOf path a (some b)))) (none none)))
                (none none))))
          ((!= status (some "seen")) none)
          (else
            (let [start (strOr op "start")
                  end (strOr op "end")]
              (cond
                ((and (allDigits start) (allDigits end))
                  (some (coverOf path (optionOr (stringToInt64 start) 0) (stringToInt64 end))))
                ((not (or (not (stringEmpty? start)) (not (stringEmpty? end)) (truthyAt op "symbol") (truthyAt op "anchor")))
                  (some (coverOf path 1 none)))
                (else none))))))))

fn pathCharB b: String -> Bool
  (or (c/isWordByte b) (= b ".") (= b "/") (= b "-"))

fn suffixesOf path: String -> (List String)
  (let [parts (stringSplit path "/")]
    (map (fn [i] (joinSep (listDrop parts i) "/")) (range 0 (listLength parts))))

fn siteNamed site: (Pair String Int64) text: String -> Bool
  (let [tail (str ":" (stringFromInt64 (pairSecond site)))
        sufs (map (fn [s] (str s tail)) (suffixesOf (pairFirst site)))
        n (stringLength text)]
    (listAny? (fn [p]
                (and (or (= p 0) (not (pathCharB (at1 text (- p 1)))))
                     (listAny? (fn [s] (and (litAt text p s) (not (isDigitB (at1 text (+ p (stringLength s))))))) sufs)))
      (range 0 (+ n 1))))

fn openPossible sites: (List (Pair (Pair String Int64) Bool)) -> (List (Pair String Int64))
  (map pairFirst (filter pairSecond sites))

fn findingsRun deliver: (Option String) findings: (List String) -> Bool
  (or (= deliver (some "findings")) (and (none? deliver) (not (listEmpty? findings))))

fn possibleSiteList sites: (List (Pair String Int64)) -> String
  (str "(" (joinSep (map (fn [s] (str "\"" (esc (pairFirst s)) ":" (stringFromInt64 (pairSecond s)) "\"")) sites) " ") ")")

fn possibleNotice sites: (List (Pair String Int64)) -> String
  (let [shown (listTake sites 10)
        more (- (listLength sites) (listLength shown))]
    (str "(:openPossible :sites " (possibleSiteList shown) (if (> more 0) (str " :more " (stringFromInt64 more)) "")
      " :ask \"observe callers listed these :possible sites and no read or finding has decided them since; "
      "only reading a site decides whether it is a call: read each one, then keep it as a caller or rule it out "
      "in a (:findings (:claim ...)) that names its file:line, then (:done)\")"))


fn hiddenNameOk s: String -> Bool
  (and (> (stringLength s) 0)
       (let [b (at1 s 0)] (or (= b "_") (and (>= b "a") (<= b "z")) (and (>= b "A") (<= b "Z"))))
       (= (skipWhile s 0 c/isWordByte) (stringLength s)))

fn hiddenVars raw: String -> (List String)
  (filter hiddenNameOk (splitWs raw 0 (list)))

fn splitWs s: String i: Int64 acc: (List String) -> (List String)
  (let [a (skipWhile s i pySpace)
        e (skipWhile s a (fn [b] (not (pySpace b))))]
    (if (>= a (stringLength s)) (listReverse acc) (splitWs s e (cons (sub s a e) acc))))

fn ! hiddenEnv! -> (List (Pair String String))
  (map (fn [n] (pair n (optionOr (envGet n) ""))) (hiddenVars (optionOr (envGet "ASL_EVAL_HIDDEN_VARS") "")))

fn refersVar w: String name: String -> Bool
  (listAny? (fn [lead]
              (listAny? (fn [p] (let [e (+ p (stringLength (str lead name)))]
                                  (and (litAt w p (str lead name)) (or (>= e (stringLength w)) (not (c/isWordByte (at1 w e)))))))
                (range 0 (stringLength w))))
    (list "$" "${"))

fn hiddenTouched rel: String root: String hidden: (List (Pair String String)) -> Bool
  (if (listEmpty? hidden)
    false
    (or (listAny? (fn [h] (refersVar rel (pairFirst h))) hidden)
        (let [dirs (filter (fn [d] (not (stringEmpty? d))) (map pairSecond hidden))]
          (and (not (listEmpty? dirs)) (c/hiddenPath rel dirs root)))))

fn setEnd pat: String i: Int64 -> Int64
  (let [j0 (if (= (at1 pat i) "!") (+ i 1) i)
        j1 (if (= (at1 pat j0) "]") (+ j0 1) j0)]
    (mt (stringIndexOf (sub pat j1 (stringLength pat)) "]") ((some k) (+ j1 k)) (none -1)))

fn inSet set: String b: String -> Bool
  (let [n (stringLength set)]
    (listAny? (fn [i] (if (and (< (+ i 2) n) (= (at1 set (+ i 1)) "-"))
                        (and (>= b (at1 set i)) (<= b (at1 set (+ i 2))))
                        (= b (at1 set i))))
      (range 0 n)))

fn fnmatch pat: String pi: Int64 name: String ni: Int64 -> Bool
  (let [pn (stringLength pat)
        nn (stringLength name)]
    (if (>= pi pn)
      (= ni nn)
      (let [p (at1 pat pi)]
        (cond
          ((= p "*") (listAny? (fn [k] (fnmatch pat (+ pi 1) name k)) (range ni (+ nn 1))))
          ((= p "?") (and (< ni nn) (fnmatch pat (+ pi 1) name (+ ni 1))))
          ((and (= p "[") (>= (setEnd pat (+ pi 1)) 0))
            (let [e (setEnd pat (+ pi 1))
                  neg (= (at1 pat (+ pi 1)) "!")
                  body (sub pat (if neg (+ pi 2) (+ pi 1)) e)]
              (and (< ni nn) (!= (inSet body (at1 name ni)) neg) (fnmatch pat (+ e 1) name (+ ni 1)))))
          (else (and (< ni nn) (= p (at1 name ni)) (fnmatch pat (+ pi 1) name (+ ni 1))))))))

fn hasMagic s: String -> Bool
  (or (stringContains? s "*") (stringContains? s "?") (stringContains? s "["))

fn ! entries! dir: String -> (List String)
  (resultOr (dirList dir) (list))

fn ! isDir! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isDir) ((err _) false))

fn ! isFile! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isFile) ((err _) false))

fn relJoin a: String b: String -> String
  (if (stringEmpty? a) b (str a "/" b))

fn ! walkAll! root: String rel: String -> (List String)
  (fold (fn [acc name]
          (let [r (relJoin rel name)]
            (listAppend (cons r acc) (if (isDir! (pathJoin root r)) (walkAll! root r) (list)))))
    (list) (filter (fn [nm] (not (stringStartsWith? nm "."))) (entries! (pathJoin root (if (stringEmpty? rel) "." rel)))))

fn ! globFrom! root: String bases: (List String) comps: (List String) -> (List String)
  (if (listEmpty? comps)
    bases
    (let [comp (c/firstOf comps)
          rest (c/restOf comps)
          last (listEmpty? rest)
          dirOf (fn [b] (pathJoin root (if (stringEmpty? b) "." b)))
          next (cond
                 ((= comp "**")
                   (fold (fn [acc b] (if (or (stringEmpty? b) (isDir! (dirOf b)))
                                       (listAppend acc (cons b (walkAll! root b)))
                                       acc))
                     (list) bases))
                 ((hasMagic comp)
                   (fold (fn [acc b]
                           (listAppend acc (map (fn [nm] (relJoin b nm))
                                             (filter (fn [nm] (and (or (stringStartsWith? comp ".") (not (stringStartsWith? nm ".")))
                                                                   (fnmatch comp 0 nm 0)))
                                               (if (or (stringEmpty? b) (isDir! (dirOf b))) (entries! (dirOf b)) (list))))))
                     (list) bases))
                 (else
                   (filter (fn [r] (if last (fileExists? (pathJoin root r)) (isDir! (pathJoin root r))))
                     (map (fn [b] (relJoin b comp)) bases))))]
      (globFrom! root next rest)))

fn ! ownsHits! root: String pat: String -> (List String)
  (if (hasMagic pat)
    (let [comps (stringSplit pat "/")
          hits (globFrom! root (list "") (filter (fn [x] (not (stringEmpty? x))) comps))]
      (listSort (dedupe (map (fn [h] (if (and (stringEndsWith? pat "/") (not (stringEmpty? h))) (str h "/") h)) hits))))
    (list pat))

fn wordRunEnd s: String i: Int64 -> Int64
  (skipWhile s i pathCharB)

fn lastSegMatch seg: String -> (Option Int64)
  (let [n (stringLength seg)
        cands (filter (fn [k] (and (> k 0) (= (at1 seg k) ".") (< (+ k 1) n) (isAlnumB (at1 seg (+ k 1)))))
                (listReverse (range 0 n)))]
    (if (or (= n 0) (= (at1 seg 0) "."))
      none
      (fold (fn [acc k]
              (if (some? acc) acc
                (let [e (skipWhile seg (+ k 1) isAlnumB)]
                  (if (or (>= e n) (not (or (c/isWordByte (at1 seg e)) (= (at1 seg e) "-")))) (some e) none))))
        none cands)))

fn namedIn run: String -> (Option String)
  (let [segs (stringSplit run "/")
        n (listLength segs)
        okDirs (fn [k] (listAll? (fn [s] (not (stringEmpty? s))) (listTake segs k)))
        offs (fn [k] (fold (fn [acc s] (+ acc (+ (stringLength s) 1))) 0 (listTake segs k)))]
    (fold (fn [acc k]
            (if (some? acc) acc
              (if (not (okDirs k)) none
                (mt (lastSegMatch (optionOr (listGet segs k) ""))
                  ((some e) (some (sub run 0 (+ (offs k) e))))
                  (none none)))))
      none (listReverse (range 0 n))))

fn namedPaths task: String i: Int64 acc: (List String) -> (List String)
  (if (>= i (stringLength task))
    (listReverse acc)
    (if (and (pathCharB (at1 task i)) (or (= i 0) (not (pathCharB (at1 task (- i 1))))))
      (let [e (wordRunEnd task i)]
        (mt (namedIn (sub task i e))
          ((some m) (namedPaths task e (cons m acc)))
          (none (namedPaths task e acc))))
      (namedPaths task (+ i 1) acc)))

fn insideRoot rel: String -> Bool
  (let [n (pyNormpath rel)]
    (and (not (or (= n "..") (stringStartsWith? n "../")))
         (!= (c/firstOf (stringSplit n "/")) ".git")))

fn ! prefetchPaths! task: (Option String) owns: (List String) root: String hidden: (List (Pair String String)) -> (List String)
  (let [found (if (listEmpty? owns)
                (filter (fn [m] (isFile! (pathJoin root m))) (namedPaths (optionOr task "") 0 (list)))
                (fold (fn [acc pat]
                        (listAppend acc (map (fn [h] (pyRelpath (pathJoin root h) root))
                                          (filter (fn [h] (isFile! (pathJoin root h))) (ownsHits! root pat)))))
                  (list) owns))]
    (filter (fn [rel] (and (insideRoot rel) (and (not (stringStartsWith? rel ".git/"))
                                                 (and (not (hiddenTouched rel root hidden)) (not (c/harnessPath rel root))))))
      (dedupe found)))

fn itemAt s: String p: Int64 -> (Option (Pair (List String) Int64))
  (let [h "(:item :name \""]
    (if (not (litAt s p h))
      none
      (mt (strBodyEnd s (+ p (stringLength h)))
        (none none)
        ((some e)
          (let [name (sub s (+ p (stringLength h)) e)
                k0 (+ e (stringLength "\" :kind \""))
                k1 (skipWhile s k0 c/isWordByte)
                s0 (+ k1 (stringLength "\" :start "))
                s1 (digitsAt s s0)
                e0 (+ s1 (stringLength " :end "))
                e1 (digitsAt s e0)]
            (if (and (litAt s e "\" :kind \"") (> k1 k0) (litAt s k1 "\" :start ") (> s1 s0) (litAt s s1 " :end ") (> e1 e0) (litAt s e1 ")"))
              (some (pair (list name (sub s k0 k1) (sub s s0 s1) (sub s e0 e1)) (+ e1 1)))
              none))))))

fn itemsIn s: String p: Int64 acc: (List (List String)) -> (List (List String))
  (mt (stringIndexOf (sub s p (stringLength s)) "(:item :name \"")
    (none (listReverse acc))
    ((some k) (mt (itemAt s (+ p k))
                ((some r) (itemsIn s (pairSecond r) (cons (pairFirst r) acc)))
                (none (itemsIn s (+ (+ p k) 1) acc)))))

fn prefetchWholeBytes -> Int64
  8192

fn ! prefetchEntry! rel: String root: String outline: (fn [String] -> (Pair Int64 String)) -> (Option (Pair String String))
  (let [full (pathJoin root rel)
        size (resultOr (fileSize full) 0)]
    (if (< size (prefetchWholeBytes))
      (let [text (resultOr (fileReadString full) "")
            lines (+ (stringCountChar text "\n") (if (stringEndsWith? text "\n") 0 1))]
        (if (stringContains? text "\u0000")
          none
          (some (pair (str "(:file \"" (esc rel) "\" :lines (1 " (stringFromInt64 lines) ") :content \"" (esc text) "\")") "file"))))
      (let [res (outline (str "(:intel :op outline :file \"" (esc rel) "\")"))
            its (itemsIn (pairSecond res) 0 (list))]
        (if (or (!= (pairFirst res) 0) (listEmpty? its))
          none
          (let [ol (joinSep (map (fn [it] (str (nth2 it 2) "-" (nth2 it 3) " " (nth2 it 1) " " (nth2 it 0))) its) "\n")]
            (some (pair (str "(:outline \"" (esc rel) "\" :items \"" (esc ol) "\")") "outline")))))))

fn nth2 xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

; (:m :tags (cache budget))
fn ! prefetchBlock! task: (Option String) owns: (List String) root: String cap: Int64 beforeTurn: Int64 hidden: (List (Pair String String)) outline: (fn [String] -> (Pair Int64 String)) -> (Pair String (List (Pair String String)))
  (let [picked (fold (fn [st rel]
                       (mt (prefetchEntry! rel root outline)
                         (none st)
                         ((some ek)
                           (let [len (c/charLen (pairFirst ek))
                                 used (pairFirst (pairFirst st))]
                             (if (> (+ used len) cap)
                               st
                               (pair (pair (+ used len) (listAppend (pairSecond (pairFirst st)) (list (pairFirst ek))))
                                 (listAppend (pairSecond st) (list (pair (pairSecond ek) rel)))))))))
                 (pair (pair 0 (list)) (list)) (prefetchPaths! task owns root hidden))
        entries (pairSecond (pairFirst picked))]
    (if (listEmpty? entries)
      (pair "" (list))
      (pair (str "prefetched before turn " (stringFromInt64 beforeTurn) ", so no read is needed for them: small files whole, larger ones as outlines "
              "(start-end kind name) to read by :symbol or :start/:end; a file written since differs, so read it again before quoting :old"
              "\n(:prefetch " (joinSep entries " ") ")")
        (pairSecond picked))))

fn phaseOfOp op: String -> (Option String)
  (cond
    ((listContains? (list "read" "query" "tree" "observe" "check" "outline" "intel" "gitDiff" "gitLog" "gitShow") op) (some "scout"))
    ((= op "note") (some "plan"))
    ((= op "gate") (some "grade"))
    (else none))

; (:m :tags (journal))
fn receiptPhase receipt: j/Json -> (Option String)
  (cond
    ((truthyAt receipt "persisted") (some "implement"))
    ((= (strAt receipt "type") (some "findings")) (some "scout"))
    ((= (strAt receipt "status") (some "ok")) (mt (strAt receipt "op") ((some o) (phaseOfOp o)) (none none)))
    (else none))

fn deliverOfMode mode: String -> String
  (cond ((= mode "scout") "findings") ((= mode "plan") "plan") ((= mode "implement") "patch") ((= mode "grade") "verdict") (else mode))

fn taskHintLines modeHint: (Option String) intent: (Option String) -> String
  (str (mt modeHint ((some m) (if (stringEmpty? m) "" (str "expected deliverable: " (deliverOfMode m) "\n"))) (none ""))
       (mt intent ((some i) (if (stringEmpty? i) "" (str "starting intent: " i "\n"))) (none "")))

fn unmetForm deliver: (Option String) reached: Bool wrote: Bool findings: (List String) -> String
  (let [d (optionOr deliver "")
        why (cond
              ((not reached) "")
              ((and (= d "patch") (not wrote)) "nothing is written; write the change, restate (:intent ...), or (:escalate :reason s)")
              ((and (= d "findings") (listEmpty? findings)) "no (:findings ...) yet; report them, restate (:intent ...), or (:escalate :reason s)")
              (else ""))]
    (if (stringEmpty? why) "" (str "(:unmet :deliver :" d " :reason \"" why "\")")))


fn specCheckSystem -> String
  (str "You check a finished change against its task. "
       "You may count as evidence receipts that show an effect, such as a file or directory "
       "absent after a run, a gate's asserts, or a run's output. "
       "Reply with one form: "
       "(:verdict :met true) or (:verdict :met false :missing (\"requirement not done\" ...)).")

fn findingsCheckSystem -> String
  (str "You check findings an agent reported against its task and the evidence of its session. "
       "Reply with one form: (:verdict :met true) or "
       "(:verdict :met false :missing (\"...\" ...)). "
       "The missing items name what the findings lack or overstate: a requirement of the task not answered, "
       "a site not covered when the task asks for every one, a claim broader than its evidence, "
       "or a number with no receipt that computed it.")

fn advisorSystem -> String
  (str "You advise a coding agent that is stuck. Read the summary and reply with one form "
       "(:advice :next \"one concrete next step\" :why \"...\" [:avoid \"what to stop doing\"])")

fn specCheckDiffMax -> Int64
  60000

fn specUnescape s: String -> String
  (stringReplace (stringReplace s "\\\"" "\"") "\\\\" "\\")

fn fileMode m: Int64 -> String
  (if (= (& m 73) 0) "100644" "100755")

fn filePatchNew rel: String data: String mode: Int64 -> String
  (let [lines (if (stringEmpty? data) (list) (pySplitLinesKeep data))
        n (listLength lines)
        head (str "diff --git a/" rel " b/" rel "\nnew file mode " (fileMode mode) "\n")]
    (if (= n 0)
      head
      (str head "--- /dev/null\n+++ b/" rel "\n@@ -0,0 +" (if (= n 1) "1" (str "1," (stringFromInt64 n))) " @@\n"
        (c/joinAll (map (fn [l] (if (stringEndsWith? l "\n") (str "+" l) (str "+" l "\n\\ No newline at end of file\n"))) lines)))))

fn universal s: String -> String
  (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n")

fn ! git! root: String args: (List String) -> (Result cp/ProcessOutput String)
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" args) root) 120000))
    ((ok out) (ok out))
    ((err e) (err (mt e
                    ((cp/notFound b) (str "git not found: " b))
                    ((cp/timeout ms) (str "git timed out after " (stringFromInt64 ms) " ms"))
                    ((cp/permissionDenied p) (str "git not executable: " p))
                    ((cp/executionFailed code m) (str "git failed: " m))))))

fn utf8Lead b: Int64 -> Int64
  (cond ((< b 128) 1) ((< b 192) 0) ((< b 224) 2) ((< b 240) 3) (else 4))

fn leadBack bs: Bytes j: Int64 -> Int64
  (if (and (>= j 0) (and (>= (bytesGet bs j) 128) (< (bytesGet bs j) 192))) (leadBack bs (- j 1)) j)

fn cutUtf8 s: String n: Int64 -> String
  (let [bs (stringToBytes s)
        j (leadBack bs (- n 1))]
    (if (and (>= j 0) (> (+ j (max 1 (utf8Lead (bytesGet bs j)))) n)) (sub s 0 j) (sub s 0 n)))

fn ! diffPart! root: String startHead: (Option String) rel: String -> (Result String String)
  (mt (git! root (list "ls-files" "--error-unmatch" "--" rel))
    ((err e) (err e))
    ((ok ls)
      (let [full (pyNormpath (pathJoin root rel))
            start (optionOr startHead "")]
        (if (and (= ls.exitCode 0) (not (stringEmpty? start)))
          (mt (git! root (list "diff" start "--" rel))
            ((err e) (err e))
            ((ok d) (ok (if (= d.exitCode 0) (universal (if (stringEmpty? d.stdout) "" (str d.stdout "\n"))) ""))))
          (if (isFile! full)
            (mt (fileReadString full)
              ((err e) (err e))
              ((ok data) (ok (filePatchNew rel data (mt (fileStat full) ((ok st) st.mode) ((err _) 0))))))
            (ok ""))))))

fn ! specCheckDiff! root: String startHead: (Option String) written: (List String) -> (Result String String)
  (let [rels (dedupe (map (fn [p] (if (isAbs p) (pyRelpath p root) (pyNormpath p))) (filter (fn [p] (not (stringEmpty? p))) written)))
        parts (fold (fn [acc rel] (mt acc ((err e) (err e)) ((ok xs) (mt (diffPart! root startHead rel) ((ok d) (ok (listAppend xs (list d)))) ((err e) (err e))))))
                (ok (list)) rels)]
    (mt parts
      ((err e) (err e))
      ((ok xs)
        (let [text (joinSep (filter (fn [p] (not (stringEmpty? p))) xs) "\n")]
          (ok (if (<= (stringLength text) (specCheckDiffMax)) text
                (str (cutUtf8 text (specCheckDiffMax)) "\n[[spec-check diff cut at 60000 bytes]]\n")))))))

fn verdictStart text: String p: Int64 -> (Option Int64)
  (mt (stringIndexOf (sub text p (stringLength text)) "(")
    (none none)
    ((some k)
      (let [a (+ p k)
            i (skipWhile text (+ a 1) pySpace)
            e (+ i 8)]
        (if (and (litAt text i ":verdict") (or (>= e (stringLength text)) (not (c/isWordByte (at1 text e)))))
          (some a)
          (verdictStart text (+ a 1))))))

fn metAt form: String p: Int64 -> (Option Bool)
  (mt (stringIndexOf (sub form p (stringLength form)) ":met")
    (none none)
    ((some k)
      (let [a (+ p k 4)
            q (skipWhile form a pySpace)]
        (cond
          ((and (> q a) (litAt form q "true")) (some true))
          ((and (> q a) (litAt form q "false")) (some false))
          (else (metAt form (+ (+ p k) 1)))))))

fn missingWalk form: String i: Int64 depth: Int64 acc: (List String) -> (Pair Int64 (List String))
  (if (or (>= i (stringLength form)) (= depth 0))
    (pair i acc)
    (let [b (at1 form i)]
      (if (= b "\"")
        (mt (strBodyEnd form (+ i 1))
          (none (pair i acc))
          ((some e) (missingWalk form (+ e 1) depth (if (= depth 1) (listAppend acc (list (specUnescape (sub form (+ i 1) e)))) acc))))
        (missingWalk form (+ i 1) (cond ((= b "(") (+ depth 1)) ((= b ")") (- depth 1)) (else depth)) acc))))

fn missingLists form: String p: Int64 acc: (List String) -> (List String)
  (mt (stringIndexOf (sub form p (stringLength form)) ":missing")
    (none acc)
    ((some k)
      (let [a (+ p k)
            q (skipWhile form (+ a 8) pySpace)]
        (if (= (at1 form q) "(")
          (let [r (missingWalk form (+ q 1) 1 acc)]
            (missingLists form (pairFirst r) (pairSecond r)))
          (missingLists form (+ a 1) acc)))))

fn parseSpecVerdict text: (Option String) -> (Option (Pair Bool (List String)))
  (mt text
    (none none)
    ((some t)
      (if (stringEmpty? (pyStrip t))
        none
        (mt (verdictStart t 0)
          (none none)
          ((some a)
            (let [close (backWhile t (stringLength t) (fn [b] (!= b ")")))]
              (if (<= close (+ a 1))
                none
                (let [form (sub t a close)]
                  (mt (metAt form 0)
                    (none none)
                    ((some met)
                      (let [missing (missingLists form 0 (list))]
                        (if (and (not met) (listEmpty? missing)) none (some (pair met missing))))))))))))))

fn countsTry s: String q: Int64 -> (Option (Pair (Pair String String) Int64))
  (let [a (+ q 8)
        a1 (skipWhile s a pySpace)
        d1 (digitsAt s a1)
        f0 (skipWhile s d1 pySpace)
        f1 (+ f0 7)
        g0 (skipWhile s f1 pySpace)
        g1 (digitsAt s g0)]
    (if (and (or (= (at1 s q) ":") (pySpace (at1 s q))) (litAt s (+ q 1) "asserts")
             (> a1 a) (> d1 a1) (> f0 d1) (litAt s f0 ":failed") (> g0 f1) (> g1 g0))
      (some (pair (pair (sub s a1 d1) (sub s g0 g1)) g1))
      none))

fn countsLazy s: String q: Int64 lineEnd: Int64 -> (Option (Pair (Pair String String) Int64))
  (if (or (> q lineEnd) (>= q (stringLength s)))
    none
    (mt (countsTry s q) ((some r) (some r)) (none (countsLazy s (+ q 1) lineEnd))))

fn countsScan s: String p: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (let [n (stringLength s)]
    (mt (stringIndexOf (sub s p n) "(:gate")
      (none (listReverse acc))
      ((some k)
        (let [a (+ p k)
              wb (or (>= (+ a 6) n) (not (c/isWordByte (at1 s (+ a 6)))))
              lineEnd (optionOr (optionMap (fn [x] (+ (+ a 6) x)) (stringIndexOf (sub s (+ a 6) n) "\n")) n)]
          (mt (if wb (countsLazy s (+ a 6) lineEnd) none)
            ((some r) (countsScan s (pairSecond r) (cons (pairFirst r) acc)))
            (none (countsScan s (+ a 1) acc)))))))

fn countsRegex1 s: String -> (List (Pair String String))
  (countsScan s 0 (list))

fn digestLines receipts: (List j/Json) -> (List String)
  (map digestLine (filter (fn [r] (mt r ((j/jobj _) true) (_ false))) receipts))

fn trimStart lens: (List Int64) budget: Int64 -> Int64
  (let [total (listSum (map (fn [l] (+ l 1)) lens))]
    (pairFirst (fold (fn [st l] (if (> (pairSecond st) budget) (pair (+ (pairFirst st) 1) (- (pairSecond st) (+ l 1))) st))
                 (pair 0 total) lens)))

fn specGateLine gcmd: String lastGates: j/Json -> String
  (let [seen (jgetOr lastGates gcmd)
        g (mt seen ((j/jarr xs) (optionOr (listGet xs 1) (j/jnull))) (_ (if (pyTruthy seen) seen (j/jobj (list)))))
        isDict (mt g ((j/jobj _) true) (_ false))
        outcome (cond
                  ((and isDict (truthyAt g "timeout")) (gateOutcome g))
                  ((and isDict (not (isNone (jgetOr g "exit")))) (str ":exit " (pyStr (jgetOr g "exit"))))
                  (else ":exit not run"))
        out (if isDict (strOr g "stdout") "")
        counts (if (stringEmpty? out) (list)
                 (let [c1 (countsRegex1 out)] (if (listEmpty? c1) (anchoredCounts out) c1)))]
    (str "(:gate :cmd \"" (esc gcmd) "\" " outcome (countsTail counts) ")"))

fn specCap -> Int64
  (+ (specCheckDiffMax) 12000)

fn specAssemble task: String diff: String unbacked: (List String) lines: (List String) start: Int64 gateLines: (List String) -> String
  (let [digest (if (listEmpty? lines) "(no receipts)"
                 (str (if (> start 0) (str "[" (stringFromInt64 start) " older receipt lines cut]\n") "") (joinSep (listDrop lines start) "\n")))]
    (str task "\n\nDiff of the written change:\n" (if (stringEmpty? diff) "(no diff)" diff)
      (if (listEmpty? unbacked) "" (str "\n\nclaims the agent made without a receipt:\n" (joinSep (map (fn [cl] (str "- \"" cl "\"")) unbacked) "\n")))
      "\n\nevidence digest, one line per receipt of this session, oldest first:\n" digest
      (if (listEmpty? gateLines) "" (str "\n" (joinSep gateLines "\n")))))

fn specShrink task: String diff: String unbacked: (List String) lines: (List String) st: Int64 gateLines: (List String) cap: Int64 -> String
  (let [txt (specAssemble task diff unbacked lines st gateLines)]
    (if (and (> (c/charLen txt) cap) (< st (listLength lines))) (specShrink task diff unbacked lines (+ st 1) gateLines cap) txt))

fn ! runSpecCheck! ask: (fn [String String String] -> (Result (Option String) String)) task: (Option String) root: String startHead: (Option String) written: (List String) unbacked: (List String) receipts: (List j/Json) gates: (List String) lastGates: j/Json -> (Result Review String)
  (mt (specCheckDiff! root startHead written)
    ((err e) (err e))
    ((ok diff)
      (let [gateLines (map (fn [g] (specGateLine g lastGates)) gates)
            lines (digestLines receipts)
            lens (map c/charLen lines)
            start0 (trimStart lens (- 12000 64))
            t (optionOr task "")
            cap (specCap)
            text0 (specAssemble t diff unbacked lines start0 gateLines)
            len0 (c/charLen text0)
            diff1 (if (and (> len0 cap) (not (stringEmpty? diff)))
                    (let [over (- len0 cap)
                          baseDiff (mt (stringIndexOf diff "\n[[spec-check diff cut") ((some k) (sub diff 0 k)) (none diff))
                          marker "\n[[spec-check diff cut]]\n"
                          room (max 0 (- (- (c/charLen baseDiff) over) (stringLength marker)))]
                      (if (> room 0) (str (charPrefix baseDiff room) marker) "(diff cut)\n"))
                    diff)
            text1 (specShrink t diff1 unbacked lines start0 gateLines cap)]
        (ok (askReviewer! ask (specCheckSystem) (charPrefix text1 cap))))))

fn observeTarget out: String -> String
  (let [dim (mt (stringIndexOf out ":dim")
              ((some k) (dimAt out k))
              (none none))
        sym (symbolIn out 0)]
    (joinSep (listAppend (mt dim ((some d) (list d)) (none (list))) (mt sym ((some s) (list s)) (none (list)))) " "))

fn dimAt s: String k: Int64 -> (Option String)
  (let [a (+ k 4)
        q (skipWhile s a pySpace)
        e (skipWhile s q c/isWordByte)]
    (if (and (> q a) (> e q))
      (some (sub s q e))
      (mt (stringIndexOf (sub s (+ k 1) (stringLength s)) ":dim") ((some k2) (dimAt s (+ (+ k 1) k2))) (none none))))

fn symbolIn s: String p: Int64 -> (Option String)
  (mt (stringIndexOf (sub s p (stringLength s)) ":symbol")
    (none none)
    ((some k)
      (let [a (+ (+ p k) 7)
            q (skipWhile s a pySpace)]
        (if (and (> q a) (= (at1 s q) "\""))
          (mt (strBodyEnd s (+ q 1)) ((some e) (some (sub s (+ q 1) e))) (none (symbolIn s (+ (+ p k) 1))))
          (symbolIn s (+ (+ p k) 1))))))

fn callersFrom s: String p: Int64 -> Bool
  (mt (stringIndexOf (sub s p (stringLength s)) ":dim")
    (none false)
    ((some k)
      (let [a (+ (+ p k) 4)
            q (skipWhile s a pySpace)
            e (+ q 7)]
        (if (and (> q a) (litAt s q "callers") (or (>= e (stringLength s)) (not (c/isWordByte (at1 s e)))))
          true
          (callersFrom s (+ (+ p k) 1))))))

fn callersAt s: String -> Bool
  (callersFrom s 0)

fn countGroupFrom s: String p: Int64 -> (Option String)
  (mt (stringIndexOf (sub s p (stringLength s)) ":count")
    (none none)
    ((some k)
      (let [a (+ (+ p k) 6)
            q (skipWhile s a pySpace)
            close (optionOr (optionMap (fn [x] (+ (+ q 1) x)) (stringIndexOf (sub s (+ q 1) (stringLength s)) ")")) -1)]
        (if (and (> q a) (= (at1 s q) "(") (> close q))
          (some (sub s (+ q 1) close))
          (countGroupFrom s (+ (+ p k) 1))))))

fn countPairs g: String p: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (mt (stringIndexOf (sub g p (stringLength g)) ":")
    (none acc)
    ((some k)
      (let [a (+ (+ p k) 1)
            w (skipWhile g a c/isWordByte)
            q (skipWhile g w pySpace)
            d (digitsAt g q)]
        (if (and (> w a) (> q w) (> d q))
          (countPairs g d (cons (pair (sub g a w) (sub g q d)) acc))
          (countPairs g a acc)))))

fn squashFrom s: String i: Int64 acc: (List String) -> String
  (if (>= i (stringLength s))
    (c/joinAll (listReverse acc))
    (if (pySpace (at1 s i))
      (squashFrom s (skipWhile s i pySpace) (cons " " acc))
      (squashFrom s (+ i 1) (cons (at1 s i) acc))))

fn squash s: String -> String
  (squashFrom s 0 (list))

fn digestLine r: j/Json -> String
  (let [opv (let [v (firstTruthy r (list "op" "type"))] (if (pyTruthy v) (pyStr v) (if (truthyAt r "cmd") "gate" "")))
        out (strOr r "stdout")
        t0 (if (= opv "observe") (observeTarget out) "")
        t1 (if (stringEmpty? t0) (strOr (firstTruthyObj r (list "file" "path" "symbol" "query" "topic" "url" "cmd")) "v") t0)
        target (charPrefix (stringReplace t1 "\n" " ") 200)
        ex (jgetOr r "exit")
        counts (if (and (= opv "observe") (callersAt out))
                 (mt (countGroupFrom out 0)
                   ((some g) (let [ps (countPairs g 0 (list))
                                   get (fn [k] (fold (fn [acc p] (if (= (pairFirst p) k) (pairSecond p) acc)) "0" (listReverse ps)))]
                               (str " :count (" (joinSep (map (fn [k] (str ":" k " " (get k))) (list "calls" "possible" "excluded")) " ") ")")))
                   (none ""))
                 "")
        src (cond ((= opv "read") (jgetOr r "content")) ((= opv "run") (jgetOr r "stdout")) (else (j/jnull)))
        excerpt (if (pyTruthy src) (charPrefix (pyStrip (squash (pyStr src))) 100) "")]
    (str "(:receipt :id \"" (esc (strOr r "id")) "\" :op \"" (esc opv) "\""
      (if (stringEmpty? target) "" (str " :target \"" (esc target) "\""))
      (if (isNone ex) (str " :" (lstripColons (let [s (jgetOr r "status")] (if (pyTruthy s) (pyStr s) "ok")))) (str " :exit " (pyStr ex)))
      counts
      (if (stringEmpty? excerpt) "" (str " :excerpt \"" (esc excerpt) "\""))
      ")"))

fn firstTruthyObj r: j/Json keys: (List String) -> j/Json
  (j/jobj (list (pair "v" (firstTruthy r keys))))

fn evidenceDigest receipts: (List j/Json) cap: Int64 -> String
  (let [lines (digestLines receipts)
        start (trimStart (map c/charLen lines) (- cap 64))]
    (str (if (> start 0) (str "[" (stringFromInt64 start) " older receipt lines cut]\n") "") (joinSep (listDrop lines start) "\n")))

fn ! askReviewer! ask: (fn [String String String] -> (Result (Option String) String)) system: String userText: String -> Review
  (mt (ask "grade" system userText)
    ((err e) (reviewError (str "reviewer call failed: " (charPrefix e 200))))
    ((ok got)
      (mt got
        (none (reviewError "reviewer returned no reply"))
        ((some reply)
          (mt (parseSpecVerdict (some reply))
            ((some v) (reviewVerdict (pairFirst v) (pairSecond v)))
            (none (reviewError "reviewer reply unreadable")))))))

fn ! runFindingsCheck! ask: (fn [String String String] -> (Result (Option String) String)) task: (Option String) findings: (List String) receipts: (List j/Json) -> Review
  (let [f (joinSep findings "\n")
        digest (evidenceDigest receipts 12000)]
    (askReviewer! ask (findingsCheckSystem)
      (str "task:\n" (optionOr task "") "\n\nfindings as the agent wrote them:\n" (if (stringEmpty? f) "(no findings)" f) "\n\n"
        "evidence digest, one line per receipt of this session, oldest first:\n" (if (stringEmpty? digest) "(no receipts)" digest))))


fn wordEnd s: String i: Int64 -> Int64
  (skipWhile s i c/isWordByte)

fn advisorSkip why: (Option String) retries: (List (Pair String Int64)) parseDefectCount: Int64 -> String
  (let [w (optionOr why "")
        pre "one more "
        e (wordEnd w (stringLength pre))
        tail " miss escalates"
        rest (sub w (+ e (stringLength tail)) (stringLength w))
        matched (and (stringStartsWith? w pre) (> e (stringLength pre)) (litAt w e tail) (or (= rest "") (= rest "\n")))
        name (sub w (stringLength pre) e)
        count (fold (fn [acc p] (if (= (pairFirst p) name) (pairSecond p) acc)) 0 retries)]
    (cond
      ((and matched (= count 0)) (str name " retry cap reached with no " name " miss: a provider or retry limit, not the model"))
      ((and (= w "one more parse defect escalates") (= parseDefectCount 0))
        "parse-defect cap reached with no parse defect: a provider or retry limit, not the model")
      (else "")))

fn advisorGateOutput g: j/Json -> String
  (let [main (fold (fn [acc k] (if (stringEmpty? acc) (optionOr (strAt g k) "") acc)) "" (list "output" "stdout" "out" "tail"))
        er (optionOr (strAt g "stderr") "")]
    (joinSep (filter (fn [x] (not (stringEmpty? x))) (list main er)) "\n"))

fn advisorOpLine r: j/Json -> String
  (let [op (cond
             ((truthyAt r "op") (pyStr (jgetOr r "op")))
             ((and (truthyAt r "cmd") (has r "exit")) "gate")
             ((truthyAt r "type") (pyStr (jgetOr r "type")))
             (else "?"))
        target (let [v (firstTruthy r (list "file" "cmd" "path" "query" "symbol"))] (if (pyTruthy v) (pyStr v) ""))
        ex (jgetOr r "exit")
        outcome (str (if (isNone ex) (str ":" (let [s (jgetOr r "status")] (if (pyTruthy s) (pyStr s) "ok"))) (str ":exit " (pyStr ex)))
                  (if (truthyAt r "error") (str " " (pyStr (jgetOr r "error"))) ""))]
    (joinSep (filter (fn [x] (not (stringEmpty? x))) (list op (charPrefix target 120) outcome)) " "))

fn advisorSummaryMax -> Int64
  8000

fn advisorSummary task: (Option String) deliver: (Option String) why: (Option String) gates: (List String) lastGates: (List (Pair String (Pair Int64 j/Json))) written: (List String) receipts: (List j/Json) lastBrief: (Option String) -> String
  (let [lookup (fn [g] (fold (fn [acc p] (if (= (pairFirst p) g) (some (pairSecond p)) acc)) none (listReverse lastGates)))
        st (fold (fn [acc g]
                   (let [i (+ (listLength (pairFirst acc)) 1)
                         seen (lookup g)
                         ex (mt seen ((some s) (jgetOr (pairSecond s) "exit")) (none (j/jnull)))
                         line (str (stringFromInt64 i) " " g " :exit " (if (isNone ex) "not run" (pyStr ex)))
                         red (pairSecond acc)
                         red2 (mt seen
                                ((some s) (if (and (not (isNone ex)) (not (isZero ex))
                                                   (mt red ((some rs) (>= (pairFirst s) (pairFirst rs))) (none true)))
                                            (some s) red))
                                (none red))]
                     (pair (listAppend (pairFirst acc) (list line)) red2)))
             (pair (list) none) gates)
        gateLines (pairFirst st)
        tail (mt (pairSecond st)
               ((some rs)
                 (let [lines (map (fn [ln] (charPrefix ln 200)) (lastN (pySplitLines (advisorGateOutput (pairSecond rs))) 40))
                       body (charSuffix (joinSep lines "\n") 3000)]
                   (str "last red gate output (" (getDefault (pairSecond rs) "cmd" "") "), last " (stringFromInt64 (listLength lines)) " lines:\n" body "\n")))
               (none ""))
        ops (joinSep (map advisorOpLine (lastN receipts 8)) "\n")
        gatesText (if (listEmpty? gateLines) "(none declared)" (joinSep gateLines "\n"))
        writtenText (charPrefix (if (listEmpty? written) "(none)" (joinSep written " ")) 600)
        w (mt why ((some s) s) (none "None"))
        briefHead (if (stringContains? (optionOr why "") "parse defect") (str "last retry brief head: " (charPrefix (optionOr lastBrief "") 200) "\n") "")
        head (str "deliverable: " (let [d (optionOr deliver "")] (if (stringEmpty? d) "not stated" d)) "\nstuck because: " w "\n"
               briefHead "gates:\n" gatesText "\n" tail "files written: " writtenText "\nlast ops, oldest first:\n"
               (if (stringEmpty? ops) "(none)" ops) "\n")
        room (max (- (- (advisorSummaryMax) (c/charLen head)) 7) 0)]
    (charPrefix (str "task:\n" (charPrefix (optionOr task "") room) "\n\n" head) (advisorSummaryMax)))

fn adviceStart text: String p: Int64 -> (Option Int64)
  (mt (stringIndexOf (sub text p (stringLength text)) "(")
    (none none)
    ((some k)
      (let [a (+ p k)
            i (skipWhile text (+ a 1) pySpace)
            e (+ i 7)]
        (if (and (litAt text i ":advice") (or (>= e (stringLength text)) (not (c/isWordByte (at1 text e)))))
          (some a)
          (adviceStart text (+ a 1))))))

fn fieldIn form: String key: String p: Int64 -> (Option String)
  (let [k (str ":" key)]
    (mt (stringIndexOf (sub form p (stringLength form)) k)
      (none none)
      ((some off)
        (let [a (+ (+ p off) (stringLength k))
              q (skipWhile form a pySpace)]
          (if (and (> q a) (= (at1 form q) "\""))
            (mt (strBodyEnd form (+ q 1)) ((some e) (some (sub form (+ q 1) e))) (none (fieldIn form key (+ (+ p off) 1))))
            (fieldIn form key (+ (+ p off) 1)))))))

fn adviceField form: String key: String -> (Option String)
  (optionMap (fn [v] (charPrefix (pyStrip (specUnescape v)) 400)) (fieldIn form key 0))

fn parseAdvice text: (Option String) -> (Option AdviceForm)
  (mt text
    (none none)
    ((some t)
      (mt (adviceStart t 0)
        (none none)
        ((some a)
          (let [form (sub t a (stringLength t))
                next (adviceField form "next")]
            (mt next
              ((some n) (if (stringEmpty? n) none (some (adviceOf n (adviceField form "why") (adviceField form "avoid")))))
              (none none)))))))

fn ! askAdvisor! advise: (Option (fn [String String] -> (Result (Option String) String))) summary: String -> AdvisorResult
  (mt advise
    (none (advisorSkipped "provider has no advisor channel"))
    ((some f)
      (mt (f (advisorSystem) summary)
        ((err e) (advisorError (str "advisor call failed: " (charPrefix e 200))))
        ((ok reply)
          (mt (parseAdvice reply)
            ((some a) (advisorAdvice a))
            (none (advisorError (str "advisor reply unreadable: " (charPrefix (optionOr reply "None") 200)))))))))

fn adviceNotice advice: AdviceForm -> String
  (mt advice
    ((adviceOf n why avoid)
      (str "(:advice :next \"" (esc n) "\""
        (mt why ((some w) (if (stringEmpty? w) "" (str " :why \"" (esc w) "\""))) (none ""))
        (mt avoid ((some a) (if (stringEmpty? a) "" (str " :avoid \"" (esc a) "\""))) (none ""))
        ")")))

fn progressLine p: j/Json -> (Option String)
  (if (not (pyTruthy p))
    none
    (let [recs (map (fn [r] (str "(\"" (getDefault r "id" "") "\" "
                                 (if (isNone (jgetOr r "exit")) (str ":" (getDefault r "status" "ok")) (str ":exit " (pyStr (jgetOr r "exit")))) ")"))
                 (items (jgetOr p "receipts")))
          gs (map (fn [g] (str "(:cmd \"" (escVal (optionOr (jget g "cmd") (j/jstr ""))) "\" " (gateOutcome g) ")")) (items (jgetOr p "gates")))
          ops (map (fn [o] (str "\"" (esc (pyStr o)) "\"")) (items (jgetOr p "ops")))]
      (some (str "(:progress :turn " (pyStr (jgetOr p "turn")) " :ops (" (joinSep ops " ") ") :receipts (" (joinSep recs " ")
              ") :gates (" (joinSep gs " ") "))"))))

fn ! emitProgress! p: j/Json -> Bool
  (mt (progressLine p) ((some l) (do (eprintln l) true)) (none false))
