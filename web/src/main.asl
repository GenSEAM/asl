(module asl-web/main
  :d "AgentScript Showcase Web Entrypoint in pure AgentScript"
  :x [main-init main]
  :i [(App :a app)])

(df main-init [] -> Str
  :d "Initializes the AgentScript showcase web application"
  "(app-mount :target \"#root\")")

(df main [] -> Str
  :d "Entry point alias"
  (main-init))
