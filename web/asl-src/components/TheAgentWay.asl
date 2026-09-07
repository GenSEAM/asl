(module asl-web/the-agent-way
  :d "The Agent Way philosophy showcase component in pure AgentScript."
  :x [agent-way-view]
  :i [])

(df agent-way-view [] -> Str
  :d "Renders comparative code paradigm breakdown."
  "(section (:class \"py-16 px-6 max-w-5xl mx-auto bg-surface/30 rounded-3xl border border-line my-12\")
    (h2 (:class \"text-3xl font-bold text-ink mb-6 text-center\") \"The Agent Way\")
    (p (:class \"text-ink-muted text-center max-w-2xl mx-auto mb-8\")
      \"Languages built for humans waste 70% of model tokens on syntax boilerplate. AgentScript is designed from the ground up for LLMs.\"))")
