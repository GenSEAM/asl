(module aslHarness/handoff :x [HandoffBrief CleanAuditEnvelope makeHandoffBrief formatBriefAsn makeCleanAudit formatAuditAsn] :i [])

(schema HandoffBrief (:f taskId Str) (:f lane Str) (:f role Str) (:f temp Float) (:f taskSpec Str) (:f budget Int64))

(schema CleanAuditEnvelope (:f taskId Str) (:f contractCmd Str) (:f candidateLane Str) (:f exitCode Int64) (:f stdout Str) (:f stderr Str) (:f diffSummary Str))

fn makeHandoffBrief taskId: Str lane: Str role: Str temp: Float taskSpec: Str budget: Int64 -> HandoffBrief
  (HandoffBrief :taskId taskId :lane lane :role role :temp temp :taskSpec taskSpec :budget budget)

fn formatBriefAsn brief: HandoffBrief -> Str
  (str "(:brief :task \"" brief.taskId "\" :lane \"" brief.lane "\" :role \"" brief.role "\" :temp " (stringFromFloat64 brief.temp) " :spec \"" brief.taskSpec "\" :budget " (stringFromInt64 brief.budget) ")")

fn makeCleanAudit taskId: Str contractCmd: Str candidateLane: Str exitCode: Int64 stdout: Str stderr: Str diffSummary: Str -> CleanAuditEnvelope
  (CleanAuditEnvelope :taskId taskId :contractCmd contractCmd :candidateLane candidateLane :exitCode exitCode :stdout stdout :stderr stderr :diffSummary diffSummary)

fn formatAuditAsn audit: CleanAuditEnvelope -> Str
  (str "(:audit :task \"" audit.taskId "\" :lane \"" audit.candidateLane "\" :spec \"" audit.contractCmd "\" :receipt \"exit=" (stringFromInt64 audit.exitCode) " out=" audit.stdout " err=" audit.stderr "\" :diff \"" audit.diffSummary "\" :pass " (if (= audit.exitCode 0) "true" "false") " :fail " (if (= audit.exitCode 0) "false" "true") ")")
