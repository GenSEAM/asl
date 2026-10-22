(module asl-cli/tests/cliCommandsTest :x [runTests] :i [(cli :a c)])

fn testCannedCommandsNotImplemented! -> Bool
  (do
    (match (c/dispatchCmd "tool" (list))
      ((err msg) (assert (stringContains? msg "ERR_NOT_IMPLEMENTED") "tool returns ERR_NOT_IMPLEMENTED"))
      ((ok _) (assert false "tool must not return canned ok")))
    (match (c/dispatchCmd "launch" (list))
      ((err msg) (assert (stringContains? msg "ERR_NOT_IMPLEMENTED") "launch returns ERR_NOT_IMPLEMENTED"))
      ((ok _) (assert false "launch must not return canned ok")))
    (match (c/dispatchCmd "chk" (list))
      ((err msg) (assert (stringContains? msg "ERR_NOT_IMPLEMENTED") "chk returns ERR_NOT_IMPLEMENTED"))
      ((ok _) (assert false "chk must not return ok")))
    (match (c/dispatchCmd "where" (list))
      ((err msg) (assert (stringContains? msg "ERR_NOT_IMPLEMENTED") "where returns ERR_NOT_IMPLEMENTED"))
      ((ok _) (assert false "where must not return ok")))
    (match (c/dispatchCmd "conform" (list))
      ((err msg) (assert (stringContains? msg "ERR_NOT_IMPLEMENTED") "conform returns ERR_NOT_IMPLEMENTED"))
      ((ok _) (assert false "conform must not return canned ok")))
    (match (c/dispatchCmd "ir" (list))
      ((err msg) (assert (stringContains? msg "ERR_NOT_IMPLEMENTED") "ir returns ERR_NOT_IMPLEMENTED"))
      ((ok _) (assert false "ir must not return canned ok")))
    true)

fn testCmdRunDiagnostics! -> Bool
  (let [(res (c/dispatchCmd "run" (list "asl/packages/asl-cli/tests/fixtures/typeBad.asl")))]
    (assert (err? res) "cmdRun on typeBad must fail")
    (match res
      ((ok _) (assert false "cmdRun on typeBad must not return ok"))
      ((err msg)
       (do
         (assert (stringContains? msg "typeBad.asl:") "cmdRun error includes path and position")
         (assert (stringContains? msg "type") "cmdRun error includes diagnostic code")
         (assert (stringContains? msg "expected Int64, found String") "cmdRun error includes diagnostic detail"))))
    true)

fn testCmdRunExecutesMain! -> Bool
  (let [(res (c/dispatchCmd "run" (list "asl/packages/asl-cli/tests/fixtures/runMe.asl")))]
    (match res
      ((ok stdoutStr) (assert (stringContains? stdoutStr "RUN_OUTPUT_MARKER") "cmdRun executed main and produced stdout"))
      ((err e) (assert false (str "cmdRun failed with: " e))))
    true)

fn testCmdTestNoEntryDiagnostics! -> Bool
  (let [(res (c/dispatchCmd "test" (list "asl/packages/asl-cli/tests/fixtures/noEntry.asl")))]
    (assert (err? res) "cmdTest on noEntry must fail")
    (match res
      ((ok _) (assert false "cmdTest on noEntry must not return ok"))
      ((err msg)
       (do
         (assert (stringContains? msg "noEntry.asl") "cmdTest error includes the path")
         (assert (stringContains? msg "ERR_NO_ENTRY") "cmdTest error includes diagnostic code"))))
    true)

fn testCmdTestZeroAssertsFails! -> Bool
  (let [(res (c/dispatchCmd "test" (list "asl/packages/asl-cli/tests/fixtures/noAsserts.asl")))]
    (assert (err? res) "cmdTest on zero asserts must fail")
    (match res
      ((ok _) (assert false "cmdTest on zero asserts must not pass"))
      ((err msg) (assert (stringContains? msg "zero assertions") "cmdTest reports zero assertions failure")))
    true)

fn testCmdTestExecutionPasses! -> Bool
  (let [(res (c/dispatchCmd "test" (list "asl/packages/asl-cli/tests/fixtures/testOk.asl")))]
    (assert (ok? res) "cmdTest on testOk must succeed")
    (match res
      ((ok out)
       (do
         (assert (stringContains? out "assertion(s) executed") "cmdTest reports executed assertions")
         (assert (stringContains? out "passed") "cmdTest reports passed")))
      ((err e) (assert false (str "cmdTest testOk failed: " e))))
    true)

fn testCmdTestNoDocPasses! -> Bool
  (let [(res (c/dispatchCmd "test" (list "asl/packages/asl-cli/tests/fixtures/testNoDoc.asl")))]
    (assert (ok? res) "cmdTest on passing test without :d must succeed")
    (match res
      ((ok out)
       (do
         (assert (stringContains? out "assertion(s) executed") "reports executed assertions")
         (assert (stringContains? out "1 passed") "reports 1 passed")))
      ((err e) (assert false (str "cmdTest on testNoDoc failed: " e))))
    true)

fn testCmdRunWithDifferentWorkingDirectory! -> Bool
  (let [(procRes (processRun "cd asl/packages/asl-cli && ../../../bin/asl eval '(+ 20 22)'"))]
    (assert (= procRes.exitCode 0) "cli eval from subdirectory must succeed")
    (assert (stringContains? procRes.stdout "42") "cli eval from subdirectory produces 42")
    true)

fn testCmdRunFromSubdirectoryExecutesMain! -> Bool
  (let [(procRes (processRun "cd asl/packages/asl-cli && ../../../bin/asl run tests/fixtures/runMe.asl"))]
    (assert (= procRes.exitCode 0) "cli run from subdirectory must exit 0")
    (assert (stringContains? procRes.stdout "RUN_OUTPUT_MARKER") "cli run from subdirectory shows main ran")
    true)

fn testCmdTestFromSubdirectory! -> Bool
  (let [(okRes (processRun "cd asl/packages/asl-cli && ../../../bin/asl test tests/fixtures/testOk.asl"))
        (badRes (processRun "cd asl/packages/asl-cli && ../../../bin/asl test tests/fixtures/noAsserts.asl"))]
    (assert (= okRes.exitCode 0) "cli test on testOk from subdirectory must exit 0")
    (assert (stringContains? okRes.stdout "assertion(s) executed") "cli test on testOk reports executed assertions")
    (assert (not (= badRes.exitCode 0)) "cli test on noAsserts from subdirectory must exit non-zero")
    (assert (stringContains? (str badRes.stdout badRes.stderr) "zero assertions") "cli test on noAsserts reports zero assertions")
    true)

fn testCmdEvalFromTmp! -> Bool
  (let [(pwdRes (processRun "pwd -P"))
        (root (stringTrim pwdRes.stdout))
        (binAsl (str root "/bin/asl"))
        (cmd (str "cd /tmp && '" binAsl "' eval '(+ 20 22)'"))
        (procRes (processRun cmd))]
    (assert (= pwdRes.exitCode 0) "pwd -P from repo root must succeed")
    (assert (= procRes.exitCode 0) (str "cli eval from /tmp must exit 0: " procRes.stdout procRes.stderr))
    (assert (stringContains? procRes.stdout "42") "cli eval from /tmp prints 42")
    true)

fn testCheckDispatchUnknownSymbol! -> Bool
  (let [(res (c/dispatchCmd "check" (list "asl/packages/asl-cli/tests/fixtures/unknownSym.asl")))]
    (assert (err? res) "check on unknownSym must fail")
    (match res
      ((ok _) (assert false "check on unknownSym must not return ok"))
      ((err msg)
       (do
         (assert (stringContains? msg "unknownSym.asl:") "check error includes path and position")
         (assert (stringContains? msg "unknownVariable") "check error mentions undefined symbol"))))
    true)

fn testCheckDispatchCleanNoDoc! -> Bool
  (let [(res (c/dispatchCmd "check" (list "asl/packages/asl-cli/tests/fixtures/cleanNoDoc.asl")))]
    (assert (ok? res) "check on clean file without doc must pass")
    (match res
      ((ok msg)
       (do
         (refute (stringContains? msg "rule-8") "check reports no rule-8: docs live in doc.asn (D158)")
         (assert (stringContains? msg "cleanNoDoc.asl") "check output includes path")))
      ((err e) (assert false (str "check on cleanNoDoc failed: " e))))
    true)

fn ! runTests -> Bool
  (and (testCannedCommandsNotImplemented!)
  (and (testCmdRunDiagnostics!)
  (and (testCmdRunExecutesMain!)
  (and (testCmdTestNoEntryDiagnostics!)
  (and (testCmdTestZeroAssertsFails!)
  (and (testCmdTestExecutionPasses!)
  (and (testCmdTestNoDocPasses!)
  (and (testCmdRunWithDifferentWorkingDirectory!)
  (and (testCmdRunFromSubdirectoryExecutesMain!)
  (and (testCmdTestFromSubdirectory!)
  (and (testCmdEvalFromTmp!)
  (and (testCheckDispatchUnknownSymbol!)
       (testCheckDispatchCleanNoDoc!)))))))))))))
