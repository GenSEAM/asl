(module aslHarness/benchRunners :x [BenchmarkProfile RunnerConfig createRunnerConfig validateRunnerSecurity formatRunnerBanner] :i [(asl-text/string :a s)])

(schema BenchmarkProfile (:f modelName Str) (:f endpoint Str) (:f isolated Bool) (:f mode Str))

(schema RunnerConfig (:f profile BenchmarkProfile) (:f configDir Str) (:f directTools (List Str)) (:f hasSecretLeaks Bool))

fn validateRunnerSecurity text: Str -> Bool
  (let [(lower (stringLower text))] (not (or (stringContains? lower "llmgtwy_") (or (stringContains? lower "sk-proj-") (or (stringContains? lower "sk-ant-") (stringContains? lower "api_key=llm"))))))

fn createRunnerConfig profile: BenchmarkProfile configDir: Str tools: (List Str) -> RunnerConfig
  (let [(endpoint profile.endpoint) (isSecure (validateRunnerSecurity endpoint))] (RunnerConfig :profile profile :configDir configDir :directTools tools :hasSecretLeaks (not isSecure)))

fn formatRunnerBanner cfg: RunnerConfig -> Str
  (let [(prof cfg.profile) (b1 (s/concat "[*] Launching ASL Benchmark Runner: " prof.modelName)) (b2 (s/concat "\n    Mode: " prof.mode)) (b3 (s/concat "\n    Endpoint: " (if cfg.hasSecretLeaks "***REDACTED***" prof.endpoint))) (b4 (s/concat "\n    Isolation: " (if prof.isolated "STRICT SANDBOX" "STANDARD")))] (s/concat b1 (s/concat b2 (s/concat b3 b4))))
