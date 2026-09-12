(module asl-sh/reducer
  :d "Pure ASL stream reducer: ANSI stripping, carriage return collapsing, duplicate-line suppression, head/tail windowing, and semantic diagnostic extraction."
  :x [ReductionConfig
      ReducedStream
      SkeletonSection
      OutputSkeleton
      default-config
      window-lines
      dedup-lines
      reduce-lines
      reduce-stream
      reduce-text
      truncate-summary
      generate-spool-path
      extract-error-summary
      demux-stream
      extract-output-skeleton
      skeleton-has-errors?
      format-output-skeleton]
  :i [(ansi :a ansi)
      (diagnostics :a diag)
      (asl-sh/process :a proc)])

(dfs ReductionConfig
  (:f head-limit Int64 "Maximum lines retained at stream head (default 500)")
  (:f tail-limit Int64 "Maximum lines retained at stream tail (default 1500)")
  (:f dedup-repeats Bool "Whether consecutive identical lines are collapsed with a repeat marker"))

(dfs ReducedStream
  (:f raw-line-count Int64 "Original line count before windowing and deduplication")
  (:f reduced-line-count Int64 "Line count in the final reduced stream")
  (:f evicted-line-count Int64 "Count of lines evicted from the middle (0 if no eviction)")
  (:f lines (List String) "Retained stream lines")
  (:f text String "Complete reduced text joined by newlines")
  (:f diagnostics diag/DiagnosticSummary "Structured compiler and test diagnostics"))

(dfs SkeletonSection
  (:f title String "Section title or milestone identifier")
  (:f start-line Int64 "1-based starting line number")
  (:f end-line Int64 "1-based ending line number")
  (:f line-count Int64 "Number of lines in section")
  (:f has-error Bool "True if section contains errors or failures"))

(dfs OutputSkeleton
  (:f total-lines Int64 "Total number of lines in raw stream")
  (:f total-bytes Int64 "Total size of raw stream in bytes")
  (:f sections (List SkeletonSection) "Logical sections identified in stream")
  (:f diagnostics (List diag/Diagnostic) "Extracted compiler and test diagnostics")
  (:f summary String "Ultra-compact one-line summary"))

(dfs SectionBuilderState
  (:f current-title String "Title of currently open section")
  (:f start-line Int64 "1-based starting line of open section")
  (:f current-line Int64 "Current line index being scanned")
  (:f has-err Bool "Whether current section encountered an error")
  (:f completed (List SkeletonSection) "Completed sections in reverse order"))

(df default-config [] -> ReductionConfig
  :d "Creates default ReductionConfig with 500 head lines, 1500 tail lines, and repeat deduplication enabled."
  (ReductionConfig
    :head-limit 500
    :tail-limit 1500
    :dedup-repeats true))

(df window-lines [(lines (List String)) (head-limit Int64) (tail-limit Int64)] -> (Pair (List String) Int64)
  :d "Applies head/tail retention windowing, replacing evicted middle lines with an eviction marker."
  (let [(total (list-length lines))
        (capacity (+ head-limit tail-limit))]
    (if (<= total capacity)
        (pair lines 0)
        (let [(evicted (- total capacity))
              (marker (str "... [" (string-from-int64 evicted) " lines evicted from buffer] ..."))
              (head-part (if (> head-limit 0)
                             (option-or (list-slice lines 0 head-limit) (list))
                             (list)))
              (tail-start (- total tail-limit))
              (tail-part (if (> tail-limit 0)
                             (option-or (list-slice lines tail-start total) (list))
                             (list)))
              (combined (list-append head-part (list-cons marker tail-part)))]
          (pair combined evicted)))))

(dfs DedupState
  (:f prev-line String "Current candidate line being tracked for repeats")
  (:f repeat-count Int64 "Number of consecutive occurrences of prev-line seen so far")
  (:f acc (List String) "Reversed accumulated lines and repeat markers"))

(df dedup-step [(st DedupState) (line String)] -> DedupState
  :d "Processes one line in the consecutive duplicate-line suppression state machine."
  (let [(prev (.-prev-line st))
        (count (.-repeat-count st))
        (acc (.-acc st))]
    (if (= line prev)
        (DedupState
          :prev-line prev
          :repeat-count (+ count 1)
          :acc acc)
        (let [(with-marker (if (> count 1)
                               (let [(marker (str "  ... [repeated " (string-from-int64 (- count 1)) " more times] ..."))]
                                 (list-cons marker acc))
                               acc))]
          (DedupState
            :prev-line line
            :repeat-count 1
            :acc (list-cons line with-marker))))))

(df dedup-lines [(lines (List String))] -> (List String)
  :d "Suppresses consecutive identical lines by collapsing them with a repeat marker."
  (let [(n (list-length lines))]
    (if (<= n 1)
        lines
        (let [(first-line (option-or (list-head lines) ""))
              (rest-lines (option-or (list-tail lines) (list)))
              (init (DedupState
                      :prev-line first-line
                      :repeat-count 1
                      :acc (list first-line)))
              (fin (fold dedup-step init rest-lines))
              (final-acc (if (> (.-repeat-count fin) 1)
                             (let [(m (str "  ... [repeated " (string-from-int64 (- (.-repeat-count fin) 1)) " more times] ..."))]
                               (list-cons m (.-acc fin)))
                             (.-acc fin)))]
          (list-reverse final-acc)))))

(df reduce-lines [(lines (List String)) (cfg ReductionConfig)] -> (Pair (List String) Int64)
  :d "Performs line deduplication and head/tail windowing on a list of lines."
  (let [(deduped (if (.-dedup-repeats cfg)
                     (dedup-lines lines)
                     lines))]
    (window-lines deduped (.-head-limit cfg) (.-tail-limit cfg))))

(df reduce-stream [(raw-text String) (cfg ReductionConfig)] -> ReducedStream
  :d "Applies ANSI stripping, CR collapsing, deduplication, windowing, and diagnostic extraction to a text stream."
  (let [(cleaned (ansi/clean-terminal-text raw-text))
        (lines (string-split cleaned "\n"))
        (raw-count (list-length lines))
        (diags (diag/extract-diagnostics lines))
        (summary (diag/summarize-diagnostics diags))
        (window-res (reduce-lines lines cfg))
        (final-lines (.-first window-res))
        (evicted-count (.-second window-res))
        (reduced-count (list-length final-lines))
        (final-text (string-join final-lines "\n"))]
    (ReducedStream
      :raw-line-count raw-count
      :reduced-line-count reduced-count
      :evicted-line-count evicted-count
      :lines final-lines
      :text final-text
      :diagnostics summary)))

(df reduce-text [(raw-text String)] -> ReducedStream
  :d "Reduces a raw text stream using default reduction configuration."
  (reduce-stream raw-text (default-config)))

(df truncate-summary [(text String) (max-tokens Int64)] -> String
  :d "Truncates summary text to keep it strictly under max-tokens budget."
  (let [(max-chars (* max-tokens 4))
        (len (string-length text))]
    (if (<= len max-chars)
        text
        (let [(slice-len (if (> max-chars 3) (- max-chars 3) max-chars))
              (prefix (option-or (string-slice text 0 slice-len) text))]
          (str prefix "...")))))

(df generate-spool-path [(bin String) (nonce Int64)] -> String
  :d "Generates canonical ephemeral spool filesystem path with sanitized binary name."
  (let [(safe-bin (string-replace bin "/" "_"))]
    (str "/tmp/asl-proc-" safe-bin "-" (string-from-int64 nonce) ".spool")))

(df extract-error-summary [(stdout-text String) (stderr-text String) (exit-code Int64)] -> String
  :d "Extracts compact semantic diagnostic string (<50 tokens) from stdout and stderr."
  (if (= exit-code 0)
      "Command succeeded"
      (let [(err-cleaned (ansi/clean-terminal-text stderr-text))
            (out-cleaned (ansi/clean-terminal-text stdout-text))
            (err-lines (if (string-empty? err-cleaned) (list) (string-split err-cleaned "\n")))
            (out-lines (if (string-empty? out-cleaned) (list) (string-split out-cleaned "\n")))
            (diags (diag/extract-diagnostics (list-append err-lines out-lines)))]
        (if (> (list-length diags) 0)
            (let [(first-diag (option-or (list-head diags) (diag/Diagnostic :kind "error" :severity "error" :message "Process failed" :file "" :line 0 :col 0 :raw (list))))
                  (msg (.-message first-diag))
                  (loc (if (not (string-empty? (.-file first-diag)))
                           (str (.-file first-diag) ":" (string-from-int64 (.-line first-diag)) ": ")
                           ""))
                  (diag-str (str loc msg))]
              (truncate-summary diag-str 50))
            (let [(combined (if (not (string-empty? (string-trim err-cleaned))) err-cleaned out-cleaned))]
              (if (string-empty? (string-trim combined))
                  (str "Process failed with exit code " (string-from-int64 exit-code))
                  (let [(first-line (option-or (list-head (string-split combined "\n")) "Process failed"))
                        (trimmed-line (string-trim first-line))]
                    (if (string-empty? trimmed-line)
                        (str "Process failed with exit code " (string-from-int64 exit-code))
                        (truncate-summary trimmed-line 50)))))))))

(df demux-stream [(stdout-text String) (stderr-text String) (exit-code Int64) (duration-ms Int64) (spool-path String)] -> proc/ProcessReceipt
  :d "Demultiplexes raw process output into an ephemeral spool reference and a compact ProcessReceipt."
  (let [(summary (extract-error-summary stdout-text stderr-text exit-code))]
    (proc/make-process-receipt exit-code duration-ms 0 spool-path summary)))

(df is-section-header? [(line String)] -> Bool
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

(df is-error-line? [(line String)] -> Bool
  :d "Detects whether an individual log line contains an error or failure indicator."
  (let [(lower (string-to-lowercase line))]
    (or (string-contains? lower "error")
        (or (string-contains? lower "failed")
            (or (string-contains? lower "fatal")
                (string-contains? lower "panic"))))))

(df step-section [(st SectionBuilderState) (line String)] -> SectionBuilderState
  :d "Processes next line during section partitioning."
  (let [(next-idx (+ (.-current-line st) 1))]
    (if (is-section-header? line)
        (let [(completed-sec (SkeletonSection
                               :title (.-current-title st)
                               :start-line (.-start-line st)
                               :end-line (.-current-line st)
                               :line-count (+ (- (.-current-line st) (.-start-line st)) 1)
                               :has-error (.-has-err st)))
              (title (truncate-summary (string-trim line) 40))]
          (SectionBuilderState
            :current-title title
            :start-line next-idx
            :current-line next-idx
            :has-err (is-error-line? line)
            :completed (list-cons completed-sec (.-completed st))))
        (SectionBuilderState
          :current-title (.-current-title st)
          :start-line (.-start-line st)
          :current-line next-idx
          :has-err (or (.-has-err st) (is-error-line? line))
          :completed (.-completed st)))))

(df partition-sections [(lines (List String))] -> (List SkeletonSection)
  :d "Partitions lines into structural milestone sections."
  (if (list-empty? lines)
      (list)
      (let [(first-line (option-or (list-head lines) ""))
            (first-title (if (is-section-header? first-line)
                             (truncate-summary (string-trim first-line) 40)
                             "Initial Output"))
            (init-st (SectionBuilderState
                       :current-title first-title
                       :start-line 1
                       :current-line 1
                       :has-err (is-error-line? first-line)
                       :completed (list)))
            (rest-lines (option-or (list-tail lines) (list)))
            (fin (fold step-section init-st rest-lines))
            (final-sec (SkeletonSection
                         :title (.-current-title fin)
                         :start-line (.-start-line fin)
                         :end-line (.-current-line fin)
                         :line-count (+ (- (.-current-line fin) (.-start-line fin)) 1)
                         :has-error (.-has-err fin)))]
        (list-reverse (list-cons final-sec (.-completed fin))))))

(df build-skeleton-summary [(total-lines Int64) (sec-count Int64) (diags (List diag/Diagnostic))] -> String
  :d "Constructs compact one-line summary describing lines, sections, and failure count."
  (let [(diag-count (list-length diags))]
    (if (= diag-count 0)
        (str "Lines: " (string-from-int64 total-lines) " | Sections: " (string-from-int64 sec-count) " | Status: clean")
        (let [(first-d (option-or (list-head diags) (diag/Diagnostic :kind "" :severity "" :message "error" :file "" :line 0 :col 0 :raw (list))))
              (loc (if (string-empty? (.-file first-d)) "" (str (.-file first-d) ":" (string-from-int64 (.-line first-d)) " ")))]
          (str "Lines: " (string-from-int64 total-lines) " | Sections: " (string-from-int64 sec-count) " | Errors: " (string-from-int64 diag-count) " (" loc (truncate-summary (.-message first-d) 20) ")")))))

(df extract-output-skeleton [(raw-text String)] -> OutputSkeleton
  :d "Extracts structural sections, diagnostics, and high-SNR metadata outline from raw stream text."
  (if (string-empty? (string-trim raw-text))
      (OutputSkeleton
        :total-lines 0
        :total-bytes 0
        :sections (list)
        :diagnostics (list)
        :summary "Lines: 0 | Sections: 0 | Status: clean")
      (let [(cleaned (ansi/clean-terminal-text raw-text))
            (norm (string-replace cleaned "\r\n" "\n"))
            (trimmed (if (string-ends-with? norm "\n")
                         (option-or (string-slice norm 0 (- (string-length norm) 1)) norm)
                         norm))
            (lines (string-split trimmed "\n"))
            (total-lines (list-length lines))
            (total-bytes (string-length norm))
            (diags (diag/extract-diagnostics lines))
            (sections (partition-sections lines))
            (summary (build-skeleton-summary total-lines (list-length sections) diags))]
        (OutputSkeleton
          :total-lines total-lines
          :total-bytes total-bytes
          :sections sections
          :diagnostics diags
          :summary summary))))

(df skeleton-has-errors? [(skel OutputSkeleton)] -> Bool
  :d "Returns true if the output skeleton contains any diagnostics or failed sections."
  (or (> (list-length (.-diagnostics skel)) 0)
      (fold (fn [(acc Bool) (s SkeletonSection)] -> Bool (or acc (.-has-error s))) false (.-sections skel))))

(df format-output-skeleton [(skel OutputSkeleton)] -> String
  :d "Renders an ASCII structural table of sections and diagnostic coordinates."
  (let [(header (str "=== Output Skeleton (" (string-from-int64 (.-total-lines skel)) " lines, " (string-from-int64 (.-total-bytes skel)) " bytes) ===\n"))
        (sec-rows (map (fn [(s SkeletonSection)] -> String
                         (let [(err-tag (if (.-has-error s) " [FAIL]" " [OK]"))]
                           (str "  L" (string-from-int64 (.-start-line s)) "-L" (string-from-int64 (.-end-line s))
                                " (" (string-from-int64 (.-line-count s)) " lines)" err-tag " " (.-title s))))
                       (.-sections skel)))
        (body (string-join sec-rows "\n"))
        (summary-line (str "\nSummary: " (.-summary skel)))]
    (str header body summary-line)))

