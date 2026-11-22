(module asl-tools/fleet/tests/ticketLiveWaiterTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js)])

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/ticketLiveWaiterTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! poll dir: String untilNs: Int64 -> Bool
  (let [(b (js/want dir "writer" "b" 20000))
        (a (js/want dir "writer" "a" 20000))]
    (if (< (monotonicNs) untilNs)
      (do (sleepMs 50) (poll dir untilNs))
      (and (= a.state "wait") (= b.state "wait"))))

fn ! testLiveKeepsPlace -> Bool
  (let [(dir (scratch "a"))
        (_ (rmDir dir))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/config.asn") "(:jobserver :tokens 1 :ticketStaleMs 300)\n"))
        (holder (js/want dir "writer" "h" 20000))
        (a0 (js/want dir "writer" "a" 20000))
        (_ (sleepMs 5))
        (b0 (js/want dir "writer" "b" 20000))
        (bothWait (poll dir (+ (monotonicNs) 1500000000)))
        (_ (js/releaseIdxs dir holder.idxs))
        (b1 (js/want dir "writer" "b" 20000))
        (a1 (js/want dir "writer" "a" 20000))
        (_ (js/releaseIdxs dir a1.idxs))
        (_ (js/releaseIdxs dir b1.idxs))
        (_ (rmDir dir))]
    (do (assert (and (= a0.state "wait") (= b0.state "wait") bothWait) "both live waiters queue for 1.5 s, five stale windows")
        (assert (= b1.state "wait") (str "the later live waiter does not jump the earlier one: " b1.state))
        (assert (= a1.state "ready") (str "the earlier live waiter keeps its place: " a1.state))
        true))

fn ! runTests -> Bool
  (do (assert (testLiveKeepsPlace) "a live polling waiter is never pruned") true)

fn ! rmDir dir: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 16)))] (= d.exit 0))
