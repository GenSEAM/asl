(module asl-web/blog-view
  :d "Declarative Engineering Blog View in pure AgentScript"
  :x [describe-blog-view render-blog-view]
  :i [(core/strings :a s)])

(df describe-blog-view [] -> Str
  :d "Returns structured description of the engineering blog view"
  "(view :id \"blog\" :title \"Engineering Blog\" :posts-source \"asl-web/blog-posts\" :categories [\"Architecture\" \"Grammar\" \"Tools\"])")

(df render-blog-view [] -> Str
  :d "Renders the blog view markup"
  (s/concat
    "<section class=\"pt-28 pb-20 max-w-6xl mx-auto px-4\">"
    (s/concat
      "<div class=\"max-w-3xl mb-12\"><span class=\"text-xs font-mono uppercase text-signal font-semibold\">Writing</span>"
      (s/concat
        "<h1 class=\"text-4xl font-bold text-ink mt-2 mb-4\">Engineering & Architecture Blog</h1>"
        (s/concat
          "<p class=\"text-ink-2 text-lg\">Deep dives into single-pass LL(1) grammars, deterministic AI agent harnesses, and zero-overhead sandboxing.</p></div>"
          "<div class=\"grid grid-cols-1 md:grid-cols-2 gap-8\"><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Tools & Architecture</span><h2 class=\"text-xl font-bold text-ink mt-2 mb-2\">The Agentic Toolchain</h2><p class=\"text-sm text-ink-2 mb-4\">Continuous action loops, native verification gates, and pure ASL architecture.</p><a href=\"#read\" class=\"text-signal font-mono text-xs font-semibold\">Read Article →</a></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Grammar & Tokenomics</span><h2 class=\"text-xl font-bold text-ink mt-2 mb-2\">The Token-Density Fallacy</h2><p class=\"text-sm text-ink-2 mb-4\">Why disemvoweling breaks BPE and how AgentScript solves identifier economics.</p><a href=\"#read\" class=\"text-signal font-mono text-xs font-semibold\">Read Article →</a></div></div></section>")))))
