(module asl-web/polyglot-studio
  :d "Declarative Polyglot Studio Component in pure AgentScript"
  :x [describe-polyglot-studio render-polyglot-studio]
  :i [(core/strings :a s)])

(df describe-polyglot-studio [] -> Str
  :d "Returns structured metadata for the polyglot code generation studio"
  "(studio :id \"polyglot\" :targets [\"react\" \"vue\" \"svelte\" \"html\" \"wasm\"] :speedup \"4.2x\")")

(df render-polyglot-studio [] -> Str
  :d "Renders the polyglot code generation studio section markup"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"polyglot\">"
    (s/concat
      "<h2 class=\"text-3xl font-bold text-ink mb-2 text-center\">Polyglot Code Generation Studio</h2>"
      (s/concat
        "<p class=\"text-ink-2 text-center mb-8\">Compile a single declarative ASN S-expression directly into clean, idiomatic code across 5 web targets.</p>"
        "<div class=\"grid grid-cols-1 lg:grid-cols-2 gap-6\"><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-4\">Input (Pure ASL)</h3><pre class=\"font-mono text-xs text-signal bg-surface-2 p-4 rounded-xl\">(div (:class \"card\")\n  (h2 \"Hello Autonomous Swarm\"))</pre></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><h3 class=\"font-bold text-ink mb-4\">Output Target</h3><pre class=\"font-mono text-xs text-emerald-400 bg-surface-2 p-4 rounded-xl\">&lt;div className=\"card\"&gt;\n  &lt;h2&gt;Hello Autonomous Swarm&lt;/h2&gt;\n&lt;/div&gt;</pre></div></div></section>"))))
