(module asl-proc/batchDag :x [BatchDagStep BatchDagPlan dagStepCreate dagPlanCreate dagFindStep dagValidateDeps dagSkipOnPriorFailure dagSkipWaveOnFailure dagFormatSummary])

(schema BatchDagStep (:f id Int64) (:f name String) (:f op String) (:f subop String) (:f status String) (:f deps (List String)) (:f reason String))

(schema BatchDagPlan (:f mode String) (:f steps (List BatchDagStep)) (:f isValid Bool) (:f errorMsg String))

fn dagStepCreate id: Int64 name: String op: String subop: String deps: (List String) -> BatchDagStep
  (BatchDagStep :id id :name name :op op :subop subop :status "pending" :deps deps :reason "")

fn dagPlanCreate mode: String steps: (List BatchDagStep) -> BatchDagPlan
  (BatchDagPlan :mode mode :steps steps :isValid true :errorMsg "")

fn dagFindStepLoop steps: (List BatchDagStep) identifier: String idx: Int64 len: Int64 -> (Option BatchDagStep)
  (if (>= idx len) (none) (let [(s (optionOr (listGet steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))] (if (or (= s.name identifier) (= (stringFromInt64 s.id) identifier)) (some s) (dagFindStepLoop steps identifier (+ idx 1) len))))

fn dagFindStep steps: (List BatchDagStep) identifier: String -> (Option BatchDagStep)
  (dagFindStepLoop steps identifier 0 (listLength steps))

fn dagCheckDepsLoop steps: (List BatchDagStep) deps: (List String) stepName: String didx: Int64 dlen: Int64 -> (Option String)
  (if (>= didx dlen) (none) (let [(depId (optionOr (listGet deps didx) ""))] (if (= depId stepName) (some (str "Self-dependency detected on step: " depId)) (let [(found (dagFindStep steps depId))] (if (none? found) (some (str "Missing dependency reference: " depId)) (dagCheckDepsLoop steps deps stepName (+ didx 1) dlen))))))

fn dagValidateStepsLoop plan: BatchDagPlan steps: (List BatchDagStep) idx: Int64 len: Int64 -> BatchDagPlan
  (if (>= idx len) plan (let [(s (optionOr (listGet steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason ""))) (err (dagCheckDepsLoop steps s.deps s.name 0 (listLength s.deps)))] (if (some? err) (with plan :isValid false :errorMsg (optionOr err "")) (dagValidateStepsLoop plan steps (+ idx 1) len))))

fn dagValidateDeps plan: BatchDagPlan -> BatchDagPlan
  (dagValidateStepsLoop plan plan.steps 0 (listLength plan.steps))

fn dagSkipWalk steps: (List BatchDagStep) idx: Int64 len: Int64 failed: Bool acc: (List BatchDagStep) -> (List BatchDagStep)
  (if (>= idx len) acc (let [(s (optionOr (listGet steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason "")))] (if failed (let [(skippedS (BatchDagStep :id s.id :name s.name :op s.op :subop s.subop :status "skipped" :deps s.deps :reason "aborted-by-prior-error"))] (dagSkipWalk steps (+ idx 1) len true (listAppend acc (list skippedS)))) (let [(isErr (= s.status "error"))] (dagSkipWalk steps (+ idx 1) len isErr (listAppend acc (list s)))))))

fn dagSkipOnPriorFailure steps: (List BatchDagStep) -> (List BatchDagStep)
  (dagSkipWalk steps 0 (listLength steps) false (list))

fn dagMarkWaveSkipped steps: (List BatchDagStep) idx: Int64 len: Int64 acc: (List BatchDagStep) -> (List BatchDagStep)
  (if (>= idx len) acc (let [(s (optionOr (listGet steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason ""))) (skippedS (BatchDagStep :id s.id :name s.name :op s.op :subop s.subop :status "skipped" :deps s.deps :reason "aborted-by-prior-wave-failure"))] (dagMarkWaveSkipped steps (+ idx 1) len (listAppend acc (list skippedS)))))

fn dagSkipWaveOnFailure wave1Failed: Bool wave2Steps: (List BatchDagStep) -> (List BatchDagStep)
  (if (not wave1Failed) wave2Steps (dagMarkWaveSkipped wave2Steps 0 (listLength wave2Steps) (list)))

fn dagCountStatus steps: (List BatchDagStep) idx: Int64 len: Int64 okCnt: Int64 errCnt: Int64 skipCnt: Int64 -> String
  (if (>= idx len) (str "(:batch-summary :total " (stringFromInt64 len) " :ok " (stringFromInt64 okCnt) " :error " (stringFromInt64 errCnt) " :skipped " (stringFromInt64 skipCnt) ")") (let [(s (optionOr (listGet steps idx) (BatchDagStep :id 0 :name "" :op "" :subop "" :status "" :deps (list) :reason ""))) (st s.status)] (cond ((= st "ok") (dagCountStatus steps (+ idx 1) len (+ okCnt 1) errCnt skipCnt)) ((= st "error") (dagCountStatus steps (+ idx 1) len okCnt (+ errCnt 1) skipCnt)) ((= st "skipped") (dagCountStatus steps (+ idx 1) len okCnt errCnt (+ skipCnt 1))) (else (dagCountStatus steps (+ idx 1) len okCnt errCnt skipCnt)))))

fn dagFormatSummary steps: (List BatchDagStep) -> String
  (dagCountStatus steps 0 (listLength steps) 0 0 0)
