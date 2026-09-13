(module asl-sh/batchDag
  :d "Batch RPC execution DAG engine, dependency topological ordering, and fail-fast skip rules."
  :x [BatchDagStep
      BatchDagPlan
      dagStepCreate
      dagPlanCreate
      dagFindStep
      dagValidateDeps
      dagSkipOnPriorFailure
      dagSkipWaveOnFailure
      dagFormatSummary])

(dfs BatchDagStep
  (:f id Int64 "Numeric step identifier")
  (:f name String "Optional logical step name or tag")
  (:f op String "Primary RPC operation name")
  (:f subop String "Secondary suboperation name")
  (:f status String "Execution status: pending, ok, error, skipped")
  (:f deps (List String) "List of step names or IDs this step depends on")
  (:f reason String "Skip reason or failure diagnostic"))

(dfs BatchDagPlan
  (:f mode String "Execution mode: flat, par, seq, wave")
  (:f steps (List BatchDagStep) "List of DAG steps in declared order")
  (:f isValid Bool "Flag indicating whether dependency graph is valid and acyclic")
  (:f errorMsg String "Validation error message if invalid"))

(df dagStepCreate [(id Int64) (name String) (op String) (subop String) (deps (List String))] -> BatchDagStep
  :d "Constructs a new pending BatchDagStep with initialized empty skip reason."
  (BatchDagStep
    :id id
    :name name
    :op op
    :subop subop
    :status "pending"
    :deps deps
    :reason ""))

(df dagPlanCreate [(mode String) (steps (List BatchDagStep))] -> BatchDagPlan
  :d "Constructs a BatchDagPlan from mode and step list."
  (BatchDagPlan
    :mode mode
    :steps steps
    :isValid true
    :errorMsg ""))

(df dagFindStepLoop [(steps (List BatchDagStep)) (identifier String) (idx Int64) (len Int64)] -> (Option BatchDagStep)
  :d "Internal recursion helper for searching step by name or stringified id."
  (if (>= idx len)
      (none)
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))]
        (if (or (= (.-name s) identifier)
                (= (int-to-string (.-id s)) identifier))
            (some s)
            (dagFindStepLoop steps identifier (+ idx 1) len)))))

(df dagFindStep [(steps (List BatchDagStep)) (identifier String)] -> (Option BatchDagStep)
  :d "Searches step list by logical name or stringified numeric ID."
  (dagFindStepLoop steps identifier 0 (list-length steps)))

(df dagCheckDepsLoop [(steps (List BatchDagStep)) (deps (List String)) (stepName String) (didx Int64) (dlen Int64)] -> (Option String)
  :d "Recursion helper validating dependency list for a single step."
  (if (>= didx dlen)
      (none)
      (let [(depId (option-or (list-get deps didx) ""))]
        (if (= depId stepName)
            (some (str "Self-dependency detected on step: " depId))
            (let [(found (dagFindStep steps depId))]
              (if (is-none? found)
                  (some (str "Missing dependency reference: " depId))
                  (dagCheckDepsLoop steps deps stepName (+ didx 1) dlen)))))))

(df dagValidateStepsLoop [(plan BatchDagPlan) (steps (List BatchDagStep)) (idx Int64) (len Int64)] -> BatchDagPlan
  :d "Recursion helper iterating over all steps to validate dependencies."
  (if (>= idx len)
      plan
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))
            (err (dagCheckDepsLoop steps (.-deps s) (.-name s) 0 (list-length (.-deps s))))]
        (if (is-some? err)
            (BatchDagPlan
              :mode (.-mode plan)
              :steps (.-steps plan)
              :isValid false
              :errorMsg (option-or err ""))
            (dagValidateStepsLoop plan steps (+ idx 1) len)))))

(df dagValidateDeps [(plan BatchDagPlan)] -> BatchDagPlan
  :d "Validates that all declared dependencies exist in the step registry."
  (dagValidateStepsLoop plan (.-steps plan) 0 (list-length (.-steps plan))))

(df dagSkipWalk [(steps (List BatchDagStep)) (idx Int64) (len Int64) (failed Bool) (acc (List BatchDagStep))] -> (List BatchDagStep)
  :d "Recursion helper executing sequential fail-fast walk."
  (if (>= idx len)
      acc
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))]
        (if failed
            (let [(skippedS (BatchDagStep
                               :id (.-id s)
                               :name (.-name s)
                               :op (.-op s)
                               :subop (.-subop s)
                               :status "skipped"
                               :deps (.-deps s)
                               :reason "aborted-by-prior-error"))]
              (dagSkipWalk steps (+ idx 1) len true (list-append acc (list skippedS))))
            (let [(isErr (= (.-status s) "error"))]
              (dagSkipWalk steps (+ idx 1) len isErr (list-append acc (list s))))))))

(df dagSkipOnPriorFailure [(steps (List BatchDagStep))] -> (List BatchDagStep)
  :d "Executes sequential fail-fast semantics: once a step fails with status error, subsequent steps become skipped."
  (dagSkipWalk steps 0 (list-length steps) false (list)))

(df dagMarkWaveSkipped [(steps (List BatchDagStep)) (idx Int64) (len Int64) (acc (List BatchDagStep))] -> (List BatchDagStep)
  :d "Recursion helper marking all wave steps as skipped."
  (if (>= idx len)
      acc
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))
            (skippedS (BatchDagStep
                         :id (.-id s)
                         :name (.-name s)
                         :op (.-op s)
                         :subop (.-subop s)
                         :status "skipped"
                         :deps (.-deps s)
                         :reason "aborted-by-prior-wave-failure"))]
        (dagMarkWaveSkipped steps (+ idx 1) len (list-append acc (list skippedS))))))

(df dagSkipWaveOnFailure [(wave1Failed Bool) (wave2Steps (List BatchDagStep))] -> (List BatchDagStep)
  :d "Executes wave cascading abort semantics: if prior wave had errors, all steps in current wave are marked skipped."
  (if (not wave1Failed)
      wave2Steps
      (dagMarkWaveSkipped wave2Steps 0 (list-length wave2Steps) (list))))

(df dagCountStatus [(steps (List BatchDagStep)) (idx Int64) (len Int64) (okCnt Int64) (errCnt Int64) (skipCnt Int64)] -> String
  :d "Recursion helper counting step statuses and formatting ASN summary."
  (if (>= idx len)
      (str "(:batch-summary :total " (int-to-string len)
           " :ok " (int-to-string okCnt)
           " :error " (int-to-string errCnt)
           " :skipped " (int-to-string skipCnt) ")")
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))
            (st (.-status s))]
        (cond
          ((= st "ok") (dagCountStatus steps (+ idx 1) len (+ okCnt 1) errCnt skipCnt))
          ((= st "error") (dagCountStatus steps (+ idx 1) len okCnt (+ errCnt 1) skipCnt))
          ((= st "skipped") (dagCountStatus steps (+ idx 1) len okCnt errCnt (+ skipCnt 1)))
          (:else (dagCountStatus steps (+ idx 1) len okCnt errCnt skipCnt))))))

(df dagFormatSummary [(steps (List BatchDagStep))] -> String
  :d "Formats an ASN string summarizing the batch results count."
  (dagCountStatus steps 0 (list-length steps) 0 0 0))
