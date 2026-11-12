(module asl-tools/tests/nativeTestLeaseTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr)])

; (:m :ref PROC-REAPER-ALL :do "the source lives in the test's scratch directory, so this test owns every file it creates; the native fixture checks its own group's lease while its runTests body executes")
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
          "fn ! runTests -> Bool"
          "  (let [(pgid (ownPgid))"
          "        (probe (optionOr (envGet \"ASL_NATIVE_LEASE_PROBE\") \"\"))"
          "        (during (fileExists? (fr/leasePath pgid)))"
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
