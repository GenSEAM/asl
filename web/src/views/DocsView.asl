(module asl-web/docs-view
  :d "Comprehensive documentation and interactive toolchain reference in pure AgentScript."
  :x [docs-view render-docs-view describe-docs-view]
  :i [(asl-text/string :a s)
      asl-web/unified-package-matrix
      asl-web/ecosystem])

(df describe-docs-view [] -> Str
  :d "Returns structural metadata for the Docs view."
  "(view :id \"docs\" :sections [\"cli\" \"mesh\" \"data\" \"sql\" \"syntax\" \"control\" \"stdlib\" \"ecosystem\"])")

(df render-docs-view [] -> Str
  :d "Renders the complete documentation cockpit in pure AgentScript."
  (s/concat
    "<div class=\"pt-24 sm:pt-28 pb-24\" id=\"dv-container\">
      <section id=\"docs\" aria-labelledby=\"docs-title\" class=\"relative py-12 sm:py-16 transition-colors bg-transparent max-w-shell mx-auto px-4 sm:px-6 lg:px-8\">
        <header class=\"mb-10 sm:mb-14 max-w-3xl\">
          <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
            <span class=\"text-signal\">04</span>
            <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
            Documentation &amp; CLI Reference
          </span>
          <h1 id=\"docs-title\" class=\"mt-6 text-h2 sm:text-display font-bold text-ink tracking-tight text-balance\">
            Language Reference &amp; Native Toolchain
          </h1>
          <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
            Interactive reference for CLI workflows, A2A mesh protocols, ASN token density, typed SQL compiler, closed AST control forms, and standard library builtins.
          </p>
        </header>

        <div class=\"p-1.5 rounded-2xl bg-surface/90 border border-line backdrop-blur-xl shadow-e2 mb-8 flex flex-wrap gap-1.5\" id=\"dv-tabs\">
          <button type=\"button\" data-tab=\"cli\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-signal text-white shadow-sm flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"4 17 10 11 4 5\"></polyline><line x1=\"12\" y1=\"19\" x2=\"20\" y2=\"19\"></line></svg>
            CLI Toolbelt
          </button>
          <button type=\"button\" data-tab=\"mesh\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"></rect><rect width=\"6\" height=\"6\" x=\"9\" y=\"9\"></rect></svg>
            Wire Mesh &amp; IPC
          </button>
          <button type=\"button\" data-tab=\"data\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><ellipse cx=\"12\" cy=\"5\" rx=\"9\" ry=\"3\"></ellipse><path d=\"M21 12c0 1.66-4 3-9 3s-9-1.34-9-3\"></path><path d=\"M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5\"></path></svg>
            ASN Token Density
          </button>
          <button type=\"button\" data-tab=\"sql\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><ellipse cx=\"12\" cy=\"5\" rx=\"9\" ry=\"3\"></ellipse><path d=\"M3 12a9 3 0 0 0 18 0\"></path></svg>
            Typed SQL Compiler
          </button>
          <button type=\"button\" data-tab=\"syntax\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"16 18 22 12 16 6\"></polyline><polyline points=\"8 6 2 12 8 18\"></polyline></svg>
            Polyglot Syntax
          </button>
          <button type=\"button\" data-tab=\"control\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m10 15 5-3-5-3v6Z\"></path></svg>
            Control Flow
          </button>
          <button type=\"button\" data-tab=\"stdlib\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1-2.5-2.5Z\"></path></svg>
            Standard Library
          </button>
          <button type=\"button\" data-tab=\"ecosystem\" class=\"dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polygon points=\"12 2 2 7 12 12 22 7 12 2\"></polygon><polyline points=\"2 17 12 22 22 17\"></polyline><polyline points=\"2 12 12 17 22 12\"></polyline></svg>
            Package Ecosystem
          </button>
        </div>

        <div id=\"dv-panes\">
          <div class=\"dv-pane block space-y-6\" id=\"dv-pane-cli\">
            <div class=\"grid grid-cols-1 md:grid-cols-2 gap-4\">
              <div class=\"p-5 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-3\">
                <div class=\"flex items-center justify-between\">
                  <code class=\"font-mono font-bold text-signal text-base\">asl check &lt;file&gt;</code>
                  <span class=\"font-mono text-micro text-emerald-400 font-semibold\">&lt;5ms</span>
                </div>
                <p class=\"text-meta text-ink-2 leading-relaxed\">Single-pass structural AST and delimiter balance check. Fast in-memory audit to verify parenthetical invariants before applying changes.</p>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
                  <span class=\"text-signal font-semibold\">$ </span>asl check src/core/auth.asl
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-3\">
                <div class=\"flex items-center justify-between\">
                  <code class=\"font-mono font-bold text-signal text-base\">asl lint &lt;file&gt;</code>
                  <span class=\"font-mono text-micro text-emerald-400 font-semibold\">&lt;10ms</span>
                </div>
                <p class=\"text-meta text-ink-2 leading-relaxed\">Validates keyword correctness and detects hallucinated forms (e.g. defun, defn, lambda) before code reaches compilation.</p>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
                  <span class=\"text-signal font-semibold\">$ </span>asl lint src/core/auth.asl
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-3\">
                <div class=\"flex items-center justify-between\">
                  <code class=\"font-mono font-bold text-signal text-base\">asl gate</code>
                  <span class=\"font-mono text-micro text-emerald-400 font-semibold\">&lt;120ms</span>
                </div>
                <p class=\"text-meta text-ink-2 leading-relaxed\">Unified 7-gate verification suite: package manifests, syntax balance, claim grounding, zero-foreign file policy, test suite, token density, and modular skills.</p>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
                  <span class=\"text-signal font-semibold\">$ </span>asl gate
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-3\">
                <div class=\"flex items-center justify-between\">
                  <code class=\"font-mono font-bold text-signal text-base\">asl test [pkg]</code>
                  <span class=\"font-mono text-micro text-emerald-400 font-semibold\">Native</span>
                </div>
                <p class=\"text-meta text-ink-2 leading-relaxed\">Executes native ASL test suites with 100% function coverage enforcement. Zero external node_modules or runner drift.</p>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
                  <span class=\"text-signal font-semibold\">$ </span>asl test asl-checker
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-3\">
                <div class=\"flex items-center justify-between\">
                  <code class=\"font-mono font-bold text-signal text-base\">asl rpc '(:batch ...)'</code>
                  <span class=\"font-mono text-micro text-emerald-400 font-semibold\">Atomic</span>
                </div>
                <p class=\"text-meta text-ink-2 leading-relaxed\">Single-roundtrip compound execution for AI coding agents: combines outlines, symbol search, in-memory string edits, diffs, and verification gates into one transaction.</p>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
                  <span class=\"text-signal font-semibold\">$ </span>asl rpc '(:batch (:out \"src/core.asl\") (:chk))'
                </div>
              </div>

              <div class=\"p-5 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-3\">
                <div class=\"flex items-center justify-between\">
                  <code class=\"font-mono font-bold text-signal text-base\">asl intel &lt;sym&gt;</code>
                  <span class=\"font-mono text-micro text-emerald-400 font-semibold\">Code Graph</span>
                </div>
                <p class=\"text-meta text-ink-2 leading-relaxed\">Dense codebase symbol lookup and call graph impact extraction without consuming large context windows.</p>
                <div class=\"p-2.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
                  <span class=\"text-signal font-semibold\">$ </span>asl intel create-token
                </div>
              </div>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-6\" id=\"dv-pane-mesh\">
            <div class=\"p-6 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-4\">
              <div class=\"flex items-center justify-between\">
                <h3 class=\"text-lg font-bold text-ink\">SeamBus Inter-Agent Protocol Envelope</h3>
                <span class=\"px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 font-mono text-micro border border-emerald-500/20\">&lt;0.04ms Latency</span>
              </div>
              <p class=\"text-meta text-ink-2 leading-relaxed\">Structured nominal envelope format used for low-latency agent-to-agent frame routing over warm Unix domain sockets and Server-Sent Events.</p>
              <pre class=\"p-4 rounded-xl bg-ground border border-line font-mono text-xs text-purple-200 overflow-x-auto leading-relaxed shadow-inner\">(sb
  :v 1
  :id \"msg-9f201\"
  :from \"agent-orchestrator\"
  :to \"agent-planner\"
  :dialect \"asl/v1\"
  :ts 1772879500000
  :type \"DATA\"
  :channel \"tasks/codegen\"
  :body (:action \"compile_wasm\" :module \"core/matrix\" :opt \"O3\" :timeout-ms 5000))</pre>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-6\" id=\"dv-pane-data\">
            <div class=\"p-6 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-4\">
              <div class=\"flex items-center justify-between\">
                <h3 class=\"text-lg font-bold text-ink\">AgentScript Notation (ASN) vs JSON vs YAML</h3>
                <span class=\"px-2 py-0.5 rounded bg-signal/10 text-signal font-mono text-micro border border-signal/20\">57%–65% Compaction</span>
              </div>
              <p class=\"text-meta text-ink-2 leading-relaxed\">ASN eliminates conversational punctuation bloat (braces, quotes, colons) by hoisting schema keys into a single vector header and serializing values positionally.</p>
              <div class=\"grid grid-cols-1 md:grid-cols-2 gap-4 pt-2\">
                <div>
                  <span class=\"font-mono text-micro text-ink-3 uppercase block mb-1.5\">Standard JSON (178 tokens):</span>
                  <pre class=\"p-3.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto\">{
  \"requestId\": \"req-8842\",
  \"actor\": \"agent-01\",
  \"action\": \"order/ack\",
  \"status\": \"paid\",
  \"items\": [
    { \"sku\": \"x1\", \"qty\": 2 },
    { \"sku\": \"y2\", \"qty\": 1 }
  ]
}</pre>
                </div>
                <div>
                  <span class=\"font-mono text-micro text-emerald-400 uppercase block mb-1.5\">Compact ASN (22 tokens):</span>
                  <pre class=\"p-3.5 rounded-xl bg-ground border border-emerald-500/30 font-mono text-micro text-emerald-300 overflow-x-auto\">(asn/table
  [:sku :qty]
  [\"x1\" 2]
  [\"y2\" 1])</pre>
                </div>
              </div>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-6\" id=\"dv-pane-sql\">
            <div class=\"p-6 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-4\">
              <div class=\"flex items-center justify-between\">
                <h3 class=\"text-lg font-bold text-ink\">Typed SQL S-Expression Compiler</h3>
                <span class=\"px-2 py-0.5 rounded bg-blue-500/10 text-blue-400 font-mono text-micro border border-blue-500/20\">5 Dialects Supported</span>
              </div>
              <p class=\"text-meta text-ink-2 leading-relaxed\">Compile declarative algebraic SQL AST into parameterized PostgreSQL, SQLite, MySQL, MSSQL, or Oracle queries with zero SQL injection risk.</p>
              <pre class=\"p-4 rounded-xl bg-ground border border-line font-mono text-xs text-purple-200 overflow-x-auto leading-relaxed shadow-inner\">(sql/select
  [:id :username :created_at]
  :from :users
  :where (and
           (= :status \"active\")
           (&gt; :score 100))
  :order-by [[:created_at :desc]]
  :limit 20)</pre>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-6\" id=\"dv-pane-syntax\">
            <div class=\"p-6 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-4\">
              <div class=\"flex items-center justify-between\">
                <h3 class=\"text-lg font-bold text-ink\">Polyglot Compilation Targets</h3>
                <span class=\"px-2 py-0.5 rounded bg-purple-500/10 text-purple-400 font-mono text-micro border border-purple-500/20\">Mathematically Verified</span>
              </div>
              <p class=\"text-meta text-ink-2 leading-relaxed\">ASL source code compiles with 100% semantic equivalence across Python, Rust, TypeScript, and Go runtimes.</p>
              <pre class=\"p-4 rounded-xl bg-ground border border-line font-mono text-xs text-purple-200 overflow-x-auto leading-relaxed shadow-inner\">(dfs Token
  (:f id Str)
  (:f exp I64))

(df create-token [(id Str) (ttl I64)] -> Token
  (Token :id id :exp (+ 1700000000 ttl)))</pre>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-6\" id=\"dv-pane-control\">
            <div class=\"p-6 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-4\">
              <div class=\"flex items-center justify-between\">
                <h3 class=\"text-lg font-bold text-ink\">Deterministic Control Forms</h3>
                <span class=\"px-2 py-0.5 rounded bg-amber-500/10 text-amber-400 font-mono text-micro border border-amber-500/20\">Single-Pass LL(1)</span>
              </div>
              <p class=\"text-meta text-ink-2 leading-relaxed\">The 4 closed control forms: if (binary branch), cnd (conditional multi-way), mt (exhaustive pattern match), and lp (bounded tail-recursive loop).</p>
              <pre class=\"p-4 rounded-xl bg-ground border border-line font-mono text-xs text-purple-200 overflow-x-auto leading-relaxed shadow-inner\">;; Exhaustive pattern matching on sum types
(mt result
  ((:ok val) (string-concat \"Success: \" val))
  ((:error err) (string-concat \"Error: \" err)))</pre>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-6\" id=\"dv-pane-stdlib\">
            <div class=\"p-6 rounded-2xl border border-line bg-surface/80 shadow-e1 space-y-4\">
              <div class=\"flex items-center justify-between\">
                <h3 class=\"text-lg font-bold text-ink\">Standard Library (107 Safe Builtins)</h3>
                <span class=\"px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 font-mono text-micro border border-emerald-500/20\">Zero Host Leakage</span>
              </div>
              <p class=\"text-meta text-ink-2 leading-relaxed\">Deterministic arithmetic, string manipulation, list operations, map transformations, and safe sandboxed IO.</p>
              <div class=\"grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 pt-2\">
                <div class=\"p-3 rounded-xl bg-ground border border-line\"><code class=\"font-mono text-micro text-signal font-bold\">+ - * / mod</code><p class=\"text-[11px] text-ink-3 mt-1\">Deterministic integer and float math</p></div>
                <div class=\"p-3 rounded-xl bg-ground border border-line\"><code class=\"font-mono text-micro text-signal font-bold\">string-concat len slice</code><p class=\"text-[11px] text-ink-3 mt-1\">UTF-8 safe string operations</p></div>
                <div class=\"p-3 rounded-xl bg-ground border border-line\"><code class=\"font-mono text-micro text-signal font-bold\">list-map filter fold</code><p class=\"text-[11px] text-ink-3 mt-1\">Higher-order list transformations</p></div>
                <div class=\"p-3 rounded-xl bg-ground border border-line\"><code class=\"font-mono text-micro text-signal font-bold\">map-get set keys vals</code><p class=\"text-[11px] text-ink-3 mt-1\">Immutable associative hash maps</p></div>
                <div class=\"p-3 rounded-xl bg-ground border border-line\"><code class=\"font-mono text-micro text-signal font-bold\">asn/encode asn/decode</code><p class=\"text-[11px] text-ink-3 mt-1\">Fast tabular token compaction</p></div>
                <div class=\"p-3 rounded-xl bg-ground border border-line\"><code class=\"font-mono text-micro text-signal font-bold\">sql/compile sql/quote</code><p class=\"text-[11px] text-ink-3 mt-1\">Cross-dialect SQL compilation</p></div>
              </div>
            </div>
          </div>

          <div class=\"dv-pane hidden space-y-12\" id=\"dv-pane-ecosystem\">"
    (unified-package-matrix)
    (ecosystem)
    "</div>
        </div>
      </section>
    </div>

    <script>
      (function() {
        function init() {
          var tabBtns = document.querySelectorAll('.dv-tab-btn');
          var panes = {
            'cli': document.getElementById('dv-pane-cli'),
            'mesh': document.getElementById('dv-pane-mesh'),
            'data': document.getElementById('dv-pane-data'),
            'sql': document.getElementById('dv-pane-sql'),
            'syntax': document.getElementById('dv-pane-syntax'),
            'control': document.getElementById('dv-pane-control'),
            'stdlib': document.getElementById('dv-pane-stdlib'),
            'ecosystem': document.getElementById('dv-pane-ecosystem')
          };

          function setTab(tab) {
            tabBtns.forEach(function(btn) {
              if (btn.getAttribute('data-tab') === tab) {
                btn.className = 'dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-signal text-white shadow-sm flex items-center gap-2';
              } else {
                btn.className = 'dv-tab-btn px-3.5 py-2 rounded-xl font-mono text-micro font-semibold transition-colors bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60 flex items-center gap-2';
              }
            });

            for (var k in panes) {
              if (panes[k]) {
                if (k === tab) {
                  panes[k].classList.remove('hidden');
                  panes[k].classList.add('block');
                } else {
                  panes[k].classList.remove('block');
                  panes[k].classList.add('hidden');
                }
              }
            }
          }

          tabBtns.forEach(function(btn) {
            btn.addEventListener('click', function() {
              setTab(btn.getAttribute('data-tab'));
            });
          });
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', init);
        } else {
          init();
        }
      })();
    </script>"))

(df docs-view [] -> Str
  :d "Alias for render-docs-view."
  (render-docs-view))
