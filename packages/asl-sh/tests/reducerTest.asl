(module asl-sh/reducerTest
  :d "Unit tests for ASL stream reducer, ANSI stripping, CR collapsing, windowing, and diagnostics extraction."
  :x [testAnsiStripping
      testCrCollapsing
      testLineDedup
      testRetentionWindowing
      testDiagnosticExtraction
      testReduceStreamIntegration
      runTests]
  :i [(reducer :a red)
      (ansi :a ansi)
      (diagnostics :a diag)])

(df testAnsiStripping [] -> Bool
  :d "Validates ANSI escape sequence removal across various terminal formats."
  (let [(c1 (ansi/stripAnsi "\u001b[31mRed Error\u001b[0m"))
        (c2 (ansi/stripAnsi "\u001b[1;32;40mGreen Bold\u001b[0m"))
        (c3 (ansi/stripAnsi "\u001b[2KLine Clear"))
        (c4 (ansi/stripAnsi "\u001b]0;Title Bar\u0007Window Title"))
        (c5 (ansi/stripAnsi "Clean No Escape"))]
    (assert (= c1 "Red Error") "Red error ANSI stripped")
    (assert (= c2 "Green Bold") "Green bold ANSI stripped")
    (assert (= c3 "Line Clear") "Line clear ANSI stripped")
    (assert (= c4 "Window Title") "Window title ANSI stripped")
    (assert (= c5 "Clean No Escape") "Plain text unaltered")
    true))

(df testCrCollapsing [] -> Bool
  :d "Validates carriage return overwrite simulation for spinners and progress bars."
  (let [(spinner (ansi/collapseCrLine "|\r/\r-\r\\"))
        (progress (ansi/collapseCrLine "Progress: 10%\rProgress: 50%\rProgress: 100%"))
        (overwrite (ansi/collapseCrLine "12345\rAB"))
        (crlfNorm (ansi/collapseCr "Line 1\r\nLine 2\r\n"))
        (multiline (ansi/collapseCr "Spinning\rFinished\nNext task\n"))]
    (assert (= spinner "\\") "Spinner collapsed to last glyph")
    (assert (= progress "Progress: 100%") "Progress bar collapsed to final percentage")
    (assert (= overwrite "AB345") "In-place overwrite emulated")
    (assert (= crlfNorm "Line 1\nLine 2\n") "CRLF normalized")
    (assert (= multiline "Finished\nNext task\n") "Multiline CR handled")
    true))

(df testLineDedup [] -> Bool
  :d "Validates consecutive duplicate line suppression and repeat marker injection."
  (let [(uniq (red/dedupLines (list "alpha" "beta" "gamma")))
        (dups (red/dedupLines (list "alpha" "beta" "beta" "beta" "gamma")))
        (single (red/dedupLines (list "lone")))]
    (assert (= (list-length uniq) 3) "Unique lines length 3")
    (assert (= (list-length dups) 4) "Deduplicated lines length 4")
    (assert (= (option-or (list-get dups 2) "") "  ... [repeated 2 more times] ...") "Repeat marker inserted")
    (assert (= (list-length single) 1) "Single line untouched")
    true))

(df testRetentionWindowing [] -> Bool
  :d "Validates head/tail windowing and eviction marker insertion for oversized buffers."
  (let [(smallInput (list "line 0" "line 1" "line 2"))
        (resSmall (red/windowLines smallInput 500 1500))
        (bigInput (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"))
        (resBig (red/windowLines bigInput 2 2))
        (linesBig (.-first resBig))
        (evictedBig (.-second resBig))]
    (assert (= (.-second resSmall) 0) "Small input zero eviction")
    (assert (= (list-length (.-first resSmall)) 3) "Small input retains all lines")
    (assert (= evictedBig 6) "Oversized input evicts 6 lines")
    (assert (= (list-length linesBig) 5) "Oversized input retains 2+1+2 lines")
    (assert (= (option-or (list-get linesBig 2) "") "... [6 lines evicted from buffer] ...") "Eviction marker present")
    true))

(df testDiagnosticExtraction [] -> Bool
  :d "Validates structured diagnostic extraction across tsc, rustc, pytest, and python tracebacks."
  (let [(sampleLog (list
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
        (diags (diag/extractDiagnostics sampleLog))
        (summary (diag/summarizeDiagnostics diags))]
    (assert (= (.-errors summary) 3) "Summary contains 3 errors")
    (assert (= (.-failures summary) 1) "Summary contains 1 failure")
    (assert (= (.-warnings summary) 0) "Summary contains 0 warnings")
    (assert (= (list-length diags) 4) "Extracted 4 diagnostics")
    (let [(dTsc (option-or (list-get diags 0) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
          (dRust (option-or (list-get diags 1) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
          (dPytest (option-or (list-get diags 2) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
          (dPy (option-or (list-get diags 3) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))]
      (assert (= (.-kind dTsc) "tsc") "First diag is tsc")
      (assert (= (.-file dTsc) "src/index.ts") "TSC file matches")
      (assert (= (.-line dTsc) 15) "TSC line 15")
      (assert (= (.-col dTsc) 3) "TSC col 3")
      (assert (= (.-kind dRust) "rustc") "Second diag is rustc")
      (assert (= (.-file dRust) "src/main.rs") "Rust file matches")
      (assert (= (.-line dRust) 24) "Rust line 24")
      (assert (= (.-col dRust) 9) "Rust col 9")
      (assert (= (.-kind dPytest) "pytest") "Third diag is pytest")
      (assert (= (.-severity dPytest) "failure") "Pytest severity failure")
      (assert (= (.-file dPytest) "tests/test_math.py") "Pytest file matches")
      (assert (= (.-kind dPy) "python") "Fourth diag is python traceback")
      (assert (= (.-file dPy) "src/worker.py") "Python file matches")
      (assert (= (.-line dPy) 12) "Python line 12"))
    true))

(df testReduceStreamIntegration [] -> Bool
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
        (cfg (red/ReductionConfig :headLimit 3 :tailLimit 2 :dedupRepeats true))
        (stream (red/reduceStream raw cfg))]
    (assert (> (.-rawLineCount stream) 0) "Raw line count > 0")
    (assert (> (.-reducedLineCount stream) 0) "Reduced line count > 0")
    (assert (= (.-failures (.-diagnostics stream)) 1) "Diagnosed 1 failure")
    (assert (= (.-warnings (.-diagnostics stream)) 1) "Diagnosed 1 warning")
    true))

(df testOutputSkeletonClean [] -> Bool
  :d "Validates clean output skeleton generation with multiple sections."
  (let [(log (str "--> [1/3] Resolving dependencies\n"
                  "fetching crates...\n"
                  "--> [2/3] Compiling core\n"
                  "compiling module a\n"
                  "compiling module b\n"
                  "--> [3/3] Running tests\n"
                  "all tests passed.\n"))
        (skel (red/extractOutputSkeleton log))]
    (assert (= (.-totalLines skel) 7) "Total lines equals 7")
    (assert (> (.-totalBytes skel) 50) "Total bytes recorded")
    (assert (= (list-length (.-sections skel)) 3) "Extracted 3 milestone sections")
    (assert (= (list-length (.-diagnostics skel)) 0) "Zero diagnostics in clean stream")
    (refute (red/skeletonHasErrors? skel) "Clean stream has no errors")
    (let [(s1 (option-or (list-get (.-sections skel) 0) (red/SkeletonSection :title "" :startLine 0 :endLine 0 :lineCount 0 :hasError false)))
          (s2 (option-or (list-get (.-sections skel) 1) (red/SkeletonSection :title "" :startLine 0 :endLine 0 :lineCount 0 :hasError false)))
          (s3 (option-or (list-get (.-sections skel) 2) (red/SkeletonSection :title "" :startLine 0 :endLine 0 :lineCount 0 :hasError false)))]
      (assert (= (.-startLine s1) 1) "Section 1 starts at line 1")
      (assert (= (.-endLine s1) 2) "Section 1 ends at line 2")
      (assert (= (.-startLine s2) 3) "Section 2 starts at line 3")
      (assert (= (.-endLine s2) 5) "Section 2 ends at line 5")
      (assert (= (.-startLine s3) 6) "Section 3 starts at line 6"))
    true))

(df testOutputSkeletonWithErrors [] -> Bool
  :d "Validates output skeleton extraction with compilation error sections."
  (let [(log (str "--> [1/2] Compiling sources\n"
                  "src/index.ts:10:5 - error TS2322: Type mismatch\n"
                  "--> [2/2] Running tests\n"
                  "FAILED tests/unit_test.py::test_run - AssertionError\n"))
        (skel (red/extractOutputSkeleton log))]
    (assert (= (list-length (.-sections skel)) 2) "Two sections identified")
    (assert (= (list-length (.-diagnostics skel)) 2) "Two diagnostics extracted")
    (assert (red/skeletonHasErrors? skel) "Skeleton reports errors")
    (let [(s1 (option-or (list-get (.-sections skel) 0) (red/SkeletonSection :title "" :startLine 0 :endLine 0 :lineCount 0 :hasError false)))
          (s2 (option-or (list-get (.-sections skel) 1) (red/SkeletonSection :title "" :startLine 0 :endLine 0 :lineCount 0 :hasError false)))]
      (assert (.-hasError s1) "Section 1 flagged with error")
      (assert (.-hasError s2) "Section 2 flagged with failure"))
    (let [(rendered (red/formatOutputSkeleton skel))]
      (assert (string-contains? rendered "Output Skeleton") "Formatted output contains header")
      (assert (string-contains? rendered "[FAIL]") "Formatted output contains fail marker"))
    true))

(df runTests [] -> Bool
  :d "Runs all test suites for reducer, ANSI stripping, diagnostics extraction, and output skeleton."
  (and (testAnsiStripping)
       (and (testCrCollapsing)
            (and (testLineDedup)
                 (and (testRetentionWindowing)
                      (and (testDiagnosticExtraction)
                           (and (testReduceStreamIntegration)
                                (and (testOutputSkeletonClean)
                                     (testOutputSkeletonWithErrors)))))))))
