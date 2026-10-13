(module aslMem/astFilter :x [ASTQuery ASTMatchNode matchAstForm] :i [(vfs :a v)])

(schema ASTQuery (:f formType Str) (:f symbolId (Option Str)) (:f paramCount (Option I64)) (:f predicateToken (Option Str)))

(schema ASTMatchNode (:f formType Str) (:f symbolId Str) (:f startChar I64) (:f endChar I64) (:f rawForm Str) (:f lineNumber I64))

(schema MatchParsed (:f node ASTMatchNode) (:f pCnt (Option I64)))

(schema RawSpan (:f startIdx I64) (:f endIdx I64) (:f lineNum I64))

(schema ScanAcc (:f idx I64) (:f line I64) (:f inStr Bool) (:f esc Bool) (:f inCmt Bool) (:f depth I64) (:f formStart I64) (:f formLine I64) (:f spans (List RawSpan)))

fn isSpaceChar ch: Str -> Bool
  (cond ((= ch " ") true) ((= ch "\t") true) ((= ch "\n") true) ((= ch "\r") true) (else false))

fn scanStepComment acc: ScanAcc ch: Str -> ScanAcc
  (let [(idx acc.idx) (line acc.line) (depth acc.depth) (fStart acc.formStart) (fLine acc.formLine) (spans acc.spans)] (cond ((= ch "\n") (ScanAcc :idx (+ idx 1) :line (+ line 1) :inStr false :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans)) (else (ScanAcc :idx (+ idx 1) :line line :inStr false :esc false :inCmt true :depth depth :formStart fStart :formLine fLine :spans spans))))

fn scanStepString acc: ScanAcc ch: Str -> ScanAcc
  (let [(idx acc.idx) (line acc.line) (esc acc.esc) (depth acc.depth) (fStart acc.formStart) (fLine acc.formLine) (spans acc.spans)] (cond (esc (ScanAcc :idx (+ idx 1) :line line :inStr true :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans)) ((= ch "\\") (ScanAcc :idx (+ idx 1) :line line :inStr true :esc true :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans)) ((= ch "\"") (ScanAcc :idx (+ idx 1) :line line :inStr false :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans)) (else (ScanAcc :idx (+ idx 1) :line line :inStr true :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans))))

fn scanStepDelimOpen acc: ScanAcc ch: Str -> ScanAcc
  (let [(idx acc.idx) (line acc.line) (depth acc.depth) (fStart acc.formStart) (fLine acc.formLine) (spans acc.spans) (isNew (= depth 0)) (nextStart (if isNew idx fStart)) (nextLine (if isNew line fLine))] (ScanAcc :idx (+ idx 1) :line line :inStr false :esc false :inCmt false :depth (+ depth 1) :formStart nextStart :formLine nextLine :spans spans))

fn scanStepDelimClose acc: ScanAcc ch: Str -> ScanAcc
  (let [(idx acc.idx) (line acc.line) (depth acc.depth) (fStart acc.formStart) (fLine acc.formLine) (spans acc.spans) (nextD (if (> depth 0) (- depth 1) 0)) (closed (and (= depth 1) (>= fStart 0))) (newSpan (RawSpan :startIdx fStart :endIdx (+ idx 1) :lineNum fLine)) (nextS (if closed (listAppend spans (list newSpan)) spans)) (nextStart (if closed -1 fStart))] (ScanAcc :idx (+ idx 1) :line line :inStr false :esc false :inCmt false :depth nextD :formStart nextStart :formLine fLine :spans nextS))

fn isOpenDelim? ch: Str -> Bool
  (cond ((= ch "(") true) ((= ch "[") true) ((= ch "{") true) (else false))

fn isCloseDelim? ch: Str -> Bool
  (cond ((= ch ")") true) ((= ch "]") true) ((= ch "}") true) (else false))

fn scanStepNormal acc: ScanAcc ch: Str -> ScanAcc
  (let [(idx acc.idx) (line acc.line) (depth acc.depth) (fStart acc.formStart) (fLine acc.formLine) (spans acc.spans)] (cond ((= ch ";") (ScanAcc :idx (+ idx 1) :line line :inStr false :esc false :inCmt true :depth depth :formStart fStart :formLine fLine :spans spans)) ((= ch "\"") (ScanAcc :idx (+ idx 1) :line line :inStr true :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans)) ((= ch "\n") (ScanAcc :idx (+ idx 1) :line (+ line 1) :inStr false :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans)) ((isOpenDelim? ch) (scanStepDelimOpen acc ch)) ((isCloseDelim? ch) (scanStepDelimClose acc ch)) (else (ScanAcc :idx (+ idx 1) :line line :inStr false :esc false :inCmt false :depth depth :formStart fStart :formLine fLine :spans spans))))

fn scanCharStep acc: ScanAcc ch: Str -> ScanAcc
  (cond (acc.inCmt (scanStepComment acc ch)) (acc.inStr (scanStepString acc ch)) (else (scanStepNormal acc ch)))

fn scanTopLevelSpans content: Str -> (List RawSpan)
  (let [(chars (stringChars content)) (initAcc (ScanAcc :idx 0 :line 1 :inStr false :esc false :inCmt false :depth 0 :formStart -1 :formLine 1 :spans (list))) (finalAcc (fold (fn [(acc ScanAcc) (ch Str)] -> ScanAcc (scanCharStep acc ch)) initAcc chars))] finalAcc.spans)

(schema HeaderAcc (:f idx I64) (:f curToken Str) (:f tokens (List Str)) (:f maxTokens I64))

fn headerCharStep acc: HeaderAcc ch: Str -> HeaderAcc
  (let [(tokens acc.tokens) (maxTok acc.maxTokens)] (if (>= (listLength tokens) maxTok) acc (let [(idx acc.idx) (cur acc.curToken)] (if (or (isSpaceChar ch) (or (= ch "(") (or (= ch ")") (or (= ch "[") (= ch "]"))))) (if (stringEmpty? cur) (HeaderAcc :idx (+ idx 1) :curToken "" :tokens tokens :maxTokens maxTok) (HeaderAcc :idx (+ idx 1) :curToken "" :tokens (listAppend tokens (list cur)) :maxTokens maxTok)) (HeaderAcc :idx (+ idx 1) :curToken (str cur ch) :tokens tokens :maxTokens maxTok)))))

fn extractHeaderTokens raw: Str maxTokens: I64 -> (List Str)
  (let [(chars (stringChars raw)) (init (HeaderAcc :idx 0 :curToken "" :tokens (list) :maxTokens maxTokens)) (res (fold (fn [(acc HeaderAcc) (ch Str)] -> HeaderAcc (headerCharStep acc ch)) init chars)) (rem res.curToken) (toks res.tokens)] (if (and (not (stringEmpty? rem)) (< (listLength toks) maxTokens)) (listAppend toks (list rem)) toks))

(schema ParamCountAcc (:f depth I64) (:f inBracket Bool) (:f inItem Bool) (:f count I64) (:f stopped Bool))

fn paramStepOutside acc: ParamCountAcc ch: Str -> ParamCountAcc
  (if (= ch "[") (ParamCountAcc :depth 1 :inBracket true :inItem false :count 0 :stopped false) acc)

fn paramStepCloseBracket acc: ParamCountAcc -> ParamCountAcc
  (let [(depth acc.depth) (cnt acc.count)] (if (<= depth 1) (ParamCountAcc :depth 0 :inBracket false :inItem false :count cnt :stopped true) (with acc :depth (- depth 1) :inBracket true :count cnt :stopped false)))

fn paramStepParen acc: ParamCountAcc ch: Str -> ParamCountAcc
  (let [(depth acc.depth) (cnt acc.count)] (if (= ch "(") (let [(nextCnt (if (= depth 1) (+ cnt 1) cnt))] (ParamCountAcc :depth (+ depth 1) :inBracket true :inItem false :count nextCnt :stopped false)) (let [(nextD (if (> depth 1) (- depth 1) depth))] (ParamCountAcc :depth nextD :inBracket true :inItem false :count cnt :stopped false))))

fn paramStepItem acc: ParamCountAcc ch: Str -> ParamCountAcc
  (let [(depth acc.depth) (inItem acc.inItem) (cnt acc.count)] (if (isSpaceChar ch) (ParamCountAcc :depth depth :inBracket true :inItem false :count cnt :stopped false) (if inItem acc (ParamCountAcc :depth depth :inBracket true :inItem true :count (+ cnt 1) :stopped false))))

fn paramStepInside acc: ParamCountAcc ch: Str -> ParamCountAcc
  (let [(depth acc.depth)] (cond ((= ch "[") (with acc :depth (+ depth 1) :inBracket true :stopped false)) ((= ch "]") (paramStepCloseBracket acc)) ((or (= ch "(") (= ch ")")) (paramStepParen acc ch)) ((= depth 1) (paramStepItem acc ch)) (else acc)))

fn paramCountStep acc: ParamCountAcc ch: Str -> ParamCountAcc
  (cond (acc.stopped acc) ((not acc.inBracket) (paramStepOutside acc ch)) (else (paramStepInside acc ch)))

fn countParamsInForm raw: Str -> (Option I64)
  (let [(chars (stringChars raw)) (init (ParamCountAcc :depth 0 :inBracket false :inItem false :count 0 :stopped false)) (res (fold (fn [(acc ParamCountAcc) (ch Str)] -> ParamCountAcc (paramCountStep acc ch)) init chars))] (if res.stopped (some res.count) (none)))

fn normalizeKw val: Str -> Str
  (if (stringStartsWith? val ":") (optionOr (stringSlice val 1 (stringLength val)) "") val)

fn paramCountMatches? queryPc: (Option I64) actualPc: (Option I64) -> Bool
  (mt queryPc ((none) true) ((some target) (mt actualPc ((none) false) ((some actual) (= target actual)))))

fn formMatchesQuery? node: ASTMatchNode pCount: (Option I64) query: ASTQuery -> Bool
  (let [(qFt (normalizeKw query.formType)) (nFt node.formType) (ftOk (or (= qFt "*") (= qFt nFt))) (symOk (mt query.symbolId ((none) true) ((some s) (= (normalizeKw s) node.symbolId)))) (pcOk (paramCountMatches? query.paramCount pCount)) (predOk (mt query.predicateToken ((none) true) ((some tok) (stringContains? node.rawForm tok))))] (and ftOk (and symOk (and pcOk predOk))))

fn parseMatchFromSpan span: RawSpan content: Str -> MatchParsed
  (let [(startC span.startIdx) (endC span.endIdx) (raw (optionOr (stringSlice content startC endC) "")) (toks (extractHeaderTokens raw 5)) (rawT0 (optionOr (listGet toks 0) "")) (t0 (normalizeKw rawT0)) (t1 (optionOr (listGet toks 1) "")) (t2 (optionOr (listGet toks 2) "")) (isEffectful (or (and (= t0 "df") (= t1 "!")) (and (= t0 "fn") (= t1 "!")))) (symId (if isEffectful t2 t1)) (pCnt (if (or (= t0 "fn") (or (= t0 "df") (or (= t0 "dfe") (= t0 "enum")))) (countParamsInForm raw) (none))) (node (ASTMatchNode :formType t0 :symbolId symId :startChar startC :endChar endC :rawForm raw :lineNumber span.lineNum))] (MatchParsed :node node :pCnt pCnt))

fn matchAstForm buffer: v/VFSBuffer query: ASTQuery -> (List ASTMatchNode)
  (let [(content buffer.content) (spans (scanTopLevelSpans content))] (fold (fn [(acc (List ASTMatchNode)) (span RawSpan)] -> (List ASTMatchNode) (let [(parsed (parseMatchFromSpan span content)) (node parsed.node) (pCnt parsed.pCnt)] (if (formMatchesQuery? node pCnt query) (listAppend acc (list node)) acc))) (list) spans))
