(module aslGateway/wire
  :x [formatWireHeaders
      isToolCall?
      isDeclarativeAsn?
      extractToolName
      formatToolCallFrame
      demuxRawAsnTurn
      findBalancedParen
      asnEscape
      isBalancedAsnForm?
      isBalancedAsnForm
      asnNumber
      asnNumberOpt
      wantsAsn?
      wantsAsn
      wantsAsnPairs?
      chatReplyUsage
      chatReplyUsageStr
      servedBy
      servedBySimple
      chatReplyAsn
      chatReplyAsnStr
      upstreamErrorReason
      sanitizeAsnContent
      extractOutermostSexpr
      ]
  :i [(asl-json/json :a j)])

fn formatWireHeaders -> (List Str)
  (list "X-ASL-Wire-Protocol: asn/1.0" "X-Tool-Call-Dialect: asn-sexpr" "Accept: application/asn+sexpr, application/json")

fn isToolCall? text: Str -> Bool
  (let [(trimmed (stringTrim text))]
    (or (stringStartsWith? trimmed "(:call :tool")
    (or (stringStartsWith? trimmed "(call :tool")
    (or (stringStartsWith? trimmed "(:call \"")
    (or (stringStartsWith? trimmed "(call \"")
        (stringStartsWith? trimmed "(:tool-call"))))))

fn isDeclarativeAsn? text: Str -> Bool
  (let [(trimmed (stringTrim text))]
    (or (stringStartsWith? trimmed "(:struct")
    (or (stringStartsWith? trimmed "(:ast")
    (or (stringStartsWith? trimmed "(:code")
    (or (stringStartsWith? trimmed "(:config")
    (or (stringStartsWith? trimmed "(:grammar")
    (or (stringStartsWith? trimmed "(:package")
    (or (stringStartsWith? trimmed "(module")
        (stringStartsWith? trimmed "(:model-profile")))))))))

fn extractToolName text: Str -> Str
  (let [(trimmed (stringTrim text))
        (prefix1 "(:call :tool \"")
        (prefix2 "(call :tool \"")
        (prefix3 "(:call \"")
        (prefix4 "(call \"")
        (prefix5 "(:tool-call \"")
        (prefix (if (stringStartsWith? trimmed prefix1) prefix1
                  (if (stringStartsWith? trimmed prefix2) prefix2
                    (if (stringStartsWith? trimmed prefix3) prefix3
                      (if (stringStartsWith? trimmed prefix4) prefix4
                        (if (stringStartsWith? trimmed prefix5) prefix5 ""))))))]
    (if (not (= prefix ""))
      (let [(after (optionOr (stringSlice trimmed (stringLength prefix) (stringLength trimmed)) ""))
            (quoteIdx (stringIndexOf after "\""))]
        (match quoteIdx
          ((some q) (optionOr (stringSlice after 0 q) "tool"))
          ((none) "tool")))
      "tool"))

fn formatToolCallFrame toolName: Str argsAsn: Str -> Str
  (str "(:call :tool \"" toolName "\" :args " argsAsn ")")

fn findBalancedParenLoop text: Str start: I64 depth: I64 inString: Bool escaped: Bool -> I64
  (if (>= start (stringLength text))
    start
    (let [(ch (optionOr (stringSlice text start (+ start 1)) ""))]
      (if inString
        (if escaped
          (findBalancedParenLoop text (+ start 1) depth true false)
          (if (= ch "\\")
            (findBalancedParenLoop text (+ start 1) depth true true)
            (if (= ch "\"")
              (findBalancedParenLoop text (+ start 1) depth false false)
              (findBalancedParenLoop text (+ start 1) depth true false))))
        (if (= ch "\"")
          (findBalancedParenLoop text (+ start 1) depth true false)
          (if (= ch "(")
            (findBalancedParenLoop text (+ start 1) (+ depth 1) false false)
            (if (= ch ")")
              (let [(newDepth (- depth 1))]
                (if (and (> depth 0) (= newDepth 0))
                  (+ start 1)
                  (findBalancedParenLoop text (+ start 1) newDepth false false)))
              (findBalancedParenLoop text (+ start 1) depth false false)))))))

fn findBalancedParen text: Str start: I64 depth: I64 -> I64
  (findBalancedParenLoop text start depth false false)

fn checkToolCall text: Str idx: I64 -> Bool
  (let [(rem12 (optionOr (stringSlice text idx (if (< (+ idx 12) (stringLength text)) (+ idx 12) (stringLength text))) ""))
        (rem9 (optionOr (stringSlice text idx (if (< (+ idx 9) (stringLength text)) (+ idx 9) (stringLength text))) ""))]
    (or (stringStartsWith? rem12 "(:call :tool")
    (or (stringStartsWith? rem12 "(call :tool")
    (or (stringStartsWith? rem12 "(:tool-call")
    (or (stringStartsWith? rem9 "(:call \"")
        (stringStartsWith? rem9 "(call \""))))))

fn demuxLoop text: Str idx: I64 uiAcc: Str toolAcc: (List Str) -> (Pair Str (List Str))
  (if (>= idx (stringLength text))
    (pair (stringTrim uiAcc) toolAcc)
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if (= ch "(")
        (if (checkToolCall text idx)
          (let [(tcEnd (findBalancedParen text idx 0))
                (tcText (optionOr (stringSlice text idx tcEnd) ""))]
            (demuxLoop text tcEnd uiAcc (listAppend toolAcc (list tcText))))
          (demuxLoop text (+ idx 1) (str uiAcc ch) toolAcc))
        (demuxLoop text (+ idx 1) (str uiAcc ch) toolAcc))))

fn demuxRawAsnTurn text: Str -> (Pair Str (List Str))
  (demuxLoop text 0 "" (list))

fn asnEscape s: String -> String
  (stringReplace
    (stringReplace
      (stringReplace
        (stringReplace
          (stringReplace s "\\" "\\\\")
          "\"" "\\\"")
        "\n" "\\n")
      "\r" "\\r")
    "\t" "\\t")

fn isBalancedAsnFormLoop text: String idx: Int64 len: Int64 depth: Int64 inStr: Bool esc: Bool -> Bool
  (if (>= idx len)
    false
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if esc
        (isBalancedAsnFormLoop text (+ idx 1) len depth inStr false)
        (if inStr
          (if (= ch "\\")
            (isBalancedAsnFormLoop text (+ idx 1) len depth true true)
            (if (= ch "\"")
              (isBalancedAsnFormLoop text (+ idx 1) len depth false false)
              (isBalancedAsnFormLoop text (+ idx 1) len depth true false)))
          (if (= ch "\"")
            (isBalancedAsnFormLoop text (+ idx 1) len depth true false)
            (if (= ch "(")
              (isBalancedAsnFormLoop text (+ idx 1) len (+ depth 1) false false)
              (if (= ch ")")
                (let [(newDepth (- depth 1))]
                  (if (< newDepth 0)
                    false
                    (if (= newDepth 0)
                      (= (+ idx 1) len)
                      (isBalancedAsnFormLoop text (+ idx 1) len newDepth false false))))
                (isBalancedAsnFormLoop text (+ idx 1) len depth false false))))))))

fn isBalancedAsnForm? text: String -> Bool
  (let [(s (stringTrim text))
        (len (stringLength s))]
    (if (or (= len 0) (not (stringStartsWith? s "(")))
      false
      (isBalancedAsnFormLoop s 0 len 0 false false)))

fn isBalancedAsnForm text: String -> Bool
  (isBalancedAsnForm? text)

fn asnNumber j: j/Json -> (Option String)
  (match j
    ((j/jint i) (some (stringFromInt64 i)))
    ((j/jfloat f) (some (stringFromFloat64 f)))
    ((j/jnum n) (some (stringFromFloat64 n)))
    (_ none))

fn asnNumberOpt opt: (Option j/Json) -> (Option String)
  (match opt
    ((some v) (asnNumber v))
    ((none) none))

fn getHeaderValLoop headers: (List String) targetLower: String -> (Option String)
  (if (listEmpty? headers)
    none
    (let [(h (optionOr (listHead headers) ""))
          (rest (optionOr (listTail headers) (list)))
          (colonIdx (stringIndexOf h ":"))]
      (match colonIdx
        ((some idx)
         (let [(name (stringTrim (stringLower (optionOr (stringSlice h 0 idx) ""))))
               (val (stringTrim (optionOr (stringSlice h (+ idx 1) (stringLength h)) "")))]
           (if (= name targetLower)
             (some val)
             (getHeaderValLoop rest targetLower))))
        ((none) (getHeaderValLoop rest targetLower)))))

fn wantsAsn? headers: (List String) -> Bool
  (let [(acceptVal (optionOr (getHeaderValLoop headers "accept") ""))
        (wireVal (stringLower (stringTrim (optionOr (getHeaderValLoop headers "x-asl-wire") ""))))]
    (or (stringContains? acceptVal "application/asn+sexpr") (= wireVal "asn")))

fn wantsAsn headers: (List String) -> Bool
  (wantsAsn? headers)

fn getPairValLoop pairs: (List (Pair String String)) targetLower: String -> (Option String)
  (if (listEmpty? pairs)
    none
    (let [(p (optionOr (listHead pairs) (pair "" "")))
          (rest (optionOr (listTail pairs) (list)))
          (k (stringTrim (stringLower (pairFirst p))))
          (v (stringTrim (pairSecond p)))]
      (if (= k targetLower)
        (some v)
        (getPairValLoop rest targetLower))))

fn wantsAsnPairs? pairs: (List (Pair String String)) -> Bool
  (let [(acceptVal (optionOr (getPairValLoop pairs "accept") ""))
        (wireVal (stringLower (stringTrim (optionOr (getPairValLoop pairs "x-asl-wire") ""))))]
    (or (stringContains? acceptVal "application/asn+sexpr") (= wireVal "asn")))

fn asJobj j: j/Json -> (Option (List (Pair String j/Json)))
  (match j
    ((j/jobj kvs) (some kvs))
    (_ none))

fn asJstr j: j/Json -> (Option String)
  (match j
    ((j/jstr s) (some s))
    (_ none))

fn getPropLoop kvs: (List (Pair String j/Json)) key: String -> (Option j/Json)
  (if (listEmpty? kvs)
    none
    (let [(p (optionOr (listHead kvs) (pair "" (j/jnull))))
          (rest (optionOr (listTail kvs) (list)))]
      (if (= (pairFirst p) key)
        (some (pairSecond p))
        (getPropLoop rest key))))

fn getObjProp obj: j/Json key: String -> (Option j/Json)
  (match (asJobj obj)
    ((some kvs) (getPropLoop kvs key))
    ((none) none))

fn getObjObj obj: j/Json key: String -> (Option (List (Pair String j/Json)))
  (match (getObjProp obj key)
    ((some j) (asJobj j))
    ((none) none))

fn chatReplyUsageStandard respJson: j/Json -> (Option String)
  (match (getObjObj respJson "usage")
    ((some uKvs)
     (let [(inOpt (asnNumberOpt (getPropLoop uKvs "prompt_tokens")))
           (outOpt (asnNumberOpt (getPropLoop uKvs "completion_tokens")))
           (directCachedOpt (match (asnNumberOpt (getPropLoop uKvs "cached_tokens"))
                              ((some c) (some c))
                              ((none) (asnNumberOpt (getPropLoop uKvs "prompt_cache_hit_tokens")))))
           (writeOpt (asnNumberOpt (getPropLoop uKvs "cache_creation_tokens")))
           (writeStr (match writeOpt ((some w) (if (= w "0") "" (str " :cacheWrite " w))) ((none) "")))
           (ptdOpt (getPropLoop uKvs "prompt_tokens_details"))
           (ptdCachedOpt (match ptdOpt
                           ((some ptdVal)
                            (match (asJobj ptdVal)
                              ((some ptdKvs) (asnNumberOpt (getPropLoop ptdKvs "cached_tokens")))
                              ((none) none)))
                           ((none) none)))
           (cachedStr (match directCachedOpt
                        ((some c) c)
                        ((none) (optionOr ptdCachedOpt "0"))))]
       (match inOpt
         ((some inNum)
          (match outOpt
            ((some outNum) (some (str "(:input " inNum " :cached " cachedStr writeStr " :output " outNum ")")))
            ((none) none)))
         ((none) none))))
    ((none) none))

fn chatReplyUsage respJson: j/Json -> (Option String)
  (match (getObjObj respJson "asl")
    ((some aslKvs)
     (match (getPropLoop aslKvs "usage")
       ((some uVal)
        (match (asJobj uVal)
          ((some uKvs)
           (let [(inOpt (asnNumberOpt (getPropLoop uKvs "inputTokens")))
                 (cachedOpt (asnNumberOpt (getPropLoop uKvs "cachedTokens")))
                 (outOpt (asnNumberOpt (getPropLoop uKvs "outputTokens")))
                 (cachedStr (optionOr cachedOpt "0"))]
             (match inOpt
               ((some inNum)
                (match outOpt
                  ((some outNum) (some (str "(:input " inNum " :cached " cachedStr " :output " outNum ")")))
                  ((none) none)))
               ((none) none))))
          ((none) (chatReplyUsageStandard respJson))))
       ((none) (chatReplyUsageStandard respJson))))
    ((none) (chatReplyUsageStandard respJson)))

fn chatReplyUsageStr jsonStr: String -> (Option String)
  (match (j/jsonParse jsonStr)
    ((ok parsed) (chatReplyUsage parsed))
    ((err _) none))

fn gatewayEntryLabel e: j/Json -> String
  (match e
    ((j/jobj kvs)
     (match (getPropLoop kvs "alias")
       ((some val)
        (match val
          ((j/jstr a) a)
          (_ (j/jsonEmit val))))
       ((none) "")))
    ((j/jstr s) s)
    (_ (j/jsonEmit e)))

fn servedBy entry: j/Json v2Entry: Bool fallbackModel: String body: (Option j/Json) sentEffort: (Option String) -> j/Json
  (let [(aliasStr (if v2Entry (gatewayEntryLabel entry) fallbackModel))
        (baseKvs (list (pair "alias" (j/jstr aliasStr))))
        (kvsWithEffort (match sentEffort
                         ((some eff)
                          (if (not (stringEmpty? eff))
                            (listAppend baseKvs (list (pair "effort" (j/jstr eff))))
                            baseKvs))
                         ((none) baseKvs)))
        (finalKvs (match body
                    ((some b)
                     (match (asJobj b)
                       ((some bodyKvs)
                        (match (getPropLoop bodyKvs "temperature")
                          ((some temp) (listAppend kvsWithEffort (list (pair "temperature" temp))))
                          ((none) kvsWithEffort)))
                       ((none) kvsWithEffort)))
                    ((none) kvsWithEffort)))]
    (j/jobj finalKvs))

fn servedBySimple entryAlias: String v2Entry: Bool fallbackModel: String body: (Option j/Json) sentEffort: (Option String) -> j/Json
  (servedBy (j/jstr entryAlias) v2Entry fallbackModel body sentEffort)

fn asnValue j: j/Json -> String
  (match j
    ((j/jbool b) (if b "true" "false"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum n) (stringFromFloat64 n))
    ((j/jnull) "nil")
    ((j/jstr s) (str "\"" (asnEscape s) "\""))
    (_ (str "\"" (asnEscape (j/jsonEmit j)) "\"")))

fn extractFirstChoice respJson: j/Json -> (Option (List (Pair String j/Json)))
  (match (getObjProp respJson "choices")
    ((some cJson)
     (match cJson
       ((j/jarr cs)
        (if (listEmpty? cs)
          none
          (let [(firstC (optionOr (listHead cs) (j/jnull)))]
            (asJobj firstC))))
       (_ none)))
    ((none) none))

fn hexDigitVal n: Int64 -> String
  (let [(hex "0123456789abcdef")]
    (optionOr (stringSlice hex (mod n 16) (+ (mod n 16) 1)) "0"))

fn hex4Digits cp: Int64 -> String
  (let [(d0 (/ cp 4096))
        (d1 (/ (mod cp 4096) 256))
        (d2 (/ (mod cp 256) 16))
        (d3 (mod cp 16))]
    (str (hexDigitVal d0) (hexDigitVal d1) (hexDigitVal d2) (hexDigitVal d3)))

fn escapeCtrlChar b: Int64 -> String
  (str "\\u00" (hexDigitVal (/ b 16)) (hexDigitVal (mod b 16)))

fn scanPythonJsonStr s: String bs: Bytes len: Int64 pos: Int64 start: Int64 pieces: (List String) -> String
  (if (>= pos len)
    (let [(tail (optionOr (stringSlice s start len) ""))
          (all (cons tail pieces))]
      (str "\"" (stringJoin (listReverse all) "") "\""))
    (let [(b (bytesGet bs pos))]
      (cond
        ((= b 34) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\\"" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 92) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\\\" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 8)  (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\b" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 9)  (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\t" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 10) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\n" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 12) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\f" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 13) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\r" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((< b 32) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons (escapeCtrlChar b) (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 127) (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons "\\u007f" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((< b 127) (scanPythonJsonStr s bs len (+ pos 1) start pieces))
        ((< b 192)
         (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons (escapeCtrlChar b) (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((< b 224)
         (if (< (+ pos 1) len)
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (cp (+ (* (- b 192) 64) (- b1 128)))
                 (esc (str "\\u" (hex4Digits cp)))]
             (scanPythonJsonStr s bs len (+ pos 2) (+ pos 2) (cons esc (cons (optionOr (stringSlice s start pos) "") pieces))))
           (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons (escapeCtrlChar b) (cons (optionOr (stringSlice s start pos) "") pieces)))))
        ((< b 240)
         (if (< (+ pos 2) len)
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (b2 (bytesGet bs (+ pos 2)))
                 (cp (+ (* (+ (* (- b 224) 64) (- b1 128)) 64) (- b2 128)))
                 (esc (str "\\u" (hex4Digits cp)))]
             (scanPythonJsonStr s bs len (+ pos 3) (+ pos 3) (cons esc (cons (optionOr (stringSlice s start pos) "") pieces))))
           (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons (escapeCtrlChar b) (cons (optionOr (stringSlice s start pos) "") pieces)))))
        (else
         (if (< (+ pos 3) len)
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (b2 (bytesGet bs (+ pos 2)))
                 (b3 (bytesGet bs (+ pos 3)))
                 (cp (+ (* (+ (* (+ (* (- b 240) 64) (- b1 128)) 64) (- b2 128)) 64) (- b3 128)))
                 (off (- cp 65536))
                 (lead (+ 55296 (/ off 1024)))
                 (trail (+ 56320 (mod off 1024)))
                 (esc (str "\\u" (hex4Digits lead) "\\u" (hex4Digits trail)))]
             (scanPythonJsonStr s bs len (+ pos 4) (+ pos 4) (cons esc (cons (optionOr (stringSlice s start pos) "") pieces))))
           (scanPythonJsonStr s bs len (+ pos 1) (+ pos 1) (cons (escapeCtrlChar b) (cons (optionOr (stringSlice s start pos) "") pieces))))))))

fn emitPythonJsonString s: String -> String
  (let [(bs (stringToBytes s))
        (len (bytesLength bs))]
    (scanPythonJsonStr s bs len 0 0 (list)))

fn emitPythonJsonPair p: (Pair String j/Json) -> String
  (match p
    ((pair k v) (str (emitPythonJsonString k) ": " (pyJsonEmit v))))

fn pyJsonEmit val: j/Json -> String
  (match val
    ((j/jnull) "null")
    ((j/jbool b) (if b "true" "false"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum n) (stringFromFloat64 n))
    ((j/jstr s) (emitPythonJsonString s))
    ((j/jarr xs)
     (if (listEmpty? xs)
       "[]"
       (str "[" (stringJoin (map pyJsonEmit xs) ", ") "]")))
    ((j/jobj kvs)
     (if (listEmpty? kvs)
       "{}"
       (str "{" (stringJoin (map emitPythonJsonPair kvs) ", ") "}"))))

fn extractContentStr msgOpt: (Option (List (Pair String j/Json))) -> String
  (match msgOpt
    ((some mkvs)
     (match (getPropLoop mkvs "content")
       ((some val)
        (match val
          ((j/jstr s) s)
          ((j/jnull) "")
          (_ (pyJsonEmit val))))
       ((none) "")))
    ((none) ""))

fn chatReplyAsn respJson: j/Json -> String
  (let [(modelStr (match (getObjProp respJson "model")
                    ((some mJson) (optionOr (asJstr mJson) ""))
                    ((none) "")))
        (choiceOpt (extractFirstChoice respJson))
        (msgOpt (match choiceOpt
                  ((some ckvs)
                   (match (getPropLoop ckvs "message")
                     ((some mJson) (asJobj mJson))
                     ((none) none)))
                  ((none) none)))
        (contentStr (extractContentStr msgOpt))
        (contentAsn (if (isBalancedAsnForm? contentStr)
                      (stringTrim contentStr)
                      (str "\"" (asnEscape contentStr) "\"")))
        (finishStr (match choiceOpt
                     ((some ckvs)
                      (match (getPropLoop ckvs "finish_reason")
                        ((some frJson)
                         (match (asJstr frJson)
                           ((some fr) (if (stringEmpty? fr) "stop" fr))
                           ((none) "stop")))
                        ((none) "stop")))
                     ((none) "stop")))
        (servedOpt (getObjObj respJson "asl"))
        (partModel (list (str ":model \"" (asnEscape modelStr) "\"")))
        (partContent (list (str ":content " contentAsn)))
        (partServed (match servedOpt
                      ((some aslKvs)
                       (let [(aPart (match (getPropLoop aslKvs "alias")
                                      ((some v) (if (match v ((j/jnull) true) (_ false)) (list) (list (str ":alias " (asnValue v)))))
                                      ((none) (list))))
                             (ePart (match (getPropLoop aslKvs "effort")
                                      ((some v) (if (match v ((j/jnull) true) (_ false)) (list) (list (str ":effort " (asnValue v)))))
                                      ((none) (list))))
                             (tPart (match (getPropLoop aslKvs "temperature")
                                      ((some v) (if (match v ((j/jnull) true) (_ false)) (list) (list (str ":temperature " (asnValue v)))))
                                      ((none) (list))))
                             (cPart (match (getPropLoop aslKvs "contextTokens")
                                      ((some v) (if (match v ((j/jnull) true) (_ false)) (list) (list (str ":contextTokens " (asnValue v)))))
                                      ((none) (list))))]
                         (listAppend aPart (listAppend ePart (listAppend tPart cPart)))))
                      ((none) (list))))
        (partFinish (list (str ":finish \"" (asnEscape finishStr) "\"")))
        (usageOpt (chatReplyUsage respJson))
        (partUsage (match usageOpt
                     ((some u) (list (str ":usage " u)))
                     ((none) (list))))
        (partAsl (match servedOpt
                   ((some aslKvs)
                    (let [(poolPart (match (getPropLoop aslKvs "pool")
                                      ((some pJson)
                                       (match (asJstr pJson)
                                         ((some p) (list (str ":pool \"" (asnEscape p) "\"")))
                                         ((none) (if (match pJson ((j/jnull) true) (_ false))
                                                   (list)
                                                   (list (str ":pool \"" (asnEscape (pyJsonEmit pJson)) "\""))))))
                                      ((none) (list))))
                          (qPart (match (asnNumberOpt (getPropLoop aslKvs "queueWaitSec"))
                                   ((some q) (list (str ":queueWaitSec " q)))
                                   ((none) (list))))
                          (execPart (match (asnNumberOpt (getPropLoop aslKvs "execSec"))
                                      ((some e) (list (str ":execSec " e)))
                                      ((none) (list))))
                          (aslItems (listAppend poolPart (listAppend qPart execPart)))]
                      (if (listEmpty? aslItems)
                        (list)
                        (list (str ":asl (" (stringJoin aslItems " ") ")")))))
                   ((none) (list))))
        (allParts (listAppend partModel
                    (listAppend partContent
                      (listAppend partServed
                        (listAppend partFinish
                          (listAppend partUsage partAsl))))))]
    (str "(:reply " (stringJoin allParts " ") ")\n"))

fn chatReplyAsnStr jsonStr: String -> String
  (match (j/jsonParse jsonStr)
    ((ok parsed) (chatReplyAsn parsed))
    ((err _) "(:reply :model \"\" :content \"\" :finish \"stop\")\n"))

fn fallbackErrorText errData: String fallbackErr: String -> String
  (let [(trimmed (stringTrim errData))]
    (if (stringEmpty? trimmed)
      fallbackErr
      (if (> (stringLength trimmed) 500)
        (optionOr (stringSlice trimmed 0 500) trimmed)
        trimmed)))

fn upstreamErrorReason errData: String fallbackErr: String -> String
  (match (j/jsonParse errData)
    ((ok parsed)
     (match (asJobj parsed)
       ((some kvs)
        (match (getPropLoop kvs "error")
          ((some errVal)
           (match errVal
             ((j/jobj errKvs)
              (match (getPropLoop errKvs "message")
                ((some msgVal)
                 (match (asJstr msgVal)
                   ((some msg) msg)
                   ((none) (fallbackErrorText errData fallbackErr))))
                ((none) (fallbackErrorText errData fallbackErr))))
             ((j/jstr errStr) errStr)
             (_ (fallbackErrorText errData fallbackErr))))
          ((none) (fallbackErrorText errData fallbackErr))))
       ((none) (fallbackErrorText errData fallbackErr))))
    ((err _) (fallbackErrorText errData fallbackErr)))

fn extractOutermostSexpLoop text: String idx: Int64 len: Int64 start: Int64 depth: Int64 inStr: Bool esc: Bool -> (Option String)
  (if (>= idx len)
    none
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if esc
        (extractOutermostSexpLoop text (+ idx 1) len start depth inStr false)
        (if inStr
          (if (= ch "\\")
            (extractOutermostSexpLoop text (+ idx 1) len start depth true true)
            (if (= ch "\"")
              (extractOutermostSexpLoop text (+ idx 1) len start depth false false)
              (extractOutermostSexpLoop text (+ idx 1) len start depth true false)))
          (if (= ch "\"")
            (extractOutermostSexpLoop text (+ idx 1) len start depth true false)
            (if (= ch "(")
              (extractOutermostSexpLoop text (+ idx 1) len start (+ depth 1) false false)
              (if (= ch ")")
                (let [(newDepth (- depth 1))]
                  (if (= newDepth 0)
                    (stringSlice text start (+ idx 1))
                    (extractOutermostSexpLoop text (+ idx 1) len start newDepth false false)))
                (extractOutermostSexpLoop text (+ idx 1) len start depth false false))))))))

fn extractOutermostSexp text: String -> (Option String)
  (match (stringIndexOf text "(")
    ((some start) (extractOutermostSexpLoop text start (stringLength text) start 0 false false))
    ((none) none))

fn isFenceChar? ch: String -> Bool
  (or (and (>= ch "a") (<= ch "z"))
  (or (and (>= ch "A") (<= ch "Z"))
  (or (and (>= ch "0") (<= ch "9"))
  (or (= ch "_") (= ch "-")))))

fn skipFenceLang text: String pos: Int64 len: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(ch (optionOr (stringSlice text pos (+ pos 1)) ""))]
      (if (isFenceChar? ch)
        (skipFenceLang text (+ pos 1) len)
        pos)))

fn skipFenceSpaces text: String pos: Int64 len: Int64 -> Int64
  (if (>= pos len)
    pos
    (let [(ch (optionOr (stringSlice text pos (+ pos 1)) ""))]
      (if (or (= ch " ") (= ch "\t"))
        (skipFenceSpaces text (+ pos 1) len)
        pos)))

fn extractFenceCandidate s: String -> String
  (match (stringIndexOf s "```")
    ((some openIdx)
     (let [(len (stringLength s))
           (afterOpen (+ openIdx 3))
           (afterLang (skipFenceLang s afterOpen len))
           (afterSpaces (skipFenceSpaces s afterLang len))
           (afterCr (if (and (< afterSpaces len) (= (optionOr (stringSlice s afterSpaces (+ afterSpaces 1)) "") "\r"))
                      (+ afterSpaces 1)
                      afterSpaces))
           (bodyStart (if (and (< afterCr len) (= (optionOr (stringSlice s afterCr (+ afterCr 1)) "") "\n"))
                        (+ afterCr 1)
                        afterCr))
           (remaining (optionOr (stringSlice s bodyStart len) ""))
           (closeRel (stringIndexOf remaining "```"))]
       (match closeRel
         ((some relIdx)
          (stringTrim (optionOr (stringSlice s bodyStart (+ bodyStart relIdx)) "")))
         ((none) s))))
    ((none) s))

fn sanitizeAsnContent content: String -> String
  (let [(s (stringTrim content))
        (candidate (extractFenceCandidate s))
        (extractedCand (extractOutermostSexp candidate))
        (extracted (match extractedCand
                     ((some e) (some e))
                     ((none)
                      (if (!= candidate s)
                        (extractOutermostSexp s)
                        none))))]
    (match extracted
      ((some found) (stringTrim found))
      ((none)
       (let [(escaped (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" " "))
             (raw (if (> (stringLength escaped) 200)
                    (str (optionOr (stringSlice escaped 0 197) "") "...")
                    escaped))]
         (str "(:error :reason \"unbalanced_non_asn\" :raw \"" raw "\")")))))

fn findRootIndex text: String roots: (List String) -> (Option Int64)
  (if (listEmpty? roots)
    none
    (let [(root (optionOr (listHead roots) ""))
          (idx (stringIndexOf text root))]
      (match idx
        ((some i) (some i))
        ((none) (findRootIndex text (optionOr (listTail roots) (list)))))))

fn extractOutermostSexprLoop text: String idx: Int64 len: Int64 start: Int64 stack: (List String) inStr: Bool esc: Bool -> (Option String)
  (if (>= idx len)
    none
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if esc
        (extractOutermostSexprLoop text (+ idx 1) len start stack inStr false)
        (if inStr
          (if (= ch "\\")
            (extractOutermostSexprLoop text (+ idx 1) len start stack true true)
            (if (= ch "\"")
              (extractOutermostSexprLoop text (+ idx 1) len start stack false false)
              (extractOutermostSexprLoop text (+ idx 1) len start stack true false)))
          (if (= ch "\"")
            (extractOutermostSexprLoop text (+ idx 1) len start stack true false)
            (if (or (= ch "(") (= ch "["))
              (extractOutermostSexprLoop text (+ idx 1) len start (cons ch stack) false false)
              (if (or (= ch ")") (= ch "]"))
                (if (listEmpty? stack)
                  none
                  (let [(top (optionOr (listHead stack) ""))
                        (expected (if (= ch ")") "(" "["))]
                    (if (!= top expected)
                      none
                      (let [(newStack (optionOr (listTail stack) (list)))]
                        (if (listEmpty? newStack)
                          (stringSlice text start (+ idx 1))
                          (extractOutermostSexprLoop text (+ idx 1) len start newStack false false))))))
                (extractOutermostSexprLoop text (+ idx 1) len start stack false false))))))))

fn extractOutermostSexpr text: String -> (Option String)
  (if (stringEmpty? text)
    none
    (let [(roots (list "(:researchReport" "(:researchTriage" "(:searchResults" "(:rawEvidence" "(:"))
          (startOpt (findRootIndex text roots))]
      (match startOpt
        ((some start)
         (extractOutermostSexprLoop text start (stringLength text) start (list) false false))
        ((none) none))))

