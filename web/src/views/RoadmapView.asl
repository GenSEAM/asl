(module asl-web/roadmap-view
  :d "Strategic Trajectory and Canons Roadmap view in pure AgentScript."
  :x [roadmap-view render-roadmap-view]
  :i [])

(df render-roadmap-view [] -> Str
  :d "Renders the complete 4-phase strategic roadmap view."
  "<div class=\"pt-28 pb-20\">
    <section id=\"roadmap\" aria-labelledby=\"roadmap-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent\">
      <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
        <header class=\"mb-16 sm:mb-20 max-w-3xl\">
          <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
            <span class=\"text-signal\">Strategic Trajectory</span>
            <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
            Canons &amp; Roadmaps
          </span>
          <h2 id=\"roadmap-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
            Engineering the Foundation for the Autonomous Agent Era
          </h2>
          <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
            Our phased development roadmap tracks core language evolution, resilient agent-to-agent mesh buses, self-hosted compilation, and zero-leak sandboxing.
          </p>
        </header>

        <div class=\"space-y-8 max-w-4xl mx-auto\">
          <!-- Milestone 1 -->
          <div class=\"p-6 sm:p-8 rounded-3xl border border-line bg-surface/70 transition-all\">
            <div class=\"flex items-center justify-between gap-4 pb-4 border-b border-line/60\">
              <div class=\"flex items-center gap-3\">
                <span class=\"font-mono text-micro font-bold text-signal px-2.5 py-1 rounded-full bg-signal/10 border border-signal/20\">
                  v0.1.0-Core
                </span>
                <span class=\"font-mono text-micro uppercase text-ink-3\">Phase 01</span>
              </div>
              <span class=\"font-mono text-micro uppercase font-semibold flex items-center gap-1.5 text-green-400\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg>
                Completed
              </span>
            </div>
            <h3 class=\"mt-5 text-xl font-bold text-ink\">Formal Grammar &amp; Differential Backends</h3>
            <p class=\"mt-2 text-body text-ink-2 leading-relaxed\">Establish closed, deterministic S-expression language with 107 safe pure builtins and differential compilation targets.</p>
            <ul class=\"mt-6 grid grid-cols-1 sm:grid-cols-2 gap-2.5\">
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Single-pass LL(1) balanced S-expression parser</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Differential verification gates (Python, Rust, Wasm, TypeScript)</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Cross-backend IoError &amp; numeric parity testing</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Compact coordinate protocol (asl/coord)</span></li>
            </ul>
          </div>

          <!-- Milestone 2 -->
          <div class=\"p-6 sm:p-8 rounded-3xl border border-line bg-surface/70 transition-all\">
            <div class=\"flex items-center justify-between gap-4 pb-4 border-b border-line/60\">
              <div class=\"flex items-center gap-3\">
                <span class=\"font-mono text-micro font-bold text-signal px-2.5 py-1 rounded-full bg-signal/10 border border-signal/20\">
                  SeamBus-Mesh
                </span>
                <span class=\"font-mono text-micro uppercase text-ink-3\">Phase 02</span>
              </div>
              <span class=\"font-mono text-micro uppercase font-semibold flex items-center gap-1.5 text-green-400\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg>
                Completed
              </span>
            </div>
            <h3 class=\"mt-5 text-xl font-bold text-ink\">Resilient Multi-Agent Mesh &amp; Wire Protocol</h3>
            <p class=\"mt-2 text-body text-ink-2 leading-relaxed\">High-frequency sub-millisecond agent-to-agent protocol and state coordination mesh.</p>
            <ul class=\"mt-6 grid grid-cols-1 sm:grid-cols-2 gap-2.5\">
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>A2A structured machine frame serialization</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Zero-copy in-memory Unix socket &amp; SSE message bus (&lt;0.04ms latency)</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Asymmetric negotiation and protocol handshakes</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Context snapshot compression (-78% token bloat reduction)</span></li>
            </ul>
          </div>

          <!-- Milestone 3 -->
          <div class=\"p-6 sm:p-8 rounded-3xl border border-signal/50 bg-surface shadow-purple-500/10 shadow-e3 relative overflow-hidden transition-all\">
            <div class=\"absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-purple-500 via-signal to-indigo-500\"></div>
            <div class=\"flex items-center justify-between gap-4 pb-4 border-b border-line/60\">
              <div class=\"flex items-center gap-3\">
                <span class=\"font-mono text-micro font-bold text-signal px-2.5 py-1 rounded-full bg-signal/10 border border-signal/20\">
                  Self-Hosted Runtime
                </span>
                <span class=\"font-mono text-micro uppercase text-ink-3\">Phase 03</span>
              </div>
              <span class=\"font-mono text-micro uppercase font-semibold flex items-center gap-1.5 text-signal\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 animate-pulse\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><polyline points=\"12 6 12 12 16 14\"></polyline></svg>
                Active Development
              </span>
            </div>
            <h3 class=\"mt-5 text-xl font-bold text-ink\">100% Pure AgentScript Parser &amp; Lexer</h3>
            <p class=\"mt-2 text-body text-ink-2 leading-relaxed\">Self-hosting compiler pipeline written entirely in pure AgentScript with zero external dependency overhead.</p>
            <ul class=\"mt-6 grid grid-cols-1 sm:grid-cols-2 gap-2.5\">
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Native tokenizer and S-expression reader in pure ASL</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Typed AST schemas (ModuleNode, SchemaNode, DefunNode)</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>CLI command: asl parse for high-speed AST inspections</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Autonomous anti-pattern linter and AST repair doctor</span></li>
            </ul>
          </div>

          <!-- Milestone 4 -->
          <div class=\"p-6 sm:p-8 rounded-3xl border border-line/60 bg-surface/40 transition-all\">
            <div class=\"flex items-center justify-between gap-4 pb-4 border-b border-line/60\">
              <div class=\"flex items-center gap-3\">
                <span class=\"font-mono text-micro font-bold text-signal px-2.5 py-1 rounded-full bg-signal/10 border border-signal/20\">
                  Autonomous Swarms
                </span>
                <span class=\"font-mono text-micro uppercase text-ink-3\">Phase 04</span>
              </div>
              <span class=\"font-mono text-micro uppercase font-semibold flex items-center gap-1.5 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path></svg>
                Planned
              </span>
            </div>
            <h3 class=\"mt-5 text-xl font-bold text-ink\">Meta-Agent Harness &amp; Speculative Task Pools</h3>
            <p class=\"mt-2 text-body text-ink-2 leading-relaxed\">Production-grade orchestration engine for autonomous agent swarms with formal circuit breakers.</p>
            <ul class=\"mt-6 grid grid-cols-1 sm:grid-cols-2 gap-2.5\">
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Zero-leak jailed sandbox execution with path jailing</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Decentralized agent search &amp; memory recall matrix</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Autonomous multi-model routing (Claude, Gemini, OpenAI)</span></li>
              <li class=\"flex items-start gap-2 text-meta text-ink-2\"><span class=\"w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0\"></span><span>Self-healing AST execution with formal verification gates</span></li>
            </ul>
          </div>
        </div>
      </div>
    </section>
  </div>")

(df roadmap-view [] -> Str
  :d "Alias for render-roadmap-view."
  (render-roadmap-view))
