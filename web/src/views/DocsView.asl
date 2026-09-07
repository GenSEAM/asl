(module asl-web/docs-view
  :d "Declarative Documentation & Grammar Reference View in pure AgentScript"
  :x [describe-docs-view render-docs-view]
  :i [(core/strings :a s)])

(df describe-docs-view [] -> Str
  :d "Returns structured description of the documentation view"
  "(view :id \"docs\" :title \"Documentation\" :sections [\"quickstart\" \"grammar\" \"compiler\" \"cli\" \"api\"])")

(df render-docs-view [] -> Str
  :d "Renders the documentation view markup"
  (s/concat
    "<section class=\"pt-28 pb-20 max-w-6xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-12\"><span class=\"text-xs font-mono uppercase text-signal font-semibold\">Reference</span>"
      (s/concat
        "<h1 class=\"text-4xl font-bold text-ink mt-2 mb-4\">AgentScript Documentation</h1>"
        (s/concat
          "<p class=\"text-ink-2 text-lg\">Comprehensive documentation for the single-pass LL(1) AgentScript language, compiler toolchain, and sovereign runtime.</p></div>"
          "<div class=\"grid grid-cols-1 md:grid-cols-3 gap-6\"><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-2\">Formal Grammar</h3><p class=\"text-sm text-ink-2\">107 pure builtins, balanced S-expressions, and closed AST semantics.</p></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-2\">Compiler Pipeline</h3><p class=\"text-sm text-ink-2\">Differential compilation to WebAssembly, ANSI C, and TypeScript.</p></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-2\">Harness & Gates</h3><p class=\"text-sm text-ink-2\">In-memory verification gates and non-interactive process supervision.</p></div></div></section>")))))
