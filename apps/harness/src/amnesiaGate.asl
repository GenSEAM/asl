(module aslHarness/amnesiaGate :x [OverflowContext AmnesiaInterceptResult AmnesiaAuditReport errAmnesiaDataLoss emulateContextOverflow interceptAmnesiaTrigger verifyFactsRetained runAmnesiaAudit] :i [])

fn errAmnesiaDataLoss -> Str
  "ERR_AMNESIA_DATA_LOSS"

(schema OverflowContext (:f bufferId Str) (:f tokens I64) (:f messages (List Str)) (:f facts (List Str)) (:f threshold I64))

(schema AmnesiaInterceptResult (:f triggered Bool) (:f chunkId Str) (:f postTokens I64) (:f facts (List Str)) (:f rawEvicted Bool))

(schema AmnesiaAuditReport (:f passed Bool) (:f inputTokens I64) (:f postTokens I64) (:f factsVerified I64) (:f missingFacts (List Str)) (:f errorCode Str))

fn emulateContextOverflow id: Str inputTokens: I64 threshold: I64 requiredFacts: (List Str) -> OverflowContext
  (let [(factMsgs (map (fn [(f Str)] -> Str (str "[fact] " f)) requiredFacts)) (baseMsgs (list (str "[init] buffer " id " with " (stringFromInt64 inputTokens) " tokens") (str "[op] conversation backlog simulating task context for " id))) (allMsgs (listAppend baseMsgs factMsgs))] (OverflowContext :bufferId id :tokens inputTokens :messages allMsgs :facts requiredFacts :threshold threshold))

fn interceptAmnesiaTrigger ctx: OverflowContext -> AmnesiaInterceptResult
  (if (>= ctx.tokens ctx.threshold) (let [(cId (str "chunk-" ctx.bufferId "-compact")) (postTokens 1200) (facts ctx.facts)] (AmnesiaInterceptResult :triggered true :chunkId cId :postTokens postTokens :facts facts :rawEvicted true)) (AmnesiaInterceptResult :triggered false :chunkId "" :postTokens ctx.tokens :facts ctx.facts :rawEvicted false))

fn factMatches? req: Str retained: (List Str) -> Bool
  (let [(matches (filter (fn [(ret Str)] -> Bool (or (= req ret) (or (stringContains? ret req) (stringContains? req ret)))) retained))] (not (listEmpty? matches)))

fn verifyFactsRetained requiredFacts: (List Str) retainedFacts: (List Str) -> (Pair Bool Str)
  (if (listEmpty? requiredFacts) (pair true "") (let [(missing (filter (fn [(req Str)] -> Bool (not (factMatches? req retainedFacts))) requiredFacts))] (if (listEmpty? missing) (pair true "") (pair false (errAmnesiaDataLoss)))))

fn runAmnesiaAudit testId: Str inputTokens: I64 threshold: I64 requiredFacts: (List Str) -> AmnesiaAuditReport
  (let [(ctx (emulateContextOverflow testId inputTokens threshold requiredFacts)) (trig (interceptAmnesiaTrigger ctx))] (if (not trig.triggered) (AmnesiaAuditReport :passed false :inputTokens inputTokens :postTokens ctx.tokens :factsVerified 0 :missingFacts requiredFacts :errorCode "ERR_NO_AMNESIA_TRIGGER") (let [(factCheck (verifyFactsRetained requiredFacts trig.facts)) (isOk (pairFirst factCheck)) (err (pairSecond factCheck))] (if isOk (AmnesiaAuditReport :passed true :inputTokens inputTokens :postTokens trig.postTokens :factsVerified (listLength requiredFacts) :missingFacts (list) :errorCode "") (let [(missing (filter (fn [(req Str)] -> Bool (not (factMatches? req trig.facts))) requiredFacts))] (AmnesiaAuditReport :passed false :inputTokens inputTokens :postTokens trig.postTokens :factsVerified (- (listLength requiredFacts) (listLength missing)) :missingFacts missing :errorCode err))))))
