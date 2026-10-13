(module asl-forms/delegate :x [DelegateCtx Outcome Spawned engineOk? engineExchangeWith engineFrameData contextFromEnv! delegateOp? runDelegate agentKillSeconds fieldNumber spawnRun spawnRunInput stepHead okLine rejectedLine pyStrip pyRepr pyExt errnoText timeoutText researchGatewayEntry! researchGatewayRoutes! resolveResearchEntry! researchEntryJson searchLimit researchCliArgv! researchCliText researchTimeoutSeconds researchDispatch researchDispatchWith researchTriage? searchFailed? crawlerSpawn] :i [(asl-forms/kernel :a k) (asl-forms/extract :a ex) (aslGateway/search :a srch) (aslGateway/research :a rs) (aslGateway/config :a cfg) (aslGateway/pyText :a pt) (asl-json/json :a j) (asl-engine/transport :a etp) (asl-intel/text :a it)])


(schema DelegateCtx (:f rootDir String) (:f binDir String) (:f wsDir String))

(schema Outcome (:f line String) (:f errCount Int64))

(schema Spawned (:f code Int64) (:f out String) (:f errText String) (:f failure String))

(schema Pump (:f outOpen Bool) (:f errOpen Bool) (:f out (List String)) (:f errText (List String)) (:f late Bool))


fn envOr! name: String -> String
  (optionOr (envGet name) "")

fn contextFromEnv! ws: String cwd: String -> DelegateCtx
  (let [(given (k/toolEnv! "SCRIPT_DIR"))
        (binDir (if (stringEmpty? given) (k/joinPath cwd "bin") given))
        (rootGiven (k/toolEnv! "ROOT_DIR"))
        (rootDir (cond ((not (stringEmpty? rootGiven)) rootGiven) ((= (k/baseName binDir) "bin") (k/dirName binDir)) (else cwd)))]
    (DelegateCtx :rootDir rootDir :binDir binDir :wsDir ws))

fn pyStripLeft s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (k/isSpaceChar (k/charAt s i))) (pyStripLeft s (+ i 1) n) i)

fn pyStripRight s: String j: Int64 lo: Int64 -> Int64
  (if (and (> j lo) (k/isSpaceChar (k/charAt s (- j 1)))) (pyStripRight s (- j 1) lo) j)

fn pyStrip s: String -> String
  (let [(n (stringLength s))
        (i (pyStripLeft s 0 n))
        (j (pyStripRight s n i))]
    (optionOr (stringSlice s i j) ""))

fn hexByte c: Int64 -> String
  (let [(digits "0123456789abcdef")]
    (str "\\x" (k/charAt digits (/ c 16)) (k/charAt digits (mod c 16))))

fn reprChar c: String quote: String -> String
  (let [(code (charCode c))]
    (cond
      ((= c "\\") "\\\\")
      ((= c quote) (str "\\" quote))
      ((= c "\n") "\\n")
      ((= c "\r") "\\r")
      ((= c "\t") "\\t")
      ((or (< code 32) (= code 127)) (hexByte code))
      (else c)))

fn pyRepr s: String -> String
  (let [(quote (if (and (stringContains? s "'") (not (stringContains? s "\""))) "\"" "'"))]
    (str quote (k/concatAll (map (fn [(c String)] -> String (reprChar c quote)) (stringChars s))) quote))

fn pyListRepr xs: (List String) -> String
  (str "[" (stringJoin (map pyRepr xs) ", ") "]")

fn leadingDots name: String i: Int64 -> Int64
  (if (and (< i (stringLength name)) (= (k/charAt name i) ".")) (leadingDots name (+ i 1)) i)

fn lastDotFrom name: String i: Int64 lo: Int64 -> Int64
  (cond
    ((< i lo) -1)
    ((= (k/charAt name i) ".") i)
    (else (lastDotFrom name (- i 1) lo)))

fn pyExt path: String -> String
  (let [(name (k/baseName path))
        (lo (leadingDots name 0))
        (dot (lastDotFrom name (- (stringLength name) 1) lo))]
    (if (< dot 0) "" (optionOr (stringSlice name dot (stringLength name)) "")))

fn strerror n: Int64 -> String
  (cond
    ((= n 2) "No such file or directory")
    ((= n 7) "Argument list too long")
    ((= n 8) "Exec format error")
    ((= n 13) "Permission denied")
    ((= n 20) "Not a directory")
    ((= n 21) "Is a directory")
    ((= n 36) "File name too long")
    ((= n 40) "Too many levels of symbolic links")
    ((= n 62) "Too many levels of symbolic links")
    (else (str "errno " (stringFromInt64 n))))

fn errnoOfKind kind: String -> Int64
  (cond
    ((= kind "notFound") 2)
    ((= kind "permission") 13)
    ((stringStartsWith? kind "io:") (optionOr (stringToInt64 (optionOr (stringSlice kind 3 (stringLength kind)) "")) -1))
    (else -1))

fn errnoText kind: String path: String -> String
  (let [(n (errnoOfKind kind))]
    (if (< n 0)
      (str kind ": " (pyRepr path))
      (str "[Errno " (stringFromInt64 n) "] " (strerror n) ": " (pyRepr path))))

fn timeoutText argv: (List String) seconds: Int64 -> String
  (str "Command '" (pyListRepr argv) "' timed out after " (stringFromInt64 seconds) " seconds")

fn envRowKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn childEnv! overrides: (Map String String) -> (Option (List String))
  (let [(keys (mapKeys overrides))]
    (if (listEmpty? keys)
      (none)
      (some (listAppend (filter (fn [(row String)] -> Bool (none? (mapGet overrides (envRowKey row)))) (envList))
                        (map (fn [(key String)] -> String (str key "=" (optionOr (mapGet overrides key) ""))) keys)))))

fn readyOn ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn ! drainFd fd: Int64 open: Bool acc: (List String) -> (Pair Bool (List String))
  (if (not open)
    (pair false acc)
    (mt (fdRead fd 65536)
      ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (pair false acc)) (pair true (cons chunk acc))))
      ((err e) (if (= e "wouldBlock") (pair true acc) (do (fdClose fd) (pair false acc))))))

fn ! pump sp: SpawnedProc st: Pump deadlineNs: Int64 -> Pump
  (if (not (or st.outOpen st.errOpen))
    st
    (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
      (if (<= leftMs 0)
        (with st :late true)
        (let [(watch (listAppend (if st.outOpen (list (pair sp.stdout 1)) (list)) (if st.errOpen (list (pair sp.stderr 1)) (list))))]
          (mt (fdPoll watch leftMs)
            ((err _) (with st :late true))
            ((ok ready)
              (let [(o (if (readyOn ready sp.stdout) (drainFd sp.stdout st.outOpen st.out) (pair st.outOpen st.out)))
                    (e (if (readyOn ready sp.stderr) (drainFd sp.stderr st.errOpen st.errText) (pair st.errOpen st.errText)))]
                (pump sp (Pump :outOpen (pairFirst o) :errOpen (pairFirst e) :out (pairSecond o) :errText (pairSecond e) :late false) deadlineNs))))))))

fn ! waitUntil pid: Int64 deadlineNs: Int64 -> (Result (Option Int64) String)
  (mt (procWaitPid pid true)
    ((err e) (err e))
    ((ok got)
      (mt got
        ((some code) (ok (some code)))
        ((none) (if (>= (monotonicNs) deadlineNs) (ok (none)) (do (sleepMs 5) (waitUntil pid deadlineNs)))))))

fn ! closeIfOpen fd: Int64 open: Bool -> Bool
  (if open (ok? (fdClose fd)) true)

fn ! killAll sp: SpawnedProc st: Pump -> Bool
  (do (procKill (- 0 sp.pid) "SIGKILL")
      (procWaitPid sp.pid false)
      (closeIfOpen sp.stdout st.outOpen)
      (closeIfOpen sp.stderr st.errOpen))

fn joined chunks: (List String) -> String
  (k/universalNewlines (k/concatAll (listReverse chunks)))

fn ! writeInputAll fd: Int64 input: String from: Int64 deadlineNs: Int64 -> (Result Int64 String)
  (if (>= from (stringLength input))
    (ok from)
    (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
      (if (<= leftMs 0)
        (err "subprocess stdin write timed out")
        (mt (fdPoll (list (pair fd 2)) leftMs)
          ((err e) (err e))
          ((ok ready)
            (if (not (readyOn ready fd))
              (do (sleepMs 5) (writeInputAll fd input from deadlineNs))
              (mt (fdWrite fd (optionOr (stringSlice input from (stringLength input)) ""))
                ((err e) (if (= e "wouldBlock") (writeInputAll fd input from deadlineNs) (err e)))
                ((ok n) (if (<= n 0) (err "subprocess stdin made no write progress") (writeInputAll fd input (+ from n) deadlineNs))))))))))

fn ! spawnRunInput argv: (List String) cwd: (Option String) overrides: (Map String String) seconds: Int64 input: String -> Spawned
  (let [(startNs (monotonicNs))
        (deadline (+ startNs (* seconds 1000000000)))]
    (mt (procSpawnv argv cwd (childEnv! overrides))
      ((err e) (Spawned :code -1 :out "" :errText "" :failure (errnoText e (optionOr (listHead argv) ""))))
      ((ok sp)
        (mt (writeInputAll sp.stdin input 0 deadline)
          ((err e) (do (fdClose sp.stdin) (procKill sp.pid "SIGKILL") (procWaitPid sp.pid false) (fdClose sp.stdout) (fdClose sp.stderr) (Spawned :code -1 :out "" :errText "" :failure e)))
          ((ok _)
              (let [(closed (fdClose sp.stdin))
                    (st (pump sp (Pump :outOpen true :errOpen true :out (list) :errText (list) :late false) deadline))]
                (if st.late
                  (do (killAll sp st) (Spawned :code -1 :out "" :errText "" :failure (timeoutText argv seconds)))
                  (mt (waitUntil sp.pid deadline)
                    ((err e) (Spawned :code -1 :out "" :errText "" :failure e))
                    ((ok got)
                      (mt got
                        ((none) (do (killAll sp st) (Spawned :code -1 :out "" :errText "" :failure (timeoutText argv seconds))))
                        ((some code) (Spawned :code code :out (joined st.out) :errText (joined st.errText) :failure ""))))))))))))

fn ! spawnRun argv: (List String) cwd: (Option String) overrides: (Map String String) seconds: Int64 -> Spawned
  (spawnRunInput argv cwd overrides seconds "")

fn stepHead id: Int64 op: String -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"" op "\"")

fn okLine line: String -> Outcome
  (Outcome :line line :errCount 0)

fn rejectedLine id: Int64 op: String code: String tail: String -> Outcome
  (Outcome :line (str (stepHead id op) " :status \"rejected\" :error-code \":" code "\"" tail ")") :errCount 1)

fn msgTail msg: String -> String
  (str " :message \"" (k/escapeAsnVal msg) "\"")

fn arg0 args: (List String) -> String
  (optionOr (listHead args) "")

fn kw2 kw: (Map String String) a: String b: String fallback: String -> String
  (k/kwOr kw a (k/kwOr kw b fallback))

fn binaryStep id: Int64 op: String field: String sp: Spawned fallback: String extra: String -> Outcome
  (cond
    ((not (stringEmpty? sp.failure)) (rejectedLine id op "ERR_EXEC_FAILED" (msgTail sp.failure)))
    ((and (= sp.code 0) (not (stringEmpty? (pyStrip sp.out))))
      (okLine (str (stepHead id op) " :status \"ok\"" extra " :" field "\n" (pyStrip sp.out) ")")))
    (else
      (let [(e (pyStrip sp.errText))]
        (rejectedLine id op "ERR_EXEC_FAILED" (msgTail (if (stringEmpty? e) fallback e))))))

fn envMapFromList! -> (Map String String)
  (fold (fn [(m (Map String String)) (row String)] -> (Map String String)
          (mt (stringIndexOf row "=")
            ((some i) (mapSet m (optionOr (stringSlice row 0 i) row) (optionOr (stringSlice row (+ i 1) (stringLength row)) "")))
            ((none) (mapSet m row ""))))
        (mapEmpty) (envList))

fn listOf v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn unwrapUrlError s: String -> String
  (let [(t (if (stringStartsWith? s "URLError: ") (optionOr (stringSlice s 10 (stringLength s)) s) s))]
    (if (and (stringStartsWith? t "<urlopen error ") (stringEndsWith? t ">"))
      (let [(inner (optionOr (stringSlice t 15 (- (stringLength t) 1)) ""))]
        (cond
          ((= inner "timed out") t)
          ((stringStartsWith? inner "curl exit ") "")
          (else inner)))
      t))

fn searchFailed? results: (List j/Json) errors: (List j/Json) -> Bool
  (and (listEmpty? results) (not (listEmpty? errors)))

fn researchTriage? value: String -> Bool
  (listContains? (list "true" "1" "yes" ":true") (stringLower value))

fn searchLimit kw: (Map String String) -> Int64
  (optionOr (stringToInt64 (kw2 kw "limit" "lim" "3")) 3)

fn ! searchStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(q (kw2 kw "query" "q" (arg0 args)))
        (lim (searchLimit kw))
        (eng (k/kwOr kw "engine" "auto"))]
    (if (stringEmpty? q)
      (rejectedLine id "search" "ERR_MISSING_ARG" (msgTail "Missing query argument"))
      (let [(env (envMapFromList!))
            (now (monotonicNs))
            (st (srch/newHubState env (/ now 1000000) 0 (mapEmpty) (mapEmpty)))
            (step (srch/executeSearchHub! st q eng lim))]
        (mt (pairFirst step)
          ((err e) (rejectedLine id "search" "ERR_EXEC_FAILED" (msgTail e.msg)))
          ((ok res)
            (let [(results (listOf (optionOr (pt/jget res "results") (j/jarr (list)))))
                  (errors (listOf (optionOr (pt/jget res "errors") (j/jarr (list)))))]
              (if (searchFailed? results errors)
                (let [(e0 (optionOr (listHead errors) (j/jnull)))
                      (rawMsg (pt/pyStr (optionOr (pt/jget e0 "error") (j/jnull))))
                      (msg (unwrapUrlError rawMsg))]
                  (rejectedLine id "search" "ERR_EXEC_FAILED" (msgTail (if (stringEmpty? msg) "Search execution failed" msg))))
                (mt (srch/formatSearchAsn res q)
                  ((err e) (rejectedLine id "search" "ERR_EXEC_FAILED" (msgTail e.msg)))
                  ((ok text)
                    (okLine (str (stepHead id "search") " :status \"ok\" :results\n" (pyStrip text) ")")))))))))))

fn researchTemp p: cfg/GatewayParams -> (List (Pair String j/Json))
  (mt p.temperature ((some v) (list (pair "temperature" (j/jfloat v)))) ((none) (list)))

fn researchEffort p: cfg/GatewayParams -> (List (Pair String j/Json))
  (mt p.effort ((some v) (list (pair "effort" (j/jstr v)))) ((none) (list)))

fn researchMaxTokens p: cfg/GatewayParams -> (List (Pair String j/Json))
  (mt p.maxTokens ((some v) (list (pair "maxTokens" (j/jint v)))) ((none) (list)))

fn researchParams p: cfg/GatewayParams -> j/Json
  (j/jobj (listAppend (listAppend (researchTemp p) (researchEffort p)) (researchMaxTokens p)))

fn researchEntryJson e: cfg/GatewayEntry -> j/Json
  (let [(u e.upstream)]
    (j/jobj (list (pair "alias" (j/jstr e.alias))
      (pair "dispatch" (j/jstr e.dispatch))
      (pair "upstream" (j/jobj (list
        (pair "provider" (j/jstr u.provider))
        (pair "url" (j/jstr u.url))
        (pair "key" (j/jstr u.key)))))
      (pair "params" (researchParams e.params))
      (pair "timeoutSec" (j/jfloat e.timeoutSec))
      (pair "rpm" (mt e.rpm ((some v) (j/jfloat v)) ((none) (j/jnull)))))))

fn resolvedResearchEntry r: cfg/GatewayResolvedEntry -> (Result j/Json pt/PyErr)
  (mt r
    ((cfg/entryResolved e) (ok (researchEntryJson e)))
    ((cfg/entryUnresolved a) (err (pt/pyErr "ValueError" (str "unresolved research route " a)))))

fn resolvedResearchEntries entries: (List cfg/GatewayResolvedEntry) -> (Result (List j/Json) pt/PyErr)
  (mt (listHead entries)
    ((none) (ok (list)))
    ((some entry)
      (mt (resolvedResearchEntry entry)
        ((err e) (err e))
        ((ok json)
          (mt (resolvedResearchEntries (optionOr (listTail entries) (list)))
            ((err e) (err e))
            ((ok rest) (ok (cons json rest))))))))

fn researchLabelMatches entry: j/Json model: String -> Bool
  (or (stringContains? (pt/pyStr (optionOr (pt/jget entry "alias") (j/jstr ""))) model)
      (stringContains? (pt/pyStr (optionOr (pt/jget entry "dispatch") (j/jstr ""))) model))

fn researchRoutesFor! table: cfg/GatewayTable profile: (Option String) intent: String model: String -> (Result (Pair String (List j/Json)) pt/PyErr)
  (mt (cfg/gatewayRouteEntries! table (list) profile intent)
    ((err message) (err (pt/pyErr "ValueError" message)))
    ((ok routes)
      (mt (resolvedResearchEntries routes.entries)
        ((err e) (err e))
        ((ok entries)
          (let [(selected (if (stringEmpty? model) entries (filter (fn [(e j/Json)] -> Bool (researchLabelMatches e model)) entries)))]
            (if (and (listEmpty? selected) (!= intent "audit"))
              (err (pt/pyErr "ValueError" (if (stringEmpty? model) (str "gateway profile has no " intent " route") (str "model " model " is not in the " intent " route of profile " routes.name))))
              (ok (pair routes.name selected))))))))

fn researchGatewayRoutes! table: cfg/GatewayTable profile: (Option String) model: String -> (Result (Pair String (Pair (List j/Json) (List j/Json))) pt/PyErr)
  (mt (researchRoutesFor! table profile "research" model)
    ((err e) (err e))
    ((ok research)
      (mt (researchRoutesFor! table (some (pairFirst research)) "audit" "")
        ((err e) (err e))
        ((ok audit) (ok (pair (pairFirst research) (pair (pairSecond research) (pairSecond audit))))))))

fn resolveResearchEntry! table: cfg/GatewayTable model: String profile: (Option String) -> (Result j/Json pt/PyErr)
  (mt (researchRoutesFor! table profile "research" model)
    ((err e) (err e))
    ((ok routes) (mt (listHead (pairSecond routes)) ((none) (err (pt/pyErr "ValueError" "gateway profile has no research route"))) ((some entry) (ok entry)))))

fn researchGatewayEntry! model: String -> (Result (Pair String (Pair (List j/Json) (List j/Json))) pt/PyErr)
  (let [(configured (envOr! "ASL_GATEWAY_CONFIG"))
        (home (envOr! "HOME"))
        (path (if (stringEmpty? configured) (cfg/gatewayProfilesPath home) configured))
        (registry (k/joinPath (k/dirName path) "cal/index.asn"))
        (exists (fileExists? path))
        (profileText (if exists (fileReadString path) (err "gateway config unavailable")))
        (loaded (cfg/gatewayProfilesLoadText! path exists profileText registry))
        (profileName (envGet "ASL_PROFILE"))]
    (mt loaded
      ((err message) (err (pt/pyErr "ValueError" message)))
      ((ok table) (researchGatewayRoutes! table profileName model))))

fn researchCliArgv! cli: String model: j/Json effort: j/Json prompt: String -> (List String)
  (researchCliArgvAt! cli model effort prompt "<system-prompt-file>" "<prompt-directory>" (resultOr (realPath ".") "."))

fn researchCliArgvAt! cli: String model: j/Json effort: j/Json prompt: String promptFile: String promptDir: String workspace: String -> (List String)
  (let [(name (pt/pyStr model))
        (eff (pt/pyStr effort))
        (bin (cond ((= cli "codex") (optionOr (envGet "CODEX_BIN") "codex")) ((= cli "claude") (optionOr (envGet "CLAUDE_BIN") "claude")) ((= cli "agy") (optionOr (envGet "AGY_BIN") "agy")) (else cli)))
        (modelFlag (if (pt/pyTruthy model) (list "-m" name) (list)))
        (effortFlag (if (listContains? (list "low" "medium" "high") eff) (list "-c" (str "model_reasoning_effort=\"" eff "\"")) (list)))]
    (cond
      ((= cli "codex") (listAppend (list bin "exec" "-C" workspace "-" "--json" "--ephemeral" "--skip-git-repo-check" "-c" (str "model_instructions_file=" promptFile) "-c" "project_doc_max_bytes=0") (listAppend effortFlag modelFlag)))
      ((= cli "claude") (listAppend (list bin "-p" "--output-format" "json" "--no-session-persistence" "--system-prompt-file" promptFile "--tools" "" "--strict-mcp-config" "--disable-slash-commands" "--setting-sources" "") (listAppend modelFlag (if (listContains? (list "low" "medium" "high" "xhigh" "max") eff) (list "--effort" eff) (list)))))
      ((= cli "agy") (list bin "--output-format" "json" "--model" name "--effort" (if (stringEmpty? eff) "low" eff) "--agent" "aslGateway" "--add-dir" promptDir "--add-dir" workspace "-p" "Answer the last turn of the conversation in your system prompt."))
      (else (list))))

fn codexTextFromLines lines: (List String) found: String -> String
  (mt (listHead lines)
    ((none) found)
    ((some line)
      (let [(parsed (j/jsonParse line))]
        (mt parsed
          ((err _) (codexTextFromLines (optionOr (listTail lines) (list)) found))
          ((ok event)
            (let [(typ (pt/pyStr (optionOr (pt/jget event "type") (j/jstr ""))))
                  (item (optionOr (pt/jget event "item") (j/jnull)))
                  (itemType (pt/pyStr (optionOr (pt/jget item "type") (j/jstr ""))))
                  (msg (pt/pyStr (optionOr (pt/jget item "text") (j/jstr ""))))]
              (codexTextFromLines (optionOr (listTail lines) (list)) (if (and (= typ "item.completed") (= itemType "agent_message")) msg found))))))))

fn researchCliText cli: String output: String -> String
  (if (= cli "codex")
    (let [(text (codexTextFromLines (stringSplit output "\n") ""))]
      (pyStrip (if (stringEmpty? text) output text)))
    (let [(parsed (j/jsonParse output))
          (key (if (= cli "claude") "result" "response"))]
      (mt parsed ((err _) (pyStrip output)) ((ok obj) (pyStrip (pt/pyStr (optionOr (pt/jget obj key) (j/jstr ""))))))))

fn ! researchDispatchWith cli: String model: j/Json effort: j/Json prompt: String overrides: (Map String String) -> (Result j/Json pt/PyErr)
  (let [(tmpDir (k/joinPath (if (stringEmpty? (envOr! "TMPDIR")) "/tmp" (envOr! "TMPDIR")) (str "asl-gateway-research-" (stringFromInt64 (procSelf)))))
        (promptDir (k/joinPath tmpDir ".agents/plugins/aslGateway/agents"))
        (promptFile (if (= cli "agy") (k/joinPath promptDir "aslGateway.md") (k/joinPath tmpDir "system.md")))
        (workspace (resultOr (realPath ".") "."))
        (rawArgv (researchCliArgvAt! cli model effort prompt promptFile tmpDir workspace))
        (key (cond ((= cli "codex") "CODEX_BIN") ((= cli "claude") "CLAUDE_BIN") ((= cli "agy") "AGY_BIN") (else "")))
        (configuredBin (if (stringEmpty? key) "" (optionOr (mapGet overrides key) (envOr! key))))
        (argv (if (or (stringEmpty? configuredBin) (listEmpty? rawArgv)) rawArgv (cons configuredBin (optionOr (listTail rawArgv) (list)))))
        (sysPrompt "The reply goes back to the program that sent the request.")
        (folder (if (= cli "agy") (k/joinPath (k/joinPath tmpDir ".agents/plugins/aslGateway") "agents") tmpDir))
        (mkdir (spawnRun (list "mkdir" "-p" folder) (none) (mapEmpty) 5))
        (systemText (if (= cli "agy") (str "---\nname: aslGateway\ndescription: asl gateway\nmainAgent: true\nsubagent: false\ntools: []\ninheritMcp: false\ninheritCustomizations: false\nexcludeDefaultComponents: true\n---\n\n" sysPrompt "\n\n(:conversation)\n" prompt) sysPrompt))
        (written (if (and (stringEmpty? mkdir.failure) (= mkdir.code 0)) (fileWrite promptFile systemText) (err "failed to prepare CLI prompt directory")))]
    (if (listEmpty? argv)
      (do (spawnRun (list "rm" "-rf" tmpDir) (none) (mapEmpty) 5) (err (pt/pyErr "ValueError" (str "unsupported research CLI provider " cli))))
      (mt written
        ((err e) (do (spawnRun (list "rm" "-rf" tmpDir) (none) (mapEmpty) 5) (err (pt/pyErr "RuntimeError" e))))
        ((ok _)
      (let [(sp (spawnRunInput argv (none) overrides (researchTimeoutSeconds) (if (= cli "agy") "" prompt)))
            (clean (spawnRun (list "rm" "-rf" tmpDir) (none) (mapEmpty) 5))]
        (cond
          ((or (not (stringEmpty? clean.failure)) (!= clean.code 0)) (err (pt/pyErr "RuntimeError" "failed to clean CLI prompt directory")))
          ((not (stringEmpty? sp.failure)) (err (pt/pyErr "RuntimeError" sp.failure)))
          ((!= sp.code 0) (err (pt/pyErr "RuntimeError" (if (stringEmpty? (pyStrip sp.errText)) (str cli " exited " (stringFromInt64 sp.code)) (pyStrip sp.errText)))))
          ((stringEmpty? (pyStrip sp.out)) (err (pt/pyErr "RuntimeError" (str cli " returned no text"))))
          (else (let [(text (researchCliText cli sp.out))]
                  (if (stringEmpty? text)
                    (err (pt/pyErr "RuntimeError" (str cli " returned no text")))
                    (ok (j/jobj (list (pair "text" (j/jstr text))))))))))))))

fn ! researchDispatch cli: String model: j/Json effort: j/Json prompt: String -> (Result j/Json pt/PyErr)
  (researchDispatchWith cli model effort prompt (mapEmpty))

fn researchTimeoutSeconds -> Int64
  400

fn routeUpstream entries: (List j/Json) name: String -> j/Json
  (mt (listHead entries)
    ((none) (j/jnull))
    ((some entry)
      (if (or (= name (pt/pyStr (optionOr (pt/jget entry "dispatch") (j/jstr ""))))
              (= name (pt/pyStr (optionOr (pt/jget entry "alias") (j/jstr "")))))
        (optionOr (pt/jget entry "upstream") (j/jnull))
        (routeUpstream (optionOr (listTail entries) (list)) name))))

fn researchDepth depth: String -> String
  (cond ((= depth "flash") "flash") ((= depth "deep") "targeted") ((= depth "exhaustive") "matrix") (else ""))

fn ! researchStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(topic (k/kwOr kw "topic" (arg0 args)))
        (depth (k/lstripColons (k/kwOr kw "depth" "flash")))
        (triage (researchTriage? (optionOr (mapGet kw "triage") "")))
        (model (k/kwOr kw "model" ""))
        (dTarget (researchDepth depth))]
    (cond
      ((stringEmpty? topic) (rejectedLine id "research" "ERR_MISSING_ARG" (msgTail "Missing topic argument")))
      ((stringEmpty? dTarget) (rejectedLine id "research" "ERR_INVALID_ARG" (msgTail (str "unknown depth :" depth "; allowed: :flash :deep :exhaustive"))))
      (else
        (mt (researchGatewayEntry! model)
          ((err e) (rejectedLine id "research" "ERR_EXEC_FAILED" (msgTail e.msg)))
          ((ok routes)
            (let [(env (envMapFromList!))
                  (now (monotonicNs))
                  (st (srch/newHubState env (/ now 1000000) 0 (mapEmpty) (mapEmpty)))
                  (entries (pairFirst (pairSecond routes)))
                  (auditEntries (pairSecond (pairSecond routes)))
                  (allEntries (listAppend entries auditEntries))
                  (up (fn [(m String)] -> j/Json (routeUpstream allEntries m)))
                  (disp (fn [(cli String) (r j/Json) (eff j/Json) (prompt String)] -> (Result j/Json pt/PyErr) (researchDispatch cli r eff prompt)))
                  (auditOpt (if (listEmpty? auditEntries) (none) (some auditEntries)))
                  (resPair (rs/executeResearchHub! st topic dTarget entries (j/jstr "auto") triage auditOpt up disp))]
              (mt (pairFirst resPair)
                ((err e) (rejectedLine id "research" "ERR_EXEC_FAILED" (msgTail e.msg)))
                ((ok rawRep)
                  (let [(rep (pt/jset rawRep "profile" (j/jstr (pairFirst routes))))
                        (status (pt/pyStr (optionOr (pt/jget rep "status") (j/jstr ""))))]
                    (if (= status "failed")
                      (let [(rawReason (pt/pyStr (optionOr (pt/jget rep "reason") (j/jstr "Research execution failed"))))
                            (triedList (listOf (optionOr (pt/jget rep "tried") (j/jarr (list)))))
                            (t0 (optionOr (listHead triedList) (j/jnull)))
                            (tErr (unwrapUrlError (pt/pyStr (optionOr (pt/jget t0 "error") (j/jnull)))))
                            (reason (if (not (stringEmpty? tErr)) tErr rawReason))]
                        (rejectedLine id "research" "ERR_EXEC_FAILED" (msgTail (if (stringEmpty? reason) "Research execution failed" reason))))
                      (mt (rs/formatResearchAsn rep triage)
                        ((err e) (rejectedLine id "research" "ERR_EXEC_FAILED" (msgTail e.msg)))
                        ((ok text)
                          (okLine (str (stepHead id "research") " :status \"ok\" :report\n" (pyStrip text) ")"))))))))))))))

fn crawlMode raw: String -> String
  (let [(m (k/lstripColons raw))]
    (cond
      ((listContains? (list "auto" "extension" "patchright" "staticHttp" "cloudProxy") m) m)
      ((or (= m "fast") (= m "static")) "staticHttp")
      (else "auto")))

fn resolveHost! ctx: DelegateCtx -> String
  (let [(env (envOr! "ASL_HOST"))]
    (cond
      ((and (not (stringEmpty? env)) (fileExists? env)) env)
      ((fileExists? (k/joinPath ctx.rootDir "asl/host/out/asl-host")) (k/joinPath ctx.rootDir "asl/host/out/asl-host"))
      ((fileExists? "asl/host/out/asl-host") "asl/host/out/asl-host")
      (else "asl-host")))

fn ! crawlerSpawn ctx: DelegateCtx args: (List String) timeoutSec: Int64 -> Spawned
  (let [(pkgEntry (k/joinPath ctx.rootDir "asl/packages/asl-crawler/src/crawler.asl"))]
    (if (fileExists? pkgEntry)
      (spawnRun (listAppend (list (resolveHost! ctx) "run" pkgEntry) args) (none) (mapEmpty) timeoutSec)
      (spawnRun (listAppend (list (str ctx.binDir "/asl-crawler")) args) (none) (mapEmpty) timeoutSec)))

fn ! crawlStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(url (k/kwOr kw "url" (arg0 args)))
        (mode (crawlMode (k/kwOr kw "mode" "auto")))
        (distill (k/lstripColons (k/kwOr kw "distill" "asn")))
        (inject (not (stringEmpty? (kw2 kw "injectAgent" "inject_agent" ""))))]
    (if (stringEmpty? url)
      (rejectedLine id "crawl" "ERR_MISSING_ARG" (msgTail "Missing url argument"))
      (binaryStep id "crawl" "snapshot"
                  (crawlerSpawn ctx (listAppend (list "crawl" url "--mode" mode "--distill" distill) (if inject (list "--inject-agent") (list))) 30)
                  "Crawl execution failed" (str " :url \"" (k/escapeAsnVal url) "\""))))

fn ! tiktokStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(url (k/kwOr kw "url" (arg0 args)))
        (watch (kw2 kw "watch" "duration" "10"))]
    (if (stringEmpty? url)
      (rejectedLine id "tiktok" "ERR_MISSING_ARG" (msgTail "Missing url argument"))
      (binaryStep id "tiktok" "receipt" (crawlerSpawn ctx (list "tiktok" url "--watch" watch) 40) "TikTok automation failed" "")))

fn ! automateStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(script (k/kwOr kw "script" (arg0 args)))]
    (if (stringEmpty? script)
      (rejectedLine id "automate" "ERR_MISSING_ARG" (msgTail "Missing script argument"))
      (binaryStep id "automate" "receipt" (crawlerSpawn ctx (list "automate" script) 60) "Automate execution failed" "")))

fn ! inBrowserAgentStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(act (k/lstripColons (k/kwOr kw "action" (optionOr (listHead args) "status"))))
        (exportFile (k/kwOr kw "export" ""))
        (tail (cond ((= act "status") (list "--status")) ((not (stringEmpty? exportFile)) (list "--export" exportFile)) (else (list))))]
    (binaryStep id "inBrowserAgent" "receipt" (crawlerSpawn ctx (listAppend (list "agent") tail) 15) "inBrowserAgent execution failed" ""))

fn digitRun s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (let [(c (charCode (k/charAt s i)))] (and (>= c 48) (<= c 57)))) (digitRun s (+ i 1) n) i)

fn spaceRun s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (k/isSpaceChar (k/charAt s i))) (spaceRun s (+ i 1) n) i)

fn fieldScan s: String b: Bytes tag: String signed: Bool from: Int64 -> (Option String)
  (let [(at (k/findFrom s b tag from))]
    (if (< at 0)
      (none)
      (let [(n (stringLength s))
            (sp (spaceRun s (+ at (stringLength tag)) n))
            (neg (and signed (> sp (+ at (stringLength tag))) (= (k/charAt s sp) "-")))
            (ds (if neg (+ sp 1) sp))
            (de (digitRun s ds n))]
        (if (and (> sp (+ at (stringLength tag))) (> de ds))
          (some (optionOr (stringSlice s (if neg sp ds) de) ""))
          (fieldScan s b tag signed (+ at 1))))))

fn fieldNumber text: String field: String signed: Bool -> (Option String)
  (fieldScan text (stringToBytes text) (str ":" field) signed 0)

fn metaFields raw: String -> String
  (k/concatAll (map (fn [(f String)] -> String (mt (fieldNumber raw f false) ((some v) (str " :" f " " v)) ((none) "")))
                    (list "packagesTotal" "modulesTotal" "cyclesCount" "totalNodes" "totalEdges" "hotspotsCount")))

fn outlineError? out: String -> Bool
  (let [(t (pyStrip out))
        (n (stringLength t))
        (a (spaceRun t 9 n))
        (b (if (= (optionOr (stringSlice t a (+ a 7)) "") ":status") (spaceRun t (+ a 7) n) -1))]
    (and (stringStartsWith? t "(:outline") (> a 9) (> b (+ a 7)) (= (optionOr (stringSlice t b (+ b 6)) "") ":error")))

fn strictFlag kw: (Map String String) -> Bool
  (mt (mapGet kw "strict") ((none) false) ((some v) (listContains? (list "true" "1" ":true") (stringLower v))))

fn intelArgs subop: String target: String kw: (Map String String) -> (List String)
  (let [(strict (if (strictFlag kw) (list "--strict") (list)))
        (opt (fn [(flag String) (v String)] -> (List String) (if (stringEmpty? v) (list) (list flag v))))
        (filterRaw (k/kwOr kw "filter" ""))]
    (cond
      ((= subop "coupling") (listAppend strict (opt "--package" target)))
      ((= subop "deadcode") (listAppend strict (opt "--package" target)))
      ((= subop "vacuity") strict)
      ((= subop "graph")
        (listAppend (if (stringEmpty? filterRaw) (list) (list "--filter" (k/lstripColons filterRaw)))
          (listAppend (opt "--limit" (k/kwOr kw "limit" ""))
            (listAppend (opt "--module" (k/kwOr kw "module" "")) (opt "--symbol" (k/kwOr kw "symbol" target))))))
      ((= subop "complexity") (listAppend (opt "--limit" (k/kwOr kw "limit" "")) (if (stringEmpty? target) (list) (list target))))
      ((= subop "trace") (cons "--asn" (opt "--target" target)))
      ((stringEmpty? target) (list))
      (else (list target))))

fn intelFinish id: Int64 subop: String sp: Spawned -> Outcome
  (cond
    ((not (stringEmpty? sp.failure)) (rejectedLine id "intel" "ERR_EXEC_FAILED" (msgTail sp.failure)))
    ((and (= sp.code 0) (= subop "outline") (outlineError? sp.out))
      (Outcome :line (str (stepHead id "intel") " :status \"rejected\" :subop \"outline\" :error-code \":ERR_INTEL_FAILED\" :receipt\n" (pyStrip sp.out) ")") :errCount 1))
    ((= sp.code 0)
      (let [(raw (pyStrip sp.out))]
        (okLine (str (stepHead id "intel") " :status \"ok\" :subop \"" subop "\"" (metaFields raw) " :receipt\n" raw ")"))))
    (else
      (let [(e (pyStrip sp.errText)) (o (pyStrip sp.out))]
        (rejectedLine id "intel" "ERR_INTEL_FAILED" (msgTail (cond ((not (stringEmpty? e)) e) ((not (stringEmpty? o)) o) (else "Intel check failed")))))))

fn ! intelStep ctx: DelegateCtx id: Int64 kw: (Map String String) args: (List String) -> Outcome
  (let [(subop (k/lstripColons (k/kwOr kw "op" (kw2 kw "subop" "action" (optionOr (listHead args) "coupling")))))
        (target (k/kwOr kw "target" (k/kwOr kw "symbol" (kw2 kw "file" "text" (optionOr (listGet args 1) "")))))
        (bin (k/joinPath ctx.binDir "asl"))]
    (if (and (= subop "outline") (not (stringEmpty? target)))
      (let [(res (k/resolveEditTarget! ctx.wsDir target))
            (path (pairFirst res))]
        (cond
          ((or (not (stringEmpty? (pairSecond res))) (not (k/isFile! path)))
            (Outcome :line (str (stepHead id "intel") " :status \"rejected\" :subop \"outline\" :error-code \":ERR_FILE_NOT_FOUND\""
                                (msgTail (if (stringEmpty? (pairSecond res)) (str "File not found: " target) (pairSecond res))) ")") :errCount 1))
          ((not (listContains? (list ".asl" ".asn") (stringLower (pyExt path))))
            (mt (fileReadString path)
              ((err e) (rejectedLine id "intel" "ERR_READ_FAILED" (msgTail (str "Failed to read file: " e))))
              ((ok text)
                (let [(lang (ex/languageOf path text))
                      (symbols (ex/extractSymbols text lang))
                      (receipt (ex/outlineReceipt (k/relToRoot ctx.wsDir path) lang text symbols))]
                  (okLine (str (stepHead id "intel") " :status \"ok\" :subop \"outline\" :receipt\n" receipt ")"))))))
          (else (intelFinish id subop (spawnRun (list bin "intel" "outline" path) (some ctx.rootDir) (mapSet (mapEmpty) "ASL_ROOT" ctx.wsDir) 60)))))
      (intelFinish id subop (spawnRun (listAppend (list bin "intel" subop) (intelArgs subop target kw)) (some ctx.rootDir)
                                      (if (= subop "outline") (mapSet (mapEmpty) "ASL_ROOT" ctx.wsDir) (mapEmpty)) 60))))

(schema EngineScope (:f sock String) (:f scope String))

fn taskScope? s: String -> Bool
  (or (stringStartsWith? s "task-") (stringStartsWith? s "task/"))

fn engineScope! ctx: DelegateCtx reqScope: String -> EngineScope
  (let [(custom (envOr! "ASL_ENGINE_SOCKET"))
        (wsSock (k/joinPath ctx.rootDir ".asl/engine.sock"))
        (sysSock "/tmp/asl-engine.sock")]
    (cond
      ((not (stringEmpty? custom)) (EngineScope :sock custom :scope "custom"))
      ((taskScope? reqScope)
        (let [(name (stringReplace (stringReplace reqScope "task/" "") "task-" ""))]
          (EngineScope :sock (k/joinPath (k/joinPath ctx.rootDir (str ".asl/tasks/" name)) "engine.sock") :scope (str "task-" name))))
      ((= reqScope "system") (EngineScope :sock sysSock :scope "system"))
      ((= reqScope "workspace") (EngineScope :sock wsSock :scope "workspace"))
      ((fileExists? wsSock) (EngineScope :sock wsSock :scope "workspace"))
      ((fileExists? sysSock) (EngineScope :sock sysSock :scope "system"))
      (else (EngineScope :sock wsSock :scope "workspace"))))

fn ! makeDirs path: String -> (Result Bool String)
  (cond
    ((k/isDir! path) (ok true))
    ((or (stringEmpty? path) (= (k/dirName path) path)) (err (str "cannot create " path)))
    (else
      (mt (makeDirs (k/dirName path))
        ((err e) (err e))
        ((ok _) (mt (dirCreate path) ((ok _) (ok true)) ((err e) (if (k/isDir! path) (ok true) (err (errnoText e path)))))))))

fn ! engineCli ctx: DelegateCtx args: (List String) seconds: Int64 -> Spawned
  (let [(entry (k/joinPath ctx.rootDir "asl/packages/asl-engine/src/cli.asl"))
        (host (resolveHost! ctx))]
    (if (not (fileExists? entry))
      (Spawned :code -1 :out "" :errText "" :failure (errnoText "notFound" entry))
      (spawnRun (listAppend (list host "run" entry) args) (some ctx.rootDir)
                (mapSet (mapSet (mapEmpty) "ASL_ENGINE_ENTRY" entry) "ASL_HOST" host) seconds)))

fn ! engineConnect ctx: DelegateCtx es: EngineScope tries: Int64 -> (Result Int64 String)
  (mt (unixConnect es.sock)
    ((ok fd) (ok fd))
    ((err e)
      (do (engineCli ctx (list "start" "--scope" es.scope) 30)
          (sleepMs 300)
          (if (<= tries 1) (err e) (engineConnect ctx es (- tries 1))))))

fn engineFrameData acc: String chunk: String -> (Pair Bool String)
  (let [(data (stringConcat acc chunk))]
    (mt (stringIndexOf data "\n")
      ((some i) (pair true (optionOr (stringSlice data 0 i) "")))
      ((none) (pair false data))))

fn ! engineFrame fd: Int64 acc: String deadline: Int64 -> (Result (Pair Bool String) String)
  (let [(current (engineFrameData acc ""))]
    (cond
      ((pairFirst current) (ok current))
      ((>= (stringLength (pairSecond current)) 8388608) (ok current))
      (else
        (let [(left (max 0 (/ (- deadline (monotonicNs)) 1000000)))]
          (cond
            ((= left 0) (err "timed out"))
            (else
              (mt (fdPoll (list (pair fd 1)) left)
                ((err e) (err (etp/socketErrorText! e)))
                ((ok ready)
                  (if (listEmpty? ready)
                    (err "timed out")
                    (mt (fdRead fd 65536)
                      ((err e) (err (etp/socketErrorText! e)))
                      ((ok chunk)
                        (let [(next (engineFrameData (pairSecond current) chunk))]
                          (cond
                            ((or (stringEmpty? chunk) (pairFirst next) (>= (stringLength (pairSecond next)) 8388608)) (ok next))
                            (else (engineFrame fd (pairSecond next) deadline)))))))))))))))

fn firstSpace s: String i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (k/isSpaceChar (k/charAt s i))) i (firstSpace s (+ i 1) n))

fn engineOk? resp: String -> Bool
  (let [(bs (stringToBytes resp))
        (n (bytesLength bs))
        (w (firstSpace resp 2 n))
        (e (+ w 12))]
    (and (stringStartsWith? resp "(:")
         (> w 2)
         (= (optionOr (stringSlice resp w e) "") " :status :ok")
         (or (>= e n) (not (it/isWordCp (it/cpAt bs n e))))))

fn engineExchangeWith id: Int64 op: String stepStr: String exchange: (fn [String] -> (Result (Pair Bool String) String)) -> Outcome
  (mt (exchange (str stepStr "\n"))
      ((err e) (rejectedLine id op "ERR_SOCKET_IO" (msgTail e)))
      ((ok got)
        (let [(resp (pyStrip (pairSecond got)))]
          (cond
            ((not (pairFirst got))
              (rejectedLine id op "ERR_TRUNCATED" (str " :truncated true :bytes " (stringFromInt64 (stringLength (pairSecond got)))
                                                        (msgTail "Engine response incomplete (no frame terminator within 8388608 bytes or connection closed early)"))))
            ((not (engineOk? resp)) (rejectedLine id op "ERR_ENGINE_REJECTED" (str " :receipt " resp)))
            (else (okLine (str (stepHead id op) " :status \"ok\" :receipt " resp ")")))))))

fn ! engineExchange id: Int64 op: String fd: Int64 stepStr: String -> Outcome
  (engineExchangeWith id op stepStr
    (fn [wire]
      (let [(sent (etp/writeAllFd! fd wire))
            (framed (mt sent ((err e) (err e)) ((ok _) (engineFrame fd "" (+ (monotonicNs) 2500000000)))))
            (closed (fdClose fd))]
        framed)))

fn ! engineStep ctx: DelegateCtx id: Int64 op: String kw: (Map String String) args: (List String) stepStr: String -> Outcome
  (let [(reqScope (k/lstripColons (optionOr (mapGet kw "scope") "")))
        (action (k/lstripColons (k/kwOr kw "action" (optionOr (listHead args) "status"))))
        (es (engineScope! ctx reqScope))
        (made (if (taskScope? reqScope) (makeDirs (k/dirName es.sock)) (ok true)))]
    (cond
      ((err? made) (rejectedLine id op "ERR_EXEC_FAILED" (msgTail (mt made ((err e) e) ((ok _) "")))))
      ((and (= op "engine") (listContains? (list "stop" "restart") action) (= es.scope "system"))
        (rejectedLine id "engine" "ERR_PERMISSION_DENIED" " :message \"Agent workspace isolation boundary: mutating actions (:stop, :restart) on system-wide engine are restricted to human CLI operators; use :scope :workspace to manage workspace engine\""))
      ((and (= op "engine") (= action "restart"))
        (let [(sp (engineCli ctx (list "restart" "--scope" es.scope) 10))]
          (cond
            ((not (stringEmpty? sp.failure)) (rejectedLine id "engine" "ERR_EXEC_FAILED" (msgTail sp.failure)))
            ((= sp.code 0)
              (okLine (str (stepHead id "engine") " :status \"ok\" :receipt (:receipt :status :ok :engine :restarted :scope \"" es.scope "\" :socket \"" (k/escapeAsnVal es.sock) "\"))")))
            (else
              (let [(e (pyStrip sp.errText))
                    (msg (stringChars (if (stringEmpty? e) (pyStrip sp.out) e)))]
                (rejectedLine id "engine" "ERR_RESTART_FAILED" (msgTail (k/concatAll (listDrop msg (max 0 (- (listLength msg) 200)))))))))))
      (else
        (mt (engineConnect ctx es 3)
          ((err _) (rejectedLine id op "ERR_ENGINE_OFFLINE" (msgTail (str "Could not connect to asl-engine at " es.sock " (scope: " es.scope ")"))))
          ((ok fd) (engineExchange id op fd stepStr))))))

fn budget kw: (Map String String) key: String fallback: Int64 -> Int64
  (let [(raw (pyStrip (optionOr (mapGet kw key) "")))]
    (if (and (not (stringEmpty? raw)) (listAll? (fn [(c String)] -> Bool (let [(x (charCode c))] (and (>= x 48) (<= x 57)))) (stringChars raw)))
      (optionOr (stringToInt64 raw) fallback)
      fallback))

fn agentKillSeconds kw: (Map String String) -> Int64
  (let [(queue (budget kw "queueTimeout" 1200))
        (given (budget kw "timeout" -1))
        (timeout (if (>= given 0) given (max 600 (- (budget kw "wallBudget" 0) queue))))]
    (+ timeout (+ queue 30)))

fn ! agentStep ctx: DelegateCtx id: Int64 kw: (Map String String) stepStr: String -> Outcome
  (let [(host (k/joinPath ctx.rootDir "asl/host/out/asl-host"))
        (agentMain (k/joinPath ctx.rootDir "asl/agentLoop/main.asl"))]
    (if (or (not (k/isFile! host)) (not (k/isFile! agentMain)))
      (rejectedLine id "agent" "ERR_AGENT_DISPATCH" (msgTail (str "ASL agent loop not installed: " agentMain)))
      (let [(sp (spawnRun (list host "run" agentMain stepStr) (some ctx.rootDir) (mapSet (mapEmpty) "ASL_ROOT_DIR" ctx.wsDir) (agentKillSeconds kw)))
            (shown (if (stringEmpty? sp.errText) true (do (eprintln (if (stringEndsWith? sp.errText "\n") (optionOr (stringSlice sp.errText 0 (- (stringLength sp.errText) 1)) "") sp.errText)) true)))
            (out (pyStrip sp.out))
            (bad (if (!= sp.code 0) 1 0))]
        (cond
          ((not (stringEmpty? sp.failure)) (rejectedLine id "agent" "ERR_AGENT_DISPATCH" (msgTail sp.failure)))
          ((not (stringEmpty? out))
            (Outcome :line (str (stepHead id "agent") " :status \"" (if (= bad 0) "ok" "failed") "\" :receipt " out ")") :errCount bad))
          (else
            (Outcome :line (str (stepHead id "agent") " :status \"rejected\" :error-code \":ERR_AGENT_DISPATCH\""
                                (msgTail (str "empty output, exit " (stringFromInt64 sp.code) " (the agent stderr went to stderr)")) ")")
                     :errCount (+ 1 bad)))))))

fn delegateOp? op: String -> Bool
  (listContains? (list "search" "research" "crawl" "tiktok" "automate" "inBrowserAgent" "intel" "manage" "proc" "engine" "agent") op)

fn ! runDelegate ctx: DelegateCtx id: Int64 op: String kw: (Map String String) args: (List String) stepStr: String -> Outcome
  (cond
    ((= op "search") (searchStep ctx id kw args))
    ((= op "research") (researchStep ctx id kw args))
    ((= op "crawl") (crawlStep ctx id kw args))
    ((= op "tiktok") (tiktokStep ctx id kw args))
    ((= op "automate") (automateStep ctx id kw args))
    ((= op "inBrowserAgent") (inBrowserAgentStep ctx id kw args))
    ((= op "intel") (intelStep ctx id kw args))
    ((listContains? (list "manage" "proc" "engine") op) (engineStep ctx id op kw args stepStr))
    ((= op "agent") (agentStep ctx id kw stepStr))
    (else (rejectedLine id op "ERR_NOT_PORTED" (msgTail (str "op " op " is not a delegating op of asl-forms/delegate; run scripts/aslForms.py")))))
