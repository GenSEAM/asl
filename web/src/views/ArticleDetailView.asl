(module asl-web/article-detail-view
  :d "Technical Article Reader and Architecture Deep-Dive View in pure AgentScript."
  :x [article-detail-view render-article-detail-view describe-article-detail-view]
  :i [])

(df describe-article-detail-view [] -> Str
  :d "Returns structural metadata for the Article Detail view."
  "(view :id \"article-detail\" :components [\"navigation\" \"header\" \"body\" \"citation\" \"related\"])")

(df render-article-detail-view [] -> Str
  :d "Renders article detail view container."
  "<main class=\"flex-1 max-w-shell mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full\" id=\"bv-article-view\"><div id=\"asl-article-content\" class=\"article-body text-ink max-w-prose mx-auto\"></div></main>")

(df article-detail-view [] -> Str
  :d "Alias for render-article-detail-view."
  (render-article-detail-view))
