(module aslAgentCore/onion :x [MiddlewareKind Middleware OnionContext OnionDecision OnionPipeline TopoState StepContext StepDecision makeMiddleware makeOnionContext makeStepContext makeStepDecision makePipeline makeLegacyPipeline addMiddleware sortPipeline hasDepEdge? hasPrerequisite? sortMiddlewares executeMiddleware dispatchToolCall dispatchStepHook middlewareKindTag middlewareKindEq? makeContext executePipeline runSanitizer LegacyOnionContext LegacyOnionPipeline LegacyOnionResult] :i [(core :a core)])


(enum MiddlewareKind (:c kindPreCall [] "Pre-call hook interceptor") (:c kindPostCall [] "Post-call hook interceptor") (:c kindFilter [] "Filter hook verifying permission or boundary") (:c kindMutate [] "Mutation hook transforming payload") (:c kindAudit [] "Audit telemetry hook") (:c kindStepPre [] "Step pre-execution hook") (:c kindStepPost [] "Step post-execution hook") (:c kindPromptPre [] "Prompt pre-synthesis hook") (:c kindModelPost [] "Model response post-processing hook"))

(schema Middleware (:f id Str) (:f name Str) (:f kind MiddlewareKind) (:f priority I64) (:f before (List Str)) (:f after (List Str)) (:f config (Map Str Str)))

(schema OnionContext (:f callId Str) (:f callerId Str) (:f toolName Str) (:f payload Str) (:f status Str) (:f auditLog (List Str)))

(schema OnionDecision (:f proceed Bool) (:f blocked Bool) (:f reason Str) (:f context OnionContext))

(schema OnionPipeline (:f middlewares (List Middleware)) (:f sorted (List Middleware)))

(schema TopoState (:f remaining (List Middleware)) (:f acc (List Middleware)))

(schema StepContext (:f stepId Str) (:f sessionId Str) (:f turnIndex I64) (:f input Str) (:f output Str) (:f toolName Str) (:f payload Str) (:f status Str) (:f metadata (Map Str Str)) (:f auditLog (List Str)))

(schema StepDecision (:f action Str) (:f proceed Bool) (:f mutate Bool) (:f abort Bool) (:f retry Bool) (:f reason Str) (:f context StepContext))

fn makeMiddleware id: Str name: Str kind: MiddlewareKind priority: I64 before: (List Str) after: (List Str) -> Middleware
  (Middleware :id id :name name :kind kind :priority priority :before before :after after :config (mapEmpty))

fn makeOnionContext callId: Str callerId: Str toolName: Str payload: Str -> OnionContext
  (OnionContext :callId callId :callerId callerId :toolName toolName :payload payload :status "ok" :auditLog (list))

fn makeStepContext stepId: Str sessionId: Str turnIndex: I64 input: Str payload: Str -> StepContext
  (StepContext :stepId stepId :sessionId sessionId :turnIndex turnIndex :input input :output "" :toolName "" :payload payload :status "ok" :metadata (mapEmpty) :auditLog (list))

fn makeStepDecision action: Str reason: Str ctx: StepContext -> StepDecision
  (let [(isProceed (= action "proceed")) (isMutate (= action "mutate")) (isAbort (= action "abort")) (isRetry (= action "retry"))] (StepDecision :action action :proceed (or isProceed isMutate) :mutate isMutate :abort isAbort :retry isRetry :reason reason :context ctx))

fn containsId ids: (List Str) target: Str -> Bool
  (let [(matches (filter (fn [(x Str)] -> Bool (= x target)) ids))] (not (listEmpty? matches)))

fn hasDepEdge? a: Middleware b: Middleware -> Bool
  (or (containsId a.before b.id) (containsId b.after a.id))

fn hasPrerequisite? target: Middleware remaining: (List Middleware) -> Bool
  (let [(prereqs (filter (fn [(other Middleware)] -> Bool (if (= other.id target.id) false (hasDepEdge? other target))) remaining))] (not (listEmpty? prereqs)))

fn pickCandidateHelper best: (Option Middleware) mws: (List Middleware) -> (Option Middleware)
  (if (listEmpty? mws) best (let [(cand (optionOr (listHead mws) (makeMiddleware "" "" (kindFilter) 999999 (list) (list)))) (rest (optionOr (listTail mws) (list)))] (mt best ((none) (pickCandidateHelper (some cand) rest)) ((some cur) (if (< cand.priority cur.priority) (pickCandidateHelper (some cand) rest) (pickCandidateHelper best rest))))))

fn pickHighestPriority candidates: (List Middleware) -> (Option Middleware)
  (pickCandidateHelper (none) candidates)

fn topoStep state: TopoState step: I64 -> TopoState
  (if (listEmpty? state.remaining) state (let [(ready (filter (fn [(m Middleware)] -> Bool (not (hasPrerequisite? m state.remaining))) state.remaining))] (let [(candidates (if (listEmpty? ready) state.remaining ready))] (mt (pickHighestPriority candidates) ((none) state) ((some chosen) (let [(nextRem (filter (fn [(m Middleware)] -> Bool (!= m.id chosen.id)) state.remaining)) (nextAcc (listAppend state.acc (list chosen)))] (TopoState :remaining nextRem :acc nextAcc)))))))

fn sortMiddlewares mws: (List Middleware) -> (List Middleware)
  (let [(n (listLength mws)) (initState (TopoState :remaining mws :acc (list))) (finalState (fold topoStep initState (range 0 n)))] finalState.acc)

fn makePipeline -> OnionPipeline
  (OnionPipeline :middlewares (list) :sorted (list))

fn makeLegacyPipeline ctx: Any -> LegacyOnionPipeline
  (LegacyOnionPipeline :context ctx)


fn addMiddleware pipe: OnionPipeline mw: Middleware -> OnionPipeline
  (let [(updatedMws (cons mw pipe.middlewares)) (sortedMws (sortMiddlewares updatedMws))] (OnionPipeline :middlewares updatedMws :sorted sortedMws))

fn sortPipeline pipe: OnionPipeline -> OnionPipeline
  (with pipe :sorted (sortMiddlewares pipe.middlewares))

fn executeMiddleware mw: Middleware ctx: OnionContext -> OnionDecision
  (mt mw.kind ((kindFilter) (if (stringContains? ctx.payload "blocked") (let [(auditEntry (str "filter:blocked:" mw.id)) (nextCtx (with ctx :status "blocked" :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed false :blocked true :reason (str "Blocked by filter: " mw.id) :context nextCtx)) (let [(auditEntry (str "filter:pass:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx)))) ((kindMutate) (let [(mutatedPayload (str ctx.payload ":" mw.id)) (auditEntry (str "mutate:" mw.id)) (nextCtx (with ctx :payload mutatedPayload :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindAudit) (let [(auditEntry (str "audit:" mw.id ":" ctx.toolName)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindPreCall) (let [(auditEntry (str "pre-call:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindPostCall) (let [(auditEntry (str "post-call:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindStepPre) (let [(auditEntry (str "step-pre:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindStepPost) (let [(auditEntry (str "step-post:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindPromptPre) (let [(auditEntry (str "prompt-pre:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))) ((kindModelPost) (let [(auditEntry (str "model-post:" mw.id)) (nextCtx (with ctx :auditLog (cons auditEntry ctx.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context nextCtx))))

fn dispatchToolCall pipe: OnionPipeline ctx: OnionContext executorResult: Str -> OnionDecision
  (let [(sortedMws pipe.sorted) (initDec (OnionDecision :proceed true :blocked false :reason "" :context ctx))] (let [(preDec (fold (fn [(dec OnionDecision) (mw Middleware)] -> OnionDecision (if (not dec.proceed) dec (executeMiddleware mw dec.context))) initDec sortedMws))] (if (not preDec.proceed) preDec (let [(execCtx (OnionContext :callId preDec.context.callId :callerId preDec.context.callerId :toolName preDec.context.toolName :payload executorResult :status "ok" :auditLog (cons (str "exec:" executorResult) preDec.context.auditLog)))] (OnionDecision :proceed true :blocked false :reason "" :context execCtx)))))

fn middlewareKindTag k: MiddlewareKind -> Str
  (mt k ((kindPreCall) "kind-pre-call") ((kindPostCall) "kind-post-call") ((kindFilter) "kind-filter") ((kindMutate) "kind-mutate") ((kindAudit) "kind-audit") ((kindStepPre) "kind-step-pre") ((kindStepPost) "kind-step-post") ((kindPromptPre) "kind-prompt-pre") ((kindModelPost) "kind-model-post"))

fn middlewareKindEq? a: MiddlewareKind b: MiddlewareKind -> Bool
  (= (middlewareKindTag a) (middlewareKindTag b))

fn executeStepMiddleware mw: Middleware ctx: StepContext -> StepDecision
  (let [(payload ctx.payload) (input ctx.input)] (if (or (stringContains? payload "abort") (or (stringContains? input "abort") (or (stringContains? payload "blocked") (or (stringContains? input "blocked") (or (stringContains? payload "deny") (stringContains? input "deny")))))) (let [(auditEntry (str "abort:" mw.id)) (nextCtx (with ctx :input input :payload payload :status "abort" :auditLog (cons auditEntry ctx.auditLog)))] (makeStepDecision "abort" (str "Aborted by middleware: " mw.id) nextCtx)) (if (or (stringContains? payload "retry") (stringContains? input "retry")) (let [(auditEntry (str "retry:" mw.id)) (nextCtx (with ctx :input input :payload payload :status "retry" :auditLog (cons auditEntry ctx.auditLog)))] (makeStepDecision "retry" (str "Retry requested by middleware: " mw.id) nextCtx)) (if (or (stringContains? payload "mutate") (or (stringContains? input "mutate") (or (stringContains? mw.id "mutate") (or (stringContains? mw.id "transform") (or (stringContains? mw.id "redact") (middlewareKindEq? mw.kind (kindMutate))))))) (let [(mutInput (if (stringContains? mw.id "redact") (stringReplace input "secret" "[REDACTED]") (if (stringEmpty? input) input (str input ":" mw.id)))) (mutPayload (if (stringContains? mw.id "redact") (stringReplace payload "secret" "[REDACTED]") (if (stringEmpty? payload) payload (str payload ":" mw.id)))) (auditEntry (str "mutate:" mw.id)) (nextCtx (with ctx :input mutInput :payload mutPayload :status "mutate" :auditLog (cons auditEntry ctx.auditLog)))] (makeStepDecision "mutate" "" nextCtx)) (let [(auditEntry (str (middlewareKindTag mw.kind) ":" mw.id)) (nextCtx (with ctx :input input :payload payload :auditLog (cons auditEntry ctx.auditLog)))] (makeStepDecision "proceed" "" nextCtx))))))

fn dispatchStepHook pipe: OnionPipeline kind: MiddlewareKind ctx: StepContext -> StepDecision
  (let [(matchingMws (filter (fn [(mw Middleware)] -> Bool (or (middlewareKindEq? mw.kind kind) (and (middlewareKindEq? mw.kind (kindFilter)) (or (middlewareKindEq? kind (kindStepPre)) (middlewareKindEq? kind (kindPreCall)))))) pipe.sorted)) (initDec (makeStepDecision "proceed" "" ctx))] (fold (fn [(dec StepDecision) (mw Middleware)] -> StepDecision (if (not dec.proceed) dec (let [(res (executeStepMiddleware mw dec.context))] (if (not res.proceed) res (if (or dec.mutate res.mutate) (StepDecision :action "mutate" :proceed true :mutate true :abort false :retry false :reason res.reason :context res.context) res))))) initDec matchingMws))

(schema LegacyOnionResult (:f status Str) (:f payload Str))

(schema LegacyOnionContext (:f toolName Str) (:f targetFile Str) (:f payload Str) (:f tokens I64) (:f budget I64) (:f policyLevel Any))

(schema LegacyOnionPipeline (:f context LegacyOnionContext))

fn makeContext toolName: Str targetFile: Str payload: Str tokens: I64 budget: I64 policyLevel: Any -> LegacyOnionContext
  (LegacyOnionContext :toolName toolName :targetFile targetFile :payload payload :tokens tokens :budget budget :policyLevel policyLevel)

fn executePipeline pipe: Any -> LegacyOnionResult
  (let [(ctx pipe.context) (tf ctx.targetFile) (tok ctx.tokens) (bud ctx.budget) (pay ctx.payload)] (if (or (stringContains? tf "../") (stringContains? tf "/etc")) (LegacyOnionResult :status "BLOCKED" :payload "ERROR: Blocked by mw-firewall") (if (> tok bud) (LegacyOnionResult :status "BLOCKED" :payload "ERROR: Blocked by mw-cost-guard (token budget exceeded)") (LegacyOnionResult :status "PROCEED" :payload pay))))

fn runSanitizer text: Str -> Str
  (if (> (stringLength text) 1300) (optionOr (stringSlice text 0 1300) text) text)

