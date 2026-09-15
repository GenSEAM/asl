(module asl-sh/gitTopo
  :d "Pure AgentScript Git topology orientation, linearized history formatting, and on-demand worktree roster management."
  :x [GitTopology
      GitWorktreeEntry
      GitCommitEntry
      gitTopoParse
      gitTopoFormat
      gitWorktreeParse
      gitWorktreesFormat
      gitLogParse
      gitLogFormat])

(dfs GitTopology
  (:f branch String "Current branch name or HEAD state")
  (:f commit String "Current commit hash or OID")
  (:f oid String "Current commit hash or OID alias")
  (:f upstream String "Upstream branch tracking reference or empty string")
  (:f detached Bool "True if repository is in detached HEAD state")
  (:f root String "Worktree or repository root path")
  (:f worktreeRoot String "Worktree or repository root path alias")
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
  (:f lockReason String "Reason why worktree was locked or empty string")
  (:f prunable Bool "True if worktree is marked prunable"))

(dfs GitCommitEntry
  (:f hash String "Full or short commit hash")
  (:f shortHash String "Shortened commit hash")
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
  (:f curPath String "Current entry path")
  (:f curCommit String "Current entry commit")
  (:f curBranch String "Current entry branch")
  (:f curLocked Bool "Current entry locked status")
  (:f curLockReason String "Current entry lock reason")
  (:f curPrunable Bool "Current entry prunable status")
  (:f inEntry Bool "True if currently inside a worktree block"))

(df updateTopoOid [(st TopoState) (t String)] -> TopoState
  :d "Updates commit OID in TopoState."
  (let [(oid (string-trim (option-or (string-slice t 13 (string-length t)) "")))]
    (TopoState :branch (.-branch st) :commit oid :upstream (.-upstream st) :detached (.-detached st)
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df updateTopoHead [(st TopoState) (t String)] -> TopoState
  :d "Updates branch name and detached status in TopoState."
  (let [(h (string-trim (option-or (string-slice t 14 (string-length t)) "")))
        (isDet (= h "(detached)"))]
    (TopoState :branch h :commit (.-commit st) :upstream (.-upstream st) :detached isDet
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df updateTopoUpstream [(st TopoState) (t String)] -> TopoState
  :d "Updates upstream reference in TopoState."
  (let [(u (string-trim (option-or (string-slice t 18 (string-length t)) "")))]
    (TopoState :branch (.-branch st) :commit (.-commit st) :upstream u :detached (.-detached st)
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df updateTopoRoot [(st TopoState) (t String)] -> TopoState
  :d "Updates worktree root in TopoState."
  (let [(w (string-trim (option-or (string-slice t 11 (string-length t)) "")))]
    (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
               :root w :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st))))

(df parseNumPart [(s String) (prefix String)] -> Int64
  :d "Parses a signed integer part from ahead-behind token."
  (if (string-starts-with? s prefix)
      (let [(numStr (option-or (string-slice s 1 (string-length s)) "0"))]
        (option-or (string-to-int64 numStr) 0))
      0))

(df updateTopoAb [(st TopoState) (t String)] -> TopoState
  :d "Updates ahead and behind commit counts in TopoState."
  (let [(abTail (string-trim (option-or (string-slice t 12 (string-length t)) "")))
        (parts (string-split abTail " "))
        (p1 (string-trim (option-or (list-get parts 0) "")))
        (p2 (string-trim (option-or (list-get parts 1) "")))
        (ahead (parseNumPart p1 "+"))
        (behind (parseNumPart p2 "-"))]
    (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
               :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
               :conflicts (.-conflicts st) :ahead ahead :behind behind)))

(df updateTopoChange [(st TopoState) (t String)] -> TopoState
  :d "Updates staged and unstaged counts from porcelain change line."
  (if (>= (string-length t) 4)
      (let [(sCode (option-or (string-slice t 2 3) "."))
            (uCode (option-or (string-slice t 3 4) "."))
            (sInc (if (!= sCode ".") 1 0))
            (uInc (if (!= uCode ".") 1 0))]
        (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
                   :root (.-root st) :staged (+ (.-staged st) sInc) :unstaged (+ (.-unstaged st) uInc)
                   :untracked (.-untracked st) :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st)))
      st))

(df stepTopoLine [(st TopoState) (line String)] -> TopoState
  :d "Accumulates git porcelain v2 line into TopoState."
  (let [(t (string-trim line))]
    (cond
      ((string-starts-with? t "# branch.oid ") (updateTopoOid st t))
      ((string-starts-with? t "# branch.head ") (updateTopoHead st t))
      ((string-starts-with? t "# branch.upstream ") (updateTopoUpstream st t))
      ((string-starts-with? t "# branch.ab ") (updateTopoAb st t))
      ((string-starts-with? t "# worktree ") (updateTopoRoot st t))
      ((or (string-starts-with? t "1 ") (string-starts-with? t "2 ")) (updateTopoChange st t))
      ((string-starts-with? t "u ")
       (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
                  :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (.-untracked st)
                  :conflicts (+ (.-conflicts st) 1) :ahead (.-ahead st) :behind (.-behind st)))
      ((string-starts-with? t "? ")
       (TopoState :branch (.-branch st) :commit (.-commit st) :upstream (.-upstream st) :detached (.-detached st)
                  :root (.-root st) :staged (.-staged st) :unstaged (.-unstaged st) :untracked (+ (.-untracked st) 1)
                  :conflicts (.-conflicts st) :ahead (.-ahead st) :behind (.-behind st)))
      (:else st))))

(df gitTopoParse [(raw String)] -> GitTopology
  :d "Parses git status porcelain v2 output into a structured GitTopology record."
  (let [(clean (string-replace raw "\r" ""))
        (lines (string-split clean "\n"))
        (init (TopoState :branch "" :commit "" :upstream "" :detached false :root ""
                         :staged 0 :unstaged 0 :untracked 0 :conflicts 0 :ahead 0 :behind 0))
        (final (fold (fn [(s TopoState) (ln String)] -> TopoState
                       (stepTopoLine s ln))
                     init
                     lines))
        (br (if (string-empty? (.-branch final)) "unknown" (.-branch final)))]
    (GitTopology :branch br :commit (.-commit final) :oid (.-commit final)
                 :upstream (.-upstream final) :detached (.-detached final) :root (.-root final)
                 :worktreeRoot (.-root final) :staged (.-staged final) :unstaged (.-unstaged final)
                 :untracked (.-untracked final) :conflicts (.-conflicts final)
                 :ahead (.-ahead final) :behind (.-behind final))))

(df closeWorktreeEntry [(st WtState)] -> WtState
  :d "Finalizes the current worktree entry into the accumulated entries list."
  (if (.-inEntry st)
      (let [(entry (GitWorktreeEntry
                     :path (.-curPath st)
                     :commit (.-curCommit st)
                     :head (.-curCommit st)
                     :branch (.-curBranch st)
                     :locked (.-curLocked st)
                     :lockReason (.-curLockReason st)
                     :prunable (.-curPrunable st)))
            (updated (list-cons entry (.-entries st)))]
        (WtState :entries updated :curPath "" :curCommit "" :curBranch ""
                 :curLocked false :curLockReason "" :curPrunable false :inEntry false))
      st))

(df stepWorktreeLine [(st WtState) (line String)] -> WtState
  :d "Processes one line of git worktree list porcelain output into WtState."
  (let [(t (string-trim line))]
    (cond
      ((string-empty? t) (closeWorktreeEntry st))
      ((string-starts-with? t "worktree ")
       (let [(stClosed (closeWorktreeEntry st))
             (p (string-trim (option-or (string-slice t 9 (string-length t)) "")))]
         (WtState :entries (.-entries stClosed) :curPath p :curCommit "" :curBranch ""
                  :curLocked false :curLockReason "" :curPrunable false :inEntry true)))
      ((string-starts-with? t "HEAD ")
       (let [(c (string-trim (option-or (string-slice t 5 (string-length t)) "")))]
         (WtState :entries (.-entries st) :curPath (.-curPath st) :curCommit c :curBranch (.-curBranch st)
                  :curLocked (.-curLocked st) :curLockReason (.-curLockReason st)
                  :curPrunable (.-curPrunable st) :inEntry (.-inEntry st))))
      ((string-starts-with? t "branch ")
       (let [(rawB (string-trim (option-or (string-slice t 7 (string-length t)) "")))
             (b (if (string-starts-with? rawB "refs/heads/")
                    (option-or (string-slice rawB 11 (string-length rawB)) rawB)
                    rawB))]
         (WtState :entries (.-entries st) :curPath (.-curPath st) :curCommit (.-curCommit st)
                  :curBranch b :curLocked (.-curLocked st) :curLockReason (.-curLockReason st)
                  :curPrunable (.-curPrunable st) :inEntry (.-inEntry st))))
      ((= t "detached")
       (WtState :entries (.-entries st) :curPath (.-curPath st) :curCommit (.-curCommit st)
                :curBranch "(detached)" :curLocked (.-curLocked st) :curLockReason (.-curLockReason st)
                :curPrunable (.-curPrunable st) :inEntry (.-inEntry st)))
      ((string-starts-with? t "locked")
       (let [(reason (if (> (string-length t) 6)
                         (string-trim (option-or (string-slice t 6 (string-length t)) ""))
                         ""))]
         (WtState :entries (.-entries st) :curPath (.-curPath st) :curCommit (.-curCommit st)
                  :curBranch (.-curBranch st) :curLocked true :curLockReason reason
                  :curPrunable (.-curPrunable st) :inEntry (.-inEntry st))))
      ((string-starts-with? t "prunable")
       (WtState :entries (.-entries st) :curPath (.-curPath st) :curCommit (.-curCommit st)
                :curBranch (.-curBranch st) :curLocked (.-curLocked st)
                :curLockReason (.-curLockReason st) :curPrunable true :inEntry (.-inEntry st)))
      (:else st))))

(df gitWorktreeParse [(raw String)] -> (List GitWorktreeEntry)
  :d "Parses git worktree list --porcelain output into a list of GitWorktreeEntry records."
  (let [(clean (string-replace raw "\r" ""))
        (lines (string-split clean "\n"))
        (init (WtState :entries (list) :curPath "" :curCommit "" :curBranch ""
                       :curLocked false :curLockReason "" :curPrunable false :inEntry false))
        (final (fold (fn [(s WtState) (ln String)] -> WtState
                       (stepWorktreeLine s ln))
                     init
                     lines))
        (closed (closeWorktreeEntry final))]
    (list-reverse (.-entries closed))))

(df parseCommitLine [(line String)] -> (Option GitCommitEntry)
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
              (some (GitCommitEntry :hash h :shortHash sh :author a :date d :message m :summary m)))
            (let [(parts (string-split t " "))
                  (h (string-trim (option-or (list-get parts 0) "")))
                  (hLen (string-length h))
                  (m (string-trim (option-or (string-slice t hLen (string-length t)) "")))
                  (sh (if (> (string-length h) 7) (option-or (string-slice h 0 7) h) h))]
              (some (GitCommitEntry :hash h :shortHash sh :author "" :date "" :message m :summary m)))))))

(df gitLogParse [(raw String)] -> (List GitCommitEntry)
  :d "Parses linearized git commit history text into a list of GitCommitEntry records."
  (let [(clean (string-replace raw "\r" ""))
        (lines (string-split clean "\n"))
        (reversed (fold (fn [(acc (List GitCommitEntry)) (ln String)] -> (List GitCommitEntry)
                          (mt (parseCommitLine ln)
                            ((some e) (list-cons e acc))
                            ((none) acc)))
                        (list)
                        lines))]
    (list-reverse reversed)))

(df gitTopoFormat [(topo GitTopology)] -> String
  :d "Formats a GitTopology record into an agent-oriented ASN S-expression."
  (let [(clean (and (= (.-staged topo) 0)
                    (and (= (.-unstaged topo) 0)
                         (and (= (.-untracked topo) 0)
                              (= (.-conflicts topo) 0)))))
        (upPart (if (string-empty? (.-upstream topo))
                     ""
                     (str " :upstream \"" (.-upstream topo) "\"")))
        (detPart (if (.-detached topo) " :detached true" ""))]
    (str "(:where-am-i :branch \"" (.-branch topo) "\""
         " :commit \"" (.-commit topo) "\""
         upPart
         detPart
         " :root \"" (.-root topo) "\""
         " :clean " (if clean "true" "false")
         " :staged " (string-from-int64 (.-staged topo))
         " :unstaged " (string-from-int64 (.-unstaged topo))
         " :untracked " (string-from-int64 (.-untracked topo))
         " :conflicts " (string-from-int64 (.-conflicts topo))
         " :ahead " (string-from-int64 (.-ahead topo))
         " :behind " (string-from-int64 (.-behind topo)) ")")))

(df formatWorktreeItem [(entry GitWorktreeEntry)] -> String
  :d "Formats a single GitWorktreeEntry into an ASN record string."
  (let [(lockPart (if (.-locked entry)
                       (if (string-empty? (.-lockReason entry))
                           " :locked true"
                           (str " :locked true :lock-reason \"" (.-lockReason entry) "\""))
                       ""))
        (prunePart (if (.-prunable entry) " :prunable true" ""))]
    (str "(:git-worktree :path \"" (.-path entry) "\""
         " :commit \"" (.-commit entry) "\""
         " :branch \"" (.-branch entry) "\""
         lockPart
         prunePart
         ")")))

(df gitWorktreesFormat [(entries (List GitWorktreeEntry))] -> String
  :d "Formats a list of GitWorktreeEntry records into a compact :git-worktrees ASN envelope."
  (let [(countStr (string-from-int64 (list-length entries)))
        (items (fold (fn [(acc String) (e GitWorktreeEntry)] -> String
                       (let [(item (formatWorktreeItem e))]
                         (if (string-empty? acc)
                             item
                             (str acc " " item))))
                     ""
                     entries))]
    (str "(:git-worktrees :count " countStr " :entries (" items "))")))

(df formatCommitItem [(entry GitCommitEntry)] -> String
  :d "Formats a single GitCommitEntry into an ASN record string."
  (let [(escMsg (string-replace (.-message entry) "\"" "\\\""))]
    (str "(:git-commit :hash \"" (.-hash entry) "\""
         " :short \"" (.-shortHash entry) "\""
         " :author \"" (.-author entry) "\""
         " :date \"" (.-date entry) "\""
         " :message \"" escMsg "\")")))

(df gitLogFormat [(entries (List GitCommitEntry))] -> String
  :d "Formats a list of GitCommitEntry records into a compact :git-log ASN envelope."
  (let [(countStr (string-from-int64 (list-length entries)))
        (items (fold (fn [(acc String) (e GitCommitEntry)] -> String
                       (let [(item (formatCommitItem e))]
                         (if (string-empty? acc)
                             item
                             (str acc " " item))))
                     ""
                     entries))]
    (str "(:git-log :count " countStr " :commits (" items "))")))
