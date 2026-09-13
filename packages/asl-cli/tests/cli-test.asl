(module asl-cli/test
  :d "Unit tests for pure AgentScript CLI dispatcher."
  :x [testVersion
      testHelp
      testDispatchVersion
      testDispatchGate
      testDispatchUnknown
      testDispatchMissing
      testDispatchEval
      testDispatchTest
      testDispatchRpc
      runTests
      RunTests]
  :i [(cli :a c)])

(df testVersion [] -> Bool
  :d "Verifies format-version outputs canonical string."
  (do
    (assert (string-contains? (c/formatVersion) "asl 0.1.0") "c-cli-pos-001: format-version contains asl 0.1.0")
    (refute (string-contains? (c/formatVersion) "error") "c-cli-neg-001: format-version has no error")
    true))

(df testHelp [] -> Bool
  :d "Verifies format-help contains usage commands."
  (do
    (assert (string-contains? (c/formatHelp) "Usage: asl") "c-cli-pos-002: format-help contains usage")
    (assert (string-contains? (c/formatHelp) "rpc '(:batch ...)'") "c-cli-pos-002: format-help contains rpc")
    (assert (string-contains? (c/formatHelp) "check <file>") "c-cli-pos-002: format-help contains check")
    (assert (string-contains? (c/formatHelp) "build <file>") "c-cli-pos-002: format-help contains build")
    (refute (string-contains? (c/formatHelp) "invalid-cmd-xyz") "c-cli-neg-002: format-help has no invalid cmd")
    true))

(df ! testDispatchVersion [] -> Bool
  :d "Verifies dispatch-cmd handles version."
  (do
    (mt (c/dispatchCmd "version" (list))
      ((ok ver) (assert (string-contains? ver "0.1.0") "c-cli-pos-003: version dispatch ok"))
      ((err _) (assert false "c-cli-neg-003: version dispatch failed")))
    (mt (c/dispatchCmd "version-xyz" (list))
      ((ok _) (assert false "c-cli-neg-003: invalid version dispatched"))
      ((err errMsg) (assert (string-contains? errMsg "Unknown command") "c-cli-neg-003: invalid version rejected")))
    true))

(df ! testDispatchGate [] -> Bool
  :d "Verifies dispatch-cmd gate processes file list."
  (do
    (mt (c/dispatchCmd "gate" (list "asl/packages/asl-cli/src/cli.asl"))
      ((ok msg) (assert (string-contains? msg "verified cleanly") "c-cli-pos-004: gate dispatch ok"))
      ((err _) (assert false "c-cli-neg-004: gate dispatch failed")))
    (mt (c/dispatchCmd "gate" (list "non-existent-gate-file-xyz.asl"))
      ((ok _) (assert false "c-cli-neg-004: missing gate file should fail"))
      ((err msg) (assert (string-contains? msg "Failed to read gate target file") "c-cli-neg-004: missing file rejected")))
    (mt (c/dispatchCmd "gate" (list))
      ((ok _) (assert false "c-cli-neg-004: empty gate args should fail"))
      ((err errMsg) (assert (string-contains? errMsg "Usage: asl gate") "c-cli-neg-004: empty gate rejected")))
    true))

(df ! testDispatchUnknown [] -> Bool
  :d "Verifies dispatch-cmd rejects unknown subcommands."
  (do
    (mt (c/dispatchCmd "non-existent-command-xyz" (list))
      ((ok _) (assert false "c-cli-neg-005: unknown command should fail"))
      ((err msg) (assert (string-contains? msg "Unknown command") "c-cli-neg-005: unknown command error")))
    (mt (c/dispatchCmd "help" (list))
      ((ok helpMsg) (assert (string-contains? helpMsg "Usage: asl") "c-cli-pos-005: help command known"))
      ((err _) (assert false "c-cli-pos-005: help rejected")))
    true))

(df ! testDispatchMissing [] -> Bool
  :d "Verifies dispatch-cmd demands file argument."
  (do
    (mt (c/dispatchCmd "check" (list))
      ((ok _) (assert false "c-cli-neg-006: missing check arg should fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl check") "c-cli-neg-006: usage returned")))
    (mt (c/dispatchCmd "check" (list "test.asl"))
      ((ok chkMsg) (assert (or (string-contains? chkMsg "passed cleanly") (string-contains? chkMsg "verified cleanly")) "c-cli-pos-006: check with arg handled"))
      ((err chkErr) (assert (not (string-empty? chkErr)) "c-cli-pos-006: check error reported")))
    true))

(df ! testDispatchEval [] -> Bool
  :d "Verifies dispatch-cmd eval evaluates expressions cleanly."
  (do
    (mt (c/dispatchCmd "eval" (list "(+ 10 20)"))
      ((ok res) (assert (= res "30") "c-cli-pos-007: eval calculation 30"))
      ((err _) (assert false "c-cli-pos-007: eval failed")))
    (mt (c/dispatchCmd "eval" (list))
      ((ok _) (assert false "c-cli-neg-007: empty eval should fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl eval") "c-cli-neg-007: empty eval usage returned")))
    true))

(df ! testDispatchTest [] -> Bool
  :d "Verifies dispatch-cmd test validates args and missing files."
  (do
    (mt (c/dispatchCmd "test" (list))
      ((ok _) (assert false "c-cli-neg-008: empty test args should fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl test") "c-cli-neg-008: empty test usage returned")))
    (mt (c/dispatchCmd "test" (list "non-existent-test-file-xyz.asl"))
      ((ok _) (assert false "c-cli-neg-008: missing test file should fail"))
      ((err msg) (assert (string-contains? msg "Failed to read test file") "c-cli-neg-008: missing file error returned")))
    true))

(df ! testDispatchRpc [] -> Bool
  :d "Verifies dispatch-cmd rpc executes batch envelopes."
  (do
    (mt (c/dispatchCmd "rpc" (list))
      ((ok _) (assert false "c-cli-neg-009: empty rpc must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl rpc '(:batch ...)'") "c-cli-neg-009: empty rpc usage returned")))
    (mt (c/dispatchCmd "rpc" (list "(:batch (:echo :message \"hello-rpc\"))"))
      ((ok res)
       (do
         (assert (string-contains? res ":batch-res") "c-cli-pos-009: rpc has batch-res")
         (assert (string-contains? res "hello-rpc") "c-cli-pos-009: message echoed")
         (refute (string-contains? res ":status \"failed\"") "c-cli-pos-009: not failed")))
      ((err _) (assert false "c-cli-neg-009: rpc echo should succeed")))
    (mt (c/dispatchCmd "(:batch (:echo :message \"hello-direct\"))" (list))
      ((ok res)
       (do
         (assert (string-contains? res ":batch-res") "c-cli-pos-010: direct shorthand has batch-res")
         (assert (string-contains? res "hello-direct") "c-cli-pos-010: direct message echoed")
         (refute (string-contains? res "Unknown command") "c-cli-pos-010: shorthand known")))
      ((err _) (assert false "c-cli-neg-010: shorthand should succeed")))
    (mt (c/dispatchCmd "rpc" (list "(:batch (:echo :message \"first\") (:echo :message \"second\"))"))
      ((ok res)
       (do
         (assert (string-contains? res ":itemsCount 2") "c-cli-pos-011: multi-step itemsCount 2")
         (assert (string-contains? res "first") "c-cli-pos-011: first step present")
         (assert (string-contains? res "second") "c-cli-pos-011: second step present")))
      ((err _) (assert false "c-cli-neg-011: multi-step should succeed")))
    true))

(df ! runTests [] -> Bool
  :d "Executes all pure ASL CLI test cases."
  (do
    (assert (testVersion) "test-version pass")
    (assert (testHelp) "test-help pass")
    (assert (testDispatchVersion) "test-dispatch-version pass")
    (assert (testDispatchGate) "test-dispatch-gate pass")
    (assert (testDispatchUnknown) "test-dispatch-unknown pass")
    (assert (testDispatchMissing) "test-dispatch-missing pass")
    (assert (testDispatchEval) "test-dispatch-eval pass")
    (assert (testDispatchTest) "test-dispatch-test pass")
    (assert (testDispatchRpc) "test-dispatch-rpc pass")
    true))

(df ! RunTests [] -> Bool
  :d "Capitalized test entry for automated test framework."
  (runTests))
