(module asl-web/architecture-view
  :d "Declarative Architecture Showcase View in pure AgentScript"
  :x [describe-architecture render-architecture-view]
  :i [(asl-text/string :a s)])

(df describe-architecture [] -> Str
  :d "Returns structured metadata description of the AgentScript compiler architecture"
  "(architecture :pipeline [\"lexer\" \"parser\" \"checker\" \"monomorphizer\" \"codegen\"] :targets [\"wasm\" \"c\" \"typescript\" \"tsx\"] :isolation \"linear-memory-sandbox\")")

(df render-architecture-view [] -> Str
  :d "Renders the architecture overview markup"
  (s/concat
    "<div class=\"pt-24 sm:pt-28 pb-24 max-w-6xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-12\"><h1 class=\"text-4xl font-bold text-ink mb-4\">AgentScript Native Architecture</h1>"
      (s/concat
        "<p class=\"text-ink-2 text-lg\">Closed, single-pass LL(1) grammar compiling directly to WebAssembly and TypeScript with zero runtime overhead.</p></div>"
        "<div class=\"grid grid-cols-1 md:grid-cols-3 gap-6\"><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-2\">Stage 1: Core</h3><p class=\"text-sm text-ink-2\">Universal ASN codec and sandboxed process automation.</p></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-2\">Stage 2: Harness</h3><p class=\"text-sm text-ink-2\">Onion middleware, ReAct loop, and vector memory matrix.</p></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-2\">Stage 3: Visual</h3><p class=\"text-sm text-ink-2\">Dual-perception VDOM and in-browser WASI copilot.</p></div></div></div>"))))
