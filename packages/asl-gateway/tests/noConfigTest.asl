(module aslGateway/tests/noConfigTest
  :x [runTests]
  :i [(aslGateway/tests/gatewayStartKit :a sk) (aslGateway/config :a cfg) (asl-tools/fleet/run :a fr)])

(schema Probe
  (:f response String)
  (:f providerContact Bool))

fn writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((ok n) (and (> n 0) (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))
      ((err _) false)))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn ! testMissingConfig -> Bool
  (let [(path "/tmp/noConfigTest/.asl/gateway.asn")
        (loaded (cfg/gatewayProfilesLoadText! path false (err "not read") ""))
        (unreadable (cfg/gatewayProfilesLoadText! path true (err "permission denied") ""))
        (emptyRoutes (cfg/gatewayProfilesLoadText! path true
          (ok "(:gateway :profile default :profiles ((:profile :id default :routes ())))") ""))
        (emptyProfiles (cfg/gatewayProfilesLoadText! path true
          (ok "(:gateway :v 2 :models () :profiles () :uses ())") ""))]
    (do
      (assert (err? loaded) "missing config does not synthesize a builtin paid-provider route")
      (assert (match loaded ((err e) (and (stringContains? e "ERR_GATEWAY_NO_CONFIG") (stringContains? e path))) ((ok _) false)) "missing config error names its type and path")
      (assert (match unreadable ((err e) (and (stringContains? e "permission denied") (stringContains? e path))) ((ok _) false)) "unreadable config error names its path and the read cause (6e8ed4982)")
      (assert (match emptyRoutes ((err e) (and (stringContains? e "ERR_GATEWAY_NO_CONFIG") (stringContains? e path))) ((ok _) false)) (str "config with no routes fails closed with its type and path: " (match emptyRoutes ((err e) e) ((ok _) "accepted"))))
      (assert (match emptyProfiles ((err e) (and (stringContains? e "ERR_GATEWAY_NO_CONFIG") (stringContains? e path))) ((ok _) false)) "config with no profiles fails closed with its type and path")
      true))

fn ! readReply! fd: Int64 -> String
  (match (fdRead fd 8192)
    ((ok t) t)
    ((err _) ""))

fn ! probe! client: Int64 recorder: Int64 response: String providerContact: Bool attempts: Int64 -> Probe
  (if (or (<= attempts 0) (and (stringContains? response "\r\n\r\n") (or (stringContains? response "ERR_GATEWAY_NO_CONFIG") (stringContains? response "HTTP/1.1 400"))))
    (Probe :response response :providerContact providerContact)
    (match (fdPoll (list (pair client 1) (pair recorder 1)) 20)
      ((err _) (probe! client recorder response providerContact (- attempts 1)))
      ((ok ready)
        (let [(contact (ready? ready recorder))
              (accepted (if contact (match (sockAccept recorder) ((ok fd) (do (fdClose fd) true)) ((err _) false)) false))
              (chunk (if (ready? ready client) (readReply! client) ""))]
          (probe! client recorder (str response chunk) (or providerContact accepted) (- attempts 1))))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (processRun "/usr/bin/mktemp -d /tmp/noConfigTest.XXXXXX").stdout))
        (listenResult (tcpListen 0))
        (listener (match listenResult ((ok fd) fd) ((err _) -1)))
        (portResult (sockLocalPort listener))
        (providerPort (resultOr portResult 0))
        (socketDebug (str "listen=" (match listenResult ((ok fd) (stringFromInt64 fd)) ((err e) e)) " local=" (match portResult ((ok p) (stringFromInt64 p)) ((err e) e))))
        (host (hostExe!))
        (server (resultOr (realPath "asl/packages/asl-gateway/src/server.asl") ""))
        (readyPath (str temp "/ready"))
        (command (str "exec " host " run " server " serve --port 0 --upstream http://127.0.0.1:" (stringFromInt64 providerPort) "/v1 --ready " readyPath " 2>" temp "/gateway.err"))
        (env (listAppend (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
                   "OPENROUTER_API_KEY=fake-test-key" (str "OPENROUTER_BASE_URL=http://127.0.0.1:" (stringFromInt64 providerPort) "/v1")) (fr/cacheEnv!)))
        (spawned (procSpawnv (list "/bin/sh" "-c" command) (none) (some env)))
        (pid (match spawned ((ok sp) sp.pid) ((err _) 0)))
        (gatewayPort (if (> pid 0) (sk/waitPort! readyPath pid) 0))
        (clientRes (if (> gatewayPort 0) (tcpConnect gatewayPort) (err "no gateway")))
        (client (match clientRes ((ok fd) fd) ((err _) -1)))
        (body "{\"model\":\"x\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}]}")
        (request (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))
        (sent (and (> client 0) (writeAll! client request)))
        (probe (if sent (probe! client listener "" false 250) (Probe :response "" :providerContact false)))
        (killed (if (> pid 0) (do (procKill (- 0 pid) "SIGTERM") (procWaitPid pid false) true) false))
        (closed (do (if (> client 0) (do (fdClose client) true) false) (fdClose listener) true))
        (gatewayErr (resultOr (fileReadString (str temp "/gateway.err")) ""))
        (removed (= (processRun (str "/bin/rm -rf " temp)).exitCode 0))]
    (do
      (testMissingConfig)
      (assert (and sent (stringStartsWith? probe.response "HTTP/1.1 503")) (str "missing config must return HTTP 503, got " probe.response " providerPort=" (stringFromInt64 providerPort) " " socketDebug " command=" command " " gatewayErr))
      (assert (and (stringContains? probe.response "ERR_GATEWAY_NO_CONFIG") (stringContains? probe.response (str temp "/.asl/gateway.asn"))) "503 body names the typed error and config path")
      (assert (not probe.providerContact) "missing config must not connect to the local provider recorder")
      (assert (not (stringContains? gatewayErr "(:gateway :usage :provider ")) "missing config must not emit a provider usage attempt")
      (and killed (and closed removed))))

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))
