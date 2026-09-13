(module asl-sh/diagnostics
  :d "Pure ASL diagnostic parsing: Extracts structured compiler and test errors (rustc, tsc, python, pytest) from log streams."
  :x [Diagnostic
      DiagnosticSummary
      parseFileLoc
      extractPythonFrame
      parseTscDiagnostic
      parsePytestDiagnostic
      extractDiagnostics
      summarizeDiagnostics
      scanStreamDiagnostics])

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

(df parseFileLoc [(s String)] -> (Pair String (Pair Int64 Int64))
  :d "Parses a file:line:col or file:line string into a path and coordinates."
  (let [(parts (string-split s ":"))
        (n (list-length parts))]
    (cond
      ((>= n 3)
       (let [(f (option-or (list-get parts 0) ""))
             (lStr (option-or (list-get parts 1) ""))
             (cStr (option-or (list-get parts 2) ""))
             (l (option-or (string-to-int64 (string-trim lStr)) 0))
             (c (option-or (string-to-int64 (string-trim cStr)) 0))]
         (pair f (pair l c))))
      ((= n 2)
       (let [(f (option-or (list-get parts 0) ""))
             (lStr (option-or (list-get parts 1) ""))
             (l (option-or (string-to-int64 (string-trim lStr)) 0))]
         (pair f (pair l 0))))
      (:else
       (pair s (pair 0 0))))))

(df extractPythonFrame [(line String)] -> (Pair String Int64)
  :d "Extracts file path and line number from a Python traceback File frame line."
  (let [(f (if (string-contains? line "File \"")
               (let [(after (option-or (list-get (string-split line "File \"") 1) ""))
                     (fileParts (string-split after "\""))]
                 (option-or (list-get fileParts 0) ""))
               ""))
        (l (if (string-contains? line ", line ")
               (let [(afterLine (option-or (list-get (string-split line ", line ") 1) ""))
                     (lineNumStr (option-or (list-get (string-split afterLine ",") 0) ""))
                     (cleanNum (option-or (list-get (string-split lineNumStr " ") 0) ""))]
                 (option-or (string-to-int64 (string-trim cleanNum)) 0))
               0))]
    (pair f l)))

(df parseTscDiagnostic [(line String)] -> (Option Diagnostic)
  :d "Parses a TypeScript compiler (tsc) diagnostic line if matched."
  (let [(isErr (string-contains? line " - error TS"))
        (isWarn (string-contains? line " - warning TS"))]
    (if (or isErr isWarn)
        (let [(marker (if isErr " - error TS" " - warning TS"))
              (sev (if isErr "error" "warning"))
              (halves (string-split line marker))
              (locStr (string-trim (option-or (list-get halves 0) "")))
              (msgTail (string-trim (option-or (list-get halves 1) "")))
              (loc (parseFileLoc locStr))
              (msg (str "TS" msgTail))]
          (some (Diagnostic
                  :kind "tsc"
                  :severity sev
                  :message msg
                  :file (.-first loc)
                  :line (.-first (.-second loc))
                  :col (.-second (.-second loc))
                  :raw (list line))))
        (none))))

(df parsePytestDiagnostic [(line String)] -> (Option Diagnostic)
  :d "Parses a pytest test failure or error line if matched."
  (let [(isFailed (string-starts-with? line "FAILED "))
        (isError (string-starts-with? line "ERROR "))]
    (if (or isFailed isError)
        (let [(sev (if isFailed "failure" "error"))
              (leadLen (if isFailed 7 6))
              (body (option-or (string-slice line leadLen (string-length line)) ""))
              (dashParts (string-split body " - "))
              (target (option-or (list-get dashParts 0) ""))
              (msg (if (> (list-length dashParts) 1)
                       (option-or (list-get dashParts 1) "")
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
  (:f inTb Bool "True while collecting a Python traceback block")
  (:f tbLines (List String) "Traceback lines in reverse order")
  (:f tbFile String "Last extracted file in traceback")
  (:f tbLine Int64 "Last extracted line in traceback")
  (:f pendingRustc (Option Diagnostic) "Rustc diagnostic awaiting source location line")
  (:f items (List Diagnostic) "Extracted diagnostics in reverse order"))

(df closeTraceback [(st DiagLoopState) (errMsg String)] -> DiagLoopState
  :d "Closes an active Python traceback block and appends the resulting Diagnostic."
  (let [(rawAll (list-reverse (.-tbLines st)))
        (d (Diagnostic
             :kind "python"
             :severity "error"
             :message errMsg
             :file (.-tbFile st)
             :line (.-tbLine st)
             :col 0
             :raw rawAll))]
    (DiagLoopState
      :inTb false
      :tbLines (list)
      :tbFile ""
      :tbLine 0
      :pendingRustc (.-pendingRustc st)
      :items (list-cons d (.-items st)))))

(df stepDiagnostic [(st DiagLoopState) (line String)] -> DiagLoopState
  :d "Processes a single line within the diagnostic extraction loop."
  (if (.-inTb st)
      (cond
        ((string-contains? line "File \"")
         (let [(frame (extractPythonFrame line))]
           (DiagLoopState
             :inTb true
             :tbLines (list-cons line (.-tbLines st))
             :tbFile (.-first frame)
             :tbLine (.-second frame)
             :pendingRustc (.-pendingRustc st)
             :items (.-items st))))
        ((or (string-starts-with? line " ") (string-starts-with? line "\t"))
         (DiagLoopState
           :inTb true
           :tbLines (list-cons line (.-tbLines st))
           :tbFile (.-tbFile st)
           :tbLine (.-tbLine st)
           :pendingRustc (.-pendingRustc st)
           :items (.-items st)))
        ((string-contains? line "Error")
         (closeTraceback (DiagLoopState
                            :inTb true
                            :tbLines (list-cons line (.-tbLines st))
                            :tbFile (.-tbFile st)
                            :tbLine (.-tbLine st)
                            :pendingRustc (.-pendingRustc st)
                            :items (.-items st))
                          line))
        (:else
         (let [(closed (closeTraceback st "Python Traceback"))]
           (stepDiagnostic closed line))))
      (mt (.-pendingRustc st)
        ((some rd)
         (if (string-contains? line "--> ")
             (let [(locStr (string-trim (option-or (list-get (string-split line "--> ") 1) "")))
                   (loc (parseFileLoc locStr))
                   (resolvedD (Diagnostic
                                 :kind "rustc"
                                 :severity (.-severity rd)
                                 :message (.-message rd)
                                 :file (.-first loc)
                                 :line (.-first (.-second loc))
                                 :col (.-second (.-second loc))
                                 :raw (list-append (.-raw rd) (list line))))]
               (DiagLoopState
                 :inTb false
                 :tbLines (list)
                 :tbFile ""
                 :tbLine 0
                 :pendingRustc (none)
                 :items (list-cons resolvedD (.-items st))))
             (let [(flushed (DiagLoopState
                              :inTb false
                              :tbLines (list)
                              :tbFile ""
                              :tbLine 0
                              :pendingRustc (none)
                              :items (list-cons rd (.-items st))))]
               (stepDiagnostic flushed line))))
        ((none)
         (cond
           ((string-starts-with? line "Traceback (most recent call last):")
            (DiagLoopState
              :inTb true
              :tbLines (list line)
              :tbFile ""
              :tbLine 0
              :pendingRustc (none)
              :items (.-items st)))
           ((or (string-starts-with? line "error[") (string-starts-with? line "error:"))
            (DiagLoopState
              :inTb false
              :tbLines (list)
              :tbFile ""
              :tbLine 0
              :pendingRustc (some (Diagnostic
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
              :inTb false
              :tbLines (list)
              :tbFile ""
              :tbLine 0
              :pendingRustc (some (Diagnostic
                                     :kind "rustc"
                                     :severity "warning"
                                     :message line
                                     :file ""
                                     :line 0
                                     :col 0
                                     :raw (list line)))
              :items (.-items st)))
           (:else
            (mt (parseTscDiagnostic line)
              ((some td)
               (DiagLoopState
                 :inTb false
                 :tbLines (list)
                 :tbFile ""
                 :tbLine 0
                 :pendingRustc (none)
                 :items (list-cons td (.-items st))))
              ((none)
               (mt (parsePytestDiagnostic line)
                 ((some pd)
                  (DiagLoopState
                    :inTb false
                    :tbLines (list)
                    :tbFile ""
                    :tbLine 0
                    :pendingRustc (none)
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
                          :inTb false
                          :tbLines (list)
                          :tbFile ""
                          :tbLine 0
                          :pendingRustc (none)
                          :items (list-cons gd (.-items st))))
                      st)))))))))))

(df extractDiagnostics [(lines (List String))] -> (List Diagnostic)
  :d "Extracts all structured diagnostics from a list of output lines."
  (let [(init (DiagLoopState
                :inTb false
                :tbLines (list)
                :tbFile ""
                :tbLine 0
                :pendingRustc (none)
                :items (list)))
        (fin (fold stepDiagnostic init lines))
        (withRustc (mt (.-pendingRustc fin)
                      ((some rd) (list-cons rd (.-items fin)))
                      ((none) (.-items fin))))
        (finalItems (if (.-inTb fin)
                         (let [(rawTb (list-reverse (.-tbLines fin)))
                               (tbD (Diagnostic
                                       :kind "python"
                                       :severity "error"
                                       :message "Python Traceback"
                                       :file (.-tbFile fin)
                                       :line (.-tbLine fin)
                                       :col 0
                                       :raw rawTb))]
                           (list-cons tbD withRustc))
                         withRustc))]
    (list-reverse finalItems)))

(df summarizeDiagnostics [(items (List Diagnostic))] -> DiagnosticSummary
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

(df scanStreamDiagnostics [(text String)] -> DiagnosticSummary
  :d "Splits raw stream text into lines, extracts diagnostics, and returns a summary."
  (let [(norm (string-replace text "\r\n" "\n"))
        (lines (string-split norm "\n"))
        (diags (extractDiagnostics lines))]
    (summarizeDiagnostics diags)))
