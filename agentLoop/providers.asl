(module asl/agentLoop/providers
  :x [retryAfterSec ProviderError providerError valueError fileMissing toolAbsent cliTimeout ioError errorCode errorMessage configPathRefusal
      ProviderEnv VendorConfig HubCall Ask askDone askHub nextTurnAsk! nextTurnReply hubBusy? Provider ScriptStep ScriptData scriptProvider scriptFixtureProvider replayProvider vendorProvider Timing TurnMeta Turn emptyMeta
      pyStrip pyRepr pyReprString pyStr pyJsonDumps universalNewlines
      parseAsnReply asnNumbers servedFields isLoopback parseScriptTurns parseReplayLines testBackendPrefixes gatewayModelIds!
      curlConfig parseCurlResponse tempDir! freshDir! attribHeaders buildDryRunInfo! providerEnv! makeProvider! nextTurn! withPrefill withTools acceptHeader readJsonReply outgoingMessages profileMessages advise! review! grade! graderAvailable? providerName vendorName splitContext cleanup! toolsField capTimeouts]
  :i [(asl-json/json :a j) (asl/agentLoop/journal :a jr) (asl-proc/coreProcess :a cp) (aslGateway/server :a gs) (aslGateway/dispatch :a gd) (aslGateway/upstream :a gu) (aslGateway/config :a cfg) (asl/agentLoop/nativeTools :a nt)])

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

(schema HubCall
  (:f sock String)
  (:f body String)
  (:f headers (List (Pair String String))))

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
  (:f link (Option gs/GatewayLoop))
  (:f turn Int64)
  (:f prefill String :default "")
  (:f tools (List j/Json) :default (list))
  (:f defer Bool :default false)
  (:f hub (Option HubCall) :default none)
  ; (:m :ref TOOLS-400-FALLBACK :do "set once a route answered HTTP 400 to a request carrying tools: cfgTools then keeps the tool list empty for the rest of the session, so every later turn speaks the text protocol")
  (:f noTools Bool :default false))

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
  (:f gradeReply (Option String))
  (:f gradeModel (Option String))
  (:f gradeError (Option String))
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
  (match e
    ((providerError c _) c)
    ((valueError _) "ERR_VALUE")
    ((fileMissing _) "ERR_NOT_FOUND")
    ((toolAbsent _ _) "ERR_TOOL_ABSENT")
    ((cliTimeout _ _) "ERR_TIMEOUT")
    ((ioError _) "ERR_IO"))

fn errorMessage e: ProviderError -> String
  (match e
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
  (match (stringIndexOf (sub s i (stringLength s)) t)
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
  (match (listHead xs)
    (none (listReverse acc))
    ((some x)
      (match (listHead acc)
        ((some a) (if (= (pairFirst (pairSecond a)) (pairFirst (pairSecond x)))
                    (groupLast (listDrop xs 1) (cons (pair (pairFirst a) (pairSecond x)) (listDrop acc 1)))
                    (groupLast (listDrop xs 1) (cons x acc))))
        (none (groupLast (listDrop xs 1) (cons x acc))))))

fn dictFromPairs ps: (List (Pair String T)) -> (List (Pair String T))
  (let [(indexed (listReverse (pairSecond (fold (fn [acc p] (pair (+ (pairFirst acc) 1) (cons (pair (pairFirst acc) p) (pairSecond acc)))) (pair 0 (list)) ps))))
        (byKey (listSortBy (fn [ip] (pairFirst (pairSecond ip))) indexed))]
    (map pairSecond (listSortBy pairFirst (groupLast byKey (list)))))

fn dictGet kv: (List (Pair String T)) k: String -> (Option T)
  (match (listHead (filter (fn [p] (= (pairFirst p) k)) kv))
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
  (match v
    ((j/jnull) "None")
    ((j/jbool b) (if b "True" "False"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum f) (stringFromFloat64 f))
    ((j/jstr s) (pyReprString s))
    ((j/jarr xs) (str "[" (stringJoin (map pyRepr xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (stringJoin (map (fn [p] (str (pyReprString (pairFirst p)) ": " (pyRepr (pairSecond p)))) kvs) ", ") "}")))

fn pyStr v: j/Json -> String
  (match v
    ((j/jstr s) s)
    (_ (pyRepr v)))

fn pyTruthy v: j/Json -> Bool
  (match v
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
  (match v
    ((j/jnull) "null")
    ((j/jbool b) (if b "true" "false"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (jsonFloat f))
    ((j/jnum f) (jsonFloat f))
    ((j/jstr s) (jsonString s))
    ((j/jarr xs) (str "[" (stringJoin (map pyJsonDumps xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (stringJoin (map (fn [p] (str (jsonString (pairFirst p)) ": " (pyJsonDumps (pairSecond p)))) kvs) ", ") "}")))

fn jsonLookup v: j/Json k: String -> (Option j/Json)
  (match v
    ((j/jobj kvs) (listLast (map pairSecond (filter (fn [p] (= (pairFirst p) k)) kvs))))
    (_ none))

fn jsonDict v: j/Json -> (List (Pair String j/Json))
  (match v
    ((j/jobj kvs) (dictFromPairs kvs))
    (_ (list)))

fn isObject v: j/Json -> Bool
  (match v ((j/jobj _) true) (_ false))

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
        ((= c 34) (match (asnStringEnd bs n (+ j 1)) ((ok k) (asnFormEnd bs n k depth)) ((err e) (err e))))
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
        (match (asnValueEnd bs n i1)
          ((err e) (err e))
          ((ok keyEnd)
            (let [(key (sub s (+ i1 1) keyEnd))
                  (i2 (runWhile bs n keyEnd isPySpace))]
              (if (>= i2 (- n 1))
                (err (str "keyword :" key " has no value"))
                (match (asnValueEnd bs n i2)
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
      (match (asnValueEnd bs n 0)
        ((err e) (err e))
        ((ok whole)
          (if (!= whole n)
            (err "trailing text after the form")
            (match (asnValueEnd bs n 2)
              ((err e) (err e))
              ((ok headEnd)
                (match (fieldsLoop s bs n headEnd (list))
                  ((err e) (err e))
                  ((ok fields) (ok (pair (sub s 2 headEnd) fields)))))))))))

fn isNumByte b: Int64 -> Bool
  (or (isDigitByte b) (= b 46))

fn floatValue v: String -> (Result j/Json ProviderError)
  (match (stringToFloat64 v)
    ((some f) (ok (j/jfloat f)))
    ((none) (err (valueError (str "could not convert string to float: " (pyReprString v))))))

fn numberValue v: String -> (Result j/Json ProviderError)
  (if (stringContains? v ".")
    (if (> (stringCountChar v ".") 1)
      (err (valueError (str "could not convert string to float: " (pyReprString v))))
      (floatValue v))
    (match (stringToInt64 v)
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
            (match (numberValue (sub s w1 e))
              ((err x) (err x))
              ((ok num) (numbersLoop s bs n e (cons (pair (sub s (+ i 1) k1) num) acc)))))))))

fn asnNumbers form: String -> (Result (List (Pair String j/Json)) ProviderError)
  (let [(bs (stringToBytes form))]
    (numbersLoop form bs (bytesLength bs) 0 (list)))

fn servedFields fields: (List (Pair String j/Json)) -> (Option (List (Pair String String)))
  (let [(keep (fn [k] (match (dictGet fields k)
                        ((some v) (match v ((j/jnull) false) ((j/jstr s) (not (stringEmpty? s))) (_ true)))
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
      (let [(hostinfo (match (listLast (stringSplit netloc "@")) ((some h) h) (none netloc)))
            (host (if (stringContains? hostinfo "[")
                    (let [(br (sub hostinfo (+ (optionOr (stringIndexOf hostinfo "[") 0) 1) (stringLength hostinfo)))]
                      (sub br 0 (optionOr (stringIndexOf br "]") (stringLength br))))
                    (sub hostinfo 0 (optionOr (stringIndexOf hostinfo ":") (stringLength hostinfo)))))]
        (ok (stringLower host)))))

fn isLoopback url: String -> Bool
  (match (urlHostname url)
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
  (match (spacesThen s bs n (+ p 5) ":num")
    (none none)
    ((some a)
      (let [(w (runWhile bs n a isPySpace))
            (d (runWhile bs n w isDigitByte))]
        (if (or (= w a) (= d w))
          none
          (match (spacesThen s bs n d ":reply")
            (none none)
            ((some r)
              (match (spacesThen s bs n r "\"")
                (none none)
                ((some q)
                  (match (quotedBodyEnd bs n q)
                    (none none)
                    ((some e) (some (pair (optionOr (stringToInt64 (sub s w d)) 9223372036854775807) (pair (+ e 1) (sub s q e))))))))))))))

fn turnsLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (match (indexFrom s ":turn" i)
    (none (listReverse acc))
    ((some p)
      (match (matchTurn s bs n p)
        (none (turnsLoop s bs n (+ p 1) acc))
        ((some m) (turnsLoop s bs n (pairFirst (pairSecond m)) (cons (pair (pairFirst m) (regexUnescape (pairSecond (pairSecond m)))) acc))))))

fn parseScriptTurns text: String -> (List String)
  (let [(bs (stringToBytes text))]
    (map pairSecond (listSortBy pairFirst (turnsLoop text bs (bytesLength bs) 0 (list)))))

fn fixtureField text: String key: String from: Int64 limit: Int64 -> (Option String)
  (if (>= from limit)
    none
    (match (indexFrom text key from)
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
                (match (quotedBodyEnd bs limit (+ v 1))
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
  (match (indexFrom text ":turn" from)
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
  (match (listGet replies index)
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
      :gradeReply (fixtureField text ":gradeReply" 0 n)
      :gradeModel (fixtureField text ":gradeModel" 0 n)
      :gradeError (fixtureField text ":gradeError" 0 n)
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
  (match (indexFrom s ":response" i)
    (none none)
    ((some p)
      (match (match (spacesThen s bs n (+ p 9) "\"")
            (none none)
            ((some q) (match (quotedBodyEnd bs n q) ((some e) (some (sub s q e))) (none none))))
        ((some body) (some body))
        (none (searchResponse s bs n (+ p 1))))))

fn jsonResponse line: String -> (Option String)
  (if (not (stringStartsWith? line "{"))
    none
    (match (j/jsonParse line)
      ((ok obj) (match (jsonLookup obj "response")
                  ((some v) (match v ((j/jstr r) (if (stringEmpty? r) none (some r))) (_ none)))
                  (none none)))
      ((err _) none)))

fn replayLine acc: (List String) raw: String -> (List String)
  (let [(line (pyStrip raw))]
    (if (stringEmpty? line)
      acc
      (match (jsonResponse line)
        ((some r) (cons (pyStrip r) acc))
        (none
          (let [(bs (stringToBytes line))]
            (match (searchResponse line bs (bytesLength bs) 0)
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
  (match (fileReadString path)
    ((err _) (list))
    ((ok text)
      (let [(bs (stringToBytes text))
            (toks (tokensLoop text bs (bytesLength bs) 0 (list)))]
        (listSort (idsLoop toks (listLength toks) 0 "" (list))))))

fn envOr! name: String fallback: String -> String
  (match (envGet name)
    ((some v) (if (stringEmpty? v) fallback v))
    (none fallback))

; (:m :ref PROFILE-PIN-NAME-20261018 :do "rule no-env-config: FREEBULK-ROUTED-DEEPSEEK-20261017 dropped the ASL_PROFILE env var entirely. An empty :profile here already made callProfile! send no X-ASL-Profile header (model != 'profile' is the only other no-header case), and the gateway resolves a headerless request through its own default profile (~/.asl/gateway.asn :uses (:use :for default :profile commandCode)), whose code/any chain opens with ccDeepseekFlash -- the exact deepseek RETRY5/6/7 hit. The env var was one more way to land on empty besides an unset/missing pin: keeping it meant a FREEPOOL child could still silently inherit whatever ASL_PROFILE its own ambient shell had (or lacked), on top of the pin file this worktree actually wanted. The pin's path, reader and writer are now the one shared cfg/profilePinPath / cfg/profilePinRead! / cfg/writeProfilePin! (asl-gateway/config.asl) every caller uses -- this used to duplicate its own path string and its own byte-tokenizer parse")
fn ! providerEnv! rootDir: String -> ProviderEnv
  (ProviderEnv
    :gatewayUrl (envOr! "ASL_GATEWAY_URL" "http://127.0.0.1:8765/v1/chat/completions")
    :inProcess (stringEmpty? (envOr! "ASL_GATEWAY_URL" ""))
    :profile (optionOr (cfg/profilePinRead! rootDir) "")
    :gatewayConfig (envOr! "ASL_GATEWAY_CONFIG" (str (envOr! "HOME" "") "/.asl/gateway.asn"))
    :tmpDir (envOr! "TMPDIR" (envOr! "TEMP" (envOr! "TMP" "/tmp")))
    :childEnv (mapEmpty))

fn normParts parts: (List String) acc: (List String) -> (List String)
  (match (listHead parts)
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
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! readText path: String -> (Result String ProviderError)
  (match (fileReadString path)
    ((ok t) (ok (universalNewlines t)))
    ((err e) (err (ioError e))))

fn ! writeText path: String text: String -> (Result Int64 ProviderError)
  (match (fileWrite path text)
    ((ok _) (ok 0))
    ((err e) (err (ioError e))))

fn ! makeDirs path: String -> (Result Int64 ProviderError)
  (match (dirCreate path)
    ((ok _) (ok 0))
    ((err e) (err (ioError e))))

fn ! loadTurns kind: String path: String parse: (fn [String] -> (List String)) -> (Result (List String) ProviderError)
  (if (not (isFile? path))
    (err (fileMissing (str kind " not found: " path)))
    (match (readText path)
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

fn ! makeProvider! backend: String mode: String rootDir: String model: String timeout: Int64 sessionId: String queueTimeout: Int64 timeoutSet: Bool env: ProviderEnv intent: String -> (Result Provider ProviderError)
  (cond
    ((stringStartsWith? backend (str (scriptBackendPrefix) "/"))
      (let [(name (sub backend 7 (stringLength backend)))
            (path (str rootDir "/tests/fixtures/agentLoop/mvp/" name ".asn"))]
        (if (not (isFile? path))
          (err (fileMissing (str "Script fixture not found: " path)))
          (match (readText path)
            ((err e) (err e))
            ((ok text) (ok (scriptFixtureProvider (str "script/" name)
              (parseScriptFixture text
                (if (some? (fixtureField text ":attemptLog" 0 (stringLength text)))
                  (some (str path ".attempts")) none)) 0)))))))
    ((stringStartsWith? backend (str (replayBackendPrefix) "/"))
      (let [(name (sub backend 7 (stringLength backend)))]
        (match (loadTurns "Replay file" (str rootDir "/tests/fixtures/agentLoop/recorded/" name) parseReplayLines)
          ((ok turns) (ok (replayProvider (str "replay/" name) rootDir turns 0 (replayVendor name))))
          ((err e) (err e)))))
    ((or (= backend "agy") (or (= backend "codex") (= backend "claude")))
      (let [(sid (if (stringEmpty? sessionId) (uniqueTag) sessionId))]
          (ok (vendorProvider (VendorConfig :vendor backend :mode (if (stringEmpty? mode) "scout" mode) :rootDir (absPath rootDir)
                                :model model :timeout (if (= timeout 0) 600 timeout) :queueTimeout (if (= queueTimeout 0) 1200 queueTimeout)
                                :sessionId sid :intent (if (stringEmpty? intent) "auto" intent) :timeoutSet timeoutSet :env env :link none :turn 0)))))
    (else (err (valueError (str "Unknown backend: " backend)))))

fn providerName p: Provider -> String
  (match p
    ((scriptProvider name _ _) name)
    ((scriptFixtureProvider name _ _) name)
    ((replayProvider name _ _ _ _) name)
    ((vendorProvider cfg) cfg.vendor))

fn vendorName p: Provider -> (Option String)
  (match p
    ((scriptProvider _ _ _) none)
    ((scriptFixtureProvider _ _ _) none)
    ((replayProvider _ _ _ _ v) (if (stringEmpty? v) none (some v)))
    ((vendorProvider cfg) (some cfg.vendor)))

fn splitContext p: Provider -> Bool
  (match p ((vendorProvider _) true) (_ false))

fn ! lockLoop path: String -> (Result Int64 ProviderError)
  (match (fileLock path true)
    ((ok fd) (ok fd))
    ((err e) (if (= e "busy") (do (sleepMs 20) (lockLoop path)) (err (ioError (str path ": " e))))))

fn ! replayLock root: String vendor: String -> (Result Int64 ProviderError)
  (if (stringEmpty? vendor)
    (ok -1)
    (let [(dir (str root "/.asl/run/agentLoop"))]
      (match (makeDirs dir)
        ((err e) (err e))
        ((ok _) (lockLoop (str dir "/" vendor ".lock"))))))

fn nth xs: (List String) i: Int64 -> (Option String)
  (if (>= i (listLength xs)) none (listGet xs i))

fn setIntent cfg: VendorConfig intent: String -> VendorConfig
  (with cfg :intent intent)

fn withTurn cfg: VendorConfig turn: Int64 -> VendorConfig
  (with cfg :turn turn)

; (:m :ref LEONATTR :do "a non-empty prefill rides as a trailing assistant message of the profile chat call; an empty one leaves the request as before; script and replay providers have no transport and pass through")
fn cfgPrefill cfg: VendorConfig prefill: String -> VendorConfig
  (with cfg :prefill prefill)

; (:m :ref PROTO-STUDY :do "native tool schemas ride on the config like the prefill; an empty list sends no tools key and keeps the ASN wire")
fn cfgTools cfg: VendorConfig tools: (List j/Json) -> VendorConfig
  (if cfg.noTools cfg (with cfg :tools tools))

fn withTools p: Provider tools: (List j/Json) -> Provider
  (match p
    ((vendorProvider cfg) (vendorProvider (cfgTools cfg tools)))
    (_ p))

; (:m :ref PROTO-STUDY :do "the ASN wire carries only text content, so a call that offers tools asks for JSON, whose message keeps its tool_calls")
fn acceptHeader tools: (List j/Json) -> (List (Pair String String))
  (if (listEmpty? tools) (list) (list (pair "Accept" "application/json")))

fn hasAccept headers: (List (Pair String String)) -> Bool
  (not (listEmpty? (filter (fn [h] (= (stringLower (pairFirst h)) "accept")) headers)))

fn withPrefill p: Provider prefill: String -> Provider
  (match p
    ((vendorProvider cfg) (vendorProvider (cfgPrefill cfg prefill)))
    (_ p))

; (:m :ref LEONATTR :do "the messages a provider would send on the profile chat call; callProfile! builds its request from the same cfg.prefill")
fn outgoingMessages p: Provider system: String user: String -> (List j/Json)
  (match p
    ((vendorProvider cfg) (profileMessages system user cfg.prefill))
    (_ (profileMessages system user "")))

fn profileMessages system: String user: String prefill: String -> (List j/Json)
  (listAppend (list (msg "system" system) (msg "user" user))
              (if (stringEmpty? prefill) (list) (list (msg "assistant" prefill))))

fn withLink cfg: VendorConfig link: gs/GatewayLoop -> VendorConfig
  (with cfg :link (some link))

fn ! runCli! cfg: VendorConfig tool: String args: (List String) cwd: String input: String -> (Result cp/ProcessOutput ProviderError)
  (let [(base (cp/withStdin (cp/withTimeout (cp/withCwd (cp/cmd tool args) cwd) (* cfg.timeout 1000)) input))
        (c (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv))) base (mapPairs cfg.env.childEnv)))]
    (match (cp/exec! c)
      ((ok out) (ok out))
      ((err pe)
        (match pe
          ((cp/notFound _) (err (toolAbsent tool (str "[Errno 2] No such file or directory: " (pyReprString tool)))))
          ((cp/permissionDenied _) (err (toolAbsent tool (str "[Errno 13] Permission denied: " (pyReprString tool)))))
          ((cp/timeout _) (err (cliTimeout (cons tool args) cfg.timeout)))
          ((cp/executionFailed _ m) (err (ioError (str tool ": " m))))))))

fn ! freshDir! base: String prefix: String tagFor: (fn [Int64] -> String) attempt: Int64 -> (Result String ProviderError)
  (let [(dir (str base "/" prefix (tagFor attempt)))]
    (cond
      ((>= attempt 1000) (err (ioError (str "no free scratch name under " base))))
      ((ok? (fileStat dir)) (freshDir! base prefix tagFor (+ attempt 1)))
      (else (match (makeDirs dir) ((ok _) (ok dir)) ((err e) (err e))))))

fn ! tempDir! cfg: VendorConfig prefix: String -> (Result String ProviderError)
  (let [(base cfg.env.tmpDir)
        (count (match (dirList base) ((ok names) (listLength names)) ((err _) 0)))]
    (freshDir! base prefix (fn [attempt] (saltedTag (str (stringFromInt64 count) "." (stringFromInt64 attempt)))) 0))

fn ! removeIfEmpty dir: String -> Bool
  (match (dirList dir)
    ((ok names) (if (listEmpty? names) (ok? (pathRemove dir)) false))
    ((err _) false))

fn ! inTempDir! cfg: VendorConfig prefix: String tool: String args: (List String) input: String -> (Result cp/ProcessOutput ProviderError)
  (match (tempDir! cfg prefix)
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
    (match (makeDirs dir)
      ((err e) (err e))
      ((ok _)
        (match (writeText instr (str system "\n"))
          ((err e) (err e))
          ((ok _)
            (match (inTempDir! cfg "asl_codex_cwd_" "codex" args user)
              ((err e) (err e))
              ((ok out)
                (if (isFile? last)
                  (match (readText last) ((ok t) (ok (some (pyStrip t)))) ((err e) (err e)))
                  (ok (if (= out.exitCode 0) (some (pyStrip (universalNewlines out.stdout))) none))))))))))

fn ! callClaude! cfg: VendorConfig system: String user: String -> (Result (Option String) ProviderError)
  (let [(args (listAppend (list "-p" "--system-prompt" system "--tools" "" "--setting-sources" "" "--output-format" "json" "--no-session-persistence")
                          (if (stringEmpty? cfg.model) (list) (list "--model" cfg.model))))]
    (match (inTempDir! cfg "asl_claude_cwd_" "claude" args user)
      ((err e) (err e))
      ((ok out)
        (if (!= out.exitCode 0)
          (ok none)
          (let [(text (universalNewlines out.stdout))]
            (match (j/jsonParse text)
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
         (if (hasAccept headers) "" (hdr "Accept" "application/asn+sexpr"))
         (stringJoin (map (fn [p] (hdr (pairFirst p) (pairSecond p))) headers) "")
         "header = \"Expect:\"\n"
         "data-raw = " (configQuote body) "\n"
         "max-time = " (configQuote maxTime) "\n"
         (if loopback "noproxy = \"*\"\n" "")))

fn headEnd out: String -> (Pair Int64 Int64)
  (match (stringIndexOf out "\r\n\r\n")
    ((some i) (pair i (+ i 4)))
    (none (match (stringIndexOf out "\n\n")
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
      (match (stringToInt64 (sub line s0 s1))
        ((some code) (some (pair code (pyStrip (sub line r0 n)))))
        (none none))))

fn headerValue lines: (List String) name: String -> String
  (match (listHead (filter (fn [l] (match (stringIndexOf l ":")
                                   ((some c) (= (stringLower (pyStrip (sub l 0 c))) name))
                                   (none false)))
                        lines))
    ((some l) (pyStrip (sub l (+ (optionOr (stringIndexOf l ":") 0) 1) (stringLength l))))
    (none ""))

; (:m :ref HUB-QUEUE-PACED :do "a 429's Retry-After header rides in the status reason as [retry-after=N] so the error text carries it to the caller; other statuses are untouched")
fn withRetryAfter st: (Pair Int64 String) header: String -> (Pair Int64 String)
  (if (and (= (pairFirst st) 429) (not (stringEmpty? header)))
    (pair (pairFirst st) (str (pairSecond st) " [retry-after=" header "]"))
    st)

fn retryAfterSec message: String -> Int64
  (match (stringIndexOf message "[retry-after=")
    ((none) 0)
    ((some at)
      (let [(rest (sub message (+ at 13) (stringLength message)))]
        (optionOr (stringToInt64 (optionOr (listHead (stringSplit rest "]")) "")) 0))))

fn parseCurlResponse out: String -> (Result (Pair (Pair Int64 String) (Pair String String)) String)
  (let [(he (headEnd out))
        (lines (headLines (sub out 0 (pairFirst he))))
        (rest (sub out (pairSecond he) (stringLength out)))]
    (match (statusOf (optionOr (listHead lines) ""))
      (none (err "gateway reply has no HTTP status line"))
      ((some st)
        (if (and (>= (pairFirst st) 100) (< (pairFirst st) 200))
          (parseCurlResponse rest)
          (ok (pair (withRetryAfter st (headerValue (listDrop lines 1) "retry-after")) (pair (headerValue (listDrop lines 1) "content-type") rest)))))))

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
  (match (stringIndexOf url ":")
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
  (match v ((j/jnull) "NoneType") ((j/jarr _) "list") ((j/jobj _) "dict") (_ "str"))

fn pyFloat v: j/Json -> (Result Float64 ProviderError)
  (match v
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
            (else (match (stringToFloat64 t)
                    ((some f) (ok f))
                    ((none) (err (valueError (str "could not convert string to float: " (pyReprString s)))))))))
        (err (valueError (str "could not convert string to float: " (pyReprString s))))))
    (_ (err (valueError (str "float() argument must be a string or a real number, not '" (pyTypeName v) "'")))))

fn numOr fields: (List (Pair String j/Json)) k: String -> Float64
  (match (dictGet fields k)
    ((some v) (match v ((j/jint i) (int64ToFloat64 i)) ((j/jfloat f) f) (_ 0.0)))
    (none 0.0))

fn numOrZero fields: (List (Pair String j/Json)) k: String -> j/Json
  (optionOr (dictGet fields k) (j/jint 0))

fn mkMeta timing: (Option Timing) usage: (Option (List (Pair String j/Json))) served: (Option (List (Pair String String))) finish: (Option String) -> TurnMeta
  (TurnMeta :timing timing :usage usage :served served :finish finish :truncated (= finish (some "length")))

fn readAsnReply text: String -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (match (parseAsnReply text)
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
            (let [(timingR (match (dictGet fields "asl")
                             ((some a) (match (asnNumbers a)
                                         ((ok nums) (ok (some (Timing :queueWaitSec (numOr nums "queueWaitSec") :execSec (numOr nums "execSec")))))
                                         ((err e) (err e))))
                             (none (ok none))))
                  (usageR (asnNumbers (field "usage" "")))]
              (match timingR
                ((err e) (pair (err e) (emptyMeta)))
                ((ok timing)
                  (match usageR
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
  (let [(pick (fn [a b] (match (jsonLookup asl a)
                          ((some v) (match v ((j/jnull) (optionOr (jsonLookup asl b) (j/jfloat 0.0))) (_ v)))
                          (none (optionOr (jsonLookup asl b) (j/jfloat 0.0))))))]
    (match (pyFloat (pick "queueWaitSec" "queue_wait_sec"))
      ((err e) (err e))
      ((ok qw) (match (pyFloat (pick "execSec" "exec_sec"))
                 ((err e) (err e))
                 ((ok es) (ok (Timing :queueWaitSec qw :execSec es)))))))

fn replyContent resp: j/Json -> (Result (Option String) ProviderError)
  (let [(choices (optionOr (jsonLookup resp "choices") (j/jnull)))
        (noReply (fn [m] (err (gatewayError "ERR_NO_REPLY" m ""))))]
    (match choices
      ((j/jarr xs)
        (match (listHead xs)
          (none (noReply "Empty choices in gateway response"))
          ((some c0)
            (if (not (isObject c0))
              (err (gatewayError "ERR_VENDOR" "Gateway choice is not an object" ""))
              (let [(msg (optionOr (jsonLookup c0 "message") (j/jobj (list))))]
                (if (not (isObject msg))
                  (err (gatewayError "ERR_VENDOR" "Gateway message is not an object" ""))
                  (let [(calls (match (optionOr (jsonLookup msg "tool_calls") (j/jnull)) ((j/jarr xs) xs) (_ (list))))
                        (content (match (optionOr (jsonLookup msg "content") (j/jnull)) ((j/jnull) "") ((j/jstr s) s) (v (pyStr v))))]
                    ; (:m :ref PROTO-STUDY :do "a native tool call reads back as the ASN form it names, after any text content")
                    (if (not (listEmpty? calls))
                      (ok (some (pyStrip (nt/callsText content calls))))
                      (match (optionOr (jsonLookup msg "content") (j/jnull))
                        ((j/jnull) (noReply "Empty content in gateway response"))
                        ((j/jstr s) (if (stringEmpty? (pyStrip s)) (noReply "Empty content in gateway response") (ok (some (pyStrip s)))))
                        (v (ok (some (pyStrip (pyStr v))))))))))))))
      (_ (noReply "Empty choices in gateway response"))))

; (:m :ref JOURNAL-USAGE-ROWS :do "a gateway or hub that answers the plain OpenAI usage block (no asl envelope) still reports tokens: prompt_tokens is the input, prompt_tokens_details.cached_tokens the cached share, completion_tokens the output; a reply without prompt_tokens has no usage")
fn openAiUsage resp: j/Json -> (Option (List (Pair String j/Json)))
  (match (jsonLookup resp "usage")
    ((some u)
     (if (and (isObject u) (some? (jsonLookup u "prompt_tokens")))
       (some (list (pair "inputTokens" (optionOr (jsonLookup u "prompt_tokens") (j/jint 0)))
                   (pair "cachedTokens" (match (jsonLookup u "prompt_tokens_details")
                                          ((some d) (if (isObject d) (optionOr (jsonLookup d "cached_tokens") (j/jint 0)) (j/jint 0)))
                                          ((none) (j/jint 0))))
                   (pair "outputTokens" (optionOr (jsonLookup u "completion_tokens") (j/jint 0)))))
       none))
    ((none) none))

fn readJsonReply body: String -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (match (j/jsonParse body)
    ((err e) (pair (err (gatewayError "ERR_VENDOR" (str "Failed to parse gateway JSON response: " e) "")) (emptyMeta)))
    ((ok resp)
      (if (not (isObject resp))
        (pair (err (gatewayError "ERR_VENDOR" "Failed to parse gateway JSON response: not an object" "")) (emptyMeta))
        (let [(asl (optionOr (jsonLookup resp "asl") (j/jnull)))
              (aslIsDict (isObject asl))]
          (match (if aslIsDict (match (timingOf asl) ((ok t) (ok (some t))) ((err e) (err e))) (ok none))
            ((err e) (pair (err e) (emptyMeta)))
            ((ok timing)
              (let [(usageV (if aslIsDict (jsonLookup asl "usage") none))
                    (internalUsage (match usageV
                             ((some u) (if (isObject u)
                                         (some (map (fn [k] (pair k (optionOr (jsonLookup u k) (j/jint 0)))) (list "inputTokens" "cachedTokens" "outputTokens")))
                                         none))
                             (none none)))
                    (usage (match internalUsage ((some u) (some u)) ((none) (openAiUsage resp))))
                    (served (servedFields (dictPut (jsonDict asl) "model" (optionOr (jsonLookup resp "model") (j/jnull)))))
                    (meta (TurnMeta :timing timing :usage usage :served served :finish none :truncated false))]
                (pair (replyContent resp) meta))))))))

fn httpErrorBody body: String -> String
  (if (stringStartsWith? (pyLstrip body) "(:error")
    (match (parseAsnReply body)
      ((ok hf) (optionOr (dictGet (pairSecond hf) "reason") body))
      ((err _) body))
    body)

fn httpError service: String code: Int64 reason: String raw: String -> ProviderError
  (let [(body (httpErrorBody raw))
        (c (stringFromInt64 code))]
    (cond
      ((= code 413) (gatewayError "ERR_CONTEXT_TOO_LONG" (pyStrip (str service " 413: " body)) ""))
      ((or (= code 504) (stringContains? body "QUEUE_TIMEOUT")) (gatewayError "ERR_QUEUE_TIMEOUT" (str service " queue timeout: " c " " body) ""))
      (else (gatewayError "ERR_VENDOR" (pyStrip (str service " HTTP error " c ": " reason " " body)) ""))))

fn transportText out: cp/ProcessOutput -> String
  (let [(e (pyStrip out.stderr))]
    (if (stringEmpty? e) (str "curl exit " (stringFromInt64 out.exitCode)) e))

fn readCurl service: String hint: String url: String out: cp/ProcessOutput -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (cond
    ((= out.exitCode 28)
      (pair (err (gatewayError "ERR_VENDOR" (str service " timed out waiting for reply: " (transportText out)) "")) (emptyMeta)))
    ((!= out.exitCode 0)
      (pair (err (gatewayError "ERR_GATEWAY_OFFLINE" (str service " unreachable at " url ": " (transportText out) (if (stringEmpty? hint) "" (str "; " hint))) hint)) (emptyMeta)))
    (else (readResponse service out.stdout)))

fn readResponse service: String raw: String -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (match (parseCurlResponse raw)
    ((err e) (pair (err (gatewayError "ERR_VENDOR" (str service " reply unreadable: " e) "")) (emptyMeta)))
    ((ok r)
      (let [(code (pairFirst (pairFirst r)))
            (ctype (pairFirst (pairSecond r)))
            (body (pairSecond (pairSecond r)))]
        (cond
          ((or (< code 200) (>= code 300)) (pair (err (httpError service code (pairSecond (pairFirst r)) body)) (emptyMeta)))
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

; (:m :ref GW-CONFIG-PATH-SUFFIX :do "the suffix rule is structural, not security: linkOpen! takes a HOME and derives the config, the secrets file, the ledger and the sessions store from HOME/.asl, so a config elsewhere would split them from its own home; the refusal is typed ERR_CONFIG_PATH and names the rule and the path")
fn configPathRefusal config: String -> ProviderError
  (gatewayError "ERR_CONFIG_PATH"
    (str "in-process gateway config path must end in /.asl/gateway.asn (its HOME is the part before /.asl, where the secrets, ledger and sessions also live); got " config)
    "put the config at <home>/.asl/gateway.asn and set ASL_GATEWAY_CONFIG to it or HOME to <home>, or set ASL_GATEWAY_URL for an HTTP gateway")

fn ! openLink! cfg: VendorConfig -> (Result gs/GatewayLoop ProviderError)
  (match cfg.link
    ((some l) (ok l))
    ((none)
      (let [(config cfg.env.gatewayConfig)
            (env (fold (fn [acc kv] (mapSet acc (pairFirst kv) (pairSecond kv))) (gu/envMapFromList (envList)) (mapPairs cfg.env.childEnv)))
            (root (optionOr (mapGet env "ASL_GATEWAY_ROOT") (optionOr (mapGet env "ROOT_DIR") cfg.rootDir)))]
        (match (configHome config)
          ((none) (err (configPathRefusal config)))
          ((some home)
            (match (gs/linkOpen! env home root (gd/builtinFamilies))
              ((err e) (err (gatewayError "ERR_GATEWAY_CONFIG" (str "in-process gateway: " e) "set ASL_GATEWAY_URL for an HTTP gateway")))
              ((ok l) (ok l))))))))

; (:m :effect net)
fn ! linkGateway! cfg: VendorConfig payload: j/Json headers: (List (Pair String String)) -> Called
  (match (openLink! cfg)
    ((err e) (Called :reply (err e) :meta (emptyMeta) :cfg cfg))
    ((ok l)
      (let [(body (pyJsonDumps payload))
            (sent (listAppend (cons (pair "Content-Type" "application/json") (if (hasAccept headers) (list) (list (pair "Accept" "application/asn+sexpr"))))
                    (listAppend headers (list (pair "Content-Length" (stringFromInt64 (bytesLength (stringToBytes body))))))))
            (out (gs/linkSend! l "POST" "/v1/chat/completions" sent body (* (+ (+ cfg.timeout cfg.queueTimeout) 30) 1000)))
            (next (withLink cfg (pairFirst out)))]
        (match (pairSecond out)
          ((err e) (Called :reply (err (gatewayError "ERR_VENDOR" (str "in-process gateway: " e) "")) :meta (emptyMeta) :cfg next))
          ((ok raw) (called next (readResponse "Gateway" raw)))))))

; (:m :ref ORCH-LEON-CLIENT :do "the hub transport is read from HOME/.asl/hub.asn (the home of the gateway config), never from env: a :sock names the unix socket of the one-per-node hub, calls carry X-Asl-Class and X-Asl-Unit, and a refused connection or an HTTP 503 from the hub (its accept limit) is a wait, retried at :backoffMs doubling until :downAfterMs has passed, then ERR_GATEWAY_DOWN for a refused connection and the 503 error itself for a busy hub; with :fallback inProcess the down hub falls back to the in-process link, with no hub.asn the older gateway path is unchanged")
fn hubAsnPath cfg: VendorConfig -> String
  (match (configHome cfg.env.gatewayConfig)
    ((some home) (str home "/.asl/hub.asn"))
    (none (str (envOr! "HOME" "") "/.asl/hub.asn")))

fn hubAsnString text: String key: String fallback: String -> String
  (match (stringIndexOf text (str ":" key " \""))
    (none fallback)
    ((some at)
      (let [(rest (sub text (+ at (+ 3 (stringLength key))) (stringLength text)))]
        (match (stringIndexOf rest "\"")
          (none fallback)
          ((some end) (sub rest 0 end))))))

fn hubAsnInt text: String key: String fallback: Int64 -> Int64
  (match (stringIndexOf text (str ":" key " "))
    (none fallback)
    ((some at)
      (let [(rest (sub text (+ at (+ 2 (stringLength key))) (stringLength text)))
            (token (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ")")) "") " ")) ""))]
        (optionOr (stringToInt64 token) fallback))))

fn hubHeaders cfg: VendorConfig class: String headers: (List (Pair String String)) -> (List (Pair String String))
  (listAppend headers
    (listAppend (list (pair "X-Asl-Class" class))
      (if (stringEmpty? cfg.sessionId) (list) (list (pair "X-Asl-Unit" cfg.sessionId)))))

; (:m :effect net)
; (:m :ref HUB-QUEUE-PACED :do "a 429 whose Retry-After fits what is left of the queue timeout is waited out and reposted; a longer one is the caller's error")
fn ! hubPost! cfg: VendorConfig sock: String payload: j/Json headers: (List (Pair String String)) delayMs: Int64 waitedMs: Int64 capMs: Int64 -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (let [(r (postUrlVia! cfg "http://hub/v1/chat/completions" sock "Hub" "start the hub (asl/tools/hub/main.asl serve)" payload headers))]
    (match (pairFirst r)
      ((err e)
        (let [(busy (stringContains? (errorMessage e) "Hub HTTP error 503"))
              (askedMs (* 1000 (retryAfterSec (errorMessage e))))]
          (if (and (stringContains? (errorMessage e) "Hub HTTP error 429") (and (> askedMs 0) (<= (+ waitedMs askedMs) (* 1000 cfg.queueTimeout))))
            (do (sleepMs askedMs) (hubPost! cfg sock payload headers delayMs (+ waitedMs askedMs) capMs))
          (if (not (or busy (= (errorCode e) "ERR_GATEWAY_OFFLINE"))) r
            (if (>= waitedMs capMs)
              (if busy r (pair (err (gatewayError "ERR_GATEWAY_DOWN" (str "hub socket " sock " refused connections for " (stringFromInt64 waitedMs) " ms: " (errorMessage e)) "start the hub or declare :fallback inProcess in hub.asn")) (emptyMeta)))
              (do (sleepMs delayMs) (hubPost! cfg sock payload headers (* delayMs 2) (+ waitedMs delayMs) capMs)))))))
      (_ r)))

fn ! sendGateway! cfg: VendorConfig payload: j/Json headers: (List (Pair String String)) -> Called
  (let [(hub (resultOr (fileReadString (hubAsnPath cfg)) ""))
        (sock (hubAsnString hub "sock" ""))]
    (cond
      ((not (stringEmpty? sock))
        (let [(hdrs (hubHeaders cfg (hubAsnString hub "class" "free") headers))]
          (if cfg.defer
            (Called :reply (ok none) :meta (emptyMeta) :cfg (withHub cfg (HubCall :sock sock :body (pyJsonDumps payload) :headers hdrs)))
            (let [(r (hubPost! cfg sock payload hdrs (hubAsnInt hub "backoffMs" 1000) 0 (hubAsnInt hub "downAfterMs" 30000)))]
              (if (and (stringContains? hub ":fallback inProcess")
                       (match (pairFirst r) ((err e) (= (errorCode e) "ERR_GATEWAY_DOWN")) (_ false)))
                (linkGateway! cfg payload headers)
                (called cfg r))))))
      (cfg.env.inProcess (linkGateway! cfg payload headers))
      (else (called cfg (postGateway! cfg payload headers)))))

; (:m :effect net)
fn unixLine sock: String -> String
  (if (stringEmpty? sock) "" (str "unix-socket = " (configQuote sock) "\n"))

fn ! postUrl! cfg: VendorConfig url: String service: String hint: String payload: j/Json headers: (List (Pair String String)) -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (postUrlVia! cfg url "" service hint payload headers)

; (:m :effect net)
fn ! postUrlVia! cfg: VendorConfig url: String sock: String service: String hint: String payload: j/Json headers: (List (Pair String String)) -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (let [(body (pyJsonDumps payload))
        (maxTime (stringFromFloat64 (int64ToFloat64 (+ (+ cfg.timeout cfg.queueTimeout) 30))))
        (bad (filter (fn [p] (illegalHeaderValue (pairSecond p))) headers))]
    (cond
      ((not (urlHasScheme url)) (pair (err (valueError (str "unknown url type: " (pyReprString url)))) (emptyMeta)))
      ((not (listEmpty? bad)) (pair (err (valueError (str "Invalid header value " (pyReprBytes (pairSecond (optionOr (listHead bad) (pair "" ""))))))) (emptyMeta)))
      (else
        (let [(conf (str (unixLine sock) (curlConfig url body headers maxTime (isLoopback url))))
              (c0 (cp/withStdin (cp/withTimeout (cp/cmd "curl" (list "--config" "-")) (* (+ (+ cfg.timeout cfg.queueTimeout) 60) 1000)) conf))
              (c (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv))) c0 (mapPairs cfg.env.childEnv)))]
          (match (cp/exec! c)
            ((ok out) (readCurl service hint url out))
            ((err pe)
              (match pe
                ((cp/notFound _) (pair (err (toolAbsent "curl" (str "curl is not installed; the " service " call needs it (capabilities.asn :externalTools curl)"))) (emptyMeta)))
                ((cp/timeout _) (pair (err (gatewayError "ERR_VENDOR" (str service " timed out waiting for reply: curl did not exit") "")) (emptyMeta)))
                (_ (pair (err (gatewayError "ERR_GATEWAY_OFFLINE" (str service " unreachable at " url ": curl could not start" (if (stringEmpty? hint) "" (str "; " hint))) hint)) (emptyMeta))))))))))

; (:m :effect net)
fn ! postGateway! cfg: VendorConfig payload: j/Json headers: (List (Pair String String)) -> (Pair (Result (Option String) ProviderError) TurnMeta)
  (postUrl! cfg cfg.env.gatewayUrl "Gateway" "run ./bin/asl-gateway start" payload headers)

fn msg role: String content: String -> j/Json
  (j/jobj (list (pair "role" (j/jstr role)) (pair "content" (j/jstr content))))

; (:m :ref GW-EMPTY-TOOLS-20261019 :do "IFM ifmK2Horizon intermittently answers HTTP 400 'tools must not be an empty array' for a request carrying an empty tools array; callProfile! and callAgy! always sent one ((pair \"tools\" (j/jarr (list)))). Neither call site has a real tools source yet (no VendorConfig field, no caller ever builds a non-empty list), so today this always omits the key -- but the rule is general, not a special case for 'always empty': a tools list is only ever named in the body when it is non-empty")
fn toolsField tools: (List j/Json) -> (List (Pair String j/Json))
  (if (listEmpty? tools) (list) (list (pair "tools" (j/jarr tools))))

; (:m :ref TOOLS-400-FALLBACK :do "a route that answers HTTP 400 to a request carrying tools cannot take native tools (a tool-less model, or a gateway that rejects the schema): the turn is retried once without them, in the text protocol, and the config remembers the route as no-tools; a 400 without tools is an ordinary error")
; (:m :ref TOOLS-400-OBSERVE :do "a 400 whose body names a context, length or token limit is the request being too big, not the tools being refused: no fallback, the error stands (dropping the tools would not shrink it)")
fn sizeLimit? text: String -> Bool
  (let [(low (stringLower text))]
    (or (stringContains? low "context") (or (stringContains? low "length") (stringContains? low "token"))))

fn toolsRejected? reply: (Result (Option String) ProviderError) -> Bool
  (match reply
    ((err e) (and (stringContains? (errorMessage e) "HTTP error 400") (not (sizeLimit? (errorMessage e)))))
    ((ok _) false))

; (:m :ref TOOLS-400-OBSERVE :do "records the fallback in the session journal so a run's text-protocol turns are explained after the fact; no session or a failed write records nothing and never fails the turn")
fn ! noteFallback! cfg: VendorConfig model: String reply: (Result (Option String) ProviderError) -> Bool
  (match reply
    ((err e)
     (if (stringEmpty? cfg.sessionId)
       false
       (match (jr/journalWrite (sessionJournal cfg) (jr/fallbackRowText model 400 (errorMessage e)))
         ((ok _) true)
         ((err _) false))))
    ((ok _) false))

; (:m :effect net)
fn ! callProfile! cfg: VendorConfig system: String user: String model: String -> Called
  (let [(once (callProfileOnce! cfg system user model))]
    (if (and (not (listEmpty? cfg.tools)) (toolsRejected? once.reply))
      (do (noteFallback! cfg model once.reply)
        (callProfileOnce! (with cfg :tools (list) :noTools true) system user model))
      once))

; (:m :effect net)
fn ! callProfileOnce! cfg: VendorConfig system: String user: String model: String -> Called
  (let [(ws (absPath (str cfg.rootDir "/.asl/run/agentLoop/agents/" cfg.sessionId)))
        (profile cfg.env.profile)
        (headers (listAppend
                   (if (and (= model "profile") (not (stringEmpty? profile))) (list (pair "X-ASL-Profile" profile)) (list))
                   (listAppend (if (stringEmpty? cfg.sessionId) (list) (list (pair "X-ASL-Session" cfg.sessionId))) (listAppend (attribHeaders cfg) (acceptHeader cfg.tools)))))
        (payload (j/jobj (listAppend
                           (listAppend
                             (list (pair "model" (j/jstr model))
                                   (pair "intent" (j/jstr cfg.intent))
                                   (pair "messages" (j/jarr (profileMessages (if (listEmpty? cfg.tools) system (str system (nt/toolsHint))) user cfg.prefill))))
                             (listAppend (toolsField cfg.tools) (list (pair "workspace" (j/jstr ws)))))
                           (listAppend (if cfg.timeoutSet (list (pair "timeout" (j/jint cfg.timeout))) (list))
                                       (list (pair "queue_timeout" (j/jint cfg.queueTimeout)))))))]
    (match (makeDirs ws)
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
              (payload (j/jobj (listAppend
                                 (list (pair "model" (j/jstr (if (stringStartsWith? model "agy/") model (str "agy/" model))))
                                       (pair "messages" (j/jarr (list (msg "user" user))))
                                       (pair "agent" (j/jstr agent)))
                                 (listAppend (toolsField (list))
                                   (list (pair "addDirs" (j/jarr (list (j/jstr root))))
                                         (pair "workspace" (j/jstr root))
                                         (pair "timeout" (j/jint cfg.timeout))
                                         (pair "queue_timeout" (j/jint cfg.queueTimeout)))))))
              (written (match (makeDirs (str pluginDir "/agents"))
                         ((err e) (err e))
                         ((ok _) (match (writeText (str pluginDir "/plugin.json") (pyJsonDumps (j/jobj (list (pair "name" (j/jstr "aslLoop"))))))
                                   ((err e) (err e))
                                   ((ok _) (writeText (str pluginDir "/agents/" agent ".md") (agentFileText agent system)))))))]
          (match written
            ((err e) (Called :reply (err e) :meta (emptyMeta) :cfg cfg))
            ((ok _) (sendGateway! cfg payload (listAppend (if (stringEmpty? cfg.sessionId) (list) (list (pair "X-ASL-Session" cfg.sessionId))) (attribHeaders cfg)))))))))

; (:m :ref LEON-ATTRIB-20261028 :do "every gateway call names its consumer (leon) and, once the first main turn has run, the turn number, so the gateway ledger row joins the session by X-ASL-Session; advisor and grader calls carry the turn of the last main turn, and a call made before any turn carries no turn header")
fn attribHeaders cfg: VendorConfig -> (List (Pair String String))
  (listAppend (list (pair "X-ASL-Consumer" "leon"))
    (if (> cfg.turn 0) (list (pair "X-ASL-Turn" (stringFromInt64 cfg.turn))) (list)))

fn ! callVendor! cfg: VendorConfig system: String user: String -> Called
  (cond
    ((= cfg.vendor "agy") (callAgy! cfg system user))
    ((= cfg.vendor "codex") (Called :reply (callCodex! cfg system user) :meta (emptyMeta) :cfg cfg))
    ((= cfg.vendor "claude") (Called :reply (callClaude! cfg system user) :meta (emptyMeta) :cfg cfg))
    (else (Called :reply (err (valueError (str "Unknown vendor: " cfg.vendor))) :meta (emptyMeta) :cfg cfg)))

fn stepTurns turns: (List String) index: Int64 -> (Pair (Option String) Int64)
  (match (nth turns index)
    ((some r) (pair (some r) (+ index 1)))
    (none (pair none index)))

; (:m :ref JOURNAL-USAGE-ROWS :do "appends the reply's usage to the session journal at rootDir/.asl/run/agentLoop/<session>.journal, the path the loop's own rows use; no usage or no session writes nothing, a failed write returns false and never fails the turn")
fn sessionJournal cfg: VendorConfig -> String
  (jr/pathJoin (jr/pathJoin cfg.rootDir ".asl/run/agentLoop") (str cfg.sessionId ".journal"))

fn ! logUsage! cfg: VendorConfig meta: TurnMeta -> Bool
  (match meta.usage
    ((none) false)
    ((some fields)
     (if (stringEmpty? cfg.sessionId)
       false
       (let [(num (fn [k] (match (optionOr (jsonLookup (j/jobj fields) k) (j/jint 0)) ((j/jint n) n) (_ 0))))
             (model (match meta.served ((some s) (optionOr (dictGet s "model") cfg.model)) ((none) cfg.model)))
             (path (sessionJournal cfg))]
         (match (jr/journalWrite path (jr/usageRowText (num "inputTokens") (num "cachedTokens") (num "outputTokens") model))
           ((ok _) true)
           ((err _) false))))))

fn ! nextTurn! p: Provider system: String user: String -> Turn
  (match p
    ((scriptProvider name turns index)
      (let [(s (stepTurns turns index))]
        (Turn :provider (scriptProvider name turns (pairSecond s)) :reply (ok (pairFirst s)) :meta (emptyMeta))))
    ((scriptFixtureProvider name fixture index)
      (let [logged (match fixture.attemptLogPath
                    ((some logPath) (fileAppend logPath (str "(:attempt :ns " (stringFromInt64 (monotonicNs)) ")\n")))
                    ((none) (ok ())))]
        (match logged
          ((err e) (Turn :provider p :reply (err (ioError e)) :meta (emptyMeta)))
          ((ok _) (match (listGet fixture.turns index)
            (none (Turn :provider p :reply (ok none) :meta (emptyMeta)))
            ((some step)
              (Turn :provider (scriptFixtureProvider name fixture (+ index 1))
                :reply (match step.error
                  (none (ok step.reply))
                  ((some code) (err (providerError code (str "scripted provider failure: " code)))))
                :meta (TurnMeta :timing none :usage step.usage :served none :finish none :truncated false))))))))
    ((replayProvider name root turns index vendor)
      (match (replayLock root vendor)
        ((err e) (Turn :provider p :reply (err e) :meta (emptyMeta)))
        ((ok fd)
          (let [(s (stepTurns turns index))
                (released (if (>= fd 0) (fdClose fd) (ok ())))]
            (Turn :provider (replayProvider name root turns (pairSecond s) vendor)
                  :reply (match released ((ok _) (ok (pairFirst s))) ((err e) (err (ioError (str "unlock: " e)))))
                  :meta (emptyMeta))))))
    ((vendorProvider cfg)
      (let [(r (callVendor! (withTurn cfg (+ cfg.turn 1)) system user))]
        (do (logUsage! r.cfg r.meta)
          (Turn :provider (vendorProvider r.cfg) :reply r.reply :meta r.meta)))))

; (:m :ref SE1-PROVIDER-SPLIT :do "the turn cut at the network: nextTurnAsk! runs everything nextTurn! runs up to the hub post and, when the call would go to the hub socket, returns askHub with the provider (turn already counted) and the exact body, headers and socket instead of posting; every other provider and path (script, replay, cli vendors, in-process, HTTP gateway) returns askDone with the Turn nextTurn! gives. nextTurnReply turns the raw HTTP reply of an askHub into the Turn nextTurn! would have returned. A pool posts the call itself, without waiting, between the two")
enum Ask
  (askDone t: Turn)
  (askHub p: Provider call: HubCall)

fn withHub cfg: VendorConfig call: HubCall -> VendorConfig
  (with cfg :hub (some call))

fn withDefer cfg: VendorConfig on: Bool -> VendorConfig
  (with cfg :defer on :hub none)

fn ! nextTurnAsk! p: Provider system: String user: String -> Ask
  (match p
    ((vendorProvider cfg)
      (let [(r (callVendor! (withDefer (withTurn cfg (+ cfg.turn 1)) true) system user))
            (back (vendorProvider (withDefer r.cfg false)))]
        (match r.cfg.hub
          ((some h) (askHub back h))
          ((none) (do (logUsage! r.cfg r.meta) (askDone (Turn :provider back :reply r.reply :meta r.meta)))))))
    (_ (askDone (nextTurn! p system user))))

fn noToolsProvider cfg: VendorConfig -> Provider
  (vendorProvider (with cfg :tools (list) :noTools true))

fn ! nextTurnReply p: Provider raw: String -> Turn
  (let [(r (readResponse "Hub" raw))
        (logged (match p ((vendorProvider cfg) (logUsage! cfg (pairSecond r))) (_ false)))
        ; (:m :ref TOOLS-400-FALLBACK :do "the hub answer arrives after the turn was cut, so the retry cannot happen here: the failed turn stands and the provider goes back no-tools, so the next turn speaks the text protocol")
        (back (match p
                ((vendorProvider cfg)
                  (if (and (not (listEmpty? cfg.tools)) (toolsRejected? (pairFirst r)))
                    (noToolsProvider cfg)
                    p))
                (_ p)))]
    (Turn :provider back :reply (pairFirst r) :meta (pairSecond r)))

; (:m :ref SE1-PROVIDER-SPLIT :do "the hub answers 503 when it is busy: that is a wait for the caller, not a failure, the same rule hubPost! applies")
fn hubBusy? t: Turn -> Bool
  (match t.reply
    ((err e) (stringContains? (errorMessage e) "Hub HTTP error 503"))
    ((ok _) false))

fn ! advise! p: Provider system: String text: String -> (Option Turn)
  (match p
    ((scriptFixtureProvider name fixture index)
      (some (Turn :provider p :reply
        (match fixture.advisor
          ((some reply) (ok (some reply)))
          ((none) (err (providerError "ERR_NO_ADVISOR_CHANNEL" "ERR_NO_ADVISOR_CHANNEL provider has no advisor channel"))))
        :meta (emptyMeta))))
    ((vendorProvider cfg)
      (let [(r (callVendor! (setIntent cfg "reinforce") system text))]
        (some (Turn :provider (vendorProvider (setIntent r.cfg cfg.intent)) :reply r.reply :meta r.meta))))
    (_ none))

fn withProfile env: ProviderEnv profile: String -> ProviderEnv
  (with env :profile profile)

; (:m :ref LEON-WALLBUDGET-ORPHAN :do "a vendor call never gets more than the seconds left of the run's wall budget: queue and call timeouts are cut to fit, so the gateway link deadline lands near the budget")
fn capConfig cfg: VendorConfig left: Int64 -> VendorConfig
  (if (>= left (+ cfg.timeout cfg.queueTimeout))
    cfg
    (let [(q (min cfg.queueTimeout (/ left 4)))]
      (with cfg :queueTimeout q :timeout (max 1 (- left q)) :timeoutSet true)))

fn capTimeouts p: Provider left: Int64 -> Provider
  (match p
    ((vendorProvider cfg) (vendorProvider (capConfig cfg left)))
    (_ p))

fn graderConfig cfg: VendorConfig intent: String profile: String -> VendorConfig
  (with cfg :intent intent :model "" :env (if (stringEmpty? profile) cfg.env (withProfile cfg.env profile)))

fn noGraderChannel p: Provider -> Turn
  (Turn :provider p :reply
    (err (providerError "ERR_NO_GRADER_CHANNEL" "ERR_NO_GRADER_CHANNEL provider has no grader channel"))
    :meta (emptyMeta))

; (:m :ref LEON-CAPS :do "the grader call is its own request: the configured gateway intent and profile pick the grader, the writer's pinned model is dropped so the profile routes it; a scripted fixture answers from :gradeReply and reports :gradeModel as the served model, so the fake proves the wiring and the model comparison, not a model's judgement")
fn ! grade! p: Provider intent: String profile: String system: String text: String -> Turn
  (match p
    ((scriptFixtureProvider scriptName fixture scriptIndex)
      (match fixture.gradeReply
        ((some reply)
          (Turn :provider p :reply (ok (some reply))
            :meta (TurnMeta :timing none :usage none :finish none :truncated false
                    :served (match fixture.gradeModel ((some m) (some (list (pair "model" m)))) ((none) none)))))
        ((none)
          (match fixture.gradeError
            ((some message) (Turn :provider p :reply (err (providerError "ERR_VENDOR" message)) :meta (emptyMeta)))
            ((none) (noGraderChannel p))))))
    ((vendorProvider cfg)
      (let [(r (callVendor! (graderConfig cfg intent profile) system text))]
        (Turn :provider p :reply r.reply :meta r.meta)))
    (_ (noGraderChannel p)))

fn graderAvailable? p: Provider -> Bool
  (match p
    ((scriptFixtureProvider _ fixture _) (or (some? fixture.gradeReply) (some? fixture.gradeError)))
    ((vendorProvider _) true)
    (_ false))

fn ! review! p: Provider system: String text: String -> Turn
  (match p
    ((scriptFixtureProvider scriptName fixture scriptIndex)
      (match fixture.reviewer
        ((some reply) (Turn :provider p :reply (ok (some reply)) :meta (emptyMeta)))
        ((none) (Turn :provider p :reply
          (err (providerError "ERR_NO_REVIEWER_CHANNEL" "ERR_NO_REVIEWER_CHANNEL provider has no reviewer channel"))
          :meta (emptyMeta)))))
    ((vendorProvider vendorConfig) (let [turn (nextTurn! p system text)]
      (match turn.reply
        ((err e) turn)
        ((ok reply) (match reply
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
    (match (pathRemove path) ((ok _) (ok 0)) ((err e) (err (ioError e))))
    (ok 0))

fn ! cleanup! p: Provider -> (Result Int64 ProviderError)
  (match p
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
  (match (makeProvider! vendor mode rootDir model timeout "" queueTimeout false env "auto")
    ((err e) (err e))
    ((ok _) (buildDryRunInfoFor vendor mode rootDir model timeout queueTimeout env)))

fn ! buildDryRunInfoFor vendor: String mode: String rootDir: String model: String timeout: Int64 queueTimeout: Int64 env: ProviderEnv -> (Result j/Json ProviderError)
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
              (written (match (makeDirs (str pluginDir "/agents"))
                         ((err e) (err e))
                         ((ok _) (match (writeText (str pluginDir "/plugin.json") (pyJsonDumps (j/jobj (list (pair "name" (j/jstr "aslLoop"))))))
                                   ((err e) (err e))
                                   ((ok _) (writeText agentFile text))))))]
          (match written
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
          (match (makeDirs dir)
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
