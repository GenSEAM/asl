(module asl-proc/gitTopo :x [GitTopology GitWorktreeEntry GitCommitEntry gitTopoParse gitTopoFormat gitWorktreeParse gitWorktreesFormat gitLogParse gitLogFormat])

(schema GitTopology (:f branch String) (:f commit String) (:f oid String) (:f upstream String) (:f detached Bool) (:f root String) (:f worktreeRoot String) (:f staged Int64) (:f unstaged Int64) (:f untracked Int64) (:f conflicts Int64) (:f ahead Int64) (:f behind Int64))

(schema GitWorktreeEntry (:f path String) (:f commit String) (:f head String) (:f branch String) (:f locked Bool) (:f lockReason String) (:f prunable Bool))

(schema GitCommitEntry (:f hash String) (:f shortHash String) (:f author String) (:f date String) (:f message String) (:f summary String))

(schema TopoState (:f branch String) (:f commit String) (:f upstream String) (:f detached Bool) (:f root String) (:f staged Int64) (:f unstaged Int64) (:f untracked Int64) (:f conflicts Int64) (:f ahead Int64) (:f behind Int64))

(schema WtState (:f entries (List GitWorktreeEntry)) (:f curPath String) (:f curCommit String) (:f curBranch String) (:f curLocked Bool) (:f curLockReason String) (:f curPrunable Bool) (:f inEntry Bool))

fn updateTopoOid st: TopoState t: String -> TopoState
  (let [(oid (stringTrim (optionOr (stringSlice t 13 (stringLength t)) "")))] (with st :commit oid))

fn updateTopoHead st: TopoState t: String -> TopoState
  (let [(h (stringTrim (optionOr (stringSlice t 14 (stringLength t)) ""))) (isDet (= h "(detached)"))] (with st :branch h :detached isDet))

fn updateTopoUpstream st: TopoState t: String -> TopoState
  (let [(u (stringTrim (optionOr (stringSlice t 18 (stringLength t)) "")))] (with st :upstream u))

fn updateTopoRoot st: TopoState t: String -> TopoState
  (let [(w (stringTrim (optionOr (stringSlice t 11 (stringLength t)) "")))] (with st :root w))

fn parseNumPart s: String prefix: String -> Int64
  (if (stringStartsWith? s prefix) (let [(numStr (optionOr (stringSlice s 1 (stringLength s)) "0"))] (optionOr (stringToInt64 numStr) 0)) 0)

fn updateTopoAb st: TopoState t: String -> TopoState
  (let [(abTail (stringTrim (optionOr (stringSlice t 12 (stringLength t)) ""))) (parts (stringSplit abTail " ")) (p1 (stringTrim (optionOr (listGet parts 0) ""))) (p2 (stringTrim (optionOr (listGet parts 1) ""))) (ahead (parseNumPart p1 "+")) (behind (parseNumPart p2 "-"))] (with st :ahead ahead :behind behind))

fn updateTopoChange st: TopoState t: String -> TopoState
  (if (>= (stringLength t) 4) (let [(sCode (optionOr (stringSlice t 2 3) ".")) (uCode (optionOr (stringSlice t 3 4) ".")) (sInc (if (!= sCode ".") 1 0)) (uInc (if (!= uCode ".") 1 0))] (with st :staged (+ st.staged sInc) :unstaged (+ st.unstaged uInc))) st)

fn stepTopoLine st: TopoState line: String -> TopoState
  (let [(t (stringTrim line))] (cond ((stringStartsWith? t "# branch.oid ") (updateTopoOid st t)) ((stringStartsWith? t "# branch.head ") (updateTopoHead st t)) ((stringStartsWith? t "# branch.upstream ") (updateTopoUpstream st t)) ((stringStartsWith? t "# branch.ab ") (updateTopoAb st t)) ((stringStartsWith? t "# worktree ") (updateTopoRoot st t)) ((or (stringStartsWith? t "1 ") (stringStartsWith? t "2 ")) (updateTopoChange st t)) ((stringStartsWith? t "u ") (with st :conflicts (+ st.conflicts 1))) ((stringStartsWith? t "? ") (with st :untracked (+ st.untracked 1))) (else st)))

fn gitTopoParse raw: String -> GitTopology
  (let [(clean (stringReplace raw "\r" "")) (lines (stringSplit clean "\n")) (init (TopoState :branch "" :commit "" :upstream "" :detached false :root "" :staged 0 :unstaged 0 :untracked 0 :conflicts 0 :ahead 0 :behind 0)) (final (fold (fn [(s TopoState) (ln String)] -> TopoState (stepTopoLine s ln)) init lines)) (br (if (stringEmpty? final.branch) "unknown" final.branch))] (GitTopology :branch br :commit final.commit :oid final.commit :upstream final.upstream :detached final.detached :root final.root :worktreeRoot final.root :staged final.staged :unstaged final.unstaged :untracked final.untracked :conflicts final.conflicts :ahead final.ahead :behind final.behind))

fn closeWorktreeEntry st: WtState -> WtState
  (if st.inEntry (let [(entry (GitWorktreeEntry :path st.curPath :commit st.curCommit :head st.curCommit :branch st.curBranch :locked st.curLocked :lockReason st.curLockReason :prunable st.curPrunable)) (updated (cons entry st.entries))] (WtState :entries updated :curPath "" :curCommit "" :curBranch "" :curLocked false :curLockReason "" :curPrunable false :inEntry false)) st)

fn stepWorktreeLine st: WtState line: String -> WtState
  (let [(t (stringTrim line))] (cond ((stringEmpty? t) (closeWorktreeEntry st)) ((stringStartsWith? t "worktree ") (let [(stClosed (closeWorktreeEntry st)) (p (stringTrim (optionOr (stringSlice t 9 (stringLength t)) "")))] (WtState :entries stClosed.entries :curPath p :curCommit "" :curBranch "" :curLocked false :curLockReason "" :curPrunable false :inEntry true))) ((stringStartsWith? t "HEAD ") (let [(c (stringTrim (optionOr (stringSlice t 5 (stringLength t)) "")))] (with st :curCommit c))) ((stringStartsWith? t "branch ") (let [(rawB (stringTrim (optionOr (stringSlice t 7 (stringLength t)) ""))) (b (if (stringStartsWith? rawB "refs/heads/") (optionOr (stringSlice rawB 11 (stringLength rawB)) rawB) rawB))] (with st :curBranch b))) ((= t "detached") (with st :curBranch "(detached)")) ((stringStartsWith? t "locked") (let [(reason (if (> (stringLength t) 6) (stringTrim (optionOr (stringSlice t 6 (stringLength t)) "")) ""))] (with st :curLocked true :curLockReason reason))) ((stringStartsWith? t "prunable") (with st :curPrunable true)) (else st)))

fn gitWorktreeParse raw: String -> (List GitWorktreeEntry)
  (let [(clean (stringReplace raw "\r" "")) (lines (stringSplit clean "\n")) (init (WtState :entries (list) :curPath "" :curCommit "" :curBranch "" :curLocked false :curLockReason "" :curPrunable false :inEntry false)) (final (fold (fn [(s WtState) (ln String)] -> WtState (stepWorktreeLine s ln)) init lines)) (closed (closeWorktreeEntry final))] (listReverse closed.entries))

fn parseCommitLine line: String -> (Option GitCommitEntry)
  (let [(t (stringTrim line))] (if (stringEmpty? t) (none) (if (stringContains? t "|") (let [(parts (stringSplit t "|")) (h (stringTrim (optionOr (listGet parts 0) ""))) (a (stringTrim (optionOr (listGet parts 1) ""))) (d (stringTrim (optionOr (listGet parts 2) ""))) (m (stringTrim (optionOr (listGet parts 3) ""))) (sh (if (> (stringLength h) 7) (optionOr (stringSlice h 0 7) h) h))] (some (GitCommitEntry :hash h :shortHash sh :author a :date d :message m :summary m))) (let [(parts (stringSplit t " ")) (h (stringTrim (optionOr (listGet parts 0) ""))) (hLen (stringLength h)) (m (stringTrim (optionOr (stringSlice t hLen (stringLength t)) ""))) (sh (if (> (stringLength h) 7) (optionOr (stringSlice h 0 7) h) h))] (some (GitCommitEntry :hash h :shortHash sh :author "" :date "" :message m :summary m))))))

fn gitLogParse raw: String -> (List GitCommitEntry)
  (let [(clean (stringReplace raw "\r" "")) (lines (stringSplit clean "\n")) (reversed (fold (fn [(acc (List GitCommitEntry)) (ln String)] -> (List GitCommitEntry) (mt (parseCommitLine ln) ((some e) (cons e acc)) ((none) acc))) (list) lines))] (listReverse reversed))

fn gitTopoFormat topo: GitTopology -> String
  (let [(clean (and (= topo.staged 0) (and (= topo.unstaged 0) (and (= topo.untracked 0) (= topo.conflicts 0))))) (upPart (if (stringEmpty? topo.upstream) "" (str " :upstream \"" topo.upstream "\""))) (detPart (if topo.detached " :detached true" ""))] (str "(:where-am-i :branch \"" topo.branch "\"" " :commit \"" topo.commit "\"" upPart detPart " :root \"" topo.root "\"" " :clean " (if clean "true" "false") " :staged " (stringFromInt64 topo.staged) " :unstaged " (stringFromInt64 topo.unstaged) " :untracked " (stringFromInt64 topo.untracked) " :conflicts " (stringFromInt64 topo.conflicts) " :ahead " (stringFromInt64 topo.ahead) " :behind " (stringFromInt64 topo.behind) ")"))

fn formatWorktreeItem entry: GitWorktreeEntry -> String
  (let [(lockPart (if entry.locked (if (stringEmpty? entry.lockReason) " :locked true" (str " :locked true :lock-reason \"" entry.lockReason "\"")) "")) (prunePart (if entry.prunable " :prunable true" ""))] (str "(:git-worktree :path \"" entry.path "\"" " :commit \"" entry.commit "\"" " :branch \"" entry.branch "\"" lockPart prunePart ")"))

fn gitWorktreesFormat entries: (List GitWorktreeEntry) -> String
  (let [(countStr (stringFromInt64 (listLength entries))) (items (fold (fn [(acc String) (e GitWorktreeEntry)] -> String (let [(item (formatWorktreeItem e))] (if (stringEmpty? acc) item (str acc " " item)))) "" entries))] (str "(:git-worktrees :count " countStr " :entries (" items "))"))

fn formatCommitItem entry: GitCommitEntry -> String
  (let [(escMsg (stringReplace entry.message "\"" "\\\""))] (str "(:git-commit :hash \"" entry.hash "\"" " :short \"" entry.shortHash "\"" " :author \"" entry.author "\"" " :date \"" entry.date "\"" " :message \"" escMsg "\")"))

fn gitLogFormat entries: (List GitCommitEntry) -> String
  (let [(countStr (stringFromInt64 (listLength entries))) (items (fold (fn [(acc String) (e GitCommitEntry)] -> String (let [(item (formatCommitItem e))] (if (stringEmpty? acc) item (str acc " " item)))) "" entries))] (str "(:git-log :count " countStr " :commits (" items "))"))
