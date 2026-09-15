(module asl-cli/tests/cliTest
  :d "Unit tests for pure AgentScript CLI main entrypoint and dispatcher."
  :x [testMainDispatch
      testVersionOutput
      testHelpOutput
      testSubcommandsDispatch
      testEvalDispatch
      testRpcDispatch
      runTests]
  :i [(main :a m)
      (cli :a c)])

(df ! testMainDispatch [] -> Bool
  :d "Asserts command line argument dispatching through main module."
  (do
    (mt (m/dispatch (list "version"))
      ((ok _) (assert (> (string-length (c/formatVersion)) 0) "version dispatch ok"))
      ((err _) (assert false "version dispatch should succeed")))
    (mt (m/dispatch (list "help"))
      ((ok _) (assert (> (string-length (c/formatHelp)) 0) "help dispatch ok"))
      ((err _) (assert false "help dispatch should succeed")))
    (mt (m/dispatch (list "invalid-command-xyz"))
      ((ok _) (assert false "invalid command should fail"))
      ((err msg)
       (do
         (assert (string-contains? msg "Unknown command") "invalid command reported")
         (refute (string-contains? msg ":batch-res") "invalid command is not batch"))))
    true))

(df testVersionOutput [] -> Bool
  :d "Asserts canonical version string output formatting."
  (let [(ver (c/formatVersion))]
    (assert (string-contains? ver "asl 0.1.0") "format-version must contain version")
    (refute (string-contains? ver "error") "format-version must not contain error")
    true))

(df testHelpOutput [] -> Bool
  :d "Asserts command line help manual formatting and options."
  (let [(hlp (c/formatHelp))]
    (assert (string-contains? hlp "Usage: asl") "help must contain usage")
    (assert (string-contains? hlp "rpc '(:batch ...)'") "help must contain rpc")
    (assert (string-contains? hlp "check <file>") "help must contain check")
    (assert (string-contains? hlp "build <file>") "help must contain build")
    (refute (string-contains? hlp "invalid-help-xyz") "help has no garbage")
    true))

(df ! testSubcommandsDispatch [] -> Bool
  :d "Asserts dispatching of language toolchain subcommands."
  (do
    (mt (c/dispatchCmd "check" (list))
      ((ok _) (assert false "empty check must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl check") "empty check returns usage")))
    (mt (c/dispatchCmd "gate" (list "asl/packages/asl-cli/src/cli.asl"))
      ((ok msg) (assert (string-contains? msg "verified cleanly") "gate with file ok"))
      ((err errMsg) (assert false (str "gate with file should succeed, error was: " errMsg))))
    (mt (c/dispatchCmd "gate" (list "non-existent-gate-target.asl"))
      ((ok _) (assert false "gate with non-existent file must fail"))
      ((err msg) (assert (string-contains? msg "Failed to read gate target file") "missing gate file reported")))
    (mt (c/dispatchCmd "gate" (list))
      ((ok _) (assert false "empty gate must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl gate") "empty gate returns usage")))
    (mt (c/dispatchCmd "test" (list))
      ((ok _) (assert false "empty test must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl test") "empty test returns usage")))
    true))

(df ! testEvalDispatch [] -> Bool
  :d "Asserts inline expression evaluation dispatch and math results."
  (do
    (mt (c/dispatchCmd "eval" (list "(+ 40 2)"))
      ((ok res) (assert (= res "42") "eval (+ 40 2) = 42"))
      ((err _) (assert false "eval should succeed")))
    (mt (c/dispatchCmd "eval" (list "(* 6 7)"))
      ((ok res) (assert (= res "42") "eval multiply should succeed")))
    (mt (c/dispatchCmd "eval" (list))
      ((ok _) (assert false "empty eval must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl eval") "empty eval returns usage")))
    true))

(df ! testRpcDispatch [] -> Bool
  :d "Asserts dispatching of RPC batch commands and shorthands."
  (do
    (mt (c/dispatchCmd "rpc" (list))
      ((ok _) (assert false "empty rpc must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl rpc '(:batch ...)'") "empty rpc returns usage")))
    (mt (c/dispatchCmd "rpc" (list "(:batch (:echo :message \"cli-test-echo\"))"))
      ((ok res)
       (do
         (assert (string-contains? res ":batch-res") "rpc result has :batch-res")
         (assert (string-contains? res "cli-test-echo") "rpc result has echoed message")
         (refute (string-contains? res ":status \"failed\"") "rpc result not failed")))
      ((err _) (assert false "rpc with echo should succeed")))
    (mt (c/dispatchCmd "(:batch (:echo :message \"shorthand-test\"))" (list))
      ((ok res)
       (do
         (assert (string-contains? res ":batch-res") "shorthand has :batch-res")
         (assert (string-contains? res "shorthand-test") "shorthand has message")
         (refute (string-contains? res "Unknown command") "shorthand recognized")))
      ((err _) (assert false "shorthand should succeed")))
    (mt (c/dispatchCmd "rpc" (list "(:batch (:echo :message \"m1\") (:echo :message \"m2\"))"))
      ((ok res)
       (do
         (assert (string-contains? res ":itemsCount 2") "multi-step has itemsCount 2")
         (assert (string-contains? res "m1") "multi-step has m1")
         (assert (string-contains? res "m2") "multi-step has m2")))
      ((err _) (assert false "multi-step should succeed")))
    true))

(df ! runTests [] -> Bool
  :d "Master test runner executing all pure ASL CLI test suites."
  (and (testMainDispatch)
       (and (testVersionOutput)
            (and (testHelpOutput)
                 (and (testSubcommandsDispatch)
                      (and (testEvalDispatch)
                           (testRpcDispatch)))))))
