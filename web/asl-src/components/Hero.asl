(module asl-web/hero
  :d "Declarative Hero Component in pure AgentScript"
  :x [describe-hero render-hero]
  :i [(asl-text/string :a s)])

(df describe-hero [] -> Str
  :d "Returns structured metadata description of the Hero section."
  "(hero :title \"The Native Language of Autonomous Agents\" :reduction \"57%-65%\" :speed \"<100ms\")")

(df render-hero [] -> Str
  :d "Renders the hero banner markup."
  (s/concat
    "<section class=\"relative pt-20 pb-16 text-center max-w-5xl mx-auto px-4\">"
    (s/concat
      "<div class=\"inline-flex items-center gap-2 px-3 py-1 rounded-full border border-signal/30 bg-signal/10 text-signal font-mono text-xs mb-6\">"
      (s/concat
        "<span>Single-Pass LL(1) Agent Language</span></div>"
        "<h1 class=\"text-5xl sm:text-7xl font-extrabold text-ink tracking-tight mb-6\">The Native Language of Autonomous Agents</h1>"
        "<p class=\"text-lg sm:text-xl text-ink-2 max-w-3xl mx-auto leading-relaxed mb-8\">Compile multi-agent swarms directly to WebAssembly and embedded Arduino C with 57%–65% token compaction and zero host overhead.</p>"
        "<div class=\"flex justify-center gap-4\"><a href=\"#repl\" class=\"px-6 py-3 rounded-xl bg-signal text-ground font-bold shadow-e2\">Try Playground</a><a href=\"#matrix\" class=\"px-6 py-3 rounded-xl border border-line bg-surface text-ink font-semibold\">Explore Packages</a></div></section>"))))
