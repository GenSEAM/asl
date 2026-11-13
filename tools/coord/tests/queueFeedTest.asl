(module asl-tools/coord/tests/queueFeedTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref NODE2-FEED-BACKLOG :do "fixture store and fixture queue file only (never ~/.asl or the real SH files): a (:queue ...) row in the store's ladder.asn makes the service cycle import backlog-schema rows; a row is taken only with :worker deepseek or cheap, :status open, :owns and a gate command, and the tick launches its write stage through a fake launcher that appends `STAGE ID` to launched.log and exits; without a queue row the ledger of ledger.path is the only intake")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/queueFeedTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "queueFeedTest" :ttlMs 600000 :maxWait 400 :maxSame 3 :stageSec 30 :maxDesc 8
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String)
                    (list "/bin/sh" "-c" (str "echo " stage " " u.id " >> " dir "/launched.log")))
          :pace (cd/fixedPace 8 8))

fn noSnap -> (fn [] -> (List (Pair String Int64)))
  (fn [] -> (List (Pair String Int64)) (list))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! ids dir: String -> (List String)
  (listSort (map (fn [(c cd/CUnit)] -> String c.id) (cd/readCUnits! dir)))

fn ! laneOf dir: String id: String -> String
  (match (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) ((some c) c.lane) ((none) "absent"))

fn ! gateOf dir: String id: String -> String
  (match (st/readUnits! dir)
    ((err _) "unreadable")
    ((ok us) (match (listFind (fn [(u st/Task)] -> Bool (= u.id id)) us) ((some u) u.gate) ((none) "absent"))))

; (:m :do "cycles until every wanted `write ID` line is in launched.log, at most max cycles of 100 ms")
fn ! cycleUntil! ctx: cd/Ctx want: (List String) max: Int64 -> Bool
  (let [(_ (cd/loopOnce! ctx (noSnap) (fn [] -> Unit ()) false))
        (log (readOr (str ctx.dir "/launched.log")))]
    (cond
      ((listAll? (fn [(id String)] -> Bool (stringContains? log (str "write " id "\n"))) want) true)
      ((<= max 0) false)
      (else (let [(_ (sleepMs 100))] (cycleUntil! ctx want (- max 1))))))

fn queueText -> String
  (str "(:backlog :v 2 :kind deepseekQueue :schema (id status prio area do gate effort src model))\n"
       "(:u :id OK1 :status open :prio p1 :area lang :do \"eligible one\" :gate \"./bin/asl test p/ok1Test.asl\" :effort S :src (L-1) :model sonnet :worker deepseek :owns (\"p/ok1.asl\" \"p/ok1Test.asl (new)\"))\n"
       "(:u :id OK2 :status open :prio p1 :area lang :do \"eligible two\" :gate \"the test names the builtin; red on base\" :gateCmd \"./bin/asl test p/ok2Test.asl && ./bin/asl check p/ok2.asl\" :effort S :src (L-2) :model sonnet :worker cheap :channel strong :owns (\"p/ok2.asl\"))\n"
       "(:u :id NOOWNS :status open :prio p1 :area lang :do \"no owns\" :gate \"./bin/asl test p/noTest.asl\" :effort S :src (L-3) :model sonnet :worker deepseek)\n"
       "(:u :id PROSE :status open :prio p1 :area lang :do \"prose gate\" :gate \"./bin/asl test p/proseTest.asl exits 0 with three new cases\" :effort S :src (L-4) :model sonnet :worker deepseek :owns (\"p/prose.asl\"))\n"
       "(:u :id WRONGW :status open :prio p1 :area lang :do \"other worker\" :gate \"./bin/asl test p/wTest.asl\" :effort S :src (L-5) :model sonnet :worker sonnet :owns (\"p/w.asl\"))\n"
       "(:u :id NOWORKER :status open :prio p1 :area lang :do \"no worker\" :gate \"./bin/asl test p/nwTest.asl\" :effort S :src (L-6) :model sonnet :owns (\"p/nw.asl\"))\n"
       "(:u :id RUN1 :status running :prio p1 :area lang :do \"running\" :gate \"./bin/asl test p/rTest.asl\" :effort S :src (L-7) :model sonnet :worker deepseek :owns (\"p/r.asl\"))\n"
       "(:u :id REV1 :status review :prio p1 :area lang :do \"in review\" :gate \"./bin/asl test p/vTest.asl\" :effort S :src (L-8) :model sonnet :worker deepseek :owns (\"p/v.asl\"))\n"
       "(:u :id DONE1 :status done :prio p1 :area lang :do \"done\" :gate \"./bin/asl test p/dTest.asl\" :effort S :src (L-9) :model sonnet :worker deepseek :owns (\"p/d.asl\"))\n"
       "(:unrewritten :rows 1 :note \"the feed skips every row below this marker\")\n"
       "(:u :id BELOW1 :status open :prio p1 :area lang :do \"below the marker\" :gate \"./bin/asl test p/bTest.asl\" :effort S :src (L-10) :model sonnet :worker deepseek :owns (\"p/b.asl\"))\n")

fn ! testQueueFeed -> Bool
  (let [(dir (scratch "feed"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (queue (str dir "/deepseekQueue.fixture.asn"))
        (_ (fileWrite queue (queueText)))
        (_ (fileWrite (str dir "/ladder.asn") (str "(:queue :path " (st/q queue) " :base \"main\" :channel \"paid\")\n")))
        (ctx (ctxOf dir))
        (launched (cycleUntil! ctx (list "OK1" "OK2") 100))
        (log (readOr (str dir "/launched.log")))
        (got (ids dir))
        (lane1 (laneOf dir "OK1"))
        (lane2 (laneOf dir "OK2"))
        (owns1 (match (st/readUnits! dir) ((err _) (list)) ((ok us) (match (listFind (fn [(u st/Task)] -> Bool (= u.id "OK1")) us) ((some u) u.owns) ((none) (list))))))
        (gate1 (gateOf dir "OK1"))
        (gate2 (gateOf dir "OK2"))
        (status (cd/status! ctx))
        (brief (cd/briefTask! dir dir (st/Task :id "ZZ" :owns (list) :reads (list) :gate "g" :channel "paid" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "") ""))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert launched (str "both eligible rows reach the write stage of the fake launcher: " log " units " (stringJoin got " ")))
        (assert (= got (list "OK1" "OK2")) (str "only the eligible rows became units: " (stringJoin got " ")))
        (assert (not (stringContains? log "NOOWNS")) (str "a row without :owns is not launched: " log))
        (assert (not (stringContains? log "WRONGW")) (str "a row of another worker is not launched: " log))
        (assert (not (stringContains? log "RUN1")) (str "a running row is not launched: " log))
        (assert (= lane1 "paid") (str "a row without :channel takes the queue row's lane: " lane1))
        (assert (= lane2 "strong") (str "a row's own :channel wins: " lane2))
        (assert (= owns1 (list "p/ok1.asl" "p/ok1Test.asl")) (str "an owned path marked (new) is owned without the mark: " (stringJoin owns1 " | ")))
        (assert (not (stringContains? status "BELOW1")) (str "a row below (:unrewritten) is neither a unit nor parked: " status))
        (assert (= gate1 "./bin/asl test p/ok1Test.asl") (str "a test-command gate is the unit gate: " gate1))
        (assert (= gate2 "./bin/asl test p/ok2Test.asl && ./bin/asl check p/ok2.asl") (str ":gateCmd is the unit gate, not the prose: " gate2))
        (assert (and (stringContains? status "\"NOOWNS:owns\"") (stringContains? status "\"PROSE:gate\"")) (str "status lists the rows that need owns or a gate command: " status))
        (assert (not (listAny? (fn [(id String)] -> Bool (stringContains? status (str "\"" id ":"))) (list "WRONGW" "NOWORKER" "RUN1" "REV1" "DONE1"))) (str "unselected rows are not parked either: " status))
        (assert (stringContains? brief queue) (str "the fallback task text cites the queue file: " brief))
        (assert (not (stringContains? brief "SH/plan.asn")) (str "and not the plan journal: " brief))
        true))

; (:m :ref NODE2-FEED-BACKLOG :do "no (:queue ...) row, or only rows refused for an unknown key or a missing :path: the queue file on disk is not read, the ledger of ledger.path is imported as before and its unit launched, and with neither the task text names the plan journal")
fn ! testLedgerFallback -> Bool
  (let [(dir (scratch "fallback"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (queue (str dir "/deepseekQueue.fixture.asn"))
        (_ (fileWrite queue (queueText)))
        (ctx (ctxOf dir))
        (_ (cd/loopOnce! ctx (noSnap) (fn [] -> Unit ()) false))
        (none (ids dir))
        (briefNone (cd/briefTask! dir dir (st/Task :id "ZZ" :owns (list) :reads (list) :gate "g" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "") ""))
        (_ (fileWrite (str dir "/ladder.asn") (str "(:queue :path " (st/q queue) " :lane \"paid\")\n(:queue :base \"main\")\n")))
        (_ (cd/loopOnce! ctx (noSnap) (fn [] -> Unit ()) false))
        (bad (ids dir))
        (ledger (str dir "/plan.fixture.asn"))
        (_ (fileWrite ledger "(:u :id N1 :queue conductor :do \"old row\" :owns (\"p/n1\") :gate \"true\")\n(:u :id N2 :queue conductor :status open :do \"old row, open\" :owns (\"p/n2\") :gate \"true\")\n"))
        (_ (fileWrite (cd/ledgerPath dir) (str ledger "\nmain\n")))
        (launched (cycleUntil! ctx (list "N1") 100))
        (got (ids dir))
        (lane (laneOf dir "N1"))
        (briefLedger (cd/briefTask! dir dir (st/Task :id "ZZ" :owns (list) :reads (list) :gate "g" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "") ""))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert (listEmpty? none) (str "no queue row and no ledger.path: nothing imported: " (stringJoin none " ")))
        (assert (stringContains? briefNone ".asl/mem/work/SH/plan.asn") (str "nothing configured: the task text names the plan journal: " briefNone))
        (assert (listEmpty? bad) (str "a queue row with an unknown key or no :path is not used: " (stringJoin bad " ")))
        (assert launched (str "the ledger row is imported and launched as before: " (stringJoin got " ")))
        (assert (= got (list "N1")) (str "only the old-schema queued row, the open one stays out: " (stringJoin got " ")))
        (assert (= lane "free") (str "an old row without :channel stays on free: " lane))
        (assert (stringContains? briefLedger ledger) (str "with a ledger the task text cites it: " briefLedger))
        true))

fn ! runTests -> Bool
  (do (assert (testQueueFeed) "backlog-schema queue rows are imported and launched, ineligible ones are not")
      (assert (testLedgerFallback) "without a queue row the ledger path works as before")
      true)
