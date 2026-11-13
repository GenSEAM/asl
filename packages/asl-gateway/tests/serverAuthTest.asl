(module aslGateway/tests/serverAuthTest
  :x [runTests]
  :i [(asl-tools/fleet/readyWait :a sk) (asl-tools/fleet/run :a fr)])

; (:m :ref GW-SERVE-AUTH-HEALTH-EXEMPT :do "a real gateway whose secrets file is named by (:gateway :secretsFile) holds gatewayServeToken; GET /health answers 200 with status only and no bearer, every other path answers 401 without the bearer and passes the check with it; the token is read from the overridden path, so a server that ignored :secretsFile would answer 200 everywhere")
fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ! slurp! fd: Int64 tries: Int64 acc: String -> String
  (if (<= tries 0) acc
    (match (fdPoll (list (pair fd 1)) 100)
      ((err _) acc)
      ((ok ready)
        (if (listEmpty? ready) (slurp! fd (- tries 1) acc)
          (match (fdRead fd 65536)
            ((err _) acc)
            ((ok chunk) (if (stringEmpty? chunk) acc (slurp! fd (- tries 1) (str acc chunk)))))))))

fn ! ask! port: Int64 line: String auth: String -> String
  (let [(client (resultOr (tcpConnect port) -1))
        (_ (writeAll! client (str line " HTTP/1.1\r\nHost: 127.0.0.1\r\n" auth "Content-Length: 0\r\nConnection: close\r\n\r\n")))
        (out (slurp! client 100 ""))
        (_2 (fdClose client))]
    out)

fn ! scratch! -> String
  (let [(d (str "/tmp/gwSrvAuth-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))
        (_2 (dirCreate (str d "/.asl")))
        (_3 (dirCreate (str d "/elsewhere")))]
    d)

fn ! dropAll! dir: String -> Bool
  (let [(_ (map (fn [(sub String)] -> Bool (ok? (pathRemove (str dir "/" sub)))) (list ".asl/gateway.asn" ".asl/secrets.asn" "elsewhere/tokens.asn" "elsewhere" ".asl" "ready" "gateway.err")))]
    (ok? (pathRemove dir)))

fn ! settle! g: fr/Guarded tries: Int64 -> Bool
  (let [(st (fr/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (if (<= tries 0) false (do (fdPoll (fr/guardFds st.guard) 20) (settle! st.guard (- tries 1)))))))

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (_ (fileWrite (str dir "/.asl/gateway.asn") (str "(:gateway :v 2 :secretsFile \"" dir "/elsewhere/tokens.asn\" :providers () :models () :profiles () :uses ())\n")))
        (_2 (do (fileWrite (str dir "/elsewhere/tokens.asn") "(:secret :id gatewayServeToken :value \"srvTok-CCCC3333\")\n") (fileChmod (str dir "/elsewhere/tokens.asn") 384) true))
        (readyPath (str dir "/ready"))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (cache (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (argv (list "/bin/sh" "-c" (str "exec " host " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream http://127.0.0.1:9/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") cache)))]
    (match (fr/guardStart! argv "." env (fr/limits 120 40))
      ((err po) (do (dropAll! dir) (assert false (str "gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (sk/waitPort! readyPath g.run.pid))
              (health (if (> port 0) (ask! port "GET /health" "") ""))
              (models (if (> port 0) (ask! port "GET /v1/models" "") ""))
              (wrong (if (> port 0) (ask! port "GET /v1/models" "Authorization: Bearer nope\r\n") ""))
              (right (if (> port 0) (ask! port "GET /v1/models" "Authorization: Bearer srvTok-CCCC3333\r\n") ""))
              (post (if (> port 0) (ask! port "POST /v1/chat/completions" "") ""))
              (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
              (err (resultOr (fileReadString (str dir "/gateway.err")) ""))
              (cleaned (dropAll! dir))]
          (do
            (assert (> port 0) (str "the gateway came up: " err))
            (assert (stringStartsWith? health "HTTP/1.1 200") (str "/health answers 200 with no bearer: " health))
            (assert (stringContains? health "(:health :status ok)") (str "/health body is status only: " health))
            (assert (not (stringContains? health "provider")) "/health carries no provider data")
            (assert (stringStartsWith? models "HTTP/1.1 401") (str "another path without the bearer is 401: " models))
            (assert (stringStartsWith? wrong "HTTP/1.1 401") (str "a wrong bearer is 401: " wrong))
            (assert (stringStartsWith? post "HTTP/1.1 401") (str "a POST without the bearer is 401: " post))
            (assert (not (stringStartsWith? right "HTTP/1.1 401")) (str "the right bearer passes the check: " right))
            (assert (not (stringContains? (str health models wrong right post err) "srvTok-CCCC3333")) "no response or log prints the token")
            (assert killed "the gateway tree is stopped")
            (and killed cleaned))))))
