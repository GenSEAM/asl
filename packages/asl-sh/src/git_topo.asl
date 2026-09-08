(module asl-sh/git-topo
  :d "Pure AgentScript Git topology orientation, linearized history formatting, and on-demand worktree roster management."
  :x [GitTopology
      GitWorktreeEntry
      GitCommitEntry
      git-topo-parse
      git-topo-format
      git-worktree-parse
      git-worktrees-format
      git-log-parse
      git-log-format])

(dfs GitTopology
  (:f branch String "Current branch name or HEAD state")
  (:f commit String "Current commit hash or OID")
  (:f oid String "Current commit hash or OID alias")
  (:f upstream String "Upstream branch tracking reference or empty string")
  (:f detached Bool "True if repository is in detached HEAD state")
  (:f root String "Worktree or repository root path")
  (:f worktree-root String "Worktree or repository root path alias")
  (:f staged Int64 "Count of staged changes")
  (:f unstaged Int64 "Count of unstaged changes")
  (:f untracked Int64 "Count of untracked files")
  (:f conflicts Int64 "Count of unmerged conflicted files")
  (:f ahead Int64 "Commits ahead of upstream")
  (:f behind Int64 "Commits behind upstream"))

(dfs GitWorktreeEntry
  (:f path String "Filesystem path to the worktree root")
  (:f commit String "HEAD commit hash checked out in the worktree")
  (:f head String "HEAD commit hash checked out alias")
  (:f branch String "Branch ref or branch name checked out, or detached")
  (:f locked Bool "True if the worktree is locked against prune or removal")
  (:f lock-reason String "Reason why worktree was locked or empty string")
  (:f prunable Bool "True if worktree is marked prunable"))

(dfs GitCommitEntry
  (:f hash String "Full or short commit hash")
  (:f short-hash String "Shortened commit hash")
  (:f author String "Commit author name or empty string")
  (:f date String "Commit date string or empty string")
  (:f message String "Commit message or subject line")
  (:f summary String "Commit summary line alias"))

(dfs TopoState
  (:f branch String "Current branch")
  (:f commit String "Commit oid")
  (:f upstream String "Upstream ref")
  (:f detached Bool "Is detached")
  (:f root String "Root path")
  (:f staged Int64 "Staged count")
  (:f unstaged Int64 "Unstaged count")
  (:f untracked Int64 "Untracked count")
  (:f conflicts Int64 "Conflicts count")
  (:f ahead Int64 "Ahead count")
  (:f behind Int64 "Behind count"))

(dfs WtState
  (:f entries (List GitWorktreeEntry) "List of accumulated worktree entries")
  (:f cur-path String "Current entry path")
  (:f cur-commit String "Current entry commit")
  (:f cur-branch String "Current entry branch")
  (:f cur-locked Bool "Current entry locked status")
  (:f cur-lock-reason String "Current entry lock reason")
  (:f cur-prunable Bool "Current entry prunable status")
  (:f in-entry Bool "True if currently inside a worktree block"))

(df update-topo-oid [(st TopoState) (t String)] -> TopoState
  :d "Updates commit OID in TopoState."
  (let [(oid (string-trim (option-or (string-slice t 13 (string-length t)) "")))]
    (TopoState :branch (.-branch st) :commit oid :upstream (.-upstream st) :detached (.-detached st)
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df update-topo-head [(st TopoState) (t String)] -> TopoState
  :d "Updates branch name and detached status in TopoState."
  (let [(h (string-trim (option-or (string-slice t 14 (string-length t)) "")))
        (is-det (= h "(detached)"))]
    (TopoState :branch h :commit (.-commit st) :upstream (.-upstream st) :detached is-det
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df update-topo-upstream [(st TopoState) (t String)] -> TopoState
  :d "Updates upstream reference in TopoState."
  (let [(u (string-trim (option-or (string-slice t 18 (string-length t)) "")))]
    (TopoState :branch (.-branch st) :commit (.-commit st) :upstream u :detached (.-detached st)
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df update-topo-root [(st TopoState) (t String)] -> TopoState
  :d "Updates worktree root in TopoState."
  (let [(w (string-trim (option-or (string-slice t 11 (string-length t)) "")))]
    (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
               :root w :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df parse-num-part [(s String) (prefix String)] -> Int64
  :d "Parses a signed integer part from ahead-behind token."
  (if (string-starts-with? s prefix)
      (let [(num-str (option-or (string-slice s 1 (string-length s)) "0"))]
        (option-or (string-to-int64 num-str) 0))
      0))

(df update-topo-ab [(st TopoState) (t String)] -> TopoState
  :d "Updates ahead and behind commit counts in TopoState."
  (let [(ab-tail (string-trim (option-or (string-slice t 12 (string-length t)) "")))
        (parts (string-split ab-tail " "))
        (p1 (string-trim (option-or (list-get parts 0) "")))
        (p2 (string-trim (option-or (list-get parts 1) "")))
        (ahead (parse-num-part p1 "+"))
        (behind (parse-num-part p2 "-"))]
    (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead ahead :behind behind)))

(df update-topo-change [(st TopoState) (t String)] -> TopoState
  :d "Updates staged and unstaged counts from porcelain change line."
  (if (>= (string-length t) 4)
      (let [(s-code (option-or (string-slice t 2 3) "."))
            (u-code (option-or (string-slice t 3 4) "."))
            (s-inc (if (!= s-code ".") 1 0))
            (u-inc (if (!= u-code ".") 1 0))]
        (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
                   :root (.-root st) :staged (+ (.-staged st) s-inc) :unstaged (+ (.-unstaged st) u-inc)
                   :untracked (.-untracked st) :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st)))
      st))

(df step-topo-line [(st TopoState) (line String)] -> TopoState
  :d "Accumulates git porcelain v2 line into TopoState."
  (let [(t (string-trim line))]
    (cond
      ((string-starts-with? t "# branch.oid ") (update-topo-oid st t))
      ((string-starts-with? t "# branch.head ") (update-topo-head st t))
      ((string-starts-with? t "# branch.upstream ") (update-topo-upstream st t))
      ((string-starts-with? t "# branch.ab ") (update-topo-ab st t))
      ((string-starts-with? t "# worktree ") (update-topo-root st t))
      ((or (string-starts-with? t "1 ") (string-starts-with? t "2 ")) (update-topo-change st t))
      ((string-starts-with? t "u ")
       (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
                  :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
                  :conflicts (+ (.-conflicts st) 1) :ahead (.-ahead st) :behind (.-behind st)))
      ((string-starts-with? t "? ")
       (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
                  :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (+ (.-untracked st) 1)
                  :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st)))
      (:else st))))

(df git-topo-parse [(raw String)] -> GitTopology
  :d "Parses git status porcelain v2 output into a structured GitTopology record."
  (let [(clean (string-replace raw "\r" ""))
        (lines (string-split clean "\n"))
        (init (TopoState :branch "" :commit "" :upstream "" :detached false :root ""
                         :staged 0 :unstaged 0 :untracked 0 :conflicts 0 :ahead 0 :behind 0))
        (final (fold (fn [(s TopoState) (ln String)] -> TopoState
                       (step-topo-line s ln))
                     init
                     lines))
        (br (if (string-empty? (.-branch final)) "unknown" (.-branch final)))]
    (GitTopology :branch br :commit (.-commit final) :oid (.-commit final)
                 :upstream (.-upstream final) :detached (.-detached final) :root (.-root final)
                 :worktree-root (.-root final) :staged (.-staged final) :unstaged (.-unstaged final)
                 :untracked (.-untracked final) :conflicts (.-conflicts final)
                 :ahead (.-ahead final) :behind (.-behind final))))

(df close-worktree-entry [(st WtState)] -> WtState
  :d "Finalizes the current worktree entry into the accumulated entries list."
  (if (.-in-entry st)
      (let [(entry (GitWorktreeEntry
                     :path (.-cur-path st)
                     :commit (.-cur-commit st)
                     :head (.-cur-commit st)
                     :branch (.-cur-branch st)
                     :locked (.-cur-locked st)
                     :lock-reason (.-cur-lock-reason st)
                     :prunable (.-cur-prunable st)))
            (updated (list-cons entry (.-entries st)))]
        (WtState :entries updated :cur-path "" :cur-commit "" :cur-branch ""
                 :cur-locked false :cur-lock-reason "" :cur-prunable false :in-entry false))
      st))

(df step-worktree-line [(st WtState) (line String)] -> WtState
  :d "Processes one line of git worktree list porcelain output into WtState."
  (let [(t (string-trim line))]
    (cond
      ((string-empty? t) (close-worktree-entry st))
      ((string-starts-with? t "worktree ")
       (let [(st-closed (close-worktree-entry st))
             (p (string-trim (option-or (string-slice t 9 (string-length t)) "")))]
         (WtState :entries (.-entries st-closed) :cur-path p :cur-commit "" :cur-branch ""
                  :cur-locked false :cur-lock-reason "" :cur-prunable false :in-entry true)))
      ((string-starts-with? t "HEAD ")
       (let [(c (string-trim (option-or (string-slice t 5 (string-length t)) "")))]
         (WtState :entries (.-entries st) :cur-path (.-cur-path st) :cur-commit c :cur-branch (.-cur-branch st)
                  :cur-locked (.-cur-locked st) :cur-lock-reason (.-cur-lock-reason st)
                  :cur-prunable (.-cur-prunable st) :in-entry (.-in-entry st))))
      ((string-starts-with? t "branch ")
       (let [(raw-b (string-trim (option-or (string-slice t 7 (string-length t)) "")))
             (b (if (string-starts-with? raw-b "refs/heads/")
                    (option-or (string-slice raw-b 11 (string-length raw-b)) raw-b)
                    raw-b))]
         (WtState :entries (.-entries st) :cur-path (.-cur-path st) :cur-commit (.-cur-commit st)
                  :cur-branch b :cur-locked (.-cur-locked st) :cur-lock-reason (.-cur-lock-reason st)
                  :cur-prunable (.-cur-prunable st) :in-entry (.-in-entry st))))
      ((= t "detached")
       (WtState :entries (.-entries st) :cur-path (.-cur-path st) :cur-commit (.-cur-commit st)
                :cur-branch "(detached)" :cur-locked (.-cur-locked st) :cur-lock-reason (.-cur-lock-reason st)
                :cur-prunable (.-cur-prunable st) :in-entry (.-in-entry st)))
      ((string-starts-with? t "locked")
       (let [(reason (if (> (string-length t) 6)
                         (string-trim (option-or (string-slice t 6 (string-length t)) ""))
                         ""))]
         (WtState :entries (.-entries st) :cur-path (.-cur-path st) :cur-commit (.-cur-commit st)
                  :cur-branch (.-cur-branch st) :cur-locked true :cur-lock-reason reason
                  :cur-prunable (.-cur-prunable st) :in-entry (.-in-entry st))))
      ((string-starts-with? t "prunable")
       (WtState :entries (.-entries st) :cur-path (.-cur-path st) :cur-commit (.-cur-commit st)
                :cur-branch (.-cur-branch st) :cur-locked (.-cur-locked st)
                :cur-lock-reason (.-cur-lock-reason st) :cur-prunable true :in-entry (.-in-entry st)))
      (:else st))))

(df git-worktree-parse [(raw String)] -> (List GitWorktreeEntry)
  :d "Parses git worktree list --porcelain output into a list of GitWorktreeEntry records."
  (let [(clean (string-replace raw "\r" ""))
        (lines (string-split clean "\n"))
        (init (WtState :entries (list) :cur-path "" :cur-commit "" :cur-branch ""
                       :cur-locked false :cur-lock-reason "" :cur-prunable false :in-entry false))
        (final (fold (fn [(s WtState) (ln String)] -> WtState
                       (step-worktree-line s ln))
                     init
                     lines))
        (closed (close-worktree-entry final))]
    (list-reverse (.-entries closed))))

(df parse-commit-line [(line String)] -> (Option GitCommitEntry)
  :d "Parses a single linearized commit line into an optional GitCommitEntry."
  (let [(t (string-trim line))]
    (if (string-empty? t)
        (none)
        (if (string-contains? t "|")
            (let [(parts (string-split t "|"))
                  (h (string-trim (option-or (list-get parts 0) "")))
                  (a (string-trim (option-or (list-get parts 1) "")))
                  (d (string-trim (option-or (list-get parts 2) "")))
                  (m (string-trim (option-or (list-get parts 3) "")))
                  (sh (if (> (string-length h) 7) (option-or (string-slice h 0 7) h) h))]
              (some (GitCommitEntry :hash h :short-hash sh :author a :date d :message m :summary m)))
            (let [(parts (string-split t " "))
                  (h (string-trim (option-or (list-get parts 0) "")))
                  (h-len (string-length h))
                  (m (string-trim (option-or (string-slice t h-len (string-length t)) "")))
                  (sh (if (> (string-length h) 7) (option-or (string-slice h 0 7) h) h))]
              (some (GitCommitEntry :hash h :short-hash sh :author "" :date "" :message m :summary m)))))))

(df git-log-parse [(raw String)] -> (List GitCommitEntry)
  :d "Parses linearized git commit history text into a list of GitCommitEntry records."
  (let [(clean (string-replace raw "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitCommitEntry)) (ln String)] -> (List GitCommitEntry)
                          (mt (parse-commit-line ln)
                            ((some e) (list-cons e acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df git-topo-format [(topo GitTopology)] -> String
  :d "Formats a GitTopology record into an agent-oriented ASN S-expression."
  (let [(clean (and (= (.-staged topo) 0)
                    (and (= (.-unstaged topo) 0)
                         (and (= (.-untracked topo) 0)
                              (= (.-conflicts topo) 0)))))
        (up-part (if (string-empty? (.-upstream topo))
                     ""
                     (str " :upstream \"" (.-upstream topo) "\"")))
        (det-part (if (.-detached topo) " :detached true" ""))]
    (str "(:where-am-i :branch \"" (.-branch topo) "\""
         " :commit \"" (.-commit topo) "\""
         up-part
         det-part
         " :root \"" (.-root topo) "\""
         " :clean " (if clean "true" "false")
         " :staged " (string-from-int64 (.-staged topo))
         " :unstaged " (string-from-int64 (.-unstaged topo))
         " :untracked " (string-from-int64 (.-untracked topo))
         " :conflicts " (string-from-int64 (.-conflicts topo))
         " :ahead " (string-from-int64 (.-ahead topo))
         " :behind " (string-from-int64 (.-behind topo)) ")")))

(df format-worktree-item [(entry GitWorktreeEntry)] -> String
  :d "Formats a single GitWorktreeEntry into an ASN record string."
  (let [(lock-part (if (.-locked entry)
                       (if (string-empty? (.-lock-reason entry))
                           " :locked true"
                           (str " :locked true :lock-reason \"" (.-lock-reason entry) "\""))
                       ""))
        (prune-part (if (.-prunable entry) " :prunable true" ""))]
    (str "(:git-worktree :path \"" (.-path entry) "\""
         " :commit \"" (.-commit entry) "\""
         " :branch \"" (.-branch entry) "\""
         lock-part
         prune-part
         ")")))

(df git-worktrees-format [(entries (List GitWorktreeEntry))] -> String
  :d "Formats a list of GitWorktreeEntry records into a compact :git-worktrees ASN envelope."
  (let [(count-str (string-from-int64 (list-length entries)))
        (items (fold (fn [(acc String) (e GitWorktreeEntry)] -> String
                       (let [(item (format-worktree-item e))]
                         (if (string-empty? acc)
                             item
                             (str acc " " item))))
                     ""
                     entries))]
    (str "(:git-worktrees :count " count-str " :entries (" items "))")))

(df format-commit-item [(entry GitCommitEntry)] -> String
  :d "Formats a single GitCommitEntry into an ASN record string."
  (let [(esc-msg (string-replace (.-message entry) "\"" "\\\""))]
    (str "(:git-commit :hash \"" (.-hash entry) "\""
         " :short \"" (.-short-hash entry) "\""
         " :author \"" (.-author entry) "\""
         " :date \"" (.-date entry) "\""
         " :message \"" esc-msg "\")")))

(df git-log-format [(entries (List GitCommitEntry))] -> String
  :d "Formats a list of GitCommitEntry records into a compact :git-log ASN envelope."
  (let [(count-str (string-from-int64 (list-length entries)))
        (items (fold (fn [(acc String) (e GitCommitEntry)] -> String
                       (let [(item (format-commit-item e))]
                         (if (string-empty? acc)
                             item
                             (str acc " " item))))
                     ""
                     entries))]
    (str "(:git-log :count " count-str " :commits (" items "))")))
