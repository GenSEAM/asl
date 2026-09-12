(module asl-web/ecosystem-view
  :d "Complete Ecosystem Architecture view in pure AgentScript."
  :x [ecosystem-view render-ecosystem-view]
  :i [(asl-text/string :a s)
      asl-web/ecosystem
      asl-web/unified-package-matrix])

(df render-ecosystem-view [] -> Str
  :d "Renders the complete Ecosystem view with DAG progression, UnifiedPackageMatrix, and Multi-Runtime Engine."
  (s/concat
    "<div class=\"pt-24 sm:pt-28 pb-24\">
      <section class=\"relative pt-8 sm:pt-12 pb-16 sm:pb-20\">
        <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8\">
          <div class=\"max-w-3xl\">
            <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
              <span class=\"text-signal\">Stages 1–3</span>
              <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
              Complete Ecosystem Architecture
            </span>
            <h1 class=\"mt-6 text-h2 sm:text-display font-bold text-ink tracking-tight text-balance\">
              The Unified Package Matrix &amp; Multi-Runtime Engine
            </h1>
            <p class=\"mt-6 text-lead text-ink-2 max-w-prose\">
              Autonomous agents require more than a syntax parser. AgentScript provides a comprehensive, mathematically verified suite of 9 official packages spanning foundational ASN codecs, process isolation, onion middleware, high-speed A2A buses, and dual-perception VDOM.
            </p>
          </div>

          <div class=\"mt-12 p-6 sm:p-8 rounded-3xl border border-line bg-surface/85 backdrop-blur-2xl shadow-e3\">
            <div class=\"flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-6 border-b border-line\">
              <div>
                <span class=\"font-mono text-micro uppercase text-signal font-semibold\">
                  Architectural Progression DAG
                </span>
                <h2 class=\"mt-1 text-h3 font-bold text-ink\">
                  Strict Sequential Milestone Pipeline
                </h2>
              </div>
              <div class=\"flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-signal/30 bg-signal/10 text-signal font-mono text-micro font-medium\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><path d=\"M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10\"></path><path d=\"m9 12 2 2 4-4\"></path></svg>
                <span>Zero External Runtime Dependencies</span>
              </div>
            </div>

            <div class=\"mt-8 grid grid-cols-1 md:grid-cols-3 gap-6 relative\">
              <div class=\"p-5 rounded-2xl border border-blue-500/30 bg-ground/80 flex flex-col justify-between space-y-4\">
                <div>
                  <div class=\"flex items-center justify-between\">
                    <span class=\"font-mono text-micro font-bold text-blue-400 px-2 py-0.5 rounded-md bg-blue-500/10 border border-blue-500/20\">
                      Stage 1: CORE
                    </span>
                    <span class=\"font-mono text-[10px] text-ink-3 uppercase\">Foundations</span>
                  </div>
                  <h3 class=\"mt-3 text-base font-bold text-ink\">Foundational Language &amp; Data Substrate</h3>
                  <p class=\"mt-1.5 text-meta text-ink-2 leading-relaxed\">
                    Closed, single-pass LL(1) grammar, universal ASN codec with 57%–65% token compaction, and guarded process automation.
                  </p>
                </div>
                <div class=\"pt-3 border-t border-line/60 space-y-1 font-mono text-micro\">
                  <div class=\"text-blue-300 font-semibold\">&bull; @genseam/asl-codec</div>
                  <div class=\"text-blue-300 font-semibold\">&bull; @genseam/asl-sh</div>
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-signal/40 bg-surface shadow-e2 flex flex-col justify-between space-y-4 relative\">
                <div>
                  <div class=\"flex items-center justify-between\">
                    <span class=\"font-mono text-micro font-bold text-signal px-2 py-0.5 rounded-md bg-signal/10 border border-signal/30\">
                      Stage 2: HARNESS
                    </span>
                    <span class=\"font-mono text-[10px] text-signal uppercase font-semibold\">Autonomous Core</span>
                  </div>
                  <h3 class=\"mt-3 text-base font-bold text-ink\">Agent Engine &amp; Execution Matrix</h3>
                  <p class=\"mt-1.5 text-meta text-ink-2 leading-relaxed\">
                    Composable onion middleware, sub-100ms sandboxed voice &amp; ReAct loops, &lt;0.04ms Unix/SSE mesh bus, and 64KB Wasm vector memory.
                  </p>
                </div>
                <div class=\"pt-3 border-t border-line/60 space-y-1 font-mono text-micro\">
                  <div class=\"text-signal-soft font-semibold\">&bull; @genseam/asl-agent-core</div>
                  <div class=\"text-signal-soft font-semibold\">&bull; @genseam/asl-eddie</div>
                  <div class=\"text-signal-soft font-semibold\">&bull; @genseam/asl-agent-bus</div>
                  <div class=\"text-signal-soft font-semibold\">&bull; @genseam/asl-mem</div>
                  <div class=\"text-signal-soft font-semibold\">&bull; @genseam/asl-web-search</div>
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-emerald-500/30 bg-ground/80 flex flex-col justify-between space-y-4\">
                <div>
                  <div class=\"flex items-center justify-between\">
                    <span class=\"font-mono text-micro font-bold text-emerald-400 px-2 py-0.5 rounded-md bg-emerald-500/10 border border-emerald-500/20\">
                      Stage 3: VISUAL
                    </span>
                    <span class=\"font-mono text-[10px] text-ink-3 uppercase\">Perception &amp; UI</span>
                  </div>
                  <h3 class=\"mt-3 text-base font-bold text-ink\">Perception, UI Dialect &amp; Browser Copilot</h3>
                  <p class=\"mt-1.5 text-meta text-ink-2 leading-relaxed\">
                    Dual perception AXTree + D2Snap DOM downsampler (-75% prompt tokens), TSX declarative dialect, and Manifest V3 in-tab WASI runner.
                  </p>
                </div>
                <div class=\"pt-3 border-t border-line/60 space-y-1 font-mono text-micro\">
                  <div class=\"text-emerald-300 font-semibold\">&bull; @genseam/asl-vdom</div>
                  <div class=\"text-emerald-300 font-semibold\">&bull; @genseam/asl-browser-plugin</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id=\"package-matrix\" aria-labelledby=\"matrix-packages-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent\">
        <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
          <header class=\"mb-16 sm:mb-20 max-w-3xl\">
            <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
              <span class=\"text-signal\">Packages</span>
              <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
              Unified Package Matrix
            </span>
            <h2 id=\"matrix-packages-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
              Eight Official Packages. One Cohesive Substrate.
            </h2>
            <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
              Every tool an autonomous agent needs to parse, sandbox, coordinate, recall, and interact with the physical and visual world &mdash; compiled with mathematical equivalence.
            </p>
          </header>"
    (unified-package-matrix)
    "</div></section>"
    (ecosystem)
    "</div>"))

(df ecosystem-view [] -> Str
  :d "Alias for render-ecosystem-view."
  (render-ecosystem-view))
