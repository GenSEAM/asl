(module asl-sh/batch-dag-test
  :d "Falsifiable test suite for Batch RPC execution DAG modeling, dependency validation, and fail-fast skip rules."
  :x [run-tests]
  :i [(batch_dag :a dag)])

(df test-step-creation-and-lookup [] -> Bool
  :d "Verifies DAG step creation and positive and negative lookup semantics."
  (let [(s1 (dag/dag-step-create 1 "init" "ping" "" (list)))
        (s2 (dag/dag-step-create 2 "check" "git" "where" (list "init")))
        (steps (list s1 s2))
        (found-ok (dag/dag-find-step steps "init"))
        (found-num (dag/dag-find-step steps "2"))
        (found-missing (dag/dag-find-step steps "missing-name"))]
    (assert (option-is-some? found-ok) "Positive lookup by name must succeed")
    (assert (= (.-op (option-or found-ok s1)) "ping") "Positive lookup by name retrieves correct op")
    (assert (option-is-some? found-num) "Positive lookup by numeric string id must succeed")
    (assert (= (.-subop (option-or found-num s2)) "where") "Positive lookup by numeric string id retrieves correct subop")
    (assert (option-is-none? found-missing) "Negative lookup for nonexistent step must return none")
    (assert (not (option-is-some? found-missing)) "Refutation: missing step cannot be resolved")
    true))

(df test-valid-dependencies [] -> Bool
  :d "Verifies acyclic valid dependency resolution."
  (let [(s1 (dag/dag-step-create 1 "init" "ping" "" (list)))
        (s2 (dag/dag-step-create 2 "work" "status" "" (list "init")))
        (plan (dag/dag-plan-create "seq" (list s1 s2)))
        (checked (dag/dag-validate-deps plan))]
    (assert (.-is-valid checked) "Acyclic valid plan must be marked valid")
    (assert (string-empty? (.-error-msg checked)) "Valid plan must carry empty error message")
    (assert (= (list-length (.-steps checked)) 2) "Validated plan preserves all declared steps")
    true))

(df test-missing-dependency-rejection [] -> Bool
  :d "Verifies rejection of steps with missing dependency references."
  (let [(s1 (dag/dag-step-create 1 "step-a" "ping" "" (list "ghost-dep")))
        (plan (dag/dag-plan-create "par" (list s1)))
        (checked (dag/dag-validate-deps plan))]
    (assert (not (.-is-valid checked)) "Plan with missing dependency must be marked invalid")
    (assert (string-contains? (.-error-msg checked) "Missing dependency reference: ghost-dep") "Error message must cite missing dependency identifier")
    (assert (> (string-length (.-error-msg checked)) 0) "Error message string is non-empty")
    true))

(df test-self-dependency-rejection [] -> Bool
  :d "Verifies rejection of steps that declare self-dependencies."
  (let [(s1 (dag/dag-step-create 1 "step-cyclic" "ping" "" (list "step-cyclic")))
        (plan (dag/dag-plan-create "wave" (list s1)))
        (checked (dag/dag-validate-deps plan))]
    (assert (not (.-is-valid checked)) "Plan with self-dependency cycle must be marked invalid")
    (assert (string-contains? (.-error-msg checked) "Self-dependency detected on step: step-cyclic") "Error message must report self-dependency")
    (assert (= (.-mode checked) "wave") "Execution mode is preserved in invalid plan")
    true))

(df test-sequential-fail-fast-skip [] -> Bool
  :d "Verifies sequential fail-fast execution and propagation of skipped status."
  (let [(s1 (dag/BatchDagStep :id 1 :name "step1" :op "ping" :subop "" :status "ok" :deps (list) :reason ""))
        (s2 (dag/BatchDagStep :id 2 :name "step2" :op "exec" :subop "" :status "error" :deps (list) :reason "exit 1"))
        (s3 (dag/BatchDagStep :id 3 :name "step3" :op "status" :subop "" :status "pending" :deps (list) :reason ""))
        (s4 (dag/BatchDagStep :id 4 :name "step4" :op "read" :subop "" :status "pending" :deps (list) :reason ""))
        (stepped (dag/dag-skip-on-prior-failure (list s1 s2 s3 s4)))
        (r1 (option-or (list-get stepped 0) s1))
        (r2 (option-or (list-get stepped 1) s2))
        (r3 (option-or (list-get stepped 2) s3))
        (r4 (option-or (list-get stepped 3) s4))]
    (assert (= (.-status r1) "ok") "Step 1 prior to error remains ok")
    (assert (= (.-status r2) "error") "Step 2 keeps error status")
    (assert (= (.-status r3) "skipped") "Step 3 is marked skipped after prior error")
    (assert (= (.-reason r3) "aborted-by-prior-error") "Step 3 carries standard fail-fast skip reason")
    (assert (= (.-status r4) "skipped") "Step 4 is marked skipped after prior error")
    (assert (not (= (.-status r3) "pending")) "Negative assertion: Step 3 is no longer pending")
    (assert (not (= (.-status r4) "ok")) "Negative assertion: Step 4 is not ok")
    true))

(df test-wave-cascading-abort [] -> Bool
  :d "Verifies wave execution cascading abort when earlier wave fails."
  (let [(s1 (dag/BatchDagStep :id 10 :name "w2-a" :op "sym" :subop "" :status "pending" :deps (list) :reason ""))
        (s2 (dag/BatchDagStep :id 11 :name "w2-b" :op "find" :subop "" :status "pending" :deps (list) :reason ""))
        (aborted (dag/dag-skip-wave-on-failure true (list s1 s2)))
        (passed (dag/dag-skip-wave-on-failure false (list s1 s2)))
        (a1 (option-or (list-get aborted 0) s1))
        (a2 (option-or (list-get aborted 1) s2))
        (p1 (option-or (list-get passed 0) s1))]
    (assert (= (.-status a1) "skipped") "Step 1 in wave 2 is skipped on wave 1 failure")
    (assert (= (.-reason a1) "aborted-by-prior-wave-failure") "Step 1 carries wave failure reason")
    (assert (= (.-status a2) "skipped") "Step 2 in wave 2 is skipped on wave 1 failure")
    (assert (= (.-status p1) "pending") "Wave 2 steps remain intact when wave 1 succeeds")
    (assert (not (= (.-status a1) "pending")) "Negative assertion: aborted wave step is not pending")
    true))

(df test-batch-summary-formatting [] -> Bool
  :d "Verifies aggregated ASN summary generation."
  (let [(s1 (dag/BatchDagStep :id 1 :name "s1" :op "ping" :subop "" :status "ok" :deps (list) :reason ""))
        (s2 (dag/BatchDagStep :id 2 :name "s2" :op "exec" :subop "" :status "error" :deps (list) :reason ""))
        (s3 (dag/BatchDagStep :id 3 :name "s3" :op "read" :subop "" :status "skipped" :deps (list) :reason ""))
        (summary (dag/dag-format-summary (list s1 s2 s3)))]
    (assert (string-contains? summary ":total 3") "Summary reports total 3")
    (assert (string-contains? summary ":ok 1") "Summary reports ok 1")
    (assert (string-contains? summary ":error 1") "Summary reports error 1")
    (assert (string-contains? summary ":skipped 1") "Summary reports skipped 1")
    (assert (not (string-contains? summary ":total 0")) "Negative assertion: total cannot be 0")
    true))

(df run-tests [] -> Bool
  :d "Executes all batch DAG test functions with dual-case qualification."
  (and (test-step-creation-and-lookup)
       (and (test-valid-dependencies)
            (and (test-missing-dependency-rejection)
                 (and (test-self-dependency-rejection)
                      (and (test-sequential-fail-fast-skip)
                           (and (test-wave-cascading-abort)
                                (test-batch-summary-formatting))))))))
