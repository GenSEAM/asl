(module aslGateway/tests/requestLogTest
  :x [runTests]
  :i [(server :a srv)
      (aslGateway/requestLog :a rq)
      (aslGateway/chat :a ch)
      (aslGateway/config :a c)
      (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b)
      (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp)
      (aslGateway/omniApi :a om)])


fn emptyLoop home: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir "/tmp" :registryPath "/tmp/absent.asn"
     :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
     :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
     :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
     :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn replyStep status: Int64 gateway: Bool -> ch/ChatStep
  (ch/stepDone (ch/ChatResponse :head (if gateway (list (ch/headStatus status) (ch/headField (ch/gatewayOriginHeader) "gateway")) (list (ch/headStatus status))) :body "{}"))

fn connOf lp: srv/GatewayLoop fd: Int64 -> Bool
  (listAny? (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd fd)) lp.conns)

fn ! turns! lp: srv/GatewayLoop fd: Int64 fuel: Int64 -> srv/GatewayLoop
  (if (or (<= fuel 0) (not (connOf lp fd)))
    lp
    (turns! (srv/gatewayTurn! lp (list (pair fd 2))) fd (- fuel 1)))

fn ! sockPair! -> (Pair Int64 Int64)
  (let [(listener (resultOr (tcpListen 0) -1))
        (port (resultOr (sockLocalPort listener) 0))
        (client (resultOr (tcpConnect port) -1))
        (server (resultOr (sockAccept listener) -1))
        (_ (fdClose listener))]
    (pair server client))

fn ! scenario! lp: srv/GatewayLoop step: ch/ChatStep dropClient: Bool -> srv/GatewayLoop
  (let [(pr (sockPair!))
        (fd (pairFirst pr))
        (accepted (srv/acceptReq! lp fd))
        (driven (srv/drive! accepted fd "" step))
        (_ (if dropClient (ok? (fdClose fd)) true))
        (done (turns! driven fd 6))
        (_ (do (fdClose (pairSecond pr)) (if dropClient true (ok? (fdClose fd)))))]
    done)

fn cfgReq n: String -> String
  (str "(:gateway :v 2 :requestDeadlineSec " n " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))")

fn countPhase rows: (List rq/ReqRow) id: String phase: String -> Int64
  (listLength (filter (fn [(r rq/ReqRow)] -> Bool (and (= r.id id) (= r.phase phase))) rows))

fn doneOutcome rows: (List rq/ReqRow) id: String -> String
  (match (listHead (filter (fn [(r rq/ReqRow)] -> Bool (and (= r.id id) (= r.phase "done"))) rows)) ((some r) r.outcome) ((none) "-"))

fn idsOf rows: (List rq/ReqRow) -> (List String)
  (map (fn [(r rq/ReqRow)] -> String r.id) (filter (fn [(r rq/ReqRow)] -> Bool (= r.phase "accepted")) rows))

fn ! runTests -> Bool
  (let [(home (str "/tmp/requestLogTest" (stringFromInt64 (procSelf))))
        (_ (pathRemove home))
        (made (dirCreate home))
        (lp0 (emptyLoop home))
        (lp1 (scenario! lp0 (replyStep 200 false) false))
        (lp2 (scenario! lp1 (replyStep 429 true) false))
        (lp3 (scenario! lp2 (replyStep 503 true) false))
        (lp4 (scenario! lp3 (replyStep 504 false) false))
        (lp5 (scenario! lp4 (replyStep 502 false) false))
        (lp6 (scenario! lp5 (replyStep 200 false) true))
        (lp7 (scenario! lp6 (ch/stepRaised "boom" "x") false))
        (rows (resultOr (rq/readReqs! (rq/reqPath home)) (list)))
        (ids (idsOf rows))
        (outcomes (map (fn [(id String)] -> String (doneOutcome rows id)) ids))
        (onceEach (listAll? (fn [(id String)] -> Bool (and (= (countPhase rows id "accepted") 1) (= (countPhase rows id "done") 1))) ids))
        (dirB (str home "/restart"))
        (madeB (dirCreate dirB))
        (_ (rq/noteAccept! dirB "ra" 1000))
        (_ (rq/noteAccept! dirB "rb" 2000))
        (_ (rq/noteDone! dirB "ra" 1500 "ok" 200 500))
        (lostOnce (rq/recoverLost! dirB 90000 604800000))
        (rowsB (resultOr (rq/readReqs! (rq/reqPath dirB)) (list)))
        (lostTwice (rq/recoverLost! dirB 95000 604800000))
        (rowsB2 (resultOr (rq/readReqs! (rq/reqPath dirB)) (list)))
        (stuck (rq/stuckRows (list (rq/ReqRow :id "x" :phase "accepted" :atMs 1000 :outcome "" :status 0 :ms 0) (rq/ReqRow :id "y" :phase "accepted" :atMs 900000 :outcome "" :status 0 :ms 0) (rq/ReqRow :id "z" :phase "accepted" :atMs 1000 :outcome "" :status 0 :ms 0) (rq/ReqRow :id "z" :phase "done" :atMs 2000 :outcome "ok" :status 200 :ms 1000)) 1000000 900))
        (line (rq/reqParse (rq/reqDoneLine "q\"1" 5 "ok" 200 7)))
        (reqOk (c/gatewayConfigCheckText! (cfgReq "3600") "src" ".asl/mem/calibration/index.asn"))
        (reqBad (c/gatewayConfigCheckText! (cfgReq "0") "src" ".asl/mem/calibration/index.asn"))
        (badLine (rq/reqParse "(:req :id \"a\")"))
        (_ (pathRemove home))]
    (do
      (assert (= (listLength ids) 7) (str "seven requests accepted: " (stringFromInt64 (listLength ids))))
      (assert onceEach "each accepted request has exactly one accepted row and one done row")
      (assert (= (stringJoin outcomes ",") "ok,limit,noRoute,timeout,upstreamError,clientGone,gatewayError") (str "the outcomes: " (stringJoin outcomes ",")))
      (assert (listEmpty? lp7.reqs) "no request stays open after its connection closed")
      (assert (match lostOnce ((ok n) (= n 1)) ((err _) false)) "a restart makes the one unfinished request lost")
      (assert (and (= (doneOutcome rowsB "rb") "lost") (= (doneOutcome rowsB "ra") "ok") (= (countPhase rowsB "rb" "accepted") 0)) "the lost row is a done row for the unfinished id, the finished one keeps its outcome")
      (assert (match lostTwice ((ok n) (= n 0)) ((err _) false)) "a second restart loses nothing more")
      (assert (= (listLength rowsB2) (listLength rowsB)) "and leaves the file as it was")
      (assert (and (= (listLength stuck) 1) (match (listHead stuck) ((some r) (= r.id "x")) ((none) false))) "only the unfinished request past the deadline is stuck")
      (assert (match line ((ok r) (and (= r.id "q\"1") (= r.outcome "ok") (= r.status 200) (= r.ms 7))) ((err _) false)) "a done row survives its line, quotes included")
      (assert (and (= (pairSecond reqOk) 0) (= (pairSecond reqBad) 1) (stringContains? (pairFirst reqBad) "requestDeadlineSec")) (str "requestDeadlineSec 3600 is clean, 0 is a config error: " (pairFirst reqBad)))
      (assert (match badLine ((err _) true) ((ok _) false)) "a row without its phase is an error")
      (assert (and (= (rq/requestDeadlineFromText "(:gateway :v 2)") 900) (= (rq/requestDeadlineFromText "(:gateway :requestDeadlineSec 60)") 60) (= (rq/requestDeadlineFromText "(:gateway :requestDeadlineSec 0)") 900)) "the deadline defaults to 900 and takes only 1..86400")
      true))
