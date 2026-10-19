; (:m :tags (retry) :do "GW-RETRY-OCGO-HANG (upstream fdPoll bound): upstreamCallLoop! previously polled with fdPoll's timeout fixed at -1 (block forever), relying entirely on curl's own speed-limit (curlConfigFollowing sets speed-time == the full per-attempt timeoutSec), so a provider that accepts the TCP connection and never writes a single byte is invisible until the ENTIRE timeoutSec elapses -- the real report was an opencodeGo-style model with :timeoutSec 900 silently blocking a worker thread. This test opens a real listening socket and never accepts/reads/writes on it: the kernel completes curl's TCP handshake from its listen backlog alone, so curl connects successfully and then waits forever for a response that never comes, exactly reproducing a provider that 'accepts and sends zero bytes'. upstreamCallLoop! now takes an explicit first-byte deadline (an absolute wallSeconds! reading) and fails fast with (transportFailure 28 ...) -- the same shape curl's own CURLE_OPERATION_TIMEDOUT uses -- once it expires with no bytes read, so the existing :retry policy already treats it as retryable with no further changes")
(module aslGateway/tests/firstByteDeadlineTest
  :x [runTests]
  :i [(upstream :a u)])

fn failureText f: u/UpstreamFailure -> String
  (mt f
    ((u/toolAbsent tool detail) (str tool ": " detail))
    ((u/transportFailure code stderrText) (str "curl exit " (stringFromInt64 code) ": " stderrText))
    ((u/httpFailure status reason _ body) (str "http " (stringFromInt64 status) " " reason ": " body))
    ((u/protocolFailure detail) detail))

fn isTimeoutCode28? f: u/UpstreamFailure -> Bool
  (mt f
    ((u/transportFailure code _) (= code 28))
    (_ false))

fn ! runTests -> Bool
  (let [(listener (resultOr (tcpListen 0) -1))
        (listening (> listener 0))
        (port (if listening (resultOr (sockLocalPort listener) 0) 0))
        (req (u/UpstreamRequest :url (str "http://127.0.0.1:" (stringFromInt64 port)) :fragment "/v1/chat/completions" :method "POST"
               :headers (list (pair "Content-Type" "application/json")) :data "{\"model\":\"silent\"}"))
        (env (mapFromPairs (list (pair "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin")))))
        (started (u/upstreamCallStart! req env 30.0))
        (before (u/wallSeconds!))
        (outcome (mt started
                   ((err f) (err f))
                   ((ok call) (u/upstreamCallLoop! call (+ before 1.0)))))
        (afterMs (- (u/wallSeconds!) before))
        (closedListener (do (fdClose listener) true))]
    (do
      (assert listening "the test owns a real listening socket standing in for a silent provider")
      (assert (ok? started) (str "a curl call against a reachable (if silent) port starts cleanly: " (mt started ((err f) (failureText f)) ((ok _) ""))))
      ; (:m the event this test actually proves: the loop returns an error classified exactly like curl's own operation-timed-out (transportFailure, code 28), not a bare duration -- retryableRaised? treats any such timeout as retryable unconditionally, so :retry already picks this failure up with no further changes)
      (assert (mt outcome ((err f) (isTimeoutCode28? f)) ((ok _) false))
        (str "a connection that never sends a byte is classified as the same timeout curl's own CURLE_OPERATION_TIMEDOUT reports (transportFailure 28), not left open: " (mt outcome ((ok _) "got an ok reply from a socket nothing ever wrote to") ((err f) (failureText f)))))
      (assert (< afterMs 5.0) (str "the first-byte deadline (1.0 s here) bounds the wait, it does not fall through to the full 30 s curl timeout: took " afterMs " s"))
      (assert closedListener "the stub socket is closed")
      true))
