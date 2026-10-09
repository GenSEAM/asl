(module aslHarness/terminalBenchEval :x [EvalTask makeEvalTask categorizeTbTask formatEvalReport formatSubmissionSummary] :i [])

(schema EvalTask (:f id Str) (:f category Str) (:f name Str) (:f desc Str))

fn makeEvalTask id: Str category: Str name: Str desc: Str -> EvalTask
  (EvalTask :id id :category category :name name :desc desc)

fn categorizeTbTask id: Str -> Str
  (let [(numStr (if (stringStartsWith? id "TB4-") (optionOr (stringSlice id 4 (stringLength id)) "") (if (stringStartsWith? id "TB-") (optionOr (stringSlice id 3 (stringLength id)) "") id)))] (mt (stringToInt64 numStr) ((some n) (cond ((<= n 12) "subshell-isolation") ((<= n 24) "cross-compile") ((<= n 36) "context-resilience") ((<= n 48) "ast-refactor") ((<= n 60) "env-bootstrap") ((<= n 70) "stream-pipeline") ((<= n 80) "system-net") ((<= n 90) "git-vcs") ((<= n 100) "build-packaging") ((<= n 110) "sec-permissions") ((<= n 150) "proc-analytics") (true "general"))) ((none) "general")))

fn formatEvalReport passed: I64 total: I64 -> Str
  (let [(failed (- total passed)) (ratePct (if (= total 0) "0.0%" (if (= passed total) "100.0%" (str (stringFromInt64 (/ (* passed 100) total)) "%")))) (statusKw (if (= passed total) ":verified" ":incomplete"))] (str "(:terminal-bench-eval" " :total-tasks " (stringFromInt64 total) " :passed-tasks " (stringFromInt64 passed) " :failed-tasks " (stringFromInt64 failed) " :pass-rate-pct " "\"" ratePct "\"" " :status " statusKw ")"))

fn formatSubmissionSummary benchmark: Str model: Str passed: I64 total: I64 jobId: Str -> Str
  (let [(failed (- total passed)) (ratePct (if (= total 0) "0.0%" (str (stringFromInt64 (/ (* passed 100) total)) "%")))] (str "(:terminal-bench-submission" " :benchmark \"" benchmark "\"" " :model \"" model "\"" " :job-id \"" jobId "\"" " :total " (stringFromInt64 total) " :passed " (stringFromInt64 passed) " :failed " (stringFromInt64 failed) " :pass-rate \"" ratePct "\"" ")"))
