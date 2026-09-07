(module asl-web/key-capabilities
  :d "Declarative key capabilities showcase component in pure AgentScript."
  :x [capabilities-view]
  :i [])

(df capabilities-view [] -> Str
  :d "Renders grid of 4 core architectural pillars: Compaction, Sandboxing, Speed, and Verification."
  "(section (:class \"py-16 px-6 max-w-6xl mx-auto\")
    (h2 (:class \"text-3xl font-bold text-ink text-center mb-12\") \"Architectural Invariants\")
    (div (:class \"grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6\")
      (div (:class \"p-6 rounded-2xl bg-surface border border-line\")
        (h3 (:class \"text-lg font-semibold text-signal mb-2\") \"64.7% Compaction\")
        (p (:class \"text-sm text-ink-muted\") \"Dense ASN S-expressions deliver maximum context window economy over JSON Schema.\"))
      (div (:class \"p-6 rounded-2xl bg-surface border border-line\")
        (h3 (:class \"text-lg font-semibold text-signal mb-2\") \"<0.04ms Launch\")
        (p (:class \"text-sm text-ink-muted\") \"Zero-cold-start WebAssembly and AOT ANSI C compilation.\"))
      (div (:class \"p-6 rounded-2xl bg-surface border border-line\")
        (h3 (:class \"text-lg font-semibold text-signal mb-2\") \"Zero-Prompt Sandbox\")
        (p (:class \"text-sm text-ink-muted\") \"Capability-based security with fine-grained path controls and zero permission spam.\"))
      (div (:class \"p-6 rounded-2xl bg-surface border border-line\")
        (h3 (:class \"text-lg font-semibold text-signal mb-2\") \"100% Pure Self-Hosted\")
        (p (:class \"text-sm text-ink-muted\") \"Compiler, parser, checker, and gates implemented natively in AgentScript.\"))))")
