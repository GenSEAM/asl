(module ws/asl/tools/mesh/board
  :x [AsnValue RecordTok RecordValue RecordStep ParseStep IntParse CleanupReport CompactReport ShardLoad Distilled
      cpLength dictGet dictPut truthy? pyStr pyRepr pyStrip pySplit pyInt pyFloat pyJoin pyDirname pyBasename relPath!
      sanitizeAsnString unescapeAsnString asnFieldString normalizeSeverity renderAttractor insertIntoDefects
      parseFinding parseVerdict tokenizeAsn parseAsnItem parseAsnForm extractGapBlocks
      recordTokens recordValue formToMap readRecord recordScalar parseGapBlock formFields parseVerification
      normAgent commandVacuity! transitionAllowed! setField valueEnd shardTextFromBlock asnListText safeDefectId
      readTextFile! atomicWriteFile! acquireFileLock! releaseFileLock! withFileLock! isProcessAlive!
      cleanupStaleTempFiles! cleanupStaleTempFilesEnv! cleanupMetrics saveDefectShard! loadShardedBlackboard!
      compactObservationMemory! compactMetrics writeShardForBlock! writeBoard! distillShard!
      loadMeshConfig! loadMeshConfigEnv! withSecureFileLock! pidFileFor]
  :i [])

enum AsnValue
  (asnNone)
  (asnBool value: Bool)
  (asnInt value: Int64)
  (asnFloat value: Float64)
  (asnStr value: String)
  (asnList items: (List AsnValue))
  (asnTuple items: (List AsnValue))
  (asnDict entries: (List (Pair String AsnValue)))

enum RecordTok
  (tokOpen text: String)
  (tokClose text: String)
  (tokStr text: String)
  (tokKey text: String)
  (tokAtom text: String)

enum RecordValue
  (recLeaf tok: RecordTok)
  (recForm items: (List RecordValue))

enum IntParse
  (intBad)
  (intOk value: Int64)
  (intHuge)

schema FieldHit
  (:f nl Int64)
  (:f keyAt Int64)
  (:f valueAt Int64)

schema RecordStep
  (:f value RecordValue)
  (:f used Int64)
  (:f rest (List RecordTok))

schema ParseStep
  (:f value AsnValue)
  (:f used Int64)
  (:f rest (List String))

schema CleanupReport
  (:f scanned Int64)
  (:f cleanedFiles Int64)
  (:f cleanedLocks Int64)
  (:f failures (List String))

schema CompactReport
  (:f archivedShards Int64)
  (:f compactedEvents Int64)
  (:f failures (List String))

schema ShardLoad
  (:f shards (List AsnValue))
  (:f failures (List String))

schema Distilled
  (:f digest String)
  (:f failures (List String))

fn sub s: String i: Int64 j: Int64 -> String
  (let [n (stringLength s)
        a (max 0 (min i n))
        b (max a (min j n))]
    (optionOr (stringSlice s a b) ""))

fn first xs: (List T) d: T -> T
  (optionOr (listHead xs) d)

fn rest xs: (List T) -> (List T)
  (optionOr (listTail xs) (list))

fn spaceLen bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    0
    (let [b (bytesGet bs i)]
      (cond
        ((or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32))) 1)
        ((and (= b 194) (< (+ i 1) n))
          (let [c (bytesGet bs (+ i 1))] (if (or (= c 133) (= c 160)) 2 0)))
        ((and (= b 225) (< (+ i 2) n))
          (if (and (= (bytesGet bs (+ i 1)) 154) (= (bytesGet bs (+ i 2)) 128)) 3 0))
        ((and (= b 226) (< (+ i 2) n))
          (let [c (bytesGet bs (+ i 1))
                d (bytesGet bs (+ i 2))]
            (if (or (and (= c 128) (or (<= d 138) (or (= d 168) (or (= d 169) (= d 175)))))
                    (and (= c 129) (= d 159)))
              3
              0)))
        ((and (= b 227) (< (+ i 2) n))
          (if (and (= (bytesGet bs (+ i 1)) 128) (= (bytesGet bs (+ i 2)) 128)) 3 0))
        (else 0))))

fn spaceEndLen bs: Bytes j: Int64 -> Int64
  (cond
    ((and (>= j 1) (= (spaceLen bs (- j 1) j) 1)) 1)
    ((and (>= j 2) (= (spaceLen bs (- j 2) j) 2)) 2)
    ((and (>= j 3) (= (spaceLen bs (- j 3) j) 3)) 3)
    (else 0))

fn skipSpace bs: Bytes i: Int64 n: Int64 -> Int64
  (let [k (spaceLen bs i n)]
    (if (> k 0) (skipSpace bs (+ i k) n) i))

fn trimEnd bs: Bytes j: Int64 lo: Int64 -> Int64
  (if (<= j lo)
    j
    (let [k (spaceEndLen bs j)]
      (if (and (> k 0) (>= (- j k) lo)) (trimEnd bs (- j k) lo) j)))

fn pyStrip s: String -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        i (skipSpace bs 0 n)]
    (sub s i (trimEnd bs n i)))

fn wordEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (> (spaceLen bs i n) 0)) i (wordEnd bs (+ i 1) n))

fn splitWords s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (let [a (skipSpace bs i n)]
    (if (>= a n)
      (listReverse acc)
      (let [e (wordEnd bs a n)]
        (splitWords s bs e n (cons (sub s a e) acc)))))

fn pySplit s: String -> (List String)
  (let [bs (stringToBytes s)]
    (splitWords s bs 0 (bytesLength bs) (list)))

fn leadCount bs: Bytes i: Int64 n: Int64 code: Int64 -> Int64
  (if (and (< i n) (= (bytesGet bs i) code)) (leadCount bs (+ i 1) n code) i)

fn tailCount bs: Bytes j: Int64 lo: Int64 code: Int64 -> Int64
  (if (and (> j lo) (= (bytesGet bs (- j 1)) code)) (tailCount bs (- j 1) lo code) j)

fn lstripByte s: String code: Int64 -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (sub s (leadCount bs 0 n code) n))

fn rstripByte s: String code: Int64 -> String
  (let [bs (stringToBytes s)]
    (sub s 0 (tailCount bs (bytesLength bs) 0 code)))

fn stripByte s: String code: Int64 -> String
  (rstripByte (lstripByte s code) code)

fn lstripColon s: String -> String
  (lstripByte s 58)

fn lower s: String -> String
  (stringLower s)

fn dictGet es: (List (Pair String V)) k: String -> (Option V)
  (mt (listHead es)
    ((none) (none))
    ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (dictGet (rest es) k))))

fn dictPutLoop es: (List (Pair String V)) k: String v: V acc: (List (Pair String V)) -> (List (Pair String V))
  (mt (listHead es)
    ((none) (listReverse (cons (pair k v) acc)))
    ((some p)
      (if (= (pairFirst p) k)
        (listAppend (listReverse (cons (pair k v) acc)) (rest es))
        (dictPutLoop (rest es) k v (cons p acc)))))

fn dictPut es: (List (Pair String V)) k: String v: V -> (List (Pair String V))
  (dictPutLoop es k v (list))

fn dictOf v: AsnValue -> (Option (List (Pair String AsnValue)))
  (mt v ((asnDict es) (some es)) (_ (none)))

fn getOr es: (List (Pair String AsnValue)) k: String d: AsnValue -> AsnValue
  (optionOr (dictGet es k) d)

fn subDict es: (List (Pair String AsnValue)) k: String -> (List (Pair String AsnValue))
  (mt (dictGet es k) ((some v) (optionOr (dictOf v) (list))) ((none) (list)))

fn truthy? v: AsnValue -> Bool
  (mt v
    ((asnNone) false)
    ((asnBool b) b)
    ((asnInt i) (!= i 0))
    ((asnFloat f) (!= f 0.0))
    ((asnStr s) (not (stringEmpty? s)))
    ((asnList xs) (not (listEmpty? xs)))
    ((asnTuple xs) (not (listEmpty? xs)))
    ((asnDict es) (not (listEmpty? es))))

fn hex2 b: Int64 -> String
  (let [h "0123456789abcdef"]
    (str (sub h (/ b 16) (+ (/ b 16) 1)) (sub h (mod b 16) (+ (mod b 16) 1))))

fn reprByte s: String bs: Bytes i: Int64 q: Int64 -> String
  (let [b (bytesGet bs i)]
    (cond
      ((= b 92) "\\\\")
      ((= b q) (if (= q 39) "\\'" "\\\""))
      ((= b 10) "\\n")
      ((= b 13) "\\r")
      ((= b 9) "\\t")
      ((or (< b 32) (= b 127)) (str "\\x" (hex2 b)))
      (else (sub s i (+ i 1)))))

fn reprLoop s: String bs: Bytes i: Int64 n: Int64 q: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (reprLoop s bs (+ i 1) n q (cons (reprByte s bs i q) acc)))

fn pyReprStr s: String -> String
  (let [q (if (and (stringContains? s "'") (not (stringContains? s "\""))) 34 39)
        qs (if (= q 34) "\"" "'")
        bs (stringToBytes s)]
    (str qs (reprLoop s bs 0 (bytesLength bs) q (list)) qs))

fn pyRepr v: AsnValue -> String
  (mt v ((asnStr s) (pyReprStr s)) (_ (pyStr v)))

fn pyStr v: AsnValue -> String
  (mt v
    ((asnNone) "None")
    ((asnBool b) (if b "True" "False"))
    ((asnInt i) (stringFromInt64 i))
    ((asnFloat f) (stringFromFloat64 f))
    ((asnStr s) s)
    ((asnList xs) (str "[" (stringJoin (map pyRepr xs) ", ") "]"))
    ((asnTuple xs) (str "(" (stringJoin (map pyRepr xs) ", ") (if (= (listLength xs) 1) ",)" ")")))
    ((asnDict es) (str "{" (stringJoin (map (fn [p] (str (pyReprStr (pairFirst p)) ": " (pyRepr (pairSecond p)))) es) ", ") "}")))

fn pyStrOr v: AsnValue d: String -> String
  (if (truthy? v) (pyStr v) d)

fn typeName v: AsnValue -> String
  (mt v
    ((asnNone) "NoneType")
    ((asnBool _) "bool")
    ((asnInt _) "int")
    ((asnFloat _) "float")
    ((asnStr _) "str")
    ((asnList _) "list")
    ((asnTuple _) "tuple")
    ((asnDict _) "dict"))

fn intDigits bs: Bytes i: Int64 n: Int64 acc: Int64 prevDigit: Bool huge: Bool -> IntParse
  (if (>= i n)
    (cond ((not prevDigit) (intBad)) (huge (intHuge)) (else (intOk acc)))
    (let [b (bytesGet bs i)]
      (cond
        ((and (>= b 48) (<= b 57))
          (let [d (- b 48)
                over (or huge (> acc (/ (- 9223372036854775807 d) 10)))]
            (intDigits bs (+ i 1) n (if over 0 (+ (* acc 10) d)) true over)))
        ((and (= b 95) prevDigit) (intDigits bs (+ i 1) n acc false huge))
        (else (intBad)))))

fn pyInt s: String -> IntParse
  (let [t (pyStrip s)
        bs (stringToBytes t)
        n (bytesLength bs)
        sign (if (> n 0) (bytesGet bs 0) 0)
        start (if (or (= sign 43) (= sign 45)) 1 0)]
    (mt (intDigits bs start n 0 false false)
      ((intOk v) (intOk (if (= sign 45) (- 0 v) v)))
      (parsed parsed)))

fn digitPart bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (< (bytesGet bs i) 48) (> (bytesGet bs i) 57))
    -1
    (let [j (+ i 1)]
      (cond
        ((and (< j n) (and (>= (bytesGet bs j) 48) (<= (bytesGet bs j) 57))) (digitPart bs j n))
        ((and (< (+ j 1) n) (and (= (bytesGet bs j) 95) (and (>= (bytesGet bs (+ j 1)) 48) (<= (bytesGet bs (+ j 1)) 57)))) (digitPart bs (+ j 1) n))
        (else j))))

fn exponentEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (or (= (bytesGet bs i) 101) (= (bytesGet bs i) 69)))
    (let [s (+ i 1)
          d (if (and (< s n) (or (= (bytesGet bs s) 43) (= (bytesGet bs s) 45))) (+ s 1) s)]
      (digitPart bs d n))
    i)

fn pyFloat s: String -> (Option Float64)
  (let [t (pyStrip s)
        bs (stringToBytes t)
        n (bytesLength bs)
        sign (if (> n 0) (bytesGet bs 0) 0)
        start (if (or (= sign 43) (= sign 45)) 1 0)
        word (lower (sub t start n))
        neg (= sign 45)]
    (cond
      ((or (= word "inf") (= word "infinity")) (some (if neg (floatNegInf) (floatInf))))
      ((= word "nan") (some (floatNan)))
      (else
        (let [ie (digitPart bs start n)
              afterInt (if (< ie 0) start ie)
              hasDot (and (< afterInt n) (= (bytesGet bs afterInt) 46))
              fe (if hasDot (digitPart bs (+ afterInt 1) n) -1)
              afterFrac (cond ((not hasDot) afterInt) ((< fe 0) (+ afterInt 1)) (else fe))
              ok (and (or (>= ie 0) (>= fe 0)) (< start n))
              ee (if ok (exponentEnd bs afterFrac n) -1)]
          (if (and ok (= ee n))
            (mt (stringToFloat64 (stringReplace t "_" ""))
              ((some f) (some f))
              ((none) none))
            (none))))))

fn sanitizeAsnString v: AsnValue -> String
  (if (not (truthy? v))
    ""
    (let [s (pyStrip (stringReplace (pyStr v) "\r" ""))]
      (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")))

fn unescapeLoop s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (stringJoin (listReverse (cons (sub s start n) acc)) ""))
    ((and (= (bytesGet bs i) 92) (< (+ i 1) n))
      (let [piece (if (= (bytesGet bs (+ i 1)) 110) "\n" (sub s (+ i 1) (+ i 2)))]
        (unescapeLoop s bs (+ i 2) (+ i 2) n (cons piece (cons (sub s start i) acc)))))
    (else (unescapeLoop s bs (+ i 1) start n acc)))

fn unescapeAsnString s: String -> String
  (let [bs (stringToBytes s)]
    (unescapeLoop s bs 0 0 (bytesLength bs) (list)))

fn matchAt bs: Bytes pb: Bytes m: Int64 i: Int64 k: Int64 -> Bool
  (cond
    ((>= k m) true)
    ((!= (bytesGet bs (+ i k)) (bytesGet pb k)) false)
    (else (matchAt bs pb m i (+ k 1))))

fn findBytes bs: Bytes n: Int64 pb: Bytes m: Int64 i: Int64 -> Int64
  (cond
    ((> (+ i m) n) -1)
    ((matchAt bs pb m i 0) i)
    (else (findBytes bs n pb m (+ i 1))))

fn findStr bs: Bytes n: Int64 pat: String i: Int64 -> Int64
  (let [pb (stringToBytes pat)]
    (findBytes bs n pb (bytesLength pb) i))

fn findByte bs: Bytes n: Int64 code: Int64 i: Int64 -> Int64
  (cond ((>= i n) -1) ((= (bytesGet bs i) code) i) (else (findByte bs n code (+ i 1))))

fn quotedEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet bs i) 34) i)
    ((= (bytesGet bs i) 92) (if (and (< (+ i 1) n) (!= (bytesGet bs (+ i 1)) 10)) (quotedEnd bs (+ i 2) n) -1))
    (else (quotedEnd bs (+ i 1) n)))

fn keyQuotedFrom text: String bs: Bytes n: Int64 key: String i: Int64 -> (Option String)
  (let [p (findStr bs n key i)]
    (if (< p 0)
      (none)
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)]
        (if (and (> b a) (and (< b n) (= (bytesGet bs b) 34)))
          (let [e (quotedEnd bs (+ b 1) n)]
            (if (>= e 0) (some (sub text (+ b 1) e)) (keyQuotedFrom text bs n key (+ p 1))))
          (keyQuotedFrom text bs n key (+ p 1))))))

fn asnFieldString text: String field: String -> (Option String)
  (let [bs (stringToBytes text)]
    (optionMap (fn [raw] (pyStrip (unescapeAsnString raw)))
      (keyQuotedFrom text bs (bytesLength bs) (str ":" field) 0)))

fn keyPlainFrom text: String bs: Bytes n: Int64 key: String i: Int64 -> (Option String)
  (let [p (findStr bs n key i)]
    (if (< p 0)
      (none)
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)
            e (if (and (> b a) (and (< b n) (= (bytesGet bs b) 34))) (findByte bs n 34 (+ b 1)) -1)]
        (if (> e (+ b 1))
          (some (sub text (+ b 1) e))
          (keyPlainFrom text bs n key (+ p 1))))))

fn letter? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn runEnd bs: Bytes i: Int64 n: Int64 pred: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (pred (bytesGet bs i))) (runEnd bs (+ i 1) n pred) i)

fn keyWordFrom text: String bs: Bytes n: Int64 key: String i: Int64 -> (Option String)
  (let [p (findStr bs n key i)]
    (if (< p 0)
      (none)
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)
            c (if (and (< b n) (= (bytesGet bs b) 58)) (+ b 1) b)
            e (runEnd bs c n letter?)]
        (if (and (> b a) (> e c))
          (some (sub text c e))
          (keyWordFrom text bs n key (+ p 1))))))

fn keyWord text: String key: String -> (Option String)
  (let [bs (stringToBytes text)]
    (keyWordFrom text bs (bytesLength bs) key 0))

fn normalizeSeverity v: AsnValue -> String
  (let [s (lower (lstripColon (pyStrOr v "")))]
    (if (or (= s "critical") (or (= s "high") (or (= s "medium") (= s "low")))) s "medium"))

fn renderAttractor v: AsnValue -> String
  (let [parts (mt v
                ((asnList xs) (map (fn [a] (lstripColon (pyStr a))) (filter (fn [a] (not (stringEmpty? (pyStrip (pyStr a))))) xs)))
                ((asnTuple xs) (map (fn [a] (lstripColon (pyStr a))) (filter (fn [a] (not (stringEmpty? (pyStrip (pyStr a))))) xs)))
                (_ (map lstripColon (filter (fn [p] (not (stringEmpty? (stripByte p 58))))
                                      (pySplit (stringReplace (stringReplace (pyStrOr v "") "(" " ") ")" " "))))))
        ps (if (listEmpty? parts) (list "verification") parts)]
    (if (= (listLength ps) 1)
      (str ":" (first ps ""))
      (str "(" (stringJoin (map (fn [p] (str ":" p)) ps) " ") ")")))

fn scanClose bs: Bytes n: Int64 i: Int64 depth: Int64 inStr: Bool esc: Bool brackets: Bool -> Int64
  (if (>= i n)
    -1
    (let [c (bytesGet bs i)]
      (cond
        (esc (scanClose bs n (+ i 1) depth inStr false brackets))
        ((= c 92) (scanClose bs n (+ i 1) depth inStr true brackets))
        ((= c 34) (scanClose bs n (+ i 1) depth (not inStr) false brackets))
        (inStr (scanClose bs n (+ i 1) depth inStr false brackets))
        ((or (= c 40) (and brackets (= c 91))) (scanClose bs n (+ i 1) (+ depth 1) inStr false brackets))
        ((or (= c 41) (and brackets (= c 93)))
          (if (<= depth 1) i (scanClose bs n (+ i 1) (- depth 1) inStr false brackets)))
        (else (scanClose bs n (+ i 1) depth inStr false brackets)))))

fn blankByte? b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 13) (= b 10))))

fn insertIntoDefects bb: String entry: String -> (Result String String)
  (let [bs (stringToBytes bb)
        n (bytesLength bs)
        k (findStr bs n ":defects" 0)]
    (if (< k 0)
      (err "ValueError: blackboard has no :defects container")
      (let [j (runEnd bs (+ k 8) n blankByte?)]
        (if (or (>= j n) (not (or (= (bytesGet bs j) 40) (= (bytesGet bs j) 91))))
          (err "ValueError: :defects is not followed by a container")
          (let [c (scanClose bs n j 0 false false true)]
            (if (< c 0)
              (err "ValueError: :defects container is not closed")
              (ok (str (sub bb 0 c) entry "\n  " (sub bb c n)))))))))

fn mkDict ps: (List (Pair String AsnValue)) -> AsnValue
  (asnDict (fold (fn [acc p] (dictPut acc (pairFirst p) (pairSecond p))) (list) ps))

fn parseFinding text: String -> (Option AsnValue)
  (let [target (optionOr (asnFieldString text "target") "")]
    (if (or (stringEmpty? target) (stringStartsWith? target "<"))
      (none)
      (let [hazard (optionOr (asnFieldString text "hazard") "")]
        (if (stringStartsWith? hazard "<")
          (none)
          (let [bs (stringToBytes text)
                sp (keyQuotedFrom text bs (bytesLength bs) ":scratchpad" 0)
                base (list (pair "target" (asnStr target))
                           (pair "severity" (asnStr (normalizeSeverity (asnStr (optionOr (keyWord text ":severity") "medium")))))
                           (pair "hazard" (asnStr hazard))
                           (pair "evidence" (asnStr (optionOr (asnFieldString text "evidence") ""))))
                withSp (mt sp ((some s) (listAppend base (list (pair "scratchpad" (asnStr (pyStrip s)))))) ((none) base))]
            (some (mkDict (listAppend withSp (list (pair "remediation" (asnStr (optionOr (asnFieldString text "remediation") ""))))))))))))

fn witnessFrom text: String bs: Bytes n: Int64 i: Int64 -> (Option String)
  (let [p (findStr bs n ":witness" i)]
    (if (< p 0)
      (none)
      (let [q (+ p 8)
            kl (cond
                 ((= (sub text q (+ q 4)) "Test") 4)
                 ((= (sub text q (+ q 5)) "_test") 5)
                 (else -1))]
        (if (< kl 0)
          (witnessFrom text bs n (+ p 1))
          (let [a (+ q kl)
                b (skipSpace bs a n)
                e (if (and (> b a) (and (< b n) (= (bytesGet bs b) 34))) (findByte bs n 34 (+ b 1)) -1)]
            (if (> e (+ b 1))
              (some (sub text (+ b 1) e))
              (witnessFrom text bs n (+ p 1))))))))

fn witnessOf text: String -> (Option String)
  (let [bs (stringToBytes text)]
    (witnessFrom text bs (bytesLength bs) 0))

fn parseVerdict text: String -> (Option AsnValue)
  (let [dec (lower (optionOr (keyWord text ":decision") ""))]
    (if (not (or (= dec "corroborate") (= dec "refute")))
      (none)
      (let [ev (mt (asnFieldString text "evidence") ((some e) (list (pair "evidence" (asnStr e)))) ((none) (list)))
            wit (mt (witnessOf text) ((some w) (list (pair "witness_test" (asnStr (pyStrip w))))) ((none) (list)))]
        (some (mkDict (listAppend (list (pair "decision" (asnStr dec))) (listAppend ev wit)))))))

fn atomStop? b: Int64 -> Bool
  (or (= b 40) (or (= b 41) (or (= b 91) (or (= b 93) (or (= b 34) (= b 59))))))

fn atomEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (or (> (spaceLen bs i n) 0) (atomStop? (bytesGet bs i)))) i (atomEnd bs (+ i 1) n))

fn tokStrEnd bs: Bytes i: Int64 n: Int64 esc: Bool -> Int64
  (cond
    ((>= i n) n)
    (esc (tokStrEnd bs (+ i 1) n false))
    ((= (bytesGet bs i) 92) (tokStrEnd bs (+ i 1) n true))
    ((= (bytesGet bs i) 34) (+ i 1))
    (else (tokStrEnd bs (+ i 1) n false)))

fn delim? b: Int64 -> Bool
  (or (= b 40) (or (= b 41) (or (= b 91) (= b 93))))

fn tokLoop text: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (Result (List String) String)
  (if (>= i n)
    (ok (listReverse acc))
    (let [c (bytesGet bs i)
          k (spaceLen bs i n)]
      (cond
        ((> k 0) (tokLoop text bs (+ i k) n acc))
        ((and (= c 59) (and (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 59)))
          (let [j (findByte bs n 10 i)] (tokLoop text bs (if (< j 0) n j) n acc)))
        ((delim? c) (tokLoop text bs (+ i 1) n (cons (sub text i (+ i 1)) acc)))
        ((= c 34)
          (let [j (tokStrEnd bs (+ i 1) n false)] (tokLoop text bs j n (cons (sub text i j) acc))))
        (else
          (let [j (atomEnd bs i n)]
            (if (= j i)
              (err (str "ValueError: lone ';' at byte " (stringFromInt64 i) "; the original tokenizer loops forever here"))
              (tokLoop text bs j n (cons (sub text i j) acc))))))))

fn tokenizeAsn text: String -> (Result (List String) String)
  (let [bs (stringToBytes text)]
    (tokLoop text bs 0 (bytesLength bs) (list)))

fn numberOrAtom t: String -> AsnValue
  (if (stringContains? t ".")
    (mt (pyFloat t) ((some f) (asnFloat f)) ((none) (asnStr t)))
    (mt (pyInt t) ((intOk v) (asnInt v)) (_ (asnStr t))))

fn itemStep toks: (List String) -> ParseStep
  (mt (listHead toks)
    ((none) (ParseStep :value (asnNone) :used 0 :rest toks))
    ((some t)
      (cond
        ((= t "(") (formStep toks))
        ((= t "[") (listStep (rest toks) 1 (list)))
        ((and (stringStartsWith? t "\"") (stringEndsWith? t "\""))
          (ParseStep :value (asnStr (stringReplace (sub t 1 (- (stringLength t) 1)) "\\\"" "\"")) :used 1 :rest (rest toks)))
        ((= t "true") (ParseStep :value (asnBool true) :used 1 :rest (rest toks)))
        ((= t "false") (ParseStep :value (asnBool false) :used 1 :rest (rest toks)))
        (else (ParseStep :value (numberOrAtom t) :used 1 :rest (rest toks))))))

fn listStep toks: (List String) used: Int64 acc: (List AsnValue) -> ParseStep
  (mt (listHead toks)
    ((none) (ParseStep :value (asnList (listReverse acc)) :used used :rest toks))
    ((some t)
      (if (= t "]")
        (ParseStep :value (asnList (listReverse acc)) :used (+ used 1) :rest (rest toks))
        (let [st (itemStep toks)]
          (listStep st.rest (+ used st.used) (cons st.value acc))))))

fn formValue es: (List (Pair String AsnValue)) items: (List AsnValue) -> AsnValue
  (cond
    ((and (not (listEmpty? items)) (listEmpty? es)) (asnList items))
    ((not (listEmpty? items)) (asnDict (dictPut es "_items" (asnList items))))
    (else (asnDict es)))

fn formLoop toks: (List String) used: Int64 es: (List (Pair String AsnValue)) items: (List AsnValue) -> ParseStep
  (mt (listHead toks)
    ((none) (ParseStep :value (formValue es (listReverse items)) :used used :rest toks))
    ((some t)
      (cond
        ((= t ")") (ParseStep :value (formValue es (listReverse items)) :used (+ used 1) :rest (rest toks)))
        ((stringStartsWith? t ":")
          (let [after (rest toks)]
            (if (listEmpty? after)
              (formLoop after (+ used 1) es items)
              (let [st (itemStep after)]
                (formLoop st.rest (+ used (+ 1 st.used)) (dictPut es (sub t 1 (stringLength t)) st.value) items)))))
        (else
          (let [st (itemStep toks)]
            (formLoop st.rest (+ used st.used) es (cons st.value items)))))))

fn formStep toks: (List String) -> ParseStep
  (mt (listHead toks)
    ((none) (ParseStep :value (asnNone) :used 0 :rest toks))
    ((some t)
      (if (!= t "(")
        (ParseStep :value (asnNone) :used 0 :rest toks)
        (let [body (rest toks)
              h1 (first body "")
              h2 (first (rest body) "")]
          (if (and (stringStartsWith? h1 ":") (stringStartsWith? h2 ":"))
            (formLoop (rest body) 2 (list (pair "_tag" (asnStr (sub h1 1 (stringLength h1))))) (list))
            (formLoop body 1 (list) (list)))))))

fn parseAsnItem toks: (List String) idx: Int64 -> (Pair AsnValue Int64)
  (if (>= idx (listLength toks))
    (pair (asnNone) idx)
    (let [st (itemStep (listDrop toks idx))]
      (pair st.value (+ idx st.used))))

fn parseAsnForm toks: (List String) idx: Int64 -> (Pair AsnValue Int64)
  (if (>= idx (listLength toks))
    (pair (asnNone) idx)
    (let [st (formStep (listDrop toks idx))]
      (pair st.value (+ idx st.used))))

fn gapLoop content: String bs: Bytes n: Int64 pat: String idx: Int64 acc: (List String) -> (List String)
  (let [pos (findStr bs n pat idx)]
    (if (< pos 0)
      (listReverse acc)
      (let [c (scanClose bs n pos 0 false false false)]
        (if (< c 0)
          (listReverse acc)
          (gapLoop content bs n pat (+ c 1) (cons (sub content pos (+ c 1)) acc))))))

fn extractGapBlocks content: String tag: String -> (List String)
  (let [bs (stringToBytes content)]
    (gapLoop content bs (bytesLength bs) (str "(:" tag) 0 (list)))

fn recStrEnd bs: Bytes j: Int64 n: Int64 -> Int64
  (cond
    ((>= j n) j)
    ((= (bytesGet bs j) 92) (recStrEnd bs (+ j 2) n))
    ((= (bytesGet bs j) 34) j)
    (else (recStrEnd bs (+ j 1) n)))

fn recTokLoop block: String bs: Bytes i: Int64 n: Int64 acc: (List RecordTok) -> (List RecordTok)
  (if (>= i n)
    (listReverse acc)
    (let [c (bytesGet bs i)
          k (spaceLen bs i n)]
      (cond
        ((> k 0) (recTokLoop block bs (+ i k) n acc))
        ((= c 59) (let [j (findByte bs n 10 i)] (recTokLoop block bs (if (< j 0) n j) n acc)))
        ((or (= c 40) (= c 91)) (recTokLoop block bs (+ i 1) n (cons (tokOpen (sub block i (+ i 1))) acc)))
        ((or (= c 41) (= c 93)) (recTokLoop block bs (+ i 1) n (cons (tokClose (sub block i (+ i 1))) acc)))
        ((= c 34)
          (let [j (recStrEnd bs (+ i 1) n)]
            (recTokLoop block bs (+ j 1) n (cons (tokStr (unescapeAsnString (sub block (+ i 1) j))) acc))))
        (else
          (let [j (atomEnd bs i n)
                t (sub block i j)]
            (recTokLoop block bs j n (cons (if (and (stringStartsWith? t ":") (> (stringLength t) 1)) (tokKey (sub t 1 (stringLength t))) (tokAtom t)) acc)))))))

fn recordTokens block: String -> (List RecordTok)
  (let [bs (stringToBytes block)]
    (recTokLoop block bs 0 (bytesLength bs) (list)))

fn close? t: RecordTok -> Bool
  (mt t ((tokClose _) true) (_ false))

fn recItemsStep toks: (List RecordTok) used: Int64 acc: (List RecordValue) -> RecordStep
  (mt (listHead toks)
    ((none) (RecordStep :value (recForm (listReverse acc)) :used (+ used 1) :rest toks))
    ((some t)
      (if (close? t)
        (RecordStep :value (recForm (listReverse acc)) :used (+ used 1) :rest (rest toks))
        (let [st (recStep toks)]
          (recItemsStep st.rest (+ used st.used) (cons st.value acc))))))

fn recStep toks: (List RecordTok) -> RecordStep
  (mt (listHead toks)
    ((none) (RecordStep :value (recForm (list)) :used 0 :rest toks))
    ((some t)
      (mt t
        ((tokOpen _) (recItemsStep (rest toks) 1 (list)))
        (_ (RecordStep :value (recLeaf t) :used 1 :rest (rest toks))))))

fn recordValue toks: (List RecordTok) k: Int64 -> (Pair RecordValue Int64)
  (let [st (recStep (listDrop toks k))]
    (pair st.value (+ k st.used)))

fn keyName v: RecordValue -> (Option String)
  (mt v ((recLeaf t) (mt t ((tokKey k) (some k)) (_ (none)))) (_ (none)))

fn ftmLoop items: (List RecordValue) acc: (List (Pair String RecordValue)) -> (List (Pair String RecordValue))
  (mt (listHead items)
    ((none) acc)
    ((some it)
      (let [after (rest items)]
        (mt (keyName it)
          ((some k) (mt (listHead after) ((some v) (ftmLoop (rest after) (dictPut acc k v))) ((none) acc)))
          ((none) (ftmLoop after acc))))))

fn formToMap items: (List RecordValue) start: Int64 -> (List (Pair String RecordValue))
  (ftmLoop (listDrop items start) (list))

fn readRecord block: String -> (List (Pair String RecordValue))
  (let [toks (recordTokens block)]
    (mt (listHead toks)
      ((some t)
        (mt t
          ((tokOpen _)
            (mt (recStep toks).value
              ((recForm items)
                (formToMap items (mt (listHead items) ((some h) (if (some? (keyName h)) 1 0)) ((none) 0))))
              (_ (list))))
          (_ (list))))
      ((none) (list))))

fn tokText t: RecordTok -> String
  (mt t ((tokOpen s) s) ((tokClose s) s) ((tokStr s) s) ((tokKey s) s) ((tokAtom s) s))

fn recordScalar v: RecordValue -> String
  (mt v
    ((recLeaf t) (tokText t))
    ((recForm items) (stringJoin (map recordScalar items) " ")))

fn leafOf v: (Option RecordValue) -> (Option RecordTok)
  (mt v ((some x) (mt x ((recLeaf t) (some t)) (_ (none)))) ((none) (none)))

fn gapStrFields rec: (List (Pair String RecordValue)) -> (List (Pair String AsnValue))
  (fold (fn [acc f] (mt (leafOf (dictGet rec f)) ((some t) (dictPut acc f (asnStr (tokText t)))) ((none) acc))) (list)
    (list "id" "target" "hazard" "evidence" "remediation" "auditor"))

fn firstOfForm v: RecordValue -> (Option RecordValue)
  (mt v ((recForm items) (listHead items)) (_ (some v)))

fn gapKwFields rec: (List (Pair String RecordValue)) acc0: (List (Pair String AsnValue)) -> (List (Pair String AsnValue))
  (fold (fn [acc f]
          (mt (leafOf (mt (dictGet rec f) ((some v) (firstOfForm v)) ((none) (none))))
            ((some t) (dictPut acc f (asnStr (lower (tokText t)))))
            ((none) acc)))
    acc0
    (list "status" "severity" "intent" "attractor" "lens"))

fn parseGapBlock block: String -> AsnValue
  (let [rec (readRecord block)
        base (dictPut (list) "raw" (asnStr block))
        withStr (fold (fn [acc p] (dictPut acc (pairFirst p) (pairSecond p))) base (gapStrFields rec))
        withKw (gapKwFields rec withStr)
        conf (mt (leafOf (dictGet rec "confirmations"))
               ((some t) (mt (pyInt (tokText t)) ((intOk v) v) (_ 1)))
               ((none) 1))]
    (asnDict (dictPut withKw "confirmations" (asnInt conf))))

fn formFields v: (Option RecordValue) -> (Option AsnValue)
  (mt v
    ((some x)
      (mt x
        ((recForm items) (some (asnDict (map (fn [p] (pair (pairFirst p) (asnStr (recordScalar (pairSecond p))))) (formToMap items 0)))))
        (_ (none))))
    ((none) (none)))

fn parseVerification block: String -> AsnValue
  (let [rec (readRecord block)
        base (list (pair "target" (asnStr (mt (dictGet rec "target") ((some v) (recordScalar v)) ((none) "")))))
        withRem (mt (dictGet rec "remediatedBy") ((some v) (dictPut base "remediatedBy" (asnStr (recordScalar v)))) ((none) base))
        withForms (fold (fn [acc f] (mt (formFields (dictGet rec f)) ((some m) (dictPut acc f m)) ((none) acc))) withRem
                    (list "verifiedBy" "reproduction" "refutedBy" "mutant"))]
    (asnDict (mt (dictGet rec "demotedFrom") ((some v) (dictPut withForms "demotedFrom" (asnStr (recordScalar v)))) ((none) withForms))))

fn normAgent a: AsnValue -> String
  (lower (stringJoin (pySplit (pyStrOr a "")) " "))

fn words c: String -> (List String)
  (stringSplit c " ")

fn trivialTest? w: (List String) -> Bool
  (let [n (listLength w)
        w0 (first w "")
        w1 (optionOr (listGet w 1) "")
        w2 (optionOr (listGet w 2) "")
        w3 (optionOr (listGet w 3) "")]
    (and (or (= n 4) (and (= n 5) (= (optionOr (listGet w 4) "") "]")))
         (or (= w0 "test") (= w0 "["))
         (or (= w2 "-eq") (= w2 "=") (= w2 "=="))
         (= w1 w3)))

fn wordByte? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (>= b 128))

fn lsFlag? f: String -> Bool
  (let [bs (stringToBytes f)
        n (bytesLength bs)]
    (and (>= n 2) (= (bytesGet bs 0) 45) (= (runEnd bs 1 n wordByte?) n)))

fn trivialPart? p: String -> Bool
  (let [w (if (stringEmpty? p) (list) (words p))
        n (listLength w)
        w0 (first w "")
        w1 (optionOr (listGet w 1) "")]
    (cond
      ((= n 0) false)
      ((= w0 "echo") true)
      ((and (or (= w0 "test") (= w0 "[")) (or (= w1 "-f") (= w1 "-e") (= w1 "-d")))
        (or (= n 3) (and (= n 4) (= (optionOr (listGet w 3) "") "]"))))
      ((= w0 "ls") (and (>= n 2) (listAll? lsFlag? (optionOr (listSlice w 1 (- n 1)) (list)))))
      ((= w0 "cat") (= n 2))
      (else false)))

fn pathByte? b: Int64 -> Bool
  (or (wordByte? b) (= b 46) (= b 47) (= b 45))

fn extMatchEnd c: String p: Int64 k: Int64 -> Int64
  (cond
    ((<= k p) -1)
    ((and (= (sub c k (+ k 1)) ".") (= (sub c (+ k 1) (+ k 4)) "asl")) (+ k 4))
    ((and (= (sub c k (+ k 1)) ".") (= (sub c (+ k 1) (+ k 4)) "asn")) (+ k 4))
    ((and (= (sub c k (+ k 1)) ".") (= (sub c (+ k 1) (+ k 3)) "sh")) (+ k 3))
    ((and (= (sub c k (+ k 1)) ".") (= (sub c (+ k 1) (+ k 3)) "py")) (+ k 3))
    (else (extMatchEnd c p (- k 1))))

fn scriptTokens c: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (if (not (pathByte? (bytesGet bs i)))
      (scriptTokens c bs (+ i 1) n acc)
      (let [e (runEnd bs i n pathByte?)
            m (extMatchEnd c i (- e 1))]
        (if (< m 0)
          (scriptTokens c bs e n acc)
          (scriptTokens c bs m n (cons (sub c i m) acc))))))

fn splitextRoot b: String -> String
  (let [bs (stringToBytes b)
        n (bytesLength bs)
        d (lastByte bs n 46)
        lead (leadCount bs 0 n 46)]
    (if (and (> d 0) (< lead d)) (sub b 0 d) b))

fn lastByte bs: Bytes j: Int64 code: Int64 -> Int64
  (cond ((<= j 0) -1) ((= (bytesGet bs (- j 1)) code) (- j 1)) (else (lastByte bs (- j 1) code)))

fn readTextFile! path: String -> (Result String String)
  (if (isDir? path)
    (err (str "OSError: isADirectory: " path))
    (textOf! path))

fn textOf! path: String -> (Result String String)
  (mt (fileReadString path)
    ((err e) (err (str "OSError: " e)))
    ((ok s) (ok (if (stringContains? s "\r") (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n") s))))

fn ! isFile? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! isDir? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! stemReferenced? root: String stem: String toks: (List String) -> Bool
  (listAny? (fn [tok]
              (let [p (pyJoin root tok)]
                (and (not (stringEmpty? stem)) (isFile? p)
                     (mt (readTextFile! p) ((ok text) (stringContains? text stem)) ((err _) false)))))
            toks)

fn commandVacuity! cmd: AsnValue target: AsnValue root: String -> String
  (let [c (stringJoin (pySplit (pyStrOr cmd "")) " ")
        w (if (stringEmpty? c) (list) (words c))]
    (cond
      ((stringEmpty? c) "empty command")
      ((or (= c "true") (= c ":") (= c "exit") (= c "exit 0") (= c "/usr/bin/true") (= c "/bin/true") (= c "return 0")) "no-op command")
      ((trivialTest? w) "trivially true test")
      ((listAll? trivialPart? (map pyStrip (stringSplit c "&&"))) "only echo/existence checks (echo, test -f|-e|-d, ls, cat)")
      (else
        (let [tfile (pyStrip (first (stringSplit (pyStrOr target "") "#") ""))]
          (if (or (stringEmpty? tfile) (stringContains? c tfile))
            ""
            (let [stem (splitextRoot (pyBasename (rstripByte tfile 47)))
                  cb (stringToBytes c)]
              (if (stemReferenced? root stem (scriptTokens c cb 0 (bytesLength cb) (list)))
                ""
                (str "command does not reference the record target " tfile))))))))

fn getAttr v: AsnValue k: String -> (Result AsnValue String)
  (mt v
    ((asnDict es) (ok (getOr es k (asnNone))))
    (_ (err (str "AttributeError: '" (typeName v) "' object has no attribute 'get'"))))

fn transitionAllowed! status: AsnValue rec: AsnValue root: String -> (Result (Pair Bool String) String)
  (let [st (lstripColon (pyStrOr status ""))]
    (if (not (or (= st "remediated") (= st "certified")))
      (ok (pair true ""))
      (mt (getAttr rec "verifiedBy")
        ((err e) (err e))
        ((ok vbRaw)
          (let [vb (if (truthy? vbRaw) vbRaw (asnDict (list)))]
            (mt (getAttr rec "remediatedBy")
              ((err e) (err e))
              ((ok rbRaw)
                (let [rb (normAgent rbRaw)]
                  (if (stringEmpty? rb)
                    (ok (pair false "missing :remediatedBy"))
                    (mt (getAttr vb "agent")
                      ((err e) (err e))
                      ((ok agent)
                        (let [command (optionOr (resultToOption (getAttr vb "command")) (asnNone))
                              exitV (optionOr (resultToOption (getAttr vb "exit")) (asnNone))
                              target (optionOr (resultToOption (getAttr rec "target")) (asnNone))]
                          (cond
                            ((or (not (truthy? agent)) (not (truthy? command))) (ok (pair false "missing :verifiedBy (:agent :command)")))
                            ((!= (pyStr exitV) "0") (ok (pair false ":verifiedBy command did not exit 0")))
                            ((= (normAgent agent) rb)
                              (ok (pair false (str "verifier " (normAgent agent) " is the remediator; an independent agent must verify"))))
                            (else
                              (let [vac (commandVacuity! command target root)]
                                (if (stringEmpty? vac)
                                  (ok (pair true ""))
                                  (ok (pair false (str "vacuous :verifiedBy command: " vac)))))))))))))))))))

fn strValueEnd bs: Bytes j: Int64 n: Int64 -> Int64
  (cond
    ((>= j n) n)
    ((= (bytesGet bs j) 92) (strValueEnd bs (+ j 2) n))
    ((= (bytesGet bs j) 34) (+ j 1))
    (else (strValueEnd bs (+ j 1) n)))

fn bareByte? b: Int64 -> Bool
  (not (delim? b))

fn bareEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (> (spaceLen bs i n) 0) (delim? (bytesGet bs i))) i (bareEnd bs (+ i 1) n))

fn valueEnd text: String i: Int64 -> (Result Int64 String)
  (let [bs (stringToBytes text)
        n (bytesLength bs)]
    (if (or (< i 0) (>= i n))
      (err "IndexError: string index out of range")
      (let [c (bytesGet bs i)]
        (cond
          ((= c 34) (ok (strValueEnd bs (+ i 1) n)))
          ((or (= c 40) (= c 91)) (let [e (scanClose bs n i 0 false false true)] (ok (if (< e 0) n (+ e 1)))))
          (else (ok (bareEnd bs i n)))))))

fn fieldHit bs: Bytes n: Int64 kb: Bytes m: Int64 i: Int64 -> FieldHit
  (let [p (findByte bs n 10 i)]
    (if (< p 0)
      (FieldHit :nl -1 :keyAt -1 :valueAt -1)
      (let [q (skipSpace bs (+ p 1) n)
            a (+ q m)
            s (skipSpace bs a n)]
        (if (and (<= a n) (matchAt bs kb m q 0) (> s a))
          (FieldHit :nl p :keyAt q :valueAt s)
          (fieldHit bs n kb m (+ p 1))))))

fn findField bs: Bytes n: Int64 key: String -> FieldHit
  (let [kb (stringToBytes key)]
    (fieldHit bs n kb (bytesLength kb) 0))

fn dropLastChar s: String -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (if (= n 0) "" (sub s 0 (charStart bs (- n 1)))))

fn charStart bs: Bytes j: Int64 -> Int64
  (if (and (> j 0) (>= (bytesGet bs j) 128) (< (bytesGet bs j) 192)) (charStart bs (- j 1)) j)

fn setField block: String field: String valueText: String -> (Result String String)
  (let [bs (stringToBytes block)
        n (bytesLength bs)
        hit (findField bs n (str ":" field))]
    (if (>= hit.nl 0)
      (mt (valueEnd block hit.valueAt)
        ((err e) (err e))
        ((ok e) (ok (str (sub block 0 hit.valueAt) valueText (sub block e n)))))
      (let [idHit (findField bs n ":id")
            indent (if (>= idHit.nl 0) (sub block (+ idHit.nl 1) idHit.keyAt) "      ")]
        (ok (str (dropLastChar block) "\n" indent ":" field " " valueText ")")))))

fn shardTextFromBlock block: String -> String
  (let [lines (stringSplit (pyStrip block) "\n")
        head (pyStrip (first lines ""))
        tailLines (map (fn [ln] (let [t (pyStrip ln)] (if (stringEmpty? t) "" (str "  " t)))) (rest lines))]
    (str (stringJoin (cons head tailLines) "\n") "\n"))

fn asnListText items: (List String) -> String
  (str "(" (stringJoin items " ") ")")

fn idByte? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (= b 45))

fn safeLoop s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [b (bytesGet bs i)
          j (charEnd bs (+ i 1) n)]
      (safeLoop s bs j n (cons (if (idByte? b) (sub s i j) "_") acc))))

fn charEnd bs: Bytes j: Int64 n: Int64 -> Int64
  (if (and (< j n) (>= (bytesGet bs j) 128) (< (bytesGet bs j) 192)) (charEnd bs (+ j 1) n) j)

fn safeDefectId id: String -> String
  (let [bs (stringToBytes id)]
    (safeLoop id bs 0 (bytesLength bs) (list)))

fn pyJoin a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((stringEmpty? a) b)
    ((stringEndsWith? a "/") (str a b))
    (else (str a "/" b)))

fn pyDirname p: String -> String
  (let [bs (stringToBytes p)
        k (lastByte bs (bytesLength bs) 47)]
    (if (< k 0)
      ""
      (let [head (sub p 0 (+ k 1))
            trimmed (rstripByte head 47)]
        (if (stringEmpty? trimmed) head trimmed))))

fn pyBasename p: String -> String
  (let [bs (stringToBytes p)
        n (bytesLength bs)]
    (sub p (+ (lastByte bs n 47) 1) n))

fn pathParts p: String -> (List String)
  (listReverse
    (fold (fn [acc c]
            (cond
              ((or (stringEmpty? c) (= c ".")) acc)
              ((= c "..") (rest acc))
              (else (cons c acc))))
      (list)
      (stringSplit p "/")))

fn absParts! p: String -> (List String)
  (if (stringStartsWith? p "/")
    (pathParts p)
    (pathParts (str (resultOr (realPath ".") "/") "/" p)))

fn dropCommon a: (List String) b: (List String) -> (Pair (List String) (List String))
  (mt (listHead a)
    ((none) (pair a b))
    ((some x)
      (mt (listHead b)
        ((none) (pair a b))
        ((some y) (if (= x y) (dropCommon (rest a) (rest b)) (pair a b))))))

fn relPath! path: String start: String -> String
  (let [d (dropCommon (absParts! path) (absParts! start))
        ups (map (fn [_] "..") (pairSecond d))
        parts (listAppend ups (pairFirst d))]
    (if (listEmpty? parts) "." (stringJoin parts "/")))

fn osErr e: String -> String
  (str "OSError: " e)

fn makeDirs! dir: String -> (Result Unit String)
  (if (stringEmpty? dir)
    (err "OSError: notFound: '': No such file or directory")
    (mt (dirCreate dir) ((ok _) (ok ())) ((err e) (err (osErr e)))))

fn atomicWriteFile! path: String content: String -> (Result Unit String)
  (let [dir (pyDirname path)
        tmp (pyJoin dir (str "." (pyBasename path) ".tmp." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
    (mt (if (stringEmpty? dir) (ok ()) (makeDirs! dir))
      ((err e) (err e))
      ((ok _)
        (mt (fileCreateExclusive tmp content)
          ((err e) (err (osErr e)))
          ((ok _)
            (mt (fileFsync tmp)
              ((err e) (do (pathRemove tmp) (err (osErr e))))
              ((ok _)
                (mt (pathRename tmp path)
                  ((ok _) (ok ()))
                  ((err e) (do (pathRemove tmp) (err (osErr e))))))))))))

fn lockLoop! lockPath: String -> (Result Int64 String)
  (mt (fileLock lockPath true)
    ((ok fd) (ok fd))
    ((err e)
      (if (= e "busy")
        (do (sleepMs 5) (lockLoop! lockPath))
        (err (osErr e)))))

fn acquireFileLock! target: String -> (Result Int64 String)
  (if (or (stringEmpty? target) (= target "/dev/null"))
    (ok -1)
    (let [lockPath (str target ".lock")
          dir (pyDirname lockPath)]
      (mt (if (stringEmpty? dir) (ok ()) (makeDirs! dir))
        ((err e) (err e))
        ((ok _)
          (mt (dirList lockPath)
            ((ok _) (err "lock path is a directory"))
            ((err _) (lockLoop! lockPath)))))))

fn releaseFileLock! fd: Int64 -> (Result Unit String)
  (if (< fd 0)
    (ok ())
    (mt (fdClose fd) ((ok _) (ok ())) ((err e) (err (osErr e)))))

fn withFileLock! target: String body: (fn [] -> (Result T String)) -> (Result T String)
  (mt (acquireFileLock! target)
    ((err e) (err e))
    ((ok fd)
      (let [r (body)]
        (mt (releaseFileLock! fd)
          ((err e) (mt r ((ok _) (err e)) ((err e2) (err e2))))
          ((ok _) r)))))

fn lockAtLoop! root: String lockPath: String -> (Result Int64 String)
  (mt (fileLockAt root lockPath true)
    ((ok fd) (ok fd))
    ((err e) (if (= e "busy") (do (sleepMs 5) (lockAtLoop! root lockPath)) (err e))))

fn withSecureFileLock! root: String target: String body: (fn [] -> (Result T String)) -> (Result T String)
  (mt (lockAtLoop! root (str target ".lock"))
    ((err e) (err e))
    ((ok fd)
      (let [r (body)]
        (mt (releaseFileLock! fd)
          ((err e) (mt r ((ok _) (err e)) ((err e2) (err e2))))
          ((ok _) r)))))

fn isProcessAlive! pid: Int64 -> (Result Bool String)
  (if (or (<= pid 0) (> pid 2147483647))
    (ok false)
    (mt (procAlive? pid) ((ok b) (ok b)) ((err _) (ok false))))

fn digitEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 57)) (digitEnd bs (+ i 1) n) i)

fn pidAt name: String bs: Bytes i: Int64 n: Int64 -> (Option String)
  (let [c (bytesGet bs i)]
    (cond
      ((and (= c 46) (= (sub name i (+ i 5)) ".tmp."))
        (let [e (digitEnd bs (+ i 5) n)] (if (> e (+ i 5)) (some (sub name (+ i 5) e)) (none))))
      ((and (= c 100) (= (sub name i (+ i 13)) "dead_process_") (or (= i 0) (not (wordByte? (bytesGet bs (- i 1))))))
        (let [e (digitEnd bs (+ i 13) n)] (if (and (> e (+ i 13)) (= (sub name e (+ e 5)) ".lock")) (some (sub name (+ i 13) e)) (none))))
      ((= c 95)
        (let [e (digitEnd bs (+ i 1) n)] (if (and (> e (+ i 1)) (= (sub name e (+ e 5)) ".lock")) (some (sub name (+ i 1) e)) (none))))
      (else (none))))

fn pidInName name: String -> (Option String)
  (let [bs (stringToBytes name)
        n (bytesLength bs)]
    (pidScan name bs 0 n))

fn pidScan name: String bs: Bytes i: Int64 n: Int64 -> (Option String)
  (if (>= i n)
    (none)
    (mt (pidAt name bs i n) ((some d) (some d)) ((none) (pidScan name bs (+ i 1) n))))

fn pidAlive! p: IntParse -> (Result (Option Bool) String)
  (mt p
    ((intOk v) (mt (isProcessAlive! v) ((ok b) (ok (some b))) ((err e) (err e))))
    ((intHuge) (ok (some false)))
    ((intBad) (ok (none))))

fn cleanPidFile! pidFile: String rep: CleanupReport -> (Result CleanupReport String)
  (if (not (ok? (fileStat pidFile)))
    (ok rep)
    (mt (readTextFile! pidFile)
      ((err e) (ok (CleanupReport :scanned rep.scanned :cleanedFiles rep.cleanedFiles :cleanedLocks rep.cleanedLocks :failures (cons e rep.failures))))
      ((ok text)
        (mt (pidAlive! (pyInt text))
          ((err e) (err e))
          ((ok alive)
            (if (= alive (some false))
              (mt (pathRemove pidFile)
                ((ok _) (ok (CleanupReport :scanned rep.scanned :cleanedFiles (+ 1 rep.cleanedFiles) :cleanedLocks rep.cleanedLocks :failures rep.failures)))
                ((err e) (ok (CleanupReport :scanned rep.scanned :cleanedFiles rep.cleanedFiles :cleanedLocks rep.cleanedLocks :failures (cons (osErr e) rep.failures)))))
              (ok rep)))))))

fn cleanEntry! dir: String entry: String rep: CleanupReport -> (Result CleanupReport String)
  (let [full (pyJoin dir entry)
        seen (CleanupReport :scanned (+ 1 rep.scanned) :cleanedFiles rep.cleanedFiles :cleanedLocks rep.cleanedLocks :failures rep.failures)]
    (if (not (isFile? full))
      (ok seen)
      (mt (pidInName entry)
        ((none) (ok seen))
        ((some digits)
          (mt (pidAlive! (pyInt digits))
            ((err e) (err e))
            ((ok alive)
              (if (!= alive (some false))
                (ok seen)
                (mt (pathRemove full)
                  ((ok _)
                    (if (stringEndsWith? entry ".lock")
                      (ok (CleanupReport :scanned seen.scanned :cleanedFiles seen.cleanedFiles :cleanedLocks (+ 1 seen.cleanedLocks) :failures seen.failures))
                      (ok (CleanupReport :scanned seen.scanned :cleanedFiles (+ 1 seen.cleanedFiles) :cleanedLocks seen.cleanedLocks :failures seen.failures))))
                  ((err e) (ok (CleanupReport :scanned seen.scanned :cleanedFiles seen.cleanedFiles :cleanedLocks seen.cleanedLocks :failures (cons (osErr e) seen.failures))))))))))))

fn cleanEntries! dir: String entries: (List String) rep: CleanupReport -> (Result CleanupReport String)
  (mt (listHead entries)
    ((none) (ok rep))
    ((some e) (mt (cleanEntry! dir e rep) ((err x) (err x)) ((ok r) (cleanEntries! dir (rest entries) r)))))

fn cleanDirs! dirs: (List String) rep: CleanupReport -> (Result CleanupReport String)
  (mt (listHead dirs)
    ((none) (ok rep))
    ((some d)
      (if (not (ok? (fileStat d)))
        (cleanDirs! (rest dirs) rep)
        (mt (dirList d)
          ((err _) (cleanDirs! (rest dirs) rep))
          ((ok entries) (mt (cleanEntries! d entries rep) ((err x) (err x)) ((ok r) (cleanDirs! (rest dirs) r))))))))

fn defaultScanDirs root: String -> (List String)
  (map (fn [r] (pyJoin root r)) (list ".asl/mem" ".asl/log" "tmp" ".asl/mem/gaps" ".asl/mem/gaps/shards"))

fn cleanupStaleTempFiles! root: String scanDirs: (Option (List String)) pidFile: String -> (Result CleanupReport String)
  (mt (cleanPidFile! pidFile (CleanupReport :scanned 0 :cleanedFiles 0 :cleanedLocks 0 :failures (list)))
    ((err e) (err e))
    ((ok rep) (cleanDirs! (optionOr scanDirs (defaultScanDirs root)) rep)))

fn pidFileFor root: String envValue: (Option String) -> String
  (let [v (optionOr envValue "")]
    (if (stringEmpty? v) (pyJoin root "tmp/asl-mesh.pid") v))

fn cleanupStaleTempFilesEnv! root: String scanDirs: (Option (List String)) -> (Result CleanupReport String)
  (cleanupStaleTempFiles! root scanDirs (pidFileFor root (envGet "ASL_MESH_PID_FILE")))

fn cleanupMetrics r: CleanupReport -> AsnValue
  (asnDict (list (pair "scanned" (asnInt r.scanned)) (pair "cleaned_files" (asnInt r.cleanedFiles)) (pair "cleaned_locks" (asnInt r.cleanedLocks))))

fn intOfValue v: AsnValue -> (Result Int64 String)
  (mt v
    ((asnInt i) (ok i))
    ((asnBool b) (ok (if b 1 0)))
    ((asnFloat f)
      (if (not (isFinite? f))
        (err "ValueError: cannot convert float NaN or infinity to integer")
        (mt (float64ToInt64 f)
          ((some n) (ok n))
          ((none) (err "OverflowError: float too large to convert to integer")))))
    ((asnStr s)
      (mt (pyInt s)
        ((intOk n) (ok n))
        ((intHuge) (err (str "ValueError: integer beyond Int64: " (pyReprStr s))))
        ((intBad) (err (str "ValueError: invalid literal for int() with base 10: " (pyReprStr s))))))
    (_ (err (str "TypeError: int() argument must be a string, a bytes-like object or a real number, not '" (typeName v) "'"))))

fn floatOfValue v: AsnValue -> (Result Float64 String)
  (mt v
    ((asnFloat f) (ok f))
    ((asnInt i) (ok (int64ToFloat64 i)))
    ((asnBool b) (ok (if b 1.0 0.0)))
    ((asnStr s) (mt (pyFloat s) ((some f) (ok f)) ((none) (err (str "ValueError: could not convert string to float: " (pyReprStr s))))))
    (_ (err (str "TypeError: float() argument must be a string or a real number, not '" (typeName v) "'"))))

fn fallbackId! -> String
  (str "DEF-" (stringFromInt64 (/ (nowNs) 1000000)))

fn shardBody id: String target: String intent: String attractor: String auditor: String severity: String hazard: String evidence: String status: String confirmations: Int64 remediation: String -> String
  (str "(:defect\n  :id \"" id "\"\n  :target \"" target "\"\n  :intent :" intent "\n  :attractor " attractor
       "\n  :auditor \"" auditor "\"\n  :severity :" severity "\n  :hazard \"" hazard "\"\n  :evidence \"" evidence
       "\"\n  :status :" status "\n  :confirmations " (stringFromInt64 confirmations) "\n  :remediation \"" remediation "\")\n")

fn saveDefectShard! d: AsnValue shardsDir: String root: String -> (Result String String)
  (if (stringEmpty? shardsDir)
    (err "ValueError: save_defect_shard needs a shards_dir; set ASL_MESH_STATE_DIR for scratch runs")
    (mt (makeDirs! shardsDir)
      ((err e) (err e))
      ((ok _)
        (mt (getAttr d "id")
          ((err e) (err e))
          ((ok idRaw)
            (let [idv (if (truthy? idRaw) idRaw (asnStr (fallbackId!)))]
              (mt idv
                ((asnStr defId)
                  (let [es (optionOr (dictOf d) (list))
                        shardFile (pyJoin shardsDir (str "defect_" (safeDefectId defId) ".asn"))
                        target (sanitizeAsnString (getOr es "target" (asnStr "unknown")))
                        intent (lstripColon (pyStr (getOr es "intent" (asnStr "falsification"))))
                        attractor (renderAttractor (getOr es "attractor" (asnStr "verification")))
                        auditor (sanitizeAsnString (getOr es "auditor" (asnStr "unknown")))
                        severity (normalizeSeverity (getOr es "severity" (asnStr "medium")))
                        hazard (sanitizeAsnString (getOr es "hazard" (asnStr "")))
                        evidence (sanitizeAsnString (getOr es "evidence" (asnStr "")))
                        status (lstripColon (pyStr (getOr es "status" (asnStr "candidate"))))]
                    (mt (intOfValue (getOr es "confirmations" (asnInt 1)))
                      ((err e) (err e))
                      ((ok conf)
                        (let [remediation (sanitizeAsnString (getOr es "remediation" (asnStr "")))]
                          (mt (transitionAllowed! (asnStr status) d root)
                            ((err e) (err e))
                            ((ok verdict)
                              (if (not (pairFirst verdict))
                                (err (str "ValueError: refusing to write " defId " as :" status ": " (pairSecond verdict)))
                                (mt (atomicWriteFile! shardFile (shardBody defId target intent attractor auditor severity hazard evidence status conf remediation))
                                  ((err e) (err e))
                                  ((ok _) (ok shardFile)))))))))))
                (_ (err "TypeError: expected string or bytes-like object")))))))))

fn plainField text: String key: String -> (Option String)
  (let [bs (stringToBytes text)]
    (keyPlainFrom text bs (bytesLength bs) key 0))

fn statusByte? b: Int64 -> Bool
  (or (letter? b) (and (>= b 48) (<= b 57)) (= b 95) (= b 45))

fn statusFrom text: String bs: Bytes n: Int64 i: Int64 -> (Option String)
  (let [p (findStr bs n ":status" i)]
    (if (< p 0)
      (none)
      (let [a (+ p 7)
            b (skipSpace bs a n)
            e (if (and (> b a) (< b n) (= (bytesGet bs b) 58)) (runEnd bs (+ b 1) n statusByte?) -1)]
        (if (> e (+ b 1)) (some (sub text (+ b 1) e)) (statusFrom text bs n (+ p 1))))))

fn shardFromText content: String -> (Option AsnValue)
  (mt (listHead (extractGapBlocks content "defect"))
    ((some b) (some (parseGapBlock b)))
    ((none)
      (mt (plainField content ":id")
        ((none) (none))
        ((some id)
          (mt (plainField content ":target")
            ((none) (none))
            ((some tgt)
              (let [bs (stringToBytes content)]
                (some (asnDict (list (pair "id" (asnStr id)) (pair "target" (asnStr tgt))
                                     (pair "status" (asnStr (optionOr (statusFrom content bs (bytesLength bs) 0) "candidate")))
                                     (pair "content" (asnStr content))))))))))))

fn shardName? f: String -> Bool
  (and (stringEndsWith? f ".asn") (stringStartsWith? f "defect_"))

fn loadShards! dir: String names: (List String) acc: ShardLoad -> ShardLoad
  (mt (listHead names)
    ((none) (ShardLoad :shards (listReverse acc.shards) :failures (listReverse acc.failures)))
    ((some f)
      (mt (readTextFile! (pyJoin dir f))
        ((err e) (loadShards! dir (rest names) (ShardLoad :shards acc.shards :failures (cons e acc.failures))))
        ((ok content)
          (mt (shardFromText content)
            ((some s) (loadShards! dir (rest names) (ShardLoad :shards (cons s acc.shards) :failures acc.failures)))
            ((none) (loadShards! dir (rest names) acc)))))))

fn loadShardedBlackboard! shardsDir: String -> ShardLoad
  (if (not (ok? (fileStat shardsDir)))
    (ShardLoad :shards (list) :failures (list))
    (mt (dirList shardsDir)
      ((err e) (ShardLoad :shards (list) :failures (list (osErr e))))
      ((ok names) (loadShards! shardsDir (filter shardName? names) (ShardLoad :shards (list) :failures (list))))))

fn archiveOne! shardsDir: String archiveDir: String f: String r: CompactReport -> CompactReport
  (mt (pathRename (pyJoin shardsDir f) (pyJoin archiveDir f))
    ((ok _) (CompactReport :archivedShards (+ 1 r.archivedShards) :compactedEvents r.compactedEvents :failures r.failures))
    ((err e) (CompactReport :archivedShards r.archivedShards :compactedEvents r.compactedEvents :failures (cons (osErr e) r.failures))))

fn archiveClosed! shardsDir: String archiveDir: String names: (List String) r: CompactReport -> CompactReport
  (fold (fn [acc f]
          (mt (readTextFile! (pyJoin shardsDir f))
            ((err e) (CompactReport :archivedShards acc.archivedShards :compactedEvents acc.compactedEvents :failures (cons e acc.failures)))
            ((ok content)
              (if (or (stringContains? content ":status :applied") (stringContains? content ":status :refuted"))
                (archiveOne! shardsDir archiveDir f acc)
                acc))))
    r names)

fn keepEndsLines text: String -> (List String)
  (if (stringEmpty? text)
    (list)
    (let [parts (stringSplit text "\n")
          n (listLength parts)
          lastPart (optionOr (listLast parts) "")]
      (listAppend (map (fn [p] (str p "\n")) (listTake parts (- n 1))) (if (stringEmpty? lastPart) (list) (list lastPart)))))

fn tailSlice xs: (List T) m: Int64 -> (List T)
  (let [n (listLength xs)]
    (cond
      ((= m 0) xs)
      ((> m 0) (listDrop xs (max 0 (- n m))))
      (else (listDrop xs (- 0 m)))))

fn compactTelemetry! telPath: String maxTel: Int64 r: CompactReport -> CompactReport
  (if (or (stringEmpty? telPath) (not (ok? (fileStat telPath))))
    r
    (mt (readTextFile! telPath)
      ((err e) (CompactReport :archivedShards r.archivedShards :compactedEvents r.compactedEvents :failures (cons e r.failures)))
      ((ok text)
        (let [lines (keepEndsLines text)
              n (listLength lines)]
          (if (<= n maxTel)
            r
            (mt (atomicWriteFile! telPath (stringJoin (tailSlice lines maxTel) ""))
              ((ok _) (CompactReport :archivedShards r.archivedShards :compactedEvents (+ r.compactedEvents (- n maxTel)) :failures r.failures))
              ((err e) (CompactReport :archivedShards r.archivedShards :compactedEvents r.compactedEvents :failures (cons e r.failures)))))))))

fn shardNames! dir: String -> (Result (List String) String)
  (mt (dirList dir) ((ok names) (ok (filter shardName? names))) ((err e) (err (osErr e))))

fn compactObservationMemory! shardsDir: String archiveDir: String maxActive: Int64 maxTel: Int64 telPath: String -> (Result CompactReport String)
  (mt (makeDirs! shardsDir)
    ((err e) (err e))
    ((ok _)
      (mt (makeDirs! archiveDir)
        ((err e) (err e))
        ((ok _)
          (let [r0 (CompactReport :archivedShards 0 :compactedEvents 0 :failures (list))
                r1 (mt (shardNames! shardsDir) ((ok names) (archiveClosed! shardsDir archiveDir names r0)) ((err e) (CompactReport :archivedShards 0 :compactedEvents 0 :failures (list e))))]
            (mt (shardNames! shardsDir)
              ((err e) (err e))
              ((ok remaining)
                (let [n (listLength remaining)
                      r2 (if (> n maxActive)
                           (fold (fn [acc f] (archiveOne! shardsDir archiveDir f acc)) r1 (listTake remaining (- n maxActive)))
                           r1)
                      r3 (compactTelemetry! telPath maxTel r2)]
                  (ok (CompactReport :archivedShards r3.archivedShards :compactedEvents r3.compactedEvents :failures (listReverse r3.failures)))))))))))

fn compactMetrics r: CompactReport -> AsnValue
  (asnDict (list (pair "status" (asnStr "ok")) (pair "archived_shards" (asnInt r.archivedShards)) (pair "compacted_events" (asnInt r.compactedEvents))))

fn writeShardForBlock! defId: String block: String shardsDir: String -> (Result Unit String)
  (mt (makeDirs! shardsDir)
    ((err e) (err e))
    ((ok _) (atomicWriteFile! (pyJoin shardsDir (str "defect_" (safeDefectId defId) ".asn")) (shardTextFromBlock block))))

fn syncShards! shardsDir: String blocks: (List String) keep: (List String) -> (Result (List String) String)
  (mt (listHead blocks)
    ((none) (ok keep))
    ((some b)
      (mt (getOr (optionOr (dictOf (parseGapBlock b)) (list)) "id" (asnNone))
        ((asnStr did)
          (if (stringEmpty? did)
            (syncShards! shardsDir (rest blocks) keep)
            (let [name (str "defect_" (safeDefectId did) ".asn")
                  path (pyJoin shardsDir name)
                  want (shardTextFromBlock b)
                  same (mt (readTextFile! path) ((ok have) (= have want)) ((err _) false))]
              (if same
                (syncShards! shardsDir (rest blocks) (cons name keep))
                (mt (atomicWriteFile! path want)
                  ((err e) (err e))
                  ((ok _) (syncShards! shardsDir (rest blocks) (cons name keep))))))))
        (_ (syncShards! shardsDir (rest blocks) keep)))))

fn dropStale! shardsDir: String names: (List String) keep: (List String) -> (Result Unit String)
  (mt (listHead names)
    ((none) (ok ()))
    ((some f)
      (if (or (not (shardName? f)) (listContains? keep f))
        (dropStale! shardsDir (rest names) keep)
        (let [p (pyJoin shardsDir f)]
          (if (isDir? p)
            (err (str "OSError: unlink " p ": is a directory"))
            (mt (pathRemove p)
              ((err e) (err (osErr e)))
              ((ok _) (dropStale! shardsDir (rest names) keep))))))))

fn writeBoard! bbPath: String content: String shardsDir: String -> (Result Unit String)
  (mt (atomicWriteFile! bbPath content)
    ((err e) (err e))
    ((ok _)
      (if (stringEmpty? shardsDir)
        (ok ())
        (mt (makeDirs! shardsDir)
          ((err e) (err e))
          ((ok _)
            (mt (syncShards! shardsDir (extractGapBlocks content "defect") (list))
              ((err e) (err e))
              ((ok keep)
                (mt (dirList shardsDir)
                  ((err e) (err (osErr e)))
                  ((ok names) (dropStale! shardsDir names keep))))))))))

fn cpLength s: String -> Int64
  (let [bs (stringToBytes s)]
    (cpLoop bs 0 (bytesLength bs) 0))

fn cpLoop bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (cpLoop bs (+ i 1) n (if (and (>= (bytesGet bs i) 128) (< (bytesGet bs i) 192)) acc (+ acc 1))))

fn breakLen bs: Bytes i: Int64 n: Int64 -> Int64
  (let [b (bytesGet bs i)]
    (cond
      ((= b 13) (if (and (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 10)) 2 1))
      ((or (= b 10) (= b 11) (= b 12) (= b 28) (= b 29) (= b 30)) 1)
      ((and (= b 194) (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 133)) 2)
      ((and (= b 226) (< (+ i 2) n) (= (bytesGet bs (+ i 1)) 128) (or (= (bytesGet bs (+ i 2)) 168) (= (bytesGet bs (+ i 2)) 169))) 3)
      (else 0)))

fn splitLinesLoop s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< start n) (cons (sub s start n) acc) acc))
    (let [k (breakLen bs i n)]
      (if (> k 0)
        (splitLinesLoop s bs (+ i k) (+ i k) n (cons (sub s start i) acc))
        (splitLinesLoop s bs (+ i 1) start n acc))))

fn splitLines s: String -> (List String)
  (let [bs (stringToBytes s)]
    (splitLinesLoop s bs 0 0 (bytesLength bs) (list)))

fn sigLine? stripped: String -> Bool
  (listAny? (fn [p] (stringStartsWith? stripped p)) (list "(module" "fn " "(schema" "(struct" "(enum" "(:" "(def"))

fn sigLines lines: (List String) acc: (List String) -> (List String)
  (mt (listHead lines)
    ((none) (listReverse acc))
    ((some l)
      (if (or (sigLine? (pyStrip l)) (< (listLength acc) 20))
        (sigLines (rest lines) (cons l acc))
        (sigLines (rest lines) acc))))

fn fileSummary text: String -> String
  (if (<= (cpLength text) 1500)
    (pyStrip text)
    (let [content (filter (fn [l] (let [t (pyStrip l)] (not (or (stringStartsWith? t ";;") (stringStartsWith? t "//"))))) (splitLines text))]
      (str (stringJoin (listTake (sigLines (listTake content 40) (list)) 20) "\n")
           "\n;; ... [AST preview bounded; full file is 100% Dyck-1 balanced on disk]")))

schema DigestState
  (:f items (List String))
  (:f len Int64)
  (:f failures (List String))

fn fileItem! root: String fp: String -> (Result String String)
  (mt (readTextFile! fp)
    ((err e) (err e))
    ((ok text) (ok (str ";; Target: " (relPath! fp root) "\n" (fileSummary text) "\n"))))

fn addItem st: DigestState item: String maxChars: Int64 -> (Pair DigestState Bool)
  (let [k (cpLength item)]
    (if (< (+ st.len k) maxChars)
      (pair (DigestState :items (cons item st.items) :len (+ st.len k) :failures st.failures) true)
      (pair st false)))

fn addFailure st: DigestState e: String -> DigestState
  (DigestState :items st.items :len st.len :failures (cons e st.failures))

fn sourceFile? f: String -> Bool
  (listAny? (fn [x] (stringEndsWith? f x)) (list ".asl" ".asn" ".c" ".h" ".sh"))

fn prunedDir? d: String -> Bool
  (listContains? (list ".git" "node_modules" "dist" "tmp" ".asl" "target") d)

fn walkFiles! root: String dir: String files: (List String) maxChars: Int64 st: DigestState -> DigestState
  (mt (listHead files)
    ((none) st)
    ((some f)
      (if (not (sourceFile? f))
        (walkFiles! root dir (rest files) maxChars st)
        (mt (fileItem! root (pyJoin dir f))
          ((err e) (walkFiles! root dir (rest files) maxChars (addFailure st e)))
          ((ok item)
            (let [r (addItem st item maxChars)]
              (if (pairSecond r) (walkFiles! root dir (rest files) maxChars (pairFirst r)) (pairFirst r))))))))

fn walkDir! root: String dir: String maxChars: Int64 st: DigestState -> (Pair DigestState Bool)
  (mt (dirList dir)
    ((err _) (pair st false))
    ((ok names)
      (let [dirs (filter (fn [x] (isDir? (pyJoin dir x))) names)
            files (filter (fn [x] (not (isDir? (pyJoin dir x)))) names)
            st1 (walkFiles! root dir files maxChars st)]
        (if (>= st1.len maxChars)
          (pair st1 true)
          (walkSubdirs! root dir (filter (fn [x] (not (prunedDir? x))) dirs) maxChars st1)))))

fn walkSubdirs! root: String dir: String subs: (List String) maxChars: Int64 st: DigestState -> (Pair DigestState Bool)
  (mt (listHead subs)
    ((none) (pair st false))
    ((some d)
      (let [r (walkDir! root (pyJoin dir d) maxChars st)]
        (if (pairSecond r) r (walkSubdirs! root dir (rest subs) maxChars (pairFirst r))))))

fn distillPath! root: String p: String maxChars: Int64 st: DigestState -> DigestState
  (let [full (pyJoin root p)]
    (cond
      ((not (ok? (fileStat full))) st)
      ((isFile? full)
        (mt (fileItem! root full)
          ((err e) (addFailure st e))
          ((ok item) (pairFirst (addItem st item maxChars)))))
      (else (pairFirst (walkDir! root full maxChars st)))))

fn distillShard! root: String paths: (List String) maxChars: Int64 -> Distilled
  (let [st (fold (fn [acc p] (distillPath! root p maxChars acc)) (DigestState :items (list) :len 0 :failures (list)) paths)]
    (Distilled :digest (stringJoin (listReverse st.items) "\n") :failures (listReverse st.failures)))

fn s v: String -> AsnValue
  (asnStr v)

fn strs xs: (List String) -> AsnValue
  (asnList (map (fn [x] (asnStr x)) xs))

fn boundaryAt? bs: Bytes i: Int64 n: Int64 -> Bool
  (or (>= i n) (not (wordByte? (bytesGet bs i))))

fn meshStart text: String bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    -1
    (let [c (bytesGet bs i)]
      (cond
        ((and (= c 40) (= (sub text i (+ i 12)) "(:meshConfig") (boundaryAt? bs (+ i 12) n)) i)
        ((and (= c 58) (= (sub text i (+ i 5)) ":mesh")
              (let [j (skipSpace bs (+ i 5) n)] (and (< j n) (= (bytesGet bs j) 40))))
          (skipSpace bs (+ i 5) n))
        ((and (= c 40) (= (sub text i (+ i 6)) "(:mesh") (boundaryAt? bs (+ i 6) n)) i)
        (else (meshStart text bs (+ i 1) n)))))

fn meshValue content: String resolved: String -> (Pair AsnValue String)
  (let [bs (stringToBytes content)
        n (bytesLength bs)
        p (meshStart content bs 0 n)
        e (if (< p 0) -1 (scanClose bs n p 0 false false false))]
    (if (< e 0)
      (pair (asnDict (list)) "")
      (mt (tokenizeAsn (sub content p (+ e 1)))
        ((err msg) (pair (asnDict (list)) (str "[Config Error] Failed to parse config from " resolved ": " msg "\n")))
        ((ok toks) (pair (pairFirst (parseAsnForm toks 0)) "")))))

fn lstripAttr v: AsnValue -> (Result String String)
  (mt v
    ((asnStr x) (ok (lstripColon x)))
    (_ (err (str "AttributeError: '" (typeName v) "' object has no attribute 'lstrip'"))))

fn joinVal root: String v: AsnValue -> (Result AsnValue String)
  (mt v
    ((asnStr x) (ok (asnStr (pyJoin root x))))
    (_ (err (str "TypeError: expected str, bytes or os.PathLike object, not '" (typeName v) "'"))))

fn listItems v: AsnValue -> (Option (List AsnValue))
  (mt v ((asnList xs) (some xs)) (_ (none)))

fn dictItems v: AsnValue -> (List (List (Pair String AsnValue)))
  (fold (fn [acc x] (mt (dictOf x) ((some es) (cons es acc)) ((none) acc))) (list) (optionOr (listItems v) (list)))

fn dictItemsInOrder v: AsnValue -> (List (List (Pair String AsnValue)))
  (listReverse (dictItems v))

fn buildProfiles items: (List (List (Pair String AsnValue))) acc: (List (Pair String AsnValue)) active: (Option String) -> (Pair (List (Pair String AsnValue)) (Option String))
  (mt (listHead items)
    ((none) (pair acc active))
    ((some p)
      (let [pid (lstripColon (pyStr (getOr p "id" (s ""))))
            act (getOr p "active" (asnBool false))
            roles (fold (fn [r kv] (dictPut r (lstripColon (pairFirst kv)) (pairSecond kv))) (list) (subDict p "roles"))
            prof (asnDict (list (pair "id" (s pid)) (pair "active" act) (pair "description" (getOr p "description" (s ""))) (pair "roles" (asnDict roles))))]
        (buildProfiles (rest items) (dictPut acc pid prof) (if (and (truthy? act) (stringEmpty? (optionOr active ""))) (some pid) active)))))

fn roleModel intent: String roles: (List (Pair String AsnValue)) model: AsnValue -> AsnValue
  (let [has (fn [k] (some? (dictGet roles k)))]
    (cond
      ((listEmpty? roles) model)
      ((and (= intent "falsify") (has "falsifier")) (getOr roles "falsifier" model))
      ((and (= intent "construct") (has "coder")) (getOr roles "coder" model))
      ((and (= intent "reconcile") (or (has "reconciler") (has "planner"))) (getOr roles "reconciler" (getOr roles "planner" (asnNone))))
      ((and (= intent "discover") (has "scout")) (getOr roles "scout" model))
      ((and (= intent "deliberate") (has "chiefJustice")) (getOr roles "chiefJustice" model))
      (else model)))

fn buildShard sh: (List (Pair String AsnValue)) roles: (List (Pair String AsnValue)) -> (Result AsnValue String)
  (mt (lstripAttr (getOr sh "intent" (s ":falsify")))
    ((err e) (err e))
    ((ok intent)
      (let [model (roleModel intent roles (getOr sh "model" (s "qwen/qwen3.8-27b:free")))]
        (mt (lstripAttr (getOr sh "attractor" (s ":verification")))
          ((err e) (err e))
          ((ok attractor)
            (mt (floatOfValue (getOr sh "temp" (asnFloat 0.55)))
              ((err e) (err e))
              ((ok temp)
                (mt (lstripAttr (getOr sh "suggestedSeverity" (s ":medium")))
                  ((err e) (err e))
                  ((ok sev)
                    (ok (asnDict (list (pair "id" (getOr sh "id" (s "shard-unknown"))) (pair "name" (getOr sh "name" (s "Unnamed Shard")))
                                       (pair "paths" (getOr sh "paths" (asnList (list)))) (pair "intent" (s intent)) (pair "attractor" (s attractor))
                                       (pair "model" model) (pair "temp" (asnFloat temp)) (pair "suggestedSeverity" (s sev))
                                       (pair "focus" (getOr sh "focus" (s "")))))))))))))))

fn buildShards items: (List (List (Pair String AsnValue))) roles: (List (Pair String AsnValue)) acc: (List AsnValue) -> (Result (List AsnValue) String)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some sh) (mt (buildShard sh roles) ((err e) (err e)) ((ok v) (buildShards (rest items) roles (cons v acc))))))

fn shardRow id: String name: String paths: (List String) intent: String attractor: String model: String temp: Float64 sev: String focus: String -> AsnValue
  (asnDict (list (pair "id" (s id)) (pair "name" (s name)) (pair "paths" (strs paths)) (pair "intent" (s intent)) (pair "attractor" (s attractor))
                 (pair "model" (s model)) (pair "temp" (asnFloat temp)) (pair "suggestedSeverity" (s sev)) (pair "focus" (s focus))))

fn defaultShards -> (List AsnValue)
  (list
    (shardRow "shard-compiler" "Core Compiler & IR Substrate" (list "asl/packages/asl-compiler" "asl/packages/asl-ir" "asl/packages/asl-eval") "falsify" "verification" "google/gemma-4-31b-it:free" 0.55 "critical" "Logic flaws, reentrancy vulnerabilities in AST lowering, and memory/VFS transaction leakage")
    (shardRow "shard-mesh" "Mesh & Concurrency Bus" (list "agent" "asl/packages/asl-mesh" "asl/packages/asl-gateway") "falsify" "reversibility" "qwen/qwen3.8-27b:free" 0.60 "critical" "Write-skew anomalies, lock-free ABA race conditions, deadlocks, and unhandled async reset cascades under high load")
    (shardRow "shard-grammar" "Grammar, Syntax & Delimiters" (list "asl/grammar" "asl/packages/asl-parser" "asl/packages/asl-checker") "falsify" "simplicity" "nex-agi/nex-n2.5-pro:free" 0.25 "high" "Pure Dyck-1 wire delimiters, non-vacuous contract bypasses, and zero truthiness adherence")
    (shardRow "shard-tools" "Host Tools & Boundaries" (list "tools" "bin") "falsify" "containment" "nvidia/nemotron-3-super-120b-a12b:free" 0.20 "high" "C-transpilation remnants, unescaped shell invocations, foreign dependencies, and L0-L3 architectural stratification violations")
    (shardRow "shard-harness" "Tests, Harnesses & Dead Code" (list "harness" "tests") "falsify" "verification" "cohere/north-mini-code:free" 0.45 "medium" "Vacuous passes lacking executed assertions, dead code paths, obsolete declarations, and mock fraud")
    (shardRow "shard-codegen" "Native Codegen & Multi-Target Transpilers" (list "asl/packages/asl-target-llvm" "asl/packages/asl-target-wat" "asl/packages/asl-target-c" "asl/packages/asl-transpile") "construct" "simplicity" "poolside/laguna-xs-2.1:free" 0.15 "critical" "SSA emission correctness, register allocation, WebAssembly instruction encoding, and transpile fidelity")
    (shardRow "shard-convergence" "Tri-Map Reconciliation & Gap Closure" (list ".asl/mem" "harness/audit") "reconcile" "convergence" "z-ai/glm-5.2:free" 0.20 "high" "Tri-Map reconciliation across intent atoms, gates, and diff hunks; debt elimination and horizon tracking")
    (shardRow "shard-macro" "Macro Architecture & Invariant Boundary Isolation" (list "manifest.asn" ".asl.config.asn" "mesh.audit.aslconfig" "asl/grammar/rules.asn") "discover" "containment" "nvidia/nemotron-3-ultra-550b-a55b:free" 0.20 "critical" "Monorepo zero-remote invariant, cross-package boundary isolation, circular dependency cycles, and systemic architectural drift"))

fn buildPeers items: (List (List (Pair String AsnValue))) acc: (List (Pair String AsnValue)) -> (Result (List (Pair String AsnValue)) String)
  (mt (listHead items)
    ((none) (ok acc))
    ((some pr)
      (if (not (and (some? (dictGet pr "origin")) (some? (dictGet pr "peer"))))
        (buildPeers (rest items) acc)
        (mt (floatOfValue (getOr pr "peerTemp" (asnFloat 0.50)))
          ((err e) (err e))
          ((ok t)
            (mt (getOr pr "origin" (asnNone))
              ((asnStr o) (buildPeers (rest items) (dictPut acc o (asnTuple (list (getOr pr "peer" (asnNone)) (asnFloat t))))))
              (bad (err (str "TypeError: origin keys other than str are not supported, got '" (typeName bad) "'")))))))))

fn peerRow o: String p: String t: Float64 -> (Pair String AsnValue)
  (pair o (asnTuple (list (s p) (asnFloat t))))

fn defaultPeers -> (List (Pair String AsnValue))
  (list (peerRow "google/gemma-4-31b-it:free" "qwen/qwen3.8-27b:free" 0.50)
        (peerRow "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free" 0.50)
        (peerRow "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free" 0.20)
        (peerRow "nvidia/nemotron-3-super-120b-a12b:free" "nex-agi/nex-n2.5-pro:free" 0.25)
        (peerRow "cohere/north-mini-code:free" "poolside/laguna-xs-2.1:free" 0.15)
        (peerRow "poolside/laguna-xs-2.1:free" "cohere/north-mini-code:free" 0.45)
        (peerRow "z-ai/glm-5.2:free" "nvidia/nemotron-3-ultra-550b-a55b:free" 0.20)
        (peerRow "nvidia/nemotron-3-ultra-550b-a55b:free" "z-ai/glm-5.2:free" 0.20))

fn buildCascades items: (List (List (Pair String AsnValue))) acc: (List (Pair String AsnValue)) -> (Result (List (Pair String AsnValue)) String)
  (mt (listHead items)
    ((none) (ok acc))
    ((some c)
      (if (not (and (some? (dictGet c "primary")) (some? (dictGet c "fallbackChain"))))
        (buildCascades (rest items) acc)
        (mt (getOr c "primary" (asnNone))
          ((asnStr p) (buildCascades (rest items) (dictPut acc p (getOr c "fallbackChain" (asnNone)))))
          (bad (err (str "TypeError: primary keys other than str are not supported, got '" (typeName bad) "'")))))))

fn defaultCascades -> (List (Pair String AsnValue))
  (list (pair "google/gemma-4-31b-it:free" (strs (list "qwen/qwen3.8-27b:free" "nex-agi/nex-n2.5-pro:free" "cohere/north-mini-code:free")))
        (pair "qwen/qwen3.8-27b:free" (strs (list "google/gemma-4-31b-it:free" "nvidia/nemotron-3-ultra-550b-a55b:free" "z-ai/glm-5.2:free")))
        (pair "nex-agi/nex-n2.5-pro:free" (strs (list "nvidia/nemotron-3-super-120b-a12b:free" "poolside/laguna-xs-2.1:free" "google/gemma-4-31b-it:free")))
        (pair "nvidia/nemotron-3-super-120b-a12b:free" (strs (list "nvidia/nemotron-3-ultra-550b-a55b:free" "z-ai/glm-5.2:free" "nex-agi/nex-n2.5-pro:free")))
        (pair "cohere/north-mini-code:free" (strs (list "poolside/laguna-xs-2.1:free" "google/gemma-4-31b-it:free" "qwen/qwen3.8-27b:free")))
        (pair "z-ai/glm-5.2:free" (strs (list "nvidia/nemotron-3-ultra-550b-a55b:free" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free")))
        (pair "poolside/laguna-xs-2.1:free" (strs (list "cohere/north-mini-code:free" "google/gemma-4-31b-it:free" "nex-agi/nex-n2.5-pro:free")))
        (pair "nvidia/nemotron-3-ultra-550b-a55b:free" (strs (list "z-ai/glm-5.2:free" "nvidia/nemotron-3-super-120b-a12b:free" "qwen/qwen3.8-27b:free"))))

fn buildPipeline items: (List (List (Pair String AsnValue))) acc: (List AsnValue) -> (Result (List AsnValue) String)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some chk)
      (mt (lstripAttr (getOr chk "id" (s ":check")))
        ((err e) (err e))
        ((ok cid)
          (let [cmd (getOr chk "cmd" (s ""))
                ev (getOr chk "eval" (s ""))]
            (if (or (truthy? cmd) (truthy? ev))
              (buildPipeline (rest items) (cons (asnDict (list (pair "id" (s cid)) (pair "cmd" cmd) (pair "eval" ev) (pair "doc" (getOr chk "doc" (s ""))))) acc))
              (buildPipeline (rest items) acc)))))))

fn defaultPipeline -> (List AsnValue)
  (list (asnDict (list (pair "id" (s "delimiters")) (pair "cmd" (s "./bin/asl audit consistency")) (pair "doc" (s "Zero Dyck-1 delimiter violations and 6-dimension consistency"))))
        (asnDict (list (pair "id" (s "pureAsl")) (pair "cmd" (s "./bin/asl audit foreign")) (pair "doc" (s "100% pure ASL without foreign code leakage"))))
        (asnDict (list (pair "id" (s "gates")) (pair "cmd" (s "./bin/asl audit gates --static")) (pair "doc" (s "Verify 7 core pure ASL verification gates"))))
        (asnDict (list (pair "id" (s "grammarCheck")) (pair "cmd" (s "./bin/asl check asl/grammar/rules.asn")) (pair "doc" (s "Syntax and balance of SSOT rules"))))
        (asnDict (list (pair "id" (s "executableGate")) (pair "eval" (s "(= (+ 40 2) 42)")) (pair "doc" (s "Pure ASL dynamic functional expression gate"))))
        (asnDict (list (pair "id" (s "descriptorValidation")) (pair "eval" (s "(= (listLength (list 1 2 3)) 3)")) (pair "doc" (s "Pure ASL in-memory runtime structure verification")))))

fn buildHooks items: (List (List (Pair String AsnValue))) acc: (List (Pair String AsnValue)) -> (Result (List (Pair String AsnValue)) String)
  (mt (listHead items)
    ((none) (ok acc))
    ((some h)
      (mt (lstripAttr (getOr h "event" (s "")))
        ((err e) (err e))
        ((ok ev)
          (mt (lstripAttr (getOr h "action" (s "")))
            ((err e) (err e))
            ((ok act)
              (if (stringEmpty? ev)
                (buildHooks (rest items) acc)
                (buildHooks (rest items) (dictPut acc ev (asnDict (list (pair "action" (s act)) (pair "eval" (getOr h "eval" (s ""))) (pair "doc" (getOr h "doc" (s ""))))))))))))))

fn buildTaxonomy items: (List (List (Pair String AsnValue))) acc: (List AsnValue) -> (Result (List AsnValue) String)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some t)
      (mt (lstripAttr (getOr t "id" (s "")))
        ((err e) (err e))
        ((ok id)
          (mt (lstripAttr (getOr t "severity" (s "medium")))
            ((err e) (err e))
            ((ok sev) (buildTaxonomy (rest items) (cons (asnDict (list (pair "id" (s id)) (pair "severity" (s sev)) (pair "doc" (getOr t "doc" (s ""))))) acc))))))))

fn strItems v: AsnValue f: (fn [String] -> String) -> (List AsnValue)
  (fold (fn [acc x] (mt x ((asnStr y) (cons (asnStr (f y)) acc)) (_ acc))) (list) (optionOr (listItems v) (list)))

fn strItemsInOrder v: AsnValue f: (fn [String] -> String) -> (List AsnValue)
  (listReverse (strItems v f))

fn nestedRows v: AsnValue -> (List AsnValue)
  (listReverse
    (fold (fn [acc x] (mt x ((asnList _) (cons (asnList (strItemsInOrder x lstripColon)) acc)) (_ acc))) (list) (optionOr (listItems v) (list))))

fn orDefault xs: (List AsnValue) d: (List AsnValue) -> AsnValue
  (asnList (if (listEmpty? xs) d xs))

fn buildRotation rot: (List (Pair String AsnValue)) -> AsnValue
  (let [regime (getOr rot "attractorRegime" (s "triple"))]
    (asnDict (list (pair "enabled" (getOr rot "enabled" (asnBool true)))
                   (pair "rotate_models" (getOr rot "rotateModels" (asnBool true)))
                   (pair "rotate_attractors" (getOr rot "rotateAttractors" (asnBool true)))
                   (pair "attractor_regime" (mt regime ((asnStr x) (s (lstripColon x))) (_ regime)))
                   (pair "cycle_models" (orDefault (strItemsInOrder (getOr rot "cycleModels" (asnList (list))) (fn [x] (stripByte x 34)))
                                          (map s (list "google/gemma-4-31b-it:free" "qwen/qwen3.8-27b:free" "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free" "cohere/north-mini-code:free" "z-ai/glm-5.2:free" "poolside/laguna-xs-2.1:free" "nvidia/nemotron-3-ultra-550b-a55b:free"))))
                   (pair "cycle_attractors" (orDefault (strItemsInOrder (getOr rot "cycleAttractors" (asnList (list))) lstripColon)
                                              (map s (list "verification" "reversibility" "simplicity" "containment" "convergence"))))
                   (pair "synthesis_triads" (orDefault (nestedRows (getOr rot "synthesisTriads" (asnList (list))))
                                              (list (strs (list "verification" "reversibility" "simplicity")) (strs (list "containment" "contract-precision" "resilience")) (strs (list "non-vacuity" "attention-density" "convergence")))))
                   (pair "dual_attractor_pairs" (orDefault (nestedRows (getOr rot "dualAttractorPairs" (asnList (list))))
                                                  (list (strs (list "verification" "reversibility")) (strs (list "containment" "simplicity")) (strs (list "verification" "containment")) (strs (list "reversibility" "convergence")) (strs (list "simplicity" "reversibility"))))))))

fn resolveConfig! root: String cands: (List String) -> (Option (Pair String String))
  (mt (listHead cands)
    ((none) (none))
    ((some cp)
      (let [full (if (stringStartsWith? cp "/") cp (pyJoin root cp))]
        (if (not (ok? (fileStat full)))
          (resolveConfig! root (rest cands))
          (mt (readTextFile! full)
            ((ok text) (some (pair full text)))
            ((err _) (resolveConfig! root (rest cands))))))))

fn expandHome home: String restPath: String -> String
  (let [r (str (rstripByte home 47) restPath)]
    (if (stringEmpty? r) "/" r))

fn firstErr rs: (List (Result AsnValue String)) -> (Result (List AsnValue) String)
  (fold (fn [acc r] (mt acc ((err e) (err e)) ((ok xs) (mt r ((err e) (err e)) ((ok v) (ok (listAppend xs (list v)))))))) (ok (list)) rs)

fn listRes r: (Result (List AsnValue) String) -> (Result AsnValue String)
  (mt r ((ok xs) (ok (asnList xs))) ((err e) (err e)))

fn dictRes r: (Result (List (Pair String AsnValue)) String) -> (Result AsnValue String)
  (mt r ((ok es) (ok (asnDict es))) ((err e) (err e)))

fn intRes v: AsnValue -> (Result AsnValue String)
  (mt (intOfValue v) ((ok i) (ok (asnInt i))) ((err e) (err e)))

fn loadMeshConfig! root: String home: String configPath: String envConfig: String stateDir: String pidFileEnv: String profile: String -> (Result (Pair AsnValue String) String)
  (let [cands (listAppend (listAppend (if (stringEmpty? configPath) (list) (list configPath)) (if (stringEmpty? envConfig) (list) (list envConfig)))
                (list (pyJoin root ".asl.config.asn") (pyJoin root "mesh.audit.aslconfig") (pyJoin root ".asl/mesh/mesh.audit.aslconfig")
                      (expandHome home "/.asl/config.asn") (expandHome home "/.asl/mesh.audit.aslconfig")))
        found (resolveConfig! root cands)
        resolved (mt found ((some p) (pairFirst p)) ((none) (pyJoin root ".asl.config.asn")))
        content (mt found ((some p) (pairSecond p)) ((none) ""))
        parsed (if (stringEmpty? content) (pair (asnDict (list)) "") (meshValue content resolved))]
    (mt (pairFirst parsed)
      ((asnDict m) (meshFromDict! root m resolved stateDir pidFileEnv profile (pairSecond parsed)))
      (bad (err (str "AttributeError: '" (typeName bad) "' object has no attribute 'get'")))))

fn meshFromDict! root: String m: (List (Pair String AsnValue)) resolved: String stateDir: String pidFileEnv: String profile: String stderr0: String -> (Result (Pair AsnValue String) String)
  (let [storage (subDict m "storage")
        daemon (subDict m "daemon")
        telemetry (subDict m "telemetry")
        profs (buildProfiles (dictItemsInOrder (getOr m "profiles" (asnList (list)))) (list) (none))
        profiles (pairFirst profs)
        poClean (lstripColon profile)
        overrideOk (and (not (stringEmpty? profile)) (some? (dictGet profiles poClean)))
        activeId (if overrideOk (some poClean) (pairSecond profs))
        warning (if (and (not (stringEmpty? profile)) (not overrideOk))
                  (str "[Warning] Requested profile '" profile "' not found in configuration. Available: " (pyStr (strs (mapKeysInOrder profiles))) "\n")
                  "")
        activeProfile (mt activeId ((some id) (mt (dictGet profiles id) ((some v) (optionOr (dictOf v) (list))) ((none) (list)))) ((none) (list)))
        roles (if (listEmpty? activeProfile) (list) (subDict activeProfile "roles"))
        shardsRaw (optionOr (listItems (getOr m "shards" (asnList (list)))) (list))
        shardsR (mt (buildShards (dictItemsInOrder (asnList shardsRaw)) roles (list))
                  ((ok xs) (ok (if (listEmpty? xs) (defaultShards) xs)))
                  ((err e) (err e)))
        peersR (mt (buildPeers (dictItemsInOrder (getOr m "peerRotation" (asnList (list)))) (list)) ((ok ps) (ok (if (listEmpty? ps) (defaultPeers) ps))) ((err e) (err e)))
        cascR (mt (buildCascades (dictItemsInOrder (getOr m "modelCascades" (asnList (list)))) (list)) ((ok cs) (ok (if (listEmpty? cs) (defaultCascades) cs))) ((err e) (err e)))
        pipeR (mt (buildPipeline (dictItemsInOrder (getOr m "staticPipeline" (asnList (list)))) (list)) ((ok xs) (ok (if (listEmpty? xs) (defaultPipeline) xs))) ((err e) (err e)))
        hooksR (buildHooks (dictItemsInOrder (getOr m "hooks" (asnList (list)))) (list))
        descriptors (map (fn [d] (asnDict (list (pair "schema" (getOr d "schema" (s ""))) (pair "package" (getOr d "package" (s "asl-mesh/descriptor"))) (pair "doc" (getOr d "doc" (s ""))))))
                      (dictItemsInOrder (getOr m "descriptors" (asnList (list)))))
        taxR (buildTaxonomy (dictItemsInOrder (getOr m "taxonomy" (asnList (list)))) (list))
        label0 (relPath! resolved root)
        label (if (= label0 ".asl.config.asn") ".asl.config.asn#mesh" label0)
        st (not (stringEmpty? stateDir))
        bbRel (if st (s (pyJoin stateDir "MeshDefectBlackboard.asn")) (getOr storage "blackboard" (s ".asl/mem/gaps/MeshDefectBlackboard.asn")))
        shardsRel (if st (s (pyJoin stateDir "shards")) (getOr storage "shardsDir" (s ".asl/mem/gaps/shards")))
        archiveRel (if st (s (pyJoin stateDir "archive")) (getOr storage "archiveDir" (s ".asl/mem/gaps/archive")))
        legacyRel (getOr storage "legacyLedger" (asnNone))
        queueRel (if st (s (pyJoin stateDir "queue.asn")) (getOr storage "queue" (s ".asl/mem/mesh/queue.asn")))
        telRel (if st (s (pyJoin stateDir "mesh_telemetry.asnl")) (getOr telemetry "logPath" (s ".asl/log/mesh_telemetry.asnl")))
        pidR (if (stringEmpty? pidFileEnv) (joinVal root (getOr daemon "pidFile" (s "tmp/asl-mesh.pid"))) (ok (s pidFileEnv)))
        keys (list "shards" "peer_rotation" "model_cascades" "static_pipeline" "hooks" "taxonomy"
                   "config_source" "blackboard_path" "shards_dir" "archive_dir" "legacy_ledger_path" "queue_path" "telemetry_log_path"
                   "interval_sec" "lease_ttl_sec" "stale_horizon_hours" "pid_file" "concurrency")
        vals (firstErr (list (listRes shardsR) (dictRes peersR) (dictRes cascR) (listRes pipeR) (dictRes hooksR) (listRes taxR)
                             (ok (s label)) (joinVal root bbRel) (joinVal root shardsRel) (joinVal root archiveRel)
                             (if (truthy? legacyRel) (joinVal root legacyRel) (ok (asnNone)))
                             (joinVal root queueRel) (joinVal root telRel)
                             (intRes (getOr daemon "intervalSec" (asnInt 300))) (intRes (getOr daemon "leaseTtlSec" (asnInt 120)))
                             (intRes (getOr daemon "staleHorizonHours" (asnInt 24))) pidR (intRes (getOr m "concurrency" (asnInt 2)))))]
    (mt vals
      ((err e) (err e))
      ((ok vs)
        (let [fixed (zip keys vs)
              extra (list (pair "rotation" (buildRotation (subDict m "rotation"))) (pair "descriptors" (asnList descriptors))
                          (pair "safety" (asnDict (subDict m "safety"))) (pair "profiles" (asnDict profiles)) (pair "active_profile" (asnDict activeProfile)))]
          (ok (pair (asnDict (listAppend fixed extra)) (str stderr0 warning)))))))

fn mapKeysInOrder es: (List (Pair String AsnValue)) -> (List String)
  (map pairFirst es)

fn loadMeshConfigEnv! root: String configPath: String profile: String -> (Result AsnValue String)
  (let [env (fn [k] (optionOr (envGet k) ""))]
    (mt (loadMeshConfig! root (env "HOME") configPath (env "ASL_MESH_CONFIG") (env "ASL_MESH_STATE_DIR") (env "ASL_MESH_PID_FILE") profile)
      ((err e) (err e))
      ((ok r)
        (do
          (if (stringEmpty? (pairSecond r)) () (eprintln (rstripByte (pairSecond r) 10)))
          (ok (pairFirst r))))))
