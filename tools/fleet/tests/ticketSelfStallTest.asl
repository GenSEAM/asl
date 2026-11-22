(module asl-tools/fleet/tests/ticketSelfStallTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js)])

; (:m :ref JOBSERVER-ABANDONED-TICKET :do "owner P files k1 behind a held token, abandons it and files k2 with the token free: k2 and a second owner's grant must arrive within 3 s although k1's deadline is 20 s away; tickets and tokens live in a scratch dir, never the machine jobserver; no child process is started")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/ticketSelfStallTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! waitGrant dir: String key: String untilNs: Int64 -> js/Grant
  (let [(g (js/want dir "writer" key 60000))]
    (if (and (= g.state "wait") (< (monotonicNs) untilNs))
      (do (sleepMs 50) (waitGrant dir key untilNs))
      g))

fn ! testAbandoned -> Bool
  (let [(dir (scratch "a"))
        (_ (rmDir dir))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/config.asn") "(:jobserver :tokens 1)\n"))
        (holder (js/want dir "writer" "h" 600000))
        (k1 (js/want dir "writer" "k1" 600000))
        (_ (js/releaseIdxs dir holder.idxs))
        (t0 (monotonicNs))
        (k2 (waitGrant dir "k2" (+ t0 45000000000)))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (_ (js/releaseIdxs dir k2.idxs))
        (_ (js/dropTicket dir "writer" "k1"))
        (k3 (js/want dir "writer" "k3" 600000))
        (_ (js/releaseIdxs dir k3.idxs))
        (_ (rmDir dir))]
    (do (assert (= k1.state "wait") (str "k1 waited behind the held token: " k1.state))
        (assert (= k2.state "ready") (str "k2 granted although abandoned k1 is older: " k2.state " after " ms " ms"))
        (assert (< ms 3000) (str "grant within the 3 s bound: " ms))
        (assert (= k3.state "ready") (str "dropTicket and the pool stay usable: " k3.state))
        true))

fn ! runTests -> Bool
  (do (assert (testAbandoned) "an abandoned older ticket of a live owner does not block the queue")
      true)

fn ! rmDir dir: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 16)))] (= d.exit 0))
