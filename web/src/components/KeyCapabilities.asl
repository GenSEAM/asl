(module asl-web/key-capabilities
  :d "Key Capabilities and Tooling blueprint section in pure AgentScript."
  :x [key-capabilities render-key-capabilities capabilities-view]
  :i [])

(df render-key-capabilities [] -> Str
  :d "Renders the 3 blueprint cards: Architect-First Observability, Accelerate Development Flow, and Built-in Ecosystem Tools."
  "<section id=\"capabilities\" class=\"relative py-24 sm:py-32 bg-transparent\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8\">
      
      <div class=\"mb-14\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">00</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          Architectural Core
        </span>
        <h2 class=\"mt-4 text-h2 font-bold text-ink tracking-tight\">
          Key Capabilities &amp; Tooling
        </h2>
        <p class=\"mt-3 text-lead text-ink-2 max-w-2xl\">
          A comprehensive suite of formal verification, real-time observability, and high-frequency developer workflows designed for autonomous agent swarms.
        </p>
      </div>

      
      <div class=\"grid grid-cols-1 md:grid-cols-3 gap-6 lg:gap-8\">
        
        
        <div class=\"group rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-6 sm:p-7 shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between\">
          <div>
            <h3 class=\"text-xl font-bold text-ink tracking-tight\">
              Architect-First Observability
            </h3>

            
            <div class=\"mt-6 w-full h-48 rounded-2xl bg-ground/80 border border-line/80 relative overflow-hidden flex items-center justify-center p-3\">
              
              <svg class=\"absolute inset-0 w-full h-full opacity-20 pointer-events-none\" xmlns=\"http://www.w3.org/2000/svg\">
                <defs>
                  <pattern id=\"card1Grid\" width=\"16\" height=\"16\" patternUnits=\"userSpaceOnUse\">
                    <path d=\"M 16 0 L 0 0 0 16\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"0.5\" class=\"text-signal\"></path>
                  </pattern>
                </defs>
                <rect width=\"100%\" height=\"100%\" fill=\"url(#card1Grid)\"></rect>
              </svg>

              
              <svg viewBox=\"0 0 240 140\" class=\"w-full h-full relative z-10\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
                
                <path d=\"M 150 110 L 220 110\" stroke=\"rgb(var(--signal))\" stroke-width=\"2\" stroke-dasharray=\"4 3\" opacity=\"0.6\"></path>
                <rect x=\"190\" y=\"98\" width=\"16\" height=\"24\" rx=\"3\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1.5\" fill=\"rgb(var(--surface))\"></rect>
                <line x1=\"198\" y1=\"102\" x2=\"198\" y2=\"118\" stroke=\"rgb(var(--signal))\" stroke-width=\"1.5\"></line>

                
                <path d=\"M 20 80 Q 40 40, 60 75 T 100 70 T 140 85 T 180 60\" stroke=\"rgb(var(--signal))\" stroke-width=\"1.5\" stroke-linecap=\"round\" opacity=\"0.5\"></path>

                
                <circle cx=\"35\" cy=\"70\" r=\"4\" fill=\"rgb(var(--signal))\"></circle>
                <circle cx=\"65\" cy=\"55\" r=\"5\" fill=\"rgb(var(--signal-soft))\"></circle>
                <circle cx=\"95\" cy=\"75\" r=\"4\" fill=\"rgb(var(--signal))\"></circle>
                <line x1=\"35\" y1=\"70\" x2=\"65\" y2=\"55\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1.2\"></line>
                <line x1=\"65\" y1=\"55\" x2=\"95\" y2=\"75\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1.2\"></line>

                
                <circle cx=\"85\" cy=\"65\" r=\"32\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"2.5\" fill=\"rgb(var(--signal) / 0.08)\"></circle>
                <circle cx=\"85\" cy=\"65\" r=\"28\" stroke=\"rgb(var(--signal))\" stroke-width=\"0.8\" stroke-dasharray=\"3 3\" opacity=\"0.7\"></circle>

                
                <path d=\"M 62 65 Q 75 42, 85 65 T 108 65\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"2.2\" stroke-linecap=\"round\"></path>
                <circle cx=\"85\" cy=\"65\" r=\"3.5\" fill=\"rgb(var(--signal-soft))\"></circle>
                
                
                <line x1=\"108\" y1=\"88\" x2=\"135\" y2=\"115\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"3.5\" stroke-linecap=\"round\"></line>
                <line x1=\"114\" y1=\"94\" x2=\"132\" y2=\"112\" stroke=\"rgb(var(--signal))\" stroke-width=\"1.5\" stroke-linecap=\"round\"></line>
                
                
                <line x1=\"20\" y1=\"125\" x2=\"100\" y2=\"125\" stroke=\"rgb(var(--ink-3))\" stroke-width=\"0.7\"></line>
                <line x1=\"20\" y1=\"122\" x2=\"20\" y2=\"128\" stroke=\"rgb(var(--ink-3))\" stroke-width=\"0.7\"></line>
                <line x1=\"100\" y1=\"122\" x2=\"100\" y2=\"128\" stroke=\"rgb(var(--ink-3))\" stroke-width=\"0.7\"></line>
                <text x=\"45\" y=\"133\" fill=\"rgb(var(--ink-3))\" font-size=\"7\" font-family=\"monospace\">Δt = 4.2ms</text>
              </svg>
            </div>
          </div>

          <p class=\"mt-5 text-meta text-ink-2 leading-relaxed\">
            See patterns, flows, and states without reading code. Formal validation from the design up with real-time AST invariants.
          </p>
        </div>

        
        <div class=\"group rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-6 sm:p-7 shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between\">
          <div>
            <h3 class=\"text-xl font-bold text-ink tracking-tight\">
              Accelerate Development Flow
            </h3>

            
            <div class=\"mt-6 w-full h-48 rounded-2xl bg-ground border border-line/90 relative overflow-hidden p-3.5 flex flex-col justify-between font-mono shadow-inner\">
              
              
              <div class=\"flex items-center justify-between pb-2.5 border-b border-line/60\">
                <div class=\"flex items-center gap-1.5\">
                  <span class=\"w-2.5 h-2.5 rounded-full bg-red-500/80 inline-block\"></span>
                  <span class=\"w-2.5 h-2.5 rounded-full bg-yellow-500/80 inline-block\"></span>
                  <span class=\"w-2.5 h-2.5 rounded-full bg-green-500/80 inline-block\"></span>
                </div>
                <span class=\"text-[10px] text-ink-3\">asl-cli — zsh</span>
                <div class=\"w-8\"></div>
              </div>

              
              <div class=\"space-y-1.5 text-[11px] sm:text-xs text-ink-2 py-1 flex-1 flex flex-col justify-center\">
                <div class=\"flex items-center gap-2\">
                  <span class=\"text-signal font-semibold\">$</span>
                  <span class=\"text-ink\">asl init application</span>
                </div>
                <div class=\"flex items-center gap-2\">
                  <span class=\"text-signal font-semibold\">$</span>
                  <span class=\"text-ink\">asl lint --fix</span>
                </div>
                <div class=\"flex items-center gap-2\">
                  <span class=\"text-signal font-semibold\">$</span>
                  <span class=\"text-ink\">asl fmt</span>
                </div>
                <div class=\"flex items-center gap-2\">
                  <span class=\"text-signal font-semibold\">$</span>
                  <span class=\"text-purple-300\">asl test --all</span>
                  <span class=\"inline-block w-1.5 h-3.5 bg-signal animate-pulse\"></span>
                </div>
              </div>

              <div class=\"pt-2 border-t border-line/40 flex items-center justify-between text-[10px] text-ink-3\">
                <span>Target: wasm32 + native</span>
                <span class=\"text-green-400\"> PASS (12/12)</span>
              </div>

            </div>
          </div>

          <p class=\"mt-5 text-meta text-ink-2 leading-relaxed\">
            Unified built-in tools. Maximize utility from the design phase. ESL-compliant. Minimal config.
          </p>
        </div>

        
        <div class=\"group rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-6 sm:p-7 shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between\">
          <div>
            <h3 class=\"text-xl font-bold text-ink tracking-tight\">
              Built-in Ecosystem Tools
            </h3>

            
            <div class=\"mt-6 w-full h-48 rounded-2xl bg-ground/80 border border-line/80 relative overflow-hidden flex items-center justify-center p-3\">
              
              <svg class=\"absolute inset-0 w-full h-full opacity-20 pointer-events-none\" xmlns=\"http://www.w3.org/2000/svg\">
                <defs>
                  <pattern id=\"card3Grid\" width=\"16\" height=\"16\" patternUnits=\"userSpaceOnUse\">
                    <path d=\"M 16 0 L 0 0 0 16\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"0.5\" class=\"text-signal\"></path>
                  </pattern>
                </defs>
                <rect width=\"100%\" height=\"100%\" fill=\"url(#card3Grid)\"></rect>
              </svg>

              
              <svg viewBox=\"0 0 240 140\" class=\"w-full h-full relative z-10\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
                
                <line x1=\"60\" y1=\"20\" x2=\"35\" y2=\"100\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"2.5\" stroke-linecap=\"round\"></line>
                
                <line x1=\"60\" y1=\"20\" x2=\"85\" y2=\"100\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"2.5\" stroke-linecap=\"round\"></line>
                
                <circle cx=\"60\" cy=\"20\" r=\"6\" stroke=\"rgb(var(--signal))\" stroke-width=\"2\" fill=\"rgb(var(--surface))\"></circle>
                <circle cx=\"60\" cy=\"20\" r=\"2.5\" fill=\"rgb(var(--signal-soft))\"></circle>
                
                
                <path d=\"M 45 68 A 30 30 0 0 1 75 68\" stroke=\"rgb(var(--signal))\" stroke-width=\"1.2\" stroke-dasharray=\"2 2\"></path>
                <text x=\"50\" y=\"80\" fill=\"rgb(var(--signal-soft))\" font-size=\"8\" font-family=\"monospace\">60°</text>

                
                <rect x=\"95\" y=\"45\" width=\"8\" height=\"55\" rx=\"1.5\" stroke=\"rgb(var(--ink-3))\" stroke-width=\"1\" fill=\"rgb(var(--surface))\"></rect>
                <line x1=\"95\" y1=\"55\" x2=\"99\" y2=\"55\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1\"></line>
                <line x1=\"95\" y1=\"65\" x2=\"101\" y2=\"65\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1\"></line>
                <line x1=\"95\" y1=\"75\" x2=\"99\" y2=\"75\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1\"></line>
                <line x1=\"95\" y1=\"85\" x2=\"101\" y2=\"85\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1\"></line>

                
                <g transform=\"translate(150, 35)\">
                  
                  <polygon points=\"25,0 45,15 45,45 25,60 5,45 5,15\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1.8\" fill=\"rgb(var(--signal) / 0.12)\"></polygon>
                  <line x1=\"25\" y1=\"0\" x2=\"25\" y2=\"60\" stroke=\"rgb(var(--signal))\" stroke-width=\"1\" opacity=\"0.6\"></line>
                  <line x1=\"5\" y1=\"15\" x2=\"45\" y2=\"15\" stroke=\"rgb(var(--signal))\" stroke-width=\"1\" opacity=\"0.6\"></line>
                  <line x1=\"5\" y1=\"45\" x2=\"45\" y2=\"45\" stroke=\"rgb(var(--signal))\" stroke-width=\"1\" opacity=\"0.6\"></line>

                  
                  <rect x=\"-22\" y=\"10\" width=\"16\" height=\"12\" rx=\"2\" stroke=\"rgb(var(--signal))\" stroke-width=\"1\" fill=\"rgb(var(--surface))\"></rect>
                  <line x1=\"-6\" y1=\"16\" x2=\"4\" y2=\"16\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1\" stroke-dasharray=\"2 1\"></line>

                  <rect x=\"52\" y=\"32\" width=\"16\" height=\"12\" rx=\"2\" stroke=\"rgb(var(--signal))\" stroke-width=\"1\" fill=\"rgb(var(--surface))\"></rect>
                  <line x1=\"46\" y1=\"38\" x2=\"52\" y2=\"38\" stroke=\"rgb(var(--signal-soft))\" stroke-width=\"1\" stroke-dasharray=\"2 1\"></line>
                </g>
              </svg>
            </div>
          </div>

          
          <div class=\"mt-5 space-y-2\">
            <div class=\"flex flex-wrap gap-1.5\">
              <span class=\"px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-2\">
                Verification Tools
              </span>
              <span class=\"px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-2\">
                Migration Suite
              </span>
            </div>
            <div class=\"flex flex-wrap gap-1.5\">
              <span class=\"px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-3\">
                Security Extensions
              </span>
              <span class=\"px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-3\">
                Interoperability Clients
              </span>
            </div>
          </div>

        </div>

      </div>

    </div>
  </section>")

(df key-capabilities [] -> Str
  :d "Alias for render-key-capabilities."
  (render-key-capabilities))

(df capabilities-view [] -> Str
  :d "Alias for render-key-capabilities."
  (render-key-capabilities))
