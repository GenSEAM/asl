(module aslGateway/tests/federationPollTest
  :x [runTests]
  :i [(asl-tools/fleet/readyWait :a sk) (asl-tools/fleet/run :a fr)])

; (:m :ref GW-BALANCER-POLL-WIRE :do "a real gateway process with a balancer section and two polled endpoint budgets; after its first request the reactor must send each due poll as a GET with the poll provider's own key to the stub in this process, consume the reply (a 500 leaves one log note, a 200 none), poll each budget once inside its interval, and never print a key")
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
  (let [(d (str "/tmp/gwFedPoll-" (procSelf) "-" (nowNs)))
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
        (cfg (str "(:gateway :v 2 :providers ((:provider :id orx :kind openai :base \"" base "/v1\" :keyEnv ORX_KEY) (:provider :id vcl :kind openai :base \"" base "/v1\" :keyEnv VCL_KEY))"
                  " :models ((:model :id mO :provider orx :name \"m-o\" :tier paid :budgets (orUsd) :costMicros 100) (:model :id mV :provider vcl :name \"m-v\" :tier paid :budgets (vUsd) :costMicros 100))"
                  " :profiles ((:profile :id default :routes ((:intent any :chain (mO))))) :uses ((:use :for default :profile default))"
                  " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" dir "/calls.asn\" :budgets ("
                  "(:budget :id orUsd :window month :unit usd :size 10000000 :source endpoint :poll (:poll :provider orx :path \"/key\" :everyMs 60000))"
                  " (:budget :id vUsd :window month :unit usd :size 100000000 :source endpoint :poll (:poll :provider vcl :path \"/credits\" :everyMs 60000)))))\n"))
        (_ (fileWrite (str dir "/.asl/gateway.asn") cfg))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream " base "/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") "ORX_KEY=orKey-AAAA1111" "VCL_KEY=vclKey-BBBB2222" (cacheEnvRow!))))
        (started (fr/guardStart! argv "." env (fr/limits 180 40)))]
    (match started
      ((err po) (do (fdClose listener) (drop! dir) (assert false (str "gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (sk/waitPort! readyPath g.run.pid))
              (client (if (> port 0) (resultOr (tcpConnect port) -1) -1))
              (body "{\"messages\":[{\"role\":\"user\",\"content\":\"route me\"}]}")
              (sent (if (> client 0) (writeAll! client (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)) false))
              (first (pump! (Live :listener listener :stubs (list) :seen (list)) client (+ (nowMs!) 20000) true ""))
              (second (pump! (pairFirst first) client (+ (nowMs!) 6000) false (pairSecond first)))
              (live (pairFirst second))
              (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
              (_2 (do (if (> client 0) (ok? (fdClose client)) true) (fdClose listener)))
              (err (resultOr (fileReadString (str dir "/gateway.err")) ""))
              (cleaned (drop! dir))]
          (do
            (assert (and (> port 0) sent) (str "gateway up and request sent: " err))
            (assert (stringContains? (pairSecond first) "served:m-o") (str "the chat request is served: " (pairSecond first)))
            (assert (= (countOf live.seen "GET /v1/key|Bearer orKey-AAAA1111") 1) (str "the OpenRouter-shaped poll is sent once with its provider's key: " (stringJoin live.seen " ; ")))
            (assert (= (countOf live.seen "GET /v1/credits|Bearer vclKey-BBBB2222") 1) (str "the Vercel-shaped poll is sent once with its provider's key: " (stringJoin live.seen " ; ")))
            (assert (stringContains? err ":budget \"orUsd\" :note \"status poll for orUsd answered 500\"") (str "a 500 reply reaches poolPollReply and leaves a note: " err))
            (assert (not (stringContains? err ":budget \"vUsd\" :note")) "a 200 reply is consumed without a note")
            (assert (not (stringContains? err "orKey-AAAA1111")) "no log row prints the OpenRouter key")
            (assert (not (stringContains? err "vclKey-BBBB2222")) "no log row prints the Vercel key")
            (assert killed "the gateway tree is stopped")
            (and killed cleaned))))))
