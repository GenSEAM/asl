(module aslGateway/tests/ledgerRotationTest
  :x [runTests]
  :i [(aslGateway/server :a srv) (aslGateway/config :a c) (aslGateway/usageLedger :a ul) (aslGateway/poolDispatch :a pd) (aslGateway/breaker :a b)
      (aslGateway/upstream :a u) (aslGateway/dispatch :a dp) (aslGateway/chat :a ch) (aslGateway/omniApi :a om) (asl-json/json :a j)])

fn rowAt atMs: Int64 -> ul/CallRow
  (ul/CallRow :atMs atMs :profile "p" :intent "construct" :alias "a" :provider "pv" :model "m" :inTokens 10 :cachedTokens 0 :outTokens 2
    :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn ! loopAt home: String wiringText: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText (some wiringText) :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "a failed attempt settles through settledFailure! and its usage note runs the real effUsageNote path")
fn ! failedAttempt! home: String f: u/UpstreamFailure outcome: String -> Bool
  (let [(srv1 (srv/settledFailure! (loopAt home "(:gateway :v 2)") "ifm/m1" "ifm" "coder" "m1" "" (ul/defaultCallParams) 0 "freeBulk" f))
        (ran (srv/runEffect! srv1 (ch/effUsageNote "ifm" "m1Alias" outcome (j/jnull))))]
    true)

fn rowFor rows: (List ul/CallRow) status: Int64 -> (Option ul/CallRow)
  (listHead (filter (fn [(r ul/CallRow)] -> Bool (= r.status status)) rows))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "a scripted upstream 400 and 429 each leave a shared-ledger row naming provider, model, status and a redacted reason")
fn ! failureChecks -> Bool
  (let [(home "/tmp/ledgerRotationTest")
        (_ (pathRemove home))
        (made (dirCreate home))
        (a400 (failedAttempt! home (u/httpFailure 400 "Bad Request" "{\"error\":\"model m1 rejects tools\",\"auth\":\"Authorization: Bearer abcdefghij0123456789KLMN\"}" (list)) "4xx"))
        (a429 (failedAttempt! home (u/httpFailure 429 "Too Many Requests" "{\"error\":\"rate limited\"}" (list)) "429"))
        (rows (resultOr (ul/readRows! (ul/defaultSharedUsagePath home)) (list)))
        (r400 (rowFor rows 400))
        (r429 (rowFor rows 429))
        (raw (resultOr (fileReadString (ul/defaultSharedUsagePath home)) ""))
        (_ (pathRemove home))]
    (do
      (assert (= (listLength rows) 2) (str "two failed attempts leave two rows: " (stringFromInt64 (listLength rows))))
      (assert (match r400 ((some r) (and (= r.provider "ifm") (and (= r.model "m1") (= r.outcome "4xx")))) ((none) false)) (str "the 400 row names provider ifm, model m1 and outcome 4xx: " raw))
      (assert (match r400 ((some r) (match r.reason ((some t) (and (stringContains? t "400 Bad Request") (stringContains? t "rejects tools"))) ((none) false))) ((none) false)) (str "the 400 row keeps the status line and body as its reason: " raw))
      (assert (not (stringContains? raw "abcdefghij0123456789")) (str "the bearer token in the upstream body is not written: " raw))
      (assert (match r429 ((some r) (and (= r.provider "ifm") (= r.outcome "429"))) ((none) false)) (str "the 429 row names provider ifm and status 429: " raw))
      true))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "secrets never reach a reason: the run after Bearer, a labelled key value and a key-shaped token are replaced, the plain words around them stay")
fn redactChecks -> Bool
  (let [(bearer (ul/redactReason "401 Unauthorized: bad header Authorization: Bearer tok_short9"))
        (labelled (ul/redactReason "{\"api_key\":\"zz9QW\",\"error\":\"invalid\"}"))
        (shaped (ul/redactReason "upstream said key AKIAabcdefgh1234567890XYZ was revoked"))
        (sk (ul/redactReason "no access for sk-proj-abcdef"))
        (lines (ul/redactReason "line one\nline two"))
        (plain (ul/redactReason "400 Bad Request: model m1 rejects tools"))]
    (do
      (assert (and (not (stringContains? bearer "tok_short9")) (stringContains? bearer "[redacted]")) (str "the run after Bearer is redacted: " bearer))
      (assert (and (not (stringContains? labelled "zz9QW")) (stringContains? labelled "invalid")) (str "a labelled key value is redacted: " labelled))
      (assert (and (not (stringContains? shaped "AKIAabcdefgh1234567890XYZ")) (stringContains? shaped "was revoked")) (str "a key-shaped token is redacted: " shaped))
      (assert (not (stringContains? sk "sk-proj-abcdef")) (str "an sk- key is redacted: " sk))
      (assert (= lines "line one line two") (str "a reason stays on one line: " lines))
      (assert (= plain "400 Bad Request: model m1 rejects tools") (str "plain text is kept: " plain))
      (assert (<= (stringLength (ul/redactReason (stringJoin (map (fn [(i Int64)] -> String "word ") (range 0 100)) ""))) 200) "a reason keeps at most 200 characters")
      true))

fn ! appendAll! path: String from: Int64 to: Int64 maxBytes: Int64 keep: Int64 -> Bool
  (listAll? (fn [(i Int64)] -> Bool (ok? (ul/appendCallRowWith! path (rowAt i) maxBytes keep))) (range from to))

fn atList rows: (List ul/CallRow) -> (List Int64)
  (map (fn [(r ul/CallRow)] -> Int64 r.atMs) rows)

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "rotation keeps every row across shifts, numbers generations upward, prunes to keep, and a narrow window opens the live file alone")
fn ! rotationChecks -> Bool
  (let [(home "/tmp/ledgerRotationTestRot")
        (_ (pathRemove home))
        (made (dirCreate home))
        (path (str home "/calls.asn"))
        (lineBytes (stringLength (ul/callRowLine (rowAt 1000))))
        (maxBytes (* 3 lineBytes))
        (wrote (appendAll! path 1000 1012 maxBytes 8))
        (gens (ul/generations! path))
        (all (resultOr (ul/readRows! path) (list)))
        (live (resultOr (fileReadString path) ""))
        (liveRows (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit live "\n")))
        (newest (listLength liveRows))
        (narrow (resultOr (ul/windowRead! path 1011) (pair (list) (list))))
        (mid (resultOr (ul/windowRead! path 1004) (pair (list) (list))))
        (pruneHome (str home "/pruned.asn"))
        (wrote2 (appendAll! pruneHome 2000 2012 maxBytes 2))
        (pgens (ul/generations! pruneHome))
        (pall (resultOr (ul/readRows! pruneHome) (list)))]
    (do
      (assert (and wrote (> (listLength gens) 2)) (str "twelve rows at three per file make several generations: " (stringJoin (map stringFromInt64 gens) " ")))
      (assert (= gens (range 1 (+ (listLength gens) 1))) (str "generations are numbered upward from 1, none overwritten: " (stringJoin (map stringFromInt64 gens) " ")))
      (assert (= (atList all) (range 1000 1012)) (str "every row is read once, in order, across the shifts: " (stringJoin (map stringFromInt64 (atList all)) " ")))
      (assert (= (pairFirst narrow) (list path)) (str "a window inside the live file opens the live file alone: " (stringJoin (pairFirst narrow) " ")))
      (assert (= (atList (pairSecond narrow)) (list 1011)) "the narrow window keeps only rows at or after its start")
      (assert (and (> (listLength (pairFirst mid)) 1) (< (listLength (pairFirst mid)) (+ (listLength gens) 1))) (str "a wider window opens older generations but stops at the one reaching back: " (stringJoin (pairFirst mid) " ")))
      (assert (= (atList (pairSecond mid)) (range 1004 1012)) "the wider window keeps rows 1004 onward")
      (assert (= (atList (resultOr (ul/readRowsSince! path 1004) (list))) (range 1004 1012)) "readRowsSince! returns the window rows")
      (assert (and wrote2 (= (listLength pgens) 2)) (str "keep 2 leaves two generations: " (stringJoin (map stringFromInt64 pgens) " ")))
      (assert (= (atList pall) (range (- 2012 (listLength pall)) 2012)) "the pruned ledger still reads its newest rows contiguously")
      (assert (> newest 0) "the live file holds the newest rows")
      (do (pathRemove home) true)))

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "a half-written last row is not read, and is read once complete")
fn ! partialChecks -> Bool
  (let [(home "/tmp/ledgerRotationTestPart")
        (_ (pathRemove home))
        (made (dirCreate home))
        (path (str home "/calls.asn"))
        (line (ul/callRowLine (rowAt 5)))
        (half (optionOr (stringSlice line 0 40) line))
        (w1 (fileWrite path (str (ul/callRowLine (rowAt 4)) half)))
        (before (resultOr (ul/readRows! path) (list)))
        (w2 (fileWrite path (str (ul/callRowLine (rowAt 4)) line)))
        (after (resultOr (ul/readRows! path) (list)))
        (_ (pathRemove home))]
    (do
      (assert (= (atList before) (list 4)) "a half-written last row is skipped, not an error")
      (assert (= (atList after) (list 4 5)) "the completed row is read")
      true))

fn ! checked extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))\n") "src" ".asl/mem/calibration/index.asn")

; (:m :ref GW-LEDGER-ROTATION-WINDOW :do "config check bounds :ledgerMaxBytes to 65536..1073741824 and :ledgerKeep to 1..64")
fn ! configChecks -> Bool
  (do
    (assert (= (pairSecond (checked " :ledgerMaxBytes 65535")) 1) "config check refuses :ledgerMaxBytes 65535")
    (assert (= (pairSecond (checked " :ledgerMaxBytes 1073741825")) 1) "config check refuses :ledgerMaxBytes 1073741825")
    (assert (= (pairSecond (checked " :ledgerMaxBytes 65536 :ledgerKeep 64")) 0) "config check accepts the bounds 65536 and 64")
    (assert (= (pairSecond (checked " :ledgerMaxBytes 1073741824 :ledgerKeep 1")) 0) "config check accepts the bounds 1073741824 and 1")
    (assert (stringContains? (pairFirst (checked " :ledgerKeep 0")) "ledgerKeep") "config check refuses :ledgerKeep 0 by name")
    (assert (= (pairSecond (checked " :ledgerKeep 65")) 1) "config check refuses :ledgerKeep 65")
    true)

fn ! runTests -> Bool
  (and (failureChecks) (and (redactChecks) (and (rotationChecks) (and (partialChecks) (configChecks)))))
