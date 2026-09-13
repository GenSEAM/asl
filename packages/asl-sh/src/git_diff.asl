(module asl-sh/gitDiff
  :d "Pure AgentScript unified diff parser and token-optimized ASN diff summary codec."
  :x [GitDiffHunk
      GitDiffFile
      GitNumstatEntry
      GitBranchCompare
      gitDiffParse
      gitDiffSummary
      gitNumstatParse
      gitCompareFormat])

(dfs GitDiffHunk
  (:f oldStart Int64 "Hunk line start in old file")
  (:f oldCount Int64 "Hunk line count in old file")
  (:f newStart Int64 "Hunk line start in new file")
  (:f newCount Int64 "Hunk line count in new file")
  (:f lines (List String) "Hunk diff lines including context and changes"))

(dfs GitDiffFile
  (:f oldPath String "Path to old file or empty string")
  (:f newPath String "Path to new file or empty string")
  (:f hunks (List GitDiffHunk) "List of hunks in this file diff")
  (:f additions Int64 "Total additions in this file diff")
  (:f deletions Int64 "Total deletions in this file diff"))

(dfs ParseState
  (:f files (List GitDiffFile) "Accumulated completed files in reverse order")
  (:f curOldPath String "Current file old path")
  (:f curNewPath String "Current file new path")
  (:f curHunks (List GitDiffHunk) "Accumulated hunks for current file in reverse order")
  (:f curAdditions Int64 "Additions count for current file")
  (:f curDeletions Int64 "Deletions count for current file")
  (:f curHunk (Option GitDiffHunk) "Active hunk being collected")
  (:f hasFile Bool "True if a file boundary has been seen"))

(df cleanDiffPath [(raw String)] -> String
  :d "Cleans trailing tab metadata and whitespace from a diff file path."
  (let [(noTab (if (string-contains? raw "\t")
                    (option-or (list-get (string-split raw "\t") 0) raw)
                    raw))]
    (string-trim noTab)))

(df extractDiffPath [(line String) (prefix String)] -> String
  :d "Extracts and normalizes target file path from a diff header line."
  (let [(pLen (string-length prefix))
        (rawTail (option-or (string-slice line pLen (string-length line)) ""))
        (trimmed (cleanDiffPath rawTail))]
    (cond
      ((string-starts-with? trimmed "a/")
       (option-or (string-slice trimmed 2 (string-length trimmed)) ""))
      ((string-starts-with? trimmed "b/")
       (option-or (string-slice trimmed 2 (string-length trimmed)) ""))
      (:else trimmed))))

(df parseRangeToken [(tok String) (prefix String)] -> (Pair Int64 Int64)
  :d "Parses start and count from a diff range token such as -1,5 or +1."
  (let [(pLen (string-length prefix))
        (cleanTok (option-or (string-slice tok pLen (string-length tok)) ""))
        (nums (string-split cleanTok ","))
        (startStr (string-trim (option-or (list-get nums 0) "0")))
        (startVal (option-or (string-to-int64 startStr) 0))]
    (if (> (list-length nums) 1)
        (let [(countStr (string-trim (option-or (list-get nums 1) "0")))
              (countVal (option-or (string-to-int64 countStr) 0))]
          (pair startVal countVal))
        (pair startVal 1))))

(df findTokenWithPrefix [(toks (List String)) (prefix String)] -> String
  :d "Finds the first token in a list starting with a specific prefix."
  (fold (fn [(acc String) (tok String)] -> String
          (if (string-empty? acc)
              (let [(t (string-trim tok))]
                (if (string-starts-with? t prefix) t ""))
              acc))
        ""
        toks))

(df parseHunkHeader [(line String)] -> (Option GitDiffHunk)
  :d "Parses a unified diff hunk header into a GitDiffHunk structure."
  (if (string-starts-with? line "@@ ")
      (let [(afterPrefix (option-or (string-slice line 3 (string-length line)) ""))
            (parts (string-split afterPrefix "@@"))]
        (if (>= (list-length parts) 2)
            (let [(rangeStr (string-trim (option-or (list-get parts 0) "")))
                  (toks (string-split rangeStr " "))
                  (oldTok (findTokenWithPrefix toks "-"))
                  (newTok (findTokenWithPrefix toks "+"))]
              (if (and (not (string-empty? oldTok)) (not (string-empty? newTok)))
                  (let [(oldRange (parseRangeToken oldTok "-"))
                        (newRange (parseRangeToken newTok "+"))]
                    (some (GitDiffHunk
                            :oldStart (.-first oldRange)
                            :oldCount (.-second oldRange)
                            :newStart (.-first newRange)
                            :newCount (.-second newRange)
                            :lines (list))))
                  (none)))
            (none)))
      (none)))

(df closeActiveHunk [(hOpt (Option GitDiffHunk)) (hunks (List GitDiffHunk))] -> (List GitDiffHunk)
  :d "Closes currently active hunk by reversing accumulated lines and appending to hunk list."
  (mt hOpt
    ((some h)
     (let [(finalH (GitDiffHunk
                      :oldStart (.-oldStart h)
                      :oldCount (.-oldCount h)
                      :newStart (.-newStart h)
                      :newCount (.-newCount h)
                      :lines (list-reverse (.-lines h))))]
       (list-cons finalH hunks)))
    ((none) hunks)))

(df closeActiveFile [(st ParseState)] -> ParseState
  :d "Closes currently active file if present and adds it to accumulated file list."
  (if (.-hasFile st)
      (let [(finalHunks (list-reverse (closeActiveHunk (.-curHunk st) (.-curHunks st))))
            (f (GitDiffFile
                 :oldPath (.-curOldPath st)
                 :newPath (.-curNewPath st)
                 :hunks finalHunks
                 :additions (.-curAdditions st)
                 :deletions (.-curDeletions st)))]
        (ParseState
          :files (list-cons f (.-files st))
          :curOldPath ""
          :curNewPath ""
          :curHunks (list)
          :curAdditions 0
          :curDeletions 0
          :curHunk (none)
          :hasFile false))
      st))

(df handleDiffGit [(st ParseState) (line String)] -> ParseState
  :d "Handles diff git header line starting a new file."
  (let [(s0 (closeActiveFile st))
        (parts (string-split line " "))
        (pOld (if (>= (list-length parts) 4)
                   (let [(raw (option-or (list-get parts 2) ""))]
                     (if (string-starts-with? raw "a/")
                         (option-or (string-slice raw 2 (string-length raw)) "")
                         raw))
                   ""))
        (pNew (if (>= (list-length parts) 4)
                   (let [(raw (option-or (list-get parts 3) ""))]
                     (if (string-starts-with? raw "b/")
                         (option-or (string-slice raw 2 (string-length raw)) "")
                         raw))
                   ""))]
    (ParseState
      :files (.-files s0)
      :curOldPath pOld
      :curNewPath pNew
      :curHunks (list)
      :curAdditions 0
      :curDeletions 0
      :curHunk (none)
      :hasFile true)))

(df handleOldPath [(st ParseState) (line String)] -> ParseState
  :d "Handles old file path line."
  (let [(needsClose (and (.-hasFile st)
                          (or (not (list-empty? (.-curHunks st)))
                              (mt (.-curHunk st) ((some _) true) ((none) false)))))
        (s0 (if needsClose (closeActiveFile st) st))
        (oldP (extractDiffPath line "--- "))]
    (ParseState
      :files (.-files s0)
      :curOldPath oldP
      :curNewPath (.-curNewPath s0)
      :curHunks (.-curHunks s0)
      :curAdditions (.-curAdditions s0)
      :curDeletions (.-curDeletions s0)
      :curHunk (.-curHunk s0)
      :hasFile true)))

(df handleNewPath [(st ParseState) (line String)] -> ParseState
  :d "Handles new file path line."
  (let [(newP (extractDiffPath line "+++ "))]
    (ParseState
      :files (.-files st)
      :curOldPath (.-curOldPath st)
      :curNewPath newP
      :curHunks (.-curHunks st)
      :curAdditions (.-curAdditions st)
      :curDeletions (.-curDeletions st)
      :curHunk (.-curHunk st)
      :hasFile true)))

(df handleHunkHead [(st ParseState) (line String)] -> ParseState
  :d "Handles hunk header line starting a new hunk."
  (let [(hunks1 (closeActiveHunk (.-curHunk st) (.-curHunks st)))
        (newHunk (parseHunkHeader line))]
    (ParseState
      :files (.-files st)
      :curOldPath (.-curOldPath st)
      :curNewPath (.-curNewPath st)
      :curHunks hunks1
      :curAdditions (.-curAdditions st)
      :curDeletions (.-curDeletions st)
      :curHunk newHunk
      :hasFile true)))

(df handleHunkLine [(st ParseState) (line String) (h GitDiffHunk)] -> ParseState
  :d "Appends a line into the active hunk updating additions and deletions counts."
  (let [(isAdd (and (string-starts-with? line "+") (not (string-starts-with? line "+++"))))
        (isDel (and (string-starts-with? line "-") (not (string-starts-with? line "---"))))
        (h2 (GitDiffHunk
              :oldStart (.-oldStart h)
              :oldCount (.-oldCount h)
              :newStart (.-newStart h)
              :newCount (.-newCount h)
              :lines (list-cons line (.-lines h))))
        (addInc (if isAdd 1 0))
        (delInc (if isDel 1 0))]
    (ParseState
      :files (.-files st)
      :curOldPath (.-curOldPath st)
      :curNewPath (.-curNewPath st)
      :curHunks (.-curHunks st)
      :curAdditions (+ (.-curAdditions st) addInc)
      :curDeletions (+ (.-curDeletions st) delInc)
      :curHunk (some h2)
      :hasFile (.-hasFile st))))

(df stepDiffLine [(st ParseState) (line String)] -> ParseState
  :d "Processes one line of unified diff input updating parse state."
  (cond
    ((string-starts-with? line "diff --git ") (handleDiffGit st line))
    ((string-starts-with? line "--- ") (handleOldPath st line))
    ((string-starts-with? line "+++ ") (handleNewPath st line))
    ((string-starts-with? line "@@ ") (handleHunkHead st line))
    (:else
     (mt (.-curHunk st)
       ((some h) (handleHunkLine st line h))
       ((none) st)))))

(df gitDiffParse [(diffText String)] -> (List GitDiffFile)
  :d "Parses unified diff text into a list of GitDiffFile records."
  (let [(trimmed (string-trim diffText))]
    (if (string-empty? trimmed)
        (list)
        (let [(cleanText (string-replace diffText "\r" ""))
              (lines (string-split cleanText "\n"))
              (initSt (ParseState
                         :files (list)
                         :curOldPath ""
                         :curNewPath ""
                         :curHunks (list)
                         :curAdditions 0
                         :curDeletions 0
                         :curHunk (none)
                         :hasFile false))
              (finalSt (fold (fn [(s ParseState) (ln String)] -> ParseState
                                (stepDiffLine s ln))
                              initSt
                              lines))
              (closedSt (closeActiveFile finalSt))]
          (list-reverse (.-files closedSt))))))

(df sumAdditions [(files (List GitDiffFile))] -> Int64
  :d "Sums all additions across a list of file diffs."
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (.-additions f))) 0 files))

(df sumDeletions [(files (List GitDiffFile))] -> Int64
  :d "Sums all deletions across a list of file diffs."
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (.-deletions f))) 0 files))

(df sumHunks [(files (List GitDiffFile))] -> Int64
  :d "Sums all hunk counts across a list of file diffs."
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (list-length (.-hunks f)))) 0 files))

(df gitDiffSummary [(files (List GitDiffFile))] -> String
  :d "Formats a list of GitDiffFile records into a compact ASN summary string."
  (let [(totalFiles (list-length files))
        (totalAdditions (sumAdditions files))
        (totalDeletions (sumDeletions files))
        (totalHunks (sumHunks files))]
    (str "(:diff-summary :files " (string-from-int64 totalFiles)
         " :additions " (string-from-int64 totalAdditions)
         " :deletions " (string-from-int64 totalDeletions)
         " :hunks " (string-from-int64 totalHunks) ")")))

(dfs GitNumstatEntry
  (:f path String "Target file path")
  (:f additions Int64 "Lines added")
  (:f deletions Int64 "Lines deleted")
  (:f status String "Inferred status: added, deleted, modified, or binary"))

(dfs GitBranchCompare
  (:f base String "Base branch or reference")
  (:f target String "Target branch or reference")
  (:f mergeBase String "Common ancestor commit hash")
  (:f ahead Int64 "Commits ahead of base")
  (:f behind Int64 "Commits behind base")
  (:f files (List GitNumstatEntry) "List of changed file records")
  (:f totalAdditions Int64 "Total lines added across all files")
  (:f totalDeletions Int64 "Total lines deleted across all files"))

(df parseNumstatLine [(line String)] -> (Option GitNumstatEntry)
  :d "Parses a single git diff --numstat line into a GitNumstatEntry record."
  (let [(clean (string-trim line))]
    (if (string-empty? clean)
        (none)
        (let [(parts (string-split clean "\t"))]
          (if (>= (list-length parts) 3)
              (let [(addRaw (string-trim (option-or (list-get parts 0) "0")))
                    (delRaw (string-trim (option-or (list-get parts 1) "0")))
                    (pathRaw (string-trim (option-or (list-get parts 2) "")))
                    (isBin (or (= addRaw "-") (= delRaw "-")))
                    (adds (if isBin 0 (option-or (string-to-int64 addRaw) 0)))
                    (dels (if isBin 0 (option-or (string-to-int64 delRaw) 0)))
                    (st (cond
                          (isBin "binary")
                          ((and (= dels 0) (> adds 0)) "added")
                          ((and (= adds 0) (> dels 0)) "deleted")
                          (:else "modified")))]
                (some (GitNumstatEntry :path pathRaw :additions adds :deletions dels :status st)))
              (none))))))

(df gitNumstatParse [(rawNumstat String)] -> (List GitNumstatEntry)
  :d "Parses multi-line git diff --numstat output into a list of GitNumstatEntry records."
  (let [(clean (string-replace rawNumstat "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitNumstatEntry)) (ln String)] -> (List GitNumstatEntry)
                          (mt (parseNumstatLine ln)
                            ((some e) (list-cons e acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df formatNumstatEntry [(e GitNumstatEntry)] -> String
  :d "Formats a single GitNumstatEntry into an ASN file delta item."
  (str "(:file :path \"" (.-path e) "\""
       " :status \"" (.-status e) "\""
       " :+ " (string-from-int64 (.-additions e))
       " :- " (string-from-int64 (.-deletions e)) ")"))

(df gitCompareFormat [(cmp GitBranchCompare) (limit Int64)] -> String
  :d "Formats a GitBranchCompare record into a compact token-bounded :git-compare ASN envelope."
  (let [(allFiles (.-files cmp))
        (totalCnt (list-length allFiles))
        (takeCnt (if (or (<= limit 0) (> limit totalCnt)) totalCnt limit))
        (isTrunc (< takeCnt totalCnt))
        (truncatedFiles (list-take allFiles takeCnt))
        (fileItems (fold (fn [(acc String) (f GitNumstatEntry)] -> String
                            (let [(item (formatNumstatEntry f))]
                              (if (string-empty? acc)
                                  item
                                  (str acc " " item))))
                          ""
                          truncatedFiles))
        (truncPart (if isTrunc (str " :truncated true :total-files " (string-from-int64 totalCnt)) ""))]
    (str "(:git-compare :base \"" (.-base cmp) "\""
         " :target \"" (.-target cmp) "\""
         " :merge-base \"" (.-mergeBase cmp) "\""
         " :ahead " (string-from-int64 (.-ahead cmp))
         " :behind " (string-from-int64 (.-behind cmp))
         " :files-count " (string-from-int64 takeCnt)
         " :+ " (string-from-int64 (.-totalAdditions cmp))
         " :- " (string-from-int64 (.-totalDeletions cmp))
         truncPart
         " :files (" fileItems "))")))
