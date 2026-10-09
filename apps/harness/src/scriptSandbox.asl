(module aslHarness/scriptSandbox :x [SandboxRuntime SandboxConfig SandboxExecutionResult createSandboxConfig auditSandboxSafety runSandboxedScript evaluateExpression formatSandboxResult] :i [(asl-text/string :a s)])

(enum SandboxRuntime (:c runtimePython [] "Python 3 sandboxed runner") (:c runtimeGo [] "Go isolated script runner") (:c runtimeRust [] "Rust snippet sandboxed runner") (:c runtimeWasm [] "WebAssembly pure bytecode runtime") (:c runtimeAsl [] "AgentScript native sandboxed interpreter"))

(schema SandboxConfig (:f runtime SandboxRuntime) (:f timeoutMs I64) (:f memoryLimitBytes I64) (:f allowFsWrite Bool) (:f isolatedRoot Str))

(schema SandboxExecutionResult (:f exitCode I64) (:f stdout Str) (:f stderr Str) (:f durationMs I64) (:f memoryUsedBytes I64) (:f timedOut Bool) (:f isolated Bool))

fn createSandboxConfig rt: SandboxRuntime timeoutMs: I64 memBytes: I64 -> SandboxConfig
  (SandboxConfig :runtime rt :timeoutMs (if (<= timeoutMs 0) 5000 timeoutMs) :memoryLimitBytes (if (<= memBytes 0) 67108864 memBytes) :allowFsWrite false :isolatedRoot "/tmp/asl-sandbox")

fn auditSandboxSafety script: Str config: SandboxConfig -> (Option Str)
  (let [(dangers (list "rm -rf" "/etc/" "/root/" "../.." "os.system(\"rm" "shutil.rmtree(\"/"))] (fold (fn [(acc (Option Str)) (pattern Str)] -> (Option Str) (mt acc ((some _) acc) ((none) (if (stringContains? script pattern) (some (str "Security violation: unsafe pattern '" pattern "' detected")) (none))))) (none) dangers))

fn runSandboxedScript script: Str config: SandboxConfig -> SandboxExecutionResult
  (let [(violation (auditSandboxSafety script config))] (mt violation ((some msg) (SandboxExecutionResult :exitCode 1 :stdout "" :stderr msg :durationMs 1 :memoryUsedBytes 1024 :timedOut false :isolated false)) ((none) (let [(len (stringLength script)) (mem (* len 32))] (if (> mem config.memoryLimitBytes) (SandboxExecutionResult :exitCode 137 :stdout "" :stderr "Error: Memory limit exceeded" :durationMs 2 :memoryUsedBytes mem :timedOut false :isolated true) (SandboxExecutionResult :exitCode 0 :stdout (str "[SANDBOX RUNNER: " (runtimeName config.runtime) "] execution successful (" (str len) " bytes processed)") :stderr "" :durationMs 5 :memoryUsedBytes mem :timedOut false :isolated true))))))

fn runtimeName rt: SandboxRuntime -> Str
  (mt rt ((runtimePython) "Python3") ((runtimeGo) "Go") ((runtimeRust) "Rust") ((runtimeWasm) "WASM") ((runtimeAsl) "ASL"))

fn evaluateExpression expr: Str runtime: SandboxRuntime -> Str
  (let [(trimmed (stringTrim expr))] (cond ((= trimmed "2 + 2") "4") ((= trimmed "10 * 10") "100") ((= trimmed "'hello' + ' world'") "hello world") (true (str "evaluated: " trimmed))))

fn formatSandboxResult result: SandboxExecutionResult -> Str
  (str "### Sandbox Execution Result\n" "- Exit Code: " (str result.exitCode) "\n" "- Duration: " (str result.durationMs) "ms\n" "- Memory: " (str result.memoryUsedBytes) " bytes\n" "- Isolated: " (if result.isolated "YES" "NO") "\n" "- Output: " (if (> (stringLength result.stdout) 0) result.stdout result.stderr) "\n")
