(module aslGateway/tests/ledgerAttribTest
  :x [runTests]
  :i [(server :a srv) (aslGateway/config :a c) (aslGateway/usageLedger :a ul) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b)
      (aslGateway/upstream :a u) (aslGateway/dispatch :a dp) (aslGateway/chat :a ch) (aslGateway/usage :a us) (asl-json/json :a j)
      (aslGateway/omniApi :a om)])

fn baseRow -> ul/CallRow
  (ul/CallRow :atMs 1000 :profile "p" :intent "construct" :alias "a" :provider "pv" :model "m" :inTokens 10 :cachedTokens 0 :outTokens 2
    :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none)

; (:m LEON-ATTRIB: a row carrying session, turn, consumer and cache write round-trips, and a row carrying none of them writes none of the four keys)
fn ! rowChecks -> Bool
  (let [(full (with (baseRow) :session (some "s1") :turn (some 2) :consumer (some "leon") :cacheWriteTokens (some 40)))
        (fullLine (ul/callRowLine full))
        (back (ul/callRowParse fullLine))
        (bare (ul/callRowLine (baseRow)))
        (bareBack (ul/callRowParse bare))]
    (do
      (assert (stringContains? fullLine " :session \"s1\" :turn 2 :consumer \"leon\" :cacheWrite 40") (str "attribution keys are written: " fullLine))
      (assert (ok? back) "the attributed row parses")
      (assert (match back ((ok r) (and (= r.session (some "s1")) (and (= r.turn (some 2)) (and (= r.consumer (some "leon")) (= r.cacheWriteTokens (some 40)))))) ((err _) false)) "the four fields survive the round trip")
      (assert (not (stringContains? bare ":session")) "no :session key when none")
      (assert (not (stringContains? bare ":cacheWrite")) "no :cacheWrite key when none")
      (assert (not (stringContains? bare ":consumer")) "no :consumer key when none")
      (assert (match bareBack ((ok r) (and (none? r.session) (and (none? r.turn) (and (none? r.consumer) (none? r.cacheWriteTokens))))) ((err _) false)) "a legacy row parses with the four fields none")
      true))

fn ! usageChecks -> Bool
  (let [(withWrite (j/jobj (list (pair "prompt_tokens" (j/jint 10)) (pair "cache_creation_tokens" (j/jint 7)))))
        (altWrite (j/jobj (list (pair "cache_creation_input_tokens" (j/jint 3)))))
        (zeroWrite (j/jobj (list (pair "cache_creation_tokens" (j/jint 0)))))
        (noWrite (j/jobj (list (pair "prompt_tokens" (j/jint 10)))))]
    (do
      (assert (= (us/usageCacheWrite withWrite) (some 7)) "cache_creation_tokens is read")
      (assert (= (us/usageCacheWrite altWrite) (some 3)) "cache_creation_input_tokens is read")
      (assert (= (us/usageCacheWrite zeroWrite) (some 0)) "a reported zero is zero, not absent")
      (assert (none? (us/usageCacheWrite noWrite)) "no field is none, never invented")
      (assert (none? (us/usageCacheWrite (j/jnull))) "null usage is none")
      true))

fn ! loopAt home: String pending: srv/PendingCall -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText none :families (list) :outbox (list) :pendingCall (some pending) :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn ! settle! home: String tag: String usage: j/Json -> Bool
  (let [(pending (srv/PendingCall :intent "coder" :model "m" :latencyMs 10 :charge 0 :tag tag :params (ul/defaultCallParams) :profile "freeBulk"))
        (ran (srv/runEffect! (loopAt home pending) (ch/effUsageNote "fixp" "mAlias" "ok" usage)))]
    true)

; (:m LEON-ATTRIB: three settled calls of one stub session write three rows with the same :session and turns 1..3 through the real effUsageNote path; a call with no attribution headers writes a row without the fields; an unknown consumer is recorded as other)
fn ! sessionChecks -> Bool
  (let [(home "/tmp/ledgerAttribTest")
        (made (dirCreate home))
        (sharedPath (ul/defaultSharedUsagePath home))
        (cleared (pathRemove sharedPath))
        (clearedStats (pathRemove (ul/defaultLedgerPath home)))
        (u1 (j/jobj (list (pair "prompt_tokens" (j/jint 10)) (pair "completion_tokens" (j/jint 2)) (pair "cache_creation_tokens" (j/jint 9)))))
        (u2 (j/jobj (list (pair "prompt_tokens" (j/jint 10)) (pair "completion_tokens" (j/jint 2)))))
        (a1 (settle! home (srv/packAttrib "" "sessA" "1" "leon") u1))
        (a2 (settle! home (srv/packAttrib "" "sessA" "2" "leon") u2))
        (a3 (settle! home (srv/packAttrib "" "sessA" "3" "leon") u2))
        (a4 (settle! home (srv/packAttrib "calib" "" "" "") u2))
        (a5 (settle! home (srv/packAttrib "" "sessB" "x" "weird") u2))
        (rows (resultOr (ul/readRows! sharedPath) (list)))
        (r1 (optionOr (listGet rows 0) (baseRow)))
        (r2 (optionOr (listGet rows 1) (baseRow)))
        (r3 (optionOr (listGet rows 2) (baseRow)))
        (r4 (optionOr (listGet rows 3) (baseRow)))
        (r5 (optionOr (listGet rows 4) (baseRow)))]
    (do
      (assert (= (listLength rows) 5) (str "five rows written: " (stringFromInt64 (listLength rows))))
      (assert (and (= r1.session (some "sessA")) (and (= r2.session (some "sessA")) (= r3.session (some "sessA")))) "the three turns share one session")
      (assert (and (= r1.turn (some 1)) (and (= r2.turn (some 2)) (= r3.turn (some 3)))) "turns are 1, 2, 3")
      (assert (= r1.consumer (some "leon")) "consumer leon is recorded")
      (assert (= r1.cacheWriteTokens (some 9)) "the reported cache write is recorded")
      (assert (none? r2.cacheWriteTokens) "a usage with no cache write field leaves it absent")
      (assert (and (none? r4.session) (and (none? r4.turn) (and (none? r4.consumer) (= r4.tag (some "calib"))))) "no attribution headers: fields absent, the plain tag still lands")
      (assert (and (= r5.session (some "sessB")) (and (none? r5.turn) (= r5.consumer (some "other")))) "a non-numeric turn is absent and an unknown consumer is other")
      true))

fn ! runTests -> Bool
  (and (rowChecks) (and (usageChecks) (sessionChecks)))
