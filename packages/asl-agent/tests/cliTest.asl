(module aslAgent/cliTest :x [testCliOptionsAndParsing testPhasedInferenceParameters testTelemetryCounters testReplSlashCommands testFormatCliHelp testMainCliEntrypoint! runTests] :i [(cli :a cli) (policy :a pol)])

fn testCliOptionsAndParsing -> Bool
  (let [(opts (cli/makeCliOptions (pol/levelGuarded) "gemma-4-31b-it" "make tests green" "" false))] (assert (= opts.modelId "gemma-4-31b-it") "model id") (assert (not opts.isRepl) "not repl") (assert (= (cli/parseAutonomyFlag "ask") (pol/levelAsk)) "autonomy ask") true)

fn testPhasedInferenceParameters -> Bool
  (let [(cfgInsp (cli/getPhasedConfig (cli/phaseInspect))) (cfgPlan (cli/getPhasedConfig (cli/phasePlan))) (cfgAst (cli/getPhasedConfig (cli/phaseAstPatch))) (cfgDbg (cli/getPhasedConfig (cli/phaseReasonDebug)))] (assert (= cfgInsp.thinkingBudget 0) "inspect budget 0") (assert (= cfgPlan.thinkingBudget 2048) "plan budget 2048") (assert (= cfgAst.thinkingBudget 0) "ast budget 0") (assert (= cfgDbg.thinkingBudget 4096) "dbg budget 4096") true)

fn testTelemetryCounters -> Bool
  (let [(tel (cli/makeTelemetry 14 85.5 0.932 4 4))] (assert (= tel.ttftMs 14) "ttft-ms 14") (assert (> tel.tps 50.0) "tps > 50") (assert (>= tel.kvCacheHitRatio 0.90) "kv cache hit ratio >= 0.90") true)

fn testReplSlashCommands -> Bool
  (do (assert (= (cli/processReplCommand "/exit") "EXIT") "/exit") (assert (= (cli/processReplCommand "/quit") "EXIT") "/quit") (assert (= (cli/processReplCommand "/clear") "CLEAR") "/clear") (assert (>= (stringLength (cli/processReplCommand "/status")) 10) "/status length") (assert (>= (stringLength (cli/processReplCommand "/telemetry")) 10) "/telemetry length") true)

fn testFormatCliHelp -> Bool
  (let [(h (cli/formatCliHelp))] (assert (>= (stringLength h) 100) "help length >= 100") (assert (= (cli/parseAutonomyFlag "auto") (pol/levelAuto)) "parse auto flag") true)

fn testMainCliEntrypoint! -> Bool
  (let [(resHelp (cli/main (list "--help"))) (resVer (cli/main (list "--version"))) (resNil (cli/main (list)))] (assert (ok? resHelp) "main --help must succeed") (assert (ok? resVer) "main --version must succeed") (assert (ok? resNil) "main empty must succeed") true)

fn ! runTests -> Bool
  (do (assert (testCliOptionsAndParsing) "test-cli-options-and-parsing must pass") (assert (testPhasedInferenceParameters) "test-phased-inference-parameters must pass") (assert (testTelemetryCounters) "test-telemetry-counters must pass") (assert (testReplSlashCommands) "test-repl-slash-commands must pass") (assert (testFormatCliHelp) "test-format-cli-help must pass") (assert (testMainCliEntrypoint!) "test-main-cli-entrypoint must pass") true)
