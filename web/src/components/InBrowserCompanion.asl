(package :web-in-browser-companion
  :doc "In-Browser WebLLM Companion and Multi-Pass SLM Execution Cockpit in pure AgentScript.")

(df render-studio-tabs ()
  :d "Studio mode selector tabs: Vector SVG, 2D Retro Games, Mini-Websites."
  "<div class=\"flex flex-wrap items-center gap-2 p-1.5 bg-ground-2 dark:bg-ground-sunken rounded-xl border border-line-subtle mb-6\">
    <button class=\"companion-tab active px-4 py-2 text-xs font-mono font-medium rounded-lg bg-surface border border-line shadow-sm text-signal transition-all flex items-center gap-2\" data-studio=\"svg\">
      <span>🎨</span><span>Vector SVG Studio</span>
    </button>
    <button class=\"companion-tab px-4 py-2 text-xs font-mono font-medium rounded-lg text-ink-3 hover:text-ink hover:bg-surface/50 transition-all flex items-center gap-2\" data-studio=\"games\">
      <span>🕹️</span><span>Playable 2D Games</span>
    </button>
    <button class=\"companion-tab px-4 py-2 text-xs font-mono font-medium rounded-lg text-ink-3 hover:text-ink hover:bg-surface/50 transition-all flex items-center gap-2\" data-studio=\"website\">
      <span>🌐</span><span>Single-File Websites</span>
    </button>
  </div>")

(df render-prompt-picker ()
  :d "Prompt template badges for 1-click execution."
  "<div class=\"flex flex-wrap items-center gap-2 mb-6\">
    <span class=\"text-micro font-mono uppercase text-ink-3 mr-1\">Quick Templates:</span>
    <button class=\"px-3 py-1.5 text-xs font-mono rounded-lg bg-surface border border-line text-ink-2 hover:text-signal hover:border-signal/50 transition-all\" data-prompt=\"gem\">💎 Neon Crystal</button>
    <button class=\"px-3 py-1.5 text-xs font-mono rounded-lg bg-surface border border-line text-ink-2 hover:text-signal hover:border-signal/50 transition-all\" data-prompt=\"rocket\">🚀 Rocket Icon</button>
    <button class=\"px-3 py-1.5 text-xs font-mono rounded-lg bg-surface border border-line text-ink-2 hover:text-signal hover:border-signal/50 transition-all\" data-prompt=\"tetris\">🕹️ Retro Tetris</button>
    <button class=\"px-3 py-1.5 text-xs font-mono rounded-lg bg-surface border border-line text-ink-2 hover:text-signal hover:border-signal/50 transition-all\" data-prompt=\"calculator\">🧮 Terminal Calc</button>
    <button class=\"px-3 py-1.5 text-xs font-mono rounded-lg bg-surface border border-line text-ink-2 hover:text-signal hover:border-signal/50 transition-all\" data-prompt=\"chameleon\">🦎 Mascot Badge</button>
  </div>")

(df render-telemetry-bar ()
  :d "In-Browser WebGPU & WebLLM hardware acceleration telemetry bar."
  "<div class=\"grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6\">
    <div class=\"p-3 rounded-xl bg-surface border border-line flex flex-col gap-1\">
      <span class=\"text-micro font-mono uppercase text-ink-3\">Acceleration Engine</span>
      <span class=\"text-sm font-mono font-semibold text-emerald-400 flex items-center gap-1.5\">
        <span class=\"w-2 h-2 rounded-full bg-emerald-400 animate-pulse\"></span>WebGPU Hardware
      </span>
    </div>
    <div class=\"p-3 rounded-xl bg-surface border border-line flex flex-col gap-1\">
      <span class=\"text-micro font-mono uppercase text-ink-3\">Active Model Spec</span>
      <span class=\"text-sm font-mono font-semibold text-ink\">Qwen2.5-Coder-1.5B</span>
    </div>
    <div class=\"p-3 rounded-xl bg-surface border border-line flex flex-col gap-1\">
      <span class=\"text-micro font-mono uppercase text-ink-3\">Airgap Boundary</span>
      <span class=\"text-sm font-mono font-semibold text-signal\">100% Offline / Local</span>
    </div>
    <div class=\"p-3 rounded-xl bg-surface border border-line flex flex-col gap-1\">
      <span class=\"text-micro font-mono uppercase text-ink-3\">Gate Evaluation</span>
      <span class=\"text-sm font-mono font-semibold text-signal-soft\">Pure ASL / VDOM Gate</span>
    </div>
  </div>")

(df render-sandbox-cockpit ()
  :d "Preview sandbox container and terminal inspection tabs."
  "<div class=\"rounded-2xl border border-line bg-ground-2 dark:bg-ground-sunken overflow-hidden shadow-2xl\">
    <div class=\"px-4 py-3 border-b border-line bg-surface/50 flex flex-wrap items-center justify-between gap-3\">
      <div class=\"flex items-center gap-2\">
        <span class=\"w-3 h-3 rounded-full bg-rose-500/80 inline-block\"></span>
        <span class=\"w-3 h-3 rounded-full bg-amber-500/80 inline-block\"></span>
        <span class=\"w-3 h-3 rounded-full bg-emerald-500/80 inline-block\"></span>
        <span class=\"ml-2 font-mono text-xs text-ink-3\">In-Browser Companion Cockpit (Zero-Server Airgap)</span>
      </div>
      <div class=\"flex items-center gap-2\">
        <span class=\"px-2 py-0.5 text-micro font-mono rounded bg-signal/10 text-signal border border-signal/20\">WebAssembly + WebGPU</span>
      </div>
    </div>
    <div class=\"p-6\">
      <div class=\"companion-input-area mb-6\">
        <label class=\"block text-xs font-mono uppercase text-ink-3 mb-2 font-medium\">Prompt Specification & Synthesis Goal:</label>
        <div class=\"relative\">
          <textarea class=\"w-full p-4 rounded-xl bg-surface border border-line focus:border-signal focus:ring-1 focus:ring-signal font-mono text-sm text-ink placeholder-ink-4 outline-none resize-none transition-all\" rows=\"3\" placeholder=\"Describe the artifact, game, or component in natural language...\">Draw a glowing neon crystal gemstone badge in ASN notation centered on 320x320 canvas. Compose faceted diamond geometry with colored polygons (:poly) and sharp highlight edges in cyan (#38bdf8) and violet (#a855f7).</textarea>
        </div>
      </div>
      <div class=\"flex flex-wrap items-center justify-between gap-4 pt-2 border-t border-line-subtle\">
        <div class=\"flex items-center gap-3 text-xs font-mono text-ink-3\">
          <span>Verification: <strong class=\"text-emerald-400\">Balanced AST</strong></span>
          <span>•</span>
          <span>Sandbox: <strong class=\"text-signal\">Isolated iframe</strong></span>
        </div>
        <div class=\"flex items-center gap-3\">
          <button class=\"px-5 py-2.5 rounded-xl bg-signal hover:bg-signal-strong text-white font-mono text-xs font-semibold shadow-lg shadow-signal/20 transition-all flex items-center gap-2\">
            <span>⚡ Generate Artifact</span>
          </button>
        </div>
      </div>
    </div>
  </div>")

(df render-in-browser-companion ()
  :d "Complete InBrowserCompanion cockpit section."
  (s/concat
    "<section id=\"in-browser-companion\" class=\"py-12 relative z-10 w-full\">"
    (render-telemetry-bar)
    (render-studio-tabs)
    (render-prompt-picker)
    (render-sandbox-cockpit)
    "</section>"))

(df in-browser-companion ()
  (render-in-browser-companion))
