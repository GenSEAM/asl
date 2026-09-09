(module asl-sh/git-search
  :d "Pure AgentScript Git cross-branch and cross-ref search engine, ref grep parser, and branch catalog codec."
  :x [GitSearchMatch
      GitBranchRecord
      git-search-parse
      git-search-format
      git-branches-parse
      git-branches-format])

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

(df parse-search-line-with-ref [(clean-line String)] -> (Option GitSearchMatch)
  :d "Parses a four-part ref:file:line:content git grep output line."
  (let [(parts (string-split clean-line ":"))]
    (if (>= (list-length parts) 4)
        (let [(r (string-trim (option-or (list-get parts 0) "")))
              (f (string-trim (option-or (list-get parts 1) "")))
              (l-str (string-trim (option-or (list-get parts 2) "0")))
              (l-num (option-or (string-to-int64 l-str) 0))
              (p0-len (+ (string-length r) 1))
              (p1-len (+ (string-length f) 1))
              (p2-len (+ (string-length l-str) 1))
              (prefix-len (+ (+ p0-len p1-len) p2-len))
              (c (if (> (string-length clean-line) prefix-len)
                     (option-or (string-slice clean-line prefix-len (string-length clean-line)) "")
                     ""))]
          (if (> l-num 0)
              (some (GitSearchMatch :ref r :file f :line l-num :content c))
              (none)))
        (none))))

(df parse-search-line-local [(clean-line String)] -> (Option GitSearchMatch)
  :d "Parses a three-part file:line:content git grep output line assuming active HEAD."
  (let [(parts (string-split clean-line ":"))]
    (if (>= (list-length parts) 3)
        (let [(f (string-trim (option-or (list-get parts 0) "")))
              (l-str (string-trim (option-or (list-get parts 1) "0")))
              (l-num (option-or (string-to-int64 l-str) 0))
              (p0-len (+ (string-length f) 1))
              (p1-len (+ (string-length l-str) 1))
              (prefix-len (+ p0-len p1-len))
              (c (if (> (string-length clean-line) prefix-len)
                     (option-or (string-slice clean-line prefix-len (string-length clean-line)) "")
                     ""))]
          (if (> l-num 0)
              (some (GitSearchMatch :ref "HEAD" :file f :line l-num :content c))
              (none)))
        (none))))

(df parse-single-search-line [(line String) (default-ref String)] -> (Option GitSearchMatch)
  :d "Parses one line of git grep output into an optional GitSearchMatch record."
  (let [(clean (string-trim line))]
    (if (string-empty? clean)
        (none)
        (mt (parse-search-line-with-ref clean)
          ((some m) (some m))
          ((none)
           (mt (parse-search-line-local clean)
             ((some m2)
              (some (GitSearchMatch :ref default-ref :file (.-file m2) :line (.-line m2) :content (.-content m2))))
             ((none) (none))))))))

(df git-search-parse [(raw-output String) (default-ref String)] -> (List GitSearchMatch)
  :d "Parses git grep output across one or more refs into a list of GitSearchMatch records."
  (let [(clean (string-replace raw-output "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitSearchMatch)) (ln String)] -> (List GitSearchMatch)
                          (mt (parse-single-search-line ln default-ref)
                            ((some m) (list-cons m acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df format-search-match-item [(m GitSearchMatch)] -> String
  :d "Formats a single GitSearchMatch record into an ASN S-expression."
  (let [(esc-content (string-replace (.-content m) "\"" "\\\""))]
    (str "(:match :ref \"" (.-ref m) "\""
         " :file \"" (.-file m) "\""
         " :line " (string-from-int64 (.-line m))
         " :content \"" esc-content "\")")))

(df git-search-format [(matches (List GitSearchMatch)) (query String) (limit Int64)] -> String
  :d "Formats a list of GitSearchMatch records into a compact token-bounded :git-search-results ASN envelope."
  (let [(total-cnt (list-length matches))
        (take-cnt (if (or (<= limit 0) (> limit total-cnt)) total-cnt limit))
        (is-trunc (< take-cnt total-cnt))
        (truncated-matches (list-take matches take-cnt))
        (match-items (fold (fn [(acc String) (m GitSearchMatch)] -> String
                             (let [(item (format-search-match-item m))]
                               (if (string-empty? acc)
                                   item
                                   (str acc " " item))))
                           ""
                           truncated-matches))
        (trunc-part (if is-trunc (str " :truncated true :total-matches " (string-from-int64 total-cnt)) ""))]
    (str "(:git-search-results :query \"" query "\""
         " :count " (string-from-int64 take-cnt)
         trunc-part
         " :matches (" match-items "))")))

(df parse-branch-upstream [(s String)] -> String
  :d "Extracts upstream tracking branch from bracketed token [origin/main]."
  (if (and (string-contains? s "[") (string-contains? s "]"))
      (let [(after-bracket (option-or (list-get (string-split s "[") 1) ""))
            (before-close (option-or (list-get (string-split after-bracket "]") 0) ""))
            (clean (string-trim before-close))]
        (if (string-contains? clean ":")
            (option-or (list-get (string-split clean ":") 0) clean)
            clean))
      ""))

(df parse-single-branch-line [(line String)] -> (Option GitBranchRecord)
  :d "Parses a single line from git branch -a -v into a GitBranchRecord."
  (let [(clean (string-trim line))]
    (if (or (string-empty? clean) (string-contains? clean " -> "))
        (none)
        (let [(is-cur (string-starts-with? line "*"))
              (after-star (if is-cur
                              (string-trim (option-or (string-slice line 1 (string-length line)) ""))
                              clean))
              (toks (string-split after-star " "))
              (raw-name (string-trim (option-or (list-get toks 0) "")))]
          (if (string-empty? raw-name)
              (none)
              (let [(is-rem (string-starts-with? raw-name "remotes/"))
                    (clean-name (if is-rem
                                    (option-or (string-slice raw-name 8 (string-length raw-name)) raw-name)
                                    raw-name))
                    (commit-hash (if (> (list-length toks) 1)
                                     (string-trim (option-or (list-get toks 1) ""))
                                     ""))
                    (up (parse-branch-upstream line))]
                (some (GitBranchRecord
                        :name clean-name
                        :commit commit-hash
                        :upstream up
                        :current is-cur
                        :remote is-rem))))))))

(df git-branches-parse [(raw-branches String)] -> (List GitBranchRecord)
  :d "Parses multi-line git branch listing output into a list of GitBranchRecord structures."
  (let [(clean (string-replace raw-branches "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitBranchRecord)) (ln String)] -> (List GitBranchRecord)
                          (mt (parse-single-branch-line ln)
                            ((some b) (list-cons b acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df format-branch-item [(b GitBranchRecord)] -> String
  :d "Formats a single GitBranchRecord into an ASN branch item."
  (let [(cur-part (if (.-current b) " :current true" ""))
        (rem-part (if (.-remote b) " :remote true" ""))
        (up-part (if (string-empty? (.-upstream b))
                     ""
                     (str " :upstream \"" (.-upstream b) "\"")))]
    (str "(:branch :name \"" (.-name b) "\""
         " :commit \"" (.-commit b) "\""
         cur-part
         rem-part
         up-part
         ")")))

(df git-branches-format [(branches (List GitBranchRecord))] -> String
  :d "Formats a list of GitBranchRecord records into a compact :git-branches ASN envelope."
  (let [(count-str (string-from-int64 (list-length branches)))
        (items (fold (fn [(acc String) (b GitBranchRecord)] -> String
                       (let [(item (format-branch-item b))]
                         (if (string-empty? acc)
                             item
                             (str acc " " item))))
                     ""
                     branches))]
    (str "(:git-branches :count " count-str " :branches (" items "))")))
