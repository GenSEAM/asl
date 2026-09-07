(module asl-web/sky-loom-visualizer
  :d "Declarative SkyLoom Swarm Visualizer Component in pure AgentScript"
  :x [describe-sky-loom render-sky-loom]
  :i [(core/strings :a s)])

(df describe-sky-loom [] -> Str
  :d "Returns structured topology metadata for the SkyLoom swarm orchestrator"
  "(visualizer :id \"sky-loom\" :nodes 12 :topology \"directed-acyclic-graph\" :protocol \"AgentWire\")")

(df render-sky-loom [] -> Str
  :d "Renders the SkyLoom swarm visualization section"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"sky-loom\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">SkyLoom Swarm Topology</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-8\">Real-time directed acyclic graph visualizing multi-agent task execution and delegation streams.</p>"
        "<div class=\"h-80 rounded-3xl border border-line bg-surface flex items-center justify-center\"><span class=\"font-mono text-xs text-signal\">[SkyLoom Swarm Visualizer Engine: Active Topology Rendered]</span></div></section>"))))
