(module asl-web/agent-wire-protocol
  :d "Agent-to-Agent Mesh Protocol showcase component in pure AgentScript."
  :x [agent-wire-protocol render-agent-wire-protocol wire-protocol-view render-wire-protocol]
  :i [])

(df render-agent-wire-protocol [] -> Str
  :d "Renders the Agent-to-Agent Mesh Protocol architecture and token comparison."
  "<section id=\"a2a-protocol\" aria-labelledby=\"a2a-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent overflow-hidden\">
    <div class=\"max-w-shell mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      <header class=\"mb-16 sm:mb-20 max-w-3xl mx-auto text-center\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">04</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          Agent-to-Agent Mesh Protocol
        </span>
        <h2 id=\"a2a-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          Machines Shouldn't Chat Like Humans.
        </h2>
        <p class=\"mt-4 text-lead text-ink-2 max-w-2xl text-balance mx-auto\">
          When autonomous agents talk to each other in conversational English, context windows are wasted on polite greetings, repetitive prompts, and JSON parse failures. AgentScript Wire Frames replace conversational chat with instant, typed machine frames.
        </p>
      </header>

      <div class=\"max-w-5xl mx-auto\">
        <div class=\"p-6 sm:p-8 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3\">
          
          <div class=\"flex flex-col sm:flex-row items-center justify-between gap-6 pb-8 border-b border-line\">
            <div class=\"flex items-center gap-3\">
              <div class=\"w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
                  <path d=\"M12 8V4H8\"></path>
                  <rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect>
                  <path d=\"M2 14h2\"></path>
                  <path d=\"M20 14h2\"></path>
                  <path d=\"M15 13v2\"></path>
                  <path d=\"M9 13v2\"></path>
                </svg>
              </div>
              <div>
                <p class=\"font-sans font-semibold text-ink\">Planner Agent (LLM)</p>
                <p class=\"font-mono text-micro uppercase text-ink-3\">High-Reasoning Orchestrator</p>
              </div>
            </div>

            <div class=\"flex items-center gap-2.5 px-4 py-1.5 rounded-full border border-signal/30 bg-signal/10 text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-signal animate-pulse\">
                <path d=\"M22 12h-4l-3 9L9 3l-3 9H2\"></path>
              </svg>
              <span class=\"font-mono text-micro font-semibold uppercase tracking-wider\">
                Sub-Millisecond Wire Mesh
              </span>
            </div>

            <div class=\"flex items-center gap-3\">
              <div class=\"w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-emerald-400\">
                  <rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"></rect>
                  <rect width=\"6\" height=\"6\" x=\"9\" y=\"9\" rx=\"1\"></rect>
                  <path d=\"M15 2v2\"></path>
                  <path d=\"M15 20v2\"></path>
                  <path d=\"M2 15h2\"></path>
                  <path d=\"M2 9h2\"></path>
                  <path d=\"M20 15h2\"></path>
                  <path d=\"M20 9h2\"></path>
                  <path d=\"M9 2v2\"></path>
                  <path d=\"M9 20v2\"></path>
                </svg>
              </div>
              <div class=\"text-right\">
                <p class=\"font-sans font-semibold text-ink\">Worker Agent (Wasm / Local)</p>
                <p class=\"font-mono text-micro uppercase text-ink-3\">High-Speed Execution Node</p>
              </div>
            </div>
          </div>

          
          <div class=\"mt-8 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4\">
            <div class=\"p-5 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm flex flex-col justify-between\">
              <div>
                <div class=\"flex items-center justify-between\">
                  <span class=\"font-mono text-micro font-semibold text-signal\">01</span>
                  <span class=\"font-mono text-micro uppercase text-ink-3\">Probe</span>
                </div>
                <h3 class=\"mt-3 font-sans font-semibold text-ink text-base\">Instant Handshake</h3>
                <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">Agents verify schemas and target runtimes in a single 20-byte discovery probe.</p>
              </div>
            </div>

            <div class=\"p-5 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm flex flex-col justify-between\">
              <div>
                <div class=\"flex items-center justify-between\">
                  <span class=\"font-mono text-micro font-semibold text-signal\">02</span>
                  <span class=\"font-mono text-micro uppercase text-ink-3\">Compact</span>
                </div>
                <h3 class=\"mt-3 font-sans font-semibold text-ink text-base\">ASN Wire Frames</h3>
                <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">Replaces conversational English with compact S-expressions. 57%&ndash;65% token compaction.</p>
              </div>
            </div>

            <div class=\"p-5 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm flex flex-col justify-between\">
              <div>
                <div class=\"flex items-center justify-between\">
                  <span class=\"font-mono text-micro font-semibold text-signal\">03</span>
                  <span class=\"font-mono text-micro uppercase text-ink-3\">Strict</span>
                </div>
                <h3 class=\"mt-3 font-sans font-semibold text-ink text-base\">Zero-Hallucination Types</h3>
                <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">Typed contract boundaries guarantee no missing keys, invalid types, or parse loops.</p>
              </div>
            </div>

            <div class=\"p-5 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm flex flex-col justify-between\">
              <div>
                <div class=\"flex items-center justify-between\">
                  <span class=\"font-mono text-micro font-semibold text-signal\">04</span>
                  <span class=\"font-mono text-micro uppercase text-ink-3\">Fast</span>
                </div>
                <h3 class=\"mt-3 font-sans font-semibold text-ink text-base\">Direct In-Memory Dispatch</h3>
                <p class=\"mt-2 text-meta text-ink-2 leading-relaxed\">Evaluates directly in host memory (&lt;0.05ms) without multi-pass JSON re-serialization.</p>
              </div>
            </div>
          </div>

          
          <div class=\"mt-8 grid grid-cols-1 md:grid-cols-2 gap-6 pt-8 border-t border-line\">
            
            <div class=\"p-6 rounded-2xl border border-rose-500/20 bg-rose-500/5\">
              <div class=\"flex items-center justify-between pb-3 border-b border-rose-500/20\">
                <span class=\"font-mono text-micro uppercase text-rose-400 font-semibold flex items-center gap-1.5\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                    <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                    <line x1=\"12\" x2=\"12\" y1=\"8\" y2=\"12\"></line>
                    <line x1=\"12\" x2=\"12.01\" y1=\"16\" y2=\"16\"></line>
                  </svg>
                  The Chatty Human Way (Conversational JSON)
                </span>
                <span class=\"px-2.5 py-0.5 rounded-full bg-rose-500/15 text-rose-300 font-mono text-micro\">
                  178 Tokens &middot; High Latency
                </span>
              </div>
              <div class=\"mt-4 font-mono text-xs text-ink-2 leading-relaxed bg-ground/70 p-4 rounded-xl border border-line overflow-x-auto\">
                <p class=\"text-ink-3\">&quot;Hi there! Could you please inspect order #892, verify if the payment cleared, and return the items formatted as strict JSON without markdown backticks? Thanks!&quot;</p>
                <p class=\"mt-2 text-rose-300\">--&gt; Sure! Here is the JSON:<br />{&quot;order_id&quot;: 892, &quot;status&quot;: &quot;paid&quot;, ...}</p>
              </div>
              <p class=\"mt-3 text-micro text-ink-3\">
                Unchecked prose. Fragile parser loops, token bloat, and frequent markdown formatting hallucinations.
              </p>
            </div>

            
            <div class=\"p-6 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 shadow-e1\">
              <div class=\"flex items-center justify-between pb-3 border-b border-emerald-500/20\">
                <span class=\"font-mono text-micro uppercase text-emerald-400 font-semibold flex items-center gap-1.5\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                    <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                    <path d=\"m9 12 2 2 4-4\"></path>
                  </svg>
                  The AgentScript Way (ASN Wire Frame)
                </span>
                <span class=\"px-2.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-300 font-mono text-micro font-semibold\">
                  22 Tokens &middot; 0.05ms
                </span>
              </div>
              <div class=\"mt-4 font-mono text-xs text-purple-300 leading-relaxed bg-ground/70 p-4 rounded-xl border border-line overflow-x-auto\">
                <p class=\"text-signal\">(? order/inspect :id 892 :req [status items])</p>
                <p class=\"mt-2 text-emerald-400\">(! order/ack :status :paid :items [(:sku &quot;x1&quot; :qty 2)])</p>
              </div>
              <p class=\"mt-3 text-micro text-emerald-400/90 font-medium\">
                Zero conversational fluff. Validated against compiler schemas in one pass, evaluated in-memory.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>")

(df agent-wire-protocol [] -> Str
  :d "Alias for render-agent-wire-protocol."
  (render-agent-wire-protocol))

(df wire-protocol-view [] -> Str
  :d "Alias for render-agent-wire-protocol."
  (render-agent-wire-protocol))

(df render-wire-protocol [] -> Str
  :d "Alias for render-agent-wire-protocol."
  (render-agent-wire-protocol))
