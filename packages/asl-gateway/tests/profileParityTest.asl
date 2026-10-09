(module aslGateway/tests/profileParityTest
  :x [runTests]
  :i [(config :a cfg)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)])

fn isNone? expr: rd/SExpr -> Bool
  (mt expr
    ((rd/sexprAtom v) (= v ":none"))
    (_ false))

fn scalarText expr: rd/SExpr -> String
  (cfg/scalarToString (cfg/asnScalar expr))

fn prop props: (Map String rd/SExpr) key: String -> rd/SExpr
  (optionOr (mapGet props key) (rd/makeAtom ":none"))

fn propStr props: (Map String rd/SExpr) key: String -> String
  (scalarText (prop props key))

fn propOptStr props: (Map String rd/SExpr) key: String -> (Option String)
  (let [(e (prop props key))]
    (if (isNone? e) (none) (some (scalarText e))))

fn items expr: rd/SExpr -> (List rd/SExpr)
  (mt expr
    ((rd/sexprList xs) xs)
    ((rd/sexprVect xs) xs)
    (_ (list)))

fn strs expr: rd/SExpr -> (List String)
  (map scalarText (items expr))

fn atomText expr: rd/SExpr -> String
  (mt expr
    ((rd/sexprAtom v) v)
    (_ ""))

fn propsOf expr: rd/SExpr -> (Map String rd/SExpr)
  (let [(xs (items expr))]
    (if (= (mod (listLength xs) 2) 1)
      (resultOr (cfg/asnProps expr (some (atomText (optionOr (listHead xs) (rd/makeAtom ""))))) (mapEmpty))
      (resultOr (cfg/asnProps expr (none)) (mapEmpty))))

fn allRun results: (List Bool) -> Bool
  (fold (fn [(acc Bool) (b Bool)] -> Bool (and b acc)) true results)

fn check c: Bool msg: String -> Bool
  (do
    (assert c msg)
    c)

fn pairsOf expr: rd/SExpr -> (List (Pair String String))
  (map (fn [(h rd/SExpr)] -> (Pair String String)
         (let [(xs (strs h))]
           (pair (optionOr (listHead xs) "") (optionOr (listHead (optionOr (listTail xs) (list))) ""))))
       (items expr))

fn sub root: String s: String -> String
  (stringReplace s "@ROOT@" root)

fn entryText e: cfg/GatewayResolvedEntry -> String
  (mt e
    ((cfg/entryResolved en) (str en.alias "|" en.kind "|" en.dispatch "|" en.upstream.provider "|" en.upstream.url))
    ((cfg/entryUnresolved a) (str a "|string|||")))

fn fixtureEntryText expr: rd/SExpr -> String
  (let [(p (propsOf expr))]
    (str (propStr p "label") "|" (propStr p "kind") "|" (propStr p "dispatch") "|" (propStr p "provider") "|" (propStr p "url")))

fn undeclaredText m: (Map String Int64) -> String
  (stringJoin (map (fn [(p (Pair String Int64))] -> String (str (pairFirst p) "=" (stringFromInt64 (pairSecond p)))) (mapPairs m)) ";")

fn fixtureUndeclaredText expr: rd/SExpr -> String
  (stringJoin (map (fn [(h rd/SExpr)] -> String
                     (let [(xs (items h))]
                       (str (scalarText (optionOr (listHead xs) (rd/makeAtom ""))) "=" (scalarText (optionOr (listHead (optionOr (listTail xs) (list))) (rd/makeAtom ""))))))
                   (items expr))
              ";")

fn loadText r: (Result cfg/GatewayTable String) -> String
  (mt r
    ((ok t) (str "ok " t.source " v" (stringFromInt64 t.version)))
    ((err e) (str "err " e)))

fn keyText k: cfg/ConfigKey -> String
  (mt k
    ((cfg/keyBuiltin) "builtin")
    ((cfg/keyFiles parts)
      (stringJoin (map (fn [(p (Pair String (Option (Pair Int64 Int64))))] -> String
                         (mt (pairSecond p)
                           ((some st) (str (pairFirst p) " true " (stringFromInt64 (pairSecond st))))
                           ((none) (str (pairFirst p) " false 0"))))
                       parts)
                  ";")))

fn fixtureKeyText root: String expr: rd/SExpr -> String
  (stringJoin (map (fn [(h rd/SExpr)] -> String
                     (let [(p (propsOf h))]
                       (str (sub root (propStr p "path")) " " (propStr p "exists") " " (propStr p "size"))))
                   (items expr))
              ";")

fn writeCaseFiles! home: String c: (Map String rd/SExpr) -> Bool
  (let [(made (and (ok? (dirCreate (str home "/.asl"))) (ok? (dirCreate (str home "/cal")))))
        (written (listAll? (fn [(f rd/SExpr)] -> Bool
                             (let [(p (propsOf f))]
                               (ok? (fileWrite (str home "/" (propStr p "path")) (propStr p "text")))))
                           (items (prop c "files"))))
        (dirs (listAll? (fn [(d String)] -> Bool (ok? (dirCreate (str home "/" d)))) (strs (prop c "dirs"))))]
    (and made written dirs))

fn checkQuery! root: String cid: String loaded: (Result cfg/GatewayTable String) path: String exists: Bool prefixOnly: Bool qExpr: rd/SExpr -> Bool
  (let [(q (propsOf qExpr))
        (headers (pairsOf (prop q "headers")))
        (env (propOptStr q "env"))
        (intent (propStr q "intent"))
        (what (str cid " intent=" intent " env=" (optionOr env "-") " headers=" (stringJoin (map (fn [(h (Pair String String))] -> String (str (pairFirst h) ":" (pairSecond h))) headers) ",")))
        (wantAsn (if (= cid "builtin")
                   (stringReplace (propStr q "profileAsn") "\"builtin\"" (str "\"" path "\""))
                   (sub root (propStr q "profileAsn"))))
        (gotAsn (cfg/gatewayProfileAsn (cfg/gatewayProfileHealth loaded headers env path exists)))]
    (allRun (list
      (if prefixOnly
        (check (and (stringStartsWith? gotAsn (str "(:error \"" path ": ")) (stringEndsWith? gotAsn (str ":source \"" path "\")"))) (str what ": profile health error form " gotAsn))
        (check (= gotAsn wantAsn) (str what ": profile health asn " gotAsn " want " wantAsn)))
      (mt loaded
        ((err _) (err? loaded))
        ((ok table)
          (let [(nameWant (propsOf (prop q "name")))
                (nameGot (cfg/gatewayProfileName table headers env))
                (nameGotText (mt nameGot ((ok n) (str "true " n)) ((err e) (str "false " e))))
                (nameWantText (str (propStr nameWant "ok") " " (propStr nameWant "value")))]
            (allRun (list
              (check (= nameGotText nameWantText) (str what ": profile name " nameGotText " want " nameWantText))
              (if (isNone? (prop q "select"))
                (check (err? (cfg/gatewayProfileSelect table headers env)) (str what ": select fails with the name"))
                (let [(selWant (propsOf (prop q "select")))
                      (selGot (cfg/gatewayProfileSelect table headers env))
                      (selText (mt selGot ((ok s) (str s.name " " s.source)) ((err e) (str "err " e))))
                      (routed (cfg/gatewayRouteEntries! table headers env intent))
                      (entriesGot (mt routed ((ok r) (stringJoin (map entryText r.entries) "\n")) ((err e) (str "err " e))))
                      (entriesWant (stringJoin (map fixtureEntryText (items (prop q "entries"))) "\n"))
                      (undGot (mt routed ((ok r) (undeclaredText r.table.undeclaredIntents)) ((err e) (str "err " e))))
                      (undWant (fixtureUndeclaredText (prop q "undeclared")))
                      (modelsExpr (prop q "models"))
                      (modelsWant (cond ((isNone? modelsExpr) "none") ((= (scalarText modelsExpr) "skip") "skip") (else (stringJoin (strs modelsExpr) ","))))
                      (modelsGot (if (= modelsWant "skip")
                                   "skip"
                                   (mt selGot
                                     ((err e) (str "err " e))
                                     ((ok s) (mt (cfg/gatewayProfileModels s.profile.routes intent) ((none) "none") ((some ms) (stringJoin ms ",")))))))]
                  (allRun (list
                    (check (= selText (str (propStr selWant "name") " " (if (= cid "builtin") path (sub root (propStr selWant "source"))))) (str what ": select " selText))
                    (check (= entriesGot entriesWant) (str what ": route entries " entriesGot " want " entriesWant))
                    (check (= undGot undWant) (str what ": undeclared intents " undGot " want " undWant))
                    (check (= modelsGot modelsWant) (str what ": profile models " modelsGot " want " modelsWant))))))))))))))

fn checkCase! root: String cExpr: rd/SExpr -> Bool
  (let [(c (propsOf cExpr))
        (cid (propStr c "id"))
        (home (str root "/" cid))
        (filesOk (writeCaseFiles! home c))
        (registry (str home "/cal/index.asn"))
        (path (cfg/gatewayProfilesPath home))
        (builtin (if (= cid "builtin")
                    (resultOr (fileReadString "asl/packages/asl-gateway/tests/fixtures/builtinConfig/gateway.asn") "")
                    ""))
        (builtinWritten (if (= cid "builtin") (ok? (fileWrite path builtin)) true))
        (exists (fileExists? path))
        (prefixOnly (= (propStr c "match") "prefix"))
        (loaded (pairSecond (cfg/gatewayProfilesLoad! (cfg/emptyProfilesCache) home registry)))
        (pure (if (= cid "builtin")
                (cfg/gatewayProfilesLoadText! path true (ok builtin) registry)
                (cfg/gatewayProfilesLoadText! path exists (fileReadString path) registry)))
        (ld (propsOf (prop c "load")))
        (wantLoad (if (= (propStr ld "ok") "true")
                    (str "ok " (if (= cid "builtin") path (sub root (propStr ld "source"))) " v" (propStr ld "v"))
                    (str "err " (sub root (propStr ld "error")))))
        (gotLoad (loadText loaded))
        (health (cfg/gatewayConfigHealth loaded))
        (wantWarn (map (fn [(s String)] -> String (sub root s)) (strs (prop c "warnLines"))))
        (gotWarn (mt loaded ((ok t) (if exists (cfg/gatewayLoadWarningLines path t) (list))) ((err _) (list))))
        (cw (prop c "configWarnings"))
        (wantCw (if (isNone? cw) "none" (stringJoin (map (fn [(s String)] -> String (sub root s)) (strs cw)) "\n")))
        (gotCw (mt health ((none) "none") ((some h) (stringJoin h.warnings "\n"))))
        (wantRe (mt (propOptStr c "registryError") ((none) "none") ((some s) (sub root s))))
        (gotRe (mt health ((none) "none") ((some h) (optionOr h.registryError "none"))))]
    (allRun (list
      (check (and filesOk builtinWritten) (str cid ": synthetic files written under " home))
      (check (= path (sub root (propStr c "path"))) (str cid ": profiles path " path))
      (if (isNone? (prop c "key"))
        (check exists (str cid ": unkeyed case has its path"))
        (let [(gotKey (keyText (cfg/gatewayConfigKey! path registry)))
              (wantKey (fixtureKeyText root (prop c "key")))]
          (check (= gotKey wantKey) (str cid ": config key " gotKey " want " wantKey))))
      (if prefixOnly
        (check (and (err? loaded) (stringStartsWith? gotLoad (str "err " path ": "))) (str cid ": load error prefix " gotLoad))
        (check (= gotLoad wantLoad) (str cid ": load " gotLoad " want " wantLoad)))
      (check (= (loadText pure) gotLoad) (str cid ": pure load equals the IO shell"))
      (check (= (stringJoin gotWarn "\n") (stringJoin wantWarn "\n")) (str cid ": stderr warning lines " (stringJoin gotWarn "|")))
      (check (= (cfg/gatewayConfigAsn health) (sub root (propStr c "configAsn"))) (str cid ": config asn " (cfg/gatewayConfigAsn health)))
      (check (= gotCw wantCw) (str cid ": config warnings " gotCw " want " wantCw))
      (check (= gotRe wantRe) (str cid ": registry error " gotRe " want " wantRe))
      (allRun (map (fn [(qe rd/SExpr)] -> Bool (checkQuery! root cid loaded path exists prefixOnly qe)) (items (prop c "queries")))))))

fn cacheResultText r: (Result cfg/GatewayTable String) -> String
  (mt r
    ((ok t) t.source)
    ((err e) (str "error: " e)))

fn checkCache! root: String cacheList: (List rd/SExpr) -> Bool
  (let [(home (str root "/v1file"))
        (registry (str home "/cal/index.asn"))
        (path (cfg/gatewayProfilesPath home))
        (key (cfg/gatewayConfigKey! path registry))
        (sentinel (cfg/gatewayProfilesLoadText! "sentinel" true (fileReadString path) registry))
        (recorded (map (fn [(e rd/SExpr)] -> String (let [(p (propsOf e))] (str (propStr p "id") "=" (sub root (propStr p "result"))))) cacheList))
        (hit (cacheResultText (pairSecond (cfg/gatewayProfilesLoad! (cfg/ProfilesCache :key (some key) :result sentinel) home registry))))
        (cachedErr (cacheResultText (pairSecond (cfg/gatewayProfilesLoad! (cfg/ProfilesCache :key (some key) :result (err "boom")) home registry))))
        (staleShell (cfg/gatewayProfilesLoad! (cfg/ProfilesCache :key (some (cfg/keyBuiltin)) :result sentinel) home registry))
        (stale (cacheResultText (pairSecond staleShell)))]
    (allRun (list
      (check (= (listLength cacheList) 3) "three cache cases recorded")
      (check (listContains? recorded (str "hit=" hit)) (str "cache hit returns the cached table: " hit))
      (check (listContains? recorded (str "cachedError=" cachedErr)) (str "cached error is raised again: " cachedErr))
      (check (listContains? recorded (str "stale=" stale)) (str "stale key reloads: " stale))
      (check (mt (pairFirst staleShell).key ((some k) (cfg/configKeyEqual? k key)) ((none) false)) "reload stores the current key"))))

fn routeOf expr: rd/SExpr -> cfg/GatewayRoute
  (let [(p (propsOf expr))]
    (cfg/GatewayRoute :intent (propStr p "intent") :chain (strs (prop p "chain")) :models (strs (prop p "models"))))

fn checkModels mExpr: rd/SExpr -> Bool
  (let [(p (propsOf mExpr))
        (routes (map routeOf (items (prop p "routes"))))
        (intent (optionOr (propOptStr p "intent") ""))
        (r (prop p "result"))
        (want (if (isNone? r) "none" (stringJoin (strs r) ",")))
        (got (mt (cfg/gatewayProfileModels routes intent) ((none) "none") ((some ms) (stringJoin ms ","))))]
    (check (= got want) (str "profile models intent=" intent ": " got " want " want)))

fn checkReceipt rExpr: rd/SExpr -> Bool
  (let [(p (propsOf rExpr))
        (got (cfg/gatewayConfigReceipt (propStr p "file") (propStr p "registry") (propStr p "status")
                                       (optionOr (stringToInt64 (propStr p "v")) -1) (strs (prop p "errors")) (strs (prop p "warnings")) (propStr p "extra")))]
    (check (= got (propStr p "result")) (str "config receipt " got)))

fn checkPath pExpr: rd/SExpr -> Bool
  (let [(p (propsOf pExpr))
        (got (cfg/gatewayProfilesPath (propStr p "home")))]
    (check (= got (propStr p "result")) (str "profiles path for home " (propStr p "home") ": " got)))

fn healthOf expr: rd/SExpr -> cfg/ProfileHealth
  (let [(p (propsOf expr))
        (kind (propStr p "kind"))
        (routes (map routeOf (items (prop p "routes"))))]
    (cond
      ((= kind "error") (cfg/healthError (propStr p "error") (propStr p "source")))
      ((= kind "v2") (cfg/healthV2 (propStr p "name") routes (propOptStr p "fallback") (propStr p "source")))
      (else (cfg/healthV1 (propStr p "name") routes (propStr p "source")))))

fn checkHealthAsn hExpr: rd/SExpr -> Bool
  (let [(p (propsOf hExpr))
        (got (cfg/gatewayProfileAsn (healthOf (prop p "info"))))]
    (check (= got (propStr p "result")) (str "profile asn " got)))

fn tempRoot! -> String
  (let [(base (optionOr (envGet "TMPDIR") "/tmp"))
        (trimmed (if (and (stringEndsWith? base "/") (> (stringLength base) 1)) (optionOr (stringSlice base 0 (- (stringLength base) 1)) base) base))]
    (str trimmed "/aslGw2Parity" (stringFromInt64 (nowNs))))

fn runFixture! f: (Map String rd/SExpr) -> Bool
  (let [(root (tempRoot!))
        (made (dirCreate root))
        (cases (items (prop f "cases")))
        (models (items (prop f "models")))
        (receipts (items (prop f "receipts")))
        (paths (items (prop f "paths")))
        (healths (items (prop f "healthAsn")))
        (parityKey (propStr f "parityKey"))]
    (allRun (list
      (check (ok? made) (str "temp root created " root))
      (check (none? (envGet parityKey)) (str parityKey " must be unset for the recorded key warnings"))
      (check (>= (listLength cases) 9) "at least 9 recorded profile cases")
      (check (>= (listLength models) 10) "at least 10 recorded profile model cases")
      (let [(casesOk (allRun (map (fn [(c rd/SExpr)] -> Bool (checkCase! root c)) cases)))
            (cacheOk (checkCache! root (items (prop f "cache"))))
            (modelsOk (allRun (map checkModels models)))
            (receiptsOk (allRun (map checkReceipt receipts)))
            (pathsOk (allRun (map checkPath paths)))
            (healthOk (allRun (map checkHealthAsn healths)))
            (removed (pathRemove root))]
        (allRun (list casesOk cacheOk modelsOk receiptsOk pathsOk healthOk (check (ok? removed) (str "temp root removed " root))))))))

fn ! runTests -> Bool
  (let [(textRes (fileReadString "asl/packages/asl-gateway/tests/profileParityFixture.asn"))
        (formsRes (mt textRes ((ok text) (mt (ast/readForms (lx/tokenize text)) ((ok forms) (ok forms)) ((err e) (err e.msg)))) ((err e) (err e))))
        (topRes (mt formsRes
                  ((err e) (err e))
                  ((ok forms) (mt (listHead forms) ((none) (err "fixture has no form")) ((some top) (cfg/asnProps top.expr (some ":fixture")))))))]
    (mt topRes
      ((err e) (check (ok? topRes) (str "fixture readable and parsed: " e)))
      ((ok f) (runFixture! f))))
