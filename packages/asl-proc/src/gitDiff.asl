(module asl-proc/gitDiff :x [GitDiffHunk GitDiffFile GitNumstatEntry GitBranchCompare gitDiffParse gitDiffSummary gitNumstatParse gitCompareFormat])

(schema GitDiffHunk (:f oldStart Int64) (:f oldCount Int64) (:f newStart Int64) (:f newCount Int64) (:f lines (List String)))

(schema GitDiffFile (:f oldPath String) (:f newPath String) (:f hunks (List GitDiffHunk)) (:f additions Int64) (:f deletions Int64))

(schema ParseState (:f files (List GitDiffFile)) (:f curOldPath String) (:f curNewPath String) (:f curHunks (List GitDiffHunk)) (:f curAdditions Int64) (:f curDeletions Int64) (:f curHunk (Option GitDiffHunk)) (:f hasFile Bool))

fn cleanDiffPath raw: String -> String
  (let [(noTab (if (stringContains? raw "\t") (optionOr (listGet (stringSplit raw "\t") 0) raw) raw))] (stringTrim noTab))

fn extractDiffPath line: String prefix: String -> String
  (let [(pLen (stringLength prefix)) (rawTail (optionOr (stringSlice line pLen (stringLength line)) "")) (trimmed (cleanDiffPath rawTail))] (cond ((stringStartsWith? trimmed "a/") (optionOr (stringSlice trimmed 2 (stringLength trimmed)) "")) ((stringStartsWith? trimmed "b/") (optionOr (stringSlice trimmed 2 (stringLength trimmed)) "")) (else trimmed)))

fn parseRangeToken tok: String prefix: String -> (Pair Int64 Int64)
  (let [(pLen (stringLength prefix)) (cleanTok (optionOr (stringSlice tok pLen (stringLength tok)) "")) (nums (stringSplit cleanTok ",")) (startStr (stringTrim (optionOr (listGet nums 0) "0"))) (startVal (optionOr (stringToInt64 startStr) 0))] (if (> (listLength nums) 1) (let [(countStr (stringTrim (optionOr (listGet nums 1) "0"))) (countVal (optionOr (stringToInt64 countStr) 0))] (pair startVal countVal)) (pair startVal 1)))

fn findTokenWithPrefix toks: (List String) prefix: String -> String
  (fold (fn [(acc String) (tok String)] -> String (if (stringEmpty? acc) (let [(t (stringTrim tok))] (if (stringStartsWith? t prefix) t "")) acc)) "" toks)

fn parseHunkHeader line: String -> (Option GitDiffHunk)
  (if (stringStartsWith? line "@@ ") (let [(afterPrefix (optionOr (stringSlice line 3 (stringLength line)) "")) (parts (stringSplit afterPrefix "@@"))] (if (>= (listLength parts) 2) (let [(rangeStr (stringTrim (optionOr (listGet parts 0) ""))) (toks (stringSplit rangeStr " ")) (oldTok (findTokenWithPrefix toks "-")) (newTok (findTokenWithPrefix toks "+"))] (if (and (not (stringEmpty? oldTok)) (not (stringEmpty? newTok))) (let [(oldRange (parseRangeToken oldTok "-")) (newRange (parseRangeToken newTok "+"))] (some (GitDiffHunk :oldStart (pairFirst oldRange) :oldCount (pairSecond oldRange) :newStart (pairFirst newRange) :newCount (pairSecond newRange) :lines (list)))) (none))) (none))) (none))

fn closeActiveHunk hOpt: (Option GitDiffHunk) hunks: (List GitDiffHunk) -> (List GitDiffHunk)
  (mt hOpt ((some h) (let [(finalH (GitDiffHunk :oldStart h.oldStart :oldCount h.oldCount :newStart h.newStart :newCount h.newCount :lines (listReverse h.lines)))] (cons finalH hunks))) ((none) hunks))

fn closeActiveFile st: ParseState -> ParseState
  (if st.hasFile (let [(finalHunks (listReverse (closeActiveHunk st.curHunk st.curHunks))) (f (GitDiffFile :oldPath st.curOldPath :newPath st.curNewPath :hunks finalHunks :additions st.curAdditions :deletions st.curDeletions))] (ParseState :files (cons f st.files) :curOldPath "" :curNewPath "" :curHunks (list) :curAdditions 0 :curDeletions 0 :curHunk (none) :hasFile false)) st)

fn handleDiffGit st: ParseState line: String -> ParseState
  (let [(s0 (closeActiveFile st)) (parts (stringSplit line " ")) (pOld (if (>= (listLength parts) 4) (let [(raw (optionOr (listGet parts 2) ""))] (if (stringStartsWith? raw "a/") (optionOr (stringSlice raw 2 (stringLength raw)) "") raw)) "")) (pNew (if (>= (listLength parts) 4) (let [(raw (optionOr (listGet parts 3) ""))] (if (stringStartsWith? raw "b/") (optionOr (stringSlice raw 2 (stringLength raw)) "") raw)) ""))] (ParseState :files s0.files :curOldPath pOld :curNewPath pNew :curHunks (list) :curAdditions 0 :curDeletions 0 :curHunk (none) :hasFile true))

fn handleOldPath st: ParseState line: String -> ParseState
  (let [(needsClose (and st.hasFile (or (not (listEmpty? st.curHunks)) (mt st.curHunk ((some _) true) ((none) false))))) (s0 (if needsClose (closeActiveFile st) st)) (oldP (extractDiffPath line "--- "))] (ParseState :files s0.files :curOldPath oldP :curNewPath s0.curNewPath :curHunks s0.curHunks :curAdditions s0.curAdditions :curDeletions s0.curDeletions :curHunk s0.curHunk :hasFile true))

fn handleNewPath st: ParseState line: String -> ParseState
  (let [(newP (extractDiffPath line "+++ "))] (with st :curNewPath newP :hasFile true))

fn handleHunkHead st: ParseState line: String -> ParseState
  (let [(hunks1 (closeActiveHunk st.curHunk st.curHunks)) (newHunk (parseHunkHeader line))] (with st :curHunks hunks1 :curHunk newHunk :hasFile true))

fn handleHunkLine st: ParseState line: String h: GitDiffHunk -> ParseState
  (let [(isAdd (and (stringStartsWith? line "+") (not (stringStartsWith? line "+++")))) (isDel (and (stringStartsWith? line "-") (not (stringStartsWith? line "---")))) (h2 (with h :lines (cons line h.lines))) (addInc (if isAdd 1 0)) (delInc (if isDel 1 0))] (with st :curAdditions (+ st.curAdditions addInc) :curDeletions (+ st.curDeletions delInc) :curHunk (some h2)))

fn stepDiffLine st: ParseState line: String -> ParseState
  (cond ((stringStartsWith? line "diff --git ") (handleDiffGit st line)) ((stringStartsWith? line "--- ") (handleOldPath st line)) ((stringStartsWith? line "+++ ") (handleNewPath st line)) ((stringStartsWith? line "@@ ") (handleHunkHead st line)) (else (mt st.curHunk ((some h) (handleHunkLine st line h)) ((none) st))))

fn gitDiffParse diffText: String -> (List GitDiffFile)
  (let [(trimmed (stringTrim diffText))] (if (stringEmpty? trimmed) (list) (let [(cleanText (stringReplace diffText "\r" "")) (lines (stringSplit cleanText "\n")) (initSt (ParseState :files (list) :curOldPath "" :curNewPath "" :curHunks (list) :curAdditions 0 :curDeletions 0 :curHunk (none) :hasFile false)) (finalSt (fold (fn [(s ParseState) (ln String)] -> ParseState (stepDiffLine s ln)) initSt lines)) (closedSt (closeActiveFile finalSt))] (listReverse closedSt.files))))

fn sumAdditions files: (List GitDiffFile) -> Int64
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc f.additions)) 0 files)

fn sumDeletions files: (List GitDiffFile) -> Int64
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc f.deletions)) 0 files)

fn sumHunks files: (List GitDiffFile) -> Int64
  (fold (fn [(acc Int64) (f GitDiffFile)] -> Int64 (+ acc (listLength f.hunks))) 0 files)

fn gitDiffSummary files: (List GitDiffFile) -> String
  (let [(totalFiles (listLength files)) (totalAdditions (sumAdditions files)) (totalDeletions (sumDeletions files)) (totalHunks (sumHunks files))] (str "(:diff-summary :files " (stringFromInt64 totalFiles) " :additions " (stringFromInt64 totalAdditions) " :deletions " (stringFromInt64 totalDeletions) " :hunks " (stringFromInt64 totalHunks) ")"))

(schema GitNumstatEntry (:f path String) (:f additions Int64) (:f deletions Int64) (:f status String))

(schema GitBranchCompare (:f base String) (:f target String) (:f mergeBase String) (:f ahead Int64) (:f behind Int64) (:f files (List GitNumstatEntry)) (:f totalAdditions Int64) (:f totalDeletions Int64))

fn parseNumstatLine line: String -> (Option GitNumstatEntry)
  (let [(clean (stringTrim line))] (if (stringEmpty? clean) (none) (let [(parts (stringSplit clean "\t"))] (if (>= (listLength parts) 3) (let [(addRaw (stringTrim (optionOr (listGet parts 0) "0"))) (delRaw (stringTrim (optionOr (listGet parts 1) "0"))) (pathRaw (stringTrim (optionOr (listGet parts 2) ""))) (isBin (or (= addRaw "-") (= delRaw "-"))) (adds (if isBin 0 (optionOr (stringToInt64 addRaw) 0))) (dels (if isBin 0 (optionOr (stringToInt64 delRaw) 0))) (st (cond (isBin "binary") ((and (= dels 0) (> adds 0)) "added") ((and (= adds 0) (> dels 0)) "deleted") (else "modified")))] (some (GitNumstatEntry :path pathRaw :additions adds :deletions dels :status st))) (none)))))

fn gitNumstatParse rawNumstat: String -> (List GitNumstatEntry)
  (let [(clean (stringReplace rawNumstat "\r" "")) (lines (stringSplit clean "\n")) (reversed (fold (fn [(acc (List GitNumstatEntry)) (ln String)] -> (List GitNumstatEntry) (mt (parseNumstatLine ln) ((some e) (cons e acc)) ((none) acc))) (list) lines))] (listReverse reversed))

fn formatNumstatEntry e: GitNumstatEntry -> String
  (str "(:file :path \"" e.path "\"" " :status \"" e.status "\"" " :+ " (stringFromInt64 e.additions) " :- " (stringFromInt64 e.deletions) ")")

fn gitCompareFormat cmp: GitBranchCompare limit: Int64 -> String
  (let [(allFiles cmp.files) (totalCnt (listLength allFiles)) (takeCnt (if (or (<= limit 0) (> limit totalCnt)) totalCnt limit)) (isTrunc (< takeCnt totalCnt)) (truncatedFiles (listTake allFiles takeCnt)) (fileItems (fold (fn [(acc String) (f GitNumstatEntry)] -> String (let [(item (formatNumstatEntry f))] (if (stringEmpty? acc) item (str acc " " item)))) "" truncatedFiles)) (truncPart (if isTrunc (str " :truncated true :total-files " (stringFromInt64 totalCnt)) ""))] (str "(:git-compare :base \"" cmp.base "\"" " :target \"" cmp.target "\"" " :merge-base \"" cmp.mergeBase "\"" " :ahead " (stringFromInt64 cmp.ahead) " :behind " (stringFromInt64 cmp.behind) " :files-count " (stringFromInt64 takeCnt) " :+ " (stringFromInt64 cmp.totalAdditions) " :- " (stringFromInt64 cmp.totalDeletions) truncPart " :files (" fileItems "))"))
