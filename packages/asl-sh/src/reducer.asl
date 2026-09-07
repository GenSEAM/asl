(module asl-sh/reducer
  :d "Pure ASL stream reducer: ANSI stripping, carriage return collapsing, duplicate-line suppression, head/tail windowing, and semantic diagnostic extraction."
  :x [ReductionConfig
      ReducedStream
      default-config
      window-lines
      dedup-lines
      reduce-lines
      reduce-stream
      reduce-text
      truncate-summary
      generate-spool-path
      extract-error-summary
      demux-stream]
  :i [(ansi :a ansi)
      (diagnostics :a diag)
      (core/process :a proc)])

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

