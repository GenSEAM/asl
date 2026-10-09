(module aslAgent/asnTranslator :x [AsnIntentFrame makeAsnIntentFrame extractProjectTarget isReleaseDisposition? translatePromptToAsn renderAsnIntentSexp] :i [(asl-text/string :a s) (aslVoice/intentCleaner :a ic)])

(schema AsnIntentFrame (:f intentId Str) (:f kind Str) (:f projectTarget Str) (:f disposition Str) (:f goal Str) (:f requiresWorktree Bool) (:f requiresGate Bool))

fn makeAsnIntentFrame id: Str kind: Str target: Str disp: Str goal: Str worktree: Bool gate: Bool -> AsnIntentFrame
  (AsnIntentFrame :intentId id :kind kind :projectTarget target :disposition disp :goal goal :requiresWorktree worktree :requiresGate gate)

fn extractProjectTarget text: Str -> Str
  (let [(low (stringLower text))] (cond ((or (stringContains? low "agentube") (stringContains? low "агентуб")) "agentube") ((or (stringContains? low "vtbot") (stringContains? low "втбот")) "vtbot") ((or (stringContains? low "datahub-core") (stringContains? low "датахаб")) "datahub-core") ((or (stringContains? low "shrody") (stringContains? low "шроуди")) "shrody") ((or (stringContains? low "paykit") (stringContains? low "пейкит")) "paykit") ((or (stringContains? low "storefront") (stringContains? low "сторфронт")) "storefront") ((or (stringContains? low "asex") (stringContains? low "асекс")) "asex") (else "general")))

fn isReleaseDisposition? low: Str -> Bool
  (or (= low "го") (or (= low "давай") (or (= low "поехали") (or (= low "всё") (or (= low "send it") (or (= low "that's it") (= low "thats it")))))))

fn isIntelQuery? low: Str -> Bool
  (or (stringContains? low "где находится") (or (stringContains? low "кто вызывает") (or (stringContains? low "find symbol") (or (stringContains? low "callers") (stringContains? low "ast outline")))))

fn isMetaQuery? low: Str -> Bool
  (or (stringContains? low "статус") (or (stringContains? low "status") (or (stringContains? low "что сейчас выполняется") (or (stringContains? low "what is running") (stringContains? low "почему упало")))))

fn isAdminCommand? low: Str -> Bool
  (or (stringContains? low "unregister ") (or (stringContains? low "переключись на проект") (or (stringContains? low "удали все задачи") (stringContains? low "switch project"))))

fn translatePromptToAsn rawPrompt: Str -> AsnIntentFrame
  (let [(cleanRes (ic/cleanVoiceIntent rawPrompt)) (goal cleanRes.cleanedIntent) (low (stringLower goal)) (target (extractProjectTarget goal))] (cond ((isReleaseDisposition? low) (makeAsnIntentFrame "intent-release" "fast-path" "general" "release" goal false false)) ((isAdminCommand? low) (makeAsnIntentFrame "intent-admin" "fast-path" target "admin" goal false false)) ((isIntelQuery? low) (makeAsnIntentFrame "intent-intel" "intel" target "query" goal false false)) ((isMetaQuery? low) (makeAsnIntentFrame "intent-meta" "meta" "general" "meta" goal false false)) ((or (stringContains? low "найди в документации") (stringContains? low "search web")) (makeAsnIntentFrame "intent-research" "research" "general" "new" goal false false)) (else (let [(needsRepo (not (= target "general")))] (makeAsnIntentFrame "intent-dev" "dev" target "new" goal needsRepo needsRepo)))))

fn renderAsnIntentSexp frame: AsnIntentFrame -> Str
  (let [(wtStr (if frame.requiresWorktree "true" "false")) (gateStr (if frame.requiresGate "true" "false"))] (str "(:intent :id \"" frame.intentId "\" :kind :" frame.kind " :project \"" frame.projectTarget "\" :disposition :" frame.disposition " :goal \"" frame.goal "\" :requires-worktree " wtStr " :requires-gate " gateStr ")"))
