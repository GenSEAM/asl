(module aslGateway/tests/serverTest :x [testModelsModeRoutesToCli testBreakerEventParks testExtractThinkBlocks testDetectEshViolation testInspectCompletionCleanTurn testInspectCompletionEshRejection testInspectCompletionQuarantine testStatePathIsolation testEnsureSessionHeader testApiKindOf testEffSleepMsDoesNotBlockReactor testEffBucketWaitDoesNotBlockReactor testBucketWaitReservationsAreSpaced testEffUsageNoteRecordsProfile testBudgetRefusalBlocksOverBudgetProfile testSpreadOrderRatioPersistsAcrossRealCalls testSpreadNote429CooldownGatesViaRealLoop runTests]
  :i [(server :a srv) (aslGateway/config :a c) (aslGateway/usageLedger :a ul) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b) (aslGateway/upstream :a u) (aslGateway/dispatch :a dp) (aslGateway/chat :a ch) (asl-json/json :a j) (aslGateway/omniApi :a om) (aslGateway/router :a rt)])

fn testExtractThinkBlocks -> Bool
  (let [(raw "<think>Planning the solution step by step</think>Here is the completed code.") (res (srv/extractThinkBlocks raw)) (thinkPart (pairFirst res)) (uiPart (pairSecond res))] (do (assert (= thinkPart "Planning the solution step by step") "Think content must match") (assert (= uiPart "Here is the completed code.") "UI content must be stripped of think tags") true))

fn testDetectEshViolation -> Bool
  (do (assert (srv/detectEshViolation "I ran the suite and all 5 tests pass cleanly.") "Must detect all 5 tests pass") (assert (srv/detectEshViolation "Done! All tests pass.") "Must detect all tests pass") (assert (srv/detectEshViolation "The gate passes cleanly without issues.") "Must detect gate passes cleanly") (assert (not (srv/detectEshViolation "Here is the diff for reviewing.")) "Normal progress statement must not be flagged") true)

fn testInspectCompletionCleanTurn -> Bool
  (let [(raw "(:call :tool \"bash\" :cmd \"asl test\")") (verdict (srv/inspectCompletionTurn raw true))] (do (assert verdict.allowed "Clean turn must be allowed") (assert (= (listLength verdict.toolCalls) 1) "Tool call must be extracted") (assert (= verdict.quarantinedThink "") "No think block in raw text") true))

fn testInspectCompletionEshRejection -> Bool
  (let [(raw "The refactor is done and all tests pass cleanly.") (verdict (srv/inspectCompletionTurn raw false))] (do (assert (not verdict.allowed) "Turn must be rejected due to ESH violation") (assert (stringContains? verdict.rejectionReason "ESH violation") "Rejection reason must reference ESH") (assert (stringContains? verdict.cleanOutput "Action blocked") "Clean output must be blocked notice") true))

fn testInspectCompletionQuarantine -> Bool
  (let [(raw "<think>Internal scratchpad</think>Final answer.") (verdict (srv/inspectCompletionTurn raw true))] (do (assert verdict.allowed "Turn must be allowed") (assert (= verdict.quarantinedThink "Internal scratchpad") "CoT must be quarantined") (assert (= verdict.cleanOutput "Final answer.") "User output must match") true))

; (:m regression guard for the 2026-10-16 incident: gatewayStatePath! once equalled c/gatewayProfilesPath, so every gateway start overwrote the real provider/model/profile config with a one-line run-state receipt; this must stay false for whatever HOME the test process has, and must also never collide with the usage ledger)
fn ! testStatePathIsolation -> Bool
  (let [(home (optionOr (envGet "HOME") "/tmp")) (statePath (srv/gatewayStatePath!))]
    (do
      (assert (not (= statePath (c/gatewayProfilesPath home))) "gatewayStatePath! must never equal the real profiles config path")
      (assert (not (= statePath (ul/defaultLedgerPath home))) "gatewayStatePath! must never equal the usage ledger path")
      (assert (stringContains? statePath "/.asl/run/") "the state file lives under .asl/run, alongside the ledger, not at the top of .asl where the profiles config lives")
      true))

; (:m OCSESSION: a provider that declares :sessionHeader rejects a call with no session id at all (MissingSessionID); ensureSessionHeader guarantees X-ASL-Session is always present for withSessionHeader to map onto, without ever overwriting a caller-supplied one)
fn testEnsureSessionHeader -> Bool
  (let [(noSession (srv/ensureSessionHeader (list) 7 123456))
        (fallback (c/headerGet noSession "X-ASL-Session"))
        (withSession (srv/ensureSessionHeader (list (pair "X-ASL-Session" "caller-sess-1")) 7 123456))
        (kept (c/headerGet withSession "X-ASL-Session"))]
    (do
      (assert (not (stringEmpty? fallback)) "a request with no X-ASL-Session gets a non-empty fallback, not MissingSessionID")
      (assert (= fallback (c/headerGet (srv/ensureSessionHeader (list) 7 123456) "X-ASL-Session")) "the fallback is deterministic for the same fd and clock reading")
      (assert (!= fallback (c/headerGet (srv/ensureSessionHeader (list) 8 123456) "X-ASL-Session")) "a different fd yields a different fallback")
      (assert (= kept "caller-sess-1") "a caller-supplied X-ASL-Session is kept exactly as sent, never overwritten")
      (assert (= (listLength withSession) 1) "no duplicate X-ASL-Session is added when the caller already sent one")
      true))

fn testApiKindOf -> Bool
  (do
    (assert (= (srv/apiKindOf "https://api.commandcode.ai/provider/v1/chat/completions") "chat") "a chat/completions URL is classified chat")
    (assert (= (srv/apiKindOf "https://commandcode.ai/provider/v1/responses") "responses") "a /responses URL is classified responses")
    (assert (= (srv/apiKindOf "https://api.commandcode.ai/provider/v1/messages") "messages") "an Anthropic-shaped /messages URL is classified messages")
    (assert (= (srv/apiKindOf "https://opencode.ai/inference/go/v1/models/gemini-4-argon-contributor:generateContent") "generateContent") "a Gemini generateContent URL, whose model name is embedded in the path, is classified generateContent rather than falling through to chat")
    true)

; (:m :tags (retry) :do "GWRETRY-2: effSleepMs must park a connTimer, never call a blocking sleep; proven here with no real network and no clock jitter by timing drive! itself -- a requested 5000 ms sleep must return in well under that, because drive! only records a wake-up deadline, it never calls sleepMs; on the blocking version this effect's own case called sleepMs synchronously and this assertion would take ~5 s and still fail")
fn ! testEffSleepMsDoesNotBlockReactor -> Bool
  (let [(loop0 (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home "/tmp" :rootDir "/tmp" :registryPath "/tmp/absent.asn"
                 :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
                 :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
                 :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
                 :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0))
        (step (ch/stepEffect (ch/effSleepMs 5000) (fn [(_ ch/ChatOutcome)] -> ch/ChatStep (ch/stepDone (ch/ChatResponse :head (list (ch/headStatus 200)) :body "{}")))))
        (before (/ (monotonicNs) 1000000))
        (after1 (srv/drive! loop0 42 "" step))
        (elapsedMs (- (/ (monotonicNs) 1000000) before))
        (parked (listHead (filter (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd 42)) after1.conns)))
        (parkedIsTimer (match parked ((some cn) (match cn.phase ((srv/connTimer _ _ _) true) (_ false))) ((none) false)))]
    (do
      (assert (< elapsedMs 500) (str "drive! returns immediately for a 5000 ms effSleepMs (it parks a connTimer instead of sleeping), took " elapsedMs " ms"))
      (assert parkedIsTimer "the connection for fd 42 is parked in connTimer, not resolved or dropped")
      true))

; (:m :tags (retry) :do "GW-BUCKET-NONBLOCK: same proof as testEffSleepMsDoesNotBlockReactor, for effBucket. The bucket is pre-seeded empty (0 tokens, a slow 0.2/s refill rate, 1.0 capacity) so tokenBucketBegin computes a ~5 s bucketWait; a request waiting on it must not block the reactor for 5 s the way the old synchronous geminiAcquire! did")
fn ! testEffBucketWaitDoesNotBlockReactor -> Bool
  (let [(seededBuckets (u/BucketRegistry :buckets (list (pair (u/bucketKey "bucketTestModel" 12.0)
                                                           (u/TokenBucket :rate 0.2 :capacity 1.0 :tokens 0.0 :lastUpdate (u/wallSeconds!))))))
        (loop0 (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home "/tmp" :rootDir "/tmp" :registryPath "/tmp/absent.asn"
                 :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
                 :buckets seededBuckets :profiles (c/emptyProfilesCache)
                 :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
                 :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0))
        (step (ch/stepEffect (ch/effBucket "bucketTestModel" 12.0 10.0) (fn [(_ ch/ChatOutcome)] -> ch/ChatStep (ch/stepDone (ch/ChatResponse :head (list (ch/headStatus 200)) :body "{}")))))
        (before (/ (monotonicNs) 1000000))
        (after1 (srv/drive! loop0 43 "" step))
        (elapsedMs (- (/ (monotonicNs) 1000000) before))
        (parked (listHead (filter (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd 43)) after1.conns)))
        (parkedIsBucketWait (match parked ((some cn) (match cn.phase ((srv/connBucketWait _ _ _) true) (_ false))) ((none) false)))]
    (do
      (assert (< elapsedMs 500) (str "drive! returns immediately for an empty token bucket needing a ~5 s wait (it parks a connBucketWait instead of blocking in geminiAcquire!), took " elapsedMs " ms"))
      (assert parkedIsBucketWait "the connection for fd 43 is parked in connBucketWait, not resolved or dropped")
      true))

fn bucketWaitDeadlineOf conns: (List srv/GatewayConn) fd: Int64 -> Int64
  (match (listHead (filter (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd fd)) conns))
    ((none) -1)
    ((some cn) (match cn.phase ((srv/connBucketWait d _ _) d) (_ -1))))

; (:m :tags (retry) :do "GW-BUCKET-RESERVE: three requests arriving at the same instant for one empty bucket (0 tokens, 0.2/s refill => 1/rate = 5000 ms) must not all wake at the same deadline (that would let all three through together, over-acquiring past the rate limit); each reservation debits the bucket before the next one reads it, so the three deadlines come out strictly increasing and spaced ~5000 ms apart")
fn ! testBucketWaitReservationsAreSpaced -> Bool
  (let [(seededBuckets (u/BucketRegistry :buckets (list (pair (u/bucketKey "spaceTestModel" 12.0)
                                                           (u/TokenBucket :rate 0.2 :capacity 1.0 :tokens 0.0 :lastUpdate (u/wallSeconds!))))))
        (loop0 (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home "/tmp" :rootDir "/tmp" :registryPath "/tmp/absent.asn"
                 :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
                 :buckets seededBuckets :profiles (c/emptyProfilesCache)
                 :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
                 :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0))
        (step (ch/stepEffect (ch/effBucket "spaceTestModel" 12.0 20.0) (fn [(_ ch/ChatOutcome)] -> ch/ChatStep (ch/stepDone (ch/ChatResponse :head (list (ch/headStatus 200)) :body "{}")))))
        (loop1 (srv/drive! loop0 61 "" step))
        (loop2 (srv/drive! loop1 62 "" step))
        (loop3 (srv/drive! loop2 63 "" step))
        (d1 (bucketWaitDeadlineOf loop3.conns 61))
        (d2 (bucketWaitDeadlineOf loop3.conns 62))
        (d3 (bucketWaitDeadlineOf loop3.conns 63))
        (gap1 (- d2 d1))
        (gap2 (- d3 d2))
        (expectedGapMs 5000.0)]
    (do
      (assert (and (> d1 0) (and (> d2 0) (> d3 0))) (str "all three requests park as connBucketWait: d1=" d1 " d2=" d2 " d3=" d3))
      (assert (< d1 d2) (str "second reservation's deadline is strictly after the first: d1=" d1 " d2=" d2))
      (assert (< d2 d3) (str "third reservation's deadline is strictly after the second: d2=" d2 " d3=" d3))
      (assert (and (> (int64ToFloat64 gap1) (* expectedGapMs 0.9)) (< (int64ToFloat64 gap1) (* expectedGapMs 1.1))) (str "first gap ~1/rate=5000 ms apart (within 10%), got " gap1))
      (assert (and (> (int64ToFloat64 gap2) (* expectedGapMs 0.9)) (< (int64ToFloat64 gap2) (* expectedGapMs 1.1))) (str "second gap ~1/rate=5000 ms apart (within 10%), got " gap2))
      true))

; (:m :do "GW-BUDGET-ENFORCE-20261018 recorded-path proof: cx.profileName threads through chat.asl's effHttp -> server.asl's connHttp/connWarm -> settled! -> PendingCall.profile -> runEffect!'s effUsageNote case builds CallRow.profile from the real pendingCall, never a hardcoded literal; this calls the real runEffect! and reads the real appended ledger row back (ul/readRows!), not a synthesized row")
fn ! testEffUsageNoteRecordsProfile -> Bool
  (let [(home "/tmp/serverTestProfilePath")
        (madeDir (dirCreate home))
        (sharedPath (ul/defaultSharedUsagePath home))
        (clearedShared (pathRemove sharedPath))
        (statsPath (ul/defaultLedgerPath home))
        (clearedStats (pathRemove statsPath))
        (pending (srv/PendingCall :intent "coder" :model "m" :latencyMs 10 :charge 0 :tag "" :params (ul/defaultCallParams) :profile "freeBulk"))
        (loop0 (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
                 :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
                 :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
                 :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
                 :wiringText none :families (list) :outbox (list) :pendingCall (some pending) :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0))
        (ran (srv/runEffect! loop0 (ch/effUsageNote "fixp" "mAlias" "ok" (j/jnull))))
        (rowsRes (ul/readRows! sharedPath))
        (rows (resultOr rowsRes (list)))
        (fallbackRow (ul/CallRow :atMs 0 :profile "" :intent "" :alias "" :provider "" :model "" :inTokens 0 :cachedTokens 0 :outTokens 0
                       :reasoningTokens 0 :ttftMs none :ms none :outcome "" :charge 0 :tag none :temperature none :topP none :maxTokens none
                       :effort none :api "" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none))
        (row (optionOr (listHead rows) fallbackRow))
        (cleanedShared (pathRemove sharedPath))
        (cleanedStats (pathRemove statsPath))]
    (do
      (assert (ok? rowsRes) "the shared usage ledger parses after effUsageNote appends to it")
      (assert (= (listLength rows) 1) "exactly one row written by this single effUsageNote call")
      (assert (= row.profile "freeBulk") (str "CallRow.profile must carry the dispatching PendingCall's profile through runEffect!'s effUsageNote case, got \"" row.profile "\""))
      true))

; (:m :do "GW-BUDGET-ENFORCE-20261018 pre-dispatch refusal: budgetRefusal! must read the SAME clock effUsageNote's CallRow.atMs is written with (nowNs epoch ms, not srv's own monotonic nowMs!) so today's ledger total actually lines up with today's budget, never a monotonic/epoch mismatch that silently never triggers; seeds the shared ledger directly via ul/appendCallRow! (the same write path effUsageNote uses), never a synthesized total")
fn ! testBudgetRefusalBlocksOverBudgetProfile -> Bool
  (let [(home "/tmp/serverTestBudgetPath")
        (madeDir (dirCreate home))
        (sharedPath (ul/defaultSharedUsagePath home))
        (clearedShared (pathRemove sharedPath))
        (atMs (/ (nowNs) 1000000))
        (seeded (ul/appendCallRow! sharedPath
                  (ul/CallRow :atMs atMs :profile "freeBulk" :intent "coder" :alias "mA" :provider "fixp" :model "m"
                    :inTokens 60 :cachedTokens 0 :outTokens 60 :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0
                    :tag none :temperature none :topP none :maxTokens none :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none)))
        (overBudgetText "(:gateway :v 2 :dailyTokenBudgets ((freeBulk 100)))")
        (underBudgetText "(:gateway :v 2 :dailyTokenBudgets ((freeBulk 1000)))")
        (noBudgetText "(:gateway :v 2)")
        (loopFor (fn [(text String)] -> srv/GatewayLoop
                   (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
                     :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
                     :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
                     :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
                     :wiringText (some text) :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0))
        )
        (overResult (srv/budgetRefusal! (loopFor overBudgetText) "freeBulk"))
        (underResult (srv/budgetRefusal! (loopFor underBudgetText) "freeBulk"))
        (noBudgetResult (srv/budgetRefusal! (loopFor noBudgetText) "freeBulk"))
        (emptyProfileResult (srv/budgetRefusal! (loopFor overBudgetText) ""))
        (cleanedShared (pathRemove sharedPath))]
    (do
      (assert (ok? seeded) "the shared ledger accepts the seeded over-threshold row")
      (assert (some? overResult) (str "120 tokens today against a 100-token budget must refuse, got " overResult))
      (assert (none? underResult) "120 tokens today against a 1000-token budget must allow")
      (assert (none? noBudgetResult) "no :dailyTokenBudgets key at all means unlimited, same as today's behavior")
      (assert (none? emptyProfileResult) "an empty profile (unprofiled/passthrough dispatch) is never budget-checked")
      true))

fn ! loopForSpread -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home "/tmp" :rootDir "/tmp" :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn stringsOutcome o: ch/ChatOutcome -> (List String)
  (match o ((ch/outStrings xs) xs) (_ (list)))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "drives 8 real effSpreadOrder calls through the SAME GatewayLoop, threading srv forward exactly as drive! would across 8 separate chat requests, so the SWRR rotation is proven to live in GatewayLoop.spreadState rather than reset per call")
; (:m :ref SPREADLIVE-TEST-SEED :do "the spread rotation starts at a clock-seeded offset in production (GW-SPREAD-START); the test pins the seed to 0 so the expected order is fixed, and the seeded state is the one effSpreadOrder reads under spreadProf|coder")
fn ! seededSpreadLoop -> srv/GatewayLoop
  (with (loopForSpread) :spreadState (mapSet (mapEmpty) "spreadProf|coder" (rt/spreadSeedState (list (pair "a" 3) (pair "b" 1)) 0)))

fn ! pickOverCalls! srv: srv/GatewayLoop n: Int64 acc: (List String) -> (List String)
  (if (<= n 0) (listReverse acc)
    (let [(ran (srv/runEffect! srv (ch/effSpreadOrder "spreadProf" "coder" (list (pair "a" 3) (pair "b" 1)) 60 (list))))
          (order (stringsOutcome (pairSecond ran)))
          (picked (optionOr (listHead order) ""))]
      (pickOverCalls! (pairFirst ran) (- n 1) (cons picked acc))))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "GW-SPREAD-LIVE recorded-provider-stub gate: weights (3 1) through runEffect!'s real GatewayLoop-persisted state give exactly the 6:2 (a a b a a a b a) ratio router.asl's own pure simulation proved in isolation -- without GatewayLoop persistence this would instead pick the same top-weight member every single call")
fn ! testSpreadOrderRatioPersistsAcrossRealCalls -> Bool
  (let [(picks (pickOverCalls! (seededSpreadLoop) 8 (list)))]
    (do
      (assert (= picks (list "a" "a" "b" "a" "a" "a" "b" "a")) (str "SPREADLIVE: weights (3 1) through the real server path must give a a b a a a b a over 8 calls, got " picks))
      true))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "GW-SPREAD-LIVE 429-cooldown gate, deterministic without a sleep: a real effSpreadNote429 records heavy's 429 at the server's own wall clock; a huge :cooldownSec on the very next effSpreadOrder call is certainly still within cooldown (now minus at is a few ms at most) so heavy must be excluded, while a :cooldownSec of 0 is always already elapsed so heavy must be eligible again -- cooldownSec stands in for an injected clock here since both reads are the real wall clock a moment apart")
fn ! testSpreadNote429CooldownGatesViaRealLoop -> Bool
  (let [(noted (srv/runEffect! (loopForSpread) (ch/effSpreadNote429 "heavy")))
        (srv1 (pairFirst noted))
        (members (list (pair "heavy" 3) (pair "light" 1)))
        (duringOrder (stringsOutcome (pairSecond (srv/runEffect! srv1 (ch/effSpreadOrder "coolProf" "coder" members 999999 (list))))))
        (afterOrder (stringsOutcome (pairSecond (srv/runEffect! srv1 (ch/effSpreadOrder "coolProf" "coder" members 0 (list))))))]
    (do
      (assert (not (listContains? duringOrder "heavy")) (str "SPREADLIVE: a huge :cooldownSec right after a real 429 must exclude heavy, got " duringOrder))
      (assert (listContains? duringOrder "light") (str "SPREADLIVE: light must still be available during heavy's cooldown, got " duringOrder))
      (assert (listContains? afterOrder "heavy") (str "SPREADLIVE: a :cooldownSec of 0 is always already elapsed, heavy must be eligible again, got " afterOrder))
      true))

; (:m :ref GW-BREAKER-STALE-20261018 :do "this is exactly the expression linkOpen! uses to build its GatewayLoop.breaker: a configured :breakerCooldownSec composes through makeBreakerState so the real GatewayLoop's cooldownSec is the configured value, not the 600s default; absent config keeps 600s unchanged")
fn ! testLinkOpenBreakerCooldownComposesFromConfig -> Bool
  (let [(configured (b/makeBreakerState (optionOr (c/gatewayBreakerCooldownSecOverride "(:gateway :v 2 :breakerCooldownSec 5)") 600)))
        (defaulted (b/makeBreakerState (optionOr (c/gatewayBreakerCooldownSecOverride "(:gateway :v 2)") 600)))]
    (do
      (assert (= configured.cooldownSec 5) (str "COOLDOWNCFG: linkOpen!'s breaker expression honours a configured :breakerCooldownSec, got " (stringFromInt64 configured.cooldownSec)))
      (assert (= defaulted.cooldownSec 600) (str "COOLDOWNCFG: linkOpen!'s breaker expression keeps the 600s default when unconfigured, got " (stringFromInt64 defaulted.cooldownSec)))
      true))

; (:m :ref GW-BREAKER-STALE-20261018 :do "half-open-probe gate without touching breakerDownFor's pinned exact-0-and-prune contract (breakerFixture.asn seq21/seq22): the existing sequential composition already gives exactly one admitted probe after cooldown expiry, re-tripped immediately if that probe's own call fails -- checkDown at/after expiry prunes and returns 0 (admitted), and if the very next outcome is another failure, breakerNote503/breakerMarkDown re-trips before any further checkDown can run, since this GatewayLoop has no concurrent writers racing the same BreakerState")
fn ! testHalfOpenProbeAdmitsOnceThenRetripsOnFailure -> Bool
  (let [(tripped (b/breakerMarkDown (b/defaultBreakerState) "flaky" 1000))
        (stillDown (b/breakerDownFor tripped "flaky" 1500))
        (afterExpiry (b/breakerDownFor tripped "flaky" 1601))
        (prunedState (pairFirst afterExpiry))
        (probeSecsLeft (pairSecond afterExpiry))
        (probeFails (b/breakerMarkDown prunedState "flaky" 1601))
        (immediatelyAfterFailedProbe (b/breakerDownFor probeFails "flaky" 1602))]
    (do
      (assert (> (pairSecond stillDown) 0) "HALFOPEN: still within cooldown, the breaker stays down")
      (assert (= probeSecsLeft 0) "HALFOPEN: right after cooldown expiry exactly one probe is admitted (0 seconds left)")
      (assert (not (mapHas? prunedState.breakers "flaky")) "HALFOPEN: admitting the probe prunes the stale breaker entry, matching breakerDownFor's pinned contract")
      (assert (> (pairSecond immediatelyAfterFailedProbe) 0) "HALFOPEN: a probe call that fails re-trips the breaker before any further call is admitted")
      true))

; (:m :ref GW-PARK-TYPED :do "the server hands a markDown event's parkSec to the breaker: the pool stays down for that long, not the fixed cooldown, and an event without parkSec keeps the cooldown")
fn ! testBreakerEventParks -> Bool
  (let [(st0 (b/defaultBreakerState))
        (parked (srv/breakerEvent! st0 "markDown" "fp:m1" 1000 7200))
        (plain (srv/breakerEvent! st0 "markDown" "fp:m1" 1000 0))]
    (do (assert (= (pairSecond (b/breakerDownFor parked "fp:m1" 1000)) 7200) "a markDown event with parkSec 7200 parks the pool for 7200 s")
        (assert (= (pairSecond (b/breakerDownFor plain "fp:m1" 1000)) 600) "a markDown event without parkSec keeps the fixed cooldown")
        true))

; (:m :ref GW-MODELS-MODE :do "mode models routes to gatewayCliMain with the other CLI subcommands; run and start stay server modes")
fn testModelsModeRoutesToCli -> Bool
  (do (assert (srv/gatewayCliMode? "models") "mode models goes to gatewayCliMain")
      (assert (and (srv/gatewayCliMode? "config") (srv/gatewayCliMode? "session") (srv/gatewayCliMode? "stats")) "the existing CLI modes still do")
      (assert (not (or (srv/gatewayCliMode? "run") (srv/gatewayCliMode? "start") (srv/gatewayCliMode? ""))) "server modes stay out")
      true)

fn ! runTests -> Bool
  (and (testModelsModeRoutesToCli) (and (testBreakerEventParks) (and (testExtractThinkBlocks) (and (testDetectEshViolation) (and (testInspectCompletionCleanTurn) (and (testInspectCompletionEshRejection) (and (testInspectCompletionQuarantine) (and (testStatePathIsolation) (and (testEnsureSessionHeader) (and (testApiKindOf) (and (testEffSleepMsDoesNotBlockReactor) (and (testEffBucketWaitDoesNotBlockReactor) (and (testBucketWaitReservationsAreSpaced) (and (testEffUsageNoteRecordsProfile) (and (testBudgetRefusalBlocksOverBudgetProfile) (and (testSpreadOrderRatioPersistsAcrossRealCalls) (and (testSpreadNote429CooldownGatesViaRealLoop) (and (testLinkOpenBreakerCooldownComposesFromConfig) (testHalfOpenProbeAdmitsOnceThenRetripsOnFailure)))))))))))))))))))
