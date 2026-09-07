(module asl-web/skills-marketplace
  :d "Declarative Skills Marketplace Component in pure AgentScript"
  :x [describe-skills-marketplace render-skills-marketplace]
  :i [(core/strings :a s)])

(df describe-skills-marketplace [] -> Str
  :d "Returns structured catalog of official agent skills"
  "(marketplace :skills [\"asl-intel\" \"asl-lens\" \"asl-mem\" \"asl-svg\" \"agent-browser\" \"constitution-query\"] :verified true)")

(df render-skills-marketplace [] -> Str
  :d "Renders the skills marketplace section markup"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"skills\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">Agent Skills Hub</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-8\">Modular capabilities and tool adapters designed for LLM code generation and semantic manipulation.</p>"
        "<div class=\"grid grid-cols-1 md:grid-cols-3 gap-6\"><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">asl-intel</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Dense Code Intelligence</h3><p class=\"text-sm text-ink-2\">Outline extraction and symbol lookups without loading entire files.</p></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">asl-mem</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Perceptual Memory</h3><p class=\"text-sm text-ink-2\">Cosine similarity retrieval and scalar fact extraction.</p></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">asl-svg</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Vector Drawing</h3><p class=\"text-sm text-ink-2\">Single-token ASN vector primitives with 50.7% compaction.</p></div></div></section>"))))
