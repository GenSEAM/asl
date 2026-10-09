(module aslAgent/intentUx :x [IntentKind UxModality FocusPolicy IntentSpec classifyIntent isDisruptiveToUser? resolveOptimalUx makeIntentSpec] :i [(asl-text/string :a s)])

(enum IntentKind (:c intentFastPath [] "Instant local action: pause, mute, stop, cancel (<1ms)") (:c intentDev [] "Code generation, refactoring, and bugfixing with worktree and failing gates") (:c intentIntel [] "Code intelligence: AST outlines, callers, impact without disk mutation") (:c intentResearch [] "Autonomous fact lookup in docs/APIs without interrupting operator") (:c intentClarify [] "Operator consultation and specification disambiguation") (:c intentFollowup [] "Conversational continuation linked to previous parent task") (:c intentMeta [] "Bookkeeping and self-reflection answered directly from task memory") (:c intentNudge [] "Proactive notification of failure runs or unreviewed decisions") (:c intentMesh [] "Swarm delegation across Claude Code CLI, Antigravity IDE, and AD-agents"))

(enum UxModality (:c modalityVoice [] "Auditory speech response via Silero TTS with 8s attention budget") (:c modalityHud [] "Compact visual sparkline HUD or status bar") (:c modalityEditor [] "Inline code diff preview in IDE") (:c modalitySilent [] "Background execution with zero UI disruption"))

(enum FocusPolicy (:c focusImmediate [] "Allowed to shift focus (e.g. critical operator clarification)") (:c focusHoldUntilIdle [] "Held while operator is speaking or typing, applied when idle") (:c focusBadgeOnly [] "Never shifts focus, annotates rail badge"))

(schema IntentSpec (:f intentId Str) (:f kind IntentKind) (:f modality UxModality) (:f focus FocusPolicy) (:f targetWorkspace Str) (:f requiresWorktree Bool) (:f requiresGate Bool) (:f latencyTier Str))

fn makeIntentSpec id: Str kind: IntentKind modality: UxModality focus: FocusPolicy target: Str worktree: Bool gate: Bool sla: Str -> IntentSpec
  (IntentSpec :intentId id :kind kind :modality modality :focus focus :targetWorkspace target :requiresWorktree worktree :requiresGate gate :latencyTier sla)

fn isStopCommand? low: Str -> Bool
  (or (= low "стоп") (or (= low "stop") (or (= low "отмена") (or (= low "cancel") (or (= low "пауза") (= low "pause"))))))

fn isIntelCommand? low: Str -> Bool
  (or (stringContains? low "где находится") (or (stringContains? low "кто вызывает") (or (stringContains? low "find symbol") (stringContains? low "callers"))))

fn isMetaCommand? low: Str -> Bool
  (or (stringContains? low "почему упало") (or (stringContains? low "что ты делаешь") (or (stringContains? low "статус") (stringContains? low "status"))))

fn isResearchCommand? low: Str -> Bool
  (or (stringContains? low "найди в документации") (or (stringContains? low "как работает библиотека") (stringContains? low "search web")))

fn isDevCommand? low: Str -> Bool
  (or (stringContains? low "исправь") (or (stringContains? low "добавь") (or (stringContains? low "напиши тест") (stringContains? low "refactor"))))

fn isMeshCommand? low: Str -> Bool
  (or (stringContains? low "распредели на claude и antigravity") (or (stringContains? low "запусти в воркспейсах") (stringContains? low "swarm")))

fn classifyIntent prompt: Str -> IntentSpec
  (let [(low (stringLower (stringTrim prompt)))] (cond ((isStopCommand? low) (makeIntentSpec "fast-path" (intentFastPath) (modalityVoice) (focusImmediate) "general" false false "sub-millisecond")) ((isIntelCommand? low) (makeIntentSpec "intel" (intentIntel) (modalityHud) (focusHoldUntilIdle) "current" false false "interactive")) ((isMetaCommand? low) (makeIntentSpec "meta" (intentMeta) (modalityVoice) (focusHoldUntilIdle) "general" false false "sub-second")) ((isResearchCommand? low) (makeIntentSpec "research" (intentResearch) (modalitySilent) (focusBadgeOnly) "general" false false "background")) ((isDevCommand? low) (makeIntentSpec "dev" (intentDev) (modalityEditor) (focusHoldUntilIdle) "current" true true "interactive")) ((isMeshCommand? low) (makeIntentSpec "mesh" (intentMesh) (modalityHud) (focusBadgeOnly) "multi" true true "background")) (else (makeIntentSpec "general" (intentDev) (modalityVoice) (focusHoldUntilIdle) "general" false false "interactive"))))

fn isDisruptiveToUser? intent: IntentSpec isUserActive: Bool -> Bool
  (if (not isUserActive) false (let [(f intent.focus)] (cond ((= f (focusImmediate)) false) ((= f (focusBadgeOnly)) false) ((= f (focusHoldUntilIdle)) true) (else false))))

fn resolveOptimalUx intent: IntentSpec -> Str
  (let [(sla intent.latencyTier)] (str "(:ux-plan :intent \"" intent.intentId "\" :sla \"" sla "\")"))
