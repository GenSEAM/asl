(module asl-web/graph-header
  :d "Declarative Graph Header Component in ASL"
  :x [render-graph-header]
  :i [(core/strings :a s)])

(df render-graph-header [(title Str) (subtitle Str)] -> Str
  :d "Renders header markup for graph reactor"
  (s/concat
    (s/concat "<div class=\"text-center max-w-3xl mx-auto mb-8\"><h1 class=\"text-3xl sm:text-5xl font-extrabold text-ink tracking-tight mb-4\">" title)
    (s/concat "</h1><p class=\"text-sm sm:text-base text-ink-muted leading-relaxed\">" (s/concat subtitle "</p></div>"))))
