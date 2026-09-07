(module asl-web/blog-view
  :d "Engineering Blog & Technical Insights view in pure AgentScript."
  :x [blog-view render-blog-view]
  :i [])

(df render-blog-view [] -> Str
  :d "Renders the complete engineering blog listing with interactive category filters, search, and article cards."
  "<main class=\"flex-1 max-w-6xl mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full\" id=\"bv-main\">
    <!-- Header -->
    <header class=\"mb-16 sm:mb-20 max-w-3xl\">
      <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
        <span class=\"text-signal\">06</span>
        <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
        Engineering Blog &amp; Technical Insights
      </span>
      <h2 id=\"blog-header\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
        Notes on building a language and infrastructure for synthetic intelligences.
      </h2>
    </header>

    <!-- Intro Subtitle -->
    <p class=\"text-base sm:text-lg text-ink-2 max-w-3xl mb-10 leading-relaxed\">
      Deep technical essays on compiler engineering, deterministic S-expressions, token economics,
      in-memory WebAssembly sandboxing, and inter-agent wire protocols. Designed for human engineers
      and structured for agentic RAG discovery.
    </p>

    <!-- View Mode Tabs -->
    <div class=\"flex flex-wrap items-center gap-2 mb-8 p-1.5 bg-surface-2/60 border border-line rounded-2xl w-fit\" id=\"bv-mode-tabs\">
      <button type=\"button\" data-mode=\"all\" class=\"bv-mode-btn flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-mono font-medium transition-all bg-signal text-ground font-semibold shadow-sm\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\"><path d=\"M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z\"></path><path d=\"M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z\"></path></svg>
        <span>All Published (19)</span>
      </button>
      <button type=\"button\" data-mode=\"flagship\" class=\"bv-mode-btn flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-mono font-medium transition-all text-ink-2 hover:text-ink\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\"><path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path></svg>
        <span>Flagship Deep Dives (4)</span>
      </button>
    </div>

    <!-- Filter and Search Bar -->
    <div class=\"flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4 mb-8 pb-6 border-b border-line\">
      <!-- Category Pills -->
      <div class=\"flex flex-wrap items-center gap-1.5\" id=\"bv-cat-pills\">
        <button type=\"button\" data-cat=\"All\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-signal text-ground font-semibold border-signal shadow-sm\">
          All <span class=\"opacity-60 text-[10px]\">(19)</span>
        </button>
        <button type=\"button\" data-cat=\"Tools &amp; Compiler Architecture\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Tools &amp; Architecture <span class=\"opacity-60 text-[10px]\">(6)</span>
        </button>
        <button type=\"button\" data-cat=\"Architecture &amp; Language Theory\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Language Theory <span class=\"opacity-60 text-[10px]\">(5)</span>
        </button>
        <button type=\"button\" data-cat=\"Multi-Agent Protocols &amp; Mesh\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Agent Protocols <span class=\"opacity-60 text-[10px]\">(4)</span>
        </button>
        <button type=\"button\" data-cat=\"Small Language Models &amp; Local Inference\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Local SLMs <span class=\"opacity-60 text-[10px]\">(4)</span>
        </button>
      </div>

      <!-- Search Input -->
      <div class=\"relative min-w-[240px]\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none\"><circle cx=\"11\" cy=\"11\" r=\"8\"></circle><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line></svg>
        <input
          type=\"text\"
          id=\"bv-search-input\"
          placeholder=\"Search essays, tags, topics...\"
          class=\"w-full pl-9 pr-3 py-1.5 text-xs font-mono rounded-lg border border-line bg-surface text-ink placeholder:text-ink-3 focus:outline-none focus:border-signal transition-colors\"
        />
      </div>
    </div>

    <!-- Post Grid -->
    <div class=\"grid grid-cols-1 md:grid-cols-2 gap-6\" id=\"bv-posts-grid\">
      <!-- Post 1 -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-agentic-toolchain-and-native-action-loops\" data-importance=\"flagship\" data-cat=\"Tools &amp; Compiler Architecture\" data-search=\"the agentic toolchain continuous action loops native verification gates pure asl architecture genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Tools &amp; Compiler Architecture</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">&starf; Flagship</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The Agentic Toolchain: Continuous Action Loops, Native Verification Gates, and Pure ASL Architecture</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why standard bash wrappers fail autonomous agents, and how persistent execution sessions, 7 in-memory verification gates, and 100% test coverage create a deterministic toolchain for AI code generation.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 &bull; GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 2 -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-token-density-fallacy-and-machine-understandability\" data-importance=\"flagship\" data-cat=\"Architecture &amp; Language Theory\" data-search=\"the token-density fallacy and machine understandability genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Architecture &amp; Language Theory</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">&starf; Flagship</span>
            </div>
            <span>10 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The Token-Density Fallacy and Machine Understandability</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why aggressive code compression harms LLM attention heads, and how AgentScript balances syntactic density with structural transparency.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 &bull; GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 3 -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"slm-benchmark-thinking-vs-non-thinking-on-apple-silicon\" data-importance=\"flagship\" data-cat=\"Small Language Models &amp; Local Inference\" data-search=\"slm benchmark thinking vs non-thinking on apple silicon local inference m1\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Small Language Models</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">&starf; Flagship</span>
            </div>
            <span>12 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">SLM Benchmark: Thinking vs Non-Thinking on Apple Silicon M1</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Empirical throughput, memory bandwidth pressure, and AST parsing accuracy across Gemma 2B, Qwen 2.5 3B, and DeepSeek R1 1.5B.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 &bull; GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 4 -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"sub-millisecond-agent-to-agent-wire-protocol\" data-importance=\"flagship\" data-cat=\"Multi-Agent Protocols &amp; Mesh\" data-search=\"sub-millisecond agent-to-agent wire protocol a2a s-expression json benchmark\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Multi-Agent Protocols &amp; Mesh</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">&starf; Flagship</span>
            </div>
            <span>9 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Sub-Millisecond Agent-to-Agent Wire Protocol</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Replacing conversational JSON over HTTP with nominal S-expression frames over warm Unix domain sockets and SSE channels.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 &bull; GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>
    </div>
  </main>

  <script>
    (function() {
      function init() {
        var modeBtns = document.querySelectorAll('.bv-mode-btn');
        var catBtns = document.querySelectorAll('.bv-cat-btn');
        var searchInput = document.getElementById('bv-search-input');
        var cards = document.querySelectorAll('.bv-post-card');

        var currentMode = 'all';
        var currentCat = 'All';
        var currentQuery = '';

        function filter() {
          var q = currentQuery.toLowerCase().trim();
          cards.forEach(function(card) {
            var imp = card.getAttribute('data-importance');
            var cat = card.getAttribute('data-cat') || '';
            var sr = (card.getAttribute('data-search') || '') + ' ' + (card.textContent || '');

            var matchMode = (currentMode === 'all' || imp === 'flagship');
            var matchCat = (currentCat === 'All' || cat.toLowerCase().indexOf(currentCat.toLowerCase()) !== -1);
            var matchQuery = (!q || sr.toLowerCase().indexOf(q) !== -1);

            if (matchMode && matchCat && matchQuery) {
              card.style.display = 'flex';
            } else {
              card.style.display = 'none';
            }
          });
        }

        modeBtns.forEach(function(btn) {
          btn.addEventListener('click', function() {
            var mode = btn.getAttribute('data-mode');
            currentMode = mode;
            modeBtns.forEach(function(b) {
              if (b === btn) {
                b.className = 'bv-mode-btn flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-mono font-medium transition-all bg-signal text-ground font-semibold shadow-sm';
              } else {
                b.className = 'bv-mode-btn flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-mono font-medium transition-all text-ink-2 hover:text-ink';
              }
            });
            filter();
          });
        });

        catBtns.forEach(function(btn) {
          btn.addEventListener('click', function() {
            var cat = btn.getAttribute('data-cat');
            currentCat = cat;
            catBtns.forEach(function(b) {
              if (b === btn) {
                b.className = 'bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-signal text-ground font-semibold border-signal shadow-sm';
              } else {
                b.className = 'bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2';
              }
            });
            filter();
          });
        });

        if (searchInput) {
          searchInput.addEventListener('input', function() {
            currentQuery = searchInput.value;
            filter();
          });
        }

        cards.forEach(function(card) {
          card.addEventListener('click', function() {
            var slug = card.getAttribute('data-slug');
            if (slug) {
              var href = '/blog/' + slug;
              window.history.pushState(null, '', href);
              window.dispatchEvent(new PopStateEvent('popstate'));
              window.scrollTo(0, 0);
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

(df blog-view [] -> Str
  :d "Alias for render-blog-view."
  (render-blog-view))
