(module aslAgent/supervisor :x [ProcessStatus SupervisorConfig ProcessReceipt procInit procRunning procIdleTimeout procDeadlock procCompleted procFailed makeSupervisorConfig buildSupervisedEnv checkProcessActivity trapInteractiveDeadlock executeSupervised!] :i [])

(enum ProcessStatus (:c procInit [] "Process spawned, waiting for startup") (:c procRunning [] "Actively streaming stdout/stderr chunks") (:c procIdleTimeout [] "Process exceeded maximum permitted sliding idle window") (:c procDeadlock [] "Interactive deadlock detected (waiting on STDIN)") (:c procCompleted [] "Process exited normally with zero exit code") (:c procFailed [] "Process exited with non-zero exit code"))

(schema SupervisorConfig (:f slidingIdleMs I64) (:f maxTimeoutMs I64) (:f nonInteractive Bool))

(schema ProcessReceipt (:f exitCode I64) (:f elapsedMs I64) (:f lastOutput Str) (:f isDeadlock Bool) (:f status ProcessStatus))

fn makeSupervisorConfig idleMs: I64 maxMs: I64 nonInteractive: Bool -> SupervisorConfig
  (SupervisorConfig :slidingIdleMs idleMs :maxTimeoutMs maxMs :nonInteractive nonInteractive)

fn buildSupervisedEnv nonInteractive: Bool -> Str
  (if nonInteractive "CI=true DEBIAN_FRONTEND=noninteractive STDIN=/dev/null" "CI=true")

fn checkProcessActivity lastChunkMs: I64 nowMs: I64 idleLimitMs: I64 -> Bool
  (<= (- nowMs lastChunkMs) idleLimitMs)

fn trapInteractiveDeadlock rawOutput: Str elapsedMs: I64 -> ProcessReceipt
  (ProcessReceipt :exitCode 124 :elapsedMs elapsedMs :lastOutput (str "INTERACTIVE DEADLOCK DETECTED (waiting for stdin)\n" rawOutput) :isDeadlock true :status (procDeadlock))

fn executeSupervised! cmd: Str idleMs: I64 cfg: SupervisorConfig -> ProcessReceipt
  (let [(idleThresh cfg.slidingIdleMs)] (if (> idleMs idleThresh) (trapInteractiveDeadlock (str "Command stalled on stdin: " cmd) idleMs) (let [(outputResult (processRun (str (buildSupervisedEnv cfg.nonInteractive) " " cmd))) (outputStr (str outputResult.stdout outputResult.stderr))] (ProcessReceipt :exitCode outputResult.exitCode :elapsedMs idleMs :lastOutput outputStr :isDeadlock false :status (if (= outputResult.exitCode 0) (procCompleted) (procFailed))))))
