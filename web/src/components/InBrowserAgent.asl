(module asl-web/in-browser-agent
  :d "In-Browser Autonomous Companion showcase component in pure AgentScript."
  :x [in-browser-agent render-in-browser-agent browser-agent-view]
  :i [])

(df render-in-browser-agent [] -> Str
  :d "Renders the in-browser companion visualizer cockpit with live tab switching and three execution modes."
  "<section id=\"browser-agent\" aria-labelledby=\"browser-agent-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent overflow-hidden\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      
      <header class=\"mb-16 sm:mb-20 max-w-3xl mx-auto text-center\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">05</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          In-Browser Autonomous Companion
        </span>
        <h2 id=\"browser-agent-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          An Agent Inside the Browser. Full Visual Context &amp; Direct In-Tab Execution.
        </h2>
        <p class=\"mt-4 text-lead text-ink-2 max-w-2xl text-balance mx-auto\">
          Stop fighting brittle remote DevTools and bloated HTML scraping. Connect your external agent (Antigravity, Cursor, Claude Code) directly to an in-browser companion agent. It checks render readiness, extracts visual layout state, executes actions locally, and coordinates with on-board WebGPU SLMs or cloud vision models.
        </p>
      </header>

      <!-- Prominent Status Badge & Direct Creator Studio Link -->
      <div class=\"flex flex-wrap items-center justify-center gap-3 -mt-6 mb-12\">
        <span class=\"inline-flex items-center gap-2 px-4 py-1.5 rounded-full border border-amber-500/40 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wider shadow-sm\">
          <span class=\"w-2 h-2 rounded-full bg-amber-400 animate-pulse\"></span>
          In Active Development // Research Preview
        </span>
        <a href=\"/studio\" class=\"iba-route-link inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-signal hover:bg-signal-hover text-white font-mono text-micro font-bold tracking-wide shadow-md transition-all hover:scale-105\">
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
            <path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path>
            <path d=\"M5 3v4\"></path><path d=\"M19 17v4\"></path><path d=\"M3 5h4\"></path><path d=\"M17 19h4\"></path>
          </svg>
          <span>Launch Tri-Studio (SVG &middot; Games &middot; Websites) &rarr;</span>
        </a>
      </div>

      <!-- Interactive Browser Cockpit Visualizer -->
      <div class=\"max-w-5xl mx-auto rounded-3xl border border-line bg-surface/85 backdrop-blur-2xl shadow-e3 overflow-hidden\">
        <!-- Browser Top Navigation Chrome -->
        <div class=\"px-5 py-3.5 border-b border-line bg-inset/70 flex flex-wrap items-center justify-between gap-4\">
          <div class=\"flex items-center gap-2.5\">
            <span class=\"w-3 h-3 rounded-full bg-rose-500/70\"></span>
            <span class=\"w-3 h-3 rounded-full bg-amber-500/70\"></span>
            <span class=\"w-3 h-3 rounded-full bg-emerald-500/70\"></span>
            <div class=\"ml-3 px-3 py-1 rounded-lg bg-ground border border-line text-micro font-mono text-ink-3 flex items-center gap-2\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal\">
                <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                <path d=\"M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20\"></path>
                <path d=\"M2 12h20\"></path>
              </svg>
              <span>https://checkout.store.dev/cart</span>
            </div>
          </div>

          <div class=\"flex items-center gap-3 font-mono text-micro\">
            <span class=\"inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-signal/15 border border-signal/30 text-signal font-semibold\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\">
                <path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path>
                <path d=\"M5 3v4\"></path><path d=\"M19 17v4\"></path><path d=\"M3 5h4\"></path><path d=\"M17 19h4\"></path>
              </svg>
              On-Board SLM / Vision API
            </span>
            <span class=\"inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-emerald-500/15 border border-emerald-500/30 text-emerald-400\">
              <span class=\"w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse\"></span>
              Agent Bus: Connected (0.04ms)
            </span>
          </div>
        </div>

        <!-- Cockpit Content Grid -->
        <div class=\"grid grid-cols-1 lg:grid-cols-12\">
          <!-- Left Column: Semantic Context & Render Readiness -->
          <div class=\"lg:col-span-7 p-6 sm:p-8 border-b lg:border-b-0 lg:border-r border-line flex flex-col justify-between\">
            <div>
              <div class=\"flex items-center justify-between pb-4 border-b border-line flex-wrap gap-2\">
                <div>
                  <h3 class=\"font-mono text-xs font-bold uppercase tracking-wider text-ink\">
                    In-Tab Agent Inspector
                  </h3>
                  <p class=\"text-micro text-ink-3 mt-0.5\">
                    Live visual context, render readiness &amp; instruction execution
                  </p>
                </div>
                <div class=\"flex rounded-lg bg-inset p-0.5 border border-line\">
                  <button type=\"button\" id=\"iba-tab-context\" class=\"px-2.5 py-1 rounded-md font-mono text-micro transition-all bg-signal text-ground font-semibold shadow-sm\">
                    UI Context &amp; Render
                  </button>
                  <button type=\"button\" id=\"iba-tab-action\" class=\"px-2.5 py-1 rounded-md font-mono text-micro transition-all text-ink-3 hover:text-ink\">
                    Action Execution
                  </button>
                  <button type=\"button\" id=\"iba-tab-raw\" class=\"px-2.5 py-1 rounded-md font-mono text-micro transition-all text-ink-3 hover:text-ink\">
                    Raw HTML (Bloat)
                  </button>
                </div>
              </div>

              <!-- Code Panel Display -->
              <div class=\"mt-5 p-4 rounded-2xl bg-ground border border-line font-mono text-xs leading-relaxed overflow-x-auto min-h-[230px]\">
                <!-- Context Tab Panel -->
                <div id=\"iba-panel-context\">
                  <pre class=\"text-purple-300\"><span class=\"text-ink-3\">;; Render readiness &amp; visual layout synthesized by browser agent</span>
<span class=\"text-signal\">(! browser/context</span>
  :route <span class=\"text-emerald-400\">&quot;/cart&quot;</span>
  :render-status <span class=\"text-emerald-400\">:hydrated-ready</span>
  :layout-shifts <span class=\"text-blue-300\">0.0</span>
  :visual-viewport [1440 900]
  :visible-actionables [
    (:target <span class=\"text-amber-300\">&quot;#coupon-code&quot;</span> :role <span class=\"text-blue-300\">:input</span> :val <span class=\"text-emerald-400\">&quot;&quot;</span>)
    (:target <span class=\"text-amber-300\">&quot;#btn-apply&quot;</span> :role <span class=\"text-blue-300\">:button</span> :enabled <span class=\"text-emerald-400\">true</span>)
    (:target <span class=\"text-amber-300\">&quot;#btn-checkout&quot;</span> :role <span class=\"text-blue-300\">:button</span> :enabled <span class=\"text-emerald-400\">true</span>)
  ]
  :vision-critique <span class=\"text-emerald-400\">&quot;Layout verified clean: zero overlapping elements&quot;</span>)</pre>
                </div>

                <!-- Action Tab Panel -->
                <div id=\"iba-panel-action\" class=\"hidden\">
                  <pre class=\"text-emerald-300\"><span class=\"text-ink-3\">;; External agent (Antigravity/Cursor) dispatches instruction</span>
<span class=\"text-signal\">(? browser/exec</span>
  :action <span class=\"text-blue-300\">:click</span>
  :target <span class=\"text-amber-300\">&quot;#btn-checkout&quot;</span>
  :wait-for <span class=\"text-emerald-400\">:navigation-complete</span>
  :verify-render <span class=\"text-blue-300\">true</span>)

<span class=\"text-ink-3\">;; In-browser agent executes locally and returns confirmation</span>
<span class=\"text-signal\">(! browser/ack</span>
  :status <span class=\"text-emerald-400\">:completed</span>
  :new-route <span class=\"text-emerald-400\">&quot;/checkout/shipping&quot;</span>
  :render-ready <span class=\"text-blue-300\">true</span>
  :latency-ms <span class=\"text-amber-300\">4.2</span>)</pre>
                </div>

                <!-- Raw Tab Panel -->
                <div id=\"iba-panel-raw\" class=\"hidden\">
                  <pre class=\"text-ink-3 opacity-60\">&lt;div id=&quot;root&quot; class=&quot;min-h-screen bg-slate-950 flex flex-col&quot;&gt;
  &lt;header class=&quot;h-16 border-b border-slate-800 px-6 flex items-center justify-between&quot;&gt;
    &lt;div class=&quot;flex items-center gap-3&quot;&gt;...&lt;/div&gt;
    &lt;div class=&quot;relative&quot;&gt;&lt;button class=&quot;...&quot;&gt;Profile&lt;/button&gt;&lt;/div&gt;
  &lt;/header&gt;
  &lt;main class=&quot;flex-1 p-8 grid grid-cols-12 gap-6&quot;&gt;
    &lt;!-- 52,000 more characters of unparsed markup &amp; script tags that burn prompt tokens --&gt;
  &lt;/main&gt;
&lt;/div&gt;</pre>
                </div>
              </div>
            </div>

            <div class=\"mt-6 pt-4 border-t border-line flex items-center justify-between text-micro font-mono text-ink-3\">
              <span class=\"flex items-center gap-1.5 text-emerald-400 font-semibold\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                  <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                  <path d=\"m9 12 2 2 4-4\"></path>
                </svg>
                Prompt Reduction: 52.4 kB &rarr; 1.2 kB (-97%)
              </span>
              <span>Zero Selenium / DevTools bloat</span>
            </div>
          </div>

          <!-- Right Column: Key Modes of Operation -->
          <div class=\"lg:col-span-5 p-6 sm:p-8 bg-inset/30 flex flex-col justify-between space-y-6\">
            <div>
              <span class=\"font-mono text-micro uppercase text-signal font-semibold tracking-wider\">
                Flexible In-Browser Topology
              </span>
              <h4 class=\"mt-2 text-h3 font-bold text-ink leading-snug\">
                One Extension. Three Execution Modes.
              </h4>
              <p class=\"mt-2.5 text-sm text-ink-2 leading-relaxed\">
                External agents don't connect directly to clumsy browser windows. They talk to an intelligent in-tab agent that understands DOM, layout readiness, and visual state.
              </p>
            </div>

            <div class=\"space-y-3.5\">
              <div class=\"flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line\">
                <div class=\"p-2 rounded-xl bg-ground border border-line text-signal shrink-0\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\">
                    <polygon points=\"13 2 3 14 12 14 11 22 21 10 12 10 13 2\"></polygon>
                  </svg>
                </div>
                <div>
                  <h5 class=\"text-xs font-bold text-ink\">1. Zero-LLM Deterministic Bus</h5>
                  <p class=\"text-micro text-ink-2 mt-0.5\">Operates purely as a high-speed tool execution bus. Handles events, layout reads, and page readiness without burning any LLM tokens.</p>
                </div>
              </div>

              <div class=\"flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line\">
                <div class=\"p-2 rounded-xl bg-ground border border-line text-signal shrink-0\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\">
                    <rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"></rect>
                    <rect width=\"6\" height=\"6\" x=\"9\" y=\"9\" rx=\"1\"></rect>
                    <path d=\"M15 2v2\"></path><path d=\"M15 20v2\"></path><path d=\"M2 15h2\"></path><path d=\"M2 9h2\"></path><path d=\"M20 15h2\"></path><path d=\"M20 9h2\"></path><path d=\"M9 2v2\"></path><path d=\"M9 20v2\"></path>
                  </svg>
                </div>
                <div>
                  <h5 class=\"text-xs font-bold text-ink\">2. Local On-Board SLM (WebGPU)</h5>
                  <p class=\"text-micro text-ink-2 mt-0.5\">Runs lightweight 0.5B-1.5B models directly in the tab via WebGPU for instant client-side autonomy without sending data to clouds.</p>
                </div>
              </div>

              <div class=\"flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line\">
                <div class=\"p-2 rounded-xl bg-ground border border-line text-signal shrink-0\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\">
                    <path d=\"M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z\"></path>
                    <circle cx=\"12\" cy=\"12\" r=\"3\"></circle>
                  </svg>
                </div>
                <div>
                  <h5 class=\"text-xs font-bold text-ink\">3. Cloud Vision Bridge</h5>
                  <p class=\"text-micro text-ink-2 mt-0.5\">Connects with Gemini Flash, Claude Sonnet, or GPT-4o Vision to evaluate UI rendering, detect visual bugs, and verify complete layout state.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

    </div>
  </section>
  <script>
    (function() {
      function init() {
        var tabContext = document.getElementById('iba-tab-context');
        var tabAction = document.getElementById('iba-tab-action');
        var tabRaw = document.getElementById('iba-tab-raw');

        var panelContext = document.getElementById('iba-panel-context');
        var panelAction = document.getElementById('iba-panel-action');
        var panelRaw = document.getElementById('iba-panel-raw');

        var activeClass = 'px-2.5 py-1 rounded-md font-mono text-micro transition-all bg-signal text-ground font-semibold shadow-sm';
        var inactiveClass = 'px-2.5 py-1 rounded-md font-mono text-micro transition-all text-ink-3 hover:text-ink';

        function show(tab) {
          if (!tabContext || !tabAction || !tabRaw) return;
          tabContext.className = (tab === 'context') ? activeClass : inactiveClass;
          tabAction.className = (tab === 'action') ? activeClass : inactiveClass;
          tabRaw.className = (tab === 'raw') ? activeClass : inactiveClass;

          if (panelContext) panelContext.className = (tab === 'context') ? '' : 'hidden';
          if (panelAction) panelAction.className = (tab === 'action') ? '' : 'hidden';
          if (panelRaw) panelRaw.className = (tab === 'raw') ? '' : 'hidden';
        }

        if (tabContext) tabContext.addEventListener('click', function() { show('context'); });
        if (tabAction) tabAction.addEventListener('click', function() { show('action'); });
        if (tabRaw) tabRaw.addEventListener('click', function() { show('raw'); });

        document.querySelectorAll('.iba-route-link').forEach(function(link) {
          link.addEventListener('click', function(e) {
            var href = link.getAttribute('href');
            if (href && window.history && window.history.pushState) {
              e.preventDefault();
              window.history.pushState({}, '', href);
              window.dispatchEvent(new PopStateEvent('popstate'));
              window.scrollTo({ top: 0, behavior: 'smooth' });
            }
          });
        });
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
      } else {
        init();
      }
    })();
  </script>")

(df in-browser-agent [] -> Str
  :d "Alias for render-in-browser-agent."
  (render-in-browser-agent))

(df browser-agent-view [] -> Str
  :d "Alias for render-in-browser-agent."
  (render-in-browser-agent))
