(module aslGateway/upstream
  :x [UpstreamSettings
      UpstreamEndpoint
      TokenBucket
      BucketStep
      bucketAcquired
      bucketRefused
      bucketWait
      BucketRegistry
      RoleTokenPolicy
      UpstreamRequest
      UpstreamResponse
      UpstreamFailure
      toolAbsent
      transportFailure
      httpFailure
      protocolFailure
      joinAll
      replaceAll
      byteChar
      utf8Decode
      slice
      asciiChar
      utf8Next
      codepoints
      inRanges?
      isPySpace?
      pyDigitValue
      unicodeDigitRanges
      unicodeSpaceRanges
      pyStrip
      pyLower
      pyFloat
      objGet
      objSet
      typeName
      envMapFromList
      envGetOr
      upstreamSettings
      UpstreamProvider
      upstreamProviders
      upstreamFallback
      upstreamProviderNamed
      upstreamProviderEndpoint
      getUpstreamForModel
      getUpstreamForModelIn
      upstreamTimeoutSec
      upstreamTimeoutSecIn
      makeTokenBucket
      tokenBucketBegin
      tokenBucketFinish
      tokenBucketAcquire!
      emptyBucketRegistry
      geminiBucket
      bucketRegistryPut
      bucketRegistrySize
      geminiAcquire!
      reasoningModels
      coderCascade
      plannerCascade
      tokenFloorRoles
      minTokenFloor
      modelTokenFloors
      replyCeiling
      roleTokenPolicyTable
      emptyContentRetries
      aslMinimalHarness
      roleTokenPolicy
      emptyContentAction
      isEmptyContent?
      isReasoningModel?
      prepareRequestPayload
      applyHarnessPolicy
      headerGet
      harnessMode
      upstreamRequest
      childEnv
      curlArgv
      curlConfig
      curlConfigFollowing
      curlConfigLine
      parseCurlOutput
      httpErrorText
      UpstreamCall
      upstreamCallStart!
      upstreamCallStartFollowing!
      upstreamCallWatch
      upstreamCallOpen?
      upstreamCallPump!
      upstreamCallFinish!
      upstreamCallAbort!
      callUpstream!]
  :i [(asl-json/json :a j)])

(schema UpstreamSettings
  (:f geminiUrl String)
  (:f geminiKey String)
  (:f groqUrl String)
  (:f ollamaUrl String)
  (:f groqKey String)
  (:f url String)
  (:f key String)
  (:f ollamaTimeoutSec Float64))

(schema UpstreamEndpoint
  (:f provider String)
  (:f url String)
  (:f key String))

(schema UpstreamProvider
  (:f id String)
  (:f prefixes (List String))
  (:f names (List String))
  (:f url (fn [UpstreamSettings (Map String String)] -> String))
  (:f key (fn [UpstreamSettings (Map String String)] -> String))
  (:f timeoutSec (fn [UpstreamSettings] -> Float64)))

(schema TokenBucket
  (:f rate Float64)
  (:f capacity Float64)
  (:f tokens Float64)
  (:f lastUpdate Float64))

(enum BucketStep
  (:c bucketAcquired [])
  (:c bucketRefused [])
  (:c bucketWait [(seconds Float64)]))

(schema BucketRegistry
  (:f buckets (List (Pair String TokenBucket))))

(schema RoleTokenPolicy
  (:f mode String)
  (:f floorIfReasoning Int64)
  (:f hardCap Int64))

(schema UpstreamRequest
  (:f url String)
  (:f fragment String)
  (:f method String)
  (:f headers (List (Pair String String)))
  (:f data String))

(schema UpstreamResponse
  (:f status Int64)
  (:f reason String)
  (:f body String))

(enum UpstreamFailure
  (:c toolAbsent [(tool String) (detail String)])
  (:c transportFailure [(exitCode Int64) (stderr String)])
  (:c httpFailure [(status Int64) (reason String) (body String)])
  (:c protocolFailure [(detail String)]))

(schema PipeState
  (:f pending String)
  (:f inOpen Bool)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f out (List String))
  (:f errText (List String)))

(schema UpstreamCall
  (:f process SpawnedProc)
  (:f pipe PipeState))

fn pairUp xs: (List String) acc: (List String) -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some a)
     (let [(rest (optionOr (listTail xs) (list)))]
       (mt (listHead rest)
         ((none) (listReverse (cons a acc)))
         ((some b) (pairUp (optionOr (listTail rest) (list)) (cons (stringConcat a b) acc)))))))

fn joinAll xs: (List String) -> String
  (if (<= (listLength xs) 1)
    (optionOr (listHead xs) "")
    (joinAll (pairUp xs (list))))

fn printableAscii -> String
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

fn asciiChar b: Int64 -> String
  (optionOr (stringSlice (printableAscii) (- b 32) (- b 31)) "")

fn slice s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn cont? bs: Bytes i: Int64 n: Int64 lo: Int64 hi: Int64 -> Bool
  (and (< i n) (and (>= (bytesGet bs i) lo) (<= (bytesGet bs i) hi)))

fn cp2 b0: Int64 b1: Int64 -> Int64
  (+ (* (- b0 192) 64) (- b1 128))

fn cp3 b0: Int64 b1: Int64 b2: Int64 -> Int64
  (+ (* (- b0 224) 4096) (+ (* (- b1 128) 64) (- b2 128)))

fn cp4 b0: Int64 b1: Int64 b2: Int64 b3: Int64 -> Int64
  (+ (* (- b0 240) 262144) (+ (* (- b1 128) 4096) (+ (* (- b2 128) 64) (- b3 128))))

fn utf8Tail3 bs: Bytes i: Int64 n: Int64 lo: Int64 hi: Int64 -> (Pair Int64 Int64)
  (cond
    ((not (cont? bs (+ i 1) n lo hi)) (pair -1 1))
    ((not (cont? bs (+ i 2) n 128 191)) (pair -1 2))
    (else (pair (cp3 (bytesGet bs i) (bytesGet bs (+ i 1)) (bytesGet bs (+ i 2))) 3)))

fn utf8Tail4 bs: Bytes i: Int64 n: Int64 lo: Int64 hi: Int64 -> (Pair Int64 Int64)
  (cond
    ((not (cont? bs (+ i 1) n lo hi)) (pair -1 1))
    ((not (cont? bs (+ i 2) n 128 191)) (pair -1 2))
    ((not (cont? bs (+ i 3) n 128 191)) (pair -1 3))
    (else (pair (cp4 (bytesGet bs i) (bytesGet bs (+ i 1)) (bytesGet bs (+ i 2)) (bytesGet bs (+ i 3))) 4)))

fn utf8Next bs: Bytes i: Int64 n: Int64 -> (Pair Int64 Int64)
  (let [(b0 (bytesGet bs i))]
    (cond
      ((< b0 128) (pair b0 1))
      ((and (>= b0 194) (<= b0 223))
       (if (cont? bs (+ i 1) n 128 191) (pair (cp2 b0 (bytesGet bs (+ i 1))) 2) (pair -1 1)))
      ((= b0 224) (utf8Tail3 bs i n 160 191))
      ((= b0 237) (utf8Tail3 bs i n 128 159))
      ((and (>= b0 225) (<= b0 239)) (utf8Tail3 bs i n 128 191))
      ((= b0 240) (utf8Tail4 bs i n 144 191))
      ((and (>= b0 241) (<= b0 243)) (utf8Tail4 bs i n 128 191))
      ((= b0 244) (utf8Tail4 bs i n 128 143))
      (else (pair -1 1))))

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn byteChar b: Int64 -> String
  (optionOr (stringSlice (byteTable) b (+ b 1)) "")

fn decodeLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 bad: String acc: (List String) -> String
  (if (>= i n)
    (joinAll (listReverse (cons (slice s start n) acc)))
    (let [(d (utf8Next bs i n))
          (k (pairSecond d))]
      (if (< (pairFirst d) 0)
        (decodeLoop s bs n (+ i k) (+ i k) bad (cons bad (cons (slice s start i) acc)))
        (decodeLoop s bs n (+ i k) start bad acc))))

fn utf8Decode s: String bad: String -> String
  (let [(bs (stringToBytes s))]
    (decodeLoop s bs (bytesLength bs) 0 0 bad (list)))

fn codepointsLoop bs: Bytes i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n)
    (listReverse acc)
    (let [(d (utf8Next bs i n))]
      (codepointsLoop bs (+ i (pairSecond d)) n (cons (pairFirst d) acc))))

fn codepoints s: String -> (List Int64)
  (let [(bs (stringToBytes s))]
    (codepointsLoop bs 0 (bytesLength bs) (list)))

fn inRangesLoop cp: Int64 rs: (List Int64) -> Bool
  (mt (listHead rs)
    ((none) false)
    ((some lo)
     (let [(rest (optionOr (listTail rs) (list)))
           (hi (optionOr (listHead rest) -1))]
       (cond
         ((< cp lo) false)
         ((<= cp hi) true)
         (else (inRangesLoop cp (optionOr (listTail rest) (list))))))))

fn inRanges? cp: Int64 rs: (List Int64) -> Bool
  (inRangesLoop cp rs)

fn unicodeSpaceRanges -> (List Int64)
  (list 9 13 28 32 133 133 160 160 5760 5760 8192 8202 8232 8233 8239 8239 8287 8287 12288 12288)

fn unicodeDigitRanges -> (List Int64)
  (list 1632 1641 1776 1785 1984 1993 2406 2415 2534 2543 2662 2671 2790 2799 2918 2927 3046 3055 3174 3183
        3302 3311 3430 3439 3558 3567 3664 3673 3792 3801 3872 3881 4160 4169 4240 4249 6112 6121 6160 6169
        6470 6479 6608 6617 6784 6793 6800 6809 6992 7001 7088 7097 7232 7241 7248 7257 42528 42537 43216 43225
        43264 43273 43472 43481 43504 43513 43600 43609 44016 44025 65296 65305 66720 66729 68912 68921 69734 69743 69872 69881
        69942 69951 70096 70105 70384 70393 70736 70745 70864 70873 71248 71257 71360 71369 71472 71481 71904 71913 72016 72025
        72784 72793 73040 73049 73120 73129 73552 73561 92768 92777 92864 92873 93008 93017 120782 120831 123200 123209 123632 123641
        124144 124153 125264 125273 130032 130041)

fn isPySpace? cp: Int64 -> Bool
  (inRanges? cp (unicodeSpaceRanges))

fn digitBlockLoop cp: Int64 rs: (List Int64) -> Int64
  (mt (listHead rs)
    ((none) -1)
    ((some lo)
     (let [(rest (optionOr (listTail rs) (list)))
           (hi (optionOr (listHead rest) -1))]
       (cond
         ((< cp lo) -1)
         ((<= cp hi) (mod (- cp lo) 10))
         (else (digitBlockLoop cp (optionOr (listTail rest) (list))))))))

fn pyDigitValue cp: Int64 -> Int64
  (if (and (>= cp 48) (<= cp 57)) (- cp 48) (digitBlockLoop cp (unicodeDigitRanges)))

fn stripStart bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    n
    (let [(d (utf8Next bs i n))]
      (if (isPySpace? (pairFirst d)) (stripStart bs (+ i (pairSecond d)) n) i)))

fn charStart bs: Bytes j: Int64 lo: Int64 -> Int64
  (if (and (> j lo) (and (>= (bytesGet bs j) 128) (< (bytesGet bs j) 192))) (charStart bs (- j 1) lo) j)

fn stripEnd bs: Bytes j: Int64 lo: Int64 n: Int64 -> Int64
  (if (<= j lo)
    lo
    (let [(k (charStart bs (- j 1) lo))
          (d (utf8Next bs k n))]
      (if (and (= (+ k (pairSecond d)) j) (isPySpace? (pairFirst d))) (stripEnd bs k lo n) j)))

fn pyStrip s: String -> String
  (let [(bs (stringToBytes s))
        (n (bytesLength bs))
        (a (stripStart bs 0 n))
        (b (stripEnd bs n a n))]
    (slice s a b))

fn upperChars -> (List String)
  (stringChars "ABCDEFGHIJKLMNOPQRSTUVWXYZ\u{c0}\u{c1}\u{c2}\u{c3}\u{c4}\u{c5}\u{c6}\u{c7}\u{c8}\u{c9}\u{ca}\u{cb}\u{cc}\u{cd}\u{ce}\u{cf}\u{d0}\u{d1}\u{d2}\u{d3}\u{d4}\u{d5}\u{d6}\u{d8}\u{d9}\u{da}\u{db}\u{dc}\u{dd}\u{de}\u{130}\u{212a}")

fn lowerChars -> (List String)
  (list "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z"
        "\u{e0}" "\u{e1}" "\u{e2}" "\u{e3}" "\u{e4}" "\u{e5}" "\u{e6}" "\u{e7}" "\u{e8}" "\u{e9}" "\u{ea}" "\u{eb}" "\u{ec}" "\u{ed}"
        "\u{ee}" "\u{ef}" "\u{f0}" "\u{f1}" "\u{f2}" "\u{f3}" "\u{f4}" "\u{f5}" "\u{f6}" "\u{f8}" "\u{f9}" "\u{fa}" "\u{fb}" "\u{fc}"
        "\u{fd}" "\u{fe}" "i\u{307}" "k")

fn pyLower s: String -> String
  (let [(ups (upperChars))
        (lows (lowerChars))]
    (joinAll (map (fn [(c String)] -> String
                    (mt (listIndexOf ups c)
                      ((some i) (optionOr (listGet lows i) c))
                      ((none) c)))
                  (stringChars s))))

fn envMapFromList rows: (List String) -> (Map String String)
  (fold (fn [(m (Map String String)) (row String)] -> (Map String String)
          (mt (stringIndexOf row "=")
            ((some i) (mapSet m (slice row 0 i) (slice row (+ i 1) (stringLength row))))
            ((none) m)))
        (mapEmpty) rows)

fn envGetOr env: (Map String String) k: String fallback: String -> String
  (optionOr (mapGet env k) fallback)

fn envTruthy? env: (Map String String) k: String -> Bool
  (not (stringEmpty? (envGetOr env k "")))

fn rstripSlash s: String -> String
  (if (stringEndsWith? s "/") (rstripSlash (slice s 0 (- (stringLength s) 1))) s)

fn removeSuffix s: String suffix: String -> String
  (if (stringEndsWith? s suffix) (slice s 0 (- (stringLength s) (stringLength suffix))) s)

fn replaceAllLoop s: String old: String new: String i: Int64 start: Int64 acc: (List String) -> String
  (let [(n (stringLength s))
        (k (stringLength old))]
    (cond
      ((> (+ i k) n) (joinAll (listReverse (cons (slice s start n) acc))))
      ((= (slice s i (+ i k)) old) (replaceAllLoop s old new (+ i k) (+ i k) (cons new (cons (slice s start i) acc))))
      (else (replaceAllLoop s old new (+ i 1) start acc))))

fn replaceAll s: String old: String new: String -> String
  (replaceAllLoop s old new 0 0 (list))

fn floatCharsLoop cps: (List Int64) acc: (List String) -> (Result (List String) String)
  (mt (listHead cps)
    ((none) (ok (listReverse acc)))
    ((some cp)
     (let [(rest (optionOr (listTail cps) (list)))
           (dv (pyDigitValue cp))]
       (cond
         ((isPySpace? cp) (floatCharsLoop rest (cons " " acc)))
         ((>= dv 0) (floatCharsLoop rest (cons (asciiChar (+ 48 dv)) acc)))
         ((and (>= cp 32) (< cp 127)) (floatCharsLoop rest (cons (asciiChar cp) acc)))
         (else (err "non-ASCII character"))))))

fn digitChar? c: String -> Bool
  (and (= (stringLength c) 1) (stringContains? "0123456789" c))

fn underscoresLoop cs: (List String) prev: String acc: (List String) -> (Result (List String) String)
  (mt (listHead cs)
    ((none) (ok (listReverse acc)))
    ((some c)
     (let [(rest (optionOr (listTail cs) (list)))]
       (if (= c "_")
         (if (and (digitChar? prev) (digitChar? (optionOr (listHead rest) "")))
           (underscoresLoop rest c acc)
           (err "misplaced underscore"))
         (underscoresLoop rest c (cons c acc))))))

fn digitsEnd s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (digitChar? (slice s i (+ i 1)))) (digitsEnd s (+ i 1)) i)

fn signEnd s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (or (= (slice s i (+ i 1)) "+") (= (slice s i (+ i 1)) "-"))) (+ i 1) i)

fn decimalLiteral? s: String -> Bool
  (let [(n (stringLength s))
        (a (signEnd s 0))
        (b (digitsEnd s a))
        (hasDot (and (< b n) (= (slice s b (+ b 1)) ".")))
        (c (if hasDot (digitsEnd s (+ b 1)) b))
        (mantissa (or (> b a) (> c (+ b 1))))
        (hasExp (and (< c n) (or (= (slice s c (+ c 1)) "e") (= (slice s c (+ c 1)) "E"))))
        (f (if hasExp (signEnd s (+ c 1)) c))
        (g (if hasExp (digitsEnd s f) c))]
    (and mantissa (and (or (not hasExp) (> g f)) (= g n))))

fn specialLiteral? s: String -> Bool
  (let [(body (stringLower (slice s (signEnd s 0) (stringLength s))))]
    (or (= body "inf") (or (= body "infinity") (= body "nan"))))

fn pyFloat text: String -> (Result Float64 String)
  (let [(fail (str "ValueError: could not convert string to float: " text))]
    (mt (floatCharsLoop (codepoints text) (list))
      ((err _) (err fail))
      ((ok cs)
       (mt (underscoresLoop cs "" (list))
         ((err _) (err fail))
         ((ok kept)
          (let [(s (stringTrim (joinAll kept)))]
            (if (or (decimalLiteral? s) (specialLiteral? s))
              (mt (stringToFloat64 s)
                ((some f) (ok f))
                ((none) (err fail)))
              (err fail))))))))

fn upstreamSettings env: (Map String String) -> (Result UpstreamSettings String)
  (let [(openrouter (envTruthy? env "OPENROUTER_API_KEY"))
        (baseUrl (if openrouter
                   (envGetOr env "OPENROUTER_BASE_URL" "https://openrouter.ai/api/v1")
                   (envGetOr env "OPENAI_BASE_URL" (envGetOr env "LLM_GATEWAY_BASE_URL" "https://openrouter.ai/api/v1"))))
        (key (if openrouter
               (envGetOr env "OPENROUTER_API_KEY" "")
               (envGetOr env "OPENAI_API_KEY" (envGetOr env "LLM_GATEWAY_API_KEY" ""))))]
    (mt (pyFloat (envGetOr env "OLLAMA_TIMEOUT_SEC" "300"))
      ((err e) (err e))
      ((ok timeout)
       (ok (UpstreamSettings
             :geminiUrl "https://generativelanguage.googleapis.com/v1beta/openai"
             :geminiKey (envGetOr env "GEMINI_API_KEY" "")
             :groqUrl (rstripSlash (envGetOr env "GROQ_BASE_URL" "https://api.groq.com/openai/v1"))
             :ollamaUrl (str (removeSuffix (rstripSlash (envGetOr env "OLLAMA_BASE_URL" "https://ollama.com")) "/v1") "/v1")
             :groqKey (envGetOr env "GROQ_API_KEY" "")
             :url (rstripSlash (replaceAll baseUrl "/v1/v1" "/v1"))
             :key key
             :ollamaTimeoutSec timeout)))))

fn oneOf? s: String xs: (List String) -> Bool
  (listContains? xs s)

fn defaultTimeoutSec st: UpstreamSettings -> Float64
  45.0

fn cliProviderRow id: String url: String prefixes: (List String) names: (List String) -> UpstreamProvider
  (UpstreamProvider :id id :prefixes prefixes :names names
    :url (fn [(st UpstreamSettings) (env (Map String String))] -> String url)
    :key (fn [(st UpstreamSettings) (env (Map String String))] -> String "")
    :timeoutSec defaultTimeoutSec)

fn upstreamProviders -> (List UpstreamProvider)
  (list
    (cliProviderRow "agy-cli" "cli://agy" (list "agy/")
      (list "agy" "antigravity" "agy-opus" "agy-sonnet" "claude-opus-4-6-thinking" "claude-sonnet-4-6" "sonnet" "opus" "claude-sonnet" "claude-opus"))
    (cliProviderRow "codex-cli" "cli://codex" (list "codex/") (list "codex" "luna" "gpt-5.6-luna" "gpt-luna" "astra" "gpt-6-astra"))
    (cliProviderRow "claude-cli" "cli://claude" (list "claude/") (list "claude"))
    (UpstreamProvider :id "gemini" :prefixes (list "gemini-") :names (list)
      :url (fn [(st UpstreamSettings) (env (Map String String))] -> String st.geminiUrl)
      :key (fn [(st UpstreamSettings) (env (Map String String))] -> String (envGetOr env "GEMINI_API_KEY" st.geminiKey))
      :timeoutSec defaultTimeoutSec)
    (UpstreamProvider :id "ollama" :prefixes (list "ollama/") :names (list)
      :url (fn [(st UpstreamSettings) (env (Map String String))] -> String st.ollamaUrl)
      :key (fn [(st UpstreamSettings) (env (Map String String))] -> String (envGetOr env "OLLAMA_API_KEY" ""))
      :timeoutSec (fn [(st UpstreamSettings)] -> Float64 st.ollamaTimeoutSec))
    (UpstreamProvider :id "groq" :prefixes (list "groq/" "qwen/") :names (list "groq" "qwen" "groq-qwen" "qwen-groq")
      :url (fn [(st UpstreamSettings) (env (Map String String))] -> String (envGetOr env "GROQ_BASE_URL" st.groqUrl))
      :key (fn [(st UpstreamSettings) (env (Map String String))] -> String (envGetOr env "GROQ_API_KEY" st.groqKey))
      :timeoutSec defaultTimeoutSec))

fn upstreamFallback -> UpstreamProvider
  (UpstreamProvider :id "openrouter" :prefixes (list) :names (list)
    :url (fn [(st UpstreamSettings) (env (Map String String))] -> String st.url)
    :key (fn [(st UpstreamSettings) (env (Map String String))] -> String st.key)
    :timeoutSec defaultTimeoutSec)

fn providerClaims? row: UpstreamProvider m: String -> Bool
  (or (listAny? (fn [(prefix String)] -> Bool (stringStartsWith? m prefix)) row.prefixes)
      (oneOf? m row.names))

fn firstProvider pred: (fn [UpstreamProvider] -> Bool) providers: (List UpstreamProvider) -> (Option UpstreamProvider)
  (if (listEmpty? providers) none
    (if (pred (preludeHead providers)) (some (preludeHead providers)) (firstProvider pred (preludeTail providers))))

fn upstreamProviderNamed providers: (List UpstreamProvider) id: String -> (Option UpstreamProvider)
  (firstProvider (fn [(row UpstreamProvider)] -> Bool (= row.id id)) providers)

fn upstreamProviderEndpoint row: UpstreamProvider st: UpstreamSettings env: (Map String String) -> UpstreamEndpoint
  (UpstreamEndpoint :provider row.id :url (row.url st env) :key (row.key st env))

fn getUpstreamForModelIn providers: (List UpstreamProvider) fallback: UpstreamProvider st: UpstreamSettings env: (Map String String) model: (Option String) -> UpstreamEndpoint
  (let [(row (mt model
               ((none) fallback)
               ((some m) (optionOr (firstProvider (fn [(r UpstreamProvider)] -> Bool (providerClaims? r m)) providers) fallback))))]
    (upstreamProviderEndpoint row st env))

fn getUpstreamForModel st: UpstreamSettings env: (Map String String) model: (Option String) -> UpstreamEndpoint
  (getUpstreamForModelIn (upstreamProviders) (upstreamFallback) st env model)

fn upstreamTimeoutSecIn providers: (List UpstreamProvider) st: UpstreamSettings provider: String -> Float64
  (mt (upstreamProviderNamed providers provider)
    ((some row) (row.timeoutSec st))
    ((none) 45.0))

fn upstreamTimeoutSec st: UpstreamSettings provider: String -> Float64
  (upstreamTimeoutSecIn (upstreamProviders) st provider)

fn pyMin a: Float64 b: Float64 -> Float64
  (if (< b a) b a)

fn makeTokenBucket rate: Float64 capacity: Float64 now: Float64 -> TokenBucket
  (TokenBucket :rate rate :capacity capacity :tokens capacity :lastUpdate now)

fn refill b: TokenBucket now: Float64 -> TokenBucket
  (let [(elapsed (- now b.lastUpdate))]
    (with b :tokens (pyMin b.capacity (+ b.tokens (* elapsed b.rate))) :lastUpdate now))

fn takeToken b: TokenBucket -> TokenBucket
  (with b :tokens (- b.tokens 1.0))

fn tokenBucketBegin b: TokenBucket timeout: Float64 now: Float64 -> (Pair TokenBucket (Result BucketStep String))
  (let [(r (refill b now))]
    (cond
      ((>= r.tokens 1.0) (pair (takeToken r) (ok (bucketAcquired))))
      ((= r.rate 0.0) (pair r (err "ZeroDivisionError: float division by zero")))
      (else
       (let [(wait (/ (- 1.0 r.tokens) r.rate))]
         (cond
           ((> wait timeout) (pair r (ok (bucketRefused))))
           ((< wait 0.0) (pair r (err "ValueError: sleep length must be non-negative")))
           (else (pair r (ok (bucketWait wait)))))))))

fn tokenBucketFinish b: TokenBucket now: Float64 -> (Pair TokenBucket Bool)
  (let [(r (refill b now))]
    (if (>= r.tokens 1.0) (pair (takeToken r) true) (pair r false)))

fn ! wallSeconds! -> Float64
  (/ (int64ToFloat64 (nowNs)) 1000000000.0)

fn ceilMs secs: Float64 -> Int64
  (let [(ms (optionOr (float64ToInt64 (* secs 1000.0)) 0))]
    (if (< (int64ToFloat64 ms) (* secs 1000.0)) (+ ms 1) ms))

fn ! tokenBucketAcquire! b: TokenBucket timeout: Float64 -> (Pair TokenBucket (Result Bool String))
  (let [(step (tokenBucketBegin b timeout (wallSeconds!)))
        (b1 (pairFirst step))]
    (mt (pairSecond step)
      ((err e) (pair b1 (err e)))
      ((ok s)
       (mt s
         ((bucketAcquired) (pair b1 (ok true)))
         ((bucketRefused) (pair b1 (ok false)))
         ((bucketWait secs)
          (let [(slept (sleepMs (ceilMs secs)))
                (done (tokenBucketFinish b1 (wallSeconds!)))]
            (pair (pairFirst done) (ok (pairSecond done)))))))))

fn emptyBucketRegistry -> BucketRegistry
  (BucketRegistry :buckets (list))

fn bucketKey model: String rpm: Float64 -> String
  (str model "\u{0}" (stringFromFloat64 rpm))

fn findBucket xs: (List (Pair String TokenBucket)) k: String -> (Option TokenBucket)
  (mt (listHead xs)
    ((none) none)
    ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (findBucket (optionOr (listTail xs) (list)) k))))

fn geminiBucket reg: BucketRegistry model: String rpm: Float64 now: Float64 -> (Pair BucketRegistry TokenBucket)
  (let [(k (bucketKey model rpm))]
    (mt (findBucket reg.buckets k)
      ((some b) (pair reg b))
      ((none)
       (let [(b (makeTokenBucket (/ rpm 60.0) 1.0 now))]
         (pair (BucketRegistry :buckets (listAppend reg.buckets (list (pair k b)))) b)))))

fn bucketRegistryPut reg: BucketRegistry model: String rpm: Float64 b: TokenBucket -> BucketRegistry
  (let [(k (bucketKey model rpm))]
    (BucketRegistry :buckets (map (fn [(p (Pair String TokenBucket))] -> (Pair String TokenBucket)
                                    (if (= (pairFirst p) k) (pair k b) p))
                                  reg.buckets)))

fn bucketRegistrySize reg: BucketRegistry -> Int64
  (listLength reg.buckets)

fn ! geminiAcquire! reg: BucketRegistry model: String rpm: Float64 timeout: Float64 -> (Pair BucketRegistry (Result Bool String))
  (let [(got (geminiBucket reg model rpm (wallSeconds!)))
        (res (tokenBucketAcquire! (pairSecond got) timeout))]
    (pair (bucketRegistryPut (pairFirst got) model rpm (pairFirst res)) (pairSecond res)))

fn reasoningModels -> (List String)
  (list "cohere/north-mini-code:free" "google/gemma-4-26b-a4b-it:free" "google/gemma-4-31b-it:free" "liquid/lfm-2.5-2.6b:free"
        "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free" "nvidia/nemotron-3-super-120b-a12b:free" "nvidia/nemotron-3-ultra-550b-a55b:free"
        "poolside/laguna-s-2.1:free" "poolside/laguna-xs-2.1:free")

fn coderCascade -> (List String)
  (list "groq/qwen/qwen3.8-27b" "gemini-3.8-flash" "poolside/laguna-s-2.1:free" "cohere/north-mini-code:free" "poolside/laguna-xs-2.1:free"
        "google/gemma-4-31b-it:free" "google/gemma-4-26b-a4b-it:free" "qwen/qwen3.8-27b:free")

fn plannerCascade -> (List String)
  (list "gemini-3.8-flash" "groq/qwen/qwen3.8-27b" "nvidia/nemotron-3-ultra-550b-a55b:free" "nvidia/nemotron-3-super-120b-a12b:free"
        "z-ai/glm-5.2:free" "nex-agi/nex-n2.5-pro:free")

fn tokenFloorRoles -> (List String)
  (list "coder" "planner")

fn minTokenFloor -> Int64
  1500

fn modelTokenFloors -> (List (Pair String Int64))
  (list (pair "ollama/glm" 32768) (pair "glm-" 32768))

fn replyCeiling mode: String -> (Option Int64)
  (cond
    ((= mode "scout") (some 450))
    ((= mode "plan") (some 600))
    ((= mode "implement") (some 350))
    ((= mode "grade") (some 350))
    ((= mode "orchestrate") (some 350))
    (else none))

fn policyRow mode: String cap: Int64 -> RoleTokenPolicy
  (RoleTokenPolicy :mode mode :floorIfReasoning (minTokenFloor) :hardCap cap)

fn roleTokenPolicyTable -> (List (Pair String RoleTokenPolicy))
  (list (pair "coder" (policyRow "implement" 4096)) (pair "falsifier" (policyRow "implement" 4096)) (pair "planner" (policyRow "plan" 4096))
        (pair "scout" (policyRow "scout" 3072)) (pair "distillator" (policyRow "scout" 3072)) (pair "audit" (policyRow "grade" 3072))
        (pair "auditor" (policyRow "grade" 3072)) (pair "shadowcritic" (policyRow "grade" 3072)) (pair "chiefjustice" (policyRow "grade" 3072))
        (pair "consult" (policyRow "orchestrate" 3072)) (pair "consilium" (policyRow "orchestrate" 3072)))

fn emptyContentRetries -> Int64
  1

fn aslMinimalHarness -> String
  ";; === ASL PROXY HARNESS ===\n;; Substrate: 100% Pure ASL / ASN. Pure Dyck-1 Parentheses. Zero Line Numbers.\n;; Format Contract: Return responses strictly as pure ASN S-expressions without markdown fences.\n;; Ground Truth: Exit 0 requires positive executed assertions (assertCount > 0).\n;; Toolbelt: Execute commands via './bin/asl' (:query, :read, :edit, :diff, :flush, check, test)."

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (slice s 1 (stringLength s))) s)

fn lookupPolicy xs: (List (Pair String RoleTokenPolicy)) k: String -> (Option RoleTokenPolicy)
  (mt (listHead xs)
    ((none) none)
    ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (lookupPolicy (optionOr (listTail xs) (list)) k))))

fn roleTokenPolicy role: (Option String) -> (Option RoleTokenPolicy)
  (let [(lowered (pyLower (lstripColons (optionOr role ""))))
        (base (mt (stringIndexOf lowered ":") ((some i) (slice lowered 0 i)) ((none) lowered)))]
    (lookupPolicy (roleTokenPolicyTable) base))

fn emptyContentAction cascadeLen: Int64 retriesDone: Int64 -> String
  (cond
    ((> cascadeLen 1) "cascade")
    ((< retriesDone (emptyContentRetries)) "retry")
    (else "fail"))

fn isEmptyContent? content: j/Json -> Bool
  (mt content
    ((j/jnull) true)
    ((j/jstr s) (stringEmpty? (pyStrip s)))
    (_ false))

fn stripModelPrefixes model: String -> String
  (let [(a (if (stringStartsWith? model "openai/") (slice model 7 (stringLength model)) model))]
    (if (stringStartsWith? a "openrouter/") (slice a 11 (stringLength a)) a))

fn isReasoningModel? model: String -> Bool
  (or (oneOf? model (reasoningModels))
      (or (stringContains? (pyLower model) "reasoning")
          (or (stringStartsWith? model "ollama/glm")
              (or (stringStartsWith? model "glm-")
                  (or (oneOf? model (coderCascade))
                      (or (oneOf? model (plannerCascade)) (oneOf? model (tokenFloorRoles))))))))

fn objGet kvs: (List (Pair String j/Json)) k: String -> (Option j/Json)
  (mt (listHead kvs)
    ((none) none)
    ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (objGet (optionOr (listTail kvs) (list)) k))))

fn objSet kvs: (List (Pair String j/Json)) k: String v: j/Json -> (List (Pair String j/Json))
  (if (some? (objGet kvs k))
    (map (fn [(p (Pair String j/Json))] -> (Pair String j/Json) (if (= (pairFirst p) k) (pair k v) p)) kvs)
    (listAppend kvs (list (pair k v))))

fn asFloat v: j/Json -> Float64
  (mt v
    ((j/jint x) (int64ToFloat64 x))
    ((j/jfloat x) x)
    ((j/jnum x) x)
    (_ 0.0))

fn numberLess? a: j/Json b: j/Json -> Bool
  (mt a
    ((j/jint x) (mt b ((j/jint y) (< x y)) (_ (< (int64ToFloat64 x) (asFloat b)))))
    (_ (< (asFloat a) (asFloat b))))

fn numberOf v: j/Json -> (Option j/Json)
  (mt v
    ((j/jint _) (some v))
    ((j/jfloat _) (some v))
    ((j/jnum _) (some v))
    (_ none))

fn modelFloor model: String base: Int64 -> Int64
  (fold (fn [(acc Int64) (p (Pair String Int64))] -> Int64
          (if (and (stringStartsWith? model (pairFirst p)) (> (pairSecond p) acc)) (pairSecond p) acc))
        base (modelTokenFloors))

fn typeName v: j/Json -> String
  (mt v
    ((j/jnull) "NoneType")
    ((j/jbool _) "bool")
    ((j/jint _) "int")
    ((j/jfloat _) "float")
    ((j/jnum _) "float")
    ((j/jstr _) "str")
    ((j/jarr _) "list")
    ((j/jobj _) "dict"))

fn cappedTokens asked: (Option j/Json) pol: (Option RoleTokenPolicy) floor: Int64 -> (Option j/Json)
  (mt asked
    ((none) none)
    ((some v)
     (mt pol
       ((none) (some v))
       ((some p)
        (let [(cap (j/jint (max p.hardCap floor)))]
          (some (if (numberLess? cap v) cap v)))))))

fn prepareRequestPayload payload: j/Json role: (Option String) -> (Result j/Json String)
  (mt payload
    ((j/jobj kvs)
     (let [(modelVal (optionOr (objGet kvs "model") (j/jstr "")))]
       (mt modelVal
         ((j/jstr raw)
          (let [(model (stripModelPrefixes raw))
                (pol (roleTokenPolicy role))
                (base (if (isReasoningModel? model) (mt pol ((some p) p.floorIfReasoning) ((none) (minTokenFloor))) 0))
                (floor (modelFloor model base))
                (asked (mt (objGet kvs "max_tokens") ((some v) (numberOf v)) ((none) none)))]
            (mt (cappedTokens asked pol floor)
              ((none) (ok (if (> floor 0) (j/jobj (objSet kvs "max_tokens" (j/jint floor))) payload)))
              ((some v) (ok (j/jobj (objSet kvs "max_tokens" (if (numberLess? (j/jint floor) v) v (j/jint floor)))))))))
         (_ (err (str "AttributeError: '" (typeName modelVal) "' object has no attribute 'startswith'"))))))
    (_ (ok payload)))

fn systemMessage content: String -> j/Json
  (j/jobj (list (pair "role" (j/jstr "system")) (pair "content" (j/jstr content))))

fn messageRole msg: j/Json -> (Result (Option j/Json) String)
  (mt msg
    ((j/jobj kvs) (ok (objGet kvs "role")))
    (_ (err (str "AttributeError: '" (typeName msg) "' object has no attribute 'get'"))))

fn isSystemRole? role: (Option j/Json) -> Bool
  (mt role
    ((some v) (= v (j/jstr "system")))
    ((none) false))

fn overrideLoop msgs: (List j/Json) harness: String found: Bool acc: (List j/Json) -> (Result (List j/Json) String)
  (mt (listHead msgs)
    ((none) (ok (if found (listReverse acc) (cons (systemMessage harness) (listReverse acc)))))
    ((some m)
     (mt (messageRole m)
       ((err e) (err e))
       ((ok role)
        (if (isSystemRole? role)
          (overrideLoop (optionOr (listTail msgs) (list)) harness true (cons (systemMessage harness) acc))
          (overrideLoop (optionOr (listTail msgs) (list)) harness found (cons m acc)))))))

fn minimalLoop msgs: (List j/Json) acc: (List j/Json) -> (Result (List j/Json) String)
  (mt (listHead msgs)
    ((none) (ok (listReverse acc)))
    ((some m)
     (mt (messageRole m)
       ((err e) (err e))
       ((ok role) (minimalLoop (optionOr (listTail msgs) (list)) (if (isSystemRole? role) acc (cons m acc)))))))

fn harnessText role: (Option String) -> String
  (mt (roleTokenPolicy role)
    ((some p) (str (aslMinimalHarness) "\n;; Reply Ceiling: one ASN form, no preamble or file bodies, under "
                   (stringFromInt64 (optionOr (replyCeiling p.mode) 0)) " tok."))
    ((none) (aslMinimalHarness)))

fn applyHarnessMessages kvs: (List (Pair String j/Json)) msgs: (List j/Json) mode: String role: (Option String) payload: j/Json -> (Result j/Json String)
  (cond
    ((= mode "override")
     (mt (overrideLoop msgs (harnessText role) false (list))
       ((err e) (err e))
       ((ok out) (ok (j/jobj (objSet kvs "messages" (j/jarr out)))))))
    ((= mode "minimal")
     (mt (minimalLoop msgs (list))
       ((err e) (err e))
       ((ok out) (ok (j/jobj (objSet kvs "messages" (j/jarr (cons (systemMessage (harnessText role)) out))))))))
    (else (ok payload)))

fn applyHarnessPolicy payload: j/Json mode: String role: (Option String) -> (Result j/Json String)
  (mt payload
    ((j/jobj kvs)
     (mt (objGet kvs "messages")
       ((some v)
        (mt v
          ((j/jarr msgs) (applyHarnessMessages kvs msgs mode role payload))
          (_ (ok payload))))
       ((none) (ok payload))))
    (_ (ok payload)))

fn headerGet headers: (List (Pair String String)) name: String -> (Option String)
  (mt (listHead headers)
    ((none) none)
    ((some p) (if (= (pyLower (pairFirst p)) (pyLower name)) (some (pairSecond p)) (headerGet (optionOr (listTail headers) (list)) name))))

fn nonEmpty v: (Option String) -> (Option String)
  (mt v
    ((some s) (if (stringEmpty? s) none (some s)))
    ((none) none))

fn harnessMode headers: (List (Pair String String)) env: (Map String String) -> String
  (pyLower (mt (nonEmpty (headerGet headers "X-ASL-Harness"))
             ((some s) s)
             ((none) (mt (nonEmpty (headerGet headers "X-ASL-Harness-Mode"))
                       ((some s) s)
                       ((none) (envGetOr env "ASL_HARNESS_MODE" "passthrough"))))))

fn capitalize s: String -> String
  (let [(cs (stringChars s))]
    (mt (listHead cs)
      ((none) "")
      ((some c) (str (stringUpper c) (pyLower (joinAll (optionOr (listTail cs) (list))))))))

fn headerPut hs: (List (Pair String String)) name: String v: String -> (List (Pair String String))
  (let [(k (capitalize name))]
    (if (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) hs)
      (map (fn [(p (Pair String String))] -> (Pair String String) (if (= (pairFirst p) k) (pair k v) p)) hs)
      (listAppend hs (list (pair k v)))))

fn unwrapUrl u: String -> String
  (let [(a (pyStrip u))
        (b (if (and (stringStartsWith? a "<") (stringEndsWith? a ">")) (pyStrip (slice a 1 (- (stringLength a) 1))) a))]
    (if (stringStartsWith? b "URL:") (pyStrip (slice b 4 (stringLength b))) b))

fn lastIndexOf s: String c: String i: Int64 -> Int64
  (cond
    ((< i 0) -1)
    ((= (slice s i (+ i 1)) c) i)
    (else (lastIndexOf s c (- i 1))))

fn hasScheme? u: String -> Bool
  (mt (stringIndexOf u ":")
    ((some i) (and (> i 0) (not (stringContains? (slice u 0 i) "/"))))
    ((none) false))

fn forwardHeaders hs: (List (Pair String String)) client: (List (Pair String String)) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (p (Pair String String))] -> (List (Pair String String))
          (if (oneOf? (pyLower (pairFirst p)) (list "host" "content-length" "authorization" "user-agent")) acc (headerPut acc (pairFirst p) (pairSecond p))))
        hs client)

fn upstreamRequest url: String path: String key: String data: String clientHeaders: (List (Pair String String)) -> (Result UpstreamRequest String)
  (let [(full (unwrapUrl (str url path)))
        (hashAt (lastIndexOf full "#" (- (stringLength full) 1)))
        (base (if (>= hashAt 0) (slice full 0 hashAt) full))
        (fragment (if (>= hashAt 0) (slice full (+ hashAt 1) (stringLength full)) ""))
        (h1 (forwardHeaders (headerPut (list) "User-Agent" "ASL-Gateway/1.0 (Darwin; macOS)") clientHeaders))
        (h2 (if (stringEmpty? key) h1 (headerPut h1 "Authorization" (str "Bearer " key))))
        (h3 (if (stringContains? url "openrouter.ai")
              (headerPut (headerPut h2 "HTTP-Referer" "https://aslang.dev") "X-Title" "ASL Gateway (OpenRouter Free Pool)")
              h2))]
    (if (hasScheme? base)
      (ok (UpstreamRequest :url base :fragment fragment :method "POST" :headers h3 :data data))
      (err (str "ValueError: unknown url type: " full))))

fn childEnvNames -> (List String)
  (list "PATH" "TMPDIR" "LANG" "LC_ALL" "SSL_CERT_FILE" "SSL_CERT_DIR" "CURL_CA_BUNDLE" "http_proxy" "https_proxy" "HTTP_PROXY" "HTTPS_PROXY"
        "no_proxy" "NO_PROXY" "all_proxy" "ALL_PROXY")

fn childEnv env: (Map String String) -> (List String)
  (fold (fn [(acc (List String)) (k String)] -> (List String)
          (mt (mapGet env k)
            ((some v) (listAppend acc (list (str k "=" v))))
            ((none) acc)))
        (list) (childEnvNames))

fn curlArgv -> (List String)
  (list "curl" "-q" "--config" "-")

fn escapeFor b: Int64 -> String
  (cond
    ((= b 92) "\\\\")
    ((= b 34) "\\\"")
    ((= b 10) "\\n")
    ((= b 13) "\\r")
    ((= b 9) "\\t")
    ((= b 11) "\\v")
    (else ""))

fn quoteLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (Result String String)
  (if (>= i n)
    (ok (joinAll (listReverse (cons (slice s start n) acc))))
    (let [(b (bytesGet bs i))
          (esc (escapeFor b))]
      (cond
        ((= b 0) (err "curl config cannot carry a NUL byte"))
        ((stringEmpty? esc) (quoteLoop s bs n (+ i 1) start acc))
        (else (quoteLoop s bs n (+ i 1) (+ i 1) (cons esc (cons (slice s start i) acc)))))))

fn configLine name: String value: String -> (Result String String)
  (let [(bs (stringToBytes value))]
    (mt (quoteLoop value bs (bytesLength bs) 0 0 (list))
      ((ok q) (ok (str name " = \"" q "\"\n")))
      ((err e) (err e))))

fn curlConfigLine name: String value: String -> (Result String String)
  (configLine name value)

fn collectLines xs: (List (Result String String)) acc: (List String) -> (Result String String)
  (mt (listHead xs)
    ((none) (ok (joinAll (listReverse acc))))
    ((some r)
     (mt r
       ((ok l) (collectLines (optionOr (listTail xs) (list)) (cons l acc)))
       ((err e) (err e)))))

fn hasHeader? hs: (List (Pair String String)) name: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (= (pyLower (pairFirst p)) name)) hs)

fn ceilSeconds t: Float64 -> Int64
  (let [(i (optionOr (float64ToInt64 t) 0))
        (up (if (< (int64ToFloat64 i) t) (+ i 1) i))]
    (if (< up 1) 1 up))

fn transportLines hs: (List (Pair String String)) -> (List (Result String String))
  (list (ok (if (hasHeader? hs "accept") "" "header = \"Accept:\"\n"))
        (ok (if (hasHeader? hs "expect") "" "header = \"Expect:\"\n"))
        (ok (if (hasHeader? hs "accept-encoding") "" "header = \"Accept-Encoding: identity\"\n"))
        (ok "header = \"Connection: close\"\n"))

fn tokenByte? b: Int64 -> Bool
  (or (inRanges? b (list 48 57 65 90 97 122)) (listContains? (list 33 35 36 37 38 39 42 43 45 46 94 95 96 124 126) b))

fn bytesAll? bs: Bytes i: Int64 n: Int64 pred: (fn [Int64] -> Bool) -> Bool
  (cond
    ((>= i n) true)
    ((pred (bytesGet bs i)) (bytesAll? bs (+ i 1) n pred))
    (else false))

fn headerNameOk? name: String -> Bool
  (let [(bs (stringToBytes name))]
    (and (> (bytesLength bs) 0) (bytesAll? bs 0 (bytesLength bs) tokenByte?)))

fn noLineBreak? s: String -> Bool
  (let [(bs (stringToBytes s))]
    (bytesAll? bs 0 (bytesLength bs) (fn [(b Int64)] -> Bool (not (or (= b 10) (or (= b 13) (= b 0)))))))

fn urlOk? s: String -> Bool
  (let [(bs (stringToBytes s))]
    (bytesAll? bs 0 (bytesLength bs) (fn [(b Int64)] -> Bool (and (> b 32) (not (= b 127))))))

fn checkRequest req: UpstreamRequest -> (Result Bool String)
  (let [(badName (listAny? (fn [(p (Pair String String))] -> Bool (not (headerNameOk? (pairFirst p)))) req.headers))
        (badValue (filter (fn [(p (Pair String String))] -> Bool (not (noLineBreak? (pairSecond p)))) req.headers))]
    (cond
      ((not (urlOk? req.url)) (err "ValueError: url carries a control character or space"))
      (badName (err "ValueError: a header name is not an RFC 7230 token"))
      ((not (listEmpty? badValue)) (err (str "ValueError: header " (pairFirst (optionOr (listHead badValue) (pair "" ""))) " value carries CR, LF or NUL")))
      (else (ok true))))

fn curlConfig req: UpstreamRequest timeoutSec: Float64 caFile: (Option String) -> (Result String String)
  (curlConfigFollowing req timeoutSec caFile 0)

fn curlConfigFollowing req: UpstreamRequest timeoutSec: Float64 caFile: (Option String) maxRedirects: Int64 -> (Result String String)
  (let [(hs (filter (fn [(p (Pair String String))] -> Bool (not (= (pyLower (pairFirst p)) "connection"))) req.headers))
        (secs (stringFromInt64 (ceilSeconds timeoutSec)))
        (follow (if (> maxRedirects 0) (str "location\nmax-redirs = " (stringFromInt64 maxRedirects) "\n") ""))
        (method (if (and (> maxRedirects 0) (= req.method "POST")) (ok "") (configLine "request" req.method)))
        (fixed (list (configLine "url" req.url) (ok "proto = \"=http,https\"\n") method (ok "http1.1\n") (ok "include\n") (ok follow)
                     (ok "silent\n") (ok "show-error\n") (ok (str "connect-timeout = " secs "\n")) (ok (str "speed-time = " secs "\n"))
                     (ok "speed-limit = 1\n")))
        (headerLines (map (fn [(p (Pair String String))] -> (Result String String) (configLine "header" (str (pairFirst p) ": " (pairSecond p)))) hs))
        (tail (list (configLine "data-raw" req.data)
                    (mt caFile ((some f) (configLine "cacert" f)) ((none) (ok "")))))]
    (mt (checkRequest req)
      ((err e) (err e))
      ((ok _) (collectLines (listAppend fixed (listAppend headerLines (listAppend (transportLines hs) tail))) (list)))))

fn statusCode line: String -> (Option (Pair Int64 String))
  (mt (stringIndexOf line " ")
    ((none) none)
    ((some i)
     (let [(rest (stringTrim (slice line i (stringLength line))))
           (sp (stringIndexOf rest " "))
           (codeText (mt sp ((some k) (slice rest 0 k)) ((none) rest)))
           (reason (mt sp ((some k) (stringTrim (slice rest k (stringLength rest)))) ((none) "")))]
       (mt (stringToInt64 codeText)
         ((some c) (if (and (= (stringLength codeText) 3) (>= c 100)) (some (pair c reason)) none))
         ((none) none)))))

fn afterHeaders raw: String eol: Int64 sc: (Pair Int64 String) -> (Result UpstreamResponse String)
  (let [(afterStatus (slice raw eol (stringLength raw)))]
    (mt (stringIndexOf afterStatus "\r\n\r\n")
      ((none) (err "curl output header block is unterminated"))
      ((some end)
       (let [(body (slice afterStatus (+ end 4) (stringLength afterStatus)))]
         (if (or (and (>= (pairFirst sc) 100) (< (pairFirst sc) 200))
                 (and (>= (pairFirst sc) 300) (and (< (pairFirst sc) 400) (stringStartsWith? body "HTTP/"))))
           (parseCurlOutput body)
           (ok (UpstreamResponse :status (pairFirst sc) :reason (pairSecond sc) :body body)))))))

fn parseCurlOutput raw: String -> (Result UpstreamResponse String)
  (if (not (stringStartsWith? raw "HTTP/"))
    (err "curl output has no HTTP status line")
    (mt (stringIndexOf raw "\r\n")
      ((none) (err "curl output status line is unterminated"))
      ((some eol)
       (mt (statusCode (slice raw 0 eol))
         ((none) (err (str "curl output status line is malformed: " (slice raw 0 eol))))
         ((some sc) (afterHeaders raw eol sc))))))

fn httpErrorText status: Int64 reason: String -> String
  (str "HTTP Error " (stringFromInt64 status) ": " reason)

fn pipeWith st: PipeState pending: String inOpen: Bool outOpen: Bool errOpen: Bool out: (List String) errText: (List String) -> PipeState
  (PipeState :pending pending :inOpen inOpen :outOpen outOpen :errOpen errOpen :out out :errText errText)

fn readyFd? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn ! pumpStdin! sp: SpawnedProc st: PipeState -> (Result PipeState String)
  (if (stringEmpty? st.pending)
    (mt (fdClose sp.stdin)
      ((ok _) (ok (pipeWith st "" false st.outOpen st.errOpen st.out st.errText)))
      ((err e) (err (str "curl stdin close: " e))))
    (mt (fdWrite sp.stdin st.pending)
      ((ok k) (ok (pipeWith st (slice st.pending k (stringLength st.pending)) true st.outOpen st.errOpen st.out st.errText)))
      ((err e) (if (= e "wouldBlock") (ok st) (err (str "curl stdin write: " e))))))

fn ! pumpRead! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 1048576)
    ((ok chunk)
     (if (stringEmpty? chunk)
       (mt (fdClose fd) ((ok _) (ok none)) ((err e) (err e)))
       (ok (some chunk))))
    ((err e) (if (= e "wouldBlock") (ok (some "")) (err e))))

fn absorbOut st: PipeState got: (Option String) -> PipeState
  (mt got
    ((none) (pipeWith st st.pending st.inOpen false st.errOpen st.out st.errText))
    ((some c) (if (stringEmpty? c) st (pipeWith st st.pending st.inOpen true st.errOpen (cons c st.out) st.errText))))

fn absorbErr st: PipeState got: (Option String) -> PipeState
  (mt got
    ((none) (pipeWith st st.pending st.inOpen st.outOpen false st.out st.errText))
    ((some c) (if (stringEmpty? c) st (pipeWith st st.pending st.inOpen st.outOpen true st.out (cons c st.errText)))))

fn watchSet sp: SpawnedProc st: PipeState -> (List (Pair Int64 Int64))
  (listAppend (if st.inOpen (list (pair sp.stdin 2)) (list))
              (listAppend (if st.outOpen (list (pair sp.stdout 1)) (list))
                          (if st.errOpen (list (pair sp.stderr 1)) (list))))

fn ! pumpReady! sp: SpawnedProc st: PipeState ready: (List (Pair Int64 Int64)) -> (Result PipeState String)
  (mt (if (and st.inOpen (readyFd? ready sp.stdin)) (pumpStdin! sp st) (ok st))
    ((err e) (err e))
    ((ok s1)
     (mt (if (and s1.outOpen (readyFd? ready sp.stdout)) (pumpRead! sp.stdout) (ok (some "")))
       ((err e) (err (str "curl stdout read: " e)))
       ((ok o)
        (let [(s2 (absorbOut s1 o))]
          (mt (if (and s2.errOpen (readyFd? ready sp.stderr)) (pumpRead! sp.stderr) (ok (some "")))
            ((err e) (err (str "curl stderr read: " e)))
            ((ok r) (ok (absorbErr s2 r)))))))))


fn ! closeOpen! sp: SpawnedProc -> Bool
  (do
    (fdClose sp.stdin)
    (fdClose sp.stdout)
    (fdClose sp.stderr)
    true)

fn curlOutcome code: Int64 out: String errText: String -> (Result UpstreamResponse UpstreamFailure)
  (if (!= code 0)
    (err (transportFailure code errText))
    (mt (parseCurlOutput out)
      ((err e) (err (protocolFailure e)))
      ((ok resp)
       (if (and (>= resp.status 200) (< resp.status 300))
         (ok resp)
         (err (httpFailure resp.status resp.reason resp.body))))))

fn ! finishCurl! sp: SpawnedProc st: PipeState -> (Result UpstreamResponse UpstreamFailure)
  (mt (procWaitPid sp.pid false)
    ((err e) (err (protocolFailure (str "curl wait: " e))))
    ((ok status)
     (mt status
       ((none) (err (protocolFailure "curl wait returned no status")))
       ((some code) (curlOutcome code (joinAll (listReverse st.out)) (joinAll (listReverse st.errText)))))))

fn ! upstreamCallStart! req: UpstreamRequest env: (Map String String) timeoutSec: Float64 -> (Result UpstreamCall UpstreamFailure)
  (upstreamCallStartFollowing! req env timeoutSec 0)

fn ! upstreamCallStartFollowing! req: UpstreamRequest env: (Map String String) timeoutSec: Float64 maxRedirects: Int64 -> (Result UpstreamCall UpstreamFailure)
  (mt (curlConfigFollowing req timeoutSec (nonEmpty (mapGet env "SSL_CERT_FILE")) maxRedirects)
    ((err e) (err (protocolFailure e)))
    ((ok cfg)
     (mt (procSpawnv (curlArgv) (none) (some (childEnv env)))
       ((err e) (err (toolAbsent "curl" (if (= e "notFound") "curl is not on PATH" e))))
       ((ok sp)
        (mt (fdNonBlocking sp.stdin true)
          ((err e) (do (upstreamCallAbort! (UpstreamCall :process sp :pipe (PipeState :pending "" :inOpen true :outOpen true :errOpen true :out (list) :errText (list))))
                     (err (protocolFailure (str "curl stdin nonblocking: " e)))))
          ((ok _) (ok (UpstreamCall :process sp :pipe (PipeState :pending cfg :inOpen true :outOpen true :errOpen true :out (list) :errText (list))))))))))

fn upstreamCallWatch call: UpstreamCall -> (List (Pair Int64 Int64))
  (watchSet call.process call.pipe)

fn upstreamCallOpen? call: UpstreamCall -> Bool
  (let [(st call.pipe)]
    (or st.inOpen (or st.outOpen st.errOpen)))

fn ! upstreamCallAbort! call: UpstreamCall -> Bool
  (let [(sp call.process)]
    (do
      (closeOpen! sp)
      (procKill (- 0 sp.pid) "SIGKILL")
      (procWaitPid sp.pid false)
      true))

fn ! upstreamCallPump! call: UpstreamCall ready: (List (Pair Int64 Int64)) -> (Result UpstreamCall UpstreamFailure)
  (mt (pumpReady! call.process call.pipe ready)
    ((err e) (do (upstreamCallAbort! call) (err (protocolFailure e))))
    ((ok st) (ok (with call :pipe st))))

fn ! upstreamCallFinish! call: UpstreamCall -> (Result UpstreamResponse UpstreamFailure)
  (finishCurl! call.process call.pipe)

fn ! upstreamCallLoop! call: UpstreamCall -> (Result UpstreamResponse UpstreamFailure)
  (if (not (upstreamCallOpen? call))
    (upstreamCallFinish! call)
    (mt (fdPoll (upstreamCallWatch call) -1)
      ((err e) (do (upstreamCallAbort! call) (err (protocolFailure (str "curl pipe poll: " e)))))
      ((ok ready)
       (mt (upstreamCallPump! call ready)
         ((err e) (err e))
         ((ok next) (upstreamCallLoop! next))))))

fn ! callUpstream! req: UpstreamRequest env: (Map String String) timeoutSec: Float64 -> (Result UpstreamResponse UpstreamFailure)
  (mt (upstreamCallStart! req env timeoutSec)
    ((err e) (err e))
    ((ok call) (upstreamCallLoop! call)))
