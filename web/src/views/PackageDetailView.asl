(module asl-web/package-detail-view
  :d "Declarative Package Detail View in pure AgentScript"
  :x [describe-package-detail-view render-package-detail-view]
  :i [(core/strings :a s)])

(df describe-package-detail-view [] -> Str
  :d "Returns structured description of the package explorer"
  "(view :id \"package-detail\" :features [\"manifest\" \"signatures\" \"exports\" \"benchmark-score\"])")

(df render-package-detail-view [(pkg-name Str) (version Str) (desc Str)] -> Str
  :d "Renders package detail markup"
  (s/concat
    "<div class=\"pt-28 pb-20 max-w-4xl mx-auto px-4\"><div class=\"p-8 rounded-3xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal uppercase\">Package Registry</span><h1 class=\"text-3xl font-bold text-ink mt-2 mb-2\">"
    (s/concat
      pkg-name
      (s/concat
        "</h1><span class=\"px-2 py-1 rounded bg-surface-2 text-xs font-mono text-ink-2\">v"
        (s/concat
          version
          (s/concat
            "</span><p class=\"mt-4 text-ink-2 text-base\">"
            (s/concat
              desc
              "</p><div class=\"mt-8 p-4 rounded-xl bg-surface-2 font-mono text-xs text-signal\"><code>asl install "
              (s/concat
                pkg-name
                "</code></div></div></div>"))))))))
