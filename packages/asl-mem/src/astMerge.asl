(module aslMem/astMerge :x [ASTCollisionRecord HomoiconicForm AstMergeOutcome AstMergeResult cleanFormId extractFormKind extractFormId parseHomoiconicForms findAstForm resolveHomoiconicForm formatAstCollision universalAst3wayMerge mergeSexpLists])

(schema ASTCollisionRecord (:f symbolId Str) (:f baseForm Str) (:f branchA Str) (:f branchB Str) (:f collisionType Str))

(schema HomoiconicForm (:f symbolId Str) (:f kind Str) (:f rawForm Str) (:f hash Str))

(schema AstMergeOutcome (:f text Str) (:f collision (Option ASTCollisionRecord)))

(schema AstMergeResult (:f mergedContent Str) (:f conflicts (List Str)) (:f collisions (List ASTCollisionRecord)) (:f clean Bool) (:f mergedFormsCount I64))

fn formatAstCollision c: ASTCollisionRecord -> Str
  (str "(:collision\n" "  :symbol \"" c.symbolId "\"\n" "  :type \"" c.collisionType "\"\n" "  :branchA \n" c.branchA "\n" "  :branchB \n" c.branchB "\n" "  :base \n" c.baseForm ")")

fn cleanFormId rawToken: Str -> Str
  (let [(t1 (stringReplace rawToken "(" "")) (t2 (stringReplace t1 ")" "")) (t3 (stringReplace t2 "[" "")) (t4 (stringReplace t3 "]" "")) (t5 (stringReplace t4 "\"" "")) (t6 (stringReplace t5 ":" ""))] (stringTrim t6))

fn extractFormKind firstLine: Str -> Str
  (let [(trimmed (stringTrim firstLine))] (if (or (stringStartsWith? trimmed "(fn ") (stringStartsWith? trimmed "fn ")) "fn" (if (or (stringStartsWith? trimmed "(df ") (stringStartsWith? trimmed "df ")) "fn" (if (or (stringStartsWith? trimmed "(schema ") (stringStartsWith? trimmed "(schema ")) "schema" (if (stringStartsWith? trimmed "(module ") "module" (if (stringStartsWith? trimmed "(:task ") "task" (if (stringStartsWith? trimmed "(:msg ") "msg" (if (stringStartsWith? trimmed "(:adr ") "adr" "form"))))))))

fn extractFormId firstLine: Str -> Str
  (let [(trimmed (stringTrim firstLine)) (words (stringSplit trimmed " ")) (wCnt (listLength words))] (if (<= wCnt 1) (cleanFormId trimmed) (if (or (stringStartsWith? trimmed "(:task") (stringStartsWith? trimmed "(:msg") (stringStartsWith? trimmed "(:adr")) (let [(idOpt (fold (fn [(acc (Option Str)) (w Str)] -> (Option Str) (mt acc ((some found) (some found)) ((none) (if (or (stringContains? w "\"") (stringStartsWith? w "T") (stringStartsWith? w "ADR-")) (some (cleanFormId w)) (none))))) (none) words))] (optionOr idOpt (cleanFormId (optionOr (listGet words 1) "anonymous")))) (let [(w1 (optionOr (listGet words 1) ""))] (if (or (stringEmpty? w1) (stringStartsWith? w1 "[")) (cleanFormId (optionOr (listGet words 0) "form")) (cleanFormId w1))))))

(schema FormScanState (:f depth I64) (:f inStr Bool) (:f esc Bool))

(schema FormLineAcc (:f forms (List (List Str))) (:f cur (List Str)) (:f scan FormScanState))

fn updateFormScanState st: FormScanState line: Str -> FormScanState
  (let [(chars (stringChars line))] (fold (fn [(s FormScanState) (c Str)] -> FormScanState (if s.inStr (if s.esc (FormScanState :depth s.depth :inStr true :esc false) (if (= c "\\") (FormScanState :depth s.depth :inStr true :esc true) (if (= c "\"") (FormScanState :depth s.depth :inStr false :esc false) s))) (if (= c "\"") (FormScanState :depth s.depth :inStr true :esc false) (cond ((or (= c "(") (or (= c "[") (= c "{"))) (FormScanState :depth (+ s.depth 1) :inStr false :esc false)) ((or (= c ")") (or (= c "]") (= c "}"))) (let [(d (- s.depth 1))] (FormScanState :depth (if (< d 0) 0 d) :inStr false :esc false))) (else s))))) st chars))

fn parseHomoiconicForms content: Str -> (List HomoiconicForm)
  (if (stringEmpty? (stringTrim content)) (list) (let [(lines (stringSplit content "\n")) (init (FormLineAcc :forms (list) :cur (list) :scan (FormScanState :depth 0 :inStr false :esc false))) (finalAcc (fold (fn [(acc FormLineAcc) (rawLn Str)] -> FormLineAcc (let [(trimmed (stringTrim rawLn)) (curLines acc.cur) (curSt acc.scan) (curD curSt.depth)] (if (= curD 0) (if (stringEmpty? trimmed) acc (let [(nextSt (updateFormScanState curSt rawLn))] (if (and (<= nextSt.depth 0) (not nextSt.inStr)) (FormLineAcc :forms (listAppend acc.forms (list (list rawLn))) :cur (list) :scan (FormScanState :depth 0 :inStr false :esc false)) (FormLineAcc :forms acc.forms :cur (list rawLn) :scan nextSt)))) (let [(nextCur (listAppend curLines (list rawLn))) (nextSt (updateFormScanState curSt rawLn))] (if (and (<= nextSt.depth 0) (not nextSt.inStr)) (FormLineAcc :forms (listAppend acc.forms (list nextCur)) :cur (list) :scan (FormScanState :depth 0 :inStr false :esc false)) (FormLineAcc :forms acc.forms :cur nextCur :scan nextSt)))))) init lines)) (allForms (if (listEmpty? finalAcc.cur) finalAcc.forms (listAppend finalAcc.forms (list finalAcc.cur))))] (fold (fn [(acc (List HomoiconicForm)) (formLines (List Str))] -> (List HomoiconicForm) (let [(raw (stringTrim (stringJoin formLines "\n"))) (fLine (optionOr (listGet formLines 0) "")) (symId (extractFormId fLine)) (kind (extractFormKind fLine))] (if (stringEmpty? (stringTrim raw)) acc (listAppend acc (list (HomoiconicForm :symbolId symId :kind kind :rawForm raw :hash (str (stringLength raw) ":" symId))))))) (list) allForms)))

fn findAstForm forms: (List HomoiconicForm) targetId: Str -> (Option HomoiconicForm)
  (fold (fn [(acc (Option HomoiconicForm)) (f HomoiconicForm)] -> (Option HomoiconicForm) (mt acc ((some found) (some found)) ((none) (if (= f.symbolId targetId) (some f) (none))))) (none) forms)

fn resolveAOnly sym: Str aRaw: Str baseOpt: (Option HomoiconicForm) -> AstMergeOutcome
  (mt baseOpt ((none) (AstMergeOutcome :text aRaw :collision (none))) ((some baseF) (let [(baseRaw baseF.rawForm)] (if (= aRaw baseRaw) (AstMergeOutcome :text "" :collision (none)) (let [(col (ASTCollisionRecord :symbolId sym :baseForm baseRaw :branchA aRaw :branchB "(deleted in branch-b)" :collisionType "modify-vs-delete"))] (AstMergeOutcome :text (formatAstCollision col) :collision (some col)))))))

fn resolveBOnly sym: Str bRaw: Str baseOpt: (Option HomoiconicForm) -> AstMergeOutcome
  (mt baseOpt ((none) (AstMergeOutcome :text bRaw :collision (none))) ((some baseF) (let [(baseRaw baseF.rawForm)] (if (= bRaw baseRaw) (AstMergeOutcome :text "" :collision (none)) (let [(col (ASTCollisionRecord :symbolId sym :baseForm baseRaw :branchA "(deleted in branch-a)" :branchB bRaw :collisionType "delete-vs-modify"))] (AstMergeOutcome :text (formatAstCollision col) :collision (some col)))))))

fn resolveBothPresent sym: Str aRaw: Str bRaw: Str baseOpt: (Option HomoiconicForm) -> AstMergeOutcome
  (if (= aRaw bRaw) (AstMergeOutcome :text aRaw :collision (none)) (mt baseOpt ((none) (let [(col (ASTCollisionRecord :symbolId sym :baseForm "(none)" :branchA aRaw :branchB bRaw :collisionType "divergent-addition"))] (AstMergeOutcome :text (formatAstCollision col) :collision (some col)))) ((some baseF) (let [(baseRaw baseF.rawForm)] (if (= aRaw baseRaw) (AstMergeOutcome :text bRaw :collision (none)) (if (= bRaw baseRaw) (AstMergeOutcome :text aRaw :collision (none)) (let [(col (ASTCollisionRecord :symbolId sym :baseForm baseRaw :branchA aRaw :branchB bRaw :collisionType "divergent-modification"))] (AstMergeOutcome :text (formatAstCollision col) :collision (some col)))))))))

fn resolveHomoiconicForm sym: Str baseOpt: (Option HomoiconicForm) branchAOpt: (Option HomoiconicForm) branchBOpt: (Option HomoiconicForm) -> AstMergeOutcome
  (mt branchAOpt ((none) (mt branchBOpt ((none) (AstMergeOutcome :text "" :collision (none))) ((some fb) (resolveBOnly sym fb.rawForm baseOpt)))) ((some fa) (mt branchBOpt ((none) (resolveAOnly sym fa.rawForm baseOpt)) ((some fb) (resolveBothPresent sym fa.rawForm fb.rawForm baseOpt)))))

(schema AstMergeAccumulator (:f merged (List Str)) (:f conflicts (List Str)) (:f collisions (List ASTCollisionRecord)) (:f seen (List Str)))

fn universalAst3wayMerge baseSrc: Str branchASrc: Str branchBSrc: Str -> AstMergeResult
  (let [(baseForms (parseHomoiconicForms baseSrc)) (aForms (parseHomoiconicForms branchASrc)) (bForms (parseHomoiconicForms branchBSrc)) (init (AstMergeAccumulator :merged (list) :conflicts (list) :collisions (list) :seen (list))) (afterA (fold (fn [(acc AstMergeAccumulator) (fa HomoiconicForm)] -> AstMergeAccumulator (let [(sym fa.symbolId) (baseOpt (findAstForm baseForms sym)) (bOpt (findAstForm bForms sym)) (outcome (resolveHomoiconicForm sym baseOpt (some fa) bOpt)) (txt outcome.text) (curM acc.merged) (curC acc.conflicts) (curCol acc.collisions) (curSeen (listAppend acc.seen (list sym))) (nextM (if (stringEmpty? txt) curM (listAppend curM (list txt)))) (nextC (mt outcome.collision ((none) curC) ((some _) (listAppend curC (list sym))))) (nextCol (mt outcome.collision ((none) curCol) ((some c) (listAppend curCol (list c)))))] (AstMergeAccumulator :merged nextM :conflicts nextC :collisions nextCol :seen curSeen))) init aForms)) (finalAcc (fold (fn [(acc AstMergeAccumulator) (fb HomoiconicForm)] -> AstMergeAccumulator (let [(sym fb.symbolId) (seen acc.seen)] (if (listContains? seen sym) acc (let [(baseOpt (findAstForm baseForms sym)) (outcome (resolveHomoiconicForm sym baseOpt (none) (some fb))) (txt outcome.text) (curM acc.merged) (curC acc.conflicts) (curCol acc.collisions) (curSeen (listAppend seen (list sym))) (nextM (if (stringEmpty? txt) curM (listAppend curM (list txt)))) (nextC (mt outcome.collision ((none) curC) ((some _) (listAppend curC (list sym))))) (nextCol (mt outcome.collision ((none) curCol) ((some c) (listAppend curCol (list c)))))] (AstMergeAccumulator :merged nextM :conflicts nextC :collisions nextCol :seen curSeen))))) afterA bForms)) (mergedList finalAcc.merged) (conflictsList finalAcc.conflicts) (collisionsList finalAcc.collisions) (mergedText (stringJoin mergedList "\n\n"))] (AstMergeResult :mergedContent mergedText :conflicts conflictsList :collisions collisionsList :clean (= (listLength conflictsList) 0) :mergedFormsCount (listLength mergedList)))

fn mergeSexpLists base: (List Str) a: (List Str) b: (List Str) -> (List Str)
  (let [(added-a (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (if (listContains? base item) acc (if (listContains? acc item) acc (listAppend acc (list item))))) (list) a)) (added-b (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (if (listContains? base item) acc (if (or (listContains? added-a item) (listContains? acc item)) acc (listAppend acc (list item))))) (list) b)) (retainedBase (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (if (and (listContains? a item) (listContains? b item)) (listAppend acc (list item)) acc)) (list) base))] (listAppend retainedBase (listAppend added-a added-b)))
