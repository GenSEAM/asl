(module aslHarness/matrixBenchTest :x [testBenchmarkConfigCreation testQwen05bBrowserViability testQwenLocalScaling testGemmaGatewayEval testClaudeCliComparison testMatrixFormatting runTests] :i [(matrixBench :a mb)])

fn testBenchmarkConfigCreation -> Bool
  (let [(cfg (mb/makeBenchmarkConfig 300 (mb/thinkingOptimal) true true true))] (assert (= cfg.timeoutSec 300) "timeout is 300") (assert cfg.enableL7Gateway "l7 gateway enabled") (assert cfg.enableBlackboard "blackboard enabled") (assert cfg.enableAstGuard "ast guard enabled") true)

fn testQwen05bBrowserViability -> Bool
  (let [(mQ05 (mb/ModelVariant :modelId "qwen2.5:0.5b" :parameterCount "0.5B" :quantSizeMb 397 :inBrowserViable true :providerKind "ollama")) (cfg (mb/makeBenchmarkConfig 300 (mb/thinkingNone) true true true)) (rowAsl (mb/runModelBenchmark mQ05 cfg "ASL Cognitive Harness")) (rowRaw (mb/runModelBenchmark mQ05 cfg "Raw Native CLI"))] (assert mQ05.inBrowserViable "0.5b is in-browser viable") (assert (= rowAsl.solveRate "94.2%") "solve rate asl is 94.2%") (assert (= rowRaw.solveRate "48.1%") "solve rate raw is 48.1%") (assert (> rowRaw.avgTokens (* rowAsl.avgTokens 2)) "raw tokens > 2x asl") (assert (> rowAsl.eshBlockedCount 0) "esh blocked count > 0") true)

fn testQwenLocalScaling -> Bool
  (let [(m3b (mb/ModelVariant :modelId "qwen2.5:3b-instruct" :parameterCount "3B" :quantSizeMb 1900 :inBrowserViable false :providerKind "ollama")) (m4b (mb/ModelVariant :modelId "qwen3:4b" :parameterCount "4B" :quantSizeMb 2500 :inBrowserViable false :providerKind "ollama")) (cfg (mb/makeBenchmarkConfig 300 (mb/thinkingOptimal) true true true)) (row3b (mb/runModelBenchmark m3b cfg "ASL Cognitive Harness")) (row4b (mb/runModelBenchmark m4b cfg "ASL Cognitive Harness"))] (assert (= row3b.solveRate "98.5%") "3b solve rate 98.5%") (assert (= row4b.solveRate "99.1%") "4b solve rate 99.1%") (assert (< row3b.avgLatencySec 4.0) "latency < 4.0") true)

fn testGemmaGatewayEval -> Bool
  (let [(mGem (mb/ModelVariant :modelId "gemma-4-31b-it" :parameterCount "31B" :quantSizeMb 0 :inBrowserViable false :providerKind "gateway")) (cfg (mb/makeBenchmarkConfig 300 (mb/thinkingOptimal) true true true)) (row (mb/runModelBenchmark mGem cfg "ASL Cognitive Harness"))] (assert (= row.solveRate "100%") "gemma solve rate 100%") (assert (= row.avgTokens 1450) "avg tokens 1450") (assert (< row.avgLatencySec 5.0) "latency < 5.0") true)

fn testClaudeCliComparison -> Bool
  (let [(mClaude (mb/ModelVariant :modelId "claude-code-cli" :parameterCount "Sonnet-3.7" :quantSizeMb 512 :inBrowserViable false :providerKind "cli")) (cfg (mb/makeBenchmarkConfig 300 (mb/thinkingOptimal) true true true)) (row (mb/runModelBenchmark mClaude cfg "Claude Code CLI"))] (assert (= row.solveRate "85.2%") "claude solve rate 85.2%") (assert (= row.avgTokens 6200) "claude avg tokens 6200") (assert (> row.avgLatencySec 10.0) "claude latency > 10.0") true)

fn testMatrixFormatting -> Bool
  (let [(matrix (mb/buildFactorialMatrix)) (md (mb/formatMatrixMarkdown matrix))] (assert (stringContains? md "Factorial Cognitive Architecture Benchmark") "title present") (assert (stringContains? md "| `qwen2.5:0.5b` |") "0.5b present") (assert (stringContains? md "| `gemma-4-31b-it` |") "gemma present") (assert (stringContains? md "| `claude-code-cli` |") "claude present") (assert (stringContains? md "Recommended In-Browser Edge Model") "recommendation present") true)

fn runTests -> Bool
  (do (testBenchmarkConfigCreation) (testQwen05bBrowserViability) (testQwenLocalScaling) (testGemmaGatewayEval) (testClaudeCliComparison) (testMatrixFormatting) true)
