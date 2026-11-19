(module suiteWallFixture/wallProbeTest :x [runTests] :i [(asl-tools/fleet/run :a fr)])

; (:m :ref NATIVETEST-PER-SUITE-WALL :do "a declared wall of 2400 s, above the 1800 s default and below the 7200 s cap")
fn suiteWallS -> Int64
  2400

fn field text: String key: String -> Int64
  (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit text (str key " ")) 1) "") " ")) "")) -1)

; (:m :ref NATIVETEST-PER-SUITE-WALL :do "the runner writes the lease just after the spawn returns, so the binary polls for it, at most 200 times 50 ms")
fn ! leaseText! pid: Int64 tries: Int64 -> String
  (let [(text (resultOr (fileReadString (fr/leasePath pid)) ""))]
    (if (or (not (stringEmpty? text)) (<= tries 0)) text (do (sleepMs 50) (leaseText! pid (- tries 1)))))

; (:m :ref NATIVETEST-PER-SUITE-WALL :do "the runner leases this binary's process group; since TEST-RUNNER-SELECT (a55bb308c) the runner itself kills at the wall and the lease is the backstop 60 s after it, so the lease deadline is the declared wall under nativeTest's own runner (fr/runGuarded kills at the lease deadline) and the wall plus that margin under bin/asl test; the fixture prints which one it saw and the parent test pins each path")
fn ! runTests -> Bool
  (let [(lease (leaseText! (procSelf) 200))
        (wallS (/ (- (field lease ":deadlineNs") (field lease ":startNs")) 1000000000))]
    (do (println (str "wallProbe leaseWallS " (stringFromInt64 wallS)))
        (assert (not (stringEmpty? lease)) "the runner wrote a lease for this binary")
        (assert (or (= wallS 2400) (= wallS 2460)) (str "the lease deadline is the declared 2400 s wall, or that wall plus the 60 s backstop margin: " (stringFromInt64 wallS)))
        true))
