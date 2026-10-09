(module aslHarness/asnBashTest :x [runTests] :i [(asnBash :a ab)])

fn testPolicy -> Bool
  (let [(policy (ab/defaultAslInvocationPolicy))] (assert policy.rpcEradicated "rpc is eradicated") (assert policy.asnPrimary "asn is primary") (assert policy.scriptsEmbedded "scripts embedded") (assert policy.executablesEmbedded "executables embedded") (assert policy.toolCallsEmbedded "tool calls embedded") true)

fn testScriptFormat -> Bool
  (let [(form (ab/makeAsnForm "tool" "(:call :tool \"fs-read\" :path \"README.md\")")) (exe (ab/makeAsnExecutable "bin/asl" (list "check" "README.md") "." (list (pair "MODE" "check")) true)) (script (ab/makeAsnScript "smoke" (list form) (list exe))) (payload (ab/invokeAsl script))] (assert (ab/validateAsnScript script) "script validates") (assert (stringStartsWith? payload "(:script :name") "ordinary script payload") (assert (stringContains? payload ":kind \"tool\"") "tool form embedded") (assert (stringContains? payload ":executable :path") "executable embedded") (assert (stringContains? payload ":allow true") "execution consent retained") true)

fn testInvalidScript -> Bool
  (let [(empty (ab/makeAsnScript "" (list) (list))) (payload (ab/invokeAsl empty))] (assert (not (ab/validateAsnScript empty)) "empty script rejected") (assert (stringContains? payload "ERR_INVALID_ASN_SCRIPT") "invalid receipt is explicit") true)

fn runTests -> Bool
  (do (assert (testPolicy) "policy verified") (assert (testScriptFormat) "script format verified") (assert (testInvalidScript) "invalid script verified") true)
