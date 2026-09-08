(module asl-sh/git-diff
  :d "Pure AgentScript unified diff parser and token-optimized ASN diff summary codec."
  :x [GitDiffHunk
      GitDiffFile
      git-diff-parse
      git-diff-summary])

(dfs GitDiffHunk
  (:f old-start Int64 "Hunk line start in old file")
  (:f old-count Int64 "Hunk line count in old file")
  (:f new-start Int64 "Hunk line start in new file")
  (:f new-count Int64 "Hunk line count in new file")
  (:f lines (List String) "Hunk diff lines including context and changes"))

(dfs GitDiffFile
  (:f old-path String "Path to old file or empty string")
  (:f new-path String "Path to new file or empty string")
  (:f hunks (List GitDiffHunk) "List of hunks in this file diff")
  (:f additions Int64 "Total additions in this file diff")
  (:f deletions Int64 "Total deletions in this file diff"))

(dfs ParseState
  (:f files (List GitDiffFile) "Accumulated completed files in reverse order")
  (:f cur-old-path String "Current file old path")
  (:f cur-new-path String "Current file new path")
  (:f cur-hunks (List GitDiffHunk) "Accumulated hunks for current file in reverse order")
  (:f cur-additions Int64 "Additions count for current file")
  (:f cur-deletions Int64 "Deletions count for current file")
  (:f cur-hunk (Option GitDiffHunk) "Active hunk being collected")
  (:f has-file Bool "True if a file boundary has been seen"))

(df clean-diff-path [(raw String)] -> String
  :d "Cleans trailing tab metadata and whitespace from a diff file path."
  (let [(no-tab (if (string-contains? raw "\t")
                    (option-or (list-get (string-split raw "\t") 0) raw)
                    raw))]
    (string-trim no-tab)))

(df extract-diff-path [(line String) (prefix String)] -> String
  :d "Extracts and normalizes target file path from a diff header line."
  (let [(p-len (string-length prefix))
        (raw-tail (option-or (string-slice line p-len (string-length line)) ""))
        (trimmed (clean-diff-path raw-tail))]
    (cond
      ((string-starts-with? trimmed "a/")
       (option-or (string-slice trimmed 2 (string-length trimmed)) ""))
      ((string-starts-with? trimmed "b/")
       (option-or (string-slice trimmed 2 (string-length trimmed)) ""))
      (:else trimmed))))

(df parse-range-token [(tok String) (prefix String)] -> (Pair Int64 Int64)
  :d "Parses start and count from a diff range token such as -1,5 or +1."
  (let [(p-len (string-length prefix))
        (clean-tok (option-or (string-slice tok p-len (string-length tok)) ""))
        (nums (string-split clean-tok ","))
        (start-str (string-trim (option-or (list-get nums 0) "0")))
        (start-val (option-or (string-to-int64 start-str) 0))]
    (if (> (list-length nums) 1)
        (let [(count-str (string-trim (option-or (list-get nums 1) "0")))
              (count-val (option-or (string-to-int64 count-str) 0))]
          (pair start-val count-val))
        (pair start-val 1))))

(df find-token-with-prefix [(toks (List String)) (prefix String)] -> String
  :d "Finds the first token in a list starting with a specific prefix."
  (fold (fn [(acc String) (tok String)] -> String
          (if (string-empty? acc)
              (let [(t (string-trim tok))]
                (if (string-starts-with? t prefix) t ""))
              acc))
        ""
        toks))

(df parse-hunk-header [(line String)] -> (Option GitDiffHunk)
  :d "Parses a unified diff hunk header into a GitDiffHunk structure."
  (if (string-starts-with? line "@@ ")
      (let [(after-prefix (option-or (string-slice line 3 (string-length line)) ""))
            (parts (string-split after-prefix "@@"))]
        (if (>= (list-length parts) 2)
            (let [(range-str (string-trim (option-or (list-get parts 0) "")))
                  (toks (string-split range-str " "))
                  (old-tok (find-token-with-prefix toks "-"))
                  (new-tok (find-token-with-prefix toks "+"))]
              (if (and (not (string-empty? old-tok)) (not (string-empty? new-tok)))
                  (let [(old-range (parse-range-token old-tok "-"))
                        (new-range (parse-range-token new-tok "+"))]
                    (some (GitDiffHunk
                            :old-start (.-first old-range)
                            :old-count (.-second old-range)
                            :new-start (.-first new-range)
                            :new-count (.-second new-range)
                            :lines (list))))
                  (none)))
            (none)))
      (none)))

(df close-active-hunk [(h-opt (Option GitDiffHunk)) (hunks (List GitDiffHunk))] -> (List GitDiffHunk)
  :d "Closes currently active hunk by reversing accumulated lines and appending to hunk list."
  (mt h-opt
    ((some h)
     (let [(final-h (GitDiffHunk
                      :old-start (.-old-start h)
                      :old-count (.-old-count h)
                      :new-start (.-new-start h)
                      :new-count (.-new-count h)
                      :lines (list-reverse (.-lines h))))]
       (list-cons final-h hunks)))
    ((none) hunks)))

(df close-active-file [(st ParseState)] -> ParseState
  :d "Closes currently active file if present and adds it to accumulated file list."
  (if (.-has-file st)
      (let [(final-hunks (list-reverse (close-active-hunk (.-cur-hunk st) (.-cur-hunks st))))
            (f (GitDiffFile
                 :old-path (.-cur-old-path st)
                 :new-path (.-cur-new-path st)
                 :hunks final-hunks
                 :additions (.-cur-additions st)
                 :deletions (.-cur-deletions st)))]
        (ParseState
          :files (list-cons f (.-files st))
          :cur-old-path ""
          :cur-new-path ""
          :cur-hunks (list)
          :cur-additions 0
          :cur-deletions 0
          :cur-hunk (none)
          :has-file false))
      st))

(df handle-diff-git [(st ParseState) (line String)] -> ParseState
  :d "Handles diff git header line starting a new file."
  (let [(s0 (close-active-file st))
        (parts (string-split line " "))
        (p-old (if (>= (list-length parts) 4)
                   (let [(raw (option-or (list-get parts 2) ""))]
                     (if (string-starts-with? raw "a/")
                         (option-or (string-slice raw 2 (string-length raw)) "")
                         raw))
                   ""))
        (p-new (if (>= (list-length parts) 4)
                   (let [(raw (option-or (list-get parts 3) ""))]
                     (if (string-starts-with? raw "b/")
                         (option-or (string-slice raw 2 (string-length raw)) "")
                         raw))
                   ""))]
    (ParseState
      :files (.-files s0)
      :cur-old-path p-old
      :cur-new-path p-new
      :cur-hunks (list)
      :cur-additions 0
      :cur-deletions 0
      :cur-hunk (none)
      :has-file true)))

(df handle-old-path [(st ParseState) (line String)] -> ParseState
  :d "Handles old file path line."
  (let [(needs-close (and (.-has-file st)
                          (or (not (list-empty? (.-cur-hunks st)))
                              (mt (.-cur-hunk st) ((some _) true) ((none) false)))))
        (s0 (if needs-close (close-active-file st) st))
        (old-p (extract-diff-path line "--- "))]
    (ParseState
      :files (.-files s0)
      :cur-old-path old-p
      :cur-new-path (.-cur-new-path s0)
      :cur-hunks (.-cur-hunks s0)
      :cur-additions (.-cur-additions s0)
      :cur-deletions (.-cur-deletions s0)
      :cur-hunk (.-cur-hunk s0)
      :has-file true)))

(df handle-new-path [(st ParseState) (line String)] -> ParseState
  :d "Handles new file path line."
  (let [(new-p (extract-diff-path line "+++ "))]
    (ParseState
      :files (.-files st)
      :cur-old-path (.-cur-old-path st)
      :cur-new-path new-p
      :cur-hunks (.-cur-hunks st)
      :cur-additions (.-cur-additions st)
      :cur-deletions (.-cur-deletions st)
      :cur-hunk (.-cur-hunk st)
      :has-file true)))

(df handle-hunk-head [(st ParseState) (line String)] -> ParseState
  :d "Handles hunk header line starting a new hunk."
  (let [(hunks1 (close-active-hunk (.-cur-hunk st) (.-cur-hunks st)))
        (new-hunk (parse-hunk-header line))]
    (ParseState
      :files (.-files st)
      :cur-old-path (.-cur-old-path st)
      :cur-new-path (.-cur-new-path st)
      :cur-hunks hunks1
      :cur-additions (.-cur-additions st)
      :cur-deletions (.-cur-deletions st)
      :cur-hunk new-hunk
      :has-file true)))

(df handle-hunk-line [(st ParseState) (line String) (h GitDiffHunk)] -> ParseState
  :d "Appends a line into the active hunk updating additions and deletions counts."
  (let [(is-add (and (string-starts-with? line "+") (not (string-starts-with? line "+++"))))
        (is-del (and (string-starts-with? line "-") (not (string-starts-with? line "---"))))
        (h2 (GitDiffHunk
              :old-start (.-old-start h)
              :old-count (.-old-count h)
              :new-start (.-new-start h)
              :new-count (.-new-count h)
              :lines (list-cons line (.-lines h))))
        (add-inc (if is-add 1 0))
        (del-inc (if is-del 1 0))]
    (ParseState
      :files (.-files st)
      :cur-old-path (.-cur-old-path st)
      :cur-new-path (.-cur-new-path st)
      :cur-hunks (.-cur-hunks st)
      :cur-additions (+ (.-cur-additions st) add-inc)
      :cur-deletions (+ (.-cur-deletions st) del-inc)
      :cur-hunk (some h2)
      :has-file (.-has-file st))))

(df step-diff-line [(st ParseState) (line String)] -> ParseState
  :d "Processes one line of unified diff input updating parse state."
  (cond
    ((string-starts-with? line "diff --git ") (handle-diff-git st line))
    ((string-starts-with? line "--- ") (handle-old-path st line))
    ((string-starts-with? line "+++ ") (handle-new-path st line))
    ((string-starts-with? line "@@ ") (handle-hunk-head st line))
    (:else
     (mt (.-cur-hunk st)
       ((some h) (handle-hunk-line st line h))
       ((none) st)))))

(df git-diff-parse [(diff-text String)] -> (List GitDiffFile)
  :d "Parses unified diff text into a list of GitDiffFile records."
  (let [(trimmed (string-trim diff-text))]
    (if (string-empty? trimmed)
        (list)
        (let [(clean-text (string-replace diff-text "\r" ""))
              (lines (string-split clean-text "\n"))
              (init-st (ParseState
                         :files (list)
                         :cur-old-path ""
                         :cur-new-path ""
                         :cur-hunks (list)
                         :cur-additions 0
                         :cur-deletions 0
                         :cur-hunk (none)
                         :has-file false))
              (final-st (fold (fn [(s ParseState) (ln String)] -> ParseState
                                (step-diff-line s ln))
                              init-st
                              lines))
              (closed-st (close-active-file final-st))]
          (list-reverse (.-files closed-st))))))

(df sum-additions [(files (List GitDiffFile))] -> Int64
  :d "Sums all additions across a list of file diffs."
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (.-additions f))) 0 files))

(df sum-deletions [(files (List GitDiffFile))] -> Int64
  :d "Sums all deletions across a list of file diffs."
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (.-deletions f))) 0 files))

(df sum-hunks [(files (List GitDiffFile))] -> Int64
  :d "Sums all hunk counts across a list of file diffs."
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (list-length (.-hunks f)))) 0 files))

(df git-diff-summary [(files (List GitDiffFile))] -> String
  :d "Formats a list of GitDiffFile records into a compact ASN summary string."
  (let [(total-files (list-length files))
        (total-additions (sum-additions files))
        (total-deletions (sum-deletions files))
        (total-hunks (sum-hunks files))]
    (str "(:diff-summary :files " (string-from-int64 total-files)
         " :additions " (string-from-int64 total-additions)
         " :deletions " (string-from-int64 total-deletions)
         " :hunks " (string-from-int64 total-hunks) ")")))
