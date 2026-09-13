(module aslWeb/main
  :d "AgentScript Showcase Web Entrypoint in pure AgentScript"
  :x [mainInit main]
  :i [(App :a app)])

(df mainInit [] -> Str
  :d "Initializes the AgentScript showcase web application"
  "(app-mount :target \"#root\")")

(df main [] -> Str
  :d "Entry point alias"
  (mainInit))
