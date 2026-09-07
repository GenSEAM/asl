(module asl-web/agent-wire-protocol
  :d "Declarative Agent Wire Protocol Component in pure AgentScript"
  :x [describe-wire-protocol render-wire-protocol]
  :i [(core/strings :a s)])

(df describe-wire-protocol [] -> Str
  :d "Returns structured metadata for the Agent Wire Protocol"
  "(protocol :name \"AgentWire\" :format \"ASN S-expression\" :framing \"length-prefixed-binary\" :compression \"57%-65%\")")

(df render-wire-protocol [] -> Str
  :d "Renders the wire protocol showcase section"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"wire-protocol\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">Agent Wire Protocol</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-10\">Sub-millisecond inter-agent communication using typed ASN S-expressions instead of conversational English.</p>"
        "<div class=\"grid grid-cols-1 md:grid-cols-3 gap-6\">"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Step 01</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Instant Handshake</h3><p class=\"text-sm text-ink-2\">20-byte discovery probe verifying schemas and target runtimes.</p></div>"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Step 02</span><h3 class=\"font-bold text-ink mt-2 mb-1\">ASN Wire Frames</h3><p class=\"text-sm text-ink-2\">Compact S-expressions cutting token consumption by 57%-65%.</p></div>"
        "<div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Step 03</span><h3 class=\"font-bold text-ink mt-2 mb-1\">Zero Hallucinations</h3><p class=\"text-sm text-ink-2\">Strict type safety with static compiler-checked contracts.</p></div>"
        "</div></section>"))))
