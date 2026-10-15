# asl-agent-bus (package `aslAgentBus`)

ASL records and pure functions for passing messages between agents: bus envelopes and a priority queue with leases, acks and a dead-letter count; wire-frame encoders and decoders for stdio, Unix-socket, HTTP and SSE framing; newline-delimited ASN (`ndAsn`); a ring buffer; mesh routing tables, peer registries and buffer leases; swarm presence and path claims; an MVCC message log; and process telemetry rows.

The modules build and transform values. None of them opens a socket, listens on a port or keeps a process running: `networkBridge` stores a peer's socket number as an integer field, and the `encode*Frame`/`decode*Frame` functions produce and parse text. There is no `bus serve` or `bus send` command.

Module names use the prefix `aslAgentBus/`. `manifest.asn` lists the same 18 modules and declares dependencies on `asl-contracts`, `asl-text` and `asl-agent-core`. On 2026-10-14 all 18 files in `src/` pass `asl/host/out/asl-host check`.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 18 modules, 315 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslAgentBus/ambient` (`src/ambient.asl`, 4): `AmbientFrame`, `createAmbientFrame`, `validateAmbientFrame`, `encodeAmbientAsn`.
- `aslAgentBus/asnlRing` (`src/asnlRing.asl`, 13): `AsnlPointer`, `AsnlRingBuffer`, `makeRingBuffer`, `makeAsnlPointer`, `isPointerValid?`, `isRingEmpty?`, `isRingFull?`, `ringPush`, `ringPushPointer`, `ringPop`, `ringPeek`, `ringDrain`, `formatRingStats`.
- `aslAgentBus/bridge` (`src/bridge.asl`, 5): `ExternalToolCommand`, `bridgeConnectExternal`, `formatExternalToolSchema`, `dispatchExternalCommand`, `makeBridgeEvent`.
- `aslAgentBus/browserBridge` (`src/browserBridge.asl`, 15): `BridgeTab`, `BridgeCommand`, `BrowserBridgeState`, `BrowserBridgeTraceFrame`, `bridgeInit`, `bridgeRegisterTab`, `bridgeEnqueueCommand`, `bridgePollCommands`, `bridgeCompleteCommand`, `formatCorsHttpResponse`, `isBridgeOpfsPathSafe?`, `emitBrowserTraceFrame`, `queryBrowserBridgeCapability`, `makeBrowserBridgeTraceFrame`, `convertBrowserFrameToMesh`.
- `aslAgentBus/bus` (`src/bus.asl`, 53): `AgentMessage`, `BusEnvelope`, `makeBusEnvelope`, `makeSequencedBusEnvelope`, `validateBusCasEpoch`, `BusEvent`, `formatSseEvent`, `isBroadcast`, `BusChannel`, `TaskLifecycleState`, `BusReceipt`, `ConditionWake`, `dispatchBusEvent`, `queryBusEvents`, `pullBusEvents`, `makeConditionWake`, `evalConditionWake`, `makeLifecycleEvent`, and 35 more.
- `aslAgentBus/cluster` (`src/cluster.asl`, 28): `NodeState`, `WorkerNode`, `ClusterPool`, `OpKind`, `ClusterFrame`, `packKeys`, `unpackKeys`, `packDag`, `poolCreate`, `poolAdd`, `poolSelect`, `dispatchTask`, `makeReceipt`, `workerIdle?`, `RelayLease`, `RelayLeaseRegistry`, `TaskPartition`, `createRelayLeaseRegistry`, and 10 more.
- `aslAgentBus/gateway` (`src/gateway.asl`, 14): `GatewayChannel`, `MultiplexedFrame`, `GatewayInspectionVerdict`, `demuxStreamContent`, `detectEshViolation`, `calculateLcsGrounding`, `inspectGatewayTurn`, `formatGatewayVerdict`, `isAsnToolCall?`, `formatAsnProtocolHeaders`, `adaptAnthropicRequest`, `formatAnthropicResponse`, `proxyContractToMesh`, `validateRelayWritePermission`.
- `aslAgentBus/mesh` (`src/mesh.asl`, 52): `MeshNode`, `RoutingTable`, `TransportProtocol`, `createRoutingTable`, `registerMeshNode`, `routePacket`, `isNodeAlive`, `TaskConstraint`, `TaskContract`, `makeTaskConstraint`, `makeTaskContract`, `delegateContract`, `ControlSignalFrame`, `makeControlSignal`, `formatControlSignal`, `ComputeTier`, `tierEdge`, `tierFog`, and 34 more.
- `aslAgentBus/mvccBus` (`src/mvccBus.asl`, 13): `CausalMessage`, `IntentConflict`, `MergedIntent`, `MvccBus`, `mvccBusCreate`, `mvccBusPublish`, `mvccBusGetMessage`, `mvccBusFindHeads`, `mvccBusMergeIntents`, `formatMergedIntent`, `extractPayloadFacts`, `mergeFactLists`, `detectIntentContradiction`.
- `aslAgentBus/ndAsn` (`src/ndAsn.asl`, 10): `NDASNFrame`, `ndAsnFrame`, `ndAsnSerialize`, `ndAsnSerializeSingle`, `serializeWireFrame`, `ndAsnDeserialize`, `ndAsnParseLines`, `ndAsnMakeToolcall`, `ndAsnEvalPayload`, `ndAsnDeserializeSingle`.
- `aslAgentBus/networkBridge` (`src/networkBridge.asl`, 8): `RemotePeer`, `NetworkBridge`, `makeNetworkBridge`, `bridgeRegisterPeer`, `bridgeSendRemote`, `bridgeReceiveRemote`, `isPeerRegistered?`, `getPeerCount`.
- `aslAgentBus/presence` (`src/presence.asl`, 21): `AgentStatus`, `ClaimMode`, `PathClaim`, `SwarmPeer`, `SwarmRoom`, `NegotiationKind`, `NegotiationOffer`, `createSwarmRoom`, `joinSwarmRoom`, `leaveSwarmRoom`, `listRoomPeers`, `findPeerInRoom`, `claimPath`, `releaseClaim`, `isClaimExpired?`, `proposeTask`, `acceptTask`, `declineTask`, and 3 more.
- `aslAgentBus/procTelemetry` (`src/procTelemetry.asl`, 16): `ProcDescriptor`, `ProcRegistry`, `ProcTelemetryEvent`, `makeProcLocus`, `makeProcDescriptor`, `emptyProcRegistry`, `recordProcTelemetry`, `removeProcTelemetry`, `updateProcLocus`, `calculateProcElapsed`, `serializeProcPsEntry`, `serializeProcRegistryPs`, `serializeProcTop`, `auditProcHealth`, `filterProcsByLane`, `findProcById`.
- `aslAgentBus/toolPlane` (`src/toolPlane.asl`, 8): `ToolRouter`, `makeToolRouter`, `registerToolRunbook`, `getToolRunbook`, `getToolGuidance`, `isToolEligible?`, `routeTools`, `countRoutedTools`.
- `aslAgentBus/transport` (`src/transport.asl`, 14): `TransportFrameType`, `TransportState`, `TransportEnvelope`, `TransportSession`, `makeTransportEnvelope`, `initTransportSession`, `sessionRecordSent`, `sessionRecordReceived`, `sessionSetState`, `isSessionActive?`, `formatFrameHeader`, `validateTransportEnvelope`, `envelope->canonicalWireFrame`, `canonicalWireFrame->envelope`.
- `aslAgentBus/transportPatch` (`src/transportPatch.asl`, 5): `serializeFrameType`, `parseFrameType`, `envelope->canonicalWireFrame`, `getPart`, `canonicalWireFrame->envelope`.
- `aslAgentBus/types` (`src/types.asl`, 11): `AgentMessage`, `ToolParam`, `ToolDef`, `ToolArg`, `ToolCall`, `ToolInvocation`, `ToolResult`, `makeAgentMessage`, `makeToolDef`, `makeToolCall`, `makeToolResult`.
- `aslAgentBus/wire` (`src/wire.asl`, 25): `CodecKind`, `CompressionAlgo`, `WireFrame`, `createWireFrame`, `compactWirePayload`, `expandWirePayload`, `encodeWireFrame`, `decodeWireFrame`, `unpackWireFrame`, `isCompressed?`, `CanonicalWireFrame`, `WireValidationResult`, `validateWireFrame`, `encodeCanonicalFrame`, `decodeCanonicalFrame`, `encodeStdioFrame`, `decodeStdioFrame`, `encodeUnixSocketFrame`, and 7 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-agent-bus/tests/<file>.asl
```

18 of 19 test files exit 0 (496 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `ambientTest.asl` | pass | 50 assertions |
| `asnlRingTest.asl` | **fail** | runs `./bin/asl check`, and there is no `bin/asl` |
| `backpressureTest.asl` | pass | 5 assertions, 2 refutations |
| `bridgeTest.asl` | pass | 1 assertions |
| `browserBridgeTest.asl` | pass | 18 assertions |
| `busTest.asl` | pass | 25 assertions |
| `clusterTest.asl` | pass | 24 assertions |
| `gatewayTest.asl` | pass | 60 assertions |
| `meshOrchestrationTest.asl` | pass | 9 assertions, 2 refutations |
| `meshTest.asl` | pass | 40 assertions |
| `mvccBusTest.asl` | pass | 28 assertions |
| `ndAsnTest.asl` | pass | 31 assertions |
| `networkBridgeTest.asl` | pass | 22 assertions, 9 refutations |
| `presenceTest.asl` | pass | 24 assertions |
| `priorityBusTest.asl` | pass | 35 assertions, 16 refutations |
| `procTelemetryTest.asl` | pass | 32 assertions |
| `toolPlaneTest.asl` | pass | 16 assertions |
| `transportTest.asl` | pass | 18 assertions |
| `wireTest.asl` | pass | 29 assertions |
