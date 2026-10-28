(module asl/tools/coord/tests/triggersTest
  :x [runTests]
  :i [(asl-tools/coord/triggers :a t)])

fn b -> t/TrigIn
  (t/blankTrigIn)

fn only in: t/TrigIn id: String -> Bool
  (= (t/triggerIds in) (list id))

fn has in: t/TrigIn id: String -> Bool
  (some? (listHead (filter (fn [(x String)] -> Bool (= x id)) (t/triggerIds in))))

fn act in: t/TrigIn -> String
  (t/decide in)

fn testQuiet -> Bool
  (do (assert (listEmpty? (t/triggerIds (b))) "a blank healthy state fires nothing")
      (assert (= (act (b)) "") "and decides nothing")
      true)

fn testResRows -> Bool
  (let [(noRed (with (b) :hasRes true :hasRedBefore false))
        (baseG (with (b) :hasRes true :baseGreen true))
        (second (with (b) :hasRes true :hasRedBefore false :missCount 1))]
    (do (assert (only noRed "redBeforeMissing") "no redBefore receipt fires redBeforeMissing")
        (assert (only baseG "redBeforeMissing") "base green fires redBeforeMissing")
        (assert (stringContains? (act noRed) "gate-not-red-on-base") "first miss: fix with the defect")
        (assert (stringContains? (act second) "testgen stage") "second miss: testgen stage")
        (assert (only (with (b) :hasRes true :resAsserts 0 :declaredAsserts 0) "gateVacuous") "zero executed asserts is vacuous")
        (assert (only (with (b) :hasRes true :resAsserts 3 :declaredAsserts 4) "gateVacuous") "declared differs from executed is vacuous")
        (assert (only (with (b) :hasRes true :constantCond true) "gateVacuous") "a constant condition is vacuous")
        (assert (only (with (b) :hasRes true :revertGreen true) "revertGreen") "green with the change reverted")
        (assert (stringContains? (act (with (b) :hasRes true :revertGreen true)) "gate-does-not-pin-change") "revertGreen defect name")
        (assert (only (with (b) :hasRes true :resClaimedGreen 1 :rerunRed true) "claimedGreenMismatch") "claimed green and rerun red")
        (assert (listEmpty? (t/triggerIds (with (b) :hasRes true :resClaimedGreen 0 :rerunRed true))) "an honest red is no mismatch")
        (assert (listEmpty? (t/triggerIds (with (b) :hasRes false :hasRedBefore false :revertGreen true))) "no Res row, no Res trigger")
        true))

fn testSignatures -> Bool
  (do (assert (only (with (b) :ownsOutside true) "ownsViolation") "path outside owns")
      (assert (listEmpty? (t/triggerIds (with (b) :ownsOutside true :widenGranted true))) "a granted widen clears ownsViolation")
      (assert (listEmpty? (t/triggerIds (with (b) :sigCount 1))) "one signature fires nothing")
      (assert (only (with (b) :sigCount 2) "sig2") "2 equal signatures")
      (assert (only (with (b) :sigCount 3) "sig3") "3 equal signatures: sig3 and not sig2")
      (assert (stringContains? (act (with (b) :sigCount 3)) "witness") "sig3 names the witness row")
      (assert (stringContains? (act (with (b) :sigCount 2)) "next writer tier") "sig2 escalates the tier")
      true)

fn testLadderRiskPace -> Bool
  (do (assert (only (with (b) :stepEscalate true :rung 1) "reviewerSplit") "ladder escalate")
      (assert (= (t/decide (with (b) :stepEscalate true :rung 1)) "reviewerSplit: next rung") "below R3: next rung")
      (assert (= (t/decide (with (b) :stepEscalate true :rung 3)) "reviewerSplit: blocked awaiting Claude") "at R3: blocked awaiting Claude")
      (assert (only (with (b) :riskHigh true) "riskHigh") "risk high")
      (assert (only (with (b) :closureChanged true) "riskHigh") "closure changed")
      (assert (only (with (b) :paceFactorPct 50) "paceSoft") "factor under 1")
      (assert (only (with (b) :paceFactorPct 0) "paceHard") "factor 0 is hard, not soft")
      (assert (only (with (b) :usedPct 95) "paceHard") "95 percent used")
      (assert (listEmpty? (t/triggerIds (with (b) :usedPct 94))) "94 percent is quiet")
      (assert (only (with (b) :windowReset true) "windowReset") "window reset")
      true)

fn testLeaseStaleWait -> Bool
  (do (assert (only (with (b) :deadlinePassed true) "leaseExpired") "deadline passed")
      (assert (only (with (b) :pidDead true) "leaseExpired") "pid dead")
      (assert (only (with (b) :mergesBehind 20) "stale") "20 merges behind")
      (assert (listEmpty? (t/triggerIds (with (b) :mergesBehind 19))) "19 merges behind is fresh")
      (assert (only (with (b) :touchedChanged true) "stale") "touched files changed")
      (assert (only (with (b) :cuWaited 21 :maxWait 20) "waitTooLong") "waited more than maxWait")
      (assert (only (with (b) :cuWaited 10 :cuParked 11 :maxWait 20) "waitTooLong") "waited plus parked counts")
      (assert (listEmpty? (t/triggerIds (with (b) :cuWaited 20 :maxWait 20))) "exactly maxWait is not too long")
      (assert (only (with (b) :claudeOnline true) "claudeOnline") "principal online")
      (assert (only (with (b) :claudeAllowance 5) "claudeOnline") "claude allowance above 0")
      (assert (only (with (b) :requestEnded true) "request") "run ended with a request")
      true)

fn testInfra -> Bool
  (let [(rate (with (b) :infraClass "rate" :hasRes true :hasRedBefore false :resAsserts 0 :declaredAsserts 0 :sigCount 3 :ownsOutside true :revertGreen true))]
    (do (assert (only rate "infra") "an infra class suppresses every Res and signature trigger")
        (assert (stringContains? (act rate) "excluded from signatures") "infra action says it is excluded")
        (assert (not (has (with rate :sigCount 2) "sig2")) "sig2 never fires on infra")
        (assert (has (with rate :deadlinePassed true) "leaseExpired") "lease facts still fire beside infra")
        (assert (has (with rate :deadlinePassed true) "infra") "infra stays first")
        (assert (has (with (b) :hasRes true :resAsserts 0 :declaredAsserts 0 :sigCount 3) "sig3") "without the infra class the same facts fire")
        true))

fn ! runTests -> Bool
  (do (assert (testQuiet) "quiet")
      (assert (testResRows) "res rows")
      (assert (testSignatures) "signatures")
      (assert (testLadderRiskPace) "ladder risk pace")
      (assert (testLeaseStaleWait) "lease stale wait")
      (assert (testInfra) "infra exclusion")
      true)
