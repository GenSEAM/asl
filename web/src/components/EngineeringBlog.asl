(module asl-web/engineering-blog-section
  :d "Declarative Engineering Blog Teaser Section in pure AgentScript"
  :x [describe-engineering-blog render-engineering-blog]
  :i [(core/strings :a s)])

(df describe-engineering-blog [] -> Str
  :d "Returns structured metadata for the blog teaser section"
  "(section :id \"writing\" :source \"asl-web/blog-posts\" :limit 4)")

(df render-engineering-blog [] -> Str
  :d "Renders the engineering blog teaser section markup"
  (s/concat
    "<section class=\"py-16 max-w-6xl mx-auto px-4\" id=\"writing\">"
    (s/concat
      "<div class=\"flex justify-between items-end mb-8\"><div><span class=\"text-xs font-mono uppercase text-signal font-semibold\">05 // Engineering Blog</span><h2 class=\"text-3xl font-bold text-ink mt-2\">Notes on Language & Autonomous Architecture</h2></div><a href=\"#blog\" class=\"text-signal font-mono text-sm font-semibold\">View All Posts →</a></div>"
      "<div class=\"grid grid-cols-1 md:grid-cols-2 gap-6\"><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Flagship</span><h3 class=\"text-xl font-bold text-ink mt-2 mb-2\">The Agentic Toolchain</h3><p class=\"text-sm text-ink-2 mb-4\">Continuous action loops, native verification gates, and pure ASL architecture.</p><a href=\"#read\" class=\"text-signal font-mono text-xs\">Read →</a></div><div class=\"p-6 rounded-2xl border border-line bg-surface\"><span class=\"text-xs font-mono text-signal\">Flagship</span><h3 class=\"text-xl font-bold text-ink mt-2 mb-2\">The Token-Density Fallacy</h3><p class=\"text-sm text-ink-2 mb-4\">Why disemvoweling breaks BPE and how AgentScript solves identifier economics.</p><a href=\"#read\" class=\"text-signal font-mono text-xs\">Read →</a></div></div></section>")))
