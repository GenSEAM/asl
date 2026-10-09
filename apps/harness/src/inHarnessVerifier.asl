(module aslHarness/inHarnessVerifier
  :x [PlanGateItem
      RefusalReceipt
      HarnessTurnState
      VerificationResult
      initTurnState
      registerPlanItem
      registerRefusal
      recordGateExecution
      recordGateDetailedExecution
      recordCommandExecution
      validateTurnCompletion
      auditActionPrecondition
      auditActionPreconditionWithReversibility
      formatVerificationFeedback
      isMutatingAction?
      isReversalAction?
      isAssertionDeletion?
      auditRefusalPolarity]
  :i [(asl-text/string :a s)])

(schema PlanGateItem
  (:f id Str)
  (:f description Str)
  (:f verificationCommand Str)
  (:f executed Bool)
  (:f passed Bool)
  (:f exitCode I64)
  (:f assertCount I64)
  (:f minAssertCount I64)
  (:f mutantsKilled I64)
  (:f minMutantsKilled I64)
  (:f isNonVacuous Bool)
  (:f receiptDigest Str))

(schema RefusalReceipt
  (:f refusalKind Str)
  (:f grounds Str)
  (:f charterCitation Str)
  (:f targetCommand Str)
  (:f falsifierWitness Str))

(schema HarnessTurnState
  (:f plannedItems (List PlanGateItem))
  (:f mutatingActionsCount I64)
  (:f eshViolations (List Str))
  (:f vacuousPassViolations (List Str))
  (:f declaredRefusal (Option RefusalReceipt))
  (:f baselineTreeDigest Str)
  (:f reversalExecuted Bool)
  (:f isTurnGrounded Bool))

(schema VerificationResult
  (:f approved Bool)
  (:f reason Str)
  (:f feedback Str))

fn initTurnState -> HarnessTurnState
  (HarnessTurnState :plannedItems (list) :mutatingActionsCount 0 :eshViolations (list) :vacuousPassViolations (list) :declaredRefusal (none) :baselineTreeDigest "" :reversalExecuted false :isTurnGrounded true)

fn isMutatingAction? actionKind: Str -> Bool
  (or (= actionKind "write_to_file") (or (= actionKind "replace_file_content") (or (= actionKind "apply_patch") (or (= actionKind "execute_bash") (or (= actionKind "run_command") (or (= actionKind "git_commit") (or (= actionKind "delete_file") (or (= actionKind "remove_file") (or (= actionKind "unlink") (or (= actionKind ":edit") (or (= actionKind ":flush") (= actionKind ":patch"))))))))))))

fn isReversalAction? actionKind: Str -> Bool
  (or (= actionKind "ram_vfs_discard") (or (= actionKind "git_revert") (or (= actionKind "git_reset_hard") (or (= actionKind ":discard") (= actionKind "git_checkout_file")))))

fn isAssertionDeletion? diffPayload: Str -> Bool
  (or (stringContains? diffPayload "- assert") (or (stringContains? diffPayload "- assert-form") (or (stringContains? diffPayload "@pytest.mark.skip") (or (stringContains? diffPayload "t.Skip") (or (stringContains? diffPayload "// assert") (stringContains? diffPayload "# assert"))))))

fn auditRefusalPolarity receipt: RefusalReceipt -> Bool
  (and (not (stringEmpty? receipt.grounds)) (and (not (stringEmpty? receipt.charterCitation)) (or (= receipt.refusalKind "hazardousAction") (or (= receipt.refusalKind "passFraudSolicitation") (or (= receipt.refusalKind "securityBreach") (= receipt.refusalKind "untrackedDataLoss"))))))

fn registerRefusal state: HarnessTurnState refusal: RefusalReceipt -> HarnessTurnState
  (with state :declaredRefusal (some refusal) :isTurnGrounded true)

fn registerPlanItem state: HarnessTurnState id: Str desc: Str gateCmd: Str -> HarnessTurnState
  (let [(item (PlanGateItem :id id :description desc :verificationCommand gateCmd :executed false :passed false :exitCode -1 :assertCount 0 :minAssertCount 1 :mutantsKilled 0 :minMutantsKilled 1 :isNonVacuous false :receiptDigest "")) (updatedItems (listAppend state.plannedItems (list item)))] (with state :plannedItems updatedItems :isTurnGrounded true))

fn auditActionPrecondition state: HarnessTurnState actionKind: Str -> VerificationResult
  (if (isReversalAction? actionKind) (VerificationResult :approved true :reason "Reversible rollback action approved unconditionally" :feedback "") (if (not (isMutatingAction? actionKind)) (VerificationResult :approved true :reason "Read-only action allowed without plan" :feedback "") (if (= (listLength state.plannedItems) 0) (VerificationResult :approved false :reason "Plan-before-act invariant violation" :feedback "(:blocked :reason :planRequired :hint \"Declare an incremental plan item with a non-vacuous verification gate before mutating files.\")") (VerificationResult :approved true :reason "Mutating action grounded in registered plan" :feedback ""))))

fn auditActionPreconditionWithReversibility state: HarnessTurnState actionKind: Str targetPath: Str diffPayload: Str -> VerificationResult
  (cond ((isReversalAction? actionKind) (VerificationResult :approved true :reason "Reversible rollback action approved unconditionally" :feedback "")) ((and (stringContains? targetPath "test") (isAssertionDeletion? diffPayload)) (VerificationResult :approved false :reason "Anti-Goodhart violation: Test degradation prohibited under release pressure" :feedback "(:blocked :reason :testDegradationProhibited :hint \"Deleting or weakening assertions is forbidden. Repair the production defect or execute ram_vfs_discard.\")")) (else (auditActionPrecondition state actionKind)))

fn recordGateDetailedExecution state: HarnessTurnState itemId: Str exitCode: I64 assertCount: I64 mutantsKilled: I64 receiptDigest: Str -> HarnessTurnState
  (let [(updatedItems (map (fn [(item PlanGateItem)] -> PlanGateItem (if (= item.id itemId) (let [(passedClean (and (= exitCode 0) (and (>= assertCount item.minAssertCount) (>= mutantsKilled item.minMutantsKilled)))) (isNonVacuous (and (>= assertCount item.minAssertCount) (>= mutantsKilled item.minMutantsKilled)))] (PlanGateItem :id item.id :description item.description :verificationCommand item.verificationCommand :executed true :passed passedClean :exitCode exitCode :assertCount assertCount :minAssertCount item.minAssertCount :mutantsKilled mutantsKilled :minMutantsKilled item.minMutantsKilled :isNonVacuous isNonVacuous :receiptDigest receiptDigest)) item)) state.plannedItems))] (with state :plannedItems updatedItems :mutatingActionsCount (+ state.mutatingActionsCount 1) :isTurnGrounded true))

fn recordGateExecution state: HarnessTurnState itemId: Str exitCode: I64 -> HarnessTurnState
  (recordGateDetailedExecution state itemId exitCode 1 1 "")

fn isTrivialCommand? cmdLine: Str -> Bool
  (or (= cmdLine "true") (or (= cmdLine "echo OK") (or (= cmdLine ":") (= (stringTrim cmdLine) ""))))

fn recordCommandExecution state: HarnessTurnState cmdLine: Str exitCode: I64 -> HarnessTurnState
  (if (isTrivialCommand? cmdLine) state (let [(updatedItems (map (fn [(item PlanGateItem)] -> PlanGateItem (let [(gateCmd item.verificationCommand)] (if (= cmdLine gateCmd) (PlanGateItem :id item.id :description item.description :verificationCommand gateCmd :executed true :passed (and (= exitCode 0) item.isNonVacuous) :exitCode exitCode :assertCount item.assertCount :minAssertCount item.minAssertCount :mutantsKilled item.mutantsKilled :minMutantsKilled item.minMutantsKilled :isNonVacuous item.isNonVacuous :receiptDigest item.receiptDigest) item))) state.plannedItems))] (with state :plannedItems updatedItems :mutatingActionsCount (+ state.mutatingActionsCount 1) :isTurnGrounded true)))

fn validateTurnCompletion state: HarnessTurnState agentClaimSuccess: Bool -> VerificationResult
  (let [(items state.plannedItems) (refusal state.declaredRefusal)] (mt refusal ((some rcp) (if (auditRefusalPolarity rcp) (VerificationResult :approved true :reason (str "Constitutional Refusal Verified: Protected " rcp.charterCitation " against " rcp.refusalKind) :feedback "") (VerificationResult :approved false :reason "Invalid Refusal: Refusal receipt lacks valid constitutional grounds or citation" :feedback "(:blocked :reason :invalidRefusal :hint \"Comply with strategic intent or register valid grounds and charter citation.\")"))) ((none) (if (not agentClaimSuccess) (VerificationResult :approved true :reason "Agent reported failure or incomplete turn" :feedback "") (if (= (listLength items) 0) (if (> state.mutatingActionsCount 0) (VerificationResult :approved false :reason "ESH violation: State mutated without plan or verification gates" :feedback "(:blocked :reason :unplannedMutations :hint \"Mutations occurred without registered plan or gate. Declare plan and run verification.\")") (VerificationResult :approved true :reason "No mutations, read-only completion approved" :feedback "")) (let [(unexecuted (filter (fn [(it PlanGateItem)] -> Bool (not it.executed)) items)) (failedCode (filter (fn [(it PlanGateItem)] -> Bool (and it.executed (not (= it.exitCode 0)))) items)) (vacuousZeroAsserts (filter (fn [(it PlanGateItem)] -> Bool (and it.executed (= it.exitCode 0) (< it.assertCount it.minAssertCount))) items)) (vacuousZeroMutants (filter (fn [(it PlanGateItem)] -> Bool (and it.executed (= it.exitCode 0) (< it.mutantsKilled it.minMutantsKilled))) items))] (cond ((> (listLength unexecuted) 0) (VerificationResult :approved false :reason "ESH violation: Claimed success but verification gate was never executed" :feedback "(:blocked :reason :unexecutedGate :hint \"You cannot claim task completion until all verification commands have executed.\")")) ((> (listLength failedCode) 0) (VerificationResult :approved false :reason "Gate failure: Claimed success but verification gate failed (non-zero exit code)" :feedback "(:blocked :reason :gateFailed :hint \"Inspect runner diagnostic logs and repair implementation.\")")) ((> (listLength vacuousZeroAsserts) 0) (VerificationResult :approved false :reason "Anti-Goodhart violation: Gate passed with exit code 0 but executed zero assertions" :feedback "(:blocked :reason :vacuousPassZeroAsserts :hint \"Vacuous pass rejected. Add non-vacuous assertion sites reaching modified code.\")")) ((> (listLength vacuousZeroMutants) 0) (VerificationResult :approved false :reason "Anti-Goodhart violation: Gate passed but killed zero mutants (unfalsifiable test suite)" :feedback "(:blocked :reason :vacuousPassZeroMutants :hint \"Fault detection requirement unmet. Prove gate falsifiability by killing mutants.\")")) (else (VerificationResult :approved true :reason "Turn verified: All plan items executed, non-zero assertions reached, and gates passed cleanly" :feedback "")))))))))

fn formatVerificationFeedback res: VerificationResult -> Str
  (if res.approved (str "(:verified :status :ok :reason \"" res.reason "\")") (str "(:blocked :reason \"" res.reason "\" :feedback \"" res.feedback "\")"))
