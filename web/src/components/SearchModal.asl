(module asl-web/search-modal
  :d "Search modal dialog component in pure AgentScript."
  :x [search-modal render-search-modal]
  :i [])

(df render-search-modal [] -> Str
  :d "Renders the universal search modal with fast filtering and keyboard navigation."
  "<div id=\"search-modal-root\" class=\"fixed inset-0 z-50 items-start justify-center pt-20 sm:pt-28 px-4 bg-black/60 backdrop-blur-md animate-fade-in\" style=\"display: none;\">
    <div id=\"search-modal-dialog\" class=\"relative w-full max-w-xl rounded-2xl border border-line bg-surface/95 backdrop-blur-2xl shadow-e4 overflow-hidden\">
      <div class=\"flex items-center gap-3 px-4 py-3.5 border-b border-line\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5 text-signal\"><circle cx=\"11\" cy=\"11\" r=\"8\"></circle><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line></svg>
        <input
          type=\"text\"
          id=\"sm-input\"
          placeholder=\"Search documentation, CLI tools, protocol...\"
          class=\"flex-1 bg-transparent border-none outline-none font-mono text-body text-ink placeholder:text-ink-3\"
        />
        <button
          type=\"button\"
          id=\"sm-close-btn\"
          class=\"p-1 rounded-lg text-ink-3 hover:text-ink hover:bg-inset transition-colors cursor-pointer\"
          title=\"Close search\"
        >
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><line x1=\"18\" y1=\"6\" x2=\"6\" y2=\"18\"></line><line x1=\"6\" y1=\"6\" x2=\"18\" y2=\"18\"></line></svg>
        </button>
      </div>

      <div id=\"sm-results-list\" class=\"max-h-80 overflow-y-auto p-2 divide-y divide-line/40\">
        <!-- Result 1 -->
        <a href=\"/#agent-way\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"the agent way why languages designed for typing hands fail autonomous agents docs\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><path d=\"M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z\"></path><path d=\"M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z\"></path></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">The Agent Way</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">docs</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">Why languages designed for typing hands fail autonomous agents.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>

        <!-- Result 2 -->
        <a href=\"/ecosystem\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"multi-runtime ecosystem wasm rust typescript python sql cross-compilation toolchain\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><rect x=\"4\" y=\"4\" width=\"16\" height=\"16\" rx=\"2\"></rect><rect x=\"9\" y=\"9\" width=\"6\" height=\"6\"></rect><line x1=\"9\" y1=\"1\" x2=\"9\" y2=\"4\"></line><line x1=\"15\" y1=\"1\" x2=\"15\" y2=\"4\"></line><line x1=\"9\" y1=\"20\" x2=\"9\" y2=\"23\"></line><line x1=\"15\" y1=\"20\" x2=\"15\" y2=\"23\"></line><line x1=\"20\" y1=\"9\" x2=\"23\" y2=\"9\"></line><line x1=\"20\" y1=\"14\" x2=\"23\" y2=\"14\"></line><line x1=\"1\" y1=\"9\" x2=\"4\" y2=\"9\"></line><line x1=\"1\" y1=\"14\" x2=\"4\" y2=\"14\"></line></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">Multi-Runtime Ecosystem</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">toolchain</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">Wasm, Rust, TypeScript, Python, and SQL cross-compilation.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>

        <!-- Result 3 -->
        <a href=\"/roadmap\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"canons roadmap strategic trajectory agent meshes self-hosted runtimes grammar\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">Canons &amp; Roadmap</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">grammar</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">Strategic trajectory, agent meshes, and self-hosted runtimes.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>

        <!-- Result 4 -->
        <a href=\"/docs\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"documentation cli reference toolchain commands grammar invariants quick start guides docs\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><polyline points=\"4 17 10 11 4 5\"></polyline><line x1=\"12\" y1=\"19\" x2=\"20\" y2=\"19\"></line></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">Documentation &amp; CLI Reference</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">docs</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">Toolchain commands, grammar invariants, and quick start guides.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>

        <!-- Result 5 -->
        <a href=\"/#a2a-protocol\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"a2a wire protocol low-latency agent-to-agent s-expression frame serialization protocol\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><polyline points=\"16 18 22 12 16 6\"></polyline><polyline points=\"8 6 2 12 8 18\"></polyline></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">A2A Wire Protocol</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">protocol</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">Low-latency agent-to-agent S-expression frame serialization.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>

        <!-- Result 6 -->
        <a href=\"/llms.txt\" target=\"_blank\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"agent specification /llms.txt machine-readable formal grammar invariant tables for ai agents grammar\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><path d=\"M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z\"></path><path d=\"M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z\"></path></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">Agent Specification (/llms.txt)</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">grammar</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">Machine-readable formal grammar and invariant tables for AI agents.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>

        <!-- Result 7 (Blog) -->
        <a href=\"/blog/manifesto\" class=\"sm-item group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all\" data-search=\"manifesto dual-projection principle pure agentscript token compaction blog\">
          <div class=\"flex items-center gap-3\">
            <div class=\"p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors text-signal\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4\"><path d=\"M4 22h16a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2H8a2 2 0 0 0-2 2v16a2 2 0 0 1-2 2Zm0 0a2 2 0 0 1-2-2v-9c0-1.1.9-2 2-2h2M18 14h-8M15 18h-5M10 6h8v4h-8z\"></path></svg>
            </div>
            <div>
              <div class=\"flex items-center gap-2\">
                <span class=\"font-semibold text-ink text-body group-hover:text-signal transition-colors\">The Agentic Language Manifesto</span>
                <span class=\"font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3\">blog</span>
              </div>
              <p class=\"text-meta text-ink-3 mt-0.5 line-clamp-1\">The dual-projection principle and why agents need native notation.</p>
            </div>
          </div>
          <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0\"><line x1=\"5\" y1=\"12\" x2=\"19\" y2=\"12\"></line><polyline points=\"12 5 19 12 12 19\"></polyline></svg>
        </a>
      </div>

      <div class=\"px-4 py-2.5 bg-sunken/60 border-t border-line flex items-center justify-between font-mono text-[11px] text-ink-3\">
        <span>Navigate with mouse or keyboard</span>
        <span>ESC to close</span>
      </div>
    </div>
  </div>

  <script>
    (function() {
      function init() {
        var root = document.getElementById('search-modal-root');
        var dialog = document.getElementById('search-modal-dialog');
        var input = document.getElementById('sm-input');
        var closeBtn = document.getElementById('sm-close-btn');
        var items = document.querySelectorAll('.sm-item');

        if (!root) return;

        function openModal() {
          root.style.display = 'flex';
          if (input) {
            input.value = '';
            filterItems('');
            setTimeout(function() { input.focus(); }, 50);
          }
        }

        function closeModal() {
          root.style.display = 'none';
        }

        function filterItems(query) {
          var q = (query || '').toLowerCase().trim();
          items.forEach(function(item) {
            var text = (item.getAttribute('data-search') || '') + ' ' + (item.textContent || '');
            if (!q || text.toLowerCase().indexOf(q) !== -1) {
              item.style.display = 'flex';
            } else {
              item.style.display = 'none';
            }
          });
        }

        window.addEventListener('open-search', openModal);
        window.addEventListener('open-search-modal', openModal);

        window.addEventListener('keydown', function(e) {
          if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
            e.preventDefault();
            if (root.style.display === 'flex') {
              closeModal();
            } else {
              openModal();
            }
          } else if (e.key === 'Escape' && root.style.display === 'flex') {
            closeModal();
          }
        });

        if (input) {
          input.addEventListener('input', function() {
            filterItems(input.value);
          });
        }

        if (closeBtn) {
          closeBtn.addEventListener('click', closeModal);
        }

        root.addEventListener('click', function(e) {
          if (dialog && !dialog.contains(e.target)) {
            closeModal();
          }
        });

        items.forEach(function(item) {
          item.addEventListener('click', function(e) {
            var href = item.getAttribute('href');
            if (href && !href.startsWith('/llms') && !href.startsWith('http')) {
              e.preventDefault();
              window.history.pushState(null, '', href);
              window.dispatchEvent(new PopStateEvent('popstate'));
              closeModal();
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

(df search-modal [] -> Str
  :d "Alias for render-search-modal."
  (render-search-modal))
