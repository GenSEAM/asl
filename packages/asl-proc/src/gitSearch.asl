(module asl-proc/gitSearch :x [GitSearchMatch GitBranchRecord gitSearchParse gitSearchFormat gitBranchesParse gitBranchesFormat])

(schema GitSearchMatch (:f ref String) (:f file String) (:f line Int64) (:f content String))

(schema GitBranchRecord (:f name String) (:f commit String) (:f upstream String) (:f current Bool) (:f remote Bool))

fn parseSearchLineWithRef cleanLine: String -> (Option GitSearchMatch)
  (let [(parts (stringSplit cleanLine ":"))] (if (>= (listLength parts) 4) (let [(r (stringTrim (optionOr (listGet parts 0) ""))) (f (stringTrim (optionOr (listGet parts 1) ""))) (lStr (stringTrim (optionOr (listGet parts 2) "0"))) (lNum (optionOr (stringToInt64 lStr) 0)) (p0Len (+ (stringLength r) 1)) (p1Len (+ (stringLength f) 1)) (p2Len (+ (stringLength lStr) 1)) (prefixLen (+ (+ p0Len p1Len) p2Len)) (c (if (> (stringLength cleanLine) prefixLen) (optionOr (stringSlice cleanLine prefixLen (stringLength cleanLine)) "") ""))] (if (> lNum 0) (some (GitSearchMatch :ref r :file f :line lNum :content c)) (none))) (none)))

fn parseSearchLineLocal cleanLine: String -> (Option GitSearchMatch)
  (let [(parts (stringSplit cleanLine ":"))] (if (>= (listLength parts) 3) (let [(f (stringTrim (optionOr (listGet parts 0) ""))) (lStr (stringTrim (optionOr (listGet parts 1) "0"))) (lNum (optionOr (stringToInt64 lStr) 0)) (p0Len (+ (stringLength f) 1)) (p1Len (+ (stringLength lStr) 1)) (prefixLen (+ p0Len p1Len)) (c (if (> (stringLength cleanLine) prefixLen) (optionOr (stringSlice cleanLine prefixLen (stringLength cleanLine)) "") ""))] (if (> lNum 0) (some (GitSearchMatch :ref "HEAD" :file f :line lNum :content c)) (none))) (none)))

fn parseSingleSearchLine line: String defaultRef: String -> (Option GitSearchMatch)
  (let [(clean (stringTrim line))] (if (stringEmpty? clean) (none) (mt (parseSearchLineWithRef clean) ((some m) (some m)) ((none) (mt (parseSearchLineLocal clean) ((some m2) (some (GitSearchMatch :ref defaultRef :file m2.file :line m2.line :content m2.content))) ((none) (none)))))))

fn gitSearchParse rawOutput: String defaultRef: String -> (List GitSearchMatch)
  (let [(clean (stringReplace rawOutput "\r" "")) (lines (stringSplit clean "\n")) (reversed (fold (fn [(acc (List GitSearchMatch)) (ln String)] -> (List GitSearchMatch) (mt (parseSingleSearchLine ln defaultRef) ((some m) (cons m acc)) ((none) acc))) (list) lines))] (listReverse reversed))

fn formatSearchMatchItem m: GitSearchMatch -> String
  (let [(escContent (stringReplace m.content "\"" "\\\""))] (str "(:match :ref \"" m.ref "\"" " :file \"" m.file "\"" " :line " (stringFromInt64 m.line) " :content \"" escContent "\")"))

fn gitSearchFormat matches: (List GitSearchMatch) query: String limit: Int64 -> String
  (let [(totalCnt (listLength matches)) (takeCnt (if (or (<= limit 0) (> limit totalCnt)) totalCnt limit)) (isTrunc (< takeCnt totalCnt)) (truncatedMatches (listTake matches takeCnt)) (matchItems (fold (fn [(acc String) (m GitSearchMatch)] -> String (let [(item (formatSearchMatchItem m))] (if (stringEmpty? acc) item (str acc " " item)))) "" truncatedMatches)) (truncPart (if isTrunc (str " :truncated true :total-matches " (stringFromInt64 totalCnt)) ""))] (str "(:git-search-results :query \"" query "\"" " :count " (stringFromInt64 takeCnt) truncPart " :matches (" matchItems "))"))

fn parseBranchUpstream s: String -> String
  (if (and (stringContains? s "[") (stringContains? s "]")) (let [(afterBracket (optionOr (listGet (stringSplit s "[") 1) "")) (beforeClose (optionOr (listGet (stringSplit afterBracket "]") 0) "")) (clean (stringTrim beforeClose))] (if (stringContains? clean ":") (optionOr (listGet (stringSplit clean ":") 0) clean) clean)) "")

fn parseSingleBranchLine line: String -> (Option GitBranchRecord)
  (let [(clean (stringTrim line))] (if (or (stringEmpty? clean) (stringContains? clean " -> ")) (none) (let [(isCur (stringStartsWith? line "*")) (afterStar (if isCur (stringTrim (optionOr (stringSlice line 1 (stringLength line)) "")) clean)) (rawToks (stringSplit afterStar " ")) (toks (filter (fn [(t String)] -> Bool (not (stringEmpty? (stringTrim t)))) rawToks)) (rawName (stringTrim (optionOr (listGet toks 0) "")))] (if (stringEmpty? rawName) (none) (let [(isRem (stringStartsWith? rawName "remotes/")) (cleanName (if isRem (optionOr (stringSlice rawName 8 (stringLength rawName)) rawName) rawName)) (commitHash (if (> (listLength toks) 1) (stringTrim (optionOr (listGet toks 1) "")) "")) (up (parseBranchUpstream line))] (some (GitBranchRecord :name cleanName :commit commitHash :upstream up :current isCur :remote isRem)))))))

fn gitBranchesParse rawBranches: String -> (List GitBranchRecord)
  (let [(clean (stringReplace rawBranches "\r" "")) (lines (stringSplit clean "\n")) (reversed (fold (fn [(acc (List GitBranchRecord)) (ln String)] -> (List GitBranchRecord) (mt (parseSingleBranchLine ln) ((some b) (cons b acc)) ((none) acc))) (list) lines))] (listReverse reversed))

fn formatBranchItem b: GitBranchRecord -> String
  (let [(curPart (if b.current " :current true" "")) (remPart (if b.remote " :remote true" "")) (upPart (if (stringEmpty? b.upstream) "" (str " :upstream \"" b.upstream "\"")))] (str "(:branch :name \"" b.name "\"" " :commit \"" b.commit "\"" curPart remPart upPart ")"))

fn gitBranchesFormat branches: (List GitBranchRecord) -> String
  (let [(countStr (stringFromInt64 (listLength branches))) (items (fold (fn [(acc String) (b GitBranchRecord)] -> String (let [(item (formatBranchItem b))] (if (stringEmpty? acc) item (str acc " " item)))) "" branches))] (str "(:git-branches :count " countStr " :branches (" items "))"))
