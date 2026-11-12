(module aslGateway/tests/federationLiveTest
  :x [runTests]
  :i [(aslGateway/tests/gatewayStartKit :a sk) (federation :a f) (secrets :a s) (upstream :a u) (asl-tools/fleet/run :a fr)])

; (:m :ref GW-FED-REAL-INSTANCE :do "a real asl-gateway process (the host side) serves on a loopback port with a gatewayServeToken in its HOME's secrets file and one provider pointing at a stub API in this process; the VPS side is federation's remote provider with its own secrets store; one thread drives the client call, the stub and nothing else, every wait is bounded and the child dies with its tree")
(schema Stub (:f fd Int64) (:f input String))
(schema Live (:f listener Int64) (:f stubs (List Stub)) (:f seen (List String)))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn headValue head: String name: String -> String
  (fold (fn [(acc String) (line String)] -> String
          (if (stringStartsWith? (stringLower line) (str (stringLower name) ":"))
            (stringTrim (optionOr (stringSlice line (+ (stringLength name) 1) (stringLength line)) "")) acc))
    "" (stringSplit head "\r\n"))

fn completeAuth raw: String -> (Option String)
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (want (optionOr (stringToInt64 (headValue head "Content-Length")) 0))]
        (if (< (- (stringLength raw) (+ end 4)) want) none (some (headValue head "Authorization"))))))

fn completion -> String
  (let [(body "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"chat-a\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"served:chat-a\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(x (Pair Int64 Int64))] -> Bool (= (pairFirst x) fd)) ready)

fn ! stepStub! live: Live stub: Stub ready: (List (Pair Int64 Int64)) -> Live
  (let [(keep (fn [(st Stub)] -> Live (with live :stubs (listAppend live.stubs (list st)))))]
    (if (not (ready? ready stub.fd)) (keep stub)
      (match (fdRead stub.fd 65536)
        ((err _) (do (fdClose stub.fd) live))
        ((ok chunk)
          (let [(input (str stub.input chunk))]
            (match (completeAuth input)
              ((none) (if (stringEmpty? chunk) (do (fdClose stub.fd) live) (keep (with stub :input input))))
              ((some auth) (do (writeAll! stub.fd (completion)) (fdClose stub.fd) (with live :seen (listAppend live.seen (list auth)))))))))))

fn ! stepLive! live: Live ready: (List (Pair Int64 Int64)) -> Live
  (let [(accepted (if (ready? ready live.listener)
                    (match (sockAccept live.listener)
                      ((ok fd) (with live :stubs (listAppend live.stubs (list (Stub :fd fd :input "")))))
                      ((err _) live))
                    live))]
    (fold (fn [(acc Live) (s Stub)] -> Live (stepStub! acc s ready))
      (with accepted :stubs (list)) accepted.stubs))

fn ! drive! live: Live call: u/UpstreamCall deadline: Int64 -> (Pair Live u/UpstreamCall)
  (if (or (not (u/upstreamCallOpen? call)) (>= (nowMs!) deadline)) (pair live call)
    (let [(watch (listAppend (listAppend (list (pair live.listener 1)) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) live.stubs)) (u/upstreamCallWatch call)))]
      (match (fdPoll watch 50)
        ((err _) (drive! live call deadline))
        ((ok ready)
          (let [(live2 (stepLive! live ready))]
            (match (u/upstreamCallPump! call ready)
              ((err _) (pair live2 call))
              ((ok next) (drive! live2 next deadline))))))))

fn ! exchange! store: s/SecretStore host: String port: Int64 secret: String live: Live -> (Pair Live String)
  (let [(rg (f/RemoteGateway :id "mac" :base (str "http://127.0.0.1:" (stringFromInt64 port)) :secret secret))
        (env (mapFromPairs (list (pair "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin")))))
        (body "{\"messages\":[{\"role\":\"user\",\"content\":\"route me\"}]}")]
    (match (f/remoteStart! store rg body (list) env 30.0)
      ((err e) (pair live e))
      ((ok call)
        (let [(driven (drive! live call (+ (nowMs!) 20000)))]
          (pair (pairFirst driven) (f/remoteFinish! store rg (pairSecond driven) 5.0))))))

fn ! scratch! -> String
  (let [(d (str "/tmp/gwFedLive-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))
        (_2 (dirCreate (str d "/.asl")))]
    d)

fn ! drop! dir: String -> Bool
  (let [(sub (str dir "/.asl"))
        (_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str sub "/" n)))) (resultOr (dirList sub) (list))))
        (_2 (pathRemove sub))
        (_3 (map (fn [(n String)] -> Bool (ok? (pathRemove (str dir "/" n)))) (resultOr (dirList dir) (list))))]
    (ok? (pathRemove dir)))

fn ! cacheEnvRow! -> String
  (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")))

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))

fn ! settle! g: fr/Guarded tries: Int64 -> Bool
  (let [(st (fr/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (if (<= tries 0) false (do (fdPoll (fr/guardFds st.guard) 20) (settle! st.guard (- tries 1)))))))

fn ! writeSecretsFile! path: String text: String -> Bool
  (do (fileWrite path text) (fileChmod path 384) true)

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (cfg (str "(:gateway :v 2 :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY)) :models ((:model :id mA :provider fixa :name \"chat-a\")) :profiles ((:profile :id default :routes ((:intent any :chain (mA))))) :uses ((:use :for default :profile default)))\n"))
        (_ (fileWrite (str dir "/.asl/gateway.asn") cfg))
        (_2 (writeSecretsFile! (str dir "/.asl/secrets.asn") "(:secret :id gatewayServeToken :value \"tok-SERVE-3c91ab07\")\n"))
        (clientFile (str dir "/client.asn"))
        (_3 (writeSecretsFile! clientFile "(:secret :id goodToken :value \"tok-SERVE-3c91ab07\")\n(:secret :id badToken :value \"tok-WRONG-8e22d4f1\")\n(:secret :id noToken :value \"\")\n"))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream " base "/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") "FIXA_KEY=aKey" (cacheEnvRow!))))
        (started (fr/guardStart! argv "." env (fr/limits 180 40)))]
    (match started
      ((err po) (do (fdClose listener) (drop! dir) (assert false (str "host gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (sk/waitPort! readyPath g.run.pid))
              (loaded (s/secretsLoad! clientFile))]
          (match loaded
            ((err e) (do (assert false (str "client secrets: " e)) false))
            ((ok store)
              (let [(live0 (Live :listener listener :stubs (list) :seen (list)))
                    (r1 (exchange! store (hostExe!) port "noToken" live0))
                    (r2 (exchange! store (hostExe!) port "badToken" (pairFirst r1)))
                    (r3 (exchange! store (hostExe!) port "goodToken" (pairFirst r2)))
                    (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
                    (_4 (fdClose listener))
                    (all (str (pairSecond r1) (pairSecond r2) (pairSecond r3)))
                    (seen (pairFirst r3))
                    (errText (resultOr (fileReadString (str dir "/gateway.err")) ""))
                    (cleaned (drop! dir))]
                (do
                  (assert (> port 0) (str "the host gateway wrote its ready file: " errText))
                  (assert (stringContains? (pairSecond r1) "ERR_REMOTE_HTTP") (str "no bearer is refused by the host gateway: " (pairSecond r1)))
                  (assert (stringContains? (pairSecond r1) ":status 401") "with a 401")
                  (assert (stringContains? (pairSecond r2) ":status 401") (str "a wrong bearer is refused with a 401: " (pairSecond r2)))
                  (assert (stringStartsWith? (pairSecond r3) "(:remoteReply :provider mac :status 200") (str "the right bearer reaches the stub API through the real gateway: " (pairSecond r3)))
                  (assert (stringContains? (pairSecond r3) "served:chat-a") "the reply is the stub's completion")
                  (assert (= seen.seen (list "Bearer aKey")) (str "only the authorised request reached the stub, with the host gateway's own provider key: " (stringJoin seen.seen ",")))
                  (assert (not (stringContains? all "tok-SERVE-3c91ab07")) "no receipt shows the serve token")
                  (assert (not (stringContains? all "tok-WRONG-8e22d4f1")) "no receipt shows the wrong token")
                  (assert killed "the gateway process tree is stopped")
                  (and killed cleaned)))))))))
