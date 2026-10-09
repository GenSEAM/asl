(module aslAgentCore/promptAudit :x [PromptDef TokenMetric PromptAuditResult BudgetAuditReport auditPromptTokens estimateTokensSimple validatePromptBudget auditRegistryString auditPromptBudgets] :i [])

(schema PromptDef (:f id Str) (:f role Str) (:f budgetTokens I64) (:f system Str) (:f template Str))

(schema TokenMetric (:f estimatedTokens I64) (:f budgetTokens I64) (:f headroom I64) (:f overBudget Bool))

(schema PromptAuditResult (:f promptId Str) (:f metric TokenMetric) (:f status Str))

fn estimateTokensSimple text: Str -> I64
  (let [(len (stringLength text))] (if (<= len 0) 0 (let [(q (/ len 4))] (if (< q 1) 1 q))))

fn auditPromptTokens prompt: PromptDef -> (Result TokenMetric Str)
  (let [(sysTok (estimateTokensSimple prompt.system)) (tplTok (estimateTokensSimple prompt.template)) (totalTok (+ sysTok tplTok)) (budget prompt.budgetTokens) (headroom (- budget totalTok)) (overBudget (> totalTok budget)) (metric (TokenMetric :estimatedTokens totalTok :budgetTokens budget :headroom headroom :overBudget overBudget))] (ok metric))

(schema BudgetAuditReport (:f promptId Str) (:f staticTokens I64) (:f staticBudget I64) (:f staticHeadroom I64) (:f payloadTokens I64) (:f payloadBudget I64) (:f payloadHeadroom I64) (:f valid Bool) (:f errorCode Str))

fn auditPromptBudgets promptId: Str systemStr: Str payloadStr: Str staticBudget: I64 payloadBudget: I64 -> BudgetAuditReport
  (let [(sTok (estimateTokensSimple systemStr)) (pTok (estimateTokensSimple payloadStr)) (sHeadroom (- staticBudget sTok)) (pHeadroom (- payloadBudget pTok)) (sOverflow (< sHeadroom 0)) (pOverflow (< pHeadroom 0)) (err (if sOverflow "STATIC_PREFIX_OVERFLOW" (if pOverflow "PAYLOAD_BUDGET_OVERFLOW" ""))) (isValid (and (not sOverflow) (not pOverflow)))] (BudgetAuditReport :promptId promptId :staticTokens sTok :staticBudget staticBudget :staticHeadroom sHeadroom :payloadTokens pTok :payloadBudget payloadBudget :payloadHeadroom pHeadroom :valid isValid :errorCode err))

fn validatePromptBudget prompt: PromptDef -> Bool
  (let [(res (auditPromptTokens prompt))] (mt res ((ok m) (not m.overBudget)) ((err _) false)))

fn extractFieldStr block: Str key: Str -> Str
  (let [(needle (str key " \"")) (idxOpt (stringIndexOf block needle))] (mt idxOpt ((some startIdx) (let [(valStart (+ startIdx (stringLength needle))) (tailStr (optionOr (stringSlice block valStart (stringLength block)) "")) (quoteOpt (stringIndexOf tailStr "\""))] (mt quoteOpt ((some endIdx) (optionOr (stringSlice tailStr 0 endIdx) "")) ((none) "")))) ((none) "")))

fn extractFieldInt block: Str key: Str -> I64
  (let [(needle (str key " ")) (idxOpt (stringIndexOf block needle))] (mt idxOpt ((some startIdx) (let [(valStart (+ startIdx (stringLength needle))) (tailStr (optionOr (stringSlice block valStart (stringLength block)) "")) (chars (stringChars tailStr)) (digitsStr (fold (fn [(acc Str) (c Str)] -> Str (if (and (stringContains? "0123456789" c) (not (stringContains? acc " "))) (str acc c) (if (stringEmpty? acc) (if (or (= c " ") (or (= c "\n") (= c "\t"))) "" acc) (str acc " ")))) "" chars)) (cleanDigits (optionOr (listHead (stringSplit digitsStr " ")) ""))] (optionOr (stringToInt64 cleanDigits) 0))) ((none) 0)))

fn auditRegistryString registryContent: Str -> (Result (List PromptAuditResult) Str)
  (let [(blocks (stringSplit registryContent "(:prompt")) (promptBlocks (optionOr (listTail blocks) (list))) (results (fold (fn [(acc (List PromptAuditResult)) (blk Str)] -> (List PromptAuditResult) (let [(id (extractFieldStr blk ":id")) (role (extractFieldStr blk ":role")) (budget (extractFieldInt blk ":budget-tokens")) (system (extractFieldStr blk ":system")) (template (extractFieldStr blk ":template"))] (if (stringEmpty? id) acc (let [(pdef (PromptDef :id id :role role :budgetTokens budget :system system :template template)) (auditRes (auditPromptTokens pdef))] (mt auditRes ((ok metric) (let [(status (if metric.overBudget "budget_exceeded" "pass")) (res (PromptAuditResult :promptId id :metric metric :status status))] (listAppend acc (list res)))) ((err _) acc)))))) (list) promptBlocks))] (if (listEmpty? results) (err "No prompt definitions found in registry") (ok results)))
