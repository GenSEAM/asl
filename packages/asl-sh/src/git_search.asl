(module asl-sh/gitSearch
  :d "Pure AgentScript Git cross-branch and cross-ref search engine, ref grep parser, and branch catalog codec."
  :x [GitSearchMatch
      GitBranchRecord
      gitSearchParse
      gitSearchFormat
      gitBranchesParse
      gitBranchesFormat])

(dfs GitSearchMatch
  (:f ref String "Branch, commit OID, or tree ref where match was discovered")
  (:f file String "File path within repository tree")
  (:f line Int64 "1-indexed line number of matching text")
  (:f content String "Matching line content"))

(dfs GitBranchRecord
  (:f name String "Branch name without remotes prefix")
  (:f commit String "Head commit hash of branch")
  (:f upstream String "Tracking upstream reference or empty string")
  (:f current Bool "True if this branch is currently checked out in active worktree")
  (:f remote Bool "True if this is a remote tracking branch"))

(df parseSearchLineWithRef [(cleanLine String)] -> (Option GitSearchMatch)
  :d "Parses a four-part ref:file:line:content git grep output line."
  (let [(parts (string-split cleanLine ":"))]
    (if (>= (list-length parts) 4)
        (let [(r (string-trim (option-or (list-get parts 0) "")))
              (f (string-trim (option-or (list-get parts 1) "")))
              (lStr (string-trim (option-or (list-get parts 2) "0")))
              (lNum (option-or (string-to-int64 lStr) 0))
              (p0Len (+ (string-length r) 1))
              (p1Len (+ (string-length f) 1))
              (p2Len (+ (string-length lStr) 1))
              (prefixLen (+ (+ p0Len p1Len) p2Len))
              (c (if (> (string-length cleanLine) prefixLen)
                     (option-or (string-slice cleanLine prefixLen (string-length cleanLine)) "")
                     ""))]
          (if (> lNum 0)
              (some (GitSearchMatch :ref r :file f :line lNum :content c))
              (none)))
        (none))))

(df parseSearchLineLocal [(cleanLine String)] -> (Option GitSearchMatch)
  :d "Parses a three-part file:line:content git grep output line assuming active HEAD."
  (let [(parts (string-split cleanLine ":"))]
    (if (>= (list-length parts) 3)
        (let [(f (string-trim (option-or (list-get parts 0) "")))
              (lStr (string-trim (option-or (list-get parts 1) "0")))
              (lNum (option-or (string-to-int64 lStr) 0))
              (p0Len (+ (string-length f) 1))
              (p1Len (+ (string-length lStr) 1))
              (prefixLen (+ p0Len p1Len))
              (c (if (> (string-length cleanLine) prefixLen)
                     (option-or (string-slice cleanLine prefixLen (string-length cleanLine)) "")
                     ""))]
          (if (> lNum 0)
              (some (GitSearchMatch :ref "HEAD" :file f :line lNum :content c))
              (none)))
        (none))))

(df parseSingleSearchLine [(line String) (defaultRef String)] -> (Option GitSearchMatch)
  :d "Parses one line of git grep output into an optional GitSearchMatch record."
  (let [(clean (string-trim line))]
    (if (string-empty? clean)
        (none)
        (mt (parseSearchLineWithRef clean)
          ((some m) (some m))
          ((none)
           (mt (parseSearchLineLocal clean)
             ((some m2)
              (some (GitSearchMatch :ref defaultRef :file (.-file m2) :line (.-line m2) :content (.-content m2))))
             ((none) (none))))))))

(df gitSearchParse [(rawOutput String) (defaultRef String)] -> (List GitSearchMatch)
  :d "Parses git grep output across one or more refs into a list of GitSearchMatch records."
  (let [(clean (string-replace rawOutput "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitSearchMatch)) (ln String)] -> (List GitSearchMatch)
                          (mt (parseSingleSearchLine ln defaultRef)
                            ((some m) (list-cons m acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df formatSearchMatchItem [(m GitSearchMatch)] -> String
  :d "Formats a single GitSearchMatch record into an ASN S-expression."
  (let [(escContent (string-replace (.-content m) "\"" "\\\""))]
    (str "(:match :ref \"" (.-ref m) "\""
         " :file \"" (.-file m) "\""
         " :line " (string-from-int64 (.-line m))
         " :content \"" escContent "\")")))

(df gitSearchFormat [(matches (List GitSearchMatch)) (query String) (limit Int64)] -> String
  :d "Formats a list of GitSearchMatch records into a compact token-bounded :git-search-results ASN envelope."
  (let [(totalCnt (list-length matches))
        (takeCnt (if (or (<= limit 0) (> limit totalCnt)) totalCnt limit))
        (isTrunc (< takeCnt totalCnt))
        (truncatedMatches (list-take matches takeCnt))
        (matchItems (fold (fn [(acc String) (m GitSearchMatch)] -> String
                             (let [(item (formatSearchMatchItem m))]
                               (if (string-empty? acc)
                                   item
                                   (str acc " " item))))
                           ""
                           truncatedMatches))
        (truncPart (if isTrunc (str " :truncated true :total-matches " (string-from-int64 totalCnt)) ""))]
    (str "(:git-search-results :query \"" query "\""
         " :count " (string-from-int64 takeCnt)
         truncPart
         " :matches (" matchItems "))")))

(df parseBranchUpstream [(s String)] -> String
  :d "Extracts upstream tracking branch from bracketed token [origin/main]."
  (if (and (string-contains? s "[") (string-contains? s "]"))
      (let [(afterBracket (option-or (list-get (string-split s "[") 1) ""))
            (beforeClose (option-or (list-get (string-split afterBracket "]") 0) ""))
            (clean (string-trim beforeClose))]
        (if (string-contains? clean ":")
            (option-or (list-get (string-split clean ":") 0) clean)
            clean))
      ""))

(df parseSingleBranchLine [(line String)] -> (Option GitBranchRecord)
  :d "Parses a single line from git branch -a -v into a GitBranchRecord."
  (let [(clean (string-trim line))]
    (if (or (string-empty? clean) (string-contains? clean " -> "))
        (none)
        (let [(isCur (string-starts-with? line "*"))
              (afterStar (if isCur
                              (string-trim (option-or (string-slice line 1 (string-length line)) ""))
                              clean))
              (rawToks (string-split afterStar " "))
              (toks (list-filter (fn [(t String)] -> Bool (not (string-empty? (string-trim t)))) rawToks))
              (rawName (string-trim (option-or (list-get toks 0) "")))]
          (if (string-empty? rawName)
              (none)
              (let [(isRem (string-starts-with? rawName "remotes/"))
                    (cleanName (if isRem
                                    (option-or (string-slice rawName 8 (string-length rawName)) rawName)
                                    rawName))
                    (commitHash (if (> (list-length toks) 1)
                                     (string-trim (option-or (list-get toks 1) ""))
                                     ""))
                    (up (parseBranchUpstream line))]
                (some (GitBranchRecord
                        :name cleanName
                        :commit commitHash
                        :upstream up
                        :current isCur
                        :remote isRem))))))))

(df gitBranchesParse [(rawBranches String)] -> (List GitBranchRecord)
  :d "Parses multi-line git branch listing output into a list of GitBranchRecord structures."
  (let [(clean (string-replace rawBranches "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitBranchRecord)) (ln String)] -> (List GitBranchRecord)
                          (mt (parseSingleBranchLine ln)
                            ((some b) (list-cons b acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df formatBranchItem [(b GitBranchRecord)] -> String
  :d "Formats a single GitBranchRecord into an ASN branch item."
  (let [(curPart (if (.-current b) " :current true" ""))
        (remPart (if (.-remote b) " :remote true" ""))
        (upPart (if (string-empty? (.-upstream b))
                     ""
                     (str " :upstream \"" (.-upstream b) "\"")))]
    (str "(:branch :name \"" (.-name b) "\""
         " :commit \"" (.-commit b) "\""
         curPart
         remPart
         upPart
         ")")))

(df gitBranchesFormat [(branches (List GitBranchRecord))] -> String
  :d "Formats a list of GitBranchRecord records into a compact :git-branches ASN envelope."
  (let [(countStr (string-from-int64 (list-length branches)))
        (items (fold (fn [(acc String) (b GitBranchRecord)] -> String
                       (let [(item (formatBranchItem b))]
                         (if (string-empty? acc)
                             item
                             (str acc " " item))))
                     ""
                     branches))]
    (str "(:git-branches :count " countStr " :branches (" items "))")))
