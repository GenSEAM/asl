(module asl-web/home-view
  :d "Declarative Home View in pure AgentScript"
  :x [describe-home-view render-home-view]
  :i [(core/strings :a s)
      (components/Hero :a hero)
      (components/KeyCapabilities :a cap)
      (components/TheAgentWay :a way)
      (components/AgentWireProtocol :a wire)
      (components/HarnessToolkit :a harness)
      (components/UnifiedPackageMatrix :a matrix)
      (components/EngineeringBlog :a blog)])

(df describe-home-view [] -> Str
  :d "Returns structured description of the home landing view composition"
  "(view :id \"home\" :components [\"hero\" \"capabilities\" \"agent-way\" \"wire-protocol\" \"harness\" \"matrix\" \"blog\"])")

(df render-home-view [] -> Str
  :d "Renders composite home page markup"
  (s/concat
    "<main class=\"flex-1\">"
    (s/concat
      (hero/render-hero)
      (s/concat
        (cap/capabilities-view)
        (s/concat
          (way/agent-way-view)
          (s/concat
            (wire/render-wire-protocol)
            (s/concat
              (harness/harness-view)
              (s/concat
                (matrix/render-package-matrix)
                (s/concat
                  (blog/render-engineering-blog)
                  "</main>")))))))))
