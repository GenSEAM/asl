(module aslAgent/supervisorTest :x [testSupervisorConfig testSupervisedEnvInjection testSlidingIdleTimeoutActivity testDeadlockTrappingReceipt testExecuteSupervisedCompletion! runTests] :i [(supervisor :a sup)])

"run: (run-tests)"

fn testSupervisorConfig -> Bool
  (let [(cfg (sup/makeSupervisorConfig 10000 900000 true))] (assert (= cfg.slidingIdleMs 10000) "sliding idle ms is 10000") (assert cfg.nonInteractive "non-interactive flag is true") true)

fn testSupervisedEnvInjection -> Bool
  (let [(env (sup/buildSupervisedEnv true))] (assert (>= (stringLength env) 20) "supervised env length >= 20") (assert (not (stringContains? env "error")) "supervised env must not contain error") true)

fn testSlidingIdleTimeoutActivity -> Bool
  (do (assert (sup/checkProcessActivity 1000 5000 10000) "active within idle threshold") (assert (not (sup/checkProcessActivity 1000 15000 10000)) "inactive exceeding idle threshold") true)

fn testDeadlockTrappingReceipt -> Bool
  (let [(rcpt (sup/trapInteractiveDeadlock "prompt: Do you want to proceed? [y/N]" 12000))] (assert rcpt.isDeadlock "interactive prompt detected as deadlock") (assert (= rcpt.exitCode 124) "exit code is 124") true)

fn testExecuteSupervisedCompletion! -> Bool
  (let [(cfg (sup/makeSupervisorConfig 10000 900000 true)) (rcptOk (sup/executeSupervised! "asl test app.asl" 2000 cfg)) (rcptStalled (sup/executeSupervised! "read -p 'Name:'" 15000 cfg))] (assert (not rcptOk.isDeadlock) "normal execution not deadlock") (assert rcptStalled.isDeadlock "stalled execution marked deadlock") true)

fn ! runTests -> Bool
  (do (testSupervisorConfig) (testSupervisedEnvInjection) (testSlidingIdleTimeoutActivity) (testDeadlockTrappingReceipt) (testExecuteSupervisedCompletion!) true)
