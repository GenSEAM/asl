(module asl-web/agent-observability-studio
  :d "Agent observability studio component in pure AgentScript."
  :x [agent-observability-studio render-agent-observability-studio]
  :i [])

(df render-agent-observability-studio [] -> Str
  :d "Renders the 4-layer agent observability architecture section."
  "<section id=\"observability\" aria-labelledby=\"observability-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      <header class=\"mb-16 sm:mb-20 max-w-3xl\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">04</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          Observability
        </span>
        <h2 id=\"observability-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          Nobody reads fifty thousand lines a day.
        </h2>
        <p class=\"mt-4 text-body-lg text-ink-2 text-balance leading-relaxed\">
          Review does not scale by reading faster. It scales by moving up: four layers, each one answering a different question, each one able to be checked without opening the one below it.
        </p>
      </header>

      <ol class=\"border-t border-line\">
        <li class=\"grid grid-cols-1 md:grid-cols-[4rem_12rem_1fr] gap-x-8 gap-y-3 py-8 border-b border-line\">
          <span class=\"font-mono text-micro uppercase text-signal\">01</span>
          <span>
            <span class=\"block text-h3 font-medium text-ink\">Strategic</span>
            <span class=\"block mt-1.5 font-mono text-micro uppercase text-ink-3\">.asl/constitution.md</span>
          </span>
          <p class=\"text-body text-ink-2 max-w-prose\">The goals, the guardrails and the architectural boundaries a swarm is not allowed to cross. Written by a person, versioned with the code.</p>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[4rem_12rem_1fr] gap-x-8 gap-y-3 py-8 border-b border-line\">
          <span class=\"font-mono text-micro uppercase text-signal\">02</span>
          <span>
            <span class=\"block text-h3 font-medium text-ink\">Tactical</span>
            <span class=\"block mt-1.5 font-mono text-micro uppercase text-ink-3\">In-memory socket bus</span>
          </span>
          <p class=\"text-body text-ink-2 max-w-prose\">How work was decomposed and which specialist took which part. The layer where drift becomes visible before it becomes a diff.</p>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[4rem_12rem_1fr] gap-x-8 gap-y-3 py-8 border-b border-line\">
          <span class=\"font-mono text-micro uppercase text-signal\">03</span>
          <span>
            <span class=\"block text-h3 font-medium text-ink\">Operational</span>
            <span class=\"block mt-1.5 font-mono text-micro uppercase text-ink-3\">.asl/mem/</span>
          </span>
          <p class=\"text-body text-ink-2 max-w-prose\">Decision records and requirements as first-class versioned files, so branching a repository branches what the agent believes about it.</p>
        </li>
        <li class=\"grid grid-cols-1 md:grid-cols-[4rem_12rem_1fr] gap-x-8 gap-y-3 py-8 border-b border-line\">
          <span class=\"font-mono text-micro uppercase text-signal\">04</span>
          <span>
            <span class=\"block text-h3 font-medium text-ink\">Physical</span>
            <span class=\"block mt-1.5 font-mono text-micro uppercase text-ink-3\">WASI isolate</span>
          </span>
          <p class=\"text-body text-ink-2 max-w-prose\">What actually executed, inside a sandbox with no host disk. The only layer that can contradict the other three.</p>
        </li>
      </ol>

      <p class=\"mt-10 font-mono text-meta text-ink-3\">
        <span class=\"text-signal\">$ </span>asl inspect
      </p>
    </div>
  </section>")

(df agent-observability-studio [] -> Str
  :d "Alias for render-agent-observability-studio."
  (render-agent-observability-studio))
