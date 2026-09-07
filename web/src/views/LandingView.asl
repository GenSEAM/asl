(module asl-web/landing-view
  :d "Declarative Landing Showcase View in pure AgentScript"
  :x [describe-landing-view render-landing-view]
  :i [(core/strings :a s)])

(df describe-landing-view [] -> Str
  :d "Returns structured description of the landing showcase"
  "(view :id \"landing\" :version \"1.0.0\" :targets [\"browser\" \"terminal\" \"edge\"])")

(df render-landing-view [] -> Str
  :d "Renders the landing showcase view markup"
  (s/concat
    "<section class=\"pt-28 pb-20 max-w-6xl mx-auto px-4 text-center\">"
    (s/concat
      "<h1 class=\"text-5xl font-extrabold text-ink mb-6\">Build Autonomous Swarms with Zero Overhead</h1>"
      (s/concat
        "<p class=\"text-xl text-ink-2 max-w-3xl mx-auto mb-10\">Single-pass S-expression language compiling directly to WebAssembly and C with 57%-65% token compaction.</p>"
        "<div class=\"flex justify-center gap-4\"><a href=\"#quickstart\" class=\"px-6 py-3 rounded-xl bg-signal text-ground font-bold\">Quickstart</a><a href=\"#docs\" class=\"px-6 py-3 rounded-xl border border-line bg-surface text-ink font-semibold\">Read Docs</a></div></section>"))))
