(module aslGateway/cockpit
  :x [AsnVal asnAtom asnText asnList CockpitEnv GatewayStatus ProfileHealth PoolStats UsageRow UsageSnapshot CockpitState
      KnownRed KnownRedRow GatesRecord CalibrationRow Calibration TaskRow TasksData MemData IntelCache
      noSource htmlEscape pyStrRepr pyRepr pyStr asnScalarText asnReadText asnProps utf8IssueText translateNewlines
      readTextPy! cockpitReadForm! cockpitKnownRed! cockpitGates! cockpitCalibration! calibrationIndexPath
      cockpitCell cockpitTable cockpitTile cockpitMissing cockpitUsageRows cockpitHtml!
      getTasksData! tasksJson getMemData! memJson getDaemonsData emptyIntelCache
      getIntelCouplingData! getVitalityData! getStubsData! envRootDir pyJoin cockpitEnvFromProcess!
      CockpitResponse CockpitCaches CockpitDispatchResult emptyCockpitCaches pyJsonDump
      observatoryBlastRadius observatory_blast_radius
      serveCockpitDashboard! serve_cockpit_dashboard!
      serveCockpitObservatoryApi! serve_cockpit_observatory_api!
      serveCockpitIntelApi! serve_cockpit_intel_api!
      serveCockpitVitalityApi! serve_cockpit_vitality_api!
      serveCockpitStubsApi! serve_cockpit_stubs_api!
      serveCockpitDaemonsApi serve_cockpit_daemons_api
      serveCockpitTasksApi! serve_cockpit_tasks_api!
      serveCockpitMemApi! serve_cockpit_mem_api!
      cockpitDispatchGet! cockpit_dispatch_get!]
  :i [(localTime :a lt)
      (pyText :a pt)
      (asl-json/json :a j)
      (asl-proc/coreProcess :a cp)])

(enum AsnVal
  (:c asnAtom [(s String)])
  (:c asnText [(s String)])
  (:c asnList [(items (List AsnVal))]))

(schema CockpitEnv
  (:f rootEnv (Option String))
  (:f cwd String)
  (:f calibrationEnv (Option String))
  (:f zone lt/Zone)
  (:f platform String))

(schema GatewayStatus
  (:f pid Int64)
  (:f version String)
  (:f diskVersion String)
  (:f stale Bool)
  (:f inFlight Int64)
  (:f draining Bool)
  (:f updates Int64))

(schema ProfileHealth
  (:f name (Option String))
  (:f error (Option String)))

(schema PoolStats
  (:f name String)
  (:f size Int64)
  (:f busy Int64)
  (:f queued Int64))

(schema UsageRow
  (:f name String)
  (:f requests (Option Int64))
  (:f okCount (Option Int64))
  (:f errors (List (Pair String Int64)))
  (:f fallbacks (Option Int64))
  (:f inputTokens (Option Int64))
  (:f cachedTokens (Option Int64))
  (:f outputTokens (Option Int64)))

(schema UsageSnapshot
  (:f since Float64)
  (:f providers (List UsageRow))
  (:f aliases (List UsageRow)))

(schema CockpitState
  (:f port Int64)
  (:f status GatewayStatus)
  (:f profile ProfileHealth)
  (:f pools (List PoolStats))
  (:f usage UsageSnapshot)
  (:f now Float64))

(schema KnownRedRow
  (:f suite String)
  (:f cause String))

(schema KnownRed
  (:f count Int64)
  (:f date (Option String))
  (:f capturedFrom (Option String))
  (:f confirmation (Option String))
  (:f rows (List KnownRedRow)))

(schema GatesRecord
  (:f count Int64)
  (:f latest String)
  (:f mtime String))

(schema CalibrationRow
  (:f id String)
  (:f status String)
  (:f date String))

(schema Calibration
  (:f updated String)
  (:f rows (List CalibrationRow)))

(schema TaskRow
  (:f id String)
  (:f filename String)
  (:f status String)
  (:f mtime String))

(schema TasksData
  (:f totalTasks Int64)
  (:f recentTasks (List TaskRow)))

(schema MemData
  (:f decisionsCount (Option Int64))
  (:f tasksCount (Option Int64))
  (:f receiptsCount (Option Int64))
  (:f notesSizeBytes (Option Int64))
  (:f recentAdrs (List String)))

(schema IntelCache
  (:f timestamp Float64)
  (:f data (Option j/Json)))

(schema CockpitResponse
  (:f status Int64)
  (:f headers (List (Pair String String)))
  (:f body String))

(schema CockpitCaches
  (:f intel IntelCache)
  (:f vitality IntelCache)
  (:f stubs IntelCache))

(schema CockpitDispatchResult
  (:f caches CockpitCaches)
  (:f response (Result CockpitResponse String)))

(schema Utf8Issue
  (:f start Int64)
  (:f end Int64)
  (:f reason String))

fn noSource -> String
  "<span class=\"none\" title=\"no source\">\u{2014}</span>"

fn sliceOr s: String i: Int64 k: Int64 -> String
  (optionOr (stringSlice s i k) "")

fn hexDigits n: Int64 width: Int64 acc: String -> String
  (if (<= width 0)
    acc
    (hexDigits (/ n 16) (- width 1) (str (sliceOr "0123456789abcdef" (mod n 16) (+ (mod n 16) 1)) acc)))

fn hex2 n: Int64 -> String
  (hexDigits n 2 "")

fn htmlEscapeScan s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse (cons (sliceOr s start n) acc)) "")
    (let [(b (bytesGet bs i))
          (rep (cond ((= b 38) "&amp;") ((= b 60) "&lt;") ((= b 62) "&gt;") ((= b 34) "&quot;") ((= b 39) "&#x27;") (else "")))]
      (if (stringEmpty? rep)
        (htmlEscapeScan s bs n (+ i 1) start acc)
        (htmlEscapeScan s bs n (+ i 1) (+ i 1) (cons rep (cons (sliceOr s start i) acc))))))

fn htmlEscape s: String -> String
  (let [(bs (stringToBytes s))]
    (htmlEscapeScan s bs (bytesLength bs) 0 0 (list)))

fn utf8SeqLen b: Int64 -> Int64
  (cond ((< b 128) 1) ((< b 194) 0) ((< b 224) 2) ((< b 240) 3) ((< b 245) 4) (else 0))

fn utf8ContOk? first: Int64 k: Int64 b: Int64 -> Bool
  (if (= k 1)
    (cond ((= first 224) (and (>= b 160) (<= b 191)))
          ((= first 237) (and (>= b 128) (<= b 159)))
          ((= first 240) (and (>= b 144) (<= b 191)))
          ((= first 244) (and (>= b 128) (<= b 143)))
          (else (and (>= b 128) (<= b 191))))
    (and (>= b 128) (<= b 191)))

fn utf8ContCheck bs: Bytes n: Int64 i: Int64 len: Int64 k: Int64 -> (Result Int64 Utf8Issue)
  (cond
    ((>= k len) (ok (+ i len)))
    ((>= (+ i k) n) (err (Utf8Issue :start i :end n :reason "unexpected end of data")))
    ((not (utf8ContOk? (bytesGet bs i) k (bytesGet bs (+ i k)))) (err (Utf8Issue :start i :end (+ i k) :reason "invalid continuation byte")))
    (else (utf8ContCheck bs n i len (+ k 1))))

fn utf8Step bs: Bytes n: Int64 i: Int64 -> (Result Int64 Utf8Issue)
  (let [(len (utf8SeqLen (bytesGet bs i)))]
    (if (= len 0)
      (err (Utf8Issue :start i :end (+ i 1) :reason "invalid start byte"))
      (utf8ContCheck bs n i len 1)))

fn utf8FirstIssue bs: Bytes n: Int64 i: Int64 -> (Option Utf8Issue)
  (cond
    ((>= i n) (none))
    ((< (bytesGet bs i) 128) (utf8FirstIssue bs n (+ i 1)))
    (else (mt (utf8Step bs n i) ((ok k) (utf8FirstIssue bs n k)) ((err issue) (some issue)))))

fn utf8IssueText bs: Bytes issue: Utf8Issue -> String
  (if (= (- issue.end issue.start) 1)
    (str "'utf-8' codec can't decode byte 0x" (hex2 (bytesGet bs issue.start)) " in position " (stringFromInt64 issue.start) ": " issue.reason)
    (str "'utf-8' codec can't decode bytes in position " (stringFromInt64 issue.start) "-" (stringFromInt64 (- issue.end 1)) ": " issue.reason))

fn utf8ReplaceScan s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (stringJoin (listReverse (cons (sliceOr s start n) acc)) ""))
    ((< (bytesGet bs i) 128) (utf8ReplaceScan s bs n (+ i 1) start acc))
    (else
      (mt (utf8Step bs n i)
        ((ok k) (utf8ReplaceScan s bs n k start acc))
        ((err issue) (utf8ReplaceScan s bs n issue.end issue.end (cons "\u{FFFD}" (cons (sliceOr s start i) acc)))))))

fn utf8Replace s: String -> String
  (let [(bs (stringToBytes s))]
    (utf8ReplaceScan s bs (bytesLength bs) 0 0 (list)))

fn translateNewlines s: String -> String
  (if (stringContains? s "\r")
    (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n")
    s)

fn charIndex bs: Bytes i: Int64 k: Int64 acc: Int64 -> Int64
  (if (>= k i)
    acc
    (charIndex bs i (+ k 1) (if (= (& (bytesGet bs k) 192) 128) acc (+ acc 1))))

fn charPrefixEnd bs: Bytes n: Int64 i: Int64 chars: Int64 limit: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (& (bytesGet bs i) 192) 128) (charPrefixEnd bs n (+ i 1) chars limit))
    ((>= chars limit) i)
    (else (charPrefixEnd bs n (+ i 1) (+ chars 1) limit)))

fn codePointAt bs: Bytes i: Int64 len: Int64 -> Int64
  (cond
    ((= len 2) (+ (* (mod (bytesGet bs i) 32) 64) (mod (bytesGet bs (+ i 1)) 64)))
    ((= len 3) (+ (* (mod (bytesGet bs i) 16) 4096) (* (mod (bytesGet bs (+ i 1)) 64) 64) (mod (bytesGet bs (+ i 2)) 64)))
    (else (+ (* (mod (bytesGet bs i) 8) 262144) (* (mod (bytesGet bs (+ i 1)) 64) 4096) (* (mod (bytesGet bs (+ i 2)) 64) 64) (mod (bytesGet bs (+ i 3)) 64))))

fn between? x: Int64 lo: Int64 hi: Int64 -> Bool
  (and (>= x lo) (<= x hi))

fn nonPrintable? cp: Int64 -> Bool
  (or (between? cp 128 160) (= cp 173) (between? cp 1536 1541) (= cp 1564) (= cp 1757) (= cp 1807) (between? cp 2192 2193) (= cp 2274)
      (= cp 5760) (= cp 6158) (between? cp 8192 8207) (between? cp 8232 8239) (between? cp 8287 8292) (between? cp 8294 8303) (= cp 12288)
      (between? cp 55296 63743) (= cp 65279) (between? cp 65529 65531) (between? cp 65534 65535) (= cp 69821) (= cp 69837) (between? cp 78896 78911)
      (between? cp 113824 113827) (between? cp 119155 119162) (= cp 917505) (between? cp 917536 917631) (>= cp 983040))

fn cpEscape cp: Int64 -> String
  (cond ((< cp 256) (str "\\x" (hex2 cp)))
        ((< cp 65536) (str "\\u" (hexDigits cp 4 "")))
        (else (str "\\U" (hexDigits cp 8 ""))))

fn reprScan s: String bs: Bytes n: Int64 i: Int64 start: Int64 q: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse (cons (sliceOr s start n) acc)) "")
    (let [(b (bytesGet bs i))]
      (if (< b 128)
        (let [(rep (cond ((= b 92) "\\\\") ((= b q) (if (= q 39) "\\'" "\\\"")) ((= b 9) "\\t") ((= b 10) "\\n") ((= b 13) "\\r")
                         ((or (< b 32) (= b 127)) (str "\\x" (hex2 b))) (else "")))]
          (if (stringEmpty? rep)
            (reprScan s bs n (+ i 1) start q acc)
            (reprScan s bs n (+ i 1) (+ i 1) q (cons rep (cons (sliceOr s start i) acc)))))
        (mt (utf8Step bs n i)
          ((err _) (reprScan s bs n (+ i 1) (+ i 1) q (cons (str "\\udc" (hex2 b)) (cons (sliceOr s start i) acc))))
          ((ok k)
            (let [(cp (codePointAt bs i (- k i)))]
              (if (nonPrintable? cp)
                (reprScan s bs n k k q (cons (cpEscape cp) (cons (sliceOr s start i) acc)))
                (reprScan s bs n k start q acc))))))))

fn pyStrRepr s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) 34 39))
        (bs (stringToBytes s))
        (quote (if (= q 34) "\"" "'"))]
    (str quote (reprScan s bs (bytesLength bs) 0 0 q (list)) quote))

fn pyRepr v: AsnVal -> String
  (mt v
    ((asnAtom s) (pyStrRepr s))
    ((asnText s) (pyStrRepr s))
    ((asnList items) (str "[" (stringJoin (map pyRepr items) ", ") "]")))

fn pyStr v: AsnVal -> String
  (mt v
    ((asnAtom s) s)
    ((asnText s) s)
    ((asnList _) (pyRepr v)))

fn digitsFrom? bs: Bytes i: Int64 n: Int64 -> Bool
  (cond ((>= i n) true)
        ((between? (bytesGet bs i) 48 57) (digitsFrom? bs (+ i 1) n))
        (else false))

fn digitRunEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (between? (bytesGet bs i) 48 57)) (digitRunEnd bs (+ i 1) n) i)

fn intText? s: String -> Bool
  (let [(bs (stringToBytes s)) (n (bytesLength bs)) (at (if (and (> n 0) (= (bytesGet bs 0) 45)) 1 0))]
    (and (< at n) (digitsFrom? bs at n)))

fn floatText? s: String -> Bool
  (let [(bs (stringToBytes s)) (n (bytesLength bs)) (at (if (and (> n 0) (= (bytesGet bs 0) 45)) 1 0)) (dot (digitRunEnd bs at n))]
    (and (> dot at) (< (+ dot 1) n) (= (bytesGet bs dot) 46) (digitsFrom? bs (+ dot 1) n)))

fn stripZeros s: String i: Int64 -> String
  (if (and (< (+ i 1) (stringLength s)) (= (sliceOr s i (+ i 1)) "0")) (stripZeros s (+ i 1)) (sliceOr s i (stringLength s)))

fn normInt s: String -> String
  (let [(neg (stringStartsWith? s "-"))
        (digits (stripZeros s (if neg 1 0)))]
    (if (and neg (not (= digits "0"))) (str "-" digits) digits))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (sliceOr s 1 (stringLength s))) s)

fn asnScalarText v: AsnVal -> String
  (mt v
    ((asnAtom s)
      (cond ((= s "true") "True")
            ((= s "false") "False")
            ((intText? s) (normInt s))
            ((floatText? s) (stringFromFloat64 (optionOr (stringToFloat64 s) 0.0)))
            (else (lstripColons s))))
    ((asnText s) s)
    ((asnList _) (pyRepr v)))

fn headIs? v: AsnVal head: String -> Bool
  (mt v
    ((asnAtom s) (= s head))
    ((asnText s) (= s head))
    ((asnList _) false))

fn listItems v: AsnVal -> (List AsnVal)
  (mt v ((asnList items) items) (_ (list)))

fn isList? v: AsnVal -> Bool
  (mt v ((asnList _) true) (_ false))

fn pushVal stack: (List (List AsnVal)) forms: (List AsnVal) v: AsnVal -> (Pair (List (List AsnVal)) (List AsnVal))
  (if (listEmpty? stack)
    (pair stack (cons v forms))
    (pair (cons (cons v (preludeHead stack)) (preludeTail stack)) forms))

fn asnDelim? b: Int64 -> Bool
  (or (= b 32) (= b 9) (= b 13) (= b 10) (= b 40) (= b 41) (= b 34) (= b 59))

fn atomEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (not (asnDelim? (bytesGet bs i)))) (atomEnd bs (+ i 1) n) i)

fn lineEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet bs i) 10) (+ i 1)) (else (lineEnd bs (+ i 1) n)))

fn escapeText b: Int64 -> String
  (cond ((= b 92) "\\") ((= b 34) "\"") ((= b 110) "\n") ((= b 116) "\t") (else ""))

fn asnHexValue b: Int64 -> Int64
  (cond ((and (>= b 48) (<= b 57)) (- b 48))
        ((and (>= b 65) (<= b 70)) (+ (- b 65) 10))
        ((and (>= b 97) (<= b 102)) (+ (- b 97) 10))
        (else -1))

fn asnHexRun bs: Bytes i: Int64 end: Int64 value: Int64 -> (Option Int64)
  (if (= i end) (some value)
    (let [(digit (asnHexValue (bytesGet bs i)))]
      (if (< digit 0) (none) (asnHexRun bs (+ i 1) end (+ (* value 16) digit)))))

fn asnFindByte bs: Bytes n: Int64 i: Int64 target: Int64 -> (Option Int64)
  (if (>= i n) (none)
    (if (= (bytesGet bs i) target) (some i) (asnFindByte bs n (+ i 1) target)))

fn asnUnicodeEscape bs: Bytes n: Int64 slash: Int64 -> (Result (Pair String Int64) String)
  (if (>= (+ slash 2) n) (err "ERR_ASN_BAD_UNICODE_ESCAPE")
    (let [(braced (= (bytesGet bs (+ slash 2)) 123))
          (start (if braced (+ slash 3) (+ slash 2)))
          (endOpt (if braced (asnFindByte bs n start 125) (some (+ start 4))))]
      (mt endOpt
        ((none) (err "ERR_ASN_BAD_UNICODE_ESCAPE"))
        ((some end)
          (let [(count (- end start))
                (next (if braced (+ end 1) end))]
            (if (or (if braced (or (< count 1) (> count 6)) (!= count 4)) (> end n))
              (err "ERR_ASN_BAD_UNICODE_ESCAPE")
              (mt (asnHexRun bs start end 0)
                ((none) (err "ERR_ASN_BAD_UNICODE_ESCAPE"))
                ((some cp)
                  (if (or (> cp 1114111) (and (>= cp 55296) (<= cp 57343)))
                    (err "ERR_ASN_BAD_UNICODE_ESCAPE")
                    (ok (pair (pt/cpEncode cp) next)))))))))))

fn asnEscapeScan bs: Bytes n: Int64 slash: Int64 -> (Result (Pair String Int64) String)
  (if (>= (+ slash 1) n) (err "ERR_ASN_BAD_ESCAPE")
    (if (= (bytesGet bs (+ slash 1)) 117)
      (asnUnicodeEscape bs n slash)
      (let [(decoded (escapeText (bytesGet bs (+ slash 1))))]
        (if (stringEmpty? decoded) (err "ERR_ASN_BAD_ESCAPE") (ok (pair decoded (+ slash 2)))))))

fn asnStringScan s: String bs: Bytes n: Int64 open: Int64 j: Int64 start: Int64 acc: (List String) -> (Result (Pair String Int64) String)
  (if (>= j n)
    (err (str "unterminated string at offset " (stringFromInt64 (charIndex bs open 0 0))))
    (let [(b (bytesGet bs j))]
      (cond
        ((= b 34) (ok (pair (stringJoin (listReverse (cons (sliceOr s start j) acc)) "") (+ j 1))))
        ((= b 92)
          (mt (asnEscapeScan bs n j)
            ((err _) (err (str "bad string escape at offset " (stringFromInt64 (charIndex bs j 0 0)))))
            ((ok decoded) (asnStringScan s bs n open (pairSecond decoded) (pairSecond decoded) (cons (pairFirst decoded) (cons (sliceOr s start j) acc))))))
        (else (asnStringScan s bs n open (+ j 1) start acc)))))

fn asnReadScan s: String bs: Bytes n: Int64 i: Int64 stack: (List (List AsnVal)) forms: (List AsnVal) -> (Result (List AsnVal) String)
  (if (>= i n)
    (if (listEmpty? stack)
      (ok (listReverse forms))
      (err (str (stringFromInt64 (listLength stack)) " unclosed ( at end of text")))
    (let [(c (bytesGet bs i))]
      (cond
        ((or (= c 32) (= c 9) (= c 13) (= c 10)) (asnReadScan s bs n (+ i 1) stack forms))
        ((= c 59) (asnReadScan s bs n (lineEnd bs i n) stack forms))
        ((= c 40) (asnReadScan s bs n (+ i 1) (cons (list) stack) forms))
        ((= c 41)
          (if (listEmpty? stack)
            (err (str "unbalanced ) at offset " (stringFromInt64 (charIndex bs i 0 0))))
            (let [(p (pushVal (preludeTail stack) forms (asnList (listReverse (preludeHead stack)))))]
              (asnReadScan s bs n (+ i 1) (pairFirst p) (pairSecond p)))))
        ((= c 34)
          (mt (asnStringScan s bs n i (+ i 1) (+ i 1) (list))
            ((err e) (err e))
            ((ok sp)
              (let [(p (pushVal stack forms (asnText (pairFirst sp))))]
                (asnReadScan s bs n (pairSecond sp) (pairFirst p) (pairSecond p))))))
        (else
          (let [(k (atomEnd bs i n))
                (p (pushVal stack forms (asnAtom (sliceOr s i k))))]
            (asnReadScan s bs n k (pairFirst p) (pairSecond p)))))))

fn asnReadText s: String -> (Result (List AsnVal) String)
  (let [(bs (stringToBytes s))]
    (asnReadScan s bs (bytesLength bs) 0 (list) (list)))

fn keywordName? k: AsnVal -> Bool
  (mt k
    ((asnAtom s) (and (stringStartsWith? s ":") (>= (stringLength s) 2)))
    (_ false))

fn firstCharDropped s: String -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (if (= n 0) "" (sliceOr s (charPrefixEnd bs n 0 0 1) n)))

fn propsPairs items: (List AsnVal) what: String acc: (List (Pair String AsnVal)) -> (Result (List (Pair String AsnVal)) String)
  (if (listEmpty? items)
    (ok acc)
    (let [(k (preludeHead items)) (rest (preludeTail items))]
      (if (not (keywordName? k))
        (err (str what ": " (pyRepr k) " is not a :keyword"))
        (propsPairs (preludeTail rest) what (cons (pair (firstCharDropped (pyStr k)) (preludeHead rest)) acc)))))

fn asnProps form: AsnVal head: (Option String) -> (Result (List (Pair String AsnVal)) String)
  (let [(what (mt head ((some h) (str "(" h " ...)")) ((none) "a property list")))]
    (mt form
      ((asnList items)
        (let [(headBad (mt head
                         ((none) false)
                         ((some h) (or (listEmpty? items) (mt (preludeHead items) ((asnAtom s) (not (= s h))) (_ true))))))]
          (if headBad
            (err (str "expected " what ", found (" (if (listEmpty? items) "" (pyStr (preludeHead items))) " ...)"))
            (let [(rest (if (some? head) (preludeTail items) items))]
              (if (= (mod (listLength rest) 2) 1)
                (err (str what " has an odd number of items"))
                (propsPairs rest what (list)))))))
      (_ (err (str "expected " what ", found " (pyRepr form))))))

fn propGet props: (List (Pair String AsnVal)) key: String -> (Option AsnVal)
  (if (listEmpty? props)
    (none)
    (if (= (pairFirst (preludeHead props)) key) (some (pairSecond (preludeHead props))) (propGet (preludeTail props) key)))

fn propText props: (List (Pair String AsnVal)) key: String -> String
  (mt (propGet props key) ((some v) (asnScalarText v)) ((none) ""))

fn pyJoin a: String b: String -> String
  (cond ((stringStartsWith? b "/") b)
        ((stringEmpty? a) b)
        ((stringEndsWith? a "/") (str a b))
        (else (str a "/" b)))

fn envRootDir env: CockpitEnv -> String
  (mt env.rootEnv
    ((some r) (if (stringEmpty? r) env.cwd r))
    ((none) env.cwd))

fn resolveAt env: CockpitEnv p: String -> String
  (pyJoin env.cwd p)

fn afterPrefix s: String prefix: String -> (Option String)
  (if (stringStartsWith? s prefix) (some (sliceOr s (stringLength prefix) (stringLength s))) (none))

fn errnoOf reason: String platform: String -> (Option Int64)
  (cond ((= reason "No such file or directory") (some 2))
        ((= reason "Permission denied") (some 13))
        ((= reason "Not a directory") (some 20))
        ((= reason "Is a directory") (some 21))
        ((= reason "Too many levels of symbolic links") (some (if (= platform "Darwin") 62 40)))
        ((= reason "File name too long") (some (if (= platform "Darwin") 63 36)))
        (else (none)))

fn osErrorText env: CockpitEnv shown: String used: String hostMsg: String -> (Result String String)
  (let [(afterKind (mt (stringIndexOf hostMsg ": ") ((some k) (sliceOr hostMsg (+ k 2) (stringLength hostMsg))) ((none) "")))
        (reason (afterPrefix afterKind (str used ": ")))]
    (mt reason
      ((none) (err (str "cockpit: unrecognised host error for " shown ": " hostMsg)))
      ((some r)
        (mt (errnoOf r env.platform)
          ((some n) (ok (str "[Errno " (stringFromInt64 n) "] " r ": " (pyStrRepr shown))))
          ((none) (err (str "cockpit: no errno mapping for " shown ": " hostMsg)))))))

fn readTextPy! env: CockpitEnv path: String -> (Result (Result String String) String)
  (let [(used (resolveAt env path))]
    (mt (fileStat used)
      ((err e) (mt (osErrorText env path used e) ((ok t) (ok (err t))) ((err h) (err h))))
      ((ok st)
        (if st.isDir
          (ok (err (str "[Errno 21] Is a directory: " (pyStrRepr path))))
          (mt (fileReadString used)
            ((err e) (mt (osErrorText env path used e) ((ok t) (ok (err t))) ((err h) (err h))))
            ((ok raw)
              (let [(bs (stringToBytes raw))]
                (mt (utf8FirstIssue bs (bytesLength bs) 0)
                  ((some issue) (ok (err (utf8IssueText bs issue))))
                  ((none) (ok (ok (translateNewlines raw))))))))))))

fn findForm forms: (List AsnVal) head: String -> (Option AsnVal)
  (if (listEmpty? forms)
    (none)
    (let [(f (preludeHead forms))]
      (mt f
        ((asnList items) (if (and (not (listEmpty? items)) (headIs? (preludeHead items) head)) (some f) (findForm (preludeTail forms) head)))
        (_ (findForm (preludeTail forms) head)))))

fn cockpitReadForm! env: CockpitEnv path: String head: String -> (Result (Result AsnVal String) String)
  (mt (readTextPy! env path)
    ((err h) (err h))
    ((ok r)
      (mt r
        ((err e) (ok (err (str path ": " e))))
        ((ok text)
          (mt (asnReadText text)
            ((err e) (ok (err (str path ": " e))))
            ((ok forms)
              (mt (findForm forms head)
                ((some f) (ok (ok f)))
                ((none) (ok (err (str path ": no (" head " ...) form")))))))))))

fn scalarPropsFrom vals: (List AsnVal) acc: (List (Pair String String)) -> (List (Pair String String))
  (if (or (listEmpty? vals) (listEmpty? (preludeTail vals)))
    acc
    (scalarPropsFrom (preludeTail (preludeTail vals))
                     (cons (pair (firstCharDropped (pyStr (preludeHead vals))) (asnScalarText (preludeHead (preludeTail vals)))) acc)))

fn pairGet props: (List (Pair String String)) key: String -> (Option String)
  (if (listEmpty? props)
    (none)
    (if (= (pairFirst (preludeHead props)) key) (some (pairSecond (preludeHead props))) (pairGet (preludeTail props) key)))

fn knownRedRow s: AsnVal -> KnownRedRow
  (let [(items (listItems s))
        (props (mt (asnProps (asnList (listDrop items 2)) (none)) ((ok p) p) ((err _) (list))))]
    (KnownRedRow :suite (if (> (listLength items) 1) (pyStr (preludeHead (preludeTail items))) "")
                 :cause (propText props "cause")))

fn suiteForm? x: AsnVal -> Bool
  (and (isList? x) (not (listEmpty? (listItems x))) (headIs? (preludeHead (listItems x)) ":suite"))

fn cockpitKnownRed! env: CockpitEnv -> (Result (Result KnownRed String) String)
  (let [(path (pyJoin (envRootDir env) ".asl/mem/knownRed.asn"))]
    (mt (cockpitReadForm! env path ":knownRed")
      ((err h) (err h))
      ((ok r)
        (mt r
          ((err e) (ok (err e)))
          ((ok form)
            (let [(items (listItems form))
                  (suites (filter suiteForm? items))
                  (headVals (filter (fn [(x AsnVal)] -> Bool (not (isList? x))) (preludeTail items)))
                  (props (scalarPropsFrom headVals (list)))]
              (ok (ok (KnownRed :count (listLength suites) :date (pairGet props "date") :capturedFrom (pairGet props "capturedFrom")
                                :confirmation (pairGet props "confirmation") :rows (map knownRedRow suites))))))))))

fn mtimeFloat st: FileStat -> Float64
  (let [(sec st.mtime)
        (nsec (- st.mtimeNs (* sec 1000000000)))]
    (+ (int64ToFloat64 sec) (* (int64ToFloat64 nsec) 0.000000001)))

fn maxByMtime stats: (List (Pair String Float64)) best: (Pair String Float64) -> (Pair String Float64)
  (if (listEmpty? stats)
    best
    (let [(p (preludeHead stats))]
      (maxByMtime (preludeTail stats) (if (> (pairSecond p) (pairSecond best)) p best))))

fn statMtimes! env: CockpitEnv dir: String names: (List String) acc: (List (Pair String Float64)) -> (Result (List (Pair String Float64)) String)
  (if (listEmpty? names)
    (ok (listReverse acc))
    (let [(name (preludeHead names))]
      (mt (fileStat (resolveAt env (pyJoin dir name)))
        ((err e) (err e))
        ((ok st) (statMtimes! env dir (preludeTail names) (cons (pair name (mtimeFloat st)) acc))))))

fn asnName? name: String -> Bool
  (stringEndsWith? name ".asn")

fn cockpitGates! env: CockpitEnv -> (Result (Result GatesRecord String) String)
  (let [(d (pyJoin (envRootDir env) ".asl/mem/benchmarks/fullGreen"))]
    (mt (dirList (resolveAt env d))
      ((err _) (ok (err (str "no fullGreen record directory " d))))
      ((ok names)
        (let [(files (filter asnName? names))]
          (if (listEmpty? files)
            (ok (err (str "no fullGreen record in " d)))
            (mt (statMtimes! env d files (list))
              ((err e) (err e))
              ((ok stats)
                (let [(best (maxByMtime (preludeTail stats) (preludeHead stats)))]
                  (ok (ok (GatesRecord :count (listLength files) :latest (pairFirst best)
                                       :mtime (lt/formatLocal env.zone (lt/floorSeconds (pairSecond best)) false))))))))))))

fn calibrationIndexPath env: CockpitEnv -> String
  (mt env.calibrationEnv
    ((some p) (if (stringEmpty? p) (pyJoin (envRootDir env) ".asl/mem/calibration/index.asn") p))
    ((none) (pyJoin (envRootDir env) ".asl/mem/calibration/index.asn")))

fn calibrationRows models: (List AsnVal) acc: (List CalibrationRow) -> (List CalibrationRow)
  (if (listEmpty? models)
    (listReverse acc)
    (mt (asnProps (preludeHead models) (some ":model"))
      ((err _) (calibrationRows (preludeTail models) acc))
      ((ok mp) (calibrationRows (preludeTail models) (cons (CalibrationRow :id (propText mp "id") :status (propText mp "status") :date (propText mp "date")) acc)))))

fn cockpitCalibration! env: CockpitEnv -> (Result (Result Calibration String) String)
  (let [(path (calibrationIndexPath env))]
    (mt (cockpitReadForm! env path ":calibrationIndex")
      ((err h) (err h))
      ((ok r)
        (mt r
          ((err e) (ok (err e)))
          ((ok form)
            (mt (asnProps form (some ":calibrationIndex"))
              ((err e) (ok (err (str path ": " e))))
              ((ok props)
                (let [(models (mt (propGet props "models") ((some m) (listItems m)) ((none) (list))))]
                  (ok (ok (Calibration :updated (propText props "updated") :rows (calibrationRows models (list)))))))))))))

fn cockpitCell v: (Option String) -> String
  (mt v
    ((none) (noSource))
    ((some s) (if (stringEmpty? s) (noSource) (htmlEscape s))))

fn cockpitTable cols: (List String) rows: (List (List (Option String))) -> String
  (let [(head (stringJoin (map (fn [(c String)] -> String (str "<th>" (htmlEscape c) "</th>")) cols) ""))
        (body (stringJoin (map (fn [(r (List (Option String)))] -> String
                                 (str "<tr>" (stringJoin (map (fn [(v (Option String))] -> String (str "<td>" (cockpitCell v) "</td>")) r) "") "</tr>"))
                               rows) ""))]
    (str "<table><thead><tr>" head "</tr></thead><tbody>" body "</tbody></table>"))

fn cockpitTile title: String body: String source: String -> String
  (str "<section class=\"tile\"><h2>" (htmlEscape title) "</h2><div class=\"src\">source: " (htmlEscape source) "</div>" body "</section>")

fn cockpitMissing e: String -> String
  (str "<p class=\"none\" title=\"no source\">\u{2014} " (htmlEscape e) "</p>")

fn intCell n: Int64 -> (Option String)
  (some (stringFromInt64 n))

fn optIntCell n: (Option Int64) -> (Option String)
  (mt n ((some v) (some (stringFromInt64 v))) ((none) (none)))

fn zeroCell n: (Option Int64) -> (Option String)
  (some (stringFromInt64 (optionOr n 0)))

fn boolText b: Bool -> String
  (if b "True" "False")

fn cockpitUsageRows rows: (List UsageRow) -> (List (List (Option String)))
  (map (fn [(r UsageRow)] -> (List (Option String))
         (let [(errs (stringJoin (map (fn [(p (Pair String Int64))] -> String (str (pairFirst p) ":" (stringFromInt64 (pairSecond p))))
                                      (listSortBy (fn [(p (Pair String Int64))] -> String (pairFirst p)) r.errors)) " "))]
           (list (some r.name) (zeroCell r.requests) (zeroCell r.okCount) (some (if (stringEmpty? errs) "0" errs)) (zeroCell r.fallbacks)
                 (zeroCell r.inputTokens) (zeroCell r.cachedTokens) (zeroCell r.outputTokens))))
       (listSortBy (fn [(r UsageRow)] -> String r.name) rows))

fn wsLen bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    0
    (let [(b (bytesGet bs i))
          (b1 (if (< (+ i 1) n) (bytesGet bs (+ i 1)) -1))
          (b2 (if (< (+ i 2) n) (bytesGet bs (+ i 2)) -1))]
      (cond
        ((or (= b 32) (between? b 9 13) (between? b 28 31)) 1)
        ((and (= b 194) (or (= b1 133) (= b1 160))) 2)
        ((and (= b 225) (= b1 154) (= b2 128)) 3)
        ((and (= b 226) (= b1 128) (or (between? b2 128 138) (= b2 168) (= b2 169) (= b2 175))) 3)
        ((and (= b 226) (= b1 129) (= b2 159)) 3)
        ((and (= b 227) (= b1 128) (= b2 128)) 3)
        (else 0))))

fn wsRunEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(k (wsLen bs i n))]
    (if (= k 0) i (wsRunEnd bs (+ i k) n)))

fn letter? b: Int64 -> Bool
  (or (between? b 65 90) (between? b 97 122))

fn letterRunEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (letter? (bytesGet bs i))) (letterRunEnd bs (+ i 1) n) i)

fn byteIs? bs: Bytes i: Int64 n: Int64 b: Int64 -> Bool
  (and (< i n) (= (bytesGet bs i) b))

fn lettersAt s: String bs: Bytes i: Int64 n: Int64 -> (Option String)
  (let [(k (letterRunEnd bs i n))]
    (if (> k i) (some (sliceOr s i k)) (none)))

fn firstSome opts: (List (Option String)) -> (Option String)
  (if (listEmpty? opts) (none) (if (some? (preludeHead opts)) (preludeHead opts) (firstSome (preludeTail opts))))

fn statusMatch s: String bs: Bytes n: Int64 from: Int64 -> (Option String)
  (mt (stringIndexOf (sliceOr s from n) ":status")
    ((none) (none))
    ((some rel)
      (let [(at (+ from rel))
            (j (+ at 7))
            (w (wsRunEnd bs j n))
            (colon (byteIs? bs w n 58))
            (found (if (= w j)
                     (none)
                     (firstSome (list (if (and colon (byteIs? bs (+ w 1) n 34)) (lettersAt s bs (+ w 2) n) (none))
                                      (if colon (lettersAt s bs (+ w 1) n) (none))
                                      (if (byteIs? bs w n 34) (lettersAt s bs (+ w 1) n) (none))
                                      (lettersAt s bs w n)))))]
        (if (some? found) found (statusMatch s bs n (+ at 1))))))

fn taskStatus raw: String -> String
  (let [(text (translateNewlines (utf8Replace raw)))
        (tbs (stringToBytes text))
        (cut (charPrefixEnd tbs (bytesLength tbs) 0 0 4096))
        (head (sliceOr text 0 cut))
        (hbs (stringToBytes head))]
    (optionOr (statusMatch head hbs (bytesLength hbs) 0) "unknown"))

fn ! isDirAt? env: CockpitEnv p: String -> Bool
  (mt (fileStat (resolveAt env p)) ((ok st) st.isDir) ((err _) false))

fn ! isFileAt? env: CockpitEnv p: String -> Bool
  (mt (fileStat (resolveAt env p)) ((ok st) st.isFile) ((err _) false))

fn entryKey! env: CockpitEnv dir: String name: String -> (Pair String Float64)
  (mt (fileStat (resolveAt env (pyJoin dir name)))
    ((ok st) (pair name (if st.isFile (mtimeFloat st) 0.0)))
    ((err _) (pair name 0.0)))

fn taskRows! env: CockpitEnv dir: String entries: (List (Pair String Float64)) acc: (List TaskRow) -> (Result (List TaskRow) String)
  (if (listEmpty? entries)
    (ok (listReverse acc))
    (let [(name (pairFirst (preludeHead entries)))
          (fp (pyJoin dir name))]
      (if (not (isFileAt? env fp))
        (taskRows! env dir (preludeTail entries) acc)
        (mt (fileReadString (resolveAt env fp))
          ((err e) (err e))
          ((ok raw)
            (mt (fileStat (resolveAt env fp))
              ((err e) (err e))
              ((ok st)
                (taskRows! env dir (preludeTail entries)
                          (cons (TaskRow :id (stringReplace name ".asn" "") :filename name :status (taskStatus raw)
                                         :mtime (lt/formatLocal env.zone (lt/floorSeconds (mtimeFloat st)) false)) acc)))))))))

fn getTasksData! env: CockpitEnv -> (Result TasksData String)
  (let [(dir (pyJoin (envRootDir env) ".asl/mem/tasks"))]
    (if (not (isDirAt? env dir))
      (ok (TasksData :totalTasks 0 :recentTasks (list)))
      (mt (dirList (resolveAt env dir))
        ((err e) (err e))
        ((ok names)
          (let [(keyed (listSortBy (fn [(p (Pair String Float64))] -> Float64 (- 0.0 (pairSecond p))) (map (fn [(nm String)] -> (Pair String Float64) (entryKey! env dir nm)) names)))]
            (mt (taskRows! env dir (listTake keyed 10) (list))
              ((err e) (err e))
              ((ok rows) (ok (TasksData :totalTasks (listLength names) :recentTasks rows)))))))))

fn tasksJson t: TasksData -> j/Json
  (j/jobj (list (pair "status" (j/jstr "ok")) (pair "totalTasks" (j/jint t.totalTasks))
                (pair "recentTasks" (j/jarr (map (fn [(r TaskRow)] -> j/Json
                                                   (j/jobj (list (pair "id" (j/jstr r.id)) (pair "filename" (j/jstr r.filename))
                                                                 (pair "status" (j/jstr r.status)) (pair "mtime" (j/jstr r.mtime)))))
                                                 t.recentTasks)))))

fn countIfDir! env: CockpitEnv p: String -> (Result (Option Int64) String)
  (if (isDirAt? env p)
    (mt (dirList (resolveAt env p)) ((ok xs) (ok (some (listLength xs)))) ((err e) (err e)))
    (ok (none)))

fn recentAdrs! env: CockpitEnv dir: String -> (Result (List String) String)
  (if (not (isDirAt? env dir))
    (ok (list))
    (mt (dirList (resolveAt env dir))
      ((err e) (err e))
      ((ok names)
        (mt (statMtimes! env dir (filter asnName? names) (list))
          ((err e) (err e))
          ((ok stats)
            (ok (map (fn [(p (Pair String Float64))] -> String (stringReplace (pairFirst p) ".asn" ""))
                     (listTake (listSortBy (fn [(p (Pair String Float64))] -> Float64 (- 0.0 (pairSecond p))) stats) 6))))))))

fn getMemData! env: CockpitEnv -> (Result MemData String)
  (let [(mem (pyJoin (envRootDir env) ".asl/mem"))
        (dec (pyJoin mem "decisions"))
        (notes (pyJoin mem "notes.asn"))]
    (mt (countIfDir! env dec)
      ((err e) (err e))
      ((ok decisions)
        (mt (countIfDir! env (pyJoin mem "tasks"))
          ((err e) (err e))
          ((ok tasks)
            (mt (countIfDir! env (pyJoin mem "receipts"))
              ((err e) (err e))
              ((ok receipts)
                (let [(notesSize (mt (fileStat (resolveAt env notes)) ((ok st) (if st.isFile (some st.size) (none))) ((err _) (none))))]
                  (mt (recentAdrs! env dec)
                    ((err e) (err e))
                    ((ok adrs) (ok (MemData :decisionsCount decisions :tasksCount tasks :receiptsCount receipts :notesSizeBytes notesSize :recentAdrs adrs))))))))))))

fn optIntJson n: (Option Int64) -> j/Json
  (mt n ((some v) (j/jint v)) ((none) (j/jnull)))

fn memJson m: MemData -> j/Json
  (j/jobj (list (pair "status" (j/jstr "ok"))
                (pair "name" (j/jstr "\u{421}\u{438}\u{441}\u{442}\u{435}\u{43C}\u{430} \u{41C}\u{44D}\u{431}\u{435}\u{43B}\u{438} (.asl/mem)"))
                (pair "decisionsCount" (optIntJson m.decisionsCount)) (pair "tasksCount" (optIntJson m.tasksCount))
                (pair "receiptsCount" (optIntJson m.receiptsCount)) (pair "notesSizeBytes" (optIntJson m.notesSizeBytes))
                (pair "recentAdrs" (j/jarr (map (fn [(a String)] -> j/Json (j/jstr a)) m.recentAdrs)))
                (pair "principlesFile" (j/jstr ".asl/mem/principles.asn")) (pair "roadmapFile" (j/jstr ".asl/mem/roadmap.asn"))))

fn getDaemonsData pid: Int64 port: Int64 st: GatewayStatus -> j/Json
  (j/jobj (list (pair "status" (j/jstr "ok"))
                (pair "daemons" (j/jarr (list (j/jobj (list (pair "id" (j/jstr "asl-gateway")) (pair "pid" (j/jint pid)) (pair "port" (j/jint port))
                                                            (pair "version" (j/jstr st.version)) (pair "inFlight" (j/jint st.inFlight))
                                                            (pair "draining" (j/jbool st.draining)))))))
                (pair "total" (j/jint 1))))

fn emptyIntelCache -> IntelCache
  (IntelCache :timestamp 0.0 :data (none))

fn jsonTruthy? v: j/Json -> Bool
  (mt v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint i) (not (= i 0)))
    ((j/jfloat f) (not (= f 0.0)))
    ((j/jnum f) (not (= f 0.0)))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj kvs) (not (listEmpty? kvs))))

fn cacheHit cache: IntelCache now: Float64 ttl: Float64 -> (Option j/Json)
  (mt cache.data
    ((some d) (if (and (jsonTruthy? d) (< (- now cache.timestamp) ttl)) (some d) (none)))
    ((none) (none)))

fn codePointCount s: String -> Int64
  (let [(bs (stringToBytes s))]
    (charIndex bs (bytesLength bs) 0 0))

fn uniqueKeys kvs: (List (Pair String j/Json)) seen: (List String) -> Int64
  (if (listEmpty? kvs)
    (listLength seen)
    (let [(k (pairFirst (preludeHead kvs)))]
      (uniqueKeys (preludeTail kvs) (if (listContains? seen k) seen (cons k seen)))))

fn pyLen v: j/Json -> (Option Int64)
  (mt v
    ((j/jstr s) (some (codePointCount s)))
    ((j/jarr xs) (some (listLength xs)))
    ((j/jobj kvs) (some (uniqueKeys kvs (list))))
    (_ (none)))

fn jsonGetOr obj: j/Json key: String dflt: j/Json -> j/Json
  (optionOr (j/jsonGet obj key) dflt)

fn setPairs kvs: (List (Pair String j/Json)) key: String val: j/Json -> (List (Pair String j/Json))
  (if (listAny? (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) key)) kvs)
    (map (fn [(p (Pair String j/Json))] -> (Pair String j/Json) (if (= (pairFirst p) key) (pair key val) p)) kvs)
    (listAppend kvs (list (pair key val))))

fn jsonSet obj: j/Json key: String val: j/Json -> j/Json
  (mt obj ((j/jobj kvs) (j/jobj (setPairs kvs key val))) (_ obj))

fn isObj? v: j/Json -> Bool
  (mt v ((j/jobj _) true) (_ false))

fn couplingSummary parsed: j/Json -> (Option j/Json)
  (if (not (isObj? parsed))
    (none)
    (let [(inter (jsonGetOr parsed "interPackage" (j/jobj (list))))]
      (if (not (isObj? inter))
        (none)
        (let [(packages (jsonGetOr inter "packages" (j/jarr (list))))
              (withPackages (jsonSet parsed "packages" packages))
              (mf (jsonGetOr withPackages "moduleFictions" (j/jobj (list))))
              (pkgLen (pyLen packages))]
          (if (or (none? pkgLen) (not (isObj? mf)))
            (none)
            (let [(g (pyLen (jsonGetOr mf "ghostModules" (j/jarr (list)))))
                  (v (pyLen (jsonGetOr mf "vacuousModules" (j/jarr (list)))))
                  (u (pyLen (jsonGetOr mf "undeclaredImports" (j/jarr (list)))))]
              (if (or (none? g) (none? v) (none? u))
                (none)
                (some (jsonSet withPackages "summary"
                               (j/jobj (list (pair "status" (j/jstr "ok"))
                                             (pair "totalPackages" (jsonGetOr withPackages "packagesTotal" (j/jint (optionOr pkgLen 0))))
                                             (pair "totalModules" (jsonGetOr withPackages "modulesTotal" (j/jint 0)))
                                             (pair "cycles" (jsonGetOr inter "cyclesCount" (j/jint 0)))
                                             (pair "totalFictions" (j/jint (+ (optionOr g 0) (+ (optionOr v 0) (optionOr u 0))))))))))))))))

fn runIntel! env: CockpitEnv bin: String sub: String timeoutMs: Int64 -> (Option j/Json)
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd bin (list "intel" sub "--json")) env.cwd) timeoutMs))
    ((err _) (none))
    ((ok out)
      (let [(text out.stdout) (bs (stringToBytes text))]
        (if (or (not (= out.exitCode 0)) (stringEmpty? text) (some? (utf8FirstIssue bs (bytesLength bs) 0)))
          (none)
          (mt (j/jsonParse text) ((ok v) (some v)) ((err _) (none)))))))

fn ! existsAt? env: CockpitEnv p: String -> Bool
  (ok? (fileStat (resolveAt env p)))

fn parentDir p: String -> String
  (let [(trimmed (if (and (stringEndsWith? p "/") (> (stringLength p) 1)) (sliceOr p 0 (- (stringLength p) 1)) p))
        (parts (stringSplit trimmed "/"))
        (kept (listTake parts (- (listLength parts) 1)))
        (joined (stringJoin kept "/"))]
    (if (stringEmpty? joined) "/" joined))

fn getIntelCouplingData! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache j/Json)
  (mt (cacheHit cache now 10.0)
    ((some d) (pair cache d))
    ((none)
      (let [(rootDir (mt env.rootEnv ((some r) (if (stringEmpty? r) (parentDir env.cwd) r)) ((none) (parentDir env.cwd))))
            (primary (pyJoin rootDir "bin/asl"))
            (bin (if (and (not (existsAt? env primary)) (existsAt? env "./bin/asl")) "./bin/asl" primary))
            (result (if (existsAt? env bin) (mt (runIntel! env bin "coupling" 5000) ((some p) (couplingSummary p)) ((none) (none))) (none)))]
        (mt result
          ((some p) (pair (IntelCache :timestamp now :data (some p)) p))
          ((none)
            (pair cache (j/jobj (list (pair "status" (j/jstr "unavailable")) (pair "reason" (j/jstr (str bin " intel coupling gave no result")))
                                      (pair "summary" (j/jobj (list (pair "status" (j/jstr "unavailable"))))) (pair "packages" (j/jarr (list)))))))))))

fn intelSimple! cache: IntelCache now: Float64 env: CockpitEnv sub: String timeoutMs: Int64 ttl: Float64 missing: (fn [String] -> j/Json) -> (Pair IntelCache j/Json)
  (mt (cacheHit cache now ttl)
    ((some d) (pair cache d))
    ((none)
      (let [(bin (pyJoin (pyJoin (envRootDir env) "bin") "asl"))
            (result (if (existsAt? env bin) (runIntel! env bin sub timeoutMs) (none)))]
        (mt result
          ((some p) (pair (IntelCache :timestamp now :data (some p)) p))
          ((none) (pair cache (missing bin)))))))

fn getVitalityData! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache j/Json)
  (intelSimple! cache now env "vitality" 8000 8.0
               (fn [(bin String)] -> j/Json
                 (j/jobj (list (pair "status" (j/jstr "unavailable")) (pair "reason" (j/jstr (str bin " intel vitality gave no result within 8 s")))
                               (pair "vitalityScore" (j/jnull)) (pair "stages" (j/jarr (list)))))))

fn getStubsData! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache j/Json)
  (intelSimple! cache now env "stubs" 6000 8.0
               (fn [(bin String)] -> j/Json
                 (j/jobj (list (pair "status" (j/jstr "unavailable")) (pair "reason" (j/jstr (str bin " intel stubs gave no result within 6 s")))
                               (pair "stubsCount" (j/jnull)) (pair "stubs" (j/jarr (list)))))))

fn someText s: String -> (Option String)
  (some s)

fn usageCols -> (List String)
  (list "name" "requests" "ok" "errors" "fallbacks" "inputTokens" "cachedTokens" "outputTokens")

fn knownRedBody kr: (Result KnownRed String) -> String
  (mt kr
    ((err e) (cockpitMissing e))
    ((ok k)
      (str (cockpitTable (list "known red suites" "date" "capturedFrom" "confirmation")
                         (list (list (intCell k.count) k.date k.capturedFrom k.confirmation)))
           (cockpitTable (list "suite" "cause") (map (fn [(r KnownRedRow)] -> (List (Option String)) (list (some r.suite) (some r.cause))) k.rows)))))

fn gatesBody g: (Result GatesRecord String) -> String
  (mt g
    ((err e) (cockpitMissing e))
    ((ok r) (cockpitTable (list "fullGreen records" "latest" "written") (list (list (intCell r.count) (some r.latest) (some r.mtime))))))

fn calibrationBody c: (Result Calibration String) -> String
  (mt c
    ((err e) (cockpitMissing e))
    ((ok cal)
      (str (cockpitTable (list "updated") (list (list (some cal.updated))))
           (cockpitTable (list "model" "status" "date")
                         (map (fn [(r CalibrationRow)] -> (List (Option String)) (list (some r.id) (some r.status) (some r.date))) cal.rows)))))

fn profileCell p: ProfileHealth -> (Option String)
  (mt p.name
    ((some n) (if (stringEmpty? n) p.error (some n)))
    ((none) p.error))

fn pageHead -> String
  (str "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\"/>\n<meta http-equiv=\"refresh\" content=\"10\"/>\n<title>ASL Gateway Cockpit</title>\n<style>\n"
       "  :root { --bg: #0b0f19; --tile: #111827; --line: #1e293b; --fg: #f8fafc; --muted: #94a3b8; }\n"
       "  body { margin: 0; padding: 20px 24px; background: var(--bg); color: var(--fg); font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif; }\n"
       "  header { padding-bottom: 12px; border-bottom: 1px solid var(--line); margin-bottom: 16px; }\n"
       "  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 16px; }\n"
       "  .tile { background: var(--tile); border: 1px solid var(--line); border-radius: 8px; padding: 14px; overflow-x: auto; }\n"
       "  h2 { font-size: 15px; margin: 0 0 4px 0; }\n"
       "  .src, .none { color: var(--muted); font-size: 11px; }\n"
       "  table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }\n"
       "  th, td { text-align: left; padding: 5px 7px; border-bottom: 1px solid var(--line); }\n"
       "  th { color: var(--muted); font-size: 11px; }\n"
       "</style>\n</head>\n<body>\n")

fn tasksTile r: (Result TasksData String) -> String
  (mt r
    ((err e) (cockpitTile "Tasks" (cockpitMissing e) ".asl/mem/tasks :status of each file"))
    ((ok tk)
      (cockpitTile (str "Tasks (" (stringFromInt64 tk.totalTasks) " files)")
                   (cockpitTable (list "task" "status" "modified")
                                 (map (fn [(t TaskRow)] -> (List (Option String)) (list (some t.id) (some t.status) (some t.mtime))) tk.recentTasks))
                   ".asl/mem/tasks :status of each file")))

fn memTile r: (Result MemData String) -> String
  (mt r
    ((err e) (cockpitTile "Memory" (cockpitMissing e) ".asl/mem"))
    ((ok mem)
      (cockpitTile "Memory" (cockpitTable (list "decisions" "tasks" "receipts" "notes bytes")
                                          (list (list (optIntCell mem.decisionsCount) (optIntCell mem.tasksCount)
                                                      (optIntCell mem.receiptsCount) (optIntCell mem.notesSizeBytes))))
                   ".asl/mem")))

fn cockpitHtml! state: CockpitState env: CockpitEnv -> (Result String String)
  (let [(st state.status)
        (zone env.zone)
        (since (lt/formatLocal zone (lt/floorSeconds state.usage.since) false))
        (gatewayTile (cockpitTile "Gateway"
                                  (cockpitTable (list "pid" "port" "version" "diskVersion" "stale" "inFlight" "draining" "updates" "profile")
                                                (list (list (intCell st.pid) (intCell state.port) (some st.version) (some st.diskVersion)
                                                            (some (boolText st.stale)) (intCell st.inFlight) (some (boolText st.draining))
                                                            (intCell st.updates) (profileCell state.profile))))
                                  "/health"))
        (poolsTile (cockpitTile "Pools"
                                (cockpitTable (list "pool" "size" "busy" "queued")
                                              (map (fn [(p PoolStats)] -> (List (Option String)) (list (some p.name) (intCell p.size) (intCell p.busy) (intCell p.queued)))
                                                   (listSortBy (fn [(p PoolStats)] -> String p.name) state.pools)))
                                "/health :pools"))
        (providersTile (cockpitTile (str "Usage by provider since " since) (cockpitTable (usageCols) (cockpitUsageRows state.usage.providers)) "/health :usage :providers"))
        (aliasesTile (cockpitTile (str "Usage by alias since " since) (cockpitTable (usageCols) (cockpitUsageRows state.usage.aliases)) "/health :usage :aliases"))]
    (mt (cockpitKnownRed! env)
      ((err h) (err h))
      ((ok kr)
        (mt (cockpitGates! env)
          ((err h) (err h))
          ((ok gt)
            (mt (cockpitCalibration! env)
              ((err h) (err h))
              ((ok cal)
                (let [(tiles (list gatewayTile poolsTile providersTile aliasesTile
                                   (cockpitTile "Known red" (knownRedBody kr) ".asl/mem/knownRed.asn")
                                   (cockpitTile "Gates" (gatesBody gt) ".asl/mem/benchmarks/fullGreen")
                                   (cockpitTile "Calibration" (calibrationBody cal) (calibrationIndexPath env))
                                   (tasksTile (getTasksData! env))
                                   (memTile (getMemData! env))))
                      (rendered (lt/formatLocal zone (lt/floorSeconds state.now) true))]
                  (ok (str (pageHead)
                           "<header><strong>ASL Gateway Cockpit</strong> <span class=\"src\">rendered " rendered
                           "; every figure is read at render time from the source named on its tile; \u{2014} marks a figure with no source</span></header>\n"
                           "<main class=\"grid\">\n" (stringJoin tiles "\n") "\n</main>\n</body>\n</html>\n"))))))))))

fn cockpitEnvFromProcess! -> (Result CockpitEnv String)
  (mt (realPath ".")
    ((err e) (err e))
    ((ok cwd)
      (mt (lt/zoneLoad! (envGet "TZ"))
        ((err e) (err e))
        ((ok zone)
          (mt (platformInfo)
            ((err e) (err e))
            ((ok info) (ok (CockpitEnv :rootEnv (envGet "ROOT_DIR") :cwd cwd :calibrationEnv (envGet "ASL_CALIBRATION_INDEX") :zone zone :platform info.os))))))))


fn emptyCockpitCaches -> CockpitCaches
  (CockpitCaches :intel (emptyIntelCache) :vitality (emptyIntelCache) :stubs (emptyIntelCache))

fn pyJsonDump val: j/Json -> String
  (pt/jsonDumps val -1)

fn jsonIntOr vOpt: (Option j/Json) dflt: Int64 -> Int64
  (mt vOpt
    ((some v)
      (mt v
        ((j/jint i) i)
        ((j/jfloat f) (optionOr (float64ToInt64 f) dflt))
        ((j/jnum n) (optionOr (float64ToInt64 n) dflt))
        (_ dflt)))
    ((none) dflt))

fn jsonStrOr vOpt: (Option j/Json) dflt: String -> String
  (mt vOpt
    ((some v)
      (mt v
        ((j/jstr s) s)
        (_ dflt)))
    ((none) dflt))

fn blastNode p: j/Json -> j/Json
  (let [(modName (jsonStrOr (j/jsonGet p "package") ""))
        (fi (jsonIntOr (j/jsonGet p "fanIn") 0))
        (fo (jsonIntOr (j/jsonGet p "fanOut") 0))
        (bc (+ fi fo))]
    (j/jobj (list (pair "module" (j/jstr modName))
                  (pair "blastCount" (j/jint bc))
                  (pair "cycles" (j/jint 0)))))

fn observatoryBlastRadius intel: j/Json -> j/Json
  (let [(statusVal (optionOr (j/jsonGet intel "status") (j/jstr "ok")))
        (summaryVal (optionOr (j/jsonGet intel "summary") (j/jobj (list))))
        (pkgsVal (optionOr (j/jsonGet intel "packages") (j/jarr (list))))
        (blastNodes (mt pkgsVal
                      ((j/jarr xs) (map blastNode (listTake xs 6)))
                      (_ (list))))]
    (j/jobj (list (pair "status" statusVal)
                  (pair "blastRadius" (j/jarr blastNodes))
                  (pair "coupling" summaryVal)
                  (pair "packages" pkgsVal))))

fn observatory_blast_radius intel: j/Json -> j/Json
  (observatoryBlastRadius intel)

fn serveCockpitDashboard! state: CockpitState env: CockpitEnv -> (Result CockpitResponse String)
  (mt (cockpitHtml! state env)
    ((err e) (err e))
    ((ok page)
      (let [(bodyLen (bytesLength (stringToBytes page)))]
        (ok (CockpitResponse
              :status 200
              :headers (list (pair "Content-Type" "text/html; charset=utf-8")
                             (pair "Content-Length" (stringFromInt64 bodyLen)))
              :body page)))))

fn serve_cockpit_dashboard! state: CockpitState env: CockpitEnv -> (Result CockpitResponse String)
  (serveCockpitDashboard! state env)

fn serveCockpitObservatoryApi! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (let [(step (getIntelCouplingData! cache now env))
        (newCache (pairFirst step))
        (intel (pairSecond step))
        (data (observatoryBlastRadius intel))
        (body (pyJsonDump data))]
    (pair newCache (CockpitResponse
                     :status 200
                     :headers (list (pair "Content-Type" "application/json"))
                     :body body)))

fn serve_cockpit_observatory_api! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (serveCockpitObservatoryApi! cache now env)

fn serveCockpitIntelApi! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (let [(step (getIntelCouplingData! cache now env))
        (newCache (pairFirst step))
        (intel (pairSecond step))
        (body (pyJsonDump intel))]
    (pair newCache (CockpitResponse
                     :status 200
                     :headers (list (pair "Content-Type" "application/json"))
                     :body body)))

fn serve_cockpit_intel_api! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (serveCockpitIntelApi! cache now env)

fn serveCockpitVitalityApi! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (let [(step (getVitalityData! cache now env))
        (newCache (pairFirst step))
        (vitality (pairSecond step))
        (body (pyJsonDump vitality))]
    (pair newCache (CockpitResponse
                     :status 200
                     :headers (list (pair "Content-Type" "application/json"))
                     :body body)))

fn serve_cockpit_vitality_api! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (serveCockpitVitalityApi! cache now env)

fn serveCockpitStubsApi! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (let [(step (getStubsData! cache now env))
        (newCache (pairFirst step))
        (stubs (pairSecond step))
        (body (pyJsonDump stubs))]
    (pair newCache (CockpitResponse
                     :status 200
                     :headers (list (pair "Content-Type" "application/json"))
                     :body body)))

fn serve_cockpit_stubs_api! cache: IntelCache now: Float64 env: CockpitEnv -> (Pair IntelCache CockpitResponse)
  (serveCockpitStubsApi! cache now env)

fn serveCockpitDaemonsApi pid: Int64 port: Int64 st: GatewayStatus -> CockpitResponse
  (let [(daemons (getDaemonsData pid port st))
        (body (pyJsonDump daemons))]
    (CockpitResponse
      :status 200
      :headers (list (pair "Content-Type" "application/json"))
      :body body))

fn serve_cockpit_daemons_api pid: Int64 port: Int64 st: GatewayStatus -> CockpitResponse
  (serveCockpitDaemonsApi pid port st)

fn serveCockpitTasksApi! env: CockpitEnv -> (Result CockpitResponse String)
  (mt (getTasksData! env)
    ((err e) (err e))
    ((ok t)
      (let [(data (tasksJson t))
            (body (pyJsonDump data))]
        (ok (CockpitResponse
              :status 200
              :headers (list (pair "Content-Type" "application/json"))
              :body body)))))

fn serve_cockpit_tasks_api! env: CockpitEnv -> (Result CockpitResponse String)
  (serveCockpitTasksApi! env)

fn serveCockpitMemApi! env: CockpitEnv -> (Result CockpitResponse String)
  (mt (getMemData! env)
    ((err e) (err e))
    ((ok m)
      (let [(data (memJson m))
            (body (pyJsonDump data))]
        (ok (CockpitResponse
              :status 200
              :headers (list (pair "Content-Type" "application/json"))
              :body body)))))

fn serve_cockpit_mem_api! env: CockpitEnv -> (Result CockpitResponse String)
  (serveCockpitMemApi! env)

fn cockpitDispatchGet! path: String state: CockpitState env: CockpitEnv caches: CockpitCaches -> (Option CockpitDispatchResult)
  (cond
    ((or (= path "/cockpit") (= path "/cockpit/"))
      (some (CockpitDispatchResult :caches caches :response (serveCockpitDashboard! state env))))

    ((= path "/cockpit/api/observatory")
      (let [(res (serveCockpitObservatoryApi! caches.intel state.now env))
            (nextCaches (with caches :intel (pairFirst res)))]
        (some (CockpitDispatchResult :caches nextCaches :response (ok (pairSecond res))))))

    ((or (= path "/cockpit/api/intel") (= path "/cockpit/api/coupling"))
      (let [(res (serveCockpitIntelApi! caches.intel state.now env))
            (nextCaches (with caches :intel (pairFirst res)))]
        (some (CockpitDispatchResult :caches nextCaches :response (ok (pairSecond res))))))

    ((= path "/cockpit/api/vitality")
      (let [(res (serveCockpitVitalityApi! caches.vitality state.now env))
            (nextCaches (with caches :vitality (pairFirst res)))]
        (some (CockpitDispatchResult :caches nextCaches :response (ok (pairSecond res))))))

    ((= path "/cockpit/api/stubs")
      (let [(res (serveCockpitStubsApi! caches.stubs state.now env))
            (nextCaches (with caches :stubs (pairFirst res)))]
        (some (CockpitDispatchResult :caches nextCaches :response (ok (pairSecond res))))))

    ((= path "/cockpit/api/daemons")
      (let [(resp (serveCockpitDaemonsApi state.status.pid state.port state.status))]
        (some (CockpitDispatchResult :caches caches :response (ok resp)))))

    ((= path "/cockpit/api/tasks")
      (some (CockpitDispatchResult :caches caches :response (serveCockpitTasksApi! env))))

    ((or (= path "/cockpit/api/mem") (= path "/cockpit/api/memory"))
      (some (CockpitDispatchResult :caches caches :response (serveCockpitMemApi! env))))

    (else (none)))

fn cockpit_dispatch_get! path: String state: CockpitState env: CockpitEnv caches: CockpitCaches -> (Option CockpitDispatchResult)
  (cockpitDispatchGet! path state env caches)
