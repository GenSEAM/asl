(module aslGateway/tests/cockpitTest
  :x [runTests]
  :i [(cockpit :a ck)
      (localTime :a lt)
      (asl-json/json :a j)
      (asl-proc/coreProcess :a cp)])

(schema Case
  (:f id String)
  (:f kind String)
  (:f props (List (Pair String ck/AsnVal))))

fn check! b: Bool msg: String -> Bool
  (if b (do (assert b msg) true) (do (eprintln (str "FAIL: " msg)) false))

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/cockpitFixture.asn"

fn prop c: Case key: String -> (Option ck/AsnVal)
  (propIn c.props key)

fn propIn props: (List (Pair String ck/AsnVal)) key: String -> (Option ck/AsnVal)
  (if (listEmpty? props)
    (none)
    (if (= (pairFirst (preludeHead props)) key) (some (pairSecond (preludeHead props))) (propIn (preludeTail props) key)))

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

fn optIntOf v: (Option ck/AsnVal) -> (Option Int64)
  (stringToInt64 (atomOf v))

fn floatOf v: (Option ck/AsnVal) -> Float64
  (optionOr (stringToFloat64 (atomOf v)) 0.0)

fn itemsOf v: (Option ck/AsnVal) -> (List ck/AsnVal)
  (mt v
    ((some x) (mt x ((ck/asnList items) items) (_ (list))))
    ((none) (list)))

fn subProps v: ck/AsnVal -> (List (Pair String ck/AsnVal))
  (mt (ck/asnProps v (none)) ((ok p) p) ((err _) (list)))

fn headProps v: ck/AsnVal head: String -> (List (Pair String ck/AsnVal))
  (mt (ck/asnProps v (some head)) ((ok p) p) ((err _) (list)))

fn toCase v: ck/AsnVal -> Case
  (let [(p (headProps v ":case"))]
    (Case :id (optionOr (textOf (propIn p "id")) "") :kind (atomOf (propIn p "kind")) :props p))

fn caseForm? v: ck/AsnVal -> Bool
  (mt v
    ((ck/asnList items) (and (not (listEmpty? items)) (= (atomOf (listGet items 0)) ":case")))
    (_ false))

fn declaredCount forms: (List ck/AsnVal) -> Int64
  (if (listEmpty? forms) -1 (intOf (propIn (headProps (preludeHead forms) ":cockpitFixture") "cases")))

fn loadCases! -> (Result (List Case) String)
  (mt (fileReadString (fixturePath))
    ((err e) (err e))
    ((ok text)
      (mt (ck/asnReadText text)
        ((err e) (err (str "fixture: " e)))
        ((ok forms)
          (let [(cases (map toCase (filter caseForm? forms)))]
            (if (= (listLength cases) (declaredCount forms))
              (ok cases)
              (err (str "fixture declares " (stringFromInt64 (declaredCount forms)) " cases, holds " (stringFromInt64 (listLength cases))))))))))

fn entryPath root: String e: ck/AsnVal -> String
  (str root "/" (optionOr (textOf (propIn (subPropsAfterHead e) "path")) ""))

fn entryKind e: ck/AsnVal -> String
  (mt e ((ck/asnList items) (atomOf (listGet items 0))) (_ ""))

fn subPropsAfterHead e: ck/AsnVal -> (List (Pair String ck/AsnVal))
  (mt e ((ck/asnList items) (subProps (ck/asnList (listDrop items 1)))) (_ (list)))

fn parentOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn createEntry! root: String e: ck/AsnVal -> (Result Unit String)
  (let [(path (entryPath root e)) (props (subPropsAfterHead e)) (kind (entryKind e))]
    (cond
      ((= kind ":dir") (dirCreate path))
      ((= kind ":file")
        (mt (dirCreate (parentOf path))
          ((err e2) (err e2))
          ((ok _)
            (mt (bytesFromBase64 (optionOr (textOf (propIn props "b64")) ""))
              ((err e2) (err e2))
              ((ok bs) (fileWrite path bs))))))
      (else
        (mt (dirCreate (parentOf path))
          ((err e2) (err e2))
          ((ok _) (pathSymlink (optionOr (textOf (propIn props "target")) "") path))))))

fn touchEntry! root: String e: ck/AsnVal -> (Result Unit String)
  (mt (optIntOf (propIn (subPropsAfterHead e) "mtimeNs"))
    ((none) (ok ()))
    ((some ns) (fileUtime (entryPath root e) ns)))

fn chmodEntry! root: String e: ck/AsnVal restore: Bool -> (Result Unit String)
  (mt (optIntOf (propIn (subPropsAfterHead e) "mode"))
    ((none) (ok ()))
    ((some m) (fileChmod (entryPath root e) (if restore 493 m))))

fn eachOk f: (fn [ck/AsnVal] -> (Result Unit String)) xs: (List ck/AsnVal) -> (Result Unit String)
  (if (listEmpty? xs)
    (ok ())
    (mt (f (preludeHead xs)) ((err e) (err e)) ((ok _) (eachOk f (preludeTail xs)))))

fn materialize! root: String tree: (List ck/AsnVal) -> (Result Unit String)
  (mt (dirCreate root)
    ((err e) (err e))
    ((ok _)
      (mt (eachOk (fn [(e ck/AsnVal)] -> (Result Unit String) (createEntry! root e)) tree)
        ((err e) (err e))
        ((ok _)
          (mt (eachOk (fn [(e ck/AsnVal)] -> (Result Unit String) (touchEntry! root e)) tree)
            ((err e) (err e))
            ((ok _) (eachOk (fn [(e ck/AsnVal)] -> (Result Unit String) (chmodEntry! root e false)) (listReverse tree))))))))

fn teardown! root: String tree: (List ck/AsnVal) -> (Result Unit String)
  (mt (eachOk (fn [(e ck/AsnVal)] -> (Result Unit String) (chmodEntry! root e true)) tree)
    ((err e) (err e))
    ((ok _) (pathRemove root)))

fn statusOf c: Case -> ck/GatewayStatus
  (let [(p (subProps (optionOr (prop c "status") (ck/asnList (list)))))]
    (ck/GatewayStatus :pid (intOf (propIn p "pid")) :version (optionOr (textOf (propIn p "version")) "") :diskVersion (optionOr (textOf (propIn p "diskVersion")) "")
                      :stale (= (atomOf (propIn p "stale")) "true") :inFlight (intOf (propIn p "inFlight")) :draining (= (atomOf (propIn p "draining")) "true")
                      :updates (intOf (propIn p "updates"))))

fn poolOf v: ck/AsnVal -> ck/PoolStats
  (let [(items (mt v ((ck/asnList xs) xs) (_ (list))))
        (p (subProps (ck/asnList (listDrop items 2))))]
    (ck/PoolStats :name (optionOr (textOf (listGet items 1)) "") :size (intOf (propIn p "size")) :busy (intOf (propIn p "busy")) :queued (intOf (propIn p "queued"))))

fn errPair v: ck/AsnVal -> (Pair String Int64)
  (let [(items (mt v ((ck/asnList xs) xs) (_ (list))))]
    (pair (optionOr (textOf (listGet items 0)) "") (intOf (listGet items 1))))

fn usageRowOf v: ck/AsnVal -> ck/UsageRow
  (let [(items (mt v ((ck/asnList xs) xs) (_ (list))))
        (p (subProps (ck/asnList (listDrop items 2))))]
    (ck/UsageRow :name (optionOr (textOf (listGet items 1)) "") :requests (optIntOf (propIn p "requests")) :okCount (optIntOf (propIn p "ok"))
                 :errors (map errPair (itemsOf (propIn p "errors"))) :fallbacks (optIntOf (propIn p "fallbacks"))
                 :inputTokens (optIntOf (propIn p "inputTokens")) :cachedTokens (optIntOf (propIn p "cachedTokens")) :outputTokens (optIntOf (propIn p "outputTokens"))))

fn stateOf c: Case -> ck/CockpitState
  (let [(pp (subProps (optionOr (prop c "profile") (ck/asnList (list)))))]
    (ck/CockpitState :port (intOf (prop c "port")) :status (statusOf c)
                     :profile (ck/ProfileHealth :name (textOf (propIn pp "name")) :error (textOf (propIn pp "error")))
                     :pools (map poolOf (itemsOf (prop c "pools")))
                     :usage (ck/UsageSnapshot :since (floatOf (prop c "since")) :providers (map usageRowOf (itemsOf (prop c "providers"))) :aliases (map usageRowOf (itemsOf (prop c "aliases"))))
                     :now (if (= c.kind ":html") (floatOf (prop c "now")) 0.0)))

fn envOf! c: Case root: String platform: String -> (Result ck/CockpitEnv String)
  (mt (lt/zoneLoad! (textOf (prop c "tz")))
    ((err e) (err e))
    ((ok zone)
      (let [(html (= c.kind ":html"))
            (rel (optionOr (textOf (prop c "cwd")) ""))
            (cal (textOf (prop c "calEnv")))]
        (ok (ck/CockpitEnv :rootEnv (if (or html (= (atomOf (prop c "rootEnv")) "true")) (some root) (none))
                           :cwd (if (stringEmpty? rel) root (str root "/" rel))
                           :calibrationEnv (mt cal ((some s) (some (if (stringEmpty? s) "" (str root "/" s)))) ((none) (none)))
                           :zone zone :platform platform)))))

fn firstDiff a: String b: String i: Int64 -> Int64
  (if (or (>= i (stringLength a)) (>= i (stringLength b)) (not (= (optionOr (stringSlice a i (+ i 1)) "") (optionOr (stringSlice b i (+ i 1)) ""))))
    i
    (firstDiff a b (+ i 1)))

fn report! id: String got: String want: String -> Bool
  (if (= got want)
    true
    (let [(d (firstDiff got want 0))]
      (do (eprintln (str "MISMATCH " id " at byte " (stringFromInt64 d) "\n  got:  " (optionOr (stringSlice got (if (> d 80) (- d 80) 0) (if (> (+ d 120) (stringLength got)) (stringLength got) (+ d 120))) "")
                         "\n  want: " (optionOr (stringSlice want (if (> d 80) (- d 80) 0) (if (> (+ d 120) (stringLength want)) (stringLength want) (+ d 120))) "")))
          false)))

fn unroot s: String root: String -> String
  (stringReplace s root "@ROOT@")

fn checkHtml! c: Case root: String env: ck/CockpitEnv -> Bool
  (let [(t0 (monotonicNs))
        (got (ck/cockpitHtml! (stateOf c) env))
        (ms (/ (- (monotonicNs) t0) 1000000))]
    (do
      (when (stringStartsWith? c.id "large") (check! (< ms 5000) (str c.id ": rendered in " (stringFromInt64 ms) " ms, bound 5000")))
      (mt (textOf (prop c "want"))
        ((some want)
          (mt got
            ((ok html)
              (mt (textOf (prop c "portErrTile"))
                ((none) (check! (report! c.id (unroot html root) want) (str c.id ": HTML byte-identical to the original")))
                ((some title)
                  (let [(got (unroot html root))
                        (gotTile (tileOf got title))
                        (wantTile (tileOf want title))]
                    (and (check! (stringContains? gotTile "<p class=\"none\" title=\"no source\">") (str c.id ": port renders the " title " tile as missing: " gotTile))
                         (check! (not (= gotTile wantTile)) (str c.id ": the original rendered that tile from swallowed data"))
                         (check! (report! c.id (stringReplace got gotTile wantTile) want) (str c.id ": every other byte identical to the original")))))))
            ((err e) (check! (report! c.id (str "port error: " e) want) (str c.id ": port failed where the original rendered: " e)))))
        ((none) (check! (err? got) (str c.id ": original raised " (optionOr (textOf (prop c "raised")) "") ", port must fail"))))))

fn tileOf page: String title: String -> String
  (let [(open (str "<section class=\"tile\"><h2>" title))]
    (mt (stringIndexOf page open)
      ((none) "")
      ((some i)
        (let [(rest (optionOr (stringSlice page i (stringLength page)) ""))]
          (mt (stringIndexOf rest "</section>")
            ((none) "")
            ((some k) (optionOr (stringSlice rest 0 (+ k 10)) "")))))))

fn normJson text: String -> String
  (mt (j/jsonParse text) ((ok v) (j/jsonEmit v)) ((err e) (str "unparseable fixture json: " e)))

fn dataResult! c: Case env: ck/CockpitEnv cache: ck/IntelCache now: Float64 -> (Pair ck/IntelCache (Result j/Json String))
  (let [(k c.kind) (st (statusOf c))]
    (cond
      ((= k ":tasks") (pair cache (mt (ck/getTasksData! env) ((ok t) (ok (ck/tasksJson t))) ((err e) (err e)))))
      ((= k ":mem") (pair cache (mt (ck/getMemData! env) ((ok m) (ok (ck/memJson m))) ((err e) (err e)))))
      ((= k ":daemons") (pair cache (ok (ck/getDaemonsData st.pid (intOf (prop c "port")) st))))
      ((= k ":intel") (let [(r (ck/getIntelCouplingData! cache now env))] (pair (pairFirst r) (ok (pairSecond r)))))
      ((= k ":vitality") (let [(r (ck/getVitalityData! cache now env))] (pair (pairFirst r) (ok (pairSecond r)))))
      (else (let [(r (ck/getStubsData! cache now env))] (pair (pairFirst r) (ok (pairSecond r)))))))

fn checkRecordedCalls! c: Case root: String env: ck/CockpitEnv cache: ck/IntelCache calls: (List ck/AsnVal) results: (List ck/AsnVal) i: Int64 -> Bool
  (if (or (listEmpty? calls) (listEmpty? results))
    (check! (and (listEmpty? calls) (listEmpty? results)) (str c.id ": one recorded result per call"))
    (let [(now (optionOr (stringToFloat64 (atomOf (listGet calls 0))) 0.0))
          (step (dataResult! c env cache now))
          (want (subPropsAfterHead (ck/asnList (cons (ck/asnAtom ":r") (listItems (preludeHead results))))))
          (label (str c.id " call " (stringFromInt64 i)))
          (ok1 (mt (textOf (propIn want "json"))
                 ((some w)
                   (mt (pairSecond step)
                     ((ok v) (check! (and (none? (prop c "portErr")) (report! label (unroot (j/jsonEmit v) root) (normJson w)))
                                     (str label ": data equal to the original, and no data where the original swallowed an OS error")))
                     ((err e) (check! (and (some? (prop c "portErr")) (not (stringEmpty? e)))
                                      (str label ": port error only where the original swallowed one: " e)))))
                 ((none) (check! (err? (pairSecond step)) (str label ": original raised " (optionOr (textOf (propIn want "raised")) "") ", port must fail")))))]
      (and ok1 (checkRecordedCalls! c root env (pairFirst step) (preludeTail calls) (preludeTail results) (+ i 1)))))

fn listItems v: ck/AsnVal -> (List ck/AsnVal)
  (mt v ((ck/asnList items) items) (_ (list)))

fn stubDir c: Case root: String -> String
  (let [(stubs (filter (fn [(e ck/AsnVal)] -> Bool (stringEndsWith? (entryPath root e) "/asl")) (itemsOf (prop c "tree"))))]
    (if (listEmpty? stubs) (str root "/bin") (parentOf (entryPath root (preludeHead stubs)))))

fn checkLog! c: Case root: String -> Bool
  (mt (textOf (prop c "log"))
    ((none) true)
    ((some want)
      (let [(got (mt (fileReadString (str (stubDir c root) "/calls.log")) ((ok t) t) ((err _) "")))]
        (check! (report! (str c.id " argv log") (unroot got root) want) (str c.id ": asl intel invoked with the same argv and count")))))

fn runCase! base: String platform: String c: Case -> Bool
  (let [(root (str base "/" c.id))
        (tree (itemsOf (prop c "tree")))]
    (mt (materialize! root tree)
      ((err e) (check! (stringEmpty? e) (str c.id ": fixture tree not built: " e)))
      ((ok _)
        (let [(verdict (mt (envOf! c root platform)
                         ((err e) (check! (stringEmpty? e) (str c.id ": zone: " e)))
                         ((ok env)
                           (if (= c.kind ":html")
                             (checkHtml! c root env)
                             (and (checkRecordedCalls! c root env (ck/emptyIntelCache) (itemsOf (prop c "calls")) (itemsOf (prop c "results")) 0)
                                  (checkLog! c root))))))
              (cleaned (teardown! root tree))]
          (do (check! (ok? cleaned) (str c.id ": teardown " (mt cleaned ((ok _) "ok") ((err e) e))))
              verdict)))))

fn runAll! base: String platform: String cases: (List Case) passed: Int64 -> Int64
  (if (listEmpty? cases)
    passed
    (runAll! base platform (preludeTail cases) (if (runCase! base platform (preludeHead cases)) (+ passed 1) passed)))

fn testReplay! -> Bool
  (mt (loadCases!)
    ((err e) (check! (stringEmpty? e) (str "fixture: " e)))
    ((ok cases)
      (mt (platformInfo)
        ((err e) (check! (stringEmpty? e) (str "platformInfo: " e)))
        ((ok info)
          (let [(base0 (str "/tmp/aslCockpitParity-" (stringFromInt64 (procSelf))))]
            (mt (dirCreate base0)
              ((err e) (check! (stringEmpty? e) (str "temp dir: " e)))
              ((ok _)
                (mt (realPath base0)
                  ((err e) (check! (stringEmpty? e) (str "temp dir: " e)))
                  ((ok base)
                    (let [(passed (runAll! base info.os cases 0))
                          (removed (pathRemove base))]
                      (do (check! (ok? removed) "temp dir removed")
                          (check! (= passed (listLength cases)) (str (stringFromInt64 passed) " of " (stringFromInt64 (listLength cases)) " recorded cases replay equal")))))))))))))

fn intelSub kind: String -> String
  (if (= kind ":intel") "coupling" (optionOr (stringSlice kind 1 (stringLength kind)) kind))

fn intelCaseThroughAsl! c: Case -> Bool
  (let [(paths (map (fn [(e ck/AsnVal)] -> String (entryPath "" e)) (itemsOf (prop c "tree"))))
        (log (optionOr (textOf (prop c "log")) ""))
        (want (str "intel|" (intelSub c.kind) "|--json|"))
        (calls (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines log)))]
    (check! (and (not (listAny? (fn [(p String)] -> Bool (stringEndsWith? p "asl-intel")) paths))
                (listAll? (fn [(l String)] -> Bool (= l want)) calls))
           (str c.id ": intel runs as bin/asl " want " with no asl-intel stub; log " log)))

fn testFixtureIntelThroughAsl! -> Bool
  (mt (loadCases!)
    ((err e) (check! (stringEmpty? e) (str "fixture: " e)))
    ((ok cases)
      (let [(intelCases (filter (fn [(c Case)] -> Bool (listContains? (list ":intel" ":vitality" ":stubs") c.kind)) cases))
            (logged (filter (fn [(c Case)] -> Bool (not (stringEmpty? (optionOr (textOf (prop c "log")) "")))) intelCases))
            (kindsLogged (map (fn [(c Case)] -> String c.kind) logged))]
        (and (check! (listAll? (fn [(k String)] -> Bool (listContains? kindsLogged k)) (list ":intel" ":vitality" ":stubs"))
                    "each intel entry point has cases that record bin/asl calls")
             (listAll? intelCaseThroughAsl! intelCases)))))

fn testFixtureCoversEveryKind! -> Bool
  (mt (loadCases!)
    ((err e) (check! (stringEmpty? e) (str "fixture: " e)))
    ((ok cases)
      (let [(kinds (map (fn [(c Case)] -> String c.kind) cases))]
        (check! (listAll? (fn [(k String)] -> Bool (listContains? kinds k)) (list ":html" ":tasks" ":mem" ":daemons" ":intel" ":vitality" ":stubs"))
                "fixture exercises every ported entry point"))))

fn asnRejected text: String -> Bool
  (mt (ck/asnReadText text) ((err _) true) ((ok _) false))

fn testUnicodeSurrogateRejected -> Bool
  (asnRejected "\"\\uD800\"")

fn testUnicodeBracedLengthRejected -> Bool
  (asnRejected "\"\\u{0000001}\"")

fn ! runTests -> Bool
  (do
    (assert (testFixtureCoversEveryKind!) "testFixtureCoversEveryKind")
    (assert (testFixtureIntelThroughAsl!) "testFixtureIntelThroughAsl")
    (assert (testReplay!) "testReplay")
    (assert (testUnicodeSurrogateRejected) "testUnicodeSurrogateRejected")
    (assert (testUnicodeBracedLengthRejected) "testUnicodeBracedLengthRejected")
    true)
