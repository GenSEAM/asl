(module asl-web/home-view
  :d "Declarative Home View in pure AgentScript"
  :x [describe-home-view render-home-view]
  :i [(core/strings :a s)])

(df describe-home-view [] -> Str
  :d "Returns structured description of the home landing view composition"
  "(view :id \"home\" :components [\"hero\" \"ecosystem\" \"capabilities\" \"agent-way\" \"wire-protocol\" \"harness\" \"blog\"])")

(df render-home-view [] -> Str
  :d "Renders composite home page markup"
  (s/concat
    "<main class=\"flex-1\">"
    (s/concat
      "<div id=\"hero-section\"></div>"
      (s/concat
        "<div id=\"capabilities-section\"></div>"
        (s/concat
          "<div id=\"agent-way-section\"></div>"
          (s/concat
            "<div id=\"matrix-section\"></div>"
            "<div id=\"blog-section\"></div></main>"))))))
