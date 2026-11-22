(module aslGateway/tests/hubRoutesLiveTest
  :x [runTests]
  :i [(asl-tools/fleet/readyWait :a sk) (asl-tools/fleet/run :a fr) (asl-json/json :a j) (aslGateway/server :a srv)])

; (:m :ref HUB-GETROUTES-WIRING :do "a real asl-gateway process, started through fleet/run guardStart with a timeout and a descendant limit on a free port, serves GET /v1/models, GET /api/asl/search and POST /api/asl/research; its --upstream is a dead port, so a route that fell through to the generic proxy answers 502. The searxng engine and the provider of the profile are this process's stub on loopback, never the network; every body is checked against what the stub and the config make only the real handlers able to say")
(schema Stub (:f fd Int64) (:f input String) (:f since Int64))
(schema Live (:f listener Int64) (:f stubs (List Stub)) (:f seen (List String)))
(schema Reply (:f live Live) (:f status Int64) (:f body String) (:f head String))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(x (Pair Int64 Int64))] -> Bool (= (pairFirst x) fd)) ready)

fn stubBody port: Int64 -> String
  (str "{\"results\":[{\"title\":\"Alpha rotor datasheet\",\"url\":\"http://127.0.0.1:" (stringFromInt64 port) "/page\",\"content\":\"torque of the alpha rotor\"}]}")

fn httpReply body: String -> String
  (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn requestLineOf raw: String -> String
  (optionOr (listHead (stringSplit raw "\r\n")) "")

fn slowHold -> Int64
  4000

; (:m :do "a request whose query says slow is held for slowHold ms before the stub answers, so a hub that serves it inline cannot answer anything else meanwhile")
fn ! stepStub! live: Live port: Int64 stub: Stub ready: (List (Pair Int64 Int64)) -> Live
  (let [(keep (fn [(st Stub)] -> Live (with live :stubs (listAppend live.stubs (list st)))))
        (got (if (and (not (stringContains? stub.input "\r\n\r\n")) (ready? ready stub.fd))
               (match (fdRead stub.fd 65536) ((err _) (none)) ((ok chunk) (if (stringEmpty? chunk) (none) (some (with stub :input (str stub.input chunk))))))
               (some stub)))]
    (match got
      ((none) (do (fdClose stub.fd) live))
      ((some s)
        (if (not (stringContains? s.input "\r\n\r\n")) (keep s)
          (let [(line (requestLineOf s.input))
                (held (and (stringContains? line "q=slow") (< (- (nowMs!) s.since) (slowHold))))]
            (if held (keep s)
              (do (writeAll! s.fd (httpReply (stubBody port))) (fdClose s.fd)
                  (with live :seen (listAppend live.seen (list line))))))))))

fn ! stepLive! live: Live port: Int64 ready: (List (Pair Int64 Int64)) -> Live
  (let [(accepted (if (ready? ready live.listener)
                    (match (sockAccept live.listener)
                      ((ok fd) (with live :stubs (listAppend live.stubs (list (Stub :fd fd :input "" :since (nowMs!))))))
                      ((err _) live))
                    live))]
    (fold (fn [(acc Live) (s Stub)] -> Live (stepStub! acc port s ready))
      (with accepted :stubs (list)) accepted.stubs))

; (:m :do "read the whole reply of one request while serving the stub: the server closes after its reply, so end of stream ends the read; the deadline bounds a server that never answers")
fn ! pump! live: Live port: Int64 client: Int64 acc: String deadline: Int64 -> (Pair Live String)
  (if (>= (nowMs!) deadline) (pair live acc)
    (let [(watch (listAppend (list (pair live.listener 1) (pair client 1)) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) live.stubs)))]
      (match (fdPoll watch 50)
        ((err _) (pump! live port client acc deadline))
        ((ok ready)
          (let [(live2 (stepLive! live port ready))]
            (if (not (ready? ready client)) (pump! live2 port client acc deadline)
              (match (fdRead client 65536)
                ((err e) (if (= e "wouldBlock") (pump! live2 port client acc deadline) (pair live2 acc)))
                ((ok chunk) (if (stringEmpty? chunk) (pair live2 acc) (pump! live2 port client (str acc chunk) deadline))))))))))

fn statusOf raw: String -> Int64
  (optionOr (stringToInt64 (optionOr (listGet (stringSplit (optionOr (listHead (stringSplit raw "\r\n")) "") " ") 1) "")) 0)

fn bodyOf raw: String -> String
  (match (stringIndexOf raw "\r\n\r\n")
    ((some at) (optionOr (stringSlice raw (+ at 4) (stringLength raw)) ""))
    ((none) ""))

fn ! call! live: Live port: Int64 gatewayPort: Int64 method: String target: String body: String -> Reply
  (match (tcpConnect gatewayPort)
    ((err _) (Reply :live live :status 0 :body "connect failed" :head ""))
    ((ok client)
      (let [(head (str method " " target " HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: application/json\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))
            (sent (writeAll! client head))
            (got (if sent (pump! live port client "" (+ (nowMs!) 90000)) (pair live "")))
            (_ (fdClose client))]
        (Reply :live (pairFirst got) :status (statusOf (pairSecond got)) :body (bodyOf (pairSecond got)) :head (pairSecond got)))))

(schema Overlap (:f live Live) (:f healthStatus Int64) (:f healthMs Int64) (:f slowMs Int64) (:f slowStatus Int64) (:f slowBody String))

fn ! pumpFor! live: Live port: Int64 until: Int64 -> Live
  (if (>= (nowMs!) until) live
    (let [(watch (cons (pair live.listener 1) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) live.stubs)))]
      (match (fdPoll watch 50)
        ((err _) (pumpFor! live port until))
        ((ok ready) (pumpFor! (stepLive! live port ready) port until)))))

; (:m :do "a search that the stub holds for four seconds is in flight while GET /health is asked: a hub that ran the search in its own poll loop answers /health only when the search is over")
fn ! overlap! live: Live port: Int64 gatewayPort: Int64 -> Overlap
  (match (tcpConnect gatewayPort)
    ((err _) (Overlap :live live :healthStatus 0 :healthMs 0 :slowMs 0 :slowStatus 0 :slowBody "connect failed"))
    ((ok slow)
      (let [(t0 (nowMs!))
            (sent (writeAll! slow "GET /api/asl/search?q=slow&engine=searxng&limit=2 HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: application/json\r\nConnection: close\r\n\r\n"))
            (live1 (pumpFor! live port (+ (nowMs!) 800)))
            (t1 (nowMs!))
            (health (call! live1 port gatewayPort "GET" "/health" ""))
            (t2 (nowMs!))
            (done (pump! health.live port slow "" (+ (nowMs!) 90000)))
            (t3 (nowMs!))
            (_ (fdClose slow))]
        (Overlap :live (pairFirst done) :healthStatus health.status :healthMs (- t2 t1) :slowMs (- t3 t0)
                 :slowStatus (statusOf (pairSecond done)) :slowBody (bodyOf (pairSecond done))))))

(schema Burst (:f live Live) (:f extraStatus Int64) (:f extraHead String) (:f firstStatus Int64) (:f secondStatus Int64))

fn slowRequest q: String -> String
  (str "GET /api/asl/search?q=" q "&engine=searxng&limit=2 HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: application/json\r\nConnection: close\r\n\r\n")

fn descendantsOf snap: (List fr/Proc) known: (List Int64) -> (List Int64)
  (let [(next (map (fn [(p fr/Proc)] -> Int64 p.pid) (filter (fn [(p fr/Proc)] -> Bool (and (listContains? known p.ppid) (not (listContains? known p.pid)))) snap)))]
    (if (listEmpty? next) known (descendantsOf snap (listAppend known next))))

; (:m :do "the live processes below the hub: its job children and their curl, counted from the process snapshot")
fn ! countJobs! hub: Int64 -> Int64
  (- (listLength (descendantsOf (fr/procSnapshot) (list hub))) 1)

; (:m :do "a caller that hangs up on a running job has the child's tree killed: the job count is 1 while it runs and 0 a moment after the hang-up, long before the stub would have answered")
fn ! hangUp! live: Live port: Int64 gatewayPort: Int64 hub: Int64 -> (Pair Live (Pair Int64 Int64))
  (match (tcpConnect gatewayPort)
    ((err _) (pair live (pair -1 -1)))
    ((ok c)
      (let [(base (countJobs! hub))
            (sent (writeAll! c (slowRequest "slowgone")))
            (live1 (pumpFor! live port (+ (nowMs!) 800)))
            (running (- (countJobs! hub) base))
            (_ (fdClose c))
            (live2 (pumpFor! live1 port (+ (nowMs!) 1500)))]
        (pair live2 (pair running (- (countJobs! hub) base))))))

; (:m :do "hubJobMax is 2 in the fixture config: two held searches fill it and a third request is a 429 with Retry-After while they run; both held ones are still answered")
fn ! burst! live: Live port: Int64 gatewayPort: Int64 -> Burst
  (match (tcpConnect gatewayPort)
    ((err _) (Burst :live live :extraStatus 0 :extraHead "" :firstStatus 0 :secondStatus 0))
    ((ok a)
      (match (tcpConnect gatewayPort)
        ((err _) (Burst :live live :extraStatus 0 :extraHead "" :firstStatus 0 :secondStatus 0))
        ((ok b)
          (let [(sa (writeAll! a (slowRequest "slowa")))
                (sb (writeAll! b (slowRequest "slowb")))
                (live1 (pumpFor! live port (+ (nowMs!) 800)))
                (extra (call! live1 port gatewayPort "GET" "/api/asl/search?q=x&engine=searxng" ""))
                (da (pump! extra.live port a "" (+ (nowMs!) 90000)))
                (db (pump! (pairFirst da) port b "" (+ (nowMs!) 90000)))
                (_ (fdClose a))
                (_2 (fdClose b))]
            (Burst :live (pairFirst db) :extraStatus extra.status :extraHead extra.head :firstStatus (statusOf (pairSecond da)) :secondStatus (statusOf (pairSecond db))))))))

fn ! scratch! -> String
  (let [(d (str "/tmp/gwHubRoutes-" (procSelf) "-" (nowNs)))
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

fn jsonOf text: String -> j/Json
  (resultOr (j/jsonParse text) (j/jnull))

fn jtext v: j/Json key: String -> String
  (match (optionOr (j/jsonGet v key) (j/jnull)) ((j/jstr s) s) (_ ""))

fn firstResultUrl v: j/Json -> String
  (match (optionOr (j/jsonGet v "results") (j/jnull))
    ((j/jarr xs) (match (listHead xs) ((some r) (jtext r "url")) ((none) "")))
    (_ ""))

fn modelIds v: j/Json -> (List String)
  (match (optionOr (j/jsonGet v "data") (j/jnull))
    ((j/jarr xs) (map (fn [(m j/Json)] -> String (jtext m "id")) xs))
    (_ (list)))

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (cfg (str "(:gateway :v 2 :profile default :hubJobMax 2 :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY)) :models ((:model :id mA :provider fixa :name \"chat-a\")) :intents ((:intent :id chat) (:intent :id research)) :profiles ((:profile :id default :routes ((:intent any :chain (mA)) (:intent chat :chain (mA)) (:intent research :chain (mA))))) :uses ((:use :for default :profile default)))\n"))
        (_ (fileWrite (str dir "/.asl/gateway.asn") cfg))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream http://127.0.0.1:1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") "FIXA_KEY=aKey" (str "SEARXNG_URL=" base) (cacheEnvRow!))))
        (started (fr/guardStart! argv "." env (fr/limits 240 40)))]
    (match started
      ((err po) (do (fdClose listener) (drop! dir) (assert false (str "hub gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (sk/waitPort! readyPath g.run.pid))
              (live0 (Live :listener listener :stubs (list) :seen (list)))
              (models (call! live0 stubPort port "GET" "/v1/models" ""))
              (search (call! models.live stubPort port "GET" "/api/asl/search?q=x&engine=searxng&limit=2" ""))
              (research (call! search.live stubPort port "POST" "/api/asl/research" "{\"topic\":\"alpha rotor torque\",\"depth\":\"flash\"}"))
              (pinned (call! research.live stubPort port "POST" "/api/asl/research" "{\"topic\":\"alpha rotor torque\",\"depth\":\"flash\",\"model\":\"mA\"}"))
              (unknown (call! pinned.live stubPort port "POST" "/api/asl/research" "{\"topic\":\"alpha rotor torque\",\"model\":\"nonesuch\"}"))
              (noTopic (call! unknown.live stubPort port "POST" "/api/asl/research" "{\"depth\":\"flash\"}"))
              (gone (hangUp! noTopic.live stubPort port g.run.pid))
              (burst (burst! (pairFirst gone) stubPort port))
              (busy (overlap! burst.live stubPort port))
              (keyRows (srv/hubKeyRows (list "FIXA_KEY" "SYNTHETIC_API_KEY" "NOPE") (mapFromPairs (list (pair "FIXA_KEY" "aKey") (pair "OTHER_API_KEY" "x") (pair "SSH_AUTH_SOCK" "s")))))
              (seen busy.live.seen)
              (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
              (_4 (fdClose listener))
              (errText (resultOr (fileReadString (str dir "/gateway.err")) ""))
              (cleaned (drop! dir))
              (mj (jsonOf models.body))
              (sj (jsonOf search.body))
              (rj (jsonOf research.body))
              (pj (jsonOf pinned.body))]
          (do
            (assert (> port 0) (str "the hub gateway wrote its ready file: " errText))
            (assert (= models.status 200) (str "GET /v1/models answers 200 and not the dead upstream's 502: " (stringFromInt64 models.status) " " models.body))
            (assert (= (jtext mj "object") "list") (str "the model list is an OpenAI list object: " models.body))
            (assert (listContains? (modelIds mj) "mA") (str "the list carries the alias of the profile in the config file: " models.body))
            (assert (= search.status 200) (str "GET /api/asl/search answers 200: " (stringFromInt64 search.status) " " search.body))
            (assert (= (firstResultUrl sj) (str base "/page")) (str "the result is the one the stub searxng returned: " search.body))
            (assert (listAny? (fn [(l String)] -> Bool (and (stringStartsWith? l "GET /search?q=x") (stringContains? l "format=json"))) seen) (str "the engine asked the stub with the query: " (stringJoin seen " | ")))
            (assert (= research.status 200) (str "POST /api/asl/research answers 200: " (stringFromInt64 research.status) " " research.body))
            (assert (= (jtext rj "topic") "alpha rotor torque") (str "the receipt carries the topic: " research.body))
            (assert (= (jtext rj "depth") "flash") (str "the receipt carries the depth: " research.body))
            (assert (= (jtext rj "profile") "default") (str "the route came from the profile of the config file: " research.body))
            (assert (= (jtext rj "status") "noEvidence") (str "no keyed engine is set, so the pipeline reports no evidence through its own status: " research.body))
            (assert (= pinned.status 200) (str "a model that is on the research route is accepted: " (stringFromInt64 pinned.status) " " pinned.body))
            (assert (= (jtext pj "profile") "default") "the pinned run names the profile too")
            (assert (= unknown.status 400) (str "a model that is not on the research route is refused: " (stringFromInt64 unknown.status) " " unknown.body))
            (assert (stringContains? unknown.body "nonesuch") (str "the refusal names the model: " unknown.body))
            (assert (= noTopic.status 400) (str "a missing topic is refused: " (stringFromInt64 noTopic.status)))
            (assert (= busy.healthStatus 200) (str "GET /health answers while a search is in flight: " (stringFromInt64 busy.healthStatus)))
            (assert (< busy.healthMs 2000) (str "GET /health answers within 2 s while a search is held for 4 s: " (stringFromInt64 busy.healthMs) " ms"))
            (assert (>= busy.slowMs (slowHold)) (str "the held search really was in flight meanwhile: " (stringFromInt64 busy.slowMs) " ms"))
            (assert (= busy.slowStatus 200) (str "the held search is answered when its child ends: " (stringFromInt64 busy.slowStatus) " " busy.slowBody))
            (assert (= (firstResultUrl (jsonOf busy.slowBody)) (str base "/page")) (str "with the stub result: " busy.slowBody))
            (assert (>= (pairFirst (pairSecond gone)) 1) (str "the hub job child ran while the caller waited: " (stringFromInt64 (pairFirst (pairSecond gone)))))
            (assert (= (pairSecond (pairSecond gone)) 0) (str "the child is gone after the caller hung up: " (stringFromInt64 (pairSecond (pairSecond gone)))))
            (assert (= burst.extraStatus 429) (str "the request over hubJobMax is a 429: " (stringFromInt64 burst.extraStatus)))
            (assert (stringContains? burst.extraHead "Retry-After") "the 429 carries Retry-After")
            (assert (and (= burst.firstStatus 200) (= burst.secondStatus 200)) "the two jobs within the cap were answered")
            (assert (= keyRows (list "FIXA_KEY=aKey")) "a hub child keeps only the named key rows that are set, not other secrets")
            (assert killed "the gateway process tree is stopped")
            (and killed cleaned))))))
