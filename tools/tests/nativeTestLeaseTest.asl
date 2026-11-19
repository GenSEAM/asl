(module asl-tools/tests/nativeTestLeaseTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr)])

; (:m :ref PROC-REAPER-ALL :do "the source lives in the test's scratch directory, so this test owns every file it creates; the native fixture checks its own group's lease while its runTests body executes")
; (:m :ref MAIN-RED-SWEEP :do "the runner writes the lease after the spawn returns and after a process snapshot of its own (fr/writeLease! runs ps), so the fixture, which also runs ps before it looks, could look first; it polls for the lease, at most 200 times 50 ms, as the suiteWall fixture does, and still passes only if the lease is there while it runs")
fn fixtureSource -> String
  (stringJoin
    (list "(module aslTools/fixtures/nativeTestLease"
          "  :x [runTests]"
          "  :i [(asl-tools/fleet/run :a fr)])"
          ""
          "fn ownPgid -> Int64"
          "  (fold (fn [(found Int64) (p fr/Proc)] -> Int64"
          "          (if (= p.pid (procSelf)) p.pgid found))"
          "        0 (fr/procSnapshot))"
          ""
          "fn ! leaseSeen! pgid: Int64 tries: Int64 -> Bool"
          "  (if (or (fileExists? (fr/leasePath pgid)) (<= tries 0)) (fileExists? (fr/leasePath pgid)) (do (sleepMs 50) (leaseSeen! pgid (- tries 1))))"
          ""
          "fn ! runTests -> Bool"
          "  (let [(pgid (ownPgid))"
          "        (probe (optionOr (envGet \"ASL_NATIVE_LEASE_PROBE\") \"\"))"
          "        (during (leaseSeen! pgid 200))"
          "        (written (fileWrite probe (stringFromInt64 pgid)))]"
          "    (do (assert (> pgid 0) \"the fixture finds its own process group\")"
          "        (assert during \"the nativeTest runner writes the fixture pgid lease while the fixture runs\")"
          "        (assert (ok? written) \"the fixture records its pgid for the parent test\")"
          "        true))")
    "\n")

fn ! runTests -> Bool
  (let [(cache (str ".asl/cache/nativeTestLeaseTest-" (monotonicNs)))
        (fixture (str cache "/leaseSuite.asl"))
        (probe (str cache "/pgid"))
        (made (dirCreate cache))
        (sourceWritten (fileWrite fixture (fixtureSource)))
        (built (nt/prepareIn cache fixture (nt/fingerprint) "test"))
        (bin (optionOr built.binary ""))
        (out (if (stringEmpty? bin)
               (nt/ProcOut :exitCode 1 :stdout "" :stderr built.reason)
               (nt/runProc (list bin)
                 (some (nt/withEnvOverrides!
                         (list "ASL_ASSERT_REPORT=1"
                               "ASL_PRELUDE=asl/host/out/prelude.asl"
                               (str "ASL_NATIVE_LEASE_PROBE=" probe)))))))
        (pgid (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString probe) ""))) 0))
        (_ (pathRemove probe))]
    (do (assert (ok? made) "the scratch directory is created")
        (assert (ok? sourceWritten) "the tiny native fixture is written")
        (assert (some? built.binary) (str "native compilation of leaseSuite succeeds: " built.reason))
        (assert (= out.exitCode 0) "the native fixture observes its pgid lease while it runs")
        (assert (> pgid 0) "the native fixture records a valid pgid")
        (refute (fileExists? (fr/leasePath pgid)) "the nativeTest runner removes the lease after reaping the fixture")
        true))
