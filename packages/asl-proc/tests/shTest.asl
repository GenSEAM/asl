(module asl-proc/tests :x [runTests runTests!] :i [(asl-proc/process :a proc) (asl-proc/log :a log) (reducer :a red) (sh :a sh) (deadline :a wd)])

fn testCommandBuilder -> Bool
  (let [(c (proc/cmd "git" (list "status" "-s"))) (c2 (proc/withTimeout c 2500))]
    (do
      (assert (= c.bin "git") "cmd bin git")
      (refute (!= c.bin "git") "cmd bin refutes non-git")
      (assert (= c2.timeoutMs 2500) "timeout 2500")
      (refute (!= c2.timeoutMs 2500) "timeout refutes non-2500")
      true))

fn testLogFormatter -> Bool
  (let [(entry (log/LogEntry :level (log/info) :message "Process started" :timestamp 1700000000 :subsystem "worker")) (formatted (log/formatEntry entry))]
    (do
      (refute (stringEmpty? formatted) "formatted log not empty")
      (assert (stringContains? formatted "Process started") "formatted log contains message")
      (refute (not (stringContains? formatted "Process started")) "formatted log refutes missing message")
      true))

fn testReducerIntegration -> Bool
  (let [(cfg (red/defaultConfig)) (stream (red/reduceText "test line"))]
    (do
      (assert (= cfg.headLimit 500) "head limit 500")
      (refute (!= cfg.headLimit 500) "head limit refutes non-500")
      (assert (= stream.reducedLineCount 1) "reduced line count 1")
      (refute (!= stream.reducedLineCount 1) "reduced line count refutes non-1")
      true))

fn ! benchRunCmdMb mb: Int64 budgetMs: Int64 -> Bool
  (let [(bytes (* mb 1048576))
        (cmdStr (str "head -c " (stringFromInt64 bytes) " /dev/zero | tr '\\0' 'A'"))
        (t0 (monotonicNs))
        (receiptRes (sh/runCmd! "sh" (list "-c" cmdStr)))
        (t1 (monotonicNs))
        (elapsedMs (/ (- t1 t0) 1000000))]
    (do
      (assert (ok? receiptRes) (str "runCmd! " (stringFromInt64 mb) "MB must succeed, not swallow an error"))
      (mt receiptRes
        ((ok receipt)
          (do (assert (= receipt.exitCode 0) "head|tr must exit 0")
              (assert (ok? (sh/releaseReceipt! receipt)) "runCmd! receipt spool file must release cleanly, leaving none behind")
              true))
        ((err _) true))
      (assert (< elapsedMs budgetMs) (str "runCmd! " (stringFromInt64 mb) "MB took " (stringFromInt64 elapsedMs) "ms, budget " (stringFromInt64 budgetMs) "ms (PROC-spoolQuadratic)"))
      true))

fn ! benchStringJoinChars n: Int64 budgetMs: Int64 -> Bool
  (let [(chars (stringChars (stringRepeat "x" n)))
        (t0 (monotonicNs))
        (joined (stringJoin chars ""))
        (t1 (monotonicNs))
        (elapsedMs (/ (- t1 t0) 1000000))]
    (do
      (assert (= (int32ToInt64 (stringLength joined)) n) (str "stringJoin of " (stringFromInt64 n) " one-char strings must reassemble to length " (stringFromInt64 n)))
      (assert (< elapsedMs budgetMs) (str "stringJoin of " (stringFromInt64 n) " one-char strings took " (stringFromInt64 elapsedMs) "ms, budget " (stringFromInt64 budgetMs) "ms"))
      true))

fn testBoundPortHeadBannerDetected -> Bool
  (let [(filler (stringRepeat "y" 100000))
        (banner (str ":port-bound 4242\n" filler))
        (window (sh/boundPortHeadWindow banner))
        (verdict (wd/detectBoundPort window))]
    (do
      (assert (<= (int32ToInt64 (stringLength window)) 65536) "boundPortHeadWindow caps detectBoundPort's input at 64KB regardless of total output size")
      (assert verdict.detected "a port-bound banner on the first line must still be detected despite >64KB of later output")
      (assert (= verdict.port 4242) "the detected port must be read correctly from the head window")
      true))

fn ! testRunCmdCaptureStaysLinear -> Bool
  (let [(bytes 4194304)
        (cmdStr (str "head -c " (stringFromInt64 bytes) " /dev/zero | tr '\\0' 'A'"))
        (expected (stringRepeat "A" bytes))
        (out (proc/exec! (proc/withTimeout (proc/cmd "sh" (list "-c" cmdStr)) 60000)))]
    (do
      (assert (ok? out) "4MB capture must complete within the 60s generous wall-clock budget, not time out (PROC-spoolQuadratic)")
      (mt out
        ((ok o)
          (do
            (assert (= o.exitCode 0) "head|tr must exit 0")
            (assert (= (int32ToInt64 (stringLength o.stdout)) bytes) "captured stdout must be exactly 4MB, no truncation or duplication from the chunk merge")
            (assert (= o.stdout expected) "captured stdout bytes must exactly match the source stream")
            true))
        ((err _) true))
      (assert (benchRunCmdMb 1 30000) "runCmd! 1MB must finish inside a 30s budget")
      (assert (benchRunCmdMb 4 30000) "runCmd! 4MB must finish inside a 30s budget")
      (assert (benchStringJoinChars 200000 1000) "stringJoin of 200k one-char strings must finish inside a 1s budget")
      true))

fn ! runTests -> Bool
  (do (assert (testCommandBuilder) "test-command-builder must pass") (assert (testLogFormatter) "test-log-formatter must pass") (assert (testReducerIntegration) "test-reducer-integration must pass") (assert (testBoundPortHeadBannerDetected) "test-bound-port-head-banner-detected must pass") (assert (testRunCmdCaptureStaysLinear) "test-run-cmd-capture-stays-linear must pass") true)

fn ! runTests! -> (Result Unit String)
  (if (runTests) (ok ()) (err "asl-proc tests failed"))
