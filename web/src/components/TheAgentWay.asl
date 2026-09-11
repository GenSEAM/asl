(module asl-web/the-agent-way
  :d "The Agent Way philosophy showcase component in pure AgentScript."
  :x [the-agent-way render-the-agent-way agent-way-view]
  :i [])

(df render-the-agent-way [] -> Str
  :d "Renders the 4 language epochs comparison and balance thesis."
  "<section id=\"agent-way\" aria-labelledby=\"agent-way-title\" class=\"relative py-28 sm:py-36 transition-colors bg-transparent\">
    <div class=\"max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10\">
      <header class=\"mb-16 sm:mb-20 max-w-3xl\">
        <span class=\"inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3\">
          <span class=\"text-signal\">01</span>
          <span class=\"w-8 h-px bg-line-strong\" aria-hidden=\"true\"></span>
          The idea
        </span>
        <h2 id=\"agent-way-title\" class=\"mt-6 text-h2 font-semibold text-ink text-balance\">
          Every language so far was designed for the hands that typed it.
        </h2>
        <p class=\"mt-4 text-lead text-ink-2 max-w-2xl text-balance\">
          That was the right constraint for thirty years. It stopped being the right one the moment most code started arriving from a model — which is a generator with no fingers, no editor and no second chance at a bracket.
        </p>
      </header>

      <ol class=\"grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 border-t border-line\">
        
        <li class=\"relative pt-8 pb-10 lg:pr-8 border-b border-line lg:border-b-0 lg:border-r last:border-r-0 lg:pl-8 first:lg:pl-0\">
          <p class=\"font-mono text-micro uppercase text-ink-3\">1990s</p>
          <h3 class=\"mt-4 text-h3 font-medium text-ink-2\">Object-oriented</h3>
          <p class=\"mt-4 text-body text-ink-2\">Structure the program the way a team can divide it.</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">Designed for</p>
          <p class=\"mt-1.5 text-body text-ink-2\">A team of typists</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">What it cost a model</p>
          <ul class=\"mt-1.5 space-y-1\">
            <li class=\"text-body text-ink-2\">Rigid hierarchies</li>
            <li class=\"text-body text-ink-2\">Mutation hazards</li>
          </ul>
        </li>

        
        <li class=\"relative pt-8 pb-10 lg:pr-8 border-b border-line lg:border-b-0 lg:border-r last:border-r-0 lg:pl-8 first:lg:pl-0\">
          <p class=\"font-mono text-micro uppercase text-ink-3\">2010s</p>
          <h3 class=\"mt-4 text-h3 font-medium text-ink-2\">Functional</h3>
          <p class=\"mt-4 text-body text-ink-2\">Make state explicit so concurrency stops being folklore.</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">Designed for</p>
          <p class=\"mt-1.5 text-body text-ink-2\">A reasoning human</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">What it cost a model</p>
          <ul class=\"mt-1.5 space-y-1\">
            <li class=\"text-body text-ink-2\">Type acrobatics</li>
            <li class=\"text-body text-ink-2\">Runtime overhead</li>
          </ul>
        </li>

        
        <li class=\"relative pt-8 pb-10 lg:pr-8 border-b border-line lg:border-b-0 lg:border-r last:border-r-0 lg:pl-8 first:lg:pl-0\">
          <p class=\"font-mono text-micro uppercase text-ink-3\">2023</p>
          <h3 class=\"mt-4 text-h3 font-medium text-ink-2\">Prompt and pray</h3>
          <p class=\"mt-4 text-body text-ink-2\">Ask a model for a language built for someone else, then fix what comes back.</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">Designed for</p>
          <p class=\"mt-1.5 text-body text-ink-2\">Nobody</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">What it cost a model</p>
          <ul class=\"mt-1.5 space-y-1\">
            <li class=\"text-body text-ink-2\">Whitespace crashes</li>
            <li class=\"text-body text-ink-2\">Repair loops</li>
            <li class=\"text-body text-ink-2\">Context exhaustion</li>
          </ul>
        </li>

        
        <li class=\"relative pt-8 pb-10 lg:pr-8 border-b border-line lg:border-b-0 lg:border-r last:border-r-0 lg:pl-8 first:lg:pl-0\">
          <span class=\"absolute -top-[3px] left-0 lg:left-8 w-8 h-1 rounded-full bg-signal\" aria-hidden=\"true\"></span>
          <p class=\"font-mono text-micro uppercase text-ink-3\">2026</p>
          <h3 class=\"mt-4 text-h3 font-semibold text-ink\">Agentic</h3>
          <p class=\"mt-4 text-body text-ink-2\">Give the generator a grammar it cannot get wrong, and check every target agrees.</p>
          <p class=\"mt-7 font-mono text-micro uppercase text-ink-3\">Designed for</p>
          <p class=\"mt-1.5 text-body text-signal font-medium\">The generator</p>
        </li>
      </ol>

      <div class=\"mt-16 sm:mt-20 grid grid-cols-1 lg:grid-cols-12 gap-10 items-start\">
        <p class=\"lg:col-span-5 text-h3 font-medium text-ink text-balance\">
          Balance is a property, not a convention.
        </p>
        <p class=\"lg:col-span-7 text-lead text-ink-2 max-w-prose\">
          An indentation-sensitive language asks a model to hold invisible state across a hundred lines. A balanced-parenthesis one asks it to close what it opened &mdash; a check the parser makes in a single left-to-right pass, and the one structural mistake a generator is least able to make silently.
        </p>
      </div>
    </div>
  </section>")

(df the-agent-way [] -> Str
  :d "Alias for render-the-agent-way."
  (render-the-agent-way))

(df agent-way-view [] -> Str
  :d "Alias for render-the-agent-way."
  (render-the-agent-way))
