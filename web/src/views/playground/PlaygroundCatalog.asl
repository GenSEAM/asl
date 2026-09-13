(module aslWeb/playground/catalog
  :d "Playground presets catalog metadata in pure AgentScript."
  :x [renderPlaygroundCatalog playgroundCatalog]
  :i [])

(df renderPlaygroundCatalog [] -> Str
  :d "Renders catalog manifest"
  "<div class=\"p-4 rounded-xl border border-line bg-surface text-xs font-mono\">Playground Manifest: 20 Presets (5 Toys, 5 Websites, 10 SVGs)</div>")

(df playgroundCatalog [] -> Str
  :d "Catalog component alias"
  (renderPlaygroundCatalog))
