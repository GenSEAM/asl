(module asl-web/engineering-blog
  :d "Engineering Blog preview component in pure AgentScript."
  :x [engineering-blog render-engineering-blog blog-preview-view]
  :i [])

(df render-engineering-blog [] -> Str
  :d "Renders the engineering blog teaser section with top essays, metadata, and router navigation."
  "<section id=\"writing\" aria-labelledby=\"writing-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      
      <div class=\"flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-2\">
        <header class=\"mb-6 sm:mb-8 max-w-3xl\">
          <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
            <span class=\"text-signal\">05</span>
            <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
            Engineering Blog
          </span>
          <h2 id=\"writing-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
            Notes on building a language and infrastructure for synthetic intelligences.
          </h2>
        </header>

        <a href=\"/blog\" class=\"asl-blog-nav shrink-0 mb-8 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-line hover:border-signal text-xs font-mono text-ink-2 hover:text-signal transition-colors bg-surface/80\">
          <span>View All Essays</span>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
            <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
            <polyline points=\"12 5 19 12 12 19\"></polyline>
          </svg>
        </a>
      </div>

      <p class=\"text-sm sm:text-base text-ink-2 max-w-3xl mb-8 leading-relaxed\">
        Deep architectural notes from the AgentScript systems group: why LLMs struggle with whitespace
        and borrow checkers, how AST interface compression eliminates the 78% token tax, and how in-memory
        WASI execution runs test suites in 0.04ms.
      </p>

      <div class=\"grid grid-cols-1 md:grid-cols-2 gap-6 border-t border-line pt-8\">
        
        <article data-slug=\"why-llms-struggle-with-python-and-rust\" class=\"asl-blog-card p-6 rounded-xl border border-line bg-surface/60 hover:bg-surface/90 hover:border-signal/50 cursor-pointer transition-all duration-200 group flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-2.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-semibold\">
                Language Theory &amp; Compilers
              </span>
              <span class=\"flex items-center gap-1\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\">
                  <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                  <polyline points=\"12 6 12 12 16 14\"></polyline>
                </svg>
                6 min read
              </span>
            </div>

            <h3 class=\"text-base sm:text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2.5 leading-snug\">
              How to Fix Agentic Coding: Why Autonomous LLMs Break on Human Languages (and What Replaces Them)
            </h3>

            <p class=\"text-xs sm:text-sm text-ink-2 leading-relaxed mb-4 line-clamp-3\">
              Why indentation and borrow-checked syntax trap coding agents in 38% syntax repair loops, and what deterministic single-pass S-expressions solve.
            </p>
          </div>

          <div>
            <div class=\"flex flex-wrap gap-1.5 mb-3\">
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                Agentic Coding
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                Syntax Repair Tax
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                S-Expressions
              </span>
            </div>

            <div class=\"flex items-center justify-between pt-2.5 border-t border-line/50 text-xs font-mono text-ink-3\">
              <span>2026-09-08</span>
              <span class=\"flex items-center gap-1 text-signal group-hover:translate-x-0.5 transition-transform font-medium\">
                <span>Read Essay</span>
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                  <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
                  <polyline points=\"12 5 19 12 12 19\"></polyline>
                </svg>
              </span>
            </div>
          </div>
        </article>

        
        <article data-slug=\"token-economy-and-structural-compression\" class=\"asl-blog-card p-6 rounded-xl border border-line bg-surface/60 hover:bg-surface/90 hover:border-signal/50 cursor-pointer transition-all duration-200 group flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-2.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-semibold\">
                Token Economy &amp; Serialization
              </span>
              <span class=\"flex items-center gap-1\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\">
                  <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                  <polyline points=\"12 6 12 12 16 14\"></polyline>
                </svg>
                8 min read
              </span>
            </div>

            <h3 class=\"text-base sm:text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2.5 leading-snug\">
              Stop Burning Money on JSON Context: How Structural Compaction Cuts LLM Bills by 65%
            </h3>

            <p class=\"text-xs sm:text-sm text-ink-2 leading-relaxed mb-4 line-clamp-3\">
              Why JSON repeats keys on every row, how tabular ASN hoists schemas into vector headers, and how structural compaction slashes LLM context bills by 64.7% without changing model weights.
            </p>
          </div>

          <div>
            <div class=\"flex flex-wrap gap-1.5 mb-3\">
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                Token Economy
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                ASN Tabular
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                -65% Context
              </span>
            </div>

            <div class=\"flex items-center justify-between pt-2.5 border-t border-line/50 text-xs font-mono text-ink-3\">
              <span>2026-09-07</span>
              <span class=\"flex items-center gap-1 text-signal group-hover:translate-x-0.5 transition-transform font-medium\">
                <span>Read Essay</span>
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                  <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
                  <polyline points=\"12 5 19 12 12 19\"></polyline>
                </svg>
              </span>
            </div>
          </div>
        </article>

        
        <article data-slug=\"from-vibe-code-to-wasm-in-0-04ms\" class=\"asl-blog-card p-6 rounded-xl border border-line bg-surface/60 hover:bg-surface/90 hover:border-signal/50 cursor-pointer transition-all duration-200 group flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-2.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-semibold\">
                Runtime &amp; Execution
              </span>
              <span class=\"flex items-center gap-1\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\">
                  <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                  <polyline points=\"12 6 12 12 16 14\"></polyline>
                </svg>
                5 min read
              </span>
            </div>

            <h3 class=\"text-base sm:text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2.5 leading-snug\">
              Killing Docker Spin-Up Latency: How We Run Agent Test Sandboxes in 0.038ms
            </h3>

            <p class=\"text-xs sm:text-sm text-ink-2 leading-relaxed mb-4 line-clamp-3\">
              Why spinning up Docker containers and microVMs (1.2s–12s) cripples agent action loops, and how compiling AgentScript directly to in-memory WebAssembly preview1 linear memory executes in 0.038ms.
            </p>
          </div>

          <div>
            <div class=\"flex flex-wrap gap-1.5 mb-3\">
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                WebAssembly
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                WASI Preview 1
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                0.038ms Sandbox
              </span>
            </div>

            <div class=\"flex items-center justify-between pt-2.5 border-t border-line/50 text-xs font-mono text-ink-3\">
              <span>2026-09-07</span>
              <span class=\"flex items-center gap-1 text-signal group-hover:translate-x-0.5 transition-transform font-medium\">
                <span>Read Essay</span>
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                  <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
                  <polyline points=\"12 5 19 12 12 19\"></polyline>
                </svg>
              </span>
            </div>
          </div>
        </article>

        
        <article data-slug=\"the-token-density-fallacy-and-machine-understandability\" class=\"asl-blog-card p-6 rounded-xl border border-line bg-surface/60 hover:bg-surface/90 hover:border-signal/50 cursor-pointer transition-all duration-200 group flex flex-col justify-between\">
          <div>
            <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-2.5\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-semibold\">
                Architecture &amp; Language Theory
              </span>
              <span class=\"flex items-center gap-1\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\">
                  <circle cx=\"12\" cy=\"12\" r=\"10\"></circle>
                  <polyline points=\"12 6 12 12 16 14\"></polyline>
                </svg>
                9 min read
              </span>
            </div>

            <h3 class=\"text-base sm:text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2.5 leading-snug\">
              Why Disemvoweling Breaks BPE: How Naive Token Optimization Destroys Agent Intelligence
            </h3>

            <p class=\"text-xs sm:text-sm text-ink-2 leading-relaxed mb-4 line-clamp-3\">
              Why naive identifier compression like ctermtxt breaks BPE subtokenization, how synonym collisions cost thousands of repair tokens, and the findings of our 2-round adversarial consultation with Claude Fable 5.
            </p>
          </div>

          <div>
            <div class=\"flex flex-wrap gap-1.5 mb-3\">
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                BPE Subtokens
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                Identifier Economics
              </span>
              <span class=\"inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface border border-line/60 text-ink-3\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><path d=\"M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z\"></path><path d=\"M7 7h.01\"></path></svg>
                Claude Fable 5
              </span>
            </div>

            <div class=\"flex items-center justify-between pt-2.5 border-t border-line/50 text-xs font-mono text-ink-3\">
              <span>2026-09-07</span>
              <span class=\"flex items-center gap-1 text-signal group-hover:translate-x-0.5 transition-transform font-medium\">
                <span>Read Essay</span>
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\">
                  <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
                  <polyline points=\"12 5 19 12 12 19\"></polyline>
                </svg>
              </span>
            </div>
          </div>
        </article>
      </div>

      <div class=\"mt-8 pt-6 border-t border-line flex justify-center\">
        <a href=\"/blog\" class=\"asl-blog-nav inline-flex items-center gap-2 px-5 py-2.5 rounded-lg border border-line bg-surface hover:border-signal text-sm font-mono text-ink hover:text-signal transition-all shadow-sm group\">
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-signal\">
            <path d=\"M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z\"></path>
            <path d=\"M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z\"></path>
          </svg>
          <span>Explore All 20 Technical Essays in the Blog</span>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 group-hover:translate-x-0.5 transition-transform\">
            <line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line>
            <polyline points=\"12 5 19 12 12 19\"></polyline>
          </svg>
        </a>
      </div>

    </div>
  </section>
  <script>
    (function() {
      function routeTo(path) {
        if (window.history && window.history.pushState) {
          window.history.pushState({}, '', path);
          window.dispatchEvent(new PopStateEvent('popstate'));
          window.scrollTo({ top: 0, behavior: 'smooth' });
        } else {
          window.location.href = path;
        }
      }

      function init() {
        document.querySelectorAll('.asl-blog-card').forEach(function(card) {
          card.addEventListener('click', function(e) {
            var slug = card.getAttribute('data-slug');
            if (slug) {
              e.preventDefault();
              routeTo('/blog/' + slug);
            }
          });
        });

        document.querySelectorAll('.asl-blog-nav').forEach(function(nav) {
          nav.addEventListener('click', function(e) {
            e.preventDefault();
            routeTo('/blog');
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

(df engineering-blog [] -> Str
  :d "Alias for render-engineering-blog."
  (render-engineering-blog))

(df blog-preview-view [] -> Str
  :d "Alias for render-engineering-blog."
  (render-engineering-blog))
