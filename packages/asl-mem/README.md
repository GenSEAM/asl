# asl-mem (package `aslMem`)

In-memory data structures for agent memory and workspace state, written as ASL records and pure functions: vector math and a fixed-dimension vector store, BM25 and reciprocal-rank fusion, SimHash, a knowledge graph, an e-graph, a ring buffer, a write-ahead log with checkpoints and snapshots, a staged virtual file system with forks, merges and drift checks, software transactional memory over file snapshots, task records with leases, DAG readiness and recovery, notes, ADR and roadmap records, and context scoring and paging. `engine` (`makeEngine`, `enginePutVector`, `engineCheckpoint`, `engineRecover`) combines the ring, vector store, graph and WAL.

Everything lives in ASL values. `sqliteAdapter` keeps tables as maps (it does not open SQLite), `opfsAdapter` and `storageFile` keep files as maps with path and lock checks, and `wasmRuntime` models WebAssembly linear memory as a map of byte offsets. The only disk reads are `fileRead` calls in `pointerOrchestrator.rehydratePointer!` and `stm.stmWrite!`; nothing in the package writes files, and nothing runs in or compiles to WebAssembly.

Most module names use the prefix `aslMem/`; `opfsAdapter`, `sqliteAdapter` and `wasmRuntime` are declared without a prefix. `manifest.asn` lists the same 60 modules. All 60 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 60 modules, 651 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslMem/amnesia` (`src/amnesia.asl`, 16): `Chunk`, `ChunkDAG`, `RetiredChunk`, `validateMemoryChunk`, `isLowConfidence?`, `chunkDagEmpty`, `chunkDagAdd`, `chunkDagFind`, `detectCycle?`, `chunkDagAncestors`, `evictBelowThreshold`, `transitionToRetired`, `evaluateRetirement`, `retireChunk`, `queryRetiredChunks`, `loadActiveChunks`.
- `aslMem/astFilter` (`src/astFilter.asl`, 3): `ASTQuery`, `ASTMatchNode`, `matchAstForm`.
- `aslMem/astMerge` (`src/astMerge.asl`, 13): `ASTCollisionRecord`, `HomoiconicForm`, `AstMergeOutcome`, `AstMergeResult`, `cleanFormId`, `extractFormKind`, `extractFormId`, `parseHomoiconicForms`, `findAstForm`, `resolveHomoiconicForm`, `formatAstCollision`, `universalAst3wayMerge`, `mergeSexpLists`.
- `aslMem/bm25` (`src/bm25.asl`, 10): `Bm25Doc`, `Bm25Index`, `Bm25Score`, `tokenizeTerms`, `makeBm25Index`, `computeIdf`, `calcIdf`, `scoreBm25`, `sortBm25Scores`, `rankBm25`.
- `aslMem/checkpoint` (`src/checkpoint.asl`, 8): `VFSCheckpoint`, `OutboxEntry`, `formatCheckpointAsn`, `parseCheckpointAsn`, `createVfsCheckpoint`, `createVfsCheckpointWithSeq`, `restoreVfsCheckpoint`, `extractBetween`.
- `aslMem/compact` (`src/compact.asl`, 6): `CompactRecord`, `encodeVectorFrame`, `serializeGraphNode`, `formatCompactRecord`, `formatCompactLedger`, `ensureQuoted`.
- `aslMem/consistencyAudit` (`src/consistencyAudit.asl`, 8): `ConsistencyDimension`, `ConsistencyReport`, `canonicalShortcode`, `verifyShortcodeBidirectional?`, `checkD52Completeness?`, `verifyRoadmapGate?`, `makeCleanReport`, `auditConsistencyState`.
- `aslMem/contextScoring` (`src/contextScoring.asl`, 9): `ContextScoreRecord`, `ActiveVolumeReport`, `makeContextRecord`, `calculateContextScore`, `penalizeUnreferencedMatches`, `evictRecordsBelowThreshold`, `calculateActiveVolume`, `isVolumeBounded?`, `reportActiveVolume`.
- `aslMem/driver` (`src/driver.asl`, 6): `VectorRecord`, `createRecord`, `RrfScore`, `sortRrfScores`, `fuseRanksRrf`, `reciprocalRankFusion`.
- `aslMem/egraph` (`src/egraph.asl`, 12): `ENode`, `EClass`, `EGraph`, `egraphNew`, `egraphFind`, `egraphAddNode`, `addEnode`, `egraphUnion`, `mergeEclasses`, `egraphRebuild`, `egraphExtract`, `egraphSaturate`.
- `aslMem/engine` (`src/engine.asl`, 13): `StorageMode`, `StorageConfig`, `MemoryEngine`, `EngineStats`, `makeEngine`, `enginePutVector`, `enginePutNode`, `enginePutEdge`, `engineDelNode`, `engineCheckpoint`, `engineApplyWalEntry`, `engineRecover`, `engineStats`.
- `aslMem/federatedMemory` (`src/federatedMemory.asl`, 5): `PackageScopedMemory`, `formatFederatedMemoryRecord`, `filterMemoriesByPackage`, `queryFederatedPackageMemory`, `discoverPackageMemories`.
- `aslMem/graph` (`src/graph.asl`, 18): `GraphNode`, `GraphEdge`, `KnowledgeGraph`, `ContradictionResult`, `KnowledgeGraphIndex`, `findNode`, `findOutgoingEdges`, `findNeighbors`, `isFresh?`, `resolveContradiction`, `addNode`, `addEdge`, `addNodesBatch`, `addEdgesBatch`, `removeNode`, `buildGraphIndex`, `findNodeFast`, `findNeighborsFast`.
- `aslMem/hydration` (`src/hydration.asl`, 11): `ContextBuffer`, `makeContextBuffer`, `checkCompressionThreshold`, `cascadeCompress`, `evictRawContext`, `defaultCoreAxioms`, `hydrateIntentSummary`, `synthesizeIntentSummary`, `defaultModernDecisions`, `hydrateModernIntent`, `nowMs`.
- `aslMem/math` (`src/math.asl`, 16): `sqrt`, `fastInvSqrt`, `vectorDot`, `vectorNorm`, `vectorCosineSim`, `cosineSimilarity`, `vectorAdd`, `vectorScale`, `vectorRelu`, `vectorSoftmax`, `bytesFromListF64!`, `bytesToListF64`, `vectorDotBytes`, `vectorNormBytes`, `vectorCosineSimBytes`, `fastLn`.
- `aslMem/migration` (`src/migration.asl`, 6): `PcpMigrationResult`, `migratePcpConstitution`, `serializeLedgerAsn`, `queryMemoryShortcode`, `benchmarkMemLatency`, `makeEmptyMigrationResult`.
- `aslMem/notes` (`src/notes.asl`, 12): `NoteRecord`, `makeNote`, `noteIsActive?`, `noteHasTag?`, `noteScopeMatches?`, `noteMatchesQuery?`, `formatNoteAsn`, `projectNoteMd`, `notePromoteToTask`, `notePromoteToAdr`, `noteCloseScope`, `notePruneBounded`.
- `opfsAdapter` (`src/opfsAdapter.asl`, 7): `initOpfsStorage`, `opfsWriteRecord`, `opfsReadRecord`, `opfsFlush`, `opfsListRecords`, `opfsDeleteRecord`, `OpfsStorageState`.
- `aslMem/paged` (`src/paged.asl`, 10): `MemoryTier`, `MemorySegment`, `PagedMemoryManager`, `makeSegment`, `makePagedManager`, `shouldPage?`, `touchSegment`, `evictOldest`, `loadSegment`, `isSegmentActive?`.
- `aslMem/pointer` (`src/pointer.asl`, 8): `BlobPointer`, `PerceptualFact`, `makeBlobPointer`, `formatPointerToken`, `extractScalarFact`, `formatPerceptualFact`, `formatPointerDescriptor`, `shouldOffload?`.
- `aslMem/pointerOrchestrator` (`src/pointerOrchestrator.asl`, 10): `PointerSpec`, `makePointerSpec`, `derefPointer`, `collapsePointer`, `rehydratePointer!`, `orchestrateContextPointers`, `formatPointerSpec`, `parsePointerSpec`, `totalActiveTokens`, `isContextMinimal?`.
- `aslMem/projection` (`src/projection.asl`, 8): `ProjectionState`, `makeProjectionState`, `hasEntity?`, `getEntityCount`, `getMetricTotal`, `replayWalEntry`, `replayWalBatch`, `extractIntField`.
- `aslMem/projector` (`src/projector.asl`, 12): `DualProjection`, `formatPhaseStatusRow`, `formatPlanItem`, `projectStatusMd`, `projectPlanMd`, `projectDualManifest`, `AdrConsequence`, `AdrRecord`, `makeAdr`, `formatConsequenceAsn`, `formatAdrAsn`, `projectAdrMd`.
- `aslMem/queryGuard` (`src/queryGuard.asl`, 18): `QueryGuardState`, `makeQueryGuard`, `makeQueryGuardWithLimits`, `recordHelpQuery`, `recordInvalidInvocation`, `recordEmptyInvocation`, `recordProductiveAction`, `recordProductiveActionWithAction`, `isTripped?`, `isTripped`, `remainingHelpBudget`, `remainingInvalidBudget`, `formatEscalationDiagnostic`, `formatEscalationDiagnosticWithReason`, `formatHelpBudget`, `formatCircuitWarning`, `resetQueryGuard`, `formatQueryGuardState`.
- `aslMem/records` (`src/records.asl`, 31): `ShortcodeType`, `Shortcode`, `AdrRule`, `RecordsLedger`, `ScanResult`, `makeShortcode`, `makeRule`, `makeLedger`, `makeScanResult`, `shortcodeTypeToString`, `stringToShortcodeType`, `isValidShortcode?`, `normalizeShortcode`, `scanShortcodes`, `findRule`, `queryRule`, `isInvariantRule?`, `checkInvariants`, and 13 more.
- `aslMem/refactorVfs` (`src/refactorVfs.asl`, 5): `RefactorPlan`, `stageRefactorDiff`, `previewTokenSavings`, `commitStagedRefactor`, `rollbackStagedRefactor`.
- `aslMem/research` (`src/research.asl`, 7): `ResearchFact`, `ResearchReport`, `ResearchQueryOutcome`, `makeResearchFact`, `makeResearchReport`, `queryResearchMemory`, `storeResearchFact`.
- `aslMem/ring` (`src/ring.asl`, 11): `OverflowPolicy`, `RingBuffer`, `RingPushResult`, `makeRingBuffer`, `ringPush`, `ringPeekRecent`, `ringPeekOldest`, `ringDrainAll`, `ringIsFull?`, `ringUtilization`, `ringEvictedCount`.
- `aslMem/roadmap` (`src/roadmap.asl`, 17): `ItemRecord`, `PhaseRecord`, `LeaseRecord`, `RoadmapRecord`, `ClaimResult`, `makeItem`, `makePhase`, `makeLease`, `makeRoadmap`, `isLeaseActive?`, `formatPhaseDefrecord`, `formatRoadmapAsn`, `phaseGet`, `phaseRegister`, `phaseClaim`, `itemComplete`, `phaseComplete`.
- `aslMem/rrf` (`src/rrf.asl`, 4): `RankedCandidate`, `computeRrfScore`, `fuseRankedChannels`, `hybridCodeSearch`.
- `aslMem/simhash` (`src/simhash.asl`, 6): `fnv1a64`, `simhash64`, `hammingDistance`, `simhashSimilarity`, `stripPunct`, `tokenizeWords`.
- `aslMem/snapshot` (`src/snapshot.asl`, 6): `SnapshotManifest`, `createSnapshotFrame`, `serializeVectorItem`, `serializeGraphNodeFrame`, `serializeGraphEdge`, `formatSnapshotLedger`.
- `aslMem/speculativeFork` (`src/speculativeFork.asl`, 6): `SpeculativeMutant`, `SpeculativeFuzzResult`, `createSpeculativeMutant`, `forkMutantCluster`, `evaluateMutantSurvival`, `summarizeFuzzRun`.
- `aslMem/spoolSearch` (`src/spoolSearch.asl`, 5): `SpoolMatch`, `spoolIndexLines`, `spoolQueryBm25`, `spoolSearchIndex`, `formatSpoolMatches`.
- `sqliteAdapter` (`src/sqliteAdapter.asl`, 9): `initSqliteStorage`, `hasTable?`, `sqliteWriteRecord`, `sqliteReadRecord`, `sqliteQueryRecords`, `sqliteDeleteRecord`, `makeEmptyRow`, `SqliteStorageState`, `SqliteRow`.
- `aslMem/stm` (`src/stm.asl`, 11): `STMFileSnapshot`, `STMTransaction`, `STMCommitResult`, `stmBegin`, `stmRead`, `stmWrite!`, `stmRollback`, `stmValidateAndMerge`, `stmGetSnapshot`, `stmDirtyFiles`, `stmRebase`.
- `aslMem/storageFile` (`src/storageFile.asl`, 9): `OpfsStorage`, `makeOpfsStorage`, `getRootPrefix`, `isLockedBy?`, `isLocked?`, `acquireWebLock`, `releaseWebLock`, `opfsWrite`, `opfsRead`.
- `aslMem/store` (`src/store.asl`, 12): `VectorItem`, `VectorStore`, `VectorSlab`, `makeVectorSlab`, `slabSlotOffset`, `slabInsert`, `sqrtApprox`, `dot`, `normalizeVector`, `dotNormalized`, `validateVectorDim`, `safeInsertItem`.
- `aslMem/structuralEditor` (`src/structuralEditor.asl`, 7): `ASTTransform`, `rewriteAstNode`, `isStubBody?`, `scaffoldModule`, `scaffoldTest`, `scaffoldFn`, `isBalancedDelimiters?`.
- `aslMem/subtreeCache` (`src/subtreeCache.asl`, 5): `SubtreeEntry`, `SubtreeCache`, `indexSubtrees`, `lookupSubtree`, `reconcileIncrementalDiff`.
- `aslMem/summarySearch` (`src/summarySearch.asl`, 4): `SummaryIndex`, `summaryIndexEmpty`, `indexChunkSummary`, `searchChunksBySummary`.
- `aslMem/taskLease` (`src/taskLease.asl`, 11): `SessionLease`, `makeSessionLease`, `renewSessionLease`, `isLeaseExpired?`, `stealExpiredLease`, `formatLeaseAsn`, `make`, `renew`, `expired?`, `steal`, `formatLease`.
- `aslMem/taskRecovery` (`src/taskRecovery.asl`, 11): `RecoverySnapshot`, `recoverTaskSession`, `resumeActionDag`, `extractHandoffState`, `verifyCheckpointIntegrity`, `formatRecoveryAsn`, `snapshot`, `resume`, `extract`, `verify`, `formatRecovery`.
- `aslMem/tasks` (`src/tasks.asl`, 48): `TaskReceipt`, `AnticipatedRisk`, `TaskTolerance`, `TaskRecord`, `PostAction`, `PostActionQueue`, `makeTaskReceipt`, `receiptIsVerified?`, `formatReceiptAsn`, `makeHolisticTask`, `makeTask`, `makeGapTask`, `makeCyberneticTask`, `taskOwnsFile?`, `taskOwnsIntersect?`, `taskOverlapFiles`, `taskOverlapBlastRadius?`, `taskDependenciesSatisfied?`, and 30 more.
- `aslMem/tasksDag` (`src/tasksDag.asl`, 8): `taskOwnsFile?`, `taskOwnsIntersect?`, `taskOverlapFiles`, `taskOverlapBlastRadius?`, `taskDependenciesSatisfied?`, `taskParallelEligible?`, `taskIsReady?`, `taskFindReady`.
- `aslMem/tasksLease` (`src/tasksLease.asl`, 13): `taskClaim`, `taskClaimSession`, `taskIsClaimedBy?`, `taskIsLeaseExpired?`, `taskRecoverSession`, `taskSpawnSubtask`, `taskStart`, `taskAdvanceStep`, `taskCaptureHandoff`, `taskAttachReceipt`, `taskComplete`, `claim`, `settle`.
- `aslMem/tasksStore` (`src/tasksStore.asl`, 27): `TaskReceipt`, `AnticipatedRisk`, `TaskTolerance`, `TaskRecord`, `makeTaskReceipt`, `receiptIsVerified?`, `formatReceiptAsn`, `makeAnticipatedRisk`, `makeTaskTolerance`, `taskIsWithinLeeway?`, `taskHasEscalationTrigger?`, `formatAnticipatedRiskAsn`, `formatTaskToleranceAsn`, `makeHolisticTask`, `makeTask`, `makeGapTask`, `makeCyberneticTask`, `taskFormatAsn`, and 9 more.
- `aslMem/telemetry` (`src/telemetry.asl`, 4): `TelemetryRecord`, `formatTelemetryEntry`, `parseTelemetryEntry`, `streamStepTelemetry`.
- `aslMem/testRunner` (`src/testRunner.asl`, 3): `SandboxResult`, `runSandboxedTest`, `createSandboxOverlay`.
- `aslMem/tokenRegex` (`src/tokenRegex.asl`, 8): `TokenPattern`, `TokenMatchResult`, `TokenMatcher`, `compileTokenPattern`, `matchTokenStream`, `scanTokenStream`, `findTokenSubsequences`, `tokenizePattern`.
- `aslMem/vfs` (`src/vfs.asl`, 37): `VFSBuffer`, `VFSRegistry`, `makeVFSRegistry`, `vfsInit`, `vfs-init`, `vfs-read`, `vfs-write`, `vfsCasHash`, `vfs-cas-hash`, `vfs-cas-update`, `vfs-discard`, `vfs-flush`, `vfs-acquire-lease`, `vfs-release-lease`, `vfs-staged-write`, `vfs-fenced-staged-write`, `normalizePath`, `norm`, and 19 more.
- `aslMem/vfsFork` (`src/vfsFork.asl`, 9): `CompensatingAction`, `VFSBranch`, `forkVfsBranch`, `forkVfsBranchWithCausal`, `writeBranchBuffer`, `registerCompensation`, `commitBranch!`, `abortBranch`, `branchDiff`.
- `aslMem/vfsMerge` (`src/vfsMerge.asl`, 6): `AstMergeResult`, `CausalMergeResult`, `ast3wayMerge`, `mergeDisjointForms`, `formatAstConflict`, `mergeCausalBranchIntent`.
- `aslMem/vfsSync` (`src/vfsSync.asl`, 7): `VFSSyncState`, `makeSyncState`, `detectDiskDrift`, `validateFlushSafety`, `updateStagedHash`, `recordFlushSuccess`, `resolveSyncAction`.
- `aslMem/viewLayer` (`src/viewLayer.asl`, 4): `MemoryChunk`, `makeMemoryChunk`, `hydrateToMarkdown`, `renderSummaryCard`.
- `aslMem/visibilityScope` (`src/visibilityScope.asl`, 8): `VisibilityTier`, `VisibilityContext`, `makeVisibilityContext`, `isGlobalAslAnchor?`, `resolveVisibilityTier`, `filterVisibleWorktrees`, `filterVisibleSessions`, `filterVisibleRepos`.
- `aslMem/wal` (`src/wal.asl`, 20): `WalOpType`, `WalEntry`, `WalState`, `WalStreamResult`, `makeWalEntry`, `computeWalChecksum`, `makeWalState`, `appendWalEntry`, `formatWalFrame`, `parseWalFrame`, `parseWalStream`, `parseWalStreamStrict`, `isWalSuccess?`, `isWalGap?`, `isWalCorrupt?`, `walDrainUnflushed`, `walRollbackUnflushed`, `walCheckpointMarker`, and 2 more.
- `wasmRuntime` (`src/wasmRuntime.asl`, 5): `initWasmRuntime`, `growLinearMemory`, `writeLinearMemory`, `readLinearMemory`, `WasmRuntimeState`.
- `aslMem/worklist` (`src/worklist.asl`, 11): `WorklistEntry`, `Worklist`, `makeWorklistEntry`, `worklistCreate`, `worklistCursorNext`, `worklistClaimBatch`, `worklistMarkDone`, `worklistMarkSkipped`, `worklistFindEntry`, `worklistIsComplete?`, `worklistFormatAsn`.
- `aslMem/xref` (`src/xref.asl`, 11): `XRefEdge`, `XRefGraph`, `makeXrefGraph`, `listAddUnique`, `xrefAddEdge`, `findDependents`, `findPrerequisites`, `findProvenance`, `xrefForwardEdges`, `xrefBackwardEdges`, `xrefHasNode?`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-mem/tests/<file>.asl
```

43 of 47 test files exit 0 (1339 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `adrTest.asl` | pass | 21 assertions |
| `amnesiaTest.asl` | pass | 26 assertions |
| `astFilterTest.asl` | pass | 28 assertions |
| `astMergeTest.asl` | pass | 33 assertions |
| `bm25Test.asl` | pass | 17 assertions |
| `checkpointTest.asl` | pass | 25 assertions |
| `compactTest.asl` | pass | 4 assertions |
| `consistencyAuditTest.asl` | pass | 18 assertions |
| `egraphTest.asl` | pass | 32 assertions |
| `engineTest.asl` | pass | 28 assertions |
| `federatedMemoryTest.asl` | pass | 20 assertions, 8 refutations |
| `hybridSearchTest.asl` | **fail** | load error: imports `aslHarness/promptCache`; `asl-harness` in this checkout has only `src/launch.asl` |
| `hydrationTest.asl` | pass | 72 assertions |
| `mathTest.asl` | pass | 27 assertions |
| `memTest.asl` | pass | 22 assertions |
| `migrationTest.asl` | pass | 11 assertions |
| `notesScopeTest.asl` | pass | 25 assertions |
| `notesTest.asl` | pass | 25 assertions |
| `opfsAdapterTest.asl` | pass | 26 assertions, 15 refutations |
| `pagedTest.asl` | pass | 4 assertions |
| `pointerOrchestratorTest.asl` | **fail** | load error: imports `aslHarness/contextPriority`, which this checkout's `asl-harness` lacks |
| `pointerTest.asl` | pass | 18 assertions |
| `queryGuardTest.asl` | pass | 90 assertions |
| `recordsTest.asl` | pass | 6 assertions |
| `refactorVfsTest.asl` | pass | 25 assertions |
| `researchTest.asl` | pass | 17 assertions |
| `ringTest.asl` | pass | 14 assertions |
| `roadmapTest.asl` | pass | 36 assertions |
| `snapshotTest.asl` | pass | 5 assertions |
| `speculativeForkTest.asl` | pass | 13 assertions |
| `spoolSearchTest.asl` | pass | 21 assertions |
| `sqliteAdapterTest.asl` | pass | 46 assertions, 30 refutations |
| `stmTest.asl` | pass | 28 assertions |
| `taskLeaseTest.asl` | pass | 50 assertions |
| `taskModularTest.asl` | pass | 19 assertions |
| `taskRecoveryTest.asl` | pass | 43 assertions |
| `tasksContingencyTest.asl` | pass | 29 assertions |
| `tasksTest.asl` | pass | 167 assertions |
| `tokenRegexTest.asl` | pass | 35 assertions |
| `vfsForkTest.asl` | pass | 33 assertions |
| `vfsSyncTest.asl` | **fail** | load error: imports `aslHarness/slmProfile`, which this checkout's `asl-harness` lacks |
| `vfsTest.asl` | pass | 43 assertions |
| `visibilityScopeTest.asl` | pass | 19 assertions |
| `walTest.asl` | pass | 11 assertions |
| `wasmRuntimeTest.asl` | pass | 27 assertions, 15 refutations |
| `worklistTest.asl` | **fail** | runtime error `ERR_MATCH_NONEXHAUSTIVE` on a worklist batch record |
| `xrefTest.asl` | pass | 12 assertions |
