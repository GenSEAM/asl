(module asl-sh/diagnostics
  :d "Pure ASL diagnostic parsing: Extracts structured compiler and test errors (rustc, tsc, python, pytest) from log streams."
  :x [Diagnostic
      DiagnosticSummary
      parse-file-loc
      extract-python-frame
      parse-tsc-diagnostic
      parse-pytest-diagnostic
      extract-diagnostics
      summarize-diagnostics
      scan-stream-diagnostics])

(dfs Diagnostic
  (:f kind String "Diagnostic source kind: rustc, tsc, python, pytest, generic")
  (:f severity String "Severity level: error, warning, failure")
  (:f message String "Primary diagnostic message text")
  (:f file String "Identified source file path, or empty string")
  (:f line Int64 "Identified 1-based line number, or 0")
  (:f col Int64 "Identified 1-based column number, or 0")
  (:f raw (List String) "Raw output lines associated with this diagnostic"))

(dfs DiagnosticSummary
  (:f errors Int64 "Total count of errors")
  (:f warnings Int64 "Total count of warnings")
  (:f failures Int64 "Total count of test failures")
  (:f diagnostics (List Diagnostic) "List of all extracted diagnostic records"))

(df parse-file-loc [(s String)] -> (Pair String (Pair Int64 Int64))
  :d "Parses a file:line:col or file:line string into a path and coordinates."
  (let [(parts (string-split s ":"))
        (n (list-length parts))]
    (cond
      ((>= n 3)
       (let [(f (option-or (list-get parts 0) ""))
             (l-str (option-or (list-get parts 1) ""))
             (c-str (option-or (list-get parts 2) ""))
             (l (option-or (string-to-int64 (string-trim l-str)) 0))
             (c (option-or (string-to-int64 (string-trim c-str)) 0))]
         (pair f (pair l c))))
      ((= n 2)
       (let [(f (option-or (list-get parts 0) ""))
             (l-str (option-or (list-get parts 1) ""))
             (l (option-or (string-to-int64 (string-trim l-str)) 0))]
         (pair f (pair l 0))))
      (:else
       (pair s (pair 0 0))))))

(df extract-python-frame [(line String)] -> (Pair String Int64)
  :d "Extracts file path and line number from a Python traceback File frame line."
  (let [(f (if (string-contains? line "File \"")
               (let [(after (option-or (list-get (string-split line "File \"") 1) ""))
                     (file-parts (string-split after "\""))]
                 (option-or (list-get file-parts 0) ""))
               ""))
        (l (if (string-contains? line ", line ")
               (let [(after-line (option-or (list-get (string-split line ", line ") 1) ""))
                     (line-num-str (option-or (list-get (string-split after-line ",") 0) ""))
                     (clean-num (option-or (list-get (string-split line-num-str " ") 0) ""))]
                 (option-or (string-to-int64 (string-trim clean-num)) 0))
               0))]
    (pair f l)))

(df parse-tsc-diagnostic [(line String)] -> (Option Diagnostic)
  :d "Parses a TypeScript compiler (tsc) diagnostic line if matched."
  (let [(is-err (string-contains? line " - error TS"))
        (is-warn (string-contains? line " - warning TS"))]
    (if (or is-err is-warn)
        (let [(marker (if is-err " - error TS" " - warning TS"))
              (sev (if is-err "error" "warning"))
              (halves (string-split line marker))
              (loc-str (string-trim (option-or (list-get halves 0) "")))
              (msg-tail (string-trim (option-or (list-get halves 1) "")))
              (loc (parse-file-loc loc-str))
              (msg (str "TS" msg-tail))]
          (some (Diagnostic
                  :kind "tsc"
                  :severity sev
                  :message msg
                  :file (.-first loc)
                  :line (.-first (.-second loc))
                  :col (.-second (.-second loc))
                  :raw (list line))))
        (none))))

(df parse-pytest-diagnostic [(line String)] -> (Option Diagnostic)
  :d "Parses a pytest test failure or error line if matched."
  (let [(is-failed (string-starts-with? line "FAILED "))
        (is-error (string-starts-with? line "ERROR "))]
    (if (or is-failed is-error)
        (let [(sev (if is-failed "failure" "error"))
              (lead-len (if is-failed 7 6))
              (body (option-or (string-slice line lead-len (string-length line)) ""))
              (dash-parts (string-split body " - "))
              (target (option-or (list-get dash-parts 0) ""))
              (msg (if (> (list-length dash-parts) 1)
                       (option-or (list-get dash-parts 1) "")
                       body))
              (file (option-or (list-get (string-split target "::") 0) target))]
          (some (Diagnostic
                  :kind "pytest"
                  :severity sev
                  :message msg
                  :file (string-trim file)
                  :line 0
                  :col 0
                  :raw (list line))))
        (none))))

(dfs DiagLoopState
  (:f in-tb Bool "True while collecting a Python traceback block")
  (:f tb-lines (List String) "Traceback lines in reverse order")
  (:f tb-file String "Last extracted file in traceback")
  (:f tb-line Int64 "Last extracted line in traceback")
  (:f pending-rustc (Option Diagnostic) "Rustc diagnostic awaiting source location line")
  (:f items (List Diagnostic) "Extracted diagnostics in reverse order"))

(df close-traceback [(st DiagLoopState) (err-msg String)] -> DiagLoopState
  :d "Closes an active Python traceback block and appends the resulting Diagnostic."
  (let [(raw-all (list-reverse (.-tb-lines st)))
        (d (Diagnostic
             :kind "python"
             :severity "error"
             :message err-msg
             :file (.-tb-file st)
             :line (.-tb-line st)
             :col 0
             :raw raw-all))]
    (DiagLoopState
      :in-tb false
      :tb-lines (list)
      :tb-file ""
      :tb-line 0
      :pending-rustc (.-pending-rustc st)
      :items (list-cons d (.-items st)))))

(df step-diagnostic [(st DiagLoopState) (line String)] -> DiagLoopState
  :d "Processes a single line within the diagnostic extraction loop."
  (if (.-in-tb st)
      (cond
        ((string-contains? line "File \"")
         (let [(frame (extract-python-frame line))]
           (DiagLoopState
             :in-tb true
             :tb-lines (list-cons line (.-tb-lines st))
             :tb-file (.-first frame)
             :tb-line (.-second frame)
             :pending-rustc (.-pending-rustc st)
             :items (.-items st))))
        ((or (string-starts-with? line " ") (string-starts-with? line "\t"))
         (DiagLoopState
           :in-tb true
           :tb-lines (list-cons line (.-tb-lines st))
           :tb-file (.-tb-file st)
           :tb-line (.-tb-line st)
           :pending-rustc (.-pending-rustc st)
           :items (.-items st)))
        ((string-contains? line "Error")
         (close-traceback (DiagLoopState
                            :in-tb true
                            :tb-lines (list-cons line (.-tb-lines st))
                            :tb-file (.-tb-file st)
                            :tb-line (.-tb-line st)
                            :pending-rustc (.-pending-rustc st)
                            :items (.-items st))
                          line))
        (:else
         (let [(closed (close-traceback st "Python Traceback"))]
           (step-diagnostic closed line))))
      (mt (.-pending-rustc st)
        ((some rd)
         (if (string-contains? line "--> ")
             (let [(loc-str (string-trim (option-or (list-get (string-split line "--> ") 1) "")))
                   (loc (parse-file-loc loc-str))
                   (resolved-d (Diagnostic
                                 :kind "rustc"
                                 :severity (.-severity rd)
                                 :message (.-message rd)
                                 :file (.-first loc)
                                 :line (.-first (.-second loc))
                                 :col (.-second (.-second loc))
                                 :raw (list-append (.-raw rd) (list line))))]
               (DiagLoopState
                 :in-tb false
                 :tb-lines (list)
                 :tb-file ""
                 :tb-line 0
                 :pending-rustc (none)
                 :items (list-cons resolved-d (.-items st))))
             (let [(flushed (DiagLoopState
                              :in-tb false
                              :tb-lines (list)
                              :tb-file ""
                              :tb-line 0
                              :pending-rustc (none)
                              :items (list-cons rd (.-items st))))]
               (step-diagnostic flushed line))))
        ((none)
         (cond
           ((string-starts-with? line "Traceback (most recent call last):")
            (DiagLoopState
              :in-tb true
              :tb-lines (list line)
              :tb-file ""
              :tb-line 0
              :pending-rustc (none)
              :items (.-items st)))
           ((or (string-starts-with? line "error[") (string-starts-with? line "error:"))
            (DiagLoopState
              :in-tb false
              :tb-lines (list)
              :tb-file ""
              :tb-line 0
              :pending-rustc (some (Diagnostic
                                     :kind "rustc"
                                     :severity "error"
                                     :message line
                                     :file ""
                                     :line 0
                                     :col 0
                                     :raw (list line)))
              :items (.-items st)))
           ((or (string-starts-with? line "warning[") (string-starts-with? line "warning:"))
            (DiagLoopState
              :in-tb false
              :tb-lines (list)
              :tb-file ""
              :tb-line 0
              :pending-rustc (some (Diagnostic
                                     :kind "rustc"
                                     :severity "warning"
                                     :message line
                                     :file ""
                                     :line 0
                                     :col 0
                                     :raw (list line)))
              :items (.-items st)))
           (:else
            (mt (parse-tsc-diagnostic line)
              ((some td)
               (DiagLoopState
                 :in-tb false
                 :tb-lines (list)
                 :tb-file ""
                 :tb-line 0
                 :pending-rustc (none)
                 :items (list-cons td (.-items st))))
              ((none)
               (mt (parse-pytest-diagnostic line)
                 ((some pd)
                  (DiagLoopState
                    :in-tb false
                    :tb-lines (list)
                    :tb-file ""
                    :tb-line 0
                    :pending-rustc (none)
                    :items (list-cons pd (.-items st))))
                 ((none)
                  (if (or (string-starts-with? line "fatal: ")
                          (string-starts-with? line "[ERROR] "))
                      (let [(gd (Diagnostic
                                  :kind "generic"
                                  :severity "error"
                                  :message line
                                  :file ""
                                  :line 0
                                  :col 0
                                  :raw (list line)))]
                        (DiagLoopState
                          :in-tb false
                          :tb-lines (list)
                          :tb-file ""
                          :tb-line 0
                          :pending-rustc (none)
                          :items (list-cons gd (.-items st))))
                      st)))))))))))

(df extract-diagnostics [(lines (List String))] -> (List Diagnostic)
  :d "Extracts all structured diagnostics from a list of output lines."
  (let [(init (DiagLoopState
                :in-tb false
                :tb-lines (list)
                :tb-file ""
                :tb-line 0
                :pending-rustc (none)
                :items (list)))
        (fin (fold step-diagnostic init lines))
        (with-rustc (mt (.-pending-rustc fin)
                      ((some rd) (list-cons rd (.-items fin)))
                      ((none) (.-items fin))))
        (final-items (if (.-in-tb fin)
                         (let [(raw-tb (list-reverse (.-tb-lines fin)))
                               (tb-d (Diagnostic
                                       :kind "python"
                                       :severity "error"
                                       :message "Python Traceback"
                                       :file (.-tb-file fin)
                                       :line (.-tb-line fin)
                                       :col 0
                                       :raw raw-tb))]
                           (list-cons tb-d with-rustc))
                         with-rustc))]
    (list-reverse final-items)))

(df summarize-diagnostics [(items (List Diagnostic))] -> DiagnosticSummary
  :d "Calculates error, warning, and failure counts for a list of diagnostics."
  (let [(counts (fold (fn [(acc (Pair Int64 (Pair Int64 Int64))) (d Diagnostic)] -> (Pair Int64 (Pair Int64 Int64))
                        (let [(errs (.-first acc))
                              (warns (.-first (.-second acc)))
                              (fails (.-second (.-second acc)))
                              (sev (.-severity d))]
                          (cond
                            ((= sev "error") (pair (+ errs 1) (pair warns fails)))
                            ((= sev "warning") (pair errs (pair (+ warns 1) fails)))
                            ((= sev "failure") (pair errs (pair warns (+ fails 1))))
                            (:else acc))))
                      (pair 0 (pair 0 0))
                      items))]
    (DiagnosticSummary
      :errors (.-first counts)
      :warnings (.-first (.-second counts))
      :failures (.-second (.-second counts))
      :diagnostics items)))

(df scan-stream-diagnostics [(text String)] -> DiagnosticSummary
  :d "Splits raw stream text into lines, extracts diagnostics, and returns a summary."
  (let [(norm (string-replace text "\r\n" "\n"))
        (lines (string-split norm "\n"))
        (diags (extract-diagnostics lines))]
    (summarize-diagnostics diags)))
