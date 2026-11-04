(module asl/tools/coord/tests/briefTest
  :x [runTests]
  :i [(asl-tools/coord/brief :a b)])

; (:m :ref COND-TASK-SPEC :do "the brief on fake owned states: a missing file is told to be created with one write and loses the size advice, an existing one gets its line count, module names derive from the path (asl-utils unit gives asl-utils/NAME, never asl-text), and no owned paths leaves the text alone")
fn testModules -> Bool
  (do (assert (= (b/moduleOfPath "asl/packages/asl-utils/src/textdiff.asl") "asl-utils/textdiff") "package src path")
      (assert (= (b/moduleOfPath "asl/tools/coord/throughput.asl") "asl-tools/coord/throughput") "tools path, not the module name as a path")
      (assert (= (b/moduleOfPath "tools/remote/nodeWatch.asl") "tools/remote/nodeWatch") "plain path")
      (assert (= (b/moduleOfPath "asl/tools/coord/tests/x.asn") "") "non asl has no module")
      true)

fn testBrief -> Bool
  (let [(task "Add the module.\nSMALL EDITS ONLY in large files.\nRun the gate.")
        (miss (b/briefFor task (list (pair "asl/packages/asl-utils/src/textdiff.asl" -1))))
        (have (b/briefFor task (list (pair "asl/tools/coord/risk.asl" 120))))
        (none (b/briefFor task (list)))]
    (do (assert (stringContains? miss "asl/packages/asl-utils/src/textdiff.asl: missing, create it with one write; module asl-utils/textdiff") (str "missing fact: " miss))
        (assert (not (stringContains? miss "SMALL EDITS ONLY")) "size advice dropped for a missing file")
        (assert (stringContains? miss "Run the gate.") "other task lines kept")
        (assert (stringContains? have "asl/tools/coord/risk.asl: exists (120 lines); module asl-tools/coord/risk") (str "existing fact: " have))
        (assert (stringContains? have "SMALL EDITS ONLY") "size advice kept when every owned file exists")
        (assert (= none task) "no owned paths leaves the text")
        true))

fn ! runTests -> Bool
  (do (assert (testModules) "module names derive from paths")
      (assert (testBrief) "owned states in the brief")
      true)
