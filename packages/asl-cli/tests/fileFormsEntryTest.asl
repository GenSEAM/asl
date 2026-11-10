(module asl-cli/tests/fileFormsEntryTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a run)])

; (:m :ref ASL-STDIN-EDIT-HANG :do "asl -f FILE ran its forms through command.asl, whose forms! spawned asl run asl-forms/main.asl, a source compile that never ends (100 percent CPU) for every file, edit forms with escaped quotes included; the native entry now dispatches the file's forms itself like asl -. Run under a 40 s bound, so the old build ends on the bound and fails")
fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/fileFormsEntryTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! cli! binary: String root: String args: (List String) -> run/Done
  (run/runOneLimited (run/job (cons binary args) root (list "PATH=/usr/bin:/bin" (str "HOME=" root) "TMPDIR=/tmp" (str "ASL_ROOT=" root) (str "ASL_CLI_ROOT=" root))) (run/limits 40 16))

fn probeSource -> String
  "(module probe/esc :x [runTests] :i [])\n\nfn runTests -> Bool\n  (stringContains? \"card\" \"x\\\"y\\\"z\")\n"

fn editForms -> String
  "(:edit :file \"esc.asl\" :old \"(stringContains? \\\"card\\\" \\\"x\\\\\\\"y\\\\\\\"z\\\")\" :new \"(stringContains? \\\"card\\\" \\\"p\\\\\\\"q\\\")\")\n"

fn ! runTests -> Bool
  (let [(base (scratchBase!))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)))
        (made (dirCreate base))
        (w1 (fileWrite (str base "/esc.asl") (probeSource)))
        (w2 (fileWrite (str base "/edit.forms") (editForms)))
        (w3 (fileWrite (str base "/read.forms") "(:read :file \"esc.asl\" :symbol \"runTests\")\n"))]
    (do
      (assert (some? built.binary) (str "native.asl builds natively: " built.reason))
      (assert (and (ok? made) (and (ok? w1) (and (ok? w2) (ok? w3)))) "fixture files written")
      (let [(binary (optionOr built.binary ""))
            (rd (cli! binary base (list "-f" (str base "/read.forms"))))
            (ed (cli! binary base (list "-f" (str base "/edit.forms"))))
            (bad (cli! binary base (list "-f" (str base "/missing.forms"))))
            (removed (pathRemove base))]
        (do
          (assert (= rd.verdict "exit") (str "asl -f with a read form ends on its own, not on the bound: " rd.out))
          (assert (and (= rd.exit 0) (stringContains? rd.out ":symbol \"runTests\"")) (str "asl -f read form answers: " rd.out))
          (assert (= ed.verdict "exit") (str "asl -f with an escaped-quote edit form ends on its own, not on the bound: " ed.out))
          (assert (and (= ed.exit 0) (stringContains? ed.out "(:edit ")) (str "asl -f edit form answers an :edit receipt: " ed.out))
          (refute (stringContains? ed.out ":status :rejected") (str "the escaped-quote edit matches: " ed.out))
          (assert (and (= bad.verdict "exit") (and (= bad.exit 2) (stringContains? bad.out "ERR_MISSING_ARG"))) (str "asl -f with a missing file is a usage error: " bad.out))
          (assert (ok? removed) "scratch tree removed")
          true))))
