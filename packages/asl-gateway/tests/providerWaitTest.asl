(module aslGateway/tests/providerWaitTest
  :x [runTests]
  :i [(chat :a ch)
      (server :a srv)
      (upstream :a u)
      (config :a c)
      (breaker :a b)
      (asl-tools/fleet/run :a fr)])

; (:m :ref TLE-2-PROVIDER-WAIT :do "a provider call that goes quiet is cut at its own limit instead of the attempt's whole timeout: no byte at all (firstByteTimeout) or a stream that stops (idleTimeout); the chain moves to the next alias, the call ledger names the outcome, the last alias of a chain returns the named error, three cuts in a row close the alias in the breaker, and configCheck judges the keys. The wire half runs the in-process gateway and curl against fixtures/silentUpstream.asl, started through fleet/run.asl guardStart! with a deadline and ended by a stop file before any assert")

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! scratchBase -> String
  (let [(t (optionOr (envGet "TMPDIR") "/tmp"))] (if (stringEndsWith? t "/") (optionOr (stringSlice t 0 (- (stringLength t) 1)) t) t))

; (:m :do "removes a scratch tree in process (no rm child, so noSelfHost counts no start)")
fn ! removeTree! p: String -> Bool
  (match (fileLstat p)
    ((err _) true)
    ((ok st)
      (if (and st.isDir (not st.isSymlink))
        (let [(kids (match (dirList p) ((ok names) (filter (fn [(n String)] -> Bool (and (!= n ".") (!= n ".."))) names)) ((err _) (list))))
              (gone (fold (fn [(a Bool) (n String)] -> Bool (and (removeTree! (str p "/" n)) a)) true kids))]
          (and gone (ok? (pathRemove p))))
        (ok? (pathRemove p)))))

fn ! drop! dir: String -> Bool
  (if (stringStartsWith? dir (str (scratchBase) "/gwProviderWait-")) (removeTree! dir) false)

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "FX_TEST_KEY" "test-key")

; (:m :do "the provider carries short limits (2 s first byte, 2 s idle) under a 12 s attempt timeout, so a call the limits do not cut is told apart from one they do without waiting minutes; mMute names its own 1 s first-byte limit")
fn wireConfig dir: String base: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id fx :kind openai :base \"" base "\" :keyEnv \"FX_TEST_KEY\" :timeoutSec 12 :firstByteSec 2 :idleSec 2))"
       " :models ((:model :id mSilent :provider fx :name \"silent\") (:model :id mStall :provider fx :name \"stall\" :stream true)"
       " (:model :id mFast :provider fx :name \"fast\") (:model :id mSlow :provider fx :name \"slowStream\" :stream true)"
       " (:model :id mLast :provider fx :name \"silent\") (:model :id mMute :provider fx :name \"mute\" :firstByteSec 1))"
       " :intents ((:intent :id silent) (:intent :id stall) (:intent :id fast) (:intent :id slow) (:intent :id last) (:intent :id mute))"
       " :profiles ((:profile :id default :routes ((:intent silent :chain (mSilent mFast)) (:intent stall :chain (mStall mFast)) (:intent fast :chain (mFast))"
       " (:intent slow :chain (mSlow)) (:intent last :chain (mLast)) (:intent mute :chain (mMute mFast)))))"
       " :uses ((:use :for default :profile default)))")

fn ! waitFile! p: String tries: Int64 -> String
  (if (<= tries 0) ""
    (match (fileReadString p)
      ((ok t) (if (stringEmpty? (stringTrim t)) (do (sleepMs 50) (waitFile! p (- tries 1))) (stringTrim t)))
      ((err _) (do (sleepMs 50) (waitFile! p (- tries 1))))))

(schema Sent
  (:f loop srv/GatewayLoop)
  (:f raw String)
  (:f ms Int64))

; (:m :do "one caller request through the in-process gateway; the 30 s bound is the caller's own and far above every limit under test")
fn ! send! l: srv/GatewayLoop intent: String -> Sent
  (let [(t0 (nowMs!))
        (r (srv/linkSend! l "POST" "/v1/chat/completions" (list (pair "Content-Type" "application/json") (pair "Accept" "application/json") (pair "X-ASL-Intent" intent))
                          "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}" 30000))]
    (Sent :loop (pairFirst r) :raw (match (pairSecond r) ((ok t) t) ((err e) (str "sendError " e))) :ms (- (nowMs!) t0)))

fn rowsOf ledger: String alias: String outcome: String -> Int64
  (listLength (filter (fn [(line String)] -> Bool (and (stringContains? line (str ":alias \"" alias "\"")) (stringContains? line (str ":outcome \"" outcome "\""))))
                      (stringLines ledger)))

fn countOf xs: (List String) x: String -> Int64
  (listLength (filter (fn [(y String)] -> Bool (= y x)) xs))

fn flat s: String -> String
  (stringReplace (stringReplace s "\r\n" " ") "\n" " ")

(schema Wire
  (:f err String)
  (:f raws (Map String String))
  (:f ms (Map String Int64))
  (:f strikeOne Int64)
  (:f closed Bool))

fn noted w: Wire key: String s: Sent -> Wire
  (with w :raws (mapSet w.raws key s.raw) :ms (mapSet w.ms key s.ms))

; (:m :do "the calls in order on one gateway loop, so the breaker state of one call is what the next one meets")
fn ! calls! l0: srv/GatewayLoop -> Wire
  (let [(silent (send! l0 "silent"))
        (strikeOne (b/breakerTimeoutCount silent.loop.breaker "fx:mSilent"))
        (stall (send! silent.loop "stall"))
        (fast (send! stall.loop "fast"))
        (slow (send! fast.loop "slow"))
        (last (send! slow.loop "last"))
        (mute1 (send! last.loop "mute"))
        (mute2 (send! mute1.loop "mute"))
        (mute3 (send! mute2.loop "mute"))
        (closed (some? (b/breakerUntil mute3.loop.breaker "fx:mMute")))
        (mute4 (send! mute3.loop "mute"))
        (w0 (Wire :err "" :raws (mapEmpty) :ms (mapEmpty) :strikeOne strikeOne :closed closed))]
    (noted (noted (noted (noted (noted (noted (noted w0 "silent" silent) "stall" stall) "fast" fast) "slow" slow) "last" last) "mute3" mute3) "mute4" mute4))

fn ! testWire -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (dir (str (scratchBase) "/gwProviderWait-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (portFile (str dir "/port"))
        (seenFile (str dir "/seen.txt"))
        (stopFile (str dir "/stop"))
        (g (fr/guardStart! (list (str here "/bin/asl") "run" (str here "/asl/packages/asl-gateway/tests/fixtures/silentUpstream.asl") portFile seenFile stopFile "200") here (fr/childEnv (list)) (fr/limits 300 20)))
        (port (match g ((ok _) (waitFile! portFile 2400)) ((err _) "")))
        (_cfg (fileWrite (str dir "/.asl/gateway.asn") (str (wireConfig dir (str "http://127.0.0.1:" port "/v1")) "\n")))
        (w (if (stringEmpty? port)
             (Wire :err "the stand-in upstream wrote no port" :raws (mapEmpty) :ms (mapEmpty) :strikeOne -1 :closed false)
             (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
               ((err e) (Wire :err (str "linkOpen: " e) :raws (mapEmpty) :ms (mapEmpty) :strikeOne -1 :closed false))
               ((ok l0) (calls! l0)))))
        (_stop (fileWrite stopFile "stop\n"))
        (out (match g ((ok gd) (fr/guardLoop gd)) ((err o) o)))
        (seen (stringLines (resultOr (fileReadString seenFile) "")))
        (ledger (resultOr (fileReadString (str dir "/calls.asn")) ""))
        (stubGone (fr/stubRemove!))
        (stubLeft (fr/stubDirsOwnedBy (procSelf)))
        (dropped (drop! dir))
        (raw (fn [(k String)] -> String (flat (mapGetOr w.raws k "absent"))))
        (ms (fn [(k String)] -> Int64 (mapGetOr w.ms k -1)))]
    (do (assert (and stubGone (listEmpty? stubLeft)) (str "the stand-in host dir of this run is removed before any assert: " (stringJoin stubLeft " ")))
        (assert dropped "the scratch home is removed")
        (assert (stringEmpty? w.err) (str "the stand-in upstream and the in-process gateway started: " w.err))
        ; (:m (a) no byte at all)
        (assert (stringContains? (raw "silent") "served:fast") (str "a first alias that accepts and never answers is cut and the second alias answers: " (raw "silent")))
        (assert (= (rowsOf ledger "mSilent" "firstByteTimeout") 1) (str "the ledger names the cut attempt firstByteTimeout: " ledger))
        (assert (>= (rowsOf ledger "mFast" "ok") 1) (str "the ledger holds the second alias's ok row: " ledger))
        (assert (and (>= (ms "silent") 1900) (< (ms "silent") 9000)) (str "the cut comes at the 2 s limit, well before the 12 s attempt timeout: " (stringFromInt64 (ms "silent")) " ms"))
        ; (:m (b) a stream that stops)
        (assert (stringContains? (raw "stall") "served:fast") (str "a stream that sends its head and one chunk and stops is cut and the second alias answers: " (raw "stall")))
        (assert (= (rowsOf ledger "mStall" "idleTimeout") 1) (str "the ledger names the stalled attempt idleTimeout, not firstByteTimeout or timeout: " ledger))
        (assert (and (>= (ms "stall") 1900) (< (ms "stall") 9000)) (str "the stall is cut at the 2 s idle limit, well before the 12 s attempt timeout: " (stringFromInt64 (ms "stall")) " ms"))
        ; (:m (c) answers that do come are untouched)
        (assert (and (stringContains? (raw "fast") "served:fast") (< (ms "fast") 1900)) (str "a prompt answer passes untouched: " (stringFromInt64 (ms "fast")) " ms " (raw "fast")))
        (assert (stringContains? (raw "slow") "served:slowStream") (str "a stream whose chunks come 1.2 s apart for 4.8 s outlives both 2 s limits, each chunk restarting the idle clock: " (raw "slow")))
        (assert (and (= (rowsOf ledger "mSlow" "ok") 1) (= (rowsOf ledger "mSlow" "idleTimeout") 0)) (str "the slow stream is one ok row: " ledger))
        ; (:m (d) the last alias of a chain)
        (assert (and (stringContains? (raw "last") " 502 ") (stringContains? (raw "last") "firstByteTimeout")) (str "a silent last alias returns an error that names firstByteTimeout: " (raw "last")))
        (assert (and (>= (ms "last") 1900) (< (ms "last") 9000)) (str "the caller has that error at the 2 s limit: " (stringFromInt64 (ms "last")) " ms"))
        (assert (= (rowsOf ledger "mLast" "firstByteTimeout") 1) (str "the ledger names the last alias's cut: " ledger))
        ; (:m (f) the breaker mark)
        (assert (= w.strikeOne 1) (str "one cut is one timeout strike on the alias's own pool: " (stringFromInt64 w.strikeOne)))
        (assert w.closed "the third cut in a row closes the alias in the breaker")
        (assert (stringContains? (raw "mute3") "served:fast") (str "the third cut call is still answered by the second alias: " (raw "mute3")))
        (assert (and (stringContains? (raw "mute4") "served:fast") (< (ms "mute4") 900)) (str "the next call skips the closed alias and does not wait its 1 s limit again: " (stringFromInt64 (ms "mute4")) " ms " (raw "mute4")))
        (assert (= (countOf seen "mute") 3) (str "the closed alias is not called a fourth time: " (stringJoin seen " ")))
        (assert (= (rowsOf ledger "mMute" "firstByteTimeout") 3) (str "three firstByteTimeout rows for the muted alias: " ledger))
        (assert (= out.exitCode 0) (str "the stand-in upstream ended on its stop file, not on its deadline or a guard limit: " (stringFromInt64 out.exitCode) " " out.stderr))
        true))

; (:m :do "drives the chat steps with scripted effects: every http effect is labelled with its model and both limits, every usage note with its outcome, every breaker event with its name and pool; n1 answers n1Reply, any other model answers ok")
fn ! drive! step: ch/ChatStep labels: String n1Reply: ch/HttpReply fuel: Int64 -> String
  (if (<= fuel 0)
    (str labels "|outOfFuel")
    (match step
      ((ch/stepDone _) labels)
      ((ch/stepRaised kind msg) (str labels "|raised " kind))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels n1Reply (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels n1Reply (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels n1Reply (- fuel 1)))
         ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels n1Reply (- fuel 1)))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels n1Reply (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels n1Reply (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels n1Reply (- fuel 1)))
         ((ch/effBreakerEvent event pool _) (drive! (k ch/outDone) (str labels "|breaker:" event ":" pool) n1Reply (- fuel 1)))
         ((ch/effUsageNote _ _ outcome _) (drive! (k ch/outDone) (str labels "|note:" outcome) n1Reply (- fuel 1)))
         ((ch/effHttp _ m _ _ _ _ _ d)
          (drive! (k (ch/outHttp (if (= m "n1") n1Reply (ch/httpOk 200 (list (pair "Content-Type" "application/json")) "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"))))
                  (str labels "|http:" m ":" (stringFromFloat64 d.firstByteSec) ":" (stringFromFloat64 d.idleSec)) n1Reply (- fuel 1)))
         (_ (drive! (k ch/outDone) labels n1Reply (- fuel 1)))))))

fn unitConfig provider: String m1: String m2: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY" provider ")) :models ((:model :id m1 :provider fp :name \"n1\" :rpm 5" m1 ") (:model :id m2 :provider fp :name \"n2\" :rpm 5" m2 ")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))")

fn ! run! provider: String m1: String m2: String n1Reply: ch/HttpReply -> String
  (match (c/gatewayConfigParse! (unitConfig provider m1 m2) "default" ".asl/mem/calibration/index.asn")
    ((err e) (str "config: " e))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) "no settings")
        ((ok st)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "FP_KEY" "k-PW-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                  "" n1Reply 200)))))

fn cut text: String -> ch/HttpReply
  (ch/httpRaised true (str "curl exit 28: " text))

; (:m :do "which limits an attempt carries, and what a cut attempt is noted as and tells the breaker")
fn ! testResolve -> Bool
  (let [(bare (run! "" "" "" (cut "Operation timed out")))
        (streamBare (run! "" " :stream true" "" (cut (u/idleDeadlineText))))
        (provKeys (run! " :firstByteSec 40 :idleSec 30" " :stream true" "" (cut (u/firstByteDeadlineText))))
        (modelKeys (run! " :firstByteSec 40 :idleSec 30" " :stream true :firstByteSec 7 :idleSec 5" " :idleSec 9" (cut (u/idleDeadlineText))))]
    (do (assert (stringContains? bare "|http:n1:0.0:0.0|") (str "a row that is not a stream and names no key carries no limit: " bare))
        (assert (and (stringContains? bare "|note:timeout") (stringContains? bare "|breaker:reset503:fp:m1") (not (stringContains? bare "noteTimeout"))) (str "an ordinary timeout keeps its outcome and its breaker event: " bare))
        (assert (stringContains? streamBare "|http:n1:90.0:60.0|") (str "a stream row that names no key takes the 90 s and 60 s defaults: " streamBare))
        (assert (and (= (c/defaultStreamFirstByteSec) 90.0) (= (c/defaultStreamIdleSec) 60.0)) "the stream defaults are 90 s to the first byte and 60 s idle")
        (assert (stringContains? streamBare "|note:idleTimeout") (str "a stalled stream is noted idleTimeout: " streamBare))
        (assert (stringContains? streamBare "|breaker:noteTimeout:fp:m1") (str "a stalled stream counts a timeout strike on the alias's pool: " streamBare))
        (assert (stringContains? streamBare "|http:n2:0.0:0.0|") (str "the stalled attempt moves to the next alias, which carries no limit of its own: " streamBare))
        (assert (stringContains? provKeys "|http:n1:40.0:30.0|") (str "a stream row takes its provider's keys over the defaults: " provKeys))
        (assert (stringContains? provKeys "|http:n2:40.0:0.0|") (str "a row that is not a stream takes the provider's first-byte limit and never an idle limit: " provKeys))
        (assert (and (stringContains? provKeys "|note:firstByteTimeout") (stringContains? provKeys "|breaker:noteTimeout:fp:m1")) (str "a silent attempt is noted firstByteTimeout and counts a strike: " provKeys))
        (assert (stringContains? modelKeys "|http:n1:7.0:5.0|") (str "a model's own keys win over its provider's: " modelKeys))
        (assert (stringContains? modelKeys "|http:n2:40.0:0.0|") (str "an :idleSec on a row that is not a stream sets no idle limit: " modelKeys))
        true))

fn ! testClock -> Bool
  (do (assert (not (u/idleExpired? 2000 1000 true 2999)) "before the idle limit the stream is live")
      (assert (u/idleExpired? 2000 1000 true 3000) "a stream silent for the whole idle limit expires")
      (assert (not (u/idleExpired? 2000 1000 false 99999)) "before any byte the idle limit is off, the first-byte limit rules")
      (assert (not (u/idleExpired? 0 1000 true 99999)) "no idle limit never expires")
      (assert (= (u/idleWaitMs 2000 1000 true 2500) (some 500)) "the reactor is woken when the idle limit falls due")
      (assert (= (u/idleWaitMs 2000 1000 false 2500) none) "before any byte the idle limit asks for no wakeup")
      (assert (= (u/idleWaitMs 0 1000 true 2500) none) "no idle limit asks for no wakeup")
      (assert (and (stringContains? (u/firstByteDeadlineText) "firstByteTimeout") (stringContains? (u/idleDeadlineText) "idleTimeout")) "each cut's text names its outcome, so the caller's error does too")
      true)

fn checkConfig provider: String model: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY" provider ")) :models ((:model :id m1 :provider fp :name \"n1\"" model ")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))")

fn ! check! provider: String model: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (checkConfig provider model) "providerWait.asn" "/nonexistent")

fn ! testConfigCheck -> Bool
  (let [(good (check! " :firstByteSec 90 :idleSec 60" " :stream true :firstByteSec 45.5 :idleSec 20"))
        (negProv (check! " :idleSec -5" ""))
        (zeroProv (check! " :idleSec 0" ""))
        (textProv (check! " :idleSec \"soon\"" ""))
        (negModel (check! "" " :idleSec -1"))
        (textModel (check! "" " :idleSec soon"))
        (negFirst (check! " :firstByteSec -3" ""))
        (textFirst (check! "" " :firstByteSec never"))
        (fracProv (check! " :idleSec -0.5" ""))
        (fracModel (check! "" " :idleSec -0.5"))]
    (do (assert (= (pairSecond good) 0) (str "configCheck accepts :firstByteSec and :idleSec on a provider and on a model: " (pairFirst good)))
        (assert (and (!= (pairSecond negProv) 0) (stringContains? (pairFirst negProv) "provider fp: :idleSec must be a positive number")) (str "a negative provider :idleSec is refused by name: " (pairFirst negProv)))
        (assert (and (!= (pairSecond zeroProv) 0) (stringContains? (pairFirst zeroProv) ":idleSec must be a positive number")) (str "a zero provider :idleSec is refused: " (pairFirst zeroProv)))
        (assert (and (!= (pairSecond textProv) 0) (stringContains? (pairFirst textProv) ":idleSec must be a positive number")) (str "a provider :idleSec that is not a number is refused: " (pairFirst textProv)))
        (assert (and (!= (pairSecond negModel) 0) (stringContains? (pairFirst negModel) ":idleSec must be a positive number")) (str "a negative model :idleSec is refused: " (pairFirst negModel)))
        (assert (and (!= (pairSecond textModel) 0) (stringContains? (pairFirst textModel) ":idleSec must be a positive number")) (str "a model :idleSec that is not a number is refused: " (pairFirst textModel)))
        (assert (and (!= (pairSecond fracProv) 0) (stringContains? (pairFirst fracProv) "provider fp: :idleSec must be a positive number")) (str "a negative fractional provider :idleSec is refused: " (pairFirst fracProv)))
        (assert (and (!= (pairSecond fracModel) 0) (stringContains? (pairFirst fracModel) ":idleSec must be a positive number")) (str "a negative fractional model :idleSec is refused: " (pairFirst fracModel)))
        (assert (and (!= (pairSecond negFirst) 0) (stringContains? (pairFirst negFirst) ":firstByteSec must be a positive number")) (str "a negative :firstByteSec is refused: " (pairFirst negFirst)))
        (assert (and (!= (pairSecond textFirst) 0) (stringContains? (pairFirst textFirst) ":firstByteSec must be a positive number")) (str "a :firstByteSec that is not a number is refused: " (pairFirst textFirst)))
        true))

fn ! runTests -> Bool
  (let [(a (testClock))
        (b (testConfigCheck))
        (r (testResolve))
        (w (testWire))]
    (and a (and b (and r w))))
