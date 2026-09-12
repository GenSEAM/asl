(module asl-web/ecosystem
  :d "Multi-Runtime Interoperability ecosystem section in pure AgentScript."
  :x [ecosystem render-ecosystem ecosystem-view]
  :i [])

(df render-ecosystem [] -> Str
  :d "Renders multi-runtime ecosystem targets, differential verification flow, and agent specs."
  "<section id=\"toolchain\" aria-labelledby=\"toolchain-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent overflow-hidden\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      
      <header class=\"mb-16 sm:mb-20 max-w-3xl\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">01</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          Multi-Runtime Interoperability
        </span>
        <h2 id=\"toolchain-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          One language. Compatible with every ecosystem your agents touch.
        </h2>
        <p class=\"mt-4 text-lead text-ink-2 max-w-2xl text-balance\">
          Agents should not have to rewrite their logic for every deployment target. AgentScript compiles deterministically into native binaries, web sandboxes, and host scripting languages with mathematically proven equivalence.
        </p>
      </header>

      
      <div class=\"flex justify-center -mt-6 mb-10\">
        <span class=\"inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wide\">
          <span class=\"w-1.5 h-1.5 rounded-full bg-amber-400\"></span>
          Core Language &amp; Wire Protocol: Stable &middot; Extended Compilers: Under Development
        </span>
      </div>

      
      <div class=\"mb-14 p-6 sm:p-8 rounded-3xl border border-line bg-surface/90 backdrop-blur-2xl shadow-e3\">
        <div class=\"flex flex-col lg:flex-row items-center justify-between gap-6 pb-6 border-b border-line\">
          <div>
            <span class=\"font-mono text-micro uppercase text-signal font-semibold\">
              Architectural Guarantees
            </span>
            <h3 class=\"mt-1 text-h3 font-bold text-ink\">
              Differential Verification &amp; Cross-Runtime Equivalence
            </h3>
          </div>
          <div class=\"flex items-center gap-2 px-4 py-2 rounded-full border border-signal/30 bg-signal/10 text-signal font-mono text-meta font-medium\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\">
              <path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\"></path>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
            <span>7-Gate Verified Equivalence</span>
          </div>
        </div>

        
        <div class=\"mt-8 grid grid-cols-1 md:grid-cols-3 gap-6 items-center\">
          
          <div class=\"p-5 rounded-2xl border border-line bg-ground/80 text-center flex flex-col items-center\">
            <div class=\"w-12 h-12 rounded-2xl bg-signal/10 border border-signal/30 flex items-center justify-center text-signal mb-3\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-6 h-6\">
                <path d=\"M12 8V4H8\"></path>
                <rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect>
                <path d=\"M2 14h2\"></path>
                <path d=\"M20 14h2\"></path>
                <path d=\"M15 13v2\"></path>
                <path d=\"M9 13v2\"></path>
              </svg>
            </div>
            <h4 class=\"font-semibold text-ink text-body\">1. Model Generates Once</h4>
            <p class=\"mt-1.5 text-meta text-ink-3 leading-relaxed\">
              The agent writes one concise, balanced S-expression. Single-pass LL(1) grammar eliminates syntax repairs.
            </p>
          </div>

          
          <div class=\"p-5 rounded-2xl border border-signal/40 bg-surface text-center flex flex-col items-center shadow-e2 relative\">
            <div class=\"w-12 h-12 rounded-2xl bg-signal text-white flex items-center justify-center mb-3 shadow-md\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-6 h-6\">
                <polygon points=\"12 2 2 7 12 12 22 7 12 2\"></polygon>
                <polyline points=\"2 17 12 22 22 17\"></polyline>
                <polyline points=\"2 12 12 17 22 12\"></polyline>
              </svg>
            </div>
            <h4 class=\"font-semibold text-ink text-body\">2. Canonical Lowering</h4>
            <p class=\"mt-1.5 text-meta text-ink-2 leading-relaxed\">
              Multi-target AST lowering translates the program into the host target while preserving exact formal semantics.
            </p>
          </div>

          
          <div class=\"p-5 rounded-2xl border border-line bg-ground/80 text-center flex flex-col items-center\">
            <div class=\"w-12 h-12 rounded-2xl bg-signal/10 border border-signal/30 flex items-center justify-center text-signal mb-3\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-6 h-6\">
                <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                <path d=\"m9 12 2 2 4-4\"></path>
              </svg>
            </div>
            <h4 class=\"font-semibold text-ink text-body\">3. Verified Execution</h4>
            <p class=\"mt-1.5 text-meta text-ink-3 leading-relaxed\">
              Identical results on WebAssembly, native systems, or host runtimes verified by differential testing.
            </p>
          </div>
        </div>
      </div>

      
      <div class=\"grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6\">
        
        <div class=\"group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-e2 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between gap-3\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
                  <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                  <path d=\"M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20\"></path>
                  <path d=\"M2 12h20\"></path>
                </svg>
              </div>
              <span class=\"px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3\">
                Zero-Leak Sandbox
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              WebAssembly (Wasm)
            </h3>
            <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">
              Edge &amp; In-Browser Sandbox
            </p>

            <p class=\"mt-3 text-meta text-ink-2 leading-relaxed\">
              Compiles to standalone wasm32-wasip1 modules. Executes inside Cloudflare Workers, Fastly Compute, or sandboxed browser agent runtimes.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3\">
            <span>Verified Target</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-green-400\">
              <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-e2 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between gap-3\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
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
              <span class=\"px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3\">
                Zero-Cost Memory
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Rust
            </h3>
            <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">
              High-Performance Systems
            </p>

            <p class=\"mt-3 text-meta text-ink-2 leading-relaxed\">
              Translates to idiomatic, memory-safe Rust with static type checks and bare-metal native binary compilation via rustc.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3\">
            <span>Verified Target</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-green-400\">
              <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-e2 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between gap-3\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
                  <path d=\"M4 22h14a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v4\"></path>
                  <path d=\"M14 2v4a2 2 0 0 0 2 2h4\"></path>
                  <path d=\"m5 12-3 3 3 3\"></path>
                  <path d=\"m9 18 3-3-3-3\"></path>
                </svg>
              </div>
              <span class=\"px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3\">
                Seamless Host Interop
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              TypeScript &amp; JavaScript
            </h3>
            <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">
              Web &amp; Host Integration
            </p>

            <p class=\"mt-3 text-meta text-ink-2 leading-relaxed\">
              Emits modern ESM TypeScript modules for seamless embedding into Node.js, Deno, Bun, and browser extensions without wrappers.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3\">
            <span>Verified Target</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-green-400\">
              <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-e2 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between gap-3\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
                  <polyline points=\"4 17 10 11 4 5\"></polyline>
                  <line x1=\"12\" x2=\"20\" y1=\"19\" y2=\"19\"></line>
                </svg>
              </div>
              <span class=\"px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3\">
                Microsecond Latency
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Go
            </h3>
            <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">
              High-Concurrency Services
            </p>

            <p class=\"mt-3 text-meta text-ink-2 leading-relaxed\">
              Generates concurrent Go routines and channels for high-throughput distributed agent swarms and microservices.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3\">
            <span>Verified Target</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-green-400\">
              <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-e2 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between gap-3\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
                  <path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path>
                  <path d=\"M5 3v4\"></path>
                  <path d=\"M19 17v4\"></path>
                  <path d=\"M3 5h4\"></path>
                  <path d=\"M17 19h4\"></path>
                </svg>
              </div>
              <span class=\"px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3\">
                Data Science Native
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Python
            </h3>
            <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">
              ML &amp; AI Orchestration
            </p>

            <p class=\"mt-3 text-meta text-ink-2 leading-relaxed\">
              Direct interoperability with PyTorch, LangChain, DSPy, and scientific workflows via clean, standard AST lowering.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3\">
            <span>Verified Target</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-green-400\">
              <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>

        
        <div class=\"group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-e2 hover:border-signal/40 transition-colors flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between gap-3\">
              <div class=\"p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\">
                  <polygon points=\"12 2 2 7 12 12 22 7 12 2\"></polygon>
                  <polyline points=\"2 17 12 22 22 17\"></polyline>
                  <polyline points=\"2 12 12 17 22 12\"></polyline>
                </svg>
              </div>
              <span class=\"px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3\">
                Provable Invariants
              </span>
            </div>

            <h3 class=\"mt-5 text-lg font-bold text-ink\">
              Relational SQL AST
            </h3>
            <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">
              Cross-Dialect Query Engine
            </p>

            <p class=\"mt-3 text-meta text-ink-2 leading-relaxed\">
              Parametric AST lowering supporting PostgreSQL, SQLite, DuckDB, and MySQL with zero SQL injection risk and formal dialect guarantees.
            </p>
          </div>

          <div class=\"mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3\">
            <span>Verified Target</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-green-400\">
              <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
              <path d=\"m9 12 2 2 4-4\"></path>
            </svg>
          </div>
        </div>
      </div>

      
      <div class=\"mt-14 p-6 sm:p-8 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6\">
        <div class=\"space-y-1.5 max-w-2xl\">
          <div class=\"flex items-center gap-2\">
            <span class=\"w-2 h-2 rounded-full bg-signal\"></span>
            <span class=\"font-mono text-micro uppercase text-signal font-semibold\">
              Engineered for Agents &middot; Documented for Models
            </span>
          </div>
          <h3 class=\"text-xl font-bold text-ink\">
            Need full AST tables, grammar invariants, or A2A endpoints?
          </h3>
          <p class=\"text-meta text-ink-2 leading-relaxed\">
            While humans explore visual concepts on this page, autonomous agents and LLMs consume our complete formal grammar and machine-readable specs directly via <code class=\"text-signal font-mono\">/llms.txt</code> and Model Context Protocol.
          </p>
        </div>

        <div class=\"flex flex-wrap items-center gap-3 shrink-0\">
          <a href=\"/llms.txt\" target=\"_blank\" rel=\"noreferrer\" class=\"inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-surface border border-line hover:border-signal/40 text-ink font-mono text-meta font-medium shadow-sm transition-colors\">
            <span>/llms.txt</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal\">
              <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
              <polyline points=\"12 5 19 12 12 19\"></polyline>
            </svg>
          </a>
          <a href=\"/llms-full.txt\" target=\"_blank\" rel=\"noreferrer\" class=\"inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-signal text-white font-mono text-meta font-medium shadow-sm hover:opacity-95 transition-opacity\">
            <span>Full Spec</span>
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
              <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
              <polyline points=\"12 5 19 12 12 19\"></polyline>
            </svg>
          </a>
        </div>
      </div>

    </div>
  </section>")

(df ecosystem [] -> Str
  :d "Alias for render-ecosystem."
  (render-ecosystem))

(df ecosystem-view [] -> Str
  :d "Alias for render-ecosystem."
  (render-ecosystem))
