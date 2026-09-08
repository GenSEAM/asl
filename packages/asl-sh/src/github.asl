(module asl-sh/github
  :d "Pure AgentScript GitHub API and CLI transcoders, compact PR and Issue projections, CI rollups, and diff compaction."
  :x [GitHubPrSummary
      GitHubIssue
      GitHubCiCheck
      github-pr-parse
      github-issue-parse
      github-diff-compact
      github-ci-parse
      github-ci-rollup])

(dfs GitHubPrSummary
  (:f number Int64 "Pull request number")
  (:f title String "Pull request title")
  (:f author String "Pull request author login")
  (:f head String "Head branch reference")
  (:f base String "Base branch reference")
  (:f state String "Pull request state: OPEN, CLOSED, MERGED")
  (:f labels (List String) "List of PR label names")
  (:f additions Int64 "Number of lines added")
  (:f deletions Int64 "Number of lines deleted"))

(dfs GitHubIssue
  (:f number Int64 "Issue number")
  (:f title String "Issue title")
  (:f author String "Issue author login")
  (:f state String "Issue state: OPEN, CLOSED")
  (:f labels (List String) "List of issue label names")
  (:f assignees (List String) "List of assignee login handles")
  (:f comments-count Int64 "Total number of comments on the issue")
  (:f body String "Issue description body markdown"))

(dfs GitHubCiCheck
  (:f name String "Check or workflow job name")
  (:f status String "Check execution status: COMPLETED, IN_PROGRESS, QUEUED")
  (:f conclusion String "Check conclusion: SUCCESS, FAILURE, NEUTRAL, CANCELLED")
  (:f target-url String "URL pointing to check run details"))

(dfs ObjScanState
  (:f objects (List String) "Accumulated completed JSON objects in reverse order")
  (:f start-idx Int64 "Start character index of current object")
  (:f cur-idx Int64 "Current character index in scan")
  (:f depth Int64 "Brace nesting depth")
  (:f in-str Bool "True if inside double quoted string")
  (:f esc Bool "True if previous character was escape backslash"))

(dfs QuoteScanState
  (:f found (Option Int64) "Index of unescaped quote")
  (:f idx Int64 "Current character index")
  (:f esc Bool "True if previous char was backslash"))

(dfs DigitScanState
  (:f digits (List String) "Accumulated digit characters in reverse order")
  (:f done Bool "True when non-digit character encountered"))

(dfs LabelsScanState
  (:f idx Int64 "Scan index")
  (:f labels (List String) "Accumulated labels in reverse order"))

(dfs AssigneesScanState
  (:f idx Int64 "Scan index")
  (:f assignees (List String) "Accumulated assignees in reverse order"))

(dfs CompactHunk
  (:f range String "Compacted hunk range header")
  (:f deltas (List String) "Added and deleted delta lines"))

(dfs CompactFile
  (:f path String "Target file path")
  (:f additions Int64 "Additions count")
  (:f deletions Int64 "Deletions count")
  (:f hunks (List CompactHunk) "List of compacted hunks in file order"))

(dfs DiffScanState
  (:f files (List CompactFile) "Completed files in reverse order")
  (:f cur-path String "Current file path")
  (:f cur-adds Int64 "Current file additions count")
  (:f cur-dels Int64 "Current file deletions count")
  (:f cur-hunks (List CompactHunk) "Current file hunks in reverse order")
  (:f cur-range String "Current hunk range")
  (:f cur-deltas (List String) "Current hunk delta lines in reverse order")
  (:f in-hunk Bool "True if currently inside a hunk")
  (:f in-file Bool "True if currently inside a file"))

(df split-json-objects [(text String)] -> (List String)
  :d "Splits a JSON string containing an array of objects or a single object into individual object strings."
  (let [(trimmed (string-trim text))]
    (if (or (string-empty? trimmed) (or (= trimmed "[]") (= trimmed "{}")))
        (list)
        (let [(chars (string-chars trimmed))
              (init-st (ObjScanState
                         :objects (list)
                         :start-idx 0
                         :cur-idx 0
                         :depth 0
                         :in-str false
                         :esc false))
              (final-st (fold (fn [(st ObjScanState) (c String)] -> ObjScanState
                                (let [(cur (.-cur-idx st))
                                      (next-idx (+ cur 1))]
                                  (cond
                                    ((.-esc st)
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :start-idx (.-start-idx st)
                                       :cur-idx next-idx
                                       :depth (.-depth st)
                                       :in-str (.-in-str st)
                                       :esc false))
                                    ((= c "\\")
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :start-idx (.-start-idx st)
                                       :cur-idx next-idx
                                       :depth (.-depth st)
                                       :in-str (.-in-str st)
                                       :esc (.-in-str st)))
                                    ((= c "\"")
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :start-idx (.-start-idx st)
                                       :cur-idx next-idx
                                       :depth (.-depth st)
                                       :in-str (not (.-in-str st))
                                       :esc false))
                                    ((.-in-str st)
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :start-idx (.-start-idx st)
                                       :cur-idx next-idx
                                       :depth (.-depth st)
                                       :in-str true
                                       :esc false))
                                    ((= c "{")
                                     (let [(d (+ (.-depth st) 1))
                                           (s-idx (if (= (.-depth st) 0) cur (.-start-idx st)))]
                                       (ObjScanState
                                         :objects (.-objects st)
                                         :start-idx s-idx
                                         :cur-idx next-idx
                                         :depth d
                                         :in-str false
                                         :esc false)))
                                    ((= c "}")
                                     (let [(d (- (.-depth st) 1))]
                                       (if (= d 0)
                                           (let [(obj-str (option-or (string-slice trimmed (.-start-idx st) next-idx) ""))]
                                             (ObjScanState
                                               :objects (list-cons obj-str (.-objects st))
                                               :start-idx 0
                                               :cur-idx next-idx
                                               :depth 0
                                               :in-str false
                                               :esc false))
                                           (ObjScanState
                                             :objects (.-objects st)
                                             :start-idx (.-start-idx st)
                                             :cur-idx next-idx
                                             :depth d
                                             :in-str false
                                             :esc false))))
                                    (:else
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :start-idx (.-start-idx st)
                                       :cur-idx next-idx
                                       :depth (.-depth st)
                                       :in-str false
                                       :esc false)))))
                              init-st
                              chars))]
          (if (= (.-depth final-st) 0)
              (list-reverse (.-objects final-st))
              (list))))))

(df json-find-key-tail [(obj String) (key String)] -> String
  :d "Finds the substring immediately following the colon for a specified JSON key."
  (let [(needle (str "\"" key "\""))]
    (mt (string-index-of obj needle)
      ((none) "")
      ((some idx)
       (let [(tail-pos (+ idx (string-length needle)))
             (tail (option-or (string-slice obj tail-pos (string-length obj)) ""))]
         (mt (string-index-of tail ":")
           ((none) "")
           ((some c-idx)
            (option-or (string-slice tail (+ c-idx 1) (string-length tail)) ""))))))))

(df find-unescaped-quote [(chars (List String))] -> (Option Int64)
  :d "Finds the first unescaped double quote character index in a list of characters."
  (let [(final-st (fold (fn [(st QuoteScanState) (c String)] -> QuoteScanState
                          (mt (.-found st)
                            ((some _) st)
                            ((none)
                             (let [(cur (.-idx st))
                                   (next (+ cur 1))]
                               (if (.-esc st)
                                   (QuoteScanState :found (none) :idx next :esc false)
                                   (if (= c "\\")
                                       (QuoteScanState :found (none) :idx next :esc true)
                                       (if (= c "\"")
                                           (QuoteScanState :found (some cur) :idx next :esc false)
                                           (QuoteScanState :found (none) :idx next :esc false))))))))
                        (QuoteScanState :found (none) :idx 0 :esc false)
                        chars))]
    (.-found final-st)))

(df json-extract-str [(obj String) (key String)] -> String
  :d "Extracts a string property value by key from a JSON object string."
  (let [(tail (string-trim (json-find-key-tail obj key)))]
    (if (string-starts-with? tail "\"")
        (let [(inner (option-or (string-slice tail 1 (string-length tail)) ""))
              (chars (string-chars inner))]
          (mt (find-unescaped-quote chars)
            ((some q-idx)
             (let [(raw-val (option-or (string-slice inner 0 q-idx) ""))]
               (string-replace (string-replace raw-val "\\\"" "\"") "\\n" "\n")))
            ((none) "")))
        "")))

(df is-digit-char? [(c String)] -> Bool
  :d "Returns true if character is a digit or minus sign."
  (or (= c "0")
      (or (= c "1")
          (or (= c "2")
              (or (= c "3")
                  (or (= c "4")
                      (or (= c "5")
                          (or (= c "6")
                              (or (= c "7")
                                  (or (= c "8")
                                      (or (= c "9")
                                          (= c "-"))))))))))))

(df extract-digits [(chars (List String))] -> String
  :d "Extracts leading digit sequence from character list."
  (let [(final-st (fold (fn [(st DigitScanState) (c String)] -> DigitScanState
                          (if (.-done st)
                              st
                              (if (is-digit-char? c)
                                  (DigitScanState :digits (list-cons c (.-digits st)) :done false)
                                  (DigitScanState :digits (.-digits st) :done true))))
                        (DigitScanState :digits (list) :done false)
                        chars))]
    (string-join (list-reverse (.-digits final-st)) "")))

(df json-extract-int [(obj String) (key String)] -> Int64
  :d "Extracts an integer property value by key from a JSON object string."
  (let [(tail (string-trim (json-find-key-tail obj key)))]
    (if (string-empty? tail)
        0
        (let [(chars (string-chars tail))
              (digits (extract-digits chars))]
          (if (string-empty? digits)
              0
              (option-or (string-to-int64 digits) 0))))))

(df json-extract-author [(obj String)] -> String
  :d "Extracts author login handle from JSON object supporting nested author or user objects."
  (let [(tail (string-trim (json-find-key-tail obj "author")))]
    (if (string-starts-with? tail "{")
        (let [(login (json-extract-str tail "login"))]
          (if (string-empty? login)
              (json-extract-str tail "name")
              login))
        (if (string-starts-with? tail "\"")
            (json-extract-str obj "author")
            (let [(user-tail (string-trim (json-find-key-tail obj "user")))]
              (if (string-starts-with? user-tail "{")
                  (json-extract-str user-tail "login")
                  (if (string-starts-with? user-tail "\"")
                      (json-extract-str obj "user")
                      "")))))))

(df json-extract-ref [(obj String) (ref-key String) (fallback-key String)] -> String
  :d "Extracts branch reference name with fallback to nested branch ref object."
  (let [(v1 (json-extract-str obj ref-key))]
    (if (not (string-empty? v1))
        v1
        (let [(tail (string-trim (json-find-key-tail obj fallback-key)))]
          (if (string-starts-with? tail "{")
              (json-extract-str tail "ref")
              (if (string-starts-with? tail "\"")
                  (json-extract-str obj fallback-key)
                  ""))))))

(df extract-labels-from-array-inner [(inner String)] -> (List String)
  :d "Extracts label name strings from inside a labels JSON array block."
  (if (string-contains? inner "\"name\"")
      (let [(parts (string-split inner "\"name\""))
            (labels-rev (fold (fn [(acc (List String)) (part String)] -> (List String)
                                (let [(tail (string-trim part))]
                                  (mt (string-index-of tail ":")
                                    ((none) acc)
                                    ((some c-idx)
                                     (let [(after-colon (string-trim (option-or (string-slice tail (+ c-idx 1) (string-length tail)) "")))]
                                       (if (string-starts-with? after-colon "\"")
                                           (let [(raw (option-or (string-slice after-colon 1 (string-length after-colon)) ""))
                                                 (q-idx (string-index-of raw "\""))]
                                             (mt q-idx
                                               ((some idx)
                                                (let [(label (option-or (string-slice raw 0 idx) ""))]
                                                  (if (string-empty? label) acc (list-cons label acc))))
                                               ((none) acc)))
                                           acc))))))
                              (list)
                              parts))]
        (list-reverse labels-rev))
      (let [(parts (string-split inner "\""))
            (labels-rev (fold (fn [(acc LabelsScanState) (part String)] -> LabelsScanState
                                (let [(idx (.-idx acc))
                                      (lst (.-labels acc))]
                                  (if (= (mod idx 2) 1)
                                      (let [(clean (string-trim part))]
                                        (if (string-empty? clean)
                                            (LabelsScanState :idx (+ idx 1) :labels lst)
                                            (LabelsScanState :idx (+ idx 1) :labels (list-cons clean lst))))
                                      (LabelsScanState :idx (+ idx 1) :labels lst))))
                              (LabelsScanState :idx 0 :labels (list))
                              parts))]
        (list-reverse (.-labels labels-rev)))))

(df json-extract-labels [(obj String)] -> (List String)
  :d "Extracts list of label names from a JSON object."
  (let [(tail (string-trim (json-find-key-tail obj "labels")))]
    (if (string-starts-with? tail "[")
        (let [(after-bracket (option-or (string-slice tail 1 (string-length tail)) ""))]
          (mt (string-index-of after-bracket "]")
            ((some end-idx)
             (let [(inner (option-or (string-slice after-bracket 0 end-idx) ""))]
               (extract-labels-from-array-inner inner)))
            ((none) (list))))
        (list))))

(df extract-assignees-from-array-inner [(inner String)] -> (List String)
  :d "Extracts assignee login strings from inside an assignees JSON array block."
  (if (string-contains? inner "\"login\"")
      (let [(parts (string-split inner "\"login\""))
            (assignees-rev (fold (fn [(acc (List String)) (part String)] -> (List String)
                                   (let [(tail (string-trim part))]
                                     (mt (string-index-of tail ":")
                                       ((none) acc)
                                       ((some c-idx)
                                        (let [(after-colon (string-trim (option-or (string-slice tail (+ c-idx 1) (string-length tail)) "")))]
                                          (if (string-starts-with? after-colon "\"")
                                              (let [(raw (option-or (string-slice after-colon 1 (string-length after-colon)) ""))
                                                    (q-idx (string-index-of raw "\""))]
                                                (mt q-idx
                                                  ((some idx)
                                                   (let [(login (option-or (string-slice raw 0 idx) ""))]
                                                     (if (string-empty? login) acc (list-cons login acc))))
                                                  ((none) acc)))
                                              acc))))))
                                 (list)
                                 parts))]
        (list-reverse assignees-rev))
      (let [(parts (string-split inner "\""))
            (assignees-rev (fold (fn [(acc AssigneesScanState) (part String)] -> AssigneesScanState
                                   (let [(idx (.-idx acc))
                                         (lst (.-assignees acc))]
                                     (if (= (mod idx 2) 1)
                                         (let [(clean (string-trim part))]
                                           (if (string-empty? clean)
                                               (AssigneesScanState :idx (+ idx 1) :assignees lst)
                                               (AssigneesScanState :idx (+ idx 1) :assignees (list-cons clean lst))))
                                         (AssigneesScanState :idx (+ idx 1) :assignees lst))))
                                 (AssigneesScanState :idx 0 :assignees (list))
                                 parts))]
        (list-reverse (.-assignees assignees-rev)))))

(df json-extract-assignees [(obj String)] -> (List String)
  :d "Extracts list of assignee login handles from a JSON object."
  (let [(tail (string-trim (json-find-key-tail obj "assignees")))]
    (if (string-starts-with? tail "[")
        (let [(after-bracket (option-or (string-slice tail 1 (string-length tail)) ""))]
          (mt (string-index-of after-bracket "]")
            ((some end-idx)
             (let [(inner (option-or (string-slice after-bracket 0 end-idx) ""))]
               (extract-assignees-from-array-inner inner)))
            ((none) (list))))
        (list))))

(df json-extract-comments-count [(obj String)] -> Int64
  :d "Extracts total comments count from issue JSON object."
  (let [(c1 (json-extract-int obj "commentsCount"))]
    (if (> c1 0)
        c1
        (let [(c2 (json-extract-int obj "comments_count"))]
          (if (> c2 0)
              c2
              (let [(tail (string-trim (json-find-key-tail obj "comments")))]
                (if (string-starts-with? tail "[")
                    (let [(after-bracket (option-or (string-slice tail 1 (string-length tail)) ""))]
                      (mt (string-index-of after-bracket "]")
                        ((some end-idx)
                         (let [(inner (option-or (string-slice after-bracket 0 end-idx) ""))
                               (objs (split-json-objects inner))]
                           (list-length objs)))
                        ((none) 0)))
                    0)))))))

(df truncate-body-lines [(body String) (max-lines Int64)] -> String
  :d "Truncates body text if it exceeds max-lines appending a truncation pointer notice."
  (let [(lines (string-split body "\n"))
        (total (list-length lines))]
    (if (> total max-lines)
        (let [(kept (option-or (list-slice lines 0 max-lines) (list)))
              (joined (string-join kept "\n"))]
          (str joined "\n... [truncated, " (string-from-int64 total) " lines total] ..."))
        body)))

(df parse-pr-summary [(obj String)] -> GitHubPrSummary
  :d "Parses a single JSON object string into a GitHubPrSummary record."
  (GitHubPrSummary
    :number (json-extract-int obj "number")
    :title (json-extract-str obj "title")
    :author (json-extract-author obj)
    :head (json-extract-ref obj "headRefName" "head")
    :base (json-extract-ref obj "baseRefName" "base")
    :state (json-extract-str obj "state")
    :labels (json-extract-labels obj)
    :additions (json-extract-int obj "additions")
    :deletions (json-extract-int obj "deletions")))

(df github-pr-parse [(json-str String)] -> (List GitHubPrSummary)
  :d "Parses GitHub PR list or view JSON into compact GitHubPrSummary records."
  (let [(objs (split-json-objects json-str))]
    (map (fn [(obj String)] -> GitHubPrSummary (parse-pr-summary obj)) objs)))

(df parse-issue [(obj String)] -> GitHubIssue
  :d "Parses a single JSON object string into a GitHubIssue record."
  (let [(raw-body (json-extract-str obj "body"))
        (capped-body (truncate-body-lines raw-body 1000))]
    (GitHubIssue
      :number (json-extract-int obj "number")
      :title (json-extract-str obj "title")
      :author (json-extract-author obj)
      :state (json-extract-str obj "state")
      :labels (json-extract-labels obj)
      :assignees (json-extract-assignees obj)
      :comments-count (json-extract-comments-count obj)
      :body capped-body)))

(df github-issue-parse [(json-str String)] -> (List GitHubIssue)
  :d "Parses GitHub issue list or view JSON into compact GitHubIssue records."
  (let [(objs (split-json-objects json-str))]
    (map (fn [(obj String)] -> GitHubIssue (parse-issue obj)) objs)))

(df extract-target-url [(obj String)] -> String
  :d "Extracts target or details URL from check run JSON object."
  (let [(u1 (json-extract-str obj "targetUrl"))]
    (if (not (string-empty? u1))
        u1
        (let [(u2 (json-extract-str obj "target_url"))]
          (if (not (string-empty? u2))
              u2
              (let [(u3 (json-extract-str obj "details_url"))]
                (if (not (string-empty? u3))
                    u3
                    (json-extract-str obj "url"))))))))

(df parse-ci-check [(obj String)] -> GitHubCiCheck
  :d "Parses a single JSON object string into a GitHubCiCheck record."
  (let [(conc (json-extract-str obj "conclusion"))
        (final-conc (if (string-empty? conc) (json-extract-str obj "state") conc))]
    (GitHubCiCheck
      :name (json-extract-str obj "name")
      :status (json-extract-str obj "status")
      :conclusion final-conc
      :target-url (extract-target-url obj))))

(df github-ci-parse [(json-str String)] -> (List GitHubCiCheck)
  :d "Parses GitHub CI check runs JSON into compact GitHubCiCheck records."
  (let [(objs (split-json-objects json-str))]
    (map (fn [(obj String)] -> GitHubCiCheck (parse-ci-check obj)) objs)))

(df is-failure-check? [(c GitHubCiCheck)] -> Bool
  :d "Returns true if a CI check has failed or timed out."
  (let [(conc (string-upper (.-conclusion c)))
        (st (string-upper (.-status c)))]
    (or (= conc "FAILURE")
        (or (= conc "FAILED")
            (or (= conc "TIMED_OUT")
                (or (= conc "ACTION_REQUIRED")
                    (= st "FAILURE")))))))

(df is-pending-check? [(c GitHubCiCheck)] -> Bool
  :d "Returns true if a CI check is currently in progress or queued."
  (let [(st (string-upper (.-status c)))
        (conc (string-upper (.-conclusion c)))]
    (or (= st "IN_PROGRESS")
        (or (= st "QUEUED")
            (or (= st "PENDING")
                (and (= st "COMPLETED") (string-empty? conc)))))))

(df github-ci-rollup [(checks (List GitHubCiCheck))] -> String
  :d "Computes aggregate CI status rollup verdict: :success, :failure, :pending."
  (if (list-empty? checks)
      ":success"
      (let [(has-fail (fold (fn [(acc Bool) (c GitHubCiCheck)] -> Bool (or acc (is-failure-check? c))) false checks))]
        (if has-fail
            ":failure"
            (let [(has-pend (fold (fn [(acc Bool) (c GitHubCiCheck)] -> Bool (or acc (is-pending-check? c))) false checks))]
              (if has-pend
                  ":pending"
                  ":success"))))))

(df clean-diff-path [(raw String)] -> String
  :d "Cleans file path prefixes and trailing tabs from diff lines."
  (let [(t (string-trim raw))]
    (if (string-starts-with? t "a/")
        (option-or (string-slice t 2 (string-length t)) "")
        (if (string-starts-with? t "b/")
            (option-or (string-slice t 2 (string-length t)) "")
            t))))

(df extract-hunk-range [(line String)] -> String
  :d "Extracts the @@ -start,count +start,count @@ range token from a hunk header line."
  (if (string-starts-with? line "@@ ")
      (let [(after-prefix (option-or (string-slice line 3 (string-length line)) ""))]
        (mt (string-index-of after-prefix "@@")
          ((some idx)
           (let [(range-inner (string-trim (option-or (string-slice after-prefix 0 idx) "")))]
             (str "@@ " range-inner " @@")))
          ((none) (string-trim line))))
      (string-trim line)))

(df close-active-hunk-state [(st DiffScanState)] -> DiffScanState
  :d "Closes active hunk if open and accumulates into cur-hunks."
  (if (.-in-hunk st)
      (let [(h (CompactHunk
                 :range (.-cur-range st)
                 :deltas (list-reverse (.-cur-deltas st))))]
        (DiffScanState
          :files (.-files st)
          :cur-path (.-cur-path st)
          :cur-adds (.-cur-adds st)
          :cur-dels (.-cur-dels st)
          :cur-hunks (list-cons h (.-cur-hunks st))
          :cur-range ""
          :cur-deltas (list)
          :in-hunk false
          :in-file (.-in-file st)))
      st))

(df close-active-file-state [(st DiffScanState)] -> DiffScanState
  :d "Closes active file if open and accumulates into files."
  (let [(s0 (close-active-hunk-state st))]
    (if (.-in-file s0)
        (let [(f (CompactFile
                   :path (.-cur-path s0)
                   :additions (.-cur-adds s0)
                   :deletions (.-cur-dels s0)
                   :hunks (list-reverse (.-cur-hunks s0))))]
          (DiffScanState
            :files (list-cons f (.-files s0))
            :cur-path ""
            :cur-adds 0
            :cur-dels 0
            :cur-hunks (list)
            :cur-range ""
            :cur-deltas (list)
            :in-hunk false
            :in-file false))
        s0)))

(df step-diff-line [(st DiffScanState) (line String)] -> DiffScanState
  :d "Processes a single line of unified diff input updating DiffScanState."
  (cond
    ((string-starts-with? line "diff --git ")
     (let [(s0 (close-active-file-state st))
           (parts (string-split line " "))
           (raw-path (if (>= (list-length parts) 4)
                         (option-or (list-get parts 3) "")
                         ""))
           (p (clean-diff-path raw-path))]
       (DiffScanState
         :files (.-files s0)
         :cur-path p
         :cur-adds 0
         :cur-dels 0
         :cur-hunks (list)
         :cur-range ""
         :cur-deltas (list)
         :in-hunk false
         :in-file true)))
    ((string-starts-with? line "--- ")
     (let [(raw (string-trim (option-or (string-slice line 4 (string-length line)) "")))]
       (if (and (not (.-in-file st)) (not (string-empty? raw)))
           (let [(p (clean-diff-path raw))]
             (DiffScanState
               :files (.-files st)
               :cur-path p
               :cur-adds 0
               :cur-dels 0
               :cur-hunks (list)
               :cur-range ""
               :cur-deltas (list)
               :in-hunk false
               :in-file true))
           st)))
    ((string-starts-with? line "+++ ")
     (let [(raw (string-trim (option-or (string-slice line 4 (string-length line)) "")))]
       (if (and (not (string-empty? raw)) (not (= raw "/dev/null")))
           (let [(p (clean-diff-path raw))]
             (DiffScanState
               :files (.-files st)
               :cur-path p
               :cur-adds (.-cur-adds st)
               :cur-dels (.-cur-dels st)
               :cur-hunks (.-cur-hunks st)
               :cur-range (.-cur-range st)
               :cur-deltas (.-cur-deltas st)
               :in-hunk (.-in-hunk st)
               :in-file true))
           st)))
    ((string-starts-with? line "@@ ")
     (let [(s0 (close-active-hunk-state st))
           (rng (extract-hunk-range line))]
       (DiffScanState
         :files (.-files s0)
         :cur-path (.-cur-path s0)
         :cur-adds (.-cur-adds s0)
         :cur-dels (.-cur-dels s0)
         :cur-hunks (.-cur-hunks s0)
         :cur-range rng
         :cur-deltas (list)
         :in-hunk true
         :in-file true)))
    (:else
     (if (.-in-hunk st)
         (let [(is-add (and (string-starts-with? line "+") (not (string-starts-with? line "+++"))))
               (is-del (and (string-starts-with? line "-") (not (string-starts-with? line "---"))))]
           (if (or is-add is-del)
               (let [(add-inc (if is-add 1 0))
                     (del-inc (if is-del 1 0))]
                 (DiffScanState
                   :files (.-files st)
                   :cur-path (.-cur-path st)
                   :cur-adds (+ (.-cur-adds st) add-inc)
                   :cur-dels (+ (.-cur-dels st) del-inc)
                   :cur-hunks (.-cur-hunks st)
                   :cur-range (.-cur-range st)
                   :cur-deltas (list-cons line (.-cur-deltas st))
                   :in-hunk true
                   :in-file true))
               st))
         st))))

(df format-compact-hunk [(h CompactHunk)] -> String
  :d "Formats a CompactHunk record into compact ASN hunk representation."
  (let [(quoted-deltas (map (fn [(d String)] -> String (str "\"" d "\"")) (.-deltas h)))
        (deltas-str (string-join quoted-deltas " "))]
    (str "(:hunk :range \"" (.-range h) "\" :deltas (" deltas-str "))")))

(df format-compact-file [(f CompactFile)] -> String
  :d "Formats a CompactFile record into compact ASN file diff representation."
  (let [(hunk-strs (map (fn [(h CompactHunk)] -> String (format-compact-hunk h)) (.-hunks f)))
        (hunks-body (string-join hunk-strs " "))]
    (str "(:file \"" (.-path f) "\" :+ " (string-from-int64 (.-additions f))
         " :- " (string-from-int64 (.-deletions f))
         " :hunks (" hunks-body "))")))

(df parse-compact-diff [(raw-diff String)] -> (List CompactFile)
  :d "Parses raw unified diff text into a list of CompactFile records."
  (let [(trimmed (string-trim raw-diff))]
    (if (string-empty? trimmed)
        (list)
        (let [(clean-text (string-replace raw-diff "\r" ""))
              (lines (string-split clean-text "\n"))
              (init-st (DiffScanState
                         :files (list)
                         :cur-path ""
                         :cur-adds 0
                         :cur-dels 0
                         :cur-hunks (list)
                         :cur-range ""
                         :cur-deltas (list)
                         :in-hunk false
                         :in-file false))
              (final-st (fold (fn [(s DiffScanState) (ln String)] -> DiffScanState
                                (step-diff-line s ln))
                              init-st
                              lines))
              (closed-st (close-active-file-state final-st))]
          (list-reverse (.-files closed-st))))))

(df github-diff-compact [(raw-diff String)] -> String
  :d "Compacts a raw unified diff by stripping index hashes and context lines into an ASN projection."
  (let [(files (parse-compact-diff raw-diff))]
    (if (list-empty? files)
        "(:pr-diff :files ())"
        (let [(file-strs (map (fn [(f CompactFile)] -> String (format-compact-file f)) files))
              (files-body (string-join file-strs " "))]
          (str "(:pr-diff :files (" files-body "))")))))
