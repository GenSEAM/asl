(module aslGateway/tests/limitSeededTest
  :x [runTests]
  :i [(aslGateway/chat :a ch)
      (aslGateway/config :a c)
      (aslGateway/usageLedger :a ul)
      (aslGateway/limits :a lim)
      (aslGateway/server :a srv)
      (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b)
      (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp)
      (aslGateway/omniApi :a om)])

; (:m :ref GW-LIMIT-SEEDED-E2E :do "a real ledger file seeds the window counts through runEffect! and effLimit: the first ask reads the shared ledger once, later asks within the seed ttl count the held rows (a call appended meanwhile is not seen), a fresh loop reads it again, and rows outside the window or of another provider do not count")
fn nowMs -> Int64
  (/ (nowNs) 1000000)

fn rowOf at: Int64 provider: String -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias "m1" :provider provider :model "m1" :inTokens 1 :cachedTokens 0 :outTokens 1 :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn ! appendN! path: String n: Int64 ageMs: Int64 provider: String -> Bool
  (if (<= n 0)
    true
    (match (ul/appendCallRow! path (rowOf (- (nowMs) (+ ageMs (* n 10))) provider))
      ((ok _) (appendN! path (- n 1) ageMs provider))
      ((err _) false)))

fn cfgWith extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))")

fn limitText -> String
  (cfgWith " :limits ((:limit :provider fp :scope account :window hour :calls 3 :method doc :verified false :date \"2026-11-01\"))")

fn ! loopAt home: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText (some (limitText)) :families (list) :outbox (list) :pendingCall none
    :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)


fn answerOf o: ch/ChatOutcome -> String
  (match o ((ch/outStrings xs) (stringJoin xs "/")) (_ "other"))

fn ! ask! s: srv/GatewayLoop -> (Pair srv/GatewayLoop String)
  (let [(r (srv/runEffect! s (ch/effLimit "fp" "m1")))]
    (pair (pairFirst r) (answerOf (pairSecond r))))

fn ! runTests -> Bool
  (let [(tag (str (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))
        (home (str "/tmp/limitSeededTest" tag))
        (_ (pathRemove home))
        (made (dirCreate home))
        (path (ul/defaultSharedUsagePath home))
        (_ (appendN! path 2 0 "fp"))
        (first (ask! (loopAt home)))
        (_ (appendN! path 1 0 "fp"))
        (firstSrv (pairFirst first))
        (cached (ask! firstSrv))
        (fresh (ask! (loopAt home)))
        (home2 (str "/tmp/limitSeededTestOld" tag))
        (_ (pathRemove home2))
        (made2 (dirCreate home2))
        (path2 (ul/defaultSharedUsagePath home2))
        (_ (appendN! path2 5 172800000 "fp"))
        (_ (appendN! path2 5 0 "other"))
        (old (ask! (loopAt home2)))
        (oldSrv (pairFirst old))
        (_ (pathRemove home))
        (_ (pathRemove home2))]
    (do
      (assert (and (>= (lim/seedTtlMs) 60000) (<= (lim/seedTtlMs) 3600000)) (str "the seed ttl stays between a minute and an hour, so the cached ask in this test is inside it: " (stringFromInt64 (lim/seedTtlMs))))
      (assert (= (pairSecond first) "") (str "two sent calls in the ledger leave a limit of three open: " (pairSecond first)))
      (assert (= (listLength firstSrv.limitRows) 2) "the first ask seeded both rows from the file")
      (assert (> firstSrv.limitSeededMs 0) "and marked the loop seeded")
      (assert (= (pairSecond cached) "") (str "a call appended after the seed is not seen within the seed ttl: " (pairSecond cached)))
      (assert (stringStartsWith? (pairSecond fresh) "limit:hour") (str "a fresh loop reads the file again and sees three calls: " (pairSecond fresh)))
      (assert (= (pairSecond old) "") (str "calls two days old and calls of another provider do not count: " (pairSecond old)))
      (assert (= (listLength oldSrv.limitRows) 5) (str "only the rows inside the window are held: " (stringFromInt64 (listLength oldSrv.limitRows))))
      true))
