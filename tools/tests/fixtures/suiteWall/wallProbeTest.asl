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

; (:m :ref NATIVETEST-PER-SUITE-WALL :do "the runner leases this binary's process group with its deadline; the lease shows the wall nativeTest ran it under")
fn ! runTests -> Bool
  (let [(lease (leaseText! (procSelf) 200))
        (wallS (/ (- (field lease ":deadlineNs") (field lease ":startNs")) 1000000000))]
    (do (assert (not (stringEmpty? lease)) "the runner wrote a lease for this binary")
        (assert (= wallS 2400) (str "the lease deadline is the declared 2400 s wall: " (stringFromInt64 wallS)))
        true))
