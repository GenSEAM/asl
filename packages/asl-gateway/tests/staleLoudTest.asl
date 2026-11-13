(module aslGateway/tests/staleLoudTest
  :x [runTests]
  :i [(server :a srv)
      (aslGateway/cliDispatch :a cli)
      (aslGateway/chat :a ch)
      (aslGateway/config :a c)
      (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b)
      (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp)
      (aslGateway/omniApi :a om)])

; (:m :ref GW-CONFIG-STALE-LOUD :do "a stale hub marks the first write of every reply with X-Asl-Config-Stale after the status line, folds line breaks, caps the value, leaves a clean hub, a body continuation and an already marked reply untouched")
fn ! testMark -> Bool
  (let [(reply "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        (marked (srv/staleMarked "profile p1: bad\nline" reply))
        (twice (srv/staleMarked "profile p1: bad" marked))
        (long (srv/staleMarked (stringRepeat "x" 900) reply))
        (unused 0)]
    (do (assert (= marked "HTTP/1.1 200 OK\r\nX-Asl-Config-Stale: profile p1: bad line\r\nContent-Length: 2\r\n\r\nok") (str "LOUD: header lands after the status line: " marked))
        (assert (= twice marked) "LOUD: a marked reply is not marked twice")
        (assert (= (srv/staleMarked "" reply) reply) "LOUD: a clean hub leaves the reply alone")
        (assert (= (srv/staleMarked "bad" "rest of a streamed body") "rest of a streamed body") "LOUD: a continuation chunk is untouched")
        (assert (< (stringLength long) (+ (stringLength reply) 340)) "LOUD: the value is capped at 300 bytes")
        true))

; (:m :ref GW-CONFIG-STALE-LOUD :do "the status client warning names the loader error and is empty for a clean status; configCheck's failure line names the file")
fn ! testWarn -> Bool
  (let [(stale "(:hub :uptimeSec 3 :configStale (:error \"profile p1: bad\"))")
        (warn (cli/hubStaleWarning stale))]
    (do (assert (stringContains? warn "profile p1: bad") (str "LOUD: warning names the error: " warn))
        (assert (stringStartsWith? warn "gateway: WARNING") "LOUD: warning is marked")
        (assert (= (cli/hubStaleWarning "(:hub :uptimeSec 3)") "") "LOUD: clean status gives no warning")
        (assert (stringContains? (cli/configCheckFailLine "/x/profiles.asn") "/x/profiles.asn") "LOUD: failure line names the file")
        true))

fn emptyLoop home: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir "/tmp" :registryPath "/tmp/absent.asn"
     :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
     :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
     :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
     :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

; (:m :ref GW-CONFIG-STALE-LOUD :do "the real write path: a reply queued through addConn on a stale hub (a link write and a socket write) holds the header in the bytes it will send, and a clean hub sends it unchanged")
fn ! testAddConn -> Bool
  (let [(reply "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        (stale (with (emptyLoop "/tmp") :profiles (c/ProfilesCache :key none :result (err "x") :stale "profile p1: bad")))
        (clean (emptyLoop "/tmp"))
        (viaLink (srv/addConn stale -2 (srv/connWriting reply)))
        (viaSock (srv/addConn stale 7 (srv/connWriting reply)))
        (cleanLink (srv/addConn clean -2 (srv/connWriting reply)))
        (sent (match (listGet viaLink.outbox 0) ((some p) (pairSecond p)) ((none) "")))
        (cleanSent (match (listGet cleanLink.outbox 0) ((some p) (pairSecond p)) ((none) "")))]
    (do (assert (stringContains? sent "\r\nX-Asl-Config-Stale: profile p1: bad\r\n") (str "LOUD: link write carries the header: " sent))
        (assert (= cleanSent reply) "LOUD: a clean hub writes the reply unchanged")
        (assert (= (listLength viaSock.conns) 1) "LOUD: socket write queues one conn")
        (assert (match (listGet viaSock.conns 0) ((some cn) (match cn.phase ((srv/connWriting d) (stringContains? d "X-Asl-Config-Stale: profile p1: bad")) (_ false))) ((none) false)) "LOUD: the queued socket phase holds the marked bytes")
        true))

fn ! runTests -> Bool
  (do (assert (testMark) "GW-CONFIG-STALE-LOUD: header marking")
      (assert (testWarn) "GW-CONFIG-STALE-LOUD: client warning")
      (assert (testAddConn) "GW-CONFIG-STALE-LOUD: addConn path")
      true)
