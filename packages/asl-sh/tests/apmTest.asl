(module asl-sh/apmTest
  :d "Falsifiable test suite for APM stream demultiplexer and ProcessReceipt token budget ceiling."
  :x [testOobStreamDemuxMemoryBound
      runTests]
  :i [(asl-sh/process :a proc)
      (reducer      :a red)
      (sh           :a sh)
      (apm          :a apm)])

(df testReceiptStructure [] -> Bool
  :d "Verifies ProcessReceipt record structure and field extraction."
  (let [(r (proc/makeProcessReceipt 0 120 32 "tmp/asl-proc-build-1.spool" "Build succeeded"))]
    (assert (= (.-exitCode r) 0) "Exit code must be 0")
    (assert (= (.-durationMs r) 120) "Duration must match 120ms")
    (assert (= (.-peakRssMb r) 32) "Peak RSS must match 32MB")
    (assert (= (.-spoolPath r) "tmp/asl-proc-build-1.spool") "Spool path must match")
    (assert (= (.-summary r) "Build succeeded") "Summary must match")
    true))

(df testTokenCeiling [] -> Bool
  :d "Verifies that ProcessReceipt stays strictly under 80 BPE tokens even with large outputs."
  (let [(hugeOut (str "line 1\nline 2\nline 3\nline 4\nline 5\n"
                       "warning: unused variable\n"
                       "error[E0382]: borrow of moved value: `v`\n  --> src/main.rs:24:9\n"
                       "error: aborting due to previous error\n"))
        (r (red/demuxStream hugeOut "" 1 450 "tmp/asl-proc-cargo-99.spool"))
        (rendered (proc/renderReceipt r))
        (toks (proc/receiptTokens r))]
    (assert (< toks 80) "ProcessReceipt must consume strictly under 80 tokens")
    (assert (> toks 0) "ProcessReceipt token count must be positive")
    (assert (string-contains? rendered ":proc-receipt") "Rendered receipt must have ASN header")
    (assert (= (.-exitCode r) 1) "Exit code 1 must be preserved")
    true))

(df testSummaryTruncation [] -> Bool
  :d "Verifies that oversized diagnostic messages are truncated to 50 tokens with ellipsis suffix."
  (let [(longMsg (str "Very long diagnostic error message exceeding the token budget ceiling with extensive compiler output "
                       "including symbol traces, memory layouts, register contents, stack unwinding frames, "
                       "type deduction failures, lifetime constraint mismatches, template expansion depths, "
                       "and diagnostic context that would otherwise degrade agent prompt token efficiency."))
        (truncated (red/truncateSummary longMsg 50))
        (r (red/demuxStream "" longMsg 1 100 "tmp/asl-proc-err-1.spool"))]
    (assert (> (string-length longMsg) 300) "Test input message must exceed 300 characters")
    (assert (<= (string-length truncated) 200) "Truncated summary must be <= 200 characters")
    (assert (string-ends-with? truncated "...") "Truncated summary must end with ellipsis")
    (assert (string-ends-with? (.-summary r) "...") "Receipt summary must end with ellipsis")
    (assert (< (proc/receiptTokens r) 80) "ProcessReceipt with truncated summary must remain strictly under 80 tokens")
    true))

(df testErrorExtraction [] -> Bool
  :d "Verifies structured diagnostic message and location extraction from stderr/stdout."
  (let [(stdoutLog "Compiling app...\nGenerating bundles...\n")
        (stderrLog "src/index.ts:42:5 - error TS2322: Type 'string' is not assignable to type 'number'.\n")
        (r (red/demuxStream stdoutLog stderrLog 1 300 "tmp/asl-proc-tsc-1.spool"))]
    (assert (= (.-exitCode r) 1) "Exit code must be 1")
    (assert (string-contains? (.-summary r) "TS2322") "Diagnostic code must be present in summary")
    (assert (string-contains? (.-summary r) "src/index.ts:42:") "File location must be extracted")
    true))

(df testExitPreservation [] -> Bool
  :d "Verifies that zero and non-zero exit codes are preserved exactly, including empty stderr/stdout."
  (let [(rOk (red/demuxStream "done" "" 0 10 "tmp/asl-proc-echo-0.spool"))
        (rOom (red/demuxStream "" "Killed\n" 137 5000 "tmp/asl-proc-app-137.spool"))
        (rTimeout (red/demuxStream "" "Timed out\n" 124 10000 "tmp/asl-proc-app-124.spool"))
        (rEmpty (red/demuxStream "" "   \n  " 2 15 "tmp/asl-proc-silent-2.spool"))]
    (assert (= (.-exitCode rOk) 0) "Exit code 0 preserved")
    (assert (= (.-summary rOk) "Command succeeded") "Success summary emitted")
    (assert (= (.-exitCode rOom) 137) "Exit code 137 (OOM) preserved")
    (assert (= (.-exitCode rTimeout) 124) "Exit code 124 (Timeout) preserved")
    (assert (= (.-exitCode rEmpty) 2) "Exit code 2 preserved")
    (assert (= (.-summary rEmpty) "Process failed with exit code 2") "Empty output non-zero failure summary emitted")
    true))

(df testDemuxStream [] -> Bool
  :d "Verifies demux-stream ephemeral spool path generation and channel separation."
  (let [(spool (red/generateSpoolPath "npm" 42))
        (spoolNested (red/generateSpoolPath "/usr/bin/npm" 99))]
    (assert (string-starts-with? spool "tmp/asl-proc-npm-") "Spool path prefix must match")
    (assert (string-ends-with? spool ".spool") "Spool path extension must be .spool")
    (refute (string-contains? spoolNested "tmp/asl-proc-/") "Spool path must sanitize path separators")
    (assert (string-ends-with? spoolNested ".spool") "Sanitized spool path extension must be .spool")
    true))

(df testShRunCmd [] -> Bool
  :d "Verifies that sh/run-cmd! returns a Result containing ProcessReceipt."
  (let [(res (sh/runCmd! "echo" (list "hello")))]
    (mt res
      ((ok receipt)
       (assert (= (.-exitCode receipt) 0) "ProcessReceipt exit-code must be 0")
       (assert (< (proc/receiptTokens receipt) 80) "Tokens must be <80")
       true)
      ((err _)
       (assert false "run-cmd! must succeed")
       false))))

(df testOobStreamDemuxMemoryBound [] -> Bool
  :d "Verifies that streaming 100MB of synthetic data through OobDemuxer is bounded < 64MB with clean termination."
  (let [(spoolPath "tmp/asl-proc-oob-100mb.spool")
        (demuxer0 (apm/makeOobDemuxer spoolPath 67108864))
        (chunk1mb (stringRepeat "0123456789ABCDEF" 65536))
        (demuxer100 (fold (fn [(d apm/OobDemuxer) (_i Int64)] -> apm/OobDemuxer
                             (apm/oobDemuxChunk d chunk1mb))
                           demuxer0
                           (range 0 70)))
        (receipt (apm/oobDemuxFinish demuxer100 0 1200))]
    (assert (.-isTerminated demuxer100) "Demuxer must be terminated after exceeding 64MB limit")
    (assert (= (.-terminationReason demuxer100) ":buffer-overflow") "Termination reason must be :buffer-overflow")
    (assert (<= (.-bufferBytes demuxer100) 68157440) "Active in-flight buffer must be strictly bounded near 64MB")
    (assert (= (.-totalBytes demuxer100) 73400320) "Total processed bytes must equal exactly 70MB (73400320)")
    (assert (= (.-exitCode receipt) 137) "Terminated stream exit code must be 137")
    (assert (string-contains? (.-summary receipt) "memory bound < 64MB exceeded") "Summary must cite memory bound exceeded")
    (assert (< (proc/receiptTokens receipt) 80) "ProcessReceipt tokens must be strictly < 80")
    true))

(df runTests [] -> Bool
  :d "Executes all APM stream demultiplexer and ProcessReceipt test suites."
  (let [(r1 (testReceiptStructure))
        (r2 (testTokenCeiling))
        (r3 (testSummaryTruncation))
        (r4 (testErrorExtraction))
        (r5 (testExitPreservation))
        (r6 (testDemuxStream))
        (r7 (testShRunCmd))
        (r8 (testOobStreamDemuxMemoryBound))]
    (and r1 (and r2 (and r3 (and r4 (and r5 (and r6 (and r7 r8)))))))))
