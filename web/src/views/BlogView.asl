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
      in-memory WebAssembly sandboxing, and inter-agent wire protocols. Prioritized from foundational
      language geometry and wire protocols up through autonomous harnesses and the global ecosystem.
    </p>

    <!-- View Mode Tabs -->
    <div class=\"flex flex-wrap items-center gap-2 mb-8 p-1.5 bg-surface-2/60 border border-line rounded-2xl w-fit\" id=\"bv-mode-tabs\">
      <button type=\"button\" data-mode=\"all\" class=\"bv-mode-btn flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-mono font-medium transition-all bg-signal text-ground font-semibold shadow-sm\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\"><path d=\"M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z\"></path><path d=\"M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z\"></path></svg>
        <span>All Published (19)</span>
      </button>
      <button type=\"button\" data-mode=\"flagship\" class=\"bv-mode-btn flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-mono font-medium transition-all text-ink-2 hover:text-ink\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\"><path d=\"m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z\"></path></svg>
        <span>Flagship Deep Dives (8)</span>
      </button>
    </div>

    <!-- Filter and Search Bar -->
    <div class=\"flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4 mb-8 pb-6 border-b border-line\">
      <!-- Category Pills -->
      <div class=\"flex flex-wrap items-center gap-1.5\" id=\"bv-cat-pills\">
        <button type=\"button\" data-cat=\"All\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-signal text-ground font-semibold border-signal shadow-sm\">
          All <span class=\"opacity-60 text-[10px]\">(19)</span>
        </button>
        <button type=\"button\" data-cat=\"Language\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Language &amp; Grammar <span class=\"opacity-60 text-[10px]\">(5)</span>
        </button>
        <button type=\"button\" data-cat=\"Token\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Token Economics <span class=\"opacity-60 text-[10px]\">(3)</span>
        </button>
        <button type=\"button\" data-cat=\"Harness\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Harness &amp; Systems <span class=\"opacity-60 text-[10px]\">(6)</span>
        </button>
        <button type=\"button\" data-cat=\"Ecosystem\" class=\"bv-cat-btn px-3 py-1 rounded-full text-xs font-mono transition-colors border bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2\">
          Ecosystem &amp; Adapters <span class=\"opacity-60 text-[10px]\">(5)</span>
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
      <!-- Post 1: why-llms-struggle-with-python-and-rust -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"why-llms-struggle-with-python-and-rust\" data-importance=\"flagship\" data-cat=\"Language Theory &amp; Compilers\" data-search=\"how to fix agentic coding: why autonomous llms break on human languages (and what replaces them) why indentation and borrow-checked syntax trap coding agents in 38% syntax repair loops, and what deterministic single-pass s-expressions solve. agentic coding grammars llm autoregression syntax repair loop s-expressions pure asl language theory &amp; compilers genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Language Theory &amp; Compilers</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>6 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">How to Fix Agentic Coding: Why Autonomous LLMs Break on Human Languages (and What Replaces Them)</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why indentation and borrow-checked syntax trap coding agents in 38% syntax repair loops, and what deterministic single-pass S-expressions solve.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-08 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 2: token-economy-and-structural-compression -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"token-economy-and-structural-compression\" data-importance=\"flagship\" data-cat=\"Token Economy &amp; Serialization\" data-search=\"stop burning money on json context: how structural compaction cuts llm bills by 65% why json repeats keys on every row, how tabular asn hoists schemas into vector headers, and how structural compaction slashes llm context bills by 64.7% without changing model weights. byte-pair encoding structural compaction tabular serialization asn token economy token economy &amp; serialization genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Token Economy &amp; Serialization</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Stop Burning Money on JSON Context: How Structural Compaction Cuts LLM Bills by 65%</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why JSON repeats keys on every row, how tabular ASN hoists schemas into vector headers, and how structural compaction slashes LLM context bills by 64.7% without changing model weights.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 3: from-vibe-code-to-wasm-in-0-04ms -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"from-vibe-code-to-wasm-in-0-04ms\" data-importance=\"flagship\" data-cat=\"Runtime &amp; Execution\" data-search=\"killing docker spin-up latency: how we run agent test sandboxes in 0.038ms why spinning up docker containers and microvms (1.2s–12s) cripples agent action loops, and how compiling agentscript directly to in-memory webassembly preview1 linear memory executes in 0.038ms. webassembly wasi microvms sub-millisecond sandboxing linear memory runtime &amp; execution genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Runtime &amp; Execution</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>5 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Killing Docker Spin-Up Latency: How We Run Agent Test Sandboxes in 0.038ms</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why spinning up Docker containers and microVMs (1.2s–12s) cripples agent action loops, and how compiling AgentScript directly to in-memory WebAssembly preview1 linear memory executes in 0.038ms.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 4: the-token-tax-and-interface-compression -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-token-tax-and-interface-compression\" data-importance=\"high\" data-cat=\"Context Architecture\" data-search=\"the 78% context tax: how ast interface extraction stops agent working memory rot shuttling whole files between agents burns 78% of context on internal implementation details. hoisting public interfaces into compact asn asts preserves attention headroom over 50+ turns. context rot token compression ast extraction multi-agent working memory context architecture genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Context Architecture</span>
              <span class=\"px-1.5 py-0.5 rounded border border-emerald-400/40 bg-emerald-400/10 text-emerald-300 font-semibold text-[10px]\">High</span>
            </div>
            <span>5 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The 78% Context Tax: How AST Interface Extraction Stops Agent Working Memory Rot</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Shuttling whole files between agents burns 78% of context on internal implementation details. Hoisting public interfaces into compact ASN ASTs preserves attention headroom over 50+ turns.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 5: the-token-density-fallacy-and-machine-understandability -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-token-density-fallacy-and-machine-understandability\" data-importance=\"flagship\" data-cat=\"Architecture &amp; Language Theory\" data-search=\"why disemvoweling breaks bpe: how naive token optimization destroys agent intelligence why naive identifier compression like ctermtxt breaks bpe subtokenization, how synonym collisions cost thousands of repair tokens, and the findings of our 2-round adversarial consultation with claude fable 5. token economics bpe subtokens machine understandability claude fable agentscript gate 6 architecture &amp; language theory genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Architecture &amp; Language Theory</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>9 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Why Disemvoweling Breaks BPE: How Naive Token Optimization Destroys Agent Intelligence</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why naive identifier compression like ctermtxt breaks BPE subtokenization, how synonym collisions cost thousands of repair tokens, and the findings of our 2-round adversarial consultation with Claude Fable 5.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-07 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 6: inter-agent-protocols-and-wire-frames -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"inter-agent-protocols-and-wire-frames\" data-importance=\"core\" data-cat=\"Protocols &amp; Mesh\" data-search=\"inter-agent protocol (agp): eradicating natural language chatter with typed s-expression frames beyond conversational mesh chaos: replacing ambiguous natural language chatter with typed s-expression frames, seambus (simba) mesh, and sub-millisecond ipc. seambus simba agp wire protocol typed frames conversational mesh protocols &amp; mesh genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Protocols &amp; Mesh</span>
              <span class=\"px-1.5 py-0.5 rounded border border-blue-400/40 bg-blue-400/10 text-blue-300 font-semibold text-[10px]\">Core</span>
            </div>
            <span>7 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Inter-Agent Protocol (AgP): Eradicating Natural Language Chatter with Typed S-Expression Frames</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Beyond conversational mesh chaos: replacing ambiguous natural language chatter with typed S-expression frames, SeamBus (Simba) mesh, and sub-millisecond IPC.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-06 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 7: the-agent-operational-circle -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-agent-operational-circle\" data-importance=\"flagship\" data-cat=\"Autonomous Systems &amp; Grammar\" data-search=\"the single grammar doctrine: why multi-agent systems collapse without homoiconic s-expressions why autonomous agents collapse when juggling json, yaml, svg xml, and bash strings, and how unifying data, visuals, and execution into a single s-expression geometry eliminates 60% of syntax token overhead. agent operational circle asn agentscript shell transpiler vector graphics homoiconicity autonomous systems &amp; grammar genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Autonomous Systems &amp; Grammar</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>7 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The Single Grammar Doctrine: Why Multi-Agent Systems Collapse Without Homoiconic S-Expressions</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why autonomous agents collapse when juggling JSON, YAML, SVG XML, and Bash strings, and how unifying data, visuals, and execution into a single S-expression geometry eliminates 60% of syntax token overhead.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-06 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 8: agent-script-the-optimal-agent-language -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"agent-script-the-optimal-agent-language\" data-importance=\"high\" data-cat=\"Language Theory\" data-search=\"the mathematical optimum: why s-expressions and algebraic types beat human syntax for llms why s-expressions, homoiconic asts, exhaustive pattern matching, and explicit effect boundaries are mathematically optimal for autoregressive llms. homoiconicity algebraic types exhaustive matching deterministic ast mathematical optimum language theory genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Language Theory</span>
              <span class=\"px-1.5 py-0.5 rounded border border-emerald-400/40 bg-emerald-400/10 text-emerald-300 font-semibold text-[10px]\">High</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The Mathematical Optimum: Why S-Expressions and Algebraic Types Beat Human Syntax for LLMs</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why S-expressions, homoiconic ASTs, exhaustive pattern matching, and explicit effect boundaries are mathematically optimal for autoregressive LLMs.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-06 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 9: the-deterministic-agent-os -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-deterministic-agent-os\" data-importance=\"flagship\" data-cat=\"Architecture &amp; Operating Systems\" data-search=\"stop making llms do os work: why autonomous coding requires an alu / kernel split why treating an llm as scheduler, filesystem, and interpreter causes cognitive collapse, and how separating the stochastic semantic alu from a deterministic operating system achieves 92% benchmark solve rates. agent os prompt vmm deterministic execution eddie swe-bench alu split architecture &amp; operating systems genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Architecture &amp; Operating Systems</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Stop Making LLMs Do OS Work: Why Autonomous Coding Requires an ALU / Kernel Split</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why treating an LLM as scheduler, filesystem, and interpreter causes cognitive collapse, and how separating the stochastic semantic ALU from a deterministic operating system achieves 92% benchmark solve rates.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-05 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 10: epistemic-grounding-and-anti-hallucination-firewalls -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"epistemic-grounding-and-anti-hallucination-firewalls\" data-importance=\"core\" data-cat=\"Safety &amp; Grounding\" data-search=\"stop your agent from faking green tests: ast mutation gates and anti-hallucination firewalls halting execution-simulation hallucinations (esh) at the ast compiler boundary with lexical closure audits, deterministic quote verification, and hardware-enforced path jailing. epistemic grounding anti-hallucination closure audit zero-leak jailing esh safety &amp; grounding genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Safety &amp; Grounding</span>
              <span class=\"px-1.5 py-0.5 rounded border border-blue-400/40 bg-blue-400/10 text-blue-300 font-semibold text-[10px]\">Core</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Stop Your Agent from Faking Green Tests: AST Mutation Gates and Anti-Hallucination Firewalls</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Halting Execution-Simulation Hallucinations (ESH) at the AST compiler boundary with lexical closure audits, deterministic quote verification, and hardware-enforced path jailing.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-05 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 11: the-agentic-toolchain-and-native-action-loops -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-agentic-toolchain-and-native-action-loops\" data-importance=\"flagship\" data-cat=\"Tools &amp; Compiler Architecture\" data-search=\"why bash wrappers fail coding agents: persistent action loops and 7 in-memory verification gates why stateless bash wrappers cause interactive terminal deadlocks, and how persistent execution sessions, 7 in-memory verification gates, and 100% test coverage create a deterministic toolchain for ai code generation. agent toolchain action-observation pure asl 100% coverage zero-foreign code verification gates tools &amp; compiler architecture genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Tools &amp; Compiler Architecture</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Why Bash Wrappers Fail Coding Agents: Persistent Action Loops and 7 In-Memory Verification Gates</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why stateless bash wrappers cause interactive terminal deadlocks, and how persistent execution sessions, 7 in-memory verification gates, and 100% test coverage create a deterministic toolchain for AI code generation.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-05 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 12: kill-80-percent-agent-code-bloat -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"kill-80-percent-agent-code-bloat\" data-importance=\"flagship\" data-cat=\"Architecture &amp; Simplicity\" data-search=\"kill 80% of agent framework bloat: why radical simplicity outperforms 10,000-line orchestrators why multi-megabyte agent frameworks collapse after turn 4, and how the ladder of restraint and pure agentscript s-expressions cut 80% of agent code bloat. architecture radical simplicity agentscript autonomous agents zero-foreign code architecture &amp; simplicity genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Architecture &amp; Simplicity</span>
              <span class=\"px-1.5 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]\">★ Flagship</span>
            </div>
            <span>5 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Kill 80% of Agent Framework Bloat: Why Radical Simplicity Outperforms 10,000-Line Orchestrators</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why multi-megabyte agent frameworks collapse after turn 4, and how the Ladder of Restraint and pure AgentScript S-expressions cut 80% of agent code bloat.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-04 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 13: multi-dimensional-observability-for-autonomous-systems -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"multi-dimensional-observability-for-autonomous-systems\" data-importance=\"technical\" data-cat=\"Observability &amp; Telemetry\" data-search=\"debugging autonomous swarms: time-travel execution replay without reading 50,000-token logs how to govern autonomous swarms without reading raw logs: multi-dimensional ast topologies, real-time cycle guards, and deterministic s-expression execution replay. multi-dimensional observability ast topology token telemetry time travel debugging observability &amp; telemetry genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Observability &amp; Telemetry</span>
              <span class=\"px-1.5 py-0.5 rounded border border-purple-400/40 bg-purple-400/10 text-purple-300 font-semibold text-[10px]\">Technical</span>
            </div>
            <span>7 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Debugging Autonomous Swarms: Time-Travel Execution Replay Without Reading 50,000-Token Logs</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">How to govern autonomous swarms without reading raw logs: multi-dimensional AST topologies, real-time cycle guards, and deterministic S-expression execution replay.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-04 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 14: the-agent-native-developer-cockpit -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"the-agent-native-developer-cockpit\" data-importance=\"technical\" data-cat=\"Developer Tooling\" data-search=\"the sub-0.05ms language server: building a developer cockpit for synthetic intelligences the complete agent-native developer cockpit: sub-0.05ms lsp, ast structural clone linters, autonomous auto-fixers, and live visual observability. language server protocol ast auto-fixer observability developer cockpit developer tooling genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Developer Tooling</span>
              <span class=\"px-1.5 py-0.5 rounded border border-purple-400/40 bg-purple-400/10 text-purple-300 font-semibold text-[10px]\">Technical</span>
            </div>
            <span>9 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The Sub-0.05ms Language Server: Building a Developer Cockpit for Synthetic Intelligences</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">The complete agent-native developer cockpit: sub-0.05ms LSP, AST structural clone linters, autonomous auto-fixers, and live visual observability.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-04 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 15: git-native-agent-memory-and-vector-recall -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"git-native-agent-memory-and-vector-recall\" data-importance=\"high\" data-cat=\"Memory &amp; Vector Systems\" data-search=\"killing the $4,000/month vector db bill: sub-millisecond vector recall in git-native memory sub-0.05ms in-memory vector recall and git-native memory matrices: eliminating 500x cloud vector db latency and ensuring agent episodic state never drifts from repository commits. agent memory vector recall git-native in-memory wasm zero-network memory &amp; vector systems genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Memory &amp; Vector Systems</span>
              <span class=\"px-1.5 py-0.5 rounded border border-emerald-400/40 bg-emerald-400/10 text-emerald-300 font-semibold text-[10px]\">High</span>
            </div>
            <span>7 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Killing the $4,000/Month Vector DB Bill: Sub-Millisecond Vector Recall in Git-Native Memory</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Sub-0.05ms in-memory vector recall and Git-native memory matrices: eliminating 500x cloud vector DB latency and ensuring agent episodic state never drifts from repository commits.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-03 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 16: cross-dialect-sql-without-hallucinations -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"cross-dialect-sql-without-hallucinations\" data-importance=\"core\" data-cat=\"Relational Data &amp; SQL\" data-search=\"zero-injection sql by construction: compiling relational s-expressions to postgres, sqlite &amp; clickhouse why agents writing raw sql fail 28% of the time, and how homoiconic relational s-expressions lower deterministically to postgres, sqlite, mysql, and clickhouse without injection risk. cross-dialect sql relational algebra sql injection eradication multi-engine relational data &amp; sql genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Relational Data &amp; SQL</span>
              <span class=\"px-1.5 py-0.5 rounded border border-blue-400/40 bg-blue-400/10 text-blue-300 font-semibold text-[10px]\">Core</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Zero-Injection SQL by Construction: Compiling Relational S-Expressions to Postgres, SQLite &amp; ClickHouse</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why agents writing raw SQL fail 28% of the time, and how homoiconic relational S-expressions lower deterministically to Postgres, SQLite, MySQL, and ClickHouse without injection risk.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-03 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 17: zero-server-in-browser-agent-runtimes -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"zero-server-in-browser-agent-runtimes\" data-importance=\"core\" data-cat=\"Browser Technologies\" data-search=\"the zero-server ide: running full autonomous agent sandboxes inside a chrome tab zero-server development inside browser tabs: booting webassembly sandboxes in 8ms, executing tests in 0.038ms via wasi and opfs, with tiered local slms. in-browser dev webassembly opfs tiered local slms offline-first browser technologies genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Browser Technologies</span>
              <span class=\"px-1.5 py-0.5 rounded border border-blue-400/40 bg-blue-400/10 text-blue-300 font-semibold text-[10px]\">Core</span>
            </div>
            <span>7 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">The Zero-Server IDE: Running Full Autonomous Agent Sandboxes Inside a Chrome Tab</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Zero-server development inside browser tabs: booting WebAssembly sandboxes in 8ms, executing tests in 0.038ms via WASI and OPFS, with tiered local SLMs.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-02 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 18: why-llms-break-on-svg-xml -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"why-llms-break-on-svg-xml\" data-importance=\"high\" data-cat=\"Vector Graphics &amp; Tokenomics\" data-search=\"why llms choke on svg xml: slashing 50.7% of vector graphic tokens with native s-expressions why autoregressive llms blow through token context on raw svg markup, and how native single-token asn vector primitives cut token usage by 50.7% with zero xml delimiter hallucinations. svg asn token compaction gemma 31b vector graphics agent tooling vector graphics &amp; tokenomics genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Vector Graphics &amp; Tokenomics</span>
              <span class=\"px-1.5 py-0.5 rounded border border-emerald-400/40 bg-emerald-400/10 text-emerald-300 font-semibold text-[10px]\">High</span>
            </div>
            <span>6 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">Why LLMs Choke on SVG XML: Slashing 50.7% of Vector Graphic Tokens with Native S-Expressions</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Why autoregressive LLMs blow through token context on raw SVG markup, and how native single-token ASN vector primitives cut token usage by 50.7% with zero XML delimiter hallucinations.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-02 • GenSEAM</span>
          <span class=\"text-signal font-semibold group-hover:translate-x-0.5 transition-transform\">&rarr;</span>
        </div>
      </article>

      <!-- Post 19: universal-cross-platform-glue-without-drift -->
      <article class=\"bv-post-card p-6 sm:p-7 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2\" data-slug=\"universal-cross-platform-glue-without-drift\" data-importance=\"technical\" data-cat=\"Cross-Platform Runtimes\" data-search=\"one source across rust, typescript, python &amp; wasm: eradicating multi-language glue drift eliminating multi-language glue code and semantic drift: compiling pure agentscript deterministically across webassembly, rust, go, typescript, and python. differential verification multi-backend cross-platform glue polyglot parity cross-platform runtimes genseam\">
        <div>
          <div class=\"flex items-center justify-between text-micro font-mono text-ink-3 mb-3\">
            <div class=\"flex items-center gap-1.5 flex-wrap\">
              <span class=\"px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium\">Cross-Platform Runtimes</span>
              <span class=\"px-1.5 py-0.5 rounded border border-purple-400/40 bg-purple-400/10 text-purple-300 font-semibold text-[10px]\">Technical</span>
            </div>
            <span>8 min read</span>
          </div>
          <h3 class=\"text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2\">One Source Across Rust, TypeScript, Python &amp; Wasm: Eradicating Multi-Language Glue Drift</h3>
          <p class=\"text-meta text-ink-2 line-clamp-3 mb-4\">Eliminating multi-language glue code and semantic drift: compiling pure AgentScript deterministically across WebAssembly, Rust, Go, TypeScript, and Python.</p>
        </div>
        <div class=\"flex items-center justify-between pt-4 border-t border-line/60 text-micro font-mono text-ink-3\">
          <span>2026-09-01 • GenSEAM</span>
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
