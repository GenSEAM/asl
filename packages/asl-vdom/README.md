# asl-vdom (package `aslVdom`)

ASL virtual DOM: node constructors, keyed and indexed diffing, accessibility-tree downsampling, and generators that print a node tree as source for other UI frameworks.

## Modules (`asl/packages/asl-vdom/src`, module prefix `aslVdom/`)
- `vdom.asl`: `VNode`, constructors (`elem`, `el`, `text`, `comp`), `diffNodes`, `domDiff`, `downsampleNode`, `formatDiffFrame`.
- `html.asl`: HTML constructors (`div`, `button`, `card`, ...) and attribute helpers.
- `polyglot.asl`: `emitReactTsx`, `emitVueSfc`, `emitSvelteComponent`, `emitSsrHtml`, `emitSwiftuiView`, `emitComposeComposable`, `compileComponent`. `emitJsx.asl`: React TSX modules.
- `signals.asl`, `state.asl`, `stateBridge.asl`: signals and effects, a reducer store with patches, a bridge to native UI events.
- `theme.asl`, `ui.asl`: design tokens, CSS variables, button/card/list/modal components.
- `perception.asl`, `asnSvg.asl`, `diagram.asl`, `physicsReactor.asl`: accessibility frames, ASN to SVG, Mermaid and HTML diagrams, force layout.

The output is source text; nothing in the package patches a live DOM.

## Tests (2026-09-24)
`./bin/asl test asl/packages/asl-vdom/tests/vdomTest.asl` exits 0 with 156 assertions on the lenient asl-core runner; `asl/host/out/asl-host test` on it exits 1 with 4 load errors.
