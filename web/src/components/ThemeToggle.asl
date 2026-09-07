(module asl-web/theme-toggle
  :d "Declarative Theme Toggle Button Component in pure AgentScript"
  :x [describe-theme-toggle render-theme-toggle]
  :i [(core/strings :a s)])

(df describe-theme-toggle [] -> Str
  :d "Returns structured description of the theme toggle control"
  "(control :type \"theme-toggle\" :modes [\"dark\" \"light\"])")

(df render-theme-toggle [] -> Str
  :d "Renders the theme toggle button markup"
  "<button class=\"w-9 h-9 rounded-full border border-line text-ink-2 hover:text-ink transition-colors flex items-center justify-center\" aria-label=\"Switch Theme\"><svg class=\"w-4 h-4\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><circle cx=\"12\" cy=\"12\" r=\"5\"/><line x1=\"12\" y1=\"1\" x2=\"12\" y2=\"3\"/><line x1=\"12\" y1=\"21\" x2=\"12\" y2=\"23\"/></svg></button>")
