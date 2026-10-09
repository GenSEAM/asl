(module aslHarness/tbench4HardenerTest :x [testIdleTimeoutTimerCreation testSkeletonLogExtraction testSanitizeTerminalExecution testNonInteractiveGuards testSkeletonErrorDetection runTests] :i [(tbench4Hardener :a tb)])

fn testIdleTimeoutTimerCreation -> Bool
  (let [(w1 (tb/makeIdleTimeoutTimer 10000 60000 true)) (w2 (tb/makeIdleTimeoutTimer 5000 30000 false))] (assert (= w1.slidingTimeoutMs 10000) "Idle timer sliding window must match 10s") (assert (= w1.hardCeilingMs 60000) "Idle timer hard ceiling must match 60s") (assert w1.escalationSigkill "Escalation must be true for w1") (assert (not w2.escalationSigkill) "Escalation must be false for w2") true)

fn testSkeletonLogExtraction -> Bool
  (let [(cleanOut "building target
compilation ok
exit 0") (sk1 (tb/extractProcSkeleton cleanOut 0)) (sk2 (tb/extractProcSkeleton cleanOut 1))] (assert sk1.exitedCleanly "sk1 must report clean exit") (assert (not sk2.exitedCleanly) "sk2 must report failed exit on non-zero return") (assert (> (stringLength sk1.headSnippet) 0) "Head snippet must be populated") (assert (= sk1.errorLines 0) "Zero error lines in clean output") true)

fn testSanitizeTerminalExecution -> Bool
  (let [(w (tb/makeIdleTimeoutTimer 10000 60000 true)) (hActive (tb/makeTbenchHardener true w 1000)) (hPassive (tb/makeTbenchHardener false w 1000)) (cmd1 "sudo apt update") (cmd2 "make test") (san1 (tb/sanitizeTerminalExecution cmd1 hActive)) (san2 (tb/sanitizeTerminalExecution cmd2 hActive)) (san3 (tb/sanitizeTerminalExecution cmd2 hPassive))] (assert (stringContains? san1 "sudo -n") "Sudo must be converted to non-interactive sudo -n") (assert (stringContains? san2 "CI=1") "Active hardener must prepend CI=1") (assert (stringContains? san2 "TERM=dumb") "Active hardener must prepend TERM=dumb") (assert (= san3 cmd2) "Passive hardener must preserve command untouched") true)

fn testNonInteractiveGuards -> Bool
  (let [(w (tb/makeIdleTimeoutTimer 10000 60000 true)) (h (tb/makeTbenchHardener true w 1000)) (res (tb/sanitizeTerminalExecution "apt-get install curl" h))] (assert (stringContains? res "DEBIAN_FRONTEND=noninteractive") "Must inject noninteractive frontend") (assert (stringContains? res "-y") "Must inject auto-yes flag -y") true)

fn testSkeletonErrorDetection -> Bool
  (let [(errOut "compiling file.c
fatal: failed to open header
error: undefined symbol
FAILED") (sk (tb/extractProcSkeleton errOut 2))] (assert (not sk.exitedCleanly) "Must report failed execution") (assert (> sk.errorLines 0) "Must count multiple error lines") (assert (stringContains? sk.tailSnippet "error") "Tail snippet must reflect error state") true)

fn runTests -> Bool
  (and (testIdleTimeoutTimerCreation) (and (testSkeletonLogExtraction) (and (testSanitizeTerminalExecution) (and (testNonInteractiveGuards) (testSkeletonErrorDetection)))))
