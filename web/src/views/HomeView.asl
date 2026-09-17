(module aslWeb/homeView
  :d "Home landing page view composed entirely in pure AgentScript."
  :x [homeView renderHomeView describeHomeView]
  :i [(asl-text/string :a s)
      (aslVdom/html :a h)
      aslWeb/hero
      (aslWeb/components/architecturePipeline :a arch)
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
  "(view :id \"home\" :components [\"hero\" \"architecture\" \"ecosystem\" \"capabilities\" \"agent-way\" \"wire-protocol\" \"harness\" \"module-graph\" \"blog\" \"in-browser-agent\"])")

(df renderHomeView [] -> Str
  :d "Renders the full showcase home landing page."
  (h/vnodeToHtml
    (h/main (h/attrsOf (list (h/attrId "main-content") (h/attrClass "flex-1 max-w-shell mx-auto w-full")))
      (list
        (h/t (hero))
        (h/t (arch/renderArchitecture))
        (h/t (ecosystem))
        (h/t (keyCapabilities))
        (h/t (theAgentWay))
        (h/t (agentWireProtocol))
        (h/t (harnessToolkit))
        (h/t (moduleGraphVisualizer))
        (h/t (engineeringBlog))
        (h/t (inBrowserAgent))))))

(df homeView [] -> Str
  :d "Alias for render-home-view."
  (renderHomeView))
