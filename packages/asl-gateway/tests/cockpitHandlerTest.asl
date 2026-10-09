(module aslGateway/tests/cockpitHandlerTest
  :x [runTests]
  :i [(cockpit :a ck)
      (pyText :a pt)
      (localTime :a lt)
      (asl-json/json :a j)])

(schema Case
  (:f id String)
  (:f kind String)
  (:f props (List (Pair String ck/AsnVal))))

(schema ParityCase
  (:f id String)
  (:f raw String)
  (:f want String))

fn check! b: Bool msg: String -> Bool
  (if b (do (assert b msg) true) (do (eprintln (str "FAIL: " msg)) (assert false msg) false))

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/cockpitHandlerFixture.asn"

fn prop c: Case key: String -> (Option ck/AsnVal)
  (propIn c.props key)

fn propIn props: (List (Pair String ck/AsnVal)) key: String -> (Option ck/AsnVal)
  (if (listEmpty? props)
    (none)
    (if (= (pairFirst (preludeHead props)) key)
      (some (pairSecond (preludeHead props)))
      (propIn (preludeTail props) key)))

fn textOf v: (Option ck/AsnVal) -> (Option String)
  (mt v
    ((some x) (mt x ((ck/asnText s) (some s)) (_ (none))))
    ((none) (none)))

fn atomOf v: (Option ck/AsnVal) -> String
  (mt v
    ((some x) (mt x ((ck/asnAtom s) s) (_ "")))
    ((none) ""))

fn intOf v: (Option ck/AsnVal) -> Int64
  (optionOr (stringToInt64 (atomOf v)) 0)

fn boolOf v: (Option ck/AsnVal) -> Bool
  (mt v
    ((some x) (mt x ((ck/asnAtom s) (= s "true")) (_ false)))
    ((none) false))

fn headProps v: ck/AsnVal head: String -> (List (Pair String ck/AsnVal))
  (mt (ck/asnProps v (some head)) ((ok p) p) ((err _) (list)))

fn toCase v: ck/AsnVal -> Case
  (let [(p (headProps v ":case"))]
    (Case :id (optionOr (textOf (propIn p "id")) "")
          :kind (atomOf (propIn p "kind"))
          :props p))

fn toParityCase v: ck/AsnVal -> ParityCase
  (let [(p (headProps v ":parityCase"))]
    (ParityCase :id (optionOr (textOf (propIn p "id")) "")
                :raw (optionOr (textOf (propIn p "raw")) "")
                :want (optionOr (textOf (propIn p "want")) "")))

fn headerPairs v: ck/AsnVal -> (List (Pair String String))
  (mt v
    ((ck/asnList items)
      (map (fn [(item ck/AsnVal)] -> (Pair String String)
             (mt item
               ((ck/asnList pairItems)
                 (let [(k (optionOr (textOf (listGet pairItems 0)) (atomOf (listGet pairItems 0))))
                       (val (optionOr (textOf (listGet pairItems 1)) (atomOf (listGet pairItems 1))))]
                   (pair k val)))
               (_ (pair "" ""))))
           items))
    (_ (list)))

fn testParityCases! pcases: (List ParityCase) -> Bool
  (if (listEmpty? pcases)
    true
    (let [(pc (preludeHead pcases))
          (parsed (resultOr (j/jsonParse pc.raw) (j/jnull)))
          (got (ck/pyJsonDump parsed))
          (want pc.want)
          (ok1 (check! (= got want) (str "parityCase " pc.id " exact match")))]
      (and ok1 (testParityCases! (preludeTail pcases)))))

fn testObservatoryCases! cases: (List Case) -> Bool
  (let [(obsCases (filter (fn [(c Case)] -> Bool (= c.kind ":observatory")) cases))]
    (if (listEmpty? obsCases)
      (check! false "no observatory cases found in fixture")
      (listAll? (fn [(c Case)] -> Bool
                  (let [(rawPayload (optionOr (textOf (prop c "payload")) "{}"))
                        (intelJson (resultOr (j/jsonParse rawPayload) (j/jnull)))
                        (transformed (ck/observatoryBlastRadius intelJson))
                        (transformedSnake (ck/observatory_blast_radius intelJson))
                        (gotJson (ck/pyJsonDump transformed))
                        (gotSnakeJson (ck/pyJsonDump transformedSnake))
                        (wantJson (optionOr (textOf (prop c "body")) ""))
                        (limitOk (if (= c.id "obs_over6")
                                   (mt (j/jsonGet intelJson "packages")
                                     ((some packagesVal)
                                      (mt packagesVal
                                        ((j/jarr packages)
                                         (mt (j/jsonGet transformed "blastRadius")
                                           ((some blastVal)
                                            (mt blastVal
                                              ((j/jarr blastNodes)
                                               (check! (and (> (listLength packages) 6)
                                                           (= (listLength blastNodes) 6))
                                                      "observatory blast radius truncates to six with more than six packages"))
                                              (_ (check! false "observatory blastRadius is an array"))))
                                           (_ (check! false "observatory blastRadius exists"))))
                                        (_ (check! false "observatory packages is an array"))))
                                     (_ (check! false "observatory packages exists")))
                                   true))
                        (ok1 (check! (= gotJson wantJson) (str "observatoryBlastRadius exact match for " c.id)))
                        (ok2 (check! (= gotSnakeJson wantJson) (str "observatory_blast_radius exact match for " c.id)))]
                    (and (and ok1 ok2) limitOk)))
                obsCases)))

fn checkHeaderMatch! got: (List (Pair String String)) want: (List (Pair String String)) id: String -> Bool
  (if (listEmpty? want)
    true
    (let [(head (preludeHead want))
          (k (pairFirst head))
          (wVal (pairSecond head))
          (found (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) got))]
      (if (listEmpty? found)
        (check! false (str id " missing header " k))
        (and (check! (= (pairSecond (preludeHead found)) wVal) (str id " header " k " match"))
             (checkHeaderMatch! got (preludeTail want) id)))))

fn checkResp! resp: ck/CockpitResponse wantStatus: Int64 wantHeaders: (List (Pair String String)) wantBody: String id: String isHtml: Bool -> Bool
  (let [(sOk (check! (= resp.status wantStatus) (str id " status match")))
        (hOk (checkHeaderMatch! resp.headers wantHeaders id))
        (bOk (if isHtml
               (check! (= resp.body wantBody) (str id " html body exact match"))
               (check! (= resp.body wantBody) (str id " body exact match"))))]
    (and (and sOk hOk) bOk))

fn setupTestDirs! -> Bool
  (let [(r1 (dirCreate "/tmp/cockpitParityEmpty"))
        (r2 (dirCreate "/tmp/cockpitParityPopulated/.asl/mem/decisions"))
        (r3 (dirCreate "/tmp/cockpitParityPopulated/.asl/mem/tasks"))
        (r4 (dirCreate "/tmp/cockpitParityPopulated/.asl/mem/receipts"))
        (r5 (fileWrite "/tmp/cockpitParityPopulated/.asl/mem/decisions/D1.asn" "(:decision :d1)"))
        (r6 (fileWrite "/tmp/cockpitParityPopulated/.asl/mem/notes.asn" "notes-1234"))]
    (and (and (and (ok? r1) (ok? r2)) (and (ok? r3) (ok? r4))) (and (ok? r5) (ok? r6))))

fn testCaseDispatch! c: Case -> Bool
  (let [(path (optionOr (textOf (prop c "path")) ""))
        (wantStatus (intOf (prop c "status")))
        (wantHeaders (headerPairs (optionOr (prop c "headers") (ck/asnList (list)))))
        (wantBody (optionOr (textOf (prop c "body")) ""))
        (payloadStr (optionOr (textOf (prop c "payload")) "{}"))
        (payloadJson (resultOr (j/jsonParse payloadStr) (j/jnull)))
        (cRoot (optionOr (textOf (prop c "root")) "/tmp/cockpitParityDash"))
        (caseEnv (ck/CockpitEnv :rootEnv (some cRoot) :cwd cRoot :calibrationEnv (none) :zone (lt/utcZone) :platform "darwin"))
        (dummyEnv (ck/CockpitEnv :rootEnv (some "/tmp/cockpitParityDash") :cwd "/tmp/cockpitParityDash" :calibrationEnv (none) :zone (lt/utcZone) :platform "darwin"))
        (dummyState (ck/CockpitState :status (ck/GatewayStatus :pid 4242 :version "abc123def456" :diskVersion "abc123def456"
                                                              :stale false :inFlight 1 :draining false :updates 0)
                                     :port 8765
                                     :pools (list)
                                     :usage (ck/UsageSnapshot :since 1767229200.75 :providers (list) :aliases (list))
                                     :profile (ck/ProfileHealth :name (some "work") :error (none))
                                     :now 1767232800.5))
        (caseCaches (ck/CockpitCaches
                      :intel (ck/IntelCache :timestamp 1767232800.5 :data (some payloadJson))
                      :vitality (ck/IntelCache :timestamp 1767232800.5 :data (some payloadJson))
                      :stubs (ck/IntelCache :timestamp 1767232800.5 :data (some payloadJson))))
        (kind c.kind)]
    (cond
      ((= kind ":dashboard")
        (let [(resp1 (resultOr (ck/serveCockpitDashboard! dummyState dummyEnv) (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (resp2 (resultOr (ck/serve_cockpit_dashboard! dummyState dummyEnv) (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (disp (ck/cockpitDispatchGet! path dummyState dummyEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState dummyEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") true)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") true))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") true)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") true)))))

      ((= kind ":observatory")
        (let [(step1 (ck/serveCockpitObservatoryApi! caseCaches.intel dummyState.now dummyEnv))
              (resp1 (pairSecond step1))
              (step2 (ck/serve_cockpit_observatory_api! caseCaches.intel dummyState.now dummyEnv))
              (resp2 (pairSecond step2))
              (disp (ck/cockpitDispatchGet! path dummyState dummyEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState dummyEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      ((= kind ":intel")
        (let [(step1 (ck/serveCockpitIntelApi! caseCaches.intel dummyState.now dummyEnv))
              (resp1 (pairSecond step1))
              (step2 (ck/serve_cockpit_intel_api! caseCaches.intel dummyState.now dummyEnv))
              (resp2 (pairSecond step2))
              (disp (ck/cockpitDispatchGet! path dummyState dummyEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState dummyEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      ((= kind ":vitality")
        (let [(step1 (ck/serveCockpitVitalityApi! caseCaches.vitality dummyState.now dummyEnv))
              (resp1 (pairSecond step1))
              (step2 (ck/serve_cockpit_vitality_api! caseCaches.vitality dummyState.now dummyEnv))
              (resp2 (pairSecond step2))
              (disp (ck/cockpitDispatchGet! path dummyState dummyEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState dummyEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      ((= kind ":stubs")
        (let [(step1 (ck/serveCockpitStubsApi! caseCaches.stubs dummyState.now dummyEnv))
              (resp1 (pairSecond step1))
              (step2 (ck/serve_cockpit_stubs_api! caseCaches.stubs dummyState.now dummyEnv))
              (resp2 (pairSecond step2))
              (disp (ck/cockpitDispatchGet! path dummyState dummyEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState dummyEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      ((= kind ":daemons")
        (let [(cStatus (ck/GatewayStatus
                         :pid (intOf (prop c "pid"))
                         :version (optionOr (textOf (prop c "version")) "abc123def456")
                         :diskVersion (optionOr (textOf (prop c "version")) "abc123def456")
                         :stale false
                         :inFlight (intOf (prop c "inFlight"))
                         :draining (boolOf (prop c "draining"))
                         :updates 0))
              (cPort (intOf (prop c "port")))
              (cState (ck/CockpitState :status cStatus
                                       :port cPort
                                       :pools (list)
                                       :usage dummyState.usage
                                       :profile dummyState.profile
                                       :now dummyState.now))
              (resp1 (ck/serveCockpitDaemonsApi cStatus.pid cPort cStatus))
              (resp2 (ck/serve_cockpit_daemons_api cStatus.pid cPort cStatus))
              (disp (ck/cockpitDispatchGet! path cState dummyEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path cState dummyEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      ((= kind ":tasks")
        (let [(resp1 (resultOr (ck/serveCockpitTasksApi! caseEnv) (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (resp2 (resultOr (ck/serve_cockpit_tasks_api! caseEnv) (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (disp (ck/cockpitDispatchGet! path dummyState caseEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState caseEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      ((= kind ":mem")
        (let [(resp1 (resultOr (ck/serveCockpitMemApi! caseEnv) (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (resp2 (resultOr (ck/serve_cockpit_mem_api! caseEnv) (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (disp (ck/cockpitDispatchGet! path dummyState caseEnv caseCaches))
              (dispSnake (ck/cockpit_dispatch_get! path dummyState caseEnv caseCaches))
              (dResp (resultOr (optionOr disp (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))
              (dRespSnake (resultOr (optionOr dispSnake (ck/CockpitDispatchResult :caches caseCaches :response (err "none"))).response (ck/CockpitResponse :status 500 :headers (list) :body "")))]
          (and (and (checkResp! resp1 wantStatus wantHeaders wantBody (str c.id " camel") false)
                    (checkResp! resp2 wantStatus wantHeaders wantBody (str c.id " snake") false))
               (and (checkResp! dResp wantStatus wantHeaders wantBody (str c.id " dispatch") false)
                    (checkResp! dRespSnake wantStatus wantHeaders wantBody (str c.id " dispatchSnake") false)))))

      (else (check! false (str "unrecognized fixture kind " kind)))))

fn testAllCases! cases: (List Case) -> Bool
  (if (listEmpty? cases)
    true
    (let [(c (preludeHead cases))
          (ok1 (testCaseDispatch! c))]
      (and ok1 (testAllCases! (preludeTail cases)))))

fn testRoutingAndAliases! -> Bool
  (let [(dummyEnv (ck/CockpitEnv :rootEnv (some "/tmp/cockpitParityDash") :cwd "/tmp/cockpitParityDash" :calibrationEnv (none) :zone (lt/utcZone) :platform "darwin"))
        (dummyState (ck/CockpitState :status (ck/GatewayStatus :pid 4242 :version "v1" :diskVersion "v1"
                                                              :stale false :inFlight 0 :draining false :updates 0)
                                     :port 8765
                                     :pools (list)
                                     :usage (ck/UsageSnapshot :since 1767229200.75 :providers (list) :aliases (list))
                                     :profile (ck/ProfileHealth :name (some "work") :error (none))
                                     :now 1767232800.5))
        (caches (ck/emptyCockpitCaches))
        (routes (list "/cockpit" "/cockpit/" "/cockpit/api/observatory" "/cockpit/api/intel"
                      "/cockpit/api/coupling" "/cockpit/api/vitality" "/cockpit/api/stubs"
                      "/cockpit/api/daemons" "/cockpit/api/tasks" "/cockpit/api/mem" "/cockpit/api/memory"))
        (matchedAll (fold (fn [(okAll Bool) (p String)] -> Bool
                            (and okAll (some? (ck/cockpitDispatchGet! p dummyState dummyEnv caches))))
                          true routes))
        (ok1 (check! matchedAll "every cockpit path and alias resolves in cockpitDispatchGet"))
        (ok2 (check! (none? (ck/cockpitDispatchGet! "/unknown" dummyState dummyEnv caches)) "unknown path returns none"))
        (ok3 (check! (none? (ck/cockpitDispatchGet! "/api/asl/status" dummyState dummyEnv caches)) "non-cockpit path returns none"))]
    (and (and ok1 ok2) ok3))

fn ! runTests -> Bool
  (let [(dirsOk (setupTestDirs!))]
    (if (not (check! dirsOk "test directories initialized"))
      false
      (mt (fileReadString (fixturePath))
        ((err e) (do (eprintln (str "cannot read fixture: " e)) false))
        ((ok text)
          (mt (ck/asnReadText text)
            ((err e) (do (eprintln (str "cannot parse fixture ASN: " e)) false))
            ((ok forms)
              (let [(cases (map toCase (filter (fn [(v ck/AsnVal)] -> Bool
                                                 (mt v ((ck/asnList items)
                                                        (mt (listHead items)
                                                          ((some h) (mt h ((ck/asnAtom a) (= a ":case")) (_ false)))
                                                          (_ false)))
                                                       (_ false))) forms)))
                    (pcases (map toParityCase (filter (fn [(v ck/AsnVal)] -> Bool
                                                        (mt v ((ck/asnList items)
                                                               (mt (listHead items)
                                                                 ((some h) (mt h ((ck/asnAtom a) (= a ":parityCase")) (_ false)))
                                                                 (_ false)))
                                                               (_ false))) forms)))
                    (pOk (testParityCases! pcases))
                    (oOk (testObservatoryCases! cases))
                    (cOk (testAllCases! cases))
                    (rOk (testRoutingAndAliases!))]
                (and (and (and pOk oOk) cOk) rOk))))))))
