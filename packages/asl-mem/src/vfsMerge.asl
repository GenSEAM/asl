(module aslMem/vfsMerge :x [AstMergeResult CausalMergeResult ast3wayMerge mergeDisjointForms formatAstConflict mergeCausalBranchIntent] :i [(astMerge :a am)])

(schema AstMergeResult (:f mergedContent Str) (:f conflicts (List Str)) (:f clean Bool) (:f mergedFormsCount I64))

(schema AstForm (:f symbolId Str) (:f rawForm Str))

fn formatAstConflict symbolId: Str stagedForm: Str diskForm: Str -> Str
  (str "<<<<<<< STAGED (" symbolId ")\n" stagedForm "\n" "=======\n" diskForm "\n" ">>>>>>> DISK (" symbolId ")")

(schema ParseAccumulator (:f chunks (List (List Str))) (:f depth I64))

fn countParens line: Str -> I64
  (let [(opens (- (listLength (stringSplit line "(")) 1)) (closes (- (listLength (stringSplit line ")")) 1))] (- opens closes))

fn parseLinesToForms lines: (List Str) -> (List AstForm)
  (let [(collected (fold (fn [(acc ParseAccumulator) (line Str)] -> ParseAccumulator (let [(isNewForm (and (stringStartsWith? line "(") (<= acc.depth 0))) (delta (countParens line)) (newDepth (if isNewForm delta (+ acc.depth delta))) (chunks acc.chunks) (n (listLength chunks))] (if isNewForm (ParseAccumulator :chunks (listAppend chunks (list (list line))) :depth newDepth) (if (= n 0) (if (stringEmpty? (stringTrim line)) acc (ParseAccumulator :chunks (listAppend chunks (list (list line))) :depth newDepth)) (let [(lastIdx (- n 1)) (prevChunk (optionOr (listGet chunks lastIdx) (list))) (initAcc (optionOr (listSlice chunks 0 lastIdx) (list))) (updatedChunk (listAppend prevChunk (list line)))] (ParseAccumulator :chunks (listAppend initAcc (list updatedChunk)) :depth newDepth)))))) (ParseAccumulator :chunks (list) :depth 0) lines))] (fold (fn [(acc (List AstForm)) (formLines (List Str))] -> (List AstForm) (let [(raw (stringJoin formLines "
")) (fLine (optionOr (listGet formLines 0) "")) (symId (am/extractFormId fLine))] (if (stringEmpty? (stringTrim raw)) acc (listAppend acc (list (AstForm :symbolId symId :rawForm raw)))))) (list) collected.chunks))

fn parseAstForms content: Str -> (List AstForm)
  (if (stringEmpty? (stringTrim content)) (list) (parseLinesToForms (stringSplit content "\n")))

fn findForm forms: (List AstForm) targetId: Str -> (Option AstForm)
  (fold (fn [(acc (Option AstForm)) (f AstForm)] -> (Option AstForm) (mt acc ((some found) (some found)) ((none) (if (= f.symbolId targetId) (some f) (none))))) (none) forms)

(schema FormMergeOutcome (:f text Str) (:f conflictId (Option Str)))

fn resolve3wayForm sym: Str sRaw: Str bOpt: (Option AstForm) dOpt: (Option AstForm) -> FormMergeOutcome
  (mt bOpt ((none) (mt dOpt ((none) (FormMergeOutcome :text sRaw :conflictId (none))) ((some df) (let [(dRaw df.rawForm)] (if (= sRaw dRaw) (FormMergeOutcome :text sRaw :conflictId (none)) (FormMergeOutcome :text (formatAstConflict sym sRaw dRaw) :conflictId (some sym))))))) ((some bf) (let [(bRaw bf.rawForm)] (mt dOpt ((none) (if (= sRaw bRaw) (FormMergeOutcome :text "" :conflictId (none)) (FormMergeOutcome :text (formatAstConflict sym sRaw "(deleted on disk)") :conflictId (some sym)))) ((some df) (let [(dRaw df.rawForm)] (if (= sRaw dRaw) (FormMergeOutcome :text sRaw :conflictId (none)) (if (= sRaw bRaw) (FormMergeOutcome :text dRaw :conflictId (none)) (if (= dRaw bRaw) (FormMergeOutcome :text sRaw :conflictId (none)) (FormMergeOutcome :text (formatAstConflict sym sRaw dRaw) :conflictId (some sym)))))))))))

(schema MergeAccumulator (:f merged (List Str)) (:f conflicts (List Str)) (:f seen (List Str)))

fn mergeDisjointForms baseContent: Str stagedContent: Str diskContent: Str -> AstMergeResult
  (let [(bForms (parseAstForms baseContent)) (sForms (parseAstForms stagedContent)) (dForms (parseAstForms diskContent)) (init (MergeAccumulator :merged (list) :conflicts (list) :seen (list))) (afterS (fold (fn [(acc MergeAccumulator) (sf AstForm)] -> MergeAccumulator (let [(sym sf.symbolId) (sRaw sf.rawForm) (bOpt (findForm bForms sym)) (dOpt (findForm dForms sym)) (outcome (resolve3wayForm sym sRaw bOpt dOpt)) (resText outcome.text) (curM acc.merged) (curC acc.conflicts) (curSeen (listAppend acc.seen (list sym))) (nextM (if (stringEmpty? resText) curM (listAppend curM (list resText)))) (nextC (mt outcome.conflictId ((none) curC) ((some cid) (listAppend curC (list cid)))))] (MergeAccumulator :merged nextM :conflicts nextC :seen curSeen))) init sForms)) (finalAcc (fold (fn [(acc MergeAccumulator) (df AstForm)] -> MergeAccumulator (let [(sym df.symbolId) (seen acc.seen)] (if (listContains? seen sym) acc (let [(bOpt (findForm bForms sym)) (dRaw df.rawForm) (curM acc.merged) (curC acc.conflicts) (curSeen (listAppend seen (list sym)))] (mt bOpt ((none) (MergeAccumulator :merged (listAppend curM (list dRaw)) :conflicts curC :seen curSeen)) ((some bf) (let [(bRaw bf.rawForm)] (if (= dRaw bRaw) (MergeAccumulator :merged curM :conflicts curC :seen curSeen) (let [(cBlock (formatAstConflict sym "(deleted in staged)" dRaw))] (MergeAccumulator :merged (listAppend curM (list cBlock)) :conflicts (listAppend curC (list sym)) :seen curSeen)))))))))) afterS dForms)) (mergedList finalAcc.merged) (conflictsList finalAcc.conflicts) (mergedText (stringJoin mergedList "\n\n"))] (AstMergeResult :mergedContent mergedText :conflicts conflictsList :clean (= (listLength conflictsList) 0) :mergedFormsCount (listLength mergedList)))

fn ast3wayMerge baseContent: Str stagedContent: Str diskContent: Str -> AstMergeResult
  (mergeDisjointForms baseContent stagedContent diskContent)

(schema CausalMergeResult (:f mergedResult AstMergeResult) (:f causalId Str) (:f intentConflict? Bool))

fn mergeCausalBranchIntent baseContent: Str stagedContent: Str diskContent: Str causalId: Str -> CausalMergeResult
  (let [(m (ast3wayMerge baseContent stagedContent diskContent))] (CausalMergeResult :mergedResult m :causalId causalId :intentConflict? (not m.clean)))
