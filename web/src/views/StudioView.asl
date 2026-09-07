(module asl-web/studio-view
  :d "Declarative Tri-Studio View in pure AgentScript"
  :x [describe-studio-view render-studio-view]
  :i [(core/strings :a s)])

(df describe-studio-view [] -> Str
  :d "Returns structured description of the Tri-Studio workspace"
  "(view :id \"studio\" :studios [\"svg\" \"games\" \"websites\"] :runtime \"in-browser-webgpu\")")

(df render-studio-view [] -> Str
  :d "Renders studio workspace markup"
  (s/concat
    "<section class=\"pt-28 pb-20 max-w-6xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-8\"><span class=\"text-xs font-mono uppercase text-signal font-semibold\">Tri-Studio</span><h1 class=\"text-4xl font-bold text-ink mt-2 mb-4\">On-Device Agent Creator Studio</h1><p class=\"text-ink-2 text-lg\">Synthesize SVG art, playable HTML5 games, and responsive web components using client-side WebGPU models.</p></div>"
      "<div class=\"p-6 rounded-3xl border border-line bg-surface\"><div class=\"flex gap-4 border-b border-line pb-4 mb-6\"><span class=\"font-bold text-signal\">SVG Studio</span><span class=\"text-ink-2\">Games Studio</span><span class=\"text-ink-2\">Websites Studio</span></div><div class=\"h-96 rounded-2xl border border-line bg-surface-2 flex items-center justify-center text-ink-2 font-mono text-sm\">Studio Workspace Ready</div></div></section>")))
