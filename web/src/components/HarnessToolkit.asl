(module asl-web/harness-toolkit
  :d "Agent harness toolkit interactive component in pure AgentScript."
  :x [harness-view]
  :i [])

(df harness-view [] -> Str
  :d "Renders multi-adapter harness controls."
  "(div (:class \"p-8 rounded-3xl bg-surface border border-line shadow-xl\")
    (h3 (:class \"text-2xl font-bold text-ink mb-4\") \"Universal Agent Harness\")
    (p (:class \"text-sm text-ink-muted mb-6\") \"Direct capability execution, hallucination normalizer, and zero-round-trip local tool execution.\"))")
