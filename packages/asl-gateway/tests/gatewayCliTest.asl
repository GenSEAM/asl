(module aslGateway/tests/gatewayCliTest
  :x [runTests main]
  :i [])

fn ! gatewayShellQuoteTail text: String index: Int64 -> String
  (if (>= index (stringLength text)) ""
    (let [(character (optionOr (stringSlice text index (+ index 1)) ""))]
      (str (if (= character "'") "'\\''" character)
           (gatewayShellQuoteTail text (+ index 1)))))

fn ! gatewayShellQuote text: String -> String
  (str "'" (gatewayShellQuoteTail text 0) "'")

fn ! gatewayInjectionRejected? runner: String temp: String upstream: String id: Int64 -> Bool
  (let [(pidDir (str temp "/inject-" (stringFromInt64 id)))
        (marker (str temp "/injection-" (stringFromInt64 id)))
        (run (processRun (str "HOME=" temp " ASL_GATEWAY_PID_DIR=" pidDir " " runner
                          " start --port 0 --upstream " (gatewayShellQuote upstream))))
        (cleanup (processRun (str "HOME=" temp " ASL_GATEWAY_PID_DIR=" pidDir " " runner " stop")))]
    (and (!= run.exitCode 0)
         (and (not (fileExists? marker)) (= cleanup.exitCode 0))))

fn ! cliRoot -> String
  (stringTrim (processRun "pwd").stdout)

fn ! cliInvoke command: String -> ProcessOutput
  (processRun (str "HOME=/dev/null " command))

fn ! testGatewayCliAndLifecycle -> Bool
  (let [(root (cliRoot))
        (host (str root "/asl/host/out/asl-host"))
        (runner (str root "/bin/asl-gateway"))
        (registry (str root "/.asl/mem/calibration/index.asn"))
        (temp (stringTrim (processRun "mktemp -d /tmp/asl-gateway-cli.XXXXXX").stdout))
        (injectionMarker (str temp "/shell-injection-ran"))
        (pathDir (str temp "/path"))
        (_path (processRun (str "/bin/mkdir -p " pathDir " && /bin/ln -sf /bin/bash " pathDir "/bash && /bin/ln -sf /usr/bin/dirname " pathDir "/dirname && /bin/ln -sf /usr/bin/basename " pathDir "/basename && /bin/ln -sf /bin/mkdir " pathDir "/mkdir")))
        (valid (str temp "/valid.asn"))
        (invalidA (str temp "/invalid-a.asn"))
        (invalidB (str temp "/invalid-b.asn"))
        (jsonPath (str temp "/convert.json"))
        (emojiPath (str temp "/emoji.json"))
        (delPath (str temp "/del.json"))
        (largePath (str temp "/large.json"))
        (numberCasesPath (str temp "/number-cases.json"))
        (duplicatePath (str temp "/duplicate.json"))
        (emptyPath (str temp "/empty.json"))
        (invalidUtf8Path (str temp "/invalid-utf8.asn"))
        (invalidContinuationPath (str temp "/invalid-continuation.asn"))
        (truncatedUtf8Path (str temp "/truncated-utf8.asn"))
        (topStringPath (str temp "/top-string.asn"))
        (v2Path (str temp "/v2.asn"))
        (unknownProviderPath (str temp "/unknown-provider.asn"))
        (registryOverride (str temp "/override-index.asn"))
        (_v (fileWrite valid "(:gateway :defaultProfile default :profiles ((:profile :id default :routes ((:intent any :models (\"model\"))))))\n"))
        (_a (fileWrite invalidA "(:gateway :v 1 :profiles ())\n"))
        (_b (fileWrite invalidB "(:gateway :v 1) (:gateway :v 1) (:gateway :v 1)\n"))
        (_j (fileWrite jsonPath "{\"nested\":{\"items\":[1,true,null,\"é\"]},\"value\":-2.5}\n"))
        (_emoji (fileWrite emojiPath "{\"value\":\"\\ud83d\\ude00\"}\n"))
        (_del (fileWrite delPath "{\"value\":\"\\u007f\"}\n"))
        (_large (fileWrite largePath "{\"value\":12345678901234567890123}\n"))
        (_numberCases (fileWrite numberCasesPath "{\"float\":1.0,\"exponent\":1e20,\"a\":12345678901234567890123,\"b\":12345678901234567890124}\n"))
        (_duplicate (fileWrite duplicatePath "{\"a\":1,\"a\":2}\n"))
        (_empty (fileWrite emptyPath ""))
        (_invalidUtf8 (processRun (str "printf '(:gateway :v 1)\\377(:gateway :v 1)' > " invalidUtf8Path)))
        (_v2 (fileWrite v2Path "(:gateway :v 2 :providers () :models () :intents () :profiles ())\n"))
        (_unknownProvider (fileWrite unknownProviderPath "(:gateway :v 2 :providers () :models ((:model :id m :provider p :name \"M\" :calibration \"absent-cal\")) :intents () :profiles ())\n"))
        (_topString (fileWrite topStringPath "\"(:gateway\"\n"))
        (_invalidContinuation (processRun (str "printf '(:gateway :v 1)\\303A' > " invalidContinuationPath)))
        (_truncatedUtf8 (processRun (str "printf '(:gateway :v 1)\\303' > " truncatedUtf8Path)))]
    (do
      (let [(python (processRun (str "PATH=" pathDir " command -v python3")))
            (run (processRun (str "PATH=" pathDir " ASL_GATEWAY_PORT=55231 " runner " status --port 55231")))]
        (assert (= python.exitCode 1) "runtime PATH has no python3")
        (assert (= run.exitCode 0) "gateway status runs with python3 absent from PATH"))
      (let [(run (cliInvoke (str runner " config check " valid)))
            (expected (str "(:configCheck :file \"" valid "\" :v 1 :registry \"" registry "\" :status :ok :errors () :warnings () :profiles 1)\n"))]
        (assert (= run.exitCode 0) "valid config exits zero")
        (assert (= run.stdout expected) "valid config stdout matches Python capture"))
      (let [(run (cliInvoke (str runner " config check " invalidA)))
            (expected (str "(:configCheck :file \"" invalidA "\" :v 1 :registry \"" registry "\" :status :error :errors (\":profiles must be a non-empty list of (:profile ...)\") :warnings ())\n"))]
        (assert (= run.exitCode 1) "invalid config A exits one")
        (assert (= run.stdout expected) "invalid config A stdout matches Python capture"))
      (let [(run (cliInvoke (str runner " config check " invalidB)))
            (expected (str "(:configCheck :file \"" invalidB "\" :v 0 :registry \"" registry "\" :status :error :errors (\"expected one (:gateway ...) form, found 3\") :warnings ())\n"))]
        (assert (= run.exitCode 1) "invalid config B exits one")
        (assert (= run.stdout expected) "invalid config B stdout matches Python capture"))
      (let [(run (cliInvoke (str runner " convert " jsonPath)))
            (out run.stdout)]
        (assert (= run.exitCode 0) "JSON conversion exits zero")
        (assert (= out "(:record :nested (:record :items [1 true nil \"\\u00e9\"]) :value -2.5)\n") "nested JSON, arrays, unicode, numbers and null match Python capture"))
      (let [(run (cliInvoke (str runner " convert " emojiPath)))]
        (assert (= run.stdout "(:record :value \"\\ud83d\\ude00\")\n") "non-BMP UTF-8 conversion matches Python surrogate escapes"))
      (let [(run (cliInvoke (str runner " convert " delPath)))]
        (assert (= run.stdout "(:record :value \"\\u007f\")\n") "DEL is escaped as Python JSON output"))
      (let [(run (cliInvoke (str runner " convert " duplicatePath)))]
        (assert (= run.stdout "(:record :a 2)\n") "duplicate JSON keys keep the last value like Python"))
      (let [(run (cliInvoke (str runner " convert " largePath)))]
        (assert (= run.stdout "(:record :value 12345678901234567890123)\n") "large integer matches Python exact integer output"))
      (let [(run (cliInvoke (str runner " convert " numberCasesPath)))
            (out run.stdout)]
        (assert (= out "(:record :float 1.0 :exponent 1e+20 :a 12345678901234567890123 :b 12345678901234567890124)\n") "float, exponent, and adjacent large integer tokens preserve Python number values"))
      (let [(run (cliInvoke (str runner " convert " emptyPath)))]
        (assert (= run.exitCode 1) "empty JSON file is rejected"))
      (let [(run (cliInvoke (str runner " config check " invalidUtf8Path)))
            (expected (str "(:configCheck :file \"" invalidUtf8Path "\" :v 0 :registry \"" registry "\" :status :error :errors (\"'utf-8' codec can't decode byte 0xff in position 15: invalid start byte\") :warnings ())\n"))]
        (assert (= run.exitCode 1) "invalid UTF-8 config is rejected")
        (assert (= run.stdout expected) "invalid UTF-8 receipt matches Python capture")
        (assert (= run.stderr "") "invalid UTF-8 diagnostics stay on the receipt channel"))
      (let [(run (cliInvoke (str runner " config check " invalidContinuationPath)))]
        (assert (= run.exitCode 1) "invalid UTF-8 continuation exits one")
        (assert (stringContains? run.stdout "invalid continuation byte") "invalid UTF-8 continuation matches Python's reason"))
      (let [(run (cliInvoke (str runner " config check " truncatedUtf8Path)))]
        (assert (= run.exitCode 1) "truncated UTF-8 exits one")
        (assert (stringContains? run.stdout "unexpected end of data") "truncated UTF-8 matches Python's reason"))
      (let [(run (cliInvoke (str runner " config check " topStringPath)))]
        (assert (stringContains? run.stdout "found '(:gateway'") "top-level string diagnostic reports its value"))
      (let [(run (processRun (str "ASL_CALIBRATION_INDEX=" registryOverride " " runner " config check " v2Path)))]
        (assert (stringContains? run.stdout registryOverride) "config check honours calibration registry override")
        (assert (stringContains? run.stdout ":v 2") "version-2 config fixture is checked"))
      (let [(run (cliInvoke (str runner " config check " unknownProviderPath)))]
        (assert (stringContains? run.stdout "model m: unknown provider p") "unknown provider is reported")
        (assert (not (stringContains? run.stdout "calibration absent-cal is not in the registry")) "unknown-provider calibration is not reported as a valid registry member")
        (assert (stringContains? run.stdout ":models 0") "unknown-provider model is excluded from effective models"))
      (gatewayLifecycleTest! root temp host runner)
      (let [(run (cliInvoke (str runner " status --port 55231")))]
        (assert (= run.exitCode 0) "offline status exits zero")
        (assert (stringContains? run.stdout "(:gateway :status :offline :port 55231)") "offline status is an ASL receipt"))
      (let [(run (cliInvoke (str "ASL_GATEWAY_PORT=55231 " runner)))]
        (assert (= run.exitCode 0) "no-argument status exits zero")
        (assert (= run.stdout "ASL Cognitive Gateway: OFFLINE (Port: 55231)\n") "no-argument status preserves the legacy output exactly"))
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1$touch " injectionMarker) 1) "dollar in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1;touch " injectionMarker) 2) "semicolon in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1|touch " injectionMarker) 3) "pipe in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1&touch " injectionMarker) 4) "ampersand in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1<" injectionMarker) 5) "less-than in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1>" injectionMarker) 6) "greater-than in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1(touch " injectionMarker " )") 7) "left parenthesis in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1)touch " injectionMarker) 8) "right parenthesis in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1\"touch " injectionMarker) 9) "double quote in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1' touch " injectionMarker) 10) "single quote in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1\ntouch " injectionMarker) 11) "newline in upstream is rejected before launch")
      (assert (gatewayInjectionRejected? runner temp (str "http://127.0.0.1:1 touch " injectionMarker) 12) "space in upstream is rejected before launch")
      true))

fn ! gatewayTestWriteAll! fd: Int64 data: String offset: Int64 -> (Result Bool String)
  (if (>= offset (stringLength data)) (ok true)
    (mt (fdWrite fd (optionOr (stringSlice data offset (stringLength data)) ""))
      ((err e) (err e))
      ((ok count) (if (<= count 0) (err "test socket write made no progress")
                   (gatewayTestWriteAll! fd data (+ offset count))))))

fn ! gatewayTestStub! portPath: String pidPath: String -> (Result Int64 String)
  (mt (fileWrite pidPath (stringFromInt64 (procSelf)))
    ((err e) (err e))
    ((ok _)
      (mt (tcpListen 0)
    ((err e) (err e))
    ((ok listenerFd)
      (mt (sockLocalPort listenerFd)
        ((err e) (do (fdClose listenerFd) (err e)))
        ((ok port)
          (mt (fileWrite portPath (stringFromInt64 port))
            ((err e) (do (fdClose listenerFd) (err e)))
            ((ok _)
              (mt (sockAccept listenerFd)
                ((err e) (do (fdClose listenerFd) (err e)))
                ((ok clientFd)
                  (mt (fdRead clientFd 65536)
                    ((err e) (do (fdClose clientFd) (fdClose listenerFd) (err e)))
                    ((ok _)
                      (let [(response (gatewayTestWriteAll! clientFd
                                      "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nupstream-ok" 0))]
                        (do (fdClose clientFd) (fdClose listenerFd)
                          (mt response
                            ((err e) (err e))
                            ((ok _) (ok 0)))))))))))))))))

fn ! gatewayTestStubMain args: (List String) -> (Result Int64 String)
  (if (= (optionOr (listGet args 0) "") "stub")
    (gatewayTestStub! (optionOr (listGet args 1) "") (optionOr (listGet args 2) ""))
    (ok 2))

fn gatewayTestReceiptNumber text: String marker: String -> Int64
  (mt (stringIndexOf text marker)
    ((none) 0)
    ((some at)
      (let [(start (+ at (stringLength marker)))
            (tail (optionOr (stringSlice text start (stringLength text)) ""))
            (space (stringIndexOf tail " "))
            (close (stringIndexOf tail ")"))
            (end (if (some? space) (optionOr space (stringLength tail))
                  (if (some? close) (optionOr close (stringLength tail)) (stringLength tail))))]
        (optionOr (stringToInt64 (optionOr (stringSlice tail 0 end) "")) 0))))

fn ! gatewayTestWaitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (mt (fileReadString path)
      ((err _) (do (sleepMs 20) (gatewayTestWaitPort! path (- attempts 1))))
      ((ok text)
        (let [(port (optionOr (stringToInt64 (stringTrim text)) 0))]
          (if (> port 0) port
            (do (sleepMs 20) (gatewayTestWaitPort! path (- attempts 1))))))))

fn ! gatewayTestWaitGone! pid: Int64 attempts: Int64 -> Bool
  (if (<= pid 1) true
    (let [(probe (processRun (str "/bin/kill -0 " (stringFromInt64 pid))))]
      (if (!= probe.exitCode 0) true
        (if (<= attempts 0) false
          (do (sleepMs 20) (gatewayTestWaitGone! pid (- attempts 1)))))))

fn ! gatewayTestReapStub! handle: Int64 pid: Int64 wait: (Result ProcessOutput String) -> (Result Int64 String)
  (mt wait
    ((err waitError)
      (mt (procKill pid "SIGTERM")
        ((err killError) (err (str "wait failed: " waitError "; kill failed: " killError)))
        ((ok _)
          (mt (processWait handle 10000)
            ((err reapError) (err (str "wait failed: " waitError "; reap failed: " reapError)))
            ((ok _) (ok 125))))))
    ((ok output) (ok output.exitCode)))

fn ! gatewayLifecycleTest! root: String temp: String host: String runner: String -> Bool
  (let [(home (str temp "/home"))
        (portPath (str temp "/upstream.port"))
        (stubPidPath (str temp "/upstream.pid"))
        (testFile (str root "/asl/packages/asl-gateway/tests/gatewayCliTest.asl"))
        (statePath (str home "/.asl/gateway.asn"))
        (stubStart (processSpawn (str host " run " testFile " stub " portPath " " stubPidPath)))
        (stubHandle (mt stubStart ((err _) 0) ((ok handle) handle)))
        (stubPid (gatewayTestWaitPort! stubPidPath 150))
        (upstreamPort (if (> stubHandle 0) (gatewayTestWaitPort! portPath 150) 0))
        (start (processRun (str "HOME=" home " " runner " start --port 0 --upstream http://127.0.0.1:" (stringFromInt64 upstreamPort))))
        (startState (resultOr (fileReadString statePath) ""))
        (startPid (gatewayTestReceiptNumber startState ":pid "))
        (restart (processRun (str "HOME=" home " " runner " restart")))
        (restartState (resultOr (fileReadString statePath) ""))
        (restartPid (gatewayTestReceiptNumber restartState ":pid "))
        (restartGone (gatewayTestWaitGone! startPid 150))
        (update (processRun (str "HOME=" home " " runner " update")))
        (updateState (resultOr (fileReadString statePath) ""))
        (updatePid (gatewayTestReceiptNumber updateState ":pid "))
        (updateGone (gatewayTestWaitGone! restartPid 150))
        (status (processRun (str "HOME=" home " " runner " status")))
        (statusText status.stdout)
        (serverPort (gatewayTestReceiptNumber statusText ":port "))
        (savedState (resultOr (fileReadString statePath) ""))
        (statusPid (gatewayTestReceiptNumber statusText ":pid "))
        (serverPid (if (> statusPid 1) statusPid (gatewayTestReceiptNumber savedState ":pid ")))
        (request (if (> serverPort 0)
                   (processRun (str "/usr/bin/curl --silent --show-error --max-time 5 http://127.0.0.1:" (stringFromInt64 serverPort) "/local-test"))
                   (processRun "/usr/bin/false")))
        (stop (processRun (str "HOME=" home " " runner " stop")))
        (gone (gatewayTestWaitGone! serverPid 150))
        (fallbackStop (if (and (> serverPid 1) (not gone))
                        (processRun (str "/bin/kill -TERM " (stringFromInt64 serverPid)))
                        (processRun "true")))
        (cleanupGone (if (> serverPid 1) (gatewayTestWaitGone! serverPid 150) true))
        (stubExit (if (> stubHandle 0)
                    (gatewayTestReapStub! stubHandle stubPid (processWait stubHandle 10000))
                    (err "spawn failed")))
        (failurePidPath (str temp "/failure.pid"))
        (failureStart (processSpawn (str "echo $$ > " failurePidPath " ; exec /bin/sleep 30")))
        (failureHandle (mt failureStart ((err _) 0) ((ok handle) handle)))
        (failurePid (gatewayTestWaitPort! failurePidPath 150))
        (failureWait (if (> failureHandle 0) (processWait failureHandle -1) (err "spawn failed")))
        (failureExit (if (> failureHandle 0)
                       (gatewayTestReapStub! failureHandle failurePid failureWait)
                       (err "spawn failed")))
        (failureGone (if (> failurePid 1) (gatewayTestWaitGone! failurePid 150) false))
        (failureReaped (if (> failureHandle 0) (processWait failureHandle 10000) (err "spawn failed")))
        (failureCleanup (if (and (> failurePid 1) (not failureGone))
                          (and (ok? (procKill failurePid "SIGKILL"))
                            (ok? (processWait failureHandle 10000)))
                          true))
        (removed (pathRemove temp))]
    (do
      (assert (> upstreamPort 0) "the ASL upstream binds an ephemeral loopback port")
      (assert (= start.exitCode 0) "gateway start launches the ASL server")
      (assert (and (= restart.exitCode 0) (stringContains? restart.stdout "(:gateway :status :restarted")) "restart replaces the running ASL server")
      (assert (and (> restartPid 1) (and restartGone (!= restartPid startPid))) "restart stops the prior process and preserves its service configuration")
      (assert (and (= update.exitCode 0) (stringContains? update.stdout "(:gateway :status :updated")) "update restarts the deployed ASL server")
      (assert (and (> updatePid 1) (and updateGone (!= updatePid restartPid))) "update replaces and stops the prior process")
      (assert (stringContains? statusText "(:gateway :status :running") "status reports the isolated gateway as running")
      (assert (and (> serverPort 0) (and (> serverPid 1) (stringContains? statusText (str ":port " (stringFromInt64 serverPort) " :pid " (stringFromInt64 serverPid))))) "running receipt exposes its actual ephemeral port and pid")
      (assert (and (= request.exitCode 0) (stringContains? request.stdout "upstream-ok")) "one local HTTP request reaches the ASL stub upstream")
      (assert (and (= stop.exitCode 0) (stringContains? stop.stdout "(:gateway :status :offline")) "stop reports the isolated service offline")
      (assert (and (= stop.exitCode 0) (and (> serverPid 1) gone)) "the gateway stop command itself leaves the process gone")
      (assert cleanupGone "test cleanup waits for any fallback-terminated gateway process")
      (assert (and (ok? stubExit) (= (resultOr stubExit -1) 0)) "the one-request ASL upstream process exits")
      (assert (err? failureWait) "negative processWait timeout produces a real wait error")
      (assert (and (ok? failureExit) (= (resultOr failureExit -1) 125)) "a failed upstream wait reports fallback only after successful kill and reap")
      (assert failureGone "a failed upstream wait terminates the spawned process")
      (assert (err? failureReaped) "fallback consumed the process handle by successfully reaping the child")
      (assert failureCleanup "failure-path fallback cleanup succeeds when still needed")
      (assert (ok? removed) "temporary gateway home and test fixtures are removed")
      true))

fn ! main args: (List String) -> (Result Int64 String)
  (gatewayTestStubMain args)

fn ! runTests -> Bool
  (testGatewayCliAndLifecycle)
