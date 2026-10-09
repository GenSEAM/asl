(module aslGateway/tests/dispatchTest
  :x [runTests]
  :i [(aslGateway/dispatch :a dp) (aslGateway/config :a cfg) (aslGateway/upstream :a u) (aslGateway/plugin :a p)
      (aslGateway/budget :a bgt) (aslGateway/fleet :a fl) (aslGateway/tests/fixtures/launch/launchFixture :a lf) (asl-parser/reader :a rd) (asl-json/json :a j)])

fn wiringConfig base: String withRouter: Bool -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id runpod :kind openai :base \"" base "/runpod/v1\" :keyEnv RUNPOD_API_KEY))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       " :endpoints [(:endpoint :id \"epA\" :provider \"fixa\" :model \"chat-a\" :pricePerMillion 2000000 :maxConcurrency 1)"
       " (:endpoint :id \"epRunpod\" :provider \"runpod\" :model \"bonsai2\" :pricePerMillion 1000000 :maxConcurrency 1)]"
       (if withRouter
         (str " :router (:profile :rules [(:rule :id \"cheap\" :intent \"any\" :role \"coder\" :costWeight 1 :waitWeight 0 :qualityWeight 0 :maxWaitMs 1000"
              " :candidates [(:candidate :endpoint \"epA\" :model \"chat-a\" :weight 1) (:candidate :endpoint \"epRunpod\" :model \"bonsai2\" :weight 1)])])")
         "")
       " :budget (:budgetConfig :lines [(:line :id \"runpodDay\" :scope :endpoint :key \"epRunpod\" :period :day :cap 1000 :approved false)] :approvals []))\n")

fn coldConfig base: String family: String withSpill: Bool line: String stall: Bool -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id coldp :kind openai :base \"" base "/cold/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       " :endpoints [(:endpoint :id \"epCold\" :provider \"coldp\" :model \"cold-m\" :pricePerMillion 1000000 :maxConcurrency 1)"
       (if withSpill " (:endpoint :id \"epA\" :provider \"fixa\" :model \"chat-a\" :pricePerMillion 2000000 :maxConcurrency 1)" "") "]"
       " :lifecycles [(:lifecycle :provider \"coldp\" :family \"" family "\" :start \"/start\" :status \"" (if stall "/stall" "/status") "\" :coldStartMs " (if stall "300" "5000") " :startCost 500)]"
       " :router (:profile :rules [(:rule :id \"cold\" :intent \"any\" :role \"coder\" :costWeight 1 :waitWeight 0 :qualityWeight 0 :maxWaitMs 60000"
       " :candidates [(:candidate :endpoint \"epCold\" :model \"cold-m\" :weight 1)"
       (if withSpill " (:candidate :endpoint \"epA\" :model \"chat-a\" :weight 1)" "") "])])"
       (if (stringEmpty? line) ""
         (str " :budget (:budgetConfig :lines [(:line :id \"day\" :scope :endpoint :key \"" line "\" :period :day :cap 100000 :approved false)] :approvals [])"))
       ")\n")

fn redirConfig base: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"" base "/v1\" :keyEnv FIXA_KEY)"
       " (:provider :id redir :kind openai :base \"" base "/redir/v1\" :keyEnv FIXA_KEY :timeoutSec 300 :redirectAfterSec 150))"
       " :models ((:model :id mA :provider fixa :name \"chat-a\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       " :endpoints [(:endpoint :id \"epRedir\" :provider \"redir\" :model \"redir-m\" :maxConcurrency 1)]"
       " :router (:profile :rules [(:rule :id \"long\" :intent \"any\" :role \"coder\" :costWeight 1 :waitWeight 0 :qualityWeight 0 :maxWaitMs 60000"
       " :candidates [(:candidate :endpoint \"epRedir\" :model \"redir-m\" :weight 1)])]))\n")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXA_KEY" "aKey") (pair "RUNPOD_API_KEY" "rpKey")))

fn hint -> dp/RouteHint
  (dp/RouteHint :provider "fixa" :model "chat-a" :intent "" :role "coder" :promptTokens 10)

fn chatRequest -> u/UpstreamRequest
  (u/UpstreamRequest :url "http://fixture.invalid/v1/chat/completions" :fragment "" :method "POST"
    :headers (list (pair "Content-Type" "application/json") (pair "Authorization" "Bearer aKey"))
    :data "{\"model\":\"chat-a\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")

fn header request: u/UpstreamRequest name: String -> String
  (optionOr (optionMap pairSecond (listHead (filter (fn [(h (Pair String String))] -> Bool (= (stringLower (pairFirst h)) (stringLower name))) request.headers))) "")

fn bodyModel data: String -> String
  (mt (j/jsonParse data) ((ok v) (mt (j/jsonGet v "model") ((some m) (mt m ((j/jstr s) s) (_ ""))) ((none) ""))) ((err _) ""))

fn sentSlot planned: dp/Plan -> String
  (mt planned ((dp/planSend slot _ _ _) slot) (_ ""))

fn sentRequest planned: dp/Plan -> (Option u/UpstreamRequest)
  (mt planned ((dp/planSend _ _ request _) (some request)) (_ none))

fn rowOf planned: dp/Plan -> dp/DecisionRow
  (mt planned ((dp/planSend _ _ _ row) row) ((dp/planReject _ _ row) row) ((dp/planWait _ _ _ row _ _) row))

fn refusedOf planned: dp/Plan -> (List String)
  (rowOf planned).refused

fn ! wiringFor text: String -> (Result dp/Wiring String)
  (mt (cfg/gatewayProfilesLoadText! "/tmp/dispatchTest/.asl/gateway.asn" true (ok text) "")
    ((err e) (err e))
    ((ok table)
      (mt (u/upstreamSettings (testEnv))
        ((err e) (err e))
        ((ok st) (dp/wiringFromConfig (some table) text st (testEnv) (listAppend (dp/builtinFamilies) (list (lf/fixtureFamily))))))))

fn ! unitChecks -> Bool
  (let [(base "http://127.0.0.1:9")
        (routed (wiringFor (wiringConfig base true)))
        (plain (wiringFor (wiringConfig base false)))]
    (mt routed
      ((err e) (do (assert false (str "routed wiring builds: " e)) false))
      ((ok w)
        (do
          (assert (= (optionOr (listHead w.rows) (u/upstreamFallback)).id "fixa") "config-only providers become rows ahead of the defaults")
          (assert (= (u/getUpstreamForModelIn w.rows (u/upstreamFallback) w.settings (testEnv) (some "runpod/bonsai2")).provider "runpod") "a config-only row claims its id prefix")
          (assert (= (u/getUpstreamForModelIn w.rows (u/upstreamFallback) w.settings (testEnv) (some "runpod/bonsai2")).url (str base "/runpod/v1")) "a config-only row takes its base from config")
          (assert (= (u/getUpstreamForModelIn w.rows (u/upstreamFallback) w.settings (testEnv) (some "runpod/bonsai2")).key "rpKey") "a config-only row reads its key from the env name config gives")
          (assert (some? (p/pluginNamed w.plugins "runpod")) "every HTTP row has a plugin")
          (assert (= (listLength w.slots) 2) "endpoints load from config")
          (let [(first (dp/plan w (hint) (chatRequest) (testEnv) 1000))]
            (do
              (assert (= (sentSlot first) "epRunpod") "route: the router rule picks the cheaper endpoint")
              (assert (mt (sentRequest first) ((some r) (= r.url (str base "/runpod/v1/chat/completions"))) ((none) false)) "send: a routed request goes to the endpoint's row URL")
              (assert (mt (sentRequest first) ((some r) (= (header r "Authorization") "Bearer rpKey")) ((none) false)) "send: a routed request carries the endpoint row's key")
              (assert (mt (sentRequest first) ((some r) (= (bodyModel r.data) "bonsai2")) ((none) false)) "send: a routed request names the candidate model")
              (let [(busy (dp/started w "epRunpod"))
                    (atCapacity (dp/plan busy (hint) (chatRequest) (testEnv) 1000))]
                (do
                  (assert (= (sentSlot atCapacity) "epA") "pick: spillover prefers the endpoint with free capacity")
                  (assert (= (refusedOf atCapacity) (list)) "pick: spillover needs no refusal to avoid a full endpoint")
                  (let [(full (dp/plan (dp/started busy "epA") (hint) (chatRequest) (testEnv) 1000))]
                    (do
                      (assert (mt full ((dp/planReject status _ _) (= status 503)) (_ false)) "admission: when every endpoint is full the request is refused with 503")
                      (assert (= (listLength (refusedOf full)) 2) "admission: each refused endpoint is recorded")
                      (assert (listAll? (fn [(r String)] -> Bool (stringEndsWith? r ":rejectAtCapacity")) (refusedOf full)) "admission: the refusals name the capacity reason")))))
              (let [(charged (dp/settle (dp/started w "epRunpod") "epRunpod" "runpod" 1000 50 true 1000))
                    (after (dp/plan (pairFirst charged) (hint) (chatRequest) (testEnv) 2000))
                    (again (dp/settle (pairFirst charged) "epRunpod" "runpod" 1 50 true 2000))]
                (do
                  (assert (stringContains? (pairSecond charged) ":tokens 1000 :cost 1000 :status charged") (str "charge: tokens times the endpoint price reach the ledger: " (pairSecond charged)))
                  (assert (= (sentSlot after) "epA") "budget: a spent endpoint is skipped for the next candidate")
                  (assert (= (refusedOf after) (list "epRunpod:budget")) "budget: the budget refusal is recorded in the decision row")
                  (assert (stringContains? (pairSecond again) ":status overCap") "charge: a charge past the cap is refused by the ledger")
                  (mt (wiringFor (str (wiringConfig base true) " "))
                    ((err e) (assert false (str "reloaded wiring builds: " e)))
                    ((ok fresh)
                      (do
                        (assert (= (sentSlot (dp/plan fresh (hint) (chatRequest) (testEnv) 2000)) "epRunpod") "a rebuilt ledger alone starts empty")
                        (assert (= (refusedOf (dp/plan (dp/carrySpend (pairFirst charged) fresh) (hint) (chatRequest) (testEnv) 2000)) (list "epRunpod:budget")) "reload: spend on a surviving line carries into the rebuilt ledger"))))))
              (assert (stringContains? (dp/decisionText (rowOf first)) ":rule \"cheap\" :candidates (\"epRunpod\" \"epA\")") "the decision row names the rule and the ranked candidates")))
          (mt plain
            ((err e) (assert false (str "plain wiring builds: " e)))
            ((ok wp)
              (let [(through (dp/plan wp (hint) (chatRequest) (testEnv) 1000))]
                (do
                  (assert (= (sentSlot through) "fixa") "without a router profile the chat's own endpoint is used")
                  (assert (mt (sentRequest through) ((some r) (= r.url (chatRequest).url)) ((none) false)) "passthrough sends the chat-built request unchanged")))))
          true))))


fn redirectChecks -> Bool
  (let [(caps (p/openaiCompatCapabilities 4 (p/alwaysOn) (p/perToken 0.0 0.0) (list)))
        (following (p/followingRedirects caps 150))
        (followCfg (resultOr (u/curlConfigFollowing (chatRequest) 1200.0 none 8) ""))
        (plainCfg (resultOr (u/curlConfig (chatRequest) 1200.0 none) ""))]
    (do
      (assert (= (p/maxRedirects following 1200.0) 8) "max-redirs is ceil(timeoutSec / redirectAfterSec): 1200 s at 150 s gives 8")
      (assert (= (p/maxRedirects following 1201.0) 9) "a partial interval needs one more hop")
      (assert (= (p/maxRedirects caps 1200.0) 0) "a row without the capability never follows")
      (assert (stringContains? followCfg "location\nmax-redirs = 8\n") "a following call passes curl --location with max-redirs")
      (assert (not (stringContains? followCfg "request = ")) "a following POST leaves the method to curl so a 303 becomes a GET")
      (assert (and (stringContains? plainCfg "request = \"POST\"") (not (stringContains? plainCfg "location"))) "a plain call keeps its method and does not follow")
      (assert (mt (u/parseCurlOutput "HTTP/1.1 303 See Other\r\nLocation: /a\r\n\r\nHTTP/1.1 303 See Other\r\nLocation: /b\r\n\r\nHTTP/1.1 200 OK\r\n\r\nfinal")
                ((ok r) (and (= r.status 200) (= r.body "final"))) ((err _) false)) "the 3xx blocks a followed redirect prints are skipped")
      true))


fn slotLifecycle w: dp/Wiring id: String -> String
  (mt (listHead (filter (fn [(s dp/Slot)] -> Bool (= s.id id)) w.slots))
    ((none) "absent")
    ((some s) (mt s.state.lifecycle ((fl/cold) "cold") ((fl/warming) "warming") ((fl/warm) "warm") ((fl/draining) "draining") ((fl/down) "down"))))

fn waitOf planned: dp/Plan -> String
  (mt planned ((dp/planWait slot _ _ _ cold deadline) (str slot (if cold " cold " " warming ") (stringFromInt64 deadline))) (_ ""))

fn readyText r: dp/SlotReady -> String
  (mt r ((dp/readyNow) "now") ((dp/readyLater) "later") ((dp/readyGone _) "gone"))

fn ! coldChecks -> Bool
  (let [(base "http://127.0.0.1:9")]
    (mt (wiringFor (coldConfig base "fixture" true "epCold" false))
      ((err e) (do (assert false (str "cold wiring builds: " e)) false))
      ((ok w)
        (let [(spilled (dp/plan w (hint) (chatRequest) (testEnv) 1000))
              (full (dp/started w "epA"))
              (parked (dp/plan full (hint) (chatRequest) (testEnv) 1000))]
          (do
            (assert (= (slotLifecycle w "epCold") "cold") "a serverless endpoint starts cold")
            (assert (= (slotLifecycle w "epA") "warm") "an always-on endpoint starts warm")
            (assert (mt (p/pluginNamed w.plugins "coldp") ((some pl) (some? pl.lifecycle)) ((none) false)) "the lifecycle row attaches to the provider's plugin")
            (assert (= (sentSlot spilled) "epA") "a cold serverless endpoint spills over to a warm candidate")
            (assert (= (waitOf parked) "epCold cold 6000") (str "with no other candidate the request waits on the cold endpoint until coldStartMs: " (waitOf parked)))
            (assert (= (rowOf parked).admission "wait") "the decision row records the wait")
            (mt (dp/startSlot! full "epCold" 1000 6000)
              ((dp/startRefused _ reason _) (assert false (str "a covered start is allowed: " reason)))
              ((dp/startOk started row)
                (do
                  (assert (= (slotLifecycle started "epCold") "warming") "an allowed start moves the endpoint warming")
                  (assert (mt started.ledger ((some l) (= (map (fn [(b bgt/Bucket)] -> Int64 b.amount) l.buckets) (list 500))) ((none) false)) "the start's expected cost is charged to the covering line")
                  (assert (stringContains? row ":op start :endpoint \"epCold\" :result started :state warming :cost 500 :charge charged") (str "the start row records the gate, state and charge: " row))
                  (assert (= (waitOf (dp/plan started (hint) (chatRequest) (testEnv) 1050)) "epCold warming 6050") "a later request joins the warming endpoint without a second start")
                  (assert (= (readyText (dp/slotReady started "epCold" 1050)) "later") "a warming endpoint keeps parked requests waiting")
                  (let [(expired (dp/pollSlots! started 6001))]
                    (do
                      (assert (= (slotLifecycle (pairFirst expired) "epCold") "cold") "a start still warming past its coldStartMs deadline goes back cold and polling stops")
                      (assert (stringContains? (stringJoin (pairSecond expired) " ") ":state cold :reason \"coldStartMs exceeded\"") "the expiry is logged")
                      (assert (listEmpty? (pairSecond (dp/pollSlots! (pairFirst expired) 6200))) "an expired start is not polled again")))
                  (let [(early (dp/pollSlots! started 1050))
                        (late (dp/pollSlots! started 1200))]
                    (do
                      (assert (and (= (slotLifecycle (pairFirst early) "epCold") "warming") (listEmpty? (pairSecond early))) "status polls are throttled to one per 100 ms")
                      (assert (= (slotLifecycle (pairFirst late) "epCold") "warm") "a warm status moves the endpoint warm")
                      (assert (stringContains? (stringJoin (pairSecond late) " ") ":op status :endpoint \"epCold\" :state warm") "the warm transition is logged")
                      (assert (= (readyText (dp/slotReady (pairFirst late) "epCold" 1200)) "now") "a parked request sends once the endpoint is warm"))))))
            (mt (wiringFor (coldConfig base "fixture" false "epA" false))
              ((err e) (assert false (str "uncovered wiring builds: " e)))
              ((ok wu)
                (mt (dp/startSlot! wu "epCold" 1000 6000)
                  ((dp/startOk _ row) (assert false (str "a start without a covering budget line is denied: " row)))
                  ((dp/startRefused status reason row)
                    (do
                      (assert (= status 429) "a spend-gate denial answers 429")
                      (assert (= reason "spendGate: no budget line covers this spend") (str "the denial names the missing line: " reason))
                      (assert (stringContains? row ":result denied") "the denied start is logged"))))))
            (mt (wiringFor (coldConfig base "fixture" false "" false))
              ((err e) (assert false (str "ledgerless wiring builds: " e)))
              ((ok wn)
                (mt (dp/startSlot! wn "epCold" 1000 6000)
                  ((dp/startOk _ row) (assert false (str "a start without a ledger is denied: " row)))
                  ((dp/startRefused status reason _) (assert (and (= status 429) (= reason "spendGate: start needs a budget ledger")) (str "no ledger means no start: " reason))))))
            (assert (mt (wiringFor (coldConfig base "nosuch" false "epCold" false)) ((err e) (stringContains? e "unknown family nosuch")) ((ok _) false)) "an unknown lifecycle family is a wiring error")
            true)))))


(schema Seen
  (:f path String)
  (:f auth String)
  (:f model String))

(schema Stub
  (:f fd Int64)
  (:f input String))

(schema Run
  (:f listener Int64)
  (:f client Int64)
  (:f response String)
  (:f done Bool)
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
                  :auth (headValue head "Authorization")
                  :model (bodyModel (optionOr (stringSlice raw start (+ start want)) ""))))))))

fn completion model: String -> String
  (let [(body (str "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"served:" model
                   "\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":990,\"total_tokens\":1000}}"))]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn jsonReply body: String -> String
  (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn stubReply seen: (List Seen) now: Seen -> String
  (cond
    ((or (stringEndsWith? now.path "/start") (stringEndsWith? now.path "/stall")) (jsonReply "{\"state\":\"warming\"}"))
    ((stringEndsWith? now.path "/status")
      (jsonReply (if (< (listLength (filter (fn [(x Seen)] -> Bool (stringEndsWith? x.path "/status")) seen)) 2) "{\"state\":\"warming\"}" "{\"state\":\"warm\"}")))
    ((stringEndsWith? now.path "/redir/v1/chat/completions") (seeOther "/redir/hop1"))
    ((= now.path "/redir/hop1") (seeOther "/redir/hop2"))
    ((= now.path "/redir/hop2") (completion "redir-final"))
    (else (completion now.model)))

fn seeOther location: String -> String
  (str "HTTP/1.1 303 See Other\r\nLocation: " location "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

fn pathsFrom seen: (List Seen) skip: Int64 -> (List String)
  (if (listEmpty? seen) (list)
    (if (> skip 0) (pathsFrom (optionOr (listTail seen) (list)) (- skip 1))
      (listAppend (list (optionOr (listHead seen) (Seen :path "" :auth "" :model "")).path) (pathsFrom (optionOr (listTail seen) (list)) 0))))

fn ! stepStub! r: Run stub: Stub ready: (List (Pair Int64 Int64)) -> Run
  (let [(keep (fn [(s Stub)] -> Run (with r :stubs (listAppend r.stubs (list s)))))]
    (if (not (ready? ready stub.fd)) (keep stub)
      (mt (fdRead stub.fd 65536)
        ((err _) (do (fdClose stub.fd) r))
        ((ok chunk)
          (let [(input (str stub.input chunk))]
            (mt (parseStub input)
              ((none) (if (stringEmpty? chunk) (do (fdClose stub.fd) r) (keep (with stub :input input))))
              ((some seen)
                (do (writeAll! stub.fd (stubReply r.seen seen)) (fdClose stub.fd)
                  (with r :seen (listAppend r.seen (list seen)))))))))))

fn ! stepRun! r: Run ready: (List (Pair Int64 Int64)) -> Run
  (let [(accepted (if (ready? ready r.listener)
                    (mt (sockAccept r.listener)
                      ((ok fd) (with r :stubs (listAppend r.stubs (list (Stub :fd fd :input "")))))
                      ((err _) r))
                    r))
        (stubbed (fold (fn [(acc Run) (s Stub)] -> Run (stepStub! acc s ready))
                   (Run :listener accepted.listener :client accepted.client :response accepted.response :done accepted.done :stubs (list) :seen accepted.seen)
                   accepted.stubs))]
    (if (or stubbed.done (not (ready? ready stubbed.client))) stubbed
      (mt (fdRead stubbed.client 65536)
        ((err _) (Run :listener stubbed.listener :client stubbed.client :response stubbed.response :done true :stubs stubbed.stubs :seen stubbed.seen))
        ((ok chunk) (Run :listener stubbed.listener :client stubbed.client :response (str stubbed.response chunk) :done (stringEmpty? chunk) :stubs stubbed.stubs :seen stubbed.seen)))))

fn ! pumpRun! r: Run deadline: Int64 -> Run
  (if (or r.done (>= (nowMs!) deadline)) r
    (let [(watch (listAppend (list (pair r.listener 1) (pair r.client 1)) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) r.stubs)))]
      (mt (fdPoll watch 20)
        ((err _) (pumpRun! r deadline))
        ((ok ready) (pumpRun! (stepRun! r ready) deadline)))))

fn ! exchange! listener: Int64 gatewayPort: Int64 seen: (List Seen) -> Run
  (let [(body "{\"messages\":[{\"role\":\"user\",\"content\":\"route me\"}]}")
        (request (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: "
                      (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))]
    (mt (tcpConnect gatewayPort)
      ((err e) (Run :listener listener :client -1 :response (str "connect failed: " e) :done true :stubs (list) :seen seen))
      ((ok fd)
        (let [(run (pumpRun! (Run :listener listener :client fd :response "" :done (not (writeAll! fd request)) :stubs (list) :seen seen) (+ (nowMs!) 15000)))]
          (do (fdClose fd) run)))))

fn ! waitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (mt (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none)
      ((some port) (if (> port 0) port (do (sleepMs 20) (waitPort! path (- attempts 1)))))
      ((none) (do (sleepMs 20) (waitPort! path (- attempts 1))))))

fn seenAt seen: (List Seen) index: Int64 -> Seen
  (optionOr (listGet seen index) (Seen :path "" :auth "" :model ""))

fn ! socketChecks -> Bool
  (let [(temp (stringTrim (processRun "/usr/bin/mktemp -d /tmp/dispatchTest.XXXXXX").stdout))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort)))
        (wrote (and (ok? (dirCreate (str temp "/.asl"))) (ok? (fileWrite (str temp "/.asl/gateway.asn") (wiringConfig base true)))))
        (host (resultOr (procExePath) ""))
        (server (resultOr (realPath "asl/packages/asl-gateway/tests/fixtures/launch/launchFixture.asl") ""))
        (readyPath (str temp "/ready"))
        (command (str "exec " host " run " server " serve --port 0 --upstream " base "/v1 --ready " readyPath " 2>" temp "/gateway.err"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
                   (str "ASL_CALIBRATION_INDEX=" temp "/absent.asn") "FIXA_KEY=aKey" "RUNPOD_API_KEY=rpKey"))
        (spawned (procSpawnv (list "/bin/sh" "-c" command) (none) (some env)))
        (pid (mt spawned ((ok sp) sp.pid) ((err _) 0)))
        (gatewayPort (if (> pid 0) (waitPort! readyPath 500) 0))
        (first (exchange! listener gatewayPort (list)))
        (second (exchange! listener gatewayPort first.seen))
        (cfgPath (str temp "/.asl/gateway.asn"))
        (wroteReload (ok? (fileWrite cfgPath (str (wiringConfig base true) " "))))
        (reloaded (exchange! listener gatewayPort second.seen))
        (wroteRedir (ok? (fileWrite cfgPath (redirConfig base))))
        (redirected (exchange! listener gatewayPort reloaded.seen))
        (wroteCold (ok? (fileWrite cfgPath (coldConfig base "http" false "epCold" false))))
        (third (exchange! listener gatewayPort redirected.seen))
        (wroteStall (ok? (fileWrite cfgPath (coldConfig base "http" false "epCold" true))))
        (fifth (exchange! listener gatewayPort third.seen))
        (paused (do (sleepMs 300) true))
        (wroteDenied (ok? (fileWrite cfgPath (coldConfig base "http" false "epA" false))))
        (fourth (exchange! listener gatewayPort fifth.seen))
        (wroteAfter (ok? (fileWrite cfgPath (wiringConfig base true))))
        (sixth (exchange! listener gatewayPort fourth.seen))
        (wroteInjected (ok? (fileWrite cfgPath (coldConfig base "fixture" false "epCold" false))))
        (seventh (exchange! listener gatewayPort sixth.seen))
        (killed (if (> pid 0) (do (procKill (- 0 pid) "SIGTERM") (procWaitPid pid false) true) false))
        (closed (do (fdClose listener) true))
        (log (resultOr (fileReadString (str temp "/gateway.err")) ""))
        (removed (= (processRun (str "/bin/rm -rf " temp)).exitCode 0))
        (s1 (seenAt second.seen 0))
        (s2 (seenAt second.seen 1))]
    (do
      (assert (and wrote (> gatewayPort 0)) (str "gateway serves on a free port: " log))
      (assert (and (stringStartsWith? first.response "HTTP/1.1 200") (stringContains? first.response "served:bonsai2")) (str "first request is answered by the routed endpoint: " first.response " " log))
      (assert (= s1.path "/runpod/v1/chat/completions") (str "first request reaches the config-only runpod row's URL: " s1.path))
      (assert (= s1.auth "Bearer rpKey") "first request carries the runpod key named by config")
      (assert (= s1.model "bonsai2") "first request names the router's candidate model")
      (assert (stringContains? log "(:gateway :route :rule \"cheap\" :candidates (\"epRunpod\" \"epA\") :pick \"epRunpod\" :refused ()") (str "a decision row is logged for the first request: " log))
      (assert (stringContains? log "(:gateway :charge :endpoint \"epRunpod\" :tokens 1000 :cost 1000 :status charged)") "budget.asl charges the first request by tokens and endpoint price")
      (assert (and (stringStartsWith? second.response "HTTP/1.1 200") (stringContains? second.response "served:chat-a")) (str "second request is answered after the budget spill: " second.response))
      (assert (and (= s2.path "/v1/chat/completions") (= s2.auth "Bearer aKey")) (str "second request goes to the next candidate's provider: " s2.path " " s2.auth))
      (assert (stringContains? log ":pick \"epA\" :refused (\"epRunpod:budget\")") "the second decision row records the budget refusal")
      (assert (stringContains? log "(:gateway :charge :endpoint \"epA\" :tokens 1000 :cost 2000 :status charged)") "the second request is charged at its endpoint's price")
      (assert (and wroteReload (stringContains? reloaded.response "served:chat-a")) (str "after a config reload the spent endpoint stays refused: " reloaded.response))
      (assert (= (listLength (stringSplit log ":pick \"epA\" :refused (\"epRunpod:budget\")")) 3) "a reload keeps the spend booked before it, so the budget refusal repeats")
      (assert (and wroteRedir (and (stringStartsWith? redirected.response "HTTP/1.1 200") (stringContains? redirected.response "served:redir-final"))) (str "a provider row with :redirectAfterSec follows 303s to the final 200 body: " redirected.response " " log))
      (assert (= (pathsFrom redirected.seen (listLength reloaded.seen)) (list "/redir/v1/chat/completions" "/redir/hop1" "/redir/hop2")) (str "the gateway followed both 303 hops: " (stringJoin (pathsFrom redirected.seen (listLength reloaded.seen)) " ")))
      (assert (and wroteCold (and (stringStartsWith? third.response "HTTP/1.1 200") (stringContains? third.response "served:cold-m"))) (str "a request to a cold serverless endpoint is served after it warms: " third.response " " log))
      (assert (= (pathsFrom third.seen (listLength redirected.seen)) (list "/cold/v1/start" "/cold/v1/status" "/cold/v1/status" "/cold/v1/status" "/cold/v1/chat/completions"))
        (str "the gateway starts the endpoint, polls status until warm, then sends: " (stringJoin (pathsFrom third.seen (listLength redirected.seen)) " ")))
      (assert (= (seenAt third.seen (listLength redirected.seen)).auth "Bearer aKey") "the lifecycle start carries the provider row's key")
      (assert (stringContains? log ":pick \"epCold\" :refused () :model \"cold-m\" :admission wait :budget allow") "the decision row records the wait on the cold endpoint")
      (assert (stringContains? log "(:gateway :lifecycle :op start :endpoint \"epCold\" :result started :state warming :cost 500 :charge charged)") "the start passed the spend gate and was charged its expected cost")
      (assert (stringContains? log "(:gateway :lifecycle :op status :endpoint \"epCold\" :state warm)") "the warm transition is logged")
      (assert (stringContains? log "(:gateway :charge :endpoint \"epCold\" :tokens 1000 :cost 1000 :status charged)") "the served request is charged by tokens and price")
      (assert (and wroteDenied (stringContains? fourth.response "HTTP Error 429: spendGate: no budget line covers this spend")) (str "a start without a covering budget line is refused with the gate's 429: " fourth.response))
      (assert (stringContains? log ":op start :endpoint \"epCold\" :result denied :reason \"spendGate: no budget line covers this spend\"") "the denied start is logged with the gate's reason")
      (assert (and wroteStall (stringContains? fifth.response "endpoint epCold did not warm within coldStartMs")) (str "a request whose endpoint stays warming past coldStartMs is refused: " fifth.response))
      (assert (stringContains? log "(:gateway :lifecycle :op wait :endpoint \"epCold\" :result timeout)") "the wait timeout is logged")
      (assert (stringContains? log "(:gateway :lifecycle :op status :endpoint \"epCold\" :state cold :reason \"coldStartMs exceeded\")") "the expired start goes back cold")
      (assert (= (pathsFrom fourth.seen (listLength fifth.seen)) (list))
        (str "after the timeout row the provider sees nothing: no status poll, no start, no chat: " (stringJoin (pathsFrom fourth.seen (listLength fifth.seen)) " ")))
      (assert (and wroteAfter (and (stringStartsWith? sixth.response "HTTP/1.1 200") (stringContains? sixth.response "served:bonsai2")))
        (str "gateway refusals (cold timeout 503, spend-gate 429) do not trip the chat provider's breaker: " sixth.response))
      (assert (and wroteInjected (stringContains? seventh.response "served:cold-m")) (str "a family injected by the launcher serves a cold endpoint: " seventh.response))
      (assert (= (pathsFrom seventh.seen (listLength sixth.seen)) (list "/cold/v1/chat/completions")) "the injected in-process lifecycle sends no lifecycle traffic")
      (assert (not (listAny? (fn [(x String)] -> Bool (stringEndsWith? x "/chat/completions")) (pathsFrom fifth.seen (listLength third.seen)))) "a request that timed out on a cold start is never sent")
      (and killed (and closed removed))))

fn ! runTests -> Bool
  (and (unitChecks) (and (redirectChecks) (and (coldChecks) (socketChecks))))
