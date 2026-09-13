(module asl-sh/reducer
  :d "Pure ASL stream reducer: ANSI stripping, carriage return collapsing, duplicate-line suppression, head/tail windowing, and semantic diagnostic extraction."
  :x [ReductionConfig
      ReducedStream
      SkeletonSection
      OutputSkeleton
      defaultConfig
      windowLines
      dedupLines
      reduceLines
      reduceStream
      reduceText
      truncateSummary
      generateSpoolPath
      extractErrorSummary
      demuxStream
      extractOutputSkeleton
      skeletonHasErrors?
      formatOutputSkeleton]
  :i [(ansi :a ansi)
      (diagnostics :a diag)
      (asl-sh/process :a proc)])

(dfs ReductionConfig
  (:f headLimit Int64 "Maximum lines retained at stream head (default 500)")
  (:f tailLimit Int64 "Maximum lines retained at stream tail (default 1500)")
  (:f dedupRepeats Bool "Whether consecutive identical lines are collapsed with a repeat marker"))

(dfs ReducedStream
  (:f rawLineCount Int64 "Original line count before windowing and deduplication")
  (:f reducedLineCount Int64 "Line count in the final reduced stream")
  (:f evictedLineCount Int64 "Count of lines evicted from the middle (0 if no eviction)")
  (:f lines (List String) "Retained stream lines")
  (:f text String "Complete reduced text joined by newlines")
  (:f diagnostics diag/DiagnosticSummary "Structured compiler and test diagnostics"))

(dfs SkeletonSection
  (:f title String "Section title or milestone identifier")
  (:f startLine Int64 "1-based starting line number")
  (:f endLine Int64 "1-based ending line number")
  (:f lineCount Int64 "Number of lines in section")
  (:f hasError Bool "True if section contains errors or failures"))

(dfs OutputSkeleton
  (:f totalLines Int64 "Total number of lines in raw stream")
  (:f totalBytes Int64 "Total size of raw stream in bytes")
  (:f sections (List SkeletonSection) "Logical sections identified in stream")
  (:f diagnostics (List diag/Diagnostic) "Extracted compiler and test diagnostics")
  (:f summary String "Ultra-compact one-line summary"))

(dfs SectionBuilderState
  (:f currentTitle String "Title of currently open section")
  (:f startLine Int64 "1-based starting line of open section")
  (:f currentLine Int64 "Current line index being scanned")
  (:f hasErr Bool "Whether current section encountered an error")
  (:f completed (List SkeletonSection) "Completed sections in reverse order"))

(df defaultConfig [] -> ReductionConfig
  :d "Creates default ReductionConfig with 500 head lines, 1500 tail lines, and repeat deduplication enabled."
  (ReductionConfig
    :headLimit 500
    :tailLimit 1500
    :dedupRepeats true))

(df windowLines [(lines (List String)) (headLimit Int64) (tailLimit Int64)] -> (Pair (List String) Int64)
  :d "Applies head/tail retention windowing, replacing evicted middle lines with an eviction marker."
  (let [(total (list-length lines))
        (capacity (+ headLimit tailLimit))]
    (if (<= total capacity)
        (pair lines 0)
        (let [(evicted (- total capacity))
              (marker (str "... [" (string-from-int64 evicted) " lines evicted from buffer] ..."))
              (headPart (if (> headLimit 0)
                             (option-or (list-slice lines 0 headLimit) (list))
                             (list)))
              (tailStart (- total tailLimit))
              (tailPart (if (> tailLimit 0)
                             (option-or (list-slice lines tailStart total) (list))
                             (list)))
              (combined (list-append headPart (list-cons marker tailPart)))]
          (pair combined evicted)))))

(dfs DedupState
  (:f prevLine String "Current candidate line being tracked for repeats")
  (:f repeatCount Int64 "Number of consecutive occurrences of prev-line seen so far")
  (:f acc (List String) "Reversed accumulated lines and repeat markers"))

(df dedupStep [(st DedupState) (line String)] -> DedupState
  :d "Processes one line in the consecutive duplicate-line suppression state machine."
  (let [(prev (.-prevLine st))
        (count (.-repeatCount st))
        (acc (.-acc st))]
    (if (= line prev)
        (DedupState
          :prevLine prev
          :repeatCount (+ count 1)
          :acc acc)
        (let [(withMarker (if (> count 1)
                               (let [(marker (str "  ... [repeated " (string-from-int64 (- count 1)) " more times] ..."))]
                                 (list-cons marker acc))
                               acc))]
          (DedupState
            :prevLine line
            :repeatCount 1
            :acc (list-cons line withMarker))))))

(df dedupLines [(lines (List String))] -> (List String)
  :d "Suppresses consecutive identical lines by collapsing them with a repeat marker."
  (let [(n (list-length lines))]
    (if (<= n 1)
        lines
        (let [(firstLine (option-or (list-head lines) ""))
              (restLines (option-or (list-tail lines) (list)))
              (init (DedupState
                      :prevLine firstLine
                      :repeatCount 1
                      :acc (list firstLine)))
              (fin (fold dedupStep init restLines))
              (finalAcc (if (> (.-repeatCount fin) 1)
                             (let [(m (str "  ... [repeated " (string-from-int64 (- (.-repeatCount fin) 1)) " more times] ..."))]
                               (list-cons m (.-acc fin)))
                             (.-acc fin)))]
          (list-reverse finalAcc)))))

(df reduceLines [(lines (List String)) (cfg ReductionConfig)] -> (Pair (List String) Int64)
  :d "Performs line deduplication and head/tail windowing on a list of lines."
  (let [(deduped (if (.-dedupRepeats cfg)
                     (dedupLines lines)
                     lines))]
    (windowLines deduped (.-headLimit cfg) (.-tailLimit cfg))))

(df reduceStream [(rawText String) (cfg ReductionConfig)] -> ReducedStream
  :d "Applies ANSI stripping, CR collapsing, deduplication, windowing, and diagnostic extraction to a text stream."
  (let [(cleaned (ansi/cleanTerminalText rawText))
        (lines (string-split cleaned "\n"))
        (rawCount (list-length lines))
        (diags (diag/extractDiagnostics lines))
        (summary (diag/summarizeDiagnostics diags))
        (windowRes (reduceLines lines cfg))
        (finalLines (.-first windowRes))
        (evictedCount (.-second windowRes))
        (reducedCount (list-length finalLines))
        (finalText (string-join finalLines "\n"))]
    (ReducedStream
      :rawLineCount rawCount
      :reducedLineCount reducedCount
      :evictedLineCount evictedCount
      :lines finalLines
      :text finalText
      :diagnostics summary)))

(df reduceText [(rawText String)] -> ReducedStream
  :d "Reduces a raw text stream using default reduction configuration."
  (reduceStream rawText (defaultConfig)))

(df truncateSummary [(text String) (maxTokens Int64)] -> String
  :d "Truncates summary text to keep it strictly under max-tokens budget."
  (let [(maxChars (* maxTokens 4))
        (len (string-length text))]
    (if (<= len maxChars)
        text
        (let [(sliceLen (if (> maxChars 3) (- maxChars 3) maxChars))
              (prefix (option-or (string-slice text 0 sliceLen) text))]
          (str prefix "...")))))

(df generateSpoolPath [(bin String) (nonce Int64)] -> String
  :d "Generates canonical ephemeral spool filesystem path with sanitized binary name."
  (let [(safeBin (string-replace bin "/" "_"))]
    (str "/tmp/asl-proc-" safeBin "-" (string-from-int64 nonce) ".spool")))

(df extractErrorSummary [(stdoutText String) (stderrText String) (exitCode Int64)] -> String
  :d "Extracts compact semantic diagnostic string (<50 tokens) from stdout and stderr."
  (if (= exitCode 0)
      "Command succeeded"
      (let [(errCleaned (ansi/cleanTerminalText stderrText))
            (outCleaned (ansi/cleanTerminalText stdoutText))
            (errLines (if (string-empty? errCleaned) (list) (string-split errCleaned "\n")))
            (outLines (if (string-empty? outCleaned) (list) (string-split outCleaned "\n")))
            (diags (diag/extractDiagnostics (list-append errLines outLines)))]
        (if (> (list-length diags) 0)
            (let [(firstDiag (option-or (list-head diags) (diag/Diagnostic :kind "error" :severity "error" :message "Process failed" :file "" :line 0 :col 0 :raw (list))))
                  (msg (.-message firstDiag))
                  (loc (if (not (string-empty? (.-file firstDiag)))
                           (str (.-file firstDiag) ":" (string-from-int64 (.-line firstDiag)) ": ")
                           ""))
                  (diagStr (str loc msg))]
              (truncateSummary diagStr 50))
            (let [(combined (if (not (string-empty? (string-trim errCleaned))) errCleaned outCleaned))]
              (if (string-empty? (string-trim combined))
                  (str "Process failed with exit code " (string-from-int64 exitCode))
                  (let [(firstLine (option-or (list-head (string-split combined "\n")) "Process failed"))
                        (trimmedLine (string-trim firstLine))]
                    (if (string-empty? trimmedLine)
                        (str "Process failed with exit code " (string-from-int64 exitCode))
                        (truncateSummary trimmedLine 50)))))))))

(df demuxStream [(stdoutText String) (stderrText String) (exitCode Int64) (durationMs Int64) (spoolPath String)] -> proc/ProcessReceipt
  :d "Demultiplexes raw process output into an ephemeral spool reference and a compact ProcessReceipt."
  (let [(summary (extractErrorSummary stdoutText stderrText exitCode))]
    (proc/makeProcessReceipt exitCode durationMs 0 spoolPath summary)))

(df isSectionHeader? [(line String)] -> Bool
  :d "Detects whether a log line represents a structural section or milestone boundary."
  (let [(t (string-trim line))]
    (or (string-starts-with? t "--> ")
        (or (string-starts-with? t "=== ")
            (or (string-starts-with? t "--- ")
                (or (string-starts-with? t "### ")
                    (or (string-starts-with? t "## ")
                        (or (string-starts-with? t "[Phase ")
                            (or (string-starts-with? t "[Step ")
                                (or (string-starts-with? t "Step ")
                                    (or (string-starts-with? t "Phase ")
                                        (or (string-starts-with? t "Test suite ")
                                            (or (string-starts-with? t "[Config]")
                                                (string-starts-with? t "================================================================================"))))))))))))))

(df isErrorLine? [(line String)] -> Bool
  :d "Detects whether an individual log line contains an error or failure indicator."
  (let [(lower (stringToLowercase line))]
    (or (string-contains? lower "error")
        (or (string-contains? lower "failed")
            (or (string-contains? lower "fatal")
                (string-contains? lower "panic"))))))

(df stepSection [(st SectionBuilderState) (line String)] -> SectionBuilderState
  :d "Processes next line during section partitioning."
  (let [(nextIdx (+ (.-currentLine st) 1))]
    (if (isSectionHeader? line)
        (let [(completedSec (SkeletonSection
                               :title (.-currentTitle st)
                               :startLine (.-startLine st)
                               :endLine (.-currentLine st)
                               :lineCount (+ (- (.-currentLine st) (.-startLine st)) 1)
                               :hasError (.-hasErr st)))
              (title (truncateSummary (string-trim line) 40))]
          (SectionBuilderState
            :currentTitle title
            :startLine nextIdx
            :currentLine nextIdx
            :hasErr (isErrorLine? line)
            :completed (list-cons completedSec (.-completed st))))
        (SectionBuilderState
          :currentTitle (.-currentTitle st)
          :startLine (.-startLine st)
          :currentLine nextIdx
          :hasErr (or (.-hasErr st) (isErrorLine? line))
          :completed (.-completed st)))))

(df partitionSections [(lines (List String))] -> (List SkeletonSection)
  :d "Partitions lines into structural milestone sections."
  (if (list-empty? lines)
      (list)
      (let [(firstLine (option-or (list-head lines) ""))
            (firstTitle (if (isSectionHeader? firstLine)
                             (truncateSummary (string-trim firstLine) 40)
                             "Initial Output"))
            (initSt (SectionBuilderState
                       :currentTitle firstTitle
                       :startLine 1
                       :currentLine 1
                       :hasErr (isErrorLine? firstLine)
                       :completed (list)))
            (restLines (option-or (list-tail lines) (list)))
            (fin (fold stepSection initSt restLines))
            (finalSec (SkeletonSection
                         :title (.-currentTitle fin)
                         :startLine (.-startLine fin)
                         :endLine (.-currentLine fin)
                         :lineCount (+ (- (.-currentLine fin) (.-startLine fin)) 1)
                         :hasError (.-hasErr fin)))]
        (list-reverse (list-cons finalSec (.-completed fin))))))

(df buildSkeletonSummary [(totalLines Int64) (secCount Int64) (diags (List diag/Diagnostic))] -> String
  :d "Constructs compact one-line summary describing lines, sections, and failure count."
  (let [(diagCount (list-length diags))]
    (if (= diagCount 0)
        (str "Lines: " (string-from-int64 totalLines) " | Sections: " (string-from-int64 secCount) " | Status: clean")
        (let [(firstD (option-or (list-head diags) (diag/Diagnostic :kind "" :severity "" :message "error" :file "" :line 0 :col 0 :raw (list))))
              (loc (if (string-empty? (.-file firstD)) "" (str (.-file firstD) ":" (string-from-int64 (.-line firstD)) " ")))]
          (str "Lines: " (string-from-int64 totalLines) " | Sections: " (string-from-int64 secCount) " | Errors: " (string-from-int64 diagCount) " (" loc (truncateSummary (.-message firstD) 20) ")")))))

(df extractOutputSkeleton [(rawText String)] -> OutputSkeleton
  :d "Extracts structural sections, diagnostics, and high-SNR metadata outline from raw stream text."
  (if (string-empty? (string-trim rawText))
      (OutputSkeleton
        :totalLines 0
        :totalBytes 0
        :sections (list)
        :diagnostics (list)
        :summary "Lines: 0 | Sections: 0 | Status: clean")
      (let [(cleaned (ansi/cleanTerminalText rawText))
            (norm (string-replace cleaned "\r\n" "\n"))
            (trimmed (if (string-ends-with? norm "\n")
                         (option-or (string-slice norm 0 (- (string-length norm) 1)) norm)
                         norm))
            (lines (string-split trimmed "\n"))
            (totalLines (list-length lines))
            (totalBytes (string-length norm))
            (diags (diag/extractDiagnostics lines))
            (sections (partitionSections lines))
            (summary (buildSkeletonSummary totalLines (list-length sections) diags))]
        (OutputSkeleton
          :totalLines totalLines
          :totalBytes totalBytes
          :sections sections
          :diagnostics diags
          :summary summary))))

(df skeletonHasErrors? [(skel OutputSkeleton)] -> Bool
  :d "Returns true if the output skeleton contains any diagnostics or failed sections."
  (or (> (list-length (.-diagnostics skel)) 0)
      (fold (fn [(acc Bool) (s SkeletonSection)] -> Bool (or acc (.-hasError s))) false (.-sections skel))))

(df formatOutputSkeleton [(skel OutputSkeleton)] -> String
  :d "Renders an ASCII structural table of sections and diagnostic coordinates."
  (let [(header (str "=== Output Skeleton (" (string-from-int64 (.-totalLines skel)) " lines, " (string-from-int64 (.-totalBytes skel)) " bytes) ===\n"))
        (secRows (map (fn [(s SkeletonSection)] -> String
                         (let [(errTag (if (.-hasError s) " [FAIL]" " [OK]"))]
                           (str "  L" (string-from-int64 (.-startLine s)) "-L" (string-from-int64 (.-endLine s))
                                " (" (string-from-int64 (.-lineCount s)) " lines)" errTag " " (.-title s))))
                       (.-sections skel)))
        (body (string-join secRows "\n"))
        (summaryLine (str "\nSummary: " (.-summary skel)))]
    (str header body summaryLine)))

