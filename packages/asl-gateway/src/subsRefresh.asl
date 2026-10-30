(module aslGateway/subsRefresh
  :x [paceFactors! mergedLedgerText ledgerMergeCli! numText opencodeWindows kimiWindows codexWindow mergeWindows ledgerWindows refreshSubsText newestSessionFiles! subsRefreshCli! subsStatusCli!]
  :i [(config :a c)
      (search :a srch)
      (localTime :a lt)
      (subPace :a sp)
      (usageLedger :a ul)
      (usage :a g)
      (asl-json/json :a j)
      (asl-cli/system :a sys)])

; (:m :ref SUBPACE :do "asl gateway subs refresh | status: refresh writes the windows of ~/.asl/subscriptions.asn from every source that exists (opencodeGo usage endpoint, codex rate_limits events, the call ledger as an estimate), each window with :src and :at; status prints one row per subscription from the same pacing core the router uses")

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn argAfter args: (List String) flag: String d: String -> String
  (match (listHead args)
    ((none) d)
    ((some a) (if (= a flag) (optionOr (listGet args 1) d) (argAfter (optionOr (listTail args) (list)) flag d))))

fn pad2 n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

; (:m :do "a JSON number as ASN text; whole numbers print without a fraction")
fn numText v: j/Json -> String
  (match v
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (sp/fixed1 f))
    ((j/jnum f) (sp/fixed1 f))
    (_ "0"))

fn jstrOr v: (Option j/Json) -> String
  (match v ((some x) (match x ((j/jstr s) s) (_ "")) ) ((none) ""))

; (:m :do "windows from the opencodeGo usage body {usage:{rolling|weekly|monthly:{percent,resetsAt}}}: one window per kind present, stamped src opencodeApi and nowMs")
fn ocWindow u: j/Json kind: String nowMs: Int64 -> (List String)
  (match (j/jsonGet u kind)
    ((none) (list))
    ((some w)
      (match (j/jsonGet w "percent")
        ((none) (list))
        ((some pc)
          (list (str "(:" kind (if (= kind "rolling") " 5h" "") " :resets " (q (jstrOr (j/jsonGet w "resetsAt")))
                     " :usedPercent " (numText pc) " :src opencodeApi :at " (stringFromInt64 nowMs) ")"))))))

fn opencodeWindows body: String nowMs: Int64 -> (List String)
  (match (j/jsonParse body)
    ((err _) (list))
    ((ok doc)
      (match (j/jsonGet doc "usage")
        ((none) (list))
        ((some u) (fold (fn [(acc (List String)) (kind String)] -> (List String) (listAppend acc (ocWindow u kind nowMs))) (list) (list "rolling" "weekly" "monthly"))))))

fn isoSeconds s: Int64 -> String
  (let [(ymd (lt/civilFromDays (/ s 86400)))
        (rem (mod s 86400))]
    (str (stringFromInt64 (optionOr (listGet ymd 0) 1970)) "-" (pad2 (optionOr (listGet ymd 1) 1)) "-" (pad2 (optionOr (listGet ymd 2) 1))
         "T" (pad2 (/ rem 3600)) ":" (pad2 (/ (mod rem 3600) 60)) ":" (pad2 (mod rem 60)) "Z"))

fn numberAfter s: String key: String -> String
  (match (stringIndexOf s key)
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice s (+ i (stringLength key)) (stringLength s)) ""))
            (tok (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ",")) "") "}")) ""))]
        (stringTrim tok))))

; (:m :do "the codex window of the latest rate_limits event whose limit_id is codex and whose primary window is not null; text is the whole session file, the last such line wins; :at is the event's own timestamp")
fn codexWindow sessionText: String nowMs: Int64 -> (Option String)
  (let [(lines (filter (fn [(l String)] -> Bool (and (stringContains? l "\"limit_id\":\"codex\"") (stringContains? l "\"primary\":{"))) (stringSplit sessionText "\n")))]
    (match (listLast lines)
      ((none) none)
      ((some l)
        (let [(prim (optionOr (stringSlice l (optionOr (stringIndexOf l "\"primary\":{") 0) (stringLength l)) ""))
              (used (numberAfter prim "\"used_percent\":"))
              (mins (numberAfter prim "\"window_minutes\":"))
              (resets (numberAfter prim "\"resets_at\":"))
              (ts (let [(t (stringTrim (numberAfter l "\"timestamp\":")))] (stringReplace t "\"" "")))
              (atMs (sp/parseTimeMs ts))]
          (if (or (stringEmpty? used) (stringEmpty? mins)) none
            (some (str "(:primary :minutes " mins " :resets " (q (match (stringToInt64 resets) ((some s) (isoSeconds s)) ((none) "")))
                       " :usedPercent " used " :src codexEvent :at " (stringFromInt64 (if (= atMs 0) 0 atMs)) ")")))))))

fn listLast xs: (List String) -> (Option String)
  (listHead (listReverse xs))

fn descNames names: (List String) -> (List String)
  (listReverse (listSortBy (fn [(n String)] -> String n) names))

; (:m :do "the n newest session files under a codex sessions dir laid out YYYY/MM/DD/rollout-*.jsonl, newest first")
fn ! newestSessionFiles! root: String n: Int64 -> (List String)
  (let [(years (match (dirList root) ((ok xs) (descNames xs)) ((err _) (list))))
        (monthsOf (fn [(y String)] -> (List String) (match (dirList (str root "/" y)) ((ok xs) (map (fn [(m String)] -> String (str y "/" m)) (descNames xs))) ((err _) (list)))))
        (ym (fold (fn [(acc (List String)) (y String)] -> (List String) (listAppend acc (monthsOf y))) (list) years))
        (daysOf (fn [(p String)] -> (List String) (match (dirList (str root "/" p)) ((ok xs) (map (fn [(d String)] -> String (str p "/" d)) (descNames xs))) ((err _) (list)))))
        (ymd (listTake (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (daysOf p))) (list) (listTake ym 3)) (+ n 3)))
        (filesOf (fn [(p String)] -> (List String) (match (dirList (str root "/" p)) ((ok xs) (map (fn [(f String)] -> String (str root "/" p "/" f)) (filter (fn [(f String)] -> Bool (stringEndsWith? f ".jsonl")) (descNames xs)))) ((err _) (list)))))]
    (listTake (fold (fn [(acc (List String)) (p String)] -> (List String) (if (>= (listLength acc) n) acc (listAppend acc (filesOf p)))) (list) ymd) n))

fn ! codexFromDir! root: String nowMs: Int64 -> (Option String)
  (fold (fn [(acc (Option String)) (f String)] -> (Option String)
          (match acc
            ((some w) (some w))
            ((none) (match (fileReadString f) ((ok t) (codexWindow t nowMs)) ((err _) none)))))
        none (newestSessionFiles! root 6))

; (:m :do "windows that carry the same kind replace each other, others stay in file order, new kinds are appended; a replaced window's hand-entered :capacity is carried to its replacement, so a refresh never drops the monthly cap")
fn mergeWindows old: (List String) fresh: (List String) -> (List String)
  (let [(kindOf (fn [(w String)] -> String (sp/kindOf w)))
        (fk (map kindOf fresh))
        (capOf (fn [(w String)] -> String (let [(c (sp/quotedAfter (optionOr (listHead (filter (fn [(o String)] -> Bool (= (kindOf o) (kindOf w))) old)) "") ":capacity"))] c)))
        (withCap (map (fn [(w String)] -> String
                        (let [(c (capOf w))]
                          (if (or (stringEmpty? c) (stringContains? w ":capacity")) w
                            (str (optionOr (stringSlice w 0 (- (stringLength w) 1)) w) " :capacity " (q c) ")"))))
                      fresh))]
    (listAppend (filter (fn [(w String)] -> Bool (not (listContains? fk (kindOf w)))) old) withCap))

; (:m :ref COND5 :do "windows from the Kimi Code usages body {usages:{limit_5h:{used_ratio,reset_time},limit_month_total:{used_ratio,reset_time}}}: the 5 h rolling window and the monthly one, used_ratio 0..1 as :usedPercent, stamped src kimiApi and nowMs; a missing limit gives no window")
fn kimiWindow u: j/Json key: String kind: String nowMs: Int64 -> (List String)
  (match (j/jsonGet u key)
    ((none) (list))
    ((some w)
      (match (j/jsonGet w "used_ratio")
        ((none) (list))
        ((some r)
          (let [(pct (match r ((j/jint i) (* 100.0 (int64ToFloat64 i))) ((j/jfloat f) (* 100.0 f)) ((j/jnum f) (* 100.0 f)) (_ 0.0)))]
            (list (str "(:" kind (if (= kind "rolling") " 5h" "") " :resets " (q (jstrOr (j/jsonGet w "reset_time"))) " :usedPercent " (sp/fixed1 pct) " :src kimiApi :at " (stringFromInt64 nowMs) ")")))))))

fn kimiWindows body: String nowMs: Int64 -> (List String)
  (match (j/jsonParse body)
    ((err _) (list))
    ((ok doc)
      (match (j/jsonGet doc "usages")
        ((none) (list))
        ((some u) (listAppend (kimiWindow u "limit_5h" "rolling" nowMs) (kimiWindow u "limit_month_total" "monthly" nowMs))))))

; (:m :do "ledger estimates for every sub line that has a capacity (or the commandCode default) and gets no other source in freshIds: a monthly window ending at renews, used = calls / capacity, with :calls and :tokens")
fn ledgerWindows z: lt/Zone subsText: String ledgerText: String nowMs: Int64 freshIds: (List String) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String))
          (let [(id (sp/subId line))
                (cap (sp/subCapacity line id))
                (renews (sp/parseStampMs z (sp/quotedAfter line ":renews")))]
            (if (or (listContains? freshIds id) (<= cap 0.0) (<= renews 0)) acc
              (let [(reset (sp/rollReset renews 2592000000 nowMs))
                    (use (sp/ledgerUse ledgerText id (- reset 2592000000)))]
                (listAppend acc (list (pair id (str "(:monthly :resets " (q (isoSeconds (/ reset 1000))) " :usedPercent " (sp/fixed1 (/ (* 100.0 (int64ToFloat64 (pairFirst use))) cap))
                                                    " :src ledger :at " (stringFromInt64 nowMs) " :calls " (stringFromInt64 (pairFirst use)) " :tokens " (stringFromInt64 (pairSecond use)) ")"))))))))
        (list) (sp/subLines subsText))

; (:m :do "the subscriptions text with fresh windows merged into the named subs; a sub line with no :windows gets one; every other byte is kept")
fn refreshSubsText subsText: String fresh: (List (Pair String (List String))) -> String
  (stringJoin
    (map (fn [(line String)] -> String
           (let [(id (sp/subId line))
                 (mine (fold (fn [(acc (List String)) (p (Pair String (List String)))] -> (List String) (if (= (pairFirst p) id) (listAppend acc (pairSecond p)) acc)) (list) fresh))]
             (if (or (listEmpty? mine) (not (stringContains? line "(:sub :id "))) line
               (let [(seg (sp/windowsSegment line))
                     (old (if (stringEmpty? seg) (list) (sp/groupsOf (optionOr (stringSlice seg 1 (- (stringLength seg) 1)) ""))))
                     (merged (str "(" (stringJoin (mergeWindows old mine) " ") ")"))]
                 (if (stringEmpty? seg)
                   (let [(cut (- (stringLength line) 1))]
                     (str (optionOr (stringSlice line 0 cut) "") " :windows " merged (optionOr (stringSlice line cut (stringLength line)) "")))
                   (stringReplace line seg merged))))))
         (stringSplit subsText "\n"))
    "\n")

; (:m :ref SUBPACE :do "the zone hand-entered dates are read in: --tz NAME, else TZ, else /etc/localtime, else UTC")
fn ! zoneOf! args: (List String) -> lt/Zone
  (let [(tz (argAfter args "--tz" ""))]
    (resultOr (lt/zoneLoad! (if (stringEmpty? tz) (envGet "TZ") (some tz))) (lt/utcZone)))

fn ! nowMs! -> Int64
  (/ (nowNs) 1000000)

fn ! readOr! path: String -> String
  (resultOr (fileReadString path) "")

; (:m :do "GET usage with the provider key resolved the way the gateway resolves it; only the body is read, the key and the response headers are never printed")
fn ! opencodeBody! table: c/GatewayTable -> (Result String String)
  (match (mapGet table.providers "opencodeGo")
    ((none) (err "no opencodeGo provider in the config"))
    ((some pv)
      (match (c/resolveProviderKey! table.keyFiles pv.keyEnv)
        ((none) (err "no key for opencodeGo"))
        ((some key)
          (let [(env (srch/curlChildEnv (mapFromPairs (map (fn [(n String)] -> (Pair String String) (pair n (optionOr (envGet n) ""))) (list "PATH" "https_proxy" "HTTPS_PROXY" "SSL_CERT_FILE")))))
                (req (srch/HttpReq :url (str pv.base "/usage") :headers (list (pair "Authorization" (str "Bearer " key)) (pair "Content-Type" "application/json")) :data (none) :timeout (j/jint 30)))]
            (match (optionOr (listHead (srch/runCurlBatch! (list req) env)) (srch/httpFail (srch/httpError 0 "no result") false))
              ((srch/httpResp status _ _ body) (if (= status 200) (ok body) (err (str "usage status " (stringFromInt64 status)))))
              ((srch/httpFail _ timedOut) (err (if timedOut "usage timeout" "usage request failed")))))))))

; (:m :ref COND5 :do "GET <kimiCode base>/usages with the provider key; free, only the body is read")
fn ! kimiBody! table: c/GatewayTable -> (Result String String)
  (match (mapGet table.providers "kimiCode")
    ((none) (err "no kimiCode provider in the config"))
    ((some pv)
      (match (c/resolveProviderKey! table.keyFiles pv.keyEnv)
        ((none) (err "no key for kimiCode"))
        ((some key)
          (let [(env (srch/curlChildEnv (mapFromPairs (map (fn [(n String)] -> (Pair String String) (pair n (optionOr (envGet n) ""))) (list "PATH" "https_proxy" "HTTPS_PROXY" "SSL_CERT_FILE")))))
                (req (srch/HttpReq :url (str pv.base "/usages") :headers (list (pair "Authorization" (str "Bearer " key)) (pair "Content-Type" "application/json")) :data (none) :timeout (j/jint 30)))]
            (match (optionOr (listHead (srch/runCurlBatch! (list req) env)) (srch/httpFail (srch/httpError 0 "no result") false))
              ((srch/httpResp status _ _ body) (if (= status 200) (ok body) (err (str "usages status " (stringFromInt64 status)))))
              ((srch/httpFail _ timedOut) (err (if timedOut "usages timeout" "usages request failed")))))))))

fn ! ledgerPathOf! args: (List String) home: String configText: String -> String
  (argAfter args "--ledger" (optionOr (c/gatewaySharedUsagePathOverride configText) (ul/defaultSharedUsagePath home)))

fn receiptSource id: String src: String ok: Bool n: Int64 why: String -> String
  (str "(:sub " id " :src " src " :ok " (if ok "true" "false") " :windows " (stringFromInt64 n) (if (stringEmpty? why) "" (str " :why " (q why))) ")")

; (:m :do "asl gateway subs refresh [--subs P] [--config P] [--codex DIR] [--ledger P] [--oc-body FILE] [--no-net] [--now MS] [--dry]: merges fresh windows into the subscriptions file through a tmp file and rename, keeping the previous file as P.bak; a source that fails leaves its windows as they were")
fn ! subsRefreshCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (subsPath (argAfter args "--subs" (str home "/.asl/subscriptions.asn")))
        (configPath (argAfter args "--config" (c/gatewayProfilesPath home)))
        (codexRoot (argAfter args "--codex" (str home "/.codex/sessions")))
        (now (optionOr (stringToInt64 (argAfter args "--now" "")) (nowMs!)))
        (configText (readOr! configPath))
        (ledgerText (readOr! (ledgerPathOf! args home configText)))
        (ocFixture (argAfter args "--oc-body" ""))
        (kimiFixture (argAfter args "--kimi-body" ""))
        (zone (zoneOf! args))]
    (match (fileReadString subsPath)
      ((err e) (do (sys/sayErr! (str "(:subsRefresh :status :error :why " (q (str "cannot read " subsPath ": " e)) ")")) (ok 1)))
      ((ok subsText)
        (let [(ocBody (cond
                        ((not (stringEmpty? ocFixture)) (fileReadString ocFixture))
                        ((listContains? args "--no-net") (err "skipped by --no-net"))
                        (else (match (c/gatewayConfigParse! configText configPath "")
                                ((err e) (err (str "config: " e)))
                                ((ok table) (opencodeBody! table))))))
              (ocWins (match ocBody ((ok b) (opencodeWindows b now)) ((err _) (list))))
              (kimiBodyR (cond
                           ((not (stringEmpty? kimiFixture)) (fileReadString kimiFixture))
                           ((listContains? args "--no-net") (err "skipped by --no-net"))
                           (else (match (c/gatewayConfigParse! configText configPath "")
                                   ((err e) (err (str "config: " e)))
                                   ((ok table) (kimiBody! table))))))
              (kimiWins (match kimiBodyR ((ok b) (kimiWindows b now)) ((err _) (list))))
              (cxWin (codexFromDir! codexRoot now))
              (cxWins (match cxWin ((some w) (list w)) ((none) (list))))
              (apiFresh (listAppend (listAppend (if (listEmpty? ocWins) (list) (list "opencodeGo")) (if (listEmpty? cxWins) (list) (list "codexLuna"))) (if (listEmpty? kimiWins) (list) (list "kimiPro"))))
              (ledgerFresh (ledgerWindows zone subsText ledgerText now apiFresh))
              (fresh (listAppend (listAppend (list (pair "opencodeGo" ocWins) (pair "codexLuna" cxWins) (pair "kimiPro" kimiWins))
                                             (map (fn [(p (Pair String String))] -> (Pair String (List String)) (pair (pairFirst p) (list (pairSecond p)))) ledgerFresh))
                                 (list)))
              (merged (refreshSubsText subsText fresh))
              (receipt (str "(:subsRefresh :status :ok :subs ("
                            (stringJoin (list (receiptSource "opencodeGo" "opencodeApi" (not (listEmpty? ocWins)) (listLength ocWins) (match ocBody ((err e) (if (listEmpty? ocWins) e "")) ((ok _) (if (listEmpty? ocWins) "no usage windows in the body" ""))))
                                              (receiptSource "kimiPro" "kimiApi" (not (listEmpty? kimiWins)) (listLength kimiWins) (match kimiBodyR ((err e) (if (listEmpty? kimiWins) e "")) ((ok _) (if (listEmpty? kimiWins) "no usage windows in the body" ""))))
                                              (receiptSource "codexLuna" "codexEvent" (not (listEmpty? cxWins)) (listLength cxWins) (if (listEmpty? cxWins) "no codex rate_limits event found" ""))
                                              (str "(:ledger " (stringJoin (map pairFirst ledgerFresh) " ") ")"))
                                        " ")
                            ") :path " (q subsPath)))]
          (if (listContains? args "--dry")
            (do (sys/say! (str receipt " :written false)")) (ok 0))
            (let [(tmp (str subsPath ".tmp"))
                  (backup (str subsPath ".bak"))]
              (cond
                ((= merged subsText) (do (sys/say! (str receipt " :written false :why \"no change\")")) (ok 0)))
                ((not (ok? (fileWrite backup subsText))) (do (sys/sayErr! (str "(:subsRefresh :status :error :why " (q (str "cannot write " backup)) ")")) (ok 1)))
                ((not (ok? (fileWrite tmp merged))) (do (sys/sayErr! (str "(:subsRefresh :status :error :why " (q (str "cannot write " tmp)) ")")) (ok 1)))
                (else (match (pathRename tmp subsPath)
                        ((err e) (do (pathRemove tmp) (sys/sayErr! (str "(:subsRefresh :status :error :why " (q (str "cannot rename: " e)) ")")) (ok 1)))
                        ((ok _) (do (sys/say! (str receipt " :written true :backup " (q backup) ")")) (ok 0))))))))))))

; (:m :do "the value multiplier of a provider in a CAL subMultipliers text: the largest numeric :x among its entries, else 1")
fn valueOf multText: String provider: String -> Float64
  (let [(segs (optionOr (listTail (stringSplit (stringReplace multText "\n" " ") (str "(" provider " \""))) (list)))
        (xs (map (fn [(s String)] -> Float64 (optionOr (stringToFloat64 (sp/tokAfter (optionOr (listHead (stringSplit s ")")) "") ":x")) 1.0)) segs))]
    (fold (fn [(a Float64) (b Float64)] -> Float64 (if (> b a) b a)) 1.0 xs))

; (:m :do "asl gateway subs status [--subs P] [--config P] [--ledger P] [--mult FILE] [--now MS]: one (:subStatus ...) row per subscription, from the same SubPace the router reads")
fn ! subsStatusCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (subsPath (argAfter args "--subs" (str home "/.asl/subscriptions.asn")))
        (configText (readOr! (argAfter args "--config" (c/gatewayProfilesPath home))))
        (ledgerText (readOr! (ledgerPathOf! args home configText)))
        (multText (readOr! (argAfter args "--mult" (str (optionOr (envGet "ASL_GATEWAY_ROOT") ".") "/.asl/mem/work/CAL/subMultipliers-20261028.asn"))))
        (now (optionOr (stringToInt64 (argAfter args "--now" "")) (nowMs!)))
        (zone (zoneOf! args))]
    (match (fileReadString subsPath)
      ((err e) (do (sys/sayErr! (str "(:subStatus :status :error :why " (q (str "cannot read " subsPath ": " e)) ")")) (ok 1)))
      ((ok subsText)
        (let [(paces (sp/paceSubs zone subsText ledgerText now))
              (dayAgo (- now 86400000))
              (callsOf (fn [(p sp/SubPace)] -> Int64 (pairFirst (sp/ledgerUse ledgerText p.id dayAgo))))
              (total (fold (fn [(a Int64) (p sp/SubPace)] -> Int64 (+ a (callsOf p))) 0 paces))]
          (do (map (fn [(p sp/SubPace)] -> Bool
                     (sys/say! (sp/statusLine p (valueOf multText p.id) (if (= total 0) 0.0 (/ (int64ToFloat64 (callsOf p)) (int64ToFloat64 total))) now)))
                   paces)
              (ok 0))))))

; (:m :ref SUBPACE :do "the factor cache the router keeps: subscription id to factor permille from the subscriptions file and the ledger, plus ~at; an unreadable or absent subscriptions file gives an empty cache, which leaves every spread as configured")
fn ! paceFactors! home: String ledgerPath: String nowMs: Int64 -> (Map String Int64)
  (match (fileReadString (str home "/.asl/subscriptions.asn"))
    ((err _) (sp/factorsFromPaces (list) nowMs))
    ((ok subsText) (sp/factorsFromPaces (sp/paceSubs (zoneOf! (list)) subsText (readOr! ledgerPath) nowMs) nowMs)))

fn firstAtOf text: String -> Int64
  (match (listHead (filter (fn [(l String)] -> Bool (stringContains? l "(:call :at ")) (stringSplit text "\n")))
    ((none) 0)
    ((some l) (optionOr (stringToInt64 (sp/tokAfter l ":at")) 0)))

; (:m :ref SUBPACE :do "the legacy stats rows older than the first row of the shared ledger, followed by the shared rows; rows from the time both files were written are the same rows and are taken once, from the shared file")
fn mergedLedgerText legacyText: String sharedText: String -> String
  (let [(cut (let [(a (firstAtOf sharedText))] (if (= a 0) 9223372036854775807 a)))
        (older (filter (fn [(l String)] -> Bool (and (stringContains? l "(:call :at ") (< (optionOr (stringToInt64 (sp/tokAfter l ":at")) 0) cut))) (stringSplit legacyText "\n")))
        (kept (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit sharedText "\n")))]
    (str (stringJoin (listAppend older kept) "\n") "\n"))

; (:m :ref SUBPACE :do "asl gateway subs ledgerMerge [--legacy P] [--shared P]: folds the old per-home stats ledger into the shared one through a tmp file and rename (shared kept as P.bak) and renames the old file to P.merged; run it while the gateway is idle, a row appended between the read and the rename would be lost")
fn ! ledgerMergeCli! args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (legacy (argAfter args "--legacy" (ul/legacyLedgerPath home)))
        (shared (argAfter args "--shared" (ul/defaultSharedUsagePath home)))]
    (match (fileReadString legacy)
      ((err _) (do (sys/say! (str "(:ledgerMerge :status :ok :merged 0 :why \"no legacy ledger\" :shared " (q shared) ")")) (ok 0)))
      ((ok legacyText)
        (let [(sharedText (readOr! shared))
              (merged (mergedLedgerText legacyText sharedText))
              (before (- (listLength (stringSplit sharedText "\n")) 1))
              (after (- (listLength (stringSplit merged "\n")) 1))
              (tmp (str shared ".merge.tmp"))]
          (cond
            ((not (ok? (dirCreate (g/posixDirname shared)))) (do (sys/sayErr! "(:ledgerMerge :status :error :why \"cannot create the shared ledger dir\")") (ok 1)))
            ((not (ok? (fileWrite (str shared ".bak") sharedText))) (do (sys/sayErr! "(:ledgerMerge :status :error :why \"cannot write the backup\")") (ok 1)))
            ((not (ok? (fileWrite tmp merged))) (do (sys/sayErr! "(:ledgerMerge :status :error :why \"cannot write the tmp file\")") (ok 1)))
            (else (match (pathRename tmp shared)
                    ((err e) (do (pathRemove tmp) (sys/sayErr! (str "(:ledgerMerge :status :error :why " (q e) ")")) (ok 1)))
                    ((ok _) (do (pathRename legacy (str legacy ".merged"))
                                (sys/say! (str "(:ledgerMerge :status :ok :rowsBefore " (stringFromInt64 before) " :rowsAfter " (stringFromInt64 after) " :shared " (q shared) " :legacy " (q (str legacy ".merged")) ")"))
                                (ok 0))))))))))
