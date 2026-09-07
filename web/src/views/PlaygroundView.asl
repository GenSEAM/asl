(module asl-web/playground-view
  :d "Interactive Developer Playground with Graph Reactor, SVG Studio, AI Companion, SQL Studio, and Quality Doctor in pure AgentScript."
  :x [playground-view render-playground-view]
  :i [])

(df render-playground-view [] -> Str
  :d "Renders the full interactive Developer Playground."
  "
<div class=\"pt-28 pb-20\">
  <section id=\"playground\" aria-labelledby=\"playground-title\" class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
    <header class=\"mb-10 max-w-3xl\">
      <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
        <span class=\"text-signal\">Interactive</span>
        <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
        Developer Playground
      </span>
      <h2 id=\"playground-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
        Interactive AgentScript Tooling &amp; Live In-Browser Studio
      </h2>
      <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
        Experience real-time graph untangling with GPU acceleration, ASN vector drawing, local client-side WebGPU agent companion, SQL transpilation, and AST quality audits.
      </p>
    </header>

    <!-- Runtime Status Banner -->
    <div class=\"mb-6 p-4 rounded-2xl bg-surface/90 border border-line flex flex-wrap items-center justify-between gap-4 shadow-sm\">
      <div class=\"flex items-center gap-3\">
        <div class=\"w-9 h-9 rounded-xl bg-signal/15 border border-signal/30 flex items-center justify-center text-signal\">
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"/><rect width=\"6\" height=\"6\" x=\"9\" y=\"9\"/><path d=\"M15 2v2\"/><path d=\"M15 20v2\"/><path d=\"M2 15h2\"/><path d=\"M2 9h2\"/><path d=\"M20 15h2\"/><path d=\"M20 9h2\"/><path d=\"M9 2v2\"/><path d=\"M9 20v2\"/></svg>
        </div>
        <div>
          <div class=\"flex items-center gap-2\">
            <span class=\"text-sm font-bold text-ink tracking-wide\">AGENTSCRIPT WEB RUNTIME</span>
            <span class=\"px-2 py-0.5 rounded-full bg-amber-500/15 border border-amber-500/30 text-amber-400 font-mono text-[10px] font-bold flex items-center gap-1\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"/></svg>
              IN ACTIVE DEVELOPMENT
            </span>
            <span class=\"px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold flex items-center gap-1\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><circle cx=\"12\" cy=\"12\" r=\"10\"/><path d=\"m9 12 2 2 4-4\"/></svg>
              CLIENT-SIDE READY
            </span>
          </div>
          <div class=\"text-xs font-mono text-ink-muted mt-0.5 flex flex-wrap items-center gap-2\">
            <span class=\"text-signal\">@asl:playground-preview</span>
            <span>•</span>
            <span>Direct Access Route (/playground)</span>
            <span>•</span>
            <span class=\"text-emerald-400\">Zero Cloud Dependencies</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Tab Navigation -->
    <div class=\"flex flex-wrap items-center gap-2 mb-8 p-1.5 rounded-2xl bg-surface border border-line max-w-3xl shadow-e1\">
      <button id=\"pg-tab-graph\" type=\"button\" class=\"flex-1 min-w-[120px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all bg-signal text-white shadow-sm cursor-pointer\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" class=\"w-3.5 h-3.5\"><circle cx=\"18\" cy=\"5\" r=\"3\"/><circle cx=\"6\" cy=\"12\" r=\"3\"/><circle cx=\"18\" cy=\"19\" r=\"3\"/><line x1=\"8.59\" x2=\"15.42\" y1=\"13.51\" y2=\"17.49\"/><line x1=\"15.41\" x2=\"8.59\" y1=\"6.51\" y2=\"10.49\"/></svg>
        <span>Untangle Graph</span>
      </button>
      <button id=\"pg-tab-svg\" type=\"button\" class=\"flex-1 min-w-[110px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" class=\"w-3.5 h-3.5\"><path d=\"m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3z\"/></svg>
        <span>SVG Studio</span>
      </button>
      <button id=\"pg-tab-companion\" type=\"button\" class=\"flex-1 min-w-[130px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" class=\"w-3.5 h-3.5\"><rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"/><rect width=\"6\" height=\"6\" x=\"9\" y=\"9\"/><path d=\"M15 2v2\"/><path d=\"M15 20v2\"/><path d=\"M2 15h2\"/><path d=\"M2 9h2\"/><path d=\"M20 15h2\"/><path d=\"M20 9h2\"/><path d=\"M9 2v2\"/><path d=\"M9 20v2\"/></svg>
        <span>AI Companion</span>
      </button>
      <button id=\"pg-tab-sql\" type=\"button\" class=\"flex-1 min-w-[100px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" class=\"w-3.5 h-3.5\"><ellipse cx=\"12\" cy=\"5\" rx=\"9\" ry=\"3\"/><path d=\"M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5\"/><path d=\"M3 12c0 1.66 4 3 9 3s9-1.34 9-3\"/></svg>
        <span>SQL Studio</span>
      </button>
      <button id=\"pg-tab-doctor\" type=\"button\" class=\"flex-1 min-w-[110px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" class=\"w-3.5 h-3.5\"><path d=\"M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10\"/><path d=\"m9 12 2 2 4-4\"/></svg>
        <span>Quality Doctor</span>
      </button>
    </div>

    <!-- Active Studio Panels -->
    <div class=\"rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-4 sm:p-6 shadow-e3\">
      <!-- 1. Graph Untangler Panel -->
      <div id=\"pg-panel-graph\" style=\"display: block;\">
        <div class=\"flex flex-col gap-4 w-full\">
          <div class=\"flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4\">
            <div>
              <h3 class=\"text-xl font-bold text-ink flex items-center gap-2\">
                <span class=\"w-3 h-3 rounded-full bg-signal animate-pulse\"></span>
                AgentScript High-Scale Graph Reactor &amp; Untangler
              </h3>
              <p class=\"text-xs text-ink-muted mt-1\">
                Simulating dynamic nodes &amp; edges with real-time force relaxation and interactive knot teasing
              </p>
            </div>
            <div class=\"flex flex-wrap items-center bg-surface-2 p-1 rounded-xl border border-line gap-1\">
              <span class=\"px-2.5 py-1 text-xs font-mono font-semibold rounded-lg bg-cyan-500/20 text-cyan-400 border border-cyan-500/40\">WebGPU Pipeline (100%)</span>
              <span class=\"px-2.5 py-1 text-xs font-mono text-ink-muted\">WASM SIMD (65%)</span>
            </div>
          </div>
          <div class=\"relative w-full h-[500px] bg-black/50 rounded-2xl border border-line overflow-hidden\">
            <canvas id=\"pg-graph-canvas\" width=\"1200\" height=\"600\" class=\"w-full h-full object-cover cursor-grab active:cursor-grabbing\"></canvas>
            <div class=\"absolute top-3 right-3 bg-black/60 backdrop-blur-md px-3 py-1 rounded-lg border border-white/10 text-[11px] font-mono text-white/60 pointer-events-none\">
              Click &amp; Drag to tease knots apart • ⚡ Untangle Knots
            </div>
            <div class=\"absolute bottom-3 left-3 bg-black/70 backdrop-blur-md px-3 py-1.5 rounded-lg border border-white/10 text-xs font-mono text-white/80 flex items-center gap-2\">
              <span class=\"w-2 h-2 rounded-full bg-cyan-400 animate-pulse\"></span>
              <span>Active Engine: WEBGPU</span>
              <span class=\"text-white/40\">|</span>
              <span>60 FPS</span>
              <span class=\"text-white/40\">|</span>
              <span class=\"text-emerald-400\">Zero Memory Leak</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 2. SVG Studio Panel -->
      <div id=\"pg-panel-svg\" style=\"display: none;\">
        <div class=\"flex flex-col gap-4 w-full\">
          <div class=\"flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4\">
            <div>
              <h3 class=\"text-xl font-bold text-ink flex items-center gap-2\">
                <span class=\"w-3 h-3 rounded-full bg-emerald-400\"></span>
                AgentScript ASN Vector Studio
              </h3>
              <p class=\"text-xs text-ink-muted mt-1\">
                Concise S-expression vector graphics transpiled directly to SVG with 52% token compaction
              </p>
            </div>
            <div class=\"flex items-center gap-2\">
              <span class=\"text-xs text-ink-muted font-mono\">Presets:</span>
              <button onclick=\"selectSvgPreset('logo')\" class=\"px-3 py-1 text-xs font-mono rounded-lg bg-surface border border-line hover:border-signal text-ink transition-all cursor-pointer\">Eddie Mascot</button>
              <button onclick=\"selectSvgPreset('topology')\" class=\"px-3 py-1 text-xs font-mono rounded-lg bg-surface border border-line hover:border-signal text-ink transition-all cursor-pointer\">Swarm Mesh</button>
            </div>
          </div>
          <div class=\"grid grid-cols-1 lg:grid-cols-2 gap-4\">
            <div class=\"flex flex-col gap-2\">
              <span class=\"text-xs font-mono text-ink-3 uppercase\">ASN Vector Source (Agent-Native):</span>
              <textarea id=\"pg-svg-editor\" class=\"w-full h-[380px] p-3 rounded-xl bg-ground border border-line font-mono text-xs text-ink resize-none outline-none focus:border-signal\">(:svg :w 600 :h 360 :v \"0 0 600 360\"
  (:rc :x 0 :y 0 :w 600 :h 360 :f \"#090d16\" :r 24)
  (:circ :cx 300 :cy 180 :r 110 :f \"none\" :s \"rgba(56, 239, 125, 0.2)\" :sw 2)
  (:circ :cx 300 :cy 180 :r 85 :f \"rgba(16, 185, 129, 0.08)\" :s \"#10b981\" :sw 3)
  (:p :d \"M 250 150 L 300 210 L 350 150 Z\" :f \"none\" :s \"#38ef7d\" :sw 4)
  (:circ :cx 300 :cy 150 :r 14 :f \"#00f2fe\" :s \"#ffffff\" :sw 2)
  (:ln :x1 180 :y1 180 :x2 240 :y2 180 :s \"#38ef7d\" :sw 2)
  (:ln :x1 360 :y1 180 :x2 420 :y2 180 :s \"#38ef7d\" :sw 2)
  (:txt :x 215 :y 290 :text \"EDDIE AUTONOMOUS AGENT\" :f \"#38ef7d\" :sz 13 :weight \"bold\")
  (:txt :x 250 :y 315 :text \"AgentScript Vector Engine\" :f \"rgba(255,255,255,0.4)\" :sz 10)
)</textarea>
            </div>
            <div class=\"flex flex-col gap-2\">
              <div class=\"flex items-center justify-between\">
                <span class=\"text-xs font-mono text-ink-3 uppercase\">Rendered SVG Canvas:</span>
                <span class=\"px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 font-mono text-[10px] border border-emerald-500/20\">52% Token Compaction</span>
              </div>
              <div id=\"pg-svg-preview\" class=\"w-full h-[380px] rounded-xl bg-ground border border-line flex items-center justify-center p-2 overflow-hidden\">
                <svg width=\"100%\" height=\"100%\" viewBox=\"0 0 600 360\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"600\" height=\"360\" rx=\"24\" fill=\"#090d16\"/><circle cx=\"300\" cy=\"180\" r=\"110\" stroke=\"rgba(56, 239, 125, 0.2)\" stroke-width=\"2\"/><circle cx=\"300\" cy=\"180\" r=\"85\" fill=\"rgba(16, 185, 129, 0.08)\" stroke=\"#10b981\" stroke-width=\"3\"/><path d=\"M 250 150 L 300 210 L 350 150 Z\" stroke=\"#38ef7d\" stroke-width=\"4\"/><circle cx=\"300\" cy=\"150\" r=\"14\" fill=\"#00f2fe\" stroke=\"#ffffff\" stroke-width=\"2\"/><line x1=\"180\" y1=\"180\" x2=\"240\" y2=\"180\" stroke=\"#38ef7d\" stroke-width=\"2\"/><line x1=\"360\" y1=\"180\" x2=\"420\" y2=\"180\" stroke=\"#38ef7d\" stroke-width=\"2\"/><text x=\"215\" y=\"290\" fill=\"#38ef7d\" font-size=\"13\" font-weight=\"bold\" font-family=\"monospace\">EDDIE AUTONOMOUS AGENT</text><text x=\"250\" y=\"315\" fill=\"rgba(255,255,255,0.4)\" font-size=\"10\" font-family=\"monospace\">AgentScript Vector Engine</text></svg>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 3. AI Companion Panel -->
      <div id=\"pg-panel-companion\" style=\"display: none;\">
        <div class=\"flex flex-col gap-4 w-full\">
          <div class=\"flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4\">
            <div>
              <h3 class=\"text-xl font-bold text-ink flex items-center gap-2\">
                <span class=\"w-3 h-3 rounded-full bg-signal\"></span>
                In-Browser Sovereign AI Companion Cockpit
              </h3>
              <p class=\"text-xs text-ink-muted mt-1\">
                100% sovereign client-side SLM agent synthesis with WebGPU hardware acceleration and gate validation
              </p>
            </div>
            <span class=\"px-3 py-1 rounded-full bg-signal/15 text-signal font-mono text-xs font-bold border border-signal/30\">Offline Airgap Ready</span>
          </div>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-3 my-2\">
            <div class=\"p-3 rounded-xl bg-surface-2 border border-line\"><div class=\"text-[10px] text-ink-muted uppercase font-mono\">Acceleration</div><div class=\"text-sm font-mono font-bold text-emerald-400 mt-1 flex items-center gap-1.5\"><span class=\"w-2 h-2 rounded-full bg-emerald-400 animate-pulse\"></span>WebGPU Active</div></div>
            <div class=\"p-3 rounded-xl bg-surface-2 border border-line\"><div class=\"text-[10px] text-ink-muted uppercase font-mono\">Model Profile</div><div class=\"text-sm font-mono font-bold text-ink mt-1\">Qwen2.5-Coder-1.5B</div></div>
            <div class=\"p-3 rounded-xl bg-surface-2 border border-line\"><div class=\"text-[10px] text-ink-muted uppercase font-mono\">Airgap Isolation</div><div class=\"text-sm font-mono font-bold text-signal mt-1\">Zero Server Roundtrip</div></div>
            <div class=\"p-3 rounded-xl bg-surface-2 border border-line\"><div class=\"text-[10px] text-ink-muted uppercase font-mono\">Verification</div><div class=\"text-sm font-mono font-bold text-signal-soft mt-1\">Pure ASL AST Gate</div></div>
          </div>
          <div class=\"p-5 rounded-2xl bg-ground border border-line flex flex-col gap-4\">
            <label class=\"text-xs font-mono uppercase text-ink-3 font-semibold\">Synthesis Specification &amp; Goal Prompt:</label>
            <textarea class=\"w-full p-3.5 rounded-xl bg-surface border border-line font-mono text-sm text-ink outline-none focus:border-signal resize-none\" rows=\"3\">Draw a glowing neon crystal gemstone badge in ASN notation centered on 320x320 canvas. Compose faceted diamond geometry with colored polygons (:poly) and sharp highlight edges in cyan (#38bdf8) and violet (#a855f7).</textarea>
            <div class=\"flex items-center justify-between pt-2 border-t border-line\">
              <span class=\"text-xs font-mono text-ink-muted\">Sandbox: <strong class=\"text-signal\">Isolated iframe</strong> • Memory: <strong class=\"text-emerald-400\">Linear Buffers</strong></span>
              <button class=\"px-4 py-2 rounded-xl bg-signal hover:bg-signal-strong text-white font-mono text-xs font-semibold shadow-md shadow-signal/20 transition-all flex items-center gap-2 cursor-pointer\">
                <span>⚡ Synthesize Artifact</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- 4. SQL Studio Panel -->
      <div id=\"pg-panel-sql\" style=\"display: none;\">
        <div class=\"flex flex-col gap-4 w-full\">
          <div class=\"flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4\">
            <div>
              <h3 class=\"text-xl font-bold text-ink flex items-center gap-2\">
                <span class=\"w-3 h-3 rounded-full bg-cyan-400\"></span>
                AgentScript SQL Compiler &amp; Parameter Binder
              </h3>
              <p class=\"text-xs text-ink-muted mt-1\">
                Transpile declarative S-expression queries into typed SQL with parameter binding protection
              </p>
            </div>
            <div class=\"flex items-center gap-2\">
              <span class=\"text-xs text-ink-muted font-mono\">Dialect:</span>
              <button onclick=\"setSqlDialect('postgres')\" class=\"px-2.5 py-1 text-xs font-mono rounded-lg bg-surface border border-signal text-signal font-bold cursor-pointer\">PostgreSQL</button>
              <button onclick=\"setSqlDialect('sqlite')\" class=\"px-2.5 py-1 text-xs font-mono rounded-lg bg-surface border border-line text-ink hover:border-signal cursor-pointer\">SQLite</button>
            </div>
          </div>
          <div class=\"grid grid-cols-1 lg:grid-cols-2 gap-4\">
            <div class=\"flex flex-col gap-2\">
              <span class=\"text-xs font-mono text-ink-3 uppercase\">ASL Query Definition:</span>
              <pre class=\"w-full h-[260px] p-3 rounded-xl bg-ground border border-line font-mono text-xs text-emerald-400 overflow-auto\">(q/select [\"id\" \"name\" \"email\" \"status\"]
  (q/from \"users\")
  (q/where (q/and (q/eq \"status\" \"active\")
                  (q/gt \"login_count\" 5)))
  (q/order-by \"created_at\" (q/desc))
  (q/limit 25)
  (q/offset 0))</pre>
            </div>
            <div class=\"flex flex-col gap-2\">
              <span class=\"text-xs font-mono text-ink-3 uppercase\">Transpiled Target SQL:</span>
              <pre id=\"pg-sql-output\" class=\"w-full h-[260px] p-3 rounded-xl bg-ground border border-line font-mono text-xs text-cyan-400 overflow-auto\">SELECT \"id\", \"name\", \"email\", \"status\" FROM \"users\" WHERE (\"status\" = $1) AND (\"login_count\" > $2) ORDER BY \"created_at\" DESC LIMIT 25 OFFSET 0;</pre>
            </div>
          </div>
        </div>
      </div>

      <!-- 5. Quality Doctor Panel -->
      <div id=\"pg-panel-doctor\" style=\"display: none;\">
        <div class=\"flex flex-col gap-4 w-full\">
          <div class=\"flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4\">
            <div>
              <h3 class=\"text-xl font-bold text-ink flex items-center gap-2\">
                <span class=\"w-3 h-3 rounded-full bg-amber-400\"></span>
                ASL AST Quality Doctor &amp; Lint Healer
              </h3>
              <p class=\"text-xs text-ink-muted mt-1\">
                Static quality scoring, anti-pattern detection, and 1-click deterministic AST repair
              </p>
            </div>
            <div class=\"flex items-center gap-3\">
              <div class=\"flex items-center gap-2\">
                <span class=\"text-xs font-mono text-ink-muted\">AST Score:</span>
                <span id=\"pg-doctor-score\" class=\"text-xl font-bold font-mono text-ink\">65</span>
                <span id=\"pg-doctor-badge\" class=\"px-2.5 py-1 text-xs font-mono font-bold rounded-full bg-amber-500/20 text-amber-400 border border-amber-500/30\">Needs Repair</span>
              </div>
              <button id=\"pg-doctor-repair-btn\" onclick=\"toggleDoctorRepair()\" class=\"px-4 py-1.5 rounded-xl bg-signal hover:bg-signal-strong text-white font-mono text-xs font-semibold shadow-md shadow-signal/20 transition-all flex items-center gap-1.5 cursor-pointer\">
                <span>⚡ Auto-Repair AST</span>
              </button>
            </div>
          </div>
          <div class=\"flex flex-col gap-2\">
            <span class=\"text-xs font-mono text-ink-3 uppercase\">Inspected ASL Module:</span>
            <pre id=\"pg-doctor-code\" class=\"w-full h-[280px] p-4 rounded-xl bg-ground border border-line font-mono text-xs text-ink overflow-auto leading-relaxed\">; Anti-pattern: Unused binding &amp; unexported referenced schema type
(module service/config
  :d \"Service configuration and runtime mode.\"
  :x [Config])

(dfe Mode
  (:c fast [] \"Optimized fast mode\")
  (:c slow [] \"Thorough slow mode\"))

(dfs Config
  (:f mode Mode \"Runtime execution mode\"))

(df compute [(n I64)] -> I64
  :d \"Computes runtime metric\"
  (let [(dead-val 42)
        (live-val 10)]
    (+ n live-val)))</pre>
          </div>
        </div>
      </div>
    </div>
  </section>
  
<script>
(function() {
  var tabs = ['graph', 'svg', 'companion', 'sql', 'doctor'];
  tabs.forEach(function(t) {
    var btn = document.getElementById('pg-tab-' + t);
    if (btn) {
      btn.addEventListener('click', function() {
        tabs.forEach(function(ot) {
          var obtn = document.getElementById('pg-tab-' + ot);
          var opnl = document.getElementById('pg-panel-' + ot);
          if (obtn) {
            if (ot === t) {
              obtn.className = 'flex-1 min-w-[120px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all bg-signal text-white shadow-sm cursor-pointer';
            } else {
              obtn.className = 'flex-1 min-w-[120px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all text-ink-2 hover:text-ink hover:bg-inset cursor-pointer';
            }
          }
          if (opnl) {
            opnl.style.display = (ot === t) ? 'block' : 'none';
          }
        });
        if (t === 'graph') initGraphCanvas();
      });
    }
  });

  var graphAnimId = null;
  function initGraphCanvas() {
    var canvas = document.getElementById('pg-graph-canvas');
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    if (!ctx) return;
    if (graphAnimId) cancelAnimationFrame(graphAnimId);

    var width = canvas.width;
    var height = canvas.height;
    var nodeCount = 50;
    var nodes = [];
    var edges = [];

    for (var i = 0; i < nodeCount; i++) {
      var angle = (i / nodeCount) * Math.PI * 2;
      var r = 130 + Math.sin(i * 3) * 60;
      nodes.push({
        x: width / 2 + Math.cos(angle) * r + (Math.random() - 0.5) * 40,
        y: height / 2 + Math.sin(angle) * r + (Math.random() - 0.5) * 40,
        vx: (Math.random() - 0.5) * 1.5,
        vy: (Math.random() - 0.5) * 1.5,
        radius: 4 + Math.random() * 3,
        color: i % 4 === 0 ? '#00f2fe' : i % 4 === 1 ? '#38ef7d' : i % 4 === 2 ? '#c084fc' : '#fbbf24'
      });
    }

    for (var i = 0; i < nodeCount; i++) {
      var next = (i + 1) % nodeCount;
      var cross = (i + 7) % nodeCount;
      edges.push([i, next]);
      if (i % 2 === 0) edges.push([i, cross]);
    }

    var isDragging = false;
    canvas.onmousedown = function(e) {
      isDragging = true;
      var rect = canvas.getBoundingClientRect();
      var mx = (e.clientX - rect.left) * (canvas.width / rect.width);
      var my = (e.clientY - rect.top) * (canvas.height / rect.height);
      untangleAt(mx, my, 150);
    };
    window.onmouseup = function() { isDragging = false; };
    canvas.onmousemove = function(e) {
      if (!isDragging) return;
      var rect = canvas.getBoundingClientRect();
      var mx = (e.clientX - rect.left) * (canvas.width / rect.width);
      var my = (e.clientY - rect.top) * (canvas.height / rect.height);
      untangleAt(mx, my, 120);
    };

    function untangleAt(cx, cy, radius) {
      nodes.forEach(function(n) {
        var dx = n.x - cx;
        var dy = n.y - cy;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < radius && dist > 1) {
          var force = (radius - dist) / radius * 14;
          n.vx += (dx / dist) * force;
          n.vy += (dy / dist) * force;
        }
      });
    }

    function step() {
      edges.forEach(function(e) {
        var a = nodes[e[0]];
        var b = nodes[e[1]];
        var dx = b.x - a.x;
        var dy = b.y - a.y;
        var dist = Math.sqrt(dx * dx + dy * dy) || 1;
        var targetDist = 70;
        var f = (dist - targetDist) * 0.008;
        var fx = (dx / dist) * f;
        var fy = (dy / dist) * f;
        a.vx += fx; a.vy += fy;
        b.vx -= fx; b.vy -= fy;
      });

      nodes.forEach(function(n) {
        var cdx = width / 2 - n.x;
        var cdy = height / 2 - n.y;
        n.vx += cdx * 0.0005;
        n.vy += cdy * 0.0005;
        n.vx *= 0.94;
        n.vy *= 0.94;
        n.x += n.vx;
        n.y += n.vy;
        if (n.x < 30) { n.x = 30; n.vx *= -0.5; }
        if (n.x > width - 30) { n.x = width - 30; n.vx *= -0.5; }
        if (n.y < 30) { n.y = 30; n.vy *= -0.5; }
        if (n.y > height - 30) { n.y = height - 30; n.vy *= -0.5; }
      });

      ctx.fillStyle = '#070a13';
      ctx.fillRect(0, 0, width, height);

      ctx.strokeStyle = 'rgba(168, 85, 247, 0.08)';
      ctx.lineWidth = 1;
      for (var x = 0; x < width; x += 40) {
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
      }
      for (var y = 0; y < height; y += 40) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
      }

      ctx.lineWidth = 1.2;
      edges.forEach(function(e) {
        var a = nodes[e[0]];
        var b = nodes[e[1]];
        var grad = ctx.createLinearGradient(a.x, a.y, b.x, b.y);
        grad.addColorStop(0, 'rgba(192, 132, 252, 0.4)');
        grad.addColorStop(1, 'rgba(56, 239, 125, 0.4)');
        ctx.strokeStyle = grad;
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      });

      nodes.forEach(function(n) {
        ctx.fillStyle = n.color;
        ctx.shadowColor = n.color;
        ctx.shadowBlur = 8;
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.radius, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;
      });

      graphAnimId = requestAnimationFrame(step);
    }
    step();
  }
  initGraphCanvas();

  var svgPresets = {
    logo: {
      asn: '(:svg :w 600 :h 360 :v \"0 0 600 360\"\n  (:rc :x 0 :y 0 :w 600 :h 360 :f \"#090d16\" :r 24)\n  (:circ :cx 300 :cy 180 :r 110 :f \"none\" :s \"rgba(56, 239, 125, 0.2)\" :sw 2)\n  (:circ :cx 300 :cy 180 :r 85 :f \"rgba(16, 185, 129, 0.08)\" :s \"#10b981\" :sw 3)\n  (:p :d \"M 250 150 L 300 210 L 350 150 Z\" :f \"none\" :s \"#38ef7d\" :sw 4)\n  (:circ :cx 300 :cy 150 :r 14 :f \"#00f2fe\" :s \"#ffffff\" :sw 2)\n  (:ln :x1 180 :y1 180 :x2 240 :y2 180 :s \"#38ef7d\" :sw 2)\n  (:ln :x1 360 :y1 180 :x2 420 :y2 180 :s \"#38ef7d\" :sw 2)\n  (:txt :x 215 :y 290 :text \"EDDIE AUTONOMOUS AGENT\" :f \"#38ef7d\" :sz 13 :weight \"bold\")\n  (:txt :x 250 :y 315 :text \"AgentScript Vector Engine\" :f \"rgba(255,255,255,0.4)\" :sz 10)\n)',
      svg: '<svg width=\"100%\" height=\"100%\" viewBox=\"0 0 600 360\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"600\" height=\"360\" rx=\"24\" fill=\"#090d16\"/><circle cx=\"300\" cy=\"180\" r=\"110\" stroke=\"rgba(56, 239, 125, 0.2)\" stroke-width=\"2\"/><circle cx=\"300\" cy=\"180\" r=\"85\" fill=\"rgba(16, 185, 129, 0.08)\" stroke=\"#10b981\" stroke-width=\"3\"/><path d=\"M 250 150 L 300 210 L 350 150 Z\" stroke=\"#38ef7d\" stroke-width=\"4\"/><circle cx=\"300\" cy=\"150\" r=\"14\" fill=\"#00f2fe\" stroke=\"#ffffff\" stroke-width=\"2\"/><line x1=\"180\" y1=\"180\" x2=\"240\" y2=\"180\" stroke=\"#38ef7d\" stroke-width=\"2\"/><line x1=\"360\" y1=\"180\" x2=\"420\" y2=\"180\" stroke=\"#38ef7d\" stroke-width=\"2\"/><text x=\"215\" y=\"290\" fill=\"#38ef7d\" font-size=\"13\" font-weight=\"bold\" font-family=\"monospace\">EDDIE AUTONOMOUS AGENT</text><text x=\"250\" y=\"315\" fill=\"rgba(255,255,255,0.4)\" font-size=\"10\" font-family=\"monospace\">AgentScript Vector Engine</text></svg>'
    },
    topology: {
      asn: '(:svg :w 600 :h 360 :v \"0 0 600 360\"\n  (:rc :x 0 :y 0 :w 600 :h 360 :f \"#070a12\" :r 20)\n  (:ln :x1 140 :y1 180 :x2 300 :y2 100 :s \"rgba(0, 242, 254, 0.4)\" :sw 2)\n  (:ln :x1 140 :y1 180 :x2 300 :y2 260 :s \"rgba(0, 242, 254, 0.4)\" :sw 2)\n  (:ln :x1 300 :y1 100 :x2 460 :y2 180 :s \"rgba(56, 239, 125, 0.4)\" :sw 2)\n  (:ln :x1 300 :y1 260 :x2 460 :y2 180 :s \"rgba(56, 239, 125, 0.4)\" :sw 2)\n  (:rc :x 90 :y 150 :w 100 :h 60 :f \"#0f172a\" :r 12 :s \"#00f2fe\" :sw 2)\n  (:txt :x 105 :y 185 :text \"Coordinator\" :f \"#00f2fe\" :sz 12 :weight \"bold\")\n  (:rc :x 250 :y 70 :w 100 :h 60 :f \"#0f172a\" :r 12 :s \"#38ef7d\" :sw 2)\n  (:txt :x 270 :y 105 :text \"Worker A\" :f \"#38ef7d\" :sz 12 :weight \"bold\")\n  (:rc :x 250 :y 230 :w 100 :h 60 :f \"#0f172a\" :r 12 :s \"#38ef7d\" :sw 2)\n  (:txt :x 270 :y 265 :text \"Worker B\" :f \"#38ef7d\" :sz 12 :weight \"bold\")\n)',
      svg: '<svg width=\"100%\" height=\"100%\" viewBox=\"0 0 600 360\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"600\" height=\"360\" rx=\"20\" fill=\"#070a12\"/><line x1=\"140\" y1=\"180\" x2=\"300\" y2=\"100\" stroke=\"rgba(0, 242, 254, 0.4)\" stroke-width=\"2\"/><line x1=\"140\" y1=\"180\" x2=\"300\" y2=\"260\" stroke=\"rgba(0, 242, 254, 0.4)\" stroke-width=\"2\"/><line x1=\"300\" y1=\"100\" x2=\"460\" y2=\"180\" stroke=\"rgba(56, 239, 125, 0.4)\" stroke-width=\"2\"/><line x1=\"300\" y1=\"260\" x2=\"460\" y2=\"180\" stroke=\"rgba(56, 239, 125, 0.4)\" stroke-width=\"2\"/><rect x=\"90\" y=\"150\" width=\"100\" height=\"60\" rx=\"12\" fill=\"#0f172a\" stroke=\"#00f2fe\" stroke-width=\"2\"/><text x=\"105\" y=\"185\" fill=\"#00f2fe\" font-size=\"12\" font-weight=\"bold\" font-family=\"monospace\">Coordinator</text><rect x=\"250\" y=\"70\" width=\"100\" height=\"60\" rx=\"12\" fill=\"#0f172a\" stroke=\"#38ef7d\" stroke-width=\"2\"/><text x=\"270\" y=\"105\" fill=\"#38ef7d\" font-size=\"12\" font-weight=\"bold\" font-family=\"monospace\">Worker A</text><rect x=\"250\" y=\"230\" width=\"100\" height=\"60\" rx=\"12\" fill=\"#0f172a\" stroke=\"#38ef7d\" stroke-width=\"2\"/><text x=\"270\" y=\"265\" fill=\"#38ef7d\" font-size=\"12\" font-weight=\"bold\" font-family=\"monospace\">Worker B</text></svg>'
    }
  };

  window.selectSvgPreset = function(name) {
    var p = svgPresets[name];
    if (!p) return;
    var ta = document.getElementById('pg-svg-editor');
    var prev = document.getElementById('pg-svg-preview');
    if (ta) ta.value = p.asn;
    if (prev) prev.innerHTML = p.svg;
  };

  var sqlData = {
    postgres: {
      users: \"SELECT \\"id\\", \\"name\\", \\"email\\", \\"status\\" FROM \\"users\\" WHERE (\\"status\\" = $1) AND (\\"login_count\\" > $2) ORDER BY \\"created_at\\" DESC LIMIT 25 OFFSET 0;\",
      joins: \"SELECT \\"u\\".\\"name\\", \\"u\\".\\"email\\", \\"o\\".\\"order_id\\", \\"o\\".\\"amount\\" FROM \\"users\\" AS \\"u\\" INNER JOIN \\"orders\\" AS \\"o\\" ON \\"u\\".\\"id\\" = \\"o\\".\\"user_id\\" WHERE (\\"o\\".\\"amount\\" >= $1) AND (\\"o\\".\\"currency\\" = $2) ORDER BY \\"o\\".\\"created_at\\" DESC LIMIT 50;\"
    },
    sqlite: {
      users: \"SELECT \\"id\\", \\"name\\", \\"email\\", \\"status\\" FROM \\"users\\" WHERE (\\"status\\" = ?) AND (\\"login_count\\" > ?) ORDER BY \\"created_at\\" DESC LIMIT 25 OFFSET 0;\",
      joins: \"SELECT \\"u\\".\\"name\\", \\"u\\".\\"email\\", \\"o\\".\\"order_id\\", \\"o\\".\\"amount\\" FROM \\"users\\" AS \\"u\\" INNER JOIN \\"orders\\" AS \\"o\\" ON \\"u\\".\\"id\\" = \\"o\\".\\"user_id\\" WHERE (\\"o\\".\\"amount\\" >= ?) AND (\\"o\\".\\"currency\\" = ?) ORDER BY \\"o\\".\\"created_at\\" DESC LIMIT 50;\"
    }
  };
  var curDialect = 'postgres';
  var curPreset = 'users';
  window.setSqlDialect = function(d) {
    curDialect = d;
    var code = document.getElementById('pg-sql-output');
    if (code && sqlData[curDialect] && sqlData[curDialect][curPreset]) {
      code.textContent = sqlData[curDialect][curPreset];
    }
  };
  window.setSqlPreset = function(p) {
    curPreset = p;
    var code = document.getElementById('pg-sql-output');
    if (code && sqlData[curDialect] && sqlData[curDialect][curPreset]) {
      code.textContent = sqlData[curDialect][curPreset];
    }
  };

  var doctorRepaired = false;
  window.toggleDoctorRepair = function() {
    doctorRepaired = !doctorRepaired;
    var scoreEl = document.getElementById('pg-doctor-score');
    var badgeEl = document.getElementById('pg-doctor-badge');
    var codeEl = document.getElementById('pg-doctor-code');
    var btn = document.getElementById('pg-doctor-repair-btn');
    if (doctorRepaired) {
      if (scoreEl) scoreEl.textContent = '100';
      if (badgeEl) { badgeEl.textContent = 'PASS (Repaired)'; badgeEl.className = 'px-2.5 py-1 text-xs font-mono font-bold rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'; }
      if (codeEl) codeEl.textContent = '; Auto-repaired by native asl-lint/heal engine\n(module service/config\n  :d \"Service configuration and runtime mode.\"\n  :x [Config Mode])\n\n(dfe Mode\n  (:c fast [] \"Optimized fast mode\")\n  (:c slow [] \"Thorough slow mode\"))\n\n(dfs Config\n  (:f mode Mode \"Runtime execution mode\"))\n\n(df compute [(n I64)] -> I64\n  :d \"Computes runtime metric\"\n  (let [(unused-dead-val 42)\n        (live-val 10)]\n    (+ n live-val)))';
      if (btn) btn.innerHTML = '<span>↺ Reset to Initial</span>';
    } else {
      if (scoreEl) scoreEl.textContent = '65';
      if (badgeEl) { badgeEl.textContent = 'Needs Repair'; badgeEl.className = 'px-2.5 py-1 text-xs font-mono font-bold rounded-full bg-amber-500/20 text-amber-400 border border-amber-500/30'; }
      if (codeEl) codeEl.textContent = '; Anti-pattern: Unused binding & unexported referenced schema type\n(module service/config\n  :d \"Service configuration and runtime mode.\"\n  :x [Config])\n\n(dfe Mode\n  (:c fast [] \"Optimized fast mode\")\n  (:c slow [] \"Thorough slow mode\"))\n\n(dfs Config\n  (:f mode Mode \"Runtime execution mode\"))\n\n(df compute [(n I64)] -> I64\n  :d \"Computes runtime metric\"\n  (let [(dead-val 42)\n        (live-val 10)]\n    (+ n live-val)))';
      if (btn) btn.innerHTML = '<span>⚡ Auto-Repair AST</span>';
    }
  };
})();
</script>

</div>
")

(df playground-view [] -> Str
  :d "Alias for render-playground-view."
  (render-playground-view))
