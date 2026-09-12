(module asl-web/ecosystem-view
  :d "Declarative Ecosystem Showcase View in pure AgentScript"
  :x [describe-ecosystem render-ecosystem-view]
  :i [(asl-text/string :a s)])

(df describe-ecosystem [] -> Str
  :d "Returns structured metadata description of the 9 official GenSEAM packages"
  "(ecosystem :packages [\"@genseam/asl-codec\" \"@genseam/asl-sh\" \"@genseam/asl-agent-core\" \"@genseam/asl-eddie\" \"@genseam/asl-agent-bus\" \"@genseam/asl-mem\" \"@genseam/asl-web-search\" \"@genseam/asl-vdom\" \"@genseam/asl-quantum\"])")

(df render-ecosystem-view [] -> Str
  :d "Renders the ecosystem view markup"
  (s/concat
    "<div class=\"pt-24 sm:pt-28 pb-24 max-w-6xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-12\"><span class=\"text-xs font-mono uppercase text-signal font-semibold\">Stages 1–3</span><h1 class=\"text-4xl font-bold text-ink mt-2 mb-4\">The Unified Package Matrix</h1>"
      (s/concat
        "<p class=\"text-ink-2 text-lg\">Comprehensive suite of official packages spanning foundational ASN codecs, process isolation, high-speed A2A buses, vector memory, and quantum simulation.</p></div>"
        "<div class=\"space-y-4\"><div class=\"p-4 rounded-xl border border-line bg-surface flex justify-between items-center\"><span class=\"font-mono font-bold text-ink\">@genseam/asl-quantum</span><span class=\"text-xs font-mono text-signal\">OpenQASM 3.0 Simulation</span></div><div class=\"p-4 rounded-xl border border-line bg-surface flex justify-between items-center\"><span class=\"font-mono font-bold text-ink\">@genseam/asl-vdom</span><span class=\"text-xs font-mono text-signal\">Dual-Perception VDOM</span></div><div class=\"p-4 rounded-xl border border-line bg-surface flex justify-between items-center\"><span class=\"font-mono font-bold text-ink\">@genseam/asl-mem</span><span class=\"text-xs font-mono text-signal\">Hierarchical Vector Store</span></div></div></div>"))))
