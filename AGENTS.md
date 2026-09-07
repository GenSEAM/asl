<!-- ASL_TOOLBELT_START -->
Always activate and follow the asl-toolbelt skill; asl is available in PATH.
<!-- ASL_TOOLBELT_END -->

# AgentScript (ASL) — Autonomous Agent Operational Instructions

## 1. Core Technical Specifications
- Consult `AGENT_SPEC_CORE.md` as the normative language specification.
- Consult `ROADMAP.md` for current milestone status and active implementation goals.
- Maintain single-source-of-truth definitions in `prelude/prelude.json` for all closed vocabulary and projection tables.

## 2. Verification Toolchain & Continuous Audit Gates
Verify all changes using the native sovereign ASL CLI before committing:

```bash
asl gate
```

The verification suite evaluates seven gates:
1. **Manifest Integrity**: Validates package manifests and module structure across all packages.
2. **Structural Balance**: Verifies pure ASL syntax and S-expression form balance across all `.asl` files.
3. **Registry Grounding**: Verifies published benchmark claims against the benchmark registry.
4. **Pure AgentScript Implementation**: Confirms that code packages contain pure AgentScript modules.
5. **Native Test Execution**: Runs native ASL test suites across packages.
6. **ASN Grammar & Symbol Density**: Verifies symbol registries, token budget limits (<= 2 tokens under BPE), and unambiguous canonical naming.
7. **Modular Skills Freshness**: Confirms skill frontmatters, trigger descriptions, and protocol names are synchronized.

Individual module checks and tests can be run targeted:
```bash
asl check <path-to-file.asl>
asl test [path-to-test.asl]
asl audit <path-to-file.asl>
```

## 3. Standard & Verbose Projection Protocol
AgentScript supports two projection formats derived from `prelude/prelude.json`:
- **Standard Projection (Storage & Wire Default)**:
  - Use Standard syntax (`df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`, `I64`, `F64`, `Str`) for files on disk, inter-agent message frames, and emitted artifacts.
  - Standard primitives adhere to a <= 2 token ceiling under BPE (`cl100k_base` and `o200k_base`), reducing context overhead by 50%–65% compared to JSON.
- **Verbose Projection (Interactive Presentation)**:
  - Present Verbose forms (`defun`, `defschema`, etc.) in interactive dialogues, user explanations, and educational walkthroughs.
  - Generate verbose representations dynamically using `asl view <file>` or `asl transcode --to verbose <file>` without modifying the underlying file.
- **Positional Aliasing**:
  - Short aliases resolve based on syntactic position as defined in `AGENT_SPEC_CORE.md` §2.1.
  - Record field keys preserve literal names (for example, `(P :x 1)` specifies a field named `:x`).
- **Comments as String Literal Notes**:
  - Express code comments as free-standing string literal notes placed at the top level or within declaration bodies.
  - Runtimes erase top-level notes during compilation while preserving multiline formatting.
- **Control-Flow Linearization**:
  - Keep nesting depth within 4 levels. Use early returns and concise local helper functions to maintain linear flow.

## 4. Code Intelligence & Polyglot Operations
Leverage the native ASL engine for fast AST queries and workspace navigation:
- **AST Outline**: Run `asl intel outline <file>` to inspect structure without loading entire files into context.
- **Symbol Lookup**: Run `asl intel search <symbol>` and `asl intel callers <symbol>` for sub-millisecond symbol reference queries.
- **In-Memory Workspace Search**: Ingest project trees using `asl mem index .` and query semantics with `asl mem query "<query>"`.
- **Batch RPC Operations**: Execute compound operations using `asl rpc '(:batch ...)'` to combine outline, query, and metrics in a single round-trip.

## 5. Ecosystem & Multi-Package Architecture
- Code packages reside under `packages/` and are organized as self-contained ASL modules with a `manifest.asn` declaration.
- Maintain pure ASL implementations across all code packages.
- When updating grammar definitions in `grammar/tree-sitter-agentscript/grammar.js`, regenerate the parser artifacts via the local build scripts.
- Ensure all public documentation examples fenced with ` ```agentscript ` or ` ```lisp ` parse cleanly, or annotate speculative snippets with `<!-- not-agentscript: reason -->`.

