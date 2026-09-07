(module asl-web/studio-view
  :d "On-Device Agent Creator Studio view in pure AgentScript."
  :x [studio-view render-studio-view]
  :i [])

(df render-studio-view [] -> Str
  :d "Renders the Tri-Studio header and section wrapper."
  "<div class=\"pt-28 pb-6\">
    <section id=\"studio\" aria-labelledby=\"studio-title\" class=\"relative pt-28 sm:pt-36 pb-6 transition-colors bg-transparent\">
      <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
        <header class=\"mb-10 sm:mb-12 max-w-3xl\">
          <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
            <span class=\"text-signal\">Tri-Studio</span>
            <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
            On-Device Agent Creator Studio
          </span>
          <h2 id=\"studio-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
            Synthesize SVG Art, Playable Games &amp; Responsive Websites
          </h2>
          <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
            Powered by on-board WebGPU micro-models with zero server roundtrips. Draw vector emblems, build playable 2D arcade games, and author responsive website components verified through client-side gates.
          </p>
        </header>
      </div>
    </section>
  </div>")

(df studio-view [] -> Str
  :d "Alias for render-studio-view."
  (render-studio-view))
