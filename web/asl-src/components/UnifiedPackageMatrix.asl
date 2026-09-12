(module asl-web/unified-package-matrix
  :d "Declarative Unified Package Matrix Component in pure AgentScript"
  :x [describe-matrix render-package-matrix]
  :i [(asl-text/string :a s)])

(df describe-matrix [] -> Str
  :d "Returns package count and tier coverage of the GenSEAM matrix."
  "(matrix :tiers [\"core\" \"harness\" \"visual\" \"quantum\" \"embedded\"] :packages 11)")

(df render-package-matrix [] -> Str
  :d "Renders the interactive unified package matrix grid."
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"matrix\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">The Unified Package Matrix</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-10\">11 official packages spanning foundational codecs, memory matrices, quantum simulation, and bare-metal IoT.</p>"
        "<div class=\"grid grid-cols-1 md:grid-cols-3 gap-6\">"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal font-semibold\">@genseam/asl-quantum</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Quantum Computing DSL</h3><p class=\"text-sm text-ink-2\">State-vector simulator & OpenQASM 3.0 synthesis.</p></div>"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal font-semibold\">@genseam/asl-arduino</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Bare-Metal Silicon</h3><p class=\"text-sm text-ink-2\">Direct GPIO and UART driver with zero heap allocation.</p></div>"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal font-semibold\">@genseam/asl-vdom</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Dual-Perception VDOM</h3><p class=\"text-sm text-ink-2\">AXTree downsampling with 75% prompt token reduction.</p></div>"
        "</div></section>"))))
