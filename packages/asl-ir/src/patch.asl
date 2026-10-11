(module asl-ir/patch :x [AstPatchOp patchOpReplace patchOpSplice patchOpRename patchOpRetype AstPatch makeAstPatch PatchDiag makePatchDiag PatchResult makePatchResult makePatchOpReplace makePatchOpSplice makePatchOpRename makePatchOpRetype makeReplacePatch parsePatch applyPatch invertPatch verifyPatch renderPatch computeAstDigest] :i [(asl-parser/ast :a ast) (asl-parser/reader :a rd) (asl-parser/lexer :a lx)])

(enum AstPatchOp (:c patchOpReplace [(target Str) (anchor Str) (oldNode Str) (newNode Str)] "Subtree substitution addressed strictly by module, symbol, and anchor") (:c patchOpSplice [(target Str) (anchor Str) (index Int64) (deletedNodes (List Str)) (insertNodes (List Str))] "Child sequence deletion of the named nodes and insertion at index") (:c patchOpRename [(target Str) (oldName Str) (newName Str)] "Identifier renaming across symbol scope") (:c patchOpRetype [(target Str) (anchor Str) (oldType Str) (newType Str)] "Type annotation modification for parameter, field, or return type"))

(schema AstPatch (:f id Str) (:f targetModule Str) (:f preRoot (Option Str)) (:f postRoot (Option Str)) (:f ops (List AstPatchOp)))

(schema PatchDiag (:f code Str) (:f target Str) (:f anchor Str) (:f message Str))

(schema PatchResult (:f success Bool) (:f patchedSource Str) (:f inversePatch (Option AstPatch)) (:f diagnostics (List PatchDiag)))

fn makePatchOpReplace target: Str anchor: Str oldNode: Str newNode: Str -> AstPatchOp
  (patchOpReplace target anchor oldNode newNode)

fn makePatchOpSplice target: Str anchor: Str index: Int64 deletedNodes: (List Str) insertNodes: (List Str) -> AstPatchOp
  (patchOpSplice target anchor index deletedNodes insertNodes)

fn makePatchOpRename target: Str oldName: Str newName: Str -> AstPatchOp
  (patchOpRename target oldName newName)

fn makePatchOpRetype target: Str anchor: Str oldType: Str newType: Str -> AstPatchOp
  (patchOpRetype target anchor oldType newType)

fn makeAstPatch id: Str targetModule: Str preRoot: (Option Str) postRoot: (Option Str) ops: (List AstPatchOp) -> AstPatch
  (AstPatch :id id :targetModule targetModule :preRoot preRoot :postRoot postRoot :ops ops)

fn makePatchDiag code: Str target: Str anchor: Str message: Str -> PatchDiag
  (PatchDiag :code code :target target :anchor anchor :message message)

fn makePatchResult success: Bool patchedSource: Str inversePatch: (Option AstPatch) diagnostics: (List PatchDiag) -> PatchResult
  (PatchResult :success success :patchedSource patchedSource :inversePatch inversePatch :diagnostics diagnostics)

fn makeReplacePatch id: Str targetModule: Str targetSymbol: Str anchor: Str oldNode: Str newNode: Str -> AstPatch
  (makeAstPatch id targetModule (none) (none) (list (makePatchOpReplace targetSymbol anchor oldNode newNode)))

fn extractSymbolName target: Str -> Str
  (if (stringContains? target ":") (let [(parts (stringSplit target ":")) (len (listLength parts))] (if (> len 0) (optionOr (listGet parts (- len 1)) target) target)) target)

fn unescapeChar st: (Pair Str Bool) c: Str -> (Pair Str Bool)
  (if (pairSecond st) (pair (str (pairFirst st) (cond ((= c "n") "\n") ((= c "t") "\t") (else c))) false) (if (= c "\\") (pair (pairFirst st) true) (pair (str (pairFirst st) c) false)))

fn unquoteText s: Str -> Str
  (let [(len (stringLength s))] (if (and (>= len 2) (stringStartsWith? s "\"") (stringEndsWith? s "\"")) (pairFirst (fold unescapeChar (pair "" false) (stringChars (optionOr (stringSlice s 1 (- len 1)) "")))) s))

fn quoteText s: Str -> Str
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn charVal c: Str -> Int64
  (let [(chars " 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ()[]{}\":;,.+-*/=_<>&|!?@#$%'`~^\n\t\r\\")] (mt (stringIndexOf chars c) ((some idx) (+ idx 32)) ((none) 42)))

fn computeAstDigest src: Str -> Str
  (let [(len (stringLength src)) (h (fold (fn [(acc Int64) (c Str)] -> Int64 (let [(code (charVal c))] (mod (+ (* acc 31) code) 1000000007))) 17 (stringChars src)))] (str "d" (stringFromInt64 len) "x" (stringFromInt64 h)))

fn parseSexprSnippet s: Str -> (Result rd/SExpr Str)
  (let [(toks (lx/tokenize s)) (res (ast/readForms toks))] (mt res ((ok forms) (mt (listHead forms) ((some pf) (ok pf.expr)) ((none) (ok (rd/makeAtom s))))) ((err e) (err e.msg))))

fn topFormHead form: rd/SExpr -> Str
  (mt form ((rd/sexprList items) (mt (listHead items) ((some h) (rd/sexprHead h)) ((none) ""))) (_ ""))

fn topFormSymbol form: rd/SExpr -> Str
  (mt form ((rd/sexprList items) (let [(headText (topFormHead form))] (if (or (= headText "df") (= headText "defun") (= headText "def") (= headText "dfs") (= headText "defschema") (= headText "schema") (= headText "dfe") (= headText "defenum") (= headText "enum") (= headText "module")) (let [(secondOpt (listHead (optionOr (listTail items) (list))))] (mt secondOpt ((some s) (rd/sexprHead s)) ((none) ""))) ""))) (_ ""))

(schema ReplaceState (:f expr rd/SExpr) (:f replaced Bool))

fn replaceInSexpr expr: rd/SExpr oldStr: Str newExpr: rd/SExpr -> ReplaceState
  (let [(rendered (rd/renderSexpr expr))] (if (= rendered oldStr) (ReplaceState :expr newExpr :replaced true) (mt expr ((rd/sexprAtom v) (if (= v oldStr) (ReplaceState :expr newExpr :replaced true) (ReplaceState :expr expr :replaced false))) ((rd/sexprList items) (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Bool)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Bool) (if (pairSecond acc) (pair (cons it (pairFirst acc)) true) (let [(sub (replaceInSexpr it oldStr newExpr))] (if sub.replaced (pair (cons sub.expr (pairFirst acc)) true) (pair (cons it (pairFirst acc)) false))))) (pair (list) false) items))] (if (pairSecond step) (ReplaceState :expr (rd/makeList (listReverse (pairFirst step))) :replaced true) (ReplaceState :expr expr :replaced false)))) ((rd/sexprVect items) (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Bool)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Bool) (if (pairSecond acc) (pair (cons it (pairFirst acc)) true) (let [(sub (replaceInSexpr it oldStr newExpr))] (if sub.replaced (pair (cons sub.expr (pairFirst acc)) true) (pair (cons it (pairFirst acc)) false))))) (pair (list) false) items))] (if (pairSecond step) (ReplaceState :expr (rd/makeVect (listReverse (pairFirst step))) :replaced true) (ReplaceState :expr expr :replaced false)))))))

fn renameInSexpr expr: rd/SExpr oldName: Str newName: Str -> (Pair rd/SExpr Int64)
  (mt expr ((rd/sexprAtom v) (if (= v oldName) (pair (rd/makeAtom newName) 1) (pair expr 0))) ((rd/sexprList items) (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Int64)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Int64) (let [(sub (renameInSexpr it oldName newName))] (pair (cons (pairFirst sub) (pairFirst acc)) (+ (pairSecond acc) (pairSecond sub))))) (pair (list) 0) items))] (pair (rd/makeList (listReverse (pairFirst step))) (pairSecond step)))) ((rd/sexprVect items) (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Int64)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Int64) (let [(sub (renameInSexpr it oldName newName))] (pair (cons (pairFirst sub) (pairFirst acc)) (+ (pairSecond acc) (pairSecond sub))))) (pair (list) 0) items))] (pair (rd/makeVect (listReverse (pairFirst step))) (pairSecond step)))))

fn takeItems n: Int64 xs: (List rd/SExpr) -> (List rd/SExpr)
  (if (<= n 0) (list) (mt (listHead xs) ((some h) (cons h (takeItems (- n 1) (optionOr (listTail xs) (list))))) ((none) (list))))

fn dropItems n: Int64 xs: (List rd/SExpr) -> (List rd/SExpr)
  (if (<= n 0) xs (mt (listTail xs) ((some tl) (dropItems (- n 1) tl)) ((none) (list))))

fn findRetTypeFrom items: (List rd/SExpr) i: Int64 -> Int64
  (mt (listHead items)
    ((none) -1)
    ((some it) (if (= (rd/sexprHead it) "->") (+ i 1) (findRetTypeFrom (optionOr (listTail items) (list)) (+ i 1)))))

fn findRetTypePos items: (List rd/SExpr) -> Int64
  (findRetTypeFrom items 0)

fn applyReplaceOp form: rd/SExpr anchor: Str oldNode: Str newNode: Str -> (Result rd/SExpr PatchDiag)
  (let [(parsedNew (parseSexprSnippet newNode))] (mt parsedNew ((err e) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" anchor (str "Replacement newNode has invalid syntax: " e)))) ((ok newExpr) (cond ((= anchor "retType") (mt form ((rd/sexprList items) (let [(pos (findRetTypePos items))] (if (< pos 0) (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Return type anchor '->' not found in symbol")) (let [(curr (optionOr (listGet items pos) (rd/makeAtom "")))] (if (!= (rd/renderSexpr curr) oldNode) (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" anchor (str "Expected oldNode '" oldNode "' but found '" (rd/renderSexpr curr) "'"))) (let [(before (takeItems pos items)) (after (dropItems (+ pos 1) items)) (updated (listAppend (listAppend before (list newExpr)) after))] (ok (rd/makeList updated)))))))) (_ (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Target form is not a list"))))) ((or (= anchor "body") (= anchor "") (= anchor "root")) (let [(res (replaceInSexpr form oldNode newExpr))] (if res.replaced (ok res.expr) (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" anchor (str "Subtree matching oldNode '" oldNode "' not found in target")))))) (else (let [(res (replaceInSexpr form oldNode newExpr))] (if res.replaced (ok res.expr) (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor (str "Anchor '" anchor "' not found in target symbol"))))))))))

fn parseNodes nodes: (List Str) -> (Result (List rd/SExpr) Str)
  (mt (fold (fn [(acc (Result (List rd/SExpr) Str)) (nodeStr Str)] -> (Result (List rd/SExpr) Str) (mt acc ((err e) (err e)) ((ok listAcc) (mt (parseSexprSnippet nodeStr) ((err pe) (err pe)) ((ok parsed) (ok (cons parsed listAcc))))))) (ok (list)) nodes)
    ((ok xs) (ok (listReverse xs)))
    ((err e) (err e)))

fn renderNodes nodes: (List rd/SExpr) -> (List Str)
  (map (fn [(n rd/SExpr)] -> Str (rd/renderSexpr n)) nodes)

fn applySpliceOp form: rd/SExpr anchor: Str index: Int64 deletedNodes: (List Str) insertNodes: (List Str) -> (Result rd/SExpr PatchDiag)
  (mt form ((rd/sexprList items) (let [(pos (findRetTypePos items))] (if (< pos 0) (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Target form does not support splicing")) (let [(bodyStart (+ pos 1)) (bodyItems (dropItems bodyStart items)) (bodyLen (listLength bodyItems)) (deleteCount (listLength deletedNodes))] (if (or (< index 0) (> (+ index deleteCount) bodyLen)) (err (makePatchDiag "ERR_PATCH_INDEX_OUT_OF_BOUNDS" "" anchor (str "Splice of " (stringFromInt64 deleteCount) " at index " (stringFromInt64 index) " out of bounds for body length " (stringFromInt64 bodyLen)))) (mt (parseNodes deletedNodes) ((err e) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" anchor (str "Deleted node has invalid syntax: " e)))) ((ok delExprs) (let [(found (renderNodes (takeItems deleteCount (dropItems index bodyItems)))) (wanted (renderNodes delExprs))] (if (!= found wanted) (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" anchor (str "Expected deleted nodes [" (stringJoin wanted " ") "] but found [" (stringJoin found " ") "]"))) (mt (parseNodes insertNodes) ((err e) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" anchor (str "Inserted node has invalid syntax: " e)))) ((ok insExprs) (let [(beforeDel (takeItems index bodyItems)) (afterDel (dropItems (+ index deleteCount) bodyItems)) (newBody (listAppend (listAppend beforeDel insExprs) afterDel)) (header (takeItems bodyStart items)) (newForm (listAppend header newBody))] (ok (rd/makeList newForm)))))))))))))) (_ (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Target form is not a list"))))

fn applyRenameOp form: rd/SExpr oldName: Str newName: Str -> (Result rd/SExpr PatchDiag)
  (let [(res (renameInSexpr form oldName newName))] (if (<= (pairSecond res) 0) (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" "" (str "Identifier '" oldName "' not found in target symbol"))) (ok (pairFirst res))))

fn applyRetypeOp form: rd/SExpr anchor: Str oldType: Str newType: Str -> (Result rd/SExpr PatchDiag)
  (if (= anchor "retType") (applyReplaceOp form "retType" oldType newType) (if (stringStartsWith? anchor "param:") (let [(pName (stringReplace anchor "param:" "")) (oldPat (str "(" pName " " oldType ")")) (newPat (str "(" pName " " newType ")"))] (applyReplaceOp form "params" oldPat newPat)) (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor (str "Unsupported retype anchor: " anchor)))))

fn applyOpToForm form: rd/SExpr op: AstPatchOp -> (Result rd/SExpr PatchDiag)
  (mt op ((patchOpReplace _ anchor oldNode newNode) (applyReplaceOp form anchor oldNode newNode)) ((patchOpSplice _ anchor index deletedNodes insertNodes) (applySpliceOp form anchor index deletedNodes insertNodes)) ((patchOpRename _ oldName newName) (applyRenameOp form oldName newName)) ((patchOpRetype _ anchor oldType newType) (applyRetypeOp form anchor oldType newType)))

fn getOpTarget op: AstPatchOp -> Str
  (mt op ((patchOpReplace t _ _ _) t) ((patchOpSplice t _ _ _ _) t) ((patchOpRename t _ _) t) ((patchOpRetype t _ _ _) t))

fn invertOp op: AstPatchOp -> AstPatchOp
  (mt op ((patchOpReplace t a oldNode newNode) (patchOpReplace t a newNode oldNode)) ((patchOpSplice t a index deletedNodes insertNodes) (patchOpSplice t a index insertNodes deletedNodes)) ((patchOpRename t oldName newName) (patchOpRename t newName oldName)) ((patchOpRetype t a oldType newType) (patchOpRetype t a newType oldType)))

fn invertPatch patch: AstPatch -> AstPatch
  (let [(invOps (map (fn [(op AstPatchOp)] -> AstPatchOp (invertOp op)) (listReverse patch.ops)))] (makeAstPatch (str patch.id ":inv") patch.targetModule patch.postRoot patch.preRoot invOps))

fn validatePatchedSource source: Str -> (Option Str)
  (let [(toks (lx/tokenize source))] (let [(readRes (ast/readForms toks))] (mt readRes ((err e) (some (str "Delimiter balance failure: " e.msg))) ((ok posForms) (let [(parseRes (ast/parse source))] (mt parseRes ((err pe) (some (str "AST parse failure: " pe.msg))) ((ok topForms) (if (listEmpty? topForms) (some "AST parse produced zero top-level declarations") (none)))))))))

fn renderAllForms forms: (List rd/SExpr) -> Str
  (stringJoin (map (fn [(f rd/SExpr)] -> Str (rd/renderSexpr f)) forms) "\n\n")

fn applyPatch patch: AstPatch sourceCode: Str -> PatchResult
  (if (listEmpty? patch.ops) (makePatchResult false sourceCode (none) (list (makePatchDiag "ERR_PATCH_EMPTY_OPS" "" "" "Patch contains no operations"))) (let [(preCheck (mt patch.preRoot ((some expected) (let [(actual (computeAstDigest sourceCode))] (if (!= actual expected) (some (makePatchDiag "ERR_CONCURRENCY_CONFLICT" patch.targetModule "" (str "Pre-condition Merkle root conflict: expected " expected " but got " actual))) (none)))) ((none) (none))))] (mt preCheck ((some diag) (makePatchResult false sourceCode (none) (list diag))) ((none) (let [(toks (lx/tokenize sourceCode)) (readRes (ast/readForms toks))] (mt readRes ((err e) (makePatchResult false sourceCode (none) (list (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Source file parse error: " e.msg))))) ((ok posForms) (let [(currentForms (map (fn [(pf ast/PosForm)] -> rd/SExpr pf.expr) posForms)) (applyStep (fold (fn [(acc (Result (List rd/SExpr) PatchDiag)) (op AstPatchOp)] -> (Result (List rd/SExpr) PatchDiag) (mt acc ((err d) (err d)) ((ok fList) (let [(targetSym (extractSymbolName (getOpTarget op))) (found (fold (fn [(subAcc (Pair (List rd/SExpr) (Pair Bool (Option PatchDiag)))) (f rd/SExpr)] -> (Pair (List rd/SExpr) (Pair Bool (Option PatchDiag))) (if (pairFirst (pairSecond subAcc)) (pair (listAppend (pairFirst subAcc) (list f)) (pairSecond subAcc)) (if (= (topFormSymbol f) targetSym) (mt (applyOpToForm f op) ((ok updated) (pair (listAppend (pairFirst subAcc) (list updated)) (pair true (none)))) ((err d) (pair (listAppend (pairFirst subAcc) (list f)) (pair true (some d))))) (pair (listAppend (pairFirst subAcc) (list f)) (pair false (none)))))) (pair (list) (pair false (none))) fList))] (if (not (pairFirst (pairSecond found))) (err (makePatchDiag "ERR_PATCH_SYMBOL_NOT_FOUND" targetSym "" (str "Target symbol '" targetSym "' not found in module"))) (mt (pairSecond (pairSecond found)) ((some diag) (err diag)) ((none) (ok (pairFirst found))))))))) (ok currentForms) patch.ops))] (mt applyStep ((err diag) (makePatchResult false sourceCode (none) (list diag))) ((ok newForms) (let [(candidateSource (renderAllForms newForms)) (valErr (validatePatchedSource candidateSource))] (mt valErr ((some errMsg) (makePatchResult false sourceCode (none) (list (makePatchDiag "ERR_PATCH_VALIDATION_FAILED" "" "" errMsg)))) ((none) (let [(postDigest (computeAstDigest candidateSource)) (preDigest (computeAstDigest sourceCode)) (invOps (map (fn [(op AstPatchOp)] -> AstPatchOp (invertOp op)) (listReverse patch.ops))) (invPatch (makeAstPatch (str patch.id ":inv") patch.targetModule (some postDigest) (some preDigest) invOps))] (makePatchResult true candidateSource (some invPatch) (list))))))))))))))))

fn verifyPatch patch: AstPatch sourceCode: Str -> (Result Unit (List PatchDiag))
  (let [(res (applyPatch patch sourceCode))] (if res.success (ok ()) (err res.diagnostics)))

fn findKvAtom items: (List rd/SExpr) key: Str -> Str
  (mt (listHead items) ((some it) (let [(rest (optionOr (listTail items) (list)))] (if (and (rd/isAtom? it) (= (rd/sexprHead it) key)) (mt (listHead rest) ((some valNode) (unquoteText (rd/sexprHead valNode))) ((none) "")) (findKvAtom rest key)))) ((none) ""))

fn findKvNode items: (List rd/SExpr) key: Str -> (Option rd/SExpr)
  (mt (listHead items) ((some it) (let [(rest (optionOr (listTail items) (list)))] (if (and (rd/isAtom? it) (= (rd/sexprHead it) key)) (listHead rest) (findKvNode rest key)))) ((none) (none)))

fn findKvStrings items: (List rd/SExpr) key: Str -> (List Str)
  (mt (findKvNode items key) ((some n) (mt n ((rd/sexprVect vItems) (map (fn [(it rd/SExpr)] -> Str (unquoteText (rd/sexprHead it))) vItems)) ((rd/sexprList lItems) (map (fn [(it rd/SExpr)] -> Str (unquoteText (rd/sexprHead it))) lItems)) (_ (list)))) ((none) (list)))

fn parseOpForm form: rd/SExpr -> (Result AstPatchOp PatchDiag)
  (mt form ((rd/sexprList items) (let [(head (topFormHead form))] (cond ((or (= head ":replace") (= head "replace")) (let [(target (findKvAtom items ":target")) (anchor (findKvAtom items ":anchor")) (oldNode (findKvAtom items ":oldNode")) (newNode (findKvAtom items ":newNode"))] (if (or (stringEmpty? target) (stringEmpty? oldNode) (stringEmpty? newNode)) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target anchor "Missing required fields for :replace op")) (ok (patchOpReplace target anchor oldNode newNode))))) ((or (= head ":splice") (= head "splice")) (let [(target (findKvAtom items ":target")) (anchor (findKvAtom items ":anchor")) (idxStr (findKvAtom items ":index")) (idx (optionOr (stringToInt64 idxStr) 0)) (delList (findKvStrings items ":deletedNodes")) (insList (findKvStrings items ":insertNodes"))] (if (stringEmpty? target) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target anchor "Missing required :target for :splice op")) (ok (patchOpSplice target anchor idx delList insList))))) ((or (= head ":rename") (= head "rename")) (let [(target (findKvAtom items ":target")) (oldName (findKvAtom items ":oldName")) (newName (findKvAtom items ":newName"))] (if (or (stringEmpty? target) (stringEmpty? oldName) (stringEmpty? newName)) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target "" "Missing required fields for :rename op")) (ok (patchOpRename target oldName newName))))) ((or (= head ":retype") (= head "retype")) (let [(target (findKvAtom items ":target")) (anchor (findKvAtom items ":anchor")) (oldType (findKvAtom items ":oldType")) (newType (findKvAtom items ":newType"))] (if (or (stringEmpty? target) (stringEmpty? oldType) (stringEmpty? newType)) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target anchor "Missing required fields for :retype op")) (ok (patchOpRetype target anchor oldType newType))))) (else (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Unknown operation head: " head))))))) (_ (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Operation form must be an S-expression list"))))

fn parsePatch patchText: Str -> (Result AstPatch PatchDiag)
  (let [(toks (lx/tokenize patchText)) (readRes (ast/readForms toks))] (mt readRes ((err e) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Malformed patch ASN: " e.msg)))) ((ok forms) (mt (listHead forms) ((none) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Empty patch input"))) ((some pf) (mt pf.expr ((rd/sexprList items) (let [(head (topFormHead pf.expr))] (if (and (!= head ":astPatch") (!= head "astPatch")) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Root form must be :astPatch, got: " head))) (let [(id (findKvAtom items ":id")) (targetMod (findKvAtom items ":targetModule")) (preStr (findKvAtom items ":preRoot")) (postStr (findKvAtom items ":postRoot")) (preOpt (if (stringEmpty? preStr) (none) (some preStr))) (postOpt (if (stringEmpty? postStr) (none) (some postStr))) (opsOpt (findKvNode items ":ops"))] (mt opsOpt ((none) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Missing :ops field in :astPatch"))) ((some opsNode) (let [(opForms (mt opsNode ((rd/sexprVect v) v) ((rd/sexprList l) l) (_ (list)))) (parsedOps (fold (fn [(acc (Result (List AstPatchOp) PatchDiag)) (f rd/SExpr)] -> (Result (List AstPatchOp) PatchDiag) (mt acc ((err d) (err d)) ((ok oList) (mt (parseOpForm f) ((err d) (err d)) ((ok parsedOp) (ok (listAppend oList (list parsedOp)))))))) (ok (list)) opForms))] (mt parsedOps ((err d) (err d)) ((ok ops) (if (stringEmpty? id) (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Missing :id in :astPatch")) (ok (makeAstPatch id targetMod preOpt postOpt ops)))))))))))) (_ (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Root patch form must be a list")))))))))

fn renderStrings xs: (List Str) -> Str
  (stringJoin (map quoteText xs) " ")

fn renderOp op: AstPatchOp -> Str
  (mt op ((patchOpReplace target anchor oldNode newNode) (str "    (:replace :target \"" target "\" :anchor \"" anchor "\" :oldNode " (quoteText oldNode) " :newNode " (quoteText newNode) ")")) ((patchOpSplice target anchor index deletedNodes insertNodes) (str "    (:splice :target \"" target "\" :anchor \"" anchor "\" :index " (stringFromInt64 index) " :deletedNodes [" (renderStrings deletedNodes) "] :insertNodes [" (renderStrings insertNodes) "])")) ((patchOpRename target oldName newName) (str "    (:rename :target \"" target "\" :oldName \"" oldName "\" :newName \"" newName "\")")) ((patchOpRetype target anchor oldType newType) (str "    (:retype :target \"" target "\" :anchor \"" anchor "\" :oldType \"" oldType "\" :newType \"" newType "\")")))

fn renderPatch p: AstPatch -> Str
  (let [(pre (mt p.preRoot ((some r) (str " :preRoot \"" r "\"")) ((none) ""))) (post (mt p.postRoot ((some r) (str " :postRoot \"" r "\"")) ((none) ""))) (opLines (map (fn [(op AstPatchOp)] -> Str (renderOp op)) p.ops))] (str "(:astPatch :id \"" p.id "\" :targetModule \"" p.targetModule "\"" pre post "\n  :ops [\n" (stringJoin opLines "\n") "\n  ])"))
