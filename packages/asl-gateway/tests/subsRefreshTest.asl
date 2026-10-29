(module aslGateway/tests/subsRefreshTest
  :x [runTests]
  :i [(localTime :a lt) (subsRefresh :a sr)
      (subPace :a sp)
      (usageLedger :a ul)])

; (:m :ref SUBPACE :do "subs refresh against scratch files only (never ~/.asl): the opencodeGo usage body, a codex sessions tree and a call ledger merge into a copy of a subscriptions file; hand-entered fields and untouched subs stay byte for byte, the previous file is kept as .bak, and a failing source leaves its windows alone")

fn subsBefore -> String
  (str "(:subscriptions :v 1 :updated \"2026-10-28\" :src \"fixture\"\n"
       "  (:sub :id commandCode :renews \"2026-11-16\" :capacity 75000 :src principal :windows () :note \"no endpoint\")\n"
       "  (:sub :id opencodeGo :renews \"2026-11-13\" :src \"principal\" :windows ((:rolling 5h :usedPercent 1) (:weekly :resets \"2026-11-02\" :usedPercent 0) (:monthly :resets \"2026-11-13\" :usedPercent 43)) :api \"GET /inference/go/v1/usage\")\n"
       "  (:sub :id codexLuna :renews \"2026-11-22 18:00\" :src \"~/.codex rate_limits event\" :windows ((:primary :minutes 43200 :usedPercent 9)))\n"
       "  (:sub :id agyGoogle :renews unknown :pace exhaust :note \"principal: use until exhausted\")\n"
       "  (:sub :id nim :renews none :note \"free tier\"))\n")

fn ocBody -> String
  "{\"usage\":{\"rolling\":{\"status\":\"ok\",\"percent\":3,\"resetsAt\":\"2026-10-28T20:28:25.343Z\"},\"weekly\":{\"status\":\"ok\",\"percent\":12,\"resetsAt\":\"2026-11-02T00:00:00.000Z\"},\"monthly\":{\"status\":\"ok\",\"percent\":44.5,\"resetsAt\":\"2026-11-13T19:46:51.000Z\"}}}"

fn codexSession -> String
  (str "{\"timestamp\":\"2026-10-27T09:00:00.000Z\",\"payload\":{\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":4.0,\"window_minutes\":43200,\"resets_at\":1795363245},\"secondary\":null}}}\n"
       "{\"timestamp\":\"2026-10-27T10:00:00.000Z\",\"payload\":{\"rate_limits\":{\"limit_id\":\"premium\",\"primary\":null,\"secondary\":null}}}\n"
       "{\"timestamp\":\"2026-10-27T11:00:00.000Z\",\"payload\":{\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":9.0,\"window_minutes\":43200,\"resets_at\":1795363245},\"secondary\":null}}}\n")

fn callRow prov: String at: Int64 -> String
  (str "(:call :at " (stringFromInt64 at) " :profile \"\" :intent \"any\" :alias \"a\" :provider \"" prov "\" :model \"m\" :in 10 :cached 0 :out 5 :reasoning 0 :outcome \"ok\" :charge 0)")

fn count s: String needle: String -> Int64
  (- (listLength (stringSplit s needle)) 1)

; (:m :ref COND5 :do "KIMI-USAGE-API: the usages body gives a 5 h rolling and a monthly window (used_ratio as percent, reset_time), a refresh keeps the monthly :capacity of the line it replaces, and the paced allowance of the refreshed line is at most 15 percent of a window on day 1 with the month unused")
fn kimiBody -> String
  "{\"usages\":{\"limit_5h\":{\"used_ratio\":0.2712,\"reset_time\":\"2026-10-29T17:00:00Z\"},\"limit_month_total\":{\"used_ratio\":0.0148,\"reset_time\":\"2026-11-29T00:00:00Z\"}}}"

fn ! testKimi -> Bool
  (let [(now (sp/parseTimeMs "2026-10-29 12:00"))
        (wins (sr/kimiWindows (kimiBody) now))
        (none (sr/kimiWindows "{\"x\":1}" now))
        (before "(:subscriptions :v 1 :updated \"2026-10-28\"\n  (:sub :id kimiPro :renews \"2026-11-29\" :windows ((:rolling 5h :usedPercent 0) (:monthly :capacity \"18 full 5 h windows\" :src \"principal\")))\n")
        (after (sr/refreshSubsText before (list (pair "kimiPro" wins))))
        (paces (sp/paceSubs (lt/utcZone) after "" now))
        (p (optionOr (listHead paces) (sp/noData "missing" 0 0)))
        (month (sp/monthCapWindows (optionOr (listHead (sp/subLines after)) "")))]
    (do (assert (= (listLength wins) 2) (str "two windows from the body: " (stringJoin wins " ")))
        (assert (and (stringContains? (optionOr (listHead wins) "") ":rolling 5h") (stringContains? (optionOr (listHead wins) "") ":usedPercent 27.1") (stringContains? (optionOr (listGet wins 1) "") ":usedPercent 1.5") (stringContains? (optionOr (listGet wins 1) "") ":src kimiApi")) (str "used_ratio read as percent: " (stringJoin wins " ")))
        (assert (listEmpty? none) "a body without usages gives no window")
        (assert (and (stringContains? after ":capacity \"18 full 5 h windows\"") (= month 18.0)) (str "the refresh keeps the monthly capacity: " after))
        (assert (and (< p.allowance 15.0) (> p.allowance 5.0)) (str "paced allowance at most 15 percent: " (sp/fixed1 p.allowance) " " p.window))
        true))

fn ! runTests -> Bool
  (let [(dir (str "/tmp/gwSubsRefresh-" (procSelf) "-" (nowNs)))
        (sessDir (str dir "/codex/2026/10/27"))
        (now (sp/parseTimeMs "2026-10-28 12:00"))
        (subs (str dir "/subscriptions.asn"))
        (_mk (dirCreate dir))
        (_mk2 (dirCreate (str dir "/codex")))
        (_mk3 (dirCreate (str dir "/codex/2026")))
        (_mk4 (dirCreate (str dir "/codex/2026/10")))
        (_mk5 (dirCreate sessDir))
        (ledger (stringJoin (listAppend (map (fn [(i Int64)] -> String (callRow "commandCode" (+ (sp/parseTimeMs "2026-10-20") (* i 1000)))) (list 0 1 2 3 4 5 6 7 8 9))
                                        (list (callRow "commandCode" (sp/parseTimeMs "2026-10-01")) (callRow "opencodeGo" (sp/parseTimeMs "2026-10-20")))) "\n"))
        (w (list (fileWrite subs (subsBefore)) (fileWrite (str dir "/oc.json") (ocBody)) (fileWrite (str sessDir "/rollout-1.jsonl") (codexSession))
                 (fileWrite (str dir "/ledger.asn") ledger) (fileWrite (str dir "/gateway.asn") "(:gateway :v 2)")))
        (base (list "--tz" "UTC" "--subs" subs "--codex" (str dir "/codex") "--ledger" (str dir "/ledger.asn") "--config" (str dir "/gateway.asn") "--now" (stringFromInt64 now)))
        (dry (sr/subsRefreshCli! (listAppend base (list "--oc-body" (str dir "/oc.json") "--dry"))))
        (afterDry (resultOr (fileReadString subs) ""))
        (code (sr/subsRefreshCli! (listAppend base (list "--oc-body" (str dir "/oc.json")))))
        (after (resultOr (fileReadString subs) ""))
        (bak (resultOr (fileReadString (str subs ".bak")) "NO-BACKUP"))
        (tmpGone (not (ok? (fileStat (str subs ".tmp")))))
        (again (sr/subsRefreshCli! (listAppend base (list "--oc-body" (str dir "/oc.json")))))
        (afterAgain (resultOr (fileReadString subs) ""))
        (down (sr/subsRefreshCli! (listAppend (list "--codex" (str dir "/none")) (listAppend base (list "--oc-body" (str dir "/missing.json"))))))
        (afterDown (resultOr (fileReadString subs) ""))
        (lines (stringSplit after "\n"))
        (lineOf (fn [(id String)] -> String (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l (str "(:sub :id " id " "))) lines)) "")))
        (oc (lineOf "opencodeGo")) (cx (lineOf "codexLuna")) (cc (lineOf "commandCode")) (agy (lineOf "agyGoogle"))
        (paces (sp/paceSubs (lt/utcZone) after ledger now))
        (ocPace (optionOr (listHead (filter (fn [(p sp/SubPace)] -> Bool (= p.id "opencodeGo")) paces)) (sp/noData "x" 0 0)))
        (removed (pathRemove dir))]
    (do
      (assert (listAll? (fn [(r (Result Unit String))] -> Bool (ok? r)) w) "the fixture files are written")
      (assert (and (= dry (ok 0)) (= afterDry (subsBefore))) "--dry changes nothing")
      (assert (= code (ok 0)) (str "refresh exits 0: " code))
      (assert (and (stringContains? oc ":monthly :resets \"2026-11-13T19:46:51.000Z\" :usedPercent 44.5 :src opencodeApi :at ") (stringContains? oc ":rolling 5h :resets \"2026-10-28T20:28:25.343Z\" :usedPercent 3 :src opencodeApi")
                   (stringContains? oc ":weekly :resets \"2026-11-02T00:00:00.000Z\" :usedPercent 12 :src opencodeApi"))
              (str "the three api windows replace the hand-entered ones: " oc))
      (assert (and (= (count oc "(:monthly") 1) (stringContains? oc ":api \"GET /inference/go/v1/usage\"") (stringContains? oc ":renews \"2026-11-13\"")) "one monthly window, the sub's other fields kept")
      (assert (and (stringContains? cx "(:primary :minutes 43200 :resets \"2026-11-22T16:00:45Z\"") (stringContains? cx ":usedPercent 9.0 :src codexEvent :at 1793098800000") (= (count cx "(:primary") 1))
              (str "the last codex event with a non-null primary wins, stamped with its own timestamp: " cx))
      (assert (and (stringContains? cc ":windows ((:monthly :resets ") (stringContains? cc ":usedPercent 0.0 ") (stringContains? cc ":src ledger") (stringContains? cc ":calls 10 :tokens 150") (stringContains? cc ":note \"no endpoint\""))
              (str "commandCode, which has no endpoint, gets a ledger estimate of its own rows since the window start: " cc))
      (assert (= agy "  (:sub :id agyGoogle :renews unknown :pace exhaust :note \"principal: use until exhausted\")") "a sub with no source is byte for byte unchanged")
      (assert (and (= bak (subsBefore)) tmpGone) "the previous file is kept as .bak and no tmp file is left")
      (assert (and (= again (ok 0)) (= afterAgain after)) "a second refresh at the same time is a no-op")
      (assert (and (= down (ok 0)) (= afterDown after)) "a failing api source and an empty codex dir leave the windows as they were")
      (assert (and (near ocPace.used 44.5) (= ocPace.src "opencodeApi") (not ocPace.stale)) "the pacing core reads what refresh wrote, fresh at the refresh time")
      (assert (> (sp/staleAfterMs "opencodeApi") 0) "api figures go stale")
      (assert (= (sr/opencodeWindows "not json" now) (list)) "an unreadable body yields no windows")
      (assert (ok? removed) "the scratch dir is removed")
      (assert (= (sr/ledgerWindows (lt/utcZone) (stringReplace (subsBefore) ":capacity 75000 " "") ledger now (list)) (list)) "a sub with no declared capacity gets no ledger percent")
      (assert (ledgerMergeCase) "ledger merge")
      (assert (testKimi) "kimi usages windows keep the monthly capacity and pace under 15 percent")
      (assert (= (ul/defaultLedgerPath "/h") (ul/defaultSharedUsagePath "/h")) "one ledger: the stats path and the shared path are the same file")
      (assert (not (= (ul/legacyLedgerPath "/h") (ul/defaultSharedUsagePath "/h"))) "the legacy path is the old file")
      true))

fn near a: Float64 b: Float64 -> Bool
  (< (if (> a b) (- a b) (- b a)) 0.01)

; (:m :ref SUBPACE :do "the two ledgers of the Mac: legacy rows from 10-01 on, shared rows from 10-18 on with the overlap identical; after the merge every row is there once, in time order, the shared file is backed up and the legacy file is renamed")
fn ! ledgerMergeCase -> Bool
  (let [(dir (str "/tmp/gwLedgerMerge-" (procSelf) "-" (nowNs)))
        (_d (dirCreate dir))
        (legacy (str dir "/gatewayCalls.asn"))
        (shared (str dir "/usage-gatewayCalls.asn"))
        (row (fn [(at Int64)] -> String (callRow "commandCode" at)))
        (w (list (fileWrite legacy (str (row 100) "\n" (row 200) "\n" (row 300) "\n" (row 400) "\n"))
                 (fileWrite shared (str (row 300) "\n" (row 400) "\n" (row 500) "\n"))))
        (code (sr/ledgerMergeCli! (list "--legacy" legacy "--shared" shared)))
        (merged (resultOr (fileReadString shared) ""))
        (bak (resultOr (fileReadString (str shared ".bak")) ""))
        (legacyGone (not (ok? (fileStat legacy))))
        (kept (ok? (fileStat (str legacy ".merged"))))
        (ats (map (fn [(l String)] -> String (sp/tokAfter l ":at")) (filter (fn [(l String)] -> Bool (stringContains? l "(:call")) (stringSplit merged "\n"))))
        (second (sr/ledgerMergeCli! (list "--legacy" legacy "--shared" shared)))
        (removed (pathRemove dir))]
    (do
      (assert (= code (ok 0)) "ledgerMerge exits 0")
      (assert (= ats (list "100" "200" "300" "400" "500")) (str "each row once, oldest first: " (stringJoin ats " ")))
      (assert (and (= bak (str (row 300) "\n" (row 400) "\n" (row 500) "\n")) legacyGone kept) "the shared file is backed up and the legacy file is renamed")
      (assert (= second (ok 0)) "a second merge with no legacy file is a no-op")
      true))
