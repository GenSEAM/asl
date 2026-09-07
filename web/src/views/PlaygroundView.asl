(module asl-web/playground-view
  :d "Declarative Playground & REPL View in pure AgentScript"
  :x [describe-playground-view render-playground-view]
  :i [(core/strings :a s)])

(df describe-playground-view [] -> Str
  :d "Returns structured description of the playground view"
  "(view :id \"playground\" :engine \"webassembly\" :features [\"ast-checker\" \"evaluator\" \"transpiler\"])")

(df render-playground-view [] -> Str
  :d "Renders playground workspace markup"
  (s/concat
    "<section class=\"pt-28 pb-20 max-w-6xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-8\"><span class=\"text-xs font-mono uppercase text-signal font-semibold\">Interactive</span><h1 class=\"text-4xl font-bold text-ink mt-2 mb-4\">Developer Playground</h1><p class=\"text-ink-2 text-lg\">Test AgentScript S-expressions directly in your browser with real-time AST validation.</p></div>"
      "<div class=\"grid grid-cols-1 lg:grid-cols-2 gap-6\"><div class=\"p-4 rounded-2xl border border-line bg-surface min-h-[400px]\"><span class=\"text-xs font-mono text-ink-2\">Editor (ASL)</span></div><div class=\"p-4 rounded-2xl border border-line bg-surface min-h-[400px]\"><span class=\"text-xs font-mono text-ink-2\">Evaluation & VDOM Output</span></div></div></section>")))
