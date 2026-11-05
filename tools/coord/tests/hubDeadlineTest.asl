(module asl-tools/coord/tests/hubDeadlineTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIPE-GATES :do "the stand-in hub bounds itself: started for 3 s and never stopped (a test that trapped between startHub! and stopHub!), it is up while its deadline has not passed and gone on its own after it; killTree! at the end is only the backstop of this test")
fn ! state! pid: Int64 -> String
  (stringTrim (resultOr (fr/shellOut (str "/bin/ps -o stat= -p " (stringFromInt64 pid) " || true") 5000) ""))

fn gone? st: String -> Bool
  (or (stringEmpty? st) (stringStartsWith? st "Z"))

fn ! waitGone! pid: Int64 tries: Int64 -> Bool
  (if (gone? (state! pid)) true
    (if (<= tries 0) false (do (sleepMs 500) (waitGone! pid (- tries 1)))))

fn ! runTests -> Bool
  (let [(root (pf/scratch "hubDeadline" "m1"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (_ (fileWrite (str root "/hubReply.txt") "(:verdict :pass :defects () :model m)"))
        (t0 (/ (monotonicNs) 1000000))
        (pid (pf/startHubFor! root 3))
        (upAtStart (not (gone? (state! pid))))
        (selfExit (waitGone! pid 40))
        (elapsed (- (/ (monotonicNs) 1000000) t0))
        (_ (if (> pid 0) (fr/killTree! pid) 0))
        (_ (pf/cleanup root))]
    (do (assert (> pid 0) "the hub stand-in came up")
        (assert upAtStart "the hub is serving before its deadline")
        (assert selfExit "the hub exited on its own with no stopHub! within 20 s of a 3 s deadline")
        (assert (>= elapsed 2500) (str "and not before its deadline: " (stringFromInt64 elapsed) " ms"))
        true))
