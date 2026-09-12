(module asl-sh/reducer-test
  :d "Unit tests for ASL stream reducer, ANSI stripping, CR collapsing, windowing, and diagnostics extraction."
  :x [test-ansi-stripping
      test-cr-collapsing
      test-line-dedup
      test-retention-windowing
      test-diagnostic-extraction
      test-reduce-stream-integration
      run-tests]
  :i [(reducer :a red)
      (ansi :a ansi)
      (diagnostics :a diag)])

(df test-ansi-stripping [] -> Bool
  :d "Validates ANSI escape sequence removal across various terminal formats."
  (let [(c1 (ansi/strip-ansi "\u001b[31mRed Error\u001b[0m"))
        (c2 (ansi/strip-ansi "\u001b[1;32;40mGreen Bold\u001b[0m"))
        (c3 (ansi/strip-ansi "\u001b[2KLine Clear"))
        (c4 (ansi/strip-ansi "\u001b]0;Title Bar\u0007Window Title"))
        (c5 (ansi/strip-ansi "Clean No Escape"))]
    (assert (= c1 "Red Error") "Red error ANSI stripped")
    (assert (= c2 "Green Bold") "Green bold ANSI stripped")
    (assert (= c3 "Line Clear") "Line clear ANSI stripped")
    (assert (= c4 "Window Title") "Window title ANSI stripped")
    (assert (= c5 "Clean No Escape") "Plain text unaltered")
    true))

(df test-cr-collapsing [] -> Bool
  :d "Validates carriage return overwrite simulation for spinners and progress bars."
  (let [(spinner (ansi/collapse-cr-line "|\r/\r-\r\\"))
        (progress (ansi/collapse-cr-line "Progress: 10%\rProgress: 50%\rProgress: 100%"))
        (overwrite (ansi/collapse-cr-line "12345\rAB"))
        (crlf-norm (ansi/collapse-cr "Line 1\r\nLine 2\r\n"))
        (multiline (ansi/collapse-cr "Spinning\rFinished\nNext task\n"))]
    (assert (= spinner "\\") "Spinner collapsed to last glyph")
    (assert (= progress "Progress: 100%") "Progress bar collapsed to final percentage")
    (assert (= overwrite "AB345") "In-place overwrite emulated")
    (assert (= crlf-norm "Line 1\nLine 2\n") "CRLF normalized")
    (assert (= multiline "Finished\nNext task\n") "Multiline CR handled")
    true))

(df test-line-dedup [] -> Bool
  :d "Validates consecutive duplicate line suppression and repeat marker injection."
  (let [(uniq (red/dedup-lines (list "alpha" "beta" "gamma")))
        (dups (red/dedup-lines (list "alpha" "beta" "beta" "beta" "gamma")))
        (single (red/dedup-lines (list "lone")))]
    (assert (= (list-length uniq) 3) "Unique lines length 3")
    (assert (= (list-length dups) 4) "Deduplicated lines length 4")
    (assert (= (option-or (list-get dups 2) "") "  ... [repeated 2 more times] ...") "Repeat marker inserted")
    (assert (= (list-length single) 1) "Single line untouched")
    true))

(df test-retention-windowing [] -> Bool
  :d "Validates head/tail windowing and eviction marker insertion for oversized buffers."
  (let [(small-input (list "line 0" "line 1" "line 2"))
        (res-small (red/window-lines small-input 500 1500))
        (big-input (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"))
        (res-big (red/window-lines big-input 2 2))
        (lines-big (.-first res-big))
        (evicted-big (.-second res-big))]
    (assert (= (.-second res-small) 0) "Small input zero eviction")
    (assert (= (list-length (.-first res-small)) 3) "Small input retains all lines")
    (assert (= evicted-big 6) "Oversized input evicts 6 lines")
    (assert (= (list-length lines-big) 5) "Oversized input retains 2+1+2 lines")
    (assert (= (option-or (list-get lines-big 2) "") "... [6 lines evicted from buffer] ...") "Eviction marker present")
    true))

(df test-diagnostic-extraction [] -> Bool
  :d "Validates structured diagnostic extraction across tsc, rustc, pytest, and python tracebacks."
  (let [(sample-log (list
                      "[INFO] Building project..."
                      "src/index.ts:15:3 - error TS2322: Type 'string' is not assignable to type 'number'."
                      "error[E0382]: borrow of moved value: `v`"
                      "  --> src/main.rs:24:9"
                      "FAILED tests/test_math.py::test_add - AssertionError: assert 1 + 1 == 3"
                      "Traceback (most recent call last):"
                      "  File \"src/worker.py\", line 50, in process"
                      "    res = calc(x)"
                      "  File \"src/worker.py\", line 12, in calc"
                      "ZeroDivisionError: division by zero"
                      "[INFO] Build finished with errors."))
        (diags (diag/extract-diagnostics sample-log))
        (summary (diag/summarize-diagnostics diags))]
    (assert (= (.-errors summary) 3) "Summary contains 3 errors")
    (assert (= (.-failures summary) 1) "Summary contains 1 failure")
    (assert (= (.-warnings summary) 0) "Summary contains 0 warnings")
    (assert (= (list-length diags) 4) "Extracted 4 diagnostics")
    (let [(d-tsc (option-or (list-get diags 0) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
          (d-rust (option-or (list-get diags 1) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
          (d-pytest (option-or (list-get diags 2) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
          (d-py (option-or (list-get diags 3) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))]
      (assert (= (.-kind d-tsc) "tsc") "First diag is tsc")
      (assert (= (.-file d-tsc) "src/index.ts") "TSC file matches")
      (assert (= (.-line d-tsc) 15) "TSC line 15")
      (assert (= (.-col d-tsc) 3) "TSC col 3")
      (assert (= (.-kind d-rust) "rustc") "Second diag is rustc")
      (assert (= (.-file d-rust) "src/main.rs") "Rust file matches")
      (assert (= (.-line d-rust) 24) "Rust line 24")
      (assert (= (.-col d-rust) 9) "Rust col 9")
      (assert (= (.-kind d-pytest) "pytest") "Third diag is pytest")
      (assert (= (.-severity d-pytest) "failure") "Pytest severity failure")
      (assert (= (.-file d-pytest) "tests/test_math.py") "Pytest file matches")
      (assert (= (.-kind d-py) "python") "Fourth diag is python traceback")
      (assert (= (.-file d-py) "src/worker.py") "Python file matches")
      (assert (= (.-line d-py) 12) "Python line 12"))
    true))

(df test-reduce-stream-integration [] -> Bool
  :d "Validates full stream reduction pipeline combining ANSI, CR, dedup, windowing, and diagnostics."
  (let [(raw (str "\u001b[32m[INFO] Starting task...\u001b[0m\n"
                  "Compiling...\rCompiling: 50%\rCompiling: 100%\n"
                  "warning: unused variable: `temp`\n"
                  "  --> src/lib.rs:8:5\n"
                  "Processing batch...\n"
                  "Processing batch...\n"
                  "Processing batch...\n"
                  "FAILED tests/test_core.py::test_run - AssertionError: expected true\n"
                  "Finished.\n"))
        (cfg (red/ReductionConfig :head-limit 3 :tail-limit 2 :dedup-repeats true))
        (stream (red/reduce-stream raw cfg))]
    (assert (> (.-raw-line-count stream) 0) "Raw line count > 0")
    (assert (> (.-reduced-line-count stream) 0) "Reduced line count > 0")
    (assert (= (.-failures (.-diagnostics stream)) 1) "Diagnosed 1 failure")
    (assert (= (.-warnings (.-diagnostics stream)) 1) "Diagnosed 1 warning")
    true))

(df test-output-skeleton-clean [] -> Bool
  :d "Validates clean output skeleton generation with multiple sections."
  (let [(log (str "--> [1/3] Resolving dependencies\n"
                  "fetching crates...\n"
                  "--> [2/3] Compiling core\n"
                  "compiling module a\n"
                  "compiling module b\n"
                  "--> [3/3] Running tests\n"
                  "all tests passed.\n"))
        (skel (red/extract-output-skeleton log))]
    (assert (= (.-total-lines skel) 7) "Total lines equals 7")
    (assert (> (.-total-bytes skel) 50) "Total bytes recorded")
    (assert (= (list-length (.-sections skel)) 3) "Extracted 3 milestone sections")
    (assert (= (list-length (.-diagnostics skel)) 0) "Zero diagnostics in clean stream")
    (assert (not (red/skeleton-has-errors? skel)) "Clean stream has no errors")
    (let [(s1 (option-or (list-get (.-sections skel) 0) (red/SkeletonSection :title "" :start-line 0 :end-line 0 :line-count 0 :has-error false)))
          (s2 (option-or (list-get (.-sections skel) 1) (red/SkeletonSection :title "" :start-line 0 :end-line 0 :line-count 0 :has-error false)))
          (s3 (option-or (list-get (.-sections skel) 2) (red/SkeletonSection :title "" :start-line 0 :end-line 0 :line-count 0 :has-error false)))]
      (assert (= (.-start-line s1) 1) "Section 1 starts at line 1")
      (assert (= (.-end-line s1) 2) "Section 1 ends at line 2")
      (assert (= (.-start-line s2) 3) "Section 2 starts at line 3")
      (assert (= (.-end-line s2) 5) "Section 2 ends at line 5")
      (assert (= (.-start-line s3) 6) "Section 3 starts at line 6"))
    true))

(df test-output-skeleton-with-errors [] -> Bool
  :d "Validates output skeleton extraction with compilation error sections."
  (let [(log (str "--> [1/2] Compiling sources\n"
                  "src/index.ts:10:5 - error TS2322: Type mismatch\n"
                  "--> [2/2] Running tests\n"
                  "FAILED tests/unit_test.py::test_run - AssertionError\n"))
        (skel (red/extract-output-skeleton log))]
    (assert (= (list-length (.-sections skel)) 2) "Two sections identified")
    (assert (= (list-length (.-diagnostics skel)) 2) "Two diagnostics extracted")
    (assert (red/skeleton-has-errors? skel) "Skeleton reports errors")
    (let [(s1 (option-or (list-get (.-sections skel) 0) (red/SkeletonSection :title "" :start-line 0 :end-line 0 :line-count 0 :has-error false)))
          (s2 (option-or (list-get (.-sections skel) 1) (red/SkeletonSection :title "" :start-line 0 :end-line 0 :line-count 0 :has-error false)))]
      (assert (.-has-error s1) "Section 1 flagged with error")
      (assert (.-has-error s2) "Section 2 flagged with failure"))
    (let [(rendered (red/format-output-skeleton skel))]
      (assert (string-contains? rendered "Output Skeleton") "Formatted output contains header")
      (assert (string-contains? rendered "[FAIL]") "Formatted output contains fail marker"))
    true))

(df run-tests [] -> Bool
  :d "Runs all test suites for reducer, ANSI stripping, diagnostics extraction, and output skeleton."
  (and (test-ansi-stripping)
       (and (test-cr-collapsing)
            (and (test-line-dedup)
                 (and (test-retention-windowing)
                      (and (test-diagnostic-extraction)
                           (and (test-reduce-stream-integration)
                                (and (test-output-skeleton-clean)
                                     (test-output-skeleton-with-errors)))))))))
