(module aslWeb/homeView
  :d "Home landing page view composed entirely in pure AgentScript."
  :x [homeView renderHomeView describeHomeView]
  :i [(asl-text/string :a s)
      aslWeb/hero
      aslWeb/ecosystem
      aslWeb/keyCapabilities
      aslWeb/theAgentWay
      aslWeb/agentWireProtocol
      aslWeb/harnessToolkit
      aslWeb/moduleGraphVisualizer
      aslWeb/engineeringBlog
      aslWeb/inBrowserAgent])

(df describeHomeView [] -> Str
  :d "Returns structural metadata for the Home view."
  "(view :id \"home\" :components [\"hero\" \"ecosystem\" \"capabilities\" \"agent-way\" \"wire-protocol\" \"harness\" \"module-graph\" \"blog\" \"in-browser-agent\"])")

(df renderHomeView [] -> Str
  :d "Renders the full showcase home landing page."
  (s/concat
    "<main id=\"main-content\" class=\"flex-1 max-w-shell mx-auto w-full\">"
    (s/concat (hero)
    (s/concat (ecosystem)
    (s/concat (keyCapabilities)
    (s/concat (theAgentWay)
    (s/concat (agentWireProtocol)
    (s/concat (harnessToolkit)
    (s/concat (moduleGraphVisualizer)
    (s/concat (engineeringBlog)
    (s/concat (inBrowserAgent)
    "</main>")))))))))))

(df homeView [] -> Str
  :d "Alias for render-home-view."
  (renderHomeView))
