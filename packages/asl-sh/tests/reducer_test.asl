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
  (let [(c1 (ansi/strip-ansi "\x1b[31mRed Error\x1b[0m"))
        (c2 (ansi/strip-ansi "\x1b[1;32;40mGreen Bold\x1b[0m"))
        (c3 (ansi/strip-ansi "\x1b[2KLine Clear"))
        (c4 (ansi/strip-ansi "\x1b]0;Title Bar\x07Window Title"))
        (c5 (ansi/strip-ansi "Clean No Escape"))]
    (and (= c1 "Red Error")
         (and (= c2 "Green Bold")
              (and (= c3 "Line Clear")
                   (and (= c4 "Window Title")
                        (= c5 "Clean No Escape")))))))

(df test-cr-collapsing [] -> Bool
  :d "Validates carriage return overwrite simulation for spinners and progress bars."
  (let [(spinner (ansi/collapse-cr-line "|\r/\r-\r\\"))
        (progress (ansi/collapse-cr-line "Progress: 10%\rProgress: 50%\rProgress: 100%"))
        (overwrite (ansi/collapse-cr-line "12345\rAB"))
        (crlf-norm (ansi/collapse-cr "Line 1\r\nLine 2\r\n"))
        (multiline (ansi/collapse-cr "Spinning\rFinished\nNext task\n"))]
    (and (= spinner "\\")
         (and (= progress "Progress: 100%")
              (and (= overwrite "AB345")
                   (and (= crlf-norm "Line 1\nLine 2\n")
                        (= multiline "Finished\nNext task\n")))))))

(df test-line-dedup [] -> Bool
  :d "Validates consecutive duplicate line suppression and repeat marker injection."
  (let [(uniq (red/dedup-lines (list "alpha" "beta" "gamma")))
        (dups (red/dedup-lines (list "alpha" "beta" "beta" "beta" "gamma")))
        (single (red/dedup-lines (list "lone")))]
    (and (= uniq (list "alpha" "beta" "gamma"))
         (and (= dups (list "alpha" "beta" "  ... [repeated 2 more times] ..." "gamma"))
              (= (list-length single) 1)))))

(df test-retention-windowing [] -> Bool
  :d "Validates head/tail windowing and eviction marker insertion for oversized buffers."
  (let [(small-input (list "line 0" "line 1" "line 2"))
        (res-small (red/window-lines small-input 500 1500))
        (big-input (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"))
        (res-big (red/window-lines big-input 2 2))
        (lines-big (.-first res-big))
        (evicted-big (.-second res-big))]
    (and (= (.-second res-small) 0)
         (and (= (list-length (.-first res-small)) 3)
              (and (= evicted-big 6)
                   (= lines-big (list "0" "1" "... [6 lines evicted from buffer] ..." "8" "9")))))))

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
    (and (= (.-errors summary) 3)
         (and (= (.-failures summary) 1)
              (and (= (.-warnings summary) 0)
                   (and (= (list-length diags) 4)
                        (let [(d-tsc (option-or (list-get diags 0) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
                              (d-rust (option-or (list-get diags 1) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
                              (d-pytest (option-or (list-get diags 2) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))
                              (d-py (option-or (list-get diags 3) (diag/Diagnostic :kind "" :severity "" :message "" :file "" :line 0 :col 0 :raw (list))))]
                          (and (= (.-kind d-tsc) "tsc")
                               (and (= (.-file d-tsc) "src/index.ts")
                                    (and (= (.-line d-tsc) 15)
                                         (and (= (.-col d-tsc) 3)
                                              (and (= (.-kind d-rust) "rustc")
                                                   (and (= (.-file d-rust) "src/main.rs")
                                                        (and (= (.-line d-rust) 24)
                                                             (and (= (.-col d-rust) 9)
                                                                  (and (= (.-kind d-pytest) "pytest")
                                                                       (and (= (.-severity d-pytest) "failure")
                                                                            (and (= (.-file d-pytest) "tests/test_math.py")
                                                                                 (and (= (.-kind d-py) "python")
                                                                                      (and (= (.-file d-py) "src/worker.py")
                                                                                           (= (.-line d-py) 12)))))))))))))))))))))

(df test-reduce-stream-integration [] -> Bool
  :d "Validates full stream reduction pipeline combining ANSI, CR, dedup, windowing, and diagnostics."
  (let [(raw (str "\x1b[32m[INFO] Starting task...\x1b[0m\n"
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
    (and (> (.-raw-line-count stream) 0)
         (and (> (.-reduced-line-count stream) 0)
              (and (= (.-failures (.-diagnostics stream)) 1)
                   (= (.-warnings (.-diagnostics stream)) 1))))))

(df run-tests [] -> Bool
  :d "Runs all test suites for reducer, ANSI stripping, and diagnostics extraction."
  (and (test-ansi-stripping)
       (and (test-cr-collapsing)
            (and (test-line-dedup)
                 (and (test-retention-windowing)
                      (and (test-diagnostic-extraction)
                           (test-reduce-stream-integration)))))))
