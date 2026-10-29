(module aslGateway/tests/usageLedgerTest
  :x [runTests]
  :i [(aslGateway/usageLedger :a ul) (aslGateway/dispatch :a dp) (aslGateway/config :a cfg) (aslGateway/upstream :a u)
      (asl-json/json :a j)])

fn allTrue bs: (List Bool) -> Bool
  (listAll? (fn [(b Bool)] -> Bool b) bs)

fn scratchDir -> String
  "/tmp/usageLedgerTest"

fn sampleRow at: Int64 provider: String model: String alias: String inT: Int64 cachedT: Int64 outT: Int64 ttft: (Option Int64) ms: (Option Int64) outcome: String charge: Int64 -> ul/CallRow
  (ul/CallRow :atMs at :profile "p1" :intent "construct" :alias alias :provider provider :model model :inTokens inT :cachedTokens cachedT :outTokens outT :reasoningTokens 0 :ttftMs ttft :ms ms :outcome outcome :charge charge
    :tag none :temperature none :topP none :maxTokens none :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none)

fn sampleRowTagged at: Int64 provider: String alias: String tag: (Option String) -> ul/CallRow
  (with (sampleRow at provider "m" alias 0 0 1 none (some 5) "ok" 0) :tag tag)

fn rowsEqual? a: ul/CallRow b: ul/CallRow -> Bool
  (allTrue (list (= a.atMs b.atMs) (= a.profile b.profile) (= a.intent b.intent) (= a.alias b.alias) (= a.provider b.provider)
                 (= a.model b.model) (= a.inTokens b.inTokens) (= a.cachedTokens b.cachedTokens) (= a.outTokens b.outTokens) (= a.reasoningTokens b.reasoningTokens)
                 (= a.ttftMs b.ttftMs) (= a.ms b.ms) (= a.outcome b.outcome) (= a.charge b.charge)
                 (= a.tag b.tag) (= a.temperature b.temperature) (= a.topP b.topP) (= a.maxTokens b.maxTokens) (= a.effort b.effort)
                 (= a.api b.api) (= a.stream b.stream) (= a.toolCount b.toolCount) (= a.promptBytes b.promptBytes) (= a.sysHash b.sysHash)))

fn optIntText v: (Option Int64) -> String
  (match v ((some n) (stringFromInt64 n)) ((none) "none"))

fn optFloatText v: (Option Float64) -> String
  (match v ((some f) (stringFromFloat64 f)) ((none) "none"))

fn errText r: (Result ul/CallRow String) -> String
  (match r ((ok _) "") ((err e) e))

fn pct part: Int64 whole: Int64 -> Float64
  (if (= whole 0) 0.0 (* 100.0 (/ (int64ToFloat64 part) (int64ToFloat64 whole))))

; (:m A: row round-trips through callRowLine/callRowParse, with ttftMs/ms both present and both absent, and with the tag/params fields both set and both absent)
fn ! roundTripChecks -> Bool
  (let [(withTtft (sampleRow 1000 "openrouter" "gemini-3.8-flash" "flash" 120 10 340 (some 80) (some 2340) "ok" 12))
        (noTtft (sampleRow 2000 "agy-cli" "" "agyFallback" 0 0 0 none none "skipped-breaker" 0))
        (withParams (ul/CallRow :atMs 3000 :profile "p1" :intent "code" :alias "ocDeepseekFlash" :provider "opencodeGo" :model "deepseek-v4.1-flash"
                      :inTokens 50 :cachedTokens 5 :outTokens 60 :reasoningTokens 15 :ttftMs none :ms (some 900) :outcome "ok" :charge 7
                      :tag (some "leon-run-42") :temperature (some 0.25) :topP (some 0.9) :maxTokens (some 32768) :effort (some "low")
                      :api "responses" :stream true :toolCount 3 :promptBytes 512 :sysHash "ab12cd34ef56" :session none :turn none :consumer none :cacheWriteTokens none))
        (lineA (ul/callRowLine withTtft))
        (lineB (ul/callRowLine noTtft))
        (lineC (ul/callRowLine withParams))
        (parsedA (ul/callRowParse lineA))
        (parsedB (ul/callRowParse lineB))
        (parsedC (ul/callRowParse lineC))]
    (do
      (assert (ok? parsedA) (str "round-trip A parses: " (errText parsedA)))
      (assert (ok? parsedB) (str "round-trip B parses: " (errText parsedB)))
      (assert (ok? parsedC) (str "round-trip C parses: " (errText parsedC)))
      (assert (rowsEqual? withTtft (resultOr parsedA withTtft)) "row with ttftMs/ms present round-trips byte-for-byte")
      (assert (rowsEqual? noTtft (resultOr parsedB noTtft)) "row with ttftMs/ms absent round-trips as none, not 0")
      (assert (rowsEqual? withParams (resultOr parsedC withParams)) "row with tag, temperature, topP, maxTokens, effort, api, stream, toolCount, promptBytes and sysHash all set round-trips byte-for-byte")
      (assert (not (stringContains? lineB "absent\" ")) "absent is a bare atom, not a quoted string")
      (assert (= (resultOr parsedB noTtft).tag none) "a row with no caller tag parses its :tag back as none, not an empty string")
      true))

; (:m B: corrupt rows are a real error, never a silent skip)
fn ! corruptChecks -> Bool
  (let [(notACall "(:notACall :at 1)")
        (missingField "(:call :at 1 :profile \"p\" :intent \"i\" :alias \"a\" :provider \"pr\" :model \"m\" :in 1 :cached 0 :out 1 :ttftMs absent :ms absent :outcome \"ok\")")
        (badType "(:call :at 1 :profile \"p\" :intent \"i\" :alias \"a\" :provider \"pr\" :model \"m\" :in \"notAnInt\" :cached 0 :out 1 :ttftMs absent :ms absent :outcome \"ok\" :charge 0)")
        (missingParamField (ul/callRowLine (sampleRow 1 "p" "m" "a" 1 0 1 none (some 5) "ok" 0)))
        (missingApi (stringReplace missingParamField " :api \"chat\"" ""))]
    (do
      (assert (err? (ul/callRowParse notACall)) "a line whose head is not :call is a parse error")
      (assert (err? (ul/callRowParse missingField)) "a row missing a required field (:charge) is a parse error")
      (assert (err? (ul/callRowParse badType)) "a row with a mistyped field (:in as a string) is a parse error")
      (assert (err? (ul/callRowParse "   ")) "a blank line is a parse error, not an empty success")
      (assert (!= missingApi missingParamField) "the :api field removal actually changed the line under test")
      (assert (err? (ul/callRowParse missingApi)) "a row missing the newer :api field is a parse error too, not silently defaulted")
      true))

; (:m corrupt-row handling inside a multi-line ledger file: one bad line fails the whole read, it never silently drops the bad row and returns only the good ones)
fn ! corruptFileChecks -> Bool
  (let [(path (str (scratchDir) "/corrupt.asn"))
        (good (sampleRow 1 "p" "m" "a" 1 0 1 none (some 5) "ok" 0))
        (text (str (ul/callRowLine good) "(:call :not :even close)\n" (ul/callRowLine good)))
        (madeDir (dirCreate (scratchDir)))
        (wrote (fileWrite path text))
        (result (ul/readRows! path))
        (cleaned (pathRemove path))]
    (do
      (assert (ok? wrote) "scratch file writes")
      (assert (err? result) "readRows! on a ledger with one corrupt line fails the whole read")
      (assert (ok? cleaned) "scratch cleanup")
      true))

; (:m C: the full append -> read loop, fed by values computed through the real dispatch settle/charge path from a fake upstream JSON response, no network)
fn wiringConfigText base: String -> String
  (str "(:gateway :v 2"
       " :providers ((:provider :id fixp :kind openai :base \"" base "/v1\" :keyEnv FIXP_KEY))"
       " :models ((:model :id mA :provider fixp :name \"requested-model\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mA)))))"
       " :uses ((:use :for default :profile default))"
       " :endpoints [(:endpoint :id \"epX\" :provider \"fixp\" :model \"requested-model\" :pricePerMillion 2000000 :maxConcurrency 1)])\n")

fn testEnv -> (Map String String)
  (mapFromPairs (list (pair "FIXP_KEY" "key")))

fn ! wiringFor text: String -> (Result dp/Wiring String)
  (match (cfg/gatewayProfilesLoadText! "/tmp/usageLedgerTest/.asl/gateway.asn" true (ok text) "")
    ((err e) (err e))
    ((ok table)
     (match (u/upstreamSettings (testEnv))
       ((err e) (err e))
       ((ok st) (dp/wiringFromConfig (some table) text st (testEnv) (dp/builtinFamilies))))))

fn fakeUpstreamBody -> String
  "{\"model\":\"served-name\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\"}}],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":200,\"total_tokens\":300,\"cached_tokens\":10}}"

fn ! settlePathChecks -> Bool
  (let [(wired (wiringFor (wiringConfigText "http://127.0.0.1:9")))
        (w (resultOr wired (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))))
        (body (fakeUpstreamBody))
        (total (dp/usageTokens body))
        (settled (dp/settle w "epX" "fixp" total 2500 true 500000))
        (w2 (pairFirst settled))
        (served (dp/servedModel body "requested-model"))
        (price (dp/priceFor w2 "epX"))
        (charge (/ (* (max 0 total) price) 1000000))
        (built (ul/CallRow :atMs 500000 :profile "default" :intent "any" :alias "mA" :provider "fixp" :model served
                 :inTokens 100 :cachedTokens 10 :outTokens 200 :reasoningTokens 0 :ttftMs none :ms (some 2500) :outcome "ok" :charge charge
                 :tag none :temperature none :topP none :maxTokens none :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none))
        (path (str (scratchDir) "/settlePath.asn"))
        (madeDir (dirCreate (scratchDir)))
        (clearedFirst (pathRemove path))
        (wrote (ul/appendCallRow! path built))
        (readBack (ul/readRows! path))
        (rows (resultOr readBack (list)))
        (cleaned (pathRemove path))]
    (do
      (assert (ok? wired) "fixture wiring builds")
      (assert (= served "served-name") "servedModel reads the model field the upstream actually returned")
      (assert (= total 300) "usageTokens reads total_tokens from the fake response")
      (assert (= price 2000000) "priceFor reads the endpoint's configured pricePerMillion")
      (assert (= charge (/ (* 300 2000000) 1000000)) "charge is tokens times price over 1e6, the same formula settle uses")
      (assert (ok? wrote) "appendCallRow! writes the computed row")
      (assert (ok? readBack) "readRows! after append succeeds")
      (assert (= (listLength rows) 1) "exactly the one appended row comes back")
      (assert (rowsEqual? built (optionOr (listHead rows) built)) "the row read back matches what was charged and served")
      (assert (ok? cleaned) "scratch cleanup")
      true))

; (:m D: rotation at the size cap)
fn ! rotationChecks -> Bool
  (let [(path (str (scratchDir) "/rotate.asn"))
        (rotated (str path ".1"))
        (madeDir (dirCreate (scratchDir)))
        (pre1 (pathRemove path))
        (pre2 (pathRemove rotated))
        (small (fileWrite path "(:call :at 1)\n"))
        (noRotate (ul/rotateIfNeeded! path))
        (big (fileWrite path (stringRepeat "a" (+ (ul/maxLedgerBytes) 16))))
        (rotate (ul/rotateIfNeeded! path))
        (rotatedExists (fileExists? rotated))
        (freshExists (fileExists? path))
        (c1 (pathRemove rotated))]
    (do
      (assert (ok? small) "writes a small ledger file")
      (assert (= noRotate (ok false)) "a file under the size cap is not rotated")
      (assert (ok? big) "writes an over-cap ledger file")
      (assert (= rotate (ok true)) "a file at or over the size cap is rotated")
      (assert rotatedExists "the rotated predecessor lands at path.1")
      (assert (not freshExists) "rotation moves the file out, leaving nothing for the next append to collide with, so there is nothing left at path to clean up")
      (assert (ok? c1) "scratch cleanup .1")
      true))

; (:m E: windowMsOf / keyFor reject anything not in the documented set)
fn ! flagChecks -> Bool
  (do
    (assert (= (ul/windowMsOf "1h") (ok 3600000)) "1h is 3600000ms")
    (assert (= (ul/windowMsOf "24h") (ok 86400000)) "24h is 86400000ms")
    (assert (= (ul/windowMsOf "7d") (ok 604800000)) "7d is 604800000ms")
    (assert (err? (ul/windowMsOf "3h")) "an unlisted window is a real error, not a silent default")
    (assert (ok? (ul/keyFor "provider")) "provider is a valid --by key")
    (assert (ok? (ul/keyFor "model")) "model is a valid --by key")
    (assert (ok? (ul/keyFor "alias")) "alias is a valid --by key")
    (assert (err? (ul/keyFor "intent")) "intent is not one of the documented --by keys")
    (assert (ok? (ul/keyFor "param:temperature")) "param:temperature is a valid --by key")
    (assert (ok? (ul/keyFor "param:effort")) "param:effort is a valid --by key")
    (assert (ok? (ul/keyFor "param:api")) "param:api is a valid --by key")
    (assert (err? (ul/keyFor "param:bogus")) "an unrecognized param name is a real error, not a silent wrong grouping")
    true)

; (:m H: filterByTag keeps exact-match rows only; an empty tag query does not filter)
fn ! tagFilterChecks -> Bool
  (let [(rowA (sampleRowTagged 1 "p" "a" (some "run-a")))
        (rowB (sampleRowTagged 2 "p" "a" (some "run-b")))
        (rowNone (sampleRowTagged 3 "p" "a" none))
        (rows (list rowA rowB rowNone))
        (filteredA (ul/filterByTag rows "run-a"))
        (filteredB (ul/filterByTag rows "run-b"))
        (filteredBogus (ul/filterByTag rows "nope"))
        (filteredEmpty (ul/filterByTag rows ""))]
    (do
      (assert (= (listLength filteredA) 1) "filtering by run-a keeps exactly the one row tagged run-a")
      (assert (= (optionOr (listHead filteredA) rowNone).tag (some "run-a")) "the kept row is the one actually tagged run-a")
      (assert (= (listLength filteredB) 1) "filtering by run-b keeps exactly the one row tagged run-b")
      (assert (= (listLength filteredBogus) 0) "a tag query matching nothing returns no rows")
      (assert (= (listLength filteredEmpty) 3) "an empty tag query means no filtering: every row comes back")
      true))

; (:m I: --by param:NAME groups rows by the effective request parameter actually sent)
fn ! paramGroupChecks -> Bool
  (let [(rowLow (with (sampleRow 1 "p" "m" "a" 0 0 10 none (some 100) "ok" 0) :effort (some "low")))
        (rowHigh (with (sampleRow 2 "p" "m" "a" 0 0 10 none (some 100) "ok" 0) :effort (some "high")))
        (rowLow2 (with (sampleRow 3 "p" "m" "a" 0 0 10 none (some 100) "ok" 0) :effort (some "low")))
        (rows (list rowLow rowHigh rowLow2))
        (keyed (ul/keyByParamNamed "effort"))
        (grouped (ul/computeStats rows 3 3600000 keyed))]
    (do
      (assert (= (listLength grouped) 2) "two distinct effort values make two groups")
      (assert (listAny? (fn [(s ul/Stat)] -> Bool (and (= s.key "low") (= s.calls 2))) grouped) "the low-effort group has both low rows")
      (assert (listAny? (fn [(s ul/Stat)] -> Bool (and (= s.key "high") (= s.calls 1))) grouped) "the high-effort group has the one high row")
      true))

fn pairToRow p: (Pair Int64 String) -> ul/CallRow
  (sampleRow (pairFirst p) "prov" "m" "a" 0 0 10 none (some (pairFirst p)) (pairSecond p) 0)

fn emptyStat -> ul/Stat
  (ul/Stat :key "" :calls 0 :ok 0 :inTokens 0 :cachedTokens 0 :outTokens 0 :reasoningTokens 0 :meanMs none :p50Ms none :p90Ms none :outputTps none :tpsBasis "" :charge 0)

; (:m F: aggregation math, percentiles, mean, TPS with and without ttft, cached share, ok percent, window cut, grouping and sort)
fn ! statsMathChecks -> Bool
  (let [(latRows (map pairToRow (list (pair 10 "ok") (pair 20 "ok") (pair 30 "ok") (pair 40 "error") (pair 50 "ok"))))
        (latStats (optionOr (listHead (ul/computeStats latRows 1000000 3600000 ul/keyByProvider)) (emptyStat)))
        (tpsRow (sampleRow 1000000 "provT" "m" "a" 0 0 80 (some 200) (some 1000) "ok" 0))
        (tpsStats (optionOr (listHead (ul/computeStats (list tpsRow) 1000000 3600000 ul/keyByProvider)) (emptyStat)))
        (cacheRows (list (sampleRow 1000000 "provC" "m" "a" 100 25 0 none none "ok" 0) (sampleRow 1000000 "provC" "m" "a" 100 25 0 none none "error" 0)))
        (cacheStats (optionOr (listHead (ul/computeStats cacheRows 1000000 3600000 ul/keyByProvider)) (emptyStat)))
        (windowRows (list (sampleRow 50000000 "provW" "m" "a" 0 0 1 none none "ok" 0) (sampleRow 1 "provW" "m" "a" 0 0 1 none none "ok" 0)))
        (windowed (ul/computeStats windowRows 50000000 3600000 ul/keyByProvider))
        (bigGroup (list (sampleRow 1 "big" "m" "a" 0 0 1 none none "ok" 0) (sampleRow 1 "big" "m" "a" 0 0 1 none none "ok" 0)))
        (smallGroup (list (sampleRow 1 "small" "m" "a" 0 0 1 none none "ok" 0)))
        (sorted (ul/computeStats (listAppend bigGroup smallGroup) 1000000 3600000 ul/keyByProvider))]
    (do
      (assert (= latStats.p50Ms (some 30)) (str "p50 of [10 20 30 40 50] is the nearest-rank 30: got " (optIntText latStats.p50Ms)))
      (assert (= latStats.p90Ms (some 40)) (str "p90 of [10 20 30 40 50] is the nearest-rank 40: got " (optIntText latStats.p90Ms)))
      (assert (= latStats.meanMs (some 30.0)) "mean of [10 20 30 40 50] is 30.0")
      (assert (= latStats.ok 4) "4 of 5 rows in the latency group are ok")
      (assert (= latStats.tpsBasis "ms") "no row in the latency group carries ttftMs, so TPS falls back to ms")
      (assert (= tpsStats.tpsBasis "ttft") "a row with ttftMs present switches the basis to ttft")
      (assert (= tpsStats.outputTps (some 100.0)) (str "TPS uses ms-minus-ttft as the generation time: 80 tokens / 0.8s = 100.0, got " (optFloatText tpsStats.outputTps)))
      (assert (= cacheStats.cachedTokens 50) "cachedTokens sums across the group")
      (assert (> (pct cacheStats.cachedTokens cacheStats.inTokens) 24.9) "cached share is cachedTokens/inTokens as a percent")
      (assert (= (listLength windowed) 1) "a row older than the window is excluded from the window cut")
      (assert (= (optionOr (listHead windowed) (emptyStat)).calls 1) "only the in-window row is counted")
      (assert (= (listLength sorted) 2) "two provider groups appear")
      (assert (= (optionOr (listHead sorted) (emptyStat)).key "big") "groups sort by call count descending, the busier group first")
      true))

; (:m G: rendering is non-empty ASN carrying the fields a human or a parser would look for)
fn ! renderChecks -> Bool
  (let [(rows (list (sampleRow 1000000 "prov" "m" "alias1" 10 2 20 none (some 100) "ok" 5)))
        (stats (ul/computeStats rows 1000000 3600000 ul/keyByProvider))
        (text (ul/statsAsn stats))]
    (do
      (assert (stringStartsWith? text "(:stats ") "statsAsn renders one (:stats ...) form per group")
      (assert (stringContains? text ":key \"prov\"") "the row's group key appears in the rendered line")
      (assert (stringContains? text ":calls 1") "the call count appears")
      (assert (stringContains? text ":charge 5") "the charge sum appears")
      true))

fn ! runTests -> Bool
  (allTrue (list (roundTripChecks) (corruptChecks) (corruptFileChecks) (settlePathChecks) (rotationChecks) (flagChecks) (tagFilterChecks) (paramGroupChecks) (statsMathChecks) (renderChecks)))
