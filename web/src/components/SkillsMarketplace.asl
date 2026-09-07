(module asl-web/skills-marketplace
  :d "Skills and packages manifest component in pure AgentScript."
  :x [skills-marketplace render-skills-marketplace]
  :i [])

(df render-skills-marketplace [] -> Str
  :d "Renders the package and skills hub manifest table."
  "<section id=\"packages\" aria-labelledby=\"packages-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      <header class=\"mb-16 sm:mb-20 max-w-3xl\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">06</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          Packages
        </span>
        <h2 id=\"packages-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          Everything the toolchain ships, in one manifest.
        </h2>
      </header>

      <ul class=\"border-t border-line\">
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Language core</span>
          <span class=\"text-body text-ink-2\">Grammar, checker, standard library</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/asl
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Agent harness</span>
          <span class=\"text-body text-ink-2\">Intent classification and task pools</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/harness
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Skills hub</span>
          <span class=\"text-body text-ink-2\">Prompt skills and tool adapters</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/skills
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Socket bus</span>
          <span class=\"text-body text-ink-2\">In-memory socket and SSE transport</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/agent-bus
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Browser lens</span>
          <span class=\"text-body text-ink-2\">DOM extraction and in-situ actions</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/browser-plugin
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">In-browser dev</span>
          <span class=\"text-body text-ink-2\">Hot-reloading Wasm runtime</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/in-browser-dev
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Search scout</span>
          <span class=\"text-body text-ink-2\">Metasearch and RAG compression</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/search
          </code>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline\">
          <span class=\"text-body font-medium text-ink\">Vector memory</span>
          <span class=\"text-body text-ink-2\">Local cosine recall in WebAssembly</span>
          <code class=\"font-mono text-meta text-ink-3 whitespace-nowrap\">
            <span class=\"text-signal\">$ </span>asl skill install @genseam/mem
          </code>
        </li>
      </ul>
    </div>
  </section>")

(df skills-marketplace [] -> Str
  :d "Alias for render-skills-marketplace."
  (render-skills-marketplace))
