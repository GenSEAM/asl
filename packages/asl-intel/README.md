# asl-intel

Code intelligence for an ASL workspace: module outlines, symbol queries, callers and impact, coupling, dead code, vacuous tests, stub bodies, a module graph, complexity, traces, idiom lint and a combined "vitality" audit, plus a symbol graph, cross-references, health anomalies, file placement checks, Mermaid/ASN diagrams and preload ranking for context building.

The package has two module families:
- `asl-intel/...` (and the entry module `asl-intel` in `src/main.asl`): the analyzers behind the command line, with their own text, regex (`rx`), JSON, string-table and host helpers (`host` wraps `git ls-files`, file walks and reads).
- `aslIntel/...`: the graph and navigation library (`extractor`, `symbolGraph`, `query`, `xref`, `health`, `diagram`, `preload`, `placement`, `hotspotCoverage`, `stmBridge`, `textScan`, `codec`, `intel`).

## Command line

`src/main.asl` exports `main`. Run it with the host from the directory that contains the files to analyse:

```sh
asl/host/out/asl-host run asl/packages/asl-intel/src/main.asl outline asl/packages/asl-regex/src/regex.asl
```

On 2026-10-14 this printed an `(:outline :status :ok :file ... :module "asl-regex/regex" :itemsCount 57 :items [...])` form. With no arguments it prints the usage: `asl-intel <coupling|impact|outline|query|deadcode|vacuity|sweep|graph|complexity|stubs|vitality|lint> [options]`; most subcommands take `--summary`, `--json` or `--asn`. There is no `asl intel` command.

All 33 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14). `manifest.asn` lists 32 modules; `asl-intel/lintOp` (`src/lintOp.asl`) is missing from it.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 33 modules, 450 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslIntel/codec` (`src/codec.asl`, 4): `encodeSymbolAsn`, `encodeEdgeAsn`, `encodeImpactAsn`, `encodeAsnResponse`.
- `asl-intel/complexity` (`src/complexity.asl`, 4): `ComplexityMetrics`, `ModuleComplexity`, `analyzeComplexity!`, `runComplexity!`.
- `asl-intel/coupling` (`src/coupling.asl`, 14): `ModInfo`, `PkgInfo`, `Scan`, `CouplingResult`, `scanCodebase!`, `analyzeCoupling`, `formatCouplingAsn`, `formatCouplingSummary`, `couplingJson`, `runCoupling!`, `firstGroup`, `allGroups`, `ghostCount`, `cycleCount`.
- `asl-intel/deadcode` (`src/deadcode.asl`, 7): `DeadCodeSummary`, `analyzeDeadcode!`, `deadcodeJson`, `formatDeadcodeAsn`, `formatDeadcodeSummary`, `runDeadcode!`, `walkIgnoring!`.
- `aslIntel/diagram` (`src/diagram.asl`, 9): `DiagramFormat`, `diagramFormatMermaid`, `diagramFormatAsn`, `diagramFormatToString`, `generateMermaidDiagram`, `generateAsnDiagram`, `generateDiagram`, `renderMermaidDag`, `renderAsnDag`.
- `aslIntel/extractor` (`src/extractor.asl`, 18): `SymbolKind`, `symFn`, `symType`, `symRecord`, `symEnum`, `symMethod`, `symClass`, `symInterface`, `symVariable`, `SymbolDef`, `SymbolRef`, `FileSymbols`, `kindToString`, `stringToKind`, `parseAslTokens`, `extractAslSymbols`, `extractGenericSymbols`, `filterExported`.
- `asl-intel/fixture` (`src/fixture.asl`, 8): `Asn`, `readAsn`, `kwArg`, `kwStr`, `kwInt`, `kwItems`, `kwKw`, `headKw`.
- `asl-intel/graph` (`src/graph.asl`, 12): `GraphNode`, `Graph`, `Rated`, `GraphSummary`, `resolveWorkspace!`, `buildGraph!`, `analyzeGraph!`, `analyzeGraphAt!`, `ratedJson`, `runGraph!`, `fl`, `flag`.
- `aslIntel/health` (`src/health.asl`, 35): `HealthAnomalyKind`, `anomalyCycle`, `anomalyBlastRadius`, `anomalyOrphanExport`, `anomalySignatureMismatch`, `anomalyComplexityHotspot`, `anomalyLayerLeakage`, `anomalyBrokenReference`, `anomalyDanglingPointer`, `anomalyTokenPenalty`, `anomalyUncompensatedSaga`, `HealthAnomaly`, `HealthMatrix`, `RefEdge`, `MultidimensionalHealthReport`, `healthAnomalyKindToString`, `detectImportCycles`, `detectBlastRadiusHotspots`, and 17 more.
- `asl-intel/host` (`src/host.asl`, 15): `Ctx`, `RunOut`, `Tree`, `Outcome`, `outcome`, `runCapture!`, `gitLsFiles!`, `findTree!`, `walkFiles!`, `globFiles!`, `readText!`, `isDir?`, `isFile?`, `isLink?`, `listSorted!`.
- `aslIntel/hotspotCoverage` (`src/hotspotCoverage.asl`, 20): `HotspotTarget`, `PlannedTraversal`, `ActualVisit`, `ActualCoverage`, `CoverageGap`, `CoverageComparison`, `createHotspotTarget`, `createPlannedTraversal`, `planAddTarget`, `planTargetCount`, `recordVisit`, `createActualCoverage`, `coverageAddVisit`, `coverageVisitCount`, `isTargetVisited?`, `findGaps`, `calculateDrift`, `compareTraversalPaths`, and 2 more.
- `aslIntel/intel` (`src/intel.asl`, 11): `intelVersion`, `intelBanner`, `intelHealth`, `buildHealthMatrix`, `formatHealthReport`, `renderMermaidDag`, `renderAsnDag`, `generateMermaidDiagram`, `generateAsnDiagram`, `generateDiagram`, `auditFilePlacement`.
- `asl-intel/json` (`src/json.asl`, 11): `Json`, `jNull`, `jBool`, `jInt`, `jFloat`, `jStr`, `jArr`, `jObj`, `jStrs`, `dumps`, `jsonString`.
- `asl-intel/lintOp` (`src/lintOp.asl`, 4): `LintRow`, `lintHitsForFile!`, `lintTree!`, `runLint!`.
- `asl-intel` (`src/main.asl`, 5): `runIntel!`, `dispatchIntel!`, `makeCtx!`, `makeCtxFor!`, `main`.
- `asl-intel/model` (`src/model.asl`, 4): `OutlineItem`, `ModuleOutline`, `makeOutlineItem`, `makeModuleOutline`.
- `asl-intel/pats` (`src/pats.asl`, 29): `lit`, `ws0!`, `ws1!`, `idRun!`, `patModuleId!`, `patModuleIdNoDot!`, `patExports!`, `patImportsBlock!`, `patImportName!`, `patFnParen!`, `patFnNewline!`, `patSchemaParen!`, `patMacroParen!`, `patSchemaLine!`, `patMacroLine!`, `patPackage!`, `patEntry!`, `patDepsBlock!`, and 11 more.
- `aslIntel/placement` (`src/placement.asl`, 1): `auditFilePlacement`.
- `aslIntel/preload` (`src/preload.asl`, 43): `PreloadTier`, `tierMicroAst`, `tierMesoSymbol`, `tierMacroTopology`, `SymbolStub`, `PreloadedHorizon`, `preloadTierToString`, `estimateStubTokens`, `stubCreate`, `horizonCreate`, `horizonAddStub`, `extractShortName`, `makeNodeFromSymbol`, `makeEdgeFromRef`, `hydrateGraphInto`, `hydrateGraphFromFileSymbols`, `hydrateGraphFromSources`, `hydrateGraphFromFiles!`, and 25 more.
- `aslIntel/query` (`src/query.asl`, 16): `QueryKind`, `qSearch`, `qCallers`, `qCallees`, `qImpact`, `qAffected`, `qContext`, `ImpactItem`, `QueryResult`, `formatQueryKind`, `filterByDepth`, `makeQueryResult`, `queryCallers`, `queryCallees`, `queryImpact`, `bfsImpact`.
- `asl-intel/rx` (`src/rx.asl`, 33): `Cls`, `Rx`, `Rex`, `clsSet!`, `clsNot!`, `clsAny`, `clsSpace!`, `clsSetSpace!`, `rxLit`, `rxLitI`, `rxOne`, `rxRep`, `rxSeq`, `rxAlt`, `rxOpt`, `rxGroup`, `rxBol`, `rxBos`, and 15 more.
- `asl-intel/search` (`src/search.asl`, 3): `analyzeImpact!`, `extractOutline!`, `querySymbols!`.
- `aslIntel/stmBridge` (`src/stmBridge.asl`, 4): `OverlaySymbolGraph`, `buildStmOverlay`, `overlayFind`, `overlayIncoming`.
- `asl-intel/stubs` (`src/stubs.asl`, 17): `Header`, `StubFinding`, `StubSummary`, `parenTrim`, `constSpan?`, `headersOf!`, `headerParams`, `constantBody?`, `paramsUnused?`, `placeholder?`, `trackedAsl!`, `analyzeStubs!`, `stubsJson`, `stubJson`, `formatStubsAsn`, `formatStubsSummary`, `runStubs!`.
- `asl-intel/sweep` (`src/sweep.asl`, 5): `Sweep`, `sweepMonorepo!`, `balanceError`, `pyOsError`, `runSweep!`.
- `aslIntel/symbolGraph` (`src/symbolGraph.asl`, 18): `EdgeKind`, `edgeCalls`, `edgeDefines`, `edgeImports`, `edgeImplements`, `edgeSubtypes`, `GraphNode`, `GraphEdge`, `SymbolGraph`, `edgeKindToString`, `graphCreate`, `graphAddNode`, `graphAddEdge`, `graphNodeCount`, `graphEdgeCount`, `graphIncoming`, `graphOutgoing`, `graphFind`.
- `asl-intel/tab` (`src/tab.asl`, 13): `Strtab`, `strtabNew`, `intern!`, `lookup`, `internStr!`, `lookupStr`, `strtabCount`, `ivNew`, `ivGet`, `ivSet!`, `ivAdd!`, `sortWith`, `sortPairsByInt`.
- `asl-intel/text` (`src/text.asl`, 51): `byteAt`, `spaceLen`, `isSpaceByte`, `utf8Len`, `cpAt`, `cpStartBefore`, `isWordCp`, `wordBefore?`, `wordAt?`, `isWordByteAscii`, `cpLength`, `cpPrefix`, `concatAll`, `joinWith`, `padRight`, `padLeft`, `lowerAscii`, `upperAscii`, and 33 more.
- `aslIntel/textScan` (`src/textScan.asl`, 8): `TextSection`, `TextDocOutline`, `TextMatchSlice`, `scanDocOutline`, `extractDocSection`, `searchDocSnippets`, `formatDocOutlineAsn`, `formatSectionAsn`.
- `asl-intel/trace` (`src/trace.asl`, 6): `TraceSummary`, `analyzeTrace!`, `traceJson`, `formatTraceAsn`, `formatTraceSummary`, `runTrace!`.
- `asl-intel/vacuity` (`src/vacuity.asl`, 6): `VacuitySummary`, `analyzeVacuity!`, `vacuityJson`, `formatVacuityAsn`, `formatVacuitySummary`, `runVacuity!`.
- `asl-intel/vitality` (`src/vitality.asl`, 6): `VitalityResult`, `runVitalityAudit!`, `vitalityJson`, `formatVitalityAsn`, `formatVitalitySummary`, `runVitality!`.
- `aslIntel/xref` (`src/xref.asl`, 10): `RefTarget`, `CrossReference`, `stripRefPrefix`, `cleanRefToken`, `parseRefUri`, `formatRefUri`, `refTargetEq?`, `refTargetToString`, `extractDocstringRefs`, `isSupportedLanguage?`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-intel/tests/<file>.asl
```

14 of 16 test files exit 0 (323 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `boundaryTest.asl` | pass | 27 assertions |
| `cliTest.asl` | pass | 12 assertions |
| `codeIntelTest.asl` | pass | 12 assertions |
| `contextBanditTest.asl` | pass | 14 assertions, 5 refutations |
| `diagramTest.asl` | pass | 24 assertions |
| `healthTest.asl` | pass | 26 assertions |
| `hotspotCoverageTest.asl` | pass | 18 assertions |
| `intelParityTest.asl` | **fail** | needs the parent monorepo: reads `tests/parity/intel/intelParityFixtures.asn` |
| `intelTest.asl` | pass | 41 assertions, 2 refutations |
| `lintOpTest.asl` | pass | 14 assertions |
| `placementTest.asl` | pass | 4 assertions |
| `preloadRankingTest.asl` | **fail** | runs `./bin/asl check`, and there is no `bin/asl` |
| `preloadTest.asl` | pass | 51 assertions |
| `queryTest.asl` | pass | 13 assertions |
| `textScanTest.asl` | pass | 11 assertions |
| `xrefTest.asl` | pass | 49 assertions |
