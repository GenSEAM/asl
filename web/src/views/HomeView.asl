(module aslWeb/homeView :x [homeView renderHomeView describeHomeView] :i [(asl-text/string :a s) (aslVdom/html :a h) (aslWeb/hero :a hero) (aslWeb/components/architecturePipeline :a arch) (aslWeb/ecosystem :a eco) (aslWeb/keyCapabilities :a kc) (aslWeb/theAgentWay :a taw) (aslWeb/agentWireProtocol :a awp) (aslWeb/harnessToolkit :a ht) (aslWeb/moduleGraphVisualizer :a mgv) (aslWeb/engineeringBlog :a eb) (aslWeb/inBrowserAgent :a iba)])

fn describeHomeView -> Str
  "(view :id \"home\" :components [\"hero\" \"architecture\" \"ecosystem\" \"capabilities\" \"agent-way\" \"wire-protocol\" \"harness\" \"module-graph\" \"blog\" \"in-browser-agent\"])"

fn renderHomeView -> Str
  (h/vnodeToHtml (h/main (h/attrsOf (list (h/attrId "main-content") (h/attrClass "flex-1 max-w-shell mx-auto w-full"))) (list (h/t (hero/hero)) (h/t (arch/renderArchitecture)) (h/t (eco/ecosystem)) (h/t (kc/keyCapabilities)) (h/t (taw/theAgentWay)) (h/t (awp/agentWireProtocol)) (h/t (ht/harnessToolkit)) (h/t (mgv/moduleGraphVisualizer)) (h/t (eb/engineeringBlog)) (h/t (iba/inBrowserAgent)))))

fn homeView -> Str
  (renderHomeView)
