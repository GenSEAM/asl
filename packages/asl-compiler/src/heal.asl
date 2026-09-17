(module asl-compiler/heal
  :d "Autonomous Self-Healing Compiler Bridge, Candidate AST Patch Synthesis, and Transactional Feedback Loop under ADR D97."
  :x [HealTransactionResult makeHealTransactionResult
      RollbackJournalRecord makeRollbackJournalRecord
      createRollbackJournalEntry
      canRetryHeal
      synthesizeHealPatch
      verifyHealPatchCandidate
      applyHealTransaction
      getPatchOpKind]
  :i [(asl-ir/patch :a patch)
      (asl-compiler/diagnostics :a diag)
      (asl-parser/ast :a ast)])

(df getPatchOpKind [(op patch/AstPatchOp)] -> Str
  (:d "Returns the discriminant kind of an AST patch operation.")
  (mt op
    ((patch/patchOpReplace _ _ _ _) "replace")
    ((patch/patchOpSplice _ _ _ _ _) "splice")
    ((patch/patchOpRename _ _ _) "rename")
    ((patch/patchOpRetype _ _ _ _) "retype")))

(dfs HealTransactionResult
  (:f success Bool)
  (:f patchedSource Str)
  (:f inversePatch (Option patch/AstPatch))
  (:f isRolledBack Bool)
  (:f errorMessage Str))

(df makeHealTransactionResult [(success Bool) (patchedSource Str) (inversePatch (Option patch/AstPatch)) (isRolledBack Bool) (errorMessage Str)] -> HealTransactionResult
  :d "Constructs a HealTransactionResult record."
  (HealTransactionResult :success success
                         :patchedSource patchedSource
                         :inversePatch inversePatch
                         :isRolledBack isRolledBack
                         :errorMessage errorMessage))

(dfs RollbackJournalRecord
  (:f patchId Str)
  (:f targetFile Str)
  (:f targetModule Str)
  (:f preRoot Str)
  (:f postRoot Str)
  (:f inversePatch patch/AstPatch)
  (:f timestamp Int64))

(df makeRollbackJournalRecord [(patchId Str) (targetFile Str) (targetModule Str) (preRoot Str) (postRoot Str) (inversePatch patch/AstPatch) (timestamp Int64)] -> RollbackJournalRecord
  :d "Constructs a RollbackJournalRecord record."
  (RollbackJournalRecord :patchId patchId
                         :targetFile targetFile
                         :targetModule targetModule
                         :preRoot preRoot
                         :postRoot postRoot
                         :inversePatch inversePatch
                         :timestamp timestamp))

(df createRollbackJournalEntry [(patchId Str) (targetFile Str) (targetModule Str) (preRoot Str) (postRoot Str) (inversePatch patch/AstPatch) (timestamp Int64)] -> RollbackJournalRecord
  :d "Constructs a RollbackJournalRecord for external journal tracking under ADR D97."
  (makeRollbackJournalRecord patchId targetFile targetModule preRoot postRoot inversePatch timestamp))

(df canRetryHeal [(attempt Int64) (maxAttempts Int64)] -> Bool
  :d "Checks whether a self-healing attempt is within the limit-cycle circuit breaker ceiling."
  (and (>= attempt 1) (<= attempt maxAttempts)))

(df synthesizeHealPatch [(errorCode Str) (targetModule Str) (targetSymbol Str) (paramA Str) (paramB Str)] -> (Option patch/AstPatch)
  :d "Synthesizes a structured candidate AST patch from a compiler error diagnostic code."
  (cond
    ((or (= errorCode "ERR_MISSING_IMPORT") (= errorCode "ERR_UNBOUND_SYMBOL"))
     (some (diag/suggestMissingImportPatch targetModule paramA paramB)))
    ((= errorCode "ERR_UNHANDLED_VARIANT")
     (some (diag/suggestMissingMatchBranchPatch targetModule targetSymbol paramA paramB)))
    ((= errorCode "ERR_TYPE_MISMATCH")
     (some (diag/suggestTypeMismatchPatch targetModule targetSymbol paramA paramB)))
    ((= errorCode "ERR_UNEXPORTED_SYMBOL")
     (some (diag/suggestMissingExportPatch targetModule paramA paramB)))
    (:else
     (none))))

(df verifyHealPatchCandidate [(p patch/AstPatch) (src Str)] -> Bool
  :d "Verifies whether a candidate patch can be safely applied to the source AST."
  (let [(verifyRes (patch/verifyPatch p src))]
    (is-ok? verifyRes)))

(df applyHealTransaction [(origSrc Str) (candidatePatch patch/AstPatch)] -> HealTransactionResult
  :d "Applies candidate AST patch transactionally, producing patched source and inverse rollback patch or rolling back cleanly."
  (let [(verifyRes (patch/verifyPatch candidatePatch origSrc))]
    (mt verifyRes
      ((err diags)
       (let [(msg (if (not (list-empty? diags))
                      (.-message (option-or (list-head diags) (patch/makePatchDiag "" "" "" "Unknown verification error")))
                      "Candidate patch verification failed"))]
         (makeHealTransactionResult false origSrc (none) true msg)))
      ((ok _)
       (let [(patchRes (patch/applyPatch candidatePatch origSrc))]
         (if (.-success patchRes)
             (makeHealTransactionResult true (.-patchedSource patchRes) (.-inversePatch patchRes) false "")
             (let [(msg (if (not (list-empty? (.-diagnostics patchRes)))
                            (.-message (option-or (list-head (.-diagnostics patchRes)) (patch/makePatchDiag "" "" "" "Patch application failed")))
                            "Patch application failed"))]
               (makeHealTransactionResult false origSrc (none) true msg))))))))
