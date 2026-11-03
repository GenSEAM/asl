(module aslGateway/tests/healthTest
  :x [runTests]
  :i [(aslGateway/health :a hl)
      (aslGateway/usageLedger :a ul)
      (aslGateway/requestLog :a rq)
      (aslGateway/config :a c)])

; (:m :ref GW-HEALTH-REPORT :do "a fixture ledger with known counts gives the exact report: per model calls, ok share, upstream 429 against own refusals, p50 and p95, tokens; the provider sums, the prune candidates, the aliases that never served, attempts per turn, the request accounting and the window cut")
fn nowMs -> Int64
  1793300400000

fn rowOf provider: String alias: String outcome: String ms: Int64 ageMs: Int64 session: (Option String) turn: (Option Int64) -> ul/CallRow
  (ul/CallRow :atMs (- (nowMs) ageMs) :profile "" :intent "" :alias alias :provider provider :model alias
              :inTokens 10 :cachedTokens 2 :outTokens 5 :reasoningTokens 0 :ttftMs none :ms (some ms)
              :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session session :turn turn :consumer none :cacheWriteTokens none :status 0 :reason none)

fn manyOf n: Int64 provider: String alias: String outcome: String ms: Int64 -> (List ul/CallRow)
  (if (<= n 0) (list) (cons (rowOf provider alias outcome (* ms n) 1000 none none) (manyOf (- n 1) provider alias outcome ms)))

fn ledger -> (List ul/CallRow)
  (listAppend
    (listAppend (listAppend (manyOf 10 "pa" "a" "ok" 100) (manyOf 2 "pa" "a" "429" 50))
                (listAppend (manyOf 3 "pa" "a" "throttled" 0) (manyOf 1 "pa" "a" "500" 70)))
    (listAppend
      (listAppend (manyOf 4 "pb" "b" "ok" 10) (manyOf 36 "pb" "b" "500" 10))
      (listAppend (manyOf 29 "pb" "c" "500" 10)
        (listAppend (list (rowOf "pa" "a" "ok" 1 172800000 none none))
          (list (rowOf "pc" "k" "429" 5 1000 (some "s1") (some 1)) (rowOf "pc" "k" "429" 5 1000 (some "s1") (some 1)) (rowOf "pc" "k" "ok" 5 1000 (some "s1") (some 1)) (rowOf "pc" "k" "ok" 5 1000 (some "s1") (some 2)))))))

fn reqsOf -> (List rq/ReqRow)
  (list (rq/ReqRow :id "r1" :phase "accepted" :atMs (- (nowMs) 5000) :outcome "" :status 0 :ms 0)
        (rq/ReqRow :id "r1" :phase "done" :atMs (- (nowMs) 4000) :outcome "ok" :status 200 :ms 1000)
        (rq/ReqRow :id "r2" :phase "accepted" :atMs (- (nowMs) 3000) :outcome "" :status 0 :ms 0)
        (rq/ReqRow :id "r2" :phase "done" :atMs (- (nowMs) 2000) :outcome "lost" :status 0 :ms 1000)
        (rq/ReqRow :id "r3" :phase "accepted" :atMs (- (nowMs) 1800000) :outcome "" :status 0 :ms 0))

fn modelOf hs: (List hl/HealthRow) alias: String -> hl/HealthRow
  (optionOr (listHead (filter (fn [(h hl/HealthRow)] -> Bool (= h.alias alias)) hs)) (hl/HealthRow :provider "" :alias "" :calls -1 :ok 0 :up429 0 :own 0 :failed 0 :p50 0 :p95 0 :tokIn 0 :tokOut 0 :tokCached 0))

fn modelRows n: Int64 oks: Int64 alias: String -> (List ul/CallRow)
  (listAppend (manyOf oks "pp" alias "ok" 10) (manyOf (- n oks) "pp" alias "500" 10))

fn aliasesOf hs: (List hl/HealthRow) -> String
  (stringJoin (listSort (map (fn [(h hl/HealthRow)] -> String h.alias) hs)) ",")

fn cfgKeep n: String -> String
  (str "(:gateway :v 2 :healthKeep " n " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))")

fn errOf r: (Result Int64 String) -> Bool
  (match r ((err _) true) ((ok _) false))

fn numOf r: (Result Int64 String) -> Int64
  (match r ((ok n) n) ((err _) -1))

; (:m :ref GW-HEALTH-REPORT :do "the prune rule at its edges, the accepted total after compaction, a provider or alias with a bar in its name, --hours errors, and the healthKeep file pruning")
fn ! fixCases! -> Bool
  (let [(edge (listAppend (listAppend (modelRows 100 19 "p19") (modelRows 100 20 "p20")) (listAppend (listAppend (modelRows 100 21 "p21") (modelRows 30 0 "pS")) (modelRows 29 0 "pT"))))
        (edgePrune (hl/pruneCandidates (hl/healthRows edge)))
        (bars (hl/healthRows (listAppend (manyOf 1 "a|b" "c" "ok" 10) (manyOf 1 "a" "b|c" "ok" 10))))
        (barProviders (stringJoin (listSort (map (fn [(h hl/HealthRow)] -> String h.provider) bars)) ","))
        (doneOnly (list (rq/ReqRow :id "r1" :phase "done" :atMs (- (nowMs) 4000) :outcome "ok" :status 200 :ms 1000)
                        (rq/ReqRow :id "r2" :phase "done" :atMs (- (nowMs) 2000) :outcome "lost" :status 0 :ms 1000)))
        (acc (hl/requestsText doneOnly (- (nowMs) 3600000) (nowMs) 900))
        (dir (str "/tmp/healthTestKeep" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))
        (_ (pathRemove dir))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/health-100.asn") "x"))
        (_ (fileWrite (str dir "/health-300.asn") "x"))
        (_ (fileWrite (str dir "/health-200.asn") "x"))
        (_ (fileWrite (str dir "/health-400.asn") "x"))
        (_ (fileWrite (str dir "/notes.txt") "x"))
        (_ (fileWrite (str dir "/health-500.txt") "x"))
        (_ (fileWrite (str dir "/old-900.asn") "x"))
        (removed (hl/pruneHealthFiles! dir 2))
        (left (stringJoin (listSort (resultOr (dirList dir) (list))) ","))
        (_ (pathRemove dir))
        (keepOk (c/gatewayConfigCheckText! (cfgKeep "5") "src" ".asl/mem/calibration/index.asn"))
        (keepBad (c/gatewayConfigCheckText! (cfgKeep "0") "src" ".asl/mem/calibration/index.asn"))]
    (do
      (assert (= (aliasesOf edgePrune) "p19,pS") (str "19 percent ok over 100 calls and 0 percent over 30 are prune candidates, 20 and 21 percent and 29 calls are not: " (aliasesOf edgePrune)))
      (assert (and (= (listLength bars) 2) (= barProviders "a,a|b")) (str "a bar in a provider or alias name does not merge or split rows: " barProviders))
      (assert (stringContains? acc ":accepted 2 :done 2") (str "accepted is done plus open, so compaction does not undercount: " acc))
      (assert (and (= (numOf (hl/hoursOfArgs (list))) 24) (= (numOf (hl/hoursOfArgs (list "--hours" "6"))) 6) (= (numOf (hl/hoursOfArgs (list "--write" "--hours" "12"))) 12)) "--hours absent is 24, a number is taken wherever it stands")
      (assert (and (errOf (hl/hoursOfArgs (list "--hours" "abc"))) (errOf (hl/hoursOfArgs (list "--hours"))) (errOf (hl/hoursOfArgs (list "--hours" "0"))) (errOf (hl/hoursOfArgs (list "--hours" "721")))) "a non-number, a missing number and a number outside 1..720 are errors")
      (assert (and (= (hl/healthKeepFromText "(:gateway :healthKeep 5)") 5) (= (hl/healthKeepFromText "") 60) (= (hl/healthKeepFromText "(:gateway :healthKeep 0)") 60) (= (hl/healthKeepFromText "(:gateway :healthKeep 10001)") 60)) "healthKeep takes 1..10000 and defaults to 60")
      (assert (= (stringJoin (hl/staleHealthFiles (list "health-3.asn" "health-1.asn" "health-2.asn" "other.txt" "health-4.asn") 2) ",") "health-1.asn,health-2.asn") "the stale files are the oldest health files beyond keep, other files never")
      (assert (and (= removed 2) (= left "health-300.asn,health-400.asn,health-500.txt,notes.txt,old-900.asn")) (str "pruning keeps the newest two health files and leaves others: " left))
      (assert (and (= (pairSecond keepOk) 0) (= (pairSecond keepBad) 1) (stringContains? (pairFirst keepBad) "healthKeep")) (str "healthKeep 5 is clean, 0 is a config error: " (pairFirst keepBad)))
      true))

fn ! runTests -> Bool
  (let [(inWin (filter (fn [(r ul/CallRow)] -> Bool (>= r.atMs (- (nowMs) 86400000))) (ledger)))
        (models (hl/healthRows inWin))
        (a (modelOf models "a"))
        (provs (hl/providerRows inWin))
        (pa (optionOr (listHead (filter (fn [(h hl/HealthRow)] -> Bool (= h.provider "pa")) provs)) a))
        (prune (hl/pruneCandidates models))
        (pruneB (modelOf prune "b"))
        (never (hl/neverServed (list "a" "b" "c" "d") models))
        (apt (hl/attemptsPerTurnX100 inWin))
        (report (hl/healthReport (ledger) (reqsOf) (list "a" "b" "c" "d") (nowMs) 24 900))
        (wide (hl/healthReport (ledger) (reqsOf) (list) (nowMs) 72 900))]
    (do
      (assert (and (= a.calls 13) (= a.ok 10) (= a.up429 2) (= a.own 3) (= a.failed 1)) (str "model a counts: " (hl/healthRowText a)))
      (assert (and (= a.p50 500) (= a.p95 1000)) (str "p50 and p95 of the ok latencies 100..1000: " (stringFromInt64 a.p50) " " (stringFromInt64 a.p95)))
      (assert (and (= a.tokIn 130) (= a.tokOut 65) (= a.tokCached 26)) "tokens count the sent calls only")
      (assert (= pa.calls 13) "the provider row sums its aliases")
      (assert (= (listLength provs) 3) "three providers seen in the window")
      (assert (and (= (listLength prune) 1) (= pruneB.ok 4)) "only b has an ok share under 20 percent over at least 30 calls, c has 29")
      (assert (= (stringJoin never ",") "c,d") (str "c never served and d never called: " (stringJoin never ",")))
      (assert (= apt 200) (str "four attempts over two turns: " (stringFromInt64 apt)))
      (assert (stringContains? report "(:m :provider \"pa\" :alias \"a\" :calls 13 :ok 10 :okPct 76 :up429 2 :own 3 :failed 1 :p50Ms 500 :p95Ms 1000 :tokIn 130 :tokOut 65 :tokCached 26)") (str "the exact model line is in the report: " report))
      (assert (stringContains? report ":requests :accepted 3 :done 2 :lost 1 :stuck 1 :outcomes ((ok 1) (limit 0) (noRoute 0) (timeout 0) (upstreamError 0) (gatewayError 0) (clientGone 0) (lost 1))") (str "the request accounting: " report))
      (assert (stringContains? report ":hours 24 :rows 89") (str "the 48 hour old row is outside a 24 hour window: " (stringSlice report 0 60)))
      (assert (stringContains? wide ":hours 72 :rows 90") "and inside a 72 hour window")
      (assert (stringContains? report ":neverServed (\"c\" \"d\")") "never served is in the report")
      (assert (stringContains? report ":attemptsPerTurnX100 200") "attempts per turn is in the report")
      (fixCases!)))
