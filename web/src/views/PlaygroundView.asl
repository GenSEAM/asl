(module asl-web/playground-view
  :d "Developer Playground view header and runtime status in pure AgentScript."
  :x [playground-view render-playground-view]
  :i [])

(df render-playground-view [] -> Str
  :d "Renders the Developer Playground header and runtime status banner."
  "<div class=\"pt-28 pb-4\">
    <section id=\"playground\" aria-labelledby=\"playground-title\" class=\"relative pt-28 sm:pt-36 pb-4 transition-colors bg-transparent\">
      <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
        <header class=\"mb-10 sm:mb-12 max-w-3xl\">
          <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
            <span class=\"text-signal\">AI Companion</span>
            <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
            Developer Playground
          </span>
          <h2 id=\"playground-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
            On-Device AI Companion &amp; Tri-Studio
          </h2>
          <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
            Direct developer access to the sovereign in-browser companion: generate vector badges (SVG Studio), playable HTML5 arcade toys (Games Studio), and modern responsive components (Websites Studio) with client-side verification gates.
          </p>
        </header>

        <!-- Runtime Status Banner -->
        <div class=\"mb-6 p-4 rounded-2xl bg-surface/90 border border-line flex flex-wrap items-center justify-between gap-4 shadow-sm\">
          <div class=\"flex items-center gap-3\">
            <div class=\"w-9 h-9 rounded-xl bg-signal/15 border border-signal/30 flex items-center justify-center text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"></rect><rect width=\"6\" height=\"6\" x=\"9\" y=\"9\"></rect><path d=\"M15 2v2\"></path><path d=\"M15 20v2\"></path><path d=\"M2 15h2\"></path><path d=\"M2 9h2\"></path><path d=\"M20 15h2\"></path><path d=\"M20 9h2\"></path><path d=\"M9 2v2\"></path><path d=\"M9 20v2\"></path></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"text-sm font-bold text-ink tracking-wide\">AGENTSCRIPT WEB RUNTIME</span>
                <span class=\"px-2 py-0.5 rounded-full bg-amber-500/15 border border-amber-500/30 text-amber-400 font-mono text-[10px] font-bold flex items-center gap-1\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path></svg>
                  IN ACTIVE DEVELOPMENT
                </span>
                <span class=\"px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold flex items-center gap-1\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg>
                  CLIENT-SIDE READY
                </span>
              </div>
              <div class=\"text-xs font-mono text-ink-muted mt-0.5 flex flex-wrap items-center gap-2\">
                <span class=\"text-signal\">@asl:playground-preview</span>
                <span>&bull;</span>
                <span>Direct Access Route (/playground)</span>
                <span>&bull;</span>
                <span class=\"text-emerald-400\">Zero Cloud Dependencies</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>")

(df playground-view [] -> Str
  :d "Alias for render-playground-view."
  (render-playground-view))
