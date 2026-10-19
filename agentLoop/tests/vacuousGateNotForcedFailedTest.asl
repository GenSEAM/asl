(module asl/agentLoop/tests/vacuousGateNotForcedFailedTest
  :x [runTests]
  :i [(asl/agentLoop/gates :a g)])

; (:m :ref LEON-OWNS-ALL-20261018 :do "gates.asl's vacuousOutsideOwns!/findVacuousOutside! used to feed checkOwns the raw, un-normalized owns list, so with :owns left unset a vacuous gate's own command file always looked outside owns -- the existing gatesParityTest coverage for the empty-owns case (testVacuousOutsideOwns!'s res3/res4) only exercised a nonexistent file or an asserted gate, where findFirstFile!/the vacuous check short-circuits before checkOwns is ever reached, so it never caught this. This test uses a vacuous gate (exit 1, no assert output) pointing at bin/asl, which exists, to actually exercise the owns check")

fn ! runTests -> Bool
  (let [vacuous (list (g/makeGateResult "sh bin/asl" 1 "" "" false 0))
        resUnset (g/vacuousOutsideOwns! vacuous (list) ".")
        resNarrowed (g/vacuousOutsideOwns! vacuous (list "some/other/path") ".")]
    (do
      (assert (none? resUnset)
        "a session with no :owns declared may write anywhere inside :root, so a vacuous gate referencing an in-root file (bin/asl) must not be forced-failed as 'outside owns' just because :owns was left unset")
      (match resNarrowed
        ((some p)
          (do
            (assert (= (pairFirst p) "sh bin/asl") "a session that does narrow its owns, and excludes the gate's own file, still gets flagged")
            (assert (= (pairSecond p) "bin/asl") "the flagged file is the gate's own command file")))
        ((none) (assert false "a session that narrows :owns away from bin/asl must still flag it as outside owns")))
      true))
