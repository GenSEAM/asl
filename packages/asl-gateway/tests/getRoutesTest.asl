(module aslGateway/tests/getRoutesTest
  :x [runTests]
  :i [(getRoutes :a rt)
      (cockpit :a ck)
      (config :a cfg)
      (usage :a us)
      (search :a se)
      (pyText :a pt)
      (asl-json/json :a j)
      (asl-http/http11 :a h)])

(schema Instance
  (:f id String)
  (:f files (List (Pair String String)))
  (:f state rt/GetState))

(schema Case
  (:f instance String)
  (:f path String)
  (:f headers (List (Pair String String)))
  (:f status Int64)
  (:f reason String)
  (:f respHeaders (List (Pair String String)))
  (:f body String))

fn check! b: Bool msg: String -> Bool
  (if b (do (assert b msg) true) (do (eprintln (str "FAIL: " msg)) (assert false msg) false))

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/getRoutesFixture.asn"

fn root -> String
  "/tmp/aslGetRoutesParity"

fn unroot s: String -> String
  (pt/replaceAll s "@ROOT@" (root))

fn propIn props: (List (Pair String ck/AsnVal)) key: String -> (Option ck/AsnVal)
  (mt (listHead props)
    ((none) (none))
    ((some p) (if (= (pairFirst p) key) (some (pairSecond p)) (propIn (optionOr (listTail props) (list)) key))))

fn textOf v: (Option ck/AsnVal) -> String
  (mt v ((some x) (mt x ((ck/asnText s) s) ((ck/asnAtom s) s) (_ ""))) ((none) ""))

fn intOf v: (Option ck/AsnVal) -> Int64
  (optionOr (stringToInt64 (textOf v)) -1)

fn itemsOf v: (Option ck/AsnVal) -> (List ck/AsnVal)
  (mt v ((some x) (mt x ((ck/asnList xs) xs) (_ (list)))) ((none) (list)))

fn headOf v: ck/AsnVal -> String
  (mt v ((ck/asnList xs) (mt (listHead xs) ((some h) (mt h ((ck/asnAtom a) a) (_ ""))) ((none) ""))) (_ ""))

fn props v: ck/AsnVal -> (List (Pair String ck/AsnVal))
  (mt (ck/asnProps v (some (headOf v))) ((ok p) p) ((err _) (list)))

fn pairsOf v: (Option ck/AsnVal) -> (List (Pair String String))
  (map (fn [(x ck/AsnVal)] -> (Pair String String)
         (mt x
           ((ck/asnList kv) (pair (textOf (listGet kv 0)) (unroot (textOf (listGet kv 1)))))
           (_ (pair "" ""))))
       (itemsOf v))

fn jsonAt v: j/Json key: String -> j/Json
  (optionOr (j/jsonGet v key) (j/jnull))

fn jInt v: j/Json -> Int64
  (mt v ((j/jint n) n) (_ -1))

fn jStr v: j/Json -> String
  (mt v ((j/jstr s) s) (_ ""))

fn jBool v: j/Json -> Bool
  (mt v ((j/jbool b) b) (_ false))

fn kvs v: j/Json -> (List (Pair String j/Json))
  (mt v ((j/jobj xs) xs) (_ (list)))

fn statusOf snap: j/Json -> us/GatewayStatus
  (us/GatewayStatus :pid (jInt (jsonAt snap "pid")) :version (jStr (jsonAt snap "version")) :diskVersion (jStr (jsonAt snap "diskVersion"))
                    :stale (jBool (jsonAt snap "stale")) :diskValid (jBool (jsonAt snap "diskValid")) :updates (jInt (jsonAt snap "updates"))
                    :updatedFrom (jStr (jsonAt snap "updatedFrom")) :inFlight (jInt (jsonAt snap "inFlight")) :draining (jBool (jsonAt snap "draining")))

fn fileText files: (List (Pair String String)) key: String -> (Option String)
  (mt (listHead files)
    ((none) (none))
    ((some p) (if (= (pairFirst p) key) (some (pairSecond p)) (fileText (optionOr (listTail files) (list)) key))))

fn healthOf! id: String files: (List (Pair String String)) snap: j/Json -> rt/HealthInputs
  (let [(path (str (root) "/" id "/home/.asl/gateway.asn"))
        (registry (str (root) "/" id "/cal/index.asn"))
        (text (fileText files ".asl/gateway.asn"))
        (builtin (if (and (= id "builtin") (not (some? text)))
                    (resultOr (fileReadString "asl/packages/asl-gateway/tests/fixtures/builtinConfig/gateway.asn") "")
                    ""))
        (loaded (if (and (= id "builtin") (not (some? text)))
                  (cfg/gatewayProfilesLoadText! "builtin" true (ok builtin) registry)
                  (cfg/gatewayProfilesLoadText! path (some? text) (mt text ((some t) (ok t)) ((none) (err "absent"))) registry)))]
    (rt/HealthInputs
      :pools (map (fn [(p (Pair String j/Json))] -> rt/PoolRow
                    (rt/PoolRow :name (pairFirst p) :size (jInt (jsonAt (pairSecond p) "size")) :busy (jInt (jsonAt (pairSecond p) "busy")) :queued (jInt (jsonAt (pairSecond p) "queued"))))
                  (kvs (jsonAt snap "pools")))
      :clis (map (fn [(p (Pair String j/Json))] -> rt/CliRow (rt/CliRow :name (pairFirst p) :bin (jStr (jsonAt (pairSecond p) "bin")) :version (jStr (jsonAt (pairSecond p) "version"))))
                 (kvs (jsonAt snap "clis")))
      :breaker (map (fn [(p (Pair String j/Json))] -> rt/BreakerRow
                      (rt/BreakerRow :name (pairFirst p) :down (jBool (jsonAt (pairSecond p) "down")) :secondsLeft (jInt (jsonAt (pairSecond p) "secondsLeft"))))
                    (kvs (jsonAt snap "breaker")))
      :undeclared (map (fn [(p (Pair String j/Json))] -> (Pair String Int64) (pair (pairFirst p) (jInt (pairSecond p)))) (kvs (jsonAt snap "undeclaredIntents")))
      :update (statusOf snap)
      :usage (jsonAt snap "usage")
      :profiles loaded
      :envProfile (none)
      :profilePath path
      :profileExists (some? text)))

fn queuesOf v: (Option ck/AsnVal) -> (List rt/ActionQueue)
  (map (fn [(q ck/AsnVal)] -> rt/ActionQueue
         (let [(p (props q))]
           (rt/ActionQueue :id (textOf (propIn p "id")) :items (map (fn [(i ck/AsnVal)] -> String (textOf (some i))) (itemsOf (propIn p "items"))))))
       (itemsOf v))

fn toInstance! v: ck/AsnVal -> (Result Instance String)
  (let [(p (props v))
        (id (textOf (propIn p "id")))
        (files (filesOf v))
        (sp (props (optionOr (propIn p "state") (ck/asnList (list)))))]
    (mt (pt/jsonLoads (unroot (textOf (propIn p "snapshot"))))
      ((err e) (err (str id " snapshot: " (pt/pyErrText e))))
      ((ok snap)
        (ok (Instance
              :id id
              :files files
              :state (rt/GetState
                       :projects (pairsOf (propIn sp "projects"))
                       :channels (pairsOf (propIn sp "channels"))
                       :sessions (map (fn [(s ck/AsnVal)] -> rt/SessionRow
                                        (let [(q (props s))] (rt/SessionRow :id (textOf (propIn q "id")) :status (textOf (propIn q "status")) :url (textOf (propIn q "url")))))
                                      (itemsOf (propIn sp "sessions")))
                       :targets (map (fn [(t ck/AsnVal)] -> rt/TargetRow
                                       (let [(q (props t))]
                                         (rt/TargetRow :id (textOf (propIn q "id")) :kind (textOf (propIn q "kind")) :family (textOf (propIn q "family"))
                                                       :authenticated (= (textOf (propIn q "authenticated")) "true")
                                                       :tabsCount (intOf (propIn q "tabsCount")) :lastHeartbeat (intOf (propIn q "lastHeartbeat")))))
                                     (itemsOf (propIn sp "targets")))
                       :targetQueues (queuesOf (propIn sp "targetQueues"))
                       :extensionQueues (queuesOf (propIn sp "extensionQueues"))
                       :health (healthOf! id files snap)))))))

fn toCase v: ck/AsnVal -> Case
  (let [(p (props v))]
    (Case :instance (textOf (propIn p "instance")) :path (textOf (propIn p "path")) :headers (pairsOf (propIn p "headers"))
          :status (intOf (propIn p "status")) :reason (textOf (propIn p "reason")) :respHeaders (pairsOf (propIn p "respHeaders"))
          :body (unroot (textOf (propIn p "body")))))

fn filesOf v: ck/AsnVal -> (List (Pair String String))
  (map (fn [(f ck/AsnVal)] -> (Pair String String) (let [(fp (mt (ck/asnProps f (none)) ((ok x) x) ((err _) (list))))] (pair (textOf (propIn fp "path")) (textOf (propIn fp "text")))))
       (itemsOf (propIn (props v) "files")))

fn writeFiles! id: String files: (List (Pair String String)) -> Bool
  (let [(home (str (root) "/" id "/home/.asl"))
        (calDir (str (root) "/" id "/cal"))
        (d1 (dirCreate home))
        (d2 (dirCreate calDir))
        (w1 (mt (fileText files ".asl/gateway.asn") ((some t) (ok? (fileWrite (str home "/gateway.asn") t))) ((none) true)))
        (w2 (mt (fileText files "cal") ((some t) (ok? (fileWrite (str calDir "/index.asn") t))) ((none) true)))]
    (check! (and (and (ok? d1) (ok? d2)) (and w1 w2)) (str id " files written under " (root))))

fn sameHeaders got: (List (Pair String String)) want: (List (Pair String String)) -> Bool
  (mt (listHead want)
    ((none) (listEmpty? got))
    ((some w)
      (mt (listHead got)
        ((none) false)
        ((some g) (and (and (= (pairFirst g) (pairFirst w)) (= (pairSecond g) (pairSecond w)))
                       (sameHeaders (optionOr (listTail got) (list)) (optionOr (listTail want) (list))))))))

fn checkResponse! c: Case resp: h/HttpResponse -> Bool
  (let [(label (str c.instance " GET " c.path))
        (a (check! (= resp.statusCode c.status) (str label " status " (stringFromInt64 resp.statusCode))))
        (b (check! (= resp.reasonPhrase c.reason) (str label " reason")))
        (d (check! (sameHeaders resp.headers.entries c.respHeaders) (str label " headers")))
        (same (= resp.body c.body))
        (shown (if same () (eprintln (str "  got:  " resp.body "\n  want: " c.body))))
        (e (check! same (str label " body byte-equal")))]
    (and (and a b) (and d e)))

fn searchResult! req: rt/SearchRequest c: Case cases: (List Case) -> (Result j/Json String)
  (if (stringEmpty? req.query)
    (mt (pairFirst (se/executeSearchHub! (se/newHubState (mapEmpty) 0 0 (mapEmpty) (mapEmpty)) "" req.engine req.limit))
      ((err e) (err (pt/pyErrText e)))
      ((ok r) (ok r)))
    (mt (listHead (filter (fn [(o Case)] -> Bool (and (= o.path c.path) (stringContains? (optionOr (lookup o.headers "Accept") "") "application/json"))) cases))
      ((none) (err (str "no JSON answer recorded for " c.path)))
      ((some o) (mt (pt/jsonLoads o.body) ((err e) (err (pt/pyErrText e))) ((ok r) (ok r))))))

fn lookup xs: (List (Pair String String)) k: String -> (Option String)
  (mt (listHead xs) ((none) (none)) ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (lookup (optionOr (listTail xs) (list)) k))))

fn replay! st: rt/GetState todo: (List Case) all: (List Case) okAcc: Bool -> Bool
  (mt (listHead todo)
    ((none) okAcc)
    ((some c)
      (let [(rest (optionOr (listTail todo) (list)))]
        (mt (rt/gatewayGet c.path c.headers st)
          ((rt/getRespond next resp) (replay! next rest all (and (checkResponse! c resp) okAcc)))
          ((rt/getSearch req)
            (mt (searchResult! req c all)
              ((err e) (replay! st rest all (and (check! false (str c.path " search result: " e)) okAcc)))
              ((ok res)
                (mt (rt/searchResponse req res)
                  ((err e) (replay! st rest all (and (check! false (str c.path " search render: " (pt/pyErrText e))) okAcc)))
                  ((ok resp) (replay! st rest all (and (checkResponse! c resp) okAcc)))))))
          ((rt/getCockpit p) (replay! st rest all (and (check! false (str c.path " routed to the cockpit")) okAcc)))
          ((rt/getFail e) (replay! st rest all (and (check! false (str c.path " failed: " (pt/pyErrText e))) okAcc)))))))

fn replayInstance! inst: Instance cases: (List Case) -> Bool
  (let [(mine (filter (fn [(c Case)] -> Bool (= c.instance inst.id)) cases))]
    (and (check! (not (listEmpty? mine)) (str inst.id " has recorded cases"))
         (replay! inst.state mine mine true)))

fn outcomeBody o: rt/GetOutcome -> String
  (mt o ((rt/getRespond _ r) r.body) (_ ""))

fn testRouting! st: rt/GetState -> Bool
  (let [(cockpit (listAll? (fn [(p String)] -> Bool (mt (rt/gatewayGet p (list) st) ((rt/getCockpit q) (= q p)) (_ false)))
                           (list "/cockpit" "/cockpit/" "/cockpit/api/intel" "/cockpit/api/memory")))
        (a (check! cockpit "cockpit paths route to the cockpit handlers"))
        (raw "GET /api/asl/browser/target/poll?targetId=tgt-2 HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: */*\r\n\r\n")
        (b (mt (h/parseHttpRequest raw)
             ((err e) (check! false (str "parseHttpRequest: " e)))
             ((ok req)
               (check! (= (outcomeBody (rt/gatewayGetRequest req st)) (outcomeBody (rt/gatewayGet "/api/asl/browser/target/poll?targetId=tgt-2" (list) st)))
                      "gatewayGetRequest answers the poll as the raw target does"))))
        (search (rt/gatewayGet "/api/asl/searchx?engine=wiki&limit=z&q=a+b&query=c" (list (pair "accept" "text/x, application/json")) st))
        (c (check! (mt search ((rt/getSearch r) (and (and (= r.query "a b") (= r.engine "wiki")) (and (= r.limit 5) r.json))) (_ false))
                  "search request: q before query, engine, int() fallback 5, Accept matched case-insensitively"))]
    (and (and a b) c))

fn testIntParse! -> Bool
  (let [(cases (list (pair "7" (some 7)) (pair " +1_0 " (some 10)) (pair "-3" (some -3)) (pair "z" (none)) (pair "1__0" (none))
                     (pair "_1" (none)) (pair "1_" (none)) (pair "" (none)) (pair "-" (none)) (pair "99999999999999999999" (none))))]
    (listAll? (fn [(c (Pair String (Option Int64)))] -> Bool
                (check! (mt (rt/pyIntParse (pairFirst c))
                         ((some n) (mt (pairSecond c) ((some m) (= n m)) ((none) false)))
                         ((none) (none? (pairSecond c))))
                       (str "int(" (pairFirst c) ")")))
              cases))

fn ! runTests -> Bool
  (mt (fileReadString (fixturePath))
    ((err e) (check! false (str "cannot read fixture: " e)))
    ((ok text)
      (mt (ck/asnReadText text)
        ((err e) (check! false (str "cannot parse fixture: " e)))
        ((ok forms)
          (let [(header (props (optionOr (listHead (filter (fn [(v ck/AsnVal)] -> Bool (= (headOf v) ":getRoutesFixture")) forms)) (ck/asnList (list)))))
                (cases (map toCase (filter (fn [(v ck/AsnVal)] -> Bool (= (headOf v) ":case")) forms)))
                (instForms (filter (fn [(v ck/AsnVal)] -> Bool (= (headOf v) ":instance")) forms))
                (countOk (check! (and (= (listLength cases) (intOf (propIn header "cases"))) (= (listLength instForms) (intOf (propIn header "instances"))))
                                (str "fixture holds " (stringFromInt64 (listLength cases)) " cases in " (stringFromInt64 (listLength instForms)) " instances as its header states")))]
            (fold (fn [(acc Bool) (v ck/AsnVal)] -> Bool
                    (let [(w (writeFiles! (textOf (propIn (props v) "id")) (filesOf v)))]
                    (mt (toInstance! v)
                      ((err e) (and (check! false e) acc))
                      ((ok inst)
                        (let [(r (replayInstance! inst cases))
                              (t (if (= inst.id "builtin") (testRouting! inst.state) true))]
                          (and (and w r) (and t acc)))))))
                  (and countOk (testIntParse!)) instForms))))))
