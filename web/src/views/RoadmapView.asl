(module asl-web/roadmap-view
  :d "Declarative Roadmap & Architecture Evolution View in pure AgentScript"
  :x [describe-roadmap-view render-roadmap-view]
  :i [(core/strings :a s)])

(df describe-roadmap-view [] -> Str
  :d "Returns structured description of the system roadmap"
  "(view :id \"roadmap\" :milestones [\"v0.1.0-Core\" \"v0.2.0-Harness\" \"v0.3.0-Visual\" \"v0.4.0-Quantum\" \"v1.0.0-Production\"])")

(df render-roadmap-view [] -> Str
  :d "Renders roadmap timeline markup"
  (s/concat
    "<section class=\"pt-28 pb-20 max-w-5xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-12\"><span class=\"text-xs font-mono uppercase text-signal font-semibold\">Timeline</span><h1 class=\"text-4xl font-bold text-ink mt-2 mb-4\">System Architecture Roadmap</h1><p class=\"text-ink-2 text-lg\">Deterministic milestones progressing from core language purity to bare-metal embedded silicon and quantum circuits.</p></div>"
      "<div class=\"space-y-6\"><div class=\"p-6 rounded-2xl border border-emerald-500/30 bg-surface\"><span class=\"text-xs font-mono text-emerald-400 font-bold uppercase\">Completed</span><h3 class=\"text-xl font-bold text-ink mt-1\">v0.1.0 Formal Grammar & Core</h3><p class=\"text-sm text-ink-2 mt-2\">Single-pass LL(1) parser, 107 safe pure builtins, and 100% test coverage across core packages.</p></div><div class=\"p-6 rounded-2xl border border-signal/30 bg-surface\"><span class=\"text-xs font-mono text-signal font-bold uppercase\">Active</span><h3 class=\"text-xl font-bold text-ink mt-1\">v0.2.0 Agent Harness & Operating System</h3><p class=\"text-sm text-ink-2 mt-2\">Persistent execution sessions, STDIN firewalls, and in-memory verification gates.</p></div></div></section>")))
