(module aslGateway/tests/learnTest
  :x [runTests]
  :i [(aslGateway/chat :a ch)
      (aslGateway/config :a c)
      (aslGateway/usageLedger :a ul)
      (aslGateway/limits :a lim)
      (aslGateway/learn :a ln)
      (aslGateway/server :a srv)
      (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b)
      (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp)
      (aslGateway/omniApi :a om)
      (asl-json/json :a j)])

; (:m :ref GW-LIMIT-LEARN :do "a canned ledger gives the learned peaks and the count at the first upstream 429 per window, our own refusals leave the peaks alone, a stored row is never lowered by a fresh pass, a ramp step needs a driven-up cap with no 429 ever, the stored caps are used only with :learnRamp true, and the settings are range checked")
fn t0 -> Int64
  1793300400000

fn rowAt at: Int64 alias: String outcome: String -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias alias :provider "p" :model alias
              :inTokens 100 :cachedTokens 0 :outTokens 10 :reasoningTokens 0 :ttftMs none :ms none
              :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn burst n: Int64 at: Int64 alias: String outcome: String -> (List ul/CallRow)
  (if (<= n 0) (list) (cons (rowAt (+ at (* n 100)) alias outcome) (burst (- n 1) at alias outcome)))

fn ledger -> (List ul/CallRow)
  (listAppend (listAppend (listAppend (burst 7 (t0) "a" "ok") (burst 3 (+ (t0) 1980000) "a" "ok"))
                          (cons (rowAt (+ (t0) 2000000) "a" "429") (burst 4 (t0) "b" "ok")))
              (listAppend (burst 20 (+ (t0) 30000) "a" "throttled") (listAppend (burst 6 (+ (t0) 3980000) "a" "ok") (list (rowAt (+ (t0) 4000000) "a" "429")))))

fn learnedOf rows: (List ln/LearnedRow) alias: String window: String -> (Option ln/LearnedRow)
  (listHead (filter (fn [(r ln/LearnedRow)] -> Bool (and (= r.provider "p") (and (= r.alias alias) (= r.window window)))) rows))

fn peakOf rows: (List ln/LearnedRow) alias: String window: String -> Int64
  (match (learnedOf rows alias window) ((some r) r.peakCalls) ((none) -1))

fn firstOf rows: (List ln/LearnedRow) alias: String window: String -> Int64
  (match (learnedOf rows alias window) ((some r) (optionOr r.first429Calls -1)) ((none) -2))

fn lrow peak: Int64 first: (Option Int64) -> ln/LearnedRow
  (ln/LearnedRow :provider "p" :alias "a" :window "minute" :peakCalls peak :peakTokens (* peak 110) :first429Calls first :first429Tokens none :rows429 0 :seenMs 5)

fn modelLimit calls: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "p" :scope "model" :model "a" :window "minute" :calls calls :tokens 0)

fn capCalls caps: (List ln/CapRow) -> Int64
  (match (listHead caps) ((some r) r.calls) ((none) -1))

fn cfgWith extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\") (:model :id m2 :provider fp :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))")

fn checkOf extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (cfgWith extra) "src" ".asl/mem/calibration/index.asn")

fn ! loopAt home: String text: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir home :registryPath "/tmp/absent.asn"
    :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
    :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
    :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
    :wiringText (some text) :families (list) :outbox (list) :pendingCall none
    :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty)
    :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn answerOf o: ch/ChatOutcome -> String
  (match o ((ch/outStrings xs) (stringJoin xs "/")) (_ "other"))

fn ! askLimit! home: String text: String -> String
  (answerOf (pairSecond (srv/runEffect! (loopAt home text) (ch/effLimit "fp" "m1"))))

fn lrr alias: String refused: Int64 first: (Option Int64) -> ln/LearnedRow
  (ln/LearnedRow :provider "fp" :alias alias :window "minute" :peakCalls 5 :peakTokens 0 :first429Calls first :first429Tokens none :rows429 0 :seenMs 5 :refused refused)

fn rpmCfg providerExtra: String learnExtra: String -> String
  (str "(:gateway :v 2" learnExtra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY" providerExtra ")) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 0.25) (:model :id m2 :provider fp :name \"n2\") (:model :id m3 :provider fp :name \"n3\" :rpm 1)) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2 m3))))) :uses ((:use :for default :profile default)))")

fn ! stepOf! text: String learned: (List ln/LearnedRow) stored: (List ln/RpmRow) pct: Int64 -> (List ln/RpmRow)
  (match (c/gatewayConfigParse! text "src" "")
    ((ok t) (ln/rpmPass t.models t.providers learned stored pct))
    ((err _) (list)))

fn rpmOf rows: (List ln/RpmRow) alias: String -> Float64
  (match (listHead (filter (fn [(r ln/RpmRow)] -> Bool (= r.alias alias)) rows)) ((some r) r.rpm) ((none) -1.0))

fn modelRpm models: (Map String c/GatewayModel) alias: String -> Float64
  (match (mapGet models alias)
    ((some m) (optionOr m.params.rpm -1.0))
    ((none) -2.0))

fn ! tableRpm! text: String alias: String rpms: (List ln/RpmRow) -> Float64
  (match (c/gatewayConfigParse! text "src" "")
    ((ok t) (modelRpm (ln/rampedModels t.models rpms) alias))
    ((err _) -3.0))

fn refusedOf rows: (List ln/LearnedRow) alias: String window: String -> Int64
  (match (learnedOf rows alias window) ((some r) r.refused) ((none) -1))

fn ! worldRpm! home: String -> Float64
  (match (c/gatewayConfigParse! (resultOr (fileReadString (c/gatewayProfilesPath home)) "") "src" "")
    ((err _) -3.0)
    ((ok t)
      (match (srv/rampedWorldTable! home (ok t))
        ((ok r) (modelRpm r.models "m1"))
        ((err _) -4.0))))

fn ! runTests -> Bool
  (let [(rows (ledger))
        (learned (ln/learnRows rows (ln/defaultLearnWindows)))
        (again (ln/mergeLearned learned (ln/learnRows rows (ln/defaultLearnWindows))))
        (merged (ln/mergeLearned (list (lrow 9 (some 2))) (list (lrow 5 (some 6)) (ln/LearnedRow :provider "q" :alias "" :window "hour" :peakCalls 1 :peakTokens 2 :first429Calls none :first429Tokens none :rows429 0 :seenMs 1))))
        (mergedA (optionOr (listHead merged) (lrow 0 none)))
        (tally (ln/refusalsOf rows))
        (tallyP (optionOr (listHead tally) (ln/Refusals :provider "" :ok 0 :own 0 :up429 0 :upOther 0)))
        (ramp1 (ln/rampPass (list (modelLimit 5)) (list (lrow 5 none)) (list) 25))
        (rampLow (ln/rampPass (list (modelLimit 5)) (list (lrow 3 none)) (list) 25))
        (ramp429 (ln/rampPass (list (modelLimit 5)) (list (lrow 5 (some 4))) (list) 25))
        (rampTwice (ln/rampPass (list (modelLimit 5)) (list (lrow 6 none)) (list (ln/CapRow :provider "p" :alias "a" :window "minute" :calls 6)) 25))
        (rampPct (ln/rampPass (list (modelLimit 5)) (list (lrow 5 none)) (list) 100))
        (rampGroup (ln/rampPass (list (c/GatewayLimit :provider "" :scope "group" :model "" :window "minute" :calls 5 :tokens 0 :group "G")) (list (lrow 5 none)) (list) 25))
        (swapped (ln/rampedLimits (list (modelLimit 5)) (list (ln/CapRow :provider "p" :alias "a" :window "minute" :calls 6))))
        (kept (ln/rampedLimits (list (modelLimit 5)) (list (ln/CapRow :provider "p" :alias "a" :window "minute" :calls 4))))
        (lineBack (ln/learnedParse (ln/learnedLine (lrow 5 (some 4)))))
        (capBack (ln/capParse (ln/capLine (ln/CapRow :provider "p" :alias "" :window "day" :calls 7))))
        (badLine (ln/learnedParse "(:learned :provider \"p\")"))
        (okCheck (checkOf " :learnRamp true :learnRampPct 25 :learnWindows \"minute day\""))
        (badPct (checkOf " :learnRampPct 4"))
        (badPctHi (checkOf " :learnRampPct 101"))
        (badRamp (checkOf " :learnRamp \"yes\""))
        (badWin (checkOf " :learnWindows \"minute year\""))
        (home "/tmp/learnTest")
        (_ (pathRemove home))
        (made (dirCreate home))
        (limitText (cfgWith " :limits ((:limit :provider fp :scope model :model m1 :window minute :calls 1 :method doc :verified false :date \"2026-10-31\"))"))
        (rampText (cfgWith " :learnRamp true :limits ((:limit :provider fp :scope model :model m1 :window minute :calls 1 :method doc :verified false :date \"2026-10-31\"))"))
        (sent (ul/appendCallRow! (ul/defaultSharedUsagePath home) (ul/CallRow :atMs (- (/ (nowNs) 1000000) 10000) :profile "" :intent "" :alias "m1" :provider "fp" :model "m1" :inTokens 1 :cachedTokens 0 :outTokens 1 :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)))
        (wroteCaps (ln/writeCaps! (ln/learnedCapsPath home) (list (ln/CapRow :provider "fp" :alias "m1" :window "minute" :calls 2))))
        (capsBack (ln/readCaps! (ln/learnedCapsPath home)))
        (wroteLearned (ln/writeLearned! (ln/learnedPath home) learned))
        (learnedBack (ln/readLearned! (ln/learnedPath home)))
        (noRamp (askLimit! home limitText))
        (withRamp (askLimit! home rampText))
        (_ (pathRemove (ln/learnedCapsPath home)))
        (rampNoCaps (askLimit! home rampText))
        (_ (pathRemove home))
        (cfgRpm (rpmCfg "" ""))
        (stepUp (stepOf! cfgRpm (list (lrr "m1" 20 none)) (list) 25))
        (stepNoRefusal (stepOf! cfgRpm (list (lrr "m1" 0 none)) (list) 25))
        (step429 (stepOf! cfgRpm (list (lrr "m1" 20 (some 3))) (list) 25))
        (stepShared (stepOf! (rpmCfg " :rpm 2 :rpmShared true" "") (list (lrr "m1" 20 none)) (list) 25))
        (stepNoOwn (stepOf! cfgRpm (list (lrr "m2" 20 none)) (list) 25))
        (stepSecond (stepOf! cfgRpm (list (lrr "m1" 20 none)) (list (ln/RpmRow :alias "m1" :rpm 0.3125)) 100))
        (stepCeil (stepOf! cfgRpm (list (lrr "m1" 20 none)) (list (ln/RpmRow :alias "m1" :rpm 1.9)) 100))
        (stepHeld (stepOf! cfgRpm (list (lrr "m1" 0 none)) (list (ln/RpmRow :alias "m1" :rpm 0.5)) 25))
        (stepTwo (stepOf! cfgRpm (list (lrr "m1" 20 none) (lrr "m3" 5 none)) (list) 100))
        (swapRpm (tableRpm! cfgRpm "m1" (list (ln/RpmRow :alias "m1" :rpm 0.5))))
        (lowRpm (tableRpm! cfgRpm "m1" (list (ln/RpmRow :alias "m1" :rpm 0.1))))
        (noOwnRpm (tableRpm! cfgRpm "m2" (list (ln/RpmRow :alias "m2" :rpm 5.0))))
        (rpmBack (ln/rpmParse (ln/rpmLine (ln/RpmRow :alias "m1" :rpm 0.3125))))
        (rpmBad (ln/rpmParse "(:rpm :alias \"m1\")"))
        (refusedBack (ln/learnedParse (ln/learnedLine (lrr "m1" 7 none))))
        (rpmHome "/tmp/learnTestRpm")
        (_ (pathRemove rpmHome))
        (rpmMade (dirCreate (str rpmHome "/.asl")))
        (rpmCfgPath (c/gatewayProfilesPath rpmHome))
        (rpmWrote (ln/writeRpm! (ln/learnedRpmPath rpmHome) (list (ln/RpmRow :alias "m1" :rpm 0.5))))
        (rpmRead (ln/readRpm! (ln/learnedRpmPath rpmHome)))
        (rpmNone (ln/readRpm! (ln/learnedRpmPath "/tmp/learnTestNoSuchHome")))
        (offFile (fileWrite rpmCfgPath (rpmCfg "" "")))
        (offWorld (worldRpm! rpmHome))
        (onFile (fileWrite rpmCfgPath (rpmCfg "" " :learnRamp true")))
        (onWorld (worldRpm! rpmHome))
        (_ (pathRemove rpmHome))]
    (do
      (assert (= (peakOf learned "a" "minute") 7) (str "alias a reached 7 sent calls in one minute: " (stringFromInt64 (peakOf learned "a" "minute"))))
      (assert (= (peakOf learned "b" "minute") 4) "alias b reached 4")
      (assert (= (peakOf learned "" "minute") 11) (str "the provider row sums its aliases: " (stringFromInt64 (peakOf learned "" "minute"))))
      (assert (= (firstOf learned "a" "minute") 4) (str "3 calls and the 429 itself make 4 at the first 429: " (stringFromInt64 (firstOf learned "a" "minute"))))
      (assert (= (firstOf learned "b" "minute") -1) "an alias that never saw a 429 has none")
      (assert (= (peakOf learned "a" "hour") 7) (str "the hour peak is a span free of 429 only: " (stringFromInt64 (peakOf learned "a" "hour"))))
      (assert (= (listLength learned) (* 5 3)) (str "three groups times five windows: " (stringFromInt64 (listLength learned))))
      (assert (= (listLength again) (listLength learned)) "a second pass over the same ledger adds no rows")
      (assert (= (peakOf again "a" "minute") 7) "and changes no peak")
      (assert (and (= mergedA.peakCalls 9) (= mergedA.first429Calls (some 2))) "a lower fresh peak never erases a stored one, the smaller count at a 429 is kept")
      (assert (= (listLength merged) 2) "a fresh row for a new key is added")
      (assert (and (= tallyP.ok 20) (= tallyP.own 20) (= tallyP.up429 2) (= tallyP.upOther 0)) (str "own refusals counted apart from provider answers: " (ln/refusalLine tallyP)))
      (assert (= (capCalls ramp1) 6) "a cap driven up to with no 429 rises by 25 percent, at least 1")
      (assert (listEmpty? rampLow) "a peak under the cap does not ramp")
      (assert (listEmpty? ramp429) "a 429 seen stops the ramp")
      (assert (= (capCalls rampTwice) 7) "a second step starts from the stored cap")
      (assert (= (capCalls rampPct) 10) "pct 100 doubles")
      (assert (listEmpty? rampGroup) "group rows are not ramped")
      (assert (= (capCalls (map (fn [(l c/GatewayLimit)] -> ln/CapRow (ln/CapRow :provider "" :alias "" :window "" :calls l.calls)) swapped)) 6) "a matching cap replaces the configured calls")
      (assert (= (capCalls (map (fn [(l c/GatewayLimit)] -> ln/CapRow (ln/CapRow :provider "" :alias "" :window "" :calls l.calls)) kept)) 5) "a cap under the configured value is ignored")
      (assert (match lineBack ((ok r) (and (= r.peakCalls 5) (= r.first429Calls (some 4)))) ((err _) false)) "a learned row survives its line")
      (assert (match capBack ((ok r) (and (= r.calls 7) (= r.window "day"))) ((err _) false)) "a cap row survives its line")
      (assert (match badLine ((err _) true) ((ok _) false)) "a learned row without its peak is an error, not a guess")
      (assert (= (pairSecond okCheck) 0) (str "the learn settings in range are clean: " (pairFirst okCheck)))
      (assert (and (= (pairSecond badPct) 1) (stringContains? (pairFirst badPct) "learnRampPct")) (str "learnRampPct 4 is an error: " (pairFirst badPct)))
      (assert (= (pairSecond badPctHi) 1) "learnRampPct 101 is an error")
      (assert (and (= (pairSecond badRamp) 1) (stringContains? (pairFirst badRamp) "learnRamp")) (str "learnRamp must be a boolean: " (pairFirst badRamp)))
      (assert (and (= (pairSecond badWin) 1) (stringContains? (pairFirst badWin) "year")) (str "an unknown learn window is an error: " (pairFirst badWin)))
      (assert (ok? wroteCaps) "caps file written")
      (assert (match capsBack ((ok cs) (= (listLength cs) 1)) ((err _) false)) "caps file read back")
      (assert (match learnedBack ((ok ls) (= (listLength ls) (listLength learned))) ((err _) false)) "learned file read back whole")
      (assert (stringStartsWith? noRamp "limit:minute") (str "without :learnRamp the stored caps are not used: " noRamp))
      (assert (stringEmpty? withRamp) (str "with :learnRamp true the stored cap of 2 lets the second call through: " withRamp))
      (assert (stringStartsWith? rampNoCaps "limit:minute") (str "ramp on with no caps file keeps the configured cap: " rampNoCaps))
      (assert (srv/gatewayCliMode? "learn") "gateway learn runs in the CLI main like stats")
      (assert (= (refusedOf learned "a" "minute") 20) (str "the 20 throttled rows are counted as refusals: " (stringFromInt64 (refusedOf learned "a" "minute"))))
      (assert (= (refusedOf learned "b" "minute") 0) "an alias with no throttled row has none")
      (assert (match refusedBack ((ok r) (= r.refused 7)) ((err _) false)) "the refusal count survives its line")
      (assert (= (rpmOf stepUp "m1") 0.3125) (str "a refused bucket with no 429 rises 25 percent: " (stringFromFloat64 (rpmOf stepUp "m1"))))
      (assert (listEmpty? stepNoRefusal) "no refusal, no rise")
      (assert (listEmpty? step429) "a 429 seen stops the rise")
      (assert (listEmpty? stepShared) "a provider shared bucket is not ramped")
      (assert (listEmpty? stepNoOwn) "a model without its own rpm is not ramped")
      (assert (= (rpmOf stepSecond "m1") 0.625) (str "the second step starts from the stored rate: " (stringFromFloat64 (rpmOf stepSecond "m1"))))
      (assert (= (rpmOf stepCeil "m1") 2.0) (str "the rate stops at 8 times the configured one: " (stringFromFloat64 (rpmOf stepCeil "m1"))))
      (assert (= (rpmOf stepHeld "m1") 0.5) "a stored rate is kept, never lowered")
      (assert (and (= (rpmOf stepTwo "m1") 0.5) (= (rpmOf stepTwo "m3") 2.0)) "each model steps from its own configured rate")
      (assert (= swapRpm 0.5) "the ramped rate replaces the configured rpm")
      (assert (= lowRpm 0.25) "a rate under the configured one is ignored")
      (assert (= noOwnRpm -1.0) "a model without an rpm gets none")
      (assert (match rpmBack ((ok r) (and (= r.alias "m1") (= r.rpm 0.3125))) ((err _) false)) "an rpm row survives its line")
      (assert (match rpmBad ((err _) true) ((ok _) false)) "an rpm row without a rate is an error")
      (assert (and (ok? rpmWrote) (match rpmRead ((ok rs) (= (rpmOf rs "m1") 0.5)) ((err _) false))) "rpm file written and read back")
      (assert (match rpmNone ((ok rs) (listEmpty? rs)) ((err _) false)) "no rpm file reads as no rows")
      (assert (= offWorld 0.25) (str "without :learnRamp the chat world keeps the configured rpm: " (stringFromFloat64 offWorld)))
      (assert (= onWorld 0.5) (str "with :learnRamp true the chat world holds the ramped rpm: " (stringFromFloat64 onWorld)))
      true))
