(module aslGateway/tests/serverKeyFilesTest
  :x [runTests]
  :i [(asl-tools/fleet/readyWait :a sk) (asl-tools/fleet/run :a fr)])

; (:m :ref GW-SERVE-KEYFILES :do "a real gateway whose only copy of a provider key is in a (:gateway :keyFiles) file sends that key as the bearer to the stub; the key is in no process env and no log")
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

fn ! scratch! -> String
  (let [(d (str "/tmp/gwKeyFiles-" (procSelf) "-" (nowNs)))
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

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (keyFile (str dir "/keys.env"))
        (_ (fileWrite keyFile "export KF_KEY=kfKey-EEEE5555\n"))
        (cfg (str "(:gateway :v 2 :keyFiles (\"" keyFile "\") :providers ((:provider :id kfp :kind openai :base \"" base "/v1\" :keyEnv KF_KEY))"
                  " :models ((:model :id mK :provider kfp :name \"m-k\" :tier free))"
                  " :profiles ((:profile :id default :routes ((:intent any :chain (mK))))) :uses ((:use :for default :profile default)))\n"))
        (_2 (fileWrite (str dir "/.asl/gateway.asn") cfg))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream " base "/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") (cacheEnvRow!))))
        (started (fr/guardStart! argv "." env (fr/limits 180 40)))]
    (match started
      ((err po) (do (fdClose listener) (drop! dir) (assert false (str "gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (sk/waitPort! readyPath g.run.pid))
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
            (assert (stringContains? (pairSecond first) "served:m-o") (str "the chat request is served: " (pairSecond first)))
            (assert (= (countOf live.seen "POST /v1/chat/completions|Bearer kfKey-EEEE5555") 1) (str "the key kept only in keyFiles is the bearer: " (stringJoin live.seen " ; ")))
            (assert (not (stringContains? (str err (pairSecond first)) "kfKey-EEEE5555")) "no log row or response prints the key")
            (assert killed "the gateway tree is stopped")
            (and killed cleaned))))))
