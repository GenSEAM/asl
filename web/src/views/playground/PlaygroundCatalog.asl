(module aslWeb/playground/catalog :x [renderPlaygroundCatalog playgroundCatalog] :i [])

fn renderPlaygroundCatalog -> Str
  "<div class=\"p-4 rounded-xl border border-line bg-surface text-xs font-mono\">Playground Manifest: 20 Presets (5 Toys, 5 Websites, 10 SVGs)</div>"

fn playgroundCatalog -> Str
  (renderPlaygroundCatalog)
