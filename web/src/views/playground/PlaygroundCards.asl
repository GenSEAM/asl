(module asl-web/playground/cards
  :d "Interactive preset card catalog in pure AgentScript."
  :x [render-playground-cards playground-cards]
  :i [])

(df render-playground-cards [] -> Str
  :d "Renders the interactive card grid container and filters."
  "<div class=\"mb-12\"><div class=\"flex flex-wrap items-center justify-between gap-4 mb-6\"><div class=\"flex flex-wrap items-center gap-2 p-1.5 rounded-2xl bg-surface border border-line shadow-e1\"><button id=\"pg-cat-all\" onclick=\"window.filterPlaygroundCards('all')\" class=\"pg-cat-btn px-4 py-1.5 rounded-xl font-mono text-xs font-semibold transition-all bg-signal text-ground shadow-sm cursor-pointer\">All Presets (20)</button><button id=\"pg-cat-toys\" onclick=\"window.filterPlaygroundCards('toys')\" class=\"pg-cat-btn px-4 py-1.5 rounded-xl font-mono text-xs font-semibold transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">2D Canvas Games (5)</button><button id=\"pg-cat-websites\" onclick=\"window.filterPlaygroundCards('websites')\" class=\"pg-cat-btn px-4 py-1.5 rounded-xl font-mono text-xs font-semibold transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">Web Applications (5)</button><button id=\"pg-cat-svgs\" onclick=\"window.filterPlaygroundCards('svgs')\" class=\"pg-cat-btn px-4 py-1.5 rounded-xl font-mono text-xs font-semibold transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">SVG Vector Icons (10)</button></div><div class=\"flex items-center gap-2 min-w-[240px] flex-1 sm:flex-initial\"><div class=\"relative w-full\"><input id=\"pg-search-input\" oninput=\"window.searchPlaygroundCards()\" type=\"text\" placeholder=\"Filter presets (mario, shop, hud, falcon)...\" class=\"w-full px-3.5 py-1.5 pl-9 rounded-xl bg-surface border border-line font-mono text-xs text-ink outline-none focus:border-signal transition-colors\"/><svg class=\"w-4 h-4 text-ink-3 absolute left-3 top-2\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\"><circle cx=\"11\" cy=\"11\" r=\"8\" stroke-width=\"2\"/><path d=\"m21 21-4.3-4.3\" stroke-width=\"2\" stroke-linecap=\"round\"/></svg></div></div></div><div id=\"pg-cards-grid\" class=\"grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4\"></div></div>")

(df playground-cards [] -> Str
  :d "Cards component alias"
  (render-playground-cards))
