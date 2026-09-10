(module asl-web/playground/catalog
  :d "Playground presets catalog metadata in pure AgentScript."
  :x [render-playground-catalog playground-catalog]
  :i [])

(df render-playground-catalog [] -> Str
  :d "Renders catalog manifest"
  "<div class=\"p-4 rounded-xl border border-line bg-surface text-xs font-mono\">Playground Manifest: 20 Presets (5 Toys, 5 Websites, 10 SVGs)</div>")

(df playground-catalog [] -> Str
  :d "Catalog component alias"
  (render-playground-catalog))
