(module aslGateway/cliDispatch
  :x [CliUsage
      CliParseResult
      CliVersionInfo
      CliPromptDir
      DispatchOptions
      CliProvider
      cliProviders
      cliProviderNamed
      cliProviderBin!
      cliProviderHealth!
      defaultDispatchOptions
      resolve_cli_bin!
      resolveCliBin!
      resolveCliBinFromLocations!
      cli_versions!
      cliVersions!
      cli_message_text
      cliMessageText
      cli_agy_tools!
      cliAgyTools!
      cli_write_prompt_dir!
      cliWritePromptDir!
      cliWritePromptDirAt!
      cliWritePromptDirFrom!
      cli_json_object
      cliJsonObject
      cli_parse_result
      cliParseResult
      dispatch_codex_fallback!
      dispatchCodexFallback!
      dispatch_agy_fallback!
      dispatchAgyFallback!
      dispatch_claude_fallback!
      dispatchClaudeFallback!
      codexBuildCmd
      agyBuildCmd!
      claudeBuildCmd!
      buildEnvString!
      runSpawnDispatch!
      agyAgentMarkdown
      jsonIntField
      gatewayCliMain
      main]
  :i [(asl-json/json :a j)
      (config :a cfg)
      (asl/packages/asl-cli/src/system :a sys)])

(schema CliUsage
  (:f inputTokens Int64)
  (:f cachedTokens Int64)
  (:f outputTokens Int64))

(schema CliParseResult
  (:f text String)
  (:f usage (Option CliUsage))
  (:f dedup Bool))

(schema CliVersionInfo
  (:f name String)
  (:f bin String)
  (:f version String))

(schema CliPromptDir
  (:f tmpDir String)
  (:f promptPath String))

(schema DispatchOptions
  (:f model (Option String))
  (:f effort (Option String))
  (:f timeout Int64)
  (:f workspace (Option String))
  (:f systemPrompt (Option String))
  (:f noTools Bool)
  (:f agent (Option String))
  (:f addDirs (List String))
  (:f cliBin (Option String)))

(schema CliProvider
  (:f id String)
  (:f binEnv String)
  (:f binName String)
  (:f binLegacy String)
  (:f keyVars (List String))
  (:f agentLayout Bool)
  (:f parse (fn [String] -> CliParseResult)))

fn cliProviders -> (List CliProvider)
  (list
    (CliProvider :id "claude" :binEnv "CLAUDE_BIN" :binName "claude" :binLegacy "/usr/local/bin/claude"
      :keyVars (list "ANTHROPIC_API_KEY" "CLAUDE_API_KEY") :agentLayout false
      :parse parseClaudeResult)
    (CliProvider :id "codex" :binEnv "CODEX_BIN" :binName "codex" :binLegacy "/opt/homebrew/bin/codex"
      :keyVars (list "OPENAI_API_KEY" "CODEX_API_KEY") :agentLayout false
      :parse parseCodexResult)
    (CliProvider :id "agy" :binEnv "AGY_BIN" :binName "agy" :binLegacy ""
      :keyVars (list "GEMINI_API_KEY" "GOOGLE_API_KEY" "AGY_API_KEY") :agentLayout true
      :parse parseAgyResult))

fn firstCliProvider id: String rows: (List CliProvider) -> (Option CliProvider)
  (if (listEmpty? rows) none
    (if (= (preludeHead rows).id id) (some (preludeHead rows)) (firstCliProvider id (preludeTail rows))))

fn cliProviderNamed id: String -> (Option CliProvider)
  (firstCliProvider id (cliProviders))

fn ! cliProviderBin! row: CliProvider -> String
  (resolveCliBin! row.binEnv row.binName row.binLegacy)

fn ! cliProviderHealth! row: CliProvider -> (Result String String)
  (let [(bin (cliProviderBin! row))]
    (if (not (fileExists? bin))
      (err (str row.binEnv " not found: " bin))
      (ok (probeCliVersion! row.id bin).version)))

fn gatewayHexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn gatewayHex4 n: Int64 -> String
  (str (gatewayHexDigit (mod (/ n 4096) 16))
       (gatewayHexDigit (mod (/ n 256) 16))
       (gatewayHexDigit (mod (/ n 16) 16))
       (gatewayHexDigit (mod n 16)))

fn gatewayJsonQuotedBytes text: String bs: Bytes pos: Int64 -> String
  (if (>= pos (- (stringLength text) 1))
    ""
    (let [(b (bytesGet bs pos))]
      (if (< b 128)
        (str (if (= b 127) "\\u007f" (optionOr (stringSlice text pos (+ pos 1)) ""))
             (gatewayJsonQuotedBytes text bs (+ pos 1)))
        (let [(width (if (< b 224) 2 (if (< b 240) 3 4)))
              (b1 (bytesGet bs (+ pos 1)))
              (leadMask (if (> width 3) 7 (if (> width 2) 15 31)))
              (cp1 (+ (* (& b leadMask) 64) (& b1 63)))
              (b2 (if (> width 2) (bytesGet bs (+ pos 2)) 0))
              (cp2 (if (> width 2) (+ (* cp1 64) (& b2 63)) cp1))
              (b3 (if (> width 3) (bytesGet bs (+ pos 3)) 0))
              (cp (if (> width 3) (+ (* cp2 64) (& b3 63)) cp2))
              (escaped (if (<= cp 65535)
                         (str "\\u" (gatewayHex4 cp))
                         (let [(n (- cp 65536))]
                           (str "\\u" (gatewayHex4 (+ 55296 (/ n 1024))) "\\u" (gatewayHex4 (+ 56320 (mod n 1024)))))))]
          (str escaped (gatewayJsonQuotedBytes text bs (+ pos width)))))))

fn gatewayJsonQuoted s: String -> String
  (let [(encoded (j/jsonEmit (j/jstr s)))]
    (str "\"" (gatewayJsonQuotedBytes encoded (stringToBytes encoded) 1) "\""))

fn gatewayJsonFinalValue kvs: (List (Pair String j/Json)) key: String fallback: j/Json -> j/Json
  (if (listEmpty? kvs) fallback
    (let [(kv (preludeHead kvs))
          (value (if (= (pairFirst kv) key) (pairSecond kv) fallback))]
      (gatewayJsonFinalValue (preludeTail kvs) key value)))

fn gatewayJsonNumberEnd text: String pos: Int64 len: Int64 -> Int64
  (if (>= pos len) pos
    (let [(c (optionOr (stringSlice text pos (+ pos 1)) ""))]
      (if (or (stringContains? ",]} \t\r\n" c) (stringEmpty? c))
        pos
        (gatewayJsonNumberEnd text (+ pos 1) len))))

fn gatewayJsonCountValues values: (List j/Json) -> Int64
  (if (listEmpty? values) 0
    (let [(value (preludeHead values))]
      (+ (gatewayJsonNumberCount value) (gatewayJsonCountValues (preludeTail values)))))

fn gatewayJsonCountKvs kvs: (List (Pair String j/Json)) -> Int64
  (if (listEmpty? kvs) 0
    (let [(kv (preludeHead kvs))]
      (+ (gatewayJsonNumberCount (pairSecond kv)) (gatewayJsonCountKvs (preludeTail kvs)))))

fn gatewayJsonNumberCount value: j/Json -> Int64
  (mt value
    ((j/jint _) 1)
    ((j/jfloat _) 1)
    ((j/jnum _) 1)
    ((j/jarr xs) (gatewayJsonCountValues xs))
    ((j/jobj kvs) (gatewayJsonCountKvs kvs))
    (_ 0))

fn gatewayJsonNumberToken text: String pos: Int64 len: Int64 inString: Bool escaped: Bool index: Int64 -> (Option String)
  (if (>= pos len) none
    (let [(c (optionOr (stringSlice text pos (+ pos 1)) ""))]
      (if inString
        (cond
          (escaped (gatewayJsonNumberToken text (+ pos 1) len true false index))
          ((= c "\\") (gatewayJsonNumberToken text (+ pos 1) len true true index))
          ((= c "\"") (gatewayJsonNumberToken text (+ pos 1) len false false index))
          (else (gatewayJsonNumberToken text (+ pos 1) len true false index)))
        (cond
          ((= c "\"") (gatewayJsonNumberToken text (+ pos 1) len true false index))
          ((or (= c "-") (stringContains? "0123456789" c))
            (let [(end (gatewayJsonNumberEnd text pos len))]
              (if (= index 0)
                (stringSlice text pos end)
                (gatewayJsonNumberToken text end len false false (- index 1)))))
          (else (gatewayJsonNumberToken text (+ pos 1) len false false index))))))

fn gatewayJsonFloatSource source: String index: Int64 value: Float64 -> String
  (mt (gatewayJsonNumberToken source 0 (stringLength source) false false index)
    ((some token)
      (if (or (stringContains? token ".") (or (stringContains? token "e") (stringContains? token "E")))
        (stringFromFloat64 value)
        token))
    ((none) (stringFromFloat64 value)))

fn gatewayJsonFinalIndex kvs: (List (Pair String j/Json)) key: String offset: Int64 selected: Int64 -> Int64
  (if (listEmpty? kvs) selected
    (let [(kv (preludeHead kvs))
          (rest (preludeTail kvs))
          (value (pairSecond kv))
          (nextSelected (if (= (pairFirst kv) key) offset selected))]
      (gatewayJsonFinalIndex rest key (+ offset (gatewayJsonNumberCount value)) nextSelected)))

fn gatewayJsonArraySourceAt values: (List j/Json) source: String index: Int64 -> String
  (if (listEmpty? values) ""
    (let [(value (preludeHead values)) (rest (preludeTail values))]
      (str (gatewayJsonAsnSourceAt value source index)
           (if (listEmpty? rest) "" " ")
           (gatewayJsonArraySourceAt rest source (+ index (gatewayJsonNumberCount value))))))

fn gatewayJsonObjectFieldsAt kvs: (List (Pair String j/Json)) seen: (List String) source: String index: Int64 -> String
  (if (listEmpty? kvs) ""
    (let [(kv (preludeHead kvs))
          (key (pairFirst kv))
          (rest (preludeTail kvs))
          (value (pairSecond kv))
          (nextIndex (+ index (gatewayJsonNumberCount value)))]
      (if (listContains? seen key)
        (gatewayJsonObjectFieldsAt rest seen source nextIndex)
        (let [(finalValue (gatewayJsonFinalValue rest key value))
              (valueIndex (gatewayJsonFinalIndex kvs key index index))
              (field (str " :" key " " (gatewayJsonAsnSourceAt finalValue source valueIndex)))]
          (str field (gatewayJsonObjectFieldsAt rest (cons key seen) source nextIndex))))))

fn gatewayJsonAsnSourceAt value: j/Json source: String index: Int64 -> String
  (mt value
    ((j/jnull) "nil")
    ((j/jbool b) (if b "true" "false"))
    ((j/jint n) (stringFromInt64 n))
    ((j/jfloat n) (gatewayJsonFloatSource source index n))
    ((j/jnum n) (gatewayJsonFloatSource source index n))
    ((j/jstr s) (gatewayJsonQuoted s))
    ((j/jarr xs) (str "[" (gatewayJsonArraySourceAt xs source index) "]"))
    ((j/jobj kvs) (str "(:record" (gatewayJsonObjectFieldsAt kvs (list) source index) ")")))

fn gatewayCliArg args: (List String) index: Int64 -> String
  (optionOr (listGet args index) "")

fn ! gatewayCliConvert! path: String -> (Result Int64 String)
  (mt (fileReadString path)
    ((err e) (do (sys/sayErr! (str "Conversion error: " e)) (ok 1)))
    ((ok text)
      (mt (j/jsonParse text)
        ((err e) (do (sys/sayErr! (str "Conversion error: " e)) (ok 1)))
        ((ok value) (do (sys/say! (gatewayJsonAsnSourceAt value text 0)) (ok 0))))))

fn gatewayUtf8Continuation b: Int64 -> Bool
  (and (>= b 128) (<= b 191))

fn gatewayUtf8ValidBytes bs: Bytes pos: Int64 len: Int64 -> Bool
  (if (>= pos len) true
    (let [(b (bytesGet bs pos))]
      (cond
        ((< b 128) (gatewayUtf8ValidBytes bs (+ pos 1) len))
        ((and (>= b 194) (<= b 223))
         (and (< (+ pos 1) len)
           (and (gatewayUtf8Continuation (bytesGet bs (+ pos 1)))
             (gatewayUtf8ValidBytes bs (+ pos 2) len))))
        ((and (>= b 224) (<= b 239))
         (and (< (+ pos 2) len)
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (b2 (bytesGet bs (+ pos 2)))
                 (firstOk (if (= b 224) (and (>= b1 160) (<= b1 191))
                           (if (= b 237) (and (>= b1 128) (<= b1 159))
                             (gatewayUtf8Continuation b1))))]
             (and firstOk
               (and (gatewayUtf8Continuation b2)
                 (gatewayUtf8ValidBytes bs (+ pos 3) len))))))
        ((and (>= b 240) (<= b 244))
         (and (< (+ pos 3) len)
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (b2 (bytesGet bs (+ pos 2)))
                 (b3 (bytesGet bs (+ pos 3)))
                 (firstOk (if (= b 240) (and (>= b1 144) (<= b1 191))
                           (if (= b 244) (and (>= b1 128) (<= b1 143))
                             (gatewayUtf8Continuation b1))))]
             (and firstOk
               (and (gatewayUtf8Continuation b2)
                 (and (gatewayUtf8Continuation b3)
                   (gatewayUtf8ValidBytes bs (+ pos 4) len)))))))
        (else false))))

fn gatewayUtf8InvalidStart bs: Bytes pos: Int64 len: Int64 -> (Option Int64)
  (if (>= pos len) none
    (let [(b (bytesGet bs pos))]
      (if (< b 128)
        (gatewayUtf8InvalidStart bs (+ pos 1) len)
        (if (or (< b 194) (> b 244))
          (some pos)
          (let [(width (if (<= b 223) 2 (if (<= b 239) 3 4)))]
            (gatewayUtf8InvalidStart bs (+ pos width) len))))))

fn gatewayUtf8InvalidContinuation bs: Bytes pos: Int64 len: Int64 -> (Option Int64)
  (if (>= pos len) none
    (let [(b (bytesGet bs pos))]
      (cond
        ((< b 128) (gatewayUtf8InvalidContinuation bs (+ pos 1) len))
        ((and (>= b 194) (<= b 223))
         (if (>= (+ pos 1) len) none
           (let [(b1 (bytesGet bs (+ pos 1)))]
             (if (gatewayUtf8Continuation b1)
               (gatewayUtf8InvalidContinuation bs (+ pos 2) len)
               (some (+ pos 1))))))
        ((and (>= b 224) (<= b 239))
         (if (>= (+ pos 2) len) none
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (b2 (bytesGet bs (+ pos 2)))
                 (firstOk (if (= b 224) (and (>= b1 160) (<= b1 191))
                           (if (= b 237) (and (>= b1 128) (<= b1 159))
                             (gatewayUtf8Continuation b1))))]
             (if (not firstOk) (some (+ pos 1))
               (if (not (gatewayUtf8Continuation b2)) (some (+ pos 2))
                 (gatewayUtf8InvalidContinuation bs (+ pos 3) len))))))
        ((and (>= b 240) (<= b 244))
         (if (>= (+ pos 3) len) none
           (let [(b1 (bytesGet bs (+ pos 1)))
                 (b2 (bytesGet bs (+ pos 2)))
                 (b3 (bytesGet bs (+ pos 3)))
                 (firstOk (if (= b 240) (and (>= b1 144) (<= b1 191))
                           (if (= b 244) (and (>= b1 128) (<= b1 143))
                             (gatewayUtf8Continuation b1))))]
             (if (not firstOk) (some (+ pos 1))
               (if (not (gatewayUtf8Continuation b2)) (some (+ pos 2))
                 (if (not (gatewayUtf8Continuation b3)) (some (+ pos 3))
                   (gatewayUtf8InvalidContinuation bs (+ pos 4) len)))))))
        (else (gatewayUtf8InvalidContinuation bs (+ pos 1) len)))))

fn gatewayUtf8TruncatedStart bs: Bytes pos: Int64 len: Int64 -> (Option Int64)
  (if (>= pos len) none
    (let [(b (bytesGet bs pos))]
      (if (< b 128)
        (gatewayUtf8TruncatedStart bs (+ pos 1) len)
        (if (and (>= b 194) (<= b 244))
          (let [(width (if (<= b 223) 2 (if (<= b 239) 3 4)))]
            (if (> (+ pos width) len)
              (some pos)
              (gatewayUtf8TruncatedStart bs (+ pos width) len)))
          (gatewayUtf8TruncatedStart bs (+ pos 1) len)))))

fn gatewayUtf8StartError bs: Bytes pos: Int64 -> String
  (let [(b (bytesGet bs pos))]
    (str "'utf-8' codec can't decode byte 0x"
         (gatewayHexDigit (/ b 16)) (gatewayHexDigit (mod b 16))
         " in position " (stringFromInt64 pos) ": invalid start byte"))

fn gatewayUtf8ContinuationError bs: Bytes pos: Int64 -> String
  (let [(b (bytesGet bs pos))]
    (str "'utf-8' codec can't decode byte 0x"
         (gatewayHexDigit (/ b 16)) (gatewayHexDigit (mod b 16))
         " in position " (stringFromInt64 pos) ": invalid continuation byte"))

fn gatewayUtf8UnexpectedEndError bs: Bytes pos: Int64 -> String
  (let [(b (bytesGet bs pos))]
    (str "'utf-8' codec can't decode byte 0x"
         (gatewayHexDigit (/ b 16)) (gatewayHexDigit (mod b 16))
         " in position " (stringFromInt64 pos) ": unexpected end of data"))

fn ! gatewayConfigCheckCli! path: String -> (Result Int64 String)
  (let [(root (optionOr (envGet "ASL_GATEWAY_ROOT") (optionOr (envGet "ROOT_DIR") ".")))
        (registryEnv (optionOr (envGet "ASL_CALIBRATION_INDEX") ""))
        (registry (if (stringEmpty? registryEnv) (str root "/.asl/mem/calibration/index.asn") registryEnv))
        (home (optionOr (envGet "HOME") root))
        (source (if (stringEmpty? path) (cfg/gatewayProfilesPath home) path))
        (loaded (fileReadString source))]
    (mt loaded
      ((err e)
        (if (not (fileExists? source))
          (let [(msg (str source " not found: the built-in default profiles apply"))]
            (do (sys/say! (cfg/gatewayConfigReceipt source registry "ok" 1 (list) (list msg) "")) (ok 0)))
          (do (sys/say! (cfg/gatewayConfigReceipt source registry "error" 0 (list e) (list) "")) (ok 1))))
      ((ok text)
        (let [(bytes (stringToBytes text))
              (invalidStart (gatewayUtf8InvalidStart bytes 0 (bytesLength bytes)))]
          (mt invalidStart
            ((some pos)
             (do (sys/say! (cfg/gatewayConfigReceipt source registry "error" 0 (list (gatewayUtf8StartError bytes pos)) (list) "")) (ok 1)))
            ((none)
             (mt (gatewayUtf8InvalidContinuation bytes 0 (bytesLength bytes))
               ((some pos)
                (do (sys/say! (cfg/gatewayConfigReceipt source registry "error" 0 (list (gatewayUtf8ContinuationError bytes pos)) (list) "")) (ok 1)))
               ((none)
                (mt (gatewayUtf8TruncatedStart bytes 0 (bytesLength bytes))
                  ((some pos)
                   (do (sys/say! (cfg/gatewayConfigReceipt source registry "error" 0 (list (gatewayUtf8UnexpectedEndError bytes pos)) (list) "")) (ok 1)))
                  ((none)
                   (if (not (gatewayUtf8ValidBytes bytes 0 (bytesLength bytes)))
                     (do (sys/say! (cfg/gatewayConfigReceipt source registry "error" 0 (list "invalid UTF-8 sequence") (list) "")) (ok 1))
                     (let [(result (cfg/gatewayConfigCheckText! text source registry))]
                       (do (sys/say! (pairFirst result)) (ok (pairSecond result)))))))))))))))

fn ! gatewayCliMain args: (List String) -> (Result Int64 String)
  (let [(mode (gatewayCliArg args 0))
        (second (gatewayCliArg args 1))
        (path (if (= mode "config") (gatewayCliArg args 2) second))]
    (if (= mode "convert")
      (gatewayCliConvert! path)
      (if (or (= mode "configCheck") (and (= mode "config") (= second "check")))
        (gatewayConfigCheckCli! path)
        (do (sys/sayErr! "unknown gateway ASL CLI mode") (ok 2)))))

fn ! main args: (List String) -> (Result Int64 String)
  (gatewayCliMain args)

fn defaultDispatchOptions -> DispatchOptions
  (DispatchOptions
    :model none
    :effort none
    :timeout 300
    :workspace none
    :systemPrompt none
    :noTools false
    :agent none
    :addDirs (list)
    :cliBin none)

fn proxySystemPrompt -> String
  "The reply goes back to the program that sent the request."

fn agyFixedPrompt -> String
  "Answer the last turn of the conversation in your system prompt."

fn claudeLeanTools -> String
  "Bash,Read,Edit,Write,Grep,Glob"

fn cliAgyAgent -> String
  "aslGateway"

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn searchPathForBin! name: String dirs: (List String) -> (Option String)
  (if (listEmpty? dirs) none
    (let [(d (preludeHead dirs))]
      (if (stringEmpty? d)
        (searchPathForBin! name (preludeTail dirs))
        (let [(cand (str d "/" name))]
          (if (fileExists? cand)
            (some cand)
            (searchPathForBin! name (preludeTail dirs)))))))

fn resolveCliBinFromLocations! name: String legacy: String home: String path: String -> String
  (let [(homeCand (if (stringEmpty? home) "" (str home "/.local/bin/" name)))]
    (if (and (not (stringEmpty? homeCand)) (fileExists? homeCand))
      homeCand
      (let [(dirs (stringSplit path ":"))
            (whichCand (searchPathForBin! name dirs))]
        (mt whichCand
          ((some w) w)
          ((none)
           (if (and (not (stringEmpty? legacy)) (fileExists? legacy))
             legacy
             legacy))))))

fn resolveCliBinAfterEnv! name: String legacy: String -> String
  (let [(home (optionOr (envGet "HOME") ""))
        (path (optionOr (envGet "PATH") ""))]
    (resolveCliBinFromLocations! name legacy home path))

fn resolveCliBin! envName: String name: String legacy: String -> String
  (let [(envCand (if (stringEmpty? envName) none (envGet envName)))]
    (mt envCand
      ((some c)
       (if (and (not (stringEmpty? c)) (fileExists? c))
         c
         (resolveCliBinAfterEnv! name legacy)))
      ((none)
       (resolveCliBinAfterEnv! name legacy))))

fn resolve_cli_bin! envName: String name: String legacy: String -> String
  (resolveCliBin! envName name legacy)

fn probeCliVersion! name: String binPath: String -> CliVersionInfo
  (if (not (fileExists? binPath))
    (CliVersionInfo :name name :bin binPath :version (str "error: FileNotFoundError: [Errno 2] No such file or directory: '" binPath "'"))
    (let [(out (processRun (str (shellQuote binPath) " --version")))
          (rawOut (if (> (stringLength out.stdout) 0) out.stdout out.stderr))
          (trimmed (stringTrim rawOut))]
      (if (stringEmpty? trimmed)
        (CliVersionInfo :name name :bin binPath :version (str "exit " (stringFromInt64 out.exitCode)))
        (let [(lines (stringSplit trimmed "\n"))]
          (CliVersionInfo :name name :bin binPath :version (preludeHead lines))))))

fn cliVersions! -> (List CliVersionInfo)
  (map (fn [(row CliProvider)] -> CliVersionInfo (probeCliVersion! row.id (cliProviderBin! row))) (cliProviders))

fn cli_versions! -> (List CliVersionInfo)
  (cliVersions!)

fn extractTextFromParts parts: (List j/Json) -> (List String)
  (if (listEmpty? parts) (list)
    (let [(item (preludeHead parts))
          (rest (extractTextFromParts (preludeTail parts)))]
      (mt item
        ((j/jobj kvs)
         (mt (j/jsonGet (j/jobj kvs) "text")
           ((some val)
            (mt val
              ((j/jstr s) (if (stringEmpty? s) rest (cons s rest)))
              (_ rest)))
           ((none) rest)))
        (_ rest))))

fn cliMessageText content: j/Json -> String
  (mt content
    ((j/jnull) "")
    ((j/jstr s) s)
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum n) (stringFromFloat64 n))
    ((j/jbool b) (if b "True" "False"))
    ((j/jarr xs)
     (let [(parts (extractTextFromParts xs))]
       (stringJoin parts "\n")))
    ((j/jobj _) ""))

fn cli_message_text content: j/Json -> String
  (cliMessageText content)

fn parseAgyToolsFromText text: String -> (Result (List String) String)
  (let [(idIdx (stringIndexOf text ":id agy"))]
    (mt idIdx
      ((none) (err "no (:client :id agy ...) in grammar"))
      ((some i)
       (let [(restAfterId (optionOr (stringSlice text i (stringLength text)) ""))
             (toolsKeyIdx (stringIndexOf restAfterId ":tools \""))]
         (mt toolsKeyIdx
           ((none) (err "no (:client :id agy :tools ...) in grammar"))
           ((some k)
            (let [(startQuote (+ k (stringLength ":tools \"")))
                  (afterQuote (optionOr (stringSlice restAfterId startQuote (stringLength restAfterId)) ""))
                  (endQuoteIdx (stringIndexOf afterQuote "\""))]
              (mt endQuoteIdx
                ((none) (err "unclosed :tools quote"))
                ((some eq)
                 (let [(toolsRaw (optionOr (stringSlice afterQuote 0 eq) ""))
                       (rawList (stringSplit toolsRaw ","))
                       (trimmedList (filter (fn [s] (not (stringEmpty? s)))
                                            (map stringTrim rawList)))]
                   (if (listEmpty? trimmedList)
                     (err "no tools found for agy")
                     (ok trimmedList))))))))))))

fn cliAgyTools! -> (Result (List String) String)
  (cliAgyToolsIn! (optionOr (envGet "ROOT_DIR") "."))

fn cliAgyToolsIn! rootDir: String -> (Result (List String) String)
  (let [(path (str rootDir "/asl/grammar/clients.asn"))
        (readRes (fileReadString path))]
    (mt readRes
      ((ok content) (parseAgyToolsFromText content))
      ((err e) (err (str "could not read " path ": " e)))))

fn cli_agy_tools! -> (Result (List String) String)
  (cliAgyTools!)

fn agyToolsYaml tools: (List String) noTools: Bool -> String
  (if noTools
    "tools: []\ninheritMcp: false\ninheritCustomizations: false\nexcludeDefaultComponents: true\n"
    (str "tools:\n"
         (fold (fn [acc t] (str acc "  - " t "\n")) "" tools)
         "inheritMcp: false\ninheritCustomizations: false\n"))

fn agyAgentMarkdown systemPrompt: String tools: (List String) noTools: Bool -> String
  (str "---\nname: aslGateway\ndescription: asl gateway\nmainAgent: true\nsubagent: false\n"
       (agyToolsYaml tools noTools)
       "---\n\n"
       systemPrompt)

fn cliWritePromptDirAt! client: String systemPrompt: String noTools: Bool tmpDir: String -> (Result CliPromptDir String)
  (cliWritePromptDirFrom! (optionOr (envGet "ROOT_DIR") ".") client systemPrompt noTools tmpDir)

fn cliWritePromptDirFrom! rootDir: String client: String systemPrompt: String noTools: Bool tmpDir: String -> (Result CliPromptDir String)
  (if (mt (cliProviderNamed client) ((some row) row.agentLayout) ((none) false))
    (let [(toolsRes (if noTools (ok (list)) (cliAgyToolsIn! rootDir)))]
      (mt toolsRes
        ((err e)
         (do (pathRemove tmpDir) (err e)))
        ((ok tools)
         (let [(agentsDir (str tmpDir "/.agents/plugins/aslGateway/agents"))
               (pluginDir (str tmpDir "/.agents/plugins/aslGateway"))
               (dRes (dirCreate agentsDir))]
           (mt dRes
             ((err e) (do (pathRemove tmpDir) (err (str "failed to create agents dir: " e))))
             ((ok _)
              (let [(wRes1 (fileWrite (str pluginDir "/plugin.json") "{\"name\": \"aslGateway\"}\n"))]
                (mt wRes1
                  ((err e) (do (pathRemove tmpDir) (err (str "failed to write plugin.json: " e))))
                  ((ok _)
                   (let [(promptPath (str agentsDir "/aslGateway.md"))
                         (mdContent (agyAgentMarkdown systemPrompt tools noTools))
                         (wRes2 (fileWrite promptPath mdContent))]
                     (mt wRes2
                       ((err e) (do (pathRemove tmpDir) (err (str "failed to write aslGateway.md: " e))))
                       ((ok _) (ok (CliPromptDir :tmpDir tmpDir :promptPath promptPath))))))))))))))
    (let [(promptPath (str tmpDir "/system.md"))
          (wRes (fileWrite promptPath systemPrompt))]
      (mt wRes
        ((err e) (do (pathRemove tmpDir) (err (str "failed to write system.md: " e))))
        ((ok _) (ok (CliPromptDir :tmpDir tmpDir :promptPath promptPath))))))

fn cliWritePromptDir! client: String systemPrompt: String noTools: Bool -> (Result CliPromptDir String)
  (let [(tmpDir (str "/tmp/asl-gw-" client "-" (stringFromInt64 (nowNs))))
        (mkRes (dirCreate tmpDir))]
    (mt mkRes
      ((err e) (err (str "failed to create temp dir " tmpDir ": " e)))
      ((ok _) (cliWritePromptDirAt! client systemPrompt noTools tmpDir))))

fn cli_write_prompt_dir! client: String systemPrompt: String noTools: Bool -> (Result CliPromptDir String)
  (cliWritePromptDir! client systemPrompt noTools)

fn findFirstBrace text: String idx: Int64 len: Int64 -> (Option Int64)
  (if (>= idx len) none
    (let [(c (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if (= c "{")
        (some idx)
        (findFirstBrace text (+ idx 1) len))))

fn findBalancedBrace text: String idx: Int64 len: Int64 depth: Int64 inStr: Bool esc: Bool -> (Option Int64)
  (if (>= idx len) none
    (let [(c (optionOr (stringSlice text idx (+ idx 1)) ""))]
      (if inStr
        (if esc
          (findBalancedBrace text (+ idx 1) len depth true false)
          (if (= c "\\")
            (findBalancedBrace text (+ idx 1) len depth true true)
            (if (= c "\"")
              (findBalancedBrace text (+ idx 1) len depth false false)
              (findBalancedBrace text (+ idx 1) len depth true false))))
        (if (= c "\"")
          (findBalancedBrace text (+ idx 1) len depth true false)
          (if (= c "{")
            (findBalancedBrace text (+ idx 1) len (+ depth 1) false false)
            (if (= c "}")
              (let [(newDepth (- depth 1))]
                (if (= newDepth 0)
                  (some (+ idx 1))
                  (findBalancedBrace text (+ idx 1) len newDepth false false)))
              (findBalancedBrace text (+ idx 1) len depth false false)))))))

fn cliJsonParserOffset parserError: String -> Int64
  (mt (stringIndexOf parserError "error at byte " )
    ((none) 0)
    ((some prefixPos)
     (let [(rest (optionOr (stringSlice parserError (+ prefixPos (stringLength "error at byte ")) (stringLength parserError)) ""))
           (colon (stringIndexOf rest ":"))]
       (mt colon
         ((none) 0)
         ((some endPos)
          (optionOr (stringToInt64 (optionOr (stringSlice rest 0 endPos) "")) 0))))))

fn cliJsonMalformedObjectError text: String startPos: Int64 parserError: String -> String
  (let [(offset (+ startPos (cliJsonParserOffset parserError)))
        (beforeError (optionOr (stringSlice text 0 offset) ""))
        (lines (stringSplit beforeError "\n"))
        (lastLine (optionOr (listHead (listReverse lines)) ""))
        (line (listLength lines))
        (column (+ (stringLength lastLine) 1))
        (category (if (or (stringContains? parserError "unclosed object")
                          (stringContains? parserError "expected ',' or '}' in object"))
                    "Expecting ',' delimiter"
                    parserError))]
    (str category ": line " (stringFromInt64 line) " column " (stringFromInt64 column) " (char " (stringFromInt64 offset) ")"))

fn cliJsonObject text: String -> (Result j/Json String)
  (let [(tLen (stringLength text))]
    (mt (findFirstBrace text 0 tLen)
      ((none) (err "no JSON object in output"))
      ((some startPos)
       (mt (findBalancedBrace text startPos tLen 0 false false)
         ((none)
          (let [(sliced (optionOr (stringSlice text startPos tLen) ""))]
            (mt (j/jsonParse sliced)
              ((err e) (err (cliJsonMalformedObjectError text startPos e)))
              ((ok _) (err "no JSON object in output")))))
         ((some endPos)
          (let [(sliced (optionOr (stringSlice text startPos endPos) ""))]
            (mt (j/jsonParse sliced)
              ((err e) (err (cliJsonMalformedObjectError text startPos e)))
              ((ok val)
               (mt val
                 ((j/jobj kvs) (ok val))
                 (_ (err "JSON output is not an object")))))))))))

fn cli_json_object text: String -> (Result j/Json String)
  (cliJsonObject text)

fn jsonIntField obj: j/Json key: String -> Int64
  (mt (j/jsonGet obj key)
    ((some val)
     (mt val
       ((j/jint n) n)
       (_ 0)))
    ((none) 0))

fn sumModelUsageKvs kvs: (List (Pair String j/Json)) inAcc: Int64 cacheAcc: Int64 outAcc: Int64 -> CliUsage
  (if (listEmpty? kvs)
    (CliUsage :inputTokens inAcc :cachedTokens cacheAcc :outputTokens outAcc)
    (let [(p (preludeHead kvs))
          (v (pairSecond p))
          (inTok (jsonIntField v "inputTokens"))
          (createTok (jsonIntField v "cacheCreationInputTokens"))
          (readTok (jsonIntField v "cacheReadInputTokens"))
          (outTok (jsonIntField v "outputTokens"))]
      (sumModelUsageKvs (preludeTail kvs)
                        (+ inAcc (+ (+ inTok createTok) readTok))
                        (+ cacheAcc readTok)
                        (+ outAcc outTok))))

fn sumModelUsage muObj: j/Json -> CliUsage
  (mt muObj
    ((j/jobj kvs)
     (sumModelUsageKvs kvs 0 0 0))
    (_ (CliUsage :inputTokens 0 :cachedTokens 0 :outputTokens 0)))

fn parseStandardUsage d: j/Json -> (Option CliUsage)
  (mt (j/jsonGet d "usage")
    ((some val)
     (mt val
       ((j/jobj uKvs)
        (let [(u (j/jobj uKvs))
              (cached (jsonIntField u "cache_read_input_tokens"))
              (inTok (jsonIntField u "input_tokens"))
              (createTok (jsonIntField u "cache_creation_input_tokens"))
              (outTok (jsonIntField u "output_tokens"))]
          (some (CliUsage :inputTokens (+ (+ inTok createTok) cached) :cachedTokens cached :outputTokens outTok))))
       (_ none)))
    ((none) none))

fn parseClaudeResult stdout: String -> CliParseResult
  (let [(raw (stringTrim stdout))]
    (mt (cliJsonObject stdout)
      ((err _) (CliParseResult :text raw :usage none :dedup false))
      ((ok d)
       (let [(resText (mt (j/jsonGet d "result")
                        ((some val)
                         (mt val
                           ((j/jstr s) (stringTrim s))
                           (_ (stringTrim (j/jsonEmit val)))))
                        ((none) "")))
             (muOpt (j/jsonGet d "modelUsage"))
             (usage (mt muOpt
                      ((some val)
                       (mt val
                         ((j/jobj kvs)
                          (if (listEmpty? kvs)
                            (parseStandardUsage d)
                            (some (sumModelUsage (j/jobj kvs)))))
                         (_ (parseStandardUsage d))))
                      ((none) (parseStandardUsage d))))]
         (CliParseResult :text resText :usage usage :dedup false)))))

(schema CodexScanAcc
  (:f text (Option String))
  (:f inTok Int64)
  (:f cacheTok Int64)
  (:f outTok Int64)
  (:f hasUsage Bool))

fn scanCodexLines lines: (List String) acc: CodexScanAcc -> CodexScanAcc
  (if (listEmpty? lines) acc
    (let [(line (stringTrim (preludeHead lines)))
          (nextAcc (if (stringEmpty? line) acc
                     (mt (j/jsonParse line)
                       ((err _) acc)
                       ((ok val)
                        (mt val
                          ((j/jobj kvs)
                           (let [(ev (j/jobj kvs))
                                 (t (mt (j/jsonGet (j/jobj kvs) "type")
                                      ((some tv) (mt tv ((j/jstr s) s) (_ "")))
                                      ((none) "")))]
                             (cond
                               ((and (= t "turn.completed") (some? (j/jsonGet ev "usage")))
                                (mt (j/jsonGet ev "usage")
                                  ((some uv)
                                   (mt uv
                                     ((j/jobj uKvs)
                                      (let [(u (j/jobj uKvs))
                                            (inT (jsonIntField u "input_tokens"))
                                            (cacheT (jsonIntField u "cached_input_tokens"))
                                            (outT (jsonIntField u "output_tokens"))]
                                        (with acc :inTok (+ acc.inTok inT) :cacheTok (+ acc.cacheTok cacheT) :outTok (+ acc.outTok outT) :hasUsage true)))
                                     (_ acc)))
                                  ((none) acc)))
                               ((= t "item.completed")
                                (mt (j/jsonGet ev "item")
                                  ((some iv)
                                   (mt iv
                                     ((j/jobj itemKvs)
                                      (let [(item (j/jobj itemKvs))
                                            (itype (mt (j/jsonGet (j/jobj itemKvs) "type")
                                                     ((some itv) (mt itv ((j/jstr s) s) (_ "")))
                                                     ((none) "")))]
                                        (if (= itype "agent_message")
                                          (let [(txt (mt (j/jsonGet (j/jobj itemKvs) "text")
                                                       ((some txtv) (mt txtv ((j/jstr s) s) (_ "")))
                                                       ((none) "")))]
                                            (with acc :text (some txt)))
                                          acc)))
                                     (_ acc)))
                                  ((none) acc)))
                               (else acc))))
                          (_ acc))))))]
      (scanCodexLines (preludeTail lines) nextAcc)))

fn parseCodexResult stdout: String -> CliParseResult
  (let [(raw (stringTrim stdout))
        (lines (stringSplit stdout "\n"))
        (scan (scanCodexLines lines (CodexScanAcc :text none :inTok 0 :cacheTok 0 :outTok 0 :hasUsage false)))]
    (if (and (none? scan.text) (not scan.hasUsage))
      (CliParseResult :text raw :usage none :dedup false)
      (let [(finalText (stringTrim (optionOr scan.text "")))
            (usage (if scan.hasUsage
                     (some (CliUsage :inputTokens scan.inTok :cachedTokens scan.cacheTok :outputTokens scan.outTok))
                     none))]
        (CliParseResult :text finalText :usage usage :dedup false))))

fn checkAgyDedup text: String -> (Pair String Bool)
  (let [(tLen (stringLength text))]
    (if (= (mod tLen 2) 1)
      (let [(halfLen (/ tLen 2))
            (half (optionOr (stringSlice text 0 halfLen) ""))
            (rest (optionOr (stringSlice text halfLen tLen) ""))]
        (if (and (not (stringEmpty? half)) (= rest (str "\n" half)))
          (pair (stringTrim half) true)
          (pair text false)))
      (pair text false)))

fn parseAgyResult stdout: String -> CliParseResult
  (let [(raw (stringTrim stdout))]
    (mt (cliJsonObject stdout)
      ((err _) (CliParseResult :text raw :usage none :dedup false))
      ((ok d)
       (let [(usage (mt (j/jsonGet d "usage")
                      ((some val)
                       (mt val
                         ((j/jobj uKvs)
                          (let [(u (j/jobj uKvs))
                                (inTok (jsonIntField u "input_tokens"))
                                (cacheTok (jsonIntField u "cache_read_tokens"))
                                (outTok (jsonIntField u "output_tokens"))
                                (thinkTok (jsonIntField u "thinking_tokens"))]
                            (some (CliUsage :inputTokens inTok :cachedTokens cacheTok :outputTokens (+ outTok thinkTok)))))
                         (_ none)))
                      ((none) none)))
             (resp (mt (j/jsonGet d "response")
                     ((some val)
                      (mt val
                        ((j/jstr s) (stringTrim s))
                        (_ (stringTrim (j/jsonEmit val)))))
                     ((none) "")))
             (dedupPair (checkAgyDedup resp))]
         (CliParseResult :text (pairFirst dedupPair) :usage usage :dedup (pairSecond dedupPair))))))

fn cliParseResult client: String stdout: String -> CliParseResult
  (mt (cliProviderNamed client)
    ((some row) (row.parse stdout))
    ((none) (parseAgyResult stdout)))

fn cli_parse_result client: String stdout: String -> CliParseResult
  (cliParseResult client stdout)

fn codexBuildCmd codexBin: String ws: String promptPath: String noTools: Bool effort: (Option String) model: (Option String) -> (List String)
  (let [(base (list codexBin "exec" "-C" ws "-" "--json" "--ephemeral" "--skip-git-repo-check" "-c" (str "model_instructions_file=" promptPath)))
        (withTools (if noTools (listAppend base (list "-c" "project_doc_max_bytes=0")) base))
        (withEffort (mt effort
                      ((some eff)
                       (if (or (= eff "low") (or (= eff "medium") (= eff "high")))
                         (listAppend withTools (list "-c" (str "model_reasoning_effort=\"" eff "\"")))
                         withTools))
                      ((none) withTools)))
        (withModel (mt model
                     ((some m)
                      (let [(cleanM (cond
                                      ((or (= m "luna") (or (= m "gpt-luna") (or (= m "codex/luna") (= m "gpt-5.6-luna")))) "gpt-5.6-luna")
                                      ((or (= m "astra") (or (= m "codex/astra") (= m "gpt-6-astra"))) "gpt-6-astra")
                                      (else m)))]
                        (listAppend withEffort (list "-m" cleanM))))
                     ((none) withEffort)))]
    withModel)

fn mapAgyModelAndEffort model: (Option String) effort: (Option String) -> (Pair String String)
  (let [(rawModel (optionOr model "gemini-3.8-flash"))
        (rawEff (optionOr effort "low"))
        (pair1 (if (stringContains? rawModel "-high")
                 (pair (stringReplace rawModel "-high" "") "high")
                 (if (stringContains? rawModel "-medium")
                   (pair (stringReplace rawModel "-medium" "") "medium")
                   (if (stringContains? rawModel "-low")
                     (pair (stringReplace rawModel "-low" "") "low")
                     (pair rawModel rawEff)))))
        (cleanM (pairFirst pair1))
        (eff (pairSecond pair1))
        (mappedM (cond
                   ((or (= cleanM "opus") (or (= cleanM "claude-opus") (or (= cleanM "agy/opus") (= cleanM "agy-opus")))) "claude-opus-4-6-thinking")
                   ((or (= cleanM "sonnet") (or (= cleanM "claude-sonnet") (or (= cleanM "agy/sonnet") (= cleanM "agy-sonnet")))) "claude-sonnet-4-6")
                   (else cleanM)))]
    (pair mappedM eff))

fn agyBuildCmd! agyBin: String ws: String tmpDir: String rootDir: String timeout: Int64 model: (Option String) effort: (Option String) agent: (Option String) addDirs: (List String) prompt: String noTools: Bool -> (List String)
  (let [(unsafeFlag (optionOr (envGet "ASL_AGENT_UNSAFE") "0"))
        (base (if (= unsafeFlag "1")
                (list agyBin "--output-format" "json" "--dangerously-skip-permissions")
                (list agyBin "--output-format" "json")))
        (modelPair (mapAgyModelAndEffort model effort))
        (cleanModel (pairFirst modelPair))
        (eff (pairSecond modelPair))
        (withModel (if (stringStartsWith? cleanModel "claude-")
                     (listAppend base (list "--model" cleanModel))
                     (if (or (= cleanModel "gemini-3.8-flash") (or (= cleanModel "gemini-flash") (or (= cleanModel "flash") (= cleanModel "agy"))))
                       (listAppend base (list "--model" "gemini-3.8-flash" "--effort" eff))
                       (if (not (stringEmpty? cleanModel))
                         (listAppend base (list "--model" cleanModel "--effort" eff))
                         (listAppend base (list "--model" "gemini-3.8-flash" "--effort" eff))))))]
    (mt agent
      ((some ag)
       (let [(pluginRoot (str rootDir "/.asl/agy"))
             (cmdWithAgent (listAppend withModel (list "--agent" ag "--add-dir" pluginRoot "--add-dir" ws)))
             (cmdWithAddDirs (fold (fn [acc d]
                                     (let [(targetD (if (stringStartsWith? d "/") d (str ws "/" d)))]
                                       (if (= targetD ws) acc (listAppend acc (list "--add-dir" targetD)))))
                                   cmdWithAgent
                                   addDirs))]
         (listAppend cmdWithAddDirs (list "--print-timeout" (str (stringFromInt64 timeout) "s") "-p" prompt))))
      ((none)
       (listAppend withModel (list "--agent" "aslGateway" "--add-dir" tmpDir "--add-dir" ws "-p" "Answer the last turn of the conversation in your system prompt.")))))

fn claudeBuildCmd! claudeBin: String promptPath: String noTools: Bool model: (Option String) effort: (Option String) -> (List String)
  (let [(base (list claudeBin "-p" "--output-format" "json" "--no-session-persistence" "--system-prompt-file" promptPath))
        (withTools (if noTools
                     (listAppend base (list "--tools" "" "--strict-mcp-config" "--disable-slash-commands" "--setting-sources" ""))
                     (listAppend base (list "--tools" "Bash,Read,Edit,Write,Grep,Glob" "--strict-mcp-config" "--disable-slash-commands"))))
        (unsafeFlag (optionOr (envGet "ASL_AGENT_UNSAFE") "0"))
        (withUnsafe (if (= unsafeFlag "1") (listAppend withTools (list "--dangerously-skip-permissions")) withTools))
        (withPlan (if (not noTools) (listAppend withUnsafe (list "--permission-mode" "plan")) withUnsafe))
        (withModel (mt model ((some m) (listAppend withPlan (list "--model" m))) ((none) withPlan)))
        (withEffort (mt effort
                      ((some eff)
                       (if (or (= eff "low") (or (= eff "medium") (or (= eff "high") (or (= eff "xhigh") (= eff "max")))))
                         (listAppend withModel (list "--effort" eff))
                         withModel))
                      ((none) withModel)))]
    withEffort)

(schema ExecIo
  (:f pending String)
  (:f inOpen Bool)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f out String)
  (:f errText String))

fn pollSet sp: SpawnedProc io: ExecIo -> (List (Pair Int64 Int64))
  (let [(w (if io.inOpen (list (pair sp.stdin 2)) (list)))
        (o (if io.outOpen (list (pair sp.stdout 1)) (list)))
        (e (if io.errOpen (list (pair sp.stderr 1)) (list)))]
    (listAppend w (listAppend o e)))

fn readyOn ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (not (listEmpty? (filter (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)))

fn ! stepStdin sp: SpawnedProc io: ExecIo -> ExecIo
  (if (stringEmpty? io.pending)
    (do (fdClose sp.stdin) (with io :pending "" :inOpen false))
    (mt (fdWrite sp.stdin io.pending)
      ((ok n) (with io :pending (optionOr (stringSlice io.pending n (stringLength io.pending)) "") :inOpen true))
      ((err e) (if (= e "wouldBlock") io (do (fdClose sp.stdin) (with io :pending "" :inOpen false))))))

fn ! stepOut sp: SpawnedProc io: ExecIo -> ExecIo
  (mt (fdRead sp.stdout 65536)
    ((ok chunk) (if (stringEmpty? chunk)
      (do (fdClose sp.stdout) (with io :outOpen false))
      (with io :outOpen true :out (str io.out chunk))))
    ((err e) (if (= e "wouldBlock") io (do (fdClose sp.stdout) (with io :outOpen false)))))

fn ! stepErr sp: SpawnedProc io: ExecIo -> ExecIo
  (mt (fdRead sp.stderr 65536)
    ((ok chunk) (if (stringEmpty? chunk)
      (do (fdClose sp.stderr) (with io :errOpen false))
      (with io :errOpen true :errText (str io.errText chunk))))
    ((err e) (if (= e "wouldBlock") io (do (fdClose sp.stderr) (with io :errOpen false)))))

fn ! closeOpen sp: SpawnedProc io: ExecIo -> Bool
  (do (if io.inOpen (fdClose sp.stdin) (ok ())) (if io.outOpen (fdClose sp.stdout) (ok ())) (if io.errOpen (fdClose sp.stderr) (ok ())) true)

fn ! pumpIo sp: SpawnedProc io: ExecIo deadlineNs: Int64 -> (Result ExecIo Int64)
  (if (not (or io.outOpen io.errOpen))
    (do (if io.inOpen (fdClose sp.stdin) (ok ())) (ok io))
    (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
      (if (<= leftMs 0)
        (do (closeOpen sp io) (err 0))
        (mt (fdPoll (pollSet sp io) leftMs)
          ((err _) (do (closeOpen sp io) (err 1)))
          ((ok ready)
            (let [(io1 (if (and io.inOpen (readyOn ready sp.stdin)) (stepStdin sp io) io))
                  (io2 (if (and io1.outOpen (readyOn ready sp.stdout)) (stepOut sp io1) io1))
                  (io3 (if (and io2.errOpen (readyOn ready sp.stderr)) (stepErr sp io2) io2))]
              (pumpIo sp io3 deadlineNs)))))))

fn stripQuotes s: String -> String
  (if (and (stringStartsWith? s "'") (stringEndsWith? s "'"))
    (let [(len (stringLength s))]
      (if (>= len 2) (optionOr (stringSlice s 1 (- len 1)) "") s))
    (if (and (stringStartsWith? s "\"") (stringEndsWith? s "\""))
      (let [(len (stringLength s))]
        (if (>= len 2) (optionOr (stringSlice s 1 (- len 1)) "") s))
      s))

fn cleanEnvEntry entry: String -> String
  (mt (stringIndexOf entry "=")
    ((none) entry)
    ((some eqIdx)
     (let [(k (optionOr (stringSlice entry 0 eqIdx) ""))
           (v (optionOr (stringSlice entry (+ eqIdx 1) (stringLength entry)) ""))]
       (str k "=" (stripQuotes v)))))

fn parseEnvLines s: String -> (List String)
  (let [(sep (if (stringContains? s "\n") "\n" " "))
        (parts (stringSplit s sep))]
    (map cleanEnvEntry (filter (fn [line] (stringContains? line "=")) (map stringTrim parts))))

fn buildEnvString! provider: String -> String
  (let [(baseVars (list "PATH" "HOME" "USER" "LOGNAME" "TMPDIR" "SHELL" "TERM" "LANG" "LC_ALL" "ROOT_DIR" "ASL_AGENT_UNSAFE"))
        (keyVars (mt (cliProviderNamed provider) ((some row) row.keyVars) ((none) (list))))
        (allVars (listAppend baseVars keyVars))
        (envAssignments (fold (fn [acc varName]
                                (mt (envGet varName)
                                  ((some v) (cons (str varName "=" v) acc))
                                  ((none) acc)))
                              (list)
                              allVars))]
    (stringJoin (listReverse envAssignments) "\n"))

fn runSpawnDispatch! cmdList: (List String) ws: String envStr: String stdinFile: (Option String) pidFile: String tmpDir: String timeoutSec: Int64 client: String -> (Result CliParseResult String)
  (let [(envLines (parseEnvLines envStr))
        (envOpt (if (listEmpty? envLines) none (some envLines)))
        (wsOpt (if (stringEmpty? ws) none (some ws)))
        (spawnRes (procSpawnv cmdList wsOpt envOpt))]
    (mt spawnRes
      ((err e)
       (let [(_rm (pathRemove tmpDir))]
         (err (str "procSpawnv failed: " e))))
      ((ok sp)
       (do
         (if (not (stringEmpty? pidFile))
           (fileWrite pidFile (stringFromInt64 sp.pid))
           (ok ()))
         (let [(stdinData (mt stdinFile
                            ((some sf) (resultOr (fileReadString sf) ""))
                            ((none) "")))
               (hasStdin (not (stringEmpty? stdinData)))
               (_nb1 (if hasStdin (fdNonBlocking sp.stdin true) (ok ())))
               (_nb2 (fdNonBlocking sp.stdout true))
               (_nb3 (fdNonBlocking sp.stderr true))
               (io0 (if hasStdin
                      (ExecIo :pending stdinData :inOpen true :outOpen true :errOpen true :out "" :errText "")
                      (do
                        (fdClose sp.stdin)
                        (ExecIo :pending "" :inOpen false :outOpen true :errOpen true :out "" :errText ""))))
               (timeoutEffective (if (<= timeoutSec 0) 300 timeoutSec))
               (deadlineNs (+ (monotonicNs) (* timeoutEffective 1000000000)))
               (pumpRes (pumpIo sp io0 deadlineNs))]
           (mt pumpRes
             ((err _)
              (do
                (procKill (- 0 sp.pid) "SIGTERM")
                (sleepMs 100)
                (procKill (- 0 sp.pid) "SIGKILL")
                (procKill sp.pid "SIGKILL")
                (procWaitPid sp.pid false)
                (pathRemove tmpDir)
                (err "timeout")))
             ((ok io)
              (mt (procWaitPid sp.pid false)
                ((err e)
                 (let [(_rm (pathRemove tmpDir))]
                   (err (str "procWaitPid failed: " e))))
                ((ok exitCodeOpt)
                 (let [(exitCode (optionOr exitCodeOpt -1))
                       (_rm (pathRemove tmpDir))]
                   (if (= exitCode 0)
                     (let [(parsed (cliParseResult client io.out))]
                       (if (not (stringEmpty? parsed.text))
                         (ok parsed)
                         (err (str client " error: empty response"))))
                     (err (str client " exit " (stringFromInt64 exitCode) ": " io.errText)))))))))))))

fn resolveWorkspace! workspace: (Option String) rootDir: String -> (Result String String)
  (mt workspace
    ((some ws)
     (if (stringEmpty? ws)
       (resolveWorkspace! none rootDir)
       (mt (realPath ws)
         ((ok p) (ok p))
         ((err _) (err "ERR_WORKSPACE")))))
    ((none)
     (let [(target (if (stringEmpty? rootDir) "." rootDir))]
       (mt (realPath target)
         ((ok p) (ok p))
         ((err _) (ok target))))))

fn dispatchCodexFallback! prompt: String opts: DispatchOptions -> (Result CliParseResult String)
  (let [(rootDir (optionOr (envGet "ROOT_DIR") "."))
        (wsRes (resolveWorkspace! opts.workspace rootDir))]
    (mt wsRes
      ((err e) (err e))
      ((ok ws)
       (let [(codexBin (mt opts.cliBin
                         ((some b) b)
                         ((none) (resolveCliBin! "CODEX_BIN" "codex" "/opt/homebrew/bin/codex"))))]
         (if (not (fileExists? codexBin))
           (err (str "CODEX_BIN not found: " codexBin))
           (let [(sysPrompt (optionOr opts.systemPrompt (proxySystemPrompt)))
                 (promptDirRes (cliWritePromptDir! "codex" sysPrompt opts.noTools))]
             (mt promptDirRes
               ((err e) (err e))
               ((ok promptDir)
                (let [(tmpDir promptDir.tmpDir)
                      (promptPath promptDir.promptPath)
                      (promptFile (str tmpDir "/prompt.txt"))
                      (wRes (fileWrite promptFile prompt))]
                  (mt wRes
                    ((err e) (do (pathRemove tmpDir) (err (str "failed to write prompt: " e))))
                    ((ok _)
                     (let [(pidFile (str tmpDir "/child.pid"))
                           (cmd (codexBuildCmd codexBin ws promptPath opts.noTools opts.effort opts.model))
                           (envStr (buildEnvString! "codex"))]
                       (runSpawnDispatch! cmd ws envStr (some promptFile) pidFile tmpDir opts.timeout "codex")))))))))))))

fn dispatch_codex_fallback! prompt: String model: (Option String) effort: (Option String) timeout: Int64 workspace: (Option String) systemPrompt: (Option String) noTools: Bool -> (Result CliParseResult String)
  (dispatchCodexFallback! prompt (DispatchOptions
                                  :model model
                                  :effort effort
                                  :timeout timeout
                                  :workspace workspace
                                  :systemPrompt systemPrompt
                                  :noTools noTools
                                  :agent none
                                  :addDirs (list)
                                  :cliBin none))

fn dispatchAgyFallback! prompt: String opts: DispatchOptions -> (Result CliParseResult String)
  (let [(rootDir (optionOr (envGet "ROOT_DIR") "."))
        (wsRes (resolveWorkspace! opts.workspace rootDir))]
    (mt wsRes
      ((err e) (err e))
      ((ok ws)
       (let [(agyBin (mt opts.cliBin
                       ((some b) b)
                       ((none) (resolveCliBin! "AGY_BIN" "agy" ""))))]
         (if (not (fileExists? agyBin))
           (err (str "AGY_BIN not found: " agyBin))
           (let [(hasAgent (some? opts.agent))]
             (if hasAgent
               (let [(tmpDir (str "/tmp/asl-gw-agy-" (stringFromInt64 (nowNs))))
                     (dRes (dirCreate tmpDir))]
                 (mt dRes
                   ((err e) (err (str "failed to create temp dir " tmpDir ": " e)))
                   ((ok _)
                    (let [(pidFile (str tmpDir "/child.pid"))
                          (cmd (agyBuildCmd! agyBin ws tmpDir rootDir opts.timeout opts.model opts.effort opts.agent opts.addDirs prompt opts.noTools))
                          (envStr (buildEnvString! "agy"))]
                      (runSpawnDispatch! cmd ws envStr none pidFile tmpDir opts.timeout "agy")))))
               (let [(sysText (optionOr opts.systemPrompt (proxySystemPrompt)))
                     (agentText (if (stringEmpty? prompt) sysText (str sysText "\n\n(:conversation)\n" prompt)))
                     (promptDirRes (cliWritePromptDir! "agy" agentText opts.noTools))]
                 (mt promptDirRes
                   ((err e) (err e))
                   ((ok promptDir)
                    (let [(tmpDir promptDir.tmpDir)
                          (pidFile (str tmpDir "/child.pid"))
                          (cmd (agyBuildCmd! agyBin ws tmpDir rootDir opts.timeout opts.model opts.effort opts.agent opts.addDirs prompt opts.noTools))
                          (envStr (buildEnvString! "agy"))]
                      (runSpawnDispatch! cmd ws envStr none pidFile tmpDir opts.timeout "agy"))))))))))))

fn dispatch_agy_fallback! prompt: String model: (Option String) effort: (Option String) timeout: Int64 agent: (Option String) addDirs: (List String) workspace: (Option String) systemPrompt: (Option String) noTools: Bool -> (Result CliParseResult String)
  (dispatchAgyFallback! prompt (DispatchOptions
                                :model model
                                :effort effort
                                :timeout timeout
                                :workspace workspace
                                :systemPrompt systemPrompt
                                :noTools noTools
                                :agent agent
                                :addDirs addDirs
                                :cliBin none))

fn dispatchClaudeFallback! prompt: String opts: DispatchOptions -> (Result CliParseResult String)
  (let [(rootDir (optionOr (envGet "ROOT_DIR") "."))
        (wsRes (resolveWorkspace! opts.workspace rootDir))]
    (mt wsRes
      ((err e) (err e))
      ((ok ws)
       (let [(claudeBin (mt opts.cliBin
                          ((some b) b)
                          ((none) (resolveCliBin! "CLAUDE_BIN" "claude" "/usr/local/bin/claude"))))]
         (if (not (fileExists? claudeBin))
           (err (str "CLAUDE_BIN not found: " claudeBin))
           (let [(sysPrompt (optionOr opts.systemPrompt (proxySystemPrompt)))
                 (promptDirRes (cliWritePromptDir! "claude" sysPrompt opts.noTools))]
             (mt promptDirRes
               ((err e) (err e))
               ((ok promptDir)
                (let [(tmpDir promptDir.tmpDir)
                      (promptPath promptDir.promptPath)
                      (promptFile (str tmpDir "/prompt.txt"))
                      (wRes (fileWrite promptFile prompt))]
                  (mt wRes
                    ((err e) (do (pathRemove tmpDir) (err (str "failed to write prompt: " e))))
                    ((ok _)
                     (let [(pidFile (str tmpDir "/child.pid"))
                           (cmd (claudeBuildCmd! claudeBin promptPath opts.noTools opts.model opts.effort))
                           (envStr (buildEnvString! "claude"))]
                       (runSpawnDispatch! cmd ws envStr (some promptFile) pidFile tmpDir opts.timeout "claude")))))))))))))

fn dispatch_claude_fallback! prompt: String model: (Option String) effort: (Option String) timeout: Int64 workspace: (Option String) systemPrompt: (Option String) noTools: Bool -> (Result CliParseResult String)
  (dispatchClaudeFallback! prompt (DispatchOptions
                                   :model model
                                   :effort effort
                                   :timeout timeout
                                   :workspace workspace
                                   :systemPrompt systemPrompt
                                   :noTools noTools
                                   :agent none
                                   :addDirs (list)
                                   :cliBin none))
