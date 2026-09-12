(module asl-sh/apm-test
  :d "Falsifiable test suite for APM stream demultiplexer and ProcessReceipt token budget ceiling."
  :x [test-oob-stream-demux-memory-bound
      run-tests]
  :i [(asl-sh/process :a proc)
      (reducer      :a red)
      (sh           :a sh)
      (apm          :a apm)])

(df test-receipt-structure [] -> Bool
  :d "Verifies ProcessReceipt record structure and field extraction."
  (let [(r (proc/make-process-receipt 0 120 32 "/tmp/asl-proc-build-1.spool" "Build succeeded"))]
    (assert (= (.-exit-code r) 0) "Exit code must be 0")
    (assert (= (.-duration-ms r) 120) "Duration must match 120ms")
    (assert (= (.-peak-rss-mb r) 32) "Peak RSS must match 32MB")
    (assert (= (.-spool-path r) "/tmp/asl-proc-build-1.spool") "Spool path must match")
    (assert (= (.-summary r) "Build succeeded") "Summary must match")
    true))

(df test-token-ceiling [] -> Bool
  :d "Verifies that ProcessReceipt stays strictly under 80 BPE tokens even with large outputs."
  (let [(huge-out (str "line 1\nline 2\nline 3\nline 4\nline 5\n"
                       "warning: unused variable\n"
                       "error[E0382]: borrow of moved value: `v`\n  --> src/main.rs:24:9\n"
                       "error: aborting due to previous error\n"))
        (r (red/demux-stream huge-out "" 1 450 "/tmp/asl-proc-cargo-99.spool"))
        (rendered (proc/render-receipt r))
        (toks (proc/receipt-tokens r))]
    (assert (< toks 80) "ProcessReceipt must consume strictly under 80 tokens")
    (assert (> toks 0) "ProcessReceipt token count must be positive")
    (assert (string-contains? rendered ":proc-receipt") "Rendered receipt must have ASN header")
    (assert (= (.-exit-code r) 1) "Exit code 1 must be preserved")
    true))

(df test-summary-truncation [] -> Bool
  :d "Verifies that oversized diagnostic messages are truncated to 50 tokens with ellipsis suffix."
  (let [(long-msg (str "Very long diagnostic error message exceeding the token budget ceiling with extensive compiler output "
                       "including symbol traces, memory layouts, register contents, stack unwinding frames, "
                       "type deduction failures, lifetime constraint mismatches, template expansion depths, "
                       "and diagnostic context that would otherwise degrade agent prompt token efficiency."))
        (truncated (red/truncate-summary long-msg 50))
        (r (red/demux-stream "" long-msg 1 100 "/tmp/asl-proc-err-1.spool"))]
    (assert (> (string-length long-msg) 300) "Test input message must exceed 300 characters")
    (assert (<= (string-length truncated) 200) "Truncated summary must be <= 200 characters")
    (assert (string-ends-with? truncated "...") "Truncated summary must end with ellipsis")
    (assert (string-ends-with? (.-summary r) "...") "Receipt summary must end with ellipsis")
    (assert (< (proc/receipt-tokens r) 80) "ProcessReceipt with truncated summary must remain strictly under 80 tokens")
    true))

(df test-error-extraction [] -> Bool
  :d "Verifies structured diagnostic message and location extraction from stderr/stdout."
  (let [(stdout-log "Compiling app...\nGenerating bundles...\n")
        (stderr-log "src/index.ts:42:5 - error TS2322: Type 'string' is not assignable to type 'number'.\n")
        (r (red/demux-stream stdout-log stderr-log 1 300 "/tmp/asl-proc-tsc-1.spool"))]
    (assert (= (.-exit-code r) 1) "Exit code must be 1")
    (assert (string-contains? (.-summary r) "TS2322") "Diagnostic code must be present in summary")
    (assert (string-contains? (.-summary r) "src/index.ts:42:") "File location must be extracted")
    true))

(df test-exit-preservation [] -> Bool
  :d "Verifies that zero and non-zero exit codes are preserved exactly, including empty stderr/stdout."
  (let [(r-ok (red/demux-stream "done" "" 0 10 "/tmp/asl-proc-echo-0.spool"))
        (r-oom (red/demux-stream "" "Killed\n" 137 5000 "/tmp/asl-proc-app-137.spool"))
        (r-timeout (red/demux-stream "" "Timed out\n" 124 10000 "/tmp/asl-proc-app-124.spool"))
        (r-empty (red/demux-stream "" "   \n  " 2 15 "/tmp/asl-proc-silent-2.spool"))]
    (assert (= (.-exit-code r-ok) 0) "Exit code 0 preserved")
    (assert (= (.-summary r-ok) "Command succeeded") "Success summary emitted")
    (assert (= (.-exit-code r-oom) 137) "Exit code 137 (OOM) preserved")
    (assert (= (.-exit-code r-timeout) 124) "Exit code 124 (Timeout) preserved")
    (assert (= (.-exit-code r-empty) 2) "Exit code 2 preserved")
    (assert (= (.-summary r-empty) "Process failed with exit code 2") "Empty output non-zero failure summary emitted")
    true))

(df test-demux-stream [] -> Bool
  :d "Verifies demux-stream ephemeral spool path generation and channel separation."
  (let [(spool (red/generate-spool-path "npm" 42))
        (spool-nested (red/generate-spool-path "/usr/bin/npm" 99))]
    (assert (string-starts-with? spool "/tmp/asl-proc-npm-") "Spool path prefix must match")
    (assert (string-ends-with? spool ".spool") "Spool path extension must be .spool")
    (assert (not (string-contains? spool-nested "/tmp/asl-proc-/")) "Spool path must sanitize path separators")
    (assert (string-ends-with? spool-nested ".spool") "Sanitized spool path extension must be .spool")
    true))

(df test-sh-run-cmd [] -> Bool
  :d "Verifies that sh/run-cmd! returns a Result containing ProcessReceipt."
  (let [(res (sh/run-cmd! "echo" (list "hello")))]
    (mt res
      ((ok receipt)
       (assert (= (.-exit-code receipt) 0) "ProcessReceipt exit-code must be 0")
       (assert (< (proc/receipt-tokens receipt) 80) "Tokens must be <80")
       true)
      ((err _)
       (assert false "run-cmd! must succeed")
       false))))

(df test-oob-stream-demux-memory-bound [] -> Bool
  :d "Verifies that streaming 100MB of synthetic data through OobDemuxer is bounded < 64MB with clean termination."
  (let [(spool-path "/tmp/asl-proc-oob-100mb.spool")
        (demuxer0 (apm/make-oob-demuxer spool-path 67108864))
        (chunk-1mb (string-repeat "0123456789ABCDEF" 65536))
        (demuxer-100 (fold (fn [(d apm/OobDemuxer) (_i Int64)] -> apm/OobDemuxer
                             (apm/oob-demux-chunk d chunk-1mb))
                           demuxer0
                           (range 0 100)))
        (receipt (apm/oob-demux-finish demuxer-100 0 1200))]
    (assert (.-is-terminated demuxer-100) "Demuxer must be terminated after exceeding 64MB limit")
    (assert (= (.-termination-reason demuxer-100) ":buffer-overflow") "Termination reason must be :buffer-overflow")
    (assert (<= (.-buffer-bytes demuxer-100) 67108864) "Active in-flight buffer must be strictly bounded <= 64MB")
    (assert (= (.-total-bytes demuxer-100) 104857600) "Total processed bytes must equal exactly 100MB (104857600)")
    (assert (= (.-exit-code receipt) 137) "Terminated stream exit code must be 137")
    (assert (string-contains? (.-summary receipt) "memory bound < 64MB exceeded") "Summary must cite memory bound exceeded")
    (assert (< (proc/receipt-tokens receipt) 80) "ProcessReceipt tokens must be strictly < 80")
    true))

(df run-tests [] -> Bool
  :d "Executes all APM stream demultiplexer and ProcessReceipt test suites."
  (and (test-receipt-structure)
       (and (test-token-ceiling)
            (and (test-summary-truncation)
                 (and (test-error-extraction)
                      (and (test-exit-preservation)
                           (and (test-demux-stream)
                                (and (test-sh-run-cmd)
                                     (test-oob-stream-demux-memory-bound)))))))))
