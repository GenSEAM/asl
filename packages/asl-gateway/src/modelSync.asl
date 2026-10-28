(module aslGateway/modelSync
  :x [SyncDiff SyncProbe modelFilterFor nonChatId? listedModels syncDiff chainsWith proposeAlias calStatus toProbe syncProposals
      syncPatchText syncCalText syncListText modelsSyncCli!]
  :i [(config :a c)
      (search :a srch)
      (localTime :a lt)
      (asl-json/json :a j)
      (asl-cli/system :a sys)])

; (:m :ref GW-FREE-MODEL-SYNC :do "asl gateway models sync: GET /models per keyed openai-kind provider, detect free models, diff them against the config's model rows, probe new free ones once, and write the current list, a FREE-SYNC calibration row and a proposed config patch into an out directory; it reads the gateway config and never writes it, and paid models are never proposed")

(schema SyncDiff
  (:f provider String)
  (:f listed Int64)
  (:f free (List String))
  (:f added (List String))
  (:f removed (List (Pair String String)))
  (:f changed (List (Pair String String))))

(schema SyncProbe
  (:f provider String)
  (:f name String)
  (:f status String))

; (:m :do "how a provider's /models marks a free model: zero prompt and completion price on openrouter, zero input and output price on together and vercel, and every chat model on a subscription provider")
fn modelFilterFor provider: String -> String
  (cond
    ((= provider "openrouter") "zeroPrice")
    ((= provider "together") "togetherZero")
    ((= provider "vercel") "vercelFree")
    (else "chatOnly"))

fn nonChatWords -> (List String)
  (list "embed" "rerank" "whisper" "tts" "speech" "audio" "transcri" "image" "imagen" "veo" "guard" "moderation" "asr" "clip"
        "parse" "ocr" "retriever" "reward" "safety" "bge" "e5-" "deplot" "kosmos" "paligemma" "flux" "sdxl" "stable-diffusion" "lyria" "live")

fn nonChatId? id: String -> Bool
  (let [(low (stringLower id))]
    (listAny? (fn [(w String)] -> Bool (stringContains? low w)) (nonChatWords)))

fn jsonAt v: j/Json path: (List String) -> (Option j/Json)
  (match (listHead path)
    ((none) (some v))
    ((some k) (match (j/jsonGet v k)
                ((none) none)
                ((some x) (jsonAt x (optionOr (listTail path) (list)))))))

fn zeroPrice? v: (Option j/Json) -> Bool
  (match v
    ((some (j/jstr s)) (match (stringToFloat64 (stringTrim s)) ((some f) (= f 0.0)) ((none) false)))
    ((some (j/jint i)) (= i 0))
    ((some (j/jfloat f)) (= f 0.0))
    ((some (j/jnum n)) (= n 0.0))
    (_ false))

fn textAt v: j/Json path: (List String) d: String -> String
  (match (jsonAt v path)
    ((some (j/jstr s)) s)
    (_ d))

; (:m :do "a free model is a chat model whose price is zero under the provider filter; non-chat ids never count, whatever their price")
fn freeItem? kind: String item: j/Json id: String -> Bool
  (and (not (nonChatId? id)) (priced? kind item))

fn priced? kind: String item: j/Json -> Bool
  (cond
    ((= kind "zeroPrice") (and (zeroPrice? (jsonAt item (list "pricing" "prompt"))) (zeroPrice? (jsonAt item (list "pricing" "completion")))))
    ((= kind "togetherZero") (and (= (textAt item (list "type") "chat") "chat")
                                    (and (zeroPrice? (jsonAt item (list "pricing" "input"))) (zeroPrice? (jsonAt item (list "pricing" "output"))))))
    ((= kind "vercelFree") (and (= (textAt item (list "type") "language") "language")
                                  (and (zeroPrice? (jsonAt item (list "pricing" "input"))) (zeroPrice? (jsonAt item (list "pricing" "output"))))))
    (else true))

fn modelItems body: j/Json -> (List j/Json)
  (match body
    ((j/jarr xs) xs)
    (_ (match (j/jsonGet body "data") ((some (j/jarr xs)) xs) (_ (list)))))

fn itemId item: j/Json -> String
  (let [(raw (textAt item (list "id") ""))]
    (if (stringStartsWith? raw "models/") (optionOr (stringSlice raw 7 (stringLength raw)) "") raw))

; (:m :do "every listed id and the free ones among them, from one /models body")
fn listedModels kind: String text: String -> (Result (Pair (List String) (List String)) String)
  (match (j/jsonParse text)
    ((err e) (err (str "ERR_MODELS_JSON: " e)))
    ((ok body)
      (let [(items (filter (fn [(it j/Json)] -> Bool (not (stringEmpty? (itemId it)))) (modelItems body)))
            (ids (map itemId items))
            (free (map itemId (filter (fn [(it j/Json)] -> Bool (freeItem? kind it (itemId it))) items)))]
        (ok (pair ids free)))))

fn providerRows table: c/GatewayTable provider: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (alias String)] -> (List (Pair String String))
          (match (mapGet table.models alias)
            ((some m) (if (= m.provider provider) (listAppend acc (list (pair alias m.name))) acc))
            ((none) acc)))
        (list) table.modelOrder)

fn routeHas? r: c/GatewayRoute alias: String -> Bool
  (or (listContains? r.chain alias) (listAny? (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) alias)) r.spread))

; (:m :do "every (profile intent) route whose chain or spread names the alias, in profile order")
fn chainsWith table: c/GatewayTable alias: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (pid String)] -> (List (Pair String String))
          (match (mapGet table.profiles pid)
            ((some prof) (listAppend acc (map (fn [(r c/GatewayRoute)] -> (Pair String String) (pair pid r.intent))
                                              (filter (fn [(r c/GatewayRoute)] -> Bool (routeHas? r alias)) prof.routes))))
            ((none) acc)))
        (list) table.profileOrder)

fn inFreeProfile? table: c/GatewayTable freeProfiles: (List String) alias: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (listContains? freeProfiles (pairFirst p))) (chainsWith table alias))

; (:m :do "added: free ids no config row of this provider names; removed: rows whose model is gone from /models; changed: rows in a free profile whose model is still listed but no longer free")
fn syncDiff table: c/GatewayTable freeProfiles: (List String) provider: String ids: (List String) free: (List String) -> SyncDiff
  (let [(rows (providerRows table provider))
        (names (map pairSecond rows))]
    (SyncDiff :provider provider :listed (listLength ids) :free free
      :added (filter (fn [(m String)] -> Bool (not (listContains? names m))) free)
      :removed (filter (fn [(r (Pair String String))] -> Bool (not (listContains? ids (pairSecond r)))) rows)
      :changed (filter (fn [(r (Pair String String))] -> Bool
                         (and (listContains? ids (pairSecond r)) (and (not (listContains? free (pairSecond r))) (inFreeProfile? table freeProfiles (pairFirst r)))))
                       rows)))

fn providerPrefix provider: String -> String
  (cond
    ((= provider "openrouter") "or") ((= provider "gemini") "gm") ((= provider "groq") "gq") ((= provider "nim") "nim")
    ((= provider "vercel") "vc") ((= provider "opencodeGo") "oc") ((= provider "commandCode") "cc") ((= provider "together") "tg")
    ((= provider "ollama") "ol")
    (else provider))

fn alnum? ch: String -> Bool
  (let [(lo (stringLower ch))]
    (or (stringContains? "abcdefghijklmnopqrstuvwxyz" lo) (stringContains? "0123456789" ch)))

fn capitalised w: String -> String
  (if (stringEmpty? w) w (str (stringUpper (optionOr (stringSlice w 0 1) "")) (stringLower (optionOr (stringSlice w 1 (stringLength w)) ""))))

fn camelWords name: String -> String
  (let [(spaced (stringJoin (map (fn [(ch String)] -> String (if (alnum? ch) ch " ")) (stringChars name)) ""))
        (words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit spaced " ")))]
    (stringJoin (map capitalised words) ""))

fn uniqueAlias base: String taken: (List String) n: Int64 -> String
  (let [(cand (if (= n 0) base (str base "X" (stringFromInt64 n))))]
    (if (listContains? taken cand) (uniqueAlias base taken (+ n 1)) cand))

; (:m :do "a new alias: provider prefix plus the model name in camel words, :free suffix kept as Free, unique against the table and earlier proposals")
fn proposeAlias provider: String name: String taken: (List String) -> String
  (let [(free (stringEndsWith? name ":free"))
        (bare (if free (optionOr (stringSlice name 0 (- (stringLength name) 5)) name) name))]
    (uniqueAlias (str (providerPrefix provider) (camelWords bare) (if free "Free" "")) taken 0))

fn probeStatus probes: (List SyncProbe) provider: String name: String -> String
  (match (listHead (filter (fn [(p SyncProbe)] -> Bool (and (= p.provider provider) (= p.name name))) probes))
    ((some p) p.status)
    ((none) "unprobed"))

; (:m :ref GW-FREE-REPROBE :do "the status the last FREE-PROBE row in CAL/freeModels.asn recorded for a model, from its (provider \"name\" :vps S ...) entry, or none")
fn calStatus calText: String provider: String name: String -> String
  (let [(needle (str "(" provider " " (q name) " :vps "))]
    (match (stringIndexOf calText needle)
      ((none) "none")
      ((some i) (optionOr (listHead (stringSplit (optionOr (stringSlice calText (+ i (stringLength needle)) (stringLength calText)) "") " ")) "none"))))

fn permanentStatus? s: String -> Bool
  (listContains? (list "400" "401" "402" "403" "404" "413") s)

; (:m :ref GW-FREE-REPROBE :do "the added models worth a probe: new ones and those CAL last saw fail with 429, 503 or a timeout; a model CAL saw refused for good (400-404, 413) is not probed again")
fn toProbe calText: String d: SyncDiff -> (List String)
  (filter (fn [(n String)] -> Bool (not (permanentStatus? (calStatus calText d.provider n)))) d.added)

; (:m :do "(provider name alias status) for every added free model; a model joins chains only when its probe answered 200, or when probing was skipped on purpose; one CAL saw refused for good is known<status> and never joins")
fn syncProposals table: c/GatewayTable calText: String diffs: (List SyncDiff) probes: (List SyncProbe) probed: Bool -> (List (List String))
  (pairFirst
    (fold (fn [(acc (Pair (List (List String)) (List String))) (d SyncDiff)] -> (Pair (List (List String)) (List String))
            (fold (fn [(a2 (Pair (List (List String)) (List String))) (name String)] -> (Pair (List (List String)) (List String))
                    (let [(alias (proposeAlias d.provider name (pairSecond a2)))
                          (known (calStatus calText d.provider name))
                          (status (if (permanentStatus? known) (str "known" known) (if probed (probeStatus probes d.provider name) "skipped")))]
                      (pair (listAppend (pairFirst a2) (list (list d.provider name alias status))) (cons alias (pairSecond a2)))))
                  acc d.added))
          (pair (list) (mapKeys table.models)) diffs))

fn joins? p: (List String) -> Bool
  (let [(status (optionOr (listGet p 3) ""))]
    (or (= status "200") (= status "skipped")))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn skippedText ps: (List (Pair String String)) -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String (str "(" (pairFirst p) " " (q (pairSecond p)) ")")) ps) " ")

fn pairsText ps: (List (Pair String String)) -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String (str "(" (pairFirst p) " " (pairSecond p) ")")) ps) " ")

fn leaveRow table: c/GatewayTable why: String r: (Pair String String) -> String
  (str "(:alias " (pairFirst r) " :name " (q (pairSecond r)) " :why " (q why) " :chains (" (pairsText (chainsWith table (pairFirst r))) "))")

fn tailRoutes table: c/GatewayTable profile: String intents: (List String) -> (List String)
  (match (mapGet table.profiles profile)
    ((some prof) (filter (fn [(i String)] -> Bool (listAny? (fn [(r c/GatewayRoute)] -> Bool (= r.intent i)) prof.routes)) intents))
    ((none) (list)))

; (:m :do "the proposed patch: model rows to add, aliases appended at the tail of the bulk routes of the pool profile, and aliases that leave their chains; the lead applies it")
fn syncPatchText table: c/GatewayTable syncId: String source: String profile: String diffs: (List SyncDiff) props: (List (List String)) -> String
  (let [(joining (filter joins? props))
        (aliases (map (fn [(p (List String))] -> String (optionOr (listGet p 2) "")) joining))
        (adds (map (fn [(p (List String))] -> String
                     (str "(:model :id " (optionOr (listGet p 2) "") " :provider " (optionOr (listGet p 0) "") " :name " (q (optionOr (listGet p 1) ""))
                          " :maxTokens 32768 :timeoutSec 600 :tier free :why " (q (str syncId " probe " (optionOr (listGet p 3) ""))) ")"))
                   joining))
        (tails (map (fn [(i String)] -> String (str "(:profile " profile " :intent " i " :aliases (" (stringJoin aliases " ") "))"))
                    (if (listEmpty? aliases) (list) (tailRoutes table profile (list "code" "any")))))
        (leaves (listAppend (fold (fn [(acc (List String)) (d SyncDiff)] -> (List String) (listAppend acc (map (fn [(r (Pair String String))] -> String (leaveRow table "gone from /models" r)) d.removed))) (list) diffs)
                            (fold (fn [(acc (List String)) (d SyncDiff)] -> (List String) (listAppend acc (map (fn [(r (Pair String String))] -> String (leaveRow table "listed but no longer free" r)) d.changed))) (list) diffs)))]
    (str "(:patch :id " syncId " :for " (q source) " :apply \"by the lead; this command never edits the config\"\n"
         "  :add (" (stringJoin adds "\n        ") ")\n"
         "  :appendTail (" (stringJoin tails " ") ")\n"
         "  :leave (" (stringJoin leaves "\n          ") "))\n"))

fn propText p: (List String) -> String
  (str "(" (optionOr (listGet p 0) "") " " (q (optionOr (listGet p 1) "")) " :alias " (optionOr (listGet p 2) "") " :probe " (optionOr (listGet p 3) "") ")")

fn syncCalText syncId: String date: String diffs: (List SyncDiff) props: (List (List String)) skipped: (List (Pair String String)) -> String
  (str "(:cal :id " syncId " :date " date " :method \"asl gateway models sync: GET /models per keyed provider, free filter per provider, one chat probe per new free model\""
       " :providers (" (stringJoin (map (fn [(d SyncDiff)] -> String (str "(" d.provider " :listed " (stringFromInt64 d.listed) " :free " (stringFromInt64 (listLength d.free))
                                                                       " :added " (stringFromInt64 (listLength d.added)) " :removed " (stringFromInt64 (listLength d.removed))
                                                                       " :changed " (stringFromInt64 (listLength d.changed)) ")")) diffs) " ") ")"
       " :added (" (stringJoin (map propText props) " ") ")"
       " :removed (" (stringJoin (fold (fn [(acc (List String)) (d SyncDiff)] -> (List String) (listAppend acc (map (fn [(r (Pair String String))] -> String (str "(" d.provider " " (pairFirst r) " " (q (pairSecond r)) ")")) d.removed))) (list) diffs) " ") ")"
       " :changed (" (stringJoin (fold (fn [(acc (List String)) (d SyncDiff)] -> (List String) (listAppend acc (map (fn [(r (Pair String String))] -> String (str "(" d.provider " " (pairFirst r) " " (q (pairSecond r)) ")")) d.changed))) (list) diffs) " ") ")"
       " :skipped (" (skippedText skipped) "))\n")

fn syncListText date: String diffs: (List SyncDiff) -> String
  (str "(:freeModels :date " date "\n  :providers ("
       (stringJoin (map (fn [(d SyncDiff)] -> String (str "(:provider " d.provider " :listed " (stringFromInt64 d.listed) " :free (" (stringJoin (map q d.free) " ") "))")) diffs) "\n              ")
       "))\n")

fn argAfter args: (List String) flag: String d: String -> String
  (match (listHead args)
    ((none) d)
    ((some a) (if (= a flag) (optionOr (listGet args 1) d) (argAfter (optionOr (listTail args) (list)) flag d))))

fn pad2 n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

fn ! todayUtc! -> String
  (let [(ymd (lt/civilFromDays (/ (/ (nowNs) 1000000000) 86400)))]
    (str (stringFromInt64 (optionOr (listGet ymd 0) 1970)) "-" (pad2 (optionOr (listGet ymd 1) 1)) "-" (pad2 (optionOr (listGet ymd 2) 1))))

fn authHeaders pv: c/GatewayProvider key: String -> (List (Pair String String))
  (listAppend (list (pair "Authorization" (str "Bearer " key)) (pair "Content-Type" "application/json"))
              (if (stringEmpty? pv.sessionHeader) (list) (list (pair pv.sessionHeader "asl-models-sync"))))

fn bodyOf r: srch/HttpResult -> (Pair String String)
  (match r
    ((srch/httpResp status _ _ body) (pair (stringFromInt64 status) body))
    ((srch/httpFail _ timedOut) (pair (if timedOut "timeout" "failed") "")))

; (:m :do "a provider's /models body: the fixture file when a fixture dir is given, else one GET with the resolved key; the key goes to curl through its stdin config, never argv or output")
fn ! modelsBody! fixtures: String pv: c/GatewayProvider key: String env: (List String) -> (Result String String)
  (if (not (stringEmpty? fixtures))
    (match (fileReadString (str fixtures "/" pv.id ".models.json")) ((ok t) (ok t)) ((err e) (err (str "no fixture: " e))))
    (let [(req (srch/HttpReq :url (str pv.base "/models") :headers (authHeaders pv key) :data (none) :timeout (j/jint 60)))
          (got (bodyOf (optionOr (listHead (srch/runCurlBatch! (list req) env)) (srch/httpFail (srch/httpError 0 "no result") false))))]
      (if (= (pairFirst got) "200") (ok (pairSecond got)) (err (str "GET /models status " (pairFirst got))))))

fn probeBody name: String -> String
  (str "{\"model\": " (q name) ", \"max_tokens\": 512, \"messages\": [{\"role\": \"user\", \"content\": \"Reply with the single word: ok\"}]}")

fn ! fixtureProbes! fixtures: String -> (List SyncProbe)
  (match (fileReadString (str fixtures "/probes.tsv"))
    ((err _) (list))
    ((ok t) (fold (fn [(acc (List SyncProbe)) (line String)] -> (List SyncProbe)
                    (let [(cols (stringSplit line "\t"))]
                      (if (< (listLength cols) 3) acc
                        (listAppend acc (list (SyncProbe :provider (optionOr (listGet cols 0) "") :name (optionOr (listGet cols 1) "") :status (stringTrim (optionOr (listGet cols 2) ""))))))))
                  (list) (stringSplit t "\n"))))

fn ! liveProbes! pv: c/GatewayProvider key: String env: (List String) names: (List String) -> (List SyncProbe)
  (let [(reqs (map (fn [(n String)] -> srch/HttpReq (srch/HttpReq :url (str pv.base "/chat/completions") :headers (authHeaders pv key) :data (some (probeBody n)) :timeout (j/jint 90))) names))
        (results (srch/runCurlBatch! reqs env))]
    (map (fn [(p (Pair Int64 String))] -> SyncProbe
           (SyncProbe :provider pv.id :name (pairSecond p) :status (pairFirst (bodyOf (optionOr (listGet results (pairFirst p)) (srch/httpFail (srch/httpError 0 "no result") false))))))
         (enumerate names)))

fn syncProviders table: c/GatewayTable only: String -> (List c/GatewayProvider)
  (filter (fn [(pv c/GatewayProvider)] -> Bool (and (= pv.kind "openai") (or (stringEmpty? only) (= only pv.id))))
          (map (fn [(k String)] -> c/GatewayProvider (optionOr (mapGet table.providers k) (c/GatewayProvider :rpmShared false :dropEmptyTools false :id k :kind "" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none))))
               (listSortBy (fn [(k String)] -> String k) (mapKeys table.providers))))

fn ! writeOut! path: String text: String -> Bool
  (ok? (fileWrite path text))

; (:m :do "asl gateway models sync [--config PATH] [--out DIR] [--fixtures DIR] [--no-probe] [--date YYYY-MM-DD] [--profile freePool] [--provider ID]: reads the config, writes freeModels-DATE.asn, FREE-SYNC-DATE.cal.asn and FREE-SYNC-DATE.patch.asn under --out, prints one receipt; the config file is only read")
fn ! modelsSyncCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (source (argAfter args "--config" (c/gatewayProfilesPath home)))
        (outDir (argAfter args "--out" (str home "/.asl/run/gwsync")))
        (calPathIn (argAfter args "--cal" (str (optionOr (envGet "ASL_GATEWAY_ROOT") ".") "/.asl/mem/work/CAL/freeModels.asn")))
        (calText (resultOr (fileReadString calPathIn) ""))
        (fixtures (argAfter args "--fixtures" ""))
        (probed (not (listContains? args "--no-probe")))
        (date (argAfter args "--date" (todayUtc!)))
        (profile (argAfter args "--profile" "freePool"))
        (only (argAfter args "--provider" ""))
        (syncId (str "FREE-SYNC-" date))
        (env (srch/curlChildEnv (mapFromPairs (map (fn [(n String)] -> (Pair String String) (pair n (optionOr (envGet n) ""))) (list "PATH" "https_proxy" "HTTPS_PROXY" "SSL_CERT_FILE")))))]
    (match (fileReadString source)
      ((err e) (do (sys/sayErr! (str "(:modelsSync :status :error :why " (q (str "cannot read " source ": " e)) ")")) (ok 1)))
      ((ok text)
        (match (c/gatewayConfigParse! text source "")
          ((err e) (do (sys/sayErr! (str "(:modelsSync :status :error :why " (q e) ")")) (ok 1)))
          ((ok table)
            (let [(provs (syncProviders table only))
                  (keyed (map (fn [(pv c/GatewayProvider)] -> (Pair c/GatewayProvider String) (pair pv (optionOr (c/resolveProviderKey! table.keyFiles pv.keyEnv) ""))) provs))
                  (usable (filter (fn [(p (Pair c/GatewayProvider String))] -> Bool (or (not (stringEmpty? fixtures)) (not (stringEmpty? (pairSecond p))))) keyed))
                  (noKey (map (fn [(p (Pair c/GatewayProvider String))] -> (Pair String String) (pair (pairFirst p).id "noKey"))
                              (filter (fn [(p (Pair c/GatewayProvider String))] -> Bool (and (stringEmpty? fixtures) (stringEmpty? (pairSecond p)))) keyed)))
                  (fetched (map (fn [(p (Pair c/GatewayProvider String))] -> (Pair (Pair c/GatewayProvider String) (Result (Pair (List String) (List String)) String))
                                  (pair p (match (modelsBody! fixtures (pairFirst p) (pairSecond p) env)
                                            ((err e) (err e))
                                            ((ok body) (listedModels (modelFilterFor (pairFirst p).id) body)))))
                                usable))
                  (failed (map (fn [(f (Pair (Pair c/GatewayProvider String) (Result (Pair (List String) (List String)) String)))] -> (Pair String String)
                                 (pair (pairFirst (pairFirst f)).id (match (pairSecond f) ((err e) e) ((ok _) ""))))
                               (filter (fn [(f (Pair (Pair c/GatewayProvider String) (Result (Pair (List String) (List String)) String)))] -> Bool (not (ok? (pairSecond f)))) fetched)))
                  (diffs (fold (fn [(acc (List SyncDiff)) (f (Pair (Pair c/GatewayProvider String) (Result (Pair (List String) (List String)) String)))] -> (List SyncDiff)
                                 (match (pairSecond f)
                                   ((ok lists) (listAppend acc (list (syncDiff table (list profile "free") (pairFirst (pairFirst f)).id (pairFirst lists) (pairSecond lists)))))
                                   ((err _) acc)))
                               (list) fetched))
                  (probes (if (not probed) (list)
                            (if (not (stringEmpty? fixtures)) (fixtureProbes! fixtures)
                              (fold (fn [(acc (List SyncProbe)) (d SyncDiff)] -> (List SyncProbe)
                                      (match (listHead (filter (fn [(p (Pair c/GatewayProvider String))] -> Bool (= (pairFirst p).id d.provider)) usable))
                                        ((some p) (if (listEmpty? (toProbe calText d)) acc (listAppend acc (liveProbes! (pairFirst p) (pairSecond p) env (toProbe calText d)))))
                                        ((none) acc)))
                                    (list) diffs))))
                  (props (syncProposals table calText diffs probes probed))
                  (made (or (ok? (dirCreate outDir)) (ok? (dirList outDir))))
                  (listPath (str outDir "/freeModels-" date ".asn"))
                  (calPath (str outDir "/" syncId ".cal.asn"))
                  (patchPath (str outDir "/" syncId ".patch.asn"))
                  (wrote (and made (and (writeOut! listPath (syncListText date diffs))
                                        (and (writeOut! calPath (syncCalText syncId date diffs props (listAppend noKey failed)))
                                             (writeOut! patchPath (syncPatchText table syncId source profile diffs props))))))]
              (do (sys/say! (str "(:modelsSync :status " (if wrote ":ok" ":error") " :id " syncId " :providers " (stringFromInt64 (listLength diffs))
                                 " :added " (stringFromInt64 (listLength props)) " :joining " (stringFromInt64 (listLength (filter joins? props)))
                                 " :skipped (" (skippedText (listAppend noKey failed)) ") :list " (q listPath) " :cal " (q calPath) " :patch " (q patchPath) " :configWritten false)"))
                  (ok (if wrote 0 1)))))))))
