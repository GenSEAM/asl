(module aslGateway/server
  :x [gatewayCliMode? breakerEvent! GatewayTurnVerdict Launch GatewayLoop linkOpen! linkSend! extractThinkBlocks detectEshViolation inspectCompletionTurn handleSyncIngest handleBrowserDispatch handleMediaDispatch gatewayHostPath! gatewayStatePath! ensureSessionHeader main! main mainWith
      GatewayConn ConnPhase connReading connTimer connBucketWait connCli connWriting drive! gatewayTurn! loopConns apiKindOf PendingCall runEffect! budgetRefusal! cliAdmit! keyFilesWorldEnv!]
  :i [(wire :a wire) (sync :a sync) (browser :a browser) (media :a media) (aslGateway/cliDispatch :a cli) (sessions :a ses) (binding :a bd) (asl-cli/system :a sys)
      (aslGateway/chat :a ch) (aslGateway/upstream :a u) (aslGateway/config :a c) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b)
      (aslGateway/dispatch :a dp) (aslGateway/plugin :a p) (aslGateway/usage :a g) (aslGateway/usageLedger :a ul) (aslGateway/router :a rt) (asl-json/json :a j)
      (aslGateway/subPace :a spc) (aslGateway/subsRefresh :a subsr) (aslGateway/omniApi :a om) (aslGateway/federation :a fed) (aslGateway/balancer :a bl) (asl-http/http11 :a h)])

(schema GatewayTurnVerdict
  (:f allowed Bool)
  (:f quarantinedThink Str)
  (:f cleanOutput Str)
  (:f toolCalls (List Str))
  (:f rejectionReason Str))

fn extractThinkBlocks text: Str -> (Pair Str Str)
  (let [(openTag "<think>")
        (closeTag "</think>")
        (idxOpen (stringIndexOf text openTag))]
    (match idxOpen
      ((none) (pair "" text))
      ((some o)
        (let [(afterOpen (optionOr (stringSlice text (+ o 7) (stringLength text)) ""))
              (idxClose (stringIndexOf afterOpen closeTag))]
          (match idxClose
            ((none) (pair (stringTrim afterOpen) (optionOr (stringSlice text 0 o) "")))
            ((some c)
              (let [(thinkContent (optionOr (stringSlice afterOpen 0 c) ""))
                    (prefix (optionOr (stringSlice text 0 o) ""))
                    (suffix (optionOr (stringSlice afterOpen (+ c 8) (stringLength afterOpen)) ""))
                    (remaining (stringTrim (str prefix " " suffix)))]
                (pair (stringTrim thinkContent) remaining))))))))

fn detectEshViolation text: Str -> Bool
  (let [(lower (stringLower text))]
    (and (or (stringContains? lower "test") (or (stringContains? lower "gate") (stringContains? lower "assert")))
         (or (stringContains? lower " pass") (or (stringContains? lower "verif") (stringContains? lower "clean")))))

fn inspectCompletionTurn rawText: Str hasVerifiedExec: Bool -> GatewayTurnVerdict
  (let [(demuxThink (extractThinkBlocks rawText))
        (thinkPart (pairFirst demuxThink))
        (remaining (pairSecond demuxThink))
        (demuxAsn (wire/demuxRawAsnTurn remaining))
        (uiPart (pairFirst demuxAsn))
        (toolPart (pairSecond demuxAsn))
        (isEsh (and (detectEshViolation uiPart) (not hasVerifiedExec)))]
    (if isEsh
      (GatewayTurnVerdict
        :allowed false
        :quarantinedThink thinkPart
        :cleanOutput "Action blocked by L7 Cognitive Gateway: verbal claim of test passage without verified execution receipt (ESH violation)."
        :toolCalls (list)
        :rejectionReason "Verbal self-declared execution without verified runtime proof (ESH violation)")
      (GatewayTurnVerdict
        :allowed true
        :quarantinedThink thinkPart
        :cleanOutput uiPart
        :toolCalls toolPart
        :rejectionReason "")))

fn handleSyncIngest rawPayload: Str -> (Pair Str Str)
  (let [(contentHash (sync/computeContentHash rawPayload))]
    (pair "ok" contentHash))

fn handleBrowserDispatch frame: browser/BrowserActionFrame -> browser/BrowserActionReceipt
  (let [(isValid (browser/validateActionOp frame.op))]
    (if isValid
      (browser/createSuccessReceipt frame.actionId 45 "https://gateway.local" "none" "executed")
      (browser/createErrorReceipt frame.actionId 0 "invalid_op" "Unknown browser operation")))

fn handleMediaDispatch req: media/MediaGenRequest -> media/MediaGenReceipt
  (let [(isValid (media/validateMediaKind req.mediaKind))
        (dim (media/calculateMediaDimensions req.aspectRatio))]
    (if isValid
      (media/createMediaReceipt req.requestId "ok" "storage://generated/asset" "/tmp/asset" "hash123" (pairFirst dim) (pairSecond dim) 10)
      (media/createMediaReceipt req.requestId "rejected" "" "" "" 0 0 0)))

fn gatewayServerArg args: (List String) index: Int64 -> String
  (optionOr (listGet args index) "")

fn gatewayDropArgs args: (List String) -> (List String)
  (match (listTail args) ((some tail) tail) ((none) (list)))

fn gatewayFindArg args: (List String) flag: String fallback: String -> String
  (if (< (listLength args) 2) fallback
    (if (= (gatewayServerArg args 0) flag) (gatewayServerArg args 1)
      (gatewayFindArg (gatewayDropArgs args) flag fallback)))

; (:m this path must never collide with c/gatewayProfilesPath's home/.asl/gateway.asn, the real hand-maintained provider/model/profile config, or with ul/defaultLedgerPath's home/.asl/run/gatewayCalls.asn: gatewayStartWithHost! below unconditionally overwrites this path with a one-line run-state receipt, and a collision silently destroys whatever real file sits at the same path on every start; serverTest.asl's testStatePathIsolation asserts this directly so a future edit cannot reintroduce the collision)
fn ! gatewayStatePath! -> String
  (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/gatewayState.asn")

fn ! gatewayReadyPath! -> String
  (str (gatewayStatePath!) ".ready")

fn gatewayNumberAfter text: String marker: String fallback: Int64 -> Int64
  (match (stringIndexOf text marker)
    ((none) fallback)
    ((some at)
      (let [(start (+ at (stringLength marker)))
            (tail (optionOr (stringSlice text start (stringLength text)) ""))
            (space (stringIndexOf tail " "))
            (close (stringIndexOf tail ")"))
            (end (if (some? space) (optionOr space (stringLength tail))
                  (if (some? close) (optionOr close (stringLength tail)) (stringLength tail))))
            (token (optionOr (stringSlice tail 0 end) ""))]
        (optionOr (stringToInt64 token) fallback))))

fn gatewayStateNumbers text: String -> (Pair Int64 Int64)
  (pair (gatewayNumberAfter text ":pid " 0) (gatewayNumberAfter text ":port " 0))

fn ! gatewayServiceOwnsPid! launch: Launch pid: Int64 -> Bool
  (if (<= pid 1) false
    (let [(ps (processRun (str "/bin/ps -p " pid " -o command=")))
          (cmd ps.stdout)]
      (and (= ps.exitCode 0)
        (and (stringContains? cmd " serve --port ")
          (or (stringContains? cmd launch.module) (stringContains? cmd " --ready "))))))

fn gatewaySafeShellArgAt? text: String index: Int64 -> Bool
  (if (>= index (stringLength text)) true
    (let [(character (optionOr (stringSlice text index (+ index 1)) ""))]
      (and (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/:=-+%" character)
        (gatewaySafeShellArgAt? text (+ index 1)))))

fn gatewaySafeShellArg? text: String -> Bool
  (and (not (stringEmpty? text)) (gatewaySafeShellArgAt? text 0))

fn gatewayUpstreamPort upstream: String -> Int64
  (let [(scheme (stringIndexOf upstream "http://"))
        (after (if (some? scheme) (+ (optionOr scheme 0) 7) (stringLength upstream)))
        (tail (optionOr (stringSlice upstream after (stringLength upstream)) ""))
        (colon (stringIndexOf tail ":"))
        (hostPort (if (some? colon)
                    (optionOr (stringSlice tail (+ (optionOr colon 0) 1) (stringLength tail)) "")
                    ""))
        (slash (stringIndexOf hostPort "/"))
        (query (stringIndexOf hostPort "?"))
        (end (if (some? slash) (optionOr slash (stringLength hostPort))
              (if (some? query) (optionOr query (stringLength hostPort)) (stringLength hostPort))))]
    (optionOr (stringToInt64 (optionOr (stringSlice hostPort 0 end) "")) 0))

fn ! gatewayStatus! launch: Launch requestedPort: Int64 -> (Result Int64 String)
  (match (fileReadString (gatewayStatePath!))
    ((err _) (do (sys/say! (str "(:gateway :status :offline :port " requestedPort ")")) (ok 0)))
    ((ok state)
      (let [(numbers (gatewayStateNumbers state))
            (pid (pairFirst numbers))
            (port (if (> (pairSecond numbers) 0) (pairSecond numbers) requestedPort))
            (running (and (> pid 1) (gatewayServiceOwnsPid! launch pid)))]
        (do (sys/say! (if running
                        (str "(:gateway :status :running :port " port " :pid " pid ")")
                        (str "(:gateway :status :offline :port " port ")")))
          (ok 0)))))

fn ! gatewayLegacyStatus! launch: Launch requestedPort: Int64 -> (Result Int64 String)
  (match (fileReadString (gatewayStatePath!))
    ((err _) (do (sys/say! (str "ASL Cognitive Gateway: OFFLINE (Port: " requestedPort ")")) (ok 0)))
    ((ok state)
      (let [(numbers (gatewayStateNumbers state))
            (pid (pairFirst numbers))
            (port (if (> (pairSecond numbers) 0) (pairSecond numbers) requestedPort))
            (running (and (> pid 1) (gatewayServiceOwnsPid! launch pid)))]
        (do (sys/say! (if running
                        (str "ASL Cognitive Gateway: ACTIVE (PID: " pid ", Port: " port ")")
                        (str "ASL Cognitive Gateway: OFFLINE (Port: " port ")")))
          (ok 0)))))

fn ! gatewayWaitGone! pid: Int64 attempts: Int64 -> Bool
  (if (<= attempts 0) (not (resultOr (procAlive? pid) false))
    (if (resultOr (procAlive? pid) false)
      (do (processRun "/bin/sleep 0.02") (gatewayWaitGone! pid (- attempts 1))) true))

fn ! gatewayStop! launch: Launch -> (Result Int64 String)
  (match (fileReadString (gatewayStatePath!))
    ((err _) (do (sys/say! "(:gateway :status :offline :port 0)") (ok 0)))
    ((ok state)
      (let [(numbers (gatewayStateNumbers state))
            (pid (pairFirst numbers))
            (port (pairSecond numbers))]
        (if (not (gatewayServiceOwnsPid! launch pid))
          (do (sys/say! (str "(:gateway :status :offline :port " port ")")) (ok 0))
          (match (procKill pid "SIGTERM")
            ((err e) (err (str "gateway stop failed: " e)))
            ((ok _)
              (if (gatewayWaitGone! pid 100)
                (do (sys/say! (str "(:gateway :status :offline :port " port ")")) (ok 0))
                (err "gateway process did not exit after SIGTERM"))))))))

fn gatewayStateUpstream text: String -> String
  (match (stringIndexOf text ":upstream ")
    ((none) "")
    ((some at)
      (let [(start (+ at 10))
            (tail (optionOr (stringSlice text start (stringLength text)) ""))
            (space (stringIndexOf tail " "))
            (close (stringIndexOf tail ")"))
            (end (if (some? space) (optionOr space (stringLength tail))
                  (if (some? close) (optionOr close (stringLength tail)) (stringLength tail))))]
        (optionOr (stringSlice tail 0 end) ""))))

fn ! gatewayRestart! launch: Launch args: (List String) -> (Result Int64 String)
  (match (fileReadString (gatewayStatePath!))
    ((err _) (gatewayStart! launch args))
    ((ok state)
      (let [(numbers (gatewayStateNumbers state))
            (oldPid (pairFirst numbers))
            (oldPort (pairSecond numbers))
            (requestedPort (gatewayFindArg args "--port" ""))
            (portText (if (stringEmpty? requestedPort) (stringFromInt64 oldPort) requestedPort))
            (requestedUpstream (gatewayFindArg args "--upstream" ""))
            (oldUpstream (gatewayStateUpstream state))
            (upstream (if (stringEmpty? requestedUpstream) oldUpstream requestedUpstream))]
        (if (or (stringEmpty? upstream) (not (gatewaySafeShellArg? upstream)))
          (err "gateway restart requires a safe upstream URL")
          (match (stringToInt64 portText)
            ((none) (err "gateway restart port must be an integer between 0 and 65535"))
            ((some port)
              (if (or (< port 0) (> port 65535))
                (err "gateway restart port must be an integer between 0 and 65535")
                (match (if (gatewayServiceOwnsPid! launch oldPid) (gatewayStop! launch) (ok 0))
                  ((err e) (err e))
                  ((ok _) (gatewayStart! launch (list "start" "--port" portText "--upstream" upstream)))))))))))

(schema Launch
  (:f module String)
  (:f families (List dp/LifecycleFamily)))

fn ! main args: (List String) -> (Result Int64 String)
  (mainWith args "asl/packages/asl-gateway/src/server.asl" (list))

; (:m :ref GW-MODELS-MODE :do "the gateway subcommands that run in the CLI main instead of the server: config, configCheck, convert, stats, session, models and subs (models sync and subs refresh reach cliDispatch)")
fn gatewayCliMode? mode: String -> Bool
  (listContains? (list "config" "configCheck" "convert" "stats" "session" "models" "subs") mode)

fn ! mainWith args: (List String) module: String families: (List dp/LifecycleFamily) -> (Result Int64 String)
  (let [(launch (Launch :module module :families (listAppend (dp/builtinFamilies) families)))
        (first (gatewayServerArg args 0))
        (mode (if (= first "--port") (gatewayServerArg args 2) first))
        (portText (gatewayFindArg args "--port" "0"))
        (port (optionOr (stringToInt64 portText) 0))]
    (cond
      ((= mode "start")
        (match (gatewayStart! launch args)
          ((err e) (do (sys/sayErr! e) (ok 1)))
          ((ok boundPort)
            (let [(state (resultOr (fileReadString (gatewayStatePath!)) ""))]
              (do (sys/say! (str "(:gateway :status :running :port " boundPort
                              " :pid " (gatewayNumberAfter state ":pid " 0) ")"))
                (ok 0))))))
      ((= mode "status") (gatewayStatus! launch port))
      ((= mode "stop") (gatewayStop! launch))
      ((= mode "serve")
        (let [(upstream (gatewayFindArg args "--upstream" ""))
              (ready (gatewayFindArg args "--ready" ""))]
          (match (gatewayRunServer! launch port upstream ready)
            ((err e) (do (sys/sayErr! e) (ok 1)))
            ((ok _) (ok 0)))))
      ((= mode "run")
        (let [(upstream (gatewayFindArg args "--upstream" ""))]
          (match (gatewayRunServer! launch port upstream "")
            ((err e) (do (sys/sayErr! e) (ok 1)))
            ((ok _) (ok 0)))))
      ((gatewayCliMode? mode)
        (cli/gatewayCliMain args))
      ((or (= mode "restart") (= mode "update"))
        (match (gatewayRestart! launch args)
          ((err e) (do (sys/sayErr! e) (ok 1)))
          ((ok boundPort)
            (let [(state (resultOr (fileReadString (gatewayStatePath!)) ""))
                  (pid (gatewayNumberAfter state ":pid " 0))
                  (status (if (= mode "update") "updated" "restarted"))]
              (do (sys/say! (str "(:gateway :status :" status " :port " boundPort " :pid " pid ")"))
                (ok 0))))))
      ((stringEmpty? mode)
        (gatewayLegacyStatus! launch (optionOr (stringToInt64 (optionOr (envGet "ASL_GATEWAY_PORT") "8765")) 8765)))
      (else (do (sys/say! (str "(:gateway :status :unsupported :command " mode ")")) (ok 2)))))


fn ! gatewayWaitReady! path: String attempts: Int64 -> (Result Int64 String)
  (if (<= attempts 0) (err "gateway server did not become ready")
    (match (fileReadString path)
      ((err _) (do (processRun "/bin/sleep 0.02") (gatewayWaitReady! path (- attempts 1))))
      ((ok text)
        (match (stringToInt64 (stringTrim text))
          ((none) (do (processRun "/bin/sleep 0.02") (gatewayWaitReady! path (- attempts 1))))
          ((some port) (if (> port 0) (ok port) (err "gateway server published an invalid port")))))))

fn gatewayHostPath! hostResult: (Result String String) -> (Result String String)
  (match hostResult
    ((err e) (err (str "cannot resolve gateway host executable: " e)))
    ((ok host)
      (if (stringEmpty? host)
        (err "resolved gateway host executable path is empty")
        (if (or (not (= (optionOr (stringSlice host 0 1) "") "/")) (not (fileExists? host)))
          (err "resolved gateway host executable path is invalid")
          (if (not (gatewaySafeShellArg? host))
            (err "resolved gateway host executable path contains unsupported shell characters")
            (ok host))))))

fn ! gatewaySelfHost! -> (Result String String)
  (let [(root (optionOr (envGet "ASL_GATEWAY_ROOT") ""))]
    (if (stringEmpty? root) (procExePath) (ok (str root "/bin/asl"))))

fn ! gatewayStart! launch: Launch args: (List String) -> (Result Int64 String)
  (match (gatewayHostPath! (gatewaySelfHost!))
    ((err e) (err e))
    ((ok host) (gatewayStartWithHost! launch args host)))

fn ! gatewayStartWithHost! launch: Launch args: (List String) host: String -> (Result Int64 String)
  (let [(statePath (gatewayStatePath!))
        (readyPath (gatewayReadyPath!))
        (dir (str (optionOr (envGet "HOME") "/tmp") "/.asl/run"))
        (portText (gatewayFindArg args "--port" "0"))
        (port (optionOr (stringToInt64 portText) (- 1)))
        (upstream (gatewayFindArg args "--upstream" ""))
        (root (optionOr (envGet "ASL_GATEWAY_ROOT")
                 (stringTrim (processRun "pwd").stdout)))
        (modulePath (str root "/" launch.module))]
    (if (or (< port 0) (> port 65535)) (err "port must be between 0 and 65535")
      (if (stringEmpty? upstream) (err "gateway start needs --upstream URL")
      (if (or (not (gatewaySafeShellArg? host))
              (or (not (gatewaySafeShellArg? modulePath))
                (or (not (gatewaySafeShellArg? upstream))
                  (or (not (gatewaySafeShellArg? portText)) (not (gatewaySafeShellArg? readyPath))))))
        (err "gateway launch arguments contain unsupported shell characters (host path, module path, --upstream, --port or ready path)")
        (match (dirCreate dir)
          ((err e) (err (str "cannot create gateway state directory: " e)))
          ((ok _)
            (match (fileWrite readyPath "pending")
              ((err e) (err (str "cannot prepare gateway readiness file: " e)))
              ((ok _)
                (let [(launch (processRun (str "/usr/bin/nohup " host " run " modulePath
                                        " serve --port " portText " --upstream " upstream
                                        " --ready " readyPath " >/dev/null 2>&1 & echo $!")))
                      (pid (optionOr (stringToInt64 (stringTrim launch.stdout)) 0))]
                  (if (or (not (= launch.exitCode 0)) (<= pid 1))
                    (err "failed to launch ASL gateway server")
                    (match (gatewayWaitReady! readyPath 250)
                      ((err e) (do (procKill pid "SIGTERM") (err e)))
                      ((ok boundPort)
                        (match (fileWrite statePath
                              (str "(:gateway :status :running :pid " pid " :port " boundPort
                                " :upstream " upstream ")"))
                          ((err e) (do (procKill pid "SIGTERM") (err (str "cannot persist gateway state: " e))))
                          ((ok _) (ok boundPort)))))))))))))))

fn ! gatewayRunServer! launch: Launch port: Int64 upstream: String readyPath: String -> (Result Int64 String)
  (let [(upstreamPort (gatewayUpstreamPort upstream))]
    (if (or (<= upstreamPort 0) (> upstreamPort 65535))
      (err "upstream must be an http URL with an explicit port")
      (match (tcpListen port)
        ((err e) (err (str "gateway listen failed: " e)))
        ((ok listenerFd)
          (match (sockLocalPort listenerFd)
            ((err e) (do (fdClose listenerFd) (err e)))
            ((ok boundPort)
              (gatewayServe! listenerFd upstreamPort launch.families readyPath boundPort)))))))

(enum ConnPhase
  (:c connReading [])
  (:c connHttp [(call u/UpstreamCall) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (slot String) (provider String) (startMs Int64) (model String) (intent String) (tag String) (params ul/CallParams) (profile String)])
  (:c connPool [(requestId Int64) (k (fn [ch/ChatOutcome] -> ch/ChatStep))])
  (:c connWarm [(slot String) (provider String) (request u/UpstreamRequest) (timeout Float64) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (deadlineMs Int64) (model String) (intent String) (tag String) (profile String)])
  ; (:m :tags (retry) :do "a retry backoff wait (effSleepMs) parks here instead of blocking: no fd, just a wall-clock deadline; the reactor resumes it once nowMs! passes deadlineMs, same turn it would otherwise have spent sleeping, so every other connection keeps being served meanwhile")
  (:c connTimer [(deadlineMs Int64) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (tag String)])
  ; (:m :tags (retry) :do "a token-bucket wait (effBucket) parks here instead of blocking, same shape as connTimer: the token is already reserved/debited into srv.buckets at park time (GW-BUCKET-RESERVE), so a second concurrent request for the same model+rpm sees the debit and computes a wait pushed out by another 1/rate, giving N parked requests deadlines spaced ~1/rate apart instead of all waking at once; resume just proceeds (the reservation already happened), no stale-snapshot write-back needed here")
  (:c connBucketWait [(deadlineMs Int64) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (tag String)])
  ; (:m :ref GW-SESSION-BIND :do "a bound CLI turn parks here instead of blocking the reactor: the vendor child runs under fleet/run limits, the reactor polls its pipes with every other connection and steps it each turn, and the continuation resumes when the child has ended")
  (:c connCli [(p bd/BoundPend) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (tag String) (t0 Int64)])
  (:c connProxy [(upstreamFd Int64) (pending String) (response String)])
  (:c connWriting [(data String)])
  (:c connStatusPoll [(call u/UpstreamCall) (budget String)]))

(schema GatewayConn
  (:f fd Int64)
  (:f input String)
  (:f phase ConnPhase))

; (:m latency, served model, intent, the caller tag and the effective request params are known only where the direct HTTP attempt completes (settled!); stashed here and merged into the next effUsageNote row, since that call alone carries alias and outcome)
(schema PendingCall
  (:f intent String)
  (:f model String)
  (:f latencyMs Int64)
  (:f charge Int64)
  (:f tag String)
  (:f params ul/CallParams)
  (:f profile String))

(schema GatewayLoop
  (:f listener Int64)
  (:f upstreamPort Int64)
  (:f env (Map String String))
  (:f home String)
  (:f rootDir String)
  (:f registryPath String)
  (:f promptMaxBytes Int64)
  (:f conns (List GatewayConn))
  (:f pools pd/PoolRegistry)
  (:f replies (List pd/PoolReply))
  (:f breaker b/BreakerState)
  (:f buckets u/BucketRegistry)
  (:f profiles c/ProfilesCache)
  (:f wiring dp/Wiring)
  (:f wiringText (Option String))
  (:f families (List dp/LifecycleFamily))
  (:f outbox (List (Pair Int64 String)))
  (:f pendingCall (Option PendingCall))
  ; (:m :ref GW-SPREAD-LIVE-20261018 :do "live SWRR state: keyed profile|intent, each a (List (Pair String Int64)) alias->current-weight map persisted across calls; spreadLast429 is alias->epoch-ms of its last 429, independent of and in addition to srv.breaker's own per-model trip")
  (:f spreadState (Map String (Map String Int64)))
  (:f spreadLast429 (Map String Int64))
  (:f omni om/OmniState))

fn omniZeroKey -> om/Word64
  (om/Word64 :hi 0 :lo 0)

fn loopOmni srv: GatewayLoop state: om/OmniState -> GatewayLoop
  (with srv :omni state)

fn loopConns srv: GatewayLoop conns: (List GatewayConn) -> GatewayLoop
  (with srv :conns conns)

fn loopPending srv: GatewayLoop pendingCall: (Option PendingCall) -> GatewayLoop
  (with srv :pendingCall pendingCall)

fn loopPools srv: GatewayLoop pools: pd/PoolRegistry replies: (List pd/PoolReply) -> GatewayLoop
  (with srv :pools pools :replies replies)

fn loopState srv: GatewayLoop breaker: b/BreakerState buckets: u/BucketRegistry profiles: c/ProfilesCache -> GatewayLoop
  (with srv :breaker breaker :buckets buckets :profiles profiles)

fn loopSpreadState srv: GatewayLoop spreadState: (Map String (Map String Int64)) spreadLast429: (Map String Int64) -> GatewayLoop
  (with srv :spreadState spreadState :spreadLast429 spreadLast429)

fn loopWiring srv: GatewayLoop wiring: dp/Wiring text: (Option String) -> GatewayLoop
  (with srv :pools (pd/poolWithPlugins srv.pools wiring.plugins) :wiring wiring :wiringText text)

fn addConn srv: GatewayLoop fd: Int64 phase: ConnPhase -> GatewayLoop
  (match phase
    ((connWriting data)
      (if (<= fd (linkFd))
        (with srv :outbox (listAppend srv.outbox (list (pair fd data))))
        (loopConns srv (listAppend srv.conns (list (GatewayConn :fd fd :input "" :phase phase))))))
    (_ (loopConns srv (listAppend srv.conns (list (GatewayConn :fd fd :input "" :phase phase))))))

fn linkFd -> Int64
  -2

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! nowSec! -> Int64
  (/ (nowNs) 1000000000)

fn readyOn? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn reasonPhrase code: Int64 -> String
  (cond
    ((= code 200) "OK") ((= code 400) "Bad Request") ((= code 404) "Not Found") ((= code 401) "Unauthorized") ((= code 429) "Too Many Requests")
    ((= code 500) "Internal Server Error") ((= code 502) "Bad Gateway") ((= code 503) "Service Unavailable")
    ((= code 504) "Gateway Timeout") (else "Status"))

fn renderResponse resp: ch/ChatResponse -> String
  (let [(head resp.head)
        (code (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus n) n) ((ch/headField _ _) acc))) 200 head))
        (fields (fold (fn [(acc (List String)) (h ch/HeadItem)] -> (List String)
                        (match h ((ch/headStatus _) acc) ((ch/headField n v) (listAppend acc (list (str n ": " v "\r\n")))))) (list) head))
        (hasLength (listAny? (fn [(h ch/HeadItem)] -> Bool (match h ((ch/headField n _) (= (stringLower n) "content-length")) ((ch/headStatus _) false))) head))
        (length (if hasLength "" (str "Content-Length: " (stringFromInt64 (stringLength resp.body)) "\r\n")))]
    (str "HTTP/1.1 " (stringFromInt64 code) " " (reasonPhrase code) "\r\n" (stringJoin fields "") length "Connection: close\r\n\r\n" resp.body))

fn errorResponse code: Int64 text: String -> String
  (renderResponse (ch/ChatResponse :head (list (ch/headStatus code) (ch/headField "Content-Type" "application/asn+sexpr"))
                    :body (str "(:error :status " (stringFromInt64 code) " :reason \"" (wire/asnEscape text) "\")\n")))

(schema HttpRequest
  (:f method String)
  (:f path String)
  (:f headers (List (Pair String String)))
  (:f body String))

fn headerPair line: String -> (Option (Pair String String))
  (match (stringIndexOf line ":")
    ((none) none)
    ((some at) (some (pair (stringTrim (optionOr (stringSlice line 0 at) ""))
                           (stringTrim (optionOr (stringSlice line (+ at 1) (stringLength line)) ""))))))

fn contentLength headers: (List (Pair String String)) -> Int64
  (fold (fn [(acc Int64) (h (Pair String String))] -> Int64
          (if (= (stringLower (pairFirst h)) "content-length") (optionOr (stringToInt64 (pairSecond h)) acc) acc))
    0 headers)

fn parseRequest raw: String -> (Option HttpRequest)
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(lines (stringSplit (optionOr (stringSlice raw 0 end) "") "\r\n"))
            (requestLine (stringSplit (optionOr (listHead lines) "") " "))
            (headers (fold (fn [(acc (List (Pair String String))) (l String)] -> (List (Pair String String))
                             (match (headerPair l) ((some h) (listAppend acc (list h))) ((none) acc)))
                       (list) (optionOr (listTail lines) (list))))
            (bodyStart (+ end 4))
            (want (contentLength headers))]
        (if (< (- (stringLength raw) bodyStart) want) none
          (some (HttpRequest :method (optionOr (listGet requestLine 0) "") :path (optionOr (listGet requestLine 1) "")
                  :headers headers :body (optionOr (stringSlice raw bodyStart (+ bodyStart want)) "")))))))

fn chatPath? path: String -> Bool
  (or (stringStartsWith? path "/v1/chat/completions") (stringStartsWith? path "/chat/completions"))

fn failureStatus f: u/UpstreamFailure -> Int64
  (match f ((u/httpFailure status _ _ _) status) (_ 0))

fn failureHeaders f: u/UpstreamFailure -> (List (Pair String String))
  (match f ((u/httpFailure _ _ _ headers) headers) (_ (list)))

fn failureReply f: u/UpstreamFailure -> ch/HttpReply
  (match f
    ((u/httpFailure status reason body headers) (ch/httpError status reason headers body))
    ((u/transportFailure code text) (ch/httpRaised (= code 28) (str "curl exit " (stringFromInt64 code) ": " (stringTrim text))))
    ((u/toolAbsent tool detail) (ch/httpRaised false (str tool ": " detail)))
    ((u/protocolFailure detail) (ch/httpRaised false detail)))

fn poolReplyHttp result: (Result u/UpstreamResponse pd/PoolFailure) -> ch/HttpReply
  (match result
    ((ok resp) (ch/httpOk resp.status (list) resp.body))
    ((err failure)
      (match failure
        ((pd/poolUpstream f) (failureReply f))
        ((pd/poolTimedOut id ms) (ch/httpRaised true (str "ERR_POOL_TIMEOUT: request " (stringFromInt64 id) " waited past requestTimeoutMs " (stringFromInt64 ms))))
        ((pd/poolRejected reason) (ch/httpRaised false (str "ERR_POOL_REJECTED: " reason))))))

fn ! logLine! text: String -> Bool
  (do (eprintln text) true)

fn breakerEvent! st: b/BreakerState event: String pool: String now: Int64 parkSec: Int64 -> b/BreakerState
  (cond
    ((= event "markDown") (b/breakerMarkDownFor st pool now parkSec))
    ((= event "note503") (pairFirst (b/breakerNote503 st pool now)))
    ((= event "reset503") (b/breakerReset503 st pool))
    ((= event "clear") (b/breakerClear st pool))
    (else (do (logLine! (str "(:gateway :breaker :unknownEvent \"" (wire/asnEscape event) "\")")) st)))

fn cliPromptTokens args: (List (Pair String j/Json)) -> Int64
  (match (listFind (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) "prompt")) args)
    ((some p) (match (pairSecond p) ((j/jstr s) (/ (stringLength s) 4)) (_ 0)))
    ((none) 0))

; (:m :ref GW-BALANCER-CLI-WIRE :do "a vendor CLI run asks the balancer first: poolPickLanes over the cli lane, refused means the run is skipped (none, so chat fails over to the next candidate), picked charges the picked alias with the prompt-size estimate at admission so concurrent runs pace each other; no pool, or a pool with no cli lane, admits every run")
fn cliAliasesFor pool: bl/Pool client: String -> (List String)
  (filter (fn [(id String)] -> Bool (and (= (bl/laneOf pool id) "cli") (match (bl/poolTarget pool id) ((some t) (= (pairFirst t) client)) ((none) false)))) (mapKeys pool.lanes))

fn balOnly bal: bl/Balancer ids: (List String) -> bl/Balancer
  (with bal :models (filter (fn [(m bl/PoolModel)] -> Bool (listContains? ids m.id)) bal.models))

fn poolWithBal pool: bl/Pool bal: bl/Balancer -> bl/Pool
  (with pool :bal bal)

fn poolOnly pool: bl/Pool ids: (List String) -> bl/Pool
  (poolWithBal pool (balOnly pool.bal ids))

fn ! cliAdmit! srv: GatewayLoop client: String args: (List (Pair String j/Json)) -> (Pair GatewayLoop Bool)
  (match srv.wiring.pool
    ((none) (pair srv true))
    ((some pool)
      (if (listEmpty? (cliAliasesFor pool client))
        (pair srv true)
        (let [(now (nowMs!))
              (tokens (cliPromptTokens args))
              (intent (match srv.pendingCall ((some x) x.intent) ((none) "")))]
          (match (bl/poolPickLanes (poolOnly pool (cliAliasesFor pool client)) (bl/poolRequest pool intent now tokens) (list "cli"))
            ((bl/refused reason) (do (logLine! (str "(:gateway :cli :refused \"" (wire/asnEscape reason) "\")")) (pair srv false)))
            ((bl/picked id _ _ _) (pair (loopWiring srv (wiringPool srv.wiring (some (bl/poolCharge pool id now tokens))) srv.wiringText) true)))))))

fn ! cliRunSync! srv: GatewayLoop client: String args: (List (Pair String j/Json)) -> (Pair GatewayLoop ch/ChatOutcome)
  (let [(sctx (ses/sessCtxAt! srv.home (envList)))]
    (if (bd/boundCliEligible? sctx client args)
      (pair srv (ch/outCli (bd/boundCliEffect! sctx client args)))
      (do (logLine! (str "(:gateway :cli :unavailable \"" (wire/asnEscape client) "\" :entry http)")) (pair srv (ch/outCli none)))))

fn ! runEffect! srv: GatewayLoop eff: ch/ChatEffect -> (Pair GatewayLoop ch/ChatOutcome)
  (match eff
    ((ch/effRealpath p) (pair srv (ch/outPath (resultOr (realPath p) p))))
    ((ch/effIsDir p) (pair srv (ch/outBool (match (fileStat p) ((ok st) st.isDir) ((err _) false)))))
    ((ch/effClock) (pair srv (ch/outFloat (/ (int64ToFloat64 (nowNs)) 1000000000.0))))
    ((ch/effBreakerDown pool)
      (let [(r (b/breakerDownFor srv.breaker pool (nowSec!)))]
        (pair (loopState srv (pairFirst r) srv.buckets srv.profiles) (ch/outFloat (int64ToFloat64 (pairSecond r))))))
    ((ch/effBreakerDownAll pools)
      (let [(now (nowSec!))
            (r (fold (fn [(acc (Pair b/BreakerState (List Float64))) (pool String)] -> (Pair b/BreakerState (List Float64))
                       (let [(d (b/breakerDownFor (pairFirst acc) pool now))]
                         (pair (pairFirst d) (listAppend (pairSecond acc) (list (int64ToFloat64 (pairSecond d)))))))
                 (pair srv.breaker (list)) pools))]
        (pair (loopState srv (pairFirst r) srv.buckets srv.profiles) (ch/outFloats (pairSecond r)))))
    ((ch/effBreakerEvent event pool parkSec)
      (pair (loopState srv (breakerEvent! srv.breaker event pool (nowSec!) parkSec) srv.buckets srv.profiles) ch/outDone))
    ((ch/effUsageNote p a o usage)
      (let [(pc srv.pendingCall)
            ; (:m :ref GW-BALANCER-ALIAS :do "after a balancer dispatch the row names the pool alias the settle charged, so two pool aliases on one upstream model stay apart; any other row keeps the chat alias")
            (alias (match pc ((some _) (optionOr srv.wiring.settledAlias a)) ((none) a)))
            (tokens (g/usageTokens usage))
            (params (match pc ((some x) x.params) ((none) (ul/defaultCallParams))))
            (row (ul/CallRow :atMs (/ (nowNs) 1000000) :profile (match pc ((some x) x.profile) ((none) "")) :intent (match pc ((some x) x.intent) ((none) "")) :alias alias :provider p
                   :model (match pc ((some x) x.model) ((none) "")) :inTokens (optionOr (listGet tokens 0) 0)
                   :cachedTokens (optionOr (listGet tokens 1) 0) :outTokens (optionOr (listGet tokens 2) 0)
                   :reasoningTokens (optionOr (listGet tokens 3) 0)
                   :ttftMs none :ms (match pc ((some x) (some x.latencyMs)) ((none) none)) :outcome o
                   :charge (match pc ((some x) x.charge) ((none) 0))
                   :tag (match pc ((some x) (if (stringEmpty? x.tag) none (some x.tag))) ((none) none))
                   :temperature params.temperature :topP params.topP :maxTokens params.maxTokens :effort params.effort
                   :api params.api :stream params.stream :toolCount params.toolCount :promptBytes params.promptBytes :sysHash params.sysHash))
            (ledgerPath (optionOr (match srv.wiringText ((some t) (c/gatewayLedgerPathOverride t)) ((none) none)) (ul/defaultLedgerPath srv.home)))
            (wrote (ul/appendCallRow! ledgerPath row))
            ; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "written in addition to, never instead of, the stats ledger above: GW-STATS's per-HOME ledgerPath keeps serving its own calibration/--by queries unchanged, this is the separate shared ledger (default outside scratch homes once the operator sets :sharedUsagePath, see gatewaySharedUsagePathOverride) that a scratch HOME's deletion cannot take with it")
            (sharedPath (optionOr (match srv.wiringText ((some t) (c/gatewaySharedUsagePathOverride t)) ((none) none)) (ul/defaultSharedUsagePath srv.home)))
            (wroteShared (if (= sharedPath ledgerPath) (ok true) (ul/appendCallRow! sharedPath row)))]
        (do (match wrote ((ok _) true) ((err e) (logLine! (str "(:gateway :statsLedger :error \"" (wire/asnEscape e) "\")"))))
          (do (match wroteShared ((ok _) true) ((err e) (logLine! (str "(:gateway :sharedUsageLedger :error \"" (wire/asnEscape e) "\")"))))
            (do (logLine! (str "(:gateway :usage :provider \"" (wire/asnEscape p) "\" :alias \"" (wire/asnEscape alias) "\" :outcome \"" (wire/asnEscape o) "\")"))
              (pair (loopPending (with srv :wiring (dp/settledConsumed srv.wiring)) none) ch/outDone))))))
    ((ch/effUsageFallback p a)
      (do (logLine! (str "(:gateway :fallback :provider \"" (wire/asnEscape p) "\" :alias \"" (wire/asnEscape a) "\")")) (pair srv ch/outDone)))
    ; (:m :ref GW-SPREAD-LIVE-20261018 :do "the only place rt/spreadOrder is ever called: real per-profile+intent state read from and written back to srv.spreadState, real wall clock, real breaker availability via srv.breaker keyed by the pool the caller resolved per alias -- chat.asl and router.asl both stay clock/breaker-free")
    ; (:m :ref SUBPACE :do "pacing hook below: subscription factors come from the cache the spread state keeps under paceCacheKey, refreshed from subscriptions.asn and the shared ledger at most once a minute; a member whose subscription is over its hard pace leaves the spread and so falls behind the rest of the chain")
    ((ch/effSpreadOrder profile intent spread cooldownSec pools)
      (let [(key (str profile "|" intent))
            (state (match (mapGet srv.spreadState key) ((some s) s) ((none) (rt/spreadSeedState spread (nowNs)))))
            (now (/ (nowNs) 1000000))
            (poolMap (mapFromPairs pools))
            (breakerOpen? (fn [(alias String)] -> Bool
                            (let [(pk (optionOr (mapGet poolMap alias) ""))]
                              (if (stringEmpty? pk) false (> (pairSecond (b/breakerDownFor srv.breaker pk (nowSec!))) 0)))))
            (cached (optionOr (mapGet srv.spreadState (spc/paceCacheKey)) (mapEmpty)))
            (factors (if (spc/paceCacheFresh? cached now) cached
                       (subsr/paceFactors! srv.home (optionOr (match srv.wiringText ((some t) (c/gatewaySharedUsagePathOverride t)) ((none) none)) (ul/defaultSharedUsagePath srv.home)) now)))
            (paced (spc/adjustSpread factors pools spread))
            (stepped (rt/spreadOrder now cooldownSec paced srv.spreadLast429 breakerOpen? state))
            (order (pairFirst stepped))
            (nextState (pairSecond stepped))]
        (pair (loopSpreadState srv (mapSet (mapSet srv.spreadState key nextState) (spc/paceCacheKey) factors) srv.spreadLast429) (ch/outStrings order))))
    ((ch/effSpreadNote429 alias)
      (pair (loopSpreadState srv srv.spreadState (mapSet srv.spreadLast429 alias (/ (nowNs) 1000000))) ch/outDone))
    ((ch/effTelemetry rec)
      (do (match rec ((some r) (logLine! r)) ((none) true)) (pair srv ch/outDone)))
    ((ch/effNoteIntent i)
      (do (logLine! (str "(:gateway :unknownIntent \"" (wire/asnEscape i) "\")")) (pair srv ch/outDone)))
    ((ch/effLog text) (do (logLine! (stringTrim text)) (pair srv ch/outDone)))
    ; (:m :tags (retry) :do "unreachable from the reactor: drive! matches ch/effBucket itself and parks a connBucketWait instead of calling the blocking geminiAcquire! below; this fallback only serves a caller that invokes runEffect! directly outside drive! (e.g. a test), where there is no reactor turn to protect")
    ((ch/effBucket model rpm timeout)
      (let [(r (u/geminiAcquire! srv.buckets model rpm timeout))]
        (pair (loopState srv srv.breaker (pairFirst r) srv.profiles) (ch/outBool (resultOr (pairSecond r) false)))))
    ; (:m :tags (retry) :do "unreachable from the reactor: drive! matches ch/effSleepMs itself and parks a connTimer instead of calling runEffect!; this blocking fallback only serves a caller that invokes runEffect! directly outside drive! (e.g. a test), where there is no reactor turn to protect")
    ((ch/effSleepMs ms) (do (sleepMs (max 0 ms)) (pair srv ch/outDone)))
    ((ch/effCli client args)
      (let [(adm (cliAdmit! srv client args))]
        (if (pairSecond adm) (cliRunSync! (pairFirst adm) client args) (pair (pairFirst adm) (ch/outCli none)))))
    ((ch/effHttp _ _ _ _ _ _ _) (pair srv (ch/outHttp (ch/httpRaised false "an HTTP effect reached the synchronous effect runner"))))
    ((ch/effPoolHttp _ _ _ _ _ _) (pair srv (ch/outHttp (ch/httpRaised false "a pool effect reached the synchronous effect runner")))))

fn ! drive! srv: GatewayLoop fd: Int64 tag: String step: ch/ChatStep -> GatewayLoop
  (match step
    ((ch/stepDone resp) (addConn srv fd (connWriting (renderResponse resp))))
    ((ch/stepRaised kind message) (addConn srv fd (connWriting (errorResponse 500 (str kind ": " message)))))
    ((ch/stepEffect eff k)
      (match eff
        ((ch/effHttp provider model intent role request timeout profile)
          (dispatchHttp! srv fd tag (dp/RouteHint :provider provider :model model :intent intent :role role
                                  :promptTokens (/ (stringLength request.data) 4)) request timeout k profile))
        ((ch/effPoolHttp provider model base pool request timeout)
          (let [(sub (pd/poolSubmit! srv.pools provider model base pool request timeout srv.env (nowMs!)))
                (out (pairSecond sub))]
            (addConn (loopPools srv out.registry (listAppend srv.replies out.replies)) fd (connPool (pairFirst sub) k))))
        ; (:m :tags (retry) :do "park, don't block: effSleepMs never reaches runEffect!'s own (blocking) case from here, so a retry backoff never stalls the single-threaded reactor for any other connection")
        ((ch/effSleepMs ms) (addConn srv fd (connTimer (+ (nowMs!) ms) k tag)))
        ; (:m :tags (retry) :do "park, don't block, same as effSleepMs: tokenBucketBegin is pure and cheap, so it always runs synchronously now (committing the refilled bucket state immediately). GW-BUCKET-RESERVE: on an actual bucketWait, the token is debited now too (takeToken on the already-under-1.0 bucket, going negative -- a reservation, not an acquisition), so the NEXT concurrent request for this same model+rpm reads that debit and computes a wait pushed out by another 1/rate, spacing parked requests instead of letting them all wake at the same instant and over-acquire")
        ((ch/effBucket model rpm timeout)
          (let [(got (u/geminiBucket srv.buckets model rpm (u/wallSeconds!)))
                (begun (u/tokenBucketBegin (pairSecond got) timeout (u/wallSeconds!)))
                (b1 (pairFirst begun))]
            (match (pairSecond begun)
              ((err _) (drive! (loopState srv srv.breaker (u/bucketRegistryPut (pairFirst got) model rpm b1) srv.profiles) fd tag (k (ch/outBool false))))
              ((ok s)
               (match s
                 ((u/bucketAcquired) (drive! (loopState srv srv.breaker (u/bucketRegistryPut (pairFirst got) model rpm b1) srv.profiles) fd tag (k (ch/outBool true))))
                 ((u/bucketRefused) (drive! (loopState srv srv.breaker (u/bucketRegistryPut (pairFirst got) model rpm b1) srv.profiles) fd tag (k (ch/outBool false))))
                 ((u/bucketWait secs)
                  (addConn (loopState srv srv.breaker (u/bucketRegistryPut (pairFirst got) model rpm (u/takeToken b1)) srv.profiles) fd
                    (connBucketWait (+ (nowMs!) (u/ceilMs secs)) k tag))))))))
        ((ch/effCli client args)
          (let [(adm (cliAdmit! srv client args))
                (srv2 (pairFirst adm))
                (sctx (ses/sessCtxAt! srv2.home (envList)))]
            (cond
              ((not (pairSecond adm)) (drive! srv2 fd tag (k (ch/outCli none))))
              ((bd/boundCliEligible? sctx client args)
                (match (bd/boundCliBegin! sctx client args)
                  ((bd/boundCliNow r) (drive! srv2 fd tag (k (ch/outCli r))))
                  ((bd/boundCliRunning p) (addConn srv2 fd (connCli p k tag (monotonicNs))))))
              (else (let [(r (cliRunSync! srv2 client args))] (drive! (pairFirst r) fd tag (k (pairSecond r))))))))
        (_ (let [(r (runEffect! srv eff))] (drive! (pairFirst r) fd tag (k (pairSecond r))))))))

fn errorOutcome status: Int64 reason: String -> ch/ChatOutcome
  (ch/outHttp (ch/httpError status reason (list (pair (ch/gatewayOriginHeader) "gateway")) (str "{\"error\": \"" (wire/asnEscape reason) "\"}")))

fn jsonFloatOf v: (Option j/Json) -> (Option Float64)
  (match v ((none) none) ((some jv) (match jv ((j/jint i) (some (int64ToFloat64 i))) ((j/jfloat f) (some f)) ((j/jnum n) (some n)) (_ none))))

fn jsonIntOf v: (Option j/Json) -> (Option Int64)
  (match v ((none) none) ((some jv) (match jv ((j/jint i) (some i)) ((j/jfloat f) (float64ToInt64 f)) ((j/jnum n) (float64ToInt64 n)) (_ none))))

fn jsonStrOf v: (Option j/Json) -> (Option String)
  (match v ((none) none) ((some jv) (match jv ((j/jstr s) (some s)) (_ none))))

fn jsonBoolOf v: (Option j/Json) d: Bool -> Bool
  (match v ((none) d) ((some jv) (match jv ((j/jbool b) b) (_ d))))

fn jsonArrOf v: (Option j/Json) -> (List j/Json)
  (match v ((none) (list)) ((some jv) (match jv ((j/jarr xs) xs) (_ (list)))))

fn apiKindOf url: String -> String
  (cond
    ((stringEndsWith? url "/responses") "responses")
    ((stringEndsWith? url "/messages") "messages")
    ((stringEndsWith? url ":generateContent") "generateContent")
    (else "chat"))

; (:m a short, non-reversible fingerprint of the system prefix, to see prefix-cache reuse across calls without storing the prefix text itself)
fn systemPrefixHash messages: (List j/Json) -> String
  (match (listHead messages)
    ((none) "")
    ((some first)
     (if (= (optionOr (jsonStrOf (j/jsonGet first "role")) "") "system")
       (match (jsonStrOf (j/jsonGet first "content"))
         ((none) "")
         ((some content) (optionOr (stringSlice (bytesSha256 (stringToBytes content)) 0 16) "")))
       "")))

; (:m the effective request parameters as actually sent, read back out of sent.data rather than re-derived from config, so a parameter the provider ignores is still recorded as sent, not guessed; on an unparseable body this is honestly the api kind alone with every other field defaulted, not a guess at what was meant)
fn paramsFromRequest sent: u/UpstreamRequest -> ul/CallParams
  (match (j/jsonParse sent.data)
    ((err _) (with (ul/defaultCallParams) :api (apiKindOf sent.url)))
    ((ok body)
     (let [(messages (jsonArrOf (j/jsonGet body "messages")))
           (effortDirect (jsonStrOf (j/jsonGet body "effort")))
           (effort (match effortDirect ((some s) (some s)) ((none) (jsonStrOf (j/jsonGet body "reasoning_effort")))))]
       (ul/CallParams
         :temperature (jsonFloatOf (j/jsonGet body "temperature"))
         :topP (jsonFloatOf (j/jsonGet body "top_p"))
         :maxTokens (jsonIntOf (j/jsonGet body "max_tokens"))
         :effort effort
         :api (apiKindOf sent.url)
         :stream (jsonBoolOf (j/jsonGet body "stream") false)
         :toolCount (listLength (jsonArrOf (j/jsonGet body "tools")))
         :promptBytes (stringLength (j/jsonEmit (j/jarr messages)))
         :sysHash (systemPrefixHash messages)))))

; (:m :ref GW-BUDGET-ENFORCE-20261018 :do "no budget row for this profile (none configured, or profile empty on an unprofiled/passthrough dispatch) means allow, same as absent ever meant; a configured cap compares against today's shared-ledger total for that exact profile (profileTokensToday), never a cross-profile or cross-day figure, so one profile's dispatches never throttle another's")
fn ! budgetRefusal! srv: GatewayLoop profile: String -> (Option String)
  (if (stringEmpty? profile) none
    (let [(text (optionOr srv.wiringText ""))]
      (match (c/gatewayDailyTokenBudget text profile)
        ((none) none)
        ((some cap)
          (let [(sharedPath (optionOr (c/gatewaySharedUsagePathOverride text) (ul/defaultSharedUsagePath srv.home)))
                (rows (resultOr (ul/readRows! sharedPath) (list)))
                (day (ul/dayKeyOf (/ (nowNs) 1000000)))
                (total (ul/profileTokensToday rows day profile))]
            (if (>= total cap)
              (some (str "profile " profile " is over its daily token budget (" (stringFromInt64 total) "/" (stringFromInt64 cap) " tokens today)"))
              none))))))

fn ! dispatchHttp! srv: GatewayLoop fd: Int64 tag: String hint: dp/RouteHint request: u/UpstreamRequest timeout: Float64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) profile: String -> GatewayLoop
  (match (budgetRefusal! srv profile)
    ((some reason) (do (logLine! (str "(:gateway :budget :profile \"" (wire/asnEscape profile) "\" :result refused :reason \"" (wire/asnEscape reason) "\")")) (drive! srv fd tag (k (errorOutcome 429 reason)))))
    ((none)
      (let [(w srv.wiring)
            (reserved (dp/planReserving w hint request srv.env (nowMs!)))
            (planned (pairFirst reserved))]
        (match planned
          ((dp/planReject status reason row)
            (do (logLine! (dp/decisionText row))
              (drive! srv fd tag (k (errorOutcome status reason)))))
          ((dp/planSend slot provider sent row)
            (do (logLine! (dp/decisionText row))
              (sendPlanned! (loopWiring srv (pairSecond reserved) srv.wiringText) fd tag slot provider sent (dp/sendTimeout w hint provider timeout) (servedModelK w slot hint k) hint.model hint.intent profile)))
          ((dp/planWait slot provider sent row cold deadline)
            (do (logLine! (dp/decisionText row))
              (if cold
                (match (dp/startSlot! w slot (nowMs!) deadline)
                  ((dp/startRefused status reason line) (do (logLine! line) (drive! srv fd tag (k (errorOutcome status reason)))))
                  ((dp/startOk next line) (do (logLine! line) (addConn (loopWiring srv next srv.wiringText) fd (connWarm slot provider sent (dp/sendTimeout w hint provider timeout) k deadline hint.model hint.intent tag profile)))))
                (addConn (loopWiring srv (dp/waiting w slot) srv.wiringText) fd (connWarm slot provider sent (dp/sendTimeout w hint provider timeout) k deadline hint.model hint.intent tag profile)))))))))

; (:m :ref GW-SERVED-MODEL-HEADER :do "when the planned slot is not the model the caller asked for, the client reply carries x-asl-served-model: <alias>/<upstream model> so a substituted pick is visible")
fn servedModelK w: dp/Wiring slot: String hint: dp/RouteHint k: (fn [ch/ChatOutcome] -> ch/ChatStep) -> (fn [ch/ChatOutcome] -> ch/ChatStep)
  (match (match w.pool ((some pool) (bl/poolTarget pool slot)) ((none) none))
    ((none) k)
    ((some t)
      (if (and (= (pairFirst t) hint.provider) (= (pairSecond t) hint.model)) k
        (fn [(o ch/ChatOutcome)] -> ch/ChatStep (k (withServedModel o (str slot "/" (pairSecond t))))))))

fn withServedModel o: ch/ChatOutcome label: String -> ch/ChatOutcome
  (match o
    ((ch/outHttp (ch/httpOk status headers body)) (ch/outHttp (ch/httpOk status (listAppend headers (list (pair "x-asl-served-model" label))) body)))
    (_ o))

fn ! sendPlanned! srv: GatewayLoop fd: Int64 tag: String slot: String provider: String sent: u/UpstreamRequest timeout: Float64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) model: String intent: String profile: String -> GatewayLoop
  (let [(w srv.wiring)
        (params (paramsFromRequest sent))]
    (match (p/sendHttp! w.plugins provider sent srv.env timeout)
      ((err f) (drive! (settled! srv slot provider intent model tag params "" 0 false profile (failureStatus f) (failureHeaders f)) fd tag (k (ch/outHttp (failureReply f)))))
      ((ok call) (addConn (loopWiring srv (dp/started w slot) srv.wiringText) fd (connHttp call k slot provider (nowMs!) model intent tag params profile)))))

fn ! stepWarm! srv: GatewayLoop conn: GatewayConn tag: String slot: String provider: String sent: u/UpstreamRequest timeout: Float64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) deadline: Int64 model: String intent: String profile: String -> GatewayLoop
  (let [(now (nowMs!))]
    (match (dp/slotReady srv.wiring slot now)
      ((dp/readyNow) (sendPlanned! srv conn.fd tag slot provider sent timeout k model intent profile))
      ((dp/readyGone reason) (drive! srv conn.fd tag (k (errorOutcome 503 reason))))
      ((dp/readyLater)
        (if (> now deadline)
          (do (logLine! (str "(:gateway :lifecycle :op wait :endpoint \"" slot "\" :result timeout)"))
            (drive! srv conn.fd tag (k (errorOutcome 503 (str "endpoint " slot " did not warm within coldStartMs")))))
          (loopConns srv (listAppend srv.conns (list conn)))))))

fn ! settled! srv: GatewayLoop slot: String provider: String intent: String model: String tag: String params: ul/CallParams body: String startMs: Int64 success: Bool profile: String status: Int64 headers: (List (Pair String String)) -> GatewayLoop
  (if (stringEmpty? slot) srv
    (let [(now (nowMs!))
          (latencyMs (if (> startMs 0) (- now startMs) 1))
          (total (dp/usageTokens body))
          (out (dp/settle srv.wiring slot provider total latencyMs success now))
          (srv1 (loopWiring srv (dp/observeReply (pairFirst out) slot status headers now) srv.wiringText))
          (served (dp/servedModel body model))
          (charge (/ (* (max 0 total) (dp/priceFor srv1.wiring slot)) 1000000))
          (pending (PendingCall :intent intent :model served :latencyMs latencyMs :charge charge :tag tag :params params :profile profile))]
      (do (logLine! (pairSecond out)) (loopPending srv1 (some pending)))))

; (:m :ref GW-KEYFILES-WIRED :do "the loop env itself carries the key-file values, so dispatch retargeting, the wiring and the balancer status polls read the same keys chat does")
fn loopEnv srv: GatewayLoop env: (Map String String) -> GatewayLoop
  (with srv :env env)

fn ! chatWorld! srv: GatewayLoop -> (Pair GatewayLoop (Result ch/ChatWorld String))
  (let [(loaded (c/gatewayProfilesLoad! srv.profiles srv.home srv.registryPath))
        (srv0 (loopState srv srv.breaker srv.buckets (pairFirst loaded)))
        (srv1 (loopEnv srv0 (keyFilesWorldEnv! (pairSecond loaded) srv0.env)))]
    (match (u/upstreamSettings srv1.env)
      ((err e) (pair srv1 (err e)))
      ((ok settings) (pair (wired! srv1 (pairSecond loaded) settings) (ok (ch/ChatWorld :env srv1.env :rootDir srv.rootDir :settings settings
                                      :agyPromptMaxBytes srv.promptMaxBytes :table (pairSecond loaded)))))))

; (:m :ref GW-KEYFILES-SEND :do "a provider key held only in a (:gateway :keyFiles) file reaches the provider call: the world env the chat effects read is the process env overlaid, per provider row with a keyEnv, by the key file value, the file winning as GW-KEYSTORE-20261019 orders it; values are never logged")
fn ! keyFilesWorldEnv! table: (Result c/GatewayTable String) env: (Map String String) -> (Map String String)
  (match table
    ((err _) env)
    ((ok t)
      (fold (fn [(acc (Map String String)) (pv c/GatewayProvider)] -> (Map String String)
              (if (stringEmpty? pv.keyEnv) acc
                (match (c/keyFileLookup! t.keyFiles pv.keyEnv) ((some v) (mapSet acc pv.keyEnv v)) ((none) acc))))
        env (mapValues t.providers))))

fn ! wired! srv: GatewayLoop table: (Result c/GatewayTable String) settings: u/UpstreamSettings -> GatewayLoop
  (let [(path (c/gatewayProfilesPath srv.home))
        (text (if (fileExists? path) (resultOr (fileReadString path) "") ""))
        (tableOpt (match table ((ok t) (some t)) ((err _) none)))]
    (if (= srv.wiringText (some text)) srv
      (match (dp/wiringFromConfig tableOpt text settings srv.env srv.families)
        ((ok w) (loopWiring srv (dp/carrySpend srv.wiring w) (some text)))
        ((err e) (do (logLine! (str "(:gateway :wiring :error \"" (wire/asnEscape e) "\")"))
                   (loopWiring srv (dp/emptyWiring settings) (some text)))))))

; (:m a provider that declares :sessionHeader (e.g. OpenCode's x-opencode-session) rejects a call with no session id at all; withSessionHeader only maps a caller-supplied X-ASL-Session onto it, so a caller that never sends one still needs a value here, not a MissingSessionID failure; this fallback is per-run, not truly session-scoped, but it is non-empty and stable for the lifetime of this one request)
fn sessionFallbackId fd: Int64 nowMs: Int64 -> String
  (str "asl-run-" (stringFromInt64 fd) "-" (stringFromInt64 nowMs))

; (:m ensures request.headers carries an X-ASL-Session value: a caller-supplied one is left exactly as sent, never overwritten; an absent one is filled with a per-run fallback, so a provider's :sessionHeader always has something to map onto; serverTest.asl's testEnsureSessionHeader covers both branches)
fn ensureSessionHeader headers: (List (Pair String String)) fd: Int64 nowMs: Int64 -> (List (Pair String String))
  (let [(existing (c/headerGet headers "X-ASL-Session"))]
    (if (stringEmpty? existing) (u/headerPut headers "X-ASL-Session" (sessionFallbackId fd nowMs)) headers))

; (:m :ref GW-FEDERATION-20261027 :do "when the secrets file holds a gatewayServeToken every request must carry it as a bearer, else a 401 before any routing: the host gateway that serves the VPS over the tunnel is never open on its port; without that secret the gateway behaves as before")
; (:m :ref GW-SERVE-AUTH-HEALTH-EXEMPT :do "GET /health answers without a bearer so a tunnel keeper or a load check can see the gateway is up; it returns a fixed status row and nothing about providers, models, budgets or keys, every other path still needs the bearer")
fn ! dispatch! srv: GatewayLoop fd: Int64 raw: String request: HttpRequest -> GatewayLoop
  (if (and (= request.method "GET") (= request.path "/health"))
    (addConn srv fd (connWriting (renderResponse (ch/ChatResponse :head (list (ch/headStatus 200) (ch/headField "Content-Type" "application/asn+sexpr")) :body "(:health :status ok)\n"))))
    (dispatchGuarded! srv fd raw request))

fn ! dispatchGuarded! srv: GatewayLoop fd: Int64 raw: String request: HttpRequest -> GatewayLoop
  (match (fed/serveAuthError srv.env request.headers)
    ((some e) (addConn srv fd (connWriting (errorResponse 401 e))))
    ((none) (dispatchAuthed! srv fd raw request)))

fn ! dispatchAuthed! srv: GatewayLoop fd: Int64 raw: String request: HttpRequest -> GatewayLoop
  (if (and (= request.method "POST") (chatPath? request.path))
    (let [(w (chatWorld! srv))
          (tag (c/headerGet request.headers "X-ASL-Tag"))
          (headersWithSession (ensureSessionHeader request.headers fd (nowMs!)))]
      (match (pairSecond w)
        ((err e) (addConn (pairFirst w) fd (connWriting (errorResponse 500 e))))
        ((ok world) (drive! (pairFirst w) fd tag (ch/chatStart! (ch/ChatRequest :path request.path :headers headersWithSession :body request.body) world)))))
    (match (omniRoute! srv fd request)
      ((some next) next)
      ((none)
        (match (tcpConnect srv.upstreamPort)
          ((err e) (addConn srv fd (connWriting (errorResponse 502 (str "upstream connect failed: " e)))))
          ((ok upstreamFd) (addConn srv fd (connProxy upstreamFd (if (fed/serveAuthOn? srv.env) (fed/withoutAuthorization raw) raw) "")))))))

; (:m :ref MAINFIX10 :do "omniApi.asl implemented every /api/asl/ route (browser target+extension registration and poll, project/channel sync ingest) but was never imported outside itself, so every /api/asl/ request fell through to the generic proxy and 502'd against whatever --upstream happened to be. omniRoute! handles only paths omniDispatch itself recognizes under /api/asl/, returning none for anything else (including every non-/api/asl path) so the existing fallback arm's proxy call is unchanged for everything this does not claim")
fn ! omniRoute! srv: GatewayLoop fd: Int64 request: HttpRequest -> (Option GatewayLoop)
  (if (not (stringStartsWith? request.path "/api/asl/")) none
    (match (om/omniDispatch srv.omni request.method request.path request.body (nowMs!))
      ((none) none)
      ((some (ok reply)) (some (addConn (loopOmni srv reply.state) fd (connWriting (h/formatHttpResponse reply.response)))))
      ((some (err e)) (some (addConn srv fd (connWriting (errorResponse 502 (str "omni dispatch failed: " e))))))))

fn ! closeConn! conn: GatewayConn -> Bool
  (do (fdClose conn.fd) true)

fn ! stepReading! srv: GatewayLoop conn: GatewayConn ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (if (not (readyOn? ready conn.fd)) (loopConns srv (listAppend srv.conns (list conn)))
    (match (fdRead conn.fd 65536)
      ((err e) (if (= e "wouldBlock") (loopConns srv (listAppend srv.conns (list conn))) (do (closeConn! conn) srv)))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (closeConn! conn) srv)
          (let [(input (str conn.input chunk))]
            (match (parseRequest input)
              ((none) (loopConns srv (listAppend srv.conns (list (with conn :input input :phase connReading)))))
              ((some request) (dispatch! srv conn.fd input request))))))))

fn ! stepProxy! srv: GatewayLoop conn: GatewayConn upstreamFd: Int64 pending: String response: String ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (let [(keep (fn [(p String) (r String)] -> GatewayLoop
                (loopConns srv (listAppend srv.conns (list (with conn :input "" :phase (connProxy upstreamFd p r)))))))]
    (if (not (readyOn? ready upstreamFd)) (keep pending response)
      (if (not (stringEmpty? pending))
        (match (fdWrite upstreamFd pending)
          ((err e) (do (fdClose upstreamFd) (addConn srv conn.fd (connWriting (errorResponse 502 (str "upstream write failed: " e))))))
          ((ok n) (keep (optionOr (stringSlice pending n (stringLength pending)) "") response)))
        (match (fdRead upstreamFd 65536)
          ((err e) (do (fdClose upstreamFd) (addConn srv conn.fd (connWriting (errorResponse 502 (str "upstream read failed: " e))))))
          ((ok chunk)
            (if (stringEmpty? chunk)
              (do (fdClose upstreamFd) (addConn srv conn.fd (connWriting response)))
              (keep pending (str response chunk))))))))

fn ! stepWriting! srv: GatewayLoop conn: GatewayConn data: String ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (if (not (readyOn? ready conn.fd)) (loopConns srv (listAppend srv.conns (list conn)))
    (match (fdWrite conn.fd data)
      ((err e) (if (= e "wouldBlock") (loopConns srv (listAppend srv.conns (list conn))) (do (closeConn! conn) srv)))
      ((ok n)
        (let [(rest (optionOr (stringSlice data n (stringLength data)) ""))]
          (if (stringEmpty? rest) (do (closeConn! conn) srv)
            (addConn srv conn.fd (connWriting rest)))))))

fn ! stepHttp! srv: GatewayLoop conn: GatewayConn tag: String call: u/UpstreamCall k: (fn [ch/ChatOutcome] -> ch/ChatStep) slot: String provider: String startMs: Int64 model: String intent: String params: ul/CallParams profile: String ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (match (u/upstreamCallPump! call ready)
    ((err f) (drive! (settled! srv slot provider intent model tag params "" startMs false profile (failureStatus f) (failureHeaders f)) conn.fd tag (k (ch/outHttp (failureReply f)))))
    ((ok next)
      (if (u/upstreamCallOpen? next) (addConn srv conn.fd (connHttp next k slot provider startMs model intent tag params profile))
        (match (u/upstreamCallFinish! next)
          ((ok resp) (drive! (settled! srv slot provider intent model tag params resp.body startMs true profile resp.status resp.headers) conn.fd tag (k (ch/outHttp (ch/httpOk resp.status (list) resp.body)))))
          ((err f) (drive! (settled! srv slot provider intent model tag params "" startMs false profile (failureStatus f) (failureHeaders f)) conn.fd tag (k (ch/outHttp (failureReply f)))))))))

; (:m :tags (retry) :do "resumes once the wall clock passes deadlineMs, same as any other conn this turn; otherwise re-parks for the next poll, exactly like stepWarm!'s coldStart wait")
fn ! stepTimer! srv: GatewayLoop conn: GatewayConn deadlineMs: Int64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) tag: String -> GatewayLoop
  (if (>= (nowMs!) deadlineMs)
    (drive! srv conn.fd tag (k ch/outDone))
    (loopConns srv (listAppend srv.conns (list conn))))

; (:m :tags (retry) :do "GW-BUCKET-RESERVE: the token was already debited into srv.buckets at park time (drive!'s bucketWait case), so resuming needs no bucket math and no write-back of a now-stale snapshot -- just proceed once the monotonic deadline passes, same shape as stepTimer!")
fn ! stepBucketWait! srv: GatewayLoop conn: GatewayConn deadlineMs: Int64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) tag: String -> GatewayLoop
  (if (>= (nowMs!) deadlineMs)
    (drive! srv conn.fd tag (k (ch/outBool true)))
    (loopConns srv (listAppend srv.conns (list conn))))

; (:m :ref GW-SESSION-BIND :do "one reactor turn of a parked bound CLI turn: boundAdvance! pumps the child's pipes and judges its limits without waiting; while it runs the conn is re-parked, when it ends the reply (or the failure, as none) goes to the chat continuation")
fn ! stepCli! srv: GatewayLoop conn: GatewayConn p: bd/BoundPend k: (fn [ch/ChatOutcome] -> ch/ChatStep) tag: String t0: Int64 -> GatewayLoop
  (let [(s (bd/boundAdvance! p))]
    (match (pairFirst s)
      ((none) (loopConns srv (listAppend srv.conns (list (GatewayConn :fd conn.fd :input conn.input :phase (connCli (pairSecond s) k tag t0))))))
      ((some r) (drive! srv conn.fd tag (k (ch/outCli (bd/boundCliFinish r (/ (- (monotonicNs) t0) 1000000))))))))

fn ! stepConn! srv: GatewayLoop conn: GatewayConn ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (match conn.phase
    ((connReading) (stepReading! srv conn ready))
    ((connHttp call k slot provider startMs model intent tag params profile) (stepHttp! srv conn tag call k slot provider startMs model intent params profile ready))
    ((connPool _ _) (loopConns srv (listAppend srv.conns (list conn))))
    ((connWarm slot provider sent timeout k deadline model intent tag profile) (stepWarm! srv conn tag slot provider sent timeout k deadline model intent profile))
    ((connTimer deadlineMs k tag) (stepTimer! srv conn deadlineMs k tag))
    ((connCli p k tag t0) (stepCli! srv conn p k tag t0))
    ((connBucketWait deadlineMs k tag) (stepBucketWait! srv conn deadlineMs k tag))
    ((connProxy upstreamFd pending response) (stepProxy! srv conn upstreamFd pending response ready))
    ((connWriting data) (stepWriting! srv conn data ready))
    ((connStatusPoll call budget) (stepStatusPoll! srv call budget ready)))

fn waitsFor? conn: GatewayConn requestId: Int64 -> Bool
  (match conn.phase ((connPool id _) (= id requestId)) (_ false))

fn ! deliverReplies! srv: GatewayLoop -> GatewayLoop
  (match (listHead srv.replies)
    ((none) srv)
    ((some reply)
      (let [(rest (loopPools srv srv.pools (optionOr (listTail srv.replies) (list))))
            (target (listHead (filter (fn [(cn GatewayConn)] -> Bool (waitsFor? cn reply.requestId)) rest.conns)))]
        (match target
          ((none) (deliverReplies! rest))
          ((some conn)
            (let [(others (loopConns rest (filter (fn [(cn GatewayConn)] -> Bool (not (waitsFor? cn reply.requestId))) rest.conns)))]
              (match conn.phase
                ((connPool _ k) (deliverReplies! (drive! others conn.fd "" (k (ch/outHttp (poolReplyHttp reply.result))))))
                (_ (deliverReplies! rest)))))))))

fn connWatch conn: GatewayConn -> (List (Pair Int64 Int64))
  (match conn.phase
    ((connReading) (list (pair conn.fd 1)))
    ((connHttp call _ _ _ _ _ _ _ _ _) (u/upstreamCallWatch call))
    ((connPool _ _) (list))
    ((connWarm _ _ _ _ _ _ _ _ _ _) (list))
    ((connTimer _ _ _) (list))
    ((connCli p _ _ _) (bd/boundFds p))
    ((connBucketWait _ _ _) (list))
    ((connProxy upstreamFd pending _) (list (pair upstreamFd (if (stringEmpty? pending) 1 2))))
    ((connWriting _) (list (pair conn.fd 2)))
    ((connStatusPoll call _) (u/upstreamCallWatch call)))

fn ! acceptReady! srv: GatewayLoop ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (if (not (readyOn? ready srv.listener)) srv
    (match (sockAccept srv.listener)
      ((err e) (do (logLine! (str "(:gateway :acceptFailed \"" e "\")")) srv))
      ((ok fd)
        (match (fdNonBlocking fd true)
          ((err e) (do (fdClose fd) (logLine! (str "(:gateway :acceptFailed \"" e "\")")) srv))
          ((ok _) (addConn srv fd connReading))))))

fn ! warmPolled! srv: GatewayLoop -> GatewayLoop
  (let [(polled (dp/pollSlots! srv.wiring (nowMs!)))]
    (do (fold (fn [(acc Bool) (line String)] -> Bool (logLine! line)) true (pairSecond polled))
      (loopWiring srv (pairFirst polled) srv.wiringText)))

; (:m :ref GW-BALANCER-POLL-WIRE :do "the balancer's status polls run on the reactor: a due poll (bl/pollsDue) is marked with poolPolled first, sent as a GET through the same curl path as any provider call with the poll provider's own key, and answered by poolPollReply when the reply lands; the key goes only into the request headers and no log row carries it")
fn wiringPool w: dp/Wiring pool: (Option bl/Pool) -> dp/Wiring
  (with w :pool pool)

fn ! statusPolls! srv: GatewayLoop -> GatewayLoop
  (match srv.wiring.pool
    ((none) srv)
    ((some pool)
      (fold (fn [(acc GatewayLoop) (poll bl/Poll)] -> GatewayLoop (startStatusPoll! acc poll (nowMs!)))
        srv (bl/pollsDue pool (nowMs!)))))

fn ! startStatusPoll! srv: GatewayLoop poll: bl/Poll now: Int64 -> GatewayLoop
  (let [(w srv.wiring)
        (key (match (u/upstreamProviderNamed w.rows poll.provider) ((some row) (row.key w.settings srv.env)) ((none) "")))
        (base (list (pair "User-Agent" "ASL-Gateway/1.0") (pair "Accept" "application/json")))
        (headers (if (stringEmpty? key) base (u/headerPut base "Authorization" (str "Bearer " key))))
        (req (u/UpstreamRequest :url poll.url :fragment "" :method "GET" :headers headers :data ""))
        (marked (loopWiring srv (wiringPool w (optionMap (fn [(p bl/Pool)] -> bl/Pool (bl/poolPolled p poll.budget now)) w.pool)) srv.wiringText))]
    (match (u/upstreamCallStart! req srv.env 15.0)
      ((err f) (do (logLine! (str "(:gateway :statusPoll :budget \"" poll.budget "\" :provider \"" poll.provider "\" :failed " (stringFromInt64 (failureStatus f)) ")")) marked))
      ((ok call) (addConn marked -1 (connStatusPoll call poll.budget)))))

fn ! stepStatusPoll! srv: GatewayLoop call: u/UpstreamCall budget: String ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (match (u/upstreamCallPump! call ready)
    ((err f) (statusPolled! srv budget (failureStatus f) ""))
    ((ok next)
      (if (u/upstreamCallOpen? next) (addConn srv -1 (connStatusPoll next budget))
        (match (u/upstreamCallFinish! next)
          ((ok resp) (statusPolled! srv budget resp.status resp.body))
          ((err f) (statusPolled! srv budget (failureStatus f) ""))))))

fn ! statusPolled! srv: GatewayLoop budget: String status: Int64 body: String -> GatewayLoop
  (match srv.wiring.pool
    ((none) srv)
    ((some pool)
      (let [(res (bl/poolPollReply pool budget status body (nowMs!)))
            (_ (if (stringEmpty? (pairSecond res)) true (logLine! (str "(:gateway :statusPoll :budget \"" budget "\" :note \"" (wire/asnEscape (pairSecond res)) "\")"))))]
        (loopWiring srv (wiringPool srv.wiring (some (pairFirst res))) srv.wiringText))))

fn pollsPending? srv: GatewayLoop -> Bool
  (match srv.wiring.pool ((some p) (not (listEmpty? p.polls))) ((none) false))

fn cliParked? conn: GatewayConn -> Bool
  (match conn.phase ((connCli _ _ _ _) true) (_ false))

fn parked? conn: GatewayConn -> Bool
  (match conn.phase ((connWarm _ _ _ _ _ _ _ _ _ _) true) (_ false))

; (:m :tags (retry) :do "the deadline-ordered timer queue the poll loop watches alongside its sockets: how long until this one conn's connTimer or connBucketWait should fire, clamped to >=0; none for every other phase")
fn timerWaitMs now: Int64 conn: GatewayConn -> (Option Int64)
  (match conn.phase
    ((connTimer deadlineMs _ _) (some (max 0 (- deadlineMs now))))
    ((connBucketWait deadlineMs _ _) (some (max 0 (- deadlineMs now))))
    (_ none))

; (:m :tags (retry) :do "the soonest a parked connTimer needs the reactor to look again; -1 (no constraint) when none are parked")
fn nearestTimerWaitMs now: Int64 conns: (List GatewayConn) -> Int64
  (fold (fn [(acc Int64) (cn GatewayConn)] -> Int64
          (match (timerWaitMs now cn)
            ((none) acc)
            ((some w) (if (< acc 0) w (min acc w)))))
    -1 conns)

; (:m :tags (retry) :do "combines two poll-timeout constraints, each either a nonnegative ms bound or -1 for \"no constraint from this source\"; the tighter (smaller) bound wins, matching fdPoll's own -1-means-block convention")
fn combineTimeoutMs a: Int64 b: Int64 -> Int64
  (if (< a 0) b (if (< b 0) a (min a b)))

fn ! gatewayTurn! srv: GatewayLoop ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (let [(polled (statusPolls! (warmPolled! srv)))
        (stepped (fold (fn [(acc GatewayLoop) (conn GatewayConn)] -> GatewayLoop (stepConn! acc conn ready))
                   (loopConns polled (list)) polled.conns))
        (advanced (pd/poolAdvance! stepped.pools ready stepped.env (nowMs!)))
        (pooled (loopPools stepped advanced.registry (listAppend stepped.replies advanced.replies)))]
    (acceptReady! (deliverReplies! pooled) ready))

fn ! gatewayEventLoop! srv: GatewayLoop -> (Result Int64 String)
  (let [(watch (listAppend (list (pair srv.listener 1))
                 (listAppend (fold (fn [(acc (List (Pair Int64 Int64))) (cn GatewayConn)] -> (List (Pair Int64 Int64)) (listAppend acc (connWatch cn))) (list) srv.conns)
                   (pd/poolWatch srv.pools))))
        (timeout (combineTimeoutMs (if (pollsPending? srv) 1000 -1) (combineTimeoutMs (if (pd/poolActive? srv.pools) 10 -1)
                   (combineTimeoutMs (if (listAny? parked? srv.conns) 20 -1)
                     (combineTimeoutMs (if (listAny? cliParked? srv.conns) 50 -1)
                       (nearestTimerWaitMs (nowMs!) srv.conns))))))]
    (match (fdPoll watch timeout)
      ((err e) (if (= e "interrupted") (gatewayEventLoop! srv) (err (str "gateway poll failed: " e))))
      ((ok ready) (gatewayEventLoop! (gatewayTurn! srv ready)))))

; (:m :ref GW-READY-BEFORE-REFUSE :do "the --ready file is written only after the config and secrets overlay succeed, so a refused serve leaves no ready file for a launcher to trust")
fn ! gatewayServe! listenerFd: Int64 upstreamPort: Int64 families: (List dp/LifecycleFamily) readyPath: String boundPort: Int64 -> (Result Int64 String)
  (match (secretsOverlayAt! (optionOr (mapGet (u/envMapFromList (envList)) "HOME") "") (u/envMapFromList (envList)))
    ((err e) (do (fdClose listenerFd) (err e)))
    ((ok env)
      (match (if (stringEmpty? readyPath) (ok true) (resultMap (fileWrite readyPath (str boundPort)) (fn [(_ Unit)] -> Bool true)))
        ((err e) (do (fdClose listenerFd) (err e)))
        ((ok _) (gatewayServeWith! listenerFd upstreamPort families (keyFilesAt! (optionOr (mapGet env "HOME") "") env))))))

; (:m :ref GW-SERVE-KEYFILES :do "the config's keyFiles supply provider keys the world env lacks")
fn ! keyFilesAt! home: String env: (Map String String) -> (Map String String)
  (c/keyFilesEnvOverlay! (resultOr (fileReadString (c/gatewayProfilesPath home)) "") env)

; (:m :ref GW-SECRETS-FILE-OVERRIDE :do "the secrets file is the config's (:gateway :secretsFile) when set, else HOME/.asl/secrets.asn, the same choice config check makes")
; (:m :ref AUDIT12-B6 :do "serve auth must not fail open: a config that cannot be read for its :secretsFile, or a named file that is missing, refuses to start instead of falling back to no token")
fn ! secretsPathAt! home: String -> (Result String String)
  (match (c/gatewaySecretsFileChoice (resultOr (fileReadString (c/gatewayProfilesPath home)) ""))
    ((err e) (err e))
    ((ok (none)) (ok (str home "/.asl/secrets.asn")))
    ((ok (some p)) (if (fileExists? p) (ok p) (err (str "ERR_SECRETS_MISSING: the :secretsFile " p " does not exist")))))

fn ! secretsOverlayAt! home: String env: (Map String String) -> (Result (Map String String) String)
  (match (secretsPathAt! home)
    ((err e) (err e))
    ((ok path) (fed/secretsEnvOverlay! path env)))

fn ! gatewayServeWith! listenerFd: Int64 upstreamPort: Int64 families: (List dp/LifecycleFamily) env: (Map String String) -> (Result Int64 String)
  (let [        (root (optionOr (mapGet env "ASL_GATEWAY_ROOT") (optionOr (mapGet env "ROOT_DIR") (resultOr (realPath ".") "."))))
        (registryEnv (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))]
    (gatewayEventLoop! (GatewayLoop :listener listenerFd :upstreamPort upstreamPort :env env :home (optionOr (mapGet env "HOME") root)
      :rootDir root :registryPath (if (stringEmpty? registryEnv) (str root "/.asl/mem/calibration/index.asn") registryEnv)
      :promptMaxBytes (optionOr (stringToInt64 (optionOr (mapGet env "AGY_PROMPT_MAX_BYTES") "188000")) 188000)
      :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
      :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
      :wiring (dp/emptyWiring (resultOr (u/upstreamSettings env) (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0)))
      :wiringText none :families families :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty)
      :omni (om/emptyOmniState (omniZeroKey) (omniZeroKey)))))


; (:m :ref GW-BREAKER-STALE-20261018 :tags (breaker config) :do "the breaker's cooldown comes from the loaded config's (:gateway ... :breakerCooldownSec N) when present, else the 600s default via makeBreakerState's own guard; a config that never sets it is unchanged from before. BreakerState itself is held only in this GatewayLoop value, freshly built here on every linkOpen! call -- there is no file-backed persistence across processes, so GW-BREAKER-STALE-20261018's '45-cell sweep stuck open' incident was one long-lived in-process breaker outlasting a fixed 600s cooldown within a single sweep run, not state surviving a restart")
fn ! linkOpen! env: (Map String String) home: String rootDir: String families: (List dp/LifecycleFamily) -> (Result GatewayLoop String)
  (match (secretsOverlayAt! home env)
    ((err e) (err e))
    ((ok overlaid) (linkOpenWith! (keyFilesAt! home overlaid) home rootDir families)))

fn ! linkOpenWith! env: (Map String String) home: String rootDir: String families: (List dp/LifecycleFamily) -> (Result GatewayLoop String)
  (let [(registryEnv (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))
        (registryPath (if (stringEmpty? registryEnv) (str rootDir "/.asl/mem/calibration/index.asn") registryEnv))
        (loaded (c/gatewayProfilesLoad! (c/emptyProfilesCache) home registryPath))
        (path (c/gatewayProfilesPath home))]
    (match (pairSecond loaded)
      ((err e) (err e))
      ((ok table)
        (match (u/upstreamSettings env)
          ((err e) (err e))
          ((ok settings)
            (let [(text (resultOr (fileReadString path) ""))]
              (match (dp/wiringFromConfig (some table) text settings env families)
                ((err e) (err (str "gateway wiring: " e)))
                ((ok w)
                  (ok (GatewayLoop :listener -1 :upstreamPort 0 :env env :home home :rootDir rootDir :registryPath registryPath
                        :promptMaxBytes (optionOr (stringToInt64 (optionOr (mapGet env "AGY_PROMPT_MAX_BYTES") "188000")) 188000)
                        :conns (list) :pools (pd/poolWithPlugins (pd/emptyPoolRegistry) w.plugins) :replies (list)
                        :breaker (b/makeBreakerState (optionOr (c/gatewayBreakerCooldownSecOverride text) 600))
                        :buckets (u/emptyBucketRegistry) :profiles (pairFirst loaded) :wiring w :wiringText (some text)
                        :families families :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty)
                        :omni (om/emptyOmniState (omniZeroKey) (omniZeroKey))))))))))))

fn outboxFor srv: GatewayLoop fd: Int64 -> (Option String)
  (optionMap pairSecond (listHead (filter (fn [(x (Pair Int64 String))] -> Bool (= (pairFirst x) fd)) srv.outbox)))

fn withoutOutbox srv: GatewayLoop fd: Int64 -> GatewayLoop
  (with srv :outbox (filter (fn [(x (Pair Int64 String))] -> Bool (!= (pairFirst x) fd)) srv.outbox))

fn pending? srv: GatewayLoop fd: Int64 -> Bool
  (or (listAny? (fn [(cn GatewayConn)] -> Bool (= cn.fd fd)) srv.conns) (not (listEmpty? srv.replies)))

fn ! linkPump! srv: GatewayLoop fd: Int64 deadlineMs: Int64 -> (Pair GatewayLoop (Result String String))
  (match (outboxFor srv fd)
    ((some data) (pair (withoutOutbox srv fd) (ok data)))
    ((none)
      (cond
        ((not (or (pending? srv fd) (pd/poolActive? srv.pools))) (pair srv (err "in-process gateway request ended without a response")))
        ((> (nowMs!) deadlineMs) (pair srv (err "in-process gateway request timed out")))
        (else
          (let [(watch (listAppend (fold (fn [(acc (List (Pair Int64 Int64))) (cn GatewayConn)] -> (List (Pair Int64 Int64)) (listAppend acc (connWatch cn))) (list) srv.conns)
                         (pd/poolWatch srv.pools)))
                (timeout (combineTimeoutMs (if (pd/poolActive? srv.pools) 10 -1)
                           (combineTimeoutMs (if (or (listEmpty? watch) (listAny? parked? srv.conns)) 20 -1)
                             (combineTimeoutMs (nearestTimerWaitMs (nowMs!) srv.conns) 1000))))]
            (match (fdPoll watch timeout)
              ((err e) (if (= e "interrupted") (linkPump! srv fd deadlineMs) (pair srv (err (str "gateway poll failed: " e)))))
              ((ok ready) (linkPump! (gatewayTurn! srv ready) fd deadlineMs))))))))

fn ! linkSend! srv: GatewayLoop method: String path: String headers: (List (Pair String String)) body: String timeoutMs: Int64 -> (Pair GatewayLoop (Result String String))
  (let [(request (HttpRequest :method method :path path :headers headers :body body))
        (started (dispatchAuthed! (withoutOutbox srv (linkFd)) (linkFd) "" request))]
    (linkPump! started (linkFd) (+ (nowMs!) timeoutMs)))
