# asl-agent (package `aslAgent`)

ASL records and functions for a coding agent: request triage and intent classification (`triage`, `intentUx`, `omniIntent`, `asnTranslator`), clarification dialogue and composition state (`feedback`, `compose`), a task DAG with box-art rendering (`taskDag`, `asnBoxart`), autonomy policy and permission checks (`policy`, `corridor`), a review circuit breaker and swarm scheduling with failure witnesses (`reviewBreaker`, `swarmCoordinator`, `swarmPartition`), model routing (`modelRouter`, `processingRouter`), a staged in-memory edit buffer (`ramTxn`), context-window slots (`vmm`), terminal formatting for a TUI (`tui`, `pty`, `cockpitScheduler`, `tuiWorkspaceRouter`), and records for IDE worktrees, computer-use actions, chat and network tasks.

What runs today:
- `src/cli.asl` and `src/tui.asl` export `main` and pass the host check. `asl/host/out/asl-host run asl/packages/asl-agent/src/cli.asl --help` prints the help text of a `gsa` command; with `-p TEXT` or `-e PATH` it prints `GSA executing directive: TEXT` or `GSA running evaluation suite: PATH` and stops. It does not call a model or execute a task. There is no `asl agent` command.
- `src/onion.asl` declares the module `aslAgent/onionOld` with no exports; it is an empty placeholder.
- On 2026-10-14, 41 of the 43 files in `src/` pass `asl/host/out/asl-host check`. `src/frontAgent.asl` and `src/unbiasedContext.asl` fail because they import `asl/packages/asl-agent/src/omniIntent` by path instead of `aslAgent/omniIntent`.

Module names use the prefix `aslAgent/`; `manifest.asn` lists the same 43 modules and declares dependencies on `asl-agent-core`, `asl-agent-bus` and `asl-text`.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 43 modules, 531 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslAgent/agent` (`src/agent.asl`, 12): `AgentState`, `AgentSession`, `StepResult`, `AgentOperatingMode`, `modeSimple`, `modeMaintainer`, `makeAgentSession`, `makeAutonomySession`, `stepAgent!`, `stepAgentWithHostCall!`, `runBoundedSession!`, `runInMode!`.
- `aslAgent/anchorLinker` (`src/anchorLinker.asl`, 5): `MemoryRef`, `resolveAnchor`, `formatMemoryRef`, `validateAnchorReference`, `extractAnchors`.
- `aslAgent/asnBoxart` (`src/asnBoxart.asl`, 5): `BoxNode`, `BoxEdge`, `formatBoxBadge`, `renderTreeBoxart`, `renderDagBoxart`.
- `aslAgent/asnTranslator` (`src/asnTranslator.asl`, 6): `AsnIntentFrame`, `makeAsnIntentFrame`, `extractProjectTarget`, `isReleaseDisposition?`, `translatePromptToAsn`, `renderAsnIntentSexp`.
- `aslAgent/chatBridge` (`src/chatBridge.asl`, 9): `ChatIngressEnvelope`, `ChatBridgeState`, `makeChatIngress`, `initChatBridge`, `streamVoiceToChat`, `triggerBargeInAbort`, `resolveAnaphoraDirective`, `formatChatIngressAsn`, `renderChatTelemetryAsn`.
- `aslAgent/cli` (`src/cli.asl`, 17): `InferencePhase`, `InferenceConfig`, `TelemetryCounters`, `CliOptions`, `phaseInspect`, `phasePlan`, `phaseAstPatch`, `phaseReasonDebug`, `makeCliOptions`, `makeSimpleCliOptions`, `getPhasedConfig`, `makeTelemetry`, `parseAutonomyFlag`, `formatCliHelp`, `processReplCommand`, `parseCliArgs`, `main`.
- `aslAgent/cliParser` (`src/cliParser.asl`, 2): `parseOpts`, `parseCliArgs`.
- `aslAgent/cockpitScheduler` (`src/cockpitScheduler.asl`, 9): `CockpitViewState`, `makeCockpitViewState`, `CockpitJobState`, `makeCockpitJobState`, `switchFocusedPane`, `verifyFocusInvariant`, `routeExecutionReceipt`, `resolveWorkspaceVisibility`, `isReceiptStale?`.
- `aslAgent/compose` (`src/compose.asl`, 19): `QuestionKind`, `UnresolvedQuestion`, `AssumedFact`, `Composition`, `kindOperator`, `kindLookup`, `operator`, `lookup`, `makeUnresolvedQuestion`, `makeAssumedFact`, `makeEmptyComposition`, `addUnresolvedQuestion`, `addAssumedFact`, `closeUnresolvedQuestion`, `supersedeAssumedFact`, `extractPendingLookups`, `resolveLookupQuestion`, `renderCompositionContext`, and 1 more.
- `aslAgent/computerUse` (`src/computerUse.asl`, 23): `TargetSubstrate`, `ComputerActionKind`, `SpatialBoundingBox`, `ComputerActionRequest`, `ComputerActionReceipt`, `substrateBrowser`, `substrateDesktop`, `substrateTerminal`, `actionNavigate`, `actionClick`, `actionType`, `actionInspect`, `actionScreenshot`, `makeSpatialBox`, `makeComputerAction`, `confirmComputerAction`, `isActionPermitted?`, `formatCdpPayload`, and 5 more.
- `aslAgent/copilot` (`src/copilot.asl`, 15): `PointerKind`, `PointerRef`, `StagedProposal`, `ptrDom`, `ptrLog`, `ptrAst`, `ptrVision`, `makePointer`, `dereferencePointer!`, `makeProposal`, `stageProposal`, `commitStagedProposal`, `intentRecord`, `intentQuery`, `traceVerify!`.
- `aslAgent/corridor` (`src/corridor.asl`, 6): `FreedomCorridor`, `makeCorridor`, `defaultCorridor`, `isActionPermittedByCorridor?`, `formatCorridorSummary`, `corridorToAsn`.
- `aslAgent/dispatch` (`src/dispatch.asl`, 2): `canonicalToolRegistry!`, `dispatchCanonicalTool!`.
- `aslAgent/eddie` (`src/eddie.asl`, 22): `TaskTier`, `TaskIntent`, `TriageVerdict`, `TaskItem`, `TaskPool`, `OrchestrationPlan`, `fastTriage`, `consultAndRefine`, `planExecution`, `evaluateCircuitBreaker`, `agentRun!`, `agentVersion`, `agentBanner`, `gsaRun!`, `gsaVersion`, `gsaBanner`, `eddieRun!`, `eddieVersion`, and 4 more.
- `aslAgent/feedback` (`src/feedback.asl`, 18): `ClarificationOption`, `RefinedRequirement`, `DialogueStage`, `IntentContract`, `stageInterview`, `stageCorridorNegotiation`, `stageGrounded`, `stageDelegated`, `isAmbiguousPrompt?`, `stripPoliteFluff`, `refineUserPrompt`, `formatClarifyingQuestion`, `formatConciseDirective`, `formatTradeoffBlock`, `makeIntentContract`, `groundIntentToMemory`, `decomposeIntentToDag`, `advanceDialogueStage`.
- `aslAgent/ffi` (`src/ffi.asl`, 7): `HostCallRequest`, `HostCallResponse`, `makeHostRequest`, `makeHostResponse`, `isValidCapability?`, `isValidAction?`, `hostCall!`.
- `aslAgent/frontAgent` (`src/frontAgent.asl`, 6): `FrontAgentConfig`, `FrontAgentState`, `FrontAgentReceipt`, `frontAgentInit`, `frontAgentHandleDirective`, `formatFrontAgentReceipt`.
- `aslAgent/horizon` (`src/horizon.asl`, 12): `HorizonDepth`, `HorizonRequest`, `HorizonResult`, `HealthMatrix`, `depthFullAst`, `depthInterfaceStubs`, `depthModuleNames`, `makeHorizonRequest`, `makeHorizonResult`, `expandHorizon`, `computeHealthMatrix`, `formatHealthSummary`.
- `aslAgent/ideMesh` (`src/ideMesh.asl`, 30): `IdeRuntime`, `WorktreeSlot`, `MeshHubConfig`, `IdeTaskEnvelope`, `IdeExecutionReceipt`, `IdeMeshCoordinator`, `ideClaudeCode`, `ideAntigravity`, `ideNativeAd`, `ideCursorBridge`, `runtimeToStr`, `strToRuntime`, `makeWorktreeSlot`, `formatGitWorktreeAdd`, `formatGitWorktreeRemove`, `hasWorktreeCollision?`, `makeDefaultHubConfig`, `makeIdeTask`, and 12 more.
- `aslAgent/intentUx` (`src/intentUx.asl`, 8): `IntentKind`, `UxModality`, `FocusPolicy`, `IntentSpec`, `classifyIntent`, `isDisruptiveToUser?`, `resolveOptimalUx`, `makeIntentSpec`.
- `aslAgent/modelRouter` (`src/modelRouter.asl`, 18): `TaskRole`, `ModelEndpoint`, `RoutingMatrix`, `roleDesign`, `roleCoding`, `roleReview`, `roleTriage`, `makeEndpoint`, `defaultRoutingMatrix`, `resolveModelForRole`, `formatRouteDecision`, `CognitiveIntent`, `AttractorGuidance`, `DispatchFrame`, `makeDispatchFrame`, `makeTriadDispatchFrame`, `resolveEndpointForIntent`, `formatDispatchFrame`.
- `aslAgent/networkTasks` (`src/networkTasks.asl`, 10): `NetworkTaskKind`, `NetworkTaskRequest`, `NetworkTaskOutcome`, `taskWebSearch`, `taskDocCrawl`, `taskApiQuery`, `taskMeshBroadcast`, `makeNetworkTask`, `executeNetworkTask`, `formatNetworkOutcomeAsn`.
- `aslAgent/nudgeGuard` (`src/nudgeGuard.asl`, 7): `NudgeEvent`, `NudgeGuardState`, `makeInitialNudgeGuard`, `recordTaskOutcome`, `evaluateProactiveNudge`, `holdDisruptiveIntent`, `releaseHeldIntentsOnIdle`.
- `aslAgent/omniIngress` (`src/omniIngress.asl`, 10): `IngressRequest`, `NormalizedIntentFrame`, `protoUnixSocket`, `protoHttpRest`, `protoTerminalCli`, `protoVoiceStream`, `resolveTargetEngine`, `ingressNormalize`, `ingressDispatch`, `isIngressValid?`.
- `aslAgent/omniIntent` (`src/omniIntent.asl`, 14): `OmniDomain`, `OmniIntent`, `domainCodeTask`, `domainResearch`, `domainBrowserAction`, `domainIdeaCapture`, `domainCrossProjectSync`, `domainSystemControl`, `classifyOmniIntent`, `formatOmniIntentAsn`, `isCodeTask?`, `isResearch?`, `isBrowserAction?`, `domainToString`.
- `aslAgent/onionOld` (`src/onion.asl`): no `:x` list; exports nothing.
- `aslAgent/policy` (`src/policy.asl`, 23): `AutonomyLevel`, `ActionCategory`, `PermissionManifest`, `PermissionResult`, `levelAsk`, `levelGuarded`, `levelAuto`, `catRead`, `catTest`, `catWrite`, `catExec`, `makeManifest`, `allowSilent`, `allowPrompt`, `denyStrict`, `denyUnauthorized`, `hasTraversal?`, `isSystemPath?`, and 5 more.
- `aslAgent/processingRouter` (`src/processingRouter.asl`, 9): `ProcessingTier`, `RouteDecision`, `tier0Ast`, `tier1Audio`, `tier2Slm`, `tier3Cloud`, `tierToStr`, `resolveProcessingTier`, `formatRouteDecisionAsn`.
- `aslAgent/promptPool` (`src/promptPool.asl`, 7): `PromptEntry`, `PromptPool`, `makePromptEntry`, `makePromptPool`, `recordPrompt`, `getActivePrompts`, `renderPromptPoolAsn`.
- `aslAgent/pty` (`src/pty.asl`, 24): `PtyResult`, `AnsiState`, `ThoughtEntry`, `PtyPointer`, `makePtyResult`, `formatPtyResult`, `isAnsiTerminator?`, `stripAnsiEscapes`, `ptyStreamBypass`, `sparklineGlyph`, `quantizeSparklinePoint`, `averageList`, `downsampleHelper`, `downsampleMetrics`, `renderSparkline`, `compressMetricsSparkline`, `makeThoughtEntry`, `formatThoughtEntry`, and 6 more.
- `aslAgent/ramTxn` (`src/ramTxn.asl`, 9): `RamBuffer`, `RamVfs`, `ThreePointReceipt`, `makeRamVfs`, `stageBufferEdit`, `getBufferContent`, `discardBuffer`, `flushBufferAtomic!`, `verifyThreePointGate!`.
- `aslAgent/reviewBreaker` (`src/reviewBreaker.asl`, 11): `ReviewDecision`, `ReviewExchange`, `revApproved`, `revRejected`, `revEscalated`, `makeReviewExchange`, `recordReviewCritique`, `recordReviewApproval`, `isReviewTripped?`, `isReviewPassed?`, `formatEscalationReport`.
- `aslAgent/snapshot` (`src/snapshot.asl`, 14): `SnapshotKind`, `SnapshotEntity`, `SnapshotGraph`, `kindReq`, `kindDecision`, `kindInvariant`, `kindEdge`, `makeEntity`, `makeGraph`, `formatEntity`, `parseKind`, `serializeGraph`, `deserializeGraph`, `diffGraphs`.
- `aslAgent/supervisor` (`src/supervisor.asl`, 14): `ProcessStatus`, `SupervisorConfig`, `ProcessReceipt`, `procInit`, `procRunning`, `procIdleTimeout`, `procDeadlock`, `procCompleted`, `procFailed`, `makeSupervisorConfig`, `buildSupervisedEnv`, `checkProcessActivity`, `trapInteractiveDeadlock`, `executeSupervised!`.
- `aslAgent/swarmCoordinator` (`src/swarmCoordinator.asl`, 9): `SwarmTask`, `FailureWitness`, `CircuitBreaker`, `makeSwarmTask`, `emptyCircuitBreaker`, `scheduleSwarmWaves`, `recordFailureWitness`, `isLimitCycleTripped?`, `getFailureWitness`.
- `aslAgent/swarmPartition` (`src/swarmPartition.asl`, 10): `PartitionSet`, `ScopeLease`, `LeaseRegistry`, `makePartitionSet`, `emptyLeaseRegistry`, `pathsOverlap?`, `detectCollision?`, `validateScopeOwnership`, `claimScopeLease`, `releaseScopeLease`.
- `aslAgent/taskDag` (`src/taskDag.asl`, 24): `TaskNodeStatus`, `TaskNode`, `TaskDAG`, `nodePending`, `nodeReady`, `nodeInProgress`, `nodeCompleted`, `nodeFailed`, `nodeBlocked`, `makeTaskNode`, `makeTaskDag`, `findNode`, `isNodeCompleted?`, `areDepsSatisfied?`, `getCompletedNodeIds`, `getReadyNodes`, `markNodeStatus`, `markNodeCompleted`, and 6 more.
- `aslAgent/triage` (`src/triage.asl`, 11): `WorkspaceContext`, `TriageDecision`, `makeWorkspaceContext`, `makeTriageDecision`, `isSetupCommand?`, `isAdminCommand?`, `isQuestion?`, `isDevCommand?`, `hasMultiAspect?`, `hasExplicitSplit?`, `triageRequest`.
- `aslAgent/tui` (`src/tui.asl`, 23): `TuiHeader`, `MeshNodeStats`, `makeTuiHeader`, `makeTuiHeaderWithMode`, `formatTuiHeader`, `formatToolCall`, `formatToolCallFold`, `formatSpinnerStatus`, `formatChatMsg`, `formatAgentBadge`, `formatThinkingBlock`, `formatReflectionChannel`, `formatMeshTelemetry`, `formatContextBar`, `formatDiffPreview`, `formatContextAndDiffBar`, `formatSessionSummary`, `parseCliArgs`, and 5 more.
- `aslAgent/tuiWorkspaceRouter` (`src/tuiWorkspaceRouter.asl`, 22): `TuiFocusTarget`, `focusWorkspace`, `focusProject`, `focusTasks`, `focusObservatory`, `focusOmniPrompt`, `focusTargetToString`, `WorkspaceItem`, `makeWorkspaceItem`, `ProjectItem`, `makeProjectItem`, `TaskItem`, `makeTaskItem`, `TuiRouterState`, `makeInitialRouterState!`, `cycleFocusForward`, `cycleFocusBackward`, `selectNextItem`, and 4 more.
- `aslAgent/types` (`src/types.asl`, 11): `AgentMessage`, `ToolParam`, `ToolDef`, `ToolArg`, `ToolCall`, `ToolInvocation`, `ToolResult`, `makeAgentMessage`, `makeToolDef`, `makeToolCall`, `makeToolResult`.
- `aslAgent/unbiasedContext` (`src/unbiasedContext.asl`, 5): `UnbiasedContextFrame`, `refutePersonaPreamble`, `sanitizeObservation`, `buildUnbiasedContextFrame`, `formatUnbiasedContextFrame`.
- `aslAgent/vmm` (`src/vmm.asl`, 13): `ContextSlot`, `VmmSlot`, `VmmState`, `slotInvariants`, `slotReceipts`, `slotPinned`, `slotWorking`, `makeVmmSlot`, `makeVmmState`, `vmmLoadKnowledge`, `vmmOffloadKnowledge`, `vmmCompact`, `vmmRenderPrompt`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-agent/tests/<file>.asl
```

39 of 42 test files exit 0 (731 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `ablationMetricsTest.asl` | pass | 9 assertions |
| `agentTest.asl` | pass | 42 assertions |
| `anchorLinkerTest.asl` | pass | 9 assertions, 1 refutations |
| `asnBoxartTest.asl` | pass | 1 assertions |
| `chatBridgeTest.asl` | pass | 19 assertions, 1 refutations |
| `cliTest.asl` | pass | 26 assertions |
| `cockpitSchedulerTest.asl` | pass | 13 assertions, 3 refutations |
| `composePromptPoolTest.asl` | pass | 16 assertions |
| `composeTest.asl` | pass | 34 assertions, 20 refutations |
| `computerUseTest.asl` | pass | 29 assertions, 2 refutations |
| `copilotTest.asl` | **fail** | needs the parent monorepo: `traceVerify!` reads `.asl/mem/intent.asn` from the working directory |
| `corridorTest.asl` | pass | 7 assertions |
| `dispatchTest.asl` | pass | 42 assertions |
| `dualModeTest.asl` | pass | 6 assertions |
| `eddieTest.asl` | pass | 29 assertions |
| `feedbackHarnessTest.asl` | pass | 8 assertions |
| `feedbackTest.asl` | pass | 12 assertions |
| `ffiTest.asl` | pass | 6 assertions |
| `horizonTest.asl` | pass | 9 assertions |
| `ideMeshTest.asl` | pass | 31 assertions, 2 refutations |
| `intentUxTest.asl` | pass | 18 assertions |
| `liveAppTest.asl` | pass | 13 assertions |
| `masterE2eTest.asl` | pass | 15 assertions |
| `modelRouterTest.asl` | pass | 8 assertions |
| `omniIngressTest.asl` | pass | 28 assertions |
| `omniIntentTest.asl` | **fail** | load errors: path imports `asl/packages/asl-agent/src/omniIntent` and `.../frontAgent` (and `src/frontAgent.asl` imports `omniIntent` by path) |
| `onionTest.asl` | pass | 8 assertions |
| `policyTest.asl` | pass | 13 assertions |
| `processingRouterTest.asl` | pass | 23 assertions |
| `ptyTest.asl` | pass | 41 assertions |
| `ramTxnTest.asl` | pass | 4 assertions, 3 refutations |
| `reviewBreakerTest.asl` | pass | 8 assertions |
| `shrodyAsnTranslationBenchTest.asl` | pass | 32 assertions |
| `snapshotTest.asl` | pass | 10 assertions |
| `supervisorTest.asl` | pass | 10 assertions |
| `swarmCoordinatorTest.asl` | pass | 7 assertions, 2 refutations |
| `swarmPartitionTest.asl` | pass | 6 assertions, 3 refutations |
| `taskDagTest.asl` | pass | 19 assertions |
| `tuiTest.asl` | pass | 57 assertions |
| `tuiWorkspaceRouterTest.asl` | pass | 15 assertions, 2 refutations |
| `unbiasedContextTest.asl` | **fail** | load errors: path imports `asl/packages/asl-agent/src/unbiasedContext` and `.../omniIntent` |
| `vmmTest.asl` | pass | 9 assertions |
