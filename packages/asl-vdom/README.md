# asl-vdom (package `aslVdom`)

ASL virtual DOM as values: node constructors, keyed and indexed diffing, accessibility-tree downsampling, and generators that print a node tree as source text for other UI frameworks. Also signals, a reducer store with patches, design tokens, and diagram and SVG rendering.

- `vdom.asl`: `VNode`, constructors (`elem`, `el`, `text`, `comp`), diffing (`DomDiff`, `MutationRecord`), accessibility nodes (`AXNode`).
- `html.asl`: HTML element constructors (`div`, `button`, `card`, ...) and attribute helpers.
- `polyglot.asl`: `emitReactTsx`, `emitVueSfc`, `emitSvelteComponent`, `emitSsrHtml`, `emitSwiftuiView`, `emitComposeComposable`, `compileComponent`. `emitJsx.asl`: React TSX modules.
- `signals.asl`, `state.asl`, `stateBridge.asl`: signals, computed values and effects; a reducer store with patches and diffs; a bridge from native UI events to store actions.
- `theme.asl`, `ui.asl`: design tokens and button/card/list/modal components with validity checks.
- `perception.asl` (accessibility frames and `downsampleTree`), `asnSvg.asl` (ASN to SVG), `diagram.asl` (Mermaid and HTML diagrams), `physicsReactor.asl` (force-layout primitives).

The output is source text and data; nothing in the package touches a live DOM, and no module reads or writes files.

Module names use the prefix `aslVdom/`; `manifest.asn` lists the same 13 modules and declares no dependencies. All 13 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 13 modules, 277 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslVdom/asnSvg` (`src/asnSvg.asl`, 9): `SvgNode`, `SvgResult`, `asnToSvg`, `parseAllChildren`, `extractFormsByTag`, `renderCircle`, `renderPath`, `renderPolygon`, `renderRect`.
- `aslVdom/diagram` (`src/diagram.asl`, 14): `DiagramNode`, `DiagramEdge`, `DiagramSubgraph`, `Diagram`, `makeDiagramNode`, `makeDiagramEdge`, `makeDiagramSubgraph`, `makeDiagram`, `formatNode`, `formatEdge`, `formatSubgraph`, `diagramToMermaid`, `mermaidToHtml`, `diagramToHtml`.
- `aslVdom/emitJsx` (`src/emitJsx.asl`, 7): `emitVnodeJsx`, `emitJsxAttrs`, `emitComponent`, `emitTsxModule`, `jsxAttrKey`, `isComponentTag?`, `indentSpaces`.
- `aslVdom/html` (`src/html.asl`, 91): `Props`, `makeProps`, `propsToAttrs`, `attrsEmpty`, `attr`, `attrClass`, `attrId`, `attrType`, `attrValue`, `attrName`, `attrPlaceholder`, `attrHref`, `attrSrc`, `attrAlt`, `attrsOf`, `withAttr`, `withClass`, `div`, and 73 more.
- `aslVdom/perception` (`src/perception.asl`, 3): `AXFrame`, `makeAxFrame`, `downsampleTree`.
- `aslVdom/physicsReactor` (`src/physicsReactor.asl`, 7): `Particle`, `Spring`, `Force2D`, `makeParticle`, `coulombRepulsion`, `hookeSpringForce`, `eulerIntegrate`.
- `aslVdom/polyglot` (`src/polyglot.asl`, 17): `emitReactTsx`, `emitVueSfc`, `emitSvelteComponent`, `emitSsrHtml`, `emitSwiftuiView`, `emitComposeComposable`, `emitSwiftuiViewModel`, `emitComposeViewModel`, `emitWebStateHook`, `compileComponent`, `emitSwiftuiModifiers`, `emitComposeModifierArg`, `vueAttrKey`, `svelteAttrKey`, `htmlAttrKey`, `isSelfClosing?`, `indentSpaces`.
- `aslVdom/signals` (`src/signals.asl`, 19): `Signal`, `Computed`, `Effect`, `SignalBatch`, `makeSignal`, `signalGet`, `signalSet`, `signalSubscribe`, `makeComputed`, `computedGet`, `computedInvalidate`, `makeEffect`, `runEffect`, `makeSignalBatch`, `queueSignalUpdate`, `flushSignalBatch`, `propagateSignalChange`, `propagateEffects`, and 1 more.
- `aslVdom/state` (`src/state.asl`, 16): `StateStore`, `Action`, `StatePatch`, `createStore`, `getState`, `getStateValue`, `dispatchAction`, `applyPatch`, `applyPatches`, `computeStateDiff`, `subscribeStore`, `unsubscribeStore`, `hasSubscriber?`, `isValidState?`, `isUniqueList?`, `uniqueSubscribers?`.
- `aslVdom/stateBridge` (`src/stateBridge.asl`, 12): `StateBridge`, `UIEvent`, `initBridge`, `updateBridgeSync`, `parseNativeEvent`, `isFallbackEvent?`, `eventToAction`, `dispatchBridgeEvent`, `serializePatchItem`, `serializePatches`, `formatBridgeBusEvent`, `extractJsonField`.
- `aslVdom/theme` (`src/theme.asl`, 22): `ThemeColors`, `ThemeSpacing`, `ThemeTypography`, `ThemeRadii`, `Theme`, `defaultColors`, `darkColors`, `defaultSpacing`, `defaultTypography`, `defaultRadii`, `createTheme`, `defaultTheme`, `darkTheme`, `resolveColor`, `resolveSpacing`, `resolveRadius`, `resolveTypography`, `isValidHexColor?`, and 4 more.
- `aslVdom/ui` (`src/ui.asl`, 18): `ButtonProps`, `CardProps`, `ListProps`, `ModalProps`, `uiButton`, `uiCard`, `uiList`, `uiModal`, `isValidButtonVariant?`, `isValidButtonSize?`, `isValidButtonProps?`, `isAccessibleModal?`, `isValidListProps?`, `buttonBgToken`, `buttonColorToken`, `buttonPaddingToken`, `buttonRadiusToken`, `listSpacingToken`.
- `aslVdom/vdom` (`src/vdom.asl`, 42): `VNode`, `AXNode`, `MutationRecord`, `DomDiff`, `t`, `txt`, `text`, `elem`, `el`, `elemPlain`, `elPlain`, `comp`, `c`, `compPlain`, `cPlain`, `isValidNode`, `isComponentTag?`, `vnodeIsComp?`, and 24 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-vdom/tests/<file>.asl
```

13 of 14 test files exit 0 (613 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `asnSvgTest.asl` | pass | 27 assertions |
| `diagramTest.asl` | pass | 17 assertions |
| `htmlSerializerTest.asl` | pass | 6 assertions, 1 refutations |
| `mobileStateSyncTest.asl` | pass | 31 assertions, 18 refutations |
| `physicsTest.asl` | pass | 15 assertions |
| `signalTest.asl` | **fail** | runs `./bin/asl check`, and there is no `bin/asl` |
| `signalsReactivityTest.asl` | pass | 9 assertions, 6 refutations |
| `stateBridgeTest.asl` | pass | 38 assertions, 9 refutations |
| `stateTest.asl` | pass | 37 assertions, 9 refutations |
| `testParseTagsTest.asl` | pass | 32 assertions |
| `themeCodegenTest.asl` | pass | 49 assertions, 42 refutations |
| `themeTest.asl` | pass | 67 assertions, 17 refutations |
| `uiTest.asl` | pass | 72 assertions, 33 refutations |
| `vdomTest.asl` | pass | 78 assertions |
