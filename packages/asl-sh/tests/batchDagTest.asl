(module asl-sh/batchDagTest
  :d "Falsifiable test suite for Batch RPC execution DAG modeling, dependency validation, and fail-fast skip rules."
  :x [runTests]
  :i [(batch_dag :a dag)])

(df testStepCreationAndLookup [] -> Bool
  :d "Verifies DAG step creation and positive and negative lookup semantics."
  (let [(s1 (dag/dagStepCreate 1 "init" "ping" "" (list)))
        (s2 (dag/dagStepCreate 2 "check" "git" "where" (list "init")))
        (steps (list s1 s2))
        (foundOk (dag/dagFindStep steps "init"))
        (foundNum (dag/dagFindStep steps "2"))
        (foundMissing (dag/dagFindStep steps "missing-name"))]
    (assert (is-some? foundOk) "Positive lookup by name must succeed")
    (assert (= (.-op (option-or foundOk s1)) "ping") "Positive lookup by name retrieves correct op")
    (assert (is-some? foundNum) "Positive lookup by numeric string id must succeed")
    (assert (= (.-subop (option-or foundNum s2)) "where") "Positive lookup by numeric string id retrieves correct subop")
    (assert (is-none? foundMissing) "Negative lookup for nonexistent step must return none")
    (refute (is-some? foundMissing) "Refutation: missing step cannot be resolved")
    true))

(df testValidDependencies [] -> Bool
  :d "Verifies acyclic valid dependency resolution."
  (let [(s1 (dag/dagStepCreate 1 "init" "ping" "" (list)))
        (s2 (dag/dagStepCreate 2 "work" "status" "" (list "init")))
        (plan (dag/dagPlanCreate "seq" (list s1 s2)))
        (checked (dag/dagValidateDeps plan))]
    (assert (.-isValid checked) "Acyclic valid plan must be marked valid")
    (assert (string-empty? (.-errorMsg checked)) "Valid plan must carry empty error message")
    (assert (= (list-length (.-steps checked)) 2) "Validated plan preserves all declared steps")
    true))

(df testMissingDependencyRejection [] -> Bool
  :d "Verifies rejection of steps with missing dependency references."
  (let [(s1 (dag/dagStepCreate 1 "step-a" "ping" "" (list "ghost-dep")))
        (plan (dag/dagPlanCreate "par" (list s1)))
        (checked (dag/dagValidateDeps plan))]
    (refute (.-isValid checked) "Plan with missing dependency must be marked invalid")
    (assert (string-contains? (.-errorMsg checked) "Missing dependency reference: ghost-dep") "Error message must cite missing dependency identifier")
    (assert (> (string-length (.-errorMsg checked)) 0) "Error message string is non-empty")
    true))

(df testSelfDependencyRejection [] -> Bool
  :d "Verifies rejection of steps that declare self-dependencies."
  (let [(s1 (dag/dagStepCreate 1 "step-cyclic" "ping" "" (list "step-cyclic")))
        (plan (dag/dagPlanCreate "wave" (list s1)))
        (checked (dag/dagValidateDeps plan))]
    (refute (.-isValid checked) "Plan with self-dependency cycle must be marked invalid")
    (assert (string-contains? (.-errorMsg checked) "Self-dependency detected on step: step-cyclic") "Error message must report self-dependency")
    (assert (= (.-mode checked) "wave") "Execution mode is preserved in invalid plan")
    true))

(df testSequentialFailFastSkip [] -> Bool
  :d "Verifies sequential fail-fast execution and propagation of skipped status."
  (let [(s1 (dag/BatchDagStep :id 1 :name "step1" :op "ping" :subop "" :status "ok" :deps (list) :reason ""))
        (s2 (dag/BatchDagStep :id 2 :name "step2" :op "exec" :subop "" :status "error" :deps (list) :reason "exit 1"))
        (s3 (dag/BatchDagStep :id 3 :name "step3" :op "status" :subop "" :status "pending" :deps (list) :reason ""))
        (s4 (dag/BatchDagStep :id 4 :name "step4" :op "read" :subop "" :status "pending" :deps (list) :reason ""))
        (stepped (dag/dagSkipOnPriorFailure (list s1 s2 s3 s4)))
        (r1 (option-or (list-get stepped 0) s1))
        (r2 (option-or (list-get stepped 1) s2))
        (r3 (option-or (list-get stepped 2) s3))
        (r4 (option-or (list-get stepped 3) s4))]
    (assert (= (.-status r1) "ok") "Step 1 prior to error remains ok")
    (assert (= (.-status r2) "error") "Step 2 keeps error status")
    (assert (= (.-status r3) "skipped") "Step 3 is marked skipped after prior error")
    (assert (= (.-reason r3) "aborted-by-prior-error") "Step 3 carries standard fail-fast skip reason")
    (assert (= (.-status r4) "skipped") "Step 4 is marked skipped after prior error")
    (refute (= (.-status r3) "pending") "Negative assertion: Step 3 is no longer pending")
    (refute (= (.-status r4) "ok") "Negative assertion: Step 4 is not ok")
    true))

(df testWaveCascadingAbort [] -> Bool
  :d "Verifies wave execution cascading abort when earlier wave fails."
  (let [(s1 (dag/BatchDagStep :id 10 :name "w2-a" :op "sym" :subop "" :status "pending" :deps (list) :reason ""))
        (s2 (dag/BatchDagStep :id 11 :name "w2-b" :op "find" :subop "" :status "pending" :deps (list) :reason ""))
        (aborted (dag/dagSkipWaveOnFailure true (list s1 s2)))
        (passed (dag/dagSkipWaveOnFailure false (list s1 s2)))
        (a1 (option-or (list-get aborted 0) s1))
        (a2 (option-or (list-get aborted 1) s2))
        (p1 (option-or (list-get passed 0) s1))]
    (assert (= (.-status a1) "skipped") "Step 1 in wave 2 is skipped on wave 1 failure")
    (assert (= (.-reason a1) "aborted-by-prior-wave-failure") "Step 1 carries wave failure reason")
    (assert (= (.-status a2) "skipped") "Step 2 in wave 2 is skipped on wave 1 failure")
    (assert (= (.-status p1) "pending") "Wave 2 steps remain intact when wave 1 succeeds")
    (refute (= (.-status a1) "pending") "Negative assertion: aborted wave step is not pending")
    true))

(df testBatchSummaryFormatting [] -> Bool
  :d "Verifies aggregated ASN summary generation."
  (let [(s1 (dag/BatchDagStep :id 1 :name "s1" :op "ping" :subop "" :status "ok" :deps (list) :reason ""))
        (s2 (dag/BatchDagStep :id 2 :name "s2" :op "exec" :subop "" :status "error" :deps (list) :reason ""))
        (s3 (dag/BatchDagStep :id 3 :name "s3" :op "read" :subop "" :status "skipped" :deps (list) :reason ""))
        (summary (dag/dagFormatSummary (list s1 s2 s3)))]
    (assert (string-contains? summary ":total 3") "Summary reports total 3")
    (assert (string-contains? summary ":ok 1") "Summary reports ok 1")
    (assert (string-contains? summary ":error 1") "Summary reports error 1")
    (assert (string-contains? summary ":skipped 1") "Summary reports skipped 1")
    (refute (string-contains? summary ":total 0") "Negative assertion: total cannot be 0")
    true))

(df runTests [] -> Bool
  :d "Executes all batch DAG test functions with dual-case qualification."
  (and (testStepCreationAndLookup)
       (and (testValidDependencies)
            (and (testMissingDependencyRejection)
                 (and (testSelfDependencyRejection)
                      (and (testSequentialFailFastSkip)
                           (and (testWaveCascadingAbort)
                                (testBatchSummaryFormatting))))))))
