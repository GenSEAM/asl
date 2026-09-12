(module asl-cli/test
  :d "Unit tests for pure AgentScript CLI dispatcher."
  :x [test-version test-help test-dispatch-version test-dispatch-gate test-dispatch-unknown test-dispatch-missing test-dispatch-eval test-dispatch-test run-tests]
  :i [(cli :a c)])

(df test-version [] -> Bool
  :d "Verifies format-version outputs canonical string."
  (do
    (assert (string-contains? (c/format-version) "asl 0.1.0") "c-cli-pos-001: format-version contains asl 0.1.0")
    (assert (not (string-contains? (c/format-version) "error")) "c-cli-neg-001: format-version has no error")
    true))

(df test-help [] -> Bool
  :d "Verifies format-help contains usage commands."
  (do
    (assert (string-contains? (c/format-help) "Usage: asl") "c-cli-pos-002: format-help contains usage")
    (assert (string-contains? (c/format-help) "check <file>") "c-cli-pos-002: format-help contains check")
    (assert (string-contains? (c/format-help) "build <file>") "c-cli-pos-002: format-help contains build")
    (assert (not (string-contains? (c/format-help) "invalid-cmd-xyz")) "c-cli-neg-002: format-help has no invalid cmd")
    true))

(df ! test-dispatch-version [] -> Bool
  :d "Verifies dispatch-cmd handles version."
  (do
    (mt (c/dispatch-cmd "version" (list))
      ((ok ver) (assert (string-contains? ver "0.1.0") "c-cli-pos-003: version dispatch ok"))
      ((err _) (assert false "c-cli-neg-003: version dispatch failed")))
    (mt (c/dispatch-cmd "version-xyz" (list))
      ((ok _) (assert false "c-cli-neg-003: invalid version dispatched"))
      ((err err-msg) (assert (string-contains? err-msg "Unknown command") "c-cli-neg-003: invalid version rejected")))
    true))

(df ! test-dispatch-gate [] -> Bool
  :d "Verifies dispatch-cmd gate processes file list."
  (do
    (mt (c/dispatch-cmd "gate" (list "test.asl"))
      ((ok msg) (assert (string-contains? msg "verified cleanly") "c-cli-pos-004: gate dispatch ok"))
      ((err _) (assert false "c-cli-neg-004: gate dispatch failed")))
    (mt (c/dispatch-cmd "gate" (list))
      ((ok _) (assert false "c-cli-neg-004: empty gate args should fail"))
      ((err err-msg) (assert (string-contains? err-msg "Usage: asl gate") "c-cli-neg-004: empty gate rejected")))
    true))

(df ! test-dispatch-unknown [] -> Bool
  :d "Verifies dispatch-cmd rejects unknown subcommands."
  (do
    (mt (c/dispatch-cmd "non-existent-command-xyz" (list))
      ((ok _) (assert false "c-cli-neg-005: unknown command should fail"))
      ((err msg) (assert (string-contains? msg "Unknown command") "c-cli-neg-005: unknown command error")))
    (mt (c/dispatch-cmd "help" (list))
      ((ok help-msg) (assert (string-contains? help-msg "Usage: asl") "c-cli-pos-005: help command known"))
      ((err _) (assert false "c-cli-pos-005: help rejected")))
    true))

(df ! test-dispatch-missing [] -> Bool
  :d "Verifies dispatch-cmd demands file argument."
  (do
    (mt (c/dispatch-cmd "check" (list))
      ((ok _) (assert false "c-cli-neg-006: missing check arg should fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl check") "c-cli-neg-006: usage returned")))
    (mt (c/dispatch-cmd "check" (list "test.asl"))
      ((ok chk-msg) (assert (or (string-contains? chk-msg "passed cleanly") (string-contains? chk-msg "verified cleanly")) "c-cli-pos-006: check with arg handled"))
      ((err chk-err) (assert (not (string-empty? chk-err)) "c-cli-pos-006: check error reported")))
    true))

(df ! test-dispatch-eval [] -> Bool
  :d "Verifies dispatch-cmd eval evaluates expressions cleanly."
  (do
    (mt (c/dispatch-cmd "eval" (list "(+ 10 20)"))
      ((ok res) (assert (= res "30") "c-cli-pos-007: eval calculation 30"))
      ((err _) (assert false "c-cli-pos-007: eval failed")))
    (mt (c/dispatch-cmd "eval" (list))
      ((ok _) (assert false "c-cli-neg-007: empty eval should fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl eval") "c-cli-neg-007: empty eval usage returned")))
    true))

(df ! test-dispatch-test [] -> Bool
  :d "Verifies dispatch-cmd test validates args and missing files."
  (do
    (mt (c/dispatch-cmd "test" (list))
      ((ok _) (assert false "c-cli-neg-008: empty test args should fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl test") "c-cli-neg-008: empty test usage returned")))
    (mt (c/dispatch-cmd "test" (list "non-existent-test-file-xyz.asl"))
      ((ok _) (assert false "c-cli-neg-008: missing test file should fail"))
      ((err msg) (assert (string-contains? msg "Failed to read test file") "c-cli-neg-008: missing file error returned")))
    true))

(df ! run-tests [] -> Bool
  :d "Executes all pure ASL CLI test cases."
  (do
    (assert (test-version) "test-version pass")
    (assert (test-help) "test-help pass")
    (assert (test-dispatch-version) "test-dispatch-version pass")
    (assert (test-dispatch-gate) "test-dispatch-gate pass")
    (assert (test-dispatch-unknown) "test-dispatch-unknown pass")
    (assert (test-dispatch-missing) "test-dispatch-missing pass")
    (assert (test-dispatch-eval) "test-dispatch-eval pass")
    (assert (test-dispatch-test) "test-dispatch-test pass")
    true))
