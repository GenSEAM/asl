(module aslGateway/tests/ledgerReadCostTest
  :x [runTests]
  :i [(aslGateway/server :a srv) (aslGateway/config :a c) (aslGateway/usageLedger :a ul) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b)
      (aslGateway/upstream :a u) (aslGateway/dispatch :a dp) (aslGateway/chat :a ch) (aslGateway/omniApi :a om) (aslGateway/balancer :a bl)
      (aslGateway/cliDispatch :a cd) (aslGateway/usage :a g)])

; (:m :ref GW-LEDGER-READ-COST :do "eight old generations hold text no reader can parse, so a reader that opens one fails; a reader that keeps to its window reads the live file alone, whose first row is 40 days old and so reaches back past every window here")
fn dir -> String
  "/tmp/ledgerReadCostTest"

fn ledger -> String
  (str (dir) "/calls.asn")

fn rowAt atMs: Int64 provider: String alias: String profile: String tokens: Int64 -> ul/CallRow
  (ul/CallRow :atMs atMs :profile profile :intent "coder" :alias alias :provider provider :model alias :inTokens tokens :cachedTokens 0 :outTokens 0
    :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn garbage -> String
  (stringJoin (map (fn [(i Int64)] -> String "this generation is not a ledger row and must stay closed\n") (range 0 1200)) "")

fn ! seed! nowMs: Int64 -> Bool
  (let [(_ (pathRemove (dir)))
        (made (dirCreate (dir)))
        (gens (listAll? (fn [(k Int64)] -> Bool (ok? (fileWrite (str (ledger) "." (stringFromInt64 k)) (garbage)))) (range 1 9)))
        (old (ul/callRowLine (rowAt (- nowMs (* 40 86400000)) "elsewhere" "zz" "other" 1)))
        (live (stringJoin (map (fn [(r ul/CallRow)] -> String (ul/callRowLine r))
                               (list (rowAt nowMs "fp" "m1" "freeBulk" 60) (rowAt nowMs "fp" "mH" "freeBulk" 60) (rowAt nowMs "fixa" "mH" "freeBulk" 60))) ""))]
    (and (ok? made) (and gens (ok? (fileWrite (ledger) (str old live))))))

fn ! loopFor text: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home (dir) :rootDir (dir) :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText (some text) :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn balancerConfig -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY))"
       " :models ((:model :id mH :provider fixa :name \"chat-a\" :tier free :budgets (hDay hWeek) :quality 300))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mH)))))"
       " :uses ((:use :for default :profile default))"
       " :balancer (:balancer :mode balanced :exploreEvery 0 :cal () :ledger \"" (ledger) "\""
       " :budgets ((:budget :id hDay :window day :unit req :size 50 :useOrLose true)"
       " (:budget :id hWeek :window week :unit req :size 400 :useOrLose true))))\n")

fn ! poolUse! -> (Result Int64 String)
  (match (c/gatewayProfilesLoadText! (str (dir) "/.asl/gateway.asn") true (ok (balancerConfig)) "")
    ((err e) (err e))
    ((ok table)
      (match (bl/loadPool! (balancerConfig) (some table) (dir) (fn [(pid String)] -> Bool (= pid "fixa")))
        ((err e) (err e))
        ((ok (none)) (err "no pool"))
        ((ok (some p)) (ok (match (mapGet p.use "hDay") ((some w) w.used) ((none) 0)))))))

; (:m :ref GW-LEDGER-READ-COST :do "the fixture is live: a reader of every generation fails on it, so each ok below means the reader stayed inside its window")
fn ! fixtureChecks nowMs: Int64 -> Bool
  (do
    (assert (not (ok? (ul/readRows! (ledger)))) "readRows! opens the old generations and fails on them")
    (assert (= (listLength (resultOr (ul/readRowsSince! (ledger) (- nowMs 60000)) (list))) 3) "a minute window reads the three live rows")
    true)

; (:m :ref GW-LEDGER-READ-COST :do "the request-path readers: the daily token budget and the limit pace check read from their window start, so eight old generations are never opened")
fn ! serverChecks nowMs: Int64 -> Bool
  (let [(path (ledger))
        (budgetText (str "(:gateway :v 2 :sharedUsagePath \"" path "\" :dailyTokenBudgets ((freeBulk 100)))"))
        (refusal (srv/budgetRefusal! (loopFor budgetText) "freeBulk"))
        (limitText (str "(:gateway :v 2 :sharedUsagePath \"" path "\" :limits ((:limit :provider fp :window minute :calls 1)))"))
        (ran (srv/runEffect! (loopFor limitText) (ch/effLimit "fp" "m1")))
        (verdict (match (pairSecond ran) ((ch/outStrings xs) xs) (_ (list))))
        (held (listLength (let [(l (pairFirst ran))] l.limitRows)))]
    (do
      (assert (some? refusal) (str "180 tokens today against a 100 budget refuse, read from the live file alone: " (optionOr refusal "none")))
      (assert (not (listEmpty? verdict)) "the minute pace check counts the live fp row and refuses the second call")
      (assert (= held 3) (str "the pace check holds the three live rows of its minute: " (stringFromInt64 held)))
      true))

; (:m :ref GW-LEDGER-READ-COST :do "the balancer rebuilds its budgets from the start of the earliest current budget window, and gw stats and gw usage --days read only their window")
fn ! reportChecks nowMs: Int64 -> Bool
  (let [(used (poolUse!))
        (keyFn (resultOr (ul/keyFor "provider") (fn [(r ul/CallRow)] -> String r.provider)))
        (stats (cd/gatewayStatsFor! (ledger) 3600000 keyFn "" nowMs))
        (day (cd/gatewayUsageFor! (ledger) "" 1 nowMs))
        (all (cd/gatewayUsageFor! (ledger) "" 0 nowMs))]
    (do
      (assert (= (resultOr used (- 0 1)) 2) (str "the balancer loads and charges hDay with the two live mH rows: " (match used ((ok n) (stringFromInt64 n)) ((err e) e))))
      (assert (match stats ((ok t) (stringContains? t "fixa")) ((err _) false)) (str "gw stats over 1 h reads the live file alone: " (match stats ((ok t) t) ((err e) e))))
      (assert (match day ((ok t) (stringContains? t "fixa")) ((err _) false)) (str "gw usage --days 1 reads today's rows from the live file alone: " (match day ((ok t) t) ((err e) e))))
      (assert (not (ok? all)) "gw usage without --days totals every kept day, so it opens the old generations")
      true))

; (:m :ref GW-LEDGER-READ-COST :do "bytes this process has read so far, from Linux /proc/self/io rchar; none where the host has no such counter")
fn ! bytesRead! -> (Option Int64)
  (match (fileReadString "/proc/self/io")
    ((err _) none)
    ((ok t) (match (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "rchar: ")) (stringSplit t "\n")))
              ((some l) (stringToInt64 (stringTrim (optionOr (stringSlice l 7 (stringLength l)) ""))))
              ((none) none))))

; (:m :ref GW-LEDGER-READ-COST :do "an append to a 4 MiB ledger reads less than 64 KiB, the reads of the counter itself included; before, appendFile! drained the whole file through the lock fd to reach its end; where no counter exists (macOS) the host must say it is not Linux, and the read claim is checked on Linux only")
fn ! appendChecks -> Bool
  (let [(path (str (dir) "/append.asn"))
        (_ (fileWrite path ""))
        (chunk (stringJoin (map (fn [(i Int64)] -> String "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde\n") (range 0 1024)) ""))
        (grown (listAll? (fn [(i Int64)] -> Bool (ok? (fileAppend path chunk))) (range 0 64)))
        (before (bytesRead!))
        (wrote (g/appendFile! path "(:tail)\n" 10))
        (after (bytesRead!))
        (size (match (fileStat path) ((ok st) st.size) ((err _) 0)))
        (ends (stringEndsWith? (resultOr (fileReadString path) "") "(:tail)\n"))
        (delta (match before ((some x) (match after ((some y) (some (- y x))) ((none) none))) ((none) none)))
        (os (match (platformInfo) ((ok pi) pi.os) ((err _) "")))]
    (do
      (assert (and grown (ok? wrote)) "the 4 MiB ledger grows and the append succeeds")
      (assert (and (= size (+ 4194304 8)) ends) (str "the row lands at the end: size " (stringFromInt64 size)))
      (assert (match delta ((some d) (< d 65536)) ((none) (and (none? before) (not (= os "Linux")))))
              (str "the append reads under 64 KiB on " os ": " (match delta ((some d) (stringFromInt64 d)) ((none) "no counter"))))
      true))

fn ! runTests -> Bool
  (let [(nowMs (/ (nowNs) 1000000))
        (seeded (seed! nowMs))
        (ok1 (do (assert seeded "eight unreadable generations and a live file are seeded") true))
        (res (and (fixtureChecks nowMs) (and (serverChecks nowMs) (and (reportChecks nowMs) (appendChecks)))))
        (_ (pathRemove (dir)))]
    res)
