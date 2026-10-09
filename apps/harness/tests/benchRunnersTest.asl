(module aslHarnessTests/benchRunnersTest :x [testCreateRunnerConfig testValidateRunnerSecurityClean testValidateRunnerSecurityLeak testFormatRunnerBanner runTests] :i [(aslHarness/benchRunners :a br) (asl-text/string :a s)])

fn testCreateRunnerConfig -> Bool
  (let [(prof (br/BenchmarkProfile :modelName "gemma-4-31b-it" :endpoint "http://127.0.0.1:8765/v1" :isolated true :mode "genseam-asl")) (cfg (br/createRunnerConfig prof "/tmp/isolated-test" (list "fs" "exec" "ast")))] (assert (= cfg.configDir "/tmp/isolated-test") "config-dir matches") (assert (= (listLength cfg.directTools) 3) "three direct tools") (assert (not cfg.hasSecretLeaks) "no secret leaks in runner config") true)

fn testValidateRunnerSecurityClean -> Bool
  (let [(cleanStr "export LLM_GATEWAY_API_KEY=\"$ENV_VAR_SECRET\"")] (assert (br/validateRunnerSecurity cleanStr) "clean string passes security validation") (assert (not (br/validateRunnerSecurity "export LLM_GATEWAY_API_KEY=\"llmgtwy_vLHJNl0D6XpsifrNXg2zKVtXDEX26m93H5E4g8RX\"")) "leaked secret rejected") true)

fn testValidateRunnerSecurityLeak -> Bool
  (let [(leakedStr "export LLM_GATEWAY_API_KEY=\"llmgtwy_vLHJNl0D6XpsifrNXg2zKVtXDEX26m93H5E4g8RX\"")] (assert (not (br/validateRunnerSecurity leakedStr)) "leaked secret caught by security validation") (assert (br/validateRunnerSecurity "export LLM_GATEWAY_API_KEY=\"$ENV_VAR_SECRET\"") "clean secret accepted") true)

fn testFormatRunnerBanner -> Bool
  (let [(prof (br/BenchmarkProfile :modelName "qwen-2.5-1.5b" :endpoint "http://localhost:11434" :isolated true :mode "factor-matrix")) (cfg (br/createRunnerConfig prof "/tmp/test" (list "intel"))) (banner (br/formatRunnerBanner cfg))] (assert (stringContains? banner "Launching ASL Benchmark Runner: qwen-2.5-1.5b") "banner has model name") (assert (stringContains? banner "Mode: factor-matrix") "banner has mode") (assert (stringContains? banner "STRICT SANDBOX") "banner notes sandbox") true)

fn runTests -> Bool
  (do (testCreateRunnerConfig) (testValidateRunnerSecurityClean) (testValidateRunnerSecurityLeak) (testFormatRunnerBanner) true)
