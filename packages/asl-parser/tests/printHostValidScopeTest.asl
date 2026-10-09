(module asl-parser/tests/printHostValidScopeTest
  :x [runTests]
  :i [(asl-parser/tests/printReparseLib :a prl)
      (asl-parser/tests/printHostValidScope :a scope)])

fn ! missingScopePaths -> (List String)
  (filter (fn [(p String)] (err? (fileStat p))) (listAppend (scope/knownSourceInvalidPaths) (scope/intentionallyRejectedPaths)))

fn ! runTests -> Bool
  (do
    (assert (listEmpty? (missingScopePaths)) (str "knownSourceInvalidPaths names only existing files, missing: " (stringJoin (missingScopePaths) " ")))
    (assert (prl/isPrintReparseFile! "tests/acceptance/r1Host/check/acyclicControlTest.asl") "valid recursive top-level control fixture remains in scope")
    (assert (not (prl/isPrintReparseFile! "tests/acceptance/r1Host/check/letrecSelfTest.asl")) "self-recursion rejection fixture opts out")
    (assert (not (prl/isPrintReparseFile! "tests/acceptance/r1Host/check/letrecValueTest.asl")) "captured-binding rejection fixture opts out")
    (assert (not (prl/isPrintReparseFile! "tests/acceptance/r1Host/check/letrecLaterTest.asl")) "later-binding rejection fixture opts out")
    (assert (not (prl/isPrintReparseFile! "tests/acceptance/r1Host/sem/invalid/letLiteralTest.asl")) "semantic-invalid directory stays out of scope")
    true)
