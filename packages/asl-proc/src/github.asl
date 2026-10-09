(module asl-proc/github :x [GitHubPrSummary GitHubIssue GitHubCiCheck githubPrParse githubIssueParse githubDiffCompact githubCiParse githubCiRollup githubPrsFormat githubIssuesFormat githubCiFormat])

(schema GitHubPrSummary (:f number Int64) (:f title String) (:f author String) (:f head String) (:f base String) (:f state String) (:f labels (List String)) (:f additions Int64) (:f deletions Int64))

(schema GitHubIssue (:f number Int64) (:f title String) (:f author String) (:f state String) (:f labels (List String)) (:f assignees (List String)) (:f commentsCount Int64) (:f body String))

(schema GitHubCiCheck (:f name String) (:f status String) (:f conclusion String) (:f targetUrl String))

(schema ObjScanState (:f objects (List String)) (:f startIdx Int64) (:f curIdx Int64) (:f depth Int64) (:f inStr Bool) (:f esc Bool))

(schema QuoteScanState (:f found (Option Int64)) (:f idx Int64) (:f esc Bool))

(schema DigitScanState (:f digits (List String)) (:f done Bool))

(schema LabelsScanState (:f idx Int64) (:f labels (List String)))

(schema AssigneesScanState (:f idx Int64) (:f assignees (List String)))

(schema CompactHunk (:f range String) (:f deltas (List String)))

(schema CompactFile (:f path String) (:f additions Int64) (:f deletions Int64) (:f hunks (List CompactHunk)))

(schema DiffScanState (:f files (List CompactFile)) (:f curPath String) (:f curAdds Int64) (:f curDels Int64) (:f curHunks (List CompactHunk)) (:f curRange String) (:f curDeltas (List String)) (:f inHunk Bool) (:f inFile Bool))

fn splitJsonObjects text: String -> (List String)
  (let [(trimmed (stringTrim text))] (if (or (stringEmpty? trimmed) (or (= trimmed "[]") (= trimmed "{}"))) (list) (let [(chars (stringChars trimmed)) (initSt (ObjScanState :objects (list) :startIdx 0 :curIdx 0 :depth 0 :inStr false :esc false)) (finalSt (fold (fn [(st ObjScanState) (c String)] -> ObjScanState (let [(cur st.curIdx) (nextIdx (+ cur 1))] (cond (st.esc (ObjScanState :objects st.objects :startIdx st.startIdx :curIdx nextIdx :depth st.depth :inStr st.inStr :esc false)) ((= c "\\") (ObjScanState :objects st.objects :startIdx st.startIdx :curIdx nextIdx :depth st.depth :inStr st.inStr :esc st.inStr)) ((= c "\"") (ObjScanState :objects st.objects :startIdx st.startIdx :curIdx nextIdx :depth st.depth :inStr (not st.inStr) :esc false)) (st.inStr (ObjScanState :objects st.objects :startIdx st.startIdx :curIdx nextIdx :depth st.depth :inStr true :esc false)) ((= c "{") (let [(d (+ st.depth 1)) (sIdx (if (= st.depth 0) cur st.startIdx))] (ObjScanState :objects st.objects :startIdx sIdx :curIdx nextIdx :depth d :inStr false :esc false))) ((= c "}") (let [(d (- st.depth 1))] (if (= d 0) (let [(objStr (optionOr (stringSlice trimmed st.startIdx nextIdx) ""))] (ObjScanState :objects (cons objStr st.objects) :startIdx 0 :curIdx nextIdx :depth 0 :inStr false :esc false)) (ObjScanState :objects st.objects :startIdx st.startIdx :curIdx nextIdx :depth d :inStr false :esc false)))) (else (ObjScanState :objects st.objects :startIdx st.startIdx :curIdx nextIdx :depth st.depth :inStr false :esc false))))) initSt chars))] (if (= finalSt.depth 0) (listReverse finalSt.objects) (list)))))

fn jsonFindKeyTail obj: String key: String -> String
  (let [(needle (str "\"" key "\""))] (mt (stringIndexOf obj needle) ((none) "") ((some idx) (let [(tailPos (+ idx (stringLength needle))) (tail (optionOr (stringSlice obj tailPos (stringLength obj)) ""))] (mt (stringIndexOf tail ":") ((none) "") ((some cIdx) (optionOr (stringSlice tail (+ cIdx 1) (stringLength tail)) "")))))))

fn findUnescapedQuote chars: (List String) -> (Option Int64)
  (let [(finalSt (fold (fn [(st QuoteScanState) (c String)] -> QuoteScanState (mt st.found ((some _) st) ((none) (let [(cur st.idx) (next (+ cur 1))] (if st.esc (QuoteScanState :found (none) :idx next :esc false) (if (= c "\\") (QuoteScanState :found (none) :idx next :esc true) (if (= c "\"") (QuoteScanState :found (some cur) :idx next :esc false) (QuoteScanState :found (none) :idx next :esc false)))))))) (QuoteScanState :found (none) :idx 0 :esc false) chars))] finalSt.found)

fn jsonExtractStr obj: String key: String -> String
  (let [(tail (stringTrim (jsonFindKeyTail obj key)))] (if (stringStartsWith? tail "\"") (let [(inner (optionOr (stringSlice tail 1 (stringLength tail)) "")) (chars (stringChars inner))] (mt (findUnescapedQuote chars) ((some qIdx) (let [(rawVal (optionOr (stringSlice inner 0 qIdx) ""))] (stringReplace (stringReplace rawVal "\\\"" "\"") "\\n" "\n"))) ((none) ""))) ""))

fn isDigitChar? c: String -> Bool
  (or (= c "0") (or (= c "1") (or (= c "2") (or (= c "3") (or (= c "4") (or (= c "5") (or (= c "6") (or (= c "7") (or (= c "8") (or (= c "9") (= c "-")))))))))))

fn extractDigits chars: (List String) -> String
  (let [(finalSt (fold (fn [(st DigitScanState) (c String)] -> DigitScanState (if st.done st (if (isDigitChar? c) (DigitScanState :digits (cons c st.digits) :done false) (DigitScanState :digits st.digits :done true)))) (DigitScanState :digits (list) :done false) chars))] (stringJoin (listReverse finalSt.digits) ""))

fn jsonExtractInt obj: String key: String -> Int64
  (let [(tail (stringTrim (jsonFindKeyTail obj key)))] (if (stringEmpty? tail) 0 (let [(chars (stringChars tail)) (digits (extractDigits chars))] (if (stringEmpty? digits) 0 (optionOr (stringToInt64 digits) 0)))))

fn jsonExtractAuthor obj: String -> String
  (let [(tail (stringTrim (jsonFindKeyTail obj "author")))] (if (stringStartsWith? tail "{") (let [(login (jsonExtractStr tail "login"))] (if (stringEmpty? login) (jsonExtractStr tail "name") login)) (if (stringStartsWith? tail "\"") (jsonExtractStr obj "author") (let [(userTail (stringTrim (jsonFindKeyTail obj "user")))] (if (stringStartsWith? userTail "{") (jsonExtractStr userTail "login") (if (stringStartsWith? userTail "\"") (jsonExtractStr obj "user") ""))))))

fn jsonExtractRef obj: String refKey: String fallbackKey: String -> String
  (let [(v1 (jsonExtractStr obj refKey))] (if (not (stringEmpty? v1)) v1 (let [(tail (stringTrim (jsonFindKeyTail obj fallbackKey)))] (if (stringStartsWith? tail "{") (jsonExtractStr tail "ref") (if (stringStartsWith? tail "\"") (jsonExtractStr obj fallbackKey) "")))))

fn extractLabelsFromArrayInner inner: String -> (List String)
  (if (stringContains? inner "\"name\"") (let [(parts (stringSplit inner "\"name\"")) (labelsRev (fold (fn [(acc (List String)) (part String)] -> (List String) (let [(tail (stringTrim part))] (mt (stringIndexOf tail ":") ((none) acc) ((some cIdx) (let [(afterColon (stringTrim (optionOr (stringSlice tail (+ cIdx 1) (stringLength tail)) "")))] (if (stringStartsWith? afterColon "\"") (let [(raw (optionOr (stringSlice afterColon 1 (stringLength afterColon)) "")) (qIdx (stringIndexOf raw "\""))] (mt qIdx ((some idx) (let [(label (optionOr (stringSlice raw 0 idx) ""))] (if (stringEmpty? label) acc (cons label acc)))) ((none) acc))) acc)))))) (list) parts))] (listReverse labelsRev)) (let [(parts (stringSplit inner "\"")) (labelsRev (fold (fn [(acc LabelsScanState) (part String)] -> LabelsScanState (let [(idx acc.idx) (lst acc.labels)] (if (= (mod idx 2) 1) (let [(clean (stringTrim part))] (if (stringEmpty? clean) (LabelsScanState :idx (+ idx 1) :labels lst) (LabelsScanState :idx (+ idx 1) :labels (cons clean lst)))) (LabelsScanState :idx (+ idx 1) :labels lst)))) (LabelsScanState :idx 0 :labels (list)) parts))] (listReverse labelsRev.labels)))

fn jsonExtractLabels obj: String -> (List String)
  (let [(tail (stringTrim (jsonFindKeyTail obj "labels")))] (if (stringStartsWith? tail "[") (let [(afterBracket (optionOr (stringSlice tail 1 (stringLength tail)) ""))] (mt (stringIndexOf afterBracket "]") ((some endIdx) (let [(inner (optionOr (stringSlice afterBracket 0 endIdx) ""))] (extractLabelsFromArrayInner inner))) ((none) (list)))) (list)))

fn extractAssigneesFromArrayInner inner: String -> (List String)
  (if (stringContains? inner "\"login\"") (let [(parts (stringSplit inner "\"login\"")) (assigneesRev (fold (fn [(acc (List String)) (part String)] -> (List String) (let [(tail (stringTrim part))] (mt (stringIndexOf tail ":") ((none) acc) ((some cIdx) (let [(afterColon (stringTrim (optionOr (stringSlice tail (+ cIdx 1) (stringLength tail)) "")))] (if (stringStartsWith? afterColon "\"") (let [(raw (optionOr (stringSlice afterColon 1 (stringLength afterColon)) "")) (qIdx (stringIndexOf raw "\""))] (mt qIdx ((some idx) (let [(login (optionOr (stringSlice raw 0 idx) ""))] (if (stringEmpty? login) acc (cons login acc)))) ((none) acc))) acc)))))) (list) parts))] (listReverse assigneesRev)) (let [(parts (stringSplit inner "\"")) (assigneesRev (fold (fn [(acc AssigneesScanState) (part String)] -> AssigneesScanState (let [(idx acc.idx) (lst acc.assignees)] (if (= (mod idx 2) 1) (let [(clean (stringTrim part))] (if (stringEmpty? clean) (AssigneesScanState :idx (+ idx 1) :assignees lst) (AssigneesScanState :idx (+ idx 1) :assignees (cons clean lst)))) (AssigneesScanState :idx (+ idx 1) :assignees lst)))) (AssigneesScanState :idx 0 :assignees (list)) parts))] (listReverse assigneesRev.assignees)))

fn jsonExtractAssignees obj: String -> (List String)
  (let [(tail (stringTrim (jsonFindKeyTail obj "assignees")))] (if (stringStartsWith? tail "[") (let [(afterBracket (optionOr (stringSlice tail 1 (stringLength tail)) ""))] (mt (stringIndexOf afterBracket "]") ((some endIdx) (let [(inner (optionOr (stringSlice afterBracket 0 endIdx) ""))] (extractAssigneesFromArrayInner inner))) ((none) (list)))) (list)))

fn jsonExtractCommentsCount obj: String -> Int64
  (let [(c1 (jsonExtractInt obj "commentsCount"))] (if (> c1 0) c1 (let [(c2 (jsonExtractInt obj "comments_count"))] (if (> c2 0) c2 (let [(tail (stringTrim (jsonFindKeyTail obj "comments")))] (if (stringStartsWith? tail "[") (let [(afterBracket (optionOr (stringSlice tail 1 (stringLength tail)) ""))] (mt (stringIndexOf afterBracket "]") ((some endIdx) (let [(inner (optionOr (stringSlice afterBracket 0 endIdx) "")) (objs (splitJsonObjects inner))] (listLength objs))) ((none) 0))) 0))))))

fn truncateBodyLines body: String maxLines: Int64 -> String
  (let [(lines (stringSplit body "\n")) (total (listLength lines))] (if (> total maxLines) (let [(kept (optionOr (listSlice lines 0 maxLines) (list))) (joined (stringJoin kept "\n"))] (str joined "\n... [truncated, " (stringFromInt64 total) " lines total] ...")) body))

fn parsePrSummary obj: String -> GitHubPrSummary
  (GitHubPrSummary :number (jsonExtractInt obj "number") :title (jsonExtractStr obj "title") :author (jsonExtractAuthor obj) :head (jsonExtractRef obj "headRefName" "head") :base (jsonExtractRef obj "baseRefName" "base") :state (jsonExtractStr obj "state") :labels (jsonExtractLabels obj) :additions (jsonExtractInt obj "additions") :deletions (jsonExtractInt obj "deletions"))

fn githubPrParse jsonStr: String -> (List GitHubPrSummary)
  (let [(objs (splitJsonObjects jsonStr))] (map (fn [(obj String)] -> GitHubPrSummary (parsePrSummary obj)) objs))

fn parseIssue obj: String -> GitHubIssue
  (let [(rawBody (jsonExtractStr obj "body")) (cappedBody (truncateBodyLines rawBody 1000))] (GitHubIssue :number (jsonExtractInt obj "number") :title (jsonExtractStr obj "title") :author (jsonExtractAuthor obj) :state (jsonExtractStr obj "state") :labels (jsonExtractLabels obj) :assignees (jsonExtractAssignees obj) :commentsCount (jsonExtractCommentsCount obj) :body cappedBody))

fn githubIssueParse jsonStr: String -> (List GitHubIssue)
  (let [(objs (splitJsonObjects jsonStr))] (map (fn [(obj String)] -> GitHubIssue (parseIssue obj)) objs))

fn extractTargetUrl obj: String -> String
  (let [(u1 (jsonExtractStr obj "targetUrl"))] (if (not (stringEmpty? u1)) u1 (let [(u2 (jsonExtractStr obj "target_url"))] (if (not (stringEmpty? u2)) u2 (let [(u3 (jsonExtractStr obj "details_url"))] (if (not (stringEmpty? u3)) u3 (jsonExtractStr obj "url")))))))

fn parseCiCheck obj: String -> GitHubCiCheck
  (let [(conc (jsonExtractStr obj "conclusion")) (finalConc (if (stringEmpty? conc) (jsonExtractStr obj "state") conc))] (GitHubCiCheck :name (jsonExtractStr obj "name") :status (jsonExtractStr obj "status") :conclusion finalConc :targetUrl (extractTargetUrl obj)))

fn githubCiParse jsonStr: String -> (List GitHubCiCheck)
  (let [(objs (splitJsonObjects jsonStr))] (map (fn [(obj String)] -> GitHubCiCheck (parseCiCheck obj)) objs))

fn isFailureCheck? c: GitHubCiCheck -> Bool
  (let [(conc (stringUpper c.conclusion)) (st (stringUpper c.status))] (or (= conc "FAILURE") (or (= conc "FAILED") (or (= conc "TIMED_OUT") (or (= conc "ACTION_REQUIRED") (= st "FAILURE"))))))

fn isPendingCheck? c: GitHubCiCheck -> Bool
  (let [(st (stringUpper c.status)) (conc (stringUpper c.conclusion))] (or (= st "IN_PROGRESS") (or (= st "QUEUED") (or (= st "PENDING") (and (= st "COMPLETED") (stringEmpty? conc))))))

fn githubCiRollup checks: (List GitHubCiCheck) -> String
  (if (listEmpty? checks) ":success" (let [(hasFail (fold (fn [(acc Bool) (c GitHubCiCheck)] -> Bool (or acc (isFailureCheck? c))) false checks))] (if hasFail ":failure" (let [(hasPend (fold (fn [(acc Bool) (c GitHubCiCheck)] -> Bool (or acc (isPendingCheck? c))) false checks))] (if hasPend ":pending" ":success")))))

fn cleanDiffPath raw: String -> String
  (let [(t (stringTrim raw))] (if (stringStartsWith? t "a/") (optionOr (stringSlice t 2 (stringLength t)) "") (if (stringStartsWith? t "b/") (optionOr (stringSlice t 2 (stringLength t)) "") t)))

fn extractHunkRange line: String -> String
  (if (stringStartsWith? line "@@ ") (let [(afterPrefix (optionOr (stringSlice line 3 (stringLength line)) ""))] (mt (stringIndexOf afterPrefix "@@") ((some idx) (let [(rangeInner (stringTrim (optionOr (stringSlice afterPrefix 0 idx) "")))] (str "@@ " rangeInner " @@"))) ((none) (stringTrim line)))) (stringTrim line))

fn closeActiveHunkState st: DiffScanState -> DiffScanState
  (if st.inHunk (let [(h (CompactHunk :range st.curRange :deltas (listReverse st.curDeltas)))] (with st :curHunks (cons h st.curHunks) :curRange "" :curDeltas (list) :inHunk false)) st)

fn closeActiveFileState st: DiffScanState -> DiffScanState
  (let [(s0 (closeActiveHunkState st))] (if s0.inFile (let [(f (CompactFile :path s0.curPath :additions s0.curAdds :deletions s0.curDels :hunks (listReverse s0.curHunks)))] (DiffScanState :files (cons f s0.files) :curPath "" :curAdds 0 :curDels 0 :curHunks (list) :curRange "" :curDeltas (list) :inHunk false :inFile false)) s0))

fn stepDiffLine st: DiffScanState line: String -> DiffScanState
  (cond ((stringStartsWith? line "diff --git ") (let [(s0 (closeActiveFileState st)) (parts (stringSplit line " ")) (rawPath (if (>= (listLength parts) 4) (optionOr (listGet parts 3) "") "")) (p (cleanDiffPath rawPath))] (DiffScanState :files s0.files :curPath p :curAdds 0 :curDels 0 :curHunks (list) :curRange "" :curDeltas (list) :inHunk false :inFile true))) ((stringStartsWith? line "--- ") (let [(raw (stringTrim (optionOr (stringSlice line 4 (stringLength line)) "")))] (if (and (not st.inFile) (not (stringEmpty? raw))) (let [(p (cleanDiffPath raw))] (with st :curPath p :curAdds 0 :curDels 0 :curHunks (list) :curRange "" :curDeltas (list) :inHunk false :inFile true)) st))) ((stringStartsWith? line "+++ ") (let [(raw (stringTrim (optionOr (stringSlice line 4 (stringLength line)) "")))] (if (and (not (stringEmpty? raw)) (not (= raw "/dev/null"))) (let [(p (cleanDiffPath raw))] (with st :curPath p :inFile true)) st))) ((stringStartsWith? line "@@ ") (let [(s0 (closeActiveHunkState st)) (rng (extractHunkRange line))] (DiffScanState :files s0.files :curPath s0.curPath :curAdds s0.curAdds :curDels s0.curDels :curHunks s0.curHunks :curRange rng :curDeltas (list) :inHunk true :inFile true))) (else (if st.inHunk (let [(isAdd (and (stringStartsWith? line "+") (not (stringStartsWith? line "+++")))) (isDel (and (stringStartsWith? line "-") (not (stringStartsWith? line "---"))))] (if (or isAdd isDel) (let [(addInc (if isAdd 1 0)) (delInc (if isDel 1 0))] (with st :curAdds (+ st.curAdds addInc) :curDels (+ st.curDels delInc) :curDeltas (cons line st.curDeltas) :inHunk true :inFile true)) st)) st)))

fn formatCompactHunk h: CompactHunk -> String
  (let [(quotedDeltas (map (fn [(d String)] -> String (str "\"" d "\"")) h.deltas)) (deltasStr (stringJoin quotedDeltas " "))] (str "(:hunk :range \"" h.range "\" :deltas (" deltasStr "))"))

fn formatCompactFile f: CompactFile -> String
  (let [(hunkStrs (map (fn [(h CompactHunk)] -> String (formatCompactHunk h)) f.hunks)) (hunksBody (stringJoin hunkStrs " "))] (str "(:file \"" f.path "\" :+ " (stringFromInt64 f.additions) " :- " (stringFromInt64 f.deletions) " :hunks (" hunksBody "))"))

fn parseCompactDiff rawDiff: String -> (List CompactFile)
  (let [(trimmed (stringTrim rawDiff))] (if (stringEmpty? trimmed) (list) (let [(cleanText (stringReplace rawDiff "\r" "")) (lines (stringSplit cleanText "\n")) (initSt (DiffScanState :files (list) :curPath "" :curAdds 0 :curDels 0 :curHunks (list) :curRange "" :curDeltas (list) :inHunk false :inFile false)) (finalSt (fold (fn [(s DiffScanState) (ln String)] -> DiffScanState (stepDiffLine s ln)) initSt lines)) (closedSt (closeActiveFileState finalSt))] (listReverse closedSt.files))))

fn githubDiffCompact rawDiff: String -> String
  (let [(files (parseCompactDiff rawDiff))] (if (listEmpty? files) "(:pr-diff :files ())" (let [(fileStrs (map (fn [(f CompactFile)] -> String (formatCompactFile f)) files)) (filesBody (stringJoin fileStrs " "))] (str "(:pr-diff :files (" filesBody "))"))))

fn formatPrItem pr: GitHubPrSummary -> String
  (let [(labelsStr (fold (fn [(acc String) (lbl String)] -> String (let [(escL (stringReplace lbl "\"" "\\\""))] (if (stringEmpty? acc) (str "\"" escL "\"") (str acc " \"" escL "\"")))) "" pr.labels)) (escTitle (stringReplace pr.title "\"" "\\\""))] (str "(:pr :number " (stringFromInt64 pr.number) " :title \"" escTitle "\"" " :author \"" pr.author "\"" " :head \"" pr.head "\"" " :base \"" pr.base "\"" " :state \"" pr.state "\"" " :additions " (stringFromInt64 pr.additions) " :deletions " (stringFromInt64 pr.deletions) " :labels (" labelsStr "))"))

fn githubPrsFormat prs: (List GitHubPrSummary) -> String
  (let [(items (fold (fn [(acc String) (pr GitHubPrSummary)] -> String (let [(item (formatPrItem pr))] (if (stringEmpty? acc) item (str acc " " item)))) "" prs))] (str "(:github-prs :count " (stringFromInt64 (listLength prs)) " :prs (" items "))"))

fn formatIssueItem issue: GitHubIssue -> String
  (let [(labelsStr (fold (fn [(acc String) (lbl String)] -> String (let [(escL (stringReplace lbl "\"" "\\\""))] (if (stringEmpty? acc) (str "\"" escL "\"") (str acc " \"" escL "\"")))) "" issue.labels)) (escTitle (stringReplace issue.title "\"" "\\\""))] (str "(:issue :number " (stringFromInt64 issue.number) " :title \"" escTitle "\"" " :author \"" issue.author "\"" " :state \"" issue.state "\"" " :comments " (stringFromInt64 issue.commentsCount) " :labels (" labelsStr "))"))

fn githubIssuesFormat issues: (List GitHubIssue) -> String
  (let [(items (fold (fn [(acc String) (issue GitHubIssue)] -> String (let [(item (formatIssueItem issue))] (if (stringEmpty? acc) item (str acc " " item)))) "" issues))] (str "(:github-issues :count " (stringFromInt64 (listLength issues)) " :issues (" items "))"))

fn formatCiItem c: GitHubCiCheck -> String
  (let [(escName (stringReplace c.name "\"" "\\\""))] (str "(:check :name \"" escName "\"" " :status \"" c.status "\"" " :conclusion \"" c.conclusion "\"" (if (stringEmpty? c.targetUrl) "" (str " :url \"" c.targetUrl "\"")) ")"))

fn githubCiFormat checks: (List GitHubCiCheck) -> String
  (let [(verdict (githubCiRollup checks)) (items (fold (fn [(acc String) (c GitHubCiCheck)] -> String (let [(item (formatCiItem c))] (if (stringEmpty? acc) item (str acc " " item)))) "" checks))] (str "(:github-ci :verdict " verdict " :count " (stringFromInt64 (listLength checks)) " :checks (" items "))"))
