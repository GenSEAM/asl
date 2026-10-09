(module aslHarness/scriptSandboxTest :x [testCreateSandboxConfig testSandboxSafetyDetection testRunSandboxedPythonScript testRunSandboxedWasm testSandboxMemoryLimit testEvaluateExpression runSandboxTests runTests] :i [(scriptSandbox :a ss)])

fn testCreateSandboxConfig -> Bool
  (let [(cfg (ss/createSandboxConfig (ss/runtimePython) 1000 1048576))] (assert (= cfg.timeoutMs 1000) "timeout is 1000") (assert (= cfg.memoryLimitBytes 1048576) "memory limit is 1048576") (assert (not cfg.allowFsWrite) "fs write disabled") true)

fn testSandboxSafetyDetection -> Bool
  (let [(cfg (ss/createSandboxConfig (ss/runtimePython) 1000 1048576)) (unsafeScript "import os\nos.system('rm -rf /')\n") (safeScript "print('hello')\n") (auditBad (ss/auditSandboxSafety unsafeScript cfg)) (auditGood (ss/auditSandboxSafety safeScript cfg))] (assert (match auditBad ((some _) true) ((none) false)) "audit-bad detected") (assert (match auditGood ((none) true) ((some _) false)) "audit-good passed") true)

fn testRunSandboxedPythonScript -> Bool
  (let [(cfg (ss/createSandboxConfig (ss/runtimePython) 1000 1048576)) (script "def fib(n):\n    return n if n <= 1 else fib(n-1) + fib(n-2)\nprint(fib(10))\n") (res (ss/runSandboxedScript script cfg))] (assert (= res.exitCode 0) "exit code 0") (assert res.isolated "is isolated") (assert (> (stringLength res.stdout) 0) "stdout non-empty") (assert (> (stringLength (ss/formatSandboxResult res)) 0) "format non-empty") true)

fn testRunSandboxedWasm -> Bool
  (let [(cfg (ss/createSandboxConfig (ss/runtimeWasm) 500 524288)) (script "(module (func (export \"add\") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))") (res (ss/runSandboxedScript script cfg))] (assert (= res.exitCode 0) "wasm exit code 0") (assert res.isolated "wasm is isolated") true)

fn testSandboxMemoryLimit -> Bool
  (let [(cfg (ss/createSandboxConfig (ss/runtimeRust) 500 100)) (hugeScript (str "fn main() {\n" "    let v = vec![0; 100000];\n" "}\n")) (res (ss/runSandboxedScript hugeScript cfg))] (assert (= res.exitCode 137) "memory limit exit code 137") (assert (not (= res.exitCode 0)) "exit code must not be 0") true)

fn testEvaluateExpression -> Bool
  (let [(res1 (ss/evaluateExpression "2 + 2" (ss/runtimePython))) (res2 (ss/evaluateExpression "10 * 10" (ss/runtimeGo)))] (assert (= res1 "4") "res1 is 4") (assert (= res2 "100") "res2 is 100") true)

fn runSandboxTests -> Bool
  (do (testCreateSandboxConfig) (testSandboxSafetyDetection) (testRunSandboxedPythonScript) (testRunSandboxedWasm) (testSandboxMemoryLimit) (testEvaluateExpression) true)

fn runTests -> Bool
  (runSandboxTests)
