(module asl-web/home-view
  :d "Home landing page view composed entirely in pure AgentScript."
  :x [home-view render-home-view describe-home-view]
  :i [(asl-text/string :a s)
      asl-web/hero
      asl-web/ecosystem
      asl-web/key-capabilities
      asl-web/the-agent-way
      asl-web/agent-wire-protocol
      asl-web/harness-toolkit
      asl-web/module-graph-visualizer
      asl-web/engineering-blog
      asl-web/in-browser-agent])

(df describe-home-view [] -> Str
  :d "Returns structural metadata for the Home view."
  "(view :id \"home\" :components [\"hero\" \"ecosystem\" \"capabilities\" \"agent-way\" \"wire-protocol\" \"harness\" \"module-graph\" \"blog\" \"in-browser-agent\"])")

(df render-home-view [] -> Str
  :d "Renders the full showcase home landing page."
  (s/concat
    "<main class=\"flex-1\">"
    (s/concat (hero)
    (s/concat (ecosystem)
    (s/concat (key-capabilities)
    (s/concat (the-agent-way)
    (s/concat (agent-wire-protocol)
    (s/concat (harness-toolkit)
    (s/concat (module-graph-visualizer)
    (s/concat (engineering-blog)
    (s/concat (in-browser-agent)
    "</main>")))))))))))

(df home-view [] -> Str
  :d "Alias for render-home-view."
  (render-home-view))
