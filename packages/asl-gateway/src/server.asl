(module aslGateway/server
  :x [GatewayTurnVerdict Launch GatewayLoop linkOpen! linkSend! extractThinkBlocks detectEshViolation inspectCompletionTurn handleSyncIngest handleBrowserDispatch handleMediaDispatch gatewayHostPath! main! main mainWith]
  :i [(wire :a wire) (sync :a sync) (browser :a browser) (media :a media) (aslGateway/cliDispatch :a cli) (asl/packages/asl-cli/src/system :a sys)
      (aslGateway/chat :a ch) (aslGateway/upstream :a u) (aslGateway/config :a c) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b)
      (aslGateway/dispatch :a dp) (aslGateway/plugin :a p)])

(schema GatewayTurnVerdict
  (:f allowed Bool)
  (:f quarantinedThink Str)
  (:f cleanOutput Str)
  (:f toolCalls (List Str))
  (:f rejectionReason Str))

fn extractThinkBlocks text: Str -> (Pair Str Str)
  (let ((openTag "<think>")
        (closeTag "</think>")
        (idxOpen (stringIndexOf text openTag)))
    (mt idxOpen
      ((none) (pair "" text))
      ((some o)
        (let ((afterOpen (optionOr (stringSlice text (+ o 7) (stringLength text)) ""))
              (idxClose (stringIndexOf afterOpen closeTag)))
          (mt idxClose
            ((none) (pair (stringTrim afterOpen) (optionOr (stringSlice text 0 o) "")))
            ((some c)
              (let ((thinkContent (optionOr (stringSlice afterOpen 0 c) ""))
                    (prefix (optionOr (stringSlice text 0 o) ""))
                    (suffix (optionOr (stringSlice afterOpen (+ c 8) (stringLength afterOpen)) ""))
                    (remaining (stringTrim (str prefix " " suffix))))
                (pair (stringTrim thinkContent) remaining))))))))

fn detectEshViolation text: Str -> Bool
  (let ((lower (stringLower text)))
    (and (or (stringContains? lower "test") (or (stringContains? lower "gate") (stringContains? lower "assert")))
         (or (stringContains? lower " pass") (or (stringContains? lower "verif") (stringContains? lower "clean")))))

fn inspectCompletionTurn rawText: Str hasVerifiedExec: Bool -> GatewayTurnVerdict
  (let ((demuxThink (extractThinkBlocks rawText))
        (thinkPart (pairFirst demuxThink))
        (remaining (pairSecond demuxThink))
        (demuxAsn (wire/demuxRawAsnTurn remaining))
        (uiPart (pairFirst demuxAsn))
        (toolPart (pairSecond demuxAsn))
        (isEsh (and (detectEshViolation uiPart) (not hasVerifiedExec))))
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
  (let ((contentHash (sync/computeContentHash rawPayload)))
    (pair "ok" contentHash))

fn handleBrowserDispatch frame: browser/BrowserActionFrame -> browser/BrowserActionReceipt
  (let ((isValid (browser/validateActionOp frame.op)))
    (if isValid
      (browser/createSuccessReceipt frame.actionId 45 "https://gateway.local" "none" "executed")
      (browser/createErrorReceipt frame.actionId 0 "invalid_op" "Unknown browser operation")))

fn handleMediaDispatch req: media/MediaGenRequest -> media/MediaGenReceipt
  (let ((isValid (media/validateMediaKind req.mediaKind))
        (dim (media/calculateMediaDimensions req.aspectRatio)))
    (if isValid
      (media/createMediaReceipt req.requestId "ok" "storage://generated/asset" "/tmp/asset" "hash123" (pairFirst dim) (pairSecond dim) 10)
      (media/createMediaReceipt req.requestId "rejected" "" "" "" 0 0 0)))

fn gatewayServerArg args: (List String) index: Int64 -> String
  (optionOr (listGet args index) "")

fn gatewayDropArgs args: (List String) -> (List String)
  (mt (listTail args) ((some tail) tail) ((none) (list)))

fn gatewayFindArg args: (List String) flag: String fallback: String -> String
  (if (< (listLength args) 2) fallback
    (if (= (gatewayServerArg args 0) flag) (gatewayServerArg args 1)
      (gatewayFindArg (gatewayDropArgs args) flag fallback)))

fn ! gatewayStatePath! -> String
  (str (optionOr (envGet "HOME") "/tmp") "/.asl/gateway.asn")

fn ! gatewayReadyPath! -> String
  (str (gatewayStatePath!) ".ready")

fn gatewayNumberAfter text: String marker: String fallback: Int64 -> Int64
  (mt (stringIndexOf text marker)
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
        (and (stringContains? cmd launch.module)
          (stringContains? cmd " serve ")))))

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
  (mt (fileReadString (gatewayStatePath!))
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
  (mt (fileReadString (gatewayStatePath!))
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
  (mt (fileReadString (gatewayStatePath!))
    ((err _) (do (sys/say! "(:gateway :status :offline :port 0)") (ok 0)))
    ((ok state)
      (let [(numbers (gatewayStateNumbers state))
            (pid (pairFirst numbers))
            (port (pairSecond numbers))]
        (if (not (gatewayServiceOwnsPid! launch pid))
          (do (sys/say! (str "(:gateway :status :offline :port " port ")")) (ok 0))
          (mt (procKill pid "SIGTERM")
            ((err e) (err (str "gateway stop failed: " e)))
            ((ok _)
              (if (gatewayWaitGone! pid 100)
                (do (sys/say! (str "(:gateway :status :offline :port " port ")")) (ok 0))
                (err "gateway process did not exit after SIGTERM"))))))))

fn gatewayStateUpstream text: String -> String
  (mt (stringIndexOf text ":upstream ")
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
  (mt (fileReadString (gatewayStatePath!))
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
          (mt (stringToInt64 portText)
            ((none) (err "gateway restart port must be an integer between 0 and 65535"))
            ((some port)
              (if (or (< port 0) (> port 65535))
                (err "gateway restart port must be an integer between 0 and 65535")
                (mt (if (gatewayServiceOwnsPid! launch oldPid) (gatewayStop! launch) (ok 0))
                  ((err e) (err e))
                  ((ok _) (gatewayStart! launch (list "start" "--port" portText "--upstream" upstream)))))))))))

(schema Launch
  (:f module String)
  (:f families (List dp/LifecycleFamily)))

fn ! main args: (List String) -> (Result Int64 String)
  (mainWith args "asl/packages/asl-gateway/src/server.asl" (list))

fn ! mainWith args: (List String) module: String families: (List dp/LifecycleFamily) -> (Result Int64 String)
  (let [(launch (Launch :module module :families (listAppend (dp/builtinFamilies) families)))
        (first (gatewayServerArg args 0))
        (mode (if (= first "--port") (gatewayServerArg args 2) first))
        (portText (gatewayFindArg args "--port" "0"))
        (port (optionOr (stringToInt64 portText) 0))]
    (cond
      ((= mode "start")
        (mt (gatewayStart! launch args)
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
          (mt (gatewayRunServer! launch port upstream ready)
            ((err e) (do (sys/sayErr! e) (ok 1)))
            ((ok _) (ok 0)))))
      ((= mode "run")
        (let [(upstream (gatewayFindArg args "--upstream" ""))]
          (mt (gatewayRunServer! launch port upstream "")
            ((err e) (do (sys/sayErr! e) (ok 1)))
            ((ok _) (ok 0)))))
      ((or (= mode "config") (or (= mode "configCheck") (= mode "convert")))
        (cli/gatewayCliMain args))
      ((or (= mode "restart") (= mode "update"))
        (mt (gatewayRestart! launch args)
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
    (mt (fileReadString path)
      ((err _) (do (processRun "/bin/sleep 0.02") (gatewayWaitReady! path (- attempts 1))))
      ((ok text)
        (mt (stringToInt64 (stringTrim text))
          ((none) (do (processRun "/bin/sleep 0.02") (gatewayWaitReady! path (- attempts 1))))
          ((some port) (if (> port 0) (ok port) (err "gateway server published an invalid port")))))))

fn gatewayHostPath! hostResult: (Result String String) -> (Result String String)
  (mt hostResult
    ((err e) (err (str "cannot resolve gateway host executable: " e)))
    ((ok host)
      (if (stringEmpty? host)
        (err "resolved gateway host executable path is empty")
        (if (or (not (= (optionOr (stringSlice host 0 1) "") "/")) (not (fileExists? host)))
          (err "resolved gateway host executable path is invalid")
          (if (not (gatewaySafeShellArg? host))
            (err "resolved gateway host executable path contains unsupported shell characters")
            (ok host))))))

fn ! gatewayStart! launch: Launch args: (List String) -> (Result Int64 String)
  (mt (gatewayHostPath! (procExePath))
    ((err e) (err e))
    ((ok host) (gatewayStartWithHost! launch args host)))

fn ! gatewayStartWithHost! launch: Launch args: (List String) host: String -> (Result Int64 String)
  (let [(statePath (gatewayStatePath!))
        (readyPath (gatewayReadyPath!))
        (dir (str (optionOr (envGet "HOME") "/tmp") "/.asl"))
        (portText (gatewayFindArg args "--port" "0"))
        (port (optionOr (stringToInt64 portText) (- 1)))
        (upstream (gatewayFindArg args "--upstream" ""))
        (root (optionOr (envGet "ASL_GATEWAY_ROOT")
                 (stringTrim (processRun "pwd").stdout)))
        (modulePath (str root "/" launch.module))]
    (if (or (< port 0) (> port 65535)) (err "port must be between 0 and 65535")
      (if (or (stringEmpty? upstream)
            (or (not (gatewaySafeShellArg? host))
              (or (not (gatewaySafeShellArg? modulePath))
                (or (not (gatewaySafeShellArg? upstream))
                  (or (not (gatewaySafeShellArg? portText)) (not (gatewaySafeShellArg? readyPath)))))))
        (err "gateway launch arguments are missing or contain unsupported shell characters")
        (mt (dirCreate dir)
          ((err e) (err (str "cannot create gateway state directory: " e)))
          ((ok _)
            (mt (fileWrite readyPath "pending")
              ((err e) (err (str "cannot prepare gateway readiness file: " e)))
              ((ok _)
                (let [(launch (processRun (str "/usr/bin/nohup " host " run " modulePath
                                        " serve --port " portText " --upstream " upstream
                                        " --ready " readyPath " >/dev/null 2>&1 & echo $!")))
                      (pid (optionOr (stringToInt64 (stringTrim launch.stdout)) 0))]
                  (if (or (not (= launch.exitCode 0)) (<= pid 1))
                    (err "failed to launch ASL gateway server")
                    (mt (gatewayWaitReady! readyPath 250)
                      ((err e) (do (procKill pid "SIGTERM") (err e)))
                      ((ok boundPort)
                        (mt (fileWrite statePath
                              (str "(:gateway :status :running :pid " pid " :port " boundPort
                                " :upstream " upstream ")"))
                          ((err e) (do (procKill pid "SIGTERM") (err (str "cannot persist gateway state: " e))))
                          ((ok _) (ok boundPort))))))))))))))

fn ! gatewayRunServer! launch: Launch port: Int64 upstream: String readyPath: String -> (Result Int64 String)
  (let [(upstreamPort (gatewayUpstreamPort upstream))]
    (if (or (<= upstreamPort 0) (> upstreamPort 65535))
      (err "upstream must be an http URL with an explicit port")
      (mt (tcpListen port)
        ((err e) (err (str "gateway listen failed: " e)))
        ((ok listenerFd)
          (mt (sockLocalPort listenerFd)
            ((err e) (do (fdClose listenerFd) (err e)))
            ((ok boundPort)
              (if (stringEmpty? readyPath)
                (gatewayServe! listenerFd upstreamPort launch.families)
                (mt (fileWrite readyPath (str boundPort))
                  ((err e) (do (fdClose listenerFd) (err e)))
                  ((ok _) (gatewayServe! listenerFd upstreamPort launch.families))))))))))

(enum ConnPhase
  (:c connReading [])
  (:c connHttp [(call u/UpstreamCall) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (slot String) (provider String) (startMs Int64)])
  (:c connPool [(requestId Int64) (k (fn [ch/ChatOutcome] -> ch/ChatStep))])
  (:c connWarm [(slot String) (provider String) (request u/UpstreamRequest) (timeout Float64) (k (fn [ch/ChatOutcome] -> ch/ChatStep)) (deadlineMs Int64)])
  (:c connProxy [(upstreamFd Int64) (pending String) (response String)])
  (:c connWriting [(data String)]))

(schema GatewayConn
  (:f fd Int64)
  (:f input String)
  (:f phase ConnPhase))

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
  (:f outbox (List (Pair Int64 String))))

fn loopConns srv: GatewayLoop conns: (List GatewayConn) -> GatewayLoop
  (with srv :conns conns)

fn loopPools srv: GatewayLoop pools: pd/PoolRegistry replies: (List pd/PoolReply) -> GatewayLoop
  (with srv :pools pools :replies replies)

fn loopState srv: GatewayLoop breaker: b/BreakerState buckets: u/BucketRegistry profiles: c/ProfilesCache -> GatewayLoop
  (with srv :breaker breaker :buckets buckets :profiles profiles)

fn loopWiring srv: GatewayLoop wiring: dp/Wiring text: (Option String) -> GatewayLoop
  (with srv :pools (pd/poolWithPlugins srv.pools wiring.plugins) :wiring wiring :wiringText text)

fn addConn srv: GatewayLoop fd: Int64 phase: ConnPhase -> GatewayLoop
  (mt phase
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
    ((= code 200) "OK") ((= code 400) "Bad Request") ((= code 404) "Not Found") ((= code 429) "Too Many Requests")
    ((= code 500) "Internal Server Error") ((= code 502) "Bad Gateway") ((= code 503) "Service Unavailable")
    ((= code 504) "Gateway Timeout") (else "Status"))

fn renderResponse resp: ch/ChatResponse -> String
  (let [(head resp.head)
        (code (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (mt h ((ch/headStatus n) n) ((ch/headField _ _) acc))) 200 head))
        (fields (fold (fn [(acc (List String)) (h ch/HeadItem)] -> (List String)
                        (mt h ((ch/headStatus _) acc) ((ch/headField n v) (listAppend acc (list (str n ": " v "\r\n")))))) (list) head))
        (hasLength (listAny? (fn [(h ch/HeadItem)] -> Bool (mt h ((ch/headField n _) (= (stringLower n) "content-length")) ((ch/headStatus _) false))) head))
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
  (mt (stringIndexOf line ":")
    ((none) none)
    ((some at) (some (pair (stringTrim (optionOr (stringSlice line 0 at) ""))
                           (stringTrim (optionOr (stringSlice line (+ at 1) (stringLength line)) ""))))))

fn contentLength headers: (List (Pair String String)) -> Int64
  (fold (fn [(acc Int64) (h (Pair String String))] -> Int64
          (if (= (stringLower (pairFirst h)) "content-length") (optionOr (stringToInt64 (pairSecond h)) acc) acc))
    0 headers)

fn parseRequest raw: String -> (Option HttpRequest)
  (mt (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(lines (stringSplit (optionOr (stringSlice raw 0 end) "") "\r\n"))
            (requestLine (stringSplit (optionOr (listHead lines) "") " "))
            (headers (fold (fn [(acc (List (Pair String String))) (l String)] -> (List (Pair String String))
                             (mt (headerPair l) ((some h) (listAppend acc (list h))) ((none) acc)))
                       (list) (optionOr (listTail lines) (list))))
            (bodyStart (+ end 4))
            (want (contentLength headers))]
        (if (< (- (stringLength raw) bodyStart) want) none
          (some (HttpRequest :method (optionOr (listGet requestLine 0) "") :path (optionOr (listGet requestLine 1) "")
                  :headers headers :body (optionOr (stringSlice raw bodyStart (+ bodyStart want)) "")))))))

fn chatPath? path: String -> Bool
  (or (stringStartsWith? path "/v1/chat/completions") (stringStartsWith? path "/chat/completions"))

fn failureReply f: u/UpstreamFailure -> ch/HttpReply
  (mt f
    ((u/httpFailure status reason body) (ch/httpError status reason (list) body))
    ((u/transportFailure code text) (ch/httpRaised (= code 28) (str "curl exit " (stringFromInt64 code) ": " (stringTrim text))))
    ((u/toolAbsent tool detail) (ch/httpRaised false (str tool ": " detail)))
    ((u/protocolFailure detail) (ch/httpRaised false detail)))

fn poolReplyHttp result: (Result u/UpstreamResponse pd/PoolFailure) -> ch/HttpReply
  (mt result
    ((ok resp) (ch/httpOk resp.status (list) resp.body))
    ((err failure)
      (mt failure
        ((pd/poolUpstream f) (failureReply f))
        ((pd/poolTimedOut id ms) (ch/httpRaised true (str "ERR_POOL_TIMEOUT: request " (stringFromInt64 id) " waited past requestTimeoutMs " (stringFromInt64 ms))))
        ((pd/poolRejected reason) (ch/httpRaised false (str "ERR_POOL_REJECTED: " reason))))))

fn ! logLine! text: String -> Bool
  (do (eprintln text) true)

fn breakerEvent! st: b/BreakerState event: String pool: String now: Int64 -> b/BreakerState
  (cond
    ((= event "markDown") (b/breakerMarkDown st pool now))
    ((= event "note503") (pairFirst (b/breakerNote503 st pool now)))
    ((= event "reset503") (b/breakerReset503 st pool))
    ((= event "clear") (b/breakerClear st pool))
    (else (do (logLine! (str "(:gateway :breaker :unknownEvent \"" (wire/asnEscape event) "\")")) st)))

fn ! runEffect! srv: GatewayLoop eff: ch/ChatEffect -> (Pair GatewayLoop ch/ChatOutcome)
  (mt eff
    ((ch/effRealpath p) (pair srv (ch/outPath (resultOr (realPath p) p))))
    ((ch/effIsDir p) (pair srv (ch/outBool (mt (fileStat p) ((ok st) st.isDir) ((err _) false)))))
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
    ((ch/effBreakerEvent event pool)
      (pair (loopState srv (breakerEvent! srv.breaker event pool (nowSec!)) srv.buckets srv.profiles) ch/outDone))
    ((ch/effUsageNote p a o _)
      (do (logLine! (str "(:gateway :usage :provider \"" (wire/asnEscape p) "\" :alias \"" (wire/asnEscape a) "\" :outcome \"" (wire/asnEscape o) "\")"))
        (pair srv ch/outDone)))
    ((ch/effUsageFallback p a)
      (do (logLine! (str "(:gateway :fallback :provider \"" (wire/asnEscape p) "\" :alias \"" (wire/asnEscape a) "\")")) (pair srv ch/outDone)))
    ((ch/effTelemetry rec)
      (do (mt rec ((some r) (logLine! r)) ((none) true)) (pair srv ch/outDone)))
    ((ch/effNoteIntent i)
      (do (logLine! (str "(:gateway :unknownIntent \"" (wire/asnEscape i) "\")")) (pair srv ch/outDone)))
    ((ch/effLog text) (do (logLine! (stringTrim text)) (pair srv ch/outDone)))
    ((ch/effBucket model rpm timeout)
      (let [(r (u/geminiAcquire! srv.buckets model rpm timeout))]
        (pair (loopState srv srv.breaker (pairFirst r) srv.profiles) (ch/outBool (resultOr (pairSecond r) false)))))
    ((ch/effCli client _)
      (do (logLine! (str "(:gateway :cli :unavailable \"" (wire/asnEscape client) "\" :entry http)")) (pair srv (ch/outCli none))))
    ((ch/effHttp _ _) (pair srv (ch/outHttp (ch/httpRaised false "an HTTP effect reached the synchronous effect runner"))))
    ((ch/effPoolHttp _ _ _ _ _ _) (pair srv (ch/outHttp (ch/httpRaised false "a pool effect reached the synchronous effect runner")))))

fn ! drive! srv: GatewayLoop fd: Int64 step: ch/ChatStep -> GatewayLoop
  (mt step
    ((ch/stepDone resp) (addConn srv fd (connWriting (renderResponse resp))))
    ((ch/stepRaised kind message) (addConn srv fd (connWriting (errorResponse 500 (str kind ": " message)))))
    ((ch/stepEffect eff k)
      (mt eff
        ((ch/effHttp provider model intent role request timeout)
          (dispatchHttp! srv fd (dp/RouteHint :provider provider :model model :intent intent :role role
                                  :promptTokens (/ (stringLength request.data) 4)) request timeout k))
        ((ch/effPoolHttp provider model base pool request timeout)
          (let [(sub (pd/poolSubmit! srv.pools provider model base pool request timeout srv.env (nowMs!)))
                (out (pairSecond sub))]
            (addConn (loopPools srv out.registry (listAppend srv.replies out.replies)) fd (connPool (pairFirst sub) k))))
        (_ (let [(r (runEffect! srv eff))] (drive! (pairFirst r) fd (k (pairSecond r))))))))

fn errorOutcome status: Int64 reason: String -> ch/ChatOutcome
  (ch/outHttp (ch/httpError status reason (list (pair (ch/gatewayOriginHeader) "gateway")) (str "{\"error\": \"" (wire/asnEscape reason) "\"}")))

fn ! dispatchHttp! srv: GatewayLoop fd: Int64 hint: dp/RouteHint request: u/UpstreamRequest timeout: Float64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) -> GatewayLoop
  (let [(w srv.wiring)
        (planned (dp/plan w hint request srv.env (nowMs!)))]
    (mt planned
      ((dp/planReject status reason row)
        (do (logLine! (dp/decisionText row))
          (drive! srv fd (k (errorOutcome status reason)))))
      ((dp/planSend slot provider sent row)
        (do (logLine! (dp/decisionText row))
          (sendPlanned! srv fd slot provider sent (dp/sendTimeout w hint provider timeout) k)))
      ((dp/planWait slot provider sent row cold deadline)
        (do (logLine! (dp/decisionText row))
          (if cold
            (mt (dp/startSlot! w slot (nowMs!) deadline)
              ((dp/startRefused status reason line) (do (logLine! line) (drive! srv fd (k (errorOutcome status reason)))))
              ((dp/startOk next line) (do (logLine! line) (addConn (loopWiring srv next srv.wiringText) fd (connWarm slot provider sent (dp/sendTimeout w hint provider timeout) k deadline)))))
            (addConn (loopWiring srv (dp/waiting w slot) srv.wiringText) fd (connWarm slot provider sent (dp/sendTimeout w hint provider timeout) k deadline)))))))

fn ! sendPlanned! srv: GatewayLoop fd: Int64 slot: String provider: String sent: u/UpstreamRequest timeout: Float64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) -> GatewayLoop
  (let [(w srv.wiring)]
    (mt (p/sendHttp! w.plugins provider sent srv.env timeout)
      ((err f) (drive! (settled! srv slot provider "" 0 false) fd (k (ch/outHttp (failureReply f)))))
      ((ok call) (addConn (loopWiring srv (dp/started w slot) srv.wiringText) fd (connHttp call k slot provider (nowMs!))))))

fn ! stepWarm! srv: GatewayLoop conn: GatewayConn slot: String provider: String sent: u/UpstreamRequest timeout: Float64 k: (fn [ch/ChatOutcome] -> ch/ChatStep) deadline: Int64 -> GatewayLoop
  (let [(now (nowMs!))]
    (mt (dp/slotReady srv.wiring slot now)
      ((dp/readyNow) (sendPlanned! srv conn.fd slot provider sent timeout k))
      ((dp/readyGone reason) (drive! srv conn.fd (k (errorOutcome 503 reason))))
      ((dp/readyLater)
        (if (> now deadline)
          (do (logLine! (str "(:gateway :lifecycle :op wait :endpoint \"" slot "\" :result timeout)"))
            (drive! srv conn.fd (k (errorOutcome 503 (str "endpoint " slot " did not warm within coldStartMs")))))
          (loopConns srv (listAppend srv.conns (list conn)))))))

fn ! settled! srv: GatewayLoop slot: String provider: String body: String startMs: Int64 success: Bool -> GatewayLoop
  (if (stringEmpty? slot) srv
    (let [(now (nowMs!))
          (out (dp/settle srv.wiring slot provider (dp/usageTokens body) (if (> startMs 0) (- now startMs) 1) success now))]
      (do (logLine! (pairSecond out)) (loopWiring srv (pairFirst out) srv.wiringText))))

fn ! chatWorld! srv: GatewayLoop -> (Pair GatewayLoop (Result ch/ChatWorld String))
  (let [(loaded (c/gatewayProfilesLoad! srv.profiles srv.home srv.registryPath))
        (srv1 (loopState srv srv.breaker srv.buckets (pairFirst loaded)))]
    (mt (u/upstreamSettings srv.env)
      ((err e) (pair srv1 (err e)))
      ((ok settings) (pair (wired! srv1 (pairSecond loaded) settings) (ok (ch/ChatWorld :env srv.env :rootDir srv.rootDir :settings settings
                                      :agyPromptMaxBytes srv.promptMaxBytes :table (pairSecond loaded)))))))

fn ! wired! srv: GatewayLoop table: (Result c/GatewayTable String) settings: u/UpstreamSettings -> GatewayLoop
  (let [(path (c/gatewayProfilesPath srv.home))
        (text (if (fileExists? path) (resultOr (fileReadString path) "") ""))
        (tableOpt (mt table ((ok t) (some t)) ((err _) none)))]
    (if (= srv.wiringText (some text)) srv
      (mt (dp/wiringFromConfig tableOpt text settings srv.env srv.families)
        ((ok w) (loopWiring srv (dp/carrySpend srv.wiring w) (some text)))
        ((err e) (do (logLine! (str "(:gateway :wiring :error \"" (wire/asnEscape e) "\")"))
                   (loopWiring srv (dp/emptyWiring settings) (some text)))))))

fn ! dispatch! srv: GatewayLoop fd: Int64 raw: String request: HttpRequest -> GatewayLoop
  (if (and (= request.method "POST") (chatPath? request.path))
    (let [(w (chatWorld! srv))]
      (mt (pairSecond w)
        ((err e) (addConn (pairFirst w) fd (connWriting (errorResponse 500 e))))
        ((ok world) (drive! (pairFirst w) fd (ch/chatStart! (ch/ChatRequest :path request.path :headers request.headers :body request.body) world)))))
    (mt (tcpConnect srv.upstreamPort)
      ((err e) (addConn srv fd (connWriting (errorResponse 502 (str "upstream connect failed: " e)))))
      ((ok upstreamFd) (addConn srv fd (connProxy upstreamFd raw "")))))

fn ! closeConn! conn: GatewayConn -> Bool
  (do (fdClose conn.fd) true)

fn ! stepReading! srv: GatewayLoop conn: GatewayConn ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (if (not (readyOn? ready conn.fd)) (loopConns srv (listAppend srv.conns (list conn)))
    (mt (fdRead conn.fd 65536)
      ((err e) (if (= e "wouldBlock") (loopConns srv (listAppend srv.conns (list conn))) (do (closeConn! conn) srv)))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (closeConn! conn) srv)
          (let [(input (str conn.input chunk))]
            (mt (parseRequest input)
              ((none) (loopConns srv (listAppend srv.conns (list (with conn :input input :phase connReading)))))
              ((some request) (dispatch! srv conn.fd input request))))))))

fn ! stepProxy! srv: GatewayLoop conn: GatewayConn upstreamFd: Int64 pending: String response: String ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (let [(keep (fn [(p String) (r String)] -> GatewayLoop
                (loopConns srv (listAppend srv.conns (list (with conn :input "" :phase (connProxy upstreamFd p r)))))))]
    (if (not (readyOn? ready upstreamFd)) (keep pending response)
      (if (not (stringEmpty? pending))
        (mt (fdWrite upstreamFd pending)
          ((err e) (do (fdClose upstreamFd) (addConn srv conn.fd (connWriting (errorResponse 502 (str "upstream write failed: " e))))))
          ((ok n) (keep (optionOr (stringSlice pending n (stringLength pending)) "") response)))
        (mt (fdRead upstreamFd 65536)
          ((err e) (do (fdClose upstreamFd) (addConn srv conn.fd (connWriting (errorResponse 502 (str "upstream read failed: " e))))))
          ((ok chunk)
            (if (stringEmpty? chunk)
              (do (fdClose upstreamFd) (addConn srv conn.fd (connWriting response)))
              (keep pending (str response chunk))))))))

fn ! stepWriting! srv: GatewayLoop conn: GatewayConn data: String ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (if (not (readyOn? ready conn.fd)) (loopConns srv (listAppend srv.conns (list conn)))
    (mt (fdWrite conn.fd data)
      ((err e) (if (= e "wouldBlock") (loopConns srv (listAppend srv.conns (list conn))) (do (closeConn! conn) srv)))
      ((ok n)
        (let [(rest (optionOr (stringSlice data n (stringLength data)) ""))]
          (if (stringEmpty? rest) (do (closeConn! conn) srv)
            (addConn srv conn.fd (connWriting rest)))))))

fn ! stepHttp! srv: GatewayLoop conn: GatewayConn call: u/UpstreamCall k: (fn [ch/ChatOutcome] -> ch/ChatStep) slot: String provider: String startMs: Int64 ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (mt (u/upstreamCallPump! call ready)
    ((err f) (drive! (settled! srv slot provider "" startMs false) conn.fd (k (ch/outHttp (failureReply f)))))
    ((ok next)
      (if (u/upstreamCallOpen? next) (addConn srv conn.fd (connHttp next k slot provider startMs))
        (mt (u/upstreamCallFinish! next)
          ((ok resp) (drive! (settled! srv slot provider resp.body startMs true) conn.fd (k (ch/outHttp (ch/httpOk resp.status (list) resp.body)))))
          ((err f) (drive! (settled! srv slot provider "" startMs false) conn.fd (k (ch/outHttp (failureReply f)))))))))

fn ! stepConn! srv: GatewayLoop conn: GatewayConn ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (mt conn.phase
    ((connReading) (stepReading! srv conn ready))
    ((connHttp call k slot provider startMs) (stepHttp! srv conn call k slot provider startMs ready))
    ((connPool _ _) (loopConns srv (listAppend srv.conns (list conn))))
    ((connWarm slot provider sent timeout k deadline) (stepWarm! srv conn slot provider sent timeout k deadline))
    ((connProxy upstreamFd pending response) (stepProxy! srv conn upstreamFd pending response ready))
    ((connWriting data) (stepWriting! srv conn data ready)))

fn waitsFor? conn: GatewayConn requestId: Int64 -> Bool
  (mt conn.phase ((connPool id _) (= id requestId)) (_ false))

fn ! deliverReplies! srv: GatewayLoop -> GatewayLoop
  (mt (listHead srv.replies)
    ((none) srv)
    ((some reply)
      (let [(rest (loopPools srv srv.pools (optionOr (listTail srv.replies) (list))))
            (target (listHead (filter (fn [(cn GatewayConn)] -> Bool (waitsFor? cn reply.requestId)) rest.conns)))]
        (mt target
          ((none) (deliverReplies! rest))
          ((some conn)
            (let [(others (loopConns rest (filter (fn [(cn GatewayConn)] -> Bool (not (waitsFor? cn reply.requestId))) rest.conns)))]
              (mt conn.phase
                ((connPool _ k) (deliverReplies! (drive! others conn.fd (k (ch/outHttp (poolReplyHttp reply.result))))))
                (_ (deliverReplies! rest)))))))))

fn connWatch conn: GatewayConn -> (List (Pair Int64 Int64))
  (mt conn.phase
    ((connReading) (list (pair conn.fd 1)))
    ((connHttp call _ _ _ _) (u/upstreamCallWatch call))
    ((connPool _ _) (list))
    ((connWarm _ _ _ _ _ _) (list))
    ((connProxy upstreamFd pending _) (list (pair upstreamFd (if (stringEmpty? pending) 1 2))))
    ((connWriting _) (list (pair conn.fd 2))))

fn ! acceptReady! srv: GatewayLoop ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (if (not (readyOn? ready srv.listener)) srv
    (mt (sockAccept srv.listener)
      ((err e) (do (logLine! (str "(:gateway :acceptFailed \"" e "\")")) srv))
      ((ok fd)
        (mt (fdNonBlocking fd true)
          ((err e) (do (fdClose fd) (logLine! (str "(:gateway :acceptFailed \"" e "\")")) srv))
          ((ok _) (addConn srv fd connReading))))))

fn ! warmPolled! srv: GatewayLoop -> GatewayLoop
  (let [(polled (dp/pollSlots! srv.wiring (nowMs!)))]
    (do (fold (fn [(acc Bool) (line String)] -> Bool (logLine! line)) true (pairSecond polled))
      (loopWiring srv (pairFirst polled) srv.wiringText)))

fn parked? conn: GatewayConn -> Bool
  (mt conn.phase ((connWarm _ _ _ _ _ _) true) (_ false))

fn ! gatewayTurn! srv: GatewayLoop ready: (List (Pair Int64 Int64)) -> GatewayLoop
  (let [(polled (warmPolled! srv))
        (stepped (fold (fn [(acc GatewayLoop) (conn GatewayConn)] -> GatewayLoop (stepConn! acc conn ready))
                   (loopConns polled (list)) polled.conns))
        (advanced (pd/poolAdvance! stepped.pools ready stepped.env (nowMs!)))
        (pooled (loopPools stepped advanced.registry (listAppend stepped.replies advanced.replies)))]
    (acceptReady! (deliverReplies! pooled) ready))

fn ! gatewayEventLoop! srv: GatewayLoop -> (Result Int64 String)
  (let [(watch (listAppend (list (pair srv.listener 1))
                 (listAppend (fold (fn [(acc (List (Pair Int64 Int64))) (cn GatewayConn)] -> (List (Pair Int64 Int64)) (listAppend acc (connWatch cn))) (list) srv.conns)
                   (pd/poolWatch srv.pools))))
        (timeout (if (pd/poolActive? srv.pools) 10 (if (listAny? parked? srv.conns) 20 -1)))]
    (mt (fdPoll watch timeout)
      ((err e) (if (= e "interrupted") (gatewayEventLoop! srv) (err (str "gateway poll failed: " e))))
      ((ok ready) (gatewayEventLoop! (gatewayTurn! srv ready)))))

fn ! gatewayServe! listenerFd: Int64 upstreamPort: Int64 families: (List dp/LifecycleFamily) -> (Result Int64 String)
  (let [(env (u/envMapFromList (envList)))
        (root (optionOr (mapGet env "ASL_GATEWAY_ROOT") (optionOr (mapGet env "ROOT_DIR") (resultOr (realPath ".") "."))))
        (registryEnv (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))]
    (gatewayEventLoop! (GatewayLoop :listener listenerFd :upstreamPort upstreamPort :env env :home (optionOr (mapGet env "HOME") root)
      :rootDir root :registryPath (if (stringEmpty? registryEnv) (str root "/.asl/mem/calibration/index.asn") registryEnv)
      :promptMaxBytes (optionOr (stringToInt64 (optionOr (mapGet env "AGY_PROMPT_MAX_BYTES") "188000")) 188000)
      :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
      :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
      :wiring (dp/emptyWiring (resultOr (u/upstreamSettings env) (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0)))
      :wiringText none :families families :outbox (list))))


fn ! linkOpen! env: (Map String String) home: String rootDir: String families: (List dp/LifecycleFamily) -> (Result GatewayLoop String)
  (let [(registryEnv (optionOr (mapGet env "ASL_CALIBRATION_INDEX") ""))
        (registryPath (if (stringEmpty? registryEnv) (str rootDir "/.asl/mem/calibration/index.asn") registryEnv))
        (loaded (c/gatewayProfilesLoad! (c/emptyProfilesCache) home registryPath))
        (path (c/gatewayProfilesPath home))]
    (mt (pairSecond loaded)
      ((err e) (err e))
      ((ok table)
        (mt (u/upstreamSettings env)
          ((err e) (err e))
          ((ok settings)
            (let [(text (resultOr (fileReadString path) ""))]
              (mt (dp/wiringFromConfig (some table) text settings env families)
                ((err e) (err (str "gateway wiring: " e)))
                ((ok w)
                  (ok (GatewayLoop :listener -1 :upstreamPort 0 :env env :home home :rootDir rootDir :registryPath registryPath
                        :promptMaxBytes (optionOr (stringToInt64 (optionOr (mapGet env "AGY_PROMPT_MAX_BYTES") "188000")) 188000)
                        :conns (list) :pools (pd/poolWithPlugins (pd/emptyPoolRegistry) w.plugins) :replies (list) :breaker (b/defaultBreakerState)
                        :buckets (u/emptyBucketRegistry) :profiles (pairFirst loaded) :wiring w :wiringText (some text)
                        :families families :outbox (list)))))))))))

fn outboxFor srv: GatewayLoop fd: Int64 -> (Option String)
  (optionMap pairSecond (listHead (filter (fn [(x (Pair Int64 String))] -> Bool (= (pairFirst x) fd)) srv.outbox)))

fn withoutOutbox srv: GatewayLoop fd: Int64 -> GatewayLoop
  (with srv :outbox (filter (fn [(x (Pair Int64 String))] -> Bool (!= (pairFirst x) fd)) srv.outbox))

fn pending? srv: GatewayLoop fd: Int64 -> Bool
  (or (listAny? (fn [(cn GatewayConn)] -> Bool (= cn.fd fd)) srv.conns) (not (listEmpty? srv.replies)))

fn ! linkPump! srv: GatewayLoop fd: Int64 deadlineMs: Int64 -> (Pair GatewayLoop (Result String String))
  (mt (outboxFor srv fd)
    ((some data) (pair (withoutOutbox srv fd) (ok data)))
    ((none)
      (cond
        ((not (or (pending? srv fd) (pd/poolActive? srv.pools))) (pair srv (err "in-process gateway request ended without a response")))
        ((> (nowMs!) deadlineMs) (pair srv (err "in-process gateway request timed out")))
        (else
          (let [(watch (listAppend (fold (fn [(acc (List (Pair Int64 Int64))) (cn GatewayConn)] -> (List (Pair Int64 Int64)) (listAppend acc (connWatch cn))) (list) srv.conns)
                         (pd/poolWatch srv.pools)))
                (timeout (if (pd/poolActive? srv.pools) 10 (if (or (listEmpty? watch) (listAny? parked? srv.conns)) 20 1000)))]
            (mt (fdPoll watch timeout)
              ((err e) (if (= e "interrupted") (linkPump! srv fd deadlineMs) (pair srv (err (str "gateway poll failed: " e)))))
              ((ok ready) (linkPump! (gatewayTurn! srv ready) fd deadlineMs))))))))

fn ! linkSend! srv: GatewayLoop method: String path: String headers: (List (Pair String String)) body: String timeoutMs: Int64 -> (Pair GatewayLoop (Result String String))
  (let [(request (HttpRequest :method method :path path :headers headers :body body))
        (started (dispatch! (withoutOutbox srv (linkFd)) (linkFd) "" request))]
    (linkPump! started (linkFd) (+ (nowMs!) timeoutMs)))
