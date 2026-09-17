(module asl-ir/patch
  :d "Pure ASL Canonical AST Patch Algebra, Parser, and In-Memory Roundtrip Validator"
  :x [AstPatchOp patchOpReplace patchOpSplice patchOpRename patchOpRetype
      AstPatch makeAstPatch
      PatchDiag makePatchDiag
      PatchResult makePatchResult
      makePatchOpReplace makePatchOpSplice makePatchOpRename makePatchOpRetype
      makeReplacePatch
      parsePatch
      applyPatch
      invertPatch
      verifyPatch
      renderPatch
      computeAstDigest]
  :i [(asl-parser/ast :a ast)
      (asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)])

(dfe AstPatchOp
  (:c patchOpReplace [(target Str) (anchor Str) (oldNode Str) (newNode Str)]
     "Subtree substitution addressed strictly by module, symbol, and anchor")
  (:c patchOpSplice  [(target Str) (anchor Str) (index Int64) (deleteCount Int64) (insertNodes (List Str))]
     "Child sequence insertion and deletion at index or relative to anchor")
  (:c patchOpRename  [(target Str) (oldName Str) (newName Str)]
     "Identifier renaming across symbol scope")
  (:c patchOpRetype  [(target Str) (anchor Str) (oldType Str) (newType Str)]
     "Type annotation modification for parameter, field, or return type"))

(dfs AstPatch
  (:f id Str "Unique patch identifier")
  (:f targetModule Str "Target module path")
  (:f preRoot (Option Str) "Expected AST Merkle root hash before patch")
  (:f postRoot (Option Str) "Expected AST Merkle root hash after patch")
  (:f ops (List AstPatchOp) "Ordered list of atomic AST patch operations"))

(dfs PatchDiag
  (:f code Str "Diagnostic error code e.g. ERR_PATCH_...")
  (:f target Str "Target symbol or path")
  (:f anchor Str "Anchor within symbol")
  (:f message Str "Descriptive error message"))

(dfs PatchResult
  (:f success Bool "True if patch applied cleanly")
  (:f patchedSource Str "Resulting source code if success, original if failure")
  (:f inversePatch (Option AstPatch) "Inverse patch to rollback changes")
  (:f diagnostics (List PatchDiag) "Diagnostic errors if failure"))

(df makePatchOpReplace [(target Str) (anchor Str) (oldNode Str) (newNode Str)] -> AstPatchOp
  :d "Constructs a patchOpReplace variant."
  (patchOpReplace target anchor oldNode newNode))

(df makePatchOpSplice [(target Str) (anchor Str) (index Int64) (deleteCount Int64) (insertNodes (List Str))] -> AstPatchOp
  :d "Constructs a patchOpSplice variant."
  (patchOpSplice target anchor index deleteCount insertNodes))

(df makePatchOpRename [(target Str) (oldName Str) (newName Str)] -> AstPatchOp
  :d "Constructs a patchOpRename variant."
  (patchOpRename target oldName newName))

(df makePatchOpRetype [(target Str) (anchor Str) (oldType Str) (newType Str)] -> AstPatchOp
  :d "Constructs a patchOpRetype variant."
  (patchOpRetype target anchor oldType newType))

(df makeAstPatch [(id Str) (targetModule Str) (preRoot (Option Str)) (postRoot (Option Str)) (ops (List AstPatchOp))] -> AstPatch
  :d "Constructs an AstPatch record."
  (AstPatch :id id :targetModule targetModule :preRoot preRoot :postRoot postRoot :ops ops))

(df makePatchDiag [(code Str) (target Str) (anchor Str) (message Str)] -> PatchDiag
  :d "Constructs a PatchDiag record."
  (PatchDiag :code code :target target :anchor anchor :message message))

(df makePatchResult [(success Bool) (patchedSource Str) (inversePatch (Option AstPatch)) (diagnostics (List PatchDiag))] -> PatchResult
  :d "Constructs a PatchResult record."
  (PatchResult :success success :patchedSource patchedSource :inversePatch inversePatch :diagnostics diagnostics))

(df makeReplacePatch [(id Str) (targetModule Str) (targetSymbol Str) (anchor Str) (oldNode Str) (newNode Str)] -> AstPatch
  :d "Constructs a single-op replace AST patch for agent editing or mutation refutation."
  (makeAstPatch id targetModule (none) (none) (list (makePatchOpReplace targetSymbol anchor oldNode newNode))))

(df extractSymbolName [(target Str)] -> Str
  :d "Extracts unqualified symbol name from Module:symbol or returns symbol."
  (if (string-contains? target ":")
      (let [(parts (string-split target ":"))
            (len (list-length parts))]
        (if (> len 0)
            (option-or (list-get parts (- len 1)) target)
            target))
      target))

(df unquoteText [(s Str)] -> Str
  :d "Strips enclosing quotes from a string literal if present."
  (let [(len (string-length s))]
    (if (and (>= len 2)
             (string-starts-with? s "\"")
             (string-ends-with? s "\""))
        (option-or (string-slice s 1 (- len 1)) "")
        s)))

(df charVal [(c Str)] -> Int64
  :d "Maps single character to deterministic integer code."
  (let [(chars " 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ()[]{}\":;,.+-*/=_<>&|!?@#$%'`~^\n\t\r\\")
        (idx (string-index-of chars c))]
    (if (>= idx 0)
        (+ idx 32)
        42)))

(df computeAstDigest [(src Str)] -> Str
  :d "Computes a deterministic digest string over source text."
  (let [(len (string-length src))
        (h (fold (fn [(acc Int64) (c Str)] -> Int64
                   (let [(code (charVal c))]
                     (mod (+ (* acc 31) code) 1000000007)))
                 17
                 (string-chars src)))]
    (str "d" (string-from-int64 len) "x" (string-from-int64 h))))

(df parseSexprSnippet [(s Str)] -> (Result rd/SExpr Str)
  :d "Parses a code snippet string into an SExpr."
  (let [(toks (lx/tokenize s))
        (res (ast/readForms toks))]
    (mt res
      ((ok forms)
       (mt (list-head forms)
         ((some pf) (ok (.-expr pf)))
         ((none) (ok (rd/makeAtom s)))))
      ((err e)
       (err (.-msg e))))))

(df topFormHead [(form rd/SExpr)] -> Str
  :d "Extracts head symbol from top-level SExpr list."
  (mt form
    ((rd/sexprList items)
     (mt (list-head items)
       ((some h) (rd/sexprHead h))
       ((none) "")))
    (_ "")))

(df topFormSymbol [(form rd/SExpr)] -> Str
  :d "Extracts the identifying symbol name of a top-level form."
  (mt form
    ((rd/sexprList items)
     (let [(headText (topFormHead form))]
       (if (or (= headText "df") (= headText "defun") (= headText "def")
               (= headText "dfs") (= headText "defschema") (= headText "schema")
               (= headText "dfe") (= headText "defenum") (= headText "enum")
               (= headText "module"))
           (let [(secondOpt (list-head (option-or (list-tail items) (list))))]
             (mt secondOpt
               ((some s) (rd/sexprHead s))
               ((none) "")))
           "")))
    (_ "")))

(dfs ReplaceState
  (:f expr rd/SExpr)
  (:f replaced Bool))

(df replaceInSexpr [(expr rd/SExpr) (oldStr Str) (newExpr rd/SExpr)] -> ReplaceState
  :d "Recursively searches and replaces matching S-expression node."
  (let [(rendered (rd/renderSexpr expr))]
    (if (= rendered oldStr)
        (ReplaceState :expr newExpr :replaced true)
        (mt expr
          ((rd/sexprAtom v)
           (if (= v oldStr)
               (ReplaceState :expr newExpr :replaced true)
               (ReplaceState :expr expr :replaced false)))
          ((rd/sexprList items)
           (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Bool)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Bool)
                               (if (.-second acc)
                                   (Pair (list-append (.-first acc) (list it)) true)
                                   (let [(sub (replaceInSexpr it oldStr newExpr))]
                                     (if (.-replaced sub)
                                         (Pair (list-append (.-first acc) (list (.-expr sub))) true)
                                         (Pair (list-append (.-first acc) (list it)) false)))))
                             (Pair (list) false)
                             items))]
             (if (.-second step)
                 (ReplaceState :expr (rd/makeList (.-first step)) :replaced true)
                 (ReplaceState :expr expr :replaced false))))
          ((rd/sexprVect items)
           (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Bool)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Bool)
                               (if (.-second acc)
                                   (Pair (list-append (.-first acc) (list it)) true)
                                   (let [(sub (replaceInSexpr it oldStr newExpr))]
                                     (if (.-replaced sub)
                                         (Pair (list-append (.-first acc) (list (.-expr sub))) true)
                                         (Pair (list-append (.-first acc) (list it)) false)))))
                             (Pair (list) false)
                             items))]
             (if (.-second step)
                 (ReplaceState :expr (rd/makeVect (.-first step)) :replaced true)
                 (ReplaceState :expr expr :replaced false))))))))

(df renameInSexpr [(expr rd/SExpr) (oldName Str) (newName Str)] -> (Pair rd/SExpr Int64)
  :d "Recursively renames identifiers matching oldName to newName."
  (mt expr
    ((rd/sexprAtom v)
     (if (= v oldName)
         (Pair (rd/makeAtom newName) 1)
         (Pair expr 0)))
    ((rd/sexprList items)
     (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Int64)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Int64)
                         (let [(sub (renameInSexpr it oldName newName))]
                           (Pair (list-append (.-first acc) (list (.-first sub)))
                                 (+ (.-second acc) (.-second sub)))))
                       (Pair (list) 0)
                       items))]
       (Pair (rd/makeList (.-first step)) (.-second step))))
    ((rd/sexprVect items)
     (let [(step (fold (fn [(acc (Pair (List rd/SExpr) Int64)) (it rd/SExpr)] -> (Pair (List rd/SExpr) Int64)
                         (let [(sub (renameInSexpr it oldName newName))]
                           (Pair (list-append (.-first acc) (list (.-first sub)))
                                 (+ (.-second acc) (.-second sub)))))
                       (Pair (list) 0)
                       items))]
       (Pair (rd/makeVect (.-first step)) (.-second step))))))

(df takeItems [(n Int64) (xs (List rd/SExpr))] -> (List rd/SExpr)
  :d "Takes first n items from SExpr list."
  (if (<= n 0)
      (list)
      (mt (list-head xs)
        ((some h)
         (list-cons h (takeItems (- n 1) (option-or (list-tail xs) (list)))))
        ((none) (list)))))

(df dropItems [(n Int64) (xs (List rd/SExpr))] -> (List rd/SExpr)
  :d "Drops first n items from SExpr list."
  (if (<= n 0)
      xs
      (mt (list-tail xs)
        ((some tl) (dropItems (- n 1) tl))
        ((none) (list)))))

(df findRetTypePos [(items (List rd/SExpr))] -> Int64
  :d "Finds 0-based index of return type element in defun items."
  (let [(len (list-length items))]
    (let [(idx (fold (fn [(acc Int64) (i Int64)] -> Int64
                       (if (!= acc -1)
                           acc
                           (let [(it (option-or (list-get items i) (rd/makeAtom "")))]
                             (if (= (rd/sexprHead it) "->")
                                 (+ i 1)
                                 -1))))
                     -1
                     (range 0 len)))]
      idx)))

(df applyReplaceOp [(form rd/SExpr) (anchor Str) (oldNode Str) (newNode Str)] -> (Result rd/SExpr PatchDiag)
  :d "Applies a replace operation to a top-level form."
  (let [(parsedNew (parseSexprSnippet newNode))]
    (mt parsedNew
      ((err e)
       (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" anchor (str "Replacement newNode has invalid syntax: " e))))
      ((ok newExpr)
       (cond
         ((= anchor "retType")
          (mt form
            ((rd/sexprList items)
             (let [(pos (findRetTypePos items))]
               (if (< pos 0)
                   (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Return type anchor '->' not found in symbol"))
                   (let [(curr (option-or (list-get items pos) (rd/makeAtom "")))]
                     (if (!= (rd/renderSexpr curr) oldNode)
                         (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" anchor (str "Expected oldNode '" oldNode "' but found '" (rd/renderSexpr curr) "'")))
                         (let [(before (takeItems pos items))
                               (after (dropItems (+ pos 1) items))
                               (updated (list-append (list-append before (list newExpr)) after))]
                           (ok (rd/makeList updated))))))))
            (_ (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Target form is not a list")))))
         ((or (= anchor "body") (= anchor "") (= anchor "root"))
          (let [(res (replaceInSexpr form oldNode newExpr))]
            (if (.-replaced res)
                (ok (.-expr res))
                (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" anchor (str "Subtree matching oldNode '" oldNode "' not found in target"))))))
         (:else
          (let [(res (replaceInSexpr form oldNode newExpr))]
            (if (.-replaced res)
                (ok (.-expr res))
                (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor (str "Anchor '" anchor "' not found in target symbol")))))))))))

(df applySpliceOp [(form rd/SExpr) (anchor Str) (index Int64) (deleteCount Int64) (insertNodes (List Str))] -> (Result rd/SExpr PatchDiag)
  :d "Applies a splice operation to a list or vector inside top-level form."
  (mt form
    ((rd/sexprList items)
     (let [(pos (findRetTypePos items))]
       (if (< pos 0)
           (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Target form does not support splicing"))
           (let [(bodyStart (+ pos 1))
                 (bodyItems (dropItems bodyStart items))
                 (bodyLen (list-length bodyItems))]
             (if (or (< index 0) (> index bodyLen))
                 (err (makePatchDiag "ERR_PATCH_INDEX_OUT_OF_BOUNDS" "" anchor (str "Splice index " (string-from-int64 index) " out of bounds for body length " (string-from-int64 bodyLen))))
                 (let [(parsedInsert (fold (fn [(acc (Result (List rd/SExpr) Str)) (nodeStr Str)] -> (Result (List rd/SExpr) Str)
                                             (mt acc
                                               ((err e) (err e))
                                               ((ok listAcc)
                                                (mt (parseSexprSnippet nodeStr)
                                                  ((err pe) (err pe))
                                                  ((ok parsed) (ok (list-append listAcc (list parsed))))))))
                                           (ok (list))
                                           insertNodes))]
                   (mt parsedInsert
                     ((err e)
                      (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" anchor (str "Inserted node has invalid syntax: " e))))
                     ((ok insExprs)
                      (let [(beforeDel (takeItems index bodyItems))
                            (afterDel (dropItems (+ index deleteCount) bodyItems))
                            (newBody (list-append (list-append beforeDel insExprs) afterDel))
                            (header (takeItems bodyStart items))
                            (newForm (list-append header newBody))]
                        (ok (rd/makeList newForm)))))))))))
    (_ (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor "Target form is not a list")))))

(df applyRenameOp [(form rd/SExpr) (oldName Str) (newName Str)] -> (Result rd/SExpr PatchDiag)
  :d "Applies identifier rename across target symbol AST."
  (let [(res (renameInSexpr form oldName newName))]
    (if (<= (.-second res) 0)
        (err (makePatchDiag "ERR_PATCH_OLD_NODE_MISMATCH" "" "" (str "Identifier '" oldName "' not found in target symbol")))
        (ok (.-first res)))))

(df applyRetypeOp [(form rd/SExpr) (anchor Str) (oldType Str) (newType Str)] -> (Result rd/SExpr PatchDiag)
  :d "Applies retype operation to parameter or return type."
  (if (= anchor "retType")
      (applyReplaceOp form "retType" oldType newType)
      (if (string-starts-with? anchor "param:")
          (let [(pName (string-replace anchor "param:" ""))
                (oldPat (str "(" pName " " oldType ")"))
                (newPat (str "(" pName " " newType ")"))]
            (applyReplaceOp form "params" oldPat newPat))
          (err (makePatchDiag "ERR_PATCH_ANCHOR_NOT_FOUND" "" anchor (str "Unsupported retype anchor: " anchor))))))

(df applyOpToForm [(form rd/SExpr) (op AstPatchOp)] -> (Result rd/SExpr PatchDiag)
  :d "Dispatches an AST patch op to the targeted top-level form."
  (mt op
    ((patchOpReplace _ anchor oldNode newNode)
     (applyReplaceOp form anchor oldNode newNode))
    ((patchOpSplice _ anchor index deleteCount insertNodes)
     (applySpliceOp form anchor index deleteCount insertNodes))
    ((patchOpRename _ oldName newName)
     (applyRenameOp form oldName newName))
    ((patchOpRetype _ anchor oldType newType)
     (applyRetypeOp form anchor oldType newType))))

(df getOpTarget [(op AstPatchOp)] -> Str
  :d "Extracts target symbol from patch op."
  (mt op
    ((patchOpReplace t _ _ _) t)
    ((patchOpSplice t _ _ _ _) t)
    ((patchOpRename t _ _) t)
    ((patchOpRetype t _ _ _) t)))

(df invertOp [(op AstPatchOp)] -> AstPatchOp
  :d "Inverts a single AST patch op."
  (mt op
    ((patchOpReplace t a oldNode newNode)
     (patchOpReplace t a newNode oldNode))
    ((patchOpSplice t a index deleteCount insertNodes)
     (patchOpSplice t a index (list-length insertNodes) (list)))
    ((patchOpRename t oldName newName)
     (patchOpRename t newName oldName))
    ((patchOpRetype t a oldType newType)
     (patchOpRetype t a newType oldType))))

(df invertPatch [(patch AstPatch)] -> AstPatch
  :d "Generates the inverse AST patch for rollback."
  (let [(invOps (map (fn [(op AstPatchOp)] -> AstPatchOp (invertOp op))
                     (list-reverse (.-ops patch))))]
    (makeAstPatch (str (.-id patch) ":inv")
                  (.-targetModule patch)
                  (.-postRoot patch)
                  (.-preRoot patch)
                  invOps)))

(df validatePatchedSource [(source Str)] -> (Option Str)
  :d "Validates that patched source is syntactically sound, balanced, and parseable into AST."
  (let [(toks (lx/tokenize source))]
    (let [(readRes (ast/readForms toks))]
      (mt readRes
        ((err e)
         (some (str "Delimiter balance failure: " (.-msg e))))
        ((ok posForms)
         (let [(parseRes (ast/parse source))]
           (mt parseRes
             ((err pe)
              (some (str "AST parse failure: " (.-msg pe))))
             ((ok topForms)
              (if (list-empty? topForms)
                  (some "AST parse produced zero top-level declarations")
                  (none))))))))))

(df renderAllForms [(forms (List rd/SExpr))] -> Str
  :d "Renders all top-level forms separated by blank lines."
  (string-join (map (fn [(f rd/SExpr)] -> Str (rd/renderSexpr f)) forms) "\n\n"))

(df applyPatch [(patch AstPatch) (sourceCode Str)] -> PatchResult
  :d "Applies an AST patch to source code with in-memory roundtrip validation."
  (if (list-empty? (.-ops patch))
      (makePatchResult false sourceCode (none) (list (makePatchDiag "ERR_PATCH_EMPTY_OPS" "" "" "Patch contains no operations")))
      (let [(preCheck (mt (.-preRoot patch)
                        ((some expected)
                         (let [(actual (computeAstDigest sourceCode))]
                           (if (!= actual expected)
                               (some (makePatchDiag "ERR_CONCURRENCY_CONFLICT" (.-targetModule patch) "" (str "Pre-condition Merkle root conflict: expected " expected " but got " actual)))
                               (none))))
                        ((none) (none))))]
        (mt preCheck
          ((some diag)
           (makePatchResult false sourceCode (none) (list diag)))
          ((none)
           (let [(toks (lx/tokenize sourceCode))
                 (readRes (ast/readForms toks))]
             (mt readRes
               ((err e)
                (makePatchResult false sourceCode (none) (list (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Source file parse error: " (.-msg e))))))
               ((ok posForms)
                (let [(currentForms (map (fn [(pf ast/PosForm)] -> rd/SExpr (.-expr pf)) posForms))
                      (applyStep (fold (fn [(acc (Result (List rd/SExpr) PatchDiag)) (op AstPatchOp)] -> (Result (List rd/SExpr) PatchDiag)
                                         (mt acc
                                           ((err d) (err d))
                                           ((ok fList)
                                            (let [(targetSym (extractSymbolName (getOpTarget op)))
                                                  (found (fold (fn [(subAcc (Pair (List rd/SExpr) (Pair Bool (Option PatchDiag)))) (f rd/SExpr)] -> (Pair (List rd/SExpr) (Pair Bool (Option PatchDiag)))
                                                                 (if (.-first (.-second subAcc))
                                                                     (Pair (list-append (.-first subAcc) (list f)) (.-second subAcc))
                                                                     (if (= (topFormSymbol f) targetSym)
                                                                         (mt (applyOpToForm f op)
                                                                           ((ok updated)
                                                                            (Pair (list-append (.-first subAcc) (list updated)) (Pair true (none))))
                                                                           ((err d)
                                                                            (Pair (list-append (.-first subAcc) (list f)) (Pair true (some d)))))
                                                                         (Pair (list-append (.-first subAcc) (list f)) (Pair false (none))))))
                                                               (Pair (list) (Pair false (none)))
                                                               fList))]
                                              (if (not (.-first (.-second found)))
                                                  (err (makePatchDiag "ERR_PATCH_SYMBOL_NOT_FOUND" targetSym "" (str "Target symbol '" targetSym "' not found in module")))
                                                  (mt (.-second (.-second found))
                                                    ((some diag) (err diag))
                                                    ((none) (ok (.-first found)))))))))
                                       (ok currentForms)
                                       (.-ops patch)))]
                  (mt applyStep
                    ((err diag)
                     (makePatchResult false sourceCode (none) (list diag)))
                    ((ok newForms)
                     (let [(candidateSource (renderAllForms newForms))
                           (valErr (validatePatchedSource candidateSource))]
                       (mt valErr
                         ((some errMsg)
                          (makePatchResult false sourceCode (none) (list (makePatchDiag "ERR_PATCH_VALIDATION_FAILED" "" "" errMsg))))
                         ((none)
                          (let [(postDigest (computeAstDigest candidateSource))
                                (preDigest (computeAstDigest sourceCode))
                                (invOps (map (fn [(op AstPatchOp)] -> AstPatchOp (invertOp op))
                                             (list-reverse (.-ops patch))))
                                (invPatch (makeAstPatch (str (.-id patch) ":inv")
                                                        (.-targetModule patch)
                                                        (some postDigest)
                                                        (some preDigest)
                                                        invOps))]
                            (makePatchResult true candidateSource (some invPatch) (list)))))))))))))))))

(df verifyPatch [(patch AstPatch) (sourceCode Str)] -> (Result Unit (List PatchDiag))
  :d "Verifies whether a patch can apply cleanly to the given source code without committing."
  (let [(res (applyPatch patch sourceCode))]
    (if (.-success res)
        (ok ())
        (err (.-diagnostics res)))))

(df findKvAtom [(items (List rd/SExpr)) (key Str)] -> Str
  :d "Finds atom value following keyword key in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
           (mt (list-head rest)
             ((some valNode) (unquoteText (rd/sexprHead valNode)))
             ((none) ""))
           (findKvAtom rest key))))
    ((none) "")))

(df findKvNode [(items (List rd/SExpr)) (key Str)] -> (Option rd/SExpr)
  :d "Finds node value following keyword key in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
           (list-head rest)
           (findKvNode rest key))))
    ((none) (none))))

(df parseOpForm [(form rd/SExpr)] -> (Result AstPatchOp PatchDiag)
  :d "Parses single patch operation from SExpr."
  (mt form
    ((rd/sexprList items)
     (let [(head (topFormHead form))]
       (cond
         ((or (= head ":replace") (= head "replace"))
          (let [(target (findKvAtom items ":target"))
                (anchor (findKvAtom items ":anchor"))
                (oldNode (findKvAtom items ":oldNode"))
                (newNode (findKvAtom items ":newNode"))]
            (if (or (string-empty? target) (string-empty? oldNode) (string-empty? newNode))
                (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target anchor "Missing required fields for :replace op"))
                (ok (patchOpReplace target anchor oldNode newNode)))))
         ((or (= head ":splice") (= head "splice"))
          (let [(target (findKvAtom items ":target"))
                (anchor (findKvAtom items ":anchor"))
                (idxStr (findKvAtom items ":index"))
                (delStr (findKvAtom items ":deleteCount"))
                (idx (option-or (string-to-int64 idxStr) 0))
                (del (option-or (string-to-int64 delStr) 0))
                (insOpt (findKvNode items ":insertNodes"))
                (insList (mt insOpt
                           ((some n)
                            (mt n
                              ((rd/sexprVect vItems)
                               (map (fn [(it rd/SExpr)] -> Str (unquoteText (rd/sexprHead it))) vItems))
                              ((rd/sexprList lItems)
                               (map (fn [(it rd/SExpr)] -> Str (unquoteText (rd/sexprHead it))) lItems))
                              (_ (list))))
                           ((none) (list))))]
            (if (string-empty? target)
                (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target anchor "Missing required :target for :splice op"))
                (ok (patchOpSplice target anchor idx del insList)))))
         ((or (= head ":rename") (= head "rename"))
          (let [(target (findKvAtom items ":target"))
                (oldName (findKvAtom items ":oldName"))
                (newName (findKvAtom items ":newName"))]
            (if (or (string-empty? target) (string-empty? oldName) (string-empty? newName))
                (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target "" "Missing required fields for :rename op"))
                (ok (patchOpRename target oldName newName)))))
         ((or (= head ":retype") (= head "retype"))
          (let [(target (findKvAtom items ":target"))
                (anchor (findKvAtom items ":anchor"))
                (oldType (findKvAtom items ":oldType"))
                (newType (findKvAtom items ":newType"))]
            (if (or (string-empty? target) (string-empty? oldType) (string-empty? newType))
                (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" target anchor "Missing required fields for :retype op"))
                (ok (patchOpRetype target anchor oldType newType)))))
         (:else
          (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Unknown operation head: " head)))))))
    (_ (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Operation form must be an S-expression list")))))

(df parsePatch [(patchText Str)] -> (Result AstPatch PatchDiag)
  :d "Parses an AST patch from ASN text representation."
  (let [(toks (lx/tokenize patchText))
        (readRes (ast/readForms toks))]
    (mt readRes
      ((err e)
       (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Malformed patch ASN: " (.-msg e)))))
      ((ok forms)
       (mt (list-head forms)
         ((none)
          (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Empty patch input")))
         ((some pf)
          (mt (.-expr pf)
            ((rd/sexprList items)
             (let [(head (topFormHead (.-expr pf)))]
               (if (and (!= head ":astPatch") (!= head "astPatch"))
                   (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" (str "Root form must be :astPatch, got: " head)))
                   (let [(id (findKvAtom items ":id"))
                         (targetMod (findKvAtom items ":targetModule"))
                         (preStr (findKvAtom items ":preRoot"))
                         (postStr (findKvAtom items ":postRoot"))
                         (preOpt (if (string-empty? preStr) (none) (some preStr)))
                         (postOpt (if (string-empty? postStr) (none) (some postStr)))
                         (opsOpt (findKvNode items ":ops"))]
                     (mt opsOpt
                       ((none)
                        (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Missing :ops field in :astPatch")))
                       ((some opsNode)
                        (let [(opForms (mt opsNode
                                         ((rd/sexprVect v) v)
                                         ((rd/sexprList l) l)
                                         (_ (list))))
                              (parsedOps (fold (fn [(acc (Result (List AstPatchOp) PatchDiag)) (f rd/SExpr)] -> (Result (List AstPatchOp) PatchDiag)
                                                 (mt acc
                                                   ((err d) (err d))
                                                   ((ok oList)
                                                    (mt (parseOpForm f)
                                                      ((err d) (err d))
                                                      ((ok parsedOp) (ok (list-append oList (list parsedOp))))))))
                                               (ok (list))
                                               opForms))]
                          (mt parsedOps
                            ((err d) (err d))
                            ((ok ops)
                             (if (string-empty? id)
                                 (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Missing :id in :astPatch"))
                                 (ok (makeAstPatch id targetMod preOpt postOpt ops))))))))))))
            (_
             (err (makePatchDiag "ERR_PATCH_INVALID_SYNTAX" "" "" "Root patch form must be a list"))))))))))

(df renderOp [(op AstPatchOp)] -> Str
  :d "Renders an atomic AST patch op to ASN format."
  (mt op
    ((patchOpReplace target anchor oldNode newNode)
     (str "    (:replace :target \"" target "\" :anchor \"" anchor "\" :oldNode \"" (string-replace oldNode "\"" "\\\"") "\" :newNode \"" (string-replace newNode "\"" "\\\"") "\")"))
    ((patchOpSplice target anchor index deleteCount insertNodes)
     (let [(insStr (string-join (map (fn [(s Str)] -> Str (str "\"" (string-replace s "\"" "\\\"") "\"")) insertNodes) " "))]
       (str "    (:splice :target \"" target "\" :anchor \"" anchor "\" :index " (string-from-int64 index) " :deleteCount " (string-from-int64 deleteCount) " :insertNodes [" insStr "])")))
    ((patchOpRename target oldName newName)
     (str "    (:rename :target \"" target "\" :oldName \"" oldName "\" :newName \"" newName "\")"))
    ((patchOpRetype target anchor oldType newType)
     (str "    (:retype :target \"" target "\" :anchor \"" anchor "\" :oldType \"" oldType "\" :newType \"" newType "\")"))))

(df renderPatch [(p AstPatch)] -> Str
  :d "Renders an AstPatch structure to ASN text."
  (let [(pre (mt (.-preRoot p)
               ((some r) (str " :preRoot \"" r "\""))
               ((none) "")))
        (post (mt (.-postRoot p)
                ((some r) (str " :postRoot \"" r "\""))
                ((none) "")))
        (opLines (map (fn [(op AstPatchOp)] -> Str (renderOp op)) (.-ops p)))]
    (str "(:astPatch :id \"" (.-id p) "\" :targetModule \"" (.-targetModule p) "\"" pre post "\n  :ops [\n"
         (string-join opLines "\n")
         "\n  ])")))
