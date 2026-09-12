(module asl-web/harness-toolkit
  :d "AgentScript Harness Toolkit showcase component in pure AgentScript."
  :x [harness-toolkit render-harness-toolkit harness-view]
  :i [])

(df render-harness-toolkit [] -> Str
  :d "Renders the Harness Toolkit dynamic orchestration capabilities."
  "<section id=\"harness-toolkit\" aria-labelledby=\"harness-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent overflow-hidden\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      <header class=\"mb-16 sm:mb-20 max-w-3xl mx-auto text-center\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">03</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          Multi-Agent Interoperability
        </span>
        <h2 id=\"harness-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          Harness Toolkit: Dynamic Orchestration for Autonomous Agents
        </h2>
        <p class=\"mt-4 text-lead text-ink-2 max-w-2xl text-balance mx-auto\">
          Workspaces don't run on one monolithic model. The AgentScript Harness Toolkit provides the modular substrate to connect, coordinate, and supervise swarms of specialized agents with dynamic escalation and zero schema drift.
        </p>
      </header>

      
      <div class=\"flex justify-center -mt-6 mb-10\">
        <span class=\"inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wide\">
          <span class=\"w-1.5 h-1.5 rounded-full bg-amber-400\"></span>
          Harness &amp; Multi-Agent Mesh: In Active Development
        </span>
      </div>

      <div class=\"max-w-5xl mx-auto grid grid-cols-1 md:grid-cols-2 gap-6\">
        
        <div class=\"p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between pb-4 border-b border-line/60\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line text-signal\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\">
                  <path d=\"M19.439 7.85c0-1.57.8-2.35 1.561-2.85-1.12-.58-2.61-.85-4.1-.85-2.07 0-3.9.72-5.4 1.85-1.34-1.13-3.13-1.85-5.2-1.85-1.49 0-2.98.27-4.1.85.76.5 1.56 1.28 1.56 2.85 0 2.2-1.25 3.15-2.16 3.15-.33 0-.64-.09-.94-.23v6.08c.3.14.61.23.94.23.91 0 2.16.95 2.16 3.15 0 1.57-.8 2.35-1.56 2.85 1.12.58 2.61.85 4.1.85 2.07 0 3.86-.72 5.2-1.85 1.5 1.13 3.33 1.85 5.4 1.85 1.49 0 2.98-.27 4.1-.85-.76-.5-1.56-1.28-1.56-2.85 0-2.2 1.25-3.15 2.16-3.15.33 0 .64.09.94.23V11c-.3-.14-.61-.23-.94-.23-.91 0-2.16-.95-2.16-3.15z\"></path>
                </svg>
              </div>
              <span class=\"font-mono text-micro uppercase text-ink-3 font-semibold\">
                Extensible &amp; Modular
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Dynamic Plugin Architecture
            </h3>

            <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">
              No rigid, hardcoded agent hierarchies. The harness is entirely modular and customizable through domain-specific plugins, allowing custom subagent graphs and tailor-made workflows.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3\">
            <span>Dynamic Configuration</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal\">
              <path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\"></path>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between pb-4 border-b border-line/60\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line text-signal\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\">
                  <line x1=\"4\" x2=\"4\" y1=\"21\" y2=\"14\"></line>
                  <line x1=\"4\" x2=\"4\" y1=\"10\" y2=\"3\"></line>
                  <line x1=\"12\" x2=\"12\" y1=\"21\" y2=\"12\"></line>
                  <line x1=\"12\" x2=\"12\" y1=\"8\" y2=\"3\"></line>
                  <line x1=\"20\" x2=\"20\" y1=\"21\" y2=\"16\"></line>
                  <line x1=\"20\" x2=\"20\" y1=\"12\" y2=\"3\"></line>
                  <line x1=\"1\" x2=\"7\" y1=\"14\" y2=\"14\"></line>
                  <line x1=\"9\" x2=\"15\" y1=\"8\" y2=\"8\"></line>
                  <line x1=\"17\" x2=\"23\" y1=\"16\" y2=\"16\"></line>
                </svg>
              </div>
              <span class=\"font-mono text-micro uppercase text-ink-3 font-semibold\">
                Tiered Reasoning Presets
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Dynamic Agent Escalation
            </h3>

            <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">
              Built-in escalation presets route lightweight routine coding to fast models while automatically escalating architectural refactors or persistent failures to heavy-reasoning agents.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3\">
            <span>Dynamic Configuration</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal\">
              <path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\"></path>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between pb-4 border-b border-line/60\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line text-signal\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\">
                  <line x1=\"6\" x2=\"6\" y1=\"3\" y2=\"15\"></line>
                  <circle cx=\"18\" cy=\"6\" r=\"3\"></circle>
                  <circle cx=\"6\" cy=\"18\" r=\"3\"></circle>
                  <path d=\"M18 9a9 9 0 0 1-9 9\"></path>
                </svg>
              </div>
              <span class=\"font-mono text-micro uppercase text-ink-3 font-semibold\">
                Enforced Quality Isolation
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Separation of Duties
            </h3>

            <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">
              The agent that writes code never reviews it. Independent planner, implementer, reviewer, and verifier roles run with isolated context under strict file ownership boundaries.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3\">
            <span>Dynamic Configuration</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal\">
              <path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\"></path>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between pb-4 border-b border-line/60\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line text-signal\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\">
                  <polygon points=\"13 2 3 14 12 14 11 22 21 10 12 10 13 2\"></polygon>
                </svg>
              </div>
              <span class=\"font-mono text-micro uppercase text-ink-3 font-semibold\">
                Low-Latency Interop
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Structured Mesh Bus
            </h3>

            <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">
              Inter-agent communication over high-speed in-memory Unix domain sockets and SSE, exchanging compact S-expression frames without conversational bloat.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3\">
            <span>Dynamic Configuration</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal\">
              <path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\"></path>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>
      </div>
    </div>
  </section>")

(df harness-toolkit [] -> Str
  :d "Alias for render-harness-toolkit."
  (render-harness-toolkit))

(df harness-view [] -> Str
  :d "Alias for render-harness-toolkit."
  (render-harness-toolkit))
