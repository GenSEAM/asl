(module asl-sh/batch-dag
  :d "Batch RPC execution DAG engine, dependency topological ordering, and fail-fast skip rules."
  :x [BatchDagStep
      BatchDagPlan
      dag-step-create
      dag-plan-create
      dag-find-step
      dag-validate-deps
      dag-skip-on-prior-failure
      dag-skip-wave-on-failure
      dag-format-summary])

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
  (:f is-valid Bool "Flag indicating whether dependency graph is valid and acyclic")
  (:f error-msg String "Validation error message if invalid"))

(df dag-step-create [(id Int64) (name String) (op String) (subop String) (deps (List String))] -> BatchDagStep
  :d "Constructs a new pending BatchDagStep with initialized empty skip reason."
  (BatchDagStep
    :id id
    :name name
    :op op
    :subop subop
    :status "pending"
    :deps deps
    :reason ""))

(df dag-plan-create [(mode String) (steps (List BatchDagStep))] -> BatchDagPlan
  :d "Constructs a BatchDagPlan from mode and step list."
  (BatchDagPlan
    :mode mode
    :steps steps
    :is-valid true
    :error-msg ""))

(df dag-find-step-loop [(steps (List BatchDagStep)) (identifier String) (idx Int64) (len Int64)] -> (Option BatchDagStep)
  :d "Internal recursion helper for searching step by name or stringified id."
  (if (>= idx len)
      (none)
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))]
        (if (or (= (.-name s) identifier)
                (= (int-to-string (.-id s)) identifier))
            (some s)
            (dag-find-step-loop steps identifier (+ idx 1) len)))))

(df dag-find-step [(steps (List BatchDagStep)) (identifier String)] -> (Option BatchDagStep)
  :d "Searches step list by logical name or stringified numeric ID."
  (dag-find-step-loop steps identifier 0 (list-length steps)))

(df dag-check-deps-loop [(steps (List BatchDagStep)) (deps (List String)) (step-name String) (didx Int64) (dlen Int64)] -> (Option String)
  :d "Recursion helper validating dependency list for a single step."
  (if (>= didx dlen)
      (none)
      (let [(dep-id (option-or (list-get deps didx) ""))]
        (if (= dep-id step-name)
            (some (str "Self-dependency detected on step: " dep-id))
            (let [(found (dag-find-step steps dep-id))]
              (if (option-is-none? found)
                  (some (str "Missing dependency reference: " dep-id))
                  (dag-check-deps-loop steps deps step-name (+ didx 1) dlen)))))))

(df dag-validate-steps-loop [(plan BatchDagPlan) (steps (List BatchDagStep)) (idx Int64) (len Int64)] -> BatchDagPlan
  :d "Recursion helper iterating over all steps to validate dependencies."
  (if (>= idx len)
      plan
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))
            (err (dag-check-deps-loop steps (.-deps s) (.-name s) 0 (list-length (.-deps s))))]
        (if (option-is-some? err)
            (BatchDagPlan
              :mode (.-mode plan)
              :steps (.-steps plan)
              :is-valid false
              :error-msg (option-or err ""))
            (dag-validate-steps-loop plan steps (+ idx 1) len)))))

(df dag-validate-deps [(plan BatchDagPlan)] -> BatchDagPlan
  :d "Validates that all declared dependencies exist in the step registry."
  (dag-validate-steps-loop plan (.-steps plan) 0 (list-length (.-steps plan))))

(df dag-skip-walk [(steps (List BatchDagStep)) (idx Int64) (len Int64) (failed Bool) (acc (List BatchDagStep))] -> (List BatchDagStep)
  :d "Recursion helper executing sequential fail-fast walk."
  (if (>= idx len)
      acc
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))]
        (if failed
            (let [(skipped-s (BatchDagStep
                               :id (.-id s)
                               :name (.-name s)
                               :op (.-op s)
                               :subop (.-subop s)
                               :status "skipped"
                               :deps (.-deps s)
                               :reason "aborted-by-prior-error"))]
              (dag-skip-walk steps (+ idx 1) len true (list-append acc (list skipped-s))))
            (let [(is-err (= (.-status s) "error"))]
              (dag-skip-walk steps (+ idx 1) len is-err (list-append acc (list s))))))))

(df dag-skip-on-prior-failure [(steps (List BatchDagStep))] -> (List BatchDagStep)
  :d "Executes sequential fail-fast semantics: once a step fails with status error, subsequent steps become skipped."
  (dag-skip-walk steps 0 (list-length steps) false (list)))

(df dag-mark-wave-skipped [(steps (List BatchDagStep)) (idx Int64) (len Int64) (acc (List BatchDagStep))] -> (List BatchDagStep)
  :d "Recursion helper marking all wave steps as skipped."
  (if (>= idx len)
      acc
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))
            (skipped-s (BatchDagStep
                         :id (.-id s)
                         :name (.-name s)
                         :op (.-op s)
                         :subop (.-subop s)
                         :status "skipped"
                         :deps (.-deps s)
                         :reason "aborted-by-prior-wave-failure"))]
        (dag-mark-wave-skipped steps (+ idx 1) len (list-append acc (list skipped-s))))))

(df dag-skip-wave-on-failure [(wave1-failed Bool) (wave2-steps (List BatchDagStep))] -> (List BatchDagStep)
  :d "Executes wave cascading abort semantics: if prior wave had errors, all steps in current wave are marked skipped."
  (if (not wave1-failed)
      wave2-steps
      (dag-mark-wave-skipped wave2-steps 0 (list-length wave2-steps) (list))))

(df dag-count-status [(steps (List BatchDagStep)) (idx Int64) (len Int64) (ok-cnt Int64) (err-cnt Int64) (skip-cnt Int64)] -> String
  :d "Recursion helper counting step statuses and formatting ASN summary."
  (if (>= idx len)
      (str "(:batch-summary :total " (int-to-string len)
           " :ok " (int-to-string ok-cnt)
           " :error " (int-to-string err-cnt)
           " :skipped " (int-to-string skip-cnt) ")")
      (let [(s (option-or (list-get steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))
            (st (.-status s))]
        (cond
          ((= st "ok") (dag-count-status steps (+ idx 1) len (+ ok-cnt 1) err-cnt skip-cnt))
          ((= st "error") (dag-count-status steps (+ idx 1) len ok-cnt (+ err-cnt 1) skip-cnt))
          ((= st "skipped") (dag-count-status steps (+ idx 1) len ok-cnt err-cnt (+ skip-cnt 1)))
          (:else (dag-count-status steps (+ idx 1) len ok-cnt err-cnt skip-cnt))))))

(df dag-format-summary [(steps (List BatchDagStep))] -> String
  :d "Formats an ASN string summarizing the batch results count."
  (dag-count-status steps 0 (list-length steps) 0 0 0))
