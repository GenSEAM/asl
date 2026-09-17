(module asl-cli/tests/cliTest
  :d "Unit tests for pure AgentScript CLI main entrypoint and dispatcher."
  :x [testMainDispatch
      testVersionOutput
      testHelpOutput
      testSubcommandsDispatch
      testEvalDispatch
      testRpcDispatch
      testPatchDispatch
      testImpactDispatch
      testWatchDispatch
      testHealDispatch
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

(df ! testPatchDispatch [] -> Bool
  :d "Asserts dispatching of patch command and option validation."
  (do
    (mt (c/dispatchCmd "patch" (list))
      ((ok msg) (assert (string-contains? msg "Usage: asl patch") "empty patch returns usage"))
      ((err _) (assert false "empty patch should return usage string")))
    (mt (c/dispatchCmd "patch" (list "--help"))
      ((ok msg) (assert (string-contains? msg "Usage: asl patch") "patch --help returns usage"))
      ((err _) (assert false "patch --help should succeed")))
    (mt (c/dispatchCmd "patch" (list "--check"))
      ((ok _) (assert false "empty check flag must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl patch --check") "empty check returns usage")))
    (mt (c/dispatchCmd "patch" (list "--apply"))
      ((ok _) (assert false "empty apply flag must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl patch --apply") "empty apply returns usage")))
    (mt (c/dispatchCmd "patch" (list "--unknown-flag"))
      ((ok _) (assert false "unknown flag must fail"))
      ((err msg) (assert (string-contains? msg "Unknown flag") "unknown flag reported")))
    true))

(df ! testImpactDispatch [] -> Bool
  :d "Asserts dispatching of impact command and blast radius analysis."
  (do
    (mt (c/dispatchCmd "impact" (list))
      ((ok msg) (assert (string-contains? msg "Usage: asl impact") "empty impact returns usage"))
      ((err _) (assert false "empty impact should return usage string")))
    (mt (c/dispatchCmd "impact" (list "--help"))
      ((ok msg) (assert (string-contains? msg "Usage: asl impact") "impact --help returns usage"))
      ((err _) (assert false "impact --help should succeed")))
    (mt (c/dispatchCmd "impact" (list "parsePatch"))
      ((ok receipt)
       (do
         (assert (string-contains? receipt ":impact-receipt") "receipt contains :impact-receipt")
         (assert (string-contains? receipt ":symbol \"parsePatch\"") "receipt contains symbol")
         (assert (string-contains? receipt ":callers") "receipt contains callers")
         (assert (string-contains? receipt ":callersCount") "receipt contains callersCount")
         (refute (string-contains? receipt ":line") "Zero-line-number invariant: no line numbers in impact receipt")
         (refute (string-contains? receipt ":col") "Zero-line-number invariant: no col in impact receipt")))
      ((err _) (assert false "impact query should succeed")))
    true))

(df ! testCheckDispatch [] -> Bool
  :d "Asserts dispatching of check command with self-healing and fix options."
  (do
    (mt (c/dispatchCmd "check" (list))
      ((ok msg) (assert (string-contains? msg "Usage: asl check") "empty check returns usage"))
      ((err msg) (assert (string-contains? msg "Usage: asl check") "empty check returns usage error")))
    (mt (c/dispatchCmd "check" (list "--help"))
      ((ok msg)
       (do
         (assert (string-contains? msg "Usage: asl check") "check --help returns usage")
         (assert (string-contains? msg "--fix") "check --help displays --fix option")
         (assert (string-contains? msg "GroundTruthOverReport") "check --help displays GroundTruthOverReport principle")
         (refute (string-contains? msg ":line") "Zero-line-number invariant in check help")
         (refute (string-contains? msg ":col") "Zero-col invariant in check help")))
      ((err _) (assert false "check --help should succeed")))
    (mt (c/dispatchCmd "check" (list "--fix"))
      ((ok _) (assert false "check --fix without files should return usage error"))
      ((err msg) (assert (string-contains? msg "Usage: asl check") "check --fix without files returns usage")))
    true))

(df ! testWatchDispatch [] -> Bool
  :d "Asserts dispatching of watch command and options in CLI."
  (do
    (mt (c/dispatchCmd "watch" (list))
      ((ok _) (assert false "empty watch must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl watch") "empty watch returns usage error")))
    (mt (c/dispatchCmd "watch" (list "--help"))
      ((ok msg)
       (do
         (assert (string-contains? msg "asl watch: Demand-Driven Incremental Compiler") "watch help title")
         (assert (string-contains? msg "--check") "watch help check option")
         (assert (string-contains? msg "sub-5ms") "watch help latency SLA")
         (refute (string-contains? msg ":line") "Zero-line-number invariant in watch help")
         (refute (string-contains? msg ":col") "Zero-col invariant in watch help")))
      ((err _) (assert false "watch --help should succeed")))
    (mt (c/dispatchCmd "watch" (list "--check"))
      ((ok receipt)
       (do
         (assert (string-contains? receipt ":watch-receipt") "receipt contains :watch-receipt")
         (assert (string-contains? receipt ":status \"ok\"") "receipt status ok")
         (assert (string-contains? receipt ":mutatedSymbol \"Math:add\"") "mutated symbol in receipt")
         (assert (string-contains? receipt ":memoryBound \"verified\"") "memory bound verified in receipt")
         (refute (string-contains? receipt ":line") "Zero-line-number invariant in watch receipt")
         (refute (string-contains? receipt ":col") "Zero-col invariant in watch receipt")))
      ((err _) (assert false "watch --check should succeed")))
    true))

(df ! testHealDispatch [] -> Bool
  :d "Asserts dispatching of heal command and options in CLI."
  (do
    (mt (c/dispatchCmd "heal" (list))
      ((ok _) (assert false "empty heal must fail"))
      ((err msg) (assert (string-contains? msg "Usage: asl heal") "empty heal returns usage error")))
    (mt (c/dispatchCmd "heal" (list "--help"))
      ((ok msg)
       (do
         (assert (string-contains? msg "Usage: asl heal") "heal help usage")
         (assert (string-contains? msg "--max-attempts") "heal help max attempts option")
         (refute (string-contains? msg ":line") "Zero-line-number invariant in heal help")
         (refute (string-contains? msg ":col") "Zero-col invariant in heal help")))
      ((err _) (assert false "heal --help should succeed")))
    true))

(df ! runTests [] -> Bool
  :d "Master test runner executing all pure ASL CLI test suites."
  (and (testMainDispatch)
       (and (testVersionOutput)
            (and (testHelpOutput)
                 (and (testSubcommandsDispatch)
                      (and (testEvalDispatch)
                           (and (testRpcDispatch)
                                (and (testPatchDispatch)
                                     (and (testImpactDispatch)
                                          (and (testCheckDispatch)
                                               (and (testWatchDispatch)
                                                    (testHealDispatch))))))))))))

