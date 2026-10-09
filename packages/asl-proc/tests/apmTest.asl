(module asl-proc/apmTest :x [testOobStreamDemuxMemoryBound runTests] :i [(asl-proc/process :a proc) (reducer :a red) (sh :a sh) (apm :a apm) (spool :a spool)])

fn testReceiptStructure -> Bool
  (let [(r (proc/makeProcessReceipt 0 120 32 "tmp/asl-proc-build-1.spool" "Build succeeded"))] (assert (= r.exitCode 0) "Exit code must be 0") (assert (= r.durationMs 120) "Duration must match 120ms") (assert (= r.peakRssMb 32) "Peak RSS must match 32MB") (assert (= r.spoolPath "tmp/asl-proc-build-1.spool") "Spool path must match") (assert (= r.summary "Build succeeded") "Summary must match") true)

fn testTokenCeiling -> Bool
  (let [(hugeOut (str "line 1\nline 2\nline 3\nline 4\nline 5\n" "warning: unused variable\n" "error[E0382]: borrow of moved value: `v`\n  --> src/main.rs:24:9\n" "error: aborting due to previous error\n")) (r (red/demuxStream hugeOut "" 1 450 "tmp/asl-proc-cargo-99.spool")) (rendered (proc/renderReceipt r)) (toks (proc/receiptTokens r))] (assert (< toks 80) "ProcessReceipt must consume strictly under 80 tokens") (assert (> toks 0) "ProcessReceipt token count must be positive") (assert (stringContains? rendered ":proc-receipt") "Rendered receipt must have ASN header") (assert (= r.exitCode 1) "Exit code 1 must be preserved") true)

fn testSummaryTruncation -> Bool
  (let [(longMsg (str "Very long diagnostic error message exceeding the token budget ceiling with extensive compiler output " "including symbol traces, memory layouts, register contents, stack unwinding frames, " "type deduction failures, lifetime constraint mismatches, template expansion depths, " "and diagnostic context that would otherwise degrade agent prompt token efficiency.")) (truncated (red/truncateSummary longMsg 50)) (r (red/demuxStream "" longMsg 1 100 "tmp/asl-proc-err-1.spool"))] (assert (> (stringLength longMsg) 300) "Test input message must exceed 300 characters") (assert (<= (stringLength truncated) 200) "Truncated summary must be <= 200 characters") (assert (stringEndsWith? truncated "...") "Truncated summary must end with ellipsis") (assert (stringEndsWith? r.summary "...") "Receipt summary must end with ellipsis") (assert (< (proc/receiptTokens r) 80) "ProcessReceipt with truncated summary must remain strictly under 80 tokens") true)

fn testErrorExtraction -> Bool
  (let [(stdoutLog "Compiling app...\nGenerating bundles...\n") (stderrLog "src/index.ts:42:5 - error TS2322: Type 'string' is not assignable to type 'number'.\n") (r (red/demuxStream stdoutLog stderrLog 1 300 "tmp/asl-proc-tsc-1.spool"))] (assert (= r.exitCode 1) "Exit code must be 1") (assert (stringContains? r.summary "TS2322") "Diagnostic code must be present in summary") (assert (stringContains? r.summary "src/index.ts:42:") "File location must be extracted") true)

fn testExitPreservation -> Bool
  (let [(rOk (red/demuxStream "done" "" 0 10 "tmp/asl-proc-echo-0.spool")) (rOom (red/demuxStream "" "Killed\n" 137 5000 "tmp/asl-proc-app-137.spool")) (rTimeout (red/demuxStream "" "Timed out\n" 124 10000 "tmp/asl-proc-app-124.spool")) (rEmpty (red/demuxStream "" "   \n  " 2 15 "tmp/asl-proc-silent-2.spool"))] (assert (= rOk.exitCode 0) "Exit code 0 preserved") (assert (= rOk.summary "Command succeeded") "Success summary emitted") (assert (= rOom.exitCode 137) "Exit code 137 (OOM) preserved") (assert (= rTimeout.exitCode 124) "Exit code 124 (Timeout) preserved") (assert (= rEmpty.exitCode 2) "Exit code 2 preserved") (assert (= rEmpty.summary "Process failed with exit code 2") "Empty output non-zero failure summary emitted") true)

fn testDemuxStream -> Bool
  (let [(spool (red/generateSpoolPath "npm" 42 "tmp")) (spoolNested (red/generateSpoolPath "/usr/bin/npm" 99 "tmp"))] (assert (stringStartsWith? spool "tmp/asl-proc-npm-") "Spool path prefix must match") (assert (stringEndsWith? spool ".spool") "Spool path extension must be .spool") (refute (stringContains? spoolNested "tmp/asl-proc-/") "Spool path must sanitize path separators") (assert (stringEndsWith? spoolNested ".spool") "Sanitized spool path extension must be .spool") true)

fn ! testShRunCmd! -> Bool
  (let [(res (sh/runCmd! "echo" (list "hello")))]
    (do
      (assert (ok? res) "run-cmd! must succeed")
      (assert (mt res ((ok receipt) (and (= receipt.exitCode 0) (< (proc/receiptTokens receipt) 80))) ((err _) false)) "ProcessReceipt exit-code must be 0 and tokens must be <80")
      (let [(_ (mt res ((ok receipt) (sh/releaseReceipt! receipt)) ((err _) (err "no receipt"))))] true)))

fn ! testOobStreamDemuxMemoryBound -> Bool
  (let [(spoolPathRes (spool/reserveSpoolPath! "oob-100mb" 0))]
    (do
      (assert (ok? spoolPathRes) "reserve-spool-path! must succeed")
      (let [(spoolPath (resultOr spoolPathRes "")) (demuxer0 (apm/makeOobDemuxer spoolPath 67108864)) (chunk1mb (stringRepeat "0123456789ABCDEF" 65536)) (demuxer100 (fold (fn [(d apm/OobDemuxer) (_i Int64)] -> apm/OobDemuxer (apm/oobDemuxChunk d chunk1mb)) demuxer0 (range 0 70))) (finishRes (apm/oobDemuxFinish demuxer100 0 1200))]
        (do
          (assert demuxer100.isTerminated "Demuxer must be terminated after exceeding 64MB limit")
          (assert (= demuxer100.terminationReason ":buffer-overflow") "Termination reason must be :buffer-overflow")
          (assert (<= demuxer100.bufferBytes 68157440) "Active in-flight buffer must be strictly bounded near 64MB")
          (assert (= demuxer100.totalBytes 73400320) "Total processed bytes must equal exactly 70MB (73400320)")
          (assert (ok? finishRes) "oob-demux-finish! must succeed")
          (assert (mt finishRes ((ok receipt) (and (= receipt.exitCode -9) (and (stringContains? receipt.summary "memory bound < 64MB exceeded") (< (proc/receiptTokens receipt) 80)))) ((err _) false)) "Terminated stream receipt must have exit -9, cite the memory bound, and stay under 80 tokens")
          (let [(_ (mt finishRes ((ok receipt) (spool/spoolPathRelease! receipt.spoolPath)) ((err _) (err "no receipt"))))] true)))))

fn ! runTests -> Bool
  (let [(r1 (testReceiptStructure)) (r2 (testTokenCeiling)) (r3 (testSummaryTruncation)) (r4 (testErrorExtraction)) (r5 (testExitPreservation)) (r6 (testDemuxStream)) (r7 (testShRunCmd!)) (r8 (testOobStreamDemuxMemoryBound))] (and r1 (and r2 (and r3 (and r4 (and r5 (and r6 (and r7 r8))))))))
