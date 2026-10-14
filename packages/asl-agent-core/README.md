# asl-agent-core (package `aslAgentCore`)

ASL building blocks for an agent runtime, as records and pure functions: message and tool records with a tool registry (`core`, `protocol`, `types`), tool dispatch with parameter checks and a path-escape guard (`dispatch`), an onion middleware pipeline (`onion`), a six-state agent state machine (`fsm`, `statemachine`), task DAGs and their merge (`dag`, `dagMerge`), a task store and scheduler (`taskstore`, `tasktypes`, `scheduler`), prompt pools, prompt trees and token-budget audits (`promptpool`, `promptTree`, `promptAudit`), clarification and goal composition (`clarify`, `compose`, `premise`, `threads`), and fiber, worker and daemon state records (`fiberPool`, `workerSupervisor`, `omniDaemon`, `fastKnowledgeCache`).

Module names use the prefix `aslAgentCore/`; `manifest.asn` lists the same 23 modules. On 2026-10-14, 22 of the 23 files in `src/` pass `asl/host/out/asl-host check`; `src/omniDaemon.asl` fails because it imports `asl/packages/asl-agent-core/src/fiberPool` by path instead of `aslAgentCore/fiberPool`.

The state machine (`fsm`) has states `idle`, `planning`, `coding`, `reviewing`, `success`, `failed` and events `start`, `planReady`, `codeReady`, `reviewPass`, `reviewFail`, `reset`; `step` is a pure transition function and `isTerminalState` is true for `success` and `failed`. In `onion`, middleware is sorted by priority and `before`/`after` constraints; the built-in `kindFilter` behaviour blocks a call whose payload contains the substring `blocked`.

## Example

Both checks below pass on the host (2026-10-14). The example lives outside this repository, so its `.asl.config.asn` names the package by path: `(:aslConfig :workspace "ex" :dependencies ((aslAgentCore :path "/path/to/asl/packages/asl-agent-core")))`.

```asl
(module example/agentCoreUsage :x [runTests] :i [(aslAgentCore/fsm :a fsm) (aslAgentCore/onion :a on)])

fn runTests -> Bool
  (let [(s1 (fsm/step (fsm/idle) (fsm/start)))
        (s4 (fsm/step (fsm/step (fsm/step s1 (fsm/planReady)) (fsm/codeReady)) (fsm/reviewPass)))
        (pipe (on/addMiddleware (on/makePipeline) (on/makeMiddleware "guard" "Guard" (on/kindFilter) 10 (list) (list))))
        (dec (on/dispatchToolCall pipe (on/makeOnionContext "c2" "agent" "fileRead" "blocked path") "done"))]
    (do (assert (fsm/isTerminalState s4) "reviewPass from reviewing ends in success")
        (assert dec.blocked "the filter stops a payload containing blocked")
        true))
```

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 23 modules, 279 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslAgentCore/clarify` (`src/clarify.asl`, 8): `ClarificationQuestion`, `ClarificationAnswer`, `ClarificationSession`, `clarificationSessionCreate`, `parseNumberedAnswers`, `attachClarificationAnswers`, `isClarificationResolved?`, `unblockClarificationTask`.
- `aslAgentCore/compose` (`src/compose.asl`, 5): `GoalSpecification`, `composeGoal`, `composeFollowupGoal`, `extractGoalDelta`, `formatCumulativeSpec`.
- `aslAgentCore/core` (`src/core.asl`, 22): `AgentMessage`, `AgentContext`, `ToolDef`, `ToolCall`, `ToolResult`, `AgentCompletion`, `AgentRegistry`, `EventBus`, `makeMessage`, `makeAgentContext`, `addMessage`, `makeToolDef`, `makeToolCall`, `makeToolResult`, `emptyRegistry`, `registerTool`, `findTool`, `hasTool?`, and 4 more.
- `aslAgentCore/dag` (`src/dag.asl`, 10): `DagNodeState`, `TaskNode`, `TaskDag`, `dagCreate`, `dagAddNode`, `dagFindNode`, `dagIsFalsified?`, `dagFalsifyPremise`, `dagCanActivate?`, `dagCasVersion`.
- `aslAgentCore/dagMerge` (`src/dagMerge.asl`, 6): `MergedTaskNode`, `DagMergeResult`, `stateToRank`, `resolveStateLattice`, `dagMergeBranches`, `validateDagAcyclic`.
- `aslAgentCore/dispatch` (`src/dispatch.asl`, 21): `ToolHandler`, `ToolRegistry`, `registerTool`, `registerHandler`, `findTool`, `findHandler`, `checkRequiredParams`, `validateInvocation`, `executeTool`, `dispatchCall`, `dispatchBatchCalls`, `DispatchResult`, `CanonicalAutonomy`, `autonomyAsk`, `autonomyGuarded`, `autonomyAuto`, `isCanonicalTool`, `pathEscapes`, and 3 more.
- `aslAgentCore/fastKnowledgeCache` (`src/fastKnowledgeCache.asl`, 10): `AstSymbolEntry`, `KnowledgeSnapshot`, `knowledgeCacheCreate`, `knowledgeIndexSymbol`, `knowledgeLookupSymbol`, `knowledgeUpdateTask`, `knowledgeGetTaskStatus`, `knowledgeRecordDefect`, `knowledgeAddNote`, `formatKnowledgeSnapshot`.
- `aslAgentCore/fiberPool` (`src/fiberPool.asl`, 21): `FiberPriority`, `FiberState`, `prioCritical`, `prioInteractive`, `prioBackground`, `fiberPending`, `fiberRunning`, `fiberYielded`, `fiberCompleted`, `fiberFailed`, `FiberFrame`, `FiberRecord`, `FiberPool`, `fiberPoolCreate`, `fiberSpawn`, `fiberStep`, `fiberYield`, `fiberComplete`, and 3 more.
- `aslAgentCore/fsm` (`src/fsm.asl`, 4): `AgentState`, `AgentEvent`, `step`, `isTerminalState`.
- `aslAgentCore/omniDaemon` (`src/omniDaemon.asl`, 13): `DaemonStatus`, `DaemonConfig`, `DaemonState`, `daemonBooting`, `daemonRunning`, `daemonDraining`, `daemonStopped`, `daemonInit`, `daemonTick`, `daemonShutdown`, `daemonDispatchFiber`, `daemonDispatchWorker`, `formatDaemonStatus`.
- `aslAgentCore/onion` (`src/onion.asl`, 30): `MiddlewareKind`, `Middleware`, `OnionContext`, `OnionDecision`, `OnionPipeline`, `TopoState`, `StepContext`, `StepDecision`, `makeMiddleware`, `makeOnionContext`, `makeStepContext`, `makeStepDecision`, `makePipeline`, `makeLegacyPipeline`, `addMiddleware`, `sortPipeline`, `hasDepEdge?`, `hasPrerequisite?`, and 12 more.
- `aslAgentCore/premise` (`src/premise.asl`, 4): `PremiseRecord`, `makePremise`, `falsifyPremise`, `formatPremise`.
- `aslAgentCore/promptAudit` (`src/promptAudit.asl`, 9): `PromptDef`, `TokenMetric`, `PromptAuditResult`, `BudgetAuditReport`, `auditPromptTokens`, `estimateTokensSimple`, `validatePromptBudget`, `auditRegistryString`, `auditPromptBudgets`.
- `aslAgentCore/promptTree` (`src/promptTree.asl`, 7): `PromptRadixNode`, `PromptTree`, `AssembledPrompt`, `promptTreeInit`, `promptTreeBranch`, `promptTreeAssemble`, `promptTreeCalcSavings`.
- `aslAgentCore/promptpool` (`src/promptpool.asl`, 13): `PromptEntry`, `PromptPool`, `MultiLanePool`, `promptPoolCreate`, `promptPoolPush`, `promptPoolPrune`, `renderPromptPool`, `multiPoolCreate`, `multiPoolPush`, `multiPoolGet`, `multiPoolPruneAll`, `poolCapDefault`, `ttlMsDefault`.
- `aslAgentCore/protocol` (`src/protocol.asl`, 13): `ToolParam`, `ToolDef`, `ToolArg`, `ToolInvocation`, `ToolResult`, `formatToolParam`, `formatToolDef`, `formatInvocation`, `formatResult`, `getArgValue`, `stripQuotes`, `parseTokens`, `parseInvocation`.
- `aslAgentCore/scheduler` (`src/scheduler.asl`, 17): `SchedulerConfig`, `SchedulerState`, `DrainResult`, `ReapResult`, `DrainAccumulator`, `schedulerCreate`, `schedulerDrain!`, `schedulerReapStale!`, `schedulerReapStaleWithMaxRetries!`, `getTaskRetryCount`, `schedulerReleaseProject`, `schedulerReleaseTask`, `schedulerReleaseLane`, `isReapableState?`, `validateDagAcyclic`, `schedulerReapStaleWithEpoch!`, `getLaneCount`.
- `aslAgentCore/statemachine` (`src/statemachine.asl`, 3): `assertTransition`, `isTerminalState?`, `validTransition?`.
- `aslAgentCore/taskstore` (`src/taskstore.asl`, 14): `TaskStore`, `taskstoreCreate`, `taskstorePut!`, `taskstoreGet`, `isTaskQueued?`, `filterQueued`, `insertTask`, `sortTasks`, `taskstoreListQueued`, `taskstoreClaim!`, `taskstoreTransition!`, `taskstoreListInFlight`, `taskstoreCountByState`, `taskstoreSpawnChildren!`.
- `aslAgentCore/tasktypes` (`src/tasktypes.asl`, 10): `TaskState`, `TaskPriority`, `TaskKind`, `TaskOutcome`, `TaskRecord`, `TaskLane`, `taskRecordCreate`, `taskLaneCreate`, `makeTaskOutcome`, `taskStateInFlight?`.
- `aslAgentCore/threads` (`src/threads.asl`, 8): `ThreadRecord`, `ThreadHandoff`, `threadCreate`, `threadAddTask`, `threadLinkFollowup`, `threadAttachHandoff`, `threadGetParentBrief`, `threadIsActive?`.
- `aslAgentCore/types` (`src/types.asl`, 11): `AgentMessage`, `ToolParam`, `ToolDef`, `ToolArg`, `ToolCall`, `ToolInvocation`, `ToolResult`, `makeAgentMessage`, `makeToolDef`, `makeToolCall`, `makeToolResult`.
- `aslAgentCore/workerSupervisor` (`src/workerSupervisor.asl`, 20): `WorkerStatus`, `WorkerSandboxMode`, `workerSpawning`, `workerIdle`, `workerBusy`, `workerStalled`, `workerCrashed`, `sandboxReadOnly`, `sandboxWorkspaceWrite`, `sandboxDangerFull`, `SupervisorLimitsConfig`, `WorkerRecord`, `WorkerPool`, `workerPoolCreate`, `workerSpawn`, `workerHeartbeat`, `workerCheckLimits`, `workerReap`, and 2 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-agent-core/tests/<file>.asl
```

13 of 17 test files exit 0 (458 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `coreTest.asl` | pass | 10 assertions, 8 refutations |
| `dagMergeTest.asl` | pass | 20 assertions |
| `dagTest.asl` | pass | 23 assertions |
| `dispatchTest.asl` | pass | 54 assertions |
| `dualIsolationTest.asl` | **fail** | load errors: imports `asl/packages/asl-agent-core/src/...` and `asl/packages/asl-agent/src/...` by path, which the host does not resolve (it wants the declared module names, e.g. `aslAgentCore/fiberPool`) |
| `fiberPoolTest.asl` | **fail** | load errors: imports `asl/packages/asl-agent-core/src/fiberPool` and `.../fastKnowledgeCache` by path; the host wants `aslAgentCore/...` |
| `fsmTest.asl` | pass | 12 assertions |
| `omniDaemonTest.asl` | **fail** | load errors: path imports `asl/packages/asl-agent-core/src/...` (including from `src/omniDaemon.asl` itself) |
| `onionTest.asl` | pass | 30 assertions |
| `promptAuditTest.asl` | pass | 31 assertions |
| `promptTreeTest.asl` | pass | 8 assertions |
| `promptpoolTest.asl` | pass | 57 assertions |
| `schedulerPromptPoolTest.asl` | pass | 53 assertions, 27 refutations |
| `schedulerTest.asl` | pass | 24 assertions, 4 refutations |
| `taskstoreTest.asl` | pass | 72 assertions |
| `toolcallTest.asl` | pass | 25 assertions |
| `workerSupervisorTest.asl` | **fail** | load error: path import `asl/packages/asl-agent-core/src/workerSupervisor` |
