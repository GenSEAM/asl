(module asl/agentLoop/providers
  :x [ProviderError providerError valueError fileMissing toolAbsent cliTimeout ioError errorCode errorMessage
      ProviderEnv VendorConfig Provider ScriptStep ScriptData scriptProvider scriptFixtureProvider replayProvider vendorProvider Timing TurnMeta Turn emptyMeta
      pyStrip pyRepr pyReprString pyStr pyJsonDumps universalNewlines
      parseAsnReply asnNumbers servedFields isLoopback parseScriptTurns parseReplayLines testBackendPrefixes gatewayModelIds!
      curlConfig parseCurlResponse tempDir! freshDir! buildDryRunInfo! providerEnv! makeProvider! nextTurn! advise! review! providerName vendorName splitContext cleanup!]
  :i [(asl-json/json :a j) (asl-proc/coreProcess :a cp) (aslGateway/server :a gs) (aslGateway/dispatch :a gd) (aslGateway/upstream :a gu)])

enum ProviderError
  (providerError code: String message: String)
  (valueError message: String)
  (fileMissing message: String)
  (toolAbsent tool: String message: String)
  (cliTimeout argv: (List String) seconds: Int64)
  (ioError message: String)

(schema ProviderEnv
  (:f gatewayUrl String)
  (:f inProcess Bool)
  (:f profile String)
  (:f gatewayConfig String)
  (:f tmpDir String)
  (:f childEnv (Map String String)))

(schema VendorConfig
  (:f vendor String)
  (:f mode String)
  (:f rootDir String)
  (:f model String)
  (:f timeout Int64)
  (:f queueTimeout Int64)
  (:f sessionId String)
  (:f intent String)
  (:f timeoutSet Bool)
  (:f env ProviderEnv)
  (:f link (Option gs/GatewayLoop)))

enum Provider
  (scriptProvider name: String turns: (List String) index: Int64)
  (scriptFixtureProvider name: String fixture: ScriptData index: Int64)
  (replayProvider name: String rootDir: String turns: (List String) index: Int64 vendor: String)
  (vendorProvider cfg: VendorConfig)

(schema ScriptStep
  (:f num Int64)
  (:f reply (Option String))
  (:f error (Option String))
  (:f usage (Option (List (Pair String j/Json)))))

(schema ScriptData
  (:f turns (List ScriptStep))
  (:f advisor (Option String))
  (:f reviewer (Option String))
  (:f attemptLogPath (Option String)))

(schema Timing
  (:f queueWaitSec Float64)
  (:f execSec Float64))

(schema TurnMeta
  (:f timing (Option Timing))
  (:f usage (Option (List (Pair String j/Json))))
  (:f served (Option (List (Pair String String))))
  (:f finish (Option String))
  (:f truncated Bool))

(schema Turn
  (:f provider Provider)
  (:f reply (Result (Option String) ProviderError))
  (:f meta TurnMeta))

fn emptyMeta -> TurnMeta
  (TurnMeta :timing none :usage none :served none :finish none :truncated false)

fn errorCode e: ProviderError -> String
  (mt e
    ((providerError c _) c)
    ((valueError _) "ERR_VALUE")
    ((fileMissing _) "ERR_NOT_FOUND")
    ((toolAbsent _ _) "ERR_TOOL_ABSENT")
    ((cliTimeout _ _) "ERR_TIMEOUT")
    ((ioError _) "ERR_IO"))

fn errorMessage e: ProviderError -> String
  (mt e
    ((providerError _ m) m)
    ((valueError m) m)
    ((fileMissing m) m)
    ((toolAbsent _ m) m)
    ((cliTimeout argv secs) (str "Command '" (pyRepr (j/jarr (map (fn [a] (j/jstr a)) argv))) "' timed out after " (stringFromInt64 secs) " seconds"))
    ((ioError m) m))

fn gatewayError code: String message: String hint: String -> ProviderError
  (providerError code
    (cond
      ((stringEmpty? hint) message)
      ((stringEmpty? message) (str code ": run " hint))
      ((stringContains? message hint) message)
      (else (str message " (hint: " hint ")"))))

fn sub s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn isPySpace b: Int64 -> Bool
  (or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32)))

fn isDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isAlphaByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn isWordByte b: Int64 -> Bool
  (or (isAlphaByte b) (or (isDigitByte b) (= b 95)))

fn runWhile bs: Bytes n: Int64 i: Int64 test: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (test (bytesGet bs i))) (runWhile bs n (+ i 1) test) i)

fn runBackWhile bs: Bytes lo: Int64 j: Int64 test: (fn [Int64] -> Bool) -> Int64
  (if (and (> j lo) (test (bytesGet bs (- j 1)))) (runBackWhile bs lo (- j 1) test) j)

fn pyStrip s: String -> String
  (let [(bs (stringToBytes s))
        (n (bytesLength bs))
        (i (runWhile bs n 0 isPySpace))]
    (sub s i (runBackWhile bs i n isPySpace)))

fn pyLstrip s: String -> String
  (let [(bs (stringToBytes s))]
    (sub s (runWhile bs (bytesLength bs) 0 isPySpace) (bytesLength bs)))

fn universalNewlines s: String -> String
  (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n")

fn indexFrom s: String t: String i: Int64 -> (Option Int64)
  (mt (stringIndexOf (sub s i (stringLength s)) t)
    ((some k) (some (+ i k)))
    (none none))

fn charIndex bs: Bytes i: Int64 k: Int64 acc: Int64 -> Int64
  (if (>= k i) acc
    (let [(b (bytesGet bs k))]
      (charIndex bs i (+ k 1) (if (and (>= b 128) (< b 192)) acc (+ acc 1)))))

fn dictPut kv: (List (Pair String T)) k: String v: T -> (List (Pair String T))
  (if (listAny? (fn [p] (= (pairFirst p) k)) kv)
    (map (fn [p] (if (= (pairFirst p) k) (pair k v) p)) kv)
    (listAppend kv (list (pair k v))))

fn groupLast xs: (List (Pair Int64 (Pair String T))) acc: (List (Pair Int64 (Pair String T))) -> (List (Pair Int64 (Pair String T)))
  (mt (listHead xs)
    (none (listReverse acc))
    ((some x)
      (mt (listHead acc)
        ((some a) (if (= (pairFirst (pairSecond a)) (pairFirst (pairSecond x)))
                    (groupLast (listDrop xs 1) (cons (pair (pairFirst a) (pairSecond x)) (listDrop acc 1)))
                    (groupLast (listDrop xs 1) (cons x acc))))
        (none (groupLast (listDrop xs 1) (cons x acc))))))

fn dictFromPairs ps: (List (Pair String T)) -> (List (Pair String T))
  (let [(indexed (listReverse (pairSecond (fold (fn [acc p] (pair (+ (pairFirst acc) 1) (cons (pair (pairFirst acc) p) (pairSecond acc)))) (pair 0 (list)) ps))))
        (byKey (listSortBy (fn [ip] (pairFirst (pairSecond ip))) indexed))]
    (map pairSecond (listSortBy pairFirst (groupLast byKey (list)))))

fn dictGet kv: (List (Pair String T)) k: String -> (Option T)
  (mt (listHead (filter (fn [p] (= (pairFirst p) k)) kv))
    ((some p) (some (pairSecond p)))
    (none none))

fn hexDigit d: Int64 -> String
  (sub "0123456789abcdef" d (+ d 1))

fn hexPad v: Int64 width: Int64 acc: String -> String
  (if (<= width 0) acc (hexPad (/ v 16) (- width 1) (str (hexDigit (mod v 16)) acc)))

fn utf8At bs: Bytes n: Int64 i: Int64 -> (Pair Int64 Int64)
  (let [(b (bytesGet bs i))
        (cont (fn [k] (and (< k n) (let [(c (bytesGet bs k))] (and (>= c 128) (< c 192))))))
        (low (fn [k] (mod (bytesGet bs k) 64)))]
    (cond
      ((< b 128) (pair b 1))
      ((and (>= b 194) (and (< b 224) (cont (+ i 1)))) (pair (+ (* (mod b 32) 64) (low (+ i 1))) 2))
      ((and (>= b 224) (and (< b 240) (and (cont (+ i 1)) (cont (+ i 2)))))
        (pair (+ (* (mod b 16) 4096) (+ (* (low (+ i 1)) 64) (low (+ i 2)))) 3))
      ((and (>= b 240) (and (< b 245) (and (cont (+ i 1)) (and (cont (+ i 2)) (cont (+ i 3))))))
        (pair (+ (* (mod b 8) 262144) (+ (* (low (+ i 1)) 4096) (+ (* (low (+ i 2)) 64) (low (+ i 3))))) 4))
      (else (pair 65533 1))))

fn isUnprintable cp: Int64 -> Bool
  (or (< cp 32)
    (or (and (>= cp 127) (<= cp 160))
      (or (= cp 173)
        (or (= cp 5760)
          (or (and (>= cp 8192) (<= cp 8207))
            (or (and (>= cp 8232) (<= cp 8239))
              (or (and (>= cp 8287) (<= cp 8292)) (or (= cp 12288) (= cp 65279)))))))))

fn reprEscape cp: Int64 -> String
  (cond
    ((< cp 256) (str "\\x" (hexPad cp 2 "")))
    ((< cp 65536) (str "\\u" (hexPad cp 4 "")))
    (else (str "\\U" (hexPad cp 8 ""))))

fn reprLoop s: String bs: Bytes n: Int64 i: Int64 quote: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(u (utf8At bs n i))
          (cp (pairFirst u))
          (w (pairSecond u))
          (piece (cond
                   ((= cp 92) "\\\\")
                   ((= cp quote) (if (= quote 39) "\\'" "\\\""))
                   ((= cp 10) "\\n")
                   ((= cp 13) "\\r")
                   ((= cp 9) "\\t")
                   ((isUnprintable cp) (reprEscape cp))
                   (else (sub s i (+ i w)))))]
      (reprLoop s bs n (+ i w) quote (cons piece acc))))

fn pyReprString s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) 34 39))
        (bs (stringToBytes s))
        (qs (if (= q 39) "'" "\""))]
    (str qs (reprLoop s bs (bytesLength bs) 0 q (list)) qs))

fn bytesReprLoop bs: Bytes n: Int64 i: Int64 quote: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))
          (piece (cond
                   ((= b 92) "\\\\")
                   ((= b quote) (if (= quote 39) "\\'" "\\\""))
                   ((= b 10) "\\n")
                   ((= b 13) "\\r")
                   ((= b 9) "\\t")
                   ((or (< b 32) (>= b 127)) (str "\\x" (hexPad b 2 "")))
                   (else (sub "                                 !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" b (+ b 1)))))]
      (bytesReprLoop bs n (+ i 1) quote (cons piece acc))))

fn pyReprBytes s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) 34 39))
        (qs (if (= q 39) "'" "\""))
        (bs (stringToBytes s))]
    (str "b" qs (bytesReprLoop bs (bytesLength bs) 0 q (list)) qs))

fn pyRepr v: j/Json -> String
  (mt v
    ((j/jnull) "None")
    ((j/jbool b) (if b "True" "False"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum f) (stringFromFloat64 f))
    ((j/jstr s) (pyReprString s))
    ((j/jarr xs) (str "[" (stringJoin (map pyRepr xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (stringJoin (map (fn [p] (str (pyReprString (pairFirst p)) ": " (pyRepr (pairSecond p)))) kvs) ", ") "}")))

fn pyStr v: j/Json -> String
  (mt v
    ((j/jstr s) s)
    (_ (pyRepr v)))

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

fn jsonEscape cp: Int64 -> String
  (cond
    ((= cp 34) "\\\"")
    ((= cp 92) "\\\\")
    ((= cp 10) "\\n")
    ((= cp 13) "\\r")
    ((= cp 9) "\\t")
    ((= cp 8) "\\b")
    ((= cp 12) "\\f")
    ((< cp 65536) (str "\\u" (hexPad cp 4 "")))
    (else (let [(v (- cp 65536))]
            (str "\\u" (hexPad (+ 55296 (/ v 1024)) 4 "") "\\u" (hexPad (+ 56320 (mod v 1024)) 4 "")))))

fn jsonStrLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse (cons (sub s start n) acc)) "")
    (let [(u (utf8At bs n i))
          (cp (pairFirst u))
          (w (pairSecond u))]
      (if (or (< cp 32) (or (>= cp 127) (or (= cp 34) (= cp 92))))
        (jsonStrLoop s bs n (+ i w) (+ i w) (cons (jsonEscape cp) (cons (sub s start i) acc)))
        (jsonStrLoop s bs n (+ i w) start acc))))

fn jsonString s: String -> String
  (let [(bs (stringToBytes s))]
    (str "\"" (jsonStrLoop s bs (bytesLength bs) 0 0 (list)) "\""))

fn jsonFloat f: Float64 -> String
  (let [(t (stringFromFloat64 f))]
    (cond ((= t "inf") "Infinity") ((= t "-inf") "-Infinity") ((= t "nan") "NaN") (else t)))

fn pyJsonDumps v: j/Json -> String
  (mt v
    ((j/jnull) "null")
    ((j/jbool b) (if b "true" "false"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (jsonFloat f))
    ((j/jnum f) (jsonFloat f))
    ((j/jstr s) (jsonString s))
    ((j/jarr xs) (str "[" (stringJoin (map pyJsonDumps xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (stringJoin (map (fn [p] (str (jsonString (pairFirst p)) ": " (pyJsonDumps (pairSecond p)))) kvs) ", ") "}")))

fn jsonLookup v: j/Json k: String -> (Option j/Json)
  (mt v
    ((j/jobj kvs) (listLast (map pairSecond (filter (fn [p] (= (pairFirst p) k)) kvs))))
    (_ none))

fn jsonDict v: j/Json -> (List (Pair String j/Json))
  (mt v
    ((j/jobj kvs) (dictFromPairs kvs))
    (_ (list)))

fn isObject v: j/Json -> Bool
  (mt v ((j/jobj _) true) (_ false))

fn asnStringEnd bs: Bytes n: Int64 j: Int64 -> (Result Int64 String)
  (cond
    ((>= j n) (err "unterminated string"))
    ((= (bytesGet bs j) 92) (asnStringEnd bs n (+ j 2)))
    ((= (bytesGet bs j) 34) (ok (+ j 1)))
    (else (asnStringEnd bs n (+ j 1))))

fn asnFormEnd bs: Bytes n: Int64 j: Int64 depth: Int64 -> (Result Int64 String)
  (if (>= j n)
    (err "unbalanced form")
    (let [(c (bytesGet bs j))]
      (cond
        ((= c 34) (mt (asnStringEnd bs n (+ j 1)) ((ok k) (asnFormEnd bs n k depth)) ((err e) (err e))))
        ((= c 40) (asnFormEnd bs n (+ j 1) (+ depth 1)))
        ((= c 41) (if (= depth 1) (ok (+ j 1)) (asnFormEnd bs n (+ j 1) (- depth 1))))
        (else (asnFormEnd bs n (+ j 1) depth)))))

fn isAtomByte b: Int64 -> Bool
  (not (or (isPySpace b) (or (= b 40) (= b 41))))

fn asnValueEnd bs: Bytes n: Int64 i: Int64 -> (Result Int64 String)
  (let [(c (bytesGet bs i))]
    (cond
      ((= c 34) (asnStringEnd bs n (+ i 1)))
      ((= c 40) (asnFormEnd bs n i 0))
      (else (ok (runWhile bs n i isAtomByte)))))

fn unescapeLoop s: String bs: Bytes n: Int64 j: Int64 start: Int64 acc: (List String) -> String
  (cond
    ((>= j n) (stringJoin (listReverse (cons (sub s start n) acc)) ""))
    ((and (= (bytesGet bs j) 92) (< (+ j 1) n))
      (let [(c (bytesGet bs (+ j 1)))
            (rep (cond ((= c 110) "\n") ((= c 114) "\r") ((= c 116) "\t") (else (sub s (+ j 1) (+ j 2)))))]
        (unescapeLoop s bs n (+ j 2) (+ j 2) (cons rep (cons (sub s start j) acc)))))
    (else (unescapeLoop s bs n (+ j 1) start acc)))

fn asnUnescape body: String -> String
  (let [(bs (stringToBytes body))]
    (unescapeLoop body bs (bytesLength bs) 0 0 (list)))

fn fieldsLoop s: String bs: Bytes n: Int64 i: Int64 fields: (List (Pair String String)) -> (Result (List (Pair String String)) String)
  (let [(i1 (runWhile bs n i isPySpace))]
    (cond
      ((>= i1 (- n 1)) (ok (dictFromPairs (listReverse fields))))
      ((!= (bytesGet bs i1) 58) (err (str "expected a keyword at offset " (stringFromInt64 (charIndex bs i1 0 0)))))
      (else
        (mt (asnValueEnd bs n i1)
          ((err e) (err e))
          ((ok keyEnd)
            (let [(key (sub s (+ i1 1) keyEnd))
                  (i2 (runWhile bs n keyEnd isPySpace))]
              (if (>= i2 (- n 1))
                (err (str "keyword :" key " has no value"))
                (mt (asnValueEnd bs n i2)
                  ((err e) (err e))
                  ((ok valEnd)
                    (let [(raw (sub s i2 valEnd))
                          (v (if (stringStartsWith? raw "\"") (asnUnescape (sub raw 1 (- (stringLength raw) 1))) raw))]
                      (fieldsLoop s bs n valEnd (cons (pair key v) fields))))))))))))

fn parseAsnReply text: String -> (Result (Pair String (List (Pair String String))) String)
  (let [(s (pyStrip text))
        (bs (stringToBytes s))
        (n (bytesLength bs))]
    (if (not (stringStartsWith? s "(:"))
      (err "not an ASN form")
      (mt (asnValueEnd bs n 0)
        ((err e) (err e))
        ((ok whole)
          (if (!= whole n)
            (err "trailing text after the form")
            (mt (asnValueEnd bs n 2)
              ((err e) (err e))
              ((ok headEnd)
                (mt (fieldsLoop s bs n headEnd (list))
                  ((err e) (err e))
                  ((ok fields) (ok (pair (sub s 2 headEnd) fields)))))))))))

fn isNumByte b: Int64 -> Bool
  (or (isDigitByte b) (= b 46))

fn floatValue v: String -> (Result j/Json ProviderError)
  (mt (stringToFloat64 v)
    ((some f) (ok (j/jfloat f)))
    ((none) (err (valueError (str "could not convert string to float: " (pyReprString v))))))

fn numberValue v: String -> (Result j/Json ProviderError)
  (if (stringContains? v ".")
    (if (> (stringCountChar v ".") 1)
      (err (valueError (str "could not convert string to float: " (pyReprString v))))
      (floatValue v))
    (mt (stringToInt64 v)
      ((some i) (ok (j/jint i)))
      (none (floatValue v))))

fn numbersLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List (Pair String j/Json)) -> (Result (List (Pair String j/Json)) ProviderError)
  (cond
    ((>= i n) (ok (dictFromPairs (listReverse acc))))
    ((!= (bytesGet bs i) 58) (numbersLoop s bs n (+ i 1) acc))
    (else
      (let [(k1 (runWhile bs n (+ i 1) isWordByte))
            (w1 (runWhile bs n k1 isPySpace))
            (d0 (if (and (< w1 n) (= (bytesGet bs w1) 45)) (+ w1 1) w1))]
        (if (or (= k1 (+ i 1)) (or (= w1 k1) (not (and (< d0 n) (isDigitByte (bytesGet bs d0))))))
          (numbersLoop s bs n (+ i 1) acc)
          (let [(e (runWhile bs n (+ d0 1) isNumByte))]
            (mt (numberValue (sub s w1 e))
              ((err x) (err x))
              ((ok num) (numbersLoop s bs n e (cons (pair (sub s (+ i 1) k1) num) acc)))))))))

fn asnNumbers form: String -> (Result (List (Pair String j/Json)) ProviderError)
  (let [(bs (stringToBytes form))]
    (numbersLoop form bs (bytesLength bs) 0 (list)))

fn servedFields fields: (List (Pair String j/Json)) -> (Option (List (Pair String String)))
  (let [(keep (fn [k] (mt (dictGet fields k)
                        ((some v) (mt v ((j/jnull) false) ((j/jstr s) (not (stringEmpty? s))) (_ true)))
                        (none false))))
        (out (map (fn [k] (pair k (pyStr (optionOr (dictGet fields k) (j/jnull)))))
                  (filter keep (list "alias" "model" "effort" "temperature"))))]
    (if (or (some? (dictGet out "alias")) (some? (dictGet out "model"))) (some out) none))

fn isSchemeByte b: Int64 -> Bool
  (or (isAlphaByte b) (or (isDigitByte b) (or (= b 43) (or (= b 45) (= b 46)))))

fn dropUnsafe s: String -> String
  (stringReplace (stringReplace (stringReplace s "\t" "") "\r" "") "\n" "")

fn firstOfAny s: String i: Int64 -> Int64
  (let [(bs (stringToBytes s))]
    (runWhile bs (bytesLength bs) i (fn [b] (not (or (= b 47) (or (= b 63) (= b 35)))))))

fn urlHostname url: String -> (Result String String)
  (let [(u0 (dropUnsafe url))
        (b0 (stringToBytes u0))
        (u (sub u0 (runWhile b0 (bytesLength b0) 0 (fn [b] (<= b 32))) (stringLength u0)))
        (bs (stringToBytes u))
        (n (bytesLength bs))
        (colon (optionOr (stringIndexOf u ":") -1))
        (hasScheme (and (> colon 0) (and (isAlphaByte (bytesGet bs 0)) (= (runWhile bs n 0 isSchemeByte) colon))))
        (rest (if hasScheme (sub u (+ colon 1) n) u))
        (netloc (if (stringStartsWith? rest "//") (sub rest 2 (firstOfAny rest 2)) ""))
        (opens (stringContains? netloc "["))
        (closes (stringContains? netloc "]"))]
    (if (!= opens closes)
      (err "Invalid IPv6 URL")
      (let [(hostinfo (mt (listLast (stringSplit netloc "@")) ((some h) h) (none netloc)))
            (host (if (stringContains? hostinfo "[")
                    (let [(br (sub hostinfo (+ (optionOr (stringIndexOf hostinfo "[") 0) 1) (stringLength hostinfo)))]
                      (sub br 0 (optionOr (stringIndexOf br "]") (stringLength br))))
                    (sub hostinfo 0 (optionOr (stringIndexOf hostinfo ":") (stringLength hostinfo)))))]
        (ok (stringLower host)))))

fn isLoopback url: String -> Bool
  (mt (urlHostname url)
    ((ok h) (or (= h "127.0.0.1") (or (= h "localhost") (or (= h "::1") (stringStartsWith? h "127.")))))
    ((err _) false))

fn quotedBodyEnd bs: Bytes n: Int64 j: Int64 -> (Option Int64)
  (cond
    ((>= j n) none)
    ((= (bytesGet bs j) 34) (some j))
    ((= (bytesGet bs j) 92) (if (and (< (+ j 1) n) (!= (bytesGet bs (+ j 1)) 10)) (quotedBodyEnd bs n (+ j 2)) none))
    (else (quotedBodyEnd bs n (+ j 1))))

fn literalAt s: String i: Int64 t: String -> Bool
  (= (sub s i (+ i (stringLength t))) t)

fn spacesThen s: String bs: Bytes n: Int64 i: Int64 t: String -> (Option Int64)
  (let [(k (runWhile bs n i isPySpace))]
    (if (and (> k i) (literalAt s k t)) (some (+ k (stringLength t))) none))

fn regexUnescape body: String -> String
  (stringReplace (stringReplace (stringReplace body "\\\"" "\"") "\\\\" "\\") "\\n" "\n")

fn matchTurn s: String bs: Bytes n: Int64 p: Int64 -> (Option (Pair Int64 (Pair Int64 String)))
  (mt (spacesThen s bs n (+ p 5) ":num")
    (none none)
    ((some a)
      (let [(w (runWhile bs n a isPySpace))
            (d (runWhile bs n w isDigitByte))]
        (if (or (= w a) (= d w))
          none
          (mt (spacesThen s bs n d ":reply")
            (none none)
            ((some r)
              (mt (spacesThen s bs n r "\"")
                (none none)
                ((some q)
                  (mt (quotedBodyEnd bs n q)
                    (none none)
                    ((some e) (some (pair (optionOr (stringToInt64 (sub s w d)) 9223372036854775807) (pair (+ e 1) (sub s q e))))))))))))))

fn turnsLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (mt (indexFrom s ":turn" i)
    (none (listReverse acc))
    ((some p)
      (mt (matchTurn s bs n p)
        (none (turnsLoop s bs n (+ p 1) acc))
        ((some m) (turnsLoop s bs n (pairFirst (pairSecond m)) (cons (pair (pairFirst m) (regexUnescape (pairSecond (pairSecond m)))) acc))))))

fn parseScriptTurns text: String -> (List String)
  (let [(bs (stringToBytes text))]
    (map pairSecond (listSortBy pairFirst (turnsLoop text bs (bytesLength bs) 0 (list)))))

fn fixtureField text: String key: String from: Int64 limit: Int64 -> (Option String)
  (if (>= from limit)
    none
    (mt (indexFrom text key from)
      (none none)
      ((some p)
        (if (>= (+ p (stringLength key)) limit)
          none
          (let [(bs (stringToBytes text))
                (n (bytesLength bs))
                (v (runWhile bs n (+ p (stringLength key)) isPySpace))]
            (if (>= v limit)
              none
              (if (= (bytesGet bs v) 34)
                (mt (quotedBodyEnd bs limit (+ v 1))
                  (none none)
                  ((some e) (some (regexUnescape (sub text (+ v 1) e)))))
                (let [(e (runWhile bs limit v (fn [i] (and (not (isPySpace (bytesGet bs i)))
                                                         (and (!= (bytesGet bs i) 40) (!= (bytesGet bs i) 41))))))]
                  (if (= e v) none (some (sub text v e)))))))))))

fn fixtureUsage text: String start: Int64 limit: Int64 -> (Option (List (Pair String j/Json)))
  (let [(input (fixtureField text ":inputTokens" start limit))
        (cached (fixtureField text ":cachedTokens" start limit))
        (output (fixtureField text ":outputTokens" start limit))]
    (if (and (some? input) (and (some? cached) (some? output)))
      (some (list (pair "inputTokens" (j/jint (optionOr (stringToInt64 (optionOr input "0")) 0)))
                  (pair "cachedTokens" (j/jint (optionOr (stringToInt64 (optionOr cached "0")) 0)))
                  (pair "outputTokens" (j/jint (optionOr (stringToInt64 (optionOr output "0")) 0)))))
      none))

fn fixtureSteps text: String bs: Bytes n: Int64 from: Int64 acc: (List ScriptStep) -> (List ScriptStep)
  (mt (indexFrom text ":turn" from)
    (none (listSortBy (fn [step] step.num) (listReverse acc)))
    ((some p)
      (if (>= (+ p 5) n)
        (listSortBy (fn [step] step.num) (listReverse acc))
        (if (not (isPySpace (bytesGet bs (+ p 5))))
          (fixtureSteps text bs n (+ p 5) acc)
          (let [(next (optionOr (indexFrom text ":turn" (+ p 5)) n))
                (num (fixtureField text ":num" p next))
                (reply (fixtureField text ":reply" p next))
                (error (fixtureField text ":error" p next))
                (usage (fixtureUsage text p next))]
            (fixtureSteps text bs n (+ p 5)
              (cons (ScriptStep :num (optionOr (stringToInt64 (optionOr num "0")) 0) :reply reply :error error :usage usage) acc)))))))

fn stepsFromReplies replies: (List String) index: Int64 -> (List ScriptStep)
  (mt (listGet replies index)
    (none (list))
    ((some reply)
      (cons (ScriptStep :num index :reply (some reply) :error none :usage none)
            (stepsFromReplies replies (+ index 1)))))

fn parseScriptFixture text: String attemptLogPath: (Option String) -> ScriptData
  (let [(bs (stringToBytes text))
        (n (bytesLength bs))
        (steps (if (or (stringContains? text ":error") (stringContains? text ":inputTokens"))
                 (fixtureSteps text bs n 0 (list))
                 (stepsFromReplies (parseScriptTurns text) 0)))]
    (ScriptData :turns steps
      :advisor (fixtureField text ":advisor" 0 n)
      :reviewer (fixtureField text ":reviewer" 0 n)
      :attemptLogPath attemptLogPath))

fn lineBreakWidth bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b (bytesGet bs i))
        (at (fn [k v] (and (< k n) (= (bytesGet bs k) v))))]
    (cond
      ((= b 13) (if (at (+ i 1) 10) 2 1))
      ((or (= b 10) (or (= b 11) (or (= b 12) (or (= b 28) (or (= b 29) (= b 30)))))) 1)
      ((and (= b 194) (at (+ i 1) 133)) 2)
      ((and (= b 226) (and (at (+ i 1) 128) (or (at (+ i 2) 168) (at (+ i 2) 169)))) 3)
      (else 0)))

fn splitLinesLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< start n) (cons (sub s start n) acc) acc))
    (let [(w (lineBreakWidth bs n i))]
      (if (= w 0)
        (splitLinesLoop s bs n (+ i 1) start acc)
        (splitLinesLoop s bs n (+ i w) (+ i w) (cons (sub s start i) acc)))))

fn pySplitLines s: String -> (List String)
  (let [(bs (stringToBytes s))]
    (splitLinesLoop s bs (bytesLength bs) 0 0 (list)))

fn searchResponse s: String bs: Bytes n: Int64 i: Int64 -> (Option String)
  (mt (indexFrom s ":response" i)
    (none none)
    ((some p)
      (mt (mt (spacesThen s bs n (+ p 9) "\"")
            (none none)
            ((some q) (mt (quotedBodyEnd bs n q) ((some e) (some (sub s q e))) (none none))))
        ((some body) (some body))
        (none (searchResponse s bs n (+ p 1))))))

fn jsonResponse line: String -> (Option String)
  (if (not (stringStartsWith? line "{"))
    none
    (mt (j/jsonParse line)
      ((ok obj) (mt (jsonLookup obj "response")
                  ((some v) (mt v ((j/jstr r) (if (stringEmpty? r) none (some r))) (_ none)))
                  (none none)))
      ((err _) none)))

fn replayLine acc: (List String) raw: String -> (List String)
  (let [(line (pyStrip raw))]
    (if (stringEmpty? line)
      acc
      (mt (jsonResponse line)
        ((some r) (cons (pyStrip r) acc))
        (none
          (let [(bs (stringToBytes line))]
            (mt (searchResponse line bs (bytesLength bs) 0)
              ((some body) (cons (pyStrip (regexUnescape body)) acc))
              (none (if (stringStartsWith? line "exit=") acc (cons line acc)))))))))

fn parseReplayLines text: String -> (List String)
  (listReverse (fold replayLine (list) (pySplitLines (pyStrip text))))

fn tokensLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [(delim (fn [b] (or (isPySpace b) (or (= b 40) (or (= b 41) (or (= b 91) (= b 93)))))))
        (a (runWhile bs n i delim))]
    (if (>= a n)
      (listReverse acc)
      (let [(e (runWhile bs n a (fn [b] (not (delim b)))))]
        (tokensLoop s bs n e (cons (sub s a e) acc)))))

fn stripQuotes s: String -> String
  (let [(bs (stringToBytes s))
        (n (bytesLength bs))
        (a (runWhile bs n 0 (fn [b] (= b 34))))]
    (sub s a (runBackWhile bs a n (fn [b] (= b 34)))))

fn scanTo toks: (List String) n: Int64 k: Int64 -> Int64
  (if (and (< (+ k 1) n) (not (stringStartsWith? (optionOr (listGet toks k) "") ":"))) (scanTo toks n (+ k 1)) k)

fn idsLoop toks: (List String) n: Int64 i: Int64 prev: String acc: (List String) -> (List String)
  (if (>= i n)
    acc
    (let [(tok (optionOr (listGet toks i) ""))
          (at (fn [k] (optionOr (listGet toks k) "")))
          (addId (fn [v] (if (or (stringEmpty? v) (listContains? acc v)) acc (cons v acc))))
          ]
      (cond
        ((or (= tok ":model") (= tok ":alias"))
          (let [(jj (scanTo toks n (+ i 1)))]
            (idsLoop toks n (+ i 1) tok (if (and (< (+ jj 1) n) (= (at jj) ":id")) (addId (stripQuotes (at (+ jj 1)))) acc))))
        ((and (= tok ":id") (and (> i 0) (or (= prev ":model") (= prev ":alias"))))
          (idsLoop toks n (+ i 1) tok (if (< (+ i 1) n) (addId (stripQuotes (at (+ i 1)))) acc)))
        (else (idsLoop toks n (+ i 1) tok acc)))))

fn ! gatewayModelIds! path: String -> (List String)
  (mt (fileReadString path)
    ((err _) (list))
    ((ok text)
      (let [(bs (stringToBytes text))
            (toks (tokensLoop text bs (bytesLength bs) 0 (list)))]
        (listSort (idsLoop toks (listLength toks) 0 "" (list))))))

fn envOr! name: String fallback: String -> String
  (mt (envGet name)
    ((some v) (if (stringEmpty? v) fallback v))
    (none fallback))

fn ! providerEnv! -> ProviderEnv
  (ProviderEnv
    :gatewayUrl (envOr! "ASL_GATEWAY_URL" "http://127.0.0.1:8765/v1/chat/completions")
    :inProcess (stringEmpty? (envOr! "ASL_GATEWAY_URL" ""))
    :profile (envOr! "ASL_PROFILE" "")
    :gatewayConfig (envOr! "ASL_GATEWAY_CONFIG" (str (envOr! "HOME" "") "/.asl/gateway.asn"))
    :tmpDir (envOr! "TMPDIR" (envOr! "TEMP" (envOr! "TMP" "/tmp")))
    :childEnv (mapEmpty))

fn normParts parts: (List String) acc: (List String) -> (List String)
  (mt (listHead parts)
    (none (listReverse acc))
    ((some p)
      (cond
        ((or (stringEmpty? p) (= p ".")) (normParts (listDrop parts 1) acc))
        ((= p "..") (normParts (listDrop parts 1) (listDrop acc 1)))
        (else (normParts (listDrop parts 1) (cons p acc))))))

fn ! absPath p: String -> String
  (let [(full (if (stringStartsWith? p "/") p (str (resultOr (realPath ".") ".") "/" p)))]
    (str "/" (stringJoin (normParts (stringSplit full "/") (list)) "/")))

fn capitalize s: String -> String
  (str (stringUpper (sub s 0 1)) (stringLower (sub s 1 (stringLength s))))

fn ! uniqueTag -> String
  (saltedTag "")

fn ! saltedTag salt: String -> String
  (let [(seed (str (stringFromInt64 (procSelf)) ":" (stringFromInt64 (nowNs)) ":" (stringFromInt64 (monotonicNs)) ":" salt))]
    (str (hexPad (& (fnv1a64 seed) 4294967295) 8 "") (hexPad (& (fnv1a64 (str seed "#")) 4294967295) 8 "")))

fn ! isFile? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! readText path: String -> (Result String ProviderError)
  (mt (fileReadString path)
    ((ok t) (ok (universalNewlines t)))
    ((err e) (err (ioError e))))

fn ! writeText path: String text: String -> (Result Int64 ProviderError)
  (mt (fileWrite path text)
    ((ok _) (ok 0))
    ((err e) (err (ioError e))))

fn ! makeDirs path: String -> (Result Int64 ProviderError)
  (mt (dirCreate path)
    ((ok _) (ok 0))
    ((err e) (err (ioError e))))

fn ! loadTurns kind: String path: String parse: (fn [String] -> (List String)) -> (Result (List String) ProviderError)
  (if (not (isFile? path))
    (err (fileMissing (str kind " not found: " path)))
    (mt (readText path)
      ((ok t) (ok (parse t)))
      ((err e) (err e))))

fn replayVendor fileName: String -> String
  (let [(low (stringLower fileName))]
    (optionOr (listHead (filter (fn [v] (stringContains? low v)) (list "agy" "codex" "claude"))) ""))

fn testBackendPrefixes -> (List String)
  (list (scriptBackendPrefix) (replayBackendPrefix))

fn scriptBackendPrefix -> String
  "script"

fn replayBackendPrefix -> String
  "replay"

fn ! makeProvider! backend: String mode: String rootDir: String model: String timeout: Int64 sessionId: String queueTimeout: Int64 timeoutSet: Bool env: ProviderEnv -> (Result Provider ProviderError)
  (cond
    ((stringStartsWith? backend (str (scriptBackendPrefix) "/"))
      (let [(name (sub backend 7 (stringLength backend)))
            (path (str rootDir "/tests/fixtures/agentLoop/mvp/" name ".asn"))]
        (if (not (isFile? path))
          (err (fileMissing (str "Script fixture not found: " path)))
          (mt (readText path)
            ((err e) (err e))
            ((ok text) (ok (scriptFixtureProvider (str "script/" name)
              (parseScriptFixture text
                (if (some? (fixtureField text ":attemptLog" 0 (stringLength text)))
                  (some (str path ".attempts")) none)) 0)))))))
    ((stringStartsWith? backend (str (replayBackendPrefix) "/"))
      (let [(name (sub backend 7 (stringLength backend)))]
        (mt (loadTurns "Replay file" (str rootDir "/tests/fixtures/agentLoop/recorded/" name) parseReplayLines)
          ((ok turns) (ok (replayProvider (str "replay/" name) rootDir turns 0 (replayVendor name))))
          ((err e) (err e)))))
    ((or (= backend "agy") (or (= backend "codex") (= backend "claude")))
      (let [(sid (if (stringEmpty? sessionId) (uniqueTag) sessionId))]
          (ok (vendorProvider (VendorConfig :vendor backend :mode (if (stringEmpty? mode) "scout" mode) :rootDir (absPath rootDir)
                                :model model :timeout (if (= timeout 0) 600 timeout) :queueTimeout (if (= queueTimeout 0) 1200 queueTimeout)
                                :sessionId sid :intent "auto" :timeoutSet timeoutSet :env env :link none)))))
    (else (err (valueError (str "Unknown backend: " backend)))))

fn providerName p: Provider -> String
  (mt p
    ((scriptProvider name _ _) name)
    ((scriptFixtureProvider name _ _) name)
    ((replayProvider name _ _ _ _) name)
    ((vendorProvider cfg) cfg.vendor))

fn vendorName p: Provider -> (Option String)
  (mt p
    ((scriptProvider _ _ _) none)
    ((scriptFixtureProvider _ _ _) none)
    ((replayProvider _ _ _ _ v) (if (stringEmpty? v) none (some v)))
    ((vendorProvider cfg) (some cfg.vendor)))

fn splitContext p: Provider -> Bool
  (mt p ((vendorProvider _) true) (_ false))

fn ! lockLoop path: String -> (Result Int64 ProviderError)
  (mt (fileLock path true)
    ((ok fd) (ok fd))
    ((err e) (if (= e "busy") (do (sleepMs 20) (lockLoop path)) (err (ioError (str path ": " e))))))

fn ! replayLock root: String vendor: String -> (Result Int64 ProviderError)
  (if (stringEmpty? vendor)
    (ok -1)
    (let [(dir (str root "/.asl/run/agentLoop"))]
      (mt (makeDirs dir)
        ((err e) (err e))
        ((ok _) (lockLoop (str dir "/" vendor ".lock"))))))

fn nth xs: (List String) i: Int64 -> (Option String)
  (if (>= i (listLength xs)) none (listGet xs i))

fn setIntent cfg: VendorConfig intent: String -> VendorConfig
  (with cfg :intent intent)

fn withLink cfg: VendorConfig link: gs/GatewayLoop -> VendorConfig
  (with cfg :link (some link))

fn ! runCli! cfg: VendorConfig tool: String args: (List String) cwd: String input: String -> (Result cp/ProcessOutput ProviderError)
  (let [(base (cp/withStdin (cp/withTimeout (cp/withCwd (cp/cmd tool args) cwd) (* cfg.timeout 1000)) input))
        (c (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv))) base (mapPairs cfg.env.childEnv)))]
    (mt (cp/exec! c)
      ((ok out) (ok out))
      ((err pe)
        (mt pe
          ((cp/notFound _) (err (toolAbsent tool (str "[Errno 2] No such file or directory: " (pyReprString tool)))))
          ((cp/permissionDenied _) (err (toolAbsent tool (str "[Errno 13] Permission denied: " (pyReprString tool)))))
          ((cp/timeout _) (err (cliTimeout (cons tool args) cfg.timeout)))
          ((cp/executionFailed _ m) (err (ioError (str tool ": " m))))))))

fn ! freshDir! base: String prefix: String tagFor: (fn [Int64] -> String) attempt: Int64 -> (Result String ProviderError)
  (let [(dir (str base "/" prefix (tagFor attempt)))]
    (cond
      ((>= attempt 1000) (err (ioError (str "no free scratch name under " base))))
      ((ok? (fileStat dir)) (freshDir! base prefix tagFor (+ attempt 1)))
      (else (mt (makeDirs dir) ((ok _) (ok dir)) ((err e) (err e))))))

fn ! tempDir! cfg: VendorConfig prefix: String -> (Result String ProviderError)
  (let [(base cfg.env.tmpDir)
        (count (mt (dirList base) ((ok names) (listLength names)) ((err _) 0)))]
    (freshDir! base prefix (fn [attempt] (saltedTag (str (stringFromInt64 count) "." (stringFromInt64 attempt)))) 0))

fn ! removeIfEmpty dir: String -> Bool
  (mt (dirList dir)
    ((ok names) (if (listEmpty? names) (ok? (pathRemove dir)) false))
    ((err _) false))

fn ! inTempDir! cfg: VendorConfig prefix: String tool: String args: (List String) input: String -> (Result cp/ProcessOutput ProviderError)
  (mt (tempDir! cfg prefix)
    ((err e) (err e))
    ((ok cwd)
      (let [(r (runCli! cfg tool args cwd input))
            (gone (removeIfEmpty cwd))]
        r)))

fn ! callCodex! cfg: VendorConfig system: String user: String -> (Result (Option String) ProviderError)
  (let [(dir (str cfg.rootDir "/.asl/run/agentLoop/codex/" cfg.sessionId))
        (instr (str dir "/" cfg.mode ".md"))
        (last (str dir "/" cfg.mode ".last"))
        (args (listAppend (list "exec" "-" "--ephemeral" "--skip-git-repo-check" "-s" "read-only"
                                "-c" (str "model_instructions_file=" instr) "-c" "project_doc_max_bytes=0" "--json" "-o" last)
                          (if (stringEmpty? cfg.model) (list) (list "-m" cfg.model))))]
    (mt (makeDirs dir)
      ((err e) (err e))
      ((ok _)
        (mt (writeText instr (str system "\n"))
          ((err e) (err e))
          ((ok _)
            (mt (inTempDir! cfg "asl_codex_cwd_" "codex" args user)
              ((err e) (err e))
              ((ok out)
                (if (isFile? last)
                  (mt (readText last) ((ok t) (ok (some (pyStrip t)))) ((err e) (err e)))
                  (ok (if (= out.exitCode 0) (some (pyStrip (universalNewlines out.stdout))) none))))))))))

fn ! callClaude! cfg: VendorConfig system: String user: String -> (Result (Option String) ProviderError)
  (let [(args (listAppend (list "-p" "--system-prompt" system "--tools" "" "--setting-sources" "" "--output-format" "json" "--no-session-persistence")
                          (if (stringEmpty? cfg.model) (list) (list "--model" cfg.model))))]
    (mt (inTempDir! cfg "asl_claude_cwd_" "claude" args user)
      ((err e) (err e))
      ((ok out)
        (if (!= out.exitCode 0)
          (ok none)
          (let [(text (universalNewlines out.stdout))]
            (mt (j/jsonParse text)
              ((err _) (ok (some (pyStrip text))))
              ((ok obj)
                (cond
                  ((not (isObject obj)) (ok (some (pyStrip text))))
                  ((pyTruthy (optionOr (jsonLookup obj "is_error") (j/jnull))) (ok none))
                  (else (ok (some (pyStrip (pyStr (optionOr (jsonLookup obj "result") (j/jstr "")))))))))))))))

fn configQuote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") "\"")

fn curlConfig url: String body: String headers: (List (Pair String String)) maxTime: String loopback: Bool -> String
  (let [(hdr (fn [k v] (str "header = " (configQuote (str k ": " v)) "\n")))]
    (str "url = " (configQuote url) "\n"
         "request = \"POST\"\n"
         "http1.1\n"
         "include\n"
         "silent\n"
         "show-error\n"
         (hdr "Content-Type" "application/json")
         (hdr "Accept" "application/asn+sexpr")
         (stringJoin (map (fn [p] (hdr (pairFirst p) (pairSecond p))) headers) "")
         "header = \"Expect:\"\n"
         "data-raw = " (configQuote body) "\n"
         "max-time = " (configQuote maxTime) "\n"
         (if loopback "noproxy = \"*\"\n" "")))

fn headEnd out: String -> (Pair Int64 Int64)
  (mt (stringIndexOf out "\r\n\r\n")
    ((some i) (pair i (+ i 4)))
    (none (mt (stringIndexOf out "\n\n")
            ((some i) (pair i (+ i 2)))
            (none (pair (stringLength out) (stringLength out))))))

fn headLines head: String -> (List String)
  (map (fn [l] (if (stringEndsWith? l "\r") (sub l 0 (- (stringLength l) 1)) l)) (stringSplit head "\n"))

fn statusOf line: String -> (Option (Pair Int64 String))
  (let [(bs (stringToBytes line))
        (n (bytesLength bs))
        (v1 (runWhile bs n 0 (fn [b] (not (isPySpace b)))))
        (s0 (runWhile bs n v1 isPySpace))
        (s1 (runWhile bs n s0 (fn [b] (not (isPySpace b)))))
        (r0 (runWhile bs n s1 isPySpace))]
    (if (not (stringStartsWith? line "HTTP/"))
      none
      (mt (stringToInt64 (sub line s0 s1))
        ((some code) (some (pair code (pyStrip (sub line r0 n)))))
        (none none))))

fn headerValue lines: (List String) name: String -> String
  (mt (listHead (filter (fn [l] (mt (stringIndexOf l ":")
                                   ((some c) (= (stringLower (pyStrip (sub l 0 c))) name))
                                   (none false)))
                        lines))
    ((some l) (pyStrip (sub l (+ (optionOr (stringIndexOf l ":") 0) 1) (stringLength l))))
    (none ""))

fn parseCurlResponse out: String -> (Result (Pair (Pair Int64 String) (Pair String String)) String)
  (let [(he (headEnd out))
        (lines (headLines (sub out 0 (pairFirst he))))
        (rest (sub out (pairSecond he) (stringLength out)))]
    (mt (statusOf (optionOr (listHead lines) ""))
      (none (err "gateway reply has no HTTP status line"))
      ((some st)
        (if (and (>= (pairFirst st) 100) (< (pairFirst st) 200))
          (parseCurlResponse rest)
          (ok (pair st (pair (headerValue (listDrop lines 1) "content-type") rest)))))))

fn illegalAt bs: Bytes n: Int64 k: Int64 -> Bool
  (let [(b (bytesGet bs k))
        (nx (if (< (+ k 1) n) (bytesGet bs (+ k 1)) -1))]
    (or (and (= b 10) (not (or (= nx 32) (= nx 9))))
        (and (= b 13) (not (or (= nx 32) (or (= nx 9) (= nx 10)))))))

fn illegalHeaderValue v: String -> Bool
  (let [(bs (stringToBytes v))
        (n (bytesLength bs))]
    (listAny? (fn [k] (illegalAt bs n k)) (range 0 n)))

fn urlHasScheme url: String -> Bool
  (mt (stringIndexOf url ":")
    ((some c) (and (> c 0) (not (stringContains? (sub url 0 c) "/"))))
    (none false))

fn floatText s: String -> Bool
  (let [(t (stringLower (pyStrip s)))
        (bs (stringToBytes t))
        (n (bytesLength bs))
        (a (if (and (> n 0) (or (= (bytesGet bs 0) 43) (= (bytesGet bs 0) 45))) 1 0))
        (d1 (runWhile bs n a isDigitByte))
        (dot (if (and (< d1 n) (= (bytesGet bs d1) 46)) (+ d1 1) d1))
        (d2 (runWhile bs n dot isDigitByte))
        (digits (> (+ (- d1 a) (- d2 dot)) 0))
        (e0 (if (and digits (and (< d2 n) (= (bytesGet bs d2) 101))) (+ d2 1) -1))
        (e1 (if (and (>= e0 0) (and (< e0 n) (or (= (bytesGet bs e0) 43) (= (bytesGet bs e0) 45)))) (+ e0 1) e0))
        (e2 (if (>= e1 0) (runWhile bs n e1 isDigitByte) -1))
        (word (sub t a n))]
    (or (and digits (if (>= e0 0) (and (> e2 e1) (= e2 n)) (= d2 n)))
        (or (= word "inf") (or (= word "infinity") (= word "nan")))))

fn pyTypeName v: j/Json -> String
  (mt v ((j/jnull) "NoneType") ((j/jarr _) "list") ((j/jobj _) "dict") (_ "str"))

fn pyFloat v: j/Json -> (Result Float64 ProviderError)
  (mt v
    ((j/jint i) (ok (int64ToFloat64 i)))
    ((j/jfloat f) (ok f))
    ((j/jnum f) (ok f))
    ((j/jbool b) (ok (if b 1.0 0.0)))
    ((j/jstr s)
      (if (floatText s)
        (let [(t (stringLower (pyStrip s)))
              (neg (stringStartsWith? t "-"))
              (word (if (or neg (stringStartsWith? t "+")) (sub t 1 (stringLength t)) t))]
          (cond
            ((or (= word "inf") (= word "infinity")) (ok (if neg (floatNegInf) (floatInf))))
            ((= word "nan") (ok (floatNan)))
            (else (mt (stringToFloat64 t)
                    ((some f) (ok f))
                    ((none) (err (valueError (str "could not convert string to float: " (pyReprString s)))))))))
        (err (valueError (str "could not convert string to float: " (pyReprString s))))))
    (_ (err (valueError (str "float() argument must be a string or a real number, not '" (pyTypeName v) "'")))))

fn numOr fields: (List (Pair String j/Json)) k: String -> Float64
  (mt (dictGet fields k)
    ((some v) (mt v ((j/jint i) (int64ToFloat64 i)) ((j/jfloat f) f) (_ 0.0)))
    (none 0.0))

fn numOrZero fields: (List (Pair String j/Json)) k: String -> j/Json
  (optionOr (dictGet fields k) (j/jint 0))

fn mkMeta timing: (Option Timing) usage: (Option (List (Pair String j/Json))) served: (Option (List (Pair String String))) finish: (Option String) -> TurnMeta
  (TurnMeta :timing timing :usage usage :served served :finish finish :truncated (= finish (some "length")))

fn readAsnReply text: String -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (mt (parseAsnReply text)
    ((err e) (pair (err (gatewayError "ERR_VENDOR" (str "Failed to parse gateway ASN response: " e) "")) (emptyMeta)))
    ((ok hf)
      (let [(head (pairFirst hf))
            (fields (pairSecond hf))
            (field (fn [k d] (optionOr (dictGet fields k) d)))]
        (cond
          ((= head "error")
            (pair (err (gatewayError "ERR_VENDOR" (pyStrip (str "Gateway error " (field "status" "?") ": " (field "reason" ""))) "")) (emptyMeta)))
          ((!= head "reply")
            (pair (err (gatewayError "ERR_VENDOR" (str "Unexpected gateway ASN form (:" head " ...)") "")) (emptyMeta)))
          (else
            (let [(timingR (mt (dictGet fields "asl")
                             ((some a) (mt (asnNumbers a)
                                         ((ok nums) (ok (some (Timing :queueWaitSec (numOr nums "queueWaitSec") :execSec (numOr nums "execSec")))))
                                         ((err e) (err e))))
                             (none (ok none))))
                  (usageR (asnNumbers (field "usage" "")))]
              (mt timingR
                ((err e) (pair (err e) (emptyMeta)))
                ((ok timing)
                  (mt usageR
                    ((err e) (pair (err e) (mkMeta timing none none none)))
                    ((ok usageNums)
                      (let [(usage (if (listEmpty? usageNums) none
                                     (some (list (pair "inputTokens" (numOrZero usageNums "input"))
                                                 (pair "cachedTokens" (numOrZero usageNums "cached"))
                                                 (pair "outputTokens" (numOrZero usageNums "output"))))))
                            (meta (mkMeta timing usage (servedFields (map (fn [p] (pair (pairFirst p) (j/jstr (pairSecond p)))) fields)) (dictGet fields "finish")))
                            (content (pyStrip (field "content" "")))]
                        (if (stringEmpty? content)
                          (pair (err (gatewayError "ERR_NO_REPLY" "Empty content in gateway response" "")) meta)
                          (pair (ok (some content)) meta)))))))))))))

fn timingOf asl: j/Json -> (Result Timing ProviderError)
  (let [(pick (fn [a b] (mt (jsonLookup asl a)
                          ((some v) (mt v ((j/jnull) (optionOr (jsonLookup asl b) (j/jfloat 0.0))) (_ v)))
                          (none (optionOr (jsonLookup asl b) (j/jfloat 0.0))))))]
    (mt (pyFloat (pick "queueWaitSec" "queue_wait_sec"))
      ((err e) (err e))
      ((ok qw) (mt (pyFloat (pick "execSec" "exec_sec"))
                 ((err e) (err e))
                 ((ok es) (ok (Timing :queueWaitSec qw :execSec es)))))))

fn replyContent resp: j/Json -> (Result (Option String) ProviderError)
  (let [(choices (optionOr (jsonLookup resp "choices") (j/jnull)))
        (noReply (fn [m] (err (gatewayError "ERR_NO_REPLY" m ""))))]
    (mt choices
      ((j/jarr xs)
        (mt (listHead xs)
          (none (noReply "Empty choices in gateway response"))
          ((some c0)
            (if (not (isObject c0))
              (err (gatewayError "ERR_VENDOR" "Gateway choice is not an object" ""))
              (let [(msg (optionOr (jsonLookup c0 "message") (j/jobj (list))))]
                (if (not (isObject msg))
                  (err (gatewayError "ERR_VENDOR" "Gateway message is not an object" ""))
                  (mt (optionOr (jsonLookup msg "content") (j/jnull))
                    ((j/jnull) (noReply "Empty content in gateway response"))
                    ((j/jstr s) (if (stringEmpty? (pyStrip s)) (noReply "Empty content in gateway response") (ok (some (pyStrip s)))))
                    (v (ok (some (pyStrip (pyStr v))))))))))))
      (_ (noReply "Empty choices in gateway response"))))

fn readJsonReply body: String -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (mt (j/jsonParse body)
    ((err e) (pair (err (gatewayError "ERR_VENDOR" (str "Failed to parse gateway JSON response: " e) "")) (emptyMeta)))
    ((ok resp)
      (if (not (isObject resp))
        (pair (err (gatewayError "ERR_VENDOR" "Failed to parse gateway JSON response: not an object" "")) (emptyMeta))
        (let [(asl (optionOr (jsonLookup resp "asl") (j/jnull)))
              (aslIsDict (isObject asl))]
          (mt (if aslIsDict (mt (timingOf asl) ((ok t) (ok (some t))) ((err e) (err e))) (ok none))
            ((err e) (pair (err e) (emptyMeta)))
            ((ok timing)
              (let [(usageV (if aslIsDict (jsonLookup asl "usage") none))
                    (usage (mt usageV
                             ((some u) (if (isObject u)
                                         (some (map (fn [k] (pair k (optionOr (jsonLookup u k) (j/jint 0)))) (list "inputTokens" "cachedTokens" "outputTokens")))
                                         none))
                             (none none)))
                    (served (servedFields (dictPut (jsonDict asl) "model" (optionOr (jsonLookup resp "model") (j/jnull)))))
                    (meta (TurnMeta :timing timing :usage usage :served served :finish none :truncated false))]
                (pair (replyContent resp) meta))))))))

fn httpErrorBody body: String -> String
  (if (stringStartsWith? (pyLstrip body) "(:error")
    (mt (parseAsnReply body)
      ((ok hf) (optionOr (dictGet (pairSecond hf) "reason") body))
      ((err _) body))
    body)

fn httpError code: Int64 reason: String raw: String -> ProviderError
  (let [(body (httpErrorBody raw))
        (c (stringFromInt64 code))]
    (cond
      ((= code 413) (gatewayError "ERR_CONTEXT_TOO_LONG" (pyStrip (str "Gateway 413: " body)) ""))
      ((or (= code 504) (stringContains? body "QUEUE_TIMEOUT")) (gatewayError "ERR_QUEUE_TIMEOUT" (str "Gateway queue timeout: " c " " body) ""))
      (else (gatewayError "ERR_VENDOR" (pyStrip (str "Gateway HTTP error " c ": " reason " " body)) ""))))

fn transportText out: cp/ProcessOutput -> String
  (let [(e (pyStrip out.stderr))]
    (if (stringEmpty? e) (str "curl exit " (stringFromInt64 out.exitCode)) e))

fn readCurl url: String out: cp/ProcessOutput -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (cond
    ((= out.exitCode 28)
      (pair (err (gatewayError "ERR_VENDOR" (str "Gateway timed out waiting for reply: " (transportText out)) "")) (emptyMeta)))
    ((!= out.exitCode 0)
      (pair (err (gatewayError "ERR_GATEWAY_OFFLINE" (str "Gateway unreachable at " url ": " (transportText out) "; run ./bin/asl-gateway start") "./bin/asl-gateway start")) (emptyMeta)))
    (else (readResponse out.stdout)))

fn readResponse raw: String -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (mt (parseCurlResponse raw)
    ((err e) (pair (err (gatewayError "ERR_VENDOR" (str "Gateway reply unreadable: " e) "")) (emptyMeta)))
    ((ok r)
      (let [(code (pairFirst (pairFirst r)))
            (ctype (pairFirst (pairSecond r)))
            (body (pairSecond (pairSecond r)))]
        (cond
          ((or (< code 200) (>= code 300)) (pair (err (httpError code (pairSecond (pairFirst r)) body)) (emptyMeta)))
          ((stringContains? ctype "application/asn+sexpr") (readAsnReply body))
          (else (readJsonReply body))))))

(schema Called
  (:f reply (Result (Option String) ProviderError))
  (:f meta TurnMeta)
  (:f cfg VendorConfig))

fn called cfg: VendorConfig r: (Pair (Result (Option String) ProviderError) TurnMeta) -> Called
  (Called :reply (pairFirst r) :meta (pairSecond r) :cfg cfg)

fn configHome path: String -> (Option String)
  (if (stringEndsWith? path "/.asl/gateway.asn") (some (sub path 0 (- (stringLength path) (stringLength "/.asl/gateway.asn")))) none)

fn ! openLink! cfg: VendorConfig -> (Result gs/GatewayLoop ProviderError)
  (mt cfg.link
    ((some l) (ok l))
    ((none)
      (let [(config cfg.env.gatewayConfig)
            (env (fold (fn [acc kv] (mapSet acc (pairFirst kv) (pairSecond kv))) (gu/envMapFromList (envList)) (mapPairs cfg.env.childEnv)))
            (root (optionOr (mapGet env "ASL_GATEWAY_ROOT") (optionOr (mapGet env "ROOT_DIR") cfg.rootDir)))]
        (mt (configHome config)
          ((none) (err (gatewayError "ERR_GATEWAY_CONFIG" (str "in-process gateway reads HOME/.asl/gateway.asn, not " config) "set ASL_GATEWAY_URL for an HTTP gateway")))
          ((some home)
            (mt (gs/linkOpen! env home root (gd/builtinFamilies))
              ((err e) (err (gatewayError "ERR_GATEWAY_CONFIG" (str "in-process gateway: " e) "set ASL_GATEWAY_URL for an HTTP gateway")))
              ((ok l) (ok l))))))))

; (:m :effect net)
fn ! linkGateway! cfg: VendorConfig payload: j/Json headers: (List (Pair String String)) -> Called
  (mt (openLink! cfg)
    ((err e) (Called :reply (err e) :meta (emptyMeta) :cfg cfg))
    ((ok l)
      (let [(body (pyJsonDumps payload))
            (sent (listAppend (list (pair "Content-Type" "application/json") (pair "Accept" "application/asn+sexpr"))
                    (listAppend headers (list (pair "Content-Length" (stringFromInt64 (bytesLength (stringToBytes body))))))))
            (out (gs/linkSend! l "POST" "/v1/chat/completions" sent body (* (+ (+ cfg.timeout cfg.queueTimeout) 30) 1000)))
            (next (withLink cfg (pairFirst out)))]
        (mt (pairSecond out)
          ((err e) (Called :reply (err (gatewayError "ERR_VENDOR" (str "in-process gateway: " e) "")) :meta (emptyMeta) :cfg next))
          ((ok raw) (called next (readResponse raw)))))))

fn ! sendGateway! cfg: VendorConfig payload: j/Json headers: (List (Pair String String)) -> Called
  (if cfg.env.inProcess (linkGateway! cfg payload headers) (called cfg (postGateway! cfg payload headers)))

; (:m :effect net)
fn ! postGateway! cfg: VendorConfig payload: j/Json headers: (List (Pair String String)) -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (let [(url cfg.env.gatewayUrl)
        (body (pyJsonDumps payload))
        (maxTime (stringFromFloat64 (int64ToFloat64 (+ (+ cfg.timeout cfg.queueTimeout) 30))))
        (bad (filter (fn [p] (illegalHeaderValue (pairSecond p))) headers))]
    (cond
      ((not (urlHasScheme url)) (pair (err (valueError (str "unknown url type: " (pyReprString url)))) (emptyMeta)))
      ((not (listEmpty? bad)) (pair (err (valueError (str "Invalid header value " (pyReprBytes (pairSecond (optionOr (listHead bad) (pair "" ""))))))) (emptyMeta)))
      (else
        (let [(conf (curlConfig url body headers maxTime (isLoopback url)))
              (c0 (cp/withStdin (cp/withTimeout (cp/cmd "curl" (list "--config" "-")) (* (+ (+ cfg.timeout cfg.queueTimeout) 60) 1000)) conf))
              (c (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv))) c0 (mapPairs cfg.env.childEnv)))]
          (mt (cp/exec! c)
            ((ok out) (readCurl url out))
            ((err pe)
              (mt pe
                ((cp/notFound _) (pair (err (toolAbsent "curl" "curl is not installed; the gateway call needs it (capabilities.asn :externalTools curl)")) (emptyMeta)))
                ((cp/timeout _) (pair (err (gatewayError "ERR_VENDOR" "Gateway timed out waiting for reply: curl did not exit" "")) (emptyMeta)))
                (_ (pair (err (gatewayError "ERR_GATEWAY_OFFLINE" (str "Gateway unreachable at " url ": curl could not start; run ./bin/asl-gateway start") "./bin/asl-gateway start")) (emptyMeta))))))))))

fn msg role: String content: String -> j/Json
  (j/jobj (list (pair "role" (j/jstr role)) (pair "content" (j/jstr content))))

; (:m :effect net)
fn ! callProfile! cfg: VendorConfig system: String user: String model: String -> Called
  (let [(ws (absPath (str cfg.rootDir "/.asl/run/agentLoop/agents/" cfg.sessionId)))
        (profile cfg.env.profile)
        (headers (if (and (= model "profile") (not (stringEmpty? profile))) (list (pair "X-ASL-Profile" profile)) (list)))
        (payload (j/jobj (listAppend
                           (list (pair "model" (j/jstr model))
                                 (pair "intent" (j/jstr cfg.intent))
                                 (pair "messages" (j/jarr (list (msg "system" system) (msg "user" user))))
                                 (pair "tools" (j/jarr (list)))
                                 (pair "workspace" (j/jstr ws)))
                           (listAppend (if cfg.timeoutSet (list (pair "timeout" (j/jint cfg.timeout))) (list))
                                       (list (pair "queue_timeout" (j/jint cfg.queueTimeout)))))))]
    (mt (makeDirs ws)
      ((err e) (Called :reply (err e) :meta (emptyMeta) :cfg cfg))
      ((ok _) (sendGateway! cfg payload headers))))

fn agentFileText agent: String system: String -> String
  (str "---\nname: " agent "\ndescription: ASL agent loop endpoint\nmainAgent: true\nsubagent: false\ntools: []\n"
       "inheritMcp: false\ninheritCustomizations: false\nexcludeDefaultComponents: true\n---\n\n# " agent "\n\n" system "\n")

; (:m :effect net)
fn ! callAgy! cfg: VendorConfig system: String user: String -> Called
  (let [(model cfg.model)]
    (cond
      ((stringEmpty? model) (callProfile! cfg system user "profile"))
      ((or (listContains? (gatewayModelIds! cfg.env.gatewayConfig) model)
           (or (stringStartsWith? model "ollama/") (or (stringStartsWith? model "groq/") (stringStartsWith? model "openrouter/"))))
        (callProfile! cfg system user model))
      (else
        (let [(agent (str "aslLoop" (if (stringEmpty? cfg.mode) "Scout" (capitalize cfg.mode))))
              (root (absPath (str cfg.rootDir "/.asl/run/agentLoop/agents/" cfg.sessionId)))
              (pluginDir (str root "/.agents/plugins/aslLoop"))
              (payload (j/jobj (list (pair "model" (j/jstr (if (stringStartsWith? model "agy/") model (str "agy/" model))))
                                     (pair "messages" (j/jarr (list (msg "user" user))))
                                     (pair "agent" (j/jstr agent))
                                     (pair "tools" (j/jarr (list)))
                                     (pair "addDirs" (j/jarr (list (j/jstr root))))
                                     (pair "workspace" (j/jstr root))
                                     (pair "timeout" (j/jint cfg.timeout))
                                     (pair "queue_timeout" (j/jint cfg.queueTimeout)))))
              (written (mt (makeDirs (str pluginDir "/agents"))
                         ((err e) (err e))
                         ((ok _) (mt (writeText (str pluginDir "/plugin.json") (pyJsonDumps (j/jobj (list (pair "name" (j/jstr "aslLoop"))))))
                                   ((err e) (err e))
                                   ((ok _) (writeText (str pluginDir "/agents/" agent ".md") (agentFileText agent system)))))))]
          (mt written
            ((err e) (Called :reply (err e) :meta (emptyMeta) :cfg cfg))
            ((ok _) (sendGateway! cfg payload (list))))))))

fn ! callVendor! cfg: VendorConfig system: String user: String -> Called
  (cond
    ((= cfg.vendor "agy") (callAgy! cfg system user))
    ((= cfg.vendor "codex") (Called :reply (callCodex! cfg system user) :meta (emptyMeta) :cfg cfg))
    ((= cfg.vendor "claude") (Called :reply (callClaude! cfg system user) :meta (emptyMeta) :cfg cfg))
    (else (Called :reply (err (valueError (str "Unknown vendor: " cfg.vendor))) :meta (emptyMeta) :cfg cfg)))

fn stepTurns turns: (List String) index: Int64 -> (Pair (Option String) Int64)
  (mt (nth turns index)
    ((some r) (pair (some r) (+ index 1)))
    (none (pair none index)))

fn ! nextTurn! p: Provider system: String user: String -> Turn
  (mt p
    ((scriptProvider name turns index)
      (let [(s (stepTurns turns index))]
        (Turn :provider (scriptProvider name turns (pairSecond s)) :reply (ok (pairFirst s)) :meta (emptyMeta))))
    ((scriptFixtureProvider name fixture index)
      (let [logged (mt fixture.attemptLogPath
                    ((some logPath) (fileAppend logPath (str "(:attempt :ns " (stringFromInt64 (monotonicNs)) ")\n")))
                    ((none) (ok true)))]
        (mt logged
          ((err e) (Turn :provider p :reply (err (ioError e)) :meta (emptyMeta)))
          ((ok _) (mt (listGet fixture.turns index)
            (none (Turn :provider p :reply (ok none) :meta (emptyMeta)))
            ((some step)
              (Turn :provider (scriptFixtureProvider name fixture (+ index 1))
                :reply (mt step.error
                  (none (ok step.reply))
                  ((some code) (err (providerError code (str "scripted provider failure: " code)))))
                :meta (TurnMeta :timing none :usage step.usage :served none :finish none :truncated false))))))))
    ((replayProvider name root turns index vendor)
      (mt (replayLock root vendor)
        ((err e) (Turn :provider p :reply (err e) :meta (emptyMeta)))
        ((ok fd)
          (let [(s (stepTurns turns index))
                (released (if (>= fd 0) (fdClose fd) (ok ())))]
            (Turn :provider (replayProvider name root turns (pairSecond s) vendor)
                  :reply (mt released ((ok _) (ok (pairFirst s))) ((err e) (err (ioError (str "unlock: " e)))))
                  :meta (emptyMeta))))))
    ((vendorProvider cfg)
      (let [(r (callVendor! cfg system user))]
        (Turn :provider (vendorProvider r.cfg) :reply r.reply :meta r.meta))))

fn ! advise! p: Provider system: String text: String -> (Option Turn)
  (mt p
    ((scriptFixtureProvider name fixture index)
      (some (Turn :provider p :reply
        (mt fixture.advisor
          ((some reply) (ok (some reply)))
          ((none) (err (providerError "ERR_NO_ADVISOR_CHANNEL" "ERR_NO_ADVISOR_CHANNEL provider has no advisor channel"))))
        :meta (emptyMeta))))
    ((vendorProvider cfg)
      (let [(r (callVendor! (setIntent cfg "reinforce") system text))]
        (some (Turn :provider (vendorProvider (setIntent r.cfg cfg.intent)) :reply r.reply :meta r.meta))))
    (_ none))

fn ! review! p: Provider system: String text: String -> Turn
  (mt p
    ((scriptFixtureProvider scriptName fixture scriptIndex)
      (mt fixture.reviewer
        ((some reply) (Turn :provider p :reply (ok (some reply)) :meta (emptyMeta)))
        ((none) (Turn :provider p :reply
          (err (providerError "ERR_NO_REVIEWER_CHANNEL" "ERR_NO_REVIEWER_CHANNEL provider has no reviewer channel"))
          :meta (emptyMeta)))))
    ((vendorProvider vendorConfig) (let [turn (nextTurn! p system text)]
      (mt turn.reply
        ((err e) turn)
        ((ok reply) (mt reply
          ((some reviewerReply) turn)
          ((none) (Turn :provider turn.provider
            :reply (err (providerError "ERR_NO_REVIEWER_CHANNEL" "ERR_NO_REVIEWER_CHANNEL provider has no reviewer channel"))
            :meta turn.meta)))))))
    ((scriptProvider scriptName turns index) (Turn :provider p :reply
      (err (providerError "ERR_NO_REVIEWER_CHANNEL" "ERR_NO_REVIEWER_CHANNEL provider has no reviewer channel"))
      :meta (emptyMeta)))
    ((replayProvider replayName rootDir turns index vendor) (Turn :provider p :reply
      (err (providerError "ERR_NO_REVIEWER_CHANNEL" "ERR_NO_REVIEWER_CHANNEL provider has no reviewer channel"))
      :meta (emptyMeta))))

fn ! removeTree path: String -> (Result Int64 ProviderError)
  (if (ok? (fileStat path))
    (mt (pathRemove path) ((ok _) (ok 0)) ((err e) (err (ioError e))))
    (ok 0))

fn ! cleanup! p: Provider -> (Result Int64 ProviderError)
  (mt p
    ((vendorProvider cfg)
      (let [(run (str cfg.rootDir "/.asl/run/agentLoop"))
            (results (map removeTree (list (absPath (str run "/agents/" cfg.sessionId))
                                           (str run "/codex/" cfg.sessionId)
                                           (str run "/claude/" cfg.sessionId))))]
        (optionOr (listHead (filter err? results)) (ok 0))))
    (_ (ok 0)))

fn relUnder root: String path: String -> String
  (if (stringStartsWith? path (str root "/")) (sub path (+ (stringLength root) 1) (stringLength path)) path)

fn codexArgv instr: String last: String model: String -> j/Json
  (j/jarr (map (fn [a] (j/jstr a))
    (listAppend (list "codex" "exec" "-" "--ephemeral" "--skip-git-repo-check" "-s" "read-only"
                      "-c" (str "model_instructions_file=" instr) "-c" "project_doc_max_bytes=0" "--json" "-o" last)
                (if (stringEmpty? model) (list) (list "-m" model)))))

fn ! buildDryRunInfo! vendor: String mode: String rootDir: String model: String timeout: Int64 queueTimeout: Int64 env: ProviderEnv -> (Result j/Json ProviderError)
  (let [(base (list (pair "vendor" (j/jstr vendor)) (pair "cwd" (j/jstr ""))))
        (t (j/jint (if (= timeout 0) 600 timeout)))
        (q (j/jint (if (= queueTimeout 0) 1200 queueTimeout)))]
    (cond
      ((= vendor "agy")
        (let [(agent (str "aslLoop" (if (stringEmpty? mode) "Scout" (capitalize mode))))
              (agents (absPath (str rootDir "/.asl/run/agentLoop/agents")))
              (pluginDir (str agents "/.agents/plugins/aslLoop"))
              (agentFile (str pluginDir "/agents/" agent ".md"))
              (url env.gatewayUrl)
              (sub0 (if (stringEmpty? model) "gemini-3.8-flash" model))
              (modelStr (j/jstr (if (stringStartsWith? sub0 "agy/") sub0 (str "agy/" sub0))))
              (dirs (j/jarr (list (j/jstr agents))))
              (text (str "---\nname: " agent "\ndescription: ASL agent loop endpoint\nmainAgent: true\nsubagent: false\ntools: []\n"
                         "inheritMcp: false\ninheritCustomizations: false\nexcludeDefaultComponents: true\n---\n\n# " agent "\n\n"))
              (written (mt (makeDirs (str pluginDir "/agents"))
                         ((err e) (err e))
                         ((ok _) (mt (writeText (str pluginDir "/plugin.json") (pyJsonDumps (j/jobj (list (pair "name" (j/jstr "aslLoop"))))))
                                   ((err e) (err e))
                                   ((ok _) (writeText agentFile text))))))]
          (mt written
            ((err e) (err e))
            ((ok _)
              (ok (j/jobj (listAppend base
                (list (pair "request" (j/jobj (list (pair "url" (j/jstr url)) (pair "model" modelStr) (pair "agent" (j/jstr agent))
                                                    (pair "addDirs" dirs) (pair "workspace" (j/jstr agents)) (pair "timeout" t) (pair "queue_timeout" q))))
                      (pair "url" (j/jstr url)) (pair "model" modelStr) (pair "agent" (j/jstr agent)) (pair "addDirs" dirs)
                      (pair "workspace" (j/jstr agents)) (pair "timeout" t) (pair "queue_timeout" q)
                      (pair "agentFile" (j/jstr (relUnder (absPath rootDir) agentFile)))
                      (pair "agentFrontmatter" (j/jstr "tools: [] inheritMcp: false inheritCustomizations: false excludeDefaultComponents: true"))))))))))
      ((= vendor "codex")
        (let [(dir (str rootDir "/.asl/run/agentLoop/codex"))
              (instr (str dir "/" mode ".md"))]
          (mt (makeDirs dir)
            ((err e) (err e))
            ((ok _)
              (ok (j/jobj (listAppend base
                (list (pair "argv" (codexArgv instr (str dir "/" mode ".last") model))
                      (pair "modelInstructionsFile" (j/jstr (relUnder (absPath rootDir) (absPath instr))))
                      (pair "stdinRedirected" (j/jbool true))))))))))
      ((= vendor "claude")
        (ok (j/jobj (listAppend base
          (list (pair "argv" (j/jarr (map (fn [a] (j/jstr a))
                  (listAppend (list "claude" "-p" "--system-prompt" "" "--tools" "" "--setting-sources" "" "--output-format" "json" "--no-session-persistence")
                              (if (stringEmpty? model) (list) (list "--model" model)))))))))))
      (else (ok (j/jobj base)))))
