(module aslAgent/tests/toolRootRowsTest
  :x [runTests]
  :i [(aslAgent/aslOps :a o)])

; (:m :ref LEON-STEP-BODY-LOST :do "the env a jailed asl call builds names the tool root of the aslBin it runs, never an inherited ASL_CLI_ROOT of another tree; nothing is run")
fn ! runTests -> Bool
  (let [base (str (optionOr (envGet "TMPDIR") "/tmp") "/toolRootRows" (stringFromInt64 (monotonicNs)))
        made (ok? (dirCreate (str base "/tool/bin")))
        real (resultOr (realPath (str base "/tool")) (str base "/tool"))
        given (list "PATH=/usr/bin:/bin" "ASL_CLI_ROOT=/elsewhere/tree" "LANG=C")
        rows (o/toolRootRows! (str base "/tool/bin/asl") given)
        other (o/toolRootRows! "/usr/local/bin/aslx" given)
        cleaned (ok? (pathRemove base))]
    (do
      (assert (and made (and (listContains? rows (str "ASL_CLI_ROOT=" real)) (not (listContains? rows "ASL_CLI_ROOT=/elsewhere/tree")))) (str "the rows name the real tool root of ROOT/bin/asl in place of the inherited one: " (stringJoin rows " ")))
      (assert (and (listContains? rows "PATH=/usr/bin:/bin") (listContains? rows "LANG=C")) "the other rows stay")
      (assert (= other given) "an aslBin that is not ROOT/bin/asl leaves the rows as given")
      (assert cleaned "the fixture directory was removed")
      true))
