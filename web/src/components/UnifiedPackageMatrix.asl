(module asl-web/unified-package-matrix
  :d "Unified Package Matrix showcase component in pure AgentScript."
  :x [unified-package-matrix render-unified-package-matrix package-matrix-view]
  :i [])

(df render-unified-package-matrix [] -> Str
  :d "Renders the 8 official AgentScript packages matrix with stage filters, search bar, and interactive code inspect."
  "<div class=\"space-y-10\" id=\"upm-container\">
    <!-- Ecosystem Summary Stats -->
    <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-4\">
      <div class=\"p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1\">
        <span class=\"font-mono text-micro uppercase text-ink-3\">Unified Packages</span>
        <p class=\"mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono\">08</p>
        <span class=\"text-meta text-signal font-mono mt-1 inline-block\">Stages 1–3 Complete</span>
      </div>
      <div class=\"p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1\">
        <span class=\"font-mono text-micro uppercase text-ink-3\">Token Compaction</span>
        <p class=\"mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono\">57%–78%</p>
        <span class=\"text-meta text-emerald-400 font-mono mt-1 inline-block\">Over Verbose JSON</span>
      </div>
      <div class=\"p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1\">
        <span class=\"font-mono text-micro uppercase text-ink-3\">IPC Mesh Latency</span>
        <p class=\"mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono\">&lt;0.04ms</p>
        <span class=\"text-meta text-signal font-mono mt-1 inline-block\">Warm Socket / SSE</span>
      </div>
      <div class=\"p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1\">
        <span class=\"font-mono text-micro uppercase text-ink-3\">Process Safety</span>
        <p class=\"mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono\">0 Leaks</p>
        <span class=\"text-meta text-emerald-400 font-mono mt-1 inline-block\">Jailed Sandboxing</span>
      </div>
    </div>

    <!-- Filter and Search Bar -->
    <div class=\"flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4 p-3 sm:p-4 rounded-2xl border border-line bg-surface/90 backdrop-blur-xl shadow-e1\">
      <!-- Stage Filter Buttons -->
      <div class=\"flex flex-wrap items-center gap-1.5 sm:gap-2\" id=\"upm-stage-filters\">
        <button type=\"button\" data-stage=\"all\" class=\"upm-stage-btn px-3 py-1.5 rounded-xl font-mono text-micro transition-all bg-signal text-white font-semibold shadow-sm\">
          All Packages (8)
        </button>
        <button type=\"button\" data-stage=\"1\" class=\"upm-stage-btn px-3 py-1.5 rounded-xl font-mono text-micro transition-all bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60\">
          Stage 1: Core (2)
        </button>
        <button type=\"button\" data-stage=\"2\" class=\"upm-stage-btn px-3 py-1.5 rounded-xl font-mono text-micro transition-all bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60\">
          Stage 2: Harness (4)
        </button>
        <button type=\"button\" data-stage=\"3\" class=\"upm-stage-btn px-3 py-1.5 rounded-xl font-mono text-micro transition-all bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60\">
          Stage 3: Visual (2)
        </button>
      </div>

      <!-- Search Input -->
      <div class=\"relative flex-1 max-w-md\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none\">
          <circle cx=\"11\" cy=\"11\" r=\"8\"></circle>
          <line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line>
        </svg>
        <input type=\"text\" id=\"upm-search-input\" placeholder=\"Search packages, APIs, or metrics...\" class=\"w-full pl-9 pr-4 py-1.5 rounded-xl bg-inset border border-line font-mono text-meta text-ink placeholder:text-ink-3 focus:outline-none focus:border-signal/60 transition-colors\" />
      </div>
    </div>

    <!-- Packages Grid -->
    <div class=\"grid grid-cols-1 lg:grid-cols-2 gap-6\" id=\"upm-packages-grid\">

      <!-- Package 1: asl-codec -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-codec\" data-stage=\"1\" data-search=\"asl-codec universal asn codec token compaction json single-pass ll(1)\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><ellipse cx=\"12\" cy=\"5\" rx=\"9\" ry=\"3\"></ellipse><path d=\"M21 12c0 1.66-4 3-9 3s-9-1.34-9-3\"></path><path d=\"M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5\"></path></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-codec</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">Universal ASN codec with 57%–65% token compaction over JSON</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-blue-500/10 text-blue-400 border-blue-500/30\">Stage 1: Core</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-emerald-400\"></span>Stable</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">Universal AgentScript Notation (ASN) reader, writer, and algebraic serializer. Slashes LLM token consumption by eliminating punctuation deadweight (braces, quotes, colons) and hoisting tabular schemas into single positional headers.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Hoists repetitive schema keys once into header vector</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Encodes tabular batches as compact positional value tuples</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Isomorphic transcode between human ASL and compact ASN</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Single-pass LL(1) parse eliminates syntax repair loops</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Token Compaction</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">57%–65% vs JSON</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">100-Row Dataset</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">1,601 vs 3,802 tokens</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Syntax Overhead</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">0 Braces / Quotes</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Grammar</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Single-Pass LL(1)</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(asn/encode)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(asn/decode)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(asn/encode-table)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(asn/validate)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">data/exchange.asl</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>(module data/exchange
  :d \"Universal ASN tabular serialization with hoisted schema.\"
  :i [(asl-codec/asn :a asn)])

(:d \"Hoists schema keys once; streams 57% fewer tokens than JSON\")
(asn/encode-table
  [:id :sku :qty :status]
  [[101 \"A-44\" 5 \"shipped\"]
   [102 \"B-12\" 1 \"pending\"]
   [103 \"C-99\" 12 \"delivered\"]])</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-codec</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-codec\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 2: asl-sh -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-sh\" data-stage=\"1\" data-search=\"asl-sh process guard streaming reducer middle eviction window retention posix_spawn\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><polyline points=\"4 17 10 11 4 5\"></polyline><line x1=\"12\" x2=\"20\" y1=\"19\" y2=\"19\"></line></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-sh</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">Process guard, streaming reducer with window retention and middle eviction</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-blue-500/10 text-blue-400 border-blue-500/30\">Stage 1: Core</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-emerald-400\"></span>Stable</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">High-assurance process execution toolkit with structured pipelines and typed channel redirection. Features a pure streaming reducer with head/tail window retention, middle eviction markers, consecutive duplicate suppression, ANSI stripping, and zero shell injection vulnerabilities.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Direct execve/posix_spawn invocation preventing shell injection bugs</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Head/tail retention windowing prevents context window exhaustion</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Evicts middle noise with &quot;... [N lines evicted from buffer] ...&quot;</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Automated semantic test and compiler diagnostic extraction</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Shell Injections</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">0 Vectors</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Window Retention</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">500h / 1500t</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Middle Eviction</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Automatic Markers</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Dedup Suppression</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">100% Repeats</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(proc/cmd)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(proc/exec!)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(reducer/reduce-stream)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(reducer/default-config)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">admin/pipeline.asl</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>(module admin/pipeline
  :d \"Run compiler tasks with head/tail retention windowing.\"
  :i [(asl-sh/process :a proc)
      (asl-sh/reducer :a reducer)])

(:d \"Direct posix_spawn execution streamed into windowing reducer\")
(let [(cmd (proc/cmd \"cargo\" [\"test\" \"--all\"]))
      (stream (proc/exec-stream! cmd))]
  (reducer/reduce-stream stream
    (reducer/ReductionConfig :head-limit 500 :tail-limit 1500 :dedup-repeats true)))</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-sh</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-sh\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 3: asl-agent-core -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-agent-core\" data-stage=\"2\" data-search=\"asl-agent-core onion middleware capability negotiator topological dag\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><rect width=\"16\" height=\"16\" x=\"4\" y=\"4\" rx=\"2\"></rect><rect width=\"6\" height=\"6\" x=\"9\" y=\"9\" rx=\"1\"></rect><path d=\"M15 2v2\"></path><path d=\"M15 20v2\"></path><path d=\"M2 15h2\"></path><path d=\"M2 9h2\"></path><path d=\"M20 15h2\"></path><path d=\"M20 9h2\"></path><path d=\"M9 2v2\"></path><path d=\"M9 20v2\"></path></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-agent-core</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">Onion middleware pipeline, capability negotiator</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-purple-500/10 text-signal border-signal/30\">Stage 2: Harness</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-purple-400\"></span>Active</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">The composable execution engine for autonomous agents. Houses a modular onion middleware pipeline supporting pre-call, post-call, filter, mutate, and audit hooks with topological DAG ordering, dynamic capability negotiation, and structured tool dispatch.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Topological DAG ordering ensures correct hook execution order</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Pre-call, post-call, filter, mutate, and audit middleware hooks</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Dynamic capability negotiator enforcing strict permission boundaries</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Unified tool registry with formal parameter schemas and event bus</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Dispatch Latency</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&lt;0.05ms</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Ordering Engine</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Topological DAG</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Middleware Hooks</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">5 Extension Types</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Permission Gates</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Zero-Prompt</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(OnionPipeline)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(dispatch-tool-call)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(make-middleware)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(AgentRegistry)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">agent/supervisor.asl</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>(module agent/supervisor
  :d \"Onion middleware dispatch with topological DAG ordering.\"
  :i [(asl-agent-core/onion :a onion)
      (asl-agent-core/core :a core)])

(:d \"Register security and telemetry hooks with topological dependencies\")
(let [(auth-mw  (onion/make-middleware \"auth\" \"Capability Gate\" onion/kind-filter 10 [] []))
      (audit-mw (onion/make-middleware \"audit\" \"Telemetry Logger\" onion/kind-audit 20 [\"auth\"] []))
      (pipeline (onion/make-pipeline [auth-mw audit-mw]))]
  (onion/dispatch-tool-call pipeline context tool-call))</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-agent-core</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-agent-core\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 4: asl-eddie -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-eddie\" data-stage=\"2\" data-search=\"asl-eddie superposition swarm orchestrator react frontline barge-in\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><polygon points=\"13 2 3 14 12 14 11 22 21 10 12 10 13 2\"></polygon></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-eddie</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">Superposition swarm orchestrator, intent triage &amp; ReAct frontline agent</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-purple-500/10 text-signal border-signal/30\">Stage 2: Harness</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-purple-400\"></span>Active</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">High-velocity ReAct agent runtime and swarm orchestrator engineered for instant voice and autonomous workflows. Launches in under 100ms with a strict &le;24MB RSS ceiling, zero permission prompts for authorized workspace paths, and conversational barge-in latency under 5ms.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Sub-100ms launch speed vs ~2,480ms legacy Node/Transformers</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>&le;24MB RSS peak memory ceiling under concurrent errand load</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Zero-prompt declarative capability permissions with path jailing</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Instant conversational barge-in cutoff (&lt;5ms) for natural speech</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Cold Start</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&lt;100ms</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">RSS Ceiling</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&le;24MB</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Barge-In Latency</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&lt;5ms</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Permission Prompts</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">0 Prompts</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(execute-react-loop)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(triage-intent)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(workspace-jail)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(barge-in-cutoff)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">voice/assistant.asl</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>(module voice/assistant
  :d \"Low-latency voice assistant with instant barge-in cutoff.\"
  :i [(asl-eddie/agent :a eddie)
      (asl-eddie/policy :a policy)])

(:d \"Jailed ReAct loop with &lt;100ms launch and zero permission prompts\")
(eddie/execute-react-loop
  :intent (eddie/triage-intent user-speech-frame)
  :policy (policy/workspace-jail \"/workspace\" :allow-read-only [\"/tmp\"])
  :barge-in-ms 5)</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-eddie</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-eddie\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 5: asl-agent-bus -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-agent-bus\" data-stage=\"2\" data-search=\"asl-agent-bus unix socket sse mcp a2a mesh warm daemon\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><circle cx=\"12\" cy=\"12\" r=\"2\"></circle><path d=\"M16.24 7.76a6 6 0 0 1 0 8.49m-8.48-.01a6 6 0 0 1 0-8.49m11.31-2.82a10 10 0 0 1 0 14.14m-14.14 0a10 10 0 0 1 0-14.14\"></path></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-agent-bus</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">High-frequency in-memory Unix socket &amp; SSE A2A mesh bus</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-purple-500/10 text-signal border-signal/30\">Stage 2: Harness</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-purple-400\"></span>Active</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">Sub-millisecond inter-agent communication mesh with Model Context Protocol (MCP) bridge. Subagents stay warm in-memory, listening on local Unix domain sockets and Server-Sent Events (SSE) streams, exchanging compact ASL frames at &lt;0.04ms latency with zero cold-start delay.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Sub-millisecond IPC over in-memory Unix domain sockets and SSE</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Zero cold-start delay: subagents stay warm and resident in-memory</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Out-of-the-box Model Context Protocol (MCP) JSON-RPC bridge</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Replaces conversational chat bloat with typed S-expression frames</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Socket Latency</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&lt;0.04ms</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Cold Start Delay</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">0ms (Warm)</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Wire Reduction</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">-78% vs Chat</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Transports</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Unix Socket, SSE, MCP</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">asl bus serve</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">asl bus send</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(bus/publish!)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(bus/subscribe!)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">terminal / bash</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre># Launch local agent bus daemon listening on Unix domain socket
asl bus serve --socket /tmp/asl-bus.sock --port 8765

# Broadcast structured machine frame to warm subagent (&lt;0.04ms latency)
asl bus send agent-coder &quot;(? task/exec :target \&quot;core/asn\&quot;)&quot;</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-agent-bus</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-agent-bus\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 6: asl-mem -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-mem\" data-stage=\"2\" data-search=\"asl-mem hierarchical memory matrix wasm vector store cosine knn 64kb\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><path d=\"M2.97 12.92A2 2 0 0 0 2 14.63v3.24a2 2 0 0 0 .97 1.71l3 1.8a2 2 0 0 0 2.06 0L12 19v-5.5l-5-3-4.03 2.42Z\"></path><path d=\"m7 16.5-4.74-2.85\"></path><path d=\"m7 16.5 5-3\"></path><path d=\"M7 16.5v5.17\"></path><path d=\"M12 13.5V19l3.97 2.38a2 2 0 0 0 2.06 0l3-1.8a2 2 0 0 0 .97-1.71v-3.24a2 2 0 0 0-.97-1.71L17 10.5l-5 3Z\"></path><path d=\"m17 16.5-5-3\"></path><path d=\"m17 16.5 4.74-2.85\"></path><path d=\"M17 16.5v5.17\"></path><path d=\"M7.97 4.42A2 2 0 0 0 7 6.13v4.37l5 3 5-3V6.13a2 2 0 0 0-.97-1.71l-3-1.8a2 2 0 0 0-2.06 0l-3 1.8Z\"></path><path d=\"M12 8 7.26 5.15\"></path><path d=\"m12 8 4.74-2.85\"></path><path d=\"M12 13.5V8\"></path></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-mem</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">Hierarchical memory matrix &amp; Wasm vector store</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-purple-500/10 text-signal border-signal/30\">Stage 2: Harness</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-purple-400\"></span>Active</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">Zero-server in-memory vector database and cosine similarity search engine executing inside a 64KB WebAssembly page. Provides sub-0.05ms semantic vector recall, local working memory, session history, and hierarchical knowledge base recall without external database servers.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>64KB WebAssembly memory page footprint for extreme portability</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>0.038ms cosine similarity search across high-dimensional embeddings</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Hierarchical tiers: working context, session recall, persistent ledger</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Runs identically in-browser, inside edge workers, or on native CLI</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Wasm Footprint</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">64KB Page</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Search Latency</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">0.038ms (5k vectors)</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">External Servers</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">0 Required</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Algorithm</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">SIMD Cosine KNN</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(vmem/init-store)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(vmem/insert!)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(vmem/knn-search)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(vmem/persist)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">memory/recall.asl</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>(module memory/recall
  :d \"Sub-0.05ms local vector recall inside 64KB WebAssembly.\"
  :i [(asl-mem/vector :a vmem)])

(:d \"Initialize local vector store and query top-k nearest neighbors\")
(let [(store (vmem/init-store :dim 384 :metric :cosine))]
  (vmem/insert! store \"chunk-91\" query-vector)
  (vmem/knn-search store query-vector :top-k 5))</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-mem</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-mem\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 7: asl-vdom -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-vdom\" data-stage=\"3\" data-search=\"asl-vdom axtree d2snap dom downsampler tsx declarative ui react 19 vue 3\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><path d=\"M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z\"></path><circle cx=\"12\" cy=\"12\" r=\"3\"></circle></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-vdom</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">Dual perception AXTree + D2Snap DOM downsampler, TSX declarative UI dialect</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-emerald-500/10 text-emerald-400 border-emerald-500/30\">Stage 3: Visual</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-amber-400\"></span>Preview</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">Declarative S-expression Virtual DOM renderer and dual perception compaction bridge. Compresses browser DOM and CDP accessibility trees by &ge;75% for LLMs via D2Snap downsampling, and compiles declarative UI trees into React 19 TSX, Vue 3 render functions, or native Wasm DOM patches.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Dual perception downsampling eliminates invisible DOM overhead</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>&ge;75% prompt token reduction over verbose browser HTML</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Declarative UI dialect compiling directly to modern React 19 TSX</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>S-expression virtual DOM diffing with surgical patch generation</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Prompt Reduction</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&ge;75%</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Target Dialects</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">React 19 TSX, Vue 3, Wasm</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Perception Modes</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">AXTree + D2Snap</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Diffing</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Surgical Mutation Ops</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(vdom/render)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(html/div)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(perception/compact-axtree)</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">(vdom/diff)</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">ui/card.asl</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>(module ui/metrics-card
  :d \"Declarative TSX component with compact perception.\"
  :i [(asl-vdom/html :a h)
      (asl-vdom/perception :a perc)])

(:d \"Declarative UI dialect transpiled directly to React 19 TSX\")
(df render-card [(title Str) (count I64)] -> h/VNode
  (h/div :class \"rounded-2xl border border-line bg-surface p-4\"
    [(h/span :class \"font-mono text-micro text-signal\" title)
     (h/h3 :class \"text-h2 font-bold text-ink\" (string-from-int64 count))]))</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-vdom</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-vdom\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

      <!-- Package 8: asl-browser-plugin -->
      <div class=\"upm-card group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6\" data-id=\"@genseam/asl-browser-plugin\" data-stage=\"3\" data-search=\"asl-browser-plugin in-tab agent copilot wasi preview1 runner manifest v3\">
        <div class=\"space-y-4\">
          <div class=\"flex items-start justify-between gap-4\">
            <div class=\"flex items-center gap-3.5\">
              <div class=\"w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-5 h-5\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20\"></path><path d=\"M2 12h20\"></path></svg>
              </div>
              <div>
                <span class=\"font-mono text-meta font-bold text-ink\">@genseam/asl-browser-plugin</span>
                <p class=\"font-mono text-micro text-signal uppercase mt-0.5\">In-tab agent copilot with in-memory WASI preview1 runner &amp; A2A mesh framing</p>
              </div>
            </div>
            <div class=\"flex flex-col items-end gap-1.5 shrink-0\">
              <span class=\"px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border bg-emerald-500/10 text-emerald-400 border-emerald-500/30\">Stage 3: Visual</span>
              <span class=\"flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3\"><span class=\"w-1.5 h-1.5 rounded-full bg-amber-400\"></span>Preview</span>
            </div>
          </div>
          <p class=\"text-meta text-ink-2 leading-relaxed\">Cross-browser Manifest V3 extension providing autonomous in-tab execution. Houses an in-memory WASI preview1 runner inside the background service worker, live DOM tree extraction into compact ASL S-expression frames saving 78% tokens, and sub-millisecond A2A mesh communication.</p>
          <ul class=\"space-y-1.5 pt-2 border-t border-line/60\">
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>In-memory WASI preview1 execution in browser background service worker</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Live DOM compaction saving 78% prompt tokens vs raw HTML</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Zero remote DevTools/Selenium protocol latency and flakiness</span></li>
            <li class=\"flex items-start gap-2 text-meta text-ink-2\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5 text-signal mt-0.5 shrink-0\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg><span>Direct A2A mesh wire framing for swarm orchestration</span></li>
          </ul>
          <div class=\"grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2\">
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Extension Standard</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Manifest V3</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Runner Latency</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">&lt;0.05ms (WASI)</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">DOM Token Savings</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">78% Compaction</span></div>
            <div class=\"p-2 rounded-xl bg-ground border border-line text-center\"><span class=\"block font-mono text-[9px] uppercase text-ink-3 leading-tight\">Compatibility</span><span class=\"block font-mono text-micro font-semibold text-ink mt-0.5\">Chrome, Edge, Firefox, Safari</span></div>
          </div>
          <div class=\"pt-2\">
            <span class=\"font-mono text-[10px] uppercase text-ink-3 block mb-1.5\">Exported Primitives &amp; Interfaces:</span>
            <div class=\"flex flex-wrap gap-1.5\">
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">WasiPreview1Runner</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">DomExtractor.extractAslFrame</code>
              <code class=\"px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300\">A2AMeshClient</code>
            </div>
          </div>
          <div class=\"upm-code-panel hidden mt-4 pt-3 border-t border-line/60 space-y-2\">
            <div class=\"flex items-center justify-between font-mono text-micro text-ink-3\">
              <span class=\"text-signal font-semibold\">background/copilot.ts</span>
              <button type=\"button\" class=\"upm-copy-code inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors\">Copy Code</button>
            </div>
            <div class=\"p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed\"><pre>import { WasiPreview1Runner, DomExtractor } from '@genseam/asl-browser-plugin';

// Run ASL Wasm preview1 directly inside browser service worker
const runner = new WasiPreview1Runner({ wasmModule: compiledAslBytes });
const compactFrame = await DomExtractor.extractAslFrame(activeTabId);

// Stream compact S-expression frame to agent mesh bus
await runner.dispatchA2AFrame(compactFrame);</pre></div>
          </div>
        </div>
        <div class=\"pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3\">
          <div class=\"flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3\">
            <span class=\"truncate text-ink-2\"><span class=\"text-signal font-semibold\">$ </span>asl pkg add @genseam/asl-browser-plugin</span>
            <button type=\"button\" data-cmd=\"asl pkg add @genseam/asl-browser-plugin\" class=\"upm-copy-cmd ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0\">Copy</button>
          </div>
          <button type=\"button\" class=\"upm-toggle-code inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0\">Inspect Code</button>
        </div>
      </div>

    </div>
  </div>
  <script>
    (function() {
      function init() {
        var stageBtns = document.querySelectorAll('.upm-stage-btn');
        var searchInput = document.getElementById('upm-search-input');
        var cards = document.querySelectorAll('.upm-card');
        var curStage = 'all';
        var curQuery = '';

        function filter() {
          var q = curQuery.toLowerCase().trim();
          cards.forEach(function(card) {
            var st = card.getAttribute('data-stage');
            var sr = (card.getAttribute('data-search') || '') + ' ' + (card.getAttribute('data-id') || '');
            var matchStage = (curStage === 'all' || st === curStage);
            var matchQuery = (!q || sr.toLowerCase().indexOf(q) !== -1);
            if (matchStage && matchQuery) {
              card.style.display = '';
            } else {
              card.style.display = 'none';
            }
          });
        }

        stageBtns.forEach(function(btn) {
          btn.addEventListener('click', function() {
            var st = btn.getAttribute('data-stage');
            curStage = st;
            stageBtns.forEach(function(b) {
              if (b === btn) {
                b.className = 'upm-stage-btn px-3 py-1.5 rounded-xl font-mono text-micro transition-all bg-signal text-white font-semibold shadow-sm';
              } else {
                b.className = 'upm-stage-btn px-3 py-1.5 rounded-xl font-mono text-micro transition-all bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60';
              }
            });
            filter();
          });
        });

        if (searchInput) {
          searchInput.addEventListener('input', function() {
            curQuery = searchInput.value;
            filter();
          });
        }

        document.querySelectorAll('.upm-toggle-code').forEach(function(btn) {
          btn.addEventListener('click', function() {
            var card = btn.closest('.upm-card');
            if (!card) return;
            var panel = card.querySelector('.upm-code-panel');
            if (!panel) return;
            if (panel.classList.contains('hidden')) {
              panel.classList.remove('hidden');
              btn.textContent = 'Hide Code';
            } else {
              panel.classList.add('hidden');
              btn.textContent = 'Inspect Code';
            }
          });
        });

        document.querySelectorAll('.upm-copy-cmd').forEach(function(btn) {
          btn.addEventListener('click', function() {
            var cmd = btn.getAttribute('data-cmd');
            if (cmd && navigator.clipboard) {
              navigator.clipboard.writeText(cmd);
              var orig = btn.textContent;
              btn.textContent = 'Copied!';
              setTimeout(function() { btn.textContent = orig; }, 2000);
            }
          });
        });

        document.querySelectorAll('.upm-copy-code').forEach(function(btn) {
          btn.addEventListener('click', function() {
            var panel = btn.closest('.upm-code-panel');
            if (!panel) return;
            var pre = panel.querySelector('pre');
            if (pre && navigator.clipboard) {
              navigator.clipboard.writeText(pre.textContent || '');
              var orig = btn.textContent;
              btn.textContent = 'Copied!';
              setTimeout(function() { btn.textContent = orig; }, 2000);
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

(df unified-package-matrix [] -> Str
  :d "Alias for render-unified-package-matrix."
  (render-unified-package-matrix))

(df package-matrix-view [] -> Str
  :d "Alias for render-unified-package-matrix."
  (render-unified-package-matrix))
