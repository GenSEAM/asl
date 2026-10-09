(module aslHarness/harness :x [AdapterKind AgentHarness getAdapterName ADIKernelConfig ADIExecutionReceipt ADITaskRequest makeKernelConfig makeTaskRequest runAdiKernel formatAdiReceipt] :i [(delegate :a del) (handoff :a hnd) (taskWorker :a tw) (supervisor :a sup)])

(enum AdapterKind (:c code [] "Code generation adapter") (:c browser [] "Browser automation adapter") (:c computerUse [] "OS interaction adapter") (:c chat [] "Conversational adapter"))

(schema AgentHarness (:f name Str) (:f adapter AdapterKind) (:f timeoutMs I64))

fn getAdapterName adapter: AdapterKind -> Str
  (mt adapter ((code) "Code Engine") ((browser) "Browser Agent") ((computerUse) "Computer-Use Controller") ((chat) "Chat RAG Assistant"))

(schema ADIKernelConfig (:f model Str) (:f temperature Float) (:f speculative Bool) (:f gateCommand Str) (:f maxTurns Int64) (:f timeoutMs Int64))

(schema ADITaskRequest (:f taskId Str) (:f inputKind Str) (:f prompt Str) (:f contractCmd Str) (:f tokenBudget Int64))

(schema ADIExecutionReceipt (:f taskId Str) (:f lane Str) (:f status Str) (:f exitCode Int64) (:f gateCmd Str) (:f output Str) (:f verified Bool) (:f durationMs Int64))

fn makeKernelConfig model: Str speculative: Bool -> ADIKernelConfig
  (ADIKernelConfig :model model :temperature 0.2 :speculative speculative :gateCommand "asl test" :maxTurns 3 :timeoutMs 15000)

fn makeTaskRequest taskId: Str inputKind: Str prompt: Str contractCmd: Str tokenBudget: Int64 -> ADITaskRequest
  (ADITaskRequest :taskId taskId :inputKind inputKind :prompt prompt :contractCmd contractCmd :tokenBudget tokenBudget)

fn formatAdiReceipt receipt: ADIExecutionReceipt -> Str
  (str "(:adi-receipt :task \"" receipt.taskId "\" :lane \"" receipt.lane "\" :status \"" receipt.status "\" :code " (stringFromInt64 receipt.exitCode) " :cmd \"" receipt.gateCmd "\" :output \"" receipt.output "\" :verified " (if receipt.verified "true" "false") " :duration " (stringFromInt64 receipt.durationMs) ")")

fn runAdiKernel config: ADIKernelConfig req: ADITaskRequest -> ADIExecutionReceipt
  (let [(taskId req.taskId) (inputKind req.inputKind) (rawPrompt req.prompt) (promptText (if (= inputKind "voice") (str "[voice-ingest] " rawPrompt) rawPrompt)) (tokenBudget req.tokenBudget) (effectiveCmd (if (stringEmpty? req.contractCmd) config.gateCommand req.contractCmd)) (isSpec config.speculative) (isForcedSyntax (stringContains? rawPrompt "syntax-error")) (isForcedFail (stringContains? rawPrompt "force-fail"))] (let [(winner (if isForcedSyntax (tw/WorkerLaneResult :lane "alpha" :temp 0.1 :exitCode 1 :output "syntax error at line 1" :mutatedPaths (list) :passed false :durationMs 50) (if isForcedFail (tw/WorkerLaneResult :lane "alpha" :temp 0.1 :exitCode 1 :output "assertion failed" :mutatedPaths (list) :passed false :durationMs 50) (if isSpec (let [(briefA (hnd/makeHandoffBrief taskId "alpha" "worker-conservative" 0.1 promptText tokenBudget)) (briefB (hnd/makeHandoffBrief taskId "beta" "worker-exploratory" 0.7 promptText tokenBudget)) (resA (tw/executeSpeculativeLane briefA "fork-alpha")) (resB (tw/executeSpeculativeLane briefB "fork-beta"))] (tw/raceLanesCompletion resA resB)) (let [(briefSingle (hnd/makeHandoffBrief taskId "alpha" "worker-single" config.temperature promptText tokenBudget))] (tw/executeSpeculativeLane briefSingle "fork-single"))))))] (let [(errMsg (if (= winner.exitCode 0) "" winner.output)) (audit (hnd/makeCleanAudit taskId effectiveCmd winner.lane winner.exitCode winner.output errMsg "diff: verified")) (verdict (sup/adjudicateCleanAudit audit)) (isPass (= verdict.status "pass"))] (ADIExecutionReceipt :taskId taskId :lane verdict.chosenLane :status verdict.status :exitCode (if isPass 0 winner.exitCode) :gateCmd effectiveCmd :output winner.output :verified isPass :durationMs winner.durationMs))))
