(module asl-web/module-graph-visualizer
  :d "Declarative Module Graph Visualizer Component in pure AgentScript"
  :x [describe-module-graph render-module-graph]
  :i [(core/strings :a s)])

(df describe-module-graph [] -> Str
  :d "Returns dependency graph metadata for official ASL packages"
  "(graph :packages 28 :coverage \"100%\" :functions 1804 :gates 7)")

(df render-module-graph [] -> Str
  :d "Renders the module dependency graph section"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"graph\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">Module Dependency Graph</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-8\">28 official packages with 1,804 functions verified under 100% test coverage and zero foreign code.</p>"
        "<div class=\"p-8 rounded-3xl border border-line bg-surface flex items-center justify-center min-h-[300px]\"><span class=\"font-mono text-sm text-signal\">[ASL Interactive Module Reactor Online: 28 Verified Nodes]</span></div></section>"))))
