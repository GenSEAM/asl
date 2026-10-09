(module aslWeb/articleDetailView :x [articleDetailView renderArticleDetailView describeArticleDetailView] :i [])

fn describeArticleDetailView -> Str
  "(view :id \"article-detail\" :components [\"navigation\" \"header\" \"body\" \"citation\" \"related\"])"

fn renderArticleDetailView -> Str
  "<main class=\"flex-1 max-w-shell mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full\" id=\"bv-article-view\"><div id=\"asl-article-content\" class=\"article-body text-ink max-w-prose mx-auto\"></div></main>"

fn articleDetailView -> Str
  (renderArticleDetailView)
