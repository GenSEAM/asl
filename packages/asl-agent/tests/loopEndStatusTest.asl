(module aslAgent/tests/loopEndStatusTest
  :x [runTests]
  :i [(aslAgent/loop :a lp)])

; (:m :ref ENDSTATUS-FALSEFAIL :do "a patch delivery with leftover non-claim findings (e.g. a stray reply fragment mis-parsed as a data op on an earlier turn) must not downgrade an otherwise-ok, gate-passing, gateIntegrity-passing run to failed; only a findings/scout delivery requires a backing claim")

fn runTests -> Bool
  (do
    (assert (= (lp/endStatus "ok" "patch" true false) "ok")
      "patch delivery with findings but no claim keeps ok (ENDSTATUS-FALSEFAIL)")
    (assert (= (lp/endStatus "ok" "patch" false false) "ok")
      "patch delivery with no findings at all stays ok")
    (assert (= (lp/endStatus "ok" "patch" true true) "ok")
      "patch delivery with findings and a claim stays ok")
    (assert (= (lp/endStatus "ok" "findings" true false) "failed")
      "findings delivery with findings but no claim still downgrades to failed")
    (assert (= (lp/endStatus "ok" "findings" true true) "ok")
      "findings delivery with a claim stays ok")
    (assert (= (lp/endStatus "ok" "findings" false false) "ok")
      "findings delivery with no findings and no claim stays ok (nothing to back)")
    (assert (= (lp/endStatus "ok" "" true false) "failed")
      "an empty/absent deliver (scout mode with no patch) still downgrades on an unclaimed finding")
    (assert (= (lp/endStatus "ok" "" false false) "ok")
      "an empty/absent deliver with no findings at all stays ok")
    (assert (= (lp/endStatus "failed" "patch" true false) "failed")
      "an already-failed status is unaffected by findings/claim")
    (assert (= (lp/endStatus "escalated" "findings" true false) "escalated")
      "an escalated status is unaffected by findings/claim")
    (assert (= (lp/finalOutcome "ok" "patch" true false 2 3) "ok|5")
      "finalOutcome keeps ok for patch delivery and sums the unbacked counts")
    (assert (= (lp/finalOutcome "ok" "findings" true false 0 0) "failed|0")
      "finalOutcome still downgrades findings delivery lacking a claim")
    true)
