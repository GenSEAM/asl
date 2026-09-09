(module asl-cli/tests/cli-test
  :d "Unit tests for pure AgentScript CLI main entrypoint and dispatcher."
  :x [test-main-dispatch
      test-version-output
      test-help-output
      test-subcommands-dispatch
      test-eval-dispatch
      run-tests]
  :i [(main :a m)
      (cli :a c)])

(df ! test-main-dispatch [] -> Bool
  :d "Asserts command line argument dispatching through main module."
  (do
    (mt (m/dispatch (list "version"))
      ((ok _) (assert true "version dispatch ok"))
      ((err _) (assert false "version dispatch should succeed")))
    (mt (m/dispatch (list "help"))
      ((ok _) (assert true "help dispatch ok"))
      ((err _) (assert false "help dispatch should succeed")))
    (mt (m/dispatch (list "invalid-command-xyz"))
      ((ok _) (assert false "invalid command should fail"))
      ((err msg) (assert (string-contains? msg "Unknown command") "invalid command reported")))
    true))

(df test-version-output [] -> Bool
  :d "Asserts canonical version string output formatting."
  (let [(ver (c/format-version))]
    (assert (string-contains? ver "asl 0.1.0") "format-version must contain version")
    (assert (not (string-contains? ver "error")) "format-version must not contain error")
    true))

(df test-help-output [] -> Bool
  :d "Asserts command line help manual formatting and options."
  (let [(hlp (c/format-help))]
    (assert (string-contains? hlp "Usage: asl") "help must contain usage")
    (assert (string-contains? hlp "rpc '(:batch ...)'") "help must contain rpc")
    (assert (string-contains? hlp "check <file>") "help must contain check")
    (assert (string-contains? hlp "build <file>") "help must contain build")
    true))

(df ! test-subcommands-dispatch [] -> Bool
  :d "Asserts dispatching of language toolchain subcommands."
  (do
    (mt (c/dispatch-cmd "check" (list))
      ((ok _) (assert false "empty check must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl check") "empty check returns usage")))
    (mt (c/dispatch-cmd "gate" (list "test.asl"))
      ((ok msg) (assert (string-contains? msg "verified cleanly") "gate with file ok"))
      ((err _) (assert false "gate with file should succeed")))
    (mt (c/dispatch-cmd "gate" (list))
      ((ok _) (assert false "empty gate must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl gate") "empty gate returns usage")))
    (mt (c/dispatch-cmd "test" (list))
      ((ok _) (assert false "empty test must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl test") "empty test returns usage")))
    true))

(df ! test-eval-dispatch [] -> Bool
  :d "Asserts inline expression evaluation dispatch and math results."
  (do
    (mt (c/dispatch-cmd "eval" (list "(+ 40 2)"))
      ((ok res) (assert (= res "42") "eval (+ 40 2) = 42"))
      ((err _) (assert false "eval should succeed")))
    (mt (c/dispatch-cmd "eval" (list "(* 6 7)"))
      ((ok res) (assert (= res "42") "eval multiply should succeed")))
    (mt (c/dispatch-cmd "eval" (list))
      ((ok _) (assert false "empty eval must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl eval") "empty eval returns usage")))
    true))

(df ! run-tests [] -> Bool
  :d "Master test runner executing all pure ASL CLI test suites."
  (and (test-main-dispatch)
       (and (test-version-output)
            (and (test-help-output)
                 (and (test-subcommands-dispatch)
                      (test-eval-dispatch))))))
