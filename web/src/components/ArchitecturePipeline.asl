(module aslWeb/components/architecturePipeline
  :d "High-Fidelity AgentScript Architecture Pipeline and Real-time Aperture HUD Component"
  :x [renderArchitecture viewArchitecture architectureView]
  :i [(asl-text/string :a s)
      (aslVdom/html :a h)])

(df renderArchitecture [] -> Str
  :d "Renders the 3-tier architecture pipeline and aperture HUD metrics"
  "<section id=\"architecture\" aria-labelledby=\"arch-title\" class=\"relative py-24 sm:py-32 transition-colors bg-transparent overflow-hidden max-w-6xl mx-auto px-4 sm:px-6 lg:px-8\">
    <div class=\"mb-16 max-w-3xl\">
      <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
        <span class=\"text-signal\">00</span>
        <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
        Architecture &amp; Perception
      </span>
      <h2 id=\"arch-title\" class=\"mt-6 text-h2 font-bold text-ink tracking-tight\">
        The Native Substrate Execution Model
      </h2>
      <p class=\"mt-4 text-lead text-ink-2 leading-relaxed\">
        Three deterministic layers: semantic AST perception, AOT polyglot compilation, and a stateless 9-syscall capability sandbox.
      </p>
    </div>

    <div class=\"grid grid-cols-1 lg:grid-cols-12 gap-8 items-start\">
      <div class=\"lg:col-span-7 space-y-6\">
        
        <div class=\"p-6 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors\">
          <div class=\"flex items-center justify-between mb-3\">
            <span class=\"text-xs font-mono font-semibold uppercase text-signal tracking-wider\">Layer 01 · Perceptual Interface</span>
            <span class=\"px-2 py-0.5 rounded-full bg-signal/15 text-signal font-mono text-[10px]\">Homoiconic AST</span>
          </div>
          <h3 class=\"text-base font-bold text-ink mb-1 font-sans\">AI Agent Perceptual Layer</h3>
          <p class=\"text-xs text-ink-2 leading-relaxed mb-4\">
            Autonomous agents write and parse single-pass S-expressions without ambiguity, context bloat, or syntax errors.
          </p>
          <div class=\"flex flex-wrap gap-2\">
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">~68% Token Density</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">LL(1) Deterministic</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">Zero-Backtrack</span>
          </div>
        </div>

        <div class=\"flex justify-center -my-2\">
          <svg class=\"w-5 h-5 text-signal animate-bounce\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\" stroke-width=\"2\">
            <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M19 14l-7 7m0 0l-7-7m7 7V3\" />
          </svg>
        </div>

        <div class=\"p-6 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors\">
          <div class=\"flex items-center justify-between mb-3\">
            <span class=\"text-xs font-mono font-semibold uppercase text-signal tracking-wider\">Layer 02 · Transpilation Substrate</span>
            <span class=\"px-2 py-0.5 rounded-full bg-signal/15 text-signal font-mono text-[10px]\">AOT Engine</span>
          </div>
          <h3 class=\"text-base font-bold text-ink mb-1 font-sans\">Multi-Target Polyglot Compilation</h3>
          <p class=\"text-xs text-ink-2 leading-relaxed mb-4\">
            Pure mathematical equivalence proving transforms AgentScript directly into pure ANSI C99, WebAssembly MVP, Python, and TypeScript.
          </p>
          <div class=\"flex flex-wrap gap-2\">
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-signal font-semibold\">ANSI C99</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-cyan-300 font-semibold\">Wasm MVP</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-amber-300 font-semibold\">Python</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-blue-300 font-semibold\">TypeScript</span>
          </div>
        </div>

        <div class=\"flex justify-center -my-2\">
          <svg class=\"w-5 h-5 text-signal animate-bounce\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\" stroke-width=\"2\">
            <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M19 14l-7 7m0 0l-7-7m7 7V3\" />
          </svg>
        </div>

        <div class=\"p-6 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-colors\">
          <div class=\"flex items-center justify-between mb-3\">
            <span class=\"text-xs font-mono font-semibold uppercase text-signal tracking-wider\">Layer 03 · Execution Microkernel</span>
            <span class=\"px-2 py-0.5 rounded-full bg-signal/15 text-signal font-mono text-[10px]\">9 Syscalls</span>
          </div>
          <h3 class=\"text-base font-bold text-ink mb-1 font-sans\">Stateless Capability Sandbox</h3>
          <p class=\"text-xs text-ink-2 leading-relaxed mb-4\">
            Hermetic sandbox with strictly declared C-host primitives and verified in-memory Virtual File System (asl mem).
          </p>
          <div class=\"flex flex-wrap gap-2\">
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">SYS_MEM</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">SYS_VFS</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">SYS_NET</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-ink-3\">SYS_EXEC</span>
            <span class=\"px-2.5 py-1 rounded-lg bg-ground border border-line font-mono text-[11px] text-emerald-400 font-semibold\">&lt;0.04ms Wasm</span>
          </div>
        </div>

      </div>

      <div class=\"lg:col-span-5 space-y-6\">
        <div class=\"p-6 rounded-2xl border border-line bg-surface/90 backdrop-blur-2xl shadow-e2 neon-card\">
          <div class=\"flex items-center justify-between pb-4 border-b border-line mb-5\">
            <span class=\"font-mono text-xs uppercase text-signal font-semibold tracking-wider\">Aperture HUD · Live Telemetry</span>
            <span class=\"flex items-center gap-1.5 font-mono text-[10px] text-emerald-400\"><span class=\"w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse\"></span>Online</span>
          </div>

          <div class=\"space-y-5\">
            <div>
              <div class=\"flex items-center justify-between text-xs font-mono text-ink-2 mb-2\">
                <span>Context Overhead Compaction</span>
                <span class=\"text-signal font-bold text-sm\">-78.4%</span>
              </div>
              <div class=\"w-full h-16 bg-ground rounded-xl border border-line p-2 relative overflow-hidden flex items-end\">
                <svg class=\"w-full h-12 text-signal overflow-visible\" viewBox=\"0 0 200 40\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
                  <path d=\"M 0 5 C 40 8, 80 25, 200 35\" stroke=\"currentColor\" stroke-width=\"2\" />
                  <path d=\"M 0 5 C 40 8, 80 25, 200 35 L 200 40 L 0 40 Z\" fill=\"currentColor\" fill-opacity=\"0.15\" />
                </svg>
              </div>
            </div>

            <div>
              <div class=\"flex items-center justify-between text-xs font-mono text-ink-2 mb-2\">
                <span>WASI Microkernel Latency</span>
                <span class=\"text-emerald-400 font-bold text-sm\">&lt;0.038ms</span>
              </div>
              <div class=\"w-full h-16 bg-ground rounded-xl border border-line p-2 relative overflow-hidden flex items-end\">
                <svg class=\"w-full h-12 text-emerald-400 overflow-visible\" viewBox=\"0 0 200 40\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
                  <path d=\"M 0 20 L 40 20 L 50 5 L 60 35 L 70 20 L 120 20 L 130 10 L 140 30 L 150 20 L 200 20\" stroke=\"currentColor\" stroke-width=\"1.8\" />
                </svg>
              </div>
            </div>

            <div class=\"pt-3 border-t border-line/60\">
              <span class=\"block font-mono text-[10px] text-ink-3 uppercase mb-3\">Hardware Verified Substrates</span>
              <div class=\"grid grid-cols-3 gap-2 text-center font-mono text-xs\">
                <div class=\"p-2.5 rounded-xl bg-ground border border-line text-ink-2 font-medium\">macOS M1-M4</div>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line text-ink-2 font-medium\">Linux x86/ARM</div>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line text-signal font-medium\">WASM MVP</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>")

(df viewArchitecture [] -> Str
  (renderArchitecture))

(df architectureView [] -> Str
  (renderArchitecture))
