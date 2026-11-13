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
        (assert (= (stringLength (srv/staleHeaderLine (stringRepeat "x" 900))) (+ (stringLength (srv/staleHeaderName)) 2 300 2)) "LOUD: the header line holds exactly 300 value characters")
        (assert (= (stringLength (srv/staleHeaderLine "short")) (+ (stringLength (srv/staleHeaderName)) 2 5 2)) "LOUD: a short value is kept whole")
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

; (:m :ref GW-CONFIG-STALE-LOUD :do "a partial write requeues its rest unmarked: a rest that starts with HTTP/1. on a stale hub stays byte for byte")
fn ! testRequeue -> Bool
  (let [(rest "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        (stale (with (emptyLoop "/tmp") :profiles (c/ProfilesCache :key none :result (err "x") :stale "profile p1: bad")))
        (out (srv/requeueWriting stale 7 rest))]
    (do (assert (= (listLength out.conns) 1) "LOUD: the rest is requeued as one conn")
        (assert (match (listGet out.conns 0) ((some cn) (match cn.phase ((srv/connWriting d) (= d rest)) (_ false))) ((none) false)) "LOUD: the requeued rest is not marked")
        true))

; (:m :ref GW-CONFIG-STALE-LOUD :do "the real partial write: the sender socket is filled until it would block, the peer reads 64 KB, stepWriting! then writes part of a 320 KB reply and requeues the rest; the rest must not carry the header. How much the kernel takes varies, so the reply is a repeating HTTP/1.1 line unit with a rotating pad and the trials run (bounded at 300, nonblocking, sockets closed) until a rest that starts with HTTP/1. is seen: the case a marking requeue rewrites. Not seeing one in 300 trials fails the test (chance (9/10)^300)")
fn ! fillUntilBlocked! fd: Int64 left: Int64 -> Bool
  (if (<= left 0) false
    (match (fdWrite fd (stringRepeat "f" 4096))
      ((err _) true)
      ((ok n) (fillUntilBlocked! fd (- left 1)))))

fn ! shortWriteRest! pad: Int64 -> String
  (match (tcpListen 0)
    ((err _) "!")
    ((ok lfd)
      (match (sockLocalPort lfd)
        ((err _) (do (fdClose lfd) "!"))
        ((ok port)
          (match (tcpConnect port)
            ((err _) (do (fdClose lfd) "!"))
            ((ok cfd)
              (match (sockAccept lfd)
                ((err _) (do (fdClose cfd) (fdClose lfd) "!"))
                ((ok pfd)
                  (let [(nb1 (fdNonBlocking cfd true))
                        (nb2 (fdNonBlocking pfd true))
                        (full (fillUntilBlocked! cfd 4096))
                        (drained (fdRead pfd 65536))
                        (data (str (stringRepeat "x" pad) (stringRepeat "HTTP/1.1\r\n" 32768)))
                        (stale (with (emptyLoop "/tmp") :profiles (c/ProfilesCache :key none :result (err "x") :stale "profile p1: bad")))
                        (conn (srv/GatewayConn :fd cfd :input "" :phase (srv/connWriting data)))
                        (out (srv/stepWriting! stale conn data (list (pair cfd 0))))
                        (rest (match (listGet out.conns 0) ((some cn) (match cn.phase ((srv/connWriting d) d) (_ "!"))) ((none) "!")))
                        (c1 (fdClose pfd))
                        (c2 (fdClose cfd))
                        (c3 (fdClose lfd))]
                    (if (and full (< (stringLength rest) (stringLength data))) rest ""))))))))))

; (:m :ref GW-CONFIG-STALE-LOUD :do "runs short writes until one rest starts with HTTP/1., checking every partial rest on the way: unmarked; returns how many partial rests it saw and whether an HTTP/1. one was among them")
fn ! shortWriteTrials! i: Int64 seen: Int64 marked: Int64 aligned: Bool -> (Pair (Pair Int64 Int64) Bool)
  (if (or (>= i 300) (and aligned (>= seen 3))) (pair (pair seen marked) aligned)
    (let [(r (shortWriteRest! (mod i 10)))
          (partial (and (!= r "") (!= r "!")))]
      (shortWriteTrials! (+ i 1) (if partial (+ seen 1) seen) (if (and partial (stringContains? r "X-Asl-Config-Stale")) (+ marked 1) marked) (or aligned (and partial (stringStartsWith? r "HTTP/1."))))))

fn ! testShortWrite -> Bool
  (let [(res (shortWriteTrials! 0 0 0 false))
        (seen (pairFirst (pairFirst res)))
        (marked (pairSecond (pairFirst res)))]
    (do (assert (>= seen 3) (str "LOUD: short writes happened: " (stringFromInt64 seen)))
        (assert (= marked 0) "LOUD: no requeued rest of a partial write carries the header")
        (assert (pairSecond res) "LOUD: a split landed on HTTP/1., the case a marking requeue would rewrite")
        true))

fn ! runTests -> Bool
  (do (assert (testMark) "GW-CONFIG-STALE-LOUD: header marking")
      (assert (testWarn) "GW-CONFIG-STALE-LOUD: client warning")
      (assert (testAddConn) "GW-CONFIG-STALE-LOUD: addConn path")
      (assert (testRequeue) "GW-CONFIG-STALE-LOUD: partial write rest unmarked")
      (assert (testShortWrite) "GW-CONFIG-STALE-LOUD: stepWriting! short write rest unmarked")
      true)
