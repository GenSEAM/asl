(module asl-web/primitives
  :d "Declarative UI Primitives for the AgentScript Web Design System"
  :x [render-section render-eyebrow render-section-header]
  :i [(core/strings :a s)])

(df render-eyebrow [(index Str) (label Str)] -> Str
  :d "Renders numbered eyebrow ornament"
  (s/concat "<span class=\"inline-flex items-center gap-3 font-mono text-xs uppercase text-ink-2\"><span class=\"text-signal font-semibold\">" (s/concat index (s/concat "</span><span class=\"w-8 h-px bg-line\"></span>" (s/concat label "</span>")))))

(df render-section-header [(index Str) (eyebrow Str) (title Str) (lead Str)] -> Str
  :d "Renders unified section header"
  (s/concat
    "<header class=\"max-w-3xl mb-12\">"
    (s/concat
      (render-eyebrow index eyebrow)
      (s/concat
        "<h2 class=\"text-3xl font-bold text-ink mt-4 mb-3\">"
        (s/concat
          title
          (s/concat
            "</h2><p class=\"text-ink-2 text-lg\">"
            (s/concat lead "</p></header>")))))))

(df render-section [(id Str) (content Str)] -> Str
  :d "Wraps content in standardized section container"
  (s/concat "<section id=\"" (s/concat id (s/concat "\" class=\"py-20 max-w-6xl mx-auto px-4\">" (s/concat content "</section>")))))
