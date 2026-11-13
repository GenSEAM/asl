(module asl/tools/fleet/tests/reapAllTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref PROC-REAPER-ALL :do "a pooled child (the path bounded.asl takes) holds a lease under its own pgid while it runs and none after; a pool start reaps a lease whose owner is gone by killing its group, here a sleeper this test started in its own group under the lease of a dead owner; the orphan sweep picks only this user's ppid-1 test binaries older than 2 h under a native test cache; every process the test starts is bounded and killed at the end; the test first stamps the sweep as just run, so neither it nor a mutant of the sweep filter ever runs the live sweep: the filter is judged on a fixture ps text only")

fn ! leaseFile pid: Int64 -> String
  (fr/leasePath pid)

; (:m :do "live and not a zombie, from a ps snapshot taken outside any pool, since a pool start would itself reap the lease under test")
fn ! alive? pid: Int64 -> Bool
  (and (> pid 1) (listAny? (fn [(p fr/Proc)] -> Bool (= p.pid pid)) (fr/procSnapshot)))

fn ! startSleeper! secs: String -> Int64
  (match (fr/spawnSep (list "sleep" secs) "/" (fr/childEnv (list)))
    ((ok r) r.pid)
    ((err _) -1))

fn psText -> String
  (stringJoin (list
                "  101     1   501   03:10:00 /Users/u/.asl/run/nativeTest/ab12/entries/fooTest"
                "  102     1   501   01:00:00 /Users/u/.asl/run/nativeTest/ab12/entries/youngTest"
                "  103   777   501   05:00:00 /Users/u/.asl/run/nativeTest/ab12/entries/parentedTest"
                "  104     1   502   05:00:00 /Users/v/.asl/run/nativeTest/ab12/entries/otherUserTest"
                "  105     1   501 1-00:00:00 /usr/lib/systemd/systemd --user"
                "  106     1   501   02:00:00 /work/repo/.asl/cache/nativeTest/entries/cacheTest --flag"
                "  107     1   501   04:00:00 /work/repo/.asl/cache/other/notATest"
                "  108     1   501   03:00:00 /Users/a b/.asl/run/nativeTest/ab12/entries/spacedTest --x"
                "  109     1   501   03:00:00 /bin/rm -rf /Users/u/.asl/run/nativeTest/ab12/entries/fooTest"
                "    1     0     0 9-00:00:00 /sbin/launchd") "\n")

; (:m :ref REAPALL-LOWS :do "the executables of the fixture that exist; any other prefix of an args column is not a file")
fn exes -> (List String)
  (list "/Users/u/.asl/run/nativeTest/ab12/entries/fooTest" "/Users/u/.asl/run/nativeTest/ab12/entries/youngTest"
        "/Users/u/.asl/run/nativeTest/ab12/entries/parentedTest" "/Users/v/.asl/run/nativeTest/ab12/entries/otherUserTest"
        "/work/repo/.asl/cache/nativeTest/entries/cacheTest" "/Users/a b/.asl/run/nativeTest/ab12/entries/spacedTest")

fn fixtureFile? p: String -> Bool
  (listContains? (exes) p)

fn picks text: String uid: Int64 minAge: Int64 -> (List Int64)
  (fr/orphanTestPidsWith text uid minAge fixtureFile?)

; (:m :ref REAPALL-LOWS :do "etime as real ps prints it, right-aligned: procps and BSD both print [[dd-]hh:]mm:ss; each row is picked at exactly its age in seconds and not one second above")
fn etimeText -> String
  (stringJoin (list
                "  201     1   501 1-02:03:04 /Users/u/.asl/run/nativeTest/ab12/entries/fooTest"
                "  202     1   501 12-01:02:03 /Users/u/.asl/run/nativeTest/ab12/entries/fooTest"
                "  203     1   501   01:02:03 /Users/u/.asl/run/nativeTest/ab12/entries/fooTest"
                "  204     1   501      08:09 /Users/u/.asl/run/nativeTest/ab12/entries/fooTest"
                "  205     1   501   1:02:03 /Users/u/.asl/run/nativeTest/ab12/entries/fooTest") "\n")

fn pickedAt pid: Int64 minAge: Int64 -> Bool
  (listContains? (picks (etimeText) 501 minAge) pid)

fn ! runTests -> Bool
  (let [(_ (dirCreate (fr/leaseDir)))
        (stamped (ok? (fileWrite (fr/sweepStamp) (stringFromInt64 (nowNs)))))
        (logBefore (resultOr (fileReadString (fr/sweepLog)) ""))
        (probe (fr/runOneLimited (fr/job (list "sh" "-c" "if test -f \"$HOME/.asl/run/fleet/leases/$$.asn\"; then echo leased $$; else echo unleased $$; fi") "/" (fr/childEnv (list))) (fr/limits 20 8)))
        (probePid (optionOr (stringToInt64 (optionOr (listLast (stringSplit (stringTrim probe.out) " ")) "")) 0))
        (probeLeftLease (fileExists? (leaseFile probePid)))
        (deadOwner (optionOr (stringToInt64 (stringTrim (fr/runOneLimited (fr/job (list "sh" "-c" "echo $$") "/" (fr/childEnv (list))) (fr/limits 10 8)).out)) 0))
        (sleeper (startSleeper! "117"))
        (snap (fr/procSnapshot))
        (wall (nowNs))
        (wrote (fr/writeLeaseAt! sleeper deadOwner (monotonicNs) (+ (monotonicNs) 600000000000) (- wall 5000000000) (fr/bornIn snap sleeper) 0))
        (aliveBefore (alive? sleeper))
        (_ (fr/runOneLimited (fr/job (list "true") "/" (fr/childEnv (list))) (fr/limits 10 8)))
        (aliveAfter (alive? sleeper))
        (leaseAfter (fileExists? (leaseFile sleeper)))
        (_ (if (alive? sleeper) (fr/killTree! sleeper) 0))
        (_ (pathRemove (leaseFile sleeper)))
        (picked (picks (psText) 501 7200))
        (sweptNow (fr/sweepOrphanTests!))
        (logAfter (resultOr (fileReadString (fr/sweepLog)) ""))]
    (do
      (assert stamped "the sweep is stamped as just run before the test starts anything")
      (assert (= sweptNow 0) (str "with the stamp fresh the live sweep kills nothing: " (stringFromInt64 sweptNow)))
      (assert (= logAfter logBefore) "no sweep kill is logged while the test runs, so no signal left the fixture's own sleeper")
      (assert (stringStartsWith? probe.out "leased ") (str "a pooled child runs under a lease named by its own pgid: " probe.out))
      (assert (> probePid 1) "the pooled child reported its pid")
      (refute probeLeftLease "the pooled child's lease is removed once it is judged")
      (assert (and (> deadOwner 1) (> sleeper 1)) "the dead owner and the sleeper have pids")
      (assert (and wrote aliveBefore) "the sleeper runs under a lease written for an owner that is gone")
      (refute aliveAfter "a pool start kills the group of a lease whose owner is gone")
      (refute leaseAfter "the reaped lease row is removed")
      (assert (= picked (list 101 106 108)) (str "the sweep picks only this user's ppid-1 test binaries older than 2 h under a native test cache, a path with a space included: " (stringJoin (map stringFromInt64 picked) " ")))
      (refute (listContains? picked 109) "an argument that names a cache binary does not make its command a test binary")
      (assert (= (fr/argsExe "/Users/a b/.asl/run/nativeTest/ab12/entries/spacedTest --x" fixtureFile?) "/Users/a b/.asl/run/nativeTest/ab12/entries/spacedTest") "argv0 with a space is read whole")
      (assert (= (fr/argsExe "/Users/a b/.asl/run/nativeTest/ab12/entries/spacedTest --x" (fn [(p String)] -> Bool false)) "") "no prefix that is a file gives no executable")
      (assert (= (fr/orphanTestPids (psText) 501 7200) (list)) "on disk none of the fixture binaries exist, so the real check picks nothing")
      (assert (= (picks (psText) 502 7200) (list 104)) "another uid sees only its own orphan")
      (assert (= (picks (psText) -1 7200) (list)) "an unknown uid picks nothing")
      (assert (and (pickedAt 201 93784) (not (pickedAt 201 93785))) "d-hh:mm:ss 1-02:03:04 is 93784 s")
      (assert (and (pickedAt 202 1040523) (not (pickedAt 202 1040524))) "dd-hh:mm:ss 12-01:02:03 is 1040523 s")
      (assert (and (pickedAt 203 3723) (not (pickedAt 203 3724))) "hh:mm:ss 01:02:03 is 3723 s")
      (assert (and (pickedAt 204 489) (not (pickedAt 204 490))) "mm:ss 08:09 with leading zeros is 489 s")
      (assert (and (pickedAt 205 3723) (not (pickedAt 205 3724))) "h:mm:ss 1:02:03 is 3723 s")
      (assert (and (fr/nativeTestExe? "/h/.asl/run/nativeTest/x/t") (not (fr/nativeTestExe? "/usr/bin/sleep"))) "only executables under a native test cache are test binaries")
      (assert (= (fr/poolLeaseDeadline 0 1000) (* 61000 1000000)) "a pooled lease outlives the pool limit by a minute")
      (assert (= (fr/poolLeaseDeadline 0 0) (* 86400000 1000000)) "a pool without a limit leases for 24 h")
      true))
