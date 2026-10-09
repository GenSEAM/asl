(module asl-compiler/heal :x [HealTransactionResult makeHealTransactionResult RollbackJournalRecord makeRollbackJournalRecord createRollbackJournalEntry canRetryHeal synthesizeHealPatch verifyHealPatchCandidate applyHealTransaction getPatchOpKind] :i [(asl-ir/patch :a patch) (asl-compiler/diagnostics :a diag) (asl-parser/ast :a ast)])

fn getPatchOpKind op: patch/AstPatchOp -> Str
  (mt op ((patch/patchOpReplace _ _ _ _) "replace") ((patch/patchOpSplice _ _ _ _ _) "splice") ((patch/patchOpRename _ _ _) "rename") ((patch/patchOpRetype _ _ _ _) "retype"))

(schema HealTransactionResult (:f success Bool) (:f patchedSource Str) (:f inversePatch (Option patch/AstPatch)) (:f isRolledBack Bool) (:f errorMessage Str))

fn makeHealTransactionResult success: Bool patchedSource: Str inversePatch: (Option patch/AstPatch) isRolledBack: Bool errorMessage: Str -> HealTransactionResult
  (HealTransactionResult :success success :patchedSource patchedSource :inversePatch inversePatch :isRolledBack isRolledBack :errorMessage errorMessage)

(schema RollbackJournalRecord (:f patchId Str) (:f targetFile Str) (:f targetModule Str) (:f preRoot Str) (:f postRoot Str) (:f inversePatch patch/AstPatch) (:f timestamp Int64))

fn makeRollbackJournalRecord patchId: Str targetFile: Str targetModule: Str preRoot: Str postRoot: Str inversePatch: patch/AstPatch timestamp: Int64 -> RollbackJournalRecord
  (RollbackJournalRecord :patchId patchId :targetFile targetFile :targetModule targetModule :preRoot preRoot :postRoot postRoot :inversePatch inversePatch :timestamp timestamp)

fn createRollbackJournalEntry patchId: Str targetFile: Str targetModule: Str preRoot: Str postRoot: Str inversePatch: patch/AstPatch timestamp: Int64 -> RollbackJournalRecord
  (makeRollbackJournalRecord patchId targetFile targetModule preRoot postRoot inversePatch timestamp)

fn canRetryHeal attempt: Int64 maxAttempts: Int64 -> Bool
  (and (>= attempt 1) (<= attempt maxAttempts))

fn synthesizeHealPatch errorCode: Str targetModule: Str targetSymbol: Str paramA: Str paramB: Str -> (Option patch/AstPatch)
  (cond ((or (= errorCode "ERR_MISSING_IMPORT") (= errorCode "ERR_UNBOUND_SYMBOL")) (some (diag/suggestMissingImportPatch targetModule paramA paramB))) ((= errorCode "ERR_UNHANDLED_VARIANT") (some (diag/suggestMissingMatchBranchPatch targetModule targetSymbol paramA paramB))) ((= errorCode "ERR_TYPE_MISMATCH") (some (diag/suggestTypeMismatchPatch targetModule targetSymbol paramA paramB))) ((= errorCode "ERR_UNEXPORTED_SYMBOL") (some (diag/suggestMissingExportPatch targetModule paramA paramB))) (else (none)))

fn verifyHealPatchCandidate p: patch/AstPatch src: Str -> Bool
  (let [(verifyRes (patch/verifyPatch p src))] (ok? verifyRes))

fn applyHealTransaction origSrc: Str candidatePatch: patch/AstPatch -> HealTransactionResult
  (let [(verifyRes (patch/verifyPatch candidatePatch origSrc))] (mt verifyRes ((err diags) (let [(msg (if (not (listEmpty? diags)) (optionOr (listHead diags) (patch/makePatchDiag "" "" "" "Unknown verification error")).message "Candidate patch verification failed"))] (makeHealTransactionResult false origSrc (none) true msg))) ((ok _) (let [(patchRes (patch/applyPatch candidatePatch origSrc))] (if patchRes.success (makeHealTransactionResult true patchRes.patchedSource patchRes.inversePatch false "") (let [(msg (if (not (listEmpty? patchRes.diagnostics)) (optionOr (listHead patchRes.diagnostics) (patch/makePatchDiag "" "" "" "Patch application failed")).message "Patch application failed"))] (makeHealTransactionResult false origSrc (none) true msg)))))))
