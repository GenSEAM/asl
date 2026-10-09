(module asl/agentLoop/tests/gatewayLinkTest
  :x [runTests]
  :i [])

fn config base: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       " :endpoints [(:endpoint :id \"epA\" :provider \"fixa\" :model \"chat-a\" :pricePerMillion 1000000 :maxConcurrency 2)]"
       " :router (:profile :rules [(:rule :id \"leon\" :intent \"auto\" :role \"\" :costWeight 1 :waitWeight 0 :qualityWeight 0 :maxWaitMs 1000"
       " :candidates [(:candidate :endpoint \"epA\" :model \"chat-a\" :weight 1)])])"
       " :budget (:budgetConfig :lines [(:line :id \"aDay\" :scope :endpoint :key \"epA\" :period :day :cap 100000 :approved false)] :approvals []))\n")

(schema Seen
  (:f path String)
  (:f body String))

(schema Stub
  (:f fd Int64)
  (:f input String))

(schema Pump
  (:f listener Int64)
  (:f stubs (List Stub))
  (:f seen (List Seen)))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(x (Pair Int64 Int64))] -> Bool (= (pairFirst x) fd)) ready)

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (mt (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn headValue head: String name: String -> String
  (fold (fn [(acc String) (line String)] -> String
          (if (stringStartsWith? (stringLower line) (str (stringLower name) ":"))
            (stringTrim (optionOr (stringSlice line (+ (stringLength name) 1) (stringLength line)) "")) acc))
    "" (stringSplit head "\r\n"))

fn parseStub raw: String -> (Option Seen)
  (mt (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (want (optionOr (stringToInt64 (headValue head "Content-Length")) 0))
            (start (+ end 4))]
        (if (< (- (stringLength raw) start) want) none
          (some (Seen :path (optionOr (listGet (stringSplit (optionOr (listHead (stringSplit head "\r\n")) "") " ") 1) "")
                  :body (optionOr (stringSlice raw start (+ start want)) "")))))))

fn completion -> String
  (let [(body "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"chat-a\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"(:done :summary \\\"linked\\\")\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":400,\"completion_tokens\":600,\"total_tokens\":1000}}")]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn ! stepStub! r: Pump stub: Stub ready: (List (Pair Int64 Int64)) -> Pump
  (let [(keep (fn [(s Stub)] -> Pump (with r :stubs (listAppend r.stubs (list s)))))]
    (if (not (ready? ready stub.fd)) (keep stub)
      (mt (fdRead stub.fd 65536)
        ((err _) (do (fdClose stub.fd) r))
        ((ok chunk)
          (let [(input (str stub.input chunk))]
            (mt (parseStub input)
              ((none) (if (stringEmpty? chunk) (do (fdClose stub.fd) r) (keep (with stub :input input))))
              ((some seen)
                (do (writeAll! stub.fd (completion)) (fdClose stub.fd)
                  (with r :seen (listAppend r.seen (list seen)))))))))))

fn ! stepPump! r: Pump ready: (List (Pair Int64 Int64)) -> Pump
  (let [(accepted (if (ready? ready r.listener)
                    (mt (sockAccept r.listener)
                      ((ok fd) (with r :stubs (listAppend r.stubs (list (Stub :fd fd :input "")))))
                      ((err _) r))
                    r))]
    (fold (fn [(acc Pump) (s Stub)] -> Pump (stepStub! acc s ready))
      (Pump :listener accepted.listener :stubs (list) :seen accepted.seen) accepted.stubs))

fn ! pumpUntilExit! r: Pump pid: Int64 deadline: Int64 -> (Pair Pump Int64)
  (mt (optionOr (resultToOption (procWaitPid pid true)) none)
    ((some code) (pair r code))
    ((none) (if (>= (nowMs!) deadline) (do (procKill pid "SIGTERM") (procWaitPid pid false) (pair r -1))
         (let [(watch (listAppend (list (pair r.listener 1)) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) r.stubs)))]
           (mt (fdPoll watch 20)
             ((err _) (pumpUntilExit! r pid deadline))
             ((ok ready) (pumpUntilExit! (stepPump! r ready) pid deadline)))))))

fn ! waitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (mt (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none)
      ((some port) (if (> port 0) port (do (sleepMs 20) (waitPort! path (- attempts 1)))))
      ((none) (do (sleepMs 20) (waitPort! path (- attempts 1))))))

fn ! spawnSh! command: String env: (List String) -> Int64
  (mt (procSpawnv (list "/bin/sh" "-c" command) (none) (some env)) ((ok sp) sp.pid) ((err _) 0))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn rowsOf log: String -> (List String)
  (filter (fn [(l String)] -> Bool (or (stringStartsWith? l "(:gateway :route") (stringStartsWith? l "(:gateway :charge"))) (stringSplit log "\n"))

fn bodyAt seen: (List Seen) i: Int64 -> String
  (optionOr (optionMap (fn [(s Seen)] -> String s.body) (listGet seen i)) "")

fn ! runTests -> Bool
  (let [(temp (stringTrim (processRun "/usr/bin/mktemp -d /tmp/gatewayLinkTest.XXXXXX").stdout))
        (bare (str temp "/bare"))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (wrote (and (ok? (dirCreate (str temp "/.asl"))) (and (ok? (fileWrite (str temp "/.asl/gateway.asn") (config base))) (and (ok? (dirCreate (str temp "/work"))) (ok? (dirCreate bare))))))
        (host (resultOr (procExePath) ""))
        (server (resultOr (realPath "asl/packages/asl-gateway/src/server.asl") ""))
        (driver (resultOr (realPath "asl/agentLoop/tests/gatewayLinkDriver.asl") ""))
        (common (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
                      (str "ASL_CALIBRATION_INDEX=" temp "/absent.asn") "FIXA_KEY=aKey" (str "TMPDIR=" temp)))
        (gwPid (spawnSh! (str "exec " host " run " server " serve --port 0 --upstream " base "/v1 --ready " temp "/ready 2>" temp "/gateway.err") common))
        (gwPort (if (> gwPid 0) (waitPort! (str temp "/ready") 500) 0))
        (url (str "http://127.0.0.1:" (stringFromInt64 gwPort) "/v1/chat/completions"))
        (httpPid (spawnSh! (str "exec " host " run " driver " " temp "/work >" temp "/http.out 2>" temp "/http.err") (listAppend common (list (str "ASL_GATEWAY_URL=" url)))))
        (httpRun (pumpUntilExit! (Pump :listener listener :stubs (list) :seen (list)) httpPid (+ (nowMs!) 60000)))
        (gwKilled (if (> gwPid 0) (do (procKill (- 0 gwPid) "SIGTERM") (procWaitPid gwPid false) true) false))
        (linkPid (spawnSh! (str "exec " host " run " driver " " temp "/work >" temp "/link.out 2>" temp "/link.err") common))
        (linkRun (pumpUntilExit! (pairFirst httpRun) linkPid (+ (nowMs!) 60000)))
        (barePid (spawnSh! (str "exec " host " run " driver " " temp "/work >" temp "/bare.out 2>" temp "/bare.err")
                   (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" bare) (str "TMPDIR=" temp))))
        (bareRun (pumpUntilExit! (pairFirst linkRun) barePid (+ (nowMs!) 60000)))
        (closed (do (fdClose listener) true))
        (seen (pairFirst bareRun).seen)
        (httpOut (stringSplit (stringTrim (readOr (str temp "/http.out"))) "\n"))
        (linkOut (stringSplit (stringTrim (readOr (str temp "/link.out"))) "\n"))
        (gwRows (rowsOf (readOr (str temp "/gateway.err"))))
        (linkRows (rowsOf (readOr (str temp "/link.err"))))
        (bareOut (readOr (str temp "/bare.out")))
        (diag (str " http.err=" (readOr (str temp "/http.err")) " link.err=" (readOr (str temp "/link.err")) " gateway.err=" (readOr (str temp "/gateway.err"))))
        (removed (= (processRun (str "/bin/rm -rf " temp)).exitCode 0))]
    (do
      (assert (and wrote (> gwPort 0)) (str "the HTTP gateway serves on a free port" diag))
      (assert (and (= (pairSecond httpRun) 0) (= (pairSecond linkRun) 0)) (str "both drivers finish: http " (stringFromInt64 (pairSecond httpRun)) " link " (stringFromInt64 (pairSecond linkRun)) diag))
      (assert (= (listLength seen) 2) (str "each path reaches the fixture upstream once, the config-less run never: " (stringFromInt64 (listLength seen)) diag))
      (assert (and (= (optionOr (listGet seen 0) (Seen :path "" :body "")).path "/v1/chat/completions") (= (optionOr (listGet seen 1) (Seen :path "" :body "")).path "/v1/chat/completions")) "both paths call the upstream's chat endpoint")
      (assert (and (not (stringEmpty? (bodyAt seen 0))) (= (bodyAt seen 0) (bodyAt seen 1))) (str "the model request bodies are byte-identical: " (bodyAt seen 0) " vs " (bodyAt seen 1)))
      (assert (stringStartsWith? (optionOr (listHead httpOut) "") "(:receipt :reply \"(:done :summary \\\"linked\\\")\" :usage (") (str "the HTTP turn's receipt carries the reply and usage: " (optionOr (listHead httpOut) "")))
      (assert (= (listHead httpOut) (listHead linkOut)) (str "the receipts are identical: " (optionOr (listHead httpOut) "") " vs " (optionOr (listHead linkOut) "")))
      (assert (= (listGet linkOut 1) (some "(:link :spent 1000)")) (str "the in-process link charged its own ledger: " (optionOr (listGet linkOut 1) "")))
      (assert (= (listGet httpOut 1) (some "(:link none)")) "the HTTP run holds no link")
      (assert (= gwRows (list "(:gateway :route :rule \"leon\" :candidates (\"epA\") :pick \"epA\" :refused () :model \"chat-a\" :admission admitNow :budget allow)"
                              "(:gateway :charge :endpoint \"epA\" :tokens 1000 :cost 1000 :status charged)"))
        (str "the HTTP gateway logs one decision and one charge row: " (stringJoin gwRows " | ")))
      (assert (= linkRows gwRows) (str "the in-process link logs the same decision and charge rows: " (stringJoin linkRows " | ")))
      (assert (stringContains? bareOut "(:error ERR_GATEWAY_CONFIG") (str "an in-process run without a config fails typed, with no HTTP fallback: " bareOut))
      (and gwKilled (and closed removed))))
