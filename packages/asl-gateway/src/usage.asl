(module aslGateway/usage
  :x [GatewayStatus
      pyTruthy?
      pyStr
      pyRound3
      jsonDedup
      usageInit
      usageTokens
      usageNote
      usageFallback
      usageHttpError
      usageException
      usageAgyFallback
      usageAsn
      usageRestoreParse
      usageRestoreApply
      usageRestore!
      wordRanges
      nfkcBadNetloc
      analyzeTelemetry
      telemetryNowMs!
      telemetryLogPath
      logTelemetryEvent!
      cleanUrl
      loadZshEnvText
      loadZshEnv!
      gatewayFileVersion!
      gatewayUpdateStatus
      gatewayStatusJson
      gatewayUpdateAsn]
  :i [(asl-json/json :a j)
      (upstream :a u)
      (wire :a w)])

(schema GatewayStatus
  (:f pid Int64)
  (:f version String)
  (:f diskVersion String)
  (:f stale Bool)
  (:f diskValid Bool)
  (:f updates Int64)
  (:f updatedFrom String)
  (:f inFlight Int64)
  (:f draining Bool))

fn pyTruthy? v: j/Json -> Bool
  (mt v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint i) (not (= i 0)))
    ((j/jfloat f) (not (= f 0.0)))
    ((j/jnum f) (not (= f 0.0)))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj kvs) (not (listEmpty? kvs))))

fn hexByte b: Int64 -> String
  (let [(digits "0123456789abcdef")]
    (str (u/slice digits (/ b 16) (+ (/ b 16) 1)) (u/slice digits (mod b 16) (+ (mod b 16) 1))))

fn reprLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 q: Int64 acc: (List String) -> String
  (if (>= i n)
    (u/joinAll (listReverse (cons (u/slice s start n) acc)))
    (let [(d (u/utf8Next bs i n))
          (cp (pairFirst d))
          (k (pairSecond d))
          (esc (cond
                 ((= cp 92) "\\\\")
                 ((= cp q) (if (= q 39) "\\'" "\\\""))
                 ((= cp 10) "\\n")
                 ((= cp 13) "\\r")
                 ((= cp 9) "\\t")
                 ((and (>= cp 0) (< cp 32)) (str "\\x" (hexByte cp)))
                 ((and (>= cp 127) (<= cp 160)) (str "\\x" (hexByte cp)))
                 ((= cp 173) "\\xad")
                 (else "")))]
      (if (stringEmpty? esc)
        (reprLoop s bs n (+ i k) start q acc)
        (reprLoop s bs n (+ i k) (+ i k) q (cons esc (cons (u/slice s start i) acc))))))

fn pyReprString s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) 34 39))
        (bs (stringToBytes s))
        (quote (if (= q 34) "\"" "'"))]
    (str quote (reprLoop s bs (bytesLength bs) 0 0 q (list)) quote))

fn pyRepr v: j/Json -> String
  (mt v
    ((j/jstr s) (pyReprString s))
    ((j/jarr xs) (str "[" (stringJoin (map (fn [(x j/Json)] -> String (pyRepr x)) xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (stringJoin (map (fn [(p (Pair String j/Json))] -> String (str (pyReprString (pairFirst p)) ": " (pyRepr (pairSecond p)))) kvs) ", ") "}"))
    (_ (pyStr v)))

fn pyStr v: j/Json -> String
  (mt v
    ((j/jnull) "None")
    ((j/jbool b) (if b "True" "False"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum f) (stringFromFloat64 f))
    ((j/jstr s) s)
    (_ (pyRepr v)))

fn pow2 k: Int64 -> Int64
  (if (<= k 0) 1 (* 2 (pow2 (- k 1))))

fn padThree n: Int64 -> String
  (cond
    ((< n 10) (str "00" (stringFromInt64 n)))
    ((< n 100) (str "0" (stringFromInt64 n)))
    (else (stringFromInt64 n)))

fn scaledRound m: Int64 k: Int64 -> Int64
  (let [(v (* m 1000))]
    (cond
      ((>= k 64) 0)
      ((= k 63) (if (> v (pow2 62)) 1 0))
      (else
       (let [(p (pow2 k))
             (q (/ v p))
             (r (- v (* q p)))]
         (cond
           ((> (* r 2) p) (+ q 1))
           ((< (* r 2) p) q)
           ((= (mod q 2) 1) (+ q 1))
           (else q))))))

fn pyRound3 x: Float64 -> Float64
  (if (or (isNan? x) (not (isFinite? x)))
    x
    (let [(buf (bytesAlloc 8))
          (wrote (bytesSetFloat64 buf 0 x))
          (b7 (bytesGet buf 7))
          (b6 (bytesGet buf 6))
          (neg (>= b7 128))
          (ex (+ (* (mod b7 128) 16) (/ b6 16)))
          (frac (+ (* (mod b6 16) 281474976710656)
                   (+ (* (bytesGet buf 5) 1099511627776)
                      (+ (* (bytesGet buf 4) 4294967296)
                         (+ (* (bytesGet buf 3) 16777216)
                            (+ (* (bytesGet buf 2) 65536) (+ (* (bytesGet buf 1) 256) (bytesGet buf 0))))))))
          (m (if (= ex 0) frac (+ frac 4503599627370496)))
          (e2 (if (= ex 0) -1074 (- ex 1075)))]
      (if (>= e2 0)
        x
        (let [(n (scaledRound m (- 0 e2)))
              (text (str (if neg "-" "") (stringFromInt64 (/ n 1000)) "." (padThree (mod n 1000))))]
          (optionOr (stringToFloat64 text) x)))))

fn dedupPairs kvs: (List (Pair String j/Json)) acc: (List (Pair String j/Json)) -> (List (Pair String j/Json))
  (mt (listHead kvs)
    ((none) acc)
    ((some p) (dedupPairs (optionOr (listTail kvs) (list)) (u/objSet acc (pairFirst p) (pairSecond p)))))

fn jsonDedup v: j/Json -> j/Json
  (mt v
    ((j/jobj kvs) (j/jobj (map (fn [(p (Pair String j/Json))] -> (Pair String j/Json) (pair (pairFirst p) (jsonDedup (pairSecond p))))
                               (dedupPairs kvs (list)))))
    ((j/jarr xs) (j/jarr (map (fn [(x j/Json)] -> j/Json (jsonDedup x)) xs)))
    (_ v))

fn objKvs v: j/Json -> (List (Pair String j/Json))
  (mt v
    ((j/jobj kvs) kvs)
    (_ (list)))

fn objField v: j/Json k: String -> j/Json
  (optionOr (u/objGet (objKvs v) k) (j/jnull))

fn usageInit since: Float64 -> j/Json
  (j/jobj (list (pair "since" (j/jfloat since)) (pair "providers" (j/jobj (list))) (pair "aliases" (j/jobj (list)))))

fn positiveInt v: (Option j/Json) -> Int64
  (mt v
    ((some x) (mt x ((j/jint i) (if (> i 0) i 0)) (_ 0)))
    ((none) 0))

fn nullish? v: (Option j/Json) -> Bool
  (mt v
    ((none) true)
    ((some x) (= x (j/jnull))))

fn usageTokens usage: j/Json -> (List Int64)
  (mt usage
    ((j/jobj kvs)
     (if (some? (u/objGet kvs "inputTokens"))
       (list (positiveInt (u/objGet kvs "inputTokens")) (positiveInt (u/objGet kvs "cachedTokens")) (positiveInt (u/objGet kvs "outputTokens")))
       (let [(cached (u/objGet kvs "cached_tokens"))
             (details (u/objGet kvs "prompt_tokens_details"))
             (fromDetails (mt details
                            ((some d) (mt d ((j/jobj dk) (some (u/objGet dk "cached_tokens"))) (_ none)))
                            ((none) none)))
             (c (if (nullish? cached)
                  (mt fromDetails ((some x) x) ((none) cached))
                  cached))]
         (list (positiveInt (u/objGet kvs "prompt_tokens")) (positiveInt c) (positiveInt (u/objGet kvs "completion_tokens"))))))
    (_ (list 0 0 0)))

fn defaultRow -> j/Json
  (j/jobj (list (pair "requests" (j/jint 0)) (pair "ok" (j/jint 0)) (pair "errors" (j/jobj (list))) (pair "fallbacks" (j/jint 0))
                (pair "inputTokens" (j/jint 0)) (pair "cachedTokens" (j/jint 0)) (pair "outputTokens" (j/jint 0)) (pair "lastErrorAt" (j/jnull))))

fn setField v: j/Json k: String x: j/Json -> j/Json
  (j/jobj (u/objSet (objKvs v) k x))

fn rowNames provider: (Option String) alias: (Option String) -> (List (Pair String String))
  (let [(p (mt provider ((some s) (if (stringEmpty? s) (list) (list (pair "providers" s)))) ((none) (list))))
        (a (mt alias ((some s) (if (stringEmpty? s) (list) (list (pair "aliases" s)))) ((none) (list))))]
    (listAppend p a))

fn ensureRows state: j/Json names: (List (Pair String String)) -> j/Json
  (fold (fn [(st j/Json) (n (Pair String String))] -> j/Json
          (let [(kind (objField st (pairFirst n)))]
            (if (some? (u/objGet (objKvs kind) (pairSecond n)))
              st
              (setField st (pairFirst n) (setField kind (pairSecond n) (defaultRow))))))
        state names)

fn subscript r: j/Json k: String -> (Result j/Json String)
  (mt r
    ((j/jobj kvs) (mt (u/objGet kvs k) ((some v) (ok v)) ((none) (err "KeyError"))))
    (_ (err "TypeError")))

fn pyAddInt v: j/Json n: Int64 -> (Result j/Json String)
  (mt v
    ((j/jint i) (ok (j/jint (+ i n))))
    ((j/jbool b) (ok (j/jint (+ (if b 1 0) n))))
    ((j/jfloat f) (ok (j/jfloat (+ f (int64ToFloat64 n)))))
    ((j/jnum f) (ok (j/jfloat (+ f (int64ToFloat64 n)))))
    (_ (err "TypeError")))

fn rowAdd r: j/Json k: String n: Int64 -> (Result j/Json String)
  (mt (subscript r k)
    ((err e) (err e))
    ((ok v)
     (mt (pyAddInt v n)
       ((err e) (err e))
       ((ok nv) (ok (setField r k nv))))))

fn rowSteps r: j/Json steps: (List (Pair String Int64)) -> (Pair j/Json (Option String))
  (mt (listHead steps)
    ((none) (pair r none))
    ((some s)
     (mt (rowAdd r (pairFirst s) (pairSecond s))
       ((err e) (pair r (some e)))
       ((ok r2) (rowSteps r2 (optionOr (listTail steps) (list)))))))

fn rowError r: j/Json outcome: String now: Float64 -> (Pair j/Json (Option String))
  (mt (subscript r "errors")
    ((err e) (pair r (some e)))
    ((ok errs)
     (mt errs
       ((j/jobj ekvs)
        (mt (pyAddInt (optionOr (u/objGet ekvs outcome) (j/jint 0)) 1)
          ((err e) (pair r (some e)))
          ((ok nv) (pair (setField (setField r "errors" (j/jobj (u/objSet ekvs outcome nv))) "lastErrorAt" (j/jfloat (pyRound3 now))) none))))
       (_ (pair r (some "AttributeError"))))))

fn noteRow r: j/Json outcome: String tokens: (List Int64) now: Float64 -> (Pair j/Json (Option String))
  (if (= outcome "ok")
    (rowSteps r (list (pair "requests" 1) (pair "ok" 1) (pair "inputTokens" (optionOr (listGet tokens 0) 0))
                      (pair "cachedTokens" (optionOr (listGet tokens 1) 0)) (pair "outputTokens" (optionOr (listGet tokens 2) 0))))
    (let [(first (rowSteps r (list (pair "requests" 1))))]
      (mt (pairSecond first)
        ((some e) first)
        ((none) (rowError (pairFirst first) outcome now)))))

fn putRow state: j/Json n: (Pair String String) r: j/Json -> j/Json
  (setField state (pairFirst n) (setField (objField state (pairFirst n)) (pairSecond n) r))

fn applyRows state: j/Json names: (List (Pair String String)) f: (fn [j/Json] -> (Pair j/Json (Option String))) -> (Pair j/Json (Option String))
  (mt (listHead names)
    ((none) (pair state none))
    ((some n)
     (let [(res (f (objField (objField state (pairFirst n)) (pairSecond n))))
           (st2 (putRow state n (pairFirst res)))]
       (mt (pairSecond res)
         ((some e) (pair st2 (some e)))
         ((none) (applyRows st2 (optionOr (listTail names) (list)) f))))))

fn usageNote state: j/Json provider: (Option String) alias: (Option String) outcome: String usage: j/Json now: Float64 -> (Pair j/Json (Option String))
  (let [(tokens (usageTokens usage))
        (names (rowNames provider alias))]
    (applyRows (ensureRows state names) names (fn [(r j/Json)] -> (Pair j/Json (Option String)) (noteRow r outcome tokens now))))

fn usageFallback state: j/Json provider: (Option String) alias: (Option String) -> (Pair j/Json (Option String))
  (let [(names (rowNames provider alias))]
    (applyRows (ensureRows state names) names (fn [(r j/Json)] -> (Pair j/Json (Option String)) (rowSteps r (list (pair "fallbacks" 1))))))

fn usageHttpError code: Int64 -> String
  (cond
    ((= code 429) "429")
    ((>= code 500) "5xx")
    (else "4xx"))

fn usageException failure: u/UpstreamFailure -> String
  (mt failure
    ((u/transportFailure code _) (if (= code 28) "timeout" "other"))
    (_ "other"))

fn dispatchText d: j/Json -> (Result j/Json String)
  (if (not (pyTruthy? d))
    (ok (j/jnull))
    (mt d
      ((j/jobj kvs) (ok (optionOr (u/objGet kvs "text") (j/jnull))))
      (_ (err "AttributeError"))))

fn noteThen res: (Pair j/Json (Option String)) value: j/Json -> (Pair j/Json (Result j/Json String))
  (mt (pairSecond res)
    ((some e) (pair (pairFirst res) (err e)))
    ((none) (pair (pairFirst res) (ok value))))

fn usageAgyFallback state: j/Json prompt: String workspace: (Option String) downFor: (fn [String] -> Int64) dispatch: (fn [String (Option String)] -> j/Json) now: Float64 -> (Pair j/Json (Result j/Json String))
  (cond
    ((stringEmpty? prompt) (pair state (ok (j/jnull))))
    ((not (= (downFor "agy") 0))
     (noteThen (usageNote state (some "agy-cli") (some "agyFallback") "skipped-breaker" (j/jnull) now) (j/jnull)))
    (else
     (mt (dispatchText (dispatch prompt workspace))
       ((err e) (pair state (err e)))
       ((ok text) (noteThen (usageNote state (some "agy-cli") (some "agyFallback") (if (pyTruthy? text) "ok" "failed") (j/jnull) now) text)))))

fn asnStr s: String -> String
  (str "\"" (w/asnEscape s) "\"")

fn pyRoundJson v: j/Json -> (Result j/Json String)
  (mt v
    ((j/jint i) (ok v))
    ((j/jbool b) (ok (j/jint (if b 1 0))))
    ((j/jfloat f) (ok (j/jfloat (pyRound3 f))))
    ((j/jnum f) (ok (j/jfloat (pyRound3 f))))
    (_ (err "TypeError")))

fn asnNumberText v: j/Json -> String
  (mt v
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum f) (stringFromFloat64 f))
    (_ "nil"))

fn fieldTexts r: j/Json keys: (List String) acc: (List String) -> (Result (List String) String)
  (mt (listHead keys)
    ((none) (ok (listReverse acc)))
    ((some k)
     (mt (subscript r k)
       ((err e) (err e))
       ((ok v) (fieldTexts r (optionOr (listTail keys) (list)) (cons (pyStr v) acc))))))

fn errorsText errs: j/Json -> (Result String String)
  (mt errs
    ((j/jobj kvs) (ok (stringJoin (map (fn [(p (Pair String j/Json))] -> String (str "(:status " (asnStr (pairFirst p)) " :count " (pyStr (pairSecond p)) ")")) kvs) " ")))
    (_ (err "AttributeError")))

fn nth xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn rowAsn head: String name: String r: j/Json -> (Result String String)
  (mt (subscript r "errors")
    ((err e) (err e))
    ((ok errs)
     (mt (errorsText errs)
       ((err e) (err e))
       ((ok errText)
        (mt (subscript r "lastErrorAt")
          ((err e) (err e))
          ((ok lastVal)
           (mt (fieldTexts r (list "requests" "ok" "fallbacks" "inputTokens" "cachedTokens" "outputTokens") (list))
             ((err e) (err e))
             ((ok fs)
              (ok (str "(:" head " " (asnStr name) " :requests " (nth fs 0) " :ok " (nth fs 1) " :errors (" errText ") :fallbacks " (nth fs 2)
                       " :inputTokens " (nth fs 3) " :cachedTokens " (nth fs 4) " :outputTokens " (nth fs 5) " :lastErrorAt " (asnNumberText lastVal) ")"))))))))))

fn rowsAsn kvs: (List (Pair String j/Json)) head: String acc: (List String) -> (Result String String)
  (mt (listHead kvs)
    ((none) (ok (stringJoin (listReverse acc) " ")))
    ((some p)
     (mt (rowAsn head (pairFirst p) (pairSecond p))
       ((err e) (err e))
       ((ok t) (rowsAsn (optionOr (listTail kvs) (list)) head (cons t acc))))))

fn usageAsn state: j/Json -> (Result String String)
  (mt (pyRoundJson (objField state "since"))
    ((err e) (err e))
    ((ok since)
     (mt (rowsAsn (objKvs (objField state "providers")) "provider" (list))
       ((err e) (err e))
       ((ok ps)
        (mt (rowsAsn (objKvs (objField state "aliases")) "alias" (list))
          ((err e) (err e))
          ((ok as) (ok (str "(:since " (pyStr since) " :providers (" ps ") :aliases (" as "))"))))))))

fn validUtf8Loop bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n)
    true
    (let [(d (u/utf8Next bs i n))]
      (if (< (pairFirst d) 0) false (validUtf8Loop bs (+ i (pairSecond d)) n))))

fn validUtf8? s: String -> Bool
  (let [(bs (stringToBytes s))]
    (validUtf8Loop bs 0 (bytesLength bs)))

fn usageRestoreParse raw: String -> (Option j/Json)
  (if (not (validUtf8? raw))
    none
    (mt (j/jsonParse raw)
      ((ok v) (some (jsonDedup v)))
      ((err _) none)))

fn isObj? v: (Option j/Json) -> Bool
  (mt v
    ((some x) (mt x ((j/jobj _) true) (_ false)))
    ((none) false))

fn usageRestoreApply state: j/Json saved: j/Json -> (Option j/Json)
  (let [(kvs (objKvs saved))]
    (mt saved
      ((j/jobj _)
       (if (and (isObj? (u/objGet kvs "providers")) (isObj? (u/objGet kvs "aliases")))
         (some (setField (setField (setField state "since" (optionOr (u/objGet kvs "since") (objField state "since")))
                                   "providers" (objField saved "providers"))
                         "aliases" (objField saved "aliases")))
         none))
      (_ none)))

fn ! usageRestore! path: String state: j/Json -> (Pair j/Json String)
  (mt (fileStat path)
    ((err e) (pair state (if (stringStartsWith? e "notFound") "absent" (str "unreadable: " e))))
    ((ok st)
     (if st.isDir
       (pair state (str "unreadable: " path " is a directory"))
       (mt (fileReadString path)
         ((err e) (pair state (str "unreadable: " e)))
         ((ok raw)
          (mt (usageRestoreParse raw)
            ((none) (pair state "unparsable"))
            ((some saved)
             (mt (pathRemove path)
               ((err e) (pair state (str "unlink failed: " e)))
               ((ok _)
                (mt (usageRestoreApply state saved)
                  ((some s2) (pair s2 "restored"))
                  ((none) (pair state "rejected"))))))))))))

fn wordRanges -> (List Int64)
  (list 170 170 178 179 181 181 185 186 188 190 192 214 216 246 248 705
        710 721 736 740 748 748 750 750 880 884 886 887 890 893 895 895
        902 902 904 906 908 908 910 929 931 1013 1015 1153 1162 1327 1329 1366
        1369 1369 1376 1416 1488 1514 1519 1522 1568 1610 1632 1641 1646 1647 1649 1747
        1749 1749 1765 1766 1774 1788 1791 1791 1808 1808 1810 1839 1869 1957 1969 1969
        1984 2026 2036 2037 2042 2042 2048 2069 2074 2074 2084 2084 2088 2088 2112 2136
        2144 2154 2160 2183 2185 2190 2208 2249 2308 2361 2365 2365 2384 2384 2392 2401
        2406 2415 2417 2432 2437 2444 2447 2448 2451 2472 2474 2480 2482 2482 2486 2489
        2493 2493 2510 2510 2524 2525 2527 2529 2534 2545 2548 2553 2556 2556 2565 2570
        2575 2576 2579 2600 2602 2608 2610 2611 2613 2614 2616 2617 2649 2652 2654 2654
        2662 2671 2674 2676 2693 2701 2703 2705 2707 2728 2730 2736 2738 2739 2741 2745
        2749 2749 2768 2768 2784 2785 2790 2799 2809 2809 2821 2828 2831 2832 2835 2856
        2858 2864 2866 2867 2869 2873 2877 2877 2908 2909 2911 2913 2918 2927 2929 2935
        2947 2947 2949 2954 2958 2960 2962 2965 2969 2970 2972 2972 2974 2975 2979 2980
        2984 2986 2990 3001 3024 3024 3046 3058 3077 3084 3086 3088 3090 3112 3114 3129
        3133 3133 3160 3162 3165 3165 3168 3169 3174 3183 3192 3198 3200 3200 3205 3212
        3214 3216 3218 3240 3242 3251 3253 3257 3261 3261 3293 3294 3296 3297 3302 3311
        3313 3314 3332 3340 3342 3344 3346 3386 3389 3389 3406 3406 3412 3414 3416 3425
        3430 3448 3450 3455 3461 3478 3482 3505 3507 3515 3517 3517 3520 3526 3558 3567
        3585 3632 3634 3635 3648 3654 3664 3673 3713 3714 3716 3716 3718 3722 3724 3747
        3749 3749 3751 3760 3762 3763 3773 3773 3776 3780 3782 3782 3792 3801 3804 3807
        3840 3840 3872 3891 3904 3911 3913 3948 3976 3980 4096 4138 4159 4169 4176 4181
        4186 4189 4193 4193 4197 4198 4206 4208 4213 4225 4238 4238 4240 4249 4256 4293
        4295 4295 4301 4301 4304 4346 4348 4680 4682 4685 4688 4694 4696 4696 4698 4701
        4704 4744 4746 4749 4752 4784 4786 4789 4792 4798 4800 4800 4802 4805 4808 4822
        4824 4880 4882 4885 4888 4954 4969 4988 4992 5007 5024 5109 5112 5117 5121 5740
        5743 5759 5761 5786 5792 5866 5870 5880 5888 5905 5919 5937 5952 5969 5984 5996
        5998 6000 6016 6067 6103 6103 6108 6108 6112 6121 6128 6137 6160 6169 6176 6264
        6272 6276 6279 6312 6314 6314 6320 6389 6400 6430 6470 6509 6512 6516 6528 6571
        6576 6601 6608 6618 6656 6678 6688 6740 6784 6793 6800 6809 6823 6823 6917 6963
        6981 6988 6992 7001 7043 7072 7086 7141 7168 7203 7232 7241 7245 7293 7296 7304
        7312 7354 7357 7359 7401 7404 7406 7411 7413 7414 7418 7418 7424 7615 7680 7957
        7960 7965 7968 8005 8008 8013 8016 8023 8025 8025 8027 8027 8029 8029 8031 8061
        8064 8116 8118 8124 8126 8126 8130 8132 8134 8140 8144 8147 8150 8155 8160 8172
        8178 8180 8182 8188 8304 8305 8308 8313 8319 8329 8336 8348 8450 8450 8455 8455
        8458 8467 8469 8469 8473 8477 8484 8484 8486 8486 8488 8488 8490 8493 8495 8505
        8508 8511 8517 8521 8526 8526 8528 8585 9312 9371 9450 9471 10102 10131 11264 11492
        11499 11502 11506 11507 11517 11517 11520 11557 11559 11559 11565 11565 11568 11623 11631 11631
        11648 11670 11680 11686 11688 11694 11696 11702 11704 11710 11712 11718 11720 11726 11728 11734
        11736 11742 11823 11823 12293 12295 12321 12329 12337 12341 12344 12348 12353 12438 12445 12447
        12449 12538 12540 12543 12549 12591 12593 12686 12690 12693 12704 12735 12784 12799 12832 12841
        12872 12879 12881 12895 12928 12937 12977 12991 13312 19903 19968 42124 42192 42237 42240 42508
        42512 42539 42560 42606 42623 42653 42656 42735 42775 42783 42786 42888 42891 42954 42960 42961
        42963 42963 42965 42969 42994 43009 43011 43013 43015 43018 43020 43042 43056 43061 43072 43123
        43138 43187 43216 43225 43250 43255 43259 43259 43261 43262 43264 43301 43312 43334 43360 43388
        43396 43442 43471 43481 43488 43492 43494 43518 43520 43560 43584 43586 43588 43595 43600 43609
        43616 43638 43642 43642 43646 43695 43697 43697 43701 43702 43705 43709 43712 43712 43714 43714
        43739 43741 43744 43754 43762 43764 43777 43782 43785 43790 43793 43798 43808 43814 43816 43822
        43824 43866 43868 43881 43888 44002 44016 44025 44032 55203 55216 55238 55243 55291 63744 64109
        64112 64217 64256 64262 64275 64279 64285 64285 64287 64296 64298 64310 64312 64316 64318 64318
        64320 64321 64323 64324 64326 64433 64467 64829 64848 64911 64914 64967 65008 65019 65136 65140
        65142 65276 65296 65305 65313 65338 65345 65370 65382 65470 65474 65479 65482 65487 65490 65495
        65498 65500 65536 65547 65549 65574 65576 65594 65596 65597 65599 65613 65616 65629 65664 65786
        65799 65843 65856 65912 65930 65931 66176 66204 66208 66256 66273 66299 66304 66339 66349 66378
        66384 66421 66432 66461 66464 66499 66504 66511 66513 66517 66560 66717 66720 66729 66736 66771
        66776 66811 66816 66855 66864 66915 66928 66938 66940 66954 66956 66962 66964 66965 66967 66977
        66979 66993 66995 67001 67003 67004 67072 67382 67392 67413 67424 67431 67456 67461 67463 67504
        67506 67514 67584 67589 67592 67592 67594 67637 67639 67640 67644 67644 67647 67669 67672 67702
        67705 67742 67751 67759 67808 67826 67828 67829 67835 67867 67872 67897 67968 68023 68028 68047
        68050 68096 68112 68115 68117 68119 68121 68149 68160 68168 68192 68222 68224 68255 68288 68295
        68297 68324 68331 68335 68352 68405 68416 68437 68440 68466 68472 68497 68521 68527 68608 68680
        68736 68786 68800 68850 68858 68899 68912 68921 69216 69246 69248 69289 69296 69297 69376 69415
        69424 69445 69457 69460 69488 69505 69552 69579 69600 69622 69635 69687 69714 69743 69745 69746
        69749 69749 69763 69807 69840 69864 69872 69881 69891 69926 69942 69951 69956 69956 69959 69959
        69968 70002 70006 70006 70019 70066 70081 70084 70096 70106 70108 70108 70113 70132 70144 70161
        70163 70187 70207 70208 70272 70278 70280 70280 70282 70285 70287 70301 70303 70312 70320 70366
        70384 70393 70405 70412 70415 70416 70419 70440 70442 70448 70450 70451 70453 70457 70461 70461
        70480 70480 70493 70497 70656 70708 70727 70730 70736 70745 70751 70753 70784 70831 70852 70853
        70855 70855 70864 70873 71040 71086 71128 71131 71168 71215 71236 71236 71248 71257 71296 71338
        71352 71352 71360 71369 71424 71450 71472 71483 71488 71494 71680 71723 71840 71922 71935 71942
        71945 71945 71948 71955 71957 71958 71960 71983 71999 71999 72001 72001 72016 72025 72096 72103
        72106 72144 72161 72161 72163 72163 72192 72192 72203 72242 72250 72250 72272 72272 72284 72329
        72349 72349 72368 72440 72704 72712 72714 72750 72768 72768 72784 72812 72818 72847 72960 72966
        72968 72969 72971 73008 73030 73030 73040 73049 73056 73061 73063 73064 73066 73097 73112 73112
        73120 73129 73440 73458 73474 73474 73476 73488 73490 73523 73552 73561 73648 73648 73664 73684
        73728 74649 74752 74862 74880 75075 77712 77808 77824 78895 78913 78918 82944 83526 92160 92728
        92736 92766 92768 92777 92784 92862 92864 92873 92880 92909 92928 92975 92992 92995 93008 93017
        93019 93025 93027 93047 93053 93071 93760 93846 93952 94026 94032 94032 94099 94111 94176 94177
        94179 94179 94208 100343 100352 101589 101632 101640 110576 110579 110581 110587 110589 110590 110592 110882
        110898 110898 110928 110930 110933 110933 110948 110951 110960 111355 113664 113770 113776 113788 113792 113800
        113808 113817 119488 119507 119520 119539 119648 119672 119808 119892 119894 119964 119966 119967 119970 119970
        119973 119974 119977 119980 119982 119993 119995 119995 119997 120003 120005 120069 120071 120074 120077 120084
        120086 120092 120094 120121 120123 120126 120128 120132 120134 120134 120138 120144 120146 120485 120488 120512
        120514 120538 120540 120570 120572 120596 120598 120628 120630 120654 120656 120686 120688 120712 120714 120744
        120746 120770 120772 120779 120782 120831 122624 122654 122661 122666 122928 122989 123136 123180 123191 123197
        123200 123209 123214 123214 123536 123565 123584 123627 123632 123641 124112 124139 124144 124153 124896 124902
        124904 124907 124909 124910 124912 124926 124928 125124 125127 125135 125184 125251 125259 125259 125264 125273
        126065 126123 126125 126127 126129 126132 126209 126253 126255 126269 126464 126467 126469 126495 126497 126498
        126500 126500 126503 126503 126505 126514 126516 126519 126521 126521 126523 126523 126530 126530 126535 126535
        126537 126537 126539 126539 126541 126543 126545 126546 126548 126548 126551 126551 126553 126553 126555 126555
        126557 126557 126559 126559 126561 126562 126564 126564 126567 126570 126572 126578 126580 126583 126585 126588
        126590 126590 126592 126601 126603 126619 126625 126627 126629 126633 126635 126651 127232 127244 130032 130041
        131072 173791 173824 177977 177984 178205 178208 183969 183984 191456 191472 192093 194560 195101 196608 201546
        201552 205743)

fn nfkcBadNetloc -> (List Int64)
  (list 8263 8264 8265 8448 8449 8453 8454 10868 65043 65046 65109 65110 65119 65131 65283 65295 65306 65311 65312)

fn asciiWord? cp: Int64 -> Bool
  (or (and (>= cp 48) (<= cp 57)) (or (and (>= cp 65) (<= cp 90)) (or (and (>= cp 97) (<= cp 122)) (= cp 95))))

fn isWordCp? cp: Int64 -> Bool
  (if (< cp 128) (asciiWord? cp) (u/inRanges? cp (wordRanges)))

fn isDigitCp? cp: Int64 -> Bool
  (if (< cp 128) (and (>= cp 48) (<= cp 57)) (u/inRanges? cp (u/unicodeDigitRanges)))

fn tailOf cs: (List Int64) -> (List Int64)
  (optionOr (listTail cs) (list))

fn headIs? cs: (List Int64) opts: (List Int64) -> Bool
  (mt (listHead cs)
    ((some c) (listContains? opts c))
    ((none) false))

fn skipWhile cs: (List Int64) pred: (fn [Int64] -> Bool) -> (List Int64)
  (mt (listHead cs)
    ((some c) (if (pred c) (skipWhile (tailOf cs) pred) cs))
    ((none) cs))

fn oneOrMore cs: (List Int64) pred: (fn [Int64] -> Bool) -> (Option (List Int64))
  (mt (listHead cs)
    ((some c) (if (pred c) (some (skipWhile (tailOf cs) pred)) none))
    ((none) none))

fn spaceCp? cp: Int64 -> Bool
  (u/isPySpace? cp)

fn lineWord cs: (List Int64) -> (Option (List Int64))
  (if (and (headIs? cs (list 76 108))
           (and (headIs? (tailOf cs) (list 73 105 304 305))
                (and (headIs? (tailOf (tailOf cs)) (list 78 110)) (headIs? (tailOf (tailOf (tailOf cs))) (list 69 101)))))
    (some (tailOf (tailOf (tailOf (tailOf cs)))))
    none)

fn lineThenNumber? cs: (List Int64) -> Bool
  (mt (lineWord cs)
    ((none) false)
    ((some rest)
     (mt (oneOrMore rest spaceCp?)
       ((none) false)
       ((some r2) (some? (oneOrMore r2 isDigitCp?))))))

fn lNumberWord? cs: (List Int64) -> Bool
  (and (headIs? cs (list 76 108))
       (mt (oneOrMore (tailOf cs) isDigitCp?)
         ((none) false)
         ((some rest) (mt (listHead rest) ((some c) (not (isWordCp? c))) ((none) true)))))

fn hunkHeader? cs: (List Int64) -> Bool
  (and (headIs? cs (list 64))
       (let [(r (skipWhile (tailOf cs) spaceCp?))]
         (and (headIs? r (list 45)) (some? (oneOrMore (tailOf r) isDigitCp?)))))

fn lineNumberScan prev: Int64 cs: (List Int64) -> Bool
  (mt (listHead cs)
    ((none) false)
    ((some c)
     (let [(rest (tailOf cs))
           (atL (or (= c 76) (= c 108)))]
       (cond
         ((and (= c 58) (lineThenNumber? rest)) true)
         ((and atL (and (not (isWordCp? prev)) (or (lineThenNumber? cs) (lNumberWord? cs)))) true)
         ((and (= c 64) (hunkHeader? rest)) true)
         (else (lineNumberScan c rest))))))

fn lowerLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (if (>= i n)
    (u/joinAll (listReverse (cons (u/slice s start n) acc)))
    (let [(b (bytesGet bs i))]
      (cond
        ((and (>= b 65) (<= b 90)) (lowerLoop s bs n (+ i 1) (+ i 1) (cons (u/asciiChar (+ b 32)) (cons (u/slice s start i) acc))))
        ((and (= b 226) (and (< (+ i 2) n) (and (= (bytesGet bs (+ i 1)) 132) (= (bytesGet bs (+ i 2)) 170))))
         (lowerLoop s bs n (+ i 3) (+ i 3) (cons "k" (cons (u/slice s start i) acc))))
        ((and (= b 196) (and (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 176)))
         (lowerLoop s bs n (+ i 2) (+ i 2) (cons "i\u{307}" (cons (u/slice s start i) acc))))
        (else (lowerLoop s bs n (+ i 1) start acc)))))

fn lowerForSearch s: String -> String
  (let [(bs (stringToBytes s))]
    (lowerLoop s bs (bytesLength bs) 0 0 (list)))

fn dyckLoop bs: Bytes i: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool -> Bool
  (if (>= i n)
    (= depth 0)
    (let [(b (bytesGet bs i))]
      (cond
        (esc (dyckLoop bs (+ i 1) n depth inStr false))
        ((= b 92) (dyckLoop bs (+ i 1) n depth inStr true))
        ((= b 34) (dyckLoop bs (+ i 1) n depth (not inStr) false))
        (inStr (dyckLoop bs (+ i 1) n depth inStr false))
        ((= b 40) (dyckLoop bs (+ i 1) n (+ depth 1) inStr false))
        ((= b 41) (if (< (- depth 1) 0) false (dyckLoop bs (+ i 1) n (- depth 1) inStr false)))
        (else (dyckLoop bs (+ i 1) n depth inStr false)))))

fn asciiLetter? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn letterRunLoop bs: Bytes i: Int64 n: Int64 run: Int64 -> Bool
  (cond
    ((>= run 3) true)
    ((>= i n) false)
    ((asciiLetter? (bytesGet bs i)) (letterRunLoop bs (+ i 1) n (+ run 1)))
    (else (letterRunLoop bs (+ i 1) n 0)))

fn hasPreamble? raw: String -> Bool
  (mt (stringIndexOf raw "(")
    ((some i) (if (> i 0) (letterRunLoop (stringToBytes (u/slice raw 0 i)) 0 i 0) false))
    ((none) false))

fn anyIn? hay: String needles: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringContains? hay n)) needles)

fn flagList pairs: (List (Pair Bool String)) -> String
  (str "[" (stringJoin (map (fn [(p (Pair Bool String))] -> String (str "\"" (pairSecond p) "\""))
                            (filter (fn [(p (Pair Bool String))] -> Bool (pairFirst p)) pairs)) " ") "]")

fn boolText b: Bool -> String
  (if b "true" "false")

fn noneText v: (Option String) -> String
  (optionOr v "None")

fn orText v: (Option String) fallback: String -> String
  (mt v
    ((some s) (if (stringEmpty? s) fallback s))
    ((none) fallback))

fn analyzeTelemetry content: j/Json intent: (Option String) role: (Option String) model: (Option String) workspace: (Option String) rootDir: String nowMs: Int64 -> (Option String)
  (mt content
    ((j/jstr text)
     (let [(raw (u/pyStrip text))]
       (if (stringEmpty? raw)
         none
         (let [(bs (stringToBytes raw))
               (markdown (stringContains? raw "```"))
               (preamble (hasPreamble? raw))
               (balanced (dyckLoop bs 0 (bytesLength bs) 0 false false))
               (lineNo (lineNumberScan -1 (u/codepoints raw)))
               (lower (lowerForSearch raw))
               (cheats (list (pair (anyIn? lower (list "assert true" "assert(true)" "(assert true)")) "vacuous-assert-true")
                             (pair (anyIn? lower (list "skip test" ":skip" "ignore test")) "skip-gate-evasion")
                             (pair (anyIn? lower (list "mock " "stub ")) "mock-evasion")
                             (pair (and (stringContains? lower "exit 0") (not (anyIn? lower (list "assert" "test" "eval")))) "unverified-exit-zero")))
               (debt (list (pair (anyIn? lower (list "truncated" "truncation")) "context-truncation-complaint")
                           (pair (anyIn? lower (list "cannot inspect" "cannot see" "file not found")) "missing-visibility")
                           (pair (anyIn? lower (list "need tool" "missing tool")) "missing-tool-affordance")))
               (cheating (listAny? (fn [(p (Pair Bool String))] -> Bool (pairFirst p)) cheats))
               (pure (and balanced (and (not markdown) (and (not preamble) (and (stringStartsWith? raw "(") (stringEndsWith? raw ")"))))))
               (ws (u/replaceAll (u/replaceAll (orText workspace rootDir) "\\" "\\\\") "\"" "\\\""))
               (ms (stringFromInt64 nowMs))]
           (some (str "(:telemetry :id \"TEL-" ms "\" :timestamp " ms " :intent :" (orText intent "unspecified")
                      " :role \"" (noneText role) "\" :model \"" (noneText model) "\" :workspace \"" ws "\""
                      " :pureDyck1 " (boolText pure) " :markdownWrapped " (boolText markdown) " :preamble " (boolText preamble)
                      " :lineNumberDetected " (boolText lineNo) " :cheatingSuspected " (boolText cheating)
                      " :cheatingFlags " (flagList cheats) " :harnessComplaints " (flagList debt) ")\n"))))))
    (_ none))

fn ! telemetryNowMs! -> Int64
  (optionOr (float64ToInt64 (* (/ (int64ToFloat64 (nowNs)) 1000000000.0) 1000.0)) 0)

fn leadingSlashes p: String -> Int64
  (cond
    ((not (stringStartsWith? p "/")) 0)
    ((and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) 2)
    (else 1))

fn normStep initial: Int64 acc: (List String) comp: String -> (List String)
  (cond
    ((or (= comp "") (= comp ".")) acc)
    ((= comp "..")
     (mt (listHead acc)
       ((none) (if (= initial 0) (cons ".." acc) acc))
       ((some last) (if (= last "..") (cons ".." acc) (optionOr (listTail acc) (list))))))
    (else (cons comp acc)))

fn posixNormpath p: String -> String
  (if (stringEmpty? p)
    "."
    (let [(initial (leadingSlashes p))
          (comps (listReverse (fold (fn [(acc (List String)) (c String)] -> (List String) (normStep initial acc c)) (list) (stringSplit p "/"))))
          (joined (str (stringRepeat "/" initial) (stringJoin comps "/")))]
      (if (stringEmpty? joined) "." joined)))

fn lastSlash s: String i: Int64 -> Int64
  (cond
    ((< i 0) -1)
    ((= (u/slice s i (+ i 1)) "/") i)
    (else (lastSlash s (- i 1))))

fn rstripSlashes s: String -> String
  (if (stringEndsWith? s "/") (rstripSlashes (u/slice s 0 (- (stringLength s) 1))) s)

fn posixDirname p: String -> String
  (let [(head (u/slice p 0 (+ (lastSlash p (- (stringLength p) 1)) 1)))]
    (if (and (not (stringEmpty? head)) (not (= head (stringRepeat "/" (stringLength head))))) (rstripSlashes head) head))

fn posixJoin a: String b: String -> String
  (if (or (stringEmpty? a) (stringEndsWith? a "/")) (str a b) (str a "/" b))

fn posixAbspath cwd: String p: String -> String
  (posixNormpath (if (stringStartsWith? p "/") p (posixJoin cwd p)))

fn telemetryLogPath env: (Map String String) cwd: String script: String -> String
  (let [(set (u/envGetOr env "ASL_TELEMETRY_LOG_PATH" ""))]
    (if (stringEmpty? set)
      (posixJoin (posixDirname (posixDirname (posixAbspath cwd script))) ".asl/log/mesh_telemetry.asnl")
      set))

fn ! drainFd! fd: Int64 -> (Result Bool String)
  (mt (fdRead fd 16777216)
    ((err e) (err e))
    ((ok chunk) (if (stringEmpty? chunk) (ok true) (drainFd! fd))))

fn ! writeAll! fd: Int64 text: String -> (Result Bool String)
  (if (stringEmpty? text)
    (ok true)
    (mt (fdWrite fd text)
      ((err e) (err e))
      ((ok k) (writeAll! fd (u/slice text k (stringLength text))))))

fn ! appendUnderLock! fd: Int64 text: String -> (Result Bool String)
  (mt (drainFd! fd)
    ((err e) (err e))
    ((ok _) (writeAll! fd text)))

fn ! appendFile! path: String text: String tries: Int64 -> (Result Bool String)
  (mt (fileLock path true)
    ((err e)
     (if (and (= e "busy") (> tries 0))
       (do (sleepMs 5) (appendFile! path text (- tries 1)))
       (err (str "telemetry log " path ": " e))))
    ((ok fd)
     (let [(res (appendUnderLock! fd text))
           (closed (fdClose fd))]
       (mt res
         ((err e) (err (str "telemetry log " path ": " e)))
         ((ok _) (mt closed ((ok _) (ok true)) ((err e) (err (str "telemetry log close " path ": " e)))))))))

fn ! logTelemetryEvent! path: String rec: (Option String) -> (Result Bool String)
  (mt rec
    ((none) (ok false))
    ((some text)
     (if (stringEmpty? text)
       (ok false)
       (mt (dirCreate (posixDirname path))
         ((err e) (err (str "telemetry log dir: " e)))
         ((ok _) (appendFile! path text 200))))))

fn stripC0Loop bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (<= (bytesGet bs i) 32)) (stripC0Loop bs (+ i 1) n) i)

fn dropBytesLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (u/joinAll (listReverse (cons (u/slice s start n) acc))))
    ((or (= (bytesGet bs i) 9) (or (= (bytesGet bs i) 10) (= (bytesGet bs i) 13)))
     (dropBytesLoop s bs n (+ i 1) (+ i 1) (cons (u/slice s start i) acc)))
    (else (dropBytesLoop s bs n (+ i 1) start acc)))

fn urlPrep url: String -> String
  (let [(bs (stringToBytes url))
        (a (stripC0Loop bs 0 (bytesLength bs)))
        (s (u/slice url a (bytesLength bs)))
        (bs2 (stringToBytes s))]
    (dropBytesLoop s bs2 (bytesLength bs2) 0 0 (list)))

fn schemeChar? b: Int64 -> Bool
  (or (u/inRanges? b (list 48 57 65 90 97 122)) (or (= b 43) (or (= b 45) (= b 46))))

fn bytesAllLoop bs: Bytes i: Int64 n: Int64 pred: (fn [Int64] -> Bool) -> Bool
  (cond
    ((>= i n) true)
    ((pred (bytesGet bs i)) (bytesAllLoop bs (+ i 1) n pred))
    (else false))

fn allBytes? s: String pred: (fn [Int64] -> Bool) -> Bool
  (let [(bs (stringToBytes s))]
    (bytesAllLoop bs 0 (bytesLength bs) pred))

fn splitFirst s: String sep: String -> (Pair String (Option String))
  (mt (stringIndexOf s sep)
    ((some i) (pair (u/slice s 0 i) (some (u/slice s (+ i (stringLength sep)) (stringLength s)))))
    ((none) (pair s none)))

fn netlocEnd s: String -> Int64
  (fold (fn [(best Int64) (c String)] -> Int64
          (mt (stringIndexOf s c) ((some i) (if (< i best) i best)) ((none) best)))
        (stringLength s) (list "/" "?" "#"))

fn hexDigit? b: Int64 -> Bool
  (u/inRanges? b (list 48 57 65 70 97 102))

fn asciiDigits? s: String -> Bool
  (and (not (stringEmpty? s)) (allBytes? s (fn [(b Int64)] -> Bool (and (>= b 48) (<= b 57)))))

fn octetOk? o: String -> Bool
  (and (asciiDigits? o)
       (and (<= (stringLength o) 3)
            (and (or (= o "0") (not (stringStartsWith? o "0")))
                 (<= (optionOr (stringToInt64 o) 999) 255))))

fn ipv4Valid? s: String -> Bool
  (let [(parts (stringSplit s "."))]
    (and (not (stringEmpty? s)) (and (= (listLength parts) 4) (listAll? octetOk? parts))))

fn hextetOk? h: String -> Bool
  (and (not (stringEmpty? h)) (and (<= (stringLength h) 4) (allBytes? h hexDigit?)))

fn emptyIndexes parts: (List String) -> (List Int64)
  (filter (fn [(i Int64)] -> Bool (= (optionOr (listGet parts i) "x") "")) (range 1 (- (listLength parts) 1)))

fn ipv6Parts parts: (List String) -> (Option (List String))
  (let [(n (listLength parts))
        (last (optionOr (listGet parts (- n 1)) ""))]
    (if (stringContains? last ".")
      (if (ipv4Valid? last) (some (listAppend (optionOr (listSlice parts 0 (- n 1)) (list)) (list "0" "0"))) none)
      (some parts)))

fn hextetsOk? parts: (List String) hi: Int64 lo: Int64 -> Bool
  (let [(n (listLength parts))]
    (and (listAll? hextetOk? (optionOr (listSlice parts 0 hi) (list)))
         (listAll? hextetOk? (optionOr (listSlice parts (- n lo) n) (list)))))

fn ipv6Skip parts: (List String) skip: Int64 -> Bool
  (let [(n (listLength parts))
        (first (optionOr (listHead parts) ""))
        (last (optionOr (listGet parts (- n 1)) ""))
        (hi (if (stringEmpty? first) (- skip 1) skip))
        (lo (if (stringEmpty? last) (- (- n skip) 2) (- (- n skip) 1)))]
    (cond
      ((and (stringEmpty? first) (not (= hi 0))) false)
      ((and (stringEmpty? last) (not (= lo 0))) false)
      ((< (- 8 (+ hi lo)) 1) false)
      (else (hextetsOk? parts hi lo))))

fn ipv6Valid? s: String -> Bool
  (let [(sp (splitFirst s "%"))
        (scopeOk (mt (pairSecond sp) ((some sc) (and (not (stringEmpty? sc)) (not (stringContains? sc "%")))) ((none) true)))
        (addr (pairFirst sp))
        (raw (stringSplit addr ":"))]
    (if (or (not scopeOk) (or (stringEmpty? addr) (< (listLength raw) 3)))
      false
      (mt (ipv6Parts raw)
        ((none) false)
        ((some parts)
         (let [(skips (emptyIndexes parts))
               (n (listLength parts))]
           (cond
             ((> n 9) false)
             ((> (listLength skips) 1) false)
             ((= (listLength skips) 1) (ipv6Skip parts (optionOr (listHead skips) 0)))
             ((not (= n 8)) false)
             ((stringEmpty? (optionOr (listHead parts) "")) false)
             ((stringEmpty? (optionOr (listGet parts 7) "")) false)
             (else (hextetsOk? parts 8 0))))))))

fn vFuture? h: String -> Bool
  (let [(rest (u/slice h 1 (stringLength h)))]
    (mt (stringIndexOf rest ".")
      ((none) false)
      ((some i) (and (> i 0) (and (allBytes? (u/slice rest 0 i) hexDigit?) (> (stringLength rest) (+ i 1)))))))

fn bracketedHostOk? h: String -> Bool
  (if (stringStartsWith? h "v")
    (vFuture? h)
    (and (not (ipv4Valid? h)) (ipv6Valid? h)))

fn netlocNfkcOk? netloc: String -> Bool
  (not (listAny? (fn [(cp Int64)] -> Bool (listContains? (nfkcBadNetloc) cp)) (u/codepoints netloc)))

fn usesNetloc -> (List String)
  (list "" "ftp" "http" "gopher" "nntp" "telnet" "imap" "wais" "file" "mms" "https" "shttp" "snews" "prospero" "rtsp" "rtsps" "rtspu"
        "rsync" "svn" "svn+ssh" "sftp" "nfs" "git" "git+ssh" "ws" "wss" "itms-services")

fn usesParams -> (List String)
  (list "" "ftp" "hdl" "prospero" "http" "imap" "https" "shttp" "rtsp" "rtsps" "rtspu" "sip" "sips" "mms" "sftp" "tel")

fn schemeSplit url: String -> (Pair String String)
  (mt (stringIndexOf url ":")
    ((some i)
     (if (and (> i 0) (and (asciiLetter? (bytesGet (stringToBytes url) 0)) (allBytes? (u/slice url 0 i) schemeChar?)))
       (pair (stringLower (u/slice url 0 i)) (u/slice url (+ i 1) (stringLength url)))
       (pair "" url)))
    ((none) (pair "" url)))

fn bracketsOk? netloc: String -> Bool
  (let [(open (stringContains? netloc "["))
        (close (stringContains? netloc "]"))]
    (cond
      ((and open (not close)) false)
      ((and close (not open)) false)
      ((and open close)
       (let [(after (optionOr (pairSecond (splitFirst netloc "[")) ""))]
         (bracketedHostOk? (pairFirst (splitFirst after "]")))))
      (else true)))

fn urlSplit url: String -> (Result (List String) String)
  (let [(sr (schemeSplit url))
        (rest (pairSecond sr))
        (hasNet (stringStartsWith? rest "//"))
        (afterSlashes (if hasNet (u/slice rest 2 (stringLength rest)) rest))
        (cut (if hasNet (netlocEnd afterSlashes) 0))
        (netloc (if hasNet (u/slice afterSlashes 0 cut) ""))
        (tail (if hasNet (u/slice afterSlashes cut (stringLength afterSlashes)) rest))
        (fr (splitFirst tail "#"))
        (qr (splitFirst (pairFirst fr) "?"))]
    (cond
      ((not (bracketsOk? netloc)) (err "ValueError: Invalid IPv6 URL"))
      ((not (netlocNfkcOk? netloc)) (err "ValueError: netloc contains invalid characters under NFKC normalization"))
      (else (ok (list (pairFirst sr) netloc (pairFirst qr) (optionOr (pairSecond qr) "") (optionOr (pairSecond fr) ""))))))

fn splitParams path: String -> (Pair String String)
  (let [(from (if (stringContains? path "/") (lastSlash path (- (stringLength path) 1)) 0))
        (i (mt (stringIndexOf (u/slice path from (stringLength path)) ";") ((some k) (+ from k)) ((none) -1)))]
    (if (< i 0) (pair path "") (pair (u/slice path 0 i) (u/slice path (+ i 1) (stringLength path)))))

fn hexVal b: Int64 -> Int64
  (cond
    ((<= b 57) (- b 48))
    ((<= b 70) (- b 55))
    (else (- b 87)))

fn hexPair bs: Bytes i: Int64 -> Int64
  (+ (* 16 (hexVal (bytesGet bs i))) (hexVal (bytesGet bs (+ i 1))))

fn percentLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (u/joinAll (listReverse acc)))
    ((and (= (bytesGet bs i) 37) (and (< (+ i 2) n) (and (hexDigit? (bytesGet bs (+ i 1))) (hexDigit? (bytesGet bs (+ i 2))))))
     (percentLoop s bs n (+ i 3) (cons (u/byteChar (hexPair bs (+ i 1))) acc)))
    (else (percentLoop s bs n (+ i 1) (cons (u/slice s i (+ i 1)) acc))))

fn unquoteRun run: String -> String
  (let [(bs (stringToBytes run))]
    (u/utf8Decode (percentLoop run bs (bytesLength bs) 0 (list)) "\u{fffd}"))

fn runsLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 ascii: Bool acc: (List String) -> String
  (if (>= i n)
    (let [(piece (u/slice s start n))]
      (u/joinAll (listReverse (cons (if ascii (unquoteRun piece) piece) acc))))
    (let [(isAscii (< (bytesGet bs i) 128))]
      (if (= isAscii ascii)
        (runsLoop s bs n (+ i 1) start ascii acc)
        (let [(piece (u/slice s start i))]
          (runsLoop s bs n (+ i 1) i isAscii (cons (if ascii (unquoteRun piece) piece) acc))))))

fn unquotePlus s: String -> String
  (let [(t (u/replaceAll s "+" " "))]
    (if (not (stringContains? t "%"))
      t
      (let [(bs (stringToBytes t))]
        (runsLoop t bs (bytesLength bs) 0 0 true (list)))))

fn quoteLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (if (>= i n)
    (u/joinAll (listReverse acc))
    (let [(b (bytesGet bs i))]
      (cond
        ((or (u/inRanges? b (list 48 57 65 90 97 122)) (or (= b 95) (or (= b 46) (or (= b 45) (= b 126)))))
         (quoteLoop s bs n (+ i 1) (cons (u/slice s i (+ i 1)) acc)))
        ((= b 32) (quoteLoop s bs n (+ i 1) (cons "+" acc)))
        (else (quoteLoop s bs n (+ i 1) (cons (str "%" (stringUpper (hexByte b))) acc))))))

fn quotePlus s: String -> String
  (let [(bs (stringToBytes s))]
    (quoteLoop s bs (bytesLength bs) 0 (list)))

fn cleanQuery q: String -> String
  (let [(fields (filter (fn [(f String)] -> Bool (not (stringEmpty? f))) (stringSplit q "&")))
        (pairs (fold (fn [(acc (List (Pair String String))) (f String)] -> (List (Pair String String))
                       (let [(kv (splitFirst f "="))
                             (v (optionOr (pairSecond kv) ""))]
                         (if (stringEmpty? v) acc (listAppend acc (list (pair (unquotePlus (pairFirst kv)) (unquotePlus v)))))))
                     (list) fields))
        (kept (filter (fn [(p (Pair String String))] -> Bool
                        (not (or (stringStartsWith? (pairFirst p) "utm_") (listContains? (list "ref" "fbclid" "gclid") (pairFirst p)))))
                      pairs))]
    (stringJoin (map (fn [(p (Pair String String))] -> String (str (quotePlus (pairFirst p)) "=" (quotePlus (pairSecond p)))) kept) "&"))

fn urlUnparse scheme: String netloc: String path: String params: String query: String fragment: String -> String
  (let [(p1 (if (stringEmpty? params) path (str path ";" params)))
        (p2 (cond
              ((not (stringEmpty? netloc)) (str "//" netloc (if (and (not (stringEmpty? p1)) (not (stringStartsWith? p1 "/"))) (str "/" p1) p1)))
              ((stringStartsWith? p1 "//") (str "//" p1))
              ((and (not (stringEmpty? scheme)) (and (listContains? (usesNetloc) scheme) (or (stringEmpty? p1) (stringStartsWith? p1 "/")))) (str "//" p1))
              (else p1)))
        (p3 (if (stringEmpty? scheme) p2 (str scheme ":" p2)))
        (p4 (if (stringEmpty? query) p3 (str p3 "?" query)))]
    (if (stringEmpty? fragment) p4 (str p4 "#" fragment)))

fn cleanUrl url: String -> String
  (mt (urlSplit (urlPrep url))
    ((err _) url)
    ((ok parts)
     (let [(scheme (nth parts 0))
           (path (nth parts 2))
           (pp (if (and (listContains? (usesParams) scheme) (stringContains? path ";")) (splitParams path) (pair path "")))]
       (urlUnparse scheme (nth parts 1) (pairFirst pp) (pairSecond pp) (cleanQuery (nth parts 3)) (nth parts 4)))))

fn linesLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (if (< start n) (cons (u/slice s start n) acc) acc)))
    ((= (bytesGet bs i) 10) (linesLoop s bs n (+ i 1) (+ i 1) (cons (u/slice s start i) acc)))
    ((= (bytesGet bs i) 13)
     (let [(skip (if (and (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 10)) 2 1))]
       (linesLoop s bs n (+ i skip) (+ i skip) (cons (u/slice s start i) acc))))
    (else (linesLoop s bs n (+ i 1) start acc)))

fn universalLines s: String -> (List String)
  (let [(bs (stringToBytes s))]
    (linesLoop s bs (bytesLength bs) 0 0 (list)))

fn quoteByte? b: Int64 -> Bool
  (or (= b 39) (= b 34))

fn stripQuotes s: String -> String
  (let [(bs (stringToBytes s))
        (n (bytesLength bs))]
    (cond
      ((= n 0) s)
      ((quoteByte? (bytesGet bs 0)) (stripQuotes (u/slice s 1 n)))
      ((quoteByte? (bytesGet bs (- n 1))) (stripQuotes (u/slice s 0 (- n 1))))
      (else s)))

fn zshLine line: String -> (Option (Pair String String))
  (let [(l1 (u/pyStrip line))
        (l2 (if (stringStartsWith? l1 "export ") (u/pyStrip (u/slice l1 7 (stringLength l1))) l1))]
    (if (and (stringContains? l2 "=") (not (stringStartsWith? l2 "#")))
      (let [(kv (splitFirst l2 "="))]
        (some (pair (u/pyStrip (pairFirst kv)) (stripQuotes (u/pyStrip (optionOr (pairSecond kv) ""))))))
      none))

fn zshLoop lines: (List String) env: (Map String String) -> (Result (Map String String) (Pair (Map String String) String))
  (mt (listHead lines)
    ((none) (ok env))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))]
       (mt (zshLine line)
         ((none) (zshLoop rest env))
         ((some kv)
          (let [(k (pairFirst kv))
                (v (pairSecond kv))]
            (cond
              ((or (stringEmpty? k) (some? (mapGet env k))) (zshLoop rest env))
              ((or (stringContains? k "\x00") (stringContains? v "\x00")) (err (pair env (str "embedded null byte in " k))))
              (else (zshLoop rest (mapSet env k v))))))))))

fn loadZshEnvText env: (Map String String) raw: String -> (Result (Map String String) (Pair (Map String String) String))
  (zshLoop (universalLines (u/utf8Decode raw "")) env)

fn ! zshFile! env: (Map String String) path: String errs: (List String) -> (Pair (Map String String) (List String))
  (mt (fileStat path)
    ((err _) (pair env errs))
    ((ok st)
     (if (not st.isFile)
       (pair env errs)
       (mt (fileReadString path)
         ((err e) (pair env (listAppend errs (list (str path ": " e)))))
         ((ok raw)
          (mt (loadZshEnvText env raw)
            ((ok env2) (pair env2 errs))
            ((err p) (pair (pairFirst p) (listAppend errs (list (str path ": " (pairSecond p))))))))))))

fn expandHome env: (Map String String) name: String -> (Option String)
  (mt (mapGet env "HOME")
    ((some h) (some (str (rstripSlashes h) name)))
    ((none) none))

fn ! loadZshEnv! env: (Map String String) -> (Pair (Map String String) (List String))
  (mt (expandHome env "/.zshenv")
    ((none) (pair env (list "HOME is unset: ~/.zshenv and ~/.zshrc cannot be located")))
    ((some zshenv)
     (let [(first (zshFile! env zshenv (list)))]
       (zshFile! (pairFirst first) (optionOr (expandHome env "/.zshrc") "") (pairSecond first)))))

fn ! gatewayFileVersion! path: String -> String
  (if (stringEmpty? path)
    "absent"
    (mt (fileStat path)
      ((err _) "absent")
      ((ok st)
       (if st.isDir
         "absent"
         (mt (fileReadBytes path)
           ((ok b) (u/slice (bytesSha256 b) 0 12))
           ((err _) "absent"))))))

fn gatewayUpdateStatus pid: Int64 version: String disk: String inFlight: Int64 draining: Bool updates: Int64 updatedFrom: String diskValid: (fn [String] -> Bool) -> GatewayStatus
  (GatewayStatus :pid pid :version version :diskVersion disk :stale (not (= disk version))
                 :diskValid (and (not (= disk "absent")) (diskValid disk))
                 :updates updates :updatedFrom updatedFrom :inFlight (max (- inFlight 1) 0) :draining draining)

fn gatewayStatusJson st: GatewayStatus -> j/Json
  (j/jobj (list (pair "pid" (j/jint st.pid)) (pair "version" (j/jstr st.version)) (pair "diskVersion" (j/jstr st.diskVersion))
                (pair "stale" (j/jbool st.stale)) (pair "diskValid" (j/jbool st.diskValid)) (pair "updates" (j/jint st.updates))
                (pair "updatedFrom" (j/jstr st.updatedFrom)) (pair "inFlight" (j/jint st.inFlight)) (pair "draining" (j/jbool st.draining))))

fn gatewayUpdateAsn st: GatewayStatus -> String
  (str ":pid " (stringFromInt64 st.pid) " :version " (asnStr st.version) " :diskVersion " (asnStr st.diskVersion)
       " :stale " (boolText st.stale) " :diskValid " (boolText st.diskValid) " :updates " (stringFromInt64 st.updates)
       " :updatedFrom " (asnStr st.updatedFrom) " :inFlight " (stringFromInt64 st.inFlight) " :draining " (boolText st.draining))
