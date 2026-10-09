(module aslHarness/chatBench
  :x [ProviderInfo provider curlConfig curlRequestWith curlWriteAllWith curlCollect requestBody responseContent systemFor casePrompt call runModel main]
  :i [(asl-json/json :a j) (asl-syntax/asl/asn :a asn)])

(schema ProviderInfo
  (:f name String)
  (:f url String)
  (:f envVar String)
  (:f modelId String))

fn provider model: String -> ProviderInfo
  (cond
    ((stringStartsWith? model "groq/")
     (let [(modelId (optionOr (stringSlice model 5 (stringLength model)) ""))]
       (ProviderInfo :name "groq"
                     :url "https://api.groq.com/openai/v1/chat/completions"
                     :envVar "GROQ_API_KEY"
                     :modelId modelId)))
    ((stringStartsWith? model "gai/")
     (let [(modelId (optionOr (stringSlice model 4 (stringLength model)) ""))]
       (ProviderInfo :name "gai"
                     :url "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
                     :envVar "GEMINI_API_KEY"
                     :modelId modelId)))
    (else
     (ProviderInfo :name "openrouter"
                   :url "https://openrouter.ai/api/v1/chat/completions"
                   :envVar "OPENROUTER_API_KEY"
                   :modelId model)))

fn curlEscape value: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace value "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r")

fn curlConfig url: String key: String body: String maxTimeSec: Int64 -> String
  (str "url = \"" (curlEscape url) "\"\n"
       "request = \"POST\"\n"
       "header = \"Authorization: Bearer " (curlEscape key) "\"\n"
       "header = \"User-Agent: asl-chatBench/1\"\n"
       "header = \"Content-Type: application/json\"\n"
       "data-raw = \"" (curlEscape body) "\"\n"
       "max-time = \"" (stringFromInt64 maxTimeSec) "\"\n"
       "silent\n"
       "show-error\n")

fn requestBody model: String system: String user: String temp: Float64 -> String
  (let [(pinfo (provider model))
        (userMessage (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr user)))))
        (messages (if (= (stringLength system) 0)
                   (list userMessage)
                   (list (j/jobj (list (pair "role" (j/jstr "system")) (pair "content" (j/jstr system)))) userMessage)))]
    (j/jsonEmit (j/jobj (list (pair "model" (j/jstr pinfo.modelId))
                              (pair "messages" (j/jarr messages))
                              (pair "max_tokens" (j/jint (if (= pinfo.name "gai") 8000 4000)))
                              (pair "temperature" (j/jfloat temp))))))

fn ! taskFiles todo: (List String) found: (List String) -> (Result (List String) String)
  (if (listEmpty? todo) (ok (listReverse found))
    (let [(path (optionOr (listHead todo) ""))
          (rest (optionOr (listTail todo) (list)))]
      (mt (fileStat path)
        ((err e) (err e))
        ((ok stat) (if stat.isDir
          (mt (dirList path)
            ((err e) (err e))
            ((ok names) (let [(children (filter (fn [n] -> Bool (and (!= n ".git") (and (!= n ".asl") (and (!= n "hidden") (and (!= n "__pycache__") (!= n ".pytest_cache")))))) names))
                           (paths (map (fn [n] -> String (str path "/" n)) children))]
                         (taskFiles (listAppend paths rest) found))))
          (let [(base (optionOr (listHead (listReverse (stringSplit path "/"))) ""))]
            (if (or (= base "task.asn") (or (= base "truth.asn") (stringEndsWith? base ".pyc")))
              (taskFiles rest found)
              (taskFiles rest (cons path found)))))))))

fn ! renderTaskFiles paths: (List String) root: String acc: (List String) -> (Result String String)
  (if (listEmpty? paths) (ok (stringJoin (listReverse acc) "\n"))
    (let [(path (optionOr (listHead paths) ""))
          (rest (optionOr (listTail paths) (list)))
          (relative (optionOr (stringSlice path (+ (stringLength root) 1) (stringLength path)) ""))]
      (mt (fileReadString path)
        ((err e) (err e))
        ((ok content) (renderTaskFiles rest root (cons (str "=== " relative " ===\n" content) acc))))))

fn ! promptWithFiles root: String prompt: String -> (Result String String)
  (mt (taskFiles (list root) (list))
    ((err e) (err (str "casePrompt: " e)))
    ((ok paths) (mt (renderTaskFiles paths root (list))
      ((err e) (err (str "casePrompt: " e)))
      ((ok contents) (ok (str "Workspace files:\n" contents "\n\n" prompt))))))

fn promptLiteralTail tail: String -> (Option String)
  (mt (stringIndexOf tail "\"")
    ((none) (none))
    ((some start) (let [(content (optionOr (stringSlice tail (+ start 1) (stringLength tail)) ""))]
      (mt (stringIndexOf content "\"")
        ((none) (none))
        ((some finish) (stringSlice tail start (+ start finish 2)))))))

fn rawTaskPrompt source: String -> (Option String)
  (let [(chunks (stringSplit source ":prompt "))]
    (mt (listTail chunks)
      ((none) (none))
      ((some tails) (mt (listHead tails)
        ((none) (none))
        ((some tail) (promptLiteralTail tail))))))

fn ! promptFromTask root: String source: String -> (Result String String)
  (mt (rawTaskPrompt source)
    ((none) (err "casePrompt: missing or malformed :prompt string"))
    ((some literal) (let [(inside (optionOr (stringSlice literal 1 (- (stringLength literal) 1)) ""))]
      (mt (asn/asnUnescape inside)
        ((err e) (err (str "casePrompt: invalid string escape: " e)))
        ((ok prompt) (promptWithFiles root prompt))))))

fn ! casePrompt caseId: String -> (Result String String)
  (if (or (= caseId "") (or (stringContains? caseId "/") (stringContains? caseId "..")))
    (err (str "casePrompt: invalid case id " caseId))
    (let [(root (str "tests/harnessBench/cases/" caseId))]
      (mt (fileReadString (str root "/task.asn"))
        ((err e) (err (str "casePrompt: " e)))
        ((ok source) (promptFromTask root source)))))

fn ! layerText source: String id: String -> (Result String String)
  (let [(parts (stringSplit source (str ":id " id)))
        (afterId (optionOr (listHead (optionOr (listTail parts) (list))) ""))
        (textParts (stringSplit afterId ":text "))
        (afterText (optionOr (listHead (optionOr (listTail textParts) (list))) ""))
        (literal (promptLiteralTail afterText))]
    (mt literal
      ((none) (err (str "systemFor: layer has no :text: " id)))
      ((some raw) (let [(inside (optionOr (stringSlice raw 1 (- (stringLength raw) 1)) ""))]
        (mt (asn/asnUnescape inside)
          ((err e) (err (str "systemFor: invalid layer text: " e)))
          ((ok text) (ok text)))))))

fn ! systemLayers source: String ids: (List String) acc: (List String) -> (Result String String)
  (if (listEmpty? ids) (ok (stringJoin (listReverse acc) "\n"))
    (let [(id (optionOr (listHead ids) ""))
          (rest (optionOr (listTail ids) (list)))
          (textResult (layerText source id))]
      (mt textResult
        ((err e) (err e))
        ((ok text) (systemLayers source rest (cons text acc))))))

fn tailAfter source: String marker: String -> (Option String)
  (let [(parts (stringSplit source marker))]
    (mt (listTail parts) ((none) (none)) ((some tails) (listHead tails))))

fn ! quotedField source: String marker: String -> (Result String String)
  (mt (tailAfter source marker)
    ((none) (err (str "missing field " marker)))
    ((some tail) (mt (promptLiteralTail tail)
      ((none) (err (str "unquoted field " marker)))
      ((some raw) (let [(inside (optionOr (stringSlice raw 1 (- (stringLength raw) 1)) ""))]
        (mt (asn/asnUnescape inside)
          ((err e) (err e))
          ((ok value) (ok value))))))))

fn modeIdsFromTail tail: String -> (Option (List String))
  (mt (tailAfter tail ":attractors (")
    ((none) (none))
    ((some listText) (let [(parts (stringSplit listText ")"))]
      (mt (listHead parts)
        ((none) (none))
        ((some ids) (some (filter (fn [id] -> Bool (!= id "")) (stringSplit (stringTrim ids) " "))))))))

fn modeAttractorIds source: String mode: String -> (Option (List String))
  (mt (tailAfter source (str ":id " mode))
    ((none) (none))
    ((some modeTail) (modeIdsFromTail modeTail)))

fn ! attrLine source: String id: String -> (Result String String)
  (mt (tailAfter source (str ":id " id))
    ((none) (err (str "systemFor: missing attractor " id)))
    ((some record) (mt (quotedField record ":goal ")
      ((err e) (err e))
      ((ok goal) (mt (quotedField record ":shadow ")
        ((err e) (err e))
        ((ok shadow) (ok (str id ": " goal ", overdone: " shadow))))))))

fn ! attrLines source: String ids: (List String) acc: (List String) -> (Result String String)
  (if (listEmpty? ids) (ok (stringJoin (listReverse acc) "; "))
    (let [(id (optionOr (listHead ids) ""))
          (rest (optionOr (listTail ids) (list)))]
      (mt (attrLine source id)
        ((err e) (err e))
        ((ok line) (attrLines source rest (cons line acc))))))

fn ! attractorText source: String mode: String -> (Result String String)
  (mt (quotedField source ":intro ")
    ((err e) (err e))
    ((ok intro) (mt (modeAttractorIds source mode)
      ((none) (err (str "systemFor: no attractors for mode " mode)))
      ((some ids) (mt (attrLines source ids (list))
        ((err e) (err e))
        ((ok lines) (ok (str intro " " lines))))))))

fn ! fillSystemDate prompt: String -> (Result String String)
  (let [(date (processRun "date +%F"))]
    (if (!= date.exitCode 0) (err "systemFor: date command failed")
      (ok (stringReplace prompt "{date}" (stringTrim date.stdout)))))

fn ! completeSystem source: String mode: String -> (Result String String)
  (mt (attractorText source mode)
    ((err e) (err e))
    ((ok attractors) (mt (systemLayers source (list "chat" "evidence" "scope" "reasoning") (list))
      ((err e) (err e))
      ((ok layers) (ok (str attractors "\n" layers))))))

fn ! systemFor condName: String mode: String -> (Result String String)
  (if (= condName "none") (ok "")
    (if (or (= condName "core") (= condName "harness"))
      (mt (fileReadString "asl/grammar/harness.asn")
        ((err e) (err (str "systemFor: cannot read harness source: " e)))
        ((ok source) (mt (completeSystem source mode)
          ((err e) (err e))
          ((ok prompt) (fillSystemDate prompt)))))
      (err (str "systemFor: unsupported condition " condName " in mode " mode))))

fn ! firstJson array: j/Json -> (Result j/Json String)
  (mt array
    ((j/jarr rows) (mt (listHead rows)
      ((none) (err "API response has empty choices"))
      ((some choice) (ok choice))))
    (_ (err "API response choices is not an array")))

fn ! jsonStringField object: j/Json key: String -> (Result String String)
  (mt (j/jsonGet object key)
    ((none) (err (str "API response is missing " key)))
    ((some value) (mt value
      ((j/jstr text) (ok text))
      (_ (err (str "API field is not text: " key))))))

fn ! contentFromChoice choice: j/Json -> (Result String String)
  (mt (j/jsonGet choice "message")
    ((none) (err "API choice is missing message"))
    ((some message) (jsonStringField message "content")))

fn ! responseContent response: j/Json -> (Result String String)
  (mt (j/jsonGet response "choices")
    ((none) (err "API response is missing choices"))
    ((some choices) (mt (firstJson choices)
      ((err e) (err e))
      ((ok choice) (mt (contentFromChoice choice)
        ((err e) (err e))
        ((ok content) (ok (stringTrim content))))))))

fn ! curlWriteAllWith write: (Fn Int64 String (Result Int64 String)) fd: Int64 data: String -> (Result Bool String)
  (if (stringEmpty? data)
    (ok true)
    (mt (write fd data)
      ((err e) (err e))
      ((ok n) (if (<= n 0) (err "curl stdin write made no progress") (curlWriteAllWith write fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ! curlWriteAll fd: Int64 data: String -> (Result Bool String)
  (curlWriteAllWith (fn [(f Int64) (text String)] -> (Result Int64 String) (fdWrite f text)) fd data)

fn ! curlReady? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn ! curlReadSide fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((err e) (err (str "curl read failed: " e)))
    ((ok chunk) (if (stringEmpty? chunk) (ok (none)) (ok (some chunk)))))

fn ! curlReadStreams stdout: Int64 stderr: Int64 outOpen: Bool errOpen: Bool body: String message: String -> (Result (Pair String String) String)
  (if (and (not outOpen) (not errOpen))
    (ok (pair body message))
    (let [(fds (listAppend (if outOpen (list (pair stdout 1)) (list)) (if errOpen (list (pair stderr 1)) (list))))]
      (mt (fdPoll fds -1)
        ((err e) (err (str "curl poll failed: " e)))
        ((ok ready)
          (let [(outR (if (and outOpen (curlReady? ready stdout)) (curlReadSide stdout) (ok (some ""))))
                (errR (if (and errOpen (curlReady? ready stderr)) (curlReadSide stderr) (ok (some ""))))]
            (mt outR
              ((err e) (err e))
              ((ok outChunk)
                (mt errR
                  ((err e) (err e))
                  ((ok errChunk)
                    (curlReadStreams stdout stderr
                      (and outOpen (some? outChunk))
                      (and errOpen (some? errChunk))
                      (str body (optionOr outChunk ""))
                      (str message (optionOr errChunk ""))))))))))))

fn ! curlOutcome code: Int64 body: String message: String -> (Result String String)
  (if (= code 0) (ok body) (err (if (stringEmpty? message) (str "curl failed: " (stringFromInt64 code)) message)))

fn ! curlCollect pid: Int64 stdout: Int64 stderr: Int64 -> (Result String String)
  (let [(streams (curlReadStreams stdout stderr true true "" ""))
        (outClosed (fdClose stdout))
        (errClosed (fdClose stderr))]
    (mt streams
      ((err e) (do (procKill (- 0 pid) "SIGKILL") (procWaitPid pid false) (err e)))
      ((ok output)
        (mt (procWaitPid pid false)
          ((err e) (err (str "curl wait failed: " e)))
          ((ok code)
            (mt outClosed
              ((err e) (err (str "curl close failed: " e)))
              ((ok _) (mt errClosed
                ((err e) (err (str "curl close failed: " e)))
                ((ok _) (curlOutcome (optionOr code -1) (pairFirst output) (pairSecond output)))))))))))

fn ! curlRequestWith config: String executable: String -> (Result String String)
  (mt (procSpawnv (list executable "-q" "--config" "-" "--fail" "--silent" "--show-error") (none) (none))
    ((err e) (err (str "curl failed to start: " e)))
    ((ok sp)
      (let [(sent (curlWriteAll sp.stdin config))]
        (fdClose sp.stdin)
        (mt sent
          ((err e) (do (procKill (- 0 sp.pid) "SIGKILL") (procWaitPid sp.pid false) (fdClose sp.stdout) (fdClose sp.stderr) (err (str "curl stdin failed: " e))))
          ((ok _) (curlCollect sp.pid sp.stdout sp.stderr))))))

fn ! curlRequest config: String -> (Result String String)
  (curlRequestWith config "curl")

fn ! call model: String system: String user: String key: String temp: Float64 -> (Result String String)
  (let [(pinfo (provider model))
        (cfg (curlConfig pinfo.url key (requestBody model system user temp) 240))]
    (mt (curlRequest cfg)
      ((err e) (err e))
      ((ok body) (mt (j/jsonParse body)
        ((err e) (err (str "invalid API JSON: " e)))
        ((ok payload) (responseContent payload))))))

fn argValue args: (List String) flag: String -> (Option String)
  (fold (fn [(found (Option String)) (entry (Pair String String))] -> (Option String)
    (if (= (pairFirst entry) flag) (some (pairSecond entry)) found))
    (none) (zip args (optionOr (listTail args) (list))))

fn ! callForCase model: String caseId: String condition: String mode: String key: String -> (Result String String)
  (mt (casePrompt caseId)
    ((err e) (err e))
    ((ok prompt) (mt (systemFor condition mode)
      ((err e) (err e))
      ((ok system) (call model system prompt key 0.7)))))

fn ! runModel model: String caseId: String condition: String mode: String -> (Result Int64 String)
  (let [(info (provider model))]
    (mt (envGet info.envVar)
      ((none) (err (str info.envVar " not set")))
      ((some key) (mt (callForCase model caseId condition mode key)
        ((err e) (err e))
        ((ok reply) (do (println reply) (ok 0)))))))

fn ! runCliWithModel args: (List String) model: String -> (Result Int64 String)
  (mt (argValue args "--case")
    ((none) (err "chatBench: --case is required"))
    ((some caseId) (runModel model caseId
      (optionOr (argValue args "--condition") "none")
      (optionOr (argValue args "--mode") "scout"))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (argValue args "--model")
    ((none) (err "usage: chatBench --model <provider/model> --case <id>"))
    ((some model) (runCliWithModel args model)))
