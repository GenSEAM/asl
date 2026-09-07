(module asl-web/observability-studio
  :d "Declarative Agent Observability Studio Component in pure AgentScript"
  :x [describe-observability-studio render-observability-studio]
  :i [(core/strings :a s)])

(df describe-observability-studio [] -> Str
  :d "Returns structured description of the three-tier observability matrix"
  "(studio :id \"observability\" :tiers [\"strategic\" \"tactical\" \"operational\"] :realtime true)")

(df render-observability-studio [] -> Str
  :d "Renders the observability studio section markup"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"observability\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">Agent Observability Studio</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-10\">Full-spectrum visibility into multi-agent reasoning, message buses, and deterministic AST execution.</p>"
        "<div class=\"grid grid-cols-1 md:grid-cols-3 gap-6\">"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Tier 01</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Strategic Guardrails</h3><p class=\"text-sm text-ink-2\">Constitution enforcement and immutable boundaries versioned with code.</p></div>"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Tier 02</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Tactical Message Bus</h3><p class=\"text-sm text-ink-2\">In-memory socket bus tracking inter-agent delegations and task pools.</p></div>"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Tier 03</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Operational Memory</h3><p class=\"text-sm text-ink-2\">Cosine similarity retrieval and deterministic AST mutation receipts.</p></div>"
        "</div></section>"))))
