(module asl-sh/github
  :d "Pure AgentScript GitHub API and CLI transcoders, compact PR and Issue projections, CI rollups, and diff compaction."
  :x [GitHubPrSummary
      GitHubIssue
      GitHubCiCheck
      githubPrParse
      githubIssueParse
      githubDiffCompact
      githubCiParse
      githubCiRollup
      githubPrsFormat
      githubIssuesFormat
      githubCiFormat])

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
  (:f commentsCount Int64 "Total number of comments on the issue")
  (:f body String "Issue description body markdown"))

(dfs GitHubCiCheck
  (:f name String "Check or workflow job name")
  (:f status String "Check execution status: COMPLETED, IN_PROGRESS, QUEUED")
  (:f conclusion String "Check conclusion: SUCCESS, FAILURE, NEUTRAL, CANCELLED")
  (:f targetUrl String "URL pointing to check run details"))

(dfs ObjScanState
  (:f objects (List String) "Accumulated completed JSON objects in reverse order")
  (:f startIdx Int64 "Start character index of current object")
  (:f curIdx Int64 "Current character index in scan")
  (:f depth Int64 "Brace nesting depth")
  (:f inStr Bool "True if inside double quoted string")
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
  (:f curPath String "Current file path")
  (:f curAdds Int64 "Current file additions count")
  (:f curDels Int64 "Current file deletions count")
  (:f curHunks (List CompactHunk) "Current file hunks in reverse order")
  (:f curRange String "Current hunk range")
  (:f curDeltas (List String) "Current hunk delta lines in reverse order")
  (:f inHunk Bool "True if currently inside a hunk")
  (:f inFile Bool "True if currently inside a file"))

(df splitJsonObjects [(text String)] -> (List String)
  :d "Splits a JSON string containing an array of objects or a single object into individual object strings."
  (let [(trimmed (string-trim text))]
    (if (or (string-empty? trimmed) (or (= trimmed "[]") (= trimmed "{}")))
        (list)
        (let [(chars (string-chars trimmed))
              (initSt (ObjScanState
                         :objects (list)
                         :startIdx 0
                         :curIdx 0
                         :depth 0
                         :inStr false
                         :esc false))
              (finalSt (fold (fn [(st ObjScanState) (c String)] -> ObjScanState
                                (let [(cur (.-curIdx st))
                                      (nextIdx (+ cur 1))]
                                  (cond
                                    ((.-esc st)
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :startIdx (.-startIdx st)
                                       :curIdx nextIdx
                                       :depth (.-depth st)
                                       :inStr (.-inStr st)
                                       :esc false))
                                    ((= c "\\")
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :startIdx (.-startIdx st)
                                       :curIdx nextIdx
                                       :depth (.-depth st)
                                       :inStr (.-inStr st)
                                       :esc (.-inStr st)))
                                    ((= c "\"")
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :startIdx (.-startIdx st)
                                       :curIdx nextIdx
                                       :depth (.-depth st)
                                       :inStr (not (.-inStr st))
                                       :esc false))
                                    ((.-inStr st)
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :startIdx (.-startIdx st)
                                       :curIdx nextIdx
                                       :depth (.-depth st)
                                       :inStr true
                                       :esc false))
                                    ((= c "{")
                                     (let [(d (+ (.-depth st) 1))
                                           (sIdx (if (= (.-depth st) 0) cur (.-startIdx st)))]
                                       (ObjScanState
                                         :objects (.-objects st)
                                         :startIdx sIdx
                                         :curIdx nextIdx
                                         :depth d
                                         :inStr false
                                         :esc false)))
                                    ((= c "}")
                                     (let [(d (- (.-depth st) 1))]
                                       (if (= d 0)
                                           (let [(objStr (option-or (string-slice trimmed (.-startIdx st) nextIdx) ""))]
                                             (ObjScanState
                                               :objects (list-cons objStr (.-objects st))
                                               :startIdx 0
                                               :curIdx nextIdx
                                               :depth 0
                                               :inStr false
                                               :esc false))
                                           (ObjScanState
                                             :objects (.-objects st)
                                             :startIdx (.-startIdx st)
                                             :curIdx nextIdx
                                             :depth d
                                             :inStr false
                                             :esc false))))
                                    (:else
                                     (ObjScanState
                                       :objects (.-objects st)
                                       :startIdx (.-startIdx st)
                                       :curIdx nextIdx
                                       :depth (.-depth st)
                                       :inStr false
                                       :esc false)))))
                              initSt
                              chars))]
          (if (= (.-depth finalSt) 0)
              (list-reverse (.-objects finalSt))
              (list))))))

(df jsonFindKeyTail [(obj String) (key String)] -> String
  :d "Finds the substring immediately following the colon for a specified JSON key."
  (let [(needle (str "\"" key "\""))]
    (mt (string-index-of obj needle)
      ((none) "")
      ((some idx)
       (let [(tailPos (+ idx (string-length needle)))
             (tail (option-or (string-slice obj tailPos (string-length obj)) ""))]
         (mt (string-index-of tail ":")
           ((none) "")
           ((some cIdx)
            (option-or (string-slice tail (+ cIdx 1) (string-length tail)) ""))))))))

(df findUnescapedQuote [(chars (List String))] -> (Option Int64)
  :d "Finds the first unescaped double quote character index in a list of characters."
  (let [(finalSt (fold (fn [(st QuoteScanState) (c String)] -> QuoteScanState
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
    (.-found finalSt)))

(df jsonExtractStr [(obj String) (key String)] -> String
  :d "Extracts a string property value by key from a JSON object string."
  (let [(tail (string-trim (jsonFindKeyTail obj key)))]
    (if (string-starts-with? tail "\"")
        (let [(inner (option-or (string-slice tail 1 (string-length tail)) ""))
              (chars (string-chars inner))]
          (mt (findUnescapedQuote chars)
            ((some qIdx)
             (let [(rawVal (option-or (string-slice inner 0 qIdx) ""))]
               (string-replace (string-replace rawVal "\\\"" "\"") "\\n" "\n")))
            ((none) "")))
        "")))

(df isDigitChar? [(c String)] -> Bool
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

(df extractDigits [(chars (List String))] -> String
  :d "Extracts leading digit sequence from character list."
  (let [(finalSt (fold (fn [(st DigitScanState) (c String)] -> DigitScanState
                          (if (.-done st)
                              st
                              (if (isDigitChar? c)
                                  (DigitScanState :digits (list-cons c (.-digits st)) :done false)
                                  (DigitScanState :digits (.-digits st) :done true))))
                        (DigitScanState :digits (list) :done false)
                        chars))]
    (string-join (list-reverse (.-digits finalSt)) "")))

(df jsonExtractInt [(obj String) (key String)] -> Int64
  :d "Extracts an integer property value by key from a JSON object string."
  (let [(tail (string-trim (jsonFindKeyTail obj key)))]
    (if (string-empty? tail)
        0
        (let [(chars (string-chars tail))
              (digits (extractDigits chars))]
          (if (string-empty? digits)
              0
              (option-or (string-to-int64 digits) 0))))))

(df jsonExtractAuthor [(obj String)] -> String
  :d "Extracts author login handle from JSON object supporting nested author or user objects."
  (let [(tail (string-trim (jsonFindKeyTail obj "author")))]
    (if (string-starts-with? tail "{")
        (let [(login (jsonExtractStr tail "login"))]
          (if (string-empty? login)
              (jsonExtractStr tail "name")
              login))
        (if (string-starts-with? tail "\"")
            (jsonExtractStr obj "author")
            (let [(userTail (string-trim (jsonFindKeyTail obj "user")))]
              (if (string-starts-with? userTail "{")
                  (jsonExtractStr userTail "login")
                  (if (string-starts-with? userTail "\"")
                      (jsonExtractStr obj "user")
                      "")))))))

(df jsonExtractRef [(obj String) (refKey String) (fallbackKey String)] -> String
  :d "Extracts branch reference name with fallback to nested branch ref object."
  (let [(v1 (jsonExtractStr obj refKey))]
    (if (not (string-empty? v1))
        v1
        (let [(tail (string-trim (jsonFindKeyTail obj fallbackKey)))]
          (if (string-starts-with? tail "{")
              (jsonExtractStr tail "ref")
              (if (string-starts-with? tail "\"")
                  (jsonExtractStr obj fallbackKey)
                  ""))))))

(df extractLabelsFromArrayInner [(inner String)] -> (List String)
  :d "Extracts label name strings from inside a labels JSON array block."
  (if (string-contains? inner "\"name\"")
      (let [(parts (string-split inner "\"name\""))
            (labelsRev (fold (fn [(acc (List String)) (part String)] -> (List String)
                                (let [(tail (string-trim part))]
                                  (mt (string-index-of tail ":")
                                    ((none) acc)
                                    ((some cIdx)
                                     (let [(afterColon (string-trim (option-or (string-slice tail (+ cIdx 1) (string-length tail)) "")))]
                                       (if (string-starts-with? afterColon "\"")
                                           (let [(raw (option-or (string-slice afterColon 1 (string-length afterColon)) ""))
                                                 (qIdx (string-index-of raw "\""))]
                                             (mt qIdx
                                               ((some idx)
                                                (let [(label (option-or (string-slice raw 0 idx) ""))]
                                                  (if (string-empty? label) acc (list-cons label acc))))
                                               ((none) acc)))
                                           acc))))))
                              (list)
                              parts))]
        (list-reverse labelsRev))
      (let [(parts (string-split inner "\""))
            (labelsRev (fold (fn [(acc LabelsScanState) (part String)] -> LabelsScanState
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
        (list-reverse (.-labels labelsRev)))))

(df jsonExtractLabels [(obj String)] -> (List String)
  :d "Extracts list of label names from a JSON object."
  (let [(tail (string-trim (jsonFindKeyTail obj "labels")))]
    (if (string-starts-with? tail "[")
        (let [(afterBracket (option-or (string-slice tail 1 (string-length tail)) ""))]
          (mt (string-index-of afterBracket "]")
            ((some endIdx)
             (let [(inner (option-or (string-slice afterBracket 0 endIdx) ""))]
               (extractLabelsFromArrayInner inner)))
            ((none) (list))))
        (list))))

(df extractAssigneesFromArrayInner [(inner String)] -> (List String)
  :d "Extracts assignee login strings from inside an assignees JSON array block."
  (if (string-contains? inner "\"login\"")
      (let [(parts (string-split inner "\"login\""))
            (assigneesRev (fold (fn [(acc (List String)) (part String)] -> (List String)
                                   (let [(tail (string-trim part))]
                                     (mt (string-index-of tail ":")
                                       ((none) acc)
                                       ((some cIdx)
                                        (let [(afterColon (string-trim (option-or (string-slice tail (+ cIdx 1) (string-length tail)) "")))]
                                          (if (string-starts-with? afterColon "\"")
                                              (let [(raw (option-or (string-slice afterColon 1 (string-length afterColon)) ""))
                                                    (qIdx (string-index-of raw "\""))]
                                                (mt qIdx
                                                  ((some idx)
                                                   (let [(login (option-or (string-slice raw 0 idx) ""))]
                                                     (if (string-empty? login) acc (list-cons login acc))))
                                                  ((none) acc)))
                                              acc))))))
                                 (list)
                                 parts))]
        (list-reverse assigneesRev))
      (let [(parts (string-split inner "\""))
            (assigneesRev (fold (fn [(acc AssigneesScanState) (part String)] -> AssigneesScanState
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
        (list-reverse (.-assignees assigneesRev)))))

(df jsonExtractAssignees [(obj String)] -> (List String)
  :d "Extracts list of assignee login handles from a JSON object."
  (let [(tail (string-trim (jsonFindKeyTail obj "assignees")))]
    (if (string-starts-with? tail "[")
        (let [(afterBracket (option-or (string-slice tail 1 (string-length tail)) ""))]
          (mt (string-index-of afterBracket "]")
            ((some endIdx)
             (let [(inner (option-or (string-slice afterBracket 0 endIdx) ""))]
               (extractAssigneesFromArrayInner inner)))
            ((none) (list))))
        (list))))

(df jsonExtractCommentsCount [(obj String)] -> Int64
  :d "Extracts total comments count from issue JSON object."
  (let [(c1 (jsonExtractInt obj "commentsCount"))]
    (if (> c1 0)
        c1
        (let [(c2 (jsonExtractInt obj "comments_count"))]
          (if (> c2 0)
              c2
              (let [(tail (string-trim (jsonFindKeyTail obj "comments")))]
                (if (string-starts-with? tail "[")
                    (let [(afterBracket (option-or (string-slice tail 1 (string-length tail)) ""))]
                      (mt (string-index-of afterBracket "]")
                        ((some endIdx)
                         (let [(inner (option-or (string-slice afterBracket 0 endIdx) ""))
                               (objs (splitJsonObjects inner))]
                           (list-length objs)))
                        ((none) 0)))
                    0)))))))

(df truncateBodyLines [(body String) (maxLines Int64)] -> String
  :d "Truncates body text if it exceeds max-lines appending a truncation pointer notice."
  (let [(lines (string-split body "\n"))
        (total (list-length lines))]
    (if (> total maxLines)
        (let [(kept (option-or (list-slice lines 0 maxLines) (list)))
              (joined (string-join kept "\n"))]
          (str joined "\n... [truncated, " (string-from-int64 total) " lines total] ..."))
        body)))

(df parsePrSummary [(obj String)] -> GitHubPrSummary
  :d "Parses a single JSON object string into a GitHubPrSummary record."
  (GitHubPrSummary
    :number (jsonExtractInt obj "number")
    :title (jsonExtractStr obj "title")
    :author (jsonExtractAuthor obj)
    :head (jsonExtractRef obj "headRefName" "head")
    :base (jsonExtractRef obj "baseRefName" "base")
    :state (jsonExtractStr obj "state")
    :labels (jsonExtractLabels obj)
    :additions (jsonExtractInt obj "additions")
    :deletions (jsonExtractInt obj "deletions")))

(df githubPrParse [(jsonStr String)] -> (List GitHubPrSummary)
  :d "Parses GitHub PR list or view JSON into compact GitHubPrSummary records."
  (let [(objs (splitJsonObjects jsonStr))]
    (map (fn [(obj String)] -> GitHubPrSummary (parsePrSummary obj)) objs)))

(df parseIssue [(obj String)] -> GitHubIssue
  :d "Parses a single JSON object string into a GitHubIssue record."
  (let [(rawBody (jsonExtractStr obj "body"))
        (cappedBody (truncateBodyLines rawBody 1000))]
    (GitHubIssue
      :number (jsonExtractInt obj "number")
      :title (jsonExtractStr obj "title")
      :author (jsonExtractAuthor obj)
      :state (jsonExtractStr obj "state")
      :labels (jsonExtractLabels obj)
      :assignees (jsonExtractAssignees obj)
      :commentsCount (jsonExtractCommentsCount obj)
      :body cappedBody)))

(df githubIssueParse [(jsonStr String)] -> (List GitHubIssue)
  :d "Parses GitHub issue list or view JSON into compact GitHubIssue records."
  (let [(objs (splitJsonObjects jsonStr))]
    (map (fn [(obj String)] -> GitHubIssue (parseIssue obj)) objs)))

(df extractTargetUrl [(obj String)] -> String
  :d "Extracts target or details URL from check run JSON object."
  (let [(u1 (jsonExtractStr obj "targetUrl"))]
    (if (not (string-empty? u1))
        u1
        (let [(u2 (jsonExtractStr obj "target_url"))]
          (if (not (string-empty? u2))
              u2
              (let [(u3 (jsonExtractStr obj "details_url"))]
                (if (not (string-empty? u3))
                    u3
                    (jsonExtractStr obj "url"))))))))

(df parseCiCheck [(obj String)] -> GitHubCiCheck
  :d "Parses a single JSON object string into a GitHubCiCheck record."
  (let [(conc (jsonExtractStr obj "conclusion"))
        (finalConc (if (string-empty? conc) (jsonExtractStr obj "state") conc))]
    (GitHubCiCheck
      :name (jsonExtractStr obj "name")
      :status (jsonExtractStr obj "status")
      :conclusion finalConc
      :targetUrl (extractTargetUrl obj))))

(df githubCiParse [(jsonStr String)] -> (List GitHubCiCheck)
  :d "Parses GitHub CI check runs JSON into compact GitHubCiCheck records."
  (let [(objs (splitJsonObjects jsonStr))]
    (map (fn [(obj String)] -> GitHubCiCheck (parseCiCheck obj)) objs)))

(df isFailureCheck? [(c GitHubCiCheck)] -> Bool
  :d "Returns true if a CI check has failed or timed out."
  (let [(conc (string-upper (.-conclusion c)))
        (st (string-upper (.-status c)))]
    (or (= conc "FAILURE")
        (or (= conc "FAILED")
            (or (= conc "TIMED_OUT")
                (or (= conc "ACTION_REQUIRED")
                    (= st "FAILURE")))))))

(df isPendingCheck? [(c GitHubCiCheck)] -> Bool
  :d "Returns true if a CI check is currently in progress or queued."
  (let [(st (string-upper (.-status c)))
        (conc (string-upper (.-conclusion c)))]
    (or (= st "IN_PROGRESS")
        (or (= st "QUEUED")
            (or (= st "PENDING")
                (and (= st "COMPLETED") (string-empty? conc)))))))

(df githubCiRollup [(checks (List GitHubCiCheck))] -> String
  :d "Computes aggregate CI status rollup verdict: :success, :failure, :pending."
  (if (list-empty? checks)
      ":success"
      (let [(hasFail (fold (fn [(acc Bool) (c GitHubCiCheck)] -> Bool (or acc (isFailureCheck? c))) false checks))]
        (if hasFail
            ":failure"
            (let [(hasPend (fold (fn [(acc Bool) (c GitHubCiCheck)] -> Bool (or acc (isPendingCheck? c))) false checks))]
              (if hasPend
                  ":pending"
                  ":success"))))))

(df cleanDiffPath [(raw String)] -> String
  :d "Cleans file path prefixes and trailing tabs from diff lines."
  (let [(t (string-trim raw))]
    (if (string-starts-with? t "a/")
        (option-or (string-slice t 2 (string-length t)) "")
        (if (string-starts-with? t "b/")
            (option-or (string-slice t 2 (string-length t)) "")
            t))))

(df extractHunkRange [(line String)] -> String
  :d "Extracts the @@ -start,count +start,count @@ range token from a hunk header line."
  (if (string-starts-with? line "@@ ")
      (let [(afterPrefix (option-or (string-slice line 3 (string-length line)) ""))]
        (mt (string-index-of afterPrefix "@@")
          ((some idx)
           (let [(rangeInner (string-trim (option-or (string-slice afterPrefix 0 idx) "")))]
             (str "@@ " rangeInner " @@")))
          ((none) (string-trim line))))
      (string-trim line)))

(df closeActiveHunkState [(st DiffScanState)] -> DiffScanState
  :d "Closes active hunk if open and accumulates into cur-hunks."
  (if (.-inHunk st)
      (let [(h (CompactHunk
                 :range (.-curRange st)
                 :deltas (list-reverse (.-curDeltas st))))]
        (DiffScanState
          :files (.-files st)
          :curPath (.-curPath st)
          :curAdds (.-curAdds st)
          :curDels (.-curDels st)
          :curHunks (list-cons h (.-curHunks st))
          :curRange ""
          :curDeltas (list)
          :inHunk false
          :inFile (.-inFile st)))
      st))

(df closeActiveFileState [(st DiffScanState)] -> DiffScanState
  :d "Closes active file if open and accumulates into files."
  (let [(s0 (closeActiveHunkState st))]
    (if (.-inFile s0)
        (let [(f (CompactFile
                   :path (.-curPath s0)
                   :additions (.-curAdds s0)
                   :deletions (.-curDels s0)
                   :hunks (list-reverse (.-curHunks s0))))]
          (DiffScanState
            :files (list-cons f (.-files s0))
            :curPath ""
            :curAdds 0
            :curDels 0
            :curHunks (list)
            :curRange ""
            :curDeltas (list)
            :inHunk false
            :inFile false))
        s0)))

(df stepDiffLine [(st DiffScanState) (line String)] -> DiffScanState
  :d "Processes a single line of unified diff input updating DiffScanState."
  (cond
    ((string-starts-with? line "diff --git ")
     (let [(s0 (closeActiveFileState st))
           (parts (string-split line " "))
           (rawPath (if (>= (list-length parts) 4)
                         (option-or (list-get parts 3) "")
                         ""))
           (p (cleanDiffPath rawPath))]
       (DiffScanState
         :files (.-files s0)
         :curPath p
         :curAdds 0
         :curDels 0
         :curHunks (list)
         :curRange ""
         :curDeltas (list)
         :inHunk false
         :inFile true)))
    ((string-starts-with? line "--- ")
     (let [(raw (string-trim (option-or (string-slice line 4 (string-length line)) "")))]
       (if (and (not (.-inFile st)) (not (string-empty? raw)))
           (let [(p (cleanDiffPath raw))]
             (DiffScanState
               :files (.-files st)
               :curPath p
               :curAdds 0
               :curDels 0
               :curHunks (list)
               :curRange ""
               :curDeltas (list)
               :inHunk false
               :inFile true))
           st)))
    ((string-starts-with? line "+++ ")
     (let [(raw (string-trim (option-or (string-slice line 4 (string-length line)) "")))]
       (if (and (not (string-empty? raw)) (not (= raw "/dev/null")))
           (let [(p (cleanDiffPath raw))]
             (DiffScanState
               :files (.-files st)
               :curPath p
               :curAdds (.-curAdds st)
               :curDels (.-curDels st)
               :curHunks (.-curHunks st)
               :curRange (.-curRange st)
               :curDeltas (.-curDeltas st)
               :inHunk (.-inHunk st)
               :inFile true))
           st)))
    ((string-starts-with? line "@@ ")
     (let [(s0 (closeActiveHunkState st))
           (rng (extractHunkRange line))]
       (DiffScanState
         :files (.-files s0)
         :curPath (.-curPath s0)
         :curAdds (.-curAdds s0)
         :curDels (.-curDels s0)
         :curHunks (.-curHunks s0)
         :curRange rng
         :curDeltas (list)
         :inHunk true
         :inFile true)))
    (:else
     (if (.-inHunk st)
         (let [(isAdd (and (string-starts-with? line "+") (not (string-starts-with? line "+++"))))
               (isDel (and (string-starts-with? line "-") (not (string-starts-with? line "---"))))]
           (if (or isAdd isDel)
               (let [(addInc (if isAdd 1 0))
                     (delInc (if isDel 1 0))]
                 (DiffScanState
                   :files (.-files st)
                   :curPath (.-curPath st)
                   :curAdds (+ (.-curAdds st) addInc)
                   :curDels (+ (.-curDels st) delInc)
                   :curHunks (.-curHunks st)
                   :curRange (.-curRange st)
                   :curDeltas (list-cons line (.-curDeltas st))
                   :inHunk true
                   :inFile true))
               st))
         st))))

(df formatCompactHunk [(h CompactHunk)] -> String
  :d "Formats a CompactHunk record into compact ASN hunk representation."
  (let [(quotedDeltas (map (fn [(d String)] -> String (str "\"" d "\"")) (.-deltas h)))
        (deltasStr (string-join quotedDeltas " "))]
    (str "(:hunk :range \"" (.-range h) "\" :deltas (" deltasStr "))")))

(df formatCompactFile [(f CompactFile)] -> String
  :d "Formats a CompactFile record into compact ASN file diff representation."
  (let [(hunkStrs (map (fn [(h CompactHunk)] -> String (formatCompactHunk h)) (.-hunks f)))
        (hunksBody (string-join hunkStrs " "))]
    (str "(:file \"" (.-path f) "\" :+ " (string-from-int64 (.-additions f))
         " :- " (string-from-int64 (.-deletions f))
         " :hunks (" hunksBody "))")))

(df parseCompactDiff [(rawDiff String)] -> (List CompactFile)
  :d "Parses raw unified diff text into a list of CompactFile records."
  (let [(trimmed (string-trim rawDiff))]
    (if (string-empty? trimmed)
        (list)
        (let [(cleanText (string-replace rawDiff "\r" ""))
              (lines (string-split cleanText "\n"))
              (initSt (DiffScanState
                         :files (list)
                         :curPath ""
                         :curAdds 0
                         :curDels 0
                         :curHunks (list)
                         :curRange ""
                         :curDeltas (list)
                         :inHunk false
                         :inFile false))
              (finalSt (fold (fn [(s DiffScanState) (ln String)] -> DiffScanState
                                (stepDiffLine s ln))
                              initSt
                              lines))
              (closedSt (closeActiveFileState finalSt))]
          (list-reverse (.-files closedSt))))))

(df githubDiffCompact [(rawDiff String)] -> String
  :d "Compacts a raw unified diff by stripping index hashes and context lines into an ASN projection."
  (let [(files (parseCompactDiff rawDiff))]
    (if (list-empty? files)
        "(:pr-diff :files ())"
        (let [(fileStrs (map (fn [(f CompactFile)] -> String (formatCompactFile f)) files))
              (filesBody (string-join fileStrs " "))]
          (str "(:pr-diff :files (" filesBody "))")))))

(df formatPrItem [(pr GitHubPrSummary)] -> String
  :d "Formats a single GitHubPrSummary record into an ASN PR item."
  (let [(labelsStr (fold (fn [(acc String) (lbl String)] -> String
                            (let [(escL (string-replace lbl "\"" "\\\""))]
                              (if (string-empty? acc)
                                  (str "\"" escL "\"")
                                  (str acc " \"" escL "\""))))
                          ""
                          (.-labels pr)))
        (escTitle (string-replace (.-title pr) "\"" "\\\""))]
    (str "(:pr :number " (string-from-int64 (.-number pr))
         " :title \"" escTitle "\""
         " :author \"" (.-author pr) "\""
         " :head \"" (.-head pr) "\""
         " :base \"" (.-base pr) "\""
         " :state \"" (.-state pr) "\""
         " :additions " (string-from-int64 (.-additions pr))
         " :deletions " (string-from-int64 (.-deletions pr))
         " :labels (" labelsStr "))")))

(df githubPrsFormat [(prs (List GitHubPrSummary))] -> String
  :d "Formats a list of GitHubPrSummary records into a compact :github-prs ASN envelope."
  (let [(items (fold (fn [(acc String) (pr GitHubPrSummary)] -> String
                       (let [(item (formatPrItem pr))]
                         (if (string-empty? acc) item (str acc " " item))))
                     ""
                     prs))]
    (str "(:github-prs :count " (string-from-int64 (list-length prs)) " :prs (" items "))")))

(df formatIssueItem [(issue GitHubIssue)] -> String
  :d "Formats a single GitHubIssue record into an ASN issue item."
  (let [(labelsStr (fold (fn [(acc String) (lbl String)] -> String
                            (let [(escL (string-replace lbl "\"" "\\\""))]
                              (if (string-empty? acc)
                                  (str "\"" escL "\"")
                                  (str acc " \"" escL "\""))))
                          ""
                          (.-labels issue)))
        (escTitle (string-replace (.-title issue) "\"" "\\\""))]
    (str "(:issue :number " (string-from-int64 (.-number issue))
         " :title \"" escTitle "\""
         " :author \"" (.-author issue) "\""
         " :state \"" (.-state issue) "\""
         " :comments " (string-from-int64 (.-commentsCount issue))
         " :labels (" labelsStr "))")))

(df githubIssuesFormat [(issues (List GitHubIssue))] -> String
  :d "Formats a list of GitHubIssue records into a compact :github-issues ASN envelope."
  (let [(items (fold (fn [(acc String) (issue GitHubIssue)] -> String
                       (let [(item (formatIssueItem issue))]
                         (if (string-empty? acc) item (str acc " " item))))
                     ""
                     issues))]
    (str "(:github-issues :count " (string-from-int64 (list-length issues)) " :issues (" items "))")))

(df formatCiItem [(c GitHubCiCheck)] -> String
  :d "Formats a single GitHubCiCheck record into an ASN check item."
  (let [(escName (string-replace (.-name c) "\"" "\\\""))]
    (str "(:check :name \"" escName "\""
         " :status \"" (.-status c) "\""
         " :conclusion \"" (.-conclusion c) "\""
         (if (string-empty? (.-targetUrl c)) "" (str " :url \"" (.-targetUrl c) "\""))
         ")")))

(df githubCiFormat [(checks (List GitHubCiCheck))] -> String
  :d "Formats a list of GitHubCiCheck records and their rollup verdict into a compact :github-ci ASN envelope."
  (let [(verdict (githubCiRollup checks))
        (items (fold (fn [(acc String) (c GitHubCiCheck)] -> String
                       (let [(item (formatCiItem c))]
                         (if (string-empty? acc) item (str acc " " item))))
                     ""
                     checks))]
    (str "(:github-ci :verdict " verdict
         " :count " (string-from-int64 (list-length checks))
         " :checks (" items "))")))

