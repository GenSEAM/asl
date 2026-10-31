(module aslGateway/tests/serverKeyFilesSendTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (server :a srv) (aslGateway/config :a cfg)])

; (:m :ref GW-KEYFILES-SEND :do "a key held in a (:gateway :keyFiles) file wins over a stale process env value and is the bearer a real gateway sends; env-only and neither cases leave the env as it was")
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

fn requestLine head: String -> String
  (let [(parts (stringSplit (optionOr (listHead (stringSplit head "\r\n")) "") " "))]
    (str (optionOr (listGet parts 0) "") " " (optionOr (listGet parts 1) "")))

fn completeRow raw: String -> (Option String)
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (want (optionOr (stringToInt64 (headValue head "Content-Length")) 0))]
        (if (< (- (stringLength raw) (+ end 4)) want) none (some (str (requestLine head) "|" (headValue head "Authorization")))))))

fn reply status: Int64 reason: String body: String -> String
  (str "HTTP/1.1 " (stringFromInt64 status) " " reason "\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn stubReply row: String -> String
  (cond
    ((stringStartsWith? row "GET /v1/key|") (reply 500 "Internal Server Error" "{\"error\":\"down\"}"))
    ((stringStartsWith? row "GET /v1/credits|") (reply 200 "OK" "{\"balance\":\"95.50\",\"total_used\":\"4.50\"}"))
    (else (reply 200 "OK" "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"m-o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"served:m-o\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(x (Pair Int64 Int64))] -> Bool (= (pairFirst x) fd)) ready)

fn ! stepStub! live: Live stub: Stub ready: (List (Pair Int64 Int64)) -> Live
  (let [(keep (fn [(st Stub)] -> Live (with live :stubs (listAppend live.stubs (list st)))))]
    (if (not (ready? ready stub.fd)) (keep stub)
      (match (fdRead stub.fd 65536)
        ((err _) (do (fdClose stub.fd) live))
        ((ok chunk)
          (let [(input (str stub.input chunk))]
            (match (completeRow input)
              ((none) (if (stringEmpty? chunk) (do (fdClose stub.fd) live) (keep (with stub :input input))))
              ((some row) (do (writeAll! stub.fd (stubReply row)) (fdClose stub.fd) (with live :seen (listAppend live.seen (list row)))))))))))

fn ! stepLive! live: Live ready: (List (Pair Int64 Int64)) -> Live
  (let [(accepted (if (ready? ready live.listener)
                    (match (sockAccept live.listener)
                      ((ok fd) (with live :stubs (listAppend live.stubs (list (Stub :fd fd :input "")))))
                      ((err _) live))
                    live))]
    (fold (fn [(acc Live) (s Stub)] -> Live (stepStub! acc s ready))
      (with accepted :stubs (list)) accepted.stubs))

fn ! pump! live: Live client: Int64 untilMs: Int64 stopOnReply: Bool got: String -> (Pair Live String)
  (if (>= (nowMs!) untilMs) (pair live got)
    (let [(watch (listAppend (list (pair live.listener 1) (pair client 1)) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) live.stubs)))]
      (match (fdPoll watch 50)
        ((err _) (pump! live client untilMs stopOnReply got))
        ((ok ready)
          (let [(live2 (stepLive! live ready))
                (got2 (if (ready? ready client)
                        (match (fdRead client 65536) ((ok chunk) (str got chunk)) ((err _) got))
                        got))]
            (if (and stopOnReply (stringContains? got2 "served:")) (pair live2 got2)
              (pump! live2 client untilMs stopOnReply got2)))))))

fn ! waitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (match (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none)
      ((some port) (if (> port 0) port (do (sleepMs 40) (waitPort! path (- attempts 1)))))
      ((none) (do (sleepMs 40) (waitPort! path (- attempts 1))))))

fn ! scratch! -> String
  (let [(d (str "/tmp/gwKeySend-" (procSelf) "-" (nowNs)))
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

fn countOf rows: (List String) prefix: String -> Int64
  (listLength (filter (fn [(r String)] -> Bool (stringStartsWith? r prefix)) rows))

fn ! tableOf! keyFile: String -> (Result cfg/GatewayTable String)
  (cfg/gatewayConfigParse! (str "(:gateway :v 2 :keyFiles (\"" keyFile "\") :providers ((:provider :id kfp :kind openai :base \"http://127.0.0.1:1/v1\" :keyEnv KF_KEY)) :models ((:model :id mK :provider kfp :name \"m-k\" :tier free)) :profiles ((:profile :id default :routes ((:intent any :chain (mK))))) :uses ((:use :for default :profile default)))") "keySend" "absent.asn")

fn ! testOverlay! -> Bool
  (let [(dir (scratch!))
        (kf (str dir "/keys.env"))
        (_ (fileWrite kf "export KF_KEY=kfKey-NEW-1111\n"))
        (table (tableOf! kf))
        (stale (mapSet (mapEmpty) "KF_KEY" "envKey-STALE-0000"))
        (withFile (srv/keyFilesWorldEnv! table stale))
        (envOnly (srv/keyFilesWorldEnv! (tableOf! (str dir "/absent.env")) stale))
        (neither (srv/keyFilesWorldEnv! (tableOf! (str dir "/absent.env")) (mapEmpty)))
        (broken (srv/keyFilesWorldEnv! (err "no table") stale))
        (_2 (drop! dir))]
    (do
      (assert (= (mapGet withFile "KF_KEY") (some "kfKey-NEW-1111")) "the key file value wins over a stale env value")
      (assert (= (mapGet envOnly "KF_KEY") (some "envKey-STALE-0000")) "a key absent from the files keeps its env value")
      (assert (= (mapGet neither "KF_KEY") none) "a key in neither stays unset")
      (assert (= (mapGet broken "KF_KEY") (some "envKey-STALE-0000")) "an unloadable table leaves the env as it was")
      true))

fn ! runDirect! -> Bool
  (let [(dir (scratch!))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (keyFile (str dir "/keys.env"))
        (_ (fileWrite keyFile "export KF_KEY=kfKey-NEW-1111\n"))
        (cfg (str "(:gateway :v 2 :keyFiles (\"" keyFile "\") :providers ((:provider :id kfp :kind openai :base \"" base "/v1\" :keyEnv KF_KEY))"
                  " :models ((:model :id mK :provider kfp :name \"m-k\" :tier free))"
                  " :profiles ((:profile :id default :routes ((:intent any :chain (mK))))) :uses ((:use :for default :profile default)))\n"))
        (_2 (fileWrite (str dir "/.asl/gateway.asn") cfg))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream " base "/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") "KF_KEY=envKey-STALE-0000" (cacheEnvRow!))))
        (started (fr/guardStart! argv "." env (fr/limits 180 40)))]
    (match started
      ((err po) (do (fdClose listener) (drop! dir) (assert false (str "gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (waitPort! readyPath 750))
              (client (if (> port 0) (resultOr (tcpConnect port) -1) -1))
              (body "{\"messages\":[{\"role\":\"user\",\"content\":\"route me\"}]}")
              (sent (if (> client 0) (writeAll! client (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)) false))
              (first (pump! (Live :listener listener :stubs (list) :seen (list)) client (+ (nowMs!) 20000) true ""))
              (live (pairFirst first))
              (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
              (_3 (do (if (> client 0) (ok? (fdClose client)) true) (fdClose listener)))
              (err (resultOr (fileReadString (str dir "/gateway.err")) ""))
              (cleaned (drop! dir))]
          (do
            (assert (and (> port 0) sent) (str "gateway up and request sent: " err))
            (assert (= (countOf live.seen "POST /v1/chat/completions|Bearer kfKey-NEW-1111") 1) (str "the key file value, not the stale env value, is the bearer (Authorization redacted), stub saw " (stringFromInt64 (listLength live.seen)) " request(s)"))
            (assert (not (stringContains? (str err (pairSecond first)) "kfKey-NEW-1111")) "no log row or response prints the key")
            (assert killed "the gateway tree is stopped")
            (and killed cleaned))))))

fn ! testSubstituted! -> Bool
  (let [(dir (scratch!))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (keyFile (str dir "/keys.env"))
        (_ (fileWrite keyFile "export KF_KEY=kfKey-NEW-1111\n"))
        (cfg (str "(:gateway :v 2 :keyFiles (\"" keyFile "\") :providers ((:provider :id kfp :kind openai :base \"" base "/v1\" :keyEnv KF_KEY))"
                  " :models ((:model :id mK :provider kfp :name \"m-k\" :tier paid :budgets (kReq)) (:model :id mL :provider kfp :name \"m-l\" :tier free :budgets (kReq)))"
                  " :profiles ((:profile :id default :routes ((:intent any :chain (mK))))) :uses ((:use :for default :profile default))"
                  " :balancer (:balancer :mode free :exploreEvery 0 :cal () :ledger \"" dir "/calls.asn\" :budgets ((:budget :id kReq :window day :unit req :size 1000 :soft 100))))\n"))
        (_2 (fileWrite (str dir "/.asl/gateway.asn") cfg))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream " base "/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") "KF_KEY=envKey-STALE-0000" (cacheEnvRow!))))
        (started (fr/guardStart! argv "." env (fr/limits 180 40)))]
    (match started
      ((err po) (do (fdClose listener) (drop! dir) (assert false (str "gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (waitPort! readyPath 750))
              (client (if (> port 0) (resultOr (tcpConnect port) -1) -1))
              (body "{\"messages\":[{\"role\":\"user\",\"content\":\"route me\"}]}")
              (sent (if (> client 0) (writeAll! client (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)) false))
              (first (pump! (Live :listener listener :stubs (list) :seen (list)) client (+ (nowMs!) 20000) true ""))
              (live (pairFirst first))
              (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
              (_3 (do (if (> client 0) (ok? (fdClose client)) true) (fdClose listener)))
              (err (resultOr (fileReadString (str dir "/gateway.err")) ""))
              (cleaned (drop! dir))]
          (do
            (assert (and (> port 0) sent) (str "gateway up and request sent: " err))
            (assert (= (countOf live.seen "POST /v1/chat/completions|Bearer kfKey-NEW-1111") 1) (str "on the substituted dispatch path the key file value, not the stale env value, is the bearer (Authorization redacted), stub saw " (stringFromInt64 (listLength live.seen)) " request(s)"))
            (assert (not (stringContains? (str err (pairSecond first)) "kfKey-NEW-1111")) "no log row or response prints the key")
            (assert killed "the gateway tree is stopped")
            (and killed cleaned))))))

fn ! runTests -> Bool
  (let [(unit (testOverlay!))
        (direct (runDirect!))
        (subst (testSubstituted!))]
    (and unit (and direct subst)))
